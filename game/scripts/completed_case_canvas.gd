extends Control
## Saved delivery objects lead back into existing company work. No simulation here.
const UI = preload("res://scripts/ui_theme.gd")
const DOSSIER = preload("res://assets/ui/completed-case/dossier-v1.png")
const INK := Color("233d43")
const MUTED := Color("627b7d")
const TEAL := Color("287b74")
const LINE := Color("b1c9c5")

class Connector extends Control:
	func _draw() -> void:
		var y := size.y * 0.40
		draw_line(Vector2(2,y),Vector2(size.x-3,y),Color("95b4ae"),2,true)
		draw_line(Vector2(size.x-9,y-4),Vector2(size.x-3,y),Color("95b4ae"),2,true)
		draw_line(Vector2(size.x-9,y+4),Vector2(size.x-3,y),Color("95b4ae"),2,true)
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

class OutcomeDial extends Control:
	var score: Variant = null
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var center:=size*0.5
		var radius:=minf(size.x,size.y)*0.40
		draw_arc(center,radius,-PI*0.85,PI*0.85,60,Color("d4e2de"),5,true)
		if score!=null:
			draw_arc(center,radius,-PI*0.85,-PI*0.85+PI*1.7*clampf(float(score)/100.0,0,1),60,Color("287b74"),5,true)

class WorkBoard extends Control:
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var s:=minf(size.x/148.0,size.y/98.0)
		var origin:=(size-Vector2(148,98)*s)*0.5
		var board:=Rect2(origin+Vector2(12,7)*s,Vector2(124,75)*s)
		draw_style_box(UI.style(Color("e8f0ee"),Color("809c97"),5,5,5),board)
		for row in 3:
			var y:=origin.y+(22+20*row)*s
			draw_circle(Vector2(origin.x+29*s,y),4*s,Color("7d9995"))
			draw_line(Vector2(origin.x+43*s,y),Vector2(origin.x+(116-12*row)*s,y),Color("7d9995"),2*s,true)
		draw_line(origin+Vector2(57,93)*s,origin+Vector2(91,93)*s,Color("637f7c"),3*s,true)
		draw_line(origin+Vector2(74,82)*s,origin+Vector2(74,93)*s,Color("637f7c"),3*s,true)

var factor:=1.0
var view:Dictionary={}
var frame:MarginContainer
var content:VBoxContainer
var routes:BoxContainer

func configure(data:Dictionary, text_factor:float, actions:Dictionary) -> void:
	view=data.duplicate(true)
	factor=text_factor
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for child in get_children(): remove_child(child); child.queue_free()
	frame=MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: frame.add_theme_constant_override("margin_"+edge,roundi(14*factor))
	add_child(frame)
	content=VBoxContainer.new()
	content.add_theme_constant_override("separation",roundi(7*factor))
	frame.add_child(content)
	var heading:=HBoxContainer.new()
	content.add_child(heading)
	_label(heading,str(view.get("client","")) if not str(view.get("client","")).is_empty() else "完了した案件",22,INK,600).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var status_label:=_label(heading,"✓ 納品済み",13,TEAL,600)
	status_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	status_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_label(content,str(view.get("title","")),14,MUTED)
	routes=BoxContainer.new()
	routes.add_theme_constant_override("separation",roundi(6*factor))
	content.add_child(routes)
	var archive:=_object(routes,"CompletedArchive",actions.get("archive",Callable()),not bool(view.get("record_available",false)))
	var archive_box:=_body(archive)
	var image:=TextureRect.new()
	image.texture=DOSSIER
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size.y=104*factor
	archive_box.add_child(image)
	_center_label(archive_box,"納品記録を開く" if bool(view.get("record_available",false)) else "納品記録なし",16,INK,600)
	var day_text:="DAY %d" % int(view.day) if int(view.get("day",-1))>=0 else "日付の記録なし"
	var grade:=str(view.get("grade",""))
	_center_label(archive_box,day_text+(" · 評価 "+grade if not grade.is_empty() else ""),12,MUTED)
	_ignore(archive_box)
	_connector(routes)
	var customer:=_object(routes,"CompletedCustomer",actions.get("customer",Callable()),not bool(view.get("customer_available",false)))
	var customer_box:=_body(customer)
	var dial:=OutcomeDial.new()
	dial.custom_minimum_size.y=104*factor
	dial.score=view.get("satisfaction_after",null)
	customer_box.add_child(dial)
	var score:=_label(dial,str(int(dial.score)) if dial.score!=null else "?",30,INK,600)
	score.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	score.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	score.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_center_label(customer_box,"顧客との仕事へ" if bool(view.get("customer_available",false)) else "顧客記録なし",16,INK,600)
	var before:Variant=view.get("satisfaction_before",null)
	var after:Variant=view.get("satisfaction_after",null)
	_center_label(customer_box,"納品時の満足 %d → %d" % [int(before),int(after)] if before!=null and after!=null else "満足の記録なし",12,MUTED)
	_ignore(customer_box)
	_connector(routes)
	var workday:=_object(routes,"CompletedWorkday",actions.get("workday",Callable()))
	var workday_box:=_body(workday)
	var board:=WorkBoard.new()
	board.custom_minimum_size.y=104*factor
	workday_box.add_child(board)
	_center_label(workday_box,"今日の仕事へ",16,INK,600)
	var pending:Variant=view.get("pending_count",null)
	_center_label(workday_box,"残りの仕事 %d件" % int(pending) if pending!=null else "受注・保守・配分",12,MUTED)
	_ignore(workday_box)
	var line:=HSeparator.new()
	line.add_theme_stylebox_override("separator",UI.style(LINE,Color.TRANSPARENT,0,0,0))
	content.add_child(line)
	var billing:=HFlowContainer.new()
	billing.add_theme_constant_override("h_separation",roundi(14*factor))
	billing.add_theme_constant_override("v_separation",roundi(4*factor))
	content.add_child(billing)
	var invoice:Dictionary=view.get("invoice",{})
	var bill_text:="請求記録なし"
	if not invoice.is_empty():
		var status:=str({"draft":"請求未確定","posted":"入金待ち","paid":"入金済"}.get(str(invoice.get("status","")),"請求を確認"))
		bill_text="%s  ¥%s  → 請求書" % [status,_money(int(invoice.get("amount",0)))]
	var invoice_button:=Button.new()
	invoice_button.name="CompletedInvoice"
	invoice_button.text=bill_text
	invoice_button.icon=UI.symbol("receipt")
	invoice_button.add_theme_constant_override("icon_max_width",roundi(18*factor))
	invoice_button.add_theme_font_override("font",UI.font(500))
	invoice_button.add_theme_font_size_override("font_size",roundi(14*factor))
	invoice_button.add_theme_color_override("font_color",INK)
	invoice_button.add_theme_stylebox_override("normal",UI.style(Color("edf3ef"),LINE,8,5,3))
	invoice_button.add_theme_stylebox_override("hover",UI.style(Color("e0ede8"),TEAL,8,5,3))
	invoice_button.add_theme_stylebox_override("pressed",UI.style(Color("d4e6de"),TEAL,8,5,3))
	invoice_button.disabled=invoice.is_empty()
	invoice_button.pressed.connect(func(): _invoke(actions.get("invoice",Callable())))
	billing.add_child(invoice_button)
	var profit:Variant=view.get("profit",null)
	_label(billing,"案件利益 ¥"+_money(int(profit)) if profit!=null else "利益の記録なし",14,MUTED).autowrap_mode=TextServer.AUTOWRAP_OFF
	frame.minimum_size_changed.connect(_fit)
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout.call_deferred()
	_fit.call_deferred()
	queue_redraw()

func _fit() -> void:
	if not is_instance_valid(frame): return
	custom_minimum_size=Vector2(0,frame.get_combined_minimum_size().y)

func _layout() -> void:
	if not is_instance_valid(routes): return
	routes.vertical=size.x<620*factor
	for child in routes.get_children():
		if child is Connector: child.visible=not routes.vertical
	_fit.call_deferred()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("f7f9f6"))

func _object(parent:Node,node_name:String,action:Callable,disabled:=false) -> Button:
	var button:=Button.new()
	button.name=node_name
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.custom_minimum_size=Vector2(142,155)*factor
	button.disabled=disabled
	for pair in [["normal",Color.TRANSPARENT],["hover",Color("e9f1ee")],["pressed",Color("d9e9e4")],["disabled",Color.TRANSPARENT]]:
		button.add_theme_stylebox_override(pair[0],UI.style(pair[1],Color.TRANSPARENT,5,5,6))
	var focus:=UI.style(Color.TRANSPARENT,TEAL,5,5,6)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus",focus)
	button.pressed.connect(func(): _invoke(action))
	parent.add_child(button)
	return button

func _body(button:Button) -> VBoxContainer:
	var margin:=MarginContainer.new()
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,roundi(5*factor))
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",roundi(4*factor))
	margin.add_child(box)
	margin.minimum_size_changed.connect(func(): button.custom_minimum_size.y=maxf(155*factor,margin.get_combined_minimum_size().y))
	return box

func _connector(parent:Node) -> void:
	var link:=Connector.new()
	link.custom_minimum_size.x=22*factor
	parent.add_child(link)

func _label(parent:Node,text:String,font_size:int,tint:Color,weight:=400) -> Label:
	var label:=Label.new()
	label.text=text
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",UI.font(weight))
	label.add_theme_font_size_override("font_size",roundi(font_size*factor))
	label.add_theme_color_override("font_color",tint)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _center_label(parent:Node,text:String,font_size:int,tint:Color,weight:=400) -> Label:
	var label:=_label(parent,text,font_size,tint,weight)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	return label

func _ignore(parent:Control) -> void:
	parent.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in parent.get_children():
		if child is Control: _ignore(child)

func _invoke(action:Callable) -> void:
	if action.is_valid(): action.call()

func _money(value:int) -> String:
	var digits:=str(absi(value))
	var result:=""
	for index in digits.length():
		if index>0 and (digits.length()-index)%3==0: result+=","
		result+=digits[index]
	return ("−" if value<0 else "")+result
