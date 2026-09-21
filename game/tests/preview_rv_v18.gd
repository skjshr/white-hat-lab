extends SceneTree

var game
var office
var output := ""
var narrow := false

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): print("FAIL: RV preview timed out"); quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg == "--narrow": narrow = true
	output = ProjectSettings.globalize_path("res://../artifacts/simulator/v18")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func frames(count := 6) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var path := output.path_join(label+("-narrow" if narrow else "-wide")+".png")
	var error := root.get_texture().get_image().save_png(path)
	print("RV18_CAPTURE ",path," error=",error)

func run() -> void:
	game = root.get_node("Game")
	game.save_path = "user://preview_rv18_"+str(OS.get_process_id())+".json"
	game.backup_path = game.save_path+".bak"
	game.previous_path = game.save_path+".previous"
	game.settings_path = game.save_path+".settings"
	game.new_game({"company":"風の森セキュリティ","player":"春山","aya":"小川","ren":"星野"})
	game.state.ui_help_seen = {"legacy":true}
	game.set_settings({"quality":"medium","resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed" if narrow else "fullscreen","text_scale":1.3 if narrow else 1.0,"render_scale":1.0,"max_fps":60,"volume":0},false)
	office = load("res://scripts/office.gd").new()
	root.add_child(office)
	await frames(12)
	office.ui.controls.menu.hide()
	game.choose_strategy("advisory")
	office._start()
	game.start_free_career()
	office.ui.open_panel("board")
	await capture("cases")
	var first_id: String = str(game.state.offers[0].id)
	office.ui._select_contract(first_id)
	await capture("case-detail")
	office.ui.open_panel("company")
	await capture("skills")
	office.ui.open_panel("shop")
	await capture("shop")
	game.choose_contract(first_id)
	office.ui.open_panel("terminal")
	var desktop = office.ui.desktop
	desktop.widgets.mail.reading = true
	desktop._refresh_mail()
	await capture("mail")
	desktop._run_command("ssh client")
	desktop._show_app("files")
	desktop._file_location(true,"/etc/samba")
	await capture("files")
	desktop._open_config()
	desktop.editor.text += "# 保存前の調査メモ\n"
	desktop._show_app("terminal")
	desktop._show_app("files")
	await capture("multiple-windows")
	if desktop.has_method("_tile_windows"):
		desktop._tile_windows()
		await capture("tiled-windows")
	if desktop.has_method("_toggle_overview"):
		desktop._toggle_overview()
		await capture("app-overview")
		desktop._toggle_overview()
	desktop._show_app("editor")
	print("RV18_DRAFT_PRESERVED ",desktop.editor.text.contains("保存前の調査メモ"))
	for app in ["terminal","editor","browser","monitor","verify","team","manual","receipt"]:
		desktop._show_app(app)
		await capture("app-"+app)
	office.ui.close_panel(false)
	await frames(3)
	office.ui.root.hide()
	office.player.enabled = false
	office.player.camera.global_position = Vector3(-4.0,1.62,0.5)
	office.player.camera.look_at(Vector3(-14,1.8,-1.5),Vector3.UP)
	await capture("window-morning")
	if game.state.has("clock_minutes"):
		game.state.clock_minutes = 17*60+30
		game.changed.emit()
	await frames(80)
	await capture("window-evening")
	office.queue_free()
	await frames(3)
	quit(0)
