extends SceneTree
## Company UI workflow: native Godot mouse/key dispatch for primary actions.
## Fixtures: starting capital; deliberately unavailable save path; VM solution;
## physical receiving/placement via public Game APIs (3D world is not instantiated).
var game
var ui
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()
var native_clicks := 0
var native_edits := 0
var choice_signals := 0
var paths: Dictionary = {}
var selected: Dictionary = {}

func _init() -> void:
	create_timer(150).timeout.connect(func(): print("COMPANY_WORKFLOWS_TIMEOUT"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count := 5) -> void:
	for _i in count: await process_frame

func control(id: String) -> Node:
	return ui.root.find_child(id, true, false) if is_instance_valid(ui) else null

func reveal(target: Control) -> void:
	var ancestor := target.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(target); await frames(2)
		ancestor = ancestor.get_parent()
	await frames()
	check(root.get_visible_rect().has_point(target.get_global_rect().get_center()), "visible " + str(target.name))

func mouse(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = position; motion.global_position = position; Input.parse_input_event(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = position; event.global_position = position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; Input.parse_input_event(event)
	native_clicks += 1

func click(id: String, twice := false) -> void:
	var target := control(id) as Control
	check(is_instance_valid(target) and target.is_visible_in_tree(), "present " + id)
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return
	if target is BaseButton:
		check(not target.disabled, "enabled " + id)
		if target.disabled: return
	await reveal(target)
	var position := target.get_global_rect().get_center()
	mouse(position)
	if twice: mouse(position)
	await frames(12)

func key(code: Key, unicode_value := 0, ctrl := false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new(); event.keycode = code; event.unicode = unicode_value; event.ctrl_pressed = ctrl; event.pressed = down; Input.parse_input_event(event)

func edit(id: String, value: String) -> void:
	var field := control(id)
	if field is SpinBox: field = field.get_line_edit()
	check(field is LineEdit, "entry " + id)
	if not field is LineEdit: return
	await reveal(field); mouse(field.get_global_rect().get_center()); await frames()
	check(field.has_focus(), "focus " + id)
	key(KEY_A, 0, true); key(KEY_BACKSPACE)
	for index in value.length(): key(KEY_NONE, value.unicode_at(index))
	key(KEY_ENTER); native_edits += 1; await frames(8)

func choose(id: String, index: int) -> void:
	var option := control(id) as OptionButton
	check(is_instance_valid(option) and index >= 0 and index < option.item_count, "choice " + id)
	if not is_instance_valid(option): return
	option.select(index); option.item_selected.emit(index); choice_signals += 1; await frames(8)

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless" or not failures.is_empty(): return
	await frames(8); await RenderingServer.frame_post_draw
	var folder := OS.get_environment("WHL_CAPTURE_DIR")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../../audit/all-services/company/screens")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label); print("CAPTURE ", path)

func open_management(kind: String) -> void:
	ui.open_panel(kind); await frames(12)
	check(ui.current_kind == kind, "open " + kind)

func open_app(app: String) -> void:
	if ui.current_kind != "terminal": ui.open_panel("terminal"); await frames(8)
	ui.desktop._show_app(app)
	if not ui.desktop.windows[app].maximized: ui.desktop.windows[app].toggle_maximize()
	await frames(12)

func invalid_save(enable: bool) -> void:
	for name in ["save_path", "backup_path", "previous_path", "settings_path"]:
		if enable:
			paths[name] = game.get(name); game.set(name, "user://missing-company-workflow-folder/" + name + ".json")
		else: game.set(name, paths[name])

func assert_feedback(label: String) -> void:
	var message := control("ManagementActionFeedback") as Label
	check(is_instance_valid(message) and not message.text.is_empty(), label + " visible reason")
	if is_instance_valid(message): check(root.get_visible_rect().has_point(message.get_global_rect().get_center()), label + " reason in viewport")

func dismiss_notifications() -> void:
	# Desktop feedback is a persistent status label, not a modal overlay.
	await frames()

func reload_company() -> void:
	check(ui.close_panel(false, false), "close saves workstation")
	check(game.save_game() and game.load_game(), "company saves and loads")
	ui.queue_free(); await frames()
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	ui.controls.menu.hide(); ui.guided_intro.skip(); ui._set_text_scale(1.3 if narrow else 1.0)

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "isolated profile")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	check(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(), "career fixture")
	game.state.cash = 100000
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.get_node("Graphics").apply_settings(game.settings); await frames()
	check(not narrow or is_equal_approx(root.get_visible_rect().size.x,960), "management fixture uses actual small-window coordinates")
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	ui.controls.menu.hide(); ui.guided_intro.skip(); ui._set_text_scale(1.3 if narrow else 1.0)
	await open_management("staffing")
	check(control("Hire_mio") is Button and control("Hire_mio").disabled, "missing workplace blocks hiring")
	check(control("StaffHireReason") is Label and not control("StaffHireReason").text.is_empty(), "missing workplace explained")
	await capture("01-staffing-requires-workplace")
	await open_management("shop"); await click("EquipmentSelect_teamdesk")
	var cash := int(game.state.cash)
	await click("Buy_teamdesk", true)
	check(game.state.delivery_orders.size() == 1 and int(game.state.cash) == cash - int(game.equipment_price("teamdesk")), "double equipment order charged once")
	await capture("02-equipment-ordered")
	game.advance_delivery(30.0)
	check(game.take_delivery("teamdesk") and game.begin_delivery_placement("teamdesk") and game.place_delivery("teamdesk", game.equipment_slot("teamdesk")), "public physical delivery APIs install purchased workplace")
	await open_management("staffing")
	invalid_save(true); cash = int(game.state.cash)
	await click("Hire_mio")
	check(int(game.staff_summary().count) == 0 and int(game.state.cash) == cash, "failed hire preserves headcount and cash")
	assert_feedback("failed hire"); invalid_save(false)
	await click("Hire_mio", true)
	check(int(game.staff_summary().count) == 1, "hire committed once")
	invalid_save(true); await choose("Shift_mio", 2)
	check(str(game.state.staff.mio.pending_shift).is_empty() and control("Shift_mio").selected == 0, "failed shift restores visible saved choice")
	assert_feedback("failed shift"); await capture("03-staff-save-failure"); invalid_save(false)
	await choose("Shift_mio", 1)
	check(str(game.state.staff.mio.pending_shift) == "morning", "shift change scheduled next day")
	await capture("04-staff-next-day-shift")
	await open_app("team")
	check(control("Assign_aya") is Button and control("Assign_aya").disabled and not control("Assign_aya").tooltip_text.is_empty(), "team explains absent active work")
	await capture("05-team-no-active-work"); await click("TeamOperations")
	check(ui.current_kind == "board", "team workload route")
	for item in game.state.offers:
		if str(item.case_id) == "service-2-case-0" and bool(item.unlocked) and bool(item.market_available): selected = item; break
	check(not selected.is_empty(), "ordinary network inquiry available")
	if selected.is_empty(): finish(); return
	ui._select_contract(str(selected.id)); await frames(10)
	# Choose care by its public catalog ID rather than depending on menu order.
	var plans: Array = game.contract_plans()
	for i in plans.size():
		if str(plans[i].id) == "care": await choose("ContractPlan", i); break
	var quote: Dictionary = game.contract_quote(selected)
	await edit("OfferPrice", str(int(quote.budget_limit) + 1)); await click("AcceptContract")
	check(not bool(game.state.accepted) and control("QuoteDeclined") is Label, "over-budget quote rejected with visible decision")
	await capture("06-sales-declined-quote")
	await edit("OfferPrice", str(int(quote.reference_fee)))
	invalid_save(true); await click("SaveQuoteDraft"); assert_feedback("quote save failure")
	check(int(control("OfferPrice").value) == int(quote.reference_fee), "quote failure retains input"); invalid_save(false)
	await click("SaveQuoteDraft")
	await reload_company()
	ui._select_contract(str(selected.id)); await frames(10)
	check(int(control("OfferPrice").value) == int(quote.reference_fee), "saved quote survives reconstructed interface")
	await capture("07-sales-saved-scope-quote"); await click("AcceptContract", true)
	check(game.contract_queue().size() == 1 and bool(game.state.accepted), "quote accepted exactly once")
	await open_management("board"); await click("DispatchControlsDisclosure")
	var chooser := control("DispatchMemberSelector") as OptionButton
	for i in chooser.item_count:
		if str(chooser.get_item_metadata(i)) == "aya": await choose("DispatchMemberSelector", i); break
	check(control("DispatchForecast") is Label and not control("DispatchForecast").text.is_empty(), "assignment shows projected time")
	await capture("08-board-workload-forecast"); await click("DispatchEnqueue", true)
	check(game.dispatch_queue("aya").size() == 1, "repeat enqueue creates one assignment")
	var jobs: Array = game.dispatch_queue("aya")
	await click("OperationsView_staff")
	await click("DispatchStart_" + str(jobs[0].id))
	game.set_office_clock_paused(false); game._process(30); game.set_office_clock_paused(true)
	await open_app("team"); ui.desktop._refresh_team(); await frames()
	check(str(game.state.assignments.aya.status) == "done", "actual delegated investigation completes")
	await capture("09-team-investigation-result"); await click("Result_aya")
	check(not ui.desktop.editor.text.is_empty(), "team result opens produced artifact")
	await open_app("mail"); await edit("MailSearch", "no-such-client-qa")
	check(control("MailNoResults") != null, "mail empty search explained")
	await edit("MailSearch", "")
	var mail_list: Node = ui.desktop.widgets.mail.list
	for button in mail_list.find_children("*", "Button", true, false):
		await reveal(button); mouse(button.get_global_rect().get_center()); await frames(10); break
	check(control("MailMessageBody") != null, "selected customer brief opens")
	await capture("10-mail-customer-brief")
	await open_app("receipt")
	check(control("GuideDeliver") is Button and control("GuideDeliver").disabled and control("ReceiptBlockers") != null, "receipt requires verified repair")
	await capture("11-receipt-blocked")
	# The security repair is a model fixture; this test targets management delivery,
	# accounting, and preserved care scope, not another training-case answer test.
	game.vm_run("ssh client")
	var machine = game._vm()
	check(game.vm_write(game.vm_info().config_path, machine.configuration_text(game._scenario().get("desired", machine._legacy_desired()))), "repair fixture writes normal config")
	game.vm_run("systemctl restart " + str(game.vm_info().service))
	for _i in 3:
		for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	game.verify(); ui.desktop._refresh_receipt(); await frames()
	check(game.can_deliver(), "actual probes permit delivery")
	await click("GuideDeliver", true)
	check(game.current_done() and game.company_invoices().size() == 1, "double delivery creates one receivable")
	await click("ReceiptFinanceTab"); await capture("12-receipt-finance"); await click("ReceiptEvaluationTab"); await capture("13-receipt-evidence")
	var invoice: Dictionary = game.company_invoices()[0]
	await open_app("billing"); await click("BillingInvoice_" + str(invoice.id).validate_node_name())
	invalid_save(true); cash = int(game.state.cash); await click("BillingPost")
	check(int(game.state.cash) == cash and str(game.company_invoices()[0].status) == "draft", "failed invoice confirmation rolls back cash")
	check(control("BillingPostFeedback") is Label and not control("BillingPostFeedback").text.is_empty(), "accounting save failure visible")
	invalid_save(false); await dismiss_notifications(); await click("BillingPost", true)
	check(str(game.company_invoices()[0].status) in ["posted", "paid"], "invoice confirmation persisted")
	await capture("14-company-billing-confirmed")
	await open_management("company"); await capture("15-company-cash-receivables")
	await click("CompanyView_growth"); await capture("16-company-growth")
	await click("CompanyView_care"); await capture("17-company-care")
	await open_management("shop"); await click("StockTab")
	await edit("StockCartQuantity_gateway", "1")
	var review: Dictionary = game.customer_cart_review(); check(bool(review.ok), "stock cart review")
	await capture("18-stock-order-cash-capacity"); cash = int(game.state.cash)
	await click("StockPurchase", true)
	check(game.customer_stock_units().size() == 1 and int(game.state.cash) == cash - int(review.total), "atomic inventory purchase once")
	await capture("19-stock-serial-traceability")
	var serial := str(game.customer_stock_units()[0].id)
	game.advance_delivery(30.0)
	check(game.take_delivery(serial) and bool(game.store_customer_stock(serial).get("ok", false)), "public receiving API stores ordered unit")
	await open_management("shop"); await click("StockSerial_" + str(game.customer_stock_units()[0].serial))
	await capture("20-stock-stored-location")
	await open_management("door"); await capture("21-day-preview")
	var previous_day := int(game.state.day)
	await click("DaySettle", true)
	check(int(game.state.day) == previous_day + 1 and ui.current_kind == "day_review", "double settle advances only one day")
	check(str(game.state.staff.mio.shift) == "morning", "pending shift starts on next day")
	await capture("22-day-actual-settlement")
	var summary: Dictionary = game.company_operating_summary().duplicate(true)
	await reload_company()
	check(JSON.stringify(game.company_operating_summary()) == JSON.stringify(summary), "cash receivables staffing stock survive restart")
	await open_management("staffing")
	check(control("Shift_mio") is OptionButton and control("Shift_mio").selected == 1, "reopened shift shows actual morning hours")
	await open_management("company"); await click("CompanyView_care")
	check(not game.maintenance_jobs().is_empty(), "delivered care agreement schedules next-day work")
	await capture("23-care-next-day-work")
	var client := str(selected.client)
	await click("CompanyClient_" + client.sha256_text().left(10))
	await click("CareSelfCheck_" + client.sha256_text().left(10), true)
	check(str(game._maintenance_job_for(client).status) == "done", "care inspects retained actual VM")
	await capture("24-care-inspection-result")
	await click("CareResult_" + client.sha256_text().left(10))
	check(ui.current_kind == "terminal" and game.maintenance_result(client).begins_with("PASS"), "care result opens recorded measurements")
	finish()

func finish() -> void:
	print("COMPANY_WORKFLOWS_UI_PASS narrow=", narrow, " native_clicks=", native_clicks, " native_edits=", native_edits, " choice_signals=", choice_signals) if failures.is_empty() else print("COMPANY_WORKFLOWS_UI_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
