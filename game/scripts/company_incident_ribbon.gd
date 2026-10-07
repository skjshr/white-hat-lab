extends Control
## Persistent, read-only deadline strip for accepted priority-response work.

signal route_requested(contract_id: String, target_index: int, queue_id: String)
signal board_requested

const UI = preload("res://scripts/ui_theme.gd")
const Watch = preload("res://scripts/company_incident_watch.gd")

const PAPER := Color("fbf6e9")
const PAPER_EDGE := Color("d9c79d")
const INK := Color("3c3830")
const MUTED := Color("6f6a5e")
const AMBER := Color("a66d1f")
const AMBER_WASH := Color("f5e9ca")
const DEEP_RED := Color("9d302a")
const GREEN := Color("2d684a")
const TRACK := Color("d8d2c4")

var _game: Object
var _factor := 1.0
var _snapshot: Dictionary = {}
var _incident: Dictionary = {}
var _queue_data: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _unknown_button: Button
var _other_button: Button
var _has_built := false
var _is_unknown := true
var _money_known := false
var _more_count := 0
var _incident_client := ""
var _pending_delivery := false


func setup(game: Object, scale: float) -> void:
	var next_factor := maxf(0.75, scale)
	if not is_equal_approx(_factor, next_factor): _snapshot.clear()
	if is_instance_valid(_game) and _game.has_signal("changed") and _game.changed.is_connected(_on_game_changed):
		_game.changed.disconnect(_on_game_changed)
	_game = game
	_factor = next_factor
	var local_theme := Theme.new()
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		local_theme.set_color(key, "Button", INK)
	local_theme.set_color("font_color", "TooltipLabel", INK)
	local_theme.set_font("font", "TooltipLabel", UI.font(500))
	local_theme.set_font_size("font_size", "TooltipLabel", roundi(13 * _factor))
	local_theme.set_stylebox("panel", "TooltipPanel", UI.style(PAPER, PAPER_EDGE, 9, 8, 4))
	theme = local_theme
	_ensure_controls()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if is_instance_valid(_game) and _game.has_signal("changed") and not _game.changed.is_connected(_on_game_changed):
		_game.changed.connect(_on_game_changed)
	refresh()


func _exit_tree() -> void:
	if is_instance_valid(_game) and _game.has_signal("changed") and _game.changed.is_connected(_on_game_changed):
		_game.changed.disconnect(_on_game_changed)


func _ensure_controls() -> void:
	if _has_built: return
	_has_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 2:
		var button := Button.new()
		button.name = "IncidentQueue_%d" % index
		button.text = ""
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_override("font", UI.font(500))
		button.add_theme_font_size_override("font_size", roundi(12 * _factor))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_focus_color", INK)
		button.add_theme_stylebox_override("normal", UI.style(PAPER, PAPER_EDGE, 7, 4, 3))
		button.add_theme_stylebox_override("hover", UI.style(AMBER_WASH, AMBER, 7, 4, 3))
		button.add_theme_stylebox_override("pressed", UI.style(AMBER_WASH, AMBER, 7, 4, 3))
		var focus_style := UI.style(Color.TRANSPARENT, INK, 7, 4, 3)
		focus_style.set_border_width_all(2)
		button.add_theme_stylebox_override("focus", focus_style)
		button.draw.connect(_draw_queue.bind(button, index))
		button.pressed.connect(_on_queue_pressed.bind(index))
		add_child(button)
		_buttons.append(button)
	_unknown_button = Button.new()
	_unknown_button.name = "IncidentRecordReview"
	_unknown_button.text = "受付記録を確認"
	_unknown_button.focus_mode = Control.FOCUS_ALL
	_unknown_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_unknown_button.add_theme_font_override("font", UI.font(500))
	_unknown_button.add_theme_font_size_override("font_size", roundi(13 * _factor))
	_unknown_button.add_theme_stylebox_override("normal", UI.style(PAPER, AMBER, 12, 7, 3))
	_unknown_button.add_theme_stylebox_override("hover", UI.style(AMBER_WASH, AMBER, 12, 7, 3))
	_unknown_button.add_theme_stylebox_override("pressed", UI.style(AMBER_WASH, AMBER, 12, 7, 3))
	var unknown_focus := UI.style(Color.TRANSPARENT, INK, 12, 7, 3)
	unknown_focus.set_border_width_all(2)
	_unknown_button.add_theme_stylebox_override("focus", unknown_focus)
	_unknown_button.pressed.connect(_on_unknown_pressed)
	add_child(_unknown_button)
	_other_button = Button.new()
	_other_button.name = "IncidentOtherCases"
	_other_button.focus_mode = Control.FOCUS_ALL
	_other_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_other_button.add_theme_font_override("font", UI.font(500))
	_other_button.add_theme_font_size_override("font_size", roundi(10 * _factor))
	_other_button.add_theme_stylebox_override("normal", UI.style(Color("fffaf0"), PAPER_EDGE, 5, 3, 3))
	_other_button.add_theme_stylebox_override("hover", UI.style(AMBER_WASH, AMBER, 5, 3, 3))
	_other_button.add_theme_stylebox_override("pressed", UI.style(AMBER_WASH, AMBER, 5, 3, 3))
	var other_focus := UI.style(Color.TRANSPARENT, INK, 5, 3, 3)
	other_focus.set_border_width_all(2)
	_other_button.add_theme_stylebox_override("focus", other_focus)
	_other_button.pressed.connect(func(): board_requested.emit())
	add_child(_other_button)
	if not resized.is_connected(_layout): resized.connect(_layout)


func _on_game_changed() -> void:
	refresh()


func refresh() -> void:
	_ensure_controls()
	if not is_instance_valid(_game):
		_apply_snapshot({"visible": false})
		return
	var next: Variant = Watch.snapshot(_game)
	if not next is Dictionary: next = {}
	if next == _snapshot: return
	_snapshot = next.duplicate(true)
	_apply_snapshot(_snapshot)


func _apply_snapshot(snapshot: Dictionary) -> void:
	var focus_name := ""
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if is_instance_valid(focused) and (focused == self or is_ancestor_of(focused)):
		focus_name = str(focused.name)
	var incidents_value: Variant = snapshot.get("incidents", [])
	var incidents: Array = incidents_value if incidents_value is Array else []
	var open_count := int(snapshot.get("open_count", incidents.size()))
	visible = bool(snapshot.get("visible", open_count > 0)) and open_count > 0
	if not visible:
		custom_minimum_size.y = 0
		for button in _buttons: button.visible = false
		_unknown_button.visible = false
		_other_button.visible = false
		queue_redraw()
		return
	custom_minimum_size.y = 64 * _factor
	_incident = _choose_incident(incidents, snapshot.get("priority", {}))
	_is_unknown = not _valid_incident(_incident)
	_money_known = _valid_costs(_incident.get("costs", {}))
	_incident_client = str(_incident.get("client", ""))
	_queue_data.clear()
	if not _is_unknown:
		for item in _incident.get("queues", []):
			_queue_data.append(item.duplicate(true))
		if _queue_data.size() > _buttons.size(): _is_unknown = true
		for item in _queue_data:
			if not _valid_queue(item): _is_unknown = true
	_pending_delivery = not _is_unknown and not _queue_data.is_empty()
	if _pending_delivery:
		for item in _queue_data:
			if not bool(item.get("received", false)):
				_pending_delivery = false
				break
	var visible_count := incidents.size()
	_more_count = maxi(0, maxi(open_count, visible_count) - 1)
	_unknown_button.visible = _is_unknown
	for index in _buttons.size():
		var active := not _is_unknown and index < _queue_data.size()
		var button: Button = _buttons[index]
		button.visible = active
		if active:
			var item: Dictionary = _queue_data[index]
			button.set_meta("queue_id", str(item.get("id", "")))
			button.tooltip_text = _queue_tooltip(item)
			button.add_theme_font_size_override("font_size", roundi(12 * _factor))
	_other_button.visible = _more_count > 0
	_other_button.text = "ほか%d件" % _more_count
	_other_button.add_theme_font_size_override("font_size", roundi(10 * _factor))
	_update_cost_tooltip()
	_layout()
	queue_redraw()
	for button in _buttons: button.queue_redraw()
	if not focus_name.is_empty(): call_deferred("_restore_focus", focus_name)


func _restore_focus(node_name: String) -> void:
	var node := find_child(node_name, true, false)
	if node is Control and node.visible and node.focus_mode != Control.FOCUS_NONE:
		node.grab_focus()
		return
	if _is_unknown and _unknown_button.visible:
		_unknown_button.grab_focus()
	elif not _buttons.is_empty():
		for button in _buttons:
			if button.visible:
				button.grab_focus()
				return


func _choose_incident(incidents: Array, priority_value: Variant) -> Dictionary:
	var priority: Dictionary = priority_value if priority_value is Dictionary else {}
	var priority_contract := str(priority.get("contract_id", ""))
	var priority_target := int(priority.get("target_index", -1))
	if not priority_contract.is_empty():
		for item in incidents:
			if item is Dictionary and str(item.get("contract_id", "")) == priority_contract and int(item.get("target_index", -1)) == priority_target:
				return item.duplicate(true)
	for item in incidents:
		if item is Dictionary: return item.duplicate(true)
	return {
		"contract_id": priority_contract,
		"target_index": priority_target,
		"client": "",
		"available": false
	}


func _valid_incident(item: Dictionary) -> bool:
	if item.is_empty() or not bool(item.get("available", false)): return false
	for key in ["contract_id", "target_index", "client", "title", "elapsed", "queues", "costs"]:
		if not item.has(key): return false
	if str(item.get("contract_id", "")).is_empty() or not _is_integer(item.get("target_index")) or int(item.target_index) < 0 or not _is_number(item.get("elapsed")) or float(item.elapsed) < 0: return false
	if not item.get("queues") is Array or item.queues.is_empty() or item.queues.size() > 2: return false
	return true


func _valid_queue(item: Dictionary) -> bool:
	for key in ["id", "label", "deadline", "remaining", "late", "received", "received_count", "approved_count", "late_cost", "loss_cost"]:
		if not item.has(key): return false
	if str(item.id).is_empty() or not _is_number(item.deadline) or float(item.deadline) < 0 or not _is_number(item.remaining) or float(item.remaining) < 0: return false
	if typeof(item.late) != TYPE_BOOL or typeof(item.received) != TYPE_BOOL: return false
	for key in ["received_count", "approved_count", "late_cost", "loss_cost"]:
		if not _is_integer(item.get(key)) or int(item[key]) < 0: return false
	if int(item.approved_count) < 1 or int(item.received_count) > int(item.approved_count): return false
	return true


func _valid_costs(value: Variant) -> bool:
	if not value is Dictionary or not bool(value.get("available", false)): return false
	for key in ["business", "impact", "manual", "assistant", "total"]:
		if not _is_integer(value.get(key)) or int(value[key]) < 0: return false
	return true


func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT and is_finite(float(value)) and floorf(float(value)) == float(value)


func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _update_cost_tooltip() -> void:
	if _money_known:
		var costs: Dictionary = _incident.costs
		_unknown_button.tooltip_text = "受付記録を開いて内容を確認します。"
		_other_button.tooltip_text = _cost_breakdown(costs)
		for button in _buttons:
			var index := _buttons.find(button)
			if index >= 0 and index < _queue_data.size():
				button.tooltip_text = _queue_tooltip(_queue_data[index]) + "\n" + _cost_breakdown(costs)
	else:
		_unknown_button.tooltip_text = "追加費用の内訳を確認できません。案件記録を開いてください。"
		_other_button.tooltip_text = _unknown_button.tooltip_text


func _cost_breakdown(costs: Dictionary) -> String:
	return "確定追加費用 ¥%s\n事業損失 ¥%s · 影響費 ¥%s\n手作業 ¥%s · 助手 ¥%s" % [
		_group_number(int(costs.total)), _group_number(int(costs.business)), _group_number(int(costs.impact)),
		_group_number(int(costs.manual)), _group_number(int(costs.assistant))
	]


func _queue_tooltip(item: Dictionary) -> String:
	var text := str(item.get("label", "受付")) + " · 横線は経過、〆は受付期限です。"
	if bool(item.get("late", false)): text += "\n遅延費用 ¥%s / 確定損失 ¥%s" % [_group_number(int(item.get("late_cost", 0))), _group_number(int(item.get("loss_cost", 0)))]
	return text


func _group_number(value: int) -> String:
	var raw := str(value)
	var result := ""
	while raw.length() > 3:
		result = "," + raw.substr(raw.length() - 3, 3) + result
		raw = raw.substr(0, raw.length() - 3)
	return raw + result


func _layout() -> void:
	if size.x <= 0 or not _has_built: return
	var s := _factor
	var width := size.x / s
	var left_width := clampf(width * 0.28, 196, 244)
	var gap := 5.0
	var queue_start := left_width + 7
	var queue_area := maxf(0, width - queue_start - 8)
	var shown := 0
	for button in _buttons:
		if not button.visible: continue
		var button_width := (queue_area - gap * maxf(0, _queue_data.size() - 1)) / maxf(1, _queue_data.size())
		button.position = Vector2((queue_start + shown * (button_width + gap)) * s, 4 * s)
		button.size = Vector2(button_width * s, 56 * s)
		button.add_theme_font_size_override("font_size", roundi(14 * s))
		shown += 1
	if _unknown_button.visible:
		_unknown_button.position = Vector2(queue_start * s, 8 * s)
		_unknown_button.size = Vector2(queue_area * s, 48 * s)
		_unknown_button.add_theme_font_size_override("font_size", roundi(13 * s))
	_other_button.position = Vector2(maxf(0, left_width - 77) * s, 4 * s)
	_other_button.size = Vector2(70 * s, 22 * s)
	_other_button.add_theme_font_size_override("font_size", roundi(10 * s))
	queue_redraw()


func _draw() -> void:
	if not visible: return
	var s := _factor
	var width := size.x / s
	var height := size.y / s
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_rect(Rect2(Vector2.ZERO, size), PAPER_EDGE, false, s)
	var left_width := clampf(width * 0.28, 196, 244)
	draw_line(Vector2(left_width * s, 5 * s), Vector2(left_width * s, (height - 5) * s), PAPER_EDGE, s)
	UI.font(500).draw_string(get_canvas_item(), Vector2(11 * s, 19 * s), "緊急受付", HORIZONTAL_ALIGNMENT_LEFT, left_width * s - 98 * s, roundi(15 * s), INK)
	UI.font(500).draw_string(get_canvas_item(), Vector2(11 * s, 38 * s), _incident_client, HORIZONTAL_ALIGNMENT_LEFT, (left_width - 90) * s, roundi(13 * s), INK)
	var state := "記録確認" if _is_unknown or not _money_known else "納品待ち" if _pending_delivery else "期限対応中"
	UI.font(500).draw_string(get_canvas_item(), Vector2((left_width - 78) * s, 38 * s), state, HORIZONTAL_ALIGNMENT_LEFT, 68 * s, roundi(11 * s), INK)
	var cost_text := "確定追加 ¥%s" % _group_number(int(_incident.costs.total)) if _money_known else "追加費用不明"
	UI.font(500).draw_string(get_canvas_item(), Vector2(11 * s, 57 * s), cost_text, HORIZONTAL_ALIGNMENT_LEFT, (left_width - 16) * s, roundi(12 * s), INK if _money_known else AMBER)


func _draw_queue(button: Button, index: int) -> void:
	if index >= _queue_data.size() or _is_unknown: return
	var item := _queue_data[index]
	var s := _factor
	var width := button.size.x / s
	var label := str(item.get("label", "受付"))
	var remaining := int(item.get("remaining", 0))
	var is_late := bool(item.get("late", false))
	var received := bool(item.get("received", false))
	var elapsed := int(_incident.get("elapsed", 0))
	var deadline := int(item.get("deadline", 0))
	var over := maxi(0, elapsed - deadline)
	var status := "✓受付済" if received else "残り %d分" % remaining
	if is_late:
		status = "✓受付済 · 期限超過" if received else "! %d分超過" % over
	var ink := DEEP_RED if is_late else GREEN if received else INK
	UI.font(500).draw_string(button.get_canvas_item(), Vector2(9 * s, 18 * s), label, HORIZONTAL_ALIGNMENT_LEFT, (width - 18) * s, roundi(14 * s), INK)
	UI.font(500).draw_string(button.get_canvas_item(), Vector2(9 * s, 35 * s), status, HORIZONTAL_ALIGNMENT_LEFT, (width - 18) * s, roundi(13 * s), ink)
	var x0 := 11.0
	var x1 := maxf(x0 + 14, width - 11)
	var y := 45.0
	var span := maxf(1, float(elapsed))
	for queue_value in _queue_data:
		span = maxf(span, float(queue_value.get("deadline", 0)))
	var deadline_x := lerpf(x0, x1, clampf(float(deadline) / span, 0, 1))
	var elapsed_x := lerpf(x0, x1, clampf(float(elapsed) / span, 0, 1))
	button.draw_rect(Rect2(Vector2(x0 * s, y * s), Vector2((x1 - x0) * s, 2 * s)), TRACK)
	button.draw_line(Vector2(deadline_x * s, (y - 4) * s), Vector2(deadline_x * s, (y + 5) * s), AMBER, 2 * s)
	button.draw_circle(Vector2(elapsed_x * s, (y + 1) * s), 3 * s, ink)
	button.draw_string(UI.font(500), Vector2(deadline_x * s - 4 * s, (y - 4) * s), "〆", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(8 * s), AMBER)
	button.draw_string(UI.font(500), Vector2(elapsed_x * s - 3 * s, (y + 9) * s), "今", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(8 * s), INK)


func _on_queue_pressed(index: int) -> void:
	if index >= _queue_data.size() or _is_unknown: return
	var contract_id := str(_incident.get("contract_id", ""))
	var target_index := int(_incident.get("target_index", -1))
	var queue_id := "" if _pending_delivery else str(_buttons[index].get_meta("queue_id", ""))
	if contract_id.is_empty() or target_index < 0 or (queue_id.is_empty() and not _pending_delivery): return
	route_requested.emit(contract_id, target_index, queue_id)


func _on_unknown_pressed() -> void:
	var contract_id := str(_incident.get("contract_id", ""))
	var target_index := int(_incident.get("target_index", -1))
	if contract_id.is_empty() or target_index < 0: return
	route_requested.emit(contract_id, target_index, "")
