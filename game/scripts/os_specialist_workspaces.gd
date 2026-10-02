extends RefCounted
## Specialist tools share application chrome, not their work objects or workflow.
const LAYOUT=preload("res://scripts/specialist_layout.gd")

const TITLES := {"advanced-cloud":"外部アプリの権限台帳","advanced-malware":"標本の実験台","advanced-detection":"検知ルールとイベント再生","advanced-ddos":"通信負荷と業務の可用性","advanced-api":"API 認可契約の検証","advanced-supplychain":"ビルドと配布の来歴"}
const PURPOSES := {"advanced-cloud":"利用申請・同意した権限・発行済み接続を照合し、実際の資料アクセスで確かめます。","advanced-malware":"隔離された模擬標本の条件を変え、観測した挙動から端末への対応を決めます。","advanced-detection":"入力イベント、収集元、条件を比較します。条件を変更したら再生結果は古くなります。","advanced-ddos":"要求の通過量と処理負荷を測定し、注文・閲覧を残す制限を試します。","advanced-api":"配布された試験アカウントで要求を送り、業務仕様と実応答の境界を比較します。","advanced-supplychain":"ソース → ビルド → 成果物 → 配置先を追い、再生成した版の実動作を確認します。"}

static func _kind(d) -> String:
	return str(d.game.state.advanced.get("case_id",d.game.state.advanced.get("kind","")))

static func _state(d) -> Dictionary:
	var kind: String=_kind(d)
	if not d.advanced_ui.get(kind) is Dictionary: d.advanced_ui[kind]={}
	return d.advanced_ui[kind]

static func build(d, parent: VBoxContainer) -> void:
	var margin:=MarginContainer.new(); margin.size_flags_vertical=Control.SIZE_EXPAND_FILL; parent.add_child(margin)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,14)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,10)
	var body := VBoxContainer.new(); body.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",7); margin.add_child(body)
	d.widgets.advanced={"family":_kind(d),"body":body,"signature":""}
	refresh(d)

static func refresh(d) -> void:
	if not d.widgets.has("advanced") or not is_instance_valid(d.widgets.advanced.get("body")): return
	var w: Dictionary=d.widgets.advanced; var u: Dictionary=_state(d); var view: Dictionary=d.game.advanced_view()
	var signature: String=JSON.stringify([view,u.get("stage",0),u.get("selection",""),u.get("result",{}),d.windows.advanced.size.x if d.windows.has("advanced") else d.size.x])
	if signature==str(w.get("signature","")): return
	w.signature=signature
	var body: VBoxContainer=w.body; var focused: Control=d.get_viewport().gui_get_focus_owner()
	var focus_name: String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	var caret: int=focused.caret_column if focused is LineEdit else 0
	var scroll_value: int=int(w.scroll.scroll_vertical) if is_instance_valid(w.get("scroll")) else int(u.get("scroll",0))
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	var header := HBoxContainer.new(); body.add_child(header)
	var title: Label=_label(header,str(TITLES.get(_kind(d),"専門作業")),20); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(header,"AdvancedVerify","検証",func():
		d.game.verify()
		_state(d).result={"message":"納品条件を満たしました。検証記録を確認して納品できます。" if d.game.can_deliver() else "追加確認が必要です。未確認の検証項目を確認してください。"}
		LAYOUT.change_stage(d,LAYOUT.STAGES[_kind(d)].size()-1))
	var deliver: Button=_button(header,"AdvancedDelivery","納品",func():
		if d.game.deliver(): d._show_app("receipt")
		else: _state(d).result={"message":"未確認の項目があります。検証と根拠を確認してください。"}; _redraw(d))
	deliver.disabled=not d.game.can_deliver()
	_label(body,str(PURPOSES.get(_kind(d),"")))
	var result: Dictionary=u.get("result",{})
	if not result.is_empty(): _label(body,str(result.get("message",d.game._advanced_result_message(result)))).name="SpecialistFeedback"
	var data: Dictionary=view.get("workspace",{})
	LAYOUT.chrome(d,body,data)
	var scroll := ScrollContainer.new(); scroll.name="SpecialistScroll"; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll); w.scroll=scroll
	var content := VBoxContainer.new(); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",12); scroll.add_child(content)
	match _kind(d):
		"advanced-cloud": _cloud(d,content,data)
		"advanced-malware": _malware(d,content,data)
		"advanced-detection": _detection(d,content,data)
		"advanced-ddos": _ddos(d,content,data)
		"advanced-api": _api(d,content,data)
		"advanced-supplychain": _supply(d,content,data)
	_checks(d,content,view)
	LAYOUT.compose(d,content,data)
	scroll.scroll_vertical=scroll_value
	scroll.get_v_scroll_bar().value_changed.connect(func(value): u.scroll=int(value))
	Callable(load("res://scripts/os_specialist_workspaces.gd"),"_restore_focus").call_deferred(d,focus_name,caret)

static func _restore_focus(d, node_name: String, caret: int) -> void:
	if not is_instance_valid(d) or d.current_app!="advanced" or node_name.is_empty(): return
	var node: Node=d.widgets.advanced.body.find_child(node_name,true,false)
	if node is Control and node.is_visible_in_tree():
		node.grab_focus()
		if node is LineEdit: node.caret_column=mini(caret,node.text.length())

static func _redraw(d) -> void:
	if d.widgets.has("advanced"): d.widgets.advanced.signature=""
	d._refresh_advanced()

static func _act(d, action: String, args: Dictionary={}) -> void:
	var previous_stage: int=int(_state(d).get("stage",0))
	var result: Dictionary=d.game.advanced_action(action,args)
	_state(d).result=result.duplicate(true)
	var observed: Dictionary=d.game.advanced_view().get("workspace",{})
	var result_control: String=""
	match _kind(d):
		"advanced-cloud":
			if action=="one_probe":
				_state(d).stage=1; _state(d).scroll=0
				if not observed.get("requests",[]).is_empty(): _state(d).cloud_request_id=observed.requests.back().id
		"advanced-detection":
			if action=="replay": _state(d).stage=1; _state(d).scroll=0
		"advanced-malware":
			if action in ["static_scan","execute_sandbox","compare_normal","derive_indicators"]:
				_state(d).observation_id=str(observed.get("observations",[]).size()); result_control="MalwareObservationDetail"
		"advanced-api":
			if action=="request":
				if not observed.get("requests",[]).is_empty(): _state(d).api_request_id=observed.requests.back().evidence_id
				result_control="ApiResponseDetail"
		"advanced-supplychain":
			if action=="build": _state(d).stage=1; _state(d).scroll=0; _state(d).artifact_id=str(observed.get("last_build",""))
	if int(_state(d).get("stage",0))!=previous_stage and is_instance_valid(d.widgets.advanced.get("scroll")): d.widgets.advanced.scroll.scroll_vertical=0
	d._save_session(false); _redraw(d)
	if not result_control.is_empty(): Callable(load("res://scripts/os_specialist_workspaces.gd"),"_focus_result").call_deferred(d,result_control)

static func _focus_result(d, id: String) -> void:
	if not is_instance_valid(d) or not d.widgets.has("advanced"): return
	await d.get_tree().process_frame
	if not is_instance_valid(d) or not d.widgets.has("advanced"): return
	var control: Control=d.widgets.advanced.body.find_child(id,true,false)
	if control!=null and control.is_visible_in_tree(): d.widgets.advanced.scroll.ensure_control_visible(control)

static func _label(parent: Node, text: String, font_size:=14) -> Label:
	var label := Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label)
	if font_size!=14: label.add_theme_font_size_override("font_size",roundi(float(label.get_theme_default_font_size())*float(font_size)/14.0))
	return label

static func _section(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.set_meta("section_title",title); parent.add_child(panel)
	var margin := MarginContainer.new(); panel.add_child(margin)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,10)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",8); margin.add_child(box); _label(box,title,17); return box

static func _button(parent: Node, id: String, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.name=id; button.text=text; button.custom_minimum_size.y=36; button.pressed.connect(callback); parent.add_child(button); return button

static func _actions(parent: Node) -> HFlowContainer:
	var flow := HFlowContainer.new(); flow.add_theme_constant_override("h_separation",8); flow.add_theme_constant_override("v_separation",6); parent.add_child(flow); return flow

static func _text(d, parent: Node, key: String, label: String, initial: String) -> LineEdit:
	var u: Dictionary=_state(d); if not u.has(key): u[key]=initial
	_label(parent,label)
	var edit := LineEdit.new(); edit.name="Spec_"+key; edit.text=str(u[key]); edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL; edit.custom_minimum_size.y=36
	edit.text_changed.connect(func(value): u[key]=value); parent.add_child(edit); return edit

static func _choice(d, parent: Node, key: String, label: String, values: Array, initial: String) -> OptionButton:
	var u: Dictionary=_state(d); if not u.has(key): u[key]=initial
	_label(parent,label)
	var select := OptionButton.new(); select.name="Spec_"+key; select.custom_minimum_size.y=36; select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for value in values:
		select.add_item(str(value)); select.set_item_metadata(select.item_count-1,str(value))
		if str(value)==str(u[key]): select.select(select.item_count-1)
	select.item_selected.connect(func(index): u[key]=select.get_item_metadata(index)); parent.add_child(select); return select

static func _toggle(d, parent: Node, key: String, label: String, initial: bool) -> CheckBox:
	var u: Dictionary=_state(d); if not u.has(key): u[key]=initial
	var check := CheckBox.new(); check.name="Spec_"+key; check.text=label; check.button_pressed=bool(u[key]); check.toggled.connect(func(value): u[key]=value); parent.add_child(check); return check

static func _table(d, parent: Node, id: String, columns: Array, rows: Array, select_key: String="") -> Tree:
	var tree := Tree.new(); tree.name=id; tree.columns=columns.size(); tree.hide_root=true; tree.column_titles_visible=true; tree.custom_minimum_size.y=clampf(36+rows.size()*31,110,240); tree.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tree.select_mode=Tree.SELECT_ROW
	for i in columns.size(): tree.set_column_title(i,str(columns[i])); tree.set_column_expand(i,true); tree.set_column_custom_minimum_width(i,70)
	var root: TreeItem=tree.create_item()
	for row in rows:
		var item: TreeItem=tree.create_item(root); item.set_metadata(0,row)
		for i in columns.size(): item.set_text(i,str(row.get("cells",[])[i])); item.set_tooltip_text(i,str(row.get("cells",[])[i]))
		if not select_key.is_empty() and str(row.get("id",""))==str(_state(d).get(select_key,"")):
			item.select(0); tree.scroll_to_item.call_deferred(item)
	if not select_key.is_empty():
		tree.item_selected.connect(func():
			var selected: TreeItem=tree.get_selected()
			if selected!=null: _state(d)[select_key]=str(selected.get_metadata(0).get("id","")); _redraw(d))
	parent.add_child(tree); return tree

static func _checks(d, parent: Node, view: Dictionary) -> void:
	var box: VBoxContainer=_section(parent,"検証記録")
	for check in view.get("checks",[]):
		var label: String=d.UI.copy(str(check.get("label_key","")),str(check.get("id","")))
		_label(box,("✓ " if bool(check.get("passed",false)) else "未確認 · ")+label)

static func _evidence(d, parent: Node, events: Array, evidence: Variant) -> void:
	var box: VBoxContainer=_section(parent,"原記録を選んで保全")
	var rows: Array=[]
	for row in events: rows.append({"id":str(row.id),"cells":[str(row.get("time","")),str(row.get("asset",row.get("source",""))),str(row.get("detail",""))]})
	_table(d,box,"SpecEvidence",["時刻","対象","観測"],rows,"evidence_id")
	var selected: String=str(_state(d).get("evidence_id",""))
	for event in events:
		if str(event.id)==selected:
			_label(box,"%s · %s · %s\n%s" % [selected,str(event.get("time","")),str(event.get("asset",event.get("source",""))),str(event.get("detail",""))])
			break
	var pin: Button=_button(box,"SpecEvidencePin","選択した原記録を保全",func(): _act(d,"pin",{"target":str(_state(d).get("evidence_id",""))}))
	pin.disabled=selected.is_empty()
	_label(box,"保全済み: %d 件" % evidence.size())

static func _cloud(d, parent: Node, data: Dictionary) -> void:
	var apps: Dictionary=data.get("apps",{})
	for id in apps:
		var grant: Dictionary=apps[id]; var box: VBoxContainer=_section(parent,"接続アプリ · "+str(id))
		var audit: Dictionary={}
		for row in data.get("audit",[]):
			if str(row.grant)==str(id): audit=row
		_label(box,"%s ／ %s ／ 利用部門 %s" % [str(audit.get("publisher","")),str(audit.get("permission","")),str(audit.get("owner",""))])
		_label(box,"利用申請: %s　承認者: %s\n同意: %s　発行済み接続: %s" % [str(audit.get("approved_change","")),str(audit.get("approved_by","")),"有効" if grant.consent else "撤回済み","有効" if grant.session else "失効済み"])
		var actions: HFlowContainer=_actions(box)
		_button(actions,"CloudRead_"+str(id),"このアプリで資料を取得",func(): _act(d,"one_probe",{"target":id}))
		_button(actions,"CloudGrant_"+str(id),"同意を撤回" if grant.consent else "同意を戻す",func(): _act(d,"disable_grant" if grant.consent else "restore_grant",{"target":id}))
		_button(actions,"CloudSession_"+str(id),"接続を失効" if grant.session else "接続を再発行",func(): _act(d,"revoke_app_session" if grant.session else "restore_app_session",{"target":id}))
		_button(actions,"CloudPin_"+str(id),"申請記録を保全",func(): _act(d,"pin",{"target":str(audit.get("id",""))}))
	var response: VBoxContainer=_section(parent,"アプリから実際に返った資料")
	var rows: Array=[]
	for row in data.get("requests",[]): rows.append({"id":str(row.id),"cells":[str(row.app),str(row.get("status",200 if row.allowed else 403)),str(row.get("body","旧記録：応答本文なし"))]})
	_table(d,response,"CloudResponses",["接続アプリ","応答","内容"],rows,"cloud_request_id")
	var history: Array=data.get("requests",[])
	var selected: String=str(_state(d).get("cloud_request_id",history.back().id if not history.is_empty() else ""))
	for row in history:
		if str(row.id)==selected: _label(response,"%s / HTTP %s\n%s" % [str(row.app),str(row.get("status",200 if row.allowed else 403)),str(row.get("body","旧記録：応答本文なし"))])
	_button(response,"CloudVerify","両アプリの現在の結果を検証",func(): _act(d,"verify"))

static func _detection(d, parent: Node, data: Dictionary) -> void:
	var box: VBoxContainer=_section(parent,"条件を組み立てる")
	var rule: Dictionary=data.get("rule",{}); var sources: Dictionary=data.get("sources",{})
	var flow: HFlowContainer=_actions(box)
	_toggle(d,flow,"source_endpoint","端末イベント",bool(sources.get("endpoint",false)))
	_toggle(d,flow,"source_network","通信イベント",bool(sources.get("network",false)))
	_toggle(d,flow,"notification","通知する",bool(data.get("notification",false)))
	_text(d,box,"rule_process","対象プロセス（* は全て）",str(rule.get("process","*")))
	_text(d,box,"rule_threshold","同じ端末・プロセスの5分以内の通信数",str(rule.get("network_threshold",1)))
	_text(d,box,"rule_exclusion","除外するプロセス（空欄は除外なし）",str(rule.get("exclusion","")))
	var actions: HFlowContainer=_actions(box)
	_button(actions,"DetectionApply","条件を適用",func():
		var u: Dictionary=_state(d)
		_act(d,"configure_rule",{"process":u.rule_process,"threshold":int(u.rule_threshold),"exclusion":u.rule_exclusion,"notification":u.notification,"sources":{"endpoint":u.source_endpoint,"network":u.source_network}}))
	_button(actions,"DetectionReplay","適用済み条件でイベントを再生",func(): _act(d,"replay"))
	_label(box,"適用中: %s / 通信 %s 以上 / 除外 %s" % [str(rule.get("process","")),str(rule.get("network_threshold",0)),str(rule.get("exclusion",""))])
	var results: VBoxContainer=_section(parent,"再生されたイベント")
	if bool(data.get("replayed",false)): _label(results,"誤検知 %d　見逃し %d　通知 %s" % [int(data.get("false_positive",0)),int(data.get("false_negative",0)),"送信済み" if bool(data.get("notified",false)) else "未送信"])
	else: _label(results,"現在の条件では未再生です。以前の結果を合格として扱いません。")
	var rows: Array=[]
	for event in data.get("events",[]):
		var state: String="未再生" if not bool(data.get("replayed",false)) else ("一致" if event.id in data.get("matched",[]) else "非一致")
		if not bool(sources.get(str(event.source),false)): state="未収集"
		rows.append({"id":event.id,"cells":[str(event.time),str(event.asset),str(event.process),state]})
	_table(d,results,"DetectionEvents",["時刻","端末","プロセス","結果"],rows)
	_button(results,"DetectionVerify","通知と検知結果を検証",func(): _act(d,"verify"))

static func _malware(d, parent: Node, data: Dictionary) -> void:
	var artifact: Dictionary=data.get("artifact",{})
	var box: VBoxContainer=_section(parent,"標本 · "+str(artifact.get("path","")))
	_label(box,"SHA-256 "+str(artifact.get("sha256","")))
	var sandbox: Dictionary=data.get("sandbox",{})
	_toggle(d,box,"sandbox_network","模擬ネットワークを有効にする",bool(sandbox.get("network",false)))
	_choice(d,box,"sandbox_profile","実行権限",["standard","restricted"],str(sandbox.get("profile","standard")))
	_text(d,box,"sandbox_date","実験日付 YYYY-MM-DD",str(sandbox.get("date","2026-09-21")))
	var actions: HFlowContainer=_actions(box)
	_button(actions,"MalwareConditions","実験条件を適用",func():
		var u: Dictionary=_state(d)
		_act(d,"configure_sandbox",{"network":u.sandbox_network,"profile":u.sandbox_profile,"date":u.sandbox_date}))
	_button(actions,"MalwareStatic","静的な痕跡を読む",func(): _act(d,"static_scan"))
	_button(actions,"MalwareRun","適用済み条件で実行",func(): _act(d,"execute_sandbox"))
	_button(actions,"MalwareNormal","通常の管理ツールと比較",func(): _act(d,"compare_normal"))
	_label(box,"適用中: %s / %s / 通信 %s" % [str(sandbox.get("date","")),str(sandbox.get("profile","")),str(sandbox.get("network",false))])
	var observations: VBoxContainer=_section(parent,"条件ごとの観測")
	var rows: Array=[]
	var index: int=0
	for observation in data.get("observations",[]):
		index+=1
		var condition: String="静的調査" if str(observation.mode)=="static" else str(observation.get("date",""))+" / "+str(observation.get("profile",""))
		var detail: String=str(observation.get("strings",[])) if str(observation.mode)=="static" else "process=%s / startup=%s / network=%s" % [str(observation.get("process","")),str(observation.get("startup",false)),str(observation.get("network",false))]
		rows.append({"id":str(index),"cells":[str(index),condition,detail]})
	var chosen: int=int(str(_state(d).get("observation_id",str(rows.size()))))-1
	if chosen>=0 and chosen<data.get("observations",[]).size():
		var record: Dictionary=data.observations[chosen]
		var detail: String="実験 %d · " % (chosen+1)
		if str(record.mode)=="static": detail+="静的調査\n"+"\n".join(record.get("strings",[]))
		else: detail+="%s / %s\nプロセス %s\n起動項目 %s · 外向き通信 %s" % [str(record.get("date","")),str(record.get("profile","")),str(record.get("process","")),"あり" if record.get("startup",false) else "なし","あり" if record.get("network",false) else "なし"]
		_label(observations,detail).name="MalwareObservationDetail"
	_table(d,observations,"MalwareObservations",["実験","条件","観測結果"],rows,"observation_id")
	var derive: HFlowContainer=_actions(observations)
	_button(derive,"MalwareDerive","観測から指標をまとめる",func(): _act(d,"derive_indicators"))
	_button(derive,"MalwareHunt","同じ指標を端末で調べる",func(): _act(d,"hunt_indicators"))
	_label(observations,"指標: "+str(data.get("indicators",[]))+"\n照合先: "+str(data.get("hunt_matches",[])))
	for endpoint in data.get("endpoints",[]):
		var ep_id: String=str(endpoint.id)
		var ep: VBoxContainer=_section(parent,"端末 · "+ep_id)
		var items: Array=[]
		for file in endpoint.files: items.append({"id":str(file.path),"cells":["ファイル",str(file.path),str(file.sha256)]})
		for process in endpoint.processes: items.append({"id":str(process.name),"cells":["実行中",str(process.name),"稼働"]})
		for startup in endpoint.startup: items.append({"id":str(startup.path),"cells":["起動項目",str(startup.path),"登録済み"]})
		_table(d,ep,"MalwareInventory_"+ep_id,["種類","名前・場所","現在の内容"],items)
		_label(ep,"通常管理業務: "+("稼働" if endpoint.business_ok else "停止"))
		var row: HFlowContainer=_actions(ep)
		_button(row,"MalwareFile_"+ep_id,"一致ファイルを隔離保管",func(): _act(d,"quarantine_file",{"target":ep_id}))
		_button(row,"MalwareProcess_"+ep_id,"対象プロセスを停止",func(): _act(d,"quarantine",{"target":ep_id}))
		_button(row,"MalwareStartup_"+ep_id,"関連起動項目を隔離",func(): _act(d,"quarantine_persistence",{"target":ep_id}))
	var store: Dictionary=data.get("quarantine",{})
	if not store.is_empty():
		var held: VBoxContainer=_section(parent,"隔離保管した実体")
		for id in store:
			_label(held,str(id))
			_button(held,"MalwareRestore_"+str(id).validate_node_name(),"この項目を元へ戻す",func(): _act(d,"restore_quarantined_item",{"target":id}))
	_button(parent,"MalwareRescan","端末を再検査し、通常業務も確かめる",func(): _act(d,"rescan"))

static func _ddos(d, parent: Node, data: Dictionary) -> void:
	var measure: VBoxContainer=_section(parent,"処理容量と通過した業務")
	var measured: Dictionary=data.get("measurements",{})
	if measured.is_empty(): _label(measure,"未測定。制限を変える前に現在の要求を測定してください。")
	else:
		var load_value: float=float(measured.get("load",0)); var capacity: float=float(data.get("capacity",0))
		_label(measure,"処理負荷 %.0f / 容量 %.0f work/s" % [load_value,capacity])
		var bar := ProgressBar.new(); bar.name="DdosCapacity"; bar.max_value=maxf(capacity,load_value); bar.value=load_value; bar.show_percentage=false; measure.add_child(bar)
		_label(measure,"注文 %s　商品一覧 %s　通常検索 %s" % [_available(measured.get("checkout",false)),_available(measured.get("catalog",false)),_available(measured.get("search",false))])
	_button(measure,"DdosMeasure","現在の要求を再生して測定",func(): _act(d,"measure",{"target":"environment"}))
	var requests: Array=[]
	for request in data.get("requests",[]): requests.append({"id":request.id,"cells":[str(request.route),str(request.client),str(request.rate)+" /s",str(request.cost)]})
	_table(d,measure,"DdosRequests",["経路","利用元","要求数","処理量/件"],requests)
	var box: VBoxContainer=_section(parent,"経路ごとの流量制御")
	var rule: Dictionary=data.get("rule",{})
	_choice(d,box,"waf_route","対象経路",["*","/search","/checkout","/catalog"],str(rule.get("route","*")))
	_choice(d,box,"waf_mode","動作",["count","limit","block"],str(rule.get("mode","count")))
	var u: Dictionary=_state(d); if not u.has("waf_limit"): u.waf_limit=int(rule.get("limit",100))
	_label(box,"通過上限（同じ要求群ごと / 秒）")
	var slider := HSlider.new(); slider.name="DdosLimit"; slider.min_value=0; slider.max_value=1000; slider.step=1; slider.value=float(u.waf_limit); box.add_child(slider)
	var value: Label=_label(box,str(int(u.waf_limit))+" / 秒")
	slider.value_changed.connect(func(amount): u.waf_limit=int(amount); value.text=str(int(amount))+" / 秒")
	_button(box,"DdosApply","このルールを適用",func(): _act(d,"apply_rule",{"target":"waf01","option":str(u.waf_route)+"|"+str(u.waf_mode)+"|"+str(int(u.waf_limit))}))
	_label(box,"適用中: "+str(rule.get("route",""))+" / "+str(rule.get("mode",""))+" / "+str(rule.get("limit",0)))
	var history: Array=[]
	for row in data.get("history",[]): history.append({"id":str(history.size()),"cells":[str(row.rule.route)+" / "+str(row.rule.mode)+" / "+str(row.rule.limit),str(row.result.load),_available(row.result.checkout)+" / "+_available(row.result.search)]})
	_table(d,box,"DdosHistory",["測定時のルール","負荷","注文 / 通常検索"],history)
	var incident: VBoxContainer=_section(parent,"同時刻の管理経路")
	var actions: HFlowContainer=_actions(incident)
	_button(actions,"DdosInspectSession","管理接続の原記録を確認",func(): _act(d,"inspect",{"target":"admin01"}))
	_button(actions,"DdosInspectTask","定期処理の原記録を確認",func(): _act(d,"inspect",{"target":"store01"}))
	var session: Dictionary=data.get("session",{}); var task: Dictionary=data.get("task",{})
	if not session.is_empty():
		_label(incident,"接続: "+JSON.stringify(session)); _button(incident,"DdosRevoke","表示した接続を失効",func(): _act(d,"revoke",{"target":"admin01","option":str(session.id)}))
	if not task.is_empty():
		_label(incident,"定期処理: "+JSON.stringify(task)); _button(incident,"DdosStopTask","表示した定期処理を停止",func(): _act(d,"disable_task",{"target":"store01","option":str(task.id)}))
	_evidence(d,parent,data.get("events",[]),data.get("evidence",{}))

static func _available(value: Variant) -> String:
	return "利用可" if bool(value) else "利用不可"

static func _api(d, parent: Node, data: Dictionary) -> void:
	var contract: VBoxContainer=_section(parent,"試験用アカウントと業務仕様")
	_label(contract,"社員は自社の請求を閲覧。承認は自社の承認担当。CSV取得は出力した本人に限定。これは検証環境の契約仕様です。")
	var actors: Array=["unauthenticated"]; var rows: Array=[]
	for id in data.get("users",{}):
		actors.append(id); var user: Dictionary=data.users[id]; rows.append({"id":id,"cells":[str(id),str(user.tenant),str(user.role)]})
	_table(d,contract,"ApiActors",["利用者","組織","役割"],rows)
	var request: VBoxContainer=_section(parent,"要求を作る")
	_choice(d,request,"api_actor","試験アカウント",actors,"alice")
	_choice(d,request,"api_operation","操作",["list","read","approve","export","download"],"list")
	_text(d,request,"api_resource","対象ID（一覧・応答で観測したIDを入力）","")
	_button(request,"ApiSend","要求を送信",func():
		var u: Dictionary=_state(d)
		_act(d,"request",{"target":str(u.api_resource),"option":str(u.api_actor)+"|"+str(u.api_operation)}))
	var history: VBoxContainer=_section(parent,"要求と応答を比較")
	var requests: Array=data.get("requests",[]); var records: Array=[]
	for item in requests: records.append({"id":item.evidence_id,"cells":[str(item.actor),str(item.operation)+" "+str(item.resource),str(int(item.response.status))]})
	_table(d,history,"ApiRequests",["利用者","要求","応答"],records,"api_request_id")
	var selected: String=str(_state(d).get("api_request_id",requests.back().evidence_id if not requests.is_empty() else ""))
	for item in requests:
		if str(item.evidence_id)!=selected: continue
		_label(history,"利用者 %s · %s %s\nHTTP %d\n%s" % [str(item.actor),str(item.operation),str(item.resource),int(item.response.status),str(item.response.body)]).name="ApiResponseDetail"
		var actions: HFlowContainer=_actions(history)
		_button(actions,"ApiPin","この要求と応答を保全",func(): _act(d,"pin",{"target":selected}))
		_button(actions,"ApiCopy","要求を入力欄へ複製",func():
			var u: Dictionary=_state(d); u.api_actor=item.actor; u.api_operation=item.operation; u.api_resource=item.resource; _redraw(d))
		break
	var policies: Dictionary=data.get("policy",{})
	if not policies.is_empty():
		var fix: VBoxContainer=_section(parent,"観測した境界を契約どおりに修正")
		for key in policies:
			var caption: String={"tenant":"組織境界","approval":"承認担当の権限","job_owner":"出力した本人の確認"}.get(key,str(key))
			_button(fix,"ApiPolicy_"+str(key),caption+" · "+("適用済み" if policies[key] else "適用する"),func(): _act(d,"set_policy",{"target":"api01","option":str(key)+"|enforce"}))
	var verify: HFlowContainer=_actions(parent); verify.set_meta("api_validation",true)
	_button(verify,"ApiRetest","保全した再現条件を再試験",func(): _act(d,"retest",{"target":"api01"}))
	_button(verify,"ApiBusiness","自社閲覧・正規承認・CSVを確認",func(): _act(d,"measure",{"target":"environment"}))
	if not data.get("retest",{}).is_empty(): _label(parent,"再試験の実応答: "+JSON.stringify(data.retest.results)).set_meta("api_validation",true)
	if not data.get("measurements",{}).is_empty(): _label(parent,"正常業務の実応答: "+JSON.stringify(data.measurements)).set_meta("api_validation",true)

static func _supply(d, parent: Node, data: Dictionary) -> void:
	var source: VBoxContainer=_section(parent,"1 · ビルド入力")
	_label(source,str(data.get("source",""))+"\n依存物: "+str(data.get("dependency","")))
	var build_box: VBoxContainer=_section(parent,"2 · ビルド実行環境")
	_button(build_box,"SupplyInspect","実行環境と変更記録を確認",func(): _act(d,"inspect",{"target":"build01"}))
	var pipeline: Dictionary=data.get("pipeline",{})
	if not pipeline.is_empty():
		_label(build_box,"追加工程: %s\n実行接続: %s\n署名鍵: %s" % [str(pipeline.hook),"有効" if pipeline.session else "失効",str(pipeline.signer)])
		var actions: HFlowContainer=_actions(build_box)
		_button(actions,"SupplyRevoke","実行接続を失効",func(): _act(d,"revoke",{"target":"build01","option":"runner-session-19"}))
		_button(actions,"SupplyRotate","署名鍵を更新",func(): _act(d,"rotate",{"target":"build01"}))
		_button(actions,"SupplyRemoveHook","追加工程を除く",func(): _act(d,"remove_hook",{"target":"build01"}))
	_button(build_box,"SupplyBuild","現在の入力と工程でビルド",func(): _act(d,"build",{"target":"build01"}))
	var registry: VBoxContainer=_section(parent,"3 · 成果物と実内容")
	var artifacts: Dictionary=data.get("artifacts",{}); var rows: Array=[]
	for id in artifacts:
		var artifact: Dictionary=artifacts[id]
		rows.append({"id":id,"cells":[str(id),str(artifact.signer)," → ".join(artifact.steps),"保留" if id in data.get("blocked",[]) else "配布候補"]})
	_table(d,registry,"SupplyArtifacts",["成果物","署名","実工程","状態"],rows,"artifact_id")
	var selected: String=str(_state(d).get("artifact_id",data.get("last_build","")))
	if artifacts.has(selected):
		var artifact: Dictionary=artifacts[selected]
		_label(registry,"%s\nSHA-256 %s\n%s" % [selected,str(artifact.bytes).sha256_text(),str(artifact.bytes)])
		_button(registry,"SupplyQuarantine","選択した成果物を配布保留",func(): _act(d,"quarantine",{"target":"registry01","option":selected}))
	var deployments: VBoxContainer=_section(parent,"4 · 配置先を選ぶ")
	for host in data.get("deployments",{}):
		_label(deployments,str(host)+" · 稼働版 "+str(data.deployments[host]))
		var deploy: Button=_button(deployments,"SupplyDeploy_"+str(host),"選択版 "+selected+" をこの配置先へ反映",func(): _act(d,"deploy",{"target":host,"option":selected}))
		deploy.disabled=not artifacts.has(selected)
	_button(deployments,"SupplyMeasure","両配置先の応答と外向き通信を測定",func(): _act(d,"measure",{"target":"environment"}))
	if not data.get("measurements",{}).is_empty(): _label(deployments,"実測: "+JSON.stringify(data.measurements.get("endpoints",{})))
	_evidence(d,parent,data.get("events",[]),data.get("evidence",{}))
