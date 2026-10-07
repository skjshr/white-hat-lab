extends RefCounted
## Read-only projection of saved colleague work and target acceptance.

static func from_context(context: Dictionary, target_index: int, assignments: Dictionary) -> Dictionary:
	var unavailable_acceptance := {"state":"unknown","passed":0,"total":0,"checks":[],"revision":-1,"validated_revision":-1,"inspected":false}
	var unavailable := {"available":false,"contract_id":"","target_index":target_index,"accepted":false,"completed":false,"current_jobs":[],"receipts":[],"acceptance":unavailable_acceptance}
	var targets_value: Variant = context.get("targets", [])
	if not targets_value is Array or target_index < 0 or target_index >= targets_value.size() or not targets_value[target_index] is Dictionary:
		return unavailable
	var contract_id := str(context.get("id", ""))
	var target: Dictionary = targets_value[target_index]
	var checks: Array = target.get("checks", []).duplicate(true) if target.get("checks", []) is Array else []
	var revision := _saved_integer(target, "revision", -1)
	var validated_revision := _saved_integer(target, "validated_revision", -1)
	var inspected := bool(target.get("inspected", false))
	var historical := false
	if checks.is_empty():
		var last_acceptance_value: Variant = target.get("last_acceptance", {})
		if last_acceptance_value is Dictionary:
			var last_checks_value: Variant = last_acceptance_value.get("checks", [])
			if last_checks_value is Array and not last_checks_value.is_empty():
				checks = last_checks_value.duplicate(true)
				validated_revision = _saved_integer(last_acceptance_value, "validated_revision", -1)
				historical = true
	var accepted := bool(context.get("accepted", false))
	var passed := 0
	for check in checks:
		if check is Dictionary and bool(check.get("passed", false)):
			passed += 1
	var acceptance_state := "unknown"
	if not checks.is_empty():
		if not accepted:
			acceptance_state = "unknown"
		elif historical:
			# The live check set was cleared. A historical receipt cannot restore
			# acceptance, even when a legacy save reused the revision number.
			acceptance_state = "stale"
		elif not inspected or revision < 0 or validated_revision < 0 or revision != validated_revision:
			acceptance_state = "stale"
		elif passed != checks.size():
			acceptance_state = "failed"
		else:
			# ready means only that the saved checks pass for this inspected revision.
			# Delivery remains the separate `completed` field below.
			acceptance_state = "ready"
	var acceptance := {"state":acceptance_state,"passed":passed,"total":checks.size(),"checks":checks,"revision":revision,"validated_revision":validated_revision,"inspected":inspected,"historical":historical}
	var receipts: Array = []
	var receipt_members: Dictionary = {}
	var saved_receipts: Variant = target.get("work_receipts", [])
	if saved_receipts is Array:
		for raw_receipt in saved_receipts:
			if not raw_receipt is Dictionary:
				continue
			if raw_receipt.has("contract_id") and str(raw_receipt.get("contract_id", "")) != contract_id:
				continue
			if raw_receipt.has("target_index") and int(raw_receipt.get("target_index", -1)) != target_index:
				continue
			var receipt := _normalize_receipt(raw_receipt)
			receipts.append(receipt)
			var member_id := str(receipt.get("member_id", ""))
			if not member_id.is_empty(): receipt_members[member_id] = true
	var current_jobs: Array = []
	for raw_member_id in assignments.keys():
		var member_id := str(raw_member_id)
		var assignment_value: Variant = assignments[raw_member_id]
		if not assignment_value is Dictionary:
			continue
		var assignment: Dictionary = assignment_value
		if str(assignment.get("kind", "normal")) != "normal" or str(assignment.get("contract_id", "")) != contract_id or int(assignment.get("target_index", -1)) != target_index:
			continue
		var status := str(assignment.get("status", ""))
		if status == "done":
			# Old saves only retained the last assignment per person. Preserve it as
			# a clearly time-unknown receipt until load migration makes it durable.
			if not receipt_members.has(member_id):
				receipts.append(_legacy_receipt(member_id, assignment, contract_id, target_index))
				receipt_members[member_id] = true
		elif status in ["pending", "working"]:
			current_jobs.append(_current_job(member_id, assignment))
	return {"available":true,"contract_id":contract_id,"target_index":target_index,"accepted":accepted,"completed":bool(context.get("completed", false)),"current_jobs":current_jobs,"receipts":receipts,"acceptance":acceptance}


static func _saved_integer(source: Dictionary, key: String, fallback: int) -> int:
	if not source.has(key):
		return fallback
	var value: Variant = source[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)):
		return fallback
	return int(value)


static func _normalize_receipt(source: Dictionary) -> Dictionary:
	var receipt := source.duplicate(true)
	var day := _saved_integer(receipt, "completed_day", -1)
	var minute := _saved_integer(receipt, "completed_minute", -1)
	var time_known := bool(receipt.get("time_known", day >= 1 and minute >= 0 and minute < 1440)) and day >= 1 and minute >= 0 and minute < 1440
	receipt["time_known"] = time_known
	if not time_known:
		receipt["completed_day"] = -1
		receipt["completed_minute"] = -1
	if not receipt.has("work_minutes"):
		receipt["work_minutes"] = -1.0
	receipt["legacy"] = bool(receipt.get("legacy", false))
	return receipt


static func _legacy_receipt(member_id: String, assignment: Dictionary, contract_id: String, target_index: int) -> Dictionary:
	return {
		"job_id":"",
		"contract_id":contract_id,
		"target_index":target_index,
		"member_id":member_id,
		"member_name":"",
		"role":str(assignment.get("role", "")),
		"phase":str(assignment.get("phase", "")),
		"result":str(assignment.get("result", "")),
		"result_path":str(assignment.get("result_path", "")),
		"revision":_saved_integer(assignment, "revision", -1),
		"completed_day":-1,
		"completed_minute":-1,
		"time_known":false,
		"work_minutes":_saved_number(assignment, "work_minutes_accounted", -1.0),
		"legacy":true
	}


static func _saved_number(source: Dictionary, key: String, fallback: float) -> float:
	if not source.has(key):
		return fallback
	var value: Variant = source[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return float(value)


static func _current_job(member_id: String, assignment: Dictionary) -> Dictionary:
	return {
		"job_id":str(assignment.get("job_id", "")),
		"member_id":member_id,
		"member_name":str(assignment.get("member_name", "")),
		"role":str(assignment.get("role", "")),
		"status":str(assignment.get("status", "")),
		"phase":str(assignment.get("phase", "")),
		"result":str(assignment.get("result", "")),
		"result_path":str(assignment.get("result_path", "")),
		"work_minutes":_saved_number(assignment, "work_minutes", _saved_number(assignment, "total", -1.0))
	}
