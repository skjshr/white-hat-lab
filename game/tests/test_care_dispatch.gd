extends SceneTree
var game
var office
var failures: Array[String]=[]
var capture_enabled:=false
var narrow:=false

func _init() -> void:
	capture_enabled="--capture" in OS.get_cmdline_user_args();narrow="--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func():push_error("care dispatch timeout");quit(2))
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);print("FAIL ",label)

func solve() -> void:
	game.inspect_mission()
	for index in game.state.targets.size():
		game.select_target(index);game.vm_run("ssh client")
		var scenario: Dictionary=game._scenario()
		game.vm_write(str(game.vm_info().config_path),game._vm().configuration_text(scenario.desired))
		game.vm_run("systemctl restart "+str(game.vm_info().service))
		if int(game.state.chapter)==1:
			game.vm_run("restic backup /srv/data");game.vm_run("restic restore latest --target /restore")
		for round_index in 3:
			for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.id))
		game.verify()

func tick_world(seconds: float) -> void:
	for i in int(seconds*10):
		office._sync_hired_staff()
		for actor in office.colleagues:office._animate_colleague(actor,0.1)
		game._process(0.1)

func select_owner(client: String,owner: String) -> void:
	office.ui.open_panel("company")
	var picker=office.ui.modal_body.find_child("CareOwner_"+client.sha256_text().left(10),true,false)
	check(picker!=null,"persistent owner dropdown exists")
	if picker==null:return
	for index in picker.item_count:
		if str(picker.get_item_metadata(index))==owner:picker.select(index);picker.item_selected.emit(index);break
	check(game.maintenance_owner(client)==owner,"dropdown saves recurring owner")

func capture(label: String) -> void:
	if not capture_enabled:return
	office._process(6.0)
	office.ui.open_panel("company")
	for i in 6:await process_frame
	office.ui.modal_scroll.scroll_vertical=int(office.ui.modal_scroll.get_v_scroll_bar().max_value)
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/v122/ui");DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func run() -> void:
	game=root.get_node("Game");game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"QA profile")
	var source:=ProjectSettings.globalize_path("res://../artifacts/simulator/v122/legacy-v121-care.json")
	var legacy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
	var client:=str(legacy.maintenance_targets.keys()[0])
	check(legacy.maintenance_targets[client].size()==1,"distributed v1.21 actually dropped older service")
	check(DirAccess.copy_absolute(source,ProjectSettings.globalize_path(game.save_path))==OK and game.load_game(),"load genuine old save")
	check(game._maintenance_targets_for(client).size()==2,"recover recorded older contracted service")
	check(str(game._maintenance_job_for(client).status)=="pending" and int(game.maintenance_summary().earned)==0,"new delivery did not verify restored older scope")
	var backup: Dictionary={}
	for target in game._maintenance_targets_for(client):
		if int(target.chapter)==1:backup=target
	check(not backup.is_empty() and backup.vm_state==legacy.vm_states[backup.vm_key],"recovery preserves original backup VM bytes and version")
	check(game.run_maintenance(client),"real multi-service inspection")
	check(str(game._maintenance_job_for(client).status)=="done","all recovered services pass actual VM probes")
	var original_fee:=int(game.state.care_agreements[client].fee)
	check(int(game.maintenance_summary().earned)==original_fee,"one client fee despite multiple services")
	check(game.end_day(),"new day requires new checks")
	var share_offer: Dictionary={};var other_offer: Dictionary={};var backup_offer: Dictionary={}
	for offer in game.state.offers:
		if str(offer.case_id)=="service-0-case-1":share_offer=offer
		if str(offer.case_id)=="service-0-case-0":other_offer=offer
		if str(offer.case_id)=="service-1-case-0":backup_offer=offer
	game.set_offer_plan("care")
	check(game.choose_contract(str(share_offer.id)),"new project on existing service")
	solve();check(game.deliver(),"deliver refreshed share service")
	check(game._maintenance_targets_for(client).size()==2,"replace matching service without duplicate or lost backup")
	check(str(game._maintenance_job_for(client).status)=="pending","unchanged service still needs today's check")
	check(int(game.state.care_agreements[client].fee)==original_fee,"scope merge preserves agreed fee")
	check(game.assign_maintenance(client,"aya"),"manual inspection may overlap new customer project")
	check(game.choose_contract(str(backup_offer.id)),"replace backup while inspection runs")
	solve();check(game.deliver(),"delivery atomically refreshes running inspection scope")
	check(str(game._maintenance_job_for(client).status)=="working" and game._assignments.aya.targets==game._maintenance_targets_for(client),"running worker uses updated scope")
	game._process(30)
	var refreshed_backup: Dictionary={}
	for target in game._maintenance_targets_for(client):
		if int(target.chapter)==1:refreshed_backup=target
	check(str(refreshed_backup.get("vm_key",""))==str(backup_offer.id)+"/site-0","old running job cannot restore superseded snapshot")
	check(game.choose_contract(str(other_offer.id)),"second real care client")
	solve();check(game.deliver(),"second client verified delivery")
	var other_client:=str(other_offer.client)
	check(str(game._maintenance_job_for(client).status)=="done","retained service inspection passed")
	check(game.end_day(),"next day's two pending checks")
	for agreement in game.state.care_agreements.values():agreement.next_incident_day=int(game.state.day)+5
	check(game.assign_maintenance(other_client,"aya"),"single-service inspection overlaps replacement delivery")
	for offer in game.state.offers:
		if str(offer.case_id)=="service-0-case-0":other_offer=offer;break
	check(game.choose_contract(str(other_offer.id)),"replacement project covers the entire managed scope")
	solve();check(game.deliver(),"deliver replacement of every managed target")
	check(str(game._maintenance_job_for(other_client).status)=="working" and game._assignments.aya.targets==game._maintenance_targets_for(other_client),"full replacement retains one consistent running inspection")
	game._process(30)
	check(str(game._maintenance_targets_for(other_client)[0].vm_key)==str(other_offer.id)+"/site-0","full replacement completion cannot restore old VM")
	check(game.end_day(),"new day resets both jobs after full replacement")
	office=load("res://scripts/office.gd").new();root.add_child(office);office.started=true;office.set_process(false);office.player.set_physics_process(false)
	office.ui.controls.menu.hide();office.ui.current_kind=""
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	await physics_frame;await process_frame
	select_owner(client,"sora");select_owner(other_client,"sora")
	var valid_path: String=game.save_path;var before: Dictionary=game.state.duplicate(true)
	game.save_path="user://missing-owner-"+str(OS.get_process_id())+"/save.json"
	check(not game.set_maintenance_owner(client,"aya") and game.state==before,"failed owner save rolls back")
	game.save_path=valid_path
	check(game.save_game() and game.load_game(),"owner choices survive restart")
	check(game.maintenance_owner(client)=="sora" and game.maintenance_owner(other_client)=="sora","both persistent owners retained")
	game._process(0.3)
	check(str(game._maintenance_job_for(client).status)=="pending","unregistered actor cannot auto-start")
	game.set_colleague_runtime_availability("sora",true);game.state.clock_minutes=1075;game._process(0.3)
	check(str(game._maintenance_job_for(client).status)=="pending","insufficient shift time prevents dispatch")
	game.state.clock_minutes=540;game.set_colleague_runtime_availability("sora",false);game._process(0.3)
	check(str(game._maintenance_job_for(client).status)=="pending","away from desk prevents dispatch")
	game.set_office_clock_paused(true);game.set_colleague_runtime_availability("sora",true);game._process(30)
	check(str(game._maintenance_job_for(client).status)=="pending","pause stops automatic dispatch")
	game.set_office_clock_paused(false)
	tick_world(48)
	check(str(game._maintenance_job_for(client).status)=="done" and str(game._maintenance_job_for(other_client).status)=="done","seated worker checks both owned clients sequentially")
	check(int(game.clock_minutes())==556 and float(game.state.staff.sora.minutes_used)==16.0,"two sequential jobs consume sixteen minutes of labor and clock")
	await capture("care-recurring")
	check(game.end_day(),"recurring owner continues on next day")
	game.set_maintenance_owner(client,"");game.set_maintenance_owner(other_client,"")
	game.set_colleague_runtime_availability("sora",true);game.set_colleague_runtime_availability("aya",true)
	check(game.assign_maintenance(client,"sora") and game.assign_maintenance(other_client,"aya"),"two real simultaneous jobs")
	var start:=int(game.clock_minutes());game._process(1.0);game._advance_maintenance_clock(5.0)
	var pending_state: Dictionary=game.state.duplicate(true);var pending_assignments: Dictionary=game._assignments.duplicate(true)
	game.save_path="user://missing-completion-"+str(OS.get_process_id())+"/save.json";game._process(30.0);game.save_path=valid_path
	check(game.state.cash==pending_state.cash and game.state.clock_minutes==pending_state.clock_minutes and game.state.staff==pending_state.staff and game.state.maintenance_targets==pending_state.maintenance_targets,"failed simultaneous completion saves preserve money, time, labor and assets")
	check(game._assignments==pending_assignments and game.state.maintenance_jobs==pending_state.maintenance_jobs,"failed simultaneous completions remain retryable")
	game._process(30.0)
	check(int(game.clock_minutes())==start+12,"parallel eight and twelve minute jobs overlap player time")
	check(str(game._maintenance_job_for(client).status)=="done" and str(game._maintenance_job_for(other_client).status)=="done","concurrent checks both finish")
	game.set_maintenance_owner(client,"sora");game.state.care_agreements[client].next_incident_day=int(game.state.day)+1
	check(game.end_day(),"next day introduces actual persistent drift")
	tick_world(40)
	check(str(game._maintenance_job_for(client).status)=="failed" and str(game.care_incident(client).status)=="detected","recurring check detects real VM drift")
	var failed_snapshot: Array=game.state.maintenance_targets[client].duplicate(true);tick_world(30)
	check(game.state.maintenance_targets[client]==failed_snapshot and str(game._maintenance_job_for(client).status)=="failed","failure is not automatically repaired or retried")
	await capture("care-recurring-incident")
	check(game.release_staff("sora") and game.maintenance_owner(client).is_empty(),"releasing owner clears recurring assignment")
	print("CARE_DISPATCH failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
