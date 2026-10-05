extends RefCounted
const UI = preload("res://scripts/ui_theme.gd")
const MAP = preload("res://scripts/branch_monitor_canvas.gd")
const SAMPLE = preload("res://scripts/service_monitor_canvas.gd")
const DIAGNOSTICS = preload("res://scripts/os_diagnostics.gd")
const BLUE := Color("315b91")

static func render(d, parent: VBoxContainer, snapshot: Dictionary, footer: VBoxContainer) -> void:
	var services: Array = snapshot.get("services", [])
	var selected := int(d.monitor_ui.get("branch_target_index", snapshot.get("current_target", 0)))
	var entry: Dictionary = {}
	for service in services:
		if int(service.index) == selected: entry = service; break
	if entry.is_empty() and not services.is_empty(): entry = services[0]; selected = int(entry.index)
	var info: Dictionary = entry.get("snapshot", {})
	var probes: Array = info.get("probes", [])
	var probe_id := str(d.monitor_ui.get("branch_probe_id", ""))
	if MAP.probe_in(info, probe_id).is_empty():
		var failed: Array = probes.filter(func(probe): return bool(probe.get("recorded", false)) and not bool(probe.get("passed", false)))
		probe_id = str(failed[0].id) if not failed.is_empty() else str(probes[0].id) if not probes.is_empty() else ""
	var map = MAP.new(); parent.add_child(map); map.setup(d, snapshot, selected)
	map.target_selected.connect(func(index: int, id: String):
		d.monitor_ui["branch_target_index"] = index; d.monitor_ui["branch_probe_id"] = id; d._save_session(false); d._refresh_monitor()
		var focus_id: String = {"branch-source-customers":"BranchFile_customers", "branch-source-orders":"BranchFile_orders", "branch-business-orders":"BranchLink_branch-business-orders", "branch-probe-shared":"BranchLink_branch-probe-shared"}.get(id, "BranchNode_%d" % index)
		var focus = d.widgets.monitor.body.find_child(focus_id, true, false)
		if is_instance_valid(focus): focus.grab_focus())
	var selected_probe := MAP.probe_in(info, probe_id)
	var selected_label: Label = d._label(str(info.get("host", "")) + " · " + SAMPLE.status(selected_probe), 14, BLUE)
	selected_label.name = "BranchSelectedTarget"; selected_label.tooltip_text = str(entry.get("name", "")); selected_label.autowrap_mode = TextServer.AUTOWRAP_OFF; selected_label.clip_text = true; footer.add_child(selected_label)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 6); actions.add_theme_constant_override("v_separation", 6); footer.add_child(actions)
	var picker := OptionButton.new(); picker.name = "BranchProbeSelector"; picker.custom_minimum_size.x = 180
	picker.add_theme_font_size_override("font_size", int(14 * float(d.game.settings.get("text_scale", 1.0))))
	for index in probes.size():
		var probe: Dictionary = probes[index]; picker.add_item(SAMPLE.status(probe) + " · " + str(probe.get("label", probe.id)))
		if str(probe.id) == probe_id: picker.select(index)
	if probes.is_empty(): picker.add_item("？ 接続後に検査対象を取得"); picker.disabled = true
	picker.item_selected.connect(func(index: int): d.monitor_ui["branch_target_index"] = selected; d.monitor_ui["branch_probe_id"] = str(probes[index].id); d._save_session(false); d._refresh_monitor())
	actions.add_child(picker)
	var inspect: Button = d._button("診断へ", func(): _open(d, selected, probe_id, true))
	inspect.name = "BranchInspectProbe"; inspect.disabled = probe_id.is_empty(); UI.os_primary(inspect, BLUE); actions.add_child(inspect)
	var controls: Button = d._button("制御へ", func(): _open(d, selected, probe_id, false))
	controls.name = "BranchOpenControls"; actions.add_child(controls)
	var details: VBoxContainer = d._disclosure(parent, "設備の状態・測定記録")
	details.add_child(d._label("受入計測  ✓ 合格 / × 不合格 / ↻ 古い測定 / ○ 未測定 / ？ 未確認", 12, UI.MUTED))
	details.add_child(d._label("▶ 稼働 / ■ 停止 / ？ 未確認 · ! 未適用 · プラグは実際の操作先", 12, UI.MUTED))
	details.add_child(d._label(MAP.coverage(info), 14, BLUE))
	var result: Label = d._label(SAMPLE.status(selected_probe), 14, SAMPLE.tint(selected_probe)); result.name = "BranchSelectedStatus"; details.add_child(result)
	details.add_child(d._label(str(info.get("config_path", "")), 13, UI.MUTED))
	var records: Array = []
	for item in info.get("observations", []):
		if str(item.get("probe_id", "")) == probe_id or (not item.has("probe_id") and not selected_probe.is_empty() and str(item.get("command", "")) == str(selected_probe.get("command", ""))):
			var record: Dictionary = item.duplicate(true); record["sample_index"] = records.size() + 1; records.append(record)
	var history = SAMPLE.new(); details.add_child(history); history.setup_history(d, records.slice(maxi(0, records.size() - 8)))
	if records.is_empty(): details.add_child(d._label("未測定", 13, UI.MUTED))
	for record in records:
		var response: Label = d._label("#%d  %s\n%s" % [int(record.sample_index), str(record.get("command", "")), str(record.get("output", ""))], 12, UI.INK)
		response.add_theme_font_override("font", d.mono); details.add_child(response)

static func _open(d, index: int, id: String, diagnose: bool) -> void:
	if int(d.game.state.target_index) != index and not d._select_target(index):
		d._notify("端末を切り替えられませんでした。保存を確認して再試行してください。")
		return
	# Explicit navigation should also focus its destination in that host's saved
	# monitor session, rather than revive a selection left on another device.
	d.monitor_ui["branch_target_index"] = index; d.monitor_ui["branch_probe_id"] = id; d._save_session(false)
	if diagnose:
		d._show_app("verify")
		if not id.is_empty(): DIAGNOSTICS._select(d, id)
	else:
		d._show_app("monitor"); d.widgets.monitor.tab = "overview"; d.monitor_ui["tab"] = "overview"; d._save_session(false); d._refresh_monitor()
