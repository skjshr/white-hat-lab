const UI := preload("res://scripts/ui_theme.gd")
const EQUIPMENT_ART := preload("res://scripts/equipment_art.gd")
const THEME := preload("res://scripts/game_theme.gd")
const M := preload("res://scripts/management_ui.gd")

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
	M.button(node)
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
	frame.add_theme_stylebox_override("panel", M.surface(M.CANVAS if color != M.PAPER else M.PAPER, padding, false))
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

static func _required_sku(game) -> String:
	var contract: Variant = game.state.get("contract", {}) if game != null else {}
	if contract is Dictionary:
		var requirement: Variant = contract.get("supply_requirement", {})
		if requirement is Dictionary: return str(requirement.get("sku", ""))
	return ""

static func _stock_summary(game, sku: String = "") -> Dictionary:
	if game != null and game.has_method("customer_stock_summary"):
		var result: Variant = game.call("customer_stock_summary", sku)
		if result is Dictionary: return result
	return {}

static func _cart_quantity(game, sku: String) -> int:
	var cart: Variant = game.procurement_cart() if game != null and game.has_method("procurement_cart") else game.state.get("procurement_cart", {}) if game != null else {}
	return clampi(int(cart.get(sku, 0)) if cart is Dictionary else 0, 0, 3)

static func _cart_lines(ui, game) -> Array:
	var review: Dictionary = game.customer_cart_review() if game != null and game.has_method("customer_cart_review") else {}
	return review.get("lines", []) if review.get("lines", []) is Array else []

static func _set_cart_quantity(ui, game, sku: String, quantity: int) -> void:
	quantity = clampi(quantity, 0, 3)
	ui.set_meta("stock_cart_" + sku, quantity)
	if game != null and game.has_method("set_customer_cart"):
		var result: Variant = game.call("set_customer_cart", sku, quantity)
		if result is Dictionary and not bool(result.get("ok", true)):
			ui.set_meta("stock_cart_error", str(result.get("error", "")))
			var persisted := _cart_quantity(game, sku)
			var spin: Variant = ui.modal.find_child("StockCartQuantity_" + sku, true, false) if is_instance_valid(ui.modal) else null
			if spin is SpinBox: spin.set_value_no_signal(persisted)
		else:
			ui.set_meta("stock_cart_error", "")
	refresh_live(ui)

static func _cart_review(ui, game) -> Dictionary:
	if game != null and game.has_method("customer_cart_review"):
		var result: Variant = game.call("customer_cart_review")
		if result is Dictionary: return result
	return {}

static func _review_reason(review: Dictionary) -> String:
	var reason_text := str(review.get("error", "")) if not bool(review.get("ok", false)) else ""
	if reason_text == "empty" or (reason_text.is_empty() and int(review.get("quantity", 0)) <= 0): return _copy("v220_cart_empty")
	return _copy("stock_error_" + reason_text, _copy("stock_error_unknown")) if not reason_text.is_empty() else ""

static func _footer_reason(ui, review: Dictionary) -> String:
	var save_error := _meta(ui, "stock_cart_error", "")
	if not save_error.is_empty(): return _copy("stock_error_" + save_error, _copy("stock_error_unknown"))
	return _review_reason(review)

static func _submit_cart(ui, game) -> void:
	var result: Dictionary = {}
	if game != null and game.has_method("buy_customer_cart"):
		var value: Variant = game.call("buy_customer_cart")
		result = value if value is Dictionary else {"ok":false,"error":"purchase_failed"}
	else:
		result = {"ok":false,"error":"unknown"}
	var feedback: Variant = ui.modal_footer.find_child("StockPurchaseResult", true, false) if is_instance_valid(ui.modal_footer) else null
	if not bool(result.get("ok", false)):
		if feedback is Label: feedback.text = _copy("stock_error_" + str(result.get("error", "unknown")), _copy("stock_error_unknown"))
		return
	ui.set_meta("stock_cart_error", "")
	_set_meta(ui, "stock_view", "inventory")
	ui.open_panel("shop")

static func _stock_footer(ui, game) -> void:
	if not is_instance_valid(ui.modal_footer): return
	for child in ui.modal_footer.get_children():
		if child.name == "StockOrderFooter": child.queue_free()
	var review := _cart_review(ui, game)
	var footer := PanelContainer.new(); footer.name = "StockOrderFooter"; footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_theme_stylebox_override("panel", M.surface(M.PAPER, 12, true)); ui.modal_footer.add_child(footer)
	var narrow := float(ui.root.size.x) < 1100.0
	if narrow: footer.custom_minimum_size.x = 560.0
	var row: HBoxContainer = HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("separation", 12); footer.add_child(row)
	var total := _label(ui, row, _copy("v220_order_total", _copy("stock_total")) + "  ¥%d" % int(review.get("total", 0)), 16, M.INK); total.name = "StockFooterTotal"; total.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var cash_after := _label(ui, row, _copy("v220_after_purchase", "") + "  ¥%d" % int(review.get("cash_after", game.state.get("cash", 0))), 12, M.MUTED); cash_after.name = "StockCashAfter"; cash_after.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var summary: Dictionary = _stock_summary(game)
	var capacity := int(summary.get("capacity", 0)); var used_after := maxi(0, capacity - int(review.get("free_capacity", capacity)))
	var capacity_after := _label(ui, row, _copy("stock_capacity", "") % [used_after, capacity], 12, M.MUTED); capacity_after.name = "StockCapacityAfter"; capacity_after.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var reason_text := _footer_reason(ui, review)
	var reason := _label(ui, row, reason_text, 12, M.DANGER); reason.name = "StockCartDisabledReason"; reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL; reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var feedback := _label(ui, row, "", 12, M.DANGER); feedback.name = "StockPurchaseResult"; feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL; feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var spacer := Control.new(); spacer.name = "StockFooterSpacer"; spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(spacer)
	var purchase := _button(ui, row, _copy("v220_cart_checkout", _copy("stock_purchase")), func(): _submit_cart(ui, game), "StockPurchase"); _primary(purchase); purchase.size_flags_horizontal = Control.SIZE_SHRINK_END
	M.button(purchase, "primary")
	purchase.disabled = not bool(review.get("ok", false))
	for node in [total, cash_after, capacity_after, reason, feedback, purchase]: node.autowrap_mode = TextServer.AUTOWRAP_OFF
	if narrow:
		for node in [reason, feedback]: node.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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
	tab.toggle_mode = true; tab.button_pressed = active; M.button(tab, "tab", active)
	return tab

static func _inventory_tab(ui, parent: Node, active: bool) -> Button:
	var tab := _button(ui, parent, _copy("stock_inventory", "Serial inventory"), func(): _set_meta(ui, "stock_view", "inventory"); ui.open_panel("shop"), "StockInventoryTab")
	tab.toggle_mode = true; tab.button_pressed = active; M.button(tab, "tab", active)
	return tab

static func render(ui, parent: VBoxContainer, game) -> void:
	if game == null:
		_label(ui, parent, "Procurement unavailable", 16, UI.RED); return
	var view := _meta(ui, "stock_view", "catalog")
	if view not in ["catalog", "inventory"]: view = "catalog"
	var root := _panel(parent, M.CANVAS, 16); root.name = "CustomerStockProcurement"
	root.get_parent().theme = UI.make_theme(ui.text_scale)
	var appbar := PanelContainer.new(); appbar.name = "StockAppBar"; appbar.add_theme_stylebox_override("panel", M.surface(M.PAPER, 0, false)); root.add_child(appbar)
	var appbar_row := HBoxContainer.new(); appbar_row.custom_minimum_size.y = 34; appbar_row.add_theme_constant_override("separation", 12); appbar.add_child(appbar_row)
	var title := _label(ui, appbar_row, _copy("stock_title", "Purchasing"), 22, M.INK); title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var toolbar := HBoxContainer.new(); toolbar.name = "StockCommandToolbar"; toolbar.add_theme_constant_override("separation", 6); root.add_child(toolbar)
	var equipment_tab := _button(ui, toolbar, _copy("stock_equipment_tab", "Equipment"), func(): ui.shop_view = "equipment"; ui.open_panel("shop"), "StockEquipmentTab"); equipment_tab.toggle_mode = true; equipment_tab.button_pressed = false
	_catalog_tab(ui, toolbar, view == "catalog"); _inventory_tab(ui, toolbar, view == "inventory")
	if view == "inventory": _inventory(ui, root, game)
	else:
		_catalog_view(ui, root, game)
		_stock_footer(ui, game)

static func refresh_live(ui) -> void:
	if ui == null or ui.current_kind != "shop" or ui.shop_view != "stock": return
	var game = ui._game()
	if game == null: return
	var review: Dictionary = _cart_review(ui, game)
	var summary: Dictionary = _stock_summary(game)
	var signature: String = JSON.stringify({
		"cash": int(summary.get("cash", game.state.get("cash", 0))),
		"used": int(summary.get("used", 0)),
		"inbound": int(summary.get("inbound", 0)),
		"available": int(summary.get("available", 0)),
		"reserved": int(summary.get("reserved", 0)),
		"required": int(summary.get("required", 0)),
		"shortage": int(summary.get("shortage", 0)),
		"units": JSON.stringify(_units(game)),
		"cart": review.get("lines", []),
		"ok": bool(review.get("ok", false)),
		"error": str(review.get("error", "")),
		"save_error": _meta(ui, "stock_cart_error", "")
	})
	if str(ui.get_meta("stock_live_signature", "")) == signature: return
	ui.set_meta("stock_live_signature", signature)
	var capacity := int(summary.get("capacity", 0)); var used_after := maxi(0, capacity - int(review.get("free_capacity", capacity)))
	var capacity_label: Variant = ui.modal.find_child("StockCapacity", true, false)
	if capacity_label is Label: capacity_label.text = _copy("stock_capacity", "") % [int(summary.get("used", 0)), capacity]
	var cash_label: Variant = ui.modal.find_child("StockCash", true, false)
	if cash_label is Label: cash_label.text = "¥%d" % int(summary.get("cash", game.state.get("cash", 0)))
	for spec in [["StockAvailable", "v220_stock_available", "available"], ["StockInbound", "v220_stock_inbound", "inbound"], ["StockReserved", "v220_stock_reserved", "reserved"], ["StockRequired", "v220_stock_required", "required"], ["StockShortage", "v220_stock_shortage", "shortage"]]:
		var chip: Variant = ui.modal.find_child(str(spec[0]), true, false)
		if chip is Label: chip.text = _copy(str(spec[1])) + "  %d" % int(summary.get(str(spec[2]), 0))
	for raw in _catalog(game):
		if not raw is Dictionary: continue
		var sku := _sku(raw); var stock := _stock_summary(game, sku)
		var available: Variant = ui.modal.find_child("StockCardAvailable_" + sku, true, false)
		if available is Label: available.text = _copy("v220_stock_available") + "  %d" % int(stock.get("available", 0))
		var flow: Variant = ui.modal.find_child("StockCardFlow_" + sku, true, false)
		if flow is Label: flow.text = "%s %d  /  %s %d  /  %s %d" % [_copy("v220_stock_available"), int(stock.get("available", 0)), _copy("v220_stock_inbound"), int(stock.get("inbound", 0)), _copy("v220_stock_reserved"), int(stock.get("reserved", 0))]
		var on_hand: Variant = ui.modal.find_child("StockCardOnHand_" + sku, true, false)
		if on_hand is Label: on_hand.text = _copy("stock_on_hand", "On hand") + " %d" % _stock_count(game, sku)
	var selected_detail: Variant = ui.modal.find_child("StockSelectedProductFacts", true, false)
	if selected_detail is Label:
		var selected_stock := _stock_summary(game, _meta(ui, "stock_sku", "gateway"))
		selected_detail.text = "%s %d   ·   %s %d   ·   %s %d   ·   %s %d" % [_copy("v220_stock_inbound"), int(selected_stock.get("inbound", 0)), _copy("v220_stock_reserved"), int(selected_stock.get("reserved", 0)), _copy("v220_stock_required"), int(selected_stock.get("required", 0)), _copy("v220_stock_shortage"), int(selected_stock.get("shortage", 0))]
	if _meta(ui, "stock_view", "catalog") == "inventory" and is_instance_valid(ui.modal):
		var selected_serial := _meta(ui, "stock_selected_serial", "")
		var selected_unit: Dictionary = {}
		for raw_unit in _units(game):
			if not raw_unit is Dictionary: continue
			var unit: Dictionary = raw_unit
			var serial := str(unit.get("serial", unit.get("id", "")))
			var model_label: Variant = ui.modal.find_child("StockUnitModel_" + serial, true, false)
			var status_label: Variant = ui.modal.find_child("StockUnitStatus_" + serial, true, false)
			var client_label: Variant = ui.modal.find_child("StockUnitClient_" + serial, true, false)
			var location_label: Variant = ui.modal.find_child("StockUnitLocation_" + serial, true, false)
			if model_label is Label: model_label.text = str(unit.get("model", unit.get("sku", "")))
			if status_label is Label: status_label.text = _state_text(str(unit.get("status", "unknown")))
			if client_label is Label: client_label.text = _assigned_client(game, unit)
			if location_label is Label: location_label.text = _location_text(unit)
			if serial == selected_serial: selected_unit = unit
		if not selected_unit.is_empty():
			var detail_status: Variant = ui.modal.find_child("StockDetailStatus", true, false)
			var detail_location: Variant = ui.modal.find_child("StockDetailLocation", true, false)
			var detail_client: Variant = ui.modal.find_child("StockDetailClient", true, false)
			if detail_status is Label: detail_status.text = _state_text(str(selected_unit.get("status", "unknown")))
			if detail_location is Label: detail_location.text = _location_text(selected_unit)
			if detail_client is Label: detail_client.text = _assigned_client(game, selected_unit)
	var footer: Variant = ui.modal_footer.find_child("StockOrderFooter", true, false) if is_instance_valid(ui.modal_footer) else null
	if footer is Control:
		var total_label: Variant = footer.find_child("StockFooterTotal", true, false); if total_label is Label: total_label.text = _copy("v220_order_total", _copy("stock_total")) + "  ¥%d" % int(review.get("total", 0))
		var cash_after: Variant = footer.find_child("StockCashAfter", true, false); if cash_after is Label: cash_after.text = _copy("v220_after_purchase", "") + "  ¥%d" % int(review.get("cash_after", game.state.get("cash", 0)))
		var capacity_after: Variant = footer.find_child("StockCapacityAfter", true, false); if capacity_after is Label: capacity_after.text = _copy("stock_capacity", "") % [used_after, capacity]
		var reason: Variant = footer.find_child("StockCartDisabledReason", true, false); if reason is Label: reason.text = _footer_reason(ui, review)
		var purchase: Variant = footer.find_child("StockPurchase", true, false); if purchase is Button: purchase.disabled = not bool(review.get("ok", false))

static func _catalog_view(ui, parent: Node, game) -> void:
	var catalog: Array = _catalog(game)
	var selected_sku := _meta(ui, "stock_sku", "")
	var cards := GridContainer.new(); cards.name = "StockProductCards"; cards.columns = 2 if float(ui.root.size.x) >= 1050.0 else 1; cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cards.add_theme_constant_override("h_separation", 10); cards.add_theme_constant_override("v_separation", 4 if float(ui.root.size.x) < 1100.0 else 10); parent.add_child(cards)
	cards.name = "StockProductTable"
	for raw in catalog:
		if raw is Dictionary: _product_card(ui, cards, game, raw, _sku(raw) == selected_sku)
	if not selected_sku.is_empty() and not _product(game, selected_sku).is_empty(): _product_detail(ui, parent, game, selected_sku)
	if catalog.is_empty(): _label(ui, parent, _copy("stock_empty", "No products"), 14, TAB)

static func _product_card(ui, parent: Node, game, item: Dictionary, selected: bool) -> void:
	var sku := _sku(item)
	var card := PanelContainer.new(); card.name = "StockProduct_" + sku; card.custom_minimum_size = Vector2(250, 92); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.add_theme_stylebox_override("panel", M.surface(M.SELECTED if selected else M.PAPER, 10, true)); parent.add_child(card)
	var row := HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("separation", 12); card.add_child(row)
	var image := TextureRect.new(); image.name = "StockProductImage_" + sku; image.texture = _icon(str(item.get("icon", sku))); image.custom_minimum_size = Vector2(80, 80); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; row.add_child(image)
	var details := VBoxContainer.new(); details.size_flags_horizontal = Control.SIZE_EXPAND_FILL; details.size_flags_vertical = Control.SIZE_SHRINK_CENTER; details.add_theme_constant_override("separation", 3); row.add_child(details)
	var title := _button(ui, details, "%s  ·  ¥%d" % [str(item.get("title", sku)), int(item.get("unit_cost", 0))], func(): _set_meta(ui, "stock_sku", sku); ui.open_panel("shop"), "StockProductSelect_" + sku); title.custom_minimum_size.y = 32; title.alignment = HORIZONTAL_ALIGNMENT_LEFT; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; M.button(title, "tab", selected); title.tooltip_text = "%s  ·  %s" % [str(item.get("model", "")), str(item.get("supplier", ""))]
	var stock := _stock_summary(game, sku)
	var available := _label(ui, details, _copy("v220_stock_available") + "  %d" % int(stock.get("available", 0)), 14, M.INK); available.name = "StockCardAvailable_" + sku; available.autowrap_mode = TextServer.AUTOWRAP_OFF
	var controls := VBoxContainer.new(); controls.name = "StockCardControls_" + sku; controls.custom_minimum_size.x = 96; controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER; controls.add_theme_constant_override("separation", 2); row.add_child(controls)
	var quantity_label := _label(ui, controls, _copy("stock_quantity"), 13, M.MUTED); quantity_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; quantity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var cart_quantity := SpinBox.new(); cart_quantity.name = "StockCartQuantity_" + sku; cart_quantity.min_value = 0; cart_quantity.max_value = 3; cart_quantity.step = 1; cart_quantity.value = _cart_quantity(game, sku); cart_quantity.custom_minimum_size = Vector2(88, 34); M.field(cart_quantity); controls.add_child(cart_quantity)
	cart_quantity.value_changed.connect(func(value: float): _set_cart_quantity(ui, game, sku, int(value)))

static func _product_detail(ui, parent: Node, game, sku: String) -> void:
	var stock := _stock_summary(game, sku)
	var detail := _panel(parent, M.PAPER, 10, "StockProductDetail")
	var facts := _label(ui, detail, "%s %d   ·   %s %d   ·   %s %d   ·   %s %d" % [_copy("v220_stock_inbound"), int(stock.get("inbound", 0)), _copy("v220_stock_reserved"), int(stock.get("reserved", 0)), _copy("v220_stock_required"), int(stock.get("required", 0)), _copy("v220_stock_shortage"), int(stock.get("shortage", 0))], 13, M.MUTED); facts.name = "StockSelectedProductFacts"; facts.autowrap_mode = TextServer.AUTOWRAP_OFF

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
	var quantity := SpinBox.new(); quantity.name = "StockQuantity"; quantity.min_value = 0; quantity.max_value = 3; quantity.step = 1; quantity.value = _cart_quantity(game, selected_sku); quantity.custom_minimum_size.x = 76; quantity_column.add_child(quantity)
	var price_column := VBoxContainer.new(); line.add_child(price_column); _label(ui, price_column, _copy("stock_unit_price", "Unit price"), 12, MUTED)
	var unit_cost := int(item.get("unit_cost", 0)); var unit_price := _label(ui, price_column, "¥%d" % unit_cost, 14, INK); unit_price.custom_minimum_size.x = 80; unit_price.size_flags_horizontal = Control.SIZE_SHRINK_END
	var total_column := VBoxContainer.new(); line.add_child(total_column); _label(ui, total_column, _copy("stock_total", "Total"), 12, MUTED)
	var subtotal := _label(ui, total_column, "¥%d" % unit_cost, 14, PURPLE_DARK); subtotal.name = "StockSubtotal"; subtotal.custom_minimum_size.x = 90; subtotal.size_flags_horizontal = Control.SIZE_SHRINK_END
	quantity.value_changed.connect(func(value: float):
		subtotal.text = "¥%d" % (unit_cost * int(value))
		_set_cart_quantity(ui, game, selected_sku, int(value))
	)
	var review := _cart_review(ui, game)
	var total := _label(ui, order, _copy("v220_order_total", _copy("stock_total")) + "  ¥%d  ·  %d %s" % [int(review.get("total", 0)), int(review.get("quantity", 0)), _copy("stock_quantity")], 14, YELLOW)
	total.name = "StockCartTotal"

static func _inventory(ui, parent: Node, game) -> void:
	var search_row := HBoxContainer.new(); search_row.add_theme_constant_override("separation", 8); parent.add_child(search_row)
	var search := LineEdit.new(); search.name = "StockSearchSerial"; search.placeholder_text = _copy("stock_search_serial", "Search serial"); search.text = _meta(ui, "stock_search", ""); search.size_flags_horizontal = Control.SIZE_EXPAND_FILL; M.field(search); search_row.add_child(search)
	var search_action := func(): _set_meta(ui, "stock_search", search.text.strip_edges()); ui.open_panel("shop")
	var search_button := _button(ui, search_row, _copy("os_search", "Search"), search_action, "StockSearchButton"); search_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	search.text_submitted.connect(func(_text: String): search_action.call())
	var filter := OptionButton.new(); filter.name = "StockSkuFilter"; filter.add_item(_copy("stock_all_products", "All products"), 0); filter.set_item_metadata(0, ""); M.field(filter)
	for raw in _catalog(game):
		if raw is Dictionary: filter.add_item(str(raw.get("title", _sku(raw))), filter.item_count); filter.set_item_metadata(filter.item_count - 1, _sku(raw))
	var wanted_filter := _meta(ui, "stock_filter", "")
	for index in range(filter.item_count):
		if str(filter.get_item_metadata(index)) == wanted_filter: filter.select(index); break
	filter.item_selected.connect(func(index: int): _set_meta(ui, "stock_filter", str(filter.get_item_metadata(index))); ui.open_panel("shop")); search_row.add_child(filter)
	var query := _meta(ui, "stock_search", "").to_lower(); var sku_filter := _meta(ui, "stock_filter", ""); var selected_serial := _meta(ui, "stock_selected_serial", "")
	var table := _panel(parent, M.PAPER, 10, "StockUnits"); table.name = "StockUnitTable"
	var grid := GridContainer.new(); grid.columns = 5; grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 8); table.add_child(grid)
	for label_text in [_copy("stock_serial", "Serial"), _copy("stock_model", "Model"), _copy("stock_status", "Status"), _copy("stock_client", "Client"), _copy("stock_location", "Location")]:
		var h := _label(ui, grid, label_text, 12, M.MUTED); h.add_theme_font_override("font", UI.font(700))
	var visible_count := 0
	for raw_unit in _units(game):
		if not raw_unit is Dictionary: continue
		var unit: Dictionary = raw_unit; var serial := str(unit.get("serial", unit.get("id", ""))); var sku := str(unit.get("sku", "gateway"))
		var assigned := _assigned_client(game, unit)
		var searchable := serial + " " + sku + " " + str(unit.get("model", "")) + " " + assigned
		if not query.is_empty() and not searchable.to_lower().contains(query): continue
		if not sku_filter.is_empty() and sku != sku_filter: continue
		visible_count += 1
		var open := _button(ui, grid, serial, func(): _set_meta(ui, "stock_selected_serial", serial); ui.open_panel("shop"), "StockSerial_" + serial); open.alignment = HORIZONTAL_ALIGNMENT_LEFT; open.flat = true; open.add_theme_color_override("font_color", M.ACCENT); open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var model_label := _label(ui, grid, str(unit.get("model", sku)), 13, M.INK); model_label.name = "StockUnitModel_" + serial
		var status_label := _label(ui, grid, _state_text(str(unit.get("status", "unknown"))), 13, M.INK); status_label.name = "StockUnitStatus_" + serial
		var client_label := _label(ui, grid, assigned, 13, M.MUTED); client_label.name = "StockUnitClient_" + serial
		var location_label := _label(ui, grid, _location_text(unit), 13, M.MUTED); location_label.name = "StockUnitLocation_" + serial
	if visible_count == 0: _label(ui, table, _copy("stock_empty" if query.is_empty() and sku_filter.is_empty() else "stock_no_matches", "No matching units"), 14, MUTED)
	if not selected_serial.is_empty():
		for raw_unit in _units(game):
			if raw_unit is Dictionary and str(raw_unit.get("serial", raw_unit.get("id", ""))) == selected_serial: _inventory_detail(ui, parent, game, raw_unit); break

static func _inventory_detail(ui, parent: Node, game, unit: Dictionary) -> void:
	var detail := _panel(parent, M.PAPER, 12, "StockSelectedDetail")
	var title := _label(ui, detail, str(unit.get("serial", "")), 18, M.ACCENT); title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var rows := [[_copy("stock_product", "Product"), str(_product(game, str(unit.get("sku", ""))).get("title", unit.get("model", "")))], [_copy("stock_model", "Model"), str(unit.get("model", ""))], [_copy("stock_status", "Status"), _state_text(str(unit.get("status", "unknown")))], [_copy("stock_location", "Location"), _location_text(unit)], [_copy("stock_client", "Client"), _assigned_client(game, unit)]]
	for pair in rows:
		var row := HBoxContainer.new(); row.custom_minimum_size.y = 30; detail.add_child(row)
		var key := _label(ui, row, str(pair[0]), 12, M.MUTED); key.custom_minimum_size.x = 130; key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var value := _label(ui, row, str(pair[1]), 13, M.INK)
		if str(pair[0]) == _copy("stock_status", "Status"): value.name = "StockDetailStatus"
		elif str(pair[0]) == _copy("stock_location", "Location"): value.name = "StockDetailLocation"
		elif str(pair[0]) == _copy("stock_client", "Client"): value.name = "StockDetailClient"
