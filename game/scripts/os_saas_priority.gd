extends RefCounted
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Board = preload("res://scripts/saas_priority_canvas.gd")
const KIND := "advanced-saas-priority"
const INK = Color("f0eee3")
const MUTED = Color("b5c7cd")
const AMBER = Color("edb767")

static func build(d, parent: VBoxContainer) -> void:
	U.mount(d, parent, KIND, "Dispatch Control / 復旧の優先順位"); refresh(d)

static func refresh(d) -> void:
	var data: Dictionary = d.game.advanced_view(); var n: Dictionary = data.get("priority", {})
	var tab := str(U.state(d, KIND).get("tab", "board")); var workspace: Dictionary = d.widgets.advanced
	if str(workspace.get("priority_tab", tab)) != tab and not workspace.has("next_scroll"): workspace.next_scroll = 0
	var body: VBoxContainer = U.begin(d, KIND, data)
	if body == null or n.is_empty(): return
	workspace.priority_tab = tab
	U.navigation(d, KIND, [["board", "業務搬送盤"], ["records", "原記録・報告"], ["results", "受入確認"]], "board", "PriorityTab_")
	for button in d.widgets.advanced.nav.get_children():
		if button is Button:
			for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: button.add_theme_color_override(key, Color("243d48"))
	if tab == "results": U.checks(body, data); return
	# Keep the live workbench in view; open the compact response to read its full text.
	if tab == "board": workspace.feedback.hide()
	var panel := PanelContainer.new(); panel.theme = Board.tooltip_theme(float(d.game.settings.get("text_scale", 1.0))); panel.add_theme_stylebox_override("panel", UI.style(Color("132b36"), Color("48636d"), 10, 8, 7)); body.add_child(panel)
	var surface := VBoxContainer.new(); surface.add_theme_constant_override("separation", 7); panel.add_child(surface)
	if tab == "records": _records(d, surface, n)
	else: _board(d, surface, n)

static func _label(parent: Node, value: String, points: int = 14, color: Color = INK) -> Label:
	return U.label(parent, value, points, color, not parent is HFlowContainer)

static func _button(parent: Node, value: String, id: String, callback: Callable) -> Button:
	var button := U.button(parent, value, id, callback)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: button.add_theme_color_override(key, INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color("25414c") if key in ["normal", "disabled"] else Color("405761"), Color("63828b"), 5, 6, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2)); return button

static func _send(d, action: String, args: Dictionary = {}) -> void:
	U.send(d, KIND, action, args)

static func _selected(d, n: Dictionary) -> Dictionary:
	var wanted := str(U.state(d, KIND).get("queue_id", "dispatch"))
	for queue in n.get("queues", []):
		if str(queue.get("id", "")) == wanted: return queue
	return n.get("queues", [])[0] if not n.get("queues", []).is_empty() else {}

static func _select_queue(id: String, d) -> void:
	d.widgets.advanced.next_scroll = 0; U.state(d, KIND).item_index = -1
	U.choose(d, KIND, "queue_id", id)

static func _item(queue_id: String, index: int, d) -> void:
	var state := U.state(d, KIND)
	state.queue_id = queue_id; state.item_index = index; state.open_record = ""
	state.scroll_records = 0; U.choose(d, KIND, "tab", "records")

static func _board(d, parent: Node, n: Dictionary) -> void:
	var queue := _selected(d, n)
	if queue.is_empty(): _label(parent, "業務データを確認できません", 15); return
	var board := Board.new(); parent.add_child(board)
	var board_scale := maxf(float(d.game.settings.get("text_scale", 1.0)), minf(1.3, float(d.windows.advanced.size.x) / 960.0))
	board.configure(n, board_scale, str(queue.get("id", "")), _select_queue.bind(d), _open_from_diagram.bind(d), _item.bind(d), func(action: String, args: Dictionary): _send(d, action, args))
	var message := str(d.widgets.advanced.status.text)
	if not message.is_empty():
		var ok := bool(U.state(d, KIND).get("result_ok", d.game.advanced_view().get("last_result", {}).get("ok", true)))
		var status := _button(parent, ("✓ " if ok else "× ") + message + "  ↗", "PriorityResponse", _show_response.bind(d))
		status.custom_minimum_size.y = 24; status.alignment = HORIZONTAL_ALIGNMENT_LEFT
		status.add_theme_font_size_override("font_size", roundi(12 * float(d.game.settings.get("text_scale", 1.0))))
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.tooltip_text = message + "\n押すと原記録・報告で全文を表示"

static func _show_response(d) -> void:
	var state := U.state(d, KIND)
	state.item_index = -1; state.open_record = ""; state.scroll_records = 0
	U.choose(d, KIND, "tab", "records")

static func _item_detail(d, parent: Node, n: Dictionary) -> void:
	var queue := _selected(d, n)
	var items: Array = queue.get("items", []); var selected_item := int(U.state(d, KIND).get("item_index", -1))
	if selected_item < 0 or selected_item >= items.size(): return
	var item: Dictionary = items[selected_item]; var row := U.row(parent)
	_label(row, str(item.get("id", "")) + " / " + str(item.get("label", "")), 15, AMBER)
	_button(row, "閉じる", "PriorityCloseItem", U.choose.bind(d, KIND, "item_index", -1))
	_label(parent, str(item.get("detail", "")), 14)
	if item.has("amount"): _label(parent, "返金額 ¥%d" % int(item.amount), 14)

static func _sources(n: Dictionary) -> Array:
	return n.get("records", []).filter(func(record): return str(record.get("action", "")) not in ["organize_manual", "organize_assistant", "submit_report"])

static func _select_records(d, n: Dictionary) -> void:
	var chosen: Array = []; var sources := _sources(n); var available: Array = sources.map(func(record): return str(record.get("id", "")))
	for id in n.get("report", {}).get("required_record_ids", []):
		if str(id) in available and str(id) not in chosen: chosen.append(str(id))
	# Never silently truncate the model's required current proofs to make room for history.
	if chosen.size() > 32:
		U.state(d, KIND).message = "必須原本が%d件あり、32件の選択上限を超えています。選択は変更していません。" % chosen.size()
		U.state(d, KIND).result_ok = false; d._refresh_advanced.call_deferred(); return
	sources.sort_custom(func(a, b): return int(a.get("seq", -1)) > int(b.get("seq", -1)))
	for record in sources:
		var id := str(record.get("id", ""))
		if id not in chosen and chosen.size() < 32: chosen.append(id)
	U.choose(d, KIND, "record_ids", chosen)

static func _record_name(record: Dictionary) -> String:
	var action := str(record.get("action", "")); var queue := str(record.get("data", {}).get("queue_id", ""))
	var label := str({"consent_review":"承認原本", "baseline_reference":"前回の原本", "run_business":"業務受付", "manual_business":"手動の初回受付", "connector_incident":"共用連携の停止記録", "rebuild_connector":"新連携の復旧記録", "probe_queue":"範囲外試験", "configure_queue":"業務設定", "configure_policy":"業務設定", "configure_background":"背景同期設定", "scheduled_background_send":"背景の実通信", "probe_background":"背景の試験", "queue_overdue":"業務期限超過", "collect_audit":"監査原本"}.get(action, action))
	return label + (" / " + str({"dispatch":"配送", "claims":"返金"}.get(queue, queue)) if not queue.is_empty() else "")

static func _records(d, parent: Node, n: Dictionary) -> void:
	var state := U.state(d, KIND); var ids: Array = state.get("record_ids", [])
	var report: Dictionary = n.get("report", {}); var organization: Dictionary = n.get("organization", {}); var assistant: Dictionary = d.game.record_assistant_status()
	var heading := U.row(parent); _label(heading, "EVIDENCE / 二つの業務と背景同期", 18, AMBER); _label(heading, "選択 %d / 32件" % ids.size(), 13, MUTED)
	_button(heading, "搬送盤に戻る", "PriorityBackToBoard", U.choose.bind(d, KIND, "tab", "board"))
	_item_detail(d, parent, n)
	_raw(d, parent, n)
	var actions := U.row(parent)
	_button(actions, "監査を取得 · 2分", "PriorityCollectAudit", _send.bind(d, "collect_audit"))
	_button(actions, "報告用の原本をまとめる", "PrioritySelectAll", _select_records.bind(d, n))
	var sorted_ids := ids.duplicate(); sorted_ids.sort(); var same := "|".join(sorted_ids) == str(organization.get("input_hash", ""))
	var tools_row := U.row(parent)
	var assisted := _button(tools_row, "保存した整理を開く · 無料" if same and str(organization.get("mode", "")) == "assistant" else "助手で整理 · 2分 / ¥300", "PriorityOrganizeAssistant", _send.bind(d, "organize_records", {"mode":"assistant", "record_ids":ids})); assisted.disabled = ids.is_empty() or ids.size() > 32 or not bool(assistant.get("owned", false))
	var manual := _button(tools_row, "保存した整理を開く · 無料" if same and str(organization.get("mode", "")) == "manual" else "手動で整理 · 5分", "PriorityOrganizeManual", _send.bind(d, "organize_records", {"mode":"manual", "record_ids":ids})); manual.disabled = ids.is_empty() or ids.size() > 32
	var submit := _button(tools_row, "追補報告 · 2分" if bool(report.get("submitted", false)) else "原記録を報告 · 2分", "PrioritySubmitReport", _send.bind(d, "submit_report", {"record_ids":ids})); submit.disabled = ids.is_empty() or ids.size() > 32
	if not bool(assistant.get("owned", false)):
		var buy := _button(parent, "整理助手を導入 · ¥%d" % int(assistant.get("purchase_cost", 3000)), "PriorityBuyAssistant", _buy.bind(d)); buy.disabled = not bool(assistant.get("can_purchase", false))
		if buy.disabled: _label(parent, str(assistant.get("reason", "")), 13, MUTED)
	var missing: Array = report.get("required_record_ids", []).filter(func(id): return str(id) not in ids)
	if not missing.is_empty(): _label(parent, "報告用原本の選択漏れ %d件" % missing.size(), 13, AMBER)
	if bool(report.get("submitted", false)): _label(parent, "報告 第%d版 / " % int(report.get("version", 1)) + ("現在の根拠を提出済み" if bool(n.get("report_fresh", false)) else "変更・損失の追補が必要"), 14, AMBER)
	if not organization.is_empty():
		_label(parent, "保存した整理 · %d分 / 保存済み原記録だけを参照" % int(organization.get("created_minute", 0)), 14, AMBER)
		if not same: _label(parent, "選択を変更しました。下は前回保存した整理です。", 12, MUTED)
		var saved: Array = organization.get("records", [])
		for category in ["dispatch", "claims", "background", "other"]:
			var row := U.row(parent); _label(row, str({"dispatch":"配送便 →", "claims":"返金票 →", "background":"背景同期 →", "other":"原本 →"}[category]), 14, MUTED)
			for record in saved:
				if _category(record) != category: continue
				var id := str(record.get("id", "")); var status := int(record.get("status", 0)); var old := _stale(record, n)
				var text := "%d分 " % int(record.get("minute", 0)) + ("旧 " if old else "") + _record_name(record)
				if str(record.get("action", "")) not in ["consent_review", "baseline_reference"]: text += (" ↑" if status == 200 else " ×") + str(status)
				_button(row, text, "PriorityOrganized_" + id, _open.bind(d, id))
	var expanded := bool(state.get("show_sources", false)); _button(parent, ("▾" if expanded else "▸") + " 原記録を選ぶ / %d件" % _sources(n).size(), "PriorityShowSources", U.choose.bind(d, KIND, "show_sources", not expanded))
	if expanded:
		for record in _sources(n):
			var id := str(record.get("id", "")); var row := U.row(parent); var check := CheckBox.new()
			check.name = "PrioritySelect_" + id; check.button_pressed = id in ids; check.disabled = ids.size() >= 32 and id not in ids; check.tooltip_text = id; row.add_child(check)
			check.toggled.connect(func(value):
				var chosen: Array = U.state(d, KIND).get("record_ids", []).duplicate()
				if value and id not in chosen: chosen.append(id)
				elif not value: chosen.erase(id)
				U.choose(d, KIND, "record_ids", chosen))
			_button(row, "%02d分 " % int(record.get("minute", 0)) + _record_name(record) + " / " + id, "PriorityRecord_" + id, _open.bind(d, id))

static func _category(record: Dictionary) -> String:
	var queue := str(record.get("data", {}).get("queue_id", ""))
	if queue in ["dispatch", "claims"]: return queue
	if "background" in str(record.get("action", "")): return "background"
	return "other"

static func _stale(record: Dictionary, n: Dictionary) -> bool:
	var data: Dictionary = record.get("data", {}); var action := str(record.get("action", ""))
	if action in ["run_business", "probe_queue"]:
		if not n.get("recovery", {}).is_empty() and str(data.get("connector_record_id", "")) != str(n.recovery.get("rebuild_record_id", "")): return true
		for queue in n.get("queues", []):
			if str(queue.get("id", "")) == str(data.get("queue_id", "")): return int(data.get("policy_revision", -1)) != int(queue.get("policy_revision", 0))
	if action in ["probe_background", "scheduled_background_send"]: return int(data.get("background_revision", -1)) != int(n.get("background", {}).get("policy_revision", 0))
	return false

static func _buy(d) -> void:
	var bought: bool = d.game.buy_record_assistant(); U.state(d, KIND).message = "記録整理助手を導入しました。" if bought else str(d.game.record_assistant_status().get("reason", "導入できませんでした。")); d._refresh_advanced.call_deferred()

static func _open_from_diagram(id: String, d) -> void:
	var state := U.state(d, KIND)
	state.item_index = -1; state.open_record = id; state.raw_json = false
	state.scroll_records = 0; U.choose(d, KIND, "tab", "records")

static func _open(d, id: String) -> void:
	d.widgets.advanced.next_scroll = 0; U.state(d, KIND).raw_json = false; U.state(d, KIND).item_index = -1
	U.choose(d, KIND, "open_record", id)

static func _raw(d, parent: Node, n: Dictionary) -> void:
	var id := str(U.state(d, KIND).get("open_record", "")); var selected: Dictionary = {}
	for record in n.get("records", []):
		if str(record.get("id", "")) == id: selected = record; break
	if selected.is_empty(): return
	var row := U.row(parent); _label(row, id + " / " + _record_name(selected), 15, AMBER)
	_button(row, "閉じる", "PriorityCloseRecord", U.choose.bind(d, KIND, "open_record", ""))
	var original: Dictionary = selected.get("data", {}).get("original", {}) if str(selected.get("action", "")) == "baseline_reference" else selected
	_label(parent, "前回の保存原本 / 今回の実測ではありません" if str(selected.get("action", "")) == "baseline_reference" else "旧設定の実測" if _stale(selected, n) else "保存原本", 13, MUTED)
	if original.has("status") and str(original.get("action", "")) != "consent_review":
		_label(parent, "%d分 / 応答 %d / %s" % [int(original.get("minute", 0)), int(original.get("status", 0)), str(original.get("destination", ""))], 14, AMBER)
	_label(parent, str(original.get("detail", "")), 14)
	var expanded := bool(U.state(d, KIND).get("raw_json", false)); _button(parent, "▾ JSON原本" if expanded else "▸ JSON原本", "PriorityExpandRaw", U.choose.bind(d, KIND, "raw_json", not expanded))
	if expanded:
		var raw := TextEdit.new(); raw.name = "PriorityRawRecord"; raw.editable = false; raw.text = JSON.stringify(selected, "\t"); raw.custom_minimum_size.y = 145 * float(d.game.settings.get("text_scale", 1.0)); raw.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; U.text_style(raw); parent.add_child(raw)
