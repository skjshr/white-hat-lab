extends SceneTree
var actors: Array[Node3D]=[]
var camera: Camera3D
func _init(): call_deferred("run")
func run():
	root.size=Vector2i(1200,900)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("9cabba");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.light_energy=1;world.add_child(light)
	var floor:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(10,.06,10);floor.mesh=box;floor.position.y=-.04;world.add_child(floor)
	for id in ["aya","ren"]:
		var actor:Node3D=load("res://assets/characters/v19/%s.glb"%id).instantiate();world.add_child(actor);actor.position.x=-.65 if id=="aya" else .65;actors.append(actor)
		var p:AnimationPlayer=actor.find_children("*","AnimationPlayer",true,false)[0];print(id," ",p.get_animation_list())
	camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.fov=44
	for clip in ["Idle","Seated","Drink","Walk"]:
		for actor in actors:
			var p:AnimationPlayer=actor.find_children("*","AnimationPlayer",true,false)[0];p.play(clip);p.seek(1.8 if clip=="Drink" else .4,true);p.pause()
		camera.position=Vector3(2.8,1.7,4);camera.look_at(Vector3(0,.85,0))
		for n in 5:await process_frame
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/simulator/v19/npc-baked-%s.png"%clip))
	quit()
