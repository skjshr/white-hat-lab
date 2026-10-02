extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const BLUE := Color("006a9e")
const INK := Color("252525")
const MUTED := Color("676767")
const LINE := Color("e7e7e7")

static func copy(key: String) -> String:
	return UI.copy("portal_"+key)

static func storage_copy(key: String, fallback: String = "") -> String:
	return UI.copy(key, fallback)

static func _external_storage(snapshot: Dictionary) -> Dictionary:
	var value: Variant = snapshot.get("external_storage", {})
	return value if value is Dictionary else {}

static func _storage_source(storage: Dictionary) -> String:
	var host := str(storage.get("host", ""))
	var share := str(storage.get("share", ""))
	if host.is_empty() or share.is_empty(): return ""
	return "//%s/%s" % [host, share]

static func _storage_error_key(storage: Dictionary) -> String:
	match str(storage.get("error", "")):
		"storage_denied": return "branch_storage_denied"
		"missing_file": return "branch_storage_missing"
		"provider_unavailable": return "branch_storage_unavailable"
	return "branch_storage_unavailable"

static func _storage_status(d, parent: Node, storage: Dictionary) -> void:
	if not bool(storage.get("enabled", false)): return
	var box := VBoxContainer.new()
	box.name = "BranchStorageStatus"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var failed := not bool(storage.get("ok", false))
	parent.add_child(box)
	box.add_theme_constant_override("separation", 3)
	var title := storage_copy("branch_storage_label", "External storage")
	if failed:
		title = storage_copy(_storage_error_key(storage), "External storage unavailable")
	var title_label := label(d, box, title, 12, UI.RED if failed else INK)
	if failed: title_label.name = "BranchStorageError"
	if not failed:
		label(d, box, "SMB/CIFS  ·  " + _storage_source(storage), 11, MUTED)
		var path := str(storage.get("path", ""))
		if not path.is_empty():
			var path_label := label(d, box, path, 11, MUTED)
			path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		var code := int(storage.get("code", 0))
		if code > 0: label(d, box, "HTTP %d" % code, 11, MUTED)
	var refresh := button(d, box, UI.copy("business_refresh", "Refresh"), "PortalStorageRefresh", func(): d._browse_url(d.browser_url, false))
	refresh.custom_minimum_size.y = 30

static func experience_copy(key: String, fallback: String) -> String:
	return UI.copy("experience_"+key, fallback)

static func label(d,parent: Node,text: String,size:=14,color:=INK) -> Label:
	var node: Label=d._label(text,size,color);node.add_theme_font_override("font",UI.font(600 if size>=18 else 400));node.autowrap_mode=TextServer.AUTOWRAP_OFF;node.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;node.clip_text=true;node.tooltip_text=text;node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(node);return node

static func fixed_label(d,parent: Node,text: String,size:=14,color:=INK) -> Label:
	var node := label(d,parent,text,size,color)
	node.clip_text = false
	node.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node

static func style_editor(d,node: TextEdit) -> void:
	node.add_theme_stylebox_override("normal",UI.style(Color.WHITE,LINE,10,10,3));node.add_theme_stylebox_override("focus",UI.style(Color.WHITE,BLUE,10,10,3))
	node.add_theme_color_override("font_color",INK);node.add_theme_color_override("font_readonly_color",MUTED)
	if d.mono!=null:node.add_theme_font_override("font",d.mono)

static func button(d,parent: Node,text: String,name: String,action: Callable) -> Button:
	var node: Button=d._button(text,action);node.name=name;node.custom_minimum_size.y=34
	node.add_theme_font_size_override("font_size",maxi(13,int(13*float(d.game.settings.get("text_scale",1.0)))))
	for kind in ["normal","hover","pressed","focus"]:
		node.add_theme_stylebox_override(kind,UI.style(Color("e8f3fa") if kind in ["hover","pressed"] else Color.TRANSPARENT,BLUE if kind=="focus" else Color.TRANSPARENT,10,5,8))
	for kind in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:node.add_theme_color_override(kind,INK)
	parent.add_child(node);return node

static func panel(parent: Node,color: Color=Color.WHITE,padding:=12) -> VBoxContainer:
	var frame:=PanelContainer.new();frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frame.add_theme_stylebox_override("panel",UI.style(color,LINE,padding,padding,2));parent.add_child(frame)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);frame.add_child(box);return box

static func persist(d) -> void:
	d._save_session(false)

static func rerender(d) -> void:
	persist(d);d._render_portal()

static func _is_compact(d) -> bool:
	return float(d.windows.browser.size.x) < 1050 * float(d.game.settings.get("text_scale", 1.0))

static func _apply_live_layout(d, page: Control) -> void:
	if not is_instance_valid(page): return
	var compact := _is_compact(d)
	var shell := page.find_child("PortalShell", true, false) as BoxContainer
	var nav_frame := page.find_child("PortalNavigation", true, false) as Control
	var nav_primary := page.find_child("PortalNavPrimary", true, false) as BoxContainer
	var nav_fill := page.find_child("PortalNavFill", true, false) as Control
	var nav_status := page.find_child("PortalNavStatus", true, false) as BoxContainer
	if shell != null:
		shell.vertical = compact
		shell.custom_minimum_size.y = maxf(460, float(d.windows.browser.size.y) - 153)
	if nav_frame != null: nav_frame.custom_minimum_size = Vector2(0, 100) if compact else Vector2(260, 0)
	if nav_primary != null: nav_primary.vertical = not compact
	if nav_fill != null: nav_fill.visible = not compact
	if nav_status != null: nav_status.vertical = not compact
	var split := page.find_child("PortalFileSplit", true, false) as BoxContainer
	if split != null:
		split.vertical = compact
		split.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_EXPAND_FILL
		var list := split.find_child("PortalFileList", false, false) as Control
		var detail_frame := split.find_child("PortalDetailsFrame", false, false) as Control
		var state: Dictionary = d.portal_ui
		var has_details := detail_frame != null and (bool(state.get("details", false)) or bool(state.get("sharing", not compact)))
		if list != null: list.visible = not compact or not has_details
		if detail_frame != null:
			detail_frame.visible = has_details
			split.move_child(detail_frame, 0 if compact else 1)
			detail_frame.custom_minimum_size = Vector2(0, 320) if compact else Vector2(320, 0)
			detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
			if not compact:
				var style := UI.style(Color.WHITE, LINE, 12, 12, 0)
				style.set_border_width_all(0)
				style.border_width_left = 1
				detail_frame.add_theme_stylebox_override("panel", style)
		var grid := page.find_child("PortalFileGrid", true, false) as GridContainer
		if grid != null: grid.columns = 2 if compact else 3
	var panes := page.find_child("PortalVersionPanes", true, false) as BoxContainer
	if panes != null: panes.vertical = compact

static func _file_content(d, path: String) -> String:
	var machine: Variant = null
	if d.game != null and d.game.has_method("_vm"): machine = d.game._vm()
	if machine != null and machine.has_method("portal_storage_read"):
		return str(machine.portal_storage_read(path))
	return str(d.game.vm_read(path))

static func reset_response(d) -> void:
	d._portal_restore_draft()

static func show_files(d,shared: bool=false) -> void:
	d.portal_ui["view"]="files";d.portal_ui["filter"]="shared" if shared else "all";d.portal_ui["details"]=false;d.portal_ui.erase("sharing");d._browse_url(d.PORTAL_URL,true)

static func app_button(d, parent: Node, icon: String, name: String, action: Callable, tooltip: String = "") -> Button:
	var node := button(d, parent, "", name, action)
	node.custom_minimum_size = Vector2(34, 34)
	node.tooltip_text = tooltip if not tooltip.is_empty() else copy("details")
	var slot := HBoxContainer.new(); slot.mouse_filter = Control.MOUSE_FILTER_IGNORE; slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); slot.alignment = BoxContainer.ALIGNMENT_CENTER; node.add_child(slot)
	Glyph.add_to(slot, icon, 20, Color.WHITE)
	return node

static func run(d,command: String) -> void:
	var raw := str(d._portal_command(command))
	var result = JSON.parse_string(raw)
	var sound = d.get_node_or_null("/root/Soundscape")
	if is_instance_valid(sound) and result is Dictionary:
		sound.play_ui("work_success" if bool(result.get("ok",false)) else "work_failure")
	if command.begins_with("portal share ") and result is Dictionary and bool(result.get("ok", false)):
		var drafts: Dictionary = d.portal_ui.get("share_drafts", {})
		drafts.erase(str(d.portal_ui.get("selected_path", "")) + "|" + command.get_slice(" ", 2))
		d.portal_ui["share_drafts"] = drafts
	rerender(d)

static func render(d,parent: VBoxContainer) -> void:
	var state: Dictionary=d.portal_ui;var snap: Dictionary=d.game._vm().portal_snapshot()
	var backdrop:=PanelContainer.new();backdrop.add_theme_stylebox_override("panel",UI.style(BLUE,Color.TRANSPARENT,8,0,0));backdrop.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(backdrop)
	var backdrop_style: StyleBoxFlat=backdrop.get_theme_stylebox("panel");backdrop_style.content_margin_bottom=8
	var page:=VBoxContainer.new();page.add_theme_constant_override("separation",0);backdrop.add_child(page)
	var top_row:=HBoxContainer.new();top_row.custom_minimum_size.y=50;top_row.add_theme_constant_override("separation",18);page.add_child(top_row)
	Glyph.add_to(top_row,"network",34,Color.WHITE)
	var home:=button(d,top_row,"Nextcloud","PortalHome",func():show_files(d));home.add_theme_color_override("font_color",Color.WHITE)
	app_button(d,top_row,"file","PortalAppFiles",func():show_files(d),copy("all_files"))
	app_button(d,top_row,"network","PortalAppShared",func():show_files(d,true),copy("shared"))
	var app_spacer:=Control.new();app_spacer.custom_minimum_size.x=4;top_row.add_child(app_spacer)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top_row.add_child(spacer)
	var account:=fixed_label(d,top_row,"OP",14,Color.WHITE);account.size_flags_horizontal=Control.SIZE_SHRINK_END;account.tooltip_text=d._player_display_name()
	var compact:=_is_compact(d)
	var shell:=BoxContainer.new();shell.name="PortalShell";shell.vertical=compact;shell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;shell.add_theme_constant_override("separation",0);shell.custom_minimum_size.y=maxf(460,float(d.windows.browser.size.y)-153);page.add_child(shell)
	var nav_frame:=PanelContainer.new();nav_frame.name="PortalNavigation";nav_frame.custom_minimum_size=Vector2(0,100) if compact else Vector2(260,0);nav_frame.add_theme_stylebox_override("panel",UI.style(Color("d5eaf3"),Color.TRANSPARENT,8,8,0));shell.add_child(nav_frame)
	var nav_style: StyleBoxFlat=nav_frame.get_theme_stylebox("panel");nav_style.corner_radius_top_left=16;nav_style.corner_radius_bottom_left=16
	var nav:=VBoxContainer.new();nav.add_theme_constant_override("separation",4);nav_frame.add_child(nav)
	var nav_primary:=BoxContainer.new();nav_primary.name="PortalNavPrimary";nav_primary.vertical=not compact;nav_primary.add_theme_constant_override("separation",4);nav.add_child(nav_primary)
	var search:=LineEdit.new();search.name="PortalSearch";search.placeholder_text=UI.copy("os_search");search.text=str(state.get("query",""));search.custom_minimum_size=Vector2(160*float(d.game.settings.get("text_scale",1.0)),34);nav_primary.add_child(search)
	search.add_theme_stylebox_override("normal",UI.style(Color.WHITE,Color("949494"),10,5,8))
	search.text_submitted.connect(func(value):state["query"]=value;rerender(d))
	for item in [["all_files","all","files"],["shared","shared","team"]]:
		var active:=str(state.get("view","files"))=="files" and str(state.get("filter","all"))==str(item[1])
		var entry:=button(d,nav_primary,copy(item[0]),"PortalNav_"+str(item[1]),func():show_files(d,str(item[1])=="shared"));entry.alignment=HORIZONTAL_ALIGNMENT_LEFT;entry.icon=UI.symbol(str(item[2]));entry.expand_icon=true;entry.add_theme_constant_override("icon_max_width",18);entry.custom_minimum_size.y=38
		entry.add_theme_stylebox_override("normal",UI.style(BLUE if active else Color.TRANSPARENT,Color.TRANSPARENT,10,7,8));entry.add_theme_color_override("font_color",Color.WHITE if active else INK)
	var fill:=Control.new();fill.name="PortalNavFill";fill.size_flags_vertical=Control.SIZE_EXPAND_FILL;nav.add_child(fill)
	var used:=0
	for file in snap.get("files",[]):used+=int(file.get("size",0))
	var nav_status:=BoxContainer.new();nav_status.name="PortalNavStatus";nav_status.vertical=not compact;nav_status.add_theme_constant_override("separation",8);nav.add_child(nav_status)
	label(d,nav_status,str(used)+" B",13,MUTED)
	_storage_status(d,nav_status,_external_storage(snap))
	var config:=button(d,nav_primary,copy("service_config"),"PortalConfig",func():d._show_app("editor");d._open_editor(str(d.game.vm_info().config_path)));config.alignment=HORIZONTAL_ALIGNMENT_LEFT
	var workspace:=PanelContainer.new();workspace.name="PortalWorkspace";workspace.size_flags_horizontal=Control.SIZE_EXPAND_FILL;workspace.add_theme_stylebox_override("panel",UI.style(Color.WHITE,Color.TRANSPARENT,12,8,0));shell.add_child(workspace)
	var workspace_style: StyleBoxFlat=workspace.get_theme_stylebox("panel");workspace_style.corner_radius_top_right=16;workspace_style.corner_radius_bottom_right=16
	var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",0);workspace.add_child(body)
	if str(state.get("view","files"))=="preview":preview(d,body,state)
	else:files(d,body,state,snap,compact)
	if not page.has_meta("portal_resize_callback"):
		var resize_callback := func(): _apply_live_layout(d,page)
		page.set_meta("portal_resize_callback",resize_callback)
		page.resized.connect(resize_callback)
	_apply_live_layout(d,page)

static func files(d,parent: VBoxContainer,state: Dictionary,snap: Dictionary,compact: bool) -> void:
	var split:=BoxContainer.new();split.name="PortalFileSplit";split.vertical=compact;split.add_theme_constant_override("separation",12);split.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(split)
	if not compact: split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var list:=VBoxContainer.new();list.name="PortalFileList";list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",0);split.add_child(list)
	var viewbar:=HBoxContainer.new();viewbar.custom_minimum_size.y=48;viewbar.add_theme_constant_override("separation",4);list.add_child(viewbar)
	label(d,viewbar,copy("shared" if str(state.get("filter","all"))=="shared" else "all_files"),16)
	var toolbar_space:=Control.new();toolbar_space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;viewbar.add_child(toolbar_space)
	var list_view:=button(d,viewbar,"☰","PortalView_list",func():state["file_view"]="list";rerender(d));list_view.tooltip_text=experience_copy("list_view","List");list_view.disabled=str(state.get("file_view","list"))=="list"
	var grid_view:=button(d,viewbar,"⊞","PortalView_grid",func():state["file_view"]="grid";rerender(d));grid_view.tooltip_text=experience_copy("grid_view","Grid");grid_view.disabled=str(state.get("file_view","list"))=="grid"
	var grid_mode := str(state.get("file_view","list"))=="grid"
	if not grid_mode:
		var head:=HBoxContainer.new();head.custom_minimum_size.y=44;list.add_child(head);label(d,head,copy("name"),13,MUTED);fixed_label(d,head,copy("size"),13,MUTED).size_flags_horizontal=Control.SIZE_SHRINK_END
		list.add_child(HSeparator.new())
	var grid: GridContainer = null
	if grid_mode:
		grid=GridContainer.new();grid.name="PortalFileGrid";grid.columns=2 if compact else 3;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10);list.add_child(grid)
	var rows: Array=snap.get("files",[]);var shown:=0;var visible_paths: Array[String]=[]
	for index in rows.size():
		var file: Dictionary=rows[index];var path:=str(file.path)
		var shared:=false
		for share in snap.get("shares",[]):
			if str(share.get("path",""))==path and int(share.get("permissions",0))>0:shared=true
		if str(state.get("filter","all"))=="shared" and not shared:continue
		if not str(state.get("query","")).is_empty() and not str(file.name).to_lower().contains(str(state.query).to_lower()):continue
		shown+=1
		visible_paths.append(path)
		var row: BoxContainer=VBoxContainer.new() if grid_mode else HBoxContainer.new();row.add_theme_constant_override("separation",8)
		if grid_mode:
			row.custom_minimum_size=Vector2(170,82);grid.add_child(row)
		else:
			var row_frame:=PanelContainer.new();row_frame.add_theme_stylebox_override("panel",UI.style(Color("f1f1f1") if str(state.get("selected_path",""))==path and bool(state.get("details",false)) else Color.WHITE,LINE,4,0,0));row_frame.custom_minimum_size.y=48;list.add_child(row_frame);row_frame.add_child(row)
		Glyph.add_to(row,"file",24,BLUE)
		var open:=button(d,row,str(file.name),"PortalFile_"+str(index),func():state["selected_path"]=path;state["details"]=true;state["detail_tab"]="sharing";rerender(d));open.flat=true;open.alignment=HORIZONTAL_ALIGNMENT_LEFT;open.size_flags_horizontal=Control.SIZE_EXPAND_FILL;open.clip_text=true
		fixed_label(d,row,str(file.size)+" B",12,MUTED).size_flags_horizontal=Control.SIZE_SHRINK_END
		var share_button:=button(d,row,"⋯","PortalShareFile_"+str(index),func():state["selected_path"]=path;state["details"]=true;state["sharing"]=true;state["detail_tab"]="sharing";rerender(d));share_button.tooltip_text=copy("details")
	if shown==0:label(d,list,copy("no_files"),14,MUTED)
	var selected:=str(state.get("selected_path",""))
	if not selected.is_empty() and selected not in visible_paths:selected="";state["details"]=false
	if selected.is_empty() and not visible_paths.is_empty():selected=visible_paths[0]
	state["selected_path"]=selected
	if not selected.is_empty():
		var details:=detail_sidebar(d,split,state,snap,selected,compact)
		details.name="PortalDetailsPane"
		var detail_frame:=details.get_parent() as Control
		detail_frame.name="PortalDetailsFrame"
		var show_details:=bool(state.get("details",false)) or bool(state.get("sharing",not compact))
		detail_frame.visible=show_details
		list.visible=not compact or not show_details
		if compact and show_details:split.move_child(detail_frame,0)
		var content_host: VBoxContainer=details if compact else list
		if str(state.get("detail_tab","sharing"))=="versions":_version_preview(d,content_host,state,selected,compact)
		elif bool(state.get("details",false)):
			_label_grid(d,content_host,_file_content(d,selected),"PortalAdminGrid")
			var source: VBoxContainer=d._disclosure(content_host,copy("file_content"))
			var content:=TextEdit.new();content.name="PortalAdminContent";content.editable=false;content.text=_file_content(d,selected);content.custom_minimum_size.y=110;style_editor(d,content);source.add_child(content)
			button(d,content_host,copy("close"),"PortalCloseContent",func():state["details"]=false;state["sharing"]=false;rerender(d))

static func _node_token(value: String) -> String:
	var token := value
	for ch in ["/", "\\", ":", " ", "?", "&", "="]:
		token = token.replace(ch, "_")
	return token

static func _portal_file(snap: Dictionary, path: String) -> Dictionary:
	for item in snap.get("files", []):
		if item is Dictionary and str(item.get("path", "")) == path: return item
	return {}

static func _detail_tab_button(d, parent: Node, text: String, name: String, active: bool, action: Callable) -> Button:
	var tab := button(d, parent, text, name, action)
	tab.custom_minimum_size.y = 38
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_stylebox_override("normal", UI.style(Color.WHITE if active else Color("f7f8f9"), BLUE if active else Color.TRANSPARENT, 0, 5, 2 if active else 0))
	tab.add_theme_stylebox_override("hover", UI.style(Color("e8f3fa"), BLUE, 0, 5, 2))
	tab.add_theme_color_override("font_color", BLUE if active else MUTED)
	return tab

static func detail_sidebar(d, split: BoxContainer, state: Dictionary, snap: Dictionary, selected: String, compact: bool) -> VBoxContainer:
	var sidebar := panel(split)
	var sidebar_parent: Node = sidebar.get_parent()
	sidebar_parent.custom_minimum_size.x = 0 if compact else 320
	sidebar_parent.custom_minimum_size.y = 320 if compact else 0
	if not compact:
		sidebar_parent.size_flags_horizontal = Control.SIZE_FILL
		sidebar_parent.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var sidebar_style := UI.style(Color.WHITE, LINE, 12, 12, 0)
		sidebar_style.set_border_width_all(0)
		sidebar_style.border_width_left = 1
		sidebar_parent.add_theme_stylebox_override("panel", sidebar_style)
	var file := _portal_file(snap, selected)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	sidebar.add_child(heading)
	Glyph.add_to(heading, "file", 24, BLUE)
	var title := label(d, heading, str(file.get("name", selected.get_file())), 17)
	title.clip_text = true
	var close := button(d, heading, "×", "PortalCloseSharing", func(): state["details"] = false; state["sharing"] = false; rerender(d))
	close.tooltip_text = copy("close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	sidebar.add_child(meta)
	fixed_label(d, meta, "%d B" % int(file.get("size", 0)), 11, MUTED)
	var sha := str(file.get("sha256", ""))
	if not sha.is_empty():
		var hash_label := fixed_label(d, meta, sha.left(16), 11, MUTED)
		hash_label.tooltip_text = sha
		hash_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	sidebar.add_child(tabs)
	var tab_name := str(state.get("detail_tab", "sharing"))
	_detail_tab_button(d, tabs, storage_copy("portal_sharing", "Sharing"), "PortalDetailSharing", tab_name == "sharing", func(): state["detail_tab"] = "sharing"; state["sharing"] = true; rerender(d))
	_detail_tab_button(d, tabs, storage_copy("portal_activity", "Activity"), "PortalDetailActivity", tab_name == "activity", func(): state["detail_tab"] = "activity"; state["sharing"] = true; rerender(d))
	_detail_tab_button(d, tabs, storage_copy("portal_versions", "Versions"), "PortalDetailVersions", tab_name == "versions", func(): state["detail_tab"] = "versions"; state["sharing"] = true; rerender(d))
	sidebar.add_child(HSeparator.new())
	match tab_name:
		"activity": _detail_activity(d, sidebar, snap, selected)
		"versions": _detail_versions(d, sidebar, state, snap, selected)
		_: _detail_sharing(d, sidebar, state, snap, selected)
	return sidebar

static func _detail_sharing(d, sidebar: VBoxContainer, state: Dictionary, snap: Dictionary, selected: String) -> void:
	var share_title := label(d, sidebar, storage_copy("portal_sharing", "Sharing"), 14, BLUE)
	share_title.custom_minimum_size.y = 28
	for role in ["staff", "partner", "public"]: share_row(d, sidebar, state, snap, selected, role)
	button(d, sidebar, copy("preview"), "PortalPreview", func(): d._portal_stash_draft(); state["view"] = "preview"; state["role"] = "partner"; state["age"] = "current"; reset_response(d); rerender(d))
	var result: Dictionary = state.get("command_result", {})
	if not result.is_empty():
		var error := str(result.get("error", "operation_failed")); error = {"file_not_found":"file_missing", "legacy_model":"unsupported_model", "public_write_forbidden":"invalid_permission"}.get(error, error)
		var message := copy("saved") if bool(result.get("ok", false)) else copy("error_" + error)
		var result_label := label(d, sidebar, message if not message.is_empty() else copy("error_operation_failed"), 13, UI.GREEN if bool(result.get("ok", false)) else UI.RED)
		result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
static func _actor(actor: String) -> String:
	return copy(str({"operator":"actor_operator","current":"staff","former":"staff"}.get(actor,actor))) if actor in ["operator","staff","partner","public","current","former"] else actor

static func _version_open(d, state: Dictionary, version_id: String) -> void:
	state["selected_version"]=version_id
	state["detail_tab"]="versions"
	run(d,"portal version "+version_id)

static func _detail_activity(d, sidebar: VBoxContainer, snap: Dictionary, selected: String) -> void:
	var rows: Array=snap.get("activity",[]).filter(func(item):return str(item.get("path",""))==selected)
	if rows.is_empty():label(d,sidebar,copy("activity_empty"),13,MUTED);return
	for item in rows:
		var row:=VBoxContainer.new();row.add_theme_constant_override("separation",4);sidebar.add_child(row)
		label(d,row,copy("action_"+str(item.action)),14)
		label(d,row,(copy("revision") % int(item.sequence))+" · "+_actor(str(item.actor)),12,MUTED)
		if str(item.action)=="share":
			var permission:=int(item.get("permissions",0))
			label(d,row,copy(str(item.get("role","")))+" · "+copy("can_edit" if permission==3 else "read_only" if permission==1 else "no_access"),12,MUTED)
			label(d,row,copy("expiration")+" · "+copy(str({"7d":"seven_days","30d":"thirty_days"}.get(str(item.get("expires","")),"unlimited"))),12,MUTED)
		var version_id:=str(item.get("version_id",""))
		if not version_id.is_empty():button(d,row,copy("activity_version"),"PortalActivityVersion_"+_node_token(str(item.id)),func():_version_open(d,d.portal_ui,version_id))
		sidebar.add_child(HSeparator.new())

static func _detail_versions(d, sidebar: VBoxContainer, state: Dictionary, snap: Dictionary, selected: String) -> void:
	var versions: Array=snap.get("versions",[]).filter(func(item):return str(item.get("path",""))==selected)
	label(d,sidebar,copy("version_current"),14,BLUE)
	var file:=_portal_file(snap,selected)
	label(d,sidebar,"%d B · %s" % [int(file.get("size",0)),str(file.get("sha256","")).left(12)],12,MUTED)
	sidebar.add_child(HSeparator.new())
	if versions.is_empty():label(d,sidebar,copy("version_empty"),13,MUTED)
	for item in versions:
		var version_id:=str(item.id)
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",4);sidebar.add_child(row)
		var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;info.add_theme_constant_override("separation",2);row.add_child(info)
		label(d,info,copy("revision") % int(item.sequence),14)
		label(d,info,"%d B · %s" % [int(item.size),str(item.sha256).left(12)],12,MUTED)
		var open:=button(d,row,copy("version_preview"),"PortalVersionPreview_"+_node_token(version_id),func():_version_open(d,state,version_id))
		open.add_theme_stylebox_override("normal",UI.style(Color("e8f3fa") if version_id==str(state.get("selected_version","")) else Color.TRANSPARENT,Color.TRANSPARENT,8,5,6))
		sidebar.add_child(HSeparator.new())
	var result: Dictionary=state.get("command_result",{})
	if not result.is_empty() and (result.has("error") or result.has("restored_version")):
		var message:=copy("version_restored") if bool(result.get("ok",false)) else copy("error_"+str(result.get("error","operation_failed")))
		if message.is_empty():message=copy("error_operation_failed")
		var feedback:=label(d,sidebar,message,13,UI.GREEN if bool(result.get("ok",false)) else UI.RED);feedback.name="PortalVersionFeedback";feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

static func _version_preview(d, parent: VBoxContainer, state: Dictionary, selected: String, compact: bool) -> void:
	var result: Dictionary=state.get("command_result",{})
	var version: Dictionary=result.get("version",{})
	if version.is_empty() or str(version.get("id",""))!=str(state.get("selected_version","")):return
	var saved:=str(version.get("content",""));var current:=_file_content(d,selected)
	var heading:=HBoxContainer.new();heading.add_theme_constant_override("separation",8);parent.add_child(heading)
	label(d,heading,copy("version_changes")+" · "+(copy("revision") % int(version.sequence)),16)
	var restore:=button(d,heading,copy("version_restore"),"PortalVersionRestore_"+_node_token(str(version.id)),func():run(d,"portal restore "+str(version.id)))
	restore.disabled=saved==current
	if saved==current:label(d,parent,copy("version_identical"),13,MUTED)
	var panes:=BoxContainer.new();panes.name="PortalVersionPanes";panes.vertical=compact;panes.add_theme_constant_override("separation",12);parent.add_child(panes)
	for spec in [["version_before",saved,"PortalVersionPreviewGrid"],["version_after",current,"PortalVersionCurrentGrid"]]:
		var pane:=VBoxContainer.new();pane.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panes.add_child(pane)
		label(d,pane,copy(str(spec[0])),14,BLUE)
		_label_grid(d,pane,str(spec[1]),str(spec[2]),100)
		var source: VBoxContainer=d._disclosure(pane,copy("file_content"))
		var text:=TextEdit.new();text.name=str(spec[2])+"Source";text.editable=false;text.text=str(spec[1]);text.custom_minimum_size.y=120;style_editor(d,text);source.add_child(text)

static func share_row(d,parent: VBoxContainer,state: Dictionary,snap: Dictionary,path: String,role: String) -> void:
	var share: Dictionary={}
	for item in snap.get("shares",[]):
		if str(item.get("path",""))==path and str(item.get("role",""))==role:share=item;break
	var permission:=int(share.get("permissions",0));var expiry:=str(share.get("expires","unlimited"))
	var drafts: Dictionary = state.get("share_drafts", {})
	var draft_key := path + "|" + role
	var draft: Dictionary = drafts.get(draft_key, {"permissions":permission, "expires":expiry})
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);parent.add_child(row)
	fixed_label(d,row,"●",17,BLUE if permission>0 else MUTED)
	var identity:=VBoxContainer.new();identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(identity)
	label(d,identity,copy(role),14);label(d,identity,copy("can_edit" if permission==3 else "read_only" if permission==1 else "no_access") + " · " + copy(str({"7d":"seven_days","30d":"thirty_days"}.get(expiry,"unlimited"))),12,MUTED)
	button(d,row,"⋯","PortalShare_"+role,func():state["editing_role"]="" if str(state.get("editing_role",""))==role else role;rerender(d))
	if str(state.get("editing_role",""))!=role:return
	var options:=panel(parent,Color("f7f9fa"),10)
	var choice:=OptionButton.new();choice.name="PortalPermission_"+role;choice.add_item(copy("no_access"),0);choice.add_item(copy("read_only"),1)
	if role!="public":choice.add_item(copy("can_edit"),3)
	var draft_permission := int(draft.get("permissions", permission))
	choice.select(2 if draft_permission==3 and role!="public" else 1 if draft_permission==1 else 0);options.add_child(choice)
	label(d,options,copy("expiration"),12,MUTED)
	var dates:=OptionButton.new();dates.name="PortalExpiry_"+role
	for item in [["unlimited","unlimited"],["seven_days","7d"],["thirty_days","30d"]]:dates.add_item(copy(item[0]));dates.set_item_metadata(dates.item_count-1,item[1])
	dates.select({"unlimited":0,"7d":1,"30d":2}.get(str(draft.get("expires", expiry)),0));options.add_child(dates)
	var note := label(d, options, "未保存の共有設定" if drafts.has(draft_key) else "適用中の共有設定", 12, MUTED)
	note.name = "PortalShareDraft_" + role
	var remember := func():
		drafts[draft_key] = {"permissions":choice.get_selected_id(), "expires":str(dates.get_item_metadata(dates.selected))}
		state["share_drafts"] = drafts; note.text = "未保存の共有設定"; persist(d)
	choice.item_selected.connect(func(_index): remember.call())
	dates.item_selected.connect(func(_index): remember.call())
	var buttons:=HFlowContainer.new();buttons.add_theme_constant_override("h_separation",6);options.add_child(buttons)
	button(d,buttons,copy("save"),"PortalApply_"+role,func():run(d,"portal share %s %s %s" % [role,{0:"none",1:"read",3:"write"}.get(choice.get_selected_id(),"none"),str(dates.get_item_metadata(dates.selected))]))
	button(d,buttons,copy("remove_share"),"PortalUnshare_"+role,func():run(d,"portal share %s none %s" % [role,expiry]))
	button(d,buttons,copy("cancel"),"PortalShareCancel_"+role,func():drafts.erase(draft_key);state["share_drafts"]=drafts;rerender(d))
	button(d,options,copy("copy_link"),"PortalLink_"+role,func():DisplayServer.clipboard_set("https://portal.client.test/%s?link=current" % role);d._notify(copy("link_copied")))
	var feedback: Dictionary = state.get("command_result", {})
	if feedback.has("error") and not bool(feedback.get("ok", false)):
		label(d, options, copy("error_" + str(feedback.get("error", "operation_failed"))) + " · 共有設定は保持しています。確認して再保存できます。", 12, UI.RED)

static func preview(d,parent: VBoxContainer,state: Dictionary) -> void:
	label(d,parent,copy("preview"),21)
	var selected := str(state.get("selected_path", ""))
	if not selected.is_empty(): label(d, parent, selected.get_file() + " · 受取側の実操作", 13, MUTED)
	var roles:=HFlowContainer.new();roles.add_theme_constant_override("h_separation",8);parent.add_child(roles)
	for role in ["staff","partner","public"]:
		var b:=button(d,roles,copy(role),"PortalRole_"+role,func():d._portal_stash_draft();state["role"]=role;reset_response(d);rerender(d));b.add_theme_color_override("font_color",BLUE if str(state.get("role","partner"))==role else INK)
	var settings:=HFlowContainer.new();settings.add_theme_constant_override("h_separation",10);settings.add_theme_constant_override("v_separation",6);parent.add_child(settings)
	fixed_label(d,settings,copy("test_identity"),12,MUTED)
	var identity:=OptionButton.new();identity.name="PortalIdentity"
	for item in d.browser_identities():
		identity.add_item(str(item.label));identity.set_item_metadata(identity.item_count-1,str(item.id))
		if str(item.id)==d.browser_identity:identity.select(identity.item_count-1)
	settings.add_child(identity)
	identity.item_selected.connect(func(index):d._portal_stash_draft();d.browser_identity=str(identity.get_item_metadata(index));reset_response(d);rerender(d))
	fixed_label(d,settings,copy("link_age"),12,MUTED)
	var ages:=OptionButton.new();ages.name="PortalAge"
	for item in [["current","current"],["week_old","week-old"],["month_old","month-old"]]:ages.add_item(copy(item[0]));ages.set_item_metadata(ages.item_count-1,item[1])
	ages.select({"current":0,"week-old":1,"month-old":2}.get(str(state.get("age","current")),0));settings.add_child(ages)
	ages.item_selected.connect(func(index):d._portal_stash_draft();state["age"]=str(ages.get_item_metadata(index));reset_response(d);rerender(d))
	var actions:=HFlowContainer.new();actions.add_theme_constant_override("h_separation",8);parent.add_child(actions)
	button(d,actions,copy("load"),"PortalRead",func():
		var raw:=str(d._portal_request(str(state.get("role","partner")),"GET",str(state.get("age","current"))))
		var sound=d.get_node_or_null("/root/Soundscape")
		if is_instance_valid(sound):sound.play_ui("work_success" if raw.begins_with("HTTP/1.1 200") else "work_failure")
		rerender(d))
	var response:=str(state.get("response",""));var ok:=response.begins_with("HTTP/1.1 200")
	var write:=button(d,actions,"提出する","PortalWrite",func():
		var raw:=str(d._portal_request(str(state.get("role","partner")),"PUT",str(state.get("age","current")),str(state.get("preview_content",""))))
		var sound=d.get_node_or_null("/root/Soundscape")
		if is_instance_valid(sound):sound.play_ui("work_success" if raw.begins_with("HTTP/1.1 200") else "work_failure")
		rerender(d));write.disabled=not ok and not bool(state.get("draft_dirty",false))
	var cancel:=button(d,actions,copy("cancel"),"PortalCancel",func():d._portal_discard_draft();rerender(d));cancel.disabled=not bool(state.get("draft_dirty",false))
	if not response.is_empty():
		var status:=response.get_slice("\n",0)
		var key:="access_allowed" if ok else "mfa_required" if "mfa_required" in response else "link_expired" if "410 Gone" in response else "tls_failed" if "TLS handshake" in response else "error_save_failed" if "save_failed" in response else "access_denied"
		var message := copy(key)
		if str(state.get("response_method", "")) == "PUT":
			message = "提出しました" if ok else "提出できませんでした" + (" · 入力は保持" if bool(state.get("draft_dirty", false)) else "")
		elif ok: message = "資料を読み込みました"
		var feedback := label(d,parent,message+"  ·  "+status,14,UI.GREEN if ok else UI.RED)
		feedback.name = "PortalResponseStatus"
		parent.move_child(feedback, actions.get_index())
	if ok or bool(state.get("draft_dirty",false)):
		var toggle := button(d, parent, "表を閉じる" if bool(state.get("edit_table", false)) else "提出内容を表で編集", "PortalEditRows", func(): d._portal_stash_draft(); state["edit_table"] = not bool(state.get("edit_table", false)); rerender(d))
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if bool(state.get("edit_table", false)): _edit_rows(d, parent, state)
		else: _label_grid(d,parent,str(state.get("preview_content","")),"PortalPreviewGrid")
		var source: VBoxContainer=d._disclosure(parent,experience_copy("edit_source","Edit source"))
		var content:=TextEdit.new();content.name="PortalContent";content.text=str(state.get("preview_content",""));content.custom_minimum_size.y=180;content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;style_editor(d,content)
		if source != null:
			source.add_child(content)
		var draft_label:=label(d,parent,copy("unsaved" if bool(state.get("draft_dirty",false)) else "file_content"),12,MUTED)
		content.text_changed.connect(func():state["preview_content"]=content.text;state["draft_dirty"]=true;d._portal_stash_draft();cancel.disabled=false;draft_label.text=copy("unsaved");persist(d))
	if not response.is_empty():
		var raw: VBoxContainer=d._disclosure(parent,copy("response"));var log:=TextEdit.new();log.editable=false;log.text=response;log.custom_minimum_size.y=140;style_editor(d,log);raw.add_child(log)

static func _csv_text(rows: Array) -> String:
	var lines: PackedStringArray = []
	for row in rows:
		var cells: PackedStringArray = []
		for value in row:
			var cell := str(value)
			if cell.contains(",") or cell.contains('"') or cell.contains("\n") or cell.contains("\r"): cell = '"' + cell.replace('"', '""') + '"'
			cells.append(cell)
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"

static func _table_changed(d, state: Dictionary, rows: Array) -> void:
	state["preview_content"] = _csv_text(rows); state["draft_dirty"] = true
	d._portal_stash_draft()
	var page: Node = d.widgets.browser.page
	var source: Node = page.find_child("PortalContent", true, false)
	if source is TextEdit:
		source.set_block_signals(true); source.text = str(state.preview_content); source.set_block_signals(false)
	for id in ["PortalWrite", "PortalCancel"]:
		var action: Node = page.find_child(id, true, false)
		if action is BaseButton: action.disabled = false
	var note: Node = page.find_child("PortalTableDraft", true, false)
	if note is Label: note.text = "未送信の提出内容 · 保存すると受取先の実ファイルが更新されます。"
	persist(d)

static func _edit_rows(d, parent: VBoxContainer, state: Dictionary) -> void:
	var rows := _csv_rows(str(state.get("preview_content", "")))
	if rows.is_empty():
		label(d, parent, "列見出しがないファイルはCSV入力から編集してください。", 13, MUTED)
		return
	var note := label(d, parent, "未送信の提出内容" if bool(state.get("draft_dirty", false)) else "取得した内容を編集します。権限と期限は送信時にも確認されます。", 12, MUTED)
	note.name = "PortalTableDraft"
	var scroll := ScrollContainer.new(); scroll.name = "PortalEntryViewport"; scroll.custom_minimum_size.y = clampf(rows.size() * 38.0, 110.0, 320.0); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(scroll)
	var table := GridContainer.new(); table.name = "PortalEntryTable"; table.columns = mini(rows[0].size(), 12) + 1; scroll.add_child(table)
	for column in table.columns - 1: _sheet_cell(d, table, str(rows[0][column]), true, false, 150)
	_sheet_cell(d, table, "行", true, true, 45)
	for row_index in range(1, mini(rows.size(), 41)):
		var row: Array = rows[row_index]
		for column in table.columns - 1:
			while row.size() <= column: row.append("")
			var input := LineEdit.new(); input.name = "PortalCell_%d_%d" % [row_index, column]; input.text = str(row[column]); input.custom_minimum_size = Vector2(150, 34); table.add_child(input)
			input.text_changed.connect(func(value): row[column] = value; _table_changed(d, state, rows))
		button(d, table, "削除", "PortalRemoveRow_%d" % row_index, func(): rows.remove_at(row_index); _table_changed(d, state, rows); rerender(d))
	if rows.size() > 41: label(d, parent, "先頭40行を表示しています。残りの行はCSV入力で編集できます。", 12, MUTED)
	var add := button(d, parent, "明細を追加", "PortalAddRow", func(): var row: Array = []; row.resize(rows[0].size()); row.fill(""); rows.append(row); _table_changed(d, state, rows); rerender(d))
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

static func _label_grid(d,parent: VBoxContainer,csv: String,id: String,cell_width: int = 200) -> void:
	var rows:=_csv_rows(csv)
	var scroll:=ScrollContainer.new();scroll.name=id+"Viewport";scroll.custom_minimum_size.y=180;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(scroll)
	var table:=GridContainer.new();table.name=id;table.add_theme_constant_override("h_separation",0);table.add_theme_constant_override("v_separation",0);scroll.add_child(table)
	if rows.is_empty():
		label(d,table,experience_copy("file_preview","File preview"),13,MUTED);return
	var columns:=0
	for row in rows:columns=maxi(columns,row.size())
	table.columns=columns+1
	_sheet_cell(d,table,"",true,true,cell_width)
	for col in columns:
		var letter:="";var number:=col
		while number>=0:
			letter=String.chr(65+number%26)+letter;number=int(number/26)-1
		_sheet_cell(d,table,letter,true,false,cell_width)
	for row_index in rows.size():
		var row:Array=rows[row_index]
		_sheet_cell(d,table,str(row_index+1),true,true,cell_width)
		for col in columns:_sheet_cell(d,table,str(row[col]) if col<row.size() else "",row_index==0,false,cell_width)

static func _sheet_cell(d,parent: Node,value: String,heading: bool,number: bool,cell_width: int = 200) -> void:
	var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(40 if number else cell_width,32);panel.add_theme_stylebox_override("panel",UI.style(Color("edf3f7") if heading else Color.WHITE,Color("d5dfe5"),8,5,0));parent.add_child(panel)
	var text:=label(d,panel,value,12,MUTED if number else INK)
	text.clip_text=true;text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;text.tooltip_text=value
	if heading:text.add_theme_font_override("font",UI.font(600))
	if number:text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

static func _csv_rows(csv: String) -> Array:
	var result: Array=[];var row: Array=[];var cell: String="";var quoted:=false;var i:=0
	while i<csv.length():
		var ch:=csv.substr(i,1)
		if ch=='"':
			if quoted and i+1<csv.length() and csv.substr(i+1,1)=='"':cell+='"';i+=1
			elif quoted:quoted=false
			elif cell.is_empty():quoted=true
			else:cell+=ch
		elif ch==',' and not quoted:row.append(cell);cell=""
		elif (ch=='\n' or ch=='\r') and not quoted:
			if ch=='\r' and i+1<csv.length() and csv.substr(i+1,1)=='\n':i+=1
			row.append(cell);result.append(row);row=[];cell=""
		else:cell+=ch
		i+=1
	if not cell.is_empty() or not row.is_empty():row.append(cell);result.append(row)
	return result
