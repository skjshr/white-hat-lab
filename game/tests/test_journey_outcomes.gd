extends SceneTree
## Native input regressions for acceptance, tutorial location and receipt reading.
## Repair setup uses explicit VM APIs; second-site fixture exercises snapshot scope.
## This is automated UI verification, not unbriefed human usability testing.
const BUSINESS = preload("res://scripts/os_business_apps.gd")
const RECEIPT = preload("res://scripts/receipt_panel.gd")
var ui
var game
var pc
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var folder := OS.get_environment("WHL_CAPTURE_DIR")
var saw_stale_measurement := false

func _init() -> void:
	create_timer(120).timeout.connect(func(): push_error("JOURNEY_OUTCOMES_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value: failures.append(label); print("FAIL ", label)

func frames(count := 6) -> void:
	for _i in count: await process_frame

func control(id: String) -> Control:
	return ui.find_child(id, true, false) as Control

func clipped(node: Control) -> Rect2:
	if node == null: return Rect2()
	var rect := node.get_global_rect()
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return rect.intersection(root.get_visible_rect())

func click(id: String) -> void:
	var node := control(id)
	check(node != null and node.is_visible_in_tree(), "visible " + id)
	if node == null or not node.is_visible_in_tree(): return
	var rect := clipped(node)
	# Evidence is intentionally below the impact statement. Reach it through
	# real wheel input, without a direct scroll-position assignment.
	for _attempt in 20:
		if rect.size.y >= minf(24, node.size.y) and rect.has_point(node.get_global_rect().get_center()): break
		var parent := node.get_parent()
		while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
		if not parent is ScrollContainer: break
		var point: Vector2 = parent.get_global_rect().get_center() * Vector2(root.size) / root.get_visible_rect().size
		for down in [true, false]:
			var wheel := InputEventMouseButton.new(); wheel.position = point; wheel.global_position = point; wheel.pressed = down
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN if node.get_global_rect().get_center().y > parent.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP
			Input.parse_input_event(wheel)
		await frames(3); rect = clipped(node)
	check(rect.has_area(), "reachable " + id)
	if not rect.has_area(): return
	var point := rect.get_center() * Vector2(root.size) / root.get_visible_rect().size
	var move := InputEventMouseMotion.new(); move.position = point; move.global_position = point; Input.parse_input_event(move)
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; Input.parse_input_event(event)
	await frames(12)

func capture(label: String) -> void:
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(10); await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func solve() -> void:
	var machine = game._vm()
	var desired: Dictionary = game._scenario().get("desired", machine._legacy_desired())
	check(game.vm_write(game.vm_info().config_path, machine.configuration_text(desired)), "save repair fixture")
	game.vm_run("systemctl restart " + str(game.vm_info().service))
	for _round in 3:
		for probe in game.diagnostic_probes():
			if not bool(probe.get("passed", false)): game.run_diagnostic(str(probe.id))
		game.verify()
		var counts := BUSINESS.delivery_measurement_counts(game.diagnostic_probes())
		if int(counts.stale) > 0:
			saw_stale_measurement = true
			check(BUSINESS.delivery_blockers(game).any(func(item): return "過去の結果" in str(item.message)), "real invalidated measurement is explained as past evidence")
		if game.state.checks.all(func(item): return bool(item.passed)): break
	check(game.state.checks.all(func(item): return bool(item.passed)), "actual recorded checks pass")

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	check(ui._new_game(), "isolated new game")
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900); ui._set_text_scale(1.3 if narrow else 1.0)
	check(game.choose_strategy("operations"), "strategy selected")
	ui.open_panel("terminal"); pc = ui.desktop; await frames()
	await click("GuideMailMessage"); await capture("01-customer-request")
	await click("GuideMailAccept")
	check(game.state.accepted and pc.current_app == "browser" and pc.browser_url == pc.SAMBA_URL, "acceptance lands on customer service")
	check(not game.vm_info().connected and float(game.state.work.minutes) == 0 and not game.state.inspected, "acceptance route has no connection or work side effects")
	check(game.diagnostic_probes().all(func(p): return not bool(p.get("recorded", false))), "acceptance creates no observation")
	await capture("02-accepted-service")
	await click("SambaConnect")
	await create_timer(0.25).timeout; await frames()
	check(game.vm_info().connected, "explicit connect establishes session")
	await click("GuidedTutorialLocate")
	check(control("GuideBaseline") != null and control("GuideBaseline").is_visible_in_tree(), "baseline Locate expands disclosure")
	check(clipped(control("GuideBaseline")).size.y >= 20, "baseline Locate scrolls target into view")
	await capture("03-located-baseline"); await click("GuideBaseline")
	game.run_diagnostic("staff-write")
	var observed: Dictionary = {}
	for probe in game.diagnostic_probes():
		if str(probe.id) == "staff-write": observed = probe
	check(bool(observed.get("recorded", false)) and not bool(observed.get("passed", true)), "first failed business use actually recorded")
	solve()
	check(saw_stale_measurement, "normal business write produced the regression freshness case")
	# A normal write invalidates an earlier read. This is stale, not a failure.
	var counts := BUSINESS.delivery_measurement_counts([{"recorded":false}, {"recorded":true,"fresh":false,"passed":false}, {"recorded":true,"fresh":true,"passed":false}, {"recorded":true,"fresh":true,"passed":true}])
	check(counts == {"unrecorded":1,"stale":1,"failed":1,"passed":1}, "four measurement states remain distinct")
	pc._show_app("receipt"); await frames(); await click("GuideDeliver")
	check(game.current_done(), "native delivery succeeds")
	var receipt: Dictionary = game.completion_receipt().duplicate(true)
	var results: Array = receipt.get("delivery_results", [])
	check(results.size() == 1 and not str(results[0].host).is_empty(), "receipt captures actual target")
	check(not results.is_empty() and results[0].probes.size() == game.diagnostic_probes().size(), "receipt keeps every recorded probe")
	check(control("ReceiptEvaluation").visible and not control("ReceiptFinance").visible, "customer outcome is first receipt view")
	check(control("ReceiptOutcomeBoard") != null and control("ReceiptTarget_0") is Button, "saved impacts and selectable site are first view")
	await capture("04-customer-outcome")
	await click("ReceiptEvidenceButton")
	check(control("ReceiptEvidenceSelection") is OptionButton, "immutable evidence selection available")
	check(control("ReceiptOutcome_staff-write") != null and control("ReceiptOutcome_guest-read") != null, "all business and protection checks retained behind evidence")
	check(control("DiagnosticFirst") is CodeEdit and control("DiagnosticLatest") is CodeEdit, "real first/latest comparison retained")
	await capture("05-recorded-evidence")
	# Receipt bytes survive both live machine changes and save/reload.
	game._vm()._active_probes()[0]["result"] = "later live change"
	check(game.completion_receipt() == receipt, "receipt snapshot is independent of live VM")
	check(game.save_game() and game.load_game(), "receipt save/reload")
	check(game.completion_receipt().get("delivery_results", []) == results, "receipt snapshot survives reload")
	pc._refresh_receipt(); await frames()
	(pc.widgets.receipt.body.get_parent() as ScrollContainer).scroll_vertical = 0; await frames()
	await click("ReceiptFinanceTab")
	check(control("ReceiptFinance").visible and control("ReceiptSales") is Label, "finance remains reachable")
	await capture("06-finance")
	# Legacy receipts must not acquire fictional response bytes or target names.
	var legacy := RECEIPT._saved_results({"checks":[{"label":"saved result","passed":true}]})
	check(legacy.size() == 1 and legacy[0].probes.is_empty() and not legacy[0].has("host"), "legacy fallback never fabricates evidence")
	await multi_target_snapshot()
	print("JOURNEY_OUTCOMES_", "PASS" if failures.is_empty() else "FAIL", " narrow=", narrow, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func multi_target_snapshot() -> void:
	ui.close_panel(false, false)
	check(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(), "multi-target fixture company")
	var offer: Dictionary = {}
	for item in game.state.offers:
		if int(item.chapter) == 0 and bool(item.unlocked): offer = item.duplicate(true); break
	check(not offer.is_empty(), "shared-folder fixture offer")
	if offer.is_empty(): return
	offer["target_specs"] = [{"chapter":0,"case_id":offer.case_id,"name":"East office"},{"chapter":0,"case_id":offer.case_id,"name":"West office"}]
	offer.targets = 2; offer.market_available = true; game.state.offers = [offer]
	check(game.choose_contract(str(offer.id)), "two-target fixture accepted")
	for index in 2:
		check(game.select_target(index), "select target " + str(index))
		game.vm_run("ssh client"); solve()
	check(game.deliver(), "two actual targets delivered")
	var results: Array = game.completion_receipt().get("delivery_results", [])
	check(results.size() == 2, "snapshot contains both targets")
	if results.size() != 2: return
	check(str(results[0].target) == "East office" and str(results[1].target) == "West office", "snapshot preserves target identity")
	for result in results:
		check(not result.checks.is_empty() and not result.probes.is_empty(), "each target has its own saved checks and probes")
	var saved: Array = results.duplicate(true)
	check(game.save_game() and game.load_game(), "multi-target save/reload")
	check(game.completion_receipt().delivery_results == saved, "both target results persist")
