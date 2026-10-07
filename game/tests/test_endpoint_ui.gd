extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args(); narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func(): push_error("endpoint UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ",label)

func frames(count := 4) -> void:
	for i in count: await process_frame

func control(id: String):
	return pc.widgets.browser.page.find_child(id,true,false)

func press(id: String) -> void:
	var node = control(id)
	check(node is BaseButton and not node.disabled,"enabled control "+id)
	if node is BaseButton and not node.disabled: node.pressed.emit()

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(8); await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/experience/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func measure() -> void:
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	game.verify()

func run() -> void:
	ui=load("res://scripts/interface.gd").new(); root.add_child(ui); await process_frame
	game=ui._game(); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"QA storage isolation")
	ui._new_game(); game.choose_strategy("response"); check(game.start_free_career(),"career started")
	var offer_id := ""
	for offer in game.state.offers:
		if str(offer.case_id)=="service-4-case-0": offer_id=str(offer.id)
	check(not offer_id.is_empty() and game.choose_contract(offer_id),"real EDR offer accepted")
	game.inspect_mission(); game.vm_run("ssh client")
	check(int(game._vm().state.get("edr_model_version",1))==2,"new EDR model")
	var mail: Dictionary = preload("res://scripts/os_business_apps.gd")._mail_for(game.mission(),game)
	check(mail.get("subject","")==game.mission().title and mail.get("body","")==game.mission().brief,"mail presents the incident without revealing response targets")
	check(game.capture_baseline(),"baseline recorded before incident response")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1280,720)
	root.content_scale_size=root.size
	await frames(); ui.open_panel("terminal"); pc=ui.desktop; pc._show_app("browser"); await frames()
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	pc._browse_url(pc.EDR_URL,true); await frames()
	check(control("EdrDevice_pc_a")!=null and control("EdrDevice_pc_b")!=null,"device inventory renders real VM endpoints")
	check(control("EdrInvestigationMap")!=null,"two endpoints share a comparison map")
	check(control("EdrBusinessProbe_pc_a")!=null and control("EdrBusinessOpen_pc_b")!=null,"new contract maps reservation access and the real cashier workspace to endpoints")
	var before_map_vm: String=JSON.stringify(game._vm().export_state(),"",true)
	var before_map_work: String=JSON.stringify(game.state.work,"",true)
	var before_map_clock: int=int(game.state.clock_minutes)
	pc._render_endpoint();await frames()
	check(JSON.stringify(game._vm().export_state(),"",true)==before_map_vm and JSON.stringify(game.state.work,"",true)==before_map_work and int(game.state.clock_minutes)==before_map_clock,"comparison rendering does not measure, charge or change endpoints")
	for id in ["EdrDevice_pc_a","EdrDevice_pc_b","EdrMapEvent_pc_a_1","EdrMapEvent_pc_b_1"]:
		var object=control(id)
		check(object is BaseButton and object.get_global_rect().position.x>=0 and object.get_global_rect().end.x<=root.size.x+2,"comparison object fits "+id)
	await capture("edr-devices")
	press("EdrBusinessOpen_pc_b"); await frames()
	check(control("HotelFrontdesk")!=null and control("HotelRoom_204")!=null and control("HotelFolioTitle").text.contains("F-204"),"business object opens the guest's actual pending folio")
	check(JSON.stringify(game._vm().export_state(),"",true)==before_map_vm and JSON.stringify(game.state.work,"",true)==before_map_work and int(game.state.clock_minutes)==before_map_clock,"front desk viewing does not measure, charge or submit a folio")
	press("HotelOpenEndpoint"); await frames(); press("EdrView_devices"); await frames()
	press("EdrMapEvent_pc_a_1"); await frames()
	check(control("EdrField_process").text==str(game._vm().edr_snapshot().devices[0].events[1].process),"grouped graph opens original event index")
	check(control("EdrField_publisher")!=null and control("EdrField_change_ref")!=null,"event evidence details are visible")
	press("EdrBackMap"); await frames()
	check(control("EdrInvestigationMap")!=null,"record detail returns directly to comparison")
	var map_search=control("EdrInventorySearch")
	map_search.text="file_read";map_search.text_changed.emit(map_search.text);await frames()
	check(control("EdrMapEvent_pc_a_0")==null and control("EdrMapEvent_pc_a_1")!=null,"map search retains source event indices")
	press("EdrMapEvent_pc_a_1");await frames()
	check(control("EdrField_process").text==str(game._vm().edr_snapshot().devices[0].events[1].process),"filtered map opens the matching source record")
	press("EdrBackMap");await frames()
	map_search=control("EdrInventorySearch");map_search.text="";map_search.text_changed.emit("");await frames()
	press("EdrMapEvent_pc_a_1");await frames()
	var type_filter = control("EdrTypeFilter")
	type_filter.select(2); type_filter.item_selected.emit(2)
	check(control("EdrEvent_0")==null and control("EdrEvent_1")!=null,"file filter selects real file events")
	type_filter.select(0); type_filter.item_selected.emit(0)
	press("EdrEvent_1")
	check(control("EdrField_process").text==str(game._vm().edr_snapshot().devices[0].events[1].process),"event selection displays the selected source record")
	var search = control("EdrSearch")
	check(search is LineEdit,"timeline search exists")
	if search is LineEdit:
		search.grab_focus(); search.text="203"; search.text_changed.emit(search.text); await frames()
		check(is_instance_valid(search) and search.has_focus() and search.text=="203","search retains input and keyboard focus")
		game.changed.emit(); await frames()
		check(is_instance_valid(search) and search.has_focus(),"clock-only refresh preserves search focus")
		search.text=""; search.text_changed.emit("")
	await capture("edr-timeline")
	if capture_enabled and narrow:
		var scroll: Node = pc.widgets.browser.page.get_parent()
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		if scroll is ScrollContainer:
			scroll.ensure_control_visible(control("EdrField_change_ref"))
			await capture("edr-details")
			scroll.scroll_vertical = 0
	press("EdrCollect")
	var original: String = game.vm_read("/var/log/evidence.log")
	check(game.vm_read("/evidence/original.log")==original,"collection preserves actual source bytes")
	var mutation: int=game._vm().state.mutation
	press("EdrCollect"); check(int(game._vm().state.mutation)==mutation,"duplicate collection is idempotent")
	press("EdrView_devices"); press("EdrDevice_pc_b"); press("EdrIsolate_pc_b")
	press("EdrView_devices");await frames()
	check(control("BusinessStripProfit")!=null and control("EdrImpactSummary")!=null,"response costs are visible in the investigation")
	press("EdrBusinessOpen_pc_b");await frames();press("HotelSubmitFolio");await frames()
	var hotel: Dictionary=game.hotel_snapshot()
	check(int(hotel.last_attempt.get("code",0))==403 and str(hotel.folios[0].status)=="pending" and int(hotel.folios[0].balance)==22800,"wrong isolation rejects the real folio and preserves its unpaid balance")
	check(control("HotelFolioStamp").text.contains("403") and control("HotelCurrentConnection").text.contains("隔離"),"failed receipt and current isolation are visible separately")
	await capture("hotel-blocked")
	press("HotelOpenEndpoint");await frames()
	press("EdrView_devices"); await frames()
	var business_object = control("EdrBusinessOpen_pc_b")
	check(business_object != null and business_object.find_children("*", "Label", true, false).any(func(item): return item.text.contains("前回 × HTTP 403")), "comparison map preserves the actual refused folio response")
	press("EdrDevice_pc_b"); await frames()
	measure(); check(not game.can_deliver(),"wrong endpoint cannot satisfy case")
	press("EdrRelease_pc_b");await frames()
	press("EdrOpenHotel");await frames()
	check(control("HotelFolioTitle").text.contains("F-204") and control("HotelFolioStamp").text.contains("403") and not bool(game.hotel_snapshot().isolated),"release retains the refused folio and its previous response for retry")
	press("HotelSubmitFolio");await frames()
	hotel=game.hotel_snapshot()
	var hotel_receipt: String=str(hotel.folios[0].receipt.get("number",""))
	check(str(hotel.folios[0].status)=="received" and int(hotel.folios[0].balance)==0 and not hotel_receipt.is_empty(),"retry of the same folio records acceptance and clears the guest balance")
	check(control("HotelFolioStamp").text.contains(hotel_receipt) and control("HotelFolioBalance").text.contains("¥0"),"saved receipt number and zero balance appear on the folio")
	await capture("hotel-received")
	press("HotelOpenEndpoint");await frames()
	press("EdrView_devices"); press("EdrDevice_pc_a"); press("EdrIsolate_pc_a")
	press("EdrView_devices");await frames()
	check(control("EdrMapEvent_pc_a_0")!=null and control("EdrMapEvent_pc_a_1")!=null,"isolation retains historical record links")
	press("EdrDevice_pc_a")
	check(game.vm_run("curl https://edr.client.test/pc-a/outbound").contains("403"),"selected endpoint outbound is blocked")
	check(bool(game._vm().edr_snapshot().devices[0].management_connected),"management channel survives isolation")
	check(not game.can_deliver(),"old measurements do not authorize delivery after response")
	measure(); check(game.can_deliver(),"response plus fresh observed probes permits delivery")
	press("EdrView_actions"); await capture("edr-actions")
	var path: String=game.save_path; var before: String=JSON.stringify(game.state,"",true); var vm_before: String=JSON.stringify(game._vm().export_state(),"",true)
	game.save_path="user://missing-edr-"+str(OS.get_process_id())+"/save.json"
	var failed = JSON.parse_string(game.vm_run("edr release pc_a"))
	check(failed is Dictionary and int(failed.get("code",0))==507,"save failure is surfaced")
	check(JSON.stringify(game.state,"",true)==before and JSON.stringify(game._vm().export_state(),"",true)==vm_before,"failed save restores all VM and business state")
	game.save_path=path
	check(pc._save_session() and game.save_game() and game.load_game(),"incident and console session persist")
	pc._load_session(); pc._browse_url(pc.EDR_URL,false)
	check(str(pc.edr_ui.get("view",""))=="actions","selected view survives reload")
	check(bool(game._vm().edr_snapshot().evidence.valid),"stored evidence remains valid")
	check(str(game.hotel_snapshot().folios[0].receipt.get("number",""))==hotel_receipt and int(game.hotel_snapshot().folios[0].balance)==0,"the same guest receipt and settled balance survive save and resume")
	check(game.vm_write("/var/log/evidence.log","tampered\n"),"tamper fixture applied")
	failed=JSON.parse_string(game.vm_run("edr collect"))
	check(failed is Dictionary and not bool(failed.get("ok",true)),"tampered source collection refused")
	check(game.vm_read("/evidence/original.log")==original,"failed collection preserves original good evidence copy")
	measure(); check(not game.can_deliver(),"tampered source cannot satisfy delivery")
	check(game.vm_write("/var/log/evidence.log",original),"restore original source for remaining QA")
	measure(); check(game.can_deliver() and game.deliver(),"EDR case delivers through normal transaction")
	print("ENDPOINT_UI failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
