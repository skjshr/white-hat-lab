extends RefCounted

# Calendar estimates for existing work, never a promise that a customer can be
# delivered. This helper must not activate VMs, save, or reserve new work.
const COPY = preload("res://scripts/ui_theme.gd")

static func _member(g, id: String) -> Dictionary:
	for member in g.team_members():
		if str(member.id) == id: return member
	return {}

static func _limited(id: String) -> bool:
	return id not in ["aya", "ren"]

static func _shift(g, id: String, day: int) -> Dictionary:
	var staff: Dictionary = g.state.get("staff", {}).get(id, {})
	var key := str(staff.get("shift", "day"))
	if day > int(g.state.day) and not str(staff.get("pending_shift", "")).is_empty():
		key = str(staff.pending_shift)
	for shift in g.staff_shift_catalog():
		if str(shift.id) == key: return shift
	return {"id":key, "start":540, "end":1080}

static func _remaining(g, job: Dictionary) -> float:
	return maxf(0.0, g._crew_minutes(job) * clampf(float(job.get("remaining", 0.0)) / maxf(0.001, float(job.get("total", 1.0))), 0.0, 1.0))

static func _deadline(g, job: Dictionary) -> Dictionary:
	# Maintenance is settled when the player ends the day, with no fixed hour.
	if str(job.get("kind", "normal")) == "maintenance":
		return {"day":int(g.state.day), "minute":-1, "absolute":-1}
	var id := str(job.get("contract_id", ""))
	var context: Dictionary = g.state.get("contract_contexts", {}).get(id, {})
	if id == str(g.state.get("current_contract_id", "")): context = g._context_from_projection()
	if context.is_empty(): return {"day":-1, "minute":-1, "absolute":-1}
	var contract: Dictionary = context.get("contract", {})
	var budget := float(contract.get("agreed_budget", 0.0))
	if budget <= 0:
		budget = float(g._contract_budget(int(context.get("chapter", 0)), context.get("targets", []).size(), contract.get("target_specs", []), str(context.get("contract_plan", "standard"))).budget)
	var work: Dictionary = context.get("work", {})
	var absolute := int(work.get("started_day", g.state.day)) * 1440 + int(work.get("started_at", 540)) + roundi(budget)
	return {"day":floori(float(absolute) / 1440.0), "minute":posmod(absolute, 1440), "absolute":absolute}

static func _waiting_for_observer(g, id: String, job: Dictionary) -> bool:
	if g.colleague_role(id) != "ren" or str(job.get("kind", "normal")) != "normal": return false
	var candidates: Array = []
	for owner in g._assignments:
		if owner != id and g.colleague_role(str(owner)) == "aya":
			var active: Dictionary = g._assignments[owner]
			if str(active.get("status", "")) == "working": candidates.append(active)
	for owner in g.state.get("dispatch_queues", {}):
		if g.colleague_role(str(owner)) == "aya": candidates.append_array(g.state.dispatch_queues[owner])
	for observation in candidates:
		if str(observation.get("kind", "normal")) == "normal" and str(observation.get("contract_id", "")) == str(job.get("contract_id", "")) and int(observation.get("target_index", -1)) == int(job.get("target_index", -2)):
			return true
	return false

static func _blocker(g, id: String, job: Dictionary, active: bool, day: int) -> String:
	if _member(g, id).is_empty(): return "staffing_inactive"
	if not active:
		var check_job := job.duplicate(true)
		check_job.member_id = id
		var invalid: String = g._dispatch_reason(check_job, false)
		if not invalid.is_empty(): return invalid
		if bool(g.state.get("dispatch_holds", {}).get(id, false)): return "dispatch_hold"
	if str(job.get("kind", "normal")) == "normal" and not g._colleague_hardware_connected(job): return "stock_error_hardware"
	if _waiting_for_observer(g, id, job): return "dispatch_waiting"
	# An employee who is off shift now can still arrive for a future shift.
	# Returning from a break during today's work has no known calendar ETA.
	var shift := _shift(g, id, int(g.state.day))
	var on_shift: bool = not _limited(id) or (g.clock_minutes() >= int(shift.start) and g.clock_minutes() < int(shift.end))
	if (active or (day == int(g.state.day) and on_shift)) and not bool(g.colleague_runtime_availability(id).available):
		return "care_maintenance_unavailable" if str(job.get("kind", "normal")) == "maintenance" else "npc_returning"
	return ""

static func _slot(g, id: String, cursor: Dictionary, minutes: float) -> Dictionary:
	var out := cursor.duplicate()
	if not _limited(id): return out
	for _attempt in 3:
		var shift := _shift(g, id, int(out.day))
		out.minute = maxf(float(out.minute), float(shift.start))
		var room := float(shift.end) - float(out.minute)
		var budget := float(shift.end) - float(shift.start) - float(out.used)
		if minutes <= room + 0.00001 and minutes <= budget + 0.00001: return out
		out.day = int(out.day) + 1
		out.minute = float(_shift(g, id, int(out.day)).start)
		out.used = 0.0
	out.blocked = "staffing_capacity_used"
	return out

static func _job(g, id: String, raw: Dictionary, cursor: Dictionary, active: bool) -> Dictionary:
	var minutes := _remaining(g, raw)
	var slot := cursor.duplicate() if active else _slot(g, id, cursor, minutes)
	var reason := _blocker(g, id, raw, active, int(slot.day))
	if reason.is_empty(): reason = str(cursor.get("blocked", ""))
	if reason.is_empty(): reason = str(slot.get("blocked", ""))
	var start_abs := int(slot.day) * 1440 + float(slot.minute)
	var finish_abs := start_abs + minutes
	var budget_minutes := minutes
	if active:
		# Game advances the global clock at pause/finish using this anchor. The
		# elapsed animation seconds need not match the already advanced clock.
		budget_minutes = maxf(0.0, g._crew_minutes(raw) - float(raw.get("work_minutes_accounted", 0.0)))
		if raw.has("work_started_at"):
			var anchored_finish := int(raw.get("work_started_day", g.state.day)) * 1440 + float(raw.work_started_at) + float(raw.get("segment_minutes", budget_minutes))
			finish_abs = maxf(start_abs, anchored_finish)
	var deadline := _deadline(g, raw)
	var finish_rounded := ceili(finish_abs - 0.00001)
	var late := maxi(0, finish_rounded - int(deadline.absolute)) if int(deadline.absolute) >= 0 else 0
	return {
		"id":str(raw.get("id", "")), "kind":str(raw.get("kind", "normal")), "status":str(raw.get("status", "queued")),
		"contract_id":str(raw.get("contract_id", "")), "target_index":int(raw.get("target_index", 0)), "client":str(raw.get("client", "")),
		"start_day":floori(start_abs / 1440.0) if reason.is_empty() else -1,
		"start_minute":posmod(ceili(start_abs), 1440) if reason.is_empty() else -1,
		"finish_day":floori(float(finish_rounded) / 1440.0) if reason.is_empty() else -1,
		"finish_minute":posmod(finish_rounded, 1440) if reason.is_empty() else -1,
		"remaining_minutes":minutes, "budget_minutes":budget_minutes,
		"used_after":float(slot.used) + budget_minutes,
		"deadline_day":int(deadline.day), "deadline_minute":int(deadline.minute), "late_minutes":late if reason.is_empty() else 0,
		"risk":"blocked" if not reason.is_empty() else "late" if late > 0 else "on_track", "blocked_reason":reason
	}

static func _walk(g, id: String, extra: Dictionary = {}) -> Dictionary:
	var member := _member(g, id)
	var today := int(g.state.day)
	var now := int(g.clock_minutes())
	var shift := _shift(g, id, today)
	var staff: Dictionary = g.state.get("staff", {}).get(id, {})
	var used := float(staff.get("minutes_used", 0.0)) if int(staff.get("minutes_day", -1)) == today else 0.0
	var cursor := {"day":today, "minute":float(now), "used":used, "blocked":""}
	var inputs: Array = []
	var active: Dictionary = g._assignments.get(id, {})
	if str(active.get("status", "")) == "working": inputs.append(active)
	inputs.append_array(g.state.get("dispatch_queues", {}).get(id, []))
	if not extra.is_empty(): inputs.append(extra)
	var jobs: Array = []
	var reserved := 0.0
	var today_budget := 0.0
	var today_remaining := 0.0
	var overflow := 0.0
	for index in inputs.size():
		var raw: Dictionary = inputs[index]
		var is_active := index == 0 and str(raw.get("status", "")) == "working"
		var planned := _job(g, id, raw, cursor, is_active)
		jobs.append(planned)
		reserved += float(planned.remaining_minutes)
		if not str(planned.blocked_reason).is_empty():
			cursor.blocked = str(planned.blocked_reason)
			continue
		if int(planned.start_day) == today:
			today_budget += float(planned.budget_minutes)
			today_remaining += float(planned.remaining_minutes)
		else: overflow += float(planned.remaining_minutes)
		cursor = {"day":int(planned.finish_day), "minute":float(planned.finish_minute), "used":float(planned.used_after), "blocked":""}
	var capacity := -1.0
	var available := -1.0
	if _limited(id):
		capacity = maxf(0.0, minf(float(shift.end) - maxf(now, float(shift.start)), float(shift.end) - float(shift.start) - used))
		# Calendar room after scheduled work and the daily labor budget are
		# independent limits. Never subtract prior labor from both of them.
		var finish_today := float(cursor.minute) if int(cursor.day) == today and str(cursor.blocked).is_empty() else maxf(now, float(shift.start)) + today_remaining
		available = maxf(0.0, minf(float(shift.end) - finish_today, float(shift.end) - float(shift.start) - used - today_budget))
		if not str(cursor.blocked).is_empty(): available = -1.0
	return {
		"member":id, "name":str(member.get("name", id)), "role":str(member.get("role", "")), "shift":str(shift.id),
		"shift_start":int(shift.start), "shift_end":int(shift.end), "day":today, "clock_minute":now,
		"capacity_minutes":capacity, "used_minutes":used, "reserved_minutes":reserved, "available_minutes":available,
		"scheduled_today_minutes":today_remaining, "overflow_minutes":overflow,
		"held":bool(g.state.get("dispatch_holds", {}).get(id, false)), "blocked_reason":str(cursor.blocked), "jobs":jobs
	}

static func workload(g, id: String) -> Dictionary:
	return _walk(g, id)

static func quote(g, id: String, contract_id: String, target_index: int, kind: String = "normal", client: String = "") -> Dictionary:
	var duration := (8.0 if g.colleague_role(id) == "maintenance" else 12.0) if kind == "maintenance" else float(g.team_work_duration(id))
	var raw := {"id":"forecast", "member_id":id, "kind":kind, "contract_id":contract_id, "target_index":target_index, "client":client, "status":"queued", "remaining":duration, "total":duration, "work_minutes":duration, "minutes":duration}
	var planned := _walk(g, id, raw)
	var job: Dictionary = planned.jobs.back()
	return {"member":id, "kind":kind, "contract_id":contract_id, "target_index":target_index, "client":client, "duration_minutes":duration, "blocked_reason":str(job.blocked_reason), "job":job, "workload":_walk(g, id)}
