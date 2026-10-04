extends RefCounted
## Read-only projection of the equipment contribution locked into real work.
## Current ownership alone is never evidence that an older job used the bonus.
const UI = preload("res://scripts/ui_theme.gd")

static func build(game, equipment_id := "monitor") -> Dictionary:
	var state: Dictionary = game.state
	var result := {"installed":equipment_id in state.get("equipment", []), "jobs":[]}
	if not result.installed or equipment_id != "monitor": return result
	var assignments: Dictionary = state.get("assignments", {})
	for member_id in assignments:
		_append_job(result.jobs, game, str(member_id), assignments[member_id], equipment_id)
	for member_id in state.get("dispatch_queues", {}):
		for job in state.dispatch_queues[member_id]:
			_append_job(result.jobs, game, str(member_id), job, equipment_id)
	var order := {"active":0, "waiting":1, "blocked":2, "paused":3, "queued":4, "done":5}
	result.jobs.sort_custom(func(a, b):
		var a_rank: int = int(order.get(str(a.mode), 9))
		var b_rank: int = int(order.get(str(b.mode), 9))
		return a_rank < b_rank if a_rank != b_rank else str(a.key) < str(b.key)
	)
	return result

static func _append_job(jobs: Array, game, member_id: String, raw: Variant, equipment_id: String) -> void:
	if not raw is Dictionary: return
	var job: Dictionary = raw
	if str(job.get("kind", "normal")) != "normal": return
	var status := str(job.get("status", ""))
	if status not in ["working", "done", "paused", "queued"]: return
	var key := str(job.get("equipment_work_id", ""))
	var effects: Variant = job.get("equipment_effects", {})
	if key.is_empty() or not effects is Dictionary: return
	var effect: Variant = effects.get(equipment_id, {})
	if not effect is Dictionary or effect.is_empty(): return
	var base := float(effect.get("base_minutes", 0.0))
	var actual := float(effect.get("actual_minutes", 0.0))
	var saved := float(effect.get("saved_minutes", 0.0))
	var total := float(job.get("total", 0.0))
	if not is_finite(base) or not is_finite(actual) or not is_finite(saved) or not is_finite(total): return
	if saved <= 0.0 or actual <= 0.0 or total <= 0.0 or not is_equal_approx(base - actual, saved): return
	if not is_equal_approx(actual, float(job.get("work_minutes", total))): return
	for existing in jobs:
		if str(existing.key) == key: return
	var remaining := clampf(float(job.get("remaining", total)), 0.0, total)
	var progress := 1.0 - remaining / total
	var mode := "done" if status == "done" else "paused" if status == "paused" else "queued" if status == "queued" else "active"
	if status == "working":
		if bool(game.get("_office_clock_paused")):
			mode = "paused"
		elif game.has_method("_colleague_hardware_connected") and not bool(game._colleague_hardware_connected(job)):
			mode = "blocked"
		elif (game.has_method("colleague_runtime_availability") and not bool(game.colleague_runtime_availability(member_id).available)) or str(job.get("phase", "")) == UI.copy("dispatch_waiting") or progress <= 0.00001:
			mode = "waiting"
	var state: Dictionary = game.state
	var contract_id := str(job.get("contract_id", ""))
	var contract: Dictionary = state.get("contract", {}) if contract_id.is_empty() or contract_id == str(state.get("current_contract_id", "")) else state.get("contract_contexts", {}).get(contract_id, {}).get("contract", {})
	var role := str(job.get("role", ""))
	jobs.append({"key":key, "mode":mode, "member_id":member_id, "member_name":str(game.member_name(member_id)) if game.has_method("member_name") else member_id, "role":role, "client":str(contract.get("client", job.get("client", ""))), "title":str(contract.get("title", job.get("title", ""))), "progress":1.0 if mode == "done" else progress, "remaining":remaining, "total":total, "base_minutes":base, "actual_minutes":actual, "saved_minutes":saved})
