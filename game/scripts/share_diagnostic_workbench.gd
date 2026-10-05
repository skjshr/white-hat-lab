extends Control
## A saved access trace and a local specimen comparator; never live telemetry.
signal object_selected(id: String)
const UI = preload("res://scripts/ui_theme.gd")
const Observation = preload("res://scripts/share_diagnostic_observation.gd")
const BG := Color("f2eef9")
const INK := Color("40364e")
const LINE := Color("bdb2ce")
const ACCENT := Color("7556ad")
const GREEN := Color("287756")
const RED := Color("ac4351")
const AMBER := Color("896321")
var observation: Dictionary = {}
var objects: Dictionary = {}
var scale_factor := 1.0
var selected := ""
var font: Font
var replay_position := -1.0
var elapsed := 0.0

func setup(d, value: Dictionary, selected_object: String) -> void:
	name = "ShareDiagnosticWorkbench"
	observation = value.duplicate(true); selected = selected_object
	scale_factor = float(d.game.settings.get("text_scale", 1.0)); font = UI.font(500)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; custom_minimum_size.y = 290 * scale_factor
	for id in ["request", "gate", "specimen", "seal"]:
		var button := Button.new(); button.name = "DiagnosticObject_" + id; button.flat = true
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = str({"request":"要求と受入条件", "gate":"停止した段階と応答", "specimen":"取得した一覧・ファイル", "seal":"原本照合" if str(value.protocol) == "hash" else "保存された受入判定"}[id])
		for state in ["normal", "pressed", "disabled"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", UI.style(Color(0.46, 0.34, 0.68, 0.06), Color.TRANSPARENT, 0, 0, 4))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, ACCENT, 0, 0, 4))
		button.pressed.connect(func(): object_selected.emit(id)); add_child(button); objects[id] = button
	resized.connect(_layout); _layout(); set_process(false)
	# The local comparator's visual order differs from child insertion order.
	# Explicit routes also bring off-screen objects back through scroll focus.
	var order: Array = ["request", "seal", "specimen", "gate"] if str(value.protocol) == "hash" else ["request", "gate", "specimen", "seal"]
	for index in range(order.size() - 1):
		objects[order[index]].focus_next = objects[order[index]].get_path_to(objects[order[index + 1]])
		objects[order[index + 1]].focus_previous = objects[order[index + 1]].get_path_to(objects[order[index]])

func _layout() -> void:
	if objects.is_empty(): return
	var s := scale_factor
	if str(observation.protocol) == "hash":
		objects.request.position = Vector2(size.x * .04, 39 * s); objects.request.size = Vector2(size.x * .31, 182 * s)
		objects.specimen.position = Vector2(size.x * .65, 39 * s); objects.specimen.size = Vector2(size.x * .31, 182 * s)
		objects.seal.position = Vector2(size.x * .37, 80 * s); objects.seal.size = Vector2(size.x * .26, 126 * s)
		objects.gate.position = Vector2(size.x * .04, 235 * s); objects.gate.size = Vector2(size.x * .92, 40 * s)
	else:
		objects.request.position = Vector2(size.x * .04, 38 * s); objects.request.size = Vector2(size.x * .25, 114 * s)
		objects.gate.position = Vector2(size.x * .40, 38 * s); objects.gate.size = Vector2(size.x * .53, 114 * s)
		objects.specimen.position = Vector2(size.x * .04, 172 * s); objects.specimen.size = Vector2(size.x * .63, 105 * s)
		objects.seal.position = Vector2(size.x * .71, 177 * s); objects.seal.size = Vector2(size.x * .25, 98 * s)
	queue_redraw()

func replay() -> void:
	if not bool(observation.recorded) or str(observation.transport) == "unknown": return
	elapsed = 0; replay_position = 0; set_process(true); queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta; replay_position = minf(1, elapsed / 1.4); queue_redraw()
	if replay_position >= 1: replay_position = -1; set_process(false)

func _text(value: String, at: Vector2, width: float, points := 14, color := INK, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var fs := int(points * scale_factor)
	var clipped := value
	while clipped.length() > 1 and font.get_string_size(clipped, align, -1, fs).x > width: clipped = clipped.left(clipped.length() - 2) + "…"
	draw_string(font, at, clipped, align, width, fs, color)

func _mark(at: Vector2, symbol: String, color: Color, radius := 12.0) -> void:
	var s := scale_factor
	draw_circle(at, radius * s, BG); draw_arc(at, radius * s, 0, TAU, 32, color, 1.6 * s, true)
	_text(symbol, at + Vector2(-radius, 5) * s, radius * 2 * s, 15, color)

func _wire(a: Vector2, b: Vector2, solid: bool, color: Color) -> void:
	var s := scale_factor
	if solid: draw_line(a, b, color, 2 * s, true)
	else: draw_dashed_line(a, b, color, 1.5 * s, 5 * s)
	var dir := (b - a).normalized(); var side := Vector2(-dir.y, dir.x)
	draw_polyline(PackedVector2Array([b - dir * 8 * s + side * 4 * s, b, b - dir * 8 * s - side * 4 * s]), color, 1.5 * s, true)

func _paper(rect: Rect2, title: String, value: String, known: bool) -> void:
	var s := scale_factor
	draw_rect(Rect2(rect.position + Vector2(4, 4) * s, rect.size), LINE)
	draw_colored_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x - 14 * s, rect.position.y), Vector2(rect.end.x, rect.position.y + 14 * s), rect.end, Vector2(rect.position.x, rect.end.y)]), Color("fffdfa"))
	draw_line(Vector2(rect.end.x - 14 * s, rect.position.y), Vector2(rect.end.x - 14 * s, rect.position.y + 14 * s), LINE, s)
	_text(title, rect.position + Vector2(7, 23) * s, rect.size.x - 14 * s, 14)
	draw_line(rect.position + Vector2(8, 34) * s, Vector2(rect.end.x - 8 * s, rect.position.y + 34 * s), LINE, s)
	if not value.is_empty():
		for row in 8:
			for col in 8:
				var cell := value.substr(row * 8 + col, 1)
				var intensity := float(cell.hex_to_int()) / 15.0
				draw_rect(Rect2(Vector2(rect.get_center().x - 23 * s + col * 6 * s, rect.position.y + (45 + row * 6) * s), Vector2(4, 4) * s), LINE.lerp(ACCENT, intensity))
	else: _text("?" if not known else "×", Vector2(rect.position.x, rect.position.y + 86 * s), rect.size.x, 32, LINE if not known else RED)
	_text(value.left(8) if not value.is_empty() else "未取得" if not known else "取得不可", Vector2(rect.position.x, rect.end.y - 9 * s), rect.size.x, 12, ACCENT)

func _draw() -> void:
	if objects.is_empty(): return
	var s := scale_factor
	var recorded := bool(observation.recorded); var fresh := bool(observation.fresh)
	var outcome := str(observation.outcome)
	var success := outcome in ["listed", "written", "downloaded", "hash_read"]
	var color := AMBER if recorded and not fresh else LINE if outcome == "unknown" else GREEN if success else RED
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(0, 0, size.x, 29 * s), Color("e6deef"))
	_text("手元の原本照合" if str(observation.protocol) == "hash" else "共有へのアクセス", Vector2(12 * s, 20 * s), size.x * .56, 12, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	_text("↻ 変更前" if recorded and not fresh else "保存した観測 · 再生中" if replay_position >= 0 else "保存した観測" if recorded else "観測待ち", Vector2(size.x * .58, 20 * s), size.x * .39, 12, AMBER if recorded and not fresh else ACCENT)
	var request: Rect2 = objects.request.get_rect(); var gate: Rect2 = objects.gate.get_rect()
	var specimen: Rect2 = objects.specimen.get_rect(); var seal: Rect2 = objects.seal.get_rect()
	if str(observation.protocol) == "hash":
		_paper(request.grow(-8 * s), "保全した原本", str(observation.expected_hash), not str(observation.expected_hash).is_empty())
		_paper(specimen.grow(-8 * s), str(observation.path).get_file(), str(observation.hash), recorded and outcome == "file_missing")
		var center := seal.get_center(); var match := str(observation.hash_match)
		var compare_color := AMBER if recorded and not fresh else GREEN if match == "match" else RED if match == "different" else LINE
		_wire(Vector2(request.end.x, center.y), Vector2(center.x - 26 * s, center.y), match != "unknown" and fresh, compare_color)
		_wire(Vector2(specimen.position.x, center.y), Vector2(center.x + 26 * s, center.y), match != "unknown" and fresh, compare_color)
		_mark(center, "=" if match == "match" else "≠" if match == "different" else "?", compare_color, 24)
		_text(("以前は " if recorded and not fresh else "") + ("一致" if match == "match" else "不一致" if match == "different" else "照合待ち"), Vector2(seal.position.x, seal.end.y - 7 * s), seal.size.x, 15, compare_color)
		_text("⌂  " + str(observation.path), gate.position + Vector2(0, 18) * s, gate.size.x, 13, INK)
		_text("手元のファイル · 共有接続は未検査", gate.position + Vector2(0, 36) * s, gate.size.x, 12, ACCENT)
		if replay_position >= 0: draw_circle(Vector2(specimen.position.x, center.y).lerp(center, replay_position), 4 * s, compare_color)
	else:
		var person := Vector2(request.get_center().x, request.position.y + 24 * s)
		draw_circle(person, 13 * s, ACCENT)
		draw_arc(person + Vector2(0, 36) * s, 23 * s, PI, TAU, 32, ACCENT, 14 * s, true)
		_text(str(observation.user), Vector2(request.position.x, request.position.y + 87 * s), request.size.x, 15)
		_text(str(observation.method), Vector2(request.position.x, request.position.y + 108 * s), request.size.x, 12, ACCENT)
		var folder := Rect2(gate.position.x + 10 * s, gate.position.y + 22 * s, gate.size.x - 20 * s, 55 * s)
		draw_rect(Rect2(folder.position - Vector2(0, 10) * s, Vector2(folder.size.x * .38, 15 * s)), Color("baa6d7"))
		draw_rect(folder, Color("d4c5e8"))
		_text("//" + str(observation.host), folder.position + Vector2(4, 21) * s, folder.size.x - 8 * s, 13, ACCENT)
		_text(str(observation.path), folder.position + Vector2(4, 44) * s, folder.size.x - 8 * s, 17)
		var a := Vector2(request.end.x, request.position.y + 47 * s); var b := Vector2(gate.position.x, a.y)
		var known := recorded and outcome != "unknown"
		var stop := str(observation.stop_at)
		_wire(a, b, known and fresh and not stop in ["identity", "request", "local_file"], color if not stop in ["identity", "request", "local_file"] else LINE)
		if not stop.is_empty():
			var mark := person + Vector2(20, 6) * s if stop == "identity" else folder.position + Vector2(folder.size.x - 13 * s, 13 * s) if stop == "share" else specimen.get_center() - Vector2(0, 6) * s if stop in ["specimen", "local_file"] else a.lerp(b, .5)
			_mark(mark, "×", RED)
		else: _mark(folder.position + Vector2(folder.size.x - 13 * s, 13 * s), "✓" if success else "?", color)
		_text(("以前の " if recorded and not fresh else "") + Observation.caption(observation), Vector2(gate.position.x, gate.position.y + 106 * s), gate.size.x, 14, color)
		var paper_top := specimen.position + Vector2(6, 3) * s
		draw_line(Vector2(paper_top.x, specimen.end.y - 5 * s), Vector2(specimen.end.x - 6 * s, specimen.end.y - 5 * s), LINE, 3 * s)
		var files: Array = observation.files if outcome == "listed" else [observation.remote_name] if outcome in ["written", "downloaded"] else []
		var count := mini(files.size(), 3)
		for index in count:
			var width := (specimen.size.x - 20 * s) / maxi(count, 1)
			var paper_width := minf(width - 7 * s, 40 * s)
			var doc := Rect2(paper_top.x + index * width + (width - paper_width) * .5, paper_top.y + 5 * s, paper_width, 54 * s)
			draw_rect(Rect2(doc.position + Vector2(3, 3) * s, doc.size), LINE)
			draw_colored_polygon(PackedVector2Array([doc.position, Vector2(doc.end.x - 11 * s, doc.position.y), Vector2(doc.end.x, doc.position.y + 11 * s), doc.end, Vector2(doc.position.x, doc.end.y)]), Color("fffdfa"))
			draw_polyline(PackedVector2Array([Vector2(doc.end.x - 11 * s, doc.position.y), Vector2(doc.end.x - 11 * s, doc.position.y + 11 * s), Vector2(doc.end.x, doc.position.y + 11 * s)]), LINE, s)
			for row in 3: draw_line(doc.position + Vector2(7, 12 + row * 7) * s, Vector2(doc.end.x - 7 * s, doc.position.y + (12 + row * 7) * s), LINE, s)
			_text(str(files[index]), Vector2(paper_top.x + index * width, paper_top.y + 73 * s), width, 12)
		if files.size() > count: _text("+%d" % (files.size() - count), Vector2(specimen.end.x - 31 * s, paper_top.y + 20 * s), 30 * s, 13, ACCENT)
		if files.is_empty(): _text("0件" if outcome == "listed" else "? 未取得", paper_top + Vector2(0, 47) * s, specimen.size.x - 12 * s, 22, LINE)
		_text("ファイル名のみ · 内容未検査" if outcome == "listed" else "保存応答 · 内容未照合" if outcome == "written" else "取得応答 · 内容未照合" if outcome == "downloaded" else "一覧・ファイル未取得", Vector2(specimen.position.x, specimen.end.y - 14 * s), specimen.size.x, 12, ACCENT)
		var start := Vector2(folder.position.x, folder.get_center().y)
		var end := Vector2(specimen.get_center().x, specimen.position.y + 3 * s)
		var elbow := Vector2(end.x, start.y)
		var trace_color := color if success else LINE
		var solid := success and fresh
		if str(observation.operation) == "put": var swap := start; start = end; end = swap
		if solid: draw_line(start, elbow, trace_color, 2 * s, true)
		else: draw_dashed_line(start, elbow, trace_color, 1.5 * s, 5 * s)
		_wire(elbow, end, solid, trace_color)
		var stamp := seal.get_center() - Vector2(0, 11) * s
		_mark(stamp, "↻" if recorded and not fresh else "✓" if recorded and bool(observation.passed) else "×" if recorded else "?", AMBER if recorded and not fresh else GREEN if recorded and bool(observation.passed) else RED if recorded else LINE, 23)
		_text("受入判定", Vector2(seal.position.x, seal.end.y - 14 * s), seal.size.x, 14)
		if replay_position >= 0:
			var point := a.lerp(b, minf(replay_position * 2, 1))
			if success and replay_position > .5:
				var progress := (replay_position - .5) * 2
				point = start.lerp(elbow, progress * 2) if progress < .5 else elbow.lerp(end, (progress - .5) * 2)
			elif not stop.is_empty(): point = person if stop == "identity" else b if stop == "share" else specimen.get_center() if stop in ["specimen", "local_file"] else a.lerp(b, .5)
			draw_circle(point, 5 * s, color)
	if selected in objects: draw_rect(objects[selected].get_rect().grow(-1), ACCENT, false, s)
