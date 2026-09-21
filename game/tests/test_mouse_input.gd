extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	await process_frame
	var game := root.get_node("Game")
	game.settings_path = "user://mouse-input-test-settings.json"
	var player = load("res://scripts/player.gd").new()
	root.add_child(player)
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.enabled = true
	game.set_settings({"mouse_sensitivity":0.5,"invert_y":false})

	# The first event after capture is the cursor-warp event and is discarded.
	player.prepare_for_capture()
	var first := _motion(Vector2(999, 0))
	player.apply_mouse_motion(first.screen_relative)
	var yaw_before: float = player.rotation.y
	player.apply_mouse_motion(_motion(Vector2(10, 0)).screen_relative)
	var sensitivity_half := absf(player.rotation.y - yaw_before)

	game.set_settings({"mouse_sensitivity":2.0,"invert_y":false})
	player.prepare_for_capture(); player.apply_mouse_motion(_motion(Vector2(999, 0)).screen_relative)
	yaw_before = player.rotation.y
	player.apply_mouse_motion(_motion(Vector2(10, 0)).screen_relative)
	var sensitivity_two := absf(player.rotation.y - yaw_before)
	_assert(absf(sensitivity_two / maxf(sensitivity_half, 0.00001) - 4.0) < 0.01, "感度0.5対2.0の回転比4")

	game.set_settings({"mouse_sensitivity":1.0,"invert_y":false})
	player.prepare_for_capture(); player.apply_mouse_motion(_motion(Vector2(999, 0)).screen_relative)
	var pitch_before: float = player.pitch
	player.apply_mouse_motion(_motion(Vector2(10, 10)).screen_relative)
	var normal_pitch_delta: float = player.pitch - pitch_before
	game.set_settings({"invert_y":true})
	player.prepare_for_capture(); player.apply_mouse_motion(_motion(Vector2(999, 0)).screen_relative)
	pitch_before = player.pitch
	player.apply_mouse_motion(_motion(Vector2(10, 10)).screen_relative)
	_assert(normal_pitch_delta * (player.pitch - pitch_before) < 0.0, "invertYで上下方向反転")

	player.stop_control(); player.enabled = false
	yaw_before = player.rotation.y; pitch_before = player.pitch
	player._input(_motion(Vector2(50, 50)))
	_assert(is_equal_approx(player.rotation.y, yaw_before) and is_equal_approx(player.pitch, pitch_before), "UI中は視点停止")
	player.velocity = Vector3(2, player.velocity.y, 2)
	player._physics_process(1.0 / 60.0)
	_assert(is_zero_approx(player.velocity.x) and is_zero_approx(player.velocity.z), "UI中は移動停止")

	game.set_settings({"mouse_sensitivity":1.0,"invert_y":false})
	if FileAccess.file_exists(game.settings_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(game.settings_path))
	print("MOUSE_INPUT failures=",failures.size()," ratio=",sensitivity_two / maxf(sensitivity_half, 0.00001))
	for failure in failures: push_error("MOUSE_INPUT: " + failure)
	quit(1 if not failures.is_empty() else 0)

func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.screen_relative = relative
	return event

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)
