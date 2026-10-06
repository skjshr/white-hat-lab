extends RefCounted
## Evidence-bound projection for the partner-v1 record organizer.
## It reads only the explicitly selected top-level records and never consults a live VM.

const VERSION := 1

static func _valid_destinations(value: Variant) -> bool:
	if not value is Array: return false
	for row in value:
		if not row is Dictionary or str(row.get("destination", "")).is_empty() or str(row.get("destination", "")) == "unknown" or str(row.get("device", "")).is_empty(): return false
		var rows: Variant = row.get("rows", null)
		if typeof(rows) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(rows)) or float(rows) < 0.0 or float(rows) != floorf(float(rows)): return false
	return true

static func build(records_value: Variant, selected_ids_value: Variant, input_hash: String, created_minute: int, world_revision: int) -> Dictionary:
	if not records_value is Array or not selected_ids_value is Array or selected_ids_value.is_empty(): return {}
	var selected_ids: Dictionary = {}
	for raw_id in selected_ids_value:
		var record_id := str(raw_id)
		if record_id.is_empty() or selected_ids.has(record_id): return {}
		selected_ids[record_id] = true
	var selected: Array[Dictionary] = []
	for raw_record in records_value:
		if not raw_record is Dictionary: continue
		if selected_ids.has(str(raw_record.get("id", ""))): selected.append(raw_record)
	if selected.size() != selected_ids.size(): return {}
	selected.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_seq := int(a.get("seq", 0))
		var b_seq := int(b.get("seq", 0))
		if a_seq != b_seq: return a_seq < b_seq
		return str(a.get("id", "")) < str(b.get("id", ""))
	)

	var approval: Dictionary = {"state":"unknown","current_record_id":"","approved_change":"","destinations":[],"prior":[]}
	var approval_seq := -1
	var lanes_by_id: Dictionary = {}
	var prior_issues: Array[Dictionary] = []
	var prior_approvals: Array[Dictionary] = []
	for record in selected:
		var action := str(record.get("action", ""))
		var seq := int(record.get("seq", 0))
		var data: Variant = record.get("data", {})
		if not data is Dictionary: continue
		if action == "consent_review" and str(record.get("app", "")) == "app-19" and int(record.get("status", 0)) == 200 and _valid_destinations(data.get("approved_destinations", null)) and not str(data.get("approved_change", "")).is_empty() and seq >= approval_seq:
			approval_seq = seq
			approval = {
				"state":"known",
				"current_record_id":str(record.get("id", "")),
				"approved_change":str(data.get("approved_change", "")),
				"destinations":data.get("approved_destinations", []).duplicate(true),
				"prior":[]
			}
		if action == "baseline_reference":
			var original: Variant = data.get("original", null)
			if not original is Dictionary or int(original.get("status", 0)) != 200: continue
			var original_action := str(original.get("action", ""))
			var original_data: Variant = original.get("data", {})
			if not original_data is Dictionary: continue
			if original_action == "consent_review":
				var prior_approval := {
					"reference_record_id":str(record.get("id", "")),
					"source_record_id":str(data.get("source_record_id", original.get("id", ""))),
					"approved_change":str(original_data.get("approved_change", "")),
					"resource":str(original_data.get("resource", "")),
					"approved_devices":original_data.get("approved_devices", []).duplicate(true) if original_data.get("approved_devices", []) is Array else [],
					"destinations":original_data.get("approved_destinations", []).duplicate(true) if original_data.get("approved_destinations", []) is Array else []
				}
				prior_approvals.append(prior_approval)
			elif original_action == "session_issued":
				prior_issues.append({
					"record_id":str(record.get("id", "")),
					"source_record_id":str(data.get("source_record_id", original.get("id", ""))),
					"session_id":str(original_data.get("session_id", "")),
					"device":str(original_data.get("device", "")),
					"destination":str(original_data.get("destination", "")),
					"approved_change":str(original_data.get("approved_change", "")),
					"approved":original_data.get("approved", null)
				})
		elif action in ["session_issued", "reissue_connection"] and int(record.get("status", 0)) == 200:
			var session_id := str(data.get("session_id", ""))
			if session_id.is_empty(): continue
			var lane: Dictionary = lanes_by_id.get(session_id, {"session_id":session_id,"device":"","issued_record_id":"","prior_issue":{},"inspection_record_id":"","inspection_world_revision":-1,"inspection_fresh":false,"observed":{},"approval_record_id":"","approval_match":"unknown"})
			lane["device"] = str(data.get("device", lane.get("device", "")))
			lane["issued_record_id"] = str(record.get("id", ""))
			lanes_by_id[session_id] = lane
		elif action == "inspect_connection":
			var session_id := str(data.get("session_id", ""))
			if session_id.is_empty(): continue
			var lane: Dictionary = lanes_by_id.get(session_id, {"session_id":session_id,"device":"","issued_record_id":"","prior_issue":{},"inspection_record_id":"","inspection_world_revision":-1,"inspection_fresh":false,"observed":{},"approval_record_id":"","approval_match":"unknown"})
			lane["device"] = str(data.get("device", lane.get("device", "")))
			lane["inspection_record_id"] = str(record.get("id", ""))
			lane["inspection_world_revision"] = int(record.get("world_revision", data.get("world_revision", -1)))
			lane["inspection_status"] = int(record.get("status", 0))
			var observed_destination := str(data.get("destination", ""))
			var observed_rows: Variant = data.get("read_rows", null)
			var observed_valid := int(record.get("status", 0)) == 200 and not observed_destination.is_empty() and observed_destination != "unknown" and typeof(observed_rows) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(observed_rows)) and float(observed_rows) >= 0.0 and float(observed_rows) == floorf(float(observed_rows))
			lane["observed"] = {"destination":observed_destination,"rows":int(observed_rows)} if observed_valid else {}
			var source_record_id := str(data.get("source_record_id", ""))
			if str(lane.get("issued_record_id", "")).is_empty() and selected_ids.has(source_record_id): lane["issued_record_id"] = source_record_id
			lanes_by_id[session_id] = lane
	approval["prior"] = prior_approvals.duplicate(true)

	var lanes: Array[Dictionary] = []
	for session_id_value in lanes_by_id:
		var session_id := str(session_id_value)
		var lane: Dictionary = lanes_by_id[session_id].duplicate(true)
		var matched_prior: Dictionary = {}
		for prior in prior_issues:
			if not str(lane.get("device", "")).is_empty() and str(prior.get("device", "")) == str(lane.get("device", "")):
				matched_prior = prior
		lane["prior_issue"] = matched_prior
		var observed: Dictionary = lane.get("observed", {})
		if not observed.is_empty() and str(approval.get("state", "unknown")) == "known":
			var matched := false
			for authorized in approval.get("destinations", []):
				if not authorized is Dictionary: continue
				if str(authorized.get("destination", "")) == str(observed.get("destination", "")) and str(authorized.get("device", "")) == str(lane.get("device", "")) and int(authorized.get("rows", -1)) == int(observed.get("rows", -1)):
					matched = true
					break
			lane["approval_record_id"] = str(approval.get("current_record_id", ""))
			lane["approval_match"] = "match" if matched else "mismatch"
		lanes.append(lane)
	lanes.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("session_id", "")) < str(b.get("session_id", "")))
	return {
		"version":VERSION,
		"input_hash":input_hash,
		"record_ids":selected_ids_value.duplicate(true),
		"created_minute":created_minute,
		"world_revision":world_revision,
		"approval":approval,
		"lanes":lanes,
		"creates_evidence":false
	}

static func project(snapshot_value: Variant, current_world_revision: int) -> Dictionary:
	if not snapshot_value is Dictionary or snapshot_value.is_empty(): return {"available":false,"fresh":false,"state":"unknown","snapshot":{}}
	var snapshot: Dictionary = snapshot_value.duplicate(true)
	var fresh := int(snapshot.get("world_revision", -1)) == current_world_revision
	var lanes: Variant = snapshot.get("lanes", [])
	if lanes is Array:
		for lane in lanes:
			if not lane is Dictionary: continue
			var has_inspection := not str(lane.get("inspection_record_id", "")).is_empty()
			lane["inspection_fresh"] = has_inspection and int(lane.get("inspection_world_revision", -1)) == current_world_revision
		snapshot["lanes"] = lanes
	return {"available":true,"fresh":fresh,"state":"current" if fresh else "stale","snapshot":snapshot}
