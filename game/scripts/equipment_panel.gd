## Internal equipment desk.  Rows choose one product; the detail pane owns the
## explanation and the modal footer owns the only ordering action.
class_name EquipmentPanel
extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")
const EQUIPMENT_ART = preload("res://scripts/equipment_art.gd")
const PROCUREMENT_PANEL = preload("res://scripts/procurement_panel.gd")
const M = preload("res://scripts/management_ui.gd")

const EXPANSION_ID := "office_expansion"

static func build(ui) -> void:
	var game = ui._game()
	if game == null:
		return
	var body: VBoxContainer = ui.modal_body
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	if is_instance_valid(ui.modal_footer):
		ui.modal_footer.alignment = BoxContainer.ALIGNMENT_END
		for child in ui.modal_footer.get_children():
			if child.name.begins_with("Buy_") or child.name in ["BuyOfficeExpansion", "EquipmentReceive", "BackToQuote"]:
				ui.modal_footer.remove_child(child)
				child.queue_free()
	body.add_theme_constant_override("separation", 8)

	if str(ui.shop_view) == "stock":
		PROCUREMENT_PANEL.render(ui, body, game)
		_add_back_to_quote(ui)
		return

	_add_shop_tabs(ui, body)
	_add_delivery_summary(ui, body, game)
	var panes := HBoxContainer.new()
	panes.name = "EquipmentPanes"
	panes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panes.custom_minimum_size.y = 360 if float(ui.text_scale) >= 1.2 else 430
	panes.add_theme_constant_override("separation", 12)
	body.add_child(panes)
	var ui_ref: WeakRef = weakref(ui)
	var body_ref: WeakRef = weakref(body)
	var panes_ref: WeakRef = weakref(panes)
	ui.get_tree().process_frame.connect(func():
		var current_ui = ui_ref.get_ref()
		var current_body = body_ref.get_ref()
		var current_panes = panes_ref.get_ref()
		if is_instance_valid(current_ui) and is_instance_valid(current_body) and is_instance_valid(current_panes):
			_fit_panes(current_ui, current_body, current_panes)
	, CONNECT_ONE_SHOT)

	var left_frame := PanelContainer.new()
	left_frame.name = "EquipmentSelectorPane"
	left_frame.custom_minimum_size.x = 360
	left_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_frame.add_theme_stylebox_override("panel", M.surface(M.PAPER, 10, true))
	panes.add_child(left_frame)
	var left_scroll := ScrollContainer.new()
	left_scroll.name = "EquipmentSelectorScroll"
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_frame.add_child(left_scroll)
	var list := VBoxContainer.new()
	list.name = "EquipmentSelectorList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	left_scroll.add_child(list)

	var items: Array = game.equipment_catalog() if game.has_method("equipment_catalog") else []
	var selected_id := str(ui.get_meta("equipment_selected", "")) if ui.has_meta("equipment_selected") else ""
	if selected_id.is_empty() or (selected_id != EXPANSION_ID and not _contains_item(items, selected_id)):
		selected_id = str(items[0].get("id", "")) if not items.is_empty() else EXPANSION_ID
		ui.set_meta("equipment_selected", selected_id)
	for item in items:
		list.add_child(_selection_row(ui, game, item, selected_id == str(item.get("id", ""))))
	list.add_child(_expansion_selection_row(ui, game, selected_id == EXPANSION_ID))
	var saved_selector_scroll := int(ui.get_meta("equipment_selector_scroll", 0)) if ui.has_meta("equipment_selector_scroll") else 0
	var scroll_ref: WeakRef = weakref(left_scroll)
	left_scroll.get_tree().process_frame.connect(func():
		var current_scroll = scroll_ref.get_ref()
		if is_instance_valid(current_scroll): current_scroll.scroll_vertical = saved_selector_scroll
	, CONNECT_ONE_SHOT)
	var selected_row: Node = list.find_child("EquipmentSelect_" + selected_id, true, false)
	var row_ref: WeakRef = weakref(selected_row)
	left_scroll.get_tree().process_frame.connect(func():
		var current_scroll = scroll_ref.get_ref()
		if not is_instance_valid(current_scroll) or not current_scroll.is_inside_tree(): return
		current_scroll.get_tree().process_frame.connect(func():
			var final_scroll = scroll_ref.get_ref()
			var final_row = row_ref.get_ref()
			if is_instance_valid(final_scroll) and is_instance_valid(final_row) and final_row is Control and final_scroll.is_ancestor_of(final_row):
				final_scroll.ensure_control_visible(final_row)
		, CONNECT_ONE_SHOT)
	, CONNECT_ONE_SHOT)

	var detail_frame := PanelContainer.new()
	detail_frame.name = "EquipmentDetailPane"
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_frame.add_theme_stylebox_override("panel", M.surface(M.PAPER, 16, true))
	panes.add_child(detail_frame)
	var detail := VBoxContainer.new()
	detail.name = "EquipmentDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	detail_frame.add_child(detail)
	if selected_id == EXPANSION_ID:
		_render_expansion(ui, game, detail)
	else:
		var item := _item_by_id(items, selected_id)
		if item.is_empty() and not items.is_empty(): item = items[0]
		_render_item(ui, game, detail, item)
	_scale_text(body, float(ui.text_scale))
	_add_back_to_quote(ui)

static func _add_back_to_quote(ui) -> void:
	if str(ui.board_selected_id).is_empty() or not is_instance_valid(ui.modal_footer): return
	var back_to_quote := _button(ui, ui.modal_footer, "← " + UI.copy("ops_sales"), func(): ui._return_to_quote(), "BackToQuote")
	back_to_quote.custom_minimum_size.x = 150
	ui.modal_footer.move_child(back_to_quote, 0)

static func _add_shop_tabs(ui, body: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "ShopTabs"
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	var equipment_tab := _button(ui, tabs, UI.copy("stock_equipment_tab"), func(): ui.shop_view = "equipment"; ui.open_panel("shop"), "EquipmentTab")
	equipment_tab.toggle_mode = true
	equipment_tab.button_pressed = true
	M.button(equipment_tab, "tab", true)
	var stock_tab := _button(ui, tabs, UI.copy("stock_tab"), func(): ui.shop_view = "stock"; ui.open_panel("shop"), "StockTab")
	stock_tab.toggle_mode = true
	M.button(stock_tab, "tab", false)

static func _add_delivery_summary(ui, body: VBoxContainer, game) -> void:
	var orders: Array = game.state.get("delivery_orders", []) if game.state.get("delivery_orders", []) is Array else []
	var installed := 0
	var counts := {"queued": 0, "ready": 0, "carried": 0, "placing": 0}
	for order in orders:
		var status := str(order.get("status", ""))
		if status == "installed": installed += 1
		elif counts.has(status): counts[status] = int(counts[status]) + 1
	var summary := VBoxContainer.new()
	summary.name = "EquipmentDeliverySummary"
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 3)
	body.add_child(summary)
	var primary := HBoxContainer.new()
	primary.add_theme_constant_override("separation", 14)
	summary.add_child(primary)
	var installed_label := _add_label(primary, "%s %d / %d" % [UI.copy("delivery_installed"), installed, game.equipment_catalog().size()], 14, M.INK)
	installed_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	installed_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var destination_label := _add_label(primary, UI.copy("delivery_destination"), 14, M.MUTED)
	destination_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	destination_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var status_text := PackedStringArray()
	for status in ["queued", "ready", "carried", "placing"]:
		if int(counts[status]) > 0:
			status_text.append("%s %d" % [UI.copy("delivery_waiting" if status == "queued" else "delivery_" + status), int(counts[status])])
	if not status_text.is_empty():
		var status_label := _add_label(summary, "　".join(status_text), 14, M.MUTED)
		status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		status_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

static func _selection_row(ui, game, item: Dictionary, selected: bool) -> Button:
	var id := str(item.get("id", ""))
	var row := Button.new()
	row.name = "EquipmentSelect_" + id
	row.custom_minimum_size.y = 64
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	M.button(row, "secondary", selected)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -8
	line.offset_top = 5
	line.offset_bottom = -5
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(54, 50)
	icon.texture = EQUIPMENT_ART.icon(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	line.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	line.add_child(copy)
	var title := _add_label(copy, str(item.get("title", "")), 15, M.INK)
	title.add_theme_font_override("font", UI.font(700))
	var price := int(game.equipment_price(id)) if game.has_method("equipment_price") else int(item.get("price", 0))
	_add_label(copy, "¥%d" % price, 13, M.MUTED)
	var state := _equipment_state(game, id)
	if not state.is_empty(): _add_label(copy, state, 12, M.MUTED)
	_ignore_mouse(line)
	row.pressed.connect(func():
		var scroll = ui.modal.find_child("EquipmentSelectorScroll", true, false)
		if scroll is ScrollContainer: ui.set_meta("equipment_selector_scroll", scroll.scroll_vertical)
		ui.set_meta("equipment_selected", id)
		build(ui)
	)
	return row

static func _expansion_selection_row(ui, game, selected: bool) -> Button:
	var row := Button.new()
	row.name = "EquipmentSelect_" + EXPANSION_ID
	row.custom_minimum_size.y = 64
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	M.button(row, "secondary", selected)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -8
	line.offset_top = 5
	line.offset_bottom = -5
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(54, 50)
	icon.texture = EQUIPMENT_ART.icon("annexdesk_a")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	line.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	line.add_child(copy)
	var title := _add_label(copy, UI.copy("expansion_title"), 15, M.INK)
	title.add_theme_font_override("font", UI.font(700))
	var expansion: Dictionary = game.office_expansion_status() if game.has_method("office_expansion_status") else {}
	var price := int(expansion.get("price", expansion.get("cost", 28000)))
	_add_label(copy, "¥%d" % price, 13, M.MUTED)
	_ignore_mouse(line)
	row.pressed.connect(func():
		var scroll = ui.modal.find_child("EquipmentSelectorScroll", true, false)
		if scroll is ScrollContainer: ui.set_meta("equipment_selector_scroll", scroll.scroll_vertical)
		ui.set_meta("equipment_selected", EXPANSION_ID)
		build(ui)
	)
	return row

static func _render_item(ui, game, host: VBoxContainer, item: Dictionary) -> void:
	var id := str(item.get("id", ""))
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 16)
	host.add_child(hero)
	var image := PanelContainer.new()
	image.custom_minimum_size = Vector2(230, 178)
	image.add_theme_stylebox_override("panel", M.surface(M.CANVAS, 8, false))
	hero.add_child(image)
	var art := TextureRect.new()
	art.texture = EQUIPMENT_ART.icon(id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(220, 168)
	image.add_child(art)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 5)
	hero.add_child(info)
	var title := _add_label(info, str(item.get("title", "")), 22, M.INK)
	title.add_theme_font_override("font", UI.font(700))
	var model := str(item.get("model", ""))
	if not model.is_empty(): _add_label(info, model, 14, M.MUTED)
	_add_label(info, _equipment_state(game, id), 14, M.ACCENT if id in game.state.equipment else M.MUTED)
	var price := int(game.equipment_price(id)) if game.has_method("equipment_price") else int(item.get("price", 0))
	_add_label(info, "¥%d" % price, 20, M.INK).name = "EquipmentPrice"
	var catalog_price := int(item.get("price", 0))
	if id in ["backup", "monitor"] and catalog_price > price and price >= 0:
		var discount := roundi(100.0 * float(catalog_price - price) / float(catalog_price))
		_add_label(info, UI.copy("equipment_operations_discount") % [catalog_price, price, discount], 13, M.MUTED).name = "EquipmentDiscount"
	host.add_child(M.rule())
	_add_label(host, str(item.get("effect", item.get("description", ""))), 16, M.INK).name = "EquipmentEffect"
	var physical := str(item.get("physical", ""))
	if not physical.is_empty(): _add_label(host, physical, 14, M.MUTED)
	var order: Dictionary = game.delivery_for(id) if game.has_method("delivery_for") else {}
	if str(order.get("status", "")) == "ready": _ready_context(ui, host)
	_add_footer_action(ui, game, id, item, price)

static func _render_expansion(ui, game, host: VBoxContainer) -> void:
	var expansion: Dictionary = game.office_expansion_status() if game.has_method("office_expansion_status") else {}
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 16)
	host.add_child(hero)
	var image := PanelContainer.new()
	image.custom_minimum_size = Vector2(230, 178)
	image.add_theme_stylebox_override("panel", M.surface(M.CANVAS, 8, false))
	hero.add_child(image)
	var art := TextureRect.new()
	art.texture = EQUIPMENT_ART.icon("annexdesk_a")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(220, 168)
	image.add_child(art)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	hero.add_child(info)
	var title := _add_label(info, UI.copy("expansion_title"), 22, M.INK)
	title.add_theme_font_override("font", UI.font(700))
	_add_label(info, UI.copy("expansion_desk_effect"), 15, M.INK)
	var status := str(expansion.get("status", "locked"))
	if status == "ordered":
		_add_label(info, UI.copy("expansion_available_day") % int(expansion.get("available_day", 0)), 14, M.MUTED)
	elif status == "open":
		var added := 0
		for id in ["annexdesk_a", "annexdesk_b"]:
			if id in game.state.equipment: added += 1
		_add_label(info, UI.copy("expansion_added_seats") % added, 14, M.MUTED)
	var price := int(expansion.get("price", expansion.get("cost", 28000)))
	_add_label(info, "¥%d" % price, 20, M.INK)
	host.add_child(M.rule())
	_add_label(host, UI.copy("expansion_desk_location"), 15, M.MUTED)
	var reason := str(game.office_expansion_reason()) if game.has_method("office_expansion_reason") else ""
	if not reason.is_empty(): _add_label(host, reason, 14, M.DANGER if status == "locked" else M.MUTED)
	_add_footer_expansion(ui, game, expansion, status)

static func _ready_context(ui, host: VBoxContainer) -> void:
	var context := PanelContainer.new()
	context.name = "EquipmentReadyContext"
	context.add_theme_stylebox_override("panel", M.surface(M.SELECTED, 10, true))
	host.add_child(context)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	context.add_child(row)
	_add_label(row, UI.copy("delivery_ready"), 14, M.INK)
	var receive := Button.new()
	receive.name = "EquipmentReceive"
	receive.text = UI.copy("delivery_destination")
	M.button(receive, "quiet")
	receive.pressed.connect(func(): ui.close_panel())
	row.add_child(receive)

static func _add_footer_action(ui, game, id: String, item: Dictionary, price: int) -> void:
	if not is_instance_valid(ui.modal_footer): return
	var order: Dictionary = game.delivery_for(id) if game.has_method("delivery_for") else {}
	var delivery_status := str(order.get("status", ""))
	var owned: bool = id in game.state.equipment
	var unavailable := str(game.equipment_unavailable_reason(id)) if game.has_method("equipment_unavailable_reason") else ""
	var action := Button.new()
	action.name = "Buy_" + id
	action.custom_minimum_size.x = 170
	action.add_theme_font_size_override("font_size", roundi(14.0 * float(ui.text_scale)))
	var delivery_copy: String = str({"queued":"delivery_waiting", "ready":"delivery_ready", "carried":"delivery_carried", "placing":"delivery_placing"}.get(delivery_status, "delivery_waiting"))
	action.text = UI.copy("delivery_installed") if owned else UI.copy(delivery_copy) if not delivery_status.is_empty() else UI.copy("delivery_order")
	action.tooltip_text = unavailable
	action.disabled = owned or not delivery_status.is_empty() or int(game.state.cash) < price or not unavailable.is_empty()
	M.button(action, "primary")
	action.pressed.connect(func(): ui._buy(id))
	ui.modal_footer.add_child(action)
	_right_align_footer_action(ui, action)

static func _add_footer_expansion(ui, game, expansion: Dictionary, status: String) -> void:
	if not is_instance_valid(ui.modal_footer): return
	var reason := str(game.office_expansion_reason()) if game.has_method("office_expansion_reason") else ""
	var action := Button.new()
	action.name = "BuyOfficeExpansion"
	action.add_theme_font_size_override("font_size", roundi(14.0 * float(ui.text_scale)))
	action.text = UI.copy("expansion_buy") if status == "locked" else UI.copy("expansion_" + status)
	action.tooltip_text = reason
	action.disabled = status != "locked" or not reason.is_empty()
	M.button(action, "primary")
	action.pressed.connect(func():
		if game.buy_office_expansion(): ui.open_panel("shop")
	)
	ui.modal_footer.add_child(action)
	_right_align_footer_action(ui, action)

static func _right_align_footer_action(ui, action: Button) -> void:
	if not is_instance_valid(ui) or not is_instance_valid(ui.modal_footer): return
	var footer_ref: WeakRef = weakref(ui.modal_footer)
	var action_ref: WeakRef = weakref(action)
	ui.get_tree().process_frame.connect(func():
		var current_footer = footer_ref.get_ref()
		var current_action = action_ref.get_ref()
		if not is_instance_valid(current_footer) or not is_instance_valid(current_action) or current_action.get_parent() != current_footer: return
		var close: Node = current_footer.find_child("CloseButton", true, false)
		if close is Control:
			current_footer.move_child(current_action, close.get_index())
	, CONNECT_ONE_SHOT)

static func _equipment_state(game, id: String) -> String:
	if id in game.state.equipment: return "（%s）" % UI.copy("delivery_installed")
	var order: Dictionary = game.delivery_for(id) if game.has_method("delivery_for") else {}
	var status := str(order.get("status", ""))
	if status == "queued": return "（%s）" % UI.copy("delivery_waiting")
	if status == "ready": return "（%s）" % UI.copy("delivery_ready")
	if status == "carried": return "（%s）" % UI.copy("delivery_carried")
	if status == "placing": return "（%s）" % UI.copy("delivery_placing")
	return ""

static func _contains_item(items: Array, id: String) -> bool:
	for item in items:
		if str(item.get("id", "")) == id: return true
	return false

static func _item_by_id(items: Array, id: String) -> Dictionary:
	for item in items:
		if str(item.get("id", "")) == id: return item
	return {}

static func _add_label(host: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI.font(500))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(label)
	return label

static func _button(ui, host: Node, text: String, action: Callable, node_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.name = node_name
	button.custom_minimum_size.y = 36
	button.add_theme_font_override("font", UI.font(500))
	button.add_theme_font_size_override("font_size", roundi(14.0 * float(ui.text_scale)))
	button.pressed.connect(action)
	M.button(button, "secondary")
	host.add_child(button)
	return button

static func _fit_panes(ui, body: VBoxContainer, panes: HBoxContainer) -> void:
	if not is_instance_valid(ui.modal_scroll) or not is_instance_valid(panes): return
	var preceding := 0.0
	for child in body.get_children():
		if child == panes: break
		preceding += child.get_combined_minimum_size().y
	preceding += float(body.get_theme_constant("separation")) * 2.0
	var available: float = ui.modal_scroll.size.y - preceding
	if available > 0.0:
		panes.custom_minimum_size.y = clampf(available, 280.0, 430.0)

static func _scale_text(node: Node, scale: float) -> void:
	if node is Control and node.has_theme_font_size_override("font_size"):
		var base_size: int
		if node.has_meta("equipment_base_font_size"):
			base_size = int(node.get_meta("equipment_base_font_size"))
		else:
			base_size = node.get_theme_font_size("font_size")
			node.set_meta("equipment_base_font_size", base_size)
		node.add_theme_font_size_override("font_size", roundi(float(base_size) * scale))
	for child in node.get_children(): _scale_text(child, scale)

static func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)
