extends Control
## Equipment floor plan from saved snapshots. No connections or measurements.
signal target_selected(index: int, probe_id: String)
const UI = preload("res://scripts/ui_theme.gd")
const SAMPLE = preload("res://scripts/service_monitor_canvas.gd")
const BLUE := Color("315b91")
const INK := Color("24344a")
const LINE := Color("b6c5d5")
var scale_factor := 1.0
var data: Dictionary = {}
var selected := -1
var nodes: Array[Button] = []
var node_data: Array[Dictionary] = []
var edges: Array[Button] = []
var edge_probes: Array[Dictionary] = []
var files: Array[Button] = []
var file_data: Array[Dictionary] = []
var font: Font

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
	data = snapshot.duplicate(true); selected = selected_index
	scale_factor = float(d.game.settings.get("text_scale", 1.0)); font = UI.font(500)
	custom_minimum_size.y = 224 + 12 * (scale_factor - 1) + 31 * scale_factor
	for chapter in [2, 0, 5]:
		var entry: Dictionary = {}
		for service in data.get("services", []):
			if int(service.get("chapter", -1)) == chapter: entry = service; break
		if entry.is_empty(): continue
		var info: Dictionary = entry.get("snapshot", {})
		var index := int(entry.index)
		var title := "受注業務" if chapter == 2 else "共有元" if chapter == 0 else "外部共有"
		var button := _target(d, "BranchNode_%d" % index, index, "")
		button.tooltip_text = str(entry.get("name", title)) + "\n" + str(info.get("host", "")) + "\n" + coverage(info) + "\n" + ("未確認" if not bool(info.get("initialized", false)) else "構成に未適用の変更" if bool(info.get("dirty", false)) else "構成は適用済み")
		var captions: Array[Label] = []
		for text in [title, str(info.get("host", "")).get_slice(".", 0), "未確認" if not bool(info.get("initialized", false)) else "稼働" if bool(info.get("active", false)) else "停止"]:
			var label: Label = d._label(text, 14, INK)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.clip_text = true
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(label); captions.append(label)
		nodes.append(button); node_data.append({"entry":entry, "captions":captions})
		if chapter == 0:
			var stored: Dictionary = info.get("guest_state", {}).get("fs", {})
			for spec in [["customers.csv", "顧客台帳", "branch-source-customers", "customers"], ["partner-order.csv", "注文原本", "branch-source-orders", "orders"]]:
				var path := "/srv/share/" + str(spec[0])
				var file := _target(d, "BranchFile_" + str(spec[3]), index, str(spec[2]))
				file.tooltip_text = path + "\n" + ("未確認" if not bool(info.get("initialized", false)) else "保存あり" if stored.has(path) else "ファイルなし") + "\n原本照合 · " + SAMPLE.status(probe_in(info, str(spec[2]))) + "\n存在・原本照合とアクセス許可は別の状態です。"
				files.append(file); file_data.append({"path":path, "title":spec[1], "known":bool(info.get("initialized", false)), "present":stored.has(path), "probe":probe_in(info, str(spec[2]))})
	for spec in [[2, "branch-business-orders", "注文API"], [5, "branch-probe-shared", "資料取得"]]:
		var entry: Dictionary = {}
		for service in data.get("services", []):
			if int(service.get("chapter", -1)) == int(spec[0]): entry = service; break
		if entry.is_empty(): continue
		var probe := probe_in(entry.get("snapshot", {}), str(spec[1])); edge_probes.append(probe)
		var edge: Button = d._button(str(spec[2]) + " · " + SAMPLE.status(probe), func(): target_selected.emit(int(entry.index), str(spec[1])))
		edge.name = "BranchLink_" + str(spec[1]); edge.clip_text = true
		edge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		edge.add_theme_font_size_override("font_size", int(14 * scale_factor))
		edge.add_theme_color_override("font_color", SAMPLE.tint(probe))
		edge.add_theme_stylebox_override("normal", UI.style(Color("f5f8fc"), LINE, 4, 3, 2))
		edge.tooltip_text = str(spec[2]) + "\n" + SAMPLE.status(probe) + "\n" + str(probe.get("result", ""))
		add_child(edge); edges.append(edge)
	resized.connect(_layout); _layout()

func _target(d, id: String, index: int, probe: String) -> Button:
	var button: Button = d._button("", func(): target_selected.emit(index, probe))
	button.name = id; button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "pressed"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", UI.style(Color(0.19, 0.36, 0.57, 0.04), Color.TRANSPARENT, 0, 0, 2))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, BLUE, 0, 0, 2))
	add_child(button); return button

func _layout() -> void:
	if nodes.size() != 3 or size.x <= 0: return
	var width := size.x / 3
	for index in 3:
		nodes[index].position = Vector2(width * index + 5, 4); nodes[index].size = Vector2(width - 10, 207)
		if index == 1: nodes[index].size.y = 224
		var captions: Array = node_data[index].captions
		for row in 3:
			captions[row].position = Vector2(0, [0, 171, 145][row]); captions[row].size = Vector2(width - 10, 23 * scale_factor)
		if index == 1:
			captions[1].position.y = 191; captions[2].position.y = 79
	for index in files.size():
		var paper_width := minf(width * 0.42, 110 * scale_factor)
		files[index].position = Vector2(size.x / 2 + (-1 if index == 0 else 1) * (paper_width / 2 + 6) - paper_width / 2, 111)
		files[index].size = Vector2(paper_width, 76)
	for index in edges.size():
		edges[index].position = Vector2(5 if index == 0 else size.x * 0.59, 220 + 12 * (scale_factor - 1))
		edges[index].size = Vector2(size.x * 0.40, 31 * scale_factor)
	queue_redraw()

func _text(text: String, at: Vector2, width: float, points := 14, color := INK) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, int(points * scale_factor), color)

func _symbol(probe: Dictionary) -> String:
	return "○" if not bool(probe.get("recorded", false)) else "?" if not bool(probe.get("freshness_known", true)) else "↻" if not bool(probe.get("fresh", false)) else "✓" if bool(probe.get("passed", false)) else "×"

func operation_marker_rect(index: int) -> Rect2:
	return Rect2(nodes[index].get_rect().get_center().x + 63, 84 if index == 1 else 114, 10, 22)

func _draw() -> void:
	if nodes.size() != 3: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("f7f9fc"))
	for x in range(14, int(size.x), 22):
		for y in range(12, int(size.y), 22): draw_circle(Vector2(x, y), 0.7, Color("d5dee9"))
	# Source fork: no gateway-to-portal cable or fabricated live traffic.
	var source := Vector2(size.x / 2, 107)
	for index in edges.size():
		var endpoint := Vector2(nodes[0 if index == 0 else 2].get_rect().get_center().x, 137)
		var points := PackedVector2Array([source, Vector2(source.x, 215), Vector2(endpoint.x, 215), endpoint])
		var probe: Dictionary = edge_probes[index]; var color := SAMPLE.tint(probe)
		for segment in 3:
			if bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("freshness_known", true)): draw_line(points[segment], points[segment+1], color, 2, true)
			else: draw_dashed_line(points[segment], points[segment+1], color, 1.5, 5)
		draw_polyline(PackedVector2Array([endpoint + Vector2(-5, 7), endpoint, endpoint + Vector2(5, 7)]), color, 2, true)
	for index in 3:
		var entry: Dictionary = node_data[index].entry; var info: Dictionary = entry.snapshot
		var rect := nodes[index].get_rect(); var center := rect.get_center().x
		var known := bool(info.get("initialized", false)); var active := known and bool(info.get("active", false))
		var device_color := Color("d7e4f1") if known else Color("e8edf3")
		var screen := Color("eaf6fb") if active else Color("e3e7ec")
		if index == 0:
			var monitor := Rect2(center - 48, 39, 96, 68)
			draw_rect(monitor.grow(4), BLUE if known else LINE); draw_rect(monitor, screen)
			for row in 3: draw_line(monitor.position + Vector2(10, 17 + row * 15), monitor.position + Vector2(84, 17 + row * 15), LINE, 2)
			draw_line(monitor.position + Vector2(38, 10), monitor.position + Vector2(38, 58), LINE, 1)
			draw_rect(Rect2(center - 4, 110, 8, 10), BLUE); draw_line(Vector2(center-30,123),Vector2(center+30,123), BLUE, 4)
		elif index == 1:
			var nas := Rect2(center-55, 35, 110, 72)
			draw_rect(nas.grow(3), BLUE if known else LINE); draw_rect(nas, device_color)
			for bay in 2:
				var slot := Rect2(center-44, 46+bay*22, 88, 17)
				draw_rect(slot, Color("f7f9fc")); draw_line(slot.position+Vector2(10,9),slot.position+Vector2(54,9),LINE,2)
		else:
			var browser := Rect2(center-57, 37, 114, 83)
			draw_rect(browser.grow(3), BLUE if known else LINE); draw_rect(browser, screen)
			draw_rect(Rect2(browser.position,Vector2(browser.size.x,16)),device_color)
			for dot in 3: draw_circle(browser.position+Vector2(8+dot*8,8),2,LINE)
			draw_rect(Rect2(browser.position+Vector2(8,25),Vector2(24,47)),device_color)
			for doc in 2:
				var sheet := Rect2(browser.position+Vector2(42+doc*29,26),Vector2(22,36))
				draw_rect(sheet,Color.WHITE); draw_rect(sheet,LINE,false,1)
				for row in 3: draw_line(sheet.position+Vector2(5,10+row*7),sheet.position+Vector2(17,10+row*7),LINE,1)
		var indicator := Vector2(center + 53, 39)
		draw_circle(indicator, 10, Color.WHITE)
		_text("▶" if active else "■" if known else "?", indicator+Vector2(-10,6),20,14,UI.GREEN if active else UI.RED if known else UI.MUTED)
		if known: _text("!" if bool(info.get("dirty", false)) else "✓", Vector2(center-65,56),20,14,Color("936819") if bool(info.get("dirty", false)) else BLUE)
		if int(entry.index) == int(data.get("current_target", -1)):
			var plug := operation_marker_rect(index).position + Vector2(0, 5)
			draw_rect(Rect2(plug,Vector2(10,8)),BLUE)
			for pin in 2: draw_line(plug+Vector2(3+pin*4,0),plug+Vector2(3+pin*4,-5),BLUE,2)
			draw_line(plug+Vector2(5,8),plug+Vector2(5,17),BLUE,2)
		if int(entry.index) == selected: draw_rect(rect.grow(-1), BLUE, false, 1.5)
		var probes: Array = info.get("probes", [])
		if index != 1:
			var step := minf(19, (rect.size.x-8)/maxf(1,probes.size()))
			for item in probes.size(): _text(_symbol(probes[item]),Vector2(center-step*probes.size()/2+item*step,207),step,12,SAMPLE.tint(probes[item]))
	for index in files.size():
		var rect := files[index].get_rect().grow(-3); var item: Dictionary = file_data[index]
		var paper_color := Color("fffdf3") if bool(item.known) and bool(item.present) else Color("edf0f4")
		draw_rect(Rect2(rect.position+Vector2(3,3),rect.size),LINE)
		draw_colored_polygon(PackedVector2Array([rect.position,Vector2(rect.end.x-11,rect.position.y),Vector2(rect.end.x,rect.position.y+11),rect.end,Vector2(rect.position.x,rect.end.y)]),paper_color)
		draw_line(Vector2(rect.end.x-11,rect.position.y),Vector2(rect.end.x-11,rect.position.y+11),LINE,1)
		_text(str(item.title),rect.position+Vector2(0,26),rect.size.x,14)
		_text("▤" if bool(item.known) and bool(item.present) else "×" if bool(item.known) else "?",rect.position+Vector2(0,50),rect.size.x,18,BLUE if bool(item.present) else UI.RED if bool(item.known) else UI.MUTED)
		_text("照合 " + _symbol(item.probe),Vector2(rect.position.x,rect.end.y-4),rect.size.x,12,SAMPLE.tint(item.probe))
