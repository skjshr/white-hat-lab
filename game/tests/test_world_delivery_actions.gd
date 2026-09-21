extends SceneTree
var office
var game
var errors:Array[String]=[]
func _init():
	create_timer(30).timeout.connect(func():quit(2))
	call_deferred("run")
func check(value:bool,message:String):
	if not value: errors.append(message);push_error(message)
func press_e():
	var event:=InputEventAction.new();event.action="interact";event.pressed=true;office._unhandled_input(event)
func run():
	game=root.get_node("Game");assert(game.save_path.begins_with("user://qa-"));game.new_game();game.state.cash=100000
	game.set_delivery_clock_enabled(true);game.set_delivery_clock_paused(false)
	office=load("res://scripts/office.gd").new();root.add_child(office)
	office.started=true;office.set_process(false);office.player.set_physics_process(false)
	office.ui.controls.menu.hide();office.ui.current_kind="";office.ui.root.hide()
	await physics_frame;await process_frame
	check(office._delivery_drop_clear(Vector3(0,0,1.6)),"clear floor permits drop without intersecting floor")
	check(not office._delivery_drop_clear(Vector3(-.5,0,-1)),"desk rejects drop")
	for id in ["plant","backup","monitor","workstation","diagnostic","teamdesk"]:
		check(game.buy_equipment(id),"order "+id);game.advance_delivery(31)
		office.focused={"action":"delivery_box","delivery_id":id}
		office.coffee_phase="carried_empty";press_e()
		check(game.delivery_for(id).status=="ready","cup blocks E pickup "+id)
		office.coffee_phase="idle";press_e();check(game.delivery_for(id).status=="carried","E pickup "+id)
		office.focused={};press_e();check(game.delivery_for(id).status=="placing","E works without focused box "+id)
		await physics_frame
		# Exercise the real input flow with space for the complete desk models.
		var target:Vector3={"plant":Vector3(-5.2,0,.4),"backup":Vector3(.7,0,-1.05),"monitor":Vector3(0,.8,-1.03),"workstation":Vector3(-1.1,0,-3.5),"diagnostic":Vector3(-1.8,0,1.8),"teamdesk":Vector3(2.7,0,2.4)}[id]
		office.player.global_position=target+Vector3(0,0,5);press_e()
		check(game.delivery_for(id).status=="placing","distant E install rejected "+id)
		var rotation_y: float = PI / 2.0 if id == "monitor" else PI if id in ["workstation","teamdesk"] else 0.0
		office.delivery.update_placement_preview([target.x,target.y,target.z],rotation_y)
		office.player.global_position=target+Vector3(0,0,1.8)
		await physics_frame
		office.delivery.update_placement_preview([target.x,target.y,target.z],rotation_y)
		if not office.delivery.placement_valid(): print("PLACEMENT_REJECT ", id, " ", office.delivery.placement_reason())
		press_e()
		check(id in game.state.equipment,"near E installs correct slot "+id)
		if id not in game.state.equipment: print("WORLD_DELIVERY_ACTIONS first_failure=",id);quit(1);return
	check(game.save_game() and game.load_game(),"installed world reload")
	check(game.state.equipment.size()==6,"all installed retained")
	print("WORLD_DELIVERY_ACTIONS failures=",errors.size())
	quit(0 if errors.is_empty() else 1)
