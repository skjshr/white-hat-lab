extends "res://tests/test_network_request_ui.gd"
## Reuse input/geometry helpers. Career entry, pause and reload are public API
## fixtures. Acceptance, failing request, cancellation, overnight, repair and
## delivery use actual mouse/key dispatch. No answer or balance overrides.

var closed_id := ""
var archive_before: Dictionary = {}

func same_saved_data(a: Variant, b: Variant) -> bool:
	# JSON loading turns integer variants into floats; retain every field/value.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func available_network_offer() -> Dictionary:
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == "service-2-case-0" and bool(offer.unlocked) and bool(offer.market_available): return offer
	return {}

func accept_network() -> bool:
	var offer := available_network_offer()
	if not expect(not offer.is_empty(), "naturally available network contract"): return false
	if not await press("SalesOffer_" + str(offer.id).replace("/", "_")): return false
	if not await press("AcceptContract"): return false
	if not expect(game.state.accepted and str(game.state.current_contract_id) == str(offer.id), "native quote send accepts authored offer"): return false
	return await press("DispatchOpen")

func connect_and_request() -> bool:
	if not await route("terminal"): return false
	if not await edit_control(ui.desktop.widgets.terminal.command, "ssh client", "customer connection"): return false
	await tap(KEY_ENTER)
	if not expect(bool(game.vm_info().connected), "native connection to fictional customer"): return false
	if not await route("browser"): return false
	if not await edit("BrowserAddress", BUSINESS_URL): return false
	await tap(KEY_ENTER)
	return await press("NetworkRequestTest")

func receipt() -> bool:
	if ui.desktop.current_app == "receipt": return true
	if control("TaskbarApp_receipt") != null and control("TaskbarApp_receipt").is_visible_in_tree(): return await press("TaskbarApp_receipt")
	if not await press("StartButton"): return false
	return await press("StartApp_receipt")

func check_numbers() -> bool:
	for id in ["報酬", "経費", "現金", "顧客満足度", "信用"]:
		var value := control("CloseoutValue_" + id) as Label
		if not expect(value != null and value.is_visible_in_tree() and value.get_line_count() == 1 and value.size.x >= value.get_minimum_size().x, "single-line untruncated closeout value " + id): return false
		if not await scroll_to(value): return false
		if not expect(clipped_rect(value).grow(1).encloses(value.get_global_rect()), "full numeric value reachable " + id): return false
	for id in ["CloseoutContinue", "CloseoutConfirm"]:
		var action := control(id)
		if not expect(action != null and clipped_rect(action).grow(1).encloses(action.get_global_rect()), "persistent footer action visible " + id): return false
	return true

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	if not expect(str(game.save_path).begins_with("user://qa-"), "isolated save"): finish(); return
	if not expect(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(), "normal-funded free-career setup"): finish(); return
	game.set_process(false)
	ui = INTERFACE.new(); root.add_child(ui); await frames()
	ui.guided_intro.skip(); ui.next_task_guide.set_enabled(false)
	var scale := 1.3 if narrow else 1.0
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed" if narrow else "borderless", "text_scale":scale, "volume":0}, false)
	ui._set_text_scale(scale); root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	root.get_node("Graphics").apply_settings(game.settings); root.grab_focus()
	ui.controls.menu.hide(); ui.open_panel("sales"); await frames()
	if not expect(int(game.state.cash) == 5000, "ordinary starting cash"): finish(); return
	if not await accept_network(): finish(); return
	if not await connect_and_request(): finish(); return
	if not expect(not bool(game.network_request_view(BUSINESS_URL).passed), "actual customer request fails before cancellation"): finish(); return
	await capture("01-failed-business")
	if not await receipt(): finish(); return
	if not ui.desktop.windows.receipt.maximized: ui.desktop.windows.receipt.toggle_maximize()
	await frames()
	var before_preview := JSON.stringify(game.state)
	game.contract_closeout_preview(); game.contract_closeout_preview()
	if not expect(JSON.stringify(game.state) == before_preview, "preview does not charge or alter customer state"): finish(); return
	if not await press("CloseoutOpen"): finish(); return
	if not await check_numbers(): finish(); return
	await capture("02-cost-and-trust-preview")
	var before_back := JSON.stringify(game.state)
	if not await keyboard_activate("CloseoutContinue"): finish(); return
	if not expect(JSON.stringify(game.state) == before_back and bool(game.state.accepted), "continuing work preserves contract and balance"): finish(); return
	# Public interruption/save/reload, retaining real failing VM observations.
	var failed_request: Dictionary = game.network_request_view(BUSINESS_URL).duplicate(true)
	ui.open_panel("board"); await frames(); ui.open_panel("terminal"); await frames()
	if not expect(game.save_game() and game.load_game(), "interrupted accepted work saves and resumes"): finish(); return
	ui.desktop._reload_contract_session(); await frames()
	if not expect(same_saved_data(game.network_request_view(BUSINESS_URL), failed_request), "resume preserves actual failing observations"): finish(); return
	if not await receipt(): finish(); return
	if not ui.desktop.windows.receipt.maximized: ui.desktop.windows.receipt.toggle_maximize()
	await frames()
	if not await press("CloseoutOpen"): finish(); return
	var valid_path: String = game.save_path
	ui.desktop._save_session(false)
	var before_failure: Dictionary = game.state.duplicate(true)
	var vm_before_failure: Dictionary = game._vm().export_state()
	game.save_path = "user://closeout-ui-missing-" + str(OS.get_process_id()) + "/save.json"
	if not await press("CloseoutConfirm"): finish(); return
	if not expect(game.state == before_failure and game._vm().export_state() == vm_before_failure, "failed save keeps exact live contract balance and VM"): finish(); return
	if not expect(control("CloseoutError") != null and (control("CloseoutError") as Label).text.contains("保存失敗"), "inline error explains retry"): finish(); return
	if not expect(clipped_rect(control("CloseoutError")).grow(1).encloses(control("CloseoutError").get_global_rect()), "save failure is fully visible beside retry actions"): finish(); return
	await capture("03-persistence-failure")
	game.save_path = valid_path
	var preview: Dictionary = game.contract_closeout_preview()
	closed_id = str(preview.id)
	if not await press("CloseoutConfirm"): finish(); return
	if not expect(control("CloseoutResult") != null and not game.state.accepted and int(game.state.cash) == int(preview.cash_after), "native retry closes without delivery reward"): finish(); return
	archive_before = game.state.contract_closeouts[closed_id].duplicate(true)
	if not expect(int(game.state.contracts_completed) == 0 and game.state.completed_ids.is_empty() and game.state.billing.invoices.is_empty(), "no completion XP or invoice"): finish(); return
	await capture("04a-cancelled-overview")
	if not await press("CloseoutArchiveToggle"): finish(); return
	if not expect(clipped_rect(control("CloseoutArchive")).grow(1).encloses(control("CloseoutArchive").get_global_rect()), "explicit archive disclosure reveals readable inspection area"): finish(); return
	var archived: Variant = JSON.parse_string((control("CloseoutArchive") as TextEdit).text)
	if not expect(same_saved_data(archived, archive_before), "optional inspection shows exact retained context and VM"): finish(); return
	await capture("04-cancelled-result")
	if not await press("CloseoutHistory"): finish(); return
	var mail_row: Button = null
	for candidate in ui.desktop.widgets.mail.list.find_children("*", "Button", true, false):
		if text_in(candidate).contains("中止・未完了"): mail_row = candidate; break
	if not await press_control(mail_row, "cancelled customer history"): finish(); return
	if not expect(control("MailCancellationResult") != null and not text_in(control("MailHistoryContent")).contains("納品済み"), "history clearly distinguishes cancelled unfinished work"): finish(); return
	if not expect(clipped_rect(control("MailCancellationResult")).grow(1).encloses(control("MailCancellationResult").get_global_rect()), "cancelled outcome visible before original request text"): finish(); return
	await capture("05-customer-history")
	if not expect(game.save_game() and game.load_game() and same_saved_data(game.state.contract_closeouts[closed_id], archive_before), "cancelled outcome and costs survive reload"): finish(); return
	ui.desktop._reload_contract_session(); await frames()
	if not await receipt(): finish(); return
	if not expect(control("CloseoutResult") != null, "resumed receipt remains cancelled"): finish(); return
	if not await press("CloseoutNext"): finish(); return
	if not expect(not game.contract_queue().any(func(item): return str(item.id) == closed_id), "cancelled job leaves operations capacity"): finish(); return
	if not await press("ManagementTab_sales"): finish(); return
	if not expect(available_network_offer().is_empty(), "same day cannot erase failure by reaccepting"): finish(); return
	if not await press("ManagementTab_board"): finish(); return
	if not await press("OperationsCloseDay"): finish(); return
	if not expect(int(game.day_preview().contract_net) == -int(preview.costs), "daily statement retains actual cancellation loss"): finish(); return
	await capture("06-daily-loss")
	if not await press("DaySettle"): finish(); return
	if not expect(int(game.state.day) == 2 and same_saved_data(game.state.contract_closeouts[closed_id], archive_before), "overnight retains failed contract archive"): finish(); return
	if not await press("ManagementTab_sales"): finish(); return
	if not expect(not available_network_offer().is_empty() and str(available_network_offer().id) != closed_id, "next-day authored retry has new contract identity"): finish(); return
	if not await accept_network(): finish(); return
	if not await connect_and_request(): finish(); return
	if not expect(not bool(game.network_request_view(BUSINESS_URL).passed), "retry begins with original fault, not archived repaired state"): finish(); return
	if not await press("NetworkRequestSettings"): finish(); return
	if not await select_option("FirewallDNS", 1): finish(); return
	if not await press("FirewallServicesSave"): finish(); return
	if not await press("FirewallApply"): finish(); return
	if not await press("NetworkRequestReturn"): finish(); return
	if not await press("NetworkRequestTest"): finish(); return
	if not expect(bool(game.network_request_view(BUSINESS_URL).passed), "native retry repairs actual business and protective request"): finish(); return
	await capture("07-retry-business-restored")
	if not await route("verify"): finish(); return
	if not await press("DiagnosticValidate"): finish(); return
	if not await press("GuideDeliver"): finish(); return
	if not expect(game.current_done() and int(game.state.contracts_completed) == 1 and same_saved_data(game.state.contract_closeouts[closed_id], archive_before), "only successful retry completes while old failure remains"): finish(); return
	await capture("08-successful-retry-result")
	if not expect(game.save_game() and game.load_game() and game.current_done() and same_saved_data(game.state.contract_closeouts[closed_id], archive_before), "final delivery and earlier failure both persist"): finish(); return
	journey_completed = true; finish()

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("journey ended before successful retry")
	var report := {"assertions":assertions,"failures":failures,"narrow":narrow,"clicks":clicks,"keys":keys,"scrolls":scrolls,"events":events,"cash":game.state.cash if game != null else 0,"closed_id":closed_id,"method":"Public normal-funded career/display setup; background paused. Real mouse/key acceptance, request, cancellation, overnight, repair, delivery. Save path fault injection and public interruption/reload. Source-inspected IDs; no human usability test."}
	var file := FileAccess.open(folder.path_join("closeout-native.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  ")); file.close()
	print("CAREER_CLOSEOUT_UI assertions=", assertions, " failures=", failures, " clicks=", clicks, " keys=", keys, " scrolls=", scrolls)
	quit(0 if failures.is_empty() else 1)
