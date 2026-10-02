extends RefCounted
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const KIND := "advanced-recovery"

static func build(d,parent: VBoxContainer) -> void:
	U.mount(d,parent,KIND,"Recovery Bay  /  隔離復旧")
	refresh(d)

static func refresh(d) -> void:
	var data: Dictionary=d.game.advanced_view();var s:=U.state(d,KIND)
	var body:=U.begin(d,KIND,data)
	if body==null:return
	var r: Dictionary=data.get("recovery",{})
	if r.is_empty():return
	U.navigation(d,KIND,[["copies","復元候補"],["stage","隔離先を編集"],["release","試験と再開"],["results","受入確認"]],"copies","RecoveryTab_")
	match str(s.get("tab","copies")):
		"results":U.checks(body,data)
		"stage":_stage(d,body,r)
		"release":_release(d,body,r,data)
		_:_copies(d,body,r,data)

static func _raw(parent: Node,text: String,id: String,height: float=90) -> void:
	var editor:=TextEdit.new();editor.name=id;editor.editable=false;editor.text=text;editor.custom_minimum_size.y=height;editor.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;U.text_style(editor);parent.add_child(editor)

static func _summary(value: String) -> String:
	return value.strip_edges().replace("\n"," | ")

static func _copies(d,body: Node,r: Dictionary,data: Dictionary) -> void:
	var s:=U.state(d,KIND);var panes:=U.columns(d,body,300)
	var selector: VBoxContainer=panes[0];var detail: VBoxContainer=panes[1]
	U.label(selector,"保存時点",16)
	var tree:=U.table(selector,"RecoverySnapshots",["候補","世代"],150)
	for item in r.snapshots:
		var row:=U.table_row(tree,[item.id,item.revision],item)
		row.set_icon(0,UI.symbol("archive"));row.set_icon_max_width(0,18)
		if str(item.id)==str(r.selected_snapshot):row.select(0)
	tree.item_selected.connect(func():U.send(d,KIND,"inspect_snapshot",{"target":str(tree.get_selected().get_metadata(0).id)}))
	var reference:=U.panel(selector,"経理の伝票控え")
	var vouchers:=U.table(reference,"RecoveryReference",["伝票 ID","金額"],75)
	for item in r.reference:U.table_row(vouchers,[item.id,item.amount],item)
	var selected: Dictionary={}
	for item in data.observations:
		if item.operation=="inspect_snapshot" and item.target==r.selected_snapshot:selected=item.data.get("files",{})
	if selected.is_empty():
		var empty:=U.panel(detail,"保存内容と本番の比較")
		U.label(empty,"保存時点を選択",20,UI.MUTED)
		U.label(empty,"原本は保持したまま、候補の実内容を確認できます。",13,UI.MUTED,true)
		return
	var comparison:=U.panel(detail,"%s  ↔  本番の現物" % r.selected_snapshot)
	var actions:=U.row(comparison)
	U.button(actions,"隔離先へ復元","RecoveryStageRestore",func():
		var result:=U.send(d,KIND,"stage_restore",{"snapshot":str(r.selected_snapshot)})
		if result.get("ok",false):s.erase("ledger_draft");s.erase("startup_draft");U.choose(d,KIND,"tab","stage"),"archive")
	U.button(actions,"ファイル原文","RecoveryShowOriginal",U.choose.bind(d,KIND,"show_original",not bool(s.get("show_original",false))),"file")
	var table:=U.table(comparison,"RecoveryCandidateComparison",["ファイル","保存候補の内容","本番の内容","差分"],112)
	for field in ["ledger","startup"]:
		var candidate:=str(selected.get(field,""));var current:=str(r.production.get(field,""))
		U.table_row(table,["ledger.csv" if field=="ledger" else "startup",_summary(candidate),_summary(current),"同一" if candidate==current else "相違あり"],{"file":field,"candidate":candidate,"production":current})
	if bool(s.get("show_original",false)):
		for field in ["ledger","startup"]:
			U.label(comparison,field+"  /  "+str(r.selected_snapshot),13,UI.MUTED)
			_raw(comparison,str(selected.get(field,"")),"RecoveryOriginal_"+field)
			U.label(comparison,field+"  /  本番",13,UI.MUTED)
			_raw(comparison,str(r.production.get(field,"")),"RecoveryProductionOriginal_"+field)
	var plan:=U.row(detail)
	U.chip(plan,"保存候補");U.label(plan,"→",18,UI.MUTED);U.chip(plan,"隔離先");U.label(plan,"→",18,UI.MUTED);U.chip(plan,"試験後に本番へ")

static func _stage(d,body: Node,r: Dictionary) -> void:
	var s:=U.state(d,KIND)
	if r.staged.is_empty():U.label(body,"隔離先は空です。復元候補を選択してください。",15,UI.MUTED,true);return
	var status:=U.row(body)
	U.chip(status,str(r.stage_source)+"  ·  編集版 "+str(r.stage_revision))
	U.button(status,"実内容を検査","RecoveryScan",U.send.bind(d,KIND,"scan_stage"),"search")
	if not r.scan.is_empty():
		U.chip(status,"伝票 %d 件 / 合計 %s" % [r.scan.rows.size(),r.scan.total])
		U.chip(status,"形式エラー %d 件" % r.scan.errors.size(),Color("9c3d32") if not r.scan.errors.is_empty() else UI.MUTED)
	var panes:=U.columns(d,body,580);var editor:=U.panel(panes[0],"隔離先のファイル");var inspected:=U.panel(panes[1],"直近の検査")
	var file_nav:=U.row(editor);var field:=str(s.get("file","ledger"))
	for spec in [["ledger","ledger.csv"],["startup","startup"]]:
		var b:=U.button(file_nav,spec[1],"RecoverySelect_"+spec[0],U.choose.bind(d,KIND,"file",spec[0]),"file")
		b.toggle_mode=true;b.button_pressed=field==spec[0];UI.navigation(b,b.button_pressed)
	var file_editor: TextEdit
	if field=="ledger":
		file_editor=U.editor(d,editor,KIND,"ledger_draft","RecoveryLedger",str(r.staged.get("ledger","")))
		U.button(editor,"台帳を保存","RecoverySaveLedger",func():U.send(d,KIND,"edit_stage",{"file":"ledger","content":str(s.get("ledger_draft",r.staged.get("ledger","")))}),"save")
	else:
		file_editor=U.editor(d,editor,KIND,"startup_draft","RecoveryStartup",str(r.staged.get("startup","")))
		U.button(editor,"起動設定を保存","RecoverySaveStartup",func():U.send(d,KIND,"edit_stage",{"file":"startup","content":str(s.get("startup_draft",r.staged.get("startup","")))}),"save")
		U.label(editor,"空欄・none = 登録なし / # = コメント\n保守処理: logrotate /var/log",12,UI.MUTED,true)
	var key: String="ledger_draft" if field=="ledger" else "startup_draft"
	var draft_status:=U.label(editor,"未保存の入力あり" if str(s.get(key,r.staged.get(field,"")))!=str(r.staged.get(field,"")) else "隔離先の保存内容を編集中",12,UI.MUTED);draft_status.name="RecoveryDraftState"
	file_editor.text_changed.connect(func():draft_status.text="未保存の入力あり" if file_editor.text!=str(r.staged.get(field,"")) else "隔離先の保存内容を編集中")
	if r.scan.is_empty():U.label(inspected,"未検査",18,UI.MUTED)
	else:
		U.label(inspected,"編集版 %s の観測" % r.scan.revision,14,UI.MUTED)
		if int(r.scan.revision)!=int(r.stage_revision):U.label(inspected,"保存内容が変わりました。再検査が必要です。",14,Color("9c3d32"),true)
		var table:=U.table(inspected,"RecoveryLedgerRows",["伝票 ID","隔離先","経理控え"],110)
		for item in r.scan.rows:
			var reference: String="控えなし"
			for original in r.reference:
				if original.id==item.id:reference=str(original.amount)
			U.table_row(table,[item.id,item.amount,reference],item)
		for item in r.scan.errors:U.label(inspected,str(item),13,Color("9c3d32"),true)
		for item in r.scan.get("startup_execution",{}).get("effects",[]):U.label(inspected,"起動時: "+str(item),13,UI.INK,true)
		for item in r.scan.get("startup_execution",{}).get("errors",[]):U.label(inspected,str(item),13,Color("9c3d32"),true)
	U.button(inspected,"サービス試験へ","RecoveryToTests",U.choose.bind(d,KIND,"tab","release"),"forward")

static func _services(d,parent: Node,r: Dictionary) -> void:
	var chain:=U.panel(parent,"隔離先の起動と業務試験")
	var row:=U.row(chain)
	for pair in [["identity","認証"],["database","DB"],["app","業務アプリ"]]:
		var b:=U.button(row,("● " if r.services[pair[0]] else "○ ")+pair[1],"RecoveryStart_"+pair[0],U.send.bind(d,KIND,"start_service",{"target":pair[0]}),"play")
		b.tooltip_text=pair[1]+"サービスを起動"
		if pair[0]!="app":U.label(row,"→",18,UI.MUTED)
	U.button(chain,"隔離先で業務を試す","RecoveryProbeBusiness",U.send.bind(d,KIND,"probe_business"),"check")
	if r.business_test.is_empty():U.label(chain,"業務試験は未実施",14,UI.MUTED)
	else:
		var result:=U.row(chain)
		U.chip(result,"業務: "+("稼働" if r.business_test.running else "接続不可"),UI.GREEN if r.business_test.running else Color("9c3d32"))
		U.chip(result,"台帳合計 "+str(r.business_test.total));U.chip(result,"編集版 "+str(r.business_test.revision))
		if int(r.business_test.revision)!=int(r.stage_revision):U.label(chain,"編集後の業務試験が必要です。",13,Color("9c3d32"))

static func _release(d,body: Node,r: Dictionary,data: Dictionary) -> void:
	var s:=U.state(d,KIND);var state_row:=U.row(body)
	U.chip(state_row,"本番接続: "+("停止中" if r.network_isolated else "接続中"))
	U.chip(state_row,"隔離先 v%s → 本番 v%s" % [r.stage_revision,r.published_revision])
	var panes:=U.columns(d,body,440);var access: VBoxContainer=panes[0];var testing: VBoxContainer=panes[1]
	var identity:=U.panel(access,"管理接続  /  restore-operator")
	var header:=U.row(identity)
	U.chip(header,"資格情報の世代 "+str(r.credential_epoch))
	U.button(header,"更新","RecoveryRotate",U.send.bind(d,KIND,"rotate_identity",{"account":"restore-operator"}),"refresh")
	for id in r.sessions:
		var item: Dictionary=r.sessions[id];var line:=U.row(identity)
		U.label(line,"%s / %s" % [id,item.device],13)
		var revoke:=U.button(line,"失効する" if item.active else "失効済み","RecoveryRevoke_"+str(id),U.send.bind(d,KIND,"revoke_session",{"target":id}),"close")
		revoke.disabled=not bool(item.active)
	var connection:=U.panel(access,"本番の接続制御")
	var isolate:=U.button(connection,"本番への接続を停止","RecoveryIsolate",U.send.bind(d,KIND,"isolate_network"),"stop")
	isolate.disabled=bool(r.network_isolated)
	_services(d,testing,r)
	var publish:=U.panel(testing,"試験した編集版を本番へ")
	var buttons:=U.row(publish)
	var apply:=U.button(buttons,"本番へ反映","RecoveryPublish",U.send.bind(d,KIND,"restore_business"),"copy")
	apply.disabled=not bool(r.network_isolated) or not bool(r.business_test.get("running",false)) or int(r.business_test.get("revision",-1))!=int(r.stage_revision)
	apply.tooltip_text="本番接続を停止し、現在の編集版で業務試験を実施してから反映します。"
	var reconnect:=U.button(buttons,"接続を再開して確認","RecoveryReconnect",U.send.bind(d,KIND,"reconnect_business"),"refresh")
	reconnect.disabled=r.staged.is_empty() or int(r.published_revision)!=int(r.stage_revision)
	var production:=U.table(publish,"RecoveryProduction",["本番ファイル","現在の内容"],110)
	for field in ["ledger","startup"]:U.table_row(production,[field,_summary(str(r.production.get(field,"")))],{"file":field,"bytes":r.production.get(field,"")})
	U.button(publish,"本番ファイルの原文","RecoveryShowProduction",U.choose.bind(d,KIND,"show_production",not bool(s.get("show_production",false))),"file")
	if bool(s.get("show_production",false)):
		for field in ["ledger","startup"]:U.label(publish,field,13,UI.MUTED);_raw(publish,str(r.production.get(field,"")),"RecoveryLive_"+field)
	U.button(body,"操作履歴","RecoveryShowHistory",U.choose.bind(d,KIND,"show_history",not bool(s.get("show_history",false))),"clock")
	if bool(s.get("show_history",false)):U.observations(body,data.observations)
