extends "res://tests/test_saas_partner.gd"
## Ordinary market and accounting from a read-only, genuinely paid prior save.
const PRIORITY := "advanced-saas-priority"

func priority_offer() -> Dictionary:
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == PRIORITY: return offer
	return {}

func queue(id: String) -> Dictionary:
	for row in game.state.advanced.priority.queues:
		if str(row.id) == id: return row
	return {}

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-priority-market-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".bak", prefix + ".previous", prefix + ".settings"]); set_paths(paths)
	source_path = OS.get_environment("WHL_PRIORITY_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_PRIORITY_SOURCE points to a read-only paid handoff save"); finish(); return
	source_hash = FileAccess.get_sha256(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(source_path)); file.close()
	if not game.load_game(): check(false, "prior paid handoff save loads"); finish(); return
	source_id = str(game.state.current_contract_id); source_history = encoded(source_record())
	var legacy := encoded(game.state.advanced)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == legacy, "legacy handoff round trips without reinterpretation")
	game._make_offers()
	check(not bool(priority_offer().get("market_available", false)), "repeat work waits until the next day")
	check(game.end_day(), "normal day settlement publishes earned follow-up")
	var offer := priority_offer().duplicate(true)
	if not bool(offer.get("market_available", false)): check(false, "priority response is available in the ordinary market"); finish(); return
	var payload: Dictionary = offer.get("saas_priority_payload", {}).duplicate(true)
	check(int(payload.get("round", 0)) == 1 and payload.get("approved_originals", []).size() == 3, "first round freezes three actual handoff originals")
	var leads: Array = game.company_cycle_view().get("opportunities", []).filter(func(row): return str(row.get("case_id", "")) == PRIORITY)
	check(leads.size() == 1 and str(leads[0].get("source_rating", "")) == str(source_record().get("rating", "")), "company follow-up shows the actual prior delivery rating")
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)), "normal quotation")
	game._make_offers()
	check(game.save_game() and game.load_game() and encoded(priority_offer().get("saas_priority_payload", {})) == encoded(payload), "offered source survives refresh and resume")
	failed_save(func(): return game.choose_contract(str(offer.id)), "failed acceptance save leaves consultation available")
	if not game.choose_contract(str(offer.id)): check(false, "normal acceptance"); finish(); return
	check(str(game.state.advanced.get("model_version", "")) == "saas-priority-v1", "independent model starts")
	var before := encoded(game.state)
	game.advanced_view(); game.company_cycle_view()
	check(encoded(game.state) == before, "views never spend time or money")
	action("wait"); action("wait"); action("wait")
	check(cost("impact_cost") == 3000 and cost("business_cost") == 4500, "ignored urgent workflow and background export charge distinct real losses")
	failed_save(func(): return action("toggle_background", {"enabled":false}), "failed repair save retains clock, incident and costs")
	action("toggle_background", {"enabled":false})
	for id in ["claims", "dispatch"]:
		action("configure", {"queue_id":id,"key":"scope","value":"linked"})
		action("configure", {"queue_id":id,"key":"recipient","value":str(queue(id).approved_recipient)})
		action("run_queue", {"queue_id":id})
		action("probe_queue", {"queue_id":id})
	action("probe_background"); action("collect_audit")
	var ids: Array = game.advanced_view().priority.report.required_record_ids
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)), "repair report proves both workflows and captures all losses")
	check(cost("business_cost") == 5400 and cost("impact_cost") == 3000, "both missed workflow deadlines persist after recovery")
	check(game.verify().all(func(row): return bool(row.get("passed", false))) and game.can_deliver(), "repaired engagement can be delivered")
	var outcome := encoded(game.state.advanced)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == outcome, "in-progress state round trips unchanged")
	check(game.deliver(), "ordinary delivery settles the repair")
	check(int(game.state.last_receipt.get("cost", 0)) == 9100 and str(game.state.last_receipt.get("grade", "")) == "A", "base 700 plus export 3000 plus late 5400 are charged once")
	check(int(game.state.last_receipt.get("saas_business_satisfaction_delta", 0)) == -6 and int(game.state.history[-1].get("saas_business_satisfaction_delta", 0)) == -6, "both late workflows retain their customer satisfaction impact in settlement and history")
	check(encoded(source_record()) == source_history, "previous delivery originals remain unchanged")
	var first_id := str(game.state.current_contract_id)
	check(game.end_day(), "next normal business day")
	var next := priority_offer()
	check(bool(next.get("market_available", false)) and int(next.get("saas_priority_payload", {}).get("round", 0)) == 2 and str(next.get("saas_priority_payload", {}).get("source_contract_id", "")) == first_id, "delivered work earns round two from this exact source")
	check(next.get("saas_priority_payload", {}).get("approved_originals", []).size() == 5, "next round retains this engagement's approvals, receipts and report only")
	check(game.set_offer_quote(str(next.id), int(game.contract_quote(next).estimated_fee)) and game.choose_contract(str(next.id)), "same catalog case can be accepted next day")
	check(int(queue("dispatch").deadline_minute) == 6 and str(queue("claims").approved_recipient) == "minato/archive", "round two reverses urgency and changes refund destination")
	check(game.cancel_current_contract(), "new repeat work supports ordinary cancellation")
	game._make_offers()
	check(not bool(priority_offer().get("market_available", false)), "cancelled engagement cannot be reoffered on the same day")
	check(game.end_day() and bool(priority_offer().get("market_available", false)), "cancelled source is retryable the following day")
	finish()

func finish() -> void:
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "source remains byte identical")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_PRIORITY_MARKET_TEST_PASS" if failures.is_empty() else "SAAS_PRIORITY_MARKET_TEST_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
