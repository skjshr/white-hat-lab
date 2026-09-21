extends SceneTree

var ui
var game
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(50).timeout.connect(func(): quit(2))
	call_deferred("run")

func frames(count: int = 6) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/workstations/chrome")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png"))

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	game.new_game({"company":"風の森セキュリティ","player":"春山","aya":"小川","ren":"星野"})
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_main_menu()
	await capture("title")
	game.choose_strategy("advisory"); game.start_free_career()
	game.state.cash=100000; game.state.credit=100000; game.state.skills={"advisory":5,"operations":5,"response":5}
	ui.controls.menu.hide(); ui.update_hud()
	for panel in ["shop","company","staffing"]:
		ui.open_panel(panel)
		await capture(panel)
		ui.modal_scroll.scroll_vertical=99999
		await capture(panel+"-bottom")
	ui.shop_view="stock"; ui.open_panel("shop"); await capture("stock")
	ui.open_panel("settings"); await capture("settings")
	ui._settings_tab("audio"); await capture("settings-audio")
	ui.queue_free(); await frames(3)
	print("GAME_CHROME_CAPTURE_PASS")
	quit(0)
