extends RefCounted

const CARE = preload("res://scripts/care_lifecycle.gd")
const DISPATCH_GUARD_META := "_maintenance_dispatch_active"


static func candidates(g) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	if g == null or not g is Object:
		return result
	var roster: Variant = g.call("team_members") if g.has_method("team_members") else []
	if not roster is Array:
		roster = []
	for raw_member in roster:
		if not raw_member is Dictionary:
			continue
		var member_id := str(raw_member.get("id", "")).strip_edges()
		if member_id.is_empty() or seen.has(member_id):
			continue
		seen[member_id] = true
		var fallback_name := member_id
		if g.has_method("member_name"):
			fallback_name = str(g.call("member_name", member_id))
		var member_name := str(raw_member.get("name", fallback_name))
		if member_name.is_empty():
			member_name = fallback_name
		result.append({"id":member_id, "name":member_name})
	return result


static func owner(g, client: String) -> String:
	var state: Variant = _state(g)
	if not state is Dictionary:
		return ""
	var agreements: Variant = state.get("care_agreements", {})
	if not agreements is Dictionary:
		return ""
	var agreement: Variant = agreements.get(client.strip_edges(), {})
	if not agreement is Dictionary:
		return ""
	return str(agreement.get("maintenance_owner", "")).strip_edges()


static func set_owner(g, client: String, member_id: String) -> bool:
	if g == null or not g is Object or not g.has_method("save_game"):
		return false
	var name := client.strip_edges()
	var selected := member_id.strip_edges()
	var state: Variant = _state(g)
	if not state is Dictionary or name.is_empty():
		return false
	var agreements: Variant = state.get("care_agreements", {})
	if not agreements is Dictionary or not agreements.has(name):
		return false
	var agreement: Variant = agreements.get(name, {})
	if not agreement is Dictionary:
		return false
	if not selected.is_empty() and not _candidate_ids(g).has(selected):
		return false
	var current := str(agreement.get("maintenance_owner", "")).strip_edges()
	if current == selected:
		return true
	var previous: Dictionary = state.duplicate(true)
	agreement["maintenance_owner"] = selected
	agreements[name] = agreement
	state["care_agreements"] = agreements
	g.set("state", state)
	var saved: Variant = g.call("save_game")
	if not bool(saved):
		g.set("state", previous)
		return false
	if g.has_signal("changed"):
		g.changed.emit()
	return true


static func prioritize(g, client: String) -> bool:
	if g == null or not g is Object or not g.has_method("save_game"):
		return false
	var name := client.strip_edges()
	var state: Variant = _state(g)
	if name.is_empty() or not state is Dictionary:
		return false
	var agreements: Variant = state.get("care_agreements", {})
	if not agreements is Dictionary or not agreements.has(name):
		return false
	var previous: Dictionary = state.duplicate(true)
	var working: Dictionary = previous.duplicate(true)
	var order: Array = state.get("maintenance_priority", []) if state.get("maintenance_priority", []) is Array else []
	var normalized: Array = []
	for raw in order:
		var existing := str(raw).strip_edges()
		if not existing.is_empty() and existing not in normalized:
			normalized.append(existing)
	var before_order: Array = normalized.duplicate()
	if name in normalized:
		normalized.erase(name)
	normalized.push_front(name)
	if normalized == before_order:
		return true
	working.maintenance_priority = normalized
	g.set("state", working)
	if not bool(g.call("save_game")):
		g.set("state", previous)
		return false
	if g.has_signal("changed"):
		g.changed.emit()
	return true


static func dispatch(g) -> bool:
	if g == null or not g is Object or not g.has_method("maintenance_jobs"):
		return false
	if g.has_meta(DISPATCH_GUARD_META) and bool(g.get_meta(DISPATCH_GUARD_META, false)):
		return false
	g.set_meta(DISPATCH_GUARD_META, true)
	var changed := false
	var raw_jobs: Variant = g.call("maintenance_jobs")
	var pending: Array = []
	if raw_jobs is Array:
		for raw_job in raw_jobs:
			if raw_job is Dictionary and str(raw_job.get("status", "")) == "pending":
				pending.append(raw_job)
	var priority: Array = state_priority(g)
	pending.sort_custom(func(left, right):
		var left_client := str(left.get("client", ""))
		var right_client := str(right.get("client", ""))
		var left_priority := priority.find(left_client) if left_client in priority else priority.size()
		var right_priority := priority.find(right_client) if right_client in priority else priority.size()
		if left_priority != right_priority:
			return left_priority < right_priority
		if left_client == right_client:
			return str(left.get("id", "")) < str(right.get("id", ""))
		return left_client < right_client
	)
	for job in pending:
		var client := str(job.get("client", "")).strip_edges()
		if client.is_empty():
			continue
		if g.has_method("_dispatch_has_queued_maintenance") and bool(g.call("_dispatch_has_queued_maintenance", client)):
			continue
		var member_id := owner(g, client)
		if member_id.is_empty() or not _candidate_ids(g).has(member_id) or bool(g.state.get("dispatch_holds",{}).get(member_id,false)):
			continue
		if g.has_method("_dispatch_has_queued") and bool(g.call("_dispatch_has_queued", member_id)):
			continue
		if not g.has_method("can_run_maintenance") or not bool(g.call("can_run_maintenance", client)):
			continue
		if CARE._busy_client(g, client):
			continue
		if not g.has_method("staff_availability") or not str(g.call("staff_availability", member_id, "maintenance")).is_empty():
			continue
		if not g.has_method("colleague_runtime_availability"):
			continue
		var runtime: Variant = g.call("colleague_runtime_availability", member_id)
		if not runtime is Dictionary or not bool(runtime.get("registered", false)) or not bool(runtime.get("available", false)):
			continue
		if not g.has_method("assign_maintenance"):
			continue
		if bool(g.call("assign_maintenance", client, member_id)):
			changed = true
	_clear_dispatch_guard(g)
	return changed


static func _state(g) -> Variant:
	if g == null or not g is Object:
		return null
	return g.get("state")


static func _candidate_ids(g) -> Array:
	var ids: Array = []
	for item in candidates(g):
		if item is Dictionary:
			ids.append(str(item.get("id", "")))
	return ids


static func state_priority(g) -> Array:
	var state: Variant = _state(g)
	var raw_priority: Variant = state.get("maintenance_priority", []) if state is Dictionary else []
	if raw_priority is Array:
		var result: Array = []
		for raw in raw_priority:
			var client := str(raw).strip_edges()
			if not client.is_empty() and client not in result:
				result.append(client)
		return result
	return []


static func _clear_dispatch_guard(g) -> void:
	if g != null and g is Object and g.has_meta(DISPATCH_GUARD_META):
		g.remove_meta(DISPATCH_GUARD_META)
