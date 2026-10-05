extends Control
## A customer's work order, not a measurement of an unconnected server.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("303c40")
const PAPER := Color("fffdf5")
const RED := Color("ad4438")
var factor := 1.0
var objects: Dictionary = {}
var inspection: Label
var profile: Dictionary = {}

func setup(value: Dictionary, scale_factor: float) -> void:
	name = "ShareIntakeBoard"
	set_meta("projection", "customer_report")
	factor = scale_factor
	profile = value.duplicate(true)
	custom_minimum_size = Vector2(0, 212 * factor)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label("ShareIntakeReported", "顧客申告 · 経理", 12, RED)
	_label("ShareIntakeUnknown", "? 原因未調査", 12, INK)
	_object("ShareIntakeReport", "日報\nreport.txt", "経理から、開けるが保存できないと連絡。今日の締めまでに編集を再開したい。原因は受注後に実測します。")
	_object("ShareIntakeBoundary", "来客 · guest", "来客には社内資料を見せない依頼です。社員の保存が成功しても、来客の閲覧・保存を許せば納品条件を満たしません。")
	_label("ShareIntakeSave", "× 保存できない", 15, RED)
	_label("ShareIntakeKeep", "社内資料を守る", 13, INK)
	_label("ShareIntakeShare", "社内共有", 11, INK)
	_label("ShareIntakeStaffGoal", "○ 社員の閲覧・保存", 13, INK)
	_label("ShareIntakeGuestGoal", "○ 来客の閲覧・保存を拒否", 13, INK)
	inspection = _label("ShareIntakeInspection", "納品条件 · 未検証", 12, INK)
	inspection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resized.connect(_layout)

func _label(id: String, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new(); label.name = id; label.text = value
	label.add_theme_font_override("font", UI.font(400))
	label.add_theme_font_size_override("font_size", roundi(font_size * factor))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(label); objects[id] = label
	return label

func _object(id: String, value: String, detail: String) -> void:
	var button := Button.new(); button.name = id; button.text = value
	button.add_theme_font_override("font", UI.font(400))
	button.add_theme_font_size_override("font_size", roundi(15 * factor))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, INK)
	button.add_theme_stylebox_override("normal", UI.style(PAPER, Color("b5b7aa"), 5, 4, 2))
	button.add_theme_stylebox_override("hover", UI.style(Color("fff6d8"), INK, 5, 4, 2))
	button.add_theme_stylebox_override("pressed", UI.style(Color("f1e8c9"), INK, 5, 4, 2))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, INK, 2, 2, 2))
	button.tooltip_text = "日報の依頼を開く" if id == "ShareIntakeReport" else "来客の条件を開く"
	button.pressed.connect(func(): inspection.text = detail)
	add_child(button); objects[id] = button

func _layout() -> void:
	if size.x < 1: return
	var w := size.x
	_place("ShareIntakeReported", Rect2(16 * factor, 8 * factor, w * .52, 24 * factor))
	_place("ShareIntakeUnknown", Rect2(w * .72, 8 * factor, w * .27, 24 * factor))
	_place("ShareIntakeReport", Rect2(w * .13, 42 * factor, w * .32, 73 * factor))
	_place("ShareIntakeSave", Rect2(w * .13, 118 * factor, w * .34, 26 * factor))
	_place("ShareIntakeBoundary", Rect2(w * .68, 74 * factor, w * .29, 40 * factor))
	_place("ShareIntakeKeep", Rect2(w * .68, 118 * factor, w * .30, 25 * factor))
	_place("ShareIntakeShare", Rect2(w * .52, 115 * factor, w * .14, 25 * factor))
	_place("ShareIntakeStaffGoal", Rect2(16 * factor, 151 * factor, w * .46, 25 * factor))
	_place("ShareIntakeGuestGoal", Rect2(w * .51, 151 * factor, w * .48, 25 * factor))
	_place("ShareIntakeInspection", Rect2(16 * factor, 182 * factor, w - 32 * factor, 25 * factor))
	# Details increase the canvas only when requested; the initial work order stays compact.
	custom_minimum_size.y = maxf(212 * factor, 188 * factor + inspection.get_minimum_size().y)
	queue_redraw()

func _place(id: String, rect: Rect2) -> void:
	var object: Control = objects[id]; object.position = rect.position; object.size = rect.size

func _draw() -> void:
	var w := size.x
	draw_style_box(UI.style(Color("f8f3e6"), Color("d3cdbd"), 0, 0, 2), Rect2(Vector2.ZERO, size))
	# Perforated job sheet and a physical privacy boundary, unlike the appliance blueprint.
	for y in range(42, 139, 16): draw_circle(Vector2(9, y) * factor, 2 * factor, Color("c5beb1"))
	for y in [49, 60, 71, 82, 93]:
		draw_line(Vector2(w * .06, y * factor), Vector2(w * .10, y * factor), Color("b8b09f"), factor)
	var gap := Vector2(w * .51, 86 * factor)
	draw_line(Vector2(w * .46, 86 * factor), gap - Vector2(6, 0) * factor, RED, 2 * factor, true)
	draw_line(gap + Vector2(6, 0) * factor, Vector2(w * .55, 86 * factor), RED, 2 * factor, true)
	draw_line(gap - Vector2(5, 5) * factor, gap + Vector2(5, 5) * factor, RED, 3 * factor, true)
	draw_line(gap + Vector2(-5, 5) * factor, gap + Vector2(5, -5) * factor, RED, 3 * factor, true)
	var folder := Vector2(w * .57, 88 * factor)
	draw_rect(Rect2(folder - Vector2(19, 19) * factor, Vector2(16, 6) * factor), Color("cfb779"))
	draw_style_box(UI.style(Color("ead8a6"), Color("a78d50"), 0, 0, 3), Rect2(folder - Vector2(22, 14) * factor, Vector2(44, 32) * factor))
	var lock := Vector2(w * .81, 50 * factor)
	draw_arc(lock - Vector2(0, 3) * factor, 8 * factor, PI, TAU, 16, INK, 2 * factor, true)
	draw_style_box(UI.style(Color("e3e8df"), INK, 0, 0, 2), Rect2(lock - Vector2(12, 3) * factor, Vector2(24, 17) * factor))
	draw_circle(lock + Vector2(0, 4) * factor, 2 * factor, INK)
	draw_dashed_line(Vector2(w * .64, 39 * factor), Vector2(w * .64, 143 * factor), Color("8e9384"), factor, 5 * factor)
	draw_line(Vector2(16 * factor, 147 * factor), Vector2(w - 16 * factor, 147 * factor), Color("d3cdbd"), factor)

func _ready() -> void:
	inspection.minimum_size_changed.connect(_layout)
	_layout()
