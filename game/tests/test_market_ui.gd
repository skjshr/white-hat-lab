extends SceneTree

const COPY = preload("res://scripts/ui_theme.gd")

var ui
var game
var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func(): push_error("market UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func node(id: String):
	if ui == null or not is_instance_valid(ui.modal):
		return null
	return ui.modal.find_child(id, true, false)

func press(id: String) -> void:
	var target = node(id)
	check(target is BaseButton and not target.disabled, "button " + id)
	if target is BaseButton and not target.disabled:
		target.pressed.emit()

func frames(count: int = 5) -> void:
	for _index in count:
		await process_frame

func capture(label: String) -> void:
	if not capture_enabled:
		return
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/market/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	check(root.get_texture().get_image().save_png(folder.path_join(label + suffix + ".png")) == OK, "capture " + label)

func available_offers() -> Array:
	return game.state.offers.filter(func(item): return item is Dictionary and bool(item.get("unlocked", false)) and bool(item.get("market_available", false)))

func click_offer(id: String) -> void:
	var node_id := str(id).replace("/", "_").replace(" ", "_")
	press("SalesOffer_" + node_id)
	await frames()

func click_catalog(id: String) -> void:
	press("SalesCatalog_" + str(id).replace("/", "_").replace(" ", "_"))
	await frames()

func filter_stage(value: String, picker_name := "SalesStageFilter") -> void:
	var picker = node(picker_name)
	check(picker is OptionButton, "stage picker exists")
	if not picker is OptionButton: return
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == value:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	check(false, "stage option " + value)

func quote_price(value: int) -> void:
	var price = node("OfferPrice")
	check(price is SpinBox, "offer price control")
	if price is SpinBox:
		price.get_line_edit().text = str(value)
		price.get_line_edit().text_changed.emit(str(value))

func run() -> void:
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(2)
	game = ui._game()
	game.set_process(false)
	check(not COPY.copy("market_inquiries").is_empty(), "Gemini market copy loaded")
	check(not COPY.copy("market_new_today").is_empty() and not COPY.copy("market_count").is_empty(), "market lane/count labels loaded")
	if not game.save_path.begins_with("user://qa-") or not game.settings_path.begins_with("user://qa-"):
		push_error("Refusing market UI test without isolated QA storage")
		quit(2)
		return
	ui._new_game()
	check(game.choose_strategy("advisory"), "advisory strategy")
	# Direct QA progression fixture: unlock catalog candidates through skills and
	# company experience; credit and rewards remain production-derived.
	game.state.skills = {"operations": 3, "advisory": 3, "response": 3}
	game.state.peak_profit = 1000000
	check(game.start_free_career(), "start career market")
	if "--professional" in OS.get_cmdline_user_args():
		await professional_ui()
		return
	var offers: Array = available_offers()
	check(offers.size() >= 4, "at least four real market inquiries")
	if offers.size() < 4:
		quit(1)
		return
	var draft_offer: Dictionary = offers[0]
	var requote_offer: Dictionary = offers[1]
	var accepted_offer: Dictionary = offers[2]
	var remaining_offer: Dictionary = offers[3]
	var nonlead_offer: Dictionary = {}
	for item in game.state.offers:
		if item is Dictionary and bool(item.get("unlocked", false)) and not bool(item.get("market_available", false)) and str(item.get("id", "")) not in [str(draft_offer.id), str(requote_offer.id), str(accepted_offer.id)]:
			nonlead_offer = item
			break
	check(not nonlead_offer.is_empty(), "catalog contains an unlocked non-lead offer")

	game.set_settings({"resolution": "960x600" if narrow else "1920x1080", "window_mode": "windowed", "text_scale": 1.3, "volume": 0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	ui.open_panel("sales")
	await frames(8)
	check(ui.modal_body.find_child("SalesInquiriesTab", true, false) is BaseButton, "inquiries tab")
	check(ui.modal_body.find_child("SalesActiveTab", true, false) == null, "duplicate active contracts tab removed")
	check(ui.modal_body.find_child("SalesSummaryTab", true, false) is BaseButton, "summary tab")
	check(node("SalesCategoryFilter") is OptionButton, "compact category filter")
	check(node("SalesStageFilter") is OptionButton, "compact stage filter")
	check(ui.modal_body.find_child("SalesLane_new", true, false) != null, "new lane")
	check(ui.modal_body.find_child("SalesLane_draft", true, false) != null, "draft lane")
	check(ui.modal_body.find_child("SalesLane_requote", true, false) != null, "requote lane")
	check(ui.modal_body.find_child("SalesLane_accepted", true, false) != null, "accepted lane")
	var sales_modal_id: int=ui.modal.get_instance_id()
	filter_stage("new")
	await frames(4)
	check(ui.modal.get_instance_id()==sales_modal_id,"stage switch keeps the mounted sales modal")
	filter_stage("all")
	await frames(4)

	filter_stage(str(draft_offer.category), "SalesCategoryFilter")
	await frames(4)
	for offer in offers:
		var row = node("SalesOffer_" + str(offer.id))
		check((row != null) == (str(offer.category) == str(draft_offer.category)), "category matches actual offer " + str(offer.id))
	filter_stage("all", "SalesCategoryFilter")
	await frames(4)

	# New inquiry -> real quote detail -> saved quote draft.
	await click_offer(str(draft_offer.id))
	check(node("OfferPrice") is SpinBox, "new inquiry opens quote detail")
	var initial_quote: Dictionary = game.contract_quote(draft_offer)
	quote_price(int(initial_quote.quoted_fee) + 7)
	var plan_control = node("ContractPlan")
	if plan_control is OptionButton and plan_control.item_count > 1:
		plan_control.select(1); plan_control.item_selected.emit(1)
		await frames(5)
		check(roundi(node("OfferPrice").value) == int(initial_quote.quoted_fee) + 7, "typed quote survives plan change")
		plan_control = node("ContractPlan")
		plan_control.select(0); plan_control.item_selected.emit(0)
		await frames(5)
	check(ui.modal_footer.get_global_rect().encloses(node("AcceptContract").get_global_rect()), "quote action stays visible outside scrolling content")
	await capture("market-detail")
	press("SaveQuoteDraft")
	await frames(8)
	check(game.state.offer_quotes.has(str(draft_offer.id)), "quote draft persisted")
	check(node("SalesLane_draft").find_child("SalesOffer_" + str(draft_offer.id), true, false) != null, "draft card enters draft lane")

	filter_stage("draft")
	await frames(4)
	check(node("SalesOffer_" + str(draft_offer.id)).is_visible_in_tree(), "draft filter retains quoted offer")
	check(not node("SalesOffer_" + str(requote_offer.id)).is_visible_in_tree(), "draft filter hides new offer")
	check(node("SalesCount").text == COPY.copy("market_count") % 1, "single count follows stage filter")
	filter_stage("all")
	await frames(4)

	# A second inquiry receives an over-budget quote and remains available for re-quote.
	await click_offer(str(requote_offer.id))
	var quote: Dictionary = game.contract_quote(requote_offer)
	quote_price(int(quote.budget_limit) + 1)
	press("AcceptContract")
	await frames(8)
	check(not game.state.accepted, "over-budget quote does not accept")
	check(not game.state.quote_decisions.is_empty() and str(game.state.quote_decisions[-1].get("offer_id", "")) == str(requote_offer.id) and str(game.state.quote_decisions[-1].get("decision", "")) == "declined", "over-budget quote records real decline")
	ui.board_selected_id = ""
	ui.open_panel("sales")
	await frames(8)
	check(node("SalesLane_requote").find_child("SalesOffer_" + str(requote_offer.id), true, false) != null, "declined card enters re-quote lane")

	# An affordable inquiry is accepted through the existing quote callback.
	await click_offer(str(accepted_offer.id))
	var accepted_quote: Dictionary = game.contract_quote(accepted_offer)
	check(bool(accepted_quote.affordable), "third inquiry has affordable real quote")
	quote_price(int(accepted_quote.quoted_fee))
	press("AcceptContract")
	await frames(10)
	check(game.state.accepted and str(game.state.current_contract_id) == str(accepted_offer.id), "affordable quote accepts the selected contract")
	ui.board_selected_id = ""
	ui.open_panel("sales")
	await frames(8)
	check(node("SalesLane_accepted").find_child("SalesOffer_" + str(accepted_offer.id), true, false) != null, "accepted card enters accepted lane")
	check(node("SalesLane_new").find_child("SalesOffer_" + str(remaining_offer.id), true, false) != null, "unmodified inquiry remains new")
	check(node("SalesCards_new") is VBoxContainer,"new cards use a vertical list")
	check(node("SalesCards_accepted") is VBoxContainer,"accepted cards use a vertical list")
	check(node("SalesAvatar_"+str(remaining_offer.id)) == null,"decorative portrait removed")
	check(node("SalesPictogram_"+str(remaining_offer.id)) == null,"duplicate category pictogram removed")
	if narrow:
		check(node("SalesBoardScroll") == null, "narrow board has no horizontal lane scroller")
		var board: Control=node("SalesBoard") as Control
		check(board!=null and board.size.x<=ui.modal_scroll.size.x+2.0,"narrow board fits the modal width")
		var first_card: BaseButton=node("SalesOffer_"+str(remaining_offer.id)) as BaseButton
		check(first_card!=null and first_card.custom_minimum_size.y<=78.0,"narrow card header stays compact")
	# Compact board exposes actionable rows immediately, without an accordion.
	ui.modal_scroll.scroll_vertical = 0
	await frames(6)
	var visible_rows := 0
	var viewport_rect: Rect2 = ui.modal_scroll.get_global_rect()
	for button in ui.modal_body.find_children("SalesOffer_*", "Button", true, false):
		if button.is_visible_in_tree() and viewport_rect.encloses(button.get_global_rect()): visible_rows += 1
	check(visible_rows >= 3, "at least three complete rows visible without scrolling")
	await capture("market-board")

	# A single accepted-row click opens the actual workspace.
	press("SalesOffer_" + str(accepted_offer.id))
	await frames(10)
	check(str(game.state.current_contract_id) == str(accepted_offer.id) and ui.current_kind == "terminal", "accepted card opens its contract workspace")
	ui.open_panel("sales")
	await frames(8)

	# Summary replaces dense prose with compact KPIs and two state-derived charts.
	sales_modal_id=ui.modal.get_instance_id()
	press("SalesSummaryTab")
	await frames(8)
	check(ui.modal.get_instance_id()==sales_modal_id,"summary switch does not reopen the modal")
	check(node("SalesSummaryMetrics")!=null,"summary KPI cards")
	check(node("SalesStageDonutGraphic")!=null,"summary uses a stage donut")
	check(node("SalesPipelineChart")!=null,"pipeline chart")
	check(node("SalesDemandChart")!=null,"demand chart")
	check(node("SalesCategoryMixGraphic")!=null,"summary uses a category mix chart")
	check(node("SalesPipelineChart").find_children("*","ProgressBar",true,false).size()>=3,"pipeline chart uses visual bars")
	await capture("market-summary")
	press("SalesInquiriesTab")
	await frames(8)

	# Catalog shows all offers, supports a real search, and exposes locked details without send controls.
	press("SalesCatalogTab")
	await frames(8)
	check(node("SalesCatalog_" + str(nonlead_offer.id)) is BaseButton, "catalog includes non-lead offer")
	var search = node("SalesSearch")
	check(search is LineEdit, "sales search control")
	if search is LineEdit:
		search.text = str(nonlead_offer.title)
		search.text_submitted.emit(search.text)
		await frames(8)
		check(node("SalesCatalog_" + str(nonlead_offer.id)) is BaseButton, "catalog search matches title")
		search = node("SalesSearch")
		search.text = "zzzz-no-market-result"
		search.text_submitted.emit(search.text)
		await frames(8)
		check(node("SalesCatalog_" + str(nonlead_offer.id)) == null, "catalog search removes non-matching rows")
		search = node("SalesSearch")
		search.text = ""
		search.text_submitted.emit("")
		await frames(8)
	await capture("market-catalog")
	await click_catalog(str(nonlead_offer.id))
	await frames(8)
	var draft_button = node("SaveQuoteDraft")
	var send_button = node("AcceptContract")
	check(draft_button is BaseButton and draft_button.disabled, "non-lead catalog detail cannot save a draft")
	check(send_button is BaseButton and send_button.disabled, "non-lead catalog detail cannot send a quote")
	ui.board_selected_id = ""
	ui.set("sales_view", "inquiries")
	ui.open_panel("sales")
	await frames(8)

	for failure in failures:
		push_error(failure)
	print("MARKET_UI failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func professional_ui() -> void:
	game.state.skills = {"advisory":2,"operations":0,"response":0}
	game.state.credit = 10000
	game.state.market_day = -1
	game.state.market_leads = []
	game._make_offers()
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_panel("company")
	await frames(8)
	var next: Node = node("SkillNext_operations")
	check(next is Label and str(next.tooltip_text).contains(COPY.copy("firm_partner_rollout_title")), "company shows cross-skill unlock")
	await capture("firm-skills")
	ui.set("sales_view","catalog")
	ui.open_panel("sales")
	await frames(8)
	var cross: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.case_id) == "firm-partner-rollout": cross = offer; break
	check(not cross.is_empty() and not bool(cross.get("unlocked",true)), "mixed contract starts locked")
	await click_catalog(str(cross.id))
	check(node("AcceptContract") is BaseButton and node("AcceptContract").disabled, "cross-skill quote cannot send")
	check(game.contract_eligibility(cross).has(COPY.copy("firm_skill_requirement") % [COPY.copy("market_operations"),1,0]), "missing secondary skill explained")
	await capture("firm-locked")
	check(game.learn_skill("operations"), "learn supporting skill")
	check("firm-partner-rollout" in game.state.market_leads, "new mixed work offered immediately")
	ui.board_selected_id = ""
	ui.set("sales_view","inquiries")
	ui.open_panel("sales")
	await frames(8)
	await click_offer(str(cross.id))
	check(node("AcceptContract") is BaseButton and not node("AcceptContract").disabled, "mixed work can quote after investment")
	await capture("firm-unlocked")
	for failure in failures: push_error(failure)
	print("PROFESSIONAL_UI failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
