extends Node3D
class_name EquipmentDelivery

const EQUIPMENT_ART := preload("res://scripts/equipment_art.gd")
const EQUIPMENT_VISUALS := preload("res://scripts/equipment_visuals.gd")
const PLACEMENT_RULES := preload("res://scripts/placement_rules.gd")
const UI := preload("res://scripts/ui_theme.gd")

## World-facing delivery presentation. Game remains the persistence authority;
## this node only creates boxes/ghosts and forwards player interactions.
signal delivery_changed

const BOX_RECEIVING_POINT := Vector3(3.4, 0.26, 3.7)
const STOCK_BOX_SCALE := 0.5
const INSTALL_SLOTS := [
	Vector3(-1.6, 0.0, -1.2), Vector3(0.0, 0.0, -1.2), Vector3(1.6, 0.0, -1.2),
	Vector3(-1.6, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(1.6, 0.0, 1.0)
]
const EQUIPMENT_SLOTS := {"plant":0, "backup":1, "monitor":2, "workstation":3, "diagnostic":4, "teamdesk":5, "annexdesk_a":6, "annexdesk_b":7}

var game: Node
var _boxes: Dictionary = {}
var _order_signatures: Dictionary = {}
var _ghost: Node3D
var _placing_id := ""
var _placing_slot := -1
var _slot_specs: Array = []
var _carried_anchor: Node3D
var _upgrade_nodes: Dictionary = {}
var _placing_position := Vector3.ZERO
var _placing_rotation := 0.0
var _placement_valid := false
var _placement_error := ""
var _moving_installed := false
var _preview_key := ""
var _preview_static_error := ""
var _last_stock_error := ""

func carried_id() -> String:
	for raw_order in game.delivery_orders() if game != null else []:
		var order: Dictionary = raw_order
		if str(order.get("status", "")) in ["carried", "placing"]: return str(order.get("id", ""))
	return ""

func is_placing() -> bool:
	return not _placing_id.is_empty()

func placement_valid() -> bool:
	return _placement_valid

func placement_reason() -> String:
	return _placement_error

func _live_position_error(position: Array, rotation_y: float) -> String:
	# The canonical monitor test is geometric (PlacementRules); once the office
	# scene is present, let it add live physics/prop checks without making this
	# delivery helper depend on the office implementation.
	if _placing_id == "monitor":
		var monitor_office := get_parent()
		if monitor_office != null and monitor_office.has_method("monitor_placement_error"):
			return str(monitor_office.monitor_placement_error(position, rotation_y))
		return ""
	if position.size() < 3 or get_world_3d() == null: return ""
	var footprint: Rect2 = PLACEMENT_RULES.footprint(_placing_id, Vector2(float(position[0]), float(position[2])), rotation_y)
	var shape := BoxShape3D.new()
	var height: float = float({"plant":1.45,"backup":0.29,"diagnostic":1.08,"workstation":1.24,"teamdesk":1.27,"annexdesk_a":1.27,"annexdesk_b":1.27}.get(_placing_id,1.45))
	shape.size = Vector3(footprint.size.x, height, footprint.size.y)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Lift the equipment AABB by 1cm to avoid treating the floor as an obstacle.
	query.transform = Transform3D(Basis.IDENTITY, Vector3(footprint.get_center().x, height * 0.5+0.01, footprint.get_center().y))
	query.collision_mask = 1
	var office := get_parent()
	var moving_body: Object = office.get("upgrade_collisions").get(_placing_id) if office != null and office.get("upgrade_collisions") is Dictionary else null
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider: Object = hit.get("collider")
		if collider == self or collider == _ghost or collider == moving_body: continue
		return "現在の位置に障害物があります。"
	if office != null and office.has_method("placement_routes_clear"):
		var proposed: Array=[]
		for order in game.delivery_orders():
			if str(order.get("id",""))!=_placing_id:proposed.append(order)
		proposed.append({"id":_placing_id,"status":"installed","install_position":position,"rotation_y":rotation_y})
		if not office.placement_routes_clear(proposed):return UI.copy("equipment_route_blocked")
	return ""

func _is_stock_id(id: String) -> bool:
	return id.begins_with("stock-")

func _stock_order(id: String) -> Dictionary:
	if game == null: return {}
	if game.has_method("customer_stock_for"):
		var value: Variant = game.customer_stock_for(id)
		if value is Dictionary: return value
	return {}

func _stock_product(id: String) -> Dictionary:
	var order := _stock_order(id)
	if game != null and game.has_method("customer_stock_catalog"):
		for product in game.customer_stock_catalog():
			if str(product.get("sku", "")) == str(order.get("sku", "")): return product
	return {"sku":str(order.get("sku", "gateway")),"icon":"backup"}

func _stock_action_result(value: Variant) -> bool:
	_last_stock_error = ""
	if value is Dictionary:
		_last_stock_error = str(value.get("error", ""))
		return bool(value.get("ok", false))
	return bool(value)

func stock_error() -> String:
	return _last_stock_error

func placement_position_array() -> Array:
	return [_placing_position.x, _placing_position.y, _placing_position.z]

func _order_for_any(id: String) -> Dictionary:
	if game == null: return {}
	for raw_order in game.delivery_orders():
		var order: Dictionary = raw_order
		if str(order.get("id", "")) == id: return order
	return {}

func allowed_slot(id: String) -> int:
	return game.equipment_slot(id) if game != null else int(EQUIPMENT_SLOTS.get(id, -1))

func update_carried_anchor() -> void:
	_sync_carried_transform()

func placement_position(id: String) -> Vector3:
	var order: Dictionary = _order_for_any(id)
	var saved: Variant = order.get("install_position",[])
	if id == "monitor" and saved is Array and saved.size() >= 3:
		return Vector3(float(saved[0]),float(saved[1]),float(saved[2]))
	var slot := int(order.get("install_slot", -1))
	if slot < 0: slot=allowed_slot(id)
	var slots := _slots()
	return slots[clampi(slot, 0, slots.size() - 1)] if not slots.is_empty() else Vector3.ZERO

func can_confirm_from(player_position: Vector3, id: String, max_distance := 2.0) -> bool:
	var destination := _placing_position if id == _placing_id and _placing_id == "monitor" else placement_position(id)
	return Vector2(player_position.x,player_position.z).distance_to(Vector2(destination.x,destination.z)) <= max_distance

func setup(game_instance: Node, slot_specs: Array = []) -> void:
	game = game_instance
	if not slot_specs.is_empty(): _slot_specs = slot_specs.duplicate(true)
	sync_orders(game.delivery_orders() if game != null else [])

func set_carried_anchor(anchor: Node3D) -> void:
	_carried_anchor = anchor
	_sync_carried_transform()

func set_upgrade_nodes(nodes: Dictionary) -> void:
	_upgrade_nodes = nodes.duplicate()

func _slots() -> Array:
	if not _slot_specs.is_empty(): return _slot_specs
	return INSTALL_SLOTS

func _box_mesh(material: Material, ghost: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(0.62, 0.52, 0.62)
	mesh.mesh = shape
	mesh.material_override = material
	mesh.transparency = 0.45 if ghost else 0.0
	return mesh

func _make_delivery_box(id: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "DeliveryBox_%s" % id
	body.set_meta("delivery_id", id)
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_meta("action", "delivery_box")
	var stock := _is_stock_id(id)
	body.set_meta("stock_box", stock)
	body.set_meta("label", UI.copy("stock_box", "Customer gateway") if stock else "設備の箱")
	var stock_order := _stock_order(id) if stock else {}
	var stock_state := str(stock_order.get("status", "ready")) if stock else ""
	var stock_product := _stock_product(id) if stock else {}
	if stock and stock_state == "staged":
		body.set_meta("label", "%s · %s" % [str(stock_product.get("title", "")), str(stock_order.get("serial", id))])
		body.set_meta("stock_appliance", true)
		body.set_meta("stock_state", stock_state)
		body.set_meta("sku", str(stock_product.get("sku", "")))
		var appliance_path := "res://assets/props/customer-appliances/%s.glb" % ("backup" if str(stock_product.get("sku", "")) == "backup_appliance" else "gateway")
		if ResourceLoader.exists(appliance_path):
			var appliance: Node3D = load(appliance_path).instantiate()
			appliance.scale = Vector3.ONE
			appliance.position = Vector3(0.0, -0.13, 0.0)
			body.add_child(appliance)
		var dimensions := Vector3(0.21, 0.29, 0.26) if str(stock_product.get("sku", "")) == "backup_appliance" else Vector3(0.40, 0.093, 0.25)
		var appliance_collision := CollisionShape3D.new()
		var appliance_shape := BoxShape3D.new()
		appliance_shape.size = dimensions
		appliance_collision.shape = appliance_shape
		# The body keeps the former carton center; the imported GLB origin is at
		# the appliance feet, so both mesh and chassis collision use this offset.
		appliance_collision.position = Vector3(0.0, -0.13 + dimensions.y * 0.5, 0.0)
		body.add_child(appliance_collision)
		return body
	if stock: body.scale = Vector3.ONE * STOCK_BOX_SCALE
	var box := _box_mesh(_material(Color("#bd8e4a")))
	body.add_child(box)
	box.set_meta("delivery_id", id)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.62, 0.52, 0.62)
	collision.shape = shape
	body.add_child(collision)
	# Two narrow tape strips make the package read as a delivered carton.
	for at in [Vector3(0.0, 0.266, 0.0), Vector3(0.0, 0.0, 0.315)]:
		var tape := _box_mesh(_material(Color("#e7c574")))
		tape.scale = Vector3(0.12, 0.01, 1.0) if at.y > 0.0 else Vector3(0.12, 0.12, 0.01)
		tape.position = at
		body.add_child(tape)
	var label := Sprite3D.new()
	label.texture = EQUIPMENT_ART.icon(str(stock_product.get("icon", "backup")) if stock else id)
	var icon_size := label.texture.get_size() if label.texture != null else Vector2.ZERO
	var icon_extent := maxf(icon_size.x, icon_size.y)
	label.pixel_size = 0.24 / icon_extent if icon_extent > 0.0 else 0.002
	label.double_sided = true
	label.position = Vector3(0.0, 0.02, 0.321)
	label.set_meta("delivery_id", id)
	body.add_child(label)
	var rear_label: Sprite3D = label.duplicate()
	rear_label.position = Vector3(0.0, 0.02, -0.321)
	rear_label.rotation.y = PI
	body.add_child(rear_label)
	if stock:
		var serial := str(_stock_order(id).get("serial", id))
		var serial_label := Label3D.new()
		serial_label.text = serial
		serial_label.font_size = 18
		serial_label.pixel_size = 0.004
		serial_label.modulate = Color("f5ead0")
		serial_label.outline_size = 3
		serial_label.position = Vector3(0.0, 0.34, 0.0)
		serial_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		body.add_child(serial_label)
	return body

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	return result

func _position_from_saved(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		var saved := Vector3(float(value[0]), float(value[1]), float(value[2]))
		# Migrate the pre-v19 placeholder receiving point without changing old
		# save data in Game's persistence layer.
		if saved.is_equal_approx(Vector3(-3.0, 0.35, 2.0)): saved.y = BOX_RECEIVING_POINT.y
		return saved
	return BOX_RECEIVING_POINT

func _signature(order: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [order.get("id", ""), order.get("status", ""), order.get("stock_state", ""), order.get("sku", ""), order.get("install_slot", -1), order.get("box_position", []), order.get("install_position", []), order.get("rotation_y", 0.0)]

func _sync_carried_transform() -> void:
	for id in _boxes:
		var body: Node3D = _boxes[id]
		if not is_instance_valid(body): continue
		var order: Dictionary = game.delivery_for(str(id)) if game != null else {}
		if str(order.get("status", "")) in ["carried", "placing"]:
			body.collision_layer = 0
			body.collision_mask = 0
			if _carried_anchor != null:
				# Keep the camera anchor as the parent reference while offsetting the
				# box into the lower foreground so it stays visible past the near clip.
				body.global_transform = _carried_anchor.global_transform.translated_local(Vector3(0.0, -0.28, -1.02))
				if bool(body.get_meta("stock_box", false)): body.scale = Vector3.ONE * STOCK_BOX_SCALE
			else: body.position = Vector3(0.0, 1.1, -0.8)

func sync_orders(orders: Array) -> void:
	var active: Dictionary = {}
	for raw_order in orders:
		var order: Dictionary = raw_order
		var status: String = str(order.get("status", ""))
		var id: String = str(order.get("id", ""))
		var stock := _is_stock_id(id)
		if stock:
			if status not in ["ready", "carried", "stored", "staged"]: continue
		elif status not in ["ready", "carried", "placing"]: continue
		active[id] = true
		var sig: String = _signature(order)
		if _order_signatures.get(id, "") == sig and _boxes.has(id): continue
		if _boxes.has(id) and is_instance_valid(_boxes[id]): _boxes[id].queue_free()
		var body: StaticBody3D = _make_delivery_box(id)
		body.position = _position_from_saved(order.get("box_position", BOX_RECEIVING_POINT))
		body.rotation.y = float(order.get("rotation_y", 0.0))
		if status in ["carried", "placing"]:
			body.collision_layer = 0
			body.collision_mask = 0
		# During placement the equipment ghost is the only preview. Keeping the
		# carton visible here creates a misleading duplicate at the slot.
		if status == "placing" and not stock: body.visible = false
		add_child(body)
		_boxes[id] = body
		_order_signatures[id] = sig
		if status in ["carried", "placing"]: _sync_carried_transform()
		if status == "placing" and id == _placing_id: _show_ghost(id)
	for stale_id in _boxes.keys().duplicate():
		if not active.has(stale_id):
			if is_instance_valid(_boxes[stale_id]): _boxes[stale_id].queue_free()
			_boxes.erase(stale_id); _order_signatures.erase(stale_id)

func _show_ghost(id: String) -> void:
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = _equipment_ghost(id)
	_ghost.name = "DeliveryPlacementGhost"
	var order: Dictionary = _order_for_any(id)
	if _placing_position == Vector3.ZERO:
		_placing_position = _slots()[clampi(_placing_slot, 0, _slots().size() - 1)]
	_placing_rotation = float(order.get("rotation_y", _placing_rotation))
	_ghost.position = _placing_position
	_ghost.rotation.y = _placing_rotation
	add_child(_ghost)
	_set_ghost_valid(_placement_valid)

func _set_ghost_valid(valid: bool) -> void:
	var tint := Color(0.35, 0.9, 0.75, 0.45) if valid else Color(0.95, 0.25, 0.25, 0.48)
	if not is_instance_valid(_ghost): return
	for mesh in _mesh_nodes(_ghost):
		var material := mesh.material_override as StandardMaterial3D
		if material == null:
			material = StandardMaterial3D.new()
		mesh.material_override = material
		material.albedo_color = tint
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func update_placement_preview(position: Array, rotation_y: float, valid_override := true, error_override := "") -> void:
	if _placing_id.is_empty(): return
	if position.size() < 3: return
	var preview_key := "%s|%.2f|%.2f|%.2f|%.3f|%s" % [_placing_id,float(position[0]),float(position[1]),float(position[2]),rotation_y,JSON.stringify(game.delivery_orders() if game != null else [])]
	_placing_position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	_placing_rotation = rotation_y
	var expanded := bool(game.office_expanded()) if game != null and game.has_method("office_expanded") else false
	preview_key += str(expanded)
	if preview_key != _preview_key:
		_preview_key = preview_key
		_preview_static_error = PLACEMENT_RULES.position_error(_placing_id, position, rotation_y, game.delivery_orders() if game != null else [], expanded)
	_placement_error = error_override if not error_override.is_empty() else _preview_static_error
	if _placement_error.is_empty(): _placement_error = _live_position_error(position, rotation_y)
	_placement_valid = valid_override and _placement_error.is_empty()
	if is_instance_valid(_ghost):
		_ghost.position = _placing_position
		_ghost.rotation.y = _placing_rotation
		_set_ghost_valid(_placement_valid)

func _equipment_ghost(id: String) -> Node3D:
	if _upgrade_nodes.has(id) and is_instance_valid(_upgrade_nodes[id]):
		var existing: Node3D = _upgrade_nodes[id].duplicate()
		existing.visible = true
		for mesh in _mesh_nodes(existing):
			if mesh.mesh != null: mesh.mesh = mesh.mesh.duplicate()
			var ghost_material := StandardMaterial3D.new()
			ghost_material.albedo_color = Color(0.35, 0.9, 0.75, 0.45)
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = ghost_material
		return existing
	# Use the same normalized equipment factory as the installed model. This is
	# especially important for the tabletop monitor, whose support height and
	# footprint must match the placement validator.
	var factory_root: Node3D = EQUIPMENT_VISUALS.build(id)
	if factory_root != null and not bool(factory_root.get_meta("unknown_equipment",false)):
		for mesh in _mesh_nodes(factory_root):
			var ghost_material := StandardMaterial3D.new()
			ghost_material.albedo_color = Color(0.35, 0.9, 0.75, 0.45)
			ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = ghost_material
		return factory_root
	# A translucent BoxMesh remains the safe fallback when an asset is absent.
	return _box_mesh(_material(Color(0.35, 0.9, 0.75, 0.65)), true)

func _mesh_nodes(root: Node) -> Array:
	var result: Array = []
	if root is MeshInstance3D: result.append(root)
	result.append_array(root.find_children("*", "MeshInstance3D", true, false))
	return result

func interact(action: String, id: String = "", slot: int = -1, position: Array = []) -> bool:
	if game == null: return false
	if _is_stock_id(id):
		var stock_result: Variant = false
		match action:
			"pickup": stock_result = game.take_delivery(id)
			"store": stock_result = game.store_customer_stock(id) if game.has_method("store_customer_stock") else false
			"stage": stock_result = game.stage_customer_stock(id) if game.has_method("stage_customer_stock") else false
			"dispatch": stock_result = game.dispatch_customer_stock(id) if game.has_method("dispatch_customer_stock") else false
			"put_down": stock_result = game.put_down_delivery(id, position if not position.is_empty() else (slot if slot >= 0 else []))
			_: return false
		var stock_ok := _stock_action_result(stock_result)
		if stock_ok:
			sync_orders(game.delivery_orders())
			delivery_changed.emit()
		return stock_ok
	var result := false
	match action:
		"pickup": result = game.take_delivery(id)
		"place_start":
			var allowed := allowed_slot(id)
			var order := _order_for_any(id)
			var office:=get_parent()
			if str(order.get("status",""))=="installed" and office!=null and office.get("staff_actors") is Dictionary:
				for worker in office.staff_actors.values():
					if str(worker.get("workplace",""))==id and not worker.routine.is_departed():
						game.notified.emit(UI.copy("equipment_move_busy"));return false
			if str(order.get("status", "")) == "installed" and game.has_method("begin_equipment_move"):
				result = game.begin_equipment_move(id)
				_moving_installed = result
			else:
				if allowed < 0: return false
				result = game.begin_delivery_placement(id)
			if result:
				_placing_id = id; _placing_slot = allowed
				_placing_position = _position_from_saved(order.get("install_position", [])) if _moving_installed else Vector3.ZERO
				if _moving_installed and _placing_position == BOX_RECEIVING_POINT: _placing_position = _slots()[clampi(allowed, 0, _slots().size() - 1)]
				_placing_rotation = float(order.get("rotation_y", 0.0)); _placement_valid = false; _placement_error = "床面を狙ってください。"; _show_ghost(id)
		"rotate":
			result = game.rotate_delivery(id)
			if result:
				# rotate_delivery emits changed synchronously; read its persisted
				# value so the signal refresh does not cause a second increment.
				_placing_rotation = float(_order_for_any(id).get("rotation_y", _placing_rotation))
				if is_instance_valid(_ghost): _ghost.rotation.y = _placing_rotation
		"rotate_left":
			result = game.rotate_delivery(id,-1.0 / 6.0)
			if result:
				_placing_rotation = float(_order_for_any(id).get("rotation_y", _placing_rotation))
				if is_instance_valid(_ghost): _ghost.rotation.y = _placing_rotation
		"rotate_right":
			result = game.rotate_delivery(id,1.0 / 6.0)
			if result:
				_placing_rotation = float(_order_for_any(id).get("rotation_y", _placing_rotation))
				if is_instance_valid(_ghost): _ghost.rotation.y = _placing_rotation
		"confirm":
			if game.has_method("place_delivery_at"):
				var live_error := _live_position_error(placement_position_array(), _placing_rotation)
				if not live_error.is_empty(): _placement_error = live_error; _placement_valid = false
				result = _placement_valid and game.place_delivery_at(id, placement_position_array(), _placing_rotation)
			else: result = game.place_delivery(id, _placing_slot, _placing_rotation)
		"cancel":
			result = game.cancel_equipment_move(id) if _moving_installed and game.has_method("cancel_equipment_move") else game.put_down_delivery(id)
		"put_down": result = game.put_down_delivery(id, position if not position.is_empty() else (slot if slot >= 0 else []))
	if result:
		if action in ["confirm", "cancel", "put_down"]:
			_placing_id = ""; _placing_slot = -1
			_placing_position = Vector3.ZERO; _placement_valid = false; _placement_error = ""; _moving_installed = false
			_preview_key = ""
			if is_instance_valid(_ghost): _ghost.queue_free(); _ghost = null
		sync_orders(game.delivery_orders())
		delivery_changed.emit()
	return result

func set_placement_slot(slot: int) -> void:
	if slot < 0 or slot >= _slots().size(): return
	if not _placing_id.is_empty() and slot != allowed_slot(_placing_id): return
	_placing_slot = slot
	if is_instance_valid(_ghost): _ghost.position = _slots()[slot]
