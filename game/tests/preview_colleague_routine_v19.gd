extends SceneTree
var office
var actor:Node3D
var routine
var animator:AnimationPlayer
var out_dir:String
func _init():
	create_timer(45).timeout.connect(func():quit(2))
	call_deferred("run")
func run():
	out_dir=ProjectSettings.globalize_path("res://../artifacts/simulator/v19")
	var game=root.get_node("Game")
	game.new_game({"company":"風の森セキュリティ","player":"春山","aya":"小川","ren":"星野"})
	game.set_settings({"quality":"medium","resolution":"1600x900","window_mode":"windowed","render_scale":1.0,"volume":0},false)
	office=load("res://scripts/office.gd").new();root.add_child(office)
	office.set_process(false);office.player.set_physics_process(false);office.started=true
	office.ui.controls.menu.hide();office.ui.root.hide();office.ui.hud.hide();office.notice.hide()
	for label in office.find_children("*","Label3D",true,false):label.hide()
	actor=office.get_node("aya");routine=actor.get_meta("office_colleague_routine")
	animator=actor.find_children("*","AnimationPlayer",true,false)[0]
	routine.set_paused(false)
	await shot("routine-seated", "Seated", .4)
	routine.request_break()
	for n in 17:routine.tick(.2,-1)
	await shot("routine-breakwalk","Walk",.4)
	for n in 250:
		if routine.phase=="drink":break
		routine.tick(.2,-1)
	assert(routine.phase=="drink")
	await shot("routine-drink-lower","Drink",.3)
	await shot("routine-drink","Drink",1.85)
	for n in 300:
		routine.tick(.2,-1)
		if routine.phase=="sit":break
	assert(routine.phase=="sit")
	await shot("routine-returnseat","Seated",.4)
	print("COLLEAGUE_PREVIEW seated/walk/drink/return verified final_position=",actor.global_position)
	quit()
func shot(name:String,clip:String,time:float):
	animator.play(clip);animator.seek(time,true);animator.pause()
	var target:=actor.global_position+Vector3(0,.86,0)
	var offset:=Vector3(1.9,1.5,2.4)
	if clip=="Drink":target=actor.global_position+Vector3(0,1.20,0);offset=actor.global_basis*Vector3(.85,1.62,1.75)
	office.player.camera.global_position=actor.global_position+offset
	office.player.camera.look_at(target,Vector3.UP);office.player.camera.fov=48
	for n in 8:
		await process_frame
		if is_instance_valid(routine.coffee_visual):routine._orient_coffee()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name+".png"))
