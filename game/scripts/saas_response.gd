extends RefCounted
## Versioned SaaS incident-response case. The projection never advances its clock.

const CASE_ID := "advanced-saas-response"
const WATCH_CASE_ID := "advanced-saas-watch"
const MODEL_VERSION := "saas-response-v1"
const ASSISTANT_COST := 300
const ROW_IMPACT_COST := 500
const LEDGER_ROWS := [
	{"id":"LEDGER-001","department":"finance","amount":18000},
	{"id":"LEDGER-002","department":"sales","amount":27000},
	{"id":"LEDGER-003","department":"operations","amount":12500}
]
const EGRESS_DUE_MINUTES := [12, 18, 24]
const WATCH_EXPORT_ROWS := [
	{"id":"ARCHIVE-001","department":"dispatch","amount":18,"type":"shipment-summary"},
	{"id":"ARCHIVE-002","department":"warehouse","amount":27,"type":"route-summary"},
	{"id":"ARCHIVE-003","department":"support","amount":12,"type":"service-summary"}
]

static func create(case_id: String = CASE_ID) -> Dictionary:
	if case_id != CASE_ID: return {}
	var audit: Array[Dictionary] = [
		{"id":"audit-1","seq":1,"minute":0,"actor":"user-7","app":"app-19","destination":"ledger","action":"consent_review","status":200,"revision":0,"world_revision":0,"detail":"FIN-114 approved billing integration","data":{"publisher":"ledger-sync","permission":"ledger.read","resource":"ledger","approved_change":"FIN-114","approved_by":"finance-owner","actualdataread":true}},
		{"id":"audit-2","seq":2,"minute":0,"actor":"user-7","app":"app-72","destination":"ledger","action":"consent_review","status":200,"revision":0,"world_revision":0,"detail":"No approved change found for expense-viewer","data":{"publisher":"expense-viewer","permission":"ledger.read","resource":"ledger","approved_change":"none","approved_by":"none","actualdataread":false}}
	]
	return {
		"kind":CASE_ID,
		"case_id":CASE_ID,
		"model_version":MODEL_VERSION,
		"revision":0,
		"world_revision":0,
		"elapsed_minutes":0,
		"sequence":2,
		"user":{"id":"user-7","password_revision":0},
		"apps":{
			"app-19":{"id":"app-19","label":"請求連携","publisher":"ledger-sync","owner":"finance","permission":"ledger.read","resource":"ledger","approved_change":"FIN-114","approved_by":"finance-owner","consent":{"enabled":true,"revision":0},"session":{"active":true,"revision":0,"id":"SES-app-19-0"}},
			"app-72":{"id":"app-72","label":"経費資料ビューア","publisher":"expense-viewer","owner":"finance","permission":"ledger.read","resource":"ledger","approved_change":"none","approved_by":"none","consent":{"enabled":true,"revision":0},"session":{"active":true,"revision":0,"id":"SES-app-72-0"}}
		},
		"audit":[audit[0].duplicate(true),audit[1].duplicate(true)],
		"records":audit,
		"egress":{"schedule":[
			{"id":"SYNC-001","due_minute":12,"status":"scheduled","row_count":0,"record_id":""},
			{"id":"SYNC-002","due_minute":18,"status":"scheduled","row_count":0,"record_id":""},
			{"id":"SYNC-003","due_minute":24,"status":"scheduled","row_count":0,"record_id":""}
		],"exported_rows":[],"impact_cost":0},
		"invoice":{"id":"BILL-001","amount":57500,"status":"pending","attempts":[],"receipt_id":"","submitted_minute":-1,"verified_revision":-1},
		"organization":{"mode":"","record_ids":[],"input_hash":"","usage_cost":0,"impact_cost":0,"created_minute":-1},
		"report":{"submitted":false,"version":0,"record_ids":[],"input_hash":"","accepted_minute":-1,"revision":-1,"original":{},"latest":{},"supplements":[]},
		"last_result":{}
	}

static func _valid_watch_source(payload: Variant) -> bool:
	if not payload is Dictionary: return false
	if str(payload.get("source_contract_id", "")).is_empty() or int(payload.get("source_day", 0)) < 1: return false
	if str(payload.get("client", "北斗物流")) != "北斗物流" or not payload.get("monitored", null) is bool: return false
	if int(payload.get("alert_delay", -1)) != (0 if bool(payload.monitored) else 9): return false
	var originals: Variant = payload.get("approved_originals", null)
	if not originals is Array: return false
	var ids: Dictionary = {}
	for row in originals:
		if not row is Dictionary: return false
		var id := str(row.get("id", ""))
		if id not in ["audit-1", "audit-2"] or str(row.get("action", "")) != "consent_review" or not row.get("data", null) is Dictionary: return false
		ids[id] = true
	return ids.has("audit-1") and ids.has("audit-2") and originals.size() == 2

static func create_followup(payload: Dictionary) -> Dictionary:
	if not _valid_watch_source(payload): return {}
	var s: Dictionary = create(CASE_ID)
	if s.is_empty(): return {}
	s["case_id"] = WATCH_CASE_ID
	s["watch_source"] = payload.duplicate(true)
	s["threat_app_id"] = "app-84"
	# This incident has a new, distinct unapproved exporter. Preserve the
	# original case's app-72 only inside the source report references.
	s.apps.erase("app-72")
	s.apps["app-84"] = {"id":"app-84","label":"配送資料エクスポーター","publisher":"archive-exporter","owner":"operations","permission":"archive.export","resource":"archive-export","approved_change":"none","approved_by":"none","consent":{"enabled":true,"revision":0},"session":{"active":true,"revision":0,"id":"SES-app-84-0"}}
	var current_audit: Array = s.get("audit", [])
	if current_audit.size() != 2: return {}
	current_audit[1] = {"id":"audit-2","seq":2,"minute":0,"actor":"user-7","app":"app-84","destination":"archive-export","action":"consent_review","status":200,"revision":0,"world_revision":0,"detail":"No approved change found for archive-exporter","data":{"publisher":"archive-exporter","permission":"archive.export","resource":"archive-export","approved_change":"none","approved_by":"none","actualdataread":false}}
	s["audit"] = current_audit
	var saved_records: Array = s.get("records", [])
	if saved_records.size() != 2: return {}
	saved_records[1] = current_audit[1].duplicate(true)
	var sequence := 2
	for raw in payload.get("approved_originals", []):
		sequence += 1
		var source_record: Dictionary = raw.duplicate(true)
		saved_records.append({"id":"watch-baseline-%s" % str(source_record.get("id", "")),"seq":sequence,"minute":0,"actor":"prior-case","app":"","destination":"prior-case/%s" % str(payload.get("source_contract_id", "")),"action":"baseline_reference","status":int(source_record.get("status", 0)),"revision":int(source_record.get("world_revision", source_record.get("revision", 0))),"world_revision":0,"detail":"前回SaaS案件の承認原本を参照しています。今回の再測定結果ではありません。","data":{"source_contract_id":str(payload.get("source_contract_id", "")),"source_day":int(payload.get("source_day", 0)),"source_record_id":str(source_record.get("id", "")),"source_app":str(source_record.get("app", "")),"original":source_record.duplicate(true)}})
	s["records"] = saved_records
	s["sequence"] = sequence
	var schedule: Array = s.egress.get("schedule", []).duplicate(true)
	var due_times: Array = EGRESS_DUE_MINUTES if bool(payload.get("monitored", false)) else [3, 9, 15]
	for index in schedule.size(): schedule[index]["due_minute"] = int(due_times[index])
	s.egress["schedule"] = schedule
	s.invoice["id"] = "BILL-002"
	s.invoice["customer"] = "北斗物流"
	return s

static func _result(ok: bool, changed: bool, observed: bool, minutes: int, usage_cost: int, impact_cost: int, message: String, data: Dictionary = {}) -> Dictionary:
	var actual_data: Dictionary = data.duplicate(true)
	actual_data["usage_cost"] = usage_cost
	actual_data["impact_cost"] = impact_cost
	return {"ok":ok,"changed":changed,"observed":observed,"minutes":minutes,"cost":usage_cost+impact_cost,"usage_cost":usage_cost,"impact_cost":impact_cost,"message":message,"data":actual_data}

static func _error(message: String) -> Dictionary:
	return _result(false,false,false,0,0,0,message)

static func _valid_state(s: Dictionary) -> bool:
	if str(s.get("kind", "")) != CASE_ID or str(s.get("model_version", "")) != MODEL_VERSION: return false
	var case_id := str(s.get("case_id", ""))
	if case_id == CASE_ID: return true
	return case_id == WATCH_CASE_ID and _valid_watch_source(s.get("watch_source", null)) and str(s.get("threat_app_id", "")) == "app-84"

static func _threat_app_id(s: Dictionary) -> String:
	return "app-84" if str(s.get("case_id", "")) == WATCH_CASE_ID else "app-72"

static func _export_destination(s: Dictionary) -> String:
	return "archive-export" if str(s.get("case_id", "")) == WATCH_CASE_ID else "ledger"

static func _export_rows(s: Dictionary) -> Array:
	return WATCH_EXPORT_ROWS if str(s.get("case_id", "")) == WATCH_CASE_ID else LEDGER_ROWS

static func _invoice_id(s: Dictionary) -> String:
	return "BILL-002" if str(s.get("case_id", "")) == WATCH_CASE_ID else "BILL-001"

static func _receipt_id(s: Dictionary) -> String:
	return "RCPT-" + _invoice_id(s)

static func _app(s: Dictionary, id: String) -> Dictionary:
	var apps: Dictionary = s.get("apps", {})
	return apps.get(id, {}) if apps.has(id) else {}

static func _effective(app: Dictionary) -> bool:
	# Consent authorizes future issuance. An already-issued session remains live
	# until it is explicitly revoked, even after consent is withdrawn.
	return bool(app.get("session", {}).get("active", false))

static func _append_record(s: Dictionary, app_id: String, destination: String, action: String, status: int, detail: String, data: Dictionary = {}, actor: String = "analyst") -> Dictionary:
	s.sequence = int(s.get("sequence", 0)) + 1
	var row := {"id":"saas-%03d" % int(s.sequence),"seq":int(s.sequence),"minute":int(s.get("elapsed_minutes", 0)),"actor":actor,"app":app_id,"destination":destination,"action":action,"status":status,"detail":detail,"revision":int(s.get("world_revision", 0)),"world_revision":int(s.get("world_revision", 0)),"data":data.duplicate(true)}
	s.records.append(row)
	return row

static func _flat_event_copy(source: Dictionary, keep_audit_snapshot: bool = false) -> Dictionary:
	var row: Dictionary = source.duplicate(false)
	var source_data: Dictionary = source.get("data", {})
	var data: Dictionary = {}
	# Historical audit/report records may themselves contain snapshots. Strip
	# those nested snapshots from timeline copies to keep saves linear in size.
	for key in source_data:
		if str(key) == "records": continue
		if str(key) == "events":
			if keep_audit_snapshot and source_data.get("events") is Array:
				var flat_events: Array[Dictionary] = []
				for event in source_data.get("events", []):
					if event is Dictionary: flat_events.append(_flat_event_copy(event))
				data["events"] = flat_events
			continue
		if source_data[key] is Dictionary or source_data[key] is Array:
			data[key] = source_data[key].duplicate(true)
		else:
			data[key] = source_data[key]
	row["data"] = data
	return row

static func _flat_event_history(s: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in s.get("records", []):
		if record is Dictionary: result.append(_flat_event_copy(record))
	return result

static func _due_schedule(s: Dictionary) -> Array:
	return s.get("egress", {}).get("schedule", [])

static func _advance(s: Dictionary, minutes: int) -> int:
	if minutes <= 0: return 0
	var start := int(s.get("elapsed_minutes", 0))
	var finish := start + minutes
	var impact_added := 0
	var egress: Dictionary = s.get("egress", {})
	var schedule: Array = egress.get("schedule", [])
	for index in schedule.size():
		var item: Dictionary = schedule[index]
		if str(item.get("status", "")) != "scheduled" or int(item.get("due_minute", 0)) > finish: continue
		s.elapsed_minutes = int(item.get("due_minute", finish))
		var threat_id := _threat_app_id(s)
		var app: Dictionary = _app(s, threat_id)
		if not bool(app.get("session", {}).get("active", false)) and bool(app.get("consent", {}).get("enabled", false)):
			app["session"]["active"] = true
			app["session"]["revision"] = int(s.get("world_revision", 0)) + 1
			app["session"]["id"] = "SES-%s-%d" % [threat_id, int(s.get("world_revision", 0)) + 1]
			s.world_revision = int(s.get("world_revision", 0)) + 1
			s.apps[threat_id] = app
			_append_record(s, threat_id, "session", "session_reissued_by_sync", 200, "同意が有効なため同期で既存接続が再発行されました。", {"revision":int(s.world_revision)}, str(app.get("publisher", "external-app")))
		var export_destination := _export_destination(s)
		var batch_data := {"sync_id":str(item.get("id", "")),"destination":export_destination,"rows":[],"row_ids":[],"world_revision":int(s.get("world_revision", 0))}
		var status := 403
		var row_count := 0
		var event_impact := 0
		if _effective(app):
			status = 200
			row_count = _export_rows(s).size()
			for source_row in _export_rows(s):
				var exported: Dictionary = source_row.duplicate(true)
				exported["sync_copy_id"] = "%s-%s" % [str(item.get("id", "")), str(source_row.get("id", ""))]
				batch_data["rows"].append(exported)
				batch_data["row_ids"].append(str(exported.get("id", "")))
				egress["exported_rows"].append({"sync_id":str(item.get("id", "")),"minute":int(item.get("due_minute", finish)),"record_id":"","row":exported.duplicate(true)})
			event_impact = row_count * ROW_IMPACT_COST
			impact_added += event_impact
		egress["impact_cost"] = int(egress.get("impact_cost", 0)) + event_impact
		var event := _append_record(s, threat_id, export_destination, "scheduled_export", status, "外部同期が%s行の写しを送信しました。" % row_count if status == 200 else "認可がなく外部同期は拒否されました。", batch_data, str(app.get("publisher", "external-app")))
		item["status"] = "sent" if status == 200 else "blocked"
		item["row_count"] = row_count
		item["record_id"] = str(event.get("id", ""))
		item["world_revision"] = int(s.get("world_revision", 0))
		for exported_row in egress.get("exported_rows", []):
			if str(exported_row.get("sync_id", "")) == str(item.get("id", "")) and str(exported_row.get("record_id", "")).is_empty():
				exported_row["record_id"] = str(event.get("id", ""))
		schedule[index] = item
	s.elapsed_minutes = finish
	egress["schedule"] = schedule
	s.egress = egress
	return impact_added

static func _next_event_minute(s: Dictionary) -> int:
	for item in _due_schedule(s):
		if str(item.get("status", "")) == "scheduled": return int(item.get("due_minute", -1))
	return -1

static func _record_costs(result: Dictionary, usage_cost: int = 0, impact_cost: int = 0) -> Dictionary:
	result["cost"] = usage_cost + impact_cost
	result["usage_cost"] = usage_cost
	result["impact_cost"] = impact_cost
	var data: Dictionary = result.get("data", {})
	data["usage_cost"] = usage_cost
	data["impact_cost"] = impact_cost
	result["data"] = data
	return result

static func _organized_hash(ids: Array[String]) -> String:
	var sorted: Array[String] = ids.duplicate()
	sorted.sort()
	return JSON.stringify(sorted).sha256_text()

static func _record_by_id(s: Dictionary, id: String) -> Dictionary:
	for row in s.get("records", []):
		if str(row.get("id", "")) == id: return row
	return {}

static func _latest_egress_record_id(s: Dictionary) -> String:
	var records: Array = s.get("records", [])
	for index in range(records.size() - 1, -1, -1):
		var row: Dictionary = records[index]
		if str(row.get("action", "")) != "scheduled_export" or int(row.get("status", 0)) != 200: continue
		var rows: Variant = row.get("data", {}).get("rows", [])
		if rows is Array and not rows.is_empty(): return str(row.get("id", ""))
	return ""

static func _audit_snapshot_covers_egress(audit_record: Dictionary, egress_id: String) -> bool:
	if egress_id.is_empty(): return true
	var events: Variant = audit_record.get("data", {}).get("events", [])
	if not events is Array: return false
	for event in events:
		if str(event.get("id", "")) == egress_id: return true
	return false

static func _report_covers_latest_egress(report_record: Dictionary, s: Dictionary) -> bool:
	if report_record.is_empty(): return false
	var egress_id := _latest_egress_record_id(s)
	if egress_id.is_empty(): return true
	for source in report_record.get("records", []):
		if str(source.get("action", "")) == "collect_audit" and _audit_snapshot_covers_egress(source, egress_id): return true
	return false

static func _act(s: Dictionary, action: String, args: Dictionary) -> Dictionary:
	var app_id := str(args.get("app", ""))
	var threat_id := _threat_app_id(s)
	var app: Dictionary
	var usage_cost := 0
	var minutes := 0
	match action:
		"inspect_app":
			if not ["app-19",threat_id].has(app_id): return _error("調査対象アプリを選んでください。")
			minutes = 1
		"collect_audit": minutes = 2
		"probe_session":
			if not ["app-19",threat_id].has(app_id): return _error("接続を確認するアプリを選んでください。")
			minutes = 1
		"change_access":
			if not ["app-19",threat_id].has(app_id) or str(args.get("control", "")) not in ["consent","session"] or not args.get("enabled", null) is bool: return _error("アプリの同意または接続状態を確認してください。")
			app = _app(s, app_id)
			var key := "enabled" if str(args.control) == "consent" else "active"
			var current := bool(app.get(str(args.control), {}).get(key, false))
			if current == bool(args.enabled): return _result(true,false,false,0,0,0,"設定は既にその状態です。")
			minutes = 2
		"password_reset": minutes = 2
		"submit_invoice":
			if str(args.get("invoice_id", "")) != _invoice_id(s): return _error("受付対象の請求書が見つかりません。")
			var saved_invoice: Dictionary = s.get("invoice", {})
			if not str(saved_invoice.get("receipt_id", "")).is_empty() and int(saved_invoice.get("verified_revision", -1)) == int(s.get("world_revision", 0)):
				return _result(true,false,false,0,0,0,"請求書は既に受付済みです。同じ受付番号を維持しています。",{"receipt_id":str(s.invoice.receipt_id),"duplicate":true})
			minutes = 2
		"organize_records":
			var organization_mode := str(args.get("mode", ""))
			var organization_ids_value: Variant = args.get("record_ids", [])
			if organization_mode not in ["manual","assistant"] or not organization_ids_value is Array or organization_ids_value.is_empty() or organization_ids_value.size() > 32: return _error("整理方法と原記録を選んでください。")
			var organization_ids: Array[String] = []
			for value in organization_ids_value:
				var organization_id := str(value)
				if organization_id.is_empty() or organization_id in organization_ids or _record_by_id(s, organization_id).is_empty(): return _error("未取得の原記録を含むため整理できません。")
				organization_ids.append(organization_id)
			var organization_hash := _organized_hash(organization_ids)
			if str(s.get("organization", {}).get("input_hash", "")) == organization_hash: return _result(true,false,false,0,0,0,"同じ整理結果を表示しています。",{"input_hash":organization_hash,"record_ids":organization_ids})
			minutes = 5 if organization_mode == "manual" else 2
			usage_cost = ASSISTANT_COST if organization_mode == "assistant" else 0
		"submit_report":
			var report_source_ids: Variant = args.get("record_ids", [])
			if not report_source_ids is Array or report_source_ids.is_empty() or report_source_ids.size() > 32: return _error("報告する原記録を選んでください。")
			var report_source_ids_list: Array[String] = []
			for value in report_source_ids:
				var report_source_id := str(value)
				if report_source_id.is_empty() or report_source_id in report_source_ids_list or _record_by_id(s, report_source_id).is_empty(): return _error("未取得の原記録を含むため報告できません。")
				report_source_ids_list.append(report_source_id)
			var selected_audit1 := "audit-1" in report_source_ids_list
			var selected_audit2 := "audit-2" in report_source_ids_list
			var selected_baseline := true
			if str(s.get("case_id", "")) == WATCH_CASE_ID:
				for prior_original in s.get("watch_source", {}).get("approved_originals", []):
					var expected_reference := "watch-baseline-%s" % str(prior_original.get("id", ""))
					if expected_reference not in report_source_ids_list: selected_baseline = false
			var collected_audit := false
			for report_source_id in report_source_ids_list:
				var report_source_record := _record_by_id(s, report_source_id)
				if str(report_source_record.get("action", "")) == "collect_audit":
					var captured_audit_ids: Variant = report_source_record.get("data", {}).get("audit_ids", [])
					if captured_audit_ids is Array and "audit-1" in captured_audit_ids and "audit-2" in captured_audit_ids and _audit_snapshot_covers_egress(report_source_record, _latest_egress_record_id(s)):
						collected_audit = true
			if not selected_audit1 or not selected_audit2 or not selected_baseline or not collected_audit: return _error("両アプリと前回の承認原本、取得した監査記録が必要です。")
			var prior_report: Dictionary = s.get("report", {})
			var prior_latest_report: Dictionary = prior_report.get("latest", prior_report.get("original", {}))
			if bool(prior_report.get("submitted", false)) and _report_covers_latest_egress(prior_latest_report, s):
				var prior_report_hash := _organized_hash(report_source_ids_list)
				if str(prior_latest_report.get("input_hash", "")) == prior_report_hash:
					return _result(true,false,false,0,0,0,"現在の報告原本に最新の送信記録まで含まれています。",{"record_ids":report_source_ids_list,"record_id":str(prior_latest_report.get("record_id", ""))})
			minutes = 2
		_:
			return _error("実際のアプリ調査、監査取得、アクセス変更、請求受付、原記録整理を選んでください。")
	var impact_cost := _advance(s, minutes)
	var world_revision := int(s.get("world_revision", 0))
	var result: Dictionary = _result(true,true,true,minutes,usage_cost,impact_cost,"操作を記録しました。")
	var record: Dictionary = {}
	match action:
		"inspect_app":
			app = _app(s, app_id)
			var audit_row := _audit_for_app(s, app_id)
			record = _append_record(s, app_id, "application", "inspect_app", 200, "申請・所有者・現在の同意と接続状態を確認しました。", {"app":app.duplicate(true),"audit_id":str(audit_row.get("id", ""))})
			result.message = "申請と現在のアクセス状態を確認しました。"
		"collect_audit":
			var audit_record_ids: Array[String] = []
			for audit_row in s.get("audit", []): audit_record_ids.append(str(audit_row.get("id", "")))
			record = _append_record(s, "", "audit-log", "collect_audit", 200, "監査記録と取得時点までの操作履歴を取得しました。", {"audit_ids":audit_record_ids,"records":s.get("audit", []).duplicate(true),"events":_flat_event_history(s)})
			result.message = "監査記録を取得しました。"
		"probe_session":
			app = _app(s, app_id)
			var allowed := _effective(app)
			record = _append_record(s, app_id, str(app.get("resource", "ledger")), "probe_session", 200 if allowed else 403, "現在のアクセス確認は許可されました。" if allowed else "現在のアクセスは拒否されました。", {"allowed":allowed,"consent":bool(app.get("consent", {}).get("enabled", false)),"session":bool(app.get("session", {}).get("active", false)),"world_revision":world_revision})
			result.ok = allowed
			result.message = "現在のアプリ接続は許可されています。" if allowed else "現在のアプリ接続は拒否されました。"
		"change_access":
			app = _app(s, app_id)
			var control := str(args.control)
			var enabled := bool(args.enabled)
			app[control]["enabled" if control == "consent" else "active"] = enabled
			app[control]["revision"] = world_revision + 1
			if control == "session" and enabled:
				app["session"]["id"] = "SES-%s-%d" % [app_id, world_revision + 1]
			s.apps[app_id] = app
			s.world_revision = world_revision + 1
			record = _append_record(s, app_id, control, "change_" + control, 200, "同意を有効化しました。" if enabled and control == "consent" else "同意を撤回しました。" if control == "consent" else "接続を再発行しました。" if enabled else "既存接続を失効させました。", {"enabled":enabled,"world_revision":int(s.world_revision)})
			result.message = "アプリの状態を変更しました。"
		"password_reset":
			s.user["password_revision"] = int(s.get("user", {}).get("password_revision", 0)) + 1
			s.world_revision = world_revision + 1
			record = _append_record(s, "", "user-7", "password_reset", 200, "利用者のパスワードを更新しました。アプリ同意と発行済み接続は別に残ります。", {"password_revision":int(s.user.password_revision),"world_revision":int(s.world_revision)})
			result.message = "利用者のパスワードを更新しました。アプリの同意と接続は別に確認してください。"
		"submit_invoice":
			var invoice: Dictionary = s.get("invoice", {})
			var billing_app := _app(s, "app-19")
			var allowed := _effective(billing_app)
			var receipt_id := str(invoice.get("receipt_id", ""))
			var had_receipt := not receipt_id.is_empty()
			if allowed and not had_receipt: receipt_id = _receipt_id(s)
			var status := 200 if allowed else 403
			var attempt := _append_record(s, "app-19", "invoice:" + str(invoice.get("id", _invoice_id(s))), "submit_invoice", status, "受付済み請求の現在世代を確認しました。" if allowed and had_receipt else "請求書を受け付けました。" if allowed else "請求連携アプリの接続が拒否されました。", {"invoice_id":str(invoice.get("id", _invoice_id(s))),"amount":int(invoice.get("amount", 0)),"receipt_id":receipt_id,"world_revision":world_revision,"duplicate":had_receipt,"reconfirmation":had_receipt})
			var attempts: Array = invoice.get("attempts", [])
			attempts.append(attempt.duplicate(true)); invoice["attempts"] = attempts
			if allowed:
				invoice["status"] = "submitted"; invoice["receipt_id"] = receipt_id
				if int(invoice.get("submitted_minute", -1)) < 0: invoice["submitted_minute"] = int(s.elapsed_minutes)
				invoice["verified_revision"] = world_revision
			else:
				if not had_receipt: invoice["status"] = "denied"
				invoice["verified_revision"] = -1
			s.invoice = invoice
			record = attempt
			result.ok = allowed
			result.message = "既存の受付番号を保ったまま、現在世代の請求接続を確認しました。" if allowed and had_receipt else "請求書を受け付けました。" if allowed else "請求受付または現在世代の再確認は拒否されました。通常請求の接続を確認してください。"
		"organize_records":
			var organization_record_ids: Array[String] = []
			for value in args.record_ids: organization_record_ids.append(str(value))
			var organization_action_mode := str(args.mode)
			var organization_action_hash := _organized_hash(organization_record_ids)
			if organization_action_mode == "assistant": usage_cost = ASSISTANT_COST
			s.organization = {"mode":organization_action_mode,"record_ids":organization_record_ids.duplicate(),"input_hash":organization_action_hash,"usage_cost":usage_cost,"impact_cost":impact_cost,"created_minute":int(s.elapsed_minutes),"world_revision":int(s.world_revision)}
			record = _append_record(s, "", "case-records", "organize_" + organization_action_mode, 200, "取得済み原記録を時系列に整理しました。", {"record_ids":organization_record_ids.duplicate(),"input_hash":organization_action_hash,"creates_evidence":false,"world_revision":int(s.world_revision)})
			result.message = "原記録を整理しました。新しい証拠は作成していません。"
		"submit_report":
			var submission_record_ids: Array[String] = []
			for value in args.record_ids: submission_record_ids.append(str(value))
			var submission_hash := _organized_hash(submission_record_ids)
			var original_records: Array[Dictionary] = []
			for original_id in submission_record_ids:
				var source_record: Dictionary = _record_by_id(s, original_id)
				original_records.append(_flat_event_copy(source_record, str(source_record.get("action", "")) == "collect_audit"))
			var existing_report: Dictionary = s.get("report", {})
			var report_version := 1
			if bool(existing_report.get("submitted", false)):
				report_version = int(existing_report.get("version", 1)) + 1
			var immutable := {"version":report_version,"record_ids":submission_record_ids.duplicate(),"records":original_records.duplicate(true),"input_hash":submission_hash,"accepted_minute":int(s.elapsed_minutes),"revision":world_revision}
			record = _append_record(s, "", "incident-report", "submit_report", 200, "申請と監査の原記録を含む報告を提出しました。", immutable)
			immutable["record_id"] = str(record.get("id", ""))
			record["data"] = immutable.duplicate(true)
			s.records[s.records.size() - 1] = record.duplicate(true)
			if bool(existing_report.get("submitted", false)):
				var supplements: Array = existing_report.get("supplements", []).duplicate(true)
				supplements.append(immutable.duplicate(true))
				existing_report["supplements"] = supplements
				existing_report["latest"] = immutable.duplicate(true)
				existing_report["record_ids"] = submission_record_ids.duplicate()
				existing_report["input_hash"] = submission_hash
				existing_report["accepted_minute"] = int(s.elapsed_minutes)
				existing_report["revision"] = world_revision
				existing_report["version"] = report_version
				s.report = existing_report
			else:
				s.report = {"submitted":true,"version":report_version,"record_ids":submission_record_ids.duplicate(),"input_hash":submission_hash,"accepted_minute":int(s.elapsed_minutes),"revision":world_revision,"original":immutable.duplicate(true),"latest":immutable.duplicate(true),"supplements":[]}
			result.message = "原記録に基づく報告を提出しました。"
	result.data["record"] = record.duplicate(true)
	result.data["usage_cost"] = usage_cost
	result.data["impact_cost"] = impact_cost
	result["usage_cost"] = usage_cost
	result["impact_cost"] = impact_cost
	result["cost"] = usage_cost + impact_cost
	result.data["elapsed_minutes"] = int(s.get("elapsed_minutes", 0))
	result.data["world_revision"] = int(s.get("world_revision", 0))
	return result

static func _audit_for_app(s: Dictionary, app_id: String) -> Dictionary:
	for row in s.get("audit", []):
		if str(row.get("app", "")) == app_id: return row
	return {}

static func act(s: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	if not _valid_state(s): return _error("SaaS対応案件の保存状態を確認できません。")
	if JSON.stringify(args).length() > 20000: return _error("入力が大きすぎます。")
	var before: Dictionary = s.duplicate(true)
	var result := _act(s, action, args)
	if bool(result.get("changed", false)):
		s.revision = int(before.get("revision", 0)) + 1
		s.last_result = {"action":action,"ok":bool(result.get("ok", false)),"record_id":str(result.get("data", {}).get("record", {}).get("id", "")),"revision":int(s.revision),"message":str(result.get("message", ""))}
	else:
		# Idempotent no-charge retries retain the saved domain state unchanged.
		var returned_data: Dictionary = result.get("data", {}).duplicate(true)
		result["data"] = returned_data
	return result

static func advance(s: Dictionary, minutes: float) -> int:
	if not _valid_state(s) or minutes <= 0.0: return 0
	var rounded_minutes := maxi(0, roundi(minutes))
	if rounded_minutes <= 0: return 0
	var impact := _advance(s, rounded_minutes)
	s.revision = int(s.get("revision", 0)) + 1
	s.last_result = {"action":"elapsed_work","ok":true,"record_id":"","revision":int(s.revision),"message":"経過した作業時間を保存しました。"}
	return impact

static func _latest_app_request(state: Dictionary, app_id: String) -> Dictionary:
	var records: Array = state.get("records", [])
	for index in range(records.size() - 1, -1, -1):
		var row: Dictionary = records[index]
		if str(row.get("app", "")) == app_id:
			return row.duplicate(true)
	return {}

static func _latest_app_probe(state: Dictionary, app_id: String) -> Dictionary:
	var records: Array = state.get("records", [])
	for index in range(records.size() - 1, -1, -1):
		var row: Dictionary = records[index]
		if str(row.get("app", "")) == app_id and str(row.get("action", "")) == "probe_session":
			return row.duplicate(true)
	return {}

static func _app_projection(state: Dictionary, app: Dictionary) -> Dictionary:
	var app_id := str(app.get("id", ""))
	var latest := _latest_app_request(state, app_id)
	var probe := _latest_app_probe(state, app_id)
	var fresh := not probe.is_empty() and int(probe.get("world_revision", -1)) == int(state.get("world_revision", 0))
	var status := int(probe.get("status", 0)) if not probe.is_empty() else 0
	var consent_enabled := bool(app.get("consent", {}).get("enabled", false))
	var session_active := bool(app.get("session", {}).get("active", false))
	var measurement := "？未実測" if probe.is_empty() else ("✓ 接続確認" if fresh and status < 400 else "× 拒否" if fresh else "◷ 要再確認")
	return {"id":app_id,"label":str(app.get("label", "")),"publisher":str(app.get("publisher", "")),"owner":str(app.get("owner", "")),"permission":str(app.get("permission", "")),"resource":str(app.get("resource", "")),"approved_change":str(app.get("approved_change", "")),"approved_by":str(app.get("approved_by", "")),"consent":app.get("consent", {}).duplicate(true),"consent_enabled":consent_enabled,"consent_revision":int(app.get("consent", {}).get("revision", 0)),"session":app.get("session", {}).duplicate(true),"session_active":session_active,"session_revision":int(app.get("session", {}).get("revision", 0)),"session_id":str(app.get("session", {}).get("id", "")),"effective_access":_effective(app),"latest_request":latest,"latest_probe":probe,"fresh":fresh,"status":status,"measurement":measurement}

static func _report_requirements(s: Dictionary) -> bool:
	var report: Dictionary = s.get("report", {})
	if not bool(report.get("submitted", false)): return false
	var latest: Dictionary = report.get("latest", report.get("original", {}))
	if latest.is_empty() or not _report_covers_latest_egress(latest, s): return false
	if str(s.get("case_id", "")) == WATCH_CASE_ID:
		var ids: Variant = latest.get("record_ids", [])
		if not ids is Array: return false
		for prior_original in s.get("watch_source", {}).get("approved_originals", []):
			if ("watch-baseline-%s" % str(prior_original.get("id", ""))) not in ids: return false
	return true

static func checks(s: Dictionary) -> Array:
	if not _valid_state(s): return []
	var threat_id := _threat_app_id(s)
	var threat_app: Dictionary = _app(s, threat_id)
	var denied_current := false
	for record in s.get("records", []):
		if str(record.get("action", "")) == "probe_session" and str(record.get("app", "")) == threat_id and int(record.get("status", 0)) == 403 and int(record.get("world_revision", -1)) == int(s.get("world_revision", 0)):
			denied_current = true
	var invoice: Dictionary = s.get("invoice", {})
	var invoice_current := str(invoice.get("receipt_id", "")) == _receipt_id(s) and int(invoice.get("verified_revision", -1)) == int(s.get("world_revision", 0))
	var audit_preserved := false
	for record in s.get("records", []):
		if str(record.get("action", "")) == "collect_audit":
			var audit_ids: Variant = record.get("data", {}).get("audit_ids", [])
			if audit_ids is Array and "audit-1" in audit_ids and "audit-2" in audit_ids:
				audit_preserved = true
	return [
		{"id":"report","label_key":"saas_check_report","passed":_report_requirements(s)},
		{"id":"controls","label_key":"saas_check_controls","passed":not bool(threat_app.get("consent", {}).get("enabled", true)) and not bool(threat_app.get("session", {}).get("active", true))},
		{"id":"denial","label_key":"saas_check_denial","passed":denied_current},
		{"id":"invoice","label_key":"saas_check_invoice","passed":invoice_current},
		{"id":"audit","label_key":"saas_check_audit","passed":audit_preserved and _report_requirements(s)}
	]

static func view(state: Dictionary, selected: String = "") -> Dictionary:
	if not _valid_state(state): return {}
	var apps: Array[Dictionary] = []
	var threat_id := _threat_app_id(state)
	for app_id in ["app-19",threat_id]: apps.append(_app_projection(state, _app(state, app_id)))
	var schedule: Array = state.get("egress", {}).get("schedule", []).duplicate(true)
	var invoice: Dictionary = state.get("invoice", {}).duplicate(true)
	invoice["total"] = int(invoice.get("amount", 0))
	invoice["customer"] = "北斗物流"
	if str(state.get("case_id", "")) == WATCH_CASE_ID: invoice["lines"] = [
		{"label":"請求連携 月額利用料","amount":18000},
		{"label":"配送API利用料","amount":27000},
		{"label":"監査・記録保全","amount":12500}
	]
	else: invoice["lines"] = [
		{"label":"請求連携 月額利用料","amount":18000},
		{"label":"配送API利用料","amount":27000},
		{"label":"監査・記録保全","amount":12500}
	]
	var attempts: Array = invoice.get("attempts", [])
	invoice["last_attempt"] = attempts.back().duplicate(true) if not attempts.is_empty() else {}
	var egress_state: Dictionary = state.get("egress", {})
	var exported_rows: Array = egress_state.get("exported_rows", []).duplicate(true)
	var data := {
		"model_version":MODEL_VERSION,
		"watch_source":state.get("watch_source", {}).duplicate(true) if state.get("watch_source", {}) is Dictionary else {},
		"threat_app_id":threat_id,
		"revision":int(state.get("revision", 0)),
		"world_revision":int(state.get("world_revision", 0)),
		"elapsed_minutes":int(state.get("elapsed_minutes", 0)),
		"next_event_minute":_next_event_minute(state),
		"user":state.get("user", {}).duplicate(true),
		"apps":apps,
		"session_id":str(_app(state,"app-19").get("session",{}).get("id","")),
		"consent":bool(_app(state,"app-19").get("consent",{}).get("enabled",false)),
		"session":bool(_app(state,"app-19").get("session",{}).get("active",false)),
		"records":state.get("records", []).duplicate(true),
		"egress":{"schedule":schedule,"exported_rows":exported_rows,"leaked_rows":exported_rows.size(),"impact_cost":int(state.get("egress", {}).get("impact_cost", 0))},
		"leaked_rows":exported_rows.size(),
		"invoice":invoice,
		"organization":state.get("organization", {}).duplicate(true),
		"organized":not str(state.get("organization", {}).get("input_hash", "")).is_empty(),
		"report":state.get("report", {}).duplicate(true)
	}
	return {"kind":"saas_response_v1","revision":int(state.get("revision", 0)),"selected":selected,"checks":checks(state),"last_result":state.get("last_result", {}).duplicate(true),"saas":data}
