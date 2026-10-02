extends SceneTree

var game
var office
var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args(); narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func(): push_error("office expansion timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ",label)

func frames(count := 4) -> void:
	for i in count: await process_frame

func press_e() -> void:
	var event := InputEventAction.new(); event.action="interact"; event.pressed=true; office._unhandled_input(event)

func passage_blocked() -> bool:
	var query := PhysicsRayQueryParameters3D.create(Vector3(5.4,1.4,3.15),Vector3(6.7,1.4,3.15),1)
	return not office.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func desk_collision_present() -> bool:
	var query := PhysicsRayQueryParameters3D.create(Vector3(8.2,0.4,2.5),Vector3(8.2,0.4,0.5),1)
	return not office.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func capture(label: String) -> void:
	if not capture_enabled: return
	office._process(5.0)
	await frames(8); await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/v119/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func run() -> void:
	game=root.get_node("Game"); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"isolated QA storage")
	game.new_game(); game.state.cash=120000
	check(not game.buy_office_expansion(),"story mode cannot expand")
	check(game.choose_strategy("operations") and game.start_free_career(),"career setup")
	office=load("res://scripts/office.gd").new(); root.add_child(office)
	office.started=true; office.set_process(false); office.player.set_physics_process(false)
	office.ui.controls.menu.hide(); office.ui.current_kind=""; office.ui.root.hide()
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	await physics_frame; await frames()
	check(passage_blocked(),"unbuilt annex physically closed")
	check(not game.buy_equipment("annexdesk_a"),"cannot order desk before construction")
	var before: Dictionary = game.state.duplicate(true); var path: String = game.save_path
	game.save_path="user://missing-expansion-"+str(OS.get_process_id())+"/save.json"
	check(not game.buy_office_expansion() and game.state==before,"failed construction order rolls back funds and state")
	game.save_path=path
	office.ui.root.show();office.ui.open_panel("shop"); await frames()
	# The current catalog selects a product first and renders its sole order
	# action in the modal footer. Follow that public UI path.
	var expansion = office.ui.modal_body.find_child("EquipmentSelect_office_expansion",true,false)
	check(expansion is Button and not expansion.disabled,"construction selectable in catalog")
	if expansion is Button and not expansion.disabled: expansion.pressed.emit(); await frames()
	var buy = office.ui.modal_footer.find_child("BuyOfficeExpansion",true,false)
	check(buy!=null and not buy.disabled,"construction order button available")
	if buy!=null and not buy.disabled: buy.pressed.emit()
	check(int(game.state.cash)==int(before.cash)-28000,"one construction fee charged")
	check(not game.buy_office_expansion(),"duplicate construction order rejected")
	check(not game.office_expanded() and game.staff_capacity()==0,"order does not create seats")
	await capture("expansion-ordered")
	check(game.save_game() and game.load_game(),"construction order survives reload")
	before=game.state.duplicate(true); game.save_path="user://missing-expansion-day-"+str(OS.get_process_id())+"/save.json"
	check(not game.end_day() and game.state==before and not game.office_expanded(),"failed day change keeps unfinished construction")
	game.save_path=path
	check(game.end_day() and game.office_expanded(),"next business day completes construction")
	office.ui.close_panel(); await physics_frame; await frames()
	check(not passage_blocked(),"completed doorway physically traversable")
	check(not desk_collision_present(),"unbought desks have no invisible collision")
	check(game.staff_capacity()==0 and game.contract_capacity()==3,"empty floor adds no work capacity")
	var base_care := int(game.care_portfolio().capacity)
	for id in ["annexdesk_a","annexdesk_b","teamdesk"]:
		var old_capacity := int(game.staff_capacity())
		check(game.buy_equipment(id),"desk order "+id)
		check(int(game.staff_capacity())==old_capacity,"ordered desk has no capacity "+id)
		game.advance_delivery(31.0)
		var box: Node3D=office.delivery._boxes[id]
		office.player.position=box.global_position+Vector3(0,-0.21,-1.25)
		office.player.camera.look_at(box.global_position)
		await physics_frame; await frames()
		office._process(0.0)
		check(str(office.focused.get("delivery_id",""))==id,"delivered box reachable through actual focus ray "+id)
		press_e()
		check(str(game.delivery_for(id).get("status",""))=="carried","physical pickup "+id)
		office.focused={}; press_e()
		check(str(game.delivery_for(id).get("status",""))=="placing","physical placement mode "+id)
		var slot: Vector3=office._delivery_slots()[game.equipment_slot(id)]
		office.player.global_position=slot+Vector3(0,0,5);office.player.camera.look_at(slot);office._process(0.0);press_e()
		check(id not in game.state.equipment,"distant install refused "+id)
		office.player.global_position=slot+Vector3(0,0,1.6);office.player.camera.look_at(slot);await physics_frame;office._process(0.0);press_e()
		check(id in game.state.equipment and game.staff_capacity()==old_capacity+1,"nearby install adds real workplace "+id)
		await frames()
	check(game.staff_capacity()==3 and game.contract_capacity()==7,"three independent seats and seven contract slots")
	await physics_frame
	check(desk_collision_present(),"installed desk has physical collision")
	check(int(game.care_portfolio().capacity)==base_care+4,"installed desks add exact maintenance capacity")
	for id in ["mio","sora","haru"]: check(game.hire_staff(id),"hire staff "+id)
	var workplaces: Array[String]=[]
	for id in ["mio","sora","haru"]:
		var workplace := str(game.staff_workplace(id));check(not workplace.is_empty() and workplace not in workplaces,"unique workplace "+id);workplaces.append(workplace)
	office._sync_hired_staff();await frames()
	check(office.staff_actors.size()==3,"three hired actors present")
	for entry in office.staff_actors.values():
		var routine = entry.routine
		routine.set_paused(false)
		for i in 200: routine.tick(0.1,float(game.clock_minutes()))
		check(entry.actor.position.distance_to(routine.seat_point)<0.12,"actor reaches assigned chair")
		check(routine.waypoints.return_path[-1]==routine.seat_point,"return path finishes at own seat")
	office.player.position=Vector3(7.0,0.05,4.15);office.player.camera.look_at(Vector3(9.25,1.05,1.1))
	await capture("expansion-furnished")
	check(game.save_game() and game.load_game(),"furnished annex and staff reload")
	check(game.office_expanded() and game.staff_capacity()==3,"reload preserves actual capacity")
	game.state.staff.mio.erase("workplace")
	check(game.save_game() and game.load_game(),"old hired staff seat migrates")
	check(game.staff_workplace("mio")=="teamdesk","old staff retains original team desk")
	var wages := int(game.staff_summary().due); var cash_before := int(game.state.cash)
	check(wages>0 and game.end_day(),"expanded staff day settles")
	check(int(game.state.cash)==cash_before-wages,"all hired staff incur payroll")
	game.new_game();await physics_frame;await frames()
	check(not game.office_expanded() and passage_blocked(),"new company closes annex")
	check(not is_instance_valid(office.annex_root) or not office.annex_root.visible,"new company removes annex visuals")
	root.get_node("Soundscape").unmount_world(office)
	await create_timer(0.15).timeout
	print("OFFICE_EXPANSION failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
