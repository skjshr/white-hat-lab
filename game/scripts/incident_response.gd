extends RefCounted
## A saved response exercise. All actor effects come from the normal dispatcher.
const SERVICE = preload("res://scripts/invoice_service.gd")
const MAX_TICKS := 48
const EVIDENCE_LIMIT := 128
const READ_EVENT_LIMIT := 512

static func result(ok: bool, changed: bool, status: int, data: Dictionary, message: String) -> Dictionary:
	return {"ok":ok,"changed":changed,"observed":changed,"exercise_only":true,"minutes":0.0,"message":message,"result_key":"","result_args":[],"response":SERVICE.response(status, data)}

static func reject(message: String, status: int = 409) -> Dictionary:
	return result(false, false, status, {"error":message}, message)

static func control(s: Dictionary, action: String, args: Dictionary, dispatch: Callable) -> Dictionary:
	var ex: Dictionary = s.get("exercise", {})
	if action == "incident_start" or action == "incident_restart":
		if action == "incident_start" and not ex.is_empty(): return reject("保存された演習があります。再開または結果から再プレイしてください。")
		if action == "incident_restart" and (ex.is_empty() or str(ex.get("phase", "")) != "concluded"): return reject("現在の結果を確定してから再プレイできます。")
		var variant: String = str(args.get("variant", ex.get("variant", "mixed")))
		if variant not in ["mixed", "exfil"]: return reject("演習の種類を確認してください。", 400)
		var seed_value: Variant = args.get("seed", randi_range(1, 999999))
		if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)) or float(seed_value) != floor(float(seed_value)): return reject("seedは整数で指定してください。", 400)
		var past: Array = ex.get("results", []).duplicate(true)
		if not ex.get("result", {}).is_empty():
			past.append({"run_id":ex.run_id,"variant":ex.variant,"seed":ex.seed,"tick":ex.tick,"result":ex.result.duplicate(true)})
		while past.size() > 5: past.pop_front()
		var branch: Dictionary = s.duplicate(true)
		branch.erase("exercise")
		if action == "incident_restart" and int(seed_value) == int(ex.seed) and variant == str(ex.variant): branch = ex.baseline.duplicate(true)
		var created := _start(branch, variant, int(seed_value), past, dispatch)
		if created.is_empty(): return reject("演習用の業務データを準備できませんでした。", 422)
		s.exercise = created
		return result(true, true, 200, {"run_id":created.run_id,"variant":variant,"tick":0}, "対応演習を開始しました。顧客の作業予定と実際の操作記録を照合してください。")
	if ex.is_empty(): return reject("対応演習を開始してください。")
	if action == "incident_leave":
		if not bool(ex.active): return result(true, false, 200, {"active":false}, "演習は一時停止中です。")
		ex.active = false
		ex.revision = int(ex.revision) + 1
		return result(true, true, 200, {"active":false}, "演習を保存して元の案件へ戻りました。")
	if action == "incident_resume":
		if bool(ex.active): return result(true, false, 200, {"active":true}, "この演習を表示しています。")
		ex.active = true
		ex.revision = int(ex.revision) + 1
		return result(true, true, 200, {"active":true,"run_id":ex.run_id}, "保存した演習を再開しました。")
	if action != "incident_action": return reject("未対応の演習操作です。", 400)
	if str(args.get("run_id", "")) != str(ex.run_id): return reject("別の演習の操作です。現在の画面から操作してください。")
	if not bool(ex.active): return reject("演習を再開してから操作してください。")
	var op := str(args.get("op", ""))
	if op == "sessions": return result(true, false, 200, {"sessions":sessions(ex)}, "利用状況を確認しました。")
	if op == "audit": return result(true, false, 200, {"events":ex.events.duplicate(true)}, "操作記録を確認しました。")
	if op == "versions":
		var id := str(args.get("invoice_id", ""))
		if not ex.branch.model.invoices.has(id): return reject("請求書が見つかりません。", 404)
		return result(true, false, 200, {"invoice_id":id,"current_version":int(ex.branch.model.invoices[id].version),"versions":ex.versions.get(id, []).duplicate(true)}, "請求書の版を確認しました。")
	var command := str(args.get("command_id", ""))
	var fingerprint := JSON.stringify(SERVICE.wire(args))
	if not command.is_empty() and ex.commands.has(command):
		var saved: Dictionary = ex.commands[command]
		if str(saved.fingerprint) != fingerprint: return reject("同じ操作IDが別の内容に使われています。")
		var previous: Dictionary = saved.result.duplicate(true)
		previous.changed = false
		previous.observed = false
		previous.duplicate = true
		return previous
	if str(ex.phase) == "concluded":
		if op == "finish": return result(true, false, 200, ex.result.duplicate(true), "結果は確定済みです。")
		return reject("演習は終了しています。結果から再プレイできます。")
	var output := _act(ex, op, args, dispatch)
	if bool(output.changed):
		ex.revision = int(ex.revision) + 1
		ex.last_observation = {"op":op,"data":output.response.data.duplicate(true)}
		if not command.is_empty(): ex.commands[command] = {"fingerprint":fingerprint,"result":output.duplicate(true)}
	return output

static func _start(branch: Dictionary, variant: String, seed: int, past: Array, dispatch: Callable) -> Dictionary:
	var baseline: Dictionary = branch.duplicate(true)
	SERVICE.initialize(branch.model, not branch.model.has("auth_version"))
	# Session credentials and temporary CSV jobs are issued afresh in this copy.
	branch.model.sessions = {}
	branch.model.session_counter = 0
	branch.model.jobs = {}
	branch.model.job_counter = 0
	branch.model.idempotency = {}
	branch.model.exercise_mode = true
	branch.model.exports_paused = false
	var ex := {"active":true,"run_id":"run-" + (str(seed) + ":" + str(Time.get_ticks_usec()) + ":" + str(randi())).sha256_text().substr(0, 12),"variant":variant,"seed":seed,"tick":0,"phase":"running","revision":1,"branch":branch,"events":[],"versions":{},"evidence":{},"results":past,"commands":{},"sessions":{},"event_counter":0,"session_counter":0,"series":[],"assessment":{},"result":{},"last_observation":{},"read_events":0,"omitted_reads":0,"metrics":{"request_success":0,"request_failure":0,"export_success":0,"export_failure":0},"private":{}}
	ex.baseline = baseline
	for invoice in branch.model.invoices.values(): _snapshot(ex, invoice, str(invoice.owner))
	for token in branch.model.sessions:
		_register_session(ex, str(token), {"device":"保存済みブラウザー","source":"192.0.2.20"})
	var candidates: Array = []
	for id in branch.model.invoices:
		if str(branch.model.invoices[id].state) == "draft": candidates.append(str(id))
	candidates.sort()
	var principal := "noah"
	var target := ""
	if not candidates.is_empty():
		target = candidates[posmod(seed, candidates.size())]
		principal = "noah" if str(branch.model.invoices[target].tenant) == "north" else "beth"
	var normal_device := "営業端末-%02d" % (10 + posmod(seed * 13, 70))
	var second_device := "営業端末-%02d" % (10 + posmod(seed * 13 + 23, 70))
	var sources := ["198.51.100.%d" % (20 + posmod(seed, 40)), "203.0.113.%d" % (30 + posmod(seed * 3, 40))]
	ex.private = {"principal":principal,"legit_token":"","attack_token":"","target":target,"normal_invoice":"","normal_device":normal_device,"normal_source":sources[posmod(seed, 2)],"attack_device":second_device,"attack_source":sources[1 - posmod(seed, 2)],"notes_done":false,"normal_export_done":false,"disclosures":[],"alterations":0,"blocked_attempts":0,"legitimate_failures":0,"last_probe":{},"recovery_revision":0,"clean_fields":{},"expected_notes":"月末の入金確認は営業窓口へ連絡。"}
	var legit := ""
	var stolen := ""
	if posmod(seed, 2) == 0:
		legit = _login(ex, principal, {"device":normal_device,"source":ex.private.normal_source}, dispatch)
		stolen = _login(ex, principal, {"device":second_device,"source":ex.private.attack_source}, dispatch)
	else:
		stolen = _login(ex, principal, {"device":second_device,"source":ex.private.attack_source}, dispatch)
		legit = _login(ex, principal, {"device":normal_device,"source":ex.private.normal_source}, dispatch)
	if legit.is_empty() or stolen.is_empty(): return {}
	ex.private.legit_token = legit
	ex.private.attack_token = stolen
	if target.is_empty():
		var made := _perform(ex, {"method":"POST","path":"/api/invoices","session":legit,"body":_draft("定期業務支援", 18000)}, dispatch)
		if int(made.response.status) != 201: return {}
		target = str(made.response.data.id)
		ex.private.target = target
	var target_invoice: Dictionary = branch.model.invoices[target]
	ex.private.clean_fields = _fields(target_invoice)
	var original_notes := str(target_invoice.notes)
	if not original_notes.is_empty(): ex.private.expected_notes = original_notes + "\n" + str(ex.private.expected_notes)
	# Keep the existing text intact even when the source invoice is at its input limit.
	if str(ex.private.expected_notes).length() > 2000: ex.private.expected_notes = original_notes
	var invoice_ids: Array = branch.model.invoices.keys()
	invoice_ids.sort()
	for id in invoice_ids:
		if str(id) != target and str(branch.model.invoices[id].tenant) == str(target_invoice.tenant):
			ex.private.normal_invoice = str(id); break
	if str(ex.private.normal_invoice).is_empty():
		var made := _perform(ex, {"method":"POST","path":"/api/invoices","session":legit,"body":_draft("定例の集計対象", 8400)}, dispatch)
		if int(made.response.status) != 201: return {}
		ex.private.normal_invoice = str(made.response.data.id)
	var note_instruction := "備考を『" + str(ex.private.expected_notes) + "』に更新します。既存の備考は保全してください。" if str(ex.private.expected_notes) != original_notes else "備考は既存の全文を維持してください。"
	var orders := [{"id":"order-1","principal":principal,"device":normal_device,"invoice_id":target,"operation":"notes","details":"請求内容・単価の変更依頼はありません。" + note_instruction},{"id":"order-2","principal":principal,"device":normal_device,"invoice_id":str(ex.private.normal_invoice),"operation":"export","details":"この端末から定例集計用のCSVを取得する予定です。他の請求書のCSV取得は予定していません。"}]
	var trigger := "月末の請求確認中、担当者が請求金額の違いに気づきました。" if variant == "mixed" else "定例集計を始める前に、CSVが取得された記録が見つかりました。"
	ex.context = {"title":"請求サービスの対応演習","brief":trigger + "顧客から確認の依頼です。下の作業予定と実際の記録を照合し、影響を抑えて業務を復旧してください。","work_orders":orders}
	for order in orders:
		_event(ex, {"kind":"customer_note","method":"NOTICE","path":"作業依頼 " + str(order.id),"status":200,"principal":principal,"device":normal_device,"source":"顧客連絡","session_id":"","invoice_id":str(order.invoice_id),"version":0,"bytes":0,"summary":str(order.details),"changes":{}})
	if variant == "mixed":
		var lines: Array = target_invoice.line_items.duplicate(true)
		var increase := 700 + posmod(seed, 8) * 100
		if int(target_invoice.amount) + int(lines[0].quantity) * increase <= SERVICE.MAX_TOTAL:
			lines[0].unit_price = int(lines[0].unit_price) + increase
		else:
			for line in lines:
				if int(line.unit_price) > 1:
					line.unit_price = int(line.unit_price) - 1; break
			if SERVICE.wire(lines) == SERVICE.wire(target_invoice.line_items): lines[0].description = "業務支援（追加）" if str(lines[0].description) != "業務支援（追加）" else "業務支援（変更）"
		var altered := _perform(ex, {"method":"PATCH","path":"/api/invoices/" + target,"session":stolen,"body":{"version":int(target_invoice.version),"line_items":lines}}, dispatch)
		if int(altered.response.status) != 200 or altered.changes.is_empty(): return {}
		ex.private.alterations = 1
	else: _attack_export(ex, dispatch)
	ex.alerts = [{"tick":0,"message":trigger + "操作履歴と顧客の作業依頼を確認してください。"}]
	_point(ex)
	return ex

static func _fields(invoice: Dictionary) -> Dictionary:
	var fields: Dictionary = {}
	for key in SERVICE.EDITABLE + ["amount"]: fields[key] = invoice.get(key)
	return fields.duplicate(true)

static func _snapshot(ex: Dictionary, invoice: Dictionary, actor: String) -> void:
	var id := str(invoice.id)
	if not ex.versions.has(id): ex.versions[id] = []
	for version in ex.versions[id]:
		if int(version.version) == int(invoice.version): return
	ex.versions[id].append({"version":int(invoice.version),"tick":int(ex.tick),"actor":actor,"fields":_fields(invoice)})

static func _register_session(ex: Dictionary, token: String, hints: Dictionary = {}) -> String:
	if token.is_empty() or not ex.branch.model.sessions.has(token): return ""
	if ex.sessions.has(token): return str(ex.sessions[token].session_id)
	ex.session_counter = int(ex.session_counter) + 1
	var username: String = SERVICE.principal(ex.branch.model, token, true)
	ex.sessions[token] = {"session_id":"session-%03d" % int(ex.session_counter),"principal":username,"username":username,"device":str(hints.get("device", "ブラウザー-%02d" % int(ex.session_counter))),"source":str(hints.get("source", "192.0.2.20")),"created_tick":int(ex.tick),"last_tick":int(ex.tick)}
	return str(ex.sessions[token].session_id)

static func sessions(ex: Dictionary) -> Array:
	var rows: Array = []
	for token in ex.sessions:
		var row: Dictionary = ex.sessions[token].duplicate(true)
		row.revoked = bool(ex.branch.model.sessions.get(token, {}).get("revoked", true))
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.session_id) < str(b.session_id))
	return rows

static func _token(ex: Dictionary, id: String) -> String:
	for token in ex.sessions:
		if str(ex.sessions[token].session_id) == id: return str(token)
	return ""

static func _event(ex: Dictionary, row: Dictionary) -> String:
	ex.event_counter = int(ex.event_counter) + 1
	row.id = "event-%05d" % int(ex.event_counter)
	row.tick = int(ex.tick)
	ex.events.append(row)
	return str(row.id)

static func _observe(ex: Dictionary, req: Dictionary, response: Dictionary, before: Dictionary, hints: Dictionary = {}, internal: bool = true) -> Dictionary:
	var token := str(req.get("session", ""))
	if str(req.path) == "/api/auth/login" and int(response.status) == 200: token = str(response.data.get("session", ""))
	var sid := _register_session(ex, token, hints)
	var metadata: Dictionary = ex.sessions.get(token, {})
	if not metadata.is_empty(): metadata.last_tick = int(ex.tick)
	var principal: String = SERVICE.principal(ex.branch.model, token, true)
	var data: Variant = response.get("data", {})
	var id := ""
	if data is Dictionary: id = str(data.get("id", ""))
	var path := str(req.path).get_slice("?", 0)
	var parts := path.split("/", false)
	if parts.size() >= 3 and parts[1] == "invoices": id = str(parts[2])
	if path == "/api/exports": id = str(req.get("body", {}).get("invoice_id", ""))
	if parts.size() >= 3 and parts[1] == "exports" and ex.branch.model.jobs.has(str(parts[2])): id = str(ex.branch.model.jobs[str(parts[2])].invoice.id)
	var changes: Dictionary = {}
	var version := 0
	if not id.is_empty() and ex.branch.model.invoices.has(id):
		var invoice: Dictionary = ex.branch.model.invoices[id]
		version = int(invoice.version)
		for key in SERVICE.EDITABLE:
			if before.has(key) and SERVICE.wire(before[key]) != SERVICE.wire(invoice[key]): changes[key] = {"before":before[key],"after":invoice[key]}
		_snapshot(ex, invoice, principal)
	var successful := int(response.status) >= 200 and int(response.status) < 300
	ex.metrics["request_success" if successful else "request_failure"] += 1
	var is_export := path.begins_with("/api/exports")
	if is_export: ex.metrics["export_success" if successful else "export_failure"] += 1
	var event_id := ""
	if internal or str(req.method) != "GET" or int(ex.read_events) < READ_EVENT_LIMIT:
		event_id = _event(ex, {"kind":"request","session_id":sid,"principal":principal,"device":str(metadata.get("device", "")),"source":str(metadata.get("source", "")),"method":str(req.method),"path":str(req.path),"status":int(response.status),"invoice_id":id,"version":version,"bytes":str(response.get("body", "")).to_utf8_buffer().size(),"summary":"%s %s — HTTP %d" % [str(req.method), str(req.path), int(response.status)],"changes":changes.duplicate(true)})
		if not internal and str(req.method) == "GET": ex.read_events = int(ex.read_events) + 1
	else: ex.omitted_reads = int(ex.omitted_reads) + 1
	return {"response":response,"event_id":event_id,"changes":changes}

static func _before(ex: Dictionary, req: Dictionary) -> Dictionary:
	var parts := str(req.get("path", "")).get_slice("?", 0).split("/", false)
	if parts.size() >= 3 and parts[1] == "invoices": return ex.branch.model.invoices.get(str(parts[2]), {}).duplicate(true)
	return {}

static func _perform(ex: Dictionary, raw: Dictionary, dispatch: Callable, hints: Dictionary = {}) -> Dictionary:
	var req := {"method":"GET","path":"/api/invoices","session":"","body":{},"headers":{},"origin":"portal","replay_of":""}
	req.merge(raw, true)
	var before := _before(ex, req)
	ex.branch.request_sequence = int(ex.branch.request_sequence) + 1
	var response: Dictionary = dispatch.call(ex.branch, req)
	return _observe(ex, req, response, before, hints)

static func _login(ex: Dictionary, username: String, hints: Dictionary, dispatch: Callable) -> String:
	var observed := _perform(ex, {"method":"POST","path":"/api/auth/login","body":{"username":username,"password":SERVICE.PASSWORDS[username]}}, dispatch, hints)
	return str(observed.response.data.get("session", "")) if int(observed.response.status) == 200 else ""

static func _draft(customer: String, price: int) -> Dictionary:
	return {"customer":customer,"issue_date":"2026-10-02","due_date":"2026-10-31","notes":"","line_items":[{"description":"定期支援","quantity":1,"unit_price":price}]}

static func _export(ex: Dictionary, token: String, invoice: String, dispatch: Callable) -> Array:
	var steps: Array = []
	var made := _perform(ex, {"method":"POST","path":"/api/exports","session":token,"body":{"invoice_id":invoice}}, dispatch)
	steps.append(made)
	if int(made.response.status) != 202: return steps
	var job: Dictionary = made.response.data
	steps.append(_perform(ex, {"method":"GET","path":str(job.status_url),"session":token}, dispatch))
	steps.append(_perform(ex, {"method":"GET","path":str(job.status_url),"session":token}, dispatch))
	steps.append(_perform(ex, {"method":"GET","path":str(job.download_url),"session":token}, dispatch))
	return steps

static func _attack_export(ex: Dictionary, dispatch: Callable) -> void:
	var steps := _export(ex, str(ex.private.attack_token), str(ex.private.target), dispatch)
	for step in steps:
		if int(step.response.status) == 401: ex.private.blocked_attempts = int(ex.private.blocked_attempts) + 1
		if int(step.response.status) == 200 and str(step.response.get("content_type", "")) == "text/csv":
			ex.private.disclosures.append({"event_id":str(step.event_id),"tick":int(ex.tick),"bytes":str(step.response.body).to_utf8_buffer().size(),"invoice_id":str(ex.private.target)})

static func _tick(ex: Dictionary, dispatch: Callable) -> void:
	if str(ex.phase) != "running": return
	ex.tick = int(ex.tick) + 1
	if not bool(ex.private.notes_done):
		var invoice: Dictionary = ex.branch.model.invoices[str(ex.private.target)]
		var note := _perform(ex, {"method":"PATCH","path":"/api/invoices/" + str(invoice.id),"session":str(ex.private.legit_token),"body":{"version":int(invoice.version),"notes":str(ex.private.expected_notes)}}, dispatch)
		if int(note.response.status) == 200: ex.private.notes_done = true
		else: ex.private.legitimate_failures = int(ex.private.legitimate_failures) + 1
	if int(ex.tick) >= 2 + posmod(int(ex.seed), 2) and not bool(ex.private.normal_export_done):
		var steps := _export(ex, str(ex.private.legit_token), str(ex.private.normal_invoice), dispatch)
		if int(steps.back().response.status) == 200: ex.private.normal_export_done = true
		else: ex.private.legitimate_failures = int(ex.private.legitimate_failures) + 1
	if int(ex.tick) >= 2 + posmod(int(ex.seed), 2) and posmod(int(ex.tick) - (2 + posmod(int(ex.seed), 2)), 2) == 0: _attack_export(ex, dispatch)
	_point(ex)
	if int(ex.tick) >= MAX_TICKS:
		ex.assessment = _assess(ex)
		ex.phase = "concluded"
		ex.result = _conclusion(ex, ex.assessment)

static func _point(ex: Dictionary) -> void:
	var total := 0
	for invoice in ex.branch.model.invoices.values(): total += int(invoice.amount)
	var point: Dictionary = ex.metrics.duplicate(true)
	point.tick = int(ex.tick)
	point.invoice_total = total
	ex.series.append(point)

static func observe_player(ex: Dictionary, req: Dictionary, response: Dictionary, before: Dictionary, dispatch: Callable) -> void:
	_observe(ex, req, response, before, {}, false)
	var write := str(req.get("method", "GET")) in ["POST", "PATCH", "PUT", "DELETE"]
	# Exact duplicate writes have no business/session/export state delta.
	var after: Dictionary = ex.branch.model
	if write and int(response.status) >= 200 and int(response.status) < 300 and before.get("_model_fingerprint", "") != JSON.stringify(SERVICE.wire(after)):
		if str(req.get("path", "")).begins_with("/api/invoices"): ex.private.recovery_revision = int(ex.private.recovery_revision) + 1
		_tick(ex, dispatch)
	ex.revision = int(ex.revision) + 1

static func player_before(ex: Dictionary, req: Dictionary) -> Dictionary:
	var before := _before(ex, req)
	before._model_fingerprint = JSON.stringify(SERVICE.wire(ex.branch.model))
	return before

static func _act(ex: Dictionary, op: String, args: Dictionary, dispatch: Callable) -> Dictionary:
	if op in ["pin_event", "unpin_event"]:
		var id := str(args.get("event_id", ""))
		if op == "unpin_event":
			if not ex.evidence.has(id): return result(true, false, 200, {"event_id":id,"pinned":false}, "この記録は保全されていません。")
			ex.evidence.erase(id)
		else:
			if ex.evidence.has(id): return result(true, false, 200, {"event_id":id,"pinned":true}, "この記録は保全済みです。")
			if ex.evidence.size() >= EVIDENCE_LIMIT: return reject("証拠保管の上限です。不要な記録を外してください。", 429)
			var record: Dictionary = {}
			for event in ex.events:
				if str(event.id) == id: record = event; break
			if record.is_empty(): return reject("操作記録が見つかりません。", 404)
			ex.evidence[id] = record.duplicate(true)
		return result(true, true, 200, {"event_id":id,"pinned":op == "pin_event"}, "記録の保全を更新しました。")
	if op == "revoke_session":
		var token := _token(ex, str(args.get("session_id", "")))
		if token.is_empty(): return reject("セッションが見つかりません。", 404)
		if bool(ex.branch.model.sessions[token].revoked): return result(true, false, 200, {"session_id":str(args.session_id),"revoked":true}, "このセッションは失効済みです。")
		ex.branch.model.sessions[token].revoked = true
		ex.private.recovery_revision = int(ex.private.recovery_revision) + 1
		_operator_event(ex, "REVOKE", str(args.session_id), "セッションを失効しました。")
		_tick(ex, dispatch)
		return result(true, true, 200, {"session_id":str(args.session_id),"revoked":true}, "選んだセッションを失効しました。後続の利用結果を確認してください。")
	if op == "set_export_paused":
		if not args.get("paused") is bool: return reject("停止状態を指定してください。", 400)
		if bool(ex.branch.model.exports_paused) == bool(args.paused): return result(true, false, 200, {"paused":args.paused}, "出力設定は変更されていません。")
		ex.branch.model.exports_paused = args.paused
		ex.private.recovery_revision = int(ex.private.recovery_revision) + 1
		_operator_event(ex, "CONFIG", "exports", "CSV出力を一時停止しました。" if bool(args.paused) else "CSV出力を再開しました。")
		_tick(ex, dispatch)
		return result(true, true, 200, {"paused":args.paused}, "CSV出力の設定を変更しました。通常の閲覧は継続できます。")
	if op == "restore_version": return _restore(ex, args, dispatch)
	if op == "business_probe":
		var probe := _business_probe(ex, dispatch)
		ex.private.last_probe = {"tick":int(ex.tick) + 1,"recovery_revision":int(ex.private.recovery_revision),"passed":bool(probe.passed),"steps":probe.steps.duplicate(true)}
		_tick(ex, dispatch)
		return result(true, true, 200, probe, str(probe.message))
	if op == "advance":
		_tick(ex, dispatch)
		return result(true, true, 200, {"tick":int(ex.tick)}, "1分進め、利用者の実際の要求を処理しました。")
	if op in ["assess", "finish"]:
		ex.assessment = _assess(ex)
		var value: Dictionary = ex.assessment.duplicate(true)
		if op == "finish":
			ex.phase = "concluded"
			ex.result = _conclusion(ex, value)
			value = ex.result.duplicate(true)
		return result(true, true, 200, value, "対応結果を確定しました。" if op == "finish" else "現在の観測と業務状態を確認しました。")
	return reject("未対応の演習操作です。", 400)

static func _operator_event(ex: Dictionary, method: String, path: String, summary: String) -> void:
	_event(ex, {"kind":"operator","session_id":"","principal":"対応担当","device":"対応コンソール","source":"演習内","method":method,"path":path,"status":200,"invoice_id":"","version":0,"bytes":0,"summary":summary,"changes":{}})

static func _restore(ex: Dictionary, args: Dictionary, dispatch: Callable) -> Dictionary:
	var id := str(args.get("invoice_id", ""))
	if not ex.branch.model.invoices.has(id): return reject("請求書が見つかりません。", 404)
	var invoice: Dictionary = ex.branch.model.invoices[id]
	for key in ["expected_version", "source_version"]:
		if not SERVICE._integer(args.get(key)) or int(args.get(key)) < 1: return reject("版は正の整数で指定してください。", 422)
	if int(args.get("expected_version", -1)) != int(invoice.version): return reject("請求書に新しい変更があります。版を比較し直してください。")
	var fields: Variant = args.get("fields", [])
	if not fields is Array or fields.is_empty(): return reject("復元する項目を選んでください。", 422)
	var source: Dictionary = {}
	for version in ex.versions.get(id, []):
		if int(version.version) == int(args.get("source_version", -1)): source = version.fields
	if source.is_empty(): return reject("その版は見つかりません。", 404)
	var body := {"version":int(invoice.version)}
	for field in fields:
		if not field is String or field not in SERVICE.EDITABLE: return reject("復元できない項目が選ばれています。", 422)
		body[field] = source[field]
	var validated: Dictionary = SERVICE._validated(body, invoice)
	if not validated.fields.is_empty(): return reject("選んだ項目の組合せでは請求書の入力条件を満たしません。", 422)
	var changes: Dictionary = {}
	for key in validated.data:
		if SERVICE.wire(invoice.get(key)) != SERVICE.wire(validated.data[key]): changes[key] = {"before":invoice.get(key),"after":validated.data[key]}
	if changes.is_empty(): return result(true, false, 200, {"invoice":SERVICE.wire(invoice)}, "選んだ項目はこの版と同じです。")
	# Authorized incident recovery creates a compensating version, never rewrites history.
	invoice.merge(validated.data, true)
	invoice.version = int(invoice.version) + 1
	ex.branch.request_sequence = int(ex.branch.request_sequence) + 1
	invoice.updated_sequence = int(ex.branch.request_sequence)
	ex.private.recovery_revision = int(ex.private.recovery_revision) + 1
	SERVICE._event(ex.branch.model, invoice, "restored", "incident-operator", int(ex.branch.request_sequence), changes)
	_snapshot(ex, invoice, "対応担当")
	_event(ex, {"kind":"operator","session_id":"","principal":"対応担当","device":"対応コンソール","source":"演習内","method":"RESTORE","path":"/api/invoices/" + id,"status":200,"invoice_id":id,"version":int(invoice.version),"bytes":0,"summary":"選択した項目を新しい版に復元しました。","changes":changes.duplicate(true)})
	var restored: Dictionary = SERVICE.wire(invoice)
	_tick(ex, dispatch)
	return result(true, true, 200, {"invoice":restored}, "選んだ項目を新しい版へ復元しました。他の項目は保持しています。")

static func _business_probe(ex: Dictionary, dispatch: Callable) -> Dictionary:
	var steps: Array = []
	var previous_token := str(ex.private.legit_token)
	var first := _perform(ex, {"method":"GET","path":"/api/invoices/" + str(ex.private.normal_invoice),"session":previous_token}, dispatch)
	steps.append(first)
	if int(first.response.status) != 200: ex.private.legitimate_failures = int(ex.private.legitimate_failures) + 1
	var token := _login(ex, str(ex.private.principal), {"device":ex.private.normal_device,"source":ex.private.normal_source}, dispatch)
	if token.is_empty(): return {"passed":false,"steps":_probe_steps(ex, steps),"message":"正規利用者の再ログインを確認できませんでした。"}
	ex.private.legit_token = token
	var created := _perform(ex, {"method":"POST","path":"/api/invoices","session":token,"body":_draft("業務復旧の試験取引", 100)}, dispatch)
	steps.append(created)
	var passed := int(created.response.status) == 201
	if passed:
		var invoice: Dictionary = created.response.data
		steps.append(_perform(ex, {"method":"GET","path":"/api/invoices/" + str(invoice.id),"session":token}, dispatch))
		steps.append(_perform(ex, {"method":"POST","path":"/api/invoices/" + str(invoice.id) + "/approve","session":token,"body":{"version":int(invoice.version)}}, dispatch))
		steps.append_array(_export(ex, token, str(invoice.id), dispatch))
		for step in steps.slice(1):
			if int(step.response.status) < 200 or int(step.response.status) >= 300: passed = false
		if str(steps.back().response.get("content_type", "")) != "text/csv": passed = false
	if not passed: ex.private.legitimate_failures = int(ex.private.legitimate_failures) + 1
	return {"passed":passed,"steps":_probe_steps(ex, steps),"message":"正規利用者が新しいセッションで請求作成・承認・CSV取得を完了しました。" if passed else "通常業務の試験が途中で失敗しました。記録されたHTTP応答と出力設定を確認してください。"}

static func _probe_steps(ex: Dictionary, steps: Array) -> Array:
	var output: Array = []
	for step in steps:
		for event in ex.events:
			if str(event.id) == str(step.event_id): output.append({"method":event.method,"path":event.path,"status":event.status,"event_id":event.id}); break
	return output

static func _assess(ex: Dictionary) -> Dictionary:
	var truth: Dictionary = ex.private
	var target: Dictionary = ex.branch.model.invoices[str(truth.target)]
	var damage := 0
	for key in SERVICE.EDITABLE:
		var expected: Variant = str(truth.expected_notes) if key == "notes" and bool(truth.notes_done) else truth.clean_fields[key]
		if SERVICE.wire(target[key]) != SERVICE.wire(expected): damage += 1
	var contained := bool(ex.branch.model.sessions[str(truth.attack_token)].revoked) and int(truth.blocked_attempts) > 0
	var business := bool(truth.get("last_probe", {}).get("passed", false)) and int(truth.get("last_probe", {}).get("recovery_revision", -1)) == int(truth.recovery_revision) and not bool(ex.branch.model.exports_paused) and not bool(ex.branch.model.sessions[str(truth.legit_token)].revoked)
	var note_context := false
	var export_context := false
	var changed_evidence := false
	var exported_evidence := false
	var sid := str(ex.sessions[str(truth.attack_token)].session_id)
	for event in ex.evidence.values():
		if str(event.kind) == "customer_note" and str(event.path) == "作業依頼 order-1": note_context = true
		if str(event.kind) == "customer_note" and str(event.path) == "作業依頼 order-2": export_context = true
		if str(event.get("session_id", "")) != sid or int(event.get("status", 0)) != 200 or str(event.get("invoice_id", "")) != str(truth.target): continue
		if str(event.method) == "PATCH" and event.get("changes", {}).has("line_items"): changed_evidence = true
		if str(event.method) == "GET" and str(event.path).ends_with("/file") and int(event.bytes) > 0: exported_evidence = true
	var checks := [{"id":"containment","label":"アクセス停止の確認","passed":contained,"message":"選択した対処後の利用要求が拒否された記録を確認してください。"},{"id":"integrity","label":"請求内容と正当な変更の保全","passed":damage == 0,"message":"作業依頼と請求書の版を比較し、未解消の変更を確認してください。"},{"id":"business","label":"通常業務の復旧","passed":business,"message":"出力制限を見直し、正常な業務試験を完了してください。"},{"id":"evidence","label":"顧客条件と操作の根拠","passed":(note_context and changed_evidence) or (export_context and exported_evidence),"message":"顧客の作業予定と、それに照合する操作記録を保全してください。"}]
	var metrics: Dictionary = ex.metrics.duplicate(true)
	metrics.evidence_count = ex.evidence.size()
	metrics.ticks = int(ex.tick)
	return {"complete":checks.all(func(row: Dictionary): return bool(row.passed)),"checks":checks,"metrics":metrics}

static func _conclusion(ex: Dictionary, assessment: Dictionary) -> Dictionary:
	var output := assessment.duplicate(true)
	var damage := 0
	var invoice: Dictionary = ex.branch.model.invoices[str(ex.private.target)]
	for key in SERVICE.EDITABLE:
		var expected: Variant = str(ex.private.expected_notes) if key == "notes" and bool(ex.private.notes_done) else ex.private.clean_fields[key]
		if SERVICE.wire(invoice[key]) != SERVICE.wire(expected): damage += 1
	output.metrics.merge({"disclosure_count":ex.private.disclosures.size(),"alteration_count":int(ex.private.alterations),"remaining_damage":damage,"legitimate_failures":int(ex.private.legitimate_failures)}, true)
	output.debrief = {"summary":"対応後の状態と残った影響を確認してください。取得済みのCSVは復元や停止で取り消されません。","disclosures":ex.private.disclosures.duplicate(true),"session_id":str(ex.sessions[str(ex.private.attack_token)].session_id),"invoice_id":str(ex.private.target),"notes":"請求内容の復元と、正当な備考更新の保持を別々に評価しています。誤失効したセッションは再有効化せず新規ログインで業務を復帰します。"}
	return output

static func view(ex: Dictionary) -> Dictionary:
	if ex.is_empty(): return {"active":false}
	return {"active":bool(ex.active),"run_id":str(ex.run_id),"variant":str(ex.variant),"seed":int(ex.seed),"tick":int(ex.tick),"phase":str(ex.phase),"revision":int(ex.revision),"export_paused":bool(ex.branch.model.exports_paused),"events":ex.events.duplicate(true),"sessions":sessions(ex),"series":ex.series.duplicate(true),"evidence":ex.evidence.values().duplicate(true),"last_observation":ex.last_observation.duplicate(true),"assessment":ex.assessment.duplicate(true),"result":ex.result.duplicate(true),"results":ex.results.duplicate(true),"context":ex.context.duplicate(true),"alerts":ex.alerts.duplicate(true),"omitted_routine_reads":int(ex.omitted_reads)}
