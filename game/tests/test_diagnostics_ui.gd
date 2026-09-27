extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var capture_enabled := "--capture" in OS.get_cmdline_user_args()
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(60).timeout.connect(func(): push_error("diagnostics UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL: ", label)

func frames(count := 4) -> void:
	for _i in count: await process_frame

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless": return
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/cognitive-load-20260925/diagnostics-after")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func run() -> void:
	var diagnostics = preload("res://scripts/os_diagnostics.gd")
	var copy = preload("res://scripts/ui_theme.gd")
	check(diagnostics._status({"recorded": false}) == copy.copy("os_result_none"), "unrun state remains explicit")
	check(diagnostics._status({"recorded": true, "fresh": true, "passed": false}) == copy.copy("os_result_fail"), "fresh failure remains explicit")
	check(diagnostics._status({"recorded": true, "fresh": false, "passed": true}) == copy.copy("os_result_stale"), "stale measurement remains explicit")
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(2)
	game = ui._game()
	check(game.save_path.begins_with("user://qa-"), "isolated QA storage")
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	check(ui._new_game(), "new company created")
	check(game.choose_strategy("operations"), "operations strategy selected")
	game.set_settings({"resolution": "960x600" if narrow else "1920x1080", "window_mode": "windowed", "text_scale": 1.3 if narrow else 1.0, "volume": 0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	ui.open_panel("terminal")
	pc = ui.desktop
	pc._accept()
	game.vm_run("ssh client")
	pc._show_app("verify")
	if not pc.windows.verify.maximized: pc.windows.verify.toggle_maximize()
	await frames()
	var probes: Array = game.diagnostic_probes()
	check(not probes.is_empty(), "accepted job exposes real diagnostic probes")
	if probes.is_empty(): quit(1); return
	var first: Dictionary = probes[0]
	var first_id := str(first.id)
	var run_button = pc.widgets.verify.right.find_child("DiagnosticRun", true, false)
	var expected = pc.widgets.verify.right.find_child("DiagnosticExpected", true, false)
	var actual = pc.widgets.verify.right.find_child("DiagnosticActual", true, false)
	check(run_button is BaseButton and not run_button.disabled, "selected probe has reachable run action")
	check(expected is Label and expected.text == str(first.get("expectation", first.get("description", ""))), "selected probe shows its real expectation")
	check(actual is Label and not bool(first.get("recorded", false)), "actual response begins as unmeasured")
	check(not bool(game.diagnostic_probes()[0].get("recorded", false)), "opening and selecting tests never runs them")
	await capture("diagnostics-before-run")
	if run_button is BaseButton and not run_button.disabled: run_button.pressed.emit()
	await frames()
	var measured: Dictionary = {}
	for probe in game.diagnostic_probes():
		if str(probe.get("id", "")) == first_id: measured = probe
	actual = pc.widgets.verify.right.find_child("DiagnosticActual", true, false)
	var result_status = pc.widgets.verify.right.find_child("DiagnosticResultStatus", true, false)
	check(bool(measured.get("recorded", false)), "explicit run records the VM response")
	check(actual is Label and actual.text == str(measured.get("result", "")).get_slice("\n", 0), "detail shows the recorded actual response")
	check(result_status is Label and result_status.text != "", "detail states current pass or freshness status")
	check(pc.widgets.verify.right.find_child("DiagnosticCompare", true, false) != null, "full output and comparison remain progressive")
	check(pc.find_child("DiagnosticValidate", true, false) != null, "existing delivery validation remains available")
	check(pc.widgets.verify.get("footer") == null, "diagnostics has no unrelated application navigation footer")
	await capture("diagnostics-recorded-result")
	print("DIAGNOSTICS_UI failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
