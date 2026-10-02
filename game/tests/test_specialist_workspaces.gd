extends SceneTree

const CATALOG = preload("res://scripts/case_catalog.gd")
var game
var desk
var failures: Array[String]=[]
var assertions:=0
var clicks:=0
var selections:=0
var edits:=0
var narrow:=false
var capture_enabled:=false

func _init() -> void:
	narrow="--narrow" in OS.get_cmdline_user_args(); capture_enabled="--capture" in OS.get_cmdline_user_args()
	create_timer(170).timeout.connect(func(): print("FAIL specialist timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions+=1
	if not ok: failures.append(label); print("FAIL ",label)

func frames(count:=4) -> void:
	for _i in count: await process_frame

func node(id: String) -> Node:
	return desk.find_child(id,true,false) if is_instance_valid(desk) else null

func reveal(id: String) -> void:
	var current: Node=node(id)
	while current!=null:
		if current.has_meta("workbench_stage") and not current.is_visible_in_tree():
			await click("SpecialistStage_"+str(current.get_meta("workbench_stage")))
			return
		current=current.get_parent()

func click(id: String) -> void:
	await reveal(id)
	var control=node(id)
	check(control is BaseButton and not control.disabled,"action "+id)
	if not control is BaseButton or control.disabled: return
	check(control.is_visible_in_tree(),"rendered action "+id)
	var ancestor: Node=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await frames(3)
	if DisplayServer.get_name()=="headless":
		if control is CheckBox: control.button_pressed=not control.button_pressed
		control.pressed.emit()
	else:
		var point: Vector2=control.get_global_rect().get_center()
		check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(point),"visible "+id)
		var motion:=InputEventMouseMotion.new(); motion.position=point; Input.parse_input_event(motion)
		var down:=InputEventMouseButton.new(); down.position=point; down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; Input.parse_input_event(down)
		await frames(1)
		var up:=InputEventMouseButton.new(); up.position=point; up.button_index=MOUSE_BUTTON_LEFT; up.pressed=false; Input.parse_input_event(up)
	clicks+=1
	await frames(5)

func edit(id: String, value: String) -> void:
	await reveal(id)
	var control=node(id)
	check(control is LineEdit,"input "+id)
	if control is LineEdit: control.text=value; control.text_changed.emit(value); edits+=1

func option(id: String, value: String) -> void:
	await reveal(id)
	var control=node(id)
	check(control is OptionButton,"selection "+id)
	if not control is OptionButton: return
	for i in control.item_count:
		if str(control.get_item_metadata(i))==value:
			control.select(i); control.item_selected.emit(i); selections+=1; return
	check(false,"choice "+id+" "+value)

func tree_select(id: String, wanted: String) -> void:
	await reveal(id)
	var control=node(id)
	check(control is Tree,"table "+id)
	if not control is Tree: return
	var row: TreeItem=control.get_root().get_first_child()
	while row!=null:
		if str(row.get_metadata(0).get("id",""))==wanted:
			row.select(0); control.item_selected.emit(); selections+=1; await frames(); return
		row=row.get_next()
	check(false,"row "+wanted)

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless": return
	await frames(6); await RenderingServer.frame_post_draw
	var folder: String=ProjectSettings.globalize_path("res://../artifacts/all-services/specialists")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func capture_control(id: String, label: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless": return
	await reveal(id)
	var control: Control=node(id)
	check(control!=null,"capture control "+id)
	if control==null: return
	var ancestor: Node=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await capture(label)

func start_case(id: String) -> bool:
	if is_instance_valid(desk): desk.queue_free(); await frames()
	game.new_game()
	var definition: Dictionary=CATALOG.by_id(id)
	game.choose_strategy(str(definition.category)); game.start_free_career()
	game.state.skills={"advisory":10,"operations":10,"response":10}; game.state.peak_profit=1000000000; game.state.credit=1000000; game.state.market_leads=[id]; game.state.market_day=game.state.day; game._make_offers()
	var offer: Dictionary={}
	for candidate in game.state.offers:
		if str(candidate.case_id)==id: offer=candidate; break
	check(not offer.is_empty(),"offer "+id)
	if offer.is_empty(): return false
	offer.market_available=true
	game.set_offer_quote(str(offer.id),int(game.contract_quote(offer).estimated_fee))
	check(game.choose_contract(str(offer.id)),"accept "+id)
	game.set_process(false)
	game.settings.text_scale=1.3 if narrow else 1.0
	desk=load("res://scripts/desktop.gd").new(); root.add_child(desk); desk.setup(game); desk._show_app("advanced")
	await frames(8)
	desk.windows.advanced.maximized=true; desk.windows.advanced.position=Vector2.ZERO; desk.windows.advanced.size=desk.workspace.size; desk._refresh_advanced()
	await frames(5)
	check(str(desk.widgets.advanced.get("family",""))==id,"specialist router "+id)
	if node("SpecialistStatus")!=null:
		for metric in node("SpecialistStatus").get_children():
			check(metric.size.y<60,"status remains a horizontal phrase "+id)
	await capture(id+"-start")
	return true

func verify_case(id: String) -> void:
	await click("AdvancedVerify")
	check(game.can_deliver(),id+" deliverable")
	var before: Dictionary=game.state.advanced.duplicate(true)
	check(desk._save_session(),id+" save desktop")
	desk.queue_free(); await frames()
	desk=load("res://scripts/desktop.gd").new(); root.add_child(desk); desk.setup(game); desk._show_app("advanced"); await frames(6)
	check(game.state.advanced==before,id+" reopen does not change model")
	await capture(id+"-result")

func api_request(actor: String, operation: String, resource: String, pin:=false) -> void:
	await option("Spec_api_actor",actor); await option("Spec_api_operation",operation); await edit("Spec_api_resource",resource)
	await click("ApiSend")
	if pin:
		var records: Array=game.advanced_view().workspace.requests
		await tree_select("ApiRequests",str(records.back().evidence_id)); await click("ApiPin")

func run() -> void:
	game=root.get_node("Game"); game.set_process(false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1440,900)
	await run_specialist_cases()
	if is_instance_valid(desk): desk.queue_free(); await frames()
	print("SPECIALIST_WORKSPACES assertions=",assertions," failures=",failures.size()," engine_clicks=",clicks," selections=",selections," field_edits=",edits," narrow=",narrow)
	quit(0 if failures.is_empty() else 1)

func run_specialist_cases() -> void:
	if await start_case("advanced-cloud"):
		await click("CloudRead_app-19"); await click("CloudRead_app-72")
		check(str(game.advanced_view().workspace.requests.back().body).contains("L-001"),"cloud actual ledger bytes")
		await click("CloudPin_app-72"); await click("CloudGrant_app-72"); await click("CloudSession_app-72")
		await click("CloudRead_app-19"); await click("CloudRead_app-72")
		check(int(game.advanced_view().workspace.requests.back().status)==403,"cloud rejected access")
		await capture_control("CloudResponses","advanced-cloud-access-results")
		await click("CloudVerify"); await verify_case("advanced-cloud")
	if await start_case("advanced-detection"):
		var original: Dictionary=game.state.advanced.duplicate(true)
		await click("SpecialistStage_1")
		var observation: Dictionary=game.advanced_view().workspace.events[2]
		await click("DetectionEvent_"+str(observation.id))
		check(str(node("Spec_rule_process").text)==str(observation.process),"event selection copies observed process into draft")
		check(game.state.advanced==original,"event selection does not apply a rule")
		await click("DetectionReplay"); check(not game.advanced_view().workspace.notified,"incomplete collection not success")
		await edit("Spec_rule_process","invoice_update.exe"); await edit("Spec_rule_threshold","2")
		await click("Spec_source_network"); await click("Spec_notification")
		await click("DetectionApply"); await click("DetectionReplay")
		var data: Dictionary=game.advanced_view().workspace
		check(data.replayed and int(data.false_positive)==0 and int(data.false_negative)==0,"detection recomputed matches")
		await capture_control("DetectionEvents","advanced-detection-replayed-events")
		await click("DetectionVerify"); await verify_case("advanced-detection")
	if await start_case("advanced-malware"):
		await click("MalwareStatic")
		await edit("Spec_sandbox_date","2026-09-22"); await click("MalwareConditions"); await click("MalwareRun"); await click("MalwareDerive")
		check(game.advanced_view().workspace.indicators.is_empty(),"inactive specimen is not proven clean")
		await edit("Spec_sandbox_date","2026-09-21"); await click("Spec_sandbox_network"); await click("MalwareConditions"); await click("MalwareRun"); await click("MalwareDerive"); await click("MalwareHunt")
		await capture_control("MalwareObservations","advanced-malware-experiments")
		await click("MalwareProcess_endpoint-b")
		check(not game.advanced_view().workspace.endpoints[1].business_ok,"wrong stop has business impact")
		await capture_control("MalwareRestore_"+"endpoint-b/processes/admin_tool.exe".validate_node_name(),"advanced-malware-wrong-isolation")
		await click("MalwareRestore_"+"endpoint-b/processes/admin_tool.exe".validate_node_name())
		check(game.advanced_view().workspace.endpoints[1].business_ok,"original process restored")
		await click("MalwareFile_endpoint-a"); await click("MalwareProcess_endpoint-a"); await click("MalwareStartup_endpoint-a"); await click("MalwareRescan"); await verify_case("advanced-malware")
	if await start_case("advanced-ddos"):
		var original: Dictionary=game.state.advanced.duplicate(true)
		await click("TrafficRoute_r03")
		check(str(desk.advanced_ui["advanced-ddos"].waf_route)=="/search","traffic card selects its real route")
		check(game.state.advanced==original,"route selection does not apply traffic controls")
		await click("DdosMeasure"); check(not game.advanced_view().workspace.measurements.checkout,"overload affects actual checkout")
		await option("Spec_waf_route","/search"); await option("Spec_waf_mode","limit")
		node("DdosLimit").value=20
		await click("DdosApply"); await click("DdosMeasure")
		check(game.advanced_view().workspace.measurements.checkout,"rate control restores checkout")
		await capture_control("DdosHistory","advanced-ddos-traffic-history")
		await click("DdosInspectSession"); await click("DdosRevoke"); await click("DdosInspectTask"); await click("DdosStopTask")
		for id in ["ingress-01","auth-74","task-12"]: await tree_select("SpecEvidence",id); await click("SpecEvidencePin")
		await click("DdosMeasure"); await verify_case("advanced-ddos")
	if await start_case("advanced-api"):
		check(game.advanced_view().workspace.policy.is_empty(),"API internal policy not initial discovery shortcut")
		await api_request("alice","list",""); await api_request("beth","list","")
		await api_request("alice","read","INV-S01",true)
		await api_request("alice","approve","INV-N01",true)
		await api_request("noah","export","INV-N01")
		await api_request("alice","download","job-noah-INV-N01",true)
		await capture_control("ApiPin","advanced-api-request-evidence")
		for policy in ["tenant","approval","job_owner"]: await click("ApiPolicy_"+policy)
		await click("ApiRetest"); await click("ApiBusiness"); await verify_case("advanced-api")
	if await start_case("advanced-supplychain"):
		var original: Dictionary=game.state.advanced.duplicate(true)
		await click("PipelineStep_2")
		check(node("SupplyArtifacts").is_visible_in_tree(),"pipeline opens actual artifacts")
		check(game.state.advanced==original,"pipeline navigation does not build or deploy")
		await click("SupplyInspect"); await click("SupplyRevoke"); await click("SupplyRotate"); await click("SupplyRemoveHook")
		await tree_select("SupplyArtifacts","pkg-42"); await click("SupplyQuarantine")
		await click("SupplyBuild")
		var id: String=str(game.advanced_view().workspace.last_build)
		await tree_select("SupplyArtifacts",id)
		await capture_control("SupplyArtifacts","advanced-supplychain-artifact-bytes")
		await click("SupplyDeploy_orders-a"); await click("SupplyDeploy_orders-b"); await click("SupplyMeasure")
		for evidence in ["build-42","token-42","egress-42"]: await tree_select("SpecEvidence",evidence); await click("SpecEvidencePin")
		await verify_case("advanced-supplychain")
