extends SceneTree

var ui
var game
var failures: Array[String] = []
var narrow := false
var capture_enabled := false

func _init() -> void:
	narrow = "--narrow" in OS.get_cmdline_user_args()
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	create_timer(60.0).timeout.connect(func(): push_error("v2.2 procurement UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 6) -> void:
	for _index in count: await process_frame

func control(id: String):
	return ui.modal.find_child(id, true, false) if is_instance_valid(ui.modal) else null

func press(id: String) -> void:
	var target: Variant = control(id)
	check(target is BaseButton and not target.disabled, "button " + id)
	if target is BaseButton and not target.disabled: target.pressed.emit()

func quantity(id: String, value: int) -> void:
	var target: Variant = control(id)
	check(target is SpinBox, "quantity " + id)
	if target is SpinBox:
		target.value = value
		target.value_changed.emit(float(value))

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(3)
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/ui-refinement-20260922/procurement")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	check(root.get_texture().get_image().save_png(folder.path_join(label + suffix + ".png")) == OK, "capture " + label)

func assert_visible_inside(id: String, container: Control) -> void:
	var node: Variant = control(id)
	check(node is Control and container.get_global_rect().encloses(node.get_global_rect()), id + " fits viewport")

func run() -> void:
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(4)
	game = ui._game()
	game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "isolated QA save")
	check(ui._new_game(), "new game")
	check(game.choose_strategy("operations") and game.start_free_career(), "career fixture")
	game.state.cash = 16000
	game.save_game()
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.shop_view = "stock"
	ui.open_panel("shop")
	await frames(8)
	check(control("StockAppBar") != null and control("StockProductTable") != null, "stock catalog shell")
	check(control("StockFlowSummary") == null and control("StockCash") == null and control("StockCapacity") == null, "shell owns cash and capacity")
	check(control("StockSelectedProductFacts") == null, "product detail waits for selection")
	for sku in ["gateway", "backup_appliance"]:
		var card: Variant = control("StockProduct_" + sku)
		var card_quantity: Variant = control("StockCartQuantity_" + sku)
		check(card is Control and card_quantity is Control, "catalog row " + sku)
		if card is Control and card_quantity is Control: check(card.get_global_rect().encloses(card_quantity.get_global_rect()), "quantity " + sku + " stays inside row")
		var image: Variant = control("StockProductImage_" + sku)
		check(image is TextureRect and image.custom_minimum_size.x == 80.0 and image.custom_minimum_size.y == 80.0, "catalog image " + sku)
	check(control("StockCardAvailable_gateway") is Label and control("StockCardAvailable_backup_appliance") is Label, "catalog availability rows")
	press("StockProductSelect_backup_appliance")
	await frames(6)
	check(control("StockSelectedProductFacts") is Label, "selected product detail")
	check(control("StockOrderFooter") != null and control("StockPurchase") is Button, "sticky cart footer")
	var footer: Control = control("StockOrderFooter")
	assert_visible_inside("StockPurchase", footer)
	quantity("StockCartQuantity_backup_appliance", 2)
	quantity("StockCartQuantity_gateway", 1)
	var gateway_quantity: Variant = control("StockCartQuantity_gateway")
	await frames(8)
	var review: Dictionary = game.customer_cart_review() if game.has_method("customer_cart_review") else {}
	check(bool(review.get("ok", false)) and int(review.get("quantity", 0)) == 3, "mixed cart review")
	check(int(review.get("total", 0)) > 0 and int(review.get("cash_after", -1)) == 16000-int(review.get("total", 0)), "cart total and cash-after")
	check(not str(control("StockCashAfter").text).is_empty() and not str(control("StockCapacityAfter").text).is_empty(), "footer cash/capacity")
	check(str(control("StockCapacityAfter").text).contains("3 / 6"), "footer shows post-cart used capacity")
	check(control("StockCartQuantity_gateway") == gateway_quantity, "live refresh keeps quantity control instance")
	game.state.cash = 0; game.changed.emit(); await frames(4)
	check(control("StockCartQuantity_gateway") == gateway_quantity and control("StockPurchase") is Button and control("StockPurchase").disabled, "cash change updates footer without rebuilding")
	game.state.cash = 16000; game.changed.emit(); await frames(4)
	await capture("mixed-cart")
	press("StockPurchase")
	await frames(10)
	check(game.customer_stock_units().size() == 3, "atomic mixed purchase")
	check(int(game.state.cash) == 16000-int(review.get("total", 0)), "atomic cash deduction")
	check(str(ui.get_meta("stock_view", "")) == "inventory", "purchase opens serial inventory")
	var inventory: Control = control("StockUnitTable")
	check(inventory != null, "serial inventory table")
	check(control("StockOrderFooter") == null, "inventory hides cart footer")
	var serial := str(game.customer_stock_units()[0].get("serial", ""))
	var first_serial: Variant = control("StockSerial_" + serial)
	check(first_serial is Button, "first serial row visible")
	if first_serial is Control and inventory is Control: check(inventory.get_global_rect().encloses(first_serial.get_global_rect()), "first serial row fits viewport")
	for field in ["StockUnitModel_", "StockUnitStatus_", "StockUnitClient_", "StockUnitLocation_"]:
		var row_value: Variant = control(field + serial)
		check(row_value is Label and not str(row_value.text).is_empty(), "initial inventory " + field)
	await capture("serial-inventory")
	var search: Variant = control("StockSearchSerial")
	if search is LineEdit:
		search.text = serial; search.text_submitted.emit(serial)
	await frames(6)
	check(control("StockSerial_" + serial) is Button, "serial search result")
	press("StockSerial_" + serial)
	await frames(6)
	check(control("StockSelectedDetail") != null, "serial selection retained")
	var before_status := str(control("StockUnitStatus_" + serial).text)
	var before_location := str(control("StockUnitLocation_" + serial).text)
	var stock_state: Variant = game.state.get("customer_stock", {})
	var stored_units: Variant = stock_state.get("units", []) if stock_state is Dictionary else []
	if stored_units is Array and not stored_units.is_empty() and stored_units[0] is Dictionary:
		stored_units[0]["status"] = "stored"
		stored_units[0]["shelf_slot"] = 2
		stored_units[0]["contract_id"] = "live-client-qa"
	game.changed.emit()
	await frames(6)
	check(str(control("StockUnitStatus_" + serial).text) != before_status, "live inventory status refresh")
	check(str(control("StockUnitLocation_" + serial).text) != before_location, "live inventory location refresh")
	check(str(control("StockUnitClient_" + serial).text) == "live-client-qa", "live inventory client refresh")
	check(str(control("StockSearchSerial").text) == serial, "inventory search preserved during refresh")
	check(str(control("StockDetailStatus").text) == str(control("StockUnitStatus_" + serial).text), "selected status detail refresh")
	check(str(control("StockDetailLocation").text) == str(control("StockUnitLocation_" + serial).text), "selected location detail refresh")
	check(str(control("StockDetailClient").text) == str(control("StockUnitClient_" + serial).text), "selected client detail refresh")
	game.state.cash = 0
	ui.set_meta("stock_view", "catalog")
	ui.open_panel("shop")
	await frames(6)
	quantity("StockCartQuantity_gateway", 3)
	await frames(6)
	check(not str(control("StockCartDisabledReason").text).is_empty(), "insufficient cash reason")
	await capture("insufficient-cash")
	for failure in failures: push_error(failure)
	print("V220_PROCUREMENT_UI failures=", failures.size(), " narrow=", narrow)
	quit(0 if failures.is_empty() else 1)
