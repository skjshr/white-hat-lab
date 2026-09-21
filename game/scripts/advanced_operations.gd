extends RefCounted

static func create(case_id: String) -> Dictionary:
	var s: Dictionary = {"kind":case_id,"revision":0,"flags":{},"nodes":[],"edges":[],"events":[],"records":[],"actions":[],"checks":[],"last_result":{}}
	if case_id not in ["advanced-hunt","advanced-pentest","advanced-recovery"]: return {}
	if case_id == "advanced-hunt":
		s.nodes = [_node("gateway","adv_node_gateway",0.05,0.20),_node("workstation","adv_node_workstation",0.30,0.20),_node("file-server","adv_node_file_server",0.55,0.20),_node("business","adv_node_business",0.80,0.20)]
		s.edges = [_edge("gateway","workstation","adv_edge_auth_chain"),_edge("workstation","file-server","adv_edge_file_access"),_edge("file-server","business","adv_edge_business_dependency")]
		s.actions = [_action("correlate_gateway","adv_action_correlate_gateway","gateway",[]),_action("correlate_workstation","adv_action_correlate_workstation","workstation",[]),_action("correlate_fileserver","adv_action_correlate_fileserver","file-server",[])]
		s.checks = [_check("scope","adv_check_hunt_scope"),_check("evidence","adv_check_evidence"),_check("containment","adv_check_containment"),_check("business","adv_check_business"),_check("false_attribution","adv_check_false_attribution")]
	elif case_id == "advanced-pentest":
		s.nodes = [_node("employee","adv_node_employee",0.05,0.20),_node("share","adv_node_share",0.30,0.20),_node("service-account","adv_node_service_account",0.55,0.20),_node("proof-file","adv_node_proof_file",0.80,0.20)]
		s.edges = [_edge("employee","share","adv_edge_share_access"),_edge("share","service-account","adv_edge_trust"),_edge("service-account","proof-file","adv_edge_sensitive_access")]
		s.actions = [_action("discover_assets","adv_action_discover_assets","assets",[]),_action("inspect_permissions","adv_action_inspect_permissions","permissions",[])]
		s.checks = [_check("scope","adv_check_authorized_scope"),_check("path","adv_check_reproducible_path"),_check("blocked","adv_check_blocked_path"),_check("legitimate","adv_check_legitimate_business")]
	else:
		s.kind = "advanced-recovery"; s.nodes = [_node("identity","adv_node_identity",0.05,0.20),_node("backup","adv_node_backup",0.30,0.20),_node("staging","adv_node_staging",0.55,0.20),_node("business","adv_node_business",0.80,0.20)]
		s.edges = [_edge("identity","backup","adv_edge_trust_dependency"),_edge("backup","staging","adv_edge_restore_dependency"),_edge("staging","business","adv_edge_business_dependency")]
		s.actions = [_action("compare_snapshots","adv_action_compare_snapshots","snapshot",["snap-0730","snap-1405","snap-1410"]),_action("stage_restore","adv_action_stage_restore","staging",[]),_action("scan_stage","adv_action_scan_stage","staging",[]),_action("repair_identity","adv_action_repair_identity","identity",[]),_action("remove_persistence","adv_action_remove_persistence","persistence",[]),_action("isolate_network","adv_action_isolate_network","network",[]),_action("restore_business","adv_action_restore_business","business",[]),_action("reconnect_business","adv_action_reconnect_business","business",[])]
		s.actions.append(_action("start_service","adv_action_start_service","service",["identity","database","app"]))
		s.checks = [_check("snapshot","adv_check_clean_snapshot"),_check("staging","adv_check_staged_scan"),_check("identity","adv_check_identity_repaired"),_check("persistence","adv_check_persistence_removed"),_check("network","adv_check_clean_network"),_check("business","adv_check_recovery_business"),_check("reinfection","adv_check_no_reinfection")]
	if case_id == "advanced-hunt": _seed_hunt(s)
	elif case_id == "advanced-pentest": _seed_pentest(s)
	else: _seed_recovery(s)
	if s.events.is_empty(): s.events = [{"id":"event-1","time":"00:00","source":"telemetry","asset":str(s.nodes[0].id),"detail":"initial evidence available","pinned":false}]
	if s.records.is_empty(): s.records = [{"id":"record-1","label":"adv_record_initial","detail":"adv_record_initial_detail","status_key":"adv_status_available"}]
	return s

static func support(s: Dictionary) -> bool:
	return str(s.get("kind", "")) in ["advanced-hunt","advanced-pentest","advanced-recovery"]

static func _seed_hunt(s: Dictionary) -> void:
	s.world = {"assets":{"gw01":{"kind":"gateway","connected":true},"ws17":{"kind":"workstation","connected":true},"fs02":{"kind":"file-server","connected":true},"backup01":{"kind":"backup","connected":true}},"sessions":{"sid-b21":{"account":"backup-agent","host":"backup01","active":true},"sid-r44":{"account":"svc-sync","host":"ws17","active":true}},"tasks":{"task-backup":{"host":"backup01","command":"backup /srv/data","enabled":true},"task-sync":{"host":"ws17","command":"sync /srv/share","enabled":true}},"pinned":[],"security_result":"unmeasured","business_result":"unmeasured"}
	var events: Array = []
	for i in 12:
		var benign: bool = i < 4
		var sid: String = "sid-b21" if benign else "sid-r44"
		var host: String = "backup01" if benign else "ws17"
		var destination: String = "fs02" if benign else "fs02"
		var task: String = "task-backup" if benign else "task-sync"
		var detail: String = ("sid-b21 src=backup01 change=CHG-114 window=02:00-02:10 task=task-backup path=/srv/data -> fs02 bytes=48000") if benign else ("sid-r44 src=ws17 change=none owner=svc-sync owner-login=01:58/gw01 task=task-sync path=/srv/share -> fs02 bytes=%d" % (87000 * i))
		events.append({"id":"evt-%02d" % i,"time":"02:%02d" % i,"source":sid,"asset":host,"destination":destination,"session":sid,"task":task,"path":"/srv/data" if benign else "/srv/share","detail":detail,"pinned":false,"hash":""})
	for event in events: event.hash = JSON.stringify(event).sha256_text()
	s.events = events
	s.records = [_record("telemetry","adv_record_telemetry","available"),_record("sessions","adv_record_sessions","available"),_record("scheduled-tasks","adv_record_scheduled_tasks","available")]
	var event_options: Array = []
	for event in events: event_options.append(str(event.id))
	s.actions.append(_action("pin_event","adv_action_pin_event","event",event_options))
	s.actions.append(_action("isolate_host","adv_action_isolate_host","host",["gw01","ws17","fs02","backup01"]))
	s.actions.append(_action("reconnect_host","adv_action_reconnect_host","host",["gw01","ws17","fs02","backup01"]))
	s.actions.append(_action("revoke_session","adv_action_revoke_session","session",["sid-b21","sid-r44"]))
	s.actions.append(_action("restore_session","adv_action_restore_session","session",["sid-b21","sid-r44"]))
	s.actions.append(_action("disable_task","adv_action_disable_task","task",["task-backup","task-sync"]))
	s.actions.append(_action("enable_task","adv_action_enable_task","task",["task-backup","task-sync"]))
	s.actions.append(_action("probe_security","adv_action_probe_security","probe",[])); s.actions.append(_action("probe_business","adv_action_probe_business","probe",[]))

static func _seed_pentest(s: Dictionary) -> void:
	s.world = {"principal":"employee01","grants":{"employee01":["share01"],"svc-report":["evidence/proof.csv"]},"files":{"share01/deploy.env":"SERVICE_USER=svc-report\nTOKEN=report-token-v1\n","evidence/proof.csv":"id,classification\nproof-01,restricted\n"},"credential":"report-token-v1","held_credentials":{},"service_access":true,"grant_fixed":false,"path_trace":[],"trace_records":[],"retest":[]}
	s.events = [{"id":"scope-01","time":"09:00","source":"engagement","asset":"employee01","detail":"authorized scope","pinned":true},{"id":"grant-01","time":"09:01","source":"acl","asset":"share01","detail":"inherited read grant","pinned":false}]
	s.records = [_record("permission-map","adv_record_permission_map","available"),_record("path-trace","adv_record_path_trace","pending"),_record("retest","adv_record_retest","pending")]
	s.actions.append(_action("connect_target","adv_action_connect_target","target",["share01","svc-report","evidence/proof.csv"]))
	s.actions.append(_action("read_credential","adv_action_read_credential","target",["share01"]))
	s.actions.append(_action("authenticate_service","adv_action_authenticate_service","target",["svc-report"]))
	s.actions.append(_action("read_proof","adv_action_read_proof","target",["evidence/proof.csv"]))
	s.actions.append(_action("modify_grant","adv_action_modify_grant","grant",["share01"]))
	s.actions.append(_action("retest_path","adv_action_retest_path","target",["evidence/proof.csv"]))

static func _seed_recovery(s: Dictionary) -> void:
	s.world = {"snapshots":{"snap-0730":{"ledger":"id,amount\n001,100\n","startup":"none","revision":7},"snap-1405":{"ledger":"id,amount\n001,100\n","startup":"sync-persistence","revision":14},"snap-1410":{"ledger":"id,amount\n001,999999\n","startup":"sync-persistence","revision":14}},"expected_ledger_sha":"id,amount\n001,100\n".sha256_text(),"production":{"ledger":"id,amount\n001,999999\n","startup":"sync-persistence"},"staged":{},"identity":{"compromised":true},"network_isolated":false,"services":{"identity":false,"database":false,"app":false},"observations":[]}

static func view(s: Dictionary, selected: String = "") -> Dictionary:
	var out: Dictionary = s.duplicate(true); out.erase("flags"); out.erase("world"); out.selected = selected
	var w: Dictionary = s.world
	out.records = []
	if s.kind == "advanced-hunt":
		for key in ["assets", "sessions", "tasks", "pinned"]: out.records.append(_record(key, key, JSON.stringify(w.get(key, {}), "  ")))
		out.records.append(_record("measurements", "measurements", "unauthorized=%s; business=%s" % [w.security_result, w.business_result]))
	elif s.kind == "advanced-pentest":
		for key in ["grants", "path_trace", "trace_records", "retest", "credential_bytes", "proof_bytes"]:
			if w.has(key): out.records.append(_record(key, key, JSON.stringify(w[key], "  ")))
	else:
		for key in ["snapshots", "staged", "scan", "identity", "services", "production", "observations"]:
			if w.has(key): out.records.append(_record(key, key, JSON.stringify(w[key], "  ")))
		out.records.append(_record("network", "network", "isolated=" + str(w.network_isolated)))
	var result_checks: Array = checks(s)
	for c in out.get("checks",[]):
		for r in result_checks:
			if str(r.id) == str(c.id): c.passed = bool(r.passed)
	for a in out.get("actions",[]): a.selected = str(a.id) == selected
	var groups: Dictionary = {}
	if s.kind == "advanced-hunt": groups = {"revoke_session":"gateway","restore_session":"gateway","isolate_host":"workstation","reconnect_host":"workstation","disable_task":"file-server","enable_task":"file-server","probe_security":"business","probe_business":"business"}
	elif s.kind == "advanced-pentest": groups = {"discover_assets":"employee","inspect_permissions":"share","connect_target":"share","read_credential":"share","modify_grant":"share","authenticate_service":"service-account","read_proof":"proof-file","retest_path":"proof-file"}
	else: groups = {"compare_snapshots":"backup","stage_restore":"staging","scan_stage":"staging","remove_persistence":"staging","isolate_network":"staging","start_service":"business"}
	for a in out.actions:
		if groups.has(str(a.id)): a.target = groups[str(a.id)]
	return out

static func act(s: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	var target := str(args.get("option", "")); var r: Dictionary
	if target.is_empty(): target = str(args.get("target", ""))
	if action == "pin": action = "pin_event"
	if s.kind == "advanced-hunt": r = _hunt(s,action,target)
	elif s.kind == "advanced-pentest": r = _pentest(s,action,target)
	else: r = _recovery(s,action,target)
	if bool(r.changed): s.revision = int(s.revision) + 1
	if bool(r.changed) and action not in ["probe_security","probe_business"]:
		if s.kind == "advanced-hunt": s.world.security_result = "unmeasured"; s.world.business_result = "unmeasured"
	if bool(r.changed) and action not in ["pin_event", "preserve_evidence"]:
		s.events.append({"id":"op-%d" % int(s.revision),"time":"+%dm" % (int(s.revision) * 8),"source":"console","asset":target,"detail":action + " result=" + ("completed" if bool(r.ok) else "denied") + " target=" + target,"pinned":false})
	s.last_result = r.duplicate(true); return r

static func checks(s: Dictionary) -> Array:
	var out: Array = []
	for c in s.get("checks",[]): var row: Dictionary = c.duplicate(true); row.passed = _passed(s,str(c.id)); out.append(row)
	return out

static func _hunt(s: Dictionary,a: String,t: String)->Dictionary:
	var w: Dictionary = s.world
	if a.begins_with("correlate_"):
		var c: Dictionary = w.get("correlated",{})
		c[a.trim_prefix("correlate_")] = true
		w.correlated = c
		return _ok("adv_result_"+a)
	if a == "pin_event" or a == "preserve_evidence":
		var event_id: String = t if not t.is_empty() else "evt-05"
		for event in s.events:
			if str(event.get("id","")) == event_id:
				event.pinned = true
				var pinned: Array = w.get("pinned",[])
				if not pinned.any(func(row: Dictionary): return str(row.id) == event_id): pinned.append({"id":event_id,"hash":JSON.stringify(event).sha256_text(),"bytes":JSON.stringify(event)})
				w.pinned = pinned
				return _ok("adv_result_pin_event")
		return _fail("adv_result_event_missing")
	if a == "isolate_host" or a == "contain_host":
		var host: String = t
		if host == "infected-host": host = "ws17"
		if host == "normal-host": host = "gw01"
		var assets: Dictionary = w.get("assets",{})
		if not assets.has(host): return _fail("adv_result_host_missing")
		assets[host].connected = false; w.assets = assets
		return _ok("adv_result_isolate_host")
	if a == "reconnect_host":
		var reconnect_assets: Dictionary = w.get("assets",{})
		if not reconnect_assets.has(t): return _fail("adv_result_host_missing")
		reconnect_assets[t].connected = true; w.assets = reconnect_assets
		return _ok("adv_result_reconnect_host")
	if a == "revoke_session":
		var sessions: Dictionary = w.get("sessions",{})
		if not sessions.has(t): return _fail("adv_result_session_missing")
		sessions[t].active = false; w.sessions = sessions
		return _ok("adv_result_revoke_session")
	if a == "restore_session":
		var restore_sessions: Dictionary = w.get("sessions",{})
		if not restore_sessions.has(t): return _fail("adv_result_session_missing")
		restore_sessions[t].active = true; w.sessions = restore_sessions
		return _ok("adv_result_restore_session")
	if a == "disable_task" or a == "remove_persistence":
		var tasks: Dictionary = w.get("tasks",{})
		var task_id: String = t if not t.is_empty() else "task-sync"
		if not tasks.has(task_id): return _fail("adv_result_task_missing")
		tasks[task_id].enabled = false; w.tasks = tasks
		return _ok("adv_result_disable_task")
	if a == "enable_task":
		var enable_tasks: Dictionary = w.get("tasks",{})
		if not enable_tasks.has(t): return _fail("adv_result_task_missing")
		enable_tasks[t].enabled = true; w.tasks = enable_tasks
		return _ok("adv_result_enable_task")
	if a == "probe_security":
		var sessions_now: Dictionary = w.get("sessions",{}); var tasks_now: Dictionary = w.get("tasks",{})
		var unauthorized: bool = bool(sessions_now.get("sid-r44",{}).get("active",false)) or bool(tasks_now.get("task-sync",{}).get("enabled",false))
		if unauthorized:
			w.security_failed_once = true; w.security_result = "failed"; w.observations = w.get("observations",[]) + ["unauthorized-access"]
		else: w.security_result = "passed"
		w.security_revision = s.revision + 1
		return _ok("adv_result_probe_security")
	if a == "probe_business" or a == "restore_business":
		var a_now: Dictionary = w.get("assets",{}); var ss: Dictionary = w.get("sessions",{}); var tt: Dictionary = w.get("tasks",{})
		var legitimate: bool = bool(a_now.get("gw01",{}).get("connected",false)) and bool(a_now.get("ws17",{}).get("connected",false)) and bool(a_now.get("fs02",{}).get("connected",false)) and bool(a_now.get("backup01",{}).get("connected",false)) and bool(ss.get("sid-b21",{}).get("active",false)) and bool(tt.get("task-backup",{}).get("enabled",false))
		if not legitimate: w.business_failed_once = true; w.business_result = "failed"
		else: w.business_result = "passed"
		w.business_revision = s.revision + 1
		return _ok("adv_result_probe_business")
	return _fail("adv_result_unknown_action")

static func _pentest(s: Dictionary,a: String,t: String)->Dictionary:
	var w: Dictionary = s.world
	if a == "discover_assets": w.discovered = true; return _ok("adv_result_discover_assets")
	if a == "inspect_permissions":
		if not bool(w.get("discovered",false)): return _fail("adv_result_wrong_sequence")
		w.permissions_read = true; return _ok("adv_result_inspect_permissions")
	if a == "traverse_edge" or a == "connect_target":
		if not bool(w.get("permissions_read",false)): return _fail("adv_result_wrong_sequence")
		if t == "share01" and _access(w,"employee01","share01"): w.path_trace.append("employee01->share01"); w.connected_share = true; return _ok("adv_result_connect_target")
		if t == "svc-report" and bool(w.get("credential_read",false)) and _access(w,"svc-report","evidence/proof.csv"): w.path_trace.append("share01->svc-report"); w.service_authenticated = true; return _ok("adv_result_connect_target")
		if t == "evidence/proof.csv" and bool(w.get("service_authenticated",false)) and _access(w,"svc-report",t): w.path_trace.append("svc-report->evidence/proof.csv"); w.proof_read = true; return _ok("adv_result_read_proof")
		return _fail("adv_result_denied_path")
	if a == "read_credential":
		if not bool(w.get("connected_share",false)) or t != "share01" or not _access(w, "employee01", t): return _fail("adv_result_credential_unavailable")
		w.credential_read = true; w.credential_bytes = str(w.files.get("share01/deploy.env",""))
		w.held_credentials.svc_report = _parse_token(str(w.credential_bytes))
		w.trace_records.append({"action":a,"principal":"employee01","resource":"share01/deploy.env","bytes":w.credential_bytes})
		return _ok("adv_result_read_credential")
	if a == "authenticate_service":
		if not bool(w.get("credential_read",false)) or t != "svc-report": return _fail("adv_result_authentication_denied")
		if str(w.held_credentials.get("svc_report","")) != str(w.credential): return _fail("adv_result_authentication_denied")
		w.service_authenticated = true; w.path_trace.append("share01->svc-report"); return _ok("adv_result_authenticate_service")
	if a == "read_proof":
		if not bool(w.get("service_authenticated",false)) or t != "evidence/proof.csv" or not _access(w,"svc-report",t): return _fail("adv_result_denied_path")
		w.proof_read = true; w.proof_bytes = str(w.files.get(t,"")); w.path_trace.append("svc-report->evidence/proof.csv")
		w.trace_records.append({"action":a,"principal":"svc-report","resource":t,"bytes":w.proof_bytes,"sha256":str(w.proof_bytes).sha256_text()})
		return _ok("adv_result_read_proof")
	if a == "prove_path":
		return _ok("adv_result_prove_path") if bool(w.get("proof_read",false)) else _fail("adv_result_wrong_sequence")
	if a == "modify_grant":
		if not bool(w.get("proof_read",false)): return _fail("adv_result_wrong_sequence")
		w.grant_fixed = true; w.grants.employee01 = []; w.retest_denied = false; w.legitimate_business = false; return _ok("adv_result_modify_grant")
	if a == "retest_path":
		if not bool(w.get("grant_fixed",false)): return _fail("adv_result_wrong_sequence")
		var replay: Array = []; var denied := false; var principal := "employee01"; var token := ""
		for step in w.path_trace:
			var destination := str(step).split("->")[-1]
			var allowed := false
			if destination == "share01":
				allowed = _access(w, principal, destination)
				if allowed: token = _parse_token(str(w.files.get("share01/deploy.env", "")))
			elif destination == "svc-report":
				allowed = token == str(w.credential)
				if allowed: principal = "svc-report"
			else: allowed = _access(w, principal, destination)
			replay.append({"principal":principal,"resource":destination,"allowed":allowed})
			if not allowed: denied = true; break
		var legit: bool = _access(w,"svc-report","evidence/proof.csv") and bool(w.get("service_access",false))
		w.retest = replay; w.retest_denied = denied; w.legitimate_business = legit
		return _ok("adv_result_retest_path") if denied and legit else _fail("adv_result_retest_failed")
	return _fail("adv_result_unknown_action")

static func _access(w: Dictionary, principal: String, resource: String) -> bool:
	if not w.get("grants",{}).get(principal,[]).has(resource): return false
	if resource == "evidence/proof.csv" and principal == "svc-report": return bool(w.get("service_access",false))
	return true

static func _parse_token(bytes: String) -> String:
	for line in bytes.split("\n"):
		if line.begins_with("TOKEN="): return line.trim_prefix("TOKEN=")
	return ""

static func _recovery(s: Dictionary,a: String,t: String)->Dictionary:
	var w: Dictionary = s.world
	if a == "compare_snapshots":
		if not w.snapshots.has(t): return _fail("adv_result_snapshot_missing")
		w.selected_snapshot = t; return _ok("adv_result_compare_snapshots")
	if a == "stage_restore":
		if not w.has("selected_snapshot"): return _fail("adv_result_wrong_sequence")
		w.staged = w.snapshots[w.selected_snapshot].duplicate(true); w.stage_revision = int(w.get("stage_revision",0)) + 1; w.scan = {}; w.business_observed = false; w.reconnected = false; return _ok("adv_result_stage_restore")
	if a == "scan_stage":
		if w.get("staged",{}).is_empty(): return _fail("adv_result_wrong_sequence")
		var staged: Dictionary = w.staged; w.scan = {"ledger_hash":str(staged.ledger).sha256_text(),"startup_present":str(staged.startup) != "none","revision":int(w.stage_revision),"clean":str(staged.ledger).sha256_text() == str(w.expected_ledger_sha) and str(staged.startup) == "none"}; return _ok("adv_result_scan_stage")
	if a == "repair_identity":
		w.identity.compromised = false; return _ok("adv_result_repair_identity")
	if a == "remove_persistence":
		if w.get("staged",{}).is_empty(): return _fail("adv_result_wrong_sequence")
		w.staged.startup = "none"; w.stage_revision = int(w.get("stage_revision",0)) + 1; if w.has("scan"): w.scan.stale = true; return _ok("adv_result_remove_persistence")
	if a == "isolate_network": w.network_isolated = true; return _ok("adv_result_isolate_network")
	if a == "start_service":
		if t == "identity": w.services.identity = not bool(w.identity.compromised); return _ok("adv_result_start_service")
		if t == "database":
			if not bool(w.services.identity): return _fail("adv_result_dependency_identity")
			w.services.database = str(w.staged.get("ledger","")) != ""; return _ok("adv_result_start_service")
		if t == "app":
			if not bool(w.services.database): return _fail("adv_result_dependency_database")
			w.services.app = true; return _ok("adv_result_start_service")
		return _fail("adv_result_service_missing")
	if a == "restore_business":
		if not bool(w.get("network_isolated",false)) or w.get("staged",{}).is_empty(): return _fail("adv_result_wrong_sequence")
		var clean_restore: bool = str(w.staged.get("ledger","")).sha256_text() == str(w.expected_ledger_sha) and str(w.staged.get("startup","")) == "none" and not bool(w.identity.get("compromised",true))
		w.production = w.staged.duplicate(true)
		# Startup follows the same dependency guards as the individual controls.
		_recovery(s, "start_service", "identity"); _recovery(s, "start_service", "database"); _recovery(s, "start_service", "app")
		w.business_observed = clean_restore and bool(w.services.app); return _ok("adv_result_restore_business")
	if a == "reconnect_business":
		if not bool(w.get("network_isolated",false)): return _fail("adv_result_network_open")
		var clean_reconnect: bool = not bool(w.identity.get("compromised",true)) and str(w.get("staged",{}).get("startup","")) == "none" and str(w.get("staged",{}).get("ledger","")).sha256_text() == str(w.expected_ledger_sha)
		if not clean_reconnect:
			w.reinfection_observed = true; w.production.ledger = "id,amount\n001,999999\n"; w.business_observed = false; w.observations.append("reinfected-after-reconnect"); var bad: Dictionary = _fail("adv_result_reinfection"); bad.changed = true; return bad
		if not bool(w.services.app): return _fail("adv_result_dependency_database")
		w.production = w.staged.duplicate(true); w.network_isolated = false; w.reconnected = true; w.reinfection_observed = false; w.business_observed = bool(w.services.identity) and bool(w.services.database) and bool(w.services.app); return _ok("adv_result_reconnect_business")
	return _fail("adv_result_unknown_action")

static func _passed(s: Dictionary,id: String)->bool:
	var w: Dictionary = s.world
	if s.kind == "advanced-hunt":
		if id == "scope": return ["gateway", "workstation", "fileserver"].all(func(key: String): return bool(w.get("correlated", {}).get(key, false)))
		if id == "evidence": return w.get("pinned",[]).filter(func(row: Dictionary): return str(row.get("bytes", "")).contains("sid-r44")).size() >= 2
		if id == "containment": return str(w.get("security_result","")) == "passed" and int(w.get("security_revision",-1)) >= 0
		if id == "business": return str(w.get("business_result","")) == "passed" and int(w.get("business_revision",-1)) >= 0
		if id == "false_attribution": return bool(w.get("assets",{}).get("gw01",{}).get("connected",false))
	if s.kind == "advanced-pentest":
		if id == "scope": return bool(w.get("discovered",false))
		if id == "path": return bool(w.get("proof_read",false)) and w.get("path_trace",[]).size() >= 3
		if id == "blocked": return bool(w.get("retest_denied",false))
		if id == "legitimate": return bool(w.get("legitimate_business",false))
	if s.kind == "advanced-recovery":
		if id == "snapshot": return str(w.get("staged", {}).get("ledger", "")).sha256_text() == str(w.expected_ledger_sha)
		if id == "staging": return not w.get("staged",{}).is_empty() and bool(w.get("scan",{}).get("clean",false)) and not bool(w.get("scan",{}).get("stale",false)) and int(w.get("scan", {}).get("revision", -1)) == int(w.get("stage_revision", 0))
		if id == "identity": return not bool(w.get("identity",{}).get("compromised",true))
		if id == "persistence": return str(w.get("staged",{}).get("startup","")) == "none" and bool(w.get("scan",{}).get("clean",false))
		if id == "network": return bool(w.get("reconnected",false)) or bool(w.get("network_isolated",false))
		if id == "business": return bool(w.get("business_observed",false)) and str(w.get("production",{}).get("ledger","" )).sha256_text() == str(w.get("expected_ledger_sha",""))
		if id == "reinfection": return bool(w.get("reconnected",false)) and not bool(w.get("reinfection_observed",false))
	return false
static func _requires(s: Dictionary,keys: Array)->bool:
	for key in keys: if not bool(s.flags.get(key,false)): return false
	return true
static func _mark(s: Dictionary,key: String)->void: s.flags[key] = true
static func _ok(key: String)->Dictionary: return {"ok":true,"changed":true,"minutes":8.0,"result_key":key,"result_args":[]}
static func _fail(key: String)->Dictionary: return {"ok":false,"changed":false,"minutes":0.0,"result_key":key,"result_args":[]}
static func _node(id:String,label:String,x:float,y:float)->Dictionary: return {"id":id,"label":label,"detail":label,"status_key":"adv_status_pending","x":x,"y":y}
static func _edge(a:String,b:String,label:String)->Dictionary: return {"from":a,"to":b,"label":label}
static func _action(id:String,label:String,target:String,options:Array)->Dictionary:
	var normalized: Array = []
	for option in options:
		if option is Dictionary: normalized.append(option)
		else: normalized.append({"id":str(option),"label":str(option)})
	return {"id":id,"label_key":label,"target":target,"options":normalized}
static func _check(id:String,label:String)->Dictionary: return {"id":id,"label_key":label,"passed":false}
static func _record(id:String,label:String,detail:String)->Dictionary: return {"id":id,"label":label,"detail":detail,"status_key":"adv_status_observed"}
