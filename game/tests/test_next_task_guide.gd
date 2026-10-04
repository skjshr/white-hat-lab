extends SceneTree

const GAME = preload("res://scripts/game.gd")
const GUIDE = preload("res://scripts/next_task_guide.gd")
const ADVANCED_IDS := ["advanced-hunt", "advanced-pentest", "advanced-recovery", "advanced-ddos", "advanced-api", "advanced-supplychain", "advanced-cloud", "advanced-malware", "advanced-detection"]
var failures: Array[String] = []
var serial := 0

class FakeMultiTarget:
	class FakeMachine:
		var state: Dictionary = {"dirty":false,"active":true,"error":""}
	var state: Dictionary
	func _init() -> void:
		state = {"strategy":"advisory","career_mode":true,"awaiting_contract":false,"accepted":true,"inspected":true,"revision":2,"validated_revision":2,"checks":[{"passed":true}],"baseline_recorded":true,"target_index":1,"targets":[{"name":"site-a","inspected":false,"revision":0,"validated_revision":-1,"checks":[]},{"name":"site-b","inspected":true,"revision":2,"validated_revision":2,"checks":[{"passed":true}]}]}
	func current_done() -> bool: return false
	func advanced_active() -> bool: return false
	func vm_info() -> Dictionary: return {"connected":true}
	func case_review() -> Dictionary: return {"can_capture":false}
	func diagnostic_probes() -> Array: return [{"id":"probe","recorded":true,"fresh":true,"passed":true}]
	func _current_chapter() -> int: return 0
	func _customer_requirement() -> Dictionary: return {}
	func _customer_hardware() -> Dictionary: return {}
	func _vm() -> FakeMachine: return FakeMachine.new()

func _check(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _new_game(label: String) -> Game:
	serial += 1
	var game := GAME.new()
	root.add_child(game)
	var stem := "user://next-task-guide-%s-%d" % [label, serial]
	game.save_path = stem + ".json"
	game.backup_path = stem + ".bak"
	game.previous_path = stem + ".previous"
	game.settings_path = stem + ".settings"
	game.new_game()
	return game

func _accept_story(chapter: int, label: String) -> Game:
	var game := _new_game(label)
	_check(game.choose_strategy("advisory"), label + " strategy")
	game.state.chapter = chapter
	game.state.credit = 999999
	game.state.completed_ids = ["share", "backup", "network", "account", "incident"].slice(0, chapter)
	_check(game.accept_mission(), label + " accept")
	return game

func _snapshot_is_stable(game, label: String) -> void:
	var before: Dictionary = game.state.duplicate(true)
	GUIDE.resolve(game)
	_check(game.state == before, label + " resolver is read-only")

func _connection_routes() -> void:
	for chapter in 6:
		var game := _accept_story(chapter, "chapter-%d" % chapter)
		var result: Dictionary = GUIDE.resolve(game)
		var expected_route := "browser" if chapter == 0 else "terminal"
		_check(result.id == "connect", "chapter %d connect action" % chapter)
		_check(str(result.route) == expected_route, "chapter %d connection route" % chapter)
		if chapter == 0: _check(str(result.get("url", "")).contains("files01.client.test"), "chapter 0 real URL")
		_snapshot_is_stable(game, "chapter %d" % chapter)

func _diagnostic_and_delivery() -> void:
	var game := _accept_story(0, "delivery")
	_check(str(GUIDE.resolve(game).id) == "connect", "delivery starts at connection")
	game.vm_run("ssh client")
	var probes: Array = game.diagnostic_probes()
	_check(not probes.is_empty(), "delivery has probes")
	if probes.is_empty(): return
	game.run_diagnostic("staff-write")
	var failed: Dictionary = GUIDE.resolve(game)
	_check(failed.id == "fix", "failed probe asks for remediation")
	_check(str(failed.hint).is_empty() or not str(failed.hint).contains(str(probes[0].id)), "failed hint does not expose internal probe id")
	var machine = game._vm()
	var desired: Dictionary = machine._legacy_desired()
	_check(game.vm_write(game.vm_info().config_path, machine._config_text(desired)), "write desired configuration")
	_check(not game.vm_run("systemctl restart " + game.vm_info().service).begins_with("Job failed"), "apply desired configuration")
	for _pass in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))): game.run_diagnostic(str(probe.id))
	var verified: Array = game.verify()
	_check(verified.all(func(row): return bool(row.get("passed", false))), "fresh verification passes")
	_check(game.can_deliver(), "verified job can deliver")
	var ready: Dictionary = GUIDE.resolve(game)
	_check(ready.id == "deliver", "verified job guides delivery")
	_check(game.deliver(), "delivery executes once")

func _multi_target_wraparound() -> void:
	var fake := FakeMultiTarget.new()
	var result: Dictionary = GUIDE.resolve(fake)
	_check(str(result.get("id", "")) == "site", "multi-target selects remaining site")
	_check(int(result.get("target_index", -1)) == 0, "multi-target wraps to earlier site")
	_check(str(result.target) == "TargetSelectorSlot" and str(result.body).contains("site-a"), "multi-target returns real target name")
	_snapshot_is_stable(fake, "multi-target")

func _advanced_objectives() -> void:
	for case_id in ADVANCED_IDS:
		var game := _new_game(case_id)
		game.state.career_mode = true
		game.state.awaiting_contract = false
		game.state.accepted = true
		game.state.contract = {"case_id":case_id,"title":"case","brief":"brief"}
		game.state.advanced = game._advanced_engine(case_id).create(case_id)
		game.state.targets = [{"name":"environment","advanced":game.state.advanced.duplicate(true)}]
		var result: Dictionary = GUIDE.resolve(game)
		_check(result.route == "advanced", case_id + " advanced route")
		_check(str(result.target) in GUIDE.ADVANCED_WORK_TARGETS[case_id].values() or result.target == "AdvancedVerify", case_id + " specialist work target")
		_check(GUIDE.navigation_target(game,{"route":"advanced","target":"AdvancedVerify","open_navigation":true}).is_empty(),case_id+" navigation never executes Verify")
		_check(not str(result.body).is_empty(), case_id + " public objective text")
		for forbidden in ["gw01", "ws17", "app-72", "runner-session-19", "endpoint-a"]:
			_check(not str(result.body).contains(forbidden), case_id + " no hidden culprit " + forbidden)
		_snapshot_is_stable(game, case_id)

func _init() -> void:
	_connection_routes()
	_diagnostic_and_delivery()
	_multi_target_wraparound()
	_advanced_objectives()
	print("NEXT_TASK_GUIDE_PASS" if failures.is_empty() else "NEXT_TASK_GUIDE_FAIL %d" % failures.size())
	for failure in failures: print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
