extends "res://tests/test_hardware_quote_native.gd"
## Continue the earned company. All new business work uses actual input events.
const ACCESS = preload("res://scripts/samba_access_board.gd")
var initial_report := ""
var daily_report := ""
var orders_before := ""

func visible_quote() -> bool:
	var board := control("ShareIntakeBoard")
	if not expect(board != null and board.get_meta("projection") == "customer_report" and control("QuoteCommissioningBoard") == null, "daily work order differs from appliance blueprint and actual measurements"): return false
	if not await fully_visible(board): return false
	for id in ["ShareIntakeReported", "ShareIntakeUnknown", "ShareIntakeReport", "ShareIntakeBoundary", "ShareIntakeSave", "ShareIntakeKeep", "ShareIntakeShare", "ShareIntakeStaffGoal", "ShareIntakeGuestGoal"]:
		var object := control(id)
		if not expect(clipped_rect(object).grow(1).encloses(object.get_global_rect()), "entire work-order object visible " + id): return false
	var before: Dictionary = game.state.duplicate(true)
	if not await press("ShareIntakeReport") or not await keyboard_activate("ShareIntakeBoundary"): return false
	for id in ["ShareIntakeReport", "ShareIntakeBoundary"]:
		for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			var contrast := (Color("f1e8c9").srgb_to_linear().get_luminance() + .05) / (control(id).get_theme_color(color).srgb_to_linear().get_luminance() + .05)
			if not expect(contrast >= 4.5, "legible object contrast in each interaction state " + id + " " + color): return false
	if not expect(game.state == before and str(control("ShareIntakeInspection").text).contains("納品条件"), "object inspection is keyboard reachable and never pretends to investigate"): return false
	if not await fully_visible(control("ShareIntakeInspection")): return false
	await capture("01-graphical-daily-work-order")
	return true

func quote_journey() -> bool:
	if not await press("SalesOffer_" + str(selected_offer.id).validate_node_name()) or not await visible_quote(): return false
	var reference := int(game.contract_quote(selected_offer).reference_fee)
	var cap := int(game.contract_quote(selected_offer).budget_limit)
	if not await fee(cap + 1) or not await press("AcceptContract"): return false
	if not expect(game.state.quote_decisions.back().decision == "declined" and str(game.state.contract.case_id) != "service-0-case-0", "actual budget rejection leaves daily work unaccepted"): return false
	if not await fee(reference) or not await press("SaveQuoteDraft"): return false
	var quotes: Dictionary = game.state.offer_quotes.duplicate(true)
	ui.queue_free(); await frames(6)
	if not expect(game.load_game() and same_values(game.state.offer_quotes, quotes), "interruption retains exact actual quote draft"): return false
	game.set_process(false); await build_ui(); ui.open_panel("sales"); await frames(10)
	if not await press("SalesOffer_" + str(selected_offer.id).validate_node_name()) or not expect(int(control("OfferPrice").value) == reference, "saved quote resumes"): return false
	var cash := int(game.state.cash); var path: String = game.save_path
	game.save_path = "user://missing-daily-report-quote/save.json"
	var clicked := await press("AcceptContract"); game.save_path = path
	if not clicked or not expect(int(game.state.cash) == cash and str(game.state.contract.case_id) != "service-0-case-0" and text_in(control("ManagementActionFeedback")).contains("送信できません"), "failed quote save retains company and visible retry"): return false
	if not await press("AcceptContract"): return false
	return expect(str(game.state.contract.case_id) == "service-0-case-0", "normal existing market accepts the daily-report work")

func projected(id: String) -> Dictionary:
	for row in ACCESS.project(game.diagnostic_probes()):
		if str(row.id) == id: return row
	return {}

func receipt_effect(receipt: Dictionary) -> bool:
	return expect(game.current_done() and str(receipt.rating) == "on_time" and int(receipt.satisfaction_after) > int(receipt.satisfaction_before), "actual on-time result changes customer trust")

func native_method() -> String:
	return "Genuine paid DAY6 source, naturally available daily-report case. New work uses Godot mouse/key input. Office Graphics applied. Background work clock paused; explicit work costs accrue. Wrong guest exposure blocks delivery, save failure rolls back PUT, retry and save/resume retain actual bytes and payment. No funds, skills, offers or answer injected. No first-time human participant."

func home() -> bool:
	if not await press("SambaCancel"): return false
	return expect(control("SambaAccessBoard") != null, "actual shared-folder paths return after edit")

func probe_all() -> bool:
	for id in ACCESS.IDS:
		if not await press("SambaAccess_" + id): return false
	return true

func settings_change(open_guest: bool) -> bool:
	if not await press("SambaEdit_share") or not await edit("SambaWriteList", "staff"): return false
	if open_guest:
		if not await edit("SambaValidUsers", "staff nobody") or not await press("SambaGuest"): return false
	else:
		if not await edit("SambaValidUsers", "staff") or not await press("SambaGuest"): return false
	if not await press("SambaSave") or not await press("SambaRestart"): return false
	return await home()

func run() -> void:
	game = root.get_node("Game")
	if not expect("--qa-profile=daily-report-native" in OS.get_cmdline_user_args() and game.save_path.begins_with("user://qa-"), "isolated ordinary-work QA"): finish(); return
	source_path = OS.get_environment("WHL_ORDINARY_FIXTURE"); source_text = FileAccess.get_file_as_string(source_path)
	var output := FileAccess.open(game.save_path, FileAccess.WRITE)
	if not expect(output != null and not source_text.is_empty(), "copy genuine paid previous-cycle checkpoint"): finish(); return
	output.store_string(source_text); output.close()
	if not expect(game.load_game() and int(game.state.day) == 6 and game.current_done(), "resume actual earned company"): finish(); return
	game.set_process(false)
	for offer in game.state.offers:
		if str(offer.case_id) == "service-0-case-0" and bool(offer.unlocked) and bool(offer.market_available): selected_offer = offer; break
	if not expect(not selected_offer.is_empty(), "daily report is naturally available without market or money injection"): finish(); return
	await build_ui(); ui.open_panel("sales"); await frames(10)
	if not await quote_journey() or not await press("DispatchOpen") or not await route("terminal"): finish(); return
	if not await edit_control(ui.desktop.widgets.terminal.command, "ssh client", "connect fictional report server"): finish(); return
	await tap(KEY_ENTER)
	initial_report = game.vm_read("/srv/share/report.txt"); daily_report = game.vm_read("/srv/data/report.txt"); orders_before = game.vm_read("/srv/data/orders.csv")
	if not expect(initial_report != daily_report and daily_report.contains("本日受付 12件"), "actual previous-day shared report differs from employee's current daily report"): finish(); return
	if not await route("browser") or not expect(text_in(control("SambaShare_share")).contains("report.txt"), "same actual report object appears in Cockpit"): finish(); return
	if not await probe_all() or not expect(projected("staff-write").status == "denied" and projected("guest-read").passed == true and game.vm_read("/srv/share/report.txt") == initial_report, "actual denied save preserves prior report and protected guest boundary"): finish(); return
	await capture("02-actual-report-save-denied")
	if not await settings_change(true) or not await probe_all(): finish(); return
	if not expect(projected("staff-write").passed == true and projected("guest-read").passed == false and game.vm_read("/srv/share/report.txt") == daily_report, "wrong broad permission fixes actual daily save but exposes private report to guest"): finish(); return
	if not await route("verify") or not await press("DiagnosticValidate") or not expect(not game.can_deliver(), "real verification rejects successful save with failed guest boundary"): finish(); return
	await capture("03-wrong-guest-exposure-blocks-delivery")
	var saved: Dictionary = game._vm().export_state()
	if not expect(ui.desktop._save_session() and game.save_game(), "save actual wrong decision and evidence"): finish(); return
	ui.queue_free(); await frames(6)
	if not expect(game.load_game() and same_values(game._vm().export_state(), saved), "resume retains report bytes and measured guest exposure without repair"): finish(); return
	game.set_process(false); await build_ui()
	if not await route("browser") or not await settings_change(false) or not await probe_all(): finish(); return
	if not expect(ACCESS.project(game.diagnostic_probes()).all(func(row): return bool(row.passed)) and game.vm_read("/srv/data/orders.csv") == orders_before and game.vm_read("/srv/share/report.txt") == daily_report, "repair restores four actual operations, writes daily report, and preserves unrelated orders"): finish(); return
	# Actual durable PUT save failure, with current evidence retained on the diagram.
	var before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var path: String = game.save_path
	game.save_path = "user://missing-daily-report-probe/save.json"
	var clicked := await press("SambaAccess_staff-write"); game.save_path = path
	if not clicked: finish(); return
	if not expect(same_values(game._vm().export_state(), before), "failed PUT persistence rolls back exact VM bytes and evidence"): finish(); return
	if not expect(int(game.state.cash) == cash, "failed PUT leaves company funds unchanged"): finish(); return
	if not expect(control("SambaAccessActionError") != null, "failed PUT persistence shows inline retry error"): finish(); return
	if not expect(clipped_rect(control("SambaAccessActionError")).grow(1).encloses(control("SambaAccessActionError").get_global_rect()), "whole error is visible without another scroll after action"): finish(); return
	await capture("04a-report-save-failure")
	if not await press("SambaAccess_staff-write") or not expect(control("SambaAccessActionError") == null and projected("staff-write").passed == true and ui.desktop.status.text == "測定を保存しました。", "same action retries report save and replaces previous failure notice"): finish(); return
	await capture("04-repaired-report-and-private-boundary")
	if not await route("verify") or not await press("DiagnosticValidate") or not expect(game.can_deliver(), "current real evidence enables delivery"): finish(); return
	if not await route("receipt") or not await press("GuideDeliver"): finish(); return
	var receipt: Dictionary = game.completion_receipt()
	if not receipt_effect(receipt): finish(); return
	if not await press("ReceiptFinanceTab") or not await press("ReceiptInvoice") or not await press("BillingPost"): finish(); return
	if not expect(game.company_invoices().any(func(row): return str(row.id) == str(receipt.invoice_id) and str(row.status) == "paid"), "accepted daily-report work reaches actual paid invoice"): finish(); return
	await capture("05-daily-work-paid")
	var result_state: Dictionary = game.state.duplicate(true)
	if not expect(game.save_game() and game.load_game() and same_values(game.state.history, result_state.history) and same_values(game.state.customer_relations, result_state.customer_relations) and same_values(game.state.last_receipt, result_state.last_receipt) and int(game.state.cash) == int(result_state.cash), "payment, customer consequence and decision history persist after save/resume"): finish(); return
	if not expect(FileAccess.get_file_as_string(source_path) == source_text, "prior earned source untouched"): finish(); return
	var completed := FileAccess.open(folder.path_join("completed.json"), FileAccess.WRITE)
	if completed != null: completed.store_string(JSON.stringify(game.state, "\t")); completed.close()
	journey_completed = true; finish()

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("daily-report journey stopped before paid result")
	var report := {"assertions":assertions,"clicks":clicks,"keys":keys,"scrolls":scrolls,"narrow":narrow,"failures":failures,"events":events,"method":native_method()}
	var file := FileAccess.open(folder.path_join("daily-report-native.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  ")); file.close()
	print("DAILY_REPORT_NATIVE_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " failures=", failures)
	if is_instance_valid(ui): ui.queue_free(); await frames(5)
	quit(0 if failures.is_empty() else 1)
