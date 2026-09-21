const UI := preload("res://scripts/ui_theme.gd")
const EQUIPMENT_ART := preload("res://scripts/equipment_art.gd")
const THEME := preload("res://scripts/game_theme.gd")

const HEADER := THEME.HEADER
const TAB_BAR := THEME.TAB_BAR
const TAB := THEME.TAB
const FILTER := THEME.FILTER
const CANVAS := THEME.CANVAS
const CARD_FRAME := THEME.CARD_FRAME
const CARD := THEME.CARD
const ACTION := THEME.ACTION
const SUCCESS := THEME.SUCCESS
const TEXT := THEME.TEXT
const FOOTER := THEME.FOOTER
const YELLOW := Color("ffd65b")
const PURPLE := TAB
const PURPLE_DARK := YELLOW
const PAPER := CANVAS
const BORDER := TAB_BAR
const INK := TEXT
const MUTED := Color("c6e8ef")

static func _copy(key: String, fallback: String = "") -> String:
	return UI.copy(key, fallback)

static func _label(ui, host: Node, text: String, size: int = 14, color: Color = INK) -> Label:
	var node: Label = ui._label(text, size, color)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_override("font", UI.font(500))
	host.add_child(node)
	return node

static func _button(ui, host: Node, text: String, action: Callable, name: String = "") -> Button:
	var node: Button = ui._button(text, action)
	if not name.is_empty(): node.name = name
	node.custom_minimum_size.y = 34
	node.add_theme_font_override("font", UI.font(500))
	node.add_theme_font_size_override("font_size", int(14 * ui.text_scale))
	for state in ["normal", "hover", "pressed", "disabled"]:
		node.add_theme_stylebox_override(state, UI.style(TAB_BAR if state == "hover" else ACTION if state == "pressed" else FILTER, TAB, 10, 6, 2))
	node.add_theme_color_override("font_color", TAB)
	node.add_theme_color_override("font_hover_color", TAB)
	node.add_theme_color_override("font_pressed_color", TEXT)
	node.add_theme_color_override("font_focus_color", TAB)
	host.add_child(node)
	return node

static func _primary(button: Button) -> void:
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, UI.style(SUCCESS if state == "normal" else Color("008f18"), Color.TRANSPARENT, 12, 6, 2))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, Color.WHITE)

static func _product(game, sku: String) -> Dictionary:
	for item in _catalog(game):
		if str(item.get("sku", "")) == sku: return item
	return {}

static func _panel(host: Node, color: Color = PAPER, padding: int = 14, frame_name: String = "") -> VBoxContainer:
	var frame := PanelContainer.new()
	if not frame_name.is_empty(): frame.name = frame_name
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UI.style(color, BORDER, padding, padding, 0))
	host.add_child(frame)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	frame.add_child(body)
	return body

static func _meta(ui, key: String, fallback: String = "") -> String:
	return str(ui.get_meta(key, fallback)) if ui.has_meta(key) else fallback

static func _set_meta(ui, key: String, value: String) -> void:
	ui.set_meta(key, value)

static func _catalog(game) -> Array:
	if game == null or not game.has_method("customer_stock_catalog"): return []
	var result: Variant = game.customer_stock_catalog()
	return result if result is Array else []

static func _sku(item: Dictionary) -> String:
	return str(item.get("sku", item.get("id", "gateway")))

static func _units(game) -> Array:
	if game == null or not game.has_method("customer_stock_units"): return []
	var result: Variant = game.customer_stock_units()
	return result if result is Array else []

static func _icon(id: String) -> Texture2D:
	return EQUIPMENT_ART.icon(id)

static func _stock_count(game, sku: String) -> int:
	var count := 0
	for raw in _units(game):
		if raw is Dictionary and str(raw.get("sku", "gateway")) == sku and str(raw.get("status", "")) in ["ready", "carried", "stored", "staged"]: count += 1
	return count

static func _state_text(status: String) -> String:
	return _copy("stock_status_" + status, status)

static func _location_text(unit: Dictionary) -> String:
	match str(unit.get("status", "")):
		"queued", "shipping": return _copy("stock_in_transit", "In transit")
		"ready": return _copy("stock_receive_area", "Receiving area")
		"carried": return _copy("stock_carry_location", "With operator")
		"stored": return _copy("stock_storage_shelf", "Shelf") + " %d" % (int(unit.get("shelf_slot", 0)) + 1)
		"staged": return _copy("stock_setup_bench", "Setup bench")
		"delivered": return _copy("stock_client_site", "Customer site")
		_: return "—"

static func _assigned_client(game, unit: Dictionary) -> String:
	var contract_id := str(unit.get("contract_id", ""))
	if contract_id.is_empty(): return _copy("stock_unassigned", "Unassigned")
	var contexts: Dictionary = game.state.get("contract_contexts", {}) if game.state.get("contract_contexts", {}) is Dictionary else {}
	var context: Dictionary = contexts.get(contract_id, {}) if contexts.get(contract_id, {}) is Dictionary else {}
	if context.is_empty() and str(game.state.get("current_contract_id", "")) == contract_id: context = {"contract": game.state.get("contract", {})}
	var contract: Dictionary = context.get("contract", {}) if context.get("contract", {}) is Dictionary else {}
	return str(contract.get("client", contract_id))

static func _catalog_tab(ui, parent: Node, active: bool) -> Button:
	var tab := _button(ui, parent, _copy("stock_catalog", "Catalog"), func(): _set_meta(ui, "stock_view", "catalog"); ui.open_panel("shop"), "StockCatalogTab")
	tab.toggle_mode = true; tab.button_pressed = active
	if active: _primary(tab)
	return tab

static func _inventory_tab(ui, parent: Node, active: bool) -> Button:
	var tab := _button(ui, parent, _copy("stock_inventory", "Serial inventory"), func(): _set_meta(ui, "stock_view", "inventory"); ui.open_panel("shop"), "StockInventoryTab")
	tab.toggle_mode = true; tab.button_pressed = active
	if active: _primary(tab)
	return tab

static func render(ui, parent: VBoxContainer, game) -> void:
	if game == null:
		_label(ui, parent, "Procurement unavailable", 16, UI.RED); return
	var view := _meta(ui, "stock_view", "catalog")
	if view not in ["catalog", "inventory"]: view = "catalog"
	var root := _panel(parent, CANVAS, 14); root.name = "CustomerStockProcurement"
	root.get_parent().theme = UI.make_theme(ui.text_scale)
	var appbar := PanelContainer.new(); appbar.name = "StockAppBar"; appbar.add_theme_stylebox_override("panel", UI.style(HEADER, HEADER, 0, 0, 0)); root.add_child(appbar)
	var appbar_row := HBoxContainer.new(); appbar_row.custom_minimum_size.y = 46; appbar_row.add_theme_constant_override("separation", 12); appbar.add_child(appbar_row)
	var title := _label(ui, appbar_row, _copy("stock_title", "Purchasing"), 22, TEXT); title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; appbar_row.add_child(spacer)
	var summary: Dictionary = game.customer_stock_summary() if game.has_method("customer_stock_summary") else {}
	var cash := _label(ui, appbar_row, "¥%d" % int(summary.get("cash", game.state.get("cash", 0))), 14, INK); cash.size_flags_horizontal = Control.SIZE_SHRINK_END; cash.autowrap_mode = TextServer.AUTOWRAP_OFF
	var capacity := _label(ui, appbar_row, _copy("stock_capacity", "%d / %d") % [int(summary.get("used", 0)), int(summary.get("capacity", 0))], 14, FOOTER); capacity.name = "StockCapacity"; capacity.size_flags_horizontal = Control.SIZE_SHRINK_END; capacity.autowrap_mode = TextServer.AUTOWRAP_OFF
	var toolbar := HBoxContainer.new(); toolbar.name = "StockCommandToolbar"; toolbar.add_theme_constant_override("separation", 6); root.add_child(toolbar)
	var equipment_tab := _button(ui, toolbar, _copy("stock_equipment_tab", "Equipment"), func(): ui.shop_view = "equipment"; ui.open_panel("shop"), "StockEquipmentTab"); equipment_tab.toggle_mode = true; equipment_tab.button_pressed = false
	_catalog_tab(ui, toolbar, view == "catalog"); _inventory_tab(ui, toolbar, view == "inventory")
	if view == "inventory": _inventory(ui, root, game)
	else: _catalog_view(ui, root, game)

static func _catalog_view(ui, parent: Node, game) -> void:
	var catalog: Array = _catalog(game)
	var selected_sku := _meta(ui, "stock_sku", _sku(catalog[0]) if not catalog.is_empty() and catalog[0] is Dictionary else "gateway")
	var requirement: Dictionary = game.state.get("contract", {}).get("supply_requirement", {}) if game.state.get("contract", {}) is Dictionary else {}
	if bool(game.state.get("accepted", false)) and not requirement.is_empty() and not str(requirement.get("sku", "")).is_empty(): _label(ui, parent, _copy("stock_current_job", "Current job") + "  ·  " + str(_product(game, str(requirement.sku)).get("title", requirement.sku)), 13, TAB)
	var cards := GridContainer.new(); cards.name = "StockProductCards"; cards.columns = 2 if float(ui.root.size.x) >= 1050.0 else 1; cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cards.add_theme_constant_override("h_separation", 10); cards.add_theme_constant_override("v_separation", 10); parent.add_child(cards)
	cards.name = "StockProductTable"
	for raw in catalog:
		if raw is Dictionary: _product_card(ui, cards, game, raw, _sku(raw) == selected_sku)
	if catalog.is_empty(): _label(ui, parent, _copy("stock_empty", "No products"), 14, TAB)
	else: _order_line(ui, parent, game, catalog, selected_sku)

static func _product_card(ui, parent: Node, game, item: Dictionary, selected: bool) -> void:
	var sku := _sku(item); var card := PanelContainer.new(); card.name = "StockProduct_" + sku; card.custom_minimum_size = Vector2(250, 152); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.add_theme_stylebox_override("panel", UI.style(ACTION if selected else CARD, TAB_BAR if selected else CARD_FRAME, 10, 10, 1)); parent.add_child(card)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); card.add_child(row)
	var image := TextureRect.new(); image.name = "StockProductImage_" + sku; image.texture = _icon(str(item.get("icon", sku))); image.custom_minimum_size = Vector2(92, 92); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; row.add_child(image)
	var details := VBoxContainer.new(); details.size_flags_horizontal = Control.SIZE_EXPAND_FILL; details.add_theme_constant_override("separation", 3); row.add_child(details)
	var title := _label(ui, details, str(item.get("title", sku)), 16, TEXT); title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(ui, details, str(item.get("model", "")) + " · " + str(item.get("supplier", "")), 12, MUTED)
	_label(ui, details, _copy("stock_unit_price", "Unit price") + "  ¥%d" % int(item.get("unit_cost", 0)), 13, YELLOW)
	_label(ui, details, _copy("stock_on_hand", "On hand") + "  %d" % _stock_count(game, sku), 12, MUTED)
	var select := _button(ui, details, _copy("stock_pick_product", "Select product"), func(): _set_meta(ui, "stock_sku", sku); ui.open_panel("shop"), "StockSelect_" + sku); select.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; select.disabled = selected

static func _order_line(ui, parent: Node, game, catalog: Array, selected_sku: String) -> void:
	var item: Dictionary = {}
	for raw in catalog:
		if raw is Dictionary and _sku(raw) == selected_sku: item = raw; break
	if item.is_empty() and catalog[0] is Dictionary: item = catalog[0]
	var order := _panel(parent, CARD_FRAME, 12); order.name = "StockPurchaseOrder"
	var order_title := _label(ui, order, _copy("stock_order_lines", "Order lines"), 18, TEXT)
	var line := HBoxContainer.new(); line.add_theme_constant_override("separation", 12); order.add_child(line)
	var image := TextureRect.new(); image.name = "StockProductImage"; image.texture = _icon(str(item.get("icon", selected_sku))); image.custom_minimum_size = Vector2(66, 56); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; line.add_child(image)
	var product_column := VBoxContainer.new(); product_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; line.add_child(product_column)
	_label(ui, product_column, str(item.get("title", selected_sku)), 14, INK)
	_label(ui, product_column, str(item.get("summary", "")), 12, MUTED)
	var quantity_column := VBoxContainer.new(); line.add_child(quantity_column); _label(ui, quantity_column, _copy("stock_quantity", "Quantity"), 12, MUTED)
	var quantity := SpinBox.new(); quantity.name = "StockQuantity"; quantity.min_value = 1; quantity.max_value = 3; quantity.step = 1; quantity.value = 1; quantity.custom_minimum_size.x = 76; quantity_column.add_child(quantity)
	var price_column := VBoxContainer.new(); line.add_child(price_column); _label(ui, price_column, _copy("stock_unit_price", "Unit price"), 12, MUTED)
	var unit_cost := int(item.get("unit_cost", 0)); var unit_price := _label(ui, price_column, "¥%d" % unit_cost, 14, INK); unit_price.custom_minimum_size.x = 80; unit_price.size_flags_horizontal = Control.SIZE_SHRINK_END
	var total_column := VBoxContainer.new(); line.add_child(total_column); _label(ui, total_column, _copy("stock_total", "Total"), 12, MUTED)
	var subtotal := _label(ui, total_column, "¥%d" % unit_cost, 14, PURPLE_DARK); subtotal.name = "StockSubtotal"; subtotal.custom_minimum_size.x = 90; subtotal.size_flags_horizontal = Control.SIZE_SHRINK_END
	quantity.value_changed.connect(func(value: float): subtotal.text = "¥%d" % (unit_cost * int(value)))
	var actions := HBoxContainer.new(); actions.add_theme_constant_override("separation", 8); order.add_child(actions)
	var result_label := _label(ui, actions, "", 13, UI.RED); result_label.name = "StockPurchaseResult"; var fill := Control.new(); fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(fill)
	var confirm := _button(ui, actions, _copy("stock_purchase", "Confirm purchase"), func():
		var result_variant: Variant = game.call("buy_customer_stock", int(quantity.value), selected_sku)
		var result: Dictionary = result_variant if result_variant is Dictionary else {"ok":false,"error":"purchase_failed"}
		if bool(result.get("ok", false)):
			_set_meta(ui, "stock_search", ""); _set_meta(ui, "stock_filter", ""); _set_meta(ui, "stock_selected_serial", "")
			_set_meta(ui, "stock_view", "inventory"); ui.open_panel("shop")
		else: result_label.text = _copy("stock_error_" + str(result.get("error", "unknown")), str(result.get("error", "purchase_failed")))
	, "StockPurchase"); _primary(confirm)

static func _inventory(ui, parent: Node, game) -> void:
	var search_row := HBoxContainer.new(); search_row.add_theme_constant_override("separation", 8); parent.add_child(search_row)
	var search := LineEdit.new(); search.name = "StockSearchSerial"; search.placeholder_text = _copy("stock_search_serial", "Search serial"); search.text = _meta(ui, "stock_search", ""); search.size_flags_horizontal = Control.SIZE_EXPAND_FILL; search_row.add_child(search)
	var search_action := func(): _set_meta(ui, "stock_search", search.text.strip_edges()); ui.open_panel("shop")
	var search_button := _button(ui, search_row, _copy("os_search", "Search"), search_action, "StockSearchButton"); search_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	search.text_submitted.connect(func(_text: String): search_action.call())
	var filter := OptionButton.new(); filter.name = "StockSkuFilter"; filter.add_item(_copy("stock_all_products", "All products"), 0); filter.set_item_metadata(0, "")
	for raw in _catalog(game):
		if raw is Dictionary: filter.add_item(str(raw.get("title", _sku(raw))), filter.item_count); filter.set_item_metadata(filter.item_count - 1, _sku(raw))
	var wanted_filter := _meta(ui, "stock_filter", "")
	for index in range(filter.item_count):
		if str(filter.get_item_metadata(index)) == wanted_filter: filter.select(index); break
	filter.item_selected.connect(func(index: int): _set_meta(ui, "stock_filter", str(filter.get_item_metadata(index))); ui.open_panel("shop")); search_row.add_child(filter)
	var query := _meta(ui, "stock_search", "").to_lower(); var sku_filter := _meta(ui, "stock_filter", ""); var selected_serial := _meta(ui, "stock_selected_serial", "")
	var table := _panel(parent, CARD_FRAME, 10, "StockUnits"); table.name = "StockUnitTable"
	var grid := GridContainer.new(); grid.columns = 5; grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 8); table.add_child(grid)
	for label_text in [_copy("stock_serial", "Serial"), _copy("stock_model", "Model"), _copy("stock_status", "Status"), _copy("stock_client", "Client"), _copy("stock_location", "Location")]:
		var h := _label(ui, grid, label_text, 12, MUTED); h.add_theme_font_override("font", UI.font(700))
	var visible_count := 0
	for raw_unit in _units(game):
		if not raw_unit is Dictionary: continue
		var unit: Dictionary = raw_unit; var serial := str(unit.get("serial", unit.get("id", ""))); var sku := str(unit.get("sku", "gateway"))
		var assigned := _assigned_client(game, unit)
		var searchable := serial + " " + sku + " " + str(unit.get("model", "")) + " " + assigned
		if not query.is_empty() and not searchable.to_lower().contains(query): continue
		if not sku_filter.is_empty() and sku != sku_filter: continue
		visible_count += 1
		var open := _button(ui, grid, serial, func(): _set_meta(ui, "stock_selected_serial", serial); ui.open_panel("shop"), "StockSerial_" + serial); open.alignment = HORIZONTAL_ALIGNMENT_LEFT; open.flat = true; open.add_theme_color_override("font_color", PURPLE_DARK); open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(ui, grid, str(unit.get("model", sku)), 13, INK); _label(ui, grid, _state_text(str(unit.get("status", "unknown"))), 13, INK); _label(ui, grid, assigned, 13, MUTED); _label(ui, grid, _location_text(unit), 13, MUTED)
	if visible_count == 0: _label(ui, table, _copy("stock_empty" if query.is_empty() and sku_filter.is_empty() else "stock_no_matches", "No matching units"), 14, MUTED)
	if not selected_serial.is_empty():
		for raw_unit in _units(game):
			if raw_unit is Dictionary and str(raw_unit.get("serial", raw_unit.get("id", ""))) == selected_serial: _inventory_detail(ui, parent, game, raw_unit); break

static func _inventory_detail(ui, parent: Node, game, unit: Dictionary) -> void:
	var detail := _panel(parent, CARD_FRAME, 12); detail.name = "StockSelectedDetail"
	var title := _label(ui, detail, str(unit.get("serial", "")), 18, PURPLE_DARK); title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var rows := [[_copy("stock_product", "Product"), str(_product(game, str(unit.get("sku", ""))).get("title", unit.get("model", "")))], [_copy("stock_model", "Model"), str(unit.get("model", ""))], [_copy("stock_status", "Status"), _state_text(str(unit.get("status", "unknown")))], [_copy("stock_location", "Location"), _location_text(unit)], [_copy("stock_client", "Client"), _assigned_client(game, unit)]]
	for pair in rows:
		var row := HBoxContainer.new(); row.custom_minimum_size.y = 30; detail.add_child(row)
		var key := _label(ui, row, str(pair[0]), 12, MUTED); key.custom_minimum_size.x = 130; key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_label(ui, row, str(pair[1]), 13, INK)
