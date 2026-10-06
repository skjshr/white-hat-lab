extends RefCounted
## Pure projection of recorded sync outcomes and not-yet-due inputs.

static func _observed(raw: Variant, fallback_rows: int = 0) -> Dictionary:
	if not raw is Dictionary or raw.is_empty(): return {}
	var record: Dictionary = raw
	var data_value: Variant = record.get("data", {})
	var data: Dictionary = data_value if data_value is Dictionary else {}
	var action := str(record.get("action", ""))
	var rows_value: Variant = data.get("read_rows", fallback_rows) if action == "scheduled_customer_read" else data.get("summary_rows", fallback_rows) if action == "run_business" else data.get("row_count", fallback_rows)
	return {
		"record_id":str(record.get("id", "")),
		"minute":int(record.get("minute", -1)),
		"status":int(record.get("status", 0)),
		"rows":int(rows_value) if typeof(rows_value) in [TYPE_INT, TYPE_FLOAT] else fallback_rows,
		"destination":str(record.get("destination", "")),
		"world_revision":int(record.get("world_revision", record.get("revision", -1))),
		"policy_revision":int(data.get("policy_revision", -1)),
		"blocked_reason":str(data.get("blocked_reason", ""))
	}

static func build(state: Dictionary) -> Dictionary:
	var records_value: Variant = state.get("records", [])
	var records: Array = records_value if records_value is Array else []
	var egress_value: Variant = state.get("egress", {})
	var egress: Dictionary = egress_value if egress_value is Dictionary else {}
	var export_value: Variant = egress.get("exported_rows", [])
	var exported_rows: Array = export_value if export_value is Array else []
	var schedule_value: Variant = egress.get("schedule", [])
	var schedule: Array = schedule_value if schedule_value is Array else []
	var ai_value: Variant = state.get("ai_preflight", {})
	var ai: Dictionary = ai_value if ai_value is Dictionary else {}
	var business_value: Variant = ai.get("business", {})
	var business: Dictionary = business_value if business_value is Dictionary else {}
	var now := int(state.get("elapsed_minutes", 0))

	# Group only recorded read/write actions. The schedule list supplies future
	# due times, never a guessed result for a scheduled item.
	var grouped: Dictionary = {}
	var latest_business: Dictionary = {}
	var first_receipt: Dictionary = {}
	var late_record: Dictionary = {}
	for raw in records:
		if not raw is Dictionary: continue
		var record: Dictionary = raw
		var action := str(record.get("action", ""))
		if action in ["scheduled_customer_read", "scheduled_external_write"]:
			var data_value: Variant = record.get("data", {})
			var data: Dictionary = data_value if data_value is Dictionary else {}
			var schedule_id := str(data.get("schedule_id", ""))
			var group_key := schedule_id if not schedule_id.is_empty() else "missing:%s" % str(record.get("id", ""))
			if not grouped.has(group_key): grouped[group_key] = {"id":schedule_id,"read_record":{},"write_record":{},"record_ids":[]}
			var group: Dictionary = grouped[group_key]
			if action == "scheduled_customer_read": group["read_record"] = record
			else: group["write_record"] = record
			var ids: Array = group.get("record_ids", [])
			var record_id := str(record.get("id", ""))
			if not record_id.is_empty() and record_id not in ids: ids.append(record_id)
			group["record_ids"] = ids
			grouped[group_key] = group
		elif action == "run_business":
			if latest_business.is_empty() or int(record.get("seq", -1)) > int(latest_business.get("seq", -1)): latest_business = record
			var receipt_id := str(record.get("data", {}).get("receipt_id", ""))
			if int(record.get("status", 0)) == 200 and not receipt_id.is_empty():
				if first_receipt.is_empty() or int(record.get("seq", 2147483647)) < int(first_receipt.get("seq", 2147483647)): first_receipt = record
		elif action == "summary_overdue":
			if late_record.is_empty() or int(record.get("seq", -1)) > int(late_record.get("seq", -1)): late_record = record

	var event_costs: Dictionary = {}
	var event_rows_from_copies: Dictionary = {}
	var event_minutes_from_copies: Dictionary = {}
	var total_rows := 0
	for raw_copy in exported_rows:
		if not raw_copy is Dictionary: continue
		var copy: Dictionary = raw_copy
		total_rows += 1
		var schedule_id := str(copy.get("schedule_id", ""))
		if schedule_id.is_empty(): continue
		event_costs[schedule_id] = int(event_costs.get(schedule_id, 0)) + int(copy.get("cost", 0))
		event_rows_from_copies[schedule_id] = int(event_rows_from_copies.get(schedule_id, 0)) + 1
		var copy_minute := int(copy.get("minute", -1))
		var old_copy_minute := int(event_minutes_from_copies.get(schedule_id, -1))
		if not event_minutes_from_copies.has(schedule_id) or (copy_minute >= 0 and (old_copy_minute < 0 or copy_minute < old_copy_minute)): event_minutes_from_copies[schedule_id] = copy_minute
		if not grouped.has(schedule_id): grouped[schedule_id] = {"id":schedule_id,"read_record":{},"write_record":{},"record_ids":[]}

	var events: Array[Dictionary] = []
	for group_value in grouped.values():
		var group: Dictionary = group_value
		var id := str(group.get("id", ""))
		var read_record: Dictionary = group.get("read_record", {})
		var write_record: Dictionary = group.get("write_record", {})
		var read := _observed(read_record)
		var write := _observed(write_record, int(event_rows_from_copies.get(id, 0)))
		var read_minute := int(read.get("minute", -1))
		var write_minute := int(write.get("minute", -1))
		var event_minute := read_minute if read_minute >= 0 else write_minute
		if read_minute < 0 and write_minute < 0: event_minute = int(event_minutes_from_copies.get(id, -1))
		if read_minute >= 0 and write_minute >= 0 and read_minute != write_minute: event_minute = -1
		var read_revision := int(read.get("world_revision", -1))
		var write_revision := int(write.get("world_revision", -1))
		var event_revision := read_revision if read_revision >= 0 else write_revision
		if read_revision >= 0 and write_revision >= 0 and read_revision != write_revision: event_revision = -1
		var observed_rows := maxi(int(write.get("rows", 0)) if not write.is_empty() else 0,int(event_rows_from_copies.get(id, 0)))
		var record_ids: Array = group.get("record_ids", []).duplicate()
		var event := {"id":id,"minute":event_minute,"world_revision":event_revision,"read":read,"write":write,"rows":observed_rows,"impact_cost":int(event_costs.get(id, 0)),"record_ids":record_ids}
		events.append(event)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_minute := int(a.get("minute", -1)); var b_minute := int(b.get("minute", -1))
		if a_minute == b_minute: return str(a.get("id", "")) < str(b.get("id", ""))
		if a_minute < 0: return false
		if b_minute < 0: return true
		return a_minute < b_minute)

	var pending: Array[Dictionary] = []
	for raw_event in schedule:
		if not raw_event is Dictionary: continue
		var scheduled: Dictionary = raw_event
		if str(scheduled.get("status", "")) == "scheduled":
			pending.append({"id":str(scheduled.get("id", "")),"minute":int(scheduled.get("due_minute", -1))})
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_minute := int(a.get("minute", -1)); var b_minute := int(b.get("minute", -1))
		if a_minute == b_minute: return str(a.get("id", "")) < str(b.get("id", ""))
		if a_minute < 0: return false
		if b_minute < 0: return true
		return a_minute < b_minute)

	var deadline_minute := int(business.get("deadline_minute", 14))
	var received_minute := int(first_receipt.get("minute", -1)) if not first_receipt.is_empty() else -1
	var received_count := 0
	var deadline_record_id := ""
	var deadline_status := "waiting"
	if not first_receipt.is_empty():
		var first_data_value: Variant = first_receipt.get("data", {})
		var first_data: Dictionary = first_data_value if first_data_value is Dictionary else {}
		var summaries_value: Variant = first_data.get("summaries", [])
		var summaries: Array = summaries_value if summaries_value is Array else []
		received_count = int(first_data.get("summary_rows", summaries.size()))
		deadline_record_id = str(first_receipt.get("id", ""))
		if received_minute >= 0: deadline_status = "met" if received_minute <= deadline_minute else "late"
		else: deadline_status = "unknown"
	if not late_record.is_empty():
		deadline_status = "late"
	if bool(business.get("late", false)):
		# Older saves may retain the lateness flag but not its source record.
		# Explicit lateness takes precedence without manufacturing an event ID.
		deadline_status = "late"
	var deadline := {"minute":deadline_minute,"status":deadline_status,"received_minute":received_minute,"received_count":received_count,"record_id":deadline_record_id,"late_record_id":str(late_record.get("id", "")),"loss_cost":int(business.get("loss_cost", 0))}

	return {
		"now":now,
		"events":events,
		"pending":pending,
		"deadline":deadline,
		"business_event":_observed(latest_business),
		"total_rows":total_rows,
		"total_impact_cost":int(egress.get("impact_cost", 0))
	}
