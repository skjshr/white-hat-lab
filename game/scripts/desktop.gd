extends Control
signal close_requested
signal return_requested
signal company_requested
signal customer_requested(client: String)
signal staffing_requested
signal contracts_requested
signal sales_requested
signal next_task_requested
signal equipment_requested
signal stock_preparation_requested
const WINDOW = preload("res://scripts/os_window.gd")
const UI = preload("res://scripts/ui_theme.gd")
const BUSINESS = preload("res://scripts/os_business_apps.gd")
const SHELL = preload("res://scripts/os_shell.gd")
const FILES = preload("res://scripts/os_file_manager.gd")
const EDITOR = preload("res://scripts/os_editor.gd")
const DIAGNOSTICS = preload("res://scripts/os_diagnostics.gd")
const ADVANCED_WORKSPACE = preload("res://scripts/os_advanced_operations.gd")
const BROWSER_PAGE = preload("res://scripts/os_browser_page.gd")
const BUSINESS_WORKSPACE = preload("res://scripts/os_business_workspace.gd")
const BILLING_WORKSPACE = preload("res://scripts/os_billing_workspace.gd")
const COMPLETED_CASE = preload("res://scripts/completed_case_workspace.gd")
const IDENTITY_CONSOLE = preload("res://scripts/os_identity_console.gd")
const IDENTITY_URL := "https://identity.client.test/admin/client/console/"
const EDR_URL := "https://edr.client.test/security/devices"
const HOTEL_URL := "https://frontdesk.client.test/"
const PORTAL_URL := "https://portal.client.test/apps/files/"
const FIREWALL_URL := "https://gateway.client.test/firewall_rules.php"
const BACKUP_URL := "http://backup.client.test:9898"
const SAMBA_URL := "https://files01.client.test:9090/file-sharing"
const PINNED_APPS := ["mail", "files", "terminal", "editor", "browser", "monitor", "verify"]
const INK := UI.INK
const MUTED := UI.MUTED
const TEAL := UI.PRIMARY
const ORANGE := UI.WARNING
var APPS := {"mail":["Outwatch","M","508bcc"],"terminal":["ターミナル",">_","354d60"],"files":["ファイル","F","d5a04a"],"editor":["エディタ","</>","4b968e"],"browser":["ブラウザ","W","5d91be"],"monitor":["サービス監視","S","315b91"],"verify":["診断ラボ","V","499276"],"team":["チーム","T","bd835c"],"manual":["リファレンス","?","728397"],"receipt":["納品・精算","¥","4b968e"]}
var game: Node
var workspace: Control
var taskbar: HBoxContainer
var start_menu: PanelContainer
var overview: PanelContainer
var side_rail: PanelContainer
var compact_nav: PanelContainer
var system_bar: PanelContainer
var system_target: Label
var system_clock: Label
var rail_buttons: Dictionary = {}
var tray: Label
var status: Label
var guidance: Button
var task_scroll: ScrollContainer
var app_dock: HBoxContainer
var taskbar_offset: Control
var launcher_search: LineEdit
var launcher_apps: GridContainer
var heading_font: Font
var windows: Dictionary = {}
var task_buttons: Dictionary = {}
var widgets: Dictionary = {}
var current_app := ""
var body: VBoxContainer
var output: RichTextLabel
var command: LineEdit
var prompt: Label
var editor: CodeEdit
var path_edit: LineEdit
var file_list: Tree
var url_edit: LineEdit
var file_directory := "/"
var editor_path := ""
var browser_url := ""
var browser_response := ""
var browser_identity := ""
var identity_ui: Dictionary = {}
var edr_ui: Dictionary = {}
var edr_render_signature := ""
var hotel_render_signature := ""
var portal_ui: Dictionary = {}
var portal_render_signature := ""
var firewall_ui: Dictionary = {}
var firewall_render_signature := ""
var backup_ui: Dictionary = {}
var backup_render_signature := ""
var samba_ui: Dictionary = {}
var smb_document_focus := false
var business_ui: Dictionary = {}
var billing_ui: Dictionary = {}
var advanced_ui: Dictionary = {}
var diagnostic_ui: Dictionary = {}
var monitor_ui: Dictionary = {}
var pentest_ui: Dictionary = {}
var billing_render_signature := ""
var samba_render_signature := ""
const BROWSER_IDENTITIES := [
	{"id":"","label":"未認証"},
	{"id":"partner-session","label":"取引先 / パスワード認証"},
	{"id":"partner-mfa-session","label":"取引先 / MFA認証済み"},
	{"id":"staff-session","label":"社員 / MFA認証済み"}
]
var terminal_log := ""
var history: Array = []
var history_index := 0
var drafts: Dictionary = {}
var mono: Font
var session_key := ""
var target_selector: OptionButton
var file_remote := true
var clipboard_path := ""
var browser_history: Array = []
var browser_history_index := -1
var file_history: Array = []
var file_forward_history: Array = []
var mail_folder := "inbox"
var mail_ui: Dictionary = {}
var _save_timer := 0.0
var ui_sound: AudioStreamPlayer
var brand_label: Label
var os_name_label: Label
var player_name_label: Label
var system_company: Label
var notice_serial := 0
var switching_target := false
var refreshing := false
var operation_trace: Array = []
var focus_order: Array[String] = []
var alt_tab_order: Array[String] = []
var running_apps: Array[String] = []
var desktop_shortcuts: Dictionary = {}
var selected_shortcut := ""
var desktop_hidden_windows: Array[String] = []
var desktop_hidden_active := ""
var configured_return_label := ""
var _app_keyboard_focus: Dictionary = {}

func browser_identities() -> Array:
	var identities: Array = BROWSER_IDENTITIES.duplicate(true)
	if game == null or not game.has_method("_vm"):
		return identities
	var machine = game._vm()
	if machine == null or not machine.has_method("has_linked_identity") or not bool(machine.has_linked_identity()):
		return identities
	identities = BROWSER_IDENTITIES.filter(func(item): return str(item.get("id", "")) != "staff-session")
	if not machine.has_method("linked_identity_sessions"):
		return identities
	var sessions: Array = machine.linked_identity_sessions()
	for session_value in sessions:
		if not session_value is Dictionary:
			continue
		var session: Dictionary = session_value
		var session_id := str(session.get("id", ""))
		if session_id.is_empty() or identities.any(func(item): return str(item.get("id", "")) == session_id):
			continue
		var user := str(session.get("user", "current"))
		var role_label := UI.copy("linked_identity_former", "Former") if user == "former" else UI.copy("linked_identity_current", "Current")
		var status_label := UI.copy("linked_identity_revoked", "Revoked") if bool(session.get("revoked", false)) else UI.copy("linked_identity_active", "Active")
		var session_label := UI.copy("linked_identity_session", "%s · %s · %s") % [role_label, session_id, status_label]
		identities.append({"id": session_id, "label": session_label, "session": session.duplicate(true)})
	return identities

func _company_name() -> String:
	return str(game.company_name()) if game != null and game.has_method("company_name") else "WHITE HAT LAB"

func _player_name() -> String:
	return str(game.player_name()) if game != null and game.has_method("player_name") else "あなた"

func _player_display_name() -> String:
	var value := _player_name()
	return value if value.length() <= 20 else value.left(19)+"…"

func _personalize(text: String) -> String:
	return str(game.personalize(text)) if game != null and game.has_method("personalize") else text

func setup(value: Node) -> void:
	game = value
	for id in ["mail","files","editor","terminal","browser"]: APPS[id][0] = UI.copy("fidelity_"+id+"_app")
	APPS["billing"] = [UI.copy("billing_app"), "¥", "714b67"]
	APPS["advanced"] = [UI.copy("adv_app"), "A", "0078d4"]
	ui_sound = AudioStreamPlayer.new(); ui_sound.stream = load("res://assets/audio/click_001.ogg"); ui_sound.volume_db = -14; add_child(ui_sound)
	_build()
	get_viewport().gui_focus_changed.connect(_keyboard_focus_changed)
	_load_session()
	var session: Dictionary = game.state.get("desktop_sessions",{}).get(session_key,{})
	_restore_session_windows(session)
	game.changed.connect(_state_changed)
	game.notified.connect(_notify)
	resized.connect(_desktop_resized)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.make_theme(float(game.settings.get("text_scale",1.0)))
	heading_font = UI.font(600)
	var cf := SystemFont.new(); cf.font_names = ["Cascadia Mono","Consolas","monospace"]; mono = cf
	var bg := TextureRect.new(); bg.texture = preload("res://assets/ui/aoba-wallpaper-v16.png"); bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	brand_label = _label(_company_name(),16,Color("d6e4ec")); brand_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT); brand_label.offset_left=-420; brand_label.offset_right=-26; brand_label.offset_top=-92; brand_label.offset_bottom=-64; brand_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; brand_label.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(brand_label)
	workspace = Control.new(); workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); workspace.offset_bottom=-52; add_child(workspace)
	var shortcuts := VBoxContainer.new(); shortcuts.name="DesktopShortcuts"; shortcuts.position=Vector2(16,14); shortcuts.add_theme_constant_override("separation",4); workspace.add_child(shortcuts)
	for id in ["files", "mail", "browser", "terminal"]:
		var shortcut := _app_tile(id,true); shortcuts.add_child(shortcut); desktop_shortcuts[id]=shortcut
	var dock := PanelContainer.new(); dock.name="Taskbar"; dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); dock.offset_top=-52; dock.add_theme_stylebox_override("panel",UI.style(Color("e9eef3"),Color("cbd3dc"),8,4,0)); add_child(dock)
	taskbar = _row(dock,4)
	taskbar_offset=Control.new(); taskbar.add_child(taskbar_offset)
	var start := _tool_button("grid",UI.copy("fidelity_all_apps"),func(): start_menu.visible=not start_menu.visible; overview.hide(); if start_menu.visible: launcher_search.grab_focus()); start.name="StartButton"; start.custom_minimum_size=Vector2(46,42); start.icon=UI.symbol("grid"); _task_style(start,false); taskbar.add_child(start)
	task_scroll=ScrollContainer.new(); task_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; task_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; task_scroll.size_flags_horizontal=Control.SIZE_FILL; taskbar.add_child(task_scroll)
	app_dock=HBoxContainer.new(); app_dock.add_theme_constant_override("separation",2); task_scroll.add_child(app_dock)
	for id in PINNED_APPS: _add_task_button(id)
	var task_tail:=Control.new(); task_tail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; taskbar.add_child(task_tail)
	status=_label("",12); status.hide(); status.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; status.custom_maximum_size.x=148; status.clip_text=true; status.autowrap_mode=TextServer.AUTOWRAP_OFF; status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; taskbar.add_child(status)
	var target_slot := Control.new(); target_slot.name="TargetSelectorSlot"; target_slot.custom_minimum_size=Vector2(116,42); target_slot.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; target_slot.clip_contents=true; taskbar.add_child(target_slot)
	target_selector = OptionButton.new(); target_selector.fit_to_longest_item=false; target_selector.custom_minimum_size=Vector2.ZERO; target_selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL; target_selector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); target_selector.clip_text=true; target_selector.item_selected.connect(_select_target); target_slot.add_child(target_selector)
	_refresh_target_selector()
	tray=_label("",11); tray.autowrap_mode=TextServer.AUTOWRAP_OFF; tray.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; tray.custom_minimum_size.x=78; taskbar.add_child(tray)
	var return_button := _button("",_return_to_source); return_button.name="DesktopReturn"; return_button.icon=UI.symbol("back"); return_button.tooltip_text=UI.copy("board_list","案件一覧"); return_button.visible=false; return_button.custom_minimum_size=Vector2(0,36); taskbar.add_child(return_button)
	var exit_button := _button(UI.copy("os_office","オフィスへ戻る"),_close); exit_button.name="ExitDesktop"; exit_button.icon=UI.symbol("external"); exit_button.tooltip_text=UI.copy("os_office","オフィスへ戻る"); exit_button.custom_minimum_size=Vector2(0,36); _task_style(exit_button,false); taskbar.add_child(exit_button)
	var show_desktop := _tool_button("grid","デスクトップを表示",_show_desktop); show_desktop.name="ShowDesktop"; show_desktop.icon=null; show_desktop.custom_minimum_size=Vector2(12,42); _task_style(show_desktop,false); taskbar.add_child(show_desktop)
	show_desktop.add_theme_stylebox_override("normal",UI.style(Color("dae1e8"),Color("cbd3dc"),0,0,2))
	start_menu=PanelContainer.new(); start_menu.name="StartMenu"; start_menu.set_anchors_preset(Control.PRESET_TOP_LEFT); start_menu.size=Vector2(600,478); start_menu.add_theme_stylebox_override("panel",UI.style(Color("f2f5fa"),Color("cdd4df"),26,22,8)); add_child(start_menu)
	start_menu.minimum_size_changed.connect(func():call_deferred("_layout_launcher"))
	var menu:=_box(start_menu,16)
	launcher_search=LineEdit.new(); launcher_search.name="LauncherSearch"; launcher_search.placeholder_text=UI.copy("fidelity_start_search"); launcher_search.right_icon=UI.symbol("search"); launcher_search.clear_button_enabled=true; launcher_search.custom_minimum_size.y=34; menu.add_child(launcher_search)
	menu.add_child(_label(UI.copy("fidelity_all_apps"),13))
	var app_scroll:=ScrollContainer.new(); app_scroll.name="LauncherAppScroll"; app_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; app_scroll.custom_minimum_size.y=150; app_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; menu.add_child(app_scroll)
	launcher_apps=GridContainer.new(); launcher_apps.columns=6; launcher_apps.add_theme_constant_override("h_separation",6); launcher_apps.add_theme_constant_override("v_separation",8); app_scroll.add_child(launcher_apps)
	for id in APPS: launcher_apps.add_child(_app_tile(id,false))
	for tile in launcher_apps.get_children(): tile.focus_entered.connect(app_scroll.ensure_control_visible.bind(tile))
	launcher_search.text_changed.connect(func(query):
		for tile in launcher_apps.get_children():
			var app: String=String(tile.name).trim_prefix("StartApp_")
			tile.visible=query.is_empty() or (str(APPS[app][0])+" "+app).to_lower().contains(query.to_lower()))
	launcher_search.text_submitted.connect(func(_query):
		for tile in launcher_apps.get_children():
			if tile.visible: tile.pressed.emit(); break)
	var menu_fill:=Control.new(); menu_fill.size_flags_vertical=Control.SIZE_EXPAND_FILL; menu.add_child(menu_fill)
	var user_row:=_row(menu,8); user_row.add_child(_icon("team",26)); player_name_label=_label(_player_display_name(),14); player_name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; user_row.add_child(player_name_label); user_row.add_child(_tool_button("close",UI.copy("fidelity_close"),func():start_menu.hide()))
	system_company=_label(_company_name(),12,UI.MUTED); system_company.hide(); menu.add_child(system_company)
	menu.add_child(HSeparator.new()); var bottom:=_row(menu,4)
	bottom.add_child(_button("案件",_contracts)); var spacer:=Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bottom.add_child(spacer)
	var windows_menu := MenuButton.new(); windows_menu.text="ウィンドウ"; bottom.add_child(windows_menu)
	var window_popup := windows_menu.get_popup(); window_popup.add_item(UI.copy("os_tile"),1); window_popup.add_item(UI.copy("os_cascade"),2); window_popup.add_separator(); window_popup.add_item("開いているアプリ",3)
	window_popup.id_pressed.connect(func(id):
		start_menu.hide()
		if id==1: _tile_windows()
		elif id==2: _cascade_windows_desktop()
		else: _toggle_overview())
	start_menu.hide()
	overview=PanelContainer.new(); overview.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); overview.offset_left=10; overview.offset_right=-10; overview.offset_top=-230; overview.offset_bottom=-58; overview.add_theme_stylebox_override("panel",UI.style(UI.SURFACE,UI.BORDER,12,10)); add_child(overview); overview.hide()
	_state_changed()
	_layout_shell()

func _build_system_bar() -> void:
	system_bar = PanelContainer.new()
	system_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	system_bar.offset_bottom = 40
	system_bar.add_theme_stylebox_override("panel", UI.style(UI.OS_SHELL, UI.OS_EDGE, 10, 3, 0))
	add_child(system_bar)
	var row := _row(system_bar, 8)
	var mark := _icon("team", 24); row.add_child(mark)
	var company := _label(_company_name(), 14, UI.OS_IVORY); company.custom_minimum_size.x = 150; company.clip_text=true; company.autowrap_mode=TextServer.AUTOWRAP_OFF; company.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(company); system_company=company
	company.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var apps := MenuButton.new(); apps.text = UI.copy("os_apps"); apps.custom_minimum_size.x = 76; apps.flat = true; apps.add_theme_color_override("font_color", UI.OS_IVORY); row.add_child(apps)
	var app_popup := apps.get_popup()
	for id in APPS:
		app_popup.add_item(APPS[id][0], app_popup.item_count)
		app_popup.set_item_metadata(app_popup.item_count - 1, id)
	app_popup.id_pressed.connect(func(index): _show_app(str(app_popup.get_item_metadata(index))))
	var windows_menu := MenuButton.new(); windows_menu.text = "ウィンドウ"; windows_menu.custom_minimum_size.x = 100; windows_menu.flat = true; windows_menu.add_theme_color_override("font_color", UI.OS_IVORY); row.add_child(windows_menu)
	var window_popup := windows_menu.get_popup()
	window_popup.add_item(UI.copy("os_tile"), 1); window_popup.add_item(UI.copy("os_cascade"), 2); window_popup.add_separator(); window_popup.add_item("開いているアプリ", 3)
	window_popup.id_pressed.connect(func(id):
		if id == 1: _tile_windows()
		elif id == 2: _cascade_windows_desktop()
		elif id == 3: _toggle_overview())
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(spacer)
	var target := _label("", 12, UI.OS_IVORY); target.custom_minimum_size.x = 170; target.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(target); system_target = target
	var clock := _label("", 12, UI.OS_IVORY); clock.custom_minimum_size.x = 170; clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(clock); system_clock = clock
	var menu := _tool_button("grid", "ランチャー", func(): start_menu.visible = not start_menu.visible); menu.modulate = UI.OS_IVORY; row.add_child(menu)
	menu.icon=null; menu.text="▦"; menu.modulate=Color.WHITE; UI.shell_navigation(menu,false)

func _build_side_rail() -> void:
	side_rail = PanelContainer.new()
	side_rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side_rail.offset_right = 190
	side_rail.offset_bottom = -50
	side_rail.add_theme_stylebox_override("panel", UI.style(UI.OS_SHELL, UI.OS_EDGE, 0, 0, 0))
	add_child(side_rail)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_"+side, 12)
	side_rail.add_child(margin)
	var box := _box(margin, 8)
	var logo_row := _row(box, 8)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/ui/mark.svg")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(34, 34)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_row.add_child(mark)
	var logo := _label(_company_name(), 16, UI.OS_IVORY)
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	logo.add_theme_constant_override("line_spacing", -4)
	logo_row.add_child(logo)
	box.add_child(HSeparator.new())
	for entry in [["cases", "案件", "mail"], ["company", "会社・スキル", "team"], ["equipment", "設備購入", "monitor"], ["desktop", "業務デスクトップ", "grid"]]:
		var button: Button = _rail_button(str(entry[1]), str(entry[2]), _rail_action.bind(str(entry[0])))
		rail_buttons[str(entry[0])] = button
		box.add_child(button)
	box.add_child(HSeparator.new())
	box.add_child(_rail_button("オプション", "manual", _show_app.bind("manual")))
	box.add_child(_rail_button("クレジット", "receipt", _show_app.bind("receipt")))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(_rail_button("終了", "external", _close))

func _rail_button(text: String, icon_id: String, callback: Callable) -> Button:
	var button := _button(text, callback)
	button.icon = UI.icon(icon_id)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 20)
	button.custom_minimum_size = Vector2(0, 38)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = false
	button.modulate = Color.WHITE
	UI.shell_navigation(button, false)
	return button

func _rail_action(id: String) -> void:
	match id:
		"cases": _contracts()
		"company": _company()
		"equipment": _request_equipment()
		"desktop": _show_app(current_app if not current_app.is_empty() else "mail")
	for key in rail_buttons:
		rail_buttons[key].modulate = Color.WHITE
		rail_buttons[key].flat = false
		UI.shell_navigation(rail_buttons[key], key == id)

func _request_equipment() -> void:
	if _save_session(): equipment_requested.emit()

func _request_stock_preparation() -> void:
	if _save_session(): stock_preparation_requested.emit()

func _build_compact_nav() -> void:
	compact_nav = PanelContainer.new()
	compact_nav.set_anchors_preset(Control.PRESET_TOP_WIDE)
	compact_nav.offset_bottom = 40
	compact_nav.add_theme_stylebox_override("panel", UI.style(UI.OS_SHELL, UI.OS_EDGE, 6, 3, 0))
	add_child(compact_nav)
	var row := _row(compact_nav, 3)
	row.add_theme_constant_override("separation", 3)
	for entry in [["案件", _contracts], ["会社・スキル", _company], ["設備購入", _request_equipment], ["業務PC", func(): _show_app(current_app if not current_app.is_empty() else "mail")]]:
		var button := _button(str(entry[0]), entry[1])
		button.custom_minimum_size.y = 34
		button.flat = false
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.shell_navigation(button, entry[0] == "業務PC")
		row.add_child(button)

func _layout_shell() -> void:
	if not is_instance_valid(workspace): return
	_layout_taskbar()
	_layout_launcher()
	var wide: bool = _is_wide_layout()
	if is_instance_valid(side_rail): side_rail.visible = false
	if is_instance_valid(compact_nav): compact_nav.visible = false
	workspace.offset_left = 0
	workspace.offset_top = 0
	workspace.offset_bottom = -52
	for w in windows.values():
		if w.maximized:
			w.position = Vector2.ZERO
			w.size = workspace.size
			w.clamp_to_desktop()
	if not rail_buttons.is_empty():
		for key in rail_buttons:
			rail_buttons[key].modulate = Color.WHITE
			rail_buttons[key].flat = false
			UI.shell_navigation(rail_buttons[key], false)

func _layout_taskbar() -> void:
	if not is_instance_valid(taskbar_offset) or not is_instance_valid(task_scroll): return
	var narrow := size.x < 1100.0
	var target_slot: Node = taskbar.find_child("TargetSelectorSlot", true, false)
	if target_slot != null:
		target_slot.custom_minimum_size.x=92.0 if narrow else 116.0
	var exit_button: Button = taskbar.find_child("ExitDesktop", true, false) as Button
	if exit_button != null:
		exit_button.text="" if narrow else UI.copy("os_office","オフィスへ戻る")
		exit_button.custom_minimum_size.x=38.0 if narrow else 132.0
		exit_button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var return_button: Button = taskbar.find_child("DesktopReturn", true, false) as Button
	if return_button != null:
		return_button.visible=not configured_return_label.is_empty()
		return_button.text="" if narrow else configured_return_label
		return_button.tooltip_text=configured_return_label
		return_button.custom_minimum_size.x=38.0 if narrow else 148.0
		return_button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var show_desktop: Button = taskbar.find_child("ShowDesktop", true, false) as Button
	if show_desktop != null: show_desktop.custom_minimum_size.x=10.0 if narrow else 12.0
	if is_instance_valid(tray):
		tray.custom_minimum_size.x=58.0 if narrow else 78.0
	var count:=0
	for id in task_buttons:
		if id in PINNED_APPS or id in running_apps: count+=1
	var dock: PanelContainer = taskbar.get_parent()
	var fixed_width: float = dock.get_theme_stylebox("panel").get_minimum_size().x
	var visible_count := 0
	for child in taskbar.get_children():
		if not child is Control or not child.visible: continue
		visible_count += 1
		if child != taskbar_offset and child != task_scroll: fixed_width += child.get_combined_minimum_size().x
	fixed_width += maxi(0, visible_count - 1) * taskbar.get_theme_constant("separation")
	var available_width: float = maxf(0.0, size.x - fixed_width)
	var dock_width: float = minf(float(count) * 48.0, available_width)
	task_scroll.custom_minimum_size.x=dock_width
	# Keep the software strip anchored; notices and new apps use the spare
	# space to its right instead of recentering the primary return targets.
	taskbar_offset.custom_minimum_size.x=0.0
	dock.offset_left = 0.0; dock.offset_right = 0.0

func _layout_launcher() -> void:
	if not is_instance_valid(start_menu): return
	var menu_width:=minf(600.0,maxf(360.0,size.x-24.0))
	var safe_top:=8.0
	var available_height:=maxf(250.0,size.y-52.0-safe_top-8.0)
	start_menu.clip_contents=true
	start_menu.size=Vector2(menu_width,minf(maxf(478.0,start_menu.get_combined_minimum_size().y),available_height))
	start_menu.position=Vector2((size.x-start_menu.size.x)*0.5,maxf(safe_top,size.y-62.0-start_menu.size.y))
	if is_instance_valid(launcher_apps): launcher_apps.columns=3 if menu_width<500.0 else 6

func _icon(app: String, pixels := 24) -> TextureRect:
	var image := TextureRect.new(); image.texture=UI.icon(app); image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.custom_minimum_size=Vector2(pixels,pixels); image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return image

func _tool_button(symbol_name: String, tooltip: String, callback: Callable) -> Button:
	var button:=_button("",callback); button.icon=UI.symbol(symbol_name); button.expand_icon=true; button.add_theme_constant_override("icon_max_width",18); button.custom_minimum_size=Vector2(30,30); button.tooltip_text=tooltip; button.flat=true
	return button

func _app_tile(app: String, on_desktop: bool) -> Button:
	var button:=_button("",func():
		if on_desktop: _select_shortcut(app)
		else:
			if is_instance_valid(start_menu): start_menu.hide()
			_show_app(app))
	button.name=("DesktopShortcut_" if on_desktop else "StartApp_")+app
	if on_desktop:
		button.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click: _show_app(app); button.accept_event()
			elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER]: _show_app(app); button.accept_event())
	button.custom_minimum_size=Vector2(84,64+36*float(game.settings.get("text_scale",1.0))); button.tooltip_text=APPS[app][0]; button.flat=true
	button.add_theme_stylebox_override("normal",UI.style(Color.TRANSPARENT,Color.TRANSPARENT,0,0))
	button.add_theme_stylebox_override("hover",UI.style(Color(0.7,0.85,0.95,0.2) if on_desktop else UI.SELECTED,Color.TRANSPARENT,0,0,6))
	var layout:=VBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layout.offset_top=4; layout.offset_left=3; layout.offset_right=-3; layout.offset_bottom=-4; layout.add_theme_constant_override("separation",0); layout.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(layout)
	var image:=_icon(app,56); image.size_flags_horizontal=Control.SIZE_SHRINK_CENTER; image.size_flags_vertical=Control.SIZE_EXPAND_FILL; layout.add_child(image)
	var label:=_label({"monitor":"監視","verify":"診断","manual":"ヘルプ","receipt":"納品"}.get(app,APPS[app][0]),12,Color("f1f5f5") if on_desktop else INK); label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY; label.clip_text=false; label.mouse_filter=Control.MOUSE_FILTER_IGNORE; layout.add_child(label)
	label.custom_minimum_size.y=36*float(game.settings.get("text_scale",1.0)); label.vertical_alignment=VERTICAL_ALIGNMENT_TOP
	return button

func _select_shortcut(app: String) -> void:
	selected_shortcut=app
	for id in desktop_shortcuts:
		var shortcut: Button=desktop_shortcuts[id]
		shortcut.add_theme_stylebox_override("normal",UI.style(Color(0.65,0.82,1,0.22) if id==app else Color.TRANSPARENT,Color(0.7,0.85,1,0.6) if id==app else Color.TRANSPARENT,0,0,3))

func _show_desktop() -> void:
	start_menu.hide(); overview.hide(); _remember_editor()
	if desktop_hidden_windows.is_empty():
		desktop_hidden_active=current_app
		for id in running_apps:
			if windows.has(id) and windows[id].visible:
				desktop_hidden_windows.append(id); windows[id].hide(); windows[id].set_active(false)
		current_app=""
	else:
		for id in desktop_hidden_windows:
			if id in running_apps and windows.has(id): windows[id].show()
		if desktop_hidden_active in running_apps: _focus(desktop_hidden_active)
		desktop_hidden_windows.clear(); desktop_hidden_active=""
	for id in task_buttons: _layout_task_button(id)
	_save_session(false)

func _style(color: Color, border := Color.TRANSPARENT, x := 12, y := 8) -> StyleBoxFlat:
	return UI.style(color,border,x,y)

func _label(text: String, point := 14, color := INK) -> Label:
	var l := Label.new(); l.text = text; l.add_theme_font_size_override("font_size",maxi(11,int(point * float(game.settings.get("text_scale",1.0))))); l.add_theme_color_override("font_color",color); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if point>=18 and heading_font!=null: l.add_theme_font_override("font",heading_font)
	return l
func _button(text: String, callback: Callable) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size.y = 30; b.pressed.connect(func(): get_node("/root/Soundscape").play_ui("click")); b.pressed.connect(callback); return b
func _primary(text: String, callback: Callable) -> Button:
	var b := _button(text,callback); UI.os_primary(b); return b

func _row(parent: Node, space := 8) -> HBoxContainer:
	var r := HBoxContainer.new(); r.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r.add_theme_constant_override("separation",space)
	r.child_entered_tree.connect(func(child):
		if child is Label and not (child.size_flags_horizontal & Control.SIZE_EXPAND): child.autowrap_mode=TextServer.AUTOWRAP_OFF)
	parent.add_child(r); return r
func _box(parent: Node, space := 10) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation",space); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(v); return v
func _pad(parent: Node, amount := 16) -> VBoxContainer:
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL; parent.add_child(m)
	for side in ["left","right","top","bottom"]: m.add_theme_constant_override("margin_"+side,amount)
	return _box(m)
func _scroll(parent: Node) -> VBoxContainer:
	var s := ScrollContainer.new(); s.follow_focus = true; s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; s.size_flags_vertical = Control.SIZE_EXPAND_FILL; s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(s); return _box(s)
func _clear(node: Node) -> void:
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func _show_app(app: String) -> void:
	if app in ["monitor", "verify"] and game.has_method("advanced_active") and game.advanced_active(): app = "advanced"
	if not APPS.has(app) or switching_target: return
	if app not in running_apps: running_apps.append(app)
	desktop_hidden_windows.clear(); desktop_hidden_active=""
	if is_instance_valid(start_menu): start_menu.hide()
	if is_instance_valid(overview): overview.hide()
	_trace("open_app",app)
	_remember_editor()
	if not windows.has(app):
		var w := WINDOW.new(); workspace.add_child(w); w.configure(app,APPS[app][0],Color(APPS[app][2])); windows[app] = w
		w.set_meta("aoba_focus_app", app)
		var usable: Vector2 = workspace.size if workspace.size.x > 1.0 and workspace.size.y > 1.0 else get_viewport_rect().size
		var window_index: int = windows.size() - 1
		var wide_layout: bool = _is_wide_layout()
		var window_size: Vector2 = Vector2(minf(usable.x * 0.86, 1320.0), minf(usable.y * 0.84, 860.0))
		window_size.x = maxf(530.0, window_size.x)
		window_size.y = maxf(320.0, window_size.y)
		window_size = window_size.min(usable)
		var window_pos := Vector2(28.0 + float(window_index % 3) * 34.0, 20.0 + float(window_index % 3) * 28.0)
		window_pos.x = minf(window_pos.x, maxf(0.0, usable.x - window_size.x))
		window_pos.y = minf(window_pos.y, maxf(0.0, usable.y - window_size.y))
		w.size = window_size; w.position = window_pos; w.restore_rect = Rect2(window_pos,window_size); w.maximized = not wide_layout
		if w.maximized:
			w.position = Vector2.ZERO
			w.size = usable
		w.focused.connect(_focus.bind(false)); w.minimized.connect(_minimized); w.dismissed.connect(_dismissed); widgets[app] = {}; _build_app(app); _wire_focus(w.content,app)
		var saved: Array = game.state.get("desktop_sessions",{}).get(session_key,{}).get("windows",{}).get(app,[])
		if saved.size() == 4:
			w.maximized = bool(game.state.get("desktop_sessions",{}).get(session_key,{}).get("maximized",{}).get(app,false))
			w.position = Vector2(float(saved[0]),float(saved[1])); w.size = Vector2(float(saved[2]),float(saved[3])).min(usable); w.clamp_to_desktop()
			w.restore_rect = Rect2(w.position,w.size)
			if w.maximized: w.position = Vector2.ZERO; w.size = usable
		if not task_buttons.has(app):
			_add_task_button(app)
	windows[app].show(); _focus(app, false)
	if app == "mail": _refresh_mail()
	if app == "monitor": _refresh_monitor()
	if app == "verify": _refresh_checks()
	if app == "receipt": _refresh_receipt()
	if app == "billing": _render_billing()
	if app == "browser": _refresh_completed_browser()
	if app == "team": _refresh_team()
	if app == "advanced": _refresh_advanced()
	_restore_keyboard_focus(app)
	# Workstation chrome stays native; the optional first-job coach is owned by interface.gd.

func _add_task_button(app: String) -> void:
	var b:=_button("",_taskbar_activate.bind(app)); b.name="TaskbarApp_"+app; b.icon=UI.icon(app); b.expand_icon=true; b.add_theme_constant_override("icon_max_width",28); b.custom_minimum_size=Vector2(46,42); b.tooltip_text=APPS[app][0]; b.flat=false; app_dock.add_child(b); task_buttons[app]=b
	b.focus_entered.connect(task_scroll.ensure_control_visible.bind(b))
	var indicator:=ColorRect.new(); indicator.name="RunningIndicator"; indicator.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); indicator.offset_left=15; indicator.offset_right=-15; indicator.offset_top=-4; indicator.offset_bottom=-1; indicator.mouse_filter=Control.MOUSE_FILTER_IGNORE; b.add_child(indicator)
	_layout_task_button(app)

func _app_task_label(app: String) -> String:
	return {"terminal":"端末","editor":"編集","browser":"Web","monitor":"監視","verify":"診断","manual":"ヘルプ","receipt":"納品"}.get(app, APPS.get(app,[app])[0])

func _layout_task_button(app: String) -> void:
	if not task_buttons.has(app): return
	var button: Button=task_buttons[app]
	button.text=""; button.tooltip_text=APPS[app][0]; button.custom_minimum_size=Vector2(46,42)
	button.visible=app in PINNED_APPS or app in running_apps
	_task_style(button,current_app==app)
	var indicator: ColorRect=button.get_node("RunningIndicator")
	indicator.visible=app in running_apps
	indicator.color=UI.PRIMARY if current_app==app else Color("798693")
	indicator.offset_left=12 if current_app==app else 17; indicator.offset_right=-12 if current_app==app else -17
	_layout_taskbar()

func _task_style(button: Button, active: bool) -> void:
	button.flat=false; button.modulate=Color.WHITE
	button.add_theme_stylebox_override("normal",UI.style(Color("ffffff") if active else Color.TRANSPARENT,Color("d3dce5") if active else Color.TRANSPARENT,6,4,4))
	button.add_theme_stylebox_override("hover",UI.style(Color("f7f9fb"),Color("d3dce5"),6,4,4))
	button.add_theme_stylebox_override("pressed",UI.style(Color("dde7f1"),Color("c5d3e2"),6,4,4))
	button.add_theme_color_override("font_color",UI.INK)

func _taskbar_activate(app: String) -> void:
	if windows.has(app) and windows[app].visible and current_app == app:
		windows[app].hide()
		_minimized(app)
	else:
		_show_app(app)

func _toggle_overview() -> void:
	if not is_instance_valid(overview): return
	if overview.visible:
		overview.hide()
		return
	start_menu.hide()
	_clear(overview)
	var box := _box(overview, 8)
	var head := _row(box, 6)
	head.add_child(_label("開いているアプリ", 15))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(spacer)
	head.add_child(_tool_button("close", "一覧を閉じる", func(): overview.hide()))
	box.add_child(HSeparator.new())
	var scroll_host := Control.new()
	scroll_host.custom_minimum_size = Vector2(0, 0)
	scroll_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_host.clip_contents = true
	box.add_child(scroll_host)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_host.add_child(scroll)
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid)
	var count := 0
	for id in focus_order:
		if not windows.has(id) or id not in running_apps: continue
		var button := _button(APPS[id][0]+("  ·  表示中" if windows[id].visible else "  ·  最小化"), _taskbar_activate.bind(id))
		button.icon = UI.icon(id); button.expand_icon = true; button.add_theme_constant_override("icon_max_width", 20)
		button.tooltip_text = APPS[id][0]
		grid.add_child(button); count += 1
	for id in running_apps:
		if focus_order.has(id): continue
		var button := _button(APPS[id][0]+("  ·  表示中" if windows[id].visible else "  ·  最小化"), _taskbar_activate.bind(id))
		button.icon = UI.icon(id); button.expand_icon = true; button.add_theme_constant_override("icon_max_width", 20)
		button.tooltip_text = APPS[id][0]
		grid.add_child(button); count += 1
	var logical_width: float = size.x if size.x > 1.0 else get_viewport_rect().size.x
	var columns: int = _overview_columns(logical_width)
	# Four open apps fit on one row on a wide work area even when the
	# presentation is running at a smaller logical scale.  Narrow layouts keep
	# their two-column limit; larger sets still use the responsive grid.
	if logical_width >= 1120.0 and count > columns and count <= 4: columns = count
	grid.columns = mini(columns, maxi(count, 1))
	if count == 0:
		grid.add_child(_label("アプリ未起動", 13, MUTED))
	# The overview is a bounded surface.  The scroll container absorbs additional
	# windows instead of allowing its minimum height to push the panel off-screen.
	overview.custom_minimum_size = Vector2(0, 0)
	overview.clip_contents = true
	overview.offset_top = -230
	overview.offset_bottom = -58
	overview.show()
	# Reapply the bounded height after child minimum sizes are calculated.
	overview.size.y = 172.0

func _overview_columns(width: float) -> int:
	if width < 1120.0: return 2
	if width < 1600.0: return 3
	return 5

func _tile_windows() -> void:
	# Give the two most recently used visible apps a stable side-by-side
	# workspace on wide screens.  Narrow screens cannot fit two chrome bars;
	# keep the front app maximized and leave the rest available from overview.
	var visible: Array[String] = []
	for id in focus_order:
		if windows.has(id) and windows[id].visible: visible.append(id)
	if visible.size() < 2: return
	var area: Vector2 = workspace.size
	if area.x <= 1.0 or area.y <= 1.0: return
	if not _is_wide_layout():
		var front: String = visible[0]
		for id in visible.slice(1):
			windows[id].hide()
			focus_order.erase(id)
		var front_window: Control = windows[front]
		front_window.maximized = true
		front_window.position = Vector2.ZERO
		front_window.size = area
		_focus(front)
		return
	visible = visible.slice(0, 2)
	var margin := 18.0
	var gap := 12.0
	var cell := Vector2((area.x - margin * 2.0 - gap) / 2.0, area.y - margin * 2.0)
	for i in visible.size():
		var w: Control = windows[visible[i]]
		w.maximized = false
		w.position = Vector2(margin + float(i) * (cell.x + gap), margin)
		w.size = cell
		w.restore_rect = Rect2(w.position, w.size)
		w.clamp_to_desktop()
	_focus(visible[0])

func _cascade_windows_desktop() -> void:
	var visible: Array[String] = []
	for id in focus_order:
		if windows.has(id) and windows[id].visible: visible.append(id)
	if visible.is_empty(): return
	var area: Vector2 = workspace.size
	var size := Vector2(minf(area.x * 0.78, 1180.0), minf(area.y * 0.78, 760.0))
	for i in visible.size():
		var w: Control = windows[visible[i]]
		w.maximized = false
		w.size = size.min(area)
		w.position = Vector2(24.0 + float(i) * 34.0, 18.0 + float(i) * 30.0)
		w.clamp_to_desktop()
		w.restore_rect = Rect2(w.position, w.size)
	_focus(visible[0])

func _build_app(app: String) -> void:
	var container: VBoxContainer = windows[app].content
	container.theme = UI.app_theme(app, float(game.settings.get("text_scale",1.0)))
	match app:
		"mail": _mail(container)
		"terminal": _terminal(container)
		"files": _files(container)
		"editor": _editor(container)
		"browser": _browser(container)
		"monitor": _monitor(container)
		"verify": _checks(container)
		"team": _team(container)
		"manual": _manual(container)
		"receipt": _receipt(container)
		"advanced": ADVANCED_WORKSPACE.build(self, container)
		"billing":
			widgets.billing.page = _scroll(container)
			_render_billing()

func _billing_signature() -> String:
	return str([game.state.get("day", 0), game.state.get("billing", {})])

func _render_billing() -> void:
	if not widgets.has("billing"): return
	var page: VBoxContainer = widgets.billing.page
	_clear(page)
	BILLING_WORKSPACE.render(self, page)
	billing_render_signature = _billing_signature()
	_wire_focus(page, "billing")

func open_invoice(id: String = "") -> void:
	billing_ui["view"] = "invoices"
	billing_ui["selected"] = id
	_show_app("billing")
	_save_session(false)

func open_delivery_history(contract_id: String) -> bool:
	if COMPLETED_CASE.delivery_for(game.state, contract_id).is_empty():
		_notify("この案件の納品履歴を確認できません。")
		return false
	var items := BUSINESS._history_items(game)
	var index := -1
	var title := ""
	for position in items.size():
		var record: Dictionary = items[position].get("item", {})
		if str(record.get("id", "")) != contract_id: continue
		index = position; title = str(record.get("title", "")); break
	if index < 0:
		_notify("この案件の納品履歴を確認できません。")
		return false
	if not _save_session(): return false
	mail_ui.merge({"folder":"history", "reading":true, "selected_id":contract_id, "selected_subject":title, "history_index":index}, true)
	if widgets.has("mail"):
		var mail: Dictionary = widgets.mail
		mail.folder = "history"; mail.reading = true; mail.selected_id = contract_id
		mail.selected_subject = title; mail.history_index = index
	_show_app("mail")
	if widgets.has("mail"):
		BUSINESS.refresh_mail(self)
		_save_session(false)
	return true

func _refresh_billing_if_changed() -> void:
	if widgets.has("billing") and _billing_signature() != billing_render_signature: _render_billing()

func _focus(app: String, restore_keyboard := true) -> void:
	if switching_target or app not in running_apps or not windows.has(app) or not is_instance_valid(windows[app]): return
	var changed_app := current_app != app
	current_app = app
	focus_order.erase(app)
	focus_order.push_front(app)
	for id in windows:
		windows[id].set_active(id == app)
		if task_buttons.has(id):
			task_buttons[id].modulate = Color.WHITE
			task_buttons[id].flat = false
			UI.shell_navigation(task_buttons[id],id == app,UI.app_tint(id))
		if task_buttons.has(id): _layout_task_button(id)
	workspace.move_child(windows[app],workspace.get_child_count()-1); body = windows[app].content
	if changed_app and app == "files" and _samba_v2() and bool(samba_ui.get("network_open", false)):
		_remember_editor()
		# Reconcile the saved/draft copy when returning from another app. This
		# redraws the captured specimen without issuing a new SMB request.
		FILES.refresh(self)
	_wire_focus(windows[app].content, app)
	if app == "editor": editor = widgets.editor.editor; path_edit = widgets.editor.path; EDITOR.refresh(self)
	if app == "files": file_list = widgets.files.list; path_edit = widgets.files.path
	if app == "terminal": output = widgets.terminal.output; command = widgets.terminal.command; prompt = widgets.terminal.prompt
	if app == "browser": url_edit = widgets.browser.url
	if restore_keyboard: _restore_keyboard_focus(app)
	elif changed_app:
		# Mouse focus is assigned during GUI dispatch. Let the clicked control
		# take it first; a titlebar/blank-area click restores only if needed.
		call_deferred("_restore_keyboard_focus", app)

func _focus_app_for(control: Control) -> String:
	if not is_instance_valid(control) or not control.is_inside_tree(): return ""
	var node: Node = control
	while node != null and node != self:
		if node.has_meta("aoba_focus_app"):
			var app := str(node.get_meta("aoba_focus_app"))
			if windows.has(app) and is_instance_valid(windows[app]) and windows[app].is_ancestor_of(control): return app
		node = node.get_parent()
	return ""

func _keyboard_focus_changed(control: Control) -> void:
	var app := _focus_app_for(control)
	if app.is_empty() or app not in running_apps: return
	# Window chrome must not replace the remembered editor/input when a user
	# clicks Minimize or Close and later reopens the application.
	if windows[app].content.is_ancestor_of(control): _app_keyboard_focus[app] = weakref(control)
	if app != current_app: _focus(app, false)

func _usable_keyboard_focus(control: Control) -> bool:
	return is_instance_valid(control) and control.is_inside_tree() and not control.is_queued_for_deletion() and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and control.disabled)

func _first_keyboard_focus(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and _usable_keyboard_focus(child): return child
		var nested := _first_keyboard_focus(child)
		if nested != null: return nested
	return null

func _restore_keyboard_focus(app: String) -> void:
	if switching_target or app != current_app or app not in running_apps or not windows.has(app) or not windows[app].is_visible_in_tree(): return
	if (is_instance_valid(start_menu) and start_menu.visible) or (is_instance_valid(overview) and overview.visible): return
	var owner := get_viewport().gui_get_focus_owner()
	if _focus_app_for(owner) == app and _usable_keyboard_focus(owner): return
	var target: Control = null
	var remembered: WeakRef = _app_keyboard_focus.get(app)
	if remembered != null:
		var previous = remembered.get_ref()
		if previous is Control and _usable_keyboard_focus(previous) and _focus_app_for(previous) == app: target = previous
	if target == null:
		var preferred: Dictionary = {"editor":"editor", "terminal":"command", "browser":"url", "files":"list"}
		var candidate = widgets.get(app, {}).get(str(preferred.get(app, "")))
		if candidate is Control and _usable_keyboard_focus(candidate): target = candidate
	if target == null: target = _first_keyboard_focus(windows[app].content)
	if target != null: target.grab_focus()
	elif is_instance_valid(owner): owner.release_focus()
func _minimized(_app: String) -> void:
	_remember_editor()
	focus_order.erase(_app)
	if _app in running_apps: focus_order.push_back(_app)
	if windows.has(_app): windows[_app].set_active(false)
	current_app = ""
	for id in focus_order:
		if id in running_apps and windows.has(id) and windows[id].visible:
			_focus(id)
			_save_session(false)
			return
	for id in running_apps:
		if windows[id].visible:
			_focus(id)
			_save_session(false)
			return
	for id in task_buttons:
		_layout_task_button(id)
	_save_session(false)

func _dismissed(app: String) -> void:
	_remember_editor()
	if windows.has(app): windows[app].hide()
	running_apps.erase(app); alt_tab_order.erase(app); desktop_hidden_windows.erase(app)
	_minimized(app)
func _wire_focus(node: Node, app: String) -> void:
	for child in node.get_children():
		if child is Control:
			if not child.has_meta("aoba_focus_app"):
				child.set_meta("aoba_focus_app", app)
				child.gui_input.connect(func(event):
					if event is InputEventMouseButton and event.pressed: _focus(app, false))
		_wire_focus(child,app)
func _desktop_resized() -> void:
	_layout_shell()
	for app in task_buttons:
		_layout_task_button(app)
	for w in windows.values():
		if w.maximized: w.position = Vector2.ZERO; w.size = workspace.size
		else: w.size = w.size.min(workspace.size); w.clamp_to_desktop()
func _remember_editor() -> void:
	if widgets.has("editor") and widgets.editor.has("editor") and is_instance_valid(widgets.editor.editor) and not editor_path.is_empty(): drafts[editor_path] = widgets.editor.editor.text
func _save_session(persist: bool = true) -> bool:
	if game == null or session_key.is_empty(): return false
	_remember_editor()
	var had_session: bool = game.state.get("desktop_sessions", {}).has(session_key)
	var previous_session: Dictionary = game.state.get("desktop_sessions", {}).get(session_key, {}).duplicate(true)
	if not game.state.has("desktop_sessions"): game.state.desktop_sessions = {}
	var placement := {}
	var maximize_states := {}
	for id in windows:
		maximize_states[id] = windows[id].maximized
		var w = windows[id]; var rect: Rect2 = w.restore_rect if w.maximized else Rect2(w.position,w.size); placement[id] = [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
	var opened: Array = []
	for id in windows:
		if windows[id].visible: opened.append(id)
	if widgets.has("files"):
		file_history = widgets.files.history.duplicate(true)
		file_forward_history = widgets.files.forward_history.duplicate(true)
	var saved_mail_ui: Dictionary = mail_ui.duplicate(true)
	if widgets.has("mail"):
		var live_mail: Dictionary = widgets.mail
		saved_mail_ui["folder"] = str(live_mail.get("folder", "inbox"))
		saved_mail_ui["reading"] = bool(live_mail.get("reading", false))
		saved_mail_ui["selected_subject"] = str(live_mail.get("selected_subject", ""))
		saved_mail_ui["selected_id"] = str(live_mail.get("selected_id", ""))
		saved_mail_ui["history_index"] = int(live_mail.get("history_index", 0))
		saved_mail_ui["single_pane"] = bool(live_mail.get("single_pane", false))
		saved_mail_ui["folders_hidden"] = bool(live_mail.get("folders_hidden", false))
		if is_instance_valid(live_mail.get("search")): saved_mail_ui["query"] = str(live_mail.search.text)
	mail_ui = saved_mail_ui.duplicate(true)
	game.state.desktop_sessions[session_key] = {"log":terminal_log,"drafts":drafts.duplicate(true),"history":history.duplicate(),"directory":file_directory,"file_remote":file_remote,"file_history":file_history.duplicate(true),"file_forward_history":file_forward_history.duplicate(true),"editor_path":editor_path,"editor_tabs":widgets.get("editor", {}).get("opened", []).duplicate(),"url":browser_url,"browser_response":browser_response,"browser_identity":browser_identity,"identity_ui":identity_ui.duplicate(true),"edr_ui":edr_ui.duplicate(true),"portal_ui":portal_ui.duplicate(true),"firewall_ui":firewall_ui.duplicate(true),"backup_ui":backup_ui.duplicate(true),"samba_ui":samba_ui.duplicate(true),"business_ui":business_ui.duplicate(true),"billing_ui":billing_ui.duplicate(true),"mail_ui":saved_mail_ui,"browser_history":browser_history.duplicate(),"browser_history_index":browser_history_index,"windows":placement,"maximized":maximize_states,"open_apps":opened,"running_apps":running_apps.duplicate(),"active_app":current_app}
	game.state.desktop_sessions[session_key]["advanced_ui"] = advanced_ui.duplicate(true)
	game.state.desktop_sessions[session_key]["pentest_ui"] = pentest_ui.duplicate(true)
	game.state.desktop_sessions[session_key]["diagnostic_ui"] = diagnostic_ui.duplicate(true)
	game.state.desktop_sessions[session_key]["monitor_ui"] = monitor_ui.duplicate(true)
	game.state.desktop_sessions[session_key]["file_selections"] = widgets.get("files",{}).get("selection_by_location",{}).duplicate(true)
	if persist and not game.save_game():
		if had_session: game.state.desktop_sessions[session_key] = previous_session
		else: game.state.desktop_sessions.erase(session_key)
		_notify(UI.copy("queue_save_failed"))
		return false
	return true

func _restore_session_windows(saved: Dictionary) -> void:
	var opened: Array=saved.get("open_apps",["mail"])
	var running: Array=saved.get("running_apps",opened)
	for app in running:
		if str(app) in APPS: _show_app(str(app))
	for app in running_apps:
		windows[app].visible=app in opened
		windows[app].set_active(false)
	current_app=""
	var active:=str(saved.get("active_app","mail"))
	if active in running_apps and windows[active].visible: _focus(active)
	else:
		for app in focus_order:
			if app in running_apps and windows[app].visible: _focus(app); break
	for app in task_buttons: _layout_task_button(app)

func _load_session() -> void:
	preload("res://scripts/profile_paths.gd").migrate(game.state)
	session_key = game._vm_key()
	var saved: Dictionary = game.state.get("desktop_sessions",{}).get(session_key,{})
	file_remote = bool(saved.get("file_remote",true))
	terminal_log = str(saved.get("log","")); drafts = saved.get("drafts",{}).duplicate(true); history = saved.get("history",[]).duplicate(); history_index = history.size(); file_directory = str(saved.get("directory","/")); file_remote = bool(saved.get("file_remote",true)); file_history = saved.get("file_history",[]).duplicate(true); file_forward_history = saved.get("file_forward_history",[]).duplicate(true); editor_path = str(saved.get("editor_path","")); browser_url = str(saved.get("url","")); browser_history = saved.get("browser_history",[]).duplicate(); browser_history_index = clampi(int(saved.get("browser_history_index", browser_history.size()-1)), -1, browser_history.size()-1)
	browser_response = str(saved.get("browser_response", ""))
	browser_identity = str(saved.get("browser_identity", ""))
	identity_ui = saved.get("identity_ui", {}).duplicate(true) if saved.get("identity_ui", {}) is Dictionary else {}
	edr_ui = saved.get("edr_ui", {}).duplicate(true) if saved.get("edr_ui", {}) is Dictionary else {}
	portal_ui = saved.get("portal_ui", {}).duplicate(true) if saved.get("portal_ui", {}) is Dictionary else {}
	firewall_ui = saved.get("firewall_ui", {}).duplicate(true) if saved.get("firewall_ui", {}) is Dictionary else {}
	backup_ui = saved.get("backup_ui", {}).duplicate(true) if saved.get("backup_ui", {}) is Dictionary else {}
	samba_ui = saved.get("samba_ui", {}).duplicate(true) if saved.get("samba_ui", {}) is Dictionary else {}
	business_ui = saved.get("business_ui", {}).duplicate(true) if saved.get("business_ui", {}) is Dictionary else {}
	billing_ui = saved.get("billing_ui", {}).duplicate(true) if saved.get("billing_ui", {}) is Dictionary else {}
	advanced_ui = saved.get("advanced_ui", {}).duplicate(true) if saved.get("advanced_ui", {}) is Dictionary else {}
	pentest_ui = saved.get("pentest_ui", {}).duplicate(true) if saved.get("pentest_ui", {}) is Dictionary else {}
	diagnostic_ui = saved.get("diagnostic_ui", {}).duplicate(true) if saved.get("diagnostic_ui", {}) is Dictionary else {}
	monitor_ui = saved.get("monitor_ui", {}).duplicate(true) if saved.get("monitor_ui", {}) is Dictionary else {}
	mail_ui = saved.get("mail_ui", {}).duplicate(true) if saved.get("mail_ui", {}) is Dictionary else {}
	if not browser_identities().any(func(identity): return str(identity.get("id", "")) == browser_identity): browser_identity = ""
	if not game.state.has("os_files"):
		var workstation_readme := "業務PCの使い方\n\nメールで受注、ターミナルの ssh client で接続。\n顧客ファイルを編集・保存し、サービスを再起動します。\n検証結果を確認して納品・精算から報告。\n\nAlt+Tab: アプリ切替\nCtrl+S: 保存\nCtrl+L: アドレス欄\nタイトルバーをダブルクリック: 最大化\n右下のハンドル: サイズ変更\n"
		game.state.os_files = {"/home/operator/Documents/作業メモ.txt":"","/home/operator/Documents/README.txt":workstation_readme}
func _state_changed() -> void:
	if not is_instance_valid(tray) or switching_target or refreshing: return
	refreshing = true
	set_deferred("refreshing",false)
	var work: Dictionary = game.work_status() if game.has_method("work_status") else {}
	if game.state.accepted and not game.current_done():
		var clock: String = str(game.business_clock()) if game.has_method("business_clock") else "--:--"
		var deadline: String = str(work.get("deadline_text", "--:--"))
		tray.text = "%s\nDAY %02d" % [clock,int(game.state.get("day",1))]
		tray.tooltip_text = "DAY %02d  %s  ·  納期 %s" % [int(game.state.get("day",1)),clock,deadline]
	else:
		var clock_idle: String = str(game.business_clock()) if game.has_method("business_clock") else "--:--"
		tray.text = "%s\nDAY %02d" % [clock_idle,int(game.state.get("day",1))]
		tray.tooltip_text = _company_name()
	var info: Dictionary = game.vm_info()
	status.text = ("● " + str(info.host).get_slice(".",0)) if info.connected else "○ このPC"
	if is_instance_valid(system_target):
		system_target.text = str(game.mission().client) if bool(game.state.get("career_mode", false)) and bool(game.state.get("accepted", false)) else (("▣ " + str(info.host).get_slice(".",0)) if info.connected else "▣ このPC")
		system_target.clip_text = true; system_target.tooltip_text = str(game.mission().title) + "\n" + UI.copy("queue_scope") % str(game.state.get("current_contract_id", ""))
	status.tooltip_text = str(info.host)+" / 接続中" if info.connected else "顧客端末には未接続です"
	if widgets.has("terminal"): SHELL.refresh(self)
	if widgets.has("editor"): EDITOR.refresh(self)
	if widgets.has("team") and widgets.team.has("body"): _refresh_team()
	if widgets.has("verify"): _refresh_checks()
	if widgets.has("mail"): BUSINESS.refresh_mail_status(self)
	if widgets.has("billing"): call_deferred("_refresh_billing_if_changed")
	if widgets.has("advanced"): call_deferred("_refresh_advanced")
	if _business_workspace_url(browser_url): call_deferred("_refresh_business_if_changed")
	if _hotel_url(browser_url) and JSON.stringify(game.hotel_snapshot()) != hotel_render_signature: _render_hotel_frontdesk()
	if is_instance_valid(brand_label): brand_label.text = _company_name()
	if is_instance_valid(system_company): system_company.text=_company_name(); system_company.tooltip_text=_company_name()
	if is_instance_valid(player_name_label): player_name_label.text = _player_display_name()
	if _edr_console_url(browser_url):
		var edr_signature := _edr_snapshot_signature()
		if edr_signature != edr_render_signature: _render_endpoint()
	if _identity_console_url(browser_url) and game.current_done() and widgets.has("browser"):
		var identity_page: VBoxContainer = widgets.browser.page
		if identity_page.get_node_or_null("CompletedCaseCanvas") == null: _refresh_completed_browser()
	if _portal_page_url(browser_url):
		var portal_signature := _portal_snapshot_signature()
		if portal_signature != portal_render_signature: _render_portal()
	if _firewall_console_url(browser_url):
		var firewall_signature := _firewall_snapshot_signature()
		if firewall_signature != firewall_render_signature: _render_firewall()
	if _backup_console_url(browser_url):
		var backup_signature := _backup_snapshot_signature()
		if backup_signature != backup_render_signature: _render_backup()
	if _samba_v2():
		_invalidate_smb()
		if _samba_console_url(browser_url) and _samba_signature()!=samba_render_signature: _render_samba()
	refreshing = false

func _is_wide_layout() -> bool:
	var logical_width: float = size.x if size.x > 1.0 else get_viewport_rect().size.x
	return logical_width >= 1100.0

func _process(delta: float) -> void:
	_save_timer += delta
	if _save_timer > 10: _save_timer = 0; _save_session()
func _notify(text: String) -> void:
	if not is_instance_valid(status): return
	notice_serial += 1
	var serial := notice_serial
	var failed := "失敗" in text or "できません" in text or "エラー" in text or "読み込め" in text
	status.text = text
	status.tooltip_text = text
	status.add_theme_color_override("font_color",UI.RED if failed else UI.INK)
	status.custom_minimum_size.x = 148.0
	status.show()
	_layout_taskbar()
	if failed: _trace("error",text.left(240)); return
	get_tree().create_timer(3).timeout.connect(func():
		if is_instance_valid(status) and serial == notice_serial: status.hide(); status.remove_theme_color_override("font_color"); _layout_taskbar())

func _money(value) -> String:
	var n := str(absi(int(value))); var out := ""
	for i in n.length(): out += ("," if i>0 and (n.length()-i)%3==0 else "") + n[i]
	return ("−" if int(value)<0 else "") + out
func _close() -> void:
	_trace("leave_desktop",current_app)
	if _save_session(): close_requested.emit()

func configure_return(label: String) -> void:
	configured_return_label=label.strip_edges()
	if is_instance_valid(taskbar): _layout_taskbar()

func _return_to_source() -> void:
	if configured_return_label.is_empty(): return
	_trace("return_to_source",current_app)
	if _save_session(): return_requested.emit()
func _company() -> void:
	if _save_session(): company_requested.emit()

func _staffing() -> void:
	if _save_session(): staffing_requested.emit()
func _contracts() -> void:
	if _save_session(): contracts_requested.emit()
func _sales() -> void:
	if _save_session(): sales_requested.emit()
func _next_task() -> void:
	if _save_session(): next_task_requested.emit()
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var start: Button=find_child("StartButton",true,false)
		if start_menu.visible and not start_menu.get_global_rect().has_point(event.position) and (start==null or not start.get_global_rect().has_point(event.position)): start_menu.hide()
		if overview.visible and not overview.get_global_rect().has_point(event.position): overview.hide()
	if not event is InputEventKey: return
	if not event.pressed:
		if event.keycode == KEY_ALT: alt_tab_order.clear()
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if current_app == "editor" and widgets.has("editor") and widgets.editor.get("find_panel") != null and widgets.editor.find_panel.visible: EDITOR.hide_find(self)
		elif is_instance_valid(overview) and overview.visible: overview.hide()
		elif is_instance_valid(start_menu) and start_menu.visible: start_menu.hide()
		elif current_app == "advanced" and bool(widgets.get("advanced", {}).get("pentest", false)) and str(pentest_ui.get("tab", "portal")) != "portal":
			pentest_ui.tab = "portal"; widgets.advanced.signature = ""; _refresh_advanced(); _save_session(false)
		else: _close()
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if (focus_owner is TextEdit or focus_owner is LineEdit) and not event.ctrl_pressed and not event.alt_pressed and event.unicode > 0: get_node("/root/Soundscape").play_ui("typing")
	if event.alt_pressed and event.keycode == KEY_TAB:
		if alt_tab_order.is_empty():
			for id in focus_order:
				if id in running_apps and windows.has(id): alt_tab_order.append(id)
			for id in running_apps:
				if not alt_tab_order.has(id): alt_tab_order.append(id)
		if not alt_tab_order.is_empty():
			var current_index := alt_tab_order.find(current_app)
			var direction:= -1 if event.shift_pressed else 1
			var next: String = str(alt_tab_order[posmod(current_index+direction,alt_tab_order.size())])
			_show_app(next)
		get_viewport().set_input_as_handled()
	elif event.alt_pressed and event.keycode==KEY_F4 and not current_app.is_empty(): _dismissed(current_app); get_viewport().set_input_as_handled()
	elif event.keycode==KEY_META: start_menu.visible=not start_menu.visible; get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_S and current_app == "editor": _save_editor(); get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode in [KEY_F,KEY_H] and current_app == "editor": EDITOR.show_find(self,event.keycode==KEY_H); get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F3 and current_app == "editor": EDITOR.show_find(self,widgets.editor.replace_row.visible); EDITOR.find_next(self,event.shift_pressed); get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_L:
		if current_app == "browser": widgets.browser.url.grab_focus(); widgets.browser.url.select_all()
		elif current_app == "files": FILES._edit_address(self)
		if current_app in ["browser","files"]: get_viewport().set_input_as_handled()

func _mail(parent: VBoxContainer) -> void:
	BUSINESS.build_mail(self,parent)
func _refresh_mail() -> void:
	BUSINESS.refresh_mail(self)
func _team(parent: VBoxContainer) -> void:
	BUSINESS.build_team(self,parent)
func _refresh_team() -> void:
	BUSINESS.refresh_team(self)
func _receipt(parent: VBoxContainer) -> void:
	BUSINESS.build_receipt(self,parent)
func _refresh_receipt() -> void:
	BUSINESS.refresh_receipt(self)
func _refresh_advanced() -> void:
	if widgets.has("advanced"): ADVANCED_WORKSPACE.refresh(self)
func _accept() -> void:
	if game.accept_mission():
		session_key = game._vm_key(); _refresh_mail(); _open_accepted_service(); _notify("受注済み")

func _open_accepted_service() -> void:
	# Acceptance locates the service; connecting and measuring remain player actions.
	if game.advanced_active():
		_show_app("advanced")
		return
	var url := SAMBA_URL if _samba_v2() else BACKUP_URL if _backup_v2() else FIREWALL_URL if _firewall_v2() else IDENTITY_URL if _identity_v2() else EDR_URL if _edr_v2() else PORTAL_URL if _portal_v2() else ""
	if not url.is_empty(): show_guide_service(url)
	else: _show_app("terminal")
func _report() -> void:
	if game.deliver():
		_show_app("receipt"); _notify("納品完了")
		if widgets.has("mail"): _refresh_mail()
	else:
		_notify("納品を完了できませんでした。保存先を確認して再試行してください。" if game.can_deliver() else "納品条件が未達成です。検証結果を確認してください。")
func _refresh_target_selector() -> void:
	if not is_instance_valid(target_selector): return
	target_selector.clear()
	for target in game.state.get("targets", []): target_selector.add_item(str(target.get("name", "")))
	target_selector.visible = target_selector.item_count > 1
	var target_slot: Node = null
	if is_instance_valid(taskbar): target_slot = taskbar.find_child("TargetSelectorSlot", true, false)
	if target_slot != null: target_slot.visible = target_selector.visible
	if target_selector.item_count > 0: target_selector.select(int(game.state.get("target_index", 0)))
	target_selector.tooltip_text=target_selector.get_item_text(target_selector.selected) if target_selector.selected >= 0 else ""

func _reload_contract_session() -> void:
	for w in windows.values():
		workspace.remove_child(w); w.queue_free()
	windows.clear(); widgets.clear(); running_apps.clear(); desktop_hidden_windows.clear(); current_app = ""; editor = null; output = null; command = null
	focus_order.clear(); alt_tab_order.clear(); clipboard_path = ""
	_app_keyboard_focus.clear()
	_load_session(); _refresh_target_selector(); switching_target = false
	var saved: Dictionary = game.state.get("desktop_sessions", {}).get(session_key, {})
	_restore_session_windows(saved)
	_state_changed()

func _switch_contract(id: String) -> bool:
	if switching_target: return false
	if id == str(game.state.get("current_contract_id", "")): return true
	if not _save_session(): return false
	switching_target = true
	if not game.switch_contract(id):
		switching_target = false; _notify(UI.copy("queue_save_failed")); return false
	_reload_contract_session()
	return true

func _select_target(index: int) -> bool:
	if switching_target: return false
	if index == int(game.state.get("target_index", 0)): return true
	_trace("select_target", str(index))
	if not _save_session(): _refresh_target_selector(); return false
	switching_target = true
	if not game.select_target(index):
		switching_target = false; _refresh_target_selector(); _notify(UI.copy("queue_save_failed")); return false
	_reload_contract_session()
	return true

func _open_colleague_result(member_id: String, path: String) -> void:
	var job: Dictionary = game.state.get("assignments", {}).get(member_id, {}).duplicate(true)
	var contract_id := str(job.get("contract_id", ""))
	if not contract_id.is_empty() and contract_id != str(game.state.get("current_contract_id", "")):
		if not _switch_contract(contract_id): return
	var target_index := int(job.get("target_index", game.state.get("target_index", 0)))
	if not _select_target(target_index): return
	_open_editor(path)

func _terminal(parent: VBoxContainer) -> void:
	SHELL.build(self,parent)
func _append(text: String) -> void:
	terminal_log += ("\n\n" if not terminal_log.is_empty() else "") + text
	if terminal_log.length()>45000: terminal_log = terminal_log.right(40000)
	if widgets.has("terminal"): widgets.terminal.output.text = terminal_log
	_save_session(false)
func _run_command(text: String) -> void:
	_trace("command",text.strip_edges().get_slice(" ",0))
	var input := text.strip_edges()
	if input.is_empty(): return
	if not windows.has("terminal"): _show_app("terminal")
	var display_command: String = load("res://scripts/virtual_machine.gd").new()._identity_redact_command(input)
	history.append(display_command)
	if history.size()>100: history.pop_front()
	history_index = history.size()
	if input == "clear": terminal_log = ""; widgets.terminal.output.text = ""
	elif input.begins_with("edit ") or input.begins_with("nano "): _open_editor(input.substr(input.find(" ")+1).strip_edges())
	else:
		var response: String = game.vm_run(input)
		if input.begins_with("ssh ") and response.contains("hardware_unavailable"):
			response = "SSH: 機材が設定台に接続されていません。上の「準備台」から機材を接続してください。"
		_append("$ "+display_command+"\n"+response)
	widgets.terminal.command.clear(); _state_changed(); _save_session(false)
	if current_app == "terminal": widgets.terminal.command.grab_focus()
	if widgets.has("monitor"): _refresh_monitor()
	if widgets.has("verify"): _refresh_checks()
func _terminal_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	var input: LineEdit = widgets.terminal.command
	if event.keycode == KEY_UP and not history.is_empty():
		history_index = maxi(0,history_index-1); input.text = history[history_index]; input.caret_column = input.text.length(); input.accept_event()
	elif event.keycode == KEY_DOWN:
		history_index = mini(history.size(),history_index+1); input.text = "" if history_index==history.size() else history[history_index]; input.caret_column = input.text.length(); input.accept_event()
	elif event.keycode == KEY_TAB:
		var choices := ["ssh client","systemctl status "+str(game.vm_info().service),"systemctl restart "+str(game.vm_info().service),"cat "+str(game.vm_info().config_path),"edit "+str(game.vm_info().config_path),"journalctl","restic snapshots","restic backup /srv/data","restic restore latest --target /restore"]
		for choice in choices:
			if choice.begins_with(input.text): input.text = choice; input.caret_column = input.text.length(); break
		input.accept_event()
	elif event.ctrl_pressed and event.keycode == KEY_L: _run_command("clear"); input.accept_event()

func _files(parent: VBoxContainer) -> void:
	FILES.build(self,parent)
	if widgets.has("files"):
		widgets.files.history = file_history.duplicate(true)
		widgets.files.forward_history = file_forward_history.duplicate(true)
		FILES.refresh(self)
func _file_location(remote: bool, path: String) -> void:
	FILES.navigate(self, path, remote)
func _list_files() -> void:
	FILES.refresh(self)
func _parent_directory() -> void:
	if bool(samba_ui.get("network_open",false)): return
	var parent := file_directory.trim_suffix("/").get_base_dir()
	FILES.navigate(self, "/" if parent.is_empty() else parent, file_remote)
func _open_file_item(_index: int = -1) -> void:
	var selected: TreeItem = widgets.files.list.get_selected()
	if selected == null: return
	var path: String = selected.get_metadata(0)
	if path.ends_with("/"): widgets.files.path.text = path.trim_suffix("/"); _list_files()
	else: _open_editor(path)
func _paste_file() -> void:
	if bool(samba_ui.get("network_open",false)): return
	if clipboard_path.is_empty() or clipboard_path.ends_with("/"): return
	var source_is_local := clipboard_path.begins_with("workstation:")
	var source_path := clipboard_path.trim_prefix("workstation:") if source_is_local else clipboard_path
	if source_is_local and not game.state.os_files.has(source_path):
		_notify(UI.copy("save_failed")); return
	var existing_paths: Array = game.vm_list(file_directory) if file_remote else game.state.os_files.keys()
	var target := FILES._copy_target(file_directory, source_path, existing_paths)
	if file_remote:
		if source_is_local:
			var info: Dictionary = game.vm_info()
			var local_contents: String = str(game.state.os_files[source_path])
			if not game.vm_write(target, local_contents):
				_notify("顧客端末: 未接続" if not bool(info.get("connected",false)) else UI.copy("save_failed")); return
			_list_files()
			return
		var output: String = game.vm_run('cp "%s" "%s"' % [source_path,target])
		if not output.is_empty():
			var result_json := JSON.new()
			if result_json.parse(output) == OK and result_json.data is Dictionary and str(result_json.data.get("error", "")) == "save_failed":
				_notify(UI.copy("save_failed"))
			else:
				_notify(output)
		_list_files()
		return
	if not source_is_local:
		var info: Dictionary = game.vm_info()
		if not bool(info.get("connected",false)):
			_notify("顧客端末: 未接続"); return
		if not game.vm_list(source_path.get_base_dir()).has(source_path):
			_notify(UI.copy("save_failed")); return
	var contents: String = str(game.state.os_files[source_path]) if source_is_local else game.vm_read(source_path)
	if game.state.os_files.has(target):
		target = FILES._copy_target(file_directory, source_path, game.state.os_files.keys())
	var had_previous: bool = game.state.os_files.has(target)
	var previous_content: String = str(game.state.os_files.get(target,""))
	game.state.os_files[target] = contents
	if not game.save_game():
		if had_previous: game.state.os_files[target]=previous_content
		else: game.state.os_files.erase(target)
		_notify(UI.copy("save_failed")); return
	_list_files()

func _editor(parent: VBoxContainer) -> void:
	EDITOR.build(self,parent)
func _read(path: String) -> String:
	path = _resolved_editor_path(path)
	return str(game.state.os_files.get(path.trim_prefix("workstation:"),"")) if path.begins_with("workstation:") else game.vm_read(path)
func _resolved_editor_path(path: String) -> String:
	if path.is_empty(): return path
	if path.begins_with("workstation:"):
		if game.state.get("os_files",{}).has(path.trim_prefix("workstation:")): return path
		return preload("res://scripts/profile_paths.gd").home(path)
	return game._vm()._path(path)
func _open_editor(path: String) -> void:
	path = _resolved_editor_path(path)
	_trace("open_file",path)
	if path == editor_path and widgets.has("editor") and is_instance_valid(widgets.editor.get("editor")):
		windows.editor.show(); _focus("editor"); EDITOR.refresh(self); return
	_remember_editor()
	if "editor" not in running_apps: _show_app("editor")
	editor_path = path
	widgets.editor.path.text = path; widgets.editor.editor.text = str(drafts.get(path,_read(path))); windows.editor.show(); _focus("editor")
	EDITOR.refresh(self)
func _open_config() -> void:
	var info: Dictionary = game.vm_info()
	if not info.connected: _notify("顧客端末: 未接続"); return
	_open_editor(info.config_path)
func _new_file() -> void:
	_open_editor("workstation:/home/operator/Documents/メモ-%d.txt" % (game.state.os_files.size()+1))
func _load_editor() -> void:
	_open_editor(widgets.editor.path.text.strip_edges())
func _save_editor() -> void:
	if not widgets.has("editor") or not is_instance_valid(widgets.editor.get("editor")): return
	_trace("save_file",editor_path)
	var w: Dictionary = widgets.editor; var path: String = _resolved_editor_path(w.path.text.strip_edges()); var ok := false
	w.path.text = path
	var previous_files: Dictionary = game.state.get("os_files",{}).duplicate(true)
	drafts[path] = w.editor.text
	w.save_result_path = path; w.save_error = ""; w.save_result = ""; w.save_pending = false
	if path.begins_with("workstation:") and not path.get_file().is_empty(): game.state.os_files[path.trim_prefix("workstation:")] = w.editor.text; ok = true
	else: ok = game.vm_write(path,w.editor.text)
	if ok:
		editor_path = path; drafts[path] = w.editor.text; w.info.text = "✓ 保存済み   UTF-8   /   "+path; _save_session(false)
		if game.save_game():
			w.save_result = "保存しました: "+path.get_file(); _notify(w.save_result)
		else:
			if path.begins_with("workstation:"): game.state.os_files = previous_files
			w.save_pending = true
			w.save_error = "作業状態を保存できませんでした。下書きを保持しています。再試行してください。"
			_notify(w.save_error)
	else:
		w.save_pending = true; w.save_error = "ファイルを保存できませんでした。接続・権限・保存先を確認して再試行してください。下書きは保持されています。"
		_notify(w.save_error)
	EDITOR.refresh(self)
	if widgets.has("monitor"): _refresh_monitor()
	if widgets.has("verify"): _refresh_checks()

func _browser(parent: VBoxContainer) -> void:
	if _samba_v2() and browser_url.is_empty(): browser_url = SAMBA_URL
	if _backup_v2() and browser_url.is_empty(): browser_url = BACKUP_URL
	if _identity_v2() and browser_url.is_empty(): browser_url = IDENTITY_URL
	if _edr_v2() and browser_url.is_empty(): browser_url = EDR_URL
	if _portal_v2() and browser_url.is_empty(): browser_url = PORTAL_URL
	if _firewall_v2() and browser_url.is_empty(): browser_url = FIREWALL_URL
	var p := _pad(parent,0); p.add_theme_constant_override("separation",0)
	var chrome := _pad(p,6); chrome.size_flags_vertical=Control.SIZE_FILL
	chrome.get_parent().size_flags_vertical=Control.SIZE_FILL
	var row := _row(chrome)
	var browser_back := _tool_button("back",UI.copy("fidelity_back"),_browser_back); row.add_child(browser_back)
	var browser_forward := _tool_button("forward",UI.copy("fidelity_forward"),_browser_forward); row.add_child(browser_forward)
	row.add_child(_tool_button("refresh",UI.copy("fidelity_reload"),_browse))
	var history_menu := MenuButton.new(); history_menu.icon=UI.symbol("more"); history_menu.tooltip_text=UI.copy("fidelity_history"); history_menu.custom_minimum_size=Vector2(34,32); history_menu.add_theme_constant_override("icon_max_width",18)
	history_menu.get_popup().about_to_popup.connect(func():
		var popup := history_menu.get_popup(); popup.clear()
		for i in range(browser_history.size()-1, maxi(-1,browser_history.size()-21), -1):
			popup.add_item(str(browser_history[i]), i)
		if browser_history.is_empty(): popup.add_item("履歴はありません", -1); popup.set_item_disabled(0, true)
	)
	history_menu.get_popup().id_pressed.connect(func(index):
		if index >= 0 and index < browser_history.size():
			browser_history_index = index; _browse_url(str(browser_history[index]), false)
	)
	var url := LineEdit.new(); url.name="BrowserAddress"; url.size_flags_horizontal = Control.SIZE_EXPAND_FILL; url.text = browser_url; url.placeholder_text = "https://intranet.client.test"; url.text_submitted.connect(func(_v): _browse()); row.add_child(url); row.add_child(history_menu)
	url.custom_minimum_size.y=32
	url.add_theme_stylebox_override("normal",UI.style(Color("edf1f7"),Color.TRANSPARENT,14,5,16)); url.add_theme_stylebox_override("focus",UI.style(Color.WHITE,Color("0067c0"),14,5,16))
	var location := _label("",12,MUTED); location.autowrap_mode=TextServer.AUTOWRAP_OFF; location.clip_text=true; location.hide(); p.add_child(location)
	var bookmarks := HFlowContainer.new(); bookmarks.add_theme_constant_override("h_separation",4); p.add_child(bookmarks)
	if _identity_v2() or _edr_v2() or _portal_v2() or _firewall_v2() or _backup_v2() or _samba_v2(): location.hide(); bookmarks.hide()
	var sets := [
		[["社内共有","https://files.client.test/staff/report.txt"],["ゲスト共有","https://files.client.test/guest/report.txt"]],
		[["社内ポータル","https://intranet.client.test"]],
		[["社内ポータル","https://intranet.client.test"],["管理画面の外部公開","https://admin.client.test"]],
		[["在籍者ログイン","https://identity.client.test/current/login"],["退職者のログイン権限","https://identity.client.test/former/login"],["既存セッション","https://identity.client.test/former/session"]],
		[["PC-A 接続","https://edr.client.test/pc-a/outbound"],["PC-B 業務","https://edr.client.test/pc-b/business"]],
		[["スタッフ","https://portal.client.test/staff"],["取引先","https://portal.client.test/partner"],["公開リンク","https://portal.client.test/public"]]]
	if _identity_v2(): sets[3] = [[UI.copy("identity_title", "Identity management"), IDENTITY_URL]]
	if _edr_v2(): sets[4].append([UI.copy("edr_title", "Endpoint security"), EDR_URL])
	if _hotel_enabled():
		sets[4] = [["端末の調査", EDR_URL], ["白波フロント", HOTEL_URL]]
		bookmarks.show()
	if _firewall_v2():
		sets[2] = [[UI.copy("fw_title"),FIREWALL_URL],[UI.copy("business_sales"),"https://intranet.client.test/sales"],[UI.copy("business_accounting"),"https://intranet.client.test/accounting"],[sets[2][1][0],"https://admin.client.test:8443"]]
		bookmarks.show()
	for pair in sets[game._current_chapter()]:
		var b:=_button(pair[0],func(): url.text = pair[1]; _browse()); b.flat=true; bookmarks.add_child(b)
	var access_account: OptionButton
	var access_link: OptionButton
	if game._current_chapter() == 5 and int(game._vm().state.get("access_model_version",1)) >= 2 and not _portal_v2():
		var access := HFlowContainer.new(); access.add_theme_constant_override("h_separation",8); access.add_theme_constant_override("v_separation",4); p.add_child(access)
		var account_label := _label("テストアカウント",12,MUTED); account_label.autowrap_mode=TextServer.AUTOWRAP_OFF; account_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER; access.add_child(account_label)
		access_account = OptionButton.new(); access_account.custom_minimum_size=Vector2(230,32)
		access_account.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		for identity in BROWSER_IDENTITIES:
			access_account.add_item(identity.label)
			if identity.id == browser_identity: access_account.select(access_account.item_count-1)
		access.add_child(access_account)
		access_account.item_selected.connect(func(index):
			browser_identity = str(BROWSER_IDENTITIES[index].id)
			if not browser_url.is_empty(): _browse_url(browser_url,false)
			else: _save_session(false)
		)
		var link_label := _label("共有リンク",12,MUTED); link_label.autowrap_mode=TextServer.AUTOWRAP_OFF; link_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER; access.add_child(link_label)
		access_link = OptionButton.new(); access_link.custom_minimum_size=Vector2(155,32)
		access_link.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		for label in ["今日発行","8日前に発行","31日前に発行"]: access_link.add_item(label)
		access.add_child(access_link)
		access_link.item_selected.connect(func(index):
			var base := browser_url.get_slice("?",0) if browser_url.begins_with("https://portal.client.test/") or browser_url.begins_with("http://portal.client.test/") else "https://portal.client.test/partner"
			_browse_url(base+"?link="+str(["current","week-old","month-old"][index]),true)
		)
	var page := _scroll(p); widgets.browser = {"url":url,"page":page,"back":browser_back,"forward":browser_forward,"location":location}; url_edit = url
	page.add_theme_constant_override("separation",0)
	if access_account != null: widgets.browser.account = access_account; widgets.browser.link = access_link
	browser_back.disabled = browser_history_index <= 0
	browser_forward.disabled = browser_history_index < 0 or browser_history_index >= browser_history.size()-1
	_update_browser_title()
	location.text = "顧客サイト  /  "+browser_url.trim_prefix("https://").trim_prefix("http://") if not browser_url.is_empty() else "顧客サイト / URL"
	if _identity_console_url(browser_url): _render_identity()
	elif _edr_console_url(browser_url): _render_endpoint()
	elif _hotel_url(browser_url): _render_hotel_frontdesk()
	elif _portal_page_url(browser_url): _render_portal()
	elif _firewall_console_url(browser_url): _render_firewall()
	elif _backup_console_url(browser_url): _render_backup()
	elif _samba_console_url(browser_url): _render_samba()
	elif _business_workspace_url(browser_url): _render_business_workspace()
	elif not browser_url.is_empty() and not browser_response.is_empty(): BROWSER_PAGE.render(self, page, browser_url, browser_response)
func _update_browser_title() -> void:
	if not windows.has("browser"): return
	var host: String=browser_url.trim_prefix("https://").trim_prefix("http://").get_slice("/",0)
	var title: String={"identity.client.test":"Keycloak", "portal.client.test":"Nextcloud", "gateway.client.test":"pfSense", "edr.client.test":"Microsoft Defender", "frontdesk.client.test":"白波フロント", "backup.client.test:9898":"Backrest", "files01.client.test:9090":"Cockpit"}.get(host,host)
	windows.browser.title_text=title if not title.is_empty() else APPS.browser[0]
	windows.browser.set_active(current_app=="browser")

func _browse() -> void:
	_browse_url(widgets.browser.url.text.strip_edges(), true)

func show_guide_service(url: String) -> void:
	# Show an existing management surface without issuing curl/console commands,
	# recording observations or charging work time just to locate a control.
	var renderers := {SAMBA_URL:_render_samba, BACKUP_URL:_render_backup, FIREWALL_URL:_render_firewall, IDENTITY_URL:_render_identity, EDR_URL:_render_endpoint, HOTEL_URL:_render_hotel_frontdesk, PORTAL_URL:_render_portal}
	if not renderers.has(url): return
	if windows.has("browser") and browser_url == url:
		_show_app("browser"); return
	var existed := windows.has("browser")
	browser_url = url
	_show_app("browser")
	widgets.browser.url.text = url
	_update_browser_title()
	if existed: renderers[url].call()
	_save_session(false)

func _browse_url(value: String, record_history := true) -> void:
	if not value.begins_with("https://") and not value.begins_with("http://"): _notify("URL形式エラー · http:// または https://"); return
	browser_url = value
	_update_browser_title()
	if is_instance_valid(widgets.browser.get("url")): widgets.browser.url.text = browser_url
	if record_history:
		if browser_history_index >= 0 and browser_history_index < browser_history.size()-1: browser_history = browser_history.slice(0,browser_history_index+1)
		if browser_history.is_empty() or str(browser_history.back()) != browser_url: browser_history.append(browser_url)
		browser_history_index = browser_history.size()-1
	var authority := browser_url.trim_prefix("https://").trim_prefix("http://").get_slice("/",0).get_slice("?",0).to_lower()
	var command := "curl "
	if authority == "portal.client.test" and not browser_identity.is_empty(): command += "-H \"Authorization: Bearer "+browser_identity+"\" "
	var request_url := _business_request_url(browser_url) if _business_workspace_url(browser_url) else browser_url
	command += '"'+request_url.replace('"','%22')+'"'
	var result: String
	if _hotel_url(browser_url):
		# Opening the front-desk workspace reads saved work; only Send transacts.
		result = ""
	elif _business_workspace_url(browser_url):
		result = str(game.business_read(request_url.get_slice("/api/business/",1),browser_url).get("response",""))
	else:
		result = "" if _samba_console_url(browser_url) else game.vm_run("restic snapshots") if _backup_console_url(browser_url) else JSON.stringify(game._vm().firewall_snapshot()) if _firewall_console_url(browser_url) else game.vm_run("identity users" if _identity_console_url(browser_url) else ("edr devices" if _edr_console_url(browser_url) else ("portal files" if _portal_console_url(browser_url) else command)))
	browser_response = result
	if _portal_console_url(browser_url):portal_ui["view"]="files"
	if _portal_page_url(browser_url) and not _portal_console_url(browser_url):
		_portal_stash_draft()
		portal_ui["view"]="preview";portal_ui["role"]=browser_url.get_slice("://",1).get_slice("/",1).get_slice("?",0)
		portal_ui["age"]="month-old" if "link=month-old" in browser_url else ("week-old" if "link=week-old" in browser_url else "current")
		_portal_restore_draft()
		portal_ui["response_method"]="GET"
		_set_portal_response(result)
	var page: VBoxContainer = widgets.browser.page; _clear(page)
	if _identity_console_url(browser_url): _render_identity()
	elif _edr_console_url(browser_url): _render_endpoint()
	elif _hotel_url(browser_url): _render_hotel_frontdesk()
	elif _portal_page_url(browser_url): _render_portal()
	elif _firewall_console_url(browser_url): _render_firewall()
	elif _backup_console_url(browser_url): _render_backup()
	elif _samba_console_url(browser_url): _render_samba()
	elif _business_workspace_url(browser_url): _render_business_workspace()
	else: BROWSER_PAGE.render(self,page,browser_url,result)
	if widgets.browser.has("back"):
		widgets.browser.back.disabled = browser_history_index <= 0
		widgets.browser.forward.disabled = browser_history_index < 0 or browser_history_index >= browser_history.size()-1
		widgets.browser.location.text = "顧客サイト  /  "+browser_url.trim_prefix("https://").trim_prefix("http://")
	if widgets.browser.has("link"):
		var link_index := 2 if "link=month-old" in browser_url else (1 if "link=week-old" in browser_url else 0)
		widgets.browser.link.select(link_index)
	_save_session(false)

func _business_workspace_url(value: String) -> bool:
	if not _firewall_v2(): return false
	var address := value.get_slice("://",1).get_slice("?",0).get_slice("#",0)
	var authority := address.get_slice("/",0).to_lower()
	var path := address.substr(authority.length()).trim_suffix("/")
	return authority in ["intranet.client.test","intranet.client.test:443","intranet.client.test:80"] and path in ["","/sales","/accounting","/customers"]

func _business_request_url(value: String) -> String:
	var address := value.get_slice("://",1).get_slice("?",0).get_slice("#",0)
	var authority := address.get_slice("/",0)
	var path := address.substr(authority.length()).trim_suffix("/")
	var origin := value.get_slice("://",0)+"://"+authority
	return origin+"/api/business/"+("ledger" if path == "/accounting" else ("customers" if path == "/customers" else "orders"))

func _refresh_business_if_changed() -> void:
	if not _business_workspace_url(browser_url) or not game.has_method("business_read"): return
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var resource: String = _business_request_url(browser_url).get_slice("/api/business/",1)
	var result: Dictionary = game.business_read(resource,browser_url)
	var response: String = str(result.get("response",browser_response))
	if response != browser_response:
		browser_response = response
		_render_business_workspace()

func _render_business_workspace() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var page: VBoxContainer = widgets.browser.page
	_clear(page)
	BUSINESS_WORKSPACE.render(self,page,browser_url,browser_response)

func _network_request_test() -> Dictionary:
	var was_refreshing := refreshing
	refreshing = true
	var result: Dictionary = game.network_request_test(browser_url)
	refreshing = was_refreshing
	business_ui.network_error = "" if bool(result.get("ok",false)) else ("検査結果を保存できませんでした。前の観測を保持しています。" if str(result.get("error",""))=="save_failed" else "検査できません。顧客への接続と案件の状態を確認してください。")
	if bool(result.get("ok",false)):
		var resource: String = _business_request_url(browser_url).get_slice("/api/business/",1)
		browser_response = str(game.business_read(resource,browser_url).get("response",browser_response))
		_save_session(false)
	_render_business_workspace()
	if widgets.has("verify"): _refresh_checks()
	var focus: Control = widgets.browser.page.find_child("NetworkRequestTest",true,false)
	if is_instance_valid(focus): focus.grab_focus.call_deferred()
	return result

func _network_request_settings() -> void:
	business_ui.network_return_url = browser_url
	business_ui.network_error = ""
	firewall_ui.view = "services"
	_save_session(false)
	_browse_url(FIREWALL_URL,true)
	var focus: Control = widgets.browser.page.find_child("FirewallDNS",true,false)
	if is_instance_valid(focus): focus.grab_focus.call_deferred()

func _network_request_return() -> void:
	var url := str(business_ui.get("network_return_url",""))
	if preload("res://scripts/network_request_evidence.gd").request(url).is_empty(): return
	_browse_url(url,true)
	var focus: Control = widgets.browser.page.find_child("NetworkRequestTest",true,false)
	if is_instance_valid(focus): focus.grab_focus.call_deferred()

func _backup_v2() -> bool:
	return game != null and game.state.accepted and game._current_chapter() == 1 and game._vm() != null and int(game._vm().state.get("backup_model_version",1)) >= 2

func _samba_v2() -> bool:
	return game != null and game.state.accepted and game._current_chapter() == 0 and int(game._vm().state.get("samba_model_version",1)) >= 2

func _samba_console_url(value: String) -> bool:
	return _samba_v2() and value.get_slice("#",0).get_slice("?",0).trim_suffix("/") == SAMBA_URL

func _samba_signature() -> String:
	if not _samba_v2(): return ""
	var live: Dictionary=game._vm().state
	return str([live.get("mutation",0),live.connected,live.active,live.get("dirty",false),game.current_done()])

func _render_samba() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var page: VBoxContainer=widgets.browser.page; _clear(page)
	samba_render_signature=_samba_signature()
	if game.current_done(): COMPLETED_CASE.render(self, page); return
	if not bool(game.vm_info().get("connected",false)):
		var connect_button := _button(UI.copy("samba_connect"),func(): _samba_command("ssh client"); _render_samba()); connect_button.name="SambaConnect"; page.add_child(connect_button); return
	preload("res://scripts/os_samba_console.gd").render(self,page)

func _samba_command(command_text: String) -> String:
	var was_refreshing:=refreshing; refreshing=true
	var result:=str(game.vm_run(command_text)); refreshing=was_refreshing
	samba_ui.output=result
	_invalidate_smb()
	_save_session(false)
	if widgets.has("verify"): _refresh_checks()
	if widgets.has("monitor"): _refresh_monitor()
	return result

func _samba_save(section: String, values: Dictionary) -> bool:
	if not _samba_v2(): return false
	var path:=str(game.vm_info().config_path)
	var updated:=preload("res://scripts/samba_config.gd").update_section(game.vm_read(path),section,values)
	if not str(updated.error).is_empty(): samba_ui.output=str(updated.error); return false
	var was_refreshing:=refreshing; refreshing=true
	var saved:=bool(game.vm_write(path,str(updated.text))); refreshing=was_refreshing
	samba_ui.output=UI.copy("samba_saved") if saved else UI.copy("ops_result_failed")
	_invalidate_smb(); _save_session(false)
	if widgets.has("verify"): _refresh_checks()
	if widgets.has("monitor"): _refresh_monitor()
	return saved

func _invalidate_smb() -> void:
	if str(samba_ui.get("access_revision",""))==_samba_signature(): return
	var live: Dictionary=game._vm().state
	var access_signature: String=JSON.stringify([live.get("applied",{}),live.get("connected",false),live.get("active",false)])
	if str(samba_ui.get("access_security_signature",""))==access_signature:
		samba_ui.access_stale=true
		samba_ui.access_revision=_samba_signature()
		if widgets.has("files") and bool(samba_ui.get("network_open",false)): _render_smb()
		return
	samba_ui.access_files=[]; samba_ui.access_preview=""; samba_ui.access_output=""
	samba_ui.access_operation=""
	samba_ui.access_selected=""; samba_ui.access_preview_path=""; samba_ui.access_revision=_samba_signature(); samba_ui.access_security_signature=access_signature
	if widgets.has("files") and bool(samba_ui.get("network_open",false)): _render_smb()

func _open_samba_share(share: String = "share") -> void:
	if not _samba_v2(): return
	samba_ui.access_share=share; samba_ui.network_open=true
	_show_app("files"); _smb_list(); _render_smb()

func _render_smb() -> void:
	if widgets.has("files"): FILES.refresh(self)

func _smb_argument(value: String) -> bool:
	return not value.is_empty() and not ('"' in value or "'" in value or "\n" in value or "\r" in value)

func _smb_command(operation: String) -> String:
	var share:=str(samba_ui.get("access_share","share"))
	if not _samba_v2() or game.current_done() or not bool(game.vm_info().get("connected",false)):
		return "NT_STATUS_CONNECTION_REFUSED"
	if not _smb_argument(share) or "/" in share: return "NT_STATUS_BAD_NETWORK_NAME"
	var identity:="-U staff" if str(samba_ui.get("access_user","staff"))=="staff" else "-N"
	var was_refreshing:=refreshing; refreshing=true
	var result:=str(game.vm_run('smbclient "//files01.client.test/'+share+'" '+identity+" -c '"+operation+"'"))
	refreshing=was_refreshing
	samba_ui.access_revision=_samba_signature()
	var live: Dictionary=game._vm().state
	samba_ui.access_security_signature=JSON.stringify([live.get("applied",{}),live.get("connected",false),live.get("active",false)])
	return result

func _smb_finish(output_text: String, success: bool, clear_on_error := false) -> bool:
	samba_ui.access_output=output_text
	if not success and clear_on_error:
		samba_ui.access_files=[]; samba_ui.access_preview=""; samba_ui.access_selected=""; samba_ui.access_preview_path=""
	_save_session(false)
	if widgets.has("verify"): _refresh_checks()
	return success

func _smb_list() -> bool:
	samba_ui.access_operation = "list"
	var scope: String = str(samba_ui.get("access_share","share"))+"|"+str(samba_ui.get("access_user","staff"))
	if scope != str(samba_ui.get("access_scope","")):
		samba_ui.access_preview=""; samba_ui.access_selected=""; samba_ui.access_preview_path=""
	samba_ui.access_scope=scope
	var result:=_smb_command("ls")
	samba_ui.access_stale=false
	var ok:=not result.begins_with("NT_STATUS_") and not result.begins_with("{") and not result.begins_with("smbclient:")
	samba_ui.access_files=Array(result.split("\n",false)) if ok and result!="0 files" else []
	if str(samba_ui.get("access_selected","")) not in samba_ui.access_files:
		samba_ui.access_preview=""; samba_ui.access_selected=""; samba_ui.access_preview_path=""
	return _smb_finish(result,ok,true)

func _smb_get(name: String, destination: String) -> bool:
	var result: String = _smb_command('get "'+name+'" "'+destination+'"') if _smb_argument(name) and _smb_argument(destination) else "NT_STATUS_INVALID_PARAMETER"
	var ok:=result.begins_with("getting file ") and result.ends_with(": OK")
	if ok:
		samba_ui.access_selected=name; samba_ui.access_preview=game.vm_read(destination); samba_ui.access_preview_path=game._vm()._path(destination)
		smb_document_focus = true
	_smb_record_transfer("download",destination,name,result,ok,str(game.vm_read(destination)) if ok else "")
	return _smb_finish(result,ok)

func _smb_put(source: String, name: String) -> bool:
	var contents: String = str(game.vm_read(source))
	var result: String = _smb_command('put "'+source+'" "'+name+'"') if _smb_argument(source) and _smb_argument(name) else "NT_STATUS_INVALID_PARAMETER"
	var ok:=result.begins_with("putting file ") and result.ends_with(": OK")
	if ok:
		_smb_list()
		_notify("転送保存済み")
	_smb_record_transfer("upload",source,name,result,ok,contents)
	get_node("/root/Soundscape").play_ui("work_success" if ok else "work_failure")
	return _smb_finish(result,ok)

func _smb_record_transfer(direction: String, local_path: String, filename: String, response: String, success: bool, contents: String) -> void:
	# A client receipt of an explicit request, never an inferred permission.
	var attempt := int(samba_ui.get("transfer_attempt",0)) + 1
	samba_ui.transfer_attempt = attempt
	samba_ui.access_operation = direction
	samba_ui.last_transfer = {"attempt":attempt,"direction":direction,"local_path":local_path,"filename":filename,"user":str(samba_ui.get("access_user","staff")),"share":str(samba_ui.get("access_share","share")),"response":response,"success":success,"bytes":contents.to_utf8_buffer().size() if success else 0,"source_sha256":contents.sha256_text(),"security_signature":_smb_security_signature()}

func _smb_security_signature() -> String:
	var live: Dictionary = game._vm().state
	return JSON.stringify([live.get("applied",{}),live.get("connected",false),live.get("active",false)])

func _backup_console_url(value: String) -> bool:
	return _backup_v2() and value.get_slice("#",0).get_slice("?",0).trim_suffix("/") == BACKUP_URL

func _backup_snapshot_signature() -> String:
	if not _backup_v2(): return ""
	var live: Dictionary = game._vm().state
	return JSON.stringify({"mutation":live.get("mutation",0),"connected":live.connected,"active":live.active,"dirty":live.get("dirty",false),"done":game.current_done()})

func _render_backup() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var page: VBoxContainer = widgets.browser.page; _clear(page)
	backup_render_signature = _backup_snapshot_signature()
	if game.current_done():
		COMPLETED_CASE.render(self, page); return
	if not bool(game.vm_info().get("connected",false)):
		page.add_child(_button("顧客端末に接続",func(): _backup_command("ssh client"); _render_backup()))
		return
	preload("res://scripts/os_backup_console.gd").render(self,page)

func _backup_command(command_text: String) -> String:
	var was_refreshing := refreshing
	refreshing = true
	var result := str(game.vm_run(command_text))
	refreshing = was_refreshing
	browser_response = result
	_save_session(false)
	if widgets.has("verify"): _refresh_checks()
	if widgets.has("monitor"): _refresh_monitor()
	return result

func _firewall_v2() -> bool:
	return game!=null and game.state.accepted and game._current_chapter()==2 and game._vm()!=null and int(game._vm().state.get("firewall_model_version",1))>=2

func _firewall_console_url(value: String) -> bool:
	return _firewall_v2() and value.get_slice("#",0).get_slice("?",0).trim_suffix("/")==FIREWALL_URL

func _firewall_snapshot_signature() -> String:
	return JSON.stringify({"snapshot":game._vm().firewall_snapshot(),"done":game.current_done()}) if _firewall_v2() else ""

func _render_firewall() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")):return
	var page: VBoxContainer=widgets.browser.page;_clear(page)
	firewall_render_signature=_firewall_snapshot_signature()
	if game.current_done(): COMPLETED_CASE.render(self,page);return
	if not bool(game.vm_info().get("connected",false)):
		page.add_child(_label(UI.copy("fw_connection_required"),14,UI.MUTED));return
	preload("res://scripts/os_firewall_console.gd").render(self,page)

func _firewall_action(action: String, payload: Dictionary = {}) -> Dictionary:
	_save_session(false)
	var result: Dictionary=game.firewall_action(action,payload)
	firewall_ui["result"]=result
	browser_response=JSON.stringify(result)
	_save_session(false)
	if widgets.has("verify"):_refresh_checks()
	if widgets.has("monitor"):_refresh_monitor()
	return result

func _identity_v2() -> bool:
	return game != null and game.state.accepted and game._current_chapter() == 3 and int(game._vm().state.get("identity_model_version",1)) >= 2

func _identity_console_url(value: String) -> bool:
	return _identity_v2() and value.get_slice("#",0).get_slice("?",0).trim_suffix("/") == IDENTITY_URL.trim_suffix("/")

func _edr_v2() -> bool:
	return game != null and game.state.accepted and game._current_chapter() == 4 and game._vm() != null and int(game._vm().state.get("edr_model_version",1)) >= 2

func _edr_console_url(value: String) -> bool:
	return _edr_v2() and value.get_slice("#",0).get_slice("?",0).trim_suffix("/") == EDR_URL.trim_suffix("/")

func _hotel_enabled() -> bool:
	return game != null and bool(game.state.get("accepted", false)) and game._current_chapter() == 4 and int(game._scenario().get("hotel_workflow_version", 0)) in [1, 2]

func _hotel_url(value: String) -> bool:
	return _hotel_enabled() and value.get_slice("#", 0).get_slice("?", 0).trim_suffix("/") == HOTEL_URL.trim_suffix("/")

func _open_hotel_frontdesk() -> void:
	if not _hotel_enabled(): return
	show_guide_service(HOTEL_URL)
	_browser_scroll_top()

func _open_endpoint_device(device_id: String) -> void:
	if device_id not in ["pc_a", "pc_b"]: return
	edr_ui.view = "devices"
	edr_ui.device = device_id
	edr_ui.erase("file_id")
	edr_ui["details_open"] = true
	show_guide_service(EDR_URL)
	_render_endpoint()
	_browser_scroll_top()

func _browser_scroll_top() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var scroll: Node = widgets.browser.page.get_parent()
	if scroll is ScrollContainer: scroll.scroll_vertical = 0

func _render_hotel_frontdesk() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var page: VBoxContainer = widgets.browser.page
	_clear(page)
	hotel_render_signature = JSON.stringify(game.hotel_snapshot())
	preload("res://scripts/hotel_frontdesk.gd").render(self, page)

func _hotel_action(folio_id: String) -> Dictionary:
	var was_refreshing := refreshing
	refreshing = true
	var result: Dictionary = game.hotel_action(folio_id)
	refreshing = was_refreshing
	_state_changed.call_deferred()
	return result

func _render_identity() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var page: VBoxContainer = widgets.browser.page
	_clear(page)
	if game.current_done(): COMPLETED_CASE.render(self,page); return
	if not bool(game.vm_info().get("connected", false)) or not bool(game._vm().state.get("active",false)):
		page.add_child(_label(browser_response if not browser_response.is_empty() else UI.copy("identity_connection_required", "SSH connection required"),14,UI.MUTED))
		return
	IDENTITY_CONSOLE.render(self,page)

func _refresh_completed_browser() -> void:
	# Returning from billing or company work must show the current saved result,
	# without refreshing the customer's service or issuing another request.
	if not game.current_done() or not widgets.has("browser"): return
	if not (_samba_console_url(browser_url) or _backup_console_url(browser_url) or _firewall_console_url(browser_url) or _identity_console_url(browser_url) or _edr_console_url(browser_url) or _portal_page_url(browser_url)): return
	var page: VBoxContainer = widgets.browser.page
	_clear(page)
	COMPLETED_CASE.render(self,page)

func _identity_command(command_text: String) -> String:
	if not command_text.begins_with("identity "): return JSON.stringify({"ok":false,"code":400,"error":"unsupported_command"})
	var result: String = game.vm_run(command_text)
	browser_response = result
	_save_session(false)
	if widgets.has("verify"): _refresh_checks()
	if widgets.has("monitor"): _refresh_monitor()
	return result

func _open_identity_login(user: String) -> void:
	identity_ui.view = "login"
	identity_ui.username = user
	for key in ["challenge", "enrollment", "required_action", "output"]: identity_ui.erase(key)
	_show_app("browser")
	_browse_url(IDENTITY_URL, true)

func _endpoint_command(command_text: String) -> String:
	if not command_text.begins_with("edr "): return JSON.stringify({"ok":false,"code":400,"error":"unsupported_command"})
	var result := str(game.vm_run(command_text)); browser_response = result; _save_session(false)
	if widgets.has("verify"): _refresh_checks()
	if widgets.has("monitor"): _refresh_monitor()
	return result

func _edr_snapshot_signature() -> String:
	if not _edr_v2() or game._vm() == null or not game._vm().has_method("edr_snapshot"): return ""
	return JSON.stringify({"snapshot":game._vm().edr_snapshot(),"done":game.current_done()})

func _render_endpoint() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")): return
	var page: VBoxContainer = widgets.browser.page; _clear(page)
	edr_render_signature = _edr_snapshot_signature()
	if game.current_done(): COMPLETED_CASE.render(self,page); return
	if not bool(game.vm_info().get("connected",false)) or not bool(game._vm().state.get("active",false)):
		page.add_child(_label(UI.copy("edr_connection_required", "Connection required"),14,UI.MUTED)); return
	preload("res://scripts/os_endpoint_console.gd").render(self,page)

func _portal_v2() -> bool:
	return game!=null and game.state.accepted and game._current_chapter()==5 and game._vm()!=null and int(game._vm().state.get("portal_model_version",1))>=2

func _portal_console_url(value: String) -> bool:
	return _portal_v2() and value.get_slice("#",0).get_slice("?",0).trim_prefix("https://").trim_prefix("http://").trim_suffix("/")=="portal.client.test/apps/files"

func _portal_page_url(value: String) -> bool:
	if not _portal_v2():return false
	var resource:=value.get_slice("#",0).get_slice("?",0).trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	return resource in ["portal.client.test/apps/files","portal.client.test/staff","portal.client.test/partner","portal.client.test/public"]

func _portal_snapshot_signature() -> String:
	if not _portal_v2():return ""
	return JSON.stringify({"snapshot":game._vm().portal_snapshot(),"done":game.current_done(),"connected":game.vm_info().connected,"active":game._vm().state.active})

func _render_portal() -> void:
	if not widgets.has("browser") or not is_instance_valid(widgets.browser.get("page")):return
	var page: VBoxContainer=widgets.browser.page;_clear(page)
	portal_render_signature=_portal_snapshot_signature()
	if game.current_done(): COMPLETED_CASE.render(self,page);return
	if not bool(game.vm_info().get("connected",false)) or not bool(game._vm().state.get("active",false)):
		page.add_child(_label(UI.copy("portal_connection_required") if not bool(game.vm_info().get("connected",false)) else UI.copy("portal_service_unavailable"),14,UI.MUTED));return
	preload("res://scripts/os_portal_console.gd").render(self,page)

func _portal_command(command_text: String) -> String:
	if not command_text.begins_with("portal "):return JSON.stringify({"ok":false,"code":400,"error":"unsupported_command"})
	var result:=str(game.vm_run(command_text));browser_response=result
	var parsed=JSON.parse_string(result)
	portal_ui["command_result"]=parsed if parsed is Dictionary else {"ok":false,"error":"operation_failed"}
	_save_session(false)
	if widgets.has("verify"):_refresh_checks()
	if widgets.has("monitor"):_refresh_monitor()
	return result

func _portal_draft_key() -> String:
	return "%s|%s|%s" % [str(portal_ui.get("role","partner")),browser_identity,str(portal_ui.get("age","current"))]

func _portal_stash_draft() -> void:
	if not bool(portal_ui.get("draft_dirty",false)):return
	var drafts_by_context: Dictionary=portal_ui.get("recipient_drafts",{})
	drafts_by_context[_portal_draft_key()]=str(portal_ui.get("preview_content",""));portal_ui["recipient_drafts"]=drafts_by_context

func _portal_restore_draft() -> void:
	portal_ui.erase("preview_content");portal_ui.erase("loaded_content");portal_ui.erase("response");portal_ui["draft_dirty"]=false
	var drafts_by_context: Dictionary=portal_ui.get("recipient_drafts",{});var key:=_portal_draft_key()
	if drafts_by_context.has(key):portal_ui["preview_content"]=str(drafts_by_context[key]);portal_ui["draft_dirty"]=true

func _portal_discard_draft() -> void:
	var drafts_by_context: Dictionary=portal_ui.get("recipient_drafts",{});drafts_by_context.erase(_portal_draft_key());portal_ui["recipient_drafts"]=drafts_by_context
	portal_ui["preview_content"]=str(portal_ui.get("loaded_content",""));portal_ui["draft_dirty"]=false
	_save_session(false)

func _set_portal_response(response: String) -> void:
	portal_ui["response"]=response
	var recipient_flow = preload("res://scripts/portal_recipient_flow.gd")
	var stamp: String = recipient_flow.signature(game._vm().portal_snapshot(),browser_identities())
	portal_ui["recipient_results"] = recipient_flow.record(portal_ui.get("recipient_results",{}),_portal_draft_key(),str(portal_ui.get("response_method","GET")),response,stamp)
	var boundary:=response.find("\n\n")
	if response.begins_with("HTTP/1.1 200") and boundary>=0:
		portal_ui["loaded_content"]=response.substr(boundary+2)
		if str(portal_ui.get("response_method","GET"))=="PUT" or not bool(portal_ui.get("draft_dirty",false)):
			_portal_discard_draft()
	elif str(portal_ui.get("response_method","GET"))=="GET" and not bool(portal_ui.get("draft_dirty",false)):
		portal_ui.erase("preview_content");portal_ui["draft_dirty"]=false

func _portal_request(role: String, method: String, age: String, content: String = "") -> String:
	_portal_stash_draft()
	portal_ui["view"]="preview";portal_ui["role"]=role;portal_ui["age"]=age;portal_ui["response_method"]=method;portal_ui["response_role"]=role
	var response: String=game.portal_request(role,method,age,browser_identity,content)
	browser_response=response;_set_portal_response(response)
	browser_url="https://portal.client.test/%s?link=%s" % [role,age]
	if browser_history_index>=0 and browser_history_index<browser_history.size()-1:browser_history=browser_history.slice(0,browser_history_index+1)
	if browser_history.is_empty() or str(browser_history.back())!=browser_url:browser_history.append(browser_url)
	browser_history_index=browser_history.size()-1
	if widgets.has("browser"):
		widgets.browser.url.text=browser_url;widgets.browser.back.disabled=browser_history_index<=0;widgets.browser.forward.disabled=true
	_save_session(false)
	if widgets.has("verify"):_refresh_checks()
	return response

func _browser_back() -> void:
	if browser_history_index <= 0: return
	browser_history_index -= 1
	_browse_url(str(browser_history[browser_history_index]), false)

func _browser_forward() -> void:
	if browser_history_index < 0 or browser_history_index >= browser_history.size()-1: return
	browser_history_index += 1
	_browse_url(str(browser_history[browser_history_index]), false)

func _monitor(parent: VBoxContainer) -> void:
	preload("res://scripts/os_services.gd").build(self,parent)

func _refresh_monitor() -> void:
	preload("res://scripts/os_services.gd").refresh(self)

func _checks(parent: VBoxContainer) -> void:
	DIAGNOSTICS.build(self,parent)
func _refresh_checks() -> void:
	DIAGNOSTICS.refresh(self)

func _verify() -> void:
	if not game.state.accepted: _notify("未受注"); return
	var checks: Array = game.verify()
	_append("動作検証\n"+"\n".join(checks.map(func(c): return ("PASS  " if c.passed else "FAIL  ")+str(c.label))))
	_show_app("verify")
	_notify(UI.copy("receipt_submit","納品できます") if game.can_deliver() else "未達成の項目があります")

func _open_guidance() -> void:
	if game.has_method("advanced_active") and game.advanced_active():
		_show_app("advanced")
		return
	var guide: Dictionary=game.work_guidance()
	if game.state.strategy=="": _company(); return
	if game.state.awaiting_contract: _contracts(); return
	var app: String=guide.get("app","manual")
	if app=="editor": _open_config()
	elif app=="browser" and _identity_v2():
		if guide.has("identity_user"):
			_open_identity_login(str(guide.identity_user))
			return
		identity_ui.view = str(guide.get("identity_view","users")); _show_app("browser"); _browse_url(IDENTITY_URL,true)
	elif app=="browser" and _edr_v2():
		edr_ui.erase("file_id")
		if guide.has("edr_device"): edr_ui.device = str(guide.edr_device)
		else: edr_ui.erase("device")
		edr_ui.view = str(guide.get("edr_view","devices")); _show_app("browser"); _browse_url(EDR_URL,true)
	elif app=="browser":
		var url:=SAMBA_URL if _samba_v2() else BACKUP_URL if _backup_v2() else FIREWALL_URL if _firewall_v2() else PORTAL_URL if _portal_v2() else browser_url
		_show_app("browser"); _browse_url(url,true)
	else: _show_app(app)

func _type_command(value: String) -> void:
	_show_app("terminal"); widgets.terminal.command.text=value; widgets.terminal.command.grab_focus(); widgets.terminal.command.caret_column=value.length()

func _manual(parent: VBoxContainer) -> void:
	var p := _pad(parent,16); var tabs := _row(p,4)
	widgets.manual = {"tab":"work","tabs":{},"body":null}
	for entry in [["work","今の作業"],["config","設定の書き方"],["commands","コマンド"]]:
		var b := _button(entry[1],func(): widgets.manual.tab=entry[0]; _refresh_manual()); b.flat=true; tabs.add_child(b); widgets.manual.tabs[entry[0]]=b
	p.add_child(HSeparator.new()); widgets.manual.body = _scroll(p); _refresh_manual()

func _refresh_manual() -> void:
	var w: Dictionary=widgets.manual; var box: VBoxContainer=w.body; _clear(box)
	for key in w.tabs: UI.navigation(w.tabs[key],key==w.tab)
	if w.tab == "work":
		var guide: Dictionary=game.work_guidance()
		box.add_child(_label(guide.title,22)); box.add_child(_label(guide.detail,15,MUTED))
		var action := _primary("作業画面を開く",_open_guidance); action.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; box.add_child(action); box.add_child(HSeparator.new())

		var detail := _disclosure(box,"同僚への依頼・案内を再表示")
		detail.add_child(_label(_personalize("役割分担：綾は調査と報告書の作成、蓮は環境の復元と証拠保全を担当します。"),15,MUTED)); detail.add_child(_button("チームを開く",_show_app.bind("team")))
		return
	if not game.state.accepted: box.add_child(_label("受注すると、この案件の資料を表示します。",17,MUTED)); return
	if w.tab == "config":
		if _edr_v2():
			box.add_child(_label(UI.copy("edr_title"),22))
			if bool(game._vm().state.get("scenario",{}).get("edr_recovery_required",false)):
				box.add_child(_label(UI.copy("rmd_debrief"),14,MUTED))
			box.add_child(_button(UI.copy("edr_devices"),func(): _show_app("browser"); _browse_url(EDR_URL,true)))
			return
		if _identity_v2():
			box.add_child(_label(UI.copy("identity_title", "Identity management"),22))
			box.add_child(_label(UI.copy("identity_reference_body", ""),14,MUTED))
			box.add_child(_button(UI.copy("identity_title", "Identity management"),func(): _show_app("browser"); _browse_url(IDENTITY_URL,true)))
			return
		if game._current_chapter() == 0 and int(game._vm().state.get("samba_model_version",1)) >= 2:
			box.add_child(_label("Samba / smb.conf",22))
			box.add_child(_label("[global] は全体設定、[share] は共有フォルダーの設定です。",15,MUTED))
			for entry in [["path","共有するフォルダーの場所"],["available = no","共有全体への接続を停止"],["guest ok = yes","匿名の接続を許可（演習のゲストは nobody）"],["valid users = staff","接続を許可するユーザーを限定"],["invalid users = staff","接続を拒否。valid users より優先"],["read only = yes","読み取り専用。yes/no、true/false、1/0 を使用"],["write list = staff","指定ユーザーに書き込みを許可"],["read list = nobody","指定ユーザーを読み取り専用にする。write list と重複した場合は書き込みを許可"]]:
				box.add_child(_label(str(entry[0]),15,UI.PRIMARY)); box.add_child(_label(str(entry[1]),14,MUTED)); box.add_child(HSeparator.new())
			box.add_child(_label("testparm -s は構文確認だけを行います。保存した設定は、サービスを再起動すると反映されます。",15,MUTED))
			box.add_child(_button("設定ファイルを開く",_open_config)); return
		box.add_child(_label("設定ファイルの書き方",22)); box.add_child(_label("設定ファイルは「項目名=値」の形式で1行ずつ記述します。",15,MUTED))
		var names := {"staff":"社員の権限","guest":"ゲスト","partner":"取引先","public":"一般公開","schedule":"バックアップ間隔","repository":"保存先","dns":"名前解決","business":"業務サイト","admin_public":"外部からの管理","tls":"暗号化通信","former":"退職者","sessions":"既存セッション","current":"在籍者","mfa":"追加認証","pc_a":"PC-A","pc_b":"PC-B","logs":"操作記録","reset":"端末初期化","expires":"共有期限","audit":"監査ログ"}
		var values := {"none":"拒否","read":"閲覧","write":"閲覧・書込","off":"無効","on":"有効","daily":"毎日","local":"端末内","offsite":"別拠点","deny":"拒否","allow":"許可","active":"有効","disabled":"無効","valid":"有効","revoked":"失効","connected":"接続","isolated":"隔離","keep":"保持","erase":"削除","wait":"実行しない","wipe":"初期化","unlimited":"期限なし","7d":"7日","30d":"30日"}
		var schema: Dictionary=game._vm().SCHEMAS[game._current_chapter()]
		for key in schema:
			var row := _row(box,16); var name := _label(str(key),15,UI.PRIMARY); name.custom_minimum_size.x=128; row.add_child(name)
			var content := _box(row,4); content.add_child(_label(str(names.get(key,key)),15))
			var choices: Array[String]=[]
			for value in schema[key]: choices.append(str(value)+"（"+str(values.get(value,value))+"）")
			content.add_child(_label(" / ".join(choices),14,MUTED)); box.add_child(HSeparator.new())
		box.add_child(_button("設定ファイルを開く",_open_config)); return
	box.add_child(_label("コマンドを選んで入力",22))
	var commands: Array = [["ssh client","接続"],["cat "+str(game.vm_info().config_path),"設定を読む"],["systemctl status "+str(game.vm_info().service),"状態を確認"],["systemctl restart "+str(game.vm_info().service),"設定を反映"],["journalctl","ログを読む"],["help","コマンド一覧"]]
	if game._current_chapter()==1: commands.append(["restic snapshots","バックアップ一覧"]); commands.append(["restic restore latest --target /restore","復元"])
	if _edr_v2():
		commands = [["ssh client",UI.copy("edr_connected")],["edr devices",UI.copy("edr_devices")],["edr timeline pc_a",UI.copy("edr_timeline")],["edr collect",UI.copy("edr_collect")],["edr isolate pc_a",UI.copy("edr_isolate")],["edr release pc_a",UI.copy("edr_release")]]
		if bool(game._vm().state.get("scenario",{}).get("edr_recovery_required",false)):
			commands.append(["edr files pc_a",UI.copy("rmd_files")]); commands.append(["edr scan pc_a",UI.copy("rmd_scan")]); commands.append(["edr status pc_a",UI.copy("rmd_probe_clean_a")])
	for entry in commands:
		var row := _row(box,10); var col := _box(row,3); col.add_child(_label(entry[1],14,MUTED)); var line:=_label(entry[0],15); line.add_theme_font_override("font",mono); col.add_child(line); row.add_child(_button("入力",_type_command.bind(entry[0])))

func _help_step(app: String) -> void:
	if app == "editor": _open_config()
	else: _show_app(app)

func _disclosure(parent: Node, title: String) -> VBoxContainer:
	var toggle := _button("▸  "+title,func(): pass); toggle.flat = true; toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT; parent.add_child(toggle)
	var content := _box(parent,8); content.hide()
	toggle.pressed.connect(func(): content.visible = not content.visible; toggle.text = ("▾  " if content.visible else "▸  ")+title)
	return content

func _trace(action: String, target: String) -> void:
	operation_trace.append({"at":Time.get_datetime_string_from_system(),"action":action,"target":target,"app":current_app,"session":session_key})
	if operation_trace.size() > 30: operation_trace.pop_front()
	var f := FileAccess.open("user://terminal-diagnostics.json",FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version",""),"recent":operation_trace},"  ")); f.close()
