extends SceneTree

var ui
var game
var pc
var failures: Array[String]=[]
var narrow: bool="--narrow" in OS.get_cmdline_user_args()
var capture_enabled: bool="--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(80).timeout.connect(func():push_error("software fidelity timeout");quit(2))
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	if not ok: failures.append(message);push_error(message)

func frames(count:=5) -> void:
	for _i in count:await process_frame

func show_app(id: String) -> void:
	pc._show_app(id)
	if not pc.windows[id].maximized:pc.windows[id].toggle_maximize()
	await frames()

func capture(id: String) -> void:
	if not capture_enabled:return
	await frames();await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/software-fidelity/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(id+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+id)

func run() -> void:
	ui=preload("res://scripts/interface.gd").new();root.add_child(ui);await frames(2)
	game=ui._game()
	check(game.save_path.begins_with("user://qa-"),"isolated QA storage")
	if not failures.is_empty():quit(1);return
	game.set_process(false);ui._new_game();game.choose_strategy("operations");game.accept_mission()
	game.set_settings({"resolution":"960x600" if narrow else "1280x720","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1280,720)
	ui.open_panel("terminal");await frames();pc=ui.desktop
	pc._run_command("ssh client");await frames()
	await show_app("mail")
	var mail_brand: Label=pc.windows.mail.find_child("MailBrand",true,false) as Label
	check(mail_brand is Label and mail_brand.text=="Outwatch","mail product name is Outwatch")
	check(pc.windows.mail.title_text=="Outwatch","mail window title is Outwatch")
	var list: VBoxContainer=pc.widgets.mail.list
	var message: BaseButton
	for node in list.get_children():
		if node is BaseButton:message=node;break
	check(message!=null,"actual inbox row")
	if message!=null and narrow:
		check(message.custom_minimum_size.y<=82.0*float(game.settings.get("text_scale",1.0)),"narrow inbox row stays compact")
		check(message.find_children("*","Label",true,false).size()==3,"narrow inbox row omits the preview line")
	await capture("outwatch-list")
	if message!=null:message.pressed.emit()
	await frames()
	check(pc.widgets.mail.paper.visible,"selected message reading pane visible")
	check(pc.widgets.mail.wide != narrow,"responsive message layout")
	if not narrow:
		check(pc.widgets.mail.list_panel.visible and pc.widgets.mail.nav_frame.visible,"three Outwatch panes at desktop width")
	var selected_subject: String=pc.widgets.mail.selected_subject
	pc.widgets.mail.single_pane=true;pc.widgets.mail.folders_hidden=true
	check(pc._save_session(),"mail session saved to isolated disk")
	check(game.load_game(),"saved mail session loads from disk")
	pc._reload_contract_session();await frames()
	check(pc.widgets.mail.reading and pc.widgets.mail.selected_subject==selected_subject,"selected message survives disk reload")
	check(pc.widgets.mail.single_pane and pc.widgets.mail.folders_hidden,"mail pane choices survive disk reload")
	pc.widgets.mail.single_pane=false;pc.widgets.mail.folders_hidden=false;pc.BUSINESS.refresh_mail(pc);await frames()
	var pointer: Vector2i=DisplayServer.mouse_get_position()
	pc.widgets.mail.single_pane=true;pc.BUSINESS.refresh_mail(pc);await frames()
	check(not pc.widgets.mail.list_panel.visible and pc.widgets.mail.paper.visible,"single pane retains selected message")
	pc.widgets.mail.single_pane=false;pc.BUSINESS.refresh_mail(pc);await frames()
	check(DisplayServer.mouse_get_position()==pointer,"mail selection/layout preserves OS pointer")
	await capture("outwatch-message")
	await show_app("files")
	pc.FILES.navigate(pc,"/etc/samba",true);await frames();await capture("explorer")
	pc._open_config();await show_app("editor")
	check(pc.editor.text.contains("[global]"),"editor uses actual Samba configuration")
	var draft: String=pc.editor.text+"\n# unsaved fidelity check\n";pc.editor.text=draft;pc.editor.text_changed.emit()
	check(pc.drafts.get(pc.editor_path,"")==draft and pc._read(pc.editor_path)!=draft,"edit creates an unsaved draft without changing file")
	await capture("code-editor")
	await show_app("terminal");pc._run_command("ls /etc/samba");await frames();await capture("terminal")
	pc._show_desktop();pc.start_menu.show();pc.launcher_search.text="editor";pc.launcher_search.text_changed.emit("editor");await frames()
	check(pc.start_menu.find_child("StartApp_editor",true,false).visible,"launcher finds editor")
	check(not pc.start_menu.find_child("StartApp_mail",true,false).visible,"launcher filters unrelated apps")
	pc.launcher_search.text_submitted.emit("editor");await frames()
	check(pc.current_app=="editor" and not pc.start_menu.visible,"launcher Enter opens actual app")
	check(pc.editor.text==draft,"draft survives app launch and switching")
	pc._show_desktop();pc.launcher_search.text="";pc.launcher_search.text_changed.emit("");pc.start_menu.show();await frames();await capture("windows-start")
	check(pc.start_menu.get_global_rect().end.x<=pc.get_global_rect().end.x+1,"launcher fits horizontal bounds")
	check(pc.start_menu.get_global_rect().position.y>=pc.get_global_rect().position.y-1,"launcher fits vertical bounds")
	check(pc.start_menu.get_global_rect().end.y<=pc.get_global_rect().end.y-52,"launcher remains above taskbar")
	print("SOFTWARE_FIDELITY failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
