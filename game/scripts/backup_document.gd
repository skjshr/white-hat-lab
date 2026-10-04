extends Control
## A document's outline also carries state; text labels remain in native controls.
var kind := "text"

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if kind.begins_with("guard-"):
		var state := kind.trim_prefix("guard-")
		var color := Color("43b653") if state in ["matched","preserved"] else Color("efc45d") if state in ["mismatch","changed"] else Color("94999f")
		var center := size/2
		if state in ["preserved","changed"]:
			draw_arc(center+Vector2(0,-4),7,PI,TAU,20,color,2,true)
			draw_rect(Rect2(center+Vector2(-10,-3),Vector2(20,14)),color,false,2)
			draw_line(center+Vector2(0,1),center+Vector2(0,6),color,2,true)
			if state=="changed":draw_line(center+Vector2(-12,12),center+Vector2(12,-12),color,2,true)
		else:
			draw_circle(center,11,color,false,2,true)
			if state=="matched":draw_polyline(PackedVector2Array([center+Vector2(-6,0),center+Vector2(-1,5),center+Vector2(7,-5)]),color,2,true)
			elif state=="mismatch":
				draw_line(center+Vector2(-5,-5),center+Vector2(5,5),color,2,true);draw_line(center+Vector2(-5,5),center+Vector2(5,-5),color,2,true)
		return
	var edge := Color("cb9c4d") if kind=="damaged" else Color("59636b")
	var r := Rect2(Vector2.ONE,size-Vector2.ONE*2)
	if r.size.x<20 or r.size.y<20:return
	var points := PackedVector2Array([r.position,Vector2(r.end.x-15,r.position.y),Vector2(r.end.x,r.position.y+15),r.end,Vector2(r.position.x,r.end.y)])
	draw_colored_polygon(points,Color("20272c") if kind!="missing" else Color("171d21"))
	points.append(r.position);draw_polyline(points,edge,1.5,true)
	draw_polyline(PackedVector2Array([Vector2(r.end.x-15,r.position.y),Vector2(r.end.x-15,r.position.y+15),Vector2(r.end.x,r.position.y+15)]),edge,1.5,true)
	if kind=="damaged":
		for y in range(10,int(size.y)-5,15):draw_line(Vector2(3,y),Vector2(10,y+7),edge,2,true)
	elif kind=="missing":
		for x in range(15,int(size.x)-12,12):draw_line(Vector2(x,size.y*0.65),Vector2(x+5,size.y*0.65),edge,1.5,true)
