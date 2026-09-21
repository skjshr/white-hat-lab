extends Node3D

## GPU preview scene for the parent integration pass. It renders a ready box,
## carried box and placement ghost with the same node APIs used in office.gd.
var delivery: Node3D

func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 3.8, 7.0)
	camera.look_at_from_position(camera.position, Vector3(0, 0.5, 0))
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.2
	add_child(light)
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new(); floor_mesh.size = Vector3(9, 0.1, 7)
	floor.mesh = floor_mesh
	floor.position.y = -0.05
	var floor_material := StandardMaterial3D.new(); floor_material.albedo_color = Color("#dce5ec")
	floor.material_override = floor_material
	add_child(floor)
	Game._reset_state(); Game.state.cash = 10000; Game.buy_equipment("plant"); Game.advance_delivery(30.0)
	delivery = load("res://scripts/equipment_delivery.gd").new()
	add_child(delivery)
	delivery.setup(Game, [Vector3(-1.6, 0.35, -1.2), Vector3(0, 0.35, -1.2), Vector3(1.6, 0.35, -1.2), Vector3(-1.6, 0.35, 1.0), Vector3(0, 0.35, 1.0), Vector3(1.6, 0.35, 1.0)])
	# Start in the actual carry/placement flow so a screenshot exposes both
	# the identifiable carton and the translucent equipment ghost.
	delivery.interact("pickup", "plant")
	delivery.interact("place_start", "plant", 0)

