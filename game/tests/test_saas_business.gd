extends "res://tests/test_saas_sessions.gd"
## Replays one accepted QA job with different recovery priorities. The v1
## compatibility branch reconstructs only the former schema, not a success.

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_BUSINESS: " + label)

func job(id: String) -> Dictionary:
	for row in game.state.advanced.get("session_case", {}).get("business", {}).get("jobs", []):
		if str(row.get("id", "")) == id: return row
	return {}

func business_cost() -> int:
	return int(game.state.work.get("saas_costs", {}).get("business_cost", 0))

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-saas-business-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths); game._reset_state()
	check(game.choose_strategy("response"), "QA company selects response career")
	game.state.peak_profit = 11000; game.state.credit = 110
	check(game.start_free_career() and accept_from_market(CASE_ID), "Lv5 company quotes and accepts the ordinary sessions offer")
	if str(game.state.get("contract", {}).get("case_id", "")) != CASE_ID: finish(); return
	check(str(game.state.advanced.model_version) == "saas-sessions-v2" and not job("BILL-RUN-01").is_empty() and not job("DISPATCH-01").is_empty(), "new accepted work contains the two actual scheduled business jobs")
	var ids: Array = ["audit-1", "audit-2", "audit-3", "audit-4"]
	for id in ["SES-201", "SES-202", "SES-203"]:
		var record := observe("inspect_connection", {"session_id":id}, 200)
		ids.append(str(record.get("id", "")))
	var audit := observe("collect_audit", {}, 200)
	ids.append(str(audit.get("id", "")))
	observe("revoke_all_connections", {}, 200)
	check(int(game.state.work.minutes) == 7 and exported() == 0, "real investigation and all-session revocation finish just before the scheduled work")
	var stopped: Dictionary = game.state.duplicate(true)
	legacy_schema(stopped, ids)
	restore_checkpoint(stopped)
	var early := recover_in_order(ids, true)
	restore_checkpoint(stopped)
	var late := recover_in_order(ids, false)
	check(int(early.get("cost", 0)) == 700 and int(late.get("cost", 0)) == 2300 and int(early.get("net", 0)) > int(late.get("net", 0)) and int(early.get("satisfaction_after", 0)) - int(late.get("satisfaction_after", 0)) == 3, "changing only recovery order leaves the same services usable but changes settlement and customer trust")
	finish()

func legacy_schema(stopped: Dictionary, ids: Array) -> void:
	# Portable compatibility fixture: downgrade only the new optional schema
	# on this uncompleted, actually accepted QA contract. Native v1 fixtures
	# are played separately; no successful job or evidence is manufactured here.
	game.state.advanced.model_version = "saas-sessions-v1"
	game.state.advanced.session_case.version = 1
	game.state.advanced.session_case.erase("business")
	var legacy := encoded(game.state.advanced)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == legacy and game.advanced_view().get("checks", []).size() == 6, "v1 JSON reload preserves the accepted world and its six original checks")
	check(bool(action("organize_records", {"mode":"manual", "record_ids":ids}).get("ok", false)), "legacy work advances through its existing record organization")
	observe("collect_audit", {}, 200)
	check(int(game.state.work.minutes) > 12 and not game.state.advanced.session_case.has("business") and business_cost() == 0 and int(game.state.work.incident_cost) == 0 and game.advanced_view().get("checks", []).size() == 6, "crossing new deadlines never invents business work, compensation or acceptance conditions in a v1 contract")
	check(encoded(stopped.get("advanced", {}).get("session_case", {}).get("business", {})) != "{}", "the compatibility fixture did not mutate the saved v2 branch")

func recover_in_order(ids: Array, aggregation_first: bool) -> Dictionary:
	var first := "aggregation" if aggregation_first else "billing"
	var second := "billing" if aggregation_first else "aggregation"
	observe("reissue_connection", {"purpose":first}, 200)
	check(int(game.state.work.minutes) == 9 and str(job("BILL-RUN-01").get("status", "")) == "queued" and str(job("DISPATCH-01").get("status", "")) == "queued", "reissuing a connection does not retroactively complete already queued work")
	var paused := encoded(game.state.advanced)
	var work := encoded(game.state.work)
	for _i in 3: game.advanced_view(); game.company_cycle_view()
	check(encoded(game.state.advanced) == paused and encoded(game.state.work) == work and game.save_game() and game.load_game() and encoded(game.state.advanced) == paused, "queued work and exact issue time survive read-only views and a JSON restart")
	if not aggregation_first:
		failed_save(func(): return action("reissue_connection", {"purpose":second}), "failed recovery save rolls back a crossed completion, deadline compensation, new ID and clock")
	observe("reissue_connection", {"purpose":second}, 200)
	var expected_loss := 0 if aggregation_first else 1600
	check(int(game.state.work.minutes) == 11 and business_cost() == expected_loss and int(game.state.work.incident_cost) == expected_loss and int(game.state.work.get("saas_costs", {}).get("impact_cost", 0)) == 0, "deadline loss is billed once as business interruption, separate from leaked rows")
	var at_deadline := encoded(game.state.advanced)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == at_deadline and business_cost() == expected_loss, "recorded deadline outcome survives restart without a second compensation")
	observe("probe_session", {"session_id":"SES-203"}, 403)
	var billing: Dictionary = job("BILL-RUN-01").duplicate(true)
	var dispatch: Dictionary = job("DISPATCH-01").duplicate(true)
	check(str(billing.get("status", "")) == "completed" and str(dispatch.get("status", "")) == "completed" and int(billing.get("completed_minute", -1)) == (12 if aggregation_first else 10) and int(dispatch.get("completed_minute", -1)) == (10 if aggregation_first else 12) and int(dispatch.get("loss_amount", -1)) == expected_loss and int(billing.get("loss_amount", -1)) == 0, "the next work minute completes each real job with its actual priority-dependent finish time")
	check(str(billing.get("used_session_id", "")) == ("SES-205" if aggregation_first else "SES-204") and str(dispatch.get("used_session_id", "")) == ("SES-204" if aggregation_first else "SES-205") and not str(billing.get("record_id", "")).is_empty() and not str(dispatch.get("record_id", "")).is_empty(), "each business completion retains the exact reissued connection and original record")
	observe("submit_invoice", {"invoice_id":"BILL-003"}, 200)
	observe("probe_session", {"session_id":str(dispatch.get("used_session_id", ""))}, 200)
	report(ids); verify_ready(0)
	check(business_cost() == expected_loss and int(game.state.work.incident_cost) == expected_loss and exported() == 0 and encoded(job("BILL-RUN-01")) == encoded(billing) and encoded(job("DISPATCH-01")) == encoded(dispatch), "later inspection and blocked synchronizations neither rerun completed jobs nor charge their delay twice")
	var ready: Dictionary = game.state.duplicate(true)
	var expected: Dictionary = game._saas_outcome().duplicate(true)
	if not aggregation_first:
		failed_save(func(): return game.cancel_current_contract(), "failed cancellation preserves the active job outcomes and unpaid compensation")
		check(game.cancel_current_contract() and int(game.state.cash) == int(ready.cash) - 2300 and str(game.state.history[-1].get("kind", "")) == "cancellation" and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected) and encoded(game.state.history[-1].get("saas_outcome", {})) == encoded(expected) and int(game.state.last_receipt.get("satisfaction_before", 0)) - int(game.state.last_receipt.get("satisfaction_after", 0)) == 12, "cancellation settles business compensation and preserves its normal twelve-point consequence without a second satisfaction penalty")
		check(game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "cancelled business loss remains saved")
		restore_checkpoint(ready)
		failed_save(func(): return game.deliver(), "failed delivery restores compensation, company cash, satisfaction and historical outcome")
	check(game.deliver(), "completed business work and explicit BILL-003 are delivered together")
	var receipt: Dictionary = game.state.last_receipt.duplicate(true)
	var history: Dictionary = game.state.history[-1].duplicate(true)
	check(encoded(receipt.get("saas_outcome", {})) == encoded(expected) and encoded(history.get("saas_outcome", {})) == encoded(expected) and int(receipt.get("saas_satisfaction_delta", -1)) == 0 and int(receipt.get("saas_business_satisfaction_delta", 0)) == (0 if aggregation_first else -3) and int(history.get("saas_business_satisfaction_delta", 0)) == (0 if aggregation_first else -3), "receipt and history retain separate business compensation and customer-trust consequences without inventing leakage")
	check(str(receipt.get("grade", "")) == ("S" if aggregation_first else "A") and (int(receipt.get("baseline_bonus", 0)) > 0 if aggregation_first else int(receipt.get("baseline_bonus", -1)) == 0), "late business work prevents the loss-free grade and prevention bonus even after restoration")
	var delivered := encoded(game.state)
	check(not game.deliver() and encoded(game.state) == delivered and game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "settled job records survive restart and cannot be paid twice")
	return receipt

func finish() -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_BUSINESS_TEST_PASS" if failures.is_empty() else "SAAS_BUSINESS_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
