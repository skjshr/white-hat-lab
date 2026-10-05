extends Control
## Measurement relationships and recorded sample order, not packet traffic or
## an invented polling clock. Buttons provide the same labels as the diagram.
signal probe_selected(id: String)
const UI = preload("res://scripts/ui_theme.gd")
const GLYPH = preload("res://scripts/service_glyph.gd")
const INK := Color("24344a")
const BLUE := Color("315b91")
const LINE := Color("bcc9d8")
const PASS := Color("247857")
const FAIL := Color("b53543")
const STALE := Color("936819")
var scale_factor := 1.0
var data: Dictionary = {}
var selected := ""
var mode := "map"
var host: PanelContainer
var endpoints: Array[Button] = []
var samples: Array = []
var sample_labels: Array[Label] = []

static func status(probe: Dictionary) -> String:
	if not bool(probe.get("recorded", false)): return "○ 未測定"
	if not bool(probe.get("freshness_known", true)): return "？ 現在性不明"
	if not bool(probe.get("fresh", false)): return "↻ 古い測定"
	return "✓ 合格" if bool(probe.get("passed", false)) else "× 不合格"

static func tint(probe: Dictionary) -> Color:
	if not bool(probe.get("recorded", false)): return BLUE
	if not bool(probe.get("freshness_known", true)): return BLUE
	if not bool(probe.get("fresh", false)): return STALE
	return PASS if bool(probe.get("passed", false)) else FAIL

func setup_map(d, snapshot: Dictionary, selected_id: String) -> void:
	name = "ServiceMeasurementMap"; data = snapshot.duplicate(true); selected = selected_id
	scale_factor = float(d.game.settings.get("text_scale", 1.0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host = PanelContainer.new(); host.name = "MonitorHost"
	host.add_theme_stylebox_override("panel", UI.style(Color("edf3fa"), BLUE, 8, 8, 3)); add_child(host)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 5); host.add_child(column)
	GLYPH.add_to(column, "process", 40 * scale_factor, BLUE)
	for text in [str(data.get("host", "client")).get_slice(".", 0), str(data.get("service", "")) + ".service", "▶ プロセス稼働" if bool(data.get("active", false)) else "■ プロセス停止", "! 未適用あり" if bool(data.get("dirty", false)) else "構成 適用済み"]:
		var label: Label = d._label(text, 13, INK); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.clip_text = true; column.add_child(label)
	host.tooltip_text = str(data.get("host", "")) + "\n" + str(data.get("config_path", ""))
	for raw in data.get("probes", []):
		var probe: Dictionary = raw
		var id := str(probe.get("id", ""))
		var button: Button = d._button("%s · %s" % [status(probe), str(probe.get("label", id))], func(): probe_selected.emit(id))
		button.name = "MonitorProbe_" + id.validate_node_name(); button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true; button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", int(14 * scale_factor))
		button.add_theme_color_override("font_color", tint(probe)); button.add_theme_color_override("font_hover_color", tint(probe)); button.add_theme_color_override("font_pressed_color", tint(probe))
		button.add_theme_stylebox_override("normal", UI.style(Color("e9f0fa") if id == selected else Color.WHITE, tint(probe) if id == selected else LINE, 7, 5, 3))
		button.add_theme_stylebox_override("hover", UI.style(Color("e9f0fa"), BLUE, 7, 5, 3))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, BLUE, 1, 1, 3))
		button.tooltip_text = str(probe.get("label", id)) + "\n" + status(probe) + "\n" + str(probe.get("result", ""))
		add_child(button); endpoints.append(button)
	custom_minimum_size.y = maxf(190, 20 + endpoints.size() * 40) * scale_factor
	resized.connect(_layout); _layout()

func setup_history(d, records: Array) -> void:
	name = "ServiceMeasurementHistory"; mode = "history"; samples = records.duplicate(true)
	scale_factor = float(d.game.settings.get("text_scale", 1.0)); size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 118 * scale_factor
	for index in samples.size():
		var item: Dictionary = samples[index]
		var text := "✓" if item.get("probe_passed", null) is bool and bool(item.probe_passed) else "×" if item.get("probe_passed", null) is bool else "?"
		var label: Label = d._label("%s #%d" % [text, int(item.get("sample_index", index + 1))], 12, INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.tooltip_text = ("実測時に合格" if bool(item.get("probe_passed", false)) else "実測時に不合格") if item.get("probe_passed", null) is bool else "旧記録：当時の判定は未記録"
		label.tooltip_text += "\n" + str(item.get("output", "")); label.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(label); sample_labels.append(label)
	resized.connect(_layout); _layout()

func _layout() -> void:
	if size.x <= 0: return
	if mode == "history":
		for index in sample_labels.size():
			var width := (size.x - 24 * scale_factor) / maxf(1, samples.size())
			sample_labels[index].position = Vector2(12 * scale_factor + width * index, 91 * scale_factor)
			sample_labels[index].size = Vector2(width, 23 * scale_factor)
	else:
		if host == null: return
		var host_width := minf(172 * scale_factor, size.x * 0.32)
		host.position = Vector2(4 * scale_factor, maxf(8 * scale_factor, (size.y - 150 * scale_factor) / 2))
		host.size = Vector2(host_width, 150 * scale_factor)
		var endpoint_x := host_width + 48 * scale_factor
		for index in endpoints.size():
			endpoints[index].position = Vector2(endpoint_x, (8 + index * 40) * scale_factor)
			endpoints[index].size = Vector2(maxf(40, size.x - endpoint_x - 4 * scale_factor), 34 * scale_factor)
	queue_redraw()

func _draw() -> void:
	if mode == "history":
		var baseline := 53 * scale_factor
		for y in [23, 53, 83]: draw_line(Vector2(10 * scale_factor, y * scale_factor), Vector2(size.x - 10 * scale_factor, y * scale_factor), LINE, 1)
		if samples.is_empty(): return
		var previous := Vector2.ZERO
		for index in samples.size():
			var item: Dictionary = samples[index]
			var known: bool = item.get("probe_passed", null) is bool
			var good: bool = known and bool(item.probe_passed)
			var point := Vector2(12 * scale_factor + (size.x - 24 * scale_factor) * (index + 0.5) / samples.size(), (23 if good else 83 if known else 53) * scale_factor)
			if index > 0: draw_line(previous, point, BLUE, 2 * scale_factor, true)
			draw_line(Vector2(point.x, baseline), point, LINE, 1)
			if good: draw_circle(point, 5 * scale_factor, PASS)
			elif known:
				draw_line(point - Vector2.ONE * 5 * scale_factor, point + Vector2.ONE * 5 * scale_factor, FAIL, 2 * scale_factor, true)
				draw_line(point + Vector2(-5, 5) * scale_factor, point + Vector2(5, -5) * scale_factor, FAIL, 2 * scale_factor, true)
			else: draw_arc(point, 5 * scale_factor, 0, TAU, 24, BLUE, 2 * scale_factor, true)
			previous = point
		return
	if host == null: return
	var source := host.position + Vector2(host.size.x, host.size.y / 2)
	var bus_x := source.x + 23 * scale_factor
	for index in endpoints.size():
		var end := endpoints[index].position + Vector2(0, endpoints[index].size.y / 2)
		var probe: Dictionary = data.probes[index]
		var color := tint(probe)
		var points := PackedVector2Array([source, Vector2(bus_x, source.y), Vector2(bus_x, end.y), end])
		if not bool(probe.get("recorded", false)) or not bool(probe.get("fresh", false)):
			for segment in 3: draw_dashed_line(points[segment], points[segment + 1], color, 1.2 * scale_factor, 4 * scale_factor)
		else: draw_polyline(points, color, 1.7 * scale_factor, true)
		draw_circle(end - Vector2(5 * scale_factor, 0), 3 * scale_factor, color)
