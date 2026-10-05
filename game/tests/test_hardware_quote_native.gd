extends "res://tests/test_portal_diff_ui.gd"
## Real earned DAY6 checkpoint, naturally available appliance commissioning.
## No offer/skill/fund/config/result injection. UI events perform all new work.
var selected_offer: Dictionary = {}
var serial := ""
var unit_id := ""
var source_path := ""
func journey_timeout() -> float: return 480.0

func build_ui() -> void:
	await super.build_ui()
	root.get_node("Graphics").apply_settings(game.settings); await frames(10)
	record("display", "Office Graphics: pixels=" + str(root.size) + " logical=" + str(root.get_visible_rect().size))

func visible_quote() -> bool:
	var board := control("QuoteCommissioningBoard")
	if not expect(board != null and board.get_meta("projection") == "planned" and board.scope.id == "hardware-backup-install", "authored commissioning plan is distinct from live measurements"): return false
	if not await scroll_to(board, true): return false
	for id in ["QuoteSourceObject", "QuoteApplianceObject", "QuoteAcceptanceObject", "QuoteSourceTitle", "QuoteApplianceTitle", "QuoteAcceptanceTitle", "QuoteSourceCount", "QuoteApplianceState", "QuoteAcceptanceState"]:
		var item := control(id)
		if not expect(clipped_rect(item).grow(1).encloses(item.get_global_rect()), id + " fully visible at actual enlarged setting"): return false
	var before: Dictionary = game.state.duplicate(true)
	if not await press("QuoteSourceObject") or not expect(str(control("QuoteScopeInspection").text).contains("customers.csv") and str(control("QuoteScopeInspection").text).contains("ledger.txt"), "paper object reveals exact authored source files"): return false
	if not await keyboard_activate("QuoteAcceptanceObject") or not expect(str(control("QuoteScopeInspection").text).contains("/restore") and game.state == before, "keyboard inspects acceptance without measurements, file writes or transactions"): return false
	await capture("01-commissioning-plan")
	return true

func fee(amount: int) -> bool:
	var input := control("OfferPrice") as SpinBox
	if not expect(input != null, "fee exists"): return false
	if not await edit_control(input.get_line_edit(), str(amount), "proposed fee"): return false
	await tap(KEY_ENTER); await frames(8)
	var expected: Dictionary = game.contract_quote(selected_offer, amount)
	var scale := control("QuotePriceScale")
	if not expect(roundi(input.value) == amount and scale.quote == expected and bool(scale.get_meta("affordable")) == bool(expected.affordable), "budget graphic follows exact actual quote calculation"): return false
	var status := control("QuoteSendState")
	if not expect(clipped_rect(status).grow(1).encloses(status.get_global_rect()), "budget result remains fully visible beside send button"): return false
	if not await fully_visible(scale): return false
	for id in ["QuoteBudgetMarker", "QuoteReferenceMarker", "QuoteProposalMarker", "QuoteMarginParts"]:
		var label := control(id) as Label
		if not expect(clipped_rect(label).grow(1).encloses(label.get_global_rect()) and label.get_theme_font_size("font_size") >= roundi(12 * game.settings.text_scale), id + " fits at requested text size"): return false
	await capture("price-" + str(amount))
	return true

func fully_visible(target: Control) -> bool:
	var parent := visible_scroll_ancestor(target)
	for _attempt in 40:
		if clipped_rect(target).grow(1).encloses(target.get_global_rect()): break
		if parent == null: break
		var rect := clipped_rect(parent)
		mouse(rect.get_center(), MOUSE_BUTTON_WHEEL_DOWN if target.get_global_rect().end.y > rect.end.y else MOUSE_BUTTON_WHEEL_UP)
		await frames(4)
	return expect(clipped_rect(target).grow(1).encloses(target.get_global_rect()), str(target.name) + " fully reachable by real wheel input")

func quote_journey() -> bool:
	if not await press("SalesOffer_" + str(selected_offer.id).validate_node_name()) or not await visible_quote(): return false
	var before: Dictionary = game.state.duplicate(true)
	if not await press("QuoteApplianceObject") or not expect(ui.current_kind == "shop", "appliance object opens actual stock software") or not await press("BackToQuote"): return false
	if not expect(game.state == before and int(control("OfferPrice").value) == int(game.contract_quote(selected_offer).quoted_fee), "procurement navigation preserves business state and proposed price"): return false
	var reference := int(game.contract_quote(selected_offer).reference_fee)
	var cap := int(game.contract_quote(selected_offer).budget_limit)
	if not await fee(0) or not expect(str(control("QuoteSendState").text).contains("赤字") and int(control("QuotePriceScale").quote.net) == -700, "zero fee visibly exposes actual negative margin"): return false
	if not await fee(cap + 1) or not await press("AcceptContract"): return false
	if not expect(str(game.state.contract.get("case_id", "")) != "hardware-backup-install" and str(control("QuoteDeclined").text).contains(str(cap + 1)) and game.state.quote_decisions.back().decision == "declined", "real over-budget quote is declined without acceptance or charge"): return false
	var feedback := control("ManagementActionFeedback")
	if not expect(feedback != null and clipped_rect(feedback).encloses(feedback.get_global_rect()) and text_in(feedback).contains("見積不成立"), "decline is readable beside fixed actions without extra scrolling"): return false
	await capture("02-real-declined-quote")
	if not await fee(reference - 500): return false
	if not expect(not control("ManagementActionFeedback").visible, "changing rejected price clears previous send failure"): return false
	if not await press("SaveQuoteDraft"): return false
	var quotes: Dictionary = game.state.offer_quotes.duplicate(true)
	ui.queue_free(); await frames(6)
	if not expect(game.load_game() and same_values(game.state.offer_quotes, quotes), "interruption resumes exact saved fee draft"): return false
	game.set_process(false); await build_ui(); ui.open_panel("sales"); await frames(10)
	if not await press("SalesOffer_" + str(selected_offer.id).validate_node_name()): return false
	if not expect(int(control("OfferPrice").value) == reference - 500 and int(control("QuotePriceScale").quote.quoted_fee) == reference - 500, "reconstructed quote and scale retain saved fee"): return false
	var old_cash := int(game.state.cash); var path: String = game.save_path
	game.save_path = "user://missing-hardware-quote-dir/save.json"
	var clicked := await press("AcceptContract")
	game.save_path = path
	if not clicked: return false
	if not expect(int(game.state.cash) == old_cash and str(game.state.contract.get("case_id", "")) != "hardware-backup-install" and int(control("OfferPrice").value) == reference - 500, "failed quote save preserves draft and leaves contract/funds unchanged"): return false
	feedback = control("ManagementActionFeedback")
	if not expect(feedback != null and clipped_rect(feedback).encloses(feedback.get_global_rect()) and text_in(feedback).contains("送信できません"), "save failure is visible next to quote actions"): return false
	await capture("quote-save-failed")
	if not await press("AcceptContract"): return false
	return expect(str(game.state.contract.case_id) == "hardware-backup-install" and int(game.state.contract.agreed_fee) == reference - 500, "retry accepts genuinely available commissioned work with saved terms")

func same_values(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func run() -> void:
	game = root.get_node("Game")
	if not expect("--qa-profile=hardware-quote-native" in OS.get_cmdline_user_args() and game.save_path.begins_with("user://qa-"), "isolated commissioning QA"): finish(); return
	source_path = OS.get_environment("WHL_HARDWARE_FIXTURE")
	source_text = FileAccess.get_file_as_string(source_path)
	var output := FileAccess.open(game.save_path, FileAccess.WRITE)
	if not expect(output != null and not source_text.is_empty(), "copy genuine prior played checkpoint"): finish(); return
	output.store_string(source_text); output.close()
	if not expect(game.load_game() and int(game.state.day) == 6 and game.current_done(), "resume naturally funded DAY6 result"): finish(); return
	game.set_process(false)
	for offer in game.state.offers:
		if str(offer.case_id) == "hardware-backup-install" and bool(offer.unlocked) and bool(offer.market_available): selected_offer = offer; break
	if not expect(not selected_offer.is_empty(), "existing market offers the appliance job without reroll or override"): finish(); return
	await build_ui(); ui.open_panel("sales"); await frames(10)
	if not await quote_journey(): finish(); return
	if not await press("DispatchOpen") or not await route("terminal") or not await press("TerminalPreparation"): finish(); return
	if not await press("StockCatalogTab") or not await press("StockProductSelect_backup_appliance"): finish(); return
	var quantity := control("StockCartQuantity_backup_appliance") as SpinBox
	if not await edit_control(quantity.get_line_edit(), "1", "one WHB-2") : finish(); return
	await tap(KEY_ENTER)
	var cash := int(game.state.cash)
	if not await press("StockPurchase") or not expect(int(game.state.cash) == cash - 4800, "actual material payment charges ¥4800 once"): finish(); return
	game.set_office_clock_paused(true); game.set_delivery_clock_enabled(true); game.set_process(true)
	for _second in 34:
		await create_timer(1.0).timeout
		if game.customer_stock_units().any(func(unit): return str(unit.sku) == "backup_appliance" and str(unit.status) == "ready"): break
	game.set_process(false)
	for unit in game.customer_stock_units():
		if str(unit.sku) == "backup_appliance" and str(unit.status) == "ready": unit_id = str(unit.id); serial = str(unit.serial); break
	if not expect(not unit_id.is_empty(), "real delivery timer makes purchased appliance available") or not await press("StockPreparationTab") or not await press("PreparationUnit_" + unit_id.validate_node_name()) or not await press("PreparationPrepare"): finish(); return
	if not expect(str(game.customer_stock_for(unit_id).status) == "staged", "same serial physically connected to commissioning bench"): finish(); return
	if not await press("PreparationShip") or not expect(str(game.customer_stock_for(unit_id).status) == "staged" and not text_in(control("PreparationFeedback")).is_empty(), "unverified appliance cannot be shipped; visible failure preserves bench"): finish(); return
	if not await press("PreparationTerminal"): finish(); return
	if not await edit_control(ui.desktop.widgets.terminal.command, "ssh client", "connect actual staged backup appliance"): finish(); return
	await tap(KEY_ENTER)
	if not await route("browser") or not await press("BackupPlan") or not await select_option("BackupSchedule", 1) or not await press("BackupSavePlan") or not await press("BackupNow") or not await press("BackupSnapshot_00000001") or not await press("BackupRestore"): finish(); return
	if not await edit("BackupDestination", "/tmp") or not await press("BackupPreviewChanges") or not await press("BackupExecuteRestore"): finish(); return
	if not expect(not game._vm().backup_acceptance_view().accepted and game._vm().state.fs.has("/tmp/srv/data/ledger.txt"), "successful wrong-destination restore still fails customer acceptance"): finish(); return
	await capture("03-wrong-recovery-location")
	if not await edit("BackupDestination", "/restore") or not await press("BackupPreviewChanges") or not await press("BackupExecuteRestore") or not expect(game._vm().backup_acceptance_view().accepted, "retry restores all actual required records to approved location"): finish(); return
	var saved: Dictionary = game._vm().export_state()
	if not expect(ui.desktop._save_session() and game.save_game(), "save actual restored but undelivered work"): finish(); return
	ui.queue_free(); await frames(6)
	if not expect(game.load_game() and same_values(game._vm().export_state(), saved) and str(game.customer_stock_for(unit_id).serial) == serial, "resume retains exact source/restored bytes and physical serial"): finish(); return
	game.set_process(false); await build_ui()
	if not await route("verify"): finish(); return
	for probe in game.diagnostic_probes():
		if not await press("DiagnosticProbe_" + str(probe.id).validate_node_name()) or not await press("DiagnosticRun"): finish(); return
	if not await press("DiagnosticValidate") or not expect(game.state.checks.filter(func(row): return not bool(row.get("hardware", false))).all(func(row): return bool(row.passed)), "actual probes pass and serial arrival remains separate"): finish(); return
	if not await route("terminal") or not await press("TerminalPreparation") or not await press("StockPreparationTab") or not await press("PreparationShip"): finish(); return
	game.set_process(true)
	for _second in 13: await create_timer(1.0).timeout
	game.set_process(false)
	if not expect(str(game.customer_stock_for(unit_id).status) == "delivered", "real shipping timer reaches customer") or not await press("PreparationReceipt") or not await press("GuideDeliver"): finish(); return
	var receipt: Dictionary = game.completion_receipt()
	if not expect(game.current_done() and str(receipt.hardware_serial) == serial and int(receipt.material_cost) == 4800 and int(receipt.satisfaction_after) > int(receipt.satisfaction_before), "actual on-time delivery records appliance, material, and customer consequence"): finish(); return
	if not await press("ReceiptFinanceTab") or not await press("ReceiptInvoice") or not await press("BillingPost"): finish(); return
	if not expect(game.company_invoices().any(func(row): return str(row.id) == str(receipt.invoice_id) and str(row.status) == "paid"), "actual invoice paid after commissioned delivery"): finish(); return
	await capture("04-commissioning-paid-result")
	if not expect(FileAccess.get_file_as_string(source_path) == source_text, "prior source checkpoint untouched"): finish(); return
	var completed := FileAccess.open(folder.path_join("completed.json"), FileAccess.WRITE)
	if completed != null: completed.store_string(JSON.stringify(game.state, "\t")); completed.close()
	journey_completed = true; finish()

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("commissioning stopped before paid result")
	var report := {"assertions":assertions, "clicks":clicks, "keys":keys, "scrolls":scrolls, "narrow":narrow, "failures":failures, "events":events, "method":"Genuine previously played DAY6 checkpoint; actual available backup appliance case. Quote inspection, budget rejection, draft interruption, save-failure retry, acceptance, procurement, preparation, restore, probes, dispatch, receipt and payment use Godot mouse/key events. Office Graphics applied. Background work clock paused with explicit work costs preserved; arrival timers run normally. No new money, skills, offer, configuration or result injected."}
	var file := FileAccess.open(folder.path_join("hardware-quote-native.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  ")); file.close()
	print("HARDWARE_QUOTE_NATIVE_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " failures=", failures)
	if is_instance_valid(ui): ui.queue_free(); await frames(5)
	quit(0 if failures.is_empty() else 1)
