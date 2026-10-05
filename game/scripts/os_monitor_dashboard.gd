extends RefCounted
const UI = preload("res://scripts/ui_theme.gd")
const CANVAS = preload("res://scripts/service_monitor_canvas.gd")
const DIAGNOSTICS = preload("res://scripts/os_diagnostics.gd")
const BLUE := Color("315b91")

static func render(d, parent: VBoxContainer, snapshot: Dictionary) -> void:
	var w: Dictionary = d.widgets.monitor
	var probes: Array = snapshot.get("probes", [])
	var selected := str(w.get("selected_probe", ""))
	if not probes.any(func(probe): return str(probe.get("id", "")) == selected):
		var failed: Array = probes.filter(func(probe): return bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and not bool(probe.get("passed", false)))
		selected = str(failed[0].id) if not failed.is_empty() else str(probes[0].id) if not probes.is_empty() else ""
	w["selected_probe"] = selected
	var header := PanelContainer.new(); header.add_theme_stylebox_override("panel", UI.style(Color("243a56"), Color.TRANSPARENT, 12, 9, 0)); parent.add_child(header)
	var heading = d._row(header, 8)
	var title: Label = d._label("サービス監視 · " + str(snapshot.get("client", "")), 17, Color.WHITE); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.add_child(title)
	var counts := {"pass":0,"fail":0,"stale":0,"unknown":0,"uncertain":0}
	for probe in probes:
		if not bool(probe.get("recorded", false)): counts.unknown += 1
		elif not bool(probe.get("freshness_known", true)): counts.uncertain += 1
		elif not bool(probe.get("fresh", false)): counts.stale += 1
		elif bool(probe.get("passed", false)): counts["pass"] += 1
		else: counts.fail += 1
	var summary: Label = d._label("✓ %d   × %d   ↻ %d   ○ %d" % [counts["pass"],counts.fail,counts.stale,counts.unknown], 13, Color.WHITE); summary.name = "MonitorCoverage"; heading.add_child(summary)
	if int(counts.uncertain) > 0: summary.text += "   ？ %d" % int(counts.uncertain)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 6); actions.add_theme_constant_override("v_separation", 5); parent.add_child(actions)
	var inspect: Button = d._button("選択した対象を診断", func():
		d._show_app("verify")
		if not selected.is_empty(): DIAGNOSTICS._select(d, selected))
	inspect.name = "MonitorInspectProbe"; UI.os_primary(inspect, BLUE); inspect.disabled = selected.is_empty(); actions.add_child(inspect)
	var controls: Button = d._button("サービス制御", func(): d.widgets.monitor.tab = "overview"; d.monitor_ui["tab"] = "overview"; d._save_session(false); d._refresh_monitor())
	controls.name = "MonitorOpenControls"; actions.add_child(controls)
	var legend: Label = d._label("受入計測 · ✓ 合格 / × 不合格 / ↻ 古い測定 / ○ 未測定", 12, UI.MUTED); parent.add_child(legend)
	if int(counts.uncertain) > 0: legend.text += " / ？ 連携元の保存記録なし"
	var map = CANVAS.new(); parent.add_child(map); map.setup_map(d, snapshot, selected)
	map.probe_selected.connect(func(id: String):
		w.selected_probe = id; d.monitor_ui["selected_probe"] = id; d._save_session(false); d._refresh_monitor()
		var focus = w.body.find_child("MonitorProbe_" + id.validate_node_name(), true, false)
		if is_instance_valid(focus): focus.grab_focus())
	var probe: Dictionary = {}
	for item in probes:
		if str(item.get("id", "")) == selected: probe = item; break
	if probe.is_empty():
		parent.add_child(d._label("保存された受入計測はありません。", 13, UI.MUTED)); return
	var result: Label = d._label(str(probe.get("label", selected)) + "  /  " + CANVAS.status(probe), 15, CANVAS.tint(probe)); result.name = "MonitorSelectedStatus"; parent.add_child(result)
	var records: Array = []
	for item in snapshot.get("observations", []):
		if str(item.get("probe_id", "")) == selected or (not item.has("probe_id") and str(item.get("command", "")) == str(probe.get("command", ""))):
			var record: Dictionary = item.duplicate(true); record["sample_index"] = records.size() + 1; records.append(record)
	var label: Label = d._label("測定履歴 · 実行順   ✓ 合格 / × 不合格 / ？ 判定不明", 12, UI.MUTED); parent.add_child(label)
	var history = CANVAS.new(); parent.add_child(history); history.setup_history(d, records.slice(maxi(0, records.size() - 8)))
	if records.is_empty(): parent.add_child(d._label("未測定 · 診断を実行すると記録が増えます。", 12, UI.MUTED))
	var details: VBoxContainer = d._disclosure(parent, "測定の応答と過去の記録")
	for record in records:
		var row: Label = d._label("#%d  %s\n%s" % [int(record.sample_index), str(record.get("command", "")), str(record.get("output", ""))], 12, UI.INK)
		row.add_theme_font_override("font", d.mono); details.add_child(row)
