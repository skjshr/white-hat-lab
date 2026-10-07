extends Control
## Read-only customer-facing deadline brief. Queue presses only request a selection.

signal queue_open_requested(queue_id: String)

const UI = preload("res://scripts/ui_theme.gd")
const PAPER := Color("fbf8ee")
const SURFACE := Color("fffdf7")
const INK := Color("253b3d")
const MUTED := Color("607475")
const LINE := Color("d5dfd8")
const GREEN := Color("286950")
const RED := Color("a94237")
const GOLD := Color("a76e20")
const DEPOT_PATH := "res://assets/ui/customers/logistics-depot-v1.png"

static var _depot_texture: Texture2D

var brief: Dictionary = {}
var factor := 1.0
var queue_callback: Callable
var queue_buttons: Dictionary = {}
var queue_data: Dictionary = {}


func configure(brief: Dictionary, scale: float, open_queue: Callable = Callable()) -> void:
	self.brief = brief.duplicate(true)
	factor = maxf(.5, scale)
	queue_callback = open_queue
	for child in get_children():
		remove_child(child)
		child.queue_free()
	queue_buttons.clear()
	queue_data.clear()
	if name.is_empty(): name = "PriorityBriefCanvas"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(0, 280 * factor)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var interactive := queue_callback.is_valid() and not bool(self.brief.get("preview", false))
	if bool(brief.get("available", false)):
		for row_value in brief.get("queues", []):
			if not row_value is Dictionary: continue
			var row: Dictionary = row_value
			var id := str(row.get("id", ""))
			if id not in ["dispatch", "claims"]: continue
			queue_data[id] = row.duplicate(true)
			var button := Button.new()
			button.name = "PriorityBrief_" + id
			button.text = ""
			button.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if interactive else Control.CURSOR_ARROW
			button.tooltip_text = _queue_tooltip(id, row) if interactive else ""
			for state in ["normal", "hover", "pressed", "disabled"]:
				var fill := Color("eaf3ed") if interactive and state in ["hover", "pressed"] else Color.TRANSPARENT
				button.add_theme_stylebox_override(state, UI.style(fill, Color.TRANSPARENT, 0, 0, 8))
			button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, UI.PRIMARY, 0, 0, 3))
			button.draw.connect(_draw_queue.bind(button, id))
			button.pressed.connect(_select_queue.bind(id))
			add_child(button)
			queue_buttons[id] = button
		if not queue_data.has("dispatch") or not queue_data.has("claims"):
			for button_value in queue_buttons.values():
				button_value.queue_free()
			queue_buttons.clear()
			queue_data.clear()
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout()
	queue_redraw()


func _queue_tooltip(id: String, row: Dictionary) -> String:
	var title := str(row.get("label", id))
	var received := int(row.get("received_count", 0))
	var approved := int(row.get("approved_count", 0))
	var state := "受付済・現行" if received >= approved and bool(row.get("current", false)) else "受付済・再検査" if received > 0 else "未受付"
	var timing := "受注後の受付期限" if bool(brief.get("preview", false)) else "受付期限 %d分 / 経過 %d分" % [int(row.get("deadline", 0)), int(brief.get("elapsed", 0))]
	return "%s / %s / %s / 選択のみ" % [title, state, timing]


func _select_queue(id: String) -> void:
	if not queue_data.has(id) or not queue_callback.is_valid(): return
	queue_open_requested.emit(id)
	queue_callback.call(id)


func _layout() -> void:
	if size.x <= 0: return
	var width := size.x / factor
	var left := _main_left(width)
	for id in ["dispatch", "claims"]:
		if not queue_buttons.has(id): continue
		var button: Button = queue_buttons[id]
		button.position = Vector2(left, 68 if id == "dispatch" else 150) * factor
		button.size = Vector2(maxf(0, width - left - 12), 76) * factor
		button.queue_redraw()
	queue_redraw()


func _text(on: Control, value: String, point: Vector2, points: float, color: Color, max_width: float) -> void:
	if max_width <= 0: return
	on.draw_string(UI.font(500), point * factor, value, HORIZONTAL_ALIGNMENT_LEFT, max_width * factor, roundi(points * factor), color)


func _font_width(value: String, points: float) -> float:
	return UI.font(500).get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(points * factor)).x / factor

func _rect(value: Rect2) -> Rect2:
	return Rect2(value.position * factor, value.size * factor)

func _depot_width(width: float) -> float:
	return 100.0 if width < 760 else 140.0

func _main_left(width: float) -> float:
	return _depot_width(width) + 20.0

func _chart_start(width: float) -> float:
	return _main_left(width) + (250.0 if width < 760 else 280.0)


func _draw() -> void:
	var width := size.x / factor
	var height := size.y / factor
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_rect(Rect2(Vector2.ZERO, size), LINE, false, factor)
	if not bool(brief.get("available", false)):
		_text(self, "業務の期限・費用は不明です", Vector2(18, 40), 14, MUTED, width - 36)
		_text(self, "保存記録を確認できません", Vector2(18, 65), 12, MUTED, width - 36)
		return
	_draw_depot()
	var chart_start := _chart_start(width)
	var chart_end := width - 16
	var chart_width := maxf(30, chart_end - chart_start)
	var max_deadline := 1
	for row in queue_data.values(): max_deadline = maxi(max_deadline, int(row.get("deadline", 0)))
	var clock := maxi(0, int(brief.get("elapsed", 0)))
	var preview := bool(brief.get("preview", false))
	var main_left := _main_left(width)
	_text(self, "業務の受付期限", Vector2(main_left, 22), 16, INK, 210)
	_text(self, "納品期限とは別", Vector2(width - 164, 22), 12, MUTED, 150)
	var connector := str(brief.get("connector_status", ""))
	var connector_text := "✓ 連携稼働" if connector == "ready" else "× 連携停止" if connector == "stopped" else "連携状態不明"
	var operation_text := ""
	if int(brief.get("rebuild_minutes", 0)) > 0:
		operation_text = " / 再構築%d分 / 手動%d分 ¥%s・残%d" % [int(brief.rebuild_minutes), int(brief.get("manual_minutes", 0)), _yen(int(brief.get("manual_fee", 0))), int(brief.get("manual_remaining", 0))]
	_text(self, connector_text + operation_text, Vector2(main_left, 45), 12, RED if connector == "stopped" else MUTED, width - main_left - 16)
	var axis_top := 51.0
	var row_top := 68.0
	var row_bottom := 226.0
	var tick_step := 10
	var tick := 0
	while tick < max_deadline:
		var tick_x := chart_start + chart_width * float(tick) / float(max_deadline)
		draw_line(Vector2(tick_x, axis_top + 11) * factor, Vector2(tick_x, row_bottom) * factor, Color("e4e9df"), factor)
		if chart_end - tick_x > 56:
			_text(self, "%d" % tick, Vector2(tick_x + 2, 66), 12, MUTED, 34)
		tick += tick_step
	var end_x := chart_end
	_text(self, "%d分" % max_deadline, Vector2(end_x - 46, 66), 12, MUTED, 46)
	if not preview:
		var elapsed_x := chart_start + chart_width * minf(float(clock), float(max_deadline)) / float(max_deadline)
		draw_line(Vector2(elapsed_x, row_top - 1) * factor, Vector2(elapsed_x, row_bottom) * factor, GREEN, 2 * factor)
		_text(self, "%s %d分" % [str(brief.get("clock_label", "対応経過")), clock], Vector2(main_left, 64), 12, GREEN, chart_start - main_left - 8)
	else:
		_text(self, "受注後の受付期限", Vector2(main_left, 64), 12, MUTED, chart_start - main_left - 8)
	_draw_loss_strip(width, height)


func _draw_depot() -> void:
	var width := size.x / factor
	var panel_width := _depot_width(width)
	var side := minf(120, panel_width - 16)
	var box := Rect2(Vector2(10, 12), Vector2(panel_width, 215))
	draw_style_box(UI.style(SURFACE, LINE, 0, 0, 9), _rect(box))
	var texture := _depot_image()
	if texture != null:
		var art_rect := Rect2(Vector2(10 + (panel_width - side) / 2.0, 20), Vector2(side, side))
		draw_texture_rect(texture, _rect(art_rect), false)
	else:
		_draw_depot_fallback()
	_text(self, str(brief.get("client", "北斗物流")), Vector2(18, 20 + side + 24), 14, INK, panel_width - 16)
	_text(self, "本人が対応", Vector2(18, 20 + side + 45), 12, MUTED, panel_width - 16)


func _depot_image() -> Texture2D:
	if _depot_texture != null: return _depot_texture
	if ResourceLoader.exists(DEPOT_PATH):
		_depot_texture = load(DEPOT_PATH) as Texture2D
		if _depot_texture != null: return _depot_texture
	var path := ProjectSettings.globalize_path(DEPOT_PATH)
	if not FileAccess.file_exists(path): return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return null
	_depot_texture = ImageTexture.create_from_image(image)
	return _depot_texture


func _draw_depot_fallback() -> void:
	var panel_width := _depot_width(size.x / factor)
	var side := minf(120, panel_width - 16)
	var left := 10 + (panel_width - side) / 2.0
	var roof := PackedVector2Array([Vector2(left, 20 + side * .45), Vector2(left + side / 2, 20), Vector2(left + side, 20 + side * .45)])
	var scaled_roof := PackedVector2Array()
	for point in roof: scaled_roof.append(point * factor)
	draw_colored_polygon(scaled_roof, Color("bbd0c5"))
	draw_rect(_rect(Rect2(Vector2(left + side * .1, 20 + side * .42), Vector2(side * .8, side * .56))), Color("d7e3dc"))
	draw_rect(_rect(Rect2(Vector2(left + side * .22, 20 + side * .67), Vector2(side * .2, side * .31))), Color("839f93"))
	draw_rect(_rect(Rect2(Vector2(left + side * .56, 20 + side * .58), Vector2(side * .27, side * .17))), Color("f7f4e9"))
	draw_line(Vector2(left, 20 + side * .98) * factor, Vector2(left + side, 20 + side * .98) * factor, Color("81978d"), 2 * factor)


func _draw_queue(button: Button, id: String) -> void:
	var row: Dictionary = queue_data.get(id, {})
	if row.is_empty(): return
	var local_width := button.size.x / factor
	var local_height := button.size.y / factor
	var deadline := maxi(0, int(row.get("deadline", 0)))
	var max_deadline := 1
	for other in queue_data.values(): max_deadline = maxi(max_deadline, int(other.get("deadline", 0)))
	var canvas_width := size.x / factor
	var main_left := _main_left(canvas_width)
	var chart_start := _chart_start(canvas_width)
	var chart_end := canvas_width - 16
	var local_chart_start := chart_start - main_left
	var local_chart_end := chart_end - main_left
	var x_deadline := local_chart_start + (local_chart_end - local_chart_start) * float(deadline) / float(max_deadline)
	var x_local := x_deadline
	var title := str(row.get("label", "配送連絡" if id == "dispatch" else "返金照合"))
	var approved := maxi(0, int(row.get("approved_count", 0)))
	var received := clampi(int(row.get("received_count", 0)), 0, approved)
	var current := bool(row.get("current", false))
	var late := bool(row.get("late", false))
	var preview := bool(brief.get("preview", false))
	var background := Color("f0f5ed") if received >= approved and approved > 0 else SURFACE
	button.draw_style_box(UI.style(background, LINE, 0, 0, 7), _rect(Rect2(Vector2(1, 1), Vector2(local_width - 2, local_height - 2))))
	if id == "dispatch": _draw_package(button, Vector2(17, 16), true)
	else: _draw_receipt(button, Vector2(18, 14), true)
	_text(button, title, Vector2(48, 25), 16, INK, 90)
	_text(button, "受付 %d/%d" % [received, approved], Vector2(48, 45), 12, MUTED, 90)
	var status := "受付済・現行" if received >= approved and approved > 0 and current else "受付済・再検査" if received > 0 else "未受付"
	_text(button, status, Vector2(48, 65), 12, GREEN if current and received > 0 else MUTED, 92)
	var item_count := mini(approved, 5)
	for index in item_count:
		var token_center := Vector2(151 + index * 18, 39)
		if id == "dispatch": _draw_package(button, token_center - Vector2(9, 9), index < received, 18)
		else: _draw_receipt(button, token_center - Vector2(8, 10), index < received, 19)
	var cost_label := "確定補償 ¥%s" % _yen(int(row.get("loss_cost", 0))) if int(row.get("loss_cost", 0)) > 0 else "遅延時 ¥%s" % _yen(int(row.get("late_cost", 0)))
	if bool(row.get("received", false)) and int(row.get("loss_cost", 0)) == 0:
		cost_label = "期限内受付 · 補償 ¥0"
	_text(button, cost_label, Vector2(local_width - 158, 72), 12, RED if int(row.get("loss_cost", 0)) > 0 else MUTED, 150)
	var baseline := 57.0
	var line_start := local_chart_start
	var line_end := local_chart_end
	button.draw_line(Vector2(line_start, baseline) * factor, Vector2(line_end, baseline) * factor, Color("bdc9c2"), factor)
	var tick := 0
	while tick <= max_deadline:
		var global_tick := chart_start + (chart_end - chart_start) * float(tick) / float(max_deadline)
		var tick_local := global_tick - main_left
		button.draw_line(Vector2(tick_local, 53) * factor, Vector2(tick_local, local_height - 8) * factor, Color("e4e9df"), factor)
		tick += 10
	if not preview:
		var elapsed_x := local_chart_start + (local_chart_end - local_chart_start) * minf(float(maxi(0, int(brief.get("elapsed", 0)))), float(max_deadline)) / float(max_deadline)
		button.draw_line(Vector2(elapsed_x, 52) * factor, Vector2(elapsed_x, local_height - 8) * factor, GREEN, 2 * factor)
	button.draw_line(Vector2(x_local, 52) * factor, Vector2(x_local, local_height - 8) * factor, GOLD if not late else RED, (2 if late else 1.5) * factor)
	var deadline_label := "%d分" % deadline
	var deadline_color := RED if late else GOLD
	var deadline_width := _font_width(deadline_label, 14)
	var label_x := clampf(x_local - deadline_width / 2, line_start, line_end - deadline_width)
	_text(button, deadline_label, Vector2(label_x, 18), 14, deadline_color, line_end - label_x)
	if late:
		var late_label_x := x_local + 4
		if late_label_x + 78 > line_end: late_label_x = maxf(line_start, x_local - 82)
		_text(button, "! 期限超過", Vector2(late_label_x, 37), 12, RED, minf(82, line_end - late_label_x))


func _draw_package(on: Control, at: Vector2, received: bool, side: float = 24) -> void:
	var rect := Rect2(at, Vector2(side, side * .76))
	var fill := Color("cfe4d8") if received else SURFACE
	var edge := GREEN if received else Color("687f79")
	on.draw_rect(_rect(rect), fill, received)
	on.draw_rect(_rect(rect), edge, false, factor)
	on.draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y * .34) * factor, Vector2(rect.end.x, rect.position.y + rect.size.y * .34) * factor, edge, factor)
	on.draw_line(Vector2(rect.get_center().x, rect.position.y + rect.size.y * .34) * factor, Vector2(rect.get_center().x, rect.end.y) * factor, edge, factor)
	if received: _text(on, "✓", Vector2(rect.position.x + side * .22, rect.position.y + side * .68), 12, GREEN, side)


func _draw_receipt(on: Control, at: Vector2, received: bool, side: float = 21) -> void:
	var rect := Rect2(at, Vector2(side * .74, side))
	var fill := Color("e7eee3") if received else SURFACE
	var edge := GREEN if received else Color("687f79")
	on.draw_rect(_rect(rect), fill, received)
	on.draw_rect(_rect(rect), edge, false, factor)
	for index in 2:
		var y := rect.position.y + 6 + index * 6
		on.draw_line(Vector2(rect.position.x + 3, y) * factor, Vector2(rect.end.x - 3, y) * factor, edge, factor)
	if received: _text(on, "✓", Vector2(rect.position.x + 1, rect.end.y - 1), 12, GREEN, side)


func _draw_loss_strip(width: float, height: float) -> void:
	var loss := maxi(0, int(brief.get("loss_cost", 0)))
	var impact := maxi(0, int(brief.get("impact_cost", 0)))
	var manual := maxi(0, int(brief.get("manual_cost", 0)))
	var assistant := maxi(0, int(brief.get("assistant_cost", 0)))
	var total := loss + impact + manual + assistant
	var y := 231.0
	var strip := Rect2(Vector2(11, y), Vector2(width - 22, minf(43, height - y - 5)))
	draw_style_box(UI.style(Color("f8e9e3"), Color("e7c8bd"), 0, 0, 5), _rect(strip))
	var description := "追加費用 ¥%s" % _yen(total) if total == 0 else "追加費用 ¥%s  / 遅延 ¥%s · 流出 ¥%s · 手動 ¥%s · 助手 ¥%s" % [_yen(total), _yen(loss), _yen(impact), _yen(manual), _yen(assistant)]
	if width < 800 and total > 0:
		_text(self, "追加費用 ¥%s / 遅延 ¥%s ・流出 ¥%s" % [_yen(total), _yen(loss), _yen(impact)], Vector2(20, y + 18), 12, RED, width - 40)
		_text(self, "手動 ¥%s ・助手 ¥%s" % [_yen(manual), _yen(assistant)], Vector2(20, y + 36), 12, RED, width - 40)
	else:
		_text(self, description, Vector2(20, y + 28), 12, RED if total > 0 else INK, width - 40)


func _yen(amount: int) -> String:
	var raw := str(maxi(0, amount))
	var grouped := ""
	for index in raw.length():
		if index > 0 and (raw.length() - index) % 3 == 0: grouped += ","
		grouped += raw.substr(index, 1)
	return grouped
