extends RefCounted
## Purpose-specific work surfaces. All figures come from the public observed view.
const UI=preload("res://scripts/ui_theme.gd")
const ACCENTS={"advanced-cloud":"7157a5","advanced-malware":"b36920","advanced-detection":"276bb1","advanced-ddos":"b25158","advanced-api":"387672","advanced-supplychain":"5263a2"}
const STAGES={"advanced-cloud":["接続と取得","取得履歴","検証"],"advanced-malware":["実験台","端末と隔離","検証"],"advanced-detection":["ルール編集","イベントと再生","検証"],"advanced-ddos":["トラフィック","管理記録","検証"],"advanced-api":["要求と応答","修正と再試験","業務仕様","検証"],"advanced-supplychain":["ビルド工程","成果物と配布","原記録","検証"]}

static func state(d) -> Dictionary:
	return d.advanced_ui[str(d.game.state.advanced.case_id)]

static func accent(d) -> Color:
	return Color(ACCENTS.get(str(d.game.state.advanced.case_id),"246b72"))

static func change_stage(d, index: int) -> void:
	var u: Dictionary=state(d)
	u.stage=index; u.scroll=0
	d._save_session(false)
	if d.widgets.has("advanced"): d.widgets.advanced.signature=""; d.widgets.advanced.scroll.scroll_vertical=0
	d._refresh_advanced()

static func caption(parent: Node, value: String, color:=Color("263c4c")) -> Label:
	var label:=Label.new(); label.text=value; label.add_theme_color_override("font_color",color); parent.add_child(label); return label

static func chrome(d, parent: Node, data: Dictionary) -> void:
	var kind: String=str(d.game.state.advanced.case_id); var u: Dictionary=state(d)
	var strip:=HFlowContainer.new(); strip.name="SpecialistStatus"; strip.add_theme_constant_override("h_separation",18); parent.add_child(strip)
	for value in metrics(kind,data): caption(strip,str(value),accent(d))
	var navigation:=HFlowContainer.new(); navigation.name="SpecialistStages"; navigation.add_theme_constant_override("h_separation",5); parent.add_child(navigation)
	var labels: Array=STAGES[kind]; var selected: int=clampi(int(u.get("stage",0)),0,labels.size()-1); u.stage=selected
	for i in labels.size():
		var button:=Button.new(); button.name="SpecialistStage_"+str(i); button.text=str(labels[i]); button.custom_minimum_size.y=35; navigation.add_child(button)
		UI.os_navigation(button,i==selected,accent(d))
		button.pressed.connect(func(): change_stage(d,i))

static func metrics(kind: String, data: Dictionary) -> Array:
	match kind:
		"advanced-cloud":
			var active:=0
			for app in data.get("apps",{}).values(): active+=int(bool(app.session))
			var records: Array=data.get("requests",[])
			return ["接続 %d 件" % active,"取得試験 %d 回" % records.size(),"直近 HTTP %d" % int(records.back().get("status",0)) if not records.is_empty() else "資料へのアクセスは未確認"]
		"advanced-malware":
			var stopped:=0
			for endpoint in data.get("endpoints",[]): stopped+=int(not bool(endpoint.business_ok))
			return ["観測 %d 件" % data.get("observations",[]).size(),"隔離保管 %d 件" % data.get("quarantine",{}).size(),"通常業務：%d 端末停止" % stopped if stopped>0 else "通常業務：停止なし"]
		"advanced-detection":
			return ["入力 %d 件" % data.get("events",[]).size(),"一致 %d 件" % data.get("matched",[]).size() if data.get("replayed",false) else "現在の条件は未再生","誤検知 %d / 見逃し %d" % [int(data.get("false_positive",0)),int(data.get("false_negative",0))] if data.get("replayed",false) else "条件を変えたら再生して比較"]
		"advanced-ddos":
			var m: Dictionary=data.get("measurements",{})
			return ["処理容量 %d /s" % int(data.get("capacity",0)),"実負荷 %d /s" % int(m.get("load",0)) if not m.is_empty() else "負荷：未測定","注文：利用可" if m.get("checkout",false) else ("注文：利用不可" if not m.is_empty() else "注文：未確認")]
		"advanced-api":
			return ["送信 %d 回" % data.get("requests",[]).size(),"保全 %d 件" % data.get("evidence",{}).size(),"再試験：結果あり" if not data.get("retest",{}).is_empty() else "修正後の再試験：未実施"]
		"advanced-supplychain":
			return ["成果物 %d 版" % data.get("artifacts",{}).size(),"保留 %d 版" % data.get("blocked",[]).size(),"最新ビルド "+str(data.get("last_build","")) if not str(data.get("last_build","")).is_empty() else "再ビルド：未実施"]
	return []

static func stage_for(kind: String, node: Node) -> int:
	var title: String=str(node.get_meta("section_title","")); var name: String=str(node.name)
	if title=="検証記録": return STAGES[kind].size()-1
	match kind:
		"advanced-cloud": return 1 if title=="アプリから実際に返った資料" else 0
		"advanced-malware": return 1 if title.begins_with("端末") or title=="隔離保管した実体" or name=="MalwareRescan" else 0
		"advanced-detection": return 1 if title=="再生されたイベント" else 0
		"advanced-ddos": return 1 if title in ["同時刻の管理経路","原記録を選んで保全"] else 0
		"advanced-api":
			if title=="試験用アカウントと業務仕様": return 2
			return 1 if title=="観測した境界を契約どおりに修正" or node.has_meta("api_validation") else 0
		"advanced-supplychain":
			if title=="原記録を選んで保全": return 2
			return 1 if title in ["3 · 成果物と実内容","4 · 配置先を選ぶ"] else 0
	return 0

static func compose(d, content: VBoxContainer, data: Dictionary) -> void:
	var kind: String=str(d.game.state.advanced.case_id); var u: Dictionary=state(d)
	var children: Array=content.get_children(); var pages: Array=[]
	var wide: bool=d.windows.advanced.size.x>=1180
	for i in STAGES[kind].size():
		var page:=VBoxContainer.new(); page.name="SpecialistPage_"+str(i); page.set_meta("workbench_stage",i); page.size_flags_horizontal=Control.SIZE_EXPAND_FILL; page.visible=i==int(u.stage); content.add_child(page); pages.append(page)
		if i==(1 if kind=="advanced-detection" else 0): visual(d,page,kind,data)
	var grids: Dictionary={}
	for child in children:
		var stage: int=stage_for(kind,child); var target: Node=pages[stage]
		# Two independent work columns keep controls beside their observed result.
		if wide and ((stage==0 and kind in ["advanced-malware","advanced-ddos","advanced-api","advanced-supplychain","advanced-cloud"]) or (stage==1 and kind=="advanced-supplychain")):
			if not grids.has(stage):
				var grid:=GridContainer.new(); grid.columns=2; grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL; grid.add_theme_constant_override("h_separation",12); grid.add_theme_constant_override("v_separation",10); target.add_child(grid); grids[stage]=grid
			target=grids[stage]
		content.remove_child(child); target.add_child(child)
		if child is Control: child.size_flags_horizontal=Control.SIZE_EXPAND_FILL

static func visual(d, parent: Node, kind: String, data: Dictionary) -> void:
	var flow:=HFlowContainer.new(); flow.name="SpecialistVisual"; flow.add_theme_constant_override("h_separation",10); flow.add_theme_constant_override("v_separation",7); parent.add_child(flow)
	if kind=="advanced-ddos":
		for request in data.get("requests",[]):
			var button:=Button.new(); button.name="TrafficRoute_"+str(request.id); button.text="%s  ·  %s\n%d 要求/秒 × %d 処理量" % [str(request.route),str(request.client),int(request.rate),int(request.cost)]; button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size=Vector2(250,58); flow.add_child(button)
			button.tooltip_text="この要求の経路を制御欄へ選択（設定はまだ変更しません）"
			button.pressed.connect(func(): state(d).waf_route=request.route; change_stage(d,0))
	elif kind=="advanced-supplychain":
		var steps: Array=[["入力","ソース + 依存物",0],["実行環境","工程・接続・署名",0],["成果物","%d 版" % data.get("artifacts",{}).size(),1],["配布先","orders-a / orders-b",1]]
		for i in steps.size():
			var button:=Button.new(); button.name="PipelineStep_"+str(i); button.text=str(steps[i][0])+"\n"+str(steps[i][1]); button.custom_minimum_size=Vector2(180,54); flow.add_child(button); button.pressed.connect(func(): change_stage(d,int(steps[i][2])))
			if i<steps.size()-1: caption(flow,"→",accent(d))
	elif kind=="advanced-cloud":
		for id in data.get("apps",{}):
			var app: Dictionary=data.apps[id]
			caption(flow,"%s  →  同意 %s  →  接続 %s  →  台帳" % [str(id),"有効" if app.consent else "撤回", "有効" if app.session else "失効"],accent(d))
	elif kind=="advanced-detection":
		for event in data.get("events",[]):
			var collected: bool=bool(data.get("sources",{}).get(str(event.source),false)); var matched: bool=event.id in data.get("matched",[])
			var button:=Button.new(); button.name="DetectionEvent_"+str(event.id); button.text=str(event.time)+"  "+str(event.process)+"\n"+("一致" if matched and data.get("replayed",false) else ("収集対象" if collected else "未収集")); button.custom_minimum_size=Vector2(210,52); flow.add_child(button)
			UI.os_navigation(button,matched and bool(data.get("replayed",false)),accent(d))
			button.tooltip_text="この観測のプロセスを条件へ転記（適用前の下書き）"
			button.pressed.connect(func(): state(d).rule_process=event.process; change_stage(d,0))
	else: flow.queue_free()
