extends RefCounted
const U=preload("res://scripts/investigation_ui.gd")
const UI=preload("res://scripts/ui_theme.gd")
const Canvas=preload("res://scripts/saas_response_canvas.gd")
const KIND:="advanced-saas-response"
const INK=Color("242a30")
const MUTED=Color("68747e")
const PURPLE=Color("714b67")

static func build(d,parent:VBoxContainer) -> void:
	U.mount(d,parent,KIND,"SaaS Response / 連携アクセス対応")
	refresh(d)

static func refresh(d) -> void:
	var data:Dictionary=d.game.advanced_view();var n:Dictionary=data.get("saas",{})
	var body:=U.begin(d,KIND,data)
	if body==null or n.is_empty():return
	var s:=U.state(d,KIND)
	U.navigation(d,KIND,[["identity","Identity"],["billing","請求デスク"],["records","原記録・整理"],["results","受入確認"]],"identity","SaasTab_")
	for tab in d.widgets.advanced.nav.get_children():
		if tab is Button:_light(tab)
	match str(s.get("tab","identity")):
		"billing":_billing(d,body,n)
		"records":_records(d,body,n,data.get("checks",[]))
		"results":U.checks(body,data)
		_:_identity(d,body,n)

static func _light(button:Button) -> void:
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:button.add_theme_color_override(state,INK)
	for state in ["hover","pressed","hover_pressed"]:button.add_theme_stylebox_override(state,UI.style(Color("e8f0f5"),Color("7094aa"),8,6,2))

static func _button(parent:Node,label:String,id:String,action:Callable) -> Button:
	var button:=U.button(parent,label,id,action);_light(button);return button

static func _label(parent:Node,text:String,size:int=14,color:Color=INK) -> Label:
	return U.label(parent,text,size,color,not parent is HFlowContainer)

static func _surface(parent:Node,title:String,accent:Color) -> VBoxContainer:
	var frame:=PanelContainer.new();frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frame.add_theme_stylebox_override("panel",UI.style(Color.WHITE,Color("d6dce0"),12,10,1));parent.add_child(frame)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",9);frame.add_child(body)
	var band:=PanelContainer.new();band.add_theme_stylebox_override("panel",UI.style(accent,accent,12,8,0));body.add_child(band)
	_label(band,title,18,Color.WHITE)
	return body

static func _send(d,action:String,args:Dictionary={}) -> void:
	var result:=U.send(d,KIND,action,args)
	var record:Dictionary=result.get("data",{}).get("record",{})
	if action=="organize_records" and bool(result.get("ok",false)):
		var s:=U.state(d,KIND);s.show_organization=true;s.show_sources=false;d.widgets.advanced.next_scroll=0
	if not record.is_empty():
		U.state(d,KIND).last_record=str(record.get("id",""));d._save_session(false)

static func _select(app_id:String,part:String,d) -> void:
	var s:=U.state(d,KIND);s.selected_app=app_id;s.selected_part=part
	s.erase("open_record");d.widgets.advanced.next_scroll=0;d._save_session(false);d._refresh_advanced.call_deferred()

static func _latest(n:Dictionary,app:String,action:String) -> Dictionary:
	var found:Dictionary={}
	for record in n.get("records",[]):
		if str(record.get("app",""))==app and str(record.get("action",""))==action:found=record
	return found

static func _record(n:Dictionary,id:String) -> Dictionary:
	for record in n.get("records",[]):
		if str(record.get("id",""))==id:return record
	return {}

static func _app(n:Dictionary,id:String) -> Dictionary:
	for app in n.get("apps",[]):
		if str(app.get("id",""))==id:return app
	return {}

static func _clock(parent:Node,n:Dictionary) -> void:
	var row:=U.row(parent);_label(row,"対応 %d分" % int(n.get("elapsed_minutes",0)),13,MUTED)
	var next:=int(n.get("next_event_minute",-1))
	_label(row,"次の同期 %d分" % next if next>=0 else "予定した同期は完了",13,MUTED)
	var count:int=n.get("egress",{}).get("exported_rows",[]).size()
	_label(row,"延べ送信 %d行" % count,14,UI.RED if count>0 else INK)

static func _identity(d,parent:Node,n:Dictionary) -> void:
	var body:=_surface(parent,"IDENTITY / 連携アクセス",Color("252a2e"));var s:=U.state(d,KIND)
	_clock(body,n)
	var selected_id:=str(s.get("selected_app",""));var app:=_app(n,selected_id)
	var global:=U.row(body)
	_button(global,"監査記録を取得 · 2分","SaasCollectAudit",_send.bind(d,"collect_audit"))
	_button(global,"パスワード更新 · 2分","SaasPasswordReset",_send.bind(d,"password_reset"))
	_raw(d,body,n)
	var factor:=float(d.game.settings.get("text_scale",1.0));var wide:=float(d.windows.advanced.size.x)/factor>=1050
	var content:BoxContainer=HBoxContainer.new() if wide else VBoxContainer.new();content.add_theme_constant_override("separation",12);body.add_child(content)
	var chart:=VBoxContainer.new();chart.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var inspector:=VBoxContainer.new();inspector.add_theme_constant_override("separation",5);inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if wide:
		inspector.custom_minimum_size.x=280*factor;inspector.size_flags_horizontal=Control.SIZE_FILL
		content.add_child(chart);content.add_child(inspector)
	else:content.add_child(inspector);content.add_child(chart)
	if not app.is_empty():
		var operations:=U.row(inspector);_label(operations,str(app.get("id",""))+" / "+str(app.get("label","")),14)
		_button(operations,"申請・所有者 · 1分","SaasInspectApp",_send.bind(d,"inspect_app",{"app":selected_id}))
		_button(operations,"現在の接続を試す · 1分","SaasProbeSession",_send.bind(d,"probe_session",{"app":selected_id}))
		var access:=U.row(inspector);var consent:=bool(app.get("consent",{}).get("enabled",false));var session:=bool(app.get("session",{}).get("active",false))
		_button(access,("同意を撤回" if consent else "同意を戻す")+" · 2分","SaasChangeConsent",_send.bind(d,"change_access",{"app":selected_id,"control":"consent","enabled":not consent}))
		_button(access,("既存接続を失効" if session else "接続を再発行")+" · 2分","SaasChangeSession",_send.bind(d,"change_access",{"app":selected_id,"control":"session","enabled":not session}))
		if selected_id=="app-19":_button(access,"請求デスクへ","SaasOpenBilling",U.choose.bind(d,KIND,"tab","billing"))
		var inspected:=_latest(n,selected_id,"inspect_app")
		if not inspected.is_empty():
			var facts:=U.row(inspector)
			_label(facts,str(app.get("publisher",""))+" · "+str(app.get("permission","")),12,MUTED)
			_label(facts,"申請 "+str(app.get("approved_change",""))+" / "+str(app.get("approved_by","")),12,MUTED)
			_button(facts,"申請原文","SaasOpenAppAudit",_open.bind(d,str(inspected.get("id",""))))
		var request:=_latest(n,selected_id,"probe_session")
		if not request.is_empty():_response(inspector,d,n,request)
	else:_label(inspector,"連携アプリ・同意プラグ・接続券を選択",13,MUTED)
	var shown:Array=[]
	for source in n.get("apps",[]):
		var id:=str(source.get("id",""));var request:=_latest(n,id,"probe_session")
		var fresh:=not request.is_empty() and int(request.get("world_revision",-1))==int(n.get("world_revision",0))
		var status:=int(request.get("status",0))
		shown.append({"id":id,"label":str(source.get("label","")),"consent":bool(source.get("consent",{}).get("enabled",false)),"session":bool(source.get("session",{}).get("active",false)),"session_id":"世代 %d" % int(source.get("session",{}).get("revision",0)),"resource":str(source.get("resource","資料")),"fresh":fresh,"status":status,"measurement":"? 未実測" if request.is_empty() else ("" if fresh else "過去 ")+("✓ " if status==200 else "× ")+str(status)})
	var canvas:=Canvas.new();chart.add_child(canvas)
	canvas.configure("identity",{"apps":shown,"user":str(n.get("user",{}).get("id","")),"leaked_rows":n.get("egress",{}).get("exported_rows",[]).size()},float(d.game.settings.get("text_scale",1.0)),selected_id,_select.bind(d))
	var sync:=U.row(chart)
	for item in n.get("egress",{}).get("schedule",[]):
		var state:=str(item.get("status",""));var marker:="◇" if state=="scheduled" else "×" if state=="blocked" else "↑"
		var button:=_button(sync,"%s %d分 · %s" % [marker,int(item.get("due_minute",0)),"予定" if state=="scheduled" else "拒否" if state=="blocked" else "%d行" % int(item.get("row_count",0))],"SaasSync_"+str(item.get("id","")),_open.bind(d,str(item.get("record_id",""))))
		button.disabled=str(item.get("record_id","")).is_empty()

static func _response(parent:Node,d,n:Dictionary,record:Dictionary) -> void:
	var row:=U.row(parent);var fresh:=int(record.get("world_revision",-1))==int(n.get("world_revision",0));var code:=int(record.get("status",0))
	_label(row,("" if fresh else "過去 ")+("✓ " if code==200 else "× ")+str(code)+" · "+str(record.get("id","")),15,MUTED if not fresh else UI.GREEN if code==200 else UI.RED)
	_button(row,"原記録を開く","SaasOpenResponse",_open.bind(d,str(record.get("id",""))))

static func _open(d,id:String) -> void:
	d.widgets.advanced.next_scroll=0
	U.choose(d,KIND,"open_record",id)

static func _raw(d,parent:Node,n:Dictionary) -> void:
	var found:=_record(n,str(U.state(d,KIND).get("open_record","")))
	if found.is_empty():return
	var heading:=U.row(parent);_label(heading,"原記録 "+str(found.get("id",""))+" · %d分 / %d" % [int(found.get("minute",0)),int(found.get("status",0))],14)
	_button(heading,"閉じる","SaasCloseRecord",U.choose.bind(d,KIND,"open_record",""))
	var raw:=TextEdit.new();raw.name="SaasRawRecord";raw.editable=false;raw.text=JSON.stringify(found,"\t")
	raw.custom_minimum_size.y=150*float(d.game.settings.get("text_scale",1.0));raw.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;U.text_style(raw);parent.add_child(raw)

static func _billing(d,parent:Node,n:Dictionary) -> void:
	var body:=_surface(parent,"請求デスク / 顧客への送信",PURPLE);var invoice:Dictionary=n.get("invoice",{})
	var attempts:Array=invoice.get("attempts",[]);var last:Dictionary=attempts.back() if not attempts.is_empty() else {}
	var accepted:=not str(invoice.get("receipt_id","")).is_empty();var actions:=U.row(body)
	var submit:=_button(actions,"受付を再確認" if accepted else "同じ請求を再送 · 2分" if int(last.get("status",0))>=400 else "顧客へ送信 · 2分","SaasSubmitInvoice",_send.bind(d,"submit_invoice",{"invoice_id":str(invoice.get("id",""))}))
	submit.disabled=invoice.is_empty()
	_button(actions,"連携アクセスへ","SaasBillingOpenIdentity",_billing_identity.bind(d))
	_raw(d,body,n)
	var app:=_app(n,"app-19");var route:=U.row(body)
	_label(route,"BILL-001 → app-19 → 顧客受付",13,PURPLE)
	_label(route,"同意 "+("✓" if bool(app.get("consent",{}).get("enabled",false)) else "×")+"  接続 "+("✓" if bool(app.get("session",{}).get("active",false)) else "×"),12,MUTED)
	if not last.is_empty():_response(body,d,n,last)
	var canvas:=Canvas.new();body.add_child(canvas)
	canvas.configure("invoice",{"id":str(invoice.get("id","")),"customer":str(invoice.get("customer","")),"lines":invoice.get("lines",[]),"total":int(invoice.get("amount",0)),"status":int(last.get("status",0)),"receipt_id":str(invoice.get("receipt_id",""))},float(d.game.settings.get("text_scale",1.0)),"",Callable())

static func _billing_identity(d) -> void:
	var s:=U.state(d,KIND);s.selected_app="app-19";s.selected_part="app"
	U.choose(d,KIND,"tab","identity")

static func _record_label(record:Dictionary) -> String:
	var action:=str(record.get("action",""))
	return str({"consent_review":"申請原本","inspect_app":"アプリ調査","collect_audit":"監査取得","probe_session":"接続実測","change_consent":"同意変更","change_session":"接続変更","session_reissued_by_sync":"同期で再発行","scheduled_export":"外部同期","password_reset":"パスワード更新","submit_invoice":"顧客請求","organize_manual":"手動整理","organize_assistant":"助手による整理","submit_report":"報告提出"}.get(action,action))

static func _records(d,parent:Node,n:Dictionary,checks:Array) -> void:
	var body:=_surface(parent,"調査ノート / 原記録と時系列",Color("3d5655"));var s:=U.state(d,KIND)
	var assistant:Dictionary=d.game.record_assistant_status();var ids:Array=s.get("record_ids",[]);var organization:Dictionary=n.get("organization",{});var report:Dictionary=n.get("report",{})
	var sources:=_source_records(n.get("records",[]));var organized:Array=organization.get("record_ids",[])
	var unorganized:=0
	for record in sources:
		if not str(record.get("id","")) in organized:unorganized+=1
	var status:=U.row(body)
	_label(status,"原記録 %d件 / 未整理 %d件" % [sources.size(),unorganized],14)
	var submitted:=bool(report.get("submitted",false));var current_report:=false
	for check in checks:
		if str(check.get("id",""))=="report":current_report=bool(check.get("passed",false))
	if submitted:_label(status,("✓ 最新の報告" if current_report else "△ 追補が必要")+" · 第%d版" % int(report.get("version",1)),13,UI.GREEN if current_report else UI.WARNING)
	var actions:=U.row(body)
	_button(actions,"原本と最新記録を選択","SaasSelectRecords",_select_records.bind(d,sources))
	var same:=ids.size()==organized.size() and not ids.is_empty()
	for id in ids:
		if not id in organized:same=false
	var manual:=_button(actions,"整理済み" if same else "手動で整理 · %d分" % int(assistant.get("manual_minutes",5)),"SaasOrganizeManual",_send.bind(d,"organize_records",{"mode":"manual","record_ids":ids}))
	manual.disabled=ids.is_empty() or ids.size()>32 or same
	var assisted:=_button(actions,"整理済み" if same else "助手で整理 · %d分 / ¥%d" % [int(assistant.get("assistant_minutes",2)),int(assistant.get("run_cost",300))],"SaasOrganizeAssistant",_send.bind(d,"organize_records",{"mode":"assistant","record_ids":ids}))
	assisted.disabled=not bool(assistant.get("owned",false)) or ids.is_empty() or ids.size()>32 or same
	var previous_ids:Array=report.get("latest",report.get("original",{})).get("record_ids",[])
	var same_submission:=submitted and ids.size()==previous_ids.size()
	for id in ids:
		if not id in previous_ids:same_submission=false
	var submit:=_button(actions,"選択した原記録を追補報告" if submitted else "選択した原記録を報告","SaasSubmitReport",_send.bind(d,"submit_report",{"record_ids":ids}))
	submit.disabled=ids.is_empty() or ids.size()>32 or same_submission
	if not bool(assistant.get("owned",false)):
		var purchase:=U.row(body)
		var buy:=_button(purchase,"記録整理助手を購入 · ¥%d" % int(assistant.get("purchase_cost",3000)),"SaasBuyAssistant",_buy_assistant.bind(d));buy.disabled=not bool(assistant.get("can_purchase",false))
		if not bool(assistant.get("can_purchase",false)):_label(purchase,str(assistant.get("reason","")),12,MUTED)
	_raw(d,body,n)
	if not organized.is_empty():
		var header:=U.row(body);var expanded:=bool(s.get("show_organization",true))
		_label(header,("助手" if str(organization.get("mode",""))=="assistant" else "手動")+"の整理 · %d件 / %d分時点" % [organized.size(),int(organization.get("created_minute",0))],14)
		_button(header,"整理を閉じる" if expanded else "前の整理を開く・無料","SaasOpenOrganization",U.choose.bind(d,KIND,"show_organization",not expanded))
		if expanded:_organized_rails(d,body,n,sources,organized)
	var selection:=U.row(body);var show_sources:=bool(s.get("show_sources",false))
	_button(selection,("▾" if show_sources else "▸")+" 原記録を選ぶ (%d/32件)" % ids.size(),"SaasShowRecordSelection",U.choose.bind(d,KIND,"show_sources",not show_sources))
	if show_sources:
		for record in sources:_timeline_row(d,body,record,true,ids)

static func _source_records(records:Array) -> Array:
	var result:Array=[]
	for record in records:
		if str(record.get("action","")) in ["organize_manual","organize_assistant","submit_report"]:continue
		result.append(record)
	result.sort_custom(func(a:Dictionary,b:Dictionary):
		if int(a.get("minute",0))!=int(b.get("minute",0)):return int(a.get("minute",0))<int(b.get("minute",0))
		return int(a.get("seq",0))<int(b.get("seq",0)))
	return result

static func _organized_rails(d,parent:Node,n:Dictionary,sources:Array,ids:Array) -> void:
	var lanes:Array=[]
	for app in n.get("apps",[]):lanes.append({"id":str(app.get("id","")),"label":str(app.get("id",""))+" / "+str(app.get("label","")),"events":[]})
	lanes.append({"id":"","label":"共通 / 利用者と監査原本","events":[]})
	for record in sources:
		if not str(record.get("id","")) in ids:continue
		for lane in lanes:
			if str(lane.id)!=str(record.get("app","")):continue
			var label:=_record_label(record)
			if str(record.get("action",""))=="scheduled_export":label+=" · %d行" % record.get("data",{}).get("row_ids",[]).size()
			elif str(record.get("action","")) in ["change_consent","change_session"]:label+=" · "+("再開" if bool(record.get("data",{}).get("enabled",false)) else "停止")
			lane.events.append({"id":str(record.get("id","")),"minute":int(record.get("minute",0)),"action":str(record.get("action","")),"label":label,"status":int(record.get("status",0)),"enabled":bool(record.get("data",{}).get("enabled",false))})
	var visible:Array=[]
	for lane in lanes:
		if not lane.events.is_empty():visible.append(lane)
	var canvas:=Canvas.new();parent.add_child(canvas)
	canvas.configure("timeline",{"lanes":visible},float(d.game.settings.get("text_scale",1.0)),"",_open_organized.bind(d))

static func _open_organized(id:String,_part:String,d) -> void:
	_open(d,id)
static func _timeline_row(d,parent:Node,record:Dictionary,selectable:bool,ids:Array) -> void:
	var row:=U.row(parent);var id:=str(record.get("id",""));var code:=int(record.get("status",0))
	if selectable:
		var check:=CheckBox.new();check.name="SaasRecordSelect_"+id;check.text="";check.tooltip_text="整理・報告に含める / "+id;check.button_pressed=id in ids;check.disabled=ids.size()>=32 and not id in ids;_light(check);row.add_child(check)
		check.toggled.connect(func(value):
			var s:=U.state(d,KIND);var chosen:Array=s.get("record_ids",[]).duplicate()
			if value and not id in chosen:chosen.append(id)
			elif not value:chosen.erase(id)
			s.record_ids=chosen;d._save_session(false);d._refresh_advanced.call_deferred())
	_label(row,"│ %02d分" % int(record.get("minute",0)),12,MUTED)
	_button(row,_record_label(record)+" · "+id,("SaasRecord_" if selectable else "SaasOrganized_")+id,_open.bind(d,id))
	_label(row,str(record.get("app",""))+" "+("✓ " if code==200 else "× ")+str(code),12,UI.RED if code>=400 else MUTED)
	if str(record.get("action",""))=="scheduled_export":_label(row,"%d行" % record.get("data",{}).get("row_ids",[]).size(),12,UI.RED if code==200 else MUTED)

static func _select_records(d,records:Array) -> void:
	var chosen:Array=[];var audit:=""
	for record in records:
		var id:=str(record.get("id",""))
		if id in ["audit-1","audit-2"]:chosen.append(id)
		if str(record.get("action",""))=="collect_audit":audit=id
	if not audit.is_empty() and not audit in chosen:chosen.append(audit)
	for index in range(records.size()-1,-1,-1):
		if chosen.size()>=32:break
		var id:=str(records[index].get("id",""))
		if not id in chosen:chosen.append(id)
	var ids:Array=[]
	for record in records:
		if str(record.get("id","")) in chosen:ids.append(str(record.get("id","")))
	U.choose(d,KIND,"record_ids",ids)

static func _buy_assistant(d) -> void:
	var bought:bool=d.game.buy_record_assistant()
	var s:=U.state(d,KIND);s.message="記録整理助手を導入しました。" if bought else "購入条件を確認してください。";s.result_ok=bought
	d._save_session(false);d._refresh_advanced.call_deferred()
