extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var game: Node = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.save_path = "user://rv19-node.json"
	game.backup_path = "user://rv19-node.json.bak"
	game._reset_state(); game.state.cash = 10000; game.buy_equipment("plant")
	game.advance_delivery(30.0)
	var delivery: Node3D = load("res://scripts/equipment_delivery.gd").new()
	root.add_child(delivery)
	delivery.setup(game, [Vector3(1, 0, 1), Vector3(2, 0, 1), Vector3(3, 0, 1), Vector3(1, 0, 2), Vector3(2, 0, 2), Vector3(3, 0, 2)])
	_assert(delivery.get_child_count() == 1, "入口箱を生成")
	var first_box: Node = delivery.get_child(0)
	_assert(first_box is StaticBody3D and first_box.get_meta("delivery_id") == "plant", "StaticBodyとdelivery_id")
	delivery.sync_orders(game.delivery_orders())
	_assert(delivery.get_child(0) == first_box, "同一状態のsyncは差分維持")
	_assert(delivery.interact("pickup", "plant"), "箱を取得")
	delivery.sync_orders(game.delivery_orders())
	_assert(delivery.get_child(0).visible, "持ち運び箱を表示")
	_assert(delivery.interact("place_start", "plant", 0), "ゴースト開始")
	_assert(delivery.get_child_count() >= 2, "設置ゴースト生成")
	delivery.interact("rotate", "plant")
	delivery.update_placement_preview([-1.0, 0.0, -3.4], 1.5707963)
	_assert(delivery.placement_valid(), "自由配置プレビュー")
	_assert(delivery.interact("confirm", "plant"), "設置確定")
	var placed: Dictionary = {}
	for order in game.delivery_orders():
		if str(order.get("id",""))=="plant":placed=order
	_assert(str(placed.get("status", "")) == "installed" and placed.get("install_position", []).size() == 3, "保存位置")
	_assert(absf(float(placed.get("rotation_y", 0.0)) - 1.5707963) < 0.01, "保存回転")
	for failure in failures: push_error("DELIVERY_NODE: " + failure)
	print("PASS: delivery node diff/collision/carry/ghost" if failures.is_empty() else "FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)
