extends RefCounted

const UI_COPY = preload("res://scripts/ui_theme.gd")

## Cross-contract colleague scheduling.  The game owns the save transaction;
## this helper only projects a target long enough to build the same assignment
## record used by the normal colleague path.

static func jobs(g) -> Array:
	if g == null or not g is Object:
		return []
	var state: Variant = g.get("state")
	if not state is Dictionary or not bool(state.get("accepted", false)):
		return []
	if g.has_method("_sync_contract_context"):
		g.call("_sync_contract_context")
	state = g.get("state")
	if not state is Dictionary:
		return []
	var contexts: Dictionary = {}
	if state.get("contract_contexts", {}) is Dictionary:
		for raw_id in state.contract_contexts.keys():
			var raw_context: Variant = state.contract_contexts[raw_id]
			if raw_context is Dictionary:
				contexts[str(raw_id)] = raw_context
	var active_id := str(state.get("current_contract_id", ""))
	if contexts.is_empty() and not active_id.is_empty():
		contexts[active_id] = _active_context(state, active_id)
	elif not active_id.is_empty() and not contexts.has(active_id):
		contexts[active_id] = _active_context(state, active_id)
	var out: Array = []
	for contract_id in contexts.keys():
		var context: Dictionary = contexts[contract_id]
		if not bool(context.get("accepted", false)) or bool(context.get("completed", false)) or str(contract_id) in state.get("completed_ids", []):
			continue
		var targets: Array = context.get("targets", []) if context.get("targets", []) is Array else []
		var contract: Dictionary = context.get("contract", {}) if context.get("contract", {}) is Dictionary else {}
		var deadline := _deadline(g, state, context)
		for target_index in targets.size():
			var target: Dictionary = targets[target_index] if targets[target_index] is Dictionary else {}
			var assignment := _assignment_for(g, str(contract_id), target_index)
			var done_checks := _target_checks(target)
			var target_name := str(target.get("name", "site-%d" % target_index))
			out.append({
				"id": "%s/site-%d" % [str(contract_id), target_index],
				"contract_id": str(contract_id),
				"target_index": target_index,
				"target_name": target_name,
				"name": target_name,
				"client": str(contract.get("client", "")),
				"title": str(contract.get("title", "")),
				"deadline_remaining": deadline.remaining,
				"remaining": deadline.remaining,
				"late": bool(deadline.late),
				"late_minutes": deadline.late_minutes,
				"done": bool(done_checks.done),
				"checks": done_checks,
				"assignee": str(assignment.get("assignee", "")),
				"assignment": assignment,
				"active": str(contract_id) == active_id,
			})
	out.sort_custom(func(left, right):
		var left_remaining := float(left.get("deadline_remaining", 0.0))
		var right_remaining := float(right.get("deadline_remaining", 0.0))
		if left_remaining != right_remaining:
			return left_remaining < right_remaining
		if str(left.get("contract_id", "")) != str(right.get("contract_id", "")):
			return str(left.get("contract_id", "")) < str(right.get("contract_id", ""))
		return int(left.get("target_index", 0)) < int(right.get("target_index", 0))
	)
	return out


static func quote(g, member_id: String, contract_id: String, target_index: int) -> Dictionary:
	var invalid := {"ok": false, "reason": "ops_invalid_target", "duration": 0.0, "daily_wage": 0, "shift_end": -1}
	var target_info := _target_context(g, contract_id, target_index)
	if not bool(target_info.get("ok", false)):
		return invalid
	var member := member_id.strip_edges()
	if member.is_empty() or g == null or not g is Object:
		return {"ok": false, "reason": "staffing_inactive", "duration": 0.0, "daily_wage": 0, "shift_end": -1}
	if not g.has_method("staff_availability"):
		return {"ok": false, "reason": "staffing_inactive", "duration": 0.0, "daily_wage": 0, "shift_end": -1}
	var target_chapter: int = int(target_info.target.get("chapter",target_info.context.get("chapter",0)))
	var reason := str(g.call("staff_availability", member, "normal", target_chapter, false))
	if reason.is_empty() and not g._colleague_hardware_connected({"contract_id":contract_id,"target_index":target_index}): reason=UI_COPY.copy("stock_error_hardware")
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "duration": 0.0, "daily_wage": 0, "shift_end": -1}
	var role := str(g.call("colleague_role", member)) if g.has_method("colleague_role") else ""
	if role.is_empty():
		return {"ok": false, "reason": "staffing_inactive", "duration": 0.0, "daily_wage": 0, "shift_end": -1}
	var duration := float(g.call("team_work_duration", member)) if g.has_method("team_work_duration") else 0.0
	if g.has_method("get") and str(g.get("_dispatch_start_member")) == member and float(g.get("_dispatch_start_remaining")) >= 0.0:
		duration = float(g.get("_dispatch_start_remaining"))
	var shift := "day"
	for candidate in g.call("team_members") if g.has_method("team_members") else []:
		if candidate is Dictionary and str(candidate.get("id", "")) == member:
			shift = str(candidate.get("shift", "day"))
	var daily_wage := int(g.call("staff_daily_wage", member, shift)) if g.has_method("staff_daily_wage") else 0
	var shift_end := -1
	for candidate_shift in g.call("staff_shift_catalog") if g.has_method("staff_shift_catalog") else []:
		if candidate_shift is Dictionary and str(candidate_shift.get("id", "")) == shift:
			shift_end = int(candidate_shift.get("end", -1))
	return {"ok": true, "reason": "", "duration": duration, "daily_wage": daily_wage, "shift_end": shift_end}


static func assign(g, member_id: String, contract_id: String, target_index: int) -> bool:
	if g._dispatch_duplicate(member_id,"normal",contract_id,target_index): return false
	var preview := quote(g, member_id, contract_id, target_index)
	if not bool(preview.get("ok", false)):
		return false
	if g == null or not g is Object or not g.has_method("save_game"):
		return false
	var previous_assignments: Dictionary = g.get("_assignments").duplicate(true) if g.get("_assignments") is Dictionary else {}
	var rollback_state: Variant = g.get("state")
	if not rollback_state is Dictionary:
		return false
	rollback_state = rollback_state.duplicate(true)
	var previous_machine: Variant = g.get("_machine")
	var previous_key := str(g.get("_machine_key"))
	if g.has_method("_sync_contract_context"):
		g.call("_sync_contract_context")
	var previous_state: Variant = g.get("state")
	if not previous_state is Dictionary:
		_restore(g, rollback_state, previous_assignments, previous_machine, previous_key)
		return false
	previous_state = previous_state.duplicate(true)
	var active_id := str(previous_state.get("current_contract_id", ""))
	if active_id != contract_id:
		if not g.has_method("_activate_contract_context") or not bool(g.call("_activate_contract_context", contract_id)):
			_restore(g, rollback_state, previous_assignments, previous_machine, previous_key)
			return false
	var projected: Variant = g.get("state")
	if not projected is Dictionary:
		_restore(g, rollback_state, previous_assignments, previous_machine, previous_key)
		return false
	var targets: Array = projected.get("targets", []) if projected.get("targets", []) is Array else []
	if target_index < 0 or target_index >= targets.size() or not targets[target_index] is Dictionary:
		_restore(g, rollback_state, previous_assignments, previous_machine, previous_key)
		return false
	var target: Dictionary = targets[target_index]
	projected.target_index = target_index
	projected.chapter = int(target.get("chapter", projected.get("chapter", 0)))
	projected.config = target.get("config", projected.get("config", {})).duplicate(true) if target.get("config", {}) is Dictionary else {}
	projected.inspected = bool(target.get("inspected", false))
	projected.checks = target.get("checks", []).duplicate(true) if target.get("checks", []) is Array else []
	projected.revision = int(target.get("revision", 0))
	projected.validated_revision = int(target.get("validated_revision", -1))
	g.set("state", projected)
	var machine: Variant = g.call("_vm") if g.has_method("_vm") else null
	var vm_key := str(g.call("_vm_key")) if g.has_method("_vm_key") else "%s/site-%d" % [contract_id, target_index]
	var role := str(g.call("colleague_role", member_id))
	var result_path := str(g.call("colleague_result_path", member_id)) if g.has_method("colleague_result_path") else ""
	var config_before := ""
	if machine != null and machine is Object:
		var machine_state: Variant = machine.get("state")
		if machine_state is Dictionary:
			var machine_fs: Variant = machine_state.get("fs", {})
			var machine_path := str(machine_state.get("config_path", ""))
			if machine_fs is Dictionary:
				config_before = str(machine_fs.get(machine_path, ""))
	var assignments := previous_assignments.duplicate(true)
	assignments[member_id] = {"status":"working","remaining":float(preview.duration),"total":float(preview.duration),"work_minutes":float(preview.duration),"revision":int(projected.get("revision", 0)),"chapter":int(projected.get("chapter", 0)),"contract_id":contract_id,"target_index":target_index,"vm_key":vm_key,"role":role,"result_path":result_path,"config_before":config_before,"phase":UI_COPY.copy("care_maintenance_working", "working"),"result":""}
	assignments[member_id].equipment_effects = g.team_work_effects(member_id)
	assignments[member_id].equipment_work_id = g.equipment_work_id(member_id)
	_restore(g, previous_state.duplicate(true), assignments, previous_machine, previous_key)
	if bool(g.get("_dispatch_transaction")):
		return true
	var saved := bool(g.call("save_game"))
	if not saved:
		_restore(g, rollback_state, previous_assignments, previous_machine, previous_key)
		return false
	if g.has_signal("changed"):
		g.changed.emit()
	return true


static func _target_context(g, contract_id: String, target_index: int, allow_verified: bool = false) -> Dictionary:
	if g == null or not g is Object:
		return {"ok": false}
	var state: Variant = g.get("state")
	if not state is Dictionary or not bool(state.get("accepted", false)):
		return {"ok": false}
	var id := contract_id.strip_edges()
	if id.is_empty():
		return {"ok": false}
	var context: Dictionary = {}
	if str(state.get("current_contract_id", "")) == id:
		context = _active_context(state, id)
	elif state.get("contract_contexts", {}) is Dictionary and state.contract_contexts.get(id, {}) is Dictionary:
		context = state.contract_contexts.get(id, {}).duplicate(true)
	if context.is_empty() or not bool(context.get("accepted", false)) or bool(context.get("completed", false)) or id in state.get("completed_ids", []):
		return {"ok": false}
	var targets: Array = context.get("targets", []) if context.get("targets", []) is Array else []
	if target_index < 0 or target_index >= targets.size() or not targets[target_index] is Dictionary:
		return {"ok": false}
	var target: Dictionary = targets[target_index]
	if not allow_verified and bool(_target_checks(target).get("done", false)):
		return {"ok": false}
	return {"ok": true, "context": context, "target": target}


static func _active_context(state: Dictionary, id: String) -> Dictionary:
	return {"id":id,"chapter":int(state.get("chapter",0)),"contract":state.get("contract",{}).duplicate(true),"contract_plan":str(state.get("contract_plan","standard")),"accepted":bool(state.get("accepted",false)),"completed":false,"targets":state.get("targets",[]).duplicate(true),"work":state.get("work",{}).duplicate(true)}


static func _deadline(g, state: Dictionary, context: Dictionary) -> Dictionary:
	var contract: Dictionary = context.get("contract", {}) if context.get("contract", {}) is Dictionary else {}
	var budget := float(contract.get("agreed_budget", 0.0))
	if budget <= 0.0 and g.has_method("_contract_budget"):
		var specs: Array = contract.get("target_specs", []) if contract.get("target_specs", []) is Array else []
		var targets: Array = context.get("targets", []) if context.get("targets", []) is Array else []
		var pricing: Variant = g.call("_contract_budget", int(context.get("chapter", 0)), targets.size(), specs, str(context.get("contract_plan", "standard")))
		if pricing is Dictionary:
			budget = float(pricing.get("budget", 0.0))
	if budget <= 0.0:
		budget = 90.0
	var work: Dictionary = context.get("work", {}) if context.get("work", {}) is Dictionary else {}
	var started_day := int(work.get("started_day", state.get("day", 1)))
	var started_at := int(work.get("started_at", 540))
	var elapsed := maxf(0.0, float((int(state.get("day", started_day)) - started_day) * 1440 + int(state.get("clock_minutes", started_at)) - started_at))
	var remaining := maxf(0.0, budget - elapsed)
	var late_minutes := maxi(0, int(round(elapsed - budget)))
	return {"remaining":remaining,"late":late_minutes > 0,"late_minutes":late_minutes}


static func _target_checks(target: Dictionary) -> Dictionary:
	var checks: Array = target.get("checks", []) if target.get("checks", []) is Array else []
	var validated := int(target.get("validated_revision", -1)) == int(target.get("revision", 0))
	var inspected := bool(target.get("inspected", false))
	var all_passed := not checks.is_empty()
	for check in checks:
		if not check is Dictionary or not bool(check.get("passed", false)):
			all_passed = false
	return {"inspected":inspected,"validated":validated,"all_passed":all_passed,"done":inspected and validated and all_passed}


static func _assignment_for(g, contract_id: String, target_index: int) -> Dictionary:
	var assignments: Variant = g.get("_assignments") if g != null and g is Object else {}
	if not assignments is Dictionary:
		return {}
	for member_id in assignments.keys():
		var assignment: Variant = assignments[member_id]
		if assignment is Dictionary and str(assignment.get("status", "")) in ["working", "done"] and str(assignment.get("contract_id", "")) == contract_id and int(assignment.get("target_index", -1)) == target_index:
			var result: Dictionary = assignment.duplicate(true)
			result["assignee"] = str(member_id)
			return result
	return {}


static func _restore(g, state: Dictionary, assignments: Dictionary, machine, machine_key: String) -> void:
	g.set("state", state)
	g.set("_assignments", assignments)
	state.assignments = assignments.duplicate(true)
	g.set("_machine", machine)
	g.set("_machine_key", machine_key)
