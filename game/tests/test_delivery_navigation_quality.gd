extends SceneTree

const UI = preload("res://scripts/interface.gd")
const GUIDE = preload("res://scripts/next_task_guide.gd")
const BUSINESS = preload("res://scripts/os_business_apps.gd")
var game
var ui
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(80).timeout.connect(func(): push_error("DELIVERY_NAVIGATION_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value: failures.append(label); print("FAIL ",label)

func frames(count := 4) -> void:
	for _i in count: await process_frame

func press(id: String) -> void:
	var button = ui.root.find_child(id,true,false)
	check(button is Button and button.is_visible_in_tree() and not button.disabled,"available "+id)
	if button is Button and not button.disabled:
		var ancestor: Node = button.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
			ancestor = ancestor.get_parent()
		await frames()
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(button.get_global_rect()),"reachable "+id)
		button.pressed.emit()
	await frames()

func offer(case_id: String) -> Dictionary:
	for item in game.state.offers:
		if str(item.case_id)==case_id and bool(item.unlocked) and bool(item.market_available): return item
	return {}

func business_state() -> Dictionary:
	var result: Dictionary = {}
	for key in ["current_contract_id","cash","profit","history","completed_ids","contract_contexts","vm_states","billing"]:
		var value = game.state.get(key)
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless": return
	await frames(8)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/ui-quality/delivery")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func start_case(story := false) -> Dictionary:
	if is_instance_valid(ui): ui.close_panel(false,false); ui.queue_free(); await frames()
	ui = UI.new(); root.add_child(ui); await frames()
	check(ui._new_game(),"new isolated company")
	game = ui._game(); game.set_process(false)
	game.set_settings({"resolution":"960x600" if narrow else "1440x900","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1440,900)
	ui._set_text_scale(1.3 if narrow else 1.0); ui.guided_intro.skip()
	check(game.choose_strategy("advisory"),"company strategy available")
	if story:
		check(game.accept_mission(),"story case accepted")
		ui.open_panel("terminal"); await frames()
		return {"id":"share"}
	check(game.start_free_career(),"career available")
	var selected := offer("service-2-case-0")
	check(not selected.is_empty(),"explicit ordinary network fixture available")
	if selected.is_empty(): return {}
	ui._select_contract(str(selected.id)); await frames()
	await press("AcceptContract")
	var accepted: Dictionary = business_state()
	ui._submit_quote(str(selected.id),int(selected.reward))
	check(business_state()==accepted,"repeat acceptance cannot duplicate contract or revenue")
	ui._operations_open(str(selected.id),0); await frames()
	return selected

func solve_ordinary() -> void:
	game.vm_run("ssh client")
	var machine = game._vm()
	var desired: Dictionary = game._scenario().get("desired",machine._legacy_desired())
	check(game.vm_write(game.vm_info().config_path,machine.configuration_text(desired)),"save real ordinary configuration")
	check(game.vm_run("systemctl restart "+str(game.vm_info().service)).contains("active (running)"),"apply ordinary configuration")
	for _round in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded",false)) and bool(probe.get("fresh",false)) and bool(probe.get("passed",false))): game.run_diagnostic(str(probe.id))
	ui.desktop._show_app("verify"); await frames()
	await press("DiagnosticValidate")
	check(game.state.checks.all(func(row):return bool(row.passed)),"real probes pass before delivery")

func run() -> void:
	game=root.get_node("Game")
	check(str(game.save_path).begins_with("user://qa-"),"QA profile required")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	var selected: Dictionary = await start_case()
	if selected.is_empty(): finish(); return
	var first_id:=str(selected.id)
	ui.desktop._show_app("receipt"); await frames()
	check(not BUSINESS.delivery_blockers(game).is_empty(),"uninspected work explains missing condition")
	await press("ReceiptResolve_verify-0")
	check(ui.desktop.current_app=="verify","missing-condition action opens diagnostic workspace")
	ui.desktop.drafts["/home/operator/flow-draft.txt"]="retain this draft"
	check(ui.close_panel(false,false),"return from first work")
	var other:=offer("advanced-portal")
	check(not other.is_empty(),"explicit second case available")
	ui._select_contract(str(other.id)); await frames(); await press("AcceptContract")
	ui._operations_open(str(other.id),0); await frames()
	ui.desktop._show_app("receipt"); await frames()
	var footer_buttons: Array = ui.desktop.widgets.receipt.footer.find_children("*","Button",true,false)
	check(not footer_buttons.any(func(button):return button.text == "設定編集" or button.text == "診断ラボ表示"),"advanced receipt hides legacy-only actions")
	await press("ReceiptReturnToWork")
	check(ui.desktop.current_app=="advanced","advanced receipt returns to the actual workbench")
	ui._operations_open(first_id,0); await frames()
	check(str(ui.desktop.drafts.get("/home/operator/flow-draft.txt",""))=="retain this draft","return restores the first case draft")
	check(game.dispatch_enqueue("aya",first_id,0),"queue a real colleague inspection")
	await solve_ordinary()
	check(not game.can_deliver(),"queued work still blocks delivery after probes pass")
	check(BUSINESS.delivery_blockers(game).any(func(row):return str(row.id)=="queue"),"queue blocker has an explicit reason")
	await capture("blocked-by-queue")
	await press("ReceiptResolve_queue")
	check(ui.current_kind=="board","queue blocker returns to operations")
	var queue: Array = game.dispatch_queue("aya")
	check(not queue.is_empty() and game.dispatch_remove("aya",str(queue[0].id)),"remove queued job through scheduling API")
	ui._operations_open(first_id,-1,"receipt"); await frames()
	check(game.can_deliver(),"work is deliverable after blocker is removed")
	await press("GuideDeliver")
	check(game.current_done(),"receipt delivers through real control")
	var completed:=business_state()
	ui.desktop._report(); ui.desktop._report()
	check(business_state()==completed,"repeated delivery cannot duplicate income, invoice or history")
	var next: Dictionary=GUIDE.resolve(game)
	check(str(next.route)=="board" and str(next.get("contract_id",""))==str(other.id),"completed case routes to remaining accepted work")
	await capture("completed-with-remaining")
	await press("ReceiptNextWork")
	check(ui.current_kind=="board","receipt uses guide navigation to remaining-work list")
	check(str(ui.operations_choices.get("dispatch_selected",{}).get("id",""))==str(other.id),"remaining case is selected without activation")
	check(business_state()==completed,"guide navigation does not mutate business state")
	await press("DispatchOpen")
	check(str(game.state.current_contract_id)==str(other.id),"remaining case opens only after user action")
	selected=await start_case()
	if selected.is_empty(): finish(); return
	await solve_ordinary(); await press("GuideDeliver")
	completed=business_state(); next=GUIDE.resolve(game)
	check(str(next.route)=="sales" and str(next.target)=="SalesBoard","no remaining work routes to an existing sales control")
	await capture("completed-ready-for-next")
	await press("ReceiptNextWork")
	check(ui.current_kind=="sales" and ui.board_selected_id.is_empty(),"receipt opens new inquiries directly")
	check(business_state()==completed,"sales navigation preserves completed contract and finances")
	check(ui.root.find_child("SalesBoard",true,false)!=null,"sales destination control exists")
	await start_case(true)
	await solve_ordinary(); await press("GuideDeliver")
	completed=business_state(); next=GUIDE.resolve(game)
	check(str(next.route)=="door" and str(next.target)=="DaySettle","story closeout uses the existing day-settlement control")
	await press("ReceiptNextWork")
	check(ui.current_kind=="door","story receipt opens day-settlement screen")
	check(ui.root.find_child("DaySettle",true,false)!=null,"story receipt destination control exists")
	check(business_state()==completed,"story closeout navigation does not settle or mutate finances")
	finish()

func finish() -> void:
	print("DELIVERY_NAVIGATION_PASS narrow="+str(narrow) if failures.is_empty() else "DELIVERY_NAVIGATION_FAIL count="+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
