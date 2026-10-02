extends RefCounted
class_name OSBackupConsole

const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const NAV := Color("111111")
const SURFACE := Color("101010")
const LINE := Color("292929")
const INK := Color("e6e6e6")
const MUTED := Color("94999f")
const GREEN := Color("43b653")

static func copy(key: String, fallback: String = "") -> String:
	var value := UI.copy("backup_" + key)
	return value if not value.is_empty() else fallback

static func label(d, parent: Node, text: String, size: int = 14, color: Color = INK) -> Label:
	var node: Label = d._label(text, size, color)
	node.add_theme_font_override("font", UI.font(500 if size >= 18 else 400))
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.clip_text = true
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

static func box(parent: Node, color: Color = SURFACE, padding: int = 16) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UI.style(color, LINE, padding, padding, 3))
	parent.add_child(frame)
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", 10)
	frame.add_child(node)
	return node

static func button(d, parent: Node, text: String, name: String, callback: Callable) -> Button:
	var node: Button = d._button(text, callback)
	node.name = name
	node.custom_minimum_size.y = 34
	parent.add_child(node)
	for kind in ["normal", "hover", "pressed", "focus"]:
		node.add_theme_stylebox_override(kind, UI.style(Color("222428") if kind in ["hover", "pressed"] else NAV, GREEN if kind == "focus" else LINE, 10, 7, 3))
	for kind in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(kind, INK)
	return node

static func persist(d) -> void:
	d._save_session(false)

static func rerender(d) -> void:
	persist(d)
	d._render_backup()

static func run(d, command: String) -> String:
	var raw: String = d._backup_command(command)
	d.backup_ui["output"] = raw
	var success := not raw.begins_with("restic:") and not raw.begins_with("mkdir:") and not raw.begins_with("Error")
	if raw.begins_with("{"):
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary and not bool(parsed.get("ok", true)):
			success = false
	if " backup " in command or " restore " in command or command.begins_with("systemctl restart"):
		d.get_node("/root/Soundscape").play_ui("work_success" if success and bool(d.game._vm().state.active) else "work_failure")
	return raw

static func quote(value: String) -> String:
	return '"' + value.replace('"', '') + '"'

static func _vm_plan(d, repo: String, selector: String, destination: String, includes: Array, overwrite: String) -> Dictionary:
	var vm = d.game._vm()
	if vm.has_method("restic_restore_plan"):
		var result = vm.call("restic_restore_plan", repo, selector, destination, includes, overwrite)
		if result is Dictionary:
			return result
	return {"ok": false, "error": "restore planning unavailable", "entries": [], "fingerprint": ""}

static func _includes(s: Dictionary) -> Array:
	if str(s.get("restore_scope", "all")) != "selected":
		return []
	var path := str(s.get("path", ""))
	return [path] if not path.is_empty() and path != "/" else []

static func _plan_key(repo: String, selector: String, destination: String, includes: Array, overwrite: String) -> String:
	return JSON.stringify([repo, selector, destination, includes, overwrite])

static func _refresh_plan(d, s: Dictionary, snapshot: Dictionary, repo: String, destination: String, explicit_preview: bool = false) -> Dictionary:
	var id := str(snapshot.get("id", ""))
	var includes := _includes(s)
	var overwrite := str(s.get("overwrite", "always"))
	var key := _plan_key(repo, id, destination, includes, overwrite)
	var plan := _vm_plan(d, repo, id, destination, includes, overwrite)
	s["restore_plan"] = plan
	s["plan_key"] = key
	s["plan_fingerprint"] = str(plan.get("fingerprint", JSON.stringify(plan.get("entries", [])).sha256_text()))
	s["plan_previewed"] = explicit_preview
	return plan

static func _execute_restore(d, s: Dictionary, snapshot: Dictionary, repo: String, destination: String) -> void:
	var id := str(snapshot.get("id", ""))
	var includes := _includes(s)
	var overwrite := str(s.get("overwrite", "always"))
	var key := _plan_key(repo, id, destination, includes, overwrite)
	var current := _vm_plan(d, repo, id, destination, includes, overwrite)
	var current_fingerprint := str(current.get("fingerprint", JSON.stringify(current.get("entries", [])).sha256_text()))
	if not bool(s.get("plan_previewed", false)) or not bool(current.get("ok", false)):
		s["restore_result"] = "preview_stale";rerender(d);return
	if str(s.get("plan_key", "")) != key or str(s.get("plan_fingerprint", "")) != current_fingerprint:
		s["restore_plan"] = current
		s["plan_key"] = key
		s["plan_fingerprint"] = current_fingerprint
		s["plan_previewed"] = false
		s["restore_result"] = "preview_stale"
		rerender(d)
		return
	var command := "restic -r " + repo + " restore " + id + " --target " + quote(destination)
	if not includes.is_empty() and d.game._vm().has_method("restic_restore_plan"):
		for include in includes:
			command += " --include " + quote(str(include))
	command += " --overwrite " + overwrite
	var raw := run(d, command)
	var parsed = JSON.parse_string(raw) if raw.begins_with("{") else null
	var succeeded := raw.begins_with("restored ") or (parsed is Dictionary and bool(parsed.get("ok", false)))
	s["restore_result"] = "succeeded" if succeeded else "failed"
	s["plan_previewed"] = false
	s["last_restore_result"] = raw
	persist(d)
	d._render_backup()

static func _set_panel_padding(panel: Control, horizontal: int, vertical: int) -> void:
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null: return
	if not is_equal_approx(style.content_margin_left, horizontal): style.content_margin_left = horizontal
	if not is_equal_approx(style.content_margin_right, horizontal): style.content_margin_right = horizontal
	if not is_equal_approx(style.content_margin_top, vertical): style.content_margin_top = vertical
	if not is_equal_approx(style.content_margin_bottom, vertical): style.content_margin_bottom = vertical

static func _reflow(d, shell: Control, nav_panel: Control, nav_toggle: Button, main_panel: Control, panes: BoxContainer, inventory_panel: Control, chosen: Dictionary, tree: Tree) -> void:
	var text_scale := maxf(1.0, float(d.game.settings.get("text_scale", 1.0)))
	var compact := float(d.windows.browser.size.x) / text_scale < 1100.0
	var compact_nav := compact and not bool(d.backup_ui.get("nav_expanded", false))
	var desired_height := maxf(450.0, float(d.windows.browser.size.y) - 155.0)
	if not is_equal_approx(shell.custom_minimum_size.y, desired_height): shell.custom_minimum_size.y = desired_height
	var nav_width := 152.0 if compact_nav else (184.0 if compact else 248.0)
	if not is_equal_approx(nav_panel.custom_minimum_size.x, nav_width): nav_panel.custom_minimum_size.x = nav_width
	nav_toggle.visible = compact
	nav_toggle.text = "›" if compact_nav else "‹"
	_set_panel_padding(nav_panel, 12 if compact else 16, 12 if compact else 16)
	_set_panel_padding(main_panel, 12 if compact else 18, 12 if compact else 18)
	if panes.vertical != compact: panes.vertical = compact
	var separation := 12 if compact else 16
	if panes.get_theme_constant("separation") != separation: panes.add_theme_constant_override("separation", separation)
	var inventory_width := 0.0 if compact else 360.0
	if not is_equal_approx(inventory_panel.custom_minimum_size.x, inventory_width): inventory_panel.custom_minimum_size.x = inventory_width
	inventory_panel.size_flags_horizontal = Control.SIZE_FILL if not compact else Control.SIZE_EXPAND_FILL
	inventory_panel.visible = not compact or chosen.is_empty()
	if is_instance_valid(tree):
		var tree_height := 310.0 if compact else 270.0
		if not is_equal_approx(tree.custom_minimum_size.y, tree_height): tree.custom_minimum_size.y = tree_height

static func render(d, parent: VBoxContainer) -> void:
	var s: Dictionary = d.backup_ui
	var live: Dictionary = d.game._vm().state
	if not s.has("repository"):s["repository"] = str(live.applied.get("repository", "local"))
	if not s.has("plan_open"):s["plan_open"] = false
	var repo := str(s.get("repository", "local"))
	var text_scale := maxf(1.0, float(d.game.settings.get("text_scale", 1.0)))
	var compact := float(d.windows.browser.size.x) / text_scale < 1100.0
	var compact_nav := compact and not bool(s.get("nav_expanded", false))
	var masthead := box(parent, Color("1c252d"), 12)
	var top := HBoxContainer.new();top.custom_minimum_size.y = 34;top.add_theme_constant_override("separation", 12);masthead.add_child(top)
	Glyph.add_to(top, "process", 30, INK)
	var brand:=label(d, top, "Backrest", 24);brand.clip_text=false;brand.custom_minimum_size.x=160;brand.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var host := label(d, top, str(live.host), 13, MUTED);host.tooltip_text=str(live.host);host.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var shell := HBoxContainer.new();shell.name = "BackupResponsiveShell";shell.add_theme_constant_override("separation", 0);shell.custom_minimum_size.y = maxf(450.0, float(d.windows.browser.size.y) - 155.0);parent.add_child(shell)
	var nav := box(shell, NAV, 12 if compact_nav else (12 if compact else 16));nav.get_parent().custom_minimum_size.x = 152 if compact_nav else (184 if compact else 248);nav.get_parent().size_flags_horizontal = Control.SIZE_FILL
	var nav_toggle := button(d, nav, "›" if compact_nav else "‹", "BackupNavigationToggle", func():s["nav_expanded"] = not bool(s.get("nav_expanded", false));rerender(d))
	nav_toggle.tooltip_text = "Backrest navigation"
	nav_toggle.visible = compact
	nav_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(d, nav, copy("plan", "Plans"), 14)
	var plan_link := button(d, nav, "/srv/data", "BackupPlan", func():s["plan_open"] = not bool(s.get("plan_open", false));rerender(d));plan_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	plan_link.tooltip_text = copy("plan", "Plans") + "  /srv/data"
	label(d, nav, copy("repositories", "Repositories"), 14)
	for repository in ["local", "offsite"]:
		var item := button(d, nav, repository, "BackupRepo_" + repository, func():s["repository"] = repository;s.erase("snapshot");s.erase("path");s.erase("preview");s.erase("restore_plan");run(d, "restic -r " + repository + " snapshots");rerender(d))
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.tooltip_text = copy("repositories", "Repositories") + " · " + repository
		item.add_theme_stylebox_override("normal", UI.style(Color("25272a") if repository == repo else NAV, Color.TRANSPARENT, 10, 10, 3))
	var nav_fill := Control.new();nav_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL;nav.add_child(nav_fill)
	var main := box(shell, Color("090909"), 12 if compact else 18);main.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := HBoxContainer.new();title.add_theme_constant_override("separation", 8);main.add_child(title)
	label(d, title, repo, 22)
	button(d, title, copy("refresh", "Refresh"), "BackupRefresh", func():run(d, "restic -r " + repo + " snapshots");rerender(d))
	button(d, title, copy("backup_now", "Backup now"), "BackupNow", func():run(d, "restic -r " + repo + " backup /srv/data");rerender(d))
	_plan(d, main, s, live)
	var panes := BoxContainer.new();panes.name = "BackupSnapshotPanes";panes.vertical = compact;panes.add_theme_constant_override("separation", 16);panes.size_flags_horizontal = Control.SIZE_EXPAND_FILL;panes.size_flags_vertical = Control.SIZE_EXPAND_FILL;main.add_child(panes)
	var inventory := box(panes);inventory.get_parent().custom_minimum_size.x = 0 if compact else 360;inventory.get_parent().size_flags_horizontal = Control.SIZE_FILL if not compact else Control.SIZE_EXPAND_FILL
	label(d, inventory, copy("snapshots", "Snapshots"), 16)
	var snapshot_table := VBoxContainer.new();snapshot_table.name = "BackupSnapshotTable";snapshot_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL;snapshot_table.add_theme_constant_override("separation", 18);inventory.add_child(snapshot_table)
	var shown := 0
	var chosen: Dictionary = {}
	for snapshot in live.get("snapshots", []):
		if str(snapshot.get("repository", "")) != repo:continue
		shown += 1
		var id := str(snapshot.get("id", ""));var bytes := 0
		for content in snapshot.get("files", {}).values():bytes += str(content).to_utf8_buffer().size()
		var snapshot_row := VBoxContainer.new();snapshot_row.add_theme_constant_override("separation", 5);snapshot_table.add_child(snapshot_row)
		var select := button(d, snapshot_row, id, "BackupSnapshot_" + id, func():s["snapshot"] = id;s.erase("path");s.erase("preview");s.erase("restore_plan");s.erase("restore_open");run(d, "restic -r " + repo + " ls " + id);rerender(d))
		select.icon=_tree_icon(false);select.custom_minimum_size.y = 42;select.alignment = HORIZONTAL_ALIGNMENT_LEFT;select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label(d, snapshot_row, "; ".join(PackedStringArray(snapshot.get("paths", []))), 12, MUTED)
		label(d,snapshot_row,UI.copy("fidelity_file_count")+" "+str(snapshot.get("files",{}).size())+"    "+str(bytes)+" B",12,MUTED)
		label(d,snapshot_row,"保存順 " + str(shown) + " / " + str(snapshot.get("repository", "")),12,MUTED)
		if id == str(s.get("snapshot", "")):
			chosen = snapshot;select.add_theme_stylebox_override("normal", UI.style(Color("242629"), LINE, 10, 7, 3))
	if shown == 0:label(d, inventory, copy("no_snapshots", "No snapshots"), 13, MUTED)
	var details := box(panes);details.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory.get_parent().visible = not compact or chosen.is_empty()
	if chosen.is_empty():label(d, details, copy("select_snapshot", "Select a snapshot"), 14, MUTED)
	else:_snapshot(d, details, s, chosen, repo)
	var nav_panel := nav.get_parent() as Control
	var main_panel := main.get_parent() as Control
	var inventory_panel := inventory.get_parent() as Control
	var tree := main.find_child("BackupSnapshotTree", true, false) as Tree
	shell.resized.connect(func():
		if is_instance_valid(shell): _reflow(d, shell, nav_panel, nav_toggle, main_panel, panes, inventory_panel, chosen, tree)
	)
	_reflow(d, shell, nav_panel, nav_toggle, main_panel, panes, inventory_panel, chosen, tree)
	var output := str(s.get("output", ""))
	if not output.is_empty():
		button(d,main,("▾  " if bool(s.get("output_open",false)) else "▸  ")+copy("result"),"BackupOutputToggle",func():s["output_open"]=not bool(s.get("output_open",false));rerender(d)).alignment=HORIZONTAL_ALIGNMENT_LEFT
		if bool(s.get("output_open",false)):
			var log:=TextEdit.new();log.name="BackupOutput";log.editable=false;log.text=output;log.custom_minimum_size.y=85;log.add_theme_font_override("font",d.mono);_dark_input(log);main.add_child(log)
	var restore_result := str(s.get("restore_result", ""))
	if not restore_result.is_empty() and not bool(s.get("restore_open", false)):
		var result_key := "preview_stale" if restore_result == "preview_stale" else "restore_" + restore_result
		var result_label := label(d, main, copy(result_key, restore_result), 12, GREEN if restore_result == "succeeded" else Color("ef6b6b"));result_label.name = "BackupRestoreResult"
	var last: Dictionary = live.get("last_restore", {})
	if not last.is_empty():
		var footer := HFlowContainer.new();main.add_child(footer);label(d, footer, copy("restored", "Previous restore") + "  " + str(last.get("snapshot", "")) + "  →  " + str(last.get("target", "")), 12, MUTED)
		button(d, footer, copy("open_files", "Open restored folder"), "BackupOpenFiles", func():d._show_app("files");d.FILES.navigate(d, str(last.get("target", "/restore")), true))

static func _dark_input(node: Control) -> void:
	for kind in ["normal", "read_only"]:node.add_theme_stylebox_override(kind, UI.style(Color("17191c"), LINE, 8, 7, 3))
	for kind in ["font_color", "font_readonly_color", "font_uneditable_color"]:node.add_theme_color_override(kind, INK)
	node.add_theme_color_override("caret_color", INK)

static func _plan(d, parent: Node, s: Dictionary, live: Dictionary) -> void:
	var plan := box(parent)
	var row := HFlowContainer.new();row.add_theme_constant_override("h_separation", 10);row.add_theme_constant_override("v_separation", 6);plan.add_child(row)
	var plan_caption:=label(d,row,copy("plan"),13,MUTED);plan_caption.clip_text=false;plan_caption.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var schedule := OptionButton.new();schedule.name = "BackupSchedule";schedule.add_item(copy("disabled", "Disabled"));schedule.add_item(copy("daily", "Daily"));schedule.select(1 if str(s.get("plan_schedule", live.applied.get("schedule", "off"))) == "daily" else 0);row.add_child(schedule);_dark_input(schedule)
	schedule.item_selected.connect(func(index):s["plan_schedule"] = "daily" if index == 1 else "off";persist(d))
	var repository := OptionButton.new();repository.name = "BackupPlanRepository";repository.add_item("local");repository.add_item("offsite");repository.select(1 if str(s.get("plan_repository", live.applied.get("repository", "local"))) == "offsite" else 0);row.add_child(repository);_dark_input(repository)
	repository.item_selected.connect(func(index):s["plan_repository"] = "offsite" if index == 1 else "local";persist(d))
	button(d, row, copy("save_plan", "Save plan"), "BackupSavePlan", func():
		var config: Dictionary = live.applied.duplicate(true);config.schedule = "daily" if schedule.selected == 1 else "off";config.repository = "offsite" if repository.selected == 1 else "local"
		var was_refreshing: bool = d.refreshing;d.refreshing = true
		var saved: bool = d.game.vm_write(str(live.config_path), d.game._vm().configuration_text(config));d.refreshing = was_refreshing
		if saved:run(d, "systemctl restart restic");s.erase("plan_schedule");s.erase("plan_repository")
		else:s["output"] = "restic: configuration save failed"
		rerender(d))
	plan.get_parent().visible = bool(s.get("plan_open", false))

static func _tree(d, parent: Node, s: Dictionary, snapshot: Dictionary, repo: String, source: String) -> void:
	var tree := Tree.new();tree.name = "BackupSnapshotTree";tree.hide_root = false;tree.columns = 2;tree.custom_minimum_size.y = 310 if float(d.windows.browser.size.x)<1100 else 270;tree.size_flags_vertical = Control.SIZE_EXPAND_FILL;tree.add_theme_font_override("font", UI.font(400));tree.add_theme_color_override("font_color", INK);tree.add_theme_color_override("font_selected_color", INK);tree.add_theme_color_override("guide_color", LINE);tree.add_theme_stylebox_override("panel", UI.style(SURFACE, LINE, 8, 8, 1));tree.add_theme_stylebox_override("selected", UI.style(Color("242629"),Color.TRANSPARENT,2,2,2));tree.add_theme_stylebox_override("selected_focus", UI.style(Color("242629"),GREEN,2,2,2));tree.set_column_expand(1,false);tree.set_column_custom_minimum_width(1,70);parent.add_child(tree)
	var root := tree.create_item();root.set_text(0, "/");root.set_metadata(0, "/");root.set_metadata(1, "folder");root.set_icon(0, _tree_icon(true))
	var folders: Dictionary = {"": root}
	var source_parent: TreeItem = root
	var source_key := ""
	for source_part in source.trim_prefix("/").split("/"):
		if str(source_part).is_empty():continue
		source_key = str(source_part) if source_key.is_empty() else source_key + "/" + str(source_part)
		var source_folder := tree.create_item(source_parent);source_folder.set_text(0, str(source_part));source_folder.set_icon(0, _tree_icon(true));source_folder.set_metadata(0, "/" + source_key);source_folder.set_metadata(1, "folder");source_parent = source_folder
		if str(s.get("path", "")) == "/"+source_key:source_folder.select(0)
	folders[""] = source_parent
	var names: Array[String] = []
	for raw_name in snapshot.get("files", {}).keys():names.append(str(raw_name))
	names.sort()
	for name in names:
		var parts := name.split("/");var parent_path := ""
		for index in range(parts.size()):
			var part := str(parts[index]);var path := part if parent_path.is_empty() else parent_path + "/" + part;var is_file := index == parts.size() - 1
			if is_file:
				var absolute_path := source.path_join(name)
				var item := tree.create_item(folders.get(parent_path, source_parent));item.set_text(0, part);item.set_icon(0, _tree_icon(false));item.set_text(1, str(str(snapshot.files[name]).to_utf8_buffer().size()) + " B");item.set_metadata(0, absolute_path);item.set_metadata(1, "file")
				if str(s.get("path", "")) == absolute_path:item.select(0)
			else:
				if not folders.has(path):
					var folder := tree.create_item(folders.get(parent_path, source_parent));folder.set_text(0, part);folder.set_icon(0, _tree_icon(true));folder.set_metadata(0, source.path_join(path));folder.set_metadata(1, "folder");folders[path] = folder
				parent_path = path
	tree.item_selected.connect(func():
		var item: TreeItem = tree.get_selected();var path := str(item.get_metadata(0))
		if path.is_empty():return
		s["path"] = path;s["restore_scope"] = "selected";s["restore_open"] = false;s["restore_plan"] = {}
		if str(item.get_metadata(1)) == "file":s["preview"] = run(d, "restic -r " + repo + " dump " + str(snapshot.get("id", "")) + " " + quote(path))
		else:s.erase("preview")
		persist(d);d._render_backup())

static func _plan_rows(d, parent: Node, entries: Array) -> void:
	for entry in entries:
		if not entry is Dictionary:continue
		var card := box(parent,SURFACE,10)
		var path_row := HBoxContainer.new();path_row.add_theme_constant_override("separation",8);card.add_child(path_row)
		Glyph.add_to(path_row,"file",20,INK)
		var destination:=label(d,path_row,str(entry.get("path","")),13,INK);destination.tooltip_text=destination.text
		var status:=str(entry.get("status",""))
		var badge:=label(d,path_row,copy("status_"+status),12,GREEN if status in ["new","unchanged"] else Color("efc45d"));badge.custom_minimum_size.x=80;badge.size_flags_horizontal=Control.SIZE_SHRINK_END
		label(d,card,str(entry.get("bytes",0))+" B",12,MUTED)
		for pair in [["current_hash","current_sha256"],["snapshot_hash","snapshot_sha256"]]:
			var value:=str(entry.get(pair[1],""));var digest:=label(d,card,copy(pair[0])+"  "+(value if not value.is_empty() else "—"),12,MUTED);digest.add_theme_font_override("font",d.mono);digest.tooltip_text=value

static var _tree_icons: Dictionary = {}
static func _tree_icon(folder: bool) -> Texture2D:
	var key:="folder" if folder else "file"
	if not _tree_icons.has(key):
		var shape:='<path d="M2 5h7l3 3h10v13H2z"/>' if folder else '<path d="M5 2h10l5 5v15H5z M15 2v6h5 M8 12h9 M8 16h9"/>'
		var pixels:=Image.new();pixels.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#c9cdd2" stroke-width="1.5" stroke-linejoin="round">'+shape+'</g></svg>')
		_tree_icons[key]=ImageTexture.create_from_image(pixels)
	return _tree_icons[key]

static func _snapshot(d, parent: Node, s: Dictionary, snapshot: Dictionary, repo: String) -> void:
	var id := str(snapshot.get("id", ""))
	var heading := HBoxContainer.new();parent.add_child(heading);Glyph.add_to(heading, "file", 24, GREEN);label(d, heading, copy("snapshot", "Snapshot") + "  " + id, 17)
	button(d, heading, "×", "BackupBackSnapshots", func():s.erase("snapshot");s.erase("path");s.erase("preview");s.erase("restore_plan");s.erase("restore_open");rerender(d)).tooltip_text = copy("back", "Back")
	button(d, heading, copy("restore", "Restore all"), "BackupRestore", func():s["restore_scope"] = "all";s["restore_open"] = true;s.erase("restore_plan");rerender(d))
	var source := str(snapshot.get("paths", ["/srv/data"])[0])
	if bool(s.get("restore_open", false)):
		_restore_form(d, parent, s, snapshot, repo, source);return
	label(d, parent, copy("browse", "Snapshot browser"), 14)
	label(d, parent, source + "/", 14, MUTED)
	var breadcrumb := HBoxContainer.new();breadcrumb.name = "BackupBreadcrumb";breadcrumb.add_theme_constant_override("separation", 4);parent.add_child(breadcrumb)
	var breadcrumb_path := source
	var selected_path := str(s.get("path", ""))
	if selected_path.begins_with(source + "/"):
		var relative: Array = Array(selected_path.trim_prefix(source + "/").split("/"))
		if not relative.is_empty() and not bool(s.get("preview", "").is_empty()):relative.pop_back()
		for segment in relative:
			breadcrumb_path = breadcrumb_path.path_join(str(segment))
			var crumb_path := breadcrumb_path
			button(d, breadcrumb, str(segment), "BackupBreadcrumb_" + str(breadcrumb.get_child_count()), func():s["path"] = crumb_path;s["restore_scope"] = "selected";s["restore_open"] = false;s.erase("preview");s.erase("restore_plan");rerender(d)).custom_minimum_size.y = 28
	_tree(d, parent, s, snapshot, repo, source)
	if not str(s.get("path", "")).is_empty():
		var path_row := HBoxContainer.new();path_row.add_theme_constant_override("separation", 8);parent.add_child(path_row);label(d, path_row, str(s.path), 12, MUTED)
		button(d, path_row, copy("restore_to_path", "Restore selected"), "BackupRestoreToPath", func():s["restore_scope"] = "selected";s["restore_open"] = true;s.erase("restore_plan");rerender(d))
		var relative := str(s.path).trim_prefix(source.trim_suffix("/") + "/")
		if snapshot.get("files", {}).has(relative): _compare_contents(d, parent, s, snapshot, source, relative)

static func _compare_contents(d, parent: Node, s: Dictionary, snapshot: Dictionary, source: String, relative: String) -> void:
	var card := box(parent, Color("14191d"), 10); card.name = "BackupContentComparison"
	var live: Dictionary = d.game._vm().state
	var controls := HFlowContainer.new(); controls.add_theme_constant_override("h_separation", 8); card.add_child(controls)
	label(d, controls, "内容を比較", 15)
	button(d, controls, "稼働中のファイル", "BackupCompareLive", func(): s["compare_target"] = "live"; rerender(d))
	var last: Dictionary = live.get("last_restore", {})
	var restored := str(last.get("snapshot", "")) == str(snapshot.get("id", "")) and not last.is_empty()
	if restored: button(d, controls, "復元先のファイル", "BackupCompareRestored", func(): s["compare_target"] = "restored"; rerender(d))
	var destination := source.path_join(relative)
	if restored and str(s.get("compare_target", "live")) == "restored": destination = str(last.get("target", "/restore")).path_join(source.trim_prefix("/")).path_join(relative)
	var saved := str(snapshot.files[relative])
	var exists: bool = live.get("fs", {}).has(destination)
	var current := str(live.get("fs", {}).get(destination, ""))
	var status := "内容が一致" if exists and current == saved else "内容が異なります" if exists else "比較先にファイルがありません"
	var outcome := label(d, card, status + "  /  " + destination, 12, GREEN if exists and current == saved else Color("efc45d")); outcome.name = "BackupComparisonStatus"; outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; outcome.clip_text = false; outcome.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING; outcome.custom_minimum_size.y = 24
	var panes := BoxContainer.new(); panes.vertical = float(d.windows.browser.size.x) / maxf(1.0, float(d.game.settings.get("text_scale", 1.0))) < 1100; panes.add_theme_constant_override("separation", 8); card.add_child(panes)
	for entry in [["保存 " + str(snapshot.get("id", "")), saved, "BackupPreview"], ["現在 " + destination, current if exists else "（ファイルなし）", "BackupCurrentPreview"]]:
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panes.add_child(column)
		var bytes := str(str(entry[1]).to_utf8_buffer().size()) + " B" if str(entry[2]) == "BackupPreview" or exists else "未作成"
		var heading := label(d, column, str(entry[0]) + "  " + bytes, 12, MUTED); heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; heading.clip_text = false; heading.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING; heading.custom_minimum_size.y = 24
		var preview := TextEdit.new(); preview.name = str(entry[2]); preview.editable = false; preview.text = str(entry[1]); preview.custom_minimum_size.y = 110; preview.add_theme_font_override("font", d.mono); _dark_input(preview); column.add_child(preview)

static func _restore_form(d, parent: Node, s: Dictionary, snapshot: Dictionary, repo: String, _source: String) -> void:
	var restore := box(parent, Color("17191c"));restore.name="BackupRestorePane"
	label(d, restore, copy("restore_review"), 16)
	var outcome:=str(s.get("restore_result",""))
	if not outcome.is_empty():
		var outcome_label:=label(d,restore,copy("preview_stale" if outcome=="preview_stale" else "restore_"+outcome),13,GREEN if outcome=="succeeded" else Color("ef6b6b"));outcome_label.name="BackupRestoreResult"
	var close_row := HBoxContainer.new();close_row.add_theme_constant_override("separation", 8);restore.add_child(close_row)
	button(d, close_row, copy("close", "Close"), "BackupCloseRestore", func():s["restore_open"] = false;rerender(d))
	label(d, close_row, copy("selected_path") + "  " + (str(s.get("path", "")) if str(s.get("restore_scope", "all")) == "selected" else copy("all_files", "All files")), 12, MUTED)
	label(d, restore, copy("restore_to", "Restore destination"), 13)
	var destination := LineEdit.new();destination.name = "BackupDestination";destination.text = str(s.get("destination", "/restore"));_dark_input(destination);restore.add_child(destination);destination.text_changed.connect(func(value):s["destination"] = value;s["plan_previewed"] = false;var execute_node=restore.find_child("BackupExecuteRestore",true,false);if execute_node != null:execute_node.disabled=true;persist(d))
	var overwrite := OptionButton.new();overwrite.name = "BackupOverwrite";overwrite.add_item(copy("overwrite_always", "Overwrite existing"));overwrite.add_item(copy("overwrite_never", "Skip existing"));overwrite.select(1 if str(s.get("overwrite", "always")) == "never" else 0);restore.add_child(overwrite);_dark_input(overwrite);overwrite.item_selected.connect(func(index):s["overwrite"] = "never" if index == 1 else "always";s.erase("restore_plan");s["plan_previewed"]=false;rerender(d))
	var plan: Dictionary = s.get("restore_plan", {}) if s.get("restore_plan", {}) is Dictionary else {}
	var entries: Array = plan.get("entries", []) if bool(plan.get("ok", false)) else []
	var preview_row := HBoxContainer.new();preview_row.add_theme_constant_override("separation", 8);restore.add_child(preview_row)
	button(d, preview_row, copy("preview_changes", "Preview changes"), "BackupPreviewChanges", func():
		var destination_now := destination.text.strip_edges()
		if destination_now.is_empty():destination_now = "/restore"
		_refresh_plan(d, s, snapshot, repo, destination_now, true)
		rerender(d))
	if plan.has("error") and not str(plan.error).is_empty():label(d,restore,str(plan.error),13,Color("ef6b6b"))
	var counts := {"new":0,"unchanged":0,"overwrite":0,"skipped":0}
	for entry in entries:
		if entry is Dictionary:counts[str(entry.get("status", ""))] = int(counts.get(str(entry.get("status", "")), 0)) + 1
	label(d, restore, "%s: %d  %s: %d  %s: %d  %s: %d" % [copy("status_new", "New"),counts.new,copy("status_unchanged", "Unchanged"),counts.unchanged,copy("status_overwrite", "Overwrite"),counts.overwrite,copy("status_skipped", "Skipped"),counts.skipped], 12, MUTED)
	var plan_table := VBoxContainer.new();plan_table.name = "BackupPlanEntries";plan_table.add_theme_constant_override("separation", 6);restore.add_child(plan_table);_plan_rows(d, plan_table, entries)
	var actions := HBoxContainer.new();actions.add_theme_constant_override("separation", 8);restore.add_child(actions)
	var execute := button(d, actions, copy("execute_restore", "Restore"), "BackupExecuteRestore", func():_execute_restore(d, s, snapshot, repo, destination.text.strip_edges() if not destination.text.strip_edges().is_empty() else "/restore"));execute.disabled = entries.is_empty() or not bool(s.get("plan_previewed", false))
