extends "res://tests/test_saas_partner.gd"
## Regression of earned work and accounting, using an actual prior paid save.
const HANDOFF := "advanced-saas-ai-handoff"

func offer_handoff() -> Dictionary:
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == HANDOFF: return offer
	return {}

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-ai-handoff-market-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".bak", prefix + ".previous", prefix + ".settings"])
	set_paths(paths)
	source_path = OS.get_environment("WHL_HANDOFF_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_HANDOFF_SOURCE points to a read-only paid preflight save"); finish(); return
	source_hash = FileAccess.get_sha256(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(source_path)); file.close()
	if not game.load_game(): check(false, "prior paid save loads"); finish(); return
	source_id = str(game.state.current_contract_id)
	source_history = encoded(source_record())
	var legacy := encoded(game.state.advanced)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == legacy, "loading legacy preflight never reinterprets its policy or originals")
	game._make_offers()
	check(not bool(offer_handoff().get("market_available", false)), "the follow-up waits for the next business day")
	check(game.end_day(), "ordinary day settlement advances the customer work")
	var offer := offer_handoff().duplicate(true)
	if not bool(offer.get("market_available", false)): check(false, "earned handoff is a normal available consultation"); finish(); return
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)), "ordinary quote is accepted")
	var payload: Dictionary = offer.get("saas_ai_handoff_payload", {}).duplicate(true)
	game._make_offers()
	check(game.save_game() and game.load_game() and encoded(offer_handoff().get("saas_ai_handoff_payload", {})) == encoded(payload), "same-day reload preserves offered originals")
	failed_save(func(): return game.choose_contract(str(offer.id)), "failed save cannot consume a customer consultation")
	if not game.choose_contract(str(offer.id)): check(false, "accept quoted consultation"); finish(); return
	check(str(game.state.advanced.get("model_version", "")) == "saas-ai-handoff-v1", "acceptance creates the independent new model")
	var before := encoded(game.state)
	game.advanced_view(); game.company_cycle_view()
	check(encoded(game.state) == before, "render projections never advance the clock or fees")
	action("wait"); action("wait"); action("wait")
	check(cost("impact_cost") == 3000 and exported() == 6, "eight-minute archive event charges six actual copied rows once")
	failed_save(func(): return action("configure", {"key":"partner_archive","enabled":false}), "failed repair save cannot lose an incident or apply unpaid time")
	action("configure", {"key":"partner_archive","enabled":false})
	action("configure", {"key":"contacts","value":"linked"})
	action("configure", {"key":"partner_dispatch","enabled":true})
	action("run_business")
	action("probe_boundaries")
	action("collect_audit")
	var ids: Array = []
	for record in game.state.advanced.records: ids.append(str(record.id))
	check(bool(action("submit_report", {"record_ids":ids}).get("ok", false)), "repair report includes inherited originals and the actual incident")
	check(cost("business_cost") == 900 and exported() == 6 and cost("impact_cost") == 3000, "late receipt preserves both loss categories without double charge")
	check(game.verify().all(func(row): return bool(row.get("passed", false))) and game.can_deliver(), "repaired job can be accepted")
	var outcome := encoded(game.state.advanced)
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == outcome, "new live engagement round trips unchanged")
	check(game.deliver(), "ordinary delivery posts the repaired result")
	check(int(game.state.last_receipt.get("cost", 0)) == 4600, "settlement retains base 700 plus leak 3000 and delay 900")
	check(encoded(source_record()) == source_history, "new work never rewrites the previous delivery")
	check(game.end_day() and not bool(offer_handoff().get("market_available", false)), "a fulfilled source is not sold twice")
	finish()

func finish() -> void:
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "read-only source remains byte identical")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_AI_HANDOFF_MARKET_TEST_PASS" if failures.is_empty() else "SAAS_AI_HANDOFF_MARKET_TEST_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
