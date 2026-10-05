extends RefCounted
const UI = preload("res://scripts/ui_theme.gd")
const CASES = preload("res://scripts/case_catalog.gd")
const CLOSEOUT = preload("res://scripts/career_closeout_panel.gd")
const MAIL_THREAD = preload("res://scripts/mail_delivery_thread.gd")
const MAIL_REQUEST = preload("res://scripts/mail_request_record.gd")
const INK := UI.INK
const MUTED := UI.MUTED
const TEAL := UI.GREEN
const BLUE := UI.PRIMARY
const ORANGE := UI.WARNING
const NEUTRAL := UI.BG
const OS_PANEL := UI.OS_PANEL
const OS_NAV := UI.OS_NAV
const OS_SELECTED := UI.OS_SELECTED
const OS_BORDER := UI.OS_BORDER
const OS_ACCENT := UI.OS_ACCENT

static func _copy(key: String, fallback: String) -> String:
	return UI.copy(key, fallback)

static func _queue_deadline(raw: String) -> String:
	var parts := raw.split(" ", false)
	if parts.size() >= 3 and parts[0] == "DAY": return _copy("queue_deadline", "%s") % [int(parts[1]), str(parts[2])]
	return raw

static func _mail_accent() -> Color:
	return Color("0f6cbd")

static func _team_accent() -> Color:
	return UI.app_accent("team")

static func _company_name(g) -> String:
	return str(g.company_name()) if g != null and g.has_method("company_name") else "AOBA"

static func _member_name(g, id: String) -> String:
	return str(g.member_name(id)) if g != null and g.has_method("member_name") else ("綾" if id == "aya" else "蓮")

static func _personalize(g, text: String) -> String:
	return str(g.personalize(text)) if g != null and g.has_method("personalize") else text

static func _mail_entry(id: String) -> Dictionary:
	return MAIL_REQUEST.entry(id)

static func _mail_for(m: Dictionary, g = null) -> Dictionary:
	if m.get("request_mail",{}) is Dictionary and not m.get("request_mail",{}).is_empty(): return m.request_mail.duplicate(true)
	if m.has("maintenance_incident_id"):
		return {"company":str(m.get("client","")),"subject":str(m.get("title","")),"body":str(m.get("brief","")),"sender":str(m.get("client",""))}
	var ids: Array[String] = []
	if g != null and g.state.get("accepted", false):
		var contract_id := str(g.state.get("contract", {}).get("case_id", ""))
		if not contract_id.is_empty(): ids.append(contract_id)
	ids.append(str(m.get("case_id", "")))
	ids.append(str(m.get("id", "")))
	ids.append(str(m.get("copy_id", "")))
	var entry: Dictionary = {}
	for id in ids:
		entry = _mail_entry(id)
		if not entry.is_empty(): break
	if entry.is_empty(): return {}
	var result := entry.duplicate(true)
	var actual_company := str(m.get("client", result.get("company", "")))
	var source_company := str(result.get("company", ""))
	if not actual_company.is_empty() and not source_company.is_empty() and actual_company != source_company:
		result.company = actual_company
		result.body = str(result.get("body", "")).replace(source_company, actual_company)
	if g != null and str(m.get("id", "")).begins_with("service-4-case-") and int(g._vm().state.get("edr_model_version", 1)) >= 2:
		result.subject = str(m.get("title", ""))
		result.body = str(m.get("brief", ""))
	return result

static func _mail_body(entry: Dictionary) -> String:
	return str(entry.get("body", "")).replace("\r\n", "\n").strip_edges()

static func _history_items(g) -> Array:
	var items: Array = []
	var records: Array = g.state.history.duplicate(true)
	var retained_ids: Dictionary = {}
	for record in records:
		if str(record.get("kind", "")) == "cancellation": retained_ids[str(record.get("id", ""))] = true
	for archive in g.state.get("contract_closeouts", {}).values():
		if archive is Dictionary and not retained_ids.has(str(archive.get("id", ""))): records.append(archive.record)
	records.sort_custom(func(a, b): return int(a.get("day", 0)) < int(b.get("day", 0)))
	for index in records.size():
		var item: Dictionary = records[index]
		if str(item.get("id", "")).begins_with("retainer-day-") or str(item.get("kind","delivery")) not in ["delivery", "cancellation"]: continue
		# Older delivery entries omit client/brief. Read their own retained
		# contract before the catalog fallback; never borrow the active client.
		var display_item := item.duplicate(true)
		var context: Dictionary = g.state.get("contract_contexts", {}).get(str(item.get("id", "")), {})
		if str(item.get("kind", "")) == "cancellation": context = g.state.get("contract_closeouts", {}).get(str(item.id), {}).get("context", {})
		var contract: Dictionary = context.get("contract", {})
		var definition: Dictionary = CASES.by_id(str(item.get("case_id", "")))
		if definition.is_empty(): definition = CASES.by_id(str(item.get("copy_id", "")))
		for key in ["client", "brief"]:
			if str(display_item.get(key, "")).is_empty():
				var value := str(contract.get(key, ""))
				display_item[key] = value if not value.is_empty() else str(definition.get(key, ""))
		items.append({"item": display_item, "index": index})
	return items

static func _mail_row(d, list: VBoxContainer, sender: String, subject: String, snippet: String, date: String, callback: Callable, selected_item := true, id := "") -> void:
	var compact: bool=not bool(d.widgets.mail.get("wide",false))
	var button: Button = d._button("", func(): d.widgets.mail["selected_subject"]=subject; d.widgets.mail.selected_id=id; callback.call()); button.custom_minimum_size.y=(62 if compact else 78)*float(d.game.settings.get("text_scale",1.0)); button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if not id.is_empty(): button.name=("MailHistory_" if d.widgets.mail.get("folder","inbox")=="history" else "MailContract_")+id.validate_node_name()
	if not bool(d.game.state.get("career_mode",false)) and d.widgets.mail.get("folder","inbox")=="inbox": button.name="GuideMailMessage"
	var selected: bool=selected_item and bool(d.widgets.mail.get("reading",false)) and str(d.widgets.mail.get("selected_subject",""))==subject
	var row_style:=UI.style(Color("cfe4fa") if selected else Color.WHITE,Color("edebe9"),10,8,0); row_style.set_border_width_all(0); row_style.border_width_bottom=1
	button.add_theme_stylebox_override("normal",row_style)
	button.add_theme_stylebox_override("hover",UI.style(Color("eff6fc"),Color.TRANSPARENT,10,8,0))
	button.tooltip_text=subject; list.add_child(button)
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,10)
	margin.add_theme_constant_override("margin_top",8); margin.add_theme_constant_override("margin_bottom",8)
	button.add_child(margin)
	var stack: VBoxContainer=d._box(margin,4); stack.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer=d._row(stack,8); row.custom_minimum_size.y=22; row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var name: Label=d._label(sender,13); name.size_flags_horizontal=Control.SIZE_EXPAND_FILL; name.autowrap_mode=TextServer.AUTOWRAP_OFF; name.clip_text=true; name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; name.mouse_filter=Control.MOUSE_FILTER_IGNORE; row.add_child(name)
	var time: Label=d._label(date,11,MUTED); time.mouse_filter=Control.MOUSE_FILTER_IGNORE; row.add_child(time)
	var lines: Array=[subject]
	if not compact:lines.append(snippet.replace("\n"," "))
	for value in lines:
		var text: Label=d._label(value,12,INK if value==subject else MUTED); text.autowrap_mode=TextServer.AUTOWRAP_OFF; text.clip_text=true; text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; text.mouse_filter=Control.MOUSE_FILTER_IGNORE; stack.add_child(text)

static func _switch_contract_from_mail(d, id: String) -> void:
	if id.is_empty(): return
	var ok := false
	if d.has_method("_switch_contract"):
		ok = bool(d._switch_contract(id))
	elif d.game.has_method("switch_contract"):
		ok = bool(d.game.switch_contract(id))
	if ok:
		# Contract switching may rebuild the desktop against a previously saved
		# target session. Reopen mail if that session did not have it running,
		# then attach the selected subject to the rebuilt widgets.
		if d.has_method("_show_app"): d._show_app("mail")
		if not d.widgets.has("mail"): return
		var selected_subject := ""
		var queue: Array = d.game.contract_queue() if d.game.has_method("contract_queue") else []
		for item in queue:
			if str(item.get("id", "")) == id:
				selected_subject = str(item.get("title", ""))
				break
		d.widgets.mail.selected_subject = selected_subject
		d.widgets.mail.selected_id = id
		d.widgets.mail.reading = not selected_subject.is_empty()
		refresh_mail(d)

static func _mail_chip(d, parent: Container, text: String) -> void:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.add_theme_stylebox_override("panel", UI.style(UI.app_tint("mail"), Color("c7d5f5"), 8, 3, 12))
	var label: Label = d._label(text, 12, _mail_accent())
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	chip.add_child(label)
	parent.add_child(chip)

static func _add_case_review(d, parent: VBoxContainer, footer: HBoxContainer, compact := false) -> void:
	var g = d.game
	if g == null or not g.has_method("case_review"): return
	var review: Dictionary = g.case_review()
	if not bool(review.get("available", false)): return
	var box = d._row(parent, 8)
	var recorded := int(review.get("recorded_sites", 0)); var total := int(review.get("total_sites", 0))
	var score := int(review.get("score", 0)); var grade := str(review.get("grade", "-"))
	var title = d._label("変更前記録", 15, TEAL); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title.autowrap_mode = TextServer.AUTOWRAP_OFF; box.add_child(title)
	box.add_child(d._label("%d / %d 拠点" % [recorded,total], 13, MUTED))
	if not compact:
		box.add_child(d._label("評価 %s  ·  %d / 3" % [grade,score],13,TEAL))
		for objective in review.get("objectives", []):
			var done := bool(objective.get("done", false)); parent.add_child(d._label(("✓  " if done else "○  ")+str(objective.get("title", "")),13,TEAL if done else MUTED))
	var actions=d._row(parent, 6)
	if bool(review.get("can_capture", false)):
		var capture = d._button("変更前記録保存 / 2分", func():
			if g.capture_baseline():
				if d.current_app == "mail": refresh_mail(d)
				elif d.current_app == "receipt": refresh_receipt(d)
		)
		capture.name = "GuideBaseline"; actions.add_child(capture)
	if bool(review.get("current_recorded",review.get("recorded",false))) and str(review.get("record_path", "")) != "":
			actions.add_child(d._button("記録を開く", d._open_editor.bind(str(review.get("record_path")))))
	elif not bool(review.get("can_capture",false)):
			actions.add_child(d._label("記録不可 · 変更済み" if g.vm_info().connected else "未接続",13,MUTED))

static func build_mail(d, parent: VBoxContainer) -> void:
	var p=d._pad(parent,0); p.size_flags_vertical=Control.SIZE_EXPAND_FILL; p.add_theme_constant_override("separation",0)
	var g=d.game
	var masthead:=PanelContainer.new(); masthead.add_theme_stylebox_override("panel",UI.style(Color("f3f3f3"),Color.TRANSPARENT,12,8,0)); p.add_child(masthead)
	var header: HBoxContainer=d._row(masthead,12)
	var folder_toggle: Button=d._tool_button("menu",UI.copy("fidelity_folder_toggle"),func(): d.widgets.mail["folders_hidden"]=not bool(d.widgets.mail.get("folders_hidden",false)); _layout_mail(d))
	folder_toggle.name="MailFolderToggle"; header.add_child(folder_toggle)
	folder_toggle.add_theme_stylebox_override("normal",UI.style(Color("eff6fc"),Color.TRANSPARENT,5,3,3))
	var brand: Label=d._label("Outwatch",18,_mail_accent()); brand.name="MailBrand"; brand.custom_minimum_size.x=106; header.add_child(brand)
	var search:=LineEdit.new(); search.name="MailSearch"; search.placeholder_text=UI.copy("fidelity_mail_search"); search.right_icon=UI.symbol("search"); search.clear_button_enabled=true; search.size_flags_horizontal=Control.SIZE_EXPAND_FILL; search.custom_minimum_size.y=32
	search.add_theme_stylebox_override("normal",UI.style(Color("eff6fc"),Color.TRANSPARENT,12,5,4)); search.add_theme_stylebox_override("focus",UI.style(Color.WHITE,Color("c7e0f4"),12,5,4))
	search.text_changed.connect(func(_value): d.widgets.mail.reading=false; refresh_mail(d)); header.add_child(search); d.widgets.mail.search=search
	var folder_picker:=OptionButton.new(); folder_picker.add_item(UI.copy("fidelity_inbox")); folder_picker.add_item("受注履歴"); folder_picker.visible=false
	folder_picker.item_selected.connect(func(i): d.widgets.mail.folder="inbox" if i==0 else "history"; d.widgets.mail.reading=false; refresh_mail(d)); header.add_child(folder_picker); d.widgets.mail.folder_picker=folder_picker
	var command_frame:=PanelContainer.new(); command_frame.add_theme_stylebox_override("panel",UI.style(Color("fafafa"),Color("edebe9"),12,3,0)); p.add_child(command_frame)
	var commands: HBoxContainer=d._row(command_frame,12)
	commands.add_child(d._tool_button("refresh",UI.copy("fidelity_reload"),func():refresh_mail(d)))
	var view_menu:=MenuButton.new(); view_menu.text=UI.copy("fidelity_mail_view"); view_menu.tooltip_text=UI.copy("fidelity_reading_pane"); commands.add_child(view_menu)
	view_menu.get_popup().add_radio_check_item(UI.copy("fidelity_reading_right"),0); view_menu.get_popup().add_radio_check_item(UI.copy("fidelity_reading_single"),1)
	view_menu.get_popup().about_to_popup.connect(func():
		view_menu.get_popup().set_item_checked(0,not bool(d.widgets.mail.get("single_pane",false))); view_menu.get_popup().set_item_checked(1,bool(d.widgets.mail.get("single_pane",false))))
	view_menu.get_popup().id_pressed.connect(func(id):d.widgets.mail["single_pane"]=id==1; _layout_mail(d); refresh_mail(d))
	var columns: HBoxContainer=d._row(p,0); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var nav_frame:=PanelContainer.new(); nav_frame.name="MailFolderPane"; nav_frame.add_theme_stylebox_override("panel",UI.style(Color("f3f2f1"),Color.TRANSPARENT,10,18,0)); columns.add_child(nav_frame)
	var nav: VBoxContainer=d._box(nav_frame,4); nav.custom_minimum_size.x=158; nav.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	nav.add_child(d._label(d._player_display_name(),13,INK)); nav.add_child(d._label(UI.copy("fidelity_folders"),12,MUTED)); nav.add_child(HSeparator.new())
	var inbox: Button=d._button("受信トレイ",func(): d.widgets.mail.folder="inbox"; d.widgets.mail.reading=false; refresh_mail(d)); inbox.icon=UI.symbol("inbox"); inbox.add_theme_constant_override("icon_max_width",18); inbox.alignment=HORIZONTAL_ALIGNMENT_LEFT; nav.add_child(inbox)
	var done: Button=d._button("受注履歴 %d" % _history_items(g).size(),func(): d.widgets.mail.folder="history"; d.widgets.mail.reading=false; refresh_mail(d)); done.icon=UI.symbol("archive"); done.add_theme_constant_override("icon_max_width",18); done.alignment=HORIZONTAL_ALIGNMENT_LEFT; nav.add_child(done)
	d.widgets.mail.nav=nav; d.widgets.mail.nav_frame=nav_frame; d.widgets.mail.inbox_nav=inbox; d.widgets.mail.done_nav=done
	var list_panel:=PanelContainer.new(); list_panel.name="MailMessageList"; list_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; list_panel.add_theme_stylebox_override("panel",UI.style(Color.WHITE,Color("edebe9"),0,0,0)); columns.add_child(list_panel)
	var list: VBoxContainer=d._scroll(list_panel); list.add_theme_constant_override("separation",1); d.widgets.mail.list=list; d.widgets.mail.list_panel=list_panel
	var paper:=PanelContainer.new(); paper.name="MailReadingPane"; paper.size_flags_horizontal=Control.SIZE_EXPAND_FILL; paper.add_theme_stylebox_override("panel",UI.style(Color.WHITE,Color.TRANSPARENT,24,20,0)); columns.add_child(paper)
	d.widgets.mail.paper=paper; d.widgets.mail.body=d._scroll(paper); d.widgets.mail.body.add_theme_constant_override("separation",14)
	var footer_frame:=PanelContainer.new(); footer_frame.add_theme_stylebox_override("panel",UI.style(Color("f3f2f1"),Color("edebe9"),12,4,0)); p.add_child(footer_frame)
	d.widgets.mail.footer=d._row(footer_frame,8); d.widgets.mail.footer_frame=footer_frame
	var saved_mail: Dictionary = d.mail_ui.duplicate(true) if d.mail_ui is Dictionary else {}
	d.widgets.mail.folder = "history" if str(saved_mail.get("folder", "inbox")) == "history" else "inbox"
	d.widgets.mail.reading = bool(saved_mail.get("reading", false))
	d.widgets.mail.selected_subject = str(saved_mail.get("selected_subject", ""))
	d.widgets.mail.selected_id = str(saved_mail.get("selected_id", ""))
	d.widgets.mail.history_index = int(saved_mail.get("history_index", 0))
	d.widgets.mail.single_pane = bool(saved_mail.get("single_pane", false))
	d.widgets.mail.folders_hidden = bool(saved_mail.get("folders_hidden", false))
	search.set_block_signals(true)
	search.text = str(saved_mail.get("query", ""))
	search.set_block_signals(false)
	d.mail_folder = d.widgets.mail.folder
	d.windows.mail.resized.connect(_layout_mail.bind(d)); _layout_mail(d)

static func _layout_mail(d) -> void:
	var w: Dictionary=d.widgets.mail
	var available: float=d.windows.mail.size.x
	var text_scale: float=float(d.game.settings.get("text_scale",1.0))
	var wide: bool=available>=760.0*text_scale and not bool(w.get("single_pane",false))
	w.wide=wide
	w.nav_frame.visible=available>=1060.0*text_scale and not bool(w.get("folders_hidden",false))
	w.folder_picker.visible=not w.nav_frame.visible
	w.list_panel.custom_minimum_size.x=340.0*text_scale if wide else 0
	w.list_panel.size_flags_horizontal=Control.SIZE_FILL if wide else Control.SIZE_EXPAND_FILL
	w.body.custom_minimum_size.x=0
	w.paper.visible=wide or bool(w.get("reading",false))
	w.list_panel.visible=wide or not bool(w.get("reading",false))
	w.list.visible=true
	for content_name in ["MailReadingContent", "MailHistoryContent", "MailEmptyContent"]:
		var content: Control=w.body.find_child(content_name,true,false) as Control
		if is_instance_valid(content): content.custom_maximum_size.x=_mail_reading_width(d,w,d.game)

static func _mail_reading_width(d, w: Dictionary, g) -> float:
	var scale:=float(g.settings.get("text_scale",1.0))
	var reserved:=64.0
	if is_instance_valid(w.get("nav_frame",null)) and w.nav_frame.visible: reserved+=198.0
	if bool(w.get("wide",false)): reserved+=340.0*scale
	return maxf(320.0,minf(960.0*scale,float(d.windows.mail.size.x)-reserved))

static func refresh_mail(d) -> void:
	var w: Dictionary = d.widgets.mail; var body: VBoxContainer = w.body; var footer: HBoxContainer = w.footer; var list: VBoxContainer = w.list
	w.erase("progress"); w.erase("report")
	d._clear(body); d._clear(footer); d._clear(list)
	_layout_mail(d)
	var list_toolbar: HBoxContainer=d._row(list,8); list_toolbar.custom_minimum_size.y=40; list_toolbar.add_child(d._label("   "+(UI.copy("fidelity_inbox") if w.get("folder","inbox")=="inbox" else "受注履歴"),14,INK))
	var g = d.game; var m: Dictionary = g.mission(); var mail: Dictionary = _mail_for(m, g); var mail_body := _mail_body(mail) if not mail.is_empty() else str(m.get("brief", "")); var reading: bool = bool(w.get("reading",true)); var query := str(w.search.text).strip_edges().to_lower() if is_instance_valid(w.get("search",null)) else ""
	var wide: bool = bool(w.get("wide", false))
	if is_instance_valid(w.get("paper",null)): w.paper.visible = wide or reading
	list.visible = wide or not reading
	if is_instance_valid(w.get("list_panel",null)): w.list_panel.visible=wide or not reading
	if is_instance_valid(w.get("folder_picker",null)): w.folder_picker.select(0 if w.get("folder","inbox") == "inbox" else 1)
	if is_instance_valid(w.get("inbox_nav",null)): UI.os_navigation(w.inbox_nav,w.get("folder","inbox") == "inbox",_mail_accent())
	if is_instance_valid(w.get("done_nav",null)):
		w.done_nav.text = "受注履歴 %d" % _history_items(g).size()
		UI.os_navigation(w.done_nav,w.get("folder","inbox") == "history",_mail_accent())
	var queue: Array = g.contract_queue() if g.has_method("contract_queue") else []
	if reading:
		var selected_subject: String = str(w.get("selected_subject", ""))
		var selection_valid := false
		if w.get("folder", "inbox") == "history":
			var history_entries_for_selection: Array = _history_items(g)
			var remembered_index := int(w.get("history_index", -1))
			var matching_index := -1
			for history_position in history_entries_for_selection.size():
				var history_entry: Dictionary = history_entries_for_selection[history_position]
				var history_item: Dictionary = history_entry.item
				var history_mail: Dictionary = _mail_for(history_item)
				if str(w.get("selected_id","")) == str(history_item.get("id","")) and not str(w.get("selected_id","" )).is_empty():
					matching_index=history_position; break
				if str(w.get("selected_id","" )).is_empty() and selected_subject == str(history_mail.get("subject", history_item.get("title", ""))):
					if matching_index < 0: matching_index = history_position
					if history_position == remembered_index:
						matching_index = history_position
						break
			if matching_index >= 0:
				selection_valid = true
				w.history_index = matching_index
				w.selected_id = str(history_entries_for_selection[matching_index].item.get("id",""))
		else:
			for queue_item in queue:
				var queue_subject: String = str(queue_item.get("title", ""))
				if selected_subject == queue_subject: selection_valid = true
			if queue.is_empty() and selected_subject == str(mail.get("subject", m.title)): selection_valid = true
		if not selection_valid:
			w.reading = false
			w.selected_subject = ""
			w.selected_id = ""
			reading = false
			if is_instance_valid(w.get("paper", null)): w.paper.visible = wide
			list.visible = true
			if is_instance_valid(w.get("list_panel", null)): w.list_panel.visible = true
	if w.get("folder","inbox") == "inbox" and g.state.get("awaiting_contract",false) and queue.is_empty():
		w.reading = false
		w.paper.hide(); w.list_panel.show(); list.show()
		list.add_child(d._label("未受注",20,INK))
		footer.add_child(d._primary("案件一覧表示",d._contracts))
		return
	if w.get("folder","inbox") == "inbox":
		for item in queue:
			var queue_id := str(item.get("id", "")); var queue_client := str(item.get("client", "")); var queue_title := str(item.get("title", "")); var queue_status := _copy("queue_done" if bool(item.get("completed", false)) else "queue_current" if bool(item.get("active", false)) else "queue_open", "")
			var queue_deadline := _queue_deadline(str(item.get("deadline_text", "")))
			var queue_subject := queue_title
			var queue_snippet := "%s  ·  %s" % [queue_status, queue_deadline]
			var queue_context: Dictionary = g.state.get("contract_contexts", {}).get(queue_id, {})
			var queue_contract: Dictionary = queue_context.get("contract", {})
			var queue_mail := _mail_for(queue_contract)
			var saved_reply: Dictionary=MAIL_THREAD.project(g.state,MAIL_THREAD.delivery_for(g.state,queue_id))
			if bool(saved_reply.completed): queue_snippet=str(saved_reply.body).replace("\n"," "); queue_status="返信 · "+queue_status
			var queue_haystack := (queue_client + " " + queue_subject + " " + queue_snippet + " " + str(queue_mail.get("sender", "")) + " " + _mail_body(queue_mail) + " " + str(queue_contract.get("brief", ""))).to_lower()
			if query.is_empty() or queue_haystack.contains(query):
				_mail_row(d, list, queue_client, queue_subject, queue_snippet, queue_status, _switch_contract_from_mail.bind(d, queue_id), bool(item.get("active", false)),queue_id)
		var haystack := (str(mail.get("company",m.client))+" "+str(mail.get("sender",""))+" "+str(mail.get("subject",m.title))+" "+mail_body).to_lower()
		if queue.is_empty() and (query.is_empty() or haystack.contains(query)):
			_mail_row(d,list,str(mail.get("company",m.client)),str(mail.get("subject",m.title)),mail_body,"納品済み" if g.current_done() else "対応中" if g.state.accepted else "新着",func(): w.reading=true; refresh_mail(d))
	if w.get("folder","inbox") == "history":
		var history_items_for_list := _history_items(g)
		for filtered_index in history_items_for_list.size():
			var item: Dictionary = history_items_for_list[filtered_index].item; var history_mail := _mail_for(item); var history_body := _mail_body(history_mail)
			var outcome := "中止・未完了" if str(item.get("kind", "")) == "cancellation" else "納品済み"
			var saved_reply := MAIL_THREAD.project(g.state,item)
			var snippet: String=str(saved_reply.body) if bool(saved_reply.completed) else outcome+" · "+history_body
			var history_text := str(history_mail.get("company",item.get("client",""))+" "+str(history_mail.get("sender",""))+" "+str(history_mail.get("subject",item.get("title","完了した依頼")))+" "+history_body+" "+snippet)
			if not query.is_empty() and not history_text.to_lower().contains(query): continue
			_mail_row(d,list,str(history_mail.get("company",item.get("client",""))),str(history_mail.get("subject",item.get("title",""))),snippet,outcome + " · DAY %02d" % int(item.get("day",0)),func(): w.history_index=filtered_index; w.reading=true; refresh_mail(d), filtered_index == int(w.get("history_index", -1)),str(item.get("id","")))
	if not reading:
		if list.get_child_count() == 1:
			var empty: VBoxContainer=d._box(list,12); empty.name = "MailNoResults"; empty.add_child(d._icon("mail",80)); empty.add_child(d._label("メールなし" if query.is_empty() else "該当メールなし",14,MUTED))
		if wide:
			var empty: VBoxContainer=d._box(body,16); empty.custom_minimum_size.y=220
			var mark: TextureRect=d._icon("mail",72); mark.size_flags_horizontal=Control.SIZE_SHRINK_CENTER; empty.add_child(mark)
			var hint: Label=d._label(UI.copy("fidelity_mail_select"),16,MUTED); hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; empty.add_child(hint)
		return
	var navigation: HBoxContainer=d._row(body,8)
	var back: Button=d._tool_button("back","一覧へ戻る",func(): w.reading=false; refresh_mail(d)); back.name="MailBack"; navigation.add_child(back); navigation.add_child(d._label("受信トレイ" if w.get("folder","inbox")=="inbox" else "受注履歴",11,MUTED))
	if w.get("folder","inbox") == "history":
		
		var history_items := _history_items(g)
		if history_items.is_empty(): body.add_child(d._label("履歴なし",14,MUTED))
		if not history_items.is_empty():
			var index := clampi(int(w.get("history_index", history_items.size()-1)), 0, history_items.size()-1); w.history_index = index
			var item: Dictionary = history_items[index].item; var history_mail := _mail_for(item); var history_body := _mail_body(history_mail)
			var history_content: VBoxContainer=d._box(body,14); history_content.name="MailHistoryContent"; history_content.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; history_content.custom_maximum_size.x=_mail_reading_width(d,w,g)
			if str(item.get("kind","delivery")) == "delivery":
				history_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				MAIL_THREAD.build(d,history_content,history_mail,item,footer)
				history_content.add_child(d._button("受信トレイへ",func(): w.folder="inbox"; w.reading=false; refresh_mail(d))); return
			history_content.add_child(d._label(str(history_mail.get("subject",item.get("title","完了した依頼"))),20,INK))
			history_content.add_child(d._label("%s  <%s>  ·  DAY %02d" % [str(history_mail.get("sender",item.get("client",m.client))),str(history_mail.get("company",item.get("client",m.client))),int(item.get("day",0))],15,BLUE))
			history_content.add_child(HSeparator.new())
			if str(item.get("kind", "")) == "cancellation":
				var result: Label = d._label("中止・未完了  ·  経費 ¥%s  ·  請求 ¥0" % d._money(item.get("costs", 0)), 15, ORANGE); result.name = "MailCancellationResult"; history_content.add_child(result)
				history_content.add_child(d._label("顧客満足度 %d → %d  ·  信用 %d → %d" % [int(item.satisfaction_before), int(item.satisfaction_after), int(item.credit_before), int(item.credit_after)], 14, MUTED))
				CLOSEOUT.add_archive(d, history_content, item)
			else:
				history_content.add_child(d._label("納品済み  ·  利益 ¥%s  ·  評価 %s" % [d._money(item.get("profit",item.get("net",0))),str(item.get("grade","-"))],15,TEAL))
			history_content.add_child(d._label(history_body if not history_body.is_empty() else str(item.get("brief","")),15,INK))
			history_content.add_child(d._button("受信トレイへ",func(): w.folder="inbox"; w.reading=false; refresh_mail(d)))
		return
	if g.state.get("awaiting_contract",false):
		var empty_content: VBoxContainer=d._box(body,14); empty_content.name="MailEmptyContent"; empty_content.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; empty_content.custom_maximum_size.x=_mail_reading_width(d,w,g)
		empty_content.add_child(d._label("未受注",24)); empty_content.add_child(d._primary("契約一覧",d._contracts)); return
	var reading_content: VBoxContainer=d._box(body,8); reading_content.name="MailReadingContent"
	reading_content.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	reading_content.custom_maximum_size.x=_mail_reading_width(d,w,g)
	if g.current_done():
		var id: String = str(g.state.current_contract_id) if bool(g.state.get("career_mode",false)) else str(m.get("id",""))
		reading_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		MAIL_THREAD.build(d,reading_content,mail,MAIL_THREAD.delivery_for(g.state,id),footer)
		footer.add_child(d._label("✓ 納品済み",15,TEAL)); return
	reading_content.add_child(d._label(str(mail.get("subject",m.title)),20,INK))
	var sender_row = d._row(reading_content,12)
	var avatar := PanelContainer.new(); avatar.custom_minimum_size=Vector2(34,34); avatar.add_theme_stylebox_override("panel",UI.style(Color("b7d7d3"),Color.TRANSPARENT,8,4,20)); sender_row.add_child(avatar)
	var initial = d._label(str(m.client).left(1),16,UI.INK); initial.autowrap_mode=TextServer.AUTOWRAP_OFF; initial.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; initial.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; avatar.add_child(initial)
	var destination = d._label("%s  ·  %s" % [str(mail.get("company",m.client)),str(mail.get("sender","担当者"))],13,INK); destination.size_flags_horizontal=Control.SIZE_EXPAND_FILL; destination.autowrap_mode=TextServer.AUTOWRAP_OFF; destination.clip_text=true; sender_row.add_child(destination); w.destination=destination
	sender_row.add_child(d._label("DAY %02d" % int(g.state.day),13,MUTED))
	var actions:=HFlowContainer.new(); actions.name="MailMessageActions"; actions.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_theme_constant_override("h_separation",8); actions.add_theme_constant_override("v_separation",6); reading_content.add_child(actions)
	var message: Label=d._label(mail_body,14,INK); message.name="MailMessageBody"; message.add_theme_constant_override("line_spacing",6); reading_content.add_child(message)
	var headers: VBoxContainer = d._disclosure(reading_content, _copy("os_mail_headers", "メッセージヘッダー"))
	headers.add_child(d._label("送信者  /  %s" % str(mail.get("sender", "担当者")), 13, MUTED))
	var recipient: Label = d._label(UI.copy("mail_recipient") % (_company_name(g)+" / "+g.player_name()),12,MUTED)
	headers.add_child(recipient); w.recipient_details = recipient; w.recipient = recipient
	headers.add_child(d._label("案件  /  %s" % str(mail.get("case_id", m.get("case_id", ""))), 13, MUTED))
	var attachment: VBoxContainer = d._disclosure(reading_content,_copy("os_attachments", "添付ファイル")+" · "+_copy("os_details", "詳細"))
	var chips := HFlowContainer.new(); chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL; chips.add_theme_constant_override("h_separation",6); attachment.add_child(chips)
	_mail_chip(d, chips, str(m.service))
	var attached_file: Button = d._button(str(m.asset).get_file(), d._open_config)
	attached_file.icon=UI.symbol("file"); attached_file.expand_icon=true; attached_file.add_theme_constant_override("icon_max_width",18)
	attached_file.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	attached_file.tooltip_text=str(m.asset); attached_file.disabled=not g.vm_info().connected
	chips.add_child(attached_file)
	attachment.add_child(d._label("達成条件",15,INK))
	for condition in m.checks: attachment.add_child(d._label("・"+str(condition),14,INK))
	if g.state.accepted and not g.current_done():
		var review_data: Dictionary = g.case_review() if g.has_method("case_review") else {}
		if bool(review_data.get("available",false)):
			var optional: VBoxContainer = d._disclosure(attachment,"変更前の記録"); _add_case_review(d,optional,footer,true)
	attachment.add_child(d._button("接続情報・リファレンス表示",d._show_app.bind("manual")))
	if g.current_done():
		footer.add_child(d._label("✓ 納品済み",15,TEAL)); actions.add_child(d._primary("精算明細",d._show_app.bind("receipt"))); return
	var work: Dictionary = g.work_status()
	if not g.state.accepted:
		reading_content.add_child(d._label("契約条件", 12, MUTED))
		var plan := OptionButton.new(); plan.name="MailContractPlan"; var plans: Array = g.contract_plans()
		for item in plans: plan.add_item(item.label)
		var selected_plan := str(g.offer_plan()) if bool(g.state.career_mode) else str(g.state.contract_plan)
		for i in plans.size():
			if plans[i].id==selected_plan: plan.select(i)
		var care_note: Label = d._label("", 12, MUTED); care_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; care_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var refresh_care_note := func(selected_index: int) -> void:
			var selected_id := str(plans[selected_index].id) if selected_index >= 0 and selected_index < plans.size() else "standard"
			if selected_id != "care":
				care_note.text = ""; care_note.hide()
				return
			var terms: Dictionary = g.care_terms(str(m.client))
			var reason: String = str(terms.reason)
			care_note.show()
			var rates_template := UI.copy("care_contract_rates", ""); var billing := UI.copy("care_billing", "")
			care_note.text = ((rates_template % [int(terms.fee),int(terms.cost),int(terms.net)]) + ("\n" + billing if not billing.is_empty() else "")) if reason.is_empty() and not rates_template.is_empty() else reason
			care_note.add_theme_color_override("font_color", ORANGE if not reason.is_empty() else TEAL)
		plan.item_selected.connect(func(i):
			if bool(g.state.career_mode): g.set_offer_plan(str(plans[i].id))
			else: g.set_contract_plan(plans[i].id)
			refresh_care_note.call(i); refresh_mail(d))
		actions.add_child(plan)
		var estimate = d._box(actions, 1); estimate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		estimate.add_child(d._label("報酬 ¥%s   /   納期 %d 分\n経費 ¥%s" % [d._money(work.estimated_fee),work.budget,d._money(work.costs)],12,MUTED))
		estimate.add_child(care_note)
		refresh_care_note.call(plan.selected)
		var accept = d._primary("引き受ける",d._accept); accept.name="GuideMailAccept"; accept.icon=UI.symbol("reply"); accept.add_theme_constant_override("icon_max_width",18); accept.disabled = str(g.state.strategy).is_empty() or (selected_plan == "care" and g.has_method("care_eligibility") and not g.care_eligibility(str(m.client)).is_empty()); actions.add_child(accept)
		if str(g.state.strategy).is_empty(): actions.add_child(d._button("会社方針決定",d._company))
	else:
		_add_care_conversion(d, reading_content, "Mail")
		var info: Dictionary = g.vm_info()
		var phase := "未接続" if not info.connected else ("完了" if g.current_done() else "接続中")
		var progress = d._label(phase,13,TEAL); progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(progress)
		actions.add_child(d._button("ターミナル",d._show_app.bind("terminal"))); var report = d._button("納品",d._show_app.bind("receipt")); actions.add_child(report)
		w.progress = progress; w.report = report

static func refresh_mail_status(d) -> void:
	var w: Dictionary = d.widgets.mail
	var g = d.game
	var recipient_text := UI.copy("mail_recipient") % (_company_name(g)+" / "+g.player_name())
	if is_instance_valid(w.get("recipient_details",null)): w.recipient_details.text = recipient_text
	if is_instance_valid(w.get("recipient",null)): w.recipient.text = recipient_text
	if not w.has("progress") or not is_instance_valid(w.progress): return
	var info: Dictionary = g.vm_info(); var work: Dictionary = g.work_status()
	var ready: bool = g.can_deliver()
	var phase := "未接続" if not info.connected else ("完了" if g.current_done() else "接続中")
	w.progress.text = phase+"   /   "+str(work.time_text)
	if w.has("report") and is_instance_valid(w.report): w.report.disabled = not ready

static func build_team(d, parent: VBoxContainer) -> void:
	var p = d._pad(parent); var row = d._row(p)
	var title = d._label("チーム",24,_team_accent()); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title.autowrap_mode = TextServer.AUTOWRAP_OFF; row.add_child(title)
	var queue = d._button("業務一覧・時間配分", d._contracts); queue.name = "TeamOperations"; row.add_child(queue)
	row.add_child(d._button(UI.copy("staffing_title"),d._staffing))
	var refresh = d._button("更新",func(): refresh_team(d)); refresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; row.add_child(refresh)
	var context = d._label("", 14, MUTED); context.name = "TeamWorkContext"; context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; p.add_child(context)
	d.widgets.team.context = context
	d.widgets.team.body = d._scroll(p); d.widgets.team.cards = []; d.widgets.team.cards_built = false
static func refresh_team(d) -> void:
	var w: Dictionary = d.widgets.team; var body: VBoxContainer = w.body; var g = d.game
	if w.get("context") is Label:
		w.context.text = "現在の案件: %s / %s\nここでは現在の対象への調査を依頼します。複数案件の順番と工数は業務一覧で調整します。" % [str(g.mission().get("client", "")), str(g.mission().get("title", ""))] if bool(g.state.get("accepted", false)) and not g.current_done() else "作業中の案件がありません。業務一覧から受注済み案件を開くと、担当者へ調査を依頼できます。"
	var members: Array = g.team_members()
	var signature := JSON.stringify(members)
	if not bool(w.get("cards_built", false)) or str(w.get("member_signature", "")) != signature:
		d._clear(body); w.cards = []; w.member_signature = signature
		for member in members:
			var member_id := str(member.id); var role := str(member.role)
			var panel := PanelContainer.new(); panel.custom_minimum_size.y=104; panel.add_theme_stylebox_override("panel",d._style(UI.app_tint("team"),_team_accent(),8,10)); body.add_child(panel)
			var stack: VBoxContainer = d._box(panel,8)
			var top: HBoxContainer = d._row(stack,10)
			var identity: VBoxContainer = d._box(top,3); identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			var name_label = d._label(str(member.name),20,INK); name_label.autowrap_mode=TextServer.AUTOWRAP_OFF; name_label.clip_text=true; identity.add_child(name_label)
			identity.add_child(d._label(UI.copy("staffing_role_"+role),13,MUTED))
			var status = d._label("待機中",14,_team_accent()); status.autowrap_mode=TextServer.AUTOWRAP_OFF; top.add_child(status)
			var description_label = d._label("",14,MUTED); description_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; stack.add_child(description_label)
			var progress := ProgressBar.new(); progress.min_value=0; progress.max_value=1; progress.show_percentage=false; progress.custom_minimum_size.y=12; progress.visible=false; stack.add_child(progress)
			var phase = d._label("",14,MUTED); stack.add_child(phase)
			var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation",8); actions.add_theme_constant_override("v_separation",6); stack.add_child(actions)
			var assign = d._button(UI.copy("care_title") if role=="maintenance" else "作業を依頼",func():
				if role=="maintenance": d._company()
				else: g.assign_colleague(member_id); refresh_team(d))
			assign.name="Assign_"+member_id; actions.add_child(assign)
			var result_path := str(g.colleague_result_path(member_id))
			var result_callback: Callable = d._open_colleague_result.bind(member_id,result_path) if d.has_method("_open_colleague_result") else d._open_editor.bind(result_path)
			var result = d._button("成果ファイル表示",result_callback); result.name="Result_"+member_id; actions.add_child(result)
			var care_result = d._button(UI.copy("care_result"),_show_maintenance_result.bind(d,member_id)); care_result.visible=false; actions.add_child(care_result)
			w.cards.append({"id":member_id,"role":role,"hired":bool(member.hired),"member":member,"name":name_label,"description":description_label,"status":status,"progress":progress,"phase":phase,"assign":assign,"result":result,"care_result":care_result})
		w.cards_built=true
	for card in w.cards:
		var member_id := str(card.id); var role := str(card.role)
		var duration: float = g.team_work_duration(member_id)
		card.description.text = UI.copy("staffing_daily_cost") % int(card.member.daily_wage) if bool(card.hired) else (("ログ・接続の調査" if role=="aya" else "復元・証拠保全")+"  ·  ¥100 / %s分" % str(duration))
		var job: Dictionary = g.state.assignments.get(member_id,{})
		var state: String = str(job.get("status","idle")); var maintenance := str(job.get("kind",""))=="maintenance"
		var state_text: String = {"idle":"待機中","working":"作業中…","done":"✓ 完了","cancelled":"要再依頼"}.get(state,state)
		if maintenance: state_text=UI.copy("care_status_"+state)
		var unavailable := str(g.staff_availability(member_id,"maintenance" if role=="maintenance" else "normal"))
		if state=="idle" and not unavailable.is_empty(): state_text=unavailable
		card.status.text=state_text; card.status.modulate=TEAL if state=="done" else ORANGE if state=="cancelled" else _team_accent()
		card.progress.visible=state=="working"; card.phase.visible=state in ["working","done","failed","cancelled"]
		if state=="working":
			card.progress.max_value=float(job.get("total",job.get("remaining",1.0))); card.progress.value=card.progress.max_value-float(job.get("remaining",0.0)); card.phase.text="%s　完了まで %.0f秒" % [job.get("phase","作業中"),float(job.get("remaining",0.0))]
		elif state in ["done","failed"]: card.phase.text=str(job.get("phase","作業終了"))
		else: card.phase.text=""
		card.assign.disabled=not unavailable.is_empty() or (role!="maintenance" and (not g.state.accepted or g.current_done()))
		var assign_reason := unavailable
		if role != "maintenance" and (not g.state.accepted or g.current_done()): assign_reason = "業務一覧から作業中の案件を開いてください。"
		card.assign.tooltip_text=assign_reason
		if card.assign.disabled and state != "working" and not assign_reason.is_empty():
			card.phase.text = assign_reason
			card.phase.visible = true
		card.result.visible=not maintenance and role!="maintenance"; card.result.disabled=state!="done"
		card.care_result.visible=maintenance; card.care_result.disabled=state not in ["done","failed"]
		if maintenance: card.description.text=UI.copy("care_client_status") % str(job.get("client",""))
		elif job.has("contract_id"):
			for item in g.contract_queue():
				if str(item.get("id",""))==str(job.get("contract_id","")):
					card.description.text=str(item.get("client",""))+" / "+str(item.get("title",""))
					break

static func _show_maintenance_result(d, member_id: String) -> void:
	var g = d.game
	var job: Dictionary = g.state.assignments.get(member_id,{})
	var client := str(job.get("client", ""))
	if client.is_empty() or not g.has_method("maintenance_result"): return
	d._show_app("terminal")
	var title_template := UI.copy("care_result_title", ""); var title := title_template % client if not title_template.is_empty() else client
	var result := str(g.maintenance_result(client)); d._append(title + "\n" + (result if not result.is_empty() else UI.copy("care_result_empty", "")))

static func build_receipt(d, parent: VBoxContainer) -> void:
	var p = d._pad(parent,22); d.widgets.receipt.body = d._scroll(p); d.widgets.receipt.footer = d._row(p)

static func delivery_measurement_counts(probes: Array) -> Dictionary:
	var counts := {"unrecorded":0, "stale":0, "failed":0, "passed":0}
	for probe in probes:
		var status := "unrecorded" if not bool(probe.get("recorded", false)) else "stale" if not bool(probe.get("fresh", false)) else "passed" if bool(probe.get("passed", false)) else "failed"
		counts[status] += 1
	return counts

static func _measurement_summary(counts: Dictionary) -> String:
	var parts: Array[String] = []
	for item in [["unrecorded", "未確認"], ["stale", "過去の結果"], ["failed", "不合格"], ["passed", "合格"]]:
		if int(counts[item[0]]) > 0: parts.append("%s %d件" % [item[1], int(counts[item[0]])])
	return " / ".join(parts)

static func delivery_blockers(g) -> Array:
	var s: Dictionary = g.state
	var out: Array = []
	if g.current_done() or g.can_deliver(): return out
	if not bool(s.get("accepted", false)):
		return [{"id":"accept", "message":UI.copy("delivery_blocked_accept"), "action":UI.copy("delivery_open_mail"), "route":"mail", "target_index":-1}]
	if g.has_method("care_conversion_offer") and bool(g.care_conversion_offer().get("available", false)):
		return [{"id":"care-conversion", "message":"この専門案件は継続保守の対象外です。料金・納期を維持した単発契約への変更を確認してください。", "action":"契約変更を確認", "route":"receipt", "target_index":-1}]
	var contract_id := str(s.get("current_contract_id", ""))
	var queued := false
	for queue in s.get("dispatch_queues", {}).values():
		for job in queue:
			if str(job.get("kind", "normal")) == "normal" and str(job.get("contract_id", "")) == contract_id: queued = true
	if queued: out.append({"id":"queue", "message":UI.copy("delivery_blocked_queue"), "action":UI.copy("delivery_open_queue"), "route":"board", "target_index":-1})
	for job in g._assignments.values():
		if str(job.get("kind", "normal")) == "normal" and str(job.get("status", "")) == "working" and str(job.get("contract_id", "")) == contract_id:
			out.append({"id":"working", "message":UI.copy("delivery_blocked_working"), "action":UI.copy("delivery_open_team"), "route":"team", "target_index":-1})
			break
	var targets: Array = s.get("targets", [])
	for index in maxi(1, targets.size()):
		var current := index == int(s.get("target_index", 0))
		var target: Dictionary = targets[index] if index < targets.size() else {}
		var projection: Dictionary = s if current else target
		var name := str(target.get("name", ""))
		if name.is_empty(): name = str(g.mission().get("title", "対象"))
		var checks: Array = projection.get("checks", [])
		var message := ""
		var kind := "verify"
		var route := "verify"
		var counts := delivery_measurement_counts(g.diagnostic_probes()) if current and bool(s.get("diagnostics_required", false)) and not g.advanced_active() else {}
		if not bool(projection.get("inspected", false)):
			message = UI.copy("delivery_blocked_inspect") % name
		elif not counts.is_empty() and int(counts.unrecorded) + int(counts.stale) + int(counts.failed) > 0:
			message = name + "：" + _measurement_summary(counts) + "。診断ラボで未確認・過去の結果を測定し、不合格の原因を確認してください。"
		elif int(projection.get("validated_revision", -1)) != int(projection.get("revision", 0)) or checks.is_empty():
			message = UI.copy("delivery_blocked_verify") % name
		else:
			var failed: Array = checks.filter(func(row): return not bool(row.get("passed", false)))
			var non_hardware: Array = failed.filter(func(row): return not bool(row.get("hardware", false)))
			if not failed.is_empty() and non_hardware.is_empty():
				message = UI.copy("delivery_blocked_hardware") % name; kind = "hardware"
				route = "preparation" if not s.get("contract", {}).get("supply_requirement", {}).is_empty() else "office"
			elif not failed.is_empty(): message = UI.copy("delivery_blocked_failed") % [name, failed.size()]
			elif g._vm_checks(index).any(func(row): return not bool(row.get("passed", false))):
				message = UI.copy("delivery_blocked_changed") % name
		if not message.is_empty(): out.append({"id":kind+"-"+str(index), "message":message, "action":UI.copy("delivery_open_office") if route in ["office", "preparation"] else UI.copy("delivery_open_checks") % name, "route":route, "target_index":index})
	if out.is_empty(): out.append({"id":"refresh", "message":UI.copy("delivery_blocked_other"), "action":UI.copy("delivery_open_checks") % str(g.mission().get("title", "対象")), "route":"verify", "target_index":-1})
	return out

static func _open_delivery_blocker(d, blocker: Dictionary) -> void:
	var index := int(blocker.get("target_index", -1))
	if index >= 0 and index != int(d.game.state.get("target_index", 0)):
		if not d._select_target(index): return
	var route := str(blocker.get("route", "verify"))
	if route == "board": d._contracts()
	elif route == "preparation": d._request_stock_preparation()
	elif route == "office": d._close()
	else: d._show_app(route)

static func _verify_receipt(d) -> void:
	var results: Array = d.game.verify()
	if results.is_empty(): d._notify(UI.copy("delivery_verify_failed"))
	refresh_receipt(d)

static func _add_care_conversion(d, parent: Control, prefix: String = "") -> bool:
	if not d.game.has_method("care_conversion_offer"): return false
	var proposal: Dictionary = d.game.care_conversion_offer()
	if not bool(proposal.get("available", false)): return false
	var box: VBoxContainer = d._box(parent, 8)
	box.name = prefix + "CareConversionNotice"
	box.add_child(d._label("継続保守の契約条件を確認", 17, ORANGE))
	box.add_child(d._label("この専門案件は継続保守の対象外です。単発契約へ変更して作業を続けられます。", 14, INK))
	box.add_child(d._label("合意済み料金 ¥%s ・ 納期 %d 分を維持\n調査・証拠・検証結果も引き継ぎます。" % [d._money(int(proposal.fee)), int(proposal.budget)], 14, INK))
	box.add_child(d._label("この案件の保守料は発生しません。既存の保守契約・別案件の保守予約は維持します。" if bool(proposal.retained_care) else "この案件の保守予約を取り消します。日々の保守料は発生しません。", 13, MUTED))
	var button: Button = d._primary("料金・納期を維持して単発へ変更", func():
		if not d.game.convert_current_care_to_standard():
			d._notify("契約変更を保存できませんでした。契約と作業内容を保持しています。")
			return
		d._notify("単発契約へ変更しました。合意済み料金・納期と作業内容を引き継ぎました。")
		refresh_mail(d); refresh_receipt(d)
	)
	button.name = prefix + "CareConvertStandard"; button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 42; box.add_child(button)
	return true

static func refresh_receipt(d) -> void:
	var body = d.widgets.receipt.body; var footer = d.widgets.receipt.footer; d._clear(body); d._clear(footer); var g = d.game
	if CLOSEOUT.render(d, body, footer): return
	if not g.current_done():
		body.add_child(d._label(_company_name(g)+"  /  DELIVERY STATEMENT",12,MUTED))
		body.add_child(d._label("納品前確認",27)); body.add_child(d._label(g.mission().title,17))
		CLOSEOUT.add_action(d, body)
		var conversion: bool = _add_care_conversion(d, body)
		var work: Dictionary = g.work_status()
		body.add_child(d._label("作業時間 %d / %d 分  ·  報酬 ¥%s  ·  経費 ¥%s" % [work.minutes,work.budget,d._money(work.estimated_fee),d._money(work.costs)],14,MUTED))
		var blockers: Array = [] if conversion else delivery_blockers(g)
		if not blockers.is_empty():
			var blocked: VBoxContainer = d._box(body, 7); blocked.name = "ReceiptBlockers"
			blocked.add_child(d._label(UI.copy("delivery_blocked_title"),17,ORANGE))
			for blocker in blockers:
				blocked.add_child(d._label(str(blocker.message),14,INK))
				var action: Button = d._button(str(blocker.action),_open_delivery_blocker.bind(d,blocker))
				action.name = "ReceiptResolve_"+str(blocker.id); action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; action.custom_minimum_size.y = 36
				blocked.add_child(action)
		if g.state.checks.is_empty():
			body.add_child(d._label("未検証",15,MUTED))
		else:
			var passed := 0
			var displayed_checks: Array = g.state.checks.duplicate(true)
			# Shipment arrival is a persisted physical event, separate from VM
			# configuration revision. Read its current status without measuring
			# or rerunning validation during rendering.
			if not g.state.get("contract", {}).get("supply_requirement", {}).is_empty():
				var hardware: Dictionary = g._customer_hardware()
				for item in displayed_checks:
					if bool(item.get("hardware", false)): item.passed = str(hardware.get("status", "")) == "delivered"
			var measured_by_id := {}
			if bool(g.state.get("diagnostics_required", false)) and not g.advanced_active():
				for probe in g.diagnostic_probes(): measured_by_id[str(probe.get("id", ""))] = probe
			for item in displayed_checks:
				if bool(item.passed): passed += 1
			var stale: bool = int(g.state.get("validated_revision", -1)) != int(g.state.get("revision", 0))
			if bool(g.state.get("diagnostics_required", false)):
				stale = stale or g.diagnostic_probes().any(func(probe): return bool(probe.get("recorded", false)) and probe.has("fresh") and not bool(probe.fresh))
			var summary := UI.copy("adv_results") + "  %d / %d" % [passed, g.state.checks.size()]
			if stale: summary += "  ·  " + UI.copy("os_result_stale")
			var details: VBoxContainer = d._disclosure(body, summary) if passed > 0 else d._box(body, 0)
			if passed == 0: body.add_child(d._label(summary,15,ORANGE))
			details.name = "DeliveryCheckDetails"
			for item in displayed_checks:
				if bool(item.get("probe", false)) and measured_by_id.has(str(item.get("id", ""))):
					var probe: Dictionary = measured_by_id[str(item.id)]
					if not bool(probe.get("recorded", false)):
						body.add_child(d._label("未確認  " + str(item.label),15,MUTED)); continue
					if not bool(probe.get("fresh", false)):
						body.add_child(d._label("過去の結果・再測定  " + str(item.label),15,ORANGE)); continue
				if bool(item.passed): details.add_child(d._label("✓  "+str(item.label),15,MUTED if stale else TEAL))
				else: body.add_child(d._label("×  "+str(item.label),15,ORANGE))
		if bool(g.case_review().get("available", false)):
			var baseline: VBoxContainer = d._disclosure(body, "変更前の記録")
			baseline.name = "ReceiptBaselineSection"
			_add_case_review(d, baseline, footer, true)
		if g.advanced_active():
			var back: Button = d._button(UI.copy("delivery_return_to_work"),d._show_app.bind("advanced")); back.name = "ReceiptReturnToWork"; footer.add_child(back)
		else:
			footer.add_child(d._button("設定編集",d._open_config)); footer.add_child(d._button("診断ラボ表示",d._show_app.bind("verify")))
		footer.add_child(d._button("再判定",_verify_receipt.bind(d)))
		var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(spacer)
		var report = d._primary("納品・精算",d._report); report.name="GuideDeliver"; report.disabled = not g.can_deliver(); footer.add_child(report); return
	var receipt: Dictionary = g.completion_receipt()
	if receipt.has("maintenance_incident_id"):
		var client := str(receipt.get("client", ""))
		var incident: Dictionary = g.care_incident(client)
		var status := str(incident.get("status", "recheck"))
		body.add_child(d._label(UI.copy("care_incident_covered")+" / "+UI.copy("care_incident_"+status),16,TEAL))
		if status == "recheck":
			var recheck: Button = d._primary(UI.copy("care_incident_reinspect"),func():
				if g.run_maintenance(client): refresh_receipt(d)
			)
			recheck.name = "CareReinspect"; recheck.disabled = not g.can_run_maintenance(client); footer.add_child(recheck)
	var receipt_key := "%s:%s:%s" % [str(receipt.get("day",g.state.day)),str(receipt.get("copy_id",receipt.get("title",""))),str(receipt.get("net",0))]
	var first_receipt_view := str(body.get_meta("receipt_key", "")) != receipt_key
	body.set_meta("receipt_key", receipt_key)
	preload("res://scripts/receipt_panel.gd").render(d, body, receipt, first_receipt_view)
	var next: Dictionary = preload("res://scripts/next_task_guide.gd").after_delivery(g)
	if str(next.id) != "recheck":
		var next_button: Button = d._primary(str(next.title),d._next_task)
		next_button.name = "ReceiptNextWork"; footer.add_child(next_button)
	footer.add_child(d._button("会社・スキル",d._company)); footer.add_child(d._button("受注履歴",func(): d._show_app("mail"); d.widgets.mail.folder = "history"; refresh_mail(d)))
	if first_receipt_view:
		body.modulate = Color(1,1,1,0.45)
		body.create_tween().tween_property(body,"modulate",Color.WHITE,0.25)
