extends RefCounted

const PRIMARY_PATH := "/srv/share/partner-order.csv"
const ROLES := ["staff", "partner", "public"]
const EXPIRIES := ["unlimited", "7d", "30d"]

static func enabled(vm: Object) -> bool:
	return int(vm.state.get("portal_model_version", 1)) >= 2

static func _permission_number(value: String) -> int:
	match value:
		"read": return 1
		"write": return 3
	return 0

static func _permission_name(value: int) -> String:
	match value:
		3: return "write"
		1: return "read"
	return "none"

static func _default_expiry(role: String, config: Dictionary) -> String:
	if role in ["partner", "public"]: return str(config.get("expires", "unlimited"))
	return "unlimited"

static func _share(role: String, permissions: int, expires: String) -> Dictionary:
	return {"id":role, "role":role, "path":PRIMARY_PATH, "permissions":permissions, "expires":expires}

static func _shares(vm: Object) -> Array:
	var shares: Array = vm.state.get("portal_shares", [])
	if not vm.state.has("portal_shares") or not shares is Array:
		shares = []
		vm.state.portal_shares = shares
	return shares

static func ensure(vm: Object) -> void:
	if not enabled(vm): return
	# Existing saves start recording here; do not invent earlier file contents.
	if not vm.state.get("portal_versions", null) is Array: vm.state.portal_versions = []
	if not vm.state.get("portal_activity", null) is Array: vm.state.portal_activity = []
	if not vm.state.has("portal_sequence"): vm.state.portal_sequence = 0
	var config: Dictionary = vm.state.get("applied", {}) if vm.state.get("applied", {}) is Dictionary else {}
	var existing: Dictionary = {}
	for item in _shares(vm):
		if item is Dictionary and str(item.get("role", "")) in ROLES:
			existing[str(item.get("role", ""))] = item
	var canonical: Array = []
	for role in ROLES:
		var item: Dictionary = existing.get(role, {})
		var permissions := int(item.get("permissions", _permission_number(str(config.get(role, "none")))))
		if permissions not in [0, 1, 3]: permissions = _permission_number(str(config.get(role, "none")))
		var expires := str(item.get("expires", _default_expiry(role, config)))
		if expires not in EXPIRIES: expires = _default_expiry(role, config)
		canonical.append(_share(role, permissions, expires))
	vm.state.portal_shares = canonical

static func sync_from_config(vm: Object, previous_config: Dictionary = {}) -> void:
	if not enabled(vm): return
	ensure(vm)
	var config: Dictionary = vm.state.get("applied", {})
	var expiry_changed := previous_config.is_empty() or str(previous_config.get("expires", "")) != str(config.get("expires", ""))
	for item in vm.state.portal_shares:
		var role := str(item.get("role", ""))
		if role not in ROLES: continue
		item.permissions = _permission_number(str(config.get(role, "none")))
		if expiry_changed and role in ["partner", "public"]: item.expires = str(config.get("expires", "unlimited"))

static func share_for(vm: Object, role: String) -> Dictionary:
	if not enabled(vm): return {}
	for item in _shares(vm):
		if item is Dictionary and str(item.get("role", "")) == role: return item
	return {}

static func canonical_shares(vm: Object) -> Array:
	if not enabled(vm): return []
	ensure(vm)
	var result: Array = []
	for item in vm.state.portal_shares:
		result.append({"id":str(item.get("id", "")),"role":str(item.get("role", "")),"path":str(item.get("path", "")),"permissions":int(item.get("permissions", 0)),"expires":str(item.get("expires", "unlimited"))})
	return result

static func _next_sequence(vm: Object) -> int:
	ensure(vm)
	var sequence := int(vm.state.get("portal_sequence",0))
	for records in [vm.state.portal_versions,vm.state.portal_activity]:
		for item in records:
			if item is Dictionary: sequence=maxi(sequence,int(item.get("sequence",0)))
	vm.state.portal_sequence=sequence+1
	return sequence+1

static func _version_metadata(version: Dictionary) -> Dictionary:
	var result:=version.duplicate(true)
	result.erase("content")
	return result

static func versions(vm: Object) -> Array:
	var result: Array=[]
	for item in vm.state.get("portal_versions",[]):
		if item is Dictionary and str(item.get("path",""))==PRIMARY_PATH: result.append(_version_metadata(item))
	result.reverse()
	return result

static func activity(vm: Object) -> Array:
	var result: Array=vm.state.get("portal_activity",[]).duplicate(true)
	result.reverse()
	return result

static func _version(vm: Object, id: String) -> Dictionary:
	for item in vm.state.get("portal_versions",[]):
		if item is Dictionary and str(item.get("id",""))==id and str(item.get("path",""))==PRIMARY_PATH:return item
	return {}

static func record_change(vm: Object, before: String, after: String, actor: String, reason: String, source_version: String = "") -> void:
	if not enabled(vm) or before==after:return
	var sequence:=_next_sequence(vm)
	var id:="v%06d" % sequence
	vm.state.portal_versions.append({"id":id,"path":PRIMARY_PATH,"content":before,"sha256":before.sha256_text(),"size":before.to_utf8_buffer().size(),"sequence":sequence,"actor":actor,"reason":reason,"source_version":source_version})
	vm.state.portal_activity.append({"id":"a%06d" % sequence,"path":PRIMARY_PATH,"sequence":sequence,"actor":actor,"action":reason,"version_id":id,"source_version":source_version,"sha256":after.sha256_text()})

static func _record_share(vm: Object, role: String, permissions: int, expires: String) -> void:
	var sequence:=_next_sequence(vm)
	vm.state.portal_activity.append({"id":"a%06d" % sequence,"path":PRIMARY_PATH,"sequence":sequence,"actor":"operator","action":"share","version_id":"","sha256":"","role":role,"permissions":permissions,"expires":expires})

static func _version_command(vm: Object, args: Array, fs: Dictionary) -> String:
	if args.size()==2 and str(args[1])=="versions":return _json(true,200,{"versions":versions(vm)})
	if args.size()==2 and str(args[1])=="activity":return _json(true,200,{"activity":activity(vm)})
	if args.size()!=3 or str(args[1]) not in ["version","restore"]:return _json(false,400,{"error":"usage"})
	var version:=_version(vm,str(args[2]))
	if version.is_empty():return _json(false,404,{"error":"version_missing"})
	if not version.get("content") is String or str(version.content).sha256_text()!=str(version.get("sha256","")) or str(version.content).to_utf8_buffer().size()!=int(version.get("size",-1)):
		return _json(false,409,{"error":"version_corrupt"})
	if str(args[1])=="version":return _json(true,200,{"version":version.duplicate(true)})
	if vm.has_method("has_linked_branch_storage") and vm.has_linked_branch_storage() and not vm.linked_business_provider_writable():return _json(false,403,{"error":"storage_denied"})
	var current:=str(fs[PRIMARY_PATH]);var restored:=str(version.content)
	if current==restored:return _json(true,200,{"changed":false,"restored_version":str(version.id)})
	record_change(vm,current,restored,"operator","restore",str(version.id))
	fs[PRIMARY_PATH]=restored
	vm._touch("portal restore version="+str(version.id))
	if str(vm.state.applied.get("audit","off"))=="on":vm._audit("portal restore version=%s file=%s result=changed" % [str(version.id),PRIMARY_PATH.get_file()])
	return _json(true,200,{"changed":true,"restored_version":str(version.id)})

static func _files(vm: Object) -> Array:
	var result: Array = []
	var fs: Dictionary = vm._portal_storage_fs() if vm.has_method("_portal_storage_fs") else vm.state.fs
	if vm.has_method("has_linked_branch_storage") and vm.has_linked_branch_storage() and vm.has_method("linked_business_provider_available") and not vm.linked_business_provider_available(): return result
	if fs.has(PRIMARY_PATH):
		var content := str(fs[PRIMARY_PATH])
		result.append({"path":PRIMARY_PATH,"name":PRIMARY_PATH.get_file(),"size":content.to_utf8_buffer().size(),"sha256":content.sha256_text()})
	return result

static func snapshot(vm: Object) -> Dictionary:
	var config: Dictionary = vm.state.get("applied", {}) if vm.state.get("applied", {}) is Dictionary else {}
	var available := true
	var provider_error := ""
	var provider_writable := true
	if vm.has_method("has_linked_branch_storage") and vm.has_linked_branch_storage():
		available = vm.linked_business_provider_available() if vm.has_method("linked_business_provider_available") else false
		provider_error = vm.linked_business_provider_error() if vm.has_method("linked_business_provider_error") else "provider_unavailable"
		provider_writable = vm.linked_business_provider_writable() if vm.has_method("linked_business_provider_writable") else false
	var mounted_fs: Dictionary = vm._portal_storage_fs() if vm.has_method("_portal_storage_fs") else vm.state.fs
	var missing := available and not mounted_fs.has(PRIMARY_PATH)
	if missing: provider_error = "missing_file"
	return {"model_version":int(vm.state.get("portal_model_version", 1)),"files":_files(vm),"shares":canonical_shares(vm),"versions":versions(vm),"activity":activity(vm),"config":config.duplicate(true),"active":bool(vm.state.get("active", false)),"connected":bool(vm.state.get("connected", false)),"external_storage":{"enabled":vm.has_method("has_linked_branch_storage") and vm.has_linked_branch_storage(),"ok":available and not missing,"code":404 if missing else (200 if available else (403 if provider_error == "storage_denied" else 503)),"error":provider_error,"host":"files01.client.test","share":"share","path":PRIMARY_PATH,"writable":available and not missing and provider_writable}}

static func _json(ok: bool, code: int, payload: Dictionary = {}) -> String:
	var result: Dictionary = {"ok":ok,"code":code}
	result.merge(payload, true)
	return JSON.stringify(result)

static func command(vm: Object, args: Array) -> String:
	if not enabled(vm): return _json(false, 426, {"error":"legacy_model"})
	if not bool(vm.state.get("active", false)): return _json(false, 503, {"error":"service_unavailable"})
	if not bool(vm.state.get("connected", false)): return _json(false, 401, {"error":"not_connected"})
	if vm.has_method("has_linked_branch_storage") and vm.has_linked_branch_storage() and vm.has_method("linked_business_provider_available") and not vm.linked_business_provider_available():
		var provider_error: String = vm.linked_business_provider_error() if vm.has_method("linked_business_provider_error") else "provider_unavailable"
		return _json(false, 403 if provider_error == "storage_denied" else 503, {"error":provider_error})
	var fs: Dictionary = vm._portal_storage_fs() if vm.has_method("_portal_storage_fs") else vm.state.fs
	if not fs.has(PRIMARY_PATH): return _json(false, 404, {"error":"file_not_found"})
	ensure(vm)
	if args.size() == 2 and str(args[1]) == "files": return _json(true, 200, {"files":_files(vm)})
	if args.size() == 2 and str(args[1]) == "shares": return _json(true, 200, {"shares":canonical_shares(vm)})
	if args.size()>=2 and str(args[1]) in ["versions","activity","version","restore"]:return _version_command(vm,args,fs)
	if args.size() != 5 or str(args[1]) != "share": return _json(false, 400, {"error":"usage"})
	var role := str(args[2]); var permission := str(args[3]); var expires := str(args[4])
	if role not in ROLES: return _json(false, 400, {"error":"invalid_role"})
	if permission not in ["none", "read", "write"]: return _json(false, 400, {"error":"invalid_permission"})
	if expires not in EXPIRIES: return _json(false, 400, {"error":"invalid_expiry"})
	if role == "public" and permission == "write": return _json(false, 400, {"error":"public_write_forbidden"})
	var share := share_for(vm, role)
	if share.is_empty(): return _json(false, 404, {"error":"share_not_found"})
	var parsed_pending: Dictionary = vm._parse_config(str(vm.state.fs.get(vm.state.config_path, "")))
	if not str(parsed_pending.get("error", "")).is_empty(): return _json(false, 409, {"error":"configuration_pending"})
	var pending: Dictionary = parsed_pending.get("values", {}).duplicate(true)
	var config: Dictionary = vm.state.get("applied", {}).duplicate(true)
	var config_changed := str(config.get(role, "none")) != permission
	var pending_changed := str(pending.get(role, "none")) != permission
	var expiry_changed := str(share.get("expires", "unlimited")) != expires
	var pending_expiry_changed := role == "partner" and str(pending.get("expires", "unlimited")) != expires
	var share_changed := int(share.get("permissions", 0)) != _permission_number(permission) or expiry_changed
	if not config_changed and not pending_changed and not pending_expiry_changed and not share_changed: return _json(true, 200, {"changed":false,"share":share.duplicate(true)})
	config[role] = permission
	if role == "partner": config.expires = expires
	pending[role] = permission
	if role == "partner": pending.expires = expires
	share.permissions = _permission_number(permission)
	share.expires = expires
	vm.state.applied = config
	vm.state.fs[vm.state.config_path] = vm.configuration_text(pending)
	vm.state.dirty = pending != config
	vm._touch("portal share role=%s permission=%s expires=%s" % [role, permission, expires])
	_record_share(vm,role,int(share.permissions),expires)
	if str(config.get("audit", "off")) == "on": vm._audit("portal share role=%s permission=%s expires=%s result=changed" % [role, permission, expires])
	return _json(true, 200, {"changed":true,"share":share.duplicate(true)})
