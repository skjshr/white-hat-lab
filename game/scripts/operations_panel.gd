extends RefCounted
const COPY = preload("res://scripts/ui_theme.gd")
const GAME_UI = preload("res://scripts/game_theme.gd")
const M = preload("res://scripts/management_ui.gd")

static func label(ui, host: Node, value: String, size: int = 16, color: Color = COPY.INK) -> Label:
	var node: Label = ui._label(value,size,color); node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;host.add_child(node);return node

static func button(ui, host: Node, key: String, action: Callable, id: String = "") -> Button:
	var node: Button=ui._button(COPY.copy(key),action);node.name=id if not id.is_empty() else key;node.custom_minimum_size.y=34;host.add_child(node);return node

static func flow(host: Node) -> HFlowContainer:
	var row:=HFlowContainer.new();row.add_theme_constant_override("h_separation",8);row.add_theme_constant_override("v_separation",6);host.add_child(row);return row

static func footer(ui) -> HBoxContainer:
	ui.modal_footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var row:=HBoxContainer.new();row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",8);ui.modal_footer.add_child(row);return row

static func box(ui, host: Node) -> VBoxContainer:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_theme_stylebox_override("panel",M.surface(M.PAPER,13,true));host.add_child(panel)
	var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",9);panel.add_child(body);return body

static func metric(ui, host: Node, key: String, value: String, id: String = "") -> void:
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.custom_minimum_size.x=170;host.add_child(column)
	label(ui,column,COPY.copy(key),13,COPY.MUTED)
	var node:=label(ui,column,value,27);if not id.is_empty():node.name=id

# Dispatch controls use one-line cells. Wrapped labels in a horizontal container
# can otherwise turn a narrow column into a full-height paragraph.
static func cell(ui, host: Node, value: String, width: float = 0, color: Color = GAME_UI.FOOTER, grow: bool = false) -> Label:
	var node: Label=ui._label(value,13,color)
	node.autowrap_mode=TextServer.AUTOWRAP_OFF
	node.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	node.clip_text=true
	node.custom_minimum_size.x=width
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL if grow else Control.SIZE_FILL
	node.tooltip_text=value
	host.add_child(node)
	return node

static func compact_control(ui, node: Button) -> void:
	node.custom_minimum_size.y = 30
	node.add_theme_font_size_override("font_size", maxi(14,int(14*ui.text_scale)))
	M.button(node,"quiet")

static func light_control(ui, node: Control) -> void:
	if node is Button:
		M.button(node as Button,"secondary")

static func action(ui, host: Node, key: String, callback: Callable, id: String = "", role: String = "quiet") -> Button:
	var node:=button(ui,host,key,callback,id)
	compact_control(ui,node)
	M.button(node,role)
	node.tooltip_text=COPY.copy(key)
	return node

static func strip(host: Node, tint: Color = GAME_UI.TAB) -> HBoxContainer:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",M.surface(tint if tint != GAME_UI.TAB else M.PAPER,7,true))
	host.add_child(panel)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);panel.add_child(row)
	return row

static func build(ui) -> void:
	var g=ui._game();var queue: Array=g.contract_queue()
	# The operations board keeps one shell but exposes three local responsibilities.
	# Rebuilding only the body preserves the management header/footer and avoids a
	# second navigation surface competing with the global Sales tab.
	for child in ui.modal_body.get_children():
		ui.modal_body.remove_child(child)
		child.queue_free()
	ui.controls.operations_signature=signature(g)
	ui.modal_body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	ui.modal_body.add_theme_constant_override("separation",8)
	ui.modal_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	if ui.root.size.x<1100:
		var title=ui.modal.find_child("PanelTitle",true,false)
		if title is Label:title.add_theme_font_size_override("font_size",int(23*ui.text_scale))
		var margin=ui.modal_scroll.get_parent().get_parent()
		if margin is MarginContainer:
			margin.add_theme_constant_override("margin_top",10)
			margin.add_theme_constant_override("margin_bottom",10)
	var header:=PanelContainer.new();header.name="DispatchToolbar"
	header.add_theme_stylebox_override("panel",M.surface(M.PAPER,8,true));ui.modal_body.add_child(header)
	var head:=HBoxContainer.new();head.add_theme_constant_override("separation",8);header.add_child(head)
	var open_count:=queue.filter(func(item):return not bool(item.get("completed",false))).size()
	cell(ui,head,COPY.copy("ops_open_count") % [open_count,g.contract_capacity()],0,M.MUTED,true).name="OperationsOpenCount"
	if not g.last_day_ledger().is_empty():action(ui,head,"ops_previous",ui.open_panel.bind("day_review"),"OperationsPrevious","quiet")
	var ready_count:=0
	for order in g.delivery_orders():
		if str(order.get("status","")) in ["ready","carried","placing"]:ready_count+=1
	if ready_count>0:action(ui,head,"ops_delivery",ui.close_panel,"OperationsReceive","secondary").text=COPY.copy("ops_delivery") % ready_count
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(spacer)
	action(ui,head,"ops_close",ui.open_panel.bind("door"),"OperationsCloseDay","quiet")
	var view:=str(ui.operations_choices.get("view","contracts"))
	if view not in ["contracts","maintenance","staff"]:view="contracts"
	ui.operations_choices.view=view
	var views:=HBoxContainer.new();views.name="DispatchViews";views.add_theme_constant_override("separation",6);ui.modal_body.add_child(views)
	for spec in [["contracts","dispatch_normal","OperationsView_contracts"],["maintenance","dispatch_maintenance","OperationsView_maintenance"],["staff","dispatch_title","OperationsView_staff"]]:
		var selected:=view==str(spec[0]);var tab:=action(ui,views,str(spec[1]),select_view.bind(ui,str(spec[0])),str(spec[2]),"tab");tab.toggle_mode=true;tab.button_pressed=selected;M.button(tab,"tab",selected);tab.tooltip_text=COPY.copy(str(spec[1]));tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	match view:
		"contracts":_dispatch_tickets(ui,ui.modal_body,g,queue,false)
		"maintenance":_dispatch_tickets(ui,ui.modal_body,g,queue,true)
		"staff":_dispatch_staff_grid(ui,ui.modal_body,g)

static func select_view(ui, view: String) -> void:
	if view not in ["contracts","maintenance","staff"]:return
	var previous_view:=str(ui.operations_choices.get("view","contracts"))
	var current: Dictionary=ui.operations_choices.get("dispatch_selected",{})
	var previous_scroll_name: String="DispatchStaffScroll" if previous_view=="staff" else "DispatchTicketScroll"
	var previous_scroll=ui.modal_body.find_child(previous_scroll_name,true,false)
	if previous_scroll is ScrollContainer:ui.operations_choices["scroll_"+previous_view]=previous_scroll.scroll_vertical
	if not current.is_empty() and previous_view in ["contracts","maintenance"]:
		ui.operations_choices["dispatch_selected_"+previous_view]=current.duplicate(true)
	ui.operations_choices.view=view
	if view in ["contracts","maintenance"]:
		var remembered: Dictionary=ui.operations_choices.get("dispatch_selected_"+view,{})
		ui.operations_choices.dispatch_selected=remembered.duplicate(true)
	build(ui)
	var restore_name: String="DispatchStaffScroll" if view=="staff" else "DispatchTicketScroll"
	var restore=ui.modal_body.find_child(restore_name,true,false)
	if restore is ScrollContainer:restore.set_deferred("scroll_vertical",int(ui.operations_choices.get("scroll_"+view,0)))

static func _dispatch_copy(key: String, fallback: String = "") -> String:
	return COPY.copy("dispatch_"+key,fallback)

static func _workload_copy(key: String, fallback: String = "") -> String:
	return COPY.copy("workload_"+key,fallback)

static func _dispatch_queue(g, member_id: String) -> Array:
	return g.dispatch_queue(member_id)

static func _dispatch_staff_grid(ui, parent: Node, g) -> void:
	var section:=VBoxContainer.new();section.name="DispatchStaffGrid";section.size_flags_vertical=Control.SIZE_EXPAND_FILL;section.add_theme_constant_override("separation",6);parent.add_child(section)
	var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
	var selected_id:=str(selected.get("member",""))
	var members: Array=g.team_members()
	if selected_id.is_empty() and not members.is_empty():
		selected_id=str(members[0].get("id",""));selected.member=selected_id;ui.operations_choices.dispatch_selected=selected
	var header:=strip(section,M.CANVAS)
	cell(ui,header,_dispatch_copy("member"),180,M.MUTED)
	cell(ui,header,_dispatch_copy("active"),0,M.MUTED,true)
	cell(ui,header,_dispatch_copy("queue"),120,M.MUTED)
	var scroll:=ScrollContainer.new();scroll.name="DispatchStaffScroll";scroll.custom_minimum_size.y=38;scroll.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;section.add_child(scroll)
	var table:=VBoxContainer.new();table.size_flags_horizontal=Control.SIZE_EXPAND_FILL;table.add_theme_constant_override("separation",3);scroll.add_child(table)
	for member in members:
		_dispatch_staff_row(ui,table,g,str(member.id),str(member.name),str(member.role),str(member.id)==selected_id)
	scroll.custom_minimum_size.y = minf(table.get_combined_minimum_size().y, 190)
	var detail_scroll := ScrollContainer.new(); detail_scroll.name="DispatchStaffDetailScroll"; detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; detail_scroll.custom_minimum_size.y=120; section.add_child(detail_scroll)
	_dispatch_staff_detail(ui,detail_scroll,g,selected_id)

static func _dispatch_staff_row(ui, parent: Node, g, member_id: String, member_name: String, role: String, selected: bool = false) -> void:
	var row:=strip(parent,M.SELECTED if selected else M.PAPER);row.name="DispatchStaff_"+member_id;row.custom_minimum_size.y=38
	var identity:=Button.new();identity.name="DispatchStaffSelect_"+member_id;identity.text=member_name;identity.alignment=HORIZONTAL_ALIGNMENT_LEFT;identity.custom_minimum_size.x=180;identity.tooltip_text=member_name+" / "+COPY.copy("staffing_role_"+role);identity.pressed.connect(func():
		var choice: Dictionary=ui.operations_choices.get("dispatch_selected",{});choice.member=member_id;ui.operations_choices.dispatch_selected=choice;build(ui))
	M.button(identity,"tab",selected);row.add_child(identity)
	var active:=_dispatch_active_job(g,member_id)
	var queued:=_dispatch_queue(g,member_id)
	var status:=_dispatch_copy("held" if bool(g.state.get("dispatch_holds",{}).get(member_id,false)) else "idle") if active.is_empty() else _dispatch_title(active)
	cell(ui,row,status,0,M.WARNING if _dispatch_is_risky(g,member_id,active) else M.INK,true).name="DispatchStaffStatus_"+member_id
	cell(ui,row,"%d" % queued.size(),120,M.MUTED).name="DispatchStaffQueueCount_"+member_id

static func _dispatch_staff_detail(ui, parent: Node, g, member_id: String) -> void:
	var detail:=PanelContainer.new();detail.name="DispatchStaffDetail";detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail.add_theme_stylebox_override("panel",M.surface(M.PAPER,10,true));parent.add_child(detail)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",5);detail.add_child(body)
	if member_id.is_empty():
		cell(ui,body,_dispatch_copy("member"),0,M.MUTED,true);return
	var member_name:=member_id
	for member in g.team_members():
		if str(member.get("id",""))==member_id:member_name=str(member.get("name",member_id));break
	label(ui,body,member_name,18,M.INK).name="DispatchStaffDetailTitle"
	var load:=_dispatch_load(g,member_id)
	var load_row:=HBoxContainer.new();load_row.name="DispatchLoadRow_"+member_id;load_row.add_theme_constant_override("separation",8);body.add_child(load_row)
	var load_bar:=ProgressBar.new();load_bar.name="DispatchLoad_"+member_id;load_bar.custom_minimum_size=Vector2(120,5);load_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;load_bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER;load_bar.show_percentage=false;load_bar.max_value=maxf(1.0,load.capacity);load_bar.value=minf(load.used,load.capacity);load_row.add_child(load_bar)
	var load_text_value:=_workload_copy("reserved","Reserved: %d min") % ceili(load.used) if bool(load.get("unbounded",false)) else "%d/%d" % [ceili(load.used),ceili(load.capacity)]
	var load_text:=cell(ui,load_row,load_text_value,84,M.WARNING if load.used>load.capacity else M.MUTED);load_text.name="DispatchLoadText_"+member_id;load_text.tooltip_text=load_text_value;load_text.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
	load_text.clip_text=false;load_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var active:=_dispatch_active_job(g,member_id)
	var active_box:=VBoxContainer.new();active_box.name="DispatchActiveDetail";active_box.add_theme_constant_override("separation",3);body.add_child(active_box)
	if active.is_empty():
		var held: bool=bool(g.state.get("dispatch_holds",{}).get(member_id,false))
		cell(ui,active_box,_dispatch_copy("held" if held else "idle"),0,M.WARNING if held else M.MUTED,true).name="DispatchActive_"+member_id
	else:
		cell(ui,active_box,_dispatch_title(active),0,M.INK,true).name="DispatchActive_"+member_id
		var controls:=HBoxContainer.new();controls.add_theme_constant_override("separation",8);active_box.add_child(controls)
		cell(ui,controls,_dispatch_remaining(g,active),0,M.INK,true).name="DispatchRemaining_"+member_id
		action(ui,controls,"dispatch_pause",func():
			if g.dispatch_pause(member_id):ui._refresh_operations()
			else:ui._operations_feedback(_dispatch_copy("failed")),"DispatchPause_"+member_id,"quiet")
		var progress:=ProgressBar.new();progress.name="DispatchProgress_"+member_id;progress.custom_minimum_size.y=4;progress.show_percentage=false;progress.value=_dispatch_progress(active);active_box.add_child(progress)
		cell(ui,active_box,_dispatch_plan(g,member_id,active),0,M.WARNING if _dispatch_is_risky(g,member_id,active) else M.MUTED,true).name="DispatchPlan_"+member_id
	var queue_box:=VBoxContainer.new();queue_box.name="DispatchQueue_"+member_id;queue_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;queue_box.add_theme_constant_override("separation",5);body.add_child(queue_box)
	var queued:=_dispatch_queue(g,member_id)
	if queued.is_empty():cell(ui,queue_box,_dispatch_copy("empty"),0,M.MUTED,true)
	for index in queued.size():_dispatch_chip(ui,queue_box,g,member_id,queued[index],index,queued.size(),active.is_empty())

static func _dispatch_title(job: Dictionary) -> String:
	return str(job.get("client",""))+" · "+str(job.get("title",""))

static func _dispatch_active_job(g, member_id: String) -> Dictionary:
	var job: Dictionary=g.state.get("assignments",{}).get(member_id,{})
	return g._dispatch_display(member_id,job) if str(job.get("status",""))=="working" else {}

static func _dispatch_remaining(g, job: Dictionary) -> String:
	return _dispatch_copy("remaining") % int(ceil(g._crew_minutes(job)*float(job.get("remaining",0))/maxf(float(job.get("total",1)),0.001)))

static func _dispatch_job_minutes(g, job: Dictionary) -> float:
	if job.is_empty(): return 0.0
	return maxf(0.0,g._crew_minutes(job)*float(job.get("remaining",job.get("total",0)))/maxf(float(job.get("total",1)),0.001))

static func _dispatch_shift_capacity(g, member_id: String) -> float:
	for member in g.team_members():
		if str(member.get("id", ""))!=member_id: continue
		for shift in g.staff_shift_catalog():
			if str(shift.get("id", ""))==str(member.get("shift", "day")):
				return maxf(1.0,float(shift.get("end",0))-float(shift.get("start",0)))
	return 480.0

static func _dispatch_load(g, member_id: String) -> Dictionary:
	if g.has_method("staff_workload"):
		var forecast: Dictionary=g.staff_workload(member_id)
		var reserved:=float(forecast.get("reserved_minutes",0.0))
		var available:=float(forecast.get("available_minutes",-1.0))
		var total:=reserved+available if available>=0.0 else maxf(1.0,reserved)
		return {"used":reserved,"capacity":maxf(1.0,total),"unbounded":available<0.0,"forecast":forecast}
	var used:=0.0
	var active:=_dispatch_active_job(g,member_id)
	if not active.is_empty():used+=_dispatch_job_minutes(g,active)
	for job in _dispatch_queue(g,member_id):used+=_dispatch_job_minutes(g,job)
	return {"used":used,"capacity":1.0,"unbounded":true,"forecast":{}}

static func _dispatch_is_risky(g, member_id: String, job: Dictionary) -> bool:
	if g.has_method("staff_workload"):
		var forecast: Dictionary=g.staff_workload(member_id)
		for projection in forecast.get("jobs",[]):
			if projection is Dictionary and (str(projection.get("id",""))==str(job.get("id","")) or (str(projection.get("contract_id",""))==str(job.get("contract_id","")) and int(projection.get("target_index",-1))==int(job.get("target_index",-2)))):
				return str(projection.get("risk","on_track"))!="on_track"
	return bool(job.get("late",false))

static func _dispatch_clock_text(minute: int) -> String:
	return "%02d:%02d" % [posmod(minute,1440)/60,posmod(minute,60)]

static func _dispatch_plan(g, member_id: String, job: Dictionary) -> String:
	if not g.has_method("staff_workload"):return _workload_copy("blocked","Blocked")
	var forecast: Dictionary=g.staff_workload(member_id)
	for projection in forecast.get("jobs",[]):
		if not projection is Dictionary:continue
		var same:=str(projection.get("id",""))==str(job.get("id",""))
		if not same:same=str(projection.get("contract_id",""))==str(job.get("contract_id","")) and int(projection.get("target_index",-1))==int(job.get("target_index",-2))
		if not same:continue
		return _dispatch_projection_text(projection,forecast)
	return _workload_copy("blocked","Blocked")

static func _dispatch_projection_text(projection: Dictionary, forecast: Dictionary) -> String:
	var risk:=str(projection.get("risk","blocked"))
	if risk=="blocked":
		var reason:=str(projection.get("blocked_reason",""))
		return COPY.copy(reason,_workload_copy("blocked","Blocked")) if not reason.is_empty() else _workload_copy("blocked","Blocked")
	var finish_day:=int(projection.get("finish_day",forecast.get("day",0)))
	var finish_minute:=int(projection.get("finish_minute",-1))
	if finish_minute<0:return _workload_copy("blocked","Blocked")
	var finish:=_workload_copy("finish","Work finish: %s")
	var result:=finish % (_workload_copy("day_time","DAY %d %s") % [finish_day,_dispatch_clock_text(finish_minute)]) if finish.find("%")>=0 else finish
	if risk=="late":
		var deadline_abs:=int(projection.get("deadline_day",finish_day))*1440+int(projection.get("deadline_minute",finish_minute))
		var actual_abs:=finish_day*1440+finish_minute
		var late:=_workload_copy("late","Late: +%d min")
		result += " · "+(late % maxi(1,actual_abs-deadline_abs) if late.find("%")>=0 else late)
	if finish_day>int(forecast.get("day",finish_day)):
		var overflow:=_workload_copy("overflow","Carry over: %d min")
		result += " · "+(overflow % int(projection.get("remaining_minutes",0)) if overflow.find("%")>=0 else overflow)
	return result

static func _dispatch_progress(job: Dictionary) -> float:
	return clampf((1.0-float(job.get("remaining",0))/maxf(float(job.get("total",1)),0.001))*100,0,100)

static func _dispatch_chip(ui, parent: Node, g, member_id: String, job: Dictionary, index: int, count: int, idle: bool) -> void:
	var item:=VBoxContainer.new();item.name="DispatchJob_"+str(job.id);item.add_theme_constant_override("separation",2);parent.add_child(item)
	var top:=HBoxContainer.new();top.add_theme_constant_override("separation",6);item.add_child(top)
	cell(ui,top,"%02d" % (index+1),22,GAME_UI.FOOTER)
	cell(ui,top,_dispatch_title(job),0,GAME_UI.FOOTER,true)
	var paused:=str(job.get("status",""))=="paused"
	cell(ui,top,_dispatch_copy("paused" if paused else "queued"),60,COPY.WARNING if paused else COPY.MUTED)
	var controls:=HBoxContainer.new();controls.add_theme_constant_override("separation",4);item.add_child(controls)
	var reason:=str(job.get("reason",""))
	var state_label:=cell(ui,controls,_dispatch_remaining(g,job) if reason.is_empty() else reason,0,GAME_UI.FOOTER if reason.is_empty() else Color("8c5b00"),true);state_label.name="DispatchReason_"+str(job.id)
	if reason.is_empty():cell(ui,item,_dispatch_plan(g,member_id,job),0,Color("8c5b00") if _dispatch_is_risky(g,member_id,job) else GAME_UI.FOOTER,true).name="DispatchPlan_"+str(job.id)
	var up:=action(ui,controls,"dispatch_up",func():
		if g.dispatch_move(member_id,str(job.id),-1):ui._refresh_operations(),"DispatchUp_"+str(job.id));up.text="↑";up.disabled=index==0
	var down:=action(ui,controls,"dispatch_down",func():
		if g.dispatch_move(member_id,str(job.id),1):ui._refresh_operations(),"DispatchDown_"+str(job.id));down.text="↓";down.disabled=index==count-1
	var start:=action(ui,controls,"dispatch_start",func():
		if g.dispatch_start(member_id,str(job.id)):ui._refresh_operations()
		else:ui._operations_feedback(_dispatch_copy("failed")),"DispatchStart_"+str(job.id));start.disabled=not idle or not reason.is_empty();start.tooltip_text=reason if not reason.is_empty() else _dispatch_copy("start")
	var remove:=action(ui,controls,"dispatch_remove",func():
		if g.dispatch_remove(member_id,str(job.id)):ui._refresh_operations(),"DispatchRemove_"+str(job.id));remove.text="×";remove.disabled=paused

static func _dispatch_tickets(ui, parent: Node, g, queue: Array, maintenance_only: bool = false) -> void:
	var section:=VBoxContainer.new();section.name="DispatchTickets";section.size_flags_vertical=Control.SIZE_EXPAND_FILL;section.add_theme_constant_override("separation",5);parent.add_child(section)
	var has_entries: bool=not (g.maintenance_jobs() if maintenance_only else queue).is_empty()
	if not has_entries:
		var empty_panel:=PanelContainer.new();empty_panel.name="DispatchEmptyState";empty_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;empty_panel.add_theme_stylebox_override("panel",M.surface(M.PAPER,12,true));section.add_child(empty_panel)
		var empty_body:=VBoxContainer.new();empty_body.add_theme_constant_override("separation",6);empty_panel.add_child(empty_body)
		cell(ui,empty_body,COPY.copy("ops_ready"),0,M.MUTED,true)
		if not maintenance_only:
			var sales:=action(ui,empty_body,"ops_sales",ui.open_panel.bind("sales"),"OperationsSalesEmpty","primary");sales.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		return
	var current: Dictionary=ui.operations_choices.get("dispatch_selected",{})
	var kind: String="maintenance" if maintenance_only else "contract"
	var candidates: Array=g.maintenance_jobs() if maintenance_only else queue
	var selected_exists:=false
	for item in candidates:
		var candidate_id:=str(item.get("client" if maintenance_only else "id",""))
		if str(current.get("kind",""))==kind and str(current.get("id",""))==candidate_id:selected_exists=true
	if not selected_exists:
		var chosen: Dictionary={}
		if not maintenance_only:
			for item in queue:
				if bool(item.get("active",false)) or str(item.get("id",""))==str(g.state.get("current_contract_id","")):
					chosen=item;break
			if chosen.is_empty():
				for item in queue:
					if not bool(item.get("completed",false)):chosen=item;break
				if chosen.is_empty() and not queue.is_empty():chosen=queue[0]
		elif not candidates.is_empty():chosen=candidates[0]
		if not chosen.is_empty():
			var chosen_id:=str(chosen.get("client" if maintenance_only else "id",""))
			_dispatch_select_ticket(ui,kind,chosen_id,int(chosen.get("target_index",0)))
	var toolbar:=HBoxContainer.new();toolbar.name="DispatchTicketToolbar";toolbar.add_theme_constant_override("separation",6)
	var member:=OptionButton.new();member.name="DispatchMemberSelector";compact_control(ui,member);member.custom_minimum_size.x=140;member.add_item(COPY.copy("ops_unassigned"));member.set_item_metadata(0,"")
	for staff in g.team_members():member.add_item(str(staff.name));member.set_item_metadata(member.item_count-1,str(staff.id))
	member.item_selected.connect(func(index):
		var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
		if not selected.is_empty():selected.member=str(member.get_item_metadata(index))
		_dispatch_sync_toolbar(ui))
	toolbar.add_child(member)
	var care_actions:=HFlowContainer.new();care_actions.name="DispatchCareActions";care_actions.add_theme_constant_override("h_separation",6);care_actions.add_theme_constant_override("v_separation",4)
	cell(ui,care_actions,"",0,GAME_UI.FOOTER,true).name="DispatchCareClient"
	action(ui,care_actions,"care_self_check",func():
		var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
		if g.run_maintenance(str(selected.get("id",""))):ui._refresh_operations(),"DispatchSelfCheck")
	action(ui,care_actions,"ops_priority_first",func():
		var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
		if g.prioritize_maintenance(str(selected.get("id",""))):ui._refresh_operations(),"DispatchPriority")
	var header:=strip(section,M.CANVAS)
	cell(ui,header,_dispatch_copy("subject"),0,M.MUTED,true)
	cell(ui,header,_dispatch_copy("target")+" / "+_dispatch_copy("owner"),190,M.MUTED)
	cell(ui,header,_dispatch_copy("status")+" / "+_dispatch_copy("deadline"),130,M.MUTED)
	var scroll:=ScrollContainer.new();scroll.name="DispatchTicketScroll";scroll.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;section.add_child(scroll)
	var table:=VBoxContainer.new();table.name="DispatchTicketTable";table.size_flags_horizontal=Control.SIZE_EXPAND_FILL;table.add_theme_constant_override("separation",0);scroll.add_child(table)
	var row_count:=0
	if not maintenance_only:
		for item in queue:_dispatch_ticket_row(ui,table,g,item);row_count+=1
	else:
		for job in g.maintenance_jobs():_dispatch_maintenance_row(ui,table,g,job);row_count+=1
	if row_count==0:
		var empty:=cell(ui,table,COPY.copy("ops_ready"),0,M.MUTED,true);empty.name="DispatchEmpty"
		if not maintenance_only:
			var sales:=action(ui,table,"ops_sales",ui.open_panel.bind("sales"),"OperationsSalesEmpty");sales.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	scroll.custom_minimum_size.y=minf(float(row_count if row_count>0 else 1),5.0)*50.0+(32.0 if row_count>0 else 0.0)
	var work:=PanelContainer.new();work.name="DispatchSelectedWork";work.add_theme_stylebox_override("panel",M.surface(M.CANVAS,8,true));section.add_child(work)
	var work_body:=VBoxContainer.new();work_body.add_theme_constant_override("separation",4);work.add_child(work_body)
	var current_selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
	var work_actions:=HBoxContainer.new();work_actions.name="DispatchSelectedActions";work_actions.add_theme_constant_override("separation",6);work_body.add_child(work_actions)
	cell(ui,work_actions,_selected_ticket_title(g,current_selected),0,M.INK,true).name="DispatchSelectedTitle"
	var action_spacer:=Control.new();action_spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;work_actions.add_child(action_spacer)
	var open_action:=action(ui,work_actions,"ops_open",func():_dispatch_open_selected(ui,g),"DispatchOpen","primary");open_action.custom_minimum_size.x=220 if ui.root.size.x>=1100 else 176
	var report:=action(ui,work_actions,"ops_report",func():_dispatch_report_selected(ui,g),"DispatchReport","secondary");report.custom_minimum_size.x=120 if ui.root.size.x>=1100 else 88
	var dispatch_disclosure:=Button.new();dispatch_disclosure.name="DispatchControlsDisclosure";dispatch_disclosure.text="▸  "+_dispatch_copy("title");dispatch_disclosure.toggle_mode=true;dispatch_disclosure.custom_minimum_size.y=30;work_body.add_child(dispatch_disclosure);M.button(dispatch_disclosure,"quiet")
	var dispatch_controls:=VBoxContainer.new();dispatch_controls.name="DispatchControls";dispatch_controls.add_theme_constant_override("separation",4);dispatch_controls.visible=bool(ui.operations_choices.get("dispatch_controls_open",false));work_body.add_child(dispatch_controls)
	dispatch_controls.add_child(toolbar)
	var dispatch_actions:=HFlowContainer.new();dispatch_actions.name="DispatchActions";dispatch_actions.add_theme_constant_override("h_separation",6);dispatch_actions.add_theme_constant_override("v_separation",4);dispatch_controls.add_child(dispatch_actions)
	var enqueue:=action(ui,dispatch_actions,"dispatch_enqueue",func():_dispatch_enqueue_selected(ui,g),"DispatchEnqueue");enqueue.custom_minimum_size.x=160
	dispatch_actions.add_child(care_actions)
	var forecast_strip:=strip(dispatch_controls,M.PAPER);forecast_strip.get_parent().name="DispatchForecastStrip";forecast_strip.get_parent().hide()
	var forecast:=cell(ui,forecast_strip,_workload_copy("schedule","Schedule"),0,M.MUTED,true);forecast.name="DispatchForecast";forecast.autowrap_mode=TextServer.AUTOWRAP_OFF
	dispatch_disclosure.button_pressed=dispatch_controls.visible
	dispatch_disclosure.text=("▾  " if dispatch_controls.visible else "▸  ")+_dispatch_copy("title")
	dispatch_disclosure.pressed.connect(func():
		dispatch_controls.visible=dispatch_disclosure.button_pressed
		ui.operations_choices.dispatch_controls_open=dispatch_controls.visible
		dispatch_disclosure.text=("▾  " if dispatch_controls.visible else "▸  ")+_dispatch_copy("title")
		_dispatch_sync_toolbar(ui))
	_dispatch_sync_toolbar(ui)
	_dispatch_sync_selected_work(ui,g)

static func _selected_ticket_title(g, selected: Dictionary) -> String:
	if selected.is_empty():return ""
	if str(selected.get("kind",""))=="maintenance":
		for item in g.maintenance_jobs():
			if str(item.get("client",""))==str(selected.get("id","")):return str(item.get("client",""))+" · "+_dispatch_copy("maintenance")
	else:
		for item in g.contract_queue():
			if str(item.get("id",""))==str(selected.get("id","")):return _dispatch_title(item)
	return ""

static func _dispatch_sync_selected_work(ui,g) -> void:
	var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
	var title=ui.modal_body.find_child("DispatchSelectedTitle",true,false)
	if title is Label:title.text=_selected_ticket_title(g,selected)
	var open=ui.modal_body.find_child("DispatchOpen",true,false)
	if open is Button:open.disabled=selected.is_empty() or (str(selected.get("kind",""))=="maintenance" and not g.maintenance_incident_reason(str(selected.get("id",""))).is_empty())

static func _dispatch_ticket_row(ui, parent: Node, g, item: Dictionary) -> void:
	var id:=str(item.id)
	var row:=strip(parent,M.PAPER);row.name="OperationsContract_"+id
	var choice: Dictionary=ui.operations_choices.get(id,{"target":int(item.get("target_index",0))})
	ui.operations_choices[id]=choice
	var ticket:=action(ui,row,"",func():_dispatch_select_ticket(ui,"contract",id,int(choice.target)),"DispatchTicket_"+id)
	light_control(ui,ticket)
	ticket.text=_dispatch_title(item);ticket.tooltip_text=ticket.text;ticket.alignment=HORIZONTAL_ALIGNMENT_LEFT;ticket.clip_text=true;ticket.size_flags_horizontal=Control.SIZE_EXPAND_FILL;ticket.toggle_mode=true
	var target:=OptionButton.new();target.name="OperationsTarget_"+id;compact_control(ui,target);target.custom_minimum_size.x=190;target.fit_to_longest_item=false;target.clip_text=true;row.add_child(target)
	light_control(ui,target)
	var context: Dictionary=g.state.contract_contexts.get(id,{})
	for site in context.get("targets",[]):target.add_item(str(site.get("name","")))
	if target.item_count>0:target.select(clampi(int(choice.target),0,target.item_count-1))
	target.disabled=bool(item.get("completed",false))
	target.item_selected.connect(func(index):choice.target=index;_dispatch_select_ticket(ui,"contract",id,index))
	cell(ui,row,COPY.copy("ops_done") if bool(item.completed) else _remaining(item),130,COPY.GREEN if bool(item.completed) else GAME_UI.FOOTER).name="DispatchDeadline_"+id

static func _dispatch_maintenance_row(ui, parent: Node, g, job: Dictionary) -> void:
	var client:=str(job.client);var row:=strip(parent,M.PAPER);row.name="DispatchMaintenance_"+client
	var ticket:=action(ui,row,"",func():_dispatch_select_ticket(ui,"maintenance",client,0),"DispatchTicketMaintenance_"+client.sha256_text().left(8))
	light_control(ui,ticket)
	ticket.text=client+" · "+_dispatch_copy("maintenance");ticket.tooltip_text=ticket.text;ticket.alignment=HORIZONTAL_ALIGNMENT_LEFT;ticket.clip_text=true;ticket.size_flags_horizontal=Control.SIZE_EXPAND_FILL;ticket.toggle_mode=true;ticket.set_meta("dispatch_client",client)
	var owner:=OptionButton.new();owner.name="OperationsCareOwner_"+client.sha256_text().left(8);compact_control(ui,owner);owner.custom_minimum_size.x=190;owner.fit_to_longest_item=false;owner.clip_text=true;owner.tooltip_text=_dispatch_copy("owner");row.add_child(owner)
	light_control(ui,owner)
	owner.add_item(COPY.copy("care_owner_manual"));owner.set_item_metadata(0,"")
	for staff in g.team_members():
		owner.add_item(str(staff.name));owner.set_item_metadata(owner.item_count-1,str(staff.id))
		if str(g.maintenance_owner(client))==str(staff.id):owner.select(owner.item_count-1)
	owner.item_selected.connect(func(index):
		if g.set_maintenance_owner(client,str(owner.get_item_metadata(index))):ui._refresh_operations())
	var raw_status:=str(g.care_incident(client).get("status",job.get("status","pending")))
	var status:=COPY.copy("care_status_"+raw_status)
	if raw_status in ["queued","paused"]:status=_dispatch_copy(raw_status)
	if raw_status in ["detected","recheck"]:status=COPY.copy("care_status_failed")
	cell(ui,row,status,130,Color("8c5b00") if raw_status in ["failed","detected","recheck"] else GAME_UI.FOOTER)

static func _dispatch_select_ticket(ui, kind: String, id: String, target_index: int) -> void:
	var previous: Dictionary=ui.operations_choices.get("dispatch_selected",{})
	var selected: Dictionary={"kind":kind,"id":id,"target":target_index,"member":str(previous.get("member",""))}
	ui.operations_choices.dispatch_selected=selected
	var view: String="maintenance" if kind=="maintenance" else "contracts"
	ui.operations_choices["dispatch_selected_"+view]=selected.duplicate(true)
	_dispatch_sync_toolbar(ui)
	_dispatch_sync_selected_work(ui,ui._game())

static func _dispatch_completed(g, selected: Dictionary) -> bool:
	for item in g.contract_queue():
		if str(item.id)==str(selected.get("id","")):return bool(item.completed)
	return false

static func _dispatch_sync_toolbar(ui) -> void:
	var g=ui._game();var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
	var current_id:=str(selected.get("id",""))
	if not selected.is_empty():
		var exists:=false
		for item in (g.maintenance_jobs() if str(selected.get("kind",""))=="maintenance" else g.contract_queue()):
			if str(item.get("client" if str(selected.get("kind",""))=="maintenance" else "id",""))==current_id:exists=true;break
		if not exists:selected={};ui.operations_choices.dispatch_selected={}
	var selector=ui.modal_body.find_child("DispatchMemberSelector",true,false)
	if selector is OptionButton:
		for index in selector.item_count:
			if str(selector.get_item_metadata(index))==str(selected.get("member","")):selector.select(index);break
	var care:=str(selected.get("kind",""))=="maintenance"
	var reason:=_dispatch_copy("select") if selected.is_empty() else ""
	var member:=str(selected.get("member",""));var id:=str(selected.get("id",""));var target:=int(selected.get("target",0))
	if reason.is_empty():
		var candidate: Dictionary={"member_id":member,"kind":"maintenance" if care else "normal","contract_id":id,"client":id,"target_index":target}
		reason=g._dispatch_reason(candidate,false)
		if reason.is_empty() and g._dispatch_duplicate(member,"maintenance" if care else "normal",id,target,id):reason=_dispatch_copy("duplicate")
	var forecast=ui.modal_body.find_child("DispatchForecast",true,false)
	if forecast is Label:
		forecast.text=_dispatch_forecast(g,selected,reason)
		forecast.add_theme_color_override("font_color", Color("8c5b00") if not reason.is_empty() else GAME_UI.FOOTER)
	var forecast_strip=ui.modal_body.find_child("DispatchForecastStrip",true,false)
	var controls=ui.modal_body.find_child("DispatchControls",true,false)
	if forecast_strip is Control:forecast_strip.visible=not selected.is_empty() and not str(selected.get("member","")).is_empty() and controls is Control and controls.visible
	var enqueue=ui.modal_body.find_child("DispatchEnqueue",true,false)
	if enqueue is Button:enqueue.disabled=not reason.is_empty();enqueue.tooltip_text=reason if not reason.is_empty() else _dispatch_copy("enqueue")
	var open=ui.modal_body.find_child("DispatchOpen",true,false)
	if open is Button:
		open.disabled=selected.is_empty() or (care and not g.maintenance_incident_reason(id).is_empty())
	var report=ui.modal_body.find_child("DispatchReport",true,false)
	if report is Button:report.disabled=selected.is_empty()
	var care_actions=ui.modal_body.find_child("DispatchCareActions",true,false)
	if care_actions!=null:
		care_actions.visible=care
		if care:
			ui.modal_body.find_child("DispatchCareClient",true,false).text=id+" · "+_dispatch_copy("maintenance")
			ui.modal_body.find_child("DispatchSelfCheck",true,false).disabled=not g.can_run_maintenance(id)
			ui.modal_body.find_child("DispatchPriority",true,false).disabled=str(g._maintenance_job_for(id).get("status",""))!="pending"
	for node in ui.modal_body.find_children("DispatchTicket*","Button",true,false):
		if node is Button and node.toggle_mode:
			var pressed: bool=(care and str(node.get_meta("dispatch_client",""))==id) or (not care and str(node.name)=="DispatchTicket_"+id)
			node.set_pressed_no_signal(pressed);M.button(node,"tab",pressed)

static func _dispatch_forecast(g, selected: Dictionary, reason: String) -> String:
	if selected.is_empty(): return _dispatch_copy("forecast_select", "Select a job and staff")
	if not reason.is_empty(): return reason
	var member:=str(selected.get("member",""));var id:=str(selected.get("id",""));var target:=int(selected.get("target",0));var care:=str(selected.get("kind",""))=="maintenance"
	if member.is_empty(): return _dispatch_copy("forecast_member", "Select staff")
	var quote: Dictionary={}
	if care:
		var mj: Dictionary=g._maintenance_job_for(id)
		quote={"ok":true,"duration":float(mj.get("estimated_minutes",mj.get("minutes",0))),"shift_end":-1}
	else: quote=g.dispatch_quote_forecast(member,id,target) if g.has_method("dispatch_quote_forecast") else {}
	if care and g.has_method("maintenance_quote_forecast"):quote=g.maintenance_quote_forecast(member,id)
	var blocked:=str(quote.get("blocked_reason",quote.get("reason","")))
	if not blocked.is_empty():return blocked
	var projection: Dictionary=quote.get("job",{}) if quote.get("job",{}) is Dictionary else {}
	var workload: Dictionary=quote.get("workload",{}) if quote.get("workload",{}) is Dictionary else {}
	if projection.is_empty():return _workload_copy("blocked","Blocked")
	return _dispatch_projection_text(projection,workload)

static func _dispatch_enqueue_selected(ui, g) -> void:
	var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{});if selected.is_empty():return
	var ok: bool=g.dispatch_enqueue_maintenance(str(selected.member),str(selected.id)) if str(selected.kind)=="maintenance" else g.dispatch_enqueue(str(selected.member),str(selected.id),int(selected.target))
	if ok:ui._refresh_operations()
	else:ui._operations_feedback(_dispatch_copy("failed"))

static func _dispatch_open_selected(ui, g) -> void:
	var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{});if selected.is_empty():return
	if str(selected.kind)=="maintenance":ui._open_maintenance_incident(str(selected.id))
	else:ui._operations_open(str(selected.id),-1 if _dispatch_completed(g,selected) else int(selected.target))

static func _dispatch_report_selected(ui, g) -> void:
	var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{});if selected.is_empty():return
	if str(selected.kind)=="maintenance":ui._show_maintenance_result(str(selected.id))
	else:
		ui._operations_open(str(selected.id),-1,"receipt")

static func _remaining(item: Dictionary) -> String:
	var late:=int(item.get("late_minutes",0));var remaining:=float(item.get("remaining",0))
	return COPY.copy("ops_late") % late if late>0 else COPY.copy("ops_remaining") % int(ceil(remaining))

static func _ledger_int(ledger: Dictionary, keys: Array, fallback: int = 0) -> int:
	for key in keys:
		if ledger.has(str(key)): return int(ledger.get(str(key), fallback))
	return fallback

static func _closeout_group(ui, host: Node, title: String, rows: Array, open: bool, name: String) -> void:
	var group := VBoxContainer.new(); group.name = name; group.add_theme_constant_override("separation", 4); host.add_child(group)
	var disclosure := Button.new(); disclosure.name = name + "Disclosure"; disclosure.text = ("▾  " if open else "▸  ") + title; disclosure.toggle_mode = true; disclosure.button_pressed = open; disclosure.alignment = HORIZONTAL_ALIGNMENT_LEFT; disclosure.custom_minimum_size.y = 32; group.add_child(disclosure); M.button(disclosure,"quiet")
	var body := VBoxContainer.new(); body.name = name + "Rows"; body.visible = open; body.add_theme_constant_override("separation", 4); group.add_child(body)
	for spec in rows:
		if spec.size() > 1 and int(spec[1]) == 0: continue
		var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation", 12); row.add_theme_constant_override("v_separation", 2); body.add_child(row)
		var key := label(ui, row, str(spec[0]), 14, M.MUTED); key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; key.autowrap_mode = TextServer.AUTOWRAP_OFF
		var value: int = int(spec[1])
		var amount := label(ui, row, preload("res://scripts/day_closeout_canvas.gd")._money(value), 15, M.WARNING if value < 0 else M.INK); amount.name = name + "Value" + str(row.get_index()); amount.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	disclosure.pressed.connect(func():
		body.visible = disclosure.button_pressed
		disclosure.text = ("▾  " if body.visible else "▸  ") + title
	)

static func closeout(ui, settled: bool) -> void:
	var g=ui._game();var ledger: Dictionary=g.last_day_ledger() if settled else g.day_preview()
	if ledger.is_empty():label(ui,ui.modal_body,COPY.copy("ops_no_receipt"));return
	ui.modal_body.add_theme_constant_override("separation", 8)
	var cash_complete: bool = bool(ledger.get("cash_flow_complete", false))
	var preview: bool = bool(ledger.get("preview", not settled))
	var cash_change: int = _ledger_int(ledger,["cash_change"], int(ledger.get("cash_after",0))-int(ledger.get("cash_open",ledger.get("cash_after",0))))
	label(ui,ui.modal_body,COPY.copy("ops_settled_day" if settled else "ops_closing_day") % int(ledger.day),20,M.ACCENT)
	var summary = preload("res://scripts/day_closeout_canvas.gd").new(); ui.modal_body.add_child(summary)
	summary.configure(ledger, float(ui.text_scale), settled)
	var details := VBoxContainer.new(); details.name = "CloseoutLedgerDetails"; details.add_theme_constant_override("separation", 4); ui.modal_body.add_child(details)
	var operating_rows: Array = [[COPY.copy("ops_contract_net"),_ledger_int(ledger,["contract_net"])],[COPY.copy("ops_care_earned"),_ledger_int(ledger,["care_gross"])],[COPY.copy("ops_care_cost"),-_ledger_int(ledger,["care_cost"])],[COPY.copy("ops_payroll"),-_ledger_int(ledger,["payroll_due"])],[COPY.copy("ops_hiring"),-_ledger_int(ledger,["hiring_cost"])],[COPY.copy("ops_profit"),_ledger_int(ledger,["total_profit"])]]
	_closeout_group(ui, details, COPY.copy("v220_profit_detail") + (" · 精算見込み" if preview else " · 確定"), operating_rows, false, "CloseoutOperating")
	var cash_rows: Array = []
	if cash_complete:
		cash_rows.append([COPY.copy("v220_cash_open"),_ledger_int(ledger,["cash_open"])])
		cash_rows.append(["入金合計",_ledger_int(ledger,["cash_in"])])
		cash_rows.append(["出金合計",-_ledger_int(ledger,["cash_out"])])
		cash_rows.append([COPY.copy("v220_cash_change"),cash_change])
		var cash_flow: Variant = ledger.get("cash_flow", {})
		if cash_flow is Dictionary:
			for flow_spec in [["v220_collections", "invoice_collections", 1],["v220_job_payments", "job_receipts", 1],["v220_job_costs", "job_costs", -1],["v220_care_income", "care_receipts", 1],["v220_care_costs", "care_costs", -1],["v220_stock_purchases", "stock_purchases", -1],["v220_investment", "investment", -1],["v220_recruitment", "recruitment", -1],["v220_wages_paid", "wages_paid", -1]]:
				if cash_flow.has(str(flow_spec[1])): cash_rows.append([COPY.copy(str(flow_spec[0])), int(cash_flow.get(str(flow_spec[1]), 0)) * int(flow_spec[2])])
	cash_rows.append([COPY.copy("v220_cash_end"),_ledger_int(ledger,["cash_after"])])
	cash_rows.append(["請求未確定",_ledger_int(ledger,["draft_total"])])
	cash_rows.append([COPY.copy("billing_receivable_total"),_ledger_int(ledger,["receivable_total"])])
	cash_rows.append([COPY.copy("billing_due_next_day") + "（売掛の内数）",_ledger_int(ledger,["due_next_day"])])
	cash_rows.append(["給与未払",_ledger_int(ledger,["arrears"])])
	_closeout_group(ui, details, COPY.copy("v220_cash_flow") + (" · 精算見込み" if preview else " · 確定") + (" / 旧台帳の内訳なし" if not cash_complete else ""), cash_rows, false, "CloseoutCash")
	var warnings:=VBoxContainer.new();warnings.name="CloseoutWarnings";warnings.add_theme_constant_override("separation",3);ui.modal_body.add_child(warnings)
	ui.modal_body.move_child(warnings, summary.get_index())
	if int(ledger.get("open_contracts",0))>0:label(ui,warnings,COPY.copy("ops_carryover") % int(ledger.get("open_contracts",0)),14,M.WARNING)
	if int(ledger.get("missed_maintenance",0))>0:label(ui,warnings,COPY.copy("ops_missed") % int(ledger.get("missed_maintenance",0)),14,M.DANGER)
	var receivable: int = _ledger_int(ledger,["receivable_total"])
	var draft: int = _ledger_int(ledger,["draft_total"])
	if not settled and int(ledger.get("open_contracts",0))>0:
		for item in g.contract_queue():
			if bool(item.completed):continue
			var pending:=flow(warnings);label(ui,pending,str(item.client)+" / "+str(item.title)+"  ·  "+str(item.deadline_text),14,M.WARNING)
			button(ui,pending,"ops_open",ui._operations_open.bind(str(item.id),-1))
	var actions:=footer(ui)
	if receivable>0 or draft>0:action(ui,actions,"billing_app",ui._open_billing,"DayBilling","quiet")
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(spacer)
	if settled:
		action(ui,actions,"ops_open_tasks",ui.open_panel.bind("board"),"DayNext","primary")
	else:
		action(ui,actions,"ops_continue",ui.open_panel.bind("board"),"DayContinue","quiet")
		var finish:=action(ui,actions,"queue_overnight",ui._end_day,"DaySettle","primary");finish.disabled=not g.can_end_day();finish.tooltip_text=g.end_day_reason()
		if not finish.tooltip_text.is_empty():label(ui,warnings,finish.tooltip_text,14,M.WARNING)
	warnings.visible=warnings.get_child_count()>0

static func signature(g) -> String:
	var jobs: Array=[]
	for id in g.state.assignments:
		var task: Dictionary=g.state.assignments[id];jobs.append([id,task.get("status",""),task.get("contract_id",""),task.get("target_index",0)])
	for id in g.state.contract_contexts:
		var context: Dictionary=g.state.contract_contexts[id];jobs.append([id,context.get("completed",false),context.get("validated_revision",-1)])
	for job in g.maintenance_jobs():jobs.append([job.get("id",""),job.get("status",""),g.maintenance_owner(str(job.get("client","")))])
	for member in g.team_members():
		if not member is Dictionary:continue
		var member_id:=str(member.get("id", ""));var queue:=_dispatch_queue(g,member_id);var shape:Array=[]
		for item in queue:
			if item is Dictionary:shape.append([str(item.get("id", "")),str(item.get("status", ""))])
		jobs.append(["dispatch",member_id,shape,bool(g.state.get("dispatch_holds",{}).get(member_id,false)) if g.state.get("dispatch_holds",{}) is Dictionary else false])
	return str([g.state.day,jobs,g.state.get("staff",{}).keys(),g.state.get("maintenance_priority",[]),g.delivery_orders().map(func(order):return [order.id,order.status])])

static func refresh_live(ui) -> void:
	var g=ui._game()
	if signature(g)!=str(ui.controls.get("operations_signature","")):ui.call_deferred("_refresh_operations");return
	var clock=ui.modal_body.find_child("OperationsClock",true,false)
	if clock!=null:clock.text="DAY %02d  %s" % [int(g.state.day),g.business_clock()]
	var preview: Dictionary=g.day_preview()
	for spec in [["OperationsCash","ops_cash",int(g.state.cash)],["OperationsProfit","ops_profit",int(preview.total_profit)],["OperationsPayroll","ops_payroll",int(preview.payroll_due)]]:
		var node=ui.modal_body.find_child(str(spec[0]),true,false)
		if node!=null:node.text=COPY.copy(spec[1])+"  ¥%d" % spec[2]
	for member in g.team_members():
		var id:=str(member.id);var active:=_dispatch_active_job(g,id)
		var live_load:=_dispatch_load(g,id)
		var live_bar=ui.modal_body.find_child("DispatchLoad_"+id,true,false)
		if live_bar is ProgressBar:
			live_bar.max_value=maxf(1.0,live_load.capacity);live_bar.value=minf(live_load.used,live_load.capacity)
		var live_load_text=ui.modal_body.find_child("DispatchLoadText_"+id,true,false)
		if live_load_text is Label:
			live_load_text.text=_workload_copy("reserved","Reserved: %d min") % ceili(live_load.used) if bool(live_load.get("unbounded",false)) else "%d/%d" % [ceili(live_load.used),ceili(live_load.capacity)]
			live_load_text.add_theme_color_override("font_color",Color("8c5b00") if live_load.used>live_load.capacity else GAME_UI.FOOTER)
		var remaining=ui.modal_body.find_child("DispatchRemaining_"+id,true,false)
		if remaining!=null:remaining.text=_dispatch_remaining(g,active)
		var plan=ui.modal_body.find_child("DispatchPlan_"+id,true,false)
		if plan is Label and not active.is_empty():
			plan.text=_dispatch_plan(g,id,active);plan.add_theme_color_override("font_color",Color("8c5b00") if _dispatch_is_risky(g,id,active) else GAME_UI.FOOTER)
		var progress=ui.modal_body.find_child("DispatchProgress_"+id,true,false)
		if progress is ProgressBar:progress.value=_dispatch_progress(active)
		for job in g.dispatch_queue(id):
			var reason:=str(job.get("reason",""));var reason_label=ui.modal_body.find_child("DispatchReason_"+str(job.id),true,false)
			if reason_label!=null:reason_label.text=reason if not reason.is_empty() else _dispatch_remaining(g,job);reason_label.tooltip_text=reason
			var plan_label=ui.modal_body.find_child("DispatchPlan_"+str(job.id),true,false)
			if plan_label is Label:
				plan_label.text=_dispatch_plan(g,id,job);plan_label.add_theme_color_override("font_color",Color("8c5b00") if _dispatch_is_risky(g,id,job) else GAME_UI.FOOTER)
			var start=ui.modal_body.find_child("DispatchStart_"+str(job.id),true,false)
			if start is Button:start.disabled=not active.is_empty() or not reason.is_empty();start.tooltip_text=reason if not reason.is_empty() else _dispatch_copy("start")
	for item in g.contract_queue():
		var deadline=ui.modal_body.find_child("DispatchDeadline_"+str(item.id),true,false)
		if deadline!=null and not bool(item.completed):deadline.text=_remaining(item)
	_dispatch_sync_toolbar(ui)
