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
	var summary := HBoxContainer.new()
	summary.name = "ReceiptSummary"
	summary.add_theme_constant_override("separation", 8)
	body.add_child(summary)
	_metric(d, summary, "ReceiptSales", UI.copy("receipt_sales"), sales, UI.INK)
	_metric(d, summary, "ReceiptCosts", UI.copy("receipt_costs"), costs, UI.INK)
	_metric(d, summary, "ReceiptProfit", UI.copy("receipt_profit"), profit, UI.GREEN if profit >= 0 else UI.RED)
	_invoice(d, body, receipt, sales)
	var tabs := HFlowContainer.new()
	tabs.name = "ReceiptTabs"
	tabs.add_theme_constant_override("h_separation", 6)
	body.add_child(tabs)
	var finance_tab := _tab(d, "ReceiptFinanceTab", UI.copy("receipt_finance"), "finance")
	var evaluation_tab := _tab(d, "ReceiptEvaluationTab", UI.copy("receipt_evaluation"), "evaluation")
	tabs.add_child(finance_tab)
	tabs.add_child(evaluation_tab)
	var selected := str(d.widgets.receipt.get("tab", "finance")) if d.widgets is Dictionary and d.widgets.has("receipt") and d.widgets.receipt is Dictionary else "finance"
	if first_view:
		selected = "finance"
		if d.widgets is Dictionary and d.widgets.has("receipt") and d.widgets.receipt is Dictionary: d.widgets.receipt["tab"] = selected
	if selected not in ["finance", "evaluation"]: selected = "finance"
	finance_tab.button_pressed = selected == "finance"
	evaluation_tab.button_pressed = selected == "evaluation"
	var finance := VBoxContainer.new(); finance.name = "ReceiptFinance"; finance.visible = selected == "finance"; body.add_child(finance)
	_finance(d, finance, receipt)
	var evaluation := VBoxContainer.new(); evaluation.name = "ReceiptEvaluation"; evaluation.visible = selected == "evaluation"; body.add_child(evaluation)
	_evaluation(d, evaluation, receipt)

static func _tab(d, name: String, text: String, selected: String) -> Button:
	var button: Button = d._button(text, func():
		if d.widgets is Dictionary and d.widgets.has("receipt") and d.widgets.receipt is Dictionary:
			d.widgets.receipt["tab"] = selected
		if d.has_method("_refresh_receipt"): d._refresh_receipt()
		(d.widgets.receipt.body.get_parent() as ScrollContainer).scroll_vertical = 0
	)
	button.name = name
	button.toggle_mode = true
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

static func _invoice(d, body: VBoxContainer, receipt: Dictionary, sales: int) -> void:
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
	label.name = "ReceiptInvoiceStatus"
	var status_row := HBoxContainer.new(); status_row.name = "ReceiptInvoiceRow"; status_row.add_theme_constant_override("separation", 8); body.add_child(status_row); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; status_row.add_child(label)
	if not invoice_id.is_empty() and not invoice.is_empty():
		var open: Button = d._button(UI.copy("billing_open_invoice"), d.open_invoice.bind(invoice_id))
		open.name = "ReceiptInvoice"
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
	if baseline != 0: _row(d, income, "", UI.copy("billing_baseline_bonus"), baseline)
	var material := int(receipt.get("material_cost", 0))
	if bool(receipt.get("material_billable", false)) and material > 0: _row(d, income, "ReceiptMaterialBillable", UI.copy("receipt_hardware_sales"), material)
	var operating := int(receipt.get("cost", 0)) - material
	_row(d, costs, "ReceiptOperatingCost", UI.copy("receipt_operating_cost"), operating)
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
		_pair(d, result, UI.copy("receipt_time"), UI.copy("receipt_time_value") % [int(receipt.minutes), int(receipt.budget)])
	if receipt.has("credit_before") and receipt.has("credit_after"):
		_pair(d, result, UI.copy("receipt_credit"), "%d → %d" % [int(receipt.credit_before), int(receipt.credit_after)])
	if receipt.has("satisfaction_before") and receipt.has("satisfaction_after"):
		_pair(d, result, UI.copy("receipt_satisfaction"), "%d → %d" % [int(receipt.satisfaction_before), int(receipt.satisfaction_after)])
	if receipt.has("quality_satisfaction_delta"): _pair(d, growth, UI.copy("receipt_quality_delta"), "%+d" % int(receipt.quality_satisfaction_delta))
	if receipt.has("price_satisfaction_delta"): _pair(d, growth, UI.copy("receipt_price_delta"), "%+d" % int(receipt.price_satisfaction_delta))
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

static func _pair(d, host: GridContainer, label_text: String, value_text: String) -> void:
	var label := _text(d, label_text, 14, UI.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(label)
	var value := _text(d, value_text, 15, UI.INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	host.add_child(value)

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
