extends Node3D
## Small, cheap 3D coffee cup shared by the world prop and the first-person hand.
## The cup is deliberately geometry-only so it works in Compatibility mode.

var liquid_level := 1.0
var liquid_mesh: MeshInstance3D
var surface_rim: MeshInstance3D
var cup_material: StandardMaterial3D
var coffee_material: StandardMaterial3D

func _ready() -> void:
	_build()
	set_liquid(liquid_level)

func _mat(color: Color, roughness := 0.82) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _mesh(mesh: Mesh, material: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _build() -> void:
	if get_child_count() > 0: return
	cup_material = _mat(Color("e8eee9"))
	coffee_material = _mat(Color("6b3e29"), 0.66)
	var body := CylinderMesh.new()
	body.top_radius = 0.052
	body.bottom_radius = 0.060
	body.height = 0.105
	body.cap_top = false
	body.cap_bottom = true
	_mesh(body, cup_material, Vector3(0, 0.053, 0))
	var inner := CylinderMesh.new()
	inner.top_radius = 0.047
	inner.bottom_radius = 0.054
	inner.height = 0.092
	inner.cap_top = false
	inner.cap_bottom = true
	inner.flip_faces = true
	_mesh(inner, cup_material, Vector3(0, 0.052, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.047
	rim.outer_radius = 0.057
	rim.rings = 12
	rim.ring_segments = 10
	_mesh(rim, cup_material, Vector3(0, 0.106, 0))
	# A second, slightly dark lip gives the first-person view a readable drinking
	# edge even when the cup is tilted.  It is geometry-only and stays cheap in
	# Compatibility mode.
	surface_rim = MeshInstance3D.new()
	var lip := TorusMesh.new()
	lip.inner_radius = 0.043
	lip.outer_radius = 0.049
	lip.rings = 10
	lip.ring_segments = 10
	surface_rim.mesh = lip
	surface_rim.material_override = coffee_material
	surface_rim.position = Vector3(0, 0.107, 0)
	surface_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface_rim)
	var handle := TorusMesh.new()
	handle.inner_radius = 0.022
	handle.outer_radius = 0.034
	handle.rings = 12
	handle.ring_segments = 8
	# Bring the grip a little toward the viewer.  The first-person forearm then
	# meets the near side of the ring instead of disappearing behind the cup wall.
	var handle_mesh := _mesh(handle, cup_material, Vector3(0.060, 0.066, -0.018))
	handle_mesh.rotation = Vector3(PI * 0.5, -0.18, 0.0)
	liquid_mesh = MeshInstance3D.new()
	var liquid := CylinderMesh.new()
	liquid.top_radius = 0.044
	liquid.bottom_radius = 0.044
	liquid.height = 0.004
	liquid_mesh.mesh = liquid
	liquid_mesh.material_override = coffee_material
	liquid_mesh.position = Vector3(0, 0.106, 0)
	liquid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(liquid_mesh)

func set_liquid(amount: float) -> void:
	liquid_level = clampf(amount, 0.0, 1.0)
	if not is_instance_valid(liquid_mesh): return
	liquid_mesh.visible = liquid_level > 0.01
	liquid_mesh.position.y = 0.106 - (1.0 - liquid_level) * 0.035
	liquid_mesh.scale = Vector3(1.0, maxf(0.12, liquid_level), 1.0)
