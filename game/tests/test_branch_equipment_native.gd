extends "res://tests/test_diagnostic_workbench_native.gd"
## Equipment selection and fixed actions inside the complete real branch loop.
var tested_files := false

func qa_profile() -> String: return "branch-equipment-native"
func report_name() -> String: return "branch-equipment-native"

func monitor() -> bool:
	if not await super.monitor(): return false
	var map = control("BranchServiceMap")
	if not expect(map.node_data.size() == 3 and map.files.size() == 2 and map.edges.size() == 2, "actual three devices and two stored-source specimens share one equipment plan"): return false
	if not expect(int(map.data.current_target) == int(game.state.target_index), "actual operation target is independent from graphical selection"): return false
	for index in map.nodes.size():
		var marker: Rect2 = map.operation_marker_rect(index)
		if not expect(map.nodes[index].get_rect().encloses(marker) and map.files.all(func(file): return not file.get_rect().intersects(marker)), "operation target marker stays visible beside equipment, outside paper shapes"): return false
	for id in ["BranchInspectProbe", "BranchOpenControls"]:
		var button = control(id)
		if not expect(clipped_rect(button).grow(1).encloses(button.get_global_rect()), "primary route stays visible in fixed toolbar " + id): return false
	return true

func fit_map() -> bool:
	if not await super.fit_map(): return false
	var map = control("BranchServiceMap")
	if not expect(clipped_rect(map).grow(1).encloses(map.get_global_rect()), "whole equipment plan fits its scroller at requested text scale"): return false
	for target in map.nodes + map.files + map.edges:
		if not expect(map.get_global_rect().grow(1).encloses(target.get_global_rect()) and clipped_rect(target).grow(1).encloses(target.get_global_rect()), "device, paper and measured route stay inside visible equipment plan " + str(target.name)): return false
	return true

func source_visible(host: String, file_name: String) -> bool:
	if not await super.source_visible(host, file_name): return false
	if not await monitor() or not await fit_map(): return false
	if not tested_files:
		var before: Dictionary = game.state.duplicate(true); var live: Dictionary = game._machine.export_state()
		for spec in [["orders", "branch-source-orders"], ["customers", "branch-source-customers"]]:
			if not await press("BranchFile_" + str(spec[0])): return false
			if not expect(control("BranchFile_" + str(spec[0])).has_focus(), "paper retains keyboard focus after its selection refresh"): return false
			if not expect(int(ui.desktop.monitor_ui.branch_target_index) == 1 and str(ui.desktop.monitor_ui.branch_probe_id) == str(spec[1]), "stored paper selects its actual preservation check " + str(spec[0])): return false
			if not expect(game.state.target_index == before.target_index and game.state.vm_states == before.vm_states and game._machine.export_state() == live and game.state.cash == before.cash and game.state.clock_minutes == before.clock_minutes, "paper selection leaves customer files, target, funds and time unchanged"): return false
		if not await keyboard_activate("BranchFile_orders"): return false
		await capture("equipment-file-selected")
		if not await press("BranchNode_%d" % int(before.target_index)): return false
		tested_files = true
	await capture("equipment-source-%02d" % sales_refreshes)
	return await route("browser")
