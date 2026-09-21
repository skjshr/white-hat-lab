extends RefCounted
const COPY = preload("res://scripts/ui_theme.gd")
const GAME_THEME = preload("res://scripts/game_theme.gd")

static func build(ui) -> void:
	var g = ui._game()
	var summary: Dictionary = g.staff_summary()
	ui.modal_body.add_child(ui._label(COPY.copy("staffing_summary") % [int(summary.count),int(summary.capacity),int(summary.due),int(summary.arrears)],16))
	var pay: Button = ui._button(COPY.copy("staffing_pay_arrears"),func():
		if g.pay_staff_arrears(): ui.open_panel("staffing"))
	pay.name = "PayrollArrears"; pay.disabled = int(summary.arrears) <= 0 or int(g.state.cash) <= 0
	ui.modal_body.add_child(pay)
	for member in g.team_members():
		var member_id := str(member.id)
		if not bool(member.get("hired",false)):
			continue
		var info: Label = ui._label(str(member.name)+" / "+COPY.copy("staffing_role_"+str(member.role)),20,GAME_THEME.TAB)
		if g.has_method("staff_workplace"):
			for equipment in g.equipment_catalog():
				if str(equipment.id)==str(g.staff_workplace(member_id)): info.tooltip_text=COPY.copy("expansion_staff_seat") % str(equipment.title); break
		ui.modal_body.add_child(info)
		var record: Dictionary = g.state.staff.get(member_id,{})
		var controls := VBoxContainer.new(); controls.add_theme_constant_override("separation",6); ui.modal_body.add_child(controls)
		var controls_row := HBoxContainer.new(); controls_row.add_theme_constant_override("separation",10); controls.add_child(controls_row)
		var cost_label: Label = ui._label(COPY.copy("staffing_daily_cost") % int(member.daily_wage),14)
		cost_label.custom_minimum_size.x = 150; cost_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		controls_row.add_child(cost_label)
		var shift := OptionButton.new(); shift.name = "Shift_"+member_id
		shift.custom_minimum_size.x = 150
		var shifts: Array = g.staff_shift_catalog()
		var chosen_shift := str(record.get("pending_shift",record.get("shift","day")))
		if chosen_shift.is_empty(): chosen_shift = str(record.get("shift","day"))
		for spec in shifts:
			shift.add_item(str(spec.label))
			if str(spec.id) == chosen_shift: shift.select(shift.item_count-1)
		shift.item_selected.connect(func(index):
			if g.set_staff_shift(member_id,str(shifts[index].id)): ui.open_panel("staffing"))
		controls_row.add_child(shift)
		var release: Button = ui._button(COPY.copy("staffing_release"),func():
			if g.release_staff(member_id): ui.open_panel("staffing"))
		release.name = "Release_"+member_id
		var queued: bool = g._dispatch_has_queued(member_id)
		release.disabled = queued or str(g.state.assignments.get(member_id,{}).get("status","")) == "working"
		release.tooltip_text = COPY.copy("dispatch_staff_pending") if queued else (COPY.copy("staffing_busy") if release.disabled else COPY.copy("staffing_wage_note"))
		GAME_THEME.primary(release, GAME_THEME.ACTION)
		controls_row.add_child(release)
		if not str(record.get("pending_shift", "")).is_empty():
			var next_shift: Label = ui._label(COPY.copy("staffing_next_shift") % str(shifts[shift.selected].label),13,ui.MUTED)
			next_shift.autowrap_mode = TextServer.AUTOWRAP_OFF; controls.add_child(next_shift)
	ui.modal_body.add_child(HSeparator.new())
	ui.modal_body.add_child(ui._label(COPY.copy("staffing_candidates"),22))
	for candidate in g.staff_candidates():
		var candidate_id := str(candidate.id)
		if bool(g.state.staff.get(candidate_id,{}).get("active",false)): continue
		var box := VBoxContainer.new(); box.add_theme_constant_override("separation",7); ui.modal_body.add_child(box)
		box.add_child(ui._label(str(candidate.name)+" / "+COPY.copy("staffing_role_"+str(candidate.role)),19,GAME_THEME.TAB))
		var row := VBoxContainer.new(); row.add_theme_constant_override("separation",6); box.add_child(row)
		var controls_row := HBoxContainer.new(); controls_row.add_theme_constant_override("separation",10); row.add_child(controls_row)
		var shifts: Array = g.staff_shift_catalog()
		var shift := OptionButton.new(); shift.name = "CandidateShift_"+candidate_id
		for spec in shifts: shift.add_item(str(spec.label))
		shift.custom_minimum_size.x = 150; controls_row.add_child(shift)
		var terms: Label = ui._label("",14); terms.custom_minimum_size.x = 220; terms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; terms.tooltip_text = COPY.copy("staffing_terms"); row.add_child(terms)
		var hire: Button = ui._button(COPY.copy("staffing_hire"),func():
			if g.hire_staff(candidate_id,str(shifts[shift.selected].id)): ui.open_panel("staffing"))
		hire.name = "Hire_"+candidate_id; controls_row.add_child(hire)
		GAME_THEME.primary(hire, GAME_THEME.BUY)
		var reason: Label = ui._label("",13,ui.MUTED); box.add_child(reason)
		var refresh: Callable = func(_index: int):
			var shift_id := str(shifts[shift.selected].id)
			terms.text = COPY.copy("staffing_terms") % [int(candidate.hire_fee),int(g.staff_daily_wage(candidate_id,shift_id))]
			reason.text = str(g.staff_hire_reason(candidate_id,shift_id)); reason.visible = not reason.text.is_empty()
			hire.disabled = not reason.text.is_empty(); hire.tooltip_text = reason.text
		shift.item_selected.connect(refresh); refresh.call(shift.selected)
	ui.modal_footer.add_child(ui._button(COPY.copy("office_team", "チーム"),ui._open_team))
	ui.modal_footer.add_child(ui._button("会社・スキル",ui.open_panel.bind("company")))
