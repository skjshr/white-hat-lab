extends RefCounted
## Read-only, cross-contract watch for accepted priority-response incidents.

const BUSINESS = preload("res://scripts/priority_business_brief.gd")
const CASE_ID := "advanced-saas-priority"


static func snapshot(game: Object) -> Dictionary:
	var empty := {"available":false,"visible":false,"open_count":0,"actionable_count":0,"incidents":[],"priority":{}}
	if not is_instance_valid(game): return empty
	var state_value: Variant = game.get("state")
	if not state_value is Dictionary: return empty
	var state: Dictionary = state_value
	var completed_ids: Array = state.get("completed_ids", []) if state.get("completed_ids", []) is Array else []
	var contexts: Array = []
	var seen: Dictionary = {}
	var active_id := str(state.get("current_contract_id", ""))
	if not active_id.is_empty() and bool(state.get("accepted", false)):
		seen[active_id] = true
		var active_contract_value: Variant = state.get("contract", {})
		if not bool(state.get("completed", false)) and not completed_ids.has(active_id) and active_contract_value is Dictionary and str(active_contract_value.get("case_id", "")) == CASE_ID:
			contexts.append({
				"id":active_id,
				"contract":active_contract_value,
				"accepted":true,
				"completed":false,
				"advanced":state.get("advanced", {}),
				"work":state.get("work", {}),
				"target_index":state.get("target_index", -1),
				"active":true
			})
	var contexts_value: Variant = state.get("contract_contexts", {})
	if contexts_value is Dictionary:
		for raw_id in contexts_value.keys():
			var contract_id := str(raw_id)
			if contract_id.is_empty() or seen.has(contract_id): continue
			seen[contract_id] = true
			if completed_ids.has(contract_id): continue
			var context_value: Variant = contexts_value[raw_id]
			if not context_value is Dictionary: continue
			var context: Dictionary = context_value
			if not bool(context.get("accepted", false)) or bool(context.get("completed", false)): continue
			var contract_value: Variant = context.get("contract", {})
			if not contract_value is Dictionary or str(contract_value.get("case_id", "")) != CASE_ID: continue
			var candidate := context.duplicate(false)
			candidate["id"] = contract_id
			candidate["active"] = false
			contexts.append(candidate)

	var incidents: Array = []
	for context in contexts:
		var projection: Dictionary = BUSINESS.from_context(context)
		var contract_value: Variant = context.get("contract", {})
		var contract: Dictionary = contract_value if contract_value is Dictionary else {}
		var target_index := _saved_integer(context, "target_index", -1)
		var available := bool(projection.get("available", false))
		var client := str(projection.get("client", ""))
		if client.is_empty(): client = str(contract.get("client", "顧客記録なし"))
		var item := {
			"contract_id":str(context.get("id", "")),
			"target_index":target_index,
			"client":client,
			"title":str(contract.get("title", "")),
			"elapsed":int(projection.get("elapsed", -1)) if available else -1,
			"queues":projection.get("queues", []).duplicate(true) if available and projection.get("queues", []) is Array else [],
			"costs":_confirmed_costs(projection) if available else {"available":false},
			"loss_cost":int(projection.get("loss_cost", -1)) if available else -1,
			"impact_cost":int(projection.get("impact_cost", -1)) if available else -1,
			"manual_cost":int(projection.get("manual_cost", -1)) if available else -1,
			"assistant_cost":int(projection.get("assistant_cost", -1)) if available else -1,
			"undelivered":true,
			"actionable":false,
			"available":available,
			"active":bool(context.get("active", false)),
			"queue_id":"",
			"_late":false,
			"_late_by":-1,
			"_remaining":2147483647
		}
		if available:
			var best_queue: Dictionary = {}
			for queue_value in item.queues:
				if not queue_value is Dictionary: continue
				var queue: Dictionary = queue_value
				if int(queue.get("received_count", -1)) < 0 or int(queue.get("approved_count", -1)) < 1: continue
				if int(queue.received_count) >= int(queue.approved_count): continue
				if best_queue.is_empty() or _queue_before(queue, best_queue, int(item.elapsed)):
					best_queue = queue
			if not best_queue.is_empty():
				item.actionable = true
				item.queue_id = str(best_queue.get("id", ""))
				item._late = bool(best_queue.get("late", false))
				item._late_by = maxi(0, int(item.elapsed) - int(best_queue.get("deadline", int(item.elapsed)))) if bool(best_queue.get("late", false)) else -1
				item._remaining = int(best_queue.get("remaining", 2147483647))
		incidents.append(item)

	incidents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _incident_before(a, b))
	var actionable_count := 0
	for incident in incidents:
		if bool(incident.actionable): actionable_count += 1
		for key in ["_late", "_late_by", "_remaining"]: incident.erase(key)
	var priority: Dictionary = {}
	if not incidents.is_empty():
		var first: Dictionary = incidents[0]
		priority = {
			"contract_id":str(first.contract_id),
			"target_index":int(first.target_index),
			"client":str(first.client),
			"title":str(first.title),
			"elapsed":int(first.elapsed),
			"queue_id":str(first.queue_id),
			"undelivered":true,
			"available":bool(first.available),
			"actionable":bool(first.actionable)
		}
		if bool(first.available) and bool(first.actionable):
			for queue_value in first.queues:
				if queue_value is Dictionary and str(queue_value.get("id", "")) == str(first.queue_id):
					for key in ["deadline", "remaining", "late", "received", "received_count", "approved_count", "late_cost", "loss_cost", "current"]:
						priority[key] = queue_value.get(key, false if key in ["late", "received", "current"] else -1)
					break
	return {"available":not incidents.is_empty(),"visible":not incidents.is_empty(),"open_count":incidents.size(),"actionable_count":actionable_count,"incidents":incidents,"priority":priority}


static func _confirmed_costs(projection: Dictionary) -> Dictionary:
	var business := int(projection.get("loss_cost", -1))
	var impact := int(projection.get("impact_cost", -1))
	var manual := int(projection.get("manual_cost", -1))
	var assistant := int(projection.get("assistant_cost", -1))
	if business < 0 or impact < 0 or manual < 0 or assistant < 0: return {"available":false}
	return {"available":true,"business":business,"impact":impact,"manual":manual,"assistant":assistant,"total":business + impact + manual + assistant}


static func _queue_before(a: Dictionary, b: Dictionary, elapsed: int) -> bool:
	var a_late := bool(a.get("late", false))
	var b_late := bool(b.get("late", false))
	if a_late != b_late: return a_late
	if a_late:
		var a_overdue := maxi(0, elapsed - int(a.get("deadline", elapsed)))
		var b_overdue := maxi(0, elapsed - int(b.get("deadline", elapsed)))
		if a_overdue != b_overdue: return a_overdue > b_overdue
	else:
		var a_remaining := int(a.get("remaining", 2147483647))
		var b_remaining := int(b.get("remaining", 2147483647))
		if a_remaining != b_remaining: return a_remaining < b_remaining
	var a_current := bool(a.get("current", false))
	var b_current := bool(b.get("current", false))
	if a_current != b_current: return a_current
	return str(a.get("id", "")) < str(b.get("id", ""))


static func _incident_before(a: Dictionary, b: Dictionary) -> bool:
	var a_actionable := bool(a.get("actionable", false))
	var b_actionable := bool(b.get("actionable", false))
	if a_actionable != b_actionable: return a_actionable
	if a_actionable:
		var a_late := bool(a.get("_late", false))
		var b_late := bool(b.get("_late", false))
		if a_late != b_late: return a_late
		if a_late and int(a.get("_late_by", 0)) != int(b.get("_late_by", 0)):
			return int(a.get("_late_by", 0)) > int(b.get("_late_by", 0))
		if not a_late and int(a.get("_remaining", 0)) != int(b.get("_remaining", 0)):
			return int(a.get("_remaining", 0)) < int(b.get("_remaining", 0))
	var a_active := bool(a.get("active", false))
	var b_active := bool(b.get("active", false))
	if a_active != b_active: return a_active
	return str(a.get("contract_id", "")) < str(b.get("contract_id", ""))


static func _saved_integer(source: Dictionary, key: String, fallback: int) -> int:
	if not source.has(key): return fallback
	var value: Variant = source[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)):
		return fallback
	return int(value)
