extends RefCounted
## Customer watch is a projection of retained delivery and alert records.
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
const INK := Color("e8f1f2")
const MUTED := Color("a7bac3")
const BG := Color("14212a")
const LINE := Color("49616c")
const TEAL := Color("79d5bc")
const AMBER := Color("f3be70")

class WatchGraph extends Control:

	var snapshot: Dictionary = {}
	var factor := 1.0
	var objects: Array[Button] = []
	var source_day := 0
	var today := 0
	var phase := ""
	var reveal: Callable

	func setup(value: Dictionary, scale: float, day: int, open_source: Callable) -> void:
		name = "CompanySaasWatchCanvas"; snapshot = value.duplicate(true); factor = scale; today = day; reveal = open_source
		size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
		var incident: Dictionary = snapshot.get("incident", {})
		phase = str(incident.get("status", "")); source_day = int(incident.get("source_day", snapshot.get("baseline", {}).get("source_day", 0)))
		custom_minimum_size.y = (184 if snapshot.get("baseline", {}).is_empty() else 350) * factor
		for index in 3:
			var button := Button.new(); button.name = ["SaaSWatchDevice", "SaaSWatchCustomer", "SaaSWatchBaseline"][index]
			button.tooltip_text = ["監視登録に使う原本を確認", "顧客と前回納品の原本を確認", "前回納品の申請原本を開く"][index]
			for state in ["normal", "hover", "pressed"]:
				button.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT if state == "normal" else Color("263d49"), Color.TRANSPARENT, 0, 0, 3))
			button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, TEAL, 0, 0, 2))
			button.pressed.connect(reveal); button.draw.connect(_object.bind(button, index)); add_child(button); objects.append(button)
		resized.connect(_layout); _layout.call_deferred()

	func _layout() -> void:
		if size.x <= 0: return
		for index in objects.size():
			objects[index].position = Vector2(size.x * (index / 3.0), 6 * factor)
			objects[index].size = Vector2(size.x / 3.0, 153 * factor)
			objects[index].queue_redraw()
		queue_redraw()

	func _text(target: Control, value: String, at: Vector2, width: float, points: int, tint: Color = INK) -> void:
		target.draw_string(UI.font(500), at, value, HORIZONTAL_ALIGNMENT_CENTER, width, int(points * factor), tint)

	func _object(button: Button, index: int) -> void:
		var f := factor; var center := Vector2(button.size.x / 2, 50 * f)
		var owned := bool(snapshot.get("owned", false)); var baseline: Dictionary = snapshot.get("baseline", {})
		var color := TEAL if owned else MUTED
		match index:
			0:
				button.draw_style_box(UI.style(Color("1b303b"), color, 3, 0, 2), Rect2(center - Vector2(44, 29) * f, Vector2(88, 58) * f))
				button.draw_line(center + Vector2(0, 30) * f, center + Vector2(0, 41) * f, color, 3 * f)
				button.draw_line(center + Vector2(-24, 42) * f, center + Vector2(24, 42) * f, color, 3 * f)
				for row in 3:
					button.draw_line(center + Vector2(-28, -14 + 13 * row) * f, center + Vector2(17, -14 + 13 * row) * f, LINE, 2 * f)
					if owned: button.draw_circle(center + Vector2(28, -14 + 13 * row) * f, 3 * f, TEAL)
					else: button.draw_arc(center + Vector2(28, -14 + 13 * row) * f, 3 * f, 0, TAU, 16, MUTED, f)
				_text(button, "監視設備", Vector2(0, 115 * f), button.size.x, 15)
				_text(button, "✓ 導入済み" if owned else "○ 未導入", Vector2(0, 139 * f), button.size.x, 14, color)
			1:
				var warehouse := Rect2(center - Vector2(43, 27) * f, Vector2(86, 63) * f)
				button.draw_rect(warehouse, Color("243b47")); button.draw_rect(warehouse, MUTED, false, 2 * f)
				button.draw_polyline(PackedVector2Array([center + Vector2(-48, -27) * f, center + Vector2(0, -42) * f, center + Vector2(48, -27) * f]), MUTED, 2 * f, true)
				for x in [-27, -6, 15]: button.draw_rect(Rect2(center + Vector2(x, -13) * f, Vector2(12, 12) * f), TEAL)
				button.draw_rect(Rect2(center + Vector2(-14, 11) * f, Vector2(28, 25) * f), LINE)
				_text(button, str(snapshot.get("client", "顧客未登録")), Vector2(0, 115 * f), button.size.x, 15)
				_text(button, "✓ 監視登録" if bool(snapshot.get("enrolled", false)) else "○ 監視未登録", Vector2(0, 139 * f), button.size.x, 14, TEAL if bool(snapshot.get("enrolled", false)) else MUTED)
			2:
				var paper := Rect2(center - Vector2(29, 39) * f, Vector2(58, 77) * f)
				button.draw_rect(paper, Color("e8e8d8") if not baseline.is_empty() else Color("253741"))
				button.draw_rect(paper, MUTED, false, f)
				for offset in [-21, -9, 3]: button.draw_line(center + Vector2(-18, offset) * f, center + Vector2(18, offset) * f, LINE, 2 * f)
				if not baseline.is_empty():
					button.draw_rect(Rect2(center + Vector2(-18, 17) * f, Vector2(36, 14) * f), Color("246e61"), false, f)
					_text(button, "保存", center + Vector2(-18, 28) * f, 36 * f, 10, Color("246e61"))
				_text(button, "前回の申請原本", Vector2(0, 115 * f), button.size.x, 15)
				var approval := "○ 未取得"
				for record in baseline.get("approved_originals", []):
					var change := str(record.get("data", {}).get("approved_change", ""))
					if change not in ["", "none"]: approval = str(record.get("app", "")) + " · " + change; break
				_text(button, approval, Vector2(0, 139 * f), button.size.x, 14, MUTED)

	func _draw() -> void:
		var f := factor; var enrolled := bool(snapshot.get("enrolled", false)); var baseline: Dictionary = snapshot.get("baseline", {})
		var incident: Dictionary = snapshot.get("incident", {})
		for index in 2:
			var start := Vector2(size.x * (index / 3.0 + 1.0 / 6.0) + 47 * f, 56 * f)
			var end := Vector2(size.x * ((index + 1) / 3.0 + 1.0 / 6.0) - 48 * f, 56 * f)
			if end.x <= start.x: continue
			if enrolled and not baseline.is_empty(): draw_line(start, end, TEAL, 2 * f, true)
			else: draw_dashed_line(start, end, LINE, 2 * f, 5 * f)
			draw_polyline(PackedVector2Array([end - Vector2(6, 4) * f, end, end - Vector2(6, -4) * f]), TEAL if enrolled else LINE, 2 * f)
		draw_line(Vector2(4, 174) * f, Vector2(size.x - 4 * f, 174 * f), LINE, f)
		if baseline.is_empty(): return
		var monitored := bool(incident.get("payload", {}).get("monitored", enrolled))
		var delay := int(incident.get("payload", {}).get("alert_delay", 0 if monitored else 9))
		var minutes := clampi(12 - delay, 0, 12)
		_text(self, "次案件の初回同期" if incident.is_empty() else "対応開始→初回同期", Vector2(0, 197 * f), size.x * .38, 14, MUTED)
		_text(self, "%d 分" % minutes, Vector2(0, 225 * f), size.x * .38, 22, TEAL if monitored else AMBER)
		var left := size.x * .42; var right := size.x - 16 * f; var ruler_y := 211 * f
		draw_line(Vector2(left, ruler_y), Vector2(right, ruler_y), LINE, 5 * f)
		draw_line(Vector2(left, ruler_y), Vector2(lerpf(left, right, minutes / 12.0), ruler_y), TEAL if monitored else AMBER, 5 * f)
		for tick in 13:
			var x := lerpf(left, right, tick / 12.0)
			draw_line(Vector2(x, ruler_y - 6 * f), Vector2(x, ruler_y + 6 * f), MUTED, f)
		for tick in [0, 3, 12]: _text(self, str(tick), Vector2(lerpf(left, right, tick / 12.0) - 12 * f, 239 * f), 24 * f, 12, MUTED)
		var centers := [size.x / 6.0, size.x / 2.0, size.x * 5.0 / 6.0]
		var y := 286 * f
		for index in 2: draw_dashed_line(Vector2(float(centers[index]) + 9 * f, y), Vector2(float(centers[index + 1]) - 9 * f, y), LINE, 2 * f, 5 * f)
		var occurred := int(incident.get("created_day", 0)) > 0
		var enrolled_day := int(snapshot.get("enrolled_day", 0))
		var days := ["DAY %02d" % source_day if source_day > 0 else "前回の納品", "DAY %02d" % enrolled_day if enrolled_day > 0 else "導入・登録", "DAY %02d" % int(incident.get("created_day", 0)) if occurred else "翌営業日"]
		var states := ["○ 原本なし" if baseline.is_empty() else "✓ 原本を保存", "✓ 監視登録" if enrolled else "○ 監視なし", {"pending":"! 警報を受信", "working":"▶ 対応中", "fulfilled":"✓ 対応を完了", "cancelled":"■ 対応中止"}.get(phase, "◇ まだ警報なし")]
		for index in 3:
			var center := Vector2(float(centers[index]), y)
			var color: Color = AMBER if index == 2 and phase in ["pending", "working", "cancelled"] else TEAL if (index == 0 and not baseline.is_empty()) or (index == 1 and enrolled) or (index == 2 and phase == "fulfilled") else MUTED
			if index == 2:
				draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9) * f, center + Vector2(9, 0) * f, center + Vector2(0, 9) * f, center + Vector2(-9, 0) * f]), color if occurred else BG)
				draw_polyline(PackedVector2Array([center + Vector2(0, -9) * f, center + Vector2(9, 0) * f, center + Vector2(0, 9) * f, center + Vector2(-9, 0) * f, center + Vector2(0, -9) * f]), color, 2 * f)
			else: draw_circle(center, 6 * f, color)
			_text(self, str(days[index]), Vector2(float(centers[index]) - size.x / 6.0, 266 * f), size.x / 3.0, 14, MUTED)
			_text(self, str(states[index]), Vector2(float(centers[index]) - size.x / 6.0, 321 * f), size.x / 3.0, 14, color)

static func build(ui, g) -> void:
	var status: Dictionary = g.saas_watch_status()
	var panel := PanelContainer.new(); panel.name = "CompanySaasWatch"; panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.style(BG, LINE, 14, 14, 1)); ui.modal_body.add_child(panel)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation", 10); panel.add_child(body)
	var header := HFlowContainer.new(); header.add_theme_constant_override("h_separation", 18); body.add_child(header)
	var title: Label = ui._label("CUSTOMER WATCH / SaaS監視", 19, INK)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF; header.add_child(title)
	var date: Label = ui._label("保存記録 · DAY %02d" % int(g.state.get("day", 0)), 13, MUTED)
	date.autowrap_mode = TextServer.AUTOWRAP_OFF; header.add_child(date)
	var baseline: Dictionary = status.get("baseline", {}); var incident: Dictionary = status.get("incident", {})
	var details := VBoxContainer.new(); details.name = "SaaSWatchSourceRecords"; details.visible = bool(ui.get_meta("saas_watch_records", false)); details.add_theme_constant_override("separation", 6)
	var graph := WatchGraph.new(); body.add_child(graph)
	graph.setup(status, float(ui.text_scale), int(g.state.get("day", 0)), _toggle_records.bind(ui, details))
	body.add_child(details)
	render_originals(details, baseline.get("approved_originals", []), int(baseline.get("source_day", 0)), float(ui.text_scale), "SaaSWatchBaseline")
	var actions := HFlowContainer.new(); actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_theme_constant_override("h_separation", 8); actions.add_theme_constant_override("v_separation", 6); ui.modal_footer.add_child(actions)
	if not bool(status.get("enrolled", false)):
		var buy := _action(ui, actions, "監視へ登録" if bool(status.get("owned", false)) else "導入・監視登録 · ¥%s" % ui._group_number(int(status.get("purchase_cost", 2400))), "SaaSWatchEnroll", _enroll.bind(ui, g), true)
		buy.disabled = not bool(status.get("can_enroll", false))
		if buy.disabled: body.add_child(ui._label(str(status.get("reason", "")), 14, AMBER))
	else: body.add_child(ui._label("✓ 監視登録済み · 追加の日額なし", 13, TEAL))
	var phase := str(incident.get("status", ""))
	if phase == "pending":
		var offer: Dictionary = g.saas_watch_offer()
		var open := _action(ui, actions, "警報の見積・受注へ", "SaaSWatchOpenOffer", _open_offer.bind(ui, g), true)
		open.disabled = offer.is_empty()
		if open.disabled: body.add_child(ui._label("見積を準備できません。営業日の案件状況を確認してください。", 13, AMBER))
	elif phase == "working": _action(ui, actions, "対応を再開", "SaaSWatchResume", _resume.bind(ui, g, str(incident.get("accepted_contract_id", ""))), true)
	elif phase.is_empty() and not baseline.is_empty(): _action(ui, actions, "日締め・翌営業日へ", "SaaSWatchNextDay", ui.open_panel.bind("door"), false)
	_action(ui, actions, "前回の原本", "SaaSWatchOpenBaseline", _toggle_records.bind(ui, details), false)

static func render_originals(parent: Node, originals: Array, source_day: int, factor: float, prefix: String) -> void:
	# Only the saved application records belong on this paper; monitoring
	# scheduling fields are not part of the customer's original application.
	var paper := PanelContainer.new(); paper.name = prefix + "Paper"; paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var paper_style := UI.style(Color("faf8ef"), Color("d5d1c3"), 10, 8, 0)
	paper_style.border_width_left = 3; paper.add_theme_stylebox_override("panel", paper_style); parent.add_child(paper)
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 5); paper.add_child(stack)
	_original_label(stack, "DAY %02d · 前回の申請原本" % source_day if source_day > 0 else "前回の申請原本", 13, factor, Color("6b6e68"))
	for index in originals.size():
		var record: Dictionary = originals[index]; var data: Dictionary = record.get("data", {})
		if index > 0:
			var rule := HSeparator.new(); var stroke := StyleBoxLine.new(); stroke.color = Color("d5d1c3"); rule.add_theme_stylebox_override("separator", stroke); stack.add_child(rule)
		var row := HFlowContainer.new(); row.name = prefix + "_" + str(record.get("id", "")).validate_node_name(); row.add_theme_constant_override("h_separation", 12); row.add_theme_constant_override("v_separation", 3); stack.add_child(row)
		var app := _original_label(row, str(record.get("app", "")), 14, factor, Color("243940")); app.add_theme_font_override("font", UI.font(700))
		_original_label(row, str(data.get("publisher", "発行者未記録")), 13, factor, Color("536466"))
		var change := str(data.get("approved_change", "")); var owner := str(data.get("approved_by", ""))
		var approved := change not in ["", "none"] and owner not in ["", "none"]
		var approval := "✓ %s · %s" % [change, owner] if approved else "— 申請なし" if change in ["", "none"] else "申請 %s · 承認者未記録" % change
		_original_label(row, approval, 14, factor, Color("246e61") if approved else Color("855821"))
		_original_label(row, "当時 %d" % int(record.get("status", 0)), 12, factor, Color("6b6e68"))
	if originals.is_empty(): _original_label(stack, "保存した申請原本はありません。", 14, factor, Color("6b6e68"))
	var toggle := Button.new(); toggle.name = prefix + "OpenRaw"; toggle.text = "原文 · %d件" % originals.size(); toggle.custom_minimum_size.y = 32 * factor; toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.add_theme_font_size_override("font_size", int(13 * factor)); M.button(toggle, "quiet"); stack.add_child(toggle)
	var raw := TextEdit.new(); raw.name = prefix + "Raw"; raw.editable = false; raw.visible = false; raw.text = JSON.stringify(originals, "\t")
	raw.custom_minimum_size.y = 150 * factor; raw.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	raw.add_theme_font_size_override("font_size", int(13 * factor)); raw.add_theme_color_override("font_readonly_color", Color("243940")); raw.add_theme_stylebox_override("read_only", UI.style(Color("fffdf7"), Color("d5d1c3"), 6, 6, 0)); stack.add_child(raw)
	toggle.disabled = originals.is_empty()
	toggle.pressed.connect(func(): raw.visible = not raw.visible; toggle.text = "原文を閉じる" if raw.visible else "原文 · %d件" % originals.size())

static func _original_label(parent: Node, text: String, points: int, factor: float, ink: Color) -> Label:
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.add_theme_font_override("font", UI.font(500)); label.add_theme_font_size_override("font_size", int(points * factor)); label.add_theme_color_override("font_color", ink); parent.add_child(label); return label

static func _action(ui, parent: Node, title: String, id: String, action: Callable, primary: bool) -> Button:
	var button: Button = ui._button(title, action); button.name = id; M.button(button, "primary" if primary else "secondary"); parent.add_child(button); return button

static func _toggle_records(ui, details: Control) -> void:
	details.visible = not details.visible; ui.set_meta("saas_watch_records", details.visible)
	if details.visible: ui.modal_scroll.ensure_control_visible.call_deferred(details)

static func _enroll(ui, g) -> void:
	if g.enroll_saas_watch(): ui._select_company_view("saas_watch")
	else: ui._management_feedback("導入・登録を保存できませんでした。" + str(g.saas_watch_status().get("reason", "")))

static func _open_offer(ui, g) -> void:
	var offer: Dictionary = g.saas_watch_offer()
	if offer.is_empty(): ui._management_feedback("受注できる監視警報はありません。"); return
	ui.board_selected_id = str(offer.get("id", "")); ui.board_filter = "all"; ui.sales_view = "inquiries"; ui.sales_stage = "all"; ui.sales_search = ""; ui.open_panel("sales")

static func _resume(ui, g, contract_id: String) -> void:
	if contract_id.is_empty() or not g.switch_contract(contract_id): ui._management_feedback("対応中の案件を開けませんでした。"); return
	ui.open_panel("terminal")
	if is_instance_valid(ui.desktop): ui.desktop._show_app("advanced")
