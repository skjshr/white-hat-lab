extends RefCounted
const UI = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/network_request_visual.gd")
const Diagram = preload("res://scripts/network_request_diagram.gd")

static func render(d, parent: Node, url: String, firewall := false) -> void:
	var view: Dictionary = d.game.network_request_view(url)
	if not bool(view.get("available",false)): return
	var visual := Visual.project(view,url)
	var frame := PanelContainer.new(); frame.name="NetworkRequestContext"
	frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel",UI.style(Color("f4f7fa") if firewall else Color("f8f5f7"),Color("d7dce2"),10,7,3))
	parent.add_child(frame)
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",5);frame.add_child(body)
	var header := HBoxContainer.new();header.add_theme_constant_override("separation",10);body.add_child(header)
	var summary: Label=d._label(str(visual.summary),12,Color("714b67") if not firewall else Color("176398"))
	summary.name="NetworkRequestStatus";summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(summary)
	var client := str(d.game.state.get("contract",{}).get("client","顧客"))
	var target: Label=d._label(client+" · "+("会計" if "/accounting" in url else ("顧客一覧" if "/customers" in url else "販売")),11,Color("667484"))
	target.name="NetworkRequestTarget";target.autowrap_mode=TextServer.AUTOWRAP_OFF;target.size_flags_horizontal=Control.SIZE_SHRINK_END
	target.tooltip_text=url;header.add_child(target)
	var diagram := Diagram.new();body.add_child(diagram);diagram.configure(d,visual,view,firewall)
	if not bool(view.get("can_test",false)) and not d.game.current_done() and not firewall:
		body.add_child(d._label("検査するには顧客環境へ接続してください",11,Color("667484")))
	if not str(d.business_ui.get("network_error","")).is_empty():
		var error: Label=d._label(str(d.business_ui.network_error),12,Color("b42318"));error.name="NetworkRequestError";body.add_child(error)
	if view.get("rows",[]).is_empty(): return
	var details: VBoxContainer=d._disclosure(body,"実測の詳細")
	var text := TextEdit.new();text.name="NetworkRequestRaw";text.editable=false;text.custom_minimum_size.y=150
	var lines := PackedStringArray(["DAY %d %s" % [int(view.get("day",1)),str(view.get("clock",""))],url])
	for id in ["request","dns-check","business-check","admin-check"]:
		lines.append("$ "+str(view.get("commands",{}).get(id,""))+"\n"+str(view.get("outputs",{}).get(id,"")))
	text.text="\n\n".join(lines);details.add_child(text)
