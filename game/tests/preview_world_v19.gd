extends SceneTree
var office
func _init() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	call_deferred("run")
func shot(name: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../artifacts/simulator/v19/"+name+".png")
	root.get_texture().get_image().save_png(path)
	print("WORLD19_CAPTURE ",name)
func run() -> void:
	var game = root.get_node("Game")
	game.new_game({"company":"風の森セキュリティ","player":"春山","aya":"小川","ren":"星野"})
	game.set_settings({"quality":"medium","resolution":"1600x900","window_mode":"windowed","render_scale":1.0,"text_scale":1.0,"volume":0},false)
	office=load("res://scripts/office.gd").new();root.add_child(office)
	await process_frame
	office.ui.controls.menu.hide(); office.ui.hud.hide();office.started=true
	office.ui.current_kind=""
	office.player.position=Vector3(-3.7,0.05,1.8)
	office.player.camera.look_at(Vector3(-22,2.7,-4),Vector3.UP)
	await shot("street-day")
	office.player.set_coffee_visible(true)
	await shot("left-hand-carry")
	var sip:Tween=office.player.animate_coffee_drink()
	await create_timer(1.10).timeout
	await shot("left-hand-sip")
	await sip.finished
	office.player.set_coffee_visible(false)
	game.state.clock_minutes=1050
	office._update_daylight()
	await shot("street-evening")
	quit()
