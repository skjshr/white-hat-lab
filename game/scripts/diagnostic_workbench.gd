extends Control
## A specimen bench, not live telemetry. Animation replays one saved observation.
signal object_selected(id: String)
const UI = preload("res://scripts/ui_theme.gd")
const BG := Color("202630")
const EDGE := Color("546070")
const INK := Color("e9edf2")
const MUTED := Color("b2bdca")
const CYAN := Color("79ced3")
const AMBER := Color("efbf79")
const RED := Color("ef9492")
const GREEN := Color("9dcdb0")
var observation: Dictionary = {}
var scale_factor := 1.0
var selected := ""
var objects: Dictionary = {}
var replay_position := -1.0
var replay_elapsed := 0.0
var font: Font

func setup(d, value: Dictionary, selected_object: String) -> void:
	name = "DiagnosticWorkbench"
	observation = value.duplicate(true)
	scale_factor = float(d.game.settings.get("text_scale", 1.0))
	font = UI.font(500)
	selected = selected_object
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 300 * scale_factor
	for id in ["request", "gate", "server", "specimen", "seal"]:
		var button := Button.new()
		button.name = "DiagnosticObject_" + id
		button.flat = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = str({"request":"送信した要求", "gate":"通信の通過・遮断", "server":"サーバーの応答", "specimen":"取得した資料", "seal":"保全した原本との照合"}[id])
		for state in ["normal", "pressed", "disabled"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", UI.style(Color(1, 1, 1, 0.045), Color.TRANSPARENT, 0, 0, 4))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, CYAN, 0, 0, 4))
		button.pressed.connect(func(): object_selected.emit(id))
		button.mouse_entered.connect(queue_redraw)
		button.mouse_exited.connect(queue_redraw)
		add_child(button); objects[id] = button
	resized.connect(_layout)
	_layout()
	set_process(false)

func _layout() -> void:
	if objects.is_empty(): return
	var s := scale_factor
	var upper := 36 * s
	var lower := 165 * s
	objects.request.position = Vector2(size.x * 0.04, upper)
	objects.request.size = Vector2(size.x * 0.24, 115 * s)
	objects.gate.position = Vector2(size.x * 0.34, upper)
	objects.gate.size = Vector2(size.x * 0.22, 115 * s)
	objects.server.position = Vector2(size.x * 0.67, upper)
	objects.server.size = Vector2(size.x * 0.28, 115 * s)
	objects.specimen.position = Vector2(size.x * 0.05, lower)
	objects.specimen.size = Vector2(size.x * 0.53, 122 * s)
	objects.seal.position = Vector2(size.x * 0.64, lower)
	objects.seal.size = Vector2(size.x * 0.31, 122 * s)
	queue_redraw()

func replay() -> void:
	if not bool(observation.get("recorded", false)) or str(observation.get("transport", "unknown")) == "unknown": return
	replay_elapsed = 0
	replay_position = 0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	replay_elapsed += delta
	replay_position = minf(1.0, replay_elapsed / 1.4)
	queue_redraw()
	if replay_position >= 1.0:
		replay_position = -1
		set_process(false)

func _text(value: String, at: Vector2, width: float, points := 14, color := INK, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var fs := int(points * scale_factor)
	var clipped := value
	while clipped.length() > 1 and font.get_string_size(clipped, align, -1, fs).x > width:
		clipped = clipped.left(clipped.length() - 2) + "…"
	draw_string(font, at, clipped, align, width, fs, color)

func _mark(at: Vector2, kind: String, color: Color) -> void:
	var s := scale_factor
	draw_circle(at, 11 * s, BG)
	draw_arc(at, 11 * s, 0, TAU, 32, color, 1.5 * s, true)
	if kind == "yes":
		draw_polyline(PackedVector2Array([at + Vector2(-5, 0) * s, at + Vector2(-1, 4) * s, at + Vector2(6, -4) * s]), color, 2 * s, true)
	elif kind == "no":
		for direction in [-1, 1]: draw_line(at + Vector2(-4, -4 * direction) * s, at + Vector2(4, 4 * direction) * s, color, 2 * s, true)
	else: _text("?", at + Vector2(-9, 5) * s, 18 * s, 14, color)

func _wire(a: Vector2, b: Vector2, known: bool, color: Color) -> void:
	if known: draw_line(a, b, color, 2 * scale_factor, true)
	else: draw_dashed_line(a, b, color, 1.4 * scale_factor, 5 * scale_factor)
	var direction := (b - a).normalized()
	var side := Vector2(-direction.y, direction.x)
	draw_polyline(PackedVector2Array([b - direction * 7 * scale_factor + side * 4 * scale_factor, b, b - direction * 7 * scale_factor - side * 4 * scale_factor]), color, 1.4 * scale_factor, true)

func _fingerprint(at: Vector2, value: String) -> void:
	var s := scale_factor
	for row in 4:
		for col in 8:
			var index := row * 8 + col
			var intensity := 0.0 if value.length() != 64 else float(value.substr(index, 1).hex_to_int()) / 15.0
			draw_rect(Rect2(at + Vector2(col * 5, row * 5) * s, Vector2(3, 3) * s), EDGE.lerp(CYAN, intensity))

func _draw() -> void:
	if objects.is_empty(): return
	var s := scale_factor
	var recorded := bool(observation.get("recorded", false))
	var fresh := bool(observation.get("fresh", false))
	var transport := str(observation.get("transport", "unknown"))
	var replied := transport == "replied" or transport == "local"
	var blocked := transport == "firewall"
	var stopped := blocked or transport == "dns" or transport == "unreachable"
	var status := int(observation.get("status", 0))
	var state_color := AMBER if recorded and not fresh else GREEN if bool(observation.get("passed", false)) else RED if recorded else MUTED
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for x in range(16, int(size.x), 24):
		for y in range(18, int(size.y), 24): draw_circle(Vector2(x, y), 0.7, Color("34404d"))
	draw_rect(Rect2(0, 0, size.x, 29 * s), Color("29313d"))
	_text("保存した観測" if recorded else "観測待ち", Vector2(12 * s, 20 * s), size.x * 0.45, 12, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_text("↻ 変更前" if recorded and not fresh else "再生中" if replay_position >= 0 else "", Vector2(size.x * 0.6, 20 * s), size.x * 0.37, 12, AMBER)
	var request: Rect2 = objects.request.get_rect()
	var gate: Rect2 = objects.gate.get_rect()
	var server: Rect2 = objects.server.get_rect()
	var paper: Rect2 = objects.specimen.get_rect()
	var seal: Rect2 = objects.seal.get_rect()
	var cy := request.position.y + 49 * s
	var route_start := Vector2(request.get_center().x + 42 * s, cy)
	var route_gate := Vector2(gate.get_center().x, cy)
	var route_end := Vector2(server.get_center().x - 42 * s, cy)
	_wire(route_start, route_gate - Vector2(18, 0) * s, recorded and fresh and transport != "unknown", AMBER if stopped else CYAN if recorded else EDGE)
	_wire(route_gate + Vector2(18, 0) * s, route_end, replied and fresh, CYAN if replied else EDGE)
	var response_start := Vector2(server.get_center().x, server.position.y + 84 * s)
	var response_end := Vector2(paper.end.x - 20 * s, paper.position.y + 20 * s)
	_wire(response_start, response_end, replied and fresh, CYAN if replied else EDGE)
	# Workstation: monitor, stand and keyboard rather than a labelled card.
	var monitor := Rect2(request.get_center().x - 37 * s, request.position.y + 15 * s, 74 * s, 48 * s)
	draw_rect(monitor.grow(4 * s), Color("43505f"))
	draw_rect(monitor, Color("111922"))
	draw_line(monitor.position + Vector2(9, 13) * s, monitor.position + Vector2(18, 19) * s, CYAN, 2 * s)
	draw_line(monitor.position + Vector2(18, 19) * s, monitor.position + Vector2(9, 25) * s, CYAN, 2 * s)
	draw_line(monitor.position + Vector2(25, 27) * s, monitor.position + Vector2(41, 27) * s, CYAN, 2 * s)
	draw_rect(Rect2(monitor.get_center().x - 3 * s, monitor.end.y, 6 * s, 12 * s), EDGE)
	draw_line(Vector2(monitor.position.x - 5 * s, monitor.end.y + 14 * s), Vector2(monitor.end.x + 5 * s, monitor.end.y + 14 * s), EDGE, 4 * s)
	_text(str(observation.get("protocol", "command")).to_upper(), Vector2(request.position.x, request.position.y + 101 * s), request.size.x, 14, INK)
	# Barrier rotation describes this measured request, never the saved policy.
	if transport in ["dns", "unreachable"]:
		var center := Vector2(gate.get_center().x, cy)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -25) * s, center + Vector2(-29, 24) * s, center + Vector2(29, 24) * s]), AMBER)
		_text("DNS" if transport == "dns" else "!", center + Vector2(-24, 14) * s, 48 * s, 14, BG)
	else:
		var post := Vector2(gate.get_center().x - 20 * s, cy + 22 * s)
		draw_rect(Rect2(post - Vector2(5, 27) * s, Vector2(10, 34) * s), EDGE)
		var hinge := post - Vector2(0, 27) * s
		var arm_end := hinge + Vector2(49, 0 if blocked else -31 if replied else -10) * s
		draw_line(hinge, arm_end, AMBER if blocked else CYAN if replied else EDGE, 7 * s, true)
		for n in 4:
			var p := hinge.lerp(arm_end, 0.15 + n * 0.2)
			draw_line(p - Vector2(0, 3) * s, p + Vector2(4, 3) * s, BG, 2 * s)
		_mark(Vector2(gate.get_center().x + 34 * s, cy + 18 * s), "no" if blocked else "yes" if replied else "unknown", AMBER if blocked else CYAN if replied else MUTED)
	_text("遮断" if blocked else "名前解決×" if transport == "dns" else "接続不可" if transport == "unreachable" else "到達" if replied else "未観測", Vector2(gate.position.x, gate.position.y + 101 * s), gate.size.x, 14, AMBER if stopped else MUTED)
	# Rack: the reply code stays separate from the acceptance verdict.
	var rack := Rect2(server.get_center().x - 38 * s, server.position.y + 9 * s, 76 * s, 70 * s)
	draw_rect(rack.grow(3 * s), Color("43505f"))
	for n in 3:
		var slot := Rect2(rack.position + Vector2(4, 4 + n * 22) * s, Vector2(68, 17) * s)
		draw_rect(slot, Color("303947"))
		draw_circle(slot.position + Vector2(8, 8) * s, 2.5 * s, CYAN if replied else EDGE)
		for bar in 4: draw_line(slot.position + Vector2(40 + bar * 5, 5) * s, slot.position + Vector2(40 + bar * 5, 12) * s, EDGE, s)
	_text(str(observation.get("host", "対象")).get_slice(".", 0), Vector2(server.position.x, server.position.y + 101 * s), server.size.x, 14, INK)
	_mark(rack.position + Vector2(75, 66) * s, "yes" if status >= 200 and status < 300 else "no" if replied else "unknown", GREEN if status >= 200 and status < 300 else RED if replied else MUTED)
	if status > 0:
		draw_rect(Rect2(rack.position + Vector2(5, 24) * s, Vector2(66, 22) * s), Color("111922"))
		_text(str(status), rack.position + Vector2(5, 42) * s, 66 * s, 16, GREEN if status < 300 else RED)
	# The response is a physical paper specimen; numbers come only from its body.
	var doc := Rect2(paper.position + Vector2(6, 7) * s, paper.size - Vector2(16, 13) * s)
	draw_rect(Rect2(doc.position + Vector2(5, 4) * s, doc.size), Color("65717c"))
	draw_colored_polygon(PackedVector2Array([doc.position, Vector2(doc.end.x - 17 * s, doc.position.y), Vector2(doc.end.x, doc.position.y + 17 * s), doc.end, Vector2(doc.position.x, doc.end.y)]), Color("e9e8dc"))
	draw_line(Vector2(doc.end.x - 17 * s, doc.position.y), Vector2(doc.end.x - 17 * s, doc.position.y + 17 * s), Color("acb3b2"), s)
	draw_line(Vector2(doc.end.x - 17 * s, doc.position.y + 17 * s), Vector2(doc.end.x, doc.position.y + 17 * s), Color("acb3b2"), s)
	var rows: Array = observation.get("rows", [])
	var specimen := str(observation.get("specimen", "response"))
	var title := "注文票" if specimen == "orders" else "顧客名簿" if specimen == "customers" else "取得した資料"
	_text(title, doc.position + Vector2(12, 23) * s, doc.size.x - 34 * s, 14, Color("344553"), HORIZONTAL_ALIGNMENT_LEFT)
	draw_line(doc.position + Vector2(12, 32) * s, Vector2(doc.end.x - 12 * s, doc.position.y + 32 * s), Color("acb3b2"), s)
	if not rows.is_empty() and rows[0] is Dictionary:
		var row: Dictionary = rows[0]
		var primary := "#" + str(row.get("order", "")) if specimen == "orders" else str(row.get("name", ""))
		var value := str(int(row.get("total", 0))) if specimen == "orders" else "#" + str(row.get("id", ""))
		_text(primary, doc.position + Vector2(12, 63) * s, doc.size.x * 0.48, 18, Color("344553"), HORIZONTAL_ALIGNMENT_LEFT)
		_text(value, Vector2(doc.get_center().x, doc.position.y + 63 * s), doc.size.x * 0.44, 22, Color("344553"), HORIZONTAL_ALIGNMENT_RIGHT)
		_text("%d件取得" % rows.size(), doc.position + Vector2(12, 90) * s, doc.size.x - 24 * s, 14, Color("536476"), HORIZONTAL_ALIGNMENT_LEFT)
	else:
		var error := str(observation.get("error", ""))
		var caption := "未取得" if not replied else "内容異常" if status == 422 else "取得不可" if not error.is_empty() else "応答あり"
		_text("?" if not replied else "×" if status == 422 or not error.is_empty() else "✓", doc.position + Vector2(12, 72) * s, 46 * s, 30, Color("9a4b45") if error != "" else Color("536476"))
		_text(caption, doc.position + Vector2(66, 70) * s, doc.size.x - 80 * s, 18, Color("344553"), HORIZONTAL_ALIGNMENT_LEFT)
	var source: Dictionary = observation.get("source", {})
	if source.has("ok"):
		var read := bool(source.ok)
		var color := Color("37755a") if read else Color("9a4b45")
		_mark(Vector2(doc.end.x - 19 * s, doc.position.y + 86 * s), "yes" if read else "no", color)
		_text("読取" if read else "共有", Vector2(doc.end.x - 83 * s, doc.position.y + 91 * s), 48 * s, 14, color)
	# Two seals compare full SHA256 values. The glyph is only an abbreviation.
	var expected_hash := str(observation.get("expected_hash", ""))
	var actual_hash := str(observation.get("hash", ""))
	var hash_match := str(observation.get("hash_match", "unknown"))
	if not expected_hash.is_empty():
		var center := seal.get_center()
		_fingerprint(seal.position + Vector2(10, 22) * s, expected_hash)
		_fingerprint(Vector2(seal.end.x - 49 * s, seal.position.y + 22 * s), actual_hash)
		_text("原本", seal.position + Vector2(4, 66) * s, seal.size.x * 0.44, 14, MUTED)
		_text("取得", Vector2(seal.get_center().x, seal.position.y + 66 * s), seal.size.x * 0.5, 14, MUTED)
		_mark(Vector2(center.x, seal.position.y + 31 * s), "yes" if hash_match == "match" else "no" if hash_match == "different" else "unknown", GREEN if hash_match == "match" else RED if hash_match == "different" else MUTED)
		_text("一致" if hash_match == "match" else "原本と異なる" if hash_match == "different" else "照合待ち", seal.position + Vector2(0, 101) * s, seal.size.x, 14, GREEN if hash_match == "match" else RED if hash_match == "different" else MUTED)
	else:
		_mark(Vector2(seal.get_center().x, seal.position.y + 37 * s), "yes" if recorded and bool(observation.get("passed", false)) and fresh else "no" if recorded and fresh else "unknown", state_color)
		_text("受入一致" if recorded and bool(observation.get("passed", false)) and fresh else "受入不一致" if recorded and fresh else "受入未確認", seal.position + Vector2(0, 92) * s, seal.size.x, 14, state_color)
	if selected in objects: draw_rect(objects[selected].get_rect().grow(-1), Color("9cb2c4"), false, s)
	if replay_position >= 0:
		var end := route_gate - Vector2(15, 0) * s if stopped else route_end
		var point := route_start.lerp(end, minf(1, replay_position * 1.7))
		if replied and replay_position > 0.6: point = response_start.lerp(response_end, (replay_position - 0.6) / 0.4)
		draw_circle(point, 7 * s, BG)
		draw_circle(point, 5 * s, AMBER if stopped else CYAN)
