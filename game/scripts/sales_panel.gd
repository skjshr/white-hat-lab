## Sales pipeline view.  The game owns all offer, quote, and contract state;
## this module only projects that state into a compact CRM board.
class_name SalesPanel
extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")
const THEME = preload("res://scripts/game_theme.gd")
const SALES_CHART = preload("res://scripts/sales_chart.gd")

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
const PAPER := CANVAS
const COLUMN := CARD_FRAME
const INK := TEXT
const MUTED := Color("c6e8ef")
const BORDER := TAB_BAR

static var _mail_entries: Dictionary = {}

static func build(ui) -> void:
	var g = ui._game()
	if g == null:
		return
	var host: VBoxContainer = ui.modal_body
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	var frame := Control.new()
	frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	host.add_child(frame)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",4)
	frame.add_child(body)
	frame.resized.connect(func(): _fit_content(frame,body))
	body.minimum_size_changed.connect(func(): _fit_content(frame,body))
	var toolbar := HFlowContainer.new()
	toolbar.name = "SalesToolbar"
	toolbar.add_theme_constant_override("h_separation", 8);toolbar.add_theme_constant_override("v_separation", 8)
	body.add_child(toolbar)
	var view := str(ui.get("sales_view"))
	if view == "active":
		view = "inquiries"
		ui.set("sales_view", "inquiries")
		ui.set("sales_stage", "accepted")
	if view not in ["inquiries", "summary", "catalog"]: view = "inquiries"
	var inquiries := _tab(ui, "SalesInquiriesTab", "board_list", "inquiries", "inbox")
	var summary := _tab_text(ui, "SalesSummaryTab", "概要", "summary", "chart")
	var catalog := _tab(ui, "SalesCatalogTab", "market_catalog", "catalog", "grid")
	for tab in [inquiries, summary, catalog]: toolbar.add_child(tab)
	var selected_tab: Button = {"inquiries": inquiries, "summary": summary, "catalog": catalog}[view]
	selected_tab.button_pressed = true
	if view in ["inquiries", "catalog"]:
		_add_filters(ui,g,body)
	match view:
		"catalog": _render_catalog(ui,g,body)
		"summary": _render_summary(ui,g,body)
		_: _render_board(ui,g,body)
	_scale_text(body, float(ui.text_scale))
	_fit_content(frame,body)

static func _fit_content(frame: Control, content: VBoxContainer) -> void:
	content.size.x=minf(1180,frame.size.x)
	content.position.x=maxf(0,roundf((frame.size.x-content.size.x)*0.5))
	var height: float=content.get_combined_minimum_size().y
	content.size.y=height
	frame.custom_minimum_size.y=height

static func _add_filters(ui, g, body: VBoxContainer) -> void:
	var filters:=HFlowContainer.new();filters.name="SalesFilters";filters.add_theme_constant_override("h_separation",8);filters.add_theme_constant_override("v_separation",6);body.add_child(filters)
	var search := LineEdit.new()
	search.name = "SalesSearch"
	search.custom_minimum_size.x = 180
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text = str(ui.get("sales_search"))
	search.placeholder_text = UI.copy("market_search")
	search.clear_button_enabled = true
	_apply_text(search, 14, CARD)
	search.add_theme_stylebox_override("normal", UI.style(THEME.WHITE, UI.MUTED, 6, 5, 1))
	search.add_theme_stylebox_override("focus", UI.style(THEME.WHITE, TAB_BAR, 6, 5, 2))
	search.add_theme_color_override("font_color", CARD)
	search.add_theme_color_override("font_placeholder_color", UI.MUTED)
	search.text_changed.connect(func(value: String): ui.set("sales_search", value))
	search.text_submitted.connect(func(value: String): ui.set("sales_search", value); ui._refresh_sales_panel(true))
	filters.add_child(search)
	var category_filter:=OptionButton.new();category_filter.name="SalesCategoryFilter";category_filter.custom_minimum_size.x=150;category_filter.tooltip_text=UI.copy("board_category");_add_filter_items(category_filter, [["all","board_all_categories"],["advisory","market_advisory"],["operations","market_operations"],["response","market_response"]], str(ui.get("board_filter")), ui, "board_filter");filters.add_child(category_filter)
	var count := _visible_count(g, ui)
	var count_text := UI.copy("market_count")
	if not count_text.is_empty(): count_text = count_text % count
	else: count_text = str(count)
	var count_label := _label(count_text, 13, UI.MUTED)
	count_label.name = "SalesCount"
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if str(ui.get("sales_view")) != "catalog":
		var stage_filter:=OptionButton.new();stage_filter.name="SalesStageFilter";stage_filter.custom_minimum_size.x=160;stage_filter.tooltip_text=UI.copy("board_stage");_add_filter_items(stage_filter, [["all","board_all_stages"],["new","market_new_today"],["draft","market_quoted"],["requote","market_requote"],["accepted","market_accepted"]], ui.get("sales_stage"), ui, "sales_stage");filters.add_child(stage_filter)

	filters.add_child(count_label)

static func _add_filter_items(control: OptionButton, specs: Array, selected: Variant, ui, state_key: String) -> void:
	var selected_value:=str(selected);if selected_value.is_empty():selected_value=str(specs[0][0])
	for spec in specs:
		control.add_item(UI.copy(str(spec[1])))
		var index:=control.item_count-1;control.set_item_metadata(index,str(spec[0]))
		if str(spec[0])==selected_value:control.select(index)
	control.add_theme_font_size_override("font_size",14);control.add_theme_color_override("font_color",CARD);control.add_theme_color_override("font_hover_color",CARD);control.add_theme_color_override("font_pressed_color",THEME.WHITE)
	control.add_theme_stylebox_override("normal",UI.style(THEME.WHITE,UI.MUTED,6,5,1));control.add_theme_stylebox_override("hover",UI.style(THEME.WHITE,TAB_BAR,6,5,1));control.add_theme_stylebox_override("pressed",UI.style(TAB,TAB_BAR,6,5,1));control.add_theme_stylebox_override("focus",UI.style(THEME.WHITE,TAB_BAR,6,5,2))
	control.item_selected.connect(func(index:int):ui.set(state_key,str(control.get_item_metadata(index)));ui.set("sales_expanded_id","");ui._refresh_sales_panel(true))

static func _scale_text(node: Node, scale: float) -> void:
	if node is Control and node.has_theme_font_size_override("font_size"):
		var size: int = node.get_theme_font_size("font_size")
		node.set_meta("base_font_size", size)
		node.add_theme_font_size_override("font_size", roundi(size * scale))
	for child in node.get_children(): _scale_text(child, scale)

static func _tab(ui, node_name: String, copy_key: String, view: String, icon_id: String = "") -> Button:
	return _tab_text(ui,node_name,UI.copy(copy_key),view,icon_id)

static func _tab_text(ui, node_name: String, value: String, view: String, icon_id: String = "") -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = value
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(118, 38)
	if not icon_id.is_empty():
		button.icon = UI.symbol(icon_id)
		button.add_theme_constant_override("icon_max_width", 18)
	button.pressed.connect(func(): ui.set("sales_view", view); ui.set("sales_expanded_id", ""); ui._refresh_sales_panel(true))
	_apply_control(button, 14)
	button.add_theme_stylebox_override("normal", UI.style(THEME.WHITE, UI.MUTED, 6, 6, 1))
	button.add_theme_stylebox_override("hover", UI.style(THEME.WHITE, TAB_BAR, 6, 6, 1))
	button.add_theme_stylebox_override("pressed", UI.style(TAB, TAB_BAR, 6, 6, 1))
	button.add_theme_stylebox_override("focus", UI.style(THEME.WHITE, TAB_BAR, 6, 6, 2))
	button.add_theme_color_override("font_color", CARD)
	button.add_theme_color_override("font_hover_color", CARD)
	button.add_theme_color_override("font_pressed_color", THEME.WHITE)
	return button

static func _render_board(ui, g, body: VBoxContainer) -> void:
	var lanes := _board_items(g, ui)
	var stage:=str(ui.get("sales_stage"));if stage.is_empty():stage="all"
	var board := VBoxContainer.new()
	board.name = "SalesBoard"
	board.add_theme_constant_override("separation", 4)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(board)
	var specs: Array = [
		["new", "market_new_today"],
		["draft", "market_quoted"],
		["requote", "market_requote"],
		["accepted", "market_accepted"]
	]
	for spec in specs:
		var lane:=_lane(ui,g,str(spec[0]),str(spec[1]),Array(lanes.get(str(spec[0]),[])))
		lane.visible=stage=="all" or stage==str(spec[0])
		board.add_child(lane)
	if _visible_count(g,ui) == 0:
		board.add_child(_label(UI.copy("market_no_matching"),14,UI.MUTED))

static func _stage_tab(ui, stage: String, value: String, selected: bool) -> Button:
	var button:=Button.new();button.name="SalesStage_"+stage;button.text=value;button.toggle_mode=true;button.button_pressed=selected;button.custom_minimum_size=Vector2(122,34);_apply_control(button,13)
	button.pressed.connect(func():ui.set("sales_stage",stage);ui.set("sales_expanded_id","");ui._refresh_sales_panel(true))
	return button

static func _lane(ui, g, lane_id: String, title_key: String, items: Array) -> VBoxContainer:
	var lane := VBoxContainer.new()
	lane.name = "SalesLane_" + lane_id
	lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cards:=VBoxContainer.new();cards.name="SalesCards_"+lane_id;cards.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cards.add_theme_constant_override("separation",4);lane.add_child(cards)
	if items.is_empty():
		lane.visible=false
		return lane
	for item in items:
		cards.add_child(_offer_card(ui, g, lane_id, item))
	return lane

static func _offer_card(ui, g, lane_id: String, item: Dictionary) -> PanelContainer:
	var id:=str(item.get("id",""))
	var amount:=int(item.get("fee",item.get("reward",0)))
	if item.has("offer") and lane_id!="accepted":
		var quote: Dictionary=g.contract_quote(item.offer)
		amount=int(quote.reference_fee if lane_id=="new" else quote.quoted_fee)
	var contact := _contact_for(item)
	var card:=PanelContainer.new();card.name="SalesCard_"+_node_id(id);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.add_theme_stylebox_override("panel",UI.style(Color.TRANSPARENT,Color.TRANSPARENT,0,0,0))
	var header:=Button.new();header.name="SalesOffer_"+_node_id(id);header.custom_minimum_size.y=60;header.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_list_row_style(header)
	card.add_child(header)
	var row:=HBoxContainer.new();row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);row.offset_left=10;row.offset_right=-10;row.offset_top=4;row.offset_bottom=-4;row.add_theme_constant_override("separation",12);header.add_child(row)
	var identity:=VBoxContainer.new();identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL;identity.add_theme_constant_override("separation",0);row.add_child(identity)
	var title:=_label(str(item.get("title","")),15,CARD);title.add_theme_font_override("font",UI.font(700));title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.max_lines_visible=2;title.tooltip_text=title.text;identity.add_child(title)
	var client_text := str(contact.get("company",item.get("client","")))
	var client:=_label(client_text,12,UI.MUTED);client.autowrap_mode=TextServer.AUTOWRAP_OFF;client.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;client.tooltip_text=client_text;identity.add_child(client)
	var value:=VBoxContainer.new();value.custom_minimum_size.x=150;value.add_theme_constant_override("separation",0);row.add_child(value)
	var price:=_label("¥%d" % amount,17,CARD);price.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;price.add_theme_font_override("font",UI.font(700));value.add_child(price)
	var state_key: String = str({"new": "market_new_today", "draft": "market_quoted", "requote": "market_requote", "accepted": "market_accepted"}.get(lane_id, "market_detail"))
	if lane_id == "accepted" and bool(item.get("completed", false)):
		state_key = "market_delivered"
	var state:=_label(UI.copy(state_key),12,UI.MUTED);state.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.add_child(state)
	row.minimum_size_changed.connect(func(): header.custom_minimum_size.y=maxf(60,row.get_combined_minimum_size().y+8))
	header.tooltip_text=title.text + " / " + client_text
	_ignore_mouse(row)
	if lane_id=="accepted":header.pressed.connect(func():ui._operations_open(id,-1,"receipt" if bool(item.get("completed",false)) else "browser"))
	else:header.pressed.connect(func():ui._select_contract(id))
	return card

static func _fact(host: Node, icon_id: String, value: String, color: Color) -> void:
	var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",UI.style(ACTION,BORDER,7,4,1));host.add_child(panel)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",5);panel.add_child(row)
	var icon:=TextureRect.new();icon.texture=UI.symbol(icon_id);icon.custom_minimum_size=Vector2(17,17);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.modulate=color;row.add_child(icon)
	var text:=_label(value,12,color);text.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(text)

static func _render_summary(ui, g, body: VBoxContainer) -> void:
	var lanes:=_board_items(g,ui)
	var metrics:=HFlowContainer.new();metrics.name="SalesSummaryMetrics";metrics.add_theme_constant_override("h_separation",8);metrics.add_theme_constant_override("v_separation",8);body.add_child(metrics)
	_metric(metrics,"新規",Array(lanes.new).size(),YELLOW,"inbox")
	_metric(metrics,"見積中",Array(lanes.draft).size()+Array(lanes.requote).size(),TAB,"money")
	_metric(metrics,"受注",Array(lanes.accepted).size(),SUCCESS,"check")
	var mix_panel:=PanelContainer.new();mix_panel.name="SalesStageDonut";mix_panel.custom_minimum_size=Vector2(242,92);mix_panel.add_theme_stylebox_override("panel",UI.style(CARD,BORDER,10,8,1));metrics.add_child(mix_panel)
	var mix_row:=HBoxContainer.new();mix_row.add_theme_constant_override("separation",10);mix_panel.add_child(mix_row)
	var donut:=SALES_CHART.new();donut.name="SalesStageDonutGraphic";donut.custom_minimum_size=Vector2(72,72);donut.configure("donut",[Array(lanes.new).size(),Array(lanes.draft).size()+Array(lanes.requote).size(),Array(lanes.accepted).size()],[YELLOW,TAB,SUCCESS]);mix_row.add_child(donut)
	var mix_copy:=VBoxContainer.new();mix_copy.add_theme_constant_override("separation",2);mix_copy.size_flags_vertical=Control.SIZE_SHRINK_CENTER;mix_row.add_child(mix_copy)
	var mix_title:=_label("案件構成",13,TEXT);mix_title.add_theme_font_override("font",UI.font(700));mix_copy.add_child(mix_title)
	mix_copy.add_child(_label("新規  見積  受注",11,MUTED))
	mix_copy.add_child(_label("%d件" % _visible_count(g,ui),20,TEXT))
	var pipeline:=_chart_panel(body,"案件の流れ","SalesPipelineChart")
	_chart_bar(pipeline,UI.copy("market_new_today"),Array(lanes.new).size(),maxi(1,_visible_count(g,ui)),YELLOW)
	_chart_bar(pipeline,"見積中",Array(lanes.draft).size()+Array(lanes.requote).size(),maxi(1,_visible_count(g,ui)),TAB)
	_chart_bar(pipeline,UI.copy("market_accepted"),Array(lanes.accepted).size(),maxi(1,_visible_count(g,ui)),SUCCESS)
	var demand:=_chart_panel(body,"分野別の相談","SalesDemandChart")
	var market: Dictionary=g.market_summary()
	for category in ["advisory","operations","response"]:
		var item: Dictionary=market.get(category,{})
		_chart_bar(demand,UI.copy("market_"+category),int(item.get("available",0)),4,TAB)
	var distribution:=_chart_panel(body,"分野の比率","SalesCategoryMixChart")
	var counts:=_category_counts(g,ui)
	var stacked:=SALES_CHART.new();stacked.name="SalesCategoryMixGraphic";stacked.custom_minimum_size=Vector2(0,30);stacked.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stacked.configure("stacked",[counts.advisory,counts.operations,counts.response],[_category_color("advisory"),_category_color("operations"),_category_color("response")]);distribution.add_child(stacked)
	var legend:=HBoxContainer.new();legend.add_theme_constant_override("separation",18);distribution.add_child(legend)
	for category in ["advisory","operations","response"]:
		var label:=_label("●  %s %d" % [_category_name(category),int(counts.get(category,0))],11,_category_color(category));legend.add_child(label)

static func _metric(host: Node, title: String, value: int, color: Color, icon_id: String) -> void:
	var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(190,72);panel.add_theme_stylebox_override("panel",UI.style(CARD,BORDER,10,8,1));host.add_child(panel)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);panel.add_child(row)
	var icon:=TextureRect.new();icon.texture=UI.symbol(icon_id);icon.custom_minimum_size=Vector2(32,32);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.modulate=color;row.add_child(icon)
	var stack:=VBoxContainer.new();row.add_child(stack);stack.add_child(_label(title,12,MUTED));var number:=_label(str(value),26,color);number.add_theme_font_override("font",UI.font(700));stack.add_child(number)

static func _chart_panel(host: Node, title: String, name: String) -> VBoxContainer:
	var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",UI.style(COLUMN,BORDER,10,10,1));host.add_child(panel)
	var stack:=VBoxContainer.new();stack.name=name;stack.add_theme_constant_override("separation",8);panel.add_child(stack);var heading:=_label(title,16,TEXT);heading.add_theme_font_override("font",UI.font(700));stack.add_child(heading);return stack

static func _chart_bar(host: Node, title: String, value: int, maximum: int, color: Color) -> void:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);host.add_child(row)
	var label:=_label(title,12,TEXT);label.custom_minimum_size.x=130;label.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(label)
	var bar:=ProgressBar.new();bar.custom_minimum_size=Vector2(0,14);bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.max_value=maxi(1,maximum);bar.value=value;bar.show_percentage=false;bar.add_theme_stylebox_override("fill",UI.style(color,Color.TRANSPARENT,4,0,0));row.add_child(bar)
	var count:=_label(str(value),13,TEXT);count.custom_minimum_size.x=28;count.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;row.add_child(count)

static func _render_catalog(ui, g, body: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.name = "SalesCatalogList"
	list.add_theme_constant_override("separation", 4)
	body.add_child(list)
	var offers: Array = _filtered_offers(g, ui, true)
	if offers.is_empty():
		list.add_child(_label(UI.copy("market_no_matching"), 14, TAB))
		return
	for offer in offers:
		list.add_child(_catalog_row(ui, g, offer))

static func _catalog_row(ui, g, offer: Dictionary) -> Button:
	var id := str(offer.get("id", ""))
	var row := Button.new()
	row.name = "SalesCatalog_" + _node_id(id)
	var quote: Dictionary = g.contract_quote(offer)
	var available := bool(offer.get("unlocked", false)) and bool(offer.get("market_available", true))
	var state_text := UI.copy("market_catalog_available") if available else UI.copy("market_not_requested") if bool(offer.get("unlocked",false)) else UI.copy("market_catalog_locked")
	var contract: Dictionary=g.state.get("contract_contexts",{}).get(id,{})
	if not contract.is_empty(): state_text=UI.copy("market_delivered" if bool(contract.get("completed",false)) else "market_accepted")
	row.custom_minimum_size = Vector2(0, 72 * float(ui.text_scale))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_control(row, 14)
	_list_row_style(row)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);margin.offset_left=12;margin.offset_right=-12;margin.offset_top=8;margin.offset_bottom=-8;row.add_child(margin)
	var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",12);margin.add_child(columns)
	var contact:=_contact_for(offer)
	var details:=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",4);columns.add_child(details)
	var title:=_label(str(offer.get("title","")),15,CARD);title.add_theme_font_override("font",UI.font(700));title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.max_lines_visible=2;title.tooltip_text=str(offer.get("title",""));details.add_child(title)
	var client_text:=str(contact.get("company",offer.get("client","")));var client:=_label(client_text,12,UI.MUTED);client.clip_text=true;client.tooltip_text=client_text;details.add_child(client)
	var price:=_label("¥%d" % int(quote.reference_fee),16,CARD);price.custom_minimum_size.x=124;price.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;price.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;columns.add_child(price)
	var state:=_label(state_text,12,UI.MUTED if not available else CARD);state.custom_minimum_size.x=160;state.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;state.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;columns.add_child(state)
	columns.minimum_size_changed.connect(func(): row.custom_minimum_size.y=maxf(68,columns.get_combined_minimum_size().y+16))
	row.tooltip_text=title.text + " / " + client_text
	_ignore_mouse(margin)
	row.pressed.connect(func(): ui._select_contract(id))
	return row

static func _list_row_style(button: Button) -> void:
	var normal := UI.style(THEME.WHITE, UI.BORDER, 8, 6, 0)
	normal.border_width_left=0; normal.border_width_right=0; normal.border_width_top=0
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",UI.style(CANVAS,TAB,8,6,0))
	button.add_theme_stylebox_override("pressed",UI.style(FILTER,TAB,8,6,0))
	var focus := UI.style(Color.TRANSPARENT,TAB,8,6,0); focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus",focus)
	for color in ["font_color","font_hover_color","font_pressed_color"]: button.add_theme_color_override(color,CARD)

static func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)

static func _board_items(g, ui, ignore_category: bool = false) -> Dictionary:
	var lanes: Dictionary = {"new": [], "draft": [], "requote": [], "accepted": []}
	var queue_by_id: Dictionary = {}
	if g.has_method("contract_queue"):
		for queued in g.contract_queue():
			if queued is Dictionary:
				queue_by_id[str(queued.get("id", ""))] = queued
	var offer_by_id: Dictionary = {}
	var offers: Array = g.state.get("offers", [])
	for offer in offers:
		if offer is Dictionary: offer_by_id[str(offer.get("id", ""))] = offer
	var accepted_ids: Dictionary = {}
	for id in queue_by_id:
		var queued: Dictionary = queue_by_id[id]
		var matched = offer_by_id.get(str(id), {})
		if matched is Dictionary and not matched.is_empty():
			queued["offer"] = matched
			queued["service"] = matched.get("service", "")
			queued["category"] = matched.get("category", "")
		elif g.state.get("contract_contexts", {}).has(str(id)):
			var context = g.state.contract_contexts.get(str(id), {})
			var contract = context.get("contract", {}) if context is Dictionary else {}
			if contract is Dictionary:
				queued["service"] = contract.get("service", "")
				queued["category"] = contract.get("category", "")
		accepted_ids[str(id)] = true
		if _matches(ui, queued, ignore_category): lanes.accepted.append(queued)
	var latest_decisions: Dictionary = {}
	for decision in g.state.get("quote_decisions", []):
		if decision is Dictionary: latest_decisions[str(decision.get("offer_id", ""))] = decision
	var quotes: Dictionary = g.state.get("offer_quotes", {})
	for offer in offers:
		if not offer is Dictionary: continue
		var id := str(offer.get("id", ""))
		if accepted_ids.has(id): continue
		if not _matches(ui, offer, ignore_category): continue
		var latest: Dictionary = latest_decisions.get(id, {})
		var lane := ""
		if str(latest.get("decision", "")) == "declined": lane = "requote"
		elif quotes.has(id): lane = "draft"
		elif bool(offer.get("unlocked", false)) and bool(offer.get("market_available", true)): lane = "new"
		if lane.is_empty(): continue
		var item: Dictionary = offer.duplicate(true)
		item["offer"] = offer
		if lane in ["draft","requote"]:
			var quote: Dictionary = g.contract_quote(offer)
			item["fee"] = int(quote.get("quoted_fee", quote.get("reference_fee", 0)))
		lanes[lane].append(item)
	return lanes

static func _filtered_offers(g, ui, include_all: bool) -> Array:
	var result: Array = []
	for offer in g.state.get("offers", []):
		if not offer is Dictionary: continue
		if not _matches(ui, offer): continue
		if not include_all and not bool(offer.get("market_available", true)): continue
		result.append(offer)
	return result

static func _matches(ui, item: Dictionary, ignore_category: bool = false) -> bool:
	var filter := str(ui.get("board_filter"))
	if filter.is_empty(): filter = "all"
	if not ignore_category and filter != "all" and str(item.get("category", "")) != filter:
		var offer = item.get("offer", {})
		if not offer is Dictionary or str(offer.get("category", "")) != filter: return false
	var query := str(ui.get("sales_search")).strip_edges().to_lower()
	if query.is_empty(): return true
	var haystack := (str(item.get("client", "")) + " " + str(item.get("title", "")) + " " + str(item.get("service", "")) + " " + str(item.get("category", ""))).to_lower()
	return haystack.contains(query)

static func _visible_count(g, ui) -> int:
	if str(ui.get("sales_view")) == "catalog": return _filtered_offers(g, ui, true).size()
	var lanes := _board_items(g, ui)
	var stage:=str(ui.get("sales_stage"));if stage.is_empty():stage="all"
	if stage != "all": return Array(lanes.get(stage,[])).size()
	var total := 0
	for values in lanes.values(): total += Array(values).size()
	return total

static func _category_counts(g, ui) -> Dictionary:
	var result := {"all":0,"advisory":0,"operations":0,"response":0}
	var items: Array = []
	if str(ui.get("sales_view")) == "catalog":
		for offer in g.state.get("offers", []):
			if offer is Dictionary and _matches(ui, offer, true): items.append(offer)
	else:
		var lanes:=_board_items(g,ui,true)
		for lane_items in lanes.values(): items.append_array(Array(lane_items))
	for item in items:
		var category:=_item_category(item)
		if result.has(category): result[category]=int(result[category])+1
		result.all=int(result.all)+1
	return result

static func _item_category(item: Dictionary) -> String:
	var category:=str(item.get("category",""))
	if category.is_empty() and item.get("offer",{}) is Dictionary:
		category=str(Dictionary(item.offer).get("category",""))
	return category if category in ["advisory","operations","response"] else "advisory"

static func _category_name(category: String) -> String:
	return UI.copy("market_"+category) if category in ["advisory","operations","response"] else UI.copy("market_all")

static func _category_color(category: String) -> Color:
	return {"advisory":Color("55d6d2"),"operations":Color("78aef2"),"response":Color("ff7b6e"),"analytics":YELLOW}.get(category,TAB)

static func _contact_for(item: Dictionary) -> Dictionary:
	if _mail_entries.is_empty():
		var file:=FileAccess.open("res://content/mail.json",FileAccess.READ)
		if file:
			var parsed=JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and parsed.get("entries",{}) is Dictionary:_mail_entries=parsed.entries
	var source: Dictionary=item.get("offer",item) if item.get("offer",item) is Dictionary else item
	for key in [str(source.get("id","")),str(item.get("id","")),str(item.get("copy_id",""))]:
		if _mail_entries.get(key,{}) is Dictionary and not Dictionary(_mail_entries.get(key,{})).is_empty():
			var entry: Dictionary=Dictionary(_mail_entries[key])
			return {"sender":str(entry.get("sender","担当者")),"company":str(entry.get("company",item.get("client","")))}
	var fallback: String={"advisory":"佐藤真紀","operations":"山本健","response":"鈴木彩"}.get(_item_category(item),"担当者")
	return {"sender":fallback,"company":str(item.get("client",source.get("client","")))}

static func _node_id(value: String) -> String:
	return value.replace("/", "_").replace(" ", "_")

static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI.font(400))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

static func _apply_text(control: Control, size: int, color: Color) -> void:
	control.add_theme_font_override("font", UI.font(400))
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	control.add_theme_color_override("font_unselected_color", color)
	control.add_theme_color_override("font_placeholder_color", TAB)

static func _apply_control(control: Control, size: int) -> void:
	_apply_text(control, size, INK)
	control.add_theme_stylebox_override("normal", UI.style(FILTER, TAB, 8, 5, 2))
	control.add_theme_stylebox_override("hover", UI.style(TAB_BAR, TAB, 8, 5, 2))
	control.add_theme_stylebox_override("pressed", UI.style(ACTION, TAB_BAR, 8, 5, 2))
	control.add_theme_color_override("font_color", TAB)
	control.add_theme_color_override("font_hover_color", TAB)
	control.add_theme_color_override("font_pressed_color", TEXT)
	control.add_theme_color_override("font_focus_color", TAB)
