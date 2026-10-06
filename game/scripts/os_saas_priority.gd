extends RefCounted
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Board = preload("res://scripts/saas_priority_canvas.gd")
const KIND := "advanced-saas-priority"
const INK = Color("f0eee3")
const MUTED = Color("b5c7cd")
const AMBER = Color("edb767")
const RECIPIENTS := ["minato/dispatch", "minato/claims", "minato/archive"]

static func build(d, parent: VBoxContainer) -> void:
	U.mount(d, parent, KIND, "Dispatch Control / 復旧の優先順位"); refresh(d)

static func refresh(d) -> void:
	var data: Dictionary = d.game.advanced_view(); var n: Dictionary = data.get("priority", {})
	var tab := str(U.state(d, KIND).get("tab", "board")); var workspace: Dictionary = d.widgets.advanced
	if str(workspace.get("priority_tab", tab)) != tab: workspace.next_scroll = 0
	var body: VBoxContainer = U.begin(d, KIND, data)
	if body == null or n.is_empty(): return
	workspace.priority_tab = tab
	U.navigation(d, KIND, [["board", "業務搬送盤"], ["records", "原記録・報告"], ["results", "受入確認"]], "board", "PriorityTab_")
	for button in d.widgets.advanced.nav.get_children():
		if button is Button:
			for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: button.add_theme_color_override(key, Color("243d48"))
	if tab == "results": U.checks(body, data); return
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
	U.state(d, KIND).queue_id = queue_id; U.choose(d, KIND, "item_index", index)

static func _board(d, parent: Node, n: Dictionary) -> void:
	var queue := _selected(d, n)
	if queue.is_empty(): _label(parent, "業務データを確認できません", 15); return
	var id := str(queue.get("id", "")); var policy: Dictionary = queue.get("policy", {})
	var actions := U.row(parent); _label(actions, str(queue.get("label", id)), 17, AMBER)
	var current := bool(queue.get("current", false))
	var run := _button(actions, "現在設定で受付確認済み" if current else "受付を再確認 · 3分" if not str(queue.get("receipt_id", "")).is_empty() else "業務を送付 · 3分", "PriorityRun", _send.bind(d, "run_queue", {"queue_id":id})); run.disabled = current
	_button(actions, "範囲外要求を試験 · 2分", "PriorityProbe", _send.bind(d, "probe_queue", {"queue_id":id}))
	_impact_band(parent, n, float(d.game.settings.get("text_scale", 1.0)))
	if not n.get("recovery", {}).is_empty(): _recovery_actions(d, parent, n, queue)
	var controls := U.row(parent); _label(controls, "範囲", 13, MUTED)
	for scope in ["off", "linked", "all"]:
		var text := "0件" if scope == "off" else "当該%d件" % int(queue.get("approved_count", 0)) if scope == "linked" else "全%d件" % int(queue.get("all_count", 0))
		var button := _button(controls, text, "PriorityScope_" + scope, _send.bind(d, "configure", {"queue_id":id, "key":"scope", "value":scope}))
		button.toggle_mode = true; button.button_pressed = str(policy.get("scope", "off")) == scope; button.disabled = button.button_pressed; button.tooltip_text = "範囲を適用 · 1分"
	_label(controls, "送付扉", 13, MUTED)
	var recipient := OptionButton.new(); recipient.name = "PriorityRecipient"; recipient.tooltip_text = "送付先を適用 · 1分"
	var recipient_options: Array = n.get("recipient_options", RECIPIENTS)
	for path in recipient_options: recipient.add_item(str(path))
	var selected_index := recipient_options.find(str(policy.get("recipient", ""))); recipient.select(selected_index)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: recipient.add_theme_color_override(key, INK)
	for key in ["normal", "hover", "pressed"]: recipient.add_theme_stylebox_override(key, UI.style(Color("25414c"), Color("63828b"), 5, 6, 1))
	recipient.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2)); controls.add_child(recipient)
	recipient.item_selected.connect(func(index): _send(d, "configure", {"queue_id":id, "key":"recipient", "value":recipient_options[index]}))
	_raw(d, parent, n)
	var board := Board.new(); parent.add_child(board)
	board.configure(n, float(d.game.settings.get("text_scale", 1.0)), id, _select_queue.bind(d), _open_from_diagram.bind(d), _item.bind(d))
	var items: Array = queue.get("items", []); var selected_item := int(U.state(d, KIND).get("item_index", -1))
	if selected_item >= 0 and selected_item < items.size():
		var item: Dictionary = items[selected_item]; var detail := U.row(parent)
		_label(detail, str(item.get("id", "")) + " / " + str(item.get("label", "")), 15, AMBER)
		_button(detail, "閉じる", "PriorityCloseItem", U.choose.bind(d, KIND, "item_index", -1))
		_label(parent, str(item.get("detail", "")), 14)
		if item.has("amount"): _label(parent, "返金額 ¥%d" % int(item.amount), 14)
	var background: Dictionary = n.get("background", {}); var background_row := U.row(parent)
	_button(background_row, "背景同期を停止 · 1分" if bool(background.get("enabled", false)) else "背景同期を有効化 · 1分", "PriorityBackground", _send.bind(d, "toggle_background", {"enabled":not bool(background.get("enabled", false))}))
	_button(background_row, "同期口を試験 · 2分", "PriorityProbeBackground", _send.bind(d, "probe_background"))
	_button(background_row, "入力を待つ · 3分", "PriorityWait", _send.bind(d, "wait"))
	var conveyor := Board.Background.new(); parent.add_child(conveyor); conveyor.configure(n, float(d.game.settings.get("text_scale", 1.0)))
	var observations := U.row(parent)
	var latest: Dictionary = {}
	for record in n.get("records", []):
		if str(record.get("action", "")) in ["scheduled_background_send", "probe_background"]: latest = record
	var stale := not latest.is_empty() and int(latest.get("data", {}).get("background_revision", -1)) != int(background.get("policy_revision", 0))
	var status := int(latest.get("status", 0)); var source := "試験" if str(latest.get("action", "")) == "probe_background" else "通信"
	var result := _button(observations, "背景 ? 未実測" if latest.is_empty() else ("旧設定 " if stale else "") + "背景 " + source + (" ↑" if status == 200 else " ×") + str(status), "PriorityBackgroundRecord", _open.bind(d, str(latest.get("id", "")))); result.disabled = latest.is_empty()
	_label(observations, "補償累計 ¥%d" % (int(n.get("impact_cost", 0)) + int(n.get("loss_cost", 0))), 13, MUTED)

static func _impact_band(parent: Node, n: Dictionary, scale: float) -> void:
	var band := U.row(parent); band.name = "PriorityImpactBand"
	var leaked := int(n.get("leaked_rows", 0)); var impact := int(n.get("impact_cost", 0)); var delay := int(n.get("loss_cost", 0))
	_label(band, "累積 ↑ 流出 %d行 / 補償 ¥%d" % [leaked, impact], 14, AMBER if leaked > 0 or impact > 0 else MUTED)
	var delayed := HBoxContainer.new(); delayed.add_theme_constant_override("separation", 5); band.add_child(delayed)
	var ink := AMBER if delay > 0 else MUTED
	var saved_clock := Control.new(); saved_clock.custom_minimum_size = Vector2(18, 18) * scale; saved_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE; delayed.add_child(saved_clock)
	saved_clock.draw.connect(func():
		var center := saved_clock.size / 2
		saved_clock.draw_circle(center, 7 * scale, ink, false, 1.5 * scale)
		saved_clock.draw_line(center, center + Vector2(0, -4) * scale, ink, 1.5 * scale)
		saved_clock.draw_line(center, center + Vector2(4, 2) * scale, ink, 1.5 * scale))
	U.label(delayed, ("× " if delay > 0 else "") + "業務遅延補償 ¥%d" % delay, 14, ink, false)
	if not n.get("recovery", {}).is_empty(): _label(band, "手動受付費 ¥%d" % int(n.recovery.get("manual_usage_cost", 0)), 14, MUTED)

static func _recovery_actions(d, parent: Node, n: Dictionary, queue: Dictionary) -> void:
	var recovery: Dictionary = n.get("recovery", {}); var row := U.row(parent)
	var ready := str(recovery.get("connector_status", "stopped")) == "ready"
	var rebuild := _button(row, "新連携 復旧済み · %d分" % int(recovery.get("rebuilt_minute", 0)) if ready else "新連携を復旧 · %d分" % int(recovery.get("rebuild_minutes", 6)), "PriorityRebuild", _send.bind(d, "rebuild_connector")); rebuild.disabled = ready
	var available := int(recovery.get("manual_remaining", 0)) > 0
	var used_here := str(recovery.get("manual_queue_id", "")) == str(queue.get("id", ""))
	var title := "この業務を手動受付 · %d分 / ¥%d" % [int(recovery.get("manual_minutes", 2)), int(recovery.get("manual_cost", 900))]
	if not available: title = "手動受付済み · %d分" % int(recovery.get("manual_used_minute", 0)) if used_here else "手動枠 使用済み"
	elif not str(queue.get("receipt_id", "")).is_empty(): title = "受付済み / 手動不要"
	var manual := _button(row, title, "PriorityManual", _send.bind(d, "manual_queue", {"queue_id":str(queue.get("id", ""))}))
	manual.disabled = not available or not str(queue.get("receipt_id", "")).is_empty()
	manual.tooltip_text = str(queue.get("label", "")) + "の受付だけを手動で運びます。新連携と旧背景同期の設定は変わりません。"

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
	_raw(d, parent, n)
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
	_open(d, id)

static func _open(d, id: String) -> void:
	d.widgets.advanced.next_scroll = 0; U.state(d, KIND).raw_json = false; U.choose(d, KIND, "open_record", id)

static func _raw(d, parent: Node, n: Dictionary) -> void:
	var id := str(U.state(d, KIND).get("open_record", "")); var selected: Dictionary = {}
	for record in n.get("records", []):
		if str(record.get("id", "")) == id: selected = record; break
	if selected.is_empty(): return
	var row := U.row(parent); _label(row, id + " / " + _record_name(selected), 15, AMBER)
	_button(row, "閉じる", "PriorityCloseRecord", U.choose.bind(d, KIND, "open_record", ""))
	var original: Dictionary = selected.get("data", {}).get("original", {}) if str(selected.get("action", "")) == "baseline_reference" else selected
	_label(parent, "前回の保存原本 / 今回の実測ではありません" if str(selected.get("action", "")) == "baseline_reference" else "旧設定の実測" if _stale(selected, n) else "保存原本", 13, MUTED)
	_label(parent, str(original.get("detail", "")), 14)
	var expanded := bool(U.state(d, KIND).get("raw_json", false)); _button(parent, "▾ JSON原本" if expanded else "▸ JSON原本", "PriorityExpandRaw", U.choose.bind(d, KIND, "raw_json", not expanded))
	if expanded:
		var raw := TextEdit.new(); raw.name = "PriorityRawRecord"; raw.editable = false; raw.text = JSON.stringify(selected, "\t"); raw.custom_minimum_size.y = 145 * float(d.game.settings.get("text_scale", 1.0)); raw.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; U.text_style(raw); parent.add_child(raw)
