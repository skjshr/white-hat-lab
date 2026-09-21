extends SceneTree

var game: Node
var failures: Array[String] = []
var run_id: String = str(OS.get_process_id())

func _init() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.save_path = "user://rv19-delivery-%s.json" % run_id
	game.backup_path = "user://rv19-delivery-%s.json.bak" % run_id
	game.previous_path = "user://rv19-delivery-%s.previous.json" % run_id
	game.settings_path = "user://rv19-delivery-settings-%s.json" % run_id
	game._reset_state()
	game.state.cash = 10000
	_assert(game.buy_equipment("plant"), "注文を作成")
	_assert(game.state.equipment.is_empty(), "注文直後は未設置")
	_assert(game.delivery_for("plant").status == "queued", "注文はqueued")
	game.set_delivery_clock_enabled(true)
	game.advance_delivery(29.0)
	_assert(game.delivery_for("plant").status == "queued", "29秒では未着")
	game.advance_delivery(1.0)
	_assert(game.delivery_for("plant").status == "ready", "30秒で入口へ到着")
	_assert(not game.buy_equipment("plant"), "同一設備の注文重複拒否")
	_assert(game.take_delivery("plant"), "箱を取得")
	_assert(game.begin_delivery_placement("plant"), "設置モード")
	_assert(game.rotate_delivery("plant"), "R回転")
	_assert(game.place_delivery("plant", 0, PI / 2.0), "設置確定")
	_assert("plant" in game.state.equipment, "設置済み設備が効果対象")
	_assert(game.delivery_for("plant").is_empty(), "設置済みは未設置注文APIから除外")
	_assert(game.save_game() and game.load_game(), "設置状態を再開")
	_assert("plant" in game.state.equipment and game.delivery_for("plant").is_empty(), "再開後も設置済み")

	# Free placement and installed-item moving must not create a second purchase.
	_assert(game.begin_equipment_move("monitor") == false, "未設置/非対応設備の移動拒否")
	_assert(game.cancel_equipment_move("monitor") == false, "未設置/非対応設備の移動取消拒否")
	_assert(game.place_delivery_at("monitor", [1.5, 0.0, -0.1], 0.0) == false, "非対応設備の自由配置拒否")
	_assert(game.begin_equipment_move("plant"), "設置済み植物の移動開始")
	_assert(game.place_delivery_at("plant", [1.5, 0.0, -0.1], 0.35), "初回自由配置")
	var original := _plant_order()
	var original_position: Array = original.get("install_position", []).duplicate()
	var original_rotation := float(original.get("rotation_y", 0.0))
	var original_cash := int(game.state.cash)
	var original_order_count: int = game.state.delivery_orders.size()

	# The API must reject the world boundaries and the actual office obstacles.
	_assert(game.begin_equipment_move("plant"), "移動開始(拒否ケース)")
	_assert(game.place_delivery_at("plant", [6.2, 0.0, 0.0], 0.0) == false, "床の範囲外を拒否")
	_assert(game.place_delivery_at("plant", [-0.5, 0.0, -1.0], 0.0) == false, "机の上を拒否")
	_assert(game.place_delivery_at("plant", [2.8, 0.0, -1.35], 0.0) == false, "同僚の通路を拒否")
	_assert(game.cancel_equipment_move("plant"), "拒否後の移動取消")
	var canceled := _plant_order()
	_assert(_same_array(canceled.get("install_position", []), original_position), "取消で位置を保持")
	_assert(is_equal_approx(float(canceled.get("rotation_y", 0.0)), original_rotation), "取消で回転を復元")
	_assert(int(game.state.cash) == original_cash and game.state.delivery_orders.size() == original_order_count, "移動で購入/注文を増やさない")

	# Saving while moving must reload as one installed order at the old position.
	_assert(game.begin_equipment_move("plant"), "移動開始(再開ケース)")
	_assert(game.save_game() and game.load_game(), "移動中の保存再開")
	_assert(_installed_plant_count() == 1, "移動再開で重複しない")
	var reloaded_moving := _plant_order()
	_assert(str(reloaded_moving.get("status", "")) == "installed", "移動再開後は設置済み")
	_assert(_same_array(reloaded_moving.get("install_position", []), original_position), "移動再開で位置を保持")

	# A valid move persists its position and normalized rotation across reload.
	_assert(game.begin_equipment_move("plant"), "移動開始(成功ケース)")
	var moved_position: Array = [0.0, 0.0, 2.5]
	var moved_rotation := 1.1
	_assert(game.place_delivery_at("plant", moved_position, moved_rotation), "自由配置の移動確定")
	_assert(_same_array(_plant_order().get("install_position", []), moved_position), "移動位置を反映")
	_assert(is_equal_approx(float(_plant_order().get("rotation_y", 0.0)), moved_rotation), "移動回転を反映")
	_assert(game.save_game() and game.load_game(), "移動後の保存再開")
	_assert(_installed_plant_count() == 1, "移動後も注文重複なし")
	_assert(_same_array(_plant_order().get("install_position", []), moved_position), "移動位置を保存")
	_assert(is_equal_approx(float(_plant_order().get("rotation_y", 0.0)), moved_rotation), "移動回転を保存")

	# rotate_delivery changes the preview, while cancel restores the origin rotation.
	_assert(game.begin_equipment_move("plant"), "移動開始(回転取消ケース)")
	_assert(game.rotate_delivery("plant"), "移動中の回転")
	_assert(not is_equal_approx(float(_plant_order().get("rotation_y", 0.0)), moved_rotation), "移動中の回転を反映")
	_assert(game.cancel_equipment_move("plant"), "回転変更を取消")
	_assert(is_equal_approx(float(_plant_order().get("rotation_y", 0.0)), moved_rotation), "取消で移動前回転を復元")

	# Failed placement save restores the complete pre-transaction state.
	var good_save: String = game.save_path
	var good_backup: String = game.backup_path
	_assert(game.begin_equipment_move("plant"), "移動開始(保存失敗ケース)")
	# begin_equipment_move saves before the intentionally broken path is installed.
	var rollback_orders: Array = game.state.delivery_orders.duplicate(true)
	var rollback_equipment: Array = game.state.equipment.duplicate(true)
	game.save_path = "user://rv19-delivery-%s-missing/save.json" % run_id
	game.backup_path = "user://rv19-delivery-%s-missing/save.json.bak" % run_id
	_assert(game.place_delivery_at("plant", [3.8, 0.0, -1.5], 0.2) == false, "配置保存失敗を拒否")
	var rolled_back := _plant_order()
	_assert(game.state.delivery_orders == rollback_orders and game.state.equipment == rollback_equipment, "配置保存失敗で取引前状態を復元")
	_assert(int(game.state.cash) == original_cash, "配置保存失敗で資産を維持")
	var rollback_status := str(rolled_back.get("status", ""))
	game.save_path = good_save
	game.backup_path = good_backup
	_assert(game.cancel_equipment_move("plant"), "保存失敗後の移動取消")
	_assert(rollback_status == "placing" and _installed_plant_count() == 1, "取消後に設置済みへ復帰")

	game._reset_state()
	game.state.cash = 10000
	_assert(game.buy_equipment("monitor"), "再注文")
	var expected_cash := int(game.state.cash)
	game.save_path = "user://rv19-delivery-%s-missing-purchase/save.json" % run_id
	game.backup_path = "user://rv19-delivery-%s-missing-purchase/save.json.bak" % run_id
	_assert(not game.buy_equipment("backup"), "保存失敗を拒否")
	_assert(int(game.state.cash) == expected_cash and game.delivery_for("backup").is_empty(), "保存失敗rollback")

	game._reset_state()
	game.state.equipment = ["diagnostic"]
	game.save_path = "user://rv19-delivery-%s-migrate.json" % run_id
	game.backup_path = "user://rv19-delivery-%s-migrate.json.bak" % run_id
	_assert(game.save_game() and game.load_game(), "旧状態を再開")
	_assert(game.delivery_for("diagnostic").is_empty() and game.state.delivery_orders.size() == 1, "旧equipmentを設置済みに移行")
	_assert(game.state.delivery_orders[0].install_slot == 4, "購入順序によらず旧診断設備の配置位置を保持")

	for failure in failures: push_error("RV_DELIVERY: " + failure)
	print("PASS: RV delivery order/wait/carry/install/recovery" if failures.is_empty() else "FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _plant_order() -> Dictionary:
	for raw in game.state.delivery_orders:
		if str(raw.get("id", "")) == "plant": return raw
	return {}

func _installed_plant_count() -> int:
	var count := 0
	for raw in game.state.delivery_orders:
		if str(raw.get("id", "")) == "plant" and str(raw.get("status", "")) == "installed": count += 1
	return count

func _same_array(a: Variant, b: Variant) -> bool:
	if not (a is Array and b is Array) or a.size() != b.size(): return false
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])): return false
	return true
