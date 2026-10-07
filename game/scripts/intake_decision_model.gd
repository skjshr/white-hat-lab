extends RefCounted
## Read-only company and offer projections for the intake decision surface.
## Never accepts, reserves, measures, synchronizes or persists work.

const BUSINESS_BRIEF = preload("res://scripts/priority_business_brief.gd")


static func company(g) -> Dictionary:
	if g == null or not g.get("state") is Dictionary:
		return _empty_company()
	var state: Dictionary = g.state.duplicate(true)
	var day := int(state.get("day", 1))
	var minute := int(g.clock_minutes()) if g.has_method("clock_minutes") else int(state.get("clock_minutes", 0))
	var contexts := _effective_contexts(g, state)
	var open_count := 0
	var self_work: Array = []
	for raw_id in contexts:
		var context_value: Variant = contexts[raw_id]
		if not context_value is Dictionary: continue
		var context: Dictionary = context_value
		var id := str(raw_id)
		if not _completed(state, id, context): open_count += 1
		if not bool(context.get("accepted", true)) or _completed(state, id, context): continue
		var contract: Dictionary = _dict(context.get("contract", {}))
		if _self_handled(contract):
			self_work.append({"id":id,"client":str(contract.get("client", "")),"title":str(contract.get("title", "")),"case_id":str(contract.get("case_id", ""))})
	# The intake canvas labels this count as care waiting today. Match the
	# workday's pending states; care-agreement renewals are a different concept.
	var care_pending := 0
	for job_value in _array(state.get("maintenance_jobs", [])):
		if not job_value is Dictionary: continue
		if int(job_value.get("day", day)) != day: continue
		if str(job_value.get("status", "")) in ["pending", "queued", "paused"]: care_pending += 1
	var people: Array = []
	var members: Array = g.team_members() if g.has_method("team_members") else []
	for member_value in members:
		if not member_value is Dictionary: continue
		var member: Dictionary = member_value
		var id := str(member.get("id", ""))
		var workload: Dictionary = g.staff_workload(id).duplicate(true) if g.has_method("staff_workload") else {}
		var runtime: Dictionary = g.colleague_runtime_availability(id).duplicate(true) if g.has_method("colleague_runtime_availability") else {"available":null,"registered":false}
		var jobs: Array = []
		for job_value in _array(workload.get("jobs", [])):
			if not job_value is Dictionary: continue
			jobs.append(_job_projection(job_value, contexts))
		var capacity_value := float(workload.get("capacity_minutes", -1.0))
		var available_value := float(workload.get("available_minutes", -1.0))
		var capacity_known := capacity_value >= 0.0
		var available_known := available_value >= 0.0
		people.append({
			"id":id,
			"name":str(member.get("name", id)),
			"role":str(member.get("role", "")),
			"hired":bool(member.get("hired", false)),
			"runtime_available":runtime.get("available", null),
			"runtime_registered":bool(runtime.get("registered", false)),
			"work_state":_person_state(jobs),
			"capacity_minutes":capacity_value if capacity_known else null,
			"capacity_known":capacity_known,
			"available_minutes":available_value if available_known else null,
			"available_known":available_known,
			"reserved_minutes":float(workload.get("reserved_minutes", 0.0)),
			"used_minutes":float(workload.get("used_minutes", 0.0)),
			"blocked_reason":str(workload.get("blocked_reason", "")),
			"jobs":jobs
		})
	var capacity := int(g.contract_capacity()) if g.has_method("contract_capacity") else 0
	return {
		"day":day,
		"clock_minute":minute,
		"clock_text":_clock_text(minute),
		"open_contracts":open_count,
		"contract_capacity":capacity,
		"free_contract_slots":maxi(0, capacity - open_count),
		"pending_care":care_pending,
		# This is the advanced-only subset that cannot be delegated to staff;
		# ordinary unfinished contracts still retain player verification/delivery.
		"own_unfinished_count":self_work.size(),
		"own_unfinished":self_work.duplicate(true),
		"people":people.duplicate(true)
	}


static func offer(g, offer_value: Dictionary) -> Dictionary:
	if g == null or not offer_value is Dictionary:
		return {"available":false,"reason":"offer_unavailable"}
	var source := offer_value.duplicate(true)
	var quote: Dictionary = g.contract_quote(source).duplicate(true) if g.has_method("contract_quote") else {}
	var specs: Array = _array(source.get("target_specs", []))
	var target_value: Variant = source.get("targets", specs.size())
	var target_count := int(target_value) if typeof(target_value) in [TYPE_INT, TYPE_FLOAT] else specs.size()
	if target_count <= 0: target_count = specs.size()
	var advanced := _self_handled(source)
	var supply: Dictionary = g.offer_operations_preview(source).duplicate(true) if g.has_method("offer_operations_preview") else {}
	var brief: Dictionary = BUSINESS_BRIEF.from_offer(source) if str(source.get("case_id", "")) == str(BUSINESS_BRIEF.CASE_ID) else {}
	var priority: Dictionary = _priority_deadlines(brief)
	var quote_budget := float(quote.get("budget", 0.0))
	var output := {
		"available":true,
		"id":str(source.get("id", "")),
		"case_id":str(source.get("case_id", "")),
		"category":str(source.get("category", "advisory")),
		"client":str(source.get("client", "")),
		"title":str(source.get("title", "")),
		"targets":specs.duplicate(true),
		"target_count":target_count,
		"advanced":advanced,
		"handling_mode":"self_after_acceptance" if advanced else "dispatch_after_acceptance",
		"quote":quote.duplicate(true),
		"fee":int(quote.get("estimated_fee", quote.get("quoted_fee", 0))),
		"base_cost":int(quote.get("costs", 0)),
		"profit":int(quote.get("net", 0)),
		"invoice_total":int(quote.get("invoice_total", 0)),
		"deadline_budget_minutes":quote_budget,
		"deadline_budget_semantics":"delivery_deadline_budget",
		"delivery_deadline_text":str(quote.get("deadline_text", "")),
		"supply":supply.duplicate(true),
		"supply_shortage":int(supply.get("shortage", 0)),
		"supply_shortage_cost":int(supply.get("purchase_cost", 0)),
		"priority_business":priority
	}
	return output.duplicate(true)


static func _empty_company() -> Dictionary:
	return {"day":0,"clock_minute":-1,"clock_text":"時刻不明","open_contracts":0,"contract_capacity":0,"free_contract_slots":0,"pending_care":0,"own_unfinished_count":0,"own_unfinished":[],"people":[]}


static func _effective_contexts(g, state: Dictionary) -> Dictionary:
	var contexts: Dictionary = _dict(state.get("contract_contexts", {})).duplicate(true)
	var id := str(state.get("current_contract_id", ""))
	if id.is_empty() or not bool(state.get("accepted", false)): return contexts
	var context: Dictionary = _dict(contexts.get(id, {})).duplicate(true)
	context["id"] = id
	for key in ["chapter", "contract", "contract_plan", "accepted", "targets", "work", "advanced"]:
		if state.has(key): context[key] = _copy_value(state[key])
	context["completed"] = _completed(state, id, context)
	contexts[id] = context
	return contexts


static func _completed(state: Dictionary, id: String, context: Dictionary) -> bool:
	return bool(context.get("completed", false)) or _array(state.get("completed_ids", [])).has(id)


static func _self_handled(contract: Dictionary) -> bool:
	var case_id := str(contract.get("case_id", ""))
	return case_id.begins_with("advanced-") or str(contract.get("console", "")) == "advanced"


static func _job_projection(raw: Dictionary, contexts: Dictionary = {}) -> Dictionary:
	var start_day := int(raw.get("start_day", -1))
	var start_minute := int(raw.get("start_minute", -1))
	var finish_day := int(raw.get("finish_day", -1))
	var finish_minute := int(raw.get("finish_minute", -1))
	var reason := str(raw.get("blocked_reason", ""))
	var time_known := start_day >= 0 and start_minute >= 0 and finish_day >= 0 and finish_minute >= 0 and reason.is_empty()
	var raw_status := str(raw.get("status", ""))
	var state := "working" if raw_status == "working" else "waiting" if raw_status in ["queued", "pending", "paused"] else "unknown_time"
	if not time_known: state = "unknown_time"
	var client := str(raw.get("client", ""))
	var contract_title := ""
	if client.is_empty():
		var context: Dictionary = _dict(contexts.get(str(raw.get("contract_id", "")), {}))
		var contract: Dictionary = _dict(context.get("contract", {}))
		client = str(contract.get("client", ""))
		contract_title = str(contract.get("title", ""))
	return {
		"id":str(raw.get("id", "")),
		"contract_id":str(raw.get("contract_id", "")),
		"kind":str(raw.get("kind", "normal")),
		"client":client,
		"contract_title":contract_title,
		"status":raw_status,
		"state":state,
		"start_day":start_day if time_known else -1,
		"start_minute":start_minute if time_known else -1,
		"finish_day":finish_day if time_known else -1,
		"finish_minute":finish_minute if time_known else -1,
		"remaining_minutes":float(raw.get("remaining_minutes", 0.0)),
		"risk":str(raw.get("risk", "unknown")),
		"blocked":not reason.is_empty() or str(raw.get("risk", "")) == "blocked",
		"blocked_reason":reason,
		"time_known":time_known
	}


static func _person_state(jobs: Array) -> String:
	if jobs.is_empty(): return "standby"
	for job in jobs:
		if str(job.get("state", "")) == "working": return "working"
	for job in jobs:
		if str(job.get("state", "")) == "waiting": return "waiting"
	return "unknown_time"


static func _priority_deadlines(brief: Dictionary) -> Dictionary:
	if brief.is_empty(): return {}
	if not bool(brief.get("available", false)):
		return {"available":false}
	var queues: Array = []
	for raw in _array(brief.get("queues", [])):
		if not raw is Dictionary: continue
		queues.append({
			"id":str(raw.get("id", "")),
			"label":str(raw.get("label", "")),
			"deadline_minute":int(raw.get("deadline", -1)),
			"remaining_minutes":int(raw.get("remaining", -1)),
			"late_compensation":int(raw.get("late_cost", 0)),
			"already_late":bool(raw.get("late", false))
		})
	return {"available":true,"elapsed_minutes":int(brief.get("elapsed", 0)),"queues":queues.duplicate(true)}


static func _clock_text(total_minutes: int) -> String:
	if total_minutes < 0: return "時刻不明"
	return "%02d:%02d" % [int(total_minutes / 60) % 24, posmod(total_minutes, 60)]


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _array(value: Variant) -> Array:
	return value if value is Array else []


static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary: return value.duplicate(true)
	if value is Array: return value.duplicate(true)
	return value
