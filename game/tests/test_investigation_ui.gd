extends "res://tests/test_specialist_workspaces.gd"

var native_edits:=0
var row_selections:=0
var resource_clicks:=0
var native_record_clicks:=0
var requested_case := ""

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless": return
	await frames(6); await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../../audit/all-services/investigations/screens")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): folder=argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func key(code: Key,unicode_value: int=0,ctrl:=false) -> void:
	for down in [true,false]:
		var event:=InputEventKey.new(); event.keycode=code; event.unicode=unicode_value; event.ctrl_pressed=ctrl; event.pressed=down; Input.parse_input_event(event); Input.flush_buffered_events()

func reachable(control: Control) -> void:
	var ancestor:=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await frames(4)
	check(root.get_visible_rect().has_point(control.get_global_rect().get_center()),"input reachable "+str(control.name))

func mouse(point: Vector2) -> Control:
	# Control rectangles are logical canvas coordinates; parsed mouse events use
	# window pixels, matching the common click() helper under canvas stretching.
	var pixels := point * Vector2(root.size) / root.get_visible_rect().size
	var motion:=InputEventMouseMotion.new(); motion.position=pixels; motion.global_position=pixels; Input.parse_input_event(motion); Input.flush_buffered_events()
	var hovered := root.gui_get_hovered_control()
	for down in [true,false]:
		var event:=InputEventMouseButton.new(); event.position=pixels; event.global_position=pixels; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down; Input.parse_input_event(event); Input.flush_buffered_events()
	return hovered

func type_text(id: String,value: String) -> void:
	var field=node(id); check(field is LineEdit or field is TextEdit,"input "+id)
	if not (field is LineEdit or field is TextEdit): return
	await reachable(field)
	field = node(id)
	var hovered := mouse(field.get_global_rect().get_center())
	check(hovered == field or (hovered != null and field.is_ancestor_of(hovered)), "pointer reaches actual input " + id)
	await frames(2); field = node(id)
	check(field.has_focus(),"mouse focus "+id)
	if not field.has_focus(): print("INVESTIGATION_INPUT_DIAGNOSTIC ",JSON.stringify({"id":id,"rect":str(field.get_global_rect()),"pixels":str(root.size),"logical":str(root.get_visible_rect().size),"hovered":str(hovered),"focus":str(root.gui_get_focus_owner())}))
	key(KEY_A,0,true); key(KEY_BACKSPACE)
	for i in value.length():
		if value[i]=="\n": key(KEY_ENTER)
		else: key(KEY_NONE,value.unicode_at(i))
	await frames(3); native_edits+=1
	check(str(node(id).text)==value,"native text "+id)

func hunt_select(ids: Array) -> void:
	for id in ids:
		var tree: Tree=node("HuntEvents"); await reachable(tree)
		var row:=tree.get_root().get_first_child()
		while row!=null and str(row.get_metadata(0).id)!=str(id): row=row.get_next()
		check(row!=null,"hunt raw record "+str(id))
		if row==null: continue
		tree.scroll_to_item(row); await frames(2)
		var bounds:=tree.get_item_area_rect(row,0)
		mouse(tree.global_position+bounds.position+Vector2(12,bounds.size.y/2)); await frames(4); row_selections+=1
	check(desk.advanced_ui["advanced-hunt"].get("selected_events",[]).size()==ids.size(),"native raw-record selection")

func latest() -> Dictionary:
	var items: Array=game.advanced_view().observations
	return items.back() if not items.is_empty() else {}

func select_record(table_id: String,id: String) -> void:
	var tree: Tree=node(table_id);await reachable(tree)
	var row:=tree.get_root().get_first_child()
	while row!=null and str(row.get_metadata(0).id)!=id:row=row.get_next()
	check(row!=null,"original record "+id)
	if row==null:return
	tree.scroll_to_item(row);await frames(2)
	var bounds:=tree.get_item_area_rect(row,1)
	mouse(tree.global_position+bounds.get_center());await frames(6);native_record_clicks+=1
	var selected_id: String=str(desk.advanced_ui["advanced-hunt"].get("event","")) if table_id=="HuntEvents" else str(game.advanced_view().recovery.selected_snapshot)
	check(selected_id==id,"native record selection "+id)

func detail_visible(id: String) -> void:
	var control: Control=node(id);var scroll: Control=node("InvestigationScroll")
	check(control!=null,"visible detail exists "+id)
	if control!=null:check(control.get_global_rect().intersection(scroll.get_global_rect()).size.y>=40,"selected detail appears without extra scrolling "+id)

func resource_node(path: String) -> Button:
	var graph: Control = node("NetworkResources")
	if graph == null: return null
	for target in graph.find_children("*", "Button", true, false):
		if str(target.get_meta("path", "")) == path: return target as Button
	return null

func network_mark() -> Dictionary:
	return {"advanced":game.state.advanced.duplicate(true),"work":game.state.work.duplicate(true),"clock":game.state.clock_minutes,"revision":game.state.revision,"cash":game.state.cash,"checks":game.state.checks.duplicate(true)}

func open_resource(path: String) -> void:
	var target := resource_node(path)
	check(target != null,"visible graphical resource "+path)
	if target == null: return
	var before := network_mark()
	await click(str(target.name)); resource_clicks += 1
	check(network_mark() == before,"selecting the diagram changes no observation, clock or cost: "+path)
	await click("NetworkBrowse" if path in ["share01", "evidence"] else "NetworkRead")
	check(str(latest().target)==path,"explicit measurement requests the selected resource "+path)

func read_path(path: String) -> void:
	var field: Control = node("NetworkPath")
	if field == null or not field.is_visible_in_tree(): await click("NetworkShowPath")
	await type_text("NetworkPath", path); await click("NetworkReadPath")

func fixed_feedback() -> void:
	var label: Control=node("InvestigationFeedback")
	check(label!=null and label.is_visible_in_tree(),"actual action feedback visible")
	if label!=null:check(root.get_visible_rect().has_point(label.get_global_rect().get_center()),"feedback remains in viewport")
	var nav: Control=node("InvestigationNavigation")
	check(nav!=null and root.get_visible_rect().has_point(nav.get_global_rect().get_center()),"work navigation remains in viewport")

func run_investigation_cases() -> void:
	if requested_case in ["", "advanced-hunt"] and await start_case("advanced-hunt"):
		await hunt_select(["evt-00","evt-01"]); await click("HuntCorrelate"); await click("HuntClearSelection")
		await hunt_select(["evt-04","evt-05","evt-06"]); await click("HuntCorrelate")
		for id in ["evt-04","evt-05"]:
			await select_record("HuntEvents",id);detail_visible("HuntOriginalRecord");await click("HuntPinEvent")
		await click("HuntOrderPin_CHG-114"); await capture("hunt-correlation")
		await click("HuntTab_response"); await click("HuntHost_gw01"); await click("HuntProbeBusiness")
		check(not game.advanced_view().checks[3].passed,"wrong isolation affects actual business")
		await click("HuntHost_gw01"); await click("HuntSession_sid-r44"); await click("HuntTask_task-sync")
		await click("HuntProbeSecurity"); await click("HuntProbeBusiness"); await capture("hunt-response")
		fixed_feedback()
		await click("HuntTab_results"); await verify_case("advanced-hunt")
	if requested_case in ["", "advanced-pentest"] and await start_case("advanced-pentest"):
		await open_resource("share01")
		await read_path("share01/does-not-exist")
		check(int(latest().status)==404,"arbitrary unknown resource returns 404")
		await open_resource("share01/deploy.env")
		detail_visible("NetworkBytes")
		check(resource_node("share01/deploy.env") != null and resource_node("share01/daily.csv") != null,"observed directory objects remain on the diagram after file read")
		check(str(node("NetworkResponseTarget").text).contains("share01/deploy.env"),"actual response target is explicit")
		var leak:=latest(); var token: String=str(leak.data.bytes).split("TOKEN=")[1].strip_edges()
		await click("NetworkPinResponse"); await click("NetworkShowAuth")
		await type_text("NetworkUsername","svc-report"); await type_text("NetworkCredential",token); await click("NetworkAuthenticate")
		await open_resource("evidence")
		await open_resource("evidence/proof.csv"); var proof:=latest()
		await click("NetworkPinResponse"); await capture("network-observed-file")
		fixed_feedback();await click("NetworkTab_report")
		await click("NetworkEvidence_"+str(leak.id)); await click("NetworkEvidence_"+str(proof.id)); await click("NetworkSubmit")
		await capture("network-evidence-report")
		await click("NetworkCustomerFix"); await click("NetworkRetest"); await open_resource("evidence/proof.csv"); check(int(latest().status)==401,"previous service session invalid after customer fix")
		await click("NetworkResetSession"); await read_path("share01/deploy.env")
		check(int(latest().status)==403,"employee former request denied")
		await read_path("share01/daily.csv")
		check(int(latest().status)==200,"employee normal daily report works")
		await verify_case("advanced-pentest")
	if requested_case in ["", "advanced-recovery"] and await start_case("advanced-recovery"):
		await select_record("RecoverySnapshots","snap-1410");detail_visible("RecoveryCandidateComparison");await capture("recovery-candidates")
		await click("RecoveryShowOriginal")
		check(str(node("RecoveryOriginal_ledger").text)==str(latest().data.files.ledger),"original candidate bytes remain available")
		await click("RecoveryStageRestore"); await click("RecoveryScan")
		await type_text("RecoveryLedger","id,amount\n001,100\n")
		check(str(node("RecoveryDraftState").text)=="未保存の入力あり","draft status changes with native input")
		var saved_ledger: String=str(game.advanced_view().recovery.staged.ledger)
		await click("RecoverySelect_startup");await click("RecoverySelect_ledger")
		check(str(node("RecoveryLedger").text)=="id,amount\n001,100\n","file switching retains unsaved draft")
		check(str(game.advanced_view().recovery.staged.ledger)==saved_ledger,"file switching does not save draft")
		await click("RecoverySaveLedger");await click("RecoverySelect_startup")
		await type_text("RecoveryStartup","none"); await click("RecoverySaveStartup"); await click("RecoveryScan")
		await capture("recovery-stage")
		await click("RecoveryToTests")
		await click("RecoveryStart_app"); check(int(latest().status)==409,"dependency failure is observed")
		fixed_feedback()
		await click("RecoveryTab_release"); await click("RecoveryIsolate"); await click("RecoveryRotate"); await click("RecoveryRevoke_sid-sync-17")
		for service in ["identity","database","app"]: await click("RecoveryStart_"+service)
		await click("RecoveryProbeBusiness"); await click("RecoveryPublish"); await click("RecoveryReconnect")
		check(str(game.advanced_view().recovery.production.ledger).contains("001,100"),"real production contains restored ledger")
		await capture("recovery-release"); await click("RecoveryTab_results"); await verify_case("advanced-recovery")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): requested_case = arg.trim_prefix("--case=")
	if requested_case not in ["", "advanced-hunt", "advanced-pentest", "advanced-recovery"]:
		check(false, "unknown investigation case filter"); quit(1); return
	game=root.get_node("Game"); game.set_process(false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1440,900)
	await run_investigation_cases()
	if is_instance_valid(desk): desk.queue_free(); await frames()
	print("INVESTIGATION_UI assertions=",assertions," failures=",failures.size()," native_clicks=",clicks," native_edits=",native_edits," native_row_checks=",row_selections," native_resource_clicks=",resource_clicks," native_record_clicks=",native_record_clicks," signal_table_selections=",selections," narrow=",narrow)
	quit(0 if failures.is_empty() else 1)
