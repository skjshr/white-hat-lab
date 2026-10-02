extends SceneTree

const ENGINE = preload("res://scripts/pentest_portal.gd")
const PASSWORDS := {"alice":"Alice-demo-27", "noah":"Noah-demo-27", "beth":"Beth-demo-27"}
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("invoice service timed out"); quit(2))
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		print("FAIL ", label)

func request(s: Dictionary, method: String, path: String, token: String = "", body: Variant = {}, headers: Dictionary = {}) -> Dictionary:
	return ENGINE.act(s, "request", {"method":method,"path":path,"session":token,"body":body,"headers":headers,"origin":"portal"})

func status(result: Dictionary) -> int:
	return int(result.get("response", {}).get("status", 0))

func data(result: Dictionary) -> Dictionary:
	var value: Variant = result.get("response", {}).get("data", {})
	return value if value is Dictionary else {}

func wire(result: Dictionary) -> String:
	return str(result.get("response", {}).get("body", ""))

func login(s: Dictionary, username: String) -> String:
	var result := request(s, "POST", "/api/auth/login", "", {"username":username,"password":PASSWORDS[username]})
	check(status(result) == 200, "login succeeds: " + username)
	var token := str(data(result).get("session", ""))
	check(not token.is_empty() and token != username, "issued session is opaque: " + username)
	return token

func draft(customer: String = "TEST Acme") -> Dictionary:
	return {"customer":customer,"issue_date":"2028-02-29","due_date":"2028-03-31","notes":"振込先は契約書に記載。","line_items":[{"description":"導入作業","quantity":2,"unit_price":1250},{"description":"保守","quantity":3,"unit_price":400}]}

func create_invoice(s: Dictionary, token: String, customer: String) -> Dictionary:
	var result := request(s, "POST", "/api/invoices", token, draft(customer))
	check(status(result) == 201, "create draft: " + customer)
	return data(result)

func detail(s: Dictionary, token: String, id: String) -> Dictionary:
	var result := request(s, "GET", "/api/invoices/" + id, token)
	check(status(result) == 200, "read invoice: " + id)
	return data(result)

func events(s: Dictionary, token: String, id: String) -> Array:
	var result := request(s, "GET", "/api/invoices/" + id + "/history", token)
	check(status(result) == 200 and data(result).get("events", null) is Array, "read business history: " + id)
	return data(result).get("events", [])

func business_snapshot(s: Dictionary, token: String, id: String) -> Dictionary:
	return {"detail":wire(request(s,"GET","/api/invoices/"+id,token)),"history":wire(request(s,"GET","/api/invoices/"+id+"/history",token))}

func rejected_edit(s: Dictionary, reader: String, actor: String, id: String, method: String, suffix: String, body: Dictionary, expected: int, label: String) -> void:
	var before := business_snapshot(s, reader, id)
	var result := request(s, method, "/api/invoices/" + id + suffix, actor, body)
	check(status(result) == expected, label + " rejects with HTTP " + str(expected))
	check(bool(result.get("ok", false)) and bool(result.get("changed", false)), label + " remains a recorded HTTP observation")
	check(business_snapshot(s, reader, id) == before, label + " preserves invoice and successful history")

func assert_summary(result: Dictionary, label: String) -> void:
	var payload := data(result)
	var rows: Array = payload.get("invoices", [])
	var total := 0; var drafts := 0; var approved := 0
	for row in rows:
		total += int(row.get("amount", 0))
		if str(row.get("state", "")) == "draft": drafts += 1
		if str(row.get("state", "")) == "approved": approved += 1
	var summary: Dictionary = payload.get("summary", {})
	check(status(result) == 200 and int(summary.get("count", -1)) == rows.size(), label + " count follows returned rows")
	check(int(summary.get("total", -1)) == total and int(summary.get("draft_count", -1)) == drafts and int(summary.get("approved_count", -1)) == approved, label + " totals follow actual invoices")

func test_authentication() -> void:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	var public: Dictionary = ENGINE.view(s)
	check(public.get("accounts", []).size() == 3, "only three authorized training accounts are listed")
	check(not public.has("invoices") and not public.has("jobs") and not public.has("model"), "initial public view does not disclose business resources")
	for account in public.get("accounts", []):
		var username := str(account.get("username", ""))
		check(PASSWORDS.has(username) and str(account.get("password", "")) == str(PASSWORDS.get(username, "missing")), "public directory supplies the stated fictional credentials")
		check(status(request(s,"GET","/api/invoices",str(account.get("session", "")))) == 401, "directory symbol is not an issued session")
	var wrong := request(s, "POST", "/api/auth/login", "", {"username":"alice","password":"wrong"})
	check(status(wrong) == 401 and not data(wrong).has("session") and not data(wrong).has("invoices"), "invalid password cannot disclose a session or invoices")
	for username in PASSWORDS:
		var token := login(s, username)
		var identity := request(s, "GET", "/api/auth/session", token)
		var user: Dictionary = data(identity).get("user", {})
		check(status(identity) == 200 and str(user.get("username", "")) == username, "session resolves to authenticated user")
		check(str(user.get("tenant", "")) == ("south" if username == "beth" else "north"), "session has the supplied tenant")
		check(str(user.get("role", "")) == ("employee" if username == "alice" else "reviewer"), "session has the supplied role")
		check(status(request(s,"POST","/api/auth/logout",token)) == 200, "logout succeeds")
		check(status(request(s,"GET","/api/auth/session",token)) == 401 and status(request(s,"GET","/api/invoices",token)) == 401, "logout revokes identity and business access")
		check(login(s, username) != token, "subsequent login issues a different session")

func test_business_lifecycle() -> void:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	var alice := login(s, "alice"); var noah := login(s, "noah"); var beth := login(s, "beth")
	var created := create_invoice(s, alice, "TEST Acme")
	var id := str(created.get("id", ""))
	if id.is_empty(): return
	check(str(created.get("tenant", "")) == "north" and str(created.get("owner", "")) == "alice" and str(created.get("state", "")) == "draft", "creation derives tenant, owner and state from the session")
	check(int(created.get("amount", 0)) == 3700 and int(created.get("version", 0)) > 0, "creation computes integer line total and version")
	check(created.get("line_items", []) == draft().line_items and str(created.get("issue_date", "")) == "2028-02-29", "line items and valid leap-day dates persist")
	var initial_events := events(s, alice, id)
	check(initial_events.size() == 1 and str(initial_events[0].get("action", "")) == "created" and str(initial_events[0].get("actor", "")) == "alice", "creation records one attributable business event")
	var version := int(created.get("version", 0))
	rejected_edit(s, alice, beth, id, "PATCH", "", {"version":version,"notes":"foreign edit"}, 403, "foreign tenant update")
	check(status(request(s,"GET","/api/invoices/"+id,beth)) == 403 and status(request(s,"GET","/api/invoices/"+id+"/history",beth)) == 403, "foreign tenant cannot read detail or history")
	var reviewer_draft := create_invoice(s, noah, "Reviewer owned")
	var reviewer_id := str(reviewer_draft.get("id", ""))
	if reviewer_id.is_empty(): return
	rejected_edit(s, noah, alice, reviewer_id, "PATCH", "", {"version":reviewer_draft.version,"notes":"not mine"}, 403, "employee editing another owner's draft")
	var edited := request(s,"PATCH","/api/invoices/"+id,alice,{"version":version,"customer":"TEST Revised","line_items":[{"description":"調査","quantity":4,"unit_price":900}]})
	check(status(edited) == 200 and int(data(edited).get("amount", 0)) == 3600, "owner edit recomputes amount")
	check(int(data(edited).get("version", 0)) == version + 1 and str(data(edited).get("notes", "")) == str(created.notes), "partial update increments version and preserves omitted fields")
	var updated := detail(s, alice, id)
	check(str(updated.get("customer", "")) == "TEST Revised", "fresh detail reflects saved edits")
	rejected_edit(s, alice, alice, id, "PATCH", "", {"version":version,"notes":"stale write"}, 409, "stale editor")
	rejected_edit(s, alice, alice, id, "POST", "/approve", {"version":updated.get("version",0)}, 403, "employee approval")
	var reviewed := request(s,"PATCH","/api/invoices/"+id,noah,{"version":updated.get("version",0),"notes":"Reviewed by Noah"})
	check(status(reviewed) == 200 and str(data(reviewed).get("owner", "")) == "alice", "reviewer edits tenant draft without taking ownership")
	var before_approval := detail(s, alice, id)
	var approved := request(s,"POST","/api/invoices/"+id+"/approve",noah,{"version":before_approval.get("version",0)})
	check(status(approved) == 200 and str(data(approved).get("state", "")) == "approved" and int(data(approved).get("version",0)) == int(before_approval.get("version",0)) + 1, "reviewer approval is a versioned transition")
	var after_approval := business_snapshot(s, alice, id)
	var duplicate := request(s,"POST","/api/invoices/"+id+"/approve",noah,{"version":data(approved).get("version",0)})
	check(status(duplicate) == 200 and business_snapshot(s, alice, id) == after_approval, "repeating current approval is idempotent")
	rejected_edit(s, alice, noah, id, "POST", "/approve", {"version":before_approval.get("version",0)}, 409, "stale approval")
	rejected_edit(s, alice, noah, id, "PATCH", "", {"version":data(approved).get("version",0),"notes":"after approval"}, 409, "approved invoice update")
	var history := events(s, alice, id)
	check(history.size() == 4, "only create, two accepted updates and approval enter business history")
	if history.size() == 4:
		check(history.map(func(event): return str(event.get("action", ""))) == ["created","updated","updated","approved"], "history identifies actual transitions in order")
		check(history.map(func(event): return str(event.get("actor", ""))) == ["alice","alice","noah","noah"], "history attributes changes to the actual principals")
		var previous_sequence := -1; var event_ids: Array = []
		for event in history:
			check(str(event.get("invoice_id", "")) == id and not str(event.get("actor_name", "")).is_empty() and int(event.get("sequence", -1)) > previous_sequence, "history events have invoice, actor and monotonic sequence")
			check(not str(event.get("id", "")).is_empty() and event.get("id") not in event_ids and not event.get("changes", {}).is_empty(), "history event ids are unique and include actual changes")
			event_ids.append(event.get("id")); previous_sequence = int(event.get("sequence", -1))
		check(JSON.stringify(history[1].get("changes", {})).contains("TEST Revised") and JSON.stringify(history[2].get("changes", {})).contains("Reviewed by Noah"), "change history contains values that were saved")
	var search := request(s,"GET","/api/invoices?q=tEsT%20rEvIsEd&state=approved",alice)
	assert_summary(search, "filtered list")
	check(data(search).get("invoices", []).size() == 1 and str(data(search).get("invoices", [{}])[0].get("id", "")) == id, "customer search is decoded and case insensitive with state filter")
	var by_id := request(s,"GET","/api/invoices?q="+id.to_lower(),alice)
	check(data(by_id).get("invoices", []).size() == 1 and str(data(by_id).get("invoices", [{}])[0].get("id", "")) == id, "ID search is case insensitive")
	var empty := request(s,"GET","/api/invoices?q=does-not-exist-123",alice)
	assert_summary(empty, "empty search")
	check(data(empty).get("invoices", []).is_empty(), "no search match returns an empty successful list")
	check(status(request(s,"GET","/api/invoices?state=invalid",alice)) == 400, "unknown list state is rejected")
	var south_list := request(s,"GET","/api/invoices",beth)
	check(data(south_list).get("invoices", []).all(func(row): return str(row.get("tenant", "")) == "south"), "list cannot cross tenant boundary")
	check(status(request(s,"DELETE","/api/invoices/"+id,noah)) == 405, "unsupported delete has no business shortcut")
	check(not ENGINE.checks(s).any(func(row): return bool(row.passed)), "ordinary business use does not solve the security engagement")

func test_validation_and_idempotency() -> void:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	var alice := login(s, "alice")
	var baseline_list := wire(request(s,"GET","/api/invoices",alice))
	var invalid: Array = [
		{"field":"customer","value":"  "}, {"field":"issue_date","value":"2027-02-29"},
		{"field":"issue_date","value":"2028-02-30"}, {"field":"due_date","value":"2028-02-28"},
		{"field":"due_date","value":"2028-13-01"}, {"field":"line_items","value":[]},
		{"field":"line_items","value":[{"description":" ","quantity":1,"unit_price":100}]},
		{"field":"line_items","value":[{"description":"x","quantity":1.5,"unit_price":100}]},
		{"field":"line_items","value":[{"description":"x","quantity":0,"unit_price":100}]},
		{"field":"line_items","value":[{"description":"x","quantity":1,"unit_price":-1}]},
		{"field":"line_items","value":[{"description":"x","quantity":1,"unit_price":0}]},
		{"field":"line_items","value":[{"description":"x","quantity":1,"unit_price":1.5}]},
		{"field":"line_items","value":[{"description":"x","quantity":"2","unit_price":100}]}
	]
	for invalid_input in invalid:
		var body := draft(); body[invalid_input.field] = invalid_input.value
		var rejected := request(s,"POST","/api/invoices",alice,body)
		check(status(rejected) == 422 and data(rejected).get("fields", {}).has(invalid_input.field), "validation identifies rejected field " + str(invalid_input))
		check(wire(request(s,"GET","/api/invoices",alice)) == baseline_list, "invalid draft does not create an invoice")
	for field in ["tenant","owner","state","amount"]:
		var body := draft(); body[field] = 1 if field == "amount" else "south"
		var rejected := request(s,"POST","/api/invoices",alice,body)
		check(status(rejected) == 422 and wire(request(s,"GET","/api/invoices",alice)) == baseline_list, "client cannot inject protected field " + field)
	var submitted := draft("Idempotent Acme")
	var first := request(s,"POST","/api/invoices",alice,submitted,{"Idempotency-Key":"invoice-form-1"})
	check(status(first) == 201, "first keyed submission creates an invoice")
	var id := str(data(first).get("id", ""))
	if id.is_empty(): return
	var once := wire(request(s,"GET","/api/invoices",alice))
	var second := request(s,"POST","/api/invoices",alice,submitted,{"idempotency-key":"invoice-form-1"})
	check(status(second) == 201 and wire(second) == wire(first), "double submission returns original payload")
	check(wire(request(s,"GET","/api/invoices",alice)) == once and events(s,alice,id).size() == 1, "double submission creates no duplicate row or event")
	var different := submitted.duplicate(true); different.customer = "Changed retry"
	check(status(request(s,"POST","/api/invoices",alice,different,{"idempotency-key":"invoice-form-1"})) == 409, "idempotency key cannot silently change submitted values")
	check(wire(request(s,"GET","/api/invoices",alice)) == once, "conflicting retry preserves business list")
	request(s,"POST","/api/auth/logout",alice)
	alice = login(s,"alice")
	var session_retry := request(s,"POST","/api/invoices",alice,submitted,{"idempotency-key":"invoice-form-1"})
	check(status(session_retry) == 201 and wire(session_retry) == wire(first), "new session of same principal preserves idempotency")
	var noah := login(s,"noah")
	var other_principal := request(s,"POST","/api/invoices",noah,submitted,{"idempotency-key":"invoice-form-1"})
	check(status(other_principal) == 201 and str(data(other_principal).get("id", "")) != id and str(data(other_principal).get("owner", "")) == "noah", "idempotency scope separates distinct principals")
	var existing := detail(s,alice,id)
	rejected_edit(s,alice,alice,id,"PATCH","",{"notes":"version missing"},422,"missing version")
	rejected_edit(s,alice,alice,id,"PATCH","",{"version":existing.version,"due_date":"2020-01-01"},422,"invalid partial update")
	for field in ["tenant","owner","state","amount"]:
		var body := {"version":existing.version}; body[field] = 1 if field == "amount" else "south"
		rejected_edit(s,alice,alice,id,"PATCH","",body,422,"protected update " + field)

func ready_job(s: Dictionary, token: String, id: String) -> Dictionary:
	var created := request(s,"POST","/api/exports",token,{"invoice_id":id})
	check(status(created) == 202, "export queues a snapshot")
	var job := data(created)
	if not job.has("status_url"): return {}
	request(s,"GET",str(job.status_url),token)
	check(status(request(s,"GET",str(job.status_url),token)) == 200, "export snapshot becomes ready")
	return job

func csv_rows(csv: String) -> Array:
	var rows: Array = []; var row: Array = []; var cell := ""; var quoted := false; var index := 0
	while index < csv.length():
		var character := csv[index]
		if character == "\"":
			if quoted and index + 1 < csv.length() and csv[index + 1] == "\"": cell += "\""; index += 1
			else: quoted = not quoted
		elif character == "," and not quoted: row.append(cell); cell = ""
		elif character == "\n" and not quoted: row.append(cell.trim_suffix("\r")); rows.append(row); row = []; cell = ""
		else: cell += character
		index += 1
	if not cell.is_empty() or not row.is_empty(): row.append(cell); rows.append(row)
	check(not quoted, "CSV quote structure closes")
	return rows

func assert_csv(response: Dictionary, invoice_id: String, customer: String, amount: int) -> void:
	check(status(response) == 200 and str(response.get("response", {}).get("content_type", "")) == "text/csv", "download exposes a CSV response")
	var rows := csv_rows(wire(response))
	check(rows.size() == 2 and rows[0].size() == rows[1].size(), "CSV escaping preserves exactly one data row")
	if rows.size() != 2: return
	for field in ["invoice_id","customer","amount"]:
		var column: int = rows[0].find(field)
		check(column >= 0, "CSV contains column " + field)
		if column < 0 or column >= rows[1].size(): continue
		var expected := invoice_id if field == "invoice_id" else customer if field == "customer" else str(amount)
		check(str(rows[1][column]) == expected, "CSV roundtrips the actual " + field)

func test_exports_and_save() -> void:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	var alice := login(s,"alice")
	var customer := "ACME, \"北支店\"\n会計"
	var created := create_invoice(s,alice,customer)
	var id := str(created.get("id", ""))
	if id.is_empty(): return
	var first_job := ready_job(s,alice,id)
	if first_job.is_empty(): return
	var first_file := request(s,"GET",str(first_job.download_url),alice)
	assert_csv(first_file,id,customer,3700)
	var edited := request(s,"PATCH","/api/invoices/"+id,alice,{"version":created.version,"customer":"Changed customer","line_items":[{"description":"現地対応","quantity":5,"unit_price":800}]})
	check(status(edited) == 200, "edit invoice after first snapshot")
	check(wire(request(s,"GET",str(first_job.download_url),alice)) == wire(first_file), "previous export bytes do not change after invoice edit")
	var second_job := ready_job(s,alice,id)
	if second_job.is_empty(): return
	check(str(second_job.job_id) != str(first_job.job_id), "new export has its own snapshot identity")
	assert_csv(request(s,"GET",str(second_job.download_url),alice),id,"Changed customer",4000)
	var saved_business := business_snapshot(s,alice,id)
	var saved_list := wire(request(s,"GET","/api/invoices",alice))
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(s))
	check(status(request(resumed,"GET","/api/auth/session",alice)) == 200, "issued session survives JSON save roundtrip")
	var resumed_business := business_snapshot(resumed,alice,id)
	check(resumed_business.detail == saved_business.detail, "saved invoice detail and numeric wire bytes remain stable")
	check(resumed_business.history == saved_business.history, "saved business history wire bytes remain stable")
	check(wire(request(resumed,"GET","/api/invoices",alice)) == saved_list, "saved invoice list order and wire bytes remain stable")
	check(wire(request(resumed,"GET",str(first_job.download_url),alice)) == wire(first_file), "immutable export snapshot survives JSON save")
	var continued := request(resumed,"PATCH","/api/invoices/"+id,alice,{"version":data(edited).get("version",0),"notes":"After resume"})
	check(status(continued) == 200 and int(data(continued).get("version",0)) == int(data(edited).get("version",0)) + 1, "restored draft remains editable with correct version")

func pin(s: Dictionary, observed: Dictionary) -> void:
	check(bool(ENGINE.act(s,"pin",{"id":str(observed.get("request_id", ""))}).get("ok",false)), "preserve an actual exchange")

func replay(s: Dictionary, id: String, token: String) -> Dictionary:
	var args: Dictionary = s.evidence[id].request.duplicate(true)
	args.session = token; args.origin = "replay"; args.replay_of = id
	return ENGINE.act(s,"request",args)

func test_report_after_reauthentication() -> void:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	var alice := login(s,"alice"); var beth := login(s,"beth")
	var north := data(request(s,"GET","/api/invoices",alice)).get("invoices", []) as Array
	var south := data(request(s,"GET","/api/invoices",beth)).get("invoices", []) as Array
	check(not north.is_empty() and not south.is_empty(), "test principals can observe their own resources")
	if north.is_empty() or south.is_empty(): return
	var job := ready_job(s,beth,str(south[0].id))
	if job.is_empty(): return
	var normal := request(s,"GET","/api/invoices/"+str(north[0].id),alice)
	var attack := request(s,"GET",str(job.download_url),alice)
	check(status(normal) == 200 and status(attack) == 200, "existing cross-tenant export defect remains observable")
	pin(s,normal); pin(s,attack)
	var original_ids := [str(normal.request_id),str(attack.request_id)]
	var original_evidence := JSON.stringify(JSON.parse_string(JSON.stringify(s.evidence)))
	check(status(request(s,"POST","/api/auth/logout",alice)) == 200, "logout revokes observed session before report submission")
	s = JSON.parse_string(JSON.stringify(s))
	var submitted: Dictionary = ENGINE.act(s,"submit_report",{"claim":ENGINE.CLAIM,"evidence_ids":original_ids,"narrative":"認証された同じ担当者で通常閲覧と他組織のCSV取得を比較した。"})
	check(bool(submitted.get("ok",false)), "preserved evidence remains interpretable after logout and reload")
	check(bool(ENGINE.act(s,"customer_fix").get("ok",false)), "accepted evidence enables the customer fix")
	var revoked := replay(s,str(attack.request_id),alice)
	check(status(revoked) == 401, "old evidence token stays revoked for new requests")
	pin(s,revoked)
	check(not bool(ENGINE.checks(s)[1].passed), "unauthenticated replay is not a security retest")
	var noah := login(s,"noah")
	var different_attack := replay(s,str(attack.request_id),noah)
	var different_normal := replay(s,str(normal.request_id),noah)
	check(status(different_attack) == 403 and status(different_normal) == 200, "other north principal can observe same statuses")
	pin(s,different_attack); pin(s,different_normal)
	check(not bool(ENGINE.checks(s)[1].passed) and not bool(ENGINE.checks(s)[2].passed), "different principal cannot satisfy original request retests")
	var new_alice := login(s,"alice")
	check(new_alice != alice, "retest uses a genuinely newly issued token")
	for changed_field in ["body", "headers"]:
		var changed_request: Dictionary = s.evidence[attack.request_id].request.duplicate(true)
		changed_request.session = new_alice; changed_request.replay_of = str(attack.request_id)
		changed_request[changed_field] = {"x-test-condition":"changed"}
		var changed_observation: Dictionary = ENGINE.act(s,"request",changed_request)
		check(status(changed_observation) == 403, "changed " + changed_field + " can observe a rejection")
		pin(s,changed_observation)
		check(not bool(ENGINE.checks(s)[1].passed), "new-session retest still requires identical " + changed_field)
	var blocked := replay(s,str(attack.request_id),new_alice)
	var regression := replay(s,str(normal.request_id),new_alice)
	check(status(blocked) == 403 and status(regression) == 200, "same principal with new token observes fixed attack and working business")
	pin(s,blocked); pin(s,regression)
	check(ENGINE.checks(s).all(func(row): return bool(row.passed)), "same-principal retests complete the existing report")
	var originals: Dictionary = {}
	for id in original_ids: originals[id] = s.evidence[id]
	check(JSON.stringify(originals) == original_evidence, "session changes and report do not rewrite preserved original exchanges")
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(s))
	check(ENGINE.checks(resumed).all(func(row): return bool(row.passed)), "completed reauthenticated report survives save roundtrip")

func test_legacy_save_migration() -> void:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	# Recreate the persisted pre-login schema, including an old HTTP exchange.
	for key in ["auth_version","sessions","session_counter","invoice_history","invoice_counter","event_counter","business_idempotency"]:
		s.model.erase(key)
	for invoice in s.model.invoices.values():
		for key in ["version","updated_sequence","issue_date","due_date","notes","line_items"]: invoice.erase(key)
	var old_invoice: Dictionary = s.model.invoices["INV-N204"].duplicate(true)
	var old_body := JSON.stringify(old_invoice)
	var old_record := {"id":"http-1","sequence":1,"phase":"investigation","request":{"method":"GET","path":"/api/invoices/INV-N204","session":"alice","body":{},"headers":{},"origin":"portal","replay_of":""},"response":{"status":200,"data":old_invoice,"body":old_body,"content_type":"application/json","headers":{"content-type":"application/json"}}}
	s.history = [old_record]; s.request_sequence = 1
	check(bool(ENGINE.act(s,"pin",{"id":"http-1"}).get("ok",false)), "legacy HTTP record can remain preserved")
	var before_view := JSON.stringify(s)
	ENGINE.view(s)
	check(JSON.stringify(s) == before_view, "viewing old save does not perform a hidden migration")
	s = JSON.parse_string(JSON.stringify(s))
	var original := JSON.stringify(s.evidence["http-1"])
	var migrated := request(s,"GET","/api/invoices/INV-N204","alice")
	check(status(migrated) == 200 and s.model.has("auth_version") and s.model.has("sessions"), "first operation explicitly migrates legacy sessions")
	check(data(migrated).has("line_items") and int(data(migrated).get("version",0)) > 0, "legacy invoice gains editable business fields")
	check(JSON.stringify(s.evidence["http-1"]) == original and str(s.history[0].response.body) == old_body, "migration preserves old evidence and exact recorded response bytes")
	var job := ready_job(s,"beth","INV-S108")
	if job.is_empty(): return
	var attack := request(s,"GET",str(job.download_url),"alice")
	check(status(attack) == 200, "legacy account can still investigate the existing export defect")
	pin(s,attack)
	var changed := request(s,"PATCH","/api/invoices/INV-N204","alice",{"version":data(migrated).get("version",0),"customer":"Updated after historical observation","line_items":[{"description":"追加作業","quantity":3,"unit_price":700}]})
	check(status(changed) == 200 and int(data(changed).get("amount",0)) == 2100, "migrated old invoice supports a legitimate later update")
	var submitted: Dictionary = ENGINE.act(s,"submit_report",{"claim":ENGINE.CLAIM,"evidence_ids":["http-1",str(attack.request_id)],"narrative":"保存済みの正常応答と組織をまたいだCSV応答を比較した。"})
	check(bool(submitted.get("ok",false)), "historical baseline remains valid after legitimate invoice values change")
	check(status(request(s,"POST","/api/auth/logout","alice")) == 200 and status(request(s,"GET","/api/invoices","alice")) == 401, "logout revokes the migrated legacy token")
	var token := login(s,"alice")
	check(bool(ENGINE.act(s,"customer_fix").get("ok",false)), "legacy evidence still enables the customer fix")
	var blocked := replay(s,str(attack.request_id),token)
	var regression := replay(s,"http-1",token)
	check(status(blocked) == 403 and status(regression) == 200 and int(data(regression).get("amount",0)) == 2100, "new session retests fixed access and the current legitimate invoice")
	pin(s,blocked); pin(s,regression)
	check(ENGINE.checks(s).all(func(row): return bool(row.passed)), "old report lifecycle completes with new opaque session")
	check(JSON.stringify(s.evidence["http-1"]) == original and str(s.evidence["http-1"].response.body) == old_body, "legacy report and retest never rewrite historical evidence")

func run() -> void:
	test_authentication()
	test_business_lifecycle()
	test_validation_and_idempotency()
	test_exports_and_save()
	test_report_after_reauthentication()
	test_legacy_save_migration()
	print("INVOICE_SERVICE_PASS assertions=" + str(assertions) if failures.is_empty() else "INVOICE_SERVICE_FAIL count=" + str(failures.size()) + " assertions=" + str(assertions))
	quit(0 if failures.is_empty() else 1)
