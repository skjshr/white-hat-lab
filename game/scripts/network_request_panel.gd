extends RefCounted
const UI = preload("res://scripts/ui_theme.gd")

static func render(d, parent: Node, url: String, firewall := false) -> void:
	var view: Dictionary = d.game.network_request_view(url)
	if not bool(view.get("available",false)): return
	var frame := PanelContainer.new()
	frame.name = "NetworkRequestContext"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel",UI.style(Color("f0f5fa"),Color("c7d5e3"),10,8,3))
	parent.add_child(frame)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",6); frame.add_child(body)
	var request: Label = d._label("依頼の再現  ·  "+url,12,Color("40546a"))
	request.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(request)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation",8); body.add_child(actions)
	var status := "未観測 · 同じ業務と外部管理接続を実際に検査します"
	if str(view.status)=="stale": status = "古い観測 · 設定またはデータが変わりました。再検査が必要です"
	elif str(view.status)=="current": status = "前回の実測  DAY %d %s · %s" % [int(view.get("day",1)),str(view.get("clock","")),"業務と管理制限を確認" if bool(view.get("passed",false)) else "未解決の結果があります"]
	var summary: Label = d._label(status,13,Color("40546a")); summary.name = "NetworkRequestStatus"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(summary)
	if firewall:
		var back: Button = d._button("同じ業務へ戻って確認",func():d._network_request_return())
		back.name = "NetworkRequestReturn"; actions.add_child(back)
	else:
		var test: Button = d._button("業務と管理制限を検査（%d分）" % int(view.minutes),func():d._network_request_test())
		test.name = "NetworkRequestTest"; test.disabled = not bool(view.get("can_test",false)); actions.add_child(test)
		var settings: Button = d._button("関連する設定を調べる",func():d._network_request_settings())
		settings.name = "NetworkRequestSettings"; actions.add_child(settings)
		if not bool(view.get("can_test",false)) and not d.game.current_done():
			var connect: Label = d._label("顧客環境に接続してから検査してください。",12,Color("40546a")); connect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(connect)
	if not str(d.business_ui.get("network_error","")).is_empty():
		var error: Label = d._label(str(d.business_ui.network_error),13,Color("b42318")); error.name = "NetworkRequestError"; error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(error)
	if view.get("rows",[]).is_empty(): return
	var outcomes := HFlowContainer.new(); outcomes.add_theme_constant_override("h_separation",18); body.add_child(outcomes)
	for row in view.rows:
		var current: bool = str(view.status)=="current"
		var color := Color("40546a") if not current else (Color("2f7d4a") if bool(row.passed) else Color("b42318"))
		var result: Label = d._label(str(row.label)+"："+str(row.detail),12,color)
		result.name = "NetworkRequest"+str(row.id).capitalize()
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; result.custom_minimum_size.x = 200; outcomes.add_child(result)
	var details: VBoxContainer = d._disclosure(body,"実行したリクエストと結果")
	var text := TextEdit.new(); text.name = "NetworkRequestRaw"; text.editable = false; text.custom_minimum_size.y = 150
	var lines := PackedStringArray()
	for id in ["request","dns-check","business-check","admin-check"]:
		lines.append("$ "+str(view.get("commands",{}).get(id,""))+"\n"+str(view.get("outputs",{}).get(id,"")))
	text.text = "\n\n".join(lines); details.add_child(text)
