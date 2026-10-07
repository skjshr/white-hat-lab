extends SceneTree

const UI = preload("res://scripts/interface.gd")
const OPERATIONS = preload("res://scripts/operations_dispatch.gd")
const MAINTENANCE = preload("res://scripts/maintenance_dispatch.gd")
const STAFF_HANDOFF = preload("res://scripts/staff_work_handoff.gd")

var game
var failures: Array[String] = []

func _init() -> void:
	create_timer(35.0).timeout.connect(func(): push_error("operations dispatch QA timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func run() -> void:
	var ui = UI.new()
	root.add_child(ui)
	await process_frame
	game = ui._game()
	game.set_process(false)
	ui._new_game()
	check(game.choose_strategy("advisory"), "strategy selected")
	check(game.start_free_career(), "career started")
	game.state.credit = 100000
	game.state.peak_profit = 100000
	game.state.skills = {"advisory":3,"operations":3,"response":3}
	game._make_offers()
	var multi: Dictionary = {}
	var other: Dictionary = {}
	for offer in game.state.offers:
		if not bool(offer.get("unlocked", false)):
			continue
		if multi.is_empty() and int(offer.get("targets", 1)) > 1:
			multi = offer
		elif other.is_empty():
			other = offer
	check(not multi.is_empty() and not other.is_empty(), "two accepted contract fixtures")
	if multi.is_empty() or other.is_empty():
		_finish()
		return
	var multi_id := str(multi.get("id", ""))
	var other_id := str(other.get("id", ""))
	check(game.choose_contract(multi_id), "multi-site contract accepted")
	check(game.choose_contract(other_id), "second contract accepted")
	var active_id := str(game.state.current_contract_id)
	var active_target := int(game.state.target_index)
	var active_vm_key := str(game._vm_key())
	var active_clock := int(game.state.clock_minutes)
	var before_state: Dictionary = game.state.duplicate(true)
	var before_assignments: Dictionary = game._assignments.duplicate(true)
	var valid_path := str(game.save_path)
	game.save_path = "user://missing-operations-dispatch-save/dispatch.json"
	check(not OPERATIONS.assign(game, "aya", multi_id, 1), "failed cross-contract save rejected")
	game.save_path = valid_path
	check(game.state == before_state and game._assignments == before_assignments, "failed save restores projection and assignment")
	check(str(game.state.current_contract_id) == active_id and int(game.state.target_index) == active_target and str(game._vm_key()) == active_vm_key and int(game.state.clock_minutes) == active_clock, "failed save preserves active VM context")
	var preview: Dictionary = OPERATIONS.quote(game, "aya", multi_id, 1)
	check(bool(preview.get("ok", false)) and float(preview.get("duration", 0.0)) > 0.0, "cross-contract target quote")
	check(OPERATIONS.assign(game, "aya", multi_id, 1), "cross-contract target assigned")
	var assignment: Dictionary = game.state.assignments.get("aya", {})
	check(str(game.state.current_contract_id) == active_id and int(game.state.target_index) == active_target and str(game._vm_key()) == active_vm_key, "assignment leaves player projection unchanged")
	check(str(assignment.get("contract_id", "")) == multi_id and int(assignment.get("target_index", -1)) == 1 and str(assignment.get("vm_key", "")) == multi_id+"/site-1", "assignment binds requested target VM")
	check(game.save_game() and game.load_game(), "assignment reloads")
	check(str(game.state.assignments.get("aya", {}).get("contract_id", "")) == multi_id and int(game.state.assignments.get("aya", {}).get("target_index", -1)) == 1, "assignment survives reload")
	var saved_path := str(game.save_path)
	game.save_path = "user://missing-operations-finish-save/finish.json"
	game._process(30.0)
	game.save_path = saved_path
	var after_failed_finish: Dictionary = STAFF_HANDOFF.from_context(game.state.contract_contexts.get(multi_id, {}), 1, game.state.assignments)
	check(str(game.state.assignments.get("aya", {}).get("status", "")) == "working" and after_failed_finish.receipts.is_empty(), "failed completion save rolls back receipt and leaves work retryable")
	game._process(30.0)
	check(str(game.state.current_contract_id) == active_id and int(game.state.target_index) == active_target, "completion restores active projection")
	var completed: Dictionary = game.state.assignments.get("aya", {})
	check(str(completed.get("status", "")) == "done", "cross-contract colleague completes")
	var handoff: Dictionary = STAFF_HANDOFF.from_context(game.state.contract_contexts.get(multi_id, {}), 1, game.state.assignments)
	check(handoff.receipts.size() == 1 and str(handoff.receipts[0].member_id) == "aya" and bool(handoff.receipts[0].time_known), "completed receipt saved once with its exact target and time")
	var vm_state: Dictionary = game.state.vm_states.get(multi_id+"/site-1", {})
	var report := str(vm_state.get("fs", {}).get("/home/operator/aya-inspection.txt", ""))
	check(not report.is_empty() and str(handoff.receipts[0].get("report_content", "")) == report, "receipt captures the actual completed report including observations")
	check(not report.is_empty(), "completed work persists on requested VM")
	check(OPERATIONS.assign(game, "aya", other_id, 0), "same worker can take a different target after completion")
	game._process(30.0)
	handoff = STAFF_HANDOFF.from_context(game.state.contract_contexts.get(multi_id, {}), 1, game.state.assignments)
	check(handoff.receipts.size() == 1 and str(handoff.receipts[0].result_path) == str(completed.result_path), "later assignment does not overwrite target receipt")
	check(game.save_game() and game.load_game(), "target work receipt survives reload")
	handoff = STAFF_HANDOFF.from_context(game.state.contract_contexts.get(multi_id, {}), 1, game.state.assignments)
	check(handoff.receipts.size() == 1 and str(handoff.receipts[0].member_id) == "aya", "reloaded target keeps its receipt without duplicate")
	await _priority_dispatch()
	_finish()

func _priority_dispatch() -> void:
	var fixture=preload("res://tests/care_fixture.gd")
	var rebuilt: Dictionary=fixture.build(game)
	check(bool(rebuilt.get("ok",false)),"build reconstructed care fixture: "+str(rebuilt.get("error","")))
	if not bool(rebuilt.get("ok",false)):return
	check(fixture.load_into(game,rebuilt.state),"reconstructed legacy-scope fixture reloads")
	if game.state.get("care_agreements", {}).is_empty():
		check(false, "care fixture has an agreement")
		return
	var existing_client := str(game.state.care_agreements.keys()[0])
	check(game.end_day(), "fixture advances to a maintenance day")
	game.set_offer_plan("care")
	# This probe dispatches ordinary VM maintenance; a manual-only pentest may
	# sort first on the modern board. Request a stable different-client service.
	game.state.market_leads=["service-0-case-0"];game.state.market_day=int(game.state.day);game._make_offers()
	var care_offer: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id",""))=="service-0-case-0" and bool(offer.get("market_available",false)) and bool(offer.get("unlocked", false)) and str(offer.get("client", "")) != existing_client and not game.state.care_agreements.has(str(offer.get("client", ""))):
			care_offer = offer
			break
	check(not care_offer.is_empty() and game.choose_contract(str(care_offer.get("id", ""))), "second real care client accepted")
	if care_offer.is_empty():
		return
	check(_solve_care_contract() and game.deliver(), "second care delivery creates a live maintenance scope")
	check(game.end_day(), "second care delivery advances to another maintenance day")
	var second_client := str(care_offer.get("client", ""))
	game.set_maintenance_owner(existing_client, "aya")
	game.set_maintenance_owner(second_client, "aya")
	var jobs: Array = game.maintenance_jobs()
	var existing_job: Dictionary = game._maintenance_job_for(existing_client)
	var second_job: Dictionary = game._maintenance_job_for(second_client)
	check(str(existing_job.get("status", "")) == "pending" and str(second_job.get("status", "")) == "pending", "two live pending maintenance jobs")
	game.set_colleague_runtime_availability("aya", true)
	check(MAINTENANCE.prioritize(game, second_client), "second client prioritized")
	check(str(game.state.maintenance_priority[0]) == second_client, "priority order is persisted in memory")
	check(game.save_game() and game.load_game(), "priority survives reload")
	check(str(game.state.maintenance_priority[0]) == second_client, "priority survives restart")
	var before_failed_priority: Dictionary = game.state.duplicate(true)
	var valid_path := str(game.save_path)
	game.save_path = "user://missing-operations-priority-save/priority.json"
	check(not MAINTENANCE.prioritize(game, existing_client), "failed priority save rejected")
	game.save_path = valid_path
	check(game.state == before_failed_priority, "failed priority save rolls back")
	game.set_colleague_runtime_availability("aya", true)
	game._process(0.3)
	check(str(game._maintenance_job_for(second_client).status) == "working" and str(game._maintenance_job_for(existing_client).status) == "pending", "dispatcher starts prioritized client first")

func _solve_care_contract() -> bool:
	game.inspect_mission()
	for index in game.state.targets.size():
		game.select_target(index)
		game.vm_run("ssh client")
		var scenario: Dictionary = game._scenario()
		game.vm_write(str(game.vm_info().config_path), game._vm().configuration_text(scenario.get("desired", {})))
		game.vm_run("systemctl restart "+str(game.vm_info().service))
		if int(game.state.chapter) == 1:
			game.vm_run("restic backup /srv/data")
			game.vm_run("restic restore latest --target /restore")
		for round_index in 3:
			for probe in game.diagnostic_probes():
				game.run_diagnostic(str(probe.get("id", "")))
		game.verify()
	return game.can_deliver()

func _finish() -> void:
	print("OPERATIONS_DISPATCH failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
