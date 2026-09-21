extends SceneTree

var game
var failures: Array[String] = []
var qa_id := "professional-contracts-" + str(OS.get_process_id())
var professional_ids := ["firm-permission-review","firm-remote-hardening","firm-continuity","firm-recovery-drill","firm-account-containment","firm-major-containment","firm-partner-rollout","firm-clean-recovery","firm-leak-response"]

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("professional contracts timeout"); quit(2))
	call_deferred("run")

func _assert(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("FAIL ", label)

func _new_game(label: String) -> Node:
	var node: Node = load("res://scripts/game.gd").new()
	root.add_child(node)
	await process_frame
	var path := "user://qa-" + qa_id + "-" + label + ".json"
	node.save_path = path; node.backup_path = path + ".bak"; node.previous_path = path + ".previous"; node.settings_path = path + ".settings"
	node.set_process(false); node._reset_state()
	return node

func _prepare_career(node: Node) -> bool:
	return bool(node.choose_strategy("advisory") and node.start_free_career())

func _same_contract_conditions(left: Dictionary, right: Dictionary) -> bool:
	for key in ["id","case_id","client","title"]:
		if str(left.get(key, "")) != str(right.get(key, "")): return false
	for key in ["payment_days","agreed_fee","agreed_bonus","targets"]:
		if int(left.get(key, 0)) != int(right.get(key, 0)): return false
	return true

func _offer(node: Node, case_id: String, max_days: int = 45) -> Dictionary:
	for day in max_days:
		node.state.day = day + 1
		# Retired definitions remain testable as already-issued legacy leads.
		if case_id.begins_with("firm-"):
			node.state.market_leads = [case_id]
			node.state.market_day = int(node.state.day)
		node._make_offers()
		for candidate in node.state.offers:
			if str(candidate.get("case_id", "")) == case_id and bool(candidate.get("unlocked", false)) and bool(candidate.get("market_available", false)):
				return candidate
	return {}

func _configure_target(node: Node, target_index: int) -> bool:
	_assert(node.select_target(target_index), "select professional target %d" % target_index)
	var connected := str(node.vm_run("ssh client"))
	if not bool(node.vm_info().get("connected", false)):
		_assert(false, "professional target connection %d: %s" % [target_index, connected]); return false
	var scenario: Dictionary = node._scenario()
	var desired: Dictionary = scenario.get("desired", {}) if scenario.get("desired", {}) is Dictionary else {}
	if not desired.is_empty():
		_assert(bool(node.vm_write(str(node.vm_info().get("config_path", "")), node._vm().configuration_text(desired))), "professional target config %d" % target_index)
	var service := str(node.vm_info().get("service", ""))
	if not service.is_empty(): node.vm_run("systemctl restart " + service)
	var chapter := int(scenario.get("chapter", node.state.get("chapter", 0)))
	if chapter == 1:
		var repository := str(desired.get("repository", "local"))
		if str(scenario.get("seed_snapshot_repository", "")) != repository: node.vm_run("restic backup /srv/data")
		var restore_command := "restic restore 00000001 --target /restore" if scenario.has("latest_snapshot_overrides") else "restic restore latest --target /restore"
		var restore_result := str(node.vm_run(restore_command))
		if restore_result.begins_with("restic:"): restore_result = str(node.vm_run("restic -r " + repository + " " + restore_command.trim_prefix("restic ")))
		_assert(not restore_result.begins_with("restic:") and not restore_result.is_empty(), "professional backup restore %d" % target_index)
	if chapter == 4:
		if bool(scenario.get("edr_recovery_required", false)):
			var collected: Variant = JSON.parse_string(str(node.vm_run("edr collect")))
			var quarantined: Variant = JSON.parse_string(str(node.vm_run("edr quarantine pc_a pc_a-sync")))
			_assert(collected is Dictionary and bool(collected.get("ok", false)), "professional endpoint evidence %d" % target_index)
			_assert(quarantined is Dictionary and bool(quarantined.get("ok", false)), "professional endpoint quarantine %d" % target_index)
			node.vm_run("edr scan pc_a"); node.vm_run("edr scan pc_b")
		else:
			_assert(not str(node.vm_run("cp /var/log/evidence.log /evidence/original.log")).begins_with("cp:"), "professional evidence preservation %d" % target_index)
	if chapter == 3:
		var auth: bool = load("res://tests/identity_test_support.gd").authenticate_current(node)
		_assert(bool(auth), "professional identity authentication %d" % target_index)
	for attempt in 3:
		for probe in node.diagnostic_probes():
			var output := str(node.run_diagnostic(str(probe.get("id", ""))))
			if output.is_empty(): _assert(false, "professional probe output empty %s command=%s" % [str(probe.get("id", "")),str(probe.get("command", ""))])
		if node.diagnostic_probes().all(func(probe): return bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))): break
	for probe in node.diagnostic_probes():
		if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
			_assert(false, "professional failed probe %s command=%s result=%s expectation=%s" % [str(probe.get("id", "")),str(probe.get("command", "")),str(probe.get("result", "")),str(probe.get("expectation", ""))])
	var checks: Array = node.verify()
	_assert(not checks.is_empty() and checks.all(func(item): return bool(item.get("passed", false))), "professional target verifies %d" % target_index)
	return checks.all(func(item): return bool(item.get("passed", false)))

func _gate_profiles() -> void:
	var node: Node = await _new_game("gates")
	_assert(_prepare_career(node), "gate career setup")
	node.state.peak_profit = 1000000; node.state.credit = 10000
	node.state.skills = {"advisory":0,"operations":0,"response":0}; node._make_offers()
	var locked: Array = node.state.offers.filter(func(item): return str(item.get("case_id", "")) == "firm-permission-review")
	_assert(not locked.is_empty() and not bool(locked[0].get("unlocked", false)), "advisory gate isolates untrained profile")
	node.state.skills.advisory = 2; node.state.skills.operations = 0; node.state.skills.response = 0; node._make_offers()
	locked = node.state.offers.filter(func(item): return str(item.get("case_id", "")) == "firm-permission-review")
	_assert(not locked.is_empty() and bool(locked[0].get("unlocked", false)) and not bool(locked[0].get("market_available", false)), "retired permission review stays out of new market")
	node.state.skills = {"advisory":2,"operations":0,"response":0}; node._make_offers()
	var cross: Array = node.state.offers.filter(func(item): return str(item.get("case_id", "")) == "firm-partner-rollout")
	_assert(not cross.is_empty() and not bool(cross[0].get("unlocked", false)), "cross-skill case remains locked without operations")
	node.state.skills.operations = 1; node._make_offers()
	cross = node.state.offers.filter(func(item): return str(item.get("case_id", "")) == "firm-partner-rollout")
	_assert(not cross.is_empty() and bool(cross[0].get("unlocked", false)) and not bool(cross[0].get("market_available", false)), "retired cross-skill case stays out of new market")
	# learn_skill uses the normal persisted state and should expose a newly met case
	# while preserving same-day leads and their quote decisions.
	node.state.skills = {"advisory":2,"operations":0,"response":0}; node.state.credit = 100000; node.state.peak_profit = 10000000; node._make_offers()
	var old_leads: Array = node.state.market_leads.duplicate()
	var old_quote_id: String = str(old_leads[0]) if not old_leads.is_empty() else ""
	var old_offer: Dictionary = {}
	for item in node.state.offers:
		if str(item.get("case_id", "")) == old_quote_id: old_offer = item; break
	if not old_offer.is_empty(): _assert(node.set_offer_quote(str(old_offer.get("id", "")), int(old_offer.get("reward", 0))), "existing lead quote before skill")
	var quotes_before: Dictionary = node.state.offer_quotes.duplicate(true)
	_assert(node.learn_skill("operations"), "learn operations skill through public API")
	var newly_unlocked: Array = node.state.offers.filter(func(item): return bool(item.get("unlocked", false)) and str(item.get("case_id", "")) == "firm-partner-rollout")
	_assert(not newly_unlocked.is_empty() and not bool(newly_unlocked[0].get("market_available", false)), "skill investment keeps retired case out of new market")
	for lead in old_leads: _assert(lead in node.state.market_leads, "skill investment preserves existing lead " + str(lead))
	_assert(node.state.offer_quotes == quotes_before, "skill investment preserves quote decisions")
	node.state.skills = {"advisory":1,"operations":0,"response":0}; node._make_offers()
	var before: Array = node.skill_case_unlocks("advisory")
	_assert(node.learn_skill("advisory"), "learn advisory skill through public API")
	newly_unlocked = node.state.offers.filter(func(item): return bool(item.get("unlocked", false)) and str(item.get("case_id", "")) == "firm-permission-review")
	_assert(str(CaseCatalog.by_id("firm-permission-review").get("title", "")) not in before and not newly_unlocked.is_empty(), "retired case excluded from skill unlock hints")
	_assert(node.save_game() and node.load_game(), "skill profile save load")

func run() -> void:
	await _gate_profiles()
	var delivered := 0
	for case_id in professional_ids:
		game = await _new_game("case-" + case_id)
		_assert(_prepare_career(game), "professional career setup " + case_id)
		game.state.skills = {"advisory":10,"operations":10,"response":10}; game.state.peak_profit = 1000000; game.state.credit = 1000000; game._update_growth()
		var offer := _offer(game, case_id)
		_assert(not offer.is_empty(), "professional offer available " + case_id)
		if offer.is_empty(): continue
		_assert(bool(offer.get("market_available", false)), "professional offer is market lead " + case_id)
		var offer_id := str(offer.get("id", ""))
		_assert(game.set_offer_quote(offer_id, int(offer.get("reward", offer.get("base_reward", 0)))) and game.choose_contract(offer_id), "professional accepted " + case_id)
		if not bool(game.state.accepted): continue
		var accepted_snapshot: Dictionary = game.state.contract.duplicate(true)
		_assert(game.save_game() and game.load_game(), "accepted contract persists " + case_id)
		_assert(_same_contract_conditions(game.state.contract, accepted_snapshot), "accepted conditions stable " + case_id)
		var solved := true
		for target_index in game.state.targets.size():
			if not _configure_target(game, target_index): solved = false
		_assert(solved and game.can_deliver(), "professional can deliver " + case_id)
		if solved and game.can_deliver() and game.deliver(): delivered += 1
		else: _assert(false, "professional delivery " + case_id)
	_assert(delivered == professional_ids.size(), "all nine professional contracts delivered")
	_finish()

func _finish() -> void:
	if failures.is_empty(): print("PROFESSIONAL_CONTRACTS_PASS")
	else:
		for failure in failures: push_error("PROFESSIONAL_CONTRACTS: " + failure)
		print("PROFESSIONAL_CONTRACTS_FAIL count=", failures.size())
	quit(0 if failures.is_empty() else 1)
