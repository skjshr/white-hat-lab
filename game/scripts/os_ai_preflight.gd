extends RefCounted
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Diagram = preload("res://scripts/ai_gate_canvas.gd")
const KIND := "advanced-saas-ai-preflight"
const INK = Color("243b40")
const MUTED = Color("61797c")
const TEAL = Color("187969")

class TicketDesk extends Control:
	var data: Dictionary = {}
	var factor := 1.0
	var columns := 3
	var buttons: Array[Button] = []
	func configure(value: Dictionary, scale: float, open: Callable) -> void:
		name = "AiServiceDeskTickets"; data = value.duplicate(true); factor = scale
		size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
		for index in 6:
			var button := Button.new(); button.name = "AiInquiry_%d" % index; button.tooltip_text = "問い合わせと保存済み要約を開く"
			for state in ["normal", "hover", "pressed"]: button.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 1))
			button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, Color("14649a"), 0, 0, 1))
			button.pressed.connect(func(): open.call(index)); add_child(button); buttons.append(button)
		resized.connect(_layout); _layout.call_deferred()
	func _layout() -> void:
		columns = 3 if size.x / factor >= 860 else 2
		var width := (size.x - 24 * factor) / columns
		for index in buttons.size():
			buttons[index].position = Vector2((index % columns) * width + 8 * factor, (index / columns) * 142 * factor + 8 * factor)
			buttons[index].size = Vector2(width - 10 * factor, 126 * factor)
		custom_minimum_size.y = (ceilf(6.0 / columns) * 142 + 16) * factor; queue_redraw()
	func _draw() -> void:
		var done := not str(data.get("receipt_id", "")).is_empty()
		var width := (size.x - 24 * factor) / columns
		var requests: Array = data.get("requests", []); var summaries: Array = data.get("accepted_summaries", [])
		for index in 6:
			var request: Dictionary = requests[index] if index < requests.size() else {}
			var summary: Dictionary = summaries[index] if index < summaries.size() else {}
			var rect := Rect2(Vector2((index % columns) * width + 8 * factor, (index / columns) * 142 * factor + 8 * factor), Vector2(width - 10 * factor, 126 * factor))
			draw_rect(Rect2(rect.position + Vector2(3, 3) * factor, rect.size), Color("d8ddd8"))
			draw_rect(rect, Color("fffdf4")); draw_rect(rect, Color("a9bab3"), false, factor)
			draw_rect(Rect2(rect.position, Vector2(5 * factor, rect.size.y)), Color("187969") if done else Color("ba9760"))
			var font := get_theme_default_font()
			draw_string(font, rect.position + Vector2(15, 25) * factor, str(request.get("id", "REQ%03d" % (301 + index))) + " / " + str(request.get("shipment_id", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 25 * factor, roundi(12 * factor), Color("536a66"))
			draw_string(font, rect.position + Vector2(15, 49) * factor, str(request.get("subject", "問い合わせ原票")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 25 * factor, roundi(14 * factor), Color("243b40"))
			draw_line(rect.position + Vector2(15, 59) * factor, rect.position + Vector2(rect.size.x - 17 * factor, 59 * factor), Color("d8ddd8"), factor)
			var answer := str(summary.get("status", "")) + " / " + str(summary.get("eta", "")) if summary.has("status") else "要約内容の保存なし" if done else "要約は未生成"
			draw_string(font, rect.position + Vector2(15, 84) * factor, answer, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 25 * factor, roundi(14 * factor), Color("243b40") if done else Color("84918a"))
			draw_string(font, rect.position + Vector2(15, 111) * factor, "✓ 要約を受付" if done else "… 回答待ち", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 25 * factor, roundi(13 * factor), Color("187969") if done else Color("8f652a"))

static func build(d, parent: VBoxContainer) -> void:
	U.mount(d, parent, KIND, "AI Gate / 北斗物流・導入審査")
	refresh(d)

static func refresh(d) -> void:
	var data: Dictionary = d.game.advanced_view(); var n: Dictionary = data.get("ai_preflight", {})
	var workspace: Dictionary = d.widgets.advanced
	var active_tab := str(U.state(d, KIND).get("tab", "wiring"))
	if str(workspace.get("ai_rendered_tab", active_tab)) != active_tab:
		workspace.next_scroll = 0
	var body: VBoxContainer = U.begin(d, KIND, data)
	if body == null or n.is_empty(): return
	workspace.ai_rendered_tab = active_tab
	U.navigation(d, KIND, [["wiring", "権限の配線"], ["desk", "問い合わせ受付"], ["records", "原記録・報告"], ["results", "受入確認"]], "wiring", "AiTab_")
	for tab in d.widgets.advanced.nav.get_children():
		if tab is Button:
			for color_key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: tab.add_theme_color_override(color_key, INK)
	match str(U.state(d, KIND).get("tab", "wiring")):
		"desk": _desk(d, body, n)
		"records": _records(d, body, n)
		"results": U.checks(body, data)
		_: _wiring(d, body, n)

static func _label(parent: Node, value: String, size: int = 14, color: Color = INK) -> Label:
	return U.label(parent, value, size, color, not parent is HFlowContainer)

static func _button(parent: Node, value: String, id: String, action: Callable) -> Button:
	var button := U.button(parent, value, id, action)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(key, INK)
	for key in ["normal", "hover", "pressed"]: button.add_theme_stylebox_override(key, UI.style(Color("f1f6ef") if key == "normal" else Color("d7eadf"), Color("a6beb3"), 10, 7, 2))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, Color("14649a"), 0, 0, 2))
	return button

static func _send(d, action: String, args: Dictionary = {}) -> void:
	U.send(d, KIND, action, args)

static func _policy(key: String, enabled: bool, d) -> void:
	_send(d, "configure", {"key":key, "enabled":enabled})

static func _band(parent: Node, title: String, background: Color = INK) -> void:
	var band := PanelContainer.new(); band.add_theme_stylebox_override("panel", UI.style(background, Color.TRANSPARENT, 14, 10, 1)); parent.add_child(band)
	var label := _label(band, title, 18, Color.WHITE); label.add_theme_font_override("font", UI.font(650))

static func _clock(parent: Node, n: Dictionary) -> void:
	var row := U.row(parent)
	_label(row, "%02d 分" % int(n.get("elapsed_minutes", 0)), 21, INK)
	var next := int(n.get("next_event_minute", -1))
	var pending_input: bool = n.get("schedule", []).any(func(event): return str(event.get("status", "")) == "scheduled" and int(event.get("due_minute", -1)) == next)
	_label(row, ("次の入力 %d分" if pending_input else "受付期限超過 %d分") % next if next >= 0 else "予定入力 完了", 13, MUTED)
	_label(row, "持出し %d行" % int(n.get("leaked_rows", 0)), 15, Color("ae6528") if int(n.get("leaked_rows", 0)) > 0 else INK)
	_label(row, "補償 ¥%d" % (int(n.get("impact_cost", 0)) + int(n.get("business", {}).get("loss_cost", 0))), 13, MUTED)

static func _latest(n: Dictionary, action: String) -> Dictionary:
	var found: Dictionary = {}
	for record in n.get("records", []):
		if str(record.get("action", "")) == action: found = record
	return found

static func _measurement(d, parent: Node, n: Dictionary, action: String, title: String) -> void:
	var record := _latest(n, action); var status := int(record.get("status", 0))
	var stale := not record.is_empty() and int(record.get("world_revision", -1)) != int(n.get("world_revision", 0))
	var text := title + " · " + ("? 未実測" if record.is_empty() else ("旧設定 " if stale else "") + str(status))
	var button := _button(parent, text, "AiObservation_" + action, _open.bind(d, str(record.get("id", ""))))
	button.disabled = record.is_empty()

static func _wiring(d, parent: Node, n: Dictionary) -> void:
	_band(parent, "AI-07   /   TOOL ACCESS ROUTER")
	_clock(parent, n)
	var actions := U.row(parent)
	_button(actions, "範囲外要求を試験 · 2分", "AiBoundaryProbe", _send.bind(d, "probe_boundaries"))
	_button(actions, "入力を3分待つ", "AiWait", _send.bind(d, "wait"))
	_button(actions, "AI-301 承認票", "AiOpenApproval", U.choose.bind(d, KIND, "approval_open", not bool(U.state(d, KIND).get("approval_open", false))))
	if bool(U.state(d, KIND).get("approval_open", false)):
		_label(parent, "承認 AI-301  /  FAQ・配送進捗 → 要約6件 → 社内問い合わせ受付", 14, TEAL)
		_label(parent, "顧客連絡先は参照対象外。外部support-dropは送付先に含まれません。", 13, MUTED)
		var approval_row := U.row(parent)
		for prior in n.get("records", []):
			if str(prior.get("action", "")) != "baseline_reference" or str(prior.get("data", {}).get("original", {}).get("action", "")) != "consent_review": continue
			var original: Dictionary = prior.data.original
			_button(approval_row, "前回 " + str(original.get("data", {}).get("approved_change", "")) + " / 委託先送付", "AiPriorApproval", _open.bind(d, str(prior.get("id", ""))))
		_label(approval_row, "→", 18, MUTED)
		_button(approval_row, "今回 AI-301 / 社内要約", "AiCurrentApproval", _open.bind(d, "AI-301"))
	var observations := U.row(parent)
	_measurement(d, observations, n, "boundary_read", "顧客連絡先")
	_measurement(d, observations, n, "boundary_write", "外部送付")
	_measurement(d, observations, n, "run_business", "問い合わせ")
	_raw(d, parent, n)
	var graph := Diagram.new(); parent.add_child(graph)
	graph.configure(n, float(d.game.settings.get("text_scale", 1.0)), _policy.bind(d))
	var events := U.row(parent)
	for event in n.get("schedule", []):
		var status := str(event.get("status", "scheduled"))
		_label(events, "%s %d分 · %s" % ["◇" if status == "scheduled" else "↑" if int(event.get("row_count", 0)) > 0 else "×", int(event.get("due_minute", 0)), "入力待ち" if status == "scheduled" else "%d行 送出" % int(event.get("row_count", 0)) if int(event.get("row_count", 0)) > 0 else "範囲外要求を拒否"], 13, MUTED)

static func _desk(d, parent: Node, n: Dictionary) -> void:
	_band(parent, "HOKUTO / 問い合わせ受付", Color("3c6276"))
	_clock(parent, n)
	var business: Dictionary = n.get("business", {})
	var row := U.row(parent)
	var receipt := str(business.get("receipt_id", ""))
	var run := _button(row, "現在の受付を確認済み" if bool(business.get("current", false)) else "同じ6件を再確認 · 2分" if not receipt.is_empty() else "問い合わせ6件を実行 · 2分", "AiBusinessRun", _send.bind(d, "run_business"))
	run.disabled = bool(business.get("current", false))
	_button(row, "資料と送付口へ", "AiReturnWiring", U.choose.bind(d, KIND, "tab", "wiring"))
	_label(row, "受付期限 %d分" % int(business.get("deadline_minute", 14)), 14, MUTED)
	var selected := int(U.state(d, KIND).get("inquiry_index", -1))
	var requests: Array = business.get("requests", []); var summaries: Array = business.get("accepted_summaries", [])
	if selected >= 0 and selected < requests.size():
		var request: Dictionary = requests[selected]
		var heading := U.row(parent); _label(heading, str(request.get("id", "")) + " / " + str(request.get("subject", "")), 16)
		_button(heading, "閉じる", "AiCloseInquiry", U.choose.bind(d, KIND, "inquiry_index", -1))
		_label(parent, str(summaries[selected].get("summary", "")) if selected < summaries.size() else "この問い合わせの要約はまだ生成されていません。", 15)
	var tickets := TicketDesk.new(); parent.add_child(tickets); tickets.configure(business, float(d.game.settings.get("text_scale", 1.0)), _inquiry.bind(d))
	var receipt_row := U.row(parent)
	_label(receipt_row, "未受付" if receipt.is_empty() else "受付控え  " + receipt, 20, TEAL if not receipt.is_empty() else MUTED)
	_measurement(d, receipt_row, n, "run_business", "現在の業務接続")
	_label(parent, "FAQ 24件 + 配送進捗 120行 → 要約 6件 → 社内問い合わせ", 14, MUTED)
	if int(business.get("loss_cost", 0)) > 0: _label(parent, "期限超過の補償 ¥%d / 再受付後も精算に残ります" % int(business.loss_cost), 14, Color("ae6528"))
	_raw(d, parent, n)

static func _source_records(n: Dictionary) -> Array:
	return n.get("records", []).filter(func(record): return str(record.get("action", "")) not in ["organize_manual", "organize_assistant", "submit_report"])

static func _select_all(d, n: Dictionary) -> void:
	var ids: Array = []
	var sources := _source_records(n)
	if sources.size() > 32:
		var latest: Dictionary = {}
		for record in sources:
			var action := str(record.get("action", ""))
			var key := action + ":" + str(record.get("id", "")) if action in ["consent_review", "baseline_reference", "scheduled_customer_read", "scheduled_external_write", "summary_overdue"] else action + ":" + str(record.get("data", {}).get("key", "")) if action == "configure_policy" else action
			if not latest.has(key) or int(record.get("seq", 0)) > int(latest[key].get("seq", 0)): latest[key] = record
		sources = latest.values()
		sources.sort_custom(func(a, b): return int(a.get("seq", 0)) < int(b.get("seq", 0)))
	for record in sources: ids.append(str(record.get("id", "")))
	U.choose(d, KIND, "record_ids", ids)

static func _inquiry(index: int, d) -> void:
	d.widgets.advanced.next_scroll = 0
	U.choose(d, KIND, "inquiry_index", index)

static func _name(record: Dictionary) -> String:
	return str({"consent_review":"承認票 AI-301", "baseline_reference":"前回の納品原本", "run_business":"問い合わせ受付", "boundary_read":"範囲外の参照試験", "boundary_write":"範囲外の送付試験", "scheduled_customer_read":"稼働中の資料要求", "scheduled_external_write":"稼働中の送付要求", "summary_overdue":"受付期限を超過", "configure_policy":"権限の適用", "collect_audit":"監査スナップショット"}.get(str(record.get("action", "")), str(record.get("action", ""))))

static func _records(d, parent: Node, n: Dictionary) -> void:
	_band(parent, "EVIDENCE / AI連携の審査記録")
	_clock(parent, n)
	var s := U.state(d, KIND); var ids: Array = s.get("record_ids", [])
	var assistant: Dictionary = d.game.record_assistant_status()
	var report: Dictionary = n.get("report", {}); var organization: Dictionary = n.get("organization", {})
	var actions := U.row(parent)
	_button(actions, "監査を取得 · 2分", "AiCollectAudit", _send.bind(d, "collect_audit"))
	_button(actions, "最新の原本と測定を選択" if _source_records(n).size() > 32 else "全記録を選択", "AiSelectAll", _select_all.bind(d, n))
	_label(actions, "選択 %d / 32件" % ids.size(), 14)
	var tools_row := U.row(parent)
	var sorted_ids := ids.duplicate(); sorted_ids.sort()
	var same: bool = "|".join(sorted_ids) == str(organization.get("input_hash", ""))
	var assisted := _button(tools_row, "保存した照合を再表示 · 無料" if same and str(organization.get("mode", "")) == "assistant" else "助手で照合 · 2分 / ¥300", "AiOrganizeAssistant", _send.bind(d, "organize_records", {"mode":"assistant", "record_ids":ids}))
	assisted.disabled = ids.is_empty() or ids.size() > 32 or not bool(assistant.get("owned", false))
	var manual := _button(tools_row, "保存した照合を再表示 · 無料" if same and str(organization.get("mode", "")) == "manual" else "手動で照合 · 5分", "AiOrganizeManual", _send.bind(d, "organize_records", {"mode":"manual", "record_ids":ids})); manual.disabled = ids.is_empty()
	var submit := _button(tools_row, "原記録を追補 · 2分" if bool(report.get("submitted", false)) else "原記録を報告 · 2分", "AiSubmitReport", _send.bind(d, "submit_report", {"record_ids":ids})); submit.disabled = ids.is_empty()
	manual.disabled = ids.is_empty() or ids.size() > 32; submit.disabled = ids.is_empty() or ids.size() > 32
	if not bool(assistant.get("owned", false)):
		var buy := _button(parent, "記録整理助手を導入 · ¥3000", "AiBuyAssistant", _buy.bind(d)); buy.disabled = not bool(assistant.get("can_purchase", false))
	if bool(report.get("submitted", false)): _label(parent, "▤ 報告 第%d版 / " % int(report.get("version", 1)) + ("現在の根拠を提出済み" if bool(n.get("report_fresh", false)) else "変更・損失の追補が必要"), 15, TEAL)
	_raw(d, parent, n)
	var comparison: Dictionary = organization.get("comparison", {})
	if not comparison.is_empty():
		_label(parent, "照合 %d分時点 / 設定v%d / 原記録だけを参照" % [int(comparison.get("created_minute", 0)), int(comparison.get("world_revision", 0))], 14, TEAL)
		var lanes: Dictionary = comparison.get("lanes", {})
		for key in ["read", "write", "business"]:
			var lane: Dictionary = lanes.get(key, {}); var refs: Array = lane.get("record_ids", [])
			var record_id := str(refs.back()) if not refs.is_empty() else ""
			var status := int(lane.get("status", 0)); var unknown := status == 0
			var row := U.row(parent)
			_label(row, str({"read":"資料棚 → 参照口", "write":"送付口 → 外部", "business":"要約 → 問い合わせ受付"}[key]), 15)
			_label(row, "? 根拠未選択" if unknown else ("過去 " if int(lane.get("world_revision", lane.get("revision", -1))) != int(n.get("world_revision", 0)) else "") + str(status), 18, MUTED if unknown else TEAL)
			var open := _button(row, record_id if not record_id.is_empty() else "原記録なし", "AiComparison_" + key, _open.bind(d, record_id)); open.disabled = record_id.is_empty()
	var expanded := bool(s.get("show_sources", false))
	_button(parent, ("▾" if expanded else "▸") + " 選択する原記録", "AiShowSources", U.choose.bind(d, KIND, "show_sources", not expanded))
	if expanded:
		for record in _source_records(n):
			var id := str(record.get("id", "")); var row := U.row(parent)
			var check := CheckBox.new(); check.name = "AiRecordSelect_" + id; check.button_pressed = id in ids; check.disabled = ids.size() >= 32 and id not in ids; check.tooltip_text = "照合・報告に含める " + id; row.add_child(check)
			check.toggled.connect(func(value):
				var chosen: Array = U.state(d, KIND).get("record_ids", []).duplicate()
				if value and id not in chosen: chosen.append(id)
				elif not value: chosen.erase(id)
				U.choose(d, KIND, "record_ids", chosen))
			_label(row, "%02d分" % int(record.get("minute", 0)), 12, MUTED)
			_button(row, _name(record) + " · " + id, "AiRecord_" + id, _open.bind(d, id))
			_label(row, str(record.get("status", "")), 13, MUTED)

static func _buy(d) -> void:
	var bought: bool = d.game.buy_record_assistant()
	U.state(d, KIND).message = "記録整理助手を導入しました。" if bought else str(d.game.record_assistant_status().get("reason", "導入できませんでした。"))
	d._refresh_advanced.call_deferred()

static func _open(d, id: String) -> void:
	d.widgets.advanced.next_scroll = 0
	U.choose(d, KIND, "open_record", id)

static func _raw(d, parent: Node, n: Dictionary) -> void:
	var id := str(U.state(d, KIND).get("open_record", "")); var selected: Dictionary = {}
	for record in n.get("records", []):
		if str(record.get("id", "")) == id: selected = record; break
	if selected.is_empty(): return
	var row := U.row(parent); _label(row, "原記録 " + id, 15)
	_button(row, "閉じる", "AiCloseRecord", U.choose.bind(d, KIND, "open_record", ""))
	var raw := TextEdit.new(); raw.name = "AiRawRecord"; raw.editable = false; raw.text = JSON.stringify(selected, "\t")
	raw.custom_minimum_size.y = 150 * float(d.game.settings.get("text_scale", 1.0)); raw.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; U.text_style(raw); parent.add_child(raw)
