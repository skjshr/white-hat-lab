extends SceneTree
## Files -> editor -> saved bytes and SMB transfer recovery through real controls.

const LOCAL := "workstation:/home/operator/Documents/workflow.txt"
const COPY := "/home/operator/report.txt"
const REMOTE := "workflow-report.txt"
var game
var ui
var pc
var failures: Array[String] = []
var assertions := 0
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(85).timeout.connect(func():push_error("FILE_WORKFLOW_TIMEOUT");quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label);print("FAIL ",label)

func frames(count := 4) -> void:
	for _index in count: await process_frame

func control(id: String):
	return pc.find_child(id,true,false)

func press(id: String) -> void:
	var button = control(id)
	check(button is BaseButton and not button.disabled,"available action "+id)
	if button is BaseButton and not button.disabled: button.pressed.emit()
	await frames()

func enter(id: String, value: String) -> void:
	var field = control(id)
	check(field is LineEdit,"available field "+id)
	if field is LineEdit: field.text=value;field.text_changed.emit(value)

func selected() -> String:
	var item: TreeItem = pc.widgets.files.tree.get_selected()
	return str(item.get_metadata(0)) if item != null else ""

func select_file(path: String) -> void:
	var tree: Tree = pc.widgets.files.tree
	var item := tree.get_root().get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == path: item.select(0);tree.item_selected.emit();return
		item = item.get_next()
	check(false,"file selectable "+path)

func maximize(id: String) -> void:
	pc._show_app(id)
	if not pc.windows[id].maximized:pc.windows[id].toggle_maximize()
	await frames()

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless":return
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../../audit/all-services/files")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func bounds(node: Control, label: String) -> void:
	check(is_instance_valid(node),label+" exists")
	if not is_instance_valid(node):return
	var rect := node.get_global_rect()
	var window: Rect2 = pc.windows[pc.current_app].get_global_rect()
	check(rect.position.x >= window.position.x-1 and rect.end.x <= window.end.x+1,label+" fits horizontally")
	check(rect.position.y >= window.position.y-1 and rect.end.y <= window.end.y+1,label+" fits vertically")

func run() -> void:
	game=root.get_node("Game");game.set_process(false)
	if not str(game.save_path).begins_with("user://qa-"):quit(2);return
	ui=load("res://scripts/interface.gd").new();root.add_child(ui);await frames()
	check(ui._new_game(),"isolated new company")
	ui.guided_intro.skip();ui.next_task_guide.set_enabled(false)
	check(game.choose_strategy("advisory") and game.accept_mission(),"real Samba engagement accepted")
	check(str(game.vm_run("ssh client")).contains("Authenticated"),"real customer connection")
	game.set_settings({"resolution":"960x600" if narrow else "1600x900","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	ui._set_text_scale(1.3 if narrow else 1.0);root.size=Vector2i(960,600) if narrow else Vector2i(1600,900)
	ui.open_panel("terminal");await frames();pc=ui.desktop
	game.state.os_files[LOCAL.trim_prefix("workstation:")]="Draft for customer report\n"
	await maximize("files")
	pc.FILES.navigate(pc,"/home/operator/Documents",false)
	select_file(LOCAL)
	check(not pc.widgets.files.open.disabled,"selecting a document enables direct edit")
	pc.FILES.refresh(pc);check(selected()==LOCAL,"file selection survives refresh")
	enter("FilesSearch","missing-match");check(selected().is_empty(),"filter hides unmatched selected row")
	enter("FilesSearch","");check(selected()==LOCAL,"clearing filter restores selection")
	pc.FILES.navigate(pc,"/home/operator",false);pc.FILES._back(pc)
	check(selected()==LOCAL,"back restores folder selection")
	await capture("files-selected")
	await press("FilesOpenSelected");await maximize("editor")
	var draft := "Customer report\nReviewed file access and saved evidence.\n"
	pc.editor.text=draft;pc.editor.text_changed.emit();pc.editor.set_caret_line(1);pc.editor.set_caret_column(8)
	check(pc.drafts.get(LOCAL,"")==draft and pc._read(LOCAL)!=draft,"edit keeps unsaved draft separate from file")
	check(pc.widgets.editor.flow.visible and not pc.widgets.editor.save.disabled,"unsaved state and save action visible")
	pc._open_editor(LOCAL)
	check(pc.editor.get_caret_line()==1 and pc.editor.get_caret_column()==8,"reopening current file preserves caret")
	await capture("editor-unsaved")
	var save_path := str(game.save_path)
	game.save_path="user://missing-files-quality-"+str(OS.get_process_id())+"/save.json"
	await press("EditorSave")
	check(not str(pc.widgets.editor.get("save_error","")).is_empty() and pc.widgets.editor.flow.visible,"persistence error remains visible")
	check(pc.editor.text==draft and pc.drafts.get(LOCAL,"")==draft,"failed save retains draft")
	check(pc._read(LOCAL)=="Draft for customer report\n","failed persistence keeps previous saved bytes")
	check(not pc.widgets.editor.save.disabled,"failed save exposes retry")
	await capture("editor-save-failed")
	game.save_path=save_path
	await press("EditorSave")
	check(str(pc.widgets.editor.get("save_error","")).is_empty() and pc._read(LOCAL)==draft,"save retry succeeds with original bytes")
	check(pc._save_session() and ui.close_panel(false,false),"close saved desktop session")
	await frames();check(game.load_game(),"reload actual saved company")
	ui.open_panel("terminal");await frames();pc=ui.desktop;pc._open_editor(LOCAL);await maximize("editor")
	check(pc.editor.text==draft,"saved file reopens after reload")
	pc.FILES.navigate(pc,"/home/operator/Documents",false)
	check(selected()==LOCAL,"file selection survives saved desktop reload")
	bounds(pc.widgets.editor.editor,"editor text");bounds(pc.widgets.editor.save,"editor save")
	await capture("editor-saved-reopened")

	pc._open_samba_share("share");await maximize("files")
	await press("SmbFile_report_txt")
	check(str(pc.samba_ui.get("access_preview_path",""))==COPY,"SMB preview records downloaded path")
	await press("SmbRefresh")
	check(str(pc.samba_ui.get("access_selected",""))=="report.txt","SMB refresh keeps selected filename")
	await press("SmbEdit");await maximize("editor")
	var report := str(pc.editor.text)+"\nReviewed through file workflow.\n"
	pc.editor.text=report;pc.editor.text_changed.emit()
	await maximize("files");pc._render_smb();await frames()
	await press("SmbUploadEdited")
	check(control("SmbUpload").disabled and control("SmbSourceDraft").visible,"upload identifies unsaved source draft")
	await maximize("editor");await press("EditorSave")
	check(game.vm_read(COPY)==report,"downloaded copy saves exact edited bytes")
	await maximize("files");pc._render_smb();await frames()
	check(control("SmbStale") != null,"preserved SMB preview is identified as previously retrieved content")
	enter("SmbRemoteName",REMOTE)
	await press("SmbUpload")
	check(str(pc.samba_ui.get("access_output","")).contains("ACCESS_DENIED"),"read-only staff transfer returns real denial")
	check(control("SmbRecoveryHint") != null and str(control("SmbSource").text)==COPY and str(control("SmbRemoteName").text)==REMOTE,"transfer failure retains inputs and recovery message")
	check(str(pc.samba_ui.get("access_selected",""))=="report.txt","transfer failure retains selected preview")
	await capture("smb-transfer-failed")
	# Change only the existing share policy through its production save API, then
	# retry the same visible transfer. No seeded applied-state mutation is used.
	check(pc._samba_save("share",{"write list":"staff","read list":""}),"stage actual staff write permission")
	pc._samba_command("systemctl restart "+str(game.vm_info().service))
	pc._render_smb();await frames()
	await press("SmbUpload")
	check(str(pc.samba_ui.get("access_output","")).contains("OK") and game.vm_read("/srv/share/"+REMOTE)==report,"transfer retry writes exact edited bytes")
	await press("SmbFile_"+REMOTE.validate_node_name())
	check(str(pc.samba_ui.get("access_preview",""))==report,"uploaded file reads back through SMB")
	await frames()
	if narrow:pc.widgets.files.network_scroll.ensure_control_visible(control("SmbEdit"));await frames()
	bounds(control("SmbEdit"),"SMB editor action")
	await capture("smb-read-write")
	check(pc._save_session() and game.load_game(),"SMB selection persists through game reload")
	pc._load_session();pc._render_smb();await frames()
	check(str(pc.samba_ui.get("access_selected",""))==REMOTE,"SMB selected file restored")
	print("FILE_WORKFLOW_QUALITY ","PASS" if failures.is_empty() else "FAIL"," assertions=",assertions," failures=",failures)
	quit(0 if failures.is_empty() else 1)
