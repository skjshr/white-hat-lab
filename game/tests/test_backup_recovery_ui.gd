extends "res://tests/test_service_workflows.gd"
## Explicit company-eligibility fixture for the authored damaged-ledger case. Recovery actions are
## native pointer/keyboard input; no command edits or successful-probe injection.
var click_count := 0
var wheel_count := 0
var key_count := 0

func setup_case(case_id: String, url: String) -> void:
	ui._new_game();game.set_process(false);game.choose_strategy("operations");game.start_free_career()
	# Company eligibility only. Preserve the normal starting cash and use the
	# real acceptance charge; this is explicitly not earned career progression.
	game.state.peak_profit=35000;game.state.skills.operations=2;game._update_growth()
	game.state.market_day=int(game.state.day);game.state.market_leads=[case_id];game._make_offers()
	var offer_id:=""
	for offer in game.state.offers:
		if str(offer.get("case_id",""))==case_id and bool(offer.get("market_available",false)):offer_id=str(offer.id);break
	check(int(game.state.cash)==5000,"fixture retains normal cash before actual contract charge")
	check(not offer_id.is_empty() and game.choose_contract(offer_id),"actual authored contract accepted")
	check(game.state.targets.size()==1,"eligibility fixture creates exactly one authored target")
	check(game.vm_run("ssh client").contains("Authenticated"),"actual customer connected")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","text_scale":1.3 if narrow else 1.0,"window_mode":"windowed","volume":0},false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_panel("terminal");pc=ui.desktop;pc._show_app("browser");await frames()
	if not pc.windows.browser.maximized:pc.windows.browser.toggle_maximize()
	pc._browse_url(url,false);await frames()

func ctl(id: String) -> Control:
	return ui.find_child(id.validate_node_name(),true,false) as Control

func visible_rect(node: Control) -> Rect2:
	if node == null or not node.is_visible_in_tree(): return Rect2()
	var rect := node.get_global_rect()
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: rect=rect.intersection(ancestor.get_global_rect())
		ancestor=ancestor.get_parent()
	return rect.intersection(root.get_visible_rect())

func pointer(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var pixel := point*Vector2(root.size)/root.get_visible_rect().size
	var motion := InputEventMouseMotion.new();motion.position=pixel;motion.global_position=pixel;Input.parse_input_event(motion)
	await frames(1)
	for down in [true,false]:
		var event := InputEventMouseButton.new();event.position=pixel;event.global_position=pixel;event.button_index=button;event.pressed=down;Input.parse_input_event(event)
		await frames(2)

func reach(node: Control) -> bool:
	for _attempt in 32:
		if visible_rect(node).size.y>=minf(node.size.y,30):return true
		var ancestor: Node=node.get_parent()
		while ancestor!=null and not ancestor is ScrollContainer:ancestor=ancestor.get_parent()
		if not ancestor is ScrollContainer:return false
		var scroll: ScrollContainer=ancestor
		await pointer(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN if node.get_global_rect().get_center().y>scroll.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP)
		wheel_count+=1
	return false

func native_click(id: String) -> void:
	print("BACKUP_INPUT click begin ",id)
	var node:=ctl(id) as Button
	check(node!=null and not node.disabled and node.is_visible_in_tree(),"enabled native action "+id)
	if node==null or node.disabled or not node.is_visible_in_tree():return
	check(await reach(node),"reachable native action "+id)
	var previous:=Rect2();var stable:=0
	for _attempt in 24:
		await frames(1);var current:=visible_rect(node)
		stable=stable+1 if current==previous and current.size.y>=minf(node.size.y,30) else 0;previous=current
		if stable>=3:break
	check(stable>=3,"stable native action "+id)
	if stable<3:return
	var pressed:=[0];node.pressed.connect(func():pressed[0]+=1)
	await pointer(previous.get_center());click_count+=1;await frames(8)
	check(pressed[0]==1,"one actual press "+id)
	print("BACKUP_INPUT click end ",id)

func tap(code: Key, shift := false, ctrl := false, unicode_value := 0) -> void:
	print("BACKUP_INPUT key begin ",code," shift=",shift," focus=",focus_id())
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.shift_pressed=shift;event.ctrl_pressed=ctrl;event.unicode=unicode_value;event.pressed=down
		# A native OptionButton popup is its own Window; target the actual visible
		# popup rather than injecting its keys into the root window behind it.
		for option in pc.widgets.browser.page.find_children("*","OptionButton",true,false):
			var popup: PopupMenu=option.get_popup()
			if popup.visible:event.window_id=popup.get_window_id();break
		Input.parse_input_event(event);await frames(3)
	key_count+=1
	print("BACKUP_INPUT key end ",code," focus=",focus_id())

func native_destination(value: String) -> void:
	var input:=ctl("BackupDestination") as LineEdit
	check(input!=null and await reach(input),"actual destination input reachable")
	if input==null:return
	await pointer(visible_rect(input).get_center());click_count+=1
	await tap(KEY_A,false,true)
	for index in value.length():await tap(value.substr(index,1).to_upper().unicode_at(0),false,false,value.unicode_at(index))
	check(input.text==value,"actual keyboard enters restore destination "+value)

func focus_id() -> String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func key_activate(id: String) -> void:
	for _step in 35:
		if focus_id()==id:break
		await tap(KEY_TAB)
	check(focus_id()==id,"Tab reaches "+id)
	if focus_id()!=id:return
	var button:=ctl(id) as Button
	if button==null:return
	var pressed:=[0];button.pressed.connect(func():pressed[0]+=1)
	await tap(KEY_SPACE);await frames(8)
	check(pressed[0]==1,"Space activates once "+id)

func select_ledger() -> void:
	var tree:=ctl("BackupSnapshotTree") as Tree
	check(tree!=null and tree.is_visible_in_tree(),"file tree visible for explicit selection")
	if tree==null or not tree.is_visible_in_tree():return
	await reach(tree)
	var item:=tree_item(tree.get_root(),"/srv/data/ledger.txt")
	check(item!=null,"real ledger item exists")
	if item==null:return
	var rect:=tree.get_item_area_rect(item,0)
	# The compact Tree has its own scroll area. Scroll the real row into that
	# area before clicking; an offscreen row coordinate is not a valid input.
	for _attempt in 16:
		rect=tree.get_item_area_rect(item,0)
		var row:=Rect2(tree.global_position+rect.position,rect.size)
		if visible_rect(tree).encloses(row):break
		await pointer(visible_rect(tree).get_center(),MOUSE_BUTTON_WHEEL_DOWN);wheel_count+=1;await frames(2)
	var row:=Rect2(tree.global_position+rect.position,rect.size)
	check(visible_rect(tree).encloses(row),"ledger row wholly inside actual clipped Tree before pointer selection")
	if not visible_rect(tree).encloses(row):return
	await pointer(tree.global_position+rect.get_center());click_count+=1;await frames(10)
	check(str(pc.backup_ui.get("path",""))=="/srv/data/ledger.txt","pointer selects actual ledger")
	check(not ctl("BackupFileList").visible,"file selection exposes comparison without tree taking its height")
	check(focus_id()=="BackupFileToggle","file selection restores useful keyboard focus")

func shot(name: String) -> void:
	assert_render_scale(name)
	check(not ui.next_task_guide.enabled(),"operation route keeps next-task instructions hidden "+name)
	check(not bool(pc.backup_ui.get("content_details",false)) and not bool(pc.backup_ui.get("plan_details",false)) and not bool(pc.backup_ui.get("output_open",false)),"recovery never opens raw details "+name)
	var fair_comparison := name.begins_with("04-") or name.begins_with("06-")
	var before: Dictionary={"vm":game._vm().export_state(),"clock":game.clock_minutes(),"cash":game.state.cash,"probes":game.diagnostic_probes()}
	if fair_comparison:
		# Display-only A/B fixture: baseline captures have the guide visible.
		# No help/hint is opened; the actual toggle hides it again before work.
		ui.next_task_guide.set_enabled(true);await frames(10)
		print("BACKUP_DISPLAY_FIXTURE guide visible for comparison-only capture ",name)
		# A fully scaled guide takes more room than the hidden operation route.
		# Use real wheel input to frame the selected documents and all guards;
		# the offscreen chooser is tested separately for keyboard reachability.
		for _attempt in 4:
			var guard:=ctl("BackupRecoveryGuard")
			if visible_rect(guard).size.y>=guard.size.y-1:break
			await pointer(visible_rect(ctl("BackupCurrentDocument")).get_center(),MOUSE_BUTTON_WHEEL_DOWN);wheel_count+=1;await frames(3)
		assert_visible_documents()
	if capture_enabled:
		await frames(8);await RenderingServer.frame_post_draw
		var folder:=OS.get_environment("WHL_CAPTURE_DIR")
		if not folder.is_empty():
			DirAccess.make_dir_recursive_absolute(folder)
			check(root.get_texture().get_image().save_png(folder.path_join(name+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+name)
	if fair_comparison:
		await native_click("NextTaskToggle")
		check(not ui.next_task_guide.enabled(),"real guide toggle resumes operation without instructions")
		var after: Dictionary={"vm":game._vm().export_state(),"clock":game.clock_minutes(),"cash":game.state.cash,"probes":game.diagnostic_probes()}
		check(before==after,"comparison-only display setup preserves VM observations cash and clock")

func assert_render_scale(checkpoint: String) -> void:
	var scale := 1.3 if narrow else 1.0
	check(is_equal_approx(float(game.settings.text_scale),scale),"actual desktop settings scale "+checkpoint)
	check(is_equal_approx(float(ui.text_scale),scale),"actual interface theme scale "+checkpoint)
	for id in ["BackupSavedDocument","BackupCurrentDocument","BackupPlanBefore","BackupPlanAfter"]:
		var document:=ctl(id)
		if document==null or not document.is_visible_in_tree():continue
		for field in document.get_meta("document").fields:
			var value:=ctl(id+"Value_"+str(field.key)) as Label
			var expected:=maxi(11,int((12 if str(field.key)=="date" else 18)*scale))
			check(value.get_theme_font_size("font_size")==expected,"actual document font at declared scale "+str(value.name))
	print("BACKUP_SCALE ",checkpoint," desktop=",game.settings.text_scale," interface=",ui.text_scale)

func assert_visible_documents() -> void:
	for id in ["BackupSavedDocument","BackupCurrentDocument"]:
		var document:=ctl(id)
		var paper:=ctl(id+"Paper")
		var caption:=document.get_child(0) as Control
		check(visible_rect(caption).size.y>=caption.size.y-1,"selected version or destination context visible beside actual document "+id)
		for field in document.get_meta("document").fields:
			var value:=ctl(id+"Value_"+str(field.key)) as Label
			var measured:=value.get_theme_font("font").get_string_size(value.text,HORIZONTAL_ALIGNMENT_LEFT,-1,value.get_theme_font_size("font_size")).x
			check(value.size.x>=measured-1 and value.size.x>0,"actual value label has width for its entire rendered string "+str(value.name))
			check(visible_rect(value).size.x>=measured-1 and visible_rect(value).size.y>=value.size.y-1,"actual value fully visible in viewport "+str(value.name))
			check(paper.get_global_rect().encloses(value.get_global_rect()),"actual value stays inside document outline "+str(value.name))
	for id in ["BackupRecoveryGuard","BackupOriginalGuard","BackupUnrelatedGuard"]:
		var guard:=ctl(id)
		print("BACKUP_GUARD_RECT ",id," rect=",guard.get_global_rect()," visible=",visible_rect(guard))
		check(visible_rect(guard).size.y>=guard.size.y-1,"complete guard visible with comparison guide geometry "+id)

func readonly_display() -> void:
	var before: Dictionary=game._vm().export_state();var clock:=int(game.clock_minutes())
	for _i in 3:pc._render_backup();await frames()
	check(before==game._vm().export_state() and int(game.clock_minutes())==clock,"passive render does not read commands, measure, change bytes, or charge work")

func comparison_paths() -> void:
	var console=load("res://scripts/os_backup_console.gd")
	var record: Dictionary={"backup_restore_origins":{"/srv/data/ledger.txt":{"path":"/restore/ledger.txt","snapshot":"00000001"}},"last_restore":{"target":"/other","snapshot":"00000002","subfolder":""}}
	check(console._comparison_restore_path(record,"/srv/data/ledger.txt")=="/restore/ledger.txt","per-file destination survives later unrelated restore")
	check(console._comparison_restore_path({"last_restore":{"target":"/restore","subfolder":"/srv/data"}},"/srv/data/ledger.txt")=="/restore/ledger.txt","legacy subfolder restore comparison uses actual flattened path")
	check(console._comparison_restore_path({"last_restore":{"target":"/restore","subfolder":"/other"}},"/srv/data/ledger.txt")=="","unrelated subfolder does not claim this file restored")
	check(console._comparison_restore_path({"last_restore":{"target":"/restore"}},"/srv/data/ledger.txt")=="/restore/srv/data/ledger.txt","legacy full-tree destination retained")
	var acceptance: Dictionary={"available":true,"enforced":true,"required_files":["/srv/data/ledger.txt"]}
	var entries: Array=[{"path":"/srv/data/ledger.txt","status":"overwrite"},{"path":"/srv/data/orders.csv","status":"skipped"},{"path":"/srv/data/customers.csv","status":"unchanged"},{"path":"/srv/data/extra.txt","status":"new"},{"path":"/restore/srv/data/ledger.txt","status":"new"}]
	check(console._planned_live_changes(acceptance,entries)=={"original":1,"unrelated":1},"only actual planned live writes warn, not skipped unchanged or staged files")
	check(console._planned_live_changes({"available":true,"enforced":false,"legacy":true},entries)=={"original":0,"unrelated":0},"legacy unknown scope does not invent protection classification")

func run() -> void:
	comparison_paths()
	ui=load("res://scripts/interface.gd").new();root.add_child(ui);await frames()
	game=ui._game();game.set_process(false)
	if not game.save_path.begins_with("user://qa-"):quit(2);return
	await setup_case("service-1-case-3","http://backup01.client.test:9898")
	if DisplayServer.get_name()!="headless":root.grab_focus();await frames(10)
	print("BACKUP_RECOVERY_FIXTURE peak_profit=35000 operations=2 market_leads=service-1-case-3; starting_cash=5000 and profit unchanged before real acceptance; one actual target; no earned-progression claim; window_focus=",root.has_focus())
	await native_click("NextTaskToggle")
	check(not ui.next_task_guide.enabled(),"actual guide toggle hides instructions before repair")
	pc._browse_url(pc.BACKUP_URL,true);await frames(10)
	await native_click("BackupSnapshot_00000002");await select_ledger()
	if ctl("BackupPreview")==null:
		print("BACKUP_RECOVERY_UI stopped before ledger comparison; failures=",failures);quit(1);return
	check(str(ctl("BackupPreview").text).contains("CORRUPTED"),"latest snapshot really contains corrupt data")
	check(str(ctl("BackupSavedDocument").get_meta("document").kind)=="damaged" and ctl("BackupSavedDocumentDamage").is_visible_in_tree(),"actual corrupt bytes produce damaged document and readable short warning")
	await shot("01-latest-is-damaged")
	await key_activate("BackupRestoreToPath")
	check(ctl("BackupDestination")!=null,"keyboard opens actual restore form")
	await native_click("BackupPreviewChanges")
	check(focus_id()=="BackupPreviewChanges","preview rerender retains button focus")
	check(str(ctl("BackupPlanBefore").get_meta("document").kind)=="missing" and str(ctl("BackupPlanAfter").get_meta("document").kind)=="damaged","real dry-run visual shows missing destination becoming damaged content")
	check(str(ctl("BackupPlanRoute").text).contains("/restore/srv/data/ledger.txt"),"dry-run visual identifies actual planned write path")
	await shot("02-selected-restore-plan")
	await key_activate("BackupExecuteRestore")
	check(game.vm_read("/restore/srv/data/ledger.txt").contains("CORRUPTED"),"restoring latest really leaves damaged destination")
	await native_click("BackupCloseRestore");await native_click("BackupCompareRestored")
	check(not bool(game._vm().backup_acceptance_view().accepted) and str(ctl("BackupAcceptanceStatus").text).contains("不一致"),"successful wrong-version command visibly fails customer acceptance")
	check(str(ctl("BackupRecoveryGuard").get_meta("state"))=="mismatch" and str(ctl("BackupOriginalGuard").get_meta("state"))=="preserved","wrong restored bytes and preserved damaged original have distinct graphical states")
	check(await reach(ctl("BackupAcceptanceGuards")),"wrong-version customer rejection reachable beside comparison")
	await shot("03-command-succeeded-but-case-not-recovered")
	# Keyboard changes the selected version through the real native chooser.
	for _step in 35:
		if focus_id()=="BackupSnapshotChoice":break
		await tap(KEY_TAB,true)
	check(focus_id()=="BackupSnapshotChoice","Tab reaches snapshot chooser")
	await tap(KEY_SPACE);await tap(KEY_UP);await tap(KEY_ENTER);await frames(10)
	check(str(pc.backup_ui.get("snapshot",""))=="00000001","native chooser selects earlier version")
	check(str(pc.backup_ui.get("path",""))=="/srv/data/ledger.txt","same file remains selected across versions")
	check(str(ctl("BackupPreview").text).contains("closing=62800"),"selected older bytes are normal")
	check(str(ctl("BackupSavedDocument").get_meta("document").kind)=="ledger" and str(ctl("BackupSavedDocumentValue_closing").text)=="62,800","selected actual ledger bytes render real closing figure")
	await native_click("BackupCompareRestored");await shot("04-older-version-vs-damaged-destination")
	check(str(ctl("BackupComparisonStatus").text).contains("異なり"),"older selected bytes differ from actual damaged destination")
	check(str(ctl("BackupCurrentDocument").get_meta("document").kind)=="damaged" and str(ctl("BackupSavedDocument_opening").get_child(0).text).contains("Δ"),"actual before/after difference changes document shape and marks differing values")
	await native_click("BackupRestoreToPath");await native_click("BackupPreviewChanges")
	var scope_before: Dictionary={"vm":game._vm().export_state(),"clock":game.clock_minutes()}
	await native_destination("/");await native_click("BackupPreviewChanges")
	check(ctl("BackupPlannedLiveChanges")!=null and str(ctl("BackupPlannedLiveChanges").text).contains("原本を変更する予定 1"),"actual root-target dry-run warns about original write")
	check(str(ctl("BackupOriginalGuard").get_meta("state"))=="preserved" and str(ctl("BackupOriginalGuardLabel").text).contains("現在"),"current original preservation remains distinct from planned overwrite")
	await shot("04b-original-write-preview-not-executed")
	await native_destination("/restore");await native_click("BackupPreviewChanges")
	check(ctl("BackupPlannedLiveChanges")==null,"returning to staged target removes planned live-write warning")
	check(scope_before=={"vm":game._vm().export_state(),"clock":game.clock_minutes()},"risky preview and destination correction do not write or charge time")
	var original: String=game.vm_read("/srv/data/ledger.txt")
	var saved_path: String=game.save_path;var previous: Dictionary=game._vm().export_state();var clock:=int(game.clock_minutes())
	game.save_path="user://missing-backup-recovery/failed.json"
	await native_click("BackupExecuteRestore");game.save_path=saved_path
	check(str(pc.backup_ui.get("restore_result",""))=="failed","real save failure is visible")
	check(game._vm().export_state()==previous and int(game.clock_minutes())==clock,"failed restore rolls back VM and time")
	await shot("05-save-failure-retains-plan")
	await native_click("BackupPreviewChanges");await key_activate("BackupExecuteRestore")
	await native_click("BackupCloseRestore");await native_click("BackupCompareRestored")
	check(game.vm_read("/srv/data/ledger.txt")==original,"original preserved through real restoration")
	check(game.vm_read("/restore/srv/data/ledger.txt").contains("closing=62800"),"correct selected version restored")
	check(str(ctl("BackupComparisonStatus").text).contains("内容が一致"),"actual restored bytes compare equal")
	check(bool(game._vm().backup_acceptance_view().accepted) and str(ctl("BackupAcceptanceStatus").text).contains("原本: 保全"),"correct bytes and preserved originals visibly satisfy customer acceptance")
	check(str(ctl("BackupCurrentDocumentValue_closing").text)=="62,800" and str(ctl("BackupRecoveryGuard").get_meta("state"))=="matched","restored actual closing figure and customer acceptance update visually")
	check(str(ctl("BackupOriginalGuard").get_meta("state"))=="preserved" and str(ctl("BackupUnrelatedGuard").get_meta("state"))=="preserved","original and unrelated preservation have separate actual guards")
	check(await reach(ctl("BackupAcceptanceGuards")),"preservation and customer acceptance reachable beside restored contents")
	# The comparison repeats the selected repository/snapshot, so the version
	# chooser can scroll above it without losing which saved bytes are shown.
	check(str(ctl("BackupRestoreProvenance").text).contains("offsite / 00000001"),"visible comparison identifies actual selected repository and snapshot")
	for id in ["BackupSavedDocument","BackupRestoreProvenance","BackupCurrentDocument","BackupComparisonStatus","BackupAcceptanceGuards"]:
		var node:=ctl(id);var rect:=node.get_global_rect()
		check(rect.position.x>=0 and rect.end.x<=root.get_visible_rect().end.x+1,"horizontal viewport fit "+id)
		check(visible_rect(node).size.y>=minf(rect.size.y,70),"comparison context visible "+id)
	await shot("06-correct-restoration-original-preserved")
	check(await reach(ctl("BackupSnapshotChoice")),"version chooser remains reachable by real wheel after comparison")
	check(str(pc.backup_ui.get("snapshot",""))=="00000001" and str(pc.backup_ui.get("path",""))=="/srv/data/ledger.txt","scrolling to version chooser preserves selected tuple")
	await shot("06a-selected-snapshot-and-file-context")
	await readonly_display()
	check(game.save_game() and game.load_game(),"real save reload")
	pc._load_session();pc._render_backup();await frames()
	check(str(pc.backup_ui.get("snapshot",""))=="00000001" and str(pc.backup_ui.get("path",""))=="/srv/data/ledger.txt" and str(pc.backup_ui.get("compare_target",""))=="restored","selected version file and comparison target survive reload")
	# Continue via the existing desktop/diagnostic/receipt controls. No success
	# flags or probe observations are written by this test.
	await native_click("TaskbarApp_verify")
	check(pc.current_app=="verify","native taskbar opens existing diagnostics")
	for probe in game.diagnostic_probes():
		await native_click("DiagnosticProbe_"+str(probe.id));await native_click("DiagnosticRun")
	check(game.diagnostic_probes().all(func(item):return bool(item.get("fresh",false)) and bool(item.get("passed",false))),"native real measurements satisfy every customer condition")
	await shot("07-real-customer-measurements")
	await native_click("DiagnosticValidate")
	check(game.can_deliver(),"existing verification permits real delivery")
	await native_click("GuideDeliver")
	check(game.current_done() and not str(game.completion_receipt().get("invoice_id","")).is_empty(),"actual delivery creates customer receipt and invoice")
	await native_click("ReceiptEvaluationTab")
	check(ctl("ReceiptCustomerOutcome")!=null,"existing customer acceptance result shown")
	await shot("08-accepted-customer-receipt")
	print("BACKUP_RECOVERY_UI assertions=",assertions," failures=",failures.size()," clicks=",click_count," wheels=",wheel_count," keys=",key_count)
	quit(0 if failures.is_empty() else 1)
