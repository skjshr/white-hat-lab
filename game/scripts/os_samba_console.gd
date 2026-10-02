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

static func compact(d) -> bool:
	return float(d.windows.browser.size.x) < 1100.0 * float(d.game.settings.get("text_scale", 1.0))

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

static func _has_draft(d, name: String) -> bool:
	var draft: Dictionary = _state(d).get("share_drafts", {}).get(name, {})
	var saved: Dictionary = _config(d).get("values", {}).get("shares", {}).get(name, {})
	for key in draft:
		if draft[key] != saved.get(key): return true
	return false

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
	_pending(d, parent)
	var nav: HBoxContainer = HBoxContainer.new(); nav.add_theme_constant_override("separation", 6); parent.add_child(nav)
	var shares_button: Button = _button(d, nav, "Samba", "SambaTabShares", func(): s["tab"] = "shares"; d._render_samba(), s.get("tab") == "shares")
	var global_button: Button = _button(d, nav, copy("global_settings", "Global settings"), "SambaGlobal", func(): s["tab"] = "global"; d._render_samba())
	var refresh: Button = _button(d, nav, copy("refresh", "Refresh"), "SambaRefresh", func(): d._render_samba())
	var status := _label(d, nav, UI.copy("os_status", "Status") + ": " + ("active" if bool(live.get("active", false)) else "failed"), 13, MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if s.get("tab") == "global":
		_global(d, parent, parsed)
	else:
		_shares(d, parent, parsed)
	var output: String = str(s.get("output", ""))
	if not output.is_empty():
		var result: VBoxContainer = _box(parent, Color("f7f8f9"))
		var summary := _label(d, result, output.get_slice("\n", 0), 13, INK)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var details: VBoxContainer = d._disclosure(result, UI.copy("realism_show_response"))
		var text: Label = _label(d, details, output, 13, INK);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_override("font", UI.font(400))

static func _shares(d, parent: VBoxContainer, parsed: Dictionary) -> void:
	var shares: Dictionary = parsed.get("values", {}).get("shares", {})
	var s: Dictionary = _state(d)
	var selected: String = str(s.get("selected_share", ""))
	var has_selection := not selected.is_empty() and shares.has(selected)
	var is_compact := compact(d)
	var workspace := BoxContainer.new(); workspace.vertical = is_compact; workspace.name="SambaSharesWorkspace";workspace.add_theme_constant_override("separation",12);workspace.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(workspace)
	var panel: VBoxContainer = _box(workspace)
	panel.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.get_parent().size_flags_stretch_ratio = 0.85 if has_selection else 1.0
	panel.get_parent().custom_minimum_size.x=320
	panel.get_parent().visible = not (is_compact and has_selection)
	workspace.resized.connect(func():
		workspace.vertical = compact(d)
		panel.get_parent().visible = not (compact(d) and has_selection)
	)
	var heading: HBoxContainer = HBoxContainer.new(); panel.add_child(heading)
	_label(d, heading, copy("shares", "Share management"), 19, INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var open_config: Button = _button(d, heading, copy("open_config", "Open config"), "SambaOpenConfig", d._open_config)
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
		select.add_theme_color_override("font_color", BLUE if name == selected else INK);select.add_theme_stylebox_override("normal",UI.style(Color("e7f1fa") if name == selected else Color.WHITE,Color.TRANSPARENT,8,7,0));row.add_child(select)
		var path_cell:=_label(d,row,str(settings.get("path","")),13,MUTED);path_cell.custom_minimum_size.x=100;path_cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var edit: Button = _button(d, row, copy("edit_share", "Edit"), "SambaEdit_" + name, func(): s["selected_share"] = name; s["tab"] = "shares"; d._render_samba(), true)
		var open: Button = _button(d, row, copy("access_share", "Open share"), "SambaOpenShare_" + name, func(): d._open_samba_share(name))
		action_header.custom_minimum_size.x=maxf(action_header.custom_minimum_size.x,edit.get_combined_minimum_size().x+open.get_combined_minimum_size().x+10)
	if has_selection:
		var editor_pane:=_box(workspace, Color("ffffff"));editor_pane.name="SambaShareEditorPane";editor_pane.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
		editor_pane.get_parent().size_flags_stretch_ratio = 1.15
		_share_editor(d, editor_pane, selected, _draft(d, selected, shares[selected]))

static func _field(d, parent: Node, label_text: String, name: String, value: String, stack_on_compact := true) -> LineEdit:
	var row := BoxContainer.new(); row.vertical = compact(d) and stack_on_compact; row.add_theme_constant_override("separation", 5 if row.vertical else 10); parent.add_child(row)
	var title: Label = _label(d, row, label_text, 13, MUTED); title.custom_minimum_size.x = 0 if row.vertical else 150; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL if row.vertical else Control.SIZE_SHRINK_BEGIN; title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var editor := parent
	var heading := HBoxContainer.new(); heading.add_theme_constant_override("separation", 8); editor.add_child(heading)
	var back := _button(d, heading, copy("shares", "Shares"), "SambaBackToShares", func(): _state(d)["selected_share"] = ""; d._render_samba())
	back.icon = UI.symbol("back")
	back.tooltip_text = UI.copy("realism_back_to_shares")
	back.visible = compact(d)
	editor.resized.connect(func(): back.visible = compact(d))
	_label(d, heading, name, 18, INK)
	var workspace := HFlowContainer.new(); workspace.add_theme_constant_override("h_separation", 6); editor.add_child(workspace)
	for entry in [["config", "共有の設定", "SambaWorkspaceConfig"], ["access", "利用者としてアクセス", "SambaWorkspaceAccess"]]:
		var destination := str(entry[0])
		_button(d, workspace, str(entry[1]), str(entry[2]), func(): _state(d)["workspace"] = destination; d._save_session(false); d._render_samba(), str(_state(d).get("workspace", "config")) == destination)
	if str(_state(d).get("workspace", "config")) == "access":
		_access_workspace(d, editor, name)
		return
	var actions: HBoxContainer = HBoxContainer.new(); actions.add_theme_constant_override("separation", 8); heading.add_child(actions)
	var draft_status := _label(d, editor, UI.copy("realism_unsaved_changes"), 12, Color("805b00"))
	draft_status.name = "SambaDraftStatus"
	draft_status.visible = _has_draft(d, name)
	editor.add_child(HSeparator.new())
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
		draft_status.visible = _has_draft(d, name)
	path.text_changed.connect(remember_text); valid.text_changed.connect(remember_text); invalid.text_changed.connect(remember_text); writes.text_changed.connect(remember_text); reads.text_changed.connect(remember_text)
	available.toggled.connect(func(_value: bool): remember_text.call("")); read_only.toggled.connect(func(_value: bool): remember_text.call("")); guest.toggled.connect(func(_value: bool): remember_text.call(""))
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

static func _access_workspace(d, parent: VBoxContainer, share: String) -> void:
	var s := _state(d)
	var live: Dictionary = d.game._vm().state
	var applied: Dictionary = live.get("applied", {}).get("shares", {}).get(share, {})
	var path := str(applied.get("path", "/srv/share"))
	var context := _label(d, parent, "適用中の共有  //" + str(live.host) + "/" + share + " → " + path, 13, MUTED)
	context.name = "SambaAccessContext"; context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bool(live.get("dirty", false)) or _has_draft(d, share):
		_label(d, parent, "アクセス結果は適用中の設定で判定されます。編集中の設定は保存・再起動後に有効です。", 12, Color("805b00")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_access_result(d, parent, share)
	var actor := _field(d, parent, "利用者\n空欄 = ゲスト", "SambaProbeUser", str(s.get("probe_user", "staff")), false)
	actor.text_changed.connect(func(value): s["probe_user"] = value; d._save_session(false))
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation", 8); parent.add_child(row)
	var operation := OptionButton.new(); operation.name = "SambaProbeOperation"; row.add_child(operation)
	for item in [["ls", "一覧を取得"], ["get", "ファイルを読む"], ["put", "ファイルを書き込む"]]:
		operation.add_item(str(item[1])); operation.set_item_metadata(operation.item_count - 1, str(item[0]))
		if str(s.get("probe_operation", "ls")) == str(item[0]): operation.select(operation.item_count - 1)
	operation.item_selected.connect(func(index): s["probe_operation"] = str(operation.get_item_metadata(index)); d._save_session(false); d._render_samba())
	var picker := OptionButton.new(); picker.name = "SambaProbeFilePicker"; picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(picker)
	picker.add_item("共有内のファイルを選択")
	var names: Array[String] = []
	for raw in live.get("fs", {}):
		if str(raw).begins_with(path.trim_suffix("/") + "/"): names.append(str(raw).trim_prefix(path.trim_suffix("/") + "/"))
	names.sort()
	for name in names:
		picker.add_item(name); picker.set_item_metadata(picker.item_count - 1, name)
		if name == str(s.get("probe_file", "")): picker.select(picker.item_count - 1)
	var remote := _field(d, parent, "共有内のファイル", "SambaProbeFile", str(s.get("probe_file", "")), false)
	remote.text_changed.connect(func(value): s["probe_file"] = value; d._save_session(false))
	picker.item_selected.connect(func(index):
		if index > 0: remote.text = str(picker.get_item_metadata(index)); s["probe_file"] = remote.text; d._save_session(false))
	var local := _field(d, parent, "取得先 / 書込元", "SambaProbeLocal", str(s.get("probe_local", "/home/operator/share-check.txt")), false)
	local.text_changed.connect(func(value): s["probe_local"] = value; d._save_session(false))
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 8); parent.add_child(actions)
	_button(d, actions, "アクセスを実行", "SambaProbeRun", func():
		var mode := str(operation.get_selected_metadata())
		var observation := {"share":share, "user":actor.text.strip_edges(), "operation":mode, "file":remote.text, "local":local.text}
		var values: Array = [share, actor.text, remote.text, local.text]
		for value in values:
			if '"' in str(value) or "'" in str(value) or "\n" in str(value) or "\r" in str(value):
				observation.merge({"ok":false, "output":"引用符と改行を含まない利用者・パスを指定してください。", "input_error":true})
				s["probe_result"] = observation; s["_reveal_probe_result"] = true; d._render_samba(); return
		observation["applied_context"] = _probe_applied_context(d, share)
		var command := mode
		if mode != "ls": command += ' "' + (local.text if mode == "put" else remote.text) + '" "' + (remote.text if mode == "put" else local.text) + '"'
		var identity := "-N" if actor.text.strip_edges().is_empty() else '-U "' + actor.text.strip_edges() + '"'
		var output := str(d._samba_command('smbclient "//files01.client.test/' + share + '" ' + identity + " -c '" + command + "'"))
		var ok := not (output.begins_with("NT_STATUS_") or output.begins_with("{") or output.begins_with("smbclient:") or output.begins_with("put:"))
		if mode in ["get", "put"]: ok = output.ends_with(": OK")
		observation.merge({"ok":ok, "output":output, "content":str(d.game.vm_read(local.text)) if ok and mode == "get" else ""})
		s["probe_result"] = observation
		d._save_session(false); s["_reveal_probe_result"] = true; d._render_samba()
	, true)
	_button(d, actions, "共有をファイルで開く", "SambaProbeOpenFiles", func(): d._open_samba_share(share))

static func _probe_applied_context(d, share: String) -> Dictionary:
	var live: Dictionary = d.game._vm().state
	return {"host":str(live.get("host", "")), "active":bool(live.get("active", false)), "share":live.get("applied", {}).get("shares", {}).get(share, {}).duplicate(true), "map_to_guest":str(live.get("applied", {}).get("map_to_guest", "Never"))}

static func _reveal_probe_result(d, target: Control) -> void:
	# Containers and desktop focus restoration finish after a rebuilt page enters
	# the tree. Only the surviving result card consumes the pending reveal.
	for _frame in 3:
		await d.get_tree().process_frame
		if not is_instance_valid(target): return
	if not bool(_state(d).get("_reveal_probe_result", false)) or not target.is_visible_in_tree(): return
	_state(d).erase("_reveal_probe_result")
	target.grab_focus()
	# Focus-follow scrolling can run deferred. Reveal again after that pass so a
	# wrapped ACL or response's final height, including its retry action, fits.
	await d.get_tree().process_frame
	if not is_instance_valid(target): return
	var ancestor: Node = target.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(target)
		ancestor = ancestor.get_parent()

static func _access_result(d, parent: VBoxContainer, share: String) -> void:
	var s := _state(d)
	var result: Dictionary = s.get("probe_result", {})
	if result.is_empty(): return
	var feedback := _box(parent, Color("f0f8f2") if bool(result.get("ok", false)) else Color("fff1ef"))
	feedback.name = "SambaProbeResultCard"; feedback.focus_mode = Control.FOCUS_ALL
	var mode := str(result.get("operation", ""))
	var action := str({"ls":"一覧を取得", "get":"ファイルを読む", "put":"ファイルを書き込む"}.get(mode, mode))
	var description := "%s / %s / %s %s" % [str(result.get("share", share)), str(result.get("user", "")) if not str(result.get("user", "")).is_empty() else "ゲスト", action, str(result.get("file", "")) if mode != "ls" else ""]
	var heading := _label(d, feedback, ("入力の確認  " if bool(result.get("input_error", false)) else "前回の実測  ") + description, 12, MUTED)
	heading.name = "SambaProbeResultContext"; heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var applied_context: Dictionary = result.get("applied_context", {})
	var settings: Dictionary = applied_context.get("share", {})
	if not applied_context.is_empty():
		var location := _label(d, feedback, "実行時の共有  //" + str(applied_context.get("host", "")) + "/" + str(result.get("share", share)) + " → " + str(settings.get("path", "")), 12, MUTED)
		location.name = "SambaProbeResultPath"; location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if applied_context != _probe_applied_context(d, str(result.get("share", share))):
			_label(d, feedback, "この実測後に適用設定が変わっています。再実行で現在の状態を確認できます。", 12, Color("805b00")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var output_label := _label(d, feedback, str(result.get("output", "")), 13, INK if bool(result.get("ok", false)) else RED)
	output_label.name = "SambaProbeResult"; output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not bool(result.get("ok", false)) and not applied_context.is_empty():
		var acl_text := "実行時の適用設定: サービス %s / 利用可 %s / 読取専用 %s / ゲスト可 %s" % ["active" if bool(applied_context.get("active", false)) else "failed", "yes" if bool(settings.get("available", true)) else "no", "yes" if bool(settings.get("read only", true)) else "no", "yes" if bool(settings.get("guest ok", false)) else "no"]
		for pair in [["valid users", "許可利用者"], ["invalid users", "拒否利用者"], ["write list", "書込リスト"], ["read list", "読取リスト"]]:
			var value := str(settings.get(pair[0], ""))
			acl_text += ("\n" if str(pair[0]) in ["valid users", "write list"] else " / ") + str(pair[1]) + ": " + (value if not value.is_empty() else "未指定")
		acl_text += " / ゲストへの変換: " + str(applied_context.get("map_to_guest", "Never"))
		var acl := _label(d, feedback, acl_text, 12, INK)
		acl.name = "SambaProbeAppliedAcl"; acl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bool(result.get("ok", false)) and str(result.get("operation", "")) == "get":
		var bytes := TextEdit.new(); bytes.name = "SambaProbeContent"; bytes.editable = false; bytes.text = str(result.get("content", "")); bytes.custom_minimum_size.y = 100 if compact(d) else 130; bytes.add_theme_font_override("font", d.mono); feedback.add_child(bytes)
		for kind in ["normal", "read_only"]: bytes.add_theme_stylebox_override(kind, UI.style(Color("fafcfd"), LINE, 10, 8, 2))
		for kind in ["font_color", "font_readonly_color", "font_uneditable_color"]: bytes.add_theme_color_override(kind, INK)
	_button(d, feedback, "入力を変更して再試行", "SambaProbeEditInputs", func():
		var input := parent.find_child("SambaProbeUser", true, false) as Control
		if input != null:
			input.grab_focus()
			_reveal_probe_inputs(d, parent)
	)
	if bool(s.get("_reveal_probe_result", false)): _reveal_probe_result(d, feedback)

static func _reveal_probe_inputs(d, parent: Control) -> void:
	for _frame in 3:
		await d.get_tree().process_frame
		if not is_instance_valid(parent): return
	var input := parent.find_child("SambaProbeUser", true, false) as Control
	var run := parent.find_child("SambaProbeRun", true, false) as Control
	if input == null or run == null or not input.has_focus(): return
	var form := input.get_global_rect().merge(run.get_global_rect())
	var ancestor: Node = run.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer and ancestor.size.y >= form.size.y:
			# Focus-follow has revealed the first field. When the form fits, align
			# its final action too, keeping all inputs and Run in one viewport.
			ancestor.ensure_control_visible(run)
		ancestor = ancestor.get_parent()

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
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 8); actions.add_theme_constant_override("v_separation", 6); bar.add_child(actions)
	var status := _label(d, actions, UI.copy("realism_apply_pending"), 14, Color("805b00"))
	status.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button(d, actions, copy("test_config", "Test configuration"), "SambaTest", func(): d._samba_command("testparm -s"); d._render_samba())
	_button(d, actions, copy("apply_restart", "Restart Samba"), "SambaRestart", func(): d._samba_command("systemctl restart samba"); d._render_samba(), true)
