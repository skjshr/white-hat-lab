extends "res://tests/test_release_journey.gd"
## Normal-funded, multi-contract continuation of the real first-job journey.
## Gameplay uses mouse/key dispatch. Public views are observation only.
## No cash, skill, time, desired-state, completion, offer or receipt injection.
var ecosystem_started := false
var checkpoints: Array[Dictionary] = []

func _init() -> void:
	started_ms = Time.get_ticks_msec()
	folder = OS.get_environment("WHL_CAPTURE_DIR")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../../audit/finish-20261004/ecosystem-journey/screens")
	DirAccess.make_dir_recursive_absolute(folder)
	create_timer(900).timeout.connect(func(): failures.append("ecosystem journey timeout"); ecosystem_started = true; finish())
	call_deferred("run")

func capture(label: String) -> void:
	if label in ["02-company-direction", "18-customer-result", "23-next-customer-request"] or label.begins_with("eco-"):
		await super.capture(label)

func checkpoint(label: String) -> void:
	var mark := {"label":label,"day":int(game.state.day),"cash":int(game.state.cash),"credit":int(game.state.credit),"skills":game.state.skills.duplicate(true),"level":game.company_level(),"cycle":game.company_cycle_view(),"billing":game.state.get("billing", {}).duplicate(true),"history":game.state.history.duplicate(true),"equipment":game.state.equipment.duplicate(),"completed_ids":game.state.completed_ids.duplicate()}
	checkpoints.append(mark)
	var file := FileAccess.open(folder.path_join(label + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(mark, "\t")); file.close()
	record("company_checkpoint", label + " cash=" + str(mark.cash) + " day=" + str(mark.day))

func finish() -> void:
	if not ecosystem_started and failures.is_empty():
		ecosystem_started = true; call_deferred("ecosystem_journey"); return
	var report := {"narrow":narrow,"failures":failures,"events":events,"checkpoints":checkpoints,"clicks":clicks,"keys":keys,"scrolls":scrolls,"method":"Godot Input.parse_input_event; source-inspected controls; normal starting funds. Equipment order and real delivery wait followed by three disclosed public take/begin/place interactions. Fixed camera framing only for the final office screenshot. No progression or answer injection."}
	var file := FileAccess.open(folder.path_join("ecosystem-journey.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ECOSYSTEM_JOURNEY_", "PASS" if failures.is_empty() else "FAIL", " clicks=", clicks, " keys=", keys, " scrolls=", scrolls, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func ecosystem_journey() -> void:
	checkpoint("eco-01-earned-first-delivery")
	if not await press("ExitDesktop"): finish(); return
	await tap(KEY_4)
	await capture("eco-02-customer-consultation")
	var opportunities: Array = game.company_cycle_view().opportunities
	if not expect(not opportunities.is_empty(), "actual first delivery creates customer follow-up"): finish(); return
	var lead: Dictionary = opportunities[0]
	if not expect(str(lead.client) == "つばさ文具" and str(lead.case_id) == "service-5-case-1", "same customer receives a different service, not another share repair"): finish(); return
	var id := str(lead.id).validate_node_name()
	var points := int(game.skill_points())
	if not await press("CyclePrepare_" + id): finish(); return
	if not await press("LearnSkill_advisory"): finish(); return
	if not expect(int(game.state.skills.advisory) == 1 and int(game.skill_points()) == points - 1, "earned skill point is spent by actual learn button"): finish(); return
	checkpoint("eco-03-earned-investment")
	if not await press("CompanyView_overview"): finish(); return
	if not await press("CycleOpen_" + id): finish(); return
	await capture("eco-04-same-client-quote")
	if not await press("AcceptContract"): finish(); return
	if not expect(bool(game.state.accepted) and str(game.state.contract.case_id) == str(lead.case_id), "real quote accepts the earned external-sharing contract"): finish(); return
	await capture("eco-05-followup-accepted")
	if not await press("DispatchOpen"): finish(); return
	if not await route("terminal"): finish(); return
	if not await press("TerminalConnect"): finish(); return
	if not await route("browser"): finish(); return
	await capture("eco-06-followup-service")
	# The customer brief requests a seven-day expiry; the controls expose its
	# existing partner access and current unlimited duration for observation.
	if not await press("PortalFile_0"): finish(); return
	if not await press("PortalShare_partner"): finish(); return
	await capture("eco-07-existing-unlimited-link")
	if not await select_option("PortalExpiry_partner", 1): finish(); return
	if not await press("PortalApply_partner"): finish(); return
	if not await press("PortalPreview"): finish(); return
	if not await select_metadata("PortalIdentity", "partner-mfa-session"): finish(); return
	if not await press("PortalRead"): finish(); return
	if not expect(str(ui.desktop.portal_ui.get("response", "")).begins_with("HTTP/1.1 200"), "authorized customer can read after expiry change"): finish(); return
	if not await select_option("PortalAge", 1): finish(); return
	if not await press("PortalRead"): finish(); return
	if not expect(str(ui.desktop.portal_ui.get("response", "")).begins_with("HTTP/1.1 410"), "same link expires at the requested age"): finish(); return
	await capture("eco-08-real-expired-link")
	if not await route("verify"): finish(); return
	for probe in game.diagnostic_probes():
		if not await press(("DiagnosticProbe_" + str(probe.id)).validate_node_name()): finish(); return
		if not await press("DiagnosticRun"): finish(); return
	if not await press("DiagnosticValidate"): finish(); return
	if not expect(game.can_deliver(), "real expiry repair and normal-business probes satisfy the contract"): finish(); return
	checkpoint("eco-09-followup-ready")
	await capture("eco-09-followup-ready")
	# Deliberately leave verified work undelivered overnight. The ordinary
	# day-closeout action persists it and the real clock makes it overdue.
	var delayed_contract := str(game.state.current_contract_id)
	if not await advance_day(): finish(); return
	if not await press("DispatchTicket_" + delayed_contract): finish(); return
	if not await press("DispatchOpen"): finish(); return
	if not expect(str(game.work_status().quality) == "late", "real overnight carryover overruns the customer's agreed deadline"): finish(); return
	if not await route("verify"): finish(); return
	if not await press("DiagnosticValidate"): finish(); return
	if not await route("receipt"): finish(); return
	await capture("eco-10-visible-late-consequence")
	if not await press("GuideDeliver"): finish(); return
	if not expect(game.current_done() and str(game.completion_receipt().rating) == "late", "actual late service delivery retained"): finish(); return
	checkpoint("eco-11-paused-after-late-delivery")
	if not await press("ExitDesktop"): finish(); return
	await tap(KEY_4)
	await capture("eco-12-paused-customer-pipeline")
	var paused := {}
	for item in game.company_cycle_view().opportunities:
		if str(item.client) == str(lead.client): paused = item
	if not expect(str(paused.get("status", "")) == "paused", "late actual delivery pauses this customer's next consultation"): finish(); return
	if not await post_current_invoice(): finish(); return
	if not await press("ExitDesktop"): finish(); return
	await tap(KEY_4)
	if not await press("CycleRecover_" + str(paused.id).validate_node_name()): finish(); return
	await capture("eco-14-normal-recovery-market")
	var available: Array = game.state.offers.filter(func(item): return bool(item.get("market_available", false)) and bool(item.get("unlocked", false)))
	var file := FileAccess.open(folder.path_join("eco-14-available-offers.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(available, "\t")); file.close()
	if not await accept_available_case("service-0-case-0"): finish(); return
	if not await repair_samba(): finish(); return
	if not await verify_and_deliver("eco-16-relationship-repair"): finish(); return
	var recovered := {}
	for item in game.company_cycle_view().opportunities:
		if str(item.client) == str(lead.client): recovered = item
	if not expect(not recovered.is_empty() and str(recovered.get("id", "")) == str(paused.id) and str(recovered.get("case_id", "")) == str(paused.case_id) and str(recovered.get("client", "")) == str(lead.client) and str(recovered.get("status", "")) in ["ready", "locked"] and int(game.completion_receipt().satisfaction_after) >= 40, "on-time genuine work restores the same retained customer consultation"): finish(); return
	if not await company_overview(): finish(); return
	await capture("eco-17-relationship-recovered")
	if not await post_current_invoice(): finish(); return
	if not await company_overview(): finish(); return
	if not await invest_equipment(): finish(); return
	if not await accept_available_case("service-1-case-0"): finish(); return
	if not await repair_backup(): finish(); return
	if not await verify_and_deliver("eco-20-second-customer-backup"): finish(); return
	if not await company_overview(): finish(); return
	if not await post_current_invoice(): finish(); return
	checkpoint("eco-21-four-real-deliveries")
	if not expect(game.state.completed_ids.size() == 4, "four distinct accepted contracts actually delivered"): finish(); return
	if not await company_overview(): finish(); return
	await capture("eco-22-real-company-goals")
	var goals: Array = game.company_cycle_view().goals
	if not expect(goals.any(func(goal): return str(goal.id) == "independent_lab" and bool(goal.complete)), "two real customers, three service families, installed equipment and cash earn the company milestone"): finish(); return
	if not await save_and_resume_company(): finish(); return
	await capture("eco-24-resumed-company")
	checkpoint("eco-25-persistent-world")
	await tap(KEY_ESCAPE)
	# Camera placement is evidence framing only, after all economic actions.
	# It neither creates progress nor substitutes for equipment interactions.
	record("capture_camera", "office board framed at a fixed viewpoint after the completed journey")
	office.player.position = Vector3(3.4, 0.05, -1.8)
	office.player.camera.look_at(Vector3(3.4, 2.0, -4.74))
	await frames(12)
	if not expect(bool(office.company_progress.get_meta("earned_first_delivery", false)) and bool(office.company_progress.get_meta("earned_independent_lab", false)), "real saved goals illuminate both office tokens"): finish(); return
	await capture("eco-26-earned-office-board")
	finish()

func post_current_invoice() -> bool:
	var invoice_id := str(game.completion_receipt().get("invoice_id", ""))
	if not expect(not invoice_id.is_empty(), "real career delivery creates an invoice draft"): return false
	var cash_before := int(game.state.cash)
	if not await press("CycleBilling"): return false
	if not await press("BillingInvoice_" + invoice_id.validate_node_name()): return false
	await capture("eco-13-real-invoice-draft")
	if not await press("BillingPost"): return false
	var invoice: Dictionary = {}
	for item in game.state.get("billing", {}).get("invoices", []):
		if str(item.id) == invoice_id: invoice = item
	if not expect(str(invoice.get("status", "")) == "paid" and int(game.state.cash) == cash_before + int(invoice.get("amount", 0)), "immediate terms collect the genuine invoice amount exactly once"): return false
	checkpoint("eco-13-invoice-collected")
	return true

func select_metadata(id: String, value: String) -> bool:
	var choice := control(id) as OptionButton
	if not expect(is_instance_valid(choice), "displayed option " + id): return false
	for index in choice.item_count:
		if str(choice.get_item_metadata(index)) == value: return await select_option(id, index)
	return expect(false, "displayed option value " + id + " " + value)

func company_overview() -> bool:
	if is_instance_valid(control("ExitDesktop")) and control("ExitDesktop").is_visible_in_tree():
		if not await press("ExitDesktop"): return false
	if is_instance_valid(control("ManagementTab_company")) and control("ManagementTab_company").is_visible_in_tree():
		if not await press("ManagementTab_company"): return false
	else:
		await tap(KEY_4)
	if is_instance_valid(control("CompanyView_overview")):
		if not await press("CompanyView_overview"): return false
	return expect(is_instance_valid(control("CompanyCycle")), "company overview reached by live navigation")

func advance_day() -> bool:
	var day := int(game.state.day)
	if not await company_overview(): return false
	if not await press("ManagementTab_board"): return false
	if not await press("OperationsCloseDay"): return false
	await capture("eco-day-" + str(day) + "-closeout")
	if not await press("DaySettle"): return false
	if not expect(int(game.state.day) == day + 1, "actual day settlement advances one day"): return false
	if not await press("DayNext"): return false
	checkpoint("eco-day-" + str(game.state.day))
	return true

func accept_available_case(case_id: String) -> bool:
	var chosen := {}
	for _day in 9:
		for item in game.state.offers:
			if str(item.get("case_id", "")) == case_id and bool(item.get("market_available", false)) and bool(item.get("unlocked", false)) and str(item.id) not in game.state.completed_ids:
				chosen = item; break
		if not chosen.is_empty(): break
		record("market_wait", case_id + " not offered today; close day through ordinary UI")
		if not await advance_day(): return false
	if not expect(not chosen.is_empty(), "ordinary market offers " + case_id + " within nine actual days"): return false
	if not await company_overview(): return false
	if not await press("ManagementTab_sales"): return false
	if not await press("SalesInquiriesTab"): return false
	if not await select_metadata("SalesCategoryFilter", "all"): return false
	if not await select_metadata("SalesStageFilter", "all"): return false
	if not await edit("SalesSearch", ""): return false
	await tap(KEY_ENTER)
	if not await press("SalesOffer_" + str(chosen.id).replace("/", "_").replace(" ", "_")): return false
	await capture("eco-quote-" + case_id)
	if not await press("AcceptContract"): return false
	if not expect(str(game.state.contract.get("case_id", "")) == case_id and bool(game.state.accepted), "ordinary quote accepted " + case_id): return false
	if not await press("DispatchOpen"): return false
	if not await route("terminal"): return false
	if not await press("TerminalConnect"): return false
	return await route("browser")

func repair_samba() -> bool:
	if not await press("SambaEdit_share"): return false
	if bool(control("SambaReadOnly").button_pressed) and not await press("SambaReadOnly"): return false
	if bool(control("SambaGuest").button_pressed) and not await press("SambaGuest"): return false
	if not await edit("SambaValidUsers", "staff"): return false
	if not await press("SambaSave"): return false
	if not await press("SambaRestart"): return false
	await capture("eco-15-same-client-repair")
	return true

func verify_and_deliver(label: String) -> bool:
	if not await route("verify"): return false
	for probe in game.diagnostic_probes():
		if not await press(("DiagnosticProbe_" + str(probe.id)).validate_node_name()): return false
		if not await press("DiagnosticRun"): return false
	for _round in 8:
		var stale: Array = game.diagnostic_probes().filter(func(probe): return not bool(probe.get("fresh", false)))
		if stale.is_empty(): break
		if not await press(("DiagnosticProbe_" + str(stale[0].id)).validate_node_name()): return false
		if not await press("DiagnosticRun"): return false
	if not await press("DiagnosticValidate"): return false
	if not expect(game.can_deliver(), "actual probes permit delivery " + label): return false
	if not await route("receipt"): return false
	if not await press("GuideDeliver"): return false
	await capture(label)
	checkpoint(label)
	return expect(game.current_done() and str(game.completion_receipt().rating) == "on_time", "real on-time delivery " + label)

func repair_backup() -> bool:
	if not await press("BackupPlan"): return false
	if not await select_option("BackupSchedule", 1): return false
	if not await select_option("BackupPlanRepository", 0): return false
	if not await press("BackupSavePlan"): return false
	if not await press("BackupNow"): return false
	var snapshots: Array = ui.find_children("BackupSnapshot_*", "Button", true, false).filter(func(button): return button.is_visible_in_tree())
	if not expect(not snapshots.is_empty(), "backup operation creates a selectable real snapshot"): return false
	if not await press(str(snapshots.back().name)): return false
	if not await press("BackupRestore"): return false
	if not await edit("BackupDestination", "/restore"): return false
	if not await press("BackupPreviewChanges"): return false
	await capture("eco-19-backup-restore-plan")
	if not await press("BackupExecuteRestore"): return false
	return true

func invest_equipment() -> bool:
	var cash := int(game.state.cash)
	var price := int(game.equipment_price("monitor"))
	if not await press("ManagementTab_shop"): return false
	if not await press("EquipmentSelect_monitor"): return false
	if not await press("Buy_monitor"): return false
	if not expect(int(game.state.cash) == cash - price and "monitor" not in game.state.equipment, "real equipment order spends earned cash before installation"): return false
	await capture("eco-18-equipment-ordered")
	if not await press("ManagementClose"): return false
	# Thirty real seconds elapse through the existing delivery process. These
	# three public interactions replace fragile 3D aiming, never order or time.
	var deadline := Time.get_ticks_msec() + 40000
	while str(game.delivery_for("monitor").get("status", "")) == "queued" and Time.get_ticks_msec() < deadline:
		await create_timer(0.25).timeout
	if not expect(str(game.delivery_for("monitor").get("status", "")) == "ready", "paid order actually arrives after the real delivery wait"): return false
	record("public_interaction_api", "take_delivery(monitor), begin_delivery_placement(monitor), place_delivery(monitor, equipment_slot); no clock/order/equipment injection")
	if not expect(game.take_delivery("monitor"), "arrived equipment picked up"): return false
	if not expect(game.begin_delivery_placement("monitor"), "carried equipment enters placement"): return false
	if not expect(game.place_delivery("monitor", game.equipment_slot("monitor")), "equipment installed through validated placement API"): return false
	if not expect("monitor" in game.state.equipment and int(game.state.cash) == cash - price, "productive equipment persists with a single actual charge"): return false
	checkpoint("eco-18-equipment-installed")
	await tap(KEY_4)
	return true

func save_and_resume_company() -> bool:
	var mark := persistent_mark()
	await tap(KEY_ESCAPE)
	await tap(KEY_ESCAPE)
	if not await press_text("セーブ"): return false
	if not await press_text("タイトルへ戻る"): return false
	await capture("eco-23-title-with-saved-world")
	if not await press("ResumeButton"): return false
	if not expect(JSON.parse_string(JSON.stringify(persistent_mark())) == JSON.parse_string(JSON.stringify(mark)), "save/title/resume preserves clients, assets, invoices, cash, skills, and earned roadmap"): return false
	return await company_overview()

func persistent_mark() -> Dictionary:
	return {"day":int(game.state.day),"cash":int(game.state.cash),"credit":int(game.state.credit),"skills":game.state.skills.duplicate(true),"cycle":game.state.get("company_cycle", {}).duplicate(true),"equipment":game.state.equipment.duplicate(),"clients":game.state.clients.duplicate(true),"vm_states":game.state.vm_states.duplicate(true),"relations":game.state.customer_relations.duplicate(true),"billing":game.state.get("billing", {}).duplicate(true),"completed":game.state.completed_ids.duplicate()}
