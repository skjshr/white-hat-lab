extends RefCounted

const M = preload("res://scripts/management_ui.gd")
const ROUTE = preload("res://scripts/customer_route_board.gd")

static func build(ui, g) -> void:
	if not g.has_method("company_cycle_view"): return
	var view: Dictionary = g.company_cycle_view()
	var body := VBoxContainer.new(); body.name = "CompanyCycle"; body.add_theme_constant_override("separation", 14); ui.modal_body.add_child(body)
	body.add_child(ui._label("顧客との仕事", 24, M.INK))
	var opportunities: Array = view.get("opportunities", [])
	if opportunities.is_empty():
		body.add_child(ui._label("納品の実績を重ねると、顧客から別の業務について相談が届きます。まずは今の依頼を完了しましょう。", 14, M.MUTED))
		_action(ui, body, "今の仕事・営業を見る", ui._open_cycle_route.bind("sales"), "CycleBrowse", "quiet")
	if not opportunities.is_empty():
		var chosen := str(ui.get_meta("cycle_customer", ""))
		if not opportunities.any(func(item): return str(item.get("id", "")) == chosen):
			var newest: Dictionary = opportunities[0]
			for item in opportunities:
				if int(item.get("source_day", 0)) > int(newest.get("source_day", 0)): newest = item
			chosen = str(newest.id)
		var contacts := HFlowContainer.new(); contacts.name = "CycleCustomers"; body.add_child(contacts)
		for raw in opportunities:
			if not raw is Dictionary: continue
			var button := _action(ui, contacts, str(raw.get("client", "")), _select_customer.bind(ui, str(raw.id)), "CycleCustomer_" + str(raw.id).validate_node_name(), "tab")
			M.button(button, "tab", str(raw.id) == chosen)
		for raw in opportunities:
			if raw is Dictionary and str(raw.id) == chosen: _opportunity(ui, g, body, raw)
	body.add_child(M.rule())
	_economy(ui, body, view.get("economy", {}))
	_action(ui, body, "今日の受取・在庫・人員を確認", ui._open_cycle_route.bind("company_overview"), "CycleOperations", "quiet")
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
	var content := VBoxContainer.new(); content.name = "CycleOpportunity_" + id.validate_node_name(); content.add_theme_constant_override("separation", 10); body.add_child(content)
	var details := VBoxContainer.new(); details.name = "CycleDetails"; details.visible = false
	var inspect := _toggle_details.bind(ui, details)
	var next: Callable = inspect
	var action_name := ""; var action_title := ""
	if status == "paused":
		next = ui._open_cycle_recovery.bind(str(item.get("client", ""))); action_name = "CycleRecover_" + id.validate_node_name(); action_title = "この顧客の通常依頼を探す"
	elif status == "locked":
		if bool(item.get("handoff_unavailable", false)):
			next = inspect; action_name = "CycleHandoffMissing"; action_title = "引継ぎ元の記録を確認"
		elif bool(g.state.get("career_mode", false)) and item.get("reasons", []).is_empty():
			next = ui.open_panel.bind("door"); action_name = "CycleWait_" + id.validate_node_name(); action_title = "日締めと翌日の営業を確認"
		else:
			next = ui._open_cycle_route.bind("company_growth"); action_name = "CyclePrepare_" + id.validate_node_name(); action_title = "必要なスキル・成長を確認"
	elif status == "ready":
		next = ui._open_cycle_offer.bind(id); action_name = "CycleOpen_" + id.validate_node_name(); action_title = "この顧客の相談へ"
	var board := ROUTE.new(); board.name = "CycleCustomerRoute"; board.setup(item, ui.text_scale, inspect, next); content.add_child(board)
	var busy: bool = not bool(g.state.get("career_mode", false)) and bool(g.state.get("accepted", false)) and not g.current_done()
	board.objects[2].disabled = busy and status == "ready"
	var actions := HFlowContainer.new(); content.add_child(actions)
	if not action_name.is_empty():
		var button := _action(ui, actions, action_title, next, action_name, "primary" if status == "ready" else "secondary")
		button.disabled = busy and status == "ready"
	_action(ui, actions, "納品記録・相談の条件", inspect, "CycleDetailsToggle", "quiet")
	content.add_child(details)
	details.add_child(ui._label(str(item.get("reason", "")), 14, M.INK))
	details.add_child(ui._label("きっかけ: DAY %02d「%s」の納品" % [int(item.get("source_day", 0)), str(item.get("source_title", ""))], 13, M.MUTED))
	var locked_reason := str(item.get("locked_reason", ""))
	if not locked_reason.is_empty(): details.add_child(ui._label(locked_reason, 13, M.MUTED))
	if status == "paused":
		details.add_child(ui._label(str(item.get("recovery_goal", "通常の依頼で期限内納品と顧客満足40以上を確認してください。")), 13, M.MUTED))
	if busy: details.add_child(ui._label("進めている依頼を納品すると相談できます。", 13, M.MUTED))

static func _toggle_details(ui, details: VBoxContainer) -> void:
	var opening := not details.visible
	if opening:
		var owner: Control = ui.get_viewport().gui_get_focus_owner()
		var source := str(owner.name) if is_instance_valid(owner) else ""
		details.set_meta("return_focus", source if source in ["CycleRouteObject0", "CycleRouteObject1", "CycleRouteObject2"] else "CycleRouteObject0")
	details.visible = opening
	var toggle := ui.find_child("CycleDetailsToggle", true, false) as Button
	if toggle != null: toggle.text = "記録を閉じる" if opening else "納品記録・相談の条件"
	var tree: SceneTree = ui.get_tree()
	await tree.process_frame; await tree.process_frame
	if not is_instance_valid(ui) or not is_instance_valid(details) or not details.is_inside_tree(): return
	if opening:
		if is_instance_valid(toggle): toggle.grab_focus()
		ui.modal_scroll.ensure_control_visible(details)
	else:
		var source := ui.find_child(str(details.get_meta("return_focus", "CycleRouteObject0")), true, false) as Control
		if is_instance_valid(source): source.grab_focus()
		var board := ui.find_child("CycleCustomerRoute", true, false) as Control
		if is_instance_valid(board): ui.modal_scroll.ensure_control_visible(board)

static func _select_customer(ui, id: String) -> void:
	ui.set_meta("cycle_customer", id); ui._select_company_view("overview")
	_focus_customer(ui, "CycleCustomer_" + id.validate_node_name())

static func _focus_customer(ui, id: String) -> void:
	var tree: SceneTree = ui.get_tree()
	await tree.process_frame; await tree.process_frame
	if not is_instance_valid(ui): return
	var button := ui.find_child(id, true, false) as Button
	if button != null: button.grab_focus()

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
