extends RefCounted

const M = preload("res://scripts/management_ui.gd")

static func build(ui, g) -> void:
	if not g.has_method("company_cycle_view"): return
	var view: Dictionary = g.company_cycle_view()
	var body := VBoxContainer.new(); body.name = "CompanyCycle"; body.add_theme_constant_override("separation", 14); ui.modal_body.add_child(body)
	body.add_child(ui._label("会社のこれから", 24, M.INK))
	_economy(ui, body, view.get("economy", {}))
	_action(ui, body, "今日の受取・在庫・人員を確認", ui._open_cycle_route.bind("company_overview"), "CycleOperations", "quiet")
	body.add_child(M.rule())
	body.add_child(ui._label("顧客からの指名相談", 18, M.INK))
	var opportunities: Array = view.get("opportunities", [])
	if opportunities.is_empty():
		body.add_child(ui._label("納品の実績を重ねると、顧客から別の業務について相談が届きます。まずは今の依頼を完了しましょう。", 14, M.MUTED))
		_action(ui, body, "今の仕事・営業を見る", ui._open_cycle_route.bind("sales"), "CycleBrowse", "quiet")
	for raw in opportunities:
		if raw is Dictionary: _opportunity(ui, g, body, raw)
	var goals: Array = view.get("goals", [])
	if not goals.is_empty():
		body.add_child(M.rule()); body.add_child(ui._label("会社の成長目標", 18, M.INK))
		for raw in goals:
			if raw is Dictionary: _goal(ui, body, raw)
	body.add_child(M.rule())
	body.add_child(ui._label("今日の運営", 18, M.INK))

static func _economy(ui, body: VBoxContainer, economy: Dictionary) -> void:
	var metrics := HFlowContainer.new(); metrics.name = "CycleEconomy"; metrics.add_theme_constant_override("h_separation", 24); metrics.add_theme_constant_override("v_separation", 10); body.add_child(metrics)
	for spec in [["cash", "現在の現金"], ["due_next_day", "翌日の入金予定"], ["settlement_costs", "日締めの支払見込み"]]:
		var column := VBoxContainer.new(); column.custom_minimum_size.x = 180; metrics.add_child(column)
		column.add_child(ui._label(str(spec[1]), 12, M.MUTED))
		var amount: Label = ui._label("¥" + ui._group_number(int(economy.get(str(spec[0]), 0))), 22, M.INK); amount.name = "CycleMoney_" + str(spec[0]); column.add_child(amount)
	var forecast: Label = ui._label("日締め直後の現金（翌日入金前）  ¥%s  ／  保守の差引  ¥%s" % [ui._group_number(int(economy.get("day_cash_after", economy.get("cash", 0)))), ui._group_number(int(economy.get("care_net", 0)))], 13, M.MUTED); forecast.name = "CycleCashForecast"; body.add_child(forecast)
	var receivable := int(economy.get("receivable_total", 0)); var drafts := int(economy.get("draft_total", 0))
	if receivable > 0 or drafts > 0:
		body.add_child(ui._label("未入金の請求  ¥%s  ／  未発行の請求下書き  ¥%s" % [ui._group_number(receivable), ui._group_number(drafts)], 13, M.MUTED))
		_action(ui, body, "請求と入金を確認", ui._open_company_billing, "CycleBilling", "quiet")
	var arrears := int(economy.get("payroll_arrears_after", 0))
	if arrears > 0:
		var warning: Label = ui._label("日締め後も残る未払給与  ¥%s。入金予定と人員の支出を確認してください。" % ui._group_number(arrears), 14, M.DANGER)
		warning.name = "CyclePayrollArrears"; body.add_child(warning)
		_action(ui, body, "人員と給与を確認", ui.open_panel.bind("staffing"), "CyclePayroll", "quiet")

static func _card(body: VBoxContainer, name: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.name = name; panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.add_theme_stylebox_override("panel", M.surface(M.CANVAS, 12)); body.add_child(panel)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 7); panel.add_child(content); return content

static func _opportunity(ui, g, body: VBoxContainer, item: Dictionary) -> void:
	var id := str(item.get("id", "")); var status := str(item.get("status", "locked"))
	var content := _card(body, "CycleOpportunity_" + id.validate_node_name())
	var state_text: String = {"ready":"相談できます", "locked":"準備が必要", "paused":"信頼の回復待ち", "fulfilled":"対応済み"}.get(status, "準備が必要")
	content.add_child(ui._label("%s  ·  %s" % [str(item.get("client", "")), state_text], 14, M.ACCENT if status in ["ready", "fulfilled"] else M.MUTED))
	content.add_child(ui._label(str(item.get("title", "")), 18, M.INK))
	content.add_child(ui._label(str(item.get("reason", "")), 14, M.INK))
	if not str(item.get("source_title", "")).is_empty():
		content.add_child(ui._label("きっかけ: DAY %02d「%s」の納品" % [int(item.get("source_day", 0)), str(item.source_title)], 12, M.MUTED))
	if status == "fulfilled": return
	var locked_reason := str(item.get("locked_reason", ""))
	if not locked_reason.is_empty(): content.add_child(ui._label(locked_reason, 13, M.MUTED))
	if status == "paused":
		content.add_child(ui._label(str(item.get("recovery_goal", "通常の依頼でこの顧客への期限内納品を完了し、顧客満足度40以上を確認してください。")), 13, M.MUTED))
		_action(ui, content, "この顧客の通常依頼を探す", ui._open_cycle_recovery.bind(str(item.get("client", ""))), "CycleRecover_" + id.validate_node_name(), "quiet")
	elif status == "locked":
		if bool(g.state.get("career_mode", false)) and item.get("reasons", []).is_empty():
			_action(ui, content, "日締めと翌日の営業を確認", ui.open_panel.bind("door"), "CycleWait_" + id.validate_node_name(), "quiet")
		else:
			_action(ui, content, "必要なスキル・成長を確認", ui._open_cycle_route.bind("company_growth"), "CyclePrepare_" + id.validate_node_name(), "quiet")
	else:
		var button := _action(ui, content, "この顧客の相談へ", ui._open_cycle_offer.bind(id), "CycleOpen_" + id.validate_node_name(), "primary")
		if not bool(g.state.get("career_mode", false)):
			var busy: bool = bool(g.state.get("accepted", false)) and not g.current_done()
			button.disabled = busy
			content.add_child(ui._label("進めている依頼を納品すると相談できます。" if busy else "営業を始めて、この相談の見積を確認します。初週の順番どおりに進める場合は、日締めへ戻れます。", 12, M.MUTED))

static func _goal(ui, body: VBoxContainer, goal: Dictionary) -> void:
	var id := str(goal.get("id", "")); var complete := bool(goal.get("complete", false))
	var content := _card(body, "CycleGoal_" + id.validate_node_name())
	content.add_child(ui._label(("達成  " if complete else "目標  ") + str(goal.get("title", "")), 16, M.ACCENT if complete else M.INK))
	if complete and int(goal.get("earned_day", 0)) > 0: content.add_child(ui._label("DAY %02d に達成。以下は現在の状況です。" % int(goal.earned_day), 12, M.MUTED))
	if not str(goal.get("description", "")).is_empty(): content.add_child(ui._label(str(goal.description), 13, M.MUTED))
	for raw in goal.get("requirements", []):
		if not raw is Dictionary: continue
		content.add_child(ui._label("%s  %s / %s%s" % [str(raw.get("label", "")), str(raw.get("current", 0)), str(raw.get("target", 0)), "  達成" if bool(raw.get("complete", false)) else ""], 13, M.INK))
	var progress := ProgressBar.new(); progress.name = "CycleProgress_" + id.validate_node_name(); progress.value = clampf(float(goal.get("progress", 0.0)), 0.0, 1.0) * 100; progress.show_percentage = false; progress.custom_minimum_size.y = 6; content.add_child(progress)
	if not complete:
		var route := str(goal.get("route", "sales"))
		var text: String = {"sales":"仕事を探す", "shop":"設備への投資を確認", "care":"顧客保守を確認", "company_growth":"スキル・成長を確認", "company_overview":"運営の状況を確認"}.get(route, "次の行動を確認")
		_action(ui, content, text, ui._open_cycle_route.bind(route), "CycleGoalAction_" + id.validate_node_name(), "quiet")

static func _action(ui, host: Node, title: String, action: Callable, name: String, role: String) -> Button:
	var button: Button = ui._button(title, action); button.name = name; button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; M.button(button, role); host.add_child(button); return button
