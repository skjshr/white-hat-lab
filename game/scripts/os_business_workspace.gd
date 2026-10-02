extends RefCounted
class_name OSBusinessWorkspace

## Odoo-like sales and accounting workspace over the customer's real JSON response.
## Drafts and selection live in the desktop session; Game commits business changes.

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
	var title := copy("statements") if view == "accounting" else ("顧客一覧" if view == "customers" else copy("orders"))
	if view == "sales" and not str(state.get("selected_order", "")).is_empty(): title += " / " + str(state.selected_order)
	_label(d, row, title, 16, INK)
	var search := LineEdit.new()
	search.name = "BusinessSearch"
	search.placeholder_text = "顧客名または番号を検索" if view == "customers" else copy("search", "Search")
	search.text = str(state.get("query", ""))
	search.custom_minimum_size = Vector2(230, 32)
	search.clear_button_enabled = true
	search.visible = view == "customers" or (view == "sales" and str(state.get("selected_order", "")).is_empty())
	search.add_theme_stylebox_override("normal", UI.style(Color.WHITE, LINE, 8, 4, 2))
	search.add_theme_stylebox_override("focus", UI.style(Color.WHITE, PURPLE, 8, 4, 2))
	row.add_child(search)
	var count := _label(d, row, "", 12, MUTED)
	count.name = "BusinessOrderCount"; count.size_flags_horizontal = Control.SIZE_SHRINK_END
	return search

static func render(d, parent: VBoxContainer, url: String, response: String) -> void:
	var state := _state(d)
	var lower_url := url.to_lower()
	var view := "accounting" if "/accounting" in lower_url else ("customers" if "/customers" in lower_url else "sales")
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
	_button(d, head, "顧客", "BusinessCustomers", func(): d._browse_url("https://intranet.client.test/customers", true), view == "customers")
	_button(d, head, copy("accounting"), "BusinessAccounting", func(): d._browse_url("https://intranet.client.test/accounting", true), view == "accounting")
	var host := _label(d, head, "intranet.client.test", 12, MUTED); host.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var body := VBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 0); page.add_child(body)
	var search := _toolbar(d, body, state, view)
	var storage_error_shown: bool = _storage_banner(d, body, _external_storage(payload, data))
	if not bool(payload.get("ok", false)):
		if not storage_error_shown: _error(d, body, payload, response)
		return
	state["revision"] = str(payload.get("revision",""))
	state["can_write"] = bool(payload.get("capabilities",{}).get("write",false))
	if not str(state.get("notice","")).is_empty():
		var notice := _label(d,body,str(state.notice),14,INK); notice.name = "BusinessFeedback"; notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not str(state.get("form","")).is_empty():
		search.visible = false
		_crud_form(d,body,data,state)
		return
	if view == "accounting":
		if bool(state.can_write): _primary(d,body,"入出金を記録","BusinessNewLedger",func(): _begin_edit(d,"append_ledger"))
		_accounting(d, body, data, response)
	elif view == "customers":
		_customers(d,body,data,state,search)
	else:
		if bool(state.can_write): _primary(d,body,"受注を登録","BusinessNewOrder",func(): _begin_edit(d,"create_order"))
		_sales(d, body, data, state, search, response)
	_history(d,body,data)

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
	var summary := HBoxContainer.new(); summary.add_theme_constant_override("separation", 16); parent.add_child(summary)
	var order_label := _label(d, summary, str(order.get("order", order.get("id", ""))), 30, INK); order_label.name = "BusinessSelectedOrder"
	order_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var total := HBoxContainer.new(); total.add_theme_constant_override("separation", 10); total.size_flags_horizontal = Control.SIZE_SHRINK_END; summary.add_child(total)
	var label := _label(d, total, copy("total"), 13, MUTED); label.size_flags_horizontal = Control.SIZE_SHRINK_END
	var amount := _label(d, total, _number(order.get("total", "")), 22, INK); amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 20); grid.add_theme_constant_override("v_separation", 8); parent.add_child(grid)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; grid.custom_minimum_size.x = 400
	_field(d, grid, copy("customer", "Customer"), str(order.get("customer", "")))
	_field(d, grid, copy("customer_id", "Customer ID"), str(order.get("customer_id", "")))
	if bool(d.business_ui.get("can_write",false)):
		var actions := HBoxContainer.new(); parent.add_child(actions)
		var original := {"id":str(order.get("order","")),"customer":str(order.get("customer_id","")),"total":str(order.get("total",0))}
		_button(d,actions,"変更","BusinessEditOrder",func(): _begin_edit(d,"update_order",original))
		_button(d,actions,"この受注を取り消す","BusinessDeleteOrder",func(): _begin_edit(d,"delete_order",original))

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

static func _primary(d, parent: Node, text: String, node_name: String, callback: Callable) -> Button:
	var button := _button(d,parent,text,node_name,callback)
	button.add_theme_stylebox_override("normal",UI.style(PURPLE,Color.TRANSPARENT,12,7,4))
	button.add_theme_stylebox_override("hover",UI.style(PURPLE_DARK,Color.TRANSPARENT,12,7,4))
	button.add_theme_color_override("font_color",Color.WHITE); button.add_theme_color_override("font_hover_color",Color.WHITE)
	return button

static func _begin_edit(d, action: String, values: Dictionary = {}) -> void:
	d.business_ui.form = action; d.business_ui.form_values = values.duplicate(true)
	d.business_ui.form_revision = str(d.business_ui.get("revision","")); d.business_ui.notice = ""
	_persist(d); d._render_business_workspace()

static func _customers(d, parent: Node, data: Dictionary, state: Dictionary, search: LineEdit) -> void:
	if bool(state.get("can_write",false)): _primary(d,parent,"顧客を登録","BusinessNewCustomer",func(): _begin_edit(d,"create_customer"))
	var rows: Array[Control] = []
	for customer in data.get("customers",[]):
		var row := HBoxContainer.new(); parent.add_child(row)
		row.set_meta("business_search",(str(customer.id)+" "+str(customer.name)).to_lower()); rows.append(row)
		_label(d,row,str(customer.id),14,MUTED)
		_label(d,row,str(customer.name),16,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bool(state.get("can_write",false)):
			_button(d,row,"変更","BusinessEditCustomer_"+str(customer.id),func(): _begin_edit(d,"update_customer",customer))
			_button(d,row,"削除","BusinessDeleteCustomer_"+str(customer.id),func(): _begin_edit(d,"delete_customer",customer))
	var count: Label = parent.find_child("BusinessOrderCount",true,false)
	var empty := _label(d,parent,"該当する顧客はありません。",14,MUTED)
	search.text_changed.connect(func(value): state.query=value; _filter(rows,value,empty,count); _persist(d))
	_filter(rows,str(state.get("query","")),empty,count)

static func _crud_form(d, parent: Node, data: Dictionary, state: Dictionary) -> void:
	var action := str(state.form)
	var titles := {"create_order":"受注を登録","update_order":"受注を変更","delete_order":"受注の取消","create_customer":"顧客を登録","update_customer":"顧客名を変更","delete_customer":"顧客の削除","append_ledger":"入出金を記録"}
	var form := _panel(parent,PANEL,16)
	_label(d,form,str(titles.get(action,action)),22,INK)
	var values: Dictionary = state.get("form_values",{})
	if action.begins_with("delete_"):
		_label(d,form,"対象: "+str(values.get("id",""))+"  "+str(values.get("name","")),16,INK)
		_label(d,form,"登録済みの受注がある顧客は削除できません。" if action=="delete_customer" else "この受注を一覧から取り消します。",14,MUTED)
	elif action.ends_with("customer"):
		_input(d,form,values,"name","顧客名","BusinessCustomerName","80字以内。カンマ・改行は使えません。")
	elif action.ends_with("order"):
		_label(d,form,"顧客",14,INK)
		var select := OptionButton.new(); select.name = "BusinessCustomerChoice"; form.add_child(select)
		for customer in data.get("customers",[]):
			select.add_item(str(customer.name)+"  ("+str(customer.id)+")")
			select.set_item_metadata(select.item_count-1,str(customer.id))
			if str(values.get("customer","")) == str(customer.id): select.select(select.item_count-1)
		if select.item_count > 0 and not values.has("customer"): values.customer = str(select.get_item_metadata(select.selected))
		select.item_selected.connect(func(index): values.customer = str(select.get_item_metadata(index)); _persist(d))
		_input(d,form,values,"total","受注金額（円）","BusinessOrderTotal","0以上の整数")
	else:
		_input(d,form,values,"date","記帳日","BusinessLedgerDate","YYYY-MM-DD（最終記帳日より後）")
		_input(d,form,values,"amount","入出金額（円）","BusinessLedgerAmount","入金は正、出金は負の整数")
		_label(d,form,"期首残高は前回の残高から引き継ぎます。訂正も新しい記帳として残します。",14,MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.form_values = values
	var controls := HBoxContainer.new(); form.add_child(controls)
	_primary(d,controls,"取り消す" if action.begins_with("delete_") else "保存","BusinessSave",func(): _submit(d,action))
	_button(d,controls,"戻る","BusinessCancel",func(): state.form = ""; state.notice = ""; _persist(d); d._render_business_workspace())

static func _input(d, parent: Node, values: Dictionary, key: String, title: String, node_name: String, placeholder: String) -> void:
	_label(d,parent,title,14,INK)
	var edit := LineEdit.new(); edit.name = node_name; edit.placeholder_text = placeholder; edit.text = str(values.get(key,"")); edit.custom_minimum_size.y = 36; parent.add_child(edit)
	edit.text_changed.connect(func(value): values[key] = value; _persist(d))

static func _submit(d, action: String) -> void:
	var state: Dictionary = d.business_ui
	var args: Dictionary = state.get("form_values",{}).duplicate(true)
	for key in ["total","amount"]:
		if args.has(key) and str(args[key]).is_valid_int(): args[key] = int(args[key])
	args.expected_revision = str(state.get("form_revision","")); args.request_url = d.browser_url
	var result: Dictionary = d.game.business_action(action,args)
	if bool(result.get("ok",false)):
		state.form = ""; state.form_values = {}; state.notice = "保存しました。"
		if action.ends_with("order"): state.selected_order = str(result.get("item",{}).get("order","")) if not action.begins_with("delete_") else ""
	else:
		var messages := {"conflict":"別の画面で更新されました。入力は保留されています。戻って最新の内容を確認してください。","recovery_required":"復旧対象の原本がまだ一致しません。先に資料の復旧を確認してください。","storage_readonly":"共有元が読み取り専用です。","customer_has_orders":"受注がある顧客は削除できません。","invalid_name":"顧客名を80字以内で入力してください。カンマ・改行は使えません。","invalid_amount":"金額は範囲内の整数で入力してください。","unknown_customer":"登録済みの顧客を選択してください。","invalid_date":"日付をYYYY-MM-DDで入力してください。","date_must_follow_ledger":"最終記帳日より後の日付を入力してください。","invalid_balance":"残高が不足する、または上限を超える記帳です。","save_failed":"保存できませんでした。変更は反映していません。"}
		state.notice = str(messages.get(str(result.get("error","")),"操作できません: "+str(result.get("error",""))))
	_persist(d)
	var resource := "ledger" if "/accounting" in d.browser_url else ("customers" if "/customers" in d.browser_url else "orders")
	d.browser_response = str(d.game.business_read(resource,d.browser_url).get("response",""))
	d._render_business_workspace()

static func _history(d, parent: Node, data: Dictionary) -> void:
	var records: Array = data.get("history",[])
	if records.is_empty(): return
	var box := _panel(parent,PANEL,10)
	_label(d,box,"最近の操作",14,MUTED)
	var names := {"create_customer":"顧客登録","update_customer":"顧客変更","delete_customer":"顧客削除","create_order":"受注登録","update_order":"受注変更","delete_order":"受注取消","append_ledger":"記帳"}
	for row in records.slice(maxi(0,records.size()-3)):
		var item: Dictionary = row.get("item",{})
		_label(d,box,"%s  %s" % [str(names.get(str(row.action),str(row.action))),str(item.get("id",item.get("order",item.get("date",""))))],13,INK)

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
