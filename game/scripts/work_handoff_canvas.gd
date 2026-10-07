extends Control
## Saved work -> recorded acceptance -> customer delivery. No VM reads or work.
signal route_requested(route: String)
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
var handoff: Dictionary = {}
var factor := 1.0
var buttons: Array[Button] = []

func configure(value: Dictionary, scale: float) -> void:
	handoff = value.duplicate(true); factor = maxf(.5, scale)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 123 * factor)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children(): remove_child(child); child.queue_free()
	buttons.clear()
	for spec in [["record", "担当記録を開く"], ["verify", "診断ラボへ"], ["receipt", "納品前確認へ"]]:
		var button := Button.new()
		button.name = "HandoffObject_" + str(spec[0]); button.text = str(spec[1])
		button.add_theme_font_override("font", UI.font(500))
		button.add_theme_font_size_override("font_size", roundi(12 * factor))
		button.clip_text = true
		M.button(button, "quiet")
		button.pressed.connect(func(): route_requested.emit(str(spec[0])))
		add_child(button); buttons.append(button)
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout.call_deferred(); queue_redraw()

func _layout() -> void:
	if size.x <= 0: return
	var visual_scale := _visual_scale()
	var width := size.x / visual_scale
	custom_minimum_size.y = 123 * visual_scale
	for i in buttons.size():
		buttons[i].position = Vector2(i * width / 3 + 3, 91) * visual_scale
		buttons[i].size = Vector2(width / 3 - 6, 30) * visual_scale
		buttons[i].add_theme_font_size_override("font_size", roundi(12 * visual_scale))
	queue_redraw()

func _visual_scale() -> float:
	return factor * (1.3 if size.x / factor > 1000 else 1.0)

func _draw() -> void:
	if size.x <= 0: return
	var visual_scale := _visual_scale()
	draw_set_transform(Vector2.ZERO, 0, Vector2(visual_scale, visual_scale))
	var width := size.x / visual_scale
	var centers := [width / 6, width / 2, width * 5 / 6]
	var receipt: Dictionary = handoff.get("receipts", []).back() if not handoff.get("receipts", []).is_empty() else {}
	var acceptance: Dictionary = handoff.get("acceptance", {})
	var state := str(acceptance.get("state", "unknown"))
	var ink: Color = M.ACCENT if state == "ready" else M.DANGER if state == "failed" else M.WARNING if state == "stale" else M.MUTED
	for i in 2:
		var from := Vector2(centers[i] + 41, 43)
		var to := Vector2(centers[i + 1] - 43, 43)
		draw_dashed_line(from, to, M.LINE if i == 1 else M.ACCENT, 2, 4)
		draw_line(to - Vector2(5, 4), to, M.MUTED, 1.5)
		draw_line(to - Vector2(5, -4), to, M.MUTED, 1.5)
	_center_text(centers[0], 12, "保存した担当記録", 12, M.MUTED)
	_center_text(centers[1], 12, "受入検査の記録", 12, M.MUTED)
	_center_text(centers[2], 12, "顧客へ納品", 12, M.MUTED)
	_paper(Vector2(centers[0], 43), not receipt.is_empty())
	var member := str(receipt.get("member_name", ""))
	if member.is_empty(): member = str(receipt.get("member_id", ""))
	member = {"aya":"綾", "ren":"蓮"}.get(member, member)
	var phase := str(receipt.get("phase", "作業記録あり"))
	var title := member + " · " + phase if not receipt.is_empty() else "記録なし"
	var font: Font = UI.font(500)
	while font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > width / 3 - 8 and title.length() > 2:
		title = title.left(-2) + "…"
	_center_text(centers[0], 87, title, 12, M.INK)
	_meter(Vector2(centers[1], 43), acceptance, ink)
	_center_text(centers[1], 87, {"ready":"✓ 記録上合格", "failed":"× 条件未達", "stale":"↻ 更新後は未検査"}.get(state, "? 未検査"), 12, ink)
	_stamp(Vector2(centers[2], 43))
	_center_text(centers[2], 87, "未納品", 12, M.MUTED)

func _paper(center: Vector2, recorded: bool) -> void:
	var rect := Rect2(center - Vector2(22, 28), Vector2(44, 56))
	draw_rect(Rect2(rect.position + Vector2(4, 3), rect.size), M.LINE)
	draw_rect(rect, Color("FFF5DF")); draw_rect(rect, Color("A87F43"), false, 1.5)
	for i in 3: draw_line(center + Vector2(-13, -13 + i * 7), center + Vector2(11, -13 + i * 7), Color("A87F43"), 1)
	if recorded:
		draw_circle(center + Vector2(13, 17), 11, M.ACCENT)
		draw_polyline(PackedVector2Array([center + Vector2(7,17), center + Vector2(11,21), center + Vector2(19,13)]), M.WHITE, 2)

func _meter(center: Vector2, acceptance: Dictionary, ink: Color) -> void:
	var rect := Rect2(center - Vector2(34, 28), Vector2(68, 53))
	draw_rect(rect, M.DARK); draw_rect(rect.grow(-3), Color("253F47"))
	var total := int(acceptance.get("total", 0))
	var count := "%d/%d" % [int(acceptance.get("passed", 0)), total] if total > 0 else "?"
	_center_text(center.x, center.y + 4, count, 22, M.WHITE)
	var cells := mini(total, 12)
	var checks: Array = acceptance.get("checks", [])
	for i in cells:
		var passed: bool = i < checks.size() and checks[i] is Dictionary and bool(checks[i].get("passed", false))
		var color: Color = ink if str(acceptance.get("state", "unknown")) == "stale" else M.ACCENT if passed else M.DANGER
		draw_rect(Rect2(center.x - cells * 2.5 + i * 5, center.y + 14, 3, 3), color)
	draw_line(center + Vector2(0,25), center + Vector2(0,30), M.INK, 3)
	draw_line(center + Vector2(-17,30), center + Vector2(17,30), M.INK, 2)

func _stamp(center: Vector2) -> void:
	for i in 16:
		var a := TAU * i / 16.0
		draw_arc(center, 27, a, a + .22, 4, M.MUTED, 1.5)
	draw_line(center + Vector2(-12,-8), center + Vector2(12,-8), M.LINE, 2)
	draw_line(center + Vector2(-12,0), center + Vector2(12,0), M.LINE, 2)
	_center_text(center.x, center.y + 17, "保留", 12, M.MUTED)

func _center_text(x: float, y: float, value: String, points: int, color: Color) -> void:
	var font: Font = UI.font(500)
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x
	draw_string(font, Vector2(x - width / 2, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, points, color)
