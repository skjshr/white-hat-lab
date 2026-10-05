extends "res://tests/test_network_request_ui.gd"
## Public normal-funded day-one acceptance setup. Connection, measurement,
## repair, remeasurement and delivery use actual Godot mouse/key dispatch.
## Save/load APIs deliberately exercise interruption; no answer/state injection.
const MAP = preload("res://scripts/service_monitor_canvas.gd")

func run() -> void:
	game = root.get_node("Game")
	if not expect("--qa-profile=service-monitor-ui" in OS.get_cmdline_user_args(), "isolated monitor QA profile"): finish(); return
	game.set_process(false)
	if not expect(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(), "public normal funded career setup"): finish(); return
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked",false)) and bool(item.get("market_available",true)) and str(item.get("case_id","")) == "service-2-case-0")
	if not expect(not offers.is_empty() and game.choose_contract(str(offers[0].id)), "accept naturally available service case via public API"): finish(); return
	game.inspect_mission()
	ui = INTERFACE.new(); root.add_child(ui); await frames(10)
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0},false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui._set_text_scale(1.3 if narrow else 1.0); ui.controls.menu.hide(); ui.next_task_guide.set_enabled(false); ui.open_panel("terminal"); await frames(10)
	root.grab_focus()
	if not await route("terminal"): finish(); return
	if not await press("TerminalConnect"): finish(); return
	if not await route("monitor"): finish(); return
	if not await map_state("dns-check", "○ 未測定"): finish(); return
	await capture("01-unmeasured")
	if not await press("MonitorProbe_dns-check"): finish(); return
	if not await keyboard_activate("MonitorInspectProbe", true): finish(); return
	if not expect(str(ui.desktop.widgets.verify.selected) == "dns-check", "map selection routes same probe without measuring"): finish(); return
	if not await press("DiagnosticRun"): finish(); return
	if not await route("monitor"): finish(); return
	if not await map_state("dns-check", "× 不合格"): finish(); return
	await capture("02-real-failure")
	if not await press("MonitorOpenControls"): finish(); return
	if not await press("ServiceOpenWorkspace"): finish(); return
	if not await press("FirewallNav_services"): finish(); return
	if not await select_option("FirewallDNS", 1): finish(); return
	if not await press("FirewallServicesSave"): finish(); return
	if not await route("monitor"): finish(); return
	if not await press_control(find_text_button(ui.desktop.widgets.monitor.body, "監視"), "監視 tab"): finish(); return
	if not await map_state("dns-check", "↻ 古い測定"): finish(); return
	if not expect(bool(game.service_monitor_snapshot().dirty) and str(game.service_monitor_snapshot().applied.dns) == "off", "saved pending editor does not silently apply"): finish(); return
	await capture("03-pending-stale")
	if not await route("browser"): finish(); return
	if not await press("FirewallApply"): finish(); return
	if not await route("monitor"): finish(); return
	if not await press("MonitorInspectProbe"): finish(); return
	if not await press("DiagnosticRun"): finish(); return
	if not await route("monitor"): finish(); return
	if not await map_state("dns-check", "✓ 合格"): finish(); return
	var history = control("ServiceMeasurementHistory")
	if not expect(history.samples.size() == 2 and not bool(history.samples[0].probe_passed) and bool(history.samples[1].probe_passed), "actual failed then passing samples remain separate"): finish(); return
	if not await scroll_to(history.sample_labels.back()): finish(); return
	if not expect(clipped_rect(history).size.y >= history.size.y - 1, "whole history including sample labels fits visible scroller"): finish(); return
	await capture("04-real-history")
	if not expect(ui.desktop._save_session() and game.save_game(), "persist selected monitor tab and actual samples"): finish(); return
	ui.queue_free(); await frames(6)
	if not expect(game.load_game(), "interrupt and reload durable isolated save"): finish(); return
	ui = INTERFACE.new(); root.add_child(ui); await frames(10); ui.controls.menu.hide(); ui.next_task_guide.set_enabled(false); ui.open_panel("terminal"); await frames(10)
	if not await route("monitor"): finish(); return
	if not expect(str(ui.desktop.widgets.monitor.tab) == "monitor" and str(ui.desktop.widgets.monitor.selected_probe) == "dns-check", "resume restores monitor view and selected measurement"): finish(); return
	if not await map_state("dns-check", "✓ 合格"): finish(); return
	await capture("05-resumed")
	var ids: Array[String] = []
	for probe in game.service_monitor_snapshot().probes: ids.append(str(probe.id))
	if not await route("verify"): finish(); return
	for id in ids:
		if id == "dns-check": continue
		if not await press("DiagnosticProbe_" + id): finish(); return
		if not await press("DiagnosticRun"): finish(); return
	if not await press("DiagnosticValidate"): finish(); return
	if not expect(game.can_deliver(), "fresh actual measurements allow delivery"): finish(); return
	if not await press("GuideDeliver"): finish(); return
	if not expect(game.current_done() and not str(game.completion_receipt().get("invoice_id", "")).is_empty(), "actual delivery creates customer invoice"): finish(); return
	if not await press("ReceiptEvaluationTab"): finish(); return
	await capture("06-customer-result")
	if not OS.get_environment("WHL_MONITOR_NINE_FIXTURE").is_empty() and not await nine_probe_fixture(): finish(); return
	journey_completed = true; finish()

func nine_probe_fixture() -> bool:
	# A copy of the ordinary, manually accepted sharing case captured before
	# this change. This checkpoint is geometry/navigation/compatibility proof,
	# not another full nine-probe playthrough or an invented unlocked account.
	var source := OS.get_environment("WHL_MONITOR_NINE_FIXTURE")
	var original := FileAccess.get_file_as_string(source)
	if not expect(not original.is_empty() and game.save_path.begins_with("user://qa-"), "nine-probe fixture copies only to isolated QA output"): return false
	ui.queue_free(); await frames(6)
	var file := FileAccess.open(game.save_path,FileAccess.WRITE)
	if not expect(file != null, "open isolated fixture destination"): return false
	file.store_string(original); file.close()
	if not expect(game.load_game() and str(game.state.contract.case_id) == "service-5-case-0", "load actual manually accepted old sharing checkpoint"): return false
	game.set_process(false)
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0,"volume":0},false)
	ui = INTERFACE.new(); root.add_child(ui); await frames(10); ui._set_text_scale(1.3 if narrow else 1.0); ui.controls.menu.hide(); ui.next_task_guide.set_enabled(false); ui.open_panel("terminal"); await frames(10)
	if not await route("monitor"): return false
	if not await map_state("partner-write", "× 不合格"): return false
	if not expect(control("ServiceMeasurementMap").endpoints.size() == 9, "all nine real sharing measurements fit diagram allocation"): return false
	await capture("07-nine-probe-old-save")
	var vm_before: Dictionary = game._vm().export_state(); var clock: String = game.business_clock()
	if not await press("MonitorProbe_portal-audit"): return false
	if not await press("MonitorInspectProbe"): return false
	if not expect(str(ui.desktop.widgets.verify.selected) == "portal-audit" and game._vm().export_state() == vm_before and game.business_clock() == clock, "last diagram node routes to matching diagnostic without implicit measurement"): return false
	await capture("08-last-node-route")
	if not await route("monitor"): return false
	if not await press_control(find_text_button(ui.desktop.widgets.monitor.body, "構成"), "構成 tab"): return false
	var files: Array = game.service_monitor_snapshot().portal_files
	if not expect(files.size() == 1 and text_in(ui.desktop.widgets.monitor.body).contains(str(files[0].name)) and text_in(ui.desktop.widgets.monitor.body).contains(str(files[0].size) + " B"), "configuration pane shows same actual file and byte count as shared-storage projection"): return false
	if not expect(game._vm().export_state() == vm_before and game.business_clock() == clock, "configuration readback does not run a command or alter guest"): return false
	await capture("09-portal-config-readback")
	return expect(FileAccess.get_file_as_string(source) == original, "manual source checkpoint remains unchanged")

func map_state(id: String, status: String) -> bool:
	await frames(12)
	var map = control("ServiceMeasurementMap")
	if not expect(is_instance_valid(map) and map.is_visible_in_tree(), "real monitor map visible"): return false
	var probe: Dictionary = {}
	for item in map.data.probes:
		if str(item.id) == id: probe = item; break
	if not expect(not probe.is_empty() and MAP.status(probe) == status, "map shows " + status): return false
	var bounds: Rect2 = map.get_global_rect().grow(1)
	if not expect(bounds.encloses(map.host.get_global_rect()), "host fits its diagram without overlapping history"): return false
	for endpoint in map.endpoints:
		if not expect(bounds.encloses(endpoint.get_global_rect()), "measurement button fits diagram allocation"): return false
	if not expect(is_equal_approx(map.scale_factor,1.3 if narrow else 1.0), "map follows actual text enlargement"): return false
	var vm_before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
	ui.desktop._refresh_monitor(); await frames(8)
	return expect(game._vm().export_state() == vm_before and int(game.state.cash) == cash and game.business_clock() == clock, "monitor redraw does not run measurements or alter guest, funds or work clock")

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("monitor journey incomplete")
	var report := {"assertions":assertions,"narrow":narrow,"clicks":clicks,"keys":keys,"scrolls":scrolls,"failures":failures,"events":events,"nine_probe_checkpoint":not OS.get_environment("WHL_MONITOR_NINE_FIXTURE").is_empty(),"method":"Public normal-funded day-one career acceptance and inspect setup. Background realtime paused, actual action costs retained. Actual Godot Input mouse/key dispatch for connection, measurement, repair, delivery; save/load APIs for interruption. No answers, progression, cash or VM-state injection in the full career loop. Optional manually accepted sharing save copied to isolated QA only for nine-node geometry/navigation compatibility. Known controls; not first-time human comprehension evidence."}
	var file := FileAccess.open(folder.path_join("monitor-native.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"  ")); file.close()
	print("SERVICE_MONITOR_UI_", "PASS" if failures.is_empty() else "FAIL", " assertions=",assertions," clicks=",clicks," keys=",keys," scrolls=",scrolls," failures=",failures)
	if is_instance_valid(ui): ui.queue_free(); await frames(5)
	quit(0 if failures.is_empty() else 1)
