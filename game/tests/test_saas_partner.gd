extends "res://tests/test_saas_sessions.gd"
## The source is a read-only native delivery. Both branches accept its ordinary
## next-day offer; no eligibility, evidence, successful job or result is injected.
const IDENTITY_UI = preload("res://scripts/os_saas_session_identity.gd")

var source_path := ""
var source_hash := ""
var source_id := ""
var source_history := ""
var source_originals: Array = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_PARTNER: " + label)

func source_record() -> Dictionary:
	for row in game.state.history:
		if str(row.get("id", "")) == source_id: return row
	return {}

func partner_offer() -> Dictionary:
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == CASE_ID and str(offer.get("saas_partner_payload", {}).get("source_contract_id", "")) == source_id: return offer
	return {}

func available_partner() -> bool:
	return bool(partner_offer().get("market_available", false))

func business_job(purpose: String) -> Dictionary:
	for job in game.state.advanced.get("session_case", {}).get("business", {}).get("jobs", []):
		if str(job.get("purpose", "")) == purpose: return job
	return {}

func cost(kind: String) -> int:
	return int(game.state.work.get("saas_costs", {}).get(kind, 0))

func observed_reissue_purposes() -> Dictionary:
	var n: Dictionary = game.advanced_view().get("saas", {})
	var purposes := {}
	for session in n.get("session_case", {}).get("sessions", []):
		var id := str(session.get("id", ""))
		if id in ["SES-201", "SES-202", "SES-203"]:
			purposes[id] = IDENTITY_UI.observed_purpose(n, session)
	return purposes

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-saas-partner-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths)
	source_path = OS.get_environment("WHL_SAAS_PARTNER_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_SAAS_PARTNER_SOURCE points to the read-only native v2 delivery"); finish(); return
	source_hash = FileAccess.get_sha256(source_path)
	var fixture := FileAccess.get_file_as_string(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	if file == null: check(false, "own QA fixture copy can be written"); finish(); return
	file.store_string(fixture); file.close()
	if not game.load_game(): check(false, "native source loads from its QA copy"); finish(); return
	source_id = str(game.state.current_contract_id)
	check(game.current_done() and str(game.state.advanced.get("model_version", "")) == "saas-sessions-v2" and str(source_record().get("rating", "")) == "on_time", "source is the genuinely delivered former v2 engagement")
	source_history = encoded(source_record())
	for record in source_record().get("saas_outcome", {}).get("report", {}).get("original", {}).get("records", []):
		if str(record.get("action", "")) in ["consent_review", "session_issued"]: source_originals.append(record.duplicate(true))
	check(source_originals.size() == 4, "four prior approval and issuance originals come from the delivered report")
	var old_world := encoded(game.state.advanced)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == old_world and encoded(source_record()) == source_history, "loading and round-tripping a completed v2 does not upgrade its world or report")
	game._make_offers()
	check(not available_partner(), "the delivered source cannot create a same-day partner engagement")
	check(game.end_day(), "ordinary business-day settlement publishes the follow-up")
	var offer: Dictionary = partner_offer().duplicate(true)
	if offer.is_empty() or not available_partner(): check(false, "next-day partner offer is available through the normal market"); finish(); return
	var payload: Dictionary = offer.get("saas_partner_payload", {}).duplicate(true)
	check(str(payload.get("source_contract_id", "")) == source_id and encoded(payload.get("approved_originals", [])) == encoded(source_originals), "offer freezes this exact delivery and all four prior originals")
	var pure := encoded(game.state)
	for _i in 3: game.advanced_view(); game.company_cycle_view()
	check(encoded(game.state) == pure, "reading the market or prior result cannot consume or revise the new source")
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)), "customer quote uses the actual offered engagement")
	game._make_offers(); game._make_offers()
	check(encoded(partner_offer().get("saas_partner_payload", {})) == encoded(payload) and game.save_game() and game.load_game() and encoded(partner_offer().get("saas_partner_payload", {})) == encoded(payload), "same-day market refresh and JSON resume preserve the quoted payload")
	var offered: Dictionary = game.state.duplicate(true)
	var correct := play_branch(false, payload)
	restore_checkpoint(offered)
	var mistaken := play_branch(true, payload)
	check(not correct.is_empty() and not mistaken.is_empty() and int(correct.get("cost", 0)) == 700 and int(mistaken.get("cost", 0)) == 3800 and int(correct.get("net", 0)) > int(mistaken.get("net", 0)) and int(correct.get("satisfaction_after", 0)) - int(mistaken.get("satisfaction_after", 0)) == 6, "the same offered incident preserves the financial and trust difference between comparison and the previous case's memorized revocation")
	finish()

func play_branch(mistaken: bool, payload: Dictionary) -> Dictionary:
	var offer := partner_offer()
	if not game.choose_contract(str(offer.get("id", ""))): check(false, "accept the quoted partner offer through Game"); return {}
	check(str(game.state.advanced.get("model_version", "")) == "saas-partner-v1" and int(game.state.advanced.get("session_case", {}).get("version", 0)) == 3 and str(game.state.advanced.invoice.id) == "BILL-004" and not game.can_deliver(), "new contract starts a fresh partner world without borrowing the source's success")
	check(observed_reissue_purposes() == {"SES-201":"", "SES-202":"", "SES-203":""}, "the actual identity UI exposes no reissue purpose before inspecting any connection")
	var reference_ids: Array = []
	var references: Array = []
	for record in game.advanced_view().get("saas", {}).get("records", []):
		if str(record.get("action", "")) == "baseline_reference":
			reference_ids.append(str(record.get("id", "")))
			references.append(record.get("data", {}).get("original", {}))
	check(reference_ids.size() == 4 and encoded(references) == encoded(source_originals) and encoded(game.state.contract.get("saas_partner_payload", {})) == encoded(payload), "new references preserve the exact former records separately from current originals")
	if mistaken: observe("revoke_connection", {"session_id":"SES-203"}, 200)
	var ids: Array = ["audit-1", "audit-2", "audit-3", "audit-4"]
	for id in ["SES-201", "SES-202", "SES-203"]:
		var record := observe("inspect_connection", {"session_id":id}, 200)
		ids.append(str(record.get("id", "")))
		if id == "SES-201": check(not bool(record.get("data", {}).get("approved", true)) and str(record.get("data", {}).get("destination", "")) == "partner-vault/archive", "the former batch ID now requests the unapproved archive")
		if id == "SES-203": check(bool(record.get("data", {}).get("approved", false)) and str(record.get("data", {}).get("destination", "")) == "partner-vault/dispatch", "the former suspicious ID now has a distinct approved dispatch destination")
	var inspected_purposes := observed_reissue_purposes()
	check(inspected_purposes == {"SES-201":"", "SES-202":"billing", "SES-203":"partner-dispatch"}, "observed originals offer billing and partner reissue while the unapproved archive remains unavailable")
	observe("collect_audit", {}, 200)
	var active_dispatch := "SES-203"
	var first_bill_receipt := ""
	if mistaken:
		observe("probe_session", {"session_id":"SES-203"}, 403)
		check(str(business_job("partner-dispatch").get("status", "")) == "queued", "revoking the old answer stops this customer's actual partner handoff")
		observe("submit_invoice", {"invoice_id":"BILL-004"}, 200)
		first_bill_receipt = str(game.state.advanced.invoice.get("receipt_id", ""))
		observe("probe_session", {"session_id":"SES-201"}, 200)
		check(cost("business_cost") == 1600 and not game.can_deliver(), "denying the normal dispatch connection cannot prove containment and its missed deadline remains a real cost")
		failed_save(func(): return action("collect_audit"), "failed audit save rolls back the newly exported rows, compensation, clock and record while keeping prior delay")
		observe("collect_audit", {}, 200)
		check(exported() == 3 and cost("impact_cost") == 1500 and cost("business_cost") == 1600, "the wrong revocation leaves the actual archive export live alongside the blocked legitimate work")
		var interrupted := encoded(game.state.advanced)
		check(game.save_game() and game.load_game() and encoded(game.state.advanced) == interrupted and encoded(source_record()) == source_history, "interrupted evidence and both losses survive JSON resume without altering source history")
		check(observed_reissue_purposes() == inspected_purposes, "JSON resume preserves the actual UI's evidence-derived reissue choices")
		observe("revoke_connection", {"session_id":"SES-201"}, 200)
		observe("reissue_connection", {"purpose":"partner-dispatch"}, 200)
		active_dispatch = "SES-204"
	else:
		observe("revoke_connection", {"session_id":"SES-201"}, 200)
	observe("probe_session", {"session_id":"SES-201"}, 403)
	observe("submit_invoice", {"invoice_id":"BILL-004"}, 200)
	if mistaken: check(not first_bill_receipt.is_empty() and str(game.state.advanced.invoice.get("receipt_id", "")) == first_bill_receipt, "reconfirming BILL-004 after recovery retains its actual first receipt")
	observe("probe_session", {"session_id":active_dispatch}, 200)
	var dispatch: Dictionary = business_job("partner-dispatch")
	check(str(dispatch.get("status", "")) == "completed" and str(dispatch.get("used_session_id", "")) == active_dispatch and int(dispatch.get("loss_amount", 0)) == (1600 if mistaken else 0), "the handoff completes on its actual approved connection and retains an already incurred delay")
	var audit := observe("collect_audit", {}, 200)
	ids.append(str(audit.get("id", "")))
	var before_report := encoded(game.state)
	check(not bool(action("submit_report", {"record_ids":ids}).get("ok", true)) and encoded(game.state) == before_report, "current observations alone cannot omit the required comparison with previous approval originals")
	ids.append_array(reference_ids)
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)), "report uses prior originals and this incident's actual inspection and audit")
	verify_ready(3 if mistaken else 0)
	var expected: Dictionary = game._saas_outcome().duplicate(true)
	var ready: Dictionary = game.state.duplicate(true)
	if mistaken:
		check(game.cancel_current_contract() and int(game.state.last_receipt.get("costs", 0)) == 3800 and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "cancelling records both actual losses without consuming a delivered outcome")
		game._make_offers()
		check(not available_partner() and game.save_game() and game.load_game() and not available_partner(), "cancelled engagement cannot be accepted again on the same day")
		check(game.end_day() and available_partner() and str(partner_offer().get("saas_partner_payload", {}).get("source_contract_id", "")) == source_id and encoded(partner_offer().get("saas_partner_payload", {}).get("approved_originals", [])) == encoded(source_originals), "next-day retry retains the same actual source originals")
		restore_checkpoint(ready)
	check(game.deliver(), "verified partner response delivers through ordinary settlement")
	var receipt: Dictionary = game.state.last_receipt.duplicate(true)
	check(encoded(receipt.get("saas_outcome", {})) == encoded(expected) and encoded(game.state.history[-1].get("saas_outcome", {})) == encoded(expected) and str(receipt.get("saas_outcome", {}).get("session_case", {}).get("partner_source", {}).get("source_contract_id", "")) == source_id and encoded(source_record()) == source_history, "the new result archives its own world and source identity while the prior delivery remains immutable")
	check(str(receipt.get("grade", "")) == ("A" if mistaken else "S") and int(receipt.get("saas_satisfaction_delta", 0)) == (-3 if mistaken else 0) and int(receipt.get("saas_business_satisfaction_delta", 0)) == (-3 if mistaken else 0), "leakage and late handoff have separate lasting customer consequences")
	var delivered := encoded(game.state)
	check(not game.deliver() and encoded(game.state) == delivered and game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "duplicate delivery cannot consume or pay the same incident twice")
	check(game.end_day() and not available_partner(), "the delivered source cannot generate the same partner engagement next day")
	game._make_offers()
	check(not available_partner() and encoded(source_record()) == source_history, "market refresh cannot reuse the consumed source or rewrite its evidence")
	return receipt

func finish() -> void:
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "the native source file remains byte-for-byte unchanged")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_PARTNER_TEST_PASS" if failures.is_empty() else "SAAS_PARTNER_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
