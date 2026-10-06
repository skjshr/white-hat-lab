extends RefCounted
## Per-connection state for the selective SaaS session response case.

const VERSION := 2
const LEGACY_VERSION := 1
const BUSINESS_VERSION := 1
const THREAT_SESSION_ID := "SES-203"
const BUSINESS_JOB_DEFS := [
	{"id":"BILL-RUN-01","purpose":"billing","label":"請求予約","units":6,"unit":"件","release_minute":8,"deadline_minute":12,"penalty":900},
	{"id":"DISPATCH-01","purpose":"aggregation","label":"配車集計","units":120,"unit":"行","release_minute":8,"deadline_minute":10,"penalty":1600}
]
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
		"business":{"version":BUSINESS_VERSION,"jobs":_new_business_jobs(),"loss_cost":0},
		"sessions":[
			{"id":"SES-201","app_id":"app-19","purpose":"billing","device":"BILLING-01","issued_at":"08:50","issued_minute":0,"generation":1,"active":true,"status":"active","expected_destination":"invoice/BILL-003","expected_read_rows":3,"approved":true,"issued_record_id":""},
			{"id":"SES-202","app_id":"app-19","purpose":"aggregation","device":"BATCH-01","issued_at":"08:55","issued_minute":0,"generation":1,"active":true,"status":"active","expected_destination":"internal-aggregate","expected_read_rows":120,"approved":true,"issued_record_id":""},
			{"id":"SES-203","app_id":"app-19","purpose":"connection","device":"SYNC-NODE","issued_at":"09:00","issued_minute":0,"generation":1,"active":true,"status":"active","expected_destination":"external-storage","expected_read_rows":3,"approved":false,"issued_record_id":""}
		]
	}

static func _new_business_jobs() -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for definition in BUSINESS_JOB_DEFS:
		var row: Dictionary = definition.duplicate(true)
		row.merge({"status":"scheduled","queued_minute":-1,"completed_minute":-1,"used_session_id":"","loss_charged":false,"loss_amount":0,"record_id":"","queued_record_id":"","loss_record_id":""}, true)
		jobs.append(row)
	return jobs

static func validate(world: Variant, elapsed_minutes: int = -1) -> bool:
	if not world is Dictionary or not _whole(world.get("version", null), LEGACY_VERSION, VERSION): return false
	var world_version := int(world.version)
	var consent: Variant = world.get("consent", null)
	if not consent is Dictionary or str(consent.get("app_id", "")) != "app-19" or typeof(consent.get("enabled", null)) != TYPE_BOOL: return false
	if str(consent.get("approved_change", "")) != "FIN-114" or not _whole(consent.get("revision", null), 0, 2147483647): return false
	var sessions: Variant = world.get("sessions", null)
	if not sessions is Array or sessions.size() < 3 or sessions.size() > 64: return false
	var sessions_array: Array = sessions
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
	if world_version == LEGACY_VERSION:
		# Existing accepted v1 contexts retain their original schema and behavior.
		return not world.has("business")
	return _validate_business(world.get("business", null), sessions_array, elapsed_minutes)

static func _validate_business(value: Variant, sessions: Array, elapsed_minutes: int) -> bool:
	if not value is Dictionary or not _whole(value.get("version", null), BUSINESS_VERSION, BUSINESS_VERSION): return false
	var jobs: Variant = value.get("jobs", null)
	if not jobs is Array or jobs.size() != BUSINESS_JOB_DEFS.size(): return false
	if not _whole(value.get("loss_cost", null), 0, 2147483647): return false
	var expected_loss := 0
	for index in BUSINESS_JOB_DEFS.size():
		var definition: Dictionary = BUSINESS_JOB_DEFS[index]
		var job: Variant = jobs[index]
		if not job is Dictionary: return false
		for key in ["id", "purpose", "label", "units", "unit", "release_minute", "deadline_minute", "penalty"]:
			if job.get(key, null) != definition[key]: return false
		if str(job.get("status", "")) not in ["scheduled", "queued", "completed"]: return false
		if not _whole(job.get("queued_minute", null), -1, 2147483647) or not _whole(job.get("completed_minute", null), -1, 2147483647): return false
		if not job.get("used_session_id", null) is String or not job.get("record_id", null) is String or not job.get("queued_record_id", null) is String or not job.get("loss_record_id", null) is String: return false
		if typeof(job.get("loss_charged", null)) != TYPE_BOOL or not _whole(job.get("loss_amount", null), 0, int(definition.penalty)): return false
		if bool(job.loss_charged) != (int(job.loss_amount) == int(definition.penalty)): return false
		if bool(job.loss_charged):
			if str(job.loss_record_id).is_empty(): return false
			expected_loss += int(job.loss_amount)
		elif not str(job.loss_record_id).is_empty():
			return false
		var status := str(job.status)
		if status == "scheduled":
			if int(job.queued_minute) != -1 or int(job.completed_minute) != -1 or not str(job.record_id).is_empty() or not str(job.queued_record_id).is_empty() or not str(job.used_session_id).is_empty() or bool(job.loss_charged): return false
		elif status == "queued":
			if int(job.queued_minute) < int(definition.release_minute) or int(job.completed_minute) != -1 or str(job.queued_record_id).is_empty() or not str(job.record_id).is_empty() or not str(job.used_session_id).is_empty(): return false
			if elapsed_minutes >= int(definition.deadline_minute) + 1 and not bool(job.loss_charged): return false
			if bool(job.loss_charged) and elapsed_minutes >= 0 and elapsed_minutes < int(definition.deadline_minute) + 1: return false
		else:
			if int(job.queued_minute) != -1 and int(job.queued_minute) < int(definition.release_minute): return false
			if int(job.completed_minute) < int(definition.release_minute) or str(job.record_id).is_empty() or str(job.used_session_id).is_empty(): return false
			if not _has_session(sessions, str(job.used_session_id), str(definition.purpose)): return false
			if not bool(job.loss_charged) and int(job.completed_minute) > int(definition.deadline_minute): return false
			if bool(job.loss_charged) and int(job.completed_minute) <= int(definition.deadline_minute): return false
			if int(job.queued_minute) >= 0 and str(job.queued_record_id).is_empty(): return false
			if int(job.queued_minute) < 0 and not str(job.queued_record_id).is_empty(): return false
			if elapsed_minutes >= 0 and int(job.completed_minute) > elapsed_minutes: return false
		if elapsed_minutes >= int(definition.release_minute) and status == "scheduled": return false
	if int(value.loss_cost) != expected_loss: return false
	return true

static func _has_session(sessions: Array, session_id: String, purpose: String) -> bool:
	for row in sessions:
		if str(row.get("id", "")) == session_id and str(row.get("purpose", "")) == purpose: return true
	return false

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

static func view(world: Dictionary, records: Array, elapsed_minutes: int = 0) -> Dictionary:
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
	var projection := {"version":int(world.get("version", LEGACY_VERSION)),"consent":world.get("consent", {}).duplicate(true),"sessions":sessions,"next_session_number":int(world.get("next_session_number", 204))}
	if int(world.get("version", LEGACY_VERSION)) >= VERSION:
		projection["business"] = business_view(world, elapsed_minutes)
	return projection

static func advance(state: Dictionary, minutes: int) -> Dictionary:
	var events: Array[Dictionary] = []
	if minutes <= 0: return {"impact_cost":0,"events":events}
	var start := int(state.get("elapsed_minutes", 0))
	var finish := start + minutes
	var world: Dictionary = state.get("session_case", {})
	if not validate(world, start): return {"impact_cost":0,"events":events}
	var world_version := int(world.get("version", LEGACY_VERSION))
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
		var sync_event := {"sync_id":str(item.get("id", "")),"minute":int(item.get("due_minute", finish)),"status":200 if allowed else 403,"session_id":str(item.session_id),"data":event_data}
		if world_version >= VERSION: sync_event["event_kind"] = "egress"
		events.append(sync_event)
	var egress: Dictionary = state.get("egress", {})
	egress["schedule"] = schedule
	egress["exported_rows"] = exported
	egress["impact_cost"] = int(egress.get("impact_cost", 0)) + impact_cost
	state["egress"] = egress
	if world_version < VERSION: return {"impact_cost":impact_cost,"events":events}
	var business_result := _advance_business(world, start, finish, int(state.get("world_revision", 0)))
	var business_events: Array = business_result.get("events", [])
	for event in business_events: events.append(event)
	events.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_minute := int(a.get("minute", 0))
		var b_minute := int(b.get("minute", 0))
		if a_minute != b_minute: return a_minute < b_minute
		var a_kind := str(a.get("event_kind", "egress"))
		var b_kind := str(b.get("event_kind", "egress"))
		if a_kind != b_kind: return a_kind == "business"
		var a_id := str(a.get("job_id", a.get("sync_id", "")))
		var b_id := str(b.get("job_id", b.get("sync_id", "")))
		return a_id < b_id
	)
	return {"impact_cost":impact_cost + int(business_result.get("impact_cost", 0)),"egress_cost":impact_cost,"business_cost":int(business_result.get("impact_cost", 0)),"events":events}

static func _advance_business(world: Dictionary, start: int, finish: int, world_revision: int) -> Dictionary:
	var business: Dictionary = world.get("business", {})
	var jobs: Array = business.get("jobs", [])
	var events: Array[Dictionary] = []
	var loss_added := 0
	var consent_enabled := bool(world.get("consent", {}).get("enabled", false))
	for index in jobs.size():
		var job: Dictionary = jobs[index]
		var status := str(job.get("status", ""))
		var release := int(job.get("release_minute", 0))
		var deadline := int(job.get("deadline_minute", 0))
		var required_purpose := str(job.get("purpose", ""))
		var active_session: Dictionary = active_for(world, required_purpose)
		var can_run := consent_enabled and not active_session.is_empty()
		if status == "scheduled":
			if release > finish: continue
			if can_run:
				var completion_minute := maxi(start, release)
				if completion_minute > deadline and not bool(job.get("loss_charged", false)) and deadline + 1 <= finish:
					loss_added += _charge_job_loss(job, business, deadline + 1, world_revision, events)
				_complete_job(job, active_session, completion_minute, world_revision, events)
			else:
				job["status"] = "queued"
				job["queued_minute"] = release
				job["queued_record_id"] = ""
				events.append(_business_event("business_job_queued", 202, job, release, world_revision, {"session_active":false,"consent_enabled":consent_enabled}))
				if deadline + 1 <= finish:
					loss_added += _charge_job_loss(job, business, deadline + 1, world_revision, events)
		elif status == "queued":
			if can_run:
				var completion_minute := start + 1
				if completion_minute > deadline and not bool(job.get("loss_charged", false)):
					loss_added += _charge_job_loss(job, business, deadline + 1, world_revision, events)
				_complete_job(job, active_session, completion_minute, world_revision, events)
			elif deadline + 1 <= finish and not bool(job.get("loss_charged", false)):
				loss_added += _charge_job_loss(job, business, deadline + 1, world_revision, events)
		jobs[index] = job
	business["jobs"] = jobs
	world["business"] = business
	return {"events":events,"impact_cost":loss_added}

static func _business_event(action: String, status: int, job: Dictionary, minute: int, world_revision: int, extra: Dictionary = {}) -> Dictionary:
	var data := {"job_id":str(job.get("id", "")),"purpose":str(job.get("purpose", "")),"label":str(job.get("label", "")),"units":int(job.get("units", 0)),"unit":str(job.get("unit", "")),"release_minute":int(job.get("release_minute", 0)),"deadline_minute":int(job.get("deadline_minute", 0)),"event_minute":minute,"loss_charged":bool(job.get("loss_charged", false)),"loss_amount":int(job.get("loss_amount", 0)),"world_revision":world_revision}
	for key in extra: data[key] = extra[key]
	return {"event_kind":"business","action":action,"status":status,"minute":minute,"job_id":str(job.get("id", "")),"data":data}

static func _charge_job_loss(job: Dictionary, business: Dictionary, minute: int, world_revision: int, events: Array[Dictionary]) -> int:
	if bool(job.get("loss_charged", false)): return 0
	var amount := int(job.get("penalty", 0))
	job["loss_charged"] = true
	job["loss_amount"] = amount
	business["loss_cost"] = int(business.get("loss_cost", 0)) + amount
	events.append(_business_event("business_job_overdue", 408, job, minute, world_revision, {"penalty":amount}))
	return amount

static func _complete_job(job: Dictionary, active_session: Dictionary, minute: int, world_revision: int, events: Array[Dictionary]) -> void:
	job["status"] = "completed"
	job["completed_minute"] = minute
	job["used_session_id"] = str(active_session.get("id", ""))
	job["record_id"] = ""
	events.append(_business_event("business_job_completed", 200, job, minute, world_revision, {"used_session_id":str(active_session.get("id", ""))}))

static func bind_business_record(world: Dictionary, job_id: String, action: String, record_id: String) -> void:
	var business: Dictionary = world.get("business", {})
	var jobs: Array = business.get("jobs", [])
	for index in jobs.size():
		if str(jobs[index].get("id", "")) != job_id: continue
		if action == "business_job_completed": jobs[index]["record_id"] = record_id
		elif action == "business_job_queued": jobs[index]["queued_record_id"] = record_id
		elif action == "business_job_overdue": jobs[index]["loss_record_id"] = record_id
	business["jobs"] = jobs
	world["business"] = business

static func business_view(world: Dictionary, elapsed_minutes: int) -> Dictionary:
	var business: Dictionary = world.get("business", {})
	var jobs: Array[Dictionary] = []
	var completed := 0
	var queued := 0
	for raw in business.get("jobs", []):
		if not raw is Dictionary: continue
		var row: Dictionary = raw.duplicate(true)
		if str(row.get("status", "")) == "completed": completed += 1
		elif str(row.get("status", "")) == "queued": queued += 1
		jobs.append(row)
	return {"version":int(business.get("version", BUSINESS_VERSION)),"jobs":jobs,"loss_cost":int(business.get("loss_cost", 0)),"completed_count":completed,"queued_count":queued,"total_count":jobs.size(),"elapsed_minutes":elapsed_minutes}

static func business_event_record_ids(world: Variant) -> Array[String]:
	var result: Array[String] = []
	if not world is Dictionary: return result
	var business: Dictionary = world.get("business", {})
	for raw in business.get("jobs", []):
		if not raw is Dictionary: continue
		for key in ["queued_record_id", "record_id", "loss_record_id"]:
			var record_id := str(raw.get(key, ""))
			if not record_id.is_empty() and record_id not in result: result.append(record_id)
	return result

static func business_snapshot_matches(snapshot: Variant, world: Dictionary) -> bool:
	if not snapshot is Dictionary: return false
	var expected: Dictionary = business_view(world, int(snapshot.get("elapsed_minutes", 0)))
	if int(snapshot.get("version", -1)) != int(expected.version) or int(snapshot.get("loss_cost", -1)) != int(expected.loss_cost): return false
	var snapshot_jobs: Variant = snapshot.get("jobs", null)
	if not snapshot_jobs is Array or snapshot_jobs.size() != expected.jobs.size(): return false
	var fields := ["id", "purpose", "status", "release_minute", "deadline_minute", "queued_minute", "completed_minute", "used_session_id", "loss_charged", "loss_amount", "record_id", "queued_record_id", "loss_record_id"]
	for index in expected.jobs.size():
		var expected_job: Dictionary = expected.jobs[index]
		var saved_job: Variant = snapshot_jobs[index]
		if not saved_job is Dictionary: return false
		for key in fields:
			if saved_job.get(key, null) != expected_job.get(key, null): return false
	return true

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
