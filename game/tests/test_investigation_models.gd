extends SceneTree
const ADV=preload("res://scripts/advanced_operations.gd")
var failures: Array[String]=[]
var assertions:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	assertions+=1
	if not ok: failures.append(label); print("FAIL ",label)
func act(s: Dictionary,op: String,args: Dictionary={}) -> Dictionary:
	var r:=ADV.act(s,op,args); check(bool(r.get("ok",false)),str(s.kind)+" "+op); return r
func all_pass(s: Dictionary) -> bool: return ADV.checks(s).all(func(x): return x.passed)
func reject(s: Dictionary,op: String,args: Dictionary={}) -> Dictionary:
	var r:=ADV.act(s,op,args); check(not r.get("ok",true),"reject "+op); return r
func hunt() -> void:
	var s:=ADV.create("advanced-hunt")
	reject(s,"correlate_gateway"); reject(s,"correlate",{"event_ids":["evt-00","evt-04"]})
	check(s.world.links.is_empty(),"cross-session hypothesis rejected")
	act(s,"correlate",{"event_ids":["evt-00","evt-01"]})
	act(s,"correlate",{"event_ids":["evt-04","evt-05","evt-06"]})
	for id in ["evt-04","evt-05","CHG-114"]: act(s,"pin",{"target":id})
	var pinned: Dictionary=s.evidence.duplicate(true)
	check(not act(s,"pin",{"target":"evt-04"}).changed,"duplicate pin no mutation")
	act(s,"isolate_host",{"target":"gw01"}); act(s,"probe_business")
	check(not ADV.checks(s)[3].passed,"miscontainment disrupts real business")
	act(s,"reconnect_host",{"target":"gw01"}); act(s,"revoke_session",{"target":"sid-r44"}); act(s,"disable_task",{"target":"task-sync"})
	check(not ADV.checks(s)[2].passed,"actions without measurement insufficient")
	act(s,"probe_security"); act(s,"probe_business"); check(all_pass(s),"hunt complete")
	act(s,"enable_task",{"target":"task-sync"}); check(not all_pass(s),"regression invalidates test")
	act(s,"disable_task",{"target":"task-sync"}); act(s,"probe_security"); act(s,"probe_business")
	check(all_pass(s),"hunt recovery")
	for i in 104: act(s,"probe_business")
	check(s.observations.size()==96 and s.evidence==pinned,"bounded history preserves immutable evidence")
	var copy: Dictionary=JSON.parse_string(JSON.stringify(s)); check(all_pass(copy),"hunt JSON resume")
func network() -> void:
	var s:=ADV.create("advanced-pentest")
	check(not JSON.stringify(ADV.view(s)).contains("report-token-v1"),"view hides unobserved credential")
	reject(s,"read_credential",{"target":"share01"}); reject(s,"customer_fix")
	act(s,"browse",{"path":"/"}); act(s,"browse",{"path":"share01"})
	check(reject(s,"read",{"path":"evidence/proof.csv"}).data.record.status==403,"employee proof forbidden")
	check(reject(s,"read",{"path":"share01/unknown.txt"}).data.record.status==404,"arbitrary missing path")
	check(reject(s,"read",{"path":"../escape"}).data.record.status==400,"path traversal rejected")
	var leak: Dictionary=act(s,"read",{"path":"share01/deploy.env"}).data.record
	var credential: String=str(leak.data.bytes).split("TOKEN=")[1].strip_edges()
	act(s,"pin",{"target":leak.id})
	reject(s,"authenticate",{"username":"svc-report","credential":"wrong"})
	act(s,"authenticate",{"username":"svc-report","credential":credential})
	var proof: Dictionary=act(s,"read",{"path":"evidence/proof.csv"}).data.record
	act(s,"pin",{"target":proof.id}); reject(s,"submit_finding",{"evidence_ids":[leak.id,leak.id]})
	act(s,"submit_finding",{"evidence_ids":[leak.id,proof.id]})
	var submitted: Dictionary=s.world.report.evidence.duplicate(true)
	act(s,"customer_fix"); check(reject(s,"read",{"path":"evidence/proof.csv"}).data.record.status==401,"old token invalidated")
	act(s,"reset_session"); reject(s,"read",{"path":"share01/deploy.env"}); act(s,"read",{"path":"share01/daily.csv"})
	check(all_pass(s),"network complete with normal business")
	check(s.world.report.evidence==submitted,"customer fix preserves submitted bytes")
	check(not act(s,"customer_fix").changed,"customer fix idempotent")
	check(all_pass(JSON.parse_string(JSON.stringify(s))),"network JSON resume")
func recover(s: Dictionary) -> void:
	act(s,"rotate_identity",{"account":"restore-operator"}); act(s,"revoke_session",{"target":"sid-sync-17"})
	act(s,"scan_stage")
	for service in ["identity","database","app"]: act(s,"start_service",{"target":service})
	act(s,"probe_business"); act(s,"isolate_network"); act(s,"restore_business"); act(s,"reconnect_business")
func recovery() -> void:
	var s:=ADV.create("advanced-recovery")
	reject(s,"stage_restore"); reject(s,"repair_identity"); reject(s,"remove_persistence")
	act(s,"inspect_snapshot",{"target":"snap-1410"}); act(s,"stage_restore")
	var production: Dictionary=s.world.production.duplicate(true)
	act(s,"edit_stage",{"file":"ledger","content":"id,amount\n001,100\n001,100\n"}); act(s,"scan_stage")
	check(not s.world.scan.errors.is_empty(),"duplicate vouchers detected")
	check(s.world.production==production,"stage edits do not mutate production")
	reject(s,"start_service",{"target":"app"}); reject(s,"restore_business")
	act(s,"edit_stage",{"file":"ledger","content":"id,amount\n001,100\n"})
	recover(s)
	check(s.world.production.ledger.contains("999999") and not all_pass(s),"unclean startup reinfects actual ledger")
	act(s,"edit_stage",{"file":"startup","content":"none"})
	check(not ADV.checks(s)[3].passed,"stage edit requires fresh scan")
	recover(s); check(all_pass(s),"recovery complete after observed reinfection")
	check(all_pass(JSON.parse_string(JSON.stringify(s))),"recovery JSON resume")
	var alternate:=ADV.create("advanced-recovery")
	act(alternate,"inspect_snapshot",{"target":"snap-0730"}); act(alternate,"stage_restore"); recover(alternate)
	check(all_pass(alternate),"alternate actual clean content accepted")
	act(alternate,"edit_stage",{"file":"startup","content":"# maintenance\nlogrotate /var/log\n"}); recover(alternate)
	check(all_pass(alternate),"legitimate custom startup accepted without exact magic string")
func migration() -> void:
	for kind in ["advanced-hunt","advanced-pentest","advanced-recovery"]:
		var s:=ADV.create(kind); s.erase("investigation_version"); s.revision=12
		if kind=="advanced-hunt": s.world.sessions["sid-r44"].active=false; s.events[5].pinned=true
		if kind=="advanced-recovery": s.world.staged=s.world.snapshots["snap-0730"].duplicate(true); s.world.services.identity=true
		var before:=JSON.stringify(s); ADV.view(s); ADV.checks(s); check(before==JSON.stringify(s),kind+" view migration read-only")
		ADV.act(s,"unknown")
		check(int(s.investigation_version)==2,kind+" versioned migration")
		if kind=="advanced-hunt": check(not s.world.sessions["sid-r44"].active and s.evidence.has("evt-05"),"legacy real containment/evidence preserved")
		if kind=="advanced-recovery": check(not s.world.staged.is_empty() and s.world.services.identity,"legacy stage/service preserved")
func run() -> void:
	hunt(); network(); recovery(); migration()
	print("INVESTIGATION_MODELS_", "PASS" if failures.is_empty() else "FAIL", " assertions=",assertions)
	quit(0 if failures.is_empty() else 1)
