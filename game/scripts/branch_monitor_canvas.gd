extends Control
## Customer-wide recorded topology. Rendering never connects or samples a VM.
signal target_selected(index: int, probe_id: String)
const UI = preload("res://scripts/ui_theme.gd")
const SAMPLE = preload("res://scripts/service_monitor_canvas.gd")
const GLYPH = preload("res://scripts/service_glyph.gd")
const BLUE := Color("315b91")
var scale_factor := 1.0
var nodes: Array[Button] = []
var edges: Array[Button] = []
var edge_probes: Array[Dictionary] = []

static func probe_in(snapshot: Dictionary, id: String) -> Dictionary:
	for probe in snapshot.get("probes", []):
		if str(probe.get("id", "")) == id: return probe
	return {}

static func coverage(snapshot: Dictionary) -> String:
	if not bool(snapshot.get("initialized", false)): return "受入 ？ 記録なし"
	var counts := [0, 0, 0, 0, 0]
	for probe in snapshot.get("probes", []):
		var index := 3 if not bool(probe.get("recorded", false)) else 4 if not bool(probe.get("freshness_known", true)) else 2 if not bool(probe.get("fresh", false)) else 0 if bool(probe.get("passed", false)) else 1
		counts[index] += 1
	var text := "✓ %d  × %d  ↻ %d  ○ %d" % [counts[0], counts[1], counts[2], counts[3]]
	return text + (" ？ %d" % counts[4] if counts[4] > 0 else "")

func setup(d, snapshot: Dictionary, selected_index: int) -> void:
	name = "BranchServiceMap"; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_factor = float(d.game.settings.get("text_scale", 1.0))
	custom_minimum_size.y = 288 * scale_factor
	var services: Array = snapshot.get("services", [])
	# Physical data flow forks from Samba, never from the gateway to the portal.
	for chapter in [2, 0, 5]:
		var entry: Dictionary = {}
		for service in services:
			if int(service.get("chapter", -1)) == chapter: entry = service; break
		if entry.is_empty(): continue
		var info: Dictionary = entry.get("snapshot", {})
		var index := int(entry.index)
		var title := "受注サイト" if chapter == 2 else "共有資料" if chapter == 0 else "外部共有"
		var button: Button = d._button("", func(): target_selected.emit(index, ""))
		button.name = "BranchNode_%d" % index
		button.tooltip_text = str(entry.get("name", title)) + "\n" + str(info.get("host", "")) + "\n" + str(info.get("config_path", ""))
		button.add_theme_stylebox_override("normal", UI.style(Color("eaf2fc") if index == selected_index else Color("f5f8fc"), BLUE if index == selected_index else Color("c5d2e1"), 10, 8, 3))
		button.add_theme_stylebox_override("hover", UI.style(Color("eaf2fc"), BLUE, 10, 8, 3))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, BLUE, 0, 0, 3))
		add_child(button); nodes.append(button)
		var column := VBoxContainer.new(); column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(column); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 10 * scale_factor; column.offset_right = -10 * scale_factor
		column.offset_top = 10 * scale_factor; column.offset_bottom = -8 * scale_factor
		column.add_theme_constant_override("separation", int(2 * scale_factor))
		var glyph: Control = GLYPH.add_to(column, "device" if chapter == 2 else "file" if chapter == 0 else "network", 28 * scale_factor, BLUE)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var known := bool(info.get("initialized", false))
		var process := "？ プロセス未確認" if not known else "▶ 稼働" if bool(info.get("active", false)) else "■ 停止"
		for text in [title, str(info.get("host", "")).get_slice(".", 0), process, "？ 構成未確認" if not known else "! 未適用あり" if bool(info.get("dirty", false)) else "構成 適用済み", coverage(info)]:
			_caption(d, column, text)
		if chapter == 0:
			var files: Dictionary = info.get("guest_state", {}).get("fs", {})
			for file in ["customers.csv", "partner-order.csv"]:
				var label := _caption(d, column, ("？ " if not known else "▤ " if files.has("/srv/share/" + file) else "× ") + file)
				label.tooltip_text = "/srv/share/" + file + "\nファイルの保存状態。利用可能かは受入計測で確認します。"
				label.mouse_filter = Control.MOUSE_FILTER_PASS
	for specification in [[2, "branch-business-orders", "注文API"], [5, "branch-probe-shared", "資料取得"]]:
		var entry: Dictionary = {}
		for service in services:
			if int(service.get("chapter", -1)) == int(specification[0]): entry = service; break
		if entry.is_empty(): continue
		var index := int(entry.index); var id := str(specification[1])
		var probe := probe_in(entry.get("snapshot", {}), id); edge_probes.append(probe)
		var edge: Button = d._button(str(specification[2]) + " · " + SAMPLE.status(probe), func(): target_selected.emit(index, id))
		edge.name = "BranchLink_" + id; edge.clip_text = true
		edge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		edge.add_theme_font_size_override("font_size", int(14 * scale_factor))
		edge.add_theme_color_override("font_color", SAMPLE.tint(probe))
		edge.tooltip_text = str(specification[2]) + "\n" + SAMPLE.status(probe) + "\n" + str(probe.get("result", ""))
		add_child(edge); edges.append(edge)
	resized.connect(_layout); _layout()

func _caption(d, parent: Node, text: String) -> Label:
	var label: Label = d._label(text, 14, UI.INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(label)
	return label

func _layout() -> void:
	if nodes.size() != 3 or size.x <= 0: return
	var gap := 14 * scale_factor
	var width := (size.x - gap * 2) / 3
	for index in 3:
		nodes[index].position = Vector2((width + gap) * index, 64 * scale_factor)
		nodes[index].size = Vector2(width, 222 * scale_factor)
	for index in edges.size():
		edges[index].position = Vector2((size.x / 2 + 8 * scale_factor) * index, 0)
		edges[index].size = Vector2(size.x / 2 - 8 * scale_factor, 32 * scale_factor)
	queue_redraw()

func _draw() -> void:
	if nodes.size() != 3: return
	var source := nodes[1].position + Vector2(nodes[1].size.x / 2, 0)
	for index in edges.size():
		var destination := nodes[0 if index == 0 else 2].position + Vector2(nodes[0 if index == 0 else 2].size.x / 2, 0)
		var bend_y := 46 * scale_factor
		var points := PackedVector2Array([source, Vector2(source.x, bend_y), Vector2(destination.x, bend_y), destination])
		var probe: Dictionary = edge_probes[index]; var color := SAMPLE.tint(probe)
		for segment in 3:
			if bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("freshness_known", true)):
				draw_line(points[segment], points[segment + 1], color, 2 * scale_factor, true)
			else: draw_dashed_line(points[segment], points[segment + 1], color, 1.5 * scale_factor, 4 * scale_factor)
		draw_polyline(PackedVector2Array([destination + Vector2(-5, -7) * scale_factor, destination, destination + Vector2(5, -7) * scale_factor]), color, 2 * scale_factor, true)
