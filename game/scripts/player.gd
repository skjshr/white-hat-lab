extends CharacterBody3D
## Movement interpolation adapted from Whimfoome/godot-FirstPersonStarter (MIT).
## See licenses/first-person-starter-MIT.txt. Office collision and focus added here.

var enabled := false
var speed := 3.4
var acceleration := 22.0
var deceleration := 30.0
var camera: Camera3D
var pitch := -0.04
var ignore_next_motion := true
var _step_clock := 0.0
var _office_walk_clock := 0.0
var coffee_rig: Node3D
var coffee_grip: Node3D
var coffee_cup: Node3D
var coffee_liquid := 1.0
var coffee_drink_tween: Tween
const COFFEE_PROP := preload("res://scripts/coffee_prop.gd")
const COFFEE_CARRY_POSITION := Vector3(-0.025,0.0,0.0)

func _ready() -> void:
	# Disable event accumulation for responsive captured-mouse look at 60 Hz.
	Input.use_accumulated_input = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	shape.shape = capsule
	shape.position.y = 0.84
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.58
	camera.fov = 70
	camera.near = 0.07
	camera.far = 90
	camera.rotation.x = pitch
	add_child(camera)
	camera.current = true
	floor_snap_length = 0.2
	_build_coffee_viewmodel()

func _coffee_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	return material

func _coffee_segment(from_point: Vector3, to_point: Vector3, radius: float, color: Color, parent: Node3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.94
	mesh.bottom_radius = radius
	mesh.height = from_point.distance_to(to_point)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _coffee_material(color)
	instance.position = (from_point + to_point) * 0.5
	instance.quaternion = Quaternion(Vector3.UP, (to_point - from_point).normalized())
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _build_coffee_viewmodel() -> void:
	coffee_rig = Node3D.new()
	coffee_rig.name = "LeftCoffeeHandView"
	coffee_rig.visible = false
	camera.add_child(coffee_rig)
	coffee_grip = Node3D.new()
	coffee_grip.name = "CoffeeGrip"
	coffee_grip.position = Vector3(-0.25,-0.24,-0.55)
	coffee_rig.add_child(coffee_grip)
	# A deliberately simple palm stays attached to the near side of the handle.
	# No anatomical fingers or forearm are needed for this first-person action.
	var hand := MeshInstance3D.new()
	hand.name = "CoffeePalm"
	var palm := SphereMesh.new()
	palm.radius = 0.032; palm.height = 0.064
	palm.radial_segments = 20; palm.rings = 12
	hand.mesh = palm
	hand.material_override = _coffee_material(Color("ddb49a"))
	hand.position = COFFEE_CARRY_POSITION + Vector3(-0.083, 0.063, 0.021)
	hand.scale = Vector3(1.0, 0.88, 1.08)
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coffee_grip.add_child(hand)
	coffee_cup = COFFEE_PROP.new()
	coffee_cup.name = "HeldCoffeeCup"
	coffee_cup.position = COFFEE_CARRY_POSITION
	coffee_cup.rotation.y = PI
	coffee_grip.add_child(coffee_cup)

func set_coffee_visible(value: bool) -> void:
	if coffee_rig: coffee_rig.visible = value

func set_coffee_liquid(value: float) -> void:
	coffee_liquid = clampf(value,0.0,1.0)
	if is_instance_valid(coffee_cup) and coffee_cup.has_method("set_liquid"):
		coffee_cup.set_liquid(coffee_liquid)

func reset_coffee_hand() -> void:
	if coffee_drink_tween and coffee_drink_tween.is_valid(): coffee_drink_tween.kill()
	if coffee_rig:
		coffee_rig.position = Vector3.ZERO
		coffee_rig.rotation = Vector3.ZERO
	if coffee_grip:
		coffee_grip.position = Vector3(-0.25,-0.24,-0.55)
		coffee_grip.rotation = Vector3.ZERO
	if is_instance_valid(coffee_cup):
		coffee_cup.position = COFFEE_CARRY_POSITION
		coffee_cup.rotation = Vector3(0,PI,0)

func _play_coffee_event(event: String) -> void:
	if has_node("/root/Soundscape"):
		get_node("/root/Soundscape").play_ui(event)

func animate_coffee_drink() -> Tween:
	reset_coffee_hand()
	if not coffee_rig: return null
	coffee_rig.visible = true
	coffee_drink_tween = create_tween()
	# Four readable beats: raise, settle the lip, sip, and lower.  The cup stays
	# on the lower-left side of the camera throughout, leaving the crosshair and
	# the interaction target visible.
	coffee_drink_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	coffee_drink_tween.tween_property(coffee_rig,"position",Vector3(0.018,0.045,0.065),0.34)
	coffee_drink_tween.parallel().tween_property(coffee_rig,"rotation",Vector3(0,-0.06,0.035),0.34)
	coffee_drink_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Move the palm and cup as one grip. The rim arrives just below the camera
	# centre and tilts toward the player without sliding through the palm.
	coffee_drink_tween.tween_property(coffee_rig,"position",Vector3(0.19,0.10,0.23),0.40)
	coffee_drink_tween.parallel().tween_property(coffee_rig,"rotation",Vector3(0,-0.03,0.02),0.40)
	coffee_drink_tween.tween_property(coffee_grip,"rotation",Vector3(0.42,0,-0.015),0.24)
	coffee_drink_tween.tween_callback(func(): _play_coffee_event("coffee_sip"))
	coffee_drink_tween.tween_interval(0.74)
	coffee_drink_tween.tween_property(coffee_grip,"rotation",Vector3.ZERO,0.26)
	coffee_drink_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	coffee_drink_tween.parallel().tween_property(coffee_rig,"position",Vector3.ZERO,0.44)
	coffee_drink_tween.parallel().tween_property(coffee_rig,"rotation",Vector3.ZERO,0.44)
	return coffee_drink_tween

func _input(event: InputEvent) -> void:
	if enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_motion(event.screen_relative)

func apply_mouse_motion(screen_relative: Vector2) -> void:
	if ignore_next_motion:
		ignore_next_motion = false
		return
	var sensitivity := 0.002 * float(Game.settings.get("mouse_sensitivity", 1.0))
	# screen_relative is raw, resolution-independent input and avoids accumulated
	# mouse events causing a perceptible turn delay at high frame rates.
	rotation.y -= screen_relative.x * sensitivity
	var vertical_sign := -1.0 if bool(Game.settings.get("invert_y", false)) else 1.0
	pitch = clampf(pitch - screen_relative.y * sensitivity * vertical_sign, -1.35, 1.35)
	camera.rotation.x = pitch

func prepare_for_capture() -> void:
	# A visible-to-captured cursor warp can emit one large synthetic motion event.
	# Discard that event so closing a UI never makes the camera jump.
	ignore_next_motion = true
	velocity.x = 0.0
	velocity.z = 0.0

func stop_control() -> void:
	ignore_next_motion = true
	velocity.x = 0.0
	velocity.z = 0.0
	_step_clock = 0.0
	_office_walk_clock = 0.0

func _physics_process(delta: float) -> void:
	var input_axis := Vector2.ZERO
	if enabled:
		input_axis = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input_axis.x, 0, input_axis.y)
	if direction.length_squared() > 1.0: direction = direction.normalized()
	var temp_vel := velocity
	temp_vel.y = 0
	var move_speed := speed * 1.45 if enabled and Input.is_action_pressed("sprint") else speed
	var target := direction * move_speed
	var temp_accel := acceleration if direction.dot(temp_vel) > 0 else deceleration
	temp_vel = temp_vel.lerp(target, clampf(temp_accel * delta, 0.0, 1.0))
	velocity.x = temp_vel.x
	velocity.z = temp_vel.z
	if not enabled:
		velocity.x = 0.0
		velocity.z = 0.0
	if not is_on_floor(): velocity.y -= 20.0 * delta
	else: velocity.y = -0.1
	move_and_slide()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if enabled and is_on_floor() and horizontal_speed > 0.55:
		var sprinting := Input.is_action_pressed("sprint")
		_step_clock += delta
		var step_interval := 0.34 if sprinting else 0.46
		if _step_clock >= step_interval:
			_step_clock = 0.0
			if has_node("/root/Soundscape"):
				get_node("/root/Soundscape").play_ui("footstep")
	else:
		_step_clock = 0.0
	if enabled:
		# A short real-time office clock keeps walking/idle time meaningful while
		# leaving billable work minutes under Game's existing action API.
		_office_walk_clock += delta
		if _office_walk_clock >= 8.0 and Game.has_method("office_walk"):
			var elapsed_minutes := floorf(_office_walk_clock / 8.0)
			_office_walk_clock -= elapsed_minutes * 8.0
			Game.office_walk(elapsed_minutes)
	else:
		_office_walk_clock = 0.0
	if position.y < -3: position = Vector3(0, 0.05, 3.5)

func focus() -> Dictionary:
	var origin := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin - camera.global_basis.z * 3.6)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {}
	var collider: Object = hit.collider
	if collider.has_meta("delivery_id"):
		return {"action":"delivery_box", "label":collider.get_meta("label", "設備の箱"), "delivery_id":str(collider.get_meta("delivery_id", ""))}
	if collider.has_meta("action"):
		var label: String = str(collider.get_meta("label", "操作"))
		if collider.has_meta("profile_name"):
			var member_id: String = str(collider.get_meta("profile_name"))
			label = (Game.player_name() if member_id == "player" else Game.member_name(member_id)) + str(collider.get_meta("profile_label_suffix", ""))
		return {"action":collider.get_meta("action"), "label":label, "coffee_machine":collider.get_meta("coffee_machine",false), "coffee_cup":collider.get_meta("coffee_cup",false)}
	return {}
