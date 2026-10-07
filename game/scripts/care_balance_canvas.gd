extends Control
## The operating floor supported by care, separate from one-off case profit.
const M = preload("res://scripts/management_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
var model := {}
var factor := 1.0

func configure(value: Dictionary, scale: float) -> void:
	model = value.duplicate(true); factor = scale
	custom_minimum_size.y = 128 * factor
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw): resized.connect(queue_redraw)
	queue_redraw()

func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(UI.font(500), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _money(value: int) -> String:
	return ("−¥%d" % absi(value)) if value < 0 else "¥%d" % value

func _draw() -> void:
	if model.is_empty(): return
	draw_set_transform(Vector2.ZERO, 0, Vector2(factor, factor))
	var width := size.x / factor
	var cell := (width - 24) / 4.0
	draw_rect(Rect2(0, 0, width, 128), Color("F5F1E5"))
	_text(Vector2(12, 21), "DAY%d · 保守と全社給与" % int(model.get("day", 0)), 14, M.INK)
	var values := [int(model.get("earned", 0)), -int(model.get("service_cost", 0)), -int(model.get("company_payroll", 0)), int(model.get("actual_after_payroll", 0))]
	var labels := ["本日の点検収入", "保守原価", "全社給与", "差引"]
	var largest := 1.0
	for value in values: largest = maxf(largest, absf(float(value)))
	for index in 4:
		var x := 12 + index * cell
		var known: bool = [int(model.get("earned", -1)) >= 0, int(model.get("service_cost", -1)) >= 0, bool(model.get("payroll_known", false)), int(model.get("earned", -1)) >= 0 and bool(model.get("payroll_known", false)) and int(model.get("service_cost", -1)) >= 0][index]
		var color: Color = M.ACCENT if int(values[index]) >= 0 else M.DANGER
		_text(Vector2(x, 46), labels[index], 13, M.MUTED)
		_text(Vector2(x, 70), _money(values[index]) if known else "記録なし", 20, color)
		draw_rect(Rect2(x, 79, cell - 20, 4), M.LINE)
		if known: draw_rect(Rect2(x, 79, (cell - 20) * absf(float(values[index])) / largest, 4), color)
		if index < 3: _text(Vector2(x + cell - 14, 67), "→" if index == 2 else "+", 14, M.MUTED)
	var expected := "全点検成功なら %s / 日" % _money(int(model.get("expected_after_payroll", 0))) if bool(model.get("payroll_known", false)) and bool(model.get("revenue_known", false)) and int(model.get("service_cost", -1)) >= 0 else "旧記録不足 · 差引を算出できません"
	_text(Vector2(12, 111), expected, 14, M.INK)
	if width > 620: _text(Vector2(width - 243, 111), "単発案件・採用費・設備費は別", 13, M.MUTED)
