extends "res://tests/test_branch_monitor_native.gd"
## Actual intake-to-payment branch loop with recorded graphical observations.
var sample_runs := 0
var tested_diagnostic_retry := false

func qa_profile() -> String: return "diagnostic-workbench-native"
func report_name() -> String: return "diagnostic-workbench-native"
func journey_timeout() -> float: return 480.0

func build_ui() -> void:
	# Deliver each injected native event immediately, rather than merging it
	# with the Windows pointer poll at the end of a rendering frame.
	Input.use_accumulated_input = false
	await super.build_ui()

func press(id: String) -> bool:
	var ok := await super.press(id)
	if not ok: await capture("blocked-" + id)
	return ok

func refresh_sales() -> bool:
	# The parent journey's HTTP200 assumption intentionally does not cover a
	# valid but changed order. This case must fail preservation acceptance.
	if not await route("browser"): return false
	if str(ui.desktop.browser_url) != SALES or not shown("BusinessStorageRefresh"):
		if not await browse(SALES): return false
	elif not await press("BusinessStorageRefresh"): return false
	sales_refreshes += 1
	var expected := "× 不合格" if ui.desktop.browser_response.contains("malformed_orders_row") or ui.desktop.browser_response.contains("12900") else "✓ 合格"
	if not await order_measurement(expected, "workbench-%02d-source-change" % sales_refreshes, true): return false
	return await route("browser")

func before_invalid_order(original: String) -> bool:
	if not await edit("PortalCell_1_2", "12900") or not await press("PortalWrite"): return false
	if not await connect_machine(0) or not await refresh_sales(): return false
	if not expect(ui.desktop.browser_response.contains("12900") and control("BusinessOrderList") != null, "valid changed order is really available to ordinary business"): return false
	await capture("valid-business-changed-original")
	if not await connect_machine(2) or not await browse(ui.desktop.PORTAL_URL) or not await compare_original(): return false
	var version: Dictionary = game._vm().portal_snapshot().versions.back()
	if not await press("PortalVersionRestore_" + str(version.id)): return false
	if not expect(game._vm().portal_storage_read(FILE) == original, "restore actual original before testing malformed data"): return false
	return await staff_read() and await ensure_editor()

func order_measurement(expected: String, screenshot_name: String, require_stale: bool) -> bool:
	if not await monitor(): return false
	if require_stale and not expect(text_in(control("BranchLink_branch-business-orders")).contains("古い測定"), "cross-software file changes expire recorded diagnostic before rerun"): return false
	if not await press("BranchLink_branch-business-orders") or not await press("BranchInspectProbe"): return false
	var bench = control("DiagnosticWorkbench")
	if not expect(is_instance_valid(bench), "real diagnostic canvas exists before measuring"): return false
	if sample_runs == 0:
		if not expect(not bool(bench.observation.recorded) and int(bench.observation.status) == 0 and bench.observation.rows.is_empty() and str(bench.observation.hash_match) == "unknown", "unmeasured workbench does not inspect hidden records or invent server health"): return false
		await capture("workbench-unmeasured")
	if require_stale:
		if not expect(bool(bench.observation.recorded) and not bool(bench.observation.fresh), "historical specimen remains explicitly stale until new measurement"): return false
		await capture(screenshot_name + "-stale")
	if not tested_diagnostic_retry:
		var before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
		var path: String = game.save_path
		game.save_path = "user://missing-diagnostic-bench-%d/save.json" % OS.get_process_id()
		var clicked := await press("DiagnosticRun")
		game.save_path = path
		if not clicked: return false
		if not expect(game._vm().export_state() == before and int(game.state.cash) == cash and game.business_clock() == clock, "measurement persistence failure rolls back exact files, evidence, work time and funds"): return false
		if not expect(shown("DiagnosticOperationFailure") and not bool(control("DiagnosticWorkbench").observation.recorded), "save failure shows unmeasured durable state instead of transient success"): return false
		await capture("workbench-measurement-save-failed")
		tested_diagnostic_retry = true
	if not await press("DiagnosticRun"): return false
	sample_runs += 1
	if not await inspect_bench(screenshot_name): return false
	if not await monitor() or not expect(text_in(control("BranchLink_branch-business-orders")).contains(expected), "monitor agrees with graphical diagnosis acceptance " + expected): return false
	return true

func inspect_bench(screenshot_name: String) -> bool:
	var bench = control("DiagnosticWorkbench")
	if not await scroll_to(bench): return false
	if not expect(clipped_rect(bench).grow(1).encloses(bench.get_global_rect()), "complete specimen bench fits actual viewport at configured text size"): return false
	var value: Dictionary = bench.observation
	if not expect(bool(value.recorded) and bool(value.fresh), "workbench uses saved fresh actual measurement"): return false
	if str(value.transport) == "firewall":
		if not expect(value.status == 0 and value.rule == "lan-business" and value.rows.is_empty() and value.source.is_empty(), "actual barrier does not invent downstream server or order state"): return false
	elif int(value.status) == 200:
		if not expect(value.rows.size() == 1 and int(value.rows[0].total) in [12800, 12900], "graphical specimen uses actual business body"): return false
		if int(value.rows[0].total) == 12900:
			if not expect(str(value.hash_match) == "different" and not bool(value.passed), "HTTP200 and valid business data still fail original preservation"): return false
		else:
			if not expect(str(value.hash_match) == "match" and bool(value.passed), "success requires actual full original hash as well as HTTP200"): return false
	elif int(value.status) == 422:
		if not expect(str(value.error) == "malformed_orders_row" and bool(value.source.ok) and value.rows.is_empty() and str(value.hash_match) == "unknown", "readable source with parse failure has no fabricated valid rows or hash"): return false
	await capture(screenshot_name + "-objects")
	var live: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
	if not await press("DiagnosticReplayObservation"): return false
	if not expect(float(control("DiagnosticWorkbench").replay_position) >= 0, "explicit replay animates a recorded observation"): return false
	await capture(screenshot_name + "-replay")
	for id in ["server", "specimen", "seal", "request"]:
		if not await press("DiagnosticObject_" + id): return false
		if not expect(shown("DiagnosticInspector"), "shape selection opens actual evidence " + id): return false
		var inspector = control("DiagnosticInspector")
		if not expect(clipped_rect(inspector).grow(1).encloses(inspector.get_global_rect()), "shape selection reveals complete evidence without another scroll " + id): return false
		if id == "specimen" and value.rows.size() > 0:
			var table := control("DiagnosticSpecimenRows") as Tree
			if not expect(table != null and table.get_root().get_first_child().get_text(2) == str(value.rows[0].total), "object inspector shows exact retrieved amount"): return false
	if not await keyboard_activate("DiagnosticObject_gate"): return false
	var gate_inspector = control("DiagnosticInspector")
	if not expect(clipped_rect(gate_inspector).grow(1).encloses(gate_inspector.get_global_rect()), "keyboard selection reveals complete gate evidence"): return false
	if not await press("DiagnosticInspectorClose") or not await press("DiagnosticCompare"): return false
	if not expect(shown("DiagnosticLatest") and control("DiagnosticLatest").text == str(game.diagnostic_probes().filter(func(item): return str(item.id) == "branch-business-orders")[0].result), "full raw observed response remains available on demand"): return false
	if not await press("DiagnosticCompare"): return false
	if not expect(game._vm().export_state() == live and int(game.state.cash) == cash and game.business_clock() == clock, "object selection, raw comparison and replay never measure, repair or charge work"): return false
	return true
