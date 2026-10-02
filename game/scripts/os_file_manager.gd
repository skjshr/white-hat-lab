extends RefCounted
## AOBA OS file manager. Compact Explorer-like view over the virtual filesystem.

const UI = preload("res://scripts/ui_theme.gd")
const FOLDER = preload("res://assets/ui/folder_item.svg")
const DOCUMENT = preload("res://assets/ui/document_item.svg")

static func _tool(d, symbol: String, tooltip: String, callback: Callable, label := "") -> Button:
	var b: Button
	if d.has_method("_tool_button"):
		b = d._tool_button(symbol, tooltip, callback)
		if not label.is_empty(): b.text = label
	else:
		b = d._button(label, callback)
	b.tooltip_text = tooltip
	b.custom_minimum_size.y = 30
	if label.is_empty(): b.text = ""
	return b

static func _section(d, parent: Node, title: String) -> Label:
	var l = d._label(title, 12, UI.MUTED)
	parent.add_child(l)
	return l

static func build(d, parent: VBoxContainer) -> void:
	var p = d._pad(parent, 8)
	var toolbar: HBoxContainer = d._row(p, 3)
	var back: Button = _tool(d, "back", "戻る", func(): _back(d))
	var forward: Button = _tool(d, "forward", "進む", func(): _forward(d))
	var up: Button = _tool(d, "up", "親フォルダー", d._parent_directory)
	toolbar.add_child(back)
	toolbar.add_child(forward)
	toolbar.add_child(up)
	var address := HBoxContainer.new()
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(address)
	var path := LineEdit.new()
	path.name = "FilesAddress"
	path.text = d.file_directory
	path.placeholder_text = "/home/operator/Documents"
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path.custom_minimum_size.y = 30
	path.text_submitted.connect(func(_v): _navigate(d, str(path.text)); path.release_focus())
	address.add_child(path)
	path.hide()
	toolbar.add_child(_tool(d, "code", "アドレスへ移動  Ctrl+L", func(): _edit_address(d)))
	var search := LineEdit.new()
	search.name = "FilesSearch"
	search.placeholder_text = "検索"
	search.custom_minimum_size = Vector2(150, 30)
	search.clear_button_enabled = true
	search.text_changed.connect(func(_v): refresh(d))
	toolbar.add_child(search)
	toolbar.add_child(_tool(d, "refresh", "更新", func():
		if bool(d.samba_ui.get("network_open",false)): d._smb_list()
		refresh(d)))
	var breadcrumb_scroll := ScrollContainer.new()
	breadcrumb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	breadcrumb_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	breadcrumb_scroll.custom_minimum_size.y = 30
	breadcrumb_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.add_child(breadcrumb_scroll)
	var breadcrumb: HBoxContainer = d._row(breadcrumb_scroll, 2)
	breadcrumb.add_theme_constant_override("separation", 2)
	breadcrumb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	path.focus_entered.connect(func():
		breadcrumb_scroll.hide()
	)
	path.focus_exited.connect(func():
		path.hide()
		breadcrumb_scroll.show()
	)
	var command_strip := PanelContainer.new()
	command_strip.add_theme_stylebox_override("panel", UI.style(UI.PAPER, UI.BORDER, 0, 2, 0))
	var command_row: HBoxContainer = d._row(command_strip, 3)
	command_row.custom_minimum_size.y = 34
	p.add_child(command_strip)

	var split: HBoxContainer = d._row(p, 6)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var places_panel := PanelContainer.new()
	places_panel.add_theme_stylebox_override("panel", UI.style(UI.OS_NAV,Color.TRANSPARENT,4,8,0))
	split.add_child(places_panel)
	var places_scroll := ScrollContainer.new()
	places_scroll.name = "FilePlacesScroll"
	places_scroll.custom_minimum_size.x = 150
	places_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	places_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	places_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	places_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	places_panel.add_child(places_scroll)
	var places: VBoxContainer = d._box(places_scroll, 1)
	var place_buttons: Array = []
	places.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section(d, places, UI.copy("fidelity_folders", "場所"))
	for place in [["このPC", false, "/home/operator/Documents", "grid"], ["顧客の端末", true, "/", "folder"], ["設定", true, "/etc", "settings"], ["ログ", true, "/var/log", "archive"], ["調査報告", true, "/home/operator", "file"]]:
		var button: Button = _tool(d, str(place[3]), str(place[0]), func(): _navigate(d, str(place[2]), bool(place[1])), str(place[0]))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.flat = false
		button.custom_minimum_size.y = 29
		places.add_child(button)
		place_buttons.append({"button":button,"remote":bool(place[1]),"path":str(place[2])})
		if str(place[0]) == "顧客の端末": places.add_child(HSeparator.new())
	_section(d, places, "ショートカット")
	var network_link: Button = _tool(d,"folder",UI.copy("samba_access_share"),func():d._open_samba_share(),UI.copy("samba_access_share"))
	network_link.name="FilesNetworkShare"; network_link.alignment=HORIZONTAL_ALIGNMENT_LEFT; places.add_child(network_link)
	var new_local: Button = _tool(d, "plus", "新しいメモ", d._new_file, "新しいメモ")
	new_local.alignment = HORIZONTAL_ALIGNMENT_LEFT
	new_local.flat = true
	places.add_child(new_local)

	var right: VBoxContainer = d._box(split, 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var host: Label = d._label("", 13, UI.INK)
	host.autowrap_mode = TextServer.AUTOWRAP_OFF
	host.clip_text = true
	right.add_child(host)
	var tree := Tree.new()
	tree.name = "FileList"
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.allow_rmb_select = true
	tree.columns = 3
	tree.set_column_titles_visible(true)
	tree.set_column_title(0, "名前")
	tree.set_column_title(1, "種類")
	tree.set_column_title(2, "サイズ")
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, false)
	tree.set_column_expand(2, false)
	tree.set_column_custom_minimum_width(1, 84)
	tree.set_column_custom_minimum_width(2, 78)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.add_theme_font_size_override("font_size", 13)
	tree.item_activated.connect(func(): _open_selected(d))
	tree.item_selected.connect(func(): _refresh_selection(d))
	tree.column_title_clicked.connect(func(column, mouse_button):
		if mouse_button != MOUSE_BUTTON_LEFT: return
		var w: Dictionary = d.widgets.files
		w.sort_desc = not bool(w.get("sort_desc",false)) if int(w.get("sort_column",0)) == column else false
		w.sort_column = column
		refresh(d))
	right.add_child(tree)
	var empty := Label.new()
	empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty.add_theme_color_override("font_color", UI.MUTED)
	tree.add_child(empty)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation",3)
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	command_row.add_child(actions)
	actions.visible = true
	var open_button: Button = _tool(d, "external", UI.copy("fidelity_open", "開く"), func(): _open_selected(d), "開く")
	open_button.custom_minimum_size = Vector2(72, 30)
	open_button.name = "FilesOpenSelected"
	actions.add_child(open_button)
	var copy_button: Button = _tool(d, "copy", UI.copy("fidelity_copy", "コピー"), func(): _copy_selected(d), "コピー")
	copy_button.custom_minimum_size = Vector2(72, 30)
	actions.add_child(copy_button)
	var paste_button: Button = _tool(d, "folder", UI.copy("fidelity_paste", "貼り付け"), d._paste_file, "貼り付け")
	paste_button.custom_minimum_size = Vector2(86, 30)
	actions.add_child(paste_button)
	var status: Label = d._label("", 12, UI.MUTED)
	status.name = "FilesSelectionStatus"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.clip_text = true
	var status_bar := PanelContainer.new()
	status_bar.add_theme_stylebox_override("panel", UI.style(UI.OS_PANEL, UI.OS_BORDER, 0, 2, 0))
	var status_row: HBoxContainer = d._row(status_bar, 4)
	status_row.add_child(status)
	p.add_child(status_bar)
	d.widgets.files = {"path": path, "search": search, "list": tree, "tree": tree, "open": open_button, "copy": copy_button, "paste": paste_button, "places": places, "places_scroll": places_scroll, "place_buttons":place_buttons, "breadcrumb_scroll":breadcrumb_scroll, "host": host, "status": status, "history": [], "forward_history": [], "backing": false, "location": {"path": d.file_directory, "remote": d.file_remote}, "back": back, "forward": forward, "breadcrumb": breadcrumb, "empty": empty}
	d.path_edit = path
	d.widgets.files.command_strip = command_strip
	var saved_selections: Variant = d.game.state.get("desktop_sessions", {}).get(d.session_key, {}).get("file_selections", {})
	d.widgets.files.selection_by_location = saved_selections.duplicate(true) if saved_selections is Dictionary else {}
	d.file_list = tree
	var network: VBoxContainer=d._scroll(right)
	d.widgets.files.network=network; d.widgets.files.network_scroll=network.get_parent()
	d.widgets.files.network_link=network_link; d.widgets.files.normal_actions=actions; d.widgets.files.up=up
	network.get_parent().hide()
	var context := PopupMenu.new(); parent.add_child(context); d.widgets.files.context=context
	for item in [["開く",0],["コピー",1],["貼り付け",2],[UI.copy("os_properties"),3]]: context.add_item(item[0],item[1])
	context.id_pressed.connect(func(id):
		if id == 0: _open_selected(d)
		elif id == 1: _copy_selected(d)
		elif id == 2: d._paste_file()
		elif id == 3: _properties(d))
	tree.item_mouse_selected.connect(func(_position, mouse_button):
		if mouse_button != MOUSE_BUTTON_RIGHT: return
		context.set_item_disabled(1, d.widgets.files.copy.disabled)
		context.set_item_disabled(2, d.clipboard_path.is_empty())
		context.position=Vector2i(d.get_viewport().get_mouse_position()); context.popup())
	refresh(d)

static func _properties(d) -> void:
	var item = _selected_item(d)
	if item == null: return
	var dialog := AcceptDialog.new(); dialog.title=UI.copy("os_properties"); dialog.theme=d.windows.files.content.theme
	dialog.dialog_text="%s\n\n%s\n%s  ·  %s" % [item.get_text(0),str(item.get_metadata(0)).trim_prefix("workstation:"),item.get_text(1),item.get_text(2)]
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free)
	d.add_child(dialog); dialog.popup_centered(Vector2i(460,200))

static func _edit_address(d) -> void:
	var w: Dictionary = d.widgets.files
	w.breadcrumb_scroll.hide()
	w.path.show()
	w.path.grab_focus()
	w.path.select_all()

static func navigate(d, path: String, remote := true) -> void:
	if d._samba_v2() and (path.begins_with("//") or path.begins_with("\\\\")):
		var parts:=path.replace("\\","/").split("/",false)
		if parts.size()==2 and parts[0]=="files01.client.test": d._open_samba_share(parts[1]); return
	d.samba_ui.network_open=false
	var w: Dictionary = d.widgets.files
	var next := path.strip_edges()
	if next.is_empty(): next = "/"
	if remote: next = d.game._vm()._path(next)
	elif not d.game.state.os_files.keys().any(func(file): return str(file).begins_with(next.trim_suffix("/")+"/")):
		next = preload("res://scripts/profile_paths.gd").home(next)
	var current: Dictionary = w.location
	var changed := str(current.get("path", "")) != next or bool(current.get("remote", false)) != remote
	if changed:
		w.history.append(current.duplicate())
		w.forward_history.clear()
	d.file_remote = remote
	d.file_directory = next
	w.path.text = next
	refresh(d)

static func _navigate(d, path: String, remote := true) -> void:
	navigate(d, path, remote)

static func _back(d) -> void:
	var w: Dictionary = d.widgets.files
	if w.history.is_empty(): return
	d.samba_ui.network_open = false
	var previous: Dictionary = w.history.pop_back()
	w.forward_history.append(w.location.duplicate())
	d.file_remote = bool(previous.get("remote", false))
	d.file_directory = str(previous.get("path", "/"))
	w.path.text = d.file_directory
	refresh(d)

static func _forward(d) -> void:
	var w: Dictionary = d.widgets.files
	if w.forward_history.is_empty(): return
	d.samba_ui.network_open = false
	var next: Dictionary = w.forward_history.pop_back()
	w.history.append(w.location.duplicate())
	d.file_remote = bool(next.get("remote", false))
	d.file_directory = str(next.get("path", "/"))
	w.path.text = d.file_directory
	refresh(d)

static func _selected_item(d):
	return d.widgets.files.tree.get_selected()

static func _location_key(location: Dictionary) -> String:
	return ("remote:" if bool(location.get("remote", false)) else "local:") + str(location.get("path", "/"))

static func _copy_target(directory: String, source_path: String, existing_paths: Array) -> String:
	var filename := source_path.get_file()
	var extension := filename.get_extension()
	var stem := filename.trim_suffix("." + extension) if not extension.is_empty() else filename
	var candidate_name := "copy-" + filename
	var candidate := directory.path_join(candidate_name)
	var suffix := 2
	while existing_paths.any(func(path): return str(path).nocasecmp_to(candidate) == 0):
		var numbered_name := "copy-" + stem + " (" + str(suffix) + ")" + ("." + extension if not extension.is_empty() else "")
		candidate = directory.path_join(numbered_name)
		suffix += 1
	return candidate

static func _copy_selected(d) -> void:
	var item = _selected_item(d)
	if item == null: return
	d.clipboard_path = str(item.get_metadata(0))
	_refresh_selection(d)

static func _open_selected(d) -> void:
	var item = _selected_item(d)
	if item == null: return
	var path := str(item.get_metadata(0))
	if path.ends_with("/"):
		_navigate(d, path.trim_prefix("workstation:").trim_suffix("/"), d.file_remote)
	else:
		d._open_editor(path)

static func refresh(d) -> void:
	if not d.widgets.has("files"): return
	var w: Dictionary = d.widgets.files
	var network: bool=d._samba_v2() and bool(d.samba_ui.get("network_open",false))
	w.network_scroll.visible=network; w.network_link.visible=d._samba_v2()
	w.tree.visible=not network; w.normal_actions.visible=not network; w.search.visible=not network
	w.command_strip.visible=not network; w.host.visible=not network
	w.up.disabled=network
	UI.os_navigation(w.network_link, network, UI.app_accent("files"))
	if network:
		for place in w.place_buttons: UI.os_navigation(place.button, false, UI.app_accent("files"))
		w.tree.clear(); w.back.disabled=true; w.forward.disabled=true
		w.path.text="//files01.client.test/"+str(d.samba_ui.get("access_share","share"))
		w.host.text=w.path.text
		d._clear(w.breadcrumb); w.breadcrumb.add_child(d._label(w.path.text,13))
		d._clear(w.network); preload("res://scripts/os_smb_browser.gd").render(d,w.network)
		w.status.text = str(d.samba_ui.get("access_selected", ""))
		return
	var path := str(w.path.text).strip_edges()
	d.file_directory = path if not path.is_empty() else "/"
	w.path.text = d.file_directory
	w.tree.clear()
	var location := {"path": d.file_directory, "remote": d.file_remote}
	var selected_meta := str(w.selection_by_location.get(_location_key(location), ""))
	w.location = location
	w.back.disabled = w.history.is_empty()
	w.forward.disabled = w.forward_history.is_empty()
	var selected_path := ""
	for place in w.place_buttons:
		if d.file_remote == bool(place.remote) and d.file_directory.begins_with(str(place.path)) and str(place.path).length() > selected_path.length(): selected_path=str(place.path)
	for place in w.place_buttons:
		UI.os_navigation(place.button, d.file_remote == bool(place.remote) and str(place.path) == selected_path, UI.app_accent("files"))
	_update_breadcrumb(d)
	var query := str(w.search.text).strip_edges().to_lower()
	var info: Dictionary = d.game.vm_info()
	var connected := bool(info.get("connected", false))
	w.host.text = (("顧客端末  ·  " + str(info.get("host", ""))) if d.file_remote else "このPC")
	var paths: Array = d.game.vm_list(d.file_directory) if d.file_remote else d.game.state.os_files.keys()
	if not d.file_remote:
		var folders: Array = []
		for file_path in paths:
			var prefix: String = d.file_directory.trim_suffix("/")+"/"
			if str(file_path).begins_with(prefix):
				var tail: String = str(file_path).trim_prefix(prefix)
				if "/" in tail:
					var folder: String = prefix+tail.get_slice("/",0)+"/"
					if folder not in folders: folders.append(folder)
		paths.append_array(folders)
	var sort_column := int(w.get("sort_column",0))
	var descending := bool(w.get("sort_desc",false))
	paths.sort_custom(func(a,b):
		var left := str(a); var right := str(b)
		if left.ends_with("/") != right.ends_with("/"): return left.ends_with("/")
		if sort_column == 2 and not left.ends_with("/"):
			var lsize: int = d._read(left if d.file_remote else "workstation:"+left).to_utf8_buffer().size()
			var rsize: int = d._read(right if d.file_remote else "workstation:"+right).to_utf8_buffer().size()
			if lsize != rsize: return lsize > rsize if descending else lsize < rsize
		return left.naturalnocasecmp_to(right) > 0 if descending else left.naturalnocasecmp_to(right) < 0)
	for column in 3:
		w.tree.set_column_title(column, ["名前","種類","サイズ"][column]+((" ↓" if descending else " ↑") if column == sort_column else ""))
	var visible := 0
	var root: TreeItem = w.tree.create_item()
	for raw in paths:
		var item_path := str(raw)
		if not d.file_remote and item_path.trim_suffix("/").get_base_dir() != d.file_directory: continue
		var is_dir := item_path.ends_with("/")
		var name := item_path.trim_suffix("/").get_file()
		if not query.is_empty() and not name.to_lower().contains(query): continue
		var meta := item_path if d.file_remote else "workstation:" + item_path
		var content: String = "" if is_dir else (str(d.game.state.os_files.get(item_path, "")) if not d.file_remote else d.game.vm_read(item_path))
		var item: TreeItem = w.tree.create_item(root)
		item.set_text(0, name)
		item.set_text(1, "フォルダー" if is_dir else "テキスト")
		item.set_text(2, "—" if is_dir else "%d B" % content.to_utf8_buffer().size())
		item.set_icon(0, FOLDER if is_dir else DOCUMENT)
		item.set_icon_max_width(0, 18)
		item.set_metadata(0, meta)
		item.set_tooltip_text(0, item_path)
		if meta == selected_meta: item.select(0)
		visible += 1
	w.empty.visible = visible == 0
	w.empty.text = "顧客端末に未接続です" if d.file_remote and not connected else ("一致するファイルはありません" if not query.is_empty() else "このフォルダーは空です")
	if d.file_remote and not connected:
		w.status.text = "未接続"
		w.open.disabled = true
		w.copy.disabled = true
		w.paste.disabled = d.clipboard_path.is_empty()
	elif visible == 0:
		w.status.text = "0 件"
		w.open.disabled = true
		w.copy.disabled = true
		w.paste.disabled = d.clipboard_path.is_empty()
	else:
		w.status.text = "%d 件" % visible
		w.open.disabled = true
		w.copy.disabled = true
		w.paste.disabled = d.clipboard_path.is_empty()
	_refresh_selection(d)

static func _update_breadcrumb(d) -> void:
	if not d.widgets.files.has("breadcrumb"): return
	var row: HBoxContainer = d.widgets.files.breadcrumb
	d._clear(row)
	var path := str(d.file_directory).strip_edges()
	var remote: bool = d.file_remote
	var root_label := "顧客端末" if remote else "このPC"
	var root_path := "/"
	var root: Button = d._button(root_label, func(): navigate(d, root_path, remote))
	root.flat = true
	root.tooltip_text = root_path
	row.add_child(root)
	var relative := path
	if not remote and relative.begins_with(root_path): relative = relative.trim_prefix(root_path)
	var parts: PackedStringArray = relative.split("/", false)
	var built := root_path if not remote else "/"
	for part in parts:
		if part.is_empty(): continue
		row.add_child(d._label("›", 12, UI.MUTED))
		built = built.path_join(part)
		var crumb_path := built
		var crumb: Button = d._button(part, func(): navigate(d, crumb_path, remote))
		crumb.flat = true
		crumb.tooltip_text = crumb_path
		row.add_child(crumb)

static func _refresh_selection(d) -> void:
	var w: Dictionary = d.widgets.files
	var item = _selected_item(d)
	if item == null: return
	var meta := str(item.get_metadata(0))
	w.selection_by_location[_location_key(w.location)] = meta
	var path := meta.trim_prefix("workstation:")
	var is_dir := meta.ends_with("/")
	w.open.text = "開く" if is_dir else "編集"
	w.open.tooltip_text = "フォルダーを開く" if is_dir else "選択したファイルをエディターで開く"
	w.open.disabled = false
	w.copy.disabled = is_dir
	w.paste.disabled = d.clipboard_path.is_empty()
	if is_dir:
		w.status.text = "選択中  ·  %s  ·  フォルダー" % path.get_file()
		return
	var content: String = str(d.game.state.os_files.get(path, "")) if meta.begins_with("workstation:") else d.game.vm_read(path)
	w.status.text = "選択中  ·  %s  ·  UTF-8  ·  %d B" % [path.get_file(), content.to_utf8_buffer().size()]
