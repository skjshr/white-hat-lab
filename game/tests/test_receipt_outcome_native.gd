extends "res://tests/test_business_source_native.gd"
## Actual three-host work and funds; optionally leave ready work overnight.
var saved_receipt: Dictionary = {}
var late := "--late" in OS.get_cmdline_user_args()

func qa_profile() -> String: return "receipt-outcome-native"
func report_name() -> String: return "receipt-outcome-native"

func same_saved_values(a: Variant, b: Variant) -> bool:
	# JSON changes integer Variants to floats; compare values in the actual
	# save format, including every response byte, rather than Variant types.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func receipt_readonly_state() -> Dictionary:
	var result: Dictionary = game.state.duplicate(true)
	# Ordinary desktop autosave remembers opened windows during the longer
	# narrow-screen route. Only these observed navigation keys are excluded;
	# every business value, VM byte, measurement, draft and saved response stays.
	for session in result.get("desktop_sessions", {}).values():
		for field in ["active_app", "windows", "maximized", "open_apps", "running_apps"]: session.erase(field)
	return result

func before_delivery() -> bool:
	if not late: return true
	var id := str(game.state.current_contract_id); var day := int(game.state.day)
	if not await press("ExitDesktop"): return false
	# This fixture hosts Interface without the 3D office's shortcuts. Open its
	# existing management surface as navigation setup; settlement itself uses
	# actual buttons, never a day/time/outcome assignment or Game.end_day().
	ui.open_panel("company"); await frames(10)
	record("navigation_setup", "Standalone Interface host: open existing management surface; actual day-close and settlement buttons follow.")
	if not await press("ManagementTab_board") or not await press("OperationsCloseDay") or not await press("DaySettle"): return false
	if not expect(int(game.state.day) == day + 1, "real day close carries verified work past the agreed deadline"): return false
	if not await press("DayNext") or not await press("DispatchTicket_" + id) or not await press("DispatchOpen") or not await route("verify"): return false
	if not await press("DiagnosticValidate"): return false
	return expect(str(game.work_status().quality) == "late" and game.can_deliver(), "ready actual work is late but remains deliverable")

func after_delivery() -> bool:
	saved_receipt = game.completion_receipt().duplicate(true)
	# Day close/reopening can leave live browser session data ahead of its last
	# autosave (for example a disconnected viewer's write capability). Establish
	# the baseline by saving the existing UI, without fetching or measuring.
	var cash_before := int(game.state.cash)
	var history_before: Array = game.state.history.duplicate(true)
	var customer_before: Dictionary = game.state.customer_relations.duplicate(true)
	if not expect(ui.desktop._save_session(), "save existing live UI before read-only receipt comparison"): return false
	if not expect(int(game.state.cash) == cash_before and game.state.history == history_before and game.state.customer_relations == customer_before and game.completion_receipt() == saved_receipt, "session baseline preserves actual delivery and financial/customer outcomes"): return false
	var all_state: Dictionary = receipt_readonly_state()
	if not await visible_impacts(): return false
	if not expect(str(control("ReceiptTiming").text) == ("期限超過" if late else "期限内") and (not late or int(saved_receipt.satisfaction_after) < int(saved_receipt.satisfaction_before)), "deadline and customer penalty follow actual saved delivery"): return false
	await capture("11-impact-first-view")
	for index in saved_receipt.delivery_results.size():
		if not await press("ReceiptTarget_" + str(index)): return false
		var options := control("ReceiptEvidenceSelection") as OptionButton
		var target: Dictionary = saved_receipt.delivery_results[index]
		if not expect(options.get_item_text(options.selected).begins_with(str(target.target) + " / ") and str(control("DiagnosticLatest").text) == str(target.probes[0].result), "selecting the saved site opens its exact first recorded response"): return false
		if not await select_saved_probe(target.probes.size() - 1): return false
		if not expect(str(control("DiagnosticLatest").text) == str(target.probes.back().result), "real popup keys select this site's last exact saved response"): return false
		if not expect(receipt_readonly_state() == all_state, "opening saved proof preserves business state and saved content"): return false
		if not await keyboard_activate("ReceiptEvidenceBack", true): return false
		if not expect(control("ReceiptTarget_" + str(index)).has_focus(), "return preserves the selected paper's keyboard focus"): return false
	if not await press("ReceiptEvaluationTab") or not await visible_impacts(): return false
	var actual_state := receipt_readonly_state()
	if actual_state != all_state:
		for field in actual_state:
			if actual_state[field] != all_state.get(field): print("RECEIPT_STATE_DIFFERENCE ", field)
		var debug := FileAccess.open(folder.path_join("receipt-state-difference.json"), FileAccess.WRITE)
		if debug != null: debug.store_string(JSON.stringify({"before":all_state,"after":actual_state}, "\t")); debug.close()
	if not expect(actual_state == all_state, "result navigation preserves all business values and saved content"): return false
	var render_before: Dictionary = game.state.duplicate(true)
	ui.desktop._refresh_receipt()
	if not expect(game.state == render_before, "direct receipt rendering preserves complete state before background autosave"): return false
	await frames(8)
	return true

func select_saved_probe(index: int) -> bool:
	if not await press("ReceiptEvidenceSelection"): return false
	var option := control("ReceiptEvidenceSelection") as OptionButton; var popup := option.get_popup()
	if not expect(popup.visible, "saved-proof popup opened by actual input"): return false
	_target_key(popup.get_window_id(), KEY_HOME)
	for _attempt in option.item_count + 1:
		if popup.get_focused_item() == index: break
		_target_key(popup.get_window_id(), KEY_DOWN)
	if not expect(popup.get_focused_item() == index, "actual keys reach chosen saved proof"): return false
	_target_key(popup.get_window_id(), KEY_ENTER); await frames(10)
	var selected := control("ReceiptEvidenceSelection") as OptionButton
	return expect(selected.selected == index and selected.has_focus() and clipped_rect(selected).encloses(selected.get_global_rect()), "saved proof selection and visible keyboard focus survive repaint")

func visible_impacts() -> bool:
	var board: Control = control("ReceiptOutcomeBoard")
	if not expect(is_instance_valid(board) and same_saved_values(board.receipt, saved_receipt), "graphical statement projects exact saved receipt"): return false
	for id in ["ReceiptGradeValue", "ReceiptTiming", "ReceiptSatisfactionValue", "ReceiptCreditValue", "ReceiptLevelValue", "ReceiptImpactSales", "ReceiptImpactCosts", "ReceiptImpactProfit"]:
		var label := control(id) as Label
		if not expect(is_instance_valid(label) and clipped_rect(label).grow(1).encloses(label.get_global_rect()), id + " is fully visible on first view without scroll"): return false
		var natural: float = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		if not expect(label.size.x + 1 >= natural and label.get_theme_font_size("font_size") == int((48 if id == "ReceiptGradeValue" else 12 if id == "ReceiptTiming" else 25 if id.begins_with("ReceiptImpact") else 23) * float(game.settings.text_scale)), id + " value fits and honors actual text setting"): return false
	var credit := "%d → %d" % [int(saved_receipt.credit_before), int(saved_receipt.credit_after)]
	return expect(str(control("ReceiptCreditValue").text) == credit and str(control("ReceiptImpactProfit").text) == ReceiptPanel._yen(int(saved_receipt.net)), "credit and profit show exact stored arithmetic")

func after_payment() -> bool:
	if not await route("receipt") or not await press("ReceiptEvaluationTab"): return false
	if not expect(str(control("ReceiptOutcomeInvoiceStatus").text).contains("入金済"), "actual invoice posting changes first-view payment status"): return false
	var state_before: Dictionary = game.state.duplicate(true)
	if not expect(ui.desktop._save_session() and game.save_game(), "save delivered statement and real payment"): return false
	var invoice: String = str(saved_receipt.invoice_id)
	ui.queue_free(); await frames(6)
	if not expect(game.load_game() and same_saved_values(game.completion_receipt(), saved_receipt), "interrupted completion reloads unchanged saved outcome"): return false
	game.set_process(false); await build_ui()
	if not await route("receipt") or not await press("ReceiptEvaluationTab") or not await visible_impacts(): return false
	if not expect(int(game.state.cash) == int(state_before.cash) and same_saved_values(game.state.history, state_before.history) and same_saved_values(game.state.customer_relations, state_before.customer_relations) and same_saved_values(game.state.company_cycle, state_before.company_cycle), "resume preserves actual cash/history/customer pipeline without another reward"): return false
	var paid: Array = game.company_invoices().filter(func(item): return str(item.id) == invoice and str(item.status) == "paid")
	if not expect(paid.size() == 1 and str(control("ReceiptOutcomeInvoiceStatus").text).contains("入金済"), "one real paid invoice survives resume"): return false
	await capture("12-paid-resumed-impacts")
	var out := FileAccess.open(folder.path_join("completed.json"), FileAccess.WRITE)
	if out != null: out.store_string(JSON.stringify(game.state, "\t")); out.close()
	return true
