extends SceneTree
## Only the QA company's eligibility is synthetic. Contracts and work use Game.
const CASE_ID := "advanced-saas-response"
const GUIDE = preload("res://scripts/next_task_guide.gd")
const MAIL = preload("res://scripts/mail_delivery_thread.gd")
var game
var paths: Array[String] = []
var failures: Array[String] = []

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("SAAS_RESPONSE timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error("SAAS_RESPONSE: " + message)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func set_paths(values: Array) -> void:
	game.save_path = str(values[0]); game.backup_path = str(values[1])
	game.previous_path = str(values[2]); game.settings_path = str(values[3])

func action(operation: String, args: Dictionary = {}) -> Dictionary:
	return game.advanced_action(operation, args)

func observe(operation: String, args: Dictionary, expected: int) -> Dictionary:
	var result := action(operation, args)
	var row: Dictionary = result.get("data", {}).get("record", {})
	check(bool(result.get("changed", false)) and not row.is_empty() and int(row.get("status", 0)) == expected, operation + " records the actual HTTP " + str(expected))
	return row

func change(app: String, control: String, enabled: bool) -> void:
	check(bool(action("change_access", {"app":app,"control":control,"enabled":enabled}).get("ok", false)), "apply " + app + " " + control + "=" + str(enabled))

func restore_checkpoint(checkpoint: Dictionary) -> void:
	# Branch only this test's actually accepted QA contract, never player files.
	game.state = checkpoint.duplicate(true)
	game._assignments = game.state.get("assignments", {}).duplicate(true)
	game._machine = null; game._machine_key = ""
	check(game.save_game(), "QA branch checkpoint saves")

func inspect_originals() -> Array:
	observe("inspect_app", {"app":"app-19"}, 200)
	observe("inspect_app", {"app":"app-72"}, 200)
	var collected := observe("collect_audit", {}, 200)
	return ["audit-1", "audit-2", str(collected.get("id", ""))]

func costs() -> Dictionary:
	return game.state.work.get("saas_costs", {})

func exported_rows() -> int:
	return game.state.advanced.get("egress", {}).get("exported_rows", []).size()

func report_passed() -> bool:
	for row in game.advanced_view().get("checks", []):
		if str(row.get("id", "")) == "report": return bool(row.get("passed", false))
	return false

func with_failed_save(callback: Callable, label: String) -> void:
	var before := encoded(game.state)
	var missing := "user://qa-saas-response-missing-" + str(OS.get_process_id()) + "/missing/save.json"
	set_paths([missing, missing + ".bak", missing + ".previous", missing + ".settings"])
	var result: Variant = callback.call()
	var ok := bool(result.get("ok", true)) if result is Dictionary else bool(result)
	check(not ok and encoded(game.state) == before, label)
	set_paths(paths)

func start_company(legacy: bool = false) -> void:
	game._reset_state()
	check(game.choose_strategy("response") and game.start_free_career(), "isolated response company starts through Game")
	# A Lv3 company with the real initial cash, not a high-level limitless wallet.
	game.state.peak_profit = 3000; game.state.credit = 30
	if legacy:
		game.state.peak_profit = 27000; game.state.credit = 270
		game.state.skills.response = 5; game.state.skills.operations = 2

func accept_case(case_id: String) -> bool:
	game.state.market_leads = [case_id]; game.state.market_day = int(game.state.day); game._make_offers()
	var offer: Dictionary = {}
	for item in game.state.offers:
		if str(item.get("case_id", "")) == case_id: offer = item; break
	check(not offer.is_empty() and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)), "eligible case is offered through the ordinary market: " + case_id)
	if offer.is_empty(): return false
	var accepted: bool = game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)) and game.choose_contract(str(offer.id))
	check(accepted, "accept quoted contract through Game: " + case_id)
	return accepted

func purchase_and_legacy_boundary() -> void:
	start_company(true)
	if not accept_case("advanced-cloud"): return
	game.state.erase("company_tools")
	var before := encoded(game.state)
	game.record_assistant_status(); game.record_assistant_status()
	check(encoded(game.state) == before and not bool(game.record_assistant_status().owned), "reading an old company does not create a license or mutate its contract")
	var scope := encoded(game.state.contract)
	var world := encoded(game.state.advanced)
	var targets := encoded(game.state.targets)
	check(game.save_game() and game.load_game() and encoded(game.state.contract) == scope and encoded(game.state.advanced) == world and encoded(game.state.targets) == targets and not bool(game.record_assistant_status().owned), "old accepted cloud contract roundtrips with the same world and conditions")
	start_company()
	var qualified: Dictionary = game.state.duplicate(true)
	game.state.peak_profit = 1000; game.state.credit = 10
	var unqualified := encoded(game.state)
	check(not game.buy_record_assistant() and encoded(game.state) == unqualified, "cash alone cannot bypass the company-level unlock")
	game.state = qualified.duplicate(true)
	game.state.skills.response = 0
	unqualified = encoded(game.state)
	check(not game.buy_record_assistant() and encoded(game.state) == unqualified, "company level alone cannot bypass the response-skill unlock")
	game.state = qualified
	var eligible: Dictionary = game.record_assistant_status()
	check(int(game.company_level().level) == 3 and int(game.state.skills.response) == 1 and bool(eligible.can_purchase), "Lv3 response1 makes the optional tool reachable with normal initial funds")
	with_failed_save(func(): return game.buy_record_assistant(), "failed license save restores the whole company including funds and investment history")
	var cash := int(game.state.cash)
	check(game.buy_record_assistant() and int(game.state.cash) == cash - 3000 and bool(game.record_assistant_status().owned), "purchase charges the company investment once")
	var purchased := encoded(game.state)
	check(game.buy_record_assistant() and encoded(game.state) == purchased, "repeated purchase is a free no-op")
	check(game.save_game() and game.load_game() and bool(game.record_assistant_status().owned) and int(game.state.cash) == cash - 3000, "owned license and purchase price survive restart")

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-saas-response-" + str(OS.get_process_id())
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths)
	purchase_and_legacy_boundary()
	if accept_case(CASE_ID): exercise_case()
	finish()

func exercise_case() -> void:
	var before := encoded(game.state)
	for _i in 3: game.advanced_view(); game.record_assistant_status(); GUIDE.resolve(game)
	check(encoded(game.state) == before, "views, eligibility and guide never generate attacks, evidence, time or expenses")
	var pristine: Dictionary = game.state.duplicate(true)
	var original_audit := encoded(game.state.advanced.audit)
	prevention_branch()
	restore_checkpoint(pristine)
	var ids := inspect_originals()
	var comparison: Dictionary = game.state.duplicate(true)
	var minutes := int(game.state.work.minutes)
	check(bool(action("organize_records", {"mode":"manual","record_ids":ids}).get("ok", false)), "manual organization accepts original record IDs")
	var manual: Dictionary = game.state.advanced.organization.duplicate(true)
	check(int(game.state.work.minutes) == minutes + 5 and int(costs().get("usage_cost", 0)) == 0, "manual organization takes five minutes without a usage charge")
	# This manual branch reaches its first report at minute 11. Only the real
	# export in the following audit acquisition should invalidate that report.
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)) and report_passed(), "a report based on the observed pre-leak state is initially valid")
	var first_report := encoded(game.state.advanced.report.original)
	var post_leak_audit := observe("collect_audit", {}, 200)
	check(exported_rows() == 3 and not report_passed(), "a newly successful export makes the earlier impact report stale")
	check(bool(action("submit_report", {"record_ids":["audit-1", "audit-2", str(post_leak_audit.get("id", ""))]}).get("ok", false)) and report_passed() and encoded(game.state.advanced.report.original) == first_report, "fresh audit supports an impact supplement while preserving the first report")
	restore_checkpoint(comparison)
	var cash := int(game.state.cash)
	check(bool(action("organize_records", {"mode":"assistant","record_ids":ids}).get("ok", false)), "owned assistant organizes the same originals")
	var organized: Dictionary = game.state.advanced.organization
	check(int(game.state.work.minutes) == minutes + 2 and int(costs().get("usage_cost", 0)) == 300 and int(costs().get("assistant_runs", 0)) == 1 and int(game.state.cash) == cash and str(organized.input_hash) == str(manual.input_hash) and encoded(organized.record_ids) == encoded(manual.record_ids), "assistant saves three minutes for one deferred expense and does not invent different evidence")
	var repeated := encoded(game.state)
	check(bool(action("organize_records", {"mode":"assistant","record_ids":ids}).get("ok", false)) and encoded(game.state) == repeated, "reopening the same input costs no time, money or new observations")
	observe("password_reset", {}, 200)
	change("app-72", "consent", false)
	observe("probe_session", {"app":"app-72"}, 200)
	check(exported_rows() == 0 and bool(game.state.advanced.apps["app-72"].session.active), "password reset and consent withdrawal leave the already issued connection active")
	change("app-72", "consent", true)
	check(exported_rows() == 3 and int(costs().get("impact_cost", 0)) == 1500, "first scheduled synchronization retains three exported rows and charges each once")
	change("app-72", "session", false)
	observe("collect_audit", {}, 200)
	observe("probe_session", {"app":"app-72"}, 200)
	check(exported_rows() == 6 and int(costs().get("impact_cost", 0)) == 3000 and bool(game.state.advanced.apps["app-72"].session.active), "session revocation alone permits reissuance at the next still-consented synchronization")
	change("app-19", "session", false)
	observe("submit_invoice", {"invoice_id":"BILL-001"}, 403)
	check(str(game.state.advanced.invoice.receipt_id).is_empty() and not game.can_deliver(), "stopping the normal integration leaves the same invoice unreceived")
	var interrupted_world := encoded(game.state.advanced)
	var interrupted_work := encoded(game.state.work)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == interrupted_world and encoded(game.state.work) == interrupted_work and int(game.state.advanced.invoice.attempts[-1].status) == 403, "denied invoice, leaked rows and expenses survive saved-career interruption")
	# At minute 22, two minutes would cross the final scheduled sync. A failed
	# save must undo both that real batch and the assistant's usage fee.
	with_failed_save(func(): return action("organize_records", {"mode":"assistant","record_ids":["audit-1", "audit-2"]}), "failed save rolls back crossed synchronization, row copies, usage fee, clock and organization together")
	change("app-19", "session", true)
	check(exported_rows() == 9 and int(costs().get("impact_cost", 0)) == 4500 and int(costs().get("usage_cost", 0)) == 300, "retry crosses the remaining synchronization exactly once without retaining the failed assistant charge")
	change("app-72", "consent", false)
	change("app-72", "session", false)
	observe("probe_session", {"app":"app-72"}, 403)
	with_failed_save(func(): return action("submit_invoice", {"invoice_id":"BILL-001"}), "failed invoice save restores the unreceived bill and creates no phantom receipt")
	observe("submit_invoice", {"invoice_id":"BILL-001"}, 200)
	var receipt_id := str(game.state.advanced.invoice.receipt_id)
	repeated = encoded(game.state)
	var duplicate := action("submit_invoice", {"invoice_id":"BILL-001"})
	check(bool(duplicate.get("ok", false)) and not receipt_id.is_empty() and str(duplicate.get("data", {}).get("receipt_id", "")) == receipt_id and encoded(game.state) == repeated, "retry of the received invoice preserves its exact receipt without duplicate billing or time")
	var stale_report := encoded(game.state)
	check(not bool(action("submit_report", {"record_ids":ids}).get("ok", true)) and encoded(game.state) == stale_report, "an audit captured before the real leakage cannot stand in for the incident impact report")
	var current_audit := observe("collect_audit", {}, 200)
	ids.append(str(current_audit.get("id", "")))
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)), "report references the retained approval originals and the audit containing all actual exports")
	repeated_audit_reports()
	var checks: Array = game.verify()
	check(checks.size() == 5 and checks.all(func(row): return bool(row.get("passed", false))) and game.can_deliver() and encoded(game.state.advanced.audit) == original_audit, "fresh denial and the restored original invoice satisfy acceptance without erasing the original evidence or leakage")
	check(int(game.state.work.incident_cost) == 4800 and int(game.work_status().costs) == 5500, "one assistant use and nine exported rows reconcile to the deferred cost plus the existing base expense")
	var ready: Dictionary = game.state.duplicate(true)
	cancellation_branch()
	restore_checkpoint(ready)
	var expected_outcome: Dictionary = game._saas_outcome().duplicate(true)
	with_failed_save(func(): return game.deliver(), "failed delivery save restores settlement, customer satisfaction, invoice draft and saved incident outcome")
	check(game.deliver(), "the recovered SaaS case is deliverable through the ordinary contract API")
	var outcome: Dictionary = game.state.last_receipt.get("saas_outcome", {}).duplicate(true)
	var history: Dictionary = game.state.history[-1].duplicate(true)
	check(encoded(outcome) == encoded(expected_outcome) and encoded(history.get("saas_outcome", {})) == encoded(outcome) and int(game.state.last_receipt.cost) == 5500 and int(game.state.last_receipt.get("saas_satisfaction_delta", 0)) == -9 and int(history.get("saas_satisfaction_delta", 0)) == -9, "delivery archives the real incident outcome, costs and continuing customer-trust loss")
	check(int(game.state.cash) == int(ready.cash) + int(history.cash_delta) and int(history.expense) == 5500 and str(game.state.last_receipt.get("invoice_id", "")) != receipt_id, "customer SaaS invoice receipt stays separate from this company's fee invoice and cash settlement")
	var settled := encoded(game.state)
	check(not game.deliver() and encoded(game.state) == settled, "repeated delivery cannot charge expenses or award the fee twice")
	var mail: Dictionary = MAIL.project(game.state, history)
	check(bool(mail.get("confirmed", false)) and str(mail.get("body", "")).contains("BILL-001") and str(mail.get("body", "")).contains(receipt_id) and str(mail.get("body", "")).contains("9行"), "customer reply identifies the original invoice receipt and the irreversible nine-row loss")
	check(game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(outcome) and encoded(game.state.history[-1].get("saas_outcome", {})) == encoded(outcome) and bool(game.record_assistant_status().owned), "saved delivery retains immutable incident results and the company-owned assistant")
	# A projection must not expose writable references to paid historical data.
	var projected: Dictionary = game.advanced_view()
	var view_invoice: Dictionary = projected.get("saas", {}).get("invoice", {})
	view_invoice["receipt_id"] = "QA projection edit"
	check(encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(outcome) and encoded(game.state.history[-1].get("saas_outcome", {})) == encoded(outcome), "changing a detached view cannot rewrite a delivered customer receipt")

func repeated_audit_reports() -> void:
	var original := encoded(game.state.advanced.report.original)
	var retained := {}
	for row in game.state.advanced.records: retained[str(row.id)] = encoded(row)
	var initial_size := encoded(game.state.advanced).length()
	var first_growth := 0
	var flat := true
	for index in 3:
		var audit := observe("collect_audit", {}, 200)
		check(bool(action("submit_report", {"record_ids":["audit-1", "audit-2", str(audit.get("id", ""))]}).get("ok", false)), "recollected audit supports a preserved supplementary report")
		var events: Array = audit.get("data", {}).get("events", []).duplicate()
		for source in game.state.advanced.report.latest.get("records", []):
			flat = flat and not source.get("data", {}).has("records")
			events.append_array(source.get("data", {}).get("events", []))
		for event in events:
			flat = flat and not event.get("data", {}).has("records") and not event.get("data", {}).has("events")
		if index == 0: first_growth = encoded(game.state.advanced).length() - initial_size
	var final_growth := encoded(game.state.advanced).length() - initial_size
	var originals_unchanged := encoded(game.state.advanced.report.original) == original
	for row in game.state.advanced.records:
		if retained.has(str(row.id)): originals_unchanged = originals_unchanged and retained[str(row.id)] == encoded(row)
	check(flat and first_growth > 0 and final_growth <= first_growth * 5 and originals_unchanged, "three audit/report refreshes keep flat snapshots, bounded growth and every earlier original unchanged")

func prevention_branch() -> void:
	# The same accepted case is solvable without buying the optional assistant.
	game.state.erase("company_tools")
	observe("submit_invoice", {"invoice_id":"BILL-001"}, 200)
	var early_receipt := str(game.state.advanced.invoice.receipt_id)
	var early_minute := int(game.state.advanced.invoice.submitted_minute)
	var ids := inspect_originals()
	var before := encoded(game.state)
	check(not bool(action("organize_records", {"mode":"assistant","record_ids":ids}).get("ok", true)) and encoded(game.state) == before, "unowned assistant cannot be invoked through the public action API")
	change("app-72", "consent", false)
	change("app-72", "session", false)
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)) and report_passed(), "the first blocked sync does not invalidate a report with no new damage")
	var contained_report := encoded(game.state.advanced.report)
	check(bool(action("organize_records", {"mode":"manual","record_ids":ids}).get("ok", false)), "manual record organization remains available")
	observe("probe_session", {"app":"app-72"}, 403)
	observe("submit_invoice", {"invoice_id":"BILL-001"}, 200)
	check(str(game.state.advanced.invoice.receipt_id) == early_receipt and int(game.state.advanced.invoice.submitted_minute) == early_minute and int(game.state.advanced.invoice.verified_revision) == int(game.state.advanced.world_revision), "a bill received before access changes can be reconfirmed without replacing its receipt or original submission")
	var checks: Array = game.verify() # Advances the final blocked sync.
	check(checks.size() == 5 and checks.all(func(row): return bool(row.get("passed", false))) and game.can_deliver() and exported_rows() == 0 and int(costs().get("usage_cost", 0)) == 0 and int(costs().get("impact_cost", 0)) == 0 and game.state.advanced.egress.schedule.all(func(event): return str(event.status) == "blocked") and encoded(game.state.advanced.report) == contained_report, "timely containment blocks all three syncs and allows delivery without AI, another audit or a forced report supplement")

func cancellation_branch() -> void:
	var outcome: Dictionary = game._saas_outcome().duplicate(true)
	var cash := int(game.state.cash)
	with_failed_save(func(): return game.cancel_current_contract(), "failed cancellation save restores the active incident and company money")
	check(game.cancel_current_contract(), "an interrupted SaaS response can be cancelled through Game")
	check(int(game.state.cash) == cash - 5500 and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(outcome) and str(game.state.history[-1].kind) == "cancellation" and encoded(game.state.history[-1].get("saas_outcome", {})) == encoded(outcome), "cancellation settles incurred costs and archives the same leaked rows and invoice outcome")
	var cancelled := encoded(game.state)
	check(not game.cancel_current_contract() and encoded(game.state) == cancelled, "repeating cancellation cannot charge the same expenses again")
	check(game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(outcome), "cancelled incident outcome survives restart")

func finish() -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_RESPONSE_TEST_PASS" if failures.is_empty() else "SAAS_RESPONSE_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
