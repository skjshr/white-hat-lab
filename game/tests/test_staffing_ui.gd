extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	for _i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/ui-refinement-20260922/customer-care")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func _init() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("staffing UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL: ",label)

func press(parent: Node, button_name: String) -> bool:
	var button = parent.find_child(button_name,true,false)
	if button == null or not button is Button or button.disabled: return false
	button.pressed.emit()
	return true

func run() -> void:
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui)
	await process_frame
	game = ui._game(); game.set_process(false)
	game.save_path = "user://qa-staffing-ui-"+str(OS.get_process_id())+".json"
	game.backup_path = game.save_path+".bak"; game.previous_path = game.save_path+".previous"; game.settings_path = game.save_path+".settings"
	ui._new_game()
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.guided_intro.skip()
	check(game.choose_strategy("advisory") and game.start_free_career(),"career setup")
	game.state.cash = 30000
	check(game.buy_equipment("teamdesk"),"desk bought")
	game.advance_delivery(30.0)
	check(game.take_delivery("teamdesk") and game.begin_delivery_placement("teamdesk") and game.place_delivery("teamdesk",game.equipment_slot("teamdesk")),"desk received and installed")
	ui.open_panel("staffing"); await process_frame
	check(press(ui.modal,"Hire_mio"),"hire button active and executed")
	await process_frame
	check(game.team_members().size()==3 and int(game.staff_summary().count)==1,"additional member in roster")
	game.state.market_day = int(game.state.day)
	game.state.market_leads = ["service-0-case-0"]
	game._make_offers()
	var offer: Dictionary = {}
	for item in game.state.offers:
		if str(item.get("case_id", "")) == "service-0-case-0" and bool(item.get("unlocked",false)) and bool(item.get("market_available", false)): offer=item; break
	check(not offer.is_empty(),"single-site file service fixture")
	if offer.is_empty(): finish(); return
	check(game.set_offer_plan("care") and game.choose_contract(str(offer.id)),"real care contract accepted")
	ui.open_panel("terminal"); pc=ui.desktop; pc._show_app("team"); await process_frame
	check(pc.widgets.team.cards.size()==3,"team UI includes hired member")
	check(press(pc.widgets.team.body,"Assign_mio"),"hired investigation dispatched from team button")
	game.set_office_clock_paused(false); game._process(30.0); pc._refresh_team(); await process_frame
	var report := str(game.vm_read(game.colleague_result_path("mio")))
	check(str(game.state.assignments.get("mio",{}).get("status",""))=="done" and report.contains(game.member_name("mio")),"real investigation report credited to hired worker")
	check(not game.can_deliver(),"investigation alone cannot pass delivery")
	check(press(pc.widgets.team.body,"Result_mio"),"result button opens hired report")
	check(pc.editor.text.contains(game.member_name("mio")),"editor renders hired report")
	pc._show_app("terminal"); pc._run_command("ssh client")
	pc._open_editor(str(game.vm_info().config_path)); pc.editor.text=game._vm().configuration_text(game._scenario().get("desired",{})); pc._save_editor()
	pc._show_app("terminal"); pc._run_command("systemctl restart "+str(game.vm_info().service))
	for attempt in 3:
		for probe in game.diagnostic_probes(): pc._run_command(str(probe.command))
	game.verify()
	check(game.can_deliver() and game.deliver(),"player performs actual correction and verification before delivery")
	var client := str(game.mission().client)
	check(game.end_day(),"care maintenance scheduled next day")
	ui.open_panel("company"); await process_frame
	# The company screen now separates the operating desk from customer care. Select
	# the care view and the customer row before assigning a maintenance worker.
	check(press(ui.modal_body,"CompanyView_care"),"customer care view opens")
	await process_frame
	var client_selector := "CompanyClient_" + client.sha256_text().left(10)
	check(press(ui.modal_body,client_selector),"care customer selection opens maintenance controls")
	await process_frame
	await capture("selected-customer")
	check(press(ui.modal_body,"Maintenance_mio"),"hired worker selectable in company maintenance UI")
	game.set_office_clock_paused(false); game._process(30.0)
	check(str(game._maintenance_job_for(client).get("status",""))=="done" and game.maintenance_result(client).begins_with("PASS"),"delegated maintenance ran real saved VM probes")
	check(game.save_game() and game.load_game(),"staff and report survive reload")
	ui.open_panel("staffing"); await process_frame
	check(press(ui.modal,"Release_mio"),"idle hired worker released from panel")
	ui.open_panel("terminal"); pc=ui.desktop; pc._show_app("team"); pc._refresh_team(); await process_frame
	check(pc.widgets.team.cards.size()==2,"released worker removed from team cards")
	var report_path := str(game.export_report("user://qa-v116-report-"+str(OS.get_process_id())))
	check(not report_path.is_empty() and FileAccess.get_file_as_string(report_path).contains(game.member_name("mio")),"business export handles staffing and payroll ledger rows")
	finish()

func finish() -> void:
	for failure in failures: push_error(failure)
	print("STAFFING_UI failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
