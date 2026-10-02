extends SceneTree

const ENGINE = preload("res://scripts/pentest_portal.gd")
const EDITABLE := ["customer","issue_date","due_date","notes","line_items"]
const PASSWORDS := {"alice":"Alice-demo-27","noah":"Noah-demo-27","beth":"Beth-demo-27"}
var failures: Array[String] = []
var assertions := 0
var serial := 0

func _init() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("INCIDENT_RESPONSE_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ",label)

func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func source(s: Dictionary) -> String:
	var snapshot := s.duplicate(true); snapshot.erase("exercise")
	return canonical(snapshot)

func payload(result: Dictionary) -> Dictionary:
	return result.get("response",{}).get("data",{})

func status(result: Dictionary) -> int:
	return int(result.get("response",{}).get("status",0))

func act(s: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	var before := source(s)
	var result: Dictionary = ENGINE.act(s,action,args)
	check(bool(result.get("exercise_only",false)) and float(result.get("minutes",-1)) == 0, action+" stays in exercise transaction")
	check(source(s) == before, action+" preserves original model, evidence, records and case revision")
	return result

func op(s: Dictionary, operation: String, args: Dictionary = {}, key: String = "") -> Dictionary:
	var request := args.duplicate(true)
	request.run_id = str(s.get("exercise",{}).get("run_id","")); request.op = operation
	if not key.is_empty(): request.command_id = key
	return act(s,"incident_action",request)

func mutation(s: Dictionary, operation: String, args: Dictionary = {}) -> Dictionary:
	serial += 1
	return op(s,operation,args,"test-command-"+str(serial))

func request(s: Dictionary, method: String, path: String, token: String = "", body: Dictionary = {}) -> Dictionary:
	return act(s,"request",{"method":method,"path":path,"session":token,"body":body,"headers":{}})

func login(s: Dictionary, username: String) -> String:
	var result := request(s,"POST","/api/auth/login","",{"username":username,"password":PASSWORDS[username]})
	check(status(result) == 200,"branch login uses real service")
	return str(payload(result).get("session",""))

func start(variant := "mixed", seed_value := 23) -> Dictionary:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	# Give the normal case real evidence before copying it into the exercise.
	var normal_login: Dictionary = ENGINE.act(s,"request",{"method":"POST","path":"/api/auth/login","body":{"username":"alice","password":PASSWORDS.alice}})
	var normal: Dictionary = ENGINE.act(s,"request",{"method":"GET","path":"/api/invoices","session":str(payload(normal_login).get("session",""))})
	ENGINE.act(s,"pin",{"id":str(normal.get("request_id",""))})
	var result := act(s,"incident_start",{"variant":variant,"seed":seed_value})
	check(bool(result.get("ok",false)) and status(result) == 200,"explicit exercise start succeeds")
	check(bool(s.get("exercise",{}).get("active",false)) and not str(s.get("exercise",{}).get("run_id","")).is_empty(),"exercise has an active distinct run")
	return s

func audit(s: Dictionary) -> Array:
	var result := op(s,"audit")
	check(status(result) == 200,"audit observation succeeds")
	return payload(result).get("events",[])

func sessions(s: Dictionary) -> Array:
	var result := op(s,"sessions")
	check(status(result) == 200,"session observation succeeds")
	return payload(result).get("sessions",[])

func pin_events(s: Dictionary) -> void:
	for event in audit(s):
		check(bool(op(s,"pin_event",{"event_id":str(event.get("id",""))}).get("ok",false)),"preserve actual incident event")

func branch_invoice(s: Dictionary, id: String) -> Dictionary:
	return s.get("exercise",{}).get("branch",{}).get("model",{}).get("invoices",{}).get(id,{})

func observed_anomaly(s: Dictionary, variant: String) -> Dictionary:
	for event in audit(s):
		if int(event.get("status",0)) != 200: continue
		if variant == "mixed" and str(event.get("method","")) == "PATCH": return event
		if variant == "exfil" and str(event.get("path","")).ends_with("/file"): return event
	check(false,"start contains a real "+variant+" anomaly")
	return {}

func no_answers(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key) in ["malicious","attacker","attacker_id","attack_session","correct_action","safe_version"]: return false
			if not no_answers(value[key]): return false
	elif value is Array:
		for item in value:
			if not no_answers(item): return false
	return true

func test_observation_and_replay() -> void:
	var s := start()
	if not s.has("exercise"): return
	var original := source(s)
	var anomaly := observed_anomaly(s,"mixed")
	if anomaly.is_empty(): return
	var start_tick := int(s.exercise.tick)
	var before_view := canonical(s)
	for _index in 8: ENGINE.view(s)
	check(canonical(s) == before_view,"repeated rendering is entirely read only")
	var public: Dictionary = ENGINE.view(s).get("exercise",{})
	check(no_answers(public),"public observations contain no hidden attacker or correct-answer keys")
	check(not public.get("context",{}).get("work_orders",[]).is_empty(),"independent authorized customer work is publicly observable")
	var serialized_view := JSON.stringify(ENGINE.view(s))
	# Test oracle inspects issued actor tokens only to detect accidental disclosure.
	for actor_token in s.exercise.get("sessions",{}):
		check(not serialized_view.contains(str(actor_token)),"public portal/workbench does not reveal an actor bearer token")
	check(sessions(s).all(func(row): return not row.has("token")),"session inventory exposes audit identifiers rather than bearer tokens")
	for _index in 3: audit(s); sessions(s); op(s,"versions",{"invoice_id":str(anomaly.invoice_id)})
	check(int(s.exercise.tick) == start_tick,"audit/session/version reads do not advance time")
	var pinned := op(s,"pin_event",{"event_id":str(anomaly.id)})
	check(bool(pinned.get("ok",false)) and int(s.exercise.tick) == start_tick,"event evidence does not advance time")
	var run_id := str(s.exercise.run_id)
	var duplicate_start := act(s,"incident_start",{"variant":"exfil","seed":99})
	check(not bool(duplicate_start.get("ok",true)) and str(s.exercise.run_id) == run_id,"unfinished run cannot be silently replaced")
	var stale := act(s,"incident_action",{"run_id":"stale-run","op":"advance","command_id":"stale"})
	check(not bool(stale.get("ok",true)) and int(s.exercise.tick) == start_tick,"stale run commands cannot affect current incident")
	var pause_args := {"paused":true}
	var pause := op(s,"set_export_paused",pause_args,"pause-once")
	check(status(pause) == 200 and int(s.exercise.tick) == start_tick + 1,"effective containment advances exactly one tick")
	var after_pause := canonical(s.exercise)
	var duplicate := op(s,"set_export_paused",pause_args,"pause-once")
	check(bool(duplicate.get("duplicate",false)) and not bool(duplicate.get("changed",true)) and canonical(s.exercise) == after_pause,"duplicate command has no extra tick, actor action or outcome")
	check(status(op(s,"set_export_paused",{"paused":false},"pause-once")) == 409 and canonical(s.exercise) == after_pause,"same command ID cannot change its arguments")
	var token := login(s,"alice")
	var listed := request(s,"GET","/api/invoices",token)
	check(status(listed) == 200,"export pause preserves ordinary reads")
	var rows: Array = payload(listed).get("invoices",[])
	if not rows.is_empty():
		var paused_export := request(s,"POST","/api/exports",token,{"invoice_id":str(rows[0].id)})
		check(status(paused_export) >= 400,"export pause actually rejects export creation")
	var probe := mutation(s,"business_probe")
	check(not bool(payload(probe).get("passed",true)),"real business probe detects paused exports")
	check(payload(probe).get("steps",[]).any(func(step): return str(step.get("path","")).begins_with("/api/exports") and int(step.get("status",0)) >= 400),"availability failure comes from a real export response")
	check(status(mutation(s,"set_export_paused",{"paused":false})) == 200,"export service can be reopened")
	var recovered := mutation(s,"business_probe")
	check(bool(payload(recovered).get("passed",false)),"reopening exports restores real legitimate service")
	check(payload(recovered).get("steps",[]).any(func(step): return str(step.get("path","")).ends_with("/file") and int(step.get("status",0)) == 200),"recovery includes an actual CSV download")
	var before_reads := int(s.exercise.tick)
	for _index in 110: request(s,"GET","/api/invoices",token)
	check(int(s.exercise.tick) == before_reads,"routine reads cannot progress the incident")
	check(audit(s).any(func(event): return str(event.id) == str(anomaly.id)),"initial evidence survives normal 96-record HTTP history turnover")
	var versions := payload(op(s,"versions",{"invoice_id":str(anomaly.invoice_id)})).get("versions",[]) as Array
	check(not versions.is_empty(),"recovery versions outlive normal HTTP history turnover")
	check(source(s) == original,"all exercise traffic leaves original case and evidence unchanged")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s))
	check(canonical(saved.exercise) == canonical(s.exercise),"events, versions and branch service survive JSON roundtrip")
	var leave_tick := int(saved.exercise.tick)
	check(bool(act(saved,"incident_leave").get("ok",false)) and not bool(saved.exercise.active),"leave pauses the run")
	var normal_state := saved.duplicate(true); normal_state.erase("exercise")
	check(canonical(ENGINE.view(saved).get("history",[])) == canonical(ENGINE.view(normal_state).get("history",[])),"leaving returns to original communications")
	check(bool(act(saved,"incident_resume").get("ok",false)) and int(saved.exercise.tick) == leave_tick and str(saved.exercise.run_id) == run_id,"resume keeps the same run and tick")

func test_mixed_recovery() -> void:
	var s := start("mixed",31)
	if not s.has("exercise"): return
	var anomaly := observed_anomaly(s,"mixed")
	if anomaly.is_empty(): return
	var id := str(anomaly.invoice_id); var suspect := str(anomaly.session_id)
	var versions: Array = payload(op(s,"versions",{"invoice_id":id})).get("versions",[])
	check(versions.size() >= 2,"real alteration preserves before and after invoice versions")
	if versions.size() < 2: return
	versions.sort_custom(func(a,b): return int(a.version) < int(b.version))
	var baseline: Dictionary = versions[0]
	var initial_changed: Array = []
	for field in EDITABLE:
		if canonical(baseline.get("fields",{}).get(field)) != canonical(branch_invoice(s,id).get(field)): initial_changed.append(field)
	check(not initial_changed.is_empty(),"initial PATCH actually changes editable business data")
	var same_user_other := ""
	for session in sessions(s):
		if str(session.get("principal","")) == str(anomaly.get("principal","")) and str(session.get("session_id","")) != suspect and not bool(session.get("revoked",false)):
			same_user_other = str(session.session_id); break
	check(not same_user_other.is_empty(),"same principal has a distinct legitimate session")
	if same_user_other.is_empty(): return
	check(status(mutation(s,"revoke_session",{"session_id":same_user_other})) == 200,"operator can make a wrong but causal revocation")
	mutation(s,"business_probe")
	check(sessions(s).any(func(row): return str(row.session_id) == same_user_other and bool(row.revoked)),"legitimate recovery never revives a revoked token")
	var after_wrong: Array = audit(s)
	check(after_wrong.any(func(event): return str(event.get("session_id","")) == same_user_other and int(event.get("status",0)) == 401),"wrong revocation produces actual failed legitimate requests")
	check(status(mutation(s,"revoke_session",{"session_id":suspect})) == 200,"observed suspicious token is revoked")
	for _index in 5: mutation(s,"advance")
	check(audit(s).any(func(event): return str(event.get("session_id","")) == suspect and int(event.get("status",0)) == 401),"later actor requests really fail with revoked authentication")
	var current := branch_invoice(s,id).duplicate(true)
	check(str(current.get("notes","")) != str(baseline.get("fields",{}).get("notes","")),"unrelated legitimate later edit exists to preserve")
	var notes := str(current.get("notes",""))
	var full_rollback: Dictionary = JSON.parse_string(JSON.stringify(s))
	var overwritten := mutation(full_rollback,"restore_version",{"invoice_id":id,"source_version":int(baseline.version),"expected_version":int(current.version),"fields":EDITABLE})
	check(status(overwritten) == 200 and str(branch_invoice(full_rollback,id).get("notes","")) != notes,"full-object rollback really discards the legitimate later note")
	var rollback_assessment := payload(op(full_rollback,"assess"))
	check(rollback_assessment.get("checks",[]).any(func(row): return str(row.get("id","")) == "integrity" and not bool(row.get("passed",true))),"assessment recognizes damage caused by overbroad restoration")
	var branch_before := canonical(s.exercise.branch)
	var stale_restore := mutation(s,"restore_version",{"invoice_id":id,"source_version":int(baseline.version),"expected_version":int(current.version)-1,"fields":initial_changed})
	check(status(stale_restore) == 409 and canonical(s.exercise.branch) == branch_before,"stale restoration does not overwrite a newer invoice")
	var restored := op(s,"restore_version",{"invoice_id":id,"source_version":int(baseline.version),"expected_version":int(current.version),"fields":initial_changed},"restore-once")
	check(status(restored) == 200,"selected-field restoration succeeds")
	var final_invoice := branch_invoice(s,id)
	check(int(final_invoice.get("version",0)) == int(current.version)+1,"restoration creates a new invoice version")
	for field in initial_changed: check(canonical(final_invoice.get(field)) == canonical(baseline.fields.get(field)),"restoration repairs selected field "+str(field))
	check(str(final_invoice.get("notes","")) == notes,"partial restoration preserves legitimate later notes")
	if "line_items" in initial_changed: check(int(final_invoice.get("amount",0)) == int(baseline.fields.get("amount",-1)),"restoration recomputes invoice total")
	var after_restore := canonical(s.exercise)
	var repeat := op(s,"restore_version",{"invoice_id":id,"source_version":int(baseline.version),"expected_version":int(current.version),"fields":initial_changed},"restore-once")
	check(bool(repeat.get("duplicate",false)) and canonical(s.exercise) == after_restore,"repeated restoration cannot add a version or tick")
	check(bool(payload(mutation(s,"business_probe")).get("passed",false)),"legitimate service works after targeted response")
	pin_events(s)
	var assessment := payload(op(s,"assess"))
	check(bool(assessment.get("complete",false)),"containment, selected-field repair, real service and evidence produce a complete response")
	if not bool(assessment.get("complete",false)): print("INCIDENT_ASSESS_DIAGNOSTIC ",JSON.stringify(assessment))
	var metrics_before: Dictionary = assessment.get("metrics",{}).duplicate(true)
	var result := mutation(s,"finish")
	check(status(result) == 200 and str(s.exercise.phase) == "concluded" and payload(result).has("debrief"),"finish produces concrete measured debrief")
	for metric in metrics_before:
		check(canonical(payload(result).get("metrics",{}).get(metric)) == canonical(metrics_before[metric]),"finish preserves observed metric "+str(metric))
	check(payload(result).get("metrics",{}).has("remaining_damage") and payload(result).get("metrics",{}).has("legitimate_failures"),"conclusion adds explicit damage and legitimate disruption accounting")

func condition_signature(s: Dictionary) -> Dictionary:
	var rows: Array = []
	for session in sessions(s):
		rows.append({"principal":session.get("principal"),"device":session.get("device"),"source":session.get("source"),"created_tick":session.get("created_tick")})
	rows.sort_custom(func(a,b): return JSON.stringify(a) < JSON.stringify(b))
	var activity: Array = []
	for event in audit(s):
		var path := str(event.get("path",""))
		if path.begins_with("/api/exports/"): path = "/api/exports/<job>" + ("/file" if path.ends_with("/file") else "")
		activity.append({"tick":event.get("tick"),"principal":event.get("principal"),"method":event.get("method"),"path":path,"status":event.get("status"),"invoice_id":event.get("invoice_id"),"device":event.get("device"),"source":event.get("source")})
	return {"sessions":rows,"events":activity}

func passed_check(assessment: Dictionary, id: String) -> bool:
	return assessment.get("checks",[]).any(func(row): return str(row.get("id","")) == id and bool(row.get("passed",false)))

func test_evidence_freshness_and_final_tick() -> void:
	var s := start("mixed",23)
	var anomaly := observed_anomaly(s,"mixed")
	if anomaly.is_empty(): return
	var id := str(anomaly.invoice_id)
	var versions: Array = payload(op(s,"versions",{"invoice_id":id})).get("versions",[])
	versions.sort_custom(func(a,b): return int(a.version) < int(b.version))
	if versions.is_empty(): return
	# Allow the real suspicious CSV transfer, then contain it using its public session ID.
	for _index in 4: mutation(s,"advance")
	mutation(s,"revoke_session",{"session_id":str(anomaly.session_id)})
	for _index in 2: mutation(s,"advance")
	var note: Dictionary = {}; var transfer: Dictionary = {}; var rejected: Dictionary = {}
	for event in audit(s):
		if str(event.get("path","")) == "作業依頼 order-2": note = event
		if str(event.get("session_id","")) != str(anomaly.session_id): continue
		if str(event.get("path","")).ends_with("/file") and int(event.get("status",0)) == 200: transfer = event
		if int(event.get("status",0)) == 401: rejected = event
	check(not note.is_empty() and not transfer.is_empty() and not rejected.is_empty(),"public CSV authorization, successful transfer and rejected follow-up all exist")
	if note.is_empty() or transfer.is_empty() or rejected.is_empty(): return
	op(s,"pin_event",{"event_id":str(note.id)}); op(s,"pin_event",{"event_id":str(rejected.id)})
	check(not passed_check(payload(op(s,"assess")),"evidence"),"customer context plus only a failed request cannot prove a prior successful deviation")
	op(s,"unpin_event",{"event_id":str(rejected.id)}); op(s,"pin_event",{"event_id":str(transfer.id)})
	check(passed_check(payload(op(s,"assess")),"evidence"),"mixed incident accepts actual CSV disclosure plus the relevant export work order")
	check(bool(payload(mutation(s,"business_probe")).get("passed",false)),"business probe succeeds before direct HTTP repair")
	check(passed_check(payload(op(s,"assess")),"business"),"successful current probe counts toward business recovery")
	var token := login(s,str(anomaly.principal))
	var current := branch_invoice(s,id).duplicate(true)
	var repaired := request(s,"PATCH","/api/invoices/"+id,token,{"version":int(current.version),"line_items":versions[0].fields.line_items.duplicate(true)})
	check(status(repaired) == 200,"ordinary HTTP PATCH can repair the altered line items")
	check(str(branch_invoice(s,id).notes) == str(current.notes),"ordinary partial PATCH retains legitimate later notes")
	var after_http := payload(op(s,"assess"))
	check(passed_check(after_http,"integrity") and not passed_check(after_http,"business"),"successful HTTP repair invalidates an older business probe")
	while int(s.exercise.tick) < 47 and str(s.exercise.phase) == "running": mutation(s,"advance")
	check(int(s.exercise.tick) == 47 and str(s.exercise.phase) == "running","explicit actions reach the last available response tick")
	var final_probe := mutation(s,"business_probe")
	check(bool(payload(final_probe).get("passed",false)) and int(s.exercise.tick) == 48 and str(s.exercise.phase) == "concluded","successful probe on final tick triggers bounded conclusion")
	check(passed_check(s.exercise.get("result",{}),"business") and bool(s.exercise.get("result",{}).get("complete",false)),"automatic conclusion includes the final-tick probe result")
	var finished := canonical(s.exercise)
	check(not bool(mutation(s,"advance").get("changed",true)) and canonical(s.exercise) == finished,"concluded run rejects later tick mutations")

func test_source_limits() -> void:
	# Saturated saved cases are valid source fixtures, not an excuse to mutate the original.
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	var normal_login: Dictionary = ENGINE.act(s,"request",{"method":"POST","path":"/api/auth/login","body":{"username":"noah","password":PASSWORDS.noah}})
	var token := str(payload(normal_login).get("session",""))
	var created: Dictionary = ENGINE.act(s,"request",{"method":"POST","path":"/api/exports","session":token,"body":{"invoice_id":"INV-N204"}})
	check(status(created) == 202,"source saturation fixture starts from a real export job")
	var template: Dictionary = s.model.invoices["INV-N204"].duplicate(true)
	for invoice in s.model.invoices.values(): invoice.state = "approved"
	while s.model.invoices.size() < 256:
		var id := "INV-LIMIT-%03d" % s.model.invoices.size()
		var invoice := template.duplicate(true); invoice.id = id; invoice.state = "approved"; s.model.invoices[id] = invoice
	while s.model.sessions.size() < 512: s.model.sessions["source-session-%03d" % s.model.sessions.size()] = {"username":"noah","revoked":false,"legacy":false}
	if s.model.jobs.is_empty(): return
	var job: Dictionary = s.model.jobs.values()[0].duplicate(true)
	while s.model.jobs.size() < 64:
		var id := "source-job-%03d" % s.model.jobs.size()
		var copy := job.duplicate(true); copy.id = id; s.model.jobs[id] = copy
	var normal_capacity: Dictionary = ENGINE.act(s,"request",{"method":"POST","path":"/api/auth/login","body":{"username":"noah","password":PASSWORDS.noah}})
	check(status(normal_capacity) == 429,"source session capacity is genuinely exhausted")
	var normal_export_capacity: Dictionary = ENGINE.act(s,"request",{"method":"POST","path":"/api/exports","session":token,"body":{"invoice_id":"INV-N204"}})
	check(status(normal_export_capacity) == 429 and s.model.jobs.size() == 64,"ordinary service keeps its 64-job export limit")
	var original := source(s)
	var started := act(s,"incident_start",{"variant":"mixed","seed":51})
	check(status(started) == 200 and bool(started.get("ok",false)),"all-approved full invoice/session/job source can start a causal exercise")
	if not s.has("exercise"): return
	check(not observed_anomaly(s,"mixed").is_empty(),"full source still produces an actual successful invoice alteration")
	check(bool(payload(mutation(s,"business_probe")).get("passed",false)),"exercise independently provisions enough capacity for real business recovery")
	check(source(s) == original and s.model.invoices.size() == 256 and s.model.sessions.size() == 512 and s.model.jobs.size() == 64,"fresh exercise resources preserve all saturated source resources")
	var extreme: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	for invoice in extreme.model.invoices.values():
		invoice.notes = "既存".repeat(1000)
		invoice.amount = 999999999
		invoice.line_items = [{"description":"入力上限の既存請求","quantity":1,"unit_price":999999999}]
	var extreme_before := source(extreme)
	check(status(act(extreme,"incident_start",{"variant":"mixed","seed":23})) == 200,"maximum legal amount and notes permit a real attack variant")
	if not extreme.has("exercise"): return
	var changed := observed_anomaly(extreme,"mixed")
	if changed.is_empty(): return
	mutation(extreme,"advance")
	var current := branch_invoice(extreme,str(changed.invoice_id))
	check(str(current.notes) == "既存".repeat(1000),"scheduled legitimate work retains full source notes at the input limit")
	check(int(current.amount) < 999999999 and int(current.amount) > 0,"upper-limit scenario uses a valid real amount change")
	check(source(extreme) == extreme_before,"upper-limit source invoice and original notes remain unchanged")

func test_repeated_probe_capacity() -> void:
	var s: Dictionary = ENGINE.create(ENGINE.CASE_ID)
	var signed_in: Dictionary = ENGINE.act(s,"request",{"method":"POST","path":"/api/auth/login","body":{"username":"noah","password":PASSWORDS.noah}})
	var parent_export: Dictionary = ENGINE.act(s,"request",{"method":"POST","path":"/api/exports","session":str(payload(signed_in).get("session","")),"body":{"invoice_id":"INV-N204"}})
	check(status(parent_export) == 202 and s.model.jobs.size() == 1,"quota regression protects a real preexisting parent CSV job")
	var original_jobs := canonical(s.model.jobs)
	check(status(act(s,"incident_start",{"variant":"mixed","seed":23})) == 200,"start bounded exercise for repeated business verification")
	if not s.has("exercise"): return
	var observed := observed_anomaly(s,"mixed")
	if observed.is_empty(): return
	for index in 43:
		check(bool(payload(mutation(s,"business_probe")).get("passed",false)),"business probe %d can complete before capacity recovery" % (index+1))
	var prior_jobs := int(s.exercise.branch.model.jobs.size())
	check(prior_jobs >= 64 and int(s.exercise.tick) == 43,"causal probe and actor traffic reaches ordinary export capacity before the final tick")
	check(status(mutation(s,"revoke_session",{"session_id":str(observed.session_id)})) == 200,"operator contains the publicly observed suspect after repeated probes")
	var fresh := mutation(s,"business_probe")
	var steps: Array = payload(fresh).get("steps",[])
	check(bool(payload(fresh).get("passed",false)),"fresh business probe can recover after high export use within the run limit")
	check(steps.any(func(step): return str(step.get("path","")).ends_with("/file") and int(step.get("status",0)) == 200),"late recovery includes a new real CSV download")
	check(int(s.exercise.tick) == 45 and str(s.exercise.phase) == "running","capacity recovery remains possible before the 48-tick conclusion")
	check(canonical(s.model.jobs) == original_jobs,"repeated exercise probes preserve original parent export jobs and bytes")
	print("INCIDENT_QUOTA_DIAGNOSTIC prior_jobs=",prior_jobs," tick=",int(s.exercise.tick)," fresh_probe=",bool(payload(fresh).get("passed",false))," steps=",JSON.stringify(steps))

func test_variation_and_exfil() -> void:
	var s := start("exfil",7)
	if not s.has("exercise"): return
	var first := observed_anomaly(s,"exfil")
	check(not first.is_empty() and int(first.get("bytes",0)) > 0,"quiet exfiltration exposes actual downloaded bytes")
	check(not audit(s).any(func(event): return str(event.get("method","")) == "PATCH"),"quiet variant has no alteration at start")
	var signature := condition_signature(s)
	var old_run := str(s.exercise.run_id)
	var incomplete := payload(op(s,"assess"))
	check(not bool(incomplete.get("complete",true)),"assess cannot complete an untreated incident")
	check(not incomplete.get("metrics",{}).has("disclosure_count") and not incomplete.get("metrics",{}).has("alteration_count"),"in-progress metrics do not reveal omniscient attacker classifications")
	if not first.is_empty(): mutation(s,"revoke_session",{"session_id":str(first.session_id)})
	var finished := mutation(s,"finish")
	check(status(finished) == 200,"incomplete outcome can still be concluded and replayed")
	check(int(payload(finished).get("metrics",{}).get("disclosure_count",0)) > 0,"concluded outcome retains real disclosure that happened before containment")
	var restart := act(s,"incident_restart",{"variant":"exfil","seed":7,"command_id":"restart-same"})
	check(status(restart) == 200 and str(s.exercise.run_id) != old_run,"restart creates a new independent run")
	check(canonical(condition_signature(s)) == canonical(signature),"same seed reproduces conditions without reusing tokens or run IDs")
	var restarted_id := str(s.exercise.run_id)
	act(s,"incident_restart",{"variant":"exfil","seed":7,"command_id":"restart-same"})
	check(str(s.exercise.run_id) == restarted_id,"repeated restart cannot replace the running branch")
	mutation(s,"finish")
	check(status(act(s,"incident_restart",{"variant":"exfil","seed":8,"command_id":"restart-new"})) == 200,"explicit changed-seed replay starts")
	check(canonical(condition_signature(s)) != canonical(signature),"changed seed changes observable exercise conditions")
	check(not s.exercise.get("results",[]).is_empty(),"replay retains prior measured outcome summaries")

func run() -> void:
	test_observation_and_replay()
	test_mixed_recovery()
	test_variation_and_exfil()
	test_evidence_freshness_and_final_tick()
	test_source_limits()
	test_repeated_probe_capacity()
	print("INCIDENT_RESPONSE_PASS assertions="+str(assertions) if failures.is_empty() else "INCIDENT_RESPONSE_FAIL count="+str(failures.size())+" assertions="+str(assertions))
	quit(0 if failures.is_empty() else 1)
