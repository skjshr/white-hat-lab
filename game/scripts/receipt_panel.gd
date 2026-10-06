class_name ReceiptPanel
extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")

static func render(d, body: VBoxContainer, receipt: Dictionary, first_view: bool = false) -> void:
	var sales := int(receipt.get("fee", 0)) + int(receipt.get("bonus", 0)) + (int(receipt.get("material_cost", 0)) if bool(receipt.get("material_billable", false)) else 0)
	var costs := int(receipt.get("cost", 0))
	var profit := int(receipt.get("net", 0))
	var heading: HBoxContainer = d._row(body, 16)
	var title: Label = d._label(UI.copy("receipt_complete"), 22, UI.INK)
	title.name = "ReceiptComplete"
	heading.add_child(title)
	var subject: Label = d._label(str(receipt.get("client", "")) + "  /  " + str(receipt.get("title", "")), 14, UI.MUTED)
	subject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(subject)
	var tabs := HFlowContainer.new()
	tabs.name = "ReceiptTabs"
	tabs.add_theme_constant_override("h_separation", 6)
	body.add_child(tabs)
	var finance_tab := _tab(d, "ReceiptFinanceTab", UI.copy("receipt_finance"), "finance")
	var evaluation_tab := _tab(d, "ReceiptEvaluationTab", "顧客の結果", "evaluation")
	tabs.add_child(evaluation_tab)
	tabs.add_child(finance_tab)
	var selected := str(d.widgets.receipt.get("tab", "evaluation")) if d.widgets is Dictionary and d.widgets.has("receipt") and d.widgets.receipt is Dictionary else "evaluation"
	if first_view:
		selected = "evaluation"
		if d.widgets is Dictionary and d.widgets.has("receipt") and d.widgets.receipt is Dictionary: d.widgets.receipt["tab"] = selected
		if d.widgets is Dictionary and d.widgets.has("receipt"): d.widgets.receipt["evidence"] = false
	if selected not in ["finance", "evaluation"]: selected = "evaluation"
	finance_tab.button_pressed = selected == "finance"
	evaluation_tab.button_pressed = selected == "evaluation"
	var finance := VBoxContainer.new(); finance.name = "ReceiptFinance"; finance.visible = selected == "finance"; body.add_child(finance)
	var summary := HBoxContainer.new()
	summary.name = "ReceiptSummary"
	summary.add_theme_constant_override("separation", 8)
	finance.add_child(summary)
	_metric(d, summary, "ReceiptSales", UI.copy("receipt_sales"), sales, UI.INK)
	_metric(d, summary, "ReceiptCosts", UI.copy("receipt_costs"), costs, UI.INK)
	_metric(d, summary, "ReceiptProfit", UI.copy("receipt_profit"), profit, UI.GREEN if profit >= 0 else UI.RED)
	_invoice(d, finance, receipt, sales)
	_finance(d, finance, receipt)
	if not receipt.get("pentest_changes", {}).get("requests", []).is_empty():
		var changes: VBoxContainer = d._disclosure(finance, "変更依頼の控え")
		changes.name = "ReceiptPentestChanges"
		var labels := {"restrict_config":"配置設定の公開範囲を制限", "rotate_credential":"サービス資格情報を更新", "isolate_share":"共有サービスを隔離", "restore_share":"共有サービスを再開"}
		for request in receipt.pentest_changes.requests:
			changes.add_child(_text(d, "%s  ·  %s  ·  %d分  ·  %s" % [str(request.get("id", "")), str(labels.get(str(request.get("change", "")), "顧客の変更作業")), int(request.get("minutes", 0)), _yen(int(request.get("cost", 0)))], 13, UI.INK))
	if receipt.get("endpoint_impact",{}) is Dictionary and not receipt.get("endpoint_impact",{}).is_empty():
		var impact: VBoxContainer=d._disclosure(finance,"補償費用の内訳")
		impact.name="ReceiptEndpointImpact"
		for item in receipt.endpoint_impact.values():
			impact.add_child(_text(d,str(item.get("name","拠点")),14,UI.INK))
			impact.add_child(_text(d,preload("res://scripts/endpoint_engagement.gd").summary({"site":item}),13,UI.MUTED))
	var evaluation := VBoxContainer.new(); evaluation.name = "ReceiptEvaluation"; evaluation.visible = selected == "evaluation"; body.add_child(evaluation)
	if bool(d.widgets.receipt.get("evidence", false)):
		_evidence(d, evaluation, receipt)
	else:
		var board := preload("res://scripts/receipt_outcome_board.gd").new()
		board.name = "ReceiptOutcomeBoard"
		board.setup(receipt, float(d.game.settings.get("text_scale", 1.0)))
		evaluation.add_child(board)
		_invoice(d, evaluation, receipt, sales, "ReceiptOutcome")
		for site in receipt.get("hotel_workflow", {}).get("sites", []):
			if str(site.get("status", "")) != "received": continue
			var caption := "✓ %s号室 · 精算受付 %s · 残高 %s" % [str(site.get("room", "")), str(site.get("receipt", {}).get("number", "")), _yen(int(site.get("balance", 0)))]
			if int(site.get("workflow_version", 1)) == 2:
				var reservation: Dictionary = site.get("reservation", {})
				caption = "✓ %s号室 · DAY %02d到着 · 予約 %s\n精算控え %s · 引継ぎ済" % [str(reservation.get("room", "")), int(reservation.get("arrival_day", 0)), str(reservation.get("bookingno", "")), str(site.get("receipt", {}).get("number", ""))]
			var accepted := _text(d, caption, 14, UI.INK)
			accepted.name = "ReceiptHotelAccepted"
			evaluation.add_child(accepted)
		_outcomes(d, evaluation, receipt)
		var details: VBoxContainer = d._disclosure(evaluation, "評価の内訳・作業時間")
		details.name = "ReceiptImpactDetails"
		_evaluation(d, details, receipt)

static func _saved_results(receipt: Dictionary) -> Array:
	var results: Array = receipt.get("delivery_results", [])
	if not results.is_empty(): return results
	# Old receipts have saved checks, but no trustworthy target or raw response.
	return [{"checks":receipt.get("checks", []), "probes":[]}]

static func _outcomes(d, host: VBoxContainer, receipt: Dictionary) -> void:
	var title := _text(d, "納品時の記録を開く", 14, UI.INK)
	title.name = "ReceiptCustomerOutcome"; host.add_child(title)
	var targets := HFlowContainer.new(); targets.add_theme_constant_override("h_separation", 8); targets.add_theme_constant_override("v_separation", 8); host.add_child(targets)
	var results := _saved_results(receipt)
	for index in results.size():
		var target: Dictionary = results[index]; var checks: Array = target.get("checks", [])
		var passed: int = checks.filter(func(item): return bool(item.get("passed", false))).size()
		var paper := preload("res://scripts/receipt_target_button.gd").new()
		paper.name = "ReceiptTarget_" + str(index); paper.passed = passed; paper.total = checks.size(); paper.text_factor = float(d.game.settings.get("text_scale", 1.0))
		paper.custom_minimum_size = Vector2(256, 66) * paper.text_factor
		paper.alignment = HORIZONTAL_ALIGNMENT_LEFT; paper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		paper.text = str(target.get("target", "対象の記録なし")) + "\n" + ("✓  納品判定 %d / %d" % [passed, checks.size()] if passed == checks.size() and not checks.is_empty() else "×  納品判定 %d / %d" % [passed, checks.size()] if not checks.is_empty() else "—  判定の記録なし")
		paper.add_theme_font_size_override("font_size", int(13 * paper.text_factor))
		for kind in ["normal", "hover", "pressed"]:
			var style := UI.style(Color("fffcf2") if kind == "normal" else Color("e8efec"), Color("d5d0bd"), 8, 0, 2)
			style.content_margin_left = 59 * paper.text_factor; style.content_margin_right = 10 * paper.text_factor
			paper.add_theme_stylebox_override(kind, style)
		paper.tooltip_text = str(target.get("host", "")) + " / 保存した納品判定と実測応答"
		paper.pressed.connect(_open_evidence.bind(d, 0, str(paper.name), index))
		targets.add_child(paper)
	var evidence: Button = d._button("初回との比較・すべての判定", _open_evidence.bind(d, 0, "ReceiptEvidenceButton"))
	evidence.name = "ReceiptEvidenceButton"; host.add_child(evidence)

static func _open_evidence(d, index: int, source: String, target_index: int = -1) -> void:
	d.widgets.receipt["evidence"] = true; d.widgets.receipt["evidence_index"] = index; d.widgets.receipt["evidence_return"] = source
	d.widgets.receipt["evidence_target"] = target_index
	d._refresh_receipt()
	(d.widgets.receipt.body.get_parent() as ScrollContainer).scroll_vertical = 0
	_focus(d, "ReceiptEvidenceBack")

static func _focus(d, id: String) -> void:
	var tree: SceneTree = d.get_tree()
	await tree.process_frame; await tree.process_frame
	if not is_instance_valid(d): return
	var control: Control = d.widgets.receipt.body.find_child(id, true, false)
	if is_instance_valid(control) and control.is_visible_in_tree(): control.grab_focus()

static func _evidence(d, host: VBoxContainer, receipt: Dictionary) -> void:
	var details := VBoxContainer.new(); details.name = "ReceiptEvidence"; details.add_theme_constant_override("separation", 8); host.add_child(details)
	var back: Button = d._button("顧客の結果に戻る", func():
		d.widgets.receipt["evidence"] = false; d._refresh_receipt()
		(d.widgets.receipt.body.get_parent() as ScrollContainer).scroll_vertical = 0
		_focus(d, str(d.widgets.receipt.get("evidence_return", "ReceiptEvidenceButton")))
	)
	back.name = "ReceiptEvidenceBack"; details.add_child(back)
	details.add_child(_text(d, "納品時の検証記録", 18, UI.INK))
	details.add_child(_text(d, "納品時に保存した判定と実測応答です。初回の記録がある測定だけ比較できます。", 13, UI.MUTED))
	var targets := _saved_results(receipt)
	var scope := int(d.widgets.receipt.get("evidence_target", -1))
	if scope >= 0 and scope < targets.size():
		var target: Dictionary = targets[scope]
		var context := _text(d, str(target.get("target", "対象の記録なし")) + (" / " + str(target.host) if target.has("host") else ""), 14, UI.INK)
		context.name = "ReceiptEvidenceTarget"; details.add_child(context)
	var options := OptionButton.new(); options.name = "ReceiptEvidenceSelection"; options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var observations: Array = []
	for index in targets.size():
		if scope >= 0 and scope != index: continue
		var target: Dictionary = targets[index]
		var context := str(target.get("target", target.get("host", "")))
		for probe in target.get("probes", []):
			options.add_item((context + " / " if not context.is_empty() else "") + str(probe.get("label", probe.get("id", "測定"))))
			observations.append(probe)
	if observations.is_empty():
		options.free()
		details.add_child(_text(d, "実測応答はこの精算に保存されていません。保存済みの判定を表示します。", 14, UI.MUTED))
	else:
		var selected := clampi(int(d.widgets.receipt.get("evidence_index", 0)), 0, observations.size() - 1)
		options.select(selected); details.add_child(options)
		options.item_selected.connect(func(index):
			d.widgets.receipt["evidence_index"] = index; d._refresh_receipt()
			_focus(d, "ReceiptEvidenceSelection")
		)
		preload("res://scripts/os_diagnostics.gd")._build_comparison(d, details, observations[selected])
	var checks: VBoxContainer = d._disclosure(details, "すべての納品判定")
	for target in targets:
		var context := str(target.get("target", target.get("host", "")))
		if not context.is_empty(): checks.add_child(_text(d, context, 14, UI.INK))
		for item in target.get("checks", []):
			var row := _text(d, ("✓  " if bool(item.get("passed", false)) else "未達成  ") + str(item.get("label", "検証")), 14, UI.MUTED)
			row.name = "ReceiptOutcome_" + str(item.get("id", checks.get_child_count())).validate_node_name(); checks.add_child(row)

static func _tab(d, name: String, text: String, selected: String) -> Button:
	var button: Button = d._button(text, func():
		if d.widgets is Dictionary and d.widgets.has("receipt") and d.widgets.receipt is Dictionary:
			d.widgets.receipt["tab"] = selected
		if d.has_method("_refresh_receipt"): d._refresh_receipt()
		(d.widgets.receipt.body.get_parent() as ScrollContainer).scroll_vertical = 0
		_focus(d, name)
	)
	button.name = name
	button.toggle_mode = true
	button.add_theme_color_override("font_hover_pressed_color", UI.INK)
	button.custom_minimum_size = Vector2(140, 34)
	return button

static func _metric(d, host: Node, name: String, title: String, amount: int, color: Color) -> void:
	var panel := PanelContainer.new()
	panel.name = name + "Panel"
	panel.custom_minimum_size = Vector2(0, 72)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.style(Color.WHITE, UI.BORDER, 14, 8, 4))
	host.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var label: Label = _text(d, title, 13, UI.MUTED)
	stack.add_child(label)
	var value: Label = _text(d, _yen(amount), 24, color)
	value.name = name
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_override("font", UI.font(700))
	stack.add_child(value)

static func _invoice(d, body: VBoxContainer, receipt: Dictionary, sales: int, prefix: String = "Receipt") -> void:
	var status := ""
	var invoice_id := str(receipt.get("invoice_id", ""))
	var invoice: Dictionary = {}
	if not invoice_id.is_empty() and d.game != null and d.game.has_method("company_invoices"):
		for item in d.game.company_invoices():
			if str(item.get("id", "")) == invoice_id:
				invoice = item
				break
	if not invoice_id.is_empty() and invoice.is_empty():
		status = UI.copy("billing_missing_invoice")
	elif not invoice.is_empty():
		var invoice_status := str(invoice.get("status", "draft"))
		match invoice_status:
			"draft": status = UI.copy("billing_receipt_pending")
			"posted": status = UI.copy("billing_posted") + "  " + (UI.copy("receipt_due_day") % int(invoice.get("due_day", 0)))
			"paid": status = UI.copy("receipt_paid_day") % int(invoice.paid_day) if int(invoice.get("paid_day", -1)) >= 0 else UI.copy("billing_paid")
			_: status = UI.copy("billing_missing_invoice")
	else:
		status = UI.copy("receipt_settled") if sales > 0 else UI.copy("receipt_no_charge")
	var label: Label = _text(d, status, 13, UI.MUTED)
	label.name = prefix + "InvoiceStatus"
	var status_row := HBoxContainer.new(); status_row.name = prefix + "InvoiceRow"; status_row.add_theme_constant_override("separation", 8); body.add_child(status_row); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; status_row.add_child(label)
	if not invoice_id.is_empty() and not invoice.is_empty():
		var open: Button = d._button(UI.copy("billing_open_invoice"), d.open_invoice.bind(invoice_id))
		open.name = prefix + "Invoice"
		status_row.add_child(open)

static func _finance(d, host: VBoxContainer, receipt: Dictionary) -> void:
	var columns := HBoxContainer.new()
	columns.name = "ReceiptFinanceColumns"
	columns.add_theme_constant_override("separation", 24)
	host.add_child(columns)
	var income := _column("ReceiptRevenueItems")
	var costs := _column("ReceiptCostItems")
	columns.add_child(income)
	columns.add_child(costs)
	income.add_child(_text(d, UI.copy("receipt_revenue_items"), 15, UI.INK))
	income.add_child(HSeparator.new())
	costs.add_child(_text(d, UI.copy("receipt_cost_items"), 15, UI.INK))
	costs.add_child(HSeparator.new())
	_row(d, income, "ReceiptFee", UI.copy("billing_fee"), int(receipt.get("fee", 0)))
	var bonus := int(receipt.get("bonus", 0)) - int(receipt.get("baseline_bonus", 0))
	if bonus != 0: _row(d, income, "", UI.copy("billing_quality_bonus"), bonus)
	var baseline := int(receipt.get("baseline_bonus", 0))
	if baseline != 0:
		var label := "証拠付き報告・再検証評価" if str(receipt.get("case_id", "")) == "advanced-portal" else UI.copy("billing_baseline_bonus")
		_row(d, income, "ReceiptEvidenceBonus", label, baseline)
	var material := int(receipt.get("material_cost", 0))
	if bool(receipt.get("material_billable", false)) and material > 0: _row(d, income, "ReceiptMaterialBillable", UI.copy("receipt_hardware_sales"), material)
	var operating := int(receipt.get("cost", 0)) - material
	var compensation := preload("res://scripts/endpoint_engagement.gd").total_cost(receipt.get("endpoint_impact",{}))
	var change_cost := int(receipt.get("pentest_changes", {}).get("cost_total", 0))
	_row(d, costs, "ReceiptOperatingCost", UI.copy("receipt_operating_cost"), operating-compensation-change_cost)
	if change_cost > 0: _row(d, costs, "ReceiptPentestChangeCost", "顧客変更作業費（%d件）" % receipt.pentest_changes.get("requests", []).size(), change_cost)
	if compensation > 0: _row(d, costs, "ReceiptCompensationCost", "未封じ込め・業務誤停止の補償" if receipt.get("endpoint_impact",{}).values().any(func(item):return item.has("uncontained_minutes")) else "業務停止・不審送信の補償", compensation)
	if material > 0: _row(d, costs, "ReceiptMaterialCost", UI.copy("stock_material_cost"), material)
	if not str(receipt.get("hardware_serial", "")).is_empty():
		var serial := _text(d, UI.copy("stock_serial") + "  " + str(receipt.get("hardware_serial")), 12, UI.MUTED)
		host.add_child(serial)

static func _evaluation(d, host: VBoxContainer, receipt: Dictionary) -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	host.add_child(columns)
	var result := _evaluation_grid(columns)
	var growth := _evaluation_grid(columns)
	if receipt.has("grade"): _pair(d, result, UI.copy("receipt_grade"), str(receipt.grade))
	if receipt.has("minutes") and receipt.has("budget"):
		if receipt.has("elapsed_minutes"):
			_pair(d, result, "実作業", _time_number(float(receipt.minutes)) + " 分", "ReceiptWorkMinutes")
			_pair(d, result, "納品まで / 期限", _time_number(float(receipt.elapsed_minutes)) + " / " + _time_number(float(receipt.budget)) + " 分", "ReceiptElapsedValue")
		else:
			_pair(d, result, UI.copy("receipt_time"), UI.copy("receipt_time_value") % [int(receipt.minutes), int(receipt.budget)])
	if receipt.has("credit_before") and receipt.has("credit_after"):
		_pair(d, result, UI.copy("receipt_credit"), "%d → %d" % [int(receipt.credit_before), int(receipt.credit_after)])
	if receipt.has("satisfaction_before") and receipt.has("satisfaction_after"):
		_pair(d, result, UI.copy("receipt_satisfaction"), "%d → %d" % [int(receipt.satisfaction_before), int(receipt.satisfaction_after)])
	if receipt.has("quality_satisfaction_delta"): _pair(d, growth, UI.copy("receipt_quality_delta"), "%+d" % int(receipt.quality_satisfaction_delta))
	if receipt.has("price_satisfaction_delta"): _pair(d, growth, UI.copy("receipt_price_delta"), "%+d" % int(receipt.price_satisfaction_delta))
	if receipt.has("endpoint_satisfaction_delta"): _pair(d, growth, "業務誤停止による評価", "%+d" % int(receipt.endpoint_satisfaction_delta))
	if receipt.has("level_before") and receipt.has("level_after"):
		_pair(d, growth, UI.copy("receipt_level"), "%d → %d" % [int(receipt.level_before), int(receipt.level_after)])
	if receipt.has("xp_gain"): _pair(d, growth, UI.copy("receipt_xp"), "+%d" % int(receipt.xp_gain))
	var care := str(receipt.get("renewal_outcome", ""))
	if care in ["active", "suspended", "signed", "none"]:
		_pair(d, growth, UI.copy("receipt_care"), UI.copy("receipt_care_" + care))

static func _evaluation_grid(host: Node) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	host.add_child(grid)
	return grid

static func _column(name: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = name
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	return column

static func _row(d, host: VBoxContainer, name: String, label_text: String, amount: int) -> void:
	var row := GridContainer.new()
	row.columns = 2
	row.custom_minimum_size.y = 30
	host.add_child(row)
	var label := _text(d, label_text, 14, UI.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var value := _text(d, _yen(amount), 15, UI.INK)
	if not name.is_empty(): value.name = name
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.custom_minimum_size.x = 108
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

static func _pair(d, host: GridContainer, label_text: String, value_text: String, id: String = "") -> void:
	var label := _text(d, label_text, 14, UI.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(label)
	var value := _text(d, value_text, 15, UI.INK)
	if not id.is_empty(): value.name = id
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	host.add_child(value)

static func _time_number(value: float) -> String:
	return _number(int(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 1)

static func _text(d, value: String, size: int, color: Color) -> Label:
	var label: Label = d._label(value, size, color)
	return label

static func _yen(value: int) -> String:
	return ("-¥%s" % _number(-value)) if value < 0 else "¥%s" % _number(value)

static func _number(value: int) -> String:
	var sign := "-" if value < 0 else ""
	var digits := str(absi(value))
	var groups := []
	while digits.length() > 3:
		groups.push_front(digits.substr(digits.length() - 3, 3))
		digits = digits.substr(0, digits.length() - 3)
	groups.push_front(digits)
	return sign + ",".join(groups)
