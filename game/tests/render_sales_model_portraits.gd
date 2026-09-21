extends SceneTree
## Renders the same GLB characters used in the office into compact sales-board portraits.

const OUTPUT_DIR := "res://assets/ui/sales"

var world: Node3D
var camera: Camera3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(512, 512)
	world = Node3D.new()
	root.add_child(world)
	_add_environment()
	_add_lights()
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 27.0
	camera.position = Vector3(0.0, 1.48, 1.08)
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.43, 0.0), Vector3.UP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for id in ["aya", "ren"]:
		await _render(id)
	print("SALES_MODEL_PORTRAITS output=", ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)

func _add_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("d9f2f1")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff7e6")
	environment.ambient_light_energy = 0.82
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key.light_color = Color("fff1dc")
	key.light_energy = 1.15
	world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.4, 1.7, 1.0)
	fill.light_color = Color("bceef1")
	fill.light_energy = 1.35
	fill.omni_range = 4.0
	world.add_child(fill)

func _render(id: String) -> void:
	var packed := load("res://assets/characters/v19/%s.glb" % id) as PackedScene
	var actor := packed.instantiate() as Node3D
	actor.name = "SalesPortrait_%s" % id
	world.add_child(actor)
	var bounds := _bounds(actor)
	var factor := 1.68 / maxf(bounds.size.y, 0.1)
	actor.scale *= factor
	actor.position.y -= bounds.position.y * factor
	for animator in actor.find_children("*", "AnimationPlayer", true, false):
		if animator.has_animation("Idle"):
			animator.play("Idle")
			animator.seek(0.35, true)
			animator.pause()
	for _frame in 8:
		await process_frame
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(ProjectSettings.globalize_path("%s/model-%s.png" % [OUTPUT_DIR, id]))
	actor.queue_free()
	await process_frame

func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if mesh.mesh == null:
			continue
		var local: AABB = mesh.transform * mesh.get_aabb()
		if initialized:
			result = result.merge(local)
		else:
			result = local
			initialized = true
	return result if initialized else AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.7, 1.0))
