extends RefCounted
class_name OSBillingWorkspace

## Odoo-style customer invoicing and payment workspace backed by Game's
## persistent billing records. This renderer does not invent or mutate records
## except through the existing post_invoice API.

const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")

const PURPLE := Color("714b67")
const PURPLE_DARK := Color("51364c")
const PURPLE_LIGHT := Color("f3edf2")
const PAGE := Color("f5f5f5")
const PANEL := Color("ffffff")
const LINE := Color("d9d9d9")
const HEAD := Color("f8f9fa")
const INK := Color("282828")
const MUTED := Color("6b6b6b")
const RED := Color("b42318")
const AMBER := Color("8a5a00")
const GREEN := Color("2f7d4a")

static func copy(key: String, fallback: String = "") -> String:
	return UI.copy("billing_" + key, fallback)

static func _state(d) -> Dictionary:
	if not d.billing_ui is Dictionary:
		d.billing_ui = {}
	var value: Dictionary = d.billing_ui
	if not value.has("view"): value["view"] = "invoices"
	if not value.has("filter"): value["filter"] = "all"
	if not value.has("query"): value["query"] = ""
	if not value.has("selected"): value["selected"] = ""
	return value

static func _persist(d) -> void:
	if d.has_method("_save_session"): d._save_session(false)

static func _label(d, parent: Node, text: String, size: int = 14, color: Color = INK) -> Label:
	var value: Label = d._label(text, size, color)
	value.add_theme_font_override("font", UI.font(400 if size < 18 else 500))
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(value)
	return value

static func _button(d, parent: Node, text: String, name: String, action: Callable, selected: bool = false) -> Button:
	var value: Button = d._button(text, action)
	value.name = name
	value.custom_minimum_size.y = 34
	value.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var normal := UI.style(Color.WHITE, Color.TRANSPARENT, 8, 5, 0)
	normal.set_border_width_all(0)
	normal.border_width_bottom = 2 if selected else 0
	normal.border_color = PURPLE
	value.add_theme_stylebox_override("normal", normal)
	value.add_theme_stylebox_override("hover", UI.style(PURPLE_LIGHT, Color.TRANSPARENT, 8, 5, 0))
	value.add_theme_stylebox_override("pressed", UI.style(PURPLE_LIGHT, Color.TRANSPARENT, 8, 5, 0))
	value.add_theme_font_override("font", UI.font(400))
	value.add_theme_color_override("font_color", PURPLE_DARK if selected else INK)
	value.add_theme_color_override("font_hover_color", INK)
	parent.add_child(value)
	return value

static func _panel(parent: Node, color: Color = PANEL, padding: int = 12) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UI.style(color, LINE, padding, padding, 2))
	parent.add_child(frame)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	frame.add_child(body)
	return body

static func _invoices(d) -> Array:
	if d.game == null or not d.game.has_method("company_invoices"): return []
	var value: Variant = d.game.company_invoices()
	return value if value is Array else []

static func _payment_records(d) -> Array:
	if d.game == null or not d.game.has_method("company_payments"): return []
	var value: Variant = d.game.company_payments()
	return value if value is Array else []

static func _summary(d) -> Dictionary:
	if d.game == null or not d.game.has_method("billing_summary"): return {}
	var value: Variant = d.game.billing_summary()
	return value if value is Dictionary else {}

static func _number(value: Variant) -> String:
	var text := str(value)
	if value is float: text = str(int(value))
	if not (value is int or value is float or text.is_valid_int()): return text
	var negative := text.begins_with("-")
	var digits := text.trim_prefix("-")
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3, 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return "¥-" + grouped if negative else "¥" + grouped

static func _day(value: Variant) -> String:
	var day := int(value)
	return copy("not_issued", "—") if day < 0 else "DAY %d" % day

static func _status_text(status: String) -> String:
	match status:
		"draft": return copy("draft", "Draft")
		"posted": return copy("posted", "Posted")
		"paid": return copy("paid", "Paid")
	return status if not status.is_empty() else copy("status", "Status")

static func _status_color(status: String) -> Color:
	match status:
		"draft": return PURPLE
		"posted": return AMBER
		"paid": return GREEN
	return MUTED

static func _post_error_key(error: String) -> String:
	match error:
		"invoice_not_found": return "missing_invoice"
		"invalid_state", "cash_overflow": return "invalid_invoice"
		"unknown": return "confirm_failed"
		"not_draft", "save_failed", "invalid_invoice", "missing_invoice", "confirm_failed": return error
	return "confirm_failed"

static func _status_chip(d, parent: Node, status: String) -> Label:
	var chip := _label(d, parent, _status_text(status), 12, _status_color(status))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.add_theme_stylebox_override("normal", UI.style(Color("f8f9fa"), _status_color(status), 8, 4, 1))
	return chip

static func _find_invoice(invoices: Array, id: String) -> Dictionary:
	for raw in invoices:
		if raw is Dictionary and str(raw.get("id", "")) == id: return raw
	return {}

static func _matches(invoice: Dictionary, state: Dictionary) -> bool:
	var filter := str(state.get("filter", "all"))
	if filter != "all" and str(invoice.get("status", "")) != filter: return false
	var query := str(state.get("query", "")).strip_edges().to_lower()
	if query.is_empty(): return true
	var haystack := " ".join([
		str(invoice.get("id", "")), str(invoice.get("contract_id", "")),
		str(invoice.get("client", "")), str(invoice.get("title", "")),
		str(invoice.get("reference", ""))
	]).to_lower()
	return haystack.contains(query)

static func _toolbar(d, parent: Node, state: Dictionary, view: String) -> Dictionary:
	var toolbar := HBoxContainer.new()
	toolbar.name = "BillingToolbar"
	toolbar.add_theme_constant_override("separation", 8)
	parent.add_child(toolbar)
	_label(d, toolbar, copy("invoices"), 17, INK)
	var filter := OptionButton.new()
	filter.name = "BillingFilter"
	filter.custom_minimum_size.x = 118
	filter.visible = view == "invoices"
	for option in [["all", copy("all", "All")], ["draft", copy("draft", "Draft")], ["posted", copy("posted", "Posted")], ["paid", copy("paid", "Paid")]]:
		filter.add_item(str(option[1]))
		filter.set_item_metadata(filter.item_count - 1, str(option[0]))
	var selected_filter := str(state.get("filter", "all"))
	for option_index in filter.item_count:
		if str(filter.get_item_metadata(option_index)) == selected_filter:
			filter.select(option_index)
	filter.item_selected.connect(func(index: int):
		state["filter"] = str(filter.get_item_metadata(index)); state["selected"] = ""; _persist(d); d._render_billing())
	toolbar.add_child(filter)
	var search := LineEdit.new()
	search.name = "BillingSearch"
	search.placeholder_text = copy("search", "Search")
	search.text = str(state.get("query", ""))
	search.clear_button_enabled = true
	search.custom_minimum_size.x = 220
	search.visible = view == "invoices" and str(state.get("selected", "")).is_empty()
	search.add_theme_stylebox_override("normal", UI.style(Color.WHITE, LINE, 8, 4, 1))
	search.add_theme_stylebox_override("focus", UI.style(Color.WHITE, PURPLE, 8, 4, 1))
	toolbar.add_child(search)
	var count := _label(d, toolbar, "", 12, MUTED)
	count.name = "BillingCount"; count.size_flags_horizontal = Control.SIZE_SHRINK_END
	return {"search":search,"filter":filter,"count":count}

static func _view_tabs(d, parent: Node, state: Dictionary, view: String) -> void:
	var invoice_action: Callable = func():
		state["view"] = "invoices"
		state["selected"] = ""
		_persist(d)
		d._render_billing()
	_button(d, parent, copy("invoices", "Invoices"), "BillingInvoices", invoice_action, view == "invoices")
	var payments_action: Callable = func():
		state["view"] = "payments"
		state["selected"] = ""
		_persist(d)
		d._render_billing()
	_button(d, parent, copy("payments", "Payments"), "BillingPayments", payments_action, view == "payments")

static func _summary_bar(d, parent: Node) -> void:
	var summary := _summary(d)
	var row := HFlowContainer.new()
	row.name = "BillingSummary"
	row.add_theme_constant_override("h_separation", 24)
	row.add_theme_constant_override("v_separation", 8)
	parent.add_child(row)
	var values := [
		[copy("draft_total", "Draft"), _number(summary.get("draft_total", 0))],
		[copy("receivable_total", "Receivable"), _number(summary.get("receivable_total", 0))],
		[copy("paid_today", "Paid today"), _number(summary.get("paid_today", 0))],
		[copy("due_next_day", "Due next day"), _number(summary.get("due_next_day", 0))]
	]
	for pair in values:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.x = 160 * float(d.game.settings.get("text_scale", 1.0))
		row.add_child(cell)
		_label(d, cell, str(pair[0]), 11, MUTED)
		_label(d, cell, str(pair[1]), 16, INK)

static func _compact_layout(d) -> bool:
	var windows_value: Variant = d.windows
	if not windows_value is Dictionary:
		return false
	var windows: Dictionary = windows_value
	var billing: Variant = windows.get("billing")
	if not is_instance_valid(billing):
		return false
	return float(billing.size.x) / float(d.game.settings.get("text_scale", 1.0)) < 650.0

static func render(d, parent: VBoxContainer) -> void:
	var state := _state(d)
	var page := _panel(parent, PANEL, 12)
	page.name = "BillingWorkspace"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	var nav := HBoxContainer.new()
	nav.name = "BillingAppNav"
	nav.add_theme_constant_override("separation", 10)
	page.add_child(nav)
	var icon := TextureRect.new(); icon.texture = UI.icon("billing"); icon.custom_minimum_size = Vector2(22,22); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; nav.add_child(icon)
	var title := _label(d, nav, copy("app", "Invoicing"), 19, INK)
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_view_tabs(d, nav, state, str(state.get("view", "invoices")))
	var view := str(state.get("view", "invoices"))
	var invoices := _invoices(d)
	if view == "invoices" and not str(state.get("selected", "")).is_empty() and _find_invoice(invoices, str(state.get("selected", ""))).is_empty():
		state["selected"] = ""
	if view == "payments":
		_payments_view(d, page, _payment_records(d))
		return
	var selected_id := str(state.get("selected", ""))
	var selected := _find_invoice(invoices, selected_id)
	if not selected.is_empty():
		_invoicedetail(d, page, selected, _payment_records(d))
		return
	_summary_bar(d, page)
	var controls := _toolbar(d, page, state, view)
	_invoicelist(d, page, invoices, state, controls.get("search"), controls.get("count"))

static func _invoicelist(d, parent: Node, invoices: Array, state: Dictionary, search: LineEdit, count: Label) -> void:
	var box := _panel(parent, PANEL, 0)
	box.name = "BillingInvoiceList"
	var scroll := ScrollContainer.new()
	scroll.name = "BillingTableScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var table := VBoxContainer.new()
	table.name = "BillingInvoiceTable"
	table.custom_minimum_size.x = 740
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 0)
	scroll.add_child(table)
	var headings := [copy("invoice", "Invoice"), copy("client", "Customer"), copy("invoice_date", "Invoice date"), copy("due_date", "Due date"), copy("amount", "Amount"), copy("status", "Status")]
	var widths := [135, 190, 82, 82, 120, 105]
	_add_table_row(d, table, headings, widths, true, -1, Callable())
	var rows: Array[Control] = []
	var row_invoices: Array = []
	for raw in invoices:
		if not raw is Dictionary: continue
		var invoice: Dictionary = raw
		var row := _invoice_row(d, table, invoice, widths)
		rows.append(row)
		row_invoices.append(invoice)
	var empty := _label(d, table, copy("no_results", "No invoices"), 14, MUTED)
	empty.name = "BillingNoResults"
	empty.visible = false
	count.text = _count_text(invoices, state)
	search.text_changed.connect(func(value: String):
		state["query"] = value
		_filter_rows(rows, row_invoices, state, empty, count)
		_persist(d))
	_filter_rows(rows, row_invoices, state, empty, count)

static func _invoice_row(d, parent: Node, invoice: Dictionary, widths: Array) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "BillingInvoice_" + str(invoice.get("id", "")).validate_node_name()
	frame.custom_minimum_size.y = 42
	var index := parent.get_child_count()
	var style := UI.style(Color("f8f9fa") if index % 2 == 0 else PANEL, LINE, 8, 3, 0)
	style.set_border_width_all(0)
	style.border_width_bottom = 1
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	frame.add_child(row)
	var values := [str(invoice.get("id", "")), str(invoice.get("client", "")), _day(invoice.get("posted_day", -1)), _day(invoice.get("due_day", -1)), _number(invoice.get("amount", 0))]
	for i in values.size():
		var cell := _label(d, row, values[i], 13, INK)
		cell.custom_minimum_size.x = int(widths[i])
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if i == 1 else Control.SIZE_SHRINK_BEGIN
		cell.clip_text = true; cell.tooltip_text = values[i]
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 4: cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var chip := _status_chip(d, row, str(invoice.get("status", "")))
	chip.custom_minimum_size.x = int(widths[5]); chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			d.billing_ui["selected"] = str(invoice.get("id", "")); _persist(d); d._render_billing())
	return frame

static func _add_table_row(d, parent: Node, values: Array, widths: Array, header: bool, _index: int, _action: Callable) -> void:
	var frame := PanelContainer.new()
	var style := UI.style(HEAD if header else (Color("f8f9fa") if _index % 2 == 0 else PANEL), LINE, 8, 7, 0)
	style.set_border_width_all(0)
	style.border_width_bottom = 1
	frame.add_theme_stylebox_override("panel", style)
	parent.add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	frame.add_child(row)
	for i in values.size():
		var cell := _label(d, row, str(values[i]), 11 if header else 13, MUTED if header else INK)
		cell.custom_minimum_size.x = int(widths[i])
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if i == 1 else Control.SIZE_SHRINK_BEGIN
		cell.clip_text = true; cell.tooltip_text = str(values[i])
		if i == values.size() - 1 or (header and values.size() == 6 and i == 4): cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _filter_rows(rows: Array[Control], invoices: Array, state: Dictionary, empty: Label, count: Label) -> void:
	var matched := 0
	for i in rows.size():
		var invoice: Dictionary = invoices[i] if i < invoices.size() and invoices[i] is Dictionary else {}
		var visible := _matches(invoice, state)
		rows[i].visible = visible
		if visible: matched += 1
	empty.visible = matched == 0
	count.text = _count_text(invoices, state)

static func _count_text(invoices: Array, state: Dictionary) -> String:
	var total := 0
	for raw in invoices:
		if raw is Dictionary and _matches(raw, state): total += 1
	return copy("records", "%d records") % total

static func _invoicedetail(d, parent: Node, invoice: Dictionary, payments: Array) -> void:
	var top := HBoxContainer.new()
	parent.add_child(top)
	var back := _button(d, top, copy("back", "Back"), "BillingBack", func(): d.billing_ui["selected"] = ""; _persist(d); d._render_billing())
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var kind := _label(d, top, copy("invoice", "Customer Invoice"), 14, MUTED)
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_chip(d, top, str(invoice.get("status", "")))
	var form := _panel(parent, PANEL, 18)
	var heading := _label(d, form, str(invoice.get("id", "")), 30, INK)
	heading.name = "BillingSelectedInvoice"
	var columns: BoxContainer = VBoxContainer.new() if _compact_layout(d) else HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	form.add_child(columns)
	var left := GridContainer.new(); left.columns = 2; left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := GridContainer.new(); right.columns = 2; right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for grid in [left, right]:
		grid.add_theme_constant_override("h_separation", 16); grid.add_theme_constant_override("v_separation", 5); columns.add_child(grid)
	_field(d, left, copy("client", "Customer"), str(invoice.get("client", "")))
	_field(d, left, copy("contract", "Contract"), str(invoice.get("title", "")))
	_field(d, left, copy("delivered", "Delivered"), _day(invoice.get("created_day", -1)))
	_field(d, right, copy("invoice_date", "Posted"), _day(invoice.get("posted_day", -1)))
	_field(d, right, copy("due_date", "Due date"), _day(invoice.get("due_day", -1)))
	var payment_days := int(invoice.get("payment_days", 0))
	var terms := copy("terms_immediate", "Immediate") if payment_days <= 0 else copy("terms_days", "%d days") % payment_days
	_field(d, right, copy("terms", "Payment terms"), terms)
	form.add_child(HSeparator.new())
	var lines := VBoxContainer.new()
	lines.name = "BillingInvoiceLines"
	form.add_child(lines)
	_line_item(d, lines, copy("fee", "Service fee"), _number(invoice.get("fee", 0)))
	_line_item(d, lines, copy("quality_bonus", "Quality bonus"), _number(int(invoice.get("bonus", 0)) - int(invoice.get("baseline_bonus", 0))))
	if int(invoice.get("baseline_bonus", 0)) > 0:
		var bonus_label := copy("baseline_bonus", "Baseline bonus")
		for delivery in d.game.state.get("history", []):
			if str(delivery.get("id", "")) == str(invoice.get("contract_id", "")) and str(delivery.get("case_id", "")) in ["advanced-saas-response", "advanced-saas-watch", "advanced-saas-sessions", "advanced-saas-ai-preflight", "advanced-saas-ai-handoff"]:
				bonus_label = "流出予防ボーナス"
				if delivery.get("saas_outcome", {}).get("session_case", {}).has("business"): bonus_label = "業務継続・流出予防ボーナス"
				if str(delivery.get("case_id", "")) == "advanced-saas-ai-preflight": bonus_label = "公開前審査・業務継続ボーナス"
				if str(delivery.get("case_id", "")) == "advanced-saas-ai-handoff": bonus_label = "配送連絡・流出予防ボーナス"
				break
		_line_item(d, lines, bonus_label, _number(invoice.get("baseline_bonus", 0)))
	var material_cost := int(invoice.get("material_cost", 0))
	if bool(invoice.get("material_billable", false)) and material_cost > 0:
		_line_item(d, lines, copy("hardware_line", "Customer equipment"), _number(material_cost))
	var total := HBoxContainer.new()
	lines.add_child(total)
	_label(d, total, copy("total", "Total"), 16, INK)
	var total_value := _label(d, total, _number(invoice.get("amount", 0)), 20, PURPLE_DARK)
	total_value.size_flags_horizontal = Control.SIZE_SHRINK_END
	if str(invoice.get("status", "")) == "paid":
		for raw in payments:
			if raw is Dictionary and str(raw.get("invoice_id", "")) == str(invoice.get("id", "")):
				_field(d, right, copy("reference", "Reference"), str(raw.get("reference", "")))
				_field(d, right, copy("payment_date", "Received"), _day(raw.get("day", -1)))
				break
	if str(invoice.get("status", "")) == "draft":
		var actions := HBoxContainer.new()
		actions.name = "BillingDraftActions"
		actions.alignment = BoxContainer.ALIGNMENT_END
		form.add_child(actions)
		var feedback := _label(d, actions, "", 12, RED)
		feedback.name = "BillingPostFeedback"
		feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var post := _button(d, actions, copy("confirm", "Confirm"), "BillingPost", func():
			if d.game != null and d.game.has_method("post_invoice"):
				var result: Variant = d.game.post_invoice(str(invoice.get("id", "")))
				if result is Dictionary and bool(result.get("ok", false)):
					d.billing_ui["selected"] = str(invoice.get("id", "")); _persist(d); d._render_billing()
				elif result is Dictionary:
					var error_key := _post_error_key(str(result.get("error", "confirm_failed")))
					feedback.text = copy(error_key, copy("confirm_failed", "Unable to confirm"))
		)
		post.add_theme_stylebox_override("normal", UI.style(PURPLE, Color.TRANSPARENT, 10, 6, 2))
		post.add_theme_stylebox_override("hover", UI.style(PURPLE_DARK, Color.TRANSPARENT, 10, 6, 2))
		post.add_theme_stylebox_override("pressed", UI.style(PURPLE_DARK, Color.TRANSPARENT, 10, 6, 2))
		post.add_theme_color_override("font_color", Color.WHITE)
		post.add_theme_color_override("font_hover_color", Color.WHITE)
		# Match the accounting app's action bar; confirmation remains visible on small windows.
		form.remove_child(actions); top.add_child(actions)
		actions.remove_child(feedback); form.add_child(feedback)
		feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func _line_item(d, parent: Node, label: String, amount: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(d, row, label, 14, MUTED)
	var value := _label(d, row, amount, 14, INK)
	value.size_flags_horizontal = Control.SIZE_SHRINK_END

static func _field(d, parent: Node, label: String, value: String) -> void:
	var key := _label(d, parent, label, 12, MUTED)
	key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	key.custom_minimum_size.x = 128
	var content := _label(d, parent, value, 14, INK)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.clip_text = true
	content.tooltip_text = value

static func _payments_view(d, parent: Node, payments: Array) -> void:
	var box := _panel(parent, PANEL, 0)
	box.name = "BillingPaymentList"
	_label(d, box, copy("payments", "Payments"), 17, INK)
	var scroll := ScrollContainer.new()
	scroll.name = "BillingPaymentTableScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var table := VBoxContainer.new()
	table.name = "BillingPaymentTable"
	table.custom_minimum_size.x = 680
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 0)
	scroll.add_child(table)
	var headings := [copy("invoice", "Invoice"), copy("client", "Customer"), copy("reference", "Reference"), copy("payment_date", "Date"), copy("amount", "Amount")]
	var widths := [135, 190, 150, 82, 120]
	_add_table_row(d, table, headings, widths, true, -1, Callable())
	if payments.is_empty():
		_label(d, table, copy("no_results", "No payments"), 14, MUTED)
		return
	var index := 0
	for raw in payments:
		if not raw is Dictionary: continue
		var payment: Dictionary = raw
		_add_table_row(d, table, [str(payment.get("invoice_id", "")), str(payment.get("client", "")), str(payment.get("reference", "")), _day(payment.get("day", -1)), _number(payment.get("amount", 0))], widths, false, index, Callable())
		index += 1
