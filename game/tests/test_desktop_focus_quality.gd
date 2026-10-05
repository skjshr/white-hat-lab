extends SceneTree
## Real input dispatch and UI-only fixtures; no completion flags or desired VM state.
var ui
var game
var pc
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(75).timeout.connect(func(): push_error("DESKTOP_FOCUS_TIMEOUT"); quit(2))
	call_deferred("run")

func frames(count := 3) -> void:
	for _i in count: await process_frame

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func key(code: int, unicode_value := 0, alt := false) -> void:
	var down := InputEventKey.new()
	down.keycode = code; down.unicode = unicode_value; down.alt_pressed = alt; down.pressed = true
	Input.parse_input_event(down)
	await frames(1)
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)

func type_text(value: String) -> void:
	for character in value:
		await key(character.unicode_at(0), character.unicode_at(0))

func alt_tab() -> void:
	await key(KEY_TAB, 0, true)
	var release := InputEventKey.new(); release.keycode = KEY_ALT; release.pressed = false
	Input.parse_input_event(release)
	await frames()

func mouse_click(point: Vector2) -> void:
	var pixels := point * Vector2(root.size) / root.get_visible_rect().size
	var motion := InputEventMouseMotion.new(); motion.position = pixels; motion.global_position = pixels
	Input.parse_input_event(motion); Input.flush_buffered_events()
	var hovered: Control = root.gui_get_hovered_control()
	check(hovered == pc.widgets.editor.editor, "mouse reaches actual editor field")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new(); event.position = pixels; event.global_position = pixels; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		Input.parse_input_event(event); Input.flush_buffered_events()
	await frames()

func front_focus(label: String) -> void:
	var focused := root.gui_get_focus_owner()
	check(is_instance_valid(focused) and pc.windows[pc.current_app].is_ancestor_of(focused), label + " input belongs to front window")

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless": return
	await frames(4)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../../audit/ui-quality/focus")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui)
	await frames()
	check(ui._new_game(), "isolated new company")
	ui.guided_intro.skip(); ui.next_task_guide.set_enabled(false)
	game.set_settings({"resolution":"960x600" if narrow else "1600x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.get_node("Graphics").apply_settings(game.settings)
	ui._set_text_scale(1.3 if narrow else 1.0)
	print("DESKTOP_FOCUS_DISPLAY pixels=", root.size, " logical=", root.get_visible_rect().size)
	ui.open_panel("terminal"); await frames(); pc = ui.desktop
	var progress := {"revision":game.state.revision,"cash":game.state.cash,"completed":game.state.completed_ids.duplicate(),"accepted":game.state.accepted}
	pc._open_editor("workstation:/home/operator/Documents/focus-quality.txt")
	await frames()
	var edit: CodeEdit = pc.widgets.editor.editor
	edit.text = "alpha beta gamma"; edit.set_caret_column(5); edit.grab_focus()
	pc._show_app("browser"); await frames()
	front_focus("browser open")
	var url: LineEdit = pc.widgets.browser.url
	var before_editor := edit.text
	await type_text("z")
	check(url.text.contains("z") and edit.text == before_editor, "front browser receives typing; back editor unchanged")
	await alt_tab()
	check(pc.current_app == "editor" and root.gui_get_focus_owner() == edit, "Alt+Tab restores editor input")
	check(edit.get_caret_column() == 5, "Alt+Tab preserves editor caret")
	await type_text("x")
	check(edit.text == "alphax beta gamma", "typing returns to remembered caret")
	await alt_tab()
	check(pc.current_app == "browser" and root.gui_get_focus_owner() == url, "second Alt+Tab restores browser input")

	# Native chrome buttons may take focus while clicked. They must not replace
	# the remembered editing field for the next restore.
	pc._show_app("editor"); await frames()
	var saved_caret := edit.get_caret_column()
	var minimize: Button = pc.windows.editor.chrome_buttons[0]
	minimize.grab_focus(); minimize.pressed.emit(); await frames()
	check(not pc.windows.editor.visible and pc.current_app != "editor", "minimize selects another visible app")
	front_focus("after minimize")
	pc.task_buttons.editor.pressed.emit(); await frames()
	check(root.gui_get_focus_owner() == edit and edit.get_caret_column() == saved_caret, "taskbar restore returns to editor, not minimize button")
	var close: Button = pc.windows.editor.chrome_buttons[2]
	close.grab_focus(); close.pressed.emit(); await frames()
	check("editor" not in pc.running_apps, "close dismisses editor")
	front_focus("after close")
	pc._show_app("editor"); await frames()
	check(root.gui_get_focus_owner() == edit and edit.text == "alphax beta gamma", "reopen retains draft and input field")

	# A physical click sets a new caret and must survive the deferred activation.
	if not pc.windows.editor.maximized: pc.windows.editor.toggle_maximize()
	await frames()
	edit.set_caret_column(edit.text.length())
	await mouse_click(edit.get_global_rect().position + Vector2(90,12))
	var clicked_column := edit.get_caret_column()
	check(root.gui_get_focus_owner() == edit and clicked_column < edit.text.length(), "mouse chooses editor caret without restoration stealing it")
	await frames(5)
	check(edit.get_caret_column() == clicked_column, "mouse caret survives deferred focus work")
	await capture("01-editor-focus")

	for cycle in 4:
		pc._show_app("terminal"); await frames()
		front_focus("terminal cycle " + str(cycle))
		var command: LineEdit = pc.widgets.terminal.command
		var previous_command := command.text
		var previous_edit := edit.text
		await type_text("q")
		check(command.text.length() == previous_command.length() + 1 and edit.text == previous_edit, "repeated app switches type only into terminal")
		pc._show_app("browser"); await frames(); front_focus("browser cycle " + str(cycle))
		pc._show_app("editor"); await frames(); front_focus("editor cycle " + str(cycle))

	# A dynamically rebuilt browser field is discovered through its owning
	# window, without manually wiring the new control in the test.
	pc._show_app("browser"); await frames()
	var page: VBoxContainer = pc.widgets.browser.page
	var temporary := LineEdit.new(); temporary.name = "FocusTemporary"; page.add_child(temporary)
	temporary.grab_focus(); await frames()
	pc._show_app("terminal"); await frames()
	page.remove_child(temporary); temporary.queue_free(); await frames()
	pc._show_app("browser"); await frames()
	check(root.gui_get_focus_owner() == url, "removed remembered control falls back to valid browser field")
	var replacement := LineEdit.new(); replacement.name = "FocusReplacement"; page.add_child(replacement)
	pc._show_app("terminal"); await frames()
	replacement.grab_focus(); await frames()
	check(pc.current_app == "browser" and root.gui_get_focus_owner() == replacement, "new dynamic field focus also updates selected application")
	page.remove_child(replacement); replacement.queue_free(); await frames()

	# Exercise the same shared scroll factory used by desktop applications with
	# enough rows to force scrolling at both supported fixture sizes.
	pc._show_app("manual"); await frames()
	pc._clear(pc.windows.manual.content)
	var rows: VBoxContainer = pc._scroll(pc.windows.manual.content)
	var buttons: Array[Button] = []
	var activated := [0]
	for index in 32:
		var button: Button = pc._button("検証項目 " + str(index + 1), func(): activated[0] += 1)
		button.custom_minimum_size.y = 44; rows.add_child(button); buttons.append(button)
	await frames()
	buttons[0].grab_focus(); await frames()
	for _i in 31: await key(KEY_TAB)
	check(root.gui_get_focus_owner() == buttons.back(), "Tab reaches final scroll row")
	var scroll: ScrollContainer = rows.get_parent()
	check(scroll.scroll_vertical > 0 and scroll.get_global_rect().encloses(buttons.back().get_global_rect()), "Tab target scrolls fully into view without test scrolling")
	front_focus("last scroll row")
	await key(KEY_ENTER)
	check(activated[0] == 1, "visible focused action executes once")
	await capture("02-tab-scroll")
	check(game.state.revision == progress.revision and game.state.cash == progress.cash and game.state.completed_ids == progress.completed and game.state.accepted == progress.accepted, "focus and navigation leave mission progression unchanged")
	print("DESKTOP_FOCUS_QUALITY failures=", failures.size(), " narrow=", narrow)
	quit(0 if failures.is_empty() else 1)
