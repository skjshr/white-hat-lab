extends SceneTree

## Review verification for the virtual workstation navigation and focus contract.
## This drives the same interface and desktop controls as the product tests.

const INTERFACE = preload("res://scripts/interface.gd")
var ui
var game
var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	capture_enabled="--capture" in OS.get_cmdline_user_args()
	narrow="--narrow" in OS.get_cmdline_user_args()
	create_timer(60.0).timeout.connect(func(): push_error("desktop review timeout"); quit(2))
	call_deferred("run")

func run() -> void:
	ui = INTERFACE.new()
	root.add_child(ui)
	await process_frame
	game = ui._game()
	_assert(game.save_path.begins_with("user://qa-"),"desktop QA uses isolated storage")
	game.set_process(false)
	ui._new_game()
	game.choose_strategy("operations")
	game.accept_mission()
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_panel("terminal")
	await process_frame
	var pc = ui.desktop
	pc._show_app("terminal")
	pc._run_command("ssh client")
	await process_frame
	_test_file_navigation(pc)
	_test_local_file_interactions(pc)
	_test_file_address_shortcut(pc)
	_test_draft_survives_switch_and_minimize(pc)
	await _test_editor_save_round_trip(pc)
	_test_editor_find_replace(pc)
	_test_alt_tab_cycles_three(pc)
	_test_overview_bounds(pc)
	_test_browser_history(pc)
	await _test_shell_lifecycle(pc)
	_test_narrow_desktop(pc)
	for failure in failures: push_error(failure)
	print("PASS: desktop review navigation, focus, drafts, close/minimize persistence, taskbar, shortcuts, overview, and browser history" if failures.is_empty() else "FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_file_navigation(pc) -> void:
	pc._show_app("files")
	var path: LineEdit = pc.widgets.files.path
	path.text = "/etc"
	path.text_submitted.emit("/etc")
	path.text = "/etc/samba"
	path.text_submitted.emit("/etc/samba")
	var crumb: Button = _find_button(pc.widgets.files.breadcrumb, "etc")
	_assert(crumb != null, "file breadcrumb renders an actionable directory")
	if crumb != null: crumb.pressed.emit()
	_assert(pc.file_directory == "/etc", "breadcrumb navigates to the selected directory")
	pc.widgets.files.back.pressed.emit()
	_assert(pc.file_directory == "/etc/samba", "file back returns to the previous location")
	pc.widgets.files.forward.pressed.emit()
	_assert(pc.file_directory == "/etc", "file forward restores the next location")
	_assert(pc.widgets.files.back.is_inside_tree() and pc.widgets.files.forward.is_inside_tree(), "file navigation controls remain reachable")
	_assert(pc.widgets.files.open.is_inside_tree() and pc.widgets.files.copy.is_inside_tree() and pc.widgets.files.paste.is_inside_tree(), "file action controls remain reachable")

func _test_file_address_shortcut(pc) -> void:
	pc._show_app("files")
	var path: LineEdit = pc.widgets.files.path
	var key := InputEventKey.new()
	key.keycode = KEY_L; key.ctrl_pressed = true; key.pressed = true
	pc._input(key)
	_assert(path.has_focus(), "Ctrl+L focuses the file address input")
	_assert(path.visible, "Ctrl+L reveals the file address input")
	path.text = "/etc/samba"
	path.text_submitted.emit(path.text)
	_assert(pc.file_directory == "/etc/samba", "address Enter navigates to the requested directory")
	_assert(not path.visible, "address input returns to breadcrumb view after Enter")

func _test_local_file_interactions(pc) -> void:
	pc.file_remote = false
	pc.game.state.os_files = {
		"/home/operator/Documents/small.txt": "小",
		"/home/operator/Documents/large.txt": "大きなローカル文書\n".repeat(12),
		"/home/operator/Documents/subfolder/nested.txt": "入れ子"
	}
	pc.file_directory = "/home/operator/Documents"
	pc.widgets.files.path.text = pc.file_directory
	pc._list_files()
	var tree: Tree = pc.widgets.files.tree
	var root_item := tree.get_root()
	_assert(_tree_item_named(root_item, "subfolder") != null, "local subfolder is listed")
	_assert(_tree_item_named(root_item, "small.txt") != null and _tree_item_named(root_item, "large.txt") != null, "two local files are listed")
	var small: TreeItem = _tree_item_named(root_item, "small.txt")
	small.select(0)
	tree.column_title_clicked.emit(2, MOUSE_BUTTON_LEFT)
	tree.column_title_clicked.emit(2, MOUSE_BUTTON_LEFT)
	var first_file: TreeItem = _first_file_item(tree.get_root())
	_assert(first_file != null and first_file.get_text(0) == "large.txt", "size column sorts descending")
	_assert(tree.get_selected() != null and str(tree.get_selected().get_metadata(0)) == "workstation:/home/operator/Documents/small.txt", "selection survives sort")
	var folder: TreeItem = _tree_item_named(tree.get_root(), "subfolder")
	tree.deselect_all(); folder.select(0); tree.item_activated.emit()
	_assert(pc.file_directory == "/home/operator/Documents/subfolder", "folder activation enters subfolder")
	pc._parent_directory()
	_assert(pc.file_directory == "/home/operator/Documents", "parent navigation returns to local folder")
	var large: TreeItem = _tree_item_by_suffix(pc.widgets.files.tree.get_root(), "/large.txt")
	pc.widgets.files.tree.deselect_all(); large.select(0)
	pc.widgets.files.context.id_pressed.emit(0)
	_assert(pc.editor_path == "workstation:/home/operator/Documents/large.txt", "context open uses canonical local path")
	pc._show_app("files")
	pc.file_remote = false; pc.file_directory = "/home/operator/Documents"; pc.widgets.files.path.text = pc.file_directory; pc._list_files()
	var copy_item: TreeItem = _tree_item_by_suffix(pc.widgets.files.tree.get_root(), "/small.txt"); copy_item.select(0); pc.widgets.files.context.id_pressed.emit(1)
	pc.widgets.files.context.id_pressed.emit(2)
	_assert(pc.game.state.os_files.has("/home/operator/Documents/copy-small.txt"), "context copy and paste create local copy")
	var key := InputEventKey.new(); key.keycode = KEY_L; key.ctrl_pressed = true; key.pressed = true; pc._input(key)
	_assert(pc.widgets.files.path.has_focus(), "Ctrl+L remains available with local file context")
	pc.game.state.os_files["/home/aoba/Documents/legacy.txt"] = "旧alias"
	preload("res://scripts/profile_paths.gd").migrate(pc.game.state)
	pc._open_editor("workstation:/home/aoba/Documents/legacy.txt")
	_assert(pc.editor_path == "workstation:/home/operator/Documents/legacy.txt" and pc.editor.text == "旧alias", "legacy home input resolves to canonical local path")

func _test_editor_find_replace(pc) -> void:
	var path := "workstation:/home/operator/Documents/search-check.txt"
	pc.game.state.os_files[path.trim_prefix("workstation:")] = "guest=read\nstaff=write\nguest=none\n"
	pc._open_editor(path)
	var key := InputEventKey.new(); key.keycode=KEY_H; key.ctrl_pressed=true; key.pressed=true; pc._input(key)
	var w: Dictionary = pc.widgets.editor
	_assert(w.find_panel.visible and w.replace_row.visible, "Ctrl+H opens editor find and replace")
	w.find_input.text = "guest"; w.find_input.text_changed.emit("guest")
	_assert(w.editor.get_selected_text() == "guest" and w.find_count.text == "2件", "find selects text and counts occurrences without altering draft")
	w.replace_input.text = "visitor"; w.replace_button.pressed.emit()
	_assert(w.editor.text.begins_with("visitor=read") and "guest=none" in w.editor.text, "replace changes only the selected match")
	w.editor.undo()
	_assert(w.editor.text == pc.game.state.os_files[path.trim_prefix("workstation:")], "replacement supports undo without changing the saved file")
	w.find_input.text = "missing-value"; w.find_input.text_changed.emit(w.find_input.text)
	_assert(w.find_count.text == "0件" and not w.editor.has_selection(), "zero matches clears old selection")
	key.keycode=KEY_ESCAPE; key.ctrl_pressed=false; pc._input(key)
	_assert(not w.find_panel.visible and pc.visible, "Escape closes find before leaving the desktop")

func _tree_item_named(root_item: TreeItem, name: String):
	if root_item == null: return null
	var item := root_item.get_first_child()
	while item != null:
		if item.get_text(0) == name: return item
		item = item.get_next()
	return null

func _tree_item_by_suffix(root_item: TreeItem, suffix: String) -> TreeItem:
	var item := root_item.get_first_child()
	while item != null:
		if str(item.get_metadata(0)).ends_with(suffix): return item
		item = item.get_next()
	return null

func _first_file_item(root_item: TreeItem) -> TreeItem:
	var item := root_item.get_first_child()
	while item != null:
		if not str(item.get_metadata(0)).ends_with("/"): return item
		item = item.get_next()
	return null

func _test_draft_survives_switch_and_minimize(pc) -> void:
	pc._open_editor("workstation:/home/aoba/Documents/rv-draft.txt")
	pc.editor.text = "保持する下書き"
	pc._show_app("browser")
	pc._show_app("editor")
	_assert(pc.editor.text == "保持する下書き", "editor draft survives app switching")
	pc._taskbar_activate("editor")
	_assert(not pc.windows.editor.visible, "active task button minimizes the focused window")
	pc._show_app("editor")
	_assert(pc.editor.text == "保持する下書き", "editor draft survives minimize and reopen")

func _test_editor_save_round_trip(pc) -> void:
	pc._show_app("editor")
	var editor_widgets: Dictionary = pc.widgets.editor
	_assert(not editor_widgets.path_row.visible, "editor path row starts hidden")
	var config_path := str(pc.game.vm_info().config_path)
	pc._open_editor(config_path)
	await _frame_for_test()
	var original: String = str(pc.game.vm_read(config_path))
	var edited: String = original + "\n# rv110-ui-finaltest\n"
	pc.editor.text = edited
	pc._state_changed()
	_assert(not pc.widgets.editor.save.disabled, "editor Save enables for unsaved content")
	_assert(pc.widgets.editor.info.text.contains("未保存"), "editor status reports unsaved content")
	var tab_title: String = str(pc.widgets.editor.tabs.get_tab_title(pc.widgets.editor.tabs.current_tab))
	_assert("●" in tab_title, "editor tab marks unsaved content")
	pc._show_app("browser")
	pc._show_app("editor")
	_assert(not pc.widgets.editor.save.disabled and pc.widgets.editor.info.text.contains("未保存"), "unsaved editor state survives app switch")
	pc.widgets.editor.save.pressed.emit()
	await _frame_for_test()
	_assert(pc.game.vm_read(config_path) == edited, "Save writes edited content to the VM file")
	_assert(pc.widgets.editor.save.disabled, "Save disables after successful write")
	_assert(not pc.widgets.editor.info.text.contains("未保存"), "editor status returns to saved")
	var saved_title: String = str(pc.widgets.editor.tabs.get_tab_title(pc.widgets.editor.tabs.current_tab))
	_assert("●" not in saved_title, "editor tab clears unsaved marker after Save")

func _frame_for_test() -> void:
	await process_frame

func _test_alt_tab_cycles_three(pc) -> void:
	pc._show_app("terminal")
	pc._show_app("files")
	pc._show_app("browser")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.alt_pressed = true
	key.pressed = true
	pc._input(key)
	_assert(pc.current_app == "files", "Alt+Tab selects the previous app")
	pc._input(key)
	_assert(pc.current_app == "terminal", "repeated Alt+Tab cycles to a third app")
	var release := InputEventKey.new()
	release.keycode = KEY_ALT
	release.pressed = false
	pc._input(release)

func _test_overview_bounds(pc) -> void:
	_assert(pc._overview_columns(960.0) == 2, "narrow overview uses two columns")
	_assert(pc._overview_columns(1280.0) == 3, "desktop overview uses three columns")
	_assert(pc._overview_columns(1920.0) == 5, "wide overview uses five columns")
	pc.size = Vector2(960, 550)
	pc.overview.size = Vector2(940, 126)
	pc._toggle_overview()
	var grid: GridContainer = _find_grid(pc.overview)
	_assert(grid != null and grid.columns == 2, "960px overview keeps the tile grid within two columns")
	_assert(pc.overview.position.x >= 0 and pc.overview.position.x + pc.overview.size.x <= pc.size.x + 1, "overview stays within the desktop bounds")
	pc._toggle_overview()

func _test_browser_history(pc) -> void:
	pc._show_app("browser")
	var urls := ["https://files.client.test/staff/report.txt", "https://intranet.client.test", "https://files.client.test/guest/report.txt"]
	for url in urls:
		pc.url_edit.text = url
		pc._browse()
	pc._browser_back()
	_assert(pc.url_edit.text == urls[1] and pc.browser_url == urls[1], "browser back keeps the address field and committed URL aligned")
	pc._browser_back()
	_assert(pc.url_edit.text == urls[0], "browser back reaches the first history entry")
	pc._browser_forward()
	_assert(pc.url_edit.text == urls[1], "browser forward restores the next history entry")
	pc.url_edit.text = "https://files.client.test/staff/report.txt"
	pc._browse()
	_assert(pc.browser_history_index == pc.browser_history.size() - 1 and pc.widgets.browser.forward.disabled, "new browser navigation truncates stale forward history")
	pc._browser_back()
	pc._save_session()
	var session: Dictionary = game.state.desktop_sessions[pc.session_key]
	_assert(int(session.get("browser_history_index", -1)) == pc.browser_history_index, "browser history cursor is persisted with the session")

func _test_narrow_desktop(pc) -> void:
	pc.size = Vector2(960, 550)
	pc._desktop_resized()
	pc._show_app("terminal")
	pc._show_app("files")
	pc._tile_windows()
	var visible: Array[String] = []
	for id in pc.windows:
		if pc.windows[id].visible: visible.append(str(id))
	_assert(visible.size() == 1, "narrow tile keeps only the front window visible")
	if visible.size() == 1:
		var front = pc.windows[visible[0]]
		_assert(front.maximized and front.position == Vector2.ZERO, "narrow tile maximizes the front window")
	pc._state_changed()
	_assert(pc.tray.text.contains("DAY") and not pc.tray.text.contains("納期"), "narrow taskbar keeps a compact day and time with deadline only in tooltip")
	_assert(pc.tray.tooltip_text.contains("納期") or not pc.game.state.accepted,"deadline remains available in tray tooltip")

func _test_shell_lifecycle(pc) -> void:
	pc.size=Vector2(root.size); pc._desktop_resized()
	await process_frame
	_assert(pc.workspace.offset_top==0 and not is_instance_valid(pc.system_bar),"desktop has no top dashboard bar")
	for id in pc.PINNED_APPS:
		_assert(pc.task_buttons[id].text.is_empty() and pc.task_buttons[id].tooltip_text==pc.APPS[id][0],"taskbar has icon and exact app tooltip: "+id)
	pc._dismissed("browser")
	var before: String=pc.current_app
	pc.desktop_shortcuts.browser.pressed.emit()
	_assert(pc.selected_shortcut=="browser" and pc.current_app==before and "browser" not in pc.running_apps,"single shortcut click selects without opening")
	var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.double_click=true
	pc.desktop_shortcuts.browser.gui_input.emit(click)
	_assert(pc.current_app=="browser" and "browser" in pc.running_apps,"double click opens desktop shortcut")
	pc._dismissed("browser")
	var enter:=InputEventKey.new(); enter.keycode=KEY_ENTER; enter.pressed=true
	pc.desktop_shortcuts.browser.gui_input.emit(enter)
	_assert(pc.current_app=="browser","Enter opens focused shortcut")
	pc._open_editor("workstation:/home/operator/Documents/lifecycle-draft.txt")
	pc.editor.text="unsaved lifecycle draft\n"
	pc.windows.editor.chrome_buttons[0].pressed.emit()
	_assert("editor" in pc.running_apps and not pc.windows.editor.visible,"minimize keeps editor running")
	_assert(pc.task_buttons.editor.get_node("RunningIndicator").visible,"minimized window keeps its running underline")
	pc._save_session()
	_assert(game.load_game(),"saved desktop loads from disk")
	pc._reload_contract_session()
	await process_frame
	_assert("editor" in pc.running_apps and not pc.windows.editor.visible,"minimized editor survives save/load without becoming visible")
	pc._show_app("editor")
	_assert(pc.editor.text=="unsaved lifecycle draft\n","minimized editor draft survives disk save/load")
	pc.windows.editor.chrome_buttons[2].pressed.emit()
	_assert("editor" not in pc.running_apps and not pc.windows.editor.visible,"close removes editor from running applications")
	_assert(not pc.task_buttons.editor.get_node("RunningIndicator").visible,"closed editor loses its running underline")
	pc.alt_tab_order.clear()
	var tab:=InputEventKey.new(); tab.keycode=KEY_TAB; tab.alt_pressed=true; tab.pressed=true; pc._input(tab)
	_assert("editor" not in pc.alt_tab_order,"closed editor is excluded from Alt+Tab")
	pc.alt_tab_order.clear(); pc._save_session()
	_assert(game.load_game(),"closed desktop state reloads from disk")
	pc._reload_contract_session()
	await process_frame
	_assert("editor" not in pc.running_apps and not pc.windows.has("editor"),"closed editor is not restored on reload")
	pc._show_app("editor")
	_assert(pc.editor.text=="unsaved lifecycle draft\n","reopening closed editor restores its saved draft")
	pc.windows.editor.chrome_buttons[0].pressed.emit()
	for id in pc.running_apps.duplicate():
		if id!="editor":pc._dismissed(id)
	pc.alt_tab_order.clear(); pc._input(tab)
	_assert(pc.current_app=="editor" and pc.windows.editor.visible,"Alt+Tab restores a minimized running window")
	pc.alt_tab_order.clear()
	var window=pc.windows.editor
	var was_maximized: bool=window.maximized
	window._title_input(click)
	_assert(window.maximized!=was_maximized,"titlebar double click toggles maximize")
	window._title_input(click)
	_assert(window.maximized==was_maximized,"titlebar second double click restores window")
	pc._show_app("files")
	pc.file_remote=false; pc.file_directory="/home/operator/Documents"; pc._list_files()
	pc._show_app("mail")
	pc.size=Vector2(root.size);pc._desktop_resized()
	await capture("desktop-windows")
	pc._show_desktop()
	_assert(pc.current_app.is_empty() and not pc.windows.mail.visible,"show desktop hides open windows")
	await capture("desktop-shortcuts")
	pc.start_menu.show()
	await capture("desktop-start")
	pc.start_menu.hide();pc._show_desktop()
	_assert(pc.current_app=="mail" and pc.windows.mail.visible,"show desktop toggles back to previous windows")
	pc._save_session()

func capture(label: String) -> void:
	if not capture_enabled:return
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/experience/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	_assert(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"native capture "+label)

func _find_button(node: Node, text: String):
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var found = _find_button(child, text)
		if found != null: return found
	return null

func _find_grid(node: Node):
	if node is GridContainer: return node
	for child in node.get_children():
		var found = _find_grid(child)
		if found != null: return found
	return null

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)
