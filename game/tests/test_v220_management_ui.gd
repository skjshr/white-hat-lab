extends SceneTree

const COPY = preload("res://scripts/ui_theme.gd")

var ui
var game
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(70.0).timeout.connect(func(): push_error("v220 management UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 5) -> void:
	for _index in count:
		await process_frame

func node(id: String):
	if ui == null or not is_instance_valid(ui.modal): return null
	return ui.modal.find_child(id, true, false)

func check_in_viewport(target: Node, label: String) -> void:
	check(target is Control, label + " exists as control")
	if not target is Control or root == null: return
	var control := target as Control
	var rect := control.get_global_rect()
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	check(control.is_visible_in_tree() and viewport.encloses(rect), label + " is visible in initial viewport")
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			check(ancestor.get_global_rect().encloses(rect), label + " fits clipped ancestor " + ancestor.name)
		ancestor = ancestor.get_parent()

func check_staff_capacity() -> void:
	var capacity: Node = node("OperatingCapacity")
	var staff_title: String = str(COPY.copy("v220_staff_seats"))
	var found := false
	if capacity is Container:
		for item in capacity.get_children():
			if not item is Container: continue
			var labels: Array[Node] = item.find_children("", "Label", true, false)
			if labels.size() < 2: continue
			if str(labels[0].text) != staff_title: continue
			var parts := str(labels[1].text).split("/")
			if parts.size() >= 2:
				found = int(parts[1].strip_edges()) >= 2
			check(found, "company staff capacity denominator is at least two")
			break
	check(found, "company staff capacity metric present")

func press(id: String) -> void:
	var target = node(id)
	check(target is BaseButton and not target.disabled, "button " + id)
	if target is BaseButton and not target.disabled: target.pressed.emit()

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/ui-refinement-20260922/management" if "--refinement-capture" in OS.get_cmdline_user_args() else "res://../artifacts/simulator/v220/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "capture image " + label)
	if image != null and not image.is_empty():
		check(image.save_png(folder.path_join(label + suffix + ".png")) == OK, "capture " + label)

func run() -> void:
	ui = preload("res://scripts/interface.gd").new()
	if ui == null:
		push_error("interface failed to load")
		quit(1)
		return
	root.add_child(ui)
	await frames(3)
	game = ui._game()
	if game == null:
		push_error("game failed to load")
		quit(1)
		return
	game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "isolated QA storage")
	check(ui._new_game(), "new v220 management UI game")
	check(game.choose_strategy("operations") and game.start_free_career(), "operations career")
	game.state.skills = {"operations": 3, "advisory": 3, "response": 3}
	game.state.peak_profit = 1000000
	game.set_settings({"resolution": "960x600" if narrow else "1920x1080", "window_mode": "windowed", "text_scale": 1.3 if narrow else 1.0, "volume": 0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)

	ui.open_panel("sales")
	await frames(8)
	check(node("SalesPricingTab") is BaseButton, "pricing tab")
	press("SalesPricingTab")
	await frames(6)
	for category in ["advisory", "operations", "response"]:
		check(node("PricingRow_" + category) is HBoxContainer, "pricing row " + category)
		check(node("PricingRate_" + category) is SpinBox, "pricing control " + category)
		check_in_viewport(node("PricingRow_" + category), "pricing row " + category)
		check_in_viewport(node("PricingRate_" + category), "pricing rate " + category)
		check_in_viewport(node("PricingApply_" + category), "pricing apply " + category)
	await capture("pricing")
	var advisory_rate = node("PricingRate_advisory")
	if advisory_rate is SpinBox:
		advisory_rate.value = 115
		advisory_rate.value_changed.emit(115.0)
	check(int(ui.pricing_drafts.get("advisory", 0)) == 115, "pricing draft survives view state")
	press("SalesInquiriesTab")
	await frames(6)
	press("SalesPricingTab")
	await frames(6)
	check(node("PricingRate_advisory") is SpinBox and int(node("PricingRate_advisory").value) == 115, "pricing draft survives tab switch")
	var apply_price = node("PricingApply_advisory")
	if apply_price is BaseButton and not apply_price.disabled:
		apply_price.pressed.emit()
		await frames(8)
		check(not ui.pricing_drafts.has("advisory"), "applied policy clears local draft")
		advisory_rate = node("PricingRate_advisory")
		if advisory_rate is SpinBox:
			advisory_rate.get_line_edit().text = "120"
			advisory_rate.apply()
			await frames(2)
			check(not apply_price.disabled, "policy row can be edited after save")
			apply_price.pressed.emit()
			await frames(8)
			check(int(game.pricing_policy().get("advisory", 0)) == 120, "second policy save updates one row")

	press("SalesCatalogTab")
	await frames(6)
	var catalog_prices_checked := 0
	for offer in game.state.offers:
		if str(offer.get("category", "")) != "advisory": continue
		var displayed = node("CatalogPrice_" + str(offer.id).replace("/", "_").replace(" ", "_"))
		if displayed is Label:
			check(displayed.text == "¥%d" % int(game.contract_quote(offer).quoted_fee), "catalog follows saved category pricing")
			catalog_prices_checked += 1
	check(catalog_prices_checked > 0, "catalog pricing checked on real offers")
	press("SalesInquiriesTab")
	await frames(6)
	var selected_offer: Dictionary = {}
	for offer in game.state.get("offers", []):
		if offer is Dictionary and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)):
			selected_offer = offer
			break
	if not selected_offer.is_empty():
		var offer_id := str(selected_offer.get("id", "")).replace("/", "_").replace(" ", "_")
		press("SalesOffer_" + offer_id)
		await frames(6)
		check(node("OfferPrice") is SpinBox, "quote price control")
		check_in_viewport(node("OfferPrice"), "quote price control")
		check_in_viewport(node("ContractPlan"), "quote plan control")
		check_in_viewport(node("AcceptContract"), "quote submit control")
		check_in_viewport(node("QuotePreview"), "quoted profit")
		var stock: Dictionary = game.offer_operations_preview(selected_offer)
		if int(stock.get("required", 0)) > 0 or int(stock.get("shortage", 0)) > 0:
			check_in_viewport(node("OperationsStockSummary"), "required stock preparation summary")
		else:
			check(not node("OperationsStockSummary").is_visible_in_tree(), "irrelevant zero stock summary omitted")
			var conditions = node("QuoteConditions")
			check(conditions is BaseButton, "quote conditions remain accessible")
			if conditions is BaseButton:
				conditions.button_pressed = true
				await frames(3)
				check(node("OperationsStaffing").is_visible_in_tree(), "capacity and team remain available in conditions")
				conditions.button_pressed = false
		var price = node("OfferPrice")
		if price is SpinBox:
			price.value = price.value + 5
			price.value_changed.emit(price.value)
			check(ui.sales_quote_drafts.has(str(selected_offer.id)), "quote draft held in interface")
		if game.has_method("offer_operations_preview"):
			check(node("OperationsPreview") is PanelContainer, "operations preview")
			check(node("OperationsProcurement") is BaseButton, "procurement route")
			check(node("OperationsStaffing") is BaseButton, "staffing route")
		await capture("quote-operations")
		ui._open_quote_procurement(str(selected_offer.id))
		await frames(6)
		if ui.current_kind == "shop":
			check(node("BackToQuote") is BaseButton, "procurement route keeps quote return")
			if node("BackToQuote") is BaseButton: press("BackToQuote")
			await frames(6)
			check(node("OfferPrice") is SpinBox, "quote returns after procurement")

	ui.open_panel("company")
	await frames(8)
	if game.has_method("company_operating_summary"):
		check(node("OperatingDesk") is VBoxContainer, "operating desk")
		check(node("OperatingMetrics") is HBoxContainer, "operating metrics")
		check(node("OperatingCapacity") is HBoxContainer, "operating capacity")
		check(node("OperatingAttention") is VBoxContainer, "operating attention")
		check(node("CompanyViews") is HBoxContainer, "company responsibilities have separate views")
		check(node("OperatingDeskActions") == null, "duplicate global navigation removed")
		check_staff_capacity()
		await capture("company-empty")
		game.state.delivery_orders = [{"id":"qa-receiving", "status":"ready"}]
		game.changed.emit()
		await frames(10)
		var live_receiving_row = node("OperatingAttention_1")
		if live_receiving_row == null: live_receiving_row = node("OperatingAttention_0")
		check(live_receiving_row is HBoxContainer, "company desk refreshes receiving attention live")
		await capture("company-attention")
		var receiving_row = node("OperatingAttention_1")
		if receiving_row == null: receiving_row = node("OperatingAttention_0")
		if receiving_row is HBoxContainer:
			for child in receiving_row.get_children():
				if child is BaseButton:
					(child as BaseButton).pressed.emit()
					break
			await frames(6)
			check(ui.current_kind == "shop" and str(ui.get_meta("stock_view", "")) == "inventory", "receiving attention opens inventory")
		ui.open_panel("company")
		await frames(6)
		game.state.delivery_orders = []
		game.state.maintenance_jobs = [{"id":"qa-maintenance", "client":"qa", "status":"pending", "day":int(game.state.day)}]
		ui.open_panel("company")
		await frames(6)
		var maintenance_row = node("OperatingAttention_1")
		if maintenance_row == null: maintenance_row = node("OperatingAttention_0")
		check(maintenance_row is HBoxContainer, "pending maintenance has an action")
		if maintenance_row is HBoxContainer:
			for child in maintenance_row.get_children():
				if child is BaseButton:
					(child as BaseButton).pressed.emit()
					break
			await frames(8)
			check(ui.current_kind == "board" and ui.operations_choices.get("view","") == "maintenance", "maintenance attention opens maintenance work queue")
		ui.open_panel("company")
	check(ui.modal_body != null and ui.modal_body.get_child_count() > 1, "company details remain available")
	var profile: Dictionary = game.profile()
	profile.company = "株式会社".repeat(10)
	check(game.set_profile(profile), "maximum company name saved")
	ui.open_panel("company")
	await frames(8)
	check_in_viewport(node("ManagementClose"), "long profile close action")
	check_in_viewport(node("ManagementTabs"), "long profile navigation")
	await capture("company-long-profile")
	print("V220_MANAGEMENT_UI failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
