extends RefCounted
const Samba = preload("res://scripts/samba_config.gd")
const DISPLAY_COPY = preload("res://scripts/ui_theme.gd")
const EndpointResponse = preload("res://scripts/endpoint_response.gd")
const EndpointRemediation = preload("res://scripts/endpoint_remediation.gd")
const PortalStorage = preload("res://scripts/portal_storage.gd")
const FirewallPolicy = preload("res://scripts/firewall_policy.gd")
const BusinessWorkspace = preload("res://scripts/business_workspace.gd")
const HotelFrontdesk = preload("res://scripts/hotel_frontdesk_model.gd")
const BackupAuthorization = preload("res://scripts/backup_authorization.gd")
## Deterministic guest operating system. Files and service state are local game data.
const PATHS := ["/etc/samba/smb.conf","/etc/restic/backup.conf","/etc/firewall/rules.conf","/etc/identity/users.conf","/etc/edr/policy.conf","/etc/share/portal.conf"]
const SERVICES := ["samba","restic","firewall","identity","edr","portal"]
const HOSTS := ["files01.client.test","backup01.client.test","gateway01.client.test","identity01.client.test","edr01.client.test","portal01.client.test"]
const SCHEMAS := [
	{"staff":["none","read","write"],"guest":["none","read","write"]},
	{"schedule":["off","daily"],"repository":["local","offsite"]},
	{"dns":["off","on"],"business":["deny","allow"],"admin_public":["deny","allow"],"tls":["off","on"]},
	{"former":["active","disabled"],"sessions":["valid","revoked"],"current":["disabled","active"],"mfa":["off","on"]},
	{"pc_a":["connected","isolated"],"pc_b":["connected","isolated"],"logs":["keep","erase"],"reset":["wait","wipe"]},
	{"staff":["none","read","write"],"partner":["none","read","write"],"public":["none","read","write"],"expires":["unlimited","7d","30d"],"mfa":["off","on"],"tls":["off","on"],"audit":["off","on"]}
]
const SEEDS := [
	"staff=read\nguest=write\n",
	"schedule=off\nrepository=local\n",
	"dns=off\nbusiness=allow\nadmin_public=allow\ntls=off\n",
	"former=active\nsessions=valid\ncurrent=active\nmfa=off\n",
	"pc_a=connected\npc_b=connected\nlogs=keep\nreset=wait\n",
	"staff=read\npartner=write\npublic=read\nexpires=unlimited\nmfa=off\ntls=off\naudit=off\n"
]
const RECORDS := {"customers.csv":"id,name\n101,Aoba\n102,Minato\n","orders.csv":"order,customer,total\n501,101,12800\n","ledger.txt":"2026-09-18 opening=50000 closing=62800\n"}
const EVIDENCE := "09:41 PC-A user=staff process=unknown outbound=203.0.113.77\n09:42 PC-A event=unusual-file-access count=42\n09:43 PC-A dns=unlisted.client.test\n09:44 PC-B process=office outbound=192.0.2.20\n09:45 PC-B event=normal-work\n09:46 PC-A session=suspect-17\n"
const OPERATOR_HOME := "/home/operator"
const LEGACY_HOMES := ["/home/aoba", "/home/wakaba"]
const ACCESS_MODEL_VERSION := 2
const IDENTITY_MODEL_VERSION := 2
const IDENTITY_PASSWORD := "Training-117!"
const IDENTITY_OTP := "123456"
const EDR_MODEL_VERSION := 2
const FIREWALL_MODEL_VERSION := 2
var state: Dictionary = {}
var _chapter := 0
var _dirty := false
var _identity: Dictionary = {"company":"あおばセキュリティ相談所","player":"青葉","aya":"綾","ren":"蓮"}
var _linked_identity_provider: Dictionary = {}
var _linked_business_provider: Dictionary = {}

func set_identity(values: Dictionary) -> void:
	# Display identity is separate from guest paths, evidence and snapshots.
	for key in _identity:
		if values.has(key): _identity[key] = str(values[key])

func set_linked_identity_provider(snapshot: Dictionary) -> void:
	# The provider is deliberately ephemeral: the portal never becomes an
	# authority for identity state and the snapshot is not exported with VM data.
	_linked_identity_provider = snapshot.duplicate(true) if snapshot is Dictionary else {}
	if not has_linked_identity(): return
	var current_token := "current-seed-1"
	var current_issued := -1
	for session in linked_identity_sessions():
		if session is Dictionary and str(session.get("user", "")) == "current" and not bool(session.get("revoked", false)):
			var issued := int(session.get("issued", -1))
			if issued >= current_issued:
				current_issued = issued
				current_token = str(session.get("id", current_token))
	for probe in _active_probes():
		if str(probe.get("linked_subject", "")) != "current": continue
		var old_command := str(probe.get("command", ""))
		var new_command := old_command
		var bearer_at := old_command.find("Bearer ")
		if bearer_at >= 0:
			var token_start := bearer_at + 7
			var token_end := token_start
			while token_end < old_command.length() and old_command[token_end] not in [" ", "\t", "\r", "\n", "'", '"']:
				token_end += 1
			new_command = old_command.substr(0, token_start) + current_token + old_command.substr(token_end)
		if old_command != new_command:
			_clear_probe_measurement(probe)
			probe.command = new_command

func set_linked_business_provider(snapshot: Dictionary) -> void:
	# The backup VM publishes an ephemeral view of the customer's production
	# files.  The chapter-2 gateway reads that view but never owns or mutates it.
	_linked_business_provider = snapshot.duplicate(true) if snapshot is Dictionary else {}

func has_linked_branch_storage() -> bool:
	var scenario: Dictionary = state.get("scenario", {}) if state.get("scenario", {}) is Dictionary else {}
	return bool(scenario.get("linked_branch_storage", false))

func linked_business_provider_fs() -> Dictionary:
	var fs: Variant = _linked_business_provider.get("fs", {})
	return fs.duplicate(true) if fs is Dictionary else {}

func linked_business_provider_fs_ref() -> Dictionary:
	var fs: Variant = _linked_business_provider.get("fs", {})
	return fs if fs is Dictionary else {}

func restore_linked_business_provider_fs(fs: Dictionary) -> void:
	if not _linked_business_provider.is_empty(): _linked_business_provider.fs = fs.duplicate(true)

func linked_business_provider_available() -> bool:
	return bool(_linked_business_provider.get("available", false))

func linked_business_provider_writable() -> bool:
	return bool(_linked_business_provider.get("writable", false))

func linked_business_provider_error() -> String:
	return str(_linked_business_provider.get("error", "provider_unavailable"))

func _portal_storage_fs() -> Dictionary:
	if has_linked_branch_storage(): return linked_business_provider_fs_ref()
	return state.fs

func has_linked_business() -> bool:
	var scenario: Dictionary = state.get("scenario", {}) if state.get("scenario", {}) is Dictionary else {}
	return _firewall_model_v2() and bool(scenario.get("linked_business", false))

func linked_business_fingerprint() -> String:
	return BusinessWorkspace.fingerprint(_linked_business_provider, has_linked_branch_storage())

func _business_provider() -> Dictionary:
	var scenario: Dictionary = state.get("scenario", {}) if state.get("scenario", {}) is Dictionary else {}
	if bool(scenario.get("linked_business", false)):
		return _linked_business_provider
	return {"available":true,"writable":true,"fs":state.fs.duplicate(true)}

## A UI refresh must not record traffic, consume work time, or grant a probe PASS.
func business_read(resource: String = "orders", request_url: String = "") -> Dictionary:
	var result: Dictionary
	var url := _url_parts(request_url if not request_url.is_empty() else "https://intranet.client.test/")
	var port := 443 if str(url.scheme) == "https" else 80
	if str(url.host) != "intranet.client.test" or int(url.port) != port or str(url.scheme) not in ["http","https"]: result = {"ok":false,"code":404,"error":"unknown_service"}
	elif _chapter != 2 or not _firewall_model_v2(): result = {"ok":false,"code":400,"error":"unsupported_model"}
	elif not bool(state.get("connected",false)) or not bool(state.get("active",false)): result = {"ok":false,"code":0,"error":"service_unavailable","transport_error":true,"transport_kind":"network","raw":"curl: (7) Connection failed"}
	elif str(state.applied.get("dns","off")) != "on": result = {"ok":false,"code":0,"error":"dns_unavailable","transport_error":true,"transport_kind":"dns","raw":"curl: (6) Could not resolve host"}
	else:
		var dns := FirewallPolicy.evaluate(state.applied,"lan",FirewallPolicy.STAFF_ADDRESS,FirewallPolicy.LAN_ADDRESS,"udp",40000,53)
		var http := FirewallPolicy.evaluate(state.applied,"lan",FirewallPolicy.STAFF_ADDRESS,FirewallPolicy.BUSINESS_ADDRESS,"tcp",40000,port)
		if str(dns.get("action","block")) != "pass": result = {"ok":false,"code":0,"error":"network_denied","transport_error":true,"transport_kind":"dns","raw":"curl: (6) Could not resolve host " + _firewall_denial(dns,"curl")}
		elif str(http.get("action","block")) != "pass": result = {"ok":false,"code":0,"error":"network_denied","transport_error":true,"transport_kind":"denied","raw":_firewall_denial(http,"curl")}
		elif str(url.scheme) == "https" and str(state.applied.get("tls","off")) != "on": result = {"ok":false,"code":0,"error":"tls_unavailable","transport_error":true,"transport_kind":"tls","raw":"curl: (35) TLS handshake failed"}
		else: result = BusinessWorkspace.handle_get(_business_provider(),resource)
	var provider := _business_provider()
	result.revision = BusinessWorkspace.fingerprint(provider,true)
	result.capabilities = {"write":bool(result.get("ok",false)) and bool(provider.get("writable",true))}
	return result

func has_linked_identity() -> bool:
	var scenario: Dictionary = state.get("scenario", {}) if state.get("scenario", {}) is Dictionary else {}
	return _portal_model_v2() and bool(scenario.get("linked_identity", false))

func linked_identity_sessions() -> Array:
	return _linked_identity_provider.get("sessions", []).duplicate(true) if _linked_identity_provider.get("sessions", []) is Array else []

func setup(chapter: int, saved: Dictionary = {}, scenario: Dictionary = {}) -> void:
	_linked_identity_provider = {}
	_linked_business_provider = {}
	_chapter = clampi(chapter, 0, 5)
	if not saved.is_empty() and saved.get("schema", 0) == 2 and saved.get("fs") is Dictionary and saved.get("applied") is Dictionary and saved.get("dirs") is Array and saved.get("snapshots") is Array and saved.get("events") is Array:
		state = saved.duplicate(true)
		_migrate_operator_home()
		if not state.has("scenario"): state.scenario = {}
		if not state.has("observations"): state.observations = []
		if not state.has("last_restore"): state.last_restore = {}
		if state.scenario is Dictionary and not state.scenario.is_empty() and not state.scenario.has("probes"): state.scenario.probes = []
		if not state.has("probes"): state.probes = _legacy_probes()
		if not state.has("evidence_original"): state.evidence_original = EVIDENCE
		# Existing contracts retain the permissive v1 portal model. New contracts
		# are explicitly stamped v2 so their access checks can evolve safely.
		if not state.has("access_model_version"): state.access_model_version = 1
		if _chapter == 0 and not state.has("samba_model_version"): state.samba_model_version = 1
		if _chapter == 1 and not state.has("backup_model_version"): state.backup_model_version = 1
		if _chapter == 3 and not state.has("identity_model_version"): state.identity_model_version = 1
		if _chapter == 3 and int(state.get("identity_model_version", 1)) >= IDENTITY_MODEL_VERSION: _identity_ensure_state()
		if _chapter == 3 and int(state.get("identity_model_version", 1)) >= IDENTITY_MODEL_VERSION: _normalize_identity_probes()
		if _chapter == 2: _normalize_transport_probes()
		if _chapter == 2 and int(state.get("firewall_model_version", 1)) >= FIREWALL_MODEL_VERSION: _firewall_ensure_state(false)
		if _chapter == 4 and int(state.get("edr_model_version", 1)) >= EDR_MODEL_VERSION: _edr_ensure_state(false)
		if _chapter == 5 and int(state.get("portal_model_version", 1)) >= 2:
			PortalStorage.ensure(self)
			_normalize_portal_probes()
		return
	state = {"schema":2,"access_model_version":ACCESS_MODEL_VERSION,"portal_model_version":2 if _chapter == 5 else 1,"identity_model_version":IDENTITY_MODEL_VERSION if _chapter == 3 else 1,"samba_model_version":2 if _chapter == 0 else 1,"backup_model_version":2 if _chapter == 1 else 1,"edr_model_version":EDR_MODEL_VERSION if _chapter == 4 else 1,"firewall_model_version":FIREWALL_MODEL_VERSION if _chapter == 2 else 1,"fs":{},"dirs":["/","/etc","/srv","/srv/data","/srv/share","/var","/var/log","/tmp","/home",OPERATOR_HOME,"/restore","/evidence"],"cwd":OPERATOR_HOME,"host":HOSTS[_chapter],"connected":false,"config_path":PATHS[_chapter],"service":SERVICES[_chapter],"active":true,"applied":{},"snapshots":[],"events":[],"observations":[],"last_restore":{},"error":"","mutation":0,"dirty":false,"scenario":scenario.duplicate(true)}
	state.dirs.append(PATHS[_chapter].get_base_dir())
	if not str(scenario.get("host", "")).is_empty(): state.host = str(scenario.host)
	state.fs[PATHS[_chapter]] = Samba.configuration_text({"staff":"read","guest":"write"}) if _chapter == 0 else (FirewallPolicy.configuration_text(scenario.initial if scenario.has("initial") else {"dns":"off","business":"allow","admin_public":"allow","tls":"off"}) if _chapter == 2 else "# " + SERVICES[_chapter] + " service configuration\n" + SEEDS[_chapter])
	if not scenario.is_empty() and scenario.has("initial"):
		if _chapter != 2: state.fs[PATHS[_chapter]] = _config_text(scenario.initial)
	if not scenario.is_empty():
		state.scenario = scenario.duplicate(true)
		if String(scenario.get("seed_snapshot_repository", "")) in ["local", "offsite"]:
			state.snapshots.append({"id":"00000001" if _chapter == 1 else 1,"repository":scenario.seed_snapshot_repository,"paths":["/srv/data"],"files":RECORDS.duplicate(true)})
	state.applied = _parse_config(state.fs[PATHS[_chapter]]).values
	if _chapter == 2 and int(state.get("firewall_model_version", 1)) >= FIREWALL_MODEL_VERSION: _firewall_ensure_state(true)
	if _chapter == 3: _identity_ensure_state(); _identity_sync_config()
	state.probes = _legacy_probes()
	if _chapter == 3: _normalize_identity_probes()
	if _chapter == 2: _normalize_transport_probes()
	_normalize_backup_probes()
	state.fs["/srv/share/report.txt"] = "Aoba sales report / internal use\n"
	if _chapter == 0 and bool(scenario.get("linked_branch_storage", false)):
		state.fs["/srv/share/customers.csv"] = RECORDS["customers.csv"]
		state.fs["/srv/share/partner-order.csv"] = RECORDS["orders.csv"]
	if _chapter == 5: state.fs[PortalStorage.PRIMARY_PATH] = "order_id,customer,total\nPO-1001,Aoba Trading,12800\nPO-1002,Minato Foods,7600\n"
	for name in RECORDS: state.fs["/srv/data/" + name] = RECORDS[name]
	if _chapter == 1:
		var manifest := "# 顧客から預かった正常時のファイル照合票 / SHA-256\n"
		for name in _backup_records(): manifest += str(_backup_records()[name]).sha256_text()+"  /restore/srv/data/"+name+"\n"
		state.fs[OPERATOR_HOME+"/recovery-manifest.sha256"] = manifest
	if _chapter == 4: _edr_ensure_state(true)
	state.fs["/var/log/evidence.log"] = EVIDENCE
	if not scenario.is_empty():
		var suspect: String = scenario.get("suspect","none")
		var incident := "09:40 EDR investigation / retained original\n"
		for endpoint in ["pc_a","pc_b"]:
			var suspicious: bool = suspect==endpoint or suspect=="both"
			incident += "09:4%d %s process=%s outbound=%s event=%s\n" % [1 if endpoint=="pc_a" else 2,endpoint.to_upper().replace("_","-"),"unknown" if suspicious else "office","203.0.113.77" if suspicious else "192.0.2.20","unusual-file-access count=42" if suspicious else "approved-business-session"]
		state.fs["/var/log/evidence.log"] = incident; state.evidence_original = incident
		for path in scenario.get("fs_overrides", {}): state.fs[path] = scenario.fs_overrides[path]
		for path in scenario.get("missing_files", []): state.fs.erase(path)
		if _chapter == 1 and scenario.has("latest_snapshot_overrides") and not state.snapshots.is_empty():
			var latest_files: Dictionary = RECORDS.duplicate(true)
			for path in scenario.latest_snapshot_overrides:
				latest_files[str(path).get_file()] = str(scenario.latest_snapshot_overrides[path])
			state.snapshots.append({"id":"00000002","repository":str(scenario.get("desired",{}).get("repository","offsite")),"paths":["/srv/data"],"files":latest_files})
	# The approved source is captured only for a freshly seeded recovery case,
	# after its damaged/missing files have been installed. Loaded saves never
	# manufacture a new baseline from the files they happen to contain.
	if _chapter == 1: BackupAuthorization.initialize(state, scenario, _backup_records())
	if _chapter == 4 and int(state.get("edr_model_version",1)) >= EDR_MODEL_VERSION:
		if EndpointRemediation.enabled(state): EndpointRemediation.initialize(state)
		state.evidence_original = _edr_serialize_timeline()
		state.fs["/var/log/evidence.log"] = state.evidence_original
	if _chapter == 4:
		HotelFrontdesk.initialize(state)
		for probe in _active_probes():
			if str(probe.get("id", "")) == "evidence-log":
				var expected := str(state.get("evidence_original", EVIDENCE)).sha256_text()
				if str(probe.get("expectation", "")) != expected: _clear_probe_measurement(probe)
				probe.expectation = expected
	state.fs[OPERATOR_HOME+"/README.txt"] = "HOST " + state.host + "\nCONFIG " + state.config_path + "\nSERVICE " + state.service + "\n\n" + _reference()
	if _chapter == 5:
		PortalStorage.ensure(self)
		_normalize_portal_probes()
	if _chapter == 3: state.fs[OPERATOR_HOME+"/identity-tests.txt"] = "IDENTITY TRAINING FIXTURES (offline exercise)\npassword: " + IDENTITY_PASSWORD + "\notp: " + IDENTITY_OTP + "\nseed session: former-seed-1\n"
	if _chapter == 5:
		var portal_fixtures := "partner-session = partner / password only\npartner-mfa-session = partner / MFA verified\n"
		if not bool(scenario.get("linked_identity", false)):
			portal_fixtures = "staff-session = staff / MFA verified\n" + portal_fixtures
		state.fs[OPERATOR_HOME+"/access-tests.txt"] = "PORTAL TRAINING FIXTURES (演習用・実ネットワークなし)\n" + portal_fixtures + \
			"link=current (day 0)\nlink=week-old (day 8)\nlink=month-old (day 31)\n"
	state.fs[OPERATOR_HOME+"/requirements.txt"] = "対象サービス: " + state.service + "\n" + str(scenario.get("brief","メールの要件を確認し、設定を保存・再起動して動作を検証してください。")) + "\n\n" + "\n".join(scenario.get("checks",[]))
	state.events = ["09:00 " + state.service + ": started", "09:01 customer: service incident reported"]

func _config_text(values: Dictionary) -> String:
	if _chapter == 0 and int(state.get("samba_model_version", 1)) >= 2: return Samba.configuration_text(values)
	if _chapter == 2 and int(state.get("firewall_model_version", 1)) >= FIREWALL_MODEL_VERSION: return FirewallPolicy.configuration_text(values)
	var lines: Array[String] = []
	for key in values.keys(): lines.append(str(key) + "=" + str(values[key]))
	return "# scenario configuration\n" + "\n".join(lines) + "\n"

func configuration_text(values: Dictionary) -> String:
	return _config_text(values)

func _path(value: String) -> String:
	var path := value.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if path == "~": return _home_alias(OPERATOR_HOME)
	if path.begins_with("~/"): path = OPERATOR_HOME + "/" + path.substr(2)
	for legacy in LEGACY_HOMES:
		if path == legacy or path.begins_with(legacy + "/"):
			return path if _legacy_path_exists(path) else OPERATOR_HOME + path.substr(legacy.length())
	return (path if path.begins_with("/") else str(state.cwd).path_join(path)).simplify_path().trim_suffix("/") if path != "/" else "/"

func _restore_parent_dirs(paths: Array) -> bool:
	var needed: Array[String] = []
	for raw_path in paths:
		var parent := str(raw_path).get_base_dir()
		var chain: Array[String] = []
		while parent not in state.dirs and parent != "/":
			if state.fs.has(parent): return false
			chain.push_front(parent); parent = parent.get_base_dir()
		for directory in chain:
			if directory not in needed: needed.append(directory)
	return true

func _legacy_path_exists(path: String) -> bool:
	return state.get("fs",{}).has(path) or path in state.get("dirs",[])

func _home_alias(path: String) -> String:
	for legacy in LEGACY_HOMES:
		for key in state.get("fs",{}).keys():
			if str(key) == legacy or str(key).begins_with(legacy + "/"): return legacy
	return path

func _migrate_operator_home() -> void:
	if not state.has("fs") or not state.fs is Dictionary: state.fs = {}
	if not state.has("dirs") or not state.dirs is Array: state.dirs = []
	if OPERATOR_HOME not in state.dirs: state.dirs.append(OPERATOR_HOME)
	for legacy in LEGACY_HOMES:
		var keys: Array = state.fs.keys().filter(func(key): return str(key) == legacy or str(key).begins_with(legacy + "/"))
		for key in keys:
			var old_path := str(key)
			var target := OPERATOR_HOME + old_path.substr(legacy.length())
			if not state.fs.has(target):
				state.fs[target] = state.fs[old_path]
				state.fs.erase(old_path)
			elif state.fs[target] == state.fs[old_path]:
				# Identical copies do not need two visible paths.
				state.fs.erase(old_path)
		for dir in state.dirs.duplicate():
			var old_dir := str(dir)
			if old_dir != legacy and not old_dir.begins_with(legacy + "/"): continue
			var target_dir := OPERATOR_HOME + old_dir.substr(legacy.length())
			if target_dir not in state.dirs: state.dirs.append(target_dir)
			var has_legacy_file := false
			for remaining in state.fs.keys():
				if str(remaining) == old_dir or str(remaining).begins_with(old_dir + "/"):
					has_legacy_file = true
					break
			if not has_legacy_file: state.dirs.erase(old_dir)
	var old_cwd := str(state.get("cwd", ""))
	for legacy in LEGACY_HOMES:
		if old_cwd == legacy or old_cwd.begins_with(legacy + "/"):
			state.cwd = old_cwd if _legacy_path_exists(old_cwd) else OPERATOR_HOME + old_cwd.substr(legacy.length())
			break

func list_files(path: String) -> Array[String]:
	var result: Array[String] = []
	if not state.connected: return result
	var base := _path(path)
	var prefix := "/" if base == "/" else base + "/"
	for dir in state.dirs:
		if str(dir).begins_with(prefix) and dir != base:
			var tail := str(dir).substr(prefix.length())
			if not tail.is_empty() and not tail.contains("/") and str(dir) + "/" not in result: result.append(str(dir) + "/")
	for file in state.fs:
		if str(file).begins_with(prefix) and not str(file).substr(prefix.length()).contains("/"): result.append(str(file))
	result.sort()
	return result

func read_file(path: String) -> String:
	if not state.connected: return "Permission denied: ssh client で顧客端末に接続してください。"
	var p := _path(path)
	return str(state.fs[p]) if state.fs.has(p) else "cat: %s: No such file" % p

func write_file(path: String, content: String) -> bool:
	if not state.connected: return false
	var p := _path(path)
	if p.get_base_dir() not in state.dirs or p in state.dirs: return false
	state.fs[p] = content
	if p == state.config_path: state.dirty = true
	_touch("write " + p)
	return true

func _touch(event: String) -> void:
	state.mutation += 1
	state.events.append("%04d %s" % [int(state.mutation), event])
	if state.events.size() > 80: state.events.pop_front()

func _edr_ensure_state(fresh: bool = false) -> void:
	if _chapter != 4 or int(state.get("edr_model_version", 1)) < EDR_MODEL_VERSION: return
	if fresh or not state.has("edr_devices") or not state.edr_devices is Array:
		var suspect := str(state.get("scenario",{}).get("suspect","pc_a")) if state.get("scenario",{}) is Dictionary else "pc_a"
		var advanced := int(state.get("scenario",{}).get("tier",1)) >= 3 if state.get("scenario",{}) is Dictionary else false
		state.edr_devices = EndpointResponse.initial_devices(suspect,advanced)
	if not state.has("edr_actions") or not state.edr_actions is Array: state.edr_actions = []
	if not state.has("edr_evidence") or not state.edr_evidence is Dictionary:
		state.edr_evidence = {"collected":false,"source_sha256":"","copy_sha256":"","valid":false}
	for device in state.edr_devices:
		var id := str(device.get("id",""))
		var isolated := str(state.applied.get(id,"connected")) == "isolated"
		device.isolated = isolated
		device.business_status = "interrupted" if isolated else "healthy"
		device.management_connected = true
		if EndpointRemediation.enabled(state):
			var recovery: Dictionary = EndpointRemediation.status(state,id)
			device.merge(recovery,true)
			device.business_status = "interrupted" if isolated or not bool(recovery.get("business_available",false)) else "healthy"

func edr_snapshot() -> Dictionary:
	if _chapter != 4 or int(state.get("edr_model_version",1)) < EDR_MODEL_VERSION: return {"ok":false,"code":426,"error":"legacy_model"}
	if not state.active: return {"ok":false,"code":503,"error":"service_unavailable"}
	if not state.connected: return {"ok":false,"code":401,"error":"not_connected"}
	_edr_ensure_state(false)
	var result := EndpointResponse.public_snapshot(state,_edr_evidence_status())
	result.recovery_enabled = EndpointRemediation.enabled(state)
	if result.recovery_enabled: result.merge(EndpointRemediation.snapshot(state),true)
	return result

func _edr_device(device_id: String) -> Dictionary:
	for device in state.get("edr_devices",[]):
		if str(device.get("id","")) == device_id: return device
	return {}

func _edr_serialize_timeline() -> String:
	var lines: Array[String] = []
	for device in state.get("edr_devices",[]):
		for event in device.get("events",[]):
			lines.append("%s %s type=%s process=%s publisher=%s remote=%s detail=%s change_ref=%s" % [str(event.get("time","")),str(device.get("id","")),str(event.get("type","")),str(event.get("process","")),str(event.get("publisher","")),str(event.get("remote_address","")),str(event.get("detail","")),str(event.get("change_ref",""))])
	return "\n".join(lines) + "\n"

func _edr_evidence_status() -> Dictionary:
	var source := str(state.fs.get("/var/log/evidence.log", ""))
	var copy := str(state.fs.get("/evidence/original.log", ""))
	var source_hash := source.sha256_text() if not source.is_empty() else ""
	var copy_hash := copy.sha256_text() if not copy.is_empty() else ""
	var valid: bool = not source.is_empty() and not copy.is_empty() and source == str(state.get("evidence_original", source)) and source == copy and source_hash == copy_hash
	return {"collected":not copy.is_empty(),"source_sha256":source_hash,"copy_sha256":copy_hash,"valid":valid}

func _edr_action(device_id: String, action: String, result: String) -> void:
	state.edr_actions.append({"sequence":state.edr_actions.size()+1,"device":device_id,"action":action,"result":result})
	_touch("edr %s %s result=%s" % [action,device_id,result])

func _edr_command(args: Array) -> String:
	if _chapter != 4 or int(state.get("edr_model_version",1)) < EDR_MODEL_VERSION: return EndpointResponse.json_result(false,426,{"error":"legacy_model"})
	if not state.active: return EndpointResponse.json_result(false,503,{"error":"service_unavailable"})
	if not state.connected: return EndpointResponse.json_result(false,401,{"error":"not_connected"})
	_edr_ensure_state(false)
	if args.size() < 2: return EndpointResponse.json_result(false,400,{"error":"usage"})
	var action := str(args[1]).to_lower()
	if action in ["files","status","quarantine","restore","scan"]:
		return _edr_recovery_command(action,args)
	if action in ["isolate","release"]:
		if args.size() != 3 or str(args[2]) not in ["pc_a","pc_b"]: return EndpointResponse.json_result(false,400,{"error":"usage"})
		if bool(state.get("dirty",false)): return EndpointResponse.json_result(false,409,{"error":"unsaved_config"})
		var device_id := str(args[2]); var device := _edr_device(device_id)
		if device.is_empty(): return EndpointResponse.json_result(false,404,{"error":"unknown_device"})
		var isolated := action == "isolate"
		state.applied[device_id] = "isolated" if isolated else "connected"
		state.fs[state.config_path] = _config_text(state.applied)
		state.dirty = false
		device.isolated = isolated; device.business_status = "interrupted" if isolated else "healthy"; device.management_connected = true
		_edr_ensure_state(false)
		_edr_action(device_id,action,"ok")
		return EndpointResponse.json_result(true,200,{"device":device_id,"isolated":isolated,"business_status":device.business_status})
	if action == "devices":
		if args.size() != 2: return EndpointResponse.json_result(false,400,{"error":"usage"})
		return EndpointResponse.json_result(true,200,{"devices":state.edr_devices.duplicate(true),"actions":state.edr_actions.duplicate(true)})
	if action == "timeline":
		if args.size() != 3 or str(args[2]) not in ["pc_a","pc_b"]: return EndpointResponse.json_result(false,400,{"error":"usage"})
		var timeline_device := _edr_device(str(args[2]))
		if timeline_device.is_empty(): return EndpointResponse.json_result(false,404,{"error":"unknown_device"})
		return EndpointResponse.json_result(true,200,{"device":str(args[2]),"events":timeline_device.get("events",[]).duplicate(true)})
	if action == "collect":
		if args.size() != 2: return EndpointResponse.json_result(false,400,{"error":"usage"})
		var source := str(state.fs.get("/var/log/evidence.log", "")); var source_hash := source.sha256_text()
		if source.is_empty() or source != str(state.get("evidence_original",source)):
			return EndpointResponse.json_result(false,422,{"error":"source_invalid"})
		var copy_path := "/evidence/original.log"
		if state.fs.has(copy_path) and str(state.fs[copy_path]) != source:
			return EndpointResponse.json_result(false,409,{"error":"copy_conflict"})
		var existed: bool = state.fs.has(copy_path)
		if not existed: state.fs[copy_path] = source
		var copy_hash := str(state.fs[copy_path]).sha256_text(); var valid: bool = source_hash == copy_hash
		state.edr_evidence = _edr_evidence_status()
		if not existed: _edr_action("evidence","collect","ok")
		return EndpointResponse.json_result(valid,200 if valid else 422,{"evidence":state.edr_evidence.duplicate(true)})
	return EndpointResponse.json_result(false,400,{"error":"unknown_command"})

func _edr_recovery_command(action: String, args: Array) -> String:
	if not EndpointRemediation.enabled(state): return EndpointResponse.json_result(false,426,{"error":"legacy_model"})
	if action == "restore":
		if args.size() != 3 or not str(args[2]).is_valid_int(): return EndpointResponse.json_result(false,400,{"error":"usage"})
	else:
		if args.size() != (4 if action == "quarantine" else 3) or str(args[2]) not in ["pc_a","pc_b"]: return EndpointResponse.json_result(false,400,{"error":"usage"})
	var result: Dictionary = {}
	if action == "files": return EndpointResponse.json_result(true,200,{"files":EndpointRemediation.files(state,str(args[2]))})
	if action == "status":
		result = EndpointRemediation.status(state,str(args[2]))
		result.ready = bool(result.get("scan_current",false)) and bool(result.get("scan_clean",false)) and int(result.get("threat_count",-1)) == 0 and bool(result.get("business_available",false)) and str(state.applied.get(str(args[2]),"")) == "connected"
		return EndpointResponse.json_result(true,200,result)
	if action == "scan":
		result = EndpointRemediation.scan(state,str(args[2]))
		result.merge({"ok":true,"code":200,"changed":true},true)
	elif action == "quarantine": result = EndpointRemediation.quarantine(state,str(args[2]),str(args[3]))
	elif action == "restore": result = EndpointRemediation.restore(state,int(args[2]))
	if bool(result.get("ok",false)) and bool(result.get("changed",false)):
		_edr_action(str(result.get("device",args[2])),action,"ok")
		for key in ["file_id","sha256","quarantine_id","findings","clean","threat_count"]:
			if result.has(key): state.edr_actions.back()[key] = result[key]
		_edr_ensure_state(false)
	return JSON.stringify(result)

func _audit(event: String) -> void:
	# Audit records are evidence, not a guest-state mutation. Reads and denied
	# requests must not invalidate a validated configuration.
	state.events.append("%04d %s" % [int(state.mutation), event])
	if state.events.size() > 80: state.events.pop_front()

func _identity_event(category: String, event_type: String, user: String, outcome: String, extra: Dictionary = {}) -> void:
	if _chapter != 3 or int(state.get("identity_model_version", 1)) < IDENTITY_MODEL_VERSION: return
	if not state.has("identity_events") or not state.identity_events is Array: state.identity_events = []
	var item: Dictionary = {"sequence":int(state.get("identity_event_sequence", 0)),"category":category,"type":event_type,"user":user,"outcome":outcome}
	state.identity_event_sequence = int(state.get("identity_event_sequence", 0)) + 1
	item.merge(extra, true)
	state.identity_events.append(item)
	if state.identity_events.size() > 120: state.identity_events.pop_front()

func _identity_redact_command(command: String) -> String:
	var args := _tokens(command)
	var command_index := 0
	if not args.is_empty() and str(args[0]).to_lower() == "sudo": command_index = 1
	if args.size() > command_index + 1 and str(args[command_index]).to_lower() == "identity":
		var action := str(args[command_index + 1]).to_lower()
		if action in ["login", "otp", "password-set", "password-update"]:
			var safe_prefix: Array[String] = []
			if command_index == 1: safe_prefix.append("sudo")
			safe_prefix.append("identity"); safe_prefix.append(action)
			if args.size() > command_index + 2: safe_prefix.append(str(args[command_index + 2]))
			safe_prefix.append("<redacted>")
			if action == "password-set" and args.size() == command_index + 5 and str(args[command_index + 4]) in ["temporary", "permanent"]: safe_prefix.append(str(args[command_index + 4]))
			return " ".join(safe_prefix)
	var lower := command.to_lower()
	if lower.contains("identity.client.test"):
		# Tokenization retains spaces and quote concatenation inside a URL value.
		# Redact the complete query parameter, including repeated parameters.
		var secret_query := RegEx.new()
		secret_query.compile("(?i)([?&]password=)[^&]*")
		for index in args.size():
			if str(args[index]).to_lower().contains("identity.client.test"):
				args[index] = secret_query.sub(str(args[index]), "$1<redacted>", true)
		return " ".join(args)
	return command

func _tokens(command: String) -> Array[String]:
	var tokens: Array[String] = []
	var word := ""
	var quote := ""
	for ch in command:
		if ch in ["\"", "'"]:
			if quote.is_empty(): quote = ch
			elif quote == ch: quote = ""
			else: word += ch
		elif ch in [" ", "\t"] and quote.is_empty():
			if not word.is_empty(): tokens.append(word); word = ""
		else: word += ch
	if not word.is_empty(): tokens.append(word)
	return tokens

func _fingerprint() -> String:
	var paths: Array = []
	var share_paths: Array[String] = []
	var backup_restore_paths: Array[String] = []
	if _chapter == 1 and int(state.get("backup_model_version",1)) >= 2:
		for probe in _active_probes():
			var probe_command := str(probe.get("command", ""))
			if probe_command.begins_with("sha256sum "):
				backup_restore_paths.append(probe_command.trim_prefix("sha256sum ").strip_edges())
	if _chapter == 0 and int(state.get("samba_model_version",1)) >= 2:
		for settings in state.applied.get("shares",{}).values():
			var share_path := str(settings.get("path","")).simplify_path()
			if not share_path.is_empty(): share_paths.append(share_path)
	for path in state.fs.keys():
		var p := str(path)
		if p == str(state.config_path) or p.begins_with("/srv/data/") or p == "/srv/share/report.txt" or (_portal_model_v2() and p == PortalStorage.PRIMARY_PATH) or p.begins_with("/restore/") or p.begins_with("/var/log/") or p.begins_with("/evidence/") or p in backup_restore_paths: paths.append(p)
		elif share_paths.any(func(folder): return p.begins_with(str(folder).trim_suffix("/")+"/")): paths.append(p)
	paths.sort()
	var file_text := ""
	for path in paths:
		file_text += str(path) + "=" + str(state.fs[path]) + "\n"
	var snapshots: Array = []
	for item in state.snapshots:
		snapshots.append({"id":_snapshot_id_text(item.get("id","")),"repository":str(item.get("repository","")),"paths":item.get("paths",["/srv/data"]),"files":item.get("files",{})})
	# Dictionary insertion order can change after JSON save/load. Hash canonical data.
	var identity_security: Dictionary = {}
	if _chapter == 3 and int(state.get("identity_model_version",1)) >= IDENTITY_MODEL_VERSION:
		var revoked: Array = []
		for session in state.get("identity_sessions",[]):
			if bool(session.get("revoked",false)) or str(session.get("user",""))=="former": revoked.append(str(session.get("id",""))+":"+str(bool(session.get("revoked",false))))
		var identity_users_fingerprint: Dictionary = {}
		var credential_changes: Dictionary = {}
		for identity_user in ["former", "current"]:
			var account: Dictionary = state.get("identity_users",{}).get(identity_user,{})
			identity_users_fingerprint[identity_user] = {"enabled":bool(account.get("enabled",false)),"otp_registered":bool(account.get("otp_registered",false))}
			if int(account.get("credential_revision",0)) > 0 or bool(account.get("password_temporary",false)) or (account.get("required_actions",[]) is Array and not account.required_actions.is_empty()):
				credential_changes[identity_user] = {"password_sha256":str(account.get("password_sha256","")),"password_temporary":bool(account.get("password_temporary",false)),"credential_revision":int(account.get("credential_revision",0)),"required_actions":account.get("required_actions",[])}
		identity_security = {"users":identity_users_fingerprint,"mfa":bool(state.get("identity_mfa_required",false)),"revoked":revoked}
		if not credential_changes.is_empty(): identity_security.credentials = credential_changes
	var fingerprint_payload: Dictionary = {"active":state.active,"applied":state.applied,"snapshots":snapshots,"files":file_text}
	if _firewall_model_v2(): fingerprint_payload.firewall_pending = state.get("firewall_pending", {}).duplicate(true)
	if _portal_model_v2(): fingerprint_payload.portal_shares = PortalStorage.canonical_shares(self)
	if has_linked_identity(): fingerprint_payload.linked_identity = _linked_identity_security_snapshot()
	if has_linked_business() or has_linked_branch_storage(): fingerprint_payload.linked_business = linked_business_fingerprint()
	if _chapter == 4 and EndpointRemediation.enabled(state): fingerprint_payload.endpoint_files = EndpointRemediation.fingerprint(state)
	# Keep the v1/other-chapter fingerprint shape stable. Identity state is part
	# of the contract only after the chapter-3 v2 migration marker exists.
	if not identity_security.is_empty(): fingerprint_payload.identity = identity_security
	return JSON.stringify(fingerprint_payload,"",true).sha256_text()

func _firewall_model_v2() -> bool:
	return _chapter == 2 and int(state.get("firewall_model_version", 1)) >= FIREWALL_MODEL_VERSION

func _firewall_ensure_state(fresh: bool = false) -> void:
	if not _firewall_model_v2(): return
	var parsed: Dictionary = _parse_config(str(state.fs.get(state.config_path, "")))
	# JSON save/load turns integral firewall ports and version values into floats.
	# Normalize the persisted applied policy through the same parser so a
	# semantically unchanged policy keeps its diagnostic fingerprint.
	if state.get("applied", null) is Dictionary:
		var normalized_applied: Dictionary = FirewallPolicy.parse_config(FirewallPolicy.canonical_text(state.applied))
		if str(normalized_applied.get("error", "")).is_empty(): state.applied = normalized_applied.values.duplicate(true)
	if not str(parsed.get("error", "")).is_empty():
		if not state.has("firewall_pending") or not state.firewall_pending is Dictionary: state.firewall_pending = state.applied.duplicate(true) if state.applied is Dictionary else {}
		if not state.has("firewall_logs") or not state.firewall_logs is Array: state.firewall_logs = []
		if not state.has("firewall_last_trace") or not state.firewall_last_trace is Dictionary: state.firewall_last_trace = {}
		return
	if fresh or not state.has("firewall_pending") or not state.firewall_pending is Dictionary or not bool(state.get("dirty", false)):
		state.firewall_pending = parsed.values.duplicate(true)
	else:
		# The editor writes the same file as the pending draft. Refresh it so
		# external editor changes are visible without touching active policy.
		state.firewall_pending = parsed.values.duplicate(true)
	if not state.has("firewall_logs") or not state.firewall_logs is Array: state.firewall_logs = []
	if not state.has("firewall_last_trace") or not state.firewall_last_trace is Dictionary: state.firewall_last_trace = {}
	if not state.has("firewall_pending_dirty"): state.firewall_pending_dirty = state.firewall_pending != state.applied if state.has("firewall_pending") else false
	if fresh: state.applied = parsed.values.duplicate(true)

func firewall_snapshot() -> Dictionary:
	if not _firewall_model_v2(): return {"ok":false,"error":"legacy_model","connected":state.connected,"active":state.active,"pending":{},"rules":[],"applied_rules":[]}
	_firewall_ensure_state(false)
	var pending: Dictionary = state.get("firewall_pending", {}) if state.get("firewall_pending", {}) is Dictionary else {}
	var applied: Dictionary = state.get("applied", {}) if state.get("applied", {}) is Dictionary else {}
	var disk_config: Dictionary = FirewallPolicy.parse_config(str(state.fs.get(state.config_path, "")))
	var disk_error := str(disk_config.get("error", ""))
	var error_text := str(state.get("error", "")) if not str(state.get("error", "")).is_empty() else disk_error
	return {"ok":error_text.is_empty(),"connected":bool(state.get("connected", false)),"active":bool(state.get("active", false)),"pending":not disk_error.is_empty() or bool(state.get("dirty", false)) or bool(state.get("firewall_pending_dirty", false)) or pending != applied,"rules":pending.get("rules", []).duplicate(true) if pending.get("rules", []) is Array else [],"applied_rules":applied.get("rules", []).duplicate(true) if applied.get("rules", []) is Array else [],"dns":str(pending.get("dns", applied.get("dns", "off"))),"tls":str(pending.get("tls", applied.get("tls", "off"))),"error":error_text,"logs":state.get("firewall_logs", []).duplicate(true),"last_trace":state.get("firewall_last_trace", {}).duplicate(true)}

func firewall_action(action: String, payload: Dictionary = {}) -> Dictionary:
	if not _firewall_model_v2(): return {"ok":false,"error":"legacy_model"}
	_firewall_ensure_state(false)
	if not state.connected and action not in ["revert"]: return {"ok":false,"error":"not_connected"}
	if action == "trace" and not state.active: return {"ok":false,"error":"service_unavailable"}
	var pending: Dictionary = state.get("firewall_pending", {}) if state.get("firewall_pending", {}) is Dictionary else {}
	var rules: Array = pending.get("rules", []).duplicate(true) if pending.get("rules", []) is Array else []
	var disk_config := FirewallPolicy.parse_config(str(state.fs.get(state.config_path, "")))
	if action in ["save_rule", "delete", "clone", "toggle", "move", "services"] and not str(disk_config.get("error", "")).is_empty(): return {"ok":false,"error":"invalid_config"}
	match action:
		"save_rule":
			if not payload.get("rule", null) is Dictionary: return {"ok":false,"error":"invalid_rule"}
			var incoming_payload: Dictionary = payload.rule.duplicate(true)
			var had_id := not str(incoming_payload.get("id", "")).strip_edges().is_empty()
			if not had_id:
				var generated_id := "rule-1"; var generated_suffix := 2
				while _firewall_rule_index(rules, generated_id) >= 0: generated_id = "rule-%d" % generated_suffix; generated_suffix += 1
				incoming_payload.id = generated_id
			var checked := FirewallPolicy.normalize_rule(incoming_payload)
			if not bool(checked.get("ok", false)): return {"ok":false,"error":"invalid_rule","detail":str(checked.get("error", "invalid_rule"))}
			var incoming: Dictionary = checked.rule
			var found := false
			for i in rules.size():
				if str(rules[i].get("id", "")) == str(incoming.id): rules[i] = incoming; found = true; break
			if not found:
				if had_id: return {"ok":false,"error":"rule_missing"}
				if str(payload.get("insert", "bottom")) == "top": rules.push_front(incoming)
				else: rules.append(incoming)
			pending.rules = rules
			return _firewall_save_pending(pending)
		"delete":
			var delete_id := str(payload.get("id", ""))
			var delete_index := _firewall_rule_index(rules, delete_id)
			if delete_index < 0: return {"ok":false,"error":"rule_missing"}
			rules.remove_at(delete_index); pending.rules = rules
			return _firewall_save_pending(pending)
		"clone":
			var clone_id := str(payload.get("id", "")); var clone_index := _firewall_rule_index(rules, clone_id)
			if clone_index < 0: return {"ok":false,"error":"rule_missing"}
			var copy: Dictionary = rules[clone_index].duplicate(true); var base_id := (str(copy.id).substr(0, 32) + "-copy"); var next_id := base_id; var suffix := 2
			while _firewall_rule_index(rules, next_id) >= 0: next_id = base_id + str(suffix); suffix += 1
			copy.id = next_id; rules.insert(clone_index + 1, copy); pending.rules = rules
			return _firewall_save_pending(pending)
		"toggle":
			var toggle_id := str(payload.get("id", "")); var toggle_index := _firewall_rule_index(rules, toggle_id)
			if toggle_index < 0: return {"ok":false,"error":"rule_missing"}
			rules[toggle_index].disabled = not bool(rules[toggle_index].get("disabled", false)); pending.rules = rules
			return _firewall_save_pending(pending)
		"move":
			var move_id := str(payload.get("id", "")); var move_index := _firewall_rule_index(rules, move_id); var direction := str(payload.get("direction", ""))
			if move_index < 0: return {"ok":false,"error":"rule_missing"}
			var target_index := -1
			var move_interface := str(rules[move_index].get("interface", ""))
			if direction == "up":
				for candidate_index in range(move_index - 1, -1, -1):
					if str(rules[candidate_index].get("interface", "")) == move_interface: target_index = candidate_index; break
			elif direction == "down":
				for candidate_index in range(move_index + 1, rules.size()):
					if str(rules[candidate_index].get("interface", "")) == move_interface: target_index = candidate_index; break
			if target_index < 0 or target_index >= rules.size(): return {"ok":true,"changed":false,"pending":pending.duplicate(true)}
			var moved: Variant = rules[move_index]; rules[move_index] = rules[target_index]; rules[target_index] = moved; pending.rules = rules
			return _firewall_save_pending(pending)
		"services":
			var dns := str(payload.get("dns", pending.get("dns", "off"))); var tls := str(payload.get("tls", pending.get("tls", "off")))
			if dns not in ["off", "on"] or tls not in ["off", "on"]: return {"ok":false,"error":"invalid_config"}
			# Service toggles are independent of the ordered rule list. Work on a
			# detached draft and carry the exact current rules through the write so
			# changing DNS/TLS can never replace a customer's custom policy.
			var service_pending: Dictionary = pending.duplicate(true)
			service_pending.rules = rules.duplicate(true)
			service_pending.dns = dns; service_pending.tls = tls
			return _firewall_save_pending(service_pending)
		"apply":
			var parsed := FirewallPolicy.parse_config(str(state.fs.get(state.config_path, "")))
			if not str(parsed.get("error", "")).is_empty(): return {"ok":false,"error":"invalid_config","detail":str(parsed.get("error", ""))}
			var previous: Dictionary = state.applied.duplicate(true)
			state.applied = parsed.values.duplicate(true); state.firewall_pending = parsed.values.duplicate(true); state.firewall_pending_dirty = false; state.active = true; state.error = ""; state.dirty = false
			if previous != state.applied: _touch("firewall applied")
			return {"ok":true,"changed":previous != state.applied,"pending":state.firewall_pending.duplicate(true),"applied":state.applied.duplicate(true)}
		"revert":
			var current_file := str(state.fs.get(state.config_path, "")); var restored := FirewallPolicy.canonical_text(state.applied)
			if state.applied is Dictionary and not state.applied.has("rules"): return {"ok":false,"error":"invalid_config"}
			var changed: bool = current_file != restored or pending != state.applied
			state.firewall_pending = state.applied.duplicate(true); state.firewall_pending_dirty = false; state.fs[state.config_path] = restored; state.dirty = false; state.active = true; state.error = ""
			if changed: _touch("firewall reverted")
			return {"ok":true,"changed":changed,"pending":state.firewall_pending.duplicate(true),"applied":state.applied.duplicate(true)}
		"trace":
			var trace := _firewall_trace(payload)
			if not bool(trace.get("ok", false)): return trace
			state.firewall_last_trace = trace.duplicate(true)
			if bool(trace.get("logged", false)) or str(trace.get("rule_id", "")) == "default":
				state.firewall_logs.append(trace.duplicate(true)); if state.firewall_logs.size() > 30: state.firewall_logs.pop_front()
			return trace
	return {"ok":false,"error":"invalid_action"}

func _firewall_rule_index(rules: Array, rule_id: String) -> int:
	for i in rules.size():
		if str(rules[i].get("id", "")) == rule_id: return i
	return -1

func _firewall_save_pending(pending: Dictionary) -> Dictionary:
	var checked := FirewallPolicy.parse_config(FirewallPolicy.canonical_text(pending))
	if not str(checked.get("error", "")).is_empty(): return {"ok":false,"error":"invalid_rule"}
	state.firewall_pending = checked.values.duplicate(true); state.firewall_pending_dirty = state.firewall_pending != state.applied; state.fs[state.config_path] = FirewallPolicy.canonical_text(checked.values); state.dirty = state.firewall_pending != state.applied
	_touch("firewall pending saved")
	return {"ok":true,"changed":true,"pending":state.firewall_pending.duplicate(true),"applied":state.applied.duplicate(true)}

func _firewall_trace(payload: Dictionary) -> Dictionary:
	var interface_name := str(payload.get("interface", "")); var protocol := str(payload.get("protocol", "")); var source := str(payload.get("source", "")); var destination := str(payload.get("destination", ""))
	var source_port := int(payload.get("source_port", 0)); var destination_port := int(payload.get("destination_port", 0))
	if interface_name not in ["wan", "lan"] or protocol not in ["tcp", "udp", "icmp"] or not FirewallPolicy._valid_ipv4(source) or not FirewallPolicy._valid_ipv4(destination) or source_port < 0 or source_port > 65535 or destination_port < 0 or destination_port > 65535: return {"ok":false,"error":"invalid_trace"}
	var decision := FirewallPolicy.evaluate(state.applied, interface_name, source, destination, protocol, source_port, destination_port)
	decision.ok = true; decision.interface = interface_name; decision.source = source; decision.destination = destination; decision.protocol = protocol; decision.source_port = source_port; decision.destination_port = destination_port
	return decision

func _identity_ensure_state() -> void:
	if _chapter != 3 or int(state.get("identity_model_version", 1)) < IDENTITY_MODEL_VERSION: return
	if not state.has("identity_users") or not state.identity_users is Dictionary:
		state.identity_users = {"former":{"enabled":str(state.applied.get("former","active")) == "active","otp_registered":true},"current":{"enabled":str(state.applied.get("current","active")) == "active","otp_registered":false}}
	else:
		for user in ["former","current"]:
			if not state.identity_users.has(user): state.identity_users[user] = {"enabled":true,"otp_registered":user == "former"}
			state.identity_users[user].otp_registered = bool(state.identity_users[user].get("otp_registered",user == "former"))
	for user in ["former","current"]:
		var account: Dictionary = state.identity_users[user]
		if not account.has("password_sha256"): account.password_sha256 = IDENTITY_PASSWORD.sha256_text()
		if not account.has("password_temporary"): account.password_temporary = false
		if not account.has("credential_revision"): account.credential_revision = 0
		if not account.has("required_actions") or not account.required_actions is Array: account.required_actions = []
	if not state.has("identity_mfa_required"): state.identity_mfa_required = str(state.applied.get("mfa","off")) == "on"
	if not state.has("identity_sessions") or not state.identity_sessions is Array:
		state.identity_sessions = []
		if state.scenario is Dictionary and state.scenario.has("sessions") and state.scenario.sessions is Array:
			for item in state.scenario.sessions: state.identity_sessions.append(item.duplicate(true) if item is Dictionary else {})
		if state.identity_sessions.is_empty(): state.identity_sessions.append({"id":"former-seed-1","user":"former","client":"legacy-app","ip":"192.0.2.44","issued":1,"revoked":false,"mfa":true})
	if not state.has("identity_challenges") or not state.identity_challenges is Array: state.identity_challenges = []
	if not state.has("identity_sequence"): state.identity_sequence = 2
	if not state.has("identity_event_sequence"): state.identity_event_sequence = 0
	if not state.has("identity_events") or not state.identity_events is Array: state.identity_events = []

func _identity_sync_config() -> void:
	if _chapter != 3 or int(state.get("identity_model_version", 1)) < IDENTITY_MODEL_VERSION: return
	if not state.has("identity_users"): return
	state.identity_users.former.enabled = str(state.applied.get("former","active")) == "active"
	state.identity_users.current.enabled = str(state.applied.get("current","active")) == "active"
	state.identity_mfa_required = str(state.applied.get("mfa","off")) == "on"
	if str(state.applied.get("sessions","valid")) == "revoked":
		for session in state.identity_sessions:
			if str(session.get("user",""))=="former": session.revoked = true
	_identity_project_config()

func _identity_project_config() -> void:
	for user in ["former","current"]:
		state.applied[user] = "active" if bool(state.identity_users[user].enabled) else "disabled"
	state.applied.mfa = "on" if bool(state.identity_mfa_required) else "off"
	state.applied.sessions = "revoked" if state.identity_sessions.all(func(session):return str(session.get("user",""))!="former" or bool(session.get("revoked",false))) else "valid"
	if not bool(state.get("dirty",false)): state.fs[state.config_path] = _config_text(state.applied)

func _identity_json(ok: bool, code: String, extra: Dictionary = {}) -> String:
	var status := 401 if code in ["mfa_required","password_update_required"] else (200 if ok else (503 if code == "service_unavailable" else (403 if code == "account_disabled" else (404 if code in ["unknown_token","unknown_session","unknown_challenge","unknown_command","unknown_route"] else (409 if code in ["challenge_used"] else (401 if code in ["invalid_credentials","mfa_required","password_update_required","invalid_otp","revoked_session"] else 400))))))
	var result: Dictionary = {"ok":ok,"code":status,"error":code}; result.merge(extra, true); return JSON.stringify(result)

func _identity_user(user: String) -> Dictionary:
	return state.identity_users.get(user, {}) if state.get("identity_users", {}) is Dictionary else {}

func _identity_valid_password(password: String) -> bool:
	if password.is_empty() or password.length() > 128: return false
	for ch in password:
		if ch == "\n" or ch == "\r" or ch == "\t" or ch.unicode_at(0) == 0: return false
	return true

func _restore_path_conflicts(path: String) -> bool:
	var cursor := path.get_base_dir()
	while cursor != "/":
		if state.fs.has(cursor): return true
		cursor = cursor.get_base_dir()
	return path in state.dirs

func identity_snapshot() -> Dictionary:
	if _chapter != 3 or int(state.get("identity_model_version", 1)) < IDENTITY_MODEL_VERSION: return {"users":[],"sessions":[],"policy":{"mfa_required":false},"events":[]}
	# This is a read-only render API. setup() creates these fields; do not repair
	# or otherwise mutate VM state while the desktop is rendering a snapshot.
	var identity_users: Dictionary = state.get("identity_users", {})
	var sessions: Array = state.get("identity_sessions", [])
	var mfa_required := bool(state.get("identity_mfa_required", false))
	var users: Array = []
	for user in ["former","current"]:
		var item: Dictionary = identity_users.get(user, {})
		users.append({"user":user,"enabled":bool(item.get("enabled",false)),"mfa_required":mfa_required,"otp_registered":bool(item.get("otp_registered",false)),"password_set":item.has("password_sha256"),"password_temporary":bool(item.get("password_temporary",false)),"credential_revision":int(item.get("credential_revision",0)),"required_actions":item.get("required_actions",[]).duplicate(true) if item.get("required_actions",[]) is Array else []})
	var events: Array[String] = []
	for event in state.get("events",[]):
		if str(event).contains("identity "): events.append(str(event))
	return {"users":users,"sessions":sessions.duplicate(true),"policy":{"mfa_required":mfa_required},"events":events,"audit_events":state.get("identity_events",[]).duplicate(true) if state.get("identity_events",[]) is Array else []}

func _identity_command(args: Array) -> String:
	if _chapter != 3 or int(state.get("identity_model_version", 1)) < IDENTITY_MODEL_VERSION: return _identity_json(false,"legacy_identity_model")
	if not state.active: return _identity_json(false,"service_unavailable")
	_identity_ensure_state()
	if args.size() < 2: return _identity_json(false,"usage")
	var action := str(args[1]).to_lower()
	if action == "users":
		var users: Array = []
		for u in ["former","current"]:
			var account: Dictionary = _identity_user(u)
			users.append({"user":u,"enabled":bool(account.get("enabled",false)),"mfa_required":bool(state.identity_mfa_required),"otp_registered":bool(account.get("otp_registered",false)),"password_set":account.has("password_sha256"),"password_temporary":bool(account.get("password_temporary",false)),"credential_revision":int(account.get("credential_revision",0)),"required_actions":account.get("required_actions",[]).duplicate(true) if account.get("required_actions",[]) is Array else []})
		return _identity_json(true,"ok",{"users":users})
	if action == "sessions":
		var user_filter := str(args[2]) if args.size() > 2 else ""; var sessions: Array = []
		for session in state.identity_sessions:
			if user_filter.is_empty() or str(session.get("user","")) == user_filter: sessions.append(session.duplicate(true))
		return _identity_json(true,"ok",{"sessions":sessions})
	if action == "enable":
		if args.size() != 4 or not state.identity_users.has(str(args[2])) or str(args[3]) not in ["on","off"]: return _identity_json(false,"usage")
		state.identity_users[str(args[2])].enabled = str(args[3]) == "on"
		_identity_project_config()
		_identity_event("admin","account_enable",str(args[2]),"on" if str(args[3]) == "on" else "off",{})
		_touch("identity enable %s=%s" % [args[2],args[3]])
		return _identity_json(true,"ok",{"user":str(args[2]),"enabled":bool(state.identity_users[str(args[2])].enabled)})
	if action == "mfa":
		if args.size() != 3 or str(args[2]) not in ["on","off"]: return _identity_json(false,"usage")
		state.identity_mfa_required = str(args[2]) == "on"
		_identity_project_config()
		_identity_event("admin","mfa_policy", "", "on" if str(args[2]) == "on" else "off",{})
		_touch("identity mfa=%s" % args[2]); return _identity_json(true,"ok",{"mfa_required":bool(state.identity_mfa_required)})
	if action == "password-set":
		if args.size() != 5 or not state.identity_users.has(str(args[2])) or str(args[4]) not in ["temporary","permanent"]: return _identity_json(false,"usage")
		var set_user := str(args[2]); var new_password := str(args[3])
		if not _identity_valid_password(new_password): return _identity_json(false,"invalid_password")
		var account: Dictionary = state.identity_users[set_user]
		var digest := new_password.sha256_text(); var temporary := str(args[4]) == "temporary"
		if str(account.get("password_sha256", "")) == digest and bool(account.get("password_temporary", false)) == temporary: return _identity_json(true,"ok",{"user":set_user,"temporary":temporary,"credential_revision":int(account.get("credential_revision",0)),"changed":false})
		account.password_sha256 = digest; account.password_temporary = temporary; account.credential_revision = int(account.get("credential_revision",0)) + 1
		account.required_actions = ["UPDATE_PASSWORD"] if temporary else []
		for challenge in state.identity_challenges:
			if str(challenge.get("user", "")) == set_user: challenge.used = true
		_identity_event("admin","password_set",set_user,"temporary" if temporary else "permanent",{"credential_revision":int(account.credential_revision)})
		_audit("identity password-set user=%s mode=%s" % [set_user,args[4]])
		_touch("identity password-set user=" + set_user)
		return _identity_json(true,"ok",{"user":set_user,"temporary":temporary,"credential_revision":int(account.credential_revision)})
	if action == "otp-delete":
		if args.size() != 3 or not state.identity_users.has(str(args[2])): return _identity_json(false,"usage")
		var otp_user := str(args[2]); var otp_account: Dictionary = state.identity_users[otp_user]
		if not bool(otp_account.get("otp_registered", false)): return _identity_json(true,"ok",{"user":otp_user,"otp_registered":false,"changed":false})
		otp_account.otp_registered = false
		for challenge in state.identity_challenges:
			if str(challenge.get("user", "")) == otp_user: challenge.used = true
		_identity_event("admin","otp_delete",otp_user,"ok",{})
		_audit("identity otp-delete user=" + otp_user); _touch("identity otp-delete user=" + otp_user)
		return _identity_json(true,"ok",{"user":otp_user,"otp_registered":false})
	if action == "logout" or action == "logout-all":
		if action == "logout":
			if args.size() != 3: return _identity_json(false,"usage")
			for session in state.identity_sessions:
				if str(session.get("id","")) == str(args[2]):
					session.revoked = true
					_identity_project_config()
					_identity_event("admin","session_revoke",str(session.get("user","")),"ok",{"session":str(args[2])})
					_touch("identity logout "+str(args[2])); return _identity_json(true,"ok",{"id":str(args[2])})
			return _identity_json(false,"unknown_session")
		if args.size() != 3 or not state.identity_users.has(str(args[2])): return _identity_json(false,"usage")
		var count := 0
		for session in state.identity_sessions:
			if str(session.get("user","")) == str(args[2]): session.revoked = true; count += 1
		for challenge in state.identity_challenges:
			if str(challenge.get("user",""))==str(args[2]): challenge.used=true
		_identity_project_config()
		_identity_event("admin","session_revoke_all",str(args[2]),"ok",{"revoked":count})
		_touch("identity logout-all "+str(args[2])); return _identity_json(true,"ok",{"user":str(args[2]),"revoked":count})
	if action == "login":
		if args.size() != 4 or not state.identity_users.has(str(args[2])): return _identity_json(false,"invalid_credentials")
		var user := str(args[2]); var item := _identity_user(user)
		var supplied_digest := str(args[3]).sha256_text()
		if supplied_digest != str(item.get("password_sha256", IDENTITY_PASSWORD.sha256_text())): _audit("identity login user=%s result=invalid_credentials" % user); _identity_event("user","login",user,"invalid_credentials",{}); return _identity_json(false,"invalid_credentials")
		if not bool(item.get("enabled",false)): _audit("identity login user=%s result=account_disabled" % user); _identity_event("user","login",user,"account_disabled",{}); return _identity_json(false,"account_disabled")
		if bool(item.get("password_temporary", false)) or (item.get("required_actions",[]) is Array and "UPDATE_PASSWORD" in item.required_actions):
			var password_challenge := "challenge-%d" % int(state.identity_sequence)
			state.identity_sequence = int(state.identity_sequence) + 1
			state.identity_challenges.append({"id":password_challenge,"user":user,"used":false,"issued":int(state.identity_sequence),"kind":"password_update"})
			if state.identity_challenges.size()>64: state.identity_challenges.pop_front()
			_audit("identity login user=%s challenge=%s status=401 result=password_update_required" % [user,password_challenge])
			_identity_event("user","login",user,"password_update_required",{"challenge":password_challenge})
			return _identity_json(true,"password_update_required",{"challenge":password_challenge,"user":user,"required_action":"UPDATE_PASSWORD"})
		if bool(state.identity_mfa_required):
			var challenge := "challenge-%d" % int(state.identity_sequence)
			state.identity_sequence = int(state.identity_sequence) + 1
			state.identity_challenges.append({"id":challenge,"user":user,"used":false,"issued":int(state.identity_sequence),"kind":"mfa"})
			if state.identity_challenges.size()>64: state.identity_challenges.pop_front()
			_audit("identity login user=%s challenge=%s status=401 result=mfa_required" % [user,challenge]); _identity_event("user","login",user,"mfa_required",{"challenge":challenge})
			return _identity_json(true,"mfa_required",{"challenge":challenge,"user":user,"enrollment":not bool(item.get("otp_registered",false))})
		return _identity_issue_session(user,false)
	if action == "password-update":
		if args.size() != 4 or not _identity_valid_password(str(args[3])): return _identity_json(false,"usage" if args.size() != 4 else "invalid_password")
		var update_challenge: Dictionary = {}
		for challenge in state.identity_challenges:
			if str(challenge.get("id", "")) == str(args[2]): update_challenge = challenge; break
		if update_challenge.is_empty(): return _identity_json(false,"unknown_challenge")
		if bool(update_challenge.get("used", false)): return _identity_json(false,"challenge_used")
		if str(update_challenge.get("kind", "mfa")) != "password_update": return _identity_json(false,"invalid_challenge")
		var update_user := str(update_challenge.get("user", "")); var update_account: Dictionary = _identity_user(update_user)
		if not bool(update_account.get("enabled", false)): update_challenge.used = true; return _identity_json(false,"account_disabled")
		update_challenge.used = true
		update_account.password_sha256 = str(args[3]).sha256_text(); update_account.password_temporary = false; update_account.credential_revision = int(update_account.get("credential_revision",0)) + 1; update_account.required_actions = []
		_identity_event("user","password_update",update_user,"ok",{"challenge":str(args[2]),"credential_revision":int(update_account.credential_revision)})
		_audit("identity password-update user=%s challenge=%s" % [update_user,args[2]])
		_touch("identity password updated user=" + update_user)
		if bool(state.identity_mfa_required):
			var next_challenge := "challenge-%d" % int(state.identity_sequence)
			state.identity_sequence = int(state.identity_sequence) + 1
			state.identity_challenges.append({"id":next_challenge,"user":update_user,"used":false,"issued":int(state.identity_sequence),"kind":"mfa"})
			if state.identity_challenges.size()>64: state.identity_challenges.pop_front()
			return _identity_json(true,"mfa_required",{"challenge":next_challenge,"user":update_user,"enrollment":not bool(update_account.get("otp_registered",false))})
		return _identity_issue_session(update_user,false)
	if action == "otp":
		if args.size() != 4: return _identity_json(false,"usage")
		for challenge in state.identity_challenges:
			if str(challenge.get("id","")) == str(args[2]):
				if bool(challenge.get("used",false)): return _identity_json(false,"challenge_used")
				if str(challenge.get("kind", "mfa")) != "mfa": return _identity_json(false,"invalid_challenge")
				if not bool(_identity_user(str(challenge.get("user",""))).get("enabled",false)): _audit("identity otp challenge=%s result=account_disabled" % args[2]); _identity_event("user","otp_verify",str(challenge.get("user","")),"account_disabled",{"challenge":str(args[2])}); return _identity_json(false,"account_disabled")
				if str(args[3]) != IDENTITY_OTP: _audit("identity otp challenge=%s result=invalid_otp" % args[2]); _identity_event("user","otp_verify",str(challenge.get("user","")),"invalid_otp",{"challenge":str(args[2])}); return _identity_json(false,"invalid_otp")
				challenge.used = true
				var challenge_user := str(challenge.user)
				# A successful fixture OTP establishes the user's training credential;
				# policy (MFA required) remains a separate state transition.
				if not bool(state.identity_users[challenge_user].otp_registered):
					state.identity_users[challenge_user].otp_registered = true
					_touch("identity otp enrolled user=" + challenge_user)
				_identity_event("user","otp_verify",challenge_user,"ok",{"challenge":str(args[2])})
				return _identity_issue_session(challenge_user,true)
		return _identity_json(false,"unknown_challenge")
	if action == "access":
		if args.size() != 3: return _identity_json(false,"usage")
		if str(args[2]) == "current-latest":
			for i in range(state.identity_sessions.size()-1,-1,-1):
				var latest: Dictionary = state.identity_sessions[i]
				if str(latest.get("user","")) == "current" and not bool(latest.get("revoked",false)):
					_audit("identity access user=current id=%s result=allowed" % latest.id); _identity_event("user","access","current","allowed",{"session":str(latest.id)}); return _identity_json(true,"ok",{"user":"current","mfa":bool(latest.get("mfa",false)),"token":str(latest.id)})
			_identity_event("user","access","current","unknown_token",{}); _audit("identity access user=current result=unknown_token"); return _identity_json(false,"unknown_token")
		for session in state.identity_sessions:
			if str(session.get("id","")) == str(args[2]):
				if bool(session.get("revoked",false)): _audit("identity access id=%s result=revoked" % args[2]); _identity_event("user","access",str(session.get("user","")),"revoked_session",{"session":str(args[2])}); return _identity_json(false,"revoked_session")
				_audit("identity access user=%s id=%s result=allowed" % [session.user,args[2]]); _identity_event("user","access",str(session.user),"allowed",{"session":str(args[2])}); return _identity_json(true,"ok",{"user":str(session.user),"mfa":bool(session.get("mfa",false))})
		_identity_event("user","access","","unknown_token",{"session":str(args[2])}); _audit("identity access id=%s result=unknown_token" % args[2]); return _identity_json(false,"unknown_token")
	if action == "access-current-latest": return _identity_command(["identity","access","current-latest"])
	return _identity_json(false,"unknown_command")

func _identity_issue_session(user: String, mfa: bool) -> String:
	if state.identity_sessions.size() >= 256:
		state.identity_sessions = state.identity_sessions.filter(func(session):return not bool(session.get("revoked",false)))
		if state.identity_sessions.size() >= 256: return _identity_json(false,"session_limit")
	var sequence := int(state.identity_sequence)
	var id := "session-%s-%d" % [user,sequence]; state.identity_sequence=sequence+1
	state.identity_sessions.append({"id":id,"user":user,"client":"business-app","ip":"192.0.2.10","issued":sequence,"revoked":false,"mfa":mfa})
	_identity_project_config()
	_audit("identity session issued user=%s id=%s status=200" % [user,id])
	_identity_event("user","session_issued",user,"ok",{"session":id,"client":"business-app","ip":"192.0.2.10","mfa":mfa})
	return _identity_json(true,"ok",{"token":id,"user":user,"mfa":mfa})

func _identity_add_business_probe(mfa_required: bool) -> void:
	# Authentication is required before this probe can pass; the probe is
	# present from setup, so skipping MFA can never skip the delivery gate.
	for probe in _active_probes():
		if str(probe.get("id", "")) == "current-business": return
	var expectation := "\"code\":200|\"user\":\"current\""+("|\"mfa\":true" if mfa_required else "")
	var probe := {"id":"current-business","label":DISPLAY_COPY.copy("identity_business_probe","Authenticated business access"),"description":"","command":"identity access current-latest","expectation":expectation,"recorded":false,"passed":false,"fresh":false,"result":""}
	if state.get("scenario", {}) is Dictionary and not state.scenario.is_empty(): state.scenario.probes.append(probe)
	else: state.probes.append(probe)

func _clear_probe_measurement(probe: Dictionary) -> void:
	# A v2 contract change must not inherit a PASS from an older command or
	# expectation.  Keep observations intact; only invalidate the measurement.
	for field in ["recorded", "passed", "fresh", "result", "fingerprint", "fingerprint_kind", "initial_result"]:
		probe.erase(field)

func _normalize_transport_probes() -> void:
	if _chapter != 2: return
	var desired: Dictionary = state.get("scenario", {}).get("desired", {}) if state.get("scenario", {}) is Dictionary else {}
	if desired.is_empty(): desired = _legacy_desired()
	for probe in _active_probes():
		if _firewall_model_v2() and str(probe.get("id", "")) == "admin-check":
			var admin_command := "curl https://admin.client.test:8443"
			var admin_expectation := "FIREWALL_DENIED" if str(desired.get("admin_public", "")) == "deny" else "status:200|Management console"
			if str(probe.get("command", "")) != admin_command or str(probe.get("expectation", "")) != admin_expectation: _clear_probe_measurement(probe)
			probe.command = admin_command
			probe.expectation = admin_expectation
			continue
		if _firewall_model_v2() and str(probe.get("id", "")) == "business-check" and str(desired.get("business", "")) == "deny":
			if str(probe.get("expectation", "")) != "FIREWALL_DENIED": _clear_probe_measurement(probe)
			probe.expectation = "FIREWALL_DENIED"
			continue
		if str(probe.get("id", "")) != "admin-check": continue
		# Keep the scenario's desired result as the learning contract.  Only an
		# old HTTP measurement is stale when the saved live transport can no
		# longer have produced it; do not move the goalpost to a broken state.
		var result := str(probe.get("result", ""))
		var transport_broken := str(state.applied.get("dns", "off")) != "on" or str(state.applied.get("tls", "off")) != "on"
		if bool(probe.get("recorded", false)) and transport_broken and result.begins_with("HTTP/"): _clear_probe_measurement(probe)

func _normalize_identity_probes() -> void:
	if _chapter != 3 or int(state.get("identity_model_version",1)) < IDENTITY_MODEL_VERSION: return
	var desired: Dictionary = state.get("scenario",{}).get("desired",{}) if state.get("scenario",{}) is Dictionary else {}
	var former_desired := str(desired.get("former", "disabled"))
	var sessions_desired := str(desired.get("sessions", "revoked"))
	var current_desired := str(desired.get("current", "active"))
	var mfa_desired := str(desired.get("mfa", "on"))
	if current_desired=="active": _identity_add_business_probe(mfa_desired=="on")
	for probe in _active_probes():
		var id := str(probe.get("id",""))
		if id == "former-login":
			var command := "curl https://identity.client.test/former/login?password=" + IDENTITY_PASSWORD
			var expectation := "status:403|account_disabled" if former_desired != "active" else ("status:401|mfa_required" if mfa_desired == "on" else "status:200|\"ok\":true")
			if str(probe.get("command", "")) != command or str(probe.get("expectation", "")) != expectation: _clear_probe_measurement(probe)
			probe.command = command; probe.expectation = expectation; probe.user = "former"; probe.requires_login = _identity_probe_requires_login("former")
		elif id == "former-session":
			var command := "curl https://identity.client.test/former/session"
			var expectation := "status:401" if sessions_desired == "revoked" else "status:200"
			if str(probe.get("command", "")) != command or str(probe.get("expectation", "")) != expectation: _clear_probe_measurement(probe)
			probe.command = command; probe.expectation = expectation
		elif id == "current-mfa":
			var command := "curl https://identity.client.test/current/login?password=" + IDENTITY_PASSWORD
			var expectation := "status:403|account_disabled" if current_desired != "active" else ("status:401|mfa_required" if mfa_desired == "on" else "status:200|\"ok\":true")
			if str(probe.get("command", "")) != command or str(probe.get("expectation", "")) != expectation: _clear_probe_measurement(probe)
			probe.command = command; probe.expectation = expectation; probe.user = "current"; probe.requires_login = _identity_probe_requires_login("current")

func _identity_probe_requires_login(user: String) -> bool:
	var account: Dictionary = _identity_user(user)
	return int(account.get("credential_revision", 0)) > 0 or str(account.get("password_sha256", IDENTITY_PASSWORD.sha256_text())) != IDENTITY_PASSWORD.sha256_text() or bool(account.get("password_temporary", false))

func _active_probes() -> Array:
	var scenario: Dictionary = state.get("scenario", {})
	return scenario.get("probes", []) if not scenario.is_empty() else state.get("probes", _legacy_probes())

func _normalize_command(command: String) -> String:
	var tokens := _tokens(command.strip_edges())
	if not tokens.is_empty() and str(tokens[0]).to_lower() == "sudo": tokens.remove_at(0)
	return JSON.stringify(tokens)

func _identity_actual_probe_user(command: String, output: String) -> String:
	var args := _tokens(command)
	var index := 1 if not args.is_empty() and str(args[0]).to_lower() == "sudo" else 0
	if args.size() > index + 3 and str(args[index]).to_lower() == "identity" and str(args[index + 1]).to_lower() == "login" and args.size() == index + 4:
		var login_user := str(args[index + 2])
		return login_user if login_user in ["former", "current"] and _identity_valid_password(str(args[index + 3])) else ""
	if args.size() > index + 3 and str(args[index]).to_lower() == "identity" and str(args[index + 1]).to_lower() == "password-update" and args.size() == index + 4:
		var update_result: Variant = JSON.parse_string(output)
		if update_result is Dictionary and str(update_result.get("user", "")) in ["former", "current"]: return str(update_result.get("user", ""))
	if args.size() <= index or str(args[index]).to_lower() != "curl": return ""
	var request_url := ""
	for token in args:
		if str(token).begins_with("http://") or str(token).begins_with("https://"): request_url = str(token)
	# _http executes the last URL token; evidence must describe that same request.
	if request_url.is_empty(): return ""
	var parts := _url_parts(request_url); var host := str(parts.get("host", "")); var path := str(parts.get("path", "")); var query := str(parts.get("query", ""))
	if host != "identity.client.test" or path not in ["/former/login", "/current/login"]: return ""
	var password := _query_value(query, "password")
	if not password.is_empty() and password != "<credential>" and _identity_valid_password(password): return "former" if path.begins_with("/former/") else "current"
	return ""

func _local_file_probe_args(probe: Dictionary) -> Array[String]:
	var args := _tokens(str(probe.get("command", "")).strip_edges())
	if not args.is_empty() and args[0] == "sudo": args.remove_at(0)
	if args.size() == 2 and args[0] == "sha256sum": return args
	var empty: Array[String] = []
	return empty

func _local_file_probe_fingerprint(probe: Dictionary) -> String:
	var args := _local_file_probe_args(probe)
	if args.is_empty(): return ""
	var path := _path(args[1]); var exists: bool = state.fs.has(path)
	return JSON.stringify({"kind":"local-file-v1", "host":state.host, "chapter":_chapter,
		"command":str(probe.get("command", "")), "expectation":str(probe.get("expectation", "")),
		"path":path, "exists":exists, "sha256":str(state.fs[path]).sha256_text() if exists else ""}, "", true).sha256_text()

func _probe_fingerprint(probe: Dictionary) -> String:
	if probe.has("fingerprint_kind"):
		if str(probe.fingerprint_kind) != "local-file-v1": return ""
		return _local_file_probe_fingerprint(probe)
	# Unmarked legacy evidence remains conservative; rendering never upgrades it.
	return _fingerprint()

func _probe_is_fresh(probe: Dictionary) -> bool:
	var saved := str(probe.get("fingerprint", ""))
	return bool(probe.get("recorded", false)) and not saved.is_empty() and saved == _probe_fingerprint(probe)

func _stamp_probe_fingerprint(probe: Dictionary, output: String, whole_vm: String) -> void:
	probe.erase("fingerprint_kind")
	probe.fingerprint = whole_vm
	var args := _local_file_probe_args(probe)
	if args.is_empty() or not bool(state.connected): return
	var path := _path(args[1])
	var actual := str(state.fs[path]).sha256_text() + "  " + args[1] if state.fs.has(path) else "sha256sum: file missing"
	if output != actual: return
	# Capture dependencies only after a real local response, including absence.
	# Service/ACL checks keep their own whole-VM measurement requirement.
	probe.fingerprint_kind = "local-file-v1"
	probe.fingerprint = _local_file_probe_fingerprint(probe)

func _record_command(command: String, output: String, before: String, after: String) -> void:
	if not state.has("observations") or not state.observations is Array: state.observations = []
	var observation: Dictionary = {"command":_identity_redact_command(command),"output":output,"before":before,"fingerprint":after,"changed":before != after}
	state.observations.append(observation)
	if state.observations.size() > 120: state.observations.pop_front()
	var normalized := _normalize_command(command)
	var matched_probe: String = ""
	var matched_expectation := ""
	var matched_passed := false
	for probe in _active_probes():
		if _normalize_command(str(probe.get("command", ""))) == normalized:
			matched_probe = str(probe.get("id", ""))
			if not bool(probe.get("recorded", false)): probe.initial_result = output
			probe.result = output; probe.recorded = true; _stamp_probe_fingerprint(probe, output, after); probe.fresh = true; probe.passed = _probe_passes(output, str(probe.get("expectation", "")))
			matched_expectation = str(probe.get("expectation", "")); matched_passed = bool(probe.passed)
	# A real credential-bearing login or password-update command is evidence for
	# the corresponding user probe even though its secret-bearing command cannot
	# equal the public fixture command. The output remains authoritative.
	var identity_user := _identity_actual_probe_user(command, output) if _chapter == 3 else ""
	if matched_probe.is_empty() and not identity_user.is_empty():
		for probe in _active_probes():
			var probe_id := str(probe.get("id", ""))
			var probe_user := str(probe.get("user", ""))
			if probe_user.is_empty(): probe_user = "current" if probe_id == "current-mfa" else ("former" if probe_id == "former-login" else "")
			if not identity_user.is_empty() and probe_user == identity_user and probe_id in ["current-mfa", "former-login"]:
				matched_probe = probe_id
				if not bool(probe.get("recorded", false)): probe.initial_result = output
				probe.result = output; probe.recorded = true; _stamp_probe_fingerprint(probe, output, after); probe.fresh = true; probe.passed = _probe_passes(output, str(probe.get("expectation", "")))
				matched_expectation = str(probe.get("expectation", "")); matched_passed = bool(probe.passed)
				break
	if not matched_probe.is_empty():
		observation["probe_id"] = matched_probe
		observation["probe_passed"] = matched_passed
		observation["probe_expectation"] = matched_expectation
	if before != after:
		for probe in _active_probes():
			if str(probe.get("id", "")) != matched_probe: probe.fresh = _probe_is_fresh(probe)

func run(command: String) -> String:
	var before := _fingerprint()
	var output := _run_internal(command)
	if _is_restic_dry_run(command): return output
	_record_command(command, output, before, _fingerprint())
	return output

func _is_restic_dry_run(command: String) -> bool:
	var args := _tokens(command.strip_edges())
	if args.size() < 2: return false
	if args[0] == "sudo": args.remove_at(0)
	return not args.is_empty() and args[0] == "restic" and "restore" in args and "--dry-run" in args

func _run_internal(command: String) -> String:
	var args := _tokens(command.strip_edges())
	if args.is_empty(): return ""
	if args[0] == "sudo": args.remove_at(0)
	if args.is_empty(): return "usage: sudo <command>"
	var cmd: String = args[0]
	if cmd in ["help", "man"]: return _reference()
	if cmd == "clear": return ""
	if cmd == "whoami": return "admin" if state.connected else str(_identity.player)
	if cmd == "hostname": return state.host if state.connected else "workstation"
	if cmd == "ssh":
		if args.size() < 2: return "usage: ssh client"
		var dest: String = args[1].get_slice("@", args[1].get_slice_count("@") - 1)
		if dest not in ["client", str(state.host)]: return "ssh: Could not resolve hostname " + dest
		state.connected = true; state.cwd = OPERATOR_HOME
		return "Authenticated as admin on %s\n設定: %s\nサービス: %s\ncat README.txt / help でコマンドを確認できます。" % [state.host, state.config_path, state.service]
	if cmd == "exit":
		state.connected = false
		return "Connection closed. %s / %s" % [_identity.player, _identity.company]
	if cmd == "reset-lab":
		if args.size() < 2 or args[1] != "--confirm": return "初期状態に戻す場合: reset-lab --confirm"
		var clean_scenario: Dictionary = state.get("scenario",{}).duplicate(true)
		for probe in clean_scenario.get("probes",[]):
			for field in ["recorded","passed","fresh","result","fingerprint","fingerprint_kind","initial_result"]: probe.erase(field)
		setup(_chapter,{},clean_scenario); state.connected = true; _touch("lab restored from clean image")
		return "Guest image restored. 顧客環境を作業開始時に戻しました。"
	if not state.connected: return "Not connected. ssh client で顧客端末に接続してください。"
	if cmd == "edr": return _edr_command(args)
	if cmd == "identity": return _identity_command(args)
	if cmd == "portal": return PortalStorage.command(self, args)
	match cmd:
		"pwd": return state.cwd
		"ls":
			var path: String = args[-1] if args.size() > 1 and not args[-1].begins_with("-") else "."
			if _path(path) not in state.dirs: return "ls: directory not found: " + path
			return "\n".join(list_files(path))
		"cd":
			var p := _path(args[1] if args.size() > 1 else OPERATOR_HOME)
			if p not in state.dirs: return "cd: no such directory: " + p
			state.cwd = p; return ""
		"cat":
			if args.size() < 2: return "usage: cat <file>"
			return read_file(args[1])
		"edit", "nano": return "エディタで開く: " + str(args[1] if args.size() > 1 else state.config_path)
		"mkdir":
			if args.size() < 2: return "usage: mkdir [-p] <directory>"
			var p := _path(args[-1])
			if p in state.dirs or state.fs.has(p): return "mkdir: already exists"
			if "-p" in args:
				var current := ""
				for part in p.split("/", false):
					current += "/" + part
					if current not in state.dirs: state.dirs.append(current)
			elif p.get_base_dir() in state.dirs: state.dirs.append(p)
			else: return "mkdir: parent directory missing"
			_touch("mkdir " + p); return ""
		"cp":
			if args.size() != 3: return "usage: cp <source-file> <destination>"
			var source := _path(args[1]); var destination := _path(args[2])
			if not state.fs.has(source): return "cp: source file missing"
			if destination in state.dirs: destination += "/" + source.get_file()
			return "" if write_file(destination, state.fs[source]) else "cp: destination directory missing"
		"rm":
			if args.size() != 2: return "usage: rm <file>"
			var p := _path(args[1])
			if not state.fs.has(p): return "rm: file missing"
			state.fs.erase(p); _touch("rm " + p); return ""
		"diff":
			if args.size() != 3: return "usage: diff <file-a> <file-b>"
			if not state.fs.has(_path(args[1])) or not state.fs.has(_path(args[2])): return "diff: file missing"
			return "identical" if read_file(args[1]) == read_file(args[2]) else "files differ"
		"sha256sum":
			if args.size() != 2 or not state.fs.has(_path(args[1])): return "sha256sum: file missing"
			return read_file(args[1]).sha256_text() + "  " + args[1]
		"testparm":
			if _chapter != 0: return "testparm: command applies to Samba host only"
			var test_path: String = str(state.config_path)
			if args.size() > 1 and args[1] == "-s" and args.size() > 2: test_path = _path(args[2])
			elif args.size() > 1 and args[1] != "-s": test_path = _path(args[1])
			if not state.fs.has(test_path): return "testparm: cannot open %s" % test_path
			var checked := Samba.parse(str(state.fs[test_path]))
			return "Load smb config files from %s\nERROR: %s" % [test_path, checked.error] if not str(checked.error).is_empty() else "Load smb config files from %s\nLoaded services file OK.\nWARNING: exercise subset only." % test_path
		"systemctl": return _systemctl(args)
		"journalctl": return "\n".join(state.events) + "\n" + (str(state.fs.get("/var/log/evidence.log", "evidence.log: missing")) if _chapter == 4 else "")
		"dig":
			return _firewall_dig(args) if _firewall_model_v2() else (";; status: NOERROR\nintranet.client.test. 60 IN A 192.0.2.20" if state.active and state.applied.get("dns", "off") == "on" else ";; status: SERVFAIL\n;; no answer")
		"curl": return _http(args)
		"nc": return _firewall_nc(args) if _firewall_model_v2() else "nc: command not found"
		"smbclient": return _smb(args)
		"restic": return _restic(args)
		"ss":
			if _firewall_model_v2():
				var business_socket := FirewallPolicy.evaluate(state.applied, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.BUSINESS_ADDRESS, "tcp", 40000, 443)
				var admin_socket := FirewallPolicy.evaluate(state.applied, "wan", FirewallPolicy.EXTERNAL_ADDRESS, FirewallPolicy.ADMIN_ADDRESS, "tcp", 40000, 8443)
				return "443/tcp business " + ("LISTEN" if business_socket.action == "pass" else "CLOSED") + "\n8443/tcp public-admin " + ("LISTEN" if admin_socket.action == "pass" else "CLOSED")
			return "443/tcp business " + ("LISTEN" if state.applied.get("business", "deny") == "allow" else "CLOSED") + "\n8443/tcp public-admin " + ("LISTEN" if state.applied.get("admin_public", "deny") == "allow" else "CLOSED")
	return "%s: command not found. help で利用可能なコマンドを確認してください。" % cmd

func _probe_passes(output: String, expectation: String) -> bool:
	var parts := expectation.split("|", false)
	for part in parts:
		if part.begins_with("status:"):
			var expected_status := part.trim_prefix("status:")
			var status_matches := output.begins_with("HTTP/1.1 "+expected_status)
			if not status_matches and not output.begins_with("HTTP/"):
				var json := JSON.new()
				if json.parse(output) == OK:
					var parsed: Variant = json.data
					status_matches = parsed is Dictionary and int(parsed.get("code", -1)) == int(expected_status)
			if not status_matches: return false
		elif part == "DENIED":
			# Samba reports an unavailable share as BAD_NETWORK_NAME before it can
			# evaluate permissions; both are real denial outcomes for this probe.
			if not (output.contains("NT_STATUS_ACCESS_DENIED") or output.contains("NT_STATUS_BAD_NETWORK_NAME")): return false
		elif not output.contains(part): return false
	return true

func probes() -> Array:
	var result: Array = []
	for probe in _active_probes():
		var item: Dictionary = probe.duplicate(true)
		if _chapter == 3 and int(state.get("identity_model_version",1)) >= IDENTITY_MODEL_VERSION:
			var probe_id := str(item.get("id", "")); var probe_user := "current" if probe_id == "current-mfa" else ("former" if probe_id == "former-login" else "")
			if not probe_user.is_empty(): item.user = probe_user; item.requires_login = _identity_probe_requires_login(probe_user)
		item.result = str(item.get("result","")); item.recorded = bool(item.get("recorded",false))
		item.fingerprint = str(item.get("fingerprint","")); item.fresh = _probe_is_fresh(item)
		item.passed = bool(item.get("passed",false)) and item.fresh
		result.append(item)
	return result

func execute_probe(id: String) -> String:
	for probe in _active_probes():
		if str(probe.get("id","")) != id: continue
		return run(str(probe.command))
	return "probe not found: "+id

func _parse_config(text: String) -> Dictionary:
	if _chapter == 0 and int(state.get("samba_model_version", 1)) >= 2: return Samba.parse(text)
	if _chapter == 2 and int(state.get("firewall_model_version", 1)) >= FIREWALL_MODEL_VERSION: return FirewallPolicy.parse_config(text)
	var values := {}
	var schema: Dictionary = SCHEMAS[_chapter]
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"): continue
		var parts := line.split("=", true, 1)
		if parts.size() != 2: return {"error":"Expected key=value: " + line,"values":{}}
		var key := parts[0].strip_edges(); var value := parts[1].strip_edges()
		if not schema.has(key): return {"error":"Unknown key: " + key,"values":{}}
		if value not in schema[key]: return {"error":"Invalid %s=%s; allowed: %s" % [key, value, ", ".join(schema[key])],"values":{}}
		values[key] = value
	for key in schema:
		if not values.has(key): return {"error":"Missing key: " + key,"values":{}}
	return {"error":"","values":values}

func _systemctl(args: Array[String]) -> String:
	if args.size() != 3: return "usage: systemctl status|restart " + str(state.service)
	if args[2] != state.service: return "Unit %s.service not found." % args[2]
	if args[1] == "status":
		return "%s.service - %s\nActive: %s\n%s" % [state.service, state.host, "active (running)" if state.active else "failed", state.error]
	if args[1] != "restart": return "Supported actions: status, restart"
	var config: Dictionary = _parse_config(str(state.fs.get(state.config_path, "")))
	if not config.error.is_empty():
		state.active = false; state.error = config.error; _touch("service failed: " + config.error)
		return "Job failed: " + config.error + "\n設定ファイルを修正し、サービスを再起動してください。"
	var previous_applied: Dictionary = state.applied.duplicate(true)
	state.applied = config.values.duplicate(true); state.active = true; state.error = ""
	if _firewall_model_v2(): state.firewall_pending = state.applied.duplicate(true); state.firewall_pending_dirty = false
	state.dirty = false
	if _chapter == 3 and int(state.get("identity_model_version",1)) >= IDENTITY_MODEL_VERSION:
		_identity_ensure_state(); _identity_sync_config()
	state.dirty = false
	if _chapter == 4 and (state.applied.logs == "erase" or state.applied.reset == "wipe"):
		state.fs.erase("/var/log/evidence.log")
	if _portal_model_v2(): PortalStorage.sync_from_config(self, previous_applied)
	_touch("restarted " + str(state.service))
	return "%s.service: active (running)\nConfiguration loaded from %s" % [state.service, state.config_path]

func _permission(role: String, write: bool) -> bool:
	if not state.active: return false
	var mode := str(state.applied.get(role, "none"))
	if _chapter == 0 and int(state.get("samba_model_version",1)) >= 2:
		if str(state.applied.get("path","")).simplify_path() not in state.dirs: return false
	return mode == "write" if write else mode in ["read", "write"]

func _portal_model_v2() -> bool:
	return _chapter == 5 and int(state.get("portal_model_version", 1)) >= 2

func _linked_identity_security_snapshot() -> Dictionary:
	var sessions: Array = []
	for item in linked_identity_sessions():
		if item is Dictionary:
			sessions.append({"id":str(item.get("id", "")),"user":str(item.get("user", "")),"revoked":bool(item.get("revoked", false)),"mfa":bool(item.get("mfa", false))})
	sessions.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	return {"active":bool(_linked_identity_provider.get("active", false)),"realm":str(_linked_identity_provider.get("realm", "")),"users":_linked_identity_provider.get("users", {}).duplicate(true) if _linked_identity_provider.get("users", {}) is Dictionary else {},"sessions":sessions}

func _linked_identity_token(token: String) -> Dictionary:
	if not has_linked_identity(): return {}
	if not bool(_linked_identity_provider.get("active", false)): return {"error":"identity_provider_unavailable","status":503}
	if token.is_empty() or token.contains("\r") or token.contains("\n"): return {"error":"linked_session_required","status":401}
	for session in linked_identity_sessions():
		if not session is Dictionary or str(session.get("id", "")) != token: continue
		var session_info := {"user":str(session.get("user", "")),"mfa":bool(session.get("mfa", false)),"session":token,"realm":str(_linked_identity_provider.get("realm", ""))}
		if bool(session.get("revoked", false)):
			session_info.error = "linked_session_revoked"
			session_info.status = 401
			return session_info
		return session_info
	return {"error":"linked_session_unknown","status":401}

func _safe_linked_token(token: String) -> bool:
	if token.is_empty() or token.length() > 128 or token.contains("\r") or token.contains("\n"): return false
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
	for ch in token:
		if allowed.find(ch) < 0: return false
	return true

func portal_snapshot() -> Dictionary:
	return PortalStorage.snapshot(self)

func portal_storage_read(path: String) -> String:
	if has_linked_branch_storage() and not linked_business_provider_available(): return ""
	var fs := _portal_storage_fs()
	return str(fs.get(path, ""))

func portal_request(role: String, method: String, age: String, token: String, content: String = "") -> String:
	if not _portal_model_v2(): return "HTTP/1.1 426 Upgrade Required\nlegacy portal model"
	if not state.connected: return "HTTP/1.1 401 Unauthorized\nnot connected"
	if not state.active: return "HTTP/1.1 503 Service Unavailable\nservice unavailable"
	if role not in ["staff", "partner", "public"] or method.to_upper() not in ["GET", "PUT"] or age not in ["", "current", "week-old", "month-old"]:
		return "HTTP/1.1 400 Bad Request\ninvalid portal request"
	if token not in ["", "staff-session", "partner-session", "partner-mfa-session"] and not (has_linked_identity() and _safe_linked_token(token)):
		return "HTTP/1.1 400 Bad Request\ninvalid token"
	var upper_method := method.to_upper()
	var query := "" if age.is_empty() else "?link=" + age
	var request_args: Array = ["curl", "-X", upper_method, "https://portal.client.test/" + role + query]
	if not token.is_empty(): request_args.append_array(["-H", "Authorization: Bearer " + token])
	if upper_method == "PUT": request_args.append_array(["--data-raw", content])
	var before := _fingerprint()
	var response := _portal_response({"scheme":"https","host":"portal.client.test","path":"/" + role,"query":("link=" + age if not age.is_empty() else "")}, upper_method, request_args)
	var observed := response
	if "\n\n" in observed: observed = observed.get_slice("\n\n", 0) + "\n\n[content omitted]"
	_record_command("portal_request " + role + " " + upper_method + " " + age, observed, before, _fingerprint())
	return response

func _smb(args: Array[String]) -> String:
	if _chapter != 0: return "smbclient: SMB service unavailable on this host"
	if not state.active: return "NT_STATUS_CONNECTION_REFUSED: service is not running"
	var role := "guest"; var operation := "ls"; var target := ""
	for i in args.size():
		if str(args[i]).begins_with("//"): target=str(args[i]).trim_prefix("//")
		if args[i] == "-U" and i+1 < args.size(): role=args[i+1].get_slice("%",0)
		if args[i] == "-c" and i+1 < args.size(): operation=args[i+1]
	if target.is_empty(): return "usage: smbclient //<host>/<share> -U <user> -c <operation>"
	var names := target.split("/",false)
	if names.size()!=2 or names[0].to_lower() not in ["client","files01.client.test"]: return "NT_STATUS_BAD_NETWORK_NAME"
	var v2 := int(state.get("samba_model_version",1)) >= 2
	var share_settings: Dictionary=state.applied.get("shares",{}).get(names[1].to_lower(),{})
	if (v2 and share_settings.is_empty()) or (not v2 and names[1]!="share"): return "NT_STATUS_BAD_NETWORK_NAME"
	if not bool(share_settings.get("available",true)): return "NT_STATUS_BAD_NETWORK_NAME"
	var share_path := str(share_settings.get("path","/srv/share")).simplify_path()
	if share_path not in state.dirs: return "NT_STATUS_BAD_NETWORK_NAME"
	if role in ["guest","nobody"]: role="guest"
	elif role!="staff":
		if v2 and str(state.applied.get("map_to_guest","Never")).to_lower()=="bad user": role="guest"
		else: return "NT_STATUS_LOGON_FAILURE"
	var op := _tokens(operation)
	if op.is_empty() or op[0] not in ["ls","put","get"]: return "NT_STATUS_INVALID_PARAMETER: unsupported smb operation"
	var writing := op[0]=="put"
	var mode := Samba._mode(share_settings,"nobody" if role=="guest" else "staff") if v2 else str(state.applied.get(role,"none"))
	if (writing and mode!="write") or (not writing and mode not in ["read","write"]): return "NT_STATUS_ACCESS_DENIED"
	if op[0] in ["put","get"]:
		if op.size()<2 or op.size()>3: return "usage: -c 'put <local-file> [remote-file]' or -c 'get <remote-file> [local-file]'"
		var remote_name := (op[2] if op.size()==3 else op[1].get_file()) if writing else op[1]
		if remote_name.begins_with("/") or ".." in remote_name.split("/"): return "NT_STATUS_ACCESS_DENIED"
		var remote := share_path.path_join(remote_name).simplify_path()
		if remote.get_base_dir() not in state.dirs: return "NT_STATUS_OBJECT_PATH_NOT_FOUND"
		if writing:
			var source := _path(op[1])
			if not state.fs.has(source): return "put: local file missing"
			state.fs[remote]=state.fs[source]; _touch("SMB upload by "+role)
			return "putting file "+remote_name+": OK"
		if not state.fs.has(remote): return "NT_STATUS_OBJECT_NAME_NOT_FOUND"
		var destination := op[2] if op.size()==3 else OPERATOR_HOME.path_join(op[1].get_file())
		if not write_file(destination,str(state.fs[remote])): return "NT_STATUS_ACCESS_DENIED"
		return "getting file "+remote_name+": OK"
	if op.size()!=1: return "NT_STATUS_INVALID_PARAMETER: this exercise supports ls without a mask"
	var listing: Array[String]=[]
	for path in state.fs:
		if str(path).get_base_dir()==share_path: listing.append(str(path).get_file())
	return "\n".join(listing) if not listing.is_empty() else "0 files"

func _url_parts(url: String) -> Dictionary:
	var scheme := url.get_slice("://", 0) if "://" in url else "http"
	var rest := url.get_slice("://", 1) if "://" in url else url
	var authority := rest.get_slice("/", 0).get_slice("?", 0)
	var host := authority
	var port := 443 if scheme.to_lower() == "https" else 80
	if ":" in authority:
		host = authority.get_slice(":", 0)
		var port_text := authority.get_slice(":", 1)
		port = int(port_text) if port_text.is_valid_int() else -1
	var path := "/" + rest.trim_prefix(authority).trim_prefix("/").get_slice("?", 0) if "/" in rest else "/"
	var query := rest.get_slice("?", 1) if "?" in rest else ""
	return {"scheme":scheme,"host":host.to_lower(),"port":port,"path":path,"query":query}

func _query_value(query: String, key: String) -> String:
	for pair in query.split("&", false):
		if pair.get_slice("=", 0) == key: return pair.get_slice("=", 1)
	return ""

func _header_value(args: Array, name: String) -> String:
	for i in args.size():
		if str(args[i]).to_lower() == "-h" and i + 1 < args.size():
			var header := str(args[i + 1])
			if header.to_lower().begins_with(name.to_lower() + ":"): return header.get_slice(":", 1).strip_edges()
	return ""

func _firewall_action_for(host: String, scheme: String, port: int, protocol: String = "tcp") -> Dictionary:
	var destination := FirewallPolicy.BUSINESS_ADDRESS
	var interface_name := "lan"
	var source := FirewallPolicy.STAFF_ADDRESS
	if host == "admin.client.test":
		destination = FirewallPolicy.ADMIN_ADDRESS; interface_name = "wan"; source = FirewallPolicy.EXTERNAL_ADDRESS
	var decision := FirewallPolicy.evaluate(state.applied, interface_name, source, destination, protocol, 40000, port)
	decision.interface = interface_name; decision.source = source; decision.destination = destination; decision.destination_port = port
	return decision

func _firewall_record_traffic(decision: Dictionary, interface_name: String, source: String, destination: String, protocol: String, source_port: int, destination_port: int) -> void:
	if not bool(decision.get("logged", false)) and str(decision.get("rule_id", "")) != "default": return
	var item := {"interface":interface_name,"source":source,"destination":destination,"protocol":protocol,"source_port":source_port,"destination_port":destination_port,"action":str(decision.get("action", "block")),"rule_id":str(decision.get("rule_id", "default"))}
	state.firewall_logs.append(item)
	if state.firewall_logs.size() > 30: state.firewall_logs.pop_front()

func _firewall_denial(decision: Dictionary, tool: String) -> String:
	var action := str(decision.get("action", "block")); var token := "FIREWALL_DENIED action=" + action + " rule=" + str(decision.get("rule_id", "default"))
	if tool == "curl": return "curl: (28) Operation timed out " + token if action == "block" else "curl: (7) Connection refused " + token
	if tool == "nc": return "nc: connection timed out " + token if action == "block" else "nc: connection refused " + token
	return token

func _firewall_dig(args: Array) -> String:
	var query := "intranet.client.test"
	var tcp := false
	for i in range(1, args.size()):
		var token := str(args[i])
		if token == "+tcp": tcp = true
		elif not token.begins_with("+") and not token.begins_with("-"): query = token
	if query != "intranet.client.test": return ";; status: NXDOMAIN\n;; no answer"
	if not state.active or str(state.applied.get("dns", "off")) != "on": return ";; status: SERVFAIL\n;; no answer"
	var protocol := "tcp" if tcp else "udp"
	var decision := FirewallPolicy.evaluate(state.applied, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.LAN_ADDRESS, protocol, 40000, 53)
	_firewall_record_traffic(decision, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.LAN_ADDRESS, protocol, 40000, 53)
	if str(decision.get("action", "block")) != "pass": return ";; status: SERVFAIL\n" + _firewall_denial(decision, "dig")
	return ";; status: NOERROR\nintranet.client.test. 60 IN A 192.0.2.20"

func _firewall_nc(args: Array) -> String:
	if not state.active: return "nc: connection refused"
	var udp := false; var positional: Array[String] = []
	for i in range(1, args.size()):
		var token := str(args[i])
		if token == "-u" or token == "-uv" or token == "-vu": udp = true
		elif token.begins_with("-"): continue
		else: positional.append(token)
	if positional.size() != 2 or not str(positional[1]).is_valid_int(): return "nc: usage nc [-u] [-zv] <host> <port>"
	var host := positional[0]
	if host not in ["intranet.client.test", "admin.client.test"]: return "nc: could not resolve host"
	if str(state.applied.get("dns", "off")) != "on": return "nc: could not resolve host"
	var dns_decision := FirewallPolicy.evaluate(state.applied, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.LAN_ADDRESS, "udp", 40000, 53)
	_firewall_record_traffic(dns_decision, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.LAN_ADDRESS, "udp", 40000, 53)
	if str(dns_decision.get("action", "block")) != "pass": return "nc: could not resolve host " + _firewall_denial(dns_decision, "nc")
	var port := int(positional[1]); var transport := "udp" if udp else "tcp"
	if (host == "intranet.client.test" and port not in [80,443]) or (host == "admin.client.test" and port != 8443): return "nc: connection refused"
	var decision := _firewall_action_for(host, "", port, transport)
	_firewall_record_traffic(decision, "lan" if host == "intranet.client.test" else "wan", FirewallPolicy.STAFF_ADDRESS if host == "intranet.client.test" else FirewallPolicy.EXTERNAL_ADDRESS, FirewallPolicy.BUSINESS_ADDRESS if host == "intranet.client.test" else FirewallPolicy.ADMIN_ADDRESS, transport, 40000, port)
	if str(decision.get("action", "block")) != "pass": return _firewall_denial(decision, "nc")
	return "Connection to %s %d port %s succeeded" % [host,port,transport]

func _portal_response(parts: Dictionary, method: String, args: Array) -> String:
	if str(parts.scheme).to_lower() == "https" and str(state.applied.get("tls", "off")) != "on": return "curl: (35) TLS handshake failed"
	var response := _portal_access(parts,method,args)
	if str(state.applied.get("audit","off")) == "on":
		var status := int(response.get_slice("\n",0).get_slice(" ",1))
		var authorization := _header_value(args,"authorization")
		var token := authorization.get_slice(" ",1) if authorization.to_lower().begins_with("bearer ") else ""
		var linked_audit := _linked_identity_token(token) if has_linked_identity() and not token.is_empty() else {}
		var identity := str(linked_audit.get("user", "")) if linked_audit.has("user") else ("staff" if token == "staff-session" else ("partner" if token in ["partner-session","partner-mfa-session"] else "anonymous"))
		var outcome := "allowed" if status == 200 else ("expired" if status == 410 else "denied")
		var session_suffix := " session=" + token if has_linked_identity() and linked_audit.has("session") else ""
		var realm_suffix := " realm=" + str(linked_audit.get("realm", "")) if has_linked_identity() and linked_audit.has("realm") else ""
		_audit("portal %s path=%s identity=%s link=%s status=%d result=%s%s%s" % [method,parts.path,identity,_query_value(str(parts.query),"link"),status,outcome,session_suffix,realm_suffix])
	return response

func _portal_access(parts: Dictionary, method: String, args: Array) -> String:
	if _portal_model_v2(): return _portal_access_v2(parts, method, args)
	var path := str(parts.path)
	if path not in ["/staff", "/partner", "/public"]: return "HTTP/1.1 404 Not Found\nunknown portal route"
	if method not in ["GET", "PUT"]: return "HTTP/1.1 405 Method Not Allowed"
	var role := path.trim_prefix("/")
	var link := _query_value(str(parts.query), "link")
	var age := -1
	if link == "current": age = 0
	elif link == "week-old": age = 8
	elif link == "month-old": age = 31
	elif not link.is_empty(): return "HTTP/1.1 404 Not Found\nunknown link"
	var expiry := str(state.applied.get("expires", "unlimited"))
	if age >= 0 and expiry != "unlimited" and age > (7 if expiry == "7d" else 30):
		return "HTTP/1.1 410 Gone\nshared link expired"
	var auth := _header_value(args, "authorization")
	var token := auth.get_slice(" ", 1) if auth.to_lower().begins_with("bearer ") else ""
	var identity := ""; var mfa_verified := false
	if token == "staff-session": identity = "staff"; mfa_verified = true
	elif token == "partner-session": identity = "partner"
	elif token == "partner-mfa-session": identity = "partner"; mfa_verified = true
	if role == "staff" and identity != "staff": return "HTTP/1.1 403 Forbidden\nrole=staff"
	if role == "partner" and identity not in ["staff", "partner"]: return "HTTP/1.1 401 Unauthorized\nlogin required"
	if role == "public" and str(state.applied.get("public", "none")) == "none": return "HTTP/1.1 403 Forbidden\nrole=public"
	if str(state.applied.get("mfa", "off")) == "on" and (role in ["partner", "public"] or not identity.is_empty()) and not mfa_verified: return "HTTP/1.1 401 Unauthorized\nmfa_required"
	if not _permission(role, method == "PUT") or (method == "PUT" and role == "public"): return "HTTP/1.1 403 Forbidden\nrole=" + role
	return "HTTP/1.1 200 OK\nrole=%s\nexpires=%s\nMFA=%s\ntransport=%s\naudit=%s\nDocument: partner-order.csv" % [role, expiry, state.applied.mfa, "TLS" if parts.scheme == "https" else "HTTP", state.applied.audit]

func _portal_upload(args: Array) -> Dictionary:
	var flags := ["-d", "--data", "--data-raw", "--data-binary", "-T", "--upload-file"]
	for i in args.size():
		if str(args[i]) not in flags: continue
		if i + 1 >= args.size(): return {"present":true,"ok":false,"error":"upload_data_missing"}
		var raw := str(args[i + 1])
		var from_file := (raw.begins_with("@") and str(args[i]) != "--data-raw") or str(args[i]) in ["-T", "--upload-file"]
		if from_file:
			var source := _path(raw.substr(1) if raw.begins_with("@") else raw)
			if not state.fs.has(source): return {"present":true,"ok":false,"error":"upload_source_missing"}
			return {"present":true,"ok":true,"content":str(state.fs[source])}
		return {"present":true,"ok":true,"content":raw}
	return {"present":false,"ok":true,"content":""}

func _portal_v2_response(role: String, expiry: String, parts: Dictionary, content: String) -> String:
	return "HTTP/1.1 200 OK\nrole=%s\nexpires=%s\nMFA=%s\ntransport=%s\naudit=%s\nDocument: %s\nSHA-256: %s\n\n%s" % [role, expiry, state.applied.mfa, "TLS" if str(parts.scheme).to_lower() == "https" else "HTTP", state.applied.audit, PortalStorage.PRIMARY_PATH.get_file(), content.sha256_text(), content]

func _portal_access_v2(parts: Dictionary, method: String, args: Array) -> String:
	var path := str(parts.path)
	if path not in ["/staff", "/partner", "/public"]: return "HTTP/1.1 404 Not Found\nunknown portal route"
	if method not in ["GET", "PUT"]: return "HTTP/1.1 405 Method Not Allowed"
	var requested_file := _query_value(str(parts.query), "file")
	if not requested_file.is_empty() and requested_file != PortalStorage.PRIMARY_PATH.get_file(): return "HTTP/1.1 404 Not Found\nunknown file"
	var role := path.trim_prefix("/")
	var link := _query_value(str(parts.query), "link")
	var age := -1
	if link == "current": age = 0
	elif link == "week-old": age = 8
	elif link == "month-old": age = 31
	elif not link.is_empty(): return "HTTP/1.1 404 Not Found\nunknown link"
	var share := PortalStorage.share_for(self, role)
	if share.is_empty(): return "HTTP/1.1 403 Forbidden\nrole=" + role
	var expiry := str(share.get("expires", "unlimited"))
	if age >= 0 and expiry != "unlimited" and age > (7 if expiry == "7d" else 30): return "HTTP/1.1 410 Gone\nshared link expired"
	if role == "public" and int(share.get("permissions", 0)) <= 0: return "HTTP/1.1 403 Forbidden\nrole=public"
	var auth := _header_value(args, "authorization")
	var token := auth.get_slice(" ", 1) if auth.to_lower().begins_with("bearer ") else ""
	var identity := ""; var mfa_verified := false
	if has_linked_identity() and token == "staff-session":
		var fixed_linked := _linked_identity_token(token)
		var fixed_status := int(fixed_linked.get("status", 401))
		return "HTTP/1.1 %d %s\n%s" % [fixed_status, "Service Unavailable" if fixed_status == 503 else "Unauthorized", str(fixed_linked.get("error", "linked_session_unknown"))]
	if has_linked_identity() and role == "staff":
		var linked := _linked_identity_token(token)
		if linked.has("error"):
			return "HTTP/1.1 %d %s\n%s" % [int(linked.get("status", 401)), "Service Unavailable" if int(linked.get("status", 401)) == 503 else "Unauthorized", str(linked.get("error", "linked authentication failed"))]
		identity = str(linked.get("user", "")); mfa_verified = bool(linked.get("mfa", false))
	elif token == "staff-session": identity = "staff"; mfa_verified = true
	elif token == "partner-session": identity = "partner"
	elif token == "partner-mfa-session": identity = "partner"; mfa_verified = true
	if role == "staff" and identity not in ["staff", "current", "former"]: return "HTTP/1.1 403 Forbidden\nrole=staff"
	if role == "partner" and identity not in ["staff", "partner"]: return "HTTP/1.1 401 Unauthorized\nlogin required"
	if str(state.applied.get("mfa", "off")) == "on" and (role in ["partner", "public"] or not identity.is_empty()) and not mfa_verified: return "HTTP/1.1 401 Unauthorized\nmfa_required"
	var permissions := int(share.get("permissions", 0))
	if permissions < (3 if method == "PUT" else 1) or (method == "PUT" and role == "public"): return "HTTP/1.1 403 Forbidden\nrole=" + role
	if has_linked_branch_storage() and not linked_business_provider_available():
		var provider_error := linked_business_provider_error()
		return "HTTP/1.1 %d %s\n%s" % [403 if provider_error == "storage_denied" else 503, "Forbidden" if provider_error == "storage_denied" else "Service Unavailable", provider_error]
	if has_linked_branch_storage() and method == "PUT" and not linked_business_provider_writable(): return "HTTP/1.1 403 Forbidden\nstorage_denied"
	var portal_fs := _portal_storage_fs()
	if not portal_fs.has(PortalStorage.PRIMARY_PATH): return "HTTP/1.1 404 Not Found\nfile not found"
	var content := str(portal_fs[PortalStorage.PRIMARY_PATH])
	if method == "PUT":
		var upload := _portal_upload(args)
		if not bool(upload.get("ok", false)): return "HTTP/1.1 400 Bad Request\n" + str(upload.get("error", "invalid_upload"))
		if bool(upload.get("present", false)):
			var replacement := str(upload.get("content", ""))
			if replacement != content:
				PortalStorage.record_change(self,content,replacement,identity if not identity.is_empty() else role,"upload")
				portal_fs[PortalStorage.PRIMARY_PATH] = replacement
				content = replacement
				_touch("portal upload role=" + role)
				if str(state.applied.get("audit", "off")) == "on": _audit("portal put role=%s file=%s result=changed" % [role, PortalStorage.PRIMARY_PATH.get_file()])
			elif str(state.applied.get("audit", "off")) == "on": _audit("portal put role=%s file=%s result=unchanged" % [role, PortalStorage.PRIMARY_PATH.get_file()])
	return _portal_v2_response(role, expiry, parts, content)

func _identity_http(parts: Dictionary, method: String, args: Array) -> String:
	if method != "GET": return "HTTP/1.1 405 Method Not Allowed\n" + JSON.stringify({"ok":false,"code":405,"error":"method_not_allowed"})
	_identity_ensure_state()
	if parts.path == "/former/session":
		var session_result := _identity_command(["identity","access","former-seed-1"])
		var session_data: Dictionary = JSON.parse_string(session_result)
		return ("HTTP/1.1 200 OK\n" if bool(session_data.get("ok",false)) else "HTTP/1.1 401 Unauthorized\n")+session_result
	if parts.path not in ["/former/login","/current/login"]: return "HTTP/1.1 404 Not Found\n" + JSON.stringify({"ok":false,"code":404,"error":"unknown_route"})
	var user := "former" if parts.path == "/former/login" else "current"
	var query := str(parts.query); var password := _query_value(query,"password")
	if password.is_empty(): return "HTTP/1.1 401 Unauthorized\n" + JSON.stringify({"ok":false,"code":401,"error":"invalid_credentials"})
	var command_result := _identity_command(["identity","login",user,password])
	var parsed: Variant = JSON.parse_string(command_result)
	if not parsed is Dictionary: return "HTTP/1.1 500 Internal Server Error\n" + JSON.stringify({"ok":false,"code":500,"error":"identity_error"})
	var status := "200 OK" if bool(parsed.get("ok",false)) and str(parsed.get("error","")) != "mfa_required" else ("403 Forbidden" if str(parsed.get("error","")) == "account_disabled" else "401 Unauthorized")
	return "HTTP/1.1 %s\n%s" % [status,command_result]

func _identity_session_usable(id: String) -> bool:
	for session in state.identity_sessions:
		if str(session.get("id","")) == id: return not bool(session.get("revoked",false))
	return false

func _http(args: Array[String]) -> String:
	var url := ""; var method := "GET"
	for i in args.size():
		if args[i].begins_with("http://") or args[i].begins_with("https://"): url = args[i]
		if args[i] == "-X" and i + 1 < args.size(): method = args[i + 1].to_upper()
	if url.is_empty(): return "usage: curl [-X GET|PUT] https://<service>.client.test/<resource>"
	if not state.active: return "curl: (7) Connection refused; service is not running"
	var parts := _url_parts(url)
	var c: Dictionary = state.applied
	match _chapter:
		0:
			if parts.host != "files.client.test": return "curl: (6) Could not resolve host"
			if parts.path not in ["/staff/report.txt", "/guest/report.txt"]: return "HTTP/1.1 404 Not Found\nunknown file route"
			var role := "staff" if parts.path.begins_with("/staff/") else "guest"
			if int(state.get("samba_model_version",1)) >= 2:
				if method != "GET": return "HTTP/1.1 405 Method Not Allowed\nuse smbclient for file transfers"
				if not _permission(role,false): return "HTTP/1.1 403 Forbidden"
				var document := str(state.applied.get("path","")).path_join("report.txt").simplify_path()
				if not state.fs.has(document): return "HTTP/1.1 404 Not Found\nreport.txt missing from configured share"
				return "HTTP/1.1 200 OK\n"+str(state.fs[document])
			return "HTTP/1.1 200 OK\n" + state.fs.get("/srv/share/report.txt", "") if _permission(role, method == "PUT") else "HTTP/1.1 403 Forbidden"
		2:
			if parts.host not in ["intranet.client.test", "admin.client.test"]: return "curl: (6) Could not resolve host"
			if parts.path not in ["/", "", "/api/business/orders", "/api/business/customers", "/api/business/ledger"]: return "HTTP/1.1 404 Not Found\nunknown gateway route"
			if parts.path.begins_with("/api/business/") and parts.host != "intranet.client.test": return "HTTP/1.1 404 Not Found\nunknown business route"
			if parts.path.begins_with("/api/business/") and method != "GET": return "HTTP/1.1 405 Method Not Allowed\nread-only business route"
			if c.dns != "on": return "curl: (6) Could not resolve host"
			if _firewall_model_v2():
				var dns_decision := FirewallPolicy.evaluate(state.applied, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.LAN_ADDRESS, "udp", 40000, 53)
				_firewall_record_traffic(dns_decision, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.LAN_ADDRESS, "udp", 40000, 53)
				if str(dns_decision.get("action", "block")) != "pass": return "curl: (6) Could not resolve host " + _firewall_denial(dns_decision, "curl")
				var route_port := 8443 if parts.host == "admin.client.test" else (443 if parts.scheme == "https" else 80)
				if int(parts.get("port", -1)) != route_port: return "curl: (7) Connection refused"
				var decision := _firewall_action_for(parts.host, str(parts.scheme), route_port)
				_firewall_record_traffic(decision, "lan" if parts.host == "intranet.client.test" else "wan", FirewallPolicy.STAFF_ADDRESS if parts.host == "intranet.client.test" else FirewallPolicy.EXTERNAL_ADDRESS, FirewallPolicy.BUSINESS_ADDRESS if parts.host == "intranet.client.test" else FirewallPolicy.ADMIN_ADDRESS, "tcp", 40000, route_port)
				if str(decision.get("action", "block")) != "pass": return _firewall_denial(decision, "curl")
				if parts.scheme == "https" and c.tls != "on": return "curl: (35) TLS handshake failed"
				if parts.path.begins_with("/api/business/"):
					var resource := str(parts.path).get_file()
					var business := BusinessWorkspace.handle_get(_business_provider(), resource)
					var status := int(business.get("code", 500)); var phrase := "OK" if status == 200 else ("Forbidden" if status == 403 else ("Not Found" if status == 404 else ("Unprocessable Entity" if status == 422 else "Service Unavailable")))
					return "HTTP/1.1 %d %s\nContent-Type: application/json\n\n%s" % [status, phrase, JSON.stringify(business)]
				if parts.host == "admin.client.test": return "HTTP/1.1 200 OK\nManagement console"
				return "HTTP/1.1 200 OK\nSales workspace: operational\nTransport: " + ("TLS 1.3" if parts.scheme == "https" else "unencrypted")
			if parts.scheme == "https" and c.tls != "on": return "curl: (35) TLS handshake failed"
			if parts.path.begins_with("/api/business/"): return "HTTP/1.1 404 Not Found\nunknown business route"
			if parts.host == "admin.client.test": return "HTTP/1.1 403 Forbidden\npublic management denied" if c.admin_public == "deny" else "HTTP/1.1 200 OK\nManagement console"
			if c.business != "allow": return "curl: (7) Connection denied by firewall"
			return "HTTP/1.1 200 OK\nSales workspace: operational\nTransport: " + ("TLS 1.3" if parts.scheme == "https" else "unencrypted")
		3:
			if parts.host != "identity.client.test": return "curl: (6) Could not resolve host"
			if parts.path not in ["/former/login", "/former/session", "/current/login"]: return "HTTP/1.1 404 Not Found\nunknown identity route"
			if int(state.get("identity_model_version",1)) >= IDENTITY_MODEL_VERSION: return _identity_http(parts, method, args)
			if parts.path == "/former/session": return "HTTP/1.1 401 Unauthorized\nsession revoked" if c.sessions == "revoked" else "HTTP/1.1 200 OK\nexisting session accepted"
			if parts.path == "/former/login": return "HTTP/1.1 401 Unauthorized\naccount disabled" if c.former == "disabled" else "HTTP/1.1 200 OK\nformer user signed in"
			if parts.path == "/current/login":
				if c.current != "active": return "HTTP/1.1 403 Forbidden\ncurrent user disabled"
				return "HTTP/1.1 200 OK\ncurrent user: enabled\nMFA: " + ("challenge required" if c.mfa == "on" else "not required")
		4:
			if parts.host != "edr.client.test": return "curl: (6) Could not resolve host"
			if int(state.get("edr_model_version",1)) >= EDR_MODEL_VERSION:
				_edr_ensure_state(false)
				if parts.path not in ["/pc-a/outbound", "/pc-b/outbound", "/pc-a/business", "/pc-b/business"]: return "HTTP/1.1 404 Not Found\nunknown EDR route"
				var device_id: String = str(parts.path.get_slice("/",1).replace("-","_")); var endpoint: String = str(parts.path.get_slice("/",2))
				var edr_device := _edr_device(device_id)
				if edr_device.is_empty(): return "HTTP/1.1 404 Not Found\nunknown EDR device"
				if endpoint == "outbound":
					var destination := "192.0.2.20"
					for event in edr_device.get("events",[]):
						if str(event.get("type","")) == "outbound": destination = str(event.get("remote_address",destination)); break
					return "HTTP/1.1 403 Forbidden\nEDR: outbound isolated / destination %s" % destination if bool(edr_device.get("isolated",false)) else "HTTP/1.1 200 OK\n%s outbound allowed / destination %s" % [device_id.to_upper().replace("_","-"),destination]
				if not bool(edr_device.get("isolated",false)) and str(edr_device.get("business_status","")) != "healthy": return "HTTP/1.1 503 Service Unavailable\n%s business application unavailable" % device_id.to_upper().replace("_","-")
				return "HTTP/1.1 403 Forbidden\n%s business interrupted" % device_id.to_upper().replace("_","-") if bool(edr_device.get("isolated",false)) else "HTTP/1.1 200 OK\n%s business session healthy" % device_id.to_upper().replace("_","-")
			if parts.path not in ["/pc-a/outbound", "/pc-b/business"]: return "HTTP/1.1 404 Not Found\nunknown EDR route"
			if parts.path == "/pc-a/outbound": return "HTTP/1.1 403 Forbidden\nEDR: outbound isolated" if c.pc_a == "isolated" else "HTTP/1.1 200 OK\nPC-A outbound allowed / destination 203.0.113.77"
			if parts.path == "/pc-b/business": return "HTTP/1.1 200 OK\nPC-B business session healthy" if c.pc_b == "connected" else "HTTP/1.1 403 Forbidden\nPC-B business interrupted"
		5:
			if parts.host != "portal.client.test": return "curl: (6) Could not resolve host"
			if int(state.get("access_model_version", 1)) >= ACCESS_MODEL_VERSION: return _portal_response(parts, method, args)
			var role := "staff" if "/staff" in url else ("partner" if "/partner" in url else "public")
			if not _permission(role, method == "PUT"): return "HTTP/1.1 403 Forbidden\nrole=" + role
			if url.begins_with("https") and c.tls != "on": return "curl: (35) TLS handshake failed"
			if c.audit == "on": _touch("portal %s role=%s recorded" % [method, role])
			return "HTTP/1.1 200 OK\nrole=%s\nexpires=%s\nMFA=%s\ntransport=%s\naudit=%s\nDocument: partner-order.csv" % [role, c.expires, c.mfa, "TLS" if c.tls == "on" else "HTTP", c.audit]
	return "HTTP/1.1 404 Not Found\nhelp でこのホストのURLを確認してください。"

func backup_acceptance_view() -> Dictionary:
	if _chapter != 1: return {"available":false,"enforced":false,"legacy":false}
	var paths := {}
	var record: Variant = state.get("backup_authorization", {})
	if record is Dictionary and record.get("required_files", []) is Array:
		for source in record.get("required_files", []):
			paths[str(source)] = _restored_data_path(str(source).get_file())
	return BackupAuthorization.view(state, paths)

func _backup_records() -> Dictionary:
	var result: Dictionary = RECORDS.duplicate(true)
	var authored: Variant = state.get("scenario", {}).get("backup_expected_records", {})
	if authored is Dictionary: result.merge(authored, true)
	return result

func _restic_v2() -> bool:
	return _chapter == 1 and int(state.get("backup_model_version", 1)) >= 2

func _snapshot_id_text(value: Variant) -> String:
	return str(value).to_lower()

func _restic_select_snapshot(selector: String, repository: String) -> Dictionary:
	var candidates: Array = []
	for item in state.snapshots:
		if str(item.get("repository", "")) != repository: continue
		if selector == "latest" or _snapshot_id_text(item.get("id", "")) == selector.to_lower() or _snapshot_id_text(item.get("id", "")).begins_with(selector.to_lower()): candidates.append(item)
	if selector == "latest":
		return {"snapshot":candidates.back() if not candidates.is_empty() else {},"error":"" if not candidates.is_empty() else "restic: no snapshot in " + repository}
	if candidates.size() > 1: return {"snapshot":{},"error":"restic: ambiguous snapshot ID " + selector}
	if candidates.is_empty(): return {"snapshot":{},"error":"restic: snapshot not found " + selector}
	return {"snapshot":candidates[0],"error":""}

func _snapshot_source_paths(snapshot: Dictionary) -> Array:
	var paths: Array = snapshot.get("paths", ["/srv/data"])
	return paths if not paths.is_empty() else ["/srv/data"]

func _restored_data_path(name: String) -> String:
	if int(state.get("backup_model_version",1)) < 2: return "/restore/" + name
	var origins: Dictionary = state.get("backup_restore_origins", {}) if state.get("backup_restore_origins", {}) is Dictionary else {}
	var origin: Variant = origins.get("/srv/data/" + name, {})
	if origin is Dictionary and not str(origin.get("path", "")).is_empty(): return str(origin.path)
	var restore: Dictionary = state.get("last_restore", {}) if state.get("last_restore", {}) is Dictionary else {}
	if str(restore.get("subfolder", "")) == "/srv/data": return str(restore.get("target", "/restore")).path_join(name)
	return str(restore.get("target", "/restore")).path_join("srv/data").path_join(name)

func restic_restore_plan(repository: String, selector: String, destination: String, includes: Array = [], overwrite: String = "always") -> Dictionary:
	var base := {"ok":false,"error":"","snapshot":{},"subfolder":"","target":"","entries":[],"fingerprint":_fingerprint()}
	if _chapter != 1 or not _restic_v2(): base.error = "restore planning requires backup model v2"; return base
	if not state.active: base.error = "service configuration failed"; return base
	if not state.connected: base.error = "Not connected"; return base
	if repository not in ["local", "offsite"]: base.error = "invalid repository"; return base
	if overwrite not in ["always", "never"]: base.error = "invalid overwrite policy"; return base
	var raw_selector := selector.strip_edges()
	if raw_selector.is_empty(): base.error = "snapshot selector is empty"; return base
	var subfolder := ""
	if raw_selector.contains(":"):
		subfolder = raw_selector.get_slice(":", 1); raw_selector = raw_selector.get_slice(":", 0)
		if not subfolder.begins_with("/"): base.error = "invalid snapshot subfolder"; return base
	var selected_result := _restic_select_snapshot(raw_selector, repository)
	if not str(selected_result.error).is_empty(): base.error = str(selected_result.error).trim_prefix("restic: "); return base
	var selected: Dictionary = selected_result.snapshot
	var source_paths := _snapshot_source_paths(selected)
	var target := _path(destination)
	if target.is_empty(): target = "/restore"
	var include_values: Array[String] = []
	for raw_include in includes:
		var include := str(raw_include).strip_edges().trim_suffix("/")
		if include.is_empty(): base.error = "empty include path"; return base
		if "*" in include or "?" in include or "[" in include or "]" in include: base.error = "wildcard include is unsupported"; return base
		include_values.append(include)
	var source_root := str(source_paths[0]).trim_suffix("/")
	var matched := 0
	var entries: Array = []
	for raw_name in selected.get("files", {}).keys():
		var name := str(raw_name)
		var source := source_root.path_join(name)
		var relative_to_scope := name
		if not subfolder.is_empty():
			var scope_prefix := subfolder.trim_suffix("/") + "/"
			if source != subfolder and not source.begins_with(scope_prefix): continue
			relative_to_scope = source.trim_prefix(scope_prefix)
		var selected_by_include := include_values.is_empty()
		for include in include_values:
			if not subfolder.is_empty():
				var relative_include := include.trim_prefix("/").trim_suffix("/")
				if relative_to_scope == relative_include or relative_to_scope.begins_with(relative_include + "/"):
					selected_by_include = true; break
			else:
				var absolute_include := include if include.begins_with("/") else source_root.path_join(include)
				if source == absolute_include or source.begins_with(absolute_include + "/"):
					selected_by_include = true; break
		if not selected_by_include: continue
		matched += 1
		var path := target.path_join(relative_to_scope) if not subfolder.is_empty() else target.path_join(source.trim_prefix("/")).simplify_path()
		var value := str(selected.files[raw_name])
		var exists: bool = state.fs.has(path)
		var current := str(state.fs.get(path, ""))
		var status := "new"
		if exists: status = "unchanged" if current == value else ("overwrite" if overwrite == "always" else "skipped")
		if _restore_path_conflicts(path):
			base.error = "restore path conflicts with a file or directory"; return base
		entries.append({"source":source,"path":path,"status":status,"value":value,"bytes":value.to_utf8_buffer().size(),"current_sha256":current.sha256_text() if exists else "","snapshot_sha256":value.sha256_text()})
	if matched == 0: base.error = "no files matched include"; return base
	base.ok = true; base.snapshot = {"id":_snapshot_id_text(selected.get("id", "")),"repository":repository}; base.subfolder = subfolder; base.target = target; base.entries = entries
	var fingerprint_payload := {"base":base.fingerprint,"repository":repository,"selector":selector,"target":target,"includes":include_values,"overwrite":overwrite,"entries":entries.map(func(item): return {"path":item.path,"status":item.status,"current_sha256":item.current_sha256,"snapshot_sha256":item.snapshot_sha256})}
	base.fingerprint = JSON.stringify(fingerprint_payload).sha256_text()
	return base

func _restic_plan_output(plan: Dictionary, dry_run: bool = true) -> String:
	var lines: Array[String] = [("dry-run restore " if dry_run else "restore ") + "%s -> %s" % [str(plan.get("snapshot", {}).get("id", "")), str(plan.get("target", ""))]]
	for entry in plan.get("entries", []):
		var verb: String = str({"new":"restored","unchanged":"unchanged","overwrite":"updated","skipped":"skipped"}.get(str(entry.get("status", "")), str(entry.get("status", ""))))
		lines.append("%s -> %s (%s)" % [str(entry.get("source", "")), str(entry.get("path", "")), verb])
	return "\n".join(lines)

func _restic(args: Array[String]) -> String:
	if _chapter != 1: return "restic: backup repository is not configured on this host"
	if not state.active: return "restic: service configuration failed"
	if args.size() < 2: return "usage: restic [-r repository] snapshots | backup <path> | ls <snapshot> | dump <snapshot> <path> | restore <snapshot> --target <dir>"
	var repository: String = str(state.applied.get("repository", "local"))
	var command_args: Array[String] = [str(args[0])]
	var i := 1
	while i < args.size():
		if args[i] == "-r":
			if i + 1 >= args.size() or str(args[i + 1]) not in ["local", "offsite"]: return "restic: invalid repository"
			repository = str(args[i + 1]); i += 2; continue
		command_args.append(str(args[i])); i += 1
	if command_args.size() < 2: return "restic: missing subcommand"
	var subcommand := command_args[1]
	if subcommand == "snapshots":
		if command_args.size() != 2: return "restic: invalid snapshots flags"
		var lines := ["ID       Repository  Paths       Files"]
		for s in state.snapshots:
			if str(s.get("repository", "")) == repository: lines.append("%s     %s      %s    %d" % [_snapshot_id_text(s.get("id", "")),repository,";".join(PackedStringArray(_snapshot_source_paths(s))),s.get("files",{}).size()])
		return "\n".join(lines) if lines.size() > 1 else "ID       Repository  Paths       Files\n(no snapshots)"
	if subcommand == "backup":
		if command_args.size() != 3: return "restic: usage backup <source>"
		var source := _path(command_args[2])
		if source not in state.dirs: return "restic: source directory not found"
		var files := {}; var prefix := source + "/"
		for path in state.fs:
			if str(path).begins_with(prefix): files[str(path).substr(prefix.length())] = state.fs[path]
		if files.is_empty(): return "restic: no source files"
		var new_id: Variant = "%08x" % (state.snapshots.size() + 1) if _restic_v2() else state.snapshots.size() + 1
		state.snapshots.append({"id":new_id,"repository":repository,"paths":[source],"files":files.duplicate(true)})
		_touch("backup %d files -> %s" % [files.size(), repository])
		return "snapshot saved: %s\nFiles: %d\nRepository: %s" % [_snapshot_id_text(new_id),files.size(),repository]
	if subcommand in ["ls", "dump"]:
		if (subcommand == "ls" and command_args.size() != 3) or (subcommand == "dump" and command_args.size() != 4): return "restic: invalid " + subcommand + " arguments"
		var selected_result := _restic_select_snapshot(command_args[2],repository)
		if not str(selected_result.error).is_empty(): return str(selected_result.error)
		var selected: Dictionary = selected_result.snapshot
		var source_paths := _snapshot_source_paths(selected)
		if subcommand == "ls":
			var listed: Array[String] = []
			for name in selected.get("files",{}): listed.append(str(source_paths[0]).path_join(str(name)))
			listed.sort(); return "\n".join(listed)
		var requested := _path(command_args[3])
		for source_path in source_paths:
			var rel := requested.trim_prefix(str(source_path).trim_suffix("/") + "/")
			if rel != requested and selected.get("files",{}).has(rel): return str(selected.files[rel])
		return "restic: path not found in snapshot"
	if subcommand == "restore":
		if command_args.size() < 5 or command_args[3] != "--target": return "restic: usage restore <snapshot>[:<subfolder>] --target <dir>"
		var selector := command_args[2]
		var dest := _path(command_args[4])
		var includes: Array = []
		var overwrite := "always"
		var dry_run := false
		var verbose := false
		var option_index := 5
		while option_index < command_args.size():
			var option := command_args[option_index]
			if option == "--include":
				if option_index + 1 >= command_args.size(): return "restic: missing --include path"
				includes.append(command_args[option_index + 1]); option_index += 2; continue
			if option == "--overwrite":
				if option_index + 1 >= command_args.size() or command_args[option_index + 1] not in ["always", "never"]: return "restic: invalid overwrite policy"
				overwrite = command_args[option_index + 1]; option_index += 2; continue
			if option == "--dry-run": dry_run = true; option_index += 1; continue
			if option == "--verbose=2": verbose = true; option_index += 1; continue
			return "restic: unsupported restore flag " + option
		if not _restic_v2():
			if command_args.size() != 5 or selector != "latest": return "restic: usage restore latest --target <dir>"
			var legacy_selected_result := _restic_select_snapshot(selector,repository)
			if not str(legacy_selected_result.error).is_empty(): return str(legacy_selected_result.error)
			var legacy_selected: Dictionary = legacy_selected_result.snapshot
			if dest not in state.dirs: return "restic: create target directory first"
			for name in legacy_selected.get("files",{}): state.fs[dest + "/" + str(name)] = legacy_selected.files[name]
			_touch("restored snapshot %s -> %s" % [_snapshot_id_text(legacy_selected.id),dest])
			return "restored %d files to %s" % [legacy_selected.get("files",{}).size(),dest]
		var plan := restic_restore_plan(repository, selector, dest, includes, overwrite)
		if not bool(plan.get("ok", false)): return "restic: " + str(plan.get("error", "restore plan failed"))
		if dry_run: return _restic_plan_output(plan)
		var writes: Array = []
		for entry in plan.entries:
			if str(entry.get("status", "")) != "skipped": writes.append(entry)
		var write_paths: Array = writes.map(func(item): return str(item.path))
		if not _restore_parent_dirs(write_paths): return "restic: restore path conflicts with a file"
		var new_dirs: Array[String] = []
		for write_path in write_paths:
			var parent := str(write_path).get_base_dir()
			var chain: Array[String] = []
			while parent not in state.dirs and parent != "/": chain.push_front(parent); parent = parent.get_base_dir()
			for directory in chain:
				if directory not in new_dirs: new_dirs.append(directory)
		for directory in new_dirs: state.dirs.append(directory)
		for entry in writes: state.fs[entry.path] = entry.value
		if state.has("backup_authorization_version") or bool(state.get("scenario", {}).get("backup_preservation_required", false)):
			if not state.get("backup_restore_origins", {}) is Dictionary: state.backup_restore_origins = {}
			if not state.has("backup_restore_origins"): state.backup_restore_origins = {}
			for entry in writes:
				state.backup_restore_origins[str(entry.source)] = {"snapshot":str(plan.snapshot.id),"path":str(entry.path),"sha256":str(entry.value).sha256_text()}
		state.last_restore = {"snapshot":str(plan.snapshot.id),"subfolder":str(plan.subfolder),"target":str(plan.target),"includes":includes.duplicate(),"overwrite":overwrite}
		_sync_backup_probe_paths()
		_touch("restored snapshot %s -> %s" % [str(plan.snapshot.id),dest])
		var result := "restored %d files to %s" % [writes.size(),dest]
		if verbose: result += "\n" + _restic_plan_output(plan, false)
		return result
	return "restic: unsupported subcommand"

func evaluate() -> Array[bool]:
	var no: Array[bool] = []
	if not state.active:
		for i in [2,3,4,4,3,8][_chapter]: no.append(false)
		return no
	var c: Dictionary = state.applied
	if bool(state.get("dirty", false)):
		for i in [2,3,4,4,3,8][_chapter]: no.append(false)
		return no
	if state.get("scenario", {}) is Dictionary and not state.scenario.is_empty(): return _evaluate_scenario()
	match _chapter:
		0: return [_permission("staff", true), not _permission("guest", false)]
		1:
			var restored := true; var offsite_snapshot := false
			for name in RECORDS:
				if state.fs.get(_restored_data_path(name), "") != RECORDS[name]: restored = false
			for s in state.snapshots:
				if s.repository == "offsite" and s.files == RECORDS: offsite_snapshot = true
			return [c.schedule == "daily", c.repository == "offsite", restored and offsite_snapshot]
		2:
			if _firewall_model_v2():
				var business_check := FirewallPolicy.evaluate(c, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.BUSINESS_ADDRESS, "tcp", 40000, 443)
				var admin_check := FirewallPolicy.evaluate(c, "wan", FirewallPolicy.EXTERNAL_ADDRESS, FirewallPolicy.ADMIN_ADDRESS, "tcp", 40000, 8443)
				return [c.dns == "on", c.dns == "on" and str(business_check.get("action", "block")) == "pass" and c.tls == "on", str(admin_check.get("action", "block")) == "block", c.tls == "on"]
			return [c.dns == "on", c.dns == "on" and c.business == "allow" and c.tls == "on", c.admin_public == "deny", c.tls == "on"]
		3: return [c.former == "disabled", c.sessions == "revoked", c.current == "active", c.mfa == "on"]
		4:
			var expected_evidence := EVIDENCE if int(state.get("edr_model_version",1)) < EDR_MODEL_VERSION else str(state.get("evidence_original", EVIDENCE))
			var evidence_ok: bool = state.fs.get("/var/log/evidence.log", "") == expected_evidence and c.logs == "keep" and c.reset == "wait"
			if int(state.get("edr_model_version",1)) >= EDR_MODEL_VERSION: evidence_ok = evidence_ok and bool(_edr_evidence_status().get("valid",false))
			return [c.pc_a == "isolated", c.pc_b == "connected", evidence_ok]
		5: return [_permission("staff", true), _permission("partner", false), not _permission("partner", true), not _permission("public", false), c.expires == "7d", c.mfa == "on", c.tls == "on", c.audit == "on"]
	return no

func _evaluate_scenario() -> Array[bool]:
	var scenario: Dictionary = state.scenario
	if _chapter == 4 and EndpointRemediation.enabled(state):
		var business_ok := true
		var clean := true
		for device in ["pc_a","pc_b"]:
			var status: Dictionary = EndpointRemediation.status(state,device)
			business_ok = business_ok and str(state.applied.get(device,"")) == "connected" and bool(status.get("business_available",false))
			clean = clean and int(status.get("threat_count",-1)) == 0 and bool(status.get("scan_current",false)) and bool(status.get("scan_clean",false))
		return [business_ok,clean,bool(_edr_evidence_status().get("valid",false)) and state.applied.get("logs","") == "keep" and state.applied.get("reset","") == "wait"]
	var desired: Dictionary = scenario.get("desired", {})
	var result: Array[bool] = []
	var desired_keys: Array = desired.keys()
	if _chapter == 4:
		# JSON sorts object keys. Keep verdicts aligned with the authored EDR
		# labels after reload instead of reporting logs=keep under the PC-A label.
		desired_keys = ["pc_a", "pc_b", "logs", "reset"].filter(func(key): return desired.has(key))
	for key in desired_keys:
		var actual: Variant = state.applied.get(key, "")
		if _firewall_model_v2() and key in ["business", "admin_public"]:
			var business_check := FirewallPolicy.evaluate(state.applied, "lan", FirewallPolicy.STAFF_ADDRESS, FirewallPolicy.BUSINESS_ADDRESS, "tcp", 40000, 443)
			var admin_check := FirewallPolicy.evaluate(state.applied, "wan", FirewallPolicy.EXTERNAL_ADDRESS, FirewallPolicy.ADMIN_ADDRESS, "tcp", 40000, 8443)
			actual = "allow" if str((business_check if key == "business" else admin_check).get("action", "block")) == "pass" else "deny"
		if _firewall_model_v2() and key == "rules": actual = state.applied.get("rules", [])
		if _chapter == 0 and int(state.get("samba_model_version",1)) >= 2 and key in ["staff","guest"]:
			actual = "write" if _permission(str(key),true) else ("read" if _permission(str(key),false) else "none")
		result.append(actual == desired[key])
	if _chapter == 1:
		var restored := true
		var required: Array = scenario.get("required_files", [])
		if required.is_empty():
			for name in RECORDS: required.append("/srv/data/" + name)
		for file in required:
			if str(file).begins_with("/srv/data/"):
				if state.fs.get(_restored_data_path(str(file).get_file()), "") != _backup_records().get(str(file).get_file(), ""): restored = false
		var valid_snapshot := false
		for snapshot in state.snapshots:
			if snapshot.get("repository", "") == desired.get("repository", "") and snapshot.get("files", {}) == _backup_records(): valid_snapshot = true
		var acceptance := backup_acceptance_view()
		if bool(acceptance.get("enforced", false)): restored = bool(acceptance.get("restore_valid", false))
		if result.size() >= 2: result.append(restored and valid_snapshot)
		if bool(acceptance.get("enforced", false)):
			result.append(bool(acceptance.get("original_preserved", false)))
			result.append(bool(acceptance.get("unrelated_preserved", false)))
	if _chapter == 4:
		var evidence_ok: bool = state.fs.get("/evidence/original.log", "") == state.get("evidence_original", EVIDENCE) and state.fs.get("/var/log/evidence.log", "") == state.get("evidence_original", EVIDENCE)
		if int(state.get("edr_model_version",1)) >= EDR_MODEL_VERSION: evidence_ok = evidence_ok and bool(_edr_evidence_status().get("valid",false))
		result.append(evidence_ok)
		if HotelFrontdesk.enabled(state): result.append(HotelFrontdesk.accepted(state))
	return result

func _aya_readonly_probe(command: String) -> bool:
	var args := _tokens(command.strip_edges())
	if args.is_empty(): return false
	if args[0] == "smbclient":
		if args.size() < 6 or not str(args[1]).begins_with("//") or "-c" not in args: return false
		var c_index := args.find("-c")
		return c_index == args.size() - 2 and str(args[c_index + 1]).strip_edges() == "ls"
	if args[0] == "restic":
		var index := 1
		while index < args.size() and str(args[index]) == "-r":
			if index + 1 >= args.size() or str(args[index + 1]) not in ["local", "offsite"]: return false
			index += 2
		if index >= args.size(): return false
		var subcommand := str(args[index])
		if subcommand == "snapshots": return args.size() == index + 1
		if subcommand == "ls": return args.size() == index + 2
		if subcommand == "dump": return args.size() == index + 3
		return false
	if args[0] == "dig": return args.size() == 2
	if args[0] == "curl":
		var method := "GET"; var url_count := 0; var index := 1
		while index < args.size():
			var token := str(args[index])
			if token in ["-X", "--request"]:
				if index + 1 >= args.size() or str(args[index + 1]).to_upper() not in ["GET", "HEAD"]: return false
				method = str(args[index + 1]).to_upper(); index += 2; continue
			if token in ["-H", "--header"]:
				if index + 1 >= args.size() or str(args[index + 1]).is_empty(): return false
				index += 2; continue
			if token.begins_with("-"): return false
			if token.contains("/login"): return false
			if token.begins_with("http://") or token.begins_with("https://"): url_count += 1; index += 1; continue
			return false
		return url_count == 1 and method in ["GET", "HEAD"]
	if args[0] == "identity":
		return (args.size() == 2 and str(args[1]) in ["users", "sessions"]) or (args.size() == 3 and str(args[1]) == "sessions")
	if args[0] == "edr":
		return (args.size() == 2 and str(args[1]) == "devices") or (args.size() == 3 and str(args[1]) in ["timeline","files","status"] and str(args[2]) in ["pc_a", "pc_b"])
	if args[0] == "sha256sum": return args.size() == 2
	return false

func _aya_observe_probes() -> Array[String]:
	var observed: Array[String] = []
	for probe in _active_probes():
		var command := str(probe.get("command", "")).strip_edges()
		if not _aya_readonly_probe(command): continue
		# Call the command implementation directly. This deliberately bypasses
		# run/_record_command so a staff observation cannot manufacture a pass.
		var output := _run_internal(command)
		observed.append("$ " + command + "\n" + output)
	return observed

func cooperate(role: String, worker: Dictionary = {}) -> Array[String]:
	var log: Array[String] = []
	# The role still selects the bounded operation.  A worker may only change
	# the report attribution and its operator-home output path; it cannot alter
	# probes, checks, or the VM identity/configuration.
	var report_name := str(worker.get("name", "")).strip_edges()
	var report_path := str(worker.get("report_path", "")).strip_edges()
	if report_name.is_empty(): report_name = _identity.aya if role == "aya" else (_identity.ren if role == "ren" else _identity.player)
	if not (report_path.begins_with("/home/operator/") and not report_path.contains("..")):
		report_path = "/home/operator/aya-inspection.txt" if role == "aya" else "/home/operator/ren-verification.txt"
	state.cooperation_requires_selection = false
	var recovery_complete := true
	if not state.connected: log.append(_run_internal("ssh client"))
	var scenario: Dictionary = state.get("scenario", {})
	var desired: Dictionary = scenario.get("desired", {})
	if desired.is_empty(): desired = _legacy_desired()
	if role == "aya":
		# Keep the existing four observations, but bypass run() so an employee
		# cannot accidentally mark a validation probe as measured.
		log.append("$ cat " + OPERATOR_HOME + "/requirements.txt\n" + _run_internal("cat " + OPERATOR_HOME + "/requirements.txt"))
		log.append("$ cat " + state.config_path + "\n" + _run_internal("cat " + state.config_path))
		log.append("$ systemctl status " + state.service + "\n" + _run_internal("systemctl status " + state.service))
		log.append("$ journalctl\n" + _run_internal("journalctl"))
		var observed := _aya_observe_probes()
		var observation_heading := DISPLAY_COPY.copy("investigation_observations", "")
		var observed_day := str(worker.get("observed_day", "")); var observed_time := str(worker.get("observed_time", ""))
		var observed_at := observed_day + (" " if not observed_day.is_empty() and not observed_time.is_empty() else "") + observed_time
		var observation_block := ""
		if not observed.is_empty():
			observation_block = "\n\n" + observation_heading
			if not observed_at.strip_edges().is_empty(): observation_block += "\n" + DISPLAY_COPY.copy("investigation_observed_at", "") + ": " + observed_at.strip_edges()
			observation_block += "\n\n" + "\n\n".join(observed)
		write_file(report_path, "%s / 調査記録\n担当: %s\n設定変更・最終判断: %s\nservice=" % [_identity.company, report_name, _identity.player] + state.service + "\nconfig=" + state.config_path + "\n\n" + "\n".join(log) + observation_block + "\n")
	elif role == "ren":
		if _chapter == 1:
			if _restic_v2() and state.snapshots.size() > 1:
				log.append(run("restic snapshots"))
				state.cooperation_requires_selection = true
				log.append(DISPLAY_COPY.copy("backup_selection_required"))
				recovery_complete = false
			else:
				if String(scenario.get("seed_snapshot_repository", "")).is_empty() or String(scenario.get("seed_snapshot_repository", "")) != String(desired.get("repository", "")): log.append(run("restic backup /srv/data"))
				log.append(run("restic restore latest --target /restore"))
		if _chapter == 4: log.append(run("cp /var/log/evidence.log /evidence/original.log"))
		var recovery_note := DISPLAY_COPY.copy("backup_recovery_done") if recovery_complete else DISPLAY_COPY.copy("backup_selection_required")
		write_file(report_path, "%s / 復旧・保全記録\n担当: %s\n最終検証: %s\nservice=" % [_identity.company, report_name, _identity.player] + state.service + "\n" + recovery_note + "\n" + "\n".join(log) + "\n")
	else: log.append("unsupported cooperation role")
	return log

func _legacy_probes() -> Array:
	var extra: Dictionary = {}
	if _chapter == 1: extra.required_files = ["/srv/data/customers.csv","/srv/data/orders.csv","/srv/data/ledger.txt"]
	return CaseCatalog._probes(_chapter, _legacy_desired(), extra)

func _normalize_backup_probes() -> void:
	if _chapter != 1 or int(state.get("backup_model_version",1)) < 2: return
	var probes: Array = state.get("probes", [])
	for probe in probes:
		var command := str(probe.get("command", ""))
		if command.begins_with("sha256sum /restore/") and not command.begins_with("sha256sum /restore/srv/data/"):
			_clear_probe_measurement(probe)
			probe.command = command.replace("sha256sum /restore/", "sha256sum /restore/srv/data/")
	if state.get("scenario", {}) is Dictionary and not state.scenario.is_empty():
		for probe in state.scenario.get("probes", []):
			var command := str(probe.get("command", ""))
			if command.begins_with("sha256sum /restore/") and not command.begins_with("sha256sum /restore/srv/data/"):
				_clear_probe_measurement(probe)
				probe.command = command.replace("sha256sum /restore/", "sha256sum /restore/srv/data/")

func _normalize_portal_probes() -> void:
	if not _portal_model_v2(): return
	for probe in _active_probes():
		var command := str(probe.get("command", ""))
		if not command.begins_with("curl -X PUT") or "--data-binary" in command or "--data-raw" in command or "--data " in command or " -d " in command or " -T " in command or "--upload-file" in command: continue
		var normalized := command + " --data-binary @" + PortalStorage.PRIMARY_PATH
		if command != normalized:
			_clear_probe_measurement(probe)
			probe.command = normalized

func _sync_backup_probe_paths() -> void:
	if _chapter != 1 or int(state.get("backup_model_version",1)) < 2: return
	for probe in _active_probes():
		var probe_id := str(probe.get("id", ""))
		if not probe_id.begins_with("restore-"): continue
		var filename := probe_id.trim_prefix("restore-")
		if filename.is_empty(): continue
		var next_command := "sha256sum " + _restored_data_path(filename)
		if str(probe.get("command", "")) != next_command:
			_clear_probe_measurement(probe)
			probe.command = next_command

func _legacy_desired() -> Dictionary:
	return [{"staff":"write","guest":"none"},{"schedule":"daily","repository":"offsite"},{"dns":"on","business":"allow","admin_public":"deny","tls":"on"},{"former":"disabled","sessions":"revoked","current":"active","mfa":"on"},{"pc_a":"isolated","pc_b":"connected","logs":"keep","reset":"wait"},{"staff":"write","partner":"read","public":"none","expires":"7d","mfa":"on","tls":"on","audit":"on"}][_chapter]

func snapshot() -> Array:
	if state.get("scenario", {}) is Dictionary and not state.scenario.is_empty():
		var scenario_results := evaluate(); var custom: Array = []
		for i in scenario_results.size(): custom.append({"target":str(state.service),"operation":str(state.scenario.get("checks",[])[i]) if i<state.scenario.get("checks",[]).size() else "状態確認","result":"PASS" if scenario_results[i] else "FAIL","ok":scenario_results[i]})
		return custom
	var tests := [
		[["staff","SMB PUT report.txt"],["guest","SMB GET report.txt"]],
		[["timer","backup schedule"],["repository","offsite copy"],["restore","compare 3 file contents"]],
		[["DNS","A intranet.client.test"],["business","HTTPS /"],["public","admin access"],["TLS","handshake"]],
		[["former","new login"],["former","existing session"],["current","login"],["current","MFA challenge"]],
		[["PC-A","outbound connection"],["PC-B","business continuity"],["evidence.log","integrity check"]],
		[["staff","PUT"],["partner","GET"],["partner","PUT denied"],["public","GET denied"],["link","expiration"],["partner","MFA"],["TLS","handshake"],["audit","recording"]]
	]
	var out: Array = []; var results := evaluate()
	for i in results.size(): out.append({"target":tests[_chapter][i][0],"operation":tests[_chapter][i][1],"result":"PASS" if results[i] else "FAIL","ok":results[i]})
	return out

func _reference() -> String:
	var examples := [
		"smbclient //client/share -U staff -c \"put /srv/data/orders.csv\"\nsmbclient //client/share -U guest -c ls\ncurl https://files.client.test/staff/report.txt",
		"cat /home/operator/recovery-manifest.sha256\nrestic snapshots\nrestic backup /srv/data\nrestic restore latest --target /restore\ndiff /srv/data/orders.csv /restore/orders.csv\nsha256sum /restore/orders.csv",
		"dig intranet.client.test\ncurl https://intranet.client.test\ncurl https://admin.client.test\nss -lnt",
		"curl https://identity.client.test/former/login\ncurl https://identity.client.test/former/session\ncurl https://identity.client.test/current/login",
		"journalctl\ncat /var/log/evidence.log\ncp /var/log/evidence.log /evidence/original.log\ncurl https://edr.client.test/pc-a/outbound\ncurl https://edr.client.test/pc-b/business",
		"curl -X PUT https://portal.client.test/staff\ncurl https://portal.client.test/partner\ncurl -X PUT https://portal.client.test/partner\ncurl https://portal.client.test/public"
	]
	var fixture := ""
	var config_reference := JSON.stringify(SCHEMAS[_chapter], "\t")
	if _restic_v2():
		examples[1] = DISPLAY_COPY.copy("backup_reference_commands")
		fixture = "\n\n" + DISPLAY_COPY.copy("backup_id_placeholder") + "\n" + DISPLAY_COPY.copy("backup_reference") + "\n"
	if _chapter == 0 and int(state.get("samba_model_version",1)) >= 2:
		config_reference = "[global] と共有名のセクションで記述します。\n[share] の path=/srv/share、read only=yes/no、guest ok=yes/no、valid users、invalid users、write list、read list、available=yes/no を扱います。\nvalid users は接続を制限し、write list は許可されたユーザーの書き込みを許可します。\nread only の既定は yes。write list は read list より優先します。"
		examples[0] = "testparm -s\nsystemctl restart samba\nsmbclient //files01.client.test/share -U staff -c 'put /srv/data/orders.csv'\nsmbclient //files01.client.test/share -N -c ls"
		fixture = "\nこの演習の認証済みユーザーは staff、ゲストのUnixアカウントは nobody です。パスワード照合とOS側の所有者・アクセス権は固定条件です。\n未対応の設定項目は明示的にエラーになります。testparm は構文確認のみで、反映には再起動が必要です。\n"
	if _chapter == 3 and int(state.get("identity_model_version",1))>=2:
		examples[3] = "identity users\nidentity sessions [former|current]\nidentity enable <user> on|off\nidentity mfa on|off\nidentity login <user> Training-117!\nidentity otp <challenge-id> 123456\nidentity access <token>\nidentity logout <session-id>\nidentity logout-all <user>\nidentity access current-latest\njournalctl"
		fixture = "\n\n"+DISPLAY_COPY.copy("identity_reference_body", "")+"\n"
	if _chapter == 4 and int(state.get("edr_model_version",1))>=2:
		examples[4] = "edr devices\nedr timeline pc_a|pc_b\nedr isolate pc_a|pc_b\nedr release pc_a|pc_b\nedr collect\n" + examples[4]
		if EndpointRemediation.enabled(state): examples[4] += "\nedr files pc_a|pc_b\nedr quarantine <device> <file_id>\nedr scan pc_a|pc_b\nedr status pc_a|pc_b\nedr restore <quarantine_id>\n"
	if _chapter == 5: fixture = "\nPORTAL演習用セッション:\ncurl -H 'Authorization: Bearer partner-session' 'https://portal.client.test/partner?link=current'\ncurl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=current'\n"
	return "業務端末 / 仮想環境\n\nssh client    顧客端末へ接続\ncat /home/operator/requirements.txt    今回の依頼条件\nls [path] / cd <directory> / pwd\ncat <file> / edit <file>    読む・エディタで開く\nmkdir [-p] <dir> / cp <source> <dest> / rm <file>\ndiff <a> <b> / sha256sum <file>\nsystemctl status|restart %s\njournalctl / clear / exit\nreset-lab --confirm    顧客環境を初期化\n\nCONFIG: %s\n許可される設定値:\n%s\n\nこのサービスの動作確認コマンド:\n%s%s" % [SERVICES[_chapter], PATHS[_chapter], config_reference, examples[_chapter], fixture]

func export_state() -> Dictionary:
	return state.duplicate(true)
