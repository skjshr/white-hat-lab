extends SceneTree

var failures: Array[String] = []

func _assert(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run_frames(count: int) -> void:
	for _i in count: await process_frame

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var game:=preload("res://scripts/game.gd").new()
	root.add_child(game)
	game.save_path="user://qa-colleague-work-gate.json"
	game.backup_path=game.save_path+".bak"
	game.previous_path=game.save_path+".previous"
	game.settings_path="user://qa-colleague-work-gate-settings.json"
	_assert("qa-" in game.save_path or "colleague-work-gate" in game.save_path,"dedicated QA save path")
	_assert(game.new_game({"company":"同僚進行ゲートテスト"}),"new game")
	_assert(game.choose_strategy("advisory") and game.accept_mission(),"mission accepted")
	game.assign_colleague("aya")
	var before: Dictionary=game.state.assignments.get("aya",{}).duplicate(true)
	_assert(str(before.get("status","")) == "working","assignment started")
	game.set_colleague_runtime_availability("aya",false)
	await _run_frames(30)
	var away: Dictionary=game.state.assignments.get("aya",{})
	_assert(is_equal_approx(float(away.get("remaining",-1)),float(before.get("remaining",-2))),"remaining frozen while NPC is away")
	game.set_colleague_runtime_availability("aya",true)
	await _run_frames(30)
	var returned: Dictionary=game.state.assignments.get("aya",{})
	_assert(float(returned.get("remaining",999)) < float(away.get("remaining",-1)),"remaining decreases after return")
	game.set_office_clock_paused(true)
	var paused_before: float=float(returned.get("remaining",-1))
	await _run_frames(30)
	var paused_after: float=float(game.state.assignments.get("aya",{}).get("remaining",-2))
	_assert(is_equal_approx(paused_before,paused_after),"Game work freezes during pause")
	game.set_office_clock_paused(false)
	print("COLLEAGUE_WORK_GATE failures=",failures.size()," save_path=",game.save_path)
	for failure in failures: print("FAIL: ",failure)
	quit(1 if not failures.is_empty() else 0)
