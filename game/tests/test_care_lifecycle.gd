extends SceneTree

const UI = preload("res://scripts/interface.gd")
var failures := 0
var ui
var game
var capture_enabled := false
var narrow := false

func expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)

func _init() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args(); narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func(): push_error("care lifecycle timed out"); quit(2))
	ui = UI.new()
	root.add_child(ui)
	await process_frame
	game = ui._game(); game.set_process(false)
	game.save_path = "user://care-lifecycle-"+str(OS.get_process_id())+".json"
	game.backup_path = game.save_path+".bak"
	game.previous_path = game.save_path+".previous"
	game.settings_path = game.save_path+".settings"
	ui._new_game()
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	game.choose_strategy("operations")
	expect(game.has_method("care_incident"), "care incident API")
	expect(game.has_method("open_maintenance_incident"), "incident open API")
	expect(game.has_method("can_run_maintenance"), "maintenance eligibility API")
	if failures > 0:
		_finish()
		return
	expect(game.start_free_career(), "career starts")
	var offer: Dictionary = {}
	for candidate in game.state.offers:
		if bool(candidate.get("unlocked", false)):
			offer = candidate
			break
	expect(not offer.is_empty(), "care offer exists")
	expect(game.set_offer_plan("care"), "care plan selected")
	var client := str(offer.get("client", ""))
	expect(game.choose_contract(str(offer.get("id", ""))), "care contract accepted")
	game.inspect_mission()
	await _finish_contract()
	var completed_before := int(game.state.get("contracts_completed", 0))
	expect(game.deliver(), "care contract delivered")
	expect(int(game.state.get("contracts_completed", 0)) == completed_before + 1, "normal delivery count increments once")
	var agreement: Dictionary = game.state.get("care_agreements", {}).get(client, {})
	expect(bool(agreement.get("active", false)), "care agreement active")
	var incident_day := int(agreement.get("next_incident_day", -1))
	expect(incident_day > int(game.state.get("day", 0)), "next incident day persisted")
	while int(game.state.get("day", 0)) < incident_day:
		if game.can_run_maintenance(client): expect(game.run_maintenance(client), "healthy daily inspection")
		expect(game.end_day(), "advance toward incident day")
	var latent: Dictionary = game.state.get("care_incidents", {}).get(client, {})
	expect(str(latent.get("status", "")) == "latent", "incident begins latent")
	expect(game.care_incident(client).is_empty(), "latent incident stays hidden")
	expect(game.run_maintenance(client), "inspection detects latent incident")
	var incident: Dictionary = game.care_incident(client)
	expect(str(incident.get("status", "")) == "detected", "failed inspection becomes detected incident")
	ui.open_panel("company")
	await capture("care-detected", true)
	var button = ui.modal_body.find_child("CareIncident_"+client.sha256_text().left(10),true,false)
	expect(button != null and not button.disabled,"incident action visible and enabled")
	var other_id := ""
	game.set_offer_plan("standard")
	for other in game.state.offers:
		if bool(other.get("unlocked",false)) and str(other.get("client","")) != client and game.choose_contract(str(other.id)):
			other_id = str(other.id); game.vm_run("ssh client"); game.vm_write("/home/operator/context.txt","OTHER_CONTEXT"); break
	expect(not other_id.is_empty(),"independent normal contract opened")
	var other_vm: Dictionary = JSON.parse_string(JSON.stringify(game.state.vm_states.get(other_id+"/site-0",{})))
	var saved_state: Dictionary = game.state.duplicate(true)
	var saved_path: String = game.save_path
	game.save_path = "user://missing-care-lifecycle-"+str(OS.get_process_id())+"/cannot-save.json"
	expect(not game.open_maintenance_incident(client), "save failure rejects incident open")
	expect(JSON.stringify(game.state) == JSON.stringify(saved_state), "save failure rolls back incident state")
	game.save_path = saved_path
	ui._open_maintenance_incident(client)
	expect(game.state.contract.has("maintenance_incident_id"), "incident ticket opens from UI")
	var opened: Dictionary = game.care_incident(client)
	var opened_id := str(opened.get("id", ""))
	expect(not opened_id.is_empty(), "incident id assigned")
	expect(game.open_maintenance_incident(client), "existing incident context is selected")
	expect(str(game.care_incident(client).get("id", "")) == opened_id, "duplicate open keeps incident id")
	expect(game.load_game(), "incident save/load")
	expect(str(game.care_incident(client).get("id", "")) == opened_id, "incident id survives reload")
	expect(JSON.parse_string(JSON.stringify(game.state.vm_states.get(other_id+"/site-0",{}))) == other_vm,"ticket leaves independent VM intact")
	expect(not game.can_deliver(),"uncorrected incident cannot deliver")
	expect(not game.run_maintenance(client),"working incident cannot be overwritten by inspection")
	expect(game.end_day(),"unfinished repair carries into next day")
	expect(game.open_maintenance_incident(client),"repair reselected after day change")
	expect(str(game.state.current_contract_id)==opened_id,"repair identity survives day change")
	var completed_before_repair := int(game.state.get("contracts_completed", 0))
	game.inspect_mission()
	await _finish_contract()
	var cash_before := int(game.state.cash); var credit_before := int(game.state.credit); var profit_before := int(game.state.profit)
	var before_delivery: Dictionary = game.state.duplicate(true)
	game.save_path = "user://missing-care-delivery-"+str(OS.get_process_id())+"/save.json"
	expect(not game.deliver(),"repair delivery save failure rejected")
	expect(game.state == before_delivery,"repair delivery full state rollback")
	game.save_path = saved_path
	expect(game.deliver(), "repair contract delivered")
	expect(int(game.state.cash)==cash_before and int(game.state.credit)==credit_before and int(game.state.profit)==profit_before,"covered repair has no extra fee credit or profit")
	expect(int(game.completion_receipt().xp_gain)==0 and int(game.completion_receipt().bonus)==0,"covered repair has no experience or bonus")
	expect(not game.deliver(),"repeat delivery rejected")
	var repaired: Dictionary = game.care_incident(client)
	expect(str(repaired.get("status", "")) == "recheck", "repair enters recheck")
	expect(int(game.state.get("contracts_completed", 0)) == completed_before_repair, "repair does not count as normal delivery")
	if str(repaired.get("status", "")) == "recheck":
		expect(int(game.maintenance_summary().earned)==0,"delivery alone does not earn retainer")
		ui.open_panel("terminal"); ui.desktop._show_app("receipt")
		await capture("care-recheck",false)
		var recheck = ui.desktop.widgets.receipt.footer.find_child("CareReinspect",true,false)
		expect(recheck != null and not recheck.disabled,"receipt reinspection action available")
		if recheck != null and not recheck.disabled: recheck.pressed.emit()
		expect(str(game.care_incident(client).get("status", "")) == "closed", "reinspection closes incident")
	var expected_fee := int(game.state.care_agreements[client].fee)
	expect(int(game.maintenance_summary().earned)==expected_fee,"reinspection earns agreed daily fee")
	var settled_day := int(game.state.get("retainer_settled_day", -1))
	expect(game.end_day(), "next day settles maintenance")
	expect(int(game.state.get("retainer_settled_day", -1)) != settled_day, "daily retainer settles once")
	expect(int(game.state.retainer_daily.get(str(int(game.state.day)-1),{}).get("maintenance_earned",-1))==expected_fee,"daily settlement pays exact agreed fee")
	var after_settlement := int(game.state.cash)
	game.state.day -= 1; game._apply_retainer(); game.state.day += 1
	expect(int(game.state.cash)==after_settlement,"same-day settlement cannot pay twice")
	expect(JSON.parse_string(JSON.stringify(game.state.vm_states.get(other_id+"/site-0",{})))==other_vm,"independent VM survives repair and settlement")
	var settled_again := int(game.state.get("retainer_settled_day", -1))
	expect(game.end_day(), "later day transition remains available")
	expect(int(game.state.get("retainer_settled_day", -1)) != settled_again or int(game.state.get("day", 0)) > incident_day + 1, "later settlement is day-scoped")
	print("CARE_LIFECYCLE_PASS" if failures == 0 else "CARE_LIFECYCLE_FAIL count="+str(failures))
	_finish()

func _finish_contract() -> void:
	for index in game.state.targets.size():
		game.select_target(index)
		game.vm_run("ssh client")
		var scenario: Dictionary = game._scenario()
		var config_path := str(game.vm_info().config_path)
		game.vm_write(config_path, game._vm().configuration_text(scenario.get("desired", {})))
		game.vm_run("systemctl restart "+str(game.vm_info().service))
		if int(scenario.get("chapter", game.state.chapter)) == 1:
			game.vm_run("restic backup /srv/data")
			game.vm_run("restic restore latest --target /restore")
		for probe in game.diagnostic_probes():
			if not bool(probe.get("passed", false)):
				game.run_diagnostic(str(probe.get("id", "")))
		preload("res://tests/identity_test_support.gd").authenticate_current(game)
		for probe_round in 3:
			for probe in game.diagnostic_probes():
				if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
					game.run_diagnostic(str(probe.get("id", "")))
		game.verify()
		if index < game.state.targets.size()-1:
			expect(not game.can_deliver(), "multi-target care contract remains open")
	await process_frame

func _finish() -> void:
	quit(1 if failures > 0 else 0)

func capture(label: String, company: bool) -> void:
	if not capture_enabled: return
	for i in 8: await process_frame
	if company:
		ui.modal_scroll.scroll_vertical = int(ui.modal_scroll.get_v_scroll_bar().max_value)
	else:
		var window = ui.desktop.windows.receipt
		if not window.maximized: window.toggle_maximize()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/v118/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	expect(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

