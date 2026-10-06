extends RefCounted
## Persistent, company-owned SaaS monitoring equipment and evidence-bound follow-up.

const SOURCE_CASE := "advanced-saas-response"
const WATCH_CASE := "advanced-saas-watch"
const CLIENT := "北斗物流"
const TOOL_ID := "saas_watch"
const PURCHASE_COST := 2400
const VERSION := 1

static func _whole(value: Variant, minimum: int = 0) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= 2147483647.0

static func _valid_records(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	var ids: Dictionary = {}
	for row in value:
		if not row is Dictionary: return false
		var id := str(row.get("id", ""))
		if id not in ["audit-1", "audit-2"] or ids.has(id): return false
		if str(row.get("action", "")) != "consent_review" or not row.get("data", null) is Dictionary: return false
		ids[id] = true
	return ids.has("audit-1") and ids.has("audit-2")

static func _valid_payload(value: Variant) -> bool:
	return value is Dictionary \
		and value.get("source_contract_id", null) is String and not str(value.source_contract_id).is_empty() \
		and str(value.get("client", CLIENT)) == CLIENT \
		and _whole(value.get("source_day", null), 1) \
		and _valid_records(value.get("approved_originals", null)) \
		and value.get("monitored", null) is bool \
		and _whole(value.get("alert_delay", null)) \
		and int(value.alert_delay) == (0 if bool(value.monitored) else 9)

static func validate(value: Variant) -> bool:
	if not value is Dictionary or not _whole(value.get("version", null), VERSION) or int(value.version) != VERSION: return false
	if not value.get("customers", null) is Dictionary or not value.get("incidents", null) is Dictionary: return false
	for client in value.customers:
		var customer: Variant = value.customers[client]
		if not client is String or client != CLIENT or not customer is Dictionary: return false
		if str(customer.get("client", "")) != CLIENT or not customer.get("source_contract_id", null) is String or str(customer.source_contract_id).is_empty(): return false
		if not _whole(customer.get("source_day", null), 1) or not _whole(customer.get("enrolled_day", null), 1): return false
		if not _valid_records(customer.get("approved_originals", null)): return false
	for source_id in value.incidents:
		var incident: Variant = value.incidents[source_id]
		if not source_id is String or source_id.is_empty() or not incident is Dictionary: return false
		if str(incident.get("source_contract_id", "")) != source_id: return false
		for field in ["source_day", "created_day"]:
			if not _whole(incident.get(field, null), 1): return false
		if int(incident.created_day) <= int(incident.source_day): return false
		if str(incident.get("status", "")) not in ["pending", "working", "fulfilled", "cancelled"]: return false
		if not _valid_payload(incident.get("payload", null)): return false
		if int(incident.payload.source_day) != int(incident.source_day): return false
		if str(incident.payload.source_contract_id) != source_id: return false
		var accepted := str(incident.get("accepted_contract_id", ""))
		if str(incident.status) in ["working", "fulfilled", "cancelled"] and accepted.is_empty(): return false
		if str(incident.status) == "pending" and not accepted.is_empty(): return false
	return true

static func _valid_tool(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	return _whole(value.get("version", null), VERSION) and int(value.version) == VERSION \
		and _whole(value.get("purchased_day", null), 1) \
		and _whole(value.get("purchase_cost", null), PURCHASE_COST) and int(value.purchase_cost) == PURCHASE_COST

static func _approved_originals(receipt: Dictionary) -> Array[Dictionary]:
	var outcome: Variant = receipt.get("saas_outcome", {})
	if not outcome is Dictionary: return []
	var report: Variant = outcome.get("report", {})
	if not report is Dictionary or not bool(report.get("submitted", false)): return []
	var original: Variant = report.get("original", {})
	if not original is Dictionary or original.is_empty(): original = report.get("latest", {})
	if not original is Dictionary: return []
	var rows: Variant = original.get("records", [])
	if not rows is Array: return []
	var found: Dictionary = {}
	for row in rows:
		if not row is Dictionary: continue
		var id := str(row.get("id", ""))
		if id in ["audit-1", "audit-2"] and str(row.get("action", "")) == "consent_review":
			found[id] = row.duplicate(true)
	if not found.has("audit-1") or not found.has("audit-2"): return []
	return [found["audit-1"], found["audit-2"]]

static func _latest_source(game) -> Dictionary:
	var completed: Array = game.state.get("completed_ids", [])
	var rows: Array = game.state.get("history", [])
	for index in range(rows.size() - 1, -1, -1):
		var row: Variant = rows[index]
		if not row is Dictionary or not str(row.get("kind", "")).is_empty(): continue
		var source_id := str(row.get("id", ""))
		if source_id.is_empty() or source_id not in completed or str(row.get("case_id", "")) != SOURCE_CASE or str(row.get("client", "")) != CLIENT: continue
		var approved := _approved_originals(row)
		if approved.size() != 2: continue
		var checks: Variant = row.get("checks", [])
		if not checks is Array or checks.is_empty() or not checks.all(func(check): return check is Dictionary and bool(check.get("passed", false))): continue
		return {"source_contract_id":source_id,"source_day":int(row.get("day", 0)),"approved_originals":approved}
	return {}

static func status(game) -> Dictionary:
	var state: Dictionary = game.state
	var tools: Variant = state.get("company_tools", {})
	var saved_tool: Variant = tools.get(TOOL_ID, {}) if tools is Dictionary else null
	var tool_valid := _valid_tool(saved_tool)
	var owned: bool = tool_valid and saved_tool is Dictionary and not saved_tool.is_empty()
	var watch: Variant = state.get("saas_watch", {"version":VERSION,"customers":{},"incidents":{}})
	var watch_valid := validate(watch)
	var source := _latest_source(game)
	var client_record: Dictionary = watch.get("customers", {}).get(CLIENT, {}) if watch_valid else {}
	var already_enrolled := not client_record.is_empty()
	var can_install: bool = not owned and tool_valid and watch_valid and not already_enrolled and not source.is_empty() and int(state.get("cash", 0)) >= PURCHASE_COST
	var can_enroll: bool = watch_valid and not already_enrolled and not source.is_empty() and (owned or can_install)
	var reason := ""
	if not tool_valid: reason = "監視設備の導入記録を確認できません。"
	elif not watch_valid: reason = "監視登録の保存記録を確認できません。"
	elif already_enrolled: reason = "北斗物流の監視登録済みです。"
	elif source.is_empty(): reason = "完了済み案件の承認原記録がありません。"
	elif not owned and int(state.get("cash", 0)) < PURCHASE_COST: reason = "監視設備の導入資金が不足しています。"
	elif not owned: reason = "監視設備の導入と登録を受け付けられます。"
	var incident: Dictionary = {}
	if watch_valid:
		var ids: Array = watch.get("incidents", {}).keys()
		ids.sort_custom(func(a, b): return int(watch.incidents[a].get("created_day", 0)) > int(watch.incidents[b].get("created_day", 0)))
		for source_id in ids:
			var candidate: Dictionary = watch.incidents[source_id]
			if str(candidate.get("payload", {}).get("client", CLIENT)) == CLIENT:
				incident = candidate.duplicate(true)
				break
	return {"owned":owned,"enrolled":already_enrolled,"enrolled_day":int(client_record.get("enrolled_day", -1)),"monitoring_customer":client_record.duplicate(true),"can_install":can_install,"can_enroll":can_enroll,"reason":reason,"purchase_cost":PURCHASE_COST,"client":CLIENT,"baseline":source.duplicate(true) if not source.is_empty() else client_record.duplicate(true),"incident":incident}

static func enroll(game) -> bool:
	var availability := status(game)
	var watch: Variant = game.state.get("saas_watch", {"version":VERSION,"customers":{},"incidents":{}})
	if not validate(watch): return false
	if bool(availability.get("enrolled", false)): return true
	var source: Dictionary = availability.get("baseline", {}).duplicate(true)
	if source.is_empty() or not bool(availability.get("can_enroll", false)): return false
	var before: Dictionary = game.state.duplicate(true)
	if not bool(availability.get("owned", false)):
		if int(game.state.get("cash", 0)) < PURCHASE_COST: return false
		if not game.state.has("company_tools") or not game.state.company_tools is Dictionary: game.state.company_tools = {}
		game.state.company_tools[TOOL_ID] = {"version":VERSION,"purchased_day":int(game.state.day),"purchase_cost":PURCHASE_COST}
		game.state.cash = int(game.state.cash) - PURCHASE_COST
		game.state.history.append({"kind":"investment","tool_id":TOOL_ID,"title":"北斗物流 SaaS監視設備","day":int(game.state.day),"amount":PURCHASE_COST})
	if not game.state.has("saas_watch"): game.state.saas_watch = {"version":VERSION,"customers":{},"incidents":{}}
	var frozen: Dictionary = source.duplicate(true)
	frozen["client"] = CLIENT
	frozen["enrolled_day"] = int(game.state.get("day", 1))
	game.state.saas_watch.customers[CLIENT] = frozen
	if not game.save_game():
		game.state = before
		if game.has_signal("notified"): game.notified.emit("SaaS監視の登録を保存できませんでした。原記録と会社状態を保持しています。")
		return false
	if game.has_signal("changed"): game.changed.emit()
	return true

static func refresh(state: Dictionary, day: int) -> bool:
	if day < 1: return false
	if not state.has("saas_watch"): state.saas_watch = {"version":VERSION,"customers":{},"incidents":{}}
	if not validate(state.saas_watch): return false
	var watch: Dictionary = state.saas_watch
	var changed := false
	for raw in state.get("history", []):
		if not raw is Dictionary or not str(raw.get("kind", "")).is_empty(): continue
		var source_id := str(raw.get("id", ""))
		var source_day := int(raw.get("day", 0))
		if source_id.is_empty() or source_id not in state.get("completed_ids", []) or str(raw.get("case_id", "")) != SOURCE_CASE or str(raw.get("client", "")) != CLIENT: continue
		if source_day < 1 or day <= source_day or watch.incidents.has(source_id): continue
		var originals := _approved_originals(raw)
		if originals.size() != 2: continue
		var checks: Variant = raw.get("checks", [])
		if not checks is Array or checks.is_empty() or not checks.all(func(check): return check is Dictionary and bool(check.get("passed", false))): continue
		var enrolled: Dictionary = watch.get("customers", {}).get(CLIENT, {})
		var tools: Variant = state.get("company_tools", {})
		var installed: Variant = tools.get(TOOL_ID, {}) if tools is Dictionary else null
		var monitor_owned: bool = _valid_tool(installed) and installed is Dictionary and not installed.is_empty()
		var monitored: bool = monitor_owned and str(enrolled.get("source_contract_id", "")) == source_id and int(enrolled.get("source_day", -1)) == source_day and int(enrolled.get("enrolled_day", day + 1)) <= day and _valid_records(enrolled.get("approved_originals", []))
		var payload := {"source_contract_id":source_id,"source_day":source_day,"approved_originals":originals.duplicate(true),"monitored":monitored,"alert_delay":0 if monitored else 9,"client":CLIENT}
		watch.incidents[source_id] = {"source_contract_id":source_id,"source_day":source_day,"created_day":day,"status":"pending","accepted_contract_id":"","payload":payload}
		changed = true
	return changed

static func available(state: Dictionary, day: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = state.get("saas_watch", {})
	if not validate(raw): return result
	var incidents: Dictionary = raw.get("incidents", {})
	var ids: Array = incidents.keys(); ids.sort()
	for source_id in ids:
		var incident: Dictionary = incidents[source_id]
		if str(incident.get("status", "")) == "pending" and int(incident.get("created_day", day + 1)) <= day:
			result.append(incident.duplicate(true))
	return result

static func accept(state: Dictionary, source_id: String, contract_id: String) -> bool:
	if contract_id.is_empty() or not validate(state.get("saas_watch", {})): return false
	var incidents: Dictionary = state.saas_watch.get("incidents", {})
	if not incidents.has(source_id): return false
	var incident: Dictionary = incidents[source_id]
	if str(incident.get("status", "")) != "pending": return false
	incident["status"] = "working"
	incident["accepted_contract_id"] = contract_id
	return true

static func finish(state: Dictionary, source_id: String, contract_id: String, cancelled: bool) -> void:
	if contract_id.is_empty() or not validate(state.get("saas_watch", {})): return
	var incidents: Dictionary = state.saas_watch.get("incidents", {})
	if not incidents.has(source_id): return
	var incident: Dictionary = incidents[source_id]
	if str(incident.get("status", "")) != "working" or str(incident.get("accepted_contract_id", "")) != contract_id: return
	incident["status"] = "cancelled" if cancelled else "fulfilled"
