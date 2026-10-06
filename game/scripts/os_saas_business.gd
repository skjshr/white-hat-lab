extends RefCounted
## The business desks display saved jobs. Time advances only through case actions.
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Canvas = preload("res://scripts/saas_business_canvas.gd")
const KIND := "advanced-saas-response"
const INK = Color("283139")
const MUTED = Color("647277")

static func enabled(n: Dictionary) -> bool:
	return n.get("session_case", {}).get("business", {}) is Dictionary and not n.get("session_case", {}).get("business", {}).is_empty()

static func job(n: Dictionary, purpose: String) -> Dictionary:
	for item in n.get("session_case", {}).get("business", {}).get("jobs", []):
		if str(item.get("purpose", "")) == purpose: return item
	return {}

static func tab_label(n: Dictionary, purpose: String) -> String:
	var item := job(n, purpose); var label := "請求" if purpose == "billing" else "配車集計"
	match str(item.get("status", "")):
		"queued": label += (" Ⅱ" if _active(n, purpose).is_empty() else " 待ち") + "%d%s" % [int(item.get("units", 0)), str(item.get("unit", ""))]
		"completed": label += " ✓"
		"scheduled":
			if _active(n, purpose).is_empty(): label += " ×停止"
	var loss := int(item.get("loss_amount", 0))
	if loss > 0: label += " 補償¥%d" % loss
	return label

static func render(d, parent: Node, n: Dictionary, purpose: String) -> void:
	var item := job(n, purpose)
	if item.is_empty(): return
	var minute := int(n.get("elapsed_minutes", 0)); var deadline := int(item.get("deadline_minute", 0)); var status := str(item.get("status", ""))
	var header := U.row(parent)
	_label(header, str(item.get("label", "")) + " / " + str(item.get("id", "")), 15)
	_label(header, "%d分時点 · 締切 %d分" % [minute, deadline], 13, MUTED)
	var operations := U.row(parent)
	var state := "投入予定 %d分" % int(item.get("release_minute", 0))
	if status == "queued": state = "Ⅱ 待ち %d%s" % [int(item.get("units", 0)), str(item.get("unit", ""))]
	elif status == "completed": state = "✓ %d分に完了" % int(item.get("completed_minute", 0))
	_label(operations, state, 14)
	var loss := int(item.get("loss_amount", 0))
	_label(operations, "補償 ¥%d" % loss if loss > 0 or status == "completed" else "遅延時 ¥%d" % int(item.get("penalty", 0)), 13, UI.RED if loss > 0 else MUTED)
	_button(operations, "請求の接続券へ" if purpose == "billing" else "集計の接続券へ", "SaasBusinessSession_" + purpose, _open_session.bind(d, n, purpose))
	var record_id := str(item.get("record_id", "")); var record_label := "処理原本"
	if record_id.is_empty():
		record_id = str(item.get("loss_record_id", "")); record_label = "補償原本"
	if record_id.is_empty():
		record_id = str(item.get("queued_record_id", "")); record_label = "待機原本"
	if not record_id.is_empty(): _button(operations, record_label, "SaasBusinessRecord_" + purpose, _open_record.bind(d, record_id))
	var active := _active(n, purpose); var view: Dictionary = item.duplicate(true)
	view["minute"] = minute; view["evidence_record_id"] = record_id; view["session_id"] = str(active.get("id", "")); view["configured_available"] = not active.is_empty() and bool(n.get("session_case", {}).get("consent", {}).get("enabled", false))
	var canvas := Canvas.new(); parent.add_child(canvas)
	canvas.configure(view, float(d.game.settings.get("text_scale", 1.0)), _object_selected.bind(d, n, purpose, record_id))
	if status == "queued" and bool(view.configured_available): _label(parent, "次の作業時間で、有効な券による予約処理が進みます。", 13, MUTED)

static func _active(n: Dictionary, purpose: String) -> Dictionary:
	for session in n.get("session_case", {}).get("sessions", []):
		if str(session.get("purpose", "")) == purpose and bool(session.get("active", false)): return session
	return {}

static func _open_session(d, n: Dictionary, purpose: String) -> void:
	var current := _active(n, purpose); var id := str(current.get("id", ""))
	var item := job(n, purpose)
	if str(item.get("status", "")) == "completed" and not str(item.get("used_session_id", "")).is_empty(): id = str(item.get("used_session_id", ""))
	if id.is_empty():
		for session in n.get("session_case", {}).get("sessions", []):
			if str(session.get("purpose", "")) == purpose: id = str(session.get("id", ""))
	var state := U.state(d, KIND); state.selected_session = id; state.session_evidence = ""; state.erase("open_record")
	U.choose(d, KIND, "tab", "identity"); d.widgets.advanced.next_scroll = 0

static func _open_record(d, id: String) -> void:
	d.widgets.advanced.next_scroll = 0; U.choose(d, KIND, "open_record", id)

static func _object_selected(part: String, d, n: Dictionary, purpose: String, record_id: String) -> void:
	if part == "session": _open_session(d, n, purpose)
	elif part == "record" and not record_id.is_empty(): _open_record(d, record_id)

static func _label(parent: Node, text: String, size: int = 14, color: Color = INK) -> Label:
	return U.label(parent, text, size, color, not parent is HFlowContainer)

static func _button(parent: Node, text: String, id: String, action: Callable) -> Button:
	var button := U.button(parent, text, id, action)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, INK)
	for state in ["hover", "pressed", "hover_pressed"]: button.add_theme_stylebox_override(state, UI.style(Color("e8f0f0"), Color("7b9d9a"), 8, 6, 2))
	return button
