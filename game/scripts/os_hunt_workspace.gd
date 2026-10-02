extends RefCounted
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const KIND := "advanced-hunt"

static func build(d,parent: VBoxContainer) -> void:
	U.mount(d,parent,KIND,"Trace Desk  /  記録の照合")
	refresh(d)

static func refresh(d) -> void:
	var data: Dictionary=d.game.advanced_view(); var s:=U.state(d,KIND)
	var body:=U.begin(d,KIND,data)
	if body==null:return
	var h: Dictionary=data.get("hunt",{})
	if h.is_empty():return
	U.navigation(d,KIND,[["timeline","原記録"],["response","接続と業務"],["results","受入確認"]],"timeline","HuntTab_")
	if str(s.get("tab","timeline"))=="results":U.checks(body,data);return
	if str(s.get("tab","timeline"))=="response":_response(d,body,h);return
	var order:=U.panel(body)
	for item in h.work_orders:
		var summary:=U.row(order)
		U.chip(summary,"作業予定  %s  %s" % [item.id,item.time])
		U.button(summary,"内容を確認","HuntShowOrder",U.choose.bind(d,KIND,"show_order",not bool(s.get("show_order",false))),"file")
		U.button(summary,"根拠に保存","HuntOrderPin_"+str(item.id),U.send.bind(d,KIND,"pin",{"target":item.id}),"save")
		if bool(s.get("show_order",false)):
			U.label(order,"%s @ %s  ·  %s  ·  %s" % [item.account,item.host,item.task,item.path],14,UI.INK,true)
			U.label(order,str(item.detail),13,UI.MUTED,true)
	var filter_row:=HBoxContainer.new();body.add_child(filter_row)
	var filter:=U.input(d,filter_row,KIND,"filter","HuntFilter","時刻・接続・端末で絞り込み")
	U.button(filter_row,"検索","HuntApplyFilter",func():d.widgets.advanced.signature="";d._refresh_advanced.call_deferred(),"search")
	filter.text_submitted.connect(func(_value):d.widgets.advanced.signature="";d._refresh_advanced.call_deferred())
	var panes:=U.columns(d,body,620)
	var primary: VBoxContainer=panes[0];var inspector: VBoxContainer=panes[1]
	var selection:=U.row(primary)
	var selection_label:=U.label(selection,"選択 %d 件" % s.get("selected_events",[]).size(),14);selection_label.name="HuntSelectionCount"
	U.button(selection,"選択を照合","HuntCorrelate",func():U.send(d,KIND,"correlate",{"event_ids":s.get("selected_events",[])}),"compare")
	U.button(selection,"解除","HuntClearSelection",U.choose.bind(d,KIND,"selected_events",[]),"close")
	var compact: bool=float(d.windows.advanced.size.x)<1100
	var tree:=U.table(primary,"HuntEvents",["時刻","収集元","接続"] if compact else ["時刻","収集元","接続","端末"],310 if float(d.windows.advanced.size.x)>=900 else 210)
	tree.set_column_expand(0,false);tree.set_column_custom_minimum_width(0,90)
	var selected: Array=s.get("selected_events",[])
	for item in h.events:
		if not str(s.get("filter","")).is_empty() and not JSON.stringify(item).contains(str(s.filter)):continue
		var row:=U.table_row(tree,[item.get("time",""),item.source,item.session,item.get("asset","")],item)
		row.set_cell_mode(0,TreeItem.CELL_MODE_CHECK);row.set_editable(0,true);row.set_checked(0,str(item.id) in selected);row.set_text(0,str(item.get("time","")))
		if str(item.id)==str(s.get("event","")):
			row.select(0);tree.scroll_to_item.call_deferred(row)
	tree.item_edited.connect(func():
		var row:=tree.get_edited();var id:=str(row.get_metadata(0).id)
		var ids: Array=s.get("selected_events",[]).duplicate()
		if row.is_checked(0) and not id in ids:ids.append(id)
		elif not row.is_checked(0):ids.erase(id)
		s.selected_events=ids;selection_label.text="選択 %d 件" % ids.size();d._save_session(false))
	tree.item_selected.connect(func():U.choose(d,KIND,"event",str(tree.get_selected().get_metadata(0).id)))
	var current: Dictionary={}
	for item in h.events:
		if str(item.id)==str(s.get("event","")):current=item
	var detail:=U.panel(inspector,"原記録インスペクター" if current.is_empty() else "")
	detail.name="HuntEventInspector"
	if current.is_empty():
		U.label(detail,"記録を選択",18,UI.MUTED)
		U.label(detail,"時刻・接続・端末を照合し、必要な原記録を保存します。",13,UI.MUTED,true)
	else:
		var tags:=U.row(detail)
		U.chip(tags,str(current.get("time","")));U.chip(tags,str(current.source));U.chip(tags,str(current.id))
		var save:=U.button(tags,"根拠に保存","HuntPinEvent",U.send.bind(d,KIND,"pin",{"target":current.id}),"save")
		save.disabled=data.evidence.has(str(current.id))
		U.label(detail,"%s  /  %s → %s" % [current.session,current.get("asset",""),current.get("destination","")],17,UI.INK,true)
		U.label(detail,"%s  ·  %s" % [current.get("account",""),current.get("task","")],13,UI.MUTED,true)
		var raw:=TextEdit.new();raw.name="HuntOriginalRecord";raw.editable=false;raw.text=str(current.get("detail",""));raw.custom_minimum_size.y=106;raw.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;U.text_style(raw);detail.add_child(raw)
	U.label(inspector,"根拠 %d 件  ·  照合ノート %d 件" % [data.evidence.size(),h.links.size()],13,UI.MUTED)
	if not h.links.is_empty():
		var links:=U.panel(inspector,"直近の照合")
		var latest: Dictionary=h.links.back()
		U.label(links,str(latest.session),17)
		var sources:=U.row(links)
		for value in latest.sources:U.chip(sources,str(value))
		U.label(links,", ".join(latest.event_ids),13,UI.MUTED,true)
		U.button(links,"照合ノートを開く","HuntShowLinks",U.choose.bind(d,KIND,"show_links",not bool(s.get("show_links",false))),"file")
		if bool(s.get("show_links",false)):
			for item in h.links:U.label(links,"%s ← %s" % [item.session,", ".join(item.event_ids)],13,UI.INK,true)

static func _response(d,body: Node,h: Dictionary) -> void:
	var tests:=U.row(body)
	U.button(tests,"アクセスを試験","HuntProbeSecurity",U.send.bind(d,KIND,"probe_security"),"play")
	U.button(tests,"通常業務を試験","HuntProbeBusiness",U.send.bind(d,KIND,"probe_business"),"check")
	for key in h.measurements:
		var measure: Dictionary=h.measurements[key]
		var allowed: int=measure.steps.filter(func(item):return bool(item.allowed)).size()
		U.chip(tests,("アクセス" if key=="security" else "業務")+": 到達 %d / %d" % [allowed,measure.steps.size()],UI.MUTED if int(measure.revision)!=int(h.change_revision) else UI.INK)
	var panes:=U.columns(d,body,450);var settings: VBoxContainer=panes[0];var observations: VBoxContainer=panes[1]
	var assets:=U.panel(settings,"端末の接続")
	var asset_row:=U.row(assets)
	for id in h.assets:
		var item: Dictionary=h.assets[id]
		var b:=U.button(asset_row,("● " if item.connected else "○ ")+str(id),"HuntHost_"+str(id),U.send.bind(d,KIND,"isolate_host" if item.connected else "reconnect_host",{"target":id}),"network")
		b.tooltip_text="隔離する" if item.connected else "再接続する"
	var sessions:=U.panel(settings,"発行済み接続")
	for id in h.sessions:
		var item: Dictionary=h.sessions[id];var row:=U.row(sessions)
		U.label(row,"%s  %s @ %s" % [id,item.account,item.host],13)
		U.button(row,"有効 → 失効" if item.active else "失効 → 再発行","HuntSession_"+str(id),U.send.bind(d,KIND,"revoke_session" if item.active else "restore_session",{"target":id}),"refresh")
	var tasks:=U.panel(settings,"定期処理")
	for id in h.tasks:
		var item: Dictionary=h.tasks[id];var row:=U.row(tasks)
		U.label(row,"%s @ %s" % [id,item.host],13)
		U.button(row,"有効 → 停止" if item.enabled else "停止 → 再開","HuntTask_"+str(id),U.send.bind(d,KIND,"disable_task" if item.enabled else "enable_task",{"target":id}),"play")
	for key in ["security","business"]:
		var result:=U.panel(observations,"アクセスの実測" if key=="security" else "通常業務の実測")
		if not h.measurements.has(key):U.label(result,"未試験",16,UI.MUTED);continue
		var measure: Dictionary=h.measurements[key]
		var table:=U.table(result,"HuntMeasurement_"+str(key),["対象","操作","結果"],160)
		for item in measure.steps:U.table_row(table,[item.target,item.operation,"到達" if item.allowed else "停止"],item)
		U.label(result,"設定変更後に再試験が必要" if int(measure.revision)!=int(h.change_revision) else "現在の設定で観測済み",13,UI.MUTED,true)
