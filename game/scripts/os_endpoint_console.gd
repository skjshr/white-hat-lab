extends RefCounted
class_name OSEndpointConsole

const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const WorkflowLinks = preload("res://scripts/endpoint_workflow_links.gd")
const Workstation = preload("res://assets/ui/endpoint/workstation-v1.png")
const Impact = preload("res://scripts/endpoint_engagement.gd")
const NAV := Color("f3f2f1")
const INK := Color("323130")
const MUTED := Color("605e5c")
const LINE := Color("edebe9")
const BLUE := Color("0078d4")

static func scale(d) -> float:
	return float(d.game.settings.get("text_scale", 1.0))

static func copy(key: String) -> String:
	return UI.copy(key)

static func _is_compact(d) -> bool:
	return float(d.windows.browser.size.x) < 1100 and not bool(d.edr_ui.get("nav_expanded", false))

static func _apply_live_layout(d, root: Control) -> void:
	if not is_instance_valid(root): return
	var compact := _is_compact(d)
	var compact_changed := bool(root.get_meta("edr_compact_applied", not compact)) != compact
	if compact_changed:
		root.set_meta("edr_compact_applied", compact)
		var nav_panel := root.find_child("EdrNavigationPanel", true, false) as Control
		if nav_panel != null: nav_panel.custom_minimum_size.x = 48 if compact else 204
		for item in ["devices", "actions"]:
			var nav_label := root.find_child("EdrNavLabel_" + item, true, false) as Control
			if nav_label != null: nav_label.visible = not compact
		var body := root.find_child("EdrBody", true, false) as VBoxContainer
		var panel := root.find_child("EdrPanel", true, false) as PanelContainer
		if body != null: body.add_theme_constant_override("separation", 8 if compact else 16)
		if panel != null: panel.add_theme_stylebox_override("panel", UI.style(Color.WHITE, Color.TRANSPARENT, 16 if compact else 28, 20, 0))
		var header := root.find_child("EdrDeviceHeader", true, false) as HBoxContainer
		var back := root.find_child("EdrBackDevices", true, false) as Button
		if header != null and back != null and body != null:
			back.text = "‹" if compact else "‹  " + copy("edr_devices")
			var target: Node = header if compact else body
			if back.get_parent() != target:
				back.get_parent().remove_child(back)
				target.add_child(back)
			if compact: header.move_child(back, 0)
			else: body.move_child(back, 0)
	var timeline_split := root.find_child("EdrEventSplit", true, false) as BoxContainer
	if timeline_split != null:
		var stacked := float(d.windows.browser.size.x) < 1280 * scale(d)
		timeline_split.vertical = stacked
		var detail_frame := timeline_split.find_child("EdrDetailsPane", false, false) as Control
		if detail_frame != null:
			detail_frame.custom_minimum_size = Vector2(0, 0) if stacked else Vector2(370, 0)
			detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL if stacked else Control.SIZE_FILL
	var file_profile := root.find_child("EdrRecoveryFileProfile", true, false) as BoxContainer
	if file_profile != null:
		var stacked := (float(d.windows.browser.size.x) - 80) / scale(d) < 580.0
		file_profile.vertical = stacked
		var metadata_frame := file_profile.find_child("EdrRecoveryFileMetadata", false, false) as Control
		if metadata_frame != null:
			metadata_frame.get_parent().custom_minimum_size.x = 0 if stacked else 260
			metadata_frame.get_parent().size_flags_stretch_ratio = 1.0 if stacked else 0.55

static func rcopy(key: String, fallback: String) -> String:
	return UI.copy(key, fallback)

static func recovery_error(_d, error: String) -> String:
	var key: String = {"destination_conflict":"conflict","unknown_file":"missing","file_missing":"missing","quarantine_corrupt":"invalid","quarantine_not_found":"no_record","trusted_file":"trusted"}.get(error,"")
	if not key.is_empty(): return copy("rmd_error_"+key)
	return UI.copy("edr_error_"+error,copy("rmd_error_failed"))

static func label(d, parent: Node, text: String, size := 14, color := INK) -> Label:
	var node: Label = d._label(text,size,color)
	node.add_theme_font_override("font",UI.font(600 if size>=18 else 400))
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

static func fluent_control(d, node: Control) -> void:
	node.add_theme_font_override("font",UI.font())
	node.add_theme_font_size_override("font_size",roundi(13*scale(d)))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		node.add_theme_color_override(key,INK)
	node.add_theme_color_override("font_disabled_color",Color("a19f9d"))
	for pair in [["normal",Color.WHITE,Color("8a8886")],["hover",Color("f3f2f1"),Color("605e5c")],["pressed",Color("edebe9"),INK],["disabled",Color("f3f2f1"),LINE],["focus",Color.TRANSPARENT,BLUE]]:
		var style := UI.style(pair[1],pair[2],10,5,3)
		style.set_border_width_all(2 if pair[0]=="focus" else 1)
		node.add_theme_stylebox_override(pair[0],style)

static func button(d, parent: Node, text: String, name: String, callback: Callable) -> Button:
	var node: Button=d._button(text,callback)
	fluent_control(d,node)
	node.name=name; node.custom_minimum_size.y=32*scale(d)
	parent.add_child(node)
	return node

static func render(d, parent: VBoxContainer) -> void:
	var state: Dictionary=d.edr_ui
	var snap: Dictionary=d.game._vm().edr_snapshot()
	var compact := _is_compact(d)
	var root:=VBoxContainer.new()
	root.name="EdrRoot"
	root.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	root.custom_minimum_size.y=maxf(300,float(d.windows.browser.size.y)-140)
	root.add_theme_constant_override("separation",0); parent.add_child(root)
	var masthead:=PanelContainer.new();masthead.name="EdrMasthead"
	masthead.add_theme_stylebox_override("panel",UI.style(Color("292827"),Color.TRANSPARENT,16,8,0));root.add_child(masthead)
	var brand:=HBoxContainer.new();brand.name="EdrBrand";brand.custom_minimum_size.y=32;brand.add_theme_constant_override("separation",12);masthead.add_child(brand)
	Glyph.add_to(brand,"network",24,Color.WHITE)
	label(d,brand,"Microsoft Defender",16,Color.WHITE)
	var host:=label(d,brand,str(d.game.vm_info().host),12,Color("e1dfdd"));host.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var layout:=HBoxContainer.new();layout.name="EdrLayout";layout.add_theme_constant_override("separation",0);layout.size_flags_vertical=Control.SIZE_EXPAND_FILL;root.add_child(layout)
	var nav_panel:=PanelContainer.new();nav_panel.name="EdrNavigationPanel"
	nav_panel.custom_minimum_size.x=48 if compact else 204
	nav_panel.add_theme_stylebox_override("panel",UI.style(NAV,Color.TRANSPARENT,0,8,0));layout.add_child(nav_panel)
	var nav:=VBoxContainer.new();nav.add_theme_constant_override("separation",2);nav_panel.add_child(nav)
	var expand:=button(d,nav,"≡","EdrNavigation",func():state["nav_expanded"]=not bool(state.get("nav_expanded",false));d._render_endpoint())
	expand.alignment=HORIZONTAL_ALIGNMENT_LEFT
	expand.add_theme_stylebox_override("normal",UI.style(NAV,Color.TRANSPARENT,16,4,0))
	var view:=str(state.get("view","devices"))
	for item in ["devices","actions"]:
		var node: Button=button(d,nav,"","EdrView_"+item,func():
			state["view"]=item;state.erase("device");state.erase("output");d._render_endpoint())
		node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		node.custom_minimum_size.y=42*scale(d)
		node.tooltip_text=copy("edr_"+item)
		var style:=UI.style(Color("e1dfdd") if item==view else NAV,BLUE if item==view else Color.TRANSPARENT,0,0,0)
		style.set_border_width_all(0);style.border_width_left=3
		node.add_theme_stylebox_override("normal",style)
		var nav_row:=HBoxContainer.new();nav_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;nav_row.add_theme_constant_override("separation",12);node.add_child(nav_row)
		nav_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);nav_row.offset_left=12;nav_row.offset_right=-8
		Glyph.add_to(nav_row,"device" if item=="devices" else "file",24,INK)
		var nav_label:=label(d,nav_row,copy("edr_"+item),13);nav_label.name="EdrNavLabel_"+item;nav_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;nav_label.visible=not compact
	var panel:=PanelContainer.new();panel.name="EdrPanel";panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",UI.style(Color.WHITE,Color.TRANSPARENT,16 if compact else 28,20,0));layout.add_child(panel)
	var body:=VBoxContainer.new();body.name="EdrBody";body.add_theme_constant_override("separation",8 if compact else 16);panel.add_child(body)
	if view=="actions":
		if bool(snap.get("recovery_enabled",false)):
			recovery_actions(d,body,snap)
		else:
			actions(d,body,snap)
	else: devices(d,body,state,snap)
	var result: Dictionary=state.get("output",{})
	if not result.is_empty() and not bool(result.get("ok",false)):
		var error:=str(result.get("error",""))
		var message:=recovery_error(d,error) if bool(snap.get("recovery_enabled",false)) else copy("edr_error_"+error)
		label(d,body,message if not message.is_empty() else copy("edr_operation_failed"),14,UI.RED)
	var space:=Control.new();space.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(space)
	root.resized.connect(func():_apply_live_layout(d,root))
	_apply_live_layout(d,root)

static func run(d, command: String) -> void:
	var raw: String=d._endpoint_command("edr "+command)
	var parsed=JSON.parse_string(raw)
	d.edr_ui["output"]=parsed if parsed is Dictionary else {"ok":false,"error":""}
	d.get_node("/root/Soundscape").play_ui("work_success" if bool(d.edr_ui.output.get("ok",false)) else "work_failure")
	d._render_endpoint()

static func device_name(value: String) -> String:
	return value.to_upper().replace("_","-")

static func _business_state(snap: Dictionary, selected: String) -> String:
	var record := recovery_device_record(snap, selected)
	var processes: Array = snap.get("processes", []).filter(func(item): return item is Dictionary and str(item.get("device", "")) == selected)
	var files: Array = snap.get("files", []).filter(func(item): return item is Dictionary and str(item.get("device", "")) == selected)
	return JSON.stringify({"device":{"isolated":record.get("isolated",false),"business_status":record.get("business_status",""),"management_connected":record.get("management_connected",false)}, "processes":processes, "files":files}, "", true)

static func _business_probe(d, selected: String) -> void:
	# Exercise the same endpoint as the browser and shell, including isolation
	# and remediation effects. A device status badge is not an HTTP observation.
	var url := "https://edr.client.test/" + selected.replace("_", "-") + "/business"
	var response: String = d.game.vm_run("curl " + url)
	var observations: Dictionary = d.edr_ui.get("business_observations", {})
	var previous: Dictionary = observations.get(selected, {})
	observations[selected] = {"url":url, "response":response, "state":_business_state(d.game._vm().edr_snapshot(), selected), "previous":str(previous.get("response", ""))}
	d.edr_ui["business_observations"] = observations
	d._save_session(false)
	if d.widgets.has("verify"): d._refresh_checks()
	d._render_endpoint()

static func _normal_use(d, body: VBoxContainer, state: Dictionary, snap: Dictionary, selected: String) -> void:
	var panel := frame(body, Color("f5f8fa"))
	panel.name = "EdrBusinessVerification"
	var controls := HFlowContainer.new(); controls.add_theme_constant_override("h_separation", 8); panel.add_child(controls)
	button(d, controls, "端末から業務接続を確認", "EdrBusinessProbe_" + selected, func(): _business_probe(d, selected))
	button(d, controls, "端末状態を再読込", "EdrRefresh_" + selected, func(): d._render_endpoint())
	var observation: Dictionary = state.get("business_observations", {}).get(selected, {})
	if observation.is_empty():
		label(d, panel, "接続結果 · 未測定", 12, MUTED)
	else:
		var response := str(observation.get("response", ""))
		var fresh := str(observation.get("state", "")) == _business_state(snap, selected)
		var status := response.get_slice("\n", 0)
		var meaning := str({"200":"業務サイトを利用できました", "403":"業務接続は拒否されました", "503":"業務サービスを利用できません"}.get(status.get_slice(" ", 1), "業務接続の結果"))
		var result := label(d, panel, ("" if fresh else "変更前の結果 · 再確認が必要: ") + meaning + " · " + status, 13, INK if fresh else MUTED)
		result.name = "EdrBusinessResult_" + selected
		var details: VBoxContainer = d._disclosure(panel, "要求と応答")
		label(d, details, "GET " + str(observation.get("url", "")) + "\n" + response, 12, MUTED)
		var previous := str(observation.get("previous", ""))
		if not previous.is_empty() and previous != response: label(d, details, "前回の応答\n" + previous, 12, MUTED)
	if bool(snap.get("recovery_enabled", false)):
		var processes: VBoxContainer = d._disclosure(panel, "稼働プロセス")
		processes.name = "EdrProcesses_" + selected
		for process in snap.get("processes", []):
			if not process is Dictionary or str(process.get("device", "")) != selected: continue
			var file := recovery_file(snap, str(process.get("file_id", "")))
			label(d, processes, str(file.get("name", process.get("file_id", ""))) + "  ·  " + ("稼働中" if bool(process.get("running", false)) else "停止"), 13, INK)

static func frame(parent: Node, color := Color.WHITE) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.style(color, LINE, 18, 16, 0))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box

static func chip(d, parent: Node, text: String, healthy: bool) -> void:
	var status_label:=label(d,parent,"●  "+text,13,Color("107c10") if healthy else Color("a4262c"))
	status_label.size_flags_horizontal=Control.SIZE_FILL
	status_label.autowrap_mode=TextServer.AUTOWRAP_OFF

static func tabline(d, parent: Node, text: String, name: String) -> void:
	var strip:=VBoxContainer.new();strip.add_theme_constant_override("separation",0);parent.add_child(strip)
	var tab:=label(d,strip,text,14);tab.name=name;tab.add_theme_font_override("font",UI.font(600));tab.custom_minimum_size.y=(32 if float(d.windows.browser.size.x)<1100 else 40)*scale(d)
	var line:=ColorRect.new();line.color=BLUE;line.custom_minimum_size=Vector2(100*scale(d),2);line.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;strip.add_child(line)
	var rule:=ColorRect.new();rule.color=LINE;rule.custom_minimum_size.y=1;strip.add_child(rule)

static func table_row(parent: Node, color:=Color.WHITE) -> HBoxContainer:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var style:=UI.style(color,LINE,10,7,0);style.set_border_width_all(0);style.border_width_bottom=1
	panel.add_theme_stylebox_override("panel",style);parent.add_child(panel)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);panel.add_child(row)
	return row

static func inventory(d, parent: VBoxContainer, rows: Array, state: Dictionary, query: String) -> void:
	d._clear(parent)
	var head:=table_row(parent,Color("faf9f8"))
	for key in ["edr_device","edr_status","edr_business","edr_management"]:
		label(d,head,copy(key),12).size_flags_stretch_ratio=1.0
	var found:=0
	for device in rows:
		var id:=str(device.id)
		if not query.is_empty() and not device_name(id).to_lower().contains(query.to_lower()):continue
		found+=1
		var open:=button(d,parent,"","EdrDevice_"+id,func():
			state["device"]=id;state["event_index"]=0;state["query"]="";state["event_type"]="all";state["details_open"]=true;state.erase("output");d._render_endpoint())
		open.size_flags_horizontal=Control.SIZE_EXPAND_FILL;open.custom_minimum_size.y=46*scale(d)
		var row_style:=UI.style(Color.WHITE,LINE,10,7,0);row_style.set_border_width_all(0);row_style.border_width_bottom=1
		open.add_theme_stylebox_override("normal",row_style)
		open.add_theme_stylebox_override("hover",UI.style(Color("f3f2f1"),Color.TRANSPARENT,10,7,0))
		var row:=HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_theme_constant_override("separation",14);open.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);row.offset_left=10;row.offset_right=-10
		var device_cell:=Control.new();device_cell.mouse_filter=Control.MOUSE_FILTER_IGNORE;device_cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(device_cell)
		var first:=HBoxContainer.new();first.mouse_filter=Control.MOUSE_FILTER_IGNORE;first.add_theme_constant_override("separation",10);device_cell.add_child(first);first.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Glyph.add_to(first,"device",22,MUTED)
		var title:=label(d,first,device_name(id),13,BLUE);title.mouse_filter=Control.MOUSE_FILTER_IGNORE;title.autowrap_mode=TextServer.AUTOWRAP_OFF
		for value in [copy("edr_isolated" if device.isolated else "edr_connected"),copy("edr_available" if str(device.business_status)=="healthy" else "edr_blocked"),copy("edr_connected" if device.management_connected else "edr_blocked")]:
			label(d,row,value,13).mouse_filter=Control.MOUSE_FILTER_IGNORE
	if found==0:label(d,parent,copy("edr_no_results"),14,MUTED)

static func recovery_device_record(snap: Dictionary, device_id: String) -> Dictionary:
	for raw in snap.get("devices",[]):
		if raw is Dictionary and str(raw.get("id",""))==device_id:return raw
	return {}

static func recovery_scan_data(snap: Dictionary, device_id: String) -> Dictionary:
	var scans: Variant=snap.get("scans",{})
	if scans is Dictionary and scans.get(device_id,{}) is Dictionary:return scans.get(device_id,{})
	return {}

static func recovery_scan_text(d, device: Dictionary, snap: Dictionary = {}) -> String:
	var current := bool(device.get("scan_current",false))
	var scan:=recovery_scan_data(snap,str(device.get("id","")))
	var findings: Array=scan.get("findings",[]) if scan.get("findings",[]) is Array else []
	if scan.is_empty():
		return rcopy("rmd_no_scan", "No scan")
	if not current:
		return rcopy("rmd_scan_stale", "Scan required")
	if bool(scan.get("clean",false)) and findings.is_empty():
		return rcopy("rmd_scan_clean", "Clean")
	return rcopy("rmd_scan_threats", "%d threats" % findings.size())

static func recovery_inventory(d, body: VBoxContainer, rows: Array, state: Dictionary, snap: Dictionary) -> void:
	label(d,body,"業務と端末",24).name="EdrRecoveryInventoryTab"
	var scenario: Dictionary = d.game._scenario()
	if int(scenario.get("endpoint_engagement",0))==1:
		var sites := HFlowContainer.new(); sites.name="EdrSiteChoices"
		sites.add_theme_constant_override("h_separation",8); body.add_child(sites)
		for index in d.game.state.targets.size():
			var current: bool = index==int(d.game.state.target_index)
			var pick := button(d,sites,("●  " if current else "○  ")+str(d.game.state.targets[index].name),"EdrSite_"+str(index),func():
				if d._select_target(index): d._show_app("terminal"))
			pick.disabled=current
		var impact: Dictionary=d.game.state.work.get("endpoint_impact",{})
		label(d,body,Impact.summary(impact),12,MUTED).name="EdrImpactSummary"
	var headings := HBoxContainer.new();headings.add_theme_constant_override("separation",28);body.add_child(headings)
	for title in ["業務接続を確認", "端末を調査", "通信記録を開く"]:
		var heading := label(d,headings,title,12,MUTED);heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var map := VBoxContainer.new(); map.name="EdrRecoveryDeviceRows";map.add_theme_constant_override("separation",8);body.add_child(map)
	for raw in rows:
		if not raw is Dictionary: continue
		var device: Dictionary=raw
		var id:=str(device.get("id",""))
		var row:=Control.new();row.name="EdrWorkflow_"+id;row.custom_minimum_size.y=148*scale(d);map.add_child(row)
		var links:=WorkflowLinks.new();row.add_child(links);links.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var layout:=HBoxContainer.new();layout.add_theme_constant_override("separation",28);row.add_child(layout);layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var job:=_object_button(d,layout,"EdrBusinessProbe_"+id,func():_business_probe(d,id))
		var job_box:=_object_content(job)
		Glyph.add_to(job_box,"file",30,BLUE)
		var job_title:=label(d,job_box,str(scenario.get("endpoint_business",{}).get(id,"業務サイト")),14)
		job_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var observation: Dictionary=state.get("business_observations",{}).get(id,{})
		var result:="未測定"
		if not observation.is_empty():
			result=str(observation.get("response","")).get_slice("\n",0)
			if str(observation.get("state",""))!=_business_state(snap,id): result="変更前 · "+result
		label(d,job_box,result,12,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var open:=_object_button(d,layout,"EdrDevice_"+id,func():_open_recovery_device(d,state,id))
		var device_box:=_object_content(open)
		var image:=TextureRect.new();image.texture=Workstation;image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size.y=86*scale(d);device_box.add_child(image)
		label(d,device_box,device_name(id)+" · "+copy("edr_isolated" if bool(device.get("isolated",false)) else "edr_connected"),14).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var scan_label:=label(d,device_box,recovery_scan_text(d,device,snap),12,MUTED);scan_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var event: Dictionary={}
		var trace_index:=0
		for index in device.get("events",[]).size():
			var item: Dictionary=device.events[index]
			if str(item.get("type",""))=="outbound": event=item;trace_index=index;break
		var evidence:=_object_button(d,layout,"EdrTrace_"+id,func():_open_recovery_device(d,state,id,trace_index))
		var evidence_box:=_object_content(evidence)
		Glyph.add_to(evidence_box,"network",28,MUTED)
		label(d,evidence_box,"記録 "+str(event.get("time","—")),12,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label(d,evidence_box,str(event.get("process","通信記録なし")),13).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label(d,evidence_box,str(event.get("remote_address","—")),12,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		links.bind_controls(job,open,evidence,bool(device.get("isolated",false)),scale(d))
		for object in [job_box,device_box,evidence_box]:_ignore_object_children(object)
	label(d,body,"実線: 接続設定   ×: 隔離   点線: 過去の記録",11,MUTED)

static func _object_button(d, parent: Node, name: String, callback: Callable) -> Button:
	var node:=button(d,parent,"",name,callback)
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for pair in [["normal",Color.TRANSPARENT,Color.TRANSPARENT],["hover",Color("f0f6fc"),Color("deecf9")],["pressed",Color("deecf9"),BLUE]]:
		var style:=UI.style(pair[1],pair[2],4,4,4);style.set_border_width_all(1)
		node.add_theme_stylebox_override(pair[0],style)
	return node

static func _object_content(parent: Control) -> VBoxContainer:
	var margin:=MarginContainer.new();parent.add_child(margin);margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,5)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",3);box.size_flags_vertical=Control.SIZE_SHRINK_CENTER;margin.add_child(box)
	box.alignment=BoxContainer.ALIGNMENT_CENTER
	return box

static func _ignore_object_children(parent: Control) -> void:
	parent.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in parent.get_children():
		if child is Control:_ignore_object_children(child)

static func _open_recovery_device(d, state: Dictionary, id: String, event_index: int = 0) -> void:
	state["device"]=id;state["event_index"]=event_index;state["query"]="";state["event_type"]="all"
	state["details_open"]=true;state["recovery_tab"]="timeline";state.erase("file_id");state.erase("output")
	d._render_endpoint()
	_show_top.call_deferred(d)

static func _show_top(d) -> void:
	if not is_instance_valid(d) or not d.widgets.has("browser"):return
	var node: Node=d.widgets.browser.page
	while node!=null and not node is ScrollContainer:node=node.get_parent()
	if node is ScrollContainer:node.scroll_vertical=0

static func recovery_device(d, body: VBoxContainer, state: Dictionary, snap: Dictionary, current: Dictionary) -> void:
	var selected:=str(state.get("device",""))
	if not str(state.get("file_id","")).is_empty():
		var selected_file:=recovery_file(snap,str(state.get("file_id","")))
		if selected_file.is_empty(): state.erase("file_id")
		else:
			recovery_file_profile(d,body,state,snap,selected_file)
			return
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",12);body.add_child(header)
	var back:=button(d,header,"‹  "+copy("edr_devices"),"EdrBackDevices",func():state.erase("device");state.erase("file_id");d._render_endpoint())
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	Glyph.add_to(header,"device",32,MUTED)
	label(d,header,device_name(selected),24)
	var status:=HFlowContainer.new();status.add_theme_constant_override("h_separation",12);status.add_theme_constant_override("v_separation",5);body.add_child(status)
	chip(d,status,copy("edr_status")+" · "+copy("edr_isolated" if bool(current.get("isolated",false)) else "edr_connected"),not bool(current.get("isolated",false)))
	chip(d,status,copy("edr_business")+" · "+copy("edr_available" if str(current.get("business_status",""))=="healthy" else "edr_blocked"),str(current.get("business_status",""))=="healthy")
	var current_scan:=recovery_scan_data(snap,selected)
	var current_findings: Array=current_scan.get("findings",[]) if current_scan.get("findings",[]) is Array else []
	var threat_text:=rcopy("rmd_detected_count","Findings: {count}").replace("{count}",(str(current_findings.size()) if not current_scan.is_empty() else "—"))
	if current_scan.is_empty() or not bool(current.get("scan_current",false)):
		var unknown:=label(d,status,"○  "+threat_text+" · "+recovery_scan_text(d,current,snap),13,MUTED)
		unknown.size_flags_horizontal=Control.SIZE_FILL;unknown.autowrap_mode=TextServer.AUTOWRAP_OFF
	else:
		chip(d,status,threat_text,current_findings.is_empty())
		chip(d,status,copy("rmd_scan_results")+" · "+recovery_scan_text(d,current,snap),bool(current_scan.get("clean",false)))
	var controls:=HFlowContainer.new();controls.add_theme_constant_override("h_separation",8);controls.add_theme_constant_override("v_separation",6);body.add_child(controls)
	button(d,controls,("✓  " if bool(snap.get("evidence",{}).get("valid",false)) else "")+copy("edr_collect"),"EdrCollect",func():run(d,"collect"))
	button(d,controls,rcopy("rmd_scan","Scan"),"EdrScan_"+selected,func():run(d,"scan "+selected))
	var isolated:=bool(current.get("isolated",false))
	var isolate_button:=button(d,controls,copy("edr_release" if isolated else "edr_isolate"),("EdrRelease_" if isolated else "EdrIsolate_")+selected,func():run(d,("release " if isolated else "isolate ")+selected))
	isolate_button.disabled=not bool(current.get("management_connected",false))
	_normal_use(d, body, state, snap, selected)
	var tab_row:=HFlowContainer.new();tab_row.name="EdrRecoveryTabs";tab_row.add_theme_constant_override("h_separation",8);body.add_child(tab_row)
	var active_tab:=str(state.get("recovery_tab","timeline"))
	for tab_id in ["timeline","files"]:
		var tab:=button(d,tab_row,copy("edr_timeline" if tab_id=="timeline" else "rmd_files"),"RecoveryTab_"+tab_id,func():state["recovery_tab"]=tab_id;state.erase("file_id");d._render_endpoint())
		var tab_style:=UI.style(Color.WHITE,BLUE if active_tab==tab_id else Color.TRANSPARENT,12,6,0)
		tab_style.set_border_width_all(0);tab_style.border_width_bottom=2
		tab.add_theme_stylebox_override("normal",tab_style)
	if active_tab=="files":
		recovery_files(d,body,state,snap,selected)
		return
	tabline(d,body,copy("edr_timeline"),"EdrTab_timeline")
	var toolbar:=HBoxContainer.new();body.add_child(toolbar)
	var search:=LineEdit.new();search.name="EdrSearch";search.placeholder_text=copy("edr_search");search.text=str(state.get("query",""));search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(search);fluent_control(d,search)
	var filter:=OptionButton.new();filter.name="EdrTypeFilter";toolbar.add_child(filter);fluent_control(d,filter)
	var types: Array[String]=["all","outbound","file_read","dns"]
	for key in ["experience_all_events","experience_network_events","experience_file_events","experience_dns_events"]:filter.add_item(copy(key))
	filter.select(maxi(0,types.find(str(state.get("event_type","all")))))
	var timeline:=VBoxContainer.new();timeline.name="EdrTimelineRows";timeline.add_theme_constant_override("separation",12);body.add_child(timeline)
	search.text_changed.connect(func(value: String):state["query"]=value;timeline_rows(d,timeline,current,state,snap))
	filter.item_selected.connect(func(index: int):state["event_type"]=types[index];timeline_rows(d,timeline,current,state,snap))
	timeline_rows(d,timeline,current,state,snap)

static func recovery_files(d, body: VBoxContainer, state: Dictionary, snap: Dictionary, device_id: String) -> void:
	var heading:=label(d,body,rcopy("rmd_files","Files"),18,INK)
	heading.name="EdrRecoveryFilesTitle"
	var search:=LineEdit.new();search.name="EdrRecoveryFileSearch";search.placeholder_text=copy("edr_search");search.text=str(state.get("file_query",""));search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;fluent_control(d,search);body.add_child(search)
	var table:=VBoxContainer.new();table.name="EdrRecoveryFileRows";table.add_theme_constant_override("separation",0);body.add_child(table)
	search.text_changed.connect(func(value: String):state["file_query"]=value;recovery_file_rows(d,table,snap,device_id,value,state))
	recovery_file_rows(d,table,snap,device_id,search.text,state)

static func recovery_file_rows(d, table: VBoxContainer, snap: Dictionary, device_id: String, query: String, state: Dictionary) -> void:
	d._clear(table)
	var head:=table_row(table,Color("faf9f8"))
	for key in ["rmd_file","rmd_path","edr_status","rmd_sha256"]:
		label(d,head,rcopy(key,key),12,MUTED).size_flags_stretch_ratio=1.0
	var found:=0
	var files: Array=snap.get("files",[])
	for raw in files:
		if not raw is Dictionary: continue
		var file: Dictionary=raw
		if not device_id.is_empty() and str(file.get("device",""))!=device_id: continue
		var haystack: String=" ".join([str(file.get("name","")),str(file.get("path","")),str(file.get("publisher",""))]).to_lower()
		if not query.is_empty() and not haystack.contains(query.to_lower()):continue
		found+=1
		var file_id:=str(file.get("id",""))
		var open:=button(d,table,"","EdrRecoveryFile_"+file_id,func():state["file_id"]=file_id;d._render_endpoint();_show_top.call_deferred(d))
		open.size_flags_horizontal=Control.SIZE_EXPAND_FILL;open.custom_minimum_size.y=44*scale(d)
		var row_style:=UI.style(Color.WHITE,LINE,10,6,0);row_style.set_border_width_all(0);row_style.border_width_bottom=1
		open.add_theme_stylebox_override("normal",row_style)
		open.add_theme_stylebox_override("hover",UI.style(Color("f3f2f1"),Color.TRANSPARENT,10,6,0))
		var row:=HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_theme_constant_override("separation",12);open.add_child(row);row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);row.offset_left=10;row.offset_right=-10
		var name:=label(d,row,str(file.get("name","")),13,BLUE);name.mouse_filter=Control.MOUSE_FILTER_IGNORE;name.size_flags_stretch_ratio=1.0
		var path:=label(d,row,str(file.get("path","")),12,MUTED);path.mouse_filter=Control.MOUSE_FILTER_IGNORE;path.autowrap_mode=TextServer.AUTOWRAP_OFF;path.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;path.size_flags_stretch_ratio=1.25
		var status:=recovery_file_status(d,file)
		var status_label:=label(d,row,status,12,UI.RED if bool(file.get("quarantined",false)) else INK);status_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;status_label.size_flags_stretch_ratio=1.0
		var hash_label:=label(d,row,str(file.get("sha256","")),11,MUTED);hash_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;hash_label.autowrap_mode=TextServer.AUTOWRAP_OFF;hash_label.tooltip_text=str(file.get("sha256",""));hash_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;hash_label.size_flags_stretch_ratio=1.2
	if found==0:label(d,table,copy("edr_no_results"),14,MUTED)

static func recovery_file_status(d, file: Dictionary) -> String:
	if bool(file.get("quarantined",false)):return rcopy("rmd_quarantined","Quarantined")
	if not bool(file.get("present",false)):return rcopy("rmd_absent","Absent")
	return rcopy("rmd_running","Running") if bool(file.get("running",false)) else rcopy("rmd_stopped","Stopped")

static func recovery_file_profile(d, body: VBoxContainer, state: Dictionary, snap: Dictionary, file: Dictionary) -> void:
	var top:=HFlowContainer.new();top.add_theme_constant_override("h_separation",12);top.add_theme_constant_override("v_separation",6);body.add_child(top)
	button(d,top,"‹  "+rcopy("rmd_files","Files"),"RecoveryBackFiles",func():state.erase("file_id");state["recovery_tab"]="files";d._render_endpoint())
	label(d,top,str(file.get("name","")),20,INK)
	if bool(file.get("present",false)) and not bool(file.get("quarantined",false)):
		var quarantine:=button(d,top,rcopy("rmd_quarantine","Stop and quarantine"),"EdrQuarantine_"+str(file.get("id","")),func():run(d,"quarantine "+str(file.get("device",""))+" "+str(file.get("id",""))))
		quarantine.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		var publisher:=str(file.get("publisher",""))
		quarantine.disabled=bool(file.get("protected",file.get("trusted",false))) or publisher.to_lower().contains("microsoft")
	var split:=BoxContainer.new();split.vertical=(float(d.windows.browser.size.x)-80)/scale(d)<580.0
	split.name="EdrRecoveryFileProfile"
	split.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var metadata:=frame(split,Color.WHITE);metadata.name="EdrRecoveryFileMetadata"
	if split is HBoxContainer:
		metadata.get_parent().size_flags_stretch_ratio=0.55
		metadata.get_parent().custom_minimum_size.x=260
	Glyph.add_to(metadata,"file",44,BLUE)
	label(d,metadata,str(file.get("name","")),20,INK)
	_field(d,metadata,rcopy("rmd_path","Path"),str(file.get("path","")))
	_field(d,metadata,copy("edr_publisher"),str(file.get("publisher","")))
	_field(d,metadata,copy("edr_device"),device_name(str(file.get("device",""))))
	_field(d,metadata,copy("rmd_observed_hash"),str(file.get("sha256","")))
	var current_hash:=str(file.get("current_sha256",""))
	if not current_hash.is_empty() and current_hash!=str(file.get("sha256","")): _field(d,metadata,copy("rmd_current_hash"),current_hash)
	_field(d,metadata,copy("edr_change"),str(file.get("change_ref","")))
	_field(d,metadata,rcopy("rmd_action_result","Status"),recovery_file_status(d,file))
	var overview:=frame(split,Color.WHITE);overview.name="EdrRecoveryFileOverview"
	overview.get_parent().size_flags_stretch_ratio=1.3
	tabline(d,overview,copy("rmd_overview"),"RecoveryFileOverviewTab")
	var device_id:=str(file.get("device",""))
	var observed:=VBoxContainer.new();observed.name="EdrRecoveryObservedDevices";observed.add_theme_constant_override("separation",4);overview.add_child(observed)
	label(d,observed,rcopy("edr_device","Observed device"),12,MUTED)
	var device:=recovery_device_record(snap,device_id)
	var observed_row:=table_row(observed,Color("fafafa"))
	label(d,observed_row,device_name(device_id),13,BLUE)
	label(d,observed_row,recovery_scan_text(d,device,snap) if not device.is_empty() else rcopy("rmd_no_scan","No scan"),12,INK)
	label(d,observed_row,recovery_file_status(d,file),12,UI.RED if bool(file.get("quarantined",false)) else INK)
	var scan_data: Dictionary=recovery_scan_data(snap,device_id)
	label(d,overview,copy("rmd_scan_results"),12,MUTED)
	var findings: Array=scan_data.get("findings",[]) if scan_data.get("findings",[]) is Array else []
	if not bool(device.get("scan_current",false)):
		label(d,overview,recovery_scan_text(d,device,snap),13,UI.WARNING)
	elif findings.is_empty():
		label(d,overview,rcopy("rmd_scan_clean","No findings") if bool(scan_data.get("clean",false)) else rcopy("rmd_no_scan","No scan"),13,UI.GREEN if bool(scan_data.get("clean",false)) else UI.WARNING)
	else:
		for finding in findings:
			if not finding is Dictionary or str(finding.get("file_id",""))!=str(file.get("id","")): continue
			var row:=table_row(overview)
			var kind:=str(finding.get("kind","file"))
			label(d,row,copy("rmd_persistence" if kind=="persistence" else "edr_process" if kind=="process" else "rmd_file"),12,MUTED)
			label(d,row,str(file.get("name","")),13,UI.RED)

static func _field(d, parent: Node, key: String, value: String) -> void:
	var row:=VBoxContainer.new();row.add_theme_constant_override("separation",2);parent.add_child(row)
	label(d,row,key,11,MUTED)
	var content:=label(d,row,value if not value.is_empty() else "—",13,INK)
	content.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.tooltip_text=value

static func recovery_file(snap: Dictionary, file_id: String) -> Dictionary:
	for raw in snap.get("files",[]):
		if raw is Dictionary and str(raw.get("id",""))==file_id:return raw
	return {}

static func recovery_quarantine(snap: Dictionary, quarantine_id: String) -> Dictionary:
	for raw in snap.get("quarantine",[]):
		if raw is Dictionary and str(int(raw.get("id",0)))==quarantine_id:return raw
	return {}

static func recovery_actions(d, body: VBoxContainer, snap: Dictionary) -> void:
	label(d,body,copy("edr_actions"),24)
	tabline(d,body,copy("edr_actions"),"EdrActionsTab")
	var records: Array=snap.get("actions",[])
	if records.is_empty():label(d,body,copy("edr_no_results"),14,MUTED)
	var table:=VBoxContainer.new();table.name="EdrRecoveryActionRows";table.add_theme_constant_override("separation",0);body.add_child(table)
	var heading:=table_row(table,Color("faf9f8"))
	for text in [copy("edr_device"),copy("edr_actions"),copy("rmd_action_result")]:label(d,heading,text,12,MUTED)
	for raw in records:
		if not raw is Dictionary:continue
		var item: Dictionary=raw
		var qid:=str(int(item.get("quarantine_id",0)))
		var q:=recovery_quarantine(snap,qid)
		var file:=recovery_file(snap,str(item.get("file_id","")))
		var action:=str(item.get("action",""))
		var row:=table_row(table)
		var device:=str(item.get("device",""))
		label(d,row,copy("edr_evidence") if device=="evidence" else device_name(device),13)
		var detail: VBoxContainer=d._box(row,2);detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label(d,detail,copy(("rmd_" if action in ["quarantine","restore","scan"] else "edr_")+action),13)
		if not file.is_empty():
			label(d,detail,str(file.get("name","")),12,MUTED)
			var hash_label:=label(d,detail,str(item.get("sha256","")),11,MUTED)
			hash_label.autowrap_mode=TextServer.AUTOWRAP_OFF;hash_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;hash_label.tooltip_text=hash_label.text
		var restored:=action=="quarantine" and bool(q.get("restored",false))
		var result:=VBoxContainer.new();result.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(result)
		label(d,result,copy("rmd_restored" if restored else "rmd_completed"),12,INK)
		if action=="quarantine" and not q.is_empty() and not restored:
			var undo:=button(d,result,copy("rmd_restore"),"EdrRestore_"+qid,func():run(d,"restore "+qid))
			undo.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	body.add_child(HSeparator.new())
	var evidence: Dictionary=snap.get("evidence",{})
	label(d,body,copy("edr_evidence"),18)
	label(d,body,copy("edr_integrity_ok" if bool(evidence.get("valid",false)) else "edr_integrity_bad" if bool(evidence.get("collected",false)) else "edr_no_package"),13,MUTED)

static func devices(d, body: VBoxContainer, state: Dictionary, snap: Dictionary) -> void:
	var selected := str(state.get("device", ""))
	var rows: Array = snap.get("devices", [])
	if selected.is_empty():
		if bool(snap.get("recovery_enabled",false)):
			recovery_inventory(d,body,rows,state,snap)
			return
		label(d,body,copy("edr_devices"),24)
		tabline(d,body,copy("edr_device")+"  ("+str(rows.size())+")","EdrInventoryTab")
		var search:=LineEdit.new();search.name="EdrInventorySearch";search.placeholder_text=copy("edr_search");search.text=str(state.get("inventory_query",""));search.custom_minimum_size.x=260*scale(d);search.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;fluent_control(d,search);body.add_child(search)
		var table:=VBoxContainer.new();table.name="EdrInventoryRows";table.add_theme_constant_override("separation",0);body.add_child(table)
		search.text_changed.connect(func(value):state["inventory_query"]=value;inventory(d,table,rows,state,value))
		inventory(d,table,rows,state,search.text)
		return
	var current: Dictionary = {}
	for row in rows:
		if str(row.id)==selected: current=row;break
	if current.is_empty():label(d,body,copy("edr_no_results"));return
	if bool(snap.get("recovery_enabled",false)):
		recovery_device(d,body,state,snap,current)
		return
	var header := HBoxContainer.new();header.name="EdrDeviceHeader";header.add_theme_constant_override("separation",12);body.add_child(header)
	var compact:=_is_compact(d)
	var back:=button(d,header if compact else body,"‹" if compact else "‹  "+copy("edr_devices"),"EdrBackDevices",func():state.erase("device");d._render_endpoint())
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;back.tooltip_text=copy("edr_devices")
	if not compact:body.move_child(back,0)
	Glyph.add_to(header,"device",32,MUTED)
	label(d,header,device_name(selected),24)
	var status := HFlowContainer.new();status.add_theme_constant_override("h_separation",12);status.add_theme_constant_override("v_separation",5);body.add_child(status)
	chip(d,status,copy("edr_status")+" · "+copy("edr_isolated" if current.isolated else "edr_connected"),not current.isolated)
	chip(d,status,copy("edr_business")+" · "+copy("edr_available" if str(current.business_status)=="healthy" else "edr_blocked"),str(current.business_status)=="healthy")
	chip(d,status,copy("edr_management")+" · "+copy("edr_connected" if current.management_connected else "edr_blocked"),current.management_connected)
	var controls := HFlowContainer.new();controls.add_theme_constant_override("h_separation",8);controls.add_theme_constant_override("v_separation",6);body.add_child(controls)
	var isolated := bool(current.isolated)
	var action := button(d,controls,copy("edr_release" if isolated else "edr_isolate"),("EdrRelease_" if isolated else "EdrIsolate_")+selected,func():run(d,("release " if isolated else "isolate ")+selected))
	action.disabled = not current.management_connected
	button(d,controls,copy("edr_collect"),"EdrCollect",func():run(d,"collect"))
	_normal_use(d, body, state, snap, selected)
	tabline(d,body,copy("edr_timeline"),"EdrTab_timeline")
	var toolbar := HBoxContainer.new();body.add_child(toolbar)
	var search := LineEdit.new();search.name="EdrSearch";search.placeholder_text=copy("edr_search");search.text=str(state.get("query",""));search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(search)
	fluent_control(d,search)
	var filter := OptionButton.new();filter.name="EdrTypeFilter";toolbar.add_child(filter)
	fluent_control(d,filter)
	var types := ["all","outbound","file_read","dns"]
	for key in ["experience_all_events","experience_network_events","experience_file_events","experience_dns_events"]:filter.add_item(copy(key))
	filter.select(maxi(0,types.find(str(state.get("event_type","all")))))
	var timeline := VBoxContainer.new();timeline.name="EdrTimelineRows";timeline.add_theme_constant_override("separation",12);body.add_child(timeline)
	search.text_changed.connect(func(value):state["query"]=value;timeline_rows(d,timeline,current,state))
	filter.item_selected.connect(func(index):state["event_type"]=types[index];timeline_rows(d,timeline,current,state))
	timeline_rows(d,timeline,current,state)

static func timeline_rows(d, parent: VBoxContainer, current: Dictionary, state: Dictionary, recovery_snap: Dictionary = {}) -> void:
	d._clear(parent)
	var events: Array=current.get("events",[])
	var query:=str(state.get("query","")).to_lower()
	var event_type:=str(state.get("event_type","all"))
	var indices: Array[int]=[]
	for index in events.size():
		if event_type!="all" and str(events[index].type)!=event_type:continue
		if query.is_empty() or JSON.stringify(events[index]).to_lower().contains(query):indices.append(index)
	if indices.is_empty():label(d,parent,copy("edr_no_results"),14,MUTED);return
	var selected:=int(state.get("event_index",0))
	if selected not in indices:selected=indices[0]
	state["event_index"]=selected
	var compact := float(d.windows.browser.size.x)<1280*scale(d)
	var split:=BoxContainer.new();split.name="EdrEventSplit"
	split.vertical=compact
	split.add_theme_constant_override("separation",16);parent.add_child(split)
	var update_direction:=func():split.vertical=float(d.windows.browser.size.x)<1280*scale(d)
	split.resized.connect(update_direction)
	update_direction.call()
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",1);split.add_child(list)
	var head:=table_row(list,Color("faf9f8"))
	for pair in [["edr_time",52*scale(d)],["edr_event",92*scale(d)],["edr_process",0]]:
		var title:=label(d,head,copy(pair[0]),12,MUTED)
		title.custom_minimum_size.x=pair[1]
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL if int(pair[1])==0 else Control.SIZE_FILL
	for index in indices:
		var event: Dictionary=events[index]
		var row:=button(d,list,"","EdrEvent_"+str(index),func():
			state["event_index"]=index
			state["details_open"]=true
			timeline_rows(d,parent,current,state,recovery_snap)
			_scroll_selected_event_details(d,parent))
		row.custom_minimum_size.y=50*scale(d);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var selected_style:=UI.style(Color("deecf9") if selected==index else Color.WHITE,LINE,10,6,0);selected_style.set_border_width_all(0);selected_style.border_width_bottom=1
		row.add_theme_stylebox_override("normal",selected_style)
		row.add_theme_stylebox_override("hover",UI.style(Color("f3f2f1"),Color.TRANSPARENT,10,6,0))
		var cells:=HBoxContainer.new();cells.mouse_filter=Control.MOUSE_FILTER_IGNORE;cells.add_theme_constant_override("separation",14)
		row.add_child(cells);cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);cells.offset_left=10;cells.offset_right=-10
		var time:=label(d,cells,str(event.time),12,MUTED);time.custom_minimum_size.x=52*scale(d);time.size_flags_horizontal=Control.SIZE_FILL;time.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var type_cell:=label(d,cells,str(event.type),12);type_cell.mouse_filter=Control.MOUSE_FILTER_IGNORE;type_cell.custom_minimum_size.x=92*scale(d);type_cell.size_flags_horizontal=Control.SIZE_FILL
		var values:=VBoxContainer.new();values.mouse_filter=Control.MOUSE_FILTER_IGNORE;values.size_flags_horizontal=Control.SIZE_EXPAND_FILL;values.size_flags_vertical=Control.SIZE_SHRINK_CENTER;cells.add_child(values)
		for value in [str(event.process),str(event.remote_address)]:
			var text:=label(d,values,value,13,INK if value==str(event.process) else MUTED)
			text.autowrap_mode=TextServer.AUTOWRAP_OFF;text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if not bool(state.get("details_open",true)):return
	var details:=frame(split)
	var details_frame: Control=details.get_parent()
	details_frame.name="EdrDetailsPane"
	var update_details_layout:=func():
		var stacked:=float(d.windows.browser.size.x)<1280*scale(d)
		details_frame.custom_minimum_size=Vector2(0,0) if stacked else Vector2(370,0)
		details_frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL if stacked else Control.SIZE_FILL
	details_frame.resized.connect(update_details_layout)
	split.resized.connect(update_details_layout)
	update_details_layout.call()
	var detail_style:=UI.style(Color.WHITE,Color("d2d0ce"),16,14,0)
	detail_style.set_border_width_all(0);detail_style.border_width_left=1;detail_style.shadow_color=Color(0,0,0,0.06);detail_style.shadow_size=4
	details.get_parent().add_theme_stylebox_override("panel",detail_style)
	var detail_title:=HBoxContainer.new();detail_title.name="EdrDetailsHeading";details.add_child(detail_title)
	label(d,detail_title,copy("experience_event_details"),18)
	var close:=button(d,detail_title,"×","EdrCloseDetails",func():state["details_open"]=false;timeline_rows(d,parent,current,state,recovery_snap))
	close.tooltip_text=copy("portal_close");close.add_theme_stylebox_override("normal",UI.style(Color.WHITE,Color.TRANSPARENT,8,3,0))
	var event:Dictionary=events[selected]
	var fields:=VBoxContainer.new();fields.name="EdrEventDetails";fields.add_theme_constant_override("separation",10);details.add_child(fields)
	for pair in [["edr_time","time"],["edr_event","type"],["edr_process","process"],["edr_publisher","publisher"],["edr_destination","remote_address"],["edr_details","detail"],["edr_change","change_ref"]]:
		var field:=VBoxContainer.new();field.add_theme_constant_override("separation",2);fields.add_child(field)
		label(d,field,copy(pair[0]),11,MUTED)
		var value:=str(event.get(pair[1],""))
		label(d,field,value if not value.is_empty() else "—",13).name="EdrField_"+str(pair[1])
	var event_file_id:=str(event.get("file_id",""))
	if not recovery_snap.is_empty() and not event_file_id.is_empty():
		var event_file:=recovery_file(recovery_snap,event_file_id)
		if not event_file.is_empty():
			button(d,fields,str(event_file.get("name",event_file_id)),"RecoveryEventFile_"+event_file_id,func():state["file_id"]=event_file_id;state["recovery_tab"]="files";d._render_endpoint())
	entity_graph(d,details,current,event)

static func _scroll_selected_event_details(d, timeline_parent: Control) -> void:
	if float(d.windows.browser.size.x)>=1280*scale(d):return
	if not d.widgets.has("browser") or not is_instance_valid(d.widgets.browser.page):return
	var page: VBoxContainer=d.widgets.browser.page
	var scroll: ScrollContainer=page.get_parent() as ScrollContainer
	var heading: Control=timeline_parent.find_child("EdrDetailsHeading",true,false) as Control
	if scroll==null or heading==null:return
	var tree: SceneTree=d.get_tree()
	var heading_ref: WeakRef = weakref(heading)
	var scroll_ref: WeakRef = weakref(scroll)
	tree.process_frame.connect(func():
		tree.process_frame.connect(func():
			var current_scroll = scroll_ref.get_ref()
			var current_heading = heading_ref.get_ref()
			if is_instance_valid(current_scroll) and is_instance_valid(current_heading):
				current_scroll.scroll_vertical += roundi(current_heading.global_position.y - current_scroll.global_position.y)
		,CONNECT_ONE_SHOT)
	,CONNECT_ONE_SHOT)

static func entity_graph(d, parent: VBoxContainer, device: Dictionary, event: Dictionary) -> void:
	label(d,parent,copy("experience_related_entities"),12,MUTED)
	var graph:=VBoxContainer.new();graph.name="EdrEntityGraph";graph.add_theme_constant_override("separation",0);parent.add_child(graph)
	var entities: Array = [["device",device_name(str(device.id)),copy("edr_isolated" if device.isolated else "edr_connected")],["process",str(event.process),str(event.publisher)],["network",str(event.remote_address),str(event.type)]]
	for index in entities.size():
		if index>0:
			var connector:=ColorRect.new();connector.color=Color("c8c6c4");connector.custom_minimum_size=Vector2(1,12);connector.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;graph.add_child(connector)
		var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",UI.style(Color("faf9f8"),LINE,10,6,0));graph.add_child(panel)
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);panel.add_child(row)
		Glyph.add_to(row,str(entities[index][0]),24,BLUE)
		var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
		label(d,text,str(entities[index][1]),13)
		label(d,text,str(entities[index][2]),11,MUTED)

static func actions(d, body: VBoxContainer, snap: Dictionary) -> void:
	label(d,body,copy("edr_actions"),24)
	tabline(d,body,copy("edr_actions"),"EdrActionsTab")
	var records: Array=snap.get("actions",[])
	if records.is_empty():label(d,body,copy("edr_no_results"),14,MUTED)
	var table:=VBoxContainer.new();table.add_theme_constant_override("separation",0);body.add_child(table)
	var heading:=table_row(table,Color("faf9f8"))
	for key in ["#",copy("edr_device"),copy("edr_actions")]:label(d,heading,key,12,MUTED)
	for item in records:
		var row:=table_row(table)
		label(d,row,str(item.sequence),13,MUTED)
		label(d,row,copy("edr_evidence") if str(item.device)=="evidence" else device_name(str(item.device)),13)
		label(d,row,copy("edr_"+str(item.action)),13)
	body.add_child(HSeparator.new())
	var evidence: Dictionary=snap.get("evidence",{})
	label(d,body,copy("edr_evidence"),18)
	var valid:=bool(evidence.get("valid",false));var collected:=bool(evidence.get("collected",false))
	label(d,body,copy("edr_integrity_ok" if valid else ("edr_integrity_bad" if collected else "edr_no_package")),14,UI.GREEN if valid else UI.WARNING)
	if collected:
		for pair in [["/var/log/evidence.log","source_sha256"],["/evidence/original.log","copy_sha256"]]:
			label(d,body,str(pair[0]),13)
			label(d,body,"SHA-256  "+str(evidence.get(pair[1],"")),12,MUTED)
