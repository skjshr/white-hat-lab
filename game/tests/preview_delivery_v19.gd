extends SceneTree

var office: Node
var game: Node
var delivery: Node
var out_dir := "res://../artifacts/simulator/v19-delivery"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	await process_frame
	office = load("res://scripts/office.gd").new()
	office.name = "DeliveryPreviewOffice"
	root.add_child(office)
	await _frames(12)
	game = root.get_node("Game")
	game.save_path = "user://delivery_preview_qa.json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	game.new_game()
	office._start()
	if office.ui.current_kind != "": office.ui.close_panel(false)
	if office.ui.controls.has("menu"): office.ui.controls.menu.hide()
	delivery = office.delivery
	game.buy_equipment("plant")
	game.set_delivery_clock_paused(false)
	game.advance_delivery(999.0)
	delivery.sync_orders(game.delivery_orders())
	print("DELIVERY_PREVIEW orders=", game.delivery_orders(), " boxes=", delivery._boxes.keys())
	office.player.enabled = false
	office.player.camera.global_position = Vector3(3.4, 1.5, 2.5)
	office.player.camera.look_at(Vector3(3.4, 0.45, 3.7), Vector3.UP)
	await _frames(8)
	await _capture("01-ready-box")
	delivery.interact("pickup", "plant")
	await _frames(8)
	await _capture("02-carried-box")
	delivery.interact("place_start", "plant")
	office.player.camera.global_position = Vector3(-4.0, 1.2, 0.4)
	office.player.camera.look_at(Vector3(-5.2, 0.6, 0.4), Vector3.UP)
	await _frames(8)
	await _capture("03-placement-ghost")
	delivery.interact("rotate", "plant")
	delivery.interact("confirm", "plant")
	await _frames(8)
	await _capture("04-installed")
	print("DELIVERY_PREVIEW captures=4")
	quit(0)

func _frames(count: int) -> void:
	for i in count: await process_frame

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(out_dir).path_join(label + ".png")
	var image := root.get_viewport().get_texture().get_image()
	print("DELIVERY_CAPTURE ", path, " error=", image.save_png(path))
