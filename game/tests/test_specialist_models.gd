extends SceneTree
## Independent model contracts for the six specialist workspaces.
const THREATS = preload("res://scripts/advanced_threats.gd")
const ASSURANCE = preload("res://scripts/advanced_assurance.gd")
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	create_timer(45).timeout.connect(func():push_error("SPECIALIST_MODELS_TIMEOUT");quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:failures.append(label);print("FAIL ",label)

func operational(s: Dictionary) -> Dictionary:
	var result := s.duplicate(true)
	result.erase("attempts");result.erase("last_result")
	return result

func rejected(engine, s: Dictionary, action: String, args: Dictionary, label: String) -> void:
	var before := operational(s)
	var result: Dictionary = engine.act(s,action,args)
	check(not bool(result.get("ok",true)) and not bool(result.get("changed",true)) and int(result.get("minutes",-1))==0,label+" rejected without work charge")
	check(operational(s)==before,label+" leaves operational state unchanged")

func accepted(engine, s: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary=engine.act(s,action,args)
	check(bool(result.get("ok",false)),str(s.case_id)+" accepts "+action)
	return result

func resume(s: Dictionary, label: String) -> Dictionary:
	var path := "user://qa-specialist-models-"+label+".json"
	var writer := FileAccess.open(path,FileAccess.WRITE)
	check(writer!=null,label+" opens isolated JSON save")
	if writer==null:return {}
	writer.store_string(JSON.stringify(s));writer.close()
	var reader := FileAccess.open(path,FileAccess.READ)
	check(reader!=null,label+" reopens JSON save")
	if reader==null:return {}
	var restored: Variant=JSON.parse_string(reader.get_as_text());reader.close()
	var normalized: Variant=JSON.parse_string(JSON.stringify(s))
	check(restored is Dictionary and restored==normalized,label+" round-trips every model field")
	return restored if restored is Dictionary else {}

func all_passed(engine, s: Dictionary) -> bool:
	var checks: Array=engine.checks(s)
	return not checks.is_empty() and checks.all(func(row):return bool(row.passed))

func test_projections() -> void:
	for id in ["advanced-cloud","advanced-malware","advanced-detection","advanced-ddos","advanced-api","advanced-supplychain"]:
		var engine=THREATS if id in ["advanced-cloud","advanced-malware","advanced-detection"] else ASSURANCE
		var s: Dictionary=engine.create(id)
		var before := s.duplicate(true)
		var view: Dictionary=engine.view(s)
		check(s==before,id+" view is observation only")
		var w: Dictionary=view.get("workspace",{})
		check(not w.is_empty(),id+" exposes a workspace")
		match id:
			"advanced-cloud":w.apps["app-19"].consent=false
			"advanced-malware":
				check(not JSON.stringify(w.endpoints).contains('"kind"') and not w.artifact.has("bytes"),"malware projection omits classifier labels and artifact bytes")
				w.endpoints[0].files[0].path="projection-only"
			"advanced-detection":
				check(w.events.all(func(row):return not row.has("truth")),"detection raw projection hides fixture truth")
				w.events[0].process="projection-only";w.rule.process="projection-only"
			"advanced-ddos":
				check(w.session.is_empty() and w.task.is_empty(),"DDoS inspection gates sensitive operational detail")
				w.rule.limit=1
			"advanced-api":
				check(w.policy.is_empty() and w.requests.is_empty() and w.jobs.is_empty() and not w.has("invoices"),"API starts without unobserved resource bodies or policy")
				w.users.alice.role="projection-only"
			"advanced-supplychain":
				check(w.pipeline.is_empty(),"supply pipeline requires inspection")
				w.artifacts["pkg-41"].bytes="projection-only"
		check(s==before,id+" nested projection cannot mutate model")

func test_cloud() -> void:
	var s:=THREATS.create("advanced-cloud")
	s.ledger_bytes="entry,department,amount\nL-QA,finance,731\n"
	rejected(THREATS,s,"probe_request",{"target":"missing-app"},"unknown cloud application")
	accepted(THREATS,s,"probe_request",{"target":"app-72"})
	var first: Dictionary=s.requests.back().duplicate(true)
	check(int(first.status)==200 and str(first.body)==str(s.ledger_bytes) and str(first.sha256)==str(s.ledger_bytes).sha256_text(),"cloud response contains actual ledger bytes and digest")
	accepted(THREATS,s,"disable_grant",{"target":"app-72"})
	accepted(THREATS,s,"probe_request",{"target":"app-72"})
	var denied: Dictionary=s.requests.back()
	check(int(denied.status)==403 and not bool(denied.actualdataread) and str(denied.sha256).is_empty() and not str(denied.body).contains("L-QA"),"revoked grant prevents ledger contents and digest disclosure")
	check(s.requests[0]==first,"later permission changes preserve original HTTP observation")
	accepted(THREATS,s,"probe_request",{"target":"app-19"})
	accepted(THREATS,s,"pin",{"target":"audit-2"})
	accepted(THREATS,s,"verify")
	check(all_passed(THREATS,s),"fresh cloud requests verify allowed business and denied unapproved application")
	s=resume(s,"cloud")
	check(all_passed(THREATS,s) and s.requests[0]==JSON.parse_string(JSON.stringify(first)),"cloud saved response and current measurements reopen")
	accepted(THREATS,s,"restore_grant",{"target":"app-72"})
	check(not all_passed(THREATS,s) and not bool(THREATS.view(s).workspace.fresh),"grant restoration stales old cloud measurements")
	check(not bool(THREATS.act(s,"verify").ok),"old denied response cannot verify reopened grant")

func test_sandbox_configuration() -> void:
	var s:=THREATS.create("advanced-malware")
	for date in ["2026-99-99","abcd-ef-gh","2026-02-30","2025-02-29"]:
		rejected(THREATS,s,"configure_sandbox",{"date":date,"profile":"standard","network":true},"invalid calendar date "+date)
	rejected(THREATS,s,"configure_sandbox",{"date":"2026-09-21","profile":"unknown","network":true},"unknown sandbox profile")
	rejected(THREATS,s,"configure_sandbox",{"date":"2026-09-21","profile":"standard","network":"true"},"non-boolean sandbox network")
	var before:=operational(s)
	var unchanged:=THREATS.act(s,"configure_sandbox",s.sandbox.duplicate(true))
	check(bool(unchanged.ok) and not bool(unchanged.changed) and int(unchanged.minutes)==0 and operational(s)==before,"unchanged sandbox settings do not charge or mutate")
	accepted(THREATS,s,"configure_sandbox",{"date":"2024-02-29","profile":"restricted","network":true})
	accepted(THREATS,s,"execute_sandbox")
	check(not bool(s.observations.back().active) and not bool(s.observations.back().network),"valid different execution date suppresses scheduled specimen behavior")
	accepted(THREATS,s,"configure_sandbox",{"date":"2026-09-21","profile":"standard","network":true})
	accepted(THREATS,s,"execute_sandbox")
	check(bool(s.observations.back().active) and bool(s.observations.back().network) and bool(s.observations.back().startup),"atomic sandbox fields drive actual observed behavior")
	accepted(THREATS,s,"configure_sandbox",{"date":"2026-09-21","profile":"restricted","network":true})
	accepted(THREATS,s,"execute_sandbox")
	check(bool(s.observations.back().active) and not bool(s.observations.back().network) and not bool(s.observations.back().startup),"restricted profile suppresses egress and persistence")
	resume(s,"sandbox")

func prepare_malware() -> Dictionary:
	var s:=THREATS.create("advanced-malware")
	accepted(THREATS,s,"run_scan");accepted(THREATS,s,"execute_sandbox")
	accepted(THREATS,s,"derive_indicators");accepted(THREATS,s,"hunt_indicators")
	return s

func test_quarantine_restore() -> void:
	var s:=prepare_malware()
	var original: Dictionary=s.endpoints[0].files[0].duplicate(true)
	rejected(THREATS,s,"remove_persistence",{"target":"bogus"},"unknown persistence endpoint")
	accepted(THREATS,s,"quarantine_file",{"target":"endpoint-a"})
	var key: String="endpoint-a/files/"+str(original.path)
	check(s.endpoints[0].files.is_empty() and s.quarantine_store[key].item==original,"quarantine retains exact removed file metadata")
	rejected(THREATS,s,"quarantine_file",{"target":"endpoint-a"},"repeated file quarantine does not remove a process")
	check(s.endpoints[0].processes.size()==1,"file quarantine leaves running process for explicit containment")
	var projected: Dictionary=THREATS.view(s).workspace.quarantine
	check(not projected[key].item.has("kind") and s.quarantine_store[key].item.has("kind"),"quarantine view hides classifier without changing restore payload")
	projected[key].item.sha256="projection-only"
	check(s.quarantine_store[key].item==original,"quarantine projection cannot alter held bytes metadata")
	s=resume(s,"quarantine")
	# Collision is an independently created replacement at the original path.
	var collision := {"path":original.path,"sha256":"replacement".sha256_text(),"kind":"normal-admin"}
	s.endpoints[0].files.append(collision)
	rejected(THREATS,s,"restore_quarantined_item",{"target":key},"restore refuses existing-path collision")
	check(s.endpoints[0].files[0]==collision and s.quarantine_store[key].item==original,"collision preserves replacement and quarantine payload")
	s.endpoints[0].files.clear()
	accepted(THREATS,s,"restore_quarantined_item",{"target":key})
	check(s.endpoints[0].files==[original] and not s.quarantine_store.has(key),"restore consumes held item and restores exact file")
	rejected(THREATS,s,"restore_quarantined_item",{"target":key},"already restored item")
	accepted(THREATS,s,"quarantine_process",{"target":"endpoint-b"})
	check(not bool(s.endpoints[1].business_ok) and s.endpoints[1].processes.is_empty(),"normal process quarantine has a real business consequence")
	accepted(THREATS,s,"restore_quarantined_item",{"target":"endpoint-b/processes/admin_tool.exe"})
	check(bool(s.endpoints[1].business_ok) and str(s.endpoints[1].processes[0].name)=="admin_tool.exe","selected normal-process restore recovers business")
	accepted(THREATS,s,"quarantine_file",{"target":"endpoint-a"})
	accepted(THREATS,s,"quarantine_process",{"target":"endpoint-a"})
	accepted(THREATS,s,"remove_persistence",{"target":"endpoint-a"})
	accepted(THREATS,s,"rescan")
	check(all_passed(THREATS,s),"targeted containment supports fresh malware verification")
	s=resume(s,"malware-clean")
	accepted(THREATS,s,"restore_quarantined_item",{"target":key})
	check(not all_passed(THREATS,s) and not bool(s.rescan_ok),"restoring specimen stales clean measurement")
	check(not bool(THREATS.act(s,"rescan").ok),"rescan detects restored specimen")

func test_detection() -> void:
	var s:=THREATS.create("advanced-detection")
	var good: Dictionary={"process":"invoice_update.exe","threshold":2,"exclusion":"","sources":{"endpoint":true,"network":true,"cloud":false},"notification":true}
	for invalid in [{"threshold":0},{"threshold":1001},{"threshold":1.5},{"sources":{"endpoint":false,"unknown":true}},{"sources":{"network":"yes"}},{"sources":[]},{"notification":"yes"},{"process":""}]:
		var args:=good.duplicate(true);args.merge(invalid,true)
		rejected(THREATS,s,"configure_rule",args,"invalid atomic rule "+JSON.stringify(invalid))
	var revision:=int(s.revision)
	accepted(THREATS,s,"configure_rule",good)
	check(int(s.revision)==revision+1 and s.sources==good.sources and str(s.rule.process)==str(good.process) and bool(s.notification),"valid atomic rule writes all fields once")
	accepted(THREATS,s,"replay");accepted(THREATS,s,"verify")
	check(all_passed(THREATS,s) and s.matched_ids==["e3","e4"],"configured correlation matches actual attack events without false positives")
	var before:=operational(s)
	var same:=THREATS.act(s,"configure_rule",good)
	check(bool(same.ok) and not bool(same.changed) and int(same.minutes)==0 and operational(s)==before and all_passed(THREATS,s),"unchanged rule keeps measured result and does not charge")
	s=resume(s,"detection")
	before=operational(s)
	same=THREATS.act(s,"configure_rule",good)
	check(bool(same.ok) and not bool(same.changed) and operational(s)==before and all_passed(THREATS,s),"same rule remains unchanged after JSON numeric normalization")
	var changed:=good.duplicate(true);changed.threshold=4
	accepted(THREATS,s,"configure_rule",changed)
	check(not bool(s.replay_done) and not bool(s.attack_notified) and not all_passed(THREATS,s),"rule mutation invalidates replay and notification measurements")
	check(not bool(THREATS.act(s,"replay").ok) and int(s.false_negative)==2,"changed threshold has a real missed-detection consequence")

func http(s: Dictionary, actor: String, operation: String, resource := "") -> Dictionary:
	accepted(ASSURANCE,s,"request",{"target":resource,"option":actor+"|"+operation})
	return ASSURANCE.view(s).workspace.requests.back()

func test_api_list() -> void:
	var s:=ASSURANCE.create("advanced-api")
	var original: Dictionary=s.model.invoices.duplicate(true)
	var own:=http(s,"alice","list","INV-S01")
	var rows: Variant=JSON.parse_string(str(own.response.body))
	check(int(own.response.status)==200 and rows is Array and rows.size()==1 and str(rows[0].id)=="INV-N01","invoice list returns actor tenant despite unrelated target")
	check(s.model.proofs.is_empty() and ASSURANCE.view(s).workspace.policy.is_empty(),"list does not manufacture cross-tenant bypass proof")
	var south:=http(s,"beth","list")
	check(str(south.response.body).contains("INV-S01") and not str(south.response.body).contains("INV-N01"),"second tenant sees its own actual invoice")
	var unknown:=http(s,"unknown","list")
	check(int(unknown.response.status)==401 and not str(unknown.response.body).contains("INV-"),"unknown actor cannot list resource data")
	check(s.model.invoices==original and s.model.jobs.is_empty(),"listing and denied listing do not mutate invoice or export data")
	rejected(ASSURANCE,s,"request",{"target":"INV-N01","option":"alice"},"malformed HTTP operation")
	var bypass:=http(s,"alice","read","INV-S01")
	check(int(bypass.response.status)==200 and s.model.proofs.has("tenant"),"real cross-tenant read retains an observed proof")
	accepted(ASSURANCE,s,"set_policy",{"target":"api01","option":"tenant|enforce"})
	check(int(http(s,"alice","read","INV-S01").response.status)==403,"enforced policy denies observed foreign invoice read")
	check(int(http(s,"alice","list").response.status)==200,"tenant repair preserves normal list operation")
	s=resume(s,"api")
	check(ASSURANCE.view(s).workspace.requests.size()==6,"API observation history reopens intact")

func test_traffic_history() -> void:
	var s:=ASSURANCE.create("advanced-ddos")
	rejected(ASSURANCE,s,"apply_rule",{"target":"waf01","option":"/unknown|limit|20"},"unknown WAF route")
	accepted(ASSURANCE,s,"measure")
	var original: Dictionary=s.traffic_history[0].duplicate(true)
	check(float(original.result.load)>float(original.result.capacity) and not bool(original.result.checkout),"traffic history records observed overload")
	accepted(ASSURANCE,s,"apply_rule",{"target":"waf01","option":"/search|limit|20"})
	check(s.measurements.is_empty() and s.traffic_history[0]==original,"rule change stales live measurement but retains prior traffic")
	accepted(ASSURANCE,s,"measure")
	check(bool(s.traffic_history.back().result.checkout) and str(s.traffic_history.back().rule.route)=="/search","traffic history records applied rule with resulting business availability")
	var projected: Dictionary=ASSURANCE.view(s).workspace
	projected.history[0].result.load=-1
	check(s.traffic_history[0]==original,"traffic projection cannot rewrite historical evidence")
	for _index in 35:ASSURANCE.act(s,"measure")
	check(s.traffic_history.size()==32 and int(s.traffic_history.front().clock)<int(s.traffic_history.back().clock),"traffic history remains bounded and chronological")
	s=resume(s,"ddos")
	check(s.traffic_history.size()==32 and s.traffic_history.back().result.checkout,"bounded traffic history reopens with results intact")
	accepted(ASSURANCE,s,"apply_rule",{"target":"waf01","option":"*|block|0"})
	check(s.measurements.is_empty(),"subsequent traffic change cannot reuse old availability measurement")

func test_supply_projection() -> void:
	var s:=ASSURANCE.create("advanced-supplychain")
	accepted(ASSURANCE,s,"inspect",{"target":"build01"})
	var w: Dictionary=ASSURANCE.view(s).workspace
	check(not w.pipeline.is_empty() and w.artifacts["pkg-42"].bytes.contains("remote_sync"),"inspected supply workspace shows actual pipeline and artifact bytes")
	w.pipeline.session=false
	check(bool(s.model.pipeline_session),"pipeline projection is independent")
	accepted(ASSURANCE,s,"revoke",{"target":"build01","option":"runner-session-19"})
	accepted(ASSURANCE,s,"remove_hook",{"target":"build01"})
	accepted(ASSURANCE,s,"build",{"target":"build01"})
	check(not str(s.model.artifacts[str(s.model.last_build)].bytes).contains("remote_sync"),"pipeline repair changes generated artifact bytes")
	s=resume(s,"supply")
	check(ASSURANCE.view(s).workspace.last_build==s.model.last_build,"supply workspace reopens selected build")

func run() -> void:
	if not str(root.get_node("Game").save_path).begins_with("user://qa-"):quit(2);return
	test_projections();test_cloud();test_sandbox_configuration();test_quarantine_restore();test_detection();test_api_list();test_traffic_history();test_supply_projection()
	print("SPECIALIST_MODELS ","PASS" if failures.is_empty() else "FAIL"," assertions=",assertions," failures=",failures)
	quit(0 if failures.is_empty() else 1)
