extends RefCounted
## Read model for the workday. Existing queue APIs may synchronize their saved
## projection; this helper never reserves work, measures a VM, or writes state.
const FORECAST = preload("res://scripts/dispatch_forecast.gd")
const OPERATIONS = preload("res://scripts/operations_dispatch.gd")
const COPY = preload("res://scripts/ui_theme.gd")

static func _kind(contract: Dictionary, plan: String) -> String:
	if not str(contract.get("maintenance_incident_id", "")).is_empty() or plan == "priority": return "emergency"
	if "緊急" in str(contract.get("title", "")) or "緊急" in str(contract.get("service", "")): return "emergency"
	return "normal"

static func _invoice(g, contract_id: String) -> Dictionary:
	for raw in g.state.get("billing", {}).get("invoices", []):
		if raw is Dictionary and str(raw.get("contract_id", "")) == contract_id: return raw.duplicate(true)
	return {}

static func _task_name(role: String, maintenance: bool) -> String:
	if maintenance: return "保守点検"
	return "調査工程（復旧・証拠の確認）" if role == "ren" else "調査工程（設定・ログの確認）"

static func _assignments(g, contract_id: String, target: int) -> Array:
	var out: Array = []
	for member in g.team_members():
		var member_id := str(member.id)
		var rows: Array = []
		var active: Dictionary = g._assignments.get(member_id, {})
		if not active.is_empty(): rows.append(active)
		rows.append_array(g.state.get("dispatch_queues", {}).get(member_id, []))
		for raw in rows:
			if str(raw.get("kind", "normal")) != "normal" or str(raw.get("contract_id", "")) != contract_id or int(raw.get("target_index", -1)) != target: continue
			out.append({"member":member_id,"name":str(member.name),"id":str(raw.get("id", "")),"status":str(raw.get("status", "")),"task_name":_task_name(str(member.role), false)})
	return out

static func _contracts(g, queue: Array) -> Array:
	var jobs: Array = []
	for row in queue:
		var id := str(row.id)
		var context: Dictionary = g.state.get("contract_contexts", {}).get(id, {})
		var contract: Dictionary = context.get("contract", {})
		var targets: Array = context.get("targets", [])
		var invoice := _invoice(g, id)
		var completed := bool(row.get("completed", false))
		var draft := completed and str(invoice.get("status", "")) == "draft"
		var deadline := FORECAST._deadline(g, {"kind":"normal","contract_id":id})
		deadline.kind = "contract"; deadline.text = str(row.get("deadline_text", ""))
		var row_count := 1 if completed else maxi(1, targets.size())
		for index in row_count:
			var target: Dictionary = targets[index] if not completed and index < targets.size() else {}
			var target_index := index if not completed and not targets.is_empty() else -1
			var assignments := _assignments(g, id, target_index)
			var ready := bool(OPERATIONS._target_checks(target).done)
			var status := "draft" if draft else "completed" if completed else "ready" if ready else "pending"
			if not completed:
				for state in ["working", "paused", "queued"]:
					if assignments.any(func(item): return str(item.status) == state): status = state; break
			jobs.append({"key":"contract:%s:%d" % [id,target_index],"id":id,"contract_id":id,"kind":_kind(contract,str(row.get("plan", ""))),"client":str(row.get("client", "")),"title":str(row.get("title", "")),"status":status,"completed":completed,"draft":draft,"remaining":float(row.get("remaining", 0.0)),"remaining_kind":"deadline","deadline":deadline.duplicate(true),"fee":int(invoice.get("amount", row.get("fee", 0))) if completed else int(row.get("fee", 0)),"fee_scope":"invoice" if completed and not invoice.is_empty() else "contract","target":target_index,"target_name":str(target.get("name", "")),"target_count":targets.size(),"task_name":"請求確定" if draft else "納品済み" if completed else "調査工程","assignments":assignments,"invoice":invoice.duplicate(true),"active":bool(row.get("active", false)),"late_minutes":int(row.get("late_minutes", 0))})
	# A day change archives completed contexts, but their unposted invoices remain.
	for invoice in g.state.get("billing", {}).get("invoices", []):
		if not invoice is Dictionary or str(invoice.get("status", "")) != "draft": continue
		var id := str(invoice.get("contract_id", ""))
		if queue.any(func(item): return str(item.id) == id): continue
		jobs.append({"key":"invoice:"+str(invoice.id),"id":id,"contract_id":id,"kind":_kind(invoice,""),"client":str(invoice.get("client", "")),"title":str(invoice.get("title", "")),"status":"draft","completed":true,"draft":true,"remaining":0.0,"remaining_kind":"none","deadline":{"kind":"none","day":-1,"minute":-1,"absolute":-1,"text":""},"fee":int(invoice.get("amount", 0)),"fee_scope":"invoice","target":-1,"target_name":"","target_count":0,"task_name":"請求確定","assignments":[],"invoice":invoice.duplicate(true),"active":false,"late_minutes":0})
	return jobs

static func _maintenance(g, rows: Array) -> Array:
	var jobs: Array = []
	for row in rows:
		var status := str(row.get("status", "pending"))
		jobs.append({"key":"maintenance:"+str(row.id),"id":str(row.id),"contract_id":"","kind":"maintenance","client":str(row.client),"title":"日次保守点検","status":status,"completed":status in ["done", "legacy"],"draft":false,"remaining":float(row.get("remaining", 0.0)),"remaining_kind":"work","deadline":{"kind":"day_end","day":int(g.state.day),"minute":-1,"absolute":-1,"text":"日締めまで"},"fee":int(row.get("fee", 0)),"fee_scope":"maintenance","cost":int(row.get("cost", 0)),"target":-1,"target_name":"保守対象","target_count":g._maintenance_targets_for(str(row.client)).size(),"task_name":"保守点検","assignee":str(row.get("assignee", "")),"assignments":[],"invoice":{},"active":status == "working","late_minutes":0})
	return jobs

static func candidates(g, job: Dictionary) -> Array:
	var out: Array = []
	if job.is_empty(): return out
	var maintenance := str(job.get("kind", "")) == "maintenance"
	var contract_id := str(job.get("contract_id", job.get("id", "")))
	var client := str(job.get("client", ""))
	var target := int(job.get("target", -1))
	for member in g.team_members():
		var member_id := str(member.id)
		var reason := ""
		var duplicate := false
		var quote: Dictionary = {}
		if bool(job.get("completed", false)): reason = "納品済みの仕事は配分できません。" if not maintenance else "本日の保守点検は完了しています。"
		else:
			var request := {"member_id":member_id,"kind":"maintenance" if maintenance else "normal","contract_id":contract_id,"client":client,"target_index":target}
			reason = str(g._dispatch_reason(request, false))
			duplicate = bool(g._dispatch_duplicate(member_id, str(request.kind), contract_id, target, client))
			if duplicate: reason = COPY.copy("dispatch_duplicate", "同じ工程を配分済みです。")
			if reason.is_empty(): quote = g.maintenance_quote_forecast(member_id, client) if maintenance else g.dispatch_quote_forecast(member_id, contract_id, target)
		var projection: Dictionary = quote.get("job", {})
		var forecast_reason := str(quote.get("blocked_reason", ""))
		var can_finish := reason.is_empty() and forecast_reason.is_empty() and int(projection.get("finish_day", -1)) >= 0
		var risk := str(projection.get("risk", "blocked")) if can_finish else "blocked"
		if maintenance and can_finish:
			# No fictitious closing hour: a next-day inspection misses today's fee.
			risk = "next_day" if int(projection.finish_day) > int(g.state.day) else "day_end"
		out.append({"member":member_id,"id":member_id,"name":str(member.name),"role":str(member.role),"task_name":_task_name(str(member.role),maintenance),"ok":reason.is_empty(),"can_enqueue":reason.is_empty(),"can_finish":can_finish,"duplicate":duplicate,"reason":reason,"forecast_reason":forecast_reason,"finish_day":int(projection.get("finish_day", -1)) if can_finish else -1,"finish_minute":int(projection.get("finish_minute", -1)) if can_finish else -1,"risk":risk,"duration_minutes":float(quote.get("duration_minutes", 0.0)),"late_minutes":int(projection.get("late_minutes", 0)),"projection":projection.duplicate(true)})
	return out

static func snapshot(g, selected_key: String = "") -> Dictionary:
	var queue: Array = g.contract_queue()
	var maintenance: Array = g.maintenance_jobs()
	var jobs := _contracts(g, queue)
	jobs.append_array(_maintenance(g, maintenance))
	var selected: Dictionary = {}
	var counts := {"open":0,"maintenance":0,"completed":0,"draft":0}
	for job in jobs:
		if str(job.key) == selected_key: selected = job
		if bool(job.completed): counts.completed += 1
		else: counts.open += 1
		if str(job.kind) == "maintenance" and not bool(job.completed): counts.maintenance += 1
		if bool(job.draft): counts.draft += 1
	var people: Array = []
	for member in g.team_members():
		var person: Dictionary = member.duplicate(true)
		var workload: Dictionary = g.staff_workload(str(member.id)).duplicate(true)
		person.shift_limited = bool(member.get("hired", false))
		if not bool(person.shift_limited): workload.shift_start = -1; workload.shift_end = -1
		person.shift_start = int(workload.get("shift_start", -1)); person.shift_end = int(workload.get("shift_end", -1))
		person.workload = workload; person.task_name = _task_name(str(member.role), false)
		people.append(person)
	return {"day":int(g.state.day),"clock_minute":int(g.clock_minutes()),"jobs":jobs,"people":people,"economy":g.day_preview().duplicate(true),"selected_key":str(selected.get("key", "")),"candidates":candidates(g,selected),"counts":counts}

static func signature(g) -> String:
	# Structure invalidation only. The UI updates clocks, remaining labor and
	# candidate forecasts in place instead of rebuilding a focused control.
	var shape: Array = [int(g.state.day),str(g.state.get("current_contract_id", ""))]
	for row in g.contract_queue():
		var context: Dictionary = g.state.get("contract_contexts", {}).get(str(row.id), {})
		var targets: Array = []
		for target in context.get("targets", []): targets.append([str(target.get("name", "")),bool(OPERATIONS._target_checks(target).done)])
		shape.append(["contract",str(row.id),str(row.title),bool(row.completed),targets])
	for job in g.maintenance_jobs(): shape.append(["maintenance",str(job.id),str(job.status),str(job.get("assignee", "")),g.maintenance_owner(str(job.client))])
	for member in g.team_members():
		var id := str(member.id)
		var tasks: Array = []
		var active: Dictionary = g._assignments.get(id, {})
		if not active.is_empty(): tasks.append([str(active.get("id", "")),str(active.get("status", "")),str(active.get("kind", "normal")),str(active.get("contract_id", "")),int(active.get("target_index", -1))])
		for job in g.state.get("dispatch_queues", {}).get(id, []): tasks.append([str(job.get("id", "")),str(job.get("status", ""))])
		shape.append(["person",member,tasks,bool(g.state.get("dispatch_holds", {}).get(id, false))])
	for invoice in g.state.get("billing", {}).get("invoices", []):
		if invoice is Dictionary: shape.append(["invoice",str(invoice.get("id", "")),str(invoice.get("status", ""))])
	return JSON.stringify(shape)
