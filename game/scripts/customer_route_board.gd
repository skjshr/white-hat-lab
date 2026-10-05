extends Control
## CRM relationship route, projected solely from the saved customer outcome.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("243940")
const TEAL := Color("247c72")
const LINE := Color("c2d5d0")
const MUTED := Color("64777b")
const RED := Color("b84639")
var item: Dictionary = {}
var factor := 1.0
var fields: Array[Dictionary] = []
var objects: Array[Button] = []

func setup(saved: Dictionary, scale: float, inspect: Callable, next: Callable) -> void:
	item = saved.duplicate(true); factor = scale
	custom_minimum_size.y = 226 * factor; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 3:
		var object := Button.new(); object.name = "CycleRouteObject" + str(index)
		object.flat = true; object.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		object.tooltip_text = ["前回の納品記録を開く", "顧客との関係を確認", "次の業務の状況を確認"][index]
		object.add_theme_stylebox_override("normal", UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
		object.add_theme_stylebox_override("hover", UI.style(Color("e1efe8"), TEAL, 6, 0, 1))
		object.add_theme_stylebox_override("pressed", UI.style(Color("c9e1d7"), TEAL, 6, 0, 1))
		object.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, TEAL, 6, 0, 2))
		object.pressed.connect(next if index == 2 else inspect)
		object.draw.connect(_object.bind(index)); add_child(object); objects.append(object)
	_field("CycleSourceTitle", str(item.get("source_title", "前回の仕事")), 15, .02, 135, .29)
	_field("CycleSourceDay", "DAY %02d · %s" % [int(item.get("source_day", 0)), "期限内" if str(item.get("source_rating", "")) == "on_time" else "期限超過" if str(item.get("source_rating", "")) == "late" else "要再対応"], 12, .02, 189, .29)
	var outcome: Dictionary = item.get("last_outcome", {})
	var satisfaction: int = int(outcome.get("satisfaction", item.get("source_satisfaction", -1)))
	_field("CycleRelationshipValue", str(satisfaction) + " / 100" if satisfaction >= 0 else "記録なし", 22, .355, 78, .29)
	_field("CycleRelationshipDay", "顧客満足 · DAY %02d" % int(outcome.get("day", item.get("source_day", 0))), 12, .355, 120, .29)
	_field("CycleRelationshipStatus", status_label(), 15, .355, 158, .29)
	_field("CycleNextTitle", str(item.get("title", "次の仕事")), 15, .685, 135, .295)
	_field("CycleNextService", {"backup":"退避・復元", "permissions":"共有資料", "network":"ネットワーク", "identity":"利用者ID", "external_sharing":"外部ファイル共有", "endpoint":"端末調査"}.get(str(item.get("work_family", "")), "次の業務"), 12, .685, 189, .295)
	resized.connect(_layout); _layout()

func status_label() -> String:
	return {"ready":"▶ 相談受付", "locked":"⌛ 準備待ち", "paused":"Ⅱ 相談保留", "fulfilled":"✓ 対応済み"}.get(str(item.get("status", "")), "— 未確認")

func _field(id: String, value: String, points: int, x: float, y: float, width: float) -> void:
	var label := Label.new(); label.name = id; label.text = value
	label.add_theme_font_override("font", UI.font(700 if points == 22 else 500))
	label.add_theme_font_size_override("font_size", int(points * factor)); label.add_theme_color_override("font_color", INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label); fields.append({"node":label,"value":value,"x":x,"y":y,"width":width,"points":points})

func _layout() -> void:
	for index in objects.size():
		objects[index].position = Vector2(size.x * (.025 + index * .33), 12 * factor)
		objects[index].size = Vector2(size.x * .285, 119 * factor)
		objects[index].queue_redraw()
	for field in fields:
		if int(field.points) == 15: field.node.text = _title_lines(field.node, str(field.value), size.x * float(field.width))
		field.node.position = Vector2(size.x * float(field.x), float(field.y) * factor)
		field.node.size = Vector2(size.x * float(field.width), _field_height(int(field.points)) * factor)
	# Labels first acquire their actual width. Their cached wrapped minimum can
	# still describe the initial zero-width layout until the next deferred pass.
	call_deferred("_settle_labels")
	queue_redraw()

func _settle_labels() -> void:
	for field in fields: field.node.size.y = _field_height(int(field.points)) * factor

func _field_height(points: int) -> float:
	return 46.0 if points == 15 else 33.0 if points == 22 else 20.0

func _title_lines(label: Label, value: String, width: float) -> String:
	var font: Font = label.get_theme_font("font"); var points := label.get_theme_font_size("font_size")
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x <= width: return value
	var boundary := value.find("を")
	if boundary < 0: return value
	var first := value.left(boundary + 1); var second := value.substr(boundary + 1)
	if font.get_string_size(first, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x <= width and font.get_string_size(second, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x <= width:
		return first + "\n" + second
	return value

func _draw() -> void:
	draw_style_box(UI.style(Color("f5faf6"), LINE, 6, 0, 1), Rect2(Vector2.ZERO, size))
	var y := 84 * factor
	var active: bool = str(item.get("status", "")) in ["ready", "fulfilled"]
	for pair in [[.20,.37],[.63,.80]]:
		var start := Vector2(size.x * float(pair[0]), y); var end := Vector2(size.x * float(pair[1]), y)
		if active or float(pair[0]) < .3: draw_line(start, end, TEAL, 3 * factor, true)
		else: draw_dashed_line(start, end, MUTED, 2 * factor, 7 * factor, true)
		draw_polyline(PackedVector2Array([end - Vector2(7, 5) * factor, end, end - Vector2(7, -5) * factor]), TEAL if active else MUTED, 2 * factor, true)

func _object(index: int) -> void:
	var object := objects[index]; var center := Vector2(object.size.x / 2, 67 * factor); var f := factor
	if index == 1:
		var outcome: Dictionary = item.get("last_outcome", {})
		var value := int(outcome.get("satisfaction", item.get("source_satisfaction", -1)))
		object.draw_arc(center, 49*f, PI*.75, PI*2.25, 60, LINE, 7*f, true)
		if value >= 0: object.draw_arc(center, 49*f, PI*.75, PI*.75 + PI*1.5*clampf(value/100.0,0,1), 60, RED if str(item.get("status", "")) == "paused" else TEAL, 7*f, true)
		for tick in 6:
			var direction := Vector2.from_angle(PI*.75 + PI*1.5*tick/5)
			object.draw_line(center + direction*54*f, center + direction*59*f, INK, f, true)
		return
	var box := Rect2(center - Vector2(31,42)*f, Vector2(62,84)*f)
	if index == 0:
		object.draw_style_box(UI.style(Color("fffaf0"), Color("b9ac88"), 2, 0, 2), box)
		for offset in [0,11,22]: object.draw_line(center + Vector2(-18, -23+offset)*f, center + Vector2(18,-23+offset)*f, Color("c1b391"), f)
		object.draw_arc(center + Vector2(12,24)*f, 13*f, 0,TAU,32, TEAL if str(item.get("source_rating", "")) == "on_time" else RED, 2*f,true)
		_mark(object, center + Vector2(12,24)*f, "check" if str(item.get("source_rating", "")) == "on_time" else "late")
	else:
		if str(item.get("work_family", "")) == "backup":
			for offset in [-26,0,26]:
				object.draw_style_box(UI.style(Color("253c45"), TEAL, 5, 0, 2), Rect2(center + Vector2(-36,offset-10)*f,Vector2(72,21)*f))
				object.draw_circle(center + Vector2(24,offset)*f, 3*f, Color("e4edbf"))
		else:
			object.draw_style_box(UI.style(Color("e0eee7"), TEAL, 5, 0, 2), box)
			object.draw_circle(center + Vector2(0,-15)*f, 10*f, TEAL)
			object.draw_line(center + Vector2(-18,12)*f, center + Vector2(18,12)*f, TEAL, 3*f)
			object.draw_line(center + Vector2(-18,25)*f, center + Vector2(10,25)*f, TEAL, 3*f)
		_mark(object, center + Vector2(31,37)*f, {"ready":"play","locked":"wait","paused":"pause","fulfilled":"check"}.get(str(item.get("status", "")), "wait"))

func _mark(object: Button, center: Vector2, kind: String) -> void:
	var f := factor; var color := RED if kind in ["late","pause"] else TEAL
	object.draw_circle(center, 12*f, Color("f5faf6")); object.draw_arc(center,12*f,0,TAU,32,color,2*f,true)
	match kind:
		"check": object.draw_polyline(PackedVector2Array([center+Vector2(-6,0)*f,center+Vector2(-1,5)*f,center+Vector2(7,-5)*f]),color,2*f,true)
		"pause":
			for x in [-4,4]: object.draw_line(center+Vector2(x,-6)*f,center+Vector2(x,6)*f,color,3*f)
		"play": object.draw_colored_polygon(PackedVector2Array([center+Vector2(-4,-6)*f,center+Vector2(6,0)*f,center+Vector2(-4,6)*f]),color)
		_:
			object.draw_line(center,center+Vector2(0,-7)*f,color,2*f); object.draw_line(center,center+Vector2(6,3)*f,color,2*f)
