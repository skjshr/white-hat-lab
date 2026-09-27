extends RefCounted

const COPY = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")

static func _copy(key: String, fallback: String = "") -> String:
	return COPY.copy(key, fallback)

static func _label(ui, text: String, size: int = 14, color: Color = M.INK) -> Label:
	return ui._label(text, size, color)

static func _panel(parent: Node, fill: Color = M.PAPER, padding: int = 12, name: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	if not name.is_empty(): panel.name = name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", M.surface(fill, padding, true))
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	return body

static func _button(ui, parent: Node, text: String, action: Callable, name: String, role: String = "secondary", selected: bool = false) -> Button:
	var button: Button = ui._button(text, action)
	button.name = name
	button.custom_minimum_size.y = 38
	M.button(button, role, selected)
	parent.add_child(button)
	return button

static func _role_name(candidate: Dictionary) -> String:
	return _copy("staffing_role_" + str(candidate.get("role", "")), str(candidate.get("role", "")))

static func _member_id(member: Dictionary) -> String:
	return str(member.get("id", member.get("member_id", "")))

static func _member_name(member: Dictionary) -> String:
	return str(member.get("name", _member_id(member)))

static func _active_member(g, member_id: String) -> Dictionary:
	for raw in g.team_members():
		if raw is Dictionary and _member_id(raw) == member_id and bool(raw.get("hired", false)):
			return raw
	return {}

static func _candidate(g, candidate_id: String) -> Dictionary:
	for raw in g.staff_candidates():
		if raw is Dictionary and _member_id(raw) == candidate_id:
			return raw
	return {}

static func _shift_catalog(g) -> Array:
	return g.staff_shift_catalog() if g.has_method("staff_shift_catalog") else []

static func _shift_id(spec: Variant) -> String:
	return str(spec.get("id", "day")) if spec is Dictionary else str(spec.id)

static func _shift_label(spec: Variant) -> String:
	return str(spec.get("label", "")) if spec is Dictionary else str(spec.label)

static func _chosen_shift(record: Dictionary) -> String:
	var chosen := str(record.get("pending_shift", record.get("shift", "day")))
	return "day" if chosen.is_empty() else chosen

static func _select_shift(control: OptionButton, shifts: Array, chosen: String) -> void:
	var index := 0
	for spec in shifts:
		control.add_item(_shift_label(spec))
		if _shift_id(spec) == chosen: index = control.item_count - 1
	control.select(index)

static func _shift_for_control(control: OptionButton, shifts: Array) -> String:
	if control.selected < 0 or control.selected >= shifts.size(): return "day"
	return _shift_id(shifts[control.selected])

static func _set_view(ui, view: String) -> void:
	ui.set_meta("staff_view", view)
	ui.open_panel("staffing")

static func build(ui) -> void:
	var g = ui._game()
	if g == null: return
	var summary: Dictionary = g.staff_summary()
	var view := str(ui.get_meta("staff_view", ""))
	var active_count := 0
	for raw in g.team_members():
		if raw is Dictionary and bool(raw.get("hired", false)): active_count += 1
	if view not in ["active", "candidates"]: view = "active" if active_count > 0 else "candidates"
	var selected_id := str(ui.get_meta("staff_selected_id", ""))
	if view == "active" and _active_member(g, selected_id).is_empty():
		for raw in g.team_members():
			if raw is Dictionary and bool(raw.get("hired", false)):
				selected_id = _member_id(raw); break
	if view == "candidates" and _candidate(g, selected_id).is_empty():
		for raw in g.staff_candidates():
			if raw is Dictionary and not bool(g.state.staff.get(_member_id(raw), {}).get("active", false)):
				selected_id = _member_id(raw); break
	ui.set_meta("staff_view", view)
	ui.set_meta("staff_selected_id", selected_id)

	var root := _panel(ui.modal_body, M.CANVAS, 16, "StaffManagementSurface")
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 10); root.add_child(content)
	var summary_row := HBoxContainer.new(); summary_row.add_theme_constant_override("separation", 10); content.add_child(summary_row)
	var summary_template := _copy("staffing_summary")
	if int(summary.arrears) <= 0:
		var arrears_marker := summary_template.find(" · 未払:")
		if arrears_marker >= 0: summary_template = summary_template.left(arrears_marker)
	var summary_text := summary_template % ([int(summary.count), int(summary.capacity), int(summary.due)] if int(summary.arrears) <= 0 else [int(summary.count), int(summary.capacity), int(summary.due), int(summary.arrears)])
	var summary_label := _label(ui, summary_text, 14, M.INK); summary_label.name = "StaffSummary"; summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; summary_row.add_child(summary_label)
	if int(summary.arrears) > 0:
		var pay := _button(ui, summary_row, _copy("staffing_pay_arrears"), func():
			if g.pay_staff_arrears(): ui.open_panel("staffing")
		, "PayrollArrears", "secondary")
		pay.disabled = int(g.state.cash) <= 0
		if pay.disabled: pay.tooltip_text = _copy("staffing_funds")
	content.add_child(M.rule())

	var tabs := HBoxContainer.new(); tabs.name = "StaffViews"; tabs.add_theme_constant_override("separation", 8); content.add_child(tabs)
	var active_tab := _button(ui, tabs, _copy("staffing_title"), func(): _set_view(ui, "active"), "StaffActiveTab", "tab", view == "active")
	var candidate_tab := _button(ui, tabs, _copy("staffing_candidates"), func(): _set_view(ui, "candidates"), "StaffCandidateTab", "tab", view == "candidates")
	active_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL; candidate_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var workspace := HBoxContainer.new(); workspace.name = "StaffContent"; workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL; workspace.add_theme_constant_override("separation", 12); content.add_child(workspace)
	var roster := _panel(workspace, M.PAPER, 10, "StaffRosterList"); roster.custom_minimum_size.x = 290 if float(ui.root.size.x) >= 1100.0 else 220
	var roster_box := VBoxContainer.new(); roster_box.add_theme_constant_override("separation", 4); roster.add_child(roster_box)
	if view == "active":
		for raw in g.team_members():
			if not raw is Dictionary or not bool(raw.get("hired", false)): continue
			var member: Dictionary = raw
			var member_id := _member_id(member)
			var row := _button(ui, roster_box, "%s  ·  %s" % [_member_name(member), _role_name(member)], func(): ui.set_meta("staff_selected_id", member_id); ui.open_panel("staffing"), "StaffMember_" + member_id, "tab", member_id == selected_id)
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT; row.tooltip_text = _copy("staffing_daily_cost") % int(member.get("daily_wage", 0))
		if active_count == 0: roster_box.add_child(_label(ui, _copy("staffing_inactive"), 13, M.MUTED))
	else:
		var candidate_count := 0
		for raw in g.staff_candidates():
			if not raw is Dictionary: continue
			var candidate: Dictionary = raw; var candidate_id := _member_id(candidate)
			if bool(g.state.staff.get(candidate_id, {}).get("active", false)): continue
			candidate_count += 1
			var row := _button(ui, roster_box, "%s  ·  %s" % [_member_name(candidate), _role_name(candidate)], func(): ui.set_meta("staff_selected_id", candidate_id); ui.open_panel("staffing"), "Candidate_" + candidate_id, "tab", candidate_id == selected_id)
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT; row.tooltip_text = _copy("staffing_terms") % [int(candidate.get("hire_fee", 0)), int(g.staff_daily_wage(candidate_id, "day"))]
		if candidate_count == 0: roster_box.add_child(_label(ui, _copy("staffing_inactive"), 13, M.MUTED))

	var detail := _panel(workspace, M.PAPER, 12, "StaffSelectedDetail"); detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if view == "active": _active_detail(ui, detail, g, selected_id)
	else: _candidate_detail(ui, detail, g, selected_id)

static func _active_detail(ui, parent: Node, g, member_id: String) -> void:
	var member := _active_member(g, member_id)
	if member.is_empty():
		parent.add_child(_label(ui, _copy("staffing_inactive"), 14, M.MUTED)); return
	var heading := _label(ui, "%s  ·  %s" % [_member_name(member), _role_name(member)], 18, M.INK); heading.name = "StaffSelectedName"; parent.add_child(heading)
	var record: Dictionary = g.state.staff.get(member_id, {})
	var detail_row := HBoxContainer.new(); detail_row.add_theme_constant_override("separation", 8); parent.add_child(detail_row)
	var cost := _label(ui, _copy("staffing_daily_cost") % int(member.get("daily_wage", 0)), 14, M.MUTED); cost.name = "StaffDailyCost"; cost.autowrap_mode = TextServer.AUTOWRAP_OFF; cost.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; detail_row.add_child(cost)
	var workplace_id := str(g.staff_workplace(member_id)) if g.has_method("staff_workplace") else ""
	if not workplace_id.is_empty():
		var workplace_title := workplace_id
		if g.has_method("equipment_catalog"):
			for equipment in g.equipment_catalog():
				var equipment_id := str(equipment.get("id", "")) if equipment is Dictionary else str(equipment.id)
				if equipment_id == workplace_id:
					workplace_title = str(equipment.get("title", workplace_id)) if equipment is Dictionary else str(equipment.title)
					break
		var workplace := _label(ui, workplace_title, 13, M.MUTED); workplace.name = "StaffWorkplace"; workplace.autowrap_mode = TextServer.AUTOWRAP_OFF; workplace.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; detail_row.add_child(workplace)
	parent.add_child(M.rule())
	var shift_row := HBoxContainer.new(); shift_row.add_theme_constant_override("separation", 8); parent.add_child(shift_row)
	var shift_label := _label(ui, _copy("staffing_shift"), 14, M.MUTED); shift_label.custom_minimum_size.x = 96; shift_row.add_child(shift_label)
	var shift := OptionButton.new(); shift.name = "Shift_" + member_id; shift.custom_minimum_size = Vector2(180, 38); M.field(shift); shift_row.add_child(shift)
	var shifts := _shift_catalog(g); _select_shift(shift, shifts, _chosen_shift(record))
	shift.item_selected.connect(func(_index: int):
		if g.set_staff_shift(member_id, _shift_for_control(shift, shifts)): ui.open_panel("staffing")
	)
	var release := _button(ui, shift_row, _copy("staffing_release"), func():
		if g.release_staff(member_id): ui.open_panel("staffing")
	, "Release_" + member_id, "secondary")
	var queued: bool = g._dispatch_has_queued(member_id) if g.has_method("_dispatch_has_queued") else false
	release.disabled = queued or str(g.state.assignments.get(member_id, {}).get("status", "")) == "working"
	release.tooltip_text = _copy("dispatch_staff_pending") if queued else (_copy("staffing_busy") if release.disabled else _copy("staffing_wage_note"))
	if not str(record.get("pending_shift", "")).is_empty() and shift.selected >= 0 and shift.selected < shifts.size():
		var next_shift := _label(ui, _copy("staffing_next_shift") % _shift_label(shifts[shift.selected]), 13, M.MUTED); next_shift.name = "StaffNextShift"; parent.add_child(next_shift)

static func _candidate_detail(ui, parent: Node, g, candidate_id: String) -> void:
	var candidate := _candidate(g, candidate_id)
	if candidate.is_empty():
		parent.add_child(_label(ui, _copy("staffing_inactive"), 14, M.MUTED)); return
	var heading := _label(ui, "%s  ·  %s" % [_member_name(candidate), _role_name(candidate)], 18, M.INK); heading.name = "StaffSelectedName"; parent.add_child(heading)
	var shifts := _shift_catalog(g)
	var shift_row := HBoxContainer.new(); shift_row.add_theme_constant_override("separation", 8); parent.add_child(shift_row)
	var shift_label := _label(ui, _copy("staffing_shift"), 14, M.MUTED); shift_label.custom_minimum_size.x = 96; shift_row.add_child(shift_label)
	var shift := OptionButton.new(); shift.name = "CandidateShift_" + candidate_id; shift.custom_minimum_size = Vector2(180, 38); M.field(shift); shift_row.add_child(shift); _select_shift(shift, shifts, "day")
	var hire := _button(ui, shift_row, _copy("staffing_hire"), func():
		if g.hire_staff(candidate_id, _shift_for_control(shift, shifts)):
			ui.set_meta("staff_view", "active"); ui.set_meta("staff_selected_id", candidate_id); ui.open_panel("staffing")
	, "Hire_" + candidate_id, "primary")
	var terms := _label(ui, "", 14, M.INK); terms.name = "StaffTerms"; terms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(terms)
	var reason := _label(ui, "", 13, M.DANGER); reason.name = "StaffHireReason"; reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(reason)
	var refresh: Callable = func(_index: int = 0):
		var shift_id := _shift_for_control(shift, shifts)
		terms.text = _copy("staffing_terms") % [int(candidate.get("hire_fee", 0)), int(g.staff_daily_wage(candidate_id, shift_id))]
		reason.text = str(g.staff_hire_reason(candidate_id, shift_id))
		reason.visible = not reason.text.is_empty()
		hire.disabled = not reason.text.is_empty()
		hire.tooltip_text = reason.text
	shift.item_selected.connect(refresh)
	refresh.call(shift.selected)
