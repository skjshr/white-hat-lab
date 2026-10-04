extends RefCounted
## Customer-approved recovery scope. Guest files cannot modify this saved record.
## Capture only while creating a new authored case, never from a loaded filesystem.
const VERSION := 1
const CASE_ID := "service-1-case-3"
const SOURCE_ROOT := "/srv/data/"
const RESTORE_ROOT := "/restore"
const MANIFEST_PATH := "/home/operator/recovery-manifest.sha256"

static func initialize(state: Dictionary, scenario: Dictionary, normal_files: Dictionary) -> void:
	if not bool(scenario.get("backup_preservation_required", false)): return
	if state.has("backup_authorization_version") or state.has("backup_authorization"): return
	var required: Array = scenario.get("required_files", []).duplicate()
	var protected_files := {}
	for path in state.get("fs", {}):
		if str(path).begins_with(SOURCE_ROOT):
			protected_files[str(path)] = {"exists":true,"sha256":str(state.fs[path]).sha256_text()}
	var expected_files := {}
	for path in required:
		var name := str(path).get_file()
		if normal_files.has(name): expected_files[str(path)] = str(normal_files[name]).sha256_text()
	state.backup_authorization_version = VERSION
	state.backup_authorization = {"version":VERSION,"case_id":str(scenario.get("id", CASE_ID)),"restore_root":RESTORE_ROOT,"required_files":required,"expected_files":expected_files,"protected_files":protected_files}
	state.backup_restore_origins = {}

static func _version(value: Variant) -> bool:
	return (value is int or value is float) and float(value) == float(VERSION)

static func _valid(state: Dictionary) -> bool:
	if not _version(state.get("backup_authorization_version")): return false
	var raw: Variant = state.get("backup_authorization")
	if not raw is Dictionary: return false
	if not _version(raw.get("version")) or not raw.get("case_id") is String or str(raw.get("restore_root", "")) != RESTORE_ROOT: return false
	if not raw.get("required_files") is Array or raw.required_files.is_empty(): return false
	if not raw.get("expected_files") is Dictionary or not raw.get("protected_files") is Dictionary or raw.protected_files.is_empty(): return false
	for path in raw.required_files:
		if not path is String or not path.begins_with(SOURCE_ROOT): return false
		if not raw.expected_files.get(path) is String or str(raw.expected_files[path]).length() != 64: return false
		if not raw.protected_files.has(path): return false
	for path in raw.protected_files:
		var item: Variant = raw.protected_files[path]
		if not path is String or not path.begins_with(SOURCE_ROOT) or not item is Dictionary: return false
		if not item.get("exists") is bool or not item.get("sha256") is String or str(item.sha256).length() != 64: return false
	return true

static func view(state: Dictionary, restored_paths: Dictionary) -> Dictionary:
	var scenario: Dictionary = state.get("scenario", {}) if state.get("scenario", {}) is Dictionary else {}
	var known := state.has("backup_authorization_version") or state.has("backup_authorization") or bool(scenario.get("backup_preservation_required", false))
	var available := known or (str(scenario.get("id", "")) == CASE_ID and str(scenario.get("backup_acceptance_mode", "")) != "production_replacement")
	var result := {"available":available,"enforced":known,"legacy":available and not known,"manifest_path":MANIFEST_PATH,"restore_root":RESTORE_ROOT,"required_files":[],"restored":[],"protected":[],"original_preserved":false,"unrelated_preserved":false,"restore_valid":false,"accepted":false,"selected_snapshot":"","last_restore_snapshot":"","error":""}
	if not known: return result
	if not _valid(state): result.error = "invalid_authorization_record"; return result
	var record: Dictionary = state.backup_authorization
	var fs: Dictionary = state.get("fs", {})
	var last: Dictionary = state.get("last_restore", {}) if state.get("last_restore", {}) is Dictionary else {}
	result.required_files = record.required_files.duplicate()
	result.last_restore_snapshot = str(last.get("snapshot", ""))
	var origins: Dictionary = state.get("backup_restore_origins", {}) if state.get("backup_restore_origins", {}) is Dictionary else {}
	var restore_valid := true
	var selected_ids: Array[String] = []
	for source in record.required_files:
		var path := str(restored_paths.get(source, ""))
		var origin: Dictionary = origins.get(source, {}) if origins.get(source, {}) is Dictionary else {}
		var snapshot_id := str(origin.get("snapshot", ""))
		var expected := str(record.expected_files[source])
		var exists := fs.has(path)
		var current := str(fs.get(path, "")).sha256_text() if exists else ""
		var permitted := path.begins_with(RESTORE_ROOT + "/") and path == path.simplify_path()
		var origin_matches := not snapshot_id.is_empty() and str(origin.get("path", "")) == path and str(origin.get("sha256", "")) == current
		var matched := exists and permitted and current == expected and origin_matches
		result.restored.append({"source":source,"path":path,"snapshot":snapshot_id,"exists":exists,"expected_sha256":expected,"current_sha256":current,"permitted":permitted,"matched":matched})
		if not snapshot_id.is_empty() and snapshot_id not in selected_ids: selected_ids.append(snapshot_id)
		restore_valid = restore_valid and matched
	if selected_ids.size() == 1: result.selected_snapshot = selected_ids[0]
	var original_preserved := true
	var unrelated_preserved := true
	var paths: Array = record.protected_files.keys()
	for path in fs:
		if str(path).begins_with(SOURCE_ROOT) and path not in paths: paths.append(path)
	paths.sort()
	for path in paths:
		var original: bool = path in record.required_files
		var expected: Dictionary = record.protected_files.get(path, {"exists":false,"sha256":""})
		var exists := fs.has(path)
		var current := str(fs.get(path, "")).sha256_text() if exists else ""
		var preserved := exists == bool(expected.exists) and current == str(expected.sha256)
		result.protected.append({"path":path,"kind":"original" if original else "unrelated","exists":exists,"expected_exists":bool(expected.exists),"preserved":preserved,"expected_sha256":str(expected.sha256),"current_sha256":current})
		if original: original_preserved = original_preserved and preserved
		else: unrelated_preserved = unrelated_preserved and preserved
	result.original_preserved = original_preserved
	result.unrelated_preserved = unrelated_preserved
	result.restore_valid = restore_valid
	result.accepted = restore_valid and original_preserved and unrelated_preserved
	return result
