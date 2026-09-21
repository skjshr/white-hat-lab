extends SceneTree

var game: Node
var office: Node3D
var failures: Array[String] = []
var previews: Array[Texture2D] = []
var narrow := false

func _init() -> void:
	narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func(): push_error("Workstation monitor timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count: int = 5) -> void:
	for _i in count: await process_frame

func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/workstations/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	check(root.get_texture().get_image().save_png(folder.path_join(label + suffix + ".png")) == OK, "capture " + label)

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-workstation-"):
		push_error("Workstation QA needs isolated profile"); quit(2); return
	game.set_process(false)
	check(game.new_game(), "new isolated game")
	check(game.choose_strategy("advisory") and game.start_free_career(), "start isolated company")
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked",false)) and bool(item.get("market_available",true)))
	check(not offers.is_empty() and game.choose_contract(str(offers[0].id)), "real customer work accepted")
	game.settings.text_scale = 1.3 if narrow else 1.0
	office = load("res://scripts/office.gd").new()
	root.add_child(office)
	await frames(12)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	await frames(5)
	office.started = true
	office.ui.controls.menu.hide()
	office.ui.current_kind = ""
	office.player.set_physics_process(false)
	office.player.position = Vector3(-0.5,0.05,0.5)
	office.player.camera.look_at(Vector3(-0.5,1.02,-1.1), Vector3.UP)
	office.ui.desktop_preview_ready.connect(func(texture): previews.append(texture))
	await capture("01-player-workstation")
	office.ui.open_panel("terminal")
	office.ui.desktop._show_app("editor")
	await frames(8)
	check(bool(office.ui._desktop_preview_drawn), "desktop has been presented")
	await capture("02-live-editor")
	var desktop_frame: Image = root.get_texture().get_image()
	var source_rect: Rect2 = office.ui.desktop.get_global_rect()
	var ratio := Vector2(desktop_frame.get_size()) / root.get_visible_rect().size
	var expected: Image = desktop_frame.get_region(Rect2i(source_rect.position * ratio, source_rect.size * ratio))
	if expected.get_width() > 1024:
		expected.resize(1024, maxi(1, roundi(float(expected.get_height()) * 1024.0 / expected.get_width())), Image.INTERPOLATE_LANCZOS)
	check(office.ui.close_panel(false, false), "close saves desktop")
	check(previews.size() == 1, "one real frame passed to monitor")
	if not previews.is_empty():
		var captured: Image = previews.back().get_image()
		check(captured.get_size() == expected.get_size() and captured.get_data() == expected.get_data(), "monitor image equals presented desktop frame")
	await capture("03-editor-on-monitor")
	check(is_instance_valid(office.player_desk_label) and office.player_desk_label.billboard == BaseMaterial3D.BILLBOARD_DISABLED and office.player_desk_label.position.y < 1.0, "nameplate is fixed to desk")
	check(not is_instance_valid(office.status_screen) or not office.status_screen.visible, "no floating status in front of monitor")
	# Switching UI panels never gives control back to the captured gameplay mouse.
	office.ui.open_panel("terminal")
	office.ui.desktop._show_app("files")
	await frames(8)
	var pointer := DisplayServer.mouse_get_position()
	office.ui.open_panel("company")
	await frames(3)
	print("POINTER before=", pointer, " after=", DisplayServer.mouse_get_position(), " mode=", Input.mouse_mode)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "UI transition retains visible pointer mode")
	check(DisplayServer.mouse_get_position() == pointer, "UI transition preserves pointer position")
	check(previews.size() == 2, "UI transition retains last actual desktop")
	check(office.ui.close_panel(false,false), "close management view")
	await capture("04-files-on-monitor")
	# Failed persistence must retain the desktop and the previous monitor image.
	office.ui.open_panel("terminal")
	await frames(6)
	var good_path: String = game.save_path
	game.save_path = "user://missing-workstation-save/blocked.json"
	check(not office.ui.close_panel(false,false), "save failure keeps desktop open")
	check(previews.size() == 2 and is_instance_valid(office.ui.desktop), "failed close emits no replacement")
	game.save_path = good_path
	check(office.ui.close_panel(false,false), "successful retry closes desktop")
	game.assign_colleague("aya")
	check(str(game.state.assignments.get("aya",{}).get("status","")) == "working", "real staff assignment starts")
	office.player.position = Vector3(-3.8,0.05,-0.7)
	office.player.camera.look_at(Vector3(-3.6,1.05,-2.4), Vector3.UP)
	await create_timer(1.2).timeout
	await capture("05-staff-workstation")
	check(office.monitors.has("aya"), "staff monitor attached")
	print("WORKSTATION_MONITOR failures=", failures.size())
	office.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
