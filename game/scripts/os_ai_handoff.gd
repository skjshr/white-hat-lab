extends RefCounted
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Diagram = preload("res://scripts/ai_handoff_canvas.gd")
const EvidenceDesk = preload("res://scripts/ai_handoff_evidence_canvas.gd")
const KIND := "advanced-saas-ai-handoff"
const BG = Color("12232f")
const INK = Color("eef0e7")
const MUTED = Color("b2c1c6")
const AMBER = Color("f1bb68")
const MINT = Color("9bd2c2")

static func build(d, parent: VBoxContainer) -> void:
	U.mount(d, parent, KIND, "Dispatch Control / 配送障害連絡")
	refresh(d)

static func refresh(d) -> void:
	var data: Dictionary = d.game.advanced_view(); var n: Dictionary = data.get("handoff", {})
	var workspace: Dictionary = d.widgets.advanced
	var tab := str(U.state(d, KIND).get("tab", "scope"))
	if str(workspace.get("handoff_rendered_tab", tab)) != tab: workspace.next_scroll = 0
	var body: VBoxContainer = U.begin(d, KIND, data)
	if body == null or n.is_empty(): return
	workspace.handoff_rendered_tab = tab
	U.navigation(d, KIND, [["scope", "連携の範囲"], ["dispatch", "3便の連絡受付"], ["records", "原本・照合"], ["results", "受入確認"]], "scope", "AiHandoffTab_")
	for button in d.widgets.advanced.nav.get_children():
		if button is Button:
			for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: button.add_theme_color_override(key, Color("243b40"))
	if tab == "results":
		U.checks(body, data); return
	var panel := PanelContainer.new(); panel.name = "AiHandoffSurface"
	panel.add_theme_stylebox_override("panel", UI.style(BG, Color("395463"), 0, 9, 8)); body.add_child(panel)
	var surface := VBoxContainer.new(); surface.add_theme_constant_override("separation", 7); surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.add_child(surface)
	match tab:
		"dispatch": _dispatch(d, surface, n)
		"records": _records(d, surface, n)
		_: _scope(d, surface, n)

static func _label(parent: Node, value: String, size: int = 14, color: Color = INK) -> Label:
	return U.label(parent, value, size, color, not parent is HFlowContainer)

static func _button(parent: Node, value: String, id: String, callback: Callable) -> Button:
	var button := U.button(parent, value, id, callback)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: button.add_theme_color_override(key, INK)
	button.add_theme_color_override("font_disabled_color", Color("afbabd"))
	for key in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(key, UI.style(Color("263e4d") if key == "normal" else Color("3f5660") if key != "disabled" else Color("1a2f3d"), Color("64818a"), 6, 6, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))
	return button

static func _send(d, action: String, args: Dictionary = {}) -> void:
	U.send(d, KIND, action, args)

static func _policy(key: String, value: Variant, d) -> void:
	_send(d, "configure", {"key":key, "value":value} if key == "contacts" else {"key":key, "enabled":value})

static func _show_event(id: String, d) -> void:
	var state := U.state(d, KIND); state.open_record = ""; state.tab = "scope"
	d.widgets.advanced.next_scroll = 0; U.choose(d, KIND, "flow_event", id)

static func _timeline(d, parent: Node, n: Dictionary) -> void:
	var row := U.row(parent)
	_label(row, "%02d 分" % int(n.get("elapsed_minutes", 0)), 20, AMBER)
	var selected := str(U.state(d, KIND).get("flow_event", ""))
	var current := _button(row, "● 現在の設定" if selected.is_empty() else "現在の設定へ", "AiHandoffCurrent", _show_event.bind("", d)); current.disabled = selected.is_empty()
	for item in n.get("schedule", []):
		var id := str(item.get("id", "")); var status := str(item.get("status", "scheduled")); var due := int(item.get("due_minute", 0))
		var label := "%d分  … 予定" % due if status == "scheduled" else "%d分  ↑通信" % due if int(item.get("write_status", 0)) == 200 else "%d分  ×通信" % due
		var event := _button(row, label, "AiHandoffEvent_" + id, _show_event.bind(id, d)); event.disabled = status == "scheduled" or id == selected
	var business: Dictionary = n.get("business", {})
	_label(row, "受付 %d分まで" % int(business.get("deadline_minute", 12)) + (" · 遅延" if bool(business.get("late", false)) else " · ✓" if not str(business.get("receipt_id", "")).is_empty() else ""), 13, MUTED)

static func _scope(d, parent: Node, n: Dictionary) -> void:
	var selected := str(U.state(d, KIND).get("flow_event", ""))
	var actions := U.row(parent)
	var probe := _button(actions, "範囲外要求を試験 · 2分", "AiHandoffProbe", _send.bind(d, "probe_boundaries")); probe.disabled = not selected.is_empty()
	var wait := _button(actions, "次の入力を待つ · 3分", "AiHandoffWait", _send.bind(d, "wait")); wait.disabled = not selected.is_empty()
	_button(actions, "3便の連絡受付へ", "AiHandoffOpenDispatch", U.choose.bind(d, KIND, "tab", "dispatch"))
	_button(actions, "AI-401 承認票", "AiHandoffApproval", _open.bind(d, "AI-401"))
	_timeline(d, parent, n)
	_raw(d, parent, n)
	var graph := Diagram.new(); parent.add_child(graph)
	graph.configure(n, float(d.game.settings.get("text_scale", 1.0)), _policy.bind(d), _diagram_record.bind(d), selected)

static func _latest(n: Dictionary, action: String) -> Dictionary:
	var latest: Dictionary = {}
	for record in n.get("records", []):
		if str(record.get("action", "")) == action: latest = record
	return latest

static func _dispatch(d, parent: Node, n: Dictionary) -> void:
	var business: Dictionary = n.get("business", {}); var receipt := str(business.get("receipt_id", ""))
	var row := U.row(parent)
	var run := _button(row, "現在設定で受付確認済み" if bool(business.get("current", false)) else "同じ3便を再確認 · 2分" if not receipt.is_empty() else "3便の連絡を送付 · 2分", "AiHandoffRun", _send.bind(d, "run_business")); run.disabled = bool(business.get("current", false))
	_button(row, "資料と送付口へ", "AiHandoffReturnScope", _show_event.bind("", d))
	_label(row, "%02d分 / 受付期限 %d分" % [int(n.get("elapsed_minutes", 0)), int(business.get("deadline_minute", 12))], 16, AMBER)
	var header := U.row(parent)
	_label(header, "MINATO  /  障害連絡の配送袋", 20, AMBER)
	_label(header, "当該3便 → /dispatch", 14, MUTED)
	var observed := _latest(n, "run_business"); var status := int(observed.get("status", 0))
	var stale := not observed.is_empty() and int(observed.get("world_revision", -1)) != int(n.get("world_revision", 0))
	var observation_row := U.row(parent)
	_label(observation_row, "現在設定 v%d" % int(n.get("world_revision", 0)), 13, MUTED)
	var measured := _button(observation_row, "? 未実行" if observed.is_empty() else ("旧設定 " if stale else "") + ("↑ 業務200" if status == 200 else "× 業務%d" % status), "AiHandoffBusinessRecord", _open.bind(d, str(observed.get("id", "")))); measured.disabled = observed.is_empty()
	_label(observation_row, "未受付" if receipt.is_empty() else "✓ 保存済み受付 " + receipt, 14, MINT if not receipt.is_empty() else MUTED)
	var bags := Diagram.Bags.new(); parent.add_child(bags); bags.configure(business, float(d.game.settings.get("text_scale", 1.0)), _job.bind(d))
	if int(business.get("loss_cost", 0)) > 0: _label(parent, "▧ 期限超過の補償 ¥%d · 受付後も精算に残ります" % int(business.loss_cost), 15, AMBER)
	var selected := int(U.state(d, KIND).get("job_index", -1)); var jobs: Array = business.get("jobs", [])
	if selected >= 0 and selected < jobs.size():
		var job: Dictionary = jobs[selected]; var details := U.row(parent)
		_label(details, str(job.get("shipment_id", "")) + " / " + str(job.get("contact_name", "")), 16, AMBER)
		_button(details, "閉じる", "AiHandoffCloseJob", U.choose.bind(d, KIND, "job_index", -1))
		_label(parent, str(job.get("status_detail", "")) + "  /  " + str(job.get("eta", "")), 14)
		_label(parent, str(job.get("instruction", "")), 14, MUTED)
	_raw(d, parent, n)

static func _job(index: int, d) -> void:
	U.choose(d, KIND, "job_index", index)

static func _source_records(n: Dictionary) -> Array:
	return n.get("records", []).filter(func(record): return str(record.get("action", "")) not in ["organize_manual", "organize_assistant", "submit_report"])

static func _select_all(d, n: Dictionary) -> void:
	var chosen: Array = []; var sources := _source_records(n); var available: Array = sources.map(func(record): return str(record.get("id", "")))
	for id in n.get("report", {}).get("required_record_ids", []):
		if str(id) in available and str(id) not in chosen and chosen.size() < 32: chosen.append(str(id))
	for index in range(sources.size() - 1, -1, -1):
		var id := str(sources[index].get("id", ""))
		if id not in chosen and chosen.size() < 32: chosen.append(id)
	U.choose(d, KIND, "record_ids", chosen)

static func _record_name(record: Dictionary) -> String:
	return str({"consent_review":"AI-401 承認原本", "baseline_reference":"前回の納品原本", "configure_policy":"権限適用", "boundary_read":"無関係な連絡先の試験", "boundary_write":"/archive の試験", "run_business":"3便の連絡受付", "scheduled_customer_read":"予定通信 / 連絡先参照", "scheduled_external_write":"予定通信 / archive送付", "summary_overdue":"受付期限超過", "collect_audit":"監査原本", "wait":"入力待ち"}.get(str(record.get("action", "")), str(record.get("action", ""))))

static func _group_ids(n: Dictionary, group: String) -> Array:
	var found: Dictionary = {}
	for record in _source_records(n):
		var action := str(record.get("action", ""))
		var key := ""
		if group == "previous" and action == "baseline_reference" and str(record.get("data", {}).get("original", {}).get("action", "")) == "consent_review": key = "approval"
		elif group == "current" and action == "consent_review": key = "approval"
		elif group == "measurements" and action in ["boundary_read", "boundary_write", "run_business"]: key = action
		if not key.is_empty() and int(record.get("seq", -1)) > int(found.get(key, {}).get("seq", -2)): found[key] = record
	return found.values().map(func(record): return str(record.get("id", "")))

static func _toggle_group(d, group_ids: Array) -> void:
	var selected: Array = U.state(d, KIND).get("record_ids", []).duplicate()
	var remove := group_ids.all(func(id): return id in selected)
	if not remove and selected.size() + group_ids.filter(func(id): return id not in selected).size() > 32: return
	for id in group_ids:
		if remove: selected.erase(id)
		elif id not in selected and selected.size() < 32: selected.append(id)
	U.choose(d, KIND, "record_ids", selected)

static func _records(d, parent: Node, n: Dictionary) -> void:
	var s := U.state(d, KIND); var ids: Array = s.get("record_ids", [])
	var assistant: Dictionary = d.game.record_assistant_status(); var report: Dictionary = n.get("report", {}); var organization: Dictionary = n.get("organization", {})
	var top := U.row(parent); _label(top, "EVIDENCE / 承認と実測の照合台", 19, AMBER)
	_label(top, "選択 %d / 32件" % ids.size(), 13, MUTED)
	var tray := U.row(parent)
	for group in [["previous", "前回承認"], ["current", "今回承認"], ["measurements", "最新の実測"]]:
		var group_ids := _group_ids(n, str(group[0]))
		var included := not group_ids.is_empty() and group_ids.all(func(id): return id in ids)
		var full := not included and ids.size() + group_ids.filter(func(id): return id not in ids).size() > 32
		var pick := _button(tray, ("✓ " if included else "+ ") + str(group[1]), "AiHandoffPick_" + str(group[0]), _toggle_group.bind(d, group_ids))
		pick.toggle_mode = true; pick.button_pressed = included; pick.disabled = group_ids.is_empty() or full
		pick.tooltip_text = "32件を超えます。原記録の選択を外してください" if full else "照合・報告の選択から外す" if included else "取得済み原本を照合・報告の選択へ載せる" if not group_ids.is_empty() else "業務実行・範囲外試験の記録がまだありません"
	var tools_row := U.row(parent); var sorted := ids.duplicate(); sorted.sort()
	var same := "|".join(sorted) == str(organization.get("input_hash", ""))
	var assisted := _button(tools_row, "保存した照合を開く · 無料" if same and str(organization.get("mode", "")) == "assistant" else "助手で照合 · 2分 / ¥300", "AiHandoffOrganizeAssistant", _send.bind(d, "organize_records", {"mode":"assistant", "record_ids":ids}))
	assisted.disabled = ids.is_empty() or ids.size() > 32 or not bool(assistant.get("owned", false))
	var manual := _button(tools_row, "保存した照合を開く · 無料" if same and str(organization.get("mode", "")) == "manual" else "手動で照合 · 5分", "AiHandoffOrganizeManual", _send.bind(d, "organize_records", {"mode":"manual", "record_ids":ids})); manual.disabled = ids.is_empty() or ids.size() > 32
	if not bool(assistant.get("owned", false)):
		var buy := _button(parent, "記録整理助手を導入 · ¥%d" % int(assistant.get("purchase_cost", 3000)), "AiHandoffBuyAssistant", _buy.bind(d)); buy.disabled = not bool(assistant.get("can_purchase", false))
		if buy.disabled: _label(parent, str(assistant.get("reason", "")), 13, MUTED)
	_raw(d, parent, n)
	var comparison: Dictionary = organization.get("comparison", {})
	var topic := str(s.get("evidence_topic", "contacts")); var subjects := U.row(parent)
	for item in [["contacts", "連絡先"], ["recipient", "送付先"], ["business", "配送受付"]]:
		var select := _button(subjects, str(item[1]), "AiHandoffEvidenceTopic_" + str(item[0]), U.choose.bind(d, KIND, "evidence_topic", str(item[0])))
		select.toggle_mode = true; select.button_pressed = topic == str(item[0])
	if comparison.is_empty(): _label(parent, "原本を載せて照合すると、選んだ根拠をこの台へ保存します。", 13, MUTED)
	elif not same: _label(parent, "選択を変更しました。図は前回保存した照合です。", 13, AMBER)
	var desk := EvidenceDesk.new(); parent.add_child(desk)
	desk.configure(comparison, float(d.game.settings.get("text_scale", 1.0)), _diagram_record.bind(d), _show_event.bind("", d), topic, int(n.get("world_revision", 0)))
	var actions := U.row(parent)
	_button(actions, "監査を取得 · 2分", "AiHandoffCollectAudit", _send.bind(d, "collect_audit"))
	_button(actions, "報告用の原本をまとめる", "AiHandoffSelectAll", _select_all.bind(d, n))
	var submit := _button(actions, "追補報告 · 2分" if bool(report.get("submitted", false)) else "原記録を報告 · 2分", "AiHandoffSubmitReport", _send.bind(d, "submit_report", {"record_ids":ids})); submit.disabled = ids.is_empty() or ids.size() > 32
	var missing: Array = []
	for id in report.get("required_record_ids", []):
		if str(id) not in ids: missing.append(str(id))
	if not missing.is_empty(): _label(parent, "報告用原本の選択漏れ %d件" % missing.size(), 13, AMBER)
	if bool(report.get("submitted", false)):
		_label(parent, "▤ 報告 第%d版 · " % int(report.get("version", 1)) + ("現在の根拠を提出済み" if bool(n.get("report_fresh", false)) else "旧記録 / 変更と損失の追補が必要"), 14, MINT)
	var expanded := bool(s.get("show_sources", false))
	_button(parent, ("▾" if expanded else "▸") + " 原記録を選ぶ / %d件" % _source_records(n).size(), "AiHandoffShowSources", U.choose.bind(d, KIND, "show_sources", not expanded))
	if expanded:
		for record in _source_records(n):
			var id := str(record.get("id", "")); var row := U.row(parent)
			var check := CheckBox.new(); check.name = "AiHandoffRecordSelect_" + id; check.button_pressed = id in ids
			check.disabled = ids.size() >= 32 and id not in ids; check.tooltip_text = "照合・報告に含める " + id; row.add_child(check)
			check.toggled.connect(func(value):
				var chosen: Array = U.state(d, KIND).get("record_ids", []).duplicate()
				if value and id not in chosen: chosen.append(id)
				elif not value: chosen.erase(id)
				U.choose(d, KIND, "record_ids", chosen))
			_label(row, "%02d分" % int(record.get("minute", 0)), 12, MUTED)
			var open := _button(row, _record_name(record) + " · " + id, "AiHandoffRecord_" + id, _open.bind(d, id)); open.tooltip_text = str(record.get("detail", ""))
			_label(row, ("当時 " if str(record.get("action", "")) in ["consent_review", "baseline_reference"] else "") + str(int(record.get("status", 0))), 13, MUTED)

static func _buy(d) -> void:
	var bought: bool = d.game.buy_record_assistant()
	U.state(d, KIND).message = "記録整理助手を導入しました。" if bought else str(d.game.record_assistant_status().get("reason", "導入できませんでした。"))
	d._refresh_advanced.call_deferred()

static func _diagram_record(id: String, d) -> void:
	_open(d, id)

static func _open(d, id: String) -> void:
	d.widgets.advanced.next_scroll = 0; U.state(d, KIND).raw_json = false; U.choose(d, KIND, "open_record", id)

static func _raw(d, parent: Node, n: Dictionary) -> void:
	var id := str(U.state(d, KIND).get("open_record", "")); var selected: Dictionary = {}
	for record in n.get("records", []):
		if str(record.get("id", "")) == id: selected = record; break
	if selected.is_empty(): return
	var row := U.row(parent); _label(row, "原記録 " + id + " / " + _record_name(selected), 14, AMBER)
	var action := str(selected.get("action", ""))
	if action == "baseline_reference":
		_label(parent, "前回納品の原本 / 今回の実測ではありません", 13, MUTED)
	elif action in ["boundary_read", "boundary_write", "run_business", "scheduled_customer_read", "scheduled_external_write"]:
		var measured := int(selected.get("world_revision", -1)); var current := int(n.get("world_revision", 0))
		_label(parent, "測定時 v%d / 現在 v%d · %s" % [measured, current, "現在の設定" if measured == current else "旧設定の記録"], 13, MUTED)
	_button(row, "閉じる", "AiHandoffCloseRecord", U.choose.bind(d, KIND, "open_record", ""))
	var original: Dictionary = selected.get("data", {}).get("original", {}) if action == "baseline_reference" else selected
	_label(parent, str(original.get("detail", "")), 14, INK)
	var expanded := bool(U.state(d, KIND).get("raw_json", false))
	_button(parent, "▾ JSON原本" if expanded else "▸ JSON原本", "AiHandoffExpandRaw", U.choose.bind(d, KIND, "raw_json", not expanded))
	if not expanded: return
	var raw := TextEdit.new(); raw.name = "AiHandoffRawRecord"; raw.editable = false; raw.text = JSON.stringify(selected, "\t")
	raw.custom_minimum_size.y = 145 * float(d.game.settings.get("text_scale", 1.0)); raw.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; U.text_style(raw); parent.add_child(raw)
