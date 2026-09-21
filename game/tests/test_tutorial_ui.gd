extends SceneTree

const UI = preload("res://scripts/interface.gd")
var failures: Array[String] = []
var capture_enabled := false

func _init() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("tutorial timeout"); quit(2))
	call_deferred("run")

func run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if "--guided" in OS.get_cmdline_user_args():
		await run_guided()
		for failure in failures: push_error("TUTORIAL_GUIDED: " + failure)
		print("TUTORIAL_GUIDED failures=", failures.size())
		quit(1 if not failures.is_empty() else 0)
		return
	var ui := UI.new()
	root.add_child(ui)
	await process_frame
	var game := ui._game()
	game.save_path = "user://qa-tutorial-ui.json"
	game.backup_path = "user://qa-tutorial-ui.json.bak"
	game.previous_path = "user://qa-tutorial-ui.previous.json"
	game.settings_path = "user://qa-tutorial-ui-settings.json"
	check(ui._new_game(), "new game")
	ui.open_panel("help")
	await process_frame
	check(ui.current_kind == "help", "tutorial opens from help route")
	check(_visible_text(ui.modal).contains("まず、自分の席へ"), "first tutorial page")
	await capture("tutorial-01-office-wide")
	for index in ui.TUTORIAL_PAGES.size():
		check(ui.modal.find_child("TutorialTab_%d" % index, true, false) is Button, "tutorial tab %d" % index)
	ui._tutorial_select(2)
	await process_frame
	check(_visible_text(ui.modal).contains("Outwatchから作業を始める"), "workstation tutorial page")
	await capture("tutorial-03-outwatch-wide")
	ui._tutorial_select(5)
	await process_frame
	check(_visible_text(ui.modal).contains("利益を次の仕事へ戻す"), "business tutorial page")
	check(ui.modal.find_child("TutorialNext", true, false) is Button and ui.modal.find_child("TutorialNext", true, false).text == "完了", "last page completion action")
	await capture("tutorial-06-business-wide")
	root.size = Vector2i(960,600)
	ui.text_scale = 1.3
	ui._tutorial_select(4)
	await process_frame
	check(ui.modal_scroll.size.y > 0 and ui.modal_scroll.get_v_scroll_bar() != null, "narrow tutorial remains scrollable")
	await capture("tutorial-05-verify-narrow")
	ui.open_panel("terminal")
	await process_frame
	var mail_brand := ui.desktop.find_child("MailBrand",true,false)
	check(mail_brand is Label and str(mail_brand.text) == "Outwatch", "mail brand renamed to Outwatch")
	for failure in failures: push_error("TUTORIAL_UI: " + failure)
	print("TUTORIAL_UI failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("FAIL ",label)

func _visible_text(node: Node) -> String:
	var result := str(node.text) if node is Label or node is Button else ""
	for child in node.get_children(): result += "\n" + _visible_text(child)
	return result

func capture(name: String) -> void:
	if not capture_enabled: return
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/tutorial/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name+".png")) == OK, "capture "+name)

func run_guided() -> void:
	var game := root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-guided-"):
		push_error("Guided tutorial QA requires --qa-profile=guided-...")
		quit(2)
		return
	var office: Node3D = load("res://scripts/office.gd").new()
	root.add_child(office)
	await process_frames(12)
	var ui = office.ui
	root.size = Vector2i(960, 600) if "--narrow" in OS.get_cmdline_user_args() else Vector2i(1920, 1080)
	await process_frames(3)
	check(ui._new_game({"company":"Guided QA","player":"Tester","aya":"Aya","ren":"Ren"}), "guided new game")
	ui._set_text_scale(1.3 if "--narrow" in OS.get_cmdline_user_args() else 1.0)
	game.set_settings({"resolution":"960x600" if "--narrow" in OS.get_cmdline_user_args() else "1920x1080", "window_mode":"windowed", "text_scale":ui.text_scale, "volume":0},false)
	root.size=Vector2i(960,600) if "--narrow" in OS.get_cmdline_user_args() else Vector2i(1920,1080)
	await process_frames(6)
	office.player.set_physics_process(false)
	var guide = ui.guided_intro
	check(guide != null and guide.active(), "guide enabled for fresh story")
	check(not bool(game.state.get("career_mode", false)), "fresh guide remains story mode")
	guide.refresh(0.2)
	check(guide.current_step == "strategy", "guide starts at strategy")
	await guided_capture("00-guide-strategy")
	_press_named(ui, "GuideStrategy_operations")
	await process_frames(2)
	guide.refresh(0.2)
	check(str(game.state.get("strategy", "")) == "operations", "strategy selected")
	check(not bool(game.state.get("career_mode", false)), "strategy does not enter career while guided")
	await guided_capture("01-strategy")
	check(guide.current_step == "walk", "strategy advances to movement guide")
	if office.player != null:
		var player = office.player
		player.position += Vector3(1.0, 0.0, -1.0)
		player.rotation.y += 0.3
	await process_frames(2)
	guide.refresh(0.2)
	check(guide.current_step == "desk", "movement/look advances guided stage")
	await guided_capture("02-movement")
	ui.open_panel("terminal")
	await process_frames(3)
	guide.refresh(0.2)
	var desktop = ui.desktop
	check(desktop != null, "desk opens desktop")
	if desktop == null: return
	await guided_capture("03-desk")
	desktop._show_app("mail")
	await process_frames(2)
	var mail_brand = desktop.find_child("MailBrand", true, false)
	check(mail_brand is Label and str(mail_brand.text) == "Outwatch", "guided mail is visible")
	_press_named(desktop, "GuideMailMessage")
	await process_frames(2)
	_press_named(desktop, "GuideMailAccept")
	await process_frames(3)
	check(bool(game.state.get("accepted", false)), "mail acceptance uses actual button")
	await guided_capture("04-accept")
	guide._locate_target()
	await process_frames(2)
	_press_named(desktop, "SambaConnect")
	await process_frames(3)
	check(bool(game.vm_info().get("connected", false)), "SambaConnect connects customer VM")
	check(guide.current_step=="baseline", "guide requires initial record")
	guide._locate_target()
	await process_frames(2)
	_press_named(desktop, "GuideBaseline")
	await process_frames(3)
	check(_baseline_recorded(game), "baseline captured through UI")
	desktop._show_app("verify")
	await process_frames(2)
	_press_named(desktop, "DiagnosticProbe_staff-write")
	await process_frames(1)
	_press_named(desktop, "DiagnosticRun")
	await process_frames(3)
	check(_probe_recorded(game, "staff-write"), "initial staff-write observation recorded")
	guide._locate_target()
	await process_frames(3)
	_press_named(desktop, "SambaEdit_share")
	await process_frames(2)
	var read_only = desktop.find_child("SambaReadOnly", true, false)
	var guest = desktop.find_child("SambaGuest", true, false)
	var users = desktop.find_child("SambaValidUsers", true, false)
	check(read_only is CheckBox and guest is CheckBox and users is LineEdit, "Samba repair controls are real nodes")
	await guided_capture("05a-read-only")
	if read_only is CheckBox: read_only.button_pressed = false
	await process_frames(2)
	check(guide.current_step=="guest", "toggle advances to guest access")
	if guest is CheckBox: guest.button_pressed = false
	await process_frames(2)
	check(guide.current_step=="users", "guest denial advances to allowed user")
	await guided_capture("05b-allowed-user")
	if users is LineEdit:
		users.text = "staff"; users.text_changed.emit(users.text)
	await process_frames(3)
	check(guide.current_step=="save", "draft changes require saving")
	_press_named(desktop, "SambaSave")
	await process_frames(3)
	check(guide.current_step=="restart", "saved changes require applying")
	_press_named(desktop, "SambaRestart")
	await process_frames(3)
	check(bool(game._vm().state.get("active", false)) and not bool(game._vm().state.get("dirty", false)), "Samba repair was saved and restarted")
	await guided_capture("05-repair")
	desktop._show_app("verify")
	await process_frames(2)
	for _attempt in 8:
		guide.refresh(0.2)
		if guide.current_step!="diagnose": break
		var target: String=guide._target_name()
		_press_named(desktop,target)
		await process_frames(2)
		if target.begins_with("DiagnosticProbe_"):
			_press_named(desktop,"DiagnosticRun")
			await process_frames(2)
	check(guide.current_step=="validate", "guide follows fresh actual measurements")
	_press_named(desktop, "DiagnosticValidate")
	await process_frames(3)
	if not game.can_deliver(): print("DELIVERY_FAILURE ",game.state.checks, " CONFIG ",game._vm().state.applied)
	check(game.can_deliver(), "diagnostics make delivery available")
	await guided_capture("06-diagnose")
	desktop._show_app("receipt")
	await process_frames(2)
	_press_named(desktop, "GuideDeliver")
	await process_frames(4)
	check(game.current_done(), "delivery uses actual receipt button")
	check(guide.current_step=="done" and guide.active(), "completion stays visible until dismissed")
	await guided_capture("07-done")
	guide.skip()
	await process_frames(2)
	check(not guide.active(), "guide closes explicitly after done")
	check(ui._new_game({"company":"Skip QA","player":"Tester","aya":"Aya","ren":"Ren"}), "skip/resume new game")
	await process_frames(2)
	guide = ui.guided_intro
	guide.skip()
	check(not guide.active(), "skip disables guide")
	game.save_game()
	check(game.load_game(), "guided save/load")
	check(not guide.active(), "missing or skipped guide stays inactive after load")
	guide.resume()
	check(guide.active(), "resume restores guide after save/load")
	game.state.erase("guided_intro")
	check(game.save_game(), "erase legacy guide key")
	check(game.load_game(), "load legacy profile")
	check(not guide.active(), "legacy save does not auto-enable guide")
	office.queue_free()
	await process_frames(3)

func _press_named(node: Node, name: String) -> bool:
	var target := node.find_child(name, true, false)
	if target is Button and target.is_visible_in_tree() and not target.disabled:
		target.pressed.emit()
		return true
	check(false, "missing or disabled button " + name)
	return false

func _probe_recorded(game: Node, id: String) -> bool:
	for probe in game.diagnostic_probes():
		if str(probe.get("id", "")) == id: return bool(probe.get("recorded", false))
	return false

func _baseline_recorded(game: Node) -> bool:
	if bool(game.state.get("baseline_recorded", false)): return true
	for target in game.state.get("targets", []):
		if bool(target.get("baseline_recorded", false)): return true
	return false

func process_frames(count: int) -> void:
	for _i in count: await process_frame
	var guide = root.find_child("GuidedTutorial",true,false)
	if guide!=null: guide.refresh(0.2)

func guided_capture(label: String) -> void:
	if not capture_enabled: return
	await process_frames(2)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/tutorial-guided/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if "--narrow" in OS.get_cmdline_user_args() else "-wide"
	var guide=root.find_child("GuidedTutorial",true,false)
	if guide!=null and guide.target_rect.has_area():
		var card: Control=guide.find_child("GuidedTutorialCard",true,false)
		check(not card.get_global_rect().intersects(guide.target_rect),"coach leaves target clickable "+label)
	var expected:=Vector2i(960,600) if "--narrow" in OS.get_cmdline_user_args() else Vector2i(1920,1080)
	check(root.get_texture().get_image().get_size()==expected,"native capture size "+label)
	check(root.get_texture().get_image().save_png(folder.path_join(label + suffix + ".png")) == OK, "guided capture " + label)
