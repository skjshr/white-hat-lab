extends Control
## Receipt-shaped attachment and two recorded customer scores, not live metrics.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("243641")
const BLUE := Color("0f6cbd")
const RED := Color("a82f33")
var data: Dictionary = {}
var factor := 1.0
var fields: Dictionary = {}

func setup(reply: Dictionary, scale: float) -> void:
	data=reply.duplicate(true); factor=scale; name="MailReceivedSheet"; set_meta("delivery",data.duplicate(true)); size_flags_horizontal=Control.SIZE_EXPAND_FILL; custom_minimum_size.y=107*factor; mouse_filter=Control.MOUSE_FILTER_IGNORE
	_field("MailReceivedStatus","✓ 受取確認" if bool(data.confirmed) else "? 内訳なし",14)
	_field("MailReceivedCount","確認内訳 %d 件" % data.checks.size() if not data.checks.is_empty() else "? 記録なし",11)
	_field("MailDeliveryTiming",{"on_time":"◷ 期限内","late":"◷ 期限超過","rework":"↻ 手戻り"}.get(str(data.rating),"? 納期の記録なし"),13)
	var known: bool = (data.before is int or data.before is float) and (data.after is int or data.after is float)
	_field("MailCustomerScores","顧客評価   %d → %d" % [int(data.before),int(data.after)] if known else "顧客評価   ? → ?",15)
	var event: Dictionary=data.event
	_field("MailNextContact",{"paused":"Ⅱ 次の相談を保留","requested":"✉ 次の相談あり","resumed":"▶ 相談を再開","fulfilled":"✓ 相談の仕事を完了","cancelled":"Ⅱ 相談を保留"}.get(str(event.get("kind","")),"次の相談 · 記録なし"),13)
	resized.connect(_layout)

func _field(id: String, text: String, points: int) -> void:
	var label := Label.new(); label.name=id; label.text=text; label.tooltip_text=text; label.clip_text=true; label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",UI.font(400)); label.add_theme_font_size_override("font_size",roundi(points*factor)); label.add_theme_color_override("font_color",INK); add_child(label); fields[id]=label
func _ready() -> void: _layout()
func _layout() -> void:
	var paper:=size.x*.29
	for spec in [["MailReceivedStatus",7,43,paper-14],["MailReceivedCount",7,68,paper-14],["MailDeliveryTiming",paper+30*factor,3,size.x-paper-30*factor],["MailCustomerScores",paper+30*factor,27,size.x-paper-30*factor],["MailNextContact",paper+30*factor,82,size.x-paper-30*factor]]:
		var label: Label=fields[str(spec[0])]; label.position=Vector2(float(spec[1])*factor if str(spec[0]) in ["MailReceivedStatus","MailReceivedCount"] else float(spec[1]),float(spec[2])*factor); label.size=Vector2(float(spec[3]),25*factor)
	queue_redraw()
func _draw() -> void:
	var f:=factor; var paper:=size.x*.29
	draw_colored_polygon(PackedVector2Array([Vector2(0,0),Vector2(paper-16*f,0),Vector2(paper,16*f),Vector2(paper,95*f),Vector2(0,95*f)]),Color("fffdf5"))
	draw_polyline(PackedVector2Array([Vector2(0,0),Vector2(paper-16*f,0),Vector2(paper,16*f),Vector2(paper,95*f),Vector2(0,95*f),Vector2(0,0)]),Color("bebfb7"),f,true)
	draw_colored_polygon(PackedVector2Array([Vector2(paper-16*f,0),Vector2(paper-16*f,16*f),Vector2(paper,16*f)]),Color("d5d4cb"))
	for line in 3: draw_line(Vector2(12*f,(15+line*8)*f),Vector2(paper-24*f,(15+line*8)*f),Color("c5c8c3"),f,true)
	draw_line(Vector2(paper+9*f,13*f),Vector2(paper+9*f,92*f),Color("c2d7e8"),2*f,true)
	for y in [13,44,92]: draw_circle(Vector2(paper+9*f,y*f),4*f,BLUE)
	var x:=paper+30*f; var w:=maxf(0,size.x-x-15*f)
	var known: bool=(data.before is int or data.before is float) and (data.after is int or data.after is float)
	for index in 2:
		var y: float=(59+index*13)*f; draw_line(Vector2(x,y),Vector2(x+w,y),Color("dfebf4"),7*f,true)
		if known:
			var value:=float(data.before) if index==0 else float(data.after)
			var color:=Color("94b5ce") if index==0 else RED if int(data.after)<int(data.before) else BLUE
			draw_line(Vector2(x,y),Vector2(x+w*clampf(value/100,0,1),y),color,7*f,true)
			for mark in [0,25,50,75,100]: draw_line(Vector2(x+w*mark/100,y-5*f),Vector2(x+w*mark/100,y+5*f),Color("b3c7d4"),f)
