extends Node3D
## Compact office assembled from Kenney CC0 furniture; no online dependencies.
const UI = preload("res://scripts/ui_theme.gd")
const DELIVERY = preload("res://scripts/equipment_delivery.gd")
const PLACEMENT_RULES = preload("res://scripts/placement_rules.gd")
const WORKSTATION_SCREEN = preload("res://scripts/office_workstation_screen.gd")
const EQUIPMENT_VISUALS = preload("res://scripts/equipment_visuals.gd")

var player: CharacterBody3D
var ui: CanvasLayer
var sun: DirectionalLight3D
var office_env: WorldEnvironment
var started := false
var focused: Dictionary = {}
var material_cache: Dictionary = {}
var upgrades: Dictionary = {}
var upgrade_collisions: Dictionary = {}
var status_screen: Label3D
var mission_board: Label3D
var colleagues: Array[Node3D] = []
var staff_actors: Dictionary = {}
var staff_sync_elapsed := 0.0
var staff_sync_signature := ""
const STAFF_ENTRY := Vector3(4.0,0.0,3.8)
const TEAMDESK_SEAT := Vector3(1.0,0.0,1.98)
const TEAMDESK_WORK := Vector3(1.0,0.0,2.7)
var sound: AudioStreamPlayer
var notice: Label
var notice_time := 0.0
var elapsed := 0.0
var last_day := 1
var last_done := 0
var font: Font
var crosshair: Label
var applied_graphics: Dictionary = {}
var company_sign: Label3D
var player_desk_label: Label3D
var colleague_labels: Dictionary = {}
var colleague_desk_labels: Dictionary = {}
var monitors: Dictionary = {}
var workstation_screen_elapsed := 0.0
var performance_collecting := false
var performance_elapsed := 0.0
var performance_fps: Array[float] = []
var performance_draws: Array[float] = []
var performance_last_usec := 0
const COFFEE_PROP := preload("res://scripts/coffee_prop.gd")
var coffee_machine: Node3D
var coffee_machine_light: MeshInstance3D
var coffee_steam: Node3D
var coffee_cup: Node3D
var coffee_cup_body: StaticBody3D
var coffee_phase := "idle"
var coffee_elapsed := 0.0
var coffee_volume := 1.0
var coffee_drink_elapsed := 0.0
var coffee_drink_tween: Tween
var exterior_motion: Array[Node3D] = []
var daylight_elapsed := 0.0
var exterior_elapsed := 0.0
var soundscape_active := false
var coffee_anim_paused := false
var colleague_paused := false
var delivery: EquipmentDelivery
var annex_root: Node3D
var annex_gate: StaticBody3D
var annex_gate_mesh: MeshInstance3D
var annex_open := false
var annex_signature := ""
var layout_route_signature := ""
const ANNEX_GATE_Z := 3.15
const ANNEX_DESKS := {"annexdesk_a": Vector3(8.2,0.0,1.0), "annexdesk_b": Vector3(10.5,0.0,1.0)}

func _office_expanded() -> bool:
	return Game.has_method("office_expanded") and bool(Game.office_expanded())

func _ready() -> void:
	_setup_input()
	var font_variant := FontVariation.new()
	font_variant.base_font = load("res://assets/fonts/NotoSansJP.ttf")
	font_variant.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	font = font_variant
	if not Game.has_settings() or Game.settings.get("quality", "auto") == "auto":
		Game.set_settings(Graphics.preset_values(Graphics.recommended_preset()))
	_build_room()
	Soundscape.mount_world(self)
	_build_furniture()
	player = load("res://scripts/player.gd").new()
	player.name = "Player"
	add_child(player)
	player.position = Vector3(0, 0.05, 3.4)
	delivery = DELIVERY.new()
	delivery.name = "EquipmentDelivery"
	add_child(delivery)
	delivery.setup(Game, _delivery_slots())
	delivery.set_upgrade_nodes(upgrades)
	delivery.set_carried_anchor(player.camera)
	ui = load("res://scripts/interface.gd").new()
	ui.name = "Interface"
	add_child(ui)
	if ui.has_signal("desktop_preview_ready"):
		ui.desktop_preview_ready.connect(set_desktop_preview)
	ui.started.connect(_start)
	ui.quit_requested.connect(_quit)
	ui.open_main_menu()
	sound = AudioStreamPlayer.new()
	add_child(sound)
	_make_overlay()
	Game.changed.connect(_state_changed)
	Game.notified.connect(_notify)
	_state_changed()
	get_tree().auto_accept_quit = false
	call_deferred("_refresh_window_surface")
	if "--smoke" in OS.get_cmdline_user_args(): call_deferred("_smoke")
	if "--performance" in OS.get_cmdline_user_args(): call_deferred("_performance")

func _refresh_window_surface() -> void:
	# Refresh the initial WGL surface after layout; some Windows drivers present black until a resize.
	if DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED: return
	var original := get_window().size
	get_window().size = original + Vector2i(1,0)
	await get_tree().process_frame
	get_window().size = original

func _setup_input() -> void:
	var actions := {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"interact":KEY_E,"cases":KEY_TAB,"workstation":KEY_F,"crew_aya":KEY_1,"crew_ren":KEY_2,"equipment":KEY_3,"company":KEY_4}
	for action in actions:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = actions[action]
		InputMap.action_add_event(action, key)
		var logical := InputEventKey.new()
		logical.keycode = actions[action]
		InputMap.action_add_event(action, logical)

func _material(hex: String) -> StandardMaterial3D:
	if material_cache.has(hex): return material_cache[hex]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.95
	material_cache[hex] = m
	return m

func _textured_plane(path: String, size: Vector2, at: Vector3, parent: Node3D = self, alpha := 1.0) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(path)
	material.roughness = 0.92
	if path.ends_with("wood_floor.svg"):
		material.uv1_scale = Vector3(5,4,1)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1,1,1,alpha)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _company_name() -> String:
	return str(Game.company_name()) if Game.has_method("company_name") else "Company"

func _player_name() -> String:
	return str(Game.player_name()) if Game.has_method("player_name") else "あなた"

func _member_name(id: String) -> String:
	return str(Game.member_name(id)) if Game.has_method("member_name") else ("綾" if id == "aya" else "蓮")

func _carried_stock_id() -> String:
	if delivery == null: return ""
	var id := delivery.carried_id()
	return id if id.begins_with("stock-") else ""

func _stock_feedback() -> void:
	if delivery == null: return
	var error := delivery.stock_error()
	if error.is_empty(): return
	var copy_key := error if error.begins_with("stock_error_") else "stock_error_%s" % error
	_notify(UI.copy(copy_key, error))

func _display_name(value: String, limit: int) -> String:
	return value if value.length() <= limit else value.left(maxi(1, limit - 1)) + "…"

func _box(size: Vector3, at: Vector3, color: String, solid := false, parent: Node3D = self) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	model.mesh = mesh
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.material_override = _material(color)
	model.position = at
	parent.add_child(model)
	if solid: _collision(size, at, "", "", parent)
	return model

func _collision(size: Vector3, at: Vector3, action := "", label := "", parent: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if not action.is_empty():
		body.set_meta("action", action)
		body.set_meta("label", label)
	return body

func _label3d(text: String, at: Vector3, size := 38, color := Color("dce7db"), parent: Node3D = self) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.pixel_size = 0.007
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.position = at
	parent.add_child(label)
	return label

func _build_room() -> void:
	office_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5386b1")
	sky_material.sky_horizon_color = Color("d4e2e7")
	sky_material.ground_horizon_color = Color("d4e2e7")
	sky_material.ground_bottom_color = Color("66858c")
	sky_material.sky_curve = 0.16
	sky.sky_material = sky_material
	env.sky = sky
	env.background_color = Color("9fc6d0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e9f0f3")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	office_env.environment = env
	add_child(office_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_color = Color("f8f5ed")
	sun.light_energy = 0.75
	sun.shadow_enabled = false
	add_child(sun)
	_collision(Vector3(12.2,0.2,10.2),Vector3(0,-0.1,0))
	# One repeated hand-drawn wood tile keeps the floor coherent and cheap.
	_textured_plane("res://assets/office/wood_floor.svg",Vector2(12.0,10.0),Vector3(0,0.008,0))
	# A soft transparent diagonal patch connects the windows to the floor.
	_textured_plane("res://assets/office/window_light.svg",Vector2(4.2,7.2),Vector3(-3.8,0.018,0),self,0.58)
	_box(Vector3(12,3.3,0.18),Vector3(0,1.65,-5),"dde5e7",true)
	_box(Vector3(12,3.3,0.18),Vector3(0,1.65,5),"e4ebec",true)
	# Keep the east wall split around the future annex doorway. The gate closes
	# the opening until the persistent office upgrade is active.
	_box(Vector3(0.18,3.3,7.35),Vector3(6,1.65,-1.325),"99b2ad",true)
	_box(Vector3(0.18,3.3,1.05),Vector3(6,1.65,4.475),"99b2ad",true)
	annex_gate = _collision(Vector3(0.20,3.3,1.6),Vector3(6,1.65,ANNEX_GATE_Z),"shop",UI.copy("expansion_title"))
	annex_gate.set_meta("annex_gate",true)
	annex_gate_mesh = _box(Vector3(0.18,3.3,1.6),Vector3(6,1.65,ANNEX_GATE_Z),"99b2ad",false)
	_box(Vector3(0.18,0.85,10),Vector3(-6,0.425,0),"d6e0e3",true)
	_box(Vector3(0.18,0.45,10),Vector3(-6,3.075,0),"d6e0e3",true)
	_collision(Vector3(0.18,3.3,10),Vector3(-6,1.65,0))
	_box(Vector3(12.2,0.12,10.2),Vector3(0,3.38,0),"edf2f3")
	# Steel window frames and a static low-poly street outside.
	for z in [-4.6,-2.2,0.2,2.6,4.8]:
		_box(Vector3(0.25,2.1,0.065),Vector3(-5.95,1.83,z),"375052")
	_box(Vector3(0.28,0.06,10),Vector3(-5.9,1.8,0),"375052")
	_box(Vector3(0.35,0.08,10),Vector3(-5.85,0.86,0),"405253")
	# Teal brand wall and a real-world route to the six-day campaign.
	_box(Vector3(5.6,2.8,0.06),Vector3(-1.9,1.7,-4.87),"224545")
	company_sign = _label3d(_display_name(_company_name(),18),Vector3(-2.0,2.55,-4.80),52,Color("f4ead0"))
	_label3d("SECURITY  /  03",Vector3(-2.0,2.13,-4.79),22,Color("90c7b7"))
	_box(Vector3(1.2,2.5,0.08),Vector3(4.7,1.25,4.88),"345152")
	_box(Vector3(0.12,0.06,0.15),Vector3(4.25,1.1,4.8),"c6ba87")
	_collision(Vector3(1.3,2.5,0.3),Vector3(4.7,1.25,4.75),"door","退勤 / 翌日へ")
	var exit_sign := _label3d("EXIT  /  退勤",Vector3(4.7,2.72,4.74),26)
	exit_sign.rotation.y = PI
	# Ceiling strips provide visual lighting without realtime light sources.
	for x in [-3,1,4]:
		_box(Vector3(1.4,0.05,0.18),Vector3(x,3.26,-1),"fff2c9")
	_build_exterior_detail()

func _build_exterior_detail() -> void:
	var street: Node3D = load("res://assets/world/neighbourhood.glb").instantiate()
	street.name = "BlenderNeighbourhood"
	add_child(street)
	for mesh in street.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 3:
		var path := "res://assets/world/street_delivery_van.glb" if i == 2 else "res://assets/world/street_hatchback.glb"
		var car: Node3D = load(path).instantiate()
		car.name = "StreetTraffic%d" % i
		car.position = Vector3(-10.4 if i % 2 == 0 else -13.7,0.08,-22.0 + float(i)*18.0)
		car.rotation.y = PI if i % 2 else 0.0
		car.set_meta("base_z",car.position.z)
		car.set_meta("speed",2.8 if i % 2 == 0 else -3.2)
		for mesh in car.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(car)
		exterior_motion.append(car)

func _clock_minutes() -> float:
	if Game.has_method("clock_minutes"):
		var value = Game.clock_minutes()
		if value is int or value is float: return clampf(float(value),0.0,1440.0)
	if Game.has_method("business_clock"):
		var clock = Game.business_clock()
		if clock is Dictionary:
			if clock.has("minutes"): return clampf(float(clock.minutes),0.0,1440.0)
			if clock.has("clock_minutes"): return clampf(float(clock.clock_minutes),0.0,1440.0)
			if clock.has("hour"):
				return clampf(float(clock.hour)*60.0+float(clock.get("minute",0)),0.0,1440.0)
	var work: Variant = Game.state.get("work",{})
	if work is Dictionary and work.has("minutes"):
		return clampf(9.0*60.0+float(work.minutes),0.0,1440.0)
	return 9.0*60.0

func _update_daylight() -> void:
	var minutes := _clock_minutes()
	var daylight := clampf((minutes-6.0*60.0)/(14.0*60.0),0.0,1.0)
	var evening := clampf((minutes-15.0*60.0)/(4.0*60.0),0.0,1.0)
	sun.rotation_degrees = Vector3(lerpf(-20.0,-62.0,daylight),-25.0,0)
	sun.light_energy = lerpf(0.60,0.48,evening)
	sun.light_color = Color("f0f5fa").lerp(Color("f3b48e"),evening)
	if office_env and office_env.environment:
		office_env.environment.background_color = Color("9bc5d1").lerp(Color("d77f70"),evening)
		var sky_material := office_env.environment.sky.sky_material as ProceduralSkyMaterial
		if sky_material:
			sky_material.sky_top_color = Color("5386b1").lerp(Color("647289"),evening)
			sky_material.sky_horizon_color = Color("d4e2e7").lerp(Color("d9ada0"),evening)
			sky_material.ground_horizon_color = sky_material.sky_horizon_color

func _animate_exterior(delta: float) -> void:
	exterior_elapsed += delta
	for car in exterior_motion:
		if not is_instance_valid(car): continue
		var base_z := float(car.get_meta("base_z",0.0))
		var speed := float(car.get_meta("speed",0.5))
		car.position.z = wrapf(base_z + exterior_elapsed*speed,-60.0,60.0)

func _bounds(node: Node, xf := Transform3D.IDENTITY) -> AABB:
	var next := xf
	if node is Node3D: next = xf * node.transform
	var result := AABB()
	if node is MeshInstance3D: result = next * node.get_aabb()
	for child in node.get_children():
		var child_bounds := _bounds(child, next)
		if child_bounds.size.length() > 0.001:
			result = child_bounds if result.size.length() < 0.001 else result.merge(child_bounds)
	return result

func _prop(asset: String, at: Vector3, height: float, angle := 0.0, parent: Node3D = self) -> Node3D:
	var path := "res://assets/furniture/%s.glb" % asset
	if not ResourceLoader.exists(path):
		push_error("Missing furniture: " + path)
		return Node3D.new()
	var pivot := Node3D.new()
	pivot.name = asset
	parent.add_child(pivot)
	pivot.position = at
	pivot.rotation.y = angle
	var model: Node3D = load(path).instantiate()
	pivot.add_child(model)
	_tint_furniture(model, asset)
	var bounds := _bounds(model)
	var factor := height / maxf(bounds.size.y, 0.01)
	model.scale *= factor
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	return pivot

func _tint_furniture(model: Node3D, asset: String) -> void:
	var palette := {"wood":"856747", "carpet":"42625c", "metal":"819590", "metalMedium":"465553", "metalDark":"243a3b"}
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var material: Material = mesh.mesh.surface_get_material(i)
			if material and palette.has(material.resource_name):
				mesh.set_surface_override_material(i,_material(palette[material.resource_name]))
	# The monitor silhouette remains the original CC0 mesh. Its display is a matte panel.
	if asset == "computerScreen":
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(i,_material("263e3e"))

func _desk(at: Vector3, label: String, action: String, angle := 0.0) -> void:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = at
	pivot.rotation.y = angle
	_prop("desk",Vector3.ZERO,0.79,0,pivot)
	var desk_body := _collision(Vector3(1.55,0.8,0.8),Vector3(0,0.4,0),action,label,pivot)
	if action in ["terminal", "aya", "ren"]: desk_body.set_meta("profile_name", "player" if action == "terminal" else action)
	var screen := _prop("computerScreen",Vector3(0,0.79,-0.17),0.48,0,pivot)
	# The GLB's second material surface is the inset display face. Apply the
	# wallpaper to that imported face so it inherits the screen's real bounds,
	# tilt and depth instead of floating as a guessed PlaneMesh.
	_screen_wallpaper(screen)
	_register_workstation_screen(screen, action)
	var screen_body := _collision(Vector3(0.76,0.6,0.18),Vector3(0,1.04,-0.17),action,label,pivot)
	if action in ["terminal", "aya", "ren"]: screen_body.set_meta("profile_name", "player" if action == "terminal" else action)
	_prop("computerKeyboard",Vector3(-0.1,0.80,0.23),0.04,0,pivot)
	_prop("computerMouse",Vector3(0.32,0.80,0.30),0.04,0,pivot)
	_prop("lampSquareTable",Vector3(-0.60,0.80,-0.17),0.38,0,pivot)
	_prop("chairDesk",Vector3(0,0,0.58 if action in ["aya","ren"] else 0.98),1.02,PI,pivot)
	var nameplate_backing := _box(Vector3(0.28,0.07,0.012),Vector3(-0.43,0.865,0.25),"eef2f3",false,pivot)
	nameplate_backing.rotation_degrees = Vector3(-58,0,0)
	var nameplate := _label3d(label,Vector3(-0.43,0.876,0.257),11,Color("244946"),pivot)
	nameplate.pixel_size = 0.0035
	nameplate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	nameplate.rotation_degrees = Vector3(-58,0,0)
	if action == "terminal": player_desk_label = nameplate
	elif action == "aya" or action == "ren": colleague_desk_labels[action] = nameplate
	if action in ["aya","ren"]: nameplate.show()
	if action == "terminal":
		status_screen = null
	_box(Vector3(0.23,0.01,0.28),Vector3(0.59,0.82,0.23),"f4e9c9",false,pivot)
	_textured_plane("res://assets/office/contact_shadow.svg",Vector2(1.65,1.55),Vector3(0,0.018,0.12),pivot,0.52)

func _screen_wallpaper(screen: Node3D) -> void:
	var texture: Texture2D = load("res://assets/ui/aoba-wallpaper-v16.png")
	if texture == null: return
	for mesh in screen.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.mesh.get_surface_count() < 2: continue
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 1.0
		# computerScreen.glb stores the inset face UVs in u=0.266..15.193,
		# v=-10.563..-1.363. Normalize that authored range to one wallpaper.
		material.uv1_scale = Vector3(1.0 / 14.92664, 1.0 / 9.19924, 1.0)
		material.uv1_offset = Vector3(-0.26676 / 14.92664, 10.562574 / 9.19924, 0.0)
		mesh.set_surface_override_material(1, material)

func _register_workstation_screen(screen: Node3D, workstation_id: String) -> void:
	if screen == null or workstation_id.is_empty(): return
	if monitors.has(workstation_id) and is_instance_valid(monitors[workstation_id]):
		monitors[workstation_id].queue_free()
	var monitor: OfficeWorkstationScreen = WORKSTATION_SCREEN.new()
	monitor.name = "WorkstationMonitor_%s" % workstation_id
	add_child(monitor)
	monitor.setup(screen, Game, workstation_id)
	monitors[workstation_id] = monitor

func set_desktop_preview(texture: Texture2D) -> void:
	var monitor = monitors.get("terminal", null)
	if monitor != null and is_instance_valid(monitor): monitor.set_desktop_preview(texture)

func clear_desktop_preview() -> void:
	var monitor = monitors.get("terminal", null)
	if monitor != null and is_instance_valid(monitor): monitor.clear_desktop_preview()

func _refresh_workstation_screens(force := false) -> void:
	for monitor in monitors.values():
		if monitor == null or not is_instance_valid(monitor): continue
		if not force and monitor.screen != null and not monitor.screen.is_visible_in_tree(): continue
		monitor.refresh(force)

func _build_furniture() -> void:
	_desk(Vector3(-0.5,0,-1.0),_display_name(_player_name(),18),"terminal")
	_desk(Vector3(-3.6,0,-2.3),_display_name(_member_name("aya"),12),"aya",0.2)
	_desk(Vector3(2.8,0,-2.8),_display_name(_member_name("ren"),12),"ren",-0.25)
	_prop("bookcaseOpen",Vector3(5.4,0,-1.0),1.9,-PI/2)
	_prop("books",Vector3(5.3,0.87,-1.0),0.22,-PI/2)
	var stock_rack := _prop("bookcaseOpenLow",Vector3(5.4,0,1.2),0.9,-PI/2)
	# The rack's local X axis runs across its shelves after the authored yaw.
	# Widen that axis slightly so three half-scale cartons fit without clipping.
	stock_rack.scale.x = 1.2
	_collision(Vector3(0.8,2,1.0),Vector3(5.4,1,-1.0),"shop","設備カタログ")
	# Keep the two widened rack uprights as the shelf interaction points. Leaving
	# the shelf faces open lets stored cartons receive the focus ray for pickup.
	var stock_label := UI.copy("stock_shelf","Customer stock")
	_collision(Vector3(0.56,0.9,0.07),Vector3(5.4,0.45,0.695),"stock_shelf",stock_label)
	_collision(Vector3(0.56,0.9,0.07),Vector3(5.4,0.45,1.705),"stock_shelf",stock_label)
	var shop_label := _label3d("設備カタログ [3]",Vector3(5.2,2.1,-1.0),24)
	shop_label.rotation.y = -PI/2
	_prop("sideTable",Vector3(-4.8,0,3.4),0.78)
	coffee_machine = _prop("kitchenCoffeeMachine",Vector3(-4.8,0.8,3.4),0.45)
	var appliance_bounds := _bounds(coffee_machine)
	_make_coffee_machine_detail()
	# Keep the plant to the machine's left so it does not hide the cup on the
	# right side of the counter.
	_prop("plantSmall1",Vector3(-5.15,0.8,3.55),0.32)
	var machine_body := _collision(Vector3(1.25,0.8,0.65),Vector3(-4.8,0.4,3.4),"coffee_brew","コーヒーを淹れる")
	machine_body.name = "CoffeeMachineInteraction"
	machine_body.set_meta("coffee_machine",true)
	# The counter collision above stops the player at the work surface, but the
	# machine model rises above it. Keep a separate upper volume for the actual
	# appliance so the focus ray can reach the brew action at its visible height.
	var machine_upper := _collision(appliance_bounds.size+Vector3(0.04,0.02,0.04),appliance_bounds.get_center(),"coffee_brew","コーヒーを淹れる")
	machine_upper.name = "CoffeeMachineUpperInteraction"
	machine_upper.set_meta("coffee_machine",true)
	_prop("coatRackStanding",Vector3(3.4,0,4.4),1.72)
	_prop("trashcan",Vector3(-4.8,0,-3.8),0.5)
	# Whiteboard with six physical result pins.
	_box(Vector3(2.65,1.5,0.08),Vector3(3.4,1.98,-4.82),"345354")
	_box(Vector3(2.45,1.3,0.02),Vector3(3.4,1.98,-4.765),"ede9ce")
	mission_board = _label3d("",Vector3(3.4,2.13,-4.74),26,Color("284943"))
	_collision(Vector3(2.65,1.5,0.2),Vector3(3.4,1.98,-4.70),"board","案件ボード [Tab]")
	for equipment_id in ["plant", "backup", "monitor", "workstation", "diagnostic", "teamdesk"]:
		var index: int = Game.equipment_slot(equipment_id)
		_build_equipment(equipment_id, _delivery_slots()[index], self)
	# The coworker models are CC0 Quaternius assets, imported as glTF.
	_add_colleague("aya",Vector3(-3.25,0,-0.3),Color("edbe7c"))
	_add_colleague("ren",Vector3(3.3,0,-1.0),Color("77c4b2"))
	_set_coffee_machine_visual()
	_sync_annex_state()

func _sync_annex_state() -> void:
	var expanded := _office_expanded()
	if annex_gate:
		annex_gate.collision_layer = 0 if expanded else 1
		annex_gate.collision_mask = 0 if expanded else 1
	if annex_gate_mesh: annex_gate_mesh.visible = not expanded
	var wanted_signature := str(expanded)
	if expanded and not is_instance_valid(annex_root):
		_build_annex()
	elif not expanded and is_instance_valid(annex_root):
		if is_instance_valid(player) and player.position.x > 5.7: player.position = Vector3(0,0.05,3.4)
		for id in ANNEX_DESKS:
			upgrades.erase(id)
			if upgrade_collisions.has(id): upgrade_collisions[id].queue_free(); upgrade_collisions.erase(id)
			if monitors.has(id):
				if is_instance_valid(monitors[id]): monitors[id].queue_free()
				monitors.erase(id)
		for id in staff_actors.keys():
			if str(staff_actors[id].get("workplace","")).begins_with("annexdesk"): _remove_staff_actor(id)
		annex_root.queue_free(); annex_root = null; annex_signature = ""
	annex_open = expanded
	annex_signature = wanted_signature if expanded else ""

func _build_annex() -> void:
	annex_root = Node3D.new(); annex_root.name = "OfficeAnnex"; add_child(annex_root)
	_collision(Vector3(6.0,0.2,5.0),Vector3(9.0,-0.1,2.5),"","",annex_root)
	_textured_plane("res://assets/office/wood_floor.svg",Vector2(6.0,5.0),Vector3(9.0,0.008,2.5),annex_root)
	_box(Vector3(6.0,3.3,0.18),Vector3(9.0,1.65,5.0),"e4ebec",true,annex_root)
	_box(Vector3(6.0,3.3,0.18),Vector3(9.0,1.65,0.0),"e4ebec",true,annex_root)
	_box(Vector3(0.18,3.3,5.0),Vector3(12.0,1.65,2.5),"99b2ad",true,annex_root)
	_box(Vector3(6.0,0.12,5.0),Vector3(9.0,3.38,2.5),"edf2f3",false,annex_root)
	_box(Vector3(2.0,0.05,0.18),Vector3(8.0,3.26,2.0),"fff2c9",false,annex_root)
	_box(Vector3(2.0,0.05,0.18),Vector3(10.5,3.26,2.0),"fff2c9",false,annex_root)
	for desk_id in ANNEX_DESKS:
		_build_annex_desk(desk_id,ANNEX_DESKS[desk_id])

func _build_equipment(id: String, at: Vector3, parent: Node3D) -> void:
	var model: Node3D = EQUIPMENT_VISUALS.build(id)
	parent.add_child(model)
	model.position = at
	model.rotation.y = PI if id in ["workstation", "teamdesk"] else -0.25 if id == "monitor" else 0.0
	upgrades[id] = model
	var screens: Array[Node] = model.find_children("*", "Node3D", true, false).filter(func(node): return bool(node.get_meta("equipment_screen", false)))
	for index in screens.size():
		_screen_wallpaper(screens[index])
		_register_workstation_screen(screens[index], id if index == 0 else id + "_aux")

func _build_annex_desk(id: String, at: Vector3) -> void:
	_build_equipment(id, at, annex_root)
	upgrades[id].visible = id in Game.state.get("equipment", [])

func _make_coffee_machine_detail() -> void:
	if not coffee_machine: return
	coffee_machine_light = MeshInstance3D.new()
	var lamp := SphereMesh.new()
	lamp.radius = 0.024
	lamp.height = 0.048
	coffee_machine_light.mesh = lamp
	coffee_machine_light.material_override = _material("63756f")
	coffee_machine_light.position = Vector3(0.10,0.22,0.20)
	coffee_machine_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coffee_machine.add_child(coffee_machine_light)
	coffee_steam = Node3D.new()
	coffee_steam.name = "Steam"
	coffee_machine.add_child(coffee_steam)
	for i in 3:
		var w := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.008
		mesh.bottom_radius = 0.012
		mesh.height = 0.10
		w.mesh = mesh
		w.material_override = _material("c8ded8")
		w.position = Vector3(0.0+float(i-1)*0.035,0.40,0.04)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		coffee_steam.add_child(w)

func _set_coffee_machine_visual() -> void:
	if not is_instance_valid(coffee_machine_light): return
	var color := Color("63756f")
	if coffee_phase == "brewing": color = Color("e7a84c")
	elif coffee_phase == "ready": color = Color("6dd1a4")
	coffee_machine_light.material_override = _material(color.to_html(false))
	if coffee_steam: coffee_steam.visible = coffee_phase == "brewing"

func _coffee_table_position() -> Vector3:
	return Vector3(-4.42,0.782,3.43)

func _spawn_coffee_cup() -> void:
	if is_instance_valid(coffee_cup): coffee_cup.queue_free()
	coffee_cup = COFFEE_PROP.new()
	coffee_cup.name = "CoffeeCup"
	coffee_cup.position = _coffee_table_position()
	add_child(coffee_cup)
	coffee_cup.set_liquid(coffee_volume)
	coffee_cup_body = _collision(Vector3(0.18,0.14,0.18),coffee_cup.position+Vector3(0,0.065,0),"coffee_pickup",UI.copy("coffee_pickup","カップを手に取る"))
	coffee_cup_body.name = "CoffeeCupInteraction"
	coffee_cup_body.set_meta("coffee_cup",true)

func _start_coffee_brew() -> void:
	if coffee_phase != "idle": return
	coffee_phase = "brewing"
	coffee_elapsed = 0.0
	coffee_volume = 1.0
	_set_coffee_machine_visual()
	Soundscape.play_ui("coffee_pour")
	_notify(UI.copy("coffee_brew","淹れる")+"…")

func _pick_up_coffee() -> void:
	if delivery != null and not delivery.carried_id().is_empty():
		_notify(UI.copy("delivery_controls")); return
	if coffee_phase != "ready" or not player: return
	if is_instance_valid(coffee_cup_body): coffee_cup_body.queue_free(); coffee_cup_body = null
	if is_instance_valid(coffee_cup): coffee_cup.queue_free(); coffee_cup = null
	coffee_phase = "carried"
	coffee_volume = 1.0
	player.set_coffee_liquid(coffee_volume)
	player.set_coffee_visible(true)
	_set_coffee_machine_visual()
	_notify("[左クリック] "+UI.copy("coffee_drink","飲む"))

func _set_down_coffee() -> void:
	if not coffee_phase in ["carried","carried_empty"]: return
	if coffee_drink_tween and coffee_drink_tween.is_valid(): coffee_drink_tween.kill()
	player.reset_coffee_hand()
	player.set_coffee_visible(false)
	if coffee_phase == "carried_empty":
		coffee_phase = "idle"
		coffee_volume = 1.0
		_set_coffee_machine_visual()
		Soundscape.play_ui("coffee_setdown")
		_notify("カップ配置完了 Eで次を淹れる")
		return
	else:
		coffee_phase = "ready"
	_spawn_coffee_cup()
	_set_coffee_machine_visual()
	Soundscape.play_ui("coffee_setdown")
	_notify("カップ配置完了")

func _drink_coffee() -> void:
	if coffee_phase != "carried" or coffee_volume <= 0.02: return
	if not player or not player.enabled or ui.is_open(): return
	coffee_phase = "drinking"
	coffee_drink_elapsed = 0.0
	coffee_drink_tween = player.animate_coffee_drink()
	if coffee_drink_tween:
		coffee_drink_tween.finished.connect(_finish_coffee_drink)
	_notify(UI.copy("coffee_drink","飲む"))

func _finish_coffee_drink() -> void:
	if coffee_phase != "drinking": return
	# One click is one sip.  Keep the cup in hand for another click until the
	# third sip has emptied it, so drinking does not teleport a full mug to zero.
	coffee_phase = "carried_empty" if coffee_volume <= 0.02 else "carried"
	player.set_coffee_liquid(coffee_volume)
	_notify("[E] "+UI.copy("coffee_setdown","机に置く") if coffee_phase == "carried_empty" else "[左クリック] "+UI.copy("coffee_drink","もう一口"))

func _add_colleague(id: String, at: Vector3, color: Color) -> void:
	var pivot := Node3D.new()
	pivot.name = id
	add_child(pivot)
	# Seat the coworkers close enough to the desk for a relaxed bend at the elbows.
	# The old 0.98m chair offset forced the imported arms into a straight reach.
	var work_position := Vector3(-3.6,0,-2.3)+Vector3(0,0,0.58).rotated(Vector3.UP,0.2) if id=="aya" else Vector3(2.8,0,-2.8)+Vector3(0,0,0.58).rotated(Vector3.UP,-0.25)
	pivot.position = work_position
	pivot.rotation.y=PI+0.2 if id=="aya" else PI-0.25
	pivot.set_meta("last_job_status","")
	var path := "res://assets/characters/v19/%s.glb" % id
	if ResourceLoader.exists(path):
		var model: Node3D = load(path).instantiate()
		pivot.add_child(model)
		var b := _bounds(model)
		var factor := 1.68 / maxf(b.size.y,0.1)
		model.scale *= factor
		model.position.y -= b.position.y * factor
		for animator in model.find_children("*","AnimationPlayer",true,false):
			for clip in ["Seated","Idle","Walk","Drink"]:
				if animator.has_animation(clip): animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			animator.play("Seated")
	var member_display := _member_name(id)
	var action_suffix := " / "+("原因調査を依頼" if id == "aya" else "復元・証拠保全を依頼")
	var member_body := _collision(Vector3(0.62,1.8,0.62),Vector3(0,0.9,0),id,member_display+action_suffix,pivot)
	member_body.set_meta("profile_name", id)
	member_body.set_meta("profile_label_suffix", action_suffix)
	var label := _label3d(_display_name(member_display,12),Vector3(0,1.51,0),22,color,pivot)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.outline_size = 2
	label.outline_modulate = Color("203a3b")
	label.hide()
	_textured_plane("res://assets/office/contact_shadow.svg",Vector2(0.82,0.62),Vector3(0,0.018,0),pivot,0.42)
	pivot.set_meta("label",label)
	colleague_labels[id] = label
	colleagues.append(pivot)
	_setup_colleague_routine(pivot)

func _setup_colleague_routine(pivot: Node3D) -> void:
	var id := str(pivot.name)
	var routine := preload("res://scripts/office_colleague.gd").new()
	routine.name = "Routine"
	add_child(routine)
	routine.actor = pivot
	if id == "ren": routine.break_schedule_minutes.assign([645.0,735.0,915.0])
	var seat := pivot.global_position
	var desk := Vector3(-3.6,0,-2.3) if id == "aya" else Vector3(2.8,0,-2.8)
	var coffee := PLACEMENT_RULES.COFFEE
	var break_spot := Vector3(-2.5,0,3.4)
	var approach := Vector3(-3.6,0,-0.85) if id == "aya" else Vector3(2.8,0,-1.35)
	var outward: Array[Vector3] = _walk_path(approach,coffee)
	var inward: Array[Vector3] = _walk_path(coffee,approach)
	var points := {"seat":seat,"seat_yaw":pivot.rotation.y,"work":desk,"break":break_spot,"coffee":coffee,"approach":approach,"break_path":outward,"return_path":inward}
	_attach_route_provider(points)
	routine.configure(pivot,points,float(Game.state.get("clock_minutes",540)))
	routine.phase_changed.connect(_routine_phase_notice.bind(id))
	pivot.set_meta("office_colleague_routine",routine)

func _spawn_hired_staff(member: Dictionary) -> void:
	var id := str(member.get("id", "")); if id.is_empty() or staff_actors.has(id): return
	var role := str(member.get("role", "aya")); var source := "ren" if role == "ren" else "aya"
	var pivot := Node3D.new(); pivot.name = id; add_child(pivot); pivot.position = STAFF_ENTRY; pivot.rotation.y = PI
	var model_path := "res://assets/characters/v19/%s.glb" % source
	if ResourceLoader.exists(model_path):
		var model: Node3D = load(model_path).instantiate(); pivot.add_child(model)
		var b := _bounds(model); var factor := 1.68 / maxf(b.size.y,0.1); model.scale *= factor; model.position.y -= b.position.y * factor
		for animator in model.find_children("*","AnimationPlayer",true,false): animator.play("Seated")
	var color := Color("b8a0df") if role == "maintenance" else Color("df9a9a") if role == "aya" else Color("7ca8d8")
	var member_display := str(member.get("name", id)); _collision(Vector3(0.62,1.8,0.62),Vector3(0,0.9,0),id,member_display,pivot)
	var label := _label3d(_display_name(member_display,12),Vector3(0,1.51,0),11,color,pivot); label.billboard = BaseMaterial3D.BILLBOARD_DISABLED; label.outline_size = 2; label.outline_modulate = Color("203a3b"); label.hide()
	_textured_plane("res://assets/office/contact_shadow.svg",Vector2(0.82,0.62),Vector3(0,0.018,0),pivot,0.42)
	pivot.set_meta("staff_id", id); pivot.set_meta("display_name", member_display); pivot.set_meta("label",label); pivot.set_meta("last_job_status",""); colleague_labels[id] = label; colleagues.append(pivot)
	var routine := preload("res://scripts/office_colleague.gd").new(); routine.name = "Routine"; add_child(routine)
	var workplace := str(Game.staff_workplace(id)) if Game.has_method("staff_workplace") else "teamdesk"
	var points := _workplace_points(workplace)
	var desk_position: Vector3=points.work
	routine.configure(pivot,points,float(Game.state.get("clock_minutes",540))); routine.begin_arrival(STAFF_ENTRY); pivot.set_meta("office_colleague_routine",routine)
	if started: Soundscape.play_ui("staff_arrival")
	staff_actors[id] = {"actor":pivot,"routine":routine,"role":role,"workplace":workplace,"workplace_position":desk_position}

func _workplace_position(workplace: String) -> Vector3:
	var info:=PLACEMENT_RULES.workplace(_workplace_order(workplace))
	return info.position

func _workplace_order(workplace: String) -> Dictionary:
	for order in Game.state.get("delivery_orders",[]):
		if str(order.get("id",""))==workplace:return order
	return {"id":workplace,"status":"installed","rotation_y":PI if workplace=="teamdesk" else 0.0}

func _workplace_points(workplace: String) -> Dictionary:
	var info:=PLACEMENT_RULES.workplace(_workplace_order(workplace))
	var points: Dictionary={"seat":info.seat,"seat_yaw":info.seat_yaw,"work":info.position,"approach":info.approach,"break":Vector3(-2.5,0,3.4),"coffee":PLACEMENT_RULES.COFFEE}
	_attach_route_provider(points)
	return points

func _attach_route_provider(points: Dictionary) -> void:
	var seat: Vector3=points.seat;var approach: Vector3=points.approach
	points.entry=PLACEMENT_RULES.ENTRY
	points.route_provider=func(from: Vector3,to: Vector3):return _route_for_seat(from,to,seat,approach)
	points.arrival_path=_route_for_seat(PLACEMENT_RULES.ENTRY,seat,seat,approach)
	points.departure_path=_route_for_seat(seat,PLACEMENT_RULES.ENTRY,seat,approach)
	points.break_path=_route_for_seat(seat,PLACEMENT_RULES.COFFEE,seat,approach)
	points.return_path=_route_for_seat(PLACEMENT_RULES.COFFEE,seat,seat,approach)

func _route_for_seat(from: Vector3,to: Vector3,seat: Vector3,approach: Vector3) -> Array[Vector3]:
	var origin:=_route_origin(from,seat,approach)
	var from_seat:=origin.distance_to(from)>0.001
	var to_seat:=to.distance_to(seat)<0.15
	var path:=_walk_path(origin,approach if to_seat else to)
	if path.is_empty():return path
	if from_seat:path.push_front(approach)
	if to_seat:path.append(seat)
	return path

func _route_origin(from: Vector3,seat: Vector3,approach: Vector3) -> Vector3:
	# A worker entering or leaving their chair must finish that short aisle
	# before joining the shared floor grid, including after a layout refresh.
	var point:=Vector2(from.x,from.z);var a:=Vector2(seat.x,seat.z);var b:=Vector2(approach.x,approach.z)
	var closest:=Geometry2D.get_closest_point_to_segment(point,a,b)
	return approach if point.distance_to(closest)<0.12 else from

func placement_routes_clear(proposed: Array) -> bool:
	for actor in colleagues:
		if not is_instance_valid(actor) or not actor.visible:continue
		var routine=actor.get_meta("office_colleague_routine",null)
		if not is_instance_valid(routine) or routine.is_departed():continue
		var origin:=_route_origin(actor.global_position,routine.seat_point,Vector3(routine.waypoints.get("approach",routine.seat_point)))
		if PLACEMENT_RULES.walk_path(origin,PLACEMENT_RULES.ENTRY,proposed,_office_expanded()).is_empty():return false
	return true

func _walk_path(from: Vector3,to: Vector3) -> Array[Vector3]:
	return PLACEMENT_RULES.walk_path(from,to,Game.state.get("delivery_orders",[]),_office_expanded())

func _refresh_layout_routes() -> void:
	var signature:=PLACEMENT_RULES._layout_key(Game.state.get("delivery_orders",[]),_office_expanded())
	if signature==layout_route_signature:return
	layout_route_signature=signature
	for actor in colleagues:
		var routine=actor.get_meta("office_colleague_routine",null)
		if not is_instance_valid(routine):continue
		var points: Dictionary=routine.waypoints.duplicate(true)
		if actor.has_meta("staff_id"):
			points=_workplace_points(str(Game.staff_workplace(str(actor.get_meta("staff_id")))))
		else:_attach_route_provider(points)
		routine.update_workplace(points)

func _staff_on_shift(member: Dictionary) -> bool:
	if not bool(member.get("hired", false)) or not bool(member.get("active", true)): return false
	var shift := str(member.get("shift", "")); if shift.is_empty() or not Game.has_method("staff_shift_catalog"): return true
	var catalog = Game.staff_shift_catalog(); var spec: Dictionary = {}
	if catalog is Array:
		for candidate in catalog:
			if str(candidate.get("id", "")) == shift: spec = candidate; break
	elif catalog is Dictionary:
		spec = catalog.get(shift, {})
	var minute := int(Game.state.get("clock_minutes", 540)); return minute >= int(spec.get("start",540)) and minute < int(spec.get("end",1080))

func _sync_hired_staff() -> void:
	if not Game.has_method("team_members"): return
	var members: Array = Game.team_members(); var seen := {}
	for member in members:
		if not member is Dictionary: continue
		var id := str(member.get("id", "")); if id.is_empty(): continue
		seen[id] = true
		var job: Dictionary = Game.state.get("assignments", {}).get(id, {})
		var working := str(job.get("status", "")) == "working"
		var workplace := str(Game.staff_workplace(id)) if Game.has_method("staff_workplace") else "teamdesk"
		var workplace_installed: bool = workplace in Game.state.get("equipment", [])
		var current_workplace_position := _workplace_position(workplace)
		if staff_actors.has(id) and str(staff_actors[id].get("workplace", "teamdesk")) != workplace:
			_remove_staff_actor(id)
		if staff_actors.has(id) and Vector2(staff_actors[id].get("workplace_position", Vector3.ZERO).x, staff_actors[id].get("workplace_position", Vector3.ZERO).z).distance_to(Vector2(current_workplace_position.x,current_workplace_position.z)) > 0.02:
			if not working:
				var moved_entry: Dictionary = staff_actors[id]
				var moved_routine: OfficeColleague = moved_entry.get("routine")
				if is_instance_valid(moved_routine): moved_routine.update_workplace(_workplace_points(workplace))
				moved_entry["workplace_position"] = current_workplace_position
		if staff_actors.has(id) and workplace.begins_with("annex") and not annex_open:
			_remove_staff_actor(id)
		if bool(member.get("hired", false)) and workplace_installed and not staff_actors.has(id) and (_staff_on_shift(member) or working): _spawn_hired_staff(member)
		if not staff_actors.has(id): continue
		var entry: Dictionary = staff_actors[id]; var actor: Node3D = entry.actor; var routine: OfficeColleague = entry.routine
		if _staff_on_shift(member) or working:
			if routine.is_departed():
				routine.begin_arrival(STAFF_ENTRY)
				Soundscape.play_ui("staff_arrival")
		elif not routine.departing and not routine.is_departed():
			routine.begin_departure(STAFF_ENTRY)
			Soundscape.play_ui("staff_departure")
	var departed_ids: Array[String] = []
	for id in staff_actors.keys():
		if seen.has(id): continue
		if str(staff_actors[id].get("workplace","")) not in Game.state.get("equipment",[]):
			_remove_staff_actor(id); continue
		var stale: Dictionary = staff_actors[id]; var stale_actor: Node3D = stale.actor; var stale_routine: OfficeColleague = stale.routine; var stale_job: Dictionary = Game.state.get("assignments", {}).get(id, {})
		if str(stale_job.get("status", "")) == "working": continue
		if not stale_routine.departing and not stale_routine.is_departed(): stale_routine.begin_departure(STAFF_ENTRY)
		if stale_routine.is_departed():
			stale_actor.queue_free(); stale_routine.queue_free(); colleague_labels.erase(str(id)); colleagues.erase(stale_actor); departed_ids.append(str(id))
	for id in departed_ids: staff_actors.erase(id)

func _remove_staff_actor(id: String) -> void:
	if not staff_actors.has(id): return
	var entry: Dictionary = staff_actors[id]
	var actor: Node3D = entry.get("actor")
	var routine: Node = entry.get("routine")
	if is_instance_valid(routine): routine.queue_free()
	if is_instance_valid(actor): actor.queue_free()
	colleague_labels.erase(id)
	if is_instance_valid(actor): colleagues.erase(actor)
	staff_actors.erase(id)

func _routine_phase_notice(phase: String, id: String) -> void:
	var key := "npc_break" if phase == "breakwalk" else "npc_coffee" if phase in ["getcoffee","drink"] else "npc_returning" if phase == "return" else ""
	if key.is_empty(): return
	var text := UI.copy(key,"休憩に向かっています" if key == "npc_break" else "コーヒーを飲んでいます" if key == "npc_coffee" else "席へ戻っています")
	_notify(_display_name(_member_name(id),12)+" / "+text)

func _make_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	notice = Label.new()
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice.offset_top = 82
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_override("font",font)
	notice.add_theme_font_size_override("font_size",22)
	notice.add_theme_color_override("font_color",Color("ffe0a5"))
	notice.add_theme_color_override("font_shadow_color",Color("142c2c"))
	notice.add_theme_constant_override("shadow_offset_x",2)
	notice.add_theme_constant_override("shadow_offset_y",2)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(notice)
	crosshair = Label.new()
	crosshair.name = "Crosshair"
	crosshair.text = "·"
	crosshair.add_theme_font_size_override("font_size",32)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -6
	crosshair.offset_top = -22
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(crosshair)

func _start() -> void:
	clear_desktop_preview()
	started = true
	player.position = Vector3(0,0.05,3.4)
	player.rotation = Vector3.ZERO
	player.pitch = -0.04
	player.camera.rotation.x = player.pitch
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Game.has_method("set_delivery_clock_enabled"): Game.set_delivery_clock_enabled(true)
	if Game.state.get("game_complete",false): ui.open_panel("ending")
	elif not Game.state.get("accepted",false): ui.open_panel("board")
	_state_changed()

func _process(delta: float) -> void:
	elapsed += delta
	if player == null or ui == null: return
	staff_sync_elapsed += delta
	if staff_sync_elapsed >= 0.25:
		staff_sync_elapsed = 0.0
		_sync_hired_staff()
	workstation_screen_elapsed += delta
	if workstation_screen_elapsed >= 1.0:
		workstation_screen_elapsed = 0.0
		_refresh_workstation_screens()
	var menu_visible := false
	if ui.controls.has("menu"):
		menu_visible = bool(ui.controls.menu.visible)
	var overlay_paused := menu_visible or str(ui.current_kind) in ["pause", "settings", "confirm_display", "ending"]
	colleague_paused = overlay_paused
	if Game.has_method("set_delivery_clock_paused"): Game.set_delivery_clock_paused(overlay_paused)
	if delivery != null: delivery.update_carried_anchor()
	if delivery != null and delivery.is_placing(): _update_equipment_placement_preview()
	var requested_soundscape := started and not menu_visible and str(ui.current_kind) not in ["pause", "confirm_display", "ending"]
	if requested_soundscape != soundscape_active:
		soundscape_active = requested_soundscape
		Soundscape.set_workspace(soundscape_active)
	if overlay_paused != coffee_anim_paused:
		coffee_anim_paused = overlay_paused
		if coffee_drink_tween and coffee_drink_tween.is_valid():
			if coffee_anim_paused: coffee_drink_tween.pause()
			else: coffee_drink_tween.play()
	_animate_exterior(delta)
	daylight_elapsed += delta
	if daylight_elapsed >= 0.5:
		daylight_elapsed = 0.0
		_update_daylight()
	if coffee_phase == "brewing" and not coffee_anim_paused:
		coffee_elapsed = minf(2.0,coffee_elapsed + delta)
		if coffee_elapsed >= 2.0:
			coffee_phase = "ready"
			_spawn_coffee_cup()
			_set_coffee_machine_visual()
			_notify(UI.copy("coffee_ready","コーヒーが淹れ上がりました")+"　Eで"+UI.copy("coffee_pickup","カップを手に取る"))
	if coffee_phase == "drinking" and not coffee_anim_paused:
		coffee_drink_elapsed += delta
		# The liquid level changes during the held sip, not while the hand is
		# still travelling toward the mouth.  Each completed action consumes 1/3.
		if coffee_drink_elapsed >= 0.98 and coffee_drink_elapsed <= 1.66:
			coffee_volume = maxf(0.0, coffee_volume - delta / 0.68 / 3.0)
		player.set_coffee_liquid(coffee_volume)
	var should_enable: bool = started and not ui.is_open()
	if should_enable != player.enabled:
		if should_enable:
			player.prepare_for_capture()
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			player.stop_control()
		player.enabled = should_enable
	crosshair.visible = player.enabled
	if player.enabled:
		focused = player.focus()
		var message := ""
		if not focused.is_empty():
			var carried_stock_id := _carried_stock_id()
			if str(focused.get("action", "")) == "delivery_box":
				var delivery_order := Game.delivery_for(str(focused.get("delivery_id", "")))
				var delivery_status := str(delivery_order.get("status", ""))
				if str(focused.get("delivery_id", "")).begins_with("stock-"):
					focused.label = UI.copy("delivery_pickup", "Receive") if delivery_status in ["ready", "stored", "staged"] else UI.copy("stock_box", "Customer gateway")
				else:
					focused.label = UI.copy("delivery_pickup", "受け取る") if delivery_status == "ready" else UI.copy("delivery_place", "設置する")
			if not carried_stock_id.is_empty():
				var focused_action := str(focused.get("action", ""))
				if focused_action == "stock_shelf":
					focused.action = "stock_store"
					focused.label = UI.copy("stock_shelf", "Store on shelf")
				elif focused_action == "terminal":
					focused.action = "stock_stage"
					focused.label = UI.copy("stock_stage", "Stage for setup")
				elif focused_action == "door":
					focused.action = "stock_dispatch"
					focused.label = UI.copy("stock_dispatch", "Dispatch to client")
			if str(focused.get("action", "")).begins_with("equipment_") and str(focused.action).ends_with("_move"): focused.label = UI.copy("equipment_move")
			if bool(focused.get("coffee_machine",false)):
				if coffee_phase in ["carried","carried_empty"]:
					focused.action = "coffee_setdown"
					focused.label = "カップを置く"
				elif coffee_phase == "ready":
					focused.action = "coffee_pickup"
					focused.label = UI.copy("coffee_pickup","カップを手に取る")
				elif coffee_phase == "brewing":
					focused.action = "coffee_busy"
					focused.label = "抽出中…"
				elif coffee_phase == "drinking":
					focused.action = "coffee_busy"
					focused.label = UI.copy("coffee_drink","飲む")+"…"
			if str(focused.action) == "coffee_busy": message = str(focused.label)
			else:
				message = "[ E ]  " + str(focused.label)
				if str(focused.action) == "coffee_brew": message = "[ E ]  "+UI.copy("coffee_brew","淹れる")
				elif str(focused.action) == "coffee_pickup": message = "[ E ]  "+UI.copy("coffee_pickup","カップを手に取る")
				elif str(focused.action) == "coffee_setdown": message = "[ E ]  置く"
				elif str(focused.action) == "delivery_box": message = "[ E ]  "+str(focused.label)
				elif str(focused.action) in ["stock_store", "stock_stage", "stock_dispatch"]: message = "[ E ]  "+str(focused.label)
		if delivery != null and delivery.is_placing():
			message = UI.copy("equipment_placement_controls") if delivery.placement_valid() else delivery.placement_reason()
		if coffee_phase == "carried":
			message = "[左クリック] "+UI.copy("coffee_drink","飲む")+("　"+message if not message.is_empty() else "")
		ui.set_focus_prompt(message)
	else:
		focused = {}
	if notice_time > 0:
		notice_time -= delta
		if notice_time <= 0: notice.text = ""
	notice.visible = ui.current_kind != "terminal"
	for colleague in colleagues: _animate_colleague(colleague,delta)
	var working_count := 0
	for id in Game.state.get("assignments",{}):
		var assignment: Dictionary = Game.state.assignments[id]
		if str(assignment.get("status","")) == "working" and bool(Game.colleague_runtime_availability(str(id)).available): working_count += 1
	Soundscape.set_activity(working_count)
	if performance_collecting:
		var now_usec := Time.get_ticks_usec()
		var frame_seconds := float(now_usec-performance_last_usec)/1000000.0
		performance_last_usec=now_usec
		performance_elapsed += frame_seconds
		if frame_seconds > 0.000001:
			performance_fps.append(1.0 / frame_seconds)
			performance_draws.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if performance_elapsed >= 5.0:
			_finish_performance()

func _animate_colleague(colleague: Node3D, delta: float) -> void:
	var id := str(colleague.get_meta("staff_id", colleague.name))
	var job: Dictionary = Game.state.get("assignments",{}).get(id,{})
	var state_name := str(job.get("status",""))
	var working := state_name=="working"
	var previous := str(colleague.get_meta("last_job_status",""))
	var phase := float(colleague.get_meta("work_anim_timer",0.0))+delta
	var report_time := maxf(0.0,float(colleague.get_meta("report_time",0.0))-delta)
	if state_name != previous:
		phase=0.0
		if state_name=="done": report_time=2.6
		colleague.set_meta("last_job_status",state_name)
	colleague.set_meta("work_anim_timer",phase); colleague.set_meta("report_time",report_time)
	var routine: Node = colleague.get_meta("office_colleague_routine",null)
	if routine and is_instance_valid(routine) and started:
		routine.set_paused(colleague_paused)
		routine.set_assignment(job)
		if Game.has_method("set_colleague_runtime_availability"):
			Game.set_colleague_runtime_availability(id,bool(routine.is_at_workstation() and not routine.paused))
		var minute := float(Game.state.get("clock_minutes",540)) if bool(Game.state.get("accepted",false)) else -1.0
		routine.tick(delta,minute)
	# Motion is tied to actual assignments, never to a random patrol timer.
	if colleague.has_meta("desk_pose") and not routine:
		colleague.get_meta("desk_pose").update(working,report_time>0,delta)
	var label: Label3D = colleague.get_meta("label")
	var activity := str(job.get("phase","作業中")) if working else "報告を送信しました" if state_name=="done" else "依頼待ち"
	var text := _display_name(str(colleague.get_meta("display_name", _member_name(id))),12)+" / "+activity
	if colleague.has_meta("staff_id"): text = _display_name(str(colleague.get_meta("display_name")),12)+"\n"+("作業中" if working else "完了" if state_name=="done" else "待機中")
	if label.text != text: label.text=text

func _unhandled_input(event: InputEvent) -> void:
	if not started or ui.is_open(): return
	var holding_coffee := coffee_phase in ["carried","carried_empty","drinking"]
	if delivery != null and delivery.is_placing() and (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		delivery.interact("cancel", delivery.carried_id()); get_viewport().set_input_as_handled(); return
	if delivery != null and not _carried_stock_id().is_empty() and event.is_action_pressed("interact"):
		var stock_id := _carried_stock_id()
		var stock_action := str(focused.get("action", ""))
		var stock_ok := false
		if stock_action == "stock_store": stock_ok = delivery.interact("store", stock_id)
		elif stock_action == "stock_stage": stock_ok = delivery.interact("stage", stock_id)
		elif stock_action == "stock_dispatch": stock_ok = delivery.interact("dispatch", stock_id)
		if not stock_ok: _stock_feedback()
		get_viewport().set_input_as_handled(); return
	if delivery != null and not delivery.carried_id().is_empty() and event.is_action_pressed("interact"):
		var id := delivery.carried_id()
		if holding_coffee: _notify(UI.copy("delivery_keep_hands_free"))
		elif not delivery.is_placing(): delivery.interact("place_start",id)
		else:
			if delivery.placement_valid(): delivery.interact("confirm",id)
			else: _notify(delivery.placement_reason())
		get_viewport().set_input_as_handled(); return
	if delivery != null and event is InputEventKey and event.pressed and event.keycode == KEY_R and not holding_coffee and not delivery.carried_id().is_empty():
		delivery.interact("rotate", delivery.carried_id()); get_viewport().set_input_as_handled(); return
	if delivery != null and event is InputEventMouseButton and event.pressed:
		var carried_id := delivery.carried_id()
		if delivery.is_placing() and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			delivery.interact("rotate_right" if event.button_index == MOUSE_BUTTON_WHEEL_UP else "rotate_left", carried_id)
			get_viewport().set_input_as_handled(); return
		if event.button_index == MOUSE_BUTTON_RIGHT and not holding_coffee and not carried_id.is_empty():
			if delivery.is_placing() and carried_id != "": delivery.interact("cancel", carried_id)
			else:
				var safe_position := _safe_delivery_drop_position()
				if safe_position.is_empty(): _notify(UI.copy("delivery_invalid"))
				else: delivery.interact("put_down", carried_id, -1, safe_position)
			get_viewport().set_input_as_handled(); return
		if event.button_index == MOUSE_BUTTON_LEFT and not carried_id.is_empty() and not holding_coffee:
			if carried_id.begins_with("stock-"):
				var stock_action := str(focused.get("action", ""))
				var stock_ok := false
				if stock_action == "stock_store": stock_ok = delivery.interact("store", carried_id)
				elif stock_action == "stock_stage": stock_ok = delivery.interact("stage", carried_id)
				elif stock_action == "stock_dispatch": stock_ok = delivery.interact("dispatch", carried_id)
				if not stock_ok: _stock_feedback()
			elif delivery._placing_id.is_empty(): delivery.interact("place_start", carried_id)
			elif delivery.placement_valid(): delivery.interact("confirm", carried_id)
			else: _notify(delivery.placement_reason())
			get_viewport().set_input_as_handled(); return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if coffee_phase == "carried": _drink_coffee()
		return
	if event.is_action_pressed("interact") and not focused.is_empty():
		var action := str(focused.action)
		if action == "delivery_box" and delivery != null:
			if holding_coffee:
				_notify(UI.copy("delivery_keep_hands_free")); get_viewport().set_input_as_handled(); return
			var delivery_id := str(focused.get("delivery_id", ""))
			var delivery_order := Game.delivery_for(delivery_id)
			var delivery_status := str(delivery_order.get("status", ""))
			if delivery_id.begins_with("stock-") and delivery_status in ["ready", "stored", "staged"]: delivery.interact("pickup", delivery_id)
			elif delivery_status == "ready": delivery.interact("pickup", delivery_id)
			elif delivery_status == "carried": delivery.interact("place_start", delivery_id)
			elif delivery_status == "placing":
				if delivery.can_confirm_from(player.global_position, delivery_id): delivery.interact("confirm", delivery_id)
				else: _notify(UI.copy("delivery_hint", "設置場所まで運搬してください。"))
			get_viewport().set_input_as_handled(); return
		if action.begins_with("equipment_") and action.ends_with("_move") and delivery != null:
			var equipment_id := action.trim_prefix("equipment_").trim_suffix("_move")
			if equipment_id in PLACEMENT_RULES.FLOOR_IDS or equipment_id == "monitor": delivery.interact("place_start", equipment_id)
			get_viewport().set_input_as_handled(); return
		if action == "coffee_brew": _start_coffee_brew()
		elif action == "coffee_pickup": _pick_up_coffee()
		elif action == "coffee_setdown": _set_down_coffee()
		elif action == "coffee_busy": pass
		elif action == "stock_shelf":
			if ui != null: ui.set("shop_view", "stock")
			_open("shop")
		elif staff_actors.has(action):
			_open("terminal")
			if is_instance_valid(ui.desktop): ui.desktop._show_app("team")
		else: _open(action)
	elif event.is_action_pressed("cases"): _open("board")
	elif event.is_action_pressed("workstation"): _open("terminal")
	elif event.is_action_pressed("crew_aya"): _open("aya")
	elif event.is_action_pressed("crew_ren"): _open("ren")
	elif event.is_action_pressed("equipment"): _open("shop")
	elif event.is_action_pressed("company"): _open("company")

func _open(kind: String) -> void:
	if player:
		player.stop_control()
		player.enabled = false
	_play_sound("click_001")
	ui.open_panel(kind)
	get_viewport().set_input_as_handled()

func _state_changed() -> void:
	if applied_graphics != Game.settings:
		var settings: Dictionary = Graphics.apply_settings(Game.settings)
		get_viewport().msaa_3d = {0:Viewport.MSAA_DISABLED,2:Viewport.MSAA_2X,4:Viewport.MSAA_4X}.get(int(settings.msaa),Viewport.MSAA_DISABLED)
		sun.shadow_enabled = settings.shadows != "off"
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if settings.shadows == "low" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 18.0
		if player: player.camera.fov = float(settings.fov)
		applied_graphics = Game.settings.duplicate(true)
	_sync_annex_state()
	# _process keeps ambience alive during normal OS work and stops it for the
	# pause/title overlays, where a focused UI should be quiet.
	for id in upgrades: upgrades[id].visible = id in Game.state.get("equipment",[])
	if delivery != null:
		delivery.set_upgrade_nodes(upgrades)
		delivery.sync_orders(Game.delivery_orders())
	_apply_installed_delivery_positions()
	var day := int(Game.state.get("day",1))
	var completed: int = Game.state.get("completed_ids",[]).size()
	if mission_board:
		mission_board.text = "案件ボード\nDAY %d   Lv.%d\n営業カタログ %d件" % [day,int(Game.company_level().level),Game.CASES.all().size()]
	if status_screen:
		status_screen.text = "●  完了" if Game.current_done() else ("●  作業中" if Game.state.get("accepted",false) else "●  待機")
	if company_sign: company_sign.text = _display_name(_company_name(),18)
	if player_desk_label: player_desk_label.text = _display_name(_player_name(),18)
	for id in ["aya","ren"]:
		if colleague_desk_labels.has(id): colleague_desk_labels[id].text = _display_name(_member_name(id),12)
	_update_daylight()
	if completed > last_done:
		_play_sound("confirmation_001")
		_notify("納品完了  案件利益 ¥%d" % int(Game.completion_receipt().get("net",0)))
	if day != last_day:
		player.position = Vector3(0,0.05,3.4)
		for colleague in colleagues:
			var routine = colleague.get_meta("office_colleague_routine",null)
			if routine:
				if colleague.has_meta("staff_id"): routine.reset_staff_day(float(Game.clock_minutes()),STAFF_ENTRY)
				else: routine.reset_day(float(Game.clock_minutes()))
		_sync_hired_staff()
		_notify("DAY %d  /  案件ボードに新規依頼" % day)
	_sync_hired_staff()
	_refresh_workstation_screens()
	last_day = day
	last_done = completed

func _delivery_slots() -> Array:
	# Preserve the existing six equipment footprints while allowing delivery_v19
	# to persist the selected slot and rotation through Game.
	return [Vector3(-5.2,0.0,0.4),Vector3(0.7,0.0,-1.05),Vector3(2.0,0.8,-2.8),Vector3(4.1,0.0,-3.25),Vector3(1.15,0.0,0.65),Vector3(1.0,0.0,2.7),Vector3(8.2,0.0,1.0),Vector3(10.5,0.0,1.0)]

func _apply_installed_delivery_positions() -> void:
	if delivery == null: return
	var slots := _delivery_slots()
	var moving_id := ""
	for order in Game.delivery_orders():
		if str(order.get("status", "")) == "placing": moving_id = str(order.get("id", ""))
		if str(order.get("status", "")) != "installed": continue
		var id := str(order.get("id", "")); var slot := int(order.get("install_slot", -1))
		if not upgrades.has(id): continue
		var saved: Variant = order.get("install_position", [])
		if saved is Array and saved.size() >= 3:
			upgrades[id].position = Vector3(float(saved[0]), 0.8 if id == "monitor" and float(saved[1]) < 0.1 else float(saved[1]), float(saved[2]))
		elif slot >= 0 and slot < slots.size(): upgrades[id].position = slots[slot]
		upgrades[id].rotation.y = float(order.get("rotation_y", 0.0))
	for id in upgrades:
		var installed: bool = id in Game.state.get("equipment",[])
		if id == moving_id:
			upgrades[id].visible = false
		else: upgrades[id].visible = installed
		if installed and not upgrade_collisions.has(id):
			var bounds := _bounds(upgrades[id])
			upgrade_collisions[id] = _collision(bounds.size,bounds.get_center())
			upgrade_collisions[id].set_meta("equipment_id", id)
		if upgrade_collisions.has(id):
			var refreshed_bounds := _bounds(upgrades[id])
			upgrade_collisions[id].position = refreshed_bounds.get_center()
			var refreshed_shape := upgrade_collisions[id].get_node_or_null("CollisionShape3D") as CollisionShape3D
			if refreshed_shape != null:
				var refreshed_box := refreshed_shape.shape as BoxShape3D
				if refreshed_box != null: refreshed_box.size = refreshed_bounds.size
			upgrade_collisions[id].collision_layer=1 if installed else 0
		if id == moving_id and upgrade_collisions.has(id): upgrade_collisions[id].collision_layer = 0
		if installed and id != moving_id and upgrade_collisions.has(id):
			upgrade_collisions[id].set_meta("action", "equipment_%s_move" % id)
			upgrade_collisions[id].set_meta("label", UI.copy("equipment_move"))

	_refresh_layout_routes()

func _update_equipment_placement_preview() -> void:
	if player == null or delivery == null: return
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_center := Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5)
	var origin: Vector3 = player.camera.project_ray_origin(screen_center)
	var direction: Vector3 = player.camera.project_ray_normal(screen_center)
	if delivery._placing_id == "monitor":
		_update_monitor_placement(origin, direction)
		return
	if absf(direction.y) < 0.0001:
		delivery.update_placement_preview(delivery.placement_position_array(), delivery._placing_rotation, false, "床面を狙ってください。")
		return
	var distance: float = -origin.y / direction.y
	if distance < 0.0 or distance > 3.0:
		delivery.update_placement_preview(delivery.placement_position_array(), delivery._placing_rotation, false, "2〜3m以内の床を対象にしてください。")
		return
	var hit: Vector3 = origin + direction * distance
	delivery.update_placement_preview([hit.x, 0.0, hit.z], delivery._placing_rotation)

func _update_monitor_placement(origin: Vector3, direction: Vector3) -> void:
	var closest := 3.0
	var picked: Array = []
	if absf(direction.y) > 0.0001:
		for surface in PLACEMENT_RULES.monitor_surface_specs(Game.delivery_orders()):
			var center: Vector3 = surface.center
			var distance := (center.y - origin.y) / direction.y
			if distance < 0.0 or distance > closest: continue
			var hit := origin + direction * distance
			var local := Vector2(hit.x-center.x,hit.z-center.z).rotated(float(surface.rotation_y))
			var size: Vector2 = surface.size
			if not Rect2(-size*0.5,size).has_point(local): continue
			picked = [hit.x, center.y, hit.z]; closest = distance
	if picked.is_empty():
		delivery.update_placement_preview(delivery.placement_position_array(), delivery._placing_rotation, false, UI.copy("equipment_surface_hint"))
	else:
		delivery.update_placement_preview(picked, delivery._placing_rotation)

func monitor_placement_error(position: Array, yaw: float) -> String:
	var support: Dictionary = PLACEMENT_RULES.monitor_surface_for_position(position, yaw, Game.delivery_orders())
	if support.is_empty(): return UI.copy("equipment_surface_invalid")
	var bounds: AABB = upgrades.monitor.get_meta("bounds")
	var shape := BoxShape3D.new(); shape.size = bounds.size
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP,yaw),Vector3(float(position[0]),float(position[1])+bounds.size.y*0.5+0.012,float(position[2])))
	query.collision_mask = 1
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body: Object = hit.collider
		if body == upgrade_collisions.get("monitor"): continue
		if str(body.get_meta("equipment_id", "")) == str(support.get("support_id", "none")): continue
		return UI.copy("equipment_surface_invalid")
	return ""

func _safe_delivery_drop_position() -> Array:
	var forward := -player.global_transform.basis.z
	var target := player.global_position + forward * 1.25
	var candidates := [target, target + Vector3(0.7, 0, 0), target + Vector3(-0.7, 0, 0)]
	for candidate in candidates:
		candidate.x = clampf(candidate.x, -5.0, 5.0)
		candidate.z = clampf(candidate.z, -4.0, 4.0)
		if _delivery_drop_clear(candidate): return [candidate.x, 0.26, candidate.z]
	return []

func _delivery_drop_clear(candidate: Vector3) -> bool:
	var shape := BoxShape3D.new()
	# Leave a 1 cm clearance from the floor in the overlap query.
	shape.size = Vector3(0.60, 0.50, 0.60)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(candidate.x, 0.26, candidate.z))
	query.collision_mask = 1
	if player is CollisionObject3D: query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()

func _play_sound(asset: String) -> void:
	Soundscape.play_ui("receipt_positive" if asset.begins_with("confirmation") else "click")

func _notify(message: String) -> void:
	if notice:
		notice.text = message
		notice_time = 4.5

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and ui and not ui.is_open():
		ui.open_panel("pause")

func _quit() -> void:
	if ui and is_instance_valid(ui.desktop): ui.desktop._save_session()
	if started: Game.save_game()
	get_tree().quit()

func _exit_tree() -> void:
	if has_node("/root/Soundscape"):
		Soundscape.unmount_world(self)

func _smoke() -> void:
	await get_tree().create_timer(3).timeout
	print("OFFICE_SMOKE nodes=",get_tree().get_node_count()," fps=",Engine.get_frames_per_second()," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," objects=",Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	get_tree().quit()

func _performance() -> void:
	# Warm up shaders and scene streaming before measuring actual rendered frames.
	await get_tree().create_timer(5.0).timeout
	performance_collecting = true
	performance_last_usec = Time.get_ticks_usec()
	performance_elapsed = 0.0
	performance_fps.clear()
	performance_draws.clear()
	print("OFFICE_PERFORMANCE_BEGIN preset=",Game.settings.get("quality", "unknown")," max_fps=",Game.settings.get("max_fps", 0)," renderer=",RenderingServer.get_video_adapter_name())

func _finish_performance() -> void:
	performance_collecting = false
	performance_fps.sort()
	performance_draws.sort()
	var count := performance_fps.size()
	var median := performance_fps[count / 2] if count > 0 else 0.0
	var low_count := maxi(1, int(ceil(float(count) * 0.01)))
	var low_sum := 0.0
	for i in low_count: low_sum += performance_fps[i]
	var one_percent_low := low_sum / float(low_count)
	var draw_count := performance_draws.size()
	var draw_median := performance_draws[draw_count / 2] if draw_count > 0 else 0.0
	print("OFFICE_PERFORMANCE_RESULT warmup_s=5 render_s=5 frames=",count," median_fps=",snappedf(median,0.1)," one_percent_low_fps=",snappedf(one_percent_low,0.1)," median_draw_calls=",snappedf(draw_median,1.0)," headless=",DisplayServer.get_name() == "headless")
	get_tree().quit()
