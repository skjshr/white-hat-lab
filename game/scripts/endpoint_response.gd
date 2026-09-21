extends RefCounted

static func json_result(ok: bool, code: int, extra: Dictionary = {}) -> String:
	var result: Dictionary = {"ok":ok,"code":code}
	result.merge(extra, true)
	return JSON.stringify(result)

static func initial_devices(suspect: String, advanced: bool = false) -> Array:
	var devices: Array = []
	for device_id in ["pc_a", "pc_b"]:
		var suspicious: bool = suspect == device_id or suspect == "both"
		var events: Array = []
		if suspicious:
			var process := "powershell.exe" if advanced else "unknown"
			var publisher := "Microsoft Windows" if advanced else "unsigned"
			events = [{"time":"09:41","type":"outbound","process":process,"publisher":publisher,"remote_address":"203.0.113.77","detail":"external outbound","change_ref":""},{"time":"09:42","type":"file_read","process":process if advanced else "unsigned-file-reader","publisher":publisher,"remote_address":"203.0.113.77","detail":"many-file-reads","change_ref":""},{"time":"09:43","type":"dns","process":process,"publisher":publisher,"remote_address":"203.0.113.77","detail":"unlisted destination","change_ref":""}]
		else:
			events = [{"time":"09:44","type":"outbound","process":"office","publisher":"Signed Business Suite","remote_address":"192.0.2.20","detail":"approved business session","change_ref":"CHG-2026-0918"},{"time":"09:45","type":"file_read","process":"unsigned-backup-script" if advanced else "backup-agent","publisher":"unsigned" if advanced else "Signed Backup Agent","remote_address":"192.0.2.20","detail":"approved change window" if advanced else "scheduled backup","change_ref":"CHG-2026-0918"}]
		devices.append({"id":device_id,"name":device_id.to_upper(),"isolated":false,"business_status":"healthy","management_connected":true,"events":events})
	return devices

static func public_snapshot(state: Dictionary, evidence: Dictionary = {}) -> Dictionary:
	var current_evidence: Dictionary = evidence if not evidence.is_empty() else state.get("edr_evidence",{}).duplicate(true)
	return {"ok":true,"devices":state.get("edr_devices",[]).duplicate(true),"actions":state.get("edr_actions",[]).duplicate(true),"evidence":current_evidence}
