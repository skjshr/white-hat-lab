extends SceneTree
## Fresh, normal-funded journey. No state/skills/cash/desired overrides.
## Display settings are setup only. Gameplay uses Godot mouse/key dispatch.
## Node names were discovered by source inspection; elapsed times are automation
## timings, not measurements of an unbriefed human participant.

var game
var office
var ui
var narrow := "--narrow" in OS.get_cmdline_user_args()
var events: Array[Dictionary] = []
var failures: Array[String] = []
var clicks := 0
var keys := 0
var scrolls := 0
var started_ms := 0
var folder := ""

func _init() -> void:
	started_ms = Time.get_ticks_msec()
	folder = OS.get_environment("WHL_CAPTURE_DIR")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../../audit/release-candidate/journey/screens")
	DirAccess.make_dir_recursive_absolute(folder)
	create_timer(240).timeout.connect(func(): failures.append("journey timeout"); finish())
	call_deferred("run")

func frames(count := 8) -> void:
	for _i in count: await process_frame

func record(kind: String, detail: String) -> void:
	events.append({"seconds": snappedf(float(Time.get_ticks_msec() - started_ms) / 1000.0, 0.01), "kind": kind, "detail": detail, "clicks": clicks, "keys": keys, "scrolls": scrolls})
	print("JOURNEY ", JSON.stringify(events.back()))

func control(id: String) -> Control:
	return ui.find_child(id, true, false) as Control if is_instance_valid(ui) else null

func clipped_rect(target: Control) -> Rect2:
	var rect := target.get_global_rect()
	var parent := target.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return rect.intersection(root.get_visible_rect())

func mouse(position: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	# Office enables canvas scaling. Input.parse_input_event takes window pixels.
	var pixel := position * Vector2(root.size) / root.get_visible_rect().size
	var move := InputEventMouseMotion.new(); move.position = pixel; move.global_position = pixel; Input.parse_input_event(move)
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = pixel; event.global_position = pixel; event.button_index = button; event.pressed = down; Input.parse_input_event(event)
	if button == MOUSE_BUTTON_LEFT: clicks += 1
	else: scrolls += 1

func press(id: String) -> bool:
	var target := control(id)
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		failures.append("No visible control: " + id); record("blocked", failures.back()); return false
	if target is BaseButton and target.disabled:
		failures.append("Disabled control: " + id); record("blocked", failures.back()); return false
	var visible := clipped_rect(target)
	if not visible.has_area() or visible.size.y < 12:
		record("offscreen", id)
		var parent := target.get_parent()
		while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
		if parent is ScrollContainer:
			for _attempt in 12:
				if clipped_rect(target).size.y >= 12: break
				var wheel := MOUSE_BUTTON_WHEEL_DOWN if target.get_global_rect().get_center().y > parent.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP
				mouse(parent.get_global_rect().get_center(), wheel); await frames(3)
		visible = clipped_rect(target)
	if not visible.has_area(): failures.append("Unreachable control: " + id); return false
	record("click", id + " | " + str(target.get("text") if target is BaseButton else ""))
	mouse(visible.get_center()); await frames(12)
	return true

func key(code: Key, pressed: bool, unicode_value := 0, ctrl := false) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.unicode = unicode_value; event.ctrl_pressed = ctrl; event.pressed = pressed; Input.parse_input_event(event)
	if pressed: keys += 1

func tap(code: Key) -> void:
	key(code, true); await frames(2); key(code, false); await frames(10)

func edit(id: String, text: String) -> bool:
	if not await press(id): return false
	var field := control(id)
	if not field is LineEdit or not field.has_focus(): failures.append("No input focus: " + id); return false
	key(KEY_A, true, 0, true); key(KEY_A, false, 0, true); key(KEY_BACKSPACE, true); key(KEY_BACKSPACE, false)
	for index in text.length(): key(KEY_NONE, true, text.unicode_at(index)); key(KEY_NONE, false, text.unicode_at(index))
	await frames(8); record("text_input", id + "=" + text); return true

func find_text_button(node: Node, text: String) -> Button:
	if node is Button and node.is_visible_in_tree() and str(node.text).contains(text): return node
	for child in node.get_children():
		var result := find_text_button(child, text)
		if result != null: return result
	return null

func press_text(text: String) -> bool:
	var button := find_text_button(ui, text)
	if button == null: failures.append("No visible button text: " + text); return false
	record("discover_by_visible_label", text)
	return await press(str(button.name))

func select_option(id: String, index: int) -> bool:
	var option := control(id) as OptionButton
	if not is_instance_valid(option) or index >= option.item_count: failures.append("Missing displayed option: " + id); return false
	record("select_displayed_option", id + " | " + option.get_item_text(index))
	if not await press(id): return false
	await tap(KEY_HOME)
	var popup := option.get_popup()
	for _i in option.item_count + 1:
		if popup.get_focused_item() == index: break
		await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	var current := control(id) as OptionButton
	return expect(is_instance_valid(current) and current.selected == index, "real keyboard selected " + id + " index " + str(index))

func ordinary_share_attempt(label: String) -> bool:
	var repaired := label.begins_with("15-after")
	if not await press("SambaWorkspaceAccess"): return false
	await capture(label + "-normal-use-entry")
	if not await press("SambaProbeRun"): return false
	if not observed_share_result("report.txt", label + " staff list"): return false
	await capture(label + "-staff-list")
	if not await select_option("SambaProbeFilePicker", 1): return false
	if not await select_option("SambaProbeOperation", 1): return false
	if not await press("SambaProbeRun"): return false
	if not observed_share_result("getting file report.txt: OK", label + " staff read"): return false
	await capture(label + "-staff-read")
	if not await select_option("SambaProbeOperation", 2): return false
	if not await press("SambaProbeRun"): return false
	if not observed_share_result("putting file report.txt: OK" if repaired else "NT_STATUS_ACCESS_DENIED", label + " staff save"): return false
	await capture(label + "-staff-save")
	if not await edit("SambaProbeUser", ""): return false
	if not await select_option("SambaProbeOperation", 0): return false
	if not await press("SambaProbeRun"): return false
	if not observed_share_result("NT_STATUS_ACCESS_DENIED" if repaired else "report.txt", label + " guest access"): return false
	await capture(label + "-guest-access")
	if not await edit("SambaProbeUser", "staff"): return false
	if not await press("SambaWorkspaceConfig"): return false
	return true

func observed_share_result(expected: String, label: String) -> bool:
	var result := control("SambaProbeResult") as Label
	if not expect(is_instance_valid(result) and result.text.contains(expected), label + " actual service response"): return false
	var shown := clipped_rect(result)
	record("observed_service_result", label + " | " + result.text + " | visible=" + str(shown))
	if not expect(shown.has_area() and shown.has_point(result.get_global_rect().get_center()), label + " result visible without test scrolling"): return false
	return true

func readable_share_field_labels() -> bool:
	for expected in ["パス", "許可ユーザー"]:
		var found: Label = null
		for candidate in ui.find_children("*", "Label", true, false):
			if candidate.is_visible_in_tree() and candidate.text == expected:
				found = candidate; break
		if not expect(is_instance_valid(found), "share setting label exists: " + expected): return false
		var text_width: float = found.get_theme_font("font").get_string_size(found.text, HORIZONTAL_ALIGNMENT_LEFT, -1, found.get_theme_font_size("font_size")).x
		if not expect(found.get_line_count() == 1 and found.size.x + 1 >= text_width, "share setting label is readable on one line: " + expected): return false
	return true

func visible_content(node: Node, out: Array) -> void:
	if node is Control and node.is_visible_in_tree():
		if node is Label or node is Button or node is RichTextLabel:
			var text := str(node.text)
			if not text.is_empty(): out.append({"node": str(node.name), "text": text, "rect": str(node.get_global_rect()), "clipped": str(clipped_rect(node))})
	for child in node.get_children(): visible_content(child, out)

func capture(label: String) -> void:
	await frames(10)
	var visible: Array = []
	visible_content(ui, visible)
	var snapshot := {"label": label, "seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0, "clicks": clicks, "keys": keys, "scrolls": scrolls, "panel": str(ui.current_kind), "guide_step": str(ui.guided_intro.current_step), "cash": game.state.get("cash", 0), "clock": game.business_clock(), "current_contract_id": game.state.get("current_contract_id", ""), "visible": visible}
	var suffix := "-narrow" if narrow else "-wide"
	var data := FileAccess.open(folder.path_join(label + suffix + ".json"), FileAccess.WRITE)
	if data != null: data.store_string(JSON.stringify(snapshot, "\t")); data.close()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(label + suffix + ".png"))
	record("capture", label)

func route(app: String) -> bool:
	if is_instance_valid(ui.desktop) and ui.desktop.current_app == app: return true
	var locate := control("GuidedTutorialLocate")
	if is_instance_valid(locate) and locate.is_visible_in_tree():
		if not await press("GuidedTutorialLocate"): return false
		if is_instance_valid(ui.desktop) and ui.desktop.current_app == app: return true
	if await press("TaskbarApp_" + app): return true
	return false

func expect(value: bool, label: String) -> bool:
	if not value: failures.append(label); record("blocked", label)
	return value

func finish() -> void:
	var report := {"narrow": narrow, "seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0, "clicks": clicks, "keys": keys, "scrolls": scrolls, "failures": failures, "events": events, "input_method": "Godot Input.parse_input_event; node names source-inspected; settings-only setup API; no money, skills, progression or answer overrides"}
	var file := FileAccess.open(folder.path_join("journey" + ("-narrow" if narrow else "-wide") + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("RELEASE_JOURNEY_", "PASS" if failures.is_empty() else "FAIL", " clicks=", clicks, " keys=", keys, " scrolls=", scrolls, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game = root.get_node("Game")
	if not expect(str(game.save_path).begins_with("user://qa-"), "isolated QA save"): finish(); return
	game.set_settings({"resolution": "960x600" if narrow else "1440x900", "window_mode": "windowed", "text_scale": 1.3 if narrow else 1.0, "volume": 0}, false)
	office = load("res://main.tscn").instantiate(); root.add_child(office); await frames(20)
	ui = office.ui; root.size = Vector2i(960,600) if narrow else Vector2i(1440,900); await frames(10)
	await capture("00-title")
	if not await press("NewCompanyButton"): finish(); return
	await capture("01-company-profile")
	if not await press("ConfirmProfile"): finish(); return
	await capture("02-company-direction")
	if not await press("GuideStrategy_operations"): finish(); return
	await capture("03-first-office")
	key(KEY_W, true); await create_timer(0.7).timeout; key(KEY_W, false)
	for _i in 3:
		var motion := InputEventMouseMotion.new(); motion.relative = Vector2(90,0); motion.screen_relative = Vector2(90,0); Input.parse_input_event(motion); await frames(3)
	await frames(12)
	await capture("04-movement-and-desk")
	record("keyboard_shortcut", "F: guide explicitly advertises workstation shortcut")
	await tap(KEY_F)
	await capture("05-first-desktop")
	if not await press("GuideMailMessage"): finish(); return
	await capture("06-customer-request")
	if not await press("GuideMailAccept"): finish(); return
	await capture("07-accepted-customer")
	if not expect(bool(game.state.get("accepted", false)), "acceptance changes state"): finish(); return
	if not expect(not bool(game.vm_info().get("connected", false)), "service landing navigates without connecting"): finish(); return
	if OS.get_environment("WHL_JOURNEY_STOP") == "accepted": finish(); return
	if not await route("browser"): finish(); return
	await capture("08-customer-service-entry")
	if not await press("SambaConnect"): finish(); return
	await capture("09-connected-shared-folder")
	if not await route("receipt"): finish(); return
	await capture("09b-baseline-location")
	if not is_instance_valid(control("GuideBaseline")) or not control("GuideBaseline").is_visible_in_tree():
		record("ux_obstacle", "Guide points to hidden baseline action; manually discover and open disclosure")
		if not await press_text("変更前の記録"): finish(); return
		await capture("09c-baseline-manually-discovered")
	if not await press("GuideBaseline"): finish(); return
	await capture("10-baseline-saved")
	var saved_cash: int = int(game.state.get("cash", 0))
	await tap(KEY_ESCAPE)
	await tap(KEY_ESCAPE)
	await capture("10a-pause-save")
	if not await press_text("セーブ"): finish(); return
	if not await press_text("タイトルへ戻る"): finish(); return
	await capture("10b-saved-title")
	if not await press("ResumeButton"): finish(); return
	await capture("10c-resumed-work")
	var saved_targets: Array = game.state.get("targets", [])
	var baseline_preserved := saved_targets.any(func(target): return bool(target.get("baseline_recorded", false)))
	if not expect(bool(game.state.get("accepted", false)) and baseline_preserved and int(game.state.get("cash", 0)) == saved_cash, "normal UI save and continue preserves accepted work and recorded baseline"): finish(); return
	if not await route("verify"): finish(); return
	if not await press("DiagnosticProbe_staff-write"): finish(); return
	if not await press("DiagnosticRun"): finish(); return
	await capture("11-observed-staff-failure")
	if not await route("browser"): finish(); return
	if not await press("SambaEdit_share"): finish(); return
	if not await ordinary_share_attempt("12-before"): finish(); return
	await capture("12-edit-shared-folder")
	if not readable_share_field_labels(): finish(); return
	if not await press("SambaReadOnly"): finish(); return
	if not await press("SambaGuest"): finish(); return
	if not await edit("SambaValidUsers", "staff"): finish(); return
	await capture("13-explicit-customer-access")
	if not await press("SambaSave"): finish(); return
	await capture("14-saved-not-applied")
	if not await press("SambaRestart"): finish(); return
	await capture("15-applied-service")
	if not await ordinary_share_attempt("15-after"): finish(); return
	if not await route("verify"): finish(); return
	# These probes are the publicly displayed employee/guest contract outcomes.
	for probe in game.diagnostic_probes():
		var id := str(probe.get("id", ""))
		if not await press("DiagnosticProbe_" + id): finish(); return
		if not await press("DiagnosticRun"): finish(); return
	await capture("16-regression-measurements")
	for _attempt in 4:
		var stale: Array = game.diagnostic_probes().filter(func(probe): return not bool(probe.get("fresh", false)))
		if stale.is_empty(): break
		var probe_id := str(stale[0].get("id", ""))
		record("repeat_public_stale_measurement", probe_id)
		if not await press("DiagnosticProbe_" + probe_id): finish(); return
		if not await press("DiagnosticRun"): finish(); return
	await capture("16b-regression-current")
	if not await press("DiagnosticValidate"): finish(); return
	if not await route("receipt"): finish(); return
	await capture("17-customer-delivery-ready")
	if not await press("GuideDeliver"): finish(); return
	await capture("18-customer-result")
	if not expect(game.current_done(), "first customer job delivered through UI"): finish(); return
	if not await press("GuidedTutorialSkip"): finish(); return
	await capture("19-after-guided-job")
	if not await press("ReceiptNextWork"): finish(); return
	await capture("20-next-job-route")
	if not await press("DaySettle"): finish(); return
	await capture("21-next-working-day")
	var locate := control("NextTaskLocate")
	if is_instance_valid(locate) and locate.is_visible_in_tree():
		if not await press("NextTaskLocate"): finish(); return
	else:
		await tap(KEY_F)
		if not await route("mail"): finish(); return
	await capture("22-next-customer-inbox")
	if not await press("GuideMailMessage"): finish(); return
	await capture("23-next-customer-request")
	if not expect(int(game.state.get("chapter", 0)) == 1 and not bool(game.state.get("accepted", false)), "next customer is available without automatic acceptance"): finish(); return
	finish()
