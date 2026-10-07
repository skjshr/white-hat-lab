extends SceneTree
## Isolated model fixture, not native or first-time-player evidence. Only company
## resources and market presentation are synthetic; care and invoices are earned
## through the existing VM, verification, delivery and maintenance APIs.
const MODEL = preload("res://scripts/company_workday.gd")
const CARE_FIXTURE = preload("res://tests/care_fixture.gd")
var game
var failures: Array[String] = []
var paths: Array[String] = []

func _init() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("company workday timeout"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value: failures.append(label); print("FAIL: ", label)

func _offer(case_id: String) -> Dictionary:
	game.state.market_leads = [case_id]; game.state.market_day = int(game.state.day); game._make_offers()
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == case_id and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)): return offer
	return {}

func _job(snapshot: Dictionary, kind: String, id: String = "") -> Dictionary:
	for job in snapshot.jobs:
		if str(job.kind) == kind and (id.is_empty() or str(job.id) == id): return job
	return {}

func _candidate(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.member) == id: return row
	return {}

func _finish() -> void:
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COMPANY_WORKDAY_TEST_PASS" if failures.is_empty() else "COMPANY_WORKDAY_TEST_FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game = load("res://scripts/game.gd").new()
	var stem := "user://qa-company-workday-%d" % OS.get_process_id()
	game.save_path = stem+".json"; game.backup_path = stem+".bak"; game.previous_path = stem+".previous"; game.settings_path = stem+".settings"
	paths.assign([game.save_path,game.backup_path,game.previous_path,game.settings_path])
	root.add_child(game); game.set_process(false)
	check(game.new_game() and game.choose_strategy("operations"), "isolated company starts")
	game.state.cash = 100000; game.state.credit = 100; game.state.equipment = ["teamdesk"]
	check(game.learn_skill("advisory") and game.start_free_career() and game.hire_staff("mio"), "synthetic company eligibility and actual hiring")
	var care_offer := _offer("service-1-case-0")
	check(not care_offer.is_empty(), "ordinary care offer exists")
	if care_offer.is_empty(): _finish(); return
	check(game.set_offer_plan("care") and game.choose_contract(str(care_offer.id)), "care contract accepted")
	check(CARE_FIXTURE._solve(game) and game.deliver(), "actual care service verified and delivered")
	if failures.size() > 0: _finish(); return
	var delivered_view := MODEL.snapshot(game)
	for row in delivered_view.jobs:
		if bool(row.get("draft",false)):
			check(int(row.fee)==int(row.invoice.amount) and str(row.fee_scope)=="invoice", "delivered fee includes earned delivery bonus in invoice amount")
	var client := str(care_offer.client)
	# Verified delivery already fulfils that day's retained inspection. Use the
	# normal day transition to create tomorrow's pending care, preserving the draft.
	check(game.end_day(), "advance from verified delivery to a new workday")
	if failures.size() > 0: _finish(); return
	var normal_offer := _offer("service-0-case-0")
	check(not normal_offer.is_empty(), "different-customer normal work exists")
	if normal_offer.is_empty(): _finish(); return
	check(game.set_offer_plan("priority") and game.choose_contract(str(normal_offer.id)), "short-deadline work accepted")
	var initial := MODEL.snapshot(game)
	var care := _job(initial, "maintenance")
	var urgent := _job(initial, "emergency", str(normal_offer.id))
	check(not care.is_empty() and str(care.get("status", "")) == "pending" and not urgent.is_empty() and int(initial.counts.draft) == 1, "one board retains pending care, urgent investigation and unposted delivery")
	if care.is_empty() or urgent.is_empty(): _finish(); return
	check(str(care.deadline.kind) == "day_end" and int(care.deadline.minute) == -1 and int(care.fee) == 750 and int(initial.economy.care_gross) == 0 and int(initial.economy.care_cost) == 100, "unperformed care has no income and no invented closing hour")
	var before: Dictionary = game.state.duplicate(true)
	var crew_before: Dictionary = game._assignments.duplicate(true)
	var selection := MODEL.snapshot(game, str(urgent.key))
	var aya := _candidate(selection.candidates, "aya")
	var ren := _candidate(selection.candidates, "ren")
	check(bool(aya.can_enqueue) and bool(aya.can_finish) and str(aya.task_name).begins_with("調査工程") and not bool(ren.can_enqueue) and not str(ren.reason).is_empty(), "forecast describes an investigation and rejects incompatible verification role")
	MODEL.signature(game); MODEL.snapshot(game, str(care.key))
	selection.jobs[0].title = "local projection only"
	check(game.state == before and game._assignments == crew_before, "repeated view, candidates and returned edits cannot change work, money or originals")
	check(game.dispatch_enqueue("aya", str(normal_offer.id), int(urgent.target)), "reserve actual investigation")
	var duplicate := _candidate(MODEL.candidates(game, urgent), "mio")
	check(bool(duplicate.get("duplicate",false)) and not bool(duplicate.can_enqueue) and int(duplicate.finish_minute) == -1, "same-role duplicate has no false completion promise")
	# The synthetic late clock distinguishes real employee shifts from the two
	# original colleagues; neither the care deadline nor Aya gains an 18:00 limit.
	var structure_before := MODEL.signature(game)
	game.state.clock_minutes = 1075
	var late := MODEL.snapshot(game, str(care.key))
	check(MODEL.signature(game) == structure_before, "clock updates do not recreate workday controls")
	var mio := _candidate(late.candidates, "mio")
	var aya_care := _candidate(late.candidates, "aya")
	check(bool(mio.can_enqueue) and int(mio.finish_day) > int(game.state.day) and str(mio.risk) == "next_day" and int(aya_care.finish_day) == int(game.state.day), "hired care rolls to a later shift while base colleague has no employee cutoff")
	for person in late.people:
		if str(person.id) == "aya": check(not bool(person.shift_limited) and int(person.shift_end) == -1, "base colleague publishes no invented shift limit")
	check(game.save_game() and game.load_game(), "workday survives JSON save and load")
	game.set_process(false)
	var resumed := MODEL.snapshot(game, str(care.key))
	check(int(_candidate(resumed.candidates,"mio").finish_day) == int(mio.finish_day) and int(resumed.counts.draft) == 1, "resume preserves queued workload and unposted invoice")
	var current_cash := int(game.state.cash)
	check(game.run_maintenance(client), "retained production inspection completes")
	var inspected := MODEL.snapshot(game)
	check(int(inspected.economy.care_gross) == 750 and int(inspected.economy.care_net) == 650 and int(game.state.cash) == current_cash, "successful inspection changes daily income forecast without collecting cash during view")
	_finish()
