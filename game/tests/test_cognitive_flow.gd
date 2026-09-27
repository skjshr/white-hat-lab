extends SceneTree

var ui
var game
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("cognitive flow timeout"); quit(2))
	call_deferred("run")

func frames(count := 8) -> void:
	for _i in count: await process_frame

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func node(id: String):
	return ui.find_child(id, true, false)

func press(id: String) -> void:
	var button = node(id)
	check(button is BaseButton and button.is_visible_in_tree() and not button.disabled, "reachable " + id)
	if button is BaseButton and button.is_visible_in_tree() and not button.disabled:
		if button.toggle_mode: button.button_pressed = not button.button_pressed
		button.pressed.emit()
	await frames()

func capture(id: String) -> void:
	await frames()
	if not capture_enabled or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/cognitive-load-20260925/after")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(id + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + id)

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui = preload("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	check(ui._new_game(), "new isolated company")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui._set_text_scale(1.3 if narrow else 1.0)
	check(game.choose_strategy("operations"), "strategy")
	check(game.accept_mission(), "story contract")
	ui.open_panel("terminal"); await frames()
	var pc = ui.desktop
	pc._run_command("ssh client"); pc._open_config(); await frames()
	if not pc.windows.editor.maximized: pc.windows.editor.toggle_maximize()
	await frames()
	ui.guided_intro.refresh(1.0); await frames()
	var card: Control = ui.guided_intro._card
	check(not card.get_global_rect().intersects(pc.get_global_rect()), "coach never overlays software")
	check(pc.get_global_rect().end.y <= root.size.y + 1, "reserved software fits screen")
	var draft: String = pc.editor.text + "\n# retained unsaved work\n"
	pc.editor.text = draft; pc.editor.text_changed.emit()
	await capture("01-editor-guide")
	await press("GuidedTutorialDetails")
	check(not card.get_global_rect().intersects(pc.get_global_rect()), "expanded coach never overlays software")
	await capture("02-editor-hint")
	await press("GuidedTutorialDetails")
	ui.guided_intro.skip(); await frames()
	ui.next_task_guide.set_enabled(false); await frames()
	check(is_zero_approx(pc.offset_top), "hiding coach returns workspace space")
	ui.next_task_guide.set_enabled(true); await frames(16)
	ui.guided_intro.resume(); await frames(16)
	check(is_equal_approx(pc.offset_top, ui.guided_intro._card.size.y + 4.0), "resumed tutorial replaces the ordinary guide inset")
	ui.guided_intro.skip(); ui.next_task_guide.set_enabled(false); await frames()
	pc.start_menu.show()
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	pc._input(escape); await frames()
	check(ui.current_kind == "terminal" and not pc.start_menu.visible, "Escape closes launcher only")
	pc.overview.show(); pc._input(escape); await frames()
	check(ui.current_kind == "terminal" and not pc.overview.visible, "Escape closes window overview only")
	ui.open_panel("company"); await frames()
	ui.open_panel("terminal"); await frames(); pc = ui.desktop
	check(pc.drafts.values().has(draft), "unsaved editor content survives management round trip")
	check(ui.desktop_return_kind == "company", "return destination is source company")
	await press("DesktopReturn")
	check(ui.current_kind == "company", "explicit return restores source management")
	ui.open_panel("terminal"); await frames()
	await press("ExitDesktop")
	check(ui.current_kind.is_empty(), "Office action actually returns to office")
	# Start the independent career fixture after the accepted story draft checks.
	check(ui._new_game(), "new career fixture")
	ui.guided_intro.skip()
	check(game.choose_strategy("operations"), "career strategy")
	check(game.start_free_career(), "career")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.open_panel("sales"); await capture("03-sales-list")
	check(not ui.hud.visible, "management does not duplicate office HUD")
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked",false)) and bool(item.get("market_available",true)))
	check(not offers.is_empty(), "available quote")
	if not offers.is_empty():
		var id := str(offers[0].id)
		ui._select_contract(id); await frames()
		var price: SpinBox = node("OfferPrice")
		var draft_price := price.value + 1
		price.value = draft_price
		await capture("04-quote")
		check(ui.modal.get_global_rect().size.y < 600 if not narrow else ui.modal.get_global_rect().end.y <= root.size.y, "quote actions remain near inputs and in viewport")
		await press("QuoteBack")
		check(ui.current_kind == "sales" and ui.board_selected_id.is_empty(), "quote back returns to list")
		ui._select_contract(id); await frames()
		check(is_equal_approx(node("OfferPrice").value,draft_price), "quote draft survives back")
		await press("AcceptContract")
		check(ui.current_kind == "board", "quote submission confirms on work board without opening software")
		check(str(ui.operations_choices.dispatch_selected.id) == id, "accepted job remains selected")
		var state_before: Dictionary = game.state.duplicate(true)
		await capture("05-selected-work")
		await press("DispatchControlsDisclosure")
		for control_name in ["DispatchMemberSelector", "DispatchEnqueue", "DispatchOpen", "DispatchReport"]:
			var item = node(control_name)
			check(item is Control and item.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(item.get_global_rect()), "selected action fits " + control_name)
		check(game.state == state_before, "selection and disclosure leave business data unchanged")
		await capture("06-delegation")
		await press("DispatchOpen")
		check(ui.current_kind == "terminal", "explicit work action opens PC")
		await press("DesktopReturn")
		check(ui.current_kind == "board" and str(ui.operations_choices.dispatch_selected.id) == id, "return keeps chosen job")
		ui._select_contract(id); await frames()
		check(ui.current_kind == "board" and node("OfferPrice") == null, "accepted catalog item never opens a new quote")
	print("COGNITIVE_FLOW failures=", failures.size(), " narrow=", narrow)
	quit(0 if failures.is_empty() else 1)
