extends Control
## Saved session specimens only. Selecting a specimen never requests access.
const UI = preload("res://scripts/ui_theme.gd")
const INK = Color("283139")
const MUTED = Color("6b7781")
const BLUE = Color("216a92")
const LINE = Color("a8b9c2")
const RED = Color("ad4943")
var model: Dictionary = {}
var factor := 1.0
var selected := ""
var callback: Callable
var tickets: Dictionary = {}
var rows: Dictionary = {}
var wide := false

func configure(value: Dictionary, scale: float, selection: String, action: Callable) -> void:
	name = "SaasSessionCanvas"; model = value.duplicate(true); factor = scale; selected = selection; callback = action
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for session in model.get("sessions", []):
		var id := str(session.get("id", "")); rows[id] = session
		var button := Button.new(); button.name = "SaasSession_" + id.replace("-", "_")
		button.set_meta("session_id", id); button.tooltip_text = "接続券を選択 / " + id
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, BLUE, 0, 0, 2))
		button.pressed.connect(func(): callback.call(id)); button.draw.connect(_draw_ticket.bind(button, id))
		add_child(button); tickets[id] = button
	resized.connect(_layout); _layout.call_deferred()

func _layout() -> void:
	if size.x <= 0: return
	wide = size.x / factor >= 760 and tickets.size() <= 3
	var count := tickets.size(); var index := 0
	for id in tickets:
		var button: Button = tickets[id]
		if wide:
			var column := size.x / maxi(1, count)
			button.position = Vector2(column * index + (column - 172 * factor) * .5, 108 * factor)
			button.size = Vector2(172, 80) * factor
		else:
			button.position = Vector2(size.x * .35, (79 + index * 120) * factor)
			button.size = Vector2(minf(172 * factor, size.x * .34), 92 * factor)
		index += 1
	custom_minimum_size.y = (315 if wide else 80 + maxi(1, count) * 120) * factor
	queue_redraw()

func _text(control: Control, text: String, point: Vector2, points: int = 14, color: Color = INK, width: float = -1.0) -> void:
	control.draw_string(control.get_theme_default_font(), point, text, HORIZONTAL_ALIGNMENT_LEFT, width, roundi(points * factor), color)

func _draw_ticket(button: Button, id: String) -> void:
	var row: Dictionary = rows[id]; var active := bool(row.get("active", false)); var border := BLUE if id == selected else LINE
	var paper := Rect2(Vector2(3, 3) * factor, button.size - Vector2(6, 6) * factor)
	button.draw_rect(paper, Color("edf4f8") if id == selected else Color("f9faf8"))
	button.draw_rect(paper, border, false, (2 if id == selected else 1) * factor)
	for x in [paper.position.x, paper.end.x]: button.draw_circle(Vector2(x, 33 * factor), 5 * factor, Color.WHITE)
	button.draw_dashed_line(Vector2(10, 34) * factor, Vector2(button.size.x - 10 * factor, 34 * factor), LINE, factor, 3 * factor)
	_text(button, id, Vector2(12, 25) * factor, 17, INK, button.size.x - 24 * factor)
	_text(button, str(row.get("issued_at", "?")) + " 発行", Vector2(12, 48 if wide else 55) * factor, 14, INK, button.size.x - 24 * factor)
	_text(button, "○ 発行済み" if active else "× 失効済み", Vector2(12, 70 if wide else 78) * factor, 14, MUTED if active else RED, button.size.x - 24 * factor)
	if not active:
		button.draw_line(Vector2(button.size.x - 29 * factor, 43 * factor), Vector2(button.size.x - 12 * factor, 60 * factor), RED, 2 * factor, true)
		button.draw_line(Vector2(button.size.x - 29 * factor, 60 * factor), Vector2(button.size.x - 12 * factor, 43 * factor), RED, 2 * factor, true)

func _arrow(start: Vector2, end: Vector2, solid: bool, color: Color = LINE) -> void:
	if solid: draw_line(start, end, color, 1.5 * factor, true)
	else: draw_dashed_line(start, end, color, factor, 4 * factor)
	var back := (start - end).normalized(); var side := Vector2(-back.y, back.x)
	for sign in [-1, 1]: draw_line(end, end + (back * 6 + side * 3 * sign) * factor, color, 1.5 * factor, true)

func _device(center: Vector2, row: Dictionary, width: float, compact: bool = false) -> void:
	var glyph := center - Vector2(54 * factor, 0) if compact else center
	var screen := Rect2(glyph - Vector2(20, 19) * factor, Vector2(40, 27) * factor)
	draw_rect(screen, Color("edf0f2")); draw_rect(screen, MUTED, false, factor)
	draw_line(glyph + Vector2(0, 8) * factor, glyph + Vector2(0, 14) * factor, MUTED, factor)
	draw_line(glyph + Vector2(-13, 14) * factor, glyph + Vector2(13, 14) * factor, MUTED, factor)
	_text(self, str(row.get("device", "?")), center + (Vector2(-24, -4) * factor if compact else Vector2(-width * .5, 33 * factor)), 14, INK, width - 52 * factor if compact else width)
	_text(self, str(row.get("approval", "? 発行原本")), center + (Vector2(-24, 16) * factor if compact else Vector2(-width * .5, 52 * factor)), 12, MUTED, width - 52 * factor if compact else width)

func _destination(center: Vector2, row: Dictionary, width: float) -> void:
	var known := not str(row.get("destination", "")).is_empty()
	var rect := Rect2(center - Vector2(19, 19) * factor, Vector2(38, 35) * factor)
	if known:
		var kind := str(row.get("destination_kind", ""))
		if kind == "external-storage":
			draw_rect(rect, Color("edf0ef"))
			for x in [rect.position.x, rect.end.x]: draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), MUTED, factor)
			for y in [rect.position.y, rect.end.y]:
				var points := PackedVector2Array()
				for step in range(33): points.append(Vector2(center.x + cos(TAU * step / 32.0) * 19 * factor, y + sin(TAU * step / 32.0) * 5 * factor))
				draw_polyline(points, MUTED, factor, true)
		else:
			draw_rect(rect, Color("edf0ef")); draw_rect(rect, MUTED, false, factor)
			for line in [0, 1, 2]: draw_line(rect.position + Vector2(7, 9 + line * 7) * factor, rect.position + Vector2(30, 9 + line * 7) * factor, LINE, factor)
			if kind.begins_with("internal-"):
				for x in [14, 23]: draw_line(rect.position + Vector2(x, 6) * factor, rect.position + Vector2(x, 28) * factor, LINE, factor)
			else:
				draw_polyline(PackedVector2Array([rect.position + Vector2(29, 0) * factor, rect.position + Vector2(29, 7) * factor, rect.position + Vector2(38, 7) * factor]), MUTED, factor)
	else:
		draw_arc(center, 19 * factor, 0, TAU, 32, LINE, factor, true)
		_text(self, "?", center + Vector2(-5, 6) * factor, 19, MUTED)
	_text(self, str(row.get("destination", "")) if known else "? 要求先未確認", center + Vector2(-width * .5, 34 * factor), 14, INK, width)
	var read_rows := int(row.get("read_rows", -1))
	_text(self, "要求 %d行" % read_rows if read_rows >= 0 else "要求 ?行", center + Vector2(-width * .5, 54 * factor), 13, MUTED, width)
	_text(self, str(row.get("measurement", "? 未実測")), center + Vector2(-width * .5, 74 * factor), 12, MUTED, width)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	var app_title := str(model.get("app", "")) + " / " + str(model.get("label", ""))
	_text(self, app_title, Vector2(10, 22) * factor, 16, INK, size.x - 20 * factor)
	_text(self, str(model.get("approval", "")), Vector2(10, 43) * factor, 13, MUTED, size.x - 20 * factor)
	var trunk_y := (54 if wide else 62) * factor
	if wide:
		draw_line(Vector2(size.x * .5, 48 * factor), Vector2(size.x * .5, trunk_y), LINE, factor)
		var count := tickets.size(); var column := size.x / maxi(1, count)
		draw_line(Vector2(column * .5 - 54 * factor, trunk_y), Vector2(size.x - column * .5 - 54 * factor, trunk_y), LINE, factor)
	for id in tickets:
		var ticket: Button = tickets[id]; var row: Dictionary = rows[id]
		var current := bool(row.get("fresh", false)); var code := int(row.get("status", 0)); var success := current and code == 200
		var color := BLUE if success else RED if current and code >= 400 else LINE
		if wide:
			var x := ticket.position.x + ticket.size.x * .5
			_arrow(Vector2(x - 54 * factor, trunk_y), Vector2(x - 54 * factor, 61 * factor), false)
			_device(Vector2(x, 82 * factor), row, 158 * factor, true)
			draw_polyline(PackedVector2Array([Vector2(x - 54 * factor, 97 * factor), Vector2(x - 54 * factor, 102 * factor), Vector2(x, 102 * factor), Vector2(x, 108 * factor)]), LINE, factor)
			_arrow(Vector2(x, ticket.get_rect().end.y + 3 * factor), Vector2(x, 208 * factor), success, color)
			_destination(Vector2(x, 231 * factor), row, 172 * factor)
		else:
			var y := ticket.position.y + 29 * factor
			draw_line(Vector2(9 * factor, trunk_y), Vector2(9 * factor, y), LINE, factor)
			_arrow(Vector2(9 * factor, y), Vector2(size.x * .16 - 24 * factor, y), false)
			_device(Vector2(size.x * .16, y), row, size.x * .25)
			_arrow(Vector2(size.x * .16 + 25 * factor, y), Vector2(ticket.position.x - 3 * factor, y), false)
			var endpoint := Vector2(size.x * .84 - 23 * factor, y)
			_arrow(Vector2(ticket.get_rect().end.x + 3 * factor, y), endpoint, success, color)
			_destination(Vector2(size.x * .84, y), row, size.x * .25)
		if current and code >= 400:
			var cross := Vector2(ticket.position.x + ticket.size.x * .5, ticket.get_rect().end.y + 17 * factor) if wide else Vector2((ticket.get_rect().end.x + size.x * .84 - 23 * factor) * .5, ticket.position.y + 29 * factor)
			draw_circle(cross, 6 * factor, Color.WHITE)
			for sign in [-1, 1]: draw_line(cross + Vector2(-4, -4 * sign) * factor, cross + Vector2(4, 4 * sign) * factor, RED, 1.5 * factor)
