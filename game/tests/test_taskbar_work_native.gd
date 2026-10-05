extends "res://tests/test_daily_workspace_native.gd"
## Keep real software return targets through the earned daily-report journey.
var app_anchors: Dictionary = {}
var app_points: Dictionary = {}

func native_method() -> String:
	return super.native_method() + " Before actual employee editing, record primary software rectangles. Real editor save and expiry, real transfer save failure and its persistence, and actual session rebuild must preserve them. Click the previously observed coordinates to return to the same application; no notification or window position is injected."

func remember_anchors() -> void:
	for app in ui.desktop.PINNED_APPS:
		app_anchors[app] = control("TaskbarApp_" + app).get_global_rect()
		app_points[app] = app_anchors[app].get_center() * Vector2(root.size) / root.get_visible_rect().size
	record("taskbar_anchors", str(app_anchors))

func stable_anchors(phase: String) -> bool:
	for app in app_anchors:
		var button := control("TaskbarApp_" + str(app))
		var actual: Rect2 = button.get_global_rect()
		var original: Rect2 = app_anchors[app]
		if not expect(actual.position.distance_to(original.position) < 1 and actual.size.distance_to(original.size) < 1, phase + " preserves software target " + str(app) + " before=" + str(original) + " after=" + str(actual)): return false
		if not expect(clipped_rect(button).grow(1).encloses(actual), phase + " keeps whole software target visible " + str(app)): return false
	return true

func click_original_app(app: String) -> bool:
	var point: Vector2 = app_points[app]
	var target := control("TaskbarApp_" + app) as Button
	var presses := [0]
	target.pressed.connect(func(): presses[0] += 1)
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	Input.parse_input_event(motion); Input.flush_buffered_events()
	var hovered: Control = root.gui_get_hovered_control()
	if not expect(hovered == target or (hovered != null and target.is_ancestor_of(hovered)), "original coordinate still points to " + app): return false
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		Input.parse_input_event(event); Input.flush_buffered_events()
	clicks += 1; await frames(8)
	record("original_taskbar_click", app + " at " + str(point))
	return expect(presses[0] == 1 and ui.desktop.current_app == app, "previously observed position opens exactly the expected software " + app)

func employee_begin() -> bool:
	remember_anchors(); await capture("dock-01-before-employee-save")
	if not await super.employee_begin(): return false
	return stable_anchors("employee transfer checkpoint rebuild")

func after_copy_saved() -> bool:
	if not expect(ui.desktop.status.visible and ui.desktop.status.text.contains("保存しました"), "actual editor save displays its real notification"): return false
	await capture("dock-02-actual-copy-save")
	if not stable_anchors("actual editor save notice") or not await click_original_app("files"): return false
	await create_timer(3.4).timeout
	if not expect(not ui.desktop.status.visible, "actual success notice expires without simulated timer callback") or not stable_anchors("expired actual editor save notice"): return false
	await capture("dock-03-notice-expired")
	return true

func after_transfer_persistence_failure() -> bool:
	var before: Dictionary = game._vm().export_state(); var minutes := int(game.state.clock_minutes)
	await create_timer(3.4).timeout
	if not expect(ui.desktop.status.visible and ui.desktop.status.text.contains("保存失敗"), "actual failure remains visible after success-notice lifetime") or not stable_anchors("real transfer persistence failure"): return false
	await capture("dock-04-real-transfer-save-failure")
	if not await click_original_app("editor") or not await click_original_app("files"): return false
	return expect(same_values(game._vm().export_state(), before) and int(game.state.clock_minutes) == minutes and str(control("SmbRemoteName").text) == "report.txt", "software round trip at old coordinates preserves failed transfer bytes, time and inputs")

func employee_retry() -> bool:
	if not await super.employee_retry(): return false
	return stable_anchors("actual transfer retry and read-back")
