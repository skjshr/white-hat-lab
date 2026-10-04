extends Button
## A native focusable object: the paper itself is the version-selection button.
var shape := "paper"
var document_kind := "text"
var selected := false
var interactive := false

func _ready() -> void:
	text="";focus_mode=Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	mouse_filter=Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	for state in ["normal","hover","pressed","focus","disabled"]:add_theme_stylebox_override(state,StyleBoxEmpty.new())
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw);mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw);focus_exited.connect(queue_redraw)

func _draw() -> void:
	var r:=Rect2(Vector2(4,3),size-Vector2(12,13))
	if r.size.x<30 or r.size.y<30:return
	if shape=="tray":
		var points:=PackedVector2Array([Vector2(2,24),Vector2(2,4),Vector2(114,4),Vector2(130,24),Vector2(size.x-3,24),Vector2(size.x-3,size.y-4),Vector2(2,size.y-4)])
		draw_colored_polygon(points,Color("273d43"));points.append(points[0]);draw_polyline(points,Color("7f9a9e"),2,true)
		draw_line(Vector2(8,size.y-16),Vector2(size.x-9,size.y-16),Color("59787e"),6,true)
		return
	if shape=="bundle":
		draw_rect(Rect2(Vector2(8,8),size-Vector2(12,12)),Color("111e22"))
		for offset in [6,3,0]:draw_rect(Rect2(Vector2(offset+2,offset+2),size-Vector2(12,12)),Color("c1c6bd"));draw_rect(Rect2(Vector2(offset+2,offset+2),size-Vector2(12,12)),Color("778980"),false,1)
		for y in [20,29,38]:draw_line(Vector2(10,y),Vector2(size.x-17,y),Color("778980"),1,true)
		return
	var edge:=Color("54c4bf") if selected else Color("cfaa6a") if document_kind=="damaged" else Color("c7c4b7")
	if interactive and (has_focus() or is_hovered()):edge=Color("70ded8")
	draw_rect(Rect2(r.position+Vector2(6,7),r.size),Color(0,0,0,0.3))
	var points:=PackedVector2Array([r.position,Vector2(r.end.x-22,r.position.y),Vector2(r.end.x,r.position.y+22),Vector2(r.end.x,r.end.y)])
	if document_kind=="damaged":
		for x in range(int(r.end.x)-12,int(r.position.x),-13):points.append(Vector2(x,r.end.y-(7 if int(x/13)%2==0 else 0)))
	points.append(Vector2(r.position.x,r.end.y))
	draw_colored_polygon(points,Color("f3e7ce") if document_kind=="damaged" else Color("f0eee3") if document_kind!="missing" else Color("c4d0ca"))
	points.append(r.position);draw_polyline(points,edge,3 if selected or has_focus() else 1.4,true)
	draw_polyline(PackedVector2Array([Vector2(r.end.x-22,r.position.y),Vector2(r.end.x-22,r.position.y+22),Vector2(r.end.x,r.position.y+22)]),edge,1.4,true)
	if selected:
		draw_circle(Vector2(r.position.x+13,r.position.y+13),5,Color("188d88"))
	if document_kind=="ledger":
		draw_line(Vector2(18,size.y*0.31),Vector2(size.x-23,size.y*0.31),Color("d4d3c6"),1,true)
		draw_line(Vector2(18,size.y*0.62),Vector2(size.x-23,size.y*0.62),Color("d4d3c6"),1,true)
	if document_kind=="damaged":
		var crack_scale:=minf(1.0,maxf(0.0,r.size.y-8)/104.0)
		draw_polyline(PackedVector2Array([r.position+Vector2(6,49)*crack_scale,r.position+Vector2(16,64)*crack_scale,r.position+Vector2(7,81)*crack_scale,r.position+Vector2(19,99)*crack_scale]),Color("b08a52"),3,true)
