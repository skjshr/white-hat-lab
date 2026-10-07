extends SceneTree
## Hiring decision -> same-job work allocation -> durable receipt, with delivery
## acceptance kept as the separate player-owned step.
const PREVIEW = preload("res://scripts/staffing_work_preview.gd")

var ui
var game
var failures: Array[String] = []

func _init() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("staffing decision UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func frames(count: int = 3) -> void:
	for _index in count: await process_frame

func modal_control(id: String):
	return ui.modal.find_child(id, true, false) if is_instance_valid(ui.modal) else null

func staffing_job_button(key: String):
	var choices = modal_control("StaffWorkChoices")
	if not is_instance_valid(choices): return null
	for child in choices.get_children():
		if child is Button and str(child.get_meta("work_key", "")) == key: return child
	return null

func is_inside(node: Node, ancestor: Node) -> bool:
	var cursor := node
	while cursor != null:
		if cursor == ancestor: return true
		cursor = cursor.get_parent()
	return false

func press_modal(id: String) -> bool:
	var button = modal_control(id)
	if not button is Button or button.disabled: return false
	button.pressed.emit()
	return true

func finish() -> void:
	for failure in failures: push_error(failure)
	print("STAFFING_DECISION_UI failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames()
	game = ui._game()
	game.set_process(false)
	var prefix := "user://qa-staffing-decision-%s.json" % OS.get_process_id()
	game.save_path = prefix
	game.backup_path = prefix + ".bak"
	game.previous_path = prefix + ".previous"
	game.settings_path = prefix + ".settings"
	check(ui._new_game(), "fresh isolated company starts")
	await frames()
	game.set_process(false)
	ui.guided_intro.skip()
	check(game.choose_strategy("advisory") and game.start_free_career(), "career setup")
	game.state.cash = 30000
	check(game.buy_equipment("teamdesk"), "real hiring seat is purchased")
	game.advance_delivery(30.0)
	check(game.take_delivery("teamdesk") and game.begin_delivery_placement("teamdesk") and game.place_delivery("teamdesk", game.equipment_slot("teamdesk")), "hiring seat arrives and is installed")
	# Unlock a real level-one backup contract so Haru's authored Ren role is valid.
	game.state.skills.operations = maxi(1, int(game.state.skills.get("operations", 0)))
	game.state.market_day = int(game.state.day)
	game.state.market_leads = ["service-1-case-0"]
	game._make_offers()
	var offer: Dictionary = {}
	for raw in game.state.offers:
		if raw is Dictionary and str(raw.get("case_id", "")) == "service-1-case-0" and bool(raw.get("unlocked", false)) and bool(raw.get("market_available", false)):
			offer = raw.duplicate(true)
			break
	if offer.is_empty():
		check(false, "a real eligible chapter-one contract is on today's market")
		finish()
		return
	var quote: Dictionary = game.contract_quote(offer)
	check(game.set_offer_quote(str(offer.id), int(quote.get("quoted_fee", 0))) and game.choose_contract(str(offer.id)), "real customer contract is accepted through the market API")
	var contract_id := str(game.state.current_contract_id)
	var job_key := "contract:%s:0" % contract_id

	ui.open_panel("staffing")
	await frames()
	check(press_modal("Candidate_haru"), "Haru candidate selected")
	var shift := modal_control("CandidateShift_haru") as OptionButton
	check(is_instance_valid(shift), "Haru shift selector is on the staffing panel")
	var morning_index := -1
	for index in game.staff_shift_catalog().size():
		if str(game.staff_shift_catalog()[index].get("id", "")) == "morning": morning_index = index
	if is_instance_valid(shift) and morning_index >= 0:
		shift.select(morning_index)
		shift.item_selected.emit(morning_index)
	await frames()
	var hire := modal_control("Hire_haru") as Button
	check(is_instance_valid(hire) and not hire.disabled, "Haru morning hiring is eligible")
	if is_instance_valid(hire): check(is_inside(hire, ui.modal_footer), "hire action is in the persistent modal footer")
	var before_hire := JSON.stringify(game.state)
	var valid_save := str(game.save_path)
	game.save_path = "user://qa-staff-hire-missing-%s/save.json" % OS.get_process_id()
	check(press_modal("Hire_haru"), "attempt hiring with an unavailable save path")
	game.save_path = valid_save
	await frames()
	check(JSON.stringify(game.state) == before_hire and not bool(game.state.staff.get("haru", {}).get("active", false)), "failed hire save rolls back cash, staff, and payroll")
	check(press_modal("Hire_haru"), "retry same hiring action after restoring save path")
	await frames()
	check(bool(game.state.staff.get("haru", {}).get("active", false)) and str(game.state.staff.haru.get("shift", "")) == "morning", "retry hires Haru on morning shift")
	var wage_rows: Array = game.state.staff_payroll.get("due", []).filter(func(row): return int(row.get("day", -1)) == int(game.state.day) and str(row.get("staff_id", "")) == "haru")
	check(wage_rows.size() == 1 and int(wage_rows[0].get("amount", 0)) == int(game.staff_daily_wage("haru", "morning")), "hire creates one correctly priced payroll row")

	var route := modal_control("StaffWorkRoute") as Button
	check(is_instance_valid(route), "hired-work route button is available")
	if is_instance_valid(route): check(is_inside(route, ui.modal_footer), "work route is in the persistent modal footer")
	check(press_modal("StaffWorkRoute"), "open the selected work route")
	await frames(5)
	check(str(ui.current_kind) == "board" and str(ui.operations_choices.get("workday_selected", "")) == job_key and str(ui.operations_choices.get("workday_member", "")) == "haru", "route opens the same accepted job and selected member")
	check(not game._assignments.has("haru") and game.state.dispatch_queues.get("haru", []).is_empty(), "opening the route does not allocate work")
	var enqueue := modal_control("WorkdayEnqueue") as Button
	check(is_instance_valid(enqueue) and not enqueue.disabled, "explicit allocation action is enabled for the selected job")
	check(press_modal("WorkdayEnqueue"), "player explicitly allocates and starts Haru's work")
	await frames(5)
	var active_job: Dictionary = game._assignments.get("haru", {})
	check(str(active_job.get("status", "")) == "working" and str(active_job.get("contract_id", "")) == contract_id and int(active_job.get("target_index", -1)) == 0, "explicit action starts the same member on the same target")
	ui.set_meta("staff_view", "active")
	ui.set_meta("staff_selected_id", "haru")
	ui.set_meta("staff_work_key", job_key)
	ui.open_panel("staffing")
	await frames(5)
	var release_working := modal_control("Release_haru") as Button
	check(is_instance_valid(release_working) and release_working.disabled, "active work disables release on the staffing screen")
	check(is_instance_valid(staffing_job_button(job_key)), "assigned work remains visible before the work clock advances")
	game.set_office_clock_paused(false)
	game._process(30.0)
	await frames(5)
	var release_done := modal_control("Release_haru") as Button
	var completed_work_button := staffing_job_button(job_key) as Button
	check(is_instance_valid(release_done) and not release_done.disabled, "staffing screen enables release after work completes without re-entry")
	check(is_instance_valid(completed_work_button) and (completed_work_button.text.contains("再確認") or completed_work_button.text.contains("配分済")), "staffing job row refreshes in place to show prior work")
	var receipts: Array = game.state.contract_contexts.get(contract_id, {}).get("targets", [{}])[0].get("work_receipts", [])
	check(str(game.state.assignments.get("haru", {}).get("status", "")) == "done" and receipts.any(func(row): return str(row.get("member_id", "")) == "haru" and str(row.get("role", "")) == "ren"), "work completes into the saved target receipt")
	check(not game.can_deliver() and not bool(game.state.contract_contexts.get(contract_id, {}).get("completed", false)), "colleague result does not complete verification or delivery")
	check(game.save_game() and game.load_game(), "save and reload the accepted contract")
	var after_reload_wages: Array = game.state.staff_payroll.get("due", []).filter(func(row): return int(row.get("day", -1)) == int(game.state.day) and str(row.get("staff_id", "")) == "haru")
	var resumed_receipts: Array = game.state.contract_contexts.get(contract_id, {}).get("targets", [{}])[0].get("work_receipts", [])
	check(after_reload_wages.size() == 1 and int(after_reload_wages[0].get("amount", 0)) == int(game.staff_daily_wage("haru", "morning")), "reload preserves one payroll charge")
	check(resumed_receipts.any(func(row): return str(row.get("member_id", "")) == "haru") and not game.can_deliver(), "reload preserves work receipt and separate delivery gate")
	ui.set_meta("staff_view", "active")
	ui.set_meta("staff_selected_id", "haru")
	ui.open_panel("staffing")
	await frames(4)
	var resumed_preview: Dictionary = PREVIEW.snapshot(game, "haru")
	var resumed_job: Dictionary = {}
	for row in resumed_preview.get("jobs", []):
		if str(row.get("key", "")) == job_key: resumed_job = row; break
	check(not resumed_job.is_empty() and bool(resumed_job.get("prior_work", false)) and not bool(resumed_job.get("demand", true)), "resumed staffing preview keeps the completed colleague work record")
	finish()
