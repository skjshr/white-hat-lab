extends RefCounted
## Customer front desk. Drawing and room selection never submit a folio.
const UI = preload("res://scripts/ui_theme.gd")
const PAPER := Color("fffdf6")
const CANVAS := Color("f1eee5")
const TEAL := Color("214f50")
const INK := Color("293d3a")
const MUTED := Color("666c61")
const LINE := Color("c7c8b8")
const SELECTED := Color("e0e9dd")
const RED := Color("a63e32")
const GREEN := Color("276751")

class ReceiptPaper extends PanelContainer:
	var factor := 1.0
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var width := maxf(0.0, size.x - 3 * factor)
		var height := maxf(0.0, size.y - 3 * factor)
		if width < 40 * factor or height < 40 * factor: return
		var fold := 15 * factor
		var edge := 4 * factor
		var points := PackedVector2Array([Vector2.ZERO, Vector2(width - fold, 0), Vector2(width, fold), Vector2(width, height - edge)])
		var teeth := maxi(2, roundi(width / (12 * factor)))
		for index in range(teeth - 1, -1, -1):
			points.append(Vector2(width * (float(index) + 0.5) / teeth, height))
			points.append(Vector2(width * float(index) / teeth, height - edge))
		var shadow := PackedVector2Array()
		for point in points: shadow.append(point + Vector2(3, 3) * factor)
		draw_colored_polygon(shadow, Color("d9d6ca"))
		draw_colored_polygon(points, PAPER)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, LINE, factor, true)
		draw_colored_polygon(PackedVector2Array([Vector2(width - fold, 0), Vector2(width - fold, fold), Vector2(width, fold)]), Color("e5e3d8"))
		draw_polyline(PackedVector2Array([Vector2(width - fold, 0), Vector2(width - fold, fold), Vector2(width, fold)]), LINE, factor, true)
		# The staple and cut edge belong to the original slip in every state.
		draw_line(Vector2(13, 8) * factor, Vector2(27, 8) * factor, Color("9d9f96"), 2 * factor)
		draw_line(Vector2(13, 7) * factor, Vector2(27, 7) * factor, Color("dedfd8"), factor)

class ResultSeal extends PanelContainer:
	var factor := 1.0
	var ink := MUTED
	var attempted := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var frame := Rect2(Vector2.ONE * factor, size - Vector2.ONE * 2 * factor)
		if frame.size.x <= 0 or frame.size.y <= 0: return
		if attempted:
			draw_rect(frame, ink, false, 1.6 * factor)
			draw_rect(frame.grow(-4 * factor), ink, false, 0.7 * factor)
		else:
			# An empty processing field is visibly different from a response stamp.
			var dash := 6 * factor
			var offset := 0.0
			while offset < frame.size.x:
				var end := minf(offset + dash, frame.size.x)
				draw_line(frame.position + Vector2(offset, 0), frame.position + Vector2(end, 0), LINE, factor)
				draw_line(Vector2(frame.position.x + offset, frame.end.y), Vector2(frame.position.x + end, frame.end.y), LINE, factor)
				offset += dash * 2
			draw_line(frame.position, Vector2(frame.position.x, frame.end.y), LINE, factor)
			draw_line(Vector2(frame.end.x, frame.position.y), frame.end, LINE, factor)

class Door extends Control:
	var factor := 1.0
	var departure := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var x := 3.0 * factor
		var top := 4.0 * factor
		var width := 34.0 * factor
		var height := 55.0 * factor
		draw_rect(Rect2(x, top, width, height), Color("dce2d5"))
		draw_rect(Rect2(x, top, width, height), TEAL, false, factor)
		draw_line(Vector2(x - 3 * factor, top + height), Vector2(x + width + 4 * factor, top + height), TEAL, factor)
		draw_rect(Rect2(x + 8 * factor, top + 9 * factor, 18 * factor, 10 * factor), PAPER)
		draw_circle(Vector2(x + 27 * factor, top + 33 * factor), 2 * factor, TEAL)
		if departure:
			var bag := Rect2(24 * factor, 43 * factor, 20 * factor, 20 * factor)
			draw_rect(bag, PAPER)
			draw_rect(bag, TEAL, false, factor)
			draw_rect(Rect2(29 * factor, 38 * factor, 10 * factor, 5 * factor), TEAL, false, factor)
			draw_line(Vector2(29, 53) * factor, Vector2(39, 53) * factor, TEAL, factor)
			draw_line(Vector2(35, 49) * factor, Vector2(39, 53) * factor, TEAL, factor)
			draw_line(Vector2(35, 57) * factor, Vector2(39, 53) * factor, TEAL, factor)

class Route extends Control:
	var factor := 1.0
	var blocked := false
	var disconnected := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var y := size.y * 0.5
		var mid := size.x * 0.5
		var gap := 8 * factor if blocked or disconnected else 0.0
		var color := RED if blocked else MUTED
		draw_line(Vector2(0, y), Vector2(maxf(0, mid - gap), y), color, factor)
		draw_line(Vector2(minf(size.x, mid + gap), y), Vector2(size.x, y), color, factor)
		if blocked:
			draw_line(Vector2(mid - 5 * factor, y - 5 * factor), Vector2(mid + 5 * factor, y + 5 * factor), color, 2 * factor)
			draw_line(Vector2(mid - 5 * factor, y + 5 * factor), Vector2(mid + 5 * factor, y - 5 * factor), color, 2 * factor)
		elif disconnected:
			draw_circle(Vector2(mid, y), 4 * factor, CANVAS)
			draw_arc(Vector2(mid, y), 4 * factor, 0, TAU, 20, MUTED, factor)
		else:
			draw_line(Vector2(size.x - 5 * factor, y - 4 * factor), Vector2(size.x, y), color, factor)
			draw_line(Vector2(size.x - 5 * factor, y + 4 * factor), Vector2(size.x, y), color, factor)

static func _scale(d) -> float:
	return float(d.game.settings.get("text_scale", 1.0))

static func _label(d, parent: Node, value: String, points: int = 14, color: Color = INK, weight: int = 400) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI.font(weight))
	label.add_theme_font_size_override("font_size", roundi(points * _scale(d)))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

static func _button(d, parent: Node, text: String, id: String, action: Callable, primary: bool = false) -> Button:
	var value := Button.new()
	value.name = id
	value.text = text
	value.custom_minimum_size.y = 38 * _scale(d)
	value.add_theme_font_override("font", UI.font(500))
	value.add_theme_font_size_override("font_size", roundi(14 * _scale(d)))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		value.add_theme_color_override(key, PAPER if primary else TEAL)
	value.add_theme_color_override("font_disabled_color", MUTED)
	value.add_theme_stylebox_override("normal", UI.style(TEAL if primary else PAPER, TEAL if primary else LINE, 12, 8, 1))
	value.add_theme_stylebox_override("hover", UI.style(Color("326665") if primary else SELECTED, TEAL, 12, 8, 1))
	value.add_theme_stylebox_override("pressed", UI.style(Color("193c3c") if primary else Color("d2dfce"), TEAL, 12, 8, 1))
	value.add_theme_stylebox_override("disabled", UI.style(CANVAS, LINE, 12, 8, 1))
	var focus := UI.style(Color.TRANSPARENT, Color("b07824"), 12, 8, 1)
	focus.set_border_width_all(3)
	value.add_theme_stylebox_override("focus", focus)
	value.pressed.connect(action)
	parent.add_child(value)
	return value

static func _rule(parent: Node) -> void:
	var line := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = LINE
	style.thickness = 1
	line.add_theme_stylebox_override("separator", style)
	parent.add_child(line)

static func _money(value: int) -> String:
	var digits := str(absi(value))
	var formatted := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0: formatted += ","
		formatted += digits[index]
	return ("−¥" if value < 0 else "¥") + formatted

static func _room_id(room: Dictionary) -> String:
	return str(room.get("room", ""))

static func _selected(d, rooms: Array, folios: Array) -> String:
	var selected := str(d.business_ui.get("hotel_selected_room", ""))
	for room in rooms:
		if _room_id(room) == selected: return selected
	for folio in folios:
		if str(folio.get("status", "")) == "pending": return str(folio.get("room", ""))
	if not folios.is_empty(): return str(folios[0].get("room", ""))
	return _room_id(rooms[0]) if not rooms.is_empty() else ""

static func _select_room(d, room: String) -> void:
	d.business_ui["hotel_selected_room"] = room
	d._save_session(false)
	d._render_hotel_frontdesk()

static func _send(d, folio_id: String) -> void:
	var result: Dictionary = d._hotel_action(folio_id)
	# A failed save may roll the durable attempt back. Retain its real response
	# in the UI until the next explicit submission, not as a hotel transaction.
	d.business_ui["hotel_action_feedback"] = {"folio_id":folio_id, "result":result}
	d._render_hotel_frontdesk()

static func _attempt(d, snap: Dictionary, folio_id: String) -> Dictionary:
	var feedback: Dictionary = d.business_ui.get("hotel_action_feedback", {})
	if str(feedback.get("folio_id", "")) == folio_id:
		return feedback.get("result", {})
	var last: Dictionary = snap.get("last_attempt", {})
	return last if str(last.get("folio_id", "")) == folio_id else {}

static func _error_text(code: int, error: String) -> String:
	if code == 403: return "× 送信拒否 · HTTP 403"
	if code == 503: return "○ 接続できません · HTTP 503"
	if code == 507: return "× 保存できません · HTTP 507"
	if code == 409: return "× 受付できません · HTTP 409"
	if code == 422: return "× 精算データを読み取れません · HTTP 422"
	return "× 送信未完了 · HTTP %d" % code if code > 0 else "× " + error

static func _room_button(d, parent: Node, room: Dictionary, selected: String) -> void:
	var factor := _scale(d)
	var id := _room_id(room)
	var departure := str(room.get("status", "")) == "departure"
	var value := _button(d, parent, "", "HotelRoom_" + id, func(): _select_room(d, id))
	value.custom_minimum_size = Vector2(142, 98) * factor
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.tooltip_text = "%s号室 · %s · %s" % [id, str(room.get("guest", "")), "出発予定" if departure else "在室"]
	var normal := UI.style(SELECTED if id == selected else PAPER, TEAL if id == selected else LINE, 10, 8, 1)
	if id == selected: normal.border_width_left = 4
	value.add_theme_stylebox_override("normal", normal)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, roundi(10 * factor))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(8 * factor))
	margin.add_child(row)
	var door := Door.new()
	door.factor = factor
	door.departure = departure
	door.custom_minimum_size = Vector2(46, 66) * factor
	row.add_child(door)
	var details := VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 1)
	row.add_child(details)
	_label(d, details, id + (" ‹" if id == selected else ""), 24, TEAL, 600)
	_label(d, details, str(room.get("guest", "")), 12)
	_label(d, details, "↗ 出発予定" if departure else "● 在室", 11, MUTED)

static func _rack(d, parent: Node, rooms: Array, selected: String) -> VBoxContainer:
	var rack := VBoxContainer.new()
	rack.name = "HotelRoomRack"
	rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.size_flags_stretch_ratio = 0.95
	rack.add_theme_constant_override("separation", roundi(10 * _scale(d)))
	parent.add_child(rack)
	_label(d, rack, "客室ラック  /  2F", 15, TEAL, 600)
	var grid := GridContainer.new()
	grid.name = "HotelRoomGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", roundi(8 * _scale(d)))
	grid.add_theme_constant_override("v_separation", roundi(8 * _scale(d)))
	rack.add_child(grid)
	for room in rooms: _room_button(d, grid, room, selected)
	_rule(rack)
	_label(d, rack, "予約台帳: PC-A / 引継ぎ対象", 12, MUTED)
	return rack

static func _route(d, parent: Node, snap: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(10 * _scale(d)))
	parent.add_child(row)
	var left := _label(d, row, "PC-B", 13, TEAL, 600)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.autowrap_mode = TextServer.AUTOWRAP_OFF
	var route := Route.new()
	route.factor = _scale(d)
	route.blocked = bool(snap.get("isolated", false))
	route.disconnected = not bool(snap.get("connected", false))
	route.custom_minimum_size = Vector2(50, 24) * _scale(d)
	route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(route)
	var right := _label(d, row, "精算受付", 13, TEAL, 600)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.autowrap_mode = TextServer.AUTOWRAP_OFF
	var state := "現在: 接続中 / 隔離なし"
	if not bool(snap.get("connected", false)): state = "現在: 顧客環境に未接続"
	elif bool(snap.get("isolated", false)): state = "現在: PC-Bに隔離を適用中"
	_label(d, parent, state, 12, RED if bool(snap.get("isolated", false)) else MUTED).name = "HotelCurrentConnection"

static func _receipt(d, parent: Node, snap: Dictionary, room: Dictionary, folio: Dictionary, archive: bool = false) -> PanelContainer:
	var factor := _scale(d)
	var sheet := ReceiptPaper.new()
	sheet.factor = factor
	sheet.name = "HotelFolioPaper"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_stretch_ratio = 1.05
	sheet.add_theme_stylebox_override("panel", UI.style(Color.TRANSPARENT, Color.TRANSPARENT, roundi(18 * factor), roundi(19 * factor), 0))
	parent.add_child(sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", roundi(7 * factor))
	sheet.add_child(body)
	if folio.is_empty():
		_label(d, body, "%s号室" % _room_id(room), 24, TEAL, 600)
		_label(d, body, str(room.get("guest", "")), 14)
		_rule(body)
		_label(d, body, "在室 / 当日の精算票なし", 15, MUTED)
		_button(d, body, "PC-BをEDRで確認", "HotelOpenEndpoint", func(): d._open_endpoint_device("pc_b"))
		return sheet
	var folio_id := str(folio.get("id", ""))
	var received := str(folio.get("status", "")) == "received"
	_label(d, body, "精算票  " + folio_id, 20, TEAL, 600).name = "HotelFolioTitle"
	_label(d, body, "%s号室   %s" % [str(folio.get("room", "")), str(folio.get("guest", ""))], 13)
	_rule(body)
	for item in folio.get("lines", []):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", roundi(14 * factor))
		body.add_child(line)
		_label(d, line, str(item.get("label", "")), 14)
		var amount := _label(d, line, _money(int(item.get("amount", 0))), 14)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	_rule(body)
	var total := HBoxContainer.new()
	body.add_child(total)
	_label(d, total, "合計", 14)
	var price := _label(d, total, _money(int(folio.get("total", 0))), 24, TEAL, 600)
	price.name = "HotelFolioTotal"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.autowrap_mode = TextServer.AUTOWRAP_OFF
	var attempt := _attempt(d, snap, folio_id)
	var code := int(attempt.get("code", 0))
	var receipt: Dictionary = folio.get("receipt", {})
	var stamp_text := "未送信"
	var stamp_color := MUTED
	if received:
		stamp_text = "✓ 受領済\n" + str(receipt.get("number", ""))
		stamp_color = GREEN
	elif not attempt.is_empty():
		stamp_text = _error_text(code, str(attempt.get("error", "送信未完了"))).replace(" · ", "\n")
		stamp_color = RED
	var result_row := HBoxContainer.new()
	result_row.add_theme_constant_override("separation", roundi(16 * factor))
	body.add_child(result_row)
	var balance := _label(d, result_row, "残高 " + _money(int(folio.get("balance", folio.get("total", 0)))), 14, TEAL, 500)
	balance.name = "HotelFolioBalance"
	balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var seal := ResultSeal.new()
	seal.name = "HotelFolioSeal"
	seal.factor = factor
	seal.ink = stamp_color
	seal.attempted = received or not attempt.is_empty()
	seal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seal.add_theme_stylebox_override("panel", UI.style(Color.TRANSPARENT, Color.TRANSPARENT, roundi(12 * factor), roundi(8 * factor), 0))
	result_row.add_child(seal)
	var stamp := _label(d, seal, stamp_text, 14, stamp_color, 600)
	stamp.name = "HotelFolioStamp"
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not received and not attempt.is_empty(): _label(d, body, "前回の送信結果 / 精算票は保持しています", 11, MUTED)
	if archive: return sheet
	_rule(body)
	_route(d, body, snap)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", roundi(8 * factor))
	actions.add_theme_constant_override("v_separation", roundi(7 * factor))
	body.add_child(actions)
	var submit := _button(d, actions, "✓ 受領済" if received else ("同じ票を再送" if not attempt.is_empty() else "送信して確認"), "HotelSubmitFolio", func(): _send(d, folio_id), true)
	submit.disabled = received or not bool(snap.get("can_send", false))
	_button(d, actions, "PC-BをEDRで確認", "HotelOpenEndpoint", func(): d._open_endpoint_device("pc_b"))
	return sheet

static func _layout(d, root: Control, split: BoxContainer, rack: Control, sheet: Control) -> void:
	if not is_instance_valid(root) or not is_instance_valid(split): return
	var narrow := root.size.x / _scale(d) < 760
	split.vertical = narrow
	# The pending slip and its send/retry action stay first on small screens.
	split.move_child(sheet, 0 if narrow else 1)
	var grid := rack.find_child("HotelRoomGrid", true, false) as GridContainer
	if grid != null: grid.columns = 1 if rack.size.x / _scale(d) < 292 else 2

static func _select_tab(d, tab: String) -> void:
	d.business_ui["hotel_tab"] = tab
	d._save_session(false)
	d._render_hotel_frontdesk()

static func _reservation_attempt(d, reservation: Dictionary) -> Dictionary:
	var id := str(reservation.get("id", ""))
	var feedback: Dictionary = d.business_ui.get("hotel_action_feedback", {})
	if str(feedback.get("folio_id", "")) == id: return feedback.get("result", {})
	var last: Dictionary = reservation.get("last_attempt", {})
	return last if str(last.get("id", "")) == id else {}

static func _reservation_error(code: int) -> String:
	match code:
		403: return "× 取込拒否\nHTTP 403"
		503: return "× 取込先を利用できません\nHTTP 503"
		507: return "× 保存できません\nHTTP 507"
		422: return "× 予約データを読み取れません\nHTTP 422"
		409: return "× 取り込めません\nHTTP 409"
	return "× 取込未完了" + ("\nHTTP %d" % code if code > 0 else "")

static func _show_reservation_ticket(d) -> void:
	var ticket: Control = d.widgets.browser.page.find_child("HotelReservationTicket", true, false)
	if ticket == null: return
	var scroll: Node = ticket.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll is ScrollContainer: scroll.ensure_control_visible(ticket)

static func _calendar(d, parent: Node, snap: Dictionary, reservation: Dictionary) -> VBoxContainer:
	var factor := _scale(d)
	var calendar := VBoxContainer.new()
	calendar.name = "HotelReservationCalendar"
	calendar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calendar.size_flags_stretch_ratio = 1.2
	calendar.add_theme_constant_override("separation", roundi(10 * factor))
	parent.add_child(calendar)
	_label(d, calendar, "2F / 予約台帳", 15, TEAL, 600)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calendar.add_child(grid)
	var arrival := int(reservation.get("arrival_day", 0))
	var nights := maxi(1, int(reservation.get("nights", 1)))
	var days := [arrival - 1, arrival, arrival + nights]
	for heading in ["客室", "営業日 %d" % days[0], "営業日 %d" % days[1], "営業日 %d" % days[2]]:
		var cell := _calendar_cell(d, grid, true)
		var text := _label(d, cell, heading, 11, PAPER, 500)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for room in snap.get("rooms", []):
		var room_id := _room_id(room)
		var number := _calendar_cell(d, grid)
		number.custom_minimum_size.x = 44 * factor
		var room_label := _label(d, number, room_id, 15, TEAL, 600)
		room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		for day in days:
			var occupied := str(reservation.get("status", "")) == "imported" and room_id == str(reservation.get("room", "")) and int(day) == arrival
			if occupied:
				var booking := _button(d, grid, "", "HotelReservationCell_" + room_id, func(): _show_reservation_ticket(d))
				booking.custom_minimum_size = Vector2(78, 58) * factor
				booking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				booking.tooltip_text = "%s · %s" % [str(reservation.get("id", "")), str(reservation.get("bookingno", ""))]
				var selected := UI.style(SELECTED, TEAL, 6, 6, 0)
				selected.border_width_left = 4
				booking.add_theme_stylebox_override("normal", selected)
				var inset := MarginContainer.new()
				inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
				booking.add_child(inset)
				inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				for side in ["left", "right", "top", "bottom"]: inset.add_theme_constant_override("margin_" + side, roundi(6 * factor))
				var booked := _label(d, inset, "%s\n✓ %d泊 →" % [str(reservation.get("guest", "")), nights], 12, TEAL, 500)
				booked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				booked.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			else:
				var cell := _calendar_cell(d, grid)
				cell.custom_minimum_size = Vector2(78, 58) * factor
				var empty := _label(d, cell, "—", 13, LINE)
				empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return calendar

static func _calendar_cell(d, parent: Node, heading: bool = false) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", UI.style(TEAL if heading else PAPER, LINE, roundi(6 * _scale(d)), roundi(8 * _scale(d)), 0))
	parent.add_child(cell)
	return cell

static func _reservation_route(d, parent: Node, reservation: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(10 * _scale(d)))
	parent.add_child(row)
	var left := _label(d, row, "PC-A", 13, TEAL, 600)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.autowrap_mode = TextServer.AUTOWRAP_OFF
	var route := Route.new()
	route.factor = _scale(d)
	route.blocked = bool(reservation.get("isolated", false))
	route.disconnected = not bool(reservation.get("connected", false)) or not bool(reservation.get("business_available", false))
	route.custom_minimum_size = Vector2(50, 24) * _scale(d)
	route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(route)
	var right := _label(d, row, "予約台帳", 13, TEAL, 600)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.autowrap_mode = TextServer.AUTOWRAP_OFF
	var state := "現在: PC-A接続中 / 業務ファイル利用可"
	if not bool(reservation.get("connected", false)): state = "現在: 顧客環境に未接続"
	elif bool(reservation.get("isolated", false)): state = "現在: PC-Aに隔離を適用中"
	elif not bool(reservation.get("business_available", false)): state = "現在: 業務ファイルを利用できません"
	_label(d, parent, state, 12, RED if route.blocked or route.disconnected else MUTED).name = "HotelReservationCurrentState"

static func _reservation_ticket(d, parent: Node, reservation: Dictionary) -> VBoxContainer:
	var factor := _scale(d)
	var imported := str(reservation.get("status", "")) == "imported"
	var tray := VBoxContainer.new()
	tray.name = "HotelReservationTray"
	tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray.size_flags_stretch_ratio = 1.0
	tray.add_theme_constant_override("separation", roundi(10 * factor))
	parent.add_child(tray)
	_label(d, tray, "受信トレイ · %d件" % (0 if imported else 1), 15, TEAL, 600).name = "HotelReservationInboxCount"
	var sheet := ReceiptPaper.new()
	sheet.name = "HotelReservationTicket"
	sheet.factor = factor
	sheet.add_theme_stylebox_override("panel", UI.style(Color.TRANSPARENT, Color.TRANSPARENT, roundi(18 * factor), roundi(19 * factor), 0))
	tray.add_child(sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", roundi(8 * factor))
	sheet.add_child(body)
	_label(d, body, "同期控え" if imported else "未同期の予約票", 18, TEAL, 600)
	_label(d, body, str(reservation.get("id", "")), 12, MUTED).name = "HotelReservationId"
	_rule(body)
	_label(d, body, "%s号室   %s" % [str(reservation.get("room", "")), str(reservation.get("guest", ""))], 19, TEAL, 600)
	var arrival := int(reservation.get("arrival_day", 0))
	var nights := int(reservation.get("nights", 1))
	_label(d, body, "営業日 %d → %d  /  %d泊" % [arrival, arrival + nights, nights], 14)
	var attempt := _reservation_attempt(d, reservation)
	var stamp_text := "未同期"
	var stamp_color := MUTED
	if imported:
		stamp_text = "✓ 同期済み\n" + str(reservation.get("bookingno", ""))
		stamp_color = GREEN
	elif not attempt.is_empty():
		stamp_text = _reservation_error(int(attempt.get("code", 0)))
		stamp_color = RED
	var seal := ResultSeal.new()
	seal.factor = factor
	seal.ink = stamp_color
	seal.attempted = imported or not attempt.is_empty()
	seal.add_theme_stylebox_override("panel", UI.style(Color.TRANSPARENT, Color.TRANSPARENT, roundi(12 * factor), roundi(8 * factor), 0))
	body.add_child(seal)
	var stamp := _label(d, seal, stamp_text, 14, stamp_color, 600)
	stamp.name = "HotelReservationStamp"
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not imported and not attempt.is_empty(): _label(d, body, "前回の取込結果 / 予約票を保持", 11, MUTED)
	_rule(body)
	_reservation_route(d, body, reservation)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", roundi(8 * factor))
	actions.add_theme_constant_override("v_separation", roundi(7 * factor))
	body.add_child(actions)
	var submit := _button(d, actions, "✓ 同期済み" if imported else ("同じ予約を再試行" if not attempt.is_empty() else "予約を取り込む"), "HotelImportReservation", func(): _send(d, str(reservation.get("id", ""))), true)
	submit.disabled = imported or not bool(reservation.get("can_send", false))
	_button(d, actions, "PC-AをEDRで確認", "HotelOpenEndpoint", func(): d._open_endpoint_device("pc_a"))
	return tray

static func _reservation_layout(d, root: Control, split: BoxContainer, tray: Control) -> void:
	if not is_instance_valid(root) or not is_instance_valid(split): return
	var narrow := root.size.x / _scale(d) < 850
	split.vertical = narrow
	split.move_child(tray, 0 if narrow else 1)

static func _recovery_view(d, body: Node, root: Control, snap: Dictionary) -> void:
	var tab := str(d.business_ui.get("hotel_tab", "reservations"))
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", roundi(8 * _scale(d)))
	tabs.add_theme_constant_override("v_separation", roundi(6 * _scale(d)))
	body.add_child(tabs)
	_button(d, tabs, "予約台帳", "HotelTabReservations", func(): _select_tab(d, "reservations"), tab != "folios")
	_button(d, tabs, "精算控え", "HotelTabFolios", func(): _select_tab(d, "folios"), tab == "folios")
	if tab == "folios":
		var folio: Dictionary = {}
		var room: Dictionary = {}
		for entry in snap.get("folios", []):
			if str(entry.get("id", "")) == "F-204": folio = entry
		for entry in snap.get("rooms", []):
			if _room_id(entry) == str(folio.get("room", "")): room = entry
		if folio.is_empty(): _label(d, body, "精算控えを読み取れません", 15, RED)
		else: _receipt(d, body, snap, room, folio, true)
		return
	var reservation: Dictionary = snap.get("reservation", {})
	if not bool(reservation.get("enabled", false)) or str(reservation.get("id", "")).is_empty() or not str(reservation.get("error", "")).is_empty():
		_label(d, body, "× 予約データを読み取れません", 17, RED, 600)
		_button(d, body, "PC-AをEDRで確認", "HotelOpenEndpoint", func(): d._open_endpoint_device("pc_a"))
		return
	var split := BoxContainer.new()
	split.name = "HotelReservationSplit"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", roundi(22 * _scale(d)))
	body.add_child(split)
	_calendar(d, split, snap, reservation)
	var tray := _reservation_ticket(d, split, reservation)
	root.resized.connect(func(): _reservation_layout(d, root, split, tray))
	_reservation_layout.call_deferred(d, root, split, tray)

static func render(d, page: Node) -> void:
	var snap: Dictionary = d.game.hotel_snapshot()
	var factor := _scale(d)
	var root := PanelContainer.new()
	root.name = "HotelFrontdesk"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_stylebox_override("panel", UI.style(CANVAS, Color.TRANSPARENT, roundi(20 * factor), roundi(16 * factor), 0))
	page.add_child(root)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", roundi(12 * factor))
	root.add_child(body)
	_label(d, body, "SHIRANAMI / FRONT DESK", 11, TEAL, 600)
	_label(d, body, "白波フロント", 25, TEAL, 600)
	_rule(body)
	if not bool(snap.get("enabled", false)):
		_label(d, body, "この案件にはフロント端末の接続先がありません。", 14, MUTED)
		_button(d, body, "EDRへ戻る", "HotelOpenEndpoint", func(): d._open_endpoint_device("pc_b"))
		return
	if int(snap.get("workflow_version", 1)) == 2:
		_recovery_view(d, body, root, snap)
		return
	var rooms: Array = snap.get("rooms", [])
	var folios: Array = snap.get("folios", [])
	if str(snap.get("error", "")) == "data_unavailable" or rooms.is_empty():
		_label(d, body, "× 客室・精算データを読み取れません", 17, RED, 600)
		_route(d, body, snap)
		_button(d, body, "PC-BをEDRで確認", "HotelOpenEndpoint", func(): d._open_endpoint_device("pc_b"))
		return
	var selected := _selected(d, rooms, folios)
	var selected_room: Dictionary = {}
	var selected_folio: Dictionary = {}
	for room in rooms:
		if _room_id(room) == selected: selected_room = room
	for folio in folios:
		if str(folio.get("room", "")) == selected: selected_folio = folio
	var split := BoxContainer.new()
	split.name = "HotelFrontdeskSplit"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", roundi(22 * factor))
	body.add_child(split)
	var rack := _rack(d, split, rooms, selected)
	var sheet := _receipt(d, split, snap, selected_room, selected_folio)
	root.resized.connect(func(): _layout(d, root, split, rack, sheet))
	rack.resized.connect(func(): _layout(d, root, split, rack, sheet))
	_layout.call_deferred(d, root, split, rack, sheet)
