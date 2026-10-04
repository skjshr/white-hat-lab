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
	root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_panel("terminal");pc=ui.desktop;pc._show_app("browser");await frames()
	if not pc.windows.browser.maximized:pc.windows.browser.toggle_maximize()
	pc._browse_url(url,false);await frames()

func ctl(id: String) -> Control:
	return pc.find_child(id.validate_node_name(),true,false) as Control

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

func tap(code: Key, shift := false) -> void:
	print("BACKUP_INPUT key begin ",code," shift=",shift," focus=",focus_id())
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.shift_pressed=shift;event.pressed=down
		# A native OptionButton popup is its own Window; target the actual visible
		# popup rather than injecting its keys into the root window behind it.
		for option in pc.widgets.browser.page.find_children("*","OptionButton",true,false):
			var popup: PopupMenu=option.get_popup()
			if popup.visible:event.window_id=popup.get_window_id();break
		Input.parse_input_event(event);await frames(3)
	key_count+=1
	print("BACKUP_INPUT key end ",code," focus=",focus_id())

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
	if not capture_enabled:return
	await frames(8);await RenderingServer.frame_post_draw
	var folder:=OS.get_environment("WHL_CAPTURE_DIR")
	if folder.is_empty():return
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+name)

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

func run() -> void:
	comparison_paths()
	ui=load("res://scripts/interface.gd").new();root.add_child(ui);await frames()
	game=ui._game();game.set_process(false)
	if not game.save_path.begins_with("user://qa-"):quit(2);return
	await setup_case("service-1-case-3","http://backup01.client.test:9898")
	if DisplayServer.get_name()!="headless":root.grab_focus();await frames(10)
	print("BACKUP_RECOVERY_FIXTURE peak_profit=35000 operations=2 market_leads=service-1-case-3; starting_cash=5000 and profit unchanged before real acceptance; one actual target; no earned-progression claim; window_focus=",root.has_focus())
	pc._browse_url(pc.BACKUP_URL,true);await frames(10)
	await native_click("BackupSnapshot_00000002");await select_ledger()
	if ctl("BackupPreview")==null:
		print("BACKUP_RECOVERY_UI stopped before ledger comparison; failures=",failures);quit(1);return
	check(str(ctl("BackupPreview").text).contains("CORRUPTED"),"latest snapshot really contains corrupt data")
	await shot("01-latest-is-damaged")
	await key_activate("BackupRestoreToPath")
	check(ctl("BackupDestination")!=null,"keyboard opens actual restore form")
	await native_click("BackupPreviewChanges")
	check(focus_id()=="BackupPreviewChanges","preview rerender retains button focus")
	await shot("02-selected-restore-plan")
	await key_activate("BackupExecuteRestore")
	check(game.vm_read("/restore/srv/data/ledger.txt").contains("CORRUPTED"),"restoring latest really leaves damaged destination")
	await native_click("BackupCloseRestore");await native_click("BackupCompareRestored")
	check(not bool(game._vm().backup_acceptance_view().accepted) and str(ctl("BackupAcceptanceStatus").text).contains("不一致"),"successful wrong-version command visibly fails customer acceptance")
	check(await reach(ctl("BackupAcceptanceStatus")),"wrong-version customer rejection reachable beside comparison")
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
	await native_click("BackupCompareRestored");await shot("04-older-version-vs-damaged-destination")
	check(str(ctl("BackupComparisonStatus").text).contains("異なり"),"older selected bytes differ from actual damaged destination")
	await native_click("BackupRestoreToPath");await native_click("BackupPreviewChanges")
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
	check(await reach(ctl("BackupAcceptanceStatus")),"preservation and customer acceptance reachable beside restored contents")
	# The comparison repeats the selected repository/snapshot, so the version
	# chooser can scroll above it without losing which saved bytes are shown.
	check(str(ctl("BackupRestoreProvenance").text).contains("offsite / 00000001"),"visible comparison identifies actual selected repository and snapshot")
	for id in ["BackupSelectedPath","BackupRestoreProvenance","BackupPreview","BackupCurrentPreview","BackupComparisonStatus","BackupAcceptanceStatus"]:
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
