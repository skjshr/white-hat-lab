extends Control
## Pure candidate comparison. Selecting a route never assigns or advances work.
signal member_selected(id: String)
signal self_selected

const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
var job: Dictionary = {}
var people: Array = []
var factor: float = 1.0
var selected_id: String = ""
var person_buttons: Array[Button] = []
var self_button: Button
var source_title: Label
var source_client: Label
var empty_label: Label
var source_width: float = 150.0
var lane_x: float = 192.0
var logical_height: float = 182.0

func configure(selected_job: Dictionary, candidates: Array, scale: float) -> void:
	job = selected_job.duplicate(true); people = candidates.duplicate(true); factor = maxf(.5, scale)
	name = "WorkdayFlowCanvas"; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE; custom_minimum_size.x = 0
	theme = M.theme(factor)
	theme.set_color("font_color", "TooltipLabel", M.WHITE)
	theme.set_stylebox("panel", "TooltipPanel", M.surface(M.DARK, 8))
	for child in get_children(): remove_child(child); child.queue_free()
	person_buttons.clear()
	source_title = _label("WorkdaySourceTitle", _job_title(), 13, M.INK)
	source_client = _label("WorkdaySourceClient", str(job.get("client", "")), 12, M.MUTED)
	var full_title: String = str(job.get("client", "")) + " / " + _job_title()
	source_title.tooltip_text = full_title; source_client.tooltip_text = full_title
	self_button = _button("WorkdaySelf", "自分で対応 → PC", "自分で対応 / PCを開く。完了時刻の予測はありません。")
	self_button.disabled = job.is_empty()
	self_button.pressed.connect(func(): set_selected("self"); self_selected.emit())
	self_button.gui_input.connect(_navigate.bind(-1))
	for index in people.size():
		var person: Dictionary = people[index] if people[index] is Dictionary else {}
		var id: String = str(person.get("id", ""))
		var title: String = str(person.get("name", id))
		var role: String = _role(str(person.get("role", "")))
		var status: String = _status(person)
		var quote: Dictionary = _quote(person)
		var reason: String = str(quote.get("reason", quote.get("blocked_reason", "")))
		var tooltip: String = title + (" / " + role if not role.is_empty() else "") + "\n" + status
		if not reason.is_empty(): tooltip += "\n" + reason
		var button: Button = _button("WorkdayMember_" + id.validate_node_name(), title + (" · " + role if not role.is_empty() else "") + "\n" + status, tooltip)
		button.set_meta("member_id", id)
		button.disabled = job.is_empty() or id.is_empty()
		button.pressed.connect(func(): set_selected(id); member_selected.emit(id))
		button.gui_input.connect(_navigate.bind(index))
		person_buttons.append(button)
	empty_label = _label("WorkdayNoCandidates", "同僚の候補なし", 13, M.MUTED)
	empty_label.visible = people.is_empty()
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout.call_deferred()
	set_selected(selected_id)

func set_selected(id: String) -> void:
	selected_id = id
	if is_instance_valid(self_button): self_button.set_pressed_no_signal(id == "self")
	for button in person_buttons: button.set_pressed_no_signal(str(button.get_meta("member_id", "")) == id)
	queue_redraw()

func _label(id: String, value: String, points: int, color: Color) -> Label:
	var label: Label = Label.new(); label.name = id; label.text = value
	label.add_theme_font_override("font", UI.font(500)); label.add_theme_font_size_override("font_size", roundi(points * factor)); label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.clip_text = true; label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_PASS; add_child(label); return label

func _button(id: String, value: String, tooltip: String) -> Button:
	var button: Button = Button.new(); button.name = id; button.text = value; button.tooltip_text = tooltip
	button.toggle_mode = true; button.clip_text = true; button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", UI.font(500)); button.add_theme_font_size_override("font_size", roundi(13 * factor))
	M.button(button, "quiet")
	# These controls use transparent surfaces; selected text must retain ink.
	for kind in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(kind, M.INK)
	button.add_theme_color_override("font_disabled_color", M.MUTED)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBoxFlat = M.surface(Color.TRANSPARENT, 0)
		style.content_margin_left = (43 if id == "WorkdaySelf" else 49) * factor
		style.content_margin_right = 3 * factor; style.content_margin_top = 2 * factor; style.content_margin_bottom = 2 * factor
		if state == "hover": style.border_width_bottom = 1; style.border_color = M.ACCENT
		button.add_theme_stylebox_override(state, style)
	add_child(button); return button

func _layout() -> void:
	if size.x <= 0: return
	var width: float = size.x / factor
	var backup: bool = not job.get("backup_work", {}).is_empty()
	source_title.visible = not backup
	source_client.visible = not backup
	if backup:
		var columns := 4 if width >= 900 else 2
		var count := people.size() + 1
		var cell := (width - 16.0) / columns
		logical_height = 20 + ceili(float(count) / columns) * 64
		custom_minimum_size.y = logical_height * factor
		self_button.text = "自分で対応 → PC"
		self_button.position = Vector2(8, 20) * factor
		self_button.size = Vector2(cell - 8, 58) * factor
		for index in person_buttons.size():
			var slot := index + 1
			person_buttons[index].position = Vector2(8 + (slot % columns) * cell, 20 + (slot / columns) * 64) * factor
			person_buttons[index].size = Vector2(cell - 8, 58) * factor
		empty_label.visible = false
		queue_redraw()
		return
	source_width = clampf(width * .25, 118, 180)
	lane_x = source_width + 39
	logical_height = maxf(182, 20 + people.size() * 54)
	custom_minimum_size.y = logical_height * factor
	source_client.position = Vector2(10, 5) * factor; source_client.size = Vector2(source_width - 14, 20) * factor
	source_title.position = Vector2(10, 85) * factor; source_title.size = Vector2(source_width - 14, 21) * factor
	self_button.position = Vector2(5, 128) * factor; self_button.size = Vector2(source_width + 10, 42) * factor
	# The narrow label keeps the same action; the complete wording is in tooltip.
	self_button.text = "自分で → PC" if source_width < 170 else "自分で対応 → PC"
	for index in person_buttons.size():
		person_buttons[index].position = Vector2(lane_x, 19 + index * 54) * factor
		person_buttons[index].size = Vector2(maxf(1, width - lane_x - 5), 51) * factor
	empty_label.position = Vector2(lane_x + 3, 55) * factor; empty_label.size = Vector2(maxf(1, width - lane_x - 8), 26) * factor
	queue_redraw()

func _draw() -> void:
	if size.x <= 0: return
	draw_set_transform(Vector2.ZERO, 0, Vector2(factor, factor))
	var width: float = size.x / factor
	if not job.get("backup_work", {}).is_empty():
		_draw_backup_dispatch(width)
		return
	var source_center: Vector2 = Vector2(source_width * .5, 55)
	var available: bool = not job.is_empty()
	var source_color: Color = M.INK if available else M.MUTED
	if str(job.get("kind", "")) == "maintenance": _equipment(source_center, source_color)
	else: _document(source_center, source_color, not available)
	var exit_point: Vector2 = Vector2(source_width - 8, 56)
	var fork_x: float = source_width + 20
	draw_line(source_center + Vector2(28, 0), exit_point, M.LINE, 2)
	_text(Vector2(lane_x + 2, 13), "担当者へ · 作業終了の見込み", 11, M.MUTED)
	if not people.is_empty():
		var last_y: float = 44 + (people.size() - 1) * 54
		draw_line(exit_point, Vector2(fork_x, 56), M.LINE, 2)
		draw_line(Vector2(fork_x, minf(44, 56)), Vector2(fork_x, maxf(last_y, 56)), M.LINE, 1)
	for index in people.size():
		var person: Dictionary = people[index] if people[index] is Dictionary else {}
		var id: String = str(person.get("id", ""))
		var quote: Dictionary = _quote(person)
		var measured: bool = quote.has("ok") and available
		var assigned: bool = str(quote.get("activity", "")) in ["working", "queued", "paused"]
		var blocked: bool = measured and not bool(quote.get("ok", false)) and not assigned
		var uncertain: bool = measured and not blocked and not assigned and (str(quote.get("risk", "")) == "blocked" or int(quote.get("finish_day", -1)) < 0 or int(quote.get("finish_minute", -1)) < 0)
		var attention: bool = str(quote.get("risk", "")) in ["late", "next_day"]
		var chosen: bool = selected_id == id and not id.is_empty()
		var color: Color = M.WARNING if attention else M.MUTED if blocked or uncertain or not measured else M.ACCENT
		var y: float = 44 + index * 54
		var avatar: Vector2 = Vector2(lane_x + 20, y)
		var path_end: Vector2 = Vector2(lane_x + 1, y)
		draw_dashed_line(Vector2(fork_x, y), path_end - Vector2(4, 0), color, 2 if chosen else 1, 4)
		if blocked:
			draw_line(path_end + Vector2(-9, -4), path_end + Vector2(-1, 4), color, 2)
			draw_line(path_end + Vector2(-9, 4), path_end + Vector2(-1, -4), color, 2)
		elif uncertain: _text(path_end + Vector2(-12, 4), "?", 12, color)
		else: _arrow(path_end - Vector2(3, 0), color)
		_person(avatar, color, chosen)
		draw_line(Vector2(lane_x + 47, y + 25), Vector2(width - 8, y + 25), M.LINE, 1)
		if chosen: _text(Vector2(lane_x + 5, y + 6), "✓", 12, color)
	var pc_color: Color = M.ACCENT if selected_id == "self" else M.INK if available else M.MUTED
	draw_dashed_line(source_center - Vector2(28, 0), Vector2(4, source_center.y), pc_color, 1, 4)
	draw_dashed_line(Vector2(4, source_center.y), Vector2(4, 117), pc_color, 1, 4)
	draw_line(Vector2(4, 117), Vector2(26, 117), pc_color, 1)
	draw_line(Vector2(26, 117), Vector2(26, 133), pc_color, 1)
	_arrow(Vector2(26, 133), pc_color, true)
	_pc(Vector2(26, 149), pc_color)
	if selected_id == "self": draw_arc(Vector2(26, 149), 21, 0, TAU, 32, pc_color, 2)

func _job_title() -> String:
	if job.is_empty(): return "仕事を選択"
	return str(job.get("label", job.get("title", "保守点検" if str(job.get("kind", "")) == "maintenance" else job.get("id", "仕事"))))

func _draw_backup_dispatch(width: float) -> void:
	_text(Vector2(9, 13), "配分先 · 作業終了の見込み", 11, M.MUTED)
	var columns := 4 if width >= 900 else 2
	var cell := (width - 16.0) / columns
	for slot in people.size() + 1:
		var at := Vector2(8 + (slot % columns) * cell, 20 + (slot / columns) * 64)
		var id := "self" if slot == 0 else str(people[slot - 1].get("id", ""))
		var selected := selected_id == id
		var color: Color = M.ACCENT if selected else M.INK
		var center := at + Vector2(24, 28)
		if slot == 0:
			_pc(center, color)
			if selected: draw_arc(center, 21, 0, TAU, 32, color, 2)
		else: _person(center, color, selected)
		draw_line(at + Vector2(1, 59), at + Vector2(cell - 9, 59), M.ACCENT if selected else M.LINE, 2 if selected else 1)

func _quote(person: Dictionary) -> Dictionary:
	var value: Variant = person.get("quote", {})
	return value if value is Dictionary else {}

func _status(person: Dictionary) -> String:
	if job.is_empty(): return "— 仕事未選択"
	var quote: Dictionary = _quote(person)
	var activity := str(quote.get("activity", ""))
	if activity in ["working", "queued", "paused"]:
		return {"working":"▶ 作業中", "queued":"待機列に配分済み", "paused":"Ⅱ 中断中"}[activity]
	if not quote.has("ok"): return "? 見込みなし"
	if not bool(quote.get("ok", false)): return "× 引受不可"
	var minute: int = int(quote.get("finish_minute", -1))
	var day: int = int(quote.get("finish_day", -1))
	var risk: String = str(quote.get("risk", ""))
	if minute < 0 or day < 0 or risk == "blocked": return "? 終了時刻未定"
	var prefix: String = "! " if risk in ["late", "next_day"] else "→ "
	var duration: float = float(quote.get("duration", quote.get("duration_minutes", 0)))
	return prefix + "DAY%d %02d:%02d · %d分" % [day, posmod(minute, 1440) / 60, posmod(minute, 60), ceili(duration)] + (" · 納期超過" if risk == "late" else " · 翌日へ持越し" if risk == "next_day" else "")

func _role(id: String) -> String:
	return UI.copy("staffing_role_" + id, id) if not id.is_empty() else ""

func _navigate(event: InputEvent, index: int) -> void:
	if not event is InputEventKey or not event.pressed: return
	var target: Button
	if event.keycode == KEY_LEFT: target = self_button
	elif event.keycode == KEY_RIGHT and not person_buttons.is_empty(): target = person_buttons[maxi(0, index)]
	elif event.keycode in [KEY_UP, KEY_DOWN] and not person_buttons.is_empty():
		var step: int = -1 if event.keycode == KEY_UP else 1
		var next: int = posmod(index + step, person_buttons.size())
		target = person_buttons[next]
	if is_instance_valid(target) and not target.disabled:
		target.grab_focus(); accept_event()

func _person(center: Vector2, color: Color, selected: bool) -> void:
	draw_circle(center, 19, M.SELECTED if selected else M.PAPER)
	draw_arc(center, 19, 0, TAU, 32, color, 2 if selected else 1)
	draw_circle(center + Vector2(0, -5), 5, color)
	draw_arc(center + Vector2(0, 10), 9, PI, TAU, 18, color, 3)

func _document(center: Vector2, color: Color, missing: bool) -> void:
	var rect: Rect2 = Rect2(center - Vector2(22, 27), Vector2(44, 54))
	draw_rect(rect, M.CANVAS)
	if missing:
		for y in range(0, 54, 7):
			draw_line(rect.position + Vector2(0, y), rect.position + Vector2(0, mini(y + 4, 54)), color, 1)
	else: draw_rect(rect, color, false, 2)
	draw_line(rect.position + Vector2(28, 0), rect.position + Vector2(28, 12), color, 1)
	draw_line(rect.position + Vector2(28, 12), rect.position + Vector2(44, 12), color, 1)
	for line in range(3): draw_line(center + Vector2(-13, -7 + line * 9), center + Vector2(12, -7 + line * 9), color, 2)
	if missing: _text(center + Vector2(-4, 8), "?", 20, color)

func _equipment(center: Vector2, color: Color) -> void:
	for index in range(3):
		var rect: Rect2 = Rect2(center + Vector2(-27, -26 + index * 18), Vector2(54, 15))
		draw_rect(rect, M.CANVAS); draw_rect(rect, color, false, 1)
		draw_circle(rect.position + Vector2(7, 7), 2, color)
		draw_line(rect.position + Vector2(16, 7), rect.end - Vector2(7, 8), color, 2)

func _pc(center: Vector2, color: Color) -> void:
	draw_rect(Rect2(center - Vector2(15, 12), Vector2(30, 21)), M.PAPER)
	draw_rect(Rect2(center - Vector2(15, 12), Vector2(30, 21)), color, false, 2)
	draw_line(center + Vector2(0, 10), center + Vector2(0, 15), color, 2)
	draw_line(center + Vector2(-10, 15), center + Vector2(10, 15), color, 2)

func _arrow(at: Vector2, color: Color, down: bool = false) -> void:
	var axis: Vector2 = Vector2(0, 1) if down else Vector2(1, 0)
	var side: Vector2 = Vector2(-axis.y, axis.x)
	draw_line(at - axis * 5 + side * 3, at, color, 1)
	draw_line(at - axis * 5 - side * 3, at, color, 1)

func _text(at: Vector2, value: String, points: int, color: Color) -> void:
	draw_string(UI.font(500), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, points, color)
