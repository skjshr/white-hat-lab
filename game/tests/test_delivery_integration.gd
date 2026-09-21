extends SceneTree

const DELIVERY = preload("res://scripts/equipment_delivery.gd")
var failures: Array[String] = []

func _init() -> void:
	await process_frame
	var game := root.get_node("Game")
	game.save_path = "user://delivery_integration_qa.json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	_assert(game.new_game(), "new game")
	var delivery := DELIVERY.new()
	root.add_child(delivery)
	delivery.setup(game, [Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(2,0,1)])
	_assert(delivery.allowed_slot("plant") == 0 and delivery.allowed_slot("backup") == 1 and delivery.allowed_slot("monitor") == 2, "equipment slot map is explicit")
	_assert(delivery.allowed_slot("workstation") == 3 and delivery.allowed_slot("diagnostic") == 4 and delivery.allowed_slot("teamdesk") == 5, "all equipment slots are distinct")
	_assert(game.buy_equipment("plant"), "purchase creates one queued order")
	game.advance_delivery(999.0)
	delivery.sync_orders(game.delivery_orders())
	_assert(str(game.delivery_for("plant").get("status", "")) == "ready", "delivery arrives at receiving point")
	_assert(delivery.interact("pickup", "plant"), "E pickup")
	_assert(delivery.carried_id() == "plant", "box is carried")
	_assert(delivery.interact("put_down", "plant", -1, [1.2, 0.35, 1.2]), "right click puts box on safe floor")
	_assert(str(game.delivery_for("plant").get("status", "")) == "ready", "put down returns to ready")
	_assert(game.save_game() and game.load_game(), "save/reload carried box state")
	delivery.sync_orders(game.delivery_orders())
	_assert(str(game.delivery_for("plant").get("status", "")) == "ready", "saved box remains recoverable")
	_assert(delivery._boxes.has("plant"), "saved box is recreated")
	_assert(delivery.interact("pickup", "plant"), "re-pickup after put down")
	_assert(delivery.interact("place_start", "plant"), "start placement")
	_assert(delivery.can_confirm_from(Vector3(4,0,0), "plant") == false, "placement requires nearby player")
	_assert(delivery.can_confirm_from(Vector3(0,0,0), "plant"), "placement accepts nearby player")
	delivery.set_placement_slot(1)
	_assert(delivery._placing_slot == 0, "plant cannot use another equipment slot")
	_assert(delivery.interact("rotate", "plant"), "R rotates")
	var persisted_rotation := float(game.delivery_for("plant").get("rotation_y", 0.0))
	_assert(is_equal_approx(delivery._placing_rotation, persisted_rotation), "ghost rotation follows persisted R angle")
	delivery.update_placement_preview([1.5, 0.0, -0.1], persisted_rotation)
	_assert(delivery.placement_valid(), "free placement preview accepts valid floor")
	_assert(is_equal_approx(delivery._ghost.rotation.y, persisted_rotation), "ghost keeps preview rotation")
	_assert(not ("plant" in game.state.equipment), "effect is not active before installation")
	_assert(delivery.interact("confirm", "plant"), "left click installs")
	_assert("plant" in game.state.equipment, "installed effect is active")
	_assert(str(game.delivery_for("plant").get("status", "")) == "", "installed order is no longer pending")
	var installed_order: Dictionary = {}
	for order in game.delivery_orders():
		if str(order.get("id", "")) == "plant": installed_order = order
	_assert(is_equal_approx(float(installed_order.get("rotation_y", 0.0)), persisted_rotation), "installed order preserves R angle")
	_assert(Vector2(float(installed_order.get("install_position", [0,0,0])[0]), float(installed_order.get("install_position", [0,0,0])[2])).distance_to(Vector2(1.5,-0.1)) < 0.01, "installed order preserves free position")
	_assert(game.save_game() and game.load_game(), "save/reload installed delivery")
	var restored_installed := false
	for order in game.delivery_orders():
		if str(order.get("id", "")) == "plant" and str(order.get("status", "")) == "installed": restored_installed = true
	_assert(restored_installed and "plant" in game.state.equipment, "installed effect survives reload")
	for failure in failures: push_error("DELIVERY_INTEGRATION: " + failure)
	print("DELIVERY_INTEGRATION failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)
