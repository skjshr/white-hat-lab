extends RefCounted
const UI=preload("res://scripts/ui_theme.gd")
const GLYPH=preload("res://scripts/service_glyph.gd")
const INK:=Color("252525")
const MUTED:=Color("666666")
const RED:=Color("b8232b")
const BLUE:=Color("337ab7")
const GREEN:=Color("398439")
const LINE:=Color("dddddd")

static func copy(key: String) -> String:return UI.copy("fw_"+key)
static func persist(d) -> void:d._save_session(false)
static func render_again(d) -> void:persist(d);d._render_firewall()
static func label(d,parent: Node,text: String,size:=14,color:=INK) -> Label:
	var node: Label=d._label(text,size,color);node.add_theme_font_override("font",UI.font(500 if size>=18 else 400));node.autowrap_mode=TextServer.AUTOWRAP_OFF;parent.add_child(node);return node
static func button(d,parent: Node,text: String,id: String,callback: Callable,color: Color=BLUE) -> Button:
	var node: Button=d._button(text,callback);node.name=id;node.custom_minimum_size.y=27
	for kind in ["normal","hover","pressed","focus"]:
		node.add_theme_stylebox_override(kind,UI.style(Color("eeeeee") if kind in ["hover","pressed"] else Color.TRANSPARENT,BLUE if kind=="focus" else Color.TRANSPARENT,3,3,1))
	for kind in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:node.add_theme_color_override(kind,color)
	parent.add_child(node);return node
static func flow(parent: Node) -> HFlowContainer:
	var node:=HFlowContainer.new();node.add_theme_constant_override("h_separation",4);node.add_theme_constant_override("v_separation",4);parent.add_child(node);return node
static func panel(parent: Node,color: Color=Color.WHITE) -> VBoxContainer:
	var frame:=PanelContainer.new();frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frame.add_theme_stylebox_override("panel",UI.style(color,LINE,4,6,0));parent.add_child(frame)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",9);frame.add_child(box);return box
static func option(parent: Node,id: String,items: Array,value: String,changed: Callable) -> OptionButton:
	var node:=OptionButton.new();node.name=id;node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for item in items:
		node.add_item(str(item[1]));node.set_item_metadata(node.item_count-1,str(item[0]))
		if str(item[0])==value:node.select(node.item_count-1)
	node.item_selected.connect(func(index):changed.call(str(node.get_item_metadata(index))));parent.add_child(node);return node
static func input(parent: Node,id: String,value: String,changed: Callable) -> LineEdit:
	var node:=LineEdit.new();node.name=id;node.text=value;node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;node.text_changed.connect(changed);parent.add_child(node);return node
static func action_error_message(result: Dictionary) -> String:
	var error_code:=str(result.get("error","operation_failed"))
	var message:=UI.copy("stock_error_hardware") if error_code=="hardware_unavailable" else copy("error_"+error_code)
	return message if not message.is_empty() else copy("error_operation_failed")
static func action(d,name: String,payload: Dictionary={}) -> Dictionary:
	# The game emits `changed` synchronously during a saved VM action. Hold the
	# desktop refresh until its transactional outcome is known so a failed save
	# does not rebuild the editor before its inline error can be shown.
	var was_refreshing: bool=bool(d.refreshing)
	var request_focus := ""
	var old_page: Control=d.widgets.browser.get("page") if d.widgets.has("browser") else null
	var owner: Control=d.get_viewport().gui_get_focus_owner()
	if d.current_app=="browser" and is_instance_valid(old_page) and is_instance_valid(owner) and old_page.is_ancestor_of(owner) and old_page.find_child("NetworkRequestReturn",true,false)!=null:
		request_focus=str(owner.name)
	if not was_refreshing:d.refreshing=true
	var result: Dictionary=d._firewall_action(name,payload)
	if not was_refreshing:d.refreshing=false
	d.get_node("/root/Soundscape").play_ui("work_success" if bool(result.get("ok",false)) else "work_failure")
	if bool(result.get("ok",false)):
		if name=="trace":d.firewall_ui["trace_policy"]=_trace_signature(d)
		if name=="save_rule":d.firewall_ui.erase("editor")
		if name=="delete":d.firewall_ui.erase("delete_id")
		if name=="services":d.firewall_ui.erase("service_draft")
		if name=="revert":d.firewall_ui.erase("service_draft")
		if not was_refreshing:
			d.firewall_render_signature=d._firewall_snapshot_signature()
			d._state_changed()
		render_again(d)
		if not request_focus.is_empty():
			# The successful action replaces the focused button. Restore its new
			# instance, or the request return node when Apply has disappeared.
			(func():
				if not is_instance_valid(d) or d.current_app!="browser" or not d._firewall_console_url(d.browser_url): return
				var page: Control=d.widgets.browser.get("page") if d.widgets.has("browser") else null
				if not is_instance_valid(page): return
				var back: Control=page.find_child("NetworkRequestReturn",true,false)
				if not is_instance_valid(back) or not back.is_visible_in_tree(): return
				var replacement: Control=page.find_child(request_focus,true,false)
				if not is_instance_valid(replacement) or not replacement.is_visible_in_tree(): replacement=back
				replacement.grab_focus()
			).call_deferred()
	else:
		# Keep the current editor controls (and focus) intact; only update the
		# reserved result area so a failed operation is visible before retrying.
		var page: Control=d.widgets.browser.get("page") if d.widgets.has("browser") else null
		var feedback: Label=page.find_child("FirewallActionResult",true,false) as Label if is_instance_valid(page) else null
		if is_instance_valid(feedback):
			feedback.text=action_error_message(result)
			feedback.visible=true
			var scroll: Node=page
			while is_instance_valid(scroll) and not scroll is ScrollContainer:scroll=scroll.get_parent()
			if scroll is ScrollContainer:(scroll as ScrollContainer).ensure_control_visible(feedback)
	return result
static func address(value: String) -> String:
	return copy("any") if value=="any" else copy("lan_net") if value=="lan_net" else copy("this_firewall") if value=="self" else value
static func protocol(value: String) -> String:return "*" if value=="any" else value.to_upper().replace("_","/")
static func port(value: String) -> String:return "*" if value=="any" else value
static func browser_width(d) -> float:
	if d.windows.has("browser") and is_instance_valid(d.windows.browser): return float(d.windows.browser.size.x)
	return 1280.0
static func compact_layout(d) -> bool:return browser_width(d)/maxf(1.0,float(d.game.settings.get("text_scale",1.0)))<1100.0
static func dense_layout(d) -> bool:return browser_width(d)<1200.0
static func column_widths(d) -> Array:
	# Keep the native rule-list columns intact. The viewport scrolls on narrow
	# windows instead of squeezing ports, descriptions and row actions together.
	return [40.0,88.0,156.0,96.0,156.0,96.0,220.0,220.0]
static func rule_table_width(widths: Array) -> float:
	var width:=0.0
	for value in widths:width+=float(value)
	return width+56.0
static func _trace_signature(d) -> String:
	var live: Dictionary=d.game._vm().state
	return JSON.stringify({"active":live.get("active",false),"applied":live.get("applied",{})})
static func chain_item(parent: Node,symbol: String,title: String,value: String,color: Color,scale:=1.0) -> void:
	var item:=VBoxContainer.new();item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;item.add_theme_constant_override("separation",2);parent.add_child(item)
	GLYPH.add_to(item,symbol,25,color)
	var title_label:=Label.new();title_label.text=title;title_label.add_theme_color_override("font_color",MUTED);title_label.add_theme_font_size_override("font_size",int(11*scale));title_label.autowrap_mode=TextServer.AUTOWRAP_OFF;item.add_child(title_label)
	var value_label:=Label.new();value_label.text=value;value_label.add_theme_color_override("font_color",INK);value_label.add_theme_font_size_override("font_size",int(12*scale));value_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;item.add_child(value_label)
static func chain_arrow(parent: Node) -> void:GLYPH.add_to(parent,"arrow",22,BLUE)
static func evidence_chain(d,parent: Node,trace: Dictionary) -> void:
	var scale:=float(d.game.settings.get("text_scale",1.0))
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",7);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(row)
	chain_item(row,"network",copy("source_address"),str(trace.get("source",""))+":"+str(trace.get("source_port","")),BLUE,scale);chain_arrow(row)
	chain_item(row,"device",copy("interface"),str(trace.get("interface","lan")).to_upper(),BLUE,scale);chain_arrow(row)
	var rule_id:=str(trace.get("rule_id","default"));var rule_text:=copy("default_deny") if rule_id=="default" else rule_id
	chain_item(row,"process",copy("matched_rule"),rule_text+" / "+copy(str(trace.get("action","block"))),GREEN if str(trace.get("action",""))=="pass" else RED,scale);chain_arrow(row)
	chain_item(row,"device",copy("destination_address"),str(trace.get("destination",""))+":"+str(trace.get("destination_port","")),BLUE,scale)

static func render(d,parent: VBoxContainer) -> void:
	var state: Dictionary=d.firewall_ui;var snap: Dictionary=d.game._vm().firewall_snapshot()
	var background:=panel(parent,Color("f4f4f4"));background.add_theme_constant_override("separation",7)
	var return_url := str(d.business_ui.get("network_return_url",""))
	if not return_url.is_empty(): preload("res://scripts/network_request_panel.gd").render(d,background,return_url,true)
	var viewport := parent.get_parent() as Control
	var reflow := func(): background.custom_minimum_size.y = maxf(0, viewport.size.y - 12)
	viewport.resized.connect(reflow)
	background.tree_exiting.connect(func():
		if viewport.resized.is_connected(reflow): viewport.resized.disconnect(reflow)
	)
	reflow.call_deferred()
	var header:=panel(background,Color("222222"));var brand:=HFlowContainer.new();brand.add_theme_constant_override("h_separation",22);brand.add_theme_constant_override("v_separation",4);header.add_child(brand)
	GLYPH.add_to(brand,"network",28,Color.WHITE);label(d,brand,"pfSense",22,Color.WHITE)
	for item in [["rules","rules"],["services","service_config"],["diagnostics","diagnostics"],["logs","logs"]]:
		var view:=str(item[0]);var nav:=button(d,brand,copy(str(item[1])),"FirewallNav_"+view,func():state["view"]=view;render_again(d),Color.WHITE);nav.add_theme_stylebox_override("normal",UI.style(Color("080808") if str(state.get("view","rules"))==view else Color.TRANSPARENT,Color.TRANSPARENT,12,8,0))
	var title:=panel(background,Color.WHITE);title.add_theme_constant_override("separation",2);label(d,title,copy("title")+" / "+copy({"rules":"rules","services":"service_config","diagnostics":"diagnostics","logs":"logs"}.get(str(state.get("view","rules")),"rules")),19,Color("555555"))
	var hardware: Dictionary=d.game._customer_hardware()
	if not hardware.is_empty():label(d,title,str(hardware.model)+" · "+str(hardware.serial),13,MUTED).name="FirewallHardwareSerial"
	if not d.game._customer_hardware_connected():
		label(d,background,UI.copy("stock_error_hardware"),14,RED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		return
	if not bool(snap.get("active",true)):label(d,background,copy("service_unavailable"),14,RED)
	if not str(snap.get("error","")).is_empty():
		label(d,background,copy("error_invalid_config"),14,RED)
		button(d,background,copy("edit"),"FirewallConfigRepair",func():d._show_app("editor");d._open_editor(str(d.game.vm_info().config_path)))
	var pending:=bool(snap.get("pending",false));var changebar:=flow(background);changebar.visible=pending or not bool(snap.get("active",true))
	label(d,changebar,copy("pending"),14,RED)
	var apply:=button(d,changebar,copy("apply"),"FirewallApply",func():action(d,"apply"),Color.WHITE);apply.add_theme_stylebox_override("normal",UI.style(GREEN,Color.TRANSPARENT,12,6,3));apply.disabled=not pending and bool(snap.get("active",true))
	button(d,changebar,copy("revert"),"FirewallRevert",func():action(d,"revert"),MUTED).disabled=not pending
	var result: Dictionary=state.get("result",{})
	var feedback:=label(d,background,"",14,RED);feedback.name="FirewallActionResult"
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.visible=not result.is_empty() and not bool(result.get("ok",false))
	if feedback.visible:feedback.text=action_error_message(result)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",0);background.add_child(body)
	match str(state.get("view","rules")):
		"services":services(d,body,snap,state)
		"diagnostics":diagnostics(d,body,snap,state)
		"logs":logs(d,body,snap)
		_:rules(d,body,snap,state)

static func rules(d,parent: VBoxContainer,snap: Dictionary,state: Dictionary) -> void:
	if state.has("editor"):editor(d,parent,state);return
	_trace_context(d,parent,snap,state)
	var tabs:=flow(parent);var iface:=str(state.get("interface","wan"));tabs.custom_minimum_size.y=58
	for name in ["wan","lan"]:
		var tab:=button(d,tabs,name.to_upper(),"FirewallTab_"+name,func():state["interface"]=name;render_again(d),RED)
		var style:=UI.style(Color.TRANSPARENT,RED,18,12,0);style.set_border_width_all(0);style.border_width_bottom=4 if iface==name else 0;tab.add_theme_stylebox_override("normal",style)
	var bar:=panel(parent,Color("414141"));bar.add_theme_constant_override("separation",0);label(d,bar,copy("rules"),15,Color.WHITE)
	var compact:=compact_layout(d)
	var scroll:=ScrollContainer.new();scroll.name="FirewallRuleTable";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED if compact else ScrollContainer.SCROLL_MODE_AUTO;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;parent.add_child(scroll)
	var widths:=column_widths(d)
	var table_width:=0.0 if compact else rule_table_width(widths)
	var table:=VBoxContainer.new();table.name="FirewallRuleColumns";table.size_flags_horizontal=Control.SIZE_EXPAND_FILL;table.custom_minimum_size.x=table_width;table.add_theme_constant_override("separation",0);scroll.add_child(table)
	var head:=HBoxContainer.new();head.add_theme_constant_override("separation",8);head.custom_minimum_size=Vector2(table_width,34);table.add_child(head)
	head.visible=not compact
	for index in 8:
		var key: String=["action","protocol","source","source_port","destination","destination_port","description",""][index]
		var cell:=label(d,head,"" if index in [0,7] else copy(key),12,INK);cell.custom_minimum_size.x=float(widths[index]);cell.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL if index==6 else Control.SIZE_FILL
	var shown:=0
	for raw in snap.get("rules",[]):
		if str(raw.get("interface",""))!=iface:continue
		shown+=1
		var row_rule: Dictionary=raw.duplicate(true);row_rule["display_order"]=shown
		row_rule["last_match"]=str(snap.get("last_trace",{}).get("rule_id",""))==str(raw.get("id",""))
		rule_row(d,table,row_rule,compact,state,widths)
	if shown==0:label(d,table,copy("no_rules"),14,MUTED)
	var addbar:=HBoxContainer.new();addbar.add_theme_constant_override("separation",8);addbar.size_flags_horizontal=Control.SIZE_SHRINK_END;parent.add_child(addbar)
	for entry in [["add_top","FirewallAddTop","top","↑"],["add_bottom","FirewallAddBottom","bottom","↓"]]:
		var add:=button(d,addbar,str(entry[3])+"  "+copy(str(entry[0])),str(entry[1]),func():open_editor(d,{},str(entry[2]),iface),Color.WHITE);add.add_theme_stylebox_override("normal",UI.style(Color("4cae4c"),Color.TRANSPARENT,8,4,2))
	if not str(state.get("delete_id","")).is_empty():
		var confirm:=panel(parent,Color("fff4f4"));label(d,confirm,copy("delete_confirm"),14,RED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var buttons:=flow(confirm);button(d,buttons,copy("delete"),"FirewallDeleteConfirm",func():action(d,"delete",{"id":str(state.get("delete_id",""))}),RED)
		button(d,buttons,copy("cancel"),"FirewallDeleteCancel",func():state.erase("delete_id");render_again(d),MUTED)

static func rule_row(d,parent: VBoxContainer,rule: Dictionary,compact: bool,state: Dictionary,widths: Array) -> void:
	var id:=str(rule.id);var wrapper:=PanelContainer.new();wrapper.name="FirewallRule_"+id;wrapper.size_flags_horizontal=Control.SIZE_EXPAND_FILL;wrapper.custom_minimum_size.x=0 if compact else rule_table_width(widths);wrapper.add_theme_stylebox_override("panel",UI.style(Color("eef6fc") if bool(rule.get("last_match",false)) else Color("f8f8f8"),BLUE if bool(rule.get("last_match",false)) else LINE,10 if compact else 0,8 if compact else 1,2));parent.add_child(wrapper)
	var row:=BoxContainer.new();row.vertical=compact;row.custom_minimum_size=Vector2(0 if compact else rule_table_width(widths),38);row.add_theme_constant_override("separation",8);wrapper.add_child(row)
	var color:=MUTED if bool(rule.disabled) else GREEN if str(rule.action)=="pass" else RED
	if compact:
		var title:=label(d,row,str(rule.get("display_order",0))+". "+copy(str(rule.action))+"  "+str(rule.description)+("（無効）" if bool(rule.disabled) else ""),14,color);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var route:=label(d,row,address(str(rule.source))+":"+port(str(rule.source_port))+" → "+address(str(rule.destination))+":"+port(str(rule.destination_port))+"  "+protocol(str(rule.protocol)),13,INK);route.name="FirewallRoute_"+id;route.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var cells: Array=["✓" if str(rule.action)=="pass" else "×" if str(rule.action)=="block" else "−",protocol(str(rule.protocol)),address(str(rule.source)),port(str(rule.source_port)),address(str(rule.destination)),port(str(rule.destination_port)),str(rule.description)]
	for index in cells.size():
		if compact:break
		var cell:=label(d,row,str(cells[index]),13,color if index==0 else MUTED if bool(rule.disabled) else INK)
		cell.custom_minimum_size.x=float(widths[index]);cell.clip_text=index==6;cell.tooltip_text=copy(str(rule.action)) if index==0 else str(cells[index]);cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL if index==6 else Control.SIZE_FILL
		if index==6:cell.custom_minimum_size.x=120
		if index==0:cell.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;cell.add_theme_font_size_override("font_size",19)
	var actions:=HFlowContainer.new();actions.add_theme_constant_override("h_separation",4);actions.custom_minimum_size.x=0 if compact else float(widths[7]);row.add_child(actions)
	for item in [["✎","Edit","edit"],["⧉","Clone","clone"],["○" if bool(rule.disabled) else "⊘","Toggle","enable" if bool(rule.disabled) else "disable"],["×","Delete","delete"],["↑","Up","move_up"],["↓","Down","move_down"]]:
		var kind:=str(item[1]);var control:=button(d,actions,copy(str(item[2])) if compact else str(item[0]),"Firewall"+kind+"_"+id,func():
			if kind=="Edit":
				var editable:=rule.duplicate(true);editable.erase("display_order");editable.erase("last_match");open_editor(d,editable,"",str(rule.interface))
			elif kind=="Delete":state["delete_id"]=id;render_again(d)
			elif kind in ["Up","Down"]:action(d,"move",{"id":id,"direction":kind.to_lower()})
			else:action(d,kind.to_lower(),{"id":id})
		);control.tooltip_text=copy(str(item[2]));control.custom_minimum_size.x=30;control.add_theme_font_size_override("font_size",12 if compact else 18)

static func _trace_context(d,parent: VBoxContainer,snap: Dictionary,state: Dictionary) -> void:
	var body:=panel(parent,Color("f0f6fb"));body.name="FirewallRuleTrace"
	var controls:=flow(body)
	label(d,controls,"適用中のルールで通信を確認",14,INK)
	button(d,controls,"通信条件を編集","FirewallTraceEdit",func():state["view"]="diagnostics";render_again(d))
	var trace: Dictionary=snap.get("last_trace",{})
	button(d,controls,"同じ通信を再検査" if not trace.is_empty() else "LAN の通信を検査","FirewallTraceReplay",func():
		var payload: Dictionary={"interface":"lan","source":"192.168.10.10","destination":"192.0.2.20","protocol":"tcp","source_port":49152,"destination_port":443}
		if not trace.is_empty():
			for key in payload:payload[key]=trace.get(key,payload[key])
		action(d,"trace",payload)
	)
	if trace.is_empty():
		label(d,body,"LAN 192.168.10.10 → 192.0.2.20:443 / TCP",12,MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		return
	var fresh:=str(state.get("trace_policy",""))==_trace_signature(d)
	var caption:=label(d,body,("前回の実測" if fresh else "適用ルールが変わりました。再検査してください")+" / "+copy(str(trace.get("action","block"))),13,GREEN if str(trace.get("action",""))=="pass" else RED);caption.name="FirewallTraceContextStatus";caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	evidence_chain(d,body,trace)
	if bool(snap.get("pending",false)):label(d,body,"下の一覧には未適用の変更があります。通信検査は適用中のルールを使用します。",12,MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

static func open_editor(d,rule: Dictionary,insert: String,iface: String) -> void:
	var draft: Dictionary=rule.duplicate(true) if not rule.is_empty() else {"interface":iface,"action":"pass","protocol":"tcp","source":"any","source_port":"any","destination":"any","destination_port":"any","disabled":false,"log":true,"description":""}
	d.firewall_ui["editor"]={"rule":draft,"insert":insert};render_again(d)
static func form_row(d,parent: Node,key: String) -> BoxContainer:
	var row:=BoxContainer.new();row.add_theme_constant_override("separation",14);parent.add_child(row)
	var title:=label(d,row,copy(key),13);title.custom_minimum_size.x=180
	var reflow:=func():
		row.vertical=row.size.x<680.0*float(d.game.settings.get("text_scale",1.0))
		row.add_theme_constant_override("separation",4 if row.vertical else 14)
	row.resized.connect(reflow);reflow.call_deferred()
	return row
static func editor(d,parent: VBoxContainer,state: Dictionary) -> void:
	var form:=panel(parent);form.name="FirewallRuleEditor";label(d,form,copy("edit_rule"),19)
	var editor_state: Dictionary=state.editor;var draft: Dictionary=editor_state.rule
	for field in ["action","interface","protocol"]:
		var items: Array=[["pass",copy("pass")],["block",copy("block")],["reject",copy("reject")]] if field=="action" else [["wan","WAN"],["lan","LAN"]] if field=="interface" else [["any",copy("any")],["tcp","TCP"],["udp","UDP"],["tcp_udp","TCP/UDP"],["icmp","ICMP"]]
		option(form_row(d,form,field),"FirewallEditor_"+field,items,str(draft[field]),func(value):draft[field]=value;persist(d))
	for field in ["source","source_port","destination","destination_port","description"]:
		var field_input:=input(form_row(d,form,field),"FirewallEditor_"+field,str(draft[field]),func(value):draft[field]=value;persist(d))
		if field=="description":field_input.max_length=52
	for field in ["log","disabled"]:
		var toggle:=CheckBox.new();toggle.name="FirewallEditor_"+field;toggle.text=copy(field);toggle.button_pressed=bool(draft[field]);toggle.toggled.connect(func(value):draft[field]=value;persist(d));form.add_child(toggle)
	var actions:=flow(form)
	button(d,actions,copy("save"),"FirewallSave",func():action(d,"save_rule",{"rule":draft.duplicate(true),"insert":str(editor_state.insert)}),GREEN)
	button(d,actions,copy("cancel"),"FirewallCancel",func():state.erase("editor");render_again(d),MUTED)

static func services(d,parent: VBoxContainer,snap: Dictionary,state: Dictionary) -> void:
	var form:=panel(parent);label(d,form,copy("service_config"),19)
	if not state.has("service_draft"):state["service_draft"]={"dns":str(snap.get("dns","off")),"tls":str(snap.get("tls","off"))}
	var draft: Dictionary=state.service_draft
	for field in ["dns","tls"]:
		option(form_row(d,form,field),"Firewall"+field.to_upper(),[["off",copy("off")],["on",copy("on")]],str(draft[field]),func(value):draft[field]=value;persist(d))
	button(d,form,copy("save"),"FirewallServicesSave",func():action(d,"services",draft.duplicate(true)),GREEN)
	button(d,form,copy("cancel"),"FirewallServicesCancel",func():state.erase("service_draft");render_again(d),MUTED)

static func diagnostics(d,parent: VBoxContainer,snap: Dictionary,state: Dictionary) -> void:
	var form:=panel(parent);label(d,form,copy("diagnostics"),19)
	if not state.has("trace_draft"):state["trace_draft"]={"interface":"lan","source":"192.168.10.10","destination":"192.0.2.20","protocol":"tcp","source_port":"49152","destination_port":"443"}
	var draft: Dictionary=state.trace_draft
	option(form_row(d,form,"interface"),"FirewallTrace_interface",[["wan","WAN"],["lan","LAN"]],str(draft.interface),func(value):draft.interface=value;persist(d))
	option(form_row(d,form,"protocol"),"FirewallTrace_protocol",[["tcp","TCP"],["udp","UDP"],["icmp","ICMP"]],str(draft.protocol),func(value):draft.protocol=value;persist(d))
	for field in ["source","destination","source_port","destination_port"]:input(form_row(d,form,field),"FirewallTrace_"+field,str(draft[field]),func(value):draft[field]=value;persist(d))
	button(d,form,copy("run"),"FirewallTraceRun",func():
		var payload: Dictionary=draft.duplicate(true)
		for key in ["source_port","destination_port"]:payload[key]=str(payload[key]).to_int() if str(payload[key]).is_valid_int() else -1
		action(d,"trace",payload)
	)
	var trace: Dictionary=snap.get("last_trace",{})
	if not trace.is_empty():
		var result:=panel(parent);label(d,result,copy("result")+"  ·  "+copy(str(trace.get("action","block"))),16,GREEN if str(trace.get("action",""))=="pass" else RED)
		evidence_chain(d,result,trace)
		var details: VBoxContainer=d._disclosure(result,copy("result"));var text:=TextEdit.new();text.editable=false;text.text=JSON.stringify(trace,"  ");text.custom_minimum_size.y=150;details.add_child(text)

static func logs(d,parent: VBoxContainer,snap: Dictionary) -> void:
	label(d,parent,copy("logs"),19)
	var rows: Array=snap.get("logs",[])
	if rows.is_empty():label(d,parent,copy("no_logs"),14,MUTED);return
	var scroll:=ScrollContainer.new();scroll.name="FirewallLogTable";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(scroll)
	var table:=panel(scroll,Color("f7f7f7"));table.name="FirewallLogColumns"
	var widths: Array=[104,180,180,92,112,180]
	var content_width:=30.0
	for index in widths.size():
		widths[index]=float(widths[index])*float(d.game.settings.get("text_scale",1.0))
		content_width+=float(widths[index])
	table.get_parent().custom_minimum_size.x=content_width+8
	var head:=HBoxContainer.new();head.add_theme_constant_override("separation",6);table.add_child(head)
	for index in 5:
		var entry: String = ["interface","source","destination","protocol","action"][index]
		var cell:=label(d,head,copy(str(entry)),12,MUTED);cell.custom_minimum_size.x=float(widths[index]);cell.size_flags_horizontal=Control.SIZE_FILL
	var rule_head:=label(d,head,copy("matched_rule"),12,MUTED);rule_head.custom_minimum_size.x=float(widths[5]);rule_head.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for item in rows:
		if not item is Dictionary:continue
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",6);table.add_child(row)
		var values: Array=[str(item.get("interface","" )).to_upper(),str(item.get("source",""))+":"+str(item.get("source_port","")),str(item.get("destination",""))+":"+str(item.get("destination_port","")),protocol(str(item.get("protocol","any"))),copy(str(item.get("action","block"))),str(item.get("rule_id","default"))]
		for index in values.size():
			var value_label:=label(d,row,str(values[index]),12,GREEN if index==4 and str(item.get("action",""))=="pass" else RED if index==4 else INK);value_label.custom_minimum_size.x=float(widths[index]);value_label.clip_text=true;value_label.tooltip_text=str(values[index]);value_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL if index==5 else Control.SIZE_FILL
	var details: VBoxContainer=d._disclosure(parent,copy("result"));var text:=TextEdit.new();text.editable=false;text.custom_minimum_size.y=170;var lines:=PackedStringArray()
	for item in rows:lines.append(JSON.stringify(item) if item is Dictionary else str(item))
	text.text="\n".join(lines);details.add_child(text)
