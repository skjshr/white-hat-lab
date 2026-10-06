extends "res://tests/test_saas_partner.gd"
## Requires WHL_AI_SOURCE: an actual delivered partner save, copied read-only.
## Branches replay only this test's accepted QA state. Automated actions are
## regression evidence, not native or first-time-player acceptance.
const AI_CASE := "advanced-saas-ai-preflight"

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_AI_PREFLIGHT: " + label)

func load_ai_source() -> bool:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-saas-ai-preflight-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths)
	source_path = OS.get_environment("WHL_AI_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_AI_SOURCE identifies the external read-only delivered partner fixture"); return false
	source_hash = FileAccess.get_sha256(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	if file == null: check(false, "the dedicated QA fixture copy can be written"); return false
	file.store_string(FileAccess.get_file_as_string(source_path)); file.close()
	if not game.load_game(): check(false, "the previous delivery loads from its QA copy"); return false
	source_id = str(game.state.current_contract_id)
	source_history = encoded(source_record())
	check(game.current_done() and str(game.state.advanced.get("model_version", "")) == "saas-partner-v1", "the source contains the actual prior partner delivery")
	var frozen := encoded(game.state.advanced)
	for _i in 3: game.advanced_view(); game.company_cycle_view()
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == frozen and encoded(source_record()) == source_history, "old partner records and organization survive reading and JSON resume without acquiring a new model")
	return true

func ai_offer() -> Dictionary:
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == AI_CASE and str(offer.get("saas_ai_payload", {}).get("source_contract_id", "")) == source_id: return offer
	return {}

func ai_available() -> bool:
	return bool(ai_offer().get("market_available", false))

func accept_preflight() -> bool:
	game._make_offers()
	check(not ai_available(), "the paid source cannot generate an AI review on the same business day")
	if not game.end_day(): check(false, "ordinary day settlement advances to the new consultation"); return false
	var offer: Dictionary = ai_offer().duplicate(true)
	if offer.is_empty() or not ai_available(): check(false, "the earned AI preflight appears in the ordinary next-day market"); return false
	var payload: Dictionary = offer.get("saas_ai_payload", {}).duplicate(true)
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)), "the real offer accepts the ordinary customer quote")
	game._make_offers(); game._make_offers()
	check(encoded(ai_offer().get("saas_ai_payload", {})) == encoded(payload) and game.save_game() and game.load_game() and encoded(ai_offer().get("saas_ai_payload", {})) == encoded(payload), "same-day refresh and JSON resume keep the exact source and quoted input")
	failed_save(func(): return game.choose_contract(str(offer.id)), "failed acceptance restores the quoted offer, prior work and source availability")
	if not game.choose_contract(str(offer.id)): check(false, "the quoted AI preflight is accepted through Game"); return false
	check(str(game.state.advanced.get("model_version", "")) == "saas-ai-preflight-v1" and str(game.state.advanced.get("kind", "")) == "advanced-saas-response" and not game.can_deliver(), "a new review begins without borrowing the previous successful acceptance")
	var pure := encoded(game.state)
	for _i in 3: game.advanced_view(); game.company_cycle_view()
	check(encoded(game.state) == pure, "viewing the work and customer path does not advance policy, events or cost")
	return true

func preflight_view() -> Dictionary:
	return game.advanced_view().get("ai_preflight", {})

func base_ids() -> Array:
	var ids: Array = ["AI-301"]
	for row in game.state.advanced.get("records", []):
		if str(row.get("action", "")) == "baseline_reference": ids.append(str(row.get("id", "")))
	return ids

func ai_record(id: String) -> Dictionary:
	for row in game.state.advanced.get("records", []):
		if str(row.get("id", "")) == id: return row
	return {}

func configure(key: String, enabled: bool) -> void:
	check(bool(action("configure", {"key":key,"enabled":enabled}).get("ok", false)), "apply policy " + key + "=" + str(enabled))

func boundaries(read_status: int = 403, write_status: int = 403) -> Array:
	var result := action("probe_boundaries")
	var ids: Array = result.get("data", {}).get("record_ids", [])
	check(bool(result.get("ok", false)) and ids.size() == 2 and int(result.get("data", {}).get("read_status", 0)) == read_status and int(result.get("data", {}).get("write_status", 0)) == write_status, "the same policy produces separate recorded read and outbound boundary results")
	if ids.size() == 2:
		check(str(ai_record(str(ids[0])).get("action", "")) == "boundary_read" and int(ai_record(str(ids[0])).get("status", 0)) == read_status and str(ai_record(str(ids[1])).get("action", "")) == "boundary_write" and int(ai_record(str(ids[1])).get("status", 0)) == write_status, "boundary status comes from the saved original records")
	return ids

func submit_current_report(proof_ids: Array) -> Array:
	var ids := base_ids(); ids.append_array(proof_ids)
	ids.append(str(observe("collect_audit", {}, 200).get("id", "")))
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)), "current approval, inherited originals, actual boundaries, normal receipt and audit support the report")
	return ids

func assistant_boundary() -> void:
	var ids := base_ids()
	var result := action("organize_records", {"mode":"assistant","record_ids":ids})
	var org: Dictionary = preflight_view().get("organization", {})
	var lanes: Dictionary = org.get("comparison", {}).get("lanes", {})
	check(bool(result.get("ok", false)) and cost("usage_cost") == 300 and lanes.size() == 3 and lanes.values().all(func(lane): return str(lane.get("state", "")) == "unknown"), "the owned assistant charges once and cannot infer unmeasured boundaries or a business receipt")
	var probe_ids := boundaries(200, 200)
	var before := encoded(game.state)
	result = action("organize_records", {"mode":"assistant","record_ids":ids})
	check(bool(result.get("ok", false)) and not bool(result.get("changed", true)) and encoded(game.state) == before and preflight_view().get("organization", {}).get("comparison", {}).get("lanes", {}).values().all(func(lane): return str(lane.get("state", "")) == "unknown"), "newly obtained but unselected originals cannot silently enter a cached comparison or trigger another charge")
	ids.append_array(probe_ids)
	failed_save(func(): return action("organize_records", {"mode":"assistant","record_ids":ids}), "failed assistant save restores fees, time, originals and the previous comparison")
	check(bool(action("organize_records", {"mode":"assistant","record_ids":ids}).get("ok", false)), "explicitly selected measurements can be compared")
	org = preflight_view().get("organization", {})
	lanes = org.get("comparison", {}).get("lanes", {})
	check(int(lanes.get("read", {}).get("status", 0)) == 200 and int(lanes.get("write", {}).get("status", 0)) == 200 and str(lanes.get("business", {}).get("state", "")) == "unknown" and lanes.values().all(func(lane): return lane.get("record_ids", []).all(func(id): return id in ids)), "comparison cites only selected observed read/write originals and leaves the unexecuted normal job unknown")
	var saved := encoded(game.state.advanced.organization)
	configure("customers", false)
	var pure := encoded(game.state)
	for _i in 3: game.advanced_view()
	check(encoded(game.state) == pure and encoded(game.state.advanced.organization) == saved and str(preflight_view().get("organization", {}).get("comparison", {}).get("state", "")) == "stale", "policy changes leave old analysis visible as stale and pure views never recalculate it")
	check(game.save_game() and game.load_game() and encoded(game.state.advanced.organization) == saved and str(preflight_view().get("organization", {}).get("comparison", {}).get("state", "")) == "stale", "JSON resume preserves the stored comparison and its policy-generation boundary")

func ready_checks() -> void:
	var checks: Array = game.verify()
	check(checks.size() == 5 and checks.all(func(row): return bool(row.get("passed", false))) and game.can_deliver(), "five actual current acceptance results permit ordinary delivery")

func deliver_preflight(expected_leak: int, expected_business: int) -> Dictionary:
	ready_checks()
	var expected: Dictionary = game._saas_outcome().duplicate(true)
	var ready: Dictionary = game.state.duplicate(true)
	failed_save(func(): return game.deliver(), "failed delivery save restores security-company finances, receipt, history and source consumption")
	check(game.deliver(), "the verified AI review delivers through ordinary company settlement")
	var receipt: Dictionary = game.state.last_receipt.duplicate(true)
	var history: Dictionary = game.state.history[-1].duplicate(true)
	check(int(receipt.get("cost", -1)) == 700 + expected_leak + expected_business and cost("usage_cost") == 0 and encoded(receipt.get("saas_outcome", {})) == encoded(expected) and encoded(history.get("saas_outcome", {})) == encoded(expected), "settlement archives actual evidence and separates base expense from leakage and deadline loss")
	check(int(receipt.get("saas_outcome", {}).get("costs", {}).get("impact_cost", 0)) == expected_leak and int(receipt.get("saas_outcome", {}).get("costs", {}).get("business_cost", 0)) == expected_business and int(game.state.cash) == int(ready.cash) + int(history.get("cash_delta", 0)) and str(receipt.get("invoice_id", "")) != "RCPT-SUM-001", "customer summary acceptance never becomes company cash and the two compensation accounts reconcile")
	var delivered := encoded(game.state)
	check(not game.deliver() and encoded(game.state) == delivered and game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "duplicate settlement cannot pay twice and the result survives restart")
	check(game.end_day() and not ai_available(), "a delivered source cannot generate a second AI review next day")
	game._make_offers()
	check(not ai_available() and encoded(source_record()) == source_history, "market refresh cannot consume the same source twice or rewrite the earlier partner originals")
	return receipt

func recover_overrestriction() -> Dictionary:
	for key in ["faq", "dispatch", "customers", "desk", "external"]: configure(key, false)
	var rejected := observe("run_business", {}, 403)
	check(rejected.get("data", {}).get("summaries", []).is_empty() and preflight_view().get("business", {}).get("accepted_summaries", []).is_empty() and game.state.advanced.invoice.get("accepted_summaries", []).is_empty(), "a denied normal job cannot invent summary content or an accepted customer copy")
	boundaries()
	check(not game.can_deliver() and str(game.state.advanced.invoice.get("receipt_id", "")).is_empty(), "blocking everything prevents leakage but cannot complete the promised normal business")
	for key in ["faq", "dispatch", "desk"]: configure(key, true)
	failed_save(func(): return action("run_business"), "failed normal-job save restores its customer receipt, policy observations, clock and costs")
	var normal := observe("run_business", {}, 200)
	check(int(normal.get("data", {}).get("summary_rows", 0)) == 6 and str(normal.get("data", {}).get("receipt_id", "")) == "RCPT-SUM-001" and int(game.state.work.minutes) == 14, "restoring only the required inputs and recipient accepts all six summaries at the deadline")
	var business: Dictionary = preflight_view().get("business", {})
	var summaries: Array = normal.get("data", {}).get("summaries", [])
	var requests: Array = business.get("requests", [])
	var knowledge: Dictionary = business.get("knowledge", {})
	var grounded: bool = summaries.size() == 6 and requests.size() == 6
	var seen := {}
	for summary in summaries:
		var request_id := str(summary.get("request_id", ""))
		var matches: Array = requests.filter(func(request): return str(request.get("id", "")) == request_id)
		if matches.size() != 1 or seen.has(request_id): grounded = false; continue
		seen[request_id] = true
		var request: Dictionary = matches[0]
		var shipment_id := str(request.get("shipment_id", ""))
		var shipment: Dictionary = knowledge.get("shipments", {}).get(shipment_id, {})
		var faq := str(knowledge.get("faq", {}).get(str(request.get("faq_key", "")), ""))
		var answer := str(summary.get("summary", ""))
		grounded = grounded and str(summary.get("subject", "")) == str(request.get("subject", "")) and str(summary.get("shipment_id", "")) == shipment_id and str(summary.get("faq_key", "")) == str(request.get("faq_key", "")) and not shipment.is_empty() and not faq.is_empty() and answer.contains(shipment_id) and answer.contains(str(shipment.get("status", ""))) and answer.contains(str(shipment.get("eta", ""))) and answer.contains(faq)
	var accepted_content := encoded(summaries)
	check(grounded and seen.size() == 6 and encoded(business.get("accepted_summaries", [])) == accepted_content and encoded(game.state.advanced.invoice.get("accepted_summaries", [])) == accepted_content, "each accepted answer cites its own actual question, shipment status and FAQ and is saved with the receipt")
	var same := encoded(game.state)
	check(bool(action("run_business").get("ok", false)) and encoded(game.state) == same, "retrying an accepted normal job preserves the receipt and never duplicates work")
	var proof_ids: Array = [str(normal.get("id", ""))]; proof_ids.append_array(boundaries())
	var ids := submit_current_report(proof_ids)
	var original := encoded(game.state.advanced.report.get("original", {}))
	configure("desk", false)
	rejected = observe("run_business", {}, 403)
	check(rejected.get("data", {}).get("summaries", []).is_empty() and encoded(preflight_view().get("business", {}).get("accepted_summaries", [])) == accepted_content and encoded(game.state.advanced.invoice.get("accepted_summaries", [])) == accepted_content, "a later denied recheck generates no answer and preserves the first accepted customer content")
	check(game.save_game() and game.load_game() and encoded(preflight_view().get("business", {}).get("accepted_summaries", [])) == accepted_content, "the accepted answers remain available after saving the later failed recheck")
	configure("desk", true)
	check(not bool(preflight_view().get("report_fresh", true)) and not game.can_deliver(), "even restoring the same policy values requires current-generation report evidence")
	check(not bool(action("submit_report", {"record_ids":ids}).get("ok", true)) and encoded(game.state.advanced.report.get("original", {})) == original, "old measurements cannot certify a new policy generation or replace the submitted original")
	normal = observe("run_business", {}, 200)
	check(str(normal.get("data", {}).get("receipt_id", "")) == "RCPT-SUM-001" and encoded(preflight_view().get("business", {}).get("accepted_summaries", [])) == accepted_content and encoded(game.state.advanced.invoice.get("accepted_summaries", [])) == accepted_content, "rechecking the current policy keeps the same real receipt and its first accepted answers")
	proof_ids = [str(normal.get("id", ""))]; proof_ids.append_array(boundaries())
	submit_current_report(proof_ids)
	check(encoded(game.state.advanced.report.get("original", {})) == original and game.state.advanced.report.get("supplements", []).size() == 1 and exported() == 0 and cost("business_cost") == 0, "a fresh supplement retains the initial report while timely recovery leaves no irreversible damage")
	return deliver_preflight(0, 0)

func delayed_review() -> Dictionary:
	for _i in 3: check(bool(action("wait").get("ok", false)), "explicit work advances the uncontained review")
	failed_save(func(): return action("wait"), "failed save crossing the first scheduled leak restores row copies, charges, clock and records")
	check(bool(action("wait").get("ok", false)) and exported() == 3 and cost("impact_cost") == 1500, "the first unattended synchronization leaves three copied rows and one real compensation")
	check(bool(action("wait").get("ok", false)) and cost("business_cost") == 900, "passing the fourteen-minute business deadline charges its own loss once")
	var interrupted := encoded(game.state.advanced)
	var work := encoded(game.state.work)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == interrupted and encoded(game.state.work) == work, "mid-loss JSON resume retains both cost accounts and the exact scheduled-event state")
	check(bool(action("wait").get("ok", false)) and exported() == 6 and cost("impact_cost") == 3000 and cost("business_cost") == 900, "the second scheduled leak adds only its three rows without charging the deadline twice")
	var late_records: Array = game.state.advanced.get("records", []).filter(func(row): return str(row.get("action", "")) == "summary_overdue")
	check(late_records.size() == 1, "deadline compensation has one persistent original record")
	var damaged: Dictionary = game.state.duplicate(true)
	var expected: Dictionary = game._saas_outcome().duplicate(true)
	var payload: Dictionary = game.state.contract.get("saas_ai_payload", {}).duplicate(true)
	failed_save(func(): return game.cancel_current_contract(), "failed cancellation restores the real damaged engagement and unpaid costs")
	check(game.cancel_current_contract() and int(game.state.last_receipt.get("costs", 0)) == 4600 and encoded(game.state.last_receipt.get("saas_outcome", {})) == encoded(expected), "cancelling settles all incurred losses and archives the interrupted result")
	game._make_offers()
	check(not ai_available() and game.save_game() and game.load_game() and not ai_available(), "cancellation cannot recreate the same consultation on the same day")
	check(game.end_day() and ai_available() and encoded(ai_offer().get("saas_ai_payload", {})) == encoded(payload), "next-day cancellation retry retains the same actual source originals")
	restore_checkpoint(damaged)
	configure("customers", false); configure("external", false)
	var normal := observe("run_business", {}, 200)
	var proofs: Array = [str(normal.get("id", ""))]; proofs.append_array(boundaries())
	submit_current_report(proofs)
	check(exported() == 6 and cost("impact_cost") == 3000 and cost("business_cost") == 900 and str(game.state.advanced.invoice.get("receipt_id", "")) == "RCPT-SUM-001", "later policy repair and normal acceptance cannot erase copied data or the missed deadline")
	return deliver_preflight(3000, 900)

func run() -> void:
	if not load_ai_source(): finish(); return
	if not accept_preflight(): finish(); return
	var accepted: Dictionary = game.state.duplicate(true)
	assistant_boundary()
	restore_checkpoint(accepted)
	var timely := recover_overrestriction()
	restore_checkpoint(accepted)
	var delayed := delayed_review()
	check(not timely.is_empty() and not delayed.is_empty() and int(timely.get("net", 0)) > int(delayed.get("net", 0)) and int(timely.get("satisfaction_after", 0)) > int(delayed.get("satisfaction_after", 0)), "the same accepted job leaves different company profit and customer trust after prevention versus delayed repair")
	finish()

func finish() -> void:
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "the original player fixture stays byte-for-byte unchanged")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_AI_PREFLIGHT_TEST_PASS" if failures.is_empty() else "SAAS_AI_PREFLIGHT_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
