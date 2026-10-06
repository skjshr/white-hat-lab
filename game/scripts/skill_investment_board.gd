extends Control
## Saved skill ranks and real customer requirements. Selection spends nothing.
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
var catalog: Array = []
var leads: Array = []
var chosen := ""
var points := 0
var factor := 1.0
var objects: Array[Button] = []
var folders: Array[Button] = []
var captions: Array[Label] = []

static func candidates(g, skill: String, focus: String) -> Array:
	var result: Array = []
	for lead in g.company_cycle_view().get("opportunities", []):
		if str(lead.get("status", "")) == "fulfilled" or not lead.get("required_skills", {}).has(skill): continue
		result.append(lead.duplicate(true))
	result.sort_custom(func(a,b):
		if str(a.id)==focus or str(b.id)==focus: return str(a.id)==focus
		return str(a.id)<str(b.id))
	return result

static func build(ui, g) -> void:
	var catalog: Array = g.skill_catalog()
	var focus := str(ui.get_meta("cycle_customer", ""))
	var selected := str(ui.get_meta("growth_skill", ""))
	if selected.is_empty():
		for lead in g.company_cycle_view().get("opportunities", []):
			if str(lead.id)!=focus: continue
			for id in lead.get("required_skills", {}):
				if int(g.state.skills.get(id,0)) < int(lead.required_skills[id]): selected=str(id); break
	if selected not in ["advisory","operations","response"]: selected=str(g.state.get("strategy","advisory"))
	if selected not in ["advisory","operations","response"]: selected="advisory"
	ui.set_meta("growth_skill", selected)
	var heading := HBoxContainer.new(); ui.modal_body.add_child(heading)
	var title: Label=ui._label("技能への投資",20,M.INK); title.autowrap_mode=TextServer.AUTOWRAP_OFF; title.name="GrowthHeading"; heading.add_child(title)
	var fill := Control.new(); fill.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(fill)
	var level: Dictionary = g.company_level()
	var level_label: Label=ui._label("会社 Lv.%d" % int(level.level),14,M.MUTED); level_label.autowrap_mode=TextServer.AUTOWRAP_OFF; level_label.tooltip_text=str(level.next_unlock); heading.add_child(level_label)
	var board: Control = load("res://scripts/skill_investment_board.gd").new()
	ui.modal_body.add_child(board)
	board.setup(catalog,g,focus,selected,ui.text_scale,ui.root.size.x<1100,func(id):ui.set_meta("growth_skill",id);ui._select_company_view("growth"),func(lead):
		if str(lead.get("status",""))=="ready": ui._open_cycle_offer(str(lead.id))
		else: ui.set_meta("cycle_customer",str(lead.id));ui._select_company_view("overview"))
	ui.modal_body.add_child(M.rule())
	for skill in catalog:
		if str(skill.id)!=selected: continue
		var action := HFlowContainer.new(); ui.modal_body.add_child(action)
		var allocation: Label=ui._label("%s  Lv.%d → %d" % [str(skill.title),int(skill.rank),mini(10,int(skill.rank)+1)],18,M.INK); allocation.autowrap_mode=TextServer.AUTOWRAP_OFF; action.add_child(allocation)
		var learn: Button=ui._button("1 pt を配分",ui._learn_skill.bind(selected)); learn.name="LearnSkill_"+selected
		learn.disabled=int(skill.rank)>=10 or g.skill_points()<=0 or str(g.state.strategy)==""; M.button(learn,"primary"); action.add_child(learn)
		if learn.disabled: action.add_child(ui._label("最大ランク" if int(skill.rank)>=10 else "配分できるポイントなし" if g.skill_points()<=0 else "最初の専門分野を選択",13,M.MUTED))
		ui.modal_body.add_child(ui._label("現在: "+str(skill.current_effect),13,M.MUTED))
		var next: Label=ui._label("配分後: "+str(skill.next_effect),14,M.INK); next.name="SkillNext_"+selected; ui.modal_body.add_child(next)
		var unlocks: Array=g.skill_case_unlocks(selected); next.tooltip_text="\n".join(unlocks)
		if not unlocks.is_empty():
			var unlocked: Label=ui._label("新しい候補: "+" / ".join(unlocks.slice(0,2)),13,M.MUTED); unlocked.name="SkillUnlocks_"+selected; unlocked.tooltip_text="\n".join(unlocks); ui.modal_body.add_child(unlocked)
		for lead in candidates(g,selected,focus):
			var needed := int(lead.required_skills[selected]); var missing := maxi(0,needed-int(skill.rank))
			var row := HFlowContainer.new(); ui.modal_body.add_child(row)
			var condition: Label=ui._label("%s · %s  %d / %d%s" % [str(lead.client),str(lead.title),int(skill.rank),needed," · あと%d pt" % missing if missing>0 else " · 技能到達"],13,M.INK)
			condition.name="GrowthRequirement_"+str(lead.id).validate_node_name(); row.add_child(condition)
			condition.custom_minimum_size.x=360*ui.text_scale
			condition.tooltip_text=" / ".join(lead.get("reasons",[]))
			var open: Button=ui._button("相談・見積へ" if str(lead.status)=="ready" else "相談の条件へ",ui._open_cycle_offer.bind(str(lead.id)) if str(lead.status)=="ready" else func():ui.set_meta("cycle_customer",str(lead.id));ui._select_company_view("overview"))
			open.name="GrowthOpen_"+str(lead.id).validate_node_name(); M.button(open,"secondary"); row.add_child(open)

func setup(skills: Array, g, focus: String, selected: String, scale: float, small: bool, choose: Callable, open: Callable) -> void:
	name="SkillInvestmentBoard"; catalog=skills.duplicate(true); chosen=selected; points=g.skill_points(); factor=scale
	custom_minimum_size.y=(276 if small else 264)*factor; size_flags_horizontal=Control.SIZE_EXPAND_FILL; mouse_filter=Control.MOUSE_FILTER_IGNORE
	for index in catalog.size():
		var skill: Dictionary=catalog[index]
		var button := Button.new(); button.name="GrowthSelect_"+str(skill.id); button.tooltip_text="%sの配分後の効果を比較" % str(skill.title)
		button.add_theme_stylebox_override("normal",UI.style(M.SELECTED if str(skill.id)==chosen else M.PAPER,M.ACCENT if str(skill.id)==chosen else M.LINE,5,0,2 if str(skill.id)==chosen else 1))
		button.add_theme_stylebox_override("hover",UI.style(M.SELECTED,M.ACCENT,5,0,2)); button.add_theme_stylebox_override("focus",UI.style(Color.TRANSPARENT,M.ACCENT,5,0,2))
		button.pressed.connect(choose.bind(str(skill.id))); button.draw.connect(_symbol.bind(index,button)); add_child(button); objects.append(button)
		var label := _caption(str(skill.title)+"\nLv.%d" % int(skill.rank),14); button.add_child(label); captions.append(label)
		var candidates: Array=candidates(g,str(skill.id),focus); var lead: Dictionary={} if candidates.is_empty() else candidates[0]; leads.append(lead)
		var folder := Button.new(); folder.name="GrowthFolder_"+str(skill.id); folder.disabled=lead.is_empty()
		folder.add_theme_stylebox_override("normal",UI.style(M.PAPER,M.LINE,2,0,1)); folder.add_theme_stylebox_override("hover",UI.style(M.SELECTED,M.ACCENT,2,0,2)); folder.add_theme_stylebox_override("focus",UI.style(Color.TRANSPARENT,M.ACCENT,2,0,2))
		folder.add_theme_stylebox_override("disabled",UI.style(M.CANVAS,M.LINE,2,0,1))
		if not lead.is_empty(): folder.pressed.connect(open.bind(lead)); folder.tooltip_text=" / ".join(lead.get("reasons",[]))
		add_child(folder); folders.append(folder)
		var text := "届いている相談なし"
		if not lead.is_empty():
			var needed := int(lead.required_skills[str(skill.id)]); var missing := maxi(0,needed-int(skill.rank))
			text="%s\n%s\n%s" % [str(lead.client),str(lead.title),"▶ 相談受付" if str(lead.status)=="ready" else "Ⅱ 保留" if str(lead.status)=="paused" else "Lv.%d · あと%d pt" % [needed,missing] if missing>0 else "⌛ 他の条件待ち"]
		var title := _caption(text,12); folder.add_child(title); captions.append(title)
	var balance := _caption("%d pt\n保有" % points,17); balance.name="GrowthPointBalance"; add_child(balance); captions.append(balance)
	resized.connect(_layout); _layout()

func _caption(text: String, font: int) -> Label:
	var label := Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",UI.font(600)); label.add_theme_font_size_override("font_size",int(font*factor)); label.add_theme_color_override("font_color",M.INK); label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _layout() -> void:
	for index in objects.size():
		var y := (10+index*87)*factor
		objects[index].position=Vector2(size.x*.14,y); objects[index].size=Vector2(size.x*.28,74*factor)
		captions[index*2].position=Vector2(objects[index].size.x*.25,7*factor); captions[index*2].size=Vector2(objects[index].size.x*.73,64*factor)
		folders[index].position=Vector2(size.x*.70,y); folders[index].size=Vector2(size.x*.29,77*factor)
		captions[index*2+1].position=Vector2(5*factor,4*factor); captions[index*2+1].size=folders[index].size-Vector2(10,8)*factor
	if not captions.is_empty(): captions[-1].position=Vector2(0,151*factor); captions[-1].size=Vector2(size.x*.12,80*factor)
	queue_redraw()

func _draw() -> void:
	var source := Vector2(size.x*.06,132*factor)
	draw_circle(source,22*factor,Color("f6e9ae")); draw_arc(source,22*factor,0,TAU,36,M.WARNING,2*factor,true)
	for index in catalog.size():
		var y := (47+index*87)*factor; var rank := int(catalog[index].rank); var color := M.ACCENT if str(catalog[index].id)==chosen else M.MUTED
		draw_polyline(PackedVector2Array([source+Vector2(22*factor,0),Vector2(size.x*.115,source.y),Vector2(size.x*.115,y),Vector2(size.x*.14,y)]),color,1.5*factor,true)
		var start := size.x*.46; var finish := size.x*.65
		draw_line(Vector2(size.x*.42,y),Vector2(size.x*.70,y),M.LINE,2*factor)
		var needed := int(leads[index].get("required_skills",{}).get(str(catalog[index].id),0))
		for at in range(1,11):
			var center := Vector2(lerpf(start,finish,float(at-1)/9.0),y)
			draw_circle(center,4.5*factor,color if at<=rank else M.PAPER); draw_arc(center,4.5*factor,0,TAU,16,color,1*factor,true)
			if at==rank+1 or at==needed:
				draw_arc(center,8*factor,0,TAU,24,M.WARNING if at==needed else color,1.3*factor,true)
				draw_string(UI.font(500),center+Vector2(-4,22)*factor,str(at),HORIZONTAL_ALIGNMENT_LEFT,-1,int(11*factor),M.INK)
		var to := Vector2(size.x*.69,y)
		draw_polyline(PackedVector2Array([to-Vector2(6,4)*factor,to,to-Vector2(6,-4)*factor]),color,1.5*factor,true)
		if not leads[index].is_empty() and str(leads[index].status)!="ready": draw_line(Vector2(size.x*.67,y-7*factor),Vector2(size.x*.67,y+7*factor),M.WARNING,3*factor)

func _symbol(index: int, button: Button) -> void:
	var center := Vector2(button.size.x*.14,button.size.y*.5); var color := M.ACCENT if str(catalog[index].id)==chosen else M.MUTED; var s := factor*.8
	if index==0:
		button.draw_arc(center,15*s,0,TAU,28,color,2*s,true); button.draw_line(center,center+Vector2(13,-12)*s,color,3*s,true)
		button.draw_line(center-Vector2(21,0)*s,center+Vector2(21,0)*s,color,1*s); button.draw_line(center-Vector2(0,21)*s,center+Vector2(0,21)*s,color,1*s)
	elif index==1:
		button.draw_rect(Rect2(center-Vector2(23,16)*s,Vector2(46,30)*s),color,false,2*s)
		button.draw_polyline(PackedVector2Array([center+Vector2(-19,3)*s,center+Vector2(-8,3)*s,center+Vector2(-3,-9)*s,center+Vector2(4,9)*s,center+Vector2(10,-2)*s,center+Vector2(19,-2)*s]),color,2*s,true)
		button.draw_line(center+Vector2(0,15)*s,center+Vector2(0,22)*s,color,2*s)
	else:
		button.draw_arc(center-Vector2(5,4)*s,13*s,0,TAU,28,color,2*s,true); button.draw_line(center+Vector2(5,6)*s,center+Vector2(22,23)*s,color,4*s,true)
		for offset in [-5,0,5]: button.draw_line(center+Vector2(-12,offset-4)*s,center+Vector2(1,offset-4)*s,color,1.5*s)
