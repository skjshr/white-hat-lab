extends SceneTree

const UI = preload("res://scripts/interface.gd")
var ui
var game
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("workload ui timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ",label)

func frames(count: int = 4) -> void:
	for _i in count: await process_frame

func find_name(node: Node, prefix: String) -> Node:
	for child in node.get_children():
		if str(child.name).begins_with(prefix): return child
		var nested:=find_name(child,prefix)
		if nested != null:return nested
	return null

func capture_screen(name: String) -> void:
	if not capture:return
	await frames(8);await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/operations/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join(name+ ("-narrow" if narrow else "-wide") + ".png")
	check(get_root().get_texture().get_image().save_png(path)==OK,"capture "+name)
	print("CAPTURE ",path)

func run() -> void:
	ui=UI.new();root.add_child(ui);await frames(3);game=ui._game();game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"QA storage")
	check(ui._new_game() and game.choose_strategy("advisory") and game.start_free_career(),"career setup")
	game.state.cash=100000;game.state.credit=100000;game.state.skills={"advisory":10,"operations":10,"response":10};game._update_growth();game._make_offers()
	var offers: Array=game.state.offers.filter(func(item):return bool(item.get("unlocked",false)))
	check(offers.size()>=2,"two offers")
	if offers.size()<2:_finish();return
	var first: Dictionary=offers[0];var second: Dictionary=offers[1]
	for candidate in offers:
		if int(candidate.get("targets",1))>1:first=candidate;break
	check(game.choose_contract(str(first.id)),"first contract")
	var first_id:=str(first.id)
	var queued_a: bool=bool(game.dispatch_enqueue("aya",first_id,0))
	check(queued_a,"first queue item")
	check(game.choose_contract(str(second.id)),"second contract")
	var second_id:=str(second.id)
	# Keep B accepted as a separate live contract, while the second queued
	# target remains on A; this exercises cross-contract queue projection without
	# requiring a hardware prerequisite from B's chapter.
	var queued_b: bool=bool(game.dispatch_enqueue("ren",first_id,1))
	check(queued_b,"second queue item")
	# Put the real queued work close to the end of the current shift so the
	# forecast must expose carry-over/risk from the workload projection.
	game.state.clock_minutes=1070
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	ui._set_text_scale(1.3 if narrow else 1.0);root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_panel("board");await frames(8)
	ui.operations_choices.dispatch_selected={"kind":"normal","id":first_id,"target":0,"member":"aya"}
	ui._refresh_operations();await frames(6)
	var toolbar:=find_name(ui.modal_body,"DispatchTicketToolbar")
	var forecast: Node=ui.modal_body.find_child("DispatchForecast",true,false)
	check(toolbar != null,"dispatch toolbar")
	check(forecast is Label and not str(forecast.text).is_empty(),"selection forecast visible")
	check(ui.modal_body.find_child("DispatchTicketScroll",true,false)!=null,"ticket table usable")
	var staff_view: Node=ui.modal_body.find_child("OperationsView_staff",true,false)
	check(staff_view is Button,"staff allocation view available")
	if staff_view is Button:staff_view.pressed.emit()
	await frames(6)
	var load:=find_name(ui.modal_body,"DispatchLoad_aya")
	check(load is ProgressBar,"staff workload bar")
	var queue_nodes: Array[Node]=ui.modal_body.find_children("DispatchJob_*","VBoxContainer",true,false)
	check(queue_nodes.size()>=1,"queued work visible")
	if queue_nodes.size()>0:
		var plan:=find_name(queue_nodes[0],"DispatchPlan_")
		check(plan is Label and not str(plan.text).is_empty(),"queued finish/risk visible")
	var rect: Rect2=ui.modal.get_global_rect()
	check(rect.size.x<=root.size.x+2.0,"modal fits viewport")
	await capture_screen("workload-board")
	_finish()

func _finish() -> void:
	print("WORKLOAD_UI failures=%d" % failures.size())
	for item in failures:push_error(item)
	quit(0 if failures.is_empty() else 1)
