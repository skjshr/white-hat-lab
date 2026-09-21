extends SceneTree

const BILLING = preload("res://scripts/company_billing.gd")
const UI = preload("res://scripts/ui_theme.gd")

var ui
var game
var pc
var failures: Array[String] = []
var profile := str(OS.get_process_id())
var capture_enabled: bool = "--capture" in OS.get_cmdline_user_args()
var narrow: bool = "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(180.0).timeout.connect(func():
		push_error("company billing ui timeout")
		quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 4) -> void:
	for _i in count:
		await process_frame

func find_name(node: Node, prefix: String) -> Node:
	if node == null:
		return null
	for child in node.get_children():
		if str(child.name) == prefix:
			return child
		var nested := find_name(child, prefix)
		if nested != null:
			return nested
	return null

func find_invoice_row(invoice_id: String) -> Node:
	return find_name(pc.widgets.billing.page, "BillingInvoice_" + invoice_id.replace("/", "_"))

func contains_text(node: Node, needle: String) -> bool:
	if node == null:
		return false
	if node is Label and str(node.text).contains(needle):
		return true
	if node is Button and str(node.text).contains(needle):
		return true
	if node is LineEdit and str(node.text).contains(needle):
		return true
	for child in node.get_children():
		if contains_text(child, needle):
			return true
	return false

func click_gui(node: Node) -> void:
	check(node is Control, "control is clickable")
	if not node is Control:
		return
	var control: Control = node
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = control.size * 0.5
	control.gui_input.emit(event)

func press(node: Node, label: String) -> void:
	check(node is BaseButton, label + " control")
	if node is BaseButton:
		(node as BaseButton).pressed.emit()

func capture(label: String) -> void:
	if not capture_enabled:
		return
	await frames(8)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/billing/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	var path := folder.path_join(label + suffix + ".png")
	check(get_root().get_texture().get_image().save_png(path) == OK, "capture " + label)
	print("CAPTURE ", path)

func assert_layout(label: String) -> void:
	var page: Control = pc.widgets.billing.page
	var rect := page.get_global_rect()
	var viewport := Vector2(root.size)
	check(rect.position.x >= -2.0 and rect.end.x <= viewport.x + 2.0, label + " page horizontal bounds")
	var toolbar := find_name(page, "BillingToolbar")
	if toolbar is Control: check(toolbar.get_global_rect().end.x <= viewport.x + 2.0, label + " toolbar visible")
	var confirm := find_name(page, "BillingPost")
	if confirm is Control: check(Rect2(Vector2.ZERO, viewport).encloses(confirm.get_global_rect()), label + " confirm visible")
	var tabs := find_name(page, "BillingInvoices")
	check(tabs is Control and (tabs as Control).get_global_rect().position.x >= -2.0, label + " billing tabs visible")

func add_fixture(contract_id: String, payment_days: int, client: String, title: String, fee: int, bonus: int, material_cost: int = 0, material_billable: bool = false) -> String:
	var result: Dictionary = BILLING.create_draft(game.state, contract_id, {"payment_days":payment_days,"client":client,"title":title}, {"fee":fee,"bonus":bonus,"baseline_bonus":0,"material_cost":material_cost,"material_billable":material_billable,"client":client,"title":title})
	check(bool(result.get("ok", false)), "create " + contract_id)
	var invoice: Dictionary = result.get("invoice", {}) if result.get("invoice", {}) is Dictionary else {}
	var id := str(invoice.get("id", ""))
	check(not id.is_empty(), "invoice id " + contract_id)
	if material_billable: check(int(invoice.get("amount", 0)) == fee + bonus + material_cost, "hardware invoice total " + contract_id)
	return id

func run() -> void:
	if "--receipt" in OS.get_cmdline_user_args():
		await run_receipt()
		_finish()
		return
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(3)
	game = ui._game()
	game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "QA storage")
	if not failures.is_empty():
		_finish()
		return
	check(ui._new_game(), "new billing UI game")
	check(game.choose_strategy("advisory") and game.start_free_career(), "billing UI career")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 640) if narrow else Vector2i(1280, 720)
	var immediate_id := add_fixture("ui-billing-immediate", 0, str(game.state.offers[0].client), str(game.state.offers[0].title), 12000, 800, 3200, true)
	var posted_id := add_fixture("ui-billing-posted", 1, str(game.state.offers[1].client), str(game.state.offers[1].title), 18000, 1200)
	var draft_id := add_fixture("ui-billing-draft", 2, str(game.state.offers[2].client), str(game.state.offers[2].title), 21000, 1400)
	check(not immediate_id.is_empty() and not posted_id.is_empty() and not draft_id.is_empty(), "three billing fixtures")
	var posted: Dictionary = game.post_invoice(posted_id)
	check(bool(posted.get("ok", false)), "post deferred invoice through Game")
	check(str(_invoice(posted_id).get("status", "")) == "posted", "deferred invoice remains posted")
	check(str(_invoice(immediate_id).get("status", "")) == "draft" and str(_invoice(draft_id).get("status", "")) == "draft", "immediate and later invoices remain drafts")
	ui.open_panel("board")
	await frames(8)
	var operations_billing := find_name(ui.root, "OperationsBilling")
	press(operations_billing, "OperationsBilling")
	await frames(10)
	pc = ui.desktop
	check(pc != null, "billing desktop opened from operations")
	if pc == null:
		_finish()
		return
	pc._show_app("billing")
	await frames(8)
	if not pc.windows.billing.maximized: pc.windows.billing.toggle_maximize()
	pc._render_billing()
	await frames(4)
	check(pc.widgets.has("billing"), "billing app window")
	check(find_name(pc.widgets.billing.page, "BillingInvoiceList") != null, "invoice list from unaccepted operations")
	assert_layout("invoice list")
	await capture("billing-list")
	var draft_row := find_invoice_row(immediate_id)
	check(draft_row != null, "immediate draft row")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(2)
	var pointer_before := root.get_viewport().get_mouse_position()
	click_gui(draft_row)
	await frames(8)
	var pointer_after := root.get_viewport().get_mouse_position()
	check(pointer_before.distance_to(pointer_after) <= 1.0, "row selection does not move pointer")
	check(find_name(pc.widgets.billing.page, "BillingSelectedInvoice") != null, "draft invoice detail")
	check(find_name(pc.widgets.billing.page, "BillingPost") is BaseButton, "draft confirm control")
	check(contains_text(pc.widgets.billing.page, "¥3,200"), "billable hardware line visible")
	assert_layout("draft detail")
	await capture("billing-draft-detail")
	var cash_before := int(game.state.cash)
	var original_save: String = game.save_path
	var original_backup: String = game.backup_path
	var original_previous: String = game.previous_path
	var original_settings: String = game.settings_path
	game.save_path = "user://qa-billing-save-failure-" + profile + "/missing/state.json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	var post_button := find_name(pc.widgets.billing.page, "BillingPost")
	press(post_button, "Billing confirm save failure")
	await frames(6)
	check(int(game.state.cash) == cash_before, "save failure keeps cash")
	check(str(_invoice(immediate_id).get("status", "")) == "draft", "save failure keeps draft")
	var failure_feedback := find_name(pc.widgets.billing.page, "BillingPostFeedback")
	check(failure_feedback is Label and not str((failure_feedback as Label).text).is_empty(), "save failure feedback")
	# Dismiss the deliberate failure notification using its existing close control.
	for node in pc.notification.find_children("*", "Button", true, false): node.pressed.emit()
	game.save_path = original_save
	game.backup_path = original_backup
	game.previous_path = original_previous
	game.settings_path = original_settings
	press(find_name(pc.widgets.billing.page, "BillingPost"), "Billing confirm immediate")
	await frames(10)
	var immediate := _invoice(immediate_id)
	var amount := int(immediate.get("amount", 0))
	check(str(immediate.get("status", "")) == "paid", "immediate invoice paid")
	check(int(game.state.cash) == cash_before + amount, "immediate confirm increments cash exactly")
	check(str(immediate.get("reference", "")).begins_with("BANK/"), "bank reference recorded")
	check(contains_text(pc.widgets.billing.page, "BANK/"), "bank reference displayed")
	assert_layout("paid detail")
	await capture("billing-paid-detail")
	press(find_name(pc.widgets.billing.page, "BillingPayments"), "Payments tab")
	await frames(8)
	check(find_name(pc.widgets.billing.page, "BillingPaymentTable") != null, "payments table")
	check(contains_text(pc.widgets.billing.page, "BANK/"), "payment actual record")
	await capture("billing-payments")
	press(find_name(pc.widgets.billing.page, "BillingInvoices"), "Invoices tab")
	await frames(8)
	var filter := find_name(pc.widgets.billing.page, "BillingFilter")
	check(filter is OptionButton, "status filter")
	if filter is OptionButton:
		(filter as OptionButton).select(3)
		(filter as OptionButton).item_selected.emit(3)
		await frames(8)
		check(contains_text(pc.widgets.billing.page, "1 records") or contains_text(pc.widgets.billing.page, "1件"), "paid filter count")
		check(find_invoice_row(immediate_id) != null and (find_invoice_row(immediate_id) as Control).visible, "paid filter row")
	var all_filter := find_name(pc.widgets.billing.page, "BillingFilter")
	if all_filter is OptionButton:
		(all_filter as OptionButton).select(0)
		(all_filter as OptionButton).item_selected.emit(0)
		await frames(8)
	var search := find_name(pc.widgets.billing.page, "BillingSearch")
	check(search is LineEdit, "billing search")
	if search is LineEdit:
		var line: LineEdit = search
		line.grab_focus()
		line.text = "No such invoice"
		line.caret_column = line.text.length()
		line.text_changed.emit(line.text)
		await frames(3)
		check(line.has_focus(), "search preserves focus")
		check(line.caret_column == line.text.length(), "search preserves caret")
		var empty := find_name(pc.widgets.billing.page, "BillingNoResults")
		check(empty is Label and (empty as Label).visible, "no-result state")
		check(contains_text(pc.widgets.billing.page, "0 records") or contains_text(pc.widgets.billing.page, "0件"), "no-result count exact")
		await capture("billing-empty-search")
	_finish()

func _receipt_fixture(id: String, fee: int, bonus: int, cost: int, material_cost: int, billable: bool, invoice_days: int = 0, create_invoice: bool = true, baseline_bonus: int = 0) -> String:
	var receipt := {"day":int(game.state.day),"client":"Receipt QA","title":UI.copy("stock_case_title"),"fee":fee,"bonus":bonus,"baseline_bonus":baseline_bonus,"cost":cost,"material_cost":material_cost,"material_billable":billable,"net":fee + bonus + (material_cost if billable else 0) - cost,"grade":"A","quality_score":3,"level_before":1,"level_after":1,"xp_gain":maxi(fee + bonus - cost,0),"rating":"on_time","minutes":10,"budget":30,"credit_before":100,"credit_after":100,"credit_gain":0,"satisfaction_before":70,"satisfaction_after":73,"quality_satisfaction_delta":5,"price_satisfaction_delta":-2,"renewal_outcome":"active"}
	var invoice: Dictionary = {}
	if create_invoice:
		var contract := {"payment_days":invoice_days,"client":"Receipt QA","title":id}
		var created: Dictionary = BILLING.create_draft(game.state, id, contract, {"fee":fee,"bonus":bonus,"baseline_bonus":baseline_bonus,"material_cost":material_cost,"material_billable":billable,"client":"Receipt QA","title":id})
		check(bool(created.get("ok",false)), "receipt invoice created " + id)
		invoice = created.get("invoice",{}) if created.get("invoice",{}) is Dictionary else {}
	receipt.invoice_id = str(invoice.get("id",""))
	game.state.current_contract_id = id
	game.state.contract = game.state.offers[0].duplicate(true)
	game.state.contract.merge({"billing_version":1,"client":"Receipt QA","title":id,"reward":fee}, true)
	game.state.completed_ids = [id]
	game.state.last_receipt = receipt
	check(game.current_done(), "receipt fixture current_done " + id)
	return str(invoice.get("id",""))

func _show_receipt() -> void:
	ui.open_panel("terminal")
	await frames(8)
	pc = ui.desktop
	check(pc != null, "receipt desktop opened")
	if pc == null: return
	pc._show_app("receipt")
	await frames(8)
	pc._refresh_receipt()
	await frames(4)

func _receipt_panel(name: String) -> Node:
	return find_name(pc.widgets.receipt.body, name) if pc != null and pc.widgets.has("receipt") else null

func _check_receipt_shell(label: String, expected_profit: String, expected_sales: String, expected_cost: String) -> void:
	check(_receipt_panel("ReceiptSales") != null, label + " sales label")
	check(_receipt_panel("ReceiptCosts") != null, label + " costs label")
	check(_receipt_panel("ReceiptProfit") != null, label + " profit label")
	check(_receipt_panel("ReceiptProfit") is Label and str((_receipt_panel("ReceiptProfit") as Label).text) == expected_profit, label + " exact profit amount")
	check(_receipt_panel("ReceiptSales") is Label and str((_receipt_panel("ReceiptSales") as Label).text) == expected_sales, label + " exact sales amount")
	check(_receipt_panel("ReceiptCosts") is Label and str((_receipt_panel("ReceiptCosts") as Label).text) == expected_cost, label + " exact cost amount")
	check(_receipt_panel("ReceiptFinanceTab") is BaseButton, label + " finance tab")
	check(_receipt_panel("ReceiptEvaluationTab") is BaseButton, label + " evaluation tab")
	check(_receipt_panel("ReceiptFinance") is Control, label + " finance panel")
	check(_receipt_panel("ReceiptEvaluation") is Control, label + " evaluation panel")
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	var body: Control = pc.widgets.receipt.body
	var footer: Control = pc.widgets.receipt.footer
	var body_rect := body.get_global_rect(); var footer_rect := footer.get_global_rect()
	check(body_rect.position.x >= -2.0 and body_rect.end.x <= viewport.end.x + 2.0, label + " receipt body horizontal bounds")
	check(footer_rect.position.x >= -2.0 and footer_rect.end.x <= viewport.end.x + 2.0, label + " receipt footer horizontal bounds")
	if _receipt_panel("ReceiptMaterialCost") != null:
		check(_has_right_aligned_label(_receipt_panel("ReceiptMaterialCost")), label + " material amount right aligned")

func _has_right_aligned_label(node: Node) -> bool:
	if node == null: return false
	if node is Label and (node as Label).horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT: return true
	for child in node.get_children():
		if _has_right_aligned_label(child): return true
	return false

func run_receipt() -> void:
	var profile_arg := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-profile="): profile_arg = str(arg).substr(13)
	check(profile_arg.begins_with("receipt-"), "receipt QA profile guard")
	if not profile_arg.begins_with("receipt-"):
		return
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(3)
	game = ui._game()
	game.set_process(false)
	game.save_path = "user://qa-receipt-" + profile + ".json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	check(game.new_game(), "receipt UI new game")
	check(game.choose_strategy("operations") and game.start_free_career(), "receipt career fixture")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	var draft_id := _receipt_fixture("completion_receipt-hardware",12000,800,4200,3200,true,0,true,300)
	await _show_receipt()
	if pc == null: return
	_check_receipt_shell("draft hardware", "¥11,800", "¥16,000", "¥4,200")
	check(_receipt_panel("ReceiptInvoiceStatus") is Label, "draft invoice status label")
	check(_receipt_panel("ReceiptInvoice") is BaseButton, "draft invoice button")
	check(contains_text(pc.widgets.receipt.body, UI.copy("billing_receipt_pending")), "draft invoice pending label")
	check(_receipt_panel("ReceiptMaterialBillable") != null, "billable material row")
	check(_receipt_panel("ReceiptMaterialCost") != null, "material cost row")
	await capture("receipt-draft")
	var finance_tab := _receipt_panel("ReceiptFinanceTab")
	press(finance_tab, "finance tab")
	await frames(3)
	check(bool((_receipt_panel("ReceiptFinance") as Control).visible), "finance tab visible")
	check(not bool((_receipt_panel("ReceiptEvaluation") as Control).visible), "evaluation tab hidden")
	press(_receipt_panel("ReceiptEvaluationTab"), "evaluation tab")
	await frames(3)
	check(bool((_receipt_panel("ReceiptEvaluation") as Control).visible), "evaluation tab visible")
	check(not bool((_receipt_panel("ReceiptFinance") as Control).visible), "finance tab hidden")
	pc._refresh_receipt()
	await frames(3)
	check(bool((_receipt_panel("ReceiptEvaluation") as Control).visible), "tab state survives refresh")
	var draft_invoice := _invoice(draft_id)
	check(str(draft_invoice.get("status","")) == "draft", "receipt starts draft")
	check(bool(game.post_invoice(draft_id).get("ok",false)), "receipt posts immediately")
	pc._refresh_receipt()
	await frames(3)
	check(contains_text(pc.widgets.receipt.body, UI.copy("billing_paid")), "paid status updates")
	check(str(_invoice(draft_id).get("status","")) == "paid", "paid status stored")
	var row_cost := _receipt_panel("ReceiptMaterialCost")
	check(row_cost is Control and (row_cost as Control).get_global_rect().position.x >= -2.0, "material row in bounds")
	await capture("receipt-paid")
	_receipt_fixture("completion_receipt-loss",0,0,1200,0,false,0,false)
	pc._refresh_receipt()
	await frames(3)
	_check_receipt_shell("negative maintenance", "-¥1,200", "¥0", "¥1,200")
	await capture("receipt-loss")
	_receipt_fixture("completion_receipt-legacy",12000,800,4200,3200,false,0,false,300)
	game.state.last_receipt.erase("material_billable")
	game.state.last_receipt.erase("invoice_id")
	pc._refresh_receipt()
	await frames(3)
	_check_receipt_shell("legacy material", "¥8,600", "¥12,800", "¥4,200")
	check(not contains_text(pc.widgets.receipt.body, "¥16,000"), "legacy missing billable excludes material")
	await capture("receipt-final")

func _invoice(id: String) -> Dictionary:
	for raw in game.company_invoices():
		if raw is Dictionary and str(raw.get("id", "")) == id:
			return raw
	return {}

func _finish() -> void:
	if game != null:
		for path in [game.save_path, game.backup_path, game.previous_path, game.settings_path]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error("COMPANY_BILLING_UI: " + failure)
	print("COMPANY_BILLING_UI_TEST_", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
