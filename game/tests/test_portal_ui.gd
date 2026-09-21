extends SceneTree
const FILE := "/srv/share/partner-order.csv"
var ui
var game
var pc
var failures: Array[String]=[]
var capture_enabled:=false
var narrow:=false
func _init() -> void:
	capture_enabled="--capture" in OS.get_cmdline_user_args();narrow="--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func():push_error("portal test timeout");quit(2));call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);print("FAIL ",label)
func control(id: String):return pc.widgets.browser.page.find_child(id,true,false)
func press(id: String) -> void:
	var node=control(id);check(node is BaseButton and not node.disabled,"button "+id)
	if node is BaseButton and not node.disabled:node.pressed.emit()
func select(id: String,index: int) -> void:
	var node=control(id);check(node is OptionButton,"select "+id)
	if node is OptionButton:node.select(index);node.item_selected.emit(index)
func response() -> String:return str(pc.portal_ui.get("response",""))
func edit(text: String) -> void:
	var editor=control("PortalContent");check(editor is TextEdit,"recipient editor exists")
	if editor is TextEdit:editor.text=text;editor.text_changed.emit()
func frames(count:=4) -> void:
	for i in count:await process_frame
func capture(label: String) -> void:
	if not capture_enabled:return
	await frames(6)
	var scroll: ScrollContainer=pc.widgets.browser.page.get_parent()
	if narrow and label=="portal-sharing":scroll.ensure_control_visible(control("PortalApply_partner"));await frames(3)
	elif narrow and label=="portal-version-content":scroll.ensure_control_visible(control("PortalVersionCurrentGrid"));await frames(3)
	elif narrow:scroll.scroll_vertical=0;await frames(3)
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/versions/ui");DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture")
func share(role: String,permission: int,expiry: int) -> void:
	press("PortalNav_all")
	if control("PortalShare_"+role)==null:press("PortalShareFile_0")
	if control("PortalPermission_"+role)==null:press("PortalShare_"+role)
	select("PortalPermission_"+role,permission);select("PortalExpiry_"+role,expiry);press("PortalApply_"+role)
func legacy() -> void:
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../artifacts/simulator/v123/legacy-v122-portal.json")))
	check(not saved.has("portal_model_version"),"actual released v122 fixture")
	var machine=load("res://scripts/virtual_machine.gd").new();machine.setup(5,saved)
	check(int(machine.state.get("portal_model_version",1))==1 and not machine.state.fs.has(FILE),"legacy data not invented")
	check(machine.probes().all(func(p):return bool(p.passed) and bool(p.fresh)),"legacy measurements preserved")
	check(machine.run("curl -H 'Authorization: Bearer partner-mfa-session' https://portal.client.test/partner").begins_with("HTTP/1.1 200"),"legacy route remains usable")
func run() -> void:
	legacy()
	ui=load("res://scripts/interface.gd").new();root.add_child(ui);await frames(1);game=ui._game();game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"QA storage")
	ui._new_game();game.choose_strategy("advisory");game.state.peak_profit=200000;game.state.cash=100000;game.state.skills.advisory=3;game.start_free_career()
	var offer: Dictionary={}
	for day_index in 60:
		game.state.day=day_index+1;game._make_offers()
		for item in game.state.offers:
			if str(item.case_id)=="service-5-case-0" and bool(item.get("market_available",false)):offer=item;break
		if not offer.is_empty():break
	var accepted: bool=not offer.is_empty() and game.choose_contract(str(offer.get("id","")))
	check(accepted,"real sharing contract accepted")
	if not accepted:quit(1);return
	game.vm_run("ssh client")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false);root.size=Vector2i(960,600) if narrow else Vector2i(1280,720)
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.open_panel("terminal");pc=ui.desktop;pc._show_app("browser");await frames()
	if not pc.windows.browser.maximized:pc.windows.browser.toggle_maximize()
	pc._browse_url(pc.PORTAL_URL,true);await frames()
	check(control("PortalFile_0")!=null and not pc.widgets.browser.has("account"),"real files page, no test controls in browser chrome")
	await capture("portal-files")
	var selected_path: String=str(pc.portal_ui.selected_path)
	press("PortalView_grid")
	check(control("PortalFileGrid") is GridContainer and control("PortalFileGrid").columns>=2,"file grid uses real columns")
	check(str(pc.portal_ui.selected_path)==selected_path,"grid toggle preserves selected file")
	press("PortalFile_0")
	check(control("PortalAdminGrid")!=null and not control("PortalAdminContent").is_visible_in_tree(),"spreadsheet preview primary, source collapsed")
	await capture("portal-grid")
	press("PortalCloseSharing")
	press("PortalView_list")
	var parsed: Array=load("res://scripts/os_portal_console.gd")._csv_rows("a,b\n\"one, two\",\"three \"\"four\"\"\"\n\"multi\nline\",value\n")
	check(parsed.size()==3 and parsed[1][0]=="one, two" and parsed[1][1]=="three \"four\"" and parsed[2][0]=="multi\nline","preview handles quoted commas, escaped quotes and multiline cells")
	var original: String=game.vm_read(FILE);var policy: Dictionary=game._vm().state.applied.duplicate(true)
	share("partner",1,1);check(game._vm().state.applied.partner=="read","sharing changes actual grant")
	for key in ["mfa","tls","audit"]:check(game._vm().state.applied[key]==policy[key],"sharing preserves "+key)
	await capture("portal-sharing")
	press("PortalPreview");select("PortalIdentity",2);press("PortalRead")
	check(response().begins_with("HTTP/1.1 200") and str(pc.portal_ui.get("preview_content",""))==original,"recipient reads exact stored CSV")
	var updated: String="order_id,customer,total\nPO-1001,Quoted 'single' and \"double\",12900\nPO-1002,Minato Foods,7600\n"
	edit(updated);press("PortalWrite")
	check(response().begins_with("HTTP/1.1 403") and game.vm_read(FILE)==original,"readonly request cannot change file")
	select("PortalIdentity",1);check(control("PortalContent")==null and not pc.portal_ui.has("preview_content"),"different identity does not inherit draft")
	select("PortalIdentity",2);check(str(pc.portal_ui.get("preview_content",""))==updated and bool(pc.portal_ui.get("draft_dirty",false)),"identity switch restores its own draft")
	select("PortalAge",1);check(control("PortalContent")==null,"different link age starts without previous draft")
	select("PortalAge",0);check(str(pc.portal_ui.get("preview_content",""))==updated,"link age switch restores draft")
	press("PortalRole_staff");check(control("PortalContent")==null,"different role does not inherit draft")
	press("PortalRole_partner");check(str(pc.portal_ui.get("preview_content",""))==updated,"role switch restores draft")
	press("PortalRead");check(str(pc.portal_ui.get("preview_content",""))==updated and str(pc.portal_ui.get("loaded_content",""))==original,"refresh preserves unsaved draft alongside current file")
	press("PortalCancel");check(str(pc.portal_ui.get("preview_content",""))==original and not bool(pc.portal_ui.get("draft_dirty",false)) and pc.portal_ui.get("recipient_drafts",{}).is_empty(),"explicit cancel discards only pending draft")
	share("partner",2,1);press("PortalPreview");select("PortalIdentity",2);press("PortalRead");edit(updated);press("PortalWrite")
	check(response().begins_with("HTTP/1.1 200") and game.vm_read(FILE)==updated,"actual PUT persists literal quotes and linebreaks")
	press("PortalRead");check(str(pc.portal_ui.preview_content)==updated,"fresh GET sees saved bytes")
	await capture("portal-recipient")
	# Recover the previous contents through actual Nextcloud-style controls,
	# then restore the saved pre-rollback copy to continue this user's edit.
	press("PortalNav_all");press("PortalShareFile_0");press("PortalDetailVersions")
	var saved_version: Dictionary=game._vm().portal_snapshot().versions.back()
	press("PortalVersionPreview_"+str(saved_version.id));await frames()
	check(control("PortalVersionPreviewGrid")!=null and control("PortalVersionCurrentGrid")!=null,"saved and current version previews visible")
	await capture("portal-version-comparison")
	if narrow:await capture("portal-version-content")
	press("PortalVersionRestore_"+str(saved_version.id));await frames()
	check(game._vm().portal_storage_read(FILE)==original and control("PortalVersionFeedback").text==preload("res://scripts/ui_theme.gd").copy("portal_version_restored"),"actual version restored with feedback")
	var undo_version: Dictionary=game._vm().portal_snapshot().versions[0]
	press("PortalDetailActivity");await frames();await capture("portal-activity")
	press("PortalDetailVersions");press("PortalVersionPreview_"+str(undo_version.id));press("PortalVersionRestore_"+str(undo_version.id))
	check(game._vm().portal_storage_read(FILE)==updated,"restore retains the replaced file for undo")
	press("PortalDetailSharing");press("PortalPreview");select("PortalIdentity",2);press("PortalRead")
	var valid_path: String=game.save_path;var clock_before:=int(game.clock_minutes());var cash_before:=int(game.state.cash)
	game.save_path="user://missing-portal-"+str(OS.get_process_id())+"/save.json";edit(updated+"PENDING\n");press("PortalWrite");game.save_path=valid_path
	check(response().contains("507") and game.vm_read(FILE)==updated and int(game.clock_minutes())==clock_before and int(game.state.cash)==cash_before,"failed PUT save restores data and time")
	check(str(pc.portal_ui.preview_content).ends_with("PENDING\n"),"failed write preserves user draft")
	check(game.save_game() and game.load_game(),"real save reload");pc._load_session();pc._render_portal()
	check(game.vm_read(FILE)==updated and str(pc.portal_ui.preview_content).ends_with("PENDING\n"),"file and unsaved draft remain distinct after reload")
	press("PortalRead");edit("");press("PortalWrite");check(response().begins_with("HTTP/1.1 200") and game.vm_read(FILE).is_empty(),"empty content PUT is a real write")
	edit(updated);press("PortalWrite")
	select("PortalIdentity",1);press("PortalRead");check(response().contains("mfa_required"),"password-only session denied")
	select("PortalIdentity",2);select("PortalAge",1);press("PortalRead");check(response().contains("410 Gone"),"expired share rejected")
	await capture("portal-expired")
	pc._browser_back();check(response().begins_with("HTTP/1.1 200") and str(pc.portal_ui.age)=="current","browser back rechecks real prior link and restores age")
	press("PortalRole_public");select("PortalAge",0);select("PortalIdentity",0);press("PortalRead");check(response().begins_with("HTTP/1.1 403"),"revoked public link denied before MFA")
	share("public",1,2)
	var per_share: Array=game._vm().portal_snapshot().shares.duplicate(true)
	var pending: Dictionary=game._vm().state.applied.duplicate(true);pending.audit="off"
	game.vm_write(str(game.vm_info().config_path),game._vm().configuration_text(pending))
	share("partner",1,1)
	check(game.vm_read(str(game.vm_info().config_path)).contains("audit=off") and bool(game._vm().state.dirty),"share update preserves pending service edit")
	game.vm_run("systemctl restart portal")
	var public_share: Dictionary={}
	for item in game._vm().portal_snapshot().shares:
		if str(item.role)=="public":public_share=item
	check(str(public_share.get("expires",""))=="30d","unrelated restart preserves per-share expiry")
	var good_snapshot: Dictionary=game._vm().export_state();var before_share: Array=game._vm().portal_snapshot().shares.duplicate(true)
	game.save_path="user://missing-share-"+str(OS.get_process_id())+"/save.json";share("partner",2,0);game.save_path=valid_path
	check(game._vm().portal_snapshot().shares==before_share and game._vm().state.fs==good_snapshot.fs,"failed share save restores grants and pending config")
	for role in ["staff","partner","public"]:share(role,0,0)
	press("PortalFile_0");check(control("PortalAdminContent")!=null,"selected file details visible")
	press("PortalNav_shared");check(control("PortalFile_0")==null and control("PortalAdminContent")==null and str(pc.portal_ui.selected_path).is_empty(),"filtered file clears selection and details")
	press("PortalNav_all");press("PortalFile_0");game.vm_run("rm "+FILE);pc._render_portal()
	check(control("PortalFile_0")==null and control("PortalAdminContent")==null and str(pc.portal_ui.selected_path).is_empty(),"deleted file clears selection and details")
	check(game.vm_write(FILE,updated),"restore actual file through editor write")
	var desired: Dictionary=game._scenario().desired;game.vm_write(str(game.vm_info().config_path),game._vm().configuration_text(desired));game.vm_run("systemctl restart portal")
	for round_index in 3:
		for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.id))
	game.verify();check(game.can_deliver(),"real diagnostics and final verification pass")
	check(game.vm_run("portal share partner write 7d").contains('"ok":true'),"change permission after verification")
	check(not game.can_deliver(),"share change invalidates delivery evidence")
	game.vm_run("portal share partner read 7d")
	for round_index in 3:
		for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.id))
	game.verify();check(game.deliver(),"revalidated real contract delivers")
	print("PORTAL_UI failures=",failures.size());quit(0 if failures.is_empty() else 1)
