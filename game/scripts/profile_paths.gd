extends RefCounted
## Only path keys are migrated; document bodies and terminal history are preserved.

static func home(path: String) -> String:
	var prefix := "workstation:" if path.begins_with("workstation:") else ""
	var value := path.trim_prefix(prefix) if not prefix.is_empty() else path
	for legacy in ["/home/aoba", "/home/wakaba"]:
		if value == legacy or value.begins_with(legacy+"/"):
			return prefix+"/home/operator"+value.substr(legacy.length())
	return path

static func migrate_keys(values: Dictionary) -> bool:
	var changed := false
	for key in values.keys():
		var canonical := home(str(key))
		if canonical == str(key): continue
		# Never overwrite two independently edited files or drafts.
		if values.has(canonical) and values[canonical] != values[key]: continue
		values[canonical] = values[key]
		values.erase(key)
		changed = true
	return changed

static func migrate(state: Dictionary) -> bool:
	var changed := false
	var local: Dictionary = state.get("os_files", {})
	changed = migrate_keys(local) or changed
	for session_key in state.get("desktop_sessions", {}):
		var session: Dictionary = state.desktop_sessions[session_key]
		var drafts: Dictionary = session.get("drafts", {})
		var remote_files: Dictionary = state.get("vm_states", {}).get(session_key, {}).get("fs", {})
		for old_key in drafts.keys():
			var canonical := _safe_path(str(old_key), local, remote_files, {})
			if canonical == old_key or (drafts.has(canonical) and drafts[canonical] != drafts[old_key]): continue
			drafts[canonical] = drafts[old_key]; drafts.erase(old_key); changed = true
		for key in ["editor_path", "directory"]:
			var old := str(session.get(key, ""))
			var canonical := _safe_path(old, local, remote_files, drafts)
			if canonical != old: session[key] = canonical; changed = true
		for key in ["file_history", "file_forward_history"]:
			for location in session.get(key, []):
				var old := str(location.get("path", ""))
				var canonical := _safe_path(old, local if not location.get("remote",true) else {}, remote_files, {})
				if canonical != old: location.path=canonical; changed=true
	return changed

static func _safe_path(path: String, local: Dictionary, remote: Dictionary, drafts: Dictionary) -> String:
	var canonical := home(path)
	if canonical == path: return path
	if drafts.has(path): return path
	var files: Dictionary = local if path.begins_with("workstation:") else remote
	var old := path.trim_prefix("workstation:")
	var target := canonical.trim_prefix("workstation:")
	if files.has(old) and files.has(target) and files[old] != files[target]: return path
	return canonical
