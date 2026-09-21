extends SceneTree

const UI = preload("res://scripts/ui_theme.gd")
const Editor = preload("res://scripts/os_editor.gd")
var ui
var game
var pc
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(80).timeout.connect(func(): push_error("comparison timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count := 4) -> void:
	for _i in count: await process_frame

func snapshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if pc.notification.visible: await create_timer(4.2).timeout
	await frames(5)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/comparison/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func run() -> void:
	var comparison = preload("res://scripts/text_comparison.gd")
	check(comparison.compare("a\nb\nc", "a\nx\nb\nc").added == [1], "insertion retains matching lines")
	check(comparison.compare("a\nb\na", "a\na").removed == [1], "repeated lines retain matching context")
	check(comparison.compare("a\n", "a").removed == [1], "trailing newline is a real change")
	check(comparison.compare("", "").added.is_empty(), "empty files unchanged")
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(2)
	game = ui._game()
	game.set_process(false)
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	check(ui._new_game(), "isolated new game")
	check(game.choose_strategy("operations"), "strategy")
	game.set_settings({"resolution": "960x600" if narrow else "1600x900", "window_mode": "windowed", "text_scale": 1.3 if narrow else 1.0, "volume": 0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1600, 900)
	ui.open_panel("terminal")
	pc = ui.desktop
	pc._accept()
	game.vm_run("ssh client")
	pc._show_app("verify")
	if not pc.windows.verify.maximized: pc.windows.verify.toggle_maximize()
	await frames()
	var toggle = pc.widgets.verify.right.find_child("DiagnosticCompare", true, false)
	check(toggle != null and toggle.disabled, "unmeasured comparison disabled")
	check(game.capture_baseline(), "real baseline recorded")
	var initial_config: String = game.vm_read(game.vm_info().config_path)
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	pc._refresh_checks()
	pc.widgets.verify.raw_visible = true
	pc._refresh_checks()
	await frames()
	var first = pc.widgets.verify.right.find_child("DiagnosticFirst", true, false)
	var latest = pc.widgets.verify.right.find_child("DiagnosticLatest", true, false)
	check(first != null and latest != null and first.text == latest.text, "one actual measurement is unchanged")
	var before: Dictionary = game._vm().export_state().duplicate(true)
	pc._refresh_checks()
	check(game._vm().export_state() == before, "comparison is observation only")
	pc._open_config()
	if not pc.windows.editor.maximized: pc.windows.editor.toggle_maximize()
	var original_editor = pc.editor
	var desired: String = game._vm()._config_text(game._vm()._legacy_desired())
	pc.editor.text = desired
	pc.editor.text_changed.emit()
	Editor._show_compare(pc, "saved")
	await frames()
	check(pc.editor == original_editor and pc.editor.text == desired, "comparison preserves live draft")
	check(game.vm_read(game.vm_info().config_path) == initial_config, "comparison never saves draft")
	check(pc.widgets.editor.compare_original.text == initial_config, "saved source is actual file")
	pc.editor.insert_text_at_caret("# comparison\n")
	await frames(2)
	pc.editor.undo()
	await frames(2)
	check(pc.editor.text == desired, "editing and undo work during comparison")
	await snapshot("editor-saved")
	pc._save_editor()
	check(pc.widgets.editor.compare_original.text == desired and pc.widgets.editor.compare_status.text == UI.copy("compare_unchanged"), "save refreshes reference and clears diff")
	Editor._show_compare(pc, "baseline")
	await frames()
	check(pc.editor == original_editor and pc.editor.text == desired, "baseline preserves editor")
	check(pc.widgets.editor.compare_original.text == initial_config, "baseline stays captured bytes after save")
	await snapshot("editor-baseline")
	Editor._close_compare(pc)
	check(pc.editor == original_editor and pc.editor.text == desired and not pc.widgets.editor.compare_source.visible, "close comparison preserves draft")
	game.vm_run("systemctl restart " + str(game.vm_info().service))
	check(game.diagnostic_probes().any(func(p): return not p.fresh), "real mutation stales measurements")
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	var changed: Dictionary = {}
	for probe in game.diagnostic_probes():
		if "-U guest -c ls" in str(probe.get("command", "")) and str(probe.get("initial_result", "")) != str(probe.get("result", "")): changed = probe; break
	check(not changed.is_empty(), "actual repair changes response")
	if changed.is_empty(): quit(1); return
	pc._show_app("verify")
	pc.widgets.verify.selected = str(changed.id)
	pc.widgets.verify.raw_visible = true
	pc._refresh_checks()
	await frames()
	first = pc.widgets.verify.right.find_child("DiagnosticFirst", true, false)
	latest = pc.widgets.verify.right.find_child("DiagnosticLatest", true, false)
	check(first != null and first.text == str(changed.initial_result), "full original measurement preserved")
	check(latest != null and latest.text == str(changed.result), "full latest measurement preserved")
	check(first != null and not first.editable and latest != null and not latest.editable, "response panes are read only")
	if first != null:
		var scroll: ScrollContainer = pc.widgets.verify.right.get_parent()
		scroll.ensure_control_visible(first)
	await snapshot("diagnostic-repair")
	check(game.save_game() and game.load_game(), "comparison source save reload")
	var restored: Dictionary = {}
	for probe in game.diagnostic_probes():
		if str(probe.id) == str(changed.id): restored = probe
	check(str(restored.get("initial_result", "")) == str(changed.initial_result) and str(restored.get("result", "")) == str(changed.result), "both real observations survive reload")
	print("COMPARISON_UI ", "PASS" if failures.is_empty() else "FAIL", " narrow=", narrow, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
