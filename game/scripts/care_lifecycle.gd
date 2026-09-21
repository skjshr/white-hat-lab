extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")
const DRIFT = preload("res://scripts/maintenance_incidents.gd")

static func _next_day(g, client: String) -> int:
	return int(g.state.day) + 3 + posmod(client.hash(), 3)

static func _busy_client(g, client: String) -> bool:
	for context in g.state.get("contract_contexts", {}).values():
		if not bool(context.get("completed", false)) and str(context.get("contract", {}).get("client", "")) == client: return true
	return false

static func advance_day(g) -> void:
	for client in g.state.care_agreements.keys():
		var agreement: Dictionary = g.state.care_agreements[client]
		if not bool(agreement.get("active", false)) or g._maintenance_targets_for(client).is_empty(): continue
		var existing: Dictionary = g.state.care_incidents.get(client, {})
		if str(existing.get("status", "closed")) != "closed" or _busy_client(g, client): continue
		if not agreement.has("next_incident_day"):
			agreement.next_incident_day = _next_day(g, client)
			continue
		if int(g.state.day) < int(agreement.next_incident_day): continue
		var id := "care-%s-%d" % [str(client).sha256_text().left(10), int(g.state.day)]
		var changed: Dictionary = DRIFT.introduce(g._maintenance_targets_for(client), id)
		if not bool(changed.get("changed", false)): continue
		g.state.maintenance_targets[client] = changed.targets
		g.state.care_incidents[client] = {"id":id, "client":client, "status":"latent", "kind":changed.kind, "target_index":changed.target_index, "occurred_day":int(g.state.day), "detected_day":-1, "contract_id":"", "inspection_result":"", "resolved_day":-1}

static func visible(g, client: String) -> Dictionary:
	var item: Dictionary = g.state.get("care_incidents", {}).get(client, {})
	return item.duplicate(true) if str(item.get("status", "")) in ["detected", "working", "recheck", "closed"] else {}

static func record_check(g, job: Dictionary, result: Dictionary) -> void:
	var client := str(job.get("client", ""))
	g.state.maintenance_targets[client] = job.get("targets", []).duplicate(true)
	var item: Dictionary = g.state.care_incidents.get(client, {})
	if bool(result.passed):
		if str(item.get("status", "")) in ["latent", "detected", "recheck"]:
			item.status = "closed"; item.resolved_day = int(g.state.day); item.inspection_result = str(result.log)
			if int(g.state.customer_relations.get(client,{}).get("satisfaction",0)) >= 40: g._activate_care(client)
			g.state.care_agreements[client].next_incident_day = _next_day(g, client)
		return
	if item.is_empty() or str(item.get("status", "")) == "closed":
		var kinds := ["share", "backup", "network", "account", "incident", "portal"]
		var targets: Array = job.get("targets", [])
		var chapter := int(targets[0].get("chapter", 0)) if not targets.is_empty() else 0
		item = {"id":"care-%s-%d" % [client.sha256_text().left(10), int(g.state.day)], "client":client, "kind":kinds[clampi(chapter,0,5)], "occurred_day":int(g.state.day), "contract_id":"", "resolved_day":-1}
	if str(item.get("status", "")) != "working":
		item.status = "detected"; item.detected_day = int(g.state.day); item.inspection_result = str(result.log)
	g.state.care_incidents[client] = item

static func reason(g, client: String) -> String:
	var item := visible(g, client)
	if str(item.get("status", "")) == "working":
		return "" if g.state.contract_contexts.has(str(item.get("contract_id", ""))) else UI.copy("care_incident_unavailable")
	if str(item.get("status", "")) != "detected" or g._maintenance_targets_for(client).is_empty(): return UI.copy("care_incident_unavailable")
	var maintenance_status := str(g._maintenance_job_for(client).get("status", ""))
	if _busy_client(g, client) or maintenance_status in ["working", "paused"] or (g.has_method("_dispatch_has_queued_maintenance") and bool(g.call("_dispatch_has_queued_maintenance", client))): return UI.copy("care_incident_working")
	if g._open_contract_count() >= g.contract_capacity(): return UI.copy("care_incident_capacity")
	return ""

static func open_ticket(g, client: String) -> bool:
	if not bool(g.state.get("career_mode", false)) or not reason(g, client).is_empty(): return false
	var incident: Dictionary = g.state.care_incidents[client]
	if str(incident.status) == "working": return g.switch_contract(str(incident.contract_id))
	var before: Dictionary = g.state.duplicate(true)
	var old_machine = g._machine; var old_key: String = g._machine_key
	g._sync_contract_context()
	var id := str(incident.id)
	if id in g.state.completed_ids or g.state.contract_contexts.has(id): return false
	var saved_targets: Array = g._maintenance_targets_for(client)
	var chapter := int(saved_targets[0].chapter)
	var contract := {"id":id,"case_id":str(saved_targets[0].get("scenario",{}).get("id","")),"chapter":chapter,"title":UI.copy("care_incident_subject") % client,"client":client,"brief":UI.copy("care_incident_brief") % [client,int(incident.detected_day)],"service":UI.copy("care_incident_kind_"+str(incident.kind)),"category":g.CATEGORIES[chapter],"grade":1,"targets":saved_targets.size(),"target_specs":[],"reward":0,"agreed_fee":0,"agreed_budget":180.0*saved_targets.size(),"required_level":1,"required_credit":0,"maintenance_incident_id":id,"maintenance_client":client}
	var targets: Array = []
	for index in saved_targets.size():
		var saved: Dictionary = saved_targets[index]; var scenario: Dictionary = saved.get("scenario",{}).duplicate(true)
		targets.append({"maintenance_asset_id":str(saved.get("asset_id","")),"chapter":int(saved.chapter),"case_id":str(scenario.get("id","")),"scenario":scenario,"name":str(scenario.get("title","site-%d" % (index+1))),"config":g._default_fields(int(saved.chapter)),"inspected":false,"checks":[],"revision":0,"validated_revision":-1,"baseline_recorded":false,"baseline_locked":false,"baseline_config":"","baseline_sha":"","baseline_report":"","baseline_report_content":""})
		g.state.vm_states["%s/site-%d" % [id,index]] = saved.vm_state.duplicate(true)
	var context := {"id":id,"chapter":chapter,"contract":contract,"contract_plan":"standard","accepted":true,"inspected":false,"targets":targets,"target_index":0,"config":g._default_fields(chapter),"checks":[],"revision":0,"validated_revision":-1,"work":{"minutes":0.0,"started_at":int(g.state.clock_minutes),"started_day":int(g.state.day),"restarts_failed":0,"resets":0,"incident_cost":0,"plan":"standard"},"diagnostics_required":true,"completed":false}
	g.state.contract_contexts[id] = context
	incident.status = "working"; incident.contract_id = id
	if not g._activate_contract_context(id) or not g.save_game():
		g.state = before; g._machine = old_machine; g._machine_key = old_key
		return false
	g.changed.emit()
	return true

static func finish_ticket(g) -> bool:
	var contract: Dictionary = g.state.contract
	var client := str(contract.get("maintenance_client", "")); var id := str(contract.get("maintenance_incident_id", ""))
	var incident: Dictionary = g.state.care_incidents.get(client, {})
	if id.is_empty() or id != str(g.state.current_contract_id) or str(incident.get("contract_id", "")) != id or str(incident.get("status", "")) != "working" or id in g.state.completed_ids: return false
	var before: Dictionary = g.state.duplicate(true)
	var targets: Array = g._capture_maintenance_targets(client)
	if targets.is_empty(): return false
	var status: Dictionary = g.work_status(); var review: Dictionary = g.case_review()
	var cost := int(g.state.work.get("incident_cost", 0))
	var relation: Dictionary = g.state.customer_relations.get(client, {"satisfaction":70,"completed_count":0})
	var satisfaction := int(relation.get("satisfaction",70))
	var delta := 3 if str(status.quality) == "on_time" else (-3 if str(status.quality) == "late" else 0)
	relation.satisfaction = clampi(satisfaction+delta,0,100); relation.last_quality = str(status.quality); relation.last_day = int(g.state.day)
	g.state.customer_relations[client] = relation
	targets = g.MAINTENANCE_SCOPE.merge(g._maintenance_targets_for(client),targets)
	g.state.maintenance_targets[client] = targets
	g.state.completed_ids.append(id)
	g.state.cash -= cost; g.state.profit -= cost
	incident.status = "recheck"
	var renewal := "active" if bool(g.state.care_agreements.get(client,{}).get("active",false)) else "suspended"
	g.state.last_receipt = {"day":int(g.state.day),"client":client,"title":str(contract.title),"fee":0,"bonus":0,"baseline_bonus":0,"quality_score":int(review.get("score",0)),"grade":str(review.get("grade","C")),"baseline_sites":int(review.get("recorded_sites",0)),"baseline_total_sites":targets.size(),"cost":cost,"net":-cost,"minutes":status.minutes,"elapsed_minutes":status.elapsed_minutes,"budget":status.budget,"rating":status.quality,"credit_gain":0,"credit_before":g.state.credit,"credit_after":g.state.credit,"checks":g.state.checks.duplicate(true),"plan":"standard","level_before":int(g.company_level().level),"level_after":int(g.company_level().level),"xp_gain":0,"satisfaction_before":satisfaction,"satisfaction_after":int(relation.satisfaction),"renewal_outcome":renewal,"price_satisfaction_delta":0,"quality_satisfaction_delta":delta,"agreed_fee":0,"reference_fee":0,"maintenance_incident_id":id}
	g.state.history.append({"id":id,"case_id":str(contract.get("case_id","")),"copy_id":str(g.mission().id),"title":str(contract.title),"client":client,"brief":str(contract.brief),"day":int(g.state.day),"reward":0,"expense":cost,"profit":-cost,"retainer":0,"checks":g.state.checks.duplicate(true),"grade":str(review.get("grade","C")),"quality_score":int(review.get("score",0)),"baseline_bonus":0,"satisfaction_before":satisfaction,"satisfaction_after":int(relation.satisfaction),"renewal_outcome":renewal,"maintenance_incident_id":id})
	g.state.clients[id] = {"title":str(contract.title),"debrief":UI.copy("care_incident_debrief"),"config":g._vm().state.get("applied",{}).duplicate(true),"evidence":g.mission().evidence.duplicate(true),"checks":g.state.checks.duplicate(true)}
	g._sync_contract_context(); g.state.contract_contexts[id].completed = true
	var job: Dictionary = g._ensure_maintenance_job(client)
	job.status = "pending"; job.targets = targets.duplicate(true); job.remaining = 12.0; job.total = 12.0; job.minutes = 12.0; job.assignee = ""; job.phase = ""
	if not g.save_game(): g.state = before; return false
	g.changed.emit()
	return true
