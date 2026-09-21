class_name AdvancedThreats
extends RefCounted

static func create(case_id: String) -> Dictionary:
	if case_id == "advanced-cloud":
		return _cloud_state()
		return {"case_id":case_id,"revision":0,"measurement_revision":-1,"user_password_revision":0,"apps":{"app-19":{"consent":true,"session":true},"app-72":{"consent":true,"session":true}},"audit":[{"id":"audit-1","time":"09:10","actor":"user-7","owner":"finance","grant":"app-19","permission":"ledger.read","resource":"ledger","created":"2026-09-01","publisher":"ledger-sync","approved_change":"FIN-114","approved_by":"finance-owner","actualdataread":true},{"id":"audit-2","time":"09:11","actor":"user-7","owner":"finance","grant":"app-72","permission":"ledger.read","resource":"ledger","created":"2026-09-18","publisher":"expense-viewer","approved_change":"none","approved_by":"none","actualdataread":false}],"requests":[],"events":[],"pinned":[],"attempts":[],"last_result":{}}
	if case_id == "advanced-malware":
		var specimen_bytes := "MZ\\x90\\x00PE\\x00\\x00INERT-TRAINING-FIXTURE"
		var specimen_sha := specimen_bytes.sha256_text(); var admin_sha := "admin_tool.exe:normal-fixture".sha256_text()
		return {"case_id":case_id,"revision":0,"measurement_revision":-1,"sandbox":{"network":false,"date":"2026-09-21","profile":"standard"},"artifact":{"path":"invoice_update.exe","bytes":specimen_bytes,"sha256":specimen_sha,"strings":["hxxp://dropper.invalid/a","RunOnce\\InvoiceSync"]},"endpoints":[{"id":"endpoint-a","files":[{"path":"invoice_update.exe","sha256":specimen_sha,"kind":"specimen"}],"processes":[{"name":"invoice_update.exe","kind":"specimen"}],"startup":[{"path":"RunOnce\\InvoiceSync","kind":"specimen"}],"business_ok":true},{"id":"endpoint-b","files":[{"path":"admin_tool.exe","sha256":admin_sha,"kind":"normal-admin"}],"processes":[{"name":"admin_tool.exe","kind":"normal-admin"}],"startup":[],"business_ok":true}],"observations":[],"indicators":[],"hunt_matches":[],"quarantined":[],"persistence_removed":[],"normal_admin_ok":true,"rescan_ok":false,"events":[],"attempts":[],"last_result":{}}
	if case_id == "advanced-detection":
		var detection := _detection_state()
		return detection
		return {"case_id":case_id,"revision":0,"measurement_revision":-1,"sources":{"endpoint":true,"network":true,"cloud":false},"rule":{"process":"invoice_update.exe","network_threshold":2,"exclusion":""},"notification":false,"raw_events":[{"id":"e1","time":"09:00","source":"endpoint","asset":"endpoint-b","process":"admin_tool.exe","network":0,"truth":"benign"},{"id":"e2","time":"09:01","source":"network","asset":"endpoint-b","process":"admin_tool.exe","network":1,"truth":"benign"},{"id":"e3","time":"09:02","source":"endpoint","asset":"endpoint-a","process":"invoice_update.exe","network":0,"truth":"attack"},{"id":"e4","time":"09:02","source":"network","asset":"endpoint-a","process":"invoice_update.exe","network":3,"truth":"attack"},{"id":"e5","time":"09:03","source":"endpoint","asset":"endpoint-c","process":"browser.exe","network":0,"truth":"benign"},{"id":"e6","time":"09:04","source":"network","asset":"endpoint-c","process":"browser.exe","network":1,"truth":"benign"}],"events":[],"records":[],"replay_done":false,"matched_ids":[],"false_positive":0,"false_negative":1,"attack_notified":false,"attempts":[],"last_result":{}}
	return {"case_id":case_id,"revision":0,"measurement_revision":-1,"events":[],"attempts":[],"last_result":{}}

static func _detection_state() -> Dictionary:
	return {"case_id":"advanced-detection","revision":0,"measurement_revision":-1,"sources":{"endpoint":true,"network":false,"cloud":false},"rule":{"process":"*","network_threshold":1,"exclusion":""},"notification":false,"raw_events":[{"id":"e1","time":"09:00","source":"endpoint","asset":"endpoint-b","process":"admin_tool.exe","network":0,"truth":"benign"},{"id":"e2","time":"09:01","source":"network","asset":"endpoint-b","process":"admin_tool.exe","network":1,"truth":"benign"},{"id":"e3","time":"09:02","source":"endpoint","asset":"endpoint-a","process":"invoice_update.exe","network":0,"truth":"attack"},{"id":"e4","time":"09:02","source":"network","asset":"endpoint-a","process":"invoice_update.exe","network":3,"truth":"attack"},{"id":"e5","time":"09:03","source":"endpoint","asset":"endpoint-c","process":"browser.exe","network":0,"truth":"benign"},{"id":"e6","time":"09:04","source":"network","asset":"endpoint-c","process":"browser.exe","network":1,"truth":"benign"}],"events":[],"records":[],"replay_done":false,"matched_ids":[],"false_positive":0,"false_negative":1,"attack_notified":false,"attempts":[],"last_result":{}}

static func _cloud_state() -> Dictionary:
	return {"case_id":"advanced-cloud","revision":0,"measurement_revision":-1,"world_revision":0,"user_password_revision":0,"apps":{"app-19":{"consent":true,"session":true},"app-72":{"consent":true,"session":true}},"audit":[{"id":"audit-1","time":"09:10","actor":"user-7","owner":"finance","grant":"app-19","permission":"ledger.read","resource":"ledger","created":"2026-09-01","publisher":"ledger-sync","approved_change":"FIN-114","approved_by":"finance-owner","actualdataread":true},{"id":"audit-2","time":"09:11","actor":"user-7","owner":"finance","grant":"app-72","permission":"ledger.read","resource":"ledger","created":"2026-09-18","publisher":"expense-viewer","approved_change":"none","approved_by":"none","actualdataread":false}],"requests":[],"events":[],"pinned":[],"attempts":[],"last_result":{}}

static func view(s: Dictionary, selected: String = "") -> Dictionary:
	if str(s.get("case_id","")) == "advanced-cloud": return _cloud_view(s,selected)
	if str(s.get("case_id","")) == "advanced-malware": return _malware_view(s,selected)
	if str(s.get("case_id","")) == "advanced-detection": return _detection_view(s,selected)
	return {"kind":"adv_no_case","nodes":[],"edges":[],"events":[],"records":[],"actions":[],"checks":checks(s),"last_result":s.get("last_result",{})}

static func act(s: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	var r: Dictionary
	if str(s.get("case_id","")) == "advanced-cloud": r = _cloud_act(s,action,args)
	elif str(s.get("case_id","")) == "advanced-malware": r = _malware_act(s,action,args)
	else: r = _detection_act(s,action,args)
	var ok := bool(r.get("ok",false)); var changed := bool(r.get("changed",ok)); s.attempts = s.get("attempts",[]); s.attempts.append({"action":action,"ok":ok,"result_key":r.get("result_key","")})
	if changed and str(s.case_id) == "advanced-cloud" and action in ["password_reset", "disable_grant", "revoke_grant", "restore_grant", "restore_consent", "revoke_app_session", "disable_session", "restore_app_session"]:
		s.world_revision = int(s.get("world_revision", 0)) + 1
	if changed and str(s.case_id) == "advanced-detection" and (action.begins_with("set_") or action == "toggle_source"):
		s.replay_done = false; s.attack_notified = false
	if changed:
		s.revision = int(s.get("revision",0))+1; s.measurement_revision = -1; s.last_result = {"action":action,"result_key":r.get("result_key",""),"result_args":r.get("result_args", []),"revision":s.revision}
		if ok and action in ["verify","probe","rescan"]: s.measurement_revision = s.revision
	else: s.last_result = {"action":action,"result_key":r.get("result_key",""),"revision":s.get("revision",0)}
	return {"ok":ok,"changed":changed,"minutes":int(r.get("minutes",0)),"result_key":r.get("result_key","adv_action_rejected"),"result_args":r.get("result_args",[])}

static func checks(s: Dictionary) -> Array:
	var fresh := int(s.get("measurement_revision",-1)) == int(s.get("revision",0)); var out: Array = []
	if str(s.get("case_id","")) == "advanced-cloud": out = [{"id":"business","label_key":"adv_check_cloud_business","passed":_request(s,"app-19",true)},{"id":"app","label_key":"adv_check_cloud_app","passed":_request(s,"app-72",false)},{"id":"evidence","label_key":"adv_check_cloud_evidence","passed":not s.get("pinned",[]).is_empty()}]
	elif str(s.get("case_id","")) == "advanced-malware": out = [{"id":"indicators","label_key":"adv_check_malware_indicators","passed":not s.get("indicators",[]).is_empty()},{"id":"quarantine","label_key":"adv_check_malware_quarantine","passed":not s.get("hunt_matches",[]).is_empty() and not s.get("quarantined",[]).is_empty() and bool(s.get("normal_admin_ok",false))},{"id":"rescan","label_key":"adv_check_malware_rescan","passed":bool(s.get("rescan_ok",false))}]
	else: out = [{"id":"sources","label_key":"adv_check_detection_sources","passed":bool(s.get("sources",{}).get("endpoint",false)) and bool(s.get("sources",{}).get("network",false))},{"id":"quality","label_key":"adv_check_detection_quality","passed":bool(s.get("replay_done",false)) and int(s.get("false_negative",1))==0 and int(s.get("false_positive",1))==0},{"id":"notification","label_key":"adv_check_detection_notification","passed":bool(s.get("notification",false)) and bool(s.get("attack_notified",false))}]
	for item in out: item.passed = bool(item.passed) and fresh
	return out

static func _target(a: Dictionary) -> String:
	if a.has("option"): return str(a.get("option",""))
	return str(a.get("target",""))

static func _cloud_act(s: Dictionary, action: String, a: Dictionary) -> Dictionary:
	var t := _target(a)
	if action == "password_reset": s.user_password_revision += 1; _event(s,"credential",t); return _result(true,true,2,"adv_cloud_password_reset")
	if action in ["disable_grant","revoke_grant"] and s.apps.has(t): s.apps[t].consent=false; _event(s,"grant",t); return _result(true,true,3,"adv_cloud_grant_disabled")
	if action in ["restore_grant","restore_consent"] and s.apps.has(t): s.apps[t].consent=true; _event(s,"grant_restored",t); return _result(true,true,2,"adv_cloud_grant_restored")
	if action in ["revoke_app_session","disable_session"] and s.apps.has(t): s.apps[t].session=false; _event(s,"session",t); return _result(true,true,3,"adv_cloud_session_revoked")
	if action == "restore_app_session" and s.apps.has(t): s.apps[t].session=true; _event(s,"session_restored",t); return _result(true,true,2,"adv_cloud_session_restored")
	if action in ["probe_request","request_data","one_probe"] and s.apps.has(t):
		var allowed := bool(s.apps[t].consent) and bool(s.apps[t].session); s.requests.append({"id":"request-%d"%s.requests.size(),"time":"now","app":t,"resource":"ledger","world_revision":int(s.get("world_revision", 0)),"allowed":allowed,"actualdataread":allowed}); _event(s,"request",t); return _result(true,true,2,"adv_cloud_request_allowed" if allowed else "adv_cloud_request_denied")
	if action == "pin":
		for row in s.audit:
			if str(row.id)==t: s.pinned.append(row.duplicate(true)); _event(s,"evidence",t); return _result(true,true,1,"adv_cloud_evidence_pinned")
		for row in s.requests:
			if str(row.id)==t: s.pinned.append(row.duplicate(true)); _event(s,"evidence",t); return _result(true,true,1,"adv_cloud_evidence_pinned")
		return _result(false,false,0,"adv_action_rejected")
	if action in ["inspect","inspect_audit","inspect_requests"]: _event(s,"inspect",t); return _result(true,true,1,"adv_cloud_inspected")
	if action in ["verify","probe"]: return _result(_request(s,"app-19",true) and _request(s,"app-72",false),true,2,"adv_cloud_verified")
	return _result(false,false,0,"adv_action_rejected")

static func _request(s: Dictionary, app: String, allowed: bool) -> bool:
	for row in s.get("requests",[]):
		if int(row.get("world_revision", -1)) != int(s.get("world_revision", 0)): continue
		if str(row.get("app",""))==app and bool(row.get("allowed",false))==allowed and bool(row.get("actualdataread",false))==allowed and (bool(s.apps[app].consent) and bool(s.apps[app].session)) == allowed: return true
	return false

static func _malware_act(s: Dictionary, action: String, a: Dictionary) -> Dictionary:
	var o := _target(a)
	if action in ["sandbox_network","set_network"]: s.sandbox.network=o in ["on","enabled","true"]; _event(s,"sandbox-network",o); return _result(true,true,2,"adv_malware_sandbox_changed")
	if action in ["sandbox_profile","set_profile"]: s.sandbox.profile=o; _event(s,"sandbox-profile",o); return _result(true,true,1,"adv_malware_sandbox_changed")
	if action in ["sandbox_date","set_date"]: s.sandbox.date=o; _event(s,"sandbox-date",o); return _result(true,true,1,"adv_malware_sandbox_changed")
	if action in ["run_scan","static_scan"]: s.observations.append({"mode":"static","strings":s.artifact.strings.duplicate()}); _event(s,"static-scan",s.artifact.path); return _result(true,true,3,"adv_malware_scan_complete")
	if action in ["compare_normal","compare_admin"]: _event(s,"compare","admin_tool.exe"); return _result(true,true,2,"adv_malware_comparison_complete")
	if action in ["run_live_probe","execute_sandbox"]:
		var active := str(s.sandbox.date)=="2026-09-21"; var startup := active and str(s.sandbox.profile)!="restricted"; var egress := active and bool(s.sandbox.network) and str(s.sandbox.profile)!="restricted"
		s.observations.append({"mode":"live","active":active,"network":egress,"startup":startup,"profile":s.sandbox.profile,"date":s.sandbox.date,"process":"invoice_update.exe" if active else "none","protocol":"https" if egress else "none"}); _event(s,"live-probe",o); return _result(true,true,4,"adv_malware_probe_complete")
	if action in ["derive_indicators","extract_indicators"]:
		var has_static:=false; var has_live:=false; var live_network:=false
		for observation in s.observations:
			if str(observation.mode)=="static": has_static=true
			if str(observation.mode)=="live": has_live=true; live_network=bool(observation.network)
		if not has_static or not has_live: return _result(false,false,0,"adv_malware_probe_required")
		var active_observed:=false; var observed_process:=""; var observed_startup:=false
		for observation in s.observations:
			if str(observation.mode)=="live" and bool(observation.active): active_observed=true; observed_process=str(observation.process); observed_startup=bool(observation.startup); live_network=bool(observation.network)
		if not active_observed or not observed_startup: return _result(false,false,0,"adv_malware_probe_required")
		s.indicators=[s.artifact.sha256,observed_process]
		if live_network: s.indicators.append("https")
		_event(s,"indicators","derived"); return _result(true,true,2,"adv_malware_indicators_ready")
	if action in ["hunt","hunt_indicators"]:
		if s.indicators.is_empty(): return _result(false,false,0,"adv_malware_indicators_required")
		s.hunt_matches=[]; for ep in s.endpoints:
			for f in ep.files:
				if str(f.sha256)==s.artifact.sha256: s.hunt_matches.append({"endpoint":ep.id,"path":f.path})
		_event(s,"hunt","endpoints"); return _result(true,true,3,"adv_malware_hunt_complete")
	if action in ["quarantine","quarantine_process","quarantine_file"]:
		if s.indicators.is_empty(): return _result(false,false,0,"adv_malware_indicators_required")
		var found:=false; var wanted:=_target(a); for ep in s.endpoints:
			if not wanted.is_empty() and str(ep.id)!=wanted: continue
			if action=="quarantine_file":
				for f in ep.files:
					if str(f.sha256)==str(s.artifact.sha256): ep.files.erase(f); s.quarantined.append(ep.id); found=true; break
				if found: break
			for p in ep.processes:
				if found: break
				if (str(p.name)=="invoice_update.exe" or (str(ep.id)=="endpoint-b" and wanted=="endpoint-b")): ep.processes.erase(p); ep.business_ok = str(ep.id)!="endpoint-b"; s.quarantined.append(ep.id); found=true; break
			if found: break
		return _result(found,found,3,"adv_malware_quarantined")
	if action in ["restore_quarantine","restore_process"]:
		var restored:=false; var wanted:=_target(a)
		for ep in s.endpoints:
			if not wanted.is_empty() and str(ep.id)!=wanted: continue
			if str(ep.id)=="endpoint-b" and ep.processes.is_empty(): ep.processes.append({"name":"admin_tool.exe","kind":"normal-admin"}); ep.business_ok=true; restored=true
			if str(ep.id)=="endpoint-a" and ep.processes.is_empty(): ep.business_ok=true; restored=true
		return _result(restored,restored,2,"adv_malware_quarantine_restored")
	if action in ["quarantine_persistence","remove_persistence"]:
		var found:=false; for ep in s.endpoints:
			for item in ep.startup:
				if str(item.kind)=="specimen": ep.startup.erase(item); s.persistence_removed.append(ep.id); found=true
		return _result(found,found,2,"adv_malware_persistence_removed")
	if action in ["rescan","verify"]:
		var clean:=true; var business:=true; for ep in s.endpoints:
			for p in ep.processes:
				if str(p.name)=="invoice_update.exe": clean=false
			for f in ep.files:
				if str(f.sha256)==str(s.artifact.sha256): clean=false
			for startup in ep.startup:
				if str(startup.kind)=="specimen": clean=false
			if not bool(ep.business_ok): business=false
		s.normal_admin_ok=business; s.rescan_ok=clean and business and not s.quarantined.is_empty() and not s.persistence_removed.is_empty(); _event(s,"rescan","endpoints"); return _result(s.rescan_ok,true,3,"adv_malware_rescan_complete")
	return _result(false,false,0,"adv_action_rejected")

static func _detection_act(s: Dictionary, action: String, a: Dictionary) -> Dictionary:
	var o:=_target(a)
	if action in ["set_source","toggle_source"] and s.sources.has(o): s.sources[o]=bool(a.get("enabled",not s.sources[o])); _event(s,"source",o); return _result(true,true,1,"adv_detection_source_changed")
	if action in ["set_process","set_rule_process"]: s.rule.process=o; _event(s,"rule-process",o); return _result(true,true,1,"adv_detection_rule_changed")
	if action in ["set_threshold","set_network_threshold"]: s.rule.network_threshold=int(a.get("value",o)); _event(s,"rule-threshold",o); return _result(true,true,1,"adv_detection_rule_changed")
	if action in ["set_exclusion","set_rule_exclusion"]: s.rule.exclusion=o; _event(s,"rule-exclusion",o); return _result(true,true,1,"adv_detection_rule_changed")
	if action in ["set_notification","set_notification_route"]: s.notification=o in ["on","enabled","true"] or bool(a.get("enabled",false)); _event(s,"notification",o); return _result(true,true,1,"adv_detection_notification_changed")
	if action in ["replay","replay_events"]: return _detection_replay(s)
	if action in ["verify","probe"]: return _result(s.replay_done,true,2,"adv_detection_verified")
	return _result(false,false,0,"adv_action_rejected")

static func _detection_replay(s: Dictionary) -> Dictionary:
	var matched: Array=[]; var missing:=false
	for row in s.raw_events:
		if not bool(s.sources.get(str(row.source),false)): missing=true; continue
		var key := str(row.asset)+"|"+str(row.process); var network_total:=0
		for network_row in s.raw_events:
			if str(network_row.source)=="network" and bool(s.sources.get("network",false)) and str(network_row.asset)==str(row.asset) and str(network_row.process)==str(row.process) and abs(_time_value(network_row.time)-_time_value(row.time))<=5: network_total += int(network_row.network)
		var excluded := not str(s.rule.exclusion).is_empty() and str(row.process)==str(s.rule.exclusion)
		var process_match := str(s.rule.process)=="*" or str(row.process)==str(s.rule.process)
		if process_match and network_total>=int(s.rule.network_threshold) and not excluded: matched.append(row.id)
	s.matched_ids=matched; s.records=[]; for id in matched: s.records.append({"id":id,"label":"matched-event","detail":id})
	var fp:=0; for id in matched: if not ["e3","e4"].has(id): fp+=1
	var fn:=0; for id in ["e3","e4"]: if not matched.has(id): fn+=1
	s.false_positive=fp; s.false_negative=fn; s.attack_notified=bool(s.notification) and fn==0 and not missing; s.replay_done=true; _event(s,"replay","fixtures"); return _result(fp==0 and fn==0,true,3,"adv_detection_replay_complete",[fp,fn])

static func _time_value(value: Variant) -> int:
	var parts := str(value).split(":")
	return int(parts[0])*60 + int(parts[1]) if parts.size() > 1 else int(value)

static func _cloud_view(s: Dictionary, selected: String) -> Dictionary:
	var app_target := selected if s.apps.has(selected) else "app-19"
	var records:Array=[]
	for row in s.audit: records.append({"id":row.id,"label":"adv_audit_record","detail":JSON.stringify(row),"pinnable":true})
	for row in s.requests: records.append({"id":row.id,"label":"adv_data_request","detail":JSON.stringify(row),"pinnable":true})
	var actions:Array=[{"id":"inspect_audit","label_key":"adv_inspect_audit","target":"ledger","options":[]},{"id":"password_reset","label_key":"adv_password_reset","target":app_target,"options":[]},{"id":"one_probe","label_key":"adv_probe_request","target":app_target,"options":[{"id":"app-19","label":"app-19"},{"id":"app-72","label":"app-72"}]},{"id":"disable_grant","label_key":"adv_disable_grant","target":app_target,"options":[{"id":"app-19","label":"app-19"},{"id":"app-72","label":"app-72"}]},{"id":"revoke_app_session","label_key":"adv_revoke_session","target":app_target,"options":[{"id":"app-19","label":"app-19"},{"id":"app-72","label":"app-72"}]},{"id":"restore_grant","label_key":"adv_restore_grant","target":app_target,"options":[{"id":"app-19","label":"app-19"},{"id":"app-72","label":"app-72"}]},{"id":"restore_app_session","label_key":"adv_restore_session","target":app_target,"options":[{"id":"app-19","label":"app-19"},{"id":"app-72","label":"app-72"}]},{"id":"pin","label_key":"adv_pin","target":selected,"options":[]},{"id":"verify","label_key":"adv_verify","target":"ledger","options":[]}]
	return {"kind":"adv_cloud_workbench","nodes":[{"id":"app-19","label":"app-19","detail":"consent and session","status_key":"connected" if s.apps["app-19"].consent and s.apps["app-19"].session else "blocked","x":0.15,"y":0.3},{"id":"app-72","label":"app-72","detail":"consent and session","status_key":"connected" if s.apps["app-72"].consent and s.apps["app-72"].session else "blocked","x":0.55,"y":0.3},{"id":"ledger","label":"ledger","detail":"data resource","status_key":"observed","x":0.38,"y":0.7}],"edges":[],"events":s.events,"records":records,"actions":actions,"checks":checks(s),"last_result":s.last_result}

static func _malware_view(s: Dictionary, selected: String) -> Dictionary:
	var endpoint_target := selected if selected in ["endpoint-a","endpoint-b"] else "endpoint-a"
	var ids: Array=["static_scan","compare_normal","sandbox_network","sandbox_profile","sandbox_date","execute_sandbox","derive_indicators","hunt_indicators","quarantine","quarantine_file","restore_quarantine","quarantine_persistence","rescan"]; var actions:Array=[]
	for id in ids:
		var opts:Array=[]
		if id=="sandbox_network": opts=[{"id":"on","label":"on"},{"id":"off","label":"off"}]
		elif id=="sandbox_profile": opts=[{"id":"standard","label":"standard"},{"id":"restricted","label":"restricted"}]
		elif id=="sandbox_date": opts=[{"id":"2026-09-21","label":"2026-09-21"},{"id":"2026-09-22","label":"2026-09-22"}]
		elif id in ["quarantine","quarantine_file"]: opts=[{"id":"endpoint-a","label":"endpoint-a"},{"id":"endpoint-b","label":"endpoint-b"}]
		elif id=="restore_quarantine": opts=[{"id":"endpoint-a","label":"endpoint-a"},{"id":"endpoint-b","label":"endpoint-b"}]
		var target := "artifact" if id in ["static_scan","compare_normal","sandbox_network","sandbox_profile","sandbox_date","execute_sandbox","derive_indicators"] else endpoint_target
		actions.append({"id":id,"label_key":"adv_"+id,"target":target,"options":opts})
	var records:Array=[{"id":"artifact","label":"adv_artifact_record","detail":JSON.stringify(s.artifact)}]
	for observation in s.observations: records.append({"id":"observation-%d"%records.size(),"label":"adv_observation_record","detail":JSON.stringify(observation)})
	for ep in s.endpoints: records.append({"id":ep.id,"label":"adv_endpoint_record","detail":JSON.stringify(ep)})
	return {"kind":"adv_malware_workbench","nodes":[{"id":"endpoint-a","label":"endpoint-a","detail":"files and processes","status_key":"observed","x":0.1,"y":0.3},{"id":"endpoint-b","label":"endpoint-b","detail":"files and processes","status_key":"observed","x":0.6,"y":0.3},{"id":"artifact","label":"invoice_update.exe","detail":"fixture artifact","status_key":"observed","x":0.35,"y":0.7}],"edges":[],"events":s.events,"records":records,"actions":actions,"checks":checks(s),"last_result":s.last_result}

static func _detection_view(s: Dictionary, selected: String) -> Dictionary:
	var source_target := selected if selected in ["endpoint-source","network-source"] else "endpoint-source"
	var actions:Array=[]
	for id in ["set_source","set_process","set_threshold","set_exclusion","set_notification","replay","verify"]:
		var opts:Array=[]
		if id=="set_source": opts=[{"id":"endpoint","label":"endpoint"},{"id":"network","label":"network"}]
		elif id=="set_process": opts=[{"id":"*","label":"any process"},{"id":"invoice_update.exe","label":"invoice_update.exe"},{"id":"admin_tool.exe","label":"admin_tool.exe"}]
		elif id=="set_threshold": opts=[{"id":"1","label":"1"},{"id":"2","label":"2"},{"id":"3","label":"3"}]
		elif id=="set_exclusion": opts=[{"id":"","label":"none"},{"id":"invoice_update.exe","label":"invoice_update.exe"}]
		elif id=="set_notification": opts=[{"id":"on","label":"enabled"},{"id":"off","label":"disabled"}]
		var target := source_target if id=="set_source" else ("notification" if id=="set_notification" else ("rule" if id in ["set_process","set_threshold","set_exclusion"] else ""))
		actions.append({"id":id,"label_key":"adv_"+id,"target":target,"options":opts})
	var records:Array=[]
	for row in s.raw_events: records.append({"id":row.id,"label":"adv_telemetry_record","detail":JSON.stringify(row)})
	for row in s.records: records.append(row)
	return {"kind":"adv_detection_workbench","nodes":[{"id":"endpoint-source","label":"endpoint-events","detail":"collection","status_key":"enabled" if s.sources.endpoint else "disabled","x":0.08,"y":0.2},{"id":"network-source","label":"network-events","detail":"collection","status_key":"enabled" if s.sources.network else "disabled","x":0.08,"y":0.58},{"id":"rule","label":"detection-rule","detail":str(s.rule.process),"status_key":"measured" if s.replay_done else "configured","x":0.5,"y":0.4},{"id":"notification","label":"notification","detail":"delivery","status_key":"enabled" if s.notification else "disabled","x":0.8,"y":0.4}],"edges":[],"events":s.events,"records":records,"actions":actions,"checks":checks(s),"last_result":s.last_result}

static func _event(s: Dictionary, kind: String, detail: String) -> void:
	s.events.append({"id":"%s-%d"%[kind,s.events.size()],"time":"now","source":"workbench","asset":detail,"detail":detail,"pinned":false})

static func _result(ok: bool, changed: bool, minutes: int, key: String, args: Array=[]) -> Dictionary:
	return {"ok":ok,"changed":changed,"minutes":minutes,"result_key":key,"result_args":args}
