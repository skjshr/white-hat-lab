extends SceneTree

## V17 visual QA only. Builds the real office and writes GPU frames without using
## the player's normal save. Run from game/ with the regular Godot executable:
##   Godot.exe --path . -s tests/preview_world_v17.gd

var game: Node
var office: Node
var output_dir := ""
var interactive_coffee := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var value := str(arg)
		if value.begins_with("--out-dir="): output_dir = value.trim_prefix("--out-dir=")
		elif value == "--interactive-coffee": interactive_coffee = true
	call_deferred("_run")

func _run() -> void:
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://../artifacts/simulator")
	elif not output_dir.is_absolute_path():
		# Godot changes the process directory to game/, while the requested QA
		# artifacts live beside it at the workspace root.
		output_dir = ProjectSettings.globalize_path("res://../"+output_dir.trim_prefix("./"))
	DirAccess.make_dir_recursive_absolute(output_dir)
	game = root.get_node_or_null("Game")
	if game == null:
		push_error("V17 preview requires the Game autoload")
		quit(2)
		return
	# Redirect every write this preview can make before starting a clean state.
	game.save_path = "user://preview_world_v17.json"
	game.backup_path = "user://preview_world_v17.json.bak"
	game.previous_path = "user://preview_world_v17.json.previous.json"
	game.settings_path = "user://preview_world_v17-settings.json"
	game.new_game({"company":"V17視認テスト","player":"視認者","aya":"綾","ren":"蓮"})
	game.set_settings({"quality":"medium","max_fps":60,"render_scale":1.0,"msaa":2,"shadows":"off","resolution":"1280x720","window_mode":"windowed","text_scale":1.0},false)

	office = load("res://scripts/office.gd").new()
	office.name = "PreviewWorldV17"
	root.add_child(office)
	await _frames(8)
	_debug_npc_pose()
	if office.player == null or office.player.camera == null:
		push_error("V17 preview did not create the real player/camera")
		quit(2)
		return
	_configure_window()
	if interactive_coffee:
		_setup_interactive_coffee()
		await _frames(3)
		await _capture("v17-world-interactive-coffee.png")
		print("V17_INTERACTIVE_COFFEE ready camera_position=",office.player.camera.global_position," camera_target=(-4.8,0.8,3.62) focus=",office.player.focus()," machine_phase=",office.coffee_phase)
		return
	_hide_ui()
	office.started = true
	office.player.enabled = false
	office.player.camera.current = true

	# Ready state gives the machine's indicator, nozzle and physical cup a useful frame.
	office._start_coffee_brew()
	await _seconds(2.25)
	_set_camera(Vector3(-3.72,1.38,2.70),Vector3(-4.62,1.02,3.42),54.0)
	await _capture("v17-world-coffee-machine.png")

	# Two diagonal seated views. Targets are the real desk positions used by desk_worker_pose.gd.
	_set_camera(Vector3(-2.06,1.34,-1.10),Vector3(-3.55,0.84,-2.03),58.0)
	await _capture("v17-world-npc-aya.png")
	_set_camera(Vector3(1.35,1.34,-1.63),Vector3(2.86,0.84,-2.56),58.0)
	await _capture("v17-world-npc-ren.png")

	# Use the real office transition so the cup is the same object/state as gameplay.
	office._pick_up_coffee()
	office.player.enabled = false
	_set_camera(Vector3(-0.20,1.58,1.95),Vector3(-0.20,1.38,0.95),70.0)
	await _capture("v17-world-coffee-held.png")

	# Enable only for the real drink guard, then freeze movement and capture during the raise/tilt tween.
	office.player.enabled = true
	office._drink_coffee()
	await _seconds(0.52)
	_set_camera(Vector3(-0.20,1.58,1.95),Vector3(-0.20,1.38,0.95),70.0)
	await _capture("v17-world-coffee-drinking.png")
	print("V17_WORLD_PREVIEW output_dir=",output_dir)
	quit(0)

func _setup_interactive_coffee() -> void:
	# Leave the real HUD and focus prompt visible while placing the player just
	# outside the machine's upper interaction volume. No coffee state is forced.
	if office.ui != null and office.ui.current_kind != "": office.ui.close_panel(false)
	if office.ui != null:
		if office.ui.controls.has("menu") and is_instance_valid(office.ui.controls.menu):
			office.ui.controls.menu.visible = false
			office.ui.controls.menu.modulate = Color.WHITE
		if office.ui.hud != null: office.ui.hud.visible = true
		if office.ui.root != null: office.ui.root.show()
	office.started = true
	office.player.enabled = true
	office.player.position = Vector3(-3.25,0.05,3.40)
	var target := Vector3(-4.8,0.8,3.62)
	var direction: Vector3 = target - office.player.camera.global_position
	office.player.rotation.y = atan2(-direction.x,-direction.z)
	office.player.pitch = atan2(direction.y,Vector2(direction.x,direction.z).length())
	office.player.camera.rotation.x = office.player.pitch
	office.player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _debug_npc_pose() -> void:
	for id in ["aya","ren"]:
		var pivot := office.get_node_or_null(id)
		if pivot == null or not pivot.has_meta("desk_pose"): continue
		var pose = pivot.get_meta("desk_pose")
		print("V17_POSE ",id," targets=",pose.arm_targets)
		var skeletons := pivot.find_children("*","Skeleton3D",true,false)
		if skeletons.is_empty(): continue
		var skeleton: Skeleton3D = skeletons[0]
		for name in ["UpperArm.L","LowerArm.L","Wrist.L","UpperArm.R","LowerArm.R","Wrist.R"]:
			var index := skeleton.find_bone(name)
			if index >= 0: print("V17_BONE ",id," ",name," ",skeleton.to_global(skeleton.get_bone_global_pose(index).origin))

func _configure_window() -> void:
	var window := root.get_window()
	window.size = Vector2i(1280,720)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _hide_ui() -> void:
	if office.ui != null:
		if office.ui.current_kind != "": office.ui.close_panel(false)
		if office.ui.controls.has("menu") and is_instance_valid(office.ui.controls.menu): office.ui.controls.menu.hide()
		if office.ui.root != null: office.ui.root.hide()
	if office.notice != null: office.notice.hide()
	if office.crosshair != null: office.crosshair.hide()
	for label in office.find_children("*","Label3D",true,false):
		label.hide()

func _set_camera(position: Vector3, target: Vector3, fov: float) -> void:
	var camera: Camera3D = office.player.camera
	camera.global_position = position
	camera.look_at(target,Vector3.UP)
	camera.fov = fov
	camera.current = true

func _frames(count: int) -> void:
	for _i in count: await process_frame

func _seconds(value: float) -> void:
	await create_timer(value).timeout

func _capture(name: String) -> void:
	await _frames(3)
	# The office status notification is useful during play, but obscures the
	# physical hand/desk review in these QA frames.
	office.set_process(false)
	if office.notice != null: office.notice.hide()
	await process_frame
	var texture := root.get_viewport().get_texture()
	if texture == null:
		push_error("V17 preview has no viewport texture for "+name)
		office.set_process(true)
		return
	var image := texture.get_image()
	if image == null:
		push_error("V17 preview has no image for "+name)
		office.set_process(true)
		return
	var path := output_dir.path_join(name)
	var error := image.save_png(path)
	print("V17_WORLD_CAPTURE path=",path," error=",error)
	office.set_process(true)
