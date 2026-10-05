extends Control
## A proposed fee, actual reference and the customer's real fee ceiling.
## Material is a pass-through invoice line; it is not counted as margin.
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
var quote: Dictionary = {}
var factor := 1.0
var ceiling: Label
var reference: Label
var proposed: Label
var margin: Label

func setup(initial: Dictionary, scale: float) -> void:
	name = "QuotePriceScale"; factor = scale; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 91 * factor
	ceiling = _label("QuoteBudgetMarker", 12, M.MUTED)
	reference = _label("QuoteReferenceMarker", 12, M.MUTED)
	proposed = _label("QuoteProposalMarker", 13, M.INK)
	margin = _label("QuoteMarginParts", 12, M.MUTED)
	resized.connect(_layout); set_quote(initial)

func _label(id: String, points: int, color: Color) -> Label:
	var label := Label.new(); label.name = id; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI.font(400)); label.add_theme_font_size_override("font_size", roundi(points * factor))
	label.add_theme_color_override("font_color", color); label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(label); return label

func set_quote(value: Dictionary) -> void:
	quote = value.duplicate(true)
	set_meta("affordable", bool(quote.get("affordable", false)))
	ceiling.text = "顧客上限 ¥%d" % int(quote.get("budget_limit", 0))
	reference.text = "○ 相場 ¥%d" % int(quote.get("reference_fee", 0))
	proposed.text = ("✓ 予算内" if bool(quote.get("affordable", false)) else "× 予算超過") + "　基本料 ¥%d" % int(quote.get("quoted_fee", 0))
	proposed.text += "　" + str({"discount":"割安 / 評価 +3", "fair":"相場内 / 評価 ±0", "premium":"高め / 評価 −3"}.get(str(quote.get("price_reaction", "")), ""))
	proposed.add_theme_color_override("font_color", M.INK if bool(quote.get("affordable", false)) else M.DANGER)
	var material := int(quote.get("invoice_total", 0)) - int(quote.get("quoted_fee", 0))
	var operating := int(quote.get("costs", 0)) - material
	margin.text = "基本料 ¥%d − 業務経費 ¥%d = 利益 ¥%d" % [int(quote.get("quoted_fee", 0)), operating, int(quote.get("net", 0))]
	_layout(); queue_redraw()

func _maximum() -> float:
	return maxf(1, maxf(float(quote.get("budget_limit", 0)) * 1.18, float(quote.get("quoted_fee", 0)) * 1.05))

func _x(value: float) -> float:
	return 12 * factor + (size.x - 24 * factor) * clampf(value / _maximum(), 0, 1)

func _layout() -> void:
	if ceiling == null: return
	var cap := _x(float(quote.get("budget_limit", 0)))
	ceiling.position = Vector2(maxf(12 * factor, cap - 155 * factor), 0)
	ceiling.size = Vector2(155 * factor, 23 * factor)
	reference.position = Vector2(12 * factor, 0); reference.size = Vector2(155 * factor, 23 * factor)
	proposed.position = Vector2(12 * factor, 41 * factor); proposed.size = Vector2(size.x - 24 * factor, 23 * factor)
	margin.position = Vector2(12 * factor, 63 * factor); margin.size = Vector2(size.x - 24 * factor, 23 * factor)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("f6f1e5"))
	var left := 12 * factor; var cap := _x(float(quote.get("budget_limit", 0))); var fee := _x(float(quote.get("quoted_fee", 0))); var y := 29 * factor
	draw_line(Vector2(left, y), Vector2(size.x - left, y), M.LINE, 9 * factor)
	draw_line(Vector2(left, y), Vector2(minf(fee, cap), y), M.ACCENT, 9 * factor)
	if fee > cap: draw_line(Vector2(cap, y), Vector2(fee, y), M.DANGER, 9 * factor)
	draw_line(Vector2(cap, y - 10 * factor), Vector2(cap, y + 9 * factor), M.INK, 2 * factor)
	var reference := _x(float(quote.get("reference_fee", 0)))
	draw_circle(Vector2(reference, y), 4 * factor, Color("f6f1e5"))
	draw_arc(Vector2(reference, y), 4 * factor, 0, TAU, 16, M.INK, factor)
	draw_colored_polygon(PackedVector2Array([Vector2(fee, y + 8 * factor), Vector2(fee - 5 * factor, y + 15 * factor), Vector2(fee + 5 * factor, y + 15 * factor)]), M.INK)
