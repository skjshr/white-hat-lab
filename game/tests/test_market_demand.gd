extends SceneTree

const MARKET = preload("res://scripts/market_demand.gd")
var failures: Array[String] = []

func _init() -> void:
	_test_pure_market()
	var qa_id := str(OS.get_process_id())
	var game: Node = await _new_game("fresh-"+qa_id)
	_assert(game.choose_strategy("advisory") and game.start_free_career(), "fresh career setup")
	var initial_leads: Array = game.state.market_leads.duplicate()
	_assert(initial_leads.size() > 0 and initial_leads.size() <= 9, "initial leads bounded")
	_assert(_category_counts_are_bounded(game), "initial category caps")
	var quoted_initial: Dictionary = _find_lead(game)
	var quoted_case_id := str(quoted_initial.get("case_id", ""))
	_assert(not quoted_initial.is_empty() and game.set_offer_quote(str(quoted_initial.get("id", "")), int(quoted_initial.get("reward", 0))), "same-day quote fixture")
	game.state.skills.advisory = 10; game.state.skills.operations = 10; game.state.skills.response = 10
	game.state.profit = 1000000; game._update_growth(); game._make_offers()
	for lead in initial_leads: _assert(lead in game.state.market_leads, "same-day lead retained")
	_assert(_category_counts_are_bounded(game), "filled category caps")
	_assert(quoted_case_id in game.state.market_leads, "same-day quoted lead retained after skill refresh")
	var completed_case := ""
	for candidate_case in game.state.market_leads:
		if str(candidate_case) != quoted_case_id:
			completed_case = str(candidate_case); break
	if not completed_case.is_empty():
		game.state.history.append({"day":int(game.state.day),"case_id":completed_case,"id":"completed-market-fixture"})
		game._make_offers()
		_assert(completed_case not in game.state.market_leads, "completed case does not occupy a fresh market lead")
		_assert(quoted_case_id in game.state.market_leads, "quoted completed lead remains visible")
	var hidden_offer: Dictionary = _find_unrequested(game)
	_assert(not hidden_offer.is_empty(), "unlocked non-lead exists")
	if not hidden_offer.is_empty():
		var before_state: Dictionary = game.state.duplicate(true)
		_assert(not game.set_offer_quote(str(hidden_offer.id), int(hidden_offer.reward)), "non-lead quote rejected")
		_assert(not game.choose_contract(str(hidden_offer.id)), "non-lead acceptance rejected")
		_assert(game.state == before_state, "non-lead rejection has no state change")
	var lead_offer: Dictionary = _find_lead(game)
	_assert(not lead_offer.is_empty(), "lead exists for quote persistence")
	if not lead_offer.is_empty():
		_assert(game.set_offer_quote(str(lead_offer.id), int(lead_offer.reward)), "lead quote saved")
		var saved_leads: Array = game.state.market_leads.duplicate(); var saved_quotes: Dictionary = game.state.offer_quotes.duplicate(true)
		_assert(game.save_game(), "market save"); _assert(game.load_game(), "market reload")
		_assert(game.state.market_leads == saved_leads and _quotes_equal(game.state.offer_quotes, saved_quotes), "leads and quotes survive reload")
	var raw: String = FileAccess.get_file_as_string(game.save_path); var legacy: Dictionary = JSON.parse_string(raw)
	legacy.erase("market_day"); legacy.erase("market_leads")
	for legacy_offer in legacy.get("offers", []): legacy_offer.erase("market_available"); legacy_offer.erase("market_day")
	var legacy_path := "user://qa-market-legacy-"+qa_id+".json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE); legacy_file.store_string(JSON.stringify(legacy)); legacy_file.close()
	var restored: Node = await _new_game("legacy-"+qa_id, legacy_path)
	_assert(restored.load_game(), "legacy save load")
	var old_unlocked: Array = []
	for old_offer in restored.state.offers:
		if bool(old_offer.get("unlocked", false)): old_unlocked.append(str(old_offer.get("case_id", "")))
	var legacy_completed: Dictionary = {}
	for receipt in restored.state.history:
		if receipt is Dictionary and not str(receipt.get("case_id", "")).is_empty(): legacy_completed[str(receipt.case_id)] = true
	for case_id in old_unlocked:
		_assert((case_id in restored.state.market_leads) == (not legacy_completed.has(case_id)), "legacy lead migration excludes completed case only")
	var legacy_available := 0
	for summary in restored.market_summary().values(): legacy_available += int(summary.get("available", 0))
	_assert(legacy_available == old_unlocked.size() - legacy_completed.size(), "legacy market summary preserves available offers")
	_assert(restored.end_day(), "legacy next day"); _assert(_category_counts_are_bounded(restored), "next-day legacy rotation bounded")
	var active: Node = await _new_game("active-"+qa_id)
	_assert(active.choose_strategy("advisory") and active.start_free_career(), "active career setup")
	var active_offer: Dictionary = _find_lead(active)
	_assert(active.set_offer_quote(str(active_offer.id), int(active_offer.reward)), "active quote")
	_assert(active.choose_contract(str(active_offer.id)), "active contract")
	var active_id := str(active.state.current_contract_id); var active_fee := int(active.state.contract.agreed_fee); var deadline := str(active.contract_queue()[0].deadline_text)
	var active_vm_key: String = str(active._vm_key()); var work_start: Dictionary = active.state.work.duplicate(true)
	_assert(active.vm_run("ssh client") != "", "active VM ssh")
	var fs_before: Dictionary = active._vm().state.fs.duplicate(true); var config_before: String = str(active._vm().state.fs.get(str(active._vm().state.config_path), ""))
	_assert(active.vm_write("/home/operator/market-note.txt", "market-check"), "active VM note write")
	fs_before = active._vm().state.fs.duplicate(true); config_before = str(active._vm().state.fs.get(str(active._vm().state.config_path), ""))
	_assert(active.end_day(), "active contract next day")
	_assert(str(active.state.current_contract_id) == active_id and int(active.state.contract.agreed_fee) == active_fee, "active contract fee survives day")
	var after_queue: Array = active.contract_queue(); _assert(not after_queue.is_empty() and str(after_queue[0].deadline_text) == deadline, "active contract deadline survives day")
	var carried_vm: Dictionary = active.state.vm_states.get(active_vm_key, {}); _assert(carried_vm.get("fs", {}) == fs_before and str(carried_vm.get("fs", {}).get(str(carried_vm.get("config_path", "")), "")) == config_before, "active VM survives day")
	_assert(int(active.state.contract_contexts[active_id].work.get("started_day", -1)) == int(work_start.get("started_day", -2)) and int(active.state.contract_contexts[active_id].work.get("started_at", -1)) == int(work_start.get("started_at", -2)), "active work start survives day")
	_assert(str(active.state.contract.get("case_id", "")) not in active.state.market_leads, "carried case absent from new leads")
	await _test_ren_guards(qa_id)
	if failures.is_empty(): print("MARKET_TEST_PASS")
	else:
		for failure in failures: push_error(failure)
		print("MARKET_TEST_FAIL count=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _test_pure_market() -> void:
	var candidates: Array = []
	for category in ["advisory", "operations", "response"]:
		for index in 8: candidates.append({"id":"%s-%d" % [category,index],"case_id":"%s-%d" % [category,index],"category":category,"unlocked":true})
	candidates.append({"id":"locked","case_id":"locked","category":"advisory","unlocked":false})
	var day := 6; var selected: Array = MARKET.select_by_category(candidates, day)
	_assert(selected.size() == 9, "pure category total")
	for category_index in 3:
		var category: String = ["advisory","operations","response"][category_index]
		var expected: int = [2,3,4][MARKET.phase(day, category_index)]
		_assert(selected.filter(func(id): return str(id).begins_with(category+"-")).size() == expected, "pure category phase cap "+category)
	_assert(MARKET.select_by_category(candidates, day) == selected, "pure same-day deterministic")
	_assert(not _same_ids(MARKET.select_by_category(candidates, day + 3), selected), "same phase day changes membership")
	var recent := selected.slice(0, 2); var without_recent: Array = MARKET.select_by_category(candidates, day, recent)
	_assert(str(recent[0]) not in without_recent and str(recent[1]) not in without_recent, "recent cases excluded when capacity exists")
	_assert("locked" not in selected, "locked pure candidate excluded")
	_test_skill_selection()

func _test_skill_selection() -> void:
	var candidates: Array = []
	for category in ["advisory", "operations", "response"]:
		for index in 6:
			candidates.append({"id":"skill-%s-%d" % [category,index],"case_id":"skill-%s-%d" % [category,index],"category":category,"chapter":index,"required_rank":1 + (index / 2),"work_family":"family-%d" % (index % 3),"unlocked":index != 5})
	candidates.append({"id":"locked-priority","case_id":"locked-priority","category":"advisory","required_rank":1,"unlocked":false})
	var skills := {"advisory":2,"operations":1,"response":3}
	var priorities := ["skill-advisory-2","skill-operations-1","skill-response-2","locked-priority"]
	var selected: Array = MARKET.select_by_category(candidates, 6, [], [], skills, priorities)
	_assert("locked-priority" not in selected, "skill priority locked candidate excluded")
	_assert("skill-advisory-2" in selected and "skill-operations-1" in selected and "skill-response-2" in selected, "one newly unlocked priority per category promoted")
	_assert(MARKET.select_by_category(candidates, 6, [], [], skills, priorities) == selected, "skill selection deterministic")
	var existing := ["skill-advisory-0", "skill-response-0"]
	var retained: Array = MARKET.select_by_category(candidates, 6, [], existing, skills, [])
	_assert("skill-advisory-0" in retained and "skill-response-0" in retained, "existing leads retained")
	var recent := ["skill-advisory-1"]
	var without_recent: Array = MARKET.select_by_category(candidates, 6, recent, [], skills, [])
	_assert("skill-advisory-1" not in without_recent, "recent lead avoided when alternatives exist")
	_assert(without_recent.size() == without_recent.duplicate().size(), "skill selection IDs unique")
	for category in ["advisory", "operations", "response"]:
		_assert(without_recent.any(func(id): return str(id).begins_with("skill-" + category)), "skill selection keeps category populated " + category)
	var family_candidates: Array = [
		{"id":"family-a-1","case_id":"family-a-1","category":"advisory","work_family":"family-a","required_rank":1,"unlocked":true},
		{"id":"family-a-2","case_id":"family-a-2","category":"advisory","work_family":"family-a","required_rank":1,"unlocked":true},
		{"id":"family-b-1","case_id":"family-b-1","category":"advisory","work_family":"family-b","required_rank":1,"unlocked":true}
	]
	var family_selected: Array = MARKET.select_by_category(family_candidates, 6)
	var family_only: Array = family_selected.filter(func(id): return str(id).begins_with("family-"))
	_assert(family_only.size() == 2 and family_only.any(func(id): return str(id).begins_with("family-a-")) and family_only.any(func(id): return str(id).begins_with("family-b-")), "remaining slot diversifies work family")

func _category_counts_are_bounded(game: Node) -> bool:
	var counts: Dictionary = {}
	for offer in game.state.offers:
		if bool(offer.get("market_available", false)):
			var category := str(offer.get("category", "")); counts[category] = int(counts.get(category, 0)) + 1
	for category_index in 3:
		var category: String = ["advisory","operations","response"][category_index]; var unlocked: int = 0
		for offer in game.state.offers:
			if bool(offer.get("unlocked", false)) and str(offer.get("category", "")) == category: unlocked += 1
		var expected: int = mini(unlocked, [2,3,4][MARKET.phase(int(game.state.day), category_index)])
		if int(counts.get(category, 0)) != expected: return false
	return true

func _find_unrequested(game: Node) -> Dictionary:
	for offer in game.state.offers:
		if bool(offer.get("unlocked", false)) and not bool(offer.get("market_available", false)): return offer
	return {}

func _find_lead(game: Node) -> Dictionary:
	for offer in game.state.offers:
		if bool(offer.get("market_available", false)): return offer
	return {}

func _same_ids(left: Array, right: Array) -> bool:
	var a := left.duplicate(); var b := right.duplicate(); a.sort(); b.sort(); return a == b

func _test_ren_guards(qa_id: String) -> void:
	var game: Node = await _new_game("ren-"+qa_id)
	game.set_process(false); _assert(game.choose_strategy("advisory") and game.start_free_career(), "ren fixture career")
	game.state.skills.advisory = 10; game.state.skills.operations = 10; game.state.skills.response = 10; game.state.profit = 1000000; game._update_growth()
	var samba: Dictionary = {}; var backup: Dictionary = {}
	for day_index in 31:
		samba = {}; backup = {}
		game.state.day = day_index + 1; game._make_offers()
		for offer in game.state.offers:
			if not bool(offer.get("market_available", false)): continue
			if str(offer.get("case_id", "")) == "service-0-case-0": samba = offer
			if str(offer.get("case_id", "")).begins_with("service-1-"): backup = offer
		if not samba.is_empty() and not backup.is_empty(): break
	_assert(not samba.is_empty() and not backup.is_empty(), "ren fixture backup and samba leads")
	if samba.is_empty() or backup.is_empty(): return
	if not (game.set_offer_quote(str(backup.id), int(backup.reward)) and game.choose_contract(str(backup.id))):
		_assert(false, "accept backup"); return
	if not (game.set_offer_quote(str(samba.id), int(samba.reward)) and game.choose_contract(str(samba.id))):
		_assert(false, "accept samba"); return
	var backup_id := str(backup.id); var samba_id := str(samba.id)
	var ren_backup: Dictionary = game.operations_quote("ren", backup_id, 0); _assert(bool(ren_backup.get("ok", false)), "Ren supports backup target")
	var ren_samba: Dictionary = game.operations_quote("ren", samba_id, 0); _assert(not bool(ren_samba.get("ok", false)), "Ren rejects Samba target"); _assert(not str(ren_samba.get("reason", "")).is_empty(), "Ren rejection has localized reason")
	var before: Dictionary = game.state.duplicate(true); var before_assignments: Dictionary = game._assignments.duplicate(true)
	_assert(not game.operations_assign("ren", samba_id, 0), "normal Ren assignment rejected")
	game.assign_colleague("ren")
	_assert(game.state == before and game._assignments == before_assignments, "Ren guard leaves state unchanged")
	_assert(game.operations_assign("ren", backup_id, 0), "Ren assigned to background backup")
	_assert(str(game.state.current_contract_id) == samba_id and str(game._assignments.get("ren", {}).get("contract_id", "")) == backup_id, "background assignment preserves player contract")

func _quotes_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.keys() != expected.keys(): return false
	for offer_id in expected.keys():
		if not actual.get(offer_id, {}).keys() == expected[offer_id].keys(): return false
		for plan in expected[offer_id].keys():
			if int(actual[offer_id][plan]) != int(expected[offer_id][plan]): return false
	return true

func _new_game(label: String, path: String = "") -> Node:
	var game: Node = load("res://scripts/game.gd").new(); root.add_child(game); await process_frame
	var base := path if not path.is_empty() else "user://qa-market-"+label+".json"
	game.save_path = base; game.backup_path = base+".bak"; game.previous_path = base+".previous"; game.settings_path = base+".settings"; game._reset_state()
	return game

func _assert(condition: bool, label: String) -> void:
	if not condition: failures.append(label)
