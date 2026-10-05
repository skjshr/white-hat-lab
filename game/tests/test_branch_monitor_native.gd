extends "res://tests/test_business_source_native.gd"
## Same genuine funded branch journey, with native cross-host monitoring routes.
const BRANCH_MAP = preload("res://scripts/branch_monitor_canvas.gd")
var first_sales := true
var tested_switch_retry := false
var sales_refreshes := 0

func qa_profile() -> String: return "branch-monitor-native"
func report_name() -> String: return "branch-monitor-native"
func journey_timeout() -> float: return 360.0

func monitor() -> bool:
	return await route("monitor") and await press("MonitorTab_monitor")

func connect_machine(index: int) -> bool:
	if int(game.state.target_index) != index:
		if not await monitor(): return false
		var before: Dictionary = game.state.duplicate(true); var live: Dictionary = game._machine.export_state()
		if not await press("BranchNode_%d" % index): return false
		if index == 2 and not await keyboard_activate("BranchNode_2"): return false
		if not expect(game.state.target_index == before.target_index and game.state.vm_states == before.vm_states and game._machine.export_state() == live and game.state.cash == before.cash and game.state.clock_minutes == before.clock_minutes, "diagram selection does not connect, switch host, sample or charge work"): return false
		if not tested_switch_retry:
			var path: String = game.save_path
			game.save_path = "user://missing-branch-monitor-%d/save.json" % OS.get_process_id()
			var clicked: bool = await press("BranchOpenControls")
			game.save_path = path
			if not clicked: return false
			if not expect(game.state.target_index == before.target_index and game.state.vm_states == before.vm_states and game._machine.export_state() == live and game.state.cash == before.cash and game.state.clock_minutes == before.clock_minutes, "failed target checkpoint leaves real selected host, files, funds and time unchanged"): return false
			await capture("monitor-switch-save-failed"); tested_switch_retry = true
		if not await press("BranchOpenControls") or not expect(int(game.state.target_index) == index, "explicit diagram control action changes selected host"): return false
	if not await super.connect_machine(index): return false
	if index != 0:
		if not await monitor(): return false
		if not expect(int(ui.desktop.monitor_ui.get("branch_target_index", -1)) == index, "explicit navigation focuses destination in resumed per-host monitor session"): return false
		var order: Dictionary = game.service_monitor_snapshot(0)
		var probe := BRANCH_MAP.probe_in(order, "branch-business-orders")
		if not expect(text_in(control("BranchLink_branch-business-orders")).contains(BRANCH_MAP.SAMPLE.status(probe)), "another selected host retains the gateway's actual recorded failure or stale sample"): return false
		await capture("monitor-selected-host-%d-%d" % [index, clicks])
		if not await route("terminal"): return false
	return true

func browse(url: String) -> bool:
	if not await super.browse(url): return false
	if url == SALES and first_sales:
		first_sales = false
		if not await order_measurement("× 不合格", "monitor-01-original-failure", false): return false
		return await route("browser")
	return true

func refresh_sales() -> bool:
	if not await super.refresh_sales(): return false
	sales_refreshes += 1
	var expected := "× 不合格" if ui.desktop.browser_response.contains("malformed_orders_row") else "✓ 合格"
	if not await order_measurement(expected, "monitor-%02d-source-change" % (sales_refreshes + 1), true): return false
	return await route("browser")

func order_measurement(expected: String, screenshot_name: String, require_stale: bool) -> bool:
	if not await monitor(): return false
	if not expect(is_instance_valid(control("BranchNode_0")) and is_instance_valid(control("BranchNode_1")) and is_instance_valid(control("BranchNode_2")), "all three real targets remain in one customer map"): return false
	if require_stale:
		if not expect(text_in(control("BranchLink_branch-business-orders")).contains("古い測定"), "source change expires earlier order measurement before explicit diagnosis"): return false
		await capture(screenshot_name + "-before-measurement")
	if not await press("BranchLink_branch-business-orders") or not await press("BranchInspectProbe") or not await press("DiagnosticRun"): return false
	if not await monitor(): return false
	if not expect(text_in(control("BranchLink_branch-business-orders")).contains(expected), "edge shows actual new acceptance result " + expected): return false
	if not await fit_map(): return false
	await capture(screenshot_name)
	return true

func fit_map() -> bool:
	var map := control("BranchServiceMap")
	if not await scroll_to(map): return false
	var area := root.get_visible_rect().grow(1)
	for label in map.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree(): continue
		if not expect(label.get_global_rect().position.x >= area.position.x and label.get_global_rect().end.x <= area.end.x, "topology caption stays within horizontal viewport"): return false
		if not expect(label.get_theme_font_size("font_size") >= int(14 * float(game.settings.text_scale)) and label.get_line_count() == 1, "topology caption keeps enlarged single-line font"): return false
		var natural: float = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		if not expect(label.size.x + 1 >= natural, "topology caption fits the actual allocated width"): return false
		var owner := label.get_parent() as Control
		if not expect(owner.get_global_rect().grow(1).encloses(label.get_global_rect()), "topology caption stays inside its device shape vertically"): return false
	var before: Dictionary = game.state.duplicate(true); var live: Dictionary = game._machine.export_state()
	ui.desktop._refresh_monitor(); await frames(8)
	return expect(game.state == before and game._machine.export_state() == live, "customer monitor redraw preserves every Game and guest value")

func source_visible(host: String, file_name: String) -> bool:
	if not await super.source_visible(host, file_name): return false
	if not await monitor(): return false
	if not await fit_map(): return false
	var map = control("BranchServiceMap")
	if not expect(map.file_data.any(func(item): return str(item.path) == "/srv/share/partner-order.csv" and bool(item.known) and bool(item.present)), "actual source file stays present from another selected host"): return false
	if sales_refreshes == 0:
		if not expect(text_in(control("BranchNode_2")).contains("未確認"), "unopened portal is unknown instead of an invented healthy VM"): return false
	if sales_refreshes >= 3:
		if not expect(int(ui.desktop.monitor_ui.get("branch_target_index", -1)) == 0 and str(ui.desktop.monitor_ui.get("branch_probe_id", "")) == "branch-business-orders", "save/resume preserves selected gateway and actual order probe"): return false
	return await route("browser")
