extends RefCounted
class_name OSSambaConsole

const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const SambaConfig = preload("res://scripts/samba_config.gd")
const NAV := Color("24282b")
const PAGE := Color("eef0f2")
const PANEL := Color("ffffff")
const INK := Color("1f2529")
const MUTED := Color("66727a")
const LINE := Color("d4d9dd")
const BLUE := Color("0667d5")
const RED := Color("d92d2d")

static func copy(key: String, fallback: String = "") -> String:
	return UI.copy("samba_" + key, fallback)

static func _state(d) -> Dictionary:
	if not d.samba_ui is Dictionary: d.samba_ui = {}
	var s: Dictionary = d.samba_ui
	if not s.has("tab"): s["tab"] = "shares"
	if not s.has("selected_share"): s["selected_share"] = ""
	if not s.has("share_drafts"): s["share_drafts"] = {}
	if not s.has("global_draft"): s["global_draft"] = {}
	if not s.has("output"): s["output"] = ""
	return s

static func _box(parent: Node, color: Color = PANEL) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.style(color, LINE, 16, 12, 2))
	parent.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	return body

static func _label(d, parent: Node, text: String, size: int = 14, color: Color = INK) -> Label:
	var value: Label = d._label(text, size, color)
	value.add_theme_font_override("font", UI.font(400))
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.custom_minimum_size.y = 20
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(value)
	return value

static func _button(d, parent: Node, text: String, name: String, callback: Callable, primary: bool = false) -> Button:
	var value: Button = d._button(text, callback)
	value.name = name
	value.custom_minimum_size.y = 32
	value.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	value.add_theme_stylebox_override("normal", UI.style(BLUE if primary else Color("f7f8f9"), BLUE if primary else LINE, 12, 7, 2))
	value.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	parent.add_child(value)
	return value

static func _config(d) -> Dictionary:
	if not is_instance_valid(d.game): return {"error":"connection"}
	var info: Dictionary = d.game.vm_info()
	if not bool(info.get("connected", false)): return {"error":"connection"}
	var parsed: Dictionary = SambaConfig.parse(str(d.game.vm_read(str(info.get("config_path", "")))))
	return parsed

static func _draft(d, name: String, original: Dictionary) -> Dictionary:
	var s: Dictionary = _state(d)
	var drafts: Dictionary = s.get("share_drafts", {})
	var value: Dictionary = drafts.get(name, {}) if drafts.get(name, {}) is Dictionary else {}
	var merged: Dictionary = original.duplicate(true)
	for key in value: merged[key] = value[key]
	return merged

static func _remember(d, name: String, values: Dictionary) -> void:
	var s: Dictionary = _state(d)
	var drafts: Dictionary = s.get("share_drafts", {})
	drafts[name] = values.duplicate(true)
	s["share_drafts"] = drafts
	if d.has_method("_save_session"): d._save_session(false)

static func render(d, parent: VBoxContainer) -> void:
	var s: Dictionary = _state(d)
	var parsed: Dictionary = _config(d)
	var background:=PanelContainer.new();background.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	background.custom_minimum_size.y=maxf(360,float(d.windows.browser.size.y)-86)
	background.add_theme_stylebox_override("panel",UI.style(PAGE,Color.TRANSPARENT,0,0,0));parent.add_child(background)
	var page:=VBoxContainer.new();page.add_theme_constant_override("separation",0);background.add_child(page);parent=page
	var chrome: PanelContainer = PanelContainer.new()
	chrome.add_theme_stylebox_override("panel", UI.style(NAV, Color.TRANSPARENT, 16, 12, 0))
	parent.add_child(chrome)
	var head: HBoxContainer = HBoxContainer.new(); head.add_theme_constant_override("separation", 10); chrome.add_child(head)
	Glyph.add_to(head, "file", 24, Color.WHITE)
	_label(d, head, "Cockpit", 20, Color.WHITE).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var host:=_label(d,head,str(d.game.vm_info().host),13,Color("c1c7cc"));host.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var margin:=MarginContainer.new();parent.add_child(margin)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,18)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",12);margin.add_child(body);parent=body
	if parsed.get("error", "") == "connection":
		_label(d, parent, copy("connection_failed", "Connect to the customer terminal first."), 15, RED)
		_button(d, parent, copy("connect", "Connect"), "SambaConnect", func(): d._samba_command("ssh client"); d._render_samba(), true)
		return
	if not str(parsed.get("error", "")).is_empty():
		_label(d, parent, str(parsed.get("error", "")), 14, RED)
		_button(d, parent, copy("open_config", "Open configuration"), "SambaOpenConfig", d._open_config)
		return
	var live: Dictionary = d.game._vm().state
	_label(d, parent, UI.copy("os_status", "Status") + ": " + ("active" if bool(live.get("active", false)) else "failed"), 13, MUTED)
	_pending(d, parent)
	var nav: HBoxContainer = HBoxContainer.new(); nav.add_theme_constant_override("separation", 6); parent.add_child(nav)
	var shares_button: Button = _button(d, nav, "Samba", "SambaTabShares", func(): s["tab"] = "shares"; d._render_samba(), s.get("tab") == "shares")
	var global_button: Button = _button(d, nav, copy("global_settings", "Global settings"), "SambaGlobal", func(): s["tab"] = "global"; d._render_samba())
	var refresh: Button = _button(d, nav, copy("refresh", "Refresh"), "SambaRefresh", func(): d._render_samba())
	if s.get("tab") == "global":
		_global(d, parent, parsed)
	else:
		_shares(d, parent, parsed)
	var output: String = str(s.get("output", ""))
	if not output.is_empty():
		var result: VBoxContainer = _box(parent, Color("f7f8f9"))
		_label(d, result, copy("result", "Result"), 15, MUTED)
		var text: Label = _label(d, result, output, 13, INK);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_override("font", UI.font(400))

static func _shares(d, parent: VBoxContainer, parsed: Dictionary) -> void:
	var shares: Dictionary = parsed.get("values", {}).get("shares", {})
	var workspace: BoxContainer = HBoxContainer.new() if float(d.windows.browser.size.x) >= 1100.0 else VBoxContainer.new();workspace.name="SambaSharesWorkspace";workspace.add_theme_constant_override("separation",12);workspace.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(workspace)
	var panel: VBoxContainer = _box(workspace)
	panel.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.get_parent().custom_minimum_size.x=320
	var heading: HBoxContainer = HBoxContainer.new(); panel.add_child(heading)
	_label(d, heading, copy("shares", "Share management"), 19, INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var open_config: Button = _button(d, heading, copy("open_config", "Open config"), "SambaOpenConfig", d._open_config)
	var s: Dictionary = _state(d)
	var columns: HBoxContainer = HBoxContainer.new(); columns.add_theme_constant_override("separation", 10); panel.add_child(columns)
	var icon_space:=Control.new();icon_space.custom_minimum_size.x=20;columns.add_child(icon_space)
	var name_header: Label = _label(d, columns, copy("name", "Name"), 12, MUTED); name_header.custom_minimum_size.x = 100; name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var path_header: Label = _label(d, columns, copy("path", "Path"), 12, MUTED); path_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL;path_header.custom_minimum_size.x=100
	var action_header:=Control.new();columns.add_child(action_header)
	panel.add_child(HSeparator.new())
	for key in shares.keys():
		var name: String = str(key)
		var settings: Dictionary = shares[key] if shares[key] is Dictionary else {}
		var row: HBoxContainer = HBoxContainer.new(); row.add_theme_constant_override("separation", 10); panel.add_child(row)
		Glyph.add_to(row, "file", 20, BLUE)
		var select: Button = d._button(name, func(): s["selected_share"] = name; s["tab"] = "shares"; d._render_samba())
		select.name = "SambaShare_" + name;select.custom_minimum_size.x=100
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT; select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.add_theme_color_override("font_color", INK);select.add_theme_stylebox_override("normal",UI.style(Color.WHITE,Color.TRANSPARENT,0,7,0));row.add_child(select)
		var path_cell:=_label(d,row,str(settings.get("path","")),13,MUTED);path_cell.custom_minimum_size.x=100;path_cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var edit: Button = _button(d, row, copy("edit_share", "Edit"), "SambaEdit_" + name, func(): s["selected_share"] = name; s["tab"] = "shares"; d._render_samba(), true)
		var open: Button = _button(d, row, copy("access_share", "Open share"), "SambaOpenShare_" + name, func(): d._open_samba_share(name))
		action_header.custom_minimum_size.x=maxf(action_header.custom_minimum_size.x,edit.get_combined_minimum_size().x+open.get_combined_minimum_size().x+10)
	var selected: String = str(s.get("selected_share", ""))
	if not selected.is_empty() and shares.has(selected):
		var editor_pane:=_box(workspace, Color("ffffff"));editor_pane.name="SambaShareEditorPane";editor_pane.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_share_editor(d, editor_pane, selected, _draft(d, selected, shares[selected]))

static func _field(d, parent: Node, label_text: String, name: String, value: String) -> LineEdit:
	var row: HBoxContainer = HBoxContainer.new(); row.add_theme_constant_override("separation", 10); parent.add_child(row)
	var title: Label = _label(d, row, label_text, 13, MUTED); title.custom_minimum_size.x = 150; title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var edit: LineEdit = LineEdit.new(); edit.name = name; edit.text = value; edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; edit.custom_minimum_size.y = 32; row.add_child(edit)
	return edit

static func _check(d, parent: Node, label_text: String, name: String, value: bool) -> CheckBox:
	var row: HBoxContainer = HBoxContainer.new(); row.add_theme_constant_override("separation", 10); parent.add_child(row)
	var title:=_label(d,row,label_text,13,MUTED);title.custom_minimum_size.x=150;title.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var check: CheckBox = CheckBox.new(); check.name=name;check.button_pressed=value
	for kind in ["normal","hover","pressed","focus"]:check.add_theme_stylebox_override(kind,StyleBoxEmpty.new())
	row.add_child(check)
	return check

static func _share_editor(d, parent: VBoxContainer, name: String, original: Dictionary) -> void:
	var holder:=HBoxContainer.new();parent.add_child(holder)
	var editor: VBoxContainer = _box(holder, Color.WHITE)
	editor.get_parent().custom_minimum_size.x=minf(500,maxf(300,float(d.windows.browser.size.x)-390))
	editor.get_parent().size_flags_horizontal=Control.SIZE_FILL
	_label(d, editor, name, 18, INK)
	var path: LineEdit = _field(d, editor, copy("path", "Path"), "SambaPath", str(original.get("path", "")))
	var available: CheckBox = _check(d, editor, copy("available", "Available"), "SambaAvailable", bool(original.get("available", true)))
	var read_only: CheckBox = _check(d, editor, copy("read_only", "Read only"), "SambaReadOnly", bool(original.get("read only", true)))
	var guest: CheckBox = _check(d, editor, copy("guest_access", "Guest access"), "SambaGuest", bool(original.get("guest ok", false)))
	var valid: LineEdit = _field(d, editor, copy("allowed_users", "Allowed users"), "SambaValidUsers", str(original.get("valid users", "")))
	var invalid: LineEdit = _field(d, editor, copy("denied_users", "Denied users"), "SambaInvalidUsers", str(original.get("invalid users", "")))
	var writes: LineEdit = _field(d, editor, copy("write_list", "Write list"), "SambaWriteList", str(original.get("write list", "")))
	var reads: LineEdit = _field(d, editor, copy("read_list", "Read list"), "SambaReadList", str(original.get("read list", "")))
	var remember_text := func(_value: String):
		_remember(d, name, {"path":path.text,"available":available.button_pressed,"read only":read_only.button_pressed,"guest ok":guest.button_pressed,"valid users":valid.text,"invalid users":invalid.text,"write list":writes.text,"read list":reads.text})
	path.text_changed.connect(remember_text); valid.text_changed.connect(remember_text); invalid.text_changed.connect(remember_text); writes.text_changed.connect(remember_text); reads.text_changed.connect(remember_text)
	available.toggled.connect(func(_value: bool): remember_text.call("")); read_only.toggled.connect(func(_value: bool): remember_text.call("")); guest.toggled.connect(func(_value: bool): remember_text.call(""))
	var actions: HBoxContainer = HBoxContainer.new(); actions.add_theme_constant_override("separation", 8); editor.add_child(actions)
	_button(d, actions, copy("save", "Save"), "SambaSave", func():
		var values: Dictionary = {"path":path.text.strip_edges(),"available":available.button_pressed,"read only":read_only.button_pressed,"guest ok":guest.button_pressed,"valid users":valid.text.strip_edges(),"invalid users":invalid.text.strip_edges(),"write list":writes.text.strip_edges(),"read list":reads.text.strip_edges()}
		var saved: bool = bool(d._samba_save(name, values))
		if saved:
			var drafts: Dictionary = _state(d).get("share_drafts", {})
			drafts.erase(name); _state(d)["share_drafts"] = drafts
		d._render_samba()
	, true)
	_button(d, actions, copy("cancel", "Cancel"), "SambaCancel", func():
		var drafts: Dictionary = _state(d).get("share_drafts", {}); drafts.erase(name); _state(d)["share_drafts"] = drafts; _state(d)["selected_share"]=""; d._render_samba())

static func _global(d, parent: VBoxContainer, parsed: Dictionary) -> void:
	var body: VBoxContainer = _box(parent)
	_label(d, body, copy("global_settings", "Global settings"), 19, INK)
	var globals: Dictionary = parsed.get("values", {}).get("samba", {}).get("global", {})
	var draft: Dictionary = _state(d).get("global_draft", {}) if _state(d).get("global_draft", {}) is Dictionary else {}
	for key in draft: globals[key] = draft[key]
	_label(d, body, copy("guest_mapping", "Guest mapping"), 13, MUTED)
	var mapping: OptionButton = OptionButton.new(); mapping.name="SambaGuestMapping"; mapping.add_item("Never"); mapping.set_item_metadata(0,"Never"); mapping.add_item("Bad User"); mapping.set_item_metadata(1,"Bad User"); mapping.select(1 if str(globals.get("map to guest", "Never")).to_lower() == "bad user" else 0); body.add_child(mapping)
	mapping.item_selected.connect(func(_index: int): _state(d)["global_draft"] = {"map to guest":str(mapping.get_selected_metadata())}; if d.has_method("_save_session"): d._save_session(false))
	var actions: HBoxContainer = HBoxContainer.new(); body.add_child(actions)
	_button(d, actions, copy("save", "Save"), "SambaGlobalSave", func():
		var saved: bool = bool(d._samba_save("global", {"map to guest":str(mapping.get_selected_metadata())}))
		if saved: _state(d)["global_draft"] = {}
		d._render_samba()
	, true)
	_button(d, actions, copy("cancel", "Cancel"), "SambaCancel", func(): _state(d)["global_draft"] = {}; _state(d)["tab"]="shares"; d._render_samba())

static func _pending(d, parent: VBoxContainer) -> void:
	if not is_instance_valid(d.game): return
	var live: Dictionary = d.game._vm().state
	if not bool(live.get("dirty", false)): return
	var bar: VBoxContainer = _box(parent, Color("fff8e6"))
	_label(d, bar, copy("pending", "Pending configuration"), 14, Color("805b00"))
	var actions: HBoxContainer = HBoxContainer.new(); bar.add_child(actions)
	_button(d, actions, copy("test_config", "Test configuration"), "SambaTest", func(): d._samba_command("testparm -s"); d._render_samba(), true)
	_button(d, actions, copy("apply_restart", "Restart Samba"), "SambaRestart", func(): d._samba_command("systemctl restart samba"); d._render_samba(), true)
