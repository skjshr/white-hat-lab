extends Control
## Display only. Gate presses request a model action; drawing never measures traffic.
const UI = preload("res://scripts/ui_theme.gd")
const BG = Color("12232f")
const PANEL = Color("1d3443")
const INK = Color("eef0e7")
const MUTED = Color("b2c1c6")
const LINE = Color("54717e")
const AMBER = Color("f1bb68")
const MINT = Color("9bd2c2")
const PAPER = Color("f1ead6")
var model: Dictionary = {}
var factor := 1.0
var event: Dictionary = {}
var event_id := ""
var policy_action: Callable
var record_action: Callable
var nodes: Dictionary = {}
var selectors: Dictionary = {}
var references: Dictionary = {}
var center := Vector2.ZERO
var cabinet := Rect2()
var compact := false

func configure(data: Dictionary, scale: float, change: Callable, open_record: Callable, selected_event: String = "") -> void:
	name = "AiHandoffCanvas"; model = data.duplicate(true); factor = maxf(.5, scale)
	policy_action = change; record_action = open_record; event_id = selected_event
	for candidate in model.get("flow", {}).get("events", []):
		if str(candidate.get("id", "")) == event_id: event = candidate.duplicate(true); break
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["dispatch", "contacts", "partner_dispatch", "partner_archive"]:
		var node := Button.new(); node.name = "AiHandoffGate_" + key
		_style(node); node.draw.connect(_draw_node.bind(node, key))
		var observed := _measurement(key); var id := str(observed.get("id", observed.get("record_id", "")))
		if _historical():
			node.disabled = id.is_empty(); node.pressed.connect(_open.bind(id))
			node.tooltip_text = _title(key) + " / " + (_observed_text(key) if not id.is_empty() else "この通信の観測なし")
		elif key == "contacts":
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE; node.focus_mode = Control.FOCUS_NONE
		else:
			var enabled := bool(model.get("policy", {}).get(key, false))
			node.tooltip_text = _title(key) + ("を閉じる · 1分" if enabled else "を開く · 1分")
			node.pressed.connect(func(): policy_action.call(key, not enabled))
		add_child(node); nodes[key] = node
		if not id.is_empty():
			var reference := Button.new(); reference.name = "AiHandoffRecord_" + key; reference.text = "原記録 ↗"
			_small_button(reference); reference.tooltip_text = _title(key) + " / " + id
			reference.set_meta("record_id", id); reference.pressed.connect(_open.bind(id))
			add_child(reference); references[key] = reference
	if not _historical():
		for mode in ["off", "linked", "all"]:
			var selector := Button.new(); selector.name = "AiHandoffContacts_" + mode
			selector.text = str({"off":"0件", "linked":"当該3件", "all":"全6件"}[mode]); selector.toggle_mode = true
			selector.button_pressed = str(model.get("policy", {}).get("contacts", "off")) == mode
			selector.tooltip_text = str({"off":"連絡先を参照しない", "linked":"今回の3便に対応する連絡先", "all":"台帳内の全6連絡先"}[mode]) + " · 1分"
			_small_button(selector); selector.disabled = selector.button_pressed
			selector.pressed.connect(func(): policy_action.call("contacts", mode))
			add_child(selector); selectors[mode] = selector
	resized.connect(_layout); _layout.call_deferred()

func _style(button: Button) -> void:
	for key in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(key, UI.style(Color.TRANSPARENT if key in ["normal", "disabled"] else Color("294454"), Color.TRANSPARENT, 0, 0, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _small_button(button: Button) -> void:
	button.add_theme_font_override("font", UI.font(500)); button.add_theme_font_size_override("font_size", roundi(12 * factor))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]: button.add_theme_color_override(key, INK)
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color("39515a") if key in ["pressed", "disabled"] else PANEL, AMBER if key == "disabled" else LINE, 4, 3, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))

func _historical() -> bool:
	return not event_id.is_empty()

func _title(key: String) -> String:
	return str({"dispatch":"配送進捗", "contacts":"連絡先台帳", "partner_dispatch":"/dispatch", "partner_archive":"/archive"}.get(key, key))

func _measurement(key: String) -> Dictionary:
	if _historical():
		return event.get("read" if key == "contacts" else "write", {}) if key in ["contacts", "partner_archive"] else {}
	var actions: Array = {"contacts":["boundary_read", "scheduled_customer_read"], "partner_archive":["boundary_write", "scheduled_external_write"], "partner_dispatch":["run_business"]}.get(key, [])
	var result: Dictionary = {}
	for record in model.get("records", []):
		if str(record.get("action", "")) in actions: result = record
	return result

func _observed_text(key: String) -> String:
	var record := _measurement(key)
	if record.is_empty(): return "? 未実測"
	var status := int(record.get("status", 0))
	var action := str(record.get("action", ""))
	var origin := "通信" if _historical() or action.begins_with("scheduled_") else "試験" if action.begins_with("boundary_") else "業務"
	var stale := not _historical() and int(record.get("world_revision", -1)) != int(model.get("world_revision", 0))
	return ("旧設定 " if stale else "") + origin + (" ↑" if status == 200 else " ×") + str(status)

func _open(id: String) -> void:
	if not id.is_empty() and record_action.is_valid(): record_action.call(id)

func _approval() -> Dictionary:
	for record in model.get("records", []):
		if str(record.get("id", "")) == "AI-401": return record.get("data", {})
	return {}

func _layout() -> void:
	if size.x <= 0: return
	var width := size.x / factor; compact = width < 760
	if compact:
		var input_width := (width - 42) / 2
		_place("dispatch", Rect2(14, 56, input_width, 146)); _place("contacts", Rect2(28 + input_width, 56, input_width, 146))
		center = Vector2(width / 2, 252) * factor
		cabinet = Rect2(10, 310, width - 20, 188)
		var folder_width := (width - 56) / 2
		_place("partner_dispatch", Rect2(22, 341, folder_width, 142)); _place("partner_archive", Rect2(34 + folder_width, 341, folder_width, 142))
		custom_minimum_size.y = 526 * factor
	else:
		var left_width := minf(260, width * .28); var right_width := minf(300, width * .32)
		_place("dispatch", Rect2(16, 58, left_width, 116)); _place("contacts", Rect2(16, 188, left_width, 146))
		center = Vector2((left_width + 16 + width - right_width - 30) / 2, 196) * factor
		cabinet = Rect2(width - right_width - 22, 40, right_width + 10, 300)
		_place("partner_dispatch", Rect2(width - right_width - 8, 69, right_width - 18, 123)); _place("partner_archive", Rect2(width - right_width - 8, 209, right_width - 18, 123))
		custom_minimum_size.y = 363 * factor
	for key in references:
		var node: Button = nodes[key]; var reference: Button = references[key]
		reference.position = node.position + Vector2(node.size.x - 88 * factor, node.size.y - 26 * factor)
		reference.size = Vector2(82, 24) * factor
	if not selectors.is_empty():
		var contacts: Button = nodes.contacts; var item_width := (contacts.size.x - 20 * factor) / 3
		for index in 3:
			var selector: Button = selectors[["off", "linked", "all"][index]]
			selector.position = contacts.position + Vector2(8 * factor + index * item_width, 79 * factor)
			selector.size = Vector2(item_width - 3 * factor, 27 * factor)
	for node in nodes.values(): node.queue_redraw()
	queue_redraw()

func _place(key: String, rect: Rect2) -> void:
	var button: Button = nodes[key]; button.position = rect.position * factor; button.size = rect.size * factor

func _text(on: Control, value: String, point: Vector2, points: int = 14, color: Color = INK, width: float = -1) -> void:
	on.draw_string(UI.font(500), point * factor, value, HORIZONTAL_ALIGNMENT_LEFT, width * factor if width >= 0 else -1, roundi(points * factor), color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if nodes.is_empty(): return
	var width := size.x / factor
	_text(self, "MINATO  /  配送連絡", Vector2(16, 24), 16, AMBER)
	var heading := "%d分の通信 / 設定v%d" % [int(event.get("minute", -1)), int(event.get("world_revision", -1))] if _historical() else "現在の設定 v%d" % int(model.get("world_revision", 0))
	_text(self, heading, Vector2(width - 230, 24), 13, MUTED, 215)
	var cab := Rect2(cabinet.position * factor, cabinet.size * factor)
	draw_rect(cab, PANEL); draw_rect(cab, LINE, false, factor)
	_text(self, str(_approval().get("partner", "ミナト配送")) + "  /  送付先", cabinet.position + Vector2(12, 20), 13, MUTED, cabinet.size.x - 20)
	for key in nodes:
		var node: Button = nodes[key]; var start: Vector2; var finish: Vector2
		if compact:
			start = node.position + Vector2(node.size.x / 2, node.size.y if key in ["dispatch", "contacts"] else 0)
			finish = center + Vector2(-18 if key in ["dispatch", "partner_dispatch"] else 18, -28 if key in ["dispatch", "contacts"] else 28) * factor
		else:
			start = node.position + Vector2(node.size.x if key in ["dispatch", "contacts"] else 0, node.size.y / 2)
			finish = center + Vector2(-43 if key in ["dispatch", "contacts"] else 43, -14 if key in ["dispatch", "partner_dispatch"] else 14) * factor
		var enabled := str(model.get("policy", {}).get("contacts", "off")) != "off" if key == "contacts" else bool(model.get("policy", {}).get(key, false))
		var measurement := _measurement(key)
		var color := (MINT if int(measurement.get("status", 0)) == 200 else AMBER) if _historical() and not measurement.is_empty() else LINE
		var solid := int(measurement.get("status", 0)) == 200 if _historical() else enabled
		var from := start if key in ["dispatch", "contacts"] else finish
		var to := finish if key in ["dispatch", "contacts"] else start
		_wire(from, to, color, solid, _historical() and measurement.is_empty())
	var chip := Rect2(center - Vector2(44, 29) * factor, Vector2(88, 58) * factor)
	draw_rect(chip, Color("304552")); draw_rect(chip, AMBER, false, 2 * factor)
	_text(self, "AI LINK", center / factor + Vector2(-33, -3), 14, AMBER)
	_text(self, "搬送器", center / factor + Vector2(-24, 18), 12, INK)
	_text(self, "記録済み通信の参照 · 設定操作なし" if _historical() else "扉＝現在設定   ↑/×＝保存済み実測   許可札＝承認原本", Vector2(16, size.y / factor - 9), 12, MUTED, width - 30)

func _wire(from: Vector2, to: Vector2, color: Color, solid: bool, unknown: bool = false) -> void:
	var bend := Vector2(from.x, to.y) if compact else Vector2(to.x, from.y)
	if solid:
		draw_line(from, bend, color, 2 * factor); draw_line(bend, to, color, 2 * factor)
	else:
		draw_dashed_line(from, bend, color, factor, 5 * factor); draw_dashed_line(bend, to, color, factor, 5 * factor)
		var midpoint := bend.lerp(to, .5) if bend.distance_to(to) > 20 * factor else from.lerp(bend, .5)
		if unknown:
			_text(self, "?", midpoint / factor + Vector2(-4, 4), 13, color)
		else:
			draw_line(midpoint + Vector2(-4, -4) * factor, midpoint + Vector2(4, 4) * factor, color, 2 * factor)
			draw_line(midpoint + Vector2(-4, 4) * factor, midpoint + Vector2(4, -4) * factor, color, 2 * factor)
	var direction := (to - bend).normalized()
	if direction.length() < .1: direction = (to - from).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(to, to - direction * 6 * factor + perpendicular * 4 * factor, color, 2 * factor)
	draw_line(to, to - direction * 6 * factor - perpendicular * 4 * factor, color, 2 * factor)

func _draw_node(on: Button, key: String) -> void:
	var width := on.size.x / factor; var height := on.size.y / factor
	var history := _historical()
	var allowed := str(model.get("policy", {}).get(key, "off")) != "off" if key == "contacts" else bool(model.get("policy", {}).get(key, false))
	var approval := _approval(); var current_policy: Dictionary = model.get("policy", {})
	if key == "dispatch":
		for index in 3:
			var x := 10 + index * 30
			on.draw_rect(Rect2(Vector2(x, 15) * factor, Vector2(24, 30) * factor), PAPER)
			on.draw_line(Vector2(x, 15) * factor, Vector2(x + 24, 30) * factor, LINE, factor)
			on.draw_line(Vector2(x + 24, 15) * factor, Vector2(x, 30) * factor, LINE, factor)
		_text(on, "配送進捗", Vector2(108, 30), 15, INK, width - 113)
		var approved: Array = approval.get("approved_shipment_ids", [])
		_text(on, "許可札 AI-401 · %d便" % approved.size() if not approval.is_empty() else "許可札 ?", Vector2(10, 64), 12, AMBER, width - 15)
		_text(on, "過去通信では未観測" if history else ("開  ┃  配送資料" if allowed else "閉  ×  配送資料"), Vector2(10, 91), 14, MUTED if history else INK, width - 15)
	elif key == "contacts":
		var mode := str(current_policy.get("contacts", "off")); var count := int({"off":0, "linked":3, "all":6}.get(mode, 0))
		_text(on, "連絡先台帳", Vector2(10, 23), 15, INK, width - 15)
		for index in 6:
			var x := 14 + index * 23
			var visible := index < count and not history
			on.draw_circle(Vector2(x + 4, 40) * factor, 4 * factor, AMBER if visible else LINE)
			on.draw_rect(Rect2(Vector2(x, 47) * factor, Vector2(8, 8) * factor), AMBER if visible else LINE)
		_text(on, "許可札 · 当該%d件" % approval.get("approved_contact_ids", []).size() if not approval.is_empty() else "許可札 ?", Vector2(10, 72), 12, AMBER, width - 15)
		if history: _text(on, "%d行を要求" % int(_measurement(key).get("rows", 0)), Vector2(10, 99), 14, INK, width - 15)
		_text(on, _observed_text(key), Vector2(10, height - 9), 12, MUTED, width - 103 if references.has(key) else width - 15)
	else:
		var archive := key == "partner_archive"
		var folder_color := Color("526978") if archive else Color("5a706a")
		if archive:
			for index in 3: on.draw_rect(Rect2(Vector2(8 + index * 3, 8 + index * 4) * factor, Vector2(36, 23) * factor), folder_color)
		else:
			on.draw_rect(Rect2(Vector2(8, 8) * factor, Vector2(21, 6) * factor), folder_color)
			on.draw_rect(Rect2(Vector2(8, 14) * factor, Vector2(43, 23) * factor), folder_color)
			on.draw_line(Vector2(19, 25) * factor, Vector2(42, 25) * factor, AMBER, 2 * factor)
			on.draw_line(Vector2(42, 25) * factor, Vector2(35, 20) * factor, AMBER, 2 * factor)
		_text(on, _title(key), Vector2(59, 29), 15, INK, width - 64)
		var target := "minato/archive" if archive else "minato/dispatch"
		var approved := str(approval.get("approved_recipient", "")) == target
		_text(on, ("許可札 AI-401" if approved else "承認票に対象記載なし") if not approval.is_empty() else "承認原本 ?", Vector2(10, 53), 12, AMBER if approved else MUTED, width - 15)
		var door := Rect2(Vector2(width - 27, 7) * factor, Vector2(18, 28) * factor)
		if not history:
			on.draw_rect(door, AMBER if allowed else BG, false, 2 * factor)
			_text(on, "開" if allowed else "閉", Vector2(width - 25, 27), 12, AMBER)
		_text(on, _observed_text(key), Vector2(10, 75), 12, INK, width - 16)
		if archive:
			_text(on, "保存累計 ↑%d行 / ¥%d" % [int(model.get("leaked_rows", 0)), int(model.get("impact_cost", 0))], Vector2(10, height - 32), 12, AMBER, width - 16)
		else:
			var business: Dictionary = model.get("business", {})
			var receipt := str(business.get("receipt_id", ""))
			_text(on, "受付控え %d便 ✓" % business.get("accepted_jobs", []).size() if not receipt.is_empty() else "受付控え  … 未受付", Vector2(10, height - 32), 12, MINT if not receipt.is_empty() else MUTED, width - 16)

class Bags extends Control:
	var model: Dictionary = {}
	var factor := 1.0
	var items: Array[Button] = []
	var columns := 3
	func configure(data: Dictionary, scale: float, open_job: Callable) -> void:
		name = "AiHandoffBags"; model = data.duplicate(true); factor = maxf(.5, scale)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
		var jobs: Array = model.get("jobs", [])
		for index in jobs.size():
			var item := Button.new(); item.name = "AiHandoffBag_" + str(jobs[index].get("shipment_id", index))
			item.tooltip_text = str(jobs[index].get("shipment_id", "")) + " / " + str(jobs[index].get("shipment_label", "")) + " / " + str(jobs[index].get("contact_name", ""))
			for key in ["normal", "hover", "pressed"]: item.add_theme_stylebox_override(key, UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 1))
			item.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))
			item.pressed.connect(func(): open_job.call(index)); item.draw.connect(_draw_bag.bind(item, jobs[index])); add_child(item); items.append(item)
		resized.connect(_layout); _layout.call_deferred()
	func _layout() -> void:
		if size.x <= 0: return
		columns = 3 if size.x / factor >= 700 else 2 if size.x / factor >= 470 else 1
		var width := (size.x / factor - 16) / columns
		for index in items.size():
			items[index].position = Vector2(8 + (index % columns) * width, 8 + int(index / columns) * 202) * factor
			items[index].size = Vector2(width - 12, 188) * factor; items[index].queue_redraw()
		custom_minimum_size.y = (16 + ceili(float(items.size()) / columns) * 202) * factor
	func _text(on: Control, value: String, point: Vector2, points: int, color: Color, width: float) -> void:
		on.draw_string(UI.font(500), point * factor, value, HORIZONTAL_ALIGNMENT_LEFT, width * factor, roundi(points * factor), color)
	func _draw_bag(on: Button, job: Dictionary) -> void:
		var width := on.size.x / factor; var received := str(job.get("status", "")) == "received"
		var r := Rect2(Vector2(3, 13) * factor, Vector2(width - 6, 170) * factor)
		on.draw_rect(r, PAPER); on.draw_rect(r, Color("b6a584"), false, factor)
		on.draw_line(Vector2(3, 13) * factor, Vector2(width / 2, 41) * factor, Color("b6a584"), factor)
		on.draw_line(Vector2(width - 3, 13) * factor, Vector2(width / 2, 41) * factor, Color("b6a584"), factor)
		on.draw_rect(Rect2(Vector2(width / 2 - 15, 8) * factor, Vector2(30, 34) * factor), Color("d6b470"))
		_text(on, str(job.get("shipment_id", "")), Vector2(15, 63), 16, BG, width - 28)
		_text(on, str(job.get("shipment_label", "")), Vector2(15, 86), 13, BG, width - 28)
		_text(on, str(job.get("contact_name", job.get("contact_id", ""))), Vector2(15, 109), 14, BG, width - 28)
		var stamp := Rect2(Vector2(13, 122) * factor, Vector2(width - 26, 45) * factor)
		on.draw_rect(stamp, Color("397164") if received else Color("92713e"), false, 2 * factor)
		_text(on, "✓ 受付 " + str(job.get("receipt_id", "")) if received else "… 送付待ち", Vector2(22, 142), 14, Color("28584e") if received else Color("73552a"), width - 42)
		_text(on, "ミナト配送 /dispatch", Vector2(22, 160), 12, BG, width - 42)
