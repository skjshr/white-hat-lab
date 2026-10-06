extends RefCounted
const U=preload("res://scripts/investigation_ui.gd")
const UI=preload("res://scripts/ui_theme.gd")
const Diagram=preload("res://scripts/pentest_engagement_canvas.gd")
const KIND:="advanced-pentest"
const INK=Color("eaf1f9")
const MUTED=Color("a6b7ca")
const BLUE=Color("76b5f5")

static func render(d,body:VBoxContainer,data:Dictionary) -> void:
	var s:=U.state(d,KIND);var n:Dictionary=data.get("network",{})
	U.navigation(d,KIND,[["explore","資源を探索"],["shipping","出荷端末"],["report","根拠と報告"],["changes","変更依頼"],["results","受入確認"]],"explore","NetworkTab_")
	for tab in d.widgets.advanced.nav.get_children():
		if tab is Button:_light(tab)
	match str(s.get("tab","explore")):
		"report":_report(d,body,data,n)
		"changes":_changes(d,body,n)
		"shipping":_shipping(d,body,n)
		"results":U.checks(body,data)
		_:_explore(d,body,data,n)

static func _rows(value:Variant) -> Array:
	if value is Array:return value
	if value is Dictionary:
		var result:Array=[]
		for id in value:
			if not value[id] is Dictionary:continue
			var row:Dictionary=value[id].duplicate(true)
			if not row.has("id"):row.id=str(id)
			result.append(row)
		return result
	return []

static func _records(data:Dictionary,n:Dictionary) -> Array:
	var combined:Dictionary={}
	for record in _rows(data.get("evidence",{}))+_rows(n.get("observations",data.get("observations",[]))):
		combined[str(record.get("id",""))]=record
	var result:Array=combined.values()
	result.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.get("sequence",0))<int(b.get("sequence",0)))
	return result

static func _record_host(record:Dictionary) -> String:
	return str(record.get("data",{}).get("host",record.get("host","")))

static func _record_path(record:Dictionary) -> String:
	return str(record.get("data",{}).get("path",record.get("target","")))

static func _principal(n:Dictionary) -> String:
	return str(n.get("principal",n.get("session",{}).get("principal","?")))

static func _source(n:Dictionary) -> String:
	return str(n.get("origin","?"))

static func _revision(n:Dictionary) -> int:
	return int(n.get("change_control",{}).get("revision",0))

static func _scoped(host:Dictionary) -> bool:
	return str(host.get("scope_state",""))=="in_scope"

static func _surface(parent:Node,dark:bool) -> VBoxContainer:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",UI.style(Diagram.NAVY if dark else Color("fbf7ef"),Color("2c425a") if dark else Color("d5c8b0"),12,10,2));parent.add_child(panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",9);panel.add_child(box);return box

static func _label(parent:Node,value:String,points:int=14,color:Color=INK) -> Label:
	return U.label(parent,value,points,color,not parent is HFlowContainer)

static func _button(parent:Node,value:String,id:String,action:Callable,dark:bool=true) -> Button:
	var button:=U.button(parent,value,id,action)
	if dark:
		for state in ["normal","hover","pressed","hover_pressed"]:button.add_theme_stylebox_override(state,UI.style(Color("1b3048"),Color("496785"),8,6,2))
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:button.add_theme_color_override(state,INK)
		button.add_theme_stylebox_override("focus",UI.style(Color.TRANSPARENT,INK,8,6,2))
	else:_light(button)
	return button

static func _light(button:Button) -> void:
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:button.add_theme_color_override(state,UI.INK)
	for state in ["pressed","hover","hover_pressed"]:button.add_theme_stylebox_override(state,UI.style(UI.SELECTED,UI.PRIMARY,8,6,2))
	button.add_theme_stylebox_override("hover_pressed",UI.style(UI.SELECTED,UI.PRIMARY,8,6,2))

static func _send(d,action:String,args:Dictionary={}) -> void:
	var s:=U.state(d,KIND);s.erase("relay_record")
	var result:=U.send(d,KIND,action,args)
	var record:Dictionary=result.get("data",{}).get("record",{})
	if not record.is_empty() and action in ["scan","browse","read","authenticate"]:
		s.relay_record=str(record.get("id",""));s.relay_host=_record_host(record)
		s.relay_path=_record_path(record) if action=="read" else ""
		d._save_session(false)

static func _choose_host(id:String,d) -> void:
	var s:=U.state(d,KIND);s.relay_host=id;s.erase("relay_path");s.erase("relay_record")
	d.widgets.advanced.next_scroll=0;d._save_session(false);d._refresh_advanced.call_deferred()

static func _choose_resource(d,host:String,path:String) -> void:
	var s:=U.state(d,KIND);s.relay_host=host;s.relay_path=path;s.erase("relay_record")
	d.widgets.advanced.next_scroll=0;d._save_session(false);d._refresh_advanced.call_deferred()

static func _explore(d,parent:Node,data:Dictionary,n:Dictionary) -> void:
	var body:=_surface(parent,true);var s:=U.state(d,KIND);var factor:=float(d.game.settings.get("text_scale",1.0))
	var context:=U.row(body)
	_label(context,"接続元  "+_source(n)+"  /  "+_principal(n),15)
	if bool(n.get("connection",{}).get("stale",false)):_label(context,"旧資格の接続",12,Color("edbc70"))
	_button(context,"社員へ戻る","NetworkResetSession",_send.bind(d,"reset_session"))
	_button(context,"鍵で接続","NetworkShowAuth",U.choose.bind(d,KIND,"relay_auth",not bool(s.get("relay_auth",false))))
	_button(context,"パス指定","NetworkShowPath",U.choose.bind(d,KIND,"relay_show_path",not bool(s.get("relay_show_path",false))))
	var records:=_records(data,n);var hosts:=_rows(n.get("hosts",[])).duplicate(true);var selected:Dictionary={}
	for spec in n.get("scope",[]):
		if str(spec.get("scope_state",""))!="excluded":continue
		var already_present:=false
		for host in hosts:
			if str(host.get("id",""))==str(spec.get("id","")):already_present=true;break
		if not already_present:hosts.append(spec)
	var host_id:=str(s.get("relay_host",""));var path:=str(s.get("relay_path",""))
	for host in hosts:
		if str(host.get("id",""))==host_id:selected=host;break
	var keys:=_credentials(n)
	if not keys.is_empty():
		var tray:=U.row(body);_label(tray,"観測した鍵",12,Color("edbc70"))
		for key in keys:
			_button(tray,"◇ "+str(key.get("username",""))+(" / 旧世代" if bool(key.get("stale",false)) else ""),"NetworkKey_"+str(key.get("username","")),_choose_key.bind(d,key))
	if bool(s.get("relay_auth",false)):
		var auth:=U.row(body)
		_label(auth,"認証先",12,MUTED)
		var destination:=U.input(d,auth,KIND,"relay_auth_host","NetworkAuthHost","ホスト")
		var user:=U.input(d,auth,KIND,"relay_username","NetworkUsername","利用者")
		var secret:=U.input(d,auth,KIND,"relay_credential","NetworkCredential","観測した資格情報",true)
		_button(auth,"このホストへ接続","NetworkAuthenticate",func():_send(d,"authenticate",{"host":destination.text,"username":user.text,"credential":secret.text}))
	var wide:=float(d.windows.advanced.size.x)/factor>=1030
	var content:BoxContainer=HBoxContainer.new() if wide else VBoxContainer.new()
	content.add_theme_constant_override("separation",16);body.add_child(content)
	var chart:=VBoxContainer.new();chart.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var inspector:=VBoxContainer.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inspector.add_theme_constant_override("separation",8)
	if wide:
		chart.size_flags_stretch_ratio=1.7;inspector.size_flags_stretch_ratio=1.0;inspector.custom_minimum_size.x=320*factor
		content.add_child(chart);content.add_child(inspector)
	else:
		content.add_child(inspector);content.add_child(chart)
	if not selected.is_empty():
		var actions:=U.row(inspector)
		_label(actions,host_id,17)
		if not _scoped(selected):_label(actions,"⊘ 契約対象外",12,MUTED)
		var scan:=_button(actions,"サービスを調べる","NetworkScan",_send.bind(d,"scan",{"host":host_id}))
		var browse:=_button(actions,"資源の一覧","NetworkBrowse",_send.bind(d,"browse",{"host":host_id,"path":""}))
		scan.disabled=not _scoped(selected);browse.disabled=scan.disabled
		var items:=U.row(inspector)
		for resource in _rows(n.get("resources",[])):
			if str(resource.get("host",""))!=host_id or not bool(resource.get("discovered",false)):continue
			var resource_path:=str(resource.get("path",""))
			var code:=int(resource.get("status",0));var old:=int(resource.get("revision",-1))!=_revision(n)
			var mark:=" · 未読" if code==0 else (" · 過去 " if old else " · ")+("✓" if code==200 else "×")+str(code)
			var resource_button:=_button(items,"▤ "+str(resource.get("label",resource_path.get_file()))+mark,"NetworkResource_"+resource_path.validate_node_name(),_choose_resource.bind(d,host_id,resource_path))
			resource_button.set_meta("host",host_id);resource_button.set_meta("path",resource_path)
		if not path.is_empty():
			var resource_actions:=U.row(inspector);_label(resource_actions,path,12,MUTED)
			var read:=_button(resource_actions,"内容を読取","NetworkRead",_send.bind(d,"read",{"host":host_id,"path":path}));read.disabled=not _scoped(selected)
	else:_label(inspector,"筐体を選択",13,MUTED)
	if bool(s.get("relay_show_path",false)):
		var manual:=U.row(inspector)
		var input:=U.input(d,manual,KIND,"relay_path","NetworkPath","選択ホスト内のパス")
		var read_path:=_button(manual,"読取","NetworkReadPath",func():_send(d,"read",{"host":host_id,"path":input.text}))
		read_path.disabled=selected.is_empty() or not _scoped(selected)
	var shown:Array=[]
	for host in hosts:
		var item:Dictionary=host.duplicate(true);item.in_scope=_scoped(host)
		var measured:Dictionary={};var past_measurement:Dictionary={}
		for record in records:
			if str(record.get("operation",""))!="scan" or _record_host(record)!=str(host.get("id","")):continue
			past_measurement=record
			if int(record.get("data",{}).get("revision",-1))==_revision(n) and str(record.get("data",{}).get("origin",""))==_source(n) and str(record.get("data",{}).get("principal",""))==_principal(n):measured=record
		item["ports"]=[];item["code"]=0;item["observation"]="? 未調査";item["current"]=false;item["reachable"]=false
		var scan:Dictionary=measured if not measured.is_empty() else past_measurement
		if not scan.is_empty():
			item.current=not measured.is_empty();item.code=int(scan.get("status",0))
			item.ports=scan.get("data",{}).get("ports",[])
			item.reachable=bool(scan.get("data",{}).get("reachable",false))
			item.observation=("" if item.current else "過去 / 別接続 ")+("✓ 到達" if item.reachable else "× 到達不可")
			item.tooltip="%s / %s · 世代 %d" % [str(scan.get("data",{}).get("origin","")),str(scan.get("data",{}).get("principal","")),int(scan.get("data",{}).get("revision",0))]
		elif bool(host.get("observed",false)):
			item.ports=host.get("ports",[]);item.reachable=bool(host.get("reachable",false))
			item.current=int(host.get("revision",-1))==_revision(n) and str(host.get("origin",""))==_source(n) and str(host.get("principal",""))==_principal(n)
			item.observation=("" if item.current else "過去 / 別接続 ")+("✓ 到達" if item.reachable else "× 到達不可")
			item.tooltip="%s / %s · 世代 %d" % [str(host.get("origin","")),str(host.get("principal","")),int(host.get("revision",0))]
		shown.append(item)
	var diagram:=Diagram.new();chart.add_child(diagram);diagram.configure("network",{"hosts":shown,"origin":_source(n),"principal":_principal(n)},factor,host_id,_choose_host.bind(d))
	_label(chart,"? 未観測   ━ 同じ接続の実測   × 到達不可   ┄ 未確認・過去",11,MUTED)
	var response_parent:Node=inspector if wide else body
	var response:=_selected_record(records,host_id,path,str(s.get("relay_record","")))
	if not response.is_empty():
		var history:=U.row(response_parent)
		var related:Array=[]
		for record in records:
			if _record_host(record)==host_id and (path.is_empty() or _record_path(record)==path):related.append(record)
		var start:=maxi(0,related.size()-6)
		for index in range(start,related.size()):
			var record:Dictionary=related[index]
			_button(history,"%s · %d · %s" % [str(record.get("data",{}).get("principal","?")),int(record.get("status",0)),str(record.get("id",""))],"NetworkRecord_"+str(record.get("id","")),U.choose.bind(d,KIND,"relay_record",str(record.get("id",""))))
		_response(d,response_parent,response,data.get("evidence",{}),_revision(n))

static func _credentials(n:Dictionary) -> Array:
	var key:Dictionary=n.get("credential",{})
	if not bool(key.get("observed",false)):return []
	return [key]

static func _choose_key(d,key:Dictionary) -> void:
	var s:=U.state(d,KIND);s.relay_auth=true;s.relay_auth_host="relay01";s.relay_username=str(key.get("username",""));s.relay_credential=str(key.get("secret",""))
	d.widgets.advanced.next_scroll=0;d._save_session(false);d._refresh_advanced.call_deferred()
static func _selected_record(records:Array,host:String,path:String,id:String) -> Dictionary:
	var result:Dictionary={}
	for record in records:
		if not id.is_empty() and str(record.get("id",""))==id:return record
		if _record_host(record)!=host:continue
		if path.is_empty() or _record_path(record)==path:result=record
	return result

static func _response(d,parent:Node,record:Dictionary,evidence:Dictionary,revision:int) -> void:
	var meta:=U.row(parent);var status:=int(record.get("status",0))
	var past:=int(record.get("data",{}).get("revision",-1))!=revision
	_label(meta,("過去 " if past else "")+("✓ " if status==200 else "× ")+str(status),18,MUTED if past else Diagram.TEAL if status==200 else Diagram.RED)
	_label(meta,str(record.get("id",""))+" · "+str(record.get("data",{}).get("origin",""))+" / "+str(record.get("data",{}).get("principal",""))+" · 世代 "+str(int(record.get("data",{}).get("revision",0))),12,MUTED)
	var save:=_button(meta,"根拠に保存","NetworkPinResponse",_send.bind(d,"pin",{"target":str(record.get("id",""))}));save.disabled=evidence.has(str(record.get("id","")))
	_label(parent,str(record.get("operation","")).to_upper()+"  "+_record_host(record)+" / "+_record_path(record),12,INK).name="NetworkResponseTarget"
	if str(record.get("operation",""))=="scan":
		var ports:=U.row(parent)
		_label(ports,"✓ 到達" if bool(record.get("data",{}).get("reachable",false)) else "× 到達不可",13,MUTED if past else Diagram.TEAL if bool(record.get("data",{}).get("reachable",false)) else Diagram.RED)
		for port in record.get("data",{}).get("ports",[]):
			_label(ports,"%d/%s · %s · %s" % [int(port.get("port",0)),str(port.get("protocol","")),str(port.get("service","")),str(port.get("status",""))],12,MUTED)
	if record.get("data",{}).has("bytes"):
		var bytes:=TextEdit.new();bytes.name="NetworkBytes";bytes.editable=false;bytes.text=str(record.data.bytes);bytes.custom_minimum_size.y=104;bytes.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
		bytes.add_theme_color_override("font_readonly_color",INK);bytes.add_theme_stylebox_override("read_only",UI.style(Color("0b1522"),Color("39526c"),8,6,2));parent.add_child(bytes)

static func _report(d,parent:Node,data:Dictionary,n:Dictionary) -> void:
	var s:=U.state(d,KIND);var body:=_surface(parent,false)
	var evidence:Dictionary=data.get("evidence",{});var records:=_rows(evidence)
	records.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.get("sequence",0))<int(b.get("sequence",0)))
	var ids:Array=s.get("report_ids",[]);var opened:=str(s.get("relay_report_record",""))
	var heading:=U.row(body)
	_label(heading,"調査経路 / 原記録 %d件" % records.size(),18,UI.INK)
	_label(heading,"✓ 顧客確認済み" if bool(n.get("report",{}).get("accepted",false)) else "未提出",13,UI.GREEN if bool(n.get("report",{}).get("accepted",false)) else UI.MUTED)
	var actions:=U.row(body)
	_button(actions,"選択した原記録を提出 (%d)" % ids.size(),"NetworkSubmit",func():_send(d,"submit_finding",{"evidence_ids":s.get("report_ids",[])}),false)
	if bool(n.get("report",{}).get("accepted",false)):_button(actions,"変更依頼へ","NetworkOpenChanges",U.choose.bind(d,KIND,"tab","changes"),false)
	if evidence.has(opened):_report_original(d,body,evidence[opened])
	if records.is_empty():
		_label(body,"探索で取得した応答を根拠に保存してください。",14,UI.MUTED);return
	var objects:Array=[];var edges:Array=[]
	for index in records.size():
		var record:Dictionary=records[index];var record_data:Dictionary=record.get("data",{})
		var operation:=str(record.get("operation",""));var principal:=str(record_data.get("principal",""))
		var caption:="認証接続" if operation=="authenticate" else "社員 · 設定取得" if operation=="read" and principal=="employee01" and _record_path(record).ends_with(".env") else "サービス · データ取得" if operation=="read" and principal.begins_with("svc-") else "サービス測定" if operation=="scan" else operation.to_upper()
		objects.append({"id":str(record.get("id","")),"host":_record_host(record),"target":_record_path(record).get_file(),"principal":principal,"operation":operation,"caption":caption,"status":int(record.get("status",0)),"included":str(record.get("id","")) in ids})
		if index==0:continue
		var prior:Dictionary=records[index-1];var prior_data:Dictionary=prior.get("data",{})
		if int(prior.get("status",0))!=200 or int(record.get("status",0))!=200 or int(prior_data.get("revision",-1))!=int(record_data.get("revision",-2)):continue
		var env_to_auth:=str(prior.get("operation",""))=="read" and _record_path(prior).ends_with(".env") and operation=="authenticate" and _record_host(prior)==_record_host(record) and str(prior_data.get("origin",""))==str(record_data.get("from_origin","")) and int(prior_data.get("credential_epoch",-1))==int(record_data.get("authenticated_epoch",-2))
		var auth_to_read:=str(prior.get("operation",""))=="authenticate" and operation=="read" and _record_host(prior)==str(record_data.get("origin","")) and str(prior_data.get("principal",""))==principal
		if env_to_auth or auth_to_read:edges.append({"from":str(prior.get("id","")),"to":str(record.get("id",""))})
	var diagram:=Diagram.new();body.add_child(diagram)
	diagram.configure("report",{"records":objects,"edges":edges},float(d.game.settings.get("text_scale",1.0)),opened,_report_open.bind(d))
	var rule:=HSeparator.new();body.add_child(rule)
	var selection:=U.row(body);_label(selection,"提出する原記録",12,UI.MUTED)
	for record in records:
		var id:=str(record.get("id",""));var check:=CheckBox.new()
		check.name="NetworkEvidence_"+id;check.text=id;check.tooltip_text="%s / %s → %d" % [_record_host(record),_record_path(record),int(record.get("status",0))]
		check.button_pressed=id in ids;_light(check);selection.add_child(check)
		check.toggled.connect(func(value):
			var chosen:Array=s.get("report_ids",[]).duplicate()
			if value and not id in chosen:chosen.append(id)
			elif not value:chosen.erase(id)
			s.report_ids=chosen;d._save_session(false);d._refresh_advanced.call_deferred())

static func _report_open(id:String,d) -> void:
	d.widgets.advanced.next_scroll=0;U.choose(d,KIND,"relay_report_record",id)

static func _report_original(d,parent:Node,record:Dictionary) -> void:
	var heading:=U.row(parent);var record_data:Dictionary=record.get("data",{})
	_label(heading,"原記録 "+str(record.get("id",""))+" / "+str(record.get("operation","")).to_upper()+" "+str(int(record.get("status",0))),14,UI.INK)
	_button(heading,"閉じる","NetworkCloseReportRecord",U.choose.bind(d,KIND,"relay_report_record",""),false)
	_label(parent,"%s / %s  →  %s / %s" % [str(record_data.get("origin","")),str(record_data.get("principal","")),_record_host(record),_record_path(record)],13,UI.INK)
	_label(parent,"観測世代 %d  ·  %s" % [int(record_data.get("revision",0)),str(record_data.get("sha256",""))],11,UI.MUTED)
	var raw:=TextEdit.new();raw.name="NetworkReportRaw";raw.editable=false
	raw.text=str(record_data.get("bytes","")) if record_data.has("bytes") else JSON.stringify(record_data,"\t")
	raw.custom_minimum_size.y=145*float(d.game.settings.get("text_scale",1.0));raw.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	U.text_style(raw);parent.add_child(raw)
static func _changes(d,parent:Node,n:Dictionary) -> void:
	var control:Dictionary=n.get("change_control",{})
	var applied:Dictionary=control.get("applied",{})
	if not bool(control.get("available",false)):
		_label(parent,"顧客の根拠確認後に変更を依頼できます。",14,UI.MUTED)
		_button(parent,"根拠と報告へ","NetworkChangeOpenReport",U.choose.bind(d,KIND,"tab","report"),false);return
	var body:=_surface(parent,false);var s:=U.state(d,KIND);var selected:=str(s.get("relay_change",""));var pending:Dictionary={};var objects:Array=[]
	var header:=U.row(body);_label(header,"中継サービスの変更依頼",18,UI.INK)
	_label(header,"適用世代 %d" % _revision(n),12,UI.MUTED)
	var last:Dictionary=control.get("last_change",{})
	if not last.is_empty():_label(header,str(last.get("id","")),12,UI.PRIMARY)
	for option in control.get("options",[]):
		var id:=str(option.get("id",""))
		if id==selected:pending=option
		if id=="isolate_relay" and bool(applied.get("relay_isolated",false)):continue
		if id=="restore_relay" and not bool(applied.get("relay_isolated",false)):continue
		objects.append({"id":id,"label":"relay01" if id in ["isolate_relay","restore_relay"] else "svc-relay" if id=="rotate_credential" else "公開設定","kind":"switch" if id in ["isolate_relay","restore_relay"] else "key" if id=="rotate_credential" else "file","active":bool(applied.get("relay_isolated",false)) if id in ["isolate_relay","restore_relay"] else bool(applied.get("config_restricted",false)),"state":"鍵を更新済み" if id=="rotate_credential" and bool(applied.get("credential_rotated",false)) else "観測した鍵が有効" if id=="rotate_credential" else "隔離中" if id=="restore_relay" else "稼働中" if id=="isolate_relay" else "制限済み" if bool(applied.get("config_restricted",false)) else "公開中","caption":str(option.get("label","")),"enabled":bool(option.get("enabled",false))})
	var row:=U.row(body)
	_label(row,"依頼する対象を選択" if pending.is_empty() else str(pending.get("label","")),14,UI.INK)
	var send:=_button(row,"顧客へ依頼" if pending.is_empty() else "顧客へ依頼  ¥%d / %d分" % [int(pending.get("cost",0)),int(pending.get("minutes",0))],"NetworkRequestChange",_request_change.bind(d,selected),false)
	send.disabled=pending.is_empty() or not bool(pending.get("enabled",false))
	_button(row,"探索で再測定","NetworkRetest",U.choose.bind(d,KIND,"tab","explore"),false)
	var canvas:=Diagram.new();body.add_child(canvas);canvas.configure("changes",{"controls":objects},float(d.game.settings.get("text_scale",1.0)),selected,_change_selected.bind(d))

static func _change_selected(id:String,d) -> void:
	d.widgets.advanced.next_scroll=0;U.choose(d,KIND,"relay_change",id)

static func _request_change(d,operation:String) -> void:
	var result:=U.send(d,KIND,"request_change",{"change":operation})
	if bool(result.get("ok",false)):
		U.state(d,KIND).erase("relay_change");d._save_session(false);d._refresh_advanced.call_deferred()

static func _shipping(d,parent:Node,n:Dictionary) -> void:
	var body:=_surface(parent,false);var shipping:Dictionary=n.get("shipping",{})
	var header:=U.row(body);_label(header,"Dispatch / 出荷端末",20,Color("463d2e"))
	_label(header,"本日便   受付 → 中継 → 配送",12,Color("7b694a"))
	_button(header,"中継の変更依頼","ShippingOpenChanges",U.choose.bind(d,KIND,"tab","changes"),false)
	var orders:Array=[]
	for order in _rows(shipping.get("orders",n.get("orders",[]))):
		var item:Dictionary=order.duplicate(true);var attempt:Dictionary=order.get("last_attempt",{})
		item.sent=bool(order.get("delivered",false))
		item.code=int(attempt.get("status",0));item.current=int(order.get("verified_revision",-1))==_revision(n)
		item.label="優先便" if str(order.get("priority",""))=="priority" else "通常便"
		item.observation=str(order.get("receipt",{}).get("id","")) if item.sent else "未受付"
		item.route_state=("✓ 現ルート確認済み" if item.current else "配送済み / 現ルート未確認") if item.sent else "未送信"
		if item.code>=400:item.route_state="× %d  %s" % [item.code,"現ルート不通" if item.sent else "未受付"]
		orders.append(item)
	var canvas:=Diagram.new();body.add_child(canvas)
	canvas.configure("shipping",{"orders":orders,"isolated":bool(n.get("change_control",{}).get("applied",{}).get("relay_isolated",false)),"can_ship":bool(shipping.get("can_ship",true))},float(d.game.settings.get("text_scale",1.0)),"",_ship.bind(d))

static func _ship(id:String,d) -> void:
	U.send(d,KIND,"ship_order",{"order_id":id})
