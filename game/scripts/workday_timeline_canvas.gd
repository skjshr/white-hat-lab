extends Control
## Shared read-only calendar for accepted work, reception deadlines and
## colleague task windows. Selecting an item emits a route request only.

signal job_selected(key: String)
signal business_selected(key: String, queue_id: String)

const M = preload("res://scripts/management_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")

const PAPER := Color("f8f6ee")
const PAPER_ALT := Color("f1f2ea")
const INK := Color("263b4a")
const MUTED := Color("657781")
const LINE := Color("d4ddd8")
const RULER := Color("294456")
const RULER_TEXT := Color("f5f4ed")
const TEAL := Color("287b70")
const TEAL_LIGHT := Color("c9e2d9")
const RED := Color("b9473a")
const RED_LIGHT := Color("f3dfd7")
const AMBER := Color("986c21")
const AMBER_LIGHT := Color("f2e8cf")

var model: Dictionary = {}
var selected_key := ""
var factor := 1.0
var row_buttons: Dictionary = {}
var business_buttons: Dictionary = {}
var row_layout: Array = []
var logical_height := 0.0
var left_width := 0.0
var label_width := 0.0
var scale_left := 0.0
var plot_right := 0.0
var row_start := 76.0


func configure(value: Dictionary, key: String, scale: float) -> void:
	model = value.duplicate(true)
	selected_key = key
	factor = maxf(0.8, scale)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	_sync_buttons()
	_sync_business_buttons()
	_layout()
	queue_redraw()


func _sync_buttons() -> void:
	var rows: Array = model.get("rows", []) if model.get("rows", []) is Array else []
	var live: Dictionary = {}
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary:
			continue
		var key := str(row.get("key", ""))
		if key.is_empty():
			continue
		live[key] = true
		var button: Button = row_buttons.get(key) as Button
		if not is_instance_valid(button):
			button = Button.new()
			button.name = "WorkdaySelect_" + key.validate_node_name()
			button.toggle_mode = true
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.clip_text = true
			button.clip_contents = true
			button.autowrap_mode = TextServer.AUTOWRAP_OFF
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.focus_mode = Control.FOCUS_ALL
			button.pressed.connect(_select_job.bind(key))
			add_child(button)
			row_buttons[key] = button
		var client := str(row.get("client", "顧客名不明"))
		var title := str(row.get("title", "仕事名不明"))
		var status := str(row.get("status_label", "")).strip_edges()
		if status.is_empty():
			status = _row_status_label(row)
		button.text = client + "\n" + title
		button.tooltip_text = client + " / " + title + "\n" + _job_kind_label(str(row.get("kind", "unknown"))) + "\n状態: " + status
		button.set_pressed_no_signal(key == selected_key)
		M.button(button, "tab", key == selected_key)
		button.add_theme_font_override("font", UI.font(500))
		button.add_theme_font_size_override("font_size", roundi(14.0 * factor))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
		button.add_theme_color_override("font_hover_pressed_color", INK)
		button.add_theme_color_override("font_focus_color", INK)
		button.add_theme_constant_override("line_spacing", roundi(1.0 * factor))
	for old_key in row_buttons.keys():
		if live.has(str(old_key)):
			continue
		var old_button: Button = row_buttons[old_key]
		row_buttons.erase(old_key)
		if is_instance_valid(old_button):
			remove_child(old_button)
			old_button.queue_free()


func _select_job(key: String) -> void:
	job_selected.emit(key)


func _sync_business_buttons() -> void:
	var rows: Array = model.get("rows", []) if model.get("rows", []) is Array else []
	var live: Dictionary = {}
	for row_value in rows:
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var key := str(row.get("key", ""))
		var markers: Array = row.get("markers", []) if row.get("markers", []) is Array else []
		for marker_index in markers.size():
			if not markers[marker_index] is Dictionary:
				continue
			var marker: Dictionary = markers[marker_index]
			if str(marker.get("kind", "")) != "business":
				continue
			var queue_id := str(marker.get("id", ""))
			var button_key := key + "|" + (queue_id if not queue_id.is_empty() else "unknown-%d" % marker_index)
			live[button_key] = true
			var button: Button = business_buttons.get(button_key) as Button
			if not is_instance_valid(button):
				button = Button.new()
				button.name = "WorkdayBusinessSelect_" + button_key.validate_node_name()
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.clip_text = true
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				button.focus_mode = Control.FOCUS_ALL
				button.pressed.connect(_select_business.bind(key, queue_id))
				add_child(button)
				business_buttons[button_key] = button
			var label := str(marker.get("label", "受付"))
			var known := bool(marker.get("known", false)) and int(marker.get("absolute", -1)) >= 0
			var received := bool(marker.get("received", false))
			var late := bool(marker.get("late", false))
			var status := "!遅延受付" if received and late else "✓受付済" if received else "!期限超過" if late else "受付期限"
			var when := _time_label(int(marker.get("absolute", -1))) if known else "時刻不明"
			button.text = "◆ %s\n%s · %s" % [label, status, when]
			var actual_cost := int(marker.get("cost", -1))
			var cost_detail := "\n発生補償 ¥%d" % actual_cost if actual_cost >= 0 else ""
			button.tooltip_text = "%s / %s\n%s · %s%s" % [str(row.get("client", "顧客名不明")), str(row.get("title", "仕事名不明")), status, when, cost_detail]
			button.disabled = queue_id.is_empty()
			M.button(button, "quiet", key == selected_key)
			button.add_theme_font_override("font", UI.font(500))
			button.add_theme_font_size_override("font_size", roundi(12.0 * factor))
			button.add_theme_color_override("font_color", RED if late else INK)
			button.add_theme_color_override("font_hover_color", INK)
			button.add_theme_color_override("font_pressed_color", INK)
			button.add_theme_color_override("font_hover_pressed_color", INK)
			button.add_theme_color_override("font_focus_color", INK)
	for old_key in business_buttons.keys():
		if live.has(str(old_key)):
			continue
		var old_button: Button = business_buttons[old_key]
		business_buttons.erase(old_key)
		if is_instance_valid(old_button):
			remove_child(old_button)
			old_button.queue_free()


func _select_business(key: String, queue_id: String) -> void:
	if not queue_id.is_empty():
		business_selected.emit(key, queue_id)


func _layout() -> void:
	if size.x <= 0.0:
		return
	var width := size.x / factor
	left_width = clampf(width * 0.29, 166.0, 240.0)
	var plot_width := maxf(120.0, width - left_width - 24.0)
	label_width = clampf(plot_width * 0.30, 96.0, 152.0)
	scale_left = left_width + 12.0 + label_width
	plot_right = width - 12.0
	row_layout.clear()
	var y := row_start
	var rows: Array = model.get("rows", []) if model.get("rows", []) is Array else []
	for row_value in rows:
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var row_height := _row_height(row)
		row_layout.append({"row":row,"top":y,"height":row_height})
		var key := str(row.get("key", ""))
		var button: Button = row_buttons.get(key) as Button
		if is_instance_valid(button):
			button.position = Vector2(8.0, y + 2.0) * factor
			button.size = Vector2(maxf(64.0, left_width - 15.0), row_height - 4.0) * factor
			button.custom_minimum_size = Vector2(maxf(64.0, left_width - 15.0), row_height - 4.0) * factor
		var markers: Array = row.get("markers", []) if row.get("markers", []) is Array else []
		var marker_lane := 0
		for marker_index in markers.size():
			if not markers[marker_index] is Dictionary:
				continue
			var marker: Dictionary = markers[marker_index]
			var lane_height := _marker_lane_height(marker)
			if str(marker.get("kind", "")) == "business":
				var queue_id := str(marker.get("id", ""))
				var business_key := key + "|" + (queue_id if not queue_id.is_empty() else "unknown-%d" % marker_index)
				var business_button: Button = business_buttons.get(business_key) as Button
				if is_instance_valid(business_button):
					business_button.position = Vector2(left_width + 2.0, y + 13.0 + marker_lane) * factor
					business_button.size = Vector2(maxf(54.0, label_width + 4.0), lane_height) * factor
					business_button.custom_minimum_size = Vector2(maxf(54.0, label_width + 4.0), lane_height) * factor
			marker_lane += lane_height
		y += row_height
	logical_height = maxf(112.0, y + 8.0)
	custom_minimum_size = Vector2(0.0, logical_height * factor)
	queue_redraw()


func _row_height(row: Dictionary) -> float:
	if bool(row.get("completed", false)) or bool(row.get("draft", false)):
		return 54.0
	var markers: Array = row.get("markers", []) if row.get("markers", []) is Array else []
	var segments: Array = row.get("segments", []) if row.get("segments", []) is Array else []
	var lane_height := 0.0
	for marker in markers:
		if marker is Dictionary:
			lane_height += _marker_lane_height(marker)
	lane_height += 24.0 * float(segments.size())
	return maxf(54.0, 31.0 + lane_height)


func _marker_lane_height(marker: Dictionary) -> float:
	return 46.0 if str(marker.get("kind", "")) == "business" else 20.0


func _draw() -> void:
	if size.x <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(factor, factor))
	var width := size.x / factor
	var height := maxf(size.y / factor, logical_height)
	draw_rect(Rect2(0.0, 0.0, width, height), PAPER)
	draw_line(Vector2(0.0, 0.5), Vector2(width, 0.5), LINE, 1.0)
	_text(Vector2(10.0, 21.0), "今日の仕事", 16, INK, left_width - 15.0)
	_draw_legend(width)
	_draw_axis(height)
	_draw_rows(width, height)
	_draw_now_line(height)


func _draw_legend(width: float) -> void:
	var y := 43.0
	var x := 10.0
	_draw_triangle(Vector2(x + 5.0, y - 4.0), TEAL, 4.0)
	x += 13.0
	_text(Vector2(x, y), "納品", 12, MUTED, 42.0)
	x += 48.0
	_draw_diamond(Vector2(x + 5.0, y - 4.0), RED, 4.0)
	x += 13.0
	_text(Vector2(x, y), "受付", 12, MUTED, 42.0)
	x += 48.0
	draw_rect(Rect2(x, y - 9.0, 15.0, 7.0), TEAL)
	x += 20.0
	_text(Vector2(x, y), "同僚の工程（納品別）", 12, MUTED, maxf(0.0, width - x - 12.0))


func _draw_axis(height: float) -> void:
	var axis_start := int(model.get("axis_start", -1))
	var axis_end := int(model.get("axis_end", -1))
	var now := int(model.get("now_absolute", -1))
	var plot_width := plot_right - scale_left
	if not bool(model.get("available", false)) or axis_start < 0 or axis_end <= axis_start or plot_width <= 20.0:
		_text(Vector2(scale_left, 61.0), "時間軸不明", 12, MUTED, plot_width)
		return
	var ruler_y := 66.0
	draw_rect(Rect2(scale_left, ruler_y - 4.0, plot_width, 8.0), RULER)
	var first_tick := int(ceil(float(axis_start) / 15.0) * 15.0)
	var tick := first_tick
	var guard := 0
	var now_x := _time_x(now if now >= 0 else axis_start)
	var now_label := "今 " + _time_label(now)
	var now_label_max_width := minf(96.0, maxf(0.0, plot_right - now_x))
	var now_label_width := minf(UI.font(500).get_string_size(now_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, now_label_max_width)
	var now_label_right := now_x + 5.0 + now_label_width
	while tick <= axis_end and guard < 64:
		var x := _time_x(tick)
		var major := posmod(tick, 60) == 0
		var tick_bottom := ruler_y + (8.0 if major else 4.0)
		draw_line(Vector2(x, ruler_y - 5.0), Vector2(x, tick_bottom), RULER_TEXT if major else RULER, 1.0)
		if major and tick > axis_start:
			var label_left := clampf(x - 32.0, scale_left, maxf(scale_left, plot_right - 68.0))
			if label_left > now_label_right + 8.0 and label_left < plot_right - 12.0:
				_text(Vector2(label_left, 56.0), _time_label(tick), 12, MUTED, minf(68.0, plot_right - label_left))
		tick += 15
		guard += 1


func _draw_now_line(height: float) -> void:
	var axis_start := int(model.get("axis_start", -1))
	if not bool(model.get("available", false)) or axis_start < 0:
		return
	var now := int(model.get("now_absolute", axis_start))
	var now_x := _time_x(now)
	draw_line(Vector2(now_x, 60.0), Vector2(now_x, height - 2.0), RULER, 2.0)
	_draw_triangle(Vector2(now_x, 60.0), RULER, 5.0)
	_text(Vector2(now_x + 5.0, 56.0), "今 " + _time_label(now), 12, INK, minf(96.0, plot_right - now_x))


func _draw_rows(width: float, height: float) -> void:
	if row_layout.is_empty():
		_text(Vector2(scale_left, 102.0), "今日の仕事はありません", 13, MUTED, width - scale_left - 12.0)
		return
	for index in row_layout.size():
		var entry: Dictionary = row_layout[index]
		var row: Dictionary = entry.row
		var top := float(entry.top)
		var row_height := float(entry.height)
		var key := str(row.get("key", ""))
		if key == selected_key:
			draw_rect(Rect2(0.0, top, width, row_height), PAPER_ALT)
		elif posmod(index, 2) == 1:
			draw_rect(Rect2(0.0, top, width, row_height), Color("f5f4ec"))
		draw_line(Vector2(0.0, top + row_height), Vector2(width, top + row_height), LINE, 1.0)
		if bool(row.get("completed", false)) or bool(row.get("draft", false)):
			_draw_compact_row(row, top, row_height)
		else:
			_draw_active_row(row, top, row_height)


func _draw_compact_row(row: Dictionary, top: float, row_height: float) -> void:
	var kind := str(row.get("kind", "unknown"))
	var status := "請求待ち" if bool(row.get("draft", false)) else "保守記録あり" if kind == "maintenance" and str(row.get("status", "")) == "legacy" else "✓ 点検完了" if kind == "maintenance" else "✓ 納品済み"
	var fee := int(row.get("fee", -1))
	if bool(row.get("draft", false)) and fee >= 0:
		status += " · ¥%d" % fee
	_text(Vector2(scale_left, top + row_height * 0.62), status, 12, M.ACCENT if bool(row.get("completed", false)) else AMBER, plot_right - scale_left - 8.0)


func _draw_active_row(row: Dictionary, top: float, row_height: float) -> void:
	var markers: Array = row.get("markers", []) if row.get("markers", []) is Array else []
	var segments: Array = row.get("segments", []) if row.get("segments", []) is Array else []
	var marker_offset := 0.0
	for marker_value in markers:
		if not marker_value is Dictionary:
			continue
		var marker: Dictionary = marker_value
		var y := top + 13.0 + marker_offset + _marker_lane_height(marker) * 0.5
		_draw_marker_lane(marker, y)
		marker_offset += _marker_lane_height(marker)
	var segment_base := top + 13.0 + marker_offset + 12.0
	for index in segments.size():
		var segment_value: Variant = segments[index]
		if not segment_value is Dictionary:
			continue
		_draw_segment_lane(segment_value, segment_base + float(index) * 24.0)
	if markers.is_empty() and segments.is_empty():
		_text(Vector2(scale_left, top + row_height * 0.62), "期限・担当時刻不明", 12, MUTED, plot_right - scale_left - 8.0)


func _draw_marker_lane(marker: Dictionary, y: float) -> void:
	var kind := str(marker.get("kind", "unknown"))
	var known := bool(marker.get("known", false)) and int(marker.get("absolute", -1)) >= 0
	var late := bool(marker.get("late", false))
	var received := bool(marker.get("received", false))
	var business := kind == "business"
	var color := RED if late else TEAL if received else RED if business else AMBER
	var label := "受付" if business else "納品"
	var user_label := str(marker.get("label", ""))
	if business and not user_label.is_empty():
		label += " " + user_label
	if received and late and business:
		label = "!遅延受付 " + user_label if not user_label.is_empty() else "!遅延受付"
	elif received:
		label = "✓受付済 " + user_label if business and not user_label.is_empty() else "✓受付済" if business else "納品"
	elif late:
		label += " 超過"
	var absolute := int(marker.get("absolute", -1))
	var marker_x := scale_left
	var outside := ""
	if known:
		marker_x = _time_x(absolute)
		if absolute < int(model.get("axis_start", -1)):
			outside = "← " + _time_label(absolute)
		elif absolute > int(model.get("axis_end", -1)):
			outside = "→ " + _time_label(absolute)
		else:
			outside = _time_label(absolute)
	else:
		outside = "時刻不明"
	var lane_text := ("◆ " if business else "▲ ") + label + " · " + outside
	if not business:
		_text(Vector2(left_width + 5.0, y + 3.5), lane_text, 12, color, label_width - 8.0)
	draw_line(Vector2(scale_left, y), Vector2(plot_right, y), LINE, 1.0)
	if known and absolute >= int(model.get("axis_start", -1)) and absolute <= int(model.get("axis_end", -1)):
		if business:
			_draw_diamond(Vector2(marker_x, y), color, 5.0)
		else:
			_draw_triangle(Vector2(marker_x, y), color, 5.0)
	elif known:
		_draw_edge_arrow(marker_x, y, absolute < int(model.get("axis_start", -1)), color)
	else:
		_draw_unknown_mark(Vector2(scale_left + 5.0, y), color)


func _draw_segment_lane(segment: Dictionary, y: float) -> void:
	var known := bool(segment.get("known", false))
	var name := str(segment.get("name", "担当名不明"))
	var status := str(segment.get("status", "unknown"))
	var risk := str(segment.get("risk", "unknown"))
	var color := RED if risk == "late" else AMBER if risk == "next_day" or status in ["queued", "paused"] else TEAL
	var label := "▬ " + name
	if not known:
		label += " · 時刻不明"
	elif risk == "late":
		label += " · 期限超過"
	elif risk == "next_day":
		label += " · 翌日工程"
	else:
		label += " · 担当工程"
	_text(Vector2(left_width + 5.0, y + 3.5), label, 12, color, label_width - 8.0)
	draw_line(Vector2(scale_left, y), Vector2(plot_right, y), LINE, 1.0)
	if not known:
		_draw_unknown_mark(Vector2(scale_left + 5.0, y), MUTED)
		return
	var start := int(segment.get("start_absolute", -1))
	var finish := int(segment.get("finish_absolute", -1))
	if start < 0 or finish < start:
		_draw_unknown_mark(Vector2(scale_left + 5.0, y), MUTED)
		return
	var x0 := _time_x(start)
	var x1 := _time_x(finish)
	var bar_left := clampf(x0, scale_left, plot_right)
	var bar_right := clampf(x1, scale_left, plot_right)
	if bar_right - bar_left < 4.0:
		bar_right = minf(plot_right, bar_left + 4.0)
	draw_rect(Rect2(bar_left, y - 4.0, maxf(3.0, bar_right - bar_left), 8.0), color)
	draw_line(Vector2(bar_left, y - 6.0), Vector2(bar_left, y + 6.0), INK, 1.2)
	draw_line(Vector2(bar_right, y - 6.0), Vector2(bar_right, y + 6.0), INK, 1.2)
	if start < int(model.get("axis_start", -1)):
		_draw_edge_arrow(scale_left, y, true, color)
	if finish > int(model.get("axis_end", -1)):
		_draw_edge_arrow(plot_right, y, false, color)


func _time_x(absolute: int) -> float:
	var start := int(model.get("axis_start", -1))
	var finish := int(model.get("axis_end", -1))
	if start < 0 or finish <= start:
		return scale_left
	var ratio := clampf(float(absolute - start) / float(finish - start), 0.0, 1.0)
	return lerpf(scale_left, plot_right, ratio)


func _time_label(absolute: int) -> String:
	if absolute < 0:
		return "?"
	var minute := posmod(absolute, 1440)
	var absolute_day := int(floor(float(absolute) / 1440.0))
	var day_delta := absolute_day - int(model.get("day", absolute_day))
	var prefix := ""
	if day_delta == 1:
		prefix = "翌"
	elif day_delta == -1:
		prefix = "前"
	elif day_delta > 1:
		prefix = "+%d日" % day_delta
	elif day_delta < -1:
		prefix = "%d日前" % abs(day_delta)
	return prefix + "%02d:%02d" % [int(minute / 60), posmod(minute, 60)]


func _draw_edge_arrow(x: float, y: float, left: bool, color: Color) -> void:
	var direction := -1.0 if left else 1.0
	var points := PackedVector2Array([
		Vector2(x, y),
		Vector2(x - direction * 8.0, y - 5.0),
		Vector2(x - direction * 8.0, y + 5.0)
	])
	draw_colored_polygon(points, color)


func _draw_triangle(center: Vector2, color: Color, radius: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(center.x, center.y + radius),
		Vector2(center.x - radius, center.y - radius),
		Vector2(center.x + radius, center.y - radius)
	]), color)


func _draw_diamond(center: Vector2, color: Color, radius: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0)
	]), color)


func _draw_unknown_mark(center: Vector2, color: Color) -> void:
	draw_circle(center, 4.5, color, false, 1.5)
	_text(center + Vector2(-4.0, 4.0), "?", 12, color, 10.0)


func _job_kind_label(kind: String) -> String:
	match kind:
		"emergency": return "緊急受付期限を含む仕事"
		"maintenance": return "保守点検"
		"normal": return "通常契約"
		_: return "仕事の種類不明"


func _row_status_label(row: Dictionary) -> String:
	if bool(row.get("draft", false)):
		return "請求待ち"
	if bool(row.get("completed", false)):
		return "保守記録あり" if str(row.get("kind", "")) == "maintenance" and str(row.get("status", "")) == "legacy" else "点検完了" if str(row.get("kind", "")) == "maintenance" else "納品済み"
	match str(row.get("status", "unknown")):
		"pending": return "未配分"
		"queued": return "配分済・待機"
		"working": return "作業中"
		"paused": return "保留"
		"failed": return "要確認"
		"blocked": return "停止中"
		_: return "状態不明"


func _text(at: Vector2, value: String, points: int, color: Color, max_width: float = -1.0) -> void:
	var font: Font = UI.font(500)
	var shown := value
	if max_width > 0.0:
		while shown.length() > 1 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x > max_width:
			shown = shown.left(shown.length() - 2) + "…"
	draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points, color)

