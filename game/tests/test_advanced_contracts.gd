extends SceneTree

const GAME = preload("res://scripts/game.gd")
const ASSURANCE_TEST = preload("res://tests/test_advanced_assurance.gd")
var failures: Array[String] = []
var serial := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("FAIL ", label)

func _new_game(case_id: String) -> Node:
	serial += 1
	var g: Node = GAME.new()
	root.add_child(g)
	var stem := "user://advanced-contracts-%s-%d" % [str(OS.get_process_id()), serial]
	g.save_path = stem + ".json"
	g.backup_path = stem + ".bak"
	g.previous_path = stem + ".previous.json"
	g.settings_path = stem + ".settings.json"
	g._reset_state()
	var offer := CaseCatalog.by_id(case_id)
	var category := str(offer.get("category", "response"))
	check(g.choose_strategy(category), case_id + " strategy")
	check(g.start_free_career(), case_id + " career")
	g.state.skills = {"advisory":10,"operations":10,"response":10}
	g.state.peak_profit = 1000000000
	g.state.credit = 1000000
	g.state.market_leads = [case_id]
	g.state.market_day = int(g.state.day)
	g._make_offers()
	for fresh_offer in g.state.offers:
		var definition: Dictionary = CaseCatalog.by_id(str(fresh_offer.get("case_id", "")))
		if bool(fresh_offer.get("market_available", false)):
			check(not bool(definition.get("retired_from_new_offers", false)), case_id + " retired offer filtered")
	var selected := ""
	var selected_offer: Dictionary = {}
	for item in g.state.offers:
		if str(item.get("case_id", "")) == case_id:
			item.market_available = true
			selected = str(item.id)
			selected_offer = item
			break
	check(not selected.is_empty(), case_id + " offer")
	if selected_offer.is_empty(): return g
	check(g.set_offer_quote(selected, int(g.contract_quote(selected_offer).estimated_fee)), case_id + " quote")
	check(g.choose_contract(selected), case_id + " accept")
	return g

func _step(g: Node, step: Array, case_id: String) -> Dictionary:
	var action := str(step[0])
	var args: Dictionary = {}
	if step.size()>1 and step[1] is Dictionary: args=step[1].duplicate(true)
	elif step.size() > 1 and not str(step[1]).is_empty(): args.target = str(step[1])
	if action == "set_source" and step.size() > 2 and not str(step[2]).is_empty(): args.enabled = str(step[2]) in ["on", "true", "enabled"]
	elif step.size() > 2 and not str(step[2]).is_empty(): args.option = str(step[2])
	var result: Dictionary = g.advanced_action(action, args)
	check(bool(result.get("changed", false)), case_id + " action " + action)
	return result

func _steps(case_id: String) -> Array:
	match case_id:
		"advanced-hunt": return [["correlate",{"event_ids":["evt-00","evt-01"]}],["correlate",{"event_ids":["evt-04","evt-05","evt-06"]}],["pin_event","evt-05"],["pin_event","evt-06"],["pin_event","CHG-114"],["isolate_host","gw01"],["probe_business"],["reconnect_host","gw01"],["probe_security"],["isolate_host","ws17"],["revoke_session","sid-r44"],["disable_task","task-sync"],["probe_security"],["reconnect_host","ws17"],["probe_security"],["probe_business"]]
		"advanced-recovery": return [["inspect_snapshot","snap-1410"],["stage_restore"],["scan_stage"],["isolate_network"],["inspect_snapshot","snap-0730"],["stage_restore"],["scan_stage"],["rotate_identity",{"account":"restore-operator"}],["revoke_session","sid-sync-17"],["start_service","identity"],["start_service","database"],["start_service","app"],["probe_business"],["restore_business"],["reconnect_business"]]
		# Pin the actual audit record for the affected grant; app-72 is only
		# the control target and is not an evidence record ID.
		"advanced-cloud": return [["disable_grant","app-72"],["revoke_app_session","app-72"],["probe_request","app-19"],["probe_request","app-72"],["pin","audit-2"],["verify"]]
		"advanced-malware": return [["run_scan"],["compare_normal"],["set_network","","on"],["run_live_probe"],["derive_indicators"],["hunt_indicators"],["quarantine_file","endpoint-a"],["quarantine","endpoint-a"],["quarantine_persistence"],["rescan"]]
		# Exercise the real source/rule controls as well as replay.
		"advanced-detection": return [["set_source","network","on"],["set_process","invoice_update.exe"],["set_threshold","2"],["set_exclusion","",""],["set_notification","","on"],["replay"],["verify"]]
		"advanced-ddos", "advanced-api", "advanced-supplychain": return ASSURANCE_TEST.solution(case_id)
	return []

func _run_case(case_id: String) -> void:
	var g := _new_game(case_id)
	check(int(g.mission().estimated_workload) >= 240, case_id + " workload shown")
	check(int(g.state.contract.estimated_budget) == int(CaseCatalog.by_id(case_id).advanced_work_minutes), case_id + " scoped deadline budget")
	check(not g.verify().all(func(row): return bool(row.get("passed",false))),case_id+" unobserved state fails verification")
	check(not g.can_deliver(),case_id+" unobserved state cannot deliver")
	if case_id=="advanced-pentest": _network_steps(g,case_id)
	else:
		for step in _steps(case_id): _step(g, step, case_id)
	var verified: Array = g.verify()
	check(verified.all(func(row: Dictionary): return bool(row.get("passed", false))), case_id + " verify")
	if case_id == "advanced-hunt": _transaction_edges(g, case_id)
	check(g.can_deliver(), case_id + " can deliver")
	check(g.deliver(), case_id + " deliver")
	check(not g.deliver(), case_id + " duplicate delivery rejected")

func _transaction_edges(g: Node, case_id: String) -> void:
	var before_advanced: Dictionary = g.state.advanced.duplicate(true)
	var before_revision := int(g.state.revision)
	var good_path: String = str(g.save_path)
	g.save_path = "user://missing-advanced-save-dir-%s/contract.json" % str(OS.get_process_id())
	var failed: Dictionary = g.advanced_action("probe_security")
	check(not bool(failed.get("ok", false)), case_id + " failed save rejected")
	check(g.state.advanced == before_advanced and int(g.state.revision) == before_revision, case_id + " failed save rollback")
	g.save_path = good_path
	_step(g, ["probe_security"], case_id)
	_step(g, ["probe_business"], case_id)
	var repaired: Array = g.verify()
	check(repaired.all(func(row: Dictionary): return bool(row.get("passed", false))), case_id + " reverify after rollback")
	var original_id := str(g.state.current_contract_id)
	var other_id := ""
	for offer in g.state.offers:
		if str(offer.get("id", "")) != original_id and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)):
			other_id = str(offer.id); break
	if not other_id.is_empty():
		check(g.choose_contract(other_id), case_id + " second context")
		check(g.switch_contract(original_id), case_id + " switch back")
		check(str(g.state.contract.get("case_id", "")) == case_id and not g.state.advanced.is_empty(), case_id + " advanced context preserved")
	check(g.save_game(), case_id + " save before reload")
	var resumed: Node = GAME.new()
	root.add_child(resumed)
	resumed.save_path = good_path
	resumed.backup_path = g.backup_path
	resumed.previous_path = g.previous_path
	resumed.settings_path = g.settings_path
	check(resumed.load_game(), case_id + " reload")
	check(str(resumed.state.contract.get("case_id", "")) == case_id and not resumed.state.advanced.is_empty(), case_id + " advanced state reload")

func _network_steps(g: Node,case_id: String) -> void:
	_step(g,["browse",{"path":"share01"}],case_id)
	var leak: Dictionary=_step(g,["read",{"path":"share01/deploy.env"}],case_id).data.record
	var token: String=str(leak.data.bytes).split("TOKEN=")[1].strip_edges()
	_step(g,["authenticate",{"username":"svc-report","credential":token}],case_id)
	var proof: Dictionary=_step(g,["read",{"path":"evidence/proof.csv"}],case_id).data.record
	_step(g,["submit_finding",{"evidence_ids":[leak.id,proof.id]}],case_id)
	_step(g,["customer_fix"],case_id); _step(g,["reset_session"],case_id)
	var denied: Dictionary=_step(g,["read",{"path":"share01/deploy.env"}],case_id)
	check(int(denied.data.record.status)==403,case_id+" same employee operation denied")
	var normal: Dictionary=_step(g,["read",{"path":"share01/daily.csv"}],case_id)
	check(int(normal.data.record.status)==200,case_id+" normal employee work retained")

func run() -> void:
	check("--qa-profile=advanced-contracts" in OS.get_cmdline_user_args(), "QA profile guard")
	check(CaseCatalog.by_id("firm-clean-recovery").has("id"), "retired definition preserved")
	check(CaseCatalog.by_id("service-0-case-3").has("id"), "retired source preserved")
	for case_id in ["advanced-hunt","advanced-pentest","advanced-recovery","advanced-ddos","advanced-api","advanced-supplychain","advanced-cloud","advanced-malware","advanced-detection"]:
		_run_case(case_id)
	if failures.is_empty(): print("ADVANCED_CONTRACTS_PASS")
	else: print("ADVANCED_CONTRACTS_FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
