extends SceneTree

const STOCK_PREFIX := "stock-"

var game: Node
var office: Node3D
var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(65.0).timeout.connect(func(): push_error("Stock world QA timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 4) -> void:
	for _i in count:
		await process_frame

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(5)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/procurement/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	check(root.get_texture().get_image().save_png(folder.path_join(label + suffix + ".png")) == OK, "capture "+label)

func press_interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	office._unhandled_input(event)

func _offer_for_stock(sku: String = "gateway") -> Dictionary:
	for offer in game.state.get("offers", []):
		if sku == "gateway" and str(offer.get("case_id", "")) == "hardware-gateway-install": return offer
		if sku == "backup_appliance" and str(offer.get("case_id", "")) == "hardware-backup-install": return offer
	return {}

func _unit(id: String) -> Dictionary:
	return game.customer_stock_for(id) if game.has_method("customer_stock_for") else {}

func _stock_ids(sku: String = "") -> Array[String]:
	var result: Array[String] = []
	for unit in game.customer_stock_units():
		var id := str(unit.get("id", ""))
		if id.begins_with(STOCK_PREFIX) and (sku.is_empty() or str(unit.get("sku", "")) == sku): result.append(id)
	return result

func _aim(point: Vector3, from_point: Vector3) -> Dictionary:
	office.player.global_position = from_point
	office.player.camera.look_at(point, Vector3.UP)
	await frames(2)
	return office.player.focus()

func _refresh_focus() -> Dictionary:
	await frames(2)
	office._process(0.016)
	return office.focused

func _setup_career() -> bool:
	if not game.save_path.begins_with("user://qa-stock-world-"):
		push_error("Refusing stock world QA without isolated storage")
		return false
	check(game.new_game(), "fresh QA game")
	check(game.choose_strategy("advisory"), "choose strategy")
	check(game.start_free_career(), "start career")
	# This is a legitimate progression fixture: it grants the level and skill
	# needed for the catalog offer, while the real contract and stock APIs do
	# all acceptance, purchase, save, and association work.
	game.state.skills.advisory = 1
	game.state.skills.operations = 1
	game.state.peak_profit = 3000
	game.state.cash = 30000
	game.state.market_leads = ["hardware-gateway-install"]
	game.state.market_day = int(game.state.day)
	game._make_offers()
	var offer := _offer_for_stock()
	check(not offer.is_empty() and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)), "gateway offer is a real current lead")
	var backup_products: Array = game.customer_stock_catalog().filter(func(item): return str(item.get("sku", "")) == "backup_appliance")
	check(backup_products.size() == 1 and str(backup_products[0].get("model", "")) == "WHB-2" and ResourceLoader.exists("res://assets/props/customer-appliances/backup.glb"), "backup appliance catalog and asset are available")
	if offer.is_empty(): return false
	check(game.choose_contract(str(offer.get("id", ""))), "accept gateway commissioning contract")
	return bool(game.state.get("accepted", false)) and str(game.state.get("contract", {}).get("case_id", "")) == "hardware-gateway-install"

func run() -> void:
	await frames(1)
	game = root.get_node("Game")
	game.set_process(false)
	if not await _setup_career():
		quit(1)
		return
	var gateway_contract_id := str(game.state.current_contract_id)
	var backup_buy: Dictionary = game.buy_customer_stock(1, "backup_appliance")
	check(bool(backup_buy.get("ok", false)) and backup_buy.get("ids", []).size() == 1, "buy one backup appliance through procurement")
	var buy: Dictionary = game.buy_customer_stock(2)
	check(bool(buy.get("ok", false)) and buy.get("ids", []).size() == 2, "buy two gateway units through procurement")
	var ids := _stock_ids("gateway")
	check(ids.size() == 2 and _stock_ids("backup_appliance").size() == 1, "serialised multi-SKU stock units exist")
	check(game.advance_delivery(30.0), "advance inbound delivery")
	await frames(3)
	var ready: Array = game.customer_stock_units().filter(func(item): return str(item.get("status", "")) == "ready")
	check(ready.size() == 3, "all appliance units arrive ready")

	office = load("res://scripts/office.gd").new()
	root.add_child(office)
	await frames(8)
	office.started = true
	office.ui.controls.menu.hide()
	office.ui.current_kind = ""
	office.ui.root.hide()
	office.player.enabled = true
	office.player.set_physics_process(false)
	await frames(3)
	check(office.delivery != null and office.delivery._boxes.size() >= 3, "world renders all ready cartons")
	var first_id := ids[0]
	var first_box: Node3D = office.delivery._boxes.get(first_id) as Node3D
	check(is_instance_valid(first_box) and bool(first_box.get_meta("stock_box", false)), "receiving carton keeps stock metadata")
	check(is_instance_valid(first_box) and absf(first_box.scale.x - 0.5) < 0.01, "receiving carton uses half scale")
	if not is_instance_valid(first_box):
		quit(1)
		return
	var empty_shelf_focus: Dictionary = await _aim(Vector3(5.4,0.62,0.695), Vector3(4.1,0.05,0.695))
	check(str(empty_shelf_focus.get("action", "")) == "stock_shelf", "empty-handed shelf focus is real")
	office.focused = empty_shelf_focus
	press_interact()
	await frames(3)
	check(str(office.ui.get("shop_view")) == "stock" and str(office.ui.current_kind) == "shop", "empty-handed shelf opens stock pane")
	office.ui.close_panel(false, false)
	office.ui.root.hide()
	office.ui.controls.menu.hide()
	office.player.enabled = true
	var receiving_focus: Dictionary = await _aim(first_box.global_position + Vector3(0,0.08,0), first_box.global_position + Vector3(-1.2,0.0,0))
	check(str(receiving_focus.get("action", "")) == "delivery_box" and str(receiving_focus.get("delivery_id", "")) == first_id, "real ray focus reaches receiving carton")
	office.focused = receiving_focus
	press_interact()
	await frames(3)
	check(str(_unit(first_id).get("status", "")) == "carried", "E picks up receiving carton")
	check(absf(float(office.delivery._boxes[first_id].scale.x) - 0.5) < 0.01, "carried carton remains half scale")
	await capture("01-receiving-carried")

	var shelf_focus: Dictionary = await _aim(Vector3(5.4,0.62,0.695), Vector3(4.1,0.05,0.695))
	check(str(shelf_focus.get("action", "")) == "stock_shelf", "real ray focus reaches stock shelf")
	office.focused = shelf_focus
	await _refresh_focus()
	check(str(office.focused.get("action", "")) == "stock_store", "carried stock maps shelf focus to store action")
	press_interact()
	await frames(3)
	check(str(_unit(first_id).get("status", "")) == "stored", "E stores carton on shelf")
	check(int(_unit(first_id).get("shelf_slot", -1)) >= 0, "stored carton has shelf slot")
	await capture("02-shelf-stored")
	var buy_more_a: Dictionary = game.buy_customer_stock(1)
	var buy_more_b: Dictionary = game.buy_customer_stock(2)
	check(bool(buy_more_a.get("ok", false)) and bool(buy_more_b.get("ok", false)) and buy_more_a.get("ids", []).size() + buy_more_b.get("ids", []).size() == 3, "buy remaining three gateway units through procurement")
	ids = _stock_ids()
	check(ids.size() == 6 and _stock_ids("gateway").size() == 5, "six serialised mixed-SKU units exist at capacity")
	check(game.advance_delivery(30.0), "advance remaining inbound delivery")
	await frames(4)
	for shelf_id in ids:
		if shelf_id == first_id: continue
		var shelf_box: Node3D = office.delivery._boxes.get(shelf_id) as Node3D
		check(is_instance_valid(shelf_box), "remaining carton rendered %s" % shelf_id)
		if not is_instance_valid(shelf_box): continue
		var shelf_receive_focus: Dictionary = await _aim(shelf_box.global_position + Vector3(0,0.08,0), shelf_box.global_position + Vector3(-1.2,0.0,0))
		check(str(shelf_receive_focus.get("action", "")) == "delivery_box" and str(shelf_receive_focus.get("delivery_id", "")) == shelf_id, "receiving focus reaches %s" % shelf_id)
		office.focused = shelf_receive_focus
		press_interact()
		await frames(2)
		check(str(_unit(shelf_id).get("status", "")) == "carried", "pickup %s" % shelf_id)
		var shelf_store_focus: Dictionary = await _aim(Vector3(5.4,0.62,0.695), Vector3(4.1,0.05,0.695))
		office.focused = shelf_store_focus
		await _refresh_focus()
		check(str(office.focused.get("action", "")) == "stock_store", "shelf action maps for %s" % shelf_id)
		press_interact()
		await frames(2)
		check(str(_unit(shelf_id).get("status", "")) == "stored", "store %s" % shelf_id)
	await capture("02b-shelf-all-six")

	var stored_box: Node3D = office.delivery._boxes.get(first_id) as Node3D
	check(is_instance_valid(stored_box), "stored carton remains visible")
	var stored_focus: Dictionary = await _aim(stored_box.global_position + Vector3(0,0.05,0), stored_box.global_position + Vector3(-1.0,0.1,0))
	check(str(stored_focus.get("action", "")) == "delivery_box" and str(stored_focus.get("delivery_id", "")) == first_id, "real ray focus reaches stored carton")
	office.focused = stored_focus
	press_interact()
	await frames(3)
	check(str(_unit(first_id).get("status", "")) == "carried", "E repicks stored carton")

	var terminal_focus: Dictionary = await _aim(Vector3(-0.5,1.04,-1.17), Vector3(-1.8,0.05,-1.17))
	check(str(terminal_focus.get("action", "")) == "terminal", "real ray focus reaches setup terminal")
	office.focused = terminal_focus
	await _refresh_focus()
	check(str(office.focused.get("action", "")) == "stock_stage", "carried stock maps terminal focus to stage action")
	press_interact()
	await frames(3)
	var staged := _unit(first_id)
	check(str(staged.get("status", "")) == "staged", "E stages carton at setup bench")
	check(str(staged.get("contract_id", "")) == str(game.state.current_contract_id) and int(staged.get("target_index", -1)) == int(game.state.target_index), "stage binds current commissioning target")
	var staged_box: Node3D = office.delivery._boxes.get(first_id) as Node3D
	check(is_instance_valid(staged_box), "staged carton remains visible on bench")
	if is_instance_valid(staged_box):
		check(bool(staged_box.get_meta("stock_appliance", false)) and str(staged_box.get_meta("stock_state", "")) == "staged", "staged stock swaps to appliance presentation")
		check(staged_box.find_children("*", "CollisionShape3D", true, false).size() > 0, "staged appliance has physical collision")
		check(staged_box.get_node_or_null("MeshInstance3D") == null, "staged appliance removes carton mesh")
		var appliance_meshes: Array = staged_box.find_children("*", "MeshInstance3D", true, false)
		var transformed_bounds: AABB = office._bounds(staged_box)
		check(not appliance_meshes.is_empty() and absf(transformed_bounds.size.x - 0.40) < 0.01 and absf(transformed_bounds.size.y - 0.093) < 0.01 and absf(transformed_bounds.position.y - 0.79) < 0.01, "gateway rendered dimensions and feet align with bench")
		var staged_focus: Dictionary = await _aim(staged_box.global_position + Vector3(0,-0.08,0), Vector3(0.7,0.05,0.1))
		check(str(staged_focus.get("action", "")) == "delivery_box" and str(staged_focus.get("delivery_id", "")) == first_id, "real ray focus reaches staged carton")
		await capture("03-setup-bench-staged")
		office.focused = staged_focus
		press_interact()
		await frames(3)
		check(str(_unit(first_id).get("status", "")) == "carried", "E picks up staged carton for dispatch")
		check(game.put_down_delivery(first_id, [3.4, 0.26, 3.7]), "put down gateway before backup staging")
		await frames(3)
		game.state.market_day = int(game.state.day)
		game.state.market_leads.append("hardware-backup-install")
		game._make_offers()
		var backup_offer := _offer_for_stock("backup_appliance")
		check(not backup_offer.is_empty() and bool(backup_offer.get("market_available",false)) and bool(backup_offer.get("unlocked",false)), "backup lead is available and unlocked")
		var backup_quote: Dictionary = game.contract_quote(backup_offer)
		check(game.set_offer_quote(str(backup_offer.get("id", "")), mini(int(backup_quote.quoted_fee), int(backup_quote.budget_limit))) and game.choose_contract(str(backup_offer.get("id", ""))), "accept backup commissioning contract")
		await frames(3)
		var backup_ids := _stock_ids("backup_appliance")
		var backup_id := str(backup_ids[0]) if not backup_ids.is_empty() else ""
		var backup_box: Node3D = office.delivery._boxes.get(backup_id) as Node3D
		check(is_instance_valid(backup_box), "backup carton is rendered")
		if is_instance_valid(backup_box):
			var backup_focus: Dictionary = await _aim(backup_box.global_position + Vector3(0,0.05,0), backup_box.global_position + Vector3(-1.0,0.1,0))
			check(str(backup_focus.get("action", "")) == "delivery_box" and str(backup_focus.get("delivery_id", "")) == backup_id, "real ray reaches backup carton")
			office.focused = backup_focus; press_interact(); await frames(3)
			check(str(_unit(backup_id).get("status", "")) == "carried", "E picks up backup carton")
			var backup_stage_focus: Dictionary = await _aim(Vector3(-0.5,1.04,-1.17), Vector3(-1.8,0.05,-1.17))
			office.focused = backup_stage_focus; await _refresh_focus(); press_interact(); await frames(3)
			var backup_staged := _unit(backup_id)
			check(str(backup_staged.get("status", "")) == "staged", "backup appliance stages at setup bench")
			var backup_staged_box: Node3D = office.delivery._boxes.get(backup_id) as Node3D
			check(is_instance_valid(backup_staged_box) and bool(backup_staged_box.get_meta("stock_appliance", false)) and str(backup_staged_box.get_meta("sku", "")) == "backup_appliance", "backup uses appliance presentation")
			if is_instance_valid(backup_staged_box):
				var backup_bounds: AABB = office._bounds(backup_staged_box)
				check(absf(backup_bounds.size.x - 0.21) < 0.01 and absf(backup_bounds.size.y - 0.29) < 0.01 and absf(backup_bounds.position.y - 0.79) < 0.01, "backup rendered dimensions and feet align with bench")
				check(backup_staged_box.find_children("*", "CollisionShape3D", true, false).size() > 0, "backup appliance has physical collision")
				check(not backup_staged_box.find_children("*", "MeshInstance3D", true, false).is_empty(), "backup appliance GLB is visible")
				var backup_front: Dictionary = await _aim(backup_staged_box.global_position + Vector3(0,0.06,0), Vector3(0.7,0.05,0.1))
				check(str(backup_front.get("action", "")) == "delivery_box" and str(backup_front.get("delivery_id", "")) == backup_id, "front three-quarter ray reaches backup appliance")
				await capture("03b-backup-staged-front")
				office.focused = backup_front; press_interact(); await frames(3)
				check(str(_unit(backup_id).get("status", "")) == "carried", "E picks up staged backup appliance")
			check(game.put_down_delivery(backup_id, [2.4, 0.16, 3.7]), "put down backup before gateway work")
		check(game.switch_contract(gateway_contract_id), "return to gateway contract after backup proof")
		await frames(3)
		var gateway_box_after_backup: Node3D = office.delivery._boxes.get(first_id) as Node3D
		if is_instance_valid(gateway_box_after_backup):
			var gateway_pickup_focus: Dictionary = await _aim(gateway_box_after_backup.global_position + Vector3(0,0.08,0), Vector3(2.5,0.7,3.0))
			office.focused = gateway_pickup_focus; press_interact(); await frames(3)
			check(str(_unit(first_id).get("status", "")) == "carried", "re-pick gateway for dispatch gate")

	var door_focus: Dictionary = await _aim(Vector3(4.7,1.25,4.75), Vector3(3.5,0.05,3.7))
	check(str(door_focus.get("action", "")) == "door", "real ray focus reaches dispatch door")
	office.focused = door_focus
	await _refresh_focus()
	check(str(office.focused.get("action", "")) == "stock_dispatch", "staged stock maps door focus to dispatch action")
	press_interact()
	await frames(3)
	check(str(_unit(first_id).get("status", "")) == "carried", "premature dispatch is rejected before verification")
	check(str(office.delivery.stock_error()) == "checks", "premature dispatch exposes stable stock error")
	await capture("04-dispatch-gate")
	check(game.state.get("equipment", []).is_empty(), "customer stock never mutates permanent office equipment")
	check(game.state.get("delivery_orders", []).is_empty(), "customer stock never enters legacy delivery orders")
	for failure in failures: push_error("STOCK_WORLD: "+failure)
	print("STOCK_WORLD failures=", failures.size(), " ids=", ids)
	quit(0 if failures.is_empty() else 1)
