extends SceneTree

var ui
var game
var failures: Array[String] = []
var narrow := false
var capture_dir := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--narrow": narrow = true
	create_timer(45.0).timeout.connect(func(): push_error("procurement UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func frames(count: int = 5) -> void:
	for _index in count: await process_frame

func control(id: String):
	return ui.find_child(id, true, false) if ui != null else null

func serial_button(serial: String):
	return ui.find_child("StockSerial_" + serial, true, false) if ui != null else null

func capture(name: String) -> void:
	await frames(8)
	var image: Image = get_root().get_texture().get_image()
	check(image.save_png(capture_dir.path_join(name + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture "+name)

func reveal(id: String) -> void:
	var target = control(id)
	if target is Control and is_instance_valid(ui.modal_scroll):
		ui.modal_scroll.ensure_control_visible(target)
		await frames(3)

func open_stock() -> void:
	ui.shop_view = "stock"
	ui.open_panel("shop")
	await frames(8)

func run() -> void:
	ui = load("res://scripts/interface.gd").new()
	get_root().add_child(ui)
	await frames(4)
	game = ui._game()
	game.set_process(false)
	check(game.save_path.begins_with("user://qa-"), "isolated QA save")
	check(ui._new_game(), "new game")
	check(game.choose_strategy("operations"), "strategy")
	check(game.start_free_career(), "career")
	game.state.cash = 16000
	check(game.save_game(), "fixture save")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	get_root().size = Vector2i(960,600) if narrow else Vector2i(1280,720)
	capture_dir = ProjectSettings.globalize_path("res://../artifacts/simulator/procurement/ui")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await open_stock()
	check(control("StockAppBar") != null, "stock appbar")
	check(control("StockProductImage") is TextureRect, "product image")
	check(control("StockQuantity") is SpinBox, "quantity control")
	check(control("StockPurchase") is Button, "purchase control")
	check(control("StockInventoryTab") is Button, "serial inventory tab")
	check(float(control("StockAppBar").size.y) <= 90.0, "compact appbar height")
	check(float(control("StockCapacity").size.y) <= 32.0, "capacity stays horizontal")
	check(float(control("StockProductTable").size.x) >= 360.0, "product table readable width")
	check(control("StockProduct_gateway") != null and control("StockProduct_backup_appliance") != null, "gateway and backup products")
	var backup_select: Button = control("StockSelect_backup_appliance")
	check(backup_select is Button, "backup product selector")
	if backup_select is Button: backup_select.pressed.emit()
	await frames(8)
	check(control("StockPurchaseOrder") != null, "backup order line")
	var quantity: SpinBox = control("StockQuantity")
	quantity.value = 1
	quantity.value_changed.emit(1.0)
	check(int(quantity.value) == 1, "backup quantity one")
	await reveal("StockPurchaseOrder")
	await capture("catalog-backup-orderline")
	await capture("catalog-backup-selected")
	var purchase: Button = control("StockPurchase")
	check(not purchase.disabled, "backup purchase enabled")
	if not purchase.disabled: purchase.pressed.emit()
	await frames(10)
	check(game.customer_stock_units().size() == 1, "backup unit purchased")
	check(str(game.customer_stock_units()[0].sku) == "backup_appliance", "backup SKU persisted")
	check(int(game.state.cash) == 11200, "backup purchase cash deducted")
	var backup_serial := str(game.customer_stock_units()[0].serial)
	check(serial_button(backup_serial) is Button, "backup serial row")
	var catalog_tab: Button = control("StockCatalogTab")
	check(catalog_tab is Button, "catalog tab")
	if catalog_tab is Button: catalog_tab.pressed.emit()
	await frames(8)
	var gateway_select: Button = control("StockSelect_gateway")
	check(gateway_select is Button, "gateway product selector")
	if gateway_select is Button: gateway_select.pressed.emit()
	await frames(8)
	quantity = control("StockQuantity")
	quantity.value = 1
	quantity.value_changed.emit(1.0)
	purchase = control("StockPurchase")
	check(purchase is Button and not purchase.disabled, "gateway purchase enabled")
	if purchase is Button and not purchase.disabled: purchase.pressed.emit()
	await frames(10)
	check(game.customer_stock_units().size() == 2, "mixed stock units purchased")
	check(int(game.state.cash) == 8000, "mixed purchase cash deducted")
	check(control("StockUnitTable") != null, "serial table")
	var gateway_serial := str(game.customer_stock_units()[1].serial)
	check(serial_button(gateway_serial) is Button, "gateway serial row")
	await capture("mixed-inventory")
	var filter: OptionButton = control("StockSkuFilter")
	check(filter is OptionButton, "SKU filter")
	if filter is OptionButton:
		for index in range(filter.item_count):
			if str(filter.get_item_metadata(index)) == "backup_appliance": filter.select(index); filter.item_selected.emit(index); break
	await frames(8)
	check(serial_button(backup_serial) is Button and serial_button(gateway_serial) == null, "backup filter hides gateway")
	var search: LineEdit = control("StockSearchSerial")
	check(search is LineEdit, "serial search")
	if search is LineEdit:
		search.text = backup_serial
		var search_button: Button = control("StockSearchButton")
		if search_button is Button: search_button.pressed.emit()
	await frames(8)
	check(serial_button(backup_serial) is Button and serial_button(gateway_serial) == null, "serial search keeps exact unit")
	var detail_button: Button = serial_button(backup_serial)
	if detail_button is Button: detail_button.pressed.emit()
	await frames(8)
	check(control("StockSelectedDetail") != null, "selected serial details")
	await reveal("StockSelectedDetail")
	await capture("filtered-backup-detail-bottom")
	await capture("filtered-backup-detail")
	game.state.cash = 0
	var catalog_again: Button = control("StockCatalogTab")
	if catalog_again is Button: catalog_again.pressed.emit()
	await frames(8)
	var backup_again: Button = control("StockSelect_backup_appliance")
	if backup_again is Button: backup_again.pressed.emit()
	await frames(8)
	quantity = control("StockQuantity")
	quantity.value = 2
	quantity.value_changed.emit(2.0)
	purchase = control("StockPurchase")
	check(purchase is Button and not purchase.disabled, "insufficient cash remains actionable")
	if purchase is Button and not purchase.disabled: purchase.pressed.emit()
	await frames(6)
	check(int((control("StockQuantity") as SpinBox).value) == 2, "failed purchase preserves quantity")
	check(not str((control("StockPurchaseResult") as Label).text).is_empty(), "failed purchase shows API error")
	await reveal("StockPurchaseResult")
	await capture("insufficient-cash-message")
	await capture("insufficient-cash")
	for failure in failures: push_error(failure)
	print("PROCUREMENT_UI failures=", failures.size(), " narrow=", narrow)
	quit(0 if failures.is_empty() else 1)
