extends SceneTree
## Real keyboard dispatch through the viewport; no test-side scrolling to targets.
var game
var ui
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(55).timeout.connect(func(): push_error("MANAGEMENT_KEYBOARD_TIMEOUT"); quit(2))
	call_deferred("run")

func frames(count := 4) -> void:
	for _i in count: await process_frame

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	root.push_input(event)
	event = InputEventKey.new(); event.keycode = code; event.pressed = false
	root.push_input(event)
	await frames()

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless": return
	await frames(8)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/ui-quality/management")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "isolated profile")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	check(game.new_game(), "new company")
	check(game.choose_strategy("operations"), "strategy")
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui)
	await frames()
	ui.controls.menu.hide(); ui.guided_intro.skip(); ui._set_text_scale(1.3 if narrow else 1.0)
	ui.open_panel("settings"); ui._settings_tab("video")
	await frames()
	var candidates: Array[Control] = []
	for node in ui.modal_body.find_children("*", "Control", true, false):
		if node.is_visible_in_tree() and node.focus_mode == Control.FOCUS_ALL and not (node is BaseButton and node.disabled): candidates.append(node)
	check(candidates.size() >= 2, "settings has keyboard controls")
	if candidates.is_empty(): finish(); return
	# Traverse native focus order, including footer actions. Opening and keyboard
	# navigation must not apply settings or alter the active business state.
	var state_before: Dictionary = game.state.duplicate(true)
	var settings_before: Dictionary = game.settings.duplicate(true)
	candidates[0].grab_focus(); await frames()
	var reached := {}
	var scrolled := false
	for _i in 45:
		var owner := root.gui_get_focus_owner()
		if owner != null and ui.modal_body.is_ancestor_of(owner):
			reached[owner.get_instance_id()] = true
			var bounds: Rect2 = ui.modal_scroll.get_global_rect()
			check(bounds.grow(2).has_point(owner.get_global_rect().get_center()), "focused setting is visible: " + str(owner.name))
			scrolled = scrolled or ui.modal_scroll.scroll_vertical > 0
		await key(KEY_TAB)
	check(reached.size() >= candidates.size(), "Tab visits every enabled setting")
	if ui.modal_body.size.y > ui.modal_scroll.size.y + 2: check(scrolled, "keyboard navigation scrolls long settings")
	check(game.settings == settings_before and game.state == state_before, "navigation has no business or settings side effects")
	await capture("settings-keyboard")
	await key(KEY_ESCAPE)
	check(ui.current_kind != "settings", "Escape closes settings")
	for _i in 3:
		ui.open_panel("company"); await frames()
		ui.open_panel("board"); await frames()
		check(ui.modal.is_visible_in_tree() and ui.current_kind == "board", "repeated management switch remains usable")
	check(game.state == state_before, "management switching does not mutate case progress")
	await capture("management-return")
	finish()

func finish() -> void:
	print("MANAGEMENT_KEYBOARD_PASS narrow=", narrow) if failures.is_empty() else print("MANAGEMENT_KEYBOARD_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
