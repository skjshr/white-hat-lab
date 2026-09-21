extends RefCounted
class_name OSBusinessWorkspace

## Odoo-like sales and accounting workspace over the customer's real JSON response.
## The renderer is read-only; order selection and search live in the desktop session.

const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")

const PURPLE := Color("714b67")
const PURPLE_DARK := Color("51364c")
const PURPLE_LIGHT := Color("f3edf2")
const PAGE := Color("f5f5f5")
const PANEL := Color("ffffff")
const LINE := Color("d9d9d9")
const INK := Color("282828")
const MUTED := Color("6b6b6b")
const RED := Color("b42318")
const GREEN := Color("2f7d4a")

static func copy(key: String, fallback: String = "") -> String:
	return UI.copy("business_" + key, fallback)

static func _external_storage(payload: Dictionary, data: Dictionary) -> Dictionary:
	var value: Variant = payload.get("external_storage", data.get("external_storage", {}))
	return value if value is Dictionary else {}

static func _storage_copy(key: String, fallback: String = "") -> String:
	return UI.copy(key, fallback)

static func _storage_error_key(storage: Dictionary) -> String:
	match str(storage.get("error", "")):
		"storage_denied": return "branch_storage_denied"
		"missing_file": return "branch_storage_missing"
		"provider_unavailable": return "branch_storage_unavailable"
	return "branch_storage_unavailable"

static func _storage_banner(d, parent: Node, storage: Dictionary) -> bool:
	if not bool(storage.get("enabled", false)) or bool(storage.get("ok", false)): return false
	var failed := not bool(storage.get("ok", false))
	var frame := PanelContainer.new()
	frame.name = "BusinessExternalStorage"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UI.style(Color("fff1f0") if failed else Color("eef7f1"), Color("d84a43") if failed else Color("8abf9a"), 8, 8, 1))
	parent.add_child(frame)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation", 3); frame.add_child(body)
	var title := _storage_copy(_storage_error_key(storage), "External storage unavailable") if failed else _storage_copy("branch_storage_label", "External storage")
	_label(d, body, title, 12, RED if failed else INK)
	if not failed:
		var host := str(storage.get("host", "")); var share := str(storage.get("share", ""))
		if not host.is_empty() and not share.is_empty(): _label(d, body, "SMB/CIFS  ·  //%s/%s" % [host, share], 11, MUTED)
		var path := str(storage.get("path", ""))
		if not path.is_empty(): _label(d, body, path, 11, MUTED)
	else:
		var code := int(storage.get("code", 0))
		if code > 0: _label(d, body, "HTTP %d" % code, 11, MUTED)
	_button(d, body, copy("refresh", "Refresh"), "BusinessStorageRefresh", func(): d._browse_url(d.browser_url, false))
	return true

static func _customer_source(data: Dictionary) -> String:
	for key in ["customers_source", "customer_source", "customers_path"]:
		var explicit_path := str(data.get(key, ""))
		if not explicit_path.is_empty(): return explicit_path
	var storage: Variant = data.get("external_storage", {})
	if storage is Dictionary and bool(storage.get("enabled", false)):
		var mounted_path := str(storage.get("path", ""))
		if not mounted_path.is_empty(): return mounted_path.get_base_dir().path_join("customers.csv")
	return "/srv/data/customers.csv"

static func _state(d) -> Dictionary:
	if not d.business_ui is Dictionary:
		d.business_ui = {}
	var value: Dictionary = d.business_ui
	if not value.has("view"): value["view"] = "sales"
	if not value.has("query"): value["query"] = ""
	if not value.has("selected_order"): value["selected_order"] = ""
	return value

static func _persist(d) -> void:
	if d.has_method("_save_session"): d._save_session(false)

static func _panel(parent: Node, color: Color = PANEL, padding: int = 14) -> VBoxContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UI.style(color, LINE, padding, padding, 2))
	parent.add_child(frame)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	frame.add_child(body)
	return body

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
	value.custom_minimum_size.y = 32
	value.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var normal := UI.style(Color.WHITE, Color.TRANSPARENT, 8, 5, 0)
	normal.set_border_width_all(0)
	normal.border_width_bottom = 2 if selected else 0
	normal.border_color = PURPLE
	value.add_theme_stylebox_override("normal", normal)
	value.add_theme_stylebox_override("hover", UI.style(PURPLE_LIGHT, Color.TRANSPARENT, 8, 5, 0))
	value.add_theme_stylebox_override("pressed", UI.style(PURPLE_LIGHT, Color.TRANSPARENT, 8, 5, 0))
	value.add_theme_font_override("font", UI.font(400))
	value.add_theme_font_size_override("font_size", int(13 * float(d.game.settings.get("text_scale", 1.0))))
	value.add_theme_color_override("font_color", PURPLE_DARK if selected else INK)
	value.add_theme_color_override("font_hover_color", INK)
	value.add_theme_color_override("font_pressed_color", INK)
	parent.add_child(value)
	return value

static func _payload(response: String) -> Dictionary:
	var text := response.strip_edges()
	var candidates: Array[String] = []
	var separator := text.find("\n\n")
	if separator >= 0:
		candidates.append(text.substr(separator + 2).strip_edges())
	else:
		var crlf_separator := text.find("\r\n\r\n")
		if crlf_separator >= 0: candidates.append(text.substr(crlf_separator + 4).strip_edges())
		else: candidates.append(text)
	for candidate in candidates:
		var parser := JSON.new()
		if parser.parse(candidate) == OK and parser.data is Dictionary: return parser.data
	var first_line := text.get_slice("\n", 0).strip_edges()
	if first_line.begins_with("HTTP/"):
		var parts := first_line.split(" ", false)
		var code := int(parts[1]) if parts.size() > 1 and str(parts[1]).is_valid_int() else 0
		return {"ok":false,"code":code,"error":"unknown","http_error":true}
	var lower := text.to_lower()
	if lower.begins_with("curl:") or lower.contains("could not resolve host") or lower.contains("name or service not known"):
		var transport_error := "network"
		if lower.contains("resolve") or lower.contains("name or service"): transport_error = "dns"
		elif lower.contains("tls") or lower.contains("certificate") or lower.contains("ssl"): transport_error = "tls"
		elif lower.contains("denied") or lower.contains("refused"): transport_error = "denied"
		return {"ok":false,"error":transport_error,"transport_error":true}
	return {"ok":false,"error":"data_error"}

static func _data(payload: Dictionary) -> Dictionary:
	var nested: Variant = payload.get("data", {})
	return nested if nested is Dictionary else payload

static func _orders(data: Dictionary) -> Array:
	var raw_orders: Variant = data.get("orders", [])
	var raw_customers: Variant = data.get("customers", [])
	var customers: Dictionary = {}
	if raw_customers is Array:
		for raw_customer in raw_customers:
			if raw_customer is Dictionary: customers[str(raw_customer.get("id", ""))] = str(raw_customer.get("name", ""))
	var result: Array = []
	if not raw_orders is Array: return result
	for raw_order in raw_orders:
		if not raw_order is Dictionary: continue
		var order: Dictionary = raw_order.duplicate(true)
		var customer_id := str(order.get("customer_id", order.get("customer", "")))
		var customer_name := str(order.get("customer_name", customers.get(customer_id, "")))
		if customer_name.is_empty(): customer_name = customer_id
		order["customer_id"] = customer_id
		order["customer"] = customer_name
		result.append(order)
	return result

static func _ledger(data: Dictionary) -> Array:
	var value: Variant = data.get("ledger", [])
	if value is Array: return value
	if value is Dictionary: return [value]
	return []

static func _compact(d) -> bool:
	return is_instance_valid(d.windows.get("browser")) and float(d.windows.browser.size.x) < 1100.0

static func _format_count(template: String, count: int) -> String:
	if template.contains("%d"): return template % count
	return template + " " + str(count)

static func _format_error(payload: Dictionary) -> String:
	var error := str(payload.get("error", "unknown"))
	if error == "storage_denied":
		var denied := UI.copy("branch_storage_denied", "External storage access denied")
		var denied_code := int(payload.get("code", 0))
		return denied + ("  ·  HTTP " + str(denied_code) if denied_code > 0 else "")
	var key := "unknown"
	if error in ["missing_file", "file_missing"]: key = "missing"
	elif error in ["provider_unavailable", "service_unavailable"]: key = "unavailable"
	elif error in ["network", "connection_refused"]: key = "network"
	elif error in ["dns", "name_resolution"]: key = "dns"
	elif error in ["tls", "certificate"]: key = "tls"
	elif error in ["denied", "access_denied", "storage_denied", "forbidden"]: key = "denied"
	elif error in ["invalid", "malformed_orders_row", "malformed_ledger", "malformed_customers_header", "malformed_orders_header"]: key = "invalid"
	elif error.begins_with("malformed_") or error == "duplicate_customer": key = "invalid"
	elif error == "data_error": key = "data_error"
	var result := copy("data_error", "Request failed") if key == "data_error" else copy("error_" + key, "Request failed")
	var code := int(payload.get("code", 0))
	if code > 0: result += "  ·  HTTP " + str(code)
	return result

static func _toolbar(d, parent: Node, state: Dictionary, view: String) -> LineEdit:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.style(Color.WHITE, Color.TRANSPARENT, 12, 8, 0))
	parent.add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	frame.add_child(row)
	var refresh := _button(d, row, copy("refresh"), "BusinessRefresh", func(): d._browse_url(d.browser_url, false))
	refresh.add_theme_stylebox_override("normal", UI.style(PURPLE, Color.TRANSPARENT, 12, 5, 3))
	refresh.add_theme_stylebox_override("hover", UI.style(PURPLE_DARK, Color.TRANSPARENT, 12, 5, 3))
	refresh.add_theme_color_override("font_color", Color.WHITE)
	refresh.add_theme_color_override("font_hover_color", Color.WHITE)
	var title := copy("statements") if view == "accounting" else copy("orders")
	if view == "sales" and not str(state.get("selected_order", "")).is_empty(): title += " / " + str(state.selected_order)
	_label(d, row, title, 16, INK)
	var search := LineEdit.new()
	search.name = "BusinessSearch"
	search.placeholder_text = copy("search", "Search")
	search.text = str(state.get("query", ""))
	search.custom_minimum_size = Vector2(230, 32)
	search.clear_button_enabled = true
	search.visible = view == "sales" and str(state.get("selected_order", "")).is_empty()
	search.add_theme_stylebox_override("normal", UI.style(Color.WHITE, LINE, 8, 4, 2))
	search.add_theme_stylebox_override("focus", UI.style(Color.WHITE, PURPLE, 8, 4, 2))
	row.add_child(search)
	var count := _label(d, row, "", 12, MUTED)
	count.name = "BusinessOrderCount"; count.size_flags_horizontal = Control.SIZE_SHRINK_END
	return search

static func render(d, parent: VBoxContainer, url: String, response: String) -> void:
	var state := _state(d)
	var lower_url := url.to_lower()
	var view := "accounting" if "/accounting" in lower_url else "sales"
	state["view"] = view
	var payload := _payload(response)
	var data := _data(payload)
	var external_storage := _external_storage(payload, data)
	if bool(external_storage.get("enabled", false)) and not str(external_storage.get("path", "")).is_empty():
		data = data.duplicate(true)
		data["source"] = str(external_storage.get("path", ""))
	if view == "sales" and bool(payload.get("ok", false)) and _find_order(_orders(data), str(state.get("selected_order", ""))).is_empty(): state.selected_order = ""
	if bool(payload.get("transport_error", false)):
		_transport_error(d, parent, payload, response, url)
		return
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 0)
	parent.add_child(page)
	var masthead := PanelContainer.new()
	masthead.add_theme_stylebox_override("panel", UI.style(Color.WHITE, LINE, 10, 5, 0))
	page.add_child(masthead)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", 12); head.custom_minimum_size.y = 32; masthead.add_child(head)
	Glyph.add_to(head, "process", 22, PURPLE)
	_button(d, head, copy("sales"), "BusinessSales", func(): d._browse_url("https://intranet.client.test/sales", true), view == "sales")
	_button(d, head, copy("accounting"), "BusinessAccounting", func(): d._browse_url("https://intranet.client.test/accounting", true), view == "accounting")
	var host := _label(d, head, "intranet.client.test", 12, MUTED); host.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var body := VBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 0); page.add_child(body)
	var search := _toolbar(d, body, state, view)
	var storage_error_shown: bool = _storage_banner(d, body, _external_storage(payload, data))
	if not bool(payload.get("ok", false)):
		if not storage_error_shown: _error(d, body, payload, response)
		return
	if view == "accounting":
		_accounting(d, body, data, response)
	else:
		_sales(d, body, data, state, search, response)

static func _transport_error(d, parent: Node, payload: Dictionary, response: String, url: String) -> void:
	var page := VBoxContainer.new(); page.size_flags_horizontal = Control.SIZE_EXPAND_FILL; page.add_theme_constant_override("separation", 12); parent.add_child(page)
	var box := _panel(page, Color("fafafa"), 24)
	_label(d, box, copy("unreachable", "This site cannot be reached"), 22, INK)
	_label(d, box, url, 13, MUTED)
	_label(d, box, copy("error_" + str(payload.get("error", "network")), "Connection failed"), 14, RED)
	_button(d, box, copy("refresh", "Refresh"), "BusinessRefresh", func(): d._browse_url(url, false))
	_response(d, box, response)

static func _error(d, parent: Node, payload: Dictionary, response: String) -> void:
	var box := _panel(parent, PANEL, 18)
	_label(d, box, _format_error(payload), 18, RED)
	_response(d, box, response)

static func _sales(d, parent: Node, data: Dictionary, state: Dictionary, search: LineEdit, response: String) -> void:
	var orders: Array = _orders(data)
	var selected_id := str(state.get("selected_order", ""))
	var query := str(state.get("query", "")).strip_edges().to_lower()
	var selected_order := _find_order(orders, selected_id)
	if not selected_order.is_empty() and not query.is_empty():
		var selected_search := (str(selected_order.get("order", selected_order.get("id", "")))+" "+str(selected_order.get("customer", ""))+" "+str(selected_order.get("customer_id", ""))).to_lower()
		if not selected_search.contains(query): selected_order = {}
	if not selected_order.is_empty():
		var form := _panel(parent, PANEL, 18)
		_order_details(d, form, selected_order)
		_source(d, parent, data, response, "/srv/data/orders.csv", [_customer_source(data)])
		return
	if not selected_id.is_empty():
		state["selected_order"] = ""
		# The toolbar is built before stale selection is cleared. Restore its
		# list affordance in the same render so a saved selection cannot hide
		# search after a refresh or a changed backend response.
		search.visible = true
	var count: Label = parent.find_child("BusinessOrderCount", true, false)
	var table := VBoxContainer.new(); table.name = "BusinessOrderList"; table.add_theme_constant_override("separation", 0); parent.add_child(table)
	var head_frame := PanelContainer.new(); head_frame.add_theme_stylebox_override("panel", UI.style(Color("f8f9fa"), LINE, 12, 5, 0)); table.add_child(head_frame)
	var columns := HBoxContainer.new(); columns.add_theme_constant_override("separation", 8); head_frame.add_child(columns)
	var order_header := _label(d, columns, copy("order", "Order"), 12, MUTED)
	order_header.custom_minimum_size.x = 140
	order_header.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_label(d, columns, copy("customer", "Customer"), 12, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var total_header := _label(d, columns, copy("total", "Total"), 12, MUTED); total_header.size_flags_horizontal = Control.SIZE_SHRINK_END; total_header.custom_minimum_size.x = 100; total_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var rows: Array[Control] = []
	for raw in orders:
		if not raw is Dictionary: continue
		var order: Dictionary = raw
		var order_id := str(order.get("order", order.get("id", "")))
		var customer := str(order.get("customer", ""))
		var customer_id := str(order.get("customer_id", ""))
		var row_frame := PanelContainer.new(); row_frame.name = "BusinessOrder_" + order_id.validate_node_name(); row_frame.custom_minimum_size.y = 36
		row_frame.set_meta("business_search", (order_id+" "+customer+" "+customer_id).to_lower()); row_frame.set_meta("business_order", order.duplicate(true)); table.add_child(row_frame); rows.append(row_frame)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); row_frame.add_child(row)
		var select := _button(d, row, order_id, "BusinessOrderOpen_" + order_id.validate_node_name(), func(): state["selected_order"] = order_id; _persist(d); d._render_business_workspace())
		select.flat = true; select.alignment = HORIZONTAL_ALIGNMENT_LEFT; select.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; select.custom_minimum_size.x = 140
		for style_key in ["normal", "hover", "pressed"]: select.add_theme_stylebox_override(style_key, UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 0))
		var customer_label := _label(d, row, customer, 14, INK); customer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var total := _label(d, row, _number(order.get("total", "")), 14, INK); total.size_flags_horizontal = Control.SIZE_SHRINK_END; total.custom_minimum_size.x = 100; total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var row_style := UI.style(PANEL if rows.size() % 2 == 1 else Color("f8f9fa"), LINE, 12, 2, 0)
		row_style.set_border_width_all(0); row_style.border_width_bottom = 1
		row_frame.add_theme_stylebox_override("panel", row_style)
		row_frame.mouse_filter = Control.MOUSE_FILTER_STOP; row_frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for item in [customer_label,total]: item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				state["selected_order"] = order_id; _persist(d); d._render_business_workspace())
	var empty_label := _label(d, table, copy("no_results", "No orders"), 14, MUTED)
	empty_label.name = "BusinessNoResults"; empty_label.visible = false
	search.text_changed.connect(func(value): state["query"] = value; _filter(rows, value, empty_label, count); _persist(d))
	_filter(rows, str(state.get("query", "")), empty_label, count)
	_source(d, parent, data, response, "/srv/data/orders.csv", [_customer_source(data)])

static func _filter(rows: Array[Control], query: String, empty_label: Label = null, count_label: Label = null) -> void:
	var needle := query.strip_edges().to_lower()
	var matches := 0
	for row in rows:
		row.visible = needle.is_empty() or str(row.get_meta("business_search", "")).contains(needle)
		if row.visible: matches += 1
	if empty_label != null: empty_label.visible = matches == 0
	if count_label != null: count_label.text = _format_count(copy("records", "%d records"), matches)

static func _find_order(orders: Array, id: String) -> Dictionary:
	for raw in orders:
		if raw is Dictionary and str(raw.get("order", raw.get("id", ""))) == id: return raw
	return {}

static func _order_details(d, parent: Node, order: Dictionary) -> void:
	var heading := HBoxContainer.new(); heading.add_theme_constant_override("separation", 8); parent.add_child(heading)
	var back := _button(d, heading, copy("back", "Back"), "BusinessBack", func(): d.business_ui["selected_order"] = ""; _persist(d); d._render_business_workspace())
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var order_label := _label(d, parent, str(order.get("order", order.get("id", ""))), 30, INK); order_label.name = "BusinessSelectedOrder"
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 20); grid.add_theme_constant_override("v_separation", 8); parent.add_child(grid)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; grid.custom_minimum_size.x = 400
	_field(d, grid, copy("customer", "Customer"), str(order.get("customer", "")))
	_field(d, grid, copy("customer_id", "Customer ID"), str(order.get("customer_id", "")))
	var space := Control.new(); space.custom_minimum_size.y = 32; parent.add_child(space)
	parent.add_child(HSeparator.new())
	var total := HBoxContainer.new(); total.add_theme_constant_override("separation", 24); parent.add_child(total)
	var label := _label(d, total, copy("total"), 15, INK); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var amount := _label(d, total, _number(order.get("total", "")), 22, INK); amount.size_flags_horizontal = Control.SIZE_SHRINK_END

static func _accounting(d, parent: Node, data: Dictionary, response: String) -> void:
	var entries: Array = _ledger(data)
	var table := VBoxContainer.new(); table.add_theme_constant_override("separation", 0); parent.add_child(table)
	var headings := [copy("date"), copy("opening"), copy("closing"), copy("movement")]
	_ledger_row(d, table, headings, true, 0)
	var count: Label = parent.find_child("BusinessOrderCount", true, false)
	count.text = _format_count(copy("records"), entries.size())
	if entries.is_empty():
		var empty := _label(d, table, copy("no_results", "No statements"), 14, MUTED); empty.name = "BusinessNoStatements"
	else:
		for index in entries.size():
			var raw = entries[index]
			if not raw is Dictionary: continue
			var row: Dictionary = raw
			var values := [str(row.get("date", "")), _number(row.get("opening", "")), _number(row.get("closing", "")), _number(row.get("movement", ""))]
			_ledger_row(d, table, values, false, index)
	_source(d, parent, data, response, "/srv/data/ledger.txt")

static func _ledger_row(d, parent: Node, values: Array, header: bool, index: int) -> void:
	var frame := PanelContainer.new()
	var style := UI.style(Color("f8f9fa") if header or index % 2 == 1 else PANEL, LINE, 12, 5, 0)
	style.set_border_width_all(0); style.border_width_bottom = 1
	frame.add_theme_stylebox_override("panel", style); parent.add_child(frame)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 18); frame.add_child(row)
	for column in values.size():
		var cell := _label(d, row, str(values[column]), 12 if header else 14, MUTED if header else INK)
		cell.custom_minimum_size = Vector2(110, 26); cell.clip_text = true; cell.tooltip_text = str(values[column])
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if column == 0 else HORIZONTAL_ALIGNMENT_RIGHT

static func _field(d, parent: Node, title: String, value: String) -> void:
	var label := _label(d, parent, title, 13, INK); label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; label.custom_minimum_size.x = 120
	var data := _label(d, parent, value, 15, INK); data.size_flags_horizontal = Control.SIZE_EXPAND_FILL; data.clip_text = true; data.tooltip_text = value

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

static func _source(d, parent: Node, data: Dictionary, response: String, fallback_source: String = "", additional_sources: Array[String] = []) -> void:
	var source := str(data.get("source", fallback_source))
	var hash := str(data.get("sha256", ""))
	if source.is_empty() and additional_sources.is_empty() and hash.is_empty() and response.is_empty(): return
	var details: VBoxContainer = d._disclosure(parent, copy("source", "Source"))
	if not source.is_empty(): _label(d, details, source, 12, MUTED)
	for extra_source in additional_sources:
		if not str(extra_source).is_empty() and str(extra_source) != source: _label(d, details, str(extra_source), 12, MUTED)
	if not hash.is_empty(): _label(d, details, "SHA-256  " + hash, 12, MUTED)
	_response(d, details, response)

static func _response(d, parent: Node, response: String) -> void:
	if response.is_empty(): return
	var details: VBoxContainer = d._disclosure(parent, copy("response", "Response"))
	var text := TextEdit.new(); text.name = "BusinessResponse"; text.editable = false; text.text = response; text.custom_minimum_size.y = 100; text.add_theme_font_override("font", d.mono); details.add_child(text)
