extends RefCounted
## Read-only company view of saved care agreements, scopes, checks and payroll.
## It intentionally avoids maintenance_jobs()/maintenance_summary(), which may
## prepare and persist today's work when called on the live game.

const CARE = preload("res://scripts/care_lifecycle.gd")

static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]

static func _member_name(g, member_id: String) -> String:
	if member_id.is_empty(): return ""
	if g != null and g.has_method("member_name"):
		var name := str(g.call("member_name", member_id))
		return name if name != member_id else ""
	return ""

static func _scope_projection(state: Dictionary, client: String, job: Dictionary, job_known: bool) -> Dictionary:
	var targets: Variant = null
	var targets_known := false
	var scopes: Variant = state.get("maintenance_targets", null)
	if scopes is Dictionary and scopes.has(client) and scopes[client] is Array:
		targets = scopes[client]
		targets_known = true
	elif job_known and job.get("targets", null) is Array:
		# A retained job can be the only surviving copy in an older save.
		targets = job["targets"]
		targets_known = true
	var result: Array = []
	if not targets_known:
		return {"scope":result,"scope_known":false}
	for raw in targets:
		if not raw is Dictionary:
			targets_known = false
			continue
		var scenario: Dictionary = raw.get("scenario", {}) if raw.get("scenario", {}) is Dictionary else {}
		var name := str(raw.get("name", scenario.get("title", ""))).strip_edges()
		if name.is_empty():
			targets_known = false
			continue
		if not raw.has("chapter") or not _is_number(raw.get("chapter")):
			targets_known = false
			continue
		result.append({"name":name,"chapter":int(raw.get("chapter")),"asset_id":str(raw.get("asset_id", ""))})
	return {"scope":result,"scope_known":targets_known}

static func _today_job(state: Dictionary, client: String, day: int) -> Dictionary:
	var records: Variant = state.get("maintenance_jobs", null)
	if not records is Array: return {"known":false,"job":{}}
	for row in records:
		if row is Dictionary and str(row.get("client", "")) == client and int(row.get("day", -1)) == day:
			return {"known":true,"job":row.duplicate(true)}
	return {"known":true,"job":{}}

static func _assignment_for(g, state: Dictionary, client: String, job: Dictionary) -> Dictionary:
	var saved_assignee := str(job.get("assignee", ""))
	if not saved_assignee.is_empty(): return {"member_id":saved_assignee,"status":str(job.get("status", "")),"remaining":job.get("remaining", -1.0),"total":job.get("total", -1.0),"result":job.get("result", "")}
	var active: Variant = g.get("_assignments") if g != null else null
	if active is Dictionary:
		for member_id in active:
			var item: Variant = active[member_id]
			if item is Dictionary and str(item.get("kind", "")) == "maintenance" and str(item.get("client", "")) == client:
				return {"member_id":str(member_id),"status":str(item.get("status", "")),"remaining":item.get("remaining", -1.0),"total":item.get("total", -1.0),"result":item.get("result", "")}
	var persisted: Variant = state.get("assignments", {})
	if persisted is Dictionary:
		for member_id in persisted:
			var item: Variant = persisted[member_id]
			if item is Dictionary and str(item.get("kind", "")) == "maintenance" and str(item.get("client", "")) == client:
				return {"member_id":str(member_id),"status":str(item.get("status", "")),"remaining":item.get("remaining", -1.0),"total":item.get("total", -1.0),"result":item.get("result", "")}
	var queues: Variant = state.get("dispatch_queues", {})
	if queues is Dictionary:
		for member_id in queues:
			if not queues[member_id] is Array: continue
			for item in queues[member_id]:
				if item is Dictionary and str(item.get("kind", "")) == "maintenance" and str(item.get("client", "")) == client:
					return {"member_id":str(member_id),"status":str(item.get("status", "queued")),"remaining":item.get("remaining", -1.0),"total":item.get("total", -1.0),"result":item.get("result", "")}
	return {}

static func _settled_earned(state: Dictionary, day: int) -> int:
	var daily: Variant = state.get("retainer_daily", {})
	if daily is Dictionary:
		var row: Variant = daily.get(str(day), {})
		if row is Dictionary:
			if _is_number(row.get("maintenance_earned", null)): return int(row["maintenance_earned"])
			if _is_number(row.get("retainer_gross", null)): return int(row["retainer_gross"])
	var history: Variant = state.get("history", [])
	if history is Array:
		for entry in history:
			if entry is Dictionary and str(entry.get("id", "")) == "retainer-day-%d" % day:
				if _is_number(entry.get("maintenance_earned", null)): return int(entry["maintenance_earned"])
				if _is_number(entry.get("retainer_gross", null)): return int(entry["retainer_gross"])
	return -1

static func _service_cost(state: Dictionary, day: int, active_count: int) -> int:
	if int(state.get("retainer_settled_day", -1)) == day:
		var daily: Variant = state.get("retainer_daily", {})
		if daily is Dictionary:
			var row: Variant = daily.get(str(day), {})
			if row is Dictionary:
				if _is_number(row.get("retainer_cost", null)): return int(row["retainer_cost"])
				if _is_number(row.get("maintenance_cost", null)): return int(row["maintenance_cost"])
		return -1
	return active_count * 100

static func _earned_for_client(state: Dictionary, agreement: Dictionary, scope: Dictionary, job_entry: Dictionary, day: int, settled: bool, active: bool, status_known: bool) -> int:
	var fee: Variant = agreement.get("fee", null)
	if not _is_number(fee): return -1
	if not status_known: return -1
	if not active: return 0
	var scope_known := bool(scope.get("scope_known", false))
	var targets: Array = scope.get("scope", [])
	var legacy := bool(agreement.get("maintenance_legacy", false))
	# Older agreements retain a guaranteed fee, but their original covered
	# targets were not migrated. Keep those two facts independent.
	if legacy: return int(fee)
	if not scope_known: return -1
	if targets.is_empty(): return int(fee)
	if not bool(job_entry.get("known", false)): return -1
	var job: Dictionary = job_entry.get("job", {})
	if job.is_empty(): return 0
	var status := str(job.get("status", ""))
	if status != "done": return 0
	if not job.has("fee") or not _is_number(job.get("fee")): return -1
	if settled:
		if not job.has("paid"): return -1
		return int(job.get("fee", 0)) if bool(job.get("paid", false)) else 0
	if bool(job.get("paid", false)): return -1
	return int(job.get("fee", 0))

static func snapshot(g) -> Dictionary:
	var unavailable := {"available":false,"day":-1,"capacity":-1,"reserved_count":-1,"expected_revenue":-1,"service_cost":-1,"earned":-1,"company_payroll":-1,"expected_after_payroll":-1,"actual_after_payroll":-1,"payroll_known":false,"revenue_known":false,"clients":[]}
	if g == null or not g.get("state") is Dictionary: return unavailable
	var state: Dictionary = g.get("state")
	var agreements: Variant = state.get("care_agreements", null)
	if not state.has("day") or not agreements is Dictionary: return unavailable
	var day := int(state.get("day", -1))
	var relations: Variant = state.get("customer_relations", {})
	var scopes: Variant = state.get("maintenance_targets", null)
	var records: Variant = state.get("maintenance_jobs", null)
	var payroll: Variant = state.get("staff_payroll", null)
	var skills: Variant = state.get("skills", null)
	var equipment: Variant = state.get("equipment", null)
	var capacity_known: bool = skills is Dictionary and skills.has("operations") and _is_number(skills.get("operations")) and equipment is Array
	var capacity := 2 + int(skills.get("operations", 0)) if capacity_known else -1
	if capacity_known:
		if "monitor" in equipment: capacity += 2
		if "teamdesk" in equipment: capacity += 2
		if "annexdesk_a" in equipment: capacity += 1
		if "annexdesk_b" in equipment: capacity += 1
	var payroll_known: bool = payroll is Dictionary and payroll.get("due", null) is Array
	var company_payroll := 0
	if payroll_known:
		for row in payroll.get("due", []):
			if not row is Dictionary or not row.has("day") or not _is_number(row.get("day")) or not row.has("amount") or not _is_number(row.get("amount")):
				payroll_known = false
				break
			if int(row.get("day", -1)) == day: company_payroll += int(row.get("amount", 0))
	if not payroll_known: company_payroll = -1
	var settled := int(state.get("retainer_settled_day", -1)) == day
	var saved_earned := _settled_earned(state, day) if settled else -1
	var saved_cost := _service_cost(state, day, 0) if settled else -1
	var clients: Array = []
	var ids: Array = agreements.keys()
	ids.sort()
	var active_count := 0
	var reserved_count := 0
	var expected_revenue := 0
	var expected_known := true
	var calculated_earned := 0
	var calculated_earned_known := true
	var client_status_known := true
	for raw_client in ids:
		var client := str(raw_client)
		var agreement_value: Variant = agreements[raw_client]
		if not agreement_value is Dictionary:
			client_status_known = false
			continue
		var agreement: Dictionary = agreement_value
		var relation_value: Variant = relations.get(client, {}) if relations is Dictionary else {}
		var relation: Dictionary = relation_value if relation_value is Dictionary else {}
		var satisfaction := clampi(int(relation.get("satisfaction", 70)), 0, 100)
		var status_known := agreement.has("active")
		var active := bool(agreement.get("active", false)) and satisfaction >= 40
		var pending := bool(agreement.get("pending", false))
		var status := "active" if active else "pending" if pending else "suspended"
		if not status_known: status = "unknown"
		if not status_known: client_status_known = false
		if status == "active": active_count += 1; reserved_count += 1
		elif status == "pending": reserved_count += 1
		var fee_known := agreement.has("fee") and _is_number(agreement.get("fee"))
		var fee := int(agreement.get("fee", -1)) if fee_known else -1
		var cost := 100 if status == "active" else 0 if status in ["pending", "suspended"] else -1
		var job_entry := _today_job(state, client, day)
		var job: Dictionary = job_entry.get("job", {})
		var scope := _scope_projection(state, client, job, bool(job_entry.get("known", false)))
		var current_assignment := _assignment_for(g, state, client, job)
		var assignee := str(current_assignment.get("member_id", agreement.get("assignee", "")))
		var owner := str(agreement.get("maintenance_owner", "")) if agreement.has("maintenance_owner") else ""
		var current_status := str(job.get("status", "unknown")) if not job.is_empty() else ("not_created" if bool(job_entry.get("known", false)) else "unknown")
		var result_known := not job.is_empty() and job.has("result")
		var result_value: Variant = job.get("result", null)
		if not result_known and current_assignment.has("result"):
			result_known = true
			result_value = current_assignment.get("result")
		var incident: Dictionary = CARE.visible(g, client)
		var client_earned := _earned_for_client(state, agreement, scope, job_entry, day, settled, status == "active", status_known)
		if status == "active":
			if not fee_known: expected_known = false
			else: expected_revenue += fee
			if client_earned < 0: calculated_earned_known = false
			else: calculated_earned += client_earned
		clients.append({
			"client":client,"fee":fee,"fee_known":fee_known,"cost":cost,
			"status":status,"status_known":status_known,"satisfaction":satisfaction,
			"scope":scope.get("scope", []),"scope_known":scope.get("scope_known", false),
			"owner":owner,"owner_known":agreement.has("maintenance_owner"),"owner_name":_member_name(g, owner),
			"assignee":assignee,"assignee_name":_member_name(g, assignee),
			"job_status":current_status,"job_known":bool(job_entry.get("known", false)),
			"remaining":current_assignment.get("remaining", job.get("remaining", -1.0)),
			"total":current_assignment.get("total", job.get("total", -1.0)),
			"result":result_value if result_known else null,"result_known":result_known,
			"incident":incident,"earned_today":client_earned,"earned_known":client_earned >= 0
		})
	var service_cost := active_count * 100 if client_status_known else -1
	if settled:
		expected_revenue = saved_earned
		expected_known = saved_earned >= 0
		calculated_earned = saved_earned
		calculated_earned_known = saved_earned >= 0
		service_cost = saved_cost
	var earned := calculated_earned if calculated_earned_known else -1
	var after_expected := expected_revenue - service_cost - company_payroll if expected_known and service_cost >= 0 and payroll_known else -1
	var after_actual := earned - service_cost - company_payroll if earned >= 0 and service_cost >= 0 and payroll_known else -1
	return {
		"available":true,"day":day,"capacity":capacity if capacity_known else -1,
		"reserved_count":reserved_count if client_status_known else -1,
		"expected_revenue":expected_revenue if expected_known else -1,
		"revenue_known":expected_known,"service_cost":service_cost,"earned":earned,
		"company_payroll":company_payroll,"payroll_known":payroll_known,
		"expected_after_payroll":after_expected,"actual_after_payroll":after_actual,
		"clients":clients
	}
