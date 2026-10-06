extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var profile := str(OS.get_process_id())
var capture_enabled := "--capture" in OS.get_cmdline_user_args()
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(180.0).timeout.connect(func(): push_error("endpoint remediation UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count: int = 4) -> void:
	for _i in count: await process_frame

func control(id: String):
	return pc.widgets.browser.page.find_child(id, true, false) if pc != null and pc.widgets.has("browser") else null

func press_id(id: String, label: String = "") -> void:
	var node = control(id)
	check(node is BaseButton, label if not label.is_empty() else "control "+id)
	if node is BaseButton:
		check(not node.disabled, "enabled "+id)
		if not node.disabled: node.pressed.emit()

func reveal(id: String) -> void:
	var node = control(id)
	if not node is Control: return
	var parent: Node = node.get_parent()
	while parent != null and not parent is ScrollContainer: parent=parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(node)
	await frames(3)

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(8); await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/remediation/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	check(get_root().get_texture().get_image().save_png(folder.path_join(label+suffix+".png")) == OK, "capture "+label)

func _snapshot() -> Dictionary:
	return game._vm().edr_snapshot() if game != null and game._vm() != null else {}

func _files_for(device: String) -> Array:
	return game._vm().state.get("edr_files", []).filter(func(item): return item is Dictionary and str(item.get("device", "")) == device)

func _find_file(device: String, name: String) -> Dictionary:
	for item in _files_for(device):
		if str(item.get("name", "")) == name: return item
	return {}

func _select_device(device: String) -> void:
	if control("EdrDevice_"+device) == null and control("EdrView_devices") != null: press_id("EdrView_devices", "endpoint devices view"); await frames(5)
	if control("EdrBackDevices") != null: press_id("EdrBackDevices", "back to endpoint inventory"); await frames(5)
	press_id("EdrDevice_"+device, "select "+device); await frames(6)

func _scan(device: String) -> void:
	press_id("EdrScan_"+device, "scan "+device); await frames(6)

func run() -> void:
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames(4)
	game = ui._game(); game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "QA storage isolation")
	if not failures.is_empty():
		_finish()
		return
	ui._new_game()
	check(game.choose_strategy("response") and game.start_free_career(), "career started")
	game.state.peak_profit=18000; game.state.skills.response=2; game._make_offers()
	var offer_id := ""
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == "endpoint-recovery":
			offer.market_available=true; offer_id = str(offer.get("id", "")); break
	check(not offer_id.is_empty() and game.choose_contract(offer_id), "new endpoint recovery offer accepted")
	if not game.state.accepted: _finish(); return
	game.inspect_mission(); game.vm_run("ssh client")
	check(bool(game._vm().state.get("scenario",{}).get("edr_recovery_required",false)), "recovery scenario enabled")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1280,720)
	# Graphics._sync_surface skips the headless display. Match the native logical
	# viewport too, otherwise a 960-pixel window still lays out a 1280-pixel canvas.
	root.content_scale_size = root.size
	await frames(3)
	ui.open_panel("terminal"); pc=ui.desktop; pc._show_app("browser"); await frames(4)
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	pc._browse_url(pc.EDR_URL, true); await frames(8)
	check(control("EdrRecoveryInventoryTab") != null and control("EdrDevice_pc_a") != null and control("EdrDevice_pc_b") != null, "endpoint recovery inventory")
	var map_work: String=JSON.stringify(game.state.work,"",true)
	var map_vm: String=JSON.stringify(game._vm().export_state(),"",true)
	pc._render_endpoint();await frames(4)
	check(JSON.stringify(game.state.work,"",true)==map_work and JSON.stringify(game._vm().export_state(),"",true)==map_vm,"workflow map does not measure, charge or repair")
	for id in ["EdrBusinessProbe_pc_a","EdrDevice_pc_a","EdrTrace_pc_a"]:
		var object=control(id)
		check(object is Control and object.get_global_rect().end.x<=root.size.x+2,"workflow object fits "+id)
	await capture("inventory")
	var pointer_before := root.get_mouse_position(); press_id("EdrDevice_pc_a", "open PC-A"); await frames(6); var pointer_after := root.get_mouse_position(); check(pointer_before.distance_to(pointer_after) <= 1.0, "device selection does not move pointer")
	check(control("EdrRecoveryTabs") != null and control("RecoveryTab_timeline") != null and control("RecoveryTab_files") != null, "timeline and files tabs")
	press_id("EdrCollect", "collect endpoint evidence"); await frames(6)
	var original := str(game._vm().state.get("fs",{}).get("/var/log/evidence.log", "")); check(not original.is_empty(), "source evidence exists")
	press_id("EdrScan_pc_a", "scan PC-A"); await frames(6)
	var snap := _snapshot(); var scan_a: Dictionary = snap.get("recovery_scans",snap.get("scans",{})).get("pc_a",{})
	check(int(scan_a.get("threat_count",0)) > 0, "PC-A scan finds actual threat")
	var events_file = control("RecoveryTab_timeline"); if events_file != null: press_id("RecoveryTab_timeline", "timeline tab")
	await frames(4)
	var file_event = control("RecoveryEventFile_pc_a-sync")
	check(file_event != null, "timeline links sync-agent file")
	if file_event != null: (file_event as BaseButton).pressed.emit(); await frames(5)
	check(control("EdrRecoveryFileMetadata") != null and control("EdrQuarantine_pc_a-sync") != null, "sync-agent file profile")
	await capture("file-profile")
	check(pc.widgets.browser.page.get_global_rect().end.x <= root.size.x+2,"file profile fits viewport width")
	var before_state := JSON.stringify(game._vm().export_state(),"",true); var old_save: String = game.save_path; var old_backup: String = game.backup_path; var old_previous: String = game.previous_path; var old_settings: String = game.settings_path
	var before_work: String=JSON.stringify(game.state.work,"",true);var before_clock: int=int(game.state.clock_minutes)
	game.save_path="user://qa-remediation-save-failure-"+profile+"/missing/state.json"; game.backup_path=game.save_path+".bak"; game.previous_path=game.save_path+".previous"; game.settings_path=game.save_path+".settings"
	press_id("EdrQuarantine_pc_a-sync", "quarantine save failure"); await frames(6)
	var failed_output: Dictionary = pc.edr_ui.get("output",{})
	check(int(failed_output.get("code",0))==507, "quarantine save failure code"); check(JSON.stringify(game._vm().export_state(),"",true)==before_state, "quarantine save failure rollback")
	check(JSON.stringify(game.state.work,"",true)==before_work and int(game.state.clock_minutes)==before_clock,"failed save rolls back compensation and elapsed time")
	game.save_path=old_save; game.backup_path=old_backup; game.previous_path=old_previous; game.settings_path=old_settings
	# Desktop notifications are a status label; Node.notification is a method.
	if is_instance_valid(pc.status): pc.status.hide()
	press_id("EdrQuarantine_pc_a-sync", "quarantine malicious sync-agent"); await frames(6)
	press_id("RecoveryBackFiles"); await frames(4)
	var file_search = control("EdrRecoveryFileSearch")
	check(file_search is LineEdit,"file search available")
	if file_search is LineEdit:
		file_search.grab_focus(); file_search.text="backup"; file_search.caret_column=6; file_search.text_changed.emit("backup"); await frames(3)
		game.changed.emit(); await frames(3)
		check(is_instance_valid(file_search) and file_search.has_focus() and file_search.caret_column==6,"file search keeps input focus and caret")
		check(control("EdrRecoveryFile_pc_a-sync")==null and control("EdrRecoveryFile_pc_a-backup")!=null,"file search filters actual rows")
		file_search.text="";file_search.text_changed.emit("")
	await reveal("EdrRecoveryFile_pc_a-sync"); await capture("files")
	snap=_snapshot(); var q: Array=snap.get("recovery_quarantine",snap.get("quarantine",[])); check(q.size()==1, "one quarantine record"); check(not game._vm().state.fs.has("/endpoints/pc_a/sync-agent.exe"), "quarantine removes actual bytes")
	press_id("EdrScan_pc_a", "scan quarantined PC-A"); await frames(5); snap=_snapshot(); scan_a=snap.get("recovery_scans",snap.get("scans",{})).get("pc_a",{}); check(int(scan_a.get("threat_count",0))==0, "quarantine scan is clean")
	press_id("EdrIsolate_pc_a", "isolate PC-A"); await frames(4); if control("EdrRelease_pc_a") != null: press_id("EdrRelease_pc_a", "release PC-A"); await frames(4)
	await _select_device("pc_b"); press_id("RecoveryTab_files", "PC-B files"); await frames(5)
	check(control("EdrRecoveryFile_pc_b-backup") != null, "PC-B backup file row")
	if control("EdrRecoveryFile_pc_b-backup") != null: press_id("EdrRecoveryFile_pc_b-backup", "open backup file"); await frames(4)
	press_id("EdrQuarantine_pc_b-backup","quarantine legitimate unsigned backup"); await frames(5)
	check(str(game.vm_run("curl https://edr.client.test/pc-b/business")).contains("503 Service Unavailable"),"wrong quarantine interrupts actual business")
	press_id("EdrView_actions","action history"); await frames(5)
	var backup_id := 0
	for record in _snapshot().get("quarantine",[]):
		if str(record.get("file_id",""))=="pc_b-backup": backup_id=int(record.id)
	check(backup_id>0,"legitimate quarantine recorded")
	await reveal("EdrRestore_"+str(backup_id)); await capture("action-history")
	press_id("EdrRestore_"+str(backup_id),"undo legitimate quarantine"); await frames(5)
	check(str(game.vm_run("curl https://edr.client.test/pc-b/business")).contains("200 OK"),"undo restores business application")
	check(str(game._vm().state.fs.get("/var/log/evidence.log",""))==original and str(game._vm().state.fs.get("/evidence/original.log",""))==original,"all UI actions preserve evidence bytes")
	await _select_device("pc_b"); await _scan("pc_b")
	press_id("EdrView_devices"); await frames(4); await capture("restored-devices")
	check(game.save_game() and game.load_game(),"remediated case survives actual save reload")
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.get("id", "")))
	game.verify()
	check(not game.can_deliver(),"first site alone cannot complete two-site engagement")
	check(pc._select_target(1),"select press-room through desktop session");await frames(5)
	game.vm_run("ssh client");pc._show_app("browser");pc._browse_url(pc.EDR_URL,true);await frames(5)
	check(not _snapshot().get("files",[]).any(func(item):return str(item.get("name",""))=="sync-agent.exe"),"press-room has no injected infection")
	await _select_device("pc_a")
	press_id("EdrCollect");await frames(4)
	await _scan("pc_a");press_id("EdrRelease_pc_a");await frames(4)
	press_id("EdrBusinessProbe_pc_a");await frames(4)
	await _scan("pc_a")
	var business_result = control("EdrBusinessResult_pc_a")
	check(business_result is Label and "200 OK" in business_result.text and not "変更前" in business_result.text,"scan alone keeps the business connection observation current")
	await _select_device("pc_b");await _scan("pc_b")
	for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.get("id","")))
	game.verify();check(game.can_deliver(),"both sites with fresh diagnostics permit delivery")
	var impact_cost: int=preload("res://scripts/endpoint_engagement.gd").total_cost(game.state.work.get("endpoint_impact",{}))
	check(impact_cost>0,"response order leaves real compensation expense")
	check(game.deliver(), "endpoint recovery delivers through Game")
	check(int(game.state.last_receipt.cost)==700+impact_cost and game.state.last_receipt.endpoint_impact==game.state.history.back().endpoint_impact,"receipt and history retain compensation without double charging")
	_finish()

func _finish() -> void:
	for failure in failures: push_error("ENDPOINT_REMEDIATION_UI: "+failure)
	print("ENDPOINT_REMEDIATION_UI_", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
