extends RefCounted
## Per-connection state for the selective SaaS session response case.

const VERSION := 1
const THREAT_SESSION_ID := "SES-203"
const EXPORT_ROWS := [
	{"id":"EXPORT-001","type":"shipment-summary","department":"dispatch"},
	{"id":"EXPORT-002","type":"route-summary","department":"warehouse"},
	{"id":"EXPORT-003","type":"service-summary","department":"support"}
]

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func create() -> Dictionary:
	return {
		"version":VERSION,
		"consent":{"app_id":"app-19","enabled":true,"approved_change":"FIN-114","approved_by":"finance-owner","revision":0},
		"next_session_number":204,
		"sessions":[
			{"id":"SES-201","app_id":"app-19","purpose":"billing","device":"BILLING-01","issued_at":"08:50","issued_minute":0,"generation":1,"active":true,"status":"active","expected_destination":"invoice/BILL-003","expected_read_rows":3,"approved":true,"issued_record_id":""},
			{"id":"SES-202","app_id":"app-19","purpose":"aggregation","device":"BATCH-01","issued_at":"08:55","issued_minute":0,"generation":1,"active":true,"status":"active","expected_destination":"internal-aggregate","expected_read_rows":120,"approved":true,"issued_record_id":""},
			{"id":"SES-203","app_id":"app-19","purpose":"connection","device":"SYNC-NODE","issued_at":"09:00","issued_minute":0,"generation":1,"active":true,"status":"active","expected_destination":"external-storage","expected_read_rows":3,"approved":false,"issued_record_id":""}
		]
	}

static func validate(world: Variant) -> bool:
	if not world is Dictionary or not _whole(world.get("version", null), VERSION, VERSION) or int(world.version) != VERSION: return false
	var consent: Variant = world.get("consent", null)
	if not consent is Dictionary or str(consent.get("app_id", "")) != "app-19" or typeof(consent.get("enabled", null)) != TYPE_BOOL: return false
	if str(consent.get("approved_change", "")) != "FIN-114" or not _whole(consent.get("revision", null), 0, 2147483647): return false
	var sessions: Variant = world.get("sessions", null)
	if not sessions is Array or sessions.size() < 3 or sessions.size() > 64: return false
	var ids: Dictionary = {}
	var active_purposes: Dictionary = {}
	for raw in sessions:
		if not raw is Dictionary: return false
		var id := str(raw.get("id", ""))
		var purpose := str(raw.get("purpose", ""))
		if id.is_empty() or ids.has(id) or not id.begins_with("SES-"): return false
		if purpose not in ["billing", "aggregation", "connection"]: return false
		if str(raw.get("app_id", "")) != "app-19" or typeof(raw.get("active", null)) != TYPE_BOOL: return false
		if str(raw.get("status", "")) != ("active" if bool(raw.active) else "revoked"): return false
		if not raw.get("device", null) is String or not raw.get("issued_at", null) is String: return false
		if not _whole(raw.get("issued_minute", null), 0, 2147483647): return false
		if not _whole(raw.get("generation", null), 1, 2147483647): return false
		if not raw.get("expected_destination", null) is String: return false
		if not _whole(raw.get("expected_read_rows", null), 0, 1000000): return false
		if typeof(raw.get("approved", null)) != TYPE_BOOL or not raw.get("issued_record_id", null) is String: return false
		ids[id] = true
		if bool(raw.active):
			if purpose == "connection":
				if id != THREAT_SESSION_ID: return false
			elif active_purposes.has(purpose):
				return false
			else:
				active_purposes[purpose] = id
	if not ids.has("SES-201") or not ids.has("SES-202") or not ids.has(THREAT_SESSION_ID): return false
	if not _whole(world.get("next_session_number", null), 204, 1000): return false
	return true

static func index_of(world: Dictionary, session_id: String) -> int:
	for index in world.get("sessions", []).size():
		if str(world.sessions[index].get("id", "")) == session_id: return index
	return -1

static func get_session(world: Dictionary, session_id: String) -> Dictionary:
	var index := index_of(world, session_id)
	return world.sessions[index] if index >= 0 else {}

static func active_for(world: Dictionary, purpose: String) -> Dictionary:
	for raw in world.get("sessions", []):
		if str(raw.get("purpose", "")) == purpose and bool(raw.get("active", false)): return raw
	return {}

static func mark_issued_record(world: Dictionary, session_id: String, record_id: String) -> void:
	var index := index_of(world, session_id)
	if index >= 0: world.sessions[index].issued_record_id = record_id

static func mark_revoked(world: Dictionary, session_id: String) -> Dictionary:
	var index := index_of(world, session_id)
	if index < 0: return {}
	var row: Dictionary = world.sessions[index]
	if not bool(row.get("active", false)): return {}
	row.active = false
	row.status = "revoked"
	world.sessions[index] = row
	return row.duplicate(true)

static func revoke_all(world: Dictionary) -> Array[Dictionary]:
	var revoked: Array[Dictionary] = []
	for index in world.get("sessions", []).size():
		var row: Dictionary = world.sessions[index]
		if not bool(row.get("active", false)): continue
		row.active = false
		row.status = "revoked"
		world.sessions[index] = row
		revoked.append(row.duplicate(true))
	return revoked

static func reissue(world: Dictionary, purpose: String, elapsed_minutes: int) -> Dictionary:
	if purpose not in ["billing", "aggregation"]: return {}
	var prior := active_for(world, purpose)
	if not prior.is_empty(): return {}
	var generation := 1
	var device := "BILLING-01" if purpose == "billing" else "BATCH-01"
	var destination := "invoice/BILL-003" if purpose == "billing" else "internal-aggregate"
	for raw in world.get("sessions", []):
		if str(raw.get("purpose", "")) == purpose:
			generation = maxi(generation, int(raw.get("generation", 0)) + 1)
	var number := int(world.get("next_session_number", 204))
	if number > 999: return {}
	var session_id := "SES-%03d" % number
	world.next_session_number = number + 1
	var hour := 9 + int(elapsed_minutes / 60)
	var minute := elapsed_minutes % 60
	var expected_read_rows := 3 if purpose == "billing" else 120
	var row := {"id":session_id,"app_id":"app-19","purpose":purpose,"device":device,"issued_at":"%02d:%02d" % [hour,minute],"issued_minute":elapsed_minutes,"generation":generation,"active":true,"status":"active","expected_destination":destination,"expected_read_rows":expected_read_rows,"approved":true,"issued_record_id":""}
	world.sessions.append(row)
	return row.duplicate(true)

static func view(world: Dictionary, records: Array) -> Dictionary:
	var sessions: Array[Dictionary] = []
	for raw in world.get("sessions", []):
		if not raw is Dictionary: continue
		var row: Dictionary = raw.duplicate(true)
		var latest_inspection: Dictionary = {}
		var latest_probe: Dictionary = {}
		for index in range(records.size() - 1, -1, -1):
			var event: Variant = records[index]
			if not event is Dictionary or str(event.get("data", {}).get("session_id", "")) != str(row.get("id", "")): continue
			if latest_probe.is_empty() and str(event.get("action", "")) == "probe_session": latest_probe = event.duplicate(true)
			if latest_inspection.is_empty() and str(event.get("action", "")) == "inspect_connection": latest_inspection = event.duplicate(true)
		row["latest_inspection"] = latest_inspection
		row["latest_probe"] = latest_probe
		row["observed_destination"] = str(latest_inspection.get("data", {}).get("destination", ""))
		row["observed_read_rows"] = int(latest_inspection.get("data", {}).get("read_rows", -1))
		# The private target is only exposed after a real inspection record exists.
		row.erase("expected_destination")
		row.erase("expected_read_rows")
		row.erase("approved")
		sessions.append(row)
	return {"version":VERSION,"consent":world.get("consent", {}).duplicate(true),"sessions":sessions,"next_session_number":int(world.get("next_session_number", 204))}

static func advance(state: Dictionary, minutes: int) -> Dictionary:
	var events: Array[Dictionary] = []
	if minutes <= 0: return {"impact_cost":0,"events":events}
	var start := int(state.get("elapsed_minutes", 0))
	var finish := start + minutes
	var world: Dictionary = state.get("session_case", {})
	if not validate(world): return {"impact_cost":0,"events":events}
	var schedule: Array = state.get("egress", {}).get("schedule", [])
	var exported: Array = state.get("egress", {}).get("exported_rows", [])
	var impact_cost := 0
	for index in schedule.size():
		var item: Dictionary = schedule[index]
		if str(item.get("status", "")) != "scheduled" or int(item.get("due_minute", 0)) > finish: continue
		var session := get_session(world, str(item.get("session_id", THREAT_SESSION_ID)))
		var allowed := not session.is_empty() and bool(session.get("active", false)) and bool(world.get("consent", {}).get("enabled", false))
		var rows: Array[Dictionary] = []
		if allowed:
			for raw in EXPORT_ROWS:
				var copy: Dictionary = raw.duplicate(true)
				copy["sync_copy_id"] = "%s-%s" % [str(item.get("id", "")), str(raw.get("id", ""))]
				rows.append(copy)
				exported.append({"sync_id":str(item.get("id", "")),"minute":int(item.get("due_minute", finish)),"record_id":"","row":copy.duplicate(true)})
			impact_cost += rows.size() * 500
		var event_data := {"sync_id":str(item.get("id", "")),"destination":"external-storage","session_id":str(item.get("session_id", THREAT_SESSION_ID)),"rows":rows.duplicate(true),"row_ids":rows.map(func(row): return str(row.get("id", ""))),"world_revision":int(state.get("world_revision", 0))}
		item["status"] = "sent" if allowed else "blocked"
		item["row_count"] = rows.size()
		item["session_id"] = str(item.get("session_id", THREAT_SESSION_ID))
		item["world_revision"] = int(state.get("world_revision", 0))
		schedule[index] = item
		events.append({"sync_id":str(item.get("id", "")),"minute":int(item.get("due_minute", finish)),"status":200 if allowed else 403,"session_id":str(item.session_id),"data":event_data})
	var egress: Dictionary = state.get("egress", {})
	egress["schedule"] = schedule
	egress["exported_rows"] = exported
	egress["impact_cost"] = int(egress.get("impact_cost", 0)) + impact_cost
	state["egress"] = egress
	return {"impact_cost":impact_cost,"events":events}

static func bind_sync_record(state: Dictionary, sync_id: String, record_id: String) -> void:
	var egress: Dictionary = state.get("egress", {})
	var schedule: Array = egress.get("schedule", [])
	for index in schedule.size():
		if str(schedule[index].get("id", "")) == sync_id:
			schedule[index]["record_id"] = record_id
		for row in egress.get("exported_rows", []):
			if str(row.get("sync_id", "")) == sync_id: row["record_id"] = record_id
	egress["schedule"] = schedule
	state["egress"] = egress
