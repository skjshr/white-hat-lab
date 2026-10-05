extends "res://tests/test_network_request_ui.gd"
## Customer-stock preparation through real UI input. Only the first normal
## career delivery uses public Game APIs as a documented funding setup; after
## that, contract acceptance, procurement, preparation, repair and delivery use
## Godot mouse/keyboard events. Timer waits model elapsed in-game shipment time.
const GameScript = preload("res://scripts/game.gd")
const HARDWARE_CASE := "hardware-gateway-install"
var stock_serial := ""
var stock_id := ""

func run() -> void:
	game = root.get_node("Game")
	if not expect_profile(): finish(); return
	game.set_process(false)
	if not expect(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(), "normal-funded public career setup"): finish(); return
	var service_offer: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == "service-2-case-0" and bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false)):
			service_offer = offer; break
	if not expect(not service_offer.is_empty() and game.choose_contract(str(service_offer.get("id", ""))), "accept naturally available service-2-case-0 via public API"): finish(); return
	game.inspect_mission()
	game.vm_run("ssh client")
	if not expect(bool(game.vm_info().get("connected", false)), "setup connects to the real accepted service"): finish(); return
	var setup_services: Dictionary = game.firewall_action("services", {"dns":"on", "tls":"on"})
	var setup_apply: Dictionary = game.firewall_action("apply")
	if not expect(bool(setup_services.get("ok", false)) and bool(setup_apply.get("ok", false)), "public setup firewall actions save and apply successfully"): finish(); return
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.get("id", "")))
	var setup_checks: Array = game.verify()
	if not expect(not setup_checks.is_empty() and setup_checks.all(func(row): return bool(row.get("passed", false))) and game.can_deliver() and game.deliver(), "repair, measure, verify and deliver first service case using public setup APIs"): finish(); return
	var first_receipt: Dictionary = game.completion_receipt()
	var invoice_id := str(first_receipt.get("invoice_id", ""))
	var setup_payment: Dictionary = game.post_invoice(invoice_id) if not invoice_id.is_empty() else {}
	if not expect(not invoice_id.is_empty() and bool(setup_payment.get("ok", false)), "first setup invoice is paid through public billing API"): finish(); return
	if not expect(game.current_done() and not invoice_id.is_empty() and str(game.completion_receipt().get("invoice_id", "")) == invoice_id, "first setup delivery is durable and invoiced"): finish(); return
	var hardware_offer: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == HARDWARE_CASE and bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false)):
			hardware_offer = offer; break
	if not expect(not hardware_offer.is_empty(), "earned career exposes hardware installation offer"): finish(); return
	ui = INTERFACE.new(); root.add_child(ui); await frames(12)
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	root.get_node("Graphics").apply_settings(game.settings); await frames(6)
	ui._set_text_scale(1.3 if narrow else 1.0); ui.controls.menu.hide(); ui.next_task_guide.set_enabled(false); ui.open_panel("sales"); await frames(10)
	if not await press("SalesOffer_" + str(hardware_offer.id).validate_node_name()): finish(); return
	if not await press("AcceptContract"): finish(); return
	if not expect(str(game.state.get("contract", {}).get("case_id", "")) == HARDWARE_CASE and game.state.get("accepted", false), "accept actual installation quote through SalesOffer and AcceptContract"): finish(); return
	if not await press("DispatchOpen"): finish(); return
	if not await route("terminal"): finish(); return
	if not await press("TerminalConnect"): finish(); return
	var terminal_output := control("TerminalOutput") as RichTextLabel
	var disconnected_output := terminal_output.text if is_instance_valid(terminal_output) else ""
	if not expect(not bool(game.vm_info().get("connected", false)) and disconnected_output.contains("機材") and not disconnected_output.contains("hardware_unavailable"), "terminal gives a plain Japanese not-connected hardware explanation"): finish(); return
	if not await press("TerminalPreparation"): finish(); return
	var empty_flow: Control = control("StockPreparationFlow")
	var ghost: Control = control("PreparationMissingAppliance")
	if not expect(is_instance_valid(ghost) and ghost.visible and is_instance_valid(empty_flow) and empty_flow.find_children("PreparationUnit_*", "Button", true, false).is_empty(), "empty preparation bench shows a missing-appliance ghost without an invented serial"): finish(); return
	var initial_cash := int(game.state.cash)
	if not await press("StockCatalogTab"): finish(); return
	if not await press("StockProductSelect_gateway"): finish(); return
	var quantity := control("StockCartQuantity_gateway") as SpinBox
	if not expect(is_instance_valid(quantity), "gateway quantity control is visible"): finish(); return
	if not await edit_control(quantity.get_line_edit(), "1", "gateway quantity actual text input"): finish(); return
	await tap(KEY_ENTER)
	if not expect(is_equal_approx(quantity.value, 1.0), "quantity one committed by keyboard"): finish(); return
	if not await press("StockPurchase"): finish(); return
	if not expect(int(game.state.cash) == initial_cash - 3200, "actual stock purchase charges normal ¥3,200 cost"): finish(); return
	game.set_office_clock_paused(true); game.set_delivery_clock_enabled(true); game.set_process(true)
	var received := false
	for _second in 34:
		await create_timer(1.0).timeout
		if game.customer_stock_units().any(func(unit): return str(unit.get("status", "")) == "ready"):
			received = true; break
	game.set_process(false)
	if not expect(received, "inbound hardware arrives on real delivery clock"): finish(); return
	if not await press("StockPreparationTab"): finish(); return
	var units: Array = game.customer_stock_units()
	var unit: Dictionary = {}
	for candidate in units:
		if str(candidate.get("sku", "")) == "gateway" and str(candidate.get("status", "")) == "ready": unit = candidate; break
	stock_id = str(unit.get("id", "")); stock_serial = str(unit.get("serial", ""))
	if not expect(not stock_id.is_empty() and not stock_serial.is_empty(), "one actual received stock identity and serial exist"): finish(); return
	if not await press("PreparationUnit_" + stock_id.validate_node_name()): finish(); return
	var prior_position := str(game.customer_stock_for(stock_id).get("status", "")); var funds_before_prepare := int(game.state.cash)
	var save_before := str(game.save_path); game.save_path = "user://stock-prep-ui-missing-parent/save.json"
	if not await press("PreparationPrepare"): finish(); return
	game.save_path = save_before
	if not expect(str(game.customer_stock_for(stock_id).get("status", "")) == prior_position and int(game.state.cash) == funds_before_prepare, "failed preparation save leaves serial position and funds unchanged"): finish(); return
	var prep_feedback := control("PreparationFeedback") as Label
	if not expect(is_instance_valid(prep_feedback) and prep_feedback.is_visible_in_tree() and not prep_feedback.text.is_empty(), "save failure is visible beside preparation actions"): finish(); return
	await capture("01-prepare-save-failure")
	if not await keyboard_activate("PreparationPrepare"): finish(); return
	if not expect(str(game.customer_stock_for(stock_id).get("status", "")) == "staged", "keyboard retry stages the same actual serial"): finish(); return
	var saved_key := str(game._machine_key); var saved_serial := str(game.customer_stock_for(stock_id).get("serial", ""))
	await capture("02-staged-before-resume")
	if not expect(game.save_game() and game.load_game(), "interrupt and resume from durable staged save"): finish(); return
	var reloaded_stock: Dictionary = game.customer_stock_for(stock_id)
	if not expect(str(reloaded_stock.get("serial", "")) == saved_serial and str(reloaded_stock.get("status", "")) == "staged" and str(game.state.get("current_contract_id", "")) == saved_key.get_slice("/", 0), "resume retains physical serial, bench location, and current contract"): finish(); return
	if not await press("PreparationShip"): finish(); return
	if not expect(str(game.customer_stock_for(stock_id).get("status", "")) == "staged" and not text_in(control("PreparationFeedback")).is_empty(), "unverified hardware shipment is rejected with visible checks"): finish(); return
	if not await board_geometry("03-unverified-staged-board"): finish(); return
	await capture("03-unverified-staged-board")
	if not await press("PreparationTerminal"): finish(); return
	var command: LineEdit = ui.desktop.widgets.terminal.command
	if not await edit_control(command, "ssh client", "hardware configuration SSH command"): finish(); return
	await tap(KEY_ENTER)
	if not expect(bool(game.vm_info().get("connected", false)), "actual SSH connects only after staging the purchased gateway"): finish(); return
	if not await route("browser"): finish(); return
	if not await press("FirewallNav_services"): finish(); return
	if not await select_option("FirewallDNS", 1): finish(); return
	if not await press("FirewallServicesSave"): finish(); return
	if not await press("FirewallNav_rules"): finish(); return
	if not await press("FirewallTab_lan"): finish(); return
	await capture("04-firewall-lan-rules")
	if not await press_scrolled("FirewallEdit_lan-business"): finish(); return
	if not await select_option("FirewallEditor_action", 0): finish(); return
	if not await press("FirewallSave"): finish(); return
	if not await press("FirewallApply"): finish(); return
	if not await route("verify"): finish(); return
	for probe in game.diagnostic_probes():
		var probe_id := str(probe.get("id", ""))
		if not await press("DiagnosticProbe_" + probe_id.validate_node_name()): finish(); return
		if not await press("DiagnosticRun"): finish(); return
	if not await press("DiagnosticValidate"): finish(); return
	if not expect(game.state.checks.filter(func(row): return not bool(row.get("hardware", false))).all(func(row): return bool(row.get("passed", false))) and not game.can_deliver(), "real non-hardware checks pass; shipping remains a separate arrival gate"): finish(); return
	var verified_key := str(game._machine_key); var verified_vm: Dictionary = game._machine.export_state(); var verified_probes: Array = game.diagnostic_probes(); var verified_path := str(game.vm_info().get("config_path", "")); var applied_before_resume: Dictionary = game._vm().state.get("applied", {}).duplicate(true)
	if not expect(game.save_game() and game.load_game(), "interrupt and reload staged repaired configuration and measured results"): finish(); return
	var resumed_probes: Array = game.diagnostic_probes(); var resumed_vm: Dictionary = game.state.get("vm_states", {}).get(verified_key, {}); var resumed_fs: Dictionary = resumed_vm.get("fs", {})
	var expected_probe_facts: Array = verified_probes.map(func(item): return [str(item.get("id", "")), bool(item.get("recorded", false)), bool(item.get("fresh", false)), bool(item.get("passed", false)), str(item.get("result", ""))])
	var resumed_probe_facts: Array = resumed_probes.map(func(item): return [str(item.get("id", "")), bool(item.get("recorded", false)), bool(item.get("fresh", false)), bool(item.get("passed", false)), str(item.get("result", ""))])
	if not expect(not verified_path.is_empty() and str(resumed_fs.get(verified_path, "")) == str(verified_vm.get("fs", {}).get(verified_path, "")) and resumed_probe_facts == expected_probe_facts and game._vm().state.get("applied", {}) == applied_before_resume, "reload preserves actual applied config and every fresh measurement"): finish(); return
	if not await route("terminal"): finish(); return
	if not await press("TerminalPreparation"): finish(); return
	if not await press("StockPreparationTab"): finish(); return
	if not expect(str(game.customer_stock_for(stock_id).get("status", "")) == "staged", "terminal return opens the same preparation board and serial"): finish(); return
	if not await board_geometry("04-verified-staged-board"): finish(); return
	await capture("04-verified-staged-board")
	if not await press("PreparationShip"): finish(); return
	if not expect(str(game.customer_stock_for(stock_id).get("status", "")) == "shipping", "verified staged unit is shipped by actual board button"): finish(); return
	await capture("05-in-transit-board")
	game.set_process(true)
	for _second in 13: await create_timer(1.0).timeout
	game.set_process(false)
	if not expect(str(game.customer_stock_for(stock_id).get("status", "")) == "delivered", "shipment arrives on real outbound delivery timer"): finish(); return
	await capture("06-arrived-board")
	var checks_before_receipt := JSON.stringify(game.state.checks)
	if not await press("PreparationReceipt"): finish(); return
	var receipt_result_text := text_in(ui.desktop)
	record("arrival_receipt_projection", JSON.stringify({"text":receipt_result_text,"checks_unchanged":JSON.stringify(game.state.checks) == checks_before_receipt,"can_deliver":game.can_deliver()}))
	await capture("07-arrived-receipt-before-delivery")
	var hardware_label := ""
	for check in game.state.checks:
		if bool(check.get("hardware", false)): hardware_label = str(check.get("label", "")); break
	if not expect(not hardware_label.is_empty() and not receipt_result_text.contains("×  " + hardware_label) and receipt_result_text.contains("8 / 8") and JSON.stringify(game.state.checks) == checks_before_receipt, "arrival receipt projects 8/8 readiness without changing saved verification checks"): finish(); return
	if not await press("GuideDeliver"): finish(); return
	var receipt: Dictionary = game.completion_receipt(); var relation: Dictionary = game.state.customer_relations.get(str(receipt.get("client", "")), {})
	if not expect(game.current_done() and str(receipt.get("hardware_serial", "")) == saved_serial and str(receipt.get("invoice_id", "")) != "", "delivery receipt records the installed physical serial and invoice"): finish(); return
	if not expect(int(relation.get("completed_count", 0)) >= 1 and int(receipt.get("fee", 0)) > 0 and int(receipt.get("credit_gain", 0)) > 0 and int(game.state.credit) == int(receipt.get("credit_after", -1)), "delivery records earned reward and trust credit"): finish(); return
	if not expect(int(relation.get("satisfaction", 0)) == int(receipt.get("satisfaction_after", -1)) and int(receipt.get("satisfaction_after", 0)) > int(receipt.get("satisfaction_before", 0)), "saved customer satisfaction reflects the on-time accepted delivery"): finish(); return
	var cash_before_hardware_invoice := int(game.state.cash)
	if not await press("ReceiptFinanceTab"): finish(); return
	if not await press("ReceiptInvoice"): finish(); return
	if not await press("BillingPost"): finish(); return
	if not expect(game.company_invoices().any(func(row): return str(row.get("id", "")) == str(receipt.invoice_id) and str(row.get("status", "")) == "paid" and int(row.get("amount", 0)) > 0) and int(game.state.cash) > cash_before_hardware_invoice, "positive customer invoice posts through actual billing control and increases cash"): finish(); return
	await capture("02-prepared-hardware-cycle-complete")
	journey_completed = true
	finish()

func expect_profile() -> bool:
	return expect("--qa-profile=stock-preparation-ui-narrow" in OS.get_cmdline_user_args() or "--qa-profile=stock-preparation-ui-wide" in OS.get_cmdline_user_args(), "isolated stock-preparation UI QA profile")

func press_scrolled(id: String) -> bool:
	var target: Control = control(id)
	if not expect(is_instance_valid(target) and target.is_visible_in_tree(), id + " exists before outer scrolling"): return false
	var ancestors: Array[ScrollContainer] = []
	var parent := target.get_parent()
	while parent != null:
		if parent is ScrollContainer and parent.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: ancestors.append(parent)
		parent = parent.get_parent()
	for scroller in ancestors:
		for _attempt in 60:
			var rect := clipped_rect(target)
			if rect.has_point(target.get_global_rect().get_center()): break
			var wheel := MOUSE_BUTTON_WHEEL_DOWN if target.get_global_rect().get_center().y > scroller.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP
			mouse(scroller.get_global_rect().get_center(), wheel)
			await frames(3)
		if clipped_rect(target).has_point(target.get_global_rect().get_center()): break
	if not expect(clipped_rect(target).has_point(target.get_global_rect().get_center()), id + " visible after real outer-page wheel input"): return false
	return await press_control(target, id)

func board_geometry(label: String) -> bool:
	var flow: Control = control("StockPreparationFlow")
	var actions: Control = control("PreparationActions")
	if not expect(is_instance_valid(flow) and flow.is_visible_in_tree() and is_instance_valid(actions) and actions.is_visible_in_tree(), label + " board and footer exist"): return false
	var selected: Button = control("PreparationUnit_" + stock_id.validate_node_name()) as Button
	if not expect(is_instance_valid(selected) and selected.is_visible_in_tree() and clipped_rect(selected).has_point(selected.get_global_rect().get_center()), label + " selected unit fits viewport"): return false
	for child in selected.find_children("*", "Control", true, false):
		if not expect(clipped_rect(selected).encloses(child.get_global_rect()), label + " unit caption fits inside physical item"): return false
	if not expect(root.get_visible_rect().encloses(clipped_rect(actions)), label + " feedback/actions footer fits viewport"): return false
	for id in ["PreparationFeedback", "PreparationPrepare", "PreparationTerminal", "PreparationVerify", "PreparationShip", "PreparationReceipt"]:
		var item: Control = control(id)
		if item != null and item.is_visible_in_tree() and not expect(clipped_rect(item).has_point(item.get_global_rect().get_center()), label + " " + id + " remains visible"): return false
	return true

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("stock preparation flow stopped before paid hardware invoice")
	var report := {"assertions":assertions,"narrow":narrow,"clicks":clicks,"keys":keys,"keyboard_actions":keyboard_actions,"scrolls":scrolls,"failures":failures,"events":events,"method":"First service-2-case-0 used documented normal career public setup APIs; hardware quote, procurement quantity/payment, preparation failure/retry, SSH/firewall editing, probes, shipment, receipt and invoice confirmation used Godot mouse/key events. Delivery timer and failed-save path were explicit fixtures; no money, desired config, answer, progression or result was injected into the hardware cycle."}
	var report_path := folder.path_join("stock-preparation-native" + ("-narrow" if narrow else "-wide") + ".json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  ")); file.close()
	print("STOCK_PREPARATION_UI_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " clicks=", clicks, " keys=", keys, " failures=", failures)
	if is_instance_valid(ui): ui.queue_free(); await frames(5)
	quit(0 if failures.is_empty() else 1)
