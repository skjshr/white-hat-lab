extends RefCounted
class_name OSBackupConsole

const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const Visual = preload("res://scripts/backup_visual.gd")
const Document = preload("res://scripts/backup_document.gd")
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
	var node: Button = d._button(text, func(): callback.call(); _focus_after(d, name))
	node.name = name
	node.custom_minimum_size.y = 34
	parent.add_child(node)
	for kind in ["normal", "hover", "pressed", "focus"]:
		node.add_theme_stylebox_override(kind, UI.style(Color("222428") if kind in ["hover", "pressed"] else NAV, GREEN if kind == "focus" else LINE, 10, 7, 3))
	for kind in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(kind, INK)
	return node

static func _focus_after(d, preferred: String) -> void:
	# Actions rebuild the page. Keep keyboard users in this work area after the
	# old button is freed, without executing another command or measurement.
	var desktop_ref: WeakRef = weakref(d)
	d.get_tree().process_frame.connect(func():
		var desktop = desktop_ref.get_ref()
		if not is_instance_valid(desktop) or desktop.current_app != "browser": return
		var page: Node = desktop.widgets.get("browser", {}).get("page")
		if not is_instance_valid(page): return
		for id in [preferred, "BackupFileToggle", "BackupPreviewChanges", "BackupSnapshotChoice", "BackupRefresh"]:
			var target := page.find_child(id, true, false) as Control
			if not is_instance_valid(target) or not target.is_visible_in_tree() or (target is BaseButton and target.disabled): continue
			target.grab_focus()
			var ancestor: Node = target.get_parent()
			while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
			if ancestor is ScrollContainer: ancestor.ensure_control_visible(target)
			break
	, CONNECT_ONE_SHOT)

static func _wrapped(d, parent: Node, text: String, name: String, size: int = 12, color: Color = MUTED) -> Label:
	var value := label(d, parent, text, size, color)
	value.name = name; value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.clip_text = false; value.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return value

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
	var desired_height := maxf(280.0, float(d.windows.browser.size.y) - 155.0)
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
		var tree_height := 156.0 if compact else 220.0
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
	masthead.get_parent().visible = not compact
	var top := HBoxContainer.new();top.custom_minimum_size.y = 34;top.add_theme_constant_override("separation", 12);masthead.add_child(top)
	Glyph.add_to(top, "process", 30, INK)
	var brand:=label(d, top, "Backrest", 24);brand.clip_text=false;brand.custom_minimum_size.x=160;brand.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var host := label(d, top, str(live.host), 13, MUTED);host.tooltip_text=str(live.host);host.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var shell := HBoxContainer.new();shell.name = "BackupResponsiveShell";shell.add_theme_constant_override("separation", 0);shell.custom_minimum_size.y = maxf(280.0, float(d.windows.browser.size.y) - 155.0);parent.add_child(shell)
	var nav := box(shell, NAV, 12 if compact_nav else (12 if compact else 16));nav.get_parent().custom_minimum_size.x = 152 if compact_nav else (184 if compact else 248);nav.get_parent().size_flags_horizontal = Control.SIZE_FILL
	var nav_toggle := button(d, nav, "›" if compact_nav else "‹", "BackupNavigationToggle", func():s["nav_expanded"] = not bool(s.get("nav_expanded", false));rerender(d))
	nav_toggle.tooltip_text = "Backrest navigation"
	nav_toggle.visible = compact
	nav_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(d, nav, "計画", 14)
	var plan_link := button(d, nav, "/srv/data", "BackupPlan", func():s["plan_open"] = not bool(s.get("plan_open", false));rerender(d));plan_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	plan_link.tooltip_text = copy("plan", "Plans") + "  /srv/data"
	label(d, nav, "保存先", 14)
	for repository in ["local", "offsite"]:
		var item := button(d, nav, repository, "BackupRepo_" + repository, func():s["repository"] = repository;s.erase("snapshot");s.erase("path");s.erase("preview");s.erase("restore_plan");run(d, "restic -r " + repository + " snapshots");rerender(d))
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.tooltip_text = copy("repositories", "Repositories") + " · " + repository
		item.add_theme_stylebox_override("normal", UI.style(Color("25272a") if repository == repo else NAV, Color.TRANSPARENT, 10, 10, 3))
	var nav_fill := Control.new();nav_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL;nav.add_child(nav_fill)
	var main := box(shell, Color("090909"), 12 if compact else 18);main.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := HBoxContainer.new();title.add_theme_constant_override("separation", 8);main.add_child(title)
	title.visible = not compact or str(s.get("snapshot", "")).is_empty()
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
		var select := button(d, snapshot_row, id, "BackupSnapshot_" + id, func():_select_snapshot(d, s, snapshot, repo))
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
		var result_label := _wrapped(d, main, "復元処理が完了 · 顧客指定内容の照合は別途確認" if restore_result == "succeeded" else copy(result_key, restore_result), "BackupRestoreResult", 12, GREEN if restore_result == "succeeded" else Color("ef6b6b"))
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
		s["file_list_open"] = false
		if str(item.get_metadata(1)) == "file":s["preview"] = run(d, "restic -r " + repo + " dump " + str(snapshot.get("id", "")) + " " + quote(path))
		else:s.erase("preview")
		# Tree still processes the mouse event after item_selected. Rebuild only
		# after that event finishes so its viewport remains valid during dispatch.
		persist(d);d._render_backup.call_deferred();_focus_after(d,"BackupFileToggle"))

static func _plan_rows(d, parent: Node, entries: Array) -> void:
	var fs: Dictionary=d.game._vm().state.get("fs",{})
	for entry in entries:
		if not entry is Dictionary:continue
		var card := box(parent,SURFACE,8);card.set_meta("restore_entry",entry.duplicate(true));card.add_theme_constant_override("separation",5)
		var target:=str(entry.get("path",""));var source:=str(entry.get("source",""));var status:=str(entry.get("status",""))
		_wrapped(d,card,source.get_file()+"  →  "+target,"BackupPlanRoute",12,INK)
		var current := str(fs.get(target,""));var exists: bool=fs.has(target)
		var after := current if status=="skipped" else str(entry.get("value",""))
		var comparison := Visual.comparison(after,current,exists)
		var flow := HBoxContainer.new();flow.add_theme_constant_override("separation",8);card.add_child(flow)
		_document_card(d,flow,comparison.current,"変更前",target.get_file(),"BackupPlanBefore",comparison.changed_keys)
		var middle := VBoxContainer.new();middle.custom_minimum_size.x=48;middle.size_flags_vertical=Control.SIZE_SHRINK_CENTER;flow.add_child(middle)
		var arrow := label(d,middle,"→" if status in ["new","overwrite"] else "＝",24,Color("efc45d") if status=="overwrite" else INK);arrow.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_wrapped(d,middle,copy("status_"+status,status),"BackupPlanOperation",11,Color("efc45d") if status=="overwrite" else MUTED)
		_document_card(d,flow,Visual.document(after,exists or status!="skipped"),"変更予定",target.get_file(),"BackupPlanAfter",comparison.changed_keys)
		var detail := VBoxContainer.new();detail.visible=bool(d.backup_ui.get("plan_details",false));card.add_child(detail)
		_wrapped(d,detail,"保存元: "+source+"\n復元先: "+target+"\n"+str(entry.get("bytes",0))+" B","BackupPlanFullPaths",11)
		for pair in [["current_hash","current_sha256"],["snapshot_hash","snapshot_sha256"]]:
			var value:=str(entry.get(pair[1],""));_wrapped(d,detail,copy(pair[0])+"  "+(value if not value.is_empty() else "—"),"BackupPlanHash",11)

static var _tree_icons: Dictionary = {}
static func _tree_icon(folder: bool) -> Texture2D:
	var key:="folder" if folder else "file"
	if not _tree_icons.has(key):
		var shape:='<path d="M2 5h7l3 3h10v13H2z"/>' if folder else '<path d="M5 2h10l5 5v15H5z M15 2v6h5 M8 12h9 M8 16h9"/>'
		var pixels:=Image.new();pixels.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#c9cdd2" stroke-width="1.5" stroke-linejoin="round">'+shape+'</g></svg>')
		_tree_icons[key]=ImageTexture.create_from_image(pixels)
	return _tree_icons[key]

static func _select_snapshot(d, s: Dictionary, snapshot: Dictionary, repo: String) -> void:
	var id := str(snapshot.get("id", ""))
	var source := str(snapshot.get("paths", ["/srv/data"])[0])
	var relative := str(s.get("path", "")).trim_prefix(source.trim_suffix("/") + "/")
	s["snapshot"] = id; s.erase("preview"); s.erase("restore_plan"); s.erase("restore_open")
	s["plan_previewed"] = false; s.erase("restore_result"); s["compare_target"] = "live"
	if not snapshot.get("files", {}).has(relative): s.erase("path")
	run(d, "restic -r " + repo + " ls " + id)
	if not str(s.get("path", "")).is_empty(): s["preview"] = run(d, "restic -r " + repo + " dump " + id + " " + quote(str(s.path)))
	rerender(d)

static func _snapshot(d, parent: Node, s: Dictionary, snapshot: Dictionary, repo: String) -> void:
	parent.add_theme_constant_override("separation",6)
	var id := str(snapshot.get("id", ""))
	var heading := HBoxContainer.new();heading.add_theme_constant_override("separation",8);parent.add_child(heading)
	var chooser := OptionButton.new();chooser.name="BackupSnapshotChoice";chooser.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(chooser);_dark_input(chooser)
	var options: Array = [];var ordinal := 0;var selected_order := 0
	for item in d.game._vm().state.get("snapshots", []):
		if str(item.get("repository", "")) != repo: continue
		ordinal += 1;options.append(item)
		chooser.add_item("%s %s · 保存順 %d" % [copy("snapshot", "Snapshot"),str(item.get("id", "")),ordinal])
		if str(item.get("id", "")) == id: chooser.select(chooser.item_count-1);selected_order=ordinal
	chooser.item_selected.connect(func(index):_select_snapshot(d,s,options[index],repo);_focus_after(d,"BackupSnapshotChoice"))
	button(d, heading, "×", "BackupBackSnapshots", func():s.erase("snapshot");s.erase("path");s.erase("preview");s.erase("restore_plan");s.erase("restore_open");rerender(d)).tooltip_text = copy("back", "Back")
	button(d, heading, copy("restore", "Restore all"), "BackupRestore", func():s["restore_scope"] = "all";s["restore_open"] = true;s.erase("restore_plan");rerender(d))
	var source := str(snapshot.get("paths", ["/srv/data"])[0])
	var context := _wrapped(d,parent,"%s · 保存順 %d · 取得時刻の記録なし" % [repo,selected_order],"BackupSnapshotContext")
	context.visible=bool(s.get("content_details",false))
	if bool(s.get("restore_open", false)):
		_restore_form(d, parent, s, snapshot, repo, source);return
	var selected_path := str(s.get("path", ""))
	var relative := selected_path.trim_prefix(source.trim_suffix("/") + "/")
	var selected_file: bool = snapshot.get("files", {}).has(relative)
	var file_row := HBoxContainer.new();file_row.add_theme_constant_override("separation",8);parent.add_child(file_row)
	_wrapped(d,file_row,selected_path if not selected_path.is_empty() else "ファイルを選択","BackupSelectedPath",13,INK)
	button(d,file_row,"一覧を閉じる" if bool(s.get("file_list_open",not selected_file)) else "ファイル選択","BackupFileToggle",func():s["file_list_open"]=not bool(s.get("file_list_open",not selected_file));rerender(d))
	var file_list := VBoxContainer.new();file_list.name="BackupFileList";file_list.visible=bool(s.get("file_list_open",not selected_file));parent.add_child(file_list)
	_tree(d, file_list, s, snapshot, repo, source)
	if not selected_path.is_empty():
		if selected_file:_compare_contents(d, parent, s, snapshot, source, relative)
		else:button(d,parent,copy("restore_to_path", "Restore selected"),"BackupRestoreToPath",func():s["restore_scope"]="selected";s["restore_open"]=true;s.erase("restore_plan");rerender(d))
	_acceptance(d,parent)

static func _comparison_restore_path(live: Dictionary, source_path: String) -> String:
	# A later restore of another file must not move this file's comparison.
	var origins: Dictionary = live.get("backup_restore_origins", {}) if live.get("backup_restore_origins", {}) is Dictionary else {}
	var origin: Dictionary = origins.get(source_path, {}) if origins.get(source_path, {}) is Dictionary else {}
	if not str(origin.get("path", "")).is_empty(): return str(origin.path)
	var last: Dictionary = live.get("last_restore", {}) if live.get("last_restore", {}) is Dictionary else {}
	var target := str(last.get("target", ""))
	if target.is_empty(): return ""
	var scope := str(last.get("subfolder", "")).trim_suffix("/")
	if scope.is_empty(): return target.path_join(source_path.trim_prefix("/")).simplify_path()
	if not source_path.begins_with(scope + "/"): return ""
	return target.path_join(source_path.trim_prefix(scope + "/")).simplify_path()

static func _compare_contents(d, parent: Node, s: Dictionary, snapshot: Dictionary, source: String, relative: String) -> void:
	var card := box(parent, Color("14191d"), 8);card.name="BackupContentComparison";card.add_theme_constant_override("separation",6)
	var live: Dictionary = d.game._vm().state
	var controls := HFlowContainer.new(); controls.add_theme_constant_override("h_separation", 8); card.add_child(controls)
	button(d, controls, "原本", "BackupCompareLive", func(): s["compare_target"] = "live"; rerender(d))
	var last: Dictionary = live.get("last_restore", {})
	var restore_path := _comparison_restore_path(live, source.path_join(relative))
	var restored: bool = not restore_path.is_empty() and live.get("fs", {}).has(restore_path)
	if restored: button(d, controls, "復元先", "BackupCompareRestored", func(): s["compare_target"] = "restored"; rerender(d))
	button(d,controls,"詳細を閉じる" if bool(s.get("content_details",false)) else "詳細","BackupContentDetails",func():s["content_details"]=not bool(s.get("content_details",false));rerender(d))
	var destination := source.path_join(relative)
	if restored and str(s.get("compare_target", "live")) == "restored": destination = restore_path
	var saved := str(snapshot.files[relative])
	var exists: bool = live.get("fs", {}).has(destination)
	var current := str(live.get("fs", {}).get(destination, ""))
	var projection := Visual.comparison(saved,current,exists)
	var status := "内容が一致" if exists and current == saved else "内容が異なります" if exists else "比較先にファイルがありません"
	# Byte equality is neutral. Only the independent customer checks can be green.
	_wrapped(d,controls,("＝ " if bool(projection.equal) else "Δ ")+status,"BackupComparisonStatus",12,MUTED if bool(projection.equal) else Color("efc45d"))
	var panes := BoxContainer.new();panes.name="BackupComparisonPanes";panes.add_theme_constant_override("separation",8);card.add_child(panes)
	panes.resized.connect(func():panes.vertical=panes.size.x<430.0*maxf(1.0,float(d.game.settings.get("text_scale",1.0))))
	_document_card(d,panes,projection.saved,"保存版",str(snapshot.get("repository",""))+" / "+str(snapshot.get("id","")),"BackupSavedDocument",projection.changed_keys,"BackupRestoreProvenance")
	var bridge := VBoxContainer.new();bridge.name="BackupComparisonBridge";bridge.size_flags_vertical=Control.SIZE_SHRINK_CENTER;panes.add_child(bridge)
	var direction := "→" if destination==restore_path else "↔"
	var arrow := label(d,bridge,direction,26,INK);arrow.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var action := button(d,bridge,"復元…","BackupRestoreToPath",func():s["restore_scope"]="selected";s["restore_open"]=true;s.erase("restore_plan");rerender(d))
	action.tooltip_text="この保存版から復元先へ。変更内容を先に確認します。"
	var relation := label(d,bridge,"復元先へ" if destination==restore_path else "比較のみ",10,MUTED);relation.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_document_card(d,panes,projection.current,"復元先" if destination==restore_path else "原本",destination,"BackupCurrentDocument",projection.changed_keys)
	var details := VBoxContainer.new();details.name="BackupContentDetailsBody";details.visible=bool(s.get("content_details",false));card.add_child(details)
	_wrapped(d,details,"保存元: "+source.path_join(relative)+"\n比較先: "+destination+"\n直近の復元操作: "+str(last.get("snapshot","なし")),"BackupComparisonPaths",11)
	for entry in [[saved,"BackupPreview"],[current if exists else "（ファイルなし）","BackupCurrentPreview"]]:
		var preview := TextEdit.new();preview.name=str(entry[1]);preview.editable=false;preview.text=str(entry[0]);preview.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;preview.custom_minimum_size.y=76;preview.add_theme_font_override("font",d.mono);_dark_input(preview);details.add_child(preview)
		preview.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode==KEY_TAB:
				var next := preview.find_prev_valid_focus() if event.shift_pressed else preview.find_next_valid_focus()
				if next!=null:next.grab_focus()
				preview.accept_event())

static func _document_card(d, parent: Node, projection: Dictionary, title: String, context: String, id: String, changed: Array, context_id := "") -> void:
	var column := VBoxContainer.new();column.name=id;column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",3);column.set_meta("document",projection.duplicate(true));parent.add_child(column)
	var caption := _wrapped(d,column,title+" · "+context,context_id if not context_id.is_empty() else id+"Path",11,MUTED)
	caption.custom_minimum_size.y=25
	var paper := Document.new();paper.name=id+"Paper";paper.kind=str(projection.kind);paper.custom_minimum_size=Vector2(0,96);paper.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_child(paper)
	var margin := MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);margin.add_theme_constant_override("margin_left",15);margin.add_theme_constant_override("margin_right",12);margin.add_theme_constant_override("margin_top",8);margin.add_theme_constant_override("margin_bottom",8);paper.add_child(margin)
	var rows := VBoxContainer.new();rows.add_theme_constant_override("separation",4);margin.add_child(rows)
	if str(projection.kind)=="ledger":
		for field in projection.fields:
			var row := HBoxContainer.new();row.name=id+"_"+str(field.key);rows.add_child(row)
			var differs: bool=str(field.key) in changed
			var value_color := Color("efc45d") if differs else INK
			var key := label(d,row,("Δ " if differs else "")+str(field.label),11,value_color);key.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			var value := label(d,row,str(field.value) if str(field.key)=="date" else Visual.number(str(field.value)),12 if str(field.key)=="date" else 18,value_color);value.name=id+"Value_"+str(field.key);value.size_flags_horizontal=Control.SIZE_SHRINK_END;value.clip_text=false;value.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
	elif str(projection.kind)=="damaged":
		_wrapped(d,rows,"! 読取不可",id+"Damage",18,Color("efc45d"))
		_wrapped(d,rows,"CORRUPTED DATA",id+"Literal",11,MUTED)
	elif str(projection.kind)=="missing":
		_wrapped(d,rows,"○ ファイルなし",id+"Missing",16,MUTED)
	else:
		var lines: Array=projection.get("lines",[])
		_wrapped(d,rows,"\n".join(PackedStringArray(lines.slice(0,3))) if not lines.is_empty() else "（空のファイル）",id+"Text",12,INK)
	rows.minimum_size_changed.connect(func():paper.custom_minimum_size.y=maxf(96,rows.get_combined_minimum_size().y+16))

static func _guard(d, parent: Node, title: String, state: String, id: String) -> void:
	var color := GREEN if state in ["matched","preserved"] else Color("efc45d") if state in ["mismatch","changed"] else MUTED
	var mark := "✓" if state in ["matched","preserved"] else "!" if state in ["mismatch","changed"] else "?" if state=="unknown" else "○"
	var words := {"matched":"照合一致","mismatch":"不一致","missing":"未復元","unknown":"記録なし","preserved":"保持","changed":"変更あり"}
	var chip := box(parent,Color("17211c") if state in ["matched","preserved"] else Color("242018") if state in ["mismatch","changed"] else Color("1d2327"),6);chip.name=id;chip.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL;chip.add_theme_constant_override("separation",2);chip.set_meta("state",state)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",5);chip.add_child(row)
	var glyph := Document.new();glyph.kind="guard-"+state;glyph.custom_minimum_size=Vector2(28,28);row.add_child(glyph)
	_wrapped(d,row,mark+" "+title+"\n"+str(words.get(state,state)),id+"Label",11,color)

static func _planned_live_changes(view: Dictionary, entries: Array) -> Dictionary:
	var counts := {"original":0,"unrelated":0}
	if not bool(view.get("available",false)) or not bool(view.get("enforced",false)) or bool(view.get("legacy",false)) or not str(view.get("error","")).is_empty():return counts
	for entry in entries:
		if str(entry.get("status","")) not in ["new","overwrite"]:continue
		var path := str(entry.get("path",""))
		if not path.begins_with("/srv/data/"):continue
		counts["original" if path in view.get("required_files",[]) else "unrelated"]+=1
	return counts

static func _acceptance(d, parent: Node, current_only := false) -> void:
	var vm = d.game._vm()
	if not vm.has_method("backup_acceptance_view"): return
	var status: Dictionary = vm.backup_acceptance_view()
	if not bool(status.get("available",false)): return
	if not str(status.get("error","")).is_empty():
		_wrapped(d,parent,"保全記録を確認できません（判定不可）。","BackupPreservationError",12,Color("efc45d"));return
	if not bool(status.get("enforced",false)):
		_wrapped(d,parent,"この記録には変更前の保全記録がありません。","BackupPreservationLegacy");return
	var restored: Array = status.get("restored",[])
	var observed := restored.any(func(item):return not str(item.get("current_sha256","")).is_empty())
	var restore_text := "一致" if bool(status.get("restore_valid",false)) else "不一致" if observed else "未復元"
	var text := "顧客指定の復元: %s · 原本: %s · 対象外: %s" % [restore_text,"保全" if bool(status.get("original_preserved",false)) else "変更あり","保全" if bool(status.get("unrelated_preserved",false)) else "変更あり"]
	var projection := Visual.acceptance(status)
	var strip := HBoxContainer.new();strip.name="BackupAcceptanceGuards";strip.add_theme_constant_override("separation",6);parent.add_child(strip)
	var prefix := "現在・" if current_only else ""
	_guard(d,strip,prefix+"復元",str(projection.restored),"BackupRecoveryGuard")
	_guard(d,strip,prefix+"原本",str(projection.original),"BackupOriginalGuard")
	_guard(d,strip,prefix+"対象外",str(projection.unrelated),"BackupUnrelatedGuard")
	# Preserve the full statement for accessibility and old saved-view consumers.
	var description := _wrapped(d,parent,text,"BackupAcceptanceStatus",12,GREEN if bool(status.get("accepted",false)) else Color("efc45d") if observed else MUTED)
	description.visible=bool(d.backup_ui.get("content_details",false))
	strip.tooltip_text=text

static func _restore_form(d, parent: Node, s: Dictionary, snapshot: Dictionary, repo: String, _source: String) -> void:
	var restore := box(parent, Color("17191c"));restore.name="BackupRestorePane"
	var outcome:=str(s.get("restore_result",""))
	if not outcome.is_empty():
		_wrapped(d,restore,"復元処理が完了 · 顧客指定内容の照合は別途確認" if outcome=="succeeded" else copy("preview_stale" if outcome=="preview_stale" else "restore_"+outcome),"BackupRestoreResult",13,GREEN if outcome=="succeeded" else Color("ef6b6b"))
	var close_row := HBoxContainer.new();close_row.add_theme_constant_override("separation", 8);restore.add_child(close_row)
	button(d, close_row, "戻る", "BackupCloseRestore", func():s["restore_open"] = false;rerender(d))
	_wrapped(d,close_row,"復元前の確認 · "+(str(s.get("path", "")) if str(s.get("restore_scope", "all")) == "selected" else copy("all_files", "All files")),"BackupRestoreScope")
	var inputs := HBoxContainer.new();inputs.add_theme_constant_override("separation",8);restore.add_child(inputs)
	var destination := LineEdit.new();destination.name = "BackupDestination";destination.text = str(s.get("destination", "/restore"));destination.size_flags_horizontal=Control.SIZE_EXPAND_FILL;destination.tooltip_text="復元先";_dark_input(destination);inputs.add_child(destination);destination.text_changed.connect(func(value):s["destination"] = value;s["plan_previewed"] = false;var execute_node=restore.find_child("BackupExecuteRestore",true,false);if execute_node != null:execute_node.disabled=true;persist(d))
	var overwrite := OptionButton.new();overwrite.name = "BackupOverwrite";overwrite.add_item(copy("overwrite_always", "Overwrite existing"));overwrite.add_item(copy("overwrite_never", "Skip existing"));overwrite.select(1 if str(s.get("overwrite", "always")) == "never" else 0);inputs.add_child(overwrite);_dark_input(overwrite);overwrite.item_selected.connect(func(index):s["overwrite"] = "never" if index == 1 else "always";s.erase("restore_plan");s["plan_previewed"]=false;rerender(d);_focus_after(d,"BackupOverwrite"))
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
	label(d,preview_row,"新規 %d · 上書き %d · 保持 %d" % [counts.new,counts.overwrite,counts.unchanged+counts.skipped],11,MUTED)
	var execute := button(d, preview_row, copy("execute_restore", "Restore"), "BackupExecuteRestore", func():_execute_restore(d, s, snapshot, repo, destination.text.strip_edges() if not destination.text.strip_edges().is_empty() else "/restore"));execute.disabled = entries.is_empty() or not bool(s.get("plan_previewed", false))
	var vm=d.game._vm()
	if vm.has_method("backup_acceptance_view"):
		var changes := _planned_live_changes(vm.backup_acceptance_view(),entries)
		var warnings: Array[String]=[]
		if int(changes.original)>0:warnings.append("原本を変更する予定 "+str(changes.original))
		if int(changes.unrelated)>0:warnings.append("対象外を変更する予定 "+str(changes.unrelated))
		if not warnings.is_empty():_wrapped(d,restore,"! "+" · ".join(warnings),"BackupPlannedLiveChanges",12,Color("efc45d"))
	var plan_table := VBoxContainer.new();plan_table.name = "BackupPlanEntries";plan_table.add_theme_constant_override("separation", 6);restore.add_child(plan_table);_plan_rows(d, plan_table, entries)
	_acceptance(d,restore,true)
	button(d,restore,"詳細を閉じる" if bool(s.get("plan_details",false)) else "パスとハッシュの詳細","BackupPlanDetails",func():s["plan_details"]=not bool(s.get("plan_details",false));rerender(d))
