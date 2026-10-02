extends RefCounted
## A conventional service console backed by the same guest VM as the shell.
const UI = preload("res://scripts/ui_theme.gd")
const SERVICE_ACCENT := Color("22745f")
const SERVICE_PANEL := Color("f7fbf9")

static func build(d, parent: VBoxContainer) -> void:
	var p = d._pad(parent, 0)
	p.add_theme_constant_override("separation", 0)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UI.style(UI.OS_NAV, UI.OS_BORDER, 12, 6, 0))
	p.add_child(header)
	var host_row = d._row(header, 8)
	host_row.add_child(d._icon("monitor", 19))
	var host = d._label("", 13)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.autowrap_mode = TextServer.AUTOWRAP_OFF
	host.clip_text = true
	host_row.add_child(host)
	host_row.add_child(d._tool_button("refresh", "更新", d._refresh_monitor))
	var status_badge: Label = d._label("", 12, SERVICE_ACCENT)
	host_row.add_child(status_badge)
	var split = d._row(p, 0)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rail := PanelContainer.new()
	var compact := float(d.windows.monitor.size.x) < 1100.0 * float(d.game.settings.get("text_scale", 1.0))
	rail.custom_minimum_size.x = 142 if compact else 190
	split.resized.connect(func(): rail.custom_minimum_size.x = 142 if split.size.x < 1100.0 * float(d.game.settings.get("text_scale", 1.0)) else 190)
	rail.add_theme_stylebox_override("panel", UI.style(UI.OS_NAV, Color.TRANSPARENT, 6, 14, 0))
	split.add_child(rail)
	var services = d._box(rail, 6)
	services.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var service_button = d._button("サービス", func(): d.widgets.monitor.tab="overview"; refresh(d))
	service_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	service_button.icon = UI.symbol("settings")
	service_button.expand_icon = true
	service_button.add_theme_constant_override("icon_max_width", 16)
	service_button.custom_minimum_size.y = 44
	services.add_child(service_button)
	service_button.hide()
	var service_tree := Tree.new()
	service_tree.hide_root=true; service_tree.columns=1; service_tree.select_mode=Tree.SELECT_ROW
	service_tree.set_column_titles_visible(true); service_tree.set_column_title(0,"サービス")
	service_tree.set_column_custom_minimum_width(0,80)
	service_tree.size_flags_vertical=Control.SIZE_EXPAND_FILL
	services.add_child(service_tree)
	d.widgets.monitor = {"body":null, "tab":"overview", "tabs":{}, "host":host, "badge":status_badge, "service_button":service_button, "log_search":null, "log_query":"", "log_view":null}
	d.widgets.monitor.service_tree=service_tree
	service_tree.item_selected.connect(func(): d.widgets.monitor.tab="overview"; refresh(d))
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", UI.style(Color.WHITE, Color.TRANSPARENT, 20, 18, 0))
	split.add_child(right)
	d.widgets.monitor.body = d._scroll(right)
	refresh(d)

static func _property(d, parent: Node, title: String, value: String, color: Color = UI.INK) -> void:
	var row = d._row(parent, 14)
	var label = d._label(title, 12, UI.MUTED)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	var text = d._label(value, 13, color)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	parent.add_child(HSeparator.new())

static func _logs(d, parent: Node, events: Array, limit: int = 0, ink: Color = UI.INK) -> void:
	if events.is_empty():
		parent.add_child(d._label(UI.copy("os_log_empty"), 12, UI.MUTED))
		return
	var start := maxi(0, events.size()-limit) if limit > 0 else 0
	for index in range(start, events.size()):
		var row = d._row(parent, 10)
		var number = d._label("%02d" % (index+1), 11, UI.MUTED)
		number.custom_minimum_size.x = 24
		row.add_child(number)
		var line = d._label(str(events[index]), 12, ink)
		line.add_theme_font_override("font", d.mono)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)

static func _refresh_log_view(d) -> void:
		if not d.widgets.has("monitor"): return
		var w: Dictionary = d.widgets.monitor
		var view = w.get("log_view")
		if not is_instance_valid(view): return
		d._clear(view)
		var events: Array = d.game._vm().state.events
		var query := str(w.get("log_query", "")).to_lower()
		var filtered: Array = []
		for event in events:
			if query.is_empty() or str(event).to_lower().contains(query): filtered.append(event)
		_logs(d, view, filtered, 0, Color("d8ece3"))

static func refresh(d) -> void:
	if not d.widgets.has("monitor") or not is_instance_valid(d.widgets.monitor.get("body")): return
	var w: Dictionary = d.widgets.monitor
	var box: VBoxContainer = w.body
	d._clear(box)
	var tabbar: HBoxContainer = d._row(box, 3)
	for entry in [["overview","詳細"],["config","構成"],["logs","ログ"]]:
		var tab_id: String = entry[0]
		var tab_button = d._button(entry[1], func(): d.widgets.monitor.tab=tab_id; refresh(d))
		UI.os_navigation(tab_button, tab_id == w.tab, SERVICE_ACCENT)
		tabbar.add_child(tab_button)
	var content: VBoxContainer = d._box(box, 8)
	box = content
	var info: Dictionary = d.game.vm_info()
	w.host.text = str(info.host)
	w.service_button.text = str(info.service)
	w.service_tree.set_block_signals(true); w.service_tree.clear()
	var tree_root: TreeItem = w.service_tree.create_item()
	if info.connected:
		var item: TreeItem = w.service_tree.create_item(tree_root)
		item.set_text(0,str(info.service))
		item.set_metadata(0,str(info.service)); item.select(0)
	w.service_tree.set_block_signals(false)
	if not info.connected:
		w.badge.text=UI.copy("os_disconnected")
		box.add_child(d._label(UI.copy("os_disconnected"), 22))
		var connect_button = d._button("顧客端末に接続", func(): d._run_command("ssh client"); refresh(d))
		connect_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(connect_button)
		return
	var live: Dictionary = d.game._vm().state
	w.badge.text="●  "+("稼働中" if live.active else "停止中")
	w.badge.add_theme_color_override("font_color",UI.GREEN if live.active else UI.RED)
	if w.tab == "config":
		if _console_configuration(d, box): return
		box.add_child(d._label("適用中の設定", 21))
		box.add_child(d._label(str(info.service)+".service", 12, UI.MUTED))
		box.add_child(HSeparator.new())
		if int(live.get("samba_model_version",1)) >= 2 and str(info.service) == "samba":
			for section in live.applied.get("samba",{}):
				box.add_child(d._label("["+str(section)+"]",16,SERVICE_ACCENT))
				for key in live.applied.samba[section]:
					var value: Variant = live.applied.samba[section][key]
					_property(d,box,str(key),("yes" if value else "no") if value is bool else str(value))
		else:
			for key in live.applied: _property(d, box, str(key), str(live.applied[key]))
		var edit = d._button("設定ファイルを開く", d._open_config)
		UI.os_primary(edit, SERVICE_ACCENT)
		edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(edit)
		return
	if w.tab == "logs":
		var log_toolbar: HBoxContainer = d._row(box, 6)
		log_toolbar.add_child(d._label("ログ", 18, SERVICE_ACCENT))
		var search := LineEdit.new(); search.placeholder_text="ログを検索"; search.text=str(w.get("log_query", "")); search.custom_minimum_size.x=180; search.text_changed.connect(func(value): w.log_query=value; _refresh_log_view(d)); log_toolbar.add_child(search)
		log_toolbar.add_child(d._tool_button("refresh", "再読み込み", func(): _refresh_log_view(d)))
		w.log_search=search; w.log_query=search.text
		var log_panel:=PanelContainer.new(); log_panel.add_theme_stylebox_override("panel",UI.style(Color("202e2b"),SERVICE_ACCENT,8,8,3)); box.add_child(log_panel)
		var log_box: VBoxContainer = d._box(log_panel,4); w.log_view=log_box; _refresh_log_view(d)
		return
	box.add_child(d._label(str(info.service)+".service", 24, SERVICE_ACCENT))
	var state_color := UI.GREEN if bool(live.active) else UI.RED
	w.badge.text = "●  "+("稼働中" if live.active else "停止中"); w.badge.add_theme_color_override("font_color",state_color)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	box.add_child(actions)
	var restart = d._button("再起動", func():
		d._trace("restart", str(info.service))
		var response: String = d.game.vm_run("systemctl restart "+str(info.service))
		var succeeded := response.begins_with(str(info.service) + ".service: active (running)")
		var parsed = JSON.parse_string(response) if response.begins_with("{") else null
		var reason := "保存できませんでした" if parsed is Dictionary and str(parsed.get("error", "")) == "save_failed" else response.get_slice("\n", 0)
		w["operation_feedback"] = "再起動完了" if succeeded else "再起動できませんでした · " + reason
		w["operation_ok"] = succeeded
		d._notify(str(w.operation_feedback))
		refresh(d)
		if d.widgets.has("verify"): d._refresh_checks())
	restart.name = "ServiceRestart"
	actions.add_child(restart)
	var edit_action = d._button("設定を編集", d._open_config)
	edit_action.custom_minimum_size.y = restart.custom_minimum_size.y
	actions.add_child(edit_action)
	var workspace := _workspace(d)
	if not workspace.is_empty():
		var open: Button = d._button(str(workspace.title) + "を開く", func(): d._show_app("browser"); d._browse_url(str(workspace.url), true))
		open.name = "ServiceOpenWorkspace"
		UI.os_primary(open, SERVICE_ACCENT)
		actions.add_child(open)
		actions.move_child(open, 0)
	else: UI.os_primary(restart, SERVICE_ACCENT)
	if w.has("operation_feedback"):
		var feedback: Label = d._label(str(w.operation_feedback), 13, UI.GREEN if bool(w.get("operation_ok", false)) else UI.RED)
		feedback.name = "ServiceOperationResult"; feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(feedback)
	box.add_child(d._label("稼働状態・設定の反映・ログを確認します。", 12, UI.MUTED))
	box.add_child(HSeparator.new())
	_property(d, box, UI.copy("os_config_file"), str(info.config_path), SERVICE_ACCENT)
	_property(d, box, UI.copy("os_configuration"), UI.copy("os_config_pending") if live.get("dirty",false) else UI.copy("os_config_applied"), UI.WARNING if live.get("dirty",false) else UI.INK)
	if not str(live.get("error", "")).is_empty():
		box.add_child(d._label(str(live.error), 13, UI.RED))
	box.add_child(d._label("サービスログ", 15, SERVICE_ACCENT))
	var overview_log := PanelContainer.new()
	overview_log.add_theme_stylebox_override("panel", UI.style(Color("202e2b"), SERVICE_ACCENT, 8, 8, 3))
	box.add_child(overview_log)
	_logs(d, d._box(overview_log, 4), live.events, 4, Color("d8ece3"))
	box.add_child(HSeparator.new())
	var recovery = d._disclosure(box, "変更前の記録と復元")
	var capture = d._button("変更前の記録を保存", func(): d.game.capture_baseline(); refresh(d))
	capture.disabled = not d.game.case_review().get("can_capture",false)
	recovery.add_child(capture)
	var rollback = d._button("記録した構成へ戻す", func():
		if d.game.rollback_configuration(): d.drafts.erase(str(info.config_path))
		refresh(d))
	rollback.disabled = not d.game.case_review().get("current_recorded",false)
	recovery.add_child(rollback)

static func _workspace(d) -> Dictionary:
	if d._samba_v2(): return {"url":d.SAMBA_URL, "title":"Samba"}
	if d._backup_v2(): return {"url":d.BACKUP_URL, "title":"Backrest"}
	if d._identity_v2(): return {"url":d.IDENTITY_URL, "title":"ID管理"}
	if d._edr_v2(): return {"url":d.EDR_URL, "title":"端末管理"}
	if d._portal_v2(): return {"url":d.PORTAL_URL, "title":"社外共有"}
	if d._firewall_v2(): return {"url":d.FIREWALL_URL, "title":"通信ルール"}
	return {}

static func _console_configuration(d, box: VBoxContainer) -> bool:
	var url := ""
	var title := ""
	var rows: Array = []
	if d._samba_v2():
		url=d.SAMBA_URL;title=UI.copy("samba_title")
		for name in d.game._vm().state.applied.get("shares",{}):
			rows.append([str(name),str(d.game._vm().state.applied.shares[name].get("path",""))])
	elif d._backup_v2():
		url=d.BACKUP_URL;title="Backrest"
		for snapshot in d.game._vm().state.get("snapshots",[]):
			rows.append([str(snapshot.get("id","")),str(snapshot.get("repository",""))+" · "+str(snapshot.get("files",{}).size())+" "+UI.copy("backup_files")])
	elif d._identity_v2():
		url=d.IDENTITY_URL;title=UI.copy("identity_title")
		for user in d.game._vm().identity_snapshot().get("users",[]):
			rows.append([str(user.user),UI.copy("identity_enabled" if user.enabled else "identity_disabled")])
	elif d._edr_v2():
		url=d.EDR_URL;title=UI.copy("edr_title")
		for device in d.game._vm().edr_snapshot().get("devices",[]):
			rows.append([str(device.id).to_upper().replace("_","-"),UI.copy("edr_isolated" if device.isolated else "edr_connected")])
	elif d._portal_v2():
		url=d.PORTAL_URL;title=UI.copy("portal_title")
		for file in d.game._vm().portal_snapshot().get("files",[]):
			rows.append([str(file.name),str(file.size)+" B"])
	elif d._firewall_v2():
		url=d.FIREWALL_URL;title=UI.copy("fw_rules")
		for rule in d.game._vm().firewall_snapshot().get("rules",[]):
			rows.append([str(rule.get("interface","")).to_upper()+" · "+str(rule.get("description","")),str(rule.get("action",""))])
	if url.is_empty():return false
	var open: Button=d._primary(title,func():d._show_app("browser");d._browse_url(url,true))
	open.custom_minimum_size.y=44;open.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;box.add_child(open)
	box.add_child(HSeparator.new())
	for item in rows:_property(d,box,str(item[0]),str(item[1]))
	return true
