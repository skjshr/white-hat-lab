extends SceneTree
const Rules=preload("res://scripts/placement_rules.gd")
var game
var office
var failures: Array[String]=[]
var capture_enabled:=false
var narrow:=false

func _init() -> void:
	capture_enabled="--capture" in OS.get_cmdline_user_args();narrow="--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func():push_error("layout integration timeout");quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:failures.append(label);print("FAIL ",label)

func frames(count:=4) -> void:
	for i in count:await process_frame

func press_e() -> void:
	var event:=InputEventAction.new();event.action="interact";event.pressed=true;office._unhandled_input(event)

func press_r() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_R;event.pressed=true;office._unhandled_input(event)

func order(id: String) -> Dictionary:
	for value in game.delivery_orders():
		if str(value.id)==id:return value
	return {}

func capture(label: String) -> void:
	if not capture_enabled:return
	await frames(8);await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/v121/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func walk_staff() -> void:
	for i in 350:
		for actor in office.colleagues:
			var routine=actor.get_meta("office_colleague_routine")
			routine.set_paused(false);routine.tick(0.1,float(game.clock_minutes()))
		office._sync_hired_staff()

func load_synthetic_fixed_slot_fixture() -> bool:
	# This is a generated schema fixture, NOT the unavailable v1.20 release save.
	# Build a valid company through public APIs, then omit absolute placement
	# fields to exercise Game.load_game's monitor migration and Rules' fixed-slot
	# fallback. All later physical placement/staff assertions run unchanged.
	check(game.new_game() and game.choose_strategy("operations") and game.start_free_career(),"synthetic layout career")
	game.state.cash=200000;game.state.credit=1000000;game.state.skills={"advisory":10,"operations":10,"response":10}
	check(game.buy_office_expansion() and game.end_day() and game.office_expanded(),"synthetic annex opened by construction")
	for id in ["monitor","plant","backup","diagnostic","workstation","teamdesk","annexdesk_a","annexdesk_b"]:
		check(game.buy_equipment(id),"synthetic equipment order "+id)
		game.advance_delivery(31.0)
		check(game.take_delivery(id) and game.place_delivery(id,game.equipment_slot(id),PI if id in ["teamdesk","workstation"] else 0.0),"synthetic equipment installed "+id)
	for id in ["mio","sora","haru"]:check(game.hire_staff(id),"synthetic occupied workplace "+id)
	if not failures.is_empty():return false
	game.state.clock_minutes=540
	var fixture: Dictionary=game.state.duplicate(true)
	for entry in fixture.delivery_orders:
		entry.erase("install_position")
		if str(entry.id)=="monitor":entry.erase("rotation_y")
	var cash_before:=int(fixture.cash)
	var file:=FileAccess.open(game.save_path,FileAccess.WRITE)
	check(file!=null,"write synthetic fixed-slot fixture")
	if file==null:return false
	file.store_string(JSON.stringify(fixture));file.close()
	check(game.load_game() and str(game.state.get("last_load_error","")).is_empty(),"load synthetic fixed-slot schema without backup fallback")
	check(int(game.state.cash)==cash_before,"schema migration does not repurchase equipment")
	for id in ["plant","backup","diagnostic","workstation","teamdesk","annexdesk_a","annexdesk_b"]:
		check(Rules._stored_position(order(id)).distance_to(Rules.FIXED_SLOTS[id])<0.01,"legacy fixed slot remains stable "+id)
	print("LAYOUT_FIXTURE generated fixed-slot schema; not an archived v1.20 save")
	return failures.is_empty()

func run() -> void:
	game=root.get_node("Game");game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"QA profile")
	if not load_synthetic_fixed_slot_fixture():print("LAYOUT_CUSTOMIZATION failures=",failures.size());quit(1);return
	check(game.state.equipment.size()==8 and game.staff_capacity()==3,"legacy equipment and staff capacity")
	var monitor := order("monitor")
	check(Rules.monitor_position_error(monitor.get("install_position",[]),float(monitor.get("rotation_y",0)),game.delivery_orders(),true).is_empty(),"legacy monitor fits its actual tabletop")
	office=load("res://scripts/office.gd").new();root.add_child(office);office.started=true;office.set_process(false)
	office.player.set_physics_process(false);office.ui.controls.menu.hide();office.ui.current_kind="";office.ui.root.hide()
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	await physics_frame;await frames()
	check(not game.begin_equipment_move("teamdesk"),"occupied on-shift desk cannot disappear under worker")
	game.state.clock_minutes=1110;game.changed.emit();office._sync_hired_staff();walk_staff()
	for entry in office.staff_actors.values():check(entry.routine.is_departed(),"staff leaves before rearrangement")
	var initial_cash:=int(game.state.cash);var initial_capacity:=int(game.contract_capacity())
	var moves: Array=[
		["annexdesk_a",Vector3(7.3,0,1.0),0.0],
		["annexdesk_b",Vector3(10.4,0,1.2),1.5*PI],
		["teamdesk",Vector3(9.2,0,4.1),PI],
		["workstation",Vector3(-1.1,0,-3.5),PI],
		["backup",Vector3(2.0,0,0.0),0.0],
		["diagnostic",Vector3(-1.8,0,1.8),0.0],
		["plant",Vector3(-2.0,0,0.3),0.0]
	]
	for move in moves:
		var id:=str(move[0]);var at: Vector3=move[1];var yaw: float=move[2]
		office.focused={"action":"equipment_"+id+"_move"};press_e()
		check(office.delivery._placing_id==id,"E input begins moving "+id)
		var original: Dictionary=order(id).duplicate(true)
		office.player.position=Vector3(0.0,0.05,3.8)
		for i in 4:
			if absf(wrapf(float(order(id).rotation_y)-yaw,-PI,PI))<0.01:break
			press_r()
		await physics_frame
		office.delivery.update_placement_preview([at.x,0.0,at.z],yaw)
		check(office.delivery.placement_valid(),"valid new layout "+id+" "+office.delivery.placement_reason())
		if id=="annexdesk_a":
			office.player.position=Vector3(6.9,0.05,4.1);office.player.camera.look_at(Vector3(8.5,0.9,1.1))
			await capture("layout-preview")
			var path: String=game.save_path;game.save_path="user://missing-layout-"+str(OS.get_process_id())+"/save.json"
			check(not office.delivery.interact("confirm",id),"failed save rejects placement")
			check(order(id).get("install_position",[])==original.get("install_position",[]),"failed save retains origin")
			game.save_path=path
		press_e()
		check(not office.delivery.is_placing(),"E input commits new layout "+id)
		await frames();await physics_frame
		check(office.upgrades[id].global_position.distance_to(at)<0.01,"rendered position matches saved position "+id)
		check(absf(wrapf(office.upgrades[id].rotation.y-yaw,-PI,PI))<0.01,"rendered rotation matches saved rotation "+id)
	check(int(game.state.cash)==initial_cash and int(game.contract_capacity())==initial_capacity,"moving does not charge money or alter capacity")
	check(game.begin_equipment_move("plant"),"cancel fixture start")
	check(not game.place_delivery_at("plant",[6.0,0.0,3.15],0.0),"annex doorway cannot be blocked")
	check(game.cancel_equipment_move("plant"),"cancel restores installed asset")
	check(office.delivery.interact("place_start","plant"),"live preview fixture")
	var preview: Array=[-2.0,0.0,0.3]
	office.player.position=Vector3(-2.0,0.05,0.3);await physics_frame
	office.delivery.update_placement_preview(preview,0.0)
	check(not office.delivery.placement_valid(),"actor inside preview blocks placement")
	office.player.position=Vector3(0,0.05,3.8);await physics_frame
	office.delivery.update_placement_preview(preview,0.0)
	check(office.delivery.placement_valid(),"same preview recovers after actor leaves")
	office.delivery.update_placement_preview(preview,0.0,false)
	check(not office.delivery.placement_valid(),"same preview respects invalid floor override")
	check(office.delivery.interact("cancel","plant"),"live preview cleanup")
	check(game.begin_equipment_move("backup") and game.save_game() and game.load_game(),"save during move reload")
	check(str(order("backup").status)=="installed" and Rules._stored_position(order("backup")).distance_to(Vector2(2,0))<0.01,"reload cancels pending move at its original position")
	check(game.end_day(),"normal next business day after rearrangement")
	office._sync_hired_staff();walk_staff();await frames()
	for entry in office.staff_actors.values():
		var expected:=Rules.workplace(order(str(entry.workplace)))
		check(entry.actor.position.distance_to(expected.seat)<0.12,"worker reaches moved rotated desk "+str(entry.workplace))
		check(absf(wrapf(entry.actor.rotation.y-float(expected.seat_yaw),-PI,PI))<0.06,"worker faces moved desk "+str(entry.workplace))
		entry.routine.request_break()
	walk_staff()
	for entry in office.staff_actors.values():
		entry.routine._return_to_work()
	walk_staff()
	for entry in office.staff_actors.values():check(entry.actor.position.distance_to(entry.routine.seat_point)<0.12,"return from break reaches own moved seat")
	for entry in office.staff_actors.values():
		var routine=entry.routine
		routine.request_break();routine.tick(0.2,float(game.clock_minutes()));routine.tick(0.1,float(game.clock_minutes()))
		check(entry.actor.position.distance_to(routine.seat_point)>0.15,"worker entered chair aisle")
		routine.update_workplace(routine.waypoints)
		check(not routine._route.is_empty(),"layout refresh preserves mid-chair route")
	walk_staff()
	for entry in office.staff_actors.values():entry.routine._return_to_work()
	walk_staff()
	for entry in office.staff_actors.values():check(entry.actor.position.distance_to(entry.routine.seat_point)<0.12,"mid-chair reroute finishes without teleporting")
	for actor in office.colleagues:actor.get_meta("office_colleague_routine").request_break()
	walk_staff()
	for actor in office.colleagues:actor.get_meta("office_colleague_routine")._return_to_work()
	walk_staff()
	for actor in office.colleagues:check(actor.position.distance_to(actor.get_meta("office_colleague_routine").seat_point)<0.12,"all original and hired staff return after layout change")
	office.player.position=Vector3(6.9,0.05,4.1);office.player.camera.look_at(Vector3(9.2,1.1,1.9))
	await capture("layout-furnished")
	if capture_enabled:
		office.ui.root.show();office.ui.open_panel("shop");await frames()
		await capture("layout-catalog")
	print("LAYOUT_CUSTOMIZATION failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
