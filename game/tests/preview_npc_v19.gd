extends SceneTree
## Focused NPC visual/evidence preview. It does not mutate Game or office.gd.

const POSE = preload("res://scripts/desk_worker_pose.gd")
var out_dir := ""
var stage_root: Node3D
var camera: Camera3D
var actors: Array[Node3D] = []
var evidence: Array[String] = []

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out-dir="): out_dir=str(arg).trim_prefix("--out-dir=")
	call_deferred("_run")

func _run() -> void:
	if out_dir.is_empty(): out_dir=ProjectSettings.globalize_path("res://../artifacts/simulator/v19")
	elif not out_dir.is_absolute_path(): out_dir=ProjectSettings.globalize_path("res://../"+out_dir.trim_prefix("./"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	stage_root=Node3D.new(); stage_root.name="NpcV19Stage"; root.add_child(stage_root)
	_add_floor(); _add_lighting(); _add_camera()
	_spawn("aya",Vector3(-0.85,0,0),0.0); _spawn("ren",Vector3(0.85,0,0),0.0)
	await _frames(8); _dump_bones("seated"); await _capture("npc-v19-seated-front.png")
	_camera(Vector3(3.5,1.8,3.6),Vector3(0,0.8,0)); await _capture("npc-v19-seated-side.png")
	# Walk clip is an asset animation; clear the procedural pose and play it.
	for actor in actors:
		var skeletons:=actor.find_children("*","Skeleton3D",true,false)
		if not skeletons.is_empty(): skeletons[0].reset_bone_poses()
		var players:=actor.find_children("*","AnimationPlayer",true,false)
		if not players.is_empty() and players[0].has_animation("Walk"): players[0].play("Walk")
	_camera(Vector3(3.8,1.7,3.2),Vector3(0,0.8,0)); await _capture("npc-v19-walk.png")
	# A visible cup is parented to the actor grip and remains attached during the
	# drink frame, exercising the same attachment contract as office_colleague.
	for actor in actors:
		var grip:=Node3D.new(); grip.name="CoffeeGrip"; grip.position=Vector3(0,1.18,0.18); actor.add_child(grip)
		var cup:=MeshInstance3D.new(); var mesh:=CylinderMesh.new(); mesh.top_radius=0.06; mesh.bottom_radius=0.05; mesh.height=0.13; cup.mesh=mesh; grip.add_child(cup)
	_camera(Vector3(3.0,1.5,2.8),Vector3(0,1.0,0)); await _capture("npc-v19-drink.png")
	print("NPC_V19_PREVIEW output_dir=",out_dir," bone_evidence=",evidence.size())
	quit(0)

func _spawn(id: String, at: Vector3, angle: float) -> void:
	var pivot:=Node3D.new(); pivot.name=id; pivot.position=at; pivot.rotation.y=angle; stage_root.add_child(pivot)
	var model: Node3D=load("res://assets/characters/v19/%s.glb"%id).instantiate(); pivot.add_child(model)
	var bounds:=AABB(Vector3(-1,-1,-1),Vector3(2,2,2)); var meshes:=model.find_children("*","MeshInstance3D",true,false)
	if not meshes.is_empty(): bounds=meshes[0].get_aabb()
	model.scale*=1.68/maxf(bounds.size.y,0.1); model.position.y-=bounds.position.y*model.scale.y
	var players:=model.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty() and players[0].has_animation("Seated"): players[0].play("Seated")
	actors.append(pivot)

func _add_floor() -> void:
	var floor:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(8,0.08,8); floor.mesh=mesh; floor.position.y=-0.04; var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("dce5ec"); floor.material_override=mat; stage_root.add_child(floor)

func _add_lighting() -> void:
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-48,-25,0); light.light_energy=1.2; stage_root.add_child(light)

func _add_camera() -> void:
	camera=Camera3D.new(); stage_root.add_child(camera); camera.current=true; _camera(Vector3(0,1.55,4.0),Vector3(0,0.82,0))

func _camera(pos: Vector3,target: Vector3) -> void:
	camera.global_position=pos; camera.look_at(target,Vector3.UP); camera.fov=52.0

func _dump_bones(label: String) -> void:
	var f:=FileAccess.open(out_dir.path_join("npc-v19-%s-bones.json"%label),FileAccess.WRITE)
	for actor in actors:
		var s:=actor.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
		for name in ["Hips","UpperLeg.L","LowerLeg.L","Foot.L","PT.L","UpperLeg.R","LowerLeg.R","Foot.R","PT.R"]:
			var i:=s.find_bone(name); if i<0: continue
			var p:=s.to_global(s.get_bone_global_pose(i).origin); evidence.append("%s %s %s"%[actor.name,name,p]); if f: f.store_line(JSON.stringify({"actor":actor.name,"bone":name,"world":[p.x,p.y,p.z]}))
	if f: f.close()

func _capture(name: String) -> void:
	await _frames(3)
	var image:=root.get_viewport().get_texture().get_image(); if image: image.save_png(out_dir.path_join(name))

func _frames(count: int) -> void:
	for _i in count: await process_frame
