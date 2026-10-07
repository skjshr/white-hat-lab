extends RefCounted
## Small read-only workday view. Commit actions stay on the existing Game and
## Interface APIs; building this panel only reads a company_workday snapshot.

const COPY = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
const MODEL = preload("res://scripts/company_workday.gd")
const FLOW = preload("res://scripts/workday_flow_canvas.gd")
const BUSINESS = preload("res://scripts/priority_brief_canvas.gd")
const HANDOFF = preload("res://scripts/work_handoff_canvas.gd")

static func build(ui, parent: Node, g) -> void:
	if g == null or parent == null: return
	var choices: Dictionary = ui.operations_choices if ui.get("operations_choices") is Dictionary else {}
	var selected_key := str(choices.get("workday_selected", ""))
	var snapshot: Dictionary = MODEL.snapshot(g, selected_key)
	var jobs: Array = snapshot.get("jobs", [])
	if selected_key.is_empty() or not jobs.any(func(row): return str(row.get("key", "")) == selected_key):
		selected_key = _default_job(jobs)
		choices.workday_selected = selected_key
		snapshot = MODEL.snapshot(g, selected_key)
	var job: Dictionary = _selected_job(snapshot.get("jobs", []), selected_key)
	var candidates: Array = _canvas_candidates(snapshot.get("candidates", []), snapshot.get("people", []), job)
	var member_id := str(choices.get("workday_member", "self"))
	if member_id != "self" and not candidates.any(func(item): return str(item.get("id", "")) == member_id):
		member_id = "self"
		choices.workday_member = member_id

	var root := VBoxContainer.new()
	root.name = "WorkdayPanel"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	parent.add_child(root)
	_summary(ui, root, snapshot.get("economy", {}))
	var has_maintenance := false
	for raw in snapshot.get("jobs", []):
		if raw is Dictionary and str(raw.get("kind", "")) == "maintenance": has_maintenance = true; break
	var scroll := ScrollContainer.new()
	scroll.name = "WorkdayScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 0
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "WorkdayContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	scroll.add_child(content)
	_jobs(ui, content, g, snapshot.get("jobs", []), selected_key)
	if not job.get("business", {}).is_empty():
		var business = BUSINESS.new()
		business.name = "WorkdayBusiness"
		content.add_child(business)
		business.configure(job.business, float(ui.text_scale), func(queue_id: String): ui._open_priority_work(str(job.id), int(job.target), queue_id))
	elif _show_handoff(job, choices):
		var handoff = HANDOFF.new()
		handoff.name = "WorkdayHandoff"
		content.add_child(handoff)
		handoff.configure(job.handoff, float(ui.text_scale))
		handoff.route_requested.connect(func(route: String): _handoff_route(ui, job, route))
		if bool(choices.get("workday_record_open", false)): _work_records(ui, content, job)
	elif not job.is_empty() and not bool(job.get("completed", false)) and not bool(job.get("draft", false)):
		var canvas = FLOW.new()
		canvas.name = "WorkdayFlowCanvas"
		content.add_child(canvas)
		canvas.configure(job, candidates, float(ui.text_scale))
		canvas.set_selected(member_id)
		canvas.member_selected.connect(func(id: String):
			choices.erase("workday_feedback")
			choices.workday_member = id
			choices.workday_feedback = ""
			_sync_dispatch_selection(choices, job, id)
			ui._refresh_operations()
		)
		canvas.self_selected.connect(func():
			choices.erase("workday_feedback")
			choices.workday_member = "self"
			choices.workday_feedback = ""
			_sync_dispatch_selection(choices, job, "self")
			ui._refresh_operations()
		)
	elif job.is_empty():
		_label(ui, content, "新規受注から次の仕事へ", 14, M.MUTED)
	if not job.is_empty() and (bool(job.get("completed", false)) or bool(job.get("draft", false))):
		_label(ui, content, _forecast_summary(job, candidates, member_id), 14, M.MUTED)
	if not has_maintenance:
		_empty_maintenance_routes(ui, content)
	_footer(ui, g, job, candidates, member_id)
	ui.controls.workday_signature = MODEL.signature(g)
	ui.controls.workday_clock = int(g.clock_minutes())
	ui.controls.workday_cash = int(g.state.get("cash", 0))

static func refresh_live(ui, g) -> void:
	if not is_instance_valid(ui) or g == null: return
	var signature := MODEL.signature(g)
	if str(ui.controls.get("workday_signature", "")) != signature:
		var scroll := ui.modal_body.find_child("WorkdayScroll", true, false) as ScrollContainer
		var position := scroll.scroll_vertical if is_instance_valid(scroll) else 0
		var focus: Control = ui.get_viewport().gui_get_focus_owner()
		var focus_name := str(focus.name) if is_instance_valid(focus) else ""
		for child in ui.modal_body.get_children():
			if child.name == "WorkdayPanel": ui.modal_body.remove_child(child); child.queue_free()
		build(ui, ui.modal_body, g)
		var refreshed := ui.modal_body.find_child("WorkdayScroll", true, false) as ScrollContainer
		if is_instance_valid(refreshed): refreshed.set_deferred("scroll_vertical", position)
		if not focus_name.is_empty(): _restore_focus(ui, focus_name)
		return
	var minute := int(g.clock_minutes())
	var cash := int(g.state.get("cash", 0))
	if int(ui.controls.get("workday_clock", -1)) == minute and int(ui.controls.get("workday_cash", cash)) == cash: return
	ui.controls.workday_clock = minute
	ui.controls.workday_cash = cash
	var selected_key := str(ui.operations_choices.get("workday_selected", ""))
	var snapshot: Dictionary = MODEL.snapshot(g, selected_key)
	_update_summary(ui, snapshot.get("economy", {}))
	var job := _selected_job(snapshot.get("jobs", []), selected_key)
	if job.is_empty() or bool(job.get("completed", false)) or bool(job.get("draft", false)): return
	var candidates := _canvas_candidates(snapshot.get("candidates", []), snapshot.get("people", []), job)
	var selected_id := str(ui.operations_choices.get("workday_member", "self"))
	var canvas = ui.modal_body.find_child("WorkdayFlowCanvas", true, false)
	if canvas == null: return
	var focus_owner: Control = ui.get_viewport().gui_get_focus_owner()
	var control_name := str(focus_owner.name) if is_instance_valid(focus_owner) else ""
	canvas.configure(job, candidates, float(ui.text_scale))
	canvas.set_selected(selected_id)
	_footer(ui, g, job, candidates, selected_id)
	if not control_name.is_empty(): _restore_focus(ui, control_name)

static func _default_job(jobs: Array) -> String:
	for item in jobs:
		if item is Dictionary and bool(item.get("draft", false)): return str(item.get("key", ""))
	for item in jobs:
		if item is Dictionary and not bool(item.get("completed", false)): return str(item.get("key", ""))
	return str(jobs[0].get("key", "")) if not jobs.is_empty() and jobs[0] is Dictionary else ""

static func _selected_job(jobs: Array, key: String) -> Dictionary:
	for item in jobs:
		if item is Dictionary and str(item.get("key", "")) == key: return item
	return {}

static func _canvas_candidates(candidates: Array, people: Array, job: Dictionary) -> Array:
	var out: Array = []
	for raw in candidates:
		if not raw is Dictionary: continue
		var item: Dictionary = raw.duplicate(true)
		var projection: Dictionary = item.get("projection", {}) if item.get("projection", {}) is Dictionary else {}
		var quote: Dictionary = {
			"reason":str(item.get("reason", "")) if not bool(item.get("can_enqueue", false)) else str(item.get("forecast_reason", projection.get("blocked_reason", ""))),
			"finish_day":int(item.get("finish_day", -1)),
			"finish_minute":int(item.get("finish_minute", -1)),
			"duration_minutes":float(item.get("duration_minutes", 0.0)),
			"late_minutes":int(item.get("late_minutes", 0))
		}
		if bool(item.get("can_finish", false)):
			quote.ok = bool(item.get("can_enqueue", false))
			quote.risk = str(item.get("risk", "unknown"))
		elif not bool(item.get("can_enqueue", false)):
			quote.ok = false
			quote.risk = "blocked"
		var activity := ""
		if str(job.get("kind", ""))=="maintenance" and str(job.get("assignee", ""))==str(item.id): activity=str(job.get("status", ""))
		for assignment in job.get("assignments", []):
			if str(assignment.get("member", ""))==str(item.id): activity=str(assignment.get("status", "")); break
		quote.activity=activity
		item.quote = quote
		for person in people:
			if person is Dictionary and str(person.get("id", "")) == str(item.get("id", "")):
				item.workload = person.get("workload", {}).duplicate(true) if person.get("workload", {}) is Dictionary else {}
				break
		out.append(item)
	return out

static func _summary(ui, parent: Node, economy: Dictionary) -> void:
	var strip := HFlowContainer.new()
	strip.name = "WorkdayEconomy"
	strip.add_theme_constant_override("h_separation", 14)
	strip.add_theme_constant_override("v_separation", 2)
	parent.add_child(strip)
	for spec in [
		["給与", int(economy.get("payroll_due", 0))],
		["保守差引", int(economy.get("care_net", 0))],
		["請求下書き", int(economy.get("draft_total", 0))],
		["締め後現金", int(economy.get("cash_after", economy.get("cash_current", 0)))]
	]:
		var label := Label.new()
		label.name = "WorkdayMetric_" + str(spec[0]).validate_node_name()
		label.text = "%s  ¥%s" % [str(spec[0]), ui._group_number(int(spec[1]))]
		label.add_theme_font_override("font", COPY.font(500))
		label.add_theme_font_size_override("font_size", roundi(13 * float(ui.text_scale)))
		label.add_theme_color_override("font_color", M.INK)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(label)

static func _update_summary(ui, economy: Dictionary) -> void:
	for spec in [
		["給与", int(economy.get("payroll_due", 0))],
		["保守差引", int(economy.get("care_net", 0))],
		["請求下書き", int(economy.get("draft_total", 0))],
		["締め後現金", int(economy.get("cash_after", economy.get("cash_current", 0)))]
	]:
		var item := ui.modal_body.find_child("WorkdayMetric_" + str(spec[0]).validate_node_name(), true, false) as Label
		if is_instance_valid(item): item.text = "%s  ¥%s" % [str(spec[0]), ui._group_number(int(spec[1]))]

static func _jobs(ui, parent: Node, g, jobs: Array, selected_key: String) -> void:
	if jobs.is_empty():
		_label(ui, parent, "今日の割当待ちはありません。受注可能な案件は営業から確認できます。", 14, M.MUTED)
		var sales := _button(ui, parent, "仕事を探す", func(): ui.open_panel("sales"), "WorkdaySales", "quiet")
		sales.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		return
	for raw in jobs:
		if not raw is Dictionary: continue
		var job: Dictionary = raw
		var key := str(job.get("key", ""))
		var row := HBoxContainer.new()
		row.name = "WorkdayJob_" + key.validate_node_name()
		row.add_theme_constant_override("separation", 5)
		parent.add_child(row)
		var selected := key == selected_key
		var label := _job_label(job)
		var pick := Button.new()
		pick.name = "WorkdaySelect_" + key.validate_node_name()
		pick.text = label
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.custom_minimum_size.y = 37 * float(ui.text_scale)
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.clip_text = true
		pick.tooltip_text = "%s / %s / %s" % [str(job.get("client", "")), str(job.get("title", "")), str(job.get("deadline", {}).get("text", ""))]
		M.button(pick, "tab", selected)
		pick.pressed.connect(func():
			ui.operations_choices.erase("workday_feedback")
			ui.operations_choices.erase("workday_handoff_dispatch")
			ui.operations_choices.erase("workday_record_open")
			ui.operations_choices.workday_selected = key
			ui.operations_choices.workday_member = "self"
			_sync_dispatch_selection(ui.operations_choices, job, "self")
			ui._refresh_operations()
		)
		row.add_child(pick)
		var status := Label.new()
		status.text = _status(job)
		status.custom_minimum_size.x = 82 * float(ui.text_scale)
		status.add_theme_font_override("font", COPY.font(500))
		status.add_theme_font_size_override("font_size", roundi(12 * float(ui.text_scale)))
		status.add_theme_color_override("font_color", M.ACCENT if bool(job.get("completed", false)) else M.WARNING if str(job.get("status", "")) in ["late", "paused"] else M.MUTED)
		status.clip_text = true; status.tooltip_text = status.text; status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(status)
		var money := Label.new()
		money.text = _money(job)
		money.custom_minimum_size.x = 78 * float(ui.text_scale)
		money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		money.add_theme_font_override("font", COPY.font(500))
		money.add_theme_font_size_override("font_size", roundi(12 * float(ui.text_scale)))
		money.add_theme_color_override("font_color", M.INK); money.clip_text = true; money.tooltip_text = money.text; money.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(money)

static func _empty_maintenance_routes(ui, parent: Node) -> void:
	var row := HFlowContainer.new()
	row.name = "WorkdayMaintenanceRoutes"
	row.add_theme_constant_override("h_separation", 5)
	parent.add_child(row)
	_label(ui, row, "保守の依頼なし", 12, M.MUTED)
	_button(ui, row, "保守契約を見る", func(): ui._open_cycle_route("care"), "WorkdayCareRoute", "quiet")
	_button(ui, row, "運用スキルを見る", func(): ui._open_cycle_route("company_growth"), "WorkdaySkillRoute", "quiet")

static func _footer(ui, g, job: Dictionary, candidates: Array, member_id: String) -> void:
	if not is_instance_valid(ui.modal_footer): return
	for child in ui.modal_footer.get_children():
		if child.name.begins_with("WorkdayAction") or child.name == "WorkdaySelectedFeedback":
			ui.modal_footer.remove_child(child); child.queue_free()
	var label := Label.new()
	label.name = "WorkdaySelectedFeedback"
	label.text = str(ui.operations_choices.get("workday_feedback", ""))
	if bool(job.get("completed", false)): label.text=""
	if label.text.is_empty(): label.text = _forecast_summary(job, candidates, member_id)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", COPY.font(500))
	label.add_theme_font_size_override("font_size", roundi(13 * float(ui.text_scale)))
	label.add_theme_color_override("font_color", M.MUTED)
	ui.modal_footer.add_child(label)
	var actions := HFlowContainer.new()
	actions.name = "WorkdayActionButtons"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_stretch_ratio = 1.5
	actions.add_theme_constant_override("h_separation", 5)
	ui.modal_footer.add_child(actions)
	if job.is_empty(): return
	if str(job.get("status", "")) == "legacy":
		label.text = "従来型契約 · 点検原本の記録なし"
		_button(ui, actions, "保守契約を見る", ui._open_cycle_route.bind("care"), "WorkdayCareRoute", "secondary")
		return
	if bool(job.get("draft", false)):
		_button(ui, actions, "請求を確認", func(): ui._open_billing(str(job.get("invoice", {}).get("id", ""))), "WorkdayBilling", "primary")
		return
	if bool(job.get("completed", false)):
		if str(job.get("kind", "")) == "maintenance":
			_button(ui, actions, "点検結果を見る", func(): ui._show_maintenance_result(str(job.get("client", ""))), "WorkdayResult", "primary")
		else:
			_button(ui, actions, "納品結果を見る", func(): ui._operations_open(str(job.get("id", "")), -1, "receipt"), "WorkdayResult", "primary")
		return
	if not job.get("business", {}).is_empty():
		label.text = "本人が対応 · 別の仕事を進める間も受付期限が進みます"
		_button(ui, actions, "対応ソフトを開く", func(): ui._open_priority_work(str(job.id), int(job.target)), "WorkdayOpen", "primary")
		return
	if _show_handoff(job, ui.operations_choices):
		var accepted: Dictionary = job.handoff.get("acceptance", {})
		var destination := "receipt" if str(accepted.get("state", "unknown")) == "ready" else "verify"
		label.text = "担当作業の結果を引継ぎ · 納品は未完了"
		if str(job.get("status", "")) in ["working", "queued", "paused"]: label.text = "追加の担当作業あり · 保存された前回の記録"
		_button(ui, actions, "納品前確認へ" if destination == "receipt" else "受入検査へ", func(): _handoff_route(ui, job, destination), "WorkdayHandoffOpen", "primary")
		_button(ui, actions, "担当を追加", func():
			ui.operations_choices.workday_handoff_dispatch = true
			ui.operations_choices.workday_member = "self"
			ui._refresh_operations()
		, "WorkdayHandoffAssign", "quiet")
		return
	if not job.get("handoff", {}).get("receipts", []).is_empty():
		_button(ui, actions, "引継ぎへ戻る", func():
			ui.operations_choices.erase("workday_handoff_dispatch")
			ui._refresh_operations()
		, "WorkdayHandoffBack", "quiet")
	if member_id != "self":
		var candidate := _candidate(candidates, member_id)
		var can_enqueue := bool(candidate.get("can_enqueue", false))
		var reason := str(candidate.get("reason", candidate.get("forecast_reason", "")))
		var active: Dictionary = g._assignments.get(member_id, {})
		var queued: Array = g.dispatch_queue(member_id)
		var idle := str(active.get("status", "")) != "working" and queued.is_empty() and not bool(g.state.get("dispatch_holds", {}).get(member_id, false))
		var enqueue_text := "保守を配分" if str(job.get("kind", "")) == "maintenance" else "調査を配分"
		if idle: enqueue_text += "して開始"
		var enqueue := _button(ui, actions, enqueue_text, func(): _enqueue(ui, g, job, member_id, candidate, idle), "WorkdayEnqueue", "primary")
		enqueue.disabled = not can_enqueue
		enqueue.tooltip_text = reason if not reason.is_empty() else "選択した担当者のキューへ追加します。"
		_button(ui, actions, "仕事を開く", func(): _open_selected(ui, job), "WorkdayOpen", "secondary")
		_button(ui, actions, "担当一覧", func(): ui.operations_choices.view="staff"; ui._refresh_operations(), "WorkdayStaff", "quiet")
		return
	if str(job.get("kind", "")) == "maintenance":
		var can_run := bool(g.can_run_maintenance(str(job.get("client", ""))))
		var run := _button(ui, actions, "自分で点検を実行", func():
			if g.run_maintenance(str(job.get("client", ""))):
				ui.operations_choices.workday_feedback = "点検を完了しました。結果を記録しました。"
				ui._refresh_operations()
			else:
				var reason := str(g.maintenance_incident_reason(str(job.get("client", ""))))
				ui.operations_choices.workday_feedback = reason if not reason.is_empty() else "点検を開始できませんでした。状態を確認してください。"
				ui._refresh_operations()
		, "WorkdaySelfRun", "primary")
		run.disabled = not can_run
		if g.maintenance_incident_reason(str(job.get("client", ""))).is_empty():
			_button(ui, actions, "異常に対応", func(): ui._open_maintenance_incident(str(job.get("client", ""))), "WorkdayOpen", "secondary")
	else:
		_button(ui, actions, "自分で進める", func(): _open_selected(ui, job), "WorkdayOpen", "primary")

static func _open_selected(ui, job: Dictionary) -> void:
	if str(job.get("kind", "")) == "maintenance": ui._open_maintenance_incident(str(job.get("client", "")))
	else: ui._operations_open(str(job.get("id", "")), int(job.get("target", -1)))

static func _sync_dispatch_selection(choices: Dictionary, job: Dictionary, member_id: String) -> void:
	var maintenance := str(job.get("kind", "")) == "maintenance"
	var id := str(job.get("client", "")) if maintenance else str(job.get("id", ""))
	var selected := {"kind":"maintenance" if maintenance else "contract", "id":id, "target":int(job.get("target", -1)), "member":"" if member_id == "self" else member_id}
	choices.dispatch_selected = selected
	choices["dispatch_selected_maintenance" if maintenance else "dispatch_selected_contracts"] = selected.duplicate(true)

static func _candidate(candidates: Array, id: String) -> Dictionary:
	for raw in candidates:
		if raw is Dictionary and str(raw.get("id", "")) == id: return raw
	return {}

static func _member_name(candidates: Array, id: String) -> String:
	var candidate := _candidate(candidates, id)
	return str(candidate.get("name", id))

static func _job_label(job: Dictionary) -> String:
	var kind := str(job.get("kind", "normal"))
	var emblem := "↻" if kind == "maintenance" else "!" if kind == "emergency" else "¥" if bool(job.get("draft", false)) else "▣"
	var title := str(job.get("title", job.get("task_name", "仕事")))
	var target := str(job.get("target_name", ""))
	var deadline: Dictionary = job.get("deadline", {})
	var due := str(deadline.get("text", ""))
	if due.is_empty() and int(deadline.get("day", -1)) >= 0: due = "DAY%dまで" % int(deadline.day)
	if bool(job.get("completed", false)): due=""
	elif not job.get("business", {}).is_empty(): due="納品 " + due
	return "%s %s · %s%s" % [emblem, str(job.get("client", "")), title, (" / " + target if not target.is_empty() else "") + (" · " + due if not due.is_empty() else "")]

static func _status(job: Dictionary) -> String:
	if str(job.get("status", ""))=="legacy": return "従来型契約"
	if bool(job.get("draft", false)): return "請求待ち"
	if bool(job.get("completed", false)): return "完了"
	if not job.get("handoff", {}).get("receipts", []).is_empty() and str(job.get("status", "")) not in ["working", "queued", "paused"]:
		return "納品確認" if str(job.handoff.get("acceptance", {}).get("state", "")) == "ready" else "引継ぎ待ち"
	return {"ready":"検査済","working":"対応中","queued":"配分済","paused":"中断","pending":"対応待ち","late":"期限超過"}.get(str(job.get("status", "")), "未完了")

static func _show_handoff(job: Dictionary, choices: Dictionary) -> bool:
	return not bool(job.get("completed", false)) and not job.get("handoff", {}).get("receipts", []).is_empty() and not bool(choices.get("workday_handoff_dispatch", false))

static func _handoff_route(ui, job: Dictionary, route: String) -> void:
	if route == "record":
		ui.operations_choices.workday_record_open = not bool(ui.operations_choices.get("workday_record_open", false))
		ui._refresh_operations()
	else: ui._operations_open(str(job.get("id", "")), int(job.get("target", -1)), route)

static func _work_records(ui, parent: Node, job: Dictionary) -> void:
	for receipt in job.get("handoff", {}).get("receipts", []):
		var member := str(receipt.get("member_name", ""))
		if member.is_empty(): member = str(receipt.get("member_id", ""))
		member = {"aya":"綾", "ren":"蓮"}.get(member, member)
		var minute := int(receipt.get("completed_minute", -1))
		var day := int(receipt.get("completed_day", -1))
		var when := "時刻の記録なし" if minute < 0 or day < 0 else "DAY%d %02d:%02d" % [day, minute / 60, minute % 60]
		_label(ui, parent, member + " · " + str(receipt.get("phase", "作業記録")) + " · " + when, 14, M.INK)
		var report := TextEdit.new()
		report.name = "HandoffReport_" + str(receipt.get("member_id", "")).validate_node_name()
		report.text = str(receipt.get("report_content", receipt.get("result", "")))
		report.editable = false; report.context_menu_enabled = false
		report.custom_minimum_size.y = 160 * float(ui.text_scale)
		report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		report.add_theme_font_override("font", COPY.font(400))
		report.add_theme_font_size_override("font_size", roundi(13 * float(ui.text_scale)))
		report.add_theme_color_override("font_readonly_color", M.INK)
		report.add_theme_stylebox_override("read_only", M.surface(M.CANVAS, 10))
		report.gui_input.connect(func(event):
			if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
				var next := report.find_prev_valid_focus() if event.shift_pressed else report.find_next_valid_focus()
				if is_instance_valid(next): next.grab_focus()
				report.accept_event()
		)
		parent.add_child(report)

static func _money(job: Dictionary) -> String:
	if bool(job.get("draft", false)): return "¥%s" % _grouped(int(job.get("fee", 0)))
	if str(job.get("kind", "")) == "maintenance": return "+¥%s" % _grouped(int(job.get("fee", 0)))
	return "¥%s" % _grouped(int(job.get("fee", 0)))

static func _grouped(value: int) -> String:
	var text := str(value)
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3, 3) + out
		text = text.substr(0, text.length() - 3)
	return text + out

static func _label(ui, parent: Node, text: String, size: int, color: Color) -> Label:
	var label: Label = ui._label(text, size, color)
	if parent is HBoxContainer or parent is HFlowContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func _button(ui, parent: Node, text: String, callback: Callable, id: String, role: String) -> Button:
	var button: Button = ui._button(text, callback)
	button.name = id
	button.custom_minimum_size.y = 36 * float(ui.text_scale)
	button.add_theme_font_size_override("font_size", roundi(13 * float(ui.text_scale)))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	M.button(button, role)
	parent.add_child(button)
	return button

static func _restore_focus(ui, id: String) -> void:
	await ui.get_tree().process_frame
	if not is_instance_valid(ui) or ui.current_kind != "board": return
	var node := ui.modal.find_child(id, true, false) as Control
	if is_instance_valid(node) and node.is_visible_in_tree(): node.grab_focus()

static func _forecast_summary(job: Dictionary, candidates: Array, member_id: String) -> String:
	if job.is_empty(): return "受注 → 対応 → 納品 → 請求"
	if bool(job.get("draft", false)): return "%s · 納品済み / 請求未確定" % str(job.get("client", ""))
	if bool(job.get("completed", false)): return "%s · 結果を確認" % str(job.get("client", ""))
	if member_id == "self": return "日締めまでに点検 · 完了後に日額を計上" if str(job.kind)=="maintenance" else "本人が対応・受入検査・納品を行います"
	var candidate := _candidate(candidates,member_id)
	var reason := str(candidate.get("reason", ""))
	if not reason.is_empty(): return reason
	reason = str(candidate.get("forecast_reason", ""))
	if not reason.is_empty(): return "配分可 · 終了時刻未定 / "+reason
	return str(candidate.get("task_name", "調査工程"))+(" · 日締めに精算" if str(job.kind)=="maintenance" else " · 納品は本人が確認")

static func _enqueue(ui, g, job: Dictionary, member_id: String, candidate: Dictionary, idle: bool) -> void:
	var care: bool = str(job.get("kind", "")) == "maintenance"
	var ok: bool = g.dispatch_enqueue_maintenance(member_id,str(job.client)) if care else g.dispatch_enqueue(member_id,str(job.contract_id),int(job.target))
	if not ok:
		ui.operations_choices.workday_feedback = "配分を保存できませんでした。もう一度お試しください。"
		ui._refresh_operations()
		return
	var message := "配分しました。担当一覧で順番を確認できます。"
	if idle:
		var id := ""
		for queued in g.dispatch_queue(member_id):
			var match_job: bool = str(queued.get("kind", "normal"))=="maintenance" and str(queued.get("client", ""))==str(job.client) if care else str(queued.get("contract_id", ""))==str(job.contract_id) and int(queued.get("target_index", -1))==int(job.target)
			if match_job: id=str(queued.get("id", "")); break
		if not id.is_empty() and g.dispatch_start(member_id,id): message = "%sの%sを開始しました。" % [str(candidate.get("name", member_id)),"点検" if care else "調査"]
		else: message = "配分は保存済みです。担当一覧から開始を再試行できます。"
	ui.operations_choices.workday_feedback = message
	ui._refresh_operations()
