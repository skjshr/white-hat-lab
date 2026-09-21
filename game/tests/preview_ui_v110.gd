extends SceneTree

var game
var office
var output := ""
var narrow := false
var review111 := false
var plant112 := false
var market112 := false
var copy113 := false
var maintenance114 := false
var queue115 := false
var staff116 := false

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): print("FAIL: RV preview timed out"); quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg == "--narrow": narrow = true
		if arg == "--review111": review111 = true
		if arg == "--plant112": plant112 = true
		if arg == "--market112": market112 = true
		if arg == "--copy113": copy113 = true
		if arg == "--maintenance114": maintenance114 = true
		if arg == "--queue115": queue115 = true
		if arg == "--staff116": staff116 = true
	output = ProjectSettings.globalize_path("res://../artifacts/simulator/v116/ui" if staff116 else ("res://../artifacts/simulator/v115/ui" if queue115 else ("res://../artifacts/simulator/v114/ui" if maintenance114 else ("res://../artifacts/simulator/v113/ui" if copy113 else ("res://../artifacts/simulator/v112/ui" if plant112 or market112 else ("res://../artifacts/simulator/v111/ui" if review111 else "res://../artifacts/simulator/v110/ui"))))))
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func frames(count := 6) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var path := output.path_join(label+("-narrow" if narrow else "-wide")+".png")
	var error := root.get_texture().get_image().save_png(path)
	print("RV110_CAPTURE ",path," error=",error)

func run() -> void:
	game = root.get_node("Game")
	game.save_path = "user://preview_rv110_"+str(OS.get_process_id())+".json"
	game.backup_path = game.save_path+".bak"
	game.previous_path = game.save_path+".previous"
	game.settings_path = game.save_path+".settings"
	game.new_game({"company":"風の森セキュリティ","player":"春山","aya":"小川","ren":"星野"})
	game.state.ui_help_seen = {"legacy":true}
	game.set_settings({"quality":"medium","resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed" if narrow else "fullscreen","text_scale":1.3 if narrow else 1.0,"render_scale":1.0,"max_fps":60,"volume":0},false)
	office = load("res://scripts/office.gd").new()
	root.add_child(office)
	await frames(12)
	office.ui.controls.menu.hide()
	game.choose_strategy("advisory")
	office._start()
	if market112:
		await run_market112()
		office.queue_free(); await frames(3); quit(0); return
	if copy113:
		await run_copy113()
		office.queue_free(); await frames(3); quit(0); return
	if maintenance114:
		await run_maintenance114()
		office.queue_free(); await frames(3); quit(0); return
	if queue115:
		await run_queue115()
		office.queue_free(); await frames(3); quit(0); return
	if staff116:
		await run_staff116()
		office.queue_free(); await frames(3); quit(0); return
	if review111:
		await run_review111()
		office.queue_free(); await frames(3); quit(0); return
	if plant112:
		await run_plant112()
		office.queue_free(); await frames(3); quit(0); return
	game.start_free_career()
	office.ui.open_panel("board")
	await capture("cases")
	var first_id: String = str(game.state.offers[0].id)
	office.ui._select_contract(first_id)
	await capture("case-detail")
	office.ui.open_panel("company")
	await capture("skills")
	office.ui.open_panel("shop")
	await capture("shop")
	game.choose_contract(first_id)
	office.ui.open_panel("terminal")
	var desktop = office.ui.desktop
	desktop.widgets.mail.reading = true
	desktop._refresh_mail()
	await capture("mail")
	desktop._run_command("ssh client")
	desktop._show_app("files")
	desktop._file_location(true,"/etc/samba")
	await capture("files")
	desktop._file_location(false,"/home/operator/Documents")
	await capture("files-home")
	desktop._file_location(true,"/etc/samba")
	desktop._open_config()
	desktop.editor.text += "# 保存前の調査メモ\n"
	desktop._show_app("terminal")
	desktop._show_app("files")
	await capture("multiple-windows")
	if desktop.has_method("_tile_windows"):
		desktop._tile_windows()
		await capture("tiled-windows")
	if desktop.has_method("_toggle_overview"):
		desktop._toggle_overview()
		await capture("app-overview")
		desktop._toggle_overview()
	desktop._show_app("editor")
	print("RV110_DRAFT_PRESERVED ",desktop.editor.text.contains("保存前の調査メモ"))
	for app in ["terminal","editor","browser","monitor","verify","team","manual","receipt"]:
		desktop._show_app(app)
		if app == "browser": desktop.url_edit.text="https://files.client.test/staff/report.txt"; desktop._browse()
		await capture("app-"+app)
	for window in desktop.windows.values(): window.hide()
	desktop._show_app("monitor")
	desktop._show_app("editor")
	desktop._tile_windows()
	await capture("desktop-services")
	office.ui.close_panel(false)
	await frames(3)
	office.ui.root.hide()
	office.player.enabled = false
	office.player.camera.global_position = Vector3(-4.0,1.62,0.5)
	office.player.camera.look_at(Vector3(-14,1.8,-1.5),Vector3.UP)
	await capture("window-morning")
	if game.state.has("clock_minutes"):
		game.state.clock_minutes = 17*60+30
		game.changed.emit()
	await frames(80)
	await capture("window-evening")
	office.queue_free()
	await frames(3)
	quit(0)

func run_review111() -> void:
	game.set_contract_plan("care")
	office.ui.open_panel("terminal")
	var desktop = office.ui.desktop
	desktop.widgets.mail.reading = true; desktop._refresh_mail()
	await capture("care-offer")
	game.accept_mission(); desktop._run_command("ssh client")
	game.vm_run("ssh client")
	game.capture_baseline()
	game.vm_write(game.vm_info().config_path,game._vm().configuration_text({"staff":"write","guest":"none"}))
	game.vm_run("systemctl restart samba")
	for round_index in 2:
		for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	game.verify()
	if not game.deliver(): push_error("Review capture requires actual deliverable first case"); quit(2); return
	desktop._show_app("receipt")
	await capture("care-receipt")
	office.ui.open_panel("company")
	await frames(5)
	for child in office.ui.modal_body.get_children():
		if child is Label and child.text == "顧客保守": office.ui.modal_scroll.scroll_vertical = int(child.position.y)-12
	await capture("care-portfolio")
	game.end_day(); game.start_free_career()
	game.set_contract_plan("care")
	office.ui._select_contract(str(game.state.offers[0].id))
	await frames(5)
	office.ui.modal_scroll.scroll_vertical = int(office.ui.modal_body.size.y)
	await capture("career-care-offer")
	# Populate a later customer environment for rendering, without treating
	# this unlock fixture as player-progression acceptance.
	game.state.credit=1000; game.state.peak_profit=100000; game.state.skills.advisory=3; game._make_offers()
	game.set_contract_plan("standard")
	for offer in game.state.offers:
		if offer.case_id == "service-5-case-0": game.choose_contract(str(offer.id)); break
	office.ui.open_panel("terminal"); desktop=office.ui.desktop
	desktop._run_command("ssh client")
	game.vm_write(game.vm_info().config_path,"staff=write\npartner=read\npublic=none\nexpires=7d\nmfa=on\ntls=on\naudit=on\n")
	game.vm_run("systemctl restart portal")
	desktop._show_app("browser")
	desktop._browse_url("https://portal.client.test/partner?link=current",true)
	await capture("portal-anonymous")
	desktop.widgets.browser.account.select(1); desktop.widgets.browser.account.item_selected.emit(1)
	await capture("portal-mfa")
	desktop.widgets.browser.account.select(2); desktop.widgets.browser.account.item_selected.emit(2)
	await capture("portal-allowed")
	desktop.widgets.browser.link.select(1); desktop.widgets.browser.link.item_selected.emit(1)
	await capture("portal-expired")
	desktop._open_config(); desktop.EDITOR.show_find(desktop,true)
	desktop.widgets.editor.find_input.text="partner"; desktop.widgets.editor.find_input.text_changed.emit("partner")
	await capture("editor-find")

func run_market112() -> void:
	game.start_free_career()
	var offer: Dictionary = game.state.offers[0]
	for candidate in game.state.offers:
		if candidate.chapter == 0 and candidate.unlocked: offer = candidate; break
	office.ui._select_contract(str(offer.id))
	await frames(6)
	var price: SpinBox = office.ui.modal_body.find_child("OfferPrice",true,false)
	var accept: Button = office.ui.modal_body.find_child("AcceptContract",true,false)
	var quote: Dictionary = game.contract_quote(offer)
	# Type a value without submitting the LineEdit first: the button must commit it.
	price.get_line_edit().text = str(int(quote.budget_limit)+1)
	accept.pressed.emit()
	await frames(6)
	if game.state.accepted or game.state.quote_decisions.is_empty() or game.state.quote_decisions[-1].decision != "declined": push_error("market112 typed over-budget quote not declined"); quit(2); return
	office.ui.modal_scroll.scroll_vertical = int(office.ui.modal_body.size.y)
	await capture("quote-declined")
	price = office.ui.modal_body.find_child("OfferPrice",true,false)
	accept = office.ui.modal_body.find_child("AcceptContract",true,false)
	var discounted := roundi(int(quote.reference_fee)*0.85)
	price.value = discounted
	await capture("quote-revised")
	accept.pressed.emit(); await frames(8)
	if not game.state.accepted or int(game.state.contract.agreed_fee)!=discounted or int(game.work_status().estimated_fee)!=discounted: push_error("market112 edited quote was not locked on acceptance"); quit(2); return
	var desktop = office.ui.desktop
	desktop._run_command("ssh client")
	desktop._open_config()
	await capture("samba-config")
	desktop._run_command("testparm -s")
	desktop._show_app("terminal")
	await capture("samba-testparm")
	game.capture_baseline()
	game.vm_write(game.vm_info().config_path,game._vm().configuration_text(game._scenario().desired))
	game.vm_run("systemctl restart samba")
	for pass_index in 2:
		for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	game.verify()
	if not game.deliver(): push_error("market112 quoted Samba contract cannot deliver"); quit(2); return
	if int(game.completion_receipt().agreed_fee)!=discounted or int(game.completion_receipt().price_satisfaction_delta)!=3: push_error("market112 receipt quote/price reaction mismatch"); quit(2); return
	desktop._show_app("receipt")
	await capture("quote-receipt")
	print("MARKET112_PASS declined/revised/locked/delivered amount=",discounted)

func _aim_floor(position: Vector3) -> void:
	office.player.camera.global_position = position + Vector3(0, 1.55, 2.4)
	office.player.camera.look_at(position, Vector3.UP)

func _plant_order() -> Dictionary:
	for raw_order in game.delivery_orders():
		var order: Dictionary = raw_order
		if str(order.get("id", "")) == "plant": return order
	return {}

func run_plant112() -> void:
	office.ui.close_panel(false)
	office.ui.root.hide()
	office.player.enabled = true
	office.player.camera.current = true
	game.start_free_career()
	game.state.cash = 10000
	game.set_delivery_clock_paused(false)
	if not game.buy_equipment("plant"): push_error("plant112 purchase failed"); quit(2); return
	game.advance_delivery(31.0)
	if not game.take_delivery("plant"): push_error("plant112 delivery failed"); quit(2); return
	office.delivery.sync_orders(game.delivery_orders())
	if not office.delivery.interact("place_start", "plant"): push_error("plant112 placement start failed"); quit(2); return
	# A real camera-to-floor placement at the open center of the office.
	_aim_floor(Vector3(1.5, 0.0, -0.1)); await frames(12)
	await capture("plant-valid-green")
	# The same camera-driven preview over the player's desk must reject.
	_aim_floor(Vector3(-0.5, 0.0, -1.0)); await frames(12)
	await capture("plant-blocked-desk-red")
	# Confirm the valid position through the placement node after moving the view back.
	_aim_floor(Vector3(1.5, 0.0, -0.1)); await frames(12)
	print("PLANT112_PRECONFIRM valid=", office.delivery.placement_valid(), " reason=", office.delivery.placement_reason(), " pos=", office.delivery.placement_position_array())
	if not office.delivery.placement_valid() or not office.delivery.interact("confirm", "plant"): push_error("plant112 valid confirm failed"); quit(2); return
	await frames(8)
	var first: Dictionary = _plant_order()
	var first_position := Vector3(float(first.install_position[0]), float(first.install_position[1]), float(first.install_position[2]))
	var body: StaticBody3D = office.upgrade_collisions.get("plant")
	print("PLANT112_FIRST_TRANSFORM body=", body.global_position if body != null else Vector3.ZERO, " plant=", office.upgrades.get("plant").global_position if office.upgrades.has("plant") else Vector3.ZERO)
	if body == null or body.global_position.distance_to(office.upgrades.get("plant").global_position) > 0.8: push_error("plant112 collision did not align after first placement"); quit(2); return
	# Move the installed plant to another open floor point, then verify collider sync.
	if not office.delivery.interact("place_start", "plant"): push_error("plant112 move start failed"); quit(2); return
	# The live scene query must also reject the player's current body; the moving
	# plant's own original collider is the only excluded body.
	office.player.global_position = first_position
	_aim_floor(first_position); await frames(12)
	await capture("plant-blocked-player-red")
	if office.delivery.placement_valid(): push_error("plant112 live player overlap was accepted"); quit(2); return
	_aim_floor(Vector3(4.0, 0.0, -1.5)); await frames(12)
	if not office.delivery.placement_valid() or not office.delivery.interact("confirm", "plant"): push_error("plant112 move confirm failed"); quit(2); return
	await frames(8)
	var moved: Dictionary = _plant_order()
	var moved_position := Vector3(float(moved.install_position[0]), float(moved.install_position[1]), float(moved.install_position[2]))
	body = office.upgrade_collisions.get("plant")
	print("PLANT112_MOVED_TRANSFORM body=", body.global_position if body != null else Vector3.ZERO, " saved=", moved_position)
	if body == null or Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(moved_position.x, moved_position.z)) > 0.02: push_error("plant112 collider stale after move"); quit(2); return
	# Start another move and cancel; the persisted position must remain the moved point.
	if not office.delivery.interact("place_start", "plant") or not office.delivery.interact("cancel", "plant"): push_error("plant112 move cancel failed"); quit(2); return
	await frames(8)
	var canceled: Dictionary = _plant_order()
	if Vector3(float(canceled.install_position[0]), float(canceled.install_position[1]), float(canceled.install_position[2])).distance_to(moved_position) > 0.02: push_error("plant112 cancel did not restore position"); quit(2); return
	game.save_game()
	if not game.load_game(): push_error("plant112 reload failed"); quit(2); return
	await frames(8)
	var restored: Dictionary = _plant_order()
	if Vector3(float(restored.install_position[0]), float(restored.install_position[1]), float(restored.install_position[2])).distance_to(moved_position) > 0.02: push_error("plant112 reload lost position"); quit(2); return
	print("PLANT112_PASS first=", first_position, " moved=", moved_position, " restored=", restored.install_position)

func run_copy113() -> void:
	# Keep the title and all management screens on the normal UI path; this
	# branch is visual evidence only and deliberately avoids string assertions.
	office.ui.open_main_menu()
	await capture("title")
	office.ui.controls.menu.hide()
	game.choose_strategy("advisory")
	office._start()
	office.ui._start_free_career()
	await capture("board")
	if not game.state.offers.is_empty():
		office.ui._select_contract(str(game.state.offers[0].id))
		await capture("case-detail")
	office.ui.open_panel("company")
	await capture("company")
	office.ui.open_panel("shop")
	await capture("shop")
	office.ui._open_settings()
	office.ui._settings_tab("video")
	await capture("settings-video")
	if office.ui.setting_options.has("quality"):
		var quality: OptionButton = office.ui.setting_options.quality.control
		quality.select(1)
		quality.item_selected.emit(1)
		await capture("settings-video-selected")
	office.ui.close_panel(false)
	office.ui.open_panel("terminal")
	var desktop = office.ui.desktop
	await capture("terminal-empty")
	desktop._show_app("editor")
	await capture("editor-empty")
	desktop._show_app("mail")
	await capture("mail-empty")
	desktop._show_app("team")
	await capture("team-empty")

func run_maintenance114() -> void:
	game.start_free_career()
	var offer: Dictionary = game.state.offers[0]
	for candidate in game.state.offers:
		if candidate.unlocked: offer = candidate; break
	if not game.set_contract_plan("care"): push_error("maintenance114 care plan setup failed"); quit(2); return
	if not game.choose_contract(str(offer.id)): push_error("maintenance114 contract setup failed"); quit(2); return
	var client := str(offer.get("client", ""))
	office.ui.open_panel("terminal"); await frames(8)
	var qa_desktop = office.ui.desktop
	qa_desktop._run_command("ssh client"); qa_desktop._open_config()
	game.capture_baseline()
	var desired: Dictionary = game._scenario().desired
	game.vm_write(game.vm_info().config_path, game._vm().configuration_text(desired))
	game.vm_run("systemctl restart "+str(game.vm_info().service))
	for pass_index in 2:
		for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	game.verify()
	print("MAINTENANCE114_PRE_DELIVER done=",game.current_done()," can=",game.can_deliver()," work=",game.work_status()," checks=",game.state.checks)
	if not game.deliver(): push_error("maintenance114 care delivery failed"); quit(2); return
	if not game.end_day(): push_error("maintenance114 next day transition failed"); quit(2); return
	game._prepare_maintenance_day(); game.changed.emit()
	office.ui.open_panel("company"); await frames(8); office.ui.modal_scroll.scroll_vertical = 450 if narrow else int(office.ui.modal_body.size.y); await capture("maintenance-pending")
	var pending: Dictionary = game._maintenance_job_for(client)
	if str(pending.get("status", "")) != "pending": push_error("maintenance114 pending state missing"); quit(2); return
	if not game.assign_maintenance(client, "aya"): push_error("maintenance114 delegation failed"); quit(2); return
	await frames(8)
	office.ui._maintenance_ui_signature = str(game.maintenance_summary()) + str(game.maintenance_jobs())
	office.ui.open_panel("terminal"); await frames(8); office.ui.desktop._show_app("team"); await capture("maintenance-working")
	var assignment: Dictionary = game.state.assignments.get("aya", {})
	if str(assignment.get("kind", "")) != "maintenance" or str(assignment.get("client", "")) != client: push_error("maintenance114 team assignment missing"); quit(2); return
	assignment.remaining = 0.0; game._finish_maintenance("aya", assignment); await frames(8)
	office.ui._maintenance_ui_signature = str(game.maintenance_summary()) + str(game.maintenance_jobs())
	office.ui.open_panel("company"); await frames(8); office.ui.modal_scroll.scroll_vertical = 450 if narrow else int(office.ui.modal_body.size.y); await capture("maintenance-done")
	var done: Dictionary = game._maintenance_job_for(client)
	if str(done.get("status", "")) not in ["done", "failed"]: push_error("maintenance114 completion missing"); quit(2); return
	done.status = "pending"; done.assignee = ""; done.result = ""; done.remaining = 12.0; game.state.assignments = {}; game._assignments = {}; game.changed.emit()
	if not game.run_maintenance(client): push_error("maintenance114 self check unavailable"); quit(2); return
	var self_done: Dictionary = game._maintenance_job_for(client)
	if str(self_done.get("assignee", "")) != "player": push_error("maintenance114 self assignee mismatch"); quit(2); return
	print("MAINTENANCE114_PASS client=",client," delegated=aya self=",self_done.get("assignee","")," status=",self_done.get("status",""))

func run_queue115() -> void:
	if not game.has_method("contract_queue") or not game.has_method("switch_contract") or not game.has_method("set_offer_plan"):
		push_error("queue115 contract API unavailable"); quit(2); return
	var career_started: bool = bool(game.start_free_career()); print("QUEUE115_CAREER_START result=", career_started, " accepted=", game.state.accepted, " career=", game.state.career_mode, " current_done=", game.current_done(), " strategy=", game.state.strategy)
	game.state.credit=1000; game.state.peak_profit=100000; game.state.skills.advisory=3; game._make_offers()
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked", false)))
	if offers.size() < 2:
		push_error("queue115 requires two unlocked offers"); quit(2); return
	var first_id := str(offers[0].id); var second_id := str(offers[1].id)
	var first_plan_ok: bool = bool(game.set_offer_plan("standard")); var first_accept_ok: bool = bool(game.choose_contract(first_id))
	print("QUEUE115_FIRST_SETUP offers=", offers.size(), " career=", game.state.career_mode, " awaiting=", game.state.awaiting_contract, " strategy=", game.state.strategy, " plan=", first_plan_ok, " accept=", first_accept_ok, " id=", first_id)
	if not first_plan_ok or not first_accept_ok:
		push_error("queue115 first contract failed"); quit(2); return
	office.ui.open_panel("terminal"); await frames(8)
	var desktop = office.ui.desktop
	desktop._show_app("editor")
	desktop._open_editor("workstation:/home/operator/Documents/queue115-draft.txt")
	await frames(5)
	if not is_instance_valid(desktop.editor):
		push_error("queue115 editor unavailable"); quit(2); return
	desktop.editor.text = "queue115 unsaved draft"
	var previous_key := str(desktop.session_key)
	var second_offer: Dictionary = offers[1]
	var second_quote: Dictionary = game.contract_quote(second_offer)
	var second_amount := int(second_quote.get("quoted_fee", second_offer.get("reward", 0)))
	office.ui._submit_quote(second_id, second_amount)
	var second_accept_ok: bool = bool(game.state.contract_contexts.has(second_id))
	print("QUEUE115_SECOND_SETUP context=", second_accept_ok, " amount=", second_amount, " awaiting=", game.state.awaiting_contract)
	if not second_accept_ok:
		push_error("queue115 second contract failed"); quit(2); return
	await frames(8)
	var saved_session: Dictionary = game.state.get("desktop_sessions", {}).get(previous_key, {})
	if str(saved_session.get("drafts", {}).get("workstation:/home/operator/Documents/queue115-draft.txt", "")) != "queue115 unsaved draft":
		push_error("queue115 unsaved draft was not preserved"); quit(2); return
	var queue: Array = game.contract_queue()
	if queue.size() < 2:
		push_error("queue115 queue does not contain two contracts"); quit(2); return
	office.ui.open_panel("board"); await frames(8); await capture("queue-two-contracts")
	office.ui.open_panel("terminal"); await frames(8); desktop = office.ui.desktop
	if not desktop._switch_contract(first_id):
		push_error("queue115 switch back failed"); quit(2); return
	await frames(8)
	if str(game.state.current_contract_id) != first_id:
		push_error("queue115 switched contract id mismatch"); quit(2); return
	office.ui.open_panel("board"); await frames(8); await capture("queue-switched-current")
	print("QUEUE115_PASS first=",first_id," second=",second_id," draft_preserved=",saved_session.get("drafts", {}).has("workstation:/home/operator/Documents/queue115-draft.txt")," queue=",game.contract_queue())

func run_staff116() -> void:
	game.state.cash=50000
	if "teamdesk" not in game.state.equipment: game.state.equipment.append("teamdesk")
	game.changed.emit(); await frames(20)
	if not game.start_free_career() or not game.hire_staff("mio","morning"):
		push_error("staff116 career or hire failed"); quit(2); return
	office.ui.close_panel(false); await frames(400)
	var actor: Node3D=office.staff_actors.mio.actor
	var routine: OfficeColleague=office.staff_actors.mio.routine
	if not routine.is_at_workstation() or not is_zero_approx(actor.rotation.y):
		push_error("staff116 arrival or desk facing incorrect"); quit(2); return
	await capture("staff-arrived")
	office.ui.open_panel("staffing"); await capture("staffing")
	office.ui.open_panel("terminal"); office.ui.desktop._show_app("team"); await frames(12)
	office.ui.desktop.widgets.team.body.get_parent().scroll_vertical=9999
	await capture("staff-team")
	office.ui.close_panel(false)
	var offer: Dictionary={}
	for candidate in game.state.offers:
		if bool(candidate.get("unlocked",false)) and int(candidate.get("targets",0))==1 and int(candidate.get("chapter",-1))==0: offer=candidate; break
	if offer.is_empty() or not game.set_offer_plan("care") or not game.choose_contract(str(offer.id)):
		push_error("staff116 actual care contract unavailable"); quit(2); return
	game.assign_colleague("mio")
	await frames(90); await capture("staff-working")
	if str(game.state.assignments.mio.status)!="working": push_error("staff116 working state missing"); quit(2); return
	game.state.clock_minutes=780; game.changed.emit(); await frames(12)
	if not actor.visible or not routine.is_at_workstation(): push_error("staff116 left unfinished work"); quit(2); return
	await capture("staff-working-after-shift")
	for _i in 24:
		await frames(30)
		if str(game.state.assignments.mio.status)=="done": break
	if str(game.state.assignments.mio.status)!="done" or not game.vm_read(game.colleague_result_path("mio")).contains(game.member_name("mio")):
		push_error("staff116 real investigation result missing"); quit(2); return
	await frames(420); await capture("staff-leaving")
	if actor.visible or not routine.is_departed(): push_error("staff116 failed departure"); quit(2); return
	game.vm_run("ssh client")
	game.vm_write(game.vm_info().config_path,game._vm().configuration_text(game._scenario().desired))
	game.vm_run("systemctl restart "+str(game.vm_info().service))
	for _i in 3:
		for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	game.verify()
	if not game.deliver() or not game.end_day(): push_error("staff116 real care delivery failed"); quit(2); return
	await frames(400)
	if not actor.visible or not routine.is_at_workstation(): push_error("staff116 next day arrival failed"); quit(2); return
	await capture("staff-nextday")
	office.ui.open_panel("company"); await frames(12)
	var delegate: Button=office.ui.modal_body.find_child("Maintenance_mio",true,false)
	if delegate==null or delegate.disabled: push_error("staff116 maintenance button unavailable"); quit(2); return
	office.ui.modal_scroll.ensure_control_visible(delegate); await frames(8); await capture("company-maintenance")
	print("STAFF116_PASS real_vm=true arrived=true departure=true next_day=true maintenance_ui=true")
