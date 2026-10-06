extends Control
## Policy buttons and saved traffic are separate; rendering never advances the model.
const UI = preload("res://scripts/ui_theme.gd")
const INK = Color("243b40")
const MUTED = Color("61797c")
const LINE = Color("c2d3cf")
const TEAL = Color("187969")
const AMBER = Color("ae6528")
const PAPER = Color("f5f7ef")
const NAMES := {"faq":"公開 FAQ", "dispatch":"配送進捗", "customers":"顧客連絡先", "desk":"社内問い合わせ", "external":"support-drop"}
const COUNTS := {"faq":"24件 / 配送案内", "dispatch":"120行 / 配送状況", "customers":"3行 / 個人情報", "desk":"要約 6件の受付", "external":"外部の保存先"}
var model: Dictionary = {}
var flow: Dictionary = {}
var event: Dictionary = {}
var event_id := ""
var factor := 1.0
var callback: Callable
var record_callback: Callable
var gates: Dictionary = {}
var references: Dictionary = {}
var center := Vector2.ZERO
var compact := false
var send_heading_y := 25.0

func configure(data: Dictionary, scale: float, policy_action: Callable, record_action: Callable = Callable(), selected_event_id: String = "") -> void:
	name = "AiGateCanvas"; model = data.duplicate(true); factor = maxf(.5, scale)
	callback = policy_action; record_callback = record_action; event_id = selected_event_id
	flow = model.get("flow", {}).duplicate(true)
	for candidate in flow.get("events", []):
		if str(candidate.get("id", "")) == event_id: event = candidate.duplicate(true); break
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["faq", "dispatch", "customers", "desk", "external"]:
		var button := Button.new(); button.name = "AiGate_" + key
		button.set_meta("flow_mode", "history" if _historical() else "policy")
		var allowed := bool(model.get("policy", {}).get(key, false))
		var record := _event_record(key)
		if _historical():
			button.tooltip_text = str(NAMES[key]) + " / " + (_record_summary(record) + " / " + str(record.get("record_id", "")) if not record.is_empty() else "この通信の観測なし")
			button.disabled = str(record.get("record_id", "")).is_empty() or not record_callback.is_valid()
			button.pressed.connect(_open_record.bind(str(record.get("record_id", ""))))
		else:
			button.tooltip_text = str(NAMES[key]) + ("の許可を外す · 1分" if allowed else "を許可する · 1分")
			button.pressed.connect(func():
				if callback.is_valid(): callback.call(key, not allowed))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not button.disabled else Control.CURSOR_ARROW
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT if state in ["normal", "disabled"] else Color("d9ebe3"), Color.TRANSPARENT, 0, 0, 1))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, Color("14649a"), 0, 0, 2))
		button.draw.connect(_draw_gate.bind(button, key)); gates[key] = button; add_child(button)
	for key in ["customers", "desk", "external"]:
		var record_id := _reference_id(key)
		if record_id.is_empty() or not record_callback.is_valid(): continue
		var reference := Button.new(); reference.name = "AiFlowRecord_" + key; reference.text = "原記録 ↗"
		reference.set_meta("record_id", record_id); reference.tooltip_text = str(NAMES[key]) + " / " + record_id
		reference.add_theme_font_override("font", UI.font(500)); reference.add_theme_font_size_override("font_size", roundi(12 * factor))
		for color_key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: reference.add_theme_color_override(color_key, INK)
		for state in ["normal", "hover", "pressed"]: reference.add_theme_stylebox_override(state, UI.style(PAPER if state == "normal" else Color("d9ebe3"), LINE, 4, 2, 1))
		reference.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, Color("14649a"), 0, 0, 2))
		reference.pressed.connect(_open_record.bind(record_id)); references[key] = reference; add_child(reference)
	resized.connect(_layout); _layout.call_deferred()

func _historical() -> bool:
	return not event_id.is_empty()

func _event_record(key: String) -> Dictionary:
	return event.get("read" if key == "customers" else "write", {}) if key in ["customers", "external"] else {}

func _reference_id(key: String) -> String:
	if _historical() and key == "customers": return str(event.get("read", {}).get("record_id", ""))
	if not _historical():
		var measurement := _measurement(key)
		if not measurement.is_empty(): return str(measurement.get("id", ""))
	if key == "desk":
		var saved_id := str(flow.get("deadline", {}).get("record_id", ""))
		return saved_id if not saved_id.is_empty() else str(flow.get("business_event", {}).get("record_id", ""))
	if _historical(): return str(event.get("write", {}).get("record_id", ""))
	if key == "customers": return ""
	var latest := ""
	for saved in flow.get("events", []):
		var saved_id := str(saved.get("write", {}).get("record_id", ""))
		if not saved_id.is_empty(): latest = saved_id
	return latest

func _measurement(key: String) -> Dictionary:
	var actions: Array = {"customers":["boundary_read", "scheduled_customer_read"], "external":["boundary_write", "scheduled_external_write"], "desk":["run_business"]}.get(key, [])
	var latest: Dictionary = {}
	for record in model.get("records", []):
		if str(record.get("action", "")) in actions: latest = record
	return latest

func _measurement_text(key: String) -> String:
	var measurement := _measurement(key)
	if measurement.is_empty(): return "? 未実測"
	var stale := int(measurement.get("world_revision", -1)) != int(model.get("world_revision", 0))
	var status := int(measurement.get("status", 0))
	var action := str(measurement.get("action", ""))
	var source := "試験" if action.begins_with("boundary_") else "通信" if action.begins_with("scheduled_") else "実測"
	return ("旧設定 " if stale else "") + source + " " + ("↑ " if status == 200 else "× ") + str(status)

func _open_record(record_id: String) -> void:
	if record_callback.is_valid() and not record_id.is_empty(): record_callback.call(record_id)

func _layout() -> void:
	if size.x <= 0: return
	var width := size.x / factor
	compact = width < 760
	if compact:
		var columns := 3 if width >= 480 else 2
		var item_width := (width - 20 - 12 * (columns - 1)) / columns
		var input_rows := ceili(3.0 / columns)
		for index in 3:
			var item: Button = gates[["faq", "dispatch", "customers"][index]]
			item.position = Vector2(10 + (index % columns) * (item_width + 12), 47 + int(index / columns) * 100) * factor
			item.size = Vector2(item_width, 92) * factor
		center = Vector2(width / 2, 47 + input_rows * 100 + 83) * factor
		send_heading_y = center.y / factor + 85
		var output_width := (width - 42) / 2
		for index in 2:
			var item: Button = gates[["desk", "external"][index]]
			item.position = Vector2(10 + index * (output_width + 22), send_heading_y + 18) * factor
			item.size = Vector2(output_width, 122) * factor
		custom_minimum_size.y = (send_heading_y + 154) * factor
	else:
		var item_width := minf(252, width * .27)
		for index in 3:
			var item: Button = gates[["faq", "dispatch", "customers"][index]]
			item.position = Vector2(18, 43 + index * 96) * factor
			item.size = Vector2(item_width, 92) * factor
		center = Vector2(width * .51, 173) * factor
		for index in 2:
			var item: Button = gates[["desk", "external"][index]]
			item.position = Vector2(width - item_width - 18, 47 + index * 149) * factor
			item.size = Vector2(item_width, 122) * factor
		send_heading_y = 25
		custom_minimum_size.y = 340 * factor
	for key in references:
		var reference: Button = references[key]; var item: Button = gates[key]
		reference.position = item.position + Vector2(item.size.x - 81 * factor, (66 if key == "customers" else 96) * factor)
		reference.size = Vector2(79, 25) * factor
	for item in gates.values(): item.queue_redraw()
	queue_redraw()

func _text(on: Control, value: String, point: Vector2, points: int, color: Color = INK, width: float = -1) -> void:
	on.draw_string(UI.font(500), point, value, HORIZONTAL_ALIGNMENT_LEFT, width, roundi(points * factor), color)

func _record_summary(record: Dictionary) -> String:
	var status := int(record.get("status", 0))
	if status == 0: return "? 未観測"
	return ("↑ " if status == 200 else "× ") + "%d / %d行" % [status, int(record.get("rows", 0))]

func _paper_stack(on: Control, width: float, count: int, tint: Color) -> void:
	for index in mini(6, maxi(0, count)):
		var paper := Rect2(Vector2(width - (15 + index * 18) * factor, 1 * factor), Vector2(13, 17) * factor)
		on.draw_rect(paper, Color("fffdf4")); on.draw_rect(paper, tint, false, factor)
		on.draw_line(paper.position + Vector2(3, 6) * factor, paper.position + Vector2(10, 6) * factor, tint, factor)

func _draw_gate(button: Button, key: String) -> void:
	var allowed := bool(model.get("policy", {}).get(key, false))
	var input := key in ["faq", "dispatch", "customers"]
	var width := button.size.x
	var record := _event_record(key)
	var observed := _historical() and not record.is_empty()
	var tint := (TEAL if int(record.get("status", 0)) == 200 else AMBER) if observed else TEAL if allowed else MUTED
	if _historical() and not observed: tint = LINE
	var object := Rect2(Vector2(2, 10) * factor, Vector2(width - 4 * factor, (54 if input else 80) * factor))
	button.draw_rect(object, Color("e9f1e7") if not _historical() and allowed else Color("edf0ec"))
	button.draw_rect(object, tint, false, factor)
	if input: button.draw_rect(Rect2(Vector2(2, 4) * factor, Vector2(minf(width * .52, 105 * factor), 7 * factor)), tint)
	else:
		var count := int(flow.get("total_rows", 0)) if key == "external" else int(flow.get("deadline", {}).get("received_count", 0))
		_paper_stack(button, width - 5 * factor, count, AMBER if key == "external" else TEAL)
	_text(button, str(NAMES[key]), Vector2(10, 34) * factor, 16, MUTED if _historical() and not observed else INK, width - 20 * factor)
	var detail := _record_summary(record) if _historical() and key in ["customers", "external"] else str(COUNTS[key])
	if not _historical() and key in ["customers", "external", "desk"]: detail = _measurement_text(key)
	if _historical() and key == "desk": detail = "保存済みの受付控え"
	_text(button, detail, Vector2(10, 56) * factor, 13, tint if observed else MUTED, width - 20 * factor)
	if not input:
		var stamp := "保存累計 ↑%d行 / ¥%d" % [int(flow.get("total_rows", 0)), int(flow.get("total_impact_cost", 0))] if key == "external" else _receipt_stamp()
		_text(button, stamp, Vector2(10, 80) * factor, 13, AMBER if key == "external" and int(flow.get("total_rows", 0)) > 0 else TEAL, width - 20 * factor)
	var action := ("原記録 ↗" if not str(record.get("record_id", "")).is_empty() else "— この通信の観測なし") if _historical() else "● 許可 → 拒否" if allowed else "× 拒否 → 許可"
	if not _historical() and references.has(key): action = "許可→拒否" if allowed else "拒否→許可"
	if _historical() and key == "desk": action = "保存済みの受付"
	_text(button, action, Vector2(8, 85 if input else 114) * factor, 12 if not input else 13, MUTED if _historical() else tint, width - (94 if references.has(key) else 16) * factor)

func _receipt_stamp() -> String:
	var deadline: Dictionary = flow.get("deadline", {})
	if deadline.is_empty(): return "? 受付未確認"
	var count := int(deadline.get("received_count", 0))
	var status := str(deadline.get("status", "waiting"))
	var prefix := "✓ 受付%d件" % count if count > 0 else "… 未受付"
	if status == "late": return prefix + " / 補償¥%d" % int(deadline.get("loss_cost", 0))
	if status == "met": return prefix + " / 期限内"
	if status == "unknown": return prefix + " / 時刻未確認"
	return prefix + " / %d分〆" % int(deadline.get("minute", 14))

func _path(from: Vector2, to: Vector2, enabled: bool, record: Dictionary = {}) -> void:
	var historical := _historical()
	var status := int(record.get("status", 0))
	var measured := historical and status > 0
	var tint := (TEAL if status == 200 else AMBER) if measured else LINE if historical else TEAL if enabled else MUTED
	var solid := status == 200 if historical else enabled
	if solid: draw_line(from, to, tint, (3 if measured else 2) * factor, true)
	else: draw_dashed_line(from, to, tint, (2 if measured else 1) * factor, 6 * factor, true)
	var gate := from.lerp(to, .54)
	draw_circle(gate, 11 * factor, PAPER)
	if measured:
		_text(self, "↑" if status == 200 else "×", gate + Vector2(-7, 6) * factor, 19, tint)
	elif historical:
		_text(self, "?", gate + Vector2(-4, 5) * factor, 14, LINE)
	elif enabled:
		draw_arc(gate, 8 * factor, -PI * .35, PI * 1.35, 20, tint, 2 * factor, true)
		draw_line(gate - Vector2(0, 8) * factor, gate + Vector2(6, -13) * factor, tint, 2 * factor, true)
	else:
		draw_rect(Rect2(gate - Vector2(7, 7) * factor, Vector2(14, 14) * factor), tint, false, 2 * factor)
		draw_line(gate - Vector2(4, 4) * factor, gate + Vector2(4, 4) * factor, tint, 2 * factor, true)
		draw_line(gate + Vector2(-4, 4) * factor, gate + Vector2(4, -4) * factor, tint, 2 * factor, true)
	if not historical or measured:
		var direction := (from - to).normalized(); var normal := Vector2(-direction.y, direction.x)
		draw_polyline(PackedVector2Array([to + (direction * 6 + normal * 4) * factor, to, to + (direction * 6 - normal * 4) * factor]), tint, factor, true)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	for x in range(10, int(size.x), maxi(1, roundi(24 * factor))):
		for y in range(10, int(size.y), maxi(1, roundi(24 * factor))): draw_circle(Vector2(x, y), .7 * factor, Color("dbe5dc"))
	if center == Vector2.ZERO: return
	_text(self, "資料 / READ", Vector2(18, 25) * factor, 13, MUTED)
	_text(self, "送付先 / SEND", Vector2(18, send_heading_y) * factor if compact else Vector2(size.x - gates.desk.size.x - 18 * factor, 25 * factor), 13, MUTED)
	var mode_label := "現在の設定" if not _historical() else "? 通信原記録なし" if event.is_empty() else "%d分の実測 / 設定v%d" % [int(event.get("minute", 0)), int(event.get("world_revision", 0))]
	if _historical() and not event.is_empty() and (int(event.get("minute", -1)) < 0 or int(event.get("world_revision", -1)) < 0): mode_label = "? 時刻・設定世代を照合"
	var mode_x: float = size.x * .32 if compact else gates.faq.position.x + gates.faq.size.x + 10 * factor
	_text(self, mode_label, Vector2(mode_x, 25 * factor), 13, INK, size.x - mode_x - 15 * factor if compact else gates.desk.position.x - mode_x - 8 * factor)
	for key in gates:
		var item: Button = gates[key]; var input: bool = key in ["faq", "dispatch", "customers"]
		var from: Vector2; var to: Vector2
		if compact:
			from = item.position + Vector2(item.size.x * .5, item.size.y + 3 * factor) if input else center + Vector2(0, 35) * factor
			to = center - Vector2(0, 35) * factor if input else item.position + Vector2(item.size.x * .5, -3 * factor)
		else:
			from = item.position + Vector2(item.size.x + 2 * factor, 36 * factor) if input else center + Vector2(69, 0) * factor
			to = center - Vector2(69, 0) * factor if input else item.position + Vector2(-2 * factor, 42 * factor)
		_path(from, to, bool(model.get("policy", {}).get(key, false)), _event_record(key))
	var chip := Rect2(center - Vector2(64, 33) * factor, Vector2(128, 66) * factor)
	draw_rect(chip, INK)
	for index in 6:
		for side in [-1, 1]:
			var pin := center + Vector2(side * 65, -25 + index * 10) * factor
			draw_line(pin, pin + Vector2(side * 7, 0) * factor, INK, 3 * factor)
	_text(self, "AI-07", center + Vector2(-28, -5) * factor, 20, Color("c6f2d8"))
	_text(self, "問い合わせ要約", center + Vector2(-50, 18) * factor, 14, Color.WHITE)
	_text(self, "記録を参照中" if _historical() else "適用設定 v%d" % int(model.get("world_revision", 0)), center + Vector2(-48, 54) * factor, 12, MUTED)
