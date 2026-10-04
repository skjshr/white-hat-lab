extends Control
## Native buttons and drawn edges share a layout; only saved evidence colors it.
const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const MUTED := Color("667484")
const PASS := Color("247046")
const FAIL := Color("b42318")
const STALE := Color("916000")
var projected: Dictionary = {}
var accent := Color("714b67")
var scale_factor := 1.0
var nodes: Dictionary = {}
var business_lane := Rect2()
var admin_lane := Rect2()

class StateMark extends Control:
	var state := "unknown"
	var ink := Color("667484")
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x,size.y)*0.39
		match state:
			"pass":
				draw_circle(c,r,ink,false,1.5,true)
				draw_polyline(PackedVector2Array([c+Vector2(-r*.5,0),c+Vector2(-r*.1,r*.4),c+Vector2(r*.55,-r*.4)]),ink,2,true)
			"blocked":
				var shape := PackedVector2Array([c+Vector2(-r,-r*.7),c+Vector2(0,-r),c+Vector2(r,-r*.7),c+Vector2(r*.8,r*.45),c+Vector2(0,r),c+Vector2(-r*.8,r*.45),c+Vector2(-r,-r*.7)])
				draw_polyline(shape,ink,1.8,true)
				draw_polyline(PackedVector2Array([c+Vector2(-r*.5,0),c+Vector2(-r*.1,r*.4),c+Vector2(r*.55,-r*.4)]),ink,2,true)
			"fail":
				draw_circle(c,r,ink,false,1.5,true)
				draw_line(c-Vector2.ONE*r*.42,c+Vector2.ONE*r*.42,ink,2,true)
				draw_line(c+Vector2(-1,1)*r*.42,c+Vector2(1,-1)*r*.42,ink,2,true)
			"stale":
				draw_circle(c,r,ink,false,1.5,true)
				draw_line(c,c+Vector2(0,-r*.65),ink,1.8,true)
				draw_line(c,c+Vector2(r*.5,r*.2),ink,1.8,true)
			_:
				draw_arc(c,r,0,TAU,24,ink,1.3,true)
				draw_string(ThemeDB.fallback_font,c+Vector2(-4,5),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)

func configure(d, value: Dictionary, view: Dictionary, firewall: bool) -> void:
	projected = value.duplicate(true)
	scale_factor = clampf(float(d.game.settings.get("text_scale",1.0)),1.0,1.6)
	accent = Color("176398") if firewall else Color("714b67")
	name = "NetworkRequestDiagram"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var action: Callable = d._network_request_return if firewall else d._network_request_test
	var source: Button = d._button("",action)
	source.name = "NetworkRequestReturn" if firewall else "NetworkRequestTest"
	source.disabled = not bool(view.get("can_test",false)) if not firewall else false
	_add_node(d,"source",source,"device","業務へ戻る" if firewall else "業務を検査","同じ URL" if firewall else "%d分" % int(view.get("minutes",0)),"action")
	if source.disabled: source.get_node("Contents").modulate=Color(1,1,1,0.45)
	if firewall:
		_add_node(d,"dns",PanelContainer.new(),"network",str(value.dns.title),str(value.dns.detail),str(value.dns.state))
	else:
		var settings: Button = d._button("",func():d._network_request_settings())
		settings.name="NetworkRequestSettings"
		_add_node(d,"dns",settings,"network",str(value.dns.title),str(value.dns.detail)+" · 設定",str(value.dns.state))
	_add_node(d,"business",PanelContainer.new(),"file",str(value.business.title),str(value.business.detail),str(value.business.state))
	_add_node(d,"external",PanelContainer.new(),"network","外部 (WAN)","管理宛て","neutral")
	_add_node(d,"admin",PanelContainer.new(),"device",str(value.admin.title),str(value.admin.detail),str(value.admin.state))
	source.tooltip_text = "同じ顧客の業務画面へ戻ります" if firewall else "同じ業務 URL・名前解決・外部管理接続を実測します（%d分）" % int(view.get("minutes",0))
	if not firewall: nodes.dns.tooltip_text="名前解決 / サービスの設定を調べる"
	resized.connect(_layout)
	_layout()

func _add_node(d, id: String, node: Control, glyph: String, title: String, detail: String, state: String) -> void:
	nodes[id]=node;add_child(node)
	node.set_meta("network_state",state)
	var color := _color(state)
	var fill := Color("ffffff") if state!="stale" else Color("fff8e8")
	if node is Button:
		node.text=title
		node.focus_mode=Control.FOCUS_ALL
		node.add_theme_font_size_override("font_size",int(12*scale_factor))
		node.add_theme_color_override("font_color",Color("273747"))
		node.add_theme_color_override("font_hover_color",Color("273747"))
		node.add_theme_color_override("font_disabled_color",MUTED)
		for key in ["normal","hover","pressed","disabled"]:
			var box := UI.style(fill if key in ["normal","disabled"] else Color("edf2f7"),MUTED if key=="disabled" else accent,8,5,5)
			box.content_margin_top=32*scale_factor;box.content_margin_bottom=26*scale_factor
			node.add_theme_stylebox_override(key,box)
		node.add_theme_stylebox_override("focus",UI.style(Color(0,0,0,0),Color("0069c8"),8,5,5))
	else:
		node.add_theme_stylebox_override("panel",UI.style(fill,Color("d1d8df"),8,5,5))
		node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var body := VBoxContainer.new();body.name="Contents";body.mouse_filter=Control.MOUSE_FILTER_IGNORE
	node.add_child(body)
	if node is Button:
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		body.offset_left=6;body.offset_right=-6;body.offset_top=5;body.offset_bottom=-5
	body.add_theme_constant_override("separation",1)
	var icon_line := HBoxContainer.new();icon_line.alignment=BoxContainer.ALIGNMENT_CENTER;icon_line.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(icon_line)
	Glyph.add_to(icon_line,glyph,25*scale_factor,accent if state in ["action","neutral"] else color)
	if state not in ["action","neutral"]:
		var mark := StateMark.new();mark.state=state;mark.ink=color;mark.custom_minimum_size=Vector2.ONE*22*scale_factor;mark.mouse_filter=Control.MOUSE_FILTER_IGNORE;icon_line.add_child(mark)
	if node is Button:
		var spacer := Control.new();spacer.custom_minimum_size.y=22*scale_factor;spacer.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(spacer)
	else:
		var heading: Label=d._label(title,12,Color("273747"));heading.autowrap_mode=TextServer.AUTOWRAP_OFF;heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;heading.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(heading)
	var caption: Label=d._label(detail,11,color);caption.autowrap_mode=TextServer.AUTOWRAP_OFF;caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(caption)
	if id in ["dns","business","admin"]: caption.name="NetworkRequest"+id.capitalize()
	node.tooltip_text=title+" · "+detail

func _color(state: String) -> Color:
	if state in ["pass","blocked"]: return PASS
	if state=="fail": return FAIL
	if state=="stale": return STALE
	if state=="action": return accent
	return MUTED

func _layout() -> void:
	if nodes.is_empty(): return
	var h := 86.0*scale_factor
	if size.x<20:
		custom_minimum_size.y=h
		return
	var gap := 32.0
	var split := size.x>=730.0*minf(scale_factor,1.15)
	custom_minimum_size.y=h if split else h*2+12
	var bw := (size.x-24.0)*0.64 if split else size.x
	business_lane=Rect2(0,0,bw,h)
	admin_lane=Rect2(bw+24,0,size.x-bw-24,h) if split else Rect2(0,h+12,size.x,h)
	var node_w := (bw-gap*2)/3.0
	for index in 3:
		var id: String=["source","dns","business"][index]
		nodes[id].position=Vector2(index*(node_w+gap),0);nodes[id].size=Vector2(node_w,h)
	var admin_w := (admin_lane.size.x-gap)/2.0
	for index in 2:
		var id: String=["external","admin"][index]
		nodes[id].position=admin_lane.position+Vector2(index*(admin_w+gap),0);nodes[id].size=Vector2(admin_w,h)
	queue_redraw()

func _draw() -> void:
	if nodes.is_empty() or size.x<20: return
	_edge(nodes.source,nodes.dns,str(projected.dns.edge_state))
	_edge(nodes.dns,nodes.business,str(projected.business.edge_state))
	_edge(nodes.external,nodes.admin,str(projected.admin.edge_state))
	if admin_lane.position.y==0:
		draw_line(Vector2(admin_lane.position.x-12,8),Vector2(admin_lane.position.x-12,admin_lane.size.y-8),Color("d9dfe5"),1)

func _edge(from: Control, to: Control, state: String) -> void:
	var start := from.position+Vector2(from.size.x,from.size.y/2)
	var end := to.position+Vector2(0,to.size.y/2)
	var color := _color(state)
	if state in ["pass","blocked"]:
		draw_line(start,end,color,2.5,true)
		if state=="blocked": draw_line(end+Vector2(-5,-9),end+Vector2(-5,9),color,3,true)
		else: draw_polyline(PackedVector2Array([end+Vector2(-7,-5),end,end+Vector2(-7,5)]),color,2,true)
	elif state=="fail":
		var middle := (start+end)/2
		draw_line(start,middle-Vector2(6,0),color,2,true)
		draw_dashed_line(middle+Vector2(6,0),end,MUTED,1.5,3,true)
		draw_line(middle-Vector2(4,4),middle+Vector2(4,4),color,2,true)
		draw_line(middle+Vector2(-4,4),middle+Vector2(4,-4),color,2,true)
	else: draw_dashed_line(start,end,color,1.5,4,true)
