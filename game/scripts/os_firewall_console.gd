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
static func action(d,name: String,payload: Dictionary={}) -> Dictionary:
	var result: Dictionary=d._firewall_action(name,payload)
	d.get_node("/root/Soundscape").play_ui("work_success" if bool(result.get("ok",false)) else "work_failure")
	if bool(result.get("ok",false)):
		if name=="save_rule":d.firewall_ui.erase("editor")
		if name=="delete":d.firewall_ui.erase("delete_id")
		if name=="services":d.firewall_ui.erase("service_draft")
		if name=="revert":d.firewall_ui.erase("service_draft")
	render_again(d);return result
static func address(value: String) -> String:
	return copy("any") if value=="any" else copy("lan_net") if value=="lan_net" else copy("this_firewall") if value=="self" else value
static func protocol(value: String) -> String:return "*" if value=="any" else value.to_upper().replace("_","/")
static func port(value: String) -> String:return "*" if value=="any" else value
static func browser_width(d) -> float:
	if d.windows.has("browser") and is_instance_valid(d.windows.browser): return float(d.windows.browser.size.x)
	return 1280.0
static func compact_layout(d) -> bool:return false
static func dense_layout(d) -> bool:return browser_width(d)<1200.0
static func column_widths(d) -> Array:
	return [36.0,72.0,128.0,76.0,128.0,76.0,0.0,184.0]
static func chain_item(parent: Node,symbol: String,title: String,value: String,color: Color) -> void:
	var item:=VBoxContainer.new();item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;item.add_theme_constant_override("separation",2);parent.add_child(item)
	GLYPH.add_to(item,symbol,25,color)
	var title_label:=Label.new();title_label.text=title;title_label.add_theme_color_override("font_color",MUTED);title_label.add_theme_font_size_override("font_size",11);title_label.autowrap_mode=TextServer.AUTOWRAP_OFF;item.add_child(title_label)
	var value_label:=Label.new();value_label.text=value;value_label.add_theme_color_override("font_color",INK);value_label.add_theme_font_size_override("font_size",12);value_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;item.add_child(value_label)
static func chain_arrow(parent: Node) -> void:GLYPH.add_to(parent,"arrow",22,BLUE)
static func evidence_chain(d,parent: Node,trace: Dictionary) -> void:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",7);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(row)
	chain_item(row,"network",copy("source_address"),str(trace.get("source",""))+":"+str(trace.get("source_port","")),BLUE);chain_arrow(row)
	chain_item(row,"device",copy("interface"),str(trace.get("interface","lan")).to_upper(),BLUE);chain_arrow(row)
	var rule_id:=str(trace.get("rule_id","default"));var rule_text:=copy("default_deny") if rule_id=="default" else rule_id
	chain_item(row,"process",copy("matched_rule"),rule_text+" / "+copy(str(trace.get("action","block"))),GREEN if str(trace.get("action",""))=="pass" else RED);chain_arrow(row)
	chain_item(row,"device",copy("destination_address"),str(trace.get("destination",""))+":"+str(trace.get("destination_port","")),BLUE)

static func render(d,parent: VBoxContainer) -> void:
	var state: Dictionary=d.firewall_ui;var snap: Dictionary=d.game._vm().firewall_snapshot()
	var background:=panel(parent,Color("f4f4f4"));background.add_theme_constant_override("separation",7);background.custom_minimum_size.y=maxf(480,float(d.windows.browser.size.y)-110)
	var header:=panel(background,Color("222222"));var brand:=HBoxContainer.new();brand.add_theme_constant_override("separation",22);header.add_child(brand)
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
	if not result.is_empty() and not bool(result.get("ok",false)):
		var key:="error_"+str(result.get("error","operation_failed"));var message:=UI.copy("stock_error_hardware") if str(result.get("error",""))=="hardware_unavailable" else copy(key)
		label(d,background,message if not message.is_empty() else copy("error_operation_failed"),14,RED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",0);background.add_child(body)
	match str(state.get("view","rules")):
		"services":services(d,body,snap,state)
		"diagnostics":diagnostics(d,body,snap,state)
		"logs":logs(d,body,snap)
		_:rules(d,body,snap,state)

static func rules(d,parent: VBoxContainer,snap: Dictionary,state: Dictionary) -> void:
	if state.has("editor"):editor(d,parent,state);return
	var tabs:=flow(parent);var iface:=str(state.get("interface","wan"));tabs.custom_minimum_size.y=58
	for name in ["wan","lan"]:
		var tab:=button(d,tabs,name.to_upper(),"FirewallTab_"+name,func():state["interface"]=name;render_again(d),RED)
		var style:=UI.style(Color.TRANSPARENT,RED,18,12,0);style.set_border_width_all(0);style.border_width_bottom=4 if iface==name else 0;tab.add_theme_stylebox_override("normal",style)
	var bar:=panel(parent,Color("414141"));bar.add_theme_constant_override("separation",0);label(d,bar,copy("rules"),15,Color.WHITE)
	var scroll:=ScrollContainer.new();scroll.name="FirewallRuleTable";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;parent.add_child(scroll)
	var table:=VBoxContainer.new();table.size_flags_horizontal=Control.SIZE_EXPAND_FILL;table.add_theme_constant_override("separation",0);scroll.add_child(table)
	var widths:=column_widths(d)
	var head:=HBoxContainer.new();head.add_theme_constant_override("separation",8);head.custom_minimum_size.y=34;table.add_child(head)
	for index in 8:
		var key: String=["action","protocol","source","source_port","destination","destination_port","description",""][index]
		var cell:=label(d,head,"" if index in [0,7] else copy(key),12,INK);cell.custom_minimum_size.x=float(widths[index]);cell.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL if index==6 else Control.SIZE_FILL
	var shown:=0
	for raw in snap.get("rules",[]):
		if str(raw.get("interface",""))!=iface:continue
		shown+=1;rule_row(d,table,raw,false,state,widths)
	if shown==0:label(d,table,copy("no_rules"),14,MUTED)
	var addbar:=HBoxContainer.new();addbar.add_theme_constant_override("separation",8);addbar.size_flags_horizontal=Control.SIZE_SHRINK_END;parent.add_child(addbar)
	for entry in [["add_top","FirewallAddTop","top","↑"],["add_bottom","FirewallAddBottom","bottom","↓"]]:
		var add:=button(d,addbar,str(entry[3])+"  "+copy(str(entry[0])),str(entry[1]),func():open_editor(d,{},str(entry[2]),iface),Color.WHITE);add.add_theme_stylebox_override("normal",UI.style(Color("4cae4c"),Color.TRANSPARENT,8,4,2))
	if not str(state.get("delete_id","")).is_empty():
		var confirm:=panel(parent,Color("fff4f4"));label(d,confirm,copy("delete_confirm"),14,RED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var buttons:=flow(confirm);button(d,buttons,copy("delete"),"FirewallDeleteConfirm",func():action(d,"delete",{"id":str(state.get("delete_id",""))}),RED)
		button(d,buttons,copy("cancel"),"FirewallDeleteCancel",func():state.erase("delete_id");render_again(d),MUTED)

static func rule_row(d,parent: VBoxContainer,rule: Dictionary,_compact: bool,state: Dictionary,widths: Array) -> void:
	var id:=str(rule.id);var wrapper:=PanelContainer.new();wrapper.name="FirewallRule_"+id;wrapper.add_theme_stylebox_override("panel",UI.style(Color("f8f8f8"),LINE,0,1,0));parent.add_child(wrapper)
	var row:=HBoxContainer.new();row.custom_minimum_size.y=38;row.add_theme_constant_override("separation",8);wrapper.add_child(row)
	var color:=MUTED if bool(rule.disabled) else GREEN if str(rule.action)=="pass" else RED
	var cells: Array=["✓" if str(rule.action)=="pass" else "×" if str(rule.action)=="block" else "−",protocol(str(rule.protocol)),address(str(rule.source)),port(str(rule.source_port)),address(str(rule.destination)),port(str(rule.destination_port)),str(rule.description)]
	for index in cells.size():
		var cell:=label(d,row,str(cells[index]),13,color if index==0 else MUTED if bool(rule.disabled) else INK)
		cell.custom_minimum_size.x=float(widths[index]);cell.clip_text=index==6;cell.tooltip_text=copy(str(rule.action)) if index==0 else str(cells[index]);cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL if index==6 else Control.SIZE_FILL
		if index==6:cell.custom_minimum_size.x=120
		if index==0:cell.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;cell.add_theme_font_size_override("font_size",19)
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",0);actions.custom_minimum_size.x=float(widths[7]);row.add_child(actions)
	for item in [["✎","Edit","edit"],["⧉","Clone","clone"],["○" if bool(rule.disabled) else "⊘","Toggle","enable" if bool(rule.disabled) else "disable"],["×","Delete","delete"],["↑","Up","move_up"],["↓","Down","move_down"]]:
		var kind:=str(item[1]);var control:=button(d,actions,str(item[0]),"Firewall"+kind+"_"+id,func():
			if kind=="Edit":open_editor(d,rule,"",str(rule.interface))
			elif kind=="Delete":state["delete_id"]=id;render_again(d)
			elif kind in ["Up","Down"]:action(d,"move",{"id":id,"direction":kind.to_lower()})
			else:action(d,kind.to_lower(),{"id":id})
		);control.tooltip_text=copy(str(item[2]));control.custom_minimum_size.x=30;control.add_theme_font_size_override("font_size",18)

static func open_editor(d,rule: Dictionary,insert: String,iface: String) -> void:
	var draft: Dictionary=rule.duplicate(true) if not rule.is_empty() else {"interface":iface,"action":"pass","protocol":"tcp","source":"any","source_port":"any","destination":"any","destination_port":"any","disabled":false,"log":true,"description":""}
	d.firewall_ui["editor"]={"rule":draft,"insert":insert};render_again(d)
static func form_row(d,parent: Node,key: String) -> HBoxContainer:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);parent.add_child(row);label(d,row,copy(key),13).custom_minimum_size.x=180;return row
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
	var table:=panel(parent,Color("f7f7f7"));var widths: Array=[62,180,180,70,80,180];var head:=HBoxContainer.new();table.add_child(head)
	for index in 5:
		var entry: String = ["interface","source","destination","protocol","action"][index]
		var cell:=label(d,head,copy(str(entry)),12,MUTED);cell.custom_minimum_size.x=float(widths[index]);cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL if index==4 else Control.SIZE_FILL
	var rule_head:=label(d,head,copy("matched_rule"),12,MUTED);rule_head.custom_minimum_size.x=float(widths[5]);
	for item in rows:
		if not item is Dictionary:continue
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",6);table.add_child(row)
		var values: Array=[str(item.get("interface","" )).to_upper(),str(item.get("source",""))+":"+str(item.get("source_port","")),str(item.get("destination",""))+":"+str(item.get("destination_port","")),protocol(str(item.get("protocol","any"))),copy(str(item.get("action","block"))),str(item.get("rule_id","default"))]
		for index in values.size():
			var value_label:=label(d,row,str(values[index]),12,GREEN if index==4 and str(item.get("action",""))=="pass" else RED if index==4 else INK);value_label.custom_minimum_size.x=float(widths[index]);value_label.clip_text=true;value_label.tooltip_text=str(values[index]);value_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL if index==5 else Control.SIZE_FILL
	var details: VBoxContainer=d._disclosure(parent,copy("result"));var text:=TextEdit.new();text.editable=false;text.custom_minimum_size.y=170;var lines:=PackedStringArray()
	for item in rows:lines.append(JSON.stringify(item) if item is Dictionary else str(item))
	text.text="\n".join(lines);details.add_child(text)
