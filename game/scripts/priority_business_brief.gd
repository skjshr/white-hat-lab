extends RefCounted
## Read-only business timing and cost projection for priority-response work.

const CASE_ID := "advanced-saas-priority"
const CLIENT := "北斗物流"
const ENGINE = preload("res://scripts/saas_priority.gd")


static func _whole(value: Variant, minimum: int = 0) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum or (typeof(value) == TYPE_FLOAT and is_finite(float(value)) and floorf(float(value)) == float(value) and float(value) >= minimum)


static func _int_field(row: Dictionary, key: String, minimum: int = 0) -> bool:
	return row.has(key) and _whole(row[key], minimum)


static func _recorded_received_count(model: Dictionary, queue: Dictionary) -> int:
	var receipt := str(queue.get("receipt_id", ""))
	var items_value: Variant = queue.get("items", null)
	if not items_value is Array: return -1
	var expected: Dictionary = {}
	for item_value in items_value:
		if not item_value is Dictionary: return -1
		var item: Dictionary = item_value
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or expected.has(item_id): return -1
		expected[item_id] = true
	if expected.size() != int(queue.get("approved_count", -1)): return -1
	if receipt.is_empty():
		for item_value in items_value:
			if str(item_value.get("status", "")) != "pending": return -1
		return 0
	if not _int_field(queue, "received_minute") or int(queue.received_minute) < 0: return -1
	var records_value: Variant = model.get("records", null)
	if not records_value is Array: return -1
	for record_value in records_value:
		if not record_value is Dictionary: continue
		var record: Dictionary = record_value
		if str(record.get("action", "")) not in ["run_business", "manual_business"] or int(record.get("status", 0)) != 200: continue
		var data_value: Variant = record.get("data", {})
		if not data_value is Dictionary: continue
		var data: Dictionary = data_value
		if str(data.get("queue_id", "")) != str(queue.get("id", "")) or str(data.get("receipt_id", "")) != receipt: continue
		if not _int_field(record, "minute") or int(record.minute) != int(queue.received_minute): continue
		var jobs_value: Variant = data.get("jobs", null)
		if not jobs_value is Array or jobs_value.size() != int(queue.get("approved_count", -1)): continue
		var seen: Dictionary = {}
		var count := 0
		var valid := true
		for job_value in jobs_value:
			if not job_value is Dictionary:
				valid = false
				break
			var job: Dictionary = job_value
			var job_id := str(job.get("id", ""))
			var job_receipt := str(job.get("receipt_id", ""))
			if not expected.has(job_id) or seen.has(job_id) or str(job.get("status", "")) != "received" or not job_receipt.begins_with(receipt + "-"):
				valid = false
				break
			seen[job_id] = true
			count += 1
		if valid and seen.size() == expected.size(): return count
	return -1


static func _project(model: Dictionary, preview: bool, work: Dictionary = {}) -> Dictionary:
	var view: Dictionary = ENGINE.view(model)
	if view.is_empty() or str(view.get("case_id", "")) != CASE_ID: return {"available":false}
	var priority_value: Variant = view.get("priority", null)
	if not priority_value is Dictionary: return {"available":false}
	var priority: Dictionary = priority_value
	var source_value: Variant = priority.get("source", null)
	if not source_value is Dictionary or str(source_value.get("client", "")) != CLIENT: return {"available":false}
	if not _int_field(priority, "round", 1) or not _int_field(priority, "elapsed_minutes") or not priority.get("queues", null) is Array or priority.queues.size() != 2:
		return {"available":false}
	var elapsed := int(priority.elapsed_minutes)
	var queues: Array = []
	var seen_ids: Dictionary = {}
	var total_loss := 0
	for queue_value in priority.queues:
		if not queue_value is Dictionary: return {"available":false}
		var queue: Dictionary = queue_value
		var id := str(queue.get("id", ""))
		if id not in ["dispatch", "claims"] or seen_ids.has(id): return {"available":false}
		seen_ids[id] = true
		for key in ["label", "approved_count", "deadline_minute", "late", "late_cost", "loss_cost", "current"]:
			if not queue.has(key): return {"available":false}
		if not _int_field(queue, "approved_count", 1) or not _int_field(queue, "deadline_minute") or not _int_field(queue, "late_cost") or not _int_field(queue, "loss_cost"):
			return {"available":false}
		if typeof(queue.late) != TYPE_BOOL or typeof(queue.current) != TYPE_BOOL: return {"available":false}
		var received_count := _recorded_received_count(model, queue)
		if received_count < 0: return {"available":false}
		var deadline := int(queue.deadline_minute)
		var loss := int(queue.loss_cost)
		total_loss += loss
		queues.append({
			"id":id,
			"label":str(queue.label),
			"approved_count":int(queue.approved_count),
			"received_count":received_count,
			"deadline":deadline,
			"remaining":maxi(0, deadline - elapsed),
			"late":bool(queue.late),
			"late_cost":int(queue.late_cost),
			"loss_cost":loss,
			"received":received_count == int(queue.approved_count),
			"current":bool(queue.current)
		})
	if seen_ids.size() != 2 or int(priority.get("loss_cost", -1)) != total_loss: return {"available":false}
	var egress_value: Variant = model.get("egress", null)
	if not egress_value is Dictionary or not _int_field(egress_value, "impact_cost"): return {"available":false}
	var impact_cost := int(egress_value.impact_cost)
	var manual_cost := 0
	var assistant_cost := 0
	var manual_remaining := 0
	var manual_minutes := 0
	var manual_fee := 0
	var rebuild_minutes := 0
	var connector_status := "ready"
	var recovery_value: Variant = priority.get("recovery", {})
	if recovery_value is Dictionary and not recovery_value.is_empty():
		var recovery: Dictionary = recovery_value
		for key in ["connector_status", "manual_remaining", "manual_minutes", "manual_cost", "rebuild_minutes", "manual_usage_cost"]:
			if not recovery.has(key): return {"available":false}
		if str(recovery.connector_status) not in ["stopped", "ready"] or not _int_field(recovery, "manual_remaining") or not _int_field(recovery, "manual_minutes") or not _int_field(recovery, "manual_cost") or not _int_field(recovery, "rebuild_minutes") or not _int_field(recovery, "manual_usage_cost"):
			return {"available":false}
		connector_status = str(recovery.connector_status)
		manual_remaining = int(recovery.manual_remaining)
		manual_minutes = int(recovery.manual_minutes)
		manual_fee = int(recovery.manual_cost)
		rebuild_minutes = int(recovery.rebuild_minutes)
		manual_cost = int(recovery.manual_usage_cost)
	var costs_value: Variant = work.get("saas_costs", null)
	if preview:
		manual_cost = 0
	elif costs_value is Dictionary:
		var costs: Dictionary = costs_value
		for key in ["usage_cost", "impact_cost", "assistant_runs"]:
			if not _int_field(costs, key): return {"available":false}
		var saved_impact := int(costs.impact_cost)
		assistant_cost = int(costs.usage_cost)
		if saved_impact != impact_cost: return {"available":false}
		impact_cost = saved_impact
		if costs.has("manual_cost"):
			if not _int_field(costs, "manual_cost"): return {"available":false}
			manual_cost = int(costs.manual_cost)
		if recovery_value is Dictionary and not recovery_value.is_empty() and int(recovery_value.manual_usage_cost) != manual_cost: return {"available":false}
		if costs.has("business_cost") and (not _int_field(costs, "business_cost") or int(costs.business_cost) != total_loss): return {"available":false}
		if total_loss > 0 and (not costs.has("business_cost") or int(costs.business_cost) != total_loss): return {"available":false}
	else:
		if impact_cost > 0 or total_loss > 0 or manual_cost > 0: return {"available":false}
	if manual_cost < 0: return {"available":false}
	return {
		"available":true,
		"preview":preview,
		"client":CLIENT,
		"elapsed":elapsed,
		"queues":queues,
		"loss_cost":total_loss,
		"impact_cost":impact_cost,
		"manual_cost":manual_cost,
		"assistant_cost":assistant_cost,
		"connector_status":connector_status,
		"rebuild_minutes":rebuild_minutes,
		"manual_minutes":manual_minutes,
		"manual_fee":manual_fee,
		"manual_remaining":manual_remaining,
		"clock_label":"対応開始から" if preview else "対応経過"
	}


static func from_offer(offer: Dictionary) -> Dictionary:
	if str(offer.get("case_id", "")) != CASE_ID: return {}
	var payload_value: Variant = offer.get("saas_priority_payload", null)
	if not payload_value is Dictionary: return {"available":false}
	var payload: Dictionary = payload_value
	if str(payload.get("client", "")) != "北斗物流": return {"available":false}
	var model: Dictionary = ENGINE.create_followup(payload)
	if model.is_empty(): return {"available":false}
	return _project(model, true)


static func from_context(context: Dictionary) -> Dictionary:
	var contract_value: Variant = context.get("contract", null)
	var contract: Dictionary = contract_value if contract_value is Dictionary else {}
	if str(contract.get("case_id", "")) != CASE_ID: return {}
	if not bool(context.get("accepted", false)): return {"available":false}
	var advanced_value: Variant = context.get("advanced", null)
	var work_value: Variant = context.get("work", null)
	if not advanced_value is Dictionary or not work_value is Dictionary: return {"available":false}
	var advanced: Dictionary = advanced_value
	if str(advanced.get("case_id", "")) != CASE_ID: return {"available":false}
	return _project(advanced, false, work_value)
