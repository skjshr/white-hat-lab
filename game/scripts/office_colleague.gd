extends Node3D
class_name OfficeColleague
## A self-contained office actor. The office owns placement and the game owns
## work state; this node only turns those two inputs into visible movement.

signal phase_changed(phase: String)

const PHASE_IDLEWORK := "idlework"
const PHASE_BREAKWALK := "breakwalk"
const PHASE_GETCOFFEE := "getcoffee"
const PHASE_DRINK := "drink"
const PHASE_RETURN := "return"
const PHASE_SIT := "sit"
const PHASE_DEPART := "depart"

@export var break_interval_minutes := 120.0
@export var break_duration_minutes := 20.0
@export var break_schedule_minutes: Array[float] = [630.0,720.0,900.0]
@export var walk_speed := 1.15
@export var drink_seconds := 8.0

var actor: Node3D
var waypoints: Dictionary = {}
var coffee_point := Vector3.ZERO
var seat_point := Vector3.ZERO
var work_point := Vector3.ZERO
var phase := PHASE_IDLEWORK
var paused := false
var assignment: Dictionary = {}
var pending_assignment: Dictionary = {}
var requested_break := false
var break_due_minute := 660.0
var break_started_minute := -1.0
var drink_elapsed := 0.0
var _last_game_minute := 540.0
var _using_clock := false
var _schedule_index := 0
var _route: Array[Vector3] = []
var _route_index := 0
var coffee_visual: Node3D
var coffee_holder: Node3D
var coffee_attachment: BoneAttachment3D
var _anim_player: AnimationPlayer
var seat_yaw := 0.0
var departing := false
var departed := false

func configure(value: Node3D, points: Dictionary, start_minute := 540.0) -> void:
	actor = value
	waypoints = points.duplicate(true)
	seat_point = Vector3(points.get("seat",Vector3.ZERO))
	work_point = Vector3(points.get("work",seat_point))
	coffee_point = Vector3(points.get("coffee",Vector3.ZERO))
	_last_game_minute = start_minute
	seat_yaw = float(points.get("seat_yaw",actor.rotation.y))
	_schedule_index = 0
	while _schedule_index < break_schedule_minutes.size() and break_schedule_minutes[_schedule_index] <= start_minute:
		_schedule_index += 1
	break_due_minute = break_schedule_minutes[_schedule_index] if _schedule_index < break_schedule_minutes.size() else start_minute + break_interval_minutes
	_find_animation_player()
	if _anim_player: _anim_player.active = true
	phase = ""
	_set_phase(PHASE_IDLEWORK)

func set_assignment(value: Dictionary) -> void:
	var incoming := value.duplicate(true)
	if str(incoming.get("status","")) != "working":
		assignment = incoming
		pending_assignment.clear()
		return
	# A request received while away is held without teleporting the actor to
	# the chair. Game work progression should use can_progress_work() until the
	# return transition reaches PHASE_SIT.
	if not is_at_workstation():
		pending_assignment = incoming
		if phase != PHASE_RETURN: _return_to_work()
		return
	assignment = incoming
	departing = false
	departed = false
	requested_break = false
	_set_phase(PHASE_SIT)

func update_workplace(points: Dictionary) -> void:
	waypoints = points.duplicate(true)
	seat_point = Vector3(points.get("seat", seat_point))
	work_point = Vector3(points.get("work", work_point))
	coffee_point = Vector3(points.get("coffee", coffee_point))
	seat_yaw = float(points.get("seat_yaw", seat_yaw))
	refresh_route()

func _has_route_provider() -> bool:
	var provider: Callable=waypoints.get("route_provider",Callable())
	return provider.is_valid()

func _load_route(target: Vector3) -> void:
	_route.clear();_route_index=0
	var provider: Callable=waypoints.get("route_provider",Callable())
	if provider.is_valid():
		var points: Array=provider.call(actor.global_position,target)
		for point in points:_route.append(Vector3(point))

func refresh_route() -> void:
	if departed or not actor or not _has_route_provider():return
	if phase==PHASE_RETURN:_load_route(seat_point)
	elif phase==PHASE_DEPART:_load_route(Vector3(waypoints.get("entry",actor.global_position)))
	elif phase in [PHASE_BREAKWALK,PHASE_GETCOFFEE]:_load_route(coffee_point)

func request_break() -> bool:
	requested_break = true
	if _is_working(): return false
	_begin_break()
	return true

func is_available_for_work() -> bool:
	return not paused and phase in [PHASE_IDLEWORK,PHASE_SIT] and not _is_working()

func is_at_workstation() -> bool:
	return not departing and not departed and (phase == PHASE_IDLEWORK or phase == PHASE_SIT)

func can_progress_work() -> bool:
	return not paused and is_at_workstation() and _is_working() and pending_assignment.is_empty()

func runtime_availability() -> Dictionary:
	return {"phase":phase,"at_workstation":is_at_workstation(),"available_for_work":is_available_for_work(),"can_progress_work":can_progress_work(),"pending_work":not pending_assignment.is_empty(),"paused":paused}

func set_paused(value: bool) -> void:
	if paused == value: return
	paused = value
	if _anim_player:
		if paused: _anim_player.pause()
		else:
			_anim_player.active = true
			_anim_player.play()
			if phase in [PHASE_BREAKWALK,PHASE_RETURN]: _play_anim("Walk")
			elif phase == PHASE_DRINK: _play_anim("Drink")
			else: _play_anim("Seated")

func status() -> Dictionary:
	return {"phase":phase,"paused":paused,"assignment":assignment.duplicate(true),"break_due_minute":break_due_minute,"break_requested":requested_break,"coffee_attached":is_instance_valid(coffee_visual)}

func tick(delta: float, game_minute := -1.0) -> void:
	if paused or departed: return
	if is_instance_valid(coffee_visual): _orient_coffee()
	var step := clampf(delta,0.0,0.2)
	if game_minute >= 0.0:
		_using_clock = true
		# Clock jumps can happen after loading or a long UI pause. Consume the
		# due break once, then schedule from the observed time.
		if game_minute >= break_due_minute: requested_break = true
		_last_game_minute = maxf(_last_game_minute,game_minute)
	else:
		_last_game_minute += step / 8.0
		if _last_game_minute >= break_due_minute: requested_break = true
	if _is_working():
		_set_phase(PHASE_SIT)
		return
	match phase:
		PHASE_IDLEWORK, PHASE_SIT:
			if not pending_assignment.is_empty():
				_accept_pending_work()
			elif requested_break: _begin_break()
		PHASE_BREAKWALK:
			if _move_to("break",step): _set_phase(PHASE_GETCOFFEE)
		PHASE_GETCOFFEE:
			if _move_to("coffee",step): _attach_coffee(); _set_phase(PHASE_DRINK)
		PHASE_DRINK:
			drink_elapsed += step
			if drink_elapsed >= drink_seconds:
				_detach_coffee()
				break_started_minute = _last_game_minute
				_route.clear(); _route_index=0
				_schedule_index += 1
				break_due_minute = break_schedule_minutes[_schedule_index] if _schedule_index < break_schedule_minutes.size() else _last_game_minute + break_interval_minutes
				_set_phase(PHASE_RETURN)
				if _has_route_provider():_load_route(seat_point)
		PHASE_RETURN:
			if _move_to("return",step):
				_set_phase(PHASE_SIT)
				_accept_pending_work()
		PHASE_DEPART:
			if _move_to("departure",step):
				departing = false; departed = true
				if actor: actor.visible = false; _set_actor_collision(false)

func _is_working() -> bool:
	return str(assignment.get("status","")) == "working"

func _accept_pending_work() -> void:
	if pending_assignment.is_empty(): return
	assignment = pending_assignment.duplicate(true)
	pending_assignment.clear()
	requested_break = false

func _begin_break() -> void:
	if _is_working(): return
	requested_break = false
	drink_elapsed = 0.0
	_route.clear(); _route_index=0
	var route_value = waypoints.get("break_path",[])
	if route_value is Array:
		for point in route_value: _route.append(Vector3(point))
	if _has_route_provider():_load_route(coffee_point)
	_set_phase(PHASE_BREAKWALK)

func _return_to_work() -> void:
	_detach_coffee()
	if departed:
		begin_arrival(actor.global_position)
		return
	departing = false; _set_actor_collision(true)
	if _has_route_provider():
		_load_route(seat_point);_set_phase(PHASE_RETURN);return
	if phase in [PHASE_BREAKWALK,PHASE_DEPART]:
		# Retrace only the corridor points already reached; taking the entire
		# return route here would walk an interrupted worker toward the kitchen.
		var visited: Array[Vector3] = []
		for index in range(mini(_route_index-1,_route.size()-1),-1,-1): visited.append(_route[index])
		visited.append(seat_point)
		_route = visited
	else:
		_route.clear()
	_route_index = 0
	_set_phase(PHASE_RETURN)

func reset_day(start_minute: float) -> void:
	if departed and actor:
		actor.visible = false
		return
	_detach_coffee()
	assignment.clear(); pending_assignment.clear(); _route.clear(); _route_index=0
	requested_break=false; drink_elapsed=0.0
	actor.global_position=seat_point
	configure(actor,waypoints,start_minute)
	departing = false
	departed = false
	if actor: actor.visible = true

func reset_staff_day(start_minute: float, entry: Vector3) -> void:
	_detach_coffee()
	assignment.clear(); pending_assignment.clear(); _route.clear(); _route_index=0
	requested_break=false; drink_elapsed=0.0
	configure(actor,waypoints,start_minute)
	departing=false; departed=true; phase=PHASE_DEPART
	actor.global_position=entry; actor.visible=false; _set_actor_collision(false)

func begin_arrival(entry: Vector3) -> void:
	if not actor: return
	departing = false; departed = false; actor.visible = true
	_set_actor_collision(true)
	actor.global_position = entry
	_route = []
	for point in waypoints.get("arrival_path", [seat_point]): _route.append(Vector3(point))
	if _has_route_provider():_load_route(seat_point)
	_route_index = 0
	_set_phase(PHASE_RETURN)

func begin_departure(entry: Vector3) -> void:
	if not actor or departing or departed: return
	_detach_coffee(); requested_break = false
	assignment.clear(); pending_assignment.clear()
	departing = true; departed = false
	_route = []
	for point in waypoints.get("departure_path", [entry]): _route.append(Vector3(point))
	if _has_route_provider():_load_route(entry)
	_route_index = 0
	_set_phase(PHASE_DEPART)

func is_departed() -> bool:
	return departed

func _move_to(key: String, delta: float) -> bool:
	if _has_route_provider() and key in ["return","break","departure"] and _route.is_empty():return false
	if key == "return":
		# Return route is loaded lazily so outward and inward paths can be
		# distinct while sharing the same movement code.
		var return_path = waypoints.get("return_path",[])
		if _route.is_empty() and return_path is Array:
			for point in return_path: _route.append(Vector3(point))
		var return_target := seat_point if _route_index >= _route.size() else _route[_route_index]
		return _move_toward(return_target,delta,key)
	var target := coffee_point if key == "coffee" else seat_point if key == "seat" else Vector3(waypoints.get("break",coffee_point))
	if key == "departure" and _route_index < _route.size(): target = _route[_route_index]
	if key == "break" and _route_index < _route.size(): target=_route[_route_index]
	return _move_toward(target,delta,key)

func _move_toward(target: Vector3, delta: float, key: String) -> bool:
	var mover: Node3D = actor if actor and actor != self else self
	var current := mover.global_position
	var flat := Vector3(target.x-current.x,0.0,target.z-current.z)
	if flat.length() <= 0.06:
		mover.global_position = Vector3(target.x,target.y,target.z)
		if key in ["break","return","departure"] and _route_index < _route.size():
			_route_index += 1
			if _route_index < _route.size(): return false
		return true
	var amount := minf(flat.length(),walk_speed*delta)
	mover.global_position += flat.normalized()*amount
	if flat.length_squared() > 0.0001: mover.look_at(mover.global_position+flat.normalized(),Vector3.UP,true)
	_play_anim("Walk")
	return false

func _set_actor_collision(enabled: bool) -> void:
	if not actor: return
	for body in actor.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 1 if enabled else 0
		body.collision_mask = 1 if enabled else 0

func _set_phase(value: String) -> void:
	if phase == value: return
	phase = value
	if phase in [PHASE_IDLEWORK,PHASE_SIT]:
		if actor: actor.rotation.y=seat_yaw
		_play_anim("Seated")
	elif phase in [PHASE_BREAKWALK,PHASE_RETURN,PHASE_DEPART]: _play_anim("Walk")
	elif phase == PHASE_DRINK: _play_anim("Drink")
	phase_changed.emit(phase)

func _find_animation_player() -> void:
	_anim_player = null
	if not actor: return
	var players := actor.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty(): _anim_player=players[0]

func _play_anim(name: String) -> void:
	if paused or not _anim_player: return
	var selected := ""
	for candidate in _anim_player.get_animation_list():
		if str(candidate).to_lower().contains(name.to_lower()): selected=str(candidate); break
	if selected.is_empty() and name == "Drink":
		for candidate in _anim_player.get_animation_list():
			if str(candidate).to_lower().contains("interact"): selected=str(candidate); break
	if not selected.is_empty() and _anim_player.current_animation != selected: _anim_player.play(selected,0.20)

func _attach_coffee() -> void:
	if not actor: return
	coffee_holder = actor.find_child("CoffeeGrip",true,false)
	if not coffee_holder:
		var skeletons := actor.find_children("*","Skeleton3D",true,false)
		if not skeletons.is_empty() and skeletons[0].find_bone("Wrist.R") >= 0:
			coffee_attachment=BoneAttachment3D.new(); coffee_attachment.name="CoffeeGrip"; coffee_attachment.bone_name="Wrist.R"; skeletons[0].add_child(coffee_attachment); coffee_holder=coffee_attachment
		else:
			coffee_holder=Node3D.new(); coffee_holder.name="CoffeeGrip"; actor.add_child(coffee_holder); coffee_holder.position=Vector3(0.0,1.22,0.22)
	coffee_visual=preload("res://scripts/coffee_prop.gd").new(); coffee_visual.name="CoffeeHeld"
	coffee_holder.add_child(coffee_visual)
	_orient_coffee.call_deferred()

func _orient_coffee() -> void:
	if not is_instance_valid(coffee_visual) or not is_instance_valid(coffee_holder): return
	# Wrist bone axes are not mug axes. Keep the vessel upright in actor space
	# while its centre follows the authored gripping hand through both sip beats.
	var sip := 0.0
	if _anim_player and _anim_player.current_animation.to_lower().contains("drink"):
		var clip_time := _anim_player.current_animation_position
		sip=smoothstep(0.75,1.58,clip_time)-smoothstep(2.71,3.54,clip_time)
	coffee_visual.global_basis = actor.global_basis * Basis(Vector3.RIGHT,-0.22*sip) * Basis(Vector3.UP,PI)
	coffee_visual.global_position = coffee_holder.global_position + actor.global_basis * Vector3(0.18,-0.065,0.025)

func _detach_coffee() -> void:
	if is_instance_valid(coffee_visual): coffee_visual.queue_free()
	coffee_visual=null
