extends RefCounted
## Read-only calendar projection over company_workday's saved jobs/forecasts.

const PRIORITY_CASE := "advanced-saas-priority"
const PRIORITY_ANCHOR_MINUTE := "priority_company_clock_anchor_minute"
const PRIORITY_ANCHOR_ELAPSED := "priority_company_clock_anchor_elapsed"
const AXIS_HORIZON_MINUTES := 360

static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _array(value: Variant) -> Array:
	return value if value is Array else []

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _absolute(day: Variant, minute: Variant) -> int:
	if not _number(day) or not _number(minute): return -1
	if int(day) < 0 or int(minute) < 0 or int(minute) >= 1440: return -1
	return int(day) * 1440 + int(minute)

static func _context_for(state: Dictionary, id: String) -> Dictionary:
	var contexts := _dict(state.get("contract_contexts", {}))
	var context := _dict(contexts.get(id, {})).duplicate(true)
	# The current projection is the authoritative copy while this contract is active.
	if id == str(state.get("current_contract_id", "")) and bool(state.get("accepted", false)):
		var contract := _dict(context.get("contract", {})).duplicate(true)
		if state.get("contract", {}) is Dictionary: contract = state.contract.duplicate(true)
		context.contract = contract
		for key in ["accepted", "work", "advanced", "targets", "chapter", "contract_plan"]:
			if state.has(key): context[key] = state[key].duplicate(true) if state[key] is Dictionary or state[key] is Array else state[key]
		context.id = id
	return context

static func _business_markers(job: Dictionary, context: Dictionary, now_absolute: int) -> Array:
	var result: Array = []
	var business := _dict(job.get("business", {}))
	if business.is_empty(): return result
	var contract := _dict(context.get("contract", {}))
	if str(contract.get("case_id", "")) != PRIORITY_CASE: return result
	var queues: Variant = business.get("queues", null)
	if not queues is Array: return result
	var work := _dict(context.get("work", {}))
	var anchor_valid := _number(work.get(PRIORITY_ANCHOR_MINUTE, null)) and _number(work.get(PRIORITY_ANCHOR_ELAPSED, null)) and int(work.get(PRIORITY_ANCHOR_MINUTE, -1)) >= 0 and int(work.get(PRIORITY_ANCHOR_ELAPSED, -1)) >= 0
	var zero_absolute := int(work.get(PRIORITY_ANCHOR_MINUTE, 0)) - int(work.get(PRIORITY_ANCHOR_ELAPSED, 0)) if anchor_valid else -1
	for raw in queues:
		if not raw is Dictionary: continue
		var queue: Dictionary = raw
		# priority_business_brief is the source projection. Its public queue
		# fields are `deadline`, `late_cost`, and `late` (not engine field names).
		var relative: Variant = queue.get("deadline", queue.get("deadline_minute", null))
		var known := anchor_valid and _number(relative) and int(relative) >= 0
		var absolute := zero_absolute + int(relative) if known else -1
		var actual_cost := int(queue.get("loss_cost", 0)) if _number(queue.get("loss_cost", null)) else -1
		var potential_cost := int(queue.get("late_compensation", queue.get("late_cost", -1))) if _number(queue.get("late_compensation", queue.get("late_cost", null))) else -1
		result.append({
			"kind":"business",
			"label":str(queue.get("label", "受付期限")),
			"absolute":absolute,
			"known":known,
			"late":bool(queue.get("late", queue.get("already_late", false))),
			"received":bool(queue.get("received", false)),
			"cost":actual_cost,
			"late_cost":potential_cost,
			"id":str(queue.get("id", "")),
			"relative_minute":int(relative) if _number(relative) else -1,
			"now_absolute":now_absolute
		})
	return result

static func _matches(job: Dictionary, forecast: Dictionary) -> bool:
	var kind := str(job.get("kind", ""))
	var forecast_kind := str(forecast.get("kind", ""))
	if kind == "maintenance":
		return forecast_kind == "maintenance" and str(forecast.get("client", "")) == str(job.get("client", ""))
	if forecast_kind != "normal": return false
	if str(forecast.get("contract_id", "")) != str(job.get("contract_id", job.get("id", ""))): return false
	if int(forecast.get("target_index", -999)) != int(job.get("target", -1)): return false
	return kind in ["normal", "emergency"]

static func _segments(job: Dictionary, people: Array) -> Array:
	var out: Array = []
	if bool(job.get("completed", false)) or bool(job.get("draft", false)): return out
	for person_value in people:
		if not person_value is Dictionary: continue
		var person: Dictionary = person_value
		var workload := _dict(person.get("workload", {}))
		for raw in _array(workload.get("jobs", [])):
			if not raw is Dictionary: continue
			var forecast: Dictionary = raw
			if not _matches(job, forecast): continue
			var start := _absolute(forecast.get("start_day", -1), forecast.get("start_minute", -1))
			var finish := _absolute(forecast.get("finish_day", -1), forecast.get("finish_minute", -1))
			var reason := str(forecast.get("blocked_reason", ""))
			var known := start >= 0 and finish >= 0 and reason.is_empty() and str(forecast.get("risk", "")) != "blocked"
			out.append({
				"member":str(person.get("id", forecast.get("member", ""))),
				"name":str(person.get("name", forecast.get("name", ""))),
				"start_absolute":start if known else -1,
				"finish_absolute":finish if known else -1,
				"known":known,
				"status":str(forecast.get("status", "unknown")),
				"risk":str(forecast.get("risk", "unknown")),
				"blocked_reason":reason
			})
	return out

static func _status_label(job: Dictionary) -> String:
	if str(job.get("status", "")) == "legacy": return "従来型契約"
	if bool(job.get("draft", false)): return "請求待ち"
	if bool(job.get("completed", false)): return "点検完了" if str(job.get("kind", "")) == "maintenance" else "納品済み"
	var handoff := _dict(job.get("handoff", {}))
	if not _array(handoff.get("receipts", [])).is_empty() and str(job.get("status", "")) not in ["working", "queued", "paused"]:
		return "納品確認" if str(_dict(handoff.get("acceptance", {})).get("state", "")) == "ready" else "引継ぎ待ち"
	return {"ready":"検査済", "working":"対応中", "queued":"配分済", "paused":"中断", "pending":"対応待ち", "late":"期限超過"}.get(str(job.get("status", "")), "未完了")

static func build(state: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not snapshot.has("day") or not snapshot.has("clock_minute") or not snapshot.get("jobs", null) is Array:
		return {"available":false,"day":-1,"now_absolute":-1,"axis_start":-1,"axis_end":-1,"rows":[]}
	var day := int(snapshot.get("day", -1))
	var minute := int(snapshot.get("clock_minute", -1))
	if day < 0 or minute < 0 or minute >= 1440:
		return {"available":false,"day":day,"now_absolute":-1,"axis_start":-1,"axis_end":-1,"rows":[]}
	var now_absolute := day * 1440 + minute
	var rows: Array = []
	var furthest := now_absolute
	for raw in snapshot.get("jobs", []):
		if not raw is Dictionary: continue
		var job: Dictionary = raw
		var id := str(job.get("contract_id", job.get("id", "")))
		var context := _context_for(state, id)
		var completed := bool(job.get("completed", false))
		var draft := bool(job.get("draft", false))
		var deadline := -1 if completed or draft else int(_dict(job.get("deadline", {})).get("absolute", -1))
		if deadline < 0: deadline = -1
		var markers: Array = []
		if not completed and not draft:
			if deadline >= 0:
				markers.append({"kind":"delivery","label":str(_dict(job.get("deadline", {})).get("text", job.get("deadline_text", "納品期限"))),"absolute":deadline,"known":true,"late":int(job.get("late_minutes", 0)) > 0 or deadline < now_absolute,"received":false,"cost":-1})
			markers.append_array(_business_markers(job, context, now_absolute))
		var segments := _segments(job, _array(snapshot.get("people", [])))
		for marker in markers:
			if bool(marker.get("known", false)): furthest = maxi(furthest, int(marker.get("absolute", -1)))
		for segment in segments:
			if bool(segment.get("known", false)): furthest = maxi(furthest, int(segment.get("finish_absolute", -1)))
		var title := str(job.get("title", ""))
		if int(job.get("target_count", 0)) > 1 and not str(job.get("target_name", "")).is_empty():
			title += " / " + str(job.target_name)
		rows.append({
			"key":str(job.get("key", "")),
			"client":str(job.get("client", "")),
			"title":title,
			"kind":str(job.get("kind", "unknown")),
			"status":str(job.get("status", "unknown")),
			"status_label":_status_label(job),
			"completed":completed,
			"draft":draft,
			"fee":int(job.get("fee", -1)),
			"deadline_absolute":deadline,
			"deadline_text":str(_dict(job.get("deadline", {})).get("text", "")),
			"markers":markers,
			"segments":segments
		})
	var span := clampi(ceili(float(maxi(0, furthest - now_absolute)) / 30.0) * 30, 60, AXIS_HORIZON_MINUTES)
	var axis_end := now_absolute + span
	return {"available":true,"day":day,"now_absolute":now_absolute,"axis_start":now_absolute,"axis_end":axis_end,"rows":rows}
