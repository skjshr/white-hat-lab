extends RefCounted
const COPY = preload("res://scripts/ui_theme.gd")
const GAME_UI = preload("res://scripts/game_theme.gd")

static func label(ui, host: Node, value: String, size: int = 16, color: Color = COPY.INK) -> Label:
	var node: Label = ui._label(value,size,color); node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;host.add_child(node);return node

static func button(ui, host: Node, key: String, action: Callable, id: String = "") -> Button:
	var node: Button=ui._button(COPY.copy(key),action);node.name=id if not id.is_empty() else key;node.custom_minimum_size.y=38;host.add_child(node);return node

static func flow(host: Node) -> HFlowContainer:
	var row:=HFlowContainer.new();row.add_theme_constant_override("h_separation",8);row.add_theme_constant_override("v_separation",6);host.add_child(row);return row

static func footer(ui) -> HBoxContainer:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);ui.modal_footer.add_child(row);return row

static func box(ui, host: Node) -> VBoxContainer:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_theme_stylebox_override("panel",COPY.style(Color("f8faf9"),COPY.BORDER,16,13,3));host.add_child(panel)
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
	node.add_theme_font_size_override("font_size", maxi(13,int(13*ui.text_scale)))
	for state in ["normal","hover","pressed","disabled","focus"]:
		var fill := GAME_UI.ACTION if state == "normal" else GAME_UI.TAB
		if state == "disabled": fill = GAME_UI.CARD_FRAME
		if state == "focus": fill = Color.TRANSPARENT
		node.add_theme_stylebox_override(state,COPY.style(fill,GAME_UI.HEADER if state == "focus" else GAME_UI.CARD_FRAME,7,3,2))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		node.add_theme_color_override(state,GAME_UI.TEXT)
	node.add_theme_color_override("font_disabled_color",GAME_UI.FILTER)

static func light_control(ui, node: Control) -> void:
	for state in ["normal","hover","pressed","disabled","focus"]:
		var fill:=Color("f8faf9") if state!="pressed" else GAME_UI.TAB
		var text:=GAME_UI.FOOTER if state!="pressed" else Color.WHITE
		node.add_theme_stylebox_override(state,COPY.style(fill,GAME_UI.CARD_FRAME,7,3,1))
		node.add_theme_color_override("font_color",GAME_UI.FOOTER)
		node.add_theme_color_override("font_hover_color",GAME_UI.FOOTER)
		node.add_theme_color_override("font_pressed_color",Color.WHITE)
		node.add_theme_color_override("font_focus_color",GAME_UI.FOOTER)
	node.add_theme_color_override("font_disabled_color",GAME_UI.MUTED)

static func action(ui, host: Node, key: String, callback: Callable, id: String = "") -> Button:
	var node:=button(ui,host,key,callback,id)
	compact_control(ui,node)
	node.tooltip_text=COPY.copy(key)
	return node

static func strip(host: Node, tint: Color = GAME_UI.TAB) -> HBoxContainer:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",COPY.style(tint,GAME_UI.CARD_FRAME,8,5,2))
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
	header.add_theme_stylebox_override("panel",COPY.style(GAME_UI.FOOTER,GAME_UI.CARD_FRAME,10,7,2));ui.modal_body.add_child(header)
	var head:=HBoxContainer.new();head.add_theme_constant_override("separation",8);header.add_child(head)
	var open_count:=queue.filter(func(item):return not bool(item.get("completed",false))).size()
	cell(ui,head,COPY.copy("ops_open_count") % [open_count,g.contract_capacity()],0,GAME_UI.FILTER,true).name="OperationsOpenCount"
	if not g.last_day_ledger().is_empty():action(ui,head,"ops_previous",ui.open_panel.bind("day_review"),"OperationsPrevious")
	var ready_count:=0
	for order in g.delivery_orders():
		if str(order.get("status","")) in ["ready","carried","placing"]:ready_count+=1
	if ready_count>0:action(ui,head,"ops_delivery",ui.close_panel,"OperationsReceive").text=COPY.copy("ops_delivery") % ready_count
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(spacer)
	action(ui,head,"ops_close",ui.open_panel.bind("door"),"OperationsCloseDay")
	var view:=str(ui.operations_choices.get("view","contracts"))
	if view not in ["contracts","maintenance","staff"]:view="contracts"
	ui.operations_choices.view=view
	var views:=HBoxContainer.new();views.name="DispatchViews";views.add_theme_constant_override("separation",6);ui.modal_body.add_child(views)
	for spec in [["contracts","dispatch_normal","OperationsView_contracts"],["maintenance","dispatch_maintenance","OperationsView_maintenance"],["staff","dispatch_title","OperationsView_staff"]]:
		var tab:=action(ui,views,str(spec[1]),select_view.bind(ui,str(spec[0])),str(spec[2]));tab.toggle_mode=true;tab.button_pressed=view==str(spec[0]);tab.tooltip_text=COPY.copy(str(spec[1]));tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
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
	var section:=VBoxContainer.new();section.name="DispatchStaffGrid";section.size_flags_vertical=Control.SIZE_EXPAND_FILL;section.size_flags_stretch_ratio=1.3;section.add_theme_constant_override("separation",0);parent.add_child(section)
	var header:=strip(section)
	cell(ui,header,_dispatch_copy("member"),125,GAME_UI.FILTER)
	cell(ui,header,_dispatch_copy("active"),230,GAME_UI.FILTER)
	cell(ui,header,_dispatch_copy("queue"),0,GAME_UI.FILTER,true)
	var scroll:=ScrollContainer.new();scroll.name="DispatchStaffScroll";scroll.custom_minimum_size.y=70;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;section.add_child(scroll)
	var table:=VBoxContainer.new();table.size_flags_horizontal=Control.SIZE_EXPAND_FILL;table.add_theme_constant_override("separation",0);scroll.add_child(table)
	for member in g.team_members():
		_dispatch_staff_row(ui,table,g,str(member.id),str(member.name),str(member.role))

static func _dispatch_staff_row(ui, parent: Node, g, member_id: String, member_name: String, role: String) -> void:
	var row:=strip(parent,Color("f8faf9"));row.name="DispatchStaff_"+member_id;row.custom_minimum_size.y=66
	var identity:=VBoxContainer.new();identity.custom_minimum_size.x=125;row.add_child(identity)
	cell(ui,identity,member_name,125)
	cell(ui,identity,COPY.copy("staffing_role_"+role),125,GAME_UI.FOOTER)
	var load:=_dispatch_load(g,member_id)
	var load_row:=VBoxContainer.new();load_row.name="DispatchLoadRow_"+member_id;load_row.add_theme_constant_override("separation",4);identity.add_child(load_row)
	var load_bar:=ProgressBar.new();load_bar.name="DispatchLoad_"+member_id;load_bar.custom_minimum_size=Vector2(64,5);load_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;load_bar.show_percentage=false;load_bar.max_value=maxf(1.0,load.capacity);load_bar.value=minf(load.used,load.capacity);load_row.add_child(load_bar)
	var load_text_value:=_workload_copy("reserved","Reserved: %d min") % ceili(load.used) if bool(load.get("unbounded",false)) else "%d/%d" % [ceili(load.used),ceili(load.capacity)]
	var load_text:=cell(ui,load_row,load_text_value,72,COPY.WARNING if load.used>load.capacity else GAME_UI.FOOTER);load_text.name="DispatchLoadText_"+member_id;load_text.tooltip_text=load_text_value;load_text.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING;load_text.add_theme_font_size_override("font_size",maxi(11,int(11*ui.text_scale)))
	var active:=_dispatch_active_job(g,member_id)
	var active_box:=VBoxContainer.new();active_box.custom_minimum_size.x=230;active_box.add_theme_constant_override("separation",3);row.add_child(active_box)
	if active.is_empty():
		var held: bool=bool(g.state.get("dispatch_holds",{}).get(member_id,false))
		cell(ui,active_box,_dispatch_copy("held" if held else "idle"),230,COPY.WARNING if held else GAME_UI.FOOTER).name="DispatchActive_"+member_id
	else:
		cell(ui,active_box,_dispatch_title(active),230).name="DispatchActive_"+member_id
		var controls:=HBoxContainer.new();controls.add_theme_constant_override("separation",8);active_box.add_child(controls)
		cell(ui,controls,_dispatch_remaining(g,active),0,GAME_UI.FOOTER,true).name="DispatchRemaining_"+member_id
		action(ui,controls,"dispatch_pause",func():
			if g.dispatch_pause(member_id):ui._refresh_operations()
			else:ui._operations_feedback(_dispatch_copy("failed")),"DispatchPause_"+member_id)
		var progress:=ProgressBar.new();progress.name="DispatchProgress_"+member_id;progress.custom_minimum_size.y=4;progress.show_percentage=false;progress.value=_dispatch_progress(active);active_box.add_child(progress)
		cell(ui,active_box,_dispatch_plan(g,member_id,active),230,COPY.WARNING if _dispatch_is_risky(g,member_id,active) else GAME_UI.FOOTER).name="DispatchPlan_"+member_id
	var queue_box:=VBoxContainer.new();queue_box.name="DispatchQueue_"+member_id;queue_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;queue_box.add_theme_constant_override("separation",5);row.add_child(queue_box)
	var queued:=_dispatch_queue(g,member_id)
	if queued.is_empty():cell(ui,queue_box,_dispatch_copy("empty"),0,COPY.MUTED,true)
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
	var toolbar:=HBoxContainer.new();toolbar.name="DispatchTicketToolbar";toolbar.add_theme_constant_override("separation",6);section.add_child(toolbar)
	cell(ui,toolbar,_dispatch_copy("tickets"),80,GAME_UI.FOOTER,true)
	var member:=OptionButton.new();member.name="DispatchMemberSelector";compact_control(ui,member);member.custom_minimum_size.x=140;member.add_item(COPY.copy("ops_unassigned"));member.set_item_metadata(0,"");toolbar.add_child(member)
	for staff in g.team_members():
		member.add_item(str(staff.name));member.set_item_metadata(member.item_count-1,str(staff.id))
	member.item_selected.connect(func(index):
		var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
		if not selected.is_empty():selected.member=str(member.get_item_metadata(index))
		_dispatch_sync_toolbar(ui))
	action(ui,toolbar,"dispatch_enqueue",func():_dispatch_enqueue_selected(ui,g),"DispatchEnqueue")
	action(ui,toolbar,"ops_open",func():_dispatch_open_selected(ui,g),"DispatchOpen")
	action(ui,toolbar,"ops_report",func():_dispatch_report_selected(ui,g),"DispatchReport")
	var forecast_strip:=strip(section,Color("f8faf9"));forecast_strip.get_parent().name="DispatchForecastStrip";forecast_strip.get_parent().hide()
	var forecast:=cell(ui,forecast_strip,_workload_copy("schedule","Schedule"),0,GAME_UI.FILTER,true);forecast.name="DispatchForecast";forecast.autowrap_mode=TextServer.AUTOWRAP_OFF
	var care_actions:=HBoxContainer.new();care_actions.name="DispatchCareActions";care_actions.add_theme_constant_override("separation",6);section.add_child(care_actions)
	cell(ui,care_actions,"",0,GAME_UI.FOOTER,true).name="DispatchCareClient"
	action(ui,care_actions,"care_self_check",func():
		var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
		if g.run_maintenance(str(selected.get("id",""))):ui._refresh_operations(),"DispatchSelfCheck")
	action(ui,care_actions,"ops_priority_first",func():
		var selected: Dictionary=ui.operations_choices.get("dispatch_selected",{})
		if g.prioritize_maintenance(str(selected.get("id",""))):ui._refresh_operations(),"DispatchPriority")
	var header:=strip(section)
	cell(ui,header,_dispatch_copy("subject"),0,GAME_UI.FILTER,true)
	cell(ui,header,_dispatch_copy("target")+" / "+_dispatch_copy("owner"),190,GAME_UI.FILTER)
	cell(ui,header,_dispatch_copy("status")+" / "+_dispatch_copy("deadline"),130,GAME_UI.FILTER)
	var scroll:=ScrollContainer.new();scroll.name="DispatchTicketScroll";scroll.custom_minimum_size.y=60 if ui.root.size.x<1100 else 75;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;section.add_child(scroll)
	var table:=VBoxContainer.new();table.name="DispatchTicketTable";table.size_flags_horizontal=Control.SIZE_EXPAND_FILL;table.add_theme_constant_override("separation",0);scroll.add_child(table)
	var row_count:=0
	if not maintenance_only:
		for item in queue:_dispatch_ticket_row(ui,table,g,item);row_count+=1
	else:
		for job in g.maintenance_jobs():_dispatch_maintenance_row(ui,table,g,job);row_count+=1
	if row_count==0:
		var empty:=cell(ui,table,COPY.copy("ops_ready"),0,GAME_UI.FOOTER,true);empty.name="DispatchEmpty"
		if not maintenance_only:
			var sales:=action(ui,table,"ops_sales",ui.open_panel.bind("sales"),"OperationsSalesEmpty");sales.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	_dispatch_sync_toolbar(ui)

static func _dispatch_ticket_row(ui, parent: Node, g, item: Dictionary) -> void:
	var id:=str(item.id)
	var row:=strip(parent,Color("f8faf9"));row.name="OperationsContract_"+id
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
	var client:=str(job.client);var row:=strip(parent,Color("f8faf9"));row.name="DispatchMaintenance_"+client
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
	if forecast_strip is Control:forecast_strip.visible=not selected.is_empty()
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
		if node is Button and node.toggle_mode:node.set_pressed_no_signal((care and str(node.get_meta("dispatch_client",""))==id) or (not care and str(node.name)=="DispatchTicket_"+id))

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
		var completed:=_dispatch_completed(g,selected)
		ui._operations_open(str(selected.id),-1 if completed else int(selected.target),"receipt" if completed else "team")

static func _remaining(item: Dictionary) -> String:
	var late:=int(item.get("late_minutes",0));var remaining:=float(item.get("remaining",0))
	return COPY.copy("ops_late") % late if late>0 else COPY.copy("ops_remaining") % int(ceil(remaining))

static func closeout(ui, settled: bool) -> void:
	var g=ui._game();var ledger: Dictionary=g.last_day_ledger() if settled else g.day_preview()
	if ledger.is_empty():label(ui,ui.modal_body,COPY.copy("ops_no_receipt"));return
	label(ui,ui.modal_body,COPY.copy("ops_settled_day" if settled else "ops_closing_day") % int(ledger.day),23,COPY.OS_ACCENT)
	var summary:=box(ui,ui.modal_body);var metrics:=flow(summary)
	metric(ui,metrics,"ops_profit","¥%d" % int(ledger.total_profit))
	metric(ui,metrics,"ops_cash_after","¥%d" % int(ledger.cash_after))
	metric(ui,metrics,"billing_next_cash","¥%d" % int(ledger.get("next_cash",ledger.cash_after)))
	var lines:=GridContainer.new();lines.columns=2;lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL;lines.add_theme_constant_override("h_separation",28);lines.add_theme_constant_override("v_separation",8);summary.add_child(lines)
	for spec in [["ops_contract_net","contract_net"],["ops_care_earned","care_gross"],["ops_care_cost","care_cost"],["ops_payroll","payroll_due"],["ops_hiring","hiring_cost"],["ops_investment","investment_spending"],["stock_title","inventory_spending"],["ops_paid_wages","paid_wages"],["ops_arrears","arrears"]]:
		label(ui,lines,COPY.copy(spec[0]),16,COPY.MUTED);var amount:=label(ui,lines,"¥%d" % int(ledger.get(spec[1],0)),18);amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	for spec in [["billing_draft_total","draft_total"],["billing_receivable_total","receivable_total"],["billing_paid_today","paid_today"],["billing_due_next_day","due_next_day"]]:
		label(ui,lines,COPY.copy(spec[0]),16,COPY.MUTED);var amount:=label(ui,lines,"¥%d" % int(ledger.get(spec[1],0)),18);amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	if int(ledger.open_contracts)>0:label(ui,summary,COPY.copy("ops_carryover") % int(ledger.open_contracts),16,COPY.WARNING)
	if int(ledger.missed_maintenance)>0:label(ui,summary,COPY.copy("ops_missed") % int(ledger.missed_maintenance),16,COPY.RED)
	if not settled and int(ledger.open_contracts)>0:
		for item in g.contract_queue():
			if bool(item.completed):continue
			var pending:=flow(ui.modal_body);label(ui,pending,str(item.client)+" / "+str(item.title)+"  ·  "+str(item.deadline_text),14,COPY.WARNING)
			button(ui,pending,"ops_open",ui._operations_open.bind(str(item.id),-1))
	var actions:=footer(ui)
	button(ui,actions,"billing_app",ui._open_billing,"DayBilling")
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(spacer)
	if settled:
		COPY.primary(button(ui,actions,"ops_open_tasks",ui.open_panel.bind("board"),"DayNext"))
	else:
		button(ui,actions,"ops_continue",ui.open_panel.bind("board"),"DayContinue")
		var finish:=button(ui,actions,"queue_overnight",ui._end_day,"DaySettle");finish.disabled=not g.can_end_day();finish.tooltip_text=g.end_day_reason();COPY.primary(finish)
		if not finish.tooltip_text.is_empty():label(ui,ui.modal_body,finish.tooltip_text,14,COPY.WARNING)

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
