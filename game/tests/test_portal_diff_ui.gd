extends "res://tests/test_network_request_ui.gd"
## The source is a genuine completed, normally funded career. Only public day
## advance/acceptance prepares the new case; work uses real mouse/key dispatch.
const FILE := "/srv/share/partner-order.csv"
var source_text := ""
var cash_start := 0

func run() -> void:
	game = root.get_node("Game")
	if not expect("--qa-profile=portal-diff-ui" in OS.get_cmdline_user_args(), "isolated diff QA storage"): finish(); return
	var source := OS.get_environment("WHL_DIFF_CAREER_FIXTURE")
	source_text = FileAccess.get_file_as_string(source)
	if not expect(not source_text.is_empty() and game.save_path.begins_with("user://qa-"), "ordinary completed career source copied only to QA"): finish(); return
	var file := FileAccess.open(game.save_path, FileAccess.WRITE)
	if not expect(file != null, "open isolated career copy"): finish(); return
	file.store_string(source_text); file.close()
	if not expect(game.load_game() and game.current_done() and int(game.state.day) == 2, "load genuine completed day two career"): finish(); return
	game.set_process(false)
	cash_start = int(game.state.cash)
	if not expect(game.end_day() and game.end_day(), "two public day settlements reach day four"): finish(); return
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked", false)) and bool(item.get("market_available", false)) and str(item.get("case_id", "")) == "service-5-case-1")
	if not expect(not offers.is_empty() and game.choose_contract(str(offers[0].id)), "accept naturally available sharing expiry contract"): finish(); return
	game.inspect_mission()
	record("setup_api", "Copy of real completed funded career; public day settlements/available sharing acceptance. No cash, skills, answers or VM overrides. Background clock paused, action costs retained.")
	await build_ui()
	if not await route("terminal") or not await press("TerminalConnect"): finish(); return
	if not await route("browser"): finish(); return
	var original: String = game._vm().portal_storage_read(FILE)
	if not await staff_read(): finish(); return
	if not await ensure_editor() or not await edit("PortalCell_1_2", "12900") or not await press("PortalWrite"): finish(); return
	if not expect(str(ui.desktop.portal_ui.response).begins_with("HTTP/1.1 200") and game._vm().portal_storage_read(FILE).contains("12900"), "real staff PUT changes stored order total"): finish(); return
	await capture("01-staff-update")
	if not await compare_original(): finish(); return
	if not await press("PortalDiffNext") or not await keyboard_activate("PortalDiffNext"): finish(); return
	if not await visible_change(): finish(); return
	await capture("02-aligned-actual-change")
	var machine: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
	for _i in 3: ui.desktop._render_portal(); await frames(5)
	if not expect(game._vm().export_state() == machine and int(game.state.cash) == cash and game.business_clock() == clock, "comparison rendering never rewrites files, history, measurements or costs"): finish(); return
	if not await press("PortalDiffShowAll"): finish(); return
	if not expect(control("PortalVersionDiffGrid").get_meta("comparison").rows.size() == 2 and text_in(control("PortalVersionDiffGrid")).contains("Minato Foods"), "explicit all rows reveals unchanged business record"): finish(); return
	if not await press("PortalDiffShowAll"): finish(); return
	var version: Dictionary = game._vm().portal_snapshot().versions.back()
	var valid_path: String = game.save_path
	game.save_path = "user://missing-portal-diff-%d/save.json" % OS.get_process_id()
	var restore_clicked: bool = await press("PortalVersionRestore_" + str(version.id))
	game.save_path = valid_path
	if not restore_clicked: finish(); return
	if not expect(game._vm().export_state() == machine and int(game.state.cash) == cash and game.business_clock() == clock and text_in(ui.desktop.widgets.browser.page).contains("保存に失敗"), "failed restore keeps exact file/history/time/cash and shows failure"): finish(); return
	await capture("03-restore-save-failure")
	if not await press("PortalVersionPreview_" + str(version.id)) or not await press("PortalVersionRestore_" + str(version.id)): finish(); return
	if not expect(game._vm().portal_storage_read(FILE) == original and game._vm().portal_snapshot().versions.size() == 2, "retry restores exact saved bytes and records replaced content for undo"): finish(); return
	if not await staff_read(): finish(); return
	if not expect(str(ui.desktop.portal_ui.preview_content) == original, "recipient GET sees restored canonical content"): finish(); return
	if not await ensure_editor() or not await edit("PortalCell_1_2", "12910"): finish(); return
	if not expect(ui.desktop._save_session() and game.save_game(), "save unpublished recipient draft independently of restored file"): finish(); return
	ui.queue_free(); await frames(6)
	if not expect(game.load_game(), "reload interrupted real QA save"): finish(); return
	game.set_process(false); await build_ui()
	if not await route("browser"): finish(); return
	if not expect(game._vm().portal_storage_read(FILE) == original and str(ui.desktop.portal_ui.get("preview_content", "")).contains("12910") and bool(ui.desktop.portal_ui.get("draft_dirty", false)), "resume preserves pending draft and exact committed file separately"): finish(); return
	await capture("04-resumed-draft")
	if not await press("PortalCancel") or not await press("PortalRole_partner") or not await select_option("PortalIdentity", 2) or not await press("PortalRead"): finish(); return
	if not await ensure_editor() or not await edit("PortalCell_1_2", "12920") or not await press("PortalWrite"): finish(); return
	if not expect(str(ui.desktop.portal_ui.response).begins_with("HTTP/1.1 403") and game._vm().portal_storage_read(FILE) == original and bool(ui.desktop.portal_ui.draft_dirty), "read-only recipient cannot update restored file and keeps retry input"): finish(); return
	await capture("05-read-only-rejection")
	if not await press("PortalCancel") or not await press("PortalNav_all"): finish(); return
	if not shown("PortalShare_partner") and not await press("PortalShareFile_0"): finish(); return
	if not await press("PortalShare_partner") or not await select_option("PortalExpiry_partner", 1) or not await press("PortalApply_partner"): finish(); return
	if not expect(str(game._vm().state.applied.expires) == "7d", "actual sharing save repairs only expiry condition"): finish(); return
	if not await route("verify"): finish(); return
	var ids: Array[String] = []
	for probe in game.diagnostic_probes(): ids.append(str(probe.id))
	for id in ids:
		if not await press("DiagnosticProbe_" + id) or not await press("DiagnosticRun"): finish(); return
	if not await press("DiagnosticValidate") or not expect(game.can_deliver(), "fresh actual service and file measurements permit delivery"): finish(); return
	if not await press("GuideDeliver") or not await press("ReceiptEvaluationTab"): finish(); return
	if not expect(game.current_done(), "sharing job is delivered after real operations"): finish(); return
	await capture("06-customer-result")
	if not await press("ReceiptFinanceTab") or not await press("ReceiptInvoice") or not await press("BillingPost"): finish(); return
	var receipt: Dictionary = game.completion_receipt()
	if not expect(int(game.state.cash) > cash_start and not str(receipt.get("invoice_id", "")).is_empty(), "invoice posting brings actual payment into normal company cash"): finish(); return
	await capture("07-invoice-paid")
	if not expect(FileAccess.get_file_as_string(source) == source_text, "original career fixture remains byte identical"): finish(); return
	journey_completed = true; finish()

func build_ui() -> void:
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui = INTERFACE.new(); root.add_child(ui); await frames(10)
	ui._set_text_scale(1.3 if narrow else 1.0); ui.controls.menu.hide(); ui.next_task_guide.set_enabled(false); ui.open_panel("terminal"); await frames(10)
	root.grab_focus()

func staff_read() -> bool:
	if not await press("PortalNav_all"): return false
	if not shown("PortalPreview") and not await press("PortalShareFile_0"): return false
	return await press("PortalPreview") and await press("PortalRole_staff") and await select_option("PortalIdentity", 3) and await press("PortalRead")

func ensure_editor() -> bool:
	var field := control("PortalCell_1_2")
	return true if is_instance_valid(field) and field.is_visible_in_tree() else await press("PortalEditRows")

func shown(id: String) -> bool:
	var node := control(id)
	return is_instance_valid(node) and node.is_visible_in_tree()

func select_option(id: String, index: int) -> bool:
	var option := control(id) as OptionButton
	if not expect(is_instance_valid(option) and index < option.item_count, id + " actual choices exist"): return false
	if not await press(id): return false
	var popup := option.get_popup()
	if not expect(popup.visible, id + " native popup opened"): return false
	await tap(KEY_HOME)
	for _attempt in option.item_count + 1:
		if popup.get_focused_item() == index: break
		await tap(KEY_DOWN)
	if not expect(popup.get_focused_item() == index, id + " keyboard reached choice"): return false
	await tap(KEY_ENTER)
	# Portal commits rebuild its page. Inspect the replacement control, never
	# the released popup/option from before the real key was dispatched.
	var committed := control(id) as OptionButton
	return expect(is_instance_valid(committed) and committed.selected == index and not committed.get_popup().visible, id + " keyboard committed choice")

func compare_original() -> bool:
	if not await press("PortalNav_all"): return false
	if not shown("PortalDetailVersions") and not await press("PortalShareFile_0"): return false
	if not await press("PortalDetailVersions"): return false
	var version: Dictionary = game._vm().portal_snapshot().versions.back()
	if not await press("PortalVersionPreview_" + str(version.id)): return false
	var table = control("PortalVersionDiffGrid")
	return expect(table is GridContainer and table.columns == 4 and int(table.get_meta("comparison").counts.changed) == 1, "one changed order shares three aligned data columns")

func visible_change() -> bool:
	var table = control("PortalVersionDiffGrid")
	for caption in control("PortalDiffSummary").get_children():
		if not expect(caption.get_line_count() == 1 and caption.size.x >= caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x - 1, "actual summary label fits without wrapping or hiding its meaning"): return false
	if not expect(control("PortalDiffNext").size.y <= 48 * float(game.settings.text_scale), "comparison action retains bounded height"): return false
	for cell in table.get_children():
		if bool(cell.get_meta("diff_change", false)) and str(cell.get_meta("before", "")) == "12800":
			return expect(str(cell.get_meta("after", "")) == "12900" and clipped_rect(cell).encloses(cell.get_global_rect()) and text_in(cell).contains("− 12800") and text_in(cell).contains("＋ 12900"), "changed money is fully visible with before/after symbols in one cell")
	return expect(false, "actual changed amount cell exists")

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("sharing comparison journey incomplete")
	var report := {"assertions":assertions,"narrow":narrow,"clicks":clicks,"keys":keys,"scrolls":scrolls,"failures":failures,"events":events,"cash":game.state.get("cash",0) if game != null else 0,"method":"Genuine funded career copy, public day advancement and actual available acceptance setup; actual Godot mouse/key for recipient edit/PUT, comparison, restore failure/retry, sharing repair, diagnostics, delivery and payment. Save-path fault injection and save/load API exercise interruption. No answer/skill/cash/VM overrides. Known controls; not first-time human proof."}
	var file := FileAccess.open(folder.path_join("portal-diff-native.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"  ")); file.close()
	print("PORTAL_DIFF_UI_", "PASS" if failures.is_empty() else "FAIL", " assertions=",assertions," clicks=",clicks," keys=",keys," scrolls=",scrolls," failures=",failures)
	if is_instance_valid(ui): ui.queue_free(); await frames(5)
	quit(0 if failures.is_empty() else 1)
