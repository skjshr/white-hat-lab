extends Control
## Read-only floor projection; the delivery node owns placement validation.
const RULES = preload("res://scripts/placement_rules.gd")
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
var equipment_id := ""
var orders: Array = []
var expanded := false
var factor := 1.0
var candidate := Vector2.ZERO
var yaw := 0.0
var valid := false
var picked: Callable
var names: Dictionary = {}
var route: Array[Vector3] = []

func configure(id: String, records: Array, annex: bool, scale: float, labels: Dictionary, callback: Callable) -> void:
	equipment_id = id; orders = records.duplicate(true); expanded = annex; factor = scale; names = labels; picked = callback
	name = "EquipmentPlacementMap"; custom_minimum_size = Vector2(300, 204 * factor)
	size_flags_horizontal = SIZE_EXPAND_FILL; size_flags_vertical = SIZE_EXPAND_FILL
	focus_mode = FOCUS_ALL; mouse_default_cursor_shape = CURSOR_POINTING_HAND
	resized.connect(queue_redraw)

func set_candidate(at: Vector2, rotation_y: float, is_valid: bool) -> void:
	candidate = at; yaw = rotation_y; valid = is_valid
	route.clear()
	if valid and equipment_id in RULES.DESKS:
		var proposed := orders.duplicate(true)
		proposed = proposed.filter(func(record): return str(record.get("id", "")) != equipment_id)
		var placed := {"id":equipment_id, "status":"installed", "install_position":[at.x, 0, at.y], "rotation_y":yaw}
		proposed.append(placed)
		route = RULES.walk_path(RULES.ENTRY, RULES.workplace(placed).approach, proposed, expanded)
	queue_redraw()

func _world_bounds() -> Rect2:
	return Rect2(-6.1, -5.1, 18.3 if expanded else 12.2, 10.2)

func _ratio() -> float:
	var bounds := _world_bounds()
	return maxf(1, minf((size.x - 34 * factor) / bounds.size.x, (size.y - 20 * factor) / bounds.size.y))

func _origin() -> Vector2:
	return (size - _world_bounds().size * _ratio()) * .5

func _point(at: Vector2) -> Vector2:
	return _origin() + (at - _world_bounds().position) * _ratio()

func _rect(rect: Rect2) -> Rect2:
	return Rect2(_point(rect.position), rect.size * _ratio())

func _text(value: String, at: Vector2, points: int = 12, color: Color = M.INK) -> void:
	draw_string(UI.font(600), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(points * factor), color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("edf1ec"))
	var rooms: Array[Rect2] = [Rect2(-5.82, -4.8, 11.64, 9.35)]
	if expanded: rooms.append(Rect2(6.12, .12, 5.75, 4.73))
	for room in rooms:
		var rect := _rect(room)
		draw_rect(rect, Color("fbfcf9")); draw_rect(rect, M.INK, false, 2 * factor)
		var step := _ratio()
		var x := rect.position.x + step
		while x < rect.end.x:
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color("e7ece6")); x += step
		var y := rect.position.y + step
		while y < rect.end.y:
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("e7ece6")); y += step
	for fixed in RULES._static_rects():
		draw_rect(_rect(fixed), Color("aab9b3")); draw_rect(_rect(fixed), Color("758b84"), false, factor)
	for spec in [[Vector2(-3.6, -2.3), str(names.get("aya", "綾"))], [Vector2(2.8, -2.8), str(names.get("ren", "蓮"))], [Vector2(-.5, -1), "自席"]]:
		_text(str(spec[1]), _point(spec[0]) + Vector2(-15, -11) * factor, 11)
	for order in orders:
		if not RULES._installed(order) or str(order.get("id", "")) not in RULES.FLOOR_IDS: continue
		var rectangle: Rect2 = RULES.footprint(str(order.id), RULES._stored_position(order), RULES._rotation(order))
		draw_rect(_rect(rectangle), Color("496e67")); draw_rect(_rect(rectangle), M.INK, false, factor)
		_text("✓", _point(rectangle.get_center()), 13, M.WHITE)
	if route.size() > 1:
		for index in range(1, route.size()):
			draw_line(_point(Vector2(route[index - 1].x, route[index - 1].z)), _point(Vector2(route[index].x, route[index].z)), Color("82bcb1"), 3 * factor, true)
	var destination := _rect(RULES.footprint(equipment_id, candidate, yaw))
	var ink := M.ACCENT if valid else M.DANGER
	draw_rect(destination, Color(ink, .2)); draw_rect(destination, ink, false, 2 * factor)
	if not valid:
		draw_line(destination.position, destination.end, ink, 2 * factor)
		draw_line(Vector2(destination.end.x, destination.position.y), Vector2(destination.position.x, destination.end.y), ink, 2 * factor)
	var center := _point(candidate)
	# Desks face their actual chair (+Z in the equipment's local coordinates).
	# Use the same transform as workplace() so the route and seat agree.
	var direction := Vector2(0, 1).rotated(-yaw)
	var seat := center + direction * .72 * _ratio()
	draw_line(center, seat, ink, 2 * factor)
	if equipment_id in RULES.DESKS:
		draw_rect(Rect2(seat - Vector2.ONE * 4 * factor, Vector2.ONE * 8 * factor), ink, false, factor)
	else:
		draw_circle(seat, 3 * factor, ink)
	_text("✓ 設置予定" if valid else "× 置けません", destination.position - Vector2(0, 5 * factor), 12, ink)
	var entry := _point(Vector2(RULES.ENTRY.x, RULES.ENTRY.z))
	draw_circle(entry, 6 * factor, M.ACCENT)
	_text("入口", entry + Vector2(10, 5) * factor, 11)
	if has_focus(): draw_rect(Rect2(Vector2.ONE * 2, size - Vector2.ONE * 4), M.ACCENT, false, factor)

func _gui_input(event: InputEvent) -> void:
	var at := candidate
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		at = (event.position - _origin()) / _ratio() + _world_bounds().position
		at = Vector2(snappedf(at.x, RULES.STEP), snappedf(at.y, RULES.STEP)); grab_focus()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: at.x -= RULES.STEP
			KEY_RIGHT: at.x += RULES.STEP
			KEY_UP: at.y -= RULES.STEP
			KEY_DOWN: at.y += RULES.STEP
			_: return
	else: return
	accept_event()
	if picked.is_valid(): picked.call(at)
