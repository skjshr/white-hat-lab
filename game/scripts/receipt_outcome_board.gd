extends Control
## A paper statement of saved delivery consequences. No live measurements.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("253e4b")
const GREEN := Color("276b57")
const RED := Color("a64032")
const LINE := Color("d5d0bd")
var receipt: Dictionary = {}
var text_factor := 1.0
var fields: Array[Dictionary] = []

func setup(saved: Dictionary, factor: float) -> void:
	receipt = saved.duplicate(true)
	text_factor = factor
	custom_minimum_size = Vector2(0, 210 * factor)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field("ReceiptGradeCaption", "納品評価", 12, INK, 0.025, 10, 0.16)
	_field("ReceiptGradeValue", str(receipt.get("grade", "—")), 48, _result_color(), 0.025, 30, 0.16)
	var late: bool = str(receipt.get("rating", "")) == "late"
	_field("ReceiptTiming", "期限超過" if late else "期限内" if str(receipt.get("rating", "")) == "on_time" else "期限の記録なし", 12, RED if late else INK, 0.025, 99, 0.16)
	_field("ReceiptSatisfactionCaption", "顧客満足 / 100", 13, INK, 0.225, 10, 0.335)
	_field("ReceiptSatisfactionValue", _change("satisfaction"), 23, INK, 0.225, 33, 0.335)
	_field("ReceiptCreditCaption", "会社の信頼", 13, INK, 0.61, 10, 0.215)
	_field("ReceiptCreditValue", _change("credit"), 23, INK, 0.61, 33, 0.215)
	_field("ReceiptCreditDelta", _delta("credit"), 13, _delta_color("credit"), 0.61, 85, 0.215)
	_field("ReceiptLevelCaption", "会社 Lv", 13, INK, 0.85, 10, 0.125)
	_field("ReceiptLevelValue", _change("level"), 23, INK, 0.85, 33, 0.125)
	_field("ReceiptLevelDelta", _delta("level"), 13, _delta_color("level"), 0.85, 85, 0.125)
	var sales := int(receipt.get("fee", 0)) + int(receipt.get("bonus", 0)) + (int(receipt.get("material_cost", 0)) if bool(receipt.get("material_billable", false)) else 0)
	for item in [["Sales", "売上", sales, 0.025, INK], ["Costs", "経費", int(receipt.get("cost", 0)), 0.375, INK], ["Profit", "案件利益", int(receipt.get("net", 0)), 0.725, GREEN if int(receipt.get("net", 0)) >= 0 else RED]]:
		_field("ReceiptImpact" + str(item[0]) + "Caption", str(item[1]), 12, item[4], item[3], 129, 0.25)
		_field("ReceiptImpact" + str(item[0]), _yen(int(item[2])), 25, item[4], item[3], 148, 0.25)
	resized.connect(_layout)
	_layout()

func _field(id: String, value: String, points: int, color: Color, x: float, y: float, width: float) -> void:
	var label := Label.new(); label.name = id; label.text = value
	label.add_theme_font_override("font", UI.font(700 if points >= 23 else 400))
	label.add_theme_font_size_override("font_size", int(points * text_factor))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.tooltip_text = value
	add_child(label); fields.append({"label":label,"x":x,"y":y,"width":width,"points":points})

func _layout() -> void:
	for field in fields:
		field.label.position = Vector2(size.x * float(field.x), float(field.y) * text_factor)
		field.label.size = Vector2(size.x * float(field.width), (float(field.points) + 8) * text_factor)
	queue_redraw()

func _change(key: String) -> String:
	if not receipt.has(key + "_before") or not receipt.has(key + "_after"): return "—"
	return "%d → %d" % [int(receipt[key + "_before"]), int(receipt[key + "_after"])]

func _delta(key: String) -> String:
	if not receipt.has(key + "_before") or not receipt.has(key + "_after"): return "記録なし"
	return "%+d" % (int(receipt[key + "_after"]) - int(receipt[key + "_before"]))

func _delta_color(key: String) -> Color:
	if not receipt.has(key + "_before") or not receipt.has(key + "_after"): return Color("77766d")
	return RED if int(receipt.get(key + "_after", 0)) < int(receipt.get(key + "_before", 0)) else GREEN

func _result_color() -> Color:
	if not receipt.has("grade"): return Color("77766d")
	return RED if str(receipt.get("rating", "")) == "late" else GREEN

func _draw() -> void:
	var f := text_factor
	draw_style_box(UI.style(Color("fffcf2"), LINE, 9, 0, 1), Rect2(Vector2.ZERO, size))
	for x in [0.025, 0.975]:
		draw_style_box(UI.style(Color("afada3"), Color("8b8a81"), 0, 0, 1), Rect2(Vector2(size.x * x - 7 * f, -3 * f), Vector2(14, 5) * f))
	var center := Vector2(size.x * 0.105, 62 * f)
	draw_arc(center, 32 * f, 0, TAU, 64, _result_color(), 2 * f, true)
	draw_arc(center, 29 * f, 0, TAU, 64, _result_color(), f, true)
	draw_line(Vector2(size.x * 0.205, 14 * f), Vector2(size.x * 0.205, 110 * f), LINE, f)
	draw_line(Vector2(16 * f, 121 * f), Vector2(size.x - 16 * f, 121 * f), LINE, f)
	_gauge()
	# Signed arithmetic and lengths distinguish earnings, spending and a loss.
	var font: Font = UI.font(700)
	for item in [["−", 0.325], ["=", 0.675]]:
		draw_string(font, Vector2(size.x * float(item[1]) - 9 * f, 173 * f), str(item[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * f), INK)
	var sales := int(receipt.get("fee", 0)) + int(receipt.get("bonus", 0)) + (int(receipt.get("material_cost", 0)) if bool(receipt.get("material_billable", false)) else 0)
	var cost := int(receipt.get("cost", 0)); var net := int(receipt.get("net", 0))
	var total := maxf(maxi(sales, cost), 1)
	var x := size.x * 0.025; var width := size.x * 0.95
	draw_rect(Rect2(x, 190 * f, width, 8 * f), Color("e9e4d5"))
	draw_rect(Rect2(x, 190 * f, width * clampf(float(cost) / total, 0, 1), 8 * f), Color("7a7d7a"))
	if net >= 0:
		draw_rect(Rect2(x + width * clampf(float(cost) / total, 0, 1), 190 * f, width * clampf(float(net) / total, 0, 1), 8 * f), GREEN)
	else:
		var start := x + width * clampf(float(sales) / total, 0, 1)
		draw_rect(Rect2(start, 187 * f, width * clampf(float(-net) / total, 0, 1), 14 * f), RED)
		for offset in range(0, int(width * clampf(float(-net) / total, 0, 1)), maxi(1, int(9 * f))): draw_line(Vector2(start + offset, 187 * f), Vector2(minf(start + offset + 7 * f, x + width), 201 * f), Color("fffcf2"), f)

func _gauge() -> void:
	var f := text_factor; var left := size.x * 0.235; var width := size.x * 0.315; var y := 83 * f
	for i in 10:
		draw_rect(Rect2(left + width * i / 10, y, width / 10 - 2 * f, 10 * f), Color("e2ddce"))
	if receipt.has("satisfaction_before") and receipt.has("satisfaction_after"):
		var before := left + width * clampf(float(receipt.satisfaction_before) / 100, 0, 1)
		var after := left + width * clampf(float(receipt.satisfaction_after) / 100, 0, 1)
		draw_line(Vector2(before, y - 4 * f), Vector2(before, y + 14 * f), INK, 2 * f)
		draw_line(Vector2(before, y + 5 * f), Vector2(after, y + 5 * f), _delta_color("satisfaction"), 4 * f)
		draw_colored_polygon(PackedVector2Array([Vector2(after, y - 6 * f), Vector2(after - 5 * f, y - 14 * f), Vector2(after + 5 * f, y - 14 * f)]), _delta_color("satisfaction"))
	var font: Font = UI.font()
	draw_string(font, Vector2(left, 109 * f), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * f), INK)
	draw_string(font, Vector2(left + width - 22 * f, 109 * f), "100", HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * f), INK)

func _yen(value: int) -> String:
	var digits := str(absi(value)); var groups := []
	while digits.length() > 3:
		groups.push_front(digits.right(3)); digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return ("-" if value < 0 else "") + "¥" + ",".join(groups)
