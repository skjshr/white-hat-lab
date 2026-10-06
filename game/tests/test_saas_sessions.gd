extends SceneTree
## Only company eligibility is synthetic. Market days, records and work use Game.
const CASE_ID := "advanced-saas-sessions"
const LEGACY_CASE := "advanced-saas-response"
const MAIL = preload("res://scripts/mail_delivery_thread.gd")
var game
var paths: Array[String] = []
var failures: Array[String] = []
var legacy_id := ""
var legacy_world := ""

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("SAAS_SESSIONS timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_SESSIONS: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func set_paths(values: Array) -> void:
	game.save_path = str(values[0]); game.backup_path = str(values[1])
	game.previous_path = str(values[2]); game.settings_path = str(values[3])

func action(operation: String, args: Dictionary = {}) -> Dictionary:
	return game.advanced_action(operation, args)

func observe(operation: String, args: Dictionary, status: int) -> Dictionary:
	var result := action(operation, args)
	var record: Dictionary = result.get("data", {}).get("record", {})
	check(bool(result.get("changed", false)) and not record.is_empty() and int(record.get("status", 0)) == status, operation + " records the actual HTTP " + str(status))
	return record

func failed_save(callback: Callable, label: String) -> void:
	var before := encoded(game.state)
	var missing := "user://qa-saas-sessions-missing-%s/save.json" % OS.get_process_id()
	set_paths([missing, missing + ".bak", missing + ".previous", missing + ".settings"])
	var result: Variant = callback.call()
	var ok := bool(result.get("ok", true)) if result is Dictionary else bool(result)
	check(not ok and encoded(game.state) == before, label)
	set_paths(paths)

func restore_checkpoint(checkpoint: Dictionary) -> void:
	# Replay only this test's actually accepted contract, never a player save.
	game.state = checkpoint.duplicate(true)
	game._assignments = game.state.get("assignments", {}).duplicate(true)
	game._machine = null; game._machine_key = ""
	check(game.save_game(), "accepted QA checkpoint saves")

func accept_from_market(case_id: String) -> bool:
	# Use ordinary next-day demand instead of inserting a pre-completed source
	# or forcing this specialist case into the current market.
	for _day in 18:
		for offer in game.state.offers:
			if str(offer.get("case_id", "")) != case_id or not bool(offer.get("unlocked", false)) or not bool(offer.get("market_available", false)): continue
			var accepted: bool = game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)) and game.choose_contract(str(offer.id))
			check(accepted, "quote and accept ordinary market case " + case_id)
			return accepted
		if not game.end_day(): check(false, "advance an ordinary market day"); return false
	check(false, "eligible case becomes available in the rotating market: " + case_id)
	return false

func session(id: String) -> Dictionary:
	for row in game.advanced_view().get("saas", {}).get("session_case", {}).get("sessions", []):
		if str(row.get("id", "")) == id: return row
	return {}

func exported() -> int:
	return game.state.advanced.get("egress", {}).get("exported_rows", []).size()

func report(ids: Array) -> void:
	var current_audit := observe("collect_audit", {}, 200)
	var records := ids.duplicate()
	records.append(str(current_audit.get("id", "")))
	check(bool(action("submit_report", {"record_ids":records}).get("ok", false)), "report cites issued originals, each inspected connection and the current audit")

func verify_ready(expected_copies: int) -> void:
	var checks: Array = game.verify()
	check(checks.size() == 6 and checks.all(func(row): return bool(row.get("passed", false))) and game.can_deliver() and exported() == expected_copies, "current denial, billing, aggregation and original report all permit delivery")

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-saas-sessions-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths); game._reset_state()
	check(game.choose_strategy("response"), "QA company selects response career")
	game.state.peak_profit = 11000; game.state.credit = 110
	check(game.start_free_career(), "eligible Lv5 company starts through Game")
	if not accept_from_market(LEGACY_CASE): finish(); return
	observe("inspect_app", {"app":"app-72"}, 200)
	observe("collect_audit", {}, 200)
	legacy_id = str(game.state.current_contract_id)
	legacy_world = encoded(game.state.advanced)
	check(not game.state.advanced.has("session_case") and game.save_game() and game.load_game() and encoded(game.state.advanced) == legacy_world, "existing SaaS world reloads without retrofitting the new session model")
	if not accept_from_market(CASE_ID): finish(); return
	check(str(game.state.contract.case_id) == CASE_ID and str(game.state.advanced.kind) == LEGACY_CASE and str(game.state.advanced.model_version) == "saas-sessions-v1", "new case identity uses its own version of the existing SaaS engine")
	var before := encoded(game.state)
	for _i in 3: game.advanced_view(); game.saas_watch_status(); game.company_cycle_view()
	var projected: Dictionary = game.advanced_view()
	var visible: Array = projected.get("saas", {}).get("session_case", {}).get("sessions", [])
	check(visible.size() == 3 and visible.all(func(row): return not row.has("expected_destination") and not row.has("approved") and row.get("latest_inspection", {}).is_empty()), "uninspected session projection does not reveal its private destination or a verdict")
	if not visible.is_empty(): visible[0]["active"] = false
	check(encoded(game.state) == before, "viewing or changing a detached projection cannot change sessions, time or evidence")
	check(not bool(action("revoke_connection", {"session_id":"SES-missing"}).get("ok", true)) and encoded(game.state) == before, "unknown session is rejected without consuming work or evidence")
	var ids: Array = ["audit-1", "audit-2", "audit-3", "audit-4"]
	for id in ["SES-201", "SES-202", "SES-203"]:
		var inspected := observe("inspect_connection", {"session_id":id}, 200)
		ids.append(str(inspected.get("id", "")))
	var audit := observe("collect_audit", {}, 200)
	ids.append(str(audit.get("id", "")))
	check(int(game.state.work.minutes) == 5 and exported() == 0, "comparing the three issued connections takes five real minutes")
	var investigated: Dictionary = game.state.duplicate(true)
	var early := prevent_and_recover(ids)
	restore_checkpoint(investigated)
	delayed_response(ids, early)
	check(encoded(game.state.contract_contexts.get(legacy_id, {}).get("advanced", {})) == legacy_world, "new session work, reloads and settlement preserve the older accepted SaaS world")
	finish()

func prevent_and_recover(ids: Array) -> Dictionary:
	observe("revoke_connection", {"session_id":"SES-203"}, 200)
	var contained := encoded(game.state)
	check(bool(action("revoke_connection", {"session_id":"SES-203"}).get("ok", false)) and encoded(game.state) == contained, "duplicate selective revocation is a free no-op")
	observe("probe_session", {"session_id":"SES-203"}, 403)
	observe("submit_invoice", {"invoice_id":"BILL-003"}, 200)
	var receipt_id := str(game.state.advanced.invoice.receipt_id)
	observe("probe_session", {"session_id":"SES-202"}, 200)
	check(bool(session("SES-201").get("active", false)) and bool(session("SES-202").get("active", false)) and bool(game.state.advanced.session_case.consent.enabled), "selective containment preserves approved consent and both normal connections")
	# A mistaken revocation must remain real, including after interruption.
	observe("revoke_connection", {"session_id":"SES-201"}, 200)
	observe("submit_invoice", {"invoice_id":"BILL-003"}, 403)
	var interrupted := encoded(game.state.advanced)
	var work := encoded(game.state.work)
	check(not game.can_deliver() and game.save_game() and game.load_game() and encoded(game.state.advanced) == interrupted and encoded(game.state.work) == work, "the incorrectly revoked billing connection and failed same-invoice attempt survive restart")
	failed_save(func(): return action("reissue_connection", {"purpose":"billing"}), "failed reissue save restores revoked IDs, sequence, clock and invoice")
	observe("reissue_connection", {"purpose":"billing"}, 200)
	var replacement := ""
	for row in game.advanced_view().get("saas", {}).get("session_case", {}).get("sessions", []):
		if str(row.get("purpose", "")) == "billing" and bool(row.get("active", false)): replacement = str(row.get("id", ""))
	check(not replacement.is_empty() and replacement != "SES-201" and not bool(session("SES-201").get("active", true)), "recovery creates a new billing connection while retaining the revoked original")
	observe("probe_session", {"session_id":"SES-201"}, 403)
	var denied := false
	for row in game.advanced_view().get("checks", []):
		if str(row.get("id", "")) == "denial": denied = bool(row.get("passed", false))
	check(not denied, "a fresh 403 for the old billing connection cannot replace proof about the external connection")
	observe("probe_session", {"session_id":"SES-203"}, 403)
	failed_save(func(): return action("submit_invoice", {"invoice_id":"BILL-003"}), "failed invoice retry save restores the actual prior rejection and work")
	var recovered_bill := observe("submit_invoice", {"invoice_id":"BILL-003"}, 200)
	check(str(game.state.advanced.invoice.receipt_id) == receipt_id and str(recovered_bill.get("data", {}).get("used_session_id", "")) == replacement, "the same invoice keeps its receipt and records the real replacement connection")
	var retried := encoded(game.state)
	check(bool(action("submit_invoice", {"invoice_id":"BILL-003"}).get("ok", false)) and encoded(game.state) == retried, "repeated invoice submission cannot duplicate receipt, customer payment or work")
	observe("probe_session", {"session_id":"SES-202"}, 200)
	report(ids); verify_ready(0)
	check(int(game.state.work.incident_cost) == 0 and int(game.work_status().costs) == 700, "timely selective response prevents copied rows and needs only the existing base expense")
	failed_save(func(): return game.deliver(), "failed delivery save rolls back company settlement, result history and invoice draft")
	check(game.deliver(), "recovered zero-loss response delivers through Game")
	var early: Dictionary = game.state.last_receipt.duplicate(true)
	check(int(early.get("saas_satisfaction_delta", -1)) == 0 and str(early.get("saas_outcome", {}).get("invoice", {}).get("receipt_id", "")) == receipt_id, "zero-loss delivery retains its customer receipt without a leakage satisfaction penalty")
	return early

func delayed_response(ids: Array, early: Dictionary) -> void:
	check(bool(action("organize_records", {"mode":"manual", "record_ids":ids}).get("ok", false)), "manual comparison uses the same actual records before containment")
	failed_save(func(): return action("collect_audit"), "failed save at the scheduled export rolls back row copies, compensation, audit and time together")
	observe("collect_audit", {}, 200)
	check(exported() == 3 and int(game.state.work.incident_cost) == 1500, "delaying containment until minute twelve leaves three real copies and one compensation expense")
	observe("revoke_connection", {"session_id":"SES-203"}, 200)
	observe("probe_session", {"session_id":"SES-203"}, 403)
	observe("submit_invoice", {"invoice_id":"BILL-003"}, 200)
	observe("probe_session", {"session_id":"SES-202"}, 200)
	var stale := encoded(game.state)
	check(not bool(action("submit_report", {"record_ids":ids}).get("ok", true)) and encoded(game.state) == stale, "the pre-export audit cannot report a later real loss")
	report(ids); verify_ready(3)
	var ready: Dictionary = game.state.duplicate(true)
	var expected: Dictionary = game._saas_outcome().duplicate(true)
	var costs := int(game.work_status().costs)
	check(costs == 2200, "base expense and the three retained copies reconcile to one settlement cost")
	failed_save(func(): return game.cancel_current_contract(), "failed cancellation restores the accepted incident, company cash and evidence")
	check(game.cancel_current_contract() and int(game.state.cash) == int(ready.cash) - costs and str(game.state.history[-1].get("kind", "")) == "cancellation" and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "cancelling pays incurred costs and archives the same session outcome")
	var cancelled := encoded(game.state)
	check(not game.cancel_current_contract() and encoded(game.state) == cancelled and game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "cancelled costs and evidence survive restart without a second charge")
	restore_checkpoint(ready)
	check(game.deliver(), "contained delayed response still delivers with its recorded damage")
	var receipt: Dictionary = game.state.last_receipt.duplicate(true)
	var history: Dictionary = game.state.history[-1].duplicate(true)
	check(encoded(receipt.get("saas_outcome", {})) == encoded(expected) and encoded(history.get("saas_outcome", {})) == encoded(expected) and int(receipt.cost) == costs and int(receipt.get("saas_satisfaction_delta", 0)) == -3 and int(receipt.net) < int(early.get("net", 0)), "identical final containment retains three-copy damage, lower profit and a customer-trust consequence")
	check(int(game.state.cash) == int(ready.cash) + int(history.cash_delta) and str(receipt.get("invoice_id", "")) != str(expected.get("invoice", {}).get("receipt_id", "")), "customer invoice receipt stays separate from the security company's bill and cash")
	var delivered := encoded(game.state)
	check(not game.deliver() and encoded(game.state) == delivered, "duplicate delivery cannot settle the same contract twice")
	var mail: Dictionary = MAIL.project(game.state, history)
	check(bool(mail.get("confirmed", false)) and str(mail.get("body", "")).contains("BILL-003") and str(mail.get("body", "")).contains("3行"), "customer reply reflects the actual bill and the retained three-row loss")
	check(game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected) and encoded(game.state.history[-1].get("saas_outcome", {})) == encoded(expected), "settled session evidence and company outcome survive restart")

func finish() -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_SESSIONS_TEST_PASS" if failures.is_empty() else "SAAS_SESSIONS_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
