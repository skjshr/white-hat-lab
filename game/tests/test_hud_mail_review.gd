extends SceneTree

var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var office
var game

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("HUD_MAIL timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func frames(count := 5) -> void:
	for _i in count: await process_frame

func capture(id: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/hud-mail-review")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(id + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + id)

func check_focus() -> void:
	var count := 0
	for body in office.find_children("*", "StaticBody3D", true, false):
		if not body.has_meta("profile_name"): continue
		count += 1
		var id: String = body.get_meta("profile_name")
		var target: Vector3 = body.global_position
		var shape: BoxShape3D = body.get_child(0).shape
		if shape.size.x > 1.0: target += body.global_basis.x * 0.65
		# Look down on the actual collider to avoid the chair in front of a desk.
		office.player.camera.global_position = target + Vector3(0.0, 1.5, 0.4)
		office.player.camera.look_at(target, Vector3.UP)
		await physics_frame
		var hit: Dictionary = office.player.focus()
		var expected: String = (game.player_name() if id == "player" else game.member_name(id)) + str(body.get_meta("profile_label_suffix", ""))
		check(str(hit.get("label", "")) == expected, "current name at " + str(body.get_path()) + " expected=" + expected + " actual=" + str(hit))
	check(count == 8, "player and two coworker desks/monitors plus two coworkers checked")

func run() -> void:
	game = root.get_node("Game")
	check(str(game.save_path).begins_with("user://qa-"), "isolated save")
	if not failures.is_empty(): quit(1); return
	game.set_process(false)
	check(game.new_game(), "create isolated company")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	office = load("res://scripts/office.gd").new()
	root.add_child(office)
	await frames(12)
	office.set_process(false)
	office.player.set_physics_process(false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	# The office already exists, matching new-game setup and later profile edits.
	check(game.set_profile({"company":"確認会社", "player":"真白 / 主人公", "aya":"調査 花子", "ren":"復旧 太郎"}), "change names after world creation")
	await check_focus()
	check(game.set_profile({"player":"星野 あかり", "aya":"青葉 綾 / 主任", "ren":"蓮 復旧担当"}), "rename again with default-name substrings")
	check(game.load_game(), "reload saved names")
	await check_focus()
	office.ui.controls.menu.hide()
	office.ui.hud.show()
	office.player.camera.global_position = Vector3(-0.5,1.58,0.5)
	office.player.camera.look_at(Vector3(-0.5,1.04,-1.17), Vector3.UP)
	await physics_frame
	office.ui.set_focus_prompt("[ E ]  " + str(office.player.focus().get("label", "")))
	check(office.ui.prompt.text.contains("星野 あかり"), "actual HUD shows renamed player")
	await capture("hud-name")
	office.ui.open_panel("terminal")
	await frames()
	var pc = office.ui.desktop
	pc._show_app("mail")
	if not pc.windows.mail.maximized: pc.windows.mail.toggle_maximize()
	await frames()
	var selected := false
	for node in pc.widgets.mail.list.get_children():
		if node is BaseButton:
			node.pressed.emit(); selected = true; break
	check(selected, "select actual inbox message")
	await frames()
	var disclosure: BaseButton
	for node in pc.widgets.mail.body.get_children():
		if node is BaseButton and node.text.contains("添付"):
			disclosure = node; node.pressed.emit(); break
	check(disclosure != null, "expand attachment details")
	await frames()
	var chips: Array = pc.widgets.mail.body.find_children("*", "HFlowContainer", true, false)
	check(not chips.is_empty(), "attachment chips exist")
	for flow in chips:
		for panel in flow.get_children():
			if not panel is PanelContainer: continue
			var label: Label = panel.get_child(0)
			var text_width: float = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			print("CHIP text=", label.text, " size=", label.size, " text_width=", text_width, " flow=", flow.size)
			check(label.size.x >= text_width and label.get_line_count() == 1, "service chip has full single-line text")
	if disclosure != null:
		var scroll: ScrollContainer = pc.widgets.mail.body.get_parent()
		scroll.ensure_control_visible(disclosure)
		await frames()
		scroll.scroll_vertical = maxi(0, int(disclosure.position.y) - 20)
	await capture("mail-details")
	print("HUD_MAIL failures=", failures.size())
	office.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
