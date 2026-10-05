extends SceneTree

## Engine integration for explicitly cancelling one ordinary career case.
## Career entry and a low-trust relation are controlled QA fixtures; accepted
## contracts, work, VM state, probes, accounting, and retry use Game APIs.
const GameScript = preload("res://scripts/game.gd")
const LEDGER = preload("res://scripts/day_ledger.gd")
const BUSINESS_APPS = preload("res://scripts/os_business_apps.gd")

var game
var failures: Array[String] = []
var original_save := ""
var original_backup := ""
var original_previous := ""
var closeout_id := ""
var archived_vm_key := ""
var old_vm: Dictionary = {}
var retry_case := "service-0-case-0"

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("CAREER_CLOSEOUT timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("CAREER_CLOSEOUT: " + label)

func _set_paths(target, prefix: String) -> void:
	target.save_path = "user://" + prefix + ".json"
	target.backup_path = target.save_path + ".bak"
	target.previous_path = target.save_path + ".previous"
	target.settings_path = target.save_path + ".settings"

func _offer(case_id: String) -> Dictionary:
	for row in game.state.offers:
		if str(row.get("case_id", "")) == case_id and bool(row.get("unlocked", false)) and bool(row.get("market_available", false)) and (row.get("supply_requirement", {}) is Dictionary and row.get("supply_requirement", {}).is_empty()): return row
	return {}

func _connect_and_fail_one_probe() -> bool:
	var login := str(game.vm_run("ssh client"))
	if not bool(game.vm_info().get("connected", false)) or login.is_empty(): return false
	var scenario: Dictionary = game._scenario()
	var desired: Dictionary = scenario.get("desired", {}).duplicate(true)
	if desired.is_empty(): return false
	var wrong := desired.duplicate(true)
	if wrong.has("staff"): wrong.staff = 0
	else:
		var first: Variant = wrong.keys()[0]
		wrong[first] = "off" if str(wrong[first]) != "off" else "on"
	var path := str(game.vm_info().get("config_path", ""))
	var text := str(game._vm().configuration_text(wrong))
	if path.is_empty() or not game.vm_write(path, text): return false
	if not str(game.vm_run("systemctl restart " + str(game.vm_info().service))).contains("active"): return false
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.get("id", "")))
	var failed := false
	for probe in game.diagnostic_probes():
		if bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and not bool(probe.get("passed", false)): failed = true
	return failed

func _solve_and_deliver() -> bool:
	if str(game.vm_run("ssh client")).is_empty() or not bool(game.vm_info().get("connected", false)): return false
	var scenario: Dictionary = game._scenario()
	var desired: Dictionary = scenario.get("desired", {}).duplicate(true)
	var info: Dictionary = game.vm_info()
	if not game.vm_write(str(info.get("config_path", "")), str(game._vm().configuration_text(desired))): return false
	if not str(game.vm_run("systemctl restart " + str(info.get("service", "")))).contains("active"): return false
	for attempt in 4:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))): game.run_diagnostic(str(probe.get("id", "")))
		if game.diagnostic_probes().all(func(probe): return bool(probe.recorded) and bool(probe.fresh) and bool(probe.passed)): break
	var verification: Array = game.verify()
	return not verification.is_empty() and verification.all(func(item): return bool(item.get("passed", false))) and game.can_deliver() and game.deliver()

func run() -> void:
	game = root.get_node("Game")
	game.set_process(false)
	var qa := "career-closeout-" + str(OS.get_process_id())
	_set_paths(game, qa)
	original_save = game.save_path; original_backup = game.backup_path; original_previous = game.previous_path
	game._reset_state()
	check(game.choose_strategy("advisory"), "set an advisory career strategy")
	# Synthetic post-story entry gate only; the case offer and all work below are authored/runtime.
	game.state.game_complete = true
	check(game.continue_business(), "enter career after synthetic story-complete gate")
	game.state.peak_profit = 100000
	game.state.credit = 1000
	game.state.trust = 1000
	game.state.skills = {"operations":3,"advisory":3,"response":3}
	game.state.market_leads = [retry_case, "service-1-case-0"]
	game.state.market_day = int(game.state.day)
	game._make_offers()
	var offer_a := _offer(retry_case)
	var offer_b := _offer("service-1-case-0")
	check(not offer_a.is_empty() and not offer_b.is_empty(), "ordinary authored offers available for two independent contexts")
	if offer_a.is_empty() or offer_b.is_empty():
		_finish(); return
	closeout_id = str(offer_a.id)
	check(game.choose_contract(closeout_id), "accept ordinary career contract through Game API")
	check(_connect_and_fail_one_probe(), "record a fresh failing probe after saving a wrong real VM configuration")
	archived_vm_key = str(game._vm_key())
	old_vm = game._vm().export_state()
	var failed_observation: bool = game.diagnostic_probes().any(func(p): return bool(p.get("recorded", false)) and bool(p.get("fresh", false)) and not bool(p.get("passed", false)))
	check(failed_observation and game.state.vm_states.has(archived_vm_key), "failed observation and VM snapshot are durable before cancellation")
	var saved_config := str(game.state.vm_states.get(archived_vm_key, {}).get("fs", {}).get(str(game.vm_info().get("config_path", "")), ""))
	check(not saved_config.is_empty(), "saved VM contains the deliberately wrong configuration")
	check(game.dispatch_enqueue("aya", closeout_id, 0), "queue a real crew task bound to the soon-to-close case")
	check(game.choose_contract(str(offer_b.id)), "accept an unrelated backup case")
	var unrelated_id := str(offer_b.id)
	check(game.dispatch_enqueue("ren", unrelated_id, 0), "queue an unrelated recovery-role task")
	check(game.switch_contract(closeout_id), "return to the target case while preserving the other context")
	var preview_before: Dictionary = game.contract_closeout_preview()
	var before_late_clock: int = game.state.clock_minutes
	game.state.clock_minutes = before_late_clock + 300
	var late_preview: Dictionary = game.contract_closeout_preview()
	check(bool(late_preview.late) and int(late_preview.satisfaction_after) == maxi(0, int(late_preview.satisfaction_before) - 18), "late cancellation has the larger customer consequence")
	game.state.clock_minutes = before_late_clock
	var json_before_preview := JSON.stringify(game.state)
	var machine_before_preview: Dictionary = game._vm().export_state()
	check(bool(preview_before.available), "supported accepted case can be cancelled")
	check(JSON.stringify(game.state) == json_before_preview and game._vm().export_state() == machine_before_preview, "preview is read-only")
	check(int(preview_before.cash_after) == int(game.state.cash) - int(preview_before.cash_cost), "preview exposes exact cash consequence")
	check(int(preview_before.open_after) == int(preview_before.open_before) - 1, "preview shows the released contract slot")
	var completed_before: Array = game.state.completed_ids.duplicate(true)
	var invoice_count_before: int = game.state.billing.invoices.size()
	var contracts_completed_before: int = int(game.state.contracts_completed)
	var peak_before: int = int(game.state.peak_profit)
	var profit_before: int = int(game.state.profit)
	var credit_before: int = int(game.state.credit)
	var earned_before: Dictionary = game.state.company_cycle.get("earned_goals", {}).duplicate(true)
	var target_count_before: int = game._open_contract_count()
	var state_before_failure: Dictionary = game.state.duplicate(true)
	var assignments_before_failure: Dictionary = game._assignments.duplicate(true)
	var machine_before_failure: Dictionary = game._machine.export_state()
	var machine_key_before_failure := str(game._machine_key)
	var normal_save: String = str(game.save_path)
	game.save_path = "user://closeout-missing-parent-" + str(OS.get_process_id()) + "/save.json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	check(not game.cancel_current_contract(), "save failure leaves cancellation retryable")
	check(game.state == state_before_failure and game._assignments == assignments_before_failure, "failed save restores exact state and crew assignments")
	check(game._machine.export_state() == machine_before_failure and str(game._machine_key) == machine_key_before_failure, "failed save restores VM runtime/key")
	game.save_path = normal_save; game.backup_path = original_backup; game.previous_path = original_previous
	for history_index in 100: game.state.history.append({"kind":"qa_noise","day":int(game.state.day)})
	check(game.cancel_current_contract(), "successful retry persists cancellation once")
	var outcome: Dictionary = game.state.get("last_receipt", {})
	check(str(outcome.get("kind", "")) == "cancellation" and str(outcome.get("rating", "")) == "cancelled", "cancellation is a separate outcome, not a delivery")
	check(game.state.get("completed_ids", []) == completed_before and int(game.state.contracts_completed) == contracts_completed_before, "completion counters remain unchanged")
	check(game.state.billing.invoices.size() == invoice_count_before and int(game.state.peak_profit) == peak_before, "no invoice or growth reward is created")
	check(int(game.state.profit) == profit_before-int(preview_before.costs) and int(game.state.cash) == int(preview_before.cash_after), "only actual base and incident work cost is charged")
	check(int(game.state.credit) == maxi(0,credit_before-3) and int(game.state.trust) == int(game.state.credit), "trust loss is applied")
	check(game.state.company_cycle.get("earned_goals", {}) == earned_before, "cancellation save does not award a milestone")
	check(not game.state.contract_contexts.has(closeout_id) and game.state.contract_closeouts.has(closeout_id), "active context removed and full closeout archive retained")
	check(game.state.contract_closeouts[closeout_id].context.get("targets", []).size() > 0 and game.state.contract_closeouts[closeout_id].vm_states.has(archived_vm_key), "archive retains targets and measured VM state")
	check(game.state.vm_states.get(archived_vm_key, {}) == old_vm, "customer VM remains unchanged by closeout")
	check(game._machine == null and str(game._machine_key).is_empty(), "successful closeout releases the old live VM instance and key")
	check(game.state.history.size() == 100 and game.state.history.any(func(row): return str(row.get("kind", "")) == "cancellation" and str(row.get("id", "")) == closeout_id), "cancellation remains in the rolling history when it starts at the 100-event limit")
	var resumed = GameScript.new(); root.add_child(resumed); resumed.set_process(false)
	resumed.save_path = normal_save; resumed.backup_path = original_backup; resumed.previous_path = original_previous
	check(resumed.load_game() and int(resumed.state.credit) == int(preview_before.credit_after), "save resume retains nonzero credit penalty")
	check(not resumed.cancel_current_contract() and int(resumed.state.cash) == int(preview_before.cash_after), "resumed closed job cannot charge a second cancellation")
	resumed.queue_free()
	check(BUSINESS_APPS._history_items(game).filter(func(row): return str(row.item.get("id", "")) == closeout_id).size() == 1, "customer history shows recent cancellation once")
	game._make_offers()
	check(_offer(retry_case).is_empty(), "same-day board regeneration does not reoffer the exact cancelled case")
	# Model a later busy day rolling the cancellation out of its 100-row event
	# window. Archive-backed rules and accounting must remain intact.
	for history_index in 100: game.state.history.append({"kind":"qa_noise","day":int(game.state.day)})
	while game.state.history.size() > 100: game.state.history.pop_front()
	check(not game.state.history.any(func(row): return str(row.get("kind", "")) == "cancellation" and str(row.get("id", "")) == closeout_id), "fixture has rolled cancellation out of recent history")
	check(BUSINESS_APPS._history_items(game).filter(func(row): return str(row.item.get("id", "")) == closeout_id).size() == 1, "archived cancellation stays accessible in customer history after rollover")
	game._make_offers()
	check(_offer(retry_case).is_empty(), "archive keeps the same-day case hidden after history rollover")
	check(not game.state.dispatch_queues.get("aya", []).any(func(row): return str(row.get("contract_id", "")) == closeout_id), "matching queued crew work is removed")
	check(game.state.dispatch_queues.get("ren", []).any(func(row): return str(row.get("contract_id", "")) == unrelated_id), "unrelated crew work remains queued")
	check(game.state.contract_contexts.has(unrelated_id) and game._open_contract_count() == target_count_before-1, "unrelated accepted case survives and capacity is released")
	check(not game.cancel_current_contract() and int(game.state.cash) == int(preview_before.cash_after), "duplicate cancellation cannot charge twice")
	check(not game.choose_contract(closeout_id), "closed identity cannot be accepted through the public contract API")
	var ledger_preview: Dictionary = LEDGER.preview(game)
	check(int(ledger_preview.get("contract_net", 0)) == -int(preview_before.costs), "day ledger reports cancellation loss once after history rollover")
	check(int(ledger_preview.get("cash_flow", {}).get("job_costs", 0)) == int(preview_before.costs), "cash ledger records cancellation costs once after history rollover")
	var old_id := closeout_id
	var old_key := archived_vm_key
	var ren_job: Dictionary = game.dispatch_queue("ren").filter(func(row): return str(row.get("contract_id", "")) == unrelated_id)[0]
	check(game.dispatch_remove("ren", str(ren_job.get("id", ""))), "fixture cleanup removes only unrelated queued task")
	var previous_day := int(game.state.day)
	check(game.end_day() and int(game.state.day) == previous_day+1, "honest overnight transition records losses and returns to work")
	var retry_offer := _offer(retry_case)
	check(not retry_offer.is_empty() and str(retry_offer.id) != old_id, "canceled authored case is offered next day under a fresh ID")
	if not retry_offer.is_empty():
		var new_id := str(retry_offer.id)
		var new_key := new_id + "/site-0"
		check(not game.state.vm_states.has(new_key), "retry starts with a fresh VM key")
		check(game.choose_contract(new_id), "accept the fresh next-day case")
		var before_retry_vm: Dictionary = game._vm().export_state()
		check(str(game._vm_key()) == new_key and before_retry_vm != game.state.contract_closeouts[old_id].vm_states.get(old_key, {}), "new offer does not restore canceled customer data as a repaired VM")
		check(_solve_and_deliver(), "real VM configuration, fresh probes, verify, and successful retry delivery")
		check(new_id in game.state.completed_ids and str(game.state.last_receipt.get("kind", "")).is_empty(), "only the successful retry enters completion history")
	for malformed_field in [{"name":"costs","value":-1},{"name":"cash_cost","value":"700"},{"name":"day","value":0}]:
		var malformed_numeric: Dictionary = game.state.duplicate(true)
		malformed_numeric.contract_closeouts[old_id].record[malformed_field.name] = malformed_field.value
		check(not game._valid_state(malformed_numeric), "save validation rejects malformed closeout field " + str(malformed_field.name))
	# Legacy saves without the optional closeout schema remain loadable; malformed
	# closeout data is rejected while its source bytes remain intact.
	var legacy: Dictionary = game.state.duplicate(true)
	legacy.erase("contract_closeouts"); legacy.erase("credit_loss")
	var legacy_path := "user://" + qa + "-legacy.json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy)); legacy_file.close()
	var legacy_game = GameScript.new(); root.add_child(legacy_game); legacy_game.set_process(false); _set_paths(legacy_game, qa + "-legacy")
	check(legacy_game.load_game() and legacy_game.state.get("contract_closeouts", {}) is Dictionary and legacy_game.state.get("credit_loss", -1) == 0, "legacy save migrates absent closeout fields")
	var malformed: Dictionary = legacy.duplicate(true); malformed.contract_closeouts = {"broken":{"kind":"cancellation"}}
	var malformed_path := "user://" + qa + "-malformed.json"
	var malformed_json := JSON.stringify(malformed)
	var malformed_file := FileAccess.open(malformed_path, FileAccess.WRITE); malformed_file.store_string(malformed_json); malformed_file.close()
	var malformed_game = GameScript.new(); root.add_child(malformed_game); malformed_game.set_process(false); _set_paths(malformed_game, qa + "-malformed")
	check(not malformed_game.load_game() and FileAccess.get_file_as_string(malformed_path) == malformed_json, "malformed archive is rejected without altering original bytes")
	for node in [legacy_game, malformed_game]: node.queue_free()
	_finish()

func _finish() -> void:
	print("CAREER_CLOSEOUT failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)
