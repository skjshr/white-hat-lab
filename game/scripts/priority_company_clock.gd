extends RefCounted
## Advances only accepted priority-response work when the company clock moves.
## Call from inside the existing mutation/save transaction, never from a view.

const PRIORITY := preload("res://scripts/saas_priority.gd")
const ANCHOR_MINUTE := "priority_company_clock_anchor_minute"
const ANCHOR_ELAPSED := "priority_company_clock_anchor_elapsed"


static func sync_state(state: Dictionary, now_absolute_minute: int) -> bool:
	var changed := false
	var visited: Dictionary = {}
	var completed: Array = state.get("completed_ids", []) if state.get("completed_ids", []) is Array else []
	var active_id := str(state.get("current_contract_id", ""))
	if bool(state.get("accepted", false)) and not active_id.is_empty() and not completed.has(active_id) and _is_priority(state.get("contract", {}), state.get("advanced", {})):
		var active_result := _sync_entry(state.get("work", {}), state.get("advanced", {}), now_absolute_minute)
		if bool(active_result.changed):
			state.work = active_result.work
			state.advanced = active_result.advanced
			_sync_active_target(state)
			changed = true
		visited[active_id] = true

	var contexts: Variant = state.get("contract_contexts", {})
	if contexts is Dictionary:
		for raw_id in contexts.keys():
			var id := str(raw_id)
			if visited.has(id) or completed.has(id): continue
			var context: Variant = contexts.get(raw_id, {})
			if not context is Dictionary or bool(context.get("completed", false)): continue
			if not _is_priority(context.get("contract", {}), context.get("advanced", {})): continue
			var result := _sync_entry(context.get("work", {}), context.get("advanced", {}), now_absolute_minute)
			if not bool(result.changed): continue
			context.work = result.work
			context.advanced = result.advanced
			_sync_context_target(context)
			contexts[raw_id] = context
			changed = true
		state.contract_contexts = contexts
	return changed


static func _is_priority(contract_value: Variant, advanced_value: Variant) -> bool:
	if not contract_value is Dictionary or not advanced_value is Dictionary: return false
	return str(contract_value.get("case_id", "")) == PRIORITY.CASE_ID and str(advanced_value.get("model_version", "")) == PRIORITY.MODEL_VERSION


static func _sync_entry(work_value: Variant, advanced_value: Variant, now_absolute_minute: int) -> Dictionary:
	if not work_value is Dictionary or not advanced_value is Dictionary:
		return {"changed":false}
	var work: Dictionary = work_value.duplicate(true)
	var advanced: Dictionary = advanced_value.duplicate(true)
	var elapsed := int(advanced.get("elapsed_minutes", 0))
	if not work.has(ANCHOR_MINUTE) or not work.has(ANCHOR_ELAPSED):
		# Legacy saves start tracking from their first state-changing transaction.
		# Preserve their already recorded elapsed time and never replay old history.
		work[ANCHOR_MINUTE] = now_absolute_minute
		work[ANCHOR_ELAPSED] = elapsed
		return {"changed":true,"work":work,"advanced":advanced}

	var anchor_minute := int(work.get(ANCHOR_MINUTE, now_absolute_minute))
	var anchor_elapsed := int(work.get(ANCHOR_ELAPSED, elapsed))
	if now_absolute_minute < anchor_minute or elapsed < anchor_elapsed:
		# A repaired/corrupt clock or old migrated payload rebases safely without
		# manufacturing elapsed time or undoing an existing observation.
		work[ANCHOR_MINUTE] = now_absolute_minute
		work[ANCHOR_ELAPSED] = elapsed
		return {"changed":true,"work":work,"advanced":advanced}

	var company_delta := now_absolute_minute - anchor_minute
	var engine_delta := elapsed - anchor_elapsed
	# An explicit priority action advances the scenario before Game advances its
	# company clock. Leave the anchor untouched until both clocks catch up.
	if engine_delta > company_delta: return {"changed":false}
	var missing := company_delta - engine_delta
	if missing > 0:
		var business_before := _business_loss(advanced)
		var impact := PRIORITY.advance(advanced, missing)
		var business_added := maxi(0, _business_loss(advanced) - business_before)
		if impact > 0:
			work.incident_cost = int(work.get("incident_cost", 0)) + impact
			var costs: Dictionary = work.get("saas_costs", {}).duplicate(true) if work.get("saas_costs", {}) is Dictionary else {}
			# Keep the established receipt/business-brief schema even when the
			# first cost on this contract comes from an elapsed-time event.
			for key in ["usage_cost", "impact_cost", "assistant_runs"]:
				if not costs.has(key): costs[key] = 0
			var non_business := maxi(0, impact - business_added)
			costs["impact_cost"] = int(costs.get("impact_cost", 0)) + non_business
			if business_added > 0 or costs.has("business_cost"):
				costs["business_cost"] = int(costs.get("business_cost", 0)) + business_added
			work.saas_costs = costs
		work[ANCHOR_MINUTE] = now_absolute_minute
		work[ANCHOR_ELAPSED] = int(advanced.get("elapsed_minutes", elapsed))
		return {"changed":true,"work":work,"advanced":advanced}

	work[ANCHOR_MINUTE] = now_absolute_minute
	work[ANCHOR_ELAPSED] = elapsed
	return {"changed":true,"work":work,"advanced":advanced}


static func _business_loss(advanced: Dictionary) -> int:
	var total := 0
	for queue in advanced.get("priority", {}).get("queues", []):
		if queue is Dictionary: total += maxi(0, int(queue.get("loss_cost", 0)))
	return total


static func _sync_active_target(state: Dictionary) -> void:
	var targets: Variant = state.get("targets", [])
	var index := int(state.get("target_index", 0))
	if not targets is Array or index < 0 or index >= targets.size() or not targets[index] is Dictionary: return
	var target: Dictionary = targets[index].duplicate(true)
	target.advanced = state.get("advanced", {}).duplicate(true)
	targets[index] = target
	state.targets = targets


static func _sync_context_target(context: Dictionary) -> void:
	var targets: Variant = context.get("targets", [])
	var index := int(context.get("target_index", 0))
	if not targets is Array or index < 0 or index >= targets.size() or not targets[index] is Dictionary: return
	var target: Dictionary = targets[index].duplicate(true)
	target.advanced = context.get("advanced", {}).duplicate(true)
	targets[index] = target
	context.targets = targets
