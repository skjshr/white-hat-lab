extends Control
## Two business objects: a paper queue and a batch machine. No timers or requests.
const UI = preload("res://scripts/ui_theme.gd")
const INK = Color("293c3d")
const MUTED = Color("6b7b7c")
const LINE = Color("adbdbc")
const TEAL = Color("326e66")
const PURPLE = Color("714b67")
const RED = Color("b04b40")
var model: Dictionary = {}
var factor := 1.0
var callback: Callable
var wide := true
var billing := false
var handoff := false
var nodes: Dictionary = {}
var input_rect := Rect2()
var gate_rect := Rect2()
var result_rect := Rect2()

func configure(value: Dictionary, scale: float, action: Callable) -> void:
	model = value.duplicate(true); factor = scale; callback = action; billing = str(model.get("purpose", "")) == "billing"
	handoff = str(model.get("purpose", "")) == "partner-dispatch"
	name = "SaasBillingQueueCanvas" if billing else "SaasPartnerHandoffCanvas" if handoff else "SaasBatchCanvas"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in ["session", "record"]:
		var button := Button.new(); button.name = ("SaasBillingQueue" if billing else "SaasPartnerHandoff" if handoff else "SaasBatch") + part.capitalize()
		button.tooltip_text = "接続券を選択" if part == "session" else "保存された処理原本を開く"
		button.disabled = part == "record" and str(model.get("evidence_record_id", "")).is_empty()
		for state in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, PURPLE if billing else TEAL, 0, 0, 2))
		button.pressed.connect(func(): callback.call(part)); add_child(button); nodes[part] = button
	resized.connect(_layout); _layout.call_deferred()

func _layout() -> void:
	if size.x <= 0: return
	wide = size.x / factor >= 680
	var stamp_height := 28 if int(model.get("loss_amount", 0)) > 0 else 0
	if wide:
		var third := size.x / 3
		input_rect = Rect2(12 * factor, 64 * factor, third - 24 * factor, 112 * factor)
		gate_rect = Rect2(third + 12 * factor, 64 * factor, third - 24 * factor, 112 * factor)
		result_rect = Rect2(third * 2 + 12 * factor, 64 * factor, third - 24 * factor, ((112 if billing else 150) + stamp_height) * factor)
		custom_minimum_size.y = ((198 if billing else 229) + stamp_height) * factor
	else:
		var width := minf(280 * factor, size.x - 20 * factor); var x := (size.x - width) * .5
		input_rect = Rect2(x, 60 * factor, width, 104 * factor)
		gate_rect = Rect2(x, 191 * factor, width, 102 * factor)
		result_rect = Rect2(x, 320 * factor, width, ((106 if billing else 149) + stamp_height) * factor)
		custom_minimum_size.y = ((440 if billing else 484) + stamp_height) * factor
	var gate: Button = nodes.session; gate.position = gate_rect.position; gate.size = gate_rect.size
	var receipt: Button = nodes.record; receipt.position = result_rect.position; receipt.size = result_rect.size
	queue_redraw()

func _text(text: String, position: Vector2, points: int = 14, color: Color = INK, width: float = -1) -> void:
	draw_string(get_theme_default_font(), position, text, HORIZONTAL_ALIGNMENT_LEFT, width, roundi(points * factor), color)

func _arrow(start: Vector2, end: Vector2, solid: bool, color: Color) -> void:
	if solid: draw_line(start, end, color, 2 * factor, true)
	else: draw_dashed_line(start, end, color, 1.3 * factor, 4 * factor)
	var back := (start - end).normalized(); var side := Vector2(-back.y, back.x)
	for sign in [-1, 1]: draw_line(end, end + (back * 6 + side * sign * 4) * factor, color, 1.5 * factor)

func _paper(rect: Rect2, count: int, color: Color) -> void:
	for offset in [8, 4, 0]:
		var paper := Rect2(rect.position + Vector2(offset, offset) * factor, rect.size)
		draw_rect(paper, Color("fffdf8")); draw_rect(paper, color, false, factor)
		for line in [0, 1, 2]: draw_line(paper.position + Vector2(7, 12 + line * 9) * factor, paper.position + Vector2(paper.size.x - 8 * factor, (12 + line * 9) * factor), LINE, factor)
	_text(str(count), rect.position + Vector2(7, 52) * factor, 20, color, rect.size.x - 12 * factor)

func _draw() -> void:
	var accent := PURPLE if billing else TEAL; var status := str(model.get("status", "scheduled")); var completed := status == "completed"
	var waiting := status == "queued"; var available := bool(model.get("configured_available", false)); var blocked := waiting and not available
	draw_rect(Rect2(Vector2.ZERO, size), Color("fbf7fb") if billing else Color("f3f7f5"))
	_time_rail(accent, completed)
	var center := input_rect.get_center(); var paper := Rect2(center - Vector2(29, 43) * factor, Vector2(58, 61) * factor)
	_paper(paper, int(model.get("units", 0)), accent)
	if billing:
		draw_polyline(PackedVector2Array([center + Vector2(-45, 8) * factor, center + Vector2(-40, 26) * factor, center + Vector2(46, 26) * factor, center + Vector2(50, 8) * factor]), accent, 2 * factor)
	else:
		for x in [19, 37]: draw_line(paper.position + Vector2(x, 7) * factor, paper.position + Vector2(x, 35) * factor, LINE, factor)
	_text(("予約 " if status == "scheduled" else "待ち " if waiting else "処理済み ") + "%d%s" % [int(model.get("units", 0)), str(model.get("unit", ""))], Vector2(input_rect.position.x, input_rect.end.y - 3 * factor), 14, accent, input_rect.size.x)
	_gate(accent, completed, available)
	_output(accent, completed)
	var start: Vector2; var end: Vector2; var onward: Vector2; var finish: Vector2
	if wide:
		start = Vector2(input_rect.get_center().x + 51 * factor, input_rect.get_center().y); end = Vector2(gate_rect.get_center().x - 61 * factor, gate_rect.get_center().y)
		onward = Vector2(gate_rect.get_center().x + 61 * factor, gate_rect.get_center().y); finish = Vector2(result_rect.position.x + 4 * factor, gate_rect.get_center().y)
	else:
		start = Vector2(center.x, input_rect.end.y + 3 * factor); end = Vector2(center.x, gate_rect.position.y - 3 * factor)
		onward = Vector2(center.x, gate_rect.end.y + 3 * factor); finish = Vector2(center.x, result_rect.position.y - 3 * factor)
	_arrow(start, end, completed, accent if completed else LINE)
	_arrow(onward, finish, completed, accent if completed else RED if blocked else LINE)
	if blocked:
		var stop := (onward + finish) * .5; draw_circle(stop, 8 * factor, Color("f3f7f5"))
		for sign in [-1, 1]: draw_line(stop + Vector2(-5, -5 * sign) * factor, stop + Vector2(5, 5 * sign) * factor, RED, 2 * factor)

func _time_rail(accent: Color, completed: bool) -> void:
	var minute := int(model.get("minute", 0)); var release := int(model.get("release_minute", 0)); var deadline := int(model.get("deadline_minute", 0))
	var horizon := maxi(deadline + 4, minute + 2); var start := 24 * factor; var length := maxf(0, size.x - 48 * factor); var y := 28 * factor
	var released_x := start + length * release / maxf(1, horizon); var deadline_x := start + length * deadline / maxf(1, horizon)
	var current_x := start + length * minute / maxf(1, horizon)
	draw_line(Vector2(start, y), Vector2(start + length, y), LINE, 2 * factor)
	draw_line(Vector2(start, y), Vector2(current_x, y), accent, 2 * factor)
	draw_circle(Vector2(released_x, y), 4 * factor, accent if minute >= release else Color.WHITE); draw_arc(Vector2(released_x, y), 4 * factor, 0, TAU, 16, accent, factor)
	draw_line(Vector2(deadline_x, y - 9 * factor), Vector2(deadline_x, y + 9 * factor), RED if int(model.get("loss_amount", 0)) > 0 else MUTED, factor)
	_text("投入 %d分" % release, Vector2(maxf(start, released_x - 30 * factor), 14 * factor), 12, MUTED, 93 * factor)
	_text("締切 %d分" % deadline, Vector2(maxf(start + 76 * factor, minf(size.x - 103 * factor, deadline_x - 20 * factor)), 51 * factor), 12, MUTED, 95 * factor)
	var marker := PackedVector2Array([Vector2(current_x - 5 * factor, y - 9 * factor), Vector2(current_x + 5 * factor, y - 9 * factor), Vector2(current_x, y - 3 * factor)])
	draw_colored_polygon(marker, accent)
	if completed or minute > deadline: _text("✓ 完了" if completed else "! 超過", Vector2(start, 51 * factor), 12, RED if int(model.get("loss_amount", 0)) > 0 else accent, 70 * factor)
	draw_line(Vector2(current_x, y - 2 * factor), Vector2(current_x, y + 8 * factor), accent, 2 * factor)

func _gate(accent: Color, completed: bool, available: bool) -> void:
	var center := gate_rect.get_center(); var session_id := str(model.get("used_session_id", "")) if completed else str(model.get("session_id", ""))
	var ticket := Rect2(center - Vector2(60, 40) * factor, Vector2(120, 54) * factor)
	draw_rect(ticket, Color.WHITE); draw_rect(ticket, accent, false, 1.5 * factor)
	if billing:
		for x in [ticket.position.x, ticket.end.x]: draw_circle(Vector2(x, ticket.position.y + 27 * factor), 5 * factor, Color("fbf7fb"))
		draw_dashed_line(ticket.position + Vector2(20, 4) * factor, ticket.position + Vector2(20, 50) * factor, LINE, factor, 3 * factor)
	elif handoff:
		var folder := Rect2(ticket.position + Vector2(8, 10) * factor, Vector2(104, 34) * factor)
		draw_rect(folder, Color("e3eae2")); draw_rect(folder, accent, false, factor)
		draw_rect(Rect2(folder.position - Vector2(0, 6) * factor, Vector2(35, 6) * factor), Color("e3eae2"))
		draw_line(folder.position - Vector2(0, 6) * factor, folder.position + Vector2(35, -6) * factor, accent, factor)
	else:
		draw_rect(Rect2(ticket.position + Vector2(8, 8) * factor, Vector2(104, 27) * factor), Color("dbeae4"))
		for x in [28, 55, 82]: draw_rect(Rect2(ticket.position + Vector2(x, 40) * factor, Vector2(10, 5) * factor), accent)
	_text(session_id if not session_id.is_empty() else "接続券なし", ticket.position + Vector2(28 if billing else 12, 29) * factor, 13, INK, ticket.size.x - (35 if billing else 20) * factor)
	_text("使用した券" if completed else "○ 有効券あり" if available else "× 券を再発行", Vector2(gate_rect.position.x, gate_rect.end.y - 24 * factor), 13, accent if completed or available else RED, gate_rect.size.x)
	_text("請求連携" if billing else "受渡の接続券" if handoff else "配車集計機", Vector2(gate_rect.position.x, gate_rect.end.y - 3 * factor), 14, INK, gate_rect.size.x)

func _output(accent: Color, completed: bool) -> void:
	var rect := result_rect.grow(-5 * factor)
	if billing:
		draw_rect(rect, accent if completed else LINE, false, (2 if completed else 1) * factor)
		_text("✓ 予約処理済み" if completed else "受付控え / 未処理", rect.position + Vector2(8, 24) * factor, 14, accent if completed else MUTED, rect.size.x - 16 * factor)
		_text("%d分 · %d%s" % [int(model.get("completed_minute", 0)), int(model.get("units", 0)), str(model.get("unit", ""))] if completed else "―", rect.position + Vector2(8, 49) * factor, 15, INK, rect.size.x - 16 * factor)
		_text(str(model.get("record_id", "")) if completed else "処理の記録なし", rect.position + Vector2(8, 74) * factor, 12, MUTED, rect.size.x - 16 * factor)
	elif handoff:
		draw_rect(rect, Color("fffef8")); draw_rect(rect, accent if completed else LINE, false, factor)
		var folded := PackedVector2Array([rect.position + Vector2(rect.size.x - 15 * factor, 0), rect.position + Vector2(rect.size.x - 15 * factor, 12 * factor), rect.position + Vector2(rect.size.x, 12 * factor)])
		draw_polyline(folded, LINE, factor)
		_text(str(model.get("partner_name", "委託先")), rect.position + Vector2(8, 22) * factor, 15, INK, rect.size.x - 26 * factor)
		_text(str(model.get("destination", "")), rect.position + Vector2(8, 43) * factor, 12, MUTED, rect.size.x - 16 * factor)
		draw_line(rect.position + Vector2(8, 51) * factor, rect.position + Vector2(rect.size.x - 8 * factor, 51 * factor), LINE, factor)
		var stamp := Rect2(rect.position + Vector2(8, 60) * factor, Vector2(rect.size.x - 16 * factor, 27 * factor))
		draw_rect(stamp, accent if completed else LINE, false, (2 if completed else 1) * factor)
		_text("✓ 委託先受付" if completed else "― 未受付", stamp.position + Vector2(7, 20) * factor, 15, accent if completed else MUTED, stamp.size.x - 14 * factor)
		_text("%d%s · %d分" % [int(model.get("units", 0)), str(model.get("unit", "")), int(model.get("completed_minute", 0))] if completed else "受付の記録なし", rect.position + Vector2(8, 106) * factor, 13, INK, rect.size.x - 16 * factor)
		_text(str(model.get("record_id", "")) if completed else "", rect.position + Vector2(8, 126) * factor, 12, MUTED, rect.size.x - 16 * factor)
	else:
		draw_rect(rect, Color.WHITE); draw_rect(rect, accent if completed else LINE, false, factor)
		var header := Rect2(rect.position, Vector2(rect.size.x, 29 * factor)); draw_rect(header, Color("dbeae4"))
		_text("✓ 集計処理控え" if completed else "集計結果 / 未作成", header.position + Vector2(8, 20) * factor, 14, accent if completed else MUTED, rect.size.x - 16 * factor)
		var labels := ["行数", "完了", "記録"]
		var values := ["%d行" % int(model.get("units", 0)), "%d分" % int(model.get("completed_minute", 0)), str(model.get("record_id", ""))] if completed else ["―", "―", "―"]
		for index in range(3):
			var y := rect.position.y + (30 + index * 31) * factor
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), LINE, factor)
			draw_line(Vector2(rect.position.x + 51 * factor, y), Vector2(rect.position.x + 51 * factor, y + 31 * factor), LINE, factor)
			_text(labels[index], Vector2(rect.position.x + 7 * factor, y + 22 * factor), 13, MUTED, 43 * factor)
			_text(values[index], Vector2(rect.position.x + 59 * factor, y + 22 * factor), 13, INK, rect.size.x - 66 * factor)
	var loss := int(model.get("loss_amount", 0))
	if loss > 0:
		var stamp := Rect2(Vector2(rect.position.x + 6 * factor, rect.end.y - 25 * factor), Vector2(rect.size.x - 12 * factor, 21 * factor))
		draw_rect(stamp, RED, false, 1.5 * factor)
		_text("! 補償 ¥%d" % loss, stamp.position + Vector2(6, 16) * factor, 13, RED, stamp.size.x - 12 * factor)
