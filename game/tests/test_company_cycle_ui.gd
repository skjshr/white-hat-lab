extends SceneTree
## Real company UI and model routing checks, using Godot input dispatch.
## Ready consultation comes from actual first-story VM work and delivery.
## Locked/paused coverage explicitly seeds validated delivery history through
## CompanyCycle.record_delivery; those fixtures never assign cash or offers.
const CYCLE = preload("res://scripts/company_cycle.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")
const PANEL = preload("res://scripts/company_cycle_panel.gd")
const REPAIR := "[global]\nserver role = standalone server\nmap to guest = Bad User\n[share]\npath = /srv/share\nread only = no\nguest ok = no\nvalid users = staff\n"
var game
var ui
var failures: Array[String] = []
var assertions := 0
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(120).timeout.connect(func(): push_error("COMPANY_CYCLE_UI_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); print("FAIL ", message)

func frames(count := 8) -> void:
	for _i in count: await process_frame

func node(id: String) -> Control:
	return ui.find_child(id, true, false) as Control

func visible_rect(control: Control) -> Rect2:
	if control == null or not control.is_visible_in_tree(): return Rect2()
	var rect := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return rect.intersection(root.get_visible_rect())

func mouse(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var pixel := point * Vector2(root.size) / root.get_visible_rect().size
	var move := InputEventMouseMotion.new(); move.position = pixel; move.global_position = pixel; Input.parse_input_event(move)
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = pixel; event.global_position = pixel; event.button_index = button; event.pressed = down; Input.parse_input_event(event)

func click(id: String) -> void:
	var button := node(id) as Button
	check(button != null and button.is_visible_in_tree() and not button.disabled, "enabled route " + id)
	if button == null or not button.is_visible_in_tree() or button.disabled: return
	for _attempt in 32:
		if visible_rect(button).size.y >= 24: break
		var scroll: ScrollContainer = ui.modal_scroll
		mouse(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN if button.get_global_rect().get_center().y > scroll.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP)
		await frames(2)
	check(visible_rect(button).size.y >= 24, "reachable route " + id)
	if visible_rect(button).size.y < 24: return
	# One broad headless run missed the first route; the unchanged rerun and
	# native runs passed, so its cause is unproven. Wait for stable geometry and
	# observe a single real click, without retrying or directly emitting signals.
	var stable := 0
	var last_rect := Rect2()
	for _attempt in 24:
		await frames(1)
		button = node(id) as Button
		if button == null or button.disabled: break
		var current := visible_rect(button)
		stable = stable + 1 if current == last_rect and current.size.y >= 24 else 0
		last_rect = current
		if stable >= 3: break
	check(stable >= 3, "stable visible route geometry " + id)
	if stable < 3: return
	var point := last_rect.get_center()
	var pixel := point * Vector2(root.size) / root.get_visible_rect().size
	var emitted := [0]
	button.pressed.connect(func(): emitted[0] += 1)
	var move := InputEventMouseMotion.new(); move.position = pixel; move.global_position = pixel; Input.parse_input_event(move)
	await frames(1)
	var ready := is_instance_valid(button) and visible_rect(button).has_point(point)
	check(ready, "route remains beneath pointer before click " + id)
	if not ready: return
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = pixel; event.global_position = pixel; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; Input.parse_input_event(event)
		await frames(2)
	await frames(10)
	check(emitted[0] == 1, "one actual pressed signal for route " + id)
	if emitted[0] != 1:
		print("COMPANY_CYCLE_UI_CLICK_DIAGNOSTIC ", JSON.stringify({"id":id,"clicked_rect":str(last_rect),"point":str(point),"window_pixels":str(root.size),"viewport":str(root.get_visible_rect()),"pressed":emitted[0],"current_rect":str(visible_rect(button)) if is_instance_valid(button) else "freed","kind":ui.current_kind,"company_view":str(ui.get_meta("company_view", ""))}))

func text_under(parent: Node) -> String:
	var result := str(parent.text) if parent is Label or parent is Button else ""
	for child in parent.get_children(): result += "\n" + text_under(child)
	return result

func opportunity(status: String) -> Dictionary:
	for item in game.company_cycle_view().opportunities:
		if str(item.status) == status: return item
	return {}

func assert_readonly_view() -> void:
	var before := JSON.stringify(game.state)
	var first: Dictionary = game.company_cycle_view()
	check(first == game.company_cycle_view(), "model view is deterministic")
	check(JSON.stringify(game.state) == before, "model view does not mutate saved state")
	ui._select_company_view("overview"); await frames()
	check(JSON.stringify(game.state) == before, "opening company overview does not mutate saved state")
	var rendered := JSON.stringify(game.state)
	ui._select_company_view("overview"); await frames()
	check(JSON.stringify(game.state) == rendered, "repeated company rendering is read only")
	check(node("CompanyCycle") != null and node("CycleMoney_cash") is Label, "actual company cycle and economy render")
	check(str(node("CycleMoney_cash").text).replace(",", "").contains("¥" + str(int(game.state.cash))), "displayed cycle cash matches actual balance")

func fixture_delivery(id: String, rating: String) -> void:
	print("COMPANY_CYCLE_UI_FIXTURE model delivery history id=", id, " rating=", rating, "; no cash, skills, offer, or acceptance overrides")
	var source: Dictionary = CATALOG.by_id("service-0-case-0")
	var receipt := {"case_id":str(source.id),"client":str(source.client),"title":str(source.title),"rating":rating,"satisfaction_after":75,"checks":[{"passed":true}],"day":int(game.state.day)}
	game.state.completed_ids.append(id)
	game.state.history.append({"id":id,"case_id":str(source.id),"day":int(game.state.day)})
	var cash := int(game.state.cash)
	check(bool(CYCLE.record_delivery(game, id, receipt).changed), "validated model fixture recorded " + id)
	check(int(game.state.cash) == cash, "model fixture does not pay money")

func actual_first_delivery() -> void:
	print("COMPANY_CYCLE_UI_FIXTURE actual first-story VM repair, diagnostics, and delivery with normal starting funds")
	check(game.accept_mission(), "ordinary first story accepted")
	game.vm_run("ssh client"); check(game.capture_baseline(), "actual baseline saved")
	check(game.vm_write(str(game.vm_info().config_path), REPAIR), "public VM configuration written")
	game.vm_run("systemctl restart " + str(game.vm_info().service))
	for _round in 3:
		for probe in game.diagnostic_probes():
			if not bool(probe.get("fresh", false)) or not bool(probe.get("passed", false)): game.run_diagnostic(str(probe.id))
		game.verify()
		if game.can_deliver(): break
	check(game.deliver(), "real first-story delivery creates follow-up")

func assert_wrapping(parent: Node) -> int:
	var text_checks := 0
	if parent is Label or parent is Button:
		var rect: Rect2 = parent.get_global_rect()
		check(rect.position.x >= -1 and rect.end.x <= root.get_visible_rect().end.x + 1, "cycle content fits viewport: " + str(parent.name))
		if parent is Label and str(parent.text).length() > 30:
			text_checks += 1
			check(parent.autowrap_mode != TextServer.AUTOWRAP_OFF and not parent.clip_text, "long customer copy permits wrapping without clipping")
			var font: Font = parent.get_theme_font("font")
			var unwrapped_width := font.get_string_size(str(parent.text), HORIZONTAL_ALIGNMENT_LEFT, -1, parent.get_theme_font_size("font_size")).x
			if unwrapped_width > rect.size.x + 1: check(parent.get_line_count() > 1, "text wider than available space actually wraps")
	for child in parent.get_children(): text_checks += assert_wrapping(child)
	return text_checks

func finance_presentation_fixtures() -> void:
	print("COMPANY_CYCLE_UI_FIXTURE finance view-only data; no gameplay balance or payroll writes")
	var state_before := JSON.stringify(game.state)
	for child in ui.modal_body.get_children(): ui.modal_body.remove_child(child); child.queue_free()
	var body := VBoxContainer.new(); body.name = "FinancePresentationFixture"; ui.modal_body.add_child(body)
	var economy := {"cash":1000,"due_next_day":4000,"settlement_costs":1000,"day_cash_after":0,"care_net":0,"payroll_outstanding":1500,"payroll_arrears_after":500,"receivable_total":4000,"draft_total":9000}
	PANEL._economy(ui, body, economy); await frames()
	var text := text_under(body)
	check(text.contains("日締めの支払見込み") and text.contains("翌日入金前"), "cash forecast labels distinguish payments from future invoice income")
	check(str(node("CycleMoney_settlement_costs").text) == "¥1,000", "cash outflow shows affordable payment instead of entire payroll obligation")
	check(str(node("CycleCashForecast").text).contains("¥0"), "draft and uncollected invoices never appear as current closing cash")
	check(node("CyclePayrollArrears") is Label and str(node("CyclePayrollArrears").text).contains("¥500"), "remaining payroll arrears has an explicit amount")
	check(node("CyclePayroll") is Button, "remaining arrears exposes staffing route")
	assert_wrapping(body)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var folder := OS.get_environment("WHL_CAPTURE_DIR")
		if not folder.is_empty():
			DirAccess.make_dir_recursive_absolute(folder)
			check(root.get_texture().get_image().save_png(folder.path_join("finance-arrears-fixture" + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture explicit finance fixture")
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	economy.care_net = 1000; economy.settlement_costs = 1500; economy.day_cash_after = 500; economy.payroll_arrears_after = 0
	PANEL._economy(ui, body, economy); await frames()
	check(node("CyclePayrollArrears") == null and node("CyclePayroll") == null, "earned same-day care income that covers wages does not cause a false arrears warning")
	check(JSON.stringify(game.state) == state_before, "finance fixtures never change world balance or payroll")
	ui._select_company_view("overview"); await frames()

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): push_error("Requires isolated QA profile"); quit(2); return
	game.set_process(false)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900); ui._set_text_scale(1.3 if narrow else 1.0)
	check(ui._new_game() and game.choose_strategy("advisory"), "ordinary fixture company")
	await assert_readonly_view()
	fixture_delivery("cycle-locked-fixture", "on_time")
	var locked := opportunity("locked")
	check(not locked.is_empty(), "level-one fixture has real locked opportunity")
	await assert_readonly_view()
	if not locked.is_empty():
		check(text_under(node("CompanyCycle")).contains(str(locked.locked_reason)), "locked card explains actual requirement")
		await click("CyclePrepare_" + str(locked.id).validate_node_name())
		check(ui.current_kind == "company" and str(ui.get_meta("company_view")) == "growth", "locked route opens actual growth view")
	check(ui._new_game() and game.choose_strategy("advisory"), "reset to ordinary funds before real delivery")
	ui.close_panel(false, false); actual_first_delivery(); await frames()
	var ready := opportunity("ready")
	check(not ready.is_empty(), "real delivery earns ready consultation")
	await assert_readonly_view()
	if not ready.is_empty():
		check(text_under(node("CompanyCycle")).contains(str(ready.source_title)), "card explains actual source delivery")
		var cash_before := int(game.state.cash); var profit_before := int(game.state.profit)
		await click("CycleOpen_" + str(ready.id).validate_node_name())
		var actual_offer := {}
		for offer in game.state.offers:
			if str(offer.id) == str(ui.board_selected_id): actual_offer = offer
		check(ui.current_kind == "sales" and node("QuoteBack") is Button, "ready action opens actual offer detail")
		check(not actual_offer.is_empty() and str(actual_offer.get("case_id", "")) == str(ready.case_id) and str(actual_offer.get("client", "")) == str(ready.client), "offer detail matches consultation customer and case")
		check(not game.state.accepted and str(game.state.current_contract_id).is_empty(), "opening consultation does not accept work")
		check(int(game.state.cash) == cash_before and int(game.state.profit) == profit_before, "opening consultation never pays or spends cash")
	fixture_delivery("cycle-paused-fixture", "late")
	var paused := opportunity("paused")
	check(not paused.is_empty(), "validated late-delivery model fixture pauses consultation")
	await assert_readonly_view()
	if not paused.is_empty():
		check(text_under(node("CompanyCycle")).contains(str(paused.recovery_goal)), "paused card explains actual recovery condition")
		var text_checks := assert_wrapping(node("CompanyCycle"))
		if narrow: check(text_checks > 0, "long customer copy checked at 130 percent narrow layout")
		var before := int(game.state.cash)
		await click("CycleRecover_" + str(paused.id).validate_node_name())
		check(ui.current_kind == "sales" and str(ui.board_selected_id).is_empty(), "paused recovery opens ordinary sales list")
		check(str(ui.sales_search) == str(paused.client) and str(ui.sales_view) == "inquiries", "recovery route filters actual inquiries to the affected customer")
		check(int(game.state.cash) == before and not game.state.accepted, "recovery route changes no cash or acceptance")
	ui._select_company_view("overview"); await frames()
	await finance_presentation_fixtures()
	print("COMPANY_CYCLE_UI_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " narrow=", narrow, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
