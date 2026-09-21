class_name EndpointRemediation
extends RefCounted

const MALICIOUS_BYTES := "TRAINING FIXTURE: sync-agent.exe unsigned persistence demo"
const MALICIOUS_SHA256 := "4002e477aa90fb29e310435f8b620e589f02afb5a64c2673a51a7f61088a1986"

static func enabled(state: Dictionary) -> bool:
	var scenario: Dictionary = state.get("scenario", {}) if state.get("scenario", {}) is Dictionary else {}
	return bool(scenario.get("edr_recovery_required", false))

static func initialize(state: Dictionary) -> void:
	if state.has("edr_files"): return
	state.edr_files = []
	state.edr_processes = []
	state.edr_persistence = []
	state.edr_quarantine = []
	state.edr_scans = {}
	var dirs: Array = state.get("dirs", []) if state.get("dirs", []) is Array else []
	for directory in ["/endpoints", "/endpoints/pc_a", "/endpoints/pc_b"]:
		if directory not in dirs: dirs.append(directory)
	state.dirs = dirs
	var fs: Dictionary = state.get("fs", {}) if state.get("fs", {}) is Dictionary else {}
	for device in ["pc_a", "pc_b"]:
		_add_file(state, fs, device, "%s-office" % device, "office.exe", "/endpoints/%s/office.exe" % device, "Signed Business Suite", "CHG-EDR-OFFICE-2026", true)
		_add_file(state, fs, device, "%s-backup" % device, "backup-agent.exe", "/endpoints/%s/backup-agent.exe" % device, "unsigned", "CHG-EDR-BACKUP-2026")
		if device == "pc_a":
			_add_file(state, fs, device, "%s-sync" % device, "sync-agent.exe", "/endpoints/%s/sync-agent.exe" % device, "Unsigned", "")
		state.edr_processes.append({"device":device,"file_id":"%s-office" % device,"sha256":_seed_hash("office.exe"),"running":true})
		state.edr_processes.append({"device":device,"file_id":"%s-backup" % device,"sha256":_seed_hash("backup-agent.exe"),"running":true})
		if device == "pc_a": state.edr_processes.append({"device":device,"file_id":"%s-sync" % device,"sha256":MALICIOUS_SHA256,"running":true})
		state.edr_persistence.append({"device":device,"file_id":"%s-backup" % device,"sha256":_seed_hash("backup-agent.exe")})
		if device == "pc_a": state.edr_persistence.append({"device":device,"file_id":"%s-sync" % device,"sha256":MALICIOUS_SHA256})
		_seed_events(state, device)

static func _seed_hash(name: String) -> String:
	return ("TRAINING FIXTURE: %s %s" % [name, "Signed Business Suite" if name == "office.exe" else "approved CHG-EDR-2026"]).sha256_text()

static func _add_file(state: Dictionary, fs: Dictionary, device: String, id: String, name: String, path: String, publisher: String, change_ref: String, trusted: bool = false) -> void:
	var bytes := MALICIOUS_BYTES if name == "sync-agent.exe" else ("TRAINING FIXTURE: %s %s" % [name, "Signed Business Suite" if name == "office.exe" else "approved CHG-EDR-2026"])
	fs[path] = bytes
	var display_path := "C:/Program Files/Business Suite/office.exe" if name == "office.exe" else ("C:/Program Files/Approved Backup/backup-agent.exe" if name == "backup-agent.exe" else "C:/Users/staff/AppData/Local/sync-agent.exe")
	state.edr_files.append({"id":id,"device":device,"name":name,"path":display_path,"guest_path":path,"publisher":publisher,"change_ref":change_ref,"trusted":trusted,"sha256":bytes.sha256_text()})

static func _seed_events(state: Dictionary, device: String) -> void:
	for item in state.get("edr_devices", []):
		if not item is Dictionary or str(item.get("id", "")) != device: continue
		item.events = []
		if device == "pc_a":
			item.events.append({"time":"09:41","type":"outbound","process":"sync-agent.exe","publisher":"Unsigned","remote_address":"203.0.113.77","detail":"unusual outbound connection","change_ref":"","file_id":"%s-sync" % device,"file_name":"sync-agent.exe"})
			item.events.append({"time":"09:42","type":"file_read","process":"sync-agent.exe","publisher":"Unsigned","remote_address":"","detail":"endpoint file access","change_ref":"","file_id":"%s-sync" % device,"file_name":"sync-agent.exe"})
			item.events.append({"time":"09:43","type":"dns","process":"sync-agent.exe","publisher":"Unsigned","remote_address":"203.0.113.77","detail":"unlisted endpoint lookup","change_ref":"","file_id":"%s-sync" % device,"file_name":"sync-agent.exe"})
			item.events.append({"time":"09:45","type":"file_read","process":"backup-agent.exe","publisher":"unsigned","remote_address":"","detail":"endpoint file access","change_ref":"CHG-EDR-BACKUP-2026","file_id":"%s-backup" % device,"file_name":"backup-agent.exe"})
			item.events.append({"time":"09:46","type":"dns","process":"backup-agent.exe","publisher":"unsigned","remote_address":"192.0.2.20","detail":"approved backup lookup","change_ref":"CHG-EDR-BACKUP-2026","file_id":"%s-backup" % device,"file_name":"backup-agent.exe"})
		else:
			item.events.append({"time":"09:44","type":"outbound","process":"office.exe","publisher":"Signed Business Suite","remote_address":"192.0.2.20","detail":"approved business session","change_ref":"CHG-EDR-OFFICE-2026","file_id":"%s-office" % device,"file_name":"office.exe"})
			item.events.append({"time":"09:42","type":"file_read","process":"backup-agent.exe","publisher":"unsigned","remote_address":"","detail":"endpoint file access","change_ref":"CHG-EDR-BACKUP-2026","file_id":"%s-backup" % device,"file_name":"backup-agent.exe"})
			item.events.append({"time":"09:43","type":"dns","process":"backup-agent.exe","publisher":"unsigned","remote_address":"192.0.2.20","detail":"approved backup lookup","change_ref":"CHG-EDR-BACKUP-2026","file_id":"%s-backup" % device,"file_name":"backup-agent.exe"})

static func _file(state: Dictionary, device: String, file_id: String = "") -> Dictionary:
	for item in state.get("edr_files", []):
		if not item is Dictionary or (not file_id.is_empty() and str(item.get("id", "")) != file_id) or (not device.is_empty() and str(item.get("device", "")) != device): continue
		return item
	return {}

static func _quarantine_for(state: Dictionary, file_id: String) -> Dictionary:
	for index in range(state.get("edr_quarantine", []).size() - 1, -1, -1):
		var item = state.edr_quarantine[index]
		if item is Dictionary and str(item.get("file_id", "")) == file_id and not bool(item.get("restored", false)): return item
	return {}

static func _is_malicious_hash(value: String) -> bool:
	return value == MALICIOUS_SHA256 and MALICIOUS_BYTES.sha256_text() == MALICIOUS_SHA256

static func _current_hash(state: Dictionary, item: Dictionary) -> String:
	var fs: Dictionary = state.get("fs", {}) if state.get("fs", {}) is Dictionary else {}
	return str(fs.get(str(item.get("guest_path", item.get("path", ""))), "")).sha256_text() if fs.has(str(item.get("guest_path", item.get("path", "")))) else ""

static func _process_running(state: Dictionary, file_id: String) -> bool:
	for item in state.get("edr_processes", []):
		if item is Dictionary and str(item.get("file_id", "")) == file_id and bool(item.get("running", false)): return true
	return false

static func files(state: Dictionary, device: String = "") -> Array:
	var result: Array = []
	for item in state.get("edr_files", []):
		if not item is Dictionary or (not device.is_empty() and str(item.get("device", "")) != device): continue
		var copy: Dictionary = item.duplicate(true); var current := _current_hash(state, item); var quarantine := _quarantine_for(state, str(item.id))
		copy.current_sha256 = current; copy.present = not current.is_empty(); copy.quarantined = current.is_empty() and not quarantine.is_empty(); copy.running = _process_running(state, str(item.id))
		result.append(copy)
	return result

static func _state_fingerprint(state: Dictionary, device: String = "") -> String:
	var payload := {"files":[],"processes":[],"persistence":[],"actual":[]}; var fs: Dictionary = state.get("fs", {}) if state.get("fs", {}) is Dictionary else {}
	var actual_paths: Array = []
	for raw_path in fs.keys():
		var path := str(raw_path)
		if path.begins_with("/endpoints/") and (device.is_empty() or path.begins_with("/endpoints/%s/" % device)): actual_paths.append(path)
	actual_paths.sort()
	for path in actual_paths: payload.actual.append({"path":path,"bytes":str(fs[path])})
	for item in state.get("edr_processes", []):
		if item is Dictionary and (device.is_empty() or str(item.get("device", "")) == device): payload.processes.append(item.duplicate(true))
	for item in state.get("edr_persistence", []):
		if item is Dictionary and (device.is_empty() or str(item.get("device", "")) == device): payload.persistence.append(item.duplicate(true))
	return JSON.stringify(payload,"",true).sha256_text()

static func fingerprint(state: Dictionary, device: String = "") -> String:
	return _state_fingerprint(state, device)

static func scan(state: Dictionary, device: String) -> Dictionary:
	var result := _scan_result(state, device)
	state.edr_scans[device] = result.duplicate(true)
	return result

static func _scan_result(state: Dictionary, device: String) -> Dictionary:
	var findings: Array = []; var count := 0; var known_guest: Dictionary = {}
	for item in files(state, device):
		var sha := str(item.get("current_sha256", "")); var file_id := str(item.get("id", ""))
		known_guest[str(_file(state, device, file_id).get("guest_path", ""))] = true
		if _is_malicious_hash(sha): findings.append({"type":"file","kind":"file","device":device,"path":str(item.get("path", "")),"file_id":file_id,"sha256":sha}); count += 1
	for process in state.get("edr_processes", []):
		if process is Dictionary and str(process.get("device", "")) == device and bool(process.get("running", false)) and _is_malicious_hash(str(process.get("sha256", ""))): findings.append({"type":"process","kind":"process","device":device,"path":str(_file(state,device,str(process.get("file_id", ""))).get("path", "")),"file_id":str(process.get("file_id", "")),"sha256":str(process.get("sha256", ""))}); count += 1
	var fs: Dictionary = state.get("fs", {}) if state.get("fs", {}) is Dictionary else {}
	for raw_path in fs.keys():
		var path := str(raw_path); if not path.begins_with("/endpoints/%s/" % device): continue
		if _is_malicious_hash(str(fs[raw_path]).sha256_text()) and not known_guest.has(path): findings.append({"type":"file","kind":"moved_file","device":device,"path":path,"file_id":"","sha256":str(fs[raw_path]).sha256_text()}); count += 1
	for item in state.get("edr_persistence", []):
		if item is Dictionary and str(item.get("device", "")) == device and _is_malicious_hash(str(item.get("sha256", ""))): findings.append({"type":"persistence","kind":"persistence","device":device,"path":str(_file(state,device,str(item.get("file_id", ""))).get("path", "")),"file_id":str(item.get("file_id", "")),"sha256":str(item.get("sha256", ""))}); count += 1
	return {"ok":true,"code":200,"device":device,"fingerprint":_state_fingerprint(state,device),"findings":findings,"threat_count":count,"clean":count == 0}

static func status(state: Dictionary, device: String) -> Dictionary:
	var office := _file(state, device, "%s-office" % device); var backup := _file(state, device, "%s-backup" % device); var office_sha := _current_hash(state, office); var backup_sha := _current_hash(state, backup); var saved_scan: Dictionary = state.get("edr_scans", {}).get(device, {})
	var threat := _scan_result(state, device); var office_ok := not office.is_empty() and office_sha == str(office.sha256); var backup_ok := not backup.is_empty() and backup_sha == str(backup.sha256); var current_fp := _state_fingerprint(state,device)
	return {"device":device,"business_available":office_ok and backup_ok,"threat_count":int(threat.get("threat_count",0)),"scan_current":str(saved_scan.get("fingerprint", "")) == current_fp and not saved_scan.is_empty(),"scan_clean":bool(saved_scan.get("clean", false)) if str(saved_scan.get("fingerprint", "")) == current_fp else false}

static func quarantine(state: Dictionary, device: String, file_id: String) -> Dictionary:
	var item := _file(state, device, file_id); if item.is_empty(): return {"ok":false,"code":404,"error":"unknown_file"}
	if bool(item.get("trusted", false)): return {"ok":false,"code":403,"error":"trusted_file"}
	var current := _current_hash(state,item); var fs: Dictionary = state.get("fs", {})
	var existing := _quarantine_for(state,file_id)
	if not existing.is_empty() and current.is_empty(): return {"ok":true,"code":200,"changed":false,"device":device,"file_id":file_id,"sha256":str(existing.get("sha256", "")),"quarantine_id":int(existing.get("id", -1))}
	if current.is_empty(): return {"ok":false,"code":404,"error":"file_missing"}
	var record := {"id":state.get("edr_quarantine",[]).size()+1,"device":device,"file_id":file_id,"path":str(item.path),"guest_path":str(item.guest_path),"sha256":current,"bytes":str(fs.get(str(item.guest_path),"")),"restored":false}
	fs.erase(str(item.guest_path)); state.edr_quarantine.append(record)
	for process in state.edr_processes:
		if process is Dictionary and str(process.get("device","")) == device and (str(process.get("file_id", "")) == file_id or str(process.get("sha256", "")) == current): process.running = false
	var kept: Array = []
	for persistence in state.edr_persistence:
		if not (persistence is Dictionary and str(persistence.get("device","")) == device and (str(persistence.get("file_id", "")) == file_id or str(persistence.get("sha256", "")) == current)): kept.append(persistence)
	state.edr_persistence = kept
	return {"ok":true,"code":200,"changed":true,"device":device,"file_id":file_id,"sha256":current,"quarantine":record.duplicate(true),"quarantine_id":int(record.id)}

static func restore(state: Dictionary, sequence: int) -> Dictionary:
	for record in state.get("edr_quarantine", []):
		if not record is Dictionary or int(record.get("id", -1)) != sequence: continue
		if bool(record.get("restored", false)): return {"ok":true,"code":200,"changed":false,"device":str(record.get("device", "")),"file_id":str(record.get("file_id", "")),"sha256":str(record.get("sha256", "")),"quarantine":record.duplicate(true),"quarantine_id":sequence}
		var bytes := str(record.get("bytes", "")); if bytes.is_empty() or bytes.sha256_text() != str(record.get("sha256", "")): return {"ok":false,"code":409,"error":"quarantine_corrupt"}
		var path := str(record.get("guest_path", record.get("path", ""))); var fs: Dictionary = state.get("fs", {})
		if fs.has(path) and str(fs[path]) != bytes: return {"ok":false,"code":409,"error":"destination_conflict"}
		fs[path] = bytes; record.restored = true; return {"ok":true,"code":200,"changed":true,"device":str(record.get("device", "")),"file_id":str(record.get("file_id", "")),"sha256":str(record.get("sha256", "")),"quarantine":record.duplicate(true),"quarantine_id":sequence}
	return {"ok":false,"code":404,"changed":false,"error":"quarantine_not_found"}

static func snapshot(state: Dictionary) -> Dictionary:
	var scan_copy: Dictionary = {}
	for device in state.get("edr_scans", {}).keys():
		var item: Dictionary = state.edr_scans[device].duplicate(true); item.current = str(item.get("fingerprint", "")) == _state_fingerprint(state,str(device)); scan_copy[str(device)] = item
	var copy := {"files":files(state),"processes":state.get("edr_processes",[]).duplicate(true),"persistence":state.get("edr_persistence",[]).duplicate(true),"quarantine":[],"scans":scan_copy}
	for item in state.get("edr_quarantine", []):
		if item is Dictionary:
			var record: Dictionary = item.duplicate(true); record.erase("bytes"); copy.quarantine.append(record)
	return copy
