extends SceneTree
var ui
var game
var pc
var failures: Array[String]=[]
var capture_enabled:=false
var narrow:=false
func _init() -> void:
	capture_enabled="--capture" in OS.get_cmdline_user_args();narrow="--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func():push_error("firewall test timeout");quit(2));call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);print("FAIL ",label)
func control(id: String):return pc.widgets.browser.page.find_child(id,true,false)
func press(id: String) -> void:
	var node=control(id);check(node is BaseButton and not node.disabled,"button "+id)
	if node is BaseButton and not node.disabled:node.pressed.emit()
func choose(id: String,value: String) -> void:
	var node=control(id);check(node is OptionButton,"option "+id)
	if node is OptionButton:
		for index in node.item_count:
			if str(node.get_item_metadata(index))==value:node.select(index);node.item_selected.emit(index);return
		check(false,"option value "+value)
func edit(id: String,text: String) -> void:
	var node=control(id);check(node is LineEdit,"field "+id)
	if node is LineEdit:node.text=text;node.text_changed.emit(text)
func frames(count:=4) -> void:
	for i in count:await process_frame
func snap() -> Dictionary:return game._vm().firewall_snapshot()
func admin() -> String:return game.vm_run("curl https://admin.client.test:8443")
func business() -> String:return game.vm_run("curl https://intranet.client.test")
func rules_equal(left: Array,right: Array) -> bool:
	# Save JSON decodes integral ports as floats; compare canonical policy values.
	var policy=load("res://scripts/firewall_policy.gd")
	var l: Dictionary=policy.parse_config(policy.canonical_text({"version":2,"dns":"on","tls":"on","rules":left}))
	var r: Dictionary=policy.parse_config(policy.canonical_text({"version":2,"dns":"on","tls":"on","rules":right}))
	return str(l.error).is_empty() and str(r.error).is_empty() and policy.canonical_text(l.values)==policy.canonical_text(r.values)
func capture(label: String,visible_id: String="") -> void:
	if not capture_enabled:return
	await frames(6)
	var scroll: ScrollContainer=pc.widgets.browser.page.get_parent()
	if narrow and not visible_id.is_empty() and control(visible_id)!=null:scroll.ensure_control_visible(control(visible_id))
	else:scroll.scroll_vertical=0
	await frames(3);await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/experience/ui");DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture")
func legacy() -> void:
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../artifacts/simulator/v124/legacy-v123-firewall.json")))
	check(not saved.has("firewall_model_version"),"released v123 fixture")
	var vm=load("res://scripts/virtual_machine.gd").new();vm.setup(2,saved)
	check(int(vm.state.get("firewall_model_version",1))==1 and not vm.state.applied.has("rules"),"legacy configuration preserved")
	check(vm.probes().all(func(p):return bool(p.passed) and bool(p.fresh)),"legacy measurements stay fresh")
	check(vm.run("curl https://admin.client.test").begins_with("HTTP/1.1 403"),"legacy response contract preserved")
func run() -> void:
	legacy()
	ui=load("res://scripts/interface.gd").new();root.add_child(ui);await frames(1);game=ui._game();game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"QA storage")
	ui._new_game();game.choose_strategy("advisory");game.state.peak_profit=200000;game.state.cash=100000;game.state.skills.advisory=3;game.start_free_career()
	var offer: Dictionary={}
	for day_index in 60:
		game.state.day=day_index+1;game._make_offers()
		for item in game.state.offers:
			if str(item.case_id)=="service-2-case-2" and bool(item.get("market_available",false)):offer=item;break
		if not offer.is_empty():break
	var accepted: bool=not offer.is_empty() and game.choose_contract(str(offer.get("id","")))
	check(accepted,"real network contract accepted")
	if not accepted:quit(1);return
	game.vm_run("ssh client")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false);root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_panel("terminal");pc=ui.desktop;pc._show_app("browser");await frames()
	if not pc.windows.browser.maximized:pc.windows.browser.toggle_maximize()
	if "--console-normal" in OS.get_cmdline_user_args():
		pc.windows.browser.toggle_maximize();pc.windows.browser.size=Vector2(1100,850);await frames()
	pc._browse_url(pc.FIREWALL_URL,true);await frames()
	check(control("FirewallEdit_wan-admin")!=null and not bool(snap().pending),"WAN console backed by applied rules")
	check(admin().begins_with("HTTP/1.1 200") and business().begins_with("HTTP/1.1 200"),"actual initial exposure with working business")
	check(game.capture_baseline(),"capture full rule configuration before edits")
	press("FirewallEdit_wan-admin");choose("FirewallEditor_action","block");edit("FirewallEditor_description","WAN management blocked")
	press("FirewallNav_logs");press("FirewallNav_rules");check(str(control("FirewallEditor_description").text)=="WAN management blocked","editor draft survives navigation")
	await capture("firewall-editor","FirewallSave")
	press("FirewallSave");check(bool(snap().pending) and admin().begins_with("HTTP/1.1 200"),"save stages rules without applying")
	press("FirewallApply");check(not bool(snap().pending) and admin().contains("FIREWALL_DENIED") and business().begins_with("HTTP/1.1 200"),"apply blocks WAN administration and preserves LAN business")
	await capture("firewall-wan")
	press("FirewallAddTop");choose("FirewallEditor_action","pass");edit("FirewallEditor_source","203.0.113.0/24");edit("FirewallEditor_destination","self");edit("FirewallEditor_destination_port","8443:8444");edit("FirewallEditor_description","Approved range")
	press("FirewallSave");check(bool(pc.firewall_ui.result.get("ok",false)),"new rule receives stable id")
	var allow_id:=""
	for rule in snap().rules:
		if str(rule.description)=="Approved range":allow_id=str(rule.id)
	check(not allow_id.is_empty(),"new rule saved")
	press("FirewallApply");check(admin().begins_with("HTTP/1.1 200"),"first matching CIDR and port range passes")
	press("FirewallUp_wan-admin");press("FirewallApply");check(admin().contains("FIREWALL_DENIED"),"moving within WAN changes actual result")
	press("FirewallToggle_wan-admin");check(bool(snap().pending) and admin().contains("FIREWALL_DENIED"),"disabled pending rule does not affect traffic")
	press("FirewallApply");check(admin().begins_with("HTTP/1.1 200"),"disabled active rule is skipped")
	press("FirewallToggle_wan-admin");press("FirewallApply")
	press("FirewallClone_"+allow_id);check(snap().rules.size()==6,"clone preserves configuration as separate rule")
	var clone_id:=""
	for rule in snap().rules:
		if str(rule.id)!=allow_id and str(rule.description)=="Approved range":clone_id=str(rule.id)
	press("FirewallDelete_"+clone_id);check(control("FirewallDeleteConfirm")!=null and snap().rules.size()==6,"delete requires its UI confirmation")
	press("FirewallDeleteConfirm");check(snap().rules.size()==5 and not bool(snap().pending),"removing pending clone restores exact applied rules")
	press("FirewallNav_diagnostics");press("FirewallTraceRun");check(str(snap().last_trace.action)=="pass","real LAN trace passes")
	var fingerprint: String=game._vm()._fingerprint();press("FirewallTraceRun");check(game._vm()._fingerprint()==fingerprint,"trace logs do not invalidate evidence")
	edit("FirewallTrace_source","192.168.11.10");press("FirewallTraceRun");check(str(snap().last_trace.action)=="block" and str(snap().last_trace.rule_id)=="default","source subnet mismatch reaches default deny")
	choose("FirewallTrace_interface","wan");edit("FirewallTrace_source","203.0.113.10");edit("FirewallTrace_destination","198.51.100.1");edit("FirewallTrace_destination_port","8443");press("FirewallTraceRun");check(str(snap().last_trace.rule_id)=="wan-admin","trace identifies actual first matching rule")
	await capture("firewall-trace")
	press("FirewallNav_rules");press("FirewallEdit_wan-admin");choose("FirewallEditor_action","reject");press("FirewallSave");press("FirewallApply");check(admin().contains("FIREWALL_DENIED action=reject") and admin().contains("refused"),"reject differs from silent block")
	var valid_path: String=game.save_path;var before: Dictionary=game._vm().export_state();var clock_before:=int(game.clock_minutes());var cash_before:=int(game.state.cash)
	press("FirewallEdit_wan-admin");choose("FirewallEditor_action","pass");game.save_path="user://missing-firewall-"+str(OS.get_process_id())+"/save.json";press("FirewallSave");game.save_path=valid_path
	check(str(pc.firewall_ui.result.get("error",""))=="save_failed" and game._vm().state.fs==before.fs and game._vm().state.applied==before.applied and int(game.clock_minutes())==clock_before and int(game.state.cash)==cash_before,"save failure restores pending, active, time and cash")
	check(pc.firewall_ui.has("editor") and str(pc.firewall_ui.editor.rule.action)=="pass","save failure preserves input")
	press("FirewallSave");check(bool(snap().pending),"retry stores pending policy")
	check(game.save_game() and game.load_game(),"real save reload");pc._load_session();pc._render_firewall();check(bool(snap().pending) and admin().contains("FIREWALL_DENIED"),"reload keeps pending separate from active")
	press("FirewallRevert")
	var exact_rules: Array=snap().applied_rules.duplicate(true)
	press("FirewallNav_services");choose("FirewallTLS","off");press("FirewallServicesSave");press("FirewallApply")
	check(admin().contains("FIREWALL_DENIED") and business().begins_with("curl: (35)"),"firewall precedes TLS; permitted traffic negotiates TLS")
	choose("FirewallTLS","on");press("FirewallServicesSave");press("FirewallApply");check(rules_equal(snap().applied_rules,exact_rules),"service changes preserve all custom rules")
	game.vm_write(str(game.vm_info().config_path),"{invalid");pc._render_firewall();press("FirewallApply")
	check(str(pc.firewall_ui.result.get("error",""))=="invalid_config" and bool(game._vm().state.active) and rules_equal(snap().applied_rules,exact_rules),"invalid apply preserves active rules")
	press("FirewallRevert");check(not bool(snap().pending),"revert repairs invalid saved config")
	press("FirewallNav_rules");press("FirewallTab_lan");await capture("firewall-lan")
	for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.id))
	game.verify();check(game.state.checks.all(func(item):return bool(item.passed)),"actual probes and target verification pass")
	var VM=load("res://scripts/virtual_machine.gd");var drift: Dictionary=load("res://scripts/maintenance_incidents.gd").introduce([{"chapter":2,"vm_key":"firewall-test","vm_state":game._vm().export_state(),"scenario":game._scenario()}],"v124-drift")
	check(bool(drift.changed),"maintenance incident changes real policy")
	if bool(drift.changed):
		var incident=VM.new();incident.setup(2,drift.targets[0].vm_state);incident.run("ssh client")
		check(incident.run("curl https://intranet.client.test").contains("FIREWALL_DENIED") and not incident.evaluate().all(func(v):return bool(v)),"maintenance drift affects actual business request")
	# The selected real contract contains two sites. Both require real measurements.
	for site in range(1,game.state.targets.size()):
		check(game.select_target(site),"select remaining contracted site");game.vm_run("ssh client");game.capture_baseline()
		for rule in snap().rules:
			if str(rule.id)=="wan-admin":rule.action="block";check(bool(game.firewall_action("save_rule",{"rule":rule}).get("ok",false)),"repair remaining WAN rule")
		game.firewall_action("services",{"dns":"on","tls":"on"});game.firewall_action("apply")
		for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.id))
		game.verify()
	check(game.can_deliver() and game.deliver(),"all contracted sites measured and delivered")
	print("FIREWALL_UI failures=",failures.size());quit(0 if failures.is_empty() else 1)
