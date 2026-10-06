extends Control
## Pure drawing of access objects and the customer's retained invoice.
const UI=preload("res://scripts/ui_theme.gd")
const INK=Color("242a30")
const MUTED=Color("68747e")
const LINE=Color("b7c3cb")
const BLUE=Color("176dae")
const GREEN=Color("237457")
const RED=Color("b3463b")
const PURPLE=Color("714b67")
var mode:="identity"
var model:Dictionary={}
var factor:=1.0
var selected:=""
var callback:Callable
var objects:Dictionary={}
var timeline_points:Dictionary={}
var timeline_headers:Array=[]

func configure(kind:String,value:Dictionary,scale:float,selection:String,action:Callable) -> void:
	mode=kind;model=value.duplicate(true);factor=scale;selected=selection;callback=action
	name="SaasIdentityCanvas" if mode=="identity" else "SaasTimelineCanvas" if mode=="timeline" else "SaasInvoiceCanvas"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL;mouse_filter=Control.MOUSE_FILTER_IGNORE
	if mode=="identity":
		for app in model.get("apps",[]):
			for part in ["app","consent","session","data"]:_object(str(app.get("id","")),part)
	elif mode=="timeline":
		for lane in model.get("lanes",[]):
			for point in lane.get("events",[]):
				var id:=str(point.get("id",""));timeline_points[id]=point
				_object(id,"record")
	resized.connect(_layout);_layout.call_deferred()

func _object(id:String,part:String) -> void:
	var button:=Button.new();button.name="Saas"+part.capitalize()+"_"+id.replace("-","_")
	button.set_meta("app",id);button.set_meta("part",part)
	button.tooltip_text="原記録を開く / "+id if mode=="timeline" else "対象を選択 / "+id+" / "+part
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed"]:button.add_theme_stylebox_override(state,UI.style(Color.TRANSPARENT if state=="normal" else Color("e7f0f5"),Color.TRANSPARENT,0,0,2))
	button.add_theme_stylebox_override("focus",UI.style(Color.TRANSPARENT,BLUE,0,0,2))
	button.pressed.connect(func():callback.call(id,part));add_child(button);objects[id+":"+part]=button
	button.draw.connect(_draw_timeline_point.bind(button,id) if mode=="timeline" else _draw_object.bind(button,id,part))

func _layout() -> void:
	if size.x<=0:return
	if mode=="timeline":
		timeline_headers=[]
		var columns:=maxi(1,floori(size.x/(142*factor)))
		var width:=size.x/columns;var y:=8*factor
		for lane in model.get("lanes",[]):
			timeline_headers.append({"text":str(lane.get("label","")),"y":y+16*factor})
			y+=28*factor
			var index:=0
			for point in lane.get("events",[]):
				_place(str(point.get("id","")),"record",Rect2((index%columns)*width+4*factor,y+(index/columns)*98*factor,width-8*factor,89*factor))
				index+=1
			y+=ceili(float(index)/columns)*98*factor+18*factor
		custom_minimum_size.y=y
	elif mode=="identity":
		var index:=0
		for app in model.get("apps",[]):
			var id:=str(app.get("id",""));var y:=(6+index*116)*factor
			_place(id,"app",Rect2(76*factor,y,size.x-87*factor,26*factor))
			_place(id,"consent",Rect2(83*factor,y+30*factor,100*factor,75*factor))
			_place(id,"session",Rect2(size.x*0.45,y+28*factor,126*factor,80*factor))
			_place(id,"data",Rect2(size.x-123*factor,y+27*factor,112*factor,86*factor))
			index+=1
		custom_minimum_size.y=(maxi(1,index)*116+16+(57 if int(model.get("leaked_rows",0))>0 else 0))*factor
	else:custom_minimum_size.y=280*factor
	queue_redraw()

func _place(id:String,part:String,rect:Rect2) -> void:
	var item:Control=objects[id+":"+part];item.position=rect.position;item.size=rect.size

func _text(control:Control,value:String,at:Vector2,points:int,color:Color=INK,width:float=-1) -> void:
	control.draw_string(control.get_theme_default_font(),at,value,HORIZONTAL_ALIGNMENT_LEFT,width,roundi(points*factor),color)

func _draw_object(button:Button,id:String,part:String) -> void:
	var app:Dictionary={}
	for item in model.get("apps",[]):
		if str(item.get("id",""))==id:app=item;break
	if app.is_empty():return
	var accent:=BLUE if id==selected else MUTED
	match part:
		"app":
			_text(button,id+"  "+str(app.get("label","")),Vector2(4,20)*factor,14,INK,button.size.x-10*factor)
			if id==selected:button.draw_line(Vector2(4,24)*factor,Vector2(button.size.x-4*factor,24*factor),BLUE,2*factor)
		"consent":
			var active:=bool(app.get("consent",false));var center:=Vector2(43,25)*factor
			button.draw_rect(Rect2(center-Vector2(14,13)*factor,Vector2(28,26)*factor),Color("e7edf1"))
			button.draw_line(center-Vector2(27,0)*factor,center-Vector2(14,0)*factor,accent,2*factor,true)
			button.draw_line(center+Vector2(14 if active else 22,0)*factor,center+Vector2(30,0)*factor,accent,2*factor,true)
			for dy in [-6,6]:button.draw_line(center+Vector2(7,dy)*factor,center+Vector2(18 if active else 14,dy)*factor,accent,2*factor,true)
			_text(button,"同意",Vector2(29,54)*factor,14,INK)
			_text(button,"✓ 有効" if active else "× 撤回",Vector2(20,72)*factor,14,GREEN if active else MUTED)
		"session":
			var active:=bool(app.get("session",false));var ticket:=Rect2(Vector2(4,4)*factor,Vector2(115,38)*factor)
			button.draw_rect(ticket,Color("e8f1f6") if active else Color("eef0f1"));button.draw_rect(ticket,accent,false,1.5*factor)
			for x in [4,119]:button.draw_circle(Vector2(x,23)*factor,5*factor,Color.WHITE)
			button.draw_dashed_line(Vector2(26,8)*factor,Vector2(26,39)*factor,accent,factor,3*factor,true)
			_text(button,"接続券",Vector2(38,28)*factor,14,INK)
			_text(button,"✓ 発行済み" if active else "× 失効",Vector2(15,62)*factor,14,GREEN if active else MUTED)
			_text(button,str(app.get("session_id","")),Vector2(6,79)*factor,14,MUTED,button.size.x-10*factor)
		"data":
			var rect:=Rect2(Vector2(14,12)*factor,Vector2(68,37)*factor)
			button.draw_rect(rect,Color("eef1f2"));button.draw_arc(Vector2(48,12)*factor,34*factor,0,PI,24,accent,1.5*factor,true)
			button.draw_line(Vector2(14,12)*factor,Vector2(14,47)*factor,accent,1.5*factor,true);button.draw_line(Vector2(82,12)*factor,Vector2(82,47)*factor,accent,1.5*factor,true)
			button.draw_line(Vector2(14,49)*factor,Vector2(82,49)*factor,accent,1.5*factor,true)
			_text(button,str(app.get("resource","資料")),Vector2(17,66)*factor,14,INK,button.size.x-21*factor)
			_text(button,str(app.get("measurement","? 未実測")),Vector2(2,84)*factor,14,MUTED if not bool(app.get("fresh",false)) else GREEN if int(app.get("status",0))==200 else RED,button.size.x-4*factor)

func _arrow(from:Vector2,to:Vector2,color:Color,solid:bool) -> void:
	if solid:draw_line(from,to,color,1.8*factor,true)
	else:draw_dashed_line(from,to,color,1.5*factor,5*factor,true)
	var direction:Vector2=(from-to).normalized();var normal:=Vector2(-direction.y,direction.x)
	for sign in [-1,1]:draw_line(to,to+(direction*6+normal*sign*4)*factor,color,1.5*factor,true)

func _draw_timeline_point(button:Button,id:String) -> void:
	var point:Dictionary=timeline_points[id];var status:=int(point.get("status",0));var color:=RED if status>=400 else BLUE
	var center:=Vector2(button.size.x*0.5,18*factor);var kind:=str(point.get("action",""))
	button.draw_circle(center,13*factor,Color.WHITE)
	if kind=="scheduled_export":
		var triangle:=PackedVector2Array([center+Vector2(0,-9)*factor,center+Vector2(10,8)*factor,center+Vector2(-10,8)*factor,center+Vector2(0,-9)*factor])
		button.draw_polyline(triangle,color,2*factor,true)
	elif kind in ["change_consent","change_session","session_reissued_by_sync"]:
		button.draw_rect(Rect2(center-Vector2(11,7)*factor,Vector2(22,14)*factor),color,false,2*factor)
		button.draw_line(center-Vector2(5,0)*factor,center+Vector2(5,-5 if bool(point.get("enabled",false)) else 5)*factor,color,2*factor,true)
	else:
		button.draw_rect(Rect2(center-Vector2(8,10)*factor,Vector2(16,20)*factor),color,false,1.5*factor)
		button.draw_line(center+Vector2(-4,-3)*factor,center+Vector2(4,-3)*factor,color,factor,true)
		button.draw_line(center+Vector2(-4,3)*factor,center+Vector2(4,3)*factor,color,factor,true)
	_text(button,"%d分 · %s%d" % [int(point.get("minute",0)),"× " if status>=400 else "✓ ",status],Vector2(4,47)*factor,11,MUTED,button.size.x-8*factor)
	_text(button,str(point.get("label","")),Vector2(4,66)*factor,12,INK,button.size.x-8*factor)
	_text(button,id,Vector2(4,84)*factor,10,BLUE,button.size.x-8*factor)

func _draw() -> void:
	if mode=="invoice":_invoice();return
	if mode=="timeline":
		draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
		for header in timeline_headers:_text(self,str(header.get("text","")),Vector2(4*factor,float(header.get("y",0))),14,INK,size.x-8*factor)
		for lane in model.get("lanes",[]):
			var prior:Control=null
			for point in lane.get("events",[]):
				var node:Control=objects[str(point.get("id",""))+":record"]
				if prior!=null and absf(prior.position.y-node.position.y)<factor:
					_arrow(prior.position+Vector2(prior.size.x*0.5+14*factor,18*factor),node.position+Vector2(node.size.x*0.5-14*factor,18*factor),LINE,true)
				prior=node
		return
	draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
	var count:int=model.get("apps",[]).size();var middle:=(maxi(1,count)*116)*factor*0.5
	draw_circle(Vector2(29,middle/factor-12)*factor,12*factor,Color("dce8ed"))
	draw_arc(Vector2(29,middle/factor+18)*factor,20*factor,PI,TAU,24,BLUE,2*factor,true)
	_text(self,str(model.get("user","")),Vector2(3,middle/factor+41)*factor,14,INK,72*factor)
	for app in model.get("apps",[]):
		var id:=str(app.get("id",""));var consent:Control=objects[id+":consent"];var session:Control=objects[id+":session"];var resource:Control=objects[id+":data"]
		var y:=consent.position.y+25*factor
		draw_line(Vector2(55*factor,middle),Vector2(55*factor,y),LINE,1.2*factor,true)
		_arrow(Vector2(55*factor,y),Vector2(consent.position.x+15*factor,y),LINE,false)
		var start:=Vector2(consent.position.x+74*factor,y);var end:=Vector2(session.position.x+2*factor,y)
		_arrow(start,end,LINE,bool(app.get("consent",false)))
		_text(self,"再発行",Vector2(start.x+3*factor,y-10*factor),14,MUTED,maxf(40*factor,end.x-start.x))
		start=Vector2(session.get_rect().end.x+2*factor,y);end=Vector2(resource.position.x+11*factor,y)
		var fresh:=bool(app.get("fresh",false));var status:=int(app.get("status",0))
		var color:=GREEN if fresh and status==200 else RED if fresh and status>=400 else LINE
		_arrow(start,end,color,fresh and status==200)
		if fresh and status>=400:
			var center:=(start+end)*0.5
			draw_circle(center,7*factor,Color.WHITE)
			for sign in [-1,1]:draw_line(center+Vector2(-4,-4*sign)*factor,center+Vector2(4,4*sign)*factor,color,2*factor,true)
	var leaked:=int(model.get("leaked_rows",0))
	if leaked>0:
		var y:=size.y-52*factor;draw_line(Vector2(76*factor,y-8*factor),Vector2(size.x-10*factor,y-8*factor),Color("d4c1bd"),factor,true)
		for offset in [8,4,0]:
			var paper:=Rect2(Vector2(84+offset,y/factor+offset)*factor,Vector2(26,32)*factor)
			draw_rect(paper,Color("fff0eb"));draw_rect(paper,RED,false,factor)
		_text(self,"外部に残るコピー  延べ%d行" % leaked,Vector2(132*factor,y+22*factor),14,RED,size.x-140*factor)

func _invoice() -> void:
	var paper:=Rect2(Vector2(4,4)*factor,Vector2(size.x-8*factor,size.y-8*factor))
	draw_rect(paper,Color.WHITE);draw_rect(paper,Color("d9d0d7"),false,factor)
	draw_line(Vector2(20,63)*factor,Vector2(size.x-20*factor,63*factor),PURPLE,2*factor,true)
	_text(self,str(model.get("id","BILL-001")),Vector2(24,38)*factor,23,PURPLE)
	_text(self,str(model.get("customer","")),Vector2(24,88)*factor,14,INK,size.x-48*factor)
	var y:=118*factor
	for line in model.get("lines",[]):
		_text(self,str(line.get("label","")),Vector2(24*factor,y),13,INK,size.x*0.60)
		_text(self,"¥%d" % int(line.get("amount",0)),Vector2(size.x*0.67,y),13,INK,size.x*0.30)
		y+=24*factor
	_text(self,"合計  ¥%d" % int(model.get("total",0)),Vector2(24,190)*factor,20,INK)
	var receipt:=str(model.get("receipt_id",""));var accepted:=not receipt.is_empty()
	var stamp:=Rect2(Vector2(maxf(24*factor,size.x-224*factor),208*factor),Vector2(minf(196*factor,size.x-48*factor),52*factor))
	draw_rect(stamp,GREEN if accepted else RED if int(model.get("status",0))>=400 else LINE,false,2*factor)
	_text(self,"✓ 顧客受付" if accepted else "× %d 未受付" % int(model.get("status",0)) if int(model.get("status",0))>=400 else "未送信",stamp.position+Vector2(10,21)*factor,14,GREEN if accepted else RED if int(model.get("status",0))>=400 else MUTED)
	_text(self,receipt if accepted else str(model.get("id","")),stamp.position+Vector2(10,42)*factor,11,INK,stamp.size.x-20*factor)
