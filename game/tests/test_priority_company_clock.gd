extends "res://tests/test_saas_priority_market.gd"
## Exercises company-clock catch-up for accepted priority work. The native paid
## handoff fixture is loaded read-only; all mutations use a QA save path.

const PRIORITY_ENGINE := preload("res://scripts/saas_priority.gd")
const CLOCK_SYNC := preload("res://scripts/priority_company_clock.gd")
const ANCHOR_MINUTE := "priority_company_clock_anchor_minute"
const ANCHOR_ELAPSED := "priority_company_clock_anchor_elapsed"

var accepted_state: Dictionary = {}

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-priority-company-clock-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".bak", prefix + ".previous", prefix + ".settings"]); set_paths(paths)
	source_path = OS.get_environment("WHL_PRIORITY_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_PRIORITY_SOURCE points to a read-only paid handoff save"); finish(); return
	source_hash = FileAccess.get_sha256(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	if file == null:
		check(false, "QA save path opens"); finish(); return
	file.store_string(FileAccess.get_file_as_string(source_path)); file.close()
	if not game.load_game(): check(false, "paid handoff save loads"); finish(); return
	game._make_offers()
	if not game.end_day(): check(false, "prior engagement settles to publish a priority offer"); finish(); return
	var offer := priority_offer().duplicate(true)
	if not bool(offer.get("market_available", false)):
		check(false, "priority offer is available"); finish(); return
	if not game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)) or not game.choose_contract(str(offer.id)):
		check(false, "priority contract accepts through the normal market"); finish(); return
	accepted_state = game.state.duplicate(true)
	_test_maintenance_elapsed()
	_test_explicit_action_is_not_double_counted()
	_test_other_contract_deadline_loss()
	_test_legacy_anchor_and_read_only_views()
	_test_save_retry_is_atomic()
	_test_day_rollover()
	finish()

func _restore_accepted() -> void:
	game.state = accepted_state.duplicate(true)
	game._assignments = game.state.get("assignments", {}).duplicate(true)
	game._machine = null; game._machine_key = ""

func _set_elapsed(minutes: int) -> void:
	PRIORITY_ENGINE.advance(game.state.advanced, minutes)
	game.state.work[ANCHOR_MINUTE] = game._company_absolute_minute()
	game.state.work[ANCHOR_ELAPSED] = int(game.state.advanced.elapsed_minutes)
	game._sync_target(); game._sync_contract_context()

func _test_maintenance_elapsed() -> void:
	_restore_accepted()
	var start := int(game.state.clock_minutes)
	var day := int(game.state.day)
	var job := {"work_started_at":float(start),"work_started_day":day,"segment_minutes":12.0,"total":12.0,"remaining":0.0}
	game._advance_crew_clock(job, true)
	check(int(game.state.advanced.elapsed_minutes) == 12 and int(game.state.clock_minutes) == start + 12, "12-minute completed maintenance advances company time and priority clock exactly 12")

func _test_explicit_action_is_not_double_counted() -> void:
	_restore_accepted()
	var start := int(game.state.clock_minutes)
	var result: Dictionary = game.advanced_action("wait")
	check(bool(result.get("changed", false)) and int(game.state.advanced.elapsed_minutes) == 3 and int(game.state.clock_minutes) == start + 3, "a direct priority action advances both clocks once, not twice")

func _test_other_contract_deadline_loss() -> void:
	_restore_accepted()
	var priority_id := str(game.state.current_contract_id)
	var priority_context: Dictionary = game._context_from_projection()
	priority_context.id = priority_id
	game.state.contract_contexts[priority_id] = priority_context
	game.state.current_contract_id = "qa-ordinary-contract"
	game.state.contract = {"case_id":"qa-ordinary-contract","title":"別契約"}
	game.state.accepted = true
	game.state.work = {"minutes":0.0,"started_at":int(game.state.clock_minutes),"started_day":int(game.state.day),"incident_cost":0}
	game.state.advanced = {}
	game.state.targets = []; game.state.target_index = 0
	game._work_add(15.0)
	var saved_priority: Dictionary = game.state.contract_contexts[priority_id]
	var saved_work: Dictionary = saved_priority.work
	var model: Dictionary = saved_priority.advanced
	check(int(model.elapsed_minutes) == 15 and int(saved_work.incident_cost) == 8400, "another contract crossing priority cutoffs advances inactive work and charges its 5,400 business loss plus 3,000 impact loss")
	check(int(saved_work.get("saas_costs", {}).get("business_cost", 0)) == 5400 and int(saved_work.get("saas_costs", {}).get("impact_cost", 0)) == 3000, "deadline and background losses are booked to the priority contract only")
	check(int(game.state.work.get("incident_cost", 0)) == 0 and not game.state.work.has("saas_costs"), "the active ordinary contract receives no priority incident charges")
	var costs_before: Dictionary = saved_work.saas_costs.duplicate(true)
	CLOCK_SYNC.sync_state(game.state, game._company_absolute_minute())
	check(JSON.stringify(saved_work.saas_costs) == JSON.stringify(costs_before), "re-reading the already caught-up company clock creates no repeated impact")

func _test_legacy_anchor_and_read_only_views() -> void:
	_restore_accepted()
	_set_elapsed(7)
	game.state.work.erase(ANCHOR_MINUTE); game.state.work.erase(ANCHOR_ELAPSED)
	var before := int(game.state.advanced.elapsed_minutes)
	game.advanced_view(); game.contract_queue()
	check(not game.state.work.has(ANCHOR_MINUTE) and int(game.state.advanced.elapsed_minutes) == before, "read-only views do not create migration anchors or advance priority time")
	game._sync_priority_company_clock()
	check(int(game.state.advanced.elapsed_minutes) == before and game.state.work.has(ANCHOR_MINUTE) and int(game.state.work.get(ANCHOR_ELAPSED, -1)) == before, "first mutation anchors an old save at its existing elapsed time without retroactive charges")
	game._work_add(1.0)
	check(int(game.state.advanced.elapsed_minutes) == before + 1, "only company time after legacy anchoring is applied")

func _test_save_retry_is_atomic() -> void:
	_restore_accepted()
	_set_elapsed(5)
	var state_before := JSON.stringify(game.state)
	var good_path := str(game.save_path)
	game.save_path = "user://missing-priority-clock-dir-%s/contract.json" % OS.get_process_id()
	var failed: Dictionary = game.advanced_action("wait")
	check(not bool(failed.get("ok", false)) and JSON.stringify(game.state) == state_before, "failed save rolls back elapsed time, anchors, losses, evidence and company clock together")
	game.save_path = good_path
	var retried: Dictionary = game.advanced_action("wait")
	var costs: Dictionary = game.state.work.get("saas_costs", {})
	check(bool(retried.get("ok", false)) and int(game.state.advanced.elapsed_minutes) == 8, "retry advances the priority clock exactly once")
	check(int(game.state.work.incident_cost) == 7500 and int(costs.get("business_cost", 0)) == 4500 and int(costs.get("impact_cost", 0)) == 3000, "retry saves urgent cutoff and background losses once in the proper cost fields")

func _test_day_rollover() -> void:
	_restore_accepted()
	game.state.clock_minutes = 1080
	game.state.work[ANCHOR_MINUTE] = game._company_absolute_minute()
	game.state.work[ANCHOR_ELAPSED] = int(game.state.advanced.elapsed_minutes)
	var previous_day := int(game.state.day)
	if not game.end_day():
		check(false, "career day settles across rollover"); return
	var context: Dictionary = game.state.contract_contexts.get(str(accepted_state.current_contract_id), {})
	check(int(game.state.day) == previous_day + 1 and int(context.get("advanced", {}).get("elapsed_minutes", -1)) == 900, "day rollover advances an open priority context through 15 hours from 18:00 to next-day 09:00")

func finish() -> void:
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "native source remains byte identical")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PRIORITY_COMPANY_CLOCK_TEST_PASS" if failures.is_empty() else "PRIORITY_COMPANY_CLOCK_TEST_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
