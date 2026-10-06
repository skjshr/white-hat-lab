extends Control
## A time ruler projected from saved observations; selecting a mark never runs a job.
const UI = preload("res://scripts/ui_theme.gd")
const INK = Color("243b40")
const MUTED = Color("61797c")
const ALERT = Color("a94e25")
const TEAL = Color("187969")
var flow: Dictionary = {}
var factor := 1.0
var selected := ""
var markers: Array[Dictionary] = []
var deadline_button: Button
var horizon := 20.0

func configure(data: Dictionary, scale: float, event_id: String, select_event: Callable, open_desk: Callable) -> void:
	name = "AiEventTimeline"; flow = data.duplicate(true); factor = scale; selected = event_id
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; custom_minimum_size.y = 108 * factor
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Keep the scheduled window stable after it ends; elapsed time remains explicit.
	for event in flow.get("events", []) + flow.get("pending", []): horizon = maxf(horizon, int(event.get("minute", 0)) + 2)
	for event in flow.get("events", []):
		var label := "?"
		var write: Dictionary = event.get("write", {})
		if int(event.get("rows", 0)) > 0: label = "↑ %d行" % int(event.rows)
		elif not write.is_empty(): label = "× 拒否" if int(write.get("status", 0)) >= 400 else "記録"
		var id := str(event.get("id", ""))
		var minute := int(event.get("minute", -1))
		var when := "%d分" % minute if minute >= 0 else "時刻不明"
		var button := _button("%s  %s" % [when, label], "AiEvent_" + id)
		button.pressed.connect(select_event.bind(id))
		button.tooltip_text = "保存した通信の経路を開く / " + id
		button.add_theme_stylebox_override("normal", UI.style(Color("fce8d9") if int(event.get("rows", 0)) > 0 else Color("e5f3ec"), INK if selected == id else Color("b9c9c4"), 6, 3, 2))
		markers.append({"minute":minute,"button":button,"observed":true})
	for event in flow.get("pending", []):
		var minute := int(event.get("minute", -1))
		var when := "%d分" % minute if minute >= 0 else "時刻未定"
		var button := _button("%s  ◇ 入力予定" % when, "AiPending_" + str(event.get("id", "")))
		button.disabled = true; button.tooltip_text = "まだ実行されていない入力"
		markers.append({"minute":minute,"button":button,"observed":false})
	var deadline: Dictionary = flow.get("deadline", {})
	var minute := int(deadline.get("minute", 14)); var now := int(flow.get("now", 0))
	var text := "受付 %d分 / 残り%d分" % [minute, maxi(0, minute - now)]
	match str(deadline.get("status", "waiting")):
		"met": text = "%d分〆 ✓ %d件 / %d分受付" % [minute, int(deadline.get("received_count", 0)), int(deadline.get("received_minute", 0))]
		"late": text = "%d分〆 ! 超過 / ¥%d" % [minute, int(deadline.get("loss_cost", 0))]
		"unknown": text = "%d分〆 ? 受付時刻未確認" % minute
	deadline_button = _button(text, "AiDeadline")
	deadline_button.pressed.connect(open_desk)
	deadline_button.tooltip_text = "問い合わせの受付と保存済み要約を開く"
	if str(deadline.get("status", "")) == "late": deadline_button.add_theme_color_override("font_color", ALERT)
	resized.connect(_layout); _layout.call_deferred()

func _button(text: String, id: String) -> Button:
	var button := Button.new(); button.name = id; button.text = text
	button.add_theme_font_size_override("font_size", roundi(12 * factor))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]: button.add_theme_color_override(key, INK if key != "font_disabled_color" else MUTED)
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color("edf3ef") if key == "normal" else Color("deebe4"), Color("b9c9c4"), 6, 3, 2))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, Color("14649a"), 0, 0, 2))
	add_child(button); return button

func _x(minute: float) -> float:
	return lerpf(90 * factor, size.x - 74 * factor, clampf(minute / horizon, 0, 1))

func _layout() -> void:
	if size.x <= 0: return
	var unknown_index := 0
	for marker in markers:
		var button: Button = marker.button
		button.size = Vector2(128, 30) * factor
		button.position = Vector2(clampf(_x(marker.minute) - button.size.x * .5, 82 * factor, size.x - button.size.x - 4 * factor), 4 * factor)
		if int(marker.minute) < 0:
			button.position.x = (82 + 134 * unknown_index) * factor
			unknown_index += 1
	deadline_button.size = Vector2(226, 30) * factor
	deadline_button.position = Vector2(clampf(_x(int(flow.get("deadline", {}).get("minute", 14))) - deadline_button.size.x * .5, 82 * factor, size.x - deadline_button.size.x - 4 * factor), 73 * factor)
	queue_redraw()

func _text(value: String, point: Vector2, font_size: int, color: Color = INK) -> void:
	draw_string(get_theme_default_font(), point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(font_size * factor), color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("f1f5ef"))
	_text("%02d分" % int(flow.get("now", 0)), Vector2(8, 29) * factor, 23)
	_text("経過", Vector2(10, 48) * factor, 11, MUTED)
	var axis_y := 51 * factor
	draw_line(Vector2(_x(0), axis_y), Vector2(_x(horizon), axis_y), Color("bdccc5"), 3 * factor)
	draw_line(Vector2(_x(0), axis_y), Vector2(_x(int(flow.get("now", 0))), axis_y), TEAL, 3 * factor)
	for minute in range(0, int(horizon) + 1, 2):
		var x := _x(minute)
		draw_line(Vector2(x, axis_y - 3 * factor), Vector2(x, axis_y + 3 * factor), MUTED, factor)
	for marker in markers:
		if int(marker.minute) < 0: continue
		var x := _x(marker.minute)
		draw_line(Vector2(x, 34 * factor), Vector2(x, axis_y), MUTED, factor)
		if marker.observed: draw_circle(Vector2(x, axis_y), 5 * factor, INK)
		else: draw_arc(Vector2(x, axis_y), 5 * factor, 0, TAU, 16, MUTED, 1.5 * factor, true)
	var deadline: Dictionary = flow.get("deadline", {})
	var end := _x(int(deadline.get("minute", 14)))
	draw_line(Vector2(end, axis_y + 5 * factor), Vector2(end, 73 * factor), ALERT, 2 * factor)
	draw_colored_polygon(PackedVector2Array([Vector2(end, axis_y), Vector2(end - 5 * factor, axis_y + 8 * factor), Vector2(end + 5 * factor, axis_y + 8 * factor)]), ALERT)
	_text("問い合わせ", Vector2(8, 93) * factor, 10, MUTED)
