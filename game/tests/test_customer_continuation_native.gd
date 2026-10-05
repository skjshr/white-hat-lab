extends "res://tests/test_receipt_outcome_native.gd"
const HANDOFF = preload("res://scripts/branch_handoff.gd")
var continuation_receipt: Dictionary = {}
func qa_profile() -> String: return "customer-continuation-native"
func report_name() -> String: return "customer-continuation-native"
func journey_timeout() -> float: return 600.0

func build_ui() -> void:
	await super.build_ui()
	# The normal Office applies Graphics, which uses real window pixels below
	# 1280x720. The standalone host must apply that same public display setup.
	root.get_node("Graphics").apply_settings(game.settings); await frames(10)
	record("display_setup", "Office Graphics applied; pixels=" + str(root.size) + " logical=" + str(root.get_visible_rect().size) + " text=" + str(game.settings.text_scale))

func run() -> void:
	if "--continuation-only" not in OS.get_cmdline_user_args(): await super.run(); return
	game = root.get_node("Game")
	if not expect("--qa-profile=" + qa_profile() in OS.get_cmdline_user_args() and game.save_path.begins_with("user://qa-"), "isolated continuation-only debugging"): finish(); return
	var source := OS.get_environment("WHL_HANDOFF_FIXTURE")
	source_text = FileAccess.get_file_as_string(source)
	var file := FileAccess.open(game.save_path, FileAccess.WRITE)
	if not expect(file != null and not source_text.is_empty(), "copy real native-delivered checkpoint"): finish(); return
	file.store_string(source_text); file.close()
	if not expect(game.load_game() and game.current_done(), "resume actual completed source case"): finish(); return
	game.set_process(false); await build_ui()
	record("setup_api", "Continuation-only debugging from actual native-delivered checkpoint. No outcome/funds/VM injection; counted separately from full journey.")
	if not await continue_customer(): finish(); return
	if not expect(FileAccess.get_file_as_string(source) == source_text, "source checkpoint unchanged"): finish(); return
	journey_completed = true; finish()

func company() -> bool:
	if shown("ExitDesktop") and not await press("ExitDesktop"): return false
	ui.open_panel("company"); await frames(10)
	return await press("CompanyView_overview") if shown("CompanyView_overview") else expect(shown("CompanyCycle"), "actual customer management surface")

func branch_lead() -> Dictionary:
	for lead in game.company_cycle_view().opportunities:
		if str(lead.client) == HANDOFF.CLIENT: return lead
	return {}

func tree_file(item: TreeItem, path: String) -> TreeItem:
	if item == null: return null
	if str(item.get_metadata(0)) == path: return item
	var child := item.get_first_child()
	while child != null:
		var found := tree_file(child, path)
		if found != null: return found
		child = child.get_next()
	return null

func select_handoff_paper() -> bool:
	var tree := control("BackupSnapshotTree") as Tree
	if not expect(is_instance_valid(tree), "actual saved-file tree available"): return false
	if not await scroll_to(tree): return false
	var item := tree_file(tree.get_root(), HANDOFF.DESTINATION)
	if not expect(item != null, "real snapshot contains carried customer file"): return false
	var row := Rect2()
	for _attempt in 20:
		var local := tree.get_item_area_rect(item, 0)
		row = Rect2(tree.global_position + local.position, local.size)
		if clipped_rect(tree).encloses(row): break
		mouse(clipped_rect(tree).get_center(), MOUSE_BUTTON_WHEEL_DOWN); await frames(3)
	if not expect(clipped_rect(tree).encloses(row), "carried file row visible before actual selection"): return false
	mouse(row.get_center()); await frames(10)
	if not expect(str(ui.desktop.backup_ui.get("path", "")) == HANDOFF.DESTINATION and shown("BackupWorkbench"), "pointer selection opens carried customer paper and actual destination tray"): return false
	return expect(str(control("BackupRecoveryGuard").get_meta("state")) == "matched", "paper tray shows genuine handoff match")

func route_projection(lead: Dictionary) -> bool:
	if not await press("CycleCustomer_" + str(lead.id).validate_node_name()): return false
	var before: Dictionary = game.state.duplicate(true)
	var board := control("CycleCustomerRoute")
	if not expect(same_saved_values(board.item, lead) and board.objects.size() == 3, "diagram shows actual prior delivery, customer satisfaction and authored next work"): return false
	for id in ["CycleSourceTitle","CycleSourceDay","CycleRelationshipValue","CycleRelationshipDay","CycleRelationshipStatus","CycleNextTitle","CycleNextService"]:
		var label := control(id) as Label
		if not expect(clipped_rect(label).grow(1).encloses(label.get_global_rect()), id + " visible on first view at actual text setting"): return false
		if not expect(label.get_theme_font_size("font_size") >= int(12 * game.settings.text_scale), id + " respects enlarged setting"): return false
	for pair in [["CycleSourceTitle","CycleSourceDay"],["CycleNextTitle","CycleNextService"]]:
		if not expect(control(pair[0]).get_global_rect().end.y <= control(pair[1]).get_global_rect().position.y, "wrapped work title does not overlap its service/day caption"): return false
	if not await press("CycleRouteObject0"): return false
	if not expect(control("CycleDetails").visible and text_in(control("CycleDetails")).contains(str(lead.source_title)), "paper opens saved source details"): return false
	if not expect(clipped_rect(control("CycleDetails")).grow(1).encloses(control("CycleDetails").get_global_rect()), "paper inspection reveals readable details without an extra scroll"): return false
	if not await keyboard_activate("CycleDetailsToggle"): return false
	if not expect(not control("CycleDetails").visible and game.state == before, "keyboard closes details without new measurement, clock or reward"): return false
	if not expect(control("CycleRouteObject0").has_focus() and clipped_rect(board).grow(1).encloses(board.get_global_rect()), "closing inspection returns visible focus and the complete customer diagram"): return false
	await capture("13-customer-route-" + str(lead.status))
	return true

func next_day() -> bool:
	var day := int(game.state.day)
	if not await company() or not await press("ManagementTab_board") or not await press("OperationsCloseDay") or not await press("DaySettle"): return false
	return expect(int(game.state.day) == day + 1, "ordinary UI day settlement opens tomorrow's demand") and await press("DayNext")

func after_payment() -> bool:
	if not await super.after_payment(): return false
	return await continue_customer()

func continue_customer() -> bool:
	if not await company(): return false
	var lead := branch_lead()
	if not expect(not lead.is_empty() and str(lead.case_id) == HANDOFF.CASE_ID, "actual branch delivery creates same-customer different-service consultation"): return false
	if not await route_projection(lead): return false
	if late:
		if not expect(str(lead.status) == "paused" and not HANDOFF.available(game.state), "actual late delivery visibly pauses customer and blocks backup handoff"): return false
		var old: Dictionary = game.state.company_cycle.duplicate(true)
		if not expect(game.save_game() and game.load_game() and same_saved_values(game.state.company_cycle, old), "paused consequence persists after save/reload"): return false
		game.set_process(false)
		return true
	if not expect(str(lead.status) == "locked" and HANDOFF.available(game.state), "earned handoff waits for ordinary next-day market slot"): return false
	if not lead.get("reasons", []).is_empty():
		var points := int(game.skill_points())
		if not await press("CyclePrepare_" + str(lead.id).validate_node_name()) or not await press("LearnSkill_operations"): return false
		if not expect(int(game.state.skills.operations) == 1 and int(game.skill_points()) == points - 1, "earned skill point enables different customer service by real investment"): return false
		if not await company(): return false
	for _day in 9:
		if not await next_day() or not await company(): return false
		lead = branch_lead()
		if str(lead.status) == "ready": break
	if not expect(str(lead.status) == "ready", "ordinary customer priority produces an available consultation"): return false
	if not await route_projection(lead) or not await press("CycleRouteObject2") or not await press("AcceptContract"): return false
	if not expect(str(game.state.contract.get("case_id", "")) == HANDOFF.CASE_ID and str(game.state.contract.get("client", "")) == HANDOFF.CLIENT, "real graph-to-quote acceptance keeps the same customer"): return false
	var prior := HANDOFF.source(game.state)
	if not await press("DispatchOpen") or not await connect_machine(0) or not await route("browser"): return false
	if not expect(game._vm().state.fs[HANDOFF.DESTINATION] == str(prior.content) and str(game._vm().state.scenario.handoff.sha256) == str(prior.sha256), "accepted backup host and manifest retain exact prior shared-file bytes"): return false
	if not await press("BackupPlan") or not await select_option("BackupSchedule",1) or not await select_option("BackupPlanRepository",1) or not await press("BackupSavePlan") or not await press("BackupRepo_offsite") or not await press("BackupNow"): return false
	if not await press("BackupSnapshot_00000001") or not await press("BackupRestore") or not await edit("BackupDestination", "/tmp") or not await press("BackupPreviewChanges") or not await press("BackupExecuteRestore"): return false
	if not expect(game._vm().state.fs.get("/tmp/srv/data/partner-order.csv", "") == str(prior.content) and not game._vm().backup_acceptance_view().accepted, "successful restore to unapproved folder remains a real customer acceptance failure"): return false
	await capture("14-wrong-destination-acceptance-failed")
	if not await edit("BackupDestination", "/restore") or not await press("BackupPreviewChanges"): return false
	var before: Dictionary = game._vm().export_state(); var path: String = game.save_path
	game.save_path = "user://missing-continuation-dir/save.json"
	if not await press("BackupExecuteRestore"): game.save_path = path; return false
	game.save_path = path
	if not expect(game._vm().export_state() == before, "failed save rolls actual restore back"): return false
	if not await press("BackupPreviewChanges") or not await press("BackupExecuteRestore"): return false
	if not expect(game._vm().backup_acceptance_view().accepted, "retry restores exact handoff and preserves all customer source records"): return false
	if not expect(not str(ui.desktop.status.text).contains("保存失敗"), "successful retry replaces stale save-failure notice with actual operation result"): return false
	if not await press("BackupCloseRestore") or not await select_handoff_paper(): return false
	await capture("15-real-handoff-restored")
	var saved: Dictionary = game._vm().export_state()
	if not expect(ui.desktop._save_session() and game.save_game(), "save restored but undelivered work"): return false
	ui.queue_free(); await frames(6)
	if not expect(game.load_game() and same_saved_values(game._vm().export_state(), saved), "interruption preserves actual restored bytes and original acceptance hash"): return false
	game.set_process(false); await build_ui()
	if not await route("verify"): return false
	for probe in game.diagnostic_probes():
		if not await press("DiagnosticProbe_" + str(probe.id)) or not await press("DiagnosticRun"): return false
	if not await press("DiagnosticValidate") or not expect(game.can_deliver(), "fresh offsite-dump and restored-hash probes satisfy real case") or not await press("GuideDeliver"): return false
	continuation_receipt = game.completion_receipt().duplicate(true)
	if not expect(str(continuation_receipt.rating) == "on_time" and str(branch_lead().status) == "fulfilled", "second actual delivery fulfills earned consultation"): return false
	if not await press("ReceiptFinanceTab") or not await press("ReceiptInvoice") or not await press("BillingPost"): return false
	if not await company() or not await route_projection(branch_lead()): return false
	await capture("16-same-customer-followup-complete")
	var out := FileAccess.open(folder.path_join("continuation-completed.json"), FileAccess.WRITE)
	if out != null: out.store_string(JSON.stringify(game.state, "\t")); out.close()
	return true
