extends SceneTree
## Eligibility alone is synthetic. Deliveries, investment and days use Game.
const SOURCE_CASE := "advanced-saas-response"
const WATCH_CASE := "advanced-saas-watch"
const CARE = preload("res://scripts/care_contract_support.gd")
const MAIL = preload("res://scripts/mail_delivery_thread.gd")
var game
var paths: Array[String] = []
var failures: Array[String] = []

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("SAAS_WATCH timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_WATCH: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func set_paths(values: Array) -> void:
	game.save_path = str(values[0]); game.backup_path = str(values[1])
	game.previous_path = str(values[2]); game.settings_path = str(values[3])

func action(operation: String, args: Dictionary = {}) -> Dictionary:
	return game.advanced_action(operation, args)

func observe(operation: String, args: Dictionary, status: int) -> Dictionary:
	var result := action(operation, args)
	var row: Dictionary = result.get("data", {}).get("record", {})
	check(bool(result.get("changed", false)) and not row.is_empty() and int(row.get("status", 0)) == status, operation + " records the actual HTTP " + str(status))
	return row

func change(app: String, control: String, enabled: bool) -> void:
	check(bool(action("change_access", {"app":app,"control":control,"enabled":enabled}).get("ok", false)), "apply " + app + " " + control + "=" + str(enabled))

func failed_save(callback: Callable, label: String) -> void:
	var before := encoded(game.state)
	var missing := "user://qa-saas-watch-missing-" + str(OS.get_process_id()) + "/save.json"
	set_paths([missing, missing + ".bak", missing + ".previous", missing + ".settings"])
	var result: Variant = callback.call()
	check(not bool(result.get("ok", true) if result is Dictionary else result) and encoded(game.state) == before, label)
	set_paths(paths)

func restore_checkpoint(checkpoint: Dictionary) -> void:
	game.state = checkpoint.duplicate(true)
	game._assignments = game.state.get("assignments", {}).duplicate(true)
	game._machine = null; game._machine_key = ""
	check(game.save_game(), "accepted QA branch checkpoint saves")

func accept_offer(offer: Dictionary) -> bool:
	check(not offer.is_empty() and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)), "follow-up is reachable in the ordinary quoted market")
	if offer.is_empty(): return false
	var accepted: bool = game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)) and game.choose_contract(str(offer.id))
	check(accepted, "accept the offered contract through Game")
	return accepted

func source_receipt(source_id: String) -> Dictionary:
	for row in game.state.history:
		if str(row.get("id", "")) == source_id: return row
	return {}

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-saas-watch-" + str(OS.get_process_id())
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths)
	game._reset_state()
	check(game.choose_strategy("response") and game.start_free_career(), "QA company starts through the normal response-career entry")
	game.state.peak_profit = 3000; game.state.credit = 30
	game.state.market_leads = [SOURCE_CASE]; game.state.market_day = int(game.state.day); game._make_offers()
	var source_offer: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == SOURCE_CASE: source_offer = offer; break
	if not accept_offer(source_offer): finish(); return
	game.state.erase("saas_watch")
	var old_world := encoded(game.state.advanced)
	var old_scope := encoded(game.state.contract)
	var before := encoded(game.state)
	game.saas_watch_status(); game.saas_watch_offer(); game.advanced_view()
	check(encoded(game.state) == before and not game.state.has("saas_watch"), "reading an old accepted SaaS case does not invent monitoring or an incident")
	check(game.save_game() and game.load_game() and not game.state.has("saas_watch") and encoded(game.state.advanced) == old_world and encoded(game.state.contract) == old_scope, "old accepted case reload keeps its exact world and contract without retrofitting monitoring")
	observe("inspect_app", {"app":"app-19"}, 200)
	observe("inspect_app", {"app":"app-72"}, 200)
	var audit := observe("collect_audit", {}, 200)
	change("app-72", "consent", false); change("app-72", "session", false)
	check(bool(action("submit_report", {"record_ids":["audit-1", "audit-2", str(audit.get("id", ""))]}).get("ok", false)), "original incident submits actual approval and audit records")
	observe("probe_session", {"app":"app-72"}, 403)
	observe("submit_invoice", {"invoice_id":"BILL-001"}, 200)
	var verified: Array = game.verify()
	check(verified.size() == 5 and verified.all(func(row): return bool(row.get("passed", false))) and game.can_deliver(), "original incident meets its existing delivery conditions")
	var source_id := str(game.state.current_contract_id)
	check(game.deliver(), "original SaaS response delivers through Game")
	var original := encoded(source_receipt(source_id))
	var completed: Dictionary = game.state.duplicate(true)
	exercise_watch(completed, source_id, original)
	finish()

func incident(source_id: String) -> Dictionary:
	for item in game.state.get("saas_watch", {}).get("incidents", {}).values():
		if str(item.get("source_contract_id", "")) == source_id: return item
	return {}

func inspect_followup() -> Array:
	observe("inspect_app", {"app":"app-19"}, 200)
	observe("inspect_app", {"app":"app-84"}, 200)
	var audit := observe("collect_audit", {}, 200)
	var ids: Array = audit.get("data", {}).get("audit_ids", []).duplicate()
	ids.append(str(audit.get("id", "")))
	for row in game.advanced_view().get("saas", {}).get("records", []):
		if str(row.get("action", "")) == "baseline_reference": ids.append(str(row.get("id", "")))
	return ids

func pure_views(label: String) -> void:
	var before := encoded(game.state)
	for _i in 3:
		game.saas_watch_status(); game.saas_watch_offer(); game.company_cycle_view(); game.advanced_view()
	check(encoded(game.state) == before, label)

func exercise_watch(completed: Dictionary, source_id: String, original: String) -> void:
	pure_views("completed-case views cannot enroll a customer or generate the next incident")
	check(game.saas_watch_offer().is_empty(), "the source delivery cannot generate a same-day emergency")
	# First replay the same actual delivery without equipment. Enrolling after
	# tomorrow's offer exists must not rewrite that already-issued alert.
	failed_save(func(): return game.end_day(), "failed day transition restores cash, calendar, incident identity and pending offers")
	check(game.end_day(), "a real next day publishes the unmonitored emergency")
	var unmonitored: Dictionary = game.saas_watch_offer()
	if unmonitored.is_empty(): check(false, "next-day unmonitored offer exists"); return
	var frozen := encoded(unmonitored.get("saas_watch_payload", {}))
	check(not bool(unmonitored.get("saas_watch_payload", {}).get("monitored", true)) and int(unmonitored.get("saas_watch_payload", {}).get("alert_delay", 0)) == 9, "unmonitored notification freezes the nine-minute delay")
	check(game.enroll_saas_watch(), "customer can enroll after an alert has already been offered")
	game._make_offers()
	check(encoded(game.saas_watch_offer().get("saas_watch_payload", {})) == frozen, "same-day refresh cannot retrofit equipment into the existing offer")
	if not accept_offer(game.saas_watch_offer()): return
	check(int(game.state.advanced.get("elapsed_minutes", -1)) == 0 and int(game.state.advanced.egress.schedule[0].due_minute) == 3, "late notification starts actual work at zero with only three minutes to the next sync")
	inspect_followup()
	check(game.state.advanced.egress.exported_rows.size() == 3 and int(game.state.work.incident_cost) == 1500, "four minutes of identical investigation cost the unmonitored customer one real exported batch")
	check(game.cancel_current_contract(), "the unfinished follow-up can be cancelled")
	var cancelled := encoded(incident(source_id))
	check(str(incident(source_id).get("status", "")) == "cancelled" and game.end_day() and game.saas_watch_offer().is_empty() and encoded(incident(source_id)) == cancelled, "cancelled source remains archived and cannot create another emergency next day")
	restore_checkpoint(completed)
	var old_care := encoded(game.state.care_agreements)
	var old_targets := encoded(game.state.maintenance_targets)
	failed_save(func(): return game.enroll_saas_watch(), "failed investment restores money, equipment, customer enrollment and investment history")
	var cash := int(game.state.cash)
	check(game.enroll_saas_watch() and int(game.state.cash) == cash - 2400 and game.state.get("company_tools", {}).has("saas_watch"), "monitoring equipment and customer enrollment cost one company investment")
	var enrolled := encoded(game.state)
	check(game.enroll_saas_watch() and encoded(game.state) == enrolled, "duplicate enrollment is a free no-op")
	check(encoded(game.state.care_agreements) == old_care and encoded(game.state.maintenance_targets) == old_targets and encoded(source_receipt(source_id)) == original, "enrollment preserves previous delivery and existing VM care agreements")
	check(game.save_game() and game.load_game() and game.state.get("company_tools", {}).has("saas_watch"), "monitoring investment and customer registration survive restart")
	check(game.end_day(), "the monitored customer reaches the next real business day")
	var monitored: Dictionary = game.saas_watch_offer()
	if monitored.is_empty(): check(false, "next-day monitored offer exists"); return
	var payload: Dictionary = monitored.get("saas_watch_payload", {})
	check(bool(payload.get("monitored", false)) and int(payload.get("alert_delay", -1)) == 0 and str(monitored.get("saas_watch_source_contract_id", "")) == source_id and not CARE.reason(monitored).is_empty(), "watch offer is bound to the source and equipment while remaining outside VM recurring care")
	var source_approvals: Array = []
	for row in source_receipt(source_id).get("saas_outcome", {}).get("report", {}).get("original", {}).get("records", []):
		if str(row.get("action", "")) == "consent_review": source_approvals.append(row)
	check(source_approvals.size() == 2 and encoded(payload.get("approved_originals", [])) == encoded(source_approvals), "the next incident copies the actual two saved approval originals without reconstructing the customer's old applications")
	pure_views("reading the new market does not consume its incident or alter the frozen alert")
	var incident_before := encoded(incident(source_id))
	game._make_offers(); game._make_offers()
	check(encoded(incident(source_id)) == incident_before and encoded(game.saas_watch_offer().get("saas_watch_payload", {})) == encoded(payload), "market refresh neither duplicates the source incident nor changes its alert conditions")
	if not accept_offer(game.saas_watch_offer()): return
	check(str(game.state.contract.case_id) == WATCH_CASE and str(game.state.advanced.kind) == SOURCE_CASE and int(game.state.advanced.elapsed_minutes) == 0 and int(game.state.advanced.egress.schedule[0].due_minute) == 12, "new contract identity uses the response engine with the monitored investigation window")
	var referenced: Array = []
	for row in game.advanced_view().get("saas", {}).get("records", []):
		if str(row.get("action", "")) == "baseline_reference": referenced.append(row.get("data", {}).get("original", {}))
	check(encoded(game.state.advanced.get("watch_source", {})) == encoded(payload) and encoded(referenced) == encoded(source_approvals), "accepted world preserves frozen source conditions and exact baseline originals as separately identified references")
	check(not bool(game.state.advanced.report.get("submitted", true)) and not game.can_deliver(), "the previous customer's report does not count as current response or delivery evidence")
	var ids := inspect_followup()
	check(game.state.advanced.egress.exported_rows.is_empty(), "the same four-minute investigation finishes before any monitored export")
	change("app-84", "consent", false); change("app-84", "session", false)
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)), "new report uses this incident's actual approvals and observations")
	observe("probe_session", {"app":"app-84"}, 403)
	change("app-19", "session", false)
	var bill_id := str(game.state.advanced.invoice.id)
	observe("submit_invoice", {"invoice_id":bill_id}, 403)
	var interrupted := encoded(game.state.advanced)
	var work := encoded(game.state.work)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == interrupted and encoded(game.state.work) == work, "actual blocked invoice, monitoring source and response work survive interruption")
	change("app-19", "session", true)
	observe("probe_session", {"app":"app-84"}, 403)
	failed_save(func(): return action("submit_invoice", {"invoice_id":bill_id}), "failed invoice save restores the unreceived bill, journal, clock and expenses")
	observe("submit_invoice", {"invoice_id":bill_id}, 200)
	var invoice_receipt := str(game.state.advanced.invoice.receipt_id)
	var received := encoded(game.state)
	check(bool(action("submit_invoice", {"invoice_id":bill_id}).get("ok", false)) and encoded(game.state) == received, "retry keeps one customer invoice receipt without duplicate payment or labor")
	var checks: Array = game.verify()
	check(checks.size() == 5 and checks.all(func(row): return bool(row.get("passed", false))) and game.can_deliver() and game.state.advanced.egress.exported_rows.is_empty(), "current containment and the restored invoice are required despite the monitoring head start")
	check(game.deliver(), "monitored emergency delivers through the ordinary settlement API")
	var outcome: Dictionary = game.state.last_receipt.get("saas_outcome", {}).duplicate(true)
	var history: Dictionary = game.state.history[-1].duplicate(true)
	check(str(incident(source_id).get("status", "")) == "fulfilled" and encoded(history.get("saas_outcome", {})) == encoded(outcome) and encoded(outcome.get("watch_source", {})) == encoded(payload) and str(outcome.get("invoice", {}).get("receipt_id", "")) == invoice_receipt and encoded(source_receipt(source_id)) == original, "settlement fulfills one source and archives this invoice and original baseline without rewriting the previous customer's result")
	var mail: Dictionary = MAIL.project(game.state, history)
	check(bool(mail.get("confirmed", false)) and str(mail.get("body", "")).contains(invoice_receipt), "customer reply comes from the exact saved follow-up invoice receipt")
	check(game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(outcome), "delivered monitoring outcome survives restart")
	var fulfilled := encoded(incident(source_id))
	check(game.end_day() and game.saas_watch_offer().is_empty() and encoded(incident(source_id)) == fulfilled, "a fulfilled source cannot spawn the same emergency again")

func finish() -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_WATCH_TEST_PASS" if failures.is_empty() else "SAAS_WATCH_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
