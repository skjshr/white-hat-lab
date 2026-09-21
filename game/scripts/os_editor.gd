extends RefCounted
## Compact code editor layout. State and editor references are kept for desktop.gd.

const UI = preload("res://scripts/ui_theme.gd")
const TEXT_COMPARISON = preload("res://scripts/text_comparison.gd")
const EDITOR_INK := Color("cccccc")
const EDITOR_MUTED := Color("858585")
const EDITOR_BG := Color("1e1e1e")
const EDITOR_NAV := Color("252526")
const EDITOR_RAIL := Color("333333")
const EDITOR_SELECT := Color("264f78")
const EDITOR_STATUS := Color("007acc")

static func _tool(d, symbol: String, tooltip: String, callback: Callable, label := "") -> Button:
	var b: Button
	if d.has_method("_tool_button"):
		b = d._tool_button(symbol, tooltip, callback)
		if not label.is_empty(): b.text = label
	else:
		b = d._button(label, callback)
	b.tooltip_text = tooltip
	b.custom_minimum_size.y = 30
	b.add_theme_stylebox_override("normal", UI.style(EDITOR_NAV, Color("3f3f46"), 5, 3, 0))
	b.add_theme_stylebox_override("hover", UI.style(Color("3c3c3c"), Color("565656"), 5, 3, 0))
	b.add_theme_stylebox_override("pressed", UI.style(EDITOR_SELECT, EDITOR_STATUS, 5, 3, 0))
	b.add_theme_color_override("font_color", EDITOR_INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	if label.is_empty(): b.text = ""
	return b

static func build(d, parent: VBoxContainer) -> void:
	var p = d._pad(parent, 0)
	p.add_theme_constant_override("separation", 0)
	var toolbar_panel := PanelContainer.new()
	toolbar_panel.add_theme_stylebox_override("panel", UI.style(EDITOR_NAV, Color.TRANSPARENT, 6, 2, 0))
	p.add_child(toolbar_panel)
	var toolbar = d._row(toolbar_panel, 3)
	var file_menu := MenuButton.new()
	file_menu.text = UI.copy("fidelity_file", "ファイル")
	file_menu.custom_minimum_size.y = 30
	file_menu.add_theme_stylebox_override("normal", UI.style(EDITOR_NAV, Color.TRANSPARENT, 5, 3, 0))
	file_menu.add_theme_stylebox_override("hover", UI.style(Color("3c3c3c"), Color.TRANSPARENT, 5, 3, 0))
	file_menu.add_theme_color_override("font_color", EDITOR_INK)
	toolbar.add_child(file_menu)
	file_menu.get_popup().add_item("新しいメモ", 0)
	file_menu.get_popup().add_item("ファイルを開く…", 1)
	file_menu.get_popup().add_item("保存   Ctrl+S", 2)
	file_menu.get_popup().id_pressed.connect(func(id):
		if id == 0: d._new_file()
		elif id == 1: d.widgets.editor.path_row.show(); d.widgets.editor.path.grab_focus()
		else: d._save_editor())
	var edit_menu := MenuButton.new(); edit_menu.text = UI.copy("fidelity_edit", "編集"); edit_menu.add_theme_stylebox_override("normal", UI.style(EDITOR_NAV, Color.TRANSPARENT, 5, 3, 0)); edit_menu.add_theme_stylebox_override("hover", UI.style(Color("3c3c3c"), Color.TRANSPARENT, 5, 3, 0)); edit_menu.add_theme_color_override("font_color", EDITOR_INK); toolbar.add_child(edit_menu)
	edit_menu.get_popup().add_item("検索   Ctrl+F",0)
	edit_menu.get_popup().add_item("置換   Ctrl+H",1)
	edit_menu.get_popup().id_pressed.connect(func(id): show_find(d,id==1))
	var view := MenuButton.new()
	view.text = "表示"
	view.custom_minimum_size.y = 30
	view.add_theme_stylebox_override("normal", UI.style(EDITOR_NAV, Color.TRANSPARENT, 5, 3, 0))
	view.add_theme_stylebox_override("hover", UI.style(Color("3c3c3c"), Color.TRANSPARENT, 5, 3, 0))
	view.add_theme_color_override("font_color", EDITOR_INK)
	toolbar.add_child(view)
	view.get_popup().add_item("エクスプローラー", 0)
	view.get_popup().add_item("操作リファレンス", 1)
	view.get_popup().add_item(UI.copy("compare_saved"), 2)
	view.get_popup().add_item(UI.copy("compare_baseline"), 3)
	view.get_popup().id_pressed.connect(func(id):
		if id == 0: d.widgets.editor.explorer.visible = not d.widgets.editor.explorer.visible
		elif id == 1: d._show_app("manual")
		elif id == 2: _show_compare(d, "saved")
		else: _show_compare(d, "baseline"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	var save: Button = _tool(d, "save", "保存  Ctrl+S", d._save_editor, "保存")
	save.icon = null
	toolbar.add_child(save)

	var path_row = d._row(p, 3)
	var path_label: Label = d._label("場所", 12, EDITOR_MUTED)
	path_label.custom_minimum_size.x = 34
	path_row.add_child(path_label)
	var path := LineEdit.new()
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path.text = d.editor_path
	path.placeholder_text = "ファイルパス"
	path.custom_minimum_size.y = 30
	path.text_submitted.connect(func(_v): d._load_editor(); path_row.hide())
	path_row.add_child(path)
	path_row.add_child(_tool(d, "external", "開く", func(): d._load_editor(); path_row.hide(), "開く"))
	path_row.add_child(_tool(d, "close", "場所欄を閉じる", func(): path_row.hide()))
	path_row.hide()

	var split = d._row(p, 0)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rail := VBoxContainer.new()
	rail.custom_minimum_size.x = 34
	rail.add_theme_constant_override("separation", 3)
	var file_activity: Button = _tool(d, "grid", UI.copy("fidelity_explorer", "エクスプローラー"), func(): d.widgets.editor.explorer.visible = true)
	var search_activity: Button = _tool(d, "search", UI.copy("fidelity_find", "ファイル内を検索"), func(): show_find(d))
	rail.add_child(file_activity)
	rail.add_child(search_activity)
	var rail_panel := PanelContainer.new()
	rail_panel.add_theme_stylebox_override("panel", UI.style(EDITOR_RAIL, Color.TRANSPARENT, 0, 3, 0))
	rail_panel.add_child(rail)
	split.add_child(rail_panel)
	var explorer := VBoxContainer.new()
	explorer.custom_minimum_size.x = 175
	explorer.add_theme_constant_override("separation", 3)
	var explorer_header := HBoxContainer.new()
	explorer_header.add_theme_constant_override("separation", 3)
	explorer.add_child(explorer_header)
	var owner = d._label(UI.copy("fidelity_explorer", "EXPLORER").to_upper(), 12, EDITOR_MUTED)
	owner.autowrap_mode = TextServer.AUTOWRAP_OFF
	owner.clip_text = true
	owner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explorer_header.add_child(owner)
	var new_button: Button = _tool(d, "plus", "新しいメモ", d._new_file)
	new_button.name = "EditorNewFile"
	new_button.text = ""
	new_button.custom_minimum_size = Vector2(28, 28)
	explorer_header.add_child(new_button)
	var tree := Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.x = 164
	tree.add_theme_font_size_override("font_size", 13)
	tree.add_theme_color_override("font_color", EDITOR_INK)
	tree.add_theme_color_override("font_selected_color", EDITOR_INK)
	tree.add_theme_color_override("guide_color", Color.TRANSPARENT)
	tree.add_theme_color_override("relationship_line_color", Color("4c5568"))
	tree.add_theme_stylebox_override("panel", UI.style(EDITOR_NAV, Color.TRANSPARENT, 4, 4, 0))
	tree.add_theme_stylebox_override("selected", UI.style(EDITOR_SELECT, Color.TRANSPARENT, 3, 3, 0))
	explorer.add_child(tree)
	split.add_child(explorer)

	var area = d._box(split, 0)
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tabs := TabBar.new()
	tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	tabs.scrolling_enabled = true
	
	tabs.custom_minimum_size.y = 30
	tabs.add_theme_stylebox_override("tab_selected", UI.style(EDITOR_BG, EDITOR_STATUS, 8, 4, 0))
	tabs.add_theme_stylebox_override("tab_unselected", UI.style(EDITOR_NAV, Color.TRANSPARENT, 8, 4, 0))
	tabs.add_theme_color_override("font_selected_color", EDITOR_INK)
	tabs.add_theme_color_override("font_unselected_color", EDITOR_MUTED)
	area.add_child(tabs)
	var name = d._label("ファイル選択", 13, EDITOR_MUTED)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	name.custom_minimum_size.y = 22
	area.add_child(name)
	var find_panel := VBoxContainer.new(); find_panel.add_theme_constant_override("separation",3); area.add_child(find_panel)
	var find_row := HBoxContainer.new(); find_row.add_theme_constant_override("separation",3); find_panel.add_child(find_row)
	var find_input := LineEdit.new(); find_input.placeholder_text="検索"; find_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; find_row.add_child(find_input)
	var case_toggle := CheckButton.new(); case_toggle.text="Aa"; case_toggle.tooltip_text="大文字/小文字を区別"; find_row.add_child(case_toggle)
	var count: Label = d._label("",12,EDITOR_MUTED); count.autowrap_mode=TextServer.AUTOWRAP_OFF; count.custom_minimum_size.x=34; count.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; find_row.add_child(count)
	find_row.add_child(_tool(d,"up","前の一致 / Shift+F3",func(): find_next(d,true),"↑"))
	find_row.add_child(_tool(d,"down","次の一致 / F3",func(): find_next(d),"↓"))
	find_row.add_child(_tool(d,"close","検索終了 / Esc",func(): hide_find(d),"×"))
	var replace_row := HBoxContainer.new(); replace_row.add_theme_constant_override("separation",3); find_panel.add_child(replace_row)
	var replace_input := LineEdit.new(); replace_input.placeholder_text="置換後の文字列"; replace_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; replace_row.add_child(replace_input)
	var replace_button: Button = d._button("置換",func(): replace_match(d)); replace_row.add_child(replace_button)
	find_panel.hide(); replace_row.hide()
	var code := CodeEdit.new()
	code.name = "ConfigEditor"
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.gutters_draw_line_numbers = true
	code.highlight_current_line = true
	code.deselect_on_focus_loss_enabled = false
	code.add_theme_font_override("font", d.mono)
	code.add_theme_font_size_override("font_size", maxi(14, int(14 * float(d.game.settings.get("text_scale", 1.0)))))
	code.add_theme_stylebox_override("normal", UI.style(EDITOR_BG, Color.TRANSPARENT, 0, 0, 0))
	code.add_theme_stylebox_override("focus", UI.style(EDITOR_BG, Color.TRANSPARENT, 0, 0, 0))
	code.add_theme_color_override("background_color", EDITOR_BG)
	code.add_theme_color_override("font_color", EDITOR_INK)
	code.add_theme_color_override("line_number_color", EDITOR_MUTED)
	code.add_theme_color_override("caret_color", EDITOR_INK)
	code.add_theme_color_override("current_line_color", Color("2a2d2e"))
	code.add_theme_color_override("selection_color", EDITOR_SELECT)
	var syntax := CodeHighlighter.new()
	syntax.number_color = Color("d9a86c")
	syntax.symbol_color = Color("c6a0e9")
	for word in ["staff", "guest", "schedule", "repository", "dns", "business", "admin_public", "tls", "former", "sessions", "current", "mfa", "pc_a", "pc_b", "logs", "reset", "partner", "public", "expires", "audit"]:
		syntax.add_keyword_color(word, Color("83bee5"))
	syntax.add_color_region("#", "", Color("8ebf8a"), true)
	code.syntax_highlighter = syntax
	var compare_bar := HBoxContainer.new()
	compare_bar.hide()
	area.add_child(compare_bar)
	var compare_status = d._label("", 12, EDITOR_INK)
	compare_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare_bar.add_child(compare_status)
	compare_bar.add_child(_tool(d, "close", UI.copy("compare_close"), func(): _close_compare(d), UI.copy("compare_close")))
	var compare_panes := BoxContainer.new()
	compare_panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compare_panes.add_theme_constant_override("separation", 6)
	area.add_child(compare_panes)
	var compare_source := VBoxContainer.new()
	compare_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare_source.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compare_source.hide()
	compare_panes.add_child(compare_source)
	var compare_title = d._label("", 12, EDITOR_INK)
	compare_source.add_child(compare_title)
	var compare_original := CodeEdit.new()
	compare_original.name = "EditorCompareOriginal"
	compare_original.editable = false
	compare_original.gutters_draw_line_numbers = true
	compare_original.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare_original.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compare_original.custom_minimum_size.y = 88
	compare_original.add_theme_font_override("font", d.mono)
	compare_original.add_theme_font_size_override("font_size", maxi(14, int(14 * float(d.game.settings.get("text_scale", 1.0)))))
	compare_original.add_theme_stylebox_override("normal", UI.style(EDITOR_BG, Color.TRANSPARENT, 0, 0, 0))
	compare_original.add_theme_color_override("background_color", EDITOR_BG)
	compare_original.add_theme_color_override("font_color", EDITOR_INK)
	compare_original.add_theme_color_override("font_readonly_color", EDITOR_INK)
	compare_original.add_theme_color_override("line_number_color", Color("b0b0b0"))
	compare_source.add_child(compare_original)
	var working := VBoxContainer.new()
	working.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	working.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compare_panes.add_child(working)
	var working_title = d._label(UI.copy("compare_working_title"), 12, EDITOR_INK)
	working_title.hide()
	working.add_child(working_title)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	working.add_child(code)
	compare_panes.resized.connect(func(): compare_panes.vertical = compare_source.visible and compare_panes.size.x < 650)

	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 5)
	p.add_child(flow)
	var hint = d._label("", 13, UI.WARNING)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.clip_text = true
	flow.add_child(hint)
	var next = _tool(d, "settings", "サービス管理", d._show_app.bind("monitor"), "サービス管理")
	flow.add_child(next)
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", UI.style(EDITOR_STATUS, Color.TRANSPARENT, 0, 2, 0))
	p.add_child(status)
	var strip = d._row(status, 8)
	var info = d._label("", 12, Color.WHITE)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.clip_text = true
	strip.add_child(info)
	var cursor = d._label("", 12, Color.WHITE)
	strip.add_child(cursor)
	strip.add_child(d._label("UTF-8", 12, Color.WHITE))
	d.widgets.editor = {"path": path, "path_row": path_row, "editor": code, "info": info, "filename": name, "owner": owner, "save": save, "hint": hint, "next": next, "cursor": cursor, "flow": flow, "explorer": explorer, "tree": tree, "tree_signature": "", "tabs": tabs, "opened": [], "view_popup": view.get_popup()}
	var saved_tabs: Array = d.game.state.get("desktop_sessions", {}).get(d.session_key, {}).get("editor_tabs", [])
	for saved_path in saved_tabs:
		if saved_path is String and not saved_path.is_empty() and not d.widgets.editor.opened.has(saved_path):
			d.widgets.editor.opened.append(saved_path); tabs.add_tab(saved_path.get_file())
	d.widgets.editor.merge({"find_panel":find_panel,"find_input":find_input,"find_case":case_toggle,"find_count":count,"replace_row":replace_row,"replace_input":replace_input,"replace_button":replace_button})
	d.widgets.editor.merge({"compare_mode":"", "compare_signature":"", "compare_panes":compare_panes, "compare_bar":compare_bar, "compare_status":compare_status, "compare_source":compare_source, "compare_title":compare_title, "compare_original":compare_original, "working_title":working_title})
	view.get_popup().set_item_disabled(3, true)
	find_input.text_changed.connect(func(_text): find_next(d,false,true))
	find_input.text_submitted.connect(func(_text): find_next(d))
	case_toggle.toggled.connect(func(_on): find_next(d,false,true))
	replace_input.text_submitted.connect(func(_text): replace_match(d))
	tree.item_activated.connect(func():
		var item := tree.get_selected()
		if item != null and item.get_metadata(0) is String: d._open_editor(str(item.get_metadata(0))))
	tabs.tab_changed.connect(func(index):
		if index >= 0 and index < d.widgets.editor.opened.size(): d._open_editor(str(d.widgets.editor.opened[index])))
	tabs.tab_close_pressed.connect(func(index):
		var w: Dictionary = d.widgets.editor
		w.opened.remove_at(index)
		tabs.set_block_signals(true)
		tabs.remove_tab(index)
		tabs.set_block_signals(false)
		if not w.opened.is_empty(): d._open_editor(str(w.opened[mini(index, w.opened.size() - 1)]))
		else: d._open_editor(""))
	d.editor = code
	d.path_edit = path
	code.text = str(d.drafts.get(d.editor_path, d._read(d.editor_path))) if not d.editor_path.is_empty() else ""
	code.text_changed.connect(func():
		if not d.editor_path.is_empty(): d.drafts[d.editor_path] = code.text
		refresh(d))
	code.caret_changed.connect(func(): cursor.text = "%d : %d" % [code.get_caret_line() + 1, code.get_caret_column() + 1])
	refresh(d)

static func _baseline(d) -> String:
	var path := str(d.editor_path)
	var info: Dictionary = d.game.vm_info()
	if path.is_empty() or path.begins_with("workstation:") or path != str(info.get("config_path", "")): return ""
	var targets: Array = d.game.state.get("targets", [])
	var index := int(d.game.state.get("target_index", 0))
	if index < 0 or index >= targets.size(): return ""
	var target: Dictionary = targets[index]
	return str(target.get("baseline_config", "")) if bool(target.get("baseline_recorded", false)) else ""

static func _show_compare(d, mode: String) -> void:
	if not d.widgets.has("editor"): return
	var w: Dictionary = d.widgets.editor
	if str(d.editor_path).is_empty() or (mode == "baseline" and _baseline(d).is_empty()): return
	if str(w.compare_mode).is_empty(): w.explorer_before_compare = w.explorer.visible
	w.compare_mode = mode
	w.compare_signature = ""
	w.explorer.hide()
	w.compare_source.show()
	w.compare_bar.show()
	w.working_title.show()
	_refresh_compare(d)

static func _close_compare(d) -> void:
	var w: Dictionary = d.widgets.editor
	w.compare_mode = ""
	w.compare_signature = ""
	w.compare_source.hide()
	w.compare_bar.hide()
	w.working_title.hide()
	w.explorer.visible = bool(w.get("explorer_before_compare", true))
	w.compare_panes.vertical = false
	for line in w.editor.get_line_count(): w.editor.set_line_background_color(line, Color.TRANSPARENT)

static func _refresh_compare(d) -> void:
	var w: Dictionary = d.widgets.editor
	if str(w.compare_mode).is_empty(): return
	var path: String = str(d.editor_path)
	var mode: String = str(w.compare_mode)
	if path.is_empty() or (mode == "baseline" and _baseline(d).is_empty()):
		_close_compare(d)
		return
	var original: String = d._read(path) if mode == "saved" else _baseline(d)
	var signature: String = JSON.stringify([mode, path, original, w.editor.text])
	if signature == str(w.compare_signature): return
	w.compare_signature = signature
	var result: Dictionary = TEXT_COMPARISON.compare(original, str(w.editor.text))
	w.compare_title.text = UI.copy("compare_saved_title" if mode == "saved" else "compare_baseline_title")
	if w.compare_original.text != original: w.compare_original.text = original
	for line in w.compare_original.get_line_count(): w.compare_original.set_line_background_color(line, Color.TRANSPARENT)
	for line in w.editor.get_line_count(): w.editor.set_line_background_color(line, Color.TRANSPARENT)
	for line in result.removed: w.compare_original.set_line_background_color(line, Color("633739"))
	for line in result.added: w.editor.set_line_background_color(line, Color("254e3d"))
	w.compare_status.text = UI.copy("compare_unchanged") if original == str(w.editor.text) else "−%d  +%d" % [result.removed.size(), result.added.size()]
	w.compare_panes.vertical = w.compare_panes.size.x < 650

static func refresh(d) -> void:
	if not d.widgets.has("editor") or not d.widgets.editor.has("filename"): return
	var w: Dictionary = d.widgets.editor
	var path: String = d.editor_path
	var local := path.begins_with("workstation:")
	var vm: Dictionary = d.game.vm_info()
	var accessible := not path.is_empty() and (local or bool(vm.connected))
	var unsaved: bool = accessible and w.editor.text != d._read(path)
	if not path.is_empty(): d.drafts[path] = w.editor.text
	var title: String = path.get_file() + (" ●" if unsaved else "") + " — エディタ" if not path.is_empty() else "エディタ"
	d.windows.editor.title_text = title
	d.windows.editor.caption.text = "  " + title
	var config: bool = not local and path == str(vm.config_path)
	var live: Dictionary = d.game._vm().state
	w.filename.text = path.trim_prefix("workstation:").replace("/", "  ›  ") if not path.is_empty() else "ファイル選択"
	if not path.is_empty() and not w.opened.has(path):
		w.opened.append(path)
		w.tabs.set_block_signals(true)
		w.tabs.add_tab(path.get_file())
		w.tabs.set_block_signals(false)
	w.tabs.set_block_signals(true)
	for index in w.opened.size():
		var item_path: String = w.opened[index]
		var dirty: bool = str(d.drafts.get(item_path, d._read(item_path))) != d._read(item_path)
		w.tabs.set_tab_title(index, item_path.get_file() + (" ●" if dirty else ""))
		w.tabs.set_tab_tooltip(index, item_path)
		if item_path == path: w.tabs.current_tab = index
	w.tabs.set_block_signals(false)
	w.owner.text = str(vm.host).get_slice(".", 0) if vm.connected else "このPC"
	w.editor.editable = accessible
	w.replace_button.disabled = not accessible
	w.save.disabled = not accessible or not unsaved
	w.cursor.text = "%d : %d" % [w.editor.get_caret_line() + 1, w.editor.get_caret_column() + 1]
	w.info.text = (("このPC" if local else str(vm.host)) + "   ·   " + UI.copy("os_unsaved" if unsaved else "os_saved")) if accessible else (UI.copy("os_disconnected") if not path.is_empty() else "UTF-8")
	# Keep operational state in the status bar; the editor surface stays a
	# workbench instead of showing a permanent tutorial footer.
	w.flow.visible = false
	w.next.visible = false
	w.next.disabled = unsaved
	if path.is_empty(): w.hint.text = ""
	elif not accessible: w.hint.text = "未接続 · 下書き保持"
	elif live.get("dirty", false): w.hint.text = "未反映の変更あり"
	elif not live.get("active", false): w.hint.text = "サービス停止中"
	else: w.hint.text = ""
	_fill_tree(d, w, vm)
	if w.find_panel.visible: _find_count(d)
	if w.has("view_popup"):
		w.view_popup.set_item_disabled(3, _baseline(d).is_empty())
	_refresh_compare(d)

static func show_find(d, replace := false) -> void:
	var w: Dictionary = d.widgets.editor
	w.find_panel.show(); w.replace_row.visible = replace
	var selection: String = w.editor.get_selected_text()
	if not selection.is_empty() and not "\n" in selection: w.find_input.text = selection
	w.find_input.grab_focus(); w.find_input.select_all(); _find_count(d)

static func hide_find(d) -> void:
	var w: Dictionary = d.widgets.editor
	w.find_panel.hide(); w.editor.set_search_text(""); w.editor.grab_focus()

static func _find_count(d) -> void:
	var w: Dictionary = d.widgets.editor
	var needle: String = w.find_input.text
	var haystack: String = w.editor.text
	if not w.find_case.button_pressed: needle = needle.to_lower(); haystack = haystack.to_lower()
	w.find_count.text = "%d件" % haystack.count(needle) if not needle.is_empty() else ""
	w.editor.set_search_text(w.find_input.text)
	w.editor.set_search_flags(TextEdit.SEARCH_MATCH_CASE if w.find_case.button_pressed else 0)

static func find_next(d, backwards := false, from_start := false) -> void:
	var w: Dictionary = d.widgets.editor
	var code: CodeEdit = w.editor
	var needle: String = w.find_input.text
	_find_count(d)
	if needle.is_empty(): return
	var line := code.get_caret_line(); var column := code.get_caret_column()
	if from_start: line = 0; column = 0
	elif backwards:
		if code.has_selection(): line = code.get_selection_from_line(); column = code.get_selection_from_column()
		column -= 1
		if column < 0: line = posmod(line-1,code.get_line_count()); column = code.get_line(line).length()
	var flags := (TextEdit.SEARCH_MATCH_CASE if w.find_case.button_pressed else 0) | (TextEdit.SEARCH_BACKWARDS if backwards else 0)
	var found := code.search(needle,flags,line,column)
	if found.x < 0: code.deselect(); return
	code.set_caret_line(found.y); code.set_caret_column(found.x+needle.length())
	code.select(found.y,found.x,found.y,found.x+needle.length())
	code.center_viewport_to_caret()

static func replace_match(d) -> void:
	var w: Dictionary = d.widgets.editor
	var code: CodeEdit = w.editor
	if not code.editable or str(w.find_input.text).is_empty(): return
	var selected := code.get_selected_text()
	var matches: bool = selected == str(w.find_input.text) if w.find_case.button_pressed else selected.to_lower() == str(w.find_input.text).to_lower()
	if matches: code.insert_text_at_caret(str(w.replace_input.text),0)
	find_next(d)

static func _fill_tree(d, w: Dictionary, vm: Dictionary) -> void:
	var files: Array = []
	if vm.connected:
		files.append(str(vm.config_path))
		for folder in ["/var/log", "/home/operator"]:
			for path in d.game.vm_list(folder):
				if not str(path).ends_with("/"): files.append(str(path))
	var local: Array = d.game.state.get("os_files", {}).keys()
	var signature := str(files) + str(local) + str(vm.connected)
	if signature == w.tree_signature: return
	w.tree_signature = signature
	var tree: Tree = w.tree
	tree.clear()
	var root := tree.create_item()
	if vm.connected:
		var remote := tree.create_item(root)
		remote.set_text(0, str(vm.host).get_slice(".", 0))
		remote.set_selectable(0, false)
		var folders := {}
		for item_path in files:
			var folder: String = str(item_path).get_base_dir()
			if not folders.has(folder):
				var branch := tree.create_item(remote); branch.set_text(0, folder.trim_prefix("/")); branch.set_selectable(0,false); folders[folder]=branch
			var item := tree.create_item(folders[folder])
			item.set_text(0, str(item_path).get_file())
			item.set_metadata(0, str(item_path))
			item.set_tooltip_text(0, str(item_path))
	var self_pc := tree.create_item(root)
	self_pc.set_text(0, "このPC")
	self_pc.set_selectable(0, false)
	for item_path in local:
		var item := tree.create_item(self_pc)
		item.set_text(0, str(item_path).get_file())
		item.set_metadata(0, "workstation:" + str(item_path))
		item.set_tooltip_text(0, str(item_path))
