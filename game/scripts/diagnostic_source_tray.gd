extends Control
## Two recorded specimens. Selection never requests or adopts evidence.
signal source_selected(source: String)
const UI = preload("res://scripts/ui_theme.gd")
const ACCENT := Color("7556ad")
var factor := 1.0
var staff: Dictionary = {}
var current: Dictionary = {}
var selected := "staff"
var objects: Array[Button] = []

func setup(scale: float, staff_record: Dictionary, probe: Dictionary, source: String) -> void:
	factor = scale; staff = staff_record.duplicate(true); current = probe.duplicate(true); selected = source
	name = "DiagnosticSourceTray"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 64 * factor
	for id in ["staff", "current"]:
		var button := Button.new()
		button.name = "DiagnosticSource_" + id
		button.tooltip_text = "担当者が保存した観測" if id == "staff" else "採用・実行した検査記録"
		button.flat = true
		for key in ["normal", "pressed", "disabled"]: button.add_theme_stylebox_override(key, StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", UI.style(Color(0.46, 0.34, 0.68, 0.06), Color.TRANSPARENT, 0, 0, 0))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, ACCENT, 0, 0, 0))
		button.pressed.connect(func(): source_selected.emit(id))
		add_child(button); objects.append(button)
	resized.connect(_layout)
	_layout.call_deferred()

func _layout() -> void:
	for i in objects.size():
		objects[i].position = Vector2(i * size.x / 2, 0)
		objects[i].size = Vector2(size.x / 2, size.y)
	queue_redraw()

func _draw() -> void:
	var s := factor
	for i in 2:
		var x := i * size.x / 2
		var active := selected == ("staff" if i == 0 else "current")
		var ink := ACCENT if active else UI.MUTED
		var sheet := Rect2(x + 8*s, 8*s, 29*s, 39*s)
		draw_rect(Rect2(sheet.position + Vector2(-3, 3)*s, sheet.size), Color("d6dfe4"))
		draw_colored_polygon(PackedVector2Array([sheet.position, sheet.position + Vector2(20,0)*s, sheet.position + Vector2(29,9)*s, sheet.end, sheet.position + Vector2(0,39)*s]), Color("fdfbf4") if i == 0 else Color("ece8f2"))
		for line in 3: draw_line(sheet.position + Vector2(6, 14 + line*5)*s, sheet.position + Vector2(23, 14 + line*5)*s, ink, s)
		var data := staff if i == 0 else current
		var known := bool(data.get("recorded", false))
		var mark := "?" if not known else "↻" if not bool(data.get("fresh", false)) else "✓" if bool(data.get("passed", false)) else "×"
		_text(mark, Vector2(x + 28*s, 49*s), 18, ink, 25*s)
		var owner := str(staff.get("member_name", staff.get("member_id", "担当者")))
		var title := owner + "の観測" if i == 0 else "検査記録"
		var note := ""
		if i == 0:
			var day := int(staff.get("completed_day", -1)); var minute := int(staff.get("completed_minute", -1))
			note = "DAY%d %02d:%02d" % [day, minute / 60, minute % 60] if day > 0 and minute >= 0 else "時刻不明"
		else:
			var attribution: Dictionary = current.get("staff_observation_source", {})
			note = "未実行" if not known else str(attribution.get("member_name", "担当者")) + "から採用" if not attribution.is_empty() else "自分で計測"
		_text(title, Vector2(x + 52*s, 25*s), 14, ink, size.x/2 - 58*s)
		_text(note, Vector2(x + 52*s, 46*s), 12, UI.MUTED, size.x/2 - 58*s)
		draw_line(Vector2(x + 4*s, 59*s), Vector2(x + size.x/2 - 4*s, 59*s), ink if active else UI.BORDER, (3 if active else 1)*s)

func _text(value: String, at: Vector2, points: int, color: Color, width: float) -> void:
	var font := UI.font(500)
	var text := value
	var fs := roundi(points * factor)
	while text.length() > 1 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		text = text.left(-2) + "…"
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, color)
