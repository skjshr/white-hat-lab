extends RefCounted
## Read-only hiring and work-fit preview. All APIs that may synchronize state
## run only against a detached Game copy.

const WORKDAY = preload("res://scripts/company_workday.gd")

static func _pick_fields(value: Variant, fields: Array) -> Dictionary:
	if not value is Dictionary: return {}
	var picked := {}
	for field in fields:
		if value.has(field): picked[field] = value[field]
	return picked

static func _target_signature(target_value: Variant) -> Dictionary:
	if not target_value is Dictionary: return {}
	var target: Dictionary = target_value
	var receipts: Array = []
	for receipt in target.get("work_receipts", []):
		if receipt is Dictionary:
			receipts.append(_pick_fields(receipt, ["member_id", "member_name", "role", "phase", "result", "result_path", "revision", "completed_day", "completed_minute", "minutes", "job_id"]))
	return {
		"name":str(target.get("name", "")),
		"case_id":str(target.get("case_id", "")),
		"chapter":int(target.get("chapter", 0)),
		"revision":int(target.get("revision", 0)),
		"validated_revision":int(target.get("validated_revision", -1)),
		"inspected":bool(target.get("inspected", false)),
		"checks":target.get("checks", []),
		"last_acceptance":_pick_fields(target.get("last_acceptance", {}), ["revision", "checks", "inspected", "validated_revision"]),
		"work_receipts":receipts
	}

static func _targets_signature(value: Variant) -> Array:
	var result: Array = []
	if not value is Array: return result
	for target in value: result.append(_target_signature(target))
	return result

static func _context_signature(context_value: Variant) -> Dictionary:
	if not context_value is Dictionary: return {}
	var context: Dictionary = context_value
	var work: Dictionary = context.get("work", {}) if context.get("work", {}) is Dictionary else {}
	return {
		"id":str(context.get("id", "")),
		"accepted":bool(context.get("accepted", false)),
		"completed":bool(context.get("completed", false)),
		"chapter":int(context.get("chapter", 0)),
		"contract_plan":str(context.get("contract_plan", "standard")),
		"contract":_pick_fields(context.get("contract", {}), ["case_id", "client", "title", "agreed_fee", "agreed_budget", "plan", "target_specs", "capabilities", "supply_requirements"]),
		"work":_pick_fields(work, ["started_day", "started_at"]),
		"advanced":_pick_fields(context.get("advanced", {}), ["case_id", "revision", "elapsed_minutes", "status", "result", "selected_plan"]),
		"revision":int(context.get("revision", 0)),
		"validated_revision":int(context.get("validated_revision", -1)),
		"checks":context.get("checks", []),
		"targets":_targets_signature(context.get("targets", []))
	}

static func _assignment_signature(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	return _pick_fields(value, ["status", "kind", "contract_id", "target_index", "target", "client", "member", "member_id", "role", "job_id", "task_name", "phase", "result", "result_path", "started_day", "started_minute", "completed_day", "completed_minute"])

static func _queues_signature(value: Variant) -> Array:
	var result: Array = []
	if not value is Dictionary: return result
	var owners: Array = value.keys()
	owners.sort()
	for owner in owners:
		var jobs: Array = []
		var raw_jobs: Variant = value[owner]
		if raw_jobs is Array:
			for job in raw_jobs:
				jobs.append(_pick_fields(job, ["id", "key", "status", "kind", "contract_id", "target_index", "target", "client", "role", "task_name", "phase", "result", "result_path", "revision", "validated_revision"]))
		result.append([str(owner), jobs])
	return result

static func _staff_signature(value: Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary: return result
	var ids: Array = value.keys()
	ids.sort()
	for id in ids:
		result[str(id)] = _pick_fields(value[id], ["active", "role", "shift", "pending_shift", "hired_day", "minutes_day", "daily_wage", "hire_fee"])
	return result

static func _maintenance_signature(value: Variant) -> Array:
	var result: Array = []
	if not value is Array: return result
	for job in value:
		result.append(_pick_fields(job, ["id", "client", "status", "assignee", "owner", "day", "fee", "cost", "created_day", "kind"]))
	return result

## Stable read-only token for staffing projections. It deliberately ignores
## ticking remaining-work counters while retaining inputs that change a quote.
static func signature(g) -> String:
	if g == null or not g.get("state") is Dictionary: return ""
	var state: Dictionary = g.get("state")
	var context_rows: Array = []
	var contexts: Variant = state.get("contract_contexts", {})
	if contexts is Dictionary:
		var context_ids: Array = contexts.keys()
		context_ids.sort()
		for raw_id in context_ids:
			context_rows.append([str(raw_id), _context_signature(contexts[raw_id])])
	var current_contract := _pick_fields(state.get("contract", {}), ["case_id", "client", "title", "agreed_fee", "agreed_budget", "plan", "target_specs", "capabilities", "supply_requirements"])
	var current_work: Dictionary = state.get("work", {}) if state.get("work", {}) is Dictionary else {}
	var current_advanced: Dictionary = state.get("advanced", {}) if state.get("advanced", {}) is Dictionary else {}
	var assignments: Dictionary = {}
	var raw_assignments: Variant = g.get("_assignments")
	if raw_assignments is Dictionary:
		var assignment_ids: Array = raw_assignments.keys()
		assignment_ids.sort()
		for owner in assignment_ids: assignments[str(owner)] = _assignment_signature(raw_assignments[owner])
	var holds: Dictionary = {}
	var raw_holds: Variant = state.get("dispatch_holds", {})
	if raw_holds is Dictionary:
		var hold_ids: Array = raw_holds.keys()
		hold_ids.sort()
		for owner in hold_ids: holds[str(owner)] = bool(raw_holds[owner])
	var payroll_due: Array = []
	var payroll: Variant = state.get("staff_payroll", {})
	if payroll is Dictionary:
		for entry in payroll.get("due", []): payroll_due.append(_pick_fields(entry, ["day", "staff_id", "amount", "paid_amount", "paid", "expense_recorded"]))
	var clock := int(g.clock_minutes()) if g.has_method("clock_minutes") else int(state.get("clock_minutes", -1))
	var shape := {
		"day":int(state.get("day", 0)),
		"clock_minutes":clock,
		"cash":int(state.get("cash", 0)),
		"career_mode":bool(state.get("career_mode", false)),
		"equipment":state.get("equipment", []),
		"staff":_staff_signature(state.get("staff", {})),
		"staff_payroll":{"enabled":bool(payroll.get("enabled", false)) if payroll is Dictionary else false, "last_settled_day":int(payroll.get("last_settled_day", -1)) if payroll is Dictionary else -1, "due":payroll_due},
		"assignments":assignments,
		"dispatch_queues":_queues_signature(state.get("dispatch_queues", {})),
		"dispatch_holds":holds,
		"crew_runtime_available":g.get("_crew_runtime_available") if g.get("_crew_runtime_available") is Dictionary else {},
		"crew_runtime_registered":g.get("_crew_runtime_registered") if g.get("_crew_runtime_registered") is Dictionary else {},
		"current_contract_id":str(state.get("current_contract_id", "")),
		"accepted":bool(state.get("accepted", false)),
		"current_completed":bool(state.get("current_contract_id", "") in state.get("completed_ids", [])),
		"completed_ids":state.get("completed_ids", []),
		"current_contract":current_contract,
		"current_contract_plan":str(state.get("contract_plan", "standard")),
		"current_work":_pick_fields(current_work, ["started_day", "started_at"]),
		"current_advanced":_pick_fields(current_advanced, ["case_id", "revision", "elapsed_minutes", "status", "result", "selected_plan"]),
		"skills":state.get("skills", {}),
		"current_revision":int(state.get("revision", 0)),
		"current_validated_revision":int(state.get("validated_revision", -1)),
		"current_checks":state.get("checks", []),
		"current_targets":_targets_signature(state.get("targets", [])),
		"contexts":context_rows,
		"maintenance_jobs":_maintenance_signature(state.get("maintenance_jobs", [])),
		"care_agreements":state.get("care_agreements", {}),
		"care_incidents":state.get("care_incidents", {}),
		"maintenance_targets":state.get("maintenance_targets", {})
	}
	return JSON.stringify(shape).sha256_text()

static func _valid_shift(g, shift_id: String) -> Dictionary:
	for raw in g.staff_shift_catalog():
		if raw is Dictionary and str(raw.get("id", "")) == shift_id:
			return raw.duplicate(true)
	return {}

static func _clone_game(g):
	if g == null or g.get_script() == null:
		return null
	var copy = g.get_script().new()
	var source_state: Dictionary = g.get("state").duplicate(true) if g.get("state") is Dictionary else {}
	# Start from the current schema so old saves missing optional containers can
	# still be projected. Overlay every saved top-level value without sharing refs.
	copy._reset_state()
	var normalized_state: Dictionary = copy.state
	for key in source_state:
		normalized_state[key] = source_state[key]
	copy.state = normalized_state
	copy.settings = g.get("settings").duplicate(true) if g.get("settings") is Dictionary else {}
	copy._assignments = g.get("_assignments").duplicate(true) if g.get("_assignments") is Dictionary else {}
	copy._crew_runtime_available = g.get("_crew_runtime_available").duplicate(true) if g.get("_crew_runtime_available") is Dictionary else {"aya":true,"ren":true}
	copy._crew_runtime_registered = g.get("_crew_runtime_registered").duplicate(true) if g.get("_crew_runtime_registered") is Dictionary else {}
	copy._crew_update = float(g.get("_crew_update"))
	copy._maintenance_dispatch_elapsed = float(g.get("_maintenance_dispatch_elapsed"))
	copy._office_clock_paused = bool(g.get("_office_clock_paused"))
	copy._delivery_clock_enabled = bool(g.get("_delivery_clock_enabled"))
	copy._delivery_clock_paused = bool(g.get("_delivery_clock_paused"))
	copy._dispatch_start_remaining = float(g.get("_dispatch_start_remaining"))
	copy._dispatch_start_member = str(g.get("_dispatch_start_member"))
	copy._dispatch_transaction = false
	# Older saves can predate these containers. Normalize only the copy because
	# CompanyWorkday.snapshot may synchronize the contract and maintenance view.
	var state: Dictionary = copy.state
	if not state.get("contract_contexts", {}) is Dictionary: state["contract_contexts"] = {}
	if not state.get("billing", {}) is Dictionary: state["billing"] = {}
	if not state.billing.get("invoices", []) is Array: state.billing["invoices"] = []
	if not state.get("dispatch_queues", {}) is Dictionary: state["dispatch_queues"] = {}
	if not state.get("dispatch_holds", {}) is Dictionary: state["dispatch_holds"] = {}
	if not state.get("staff", {}) is Dictionary: state["staff"] = {}
	if not state.get("staff_payroll", {}) is Dictionary: state["staff_payroll"] = {"enabled":false,"due":[]}
	if not state.staff_payroll.get("due", []) is Array: state.staff_payroll["due"] = []
	if not state.get("maintenance_jobs", []) is Array: state["maintenance_jobs"] = []
	if not state.get("care_agreements", {}) is Dictionary: state["care_agreements"] = {}
	if not state.get("care_incidents", {}) is Dictionary: state["care_incidents"] = {}
	if not state.get("maintenance_targets", {}) is Dictionary: state["maintenance_targets"] = {}
	if not state.get("equipment", []) is Array: state["equipment"] = []
	return copy

static func _setup_candidate(copy, member_id: String, shift_id: String) -> void:
	var candidates: Array = copy.staff_candidates()
	var candidate: Dictionary = {}
	for raw in candidates:
		if str(raw.get("id", "")) == member_id:
			candidate = raw
			break
	if candidate.is_empty(): return
	var old: Dictionary = copy.state.staff.get(member_id, {})
	var used := float(old.get("minutes_used", 0.0)) if int(old.get("minutes_day", -1)) == int(copy.state.get("day", 0)) else 0.0
	copy.state.staff[member_id] = {
		"active":true,
		"role":str(candidate.get("role", "")),
		"shift":shift_id,
		"pending_shift":"",
		"hired_day":int(copy.state.get("day", 0)),
		"minutes_used":used,
		"minutes_day":int(copy.state.get("day", 0)),
		"daily_wage":int(candidate.get("daily_wage", 0)),
		"hire_fee":int(candidate.get("hire_fee", 0))
	}
	copy._assignments.erase(member_id)
	copy.state["assignments"] = copy._assignments.duplicate(true)
	copy.state.dispatch_queues.erase(member_id)
	copy.state.dispatch_holds.erase(member_id)
	# Mirror only the payroll projection part of hire_staff, on the detached copy.
	copy.state.staff_payroll["enabled"] = true
	copy._ensure_staff_wage(member_id)

static func _has_prior_work(g, job: Dictionary, role: String) -> bool:
	if role.is_empty(): return false
	var maintenance := str(job.get("kind", "")) == "maintenance"
	for assignment in job.get("assignments", []):
		if not assignment is Dictionary: continue
		var owner := str(assignment.get("member", assignment.get("member_id", "")))
		if owner.is_empty() or str(g.colleague_role(owner)) != role: continue
		if str(assignment.get("status", "")) in ["working", "queued", "paused", "pending"]:
			return true
	if maintenance:
		var assignee := str(job.get("assignee", ""))
		if not assignee.is_empty() and str(g.colleague_role(assignee)) == role: return true
		return false
	var context: Dictionary = g.state.get("contract_contexts", {}).get(str(job.get("contract_id", "")), {})
	var targets: Array = context.get("targets", []) if context.get("targets", []) is Array else []
	var target_index := int(job.get("target", -1))
	if target_index < 0 or target_index >= targets.size() or not targets[target_index] is Dictionary: return false
	var target: Dictionary = targets[target_index]
	var receipts: Variant = target.get("work_receipts", [])
	if receipts is Array:
		for receipt in receipts:
			if receipt is Dictionary and str(receipt.get("role", "")) == role:
				return true
	# Legacy saves may still carry a completed assignment instead of a receipt.
	for owner in g._assignments:
		var done: Variant = g._assignments[owner]
		if not done is Dictionary or str(done.get("status", "")) != "done": continue
		if str(g.colleague_role(str(owner))) != role: continue
		if str(done.get("contract_id", "")) == str(job.get("contract_id", "")) and int(done.get("target_index", -1)) == target_index: return true
	return false

static func _job_projection(g, job: Dictionary, member_id: String) -> Dictionary:
	var forecast: Dictionary = {}
	for raw in WORKDAY.candidates(g, job):
		if str(raw.get("member", raw.get("id", ""))) == member_id:
			forecast = raw
			break
	var blocked := str(forecast.get("reason", ""))
	if blocked.is_empty(): blocked = str(forecast.get("forecast_reason", ""))
	return {
		"key":str(job.get("key", "")),
		"client":str(job.get("client", "")),
		"title":str(job.get("title", "")),
		"kind":str(job.get("kind", "")),
		"target":int(job.get("target", -1)),
		"target_name":str(job.get("target_name", "")),
		"task_name":str(forecast.get("task_name", job.get("task_name", ""))),
		"can_enqueue":bool(forecast.get("can_enqueue", false)),
		"can_finish":bool(forecast.get("can_finish", false)),
		"reason":blocked,
		"finish_day":int(forecast.get("finish_day", -1)),
		"finish_minute":int(forecast.get("finish_minute", -1)),
		"duration_minutes":float(forecast.get("duration_minutes", 0.0)),
		"risk":str(forecast.get("risk", "blocked"))
	}

static func snapshot(g, member_id: String, shift_id: String = "day") -> Dictionary:
	if g == null or not g.has_method("team_members") or not g.has_method("staff_candidates"):
		return {}
	var day := int(g.state.get("day", 0)) if g.get("state") is Dictionary else 0
	var candidate: Dictionary = {}
	for raw in g.staff_candidates():
		if str(raw.get("id", "")) == member_id:
			candidate = raw.duplicate(true)
			break
	var existing: Dictionary = {}
	for raw in g.team_members():
		if str(raw.get("id", "")) == member_id:
			existing = raw.duplicate(true)
			break
	if candidate.is_empty() and existing.is_empty(): return {}
	var is_candidate := not candidate.is_empty()
	var staff_row: Dictionary = g.state.get("staff", {}).get(member_id, {}) if g.get("state") is Dictionary else {}
	var active_candidate := is_candidate and bool(staff_row.get("active", false))
	var hired := not is_candidate or active_candidate
	var actual_shift := str(staff_row.get("shift", "day")) if active_candidate else (str(existing.get("shift", "day")) if not is_candidate else shift_id)
	var shift: Dictionary = _valid_shift(g, actual_shift)
	if shift.is_empty(): return {}
	var role := str(staff_row.get("role", candidate.get("role", ""))) if is_candidate else str(existing.get("role", ""))
	var wage := int(g.staff_daily_wage(member_id, actual_shift)) if g.has_method("staff_daily_wage") else int(existing.get("daily_wage", candidate.get("daily_wage", 0)))
	var copy = _clone_game(g)
	if copy == null: return {}
	var before_preview: Dictionary = copy.day_preview() if copy.has_method("day_preview") else {}
	var payroll_before := int(before_preview.get("payroll_due", 0))
	var hire_reason := ""
	var live_hire_state_valid: bool = g.get("state") is Dictionary and g.state.get("staff", {}) is Dictionary and g.state.get("equipment", []) is Array and g.state.has("cash")
	if is_candidate and not active_candidate and g.has_method("staff_hire_reason") and live_hire_state_valid:
		hire_reason = str(g.staff_hire_reason(member_id, actual_shift))
	elif is_candidate and not active_candidate:
		hire_reason = "採用条件を確認できません"
	elif active_candidate:
		hire_reason = "在籍中"
	elif not is_candidate:
		hire_reason = "在籍中"
	if is_candidate and not active_candidate:
		_setup_candidate(copy, member_id, actual_shift)
	var workday: Dictionary = WORKDAY.snapshot(copy)
	var jobs: Array = []
	for job_value in workday.get("jobs", []):
		if not job_value is Dictionary: continue
		var job: Dictionary = job_value
		var kind := str(job.get("kind", ""))
		if bool(job.get("completed", false)) or bool(job.get("draft", false)): continue
		if kind == "maintenance":
			if str(job.get("status", "")) not in ["pending", "working", "queued", "paused", "failed"]: continue
		else:
			if str(job.get("status", "")) in ["completed", "draft", "ready"]: continue
		var prior_work := _has_prior_work(copy, job, role)
		var projection := _job_projection(copy, job, member_id)
		projection["demand"] = not prior_work
		projection["prior_work"] = prior_work
		jobs.append(projection)
	var payroll_after := payroll_before
	if is_candidate and not active_candidate:
		var after_preview: Dictionary = copy.day_preview()
		payroll_after = int(after_preview.get("payroll_due", payroll_before))
	var result := {
		"id":member_id,
		"name":str(candidate.get("name", existing.get("name", member_id))),
		"role":role,
		"hired":hired,
		"forecast_basis":"現在の在籍状態" if hired else "採用後の仮定",
		"shift":actual_shift,
		"shift_start":int(shift.get("start", -1)),
		"shift_end":int(shift.get("end", -1)),
		"current_day":day,
		"clock_minute":int(g.clock_minutes()) if g.has_method("clock_minutes") else -1,
		"wage":wage,
		"day_payroll_before":payroll_before,
		"day_payroll_after":payroll_after,
		"hire_reason":hire_reason,
		"jobs":jobs
	}
	if is_candidate and not active_candidate: result["hire_fee"] = int(candidate.get("hire_fee", 0))
	copy.free()
	return result
