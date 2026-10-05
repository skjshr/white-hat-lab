extends SceneTree
## UI fixtures cover crowded taskbars; native work tests supply real notices.
var game
var ui
var pc
var assertions := 0
var failures: Array[String] = []
var anchors: Dictionary = {}
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("TASKBAR_LAYOUT_TIMEOUT"); quit(2))
	call_deferred("run")

func frames(count := 6) -> void:
	for _frame in count: await process_frame

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ", label)

func clipped(node: Control) -> Rect2:
	var result := node.get_global_rect().intersection(root.get_visible_rect())
	var parent := node.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents: result = result.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return result

func stable(phase: String) -> void:
	for app in anchors:
		var actual: Rect2 = pc.task_buttons[app].get_global_rect()
		var before: Rect2 = anchors[app]
		check(actual.position.distance_to(before.position) < 1 and actual.size.distance_to(before.size) < 1, phase + " keeps primary target " + app + " before=" + str(before) + " actual=" + str(actual))
		check(clipped(pc.task_buttons[app]).grow(1).encloses(actual), phase + " keeps whole primary target visible " + app + " visible=" + str(clipped(pc.task_buttons[app])))

func click(node: Control) -> void:
	var point := clipped(node).get_center() * Vector2(root.size) / root.get_visible_rect().size
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	Input.parse_input_event(motion); Input.flush_buffered_events()
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		Input.parse_input_event(event); Input.flush_buffered_events()
	await frames()

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	check(ui._new_game() and game.choose_strategy("advisory") and game.accept_mission(), "public APIs prepare isolated UI fixture")
	ui.guided_intro.skip(); ui.next_task_guide.set_enabled(false)
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(float(game.settings.text_scale)); root.get_node("Graphics").apply_settings(game.settings)
	ui.open_panel("terminal"); await frames(12); pc = ui.desktop
	for app in pc.PINNED_APPS: anchors[app] = pc.task_buttons[app].get_global_rect()
	stable("initial software strip")
	var machine: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var work: Dictionary = game.state.work.duplicate(true)
	for message in ["保存しました", "保存失敗", "長い保存失敗の通知。入力は保持されています。接続と保存先を確認して、同じ操作で再試行してください。"]:
		pc._notify(message); await frames()
		stable("UI notice fixture " + message)
		check(pc.status.visible and pc.status.tooltip_text == message, "notice retains its complete text on demand")
		pc.status.hide(); pc._layout_taskbar(); await frames(); stable("hidden notice fixture")
	pc.configure_return("案件一覧"); pc._notify("保存失敗"); await frames()
	stable("return button and persistent error")
	for app in pc.APPS:
		pc._show_app(app); await frames(3)
		stable("software start " + app)
	check(pc.find_child("AdvancedUnassigned",true,false) != null and pc.find_child("AdvancedOpenContracts",true,false) != null, "normal work opens an unassigned specialist tool with real case navigation")
	check(game._vm().export_state() == machine and int(game.state.cash) == cash and game.state.work == work, "window/notice fixtures do not perform work or rewrite customer data")
	pc._show_app("mail"); await frames()
	var last_app := str(pc.APPS.keys().back())
	var last: Button = pc.task_buttons[last_app]
	last.grab_focus(); await frames(12)
	check(clipped(last).grow(1).encloses(last.get_global_rect()), "keyboard focus reveals whole crowded software button")
	var scrolling: bool = pc.task_scroll.get_h_scroll_bar().visible
	if narrow: check(scrolling, "crowded narrow fixture actually requires software scrolling")
	if scrolling: check(clipped(pc.task_scroll.get_h_scroll_bar()).grow(1).encloses(pc.task_scroll.get_h_scroll_bar().get_global_rect()), "crowded software scrollbar stays within screen")
	await click(last)
	check(pc.current_app == last_app, "visible crowded button activates its actual software")
	pc.task_buttons.files.grab_focus(); await frames(12); await click(pc.task_buttons.files)
	check(pc.current_app == "files", "keyboard scroll returns to the primary file software")
	print("TASKBAR_LAYOUT_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " narrow=", narrow, " pixels=", root.size, " logical=", root.get_visible_rect().size, " scroll=", scrolling, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
