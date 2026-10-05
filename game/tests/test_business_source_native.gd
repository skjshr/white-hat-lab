extends "res://tests/test_portal_diff_ui.gd"
## Genuine funded DAY5 lead; setup accepts only an actually available case.
## Work, bad data, rollback, diagnostics, delivery and payment use native input.
const SALES := "https://intranet.client.test/sales"

func qa_profile() -> String: return "business-source-native"
func report_name() -> String: return "business-source-native"

func control(id: String) -> Control:
	if id == "NativeTargetSelector" and is_instance_valid(ui) and is_instance_valid(ui.desktop): return ui.desktop.target_selector
	return super.control(id)

func run() -> void:
	game = root.get_node("Game")
	if not expect("--qa-profile=" + qa_profile() in OS.get_cmdline_user_args(), "isolated business-source QA storage"): finish(); return
	var source := OS.get_environment("WHL_BRANCH_CAREER_FIXTURE")
	source_text = FileAccess.get_file_as_string(source)
	if not expect(not source_text.is_empty() and game.save_path.begins_with("user://qa-"), "genuine completed funded career copied only to QA"): finish(); return
	var file := FileAccess.open(game.save_path, FileAccess.WRITE)
	if not expect(file != null, "open isolated career output"): finish(); return
	file.store_string(source_text); file.close()
	if not expect(game.load_game() and int(game.state.day) == 5, "load actual public day-settlement checkpoint"): finish(); return
	game.set_process(false); cash_start = int(game.state.cash)
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked", false)) and bool(item.get("market_available", false)) and str(item.get("case_id", "")) == "composite-branch-reopen")
	if not expect(not offers.is_empty() and game.choose_contract(str(offers[0].id)), "accept naturally available branch reopening lead"): finish(); return
	game.inspect_mission()
	record("setup_api", "Actual funded DAY5 career reached with public day settlements; public available offer acceptance. Background clock paused, explicit work costs retained. No answers/cash/skill/VM injection.")
	await build_ui()
	if not await connect_machine(0) or not await browse(SALES): finish(); return
	var initial_reply: Variant = JSON.parse_string(ui.desktop.browser_response)
	if not expect(initial_reply is Dictionary and bool(initial_reply.get("transport_error", false)) and str(initial_reply.get("raw", "")).begins_with("curl:"), "normal business is initially blocked before an HTTP response"): finish(); return
	await capture("01-normal-business-blocked")
	if not await browse(ui.desktop.FIREWALL_URL) or not await press("FirewallTab_lan"): finish(); return
	var rule_ids: Array[String] = []
	for rule in game._vm().firewall_snapshot().rules:
		if str(rule.description) in ["Business HTTPS", "Business HTTP"]: rule_ids.append(str(rule.id))
	if not expect(rule_ids.size() == 2, "existing business rules selected while WAN management remains blocked"): finish(); return
	for id in rule_ids:
		if not await press("FirewallEdit_" + id) or not await select_option("FirewallEditor_action", 0) or not await press("FirewallSave"): finish(); return
	if not await press("FirewallApply") or not await browse(SALES): finish(); return
	if not expect(ui.desktop.browser_response.contains("provider_unavailable"), "HTTP now reaches business server and exposes separate source-share outage"): finish(); return
	if not await source_visible("files01.client.test", "partner-order.csv"): finish(); return
	if not expect(text_in(control("BusinessSourceStageStatus1")).contains("接続不可") and text_in(control("BusinessSourceStageStatus2")).contains("未確認") and text_in(control("BusinessSourceStageStatus3")).contains("未取得"), "failed source does not pretend to inspect file or business records"): finish(); return
	await capture("02-source-share-unavailable")
	if not await press("BusinessSourceDetailsToggle"): finish(); return
	if not expect(control("BusinessSourceDetails").is_visible_in_tree() and text_in(control("BusinessSourceDetails")).contains("/srv/share/partner-order.csv") and text_in(control("BusinessSourceDetails")).contains("provider_unavailable"), "on-demand details show actual full path and response failure"): finish(); return
	await capture("02a-source-details")
	if not await keyboard_activate("BusinessSourceDetailsToggle") or not expect(not control("BusinessSourceDetails").is_visible_in_tree(), "native Enter closes source details"): finish(); return
	if not await connect_machine(1) or not await browse(ui.desktop.SAMBA_URL) or not await press("SambaShare_share"): finish(); return
	for spec in [["SambaAvailable", true], ["SambaReadOnly", true], ["SambaGuest", false]]:
		if not await set_toggle(str(spec[0]), bool(spec[1])): finish(); return
	for spec in [["SambaPath", "/srv/share"], ["SambaValidUsers", "staff"], ["SambaInvalidUsers", ""], ["SambaWriteList", "staff"], ["SambaReadList", ""]]:
		if not await edit(str(spec[0]), str(spec[1])): finish(); return
	var before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
	var valid_path: String = game.save_path
	game.save_path = "user://missing-business-source-%d/save.json" % OS.get_process_id()
	var clicked: bool = await press("SambaSave")
	game.save_path = valid_path
	if not clicked: finish(); return
	if not expect(game._vm().export_state() == before and int(game.state.cash) == cash and game.business_clock() == clock, "failed share save preserves actual VM/time/funds for retry"): finish(); return
	await capture("03-share-save-failed")
	if not await press("SambaSave") or not await press("SambaTest") or not await press("SambaRestart"): finish(); return
	if not expect(game.vm_read(FILE).contains("12800"), "source-share repair preserves original business amount"): finish(); return
	if not await connect_machine(0) or not await refresh_sales(): finish(); return
	if not expect(ui.desktop.browser_response.contains("12800") and control("BusinessOrderList") != null, "ERP reads the actual recovered shared order"): finish(); return
	if not await source_visible("files01.client.test", "partner-order.csv"): finish(); return
	if not expect(text_in(control("BusinessSourceStageStatus2")).contains("読取済") and text_in(control("BusinessSourceStageStatus3")).contains("受注"), "actual readable file and fetched business count are separate stages"): finish(); return
	await capture("04-orders-from-recovered-source")
	if not await connect_machine(2) or not await browse(ui.desktop.PORTAL_URL) or not await staff_read() or not await ensure_editor(): finish(); return
	var original: String = game._vm().portal_storage_read(FILE)
	if not await edit("PortalCell_1_2", "broken") or not await press("PortalWrite"): finish(); return
	if not expect(str(ui.desktop.portal_ui.response).begins_with("HTTP/1.1 200") and game._vm().portal_storage_read(FILE).contains("broken"), "real staff PUT saves parse-invalid business data as a new version"): finish(); return
	if not await connect_machine(0) or not await refresh_sales(): finish(); return
	if not expect(ui.desktop.browser_response.contains("malformed_orders_row") and control("BusinessOrderList") == null, "ERP cannot display invalid amount despite readable shared storage"): finish(); return
	if not await source_visible("files01.client.test", "partner-order.csv"): finish(); return
	if not expect(text_in(control("BusinessSourceStageStatus1")).contains("応答あり") and text_in(control("BusinessSourceStageStatus2")).contains("読取済") and text_in(control("BusinessSourceStageStatus3")).contains("異常"), "readable provider/file stays distinct from parse-invalid business record"): finish(); return
	await capture("05-readable-source-invalid-record")
	if not await connect_machine(2) or not await browse(ui.desktop.PORTAL_URL) or not await compare_original(): finish(); return
	var version: Dictionary = game._vm().portal_snapshot().versions.back()
	if not await press("PortalVersionRestore_" + str(version.id)): finish(); return
	if not expect(game._vm().portal_storage_read(FILE) == original, "explicit version restore recovers the actual source bytes"): finish(); return
	if not await connect_machine(0) or not await refresh_sales(): finish(); return
	if not expect(ui.desktop.browser_response.contains("12800") and control("BusinessOrderList") != null, "ERP fresh GET reflects restore performed through another software"): finish(); return
	if not await browse("https://intranet.client.test/customers") or not await source_visible("files01.client.test", "customers.csv"): finish(); return
	await capture("06-customers-use-their-own-source")
	if not await browse("https://intranet.client.test/accounting") or not await source_visible("業務API", "ledger.txt"): finish(); return
	if not expect(ui.desktop.browser_response.contains("missing_file") and not text_in(control("BusinessSourceFlow")).contains("partner-order.csv"), "missing ledger remains a distinct missing file instead of pretending to use orders"): finish(); return
	await capture("07-missing-ledger-is-not-orders")
	if not await browse(SALES): finish(); return
	if not expect(ui.desktop._save_session() and game.save_game(), "save real recovered source and browser checkpoint"): finish(); return
	ui.queue_free(); await frames(6)
	if not expect(game.load_game(), "reload interrupted genuine career save"): finish(); return
	game.set_process(false); await build_ui()
	if not await route("browser") or not await source_visible("files01.client.test", "partner-order.csv"): finish(); return
	if not expect(ui.desktop.browser_response.contains("12800"), "resume keeps last fetched source and actual restored order"): finish(); return
	await capture("08-resumed-source-and-order")
	if not await connect_machine(2) or not await browse(ui.desktop.PORTAL_URL) or not await press("PortalNav_all"): finish(); return
	if not shown("PortalShare_partner") and not await press("PortalShareFile_0"): finish(); return
	for role in ["partner", "public"]:
		if not await press("PortalShare_" + role) or not await select_option("PortalPermission_" + role, 1 if role == "partner" else 0) or not await select_option("PortalExpiry_" + role, 1 if role == "partner" else 0) or not await press("PortalApply_" + role): finish(); return
	for index in 3:
		if not await connect_machine(index) or not await route("verify"): finish(); return
		var ids: Array[String] = []
		for probe in game.diagnostic_probes(): ids.append(str(probe.id))
		# SMB PUT changes the directory and expires earlier read measurements.
		# Write first, then collect fresh read and access-denial evidence.
		if "staff-write" in ids: ids.erase("staff-write"); ids.push_front("staff-write")
		for id in ids:
			if not await press("DiagnosticProbe_" + id) or not await press("DiagnosticRun"): finish(); return
		if not await press("DiagnosticValidate"): finish(); return
	if not expect(game.can_deliver(), "all three services have fresh actual normal-use and access-denial measurements"): finish(); return
	if not await press("GuideDeliver") or not await press("ReceiptEvaluationTab"): finish(); return
	await capture("09-branch-customer-result")
	if not await press("ReceiptFinanceTab") or not await press("ReceiptInvoice") or not await press("BillingPost"): finish(); return
	if not expect(game.current_done() and int(game.state.cash) > cash_start, "actual branch delivery and payment grow normally funded company"): finish(); return
	await capture("10-branch-invoice-paid")
	if not expect(FileAccess.get_file_as_string(source) == source_text, "original available career checkpoint stays byte identical"): finish(); return
	journey_completed = true; finish()

func connect_machine(index: int) -> bool:
	if int(game.state.target_index) != index and not await select_option("NativeTargetSelector", index): return false
	if not await route("terminal"): return false
	return await press("TerminalConnect") if shown("TerminalConnect") else expect(bool(game._vm().state.connected), "return to already connected actual customer host")

func browse(url: String) -> bool:
	if not await route("browser") or not await edit("BrowserAddress", url): return false
	await tap(KEY_ENTER); await frames(10)
	return expect(str(ui.desktop.browser_url) == url, "real address submission fetches " + url)

func refresh_sales() -> bool:
	if not await route("browser"): return false
	if str(ui.desktop.browser_url) != SALES or not shown("BusinessStorageRefresh"): return await browse(SALES)
	return await press("BusinessStorageRefresh")

func set_toggle(id: String, enabled: bool) -> bool:
	var checkbox := control(id) as BaseButton
	if not expect(is_instance_valid(checkbox), "actual sharing toggle " + id): return false
	return true if checkbox.button_pressed == enabled else await press(id)

func source_visible(host: String, file_name: String) -> bool:
	var flow := control("BusinessSourceFlow")
	if not expect(is_instance_valid(flow) and flow.is_visible_in_tree(), "source flow exists in failure and success"): return false
	if not await scroll_to(flow): return false
	var displayed := text_in(flow)
	if not expect(displayed.contains(host) and displayed.contains(file_name), "actual provider and distinct resource are displayed"): return false
	if not expect(text_in(control("BusinessSourceStage1")).contains(host) and text_in(control("BusinessSourceStageDetail2")).contains(file_name), "provider and file are visible in the diagram itself"): return false
	var area := root.get_visible_rect().grow(1)
	for label in flow.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree(): continue
		if not expect(label.get_global_rect().position.x >= area.position.x and label.get_global_rect().end.x <= area.end.x, "source caption remains within horizontal viewport at actual text scale"): return false
		if not expect(label.get_theme_font_size("font_size") >= int(14 * float(game.settings.text_scale)), "source diagram respects enlarged readable font size"): return false
		if not expect(label.get_line_count() == 1, "visible source caption stays on a readable single line"): return false
		var natural_width: float = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		if not expect(label.size.x + 1 >= natural_width, "visible source caption fits its allocated width"): return false
	for id in ["BusinessSourceStatus", "BusinessSourceLastFetch"]:
		var caption := control(id) as Label
		var natural := caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
		if not expect(caption.size.x + 1 >= natural, "source status and last-fetch text fit without clipping"): return false
	if not expect(control("BusinessStorageRefresh").size.y <= 48 * float(game.settings.text_scale), "source refresh action has a bounded visible height"): return false
	var before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
	ui.desktop._render_business_workspace(); await frames(8)
	return expect(game._vm().export_state() == before and int(game.state.cash) == cash and game.business_clock() == clock, "source redraw never repairs, measures, or changes company funds/time")

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("business source journey incomplete")
	var report := {"assertions":assertions,"narrow":narrow,"clicks":clicks,"keys":keys,"scrolls":scrolls,"failures":failures,"events":events,"cash":game.state.get("cash",0) if game != null else 0,"method":"Actual funded DAY5 public settlement checkpoint; public available acceptance setup. Actual Godot mouse/key for firewall/share repair, save failure/retry, invalid shared amount, version restore, ERP reload, all three targets' diagnostics, delivery and payment. Save/load API tests interruption. No answer/cash/skill/VM state injection. Known controls; not first-time player proof."}
	var file := FileAccess.open(folder.path_join(report_name() + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  ")); file.close()
	print("BUSINESS_SOURCE_NATIVE_", "PASS" if failures.is_empty() else "FAIL", " assertions=",assertions," clicks=",clicks," keys=",keys," scrolls=",scrolls," failures=",failures)
	if is_instance_valid(ui): ui.queue_free(); await frames(5)
	quit(0 if failures.is_empty() else 1)
