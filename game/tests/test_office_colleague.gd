extends SceneTree

var failures: Array[String] = []
var actor: Node3D
var colleague: OfficeColleague

func _assert(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	actor=Node3D.new(); root.add_child(actor)
	colleague=preload("res://scripts/office_colleague.gd").new(); root.add_child(colleague)
	colleague.configure(actor,{"seat":Vector3(0,0,0),"break":Vector3(-2,0,0),"break_path":[Vector3(0,0,1),Vector3(-2,0,1),Vector3(-2,0,0)],"return_path":[Vector3(-2,0,1),Vector3(0,0,1),Vector3(0,0,0)],"coffee":Vector3(-2,0,0)},540.0)
	_assert(colleague.is_at_workstation(),"starts at workstation")
	_assert(colleague.request_break(),"break requested")
	for _i in 20: colleague.tick(0.2)
	_assert(colleague.phase == colleague.PHASE_BREAKWALK or colleague.phase == colleague.PHASE_GETCOFFEE,"outward path is active")
	var away_position:=colleague.global_position
	colleague.set_assignment({"status":"working","phase":"queued"})
	_assert(not colleague.can_progress_work(),"away assignment is deferred")
	var paused_position:=colleague.global_position; colleague.set_paused(true); colleague.tick(0.2); _assert(colleague.global_position.is_equal_approx(paused_position),"pause freezes position"); colleague.set_paused(false)
	for _i in 240: colleague.tick(0.2)
	colleague.tick(0.2)
	_assert(colleague.phase == colleague.PHASE_SIT,"reverse return reaches seat")
	_assert(colleague.can_progress_work(),"deferred work starts after return")
	colleague.request_break(); _assert(colleague.phase == colleague.PHASE_SIT,"working blocks break")
	var timer_phase:=colleague.phase; colleague.set_paused(true); colleague.tick(1.0); _assert(colleague.phase == timer_phase,"pause freezes timer/phase"); colleague.set_paused(false)
	var game:=get_root().get_node_or_null("Game")
	if game and game.has_method("set_colleague_runtime_availability"):
		game.set_colleague_runtime_availability("aya",false)
		_assert(not bool(game.colleague_runtime_availability("aya").available),"Game runtime availability false propagates")
		game.set_colleague_runtime_availability("aya",true)
	var collider := StaticBody3D.new(); actor.add_child(collider)
	colleague.set_assignment({"status":"done"})
	var entry := Vector3(2,0,2)
	colleague.waypoints.arrival_path=[entry,Vector3(2,0,1),Vector3(0,0,1),Vector3.ZERO]
	colleague.waypoints.departure_path=[Vector3(0,0,1),Vector3(2,0,1),entry]
	colleague.begin_departure(entry)
	for _i in 80: colleague.tick(0.2)
	_assert(colleague.is_departed() and not actor.visible and actor.global_position.is_equal_approx(entry) and collider.collision_layer==0,"departure follows every corridor point and disables collision")
	for _i in 20: colleague.tick(0.2)
	_assert(actor.global_position.is_equal_approx(entry),"departed actor stays at doorway")
	colleague.reset_staff_day(540.0,entry)
	_assert(colleague.is_departed() and is_equal_approx(colleague.break_due_minute,630.0),"new day resets schedule and holds actor outside")
	colleague.begin_arrival(entry)
	for _i in 80: colleague.tick(0.2,540.0)
	_assert(colleague.is_at_workstation() and actor.visible and collider.collision_layer==1 and actor.global_position.is_equal_approx(Vector3.ZERO),"new day arrival returns visibly along corridor")
	colleague.begin_departure(entry); colleague.tick(0.2)
	colleague.set_assignment({"status":"working"})
	for _i in 80: colleague.tick(0.2,540.0)
	_assert(colleague.can_progress_work() and not colleague.departing and actor.global_position.is_equal_approx(Vector3.ZERO),"reassignment during departure returns without stuck work")
	print("OFFICE_COLLEAGUE failures=",failures.size())
	for failure in failures: print("FAIL: ",failure)
	quit(1 if not failures.is_empty() else 0)
