extends SceneTree
## Controlled career/market fixtures; all response work and accounting use Game.
## Optional --legacy-fixture=PATH reads and copies an actual accepted save.
const IMPACT = preload("res://scripts/endpoint_engagement.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")
var game
var failures: Array[String] = []
var paths: Array[String] = []
var case_id := "service-4-case-1"

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("ENDPOINT_CONTAINMENT timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("ENDPOINT_CONTAINMENT: " + label)

func encoded(value: Variant) -> String:
	# JSON loads all numbers as floats; compare both sides after that same
	# serialization boundary without weakening values, strings or field checks.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func offer(id: String) -> Dictionary:
	for row in game.state.offers:
		if str(row.get("case_id", "")) == id: return row
	return {}

func set_paths(values: Array) -> void:
	game.save_path = str(values[0]); game.backup_path = str(values[1])
	game.previous_path = str(values[2]); game.settings_path = str(values[3])

func restore_checkpoint(checkpoint: Dictionary) -> void:
	game.state = checkpoint.duplicate(true)
	game._assignments = checkpoint.get("assignments", {}).duplicate(true)
	game._machine = null; game._machine_key = ""
	check(game.save_game(), "branch checkpoint saved to isolated QA profile")

func impact() -> Dictionary:
	return game.state.work.get("endpoint_impact", {}).duplicate(true)

func vm_files() -> Dictionary:
	var result := {}
	for key in game.state.get("vm_states", {}):
		result[str(key)] = game.state.vm_states[key].get("fs", {}).duplicate(true)
	return result

func legacy_roundtrip() -> void:
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--legacy-fixture="): source = argument.trim_prefix("--legacy-fixture=")
	if source.is_empty(): return
	check(FileAccess.file_exists(source), "accepted legacy fixture exists")
	if not FileAccess.file_exists(source): return
	var source_hash := FileAccess.get_sha256(source)
	check(DirAccess.copy_absolute(source, ProjectSettings.globalize_path(game.save_path)) == OK, "legacy fixture copied, never edited")
	check(game.load_game(), "accepted legacy fixture loads")
	if not game.state.get("accepted", false): check(false, "legacy fixture must contain an accepted contract"); return
	var legacy_targets := encoded(game.state.targets)
	var legacy_cost := int(game.state.work.get("incident_cost", 0))
	var legacy_desired := encoded(game._scenario().get("desired", {}))
	var legacy_files := encoded(vm_files())
	check(game.state.targets.all(func(item): return not item.has("scenario")), "legacy accepted targets have no new frozen scenario")
	check(game.save_game() and game.load_game(), "legacy accepted save roundtrip")
	check(encoded(game.state.targets) == legacy_targets and encoded(vm_files()) == legacy_files and encoded(game._scenario().get("desired", {})) == legacy_desired and int(game.state.work.get("incident_cost", 0)) == legacy_cost, "legacy roundtrip preserves targets, acceptance conditions, file bytes and costs")
	game.vm_run("cat /var/log/evidence.log")
	check(not game.state.work.has("endpoint_impact") and int(game.state.work.get("incident_cost", 0)) == legacy_cost, "legacy response work acquires no new compensation")
	check(FileAccess.get_sha256(source) == source_hash, "accepted legacy source hash unchanged")

func prepare() -> Dictionary:
	game._reset_state()
	check(game.choose_strategy("response") and game.start_free_career(), "controlled response career starts")
	game.state.peak_profit = 60000; game.state.skills.response = 2
	game.state.day += 1; game._make_offers()
	var old: Dictionary = offer(case_id)
	old.target_specs = []; old.brief = str(CATALOG.by_id(case_id).brief)
	var commercial := {}
	for field in ["targets", "reward", "base_reward", "estimated_budget", "deadline_text", "brief"]: commercial[field] = old[field]
	game._make_offers()
	var preserved := offer(case_id)
	check(preserved.target_specs.is_empty() and commercial.keys().all(func(field): return preserved[field] == commercial[field]), "same-day legacy offer keeps its original scope and terms")
	game.state.day += 1; game._make_offers()
	var fresh := offer(case_id)
	check(not fresh.target_specs.is_empty() and int(fresh.target_specs[0].scenario.get("endpoint_engagement", 0)) == 2, "new day's offer freezes containment version two")
	check(fresh.targets == commercial.targets and fresh.reward == commercial.reward and fresh.estimated_budget == commercial.estimated_budget, "authored scenario preserves original site count, reward and budget")
	var two_sites := offer("service-4-case-2")
	check(int(two_sites.targets) == 2 and two_sites.target_specs.size() == 2 and int(two_sites.estimated_budget) == 234, "multi-site ordinary offer keeps both priced sites")
	check(not CATALOG.by_id(case_id).has("endpoint_engagement"), "catalog fallback does not acquire new accepted-contract terms")
	fresh.market_available = true
	check(game.choose_contract(str(fresh.id)), "ordinary response offer accepted through Game")
	game.inspect_mission()
	check(str(game.vm_run("ssh client")).contains("Authenticated"), "accepted endpoint connected")
	check(not game._vm().state.has("edr_processes") and int(impact().get("0", {}).get("cost", 0)) > 0, "ordinary containment accrues before and after connection without invented processes")
	check(game.save_game(), "shared branch start saved")
	return game.state.duplicate(true)

func failed_save(command: String = "") -> void:
	var vm_before := encoded(game._vm().export_state())
	var before := encoded(game.state)
	var missing := "user://qa-endpoint-containment-missing-" + str(OS.get_process_id()) + "/missing/save.json"
	set_paths([missing, missing + ".bak", missing + ".previous", missing + ".settings"])
	if command == "baseline":
		check(not game.capture_baseline(), "baseline capture reports failed persistence")
	elif command.is_empty():
		check(game.verify().is_empty(), "verification reports failed persistence")
	else:
		var response = JSON.parse_string(str(game.vm_run(command)))
		check(response is Dictionary and int(response.get("code", 0)) == 507, "response action reports failed persistence")
	check(encoded(game.state) == before and encoded(game._vm().export_state()) == vm_before, "failed persistence restores files, policy, observations, compensation and clock")
	set_paths(paths)

func baseline_transaction(checkpoint: Dictionary) -> void:
	failed_save("baseline")
	var prior_cost := IMPACT.total_cost(impact())
	check(game.capture_baseline(), "baseline capture can be retried after save failure")
	check(game._target_has_baseline(game.state.targets[0], game._vm().export_state()) and IMPACT.total_cost(impact()) == prior_cost + 200, "baseline retry records both files and charges its two working minutes once")
	restore_checkpoint(checkpoint)

func two_site_release() -> void:
	var base: Dictionary = CATALOG.by_id("service-4-case-2").duplicate(true)
	base.erase("suspect")
	check(IMPACT.containment_specs(base, 2).all(func(item): return str(item.scenario.get("suspect", "")) == "pc_a"), "missing source uses the same frozen PC-A default as the endpoint VM")
	var selected := offer("service-4-case-2")
	selected.market_available = true
	check(game.choose_contract(str(selected.id)), "two-site containment correction accepted")
	if not game.state.get("accepted", false): return
	game.inspect_mission(); game.vm_run("ssh client")
	for index in 2:
		check(game.select_target(index), "select containment correction site " + str(index))
		game.vm_run("ssh client")
		check(str(game._scenario().get("suspect", "")) == "pc_a", "accepted site freezes its actual source")
		game.vm_run("edr release pc_a")
		var before := float(impact().get(str(index), {}).get("uncontained_minutes", 0))
		check(str(game.vm_run("curl https://edr.client.test/pc-a/outbound")).begins_with("HTTP/1.1 200"), "releasing source actually permits outbound at site " + str(index))
		check(float(impact()[str(index)].uncontained_minutes) == before + 3, "released source adds uncontained working time at site " + str(index))

func background_interruption(checkpoint: Dictionary) -> void:
	restore_checkpoint(checkpoint)
	var response_id := str(game.state.current_contract_id)
	check(game.dispatch_enqueue("aya", response_id, 0), "queue response investigation for a colleague")
	var queue: Array = game.state.dispatch_queues.get("aya", [])
	if queue.is_empty(): return
	var job_id := str(queue[0].id)
	check(game.dispatch_start("aya", job_id), "start real colleague response work")
	var duration := float(game._assignments.get("aya", {}).get("work_minutes", 0))
	var other := offer("service-4-case-0"); other.market_available = true
	check(game.choose_contract(str(other.id)), "switch to another accepted case while colleague works")
	var visible_id := str(game.state.current_contract_id)
	var visible_work := encoded(game.state.work)
	var machines_before := encoded(game.state.vm_states)
	var prior: Dictionary = game.state.contract_contexts[response_id].work.endpoint_impact.duplicate(true)
	game._process(1.0)
	check(game.dispatch_pause("aya"), "pause the inactive contract's partially completed work")
	var partial: Dictionary = game.state.contract_contexts[response_id].work.endpoint_impact
	check(IMPACT.total_cost(partial) == IMPACT.total_cost(prior) + 100, "inactive partial work accrues compensation before its accounted minutes are retired")
	check(str(game.state.current_contract_id) == visible_id and encoded(game.state.work) == visible_work and encoded(game.state.vm_states) == machines_before, "background impact does not switch the visible case or modify customer machines")
	check(game.dispatch_start("aya", job_id), "resume the same interrupted job")
	game._process(float(game._assignments.get("aya", {}).get("remaining", 0)) + 0.01)
	var completed: Dictionary = game.state.contract_contexts[response_id].work.endpoint_impact
	check(IMPACT.total_cost(completed) == IMPACT.total_cost(prior) + roundi(duration * IMPACT.UNCONTAINED_RATE) and str(game.state.current_contract_id) == visible_id, "job completion adds only remaining labor once and keeps the visible case")

func finish_case() -> Dictionary:
	game.vm_run("edr collect")
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	var verification: Array = game.verify()
	check(not verification.is_empty() and verification.all(func(item): return bool(item.get("passed", false))), "real response state and fresh observations satisfy delivery")
	check(game.can_deliver() and game.deliver(), "verified response delivered")
	return game.state.last_receipt.duplicate(true)

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-endpoint-containment-" + str(OS.get_process_id())
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths)
	legacy_roundtrip()
	var checkpoint := prepare()
	if not game.state.get("accepted", false): finish(); return
	baseline_transaction(checkpoint)
	game.vm_run("edr isolate pc_b")
	var efficient := finish_case()
	var efficient_applied := encoded(game._vm().state.applied)
	check(int(efficient.get("endpoint_satisfaction_delta", 99)) == 0, "correct containment does not penalize normal business")
	restore_checkpoint(checkpoint)
	game.vm_run("edr isolate pc_a")
	check(str(game.vm_run("curl https://edr.client.test/pc-a/business")).begins_with("HTTP/1.1 403"), "mistaken isolation interrupts the real business endpoint")
	var interrupted := impact()
	check(float(interrupted["0"].stop_minutes) > 0 and float(interrupted["0"].uncontained_minutes) > 0, "wrong target incurs both continued exposure and normal-business interruption")
	check(game.save_game() and game.load_game() and encoded(impact()) == encoded(interrupted), "interrupted response and compensation survive save/resume")
	var cancellation_checkpoint: Dictionary = game.state.duplicate(true)
	failed_save("edr isolate pc_b")
	game.vm_run("edr isolate pc_b")
	game.vm_run("edr release pc_a")
	check(str(game.vm_run("curl https://edr.client.test/pc-a/business")).begins_with("HTTP/1.1 200"), "retry restores the real business endpoint")
	failed_save()
	var costly := finish_case()
	check(encoded(game._vm().state.applied) == efficient_applied, "both approaches finish with the same accepted endpoint policy")
	check(int(costly.net) == int(efficient.net) - 1050 and int(costly.cost) == int(efficient.cost) + 1050, "six extra uncontained and nine stopped minutes persist as 1050 yen lower profit")
	check(int(costly.get("endpoint_satisfaction_delta", 0)) == -2 and int(costly.satisfaction_after) == int(efficient.satisfaction_after) - 2, "nine minutes of mistaken business interruption remain as two satisfaction points")
	check(str(costly.grade) == str(efficient.grade), "business penalty does not change the technical grade")
	check(int(game.state.history[-1].get("endpoint_satisfaction_delta", 0)) == -2 and encoded(game.state.history[-1].endpoint_impact) == encoded(costly.endpoint_impact), "delivery history retains business impact and its satisfaction component")
	check(game.save_game() and game.load_game() and int(game.state.last_receipt.get("endpoint_satisfaction_delta", 0)) == -2, "delivery's business consequence survives restart")
	check(IMPACT.satisfaction_delta({"legacy":{"send_minutes":0, "stop_minutes":120, "cost":6000}}) == 0 and IMPACT.satisfaction_delta({"new":{"uncontained_minutes":0, "stop_minutes":91}}) == -15, "satisfaction rule excludes recovery version one and caps ordinary penalties")
	restore_checkpoint(cancellation_checkpoint)
	var canceled_id := str(game.state.current_contract_id)
	var preview: Dictionary = game.contract_closeout_preview()
	var cash_before := int(game.state.cash)
	check(int(preview.costs) == 700 + IMPACT.total_cost(interrupted), "cancellation includes accrued compensation")
	check(game.cancel_current_contract(), "interrupted ordinary response can be closed out")
	check(int(game.state.cash) == cash_before - int(preview.costs) and encoded(game.state.contract_closeouts[canceled_id].context.work.endpoint_impact) == encoded(interrupted), "cancellation pays the cost and archives the interrupted impact")
	check(encoded(game.state.last_receipt.get("endpoint_impact", {})) == encoded(interrupted) and encoded(game.state.history[-1].get("endpoint_impact", {})) == encoded(interrupted), "cancellation result and history expose the archived business impact")
	two_site_release()
	background_interruption(checkpoint)
	finish()

func finish() -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("ENDPOINT_CONTAINMENT_TEST_PASS" if failures.is_empty() else "ENDPOINT_CONTAINMENT_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
