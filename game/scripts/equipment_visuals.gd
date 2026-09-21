class_name EquipmentVisuals
extends RefCounted

## One source of truth for purchased equipment previews and world models.
## Every model is rooted at its floor contact so a ghost and an installed item
## use identical geometry and metadata.

const FURNITURE := "res://assets/furniture/"
const APPLIANCES := "res://assets/props/customer-appliances/"
const MODELS := {
	"plant": "pottedPlant.glb",
	"monitor": "computerScreen.glb",
	"backup": "backup.glb",
	"workstation": "deskCorner.glb",
	"diagnostic": "desk.glb",
	"teamdesk": "desk.glb",
	"annexdesk_a": "desk.glb",
	"annexdesk_b": "desk.glb",
}

static func _scene(path: String) -> Node3D:
	var packed: PackedScene = load(path)
	return packed.instantiate() as Node3D if packed != null else Node3D.new()

static func _add(root: Node3D, path: String, position: Vector3, height: float, rotation_y: float = 0.0) -> Node3D:
	var node := _scene(path)
	_finish_materials(node, path.ends_with("computerScreen.glb"))
	var bounds := _bounds(node)
	var factor := height / maxf(bounds.size.y, 0.01)
	node.scale = Vector3.ONE * factor
	node.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	var pivot := Node3D.new()
	pivot.position = position
	pivot.rotation.y = rotation_y
	if path.ends_with("computerScreen.glb"):
		pivot.set_meta("equipment_screen", true)
	pivot.add_child(node)
	root.add_child(pivot)
	return pivot

static func _finish_materials(node: Node3D, screen: bool) -> void:
	var palette := {"wood":"856747", "carpet":"42625c", "metal":"819590", "metalMedium":"465553", "metalDark":"243a3b"}
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(index)
			if not screen and (original == null or not palette.has(original.resource_name)): continue
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("263e3e" if screen else palette[original.resource_name])
			material.roughness = 0.9
			if screen and index == 1:
				material.albedo_color = Color.WHITE
				material.albedo_texture = load("res://assets/ui/aoba-wallpaper-v16.png")
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.uv1_scale = Vector3(1.0/14.92664, 1.0/9.19924, 1)
				material.uv1_offset = Vector3(-0.26676/14.92664, 10.562574/9.19924, 0)
			mesh.set_surface_override_material(index, material)

static func _add_raw(root: Node3D, path: String, position: Vector3, scale: float, rotation_y: float = 0.0) -> Node3D:
	var node := _scene(path)
	node.position = position
	node.scale = Vector3.ONE * scale
	node.rotation.y = rotation_y
	root.add_child(node)
	return node

static func _box(root: Node3D, position: Vector3, size: Vector3, material_color: Color) -> Node3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = material_color
	mesh.material = material
	node.mesh = mesh
	node.position = position
	root.add_child(node)
	return node

static func _bounds(node: Node, parent: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform := parent
	if node is Node3D:
		transform = parent * node.transform
	var result := AABB()
	if node is MeshInstance3D and node.mesh != null:
		result = transform * node.get_aabb()
	for child in node.get_children():
		var child_bounds := _bounds(child, transform)
		if child_bounds.size.length() > 0.001:
			result = child_bounds if result.size.length() < 0.001 else result.merge(child_bounds)
	return result

static func _metadata(root: Node3D, id: String, footprint: Vector3, anchors: Array, seats: Array) -> Node3D:
	root.name = "EquipmentVisual_%s" % id
	root.set_meta("equipment_id", id)
	root.set_meta("footprint", footprint)
	root.set_meta("screen_anchors", anchors)
	root.set_meta("seat_offsets", seats)
	root.set_meta("floor_origin", Vector3.ZERO)
	return root

static func _finalize(root: Node3D) -> Node3D:
	var bounds := _bounds(root)
	root.set_meta("bounds", bounds)
	root.set_meta("bounds_min", bounds.position)
	root.set_meta("bounds_max", bounds.position + bounds.size)
	root.set_meta("footprint", bounds.size)
	return root

static func build(id: String) -> Node3D:
	var root := Node3D.new()
	match id:
		"plant":
			_metadata(root, id, Vector3(0.42, 1.45, 0.42), [], [])
			_add(root, FURNITURE + MODELS[id], Vector3(0, 0, 0), 1.45)
		"backup":
			_metadata(root, id, Vector3(0.40, 0.29, 0.26), [], [])
			_add_raw(root, APPLIANCES + MODELS[id], Vector3(0, 0, 0), 1.0)
		"monitor":
			_metadata(root, id, Vector3(0.54, 0.52, 0.20), [Vector3(0, 0.52, 0)], [])
			_add(root, FURNITURE + MODELS[id], Vector3(0, 0, 0), 0.46)
		"workstation":
			_metadata(root, id, Vector3(1.35, 1.26, 0.78), [Vector3(0, 0.90, -0.15)], [Vector3(0, 0, 0.72)])
			_add(root, FURNITURE + MODELS[id], Vector3.ZERO, 0.76)
			# The corner desk is L-shaped: the rear wing ends at z=-0.1922.
			_add(root, FURNITURE + "computerScreen.glb", Vector3(0, 0.76, -0.62), 0.48)
			_add(root, FURNITURE + "computerKeyboard.glb", Vector3(-0.08, 0.76, -0.29), 0.04)
			_add(root, FURNITURE + "computerMouse.glb", Vector3(0.32, 0.76, -0.30), 0.04)
			_box(root, Vector3(-0.43, 0.21, 0.38), Vector3(0.22, 0.42, 0.38), Color("263e3e"))
		"diagnostic":
			_metadata(root, id, Vector3(1.45, 1.18, 0.78), [Vector3(-0.22, 1.03, -0.08), Vector3(0.22, 1.03, -0.08)], [Vector3(0, 0, 0.70)])
			_add(root, FURNITURE + MODELS[id], Vector3.ZERO, 0.68)
			_add(root, FURNITURE + "computerScreen.glb", Vector3(-0.32, 0.68, -0.12), 0.40)
			_add(root, FURNITURE + "computerScreen.glb", Vector3(0.32, 0.68, -0.12), 0.40)
			_add(root, FURNITURE + "computerKeyboard.glb", Vector3(0, 0.68, 0.20), 0.04)
		"teamdesk", "annexdesk_a", "annexdesk_b":
			_metadata(root, id, Vector3(1.60, 1.27, 1.05), [Vector3(0, 1.10, -0.17)], [Vector3(0, 0, 0.72)])
			_add(root, FURNITURE + MODELS[id], Vector3.ZERO, 0.79)
			_add(root, FURNITURE + "chairDesk.glb", Vector3(0, 0, 0.72), 1.02, PI)
			_add(root, FURNITURE + "computerScreen.glb", Vector3(0, 0.79, -0.17), 0.48)
			_add(root, FURNITURE + "computerKeyboard.glb", Vector3(-0.10, 0.79, 0.23), 0.04)
			_add(root, FURNITURE + "computerMouse.glb", Vector3(0.32, 0.79, 0.30), 0.04)
		_:
			root.set_meta("unknown_equipment", true)
	return _finalize(root)

static func catalog_ids() -> Array[String]:
	return ["plant", "backup", "monitor", "workstation", "diagnostic", "teamdesk", "annexdesk_a", "annexdesk_b"]

static func metadata(id: String) -> Dictionary:
	var node := build(id)
	var result := {"id": id, "footprint": node.get_meta("footprint", Vector3.ZERO), "bounds_min": node.get_meta("bounds_min", Vector3.ZERO), "bounds_max": node.get_meta("bounds_max", Vector3.ZERO), "screen_anchors": node.get_meta("screen_anchors", []), "seat_offsets": node.get_meta("seat_offsets", [])}
	node.free()
	return result
