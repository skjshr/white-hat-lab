extends Control
## Pure rendering of the supplied daily ledger; no settlement or account access.
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
const TEAL = Color("247c72")
const AMBER = Color("a46c26")
const CASH_FILL = Color("e5efea")
var ledger: Dictionary = {}
var factor: float = 1.0
var preview: bool = true
var complete: bool = false
var values: Dictionary = {}
var narrow: bool = false
var cash_height: float = 132.0
var profit_y: float = 140.0
var pending_y: float = 236.0

func configure(data: Dictionary, scale: float, settled: bool) -> void:
	name = "CloseoutSummary"; ledger = data.duplicate(true); factor = maxf(.5, scale)
	preview = bool(ledger.get("preview", not settled)); complete = bool(ledger.get("cash_flow_complete", false))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children(): remove_child(child); child.queue_free()
	values.clear()
	values.open = _label("CloseoutCashOpen", _money(int(ledger.get("cash_open", 0))) if complete else _money(int(ledger.get("cash_current", ledger.get("cash_after", 0)))), 21, M.INK)
	values.after = _label("CloseoutCashAfter", _money(int(ledger.get("cash_after", 0))), 23, M.INK)
	values.change = _label("CloseoutCashChange", "増減 " + _signed(int(ledger.get("cash_change", 0))), 14, AMBER if int(ledger.get("cash_change", 0)) < 0 else TEAL)
	values.change.visible = complete
	values.profit = _label("CloseoutProfit", _money(int(ledger.get("total_profit", 0))), 22, M.INK)
	values.legend = _label("CloseoutProfitLegend", "", 12, M.MUTED)
	values.legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var names: Array[String] = []
	for component in _profit_parts():
		if int(component.amount) != 0: names.append(str(component.label) + " " + _signed(int(component.amount)))
	values.legend.text = "    ".join(names) if not names.is_empty() else "本日の利益計上なし · ¥0"
	values.legend.tooltip_text = values.legend.text
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout.call_deferred()

func _label(id: String, value: String, points: int, color: Color) -> Label:
	var label: Label = Label.new(); label.name = id; label.text = value
	label.add_theme_font_override("font", UI.font(600 if points >= 20 else 500)); label.add_theme_font_size_override("font_size", roundi(points * factor)); label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label); return label

func _layout() -> void:
	if size.x <= 0 or values.is_empty(): return
	var width: float = size.x / factor
	narrow = width < 550
	cash_height = 197.0 if narrow else 132.0
	profit_y = cash_height + 8.0; pending_y = profit_y + 96.0
	var vault_width: float = minf(190, (width - 52) * .28)
	var end_x: float = width - vault_width - 12
	_place(values.open, Rect2(24, 64, vault_width - 21, 29))
	_place(values.after, Rect2(end_x + 11, 64, vault_width - 22, 29))
	_place(values.change, Rect2(12, cash_height - 23, width - 24, 22)); values.change.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(values.profit, Rect2(width - 206, profit_y + 2, 192, 29)); values.profit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(values.legend, Rect2(14, profit_y + 55, width - 28, 37))
	custom_minimum_size.y = (pending_y + (119 if narrow else 69)) * factor
	queue_redraw()

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position * factor; control.size = rect.size * factor

static func _money(amount: int) -> String:
	var digits: String = str(absi(amount)); var parts: Array[String] = []
	while digits.length() > 3:
		parts.push_front(digits.right(3)); digits = digits.left(digits.length() - 3)
	parts.push_front(digits)
	return ("−" if amount < 0 else "") + "¥" + ",".join(parts)

static func _signed(amount: int) -> String:
	return ("＋" if amount > 0 else "−" if amount < 0 else "") + _money(absi(amount))

func _profit_parts() -> Array[Dictionary]:
	return [
		{"label":"案件純利益","amount":int(ledger.get("contract_net", 0))},
		{"label":"保守純利益","amount":int(ledger.get("care_gross", 0)) - int(ledger.get("care_cost", 0))},
		{"label":"給与","amount":-int(ledger.get("payroll_due", 0))},
		{"label":"採用","amount":-int(ledger.get("hiring_cost", 0))}
	]

func _text(value: String, at: Vector2, points: int = 13, color: Color = M.INK, width: float = -1) -> void:
	draw_string(UI.font(500), at * factor, value, HORIZONTAL_ALIGNMENT_LEFT, width * factor if width >= 0 else -1, roundi(points * factor), color)

func _line(from: Vector2, to: Vector2, color: Color, thickness: float = 1.5) -> void:
	if preview: draw_dashed_line(from * factor, to * factor, color, thickness * factor, 5 * factor)
	else: draw_line(from * factor, to * factor, color, thickness * factor)

func _arrow(from: Vector2, to: Vector2, color: Color, thickness: float = 1.5) -> void:
	_line(from, to, color, thickness)
	var direction: Vector2 = (from - to).normalized()
	var side: Vector2 = direction.orthogonal()
	draw_line(to * factor, (to + direction * 6 + side * 3) * factor, color, factor)
	draw_line(to * factor, (to + direction * 6 - side * 3) * factor, color, factor)

func _vault(rect: Rect2, title: String, estimated: bool) -> void:
	draw_rect(Rect2(rect.position * factor, rect.size * factor), CASH_FILL)
	var edges: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in 4:
		if estimated: draw_dashed_line(edges[index] * factor, edges[(index + 1) % 4] * factor, TEAL, factor, 5 * factor)
		else: draw_line(edges[index] * factor, edges[(index + 1) % 4] * factor, TEAL, factor)
	_text(title, rect.position + Vector2(11, 17), 13, M.INK, rect.size.x - 20)
	var center: Vector2 = rect.position + Vector2(20, rect.size.y - 13)
	draw_circle(center * factor, 6 * factor, TEAL, false, factor)
	for direction in [Vector2(0, -1), Vector2(.86, .5), Vector2(-.86, .5)]: draw_line(center * factor, (center + direction * 5) * factor, TEAL, factor)
	draw_line((rect.position + Vector2(36, rect.size.y - 13)) * factor, (rect.end - Vector2(13, 13)) * factor, M.LINE, factor)

func _draw() -> void:
	if ledger.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO, size), M.PAPER)
	_draw_cash(); _draw_profit(); _draw_pending()

func _draw_cash() -> void:
	var width: float = size.x / factor
	_text("資金の流れ", Vector2(12, 19), 15, M.INK)
	_text("… 精算見込み" if preview else "✓ 精算確定", Vector2(130, 19), 13, AMBER if preview else TEAL, 180)
	var current: String = "現在資金 " + _money(int(ledger.get("cash_current", ledger.get("cash_after", 0)))) if preview else "DAY %d の確定台帳" % int(ledger.get("day", 0))
	if width >= 600: _text(current, Vector2(width - 256, 19), 12, M.MUTED, 244)
	var vault_width: float = minf(190, (width - 52) * .28)
	var end_x: float = width - vault_width - 12
	_vault(Rect2(12, 36, vault_width, 73), "期首資金" if complete else "記録済み資金", false)
	_vault(Rect2(end_x, 36, vault_width, 73), "精算後資金・見込" if preview else "精算後資金・確定", preview)
	var left: float = 12 + vault_width + 12; var right: float = end_x - 12
	if not complete:
		_text("入出金の内訳", Vector2(left, 62), 12, M.MUTED, right - left)
		_text("記録なし", Vector2(left, 81), 13, M.MUTED, right - left)
		_text("旧台帳 · 残高から内訳を推定しません", Vector2(12, cash_height - 5), 12, M.MUTED, width - 24)
		return
	var incoming: int = int(ledger.get("cash_in", 0)); var outgoing: int = int(ledger.get("cash_out", 0))
	var y: float = 128.0 if narrow else 49.0
	var flow_left: float = 18.0 if narrow else left; var flow_right: float = width - 18 if narrow else right
	if narrow: _arrow(Vector2(12 + vault_width, 73), Vector2(end_x - 4, 73), M.LINE)
	else:
		_line(Vector2(left, 64), Vector2(right, 64), M.LINE, 1)
		_arrow(Vector2(12 + vault_width, 72), Vector2(left - 3, 72), M.LINE)
		_arrow(Vector2(right + 2, 72), Vector2(end_x - 3, 72), M.LINE)
	_text("＋ 入金 " + _money(incoming), Vector2(flow_left, y + 1), 14, TEAL, flow_right - flow_left)
	_text("− 出金 " + _money(outgoing), Vector2(flow_left, y + 30), 14, AMBER, flow_right - flow_left)
	var ratio_y: float = y + 41; var total: int = maxi(0, incoming) + maxi(0, outgoing); var bar_width: float = maxf(0, flow_right - flow_left)
	if total > 0:
		var part: float = bar_width * float(maxi(0, incoming)) / total
		draw_rect(Rect2(Vector2(flow_left, ratio_y) * factor, Vector2(part, 5) * factor), TEAL)
		draw_rect(Rect2(Vector2(flow_left + part, ratio_y) * factor, Vector2(bar_width - part, 5) * factor), AMBER)
	else: draw_rect(Rect2(Vector2(flow_left, ratio_y) * factor, Vector2(bar_width, 5) * factor), M.LINE, false, factor)
	# Preview includes outstanding care and payroll, so its whole route is a forecast.
	_line(Vector2(flow_left, ratio_y + 10), Vector2(flow_right, ratio_y + 10), M.LINE, 1)

func _draw_profit() -> void:
	var width: float = size.x / factor
	draw_line(Vector2(12, profit_y - 4) * factor, Vector2(width - 12, profit_y - 4) * factor, M.LINE, factor)
	_text("営業利益", Vector2(12, profit_y + 23), 15, M.INK)
	_text("業績の計上 / 現金とは別", Vector2(122, profit_y + 23), 12, M.MUTED, width - 340)
	var parts: Array[Dictionary] = _profit_parts(); var total: int = 0
	for part in parts: total += absi(int(part.amount))
	var x: float = 14; var bar_width: float = width - 28
	if total == 0: draw_rect(Rect2(Vector2(x, profit_y + 37) * factor, Vector2(bar_width, 9) * factor), M.LINE, false, factor)
	else:
		for part in parts:
			var amount: int = int(part.amount)
			if amount == 0: continue
			var span: float = bar_width * float(absi(amount)) / total
			draw_rect(Rect2(Vector2(x, profit_y + 37) * factor, Vector2(maxf(0, span - 1), 9) * factor), TEAL if amount > 0 else AMBER)
			if amount < 0:
				var tick: float = x + 4
				while tick < x + span - 2:
					draw_line(Vector2(tick, profit_y + 39) * factor, Vector2(tick, profit_y + 44) * factor, M.PAPER, factor); tick += 6
			x += span

func _draw_pending() -> void:
	var width: float = size.x / factor
	draw_line(Vector2(12, pending_y - 4) * factor, Vector2(width - 12, pending_y - 4) * factor, M.LINE, factor)
	_text("現金に未算入の記録", Vector2(12, pending_y + 13), 12, M.MUTED)
	if not narrow: _text("翌朝予定は売掛残高の内数", Vector2(width - 226, pending_y + 13), 11, M.MUTED, 214)
	var specs: Array = [["請求未確定","draft_total"],["売掛残高","receivable_total"],["翌朝入金予定","due_next_day"],["給与未払","arrears"]]
	var columns: int = 2 if narrow else 4; var column: float = (width - 24) / columns
	for index in specs.size():
		var x: float = 12 + (index % columns) * column; var y: float = pending_y + 24 + (index / columns) * 49
		var recorded: bool = ledger.has(str(specs[index][1]))
		var amount: int = int(ledger.get(str(specs[index][1]), 0)); var color: Color = AMBER if recorded and amount > 0 else M.MUTED
		for sheet in 2:
			draw_rect(Rect2(Vector2(x + sheet * 3, y + 2 + sheet * 3) * factor, Vector2(13, 26) * factor), M.PAPER)
			draw_rect(Rect2(Vector2(x + sheet * 3, y + 2 + sheet * 3) * factor, Vector2(13, 26) * factor), M.LINE, false, factor)
		_text(str(specs[index][0]), Vector2(x + 26, y + 12), 12, M.MUTED, column - 32)
		_text(_money(amount) if recorded else "記録なし", Vector2(x + 26, y + 32), 15, color, column - 32)
