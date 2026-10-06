extends Control
## Read-only view. Forecast deltas mirror Game.staff_capacity(),
## Game.contract_capacity() and Game.care_portfolio(); never change Game.state.
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
const ART = preload("res://scripts/equipment_art.gd")
const DESKS: Array[String] = ["teamdesk", "annexdesk_a", "annexdesk_b"]
var model: Dictionary = {}
var factor: float = 1.0
var view_mode: String = "equipment"
var seat_action: Callable = Callable()
var seat_buttons: Array[Button] = []
var effect_label: Label

static func snapshot(game, equipment_id: String = "") -> Dictionary:
	var equipment: Array = game.state.get("equipment", [])
	var staff: Dictionary = game.staff_summary()
	var operating: Dictionary = game.company_operating_summary()
	var care: Dictionary = game.care_portfolio()
	var owned: bool = equipment_id in equipment
	var gains: Array[int] = [0, 0, 0]
	if not owned:
		if equipment_id == "teamdesk": gains = [1, 2, 2]
		elif equipment_id in ["annexdesk_a", "annexdesk_b"]: gains = [1, 1, 1]
		elif equipment_id == "monitor": gains = [0, 0, 2]
	var order: Dictionary = game.delivery_for(equipment_id)
	var seats: Array[Dictionary] = []
	for desk in DESKS:
		var member_id: String = ""
		var member_name: String = ""
		for member in game.team_members():
			if bool(member.get("hired", false)) and str(member.get("workplace", "")) == desk:
				member_id = str(member.get("id", "")); member_name = str(member.get("name", member_id)); break
		var desk_order: Dictionary = game.delivery_for(desk)
		seats.append({"id":desk, "installed":desk in equipment, "member_id":member_id, "member_name":member_name, "status":str(desk_order.get("status", "")), "locked":desk != "teamdesk" and not game.office_expanded()})
	return {"id":equipment_id, "installed":owned, "status":str(order.get("status", "")), "available_day":int(order.get("available_day", -1)), "blocked":str(game.equipment_unavailable_reason(equipment_id)), "effect":str(game.equipment_effect(equipment_id)), "seats":seats,
		"capacities":[{"id":"staff", "label":"追加採用席", "used":int(staff.get("count", 0)), "capacity":int(staff.get("capacity", 0)), "gain":gains[0]}, {"id":"contracts", "label":"同時受注", "used":int(operating.get("open_contracts", 0)), "capacity":int(game.contract_capacity()), "gain":gains[1]}, {"id":"care", "label":"保守枠", "used":int(care.get("reserved_count", 0)), "capacity":int(care.get("capacity", 0)), "gain":gains[2]}]}

func configure(data: Dictionary, scale: float, mode: String = "equipment", on_seat: Callable = Callable()) -> void:
	model = data.duplicate(true); factor = maxf(.5, scale); view_mode = mode; seat_action = on_seat
	name = "StaffSeatMap" if mode == "staff" else "EquipmentCapacityCanvas"
	set_meta("equipment_scale_managed", true)
	theme = M.theme(factor)
	theme.set_color("font_color", "TooltipLabel", M.WHITE)
	theme.set_stylebox("panel", "TooltipPanel", M.surface(M.DARK, 8))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = (112.0 if mode == "staff" else 148.0 if _shows_effect() else 194.0) * factor
	for child in get_children(): remove_child(child); child.queue_free()
	seat_buttons.clear()
	effect_label = null
	if mode != "staff" and _shows_effect():
		effect_label = Label.new(); effect_label.name = "EquipmentPrimaryEffect"
		effect_label.text = str(model.get("effect", ""))
		effect_label.add_theme_font_override("font", UI.font(600)); effect_label.add_theme_font_size_override("font_size", roundi(16 * factor))
		effect_label.add_theme_color_override("font_color", M.INK)
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(effect_label)
	if mode == "staff":
		for seat in model.get("seats", []):
			var record: Dictionary = seat
			var button: Button = Button.new(); button.name = "StaffSeat_" + str(record.id)
			var label: String = _seat_name(str(record.id))
			var state: String = str(record.get("member_name", "")) if not str(record.get("member_id", "")).is_empty() else "＋ 候補者へ" if bool(record.installed) else "配送待ち →" if str(record.status) == "queued" else "配置待ち →" if str(record.status) in ["ready", "carried", "placing"] else "未設置 → 設備"
			button.text = label + "\n" + state
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_font_override("font", UI.font(500)); button.add_theme_font_size_override("font_size", roundi(13 * factor))
			M.button(button, "quiet")
			for style_name in ["normal", "hover", "pressed", "disabled"]:
				var style: StyleBoxFlat = button.get_theme_stylebox(style_name).duplicate()
				style.bg_color = Color.TRANSPARENT
				style.content_margin_left = 61 * factor; style.content_margin_right = 3 * factor
				button.add_theme_stylebox_override(style_name, style)
			button.tooltip_text = label + " / " + state + (" / 拡張工事が必要" if bool(record.get("locked", false)) else "")
			button.set_meta("equipment_seat", record.duplicate(true))
			button.pressed.connect(func():
				if seat_action.is_valid(): seat_action.call(record.duplicate(true))
			)
			add_child(button); seat_buttons.append(button)
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout.call_deferred()

func _layout() -> void:
	if size.x <= 0: return
	var width: float = size.x / factor
	if view_mode == "staff":
		var cell: float = (width - 16) / 3.0
		for index in seat_buttons.size():
			seat_buttons[index].position = Vector2(8 + index * cell, 30) * factor
			seat_buttons[index].size = Vector2(cell - 4, 73) * factor
	elif is_instance_valid(effect_label):
		var x: float = minf(148, width * .25) + 8
		effect_label.position = Vector2(x, 50) * factor
		effect_label.size = Vector2(maxf(1, width - x - 8), 78) * factor
	queue_redraw()

func _shows_effect() -> bool:
	return str(model.get("id", "")) in ["backup", "plant", "workstation", "diagnostic"]

func _draw() -> void:
	if model.is_empty() or size.x <= 0: return
	draw_set_transform(Vector2.ZERO, 0, Vector2(factor, factor))
	var width: float = size.x / factor
	if view_mode == "staff": _draw_seats(width)
	else: _draw_equipment(width)

func _draw_equipment(width: float) -> void:
	var id: String = str(model.get("id", ""))
	var installed: bool = bool(model.get("installed", false))
	var status: String = str(model.get("status", ""))
	var split: float = minf(148, width * .25)
	var art: Texture2D = ART.icon(id)
	if art != null:
		var area: Rect2 = Rect2(3, 35, split - 13, 88 if _shows_effect() else 114)
		var ratio: float = minf(area.size.x / art.get_width(), area.size.y / art.get_height())
		var drawn: Vector2 = Vector2(art.get_width(), art.get_height()) * ratio
		draw_texture_rect(art, Rect2(area.get_center() - drawn * .5, drawn), false)
	var stage: int = 3 if installed else 2 if status in ["carried", "placing"] else 1 if status in ["queued", "ready"] else 0
	var stage_text: String = "✓ 稼働中" if installed else "○ 配置待ち" if stage == 2 else "□ 受取待ち" if status == "ready" else "□ 配送待ち" if stage == 1 else "未購入"
	_text(Vector2(5, 18), stage_text, 14, M.ACCENT if installed else M.INK)
	_text(Vector2(5, 143 if _shows_effect() else 173), "設置で有効" if not installed else "設置済み", 12, M.MUTED)
	var x: float = split + 8
	var content_width: float = width - x - 5
	var steps: Array[String] = ["発注", "受取", "設置"]
	var step_width: float = content_width / 3.0
	for index in range(3):
		var center: Vector2 = Vector2(x + index * step_width + 7, 11)
		if index < 2: draw_line(center + Vector2(10, 0), center + Vector2(step_width - 10, 0), M.LINE, 2)
		draw_circle(center, 6, M.ACCENT if stage > index else M.PAPER)
		draw_arc(center, 6, 0, TAU, 20, M.ACCENT if stage > index else M.MUTED, 1)
		_text(center + Vector2(12, 5), ("✓ " if stage > index else "") + steps[index], 12, M.INK)
	if _shows_effect():
		_text(Vector2(x, 39), "✓ 有効な効果" if installed else "設置後の効果", 12, M.ACCENT if installed else M.MUTED)
		return
	_text(Vector2(x, 38), "稼働枠 · 使用 / 上限", 12, M.MUTED)
	var has_gain: bool = false
	for raw in model.get("capacities", []):
		if int(raw.get("gain", 0)) > 0: has_gain = true
	if has_gain: _text(Vector2(width - 100, 38), "┄ 設置後", 12, M.ACCENT)
	var index: int = 0
	for raw in model.get("capacities", []):
		var row: Dictionary = raw
		var y: float = 57 + index * 43
		var current: int = int(row.capacity); var used: int = int(row.used); var gain: int = int(row.gain)
		_text(Vector2(x, y + 2), str(row.label), 13, M.INK)
		_text(Vector2(x + 90, y + 2), "%d / %d" % [used, current], 14, M.INK)
		if gain > 0: _text(Vector2(width - 99, y + 2), "→ %d / %d" % [used, current + gain], 14, M.ACCENT)
		var slots: int = mini(current + gain, 12)
		var slot_step: float = minf(28, (content_width - 4) / maxf(1, slots))
		for slot in range(slots):
			var box: Rect2 = Rect2(x + slot * slot_step, y + 9, minf(22, slot_step - 3), 15)
			var future: bool = slot >= current
			_slot(box, str(row.id), slot < used, future)
		if current + gain == 0: _text(Vector2(x, y + 23), "—", 13, M.MUTED)
		if current + gain > 12: _text(Vector2(x + slots * slot_step + 3, y + 23), "+%d" % (current + gain - 12), 12, M.MUTED)
		index += 1
	if not str(model.get("blocked", "")).is_empty(): _text(Vector2(x, 192), "※ 部屋の拡張後に購入・設置", 12, M.WARNING)

func _draw_seats(width: float) -> void:
	var installed_count: int = 0
	var occupied_count: int = 0
	for seat in model.get("seats", []):
		if bool(seat.get("installed", false)): installed_count += 1
		if not str(seat.get("member_id", "")).is_empty(): occupied_count += 1
	_text(Vector2(8, 18), "追加採用席  %d / %d" % [occupied_count, installed_count], 14, M.INK)
	_text(Vector2(width - 144, 18), "常設の2席は別枠", 12, M.MUTED)
	var cell: float = (width - 16) / 3.0
	for index in mini(3, model.get("seats", []).size()):
		var seat: Dictionary = model.seats[index]
		var x: float = 8 + index * cell
		var installed: bool = bool(seat.get("installed", false))
		var occupied: bool = not str(seat.get("member_id", "")).is_empty()
		var color: Color = M.ACCENT if installed else M.MUTED
		var desk: Rect2 = Rect2(x + 9, 59, 42, 9)
		if installed: draw_rect(desk, color, false, 2)
		else: _dashed_rect(desk, color)
		draw_line(Vector2(x + 13, 69), Vector2(x + 13, 83), color, 2)
		draw_line(Vector2(x + 47, 69), Vector2(x + 47, 83), color, 2)
		if occupied:
			draw_circle(Vector2(x + 30, 42), 7, M.ACCENT)
			draw_arc(Vector2(x + 30, 59), 13, PI, TAU, 18, M.ACCENT, 4)
		else:
			_slot(Rect2(x + 21, 39, 18, 15), "staff", false, not installed)
		_text(Vector2(x + 12, 100), "✓" if installed else "┄", 13, color)

func _slot(rect: Rect2, kind: String, occupied: bool, future: bool) -> void:
	var color: Color = M.ACCENT if future or occupied else M.MUTED
	if occupied: draw_rect(rect, M.SELECTED)
	if future: _dashed_rect(rect, color)
	else: draw_rect(rect, color, false, 1)
	if kind == "staff":
		draw_line(rect.position + Vector2(2, rect.size.y + 2), rect.end + Vector2(-2, 2), color, 1)
	elif kind == "contracts":
		draw_line(rect.position + Vector2(3, 5), rect.end - Vector2(3, rect.size.y - 5), color, 1)
	else:
		draw_circle(rect.get_center(), 2, color)
	if occupied: _text(rect.position + Vector2(4, 12), "✓", 10, color)

func _dashed_rect(rect: Rect2, color: Color) -> void:
	for points in [[rect.position, Vector2(rect.end.x, rect.position.y)], [Vector2(rect.end.x, rect.position.y), rect.end], [rect.end, Vector2(rect.position.x, rect.end.y)], [Vector2(rect.position.x, rect.end.y), rect.position]]:
		draw_dashed_line(points[0], points[1], color, 1, 3)

func _text(at: Vector2, value: String, points: int, color: Color) -> void:
	draw_string(UI.font(500), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, points, color)

static func _seat_name(id: String) -> String:
	return str({"teamdesk":"チーム席", "annexdesk_a":"増設 A", "annexdesk_b":"増設 B"}.get(id, id))
