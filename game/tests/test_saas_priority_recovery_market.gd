extends "res://tests/test_saas_priority_market.gd"
## Starts from the native, paid round-two save; no completion or offer is injected.

func finish_report(use_assistant: bool = true) -> void:
	for id in ["dispatch", "claims"]: action("probe_queue", {"queue_id":id})
	action("collect_audit")
	var ids: Array = game.advanced_view().priority.report.required_record_ids
	if use_assistant: check(bool(action("organize_records", {"record_ids":ids,"mode":"assistant"}).get("ok", false)), "selected originals can be organized")
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)), "report includes the actual restoration and emergency receipt")
	check(game.verify().all(func(row): return bool(row.get("passed", false))) and game.can_deliver(), "ordinary validation permits delivery")

func configure_queue(id: String) -> void:
	action("configure", {"queue_id":id,"key":"scope","value":"linked"})
	action("configure", {"queue_id":id,"key":"recipient","value":str(queue(id).approved_recipient)})

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-priority-recovery-market-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".bak", prefix + ".previous", prefix + ".settings"]); set_paths(paths)
	source_path = OS.get_environment("WHL_PRIORITY_RECOVERY_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_PRIORITY_RECOVERY_SOURCE must reference a native paid round-two save"); finish(); return
	source_hash = FileAccess.get_sha256(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(source_path)); file.close()
	if not game.load_game(): check(false, "paid legacy round two loads"); finish(); return
	source_id = str(game.state.current_contract_id); source_history = encoded(source_record())
	var legacy := encoded(game.state.advanced)
	check(int(game.state.advanced.priority.round) == 2 and not game.state.advanced.priority.has("recovery"), "source is a genuine legacy priority engagement")
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == legacy, "legacy world stays byte-structurally unchanged through save/load")
	check(game.end_day(), "normal next-day market")
	var offer := priority_offer().duplicate(true)
	check(int(offer.get("saas_priority_payload", {}).get("round", 0)) == 3 and offer.get("saas_priority_payload", {}).has("recovery_plan"), "new market offer freezes round-three restoration plan")
	if not bool(offer.get("market_available", false)) or not game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)) or not game.choose_contract(str(offer.id)):
		check(false, "normal quotation and acceptance"); finish(); return
	var accepted: Dictionary = game.state.duplicate(true)
	var frozen := encoded(game.state)
	game.advanced_view(); game.company_cycle_view()
	check(encoded(game.state) == frozen, "restoration views do not transact")
	action("toggle_background", {"enabled":false}); configure_queue("claims")
	failed_save(func(): return action("manual_queue", {"queue_id":"claims"}), "failed handoff save restores money, clock, quota and receipt")
	check(bool(action("manual_queue", {"queue_id":"claims"}).get("ok", false)), "urgent refund handoff completes before its deadline")
	check(cost("manual_cost") == 900 and cost("manual_runs") == 1 and cost("usage_cost") == 0 and cost("assistant_runs") == 0, "manual fee is never charged as an assistant call")
	var receipt_id := str(queue("claims").receipt_id); var first_minute := int(queue("claims").received_minute)
	var handed_off := encoded(game.state)
	check(not bool(action("manual_queue", {"queue_id":"claims"}).get("changed", true)) and encoded(game.state) == handed_off, "same handoff retry consumes no time, money or quota")
	check(game.save_game() and game.load_game() and encoded(game.state) == handed_off, "interrupted emergency handoff survives resume")
	action("rebuild_connector"); configure_queue("dispatch"); action("run_queue", {"queue_id":"dispatch"}); action("run_queue", {"queue_id":"claims"})
	check(str(queue("claims").receipt_id) == receipt_id and int(queue("claims").received_minute) == first_minute and str(queue("claims").receipt_channel) == "manual", "normal verification retains the first manual receipt and time")
	finish_report()
	check(cost("business_cost") == 0 and cost("impact_cost") == 0 and cost("usage_cost") == 300 and cost("manual_cost") == 900, "successful fees remain separate from avoided losses")
	check(game.deliver(), "ordinary emergency delivery")
	check(str(game.state.last_receipt.get("grade", "")) == "S" and int(game.state.last_receipt.get("cost", 0)) == 1900, "base 700, manual 900 and assistant 300 settle exactly once")
	check(encoded(source_record()) == source_history, "prior paid originals are unchanged")
	var reply := str(MAIL.project(game.state, game.state.history[-1]).get("body", ""))
	check(reply.contains("手動受付") and reply.contains("900"), "customer acknowledges the actual emergency route and fee")
	check(game.end_day(), "next regular business day after repair")
	offer = priority_offer().duplicate(true)
	check(int(offer.get("saas_priority_payload", {}).get("round", 0)) == 4, "restored delivery earns the next engagement")
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)) and game.choose_contract(str(offer.id)), "ordinary next engagement can be accepted")
	action("toggle_background", {"enabled":false}); action("rebuild_connector")
	configure_queue("dispatch"); action("run_queue", {"queue_id":"dispatch"})
	configure_queue("claims"); action("run_queue", {"queue_id":"claims"})
	finish_report()
	check(cost("manual_cost") == 0 and cost("business_cost") == 0 and cost("impact_cost") == 0, "longer cutoff permits direct repair without paying for the manual route")
	check(game.deliver() and int(game.state.last_receipt.get("cost", 0)) == 1000, "direct repair saves the optional 900 fee")

	restore_checkpoint(accepted)
	observe("run_queue", {"queue_id":"claims"}, 503)
	action("rebuild_connector")
	check(cost("business_cost") == 4500 and cost("impact_cost") == 3000, "rebuilding alone leaves the old session and missed cutoff losses")
	action("toggle_background", {"enabled":false}); configure_queue("claims"); action("manual_queue", {"queue_id":"claims"})
	check(cost("manual_cost") == 900 and cost("usage_cost") == 0, "late manual handoff is still charged only as manual work")
	var late_handoff := encoded(game.state)
	check(game.save_game() and game.load_game() and encoded(game.state) == late_handoff, "failure and handoff state persist together")
	var cancel_cost := 700 + int(game.state.work.get("incident_cost", 0))
	check(game.cancel_current_contract() and int(game.state.last_receipt.get("costs", 0)) == cancel_cost and cancel_cost == 9100, "cancellation retains manual, leakage and missed-cutoff expenses")
	finish()

func finish() -> void:
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "native source remains byte identical")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_PRIORITY_RECOVERY_MARKET_TEST_PASS" if failures.is_empty() else "SAAS_PRIORITY_RECOVERY_MARKET_TEST_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
