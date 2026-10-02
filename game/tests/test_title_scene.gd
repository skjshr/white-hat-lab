extends SceneTree

var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	call_deferred("run")

func run() -> void:
	var game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.new_game({"company":"風の森セキュリティ", "player":"春山", "aya":"小川", "ren":"星野"})
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed" if narrow else "borderless", "text_scale":1.3 if narrow else 1.0, "volume":0},false)
	var office = load("res://main.tscn").instantiate()
	root.add_child(office)
	root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	await create_timer(2.0).timeout
	var artwork = office.ui.controls.menu.find_child("TitleArtwork",true,false)
	if office.ui.controls.company_title.text != "ホワイトハッカーラボ":
		push_error("Title must use the user-selected name"); quit(1); return
	if artwork == null or artwork.texture.resource_path != "res://assets/ui/menu_backdrop.svg":
		push_error("Title must retain original background"); quit(1); return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/ui-refinement-20260922/screens" if "--refinement-capture" in OS.get_cmdline_user_args() else "res://../artifacts/simulator/v220/ui" if "--v220-capture" in OS.get_cmdline_user_args() else "res://../artifacts/simulator/ui-polish-20260922/after")
	if not OS.get_environment("WHL_CAPTURE_DIR").is_empty():
		folder = OS.get_environment("WHL_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join("title" + ("-narrow" if narrow else "-wide") + ".png"))
	print("TITLE_SCENE_OK original_background=true narrow=",narrow)
	quit(0)
