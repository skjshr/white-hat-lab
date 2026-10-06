extends RefCounted
class_name CareerCloseout

## Transactional closeout for an accepted, ordinary career engagement.
const CASES = preload("res://scripts/case_catalog.gd")
const STOCK = preload("res://scripts/customer_stock.gd")
const CYCLE = preload("res://scripts/company_cycle.gd")
const DAY_START_MINUTE := 540

static func ensure(state: Dictionary) -> bool:
	if not state.has("contract_closeouts"):
		state.contract_closeouts = {}
		return true
	return validate(state.get("contract_closeouts"))

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	for raw_id in value:
		if not raw_id is String or str(raw_id).is_empty(): return false
		var archive: Variant = value[raw_id]
		if not archive is Dictionary or str(archive.get("id", "")) != str(raw_id): return false
		if str(archive.get("kind", "")) != "cancellation": return false
		if not archive.get("context", null) is Dictionary or not archive.get("vm_states", null) is Dictionary: return false
		if not archive.get("record", null) is Dictionary: return false
		var record: Dictionary = archive.record
		if str(record.get("id", "")) != str(raw_id) or str(record.get("kind", "")) != "cancellation": return false
		for key in ["day", "costs", "cash_cost", "cash_before", "cash_after", "fee_forgone", "expense", "profit", "cash_delta", "satisfaction_before", "satisfaction_after", "credit_before", "credit_after"]:
			var number: Variant = record.get(key, null)
			if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) or float(number) != floorf(float(number)): return false
		if int(record.day) < 1 or int(record.costs) < 0 or int(record.cash_cost) != int(record.costs) or int(record.expense) != int(record.costs) or int(record.fee_forgone) < 0: return false
		if int(record.profit) != -int(record.costs) or int(record.cash_delta) != -int(record.costs) or int(record.cash_after) != int(record.cash_before) - int(record.costs): return false
		if int(record.satisfaction_before) < 0 or int(record.satisfaction_before) > 100 or int(record.satisfaction_after) < 0 or int(record.satisfaction_after) > 100: return false
		if int(record.credit_before) < 0 or int(record.credit_after) != maxi(0, int(record.credit_before) - 3): return false
	return true

static func _result(reason: String = "") -> Dictionary:
	return {"available":reason.is_empty(),"reason":reason,"id":"","client":"","title":"","fee_forgone":0,"costs":0,"cash_cost":0,"cash_before":0,"cash_after":0,"satisfaction_before":0,"satisfaction_after":0,"credit_before":0,"credit_after":0,"late":false,"queued_jobs":[],"open_before":0,"open_after":0,"capacity":0}

static func _unsupported_reason(game) -> String:
	var state: Dictionary = game.state
	if not bool(state.get("career_mode", false)): return "受注済みのキャリア案件だけ中止できます。"
	if bool(state.get("game_complete", false)) or not bool(state.get("accepted", false)) or bool(state.get("awaiting_contract", false)): return "中止できる受注済み案件がありません。"
	var id := str(state.get("current_contract_id", ""))
	if id.is_empty() or game.current_done(): return "中止できる未完了案件がありません。"
	if state.get("contract_closeouts", {}).has(id): return "この案件はすでに中止されています。"
	if not state.get("contract_contexts", {}).has(id): return "案件の保存状態を確認できないため中止できません。"
	var context: Variant = state.contract_contexts[id]
	if not context is Dictionary or bool(context.get("completed", false)): return "案件の保存状態を確認できないため中止できません。"
	var contract: Dictionary = state.get("contract", {}) if state.get("contract", {}) is Dictionary else {}
	var plan := str(state.get("contract_plan", ""))
	if plan not in ["standard", "priority"]: return "保守付き案件は専用の保守契約手順で変更してください。"
	if contract.has("maintenance_incident_id"): return "保守中の事故案件は専用の保守対応手順で処理してください。"
	var case_id := str(contract.get("case_id", ""))
	var definition := CASES.by_id(case_id)
	if case_id.is_empty() or definition.is_empty(): return "通常案件として確認できないため中止できません。"
	if bool(definition.get("advanced_work_minutes", 0)) or case_id.begins_with("advanced-") or case_id.begins_with("composite-"):
		return "専門・複合案件はこの中止手順の対象外です。"
	var requirement: Variant = contract.get("supply_requirement", definition.get("supply_requirement", {}))
	if requirement is Dictionary and not requirement.is_empty(): return "設備・資材を伴う案件は専用の注文手順で処理してください。"
	for target_index in state.get("targets", []).size():
		if not STOCK.assigned(state, id, target_index).is_empty(): return "設備・資材が割り当てられた案件は専用の注文手順で処理してください。"
	return ""

static func preview(game) -> Dictionary:
	var result := _result(_unsupported_reason(game))
	if not bool(result.available): return result
	var state: Dictionary = game.state
	var id := str(state.current_contract_id)
	var contract: Dictionary = state.contract
	var relation: Dictionary = state.get("customer_relations", {}).get(str(contract.get("client", "")), {})
	var work: Dictionary = state.get("work", {}) if state.get("work", {}) is Dictionary else {}
	var budget := float(contract.get("agreed_budget", game._contract_budget(int(state.chapter), int(state.get("targets", []).size()), contract.get("target_specs", []), str(state.contract_plan)).budget))
	var elapsed := maxf(0.0, float((int(state.day) - int(work.get("started_day", state.day))) * 1440 + game.clock_minutes() - int(work.get("started_at", DAY_START_MINUTE))))
	var late := elapsed > budget
	var costs := 700 + maxi(0, int(work.get("incident_cost", 0)))
	var satisfaction_before := clampi(int(relation.get("satisfaction", 70)), 0, 100)
	var credit_before := maxi(0, int(state.get("credit", state.get("trust", 0))))
	var cash_before := int(state.get("cash", 0))
	var open_before: int = int(game._open_contract_count())
	result.merge({"id":id,"client":str(contract.get("client", "")),"title":str(contract.get("title", "")),"fee_forgone":maxi(0, int(contract.get("agreed_fee", contract.get("reward", 0)))),"costs":costs,"cash_cost":costs,"cash_before":cash_before,"cash_after":cash_before-costs,"satisfaction_before":satisfaction_before,"satisfaction_after":maxi(0, satisfaction_before - (18 if late else 12)),"credit_before":credit_before,"credit_after":maxi(0, credit_before - 3),"late":late,"queued_jobs":_matching_jobs(state, id),"open_before":open_before,"open_after":maxi(0,open_before-1),"capacity":game.contract_capacity()}, true)
	return result

static func _matching_jobs(state: Dictionary, contract_id: String) -> Array:
	var matches: Array = []
	for member_id in state.get("assignments", {}):
		var job: Variant = state.assignments[member_id]
		if job is Dictionary and str(job.get("kind", "normal")) == "normal" and str(job.get("contract_id", "")) == contract_id:
			matches.append({"member_id":str(member_id),"status":str(job.get("status", "")),"id":str(job.get("id", ""))})
	for member_id in state.get("dispatch_queues", {}):
		for job in state.dispatch_queues[member_id]:
			if job is Dictionary and str(job.get("kind", "normal")) == "normal" and str(job.get("contract_id", "")) == contract_id:
				matches.append({"member_id":str(member_id),"status":str(job.get("status", "")),"id":str(job.get("id", ""))})
	return matches

static func _archive_vm_states(state: Dictionary, id: String) -> Dictionary:
	var archive := {}
	var prefix := id + "/site-"
	for raw_key in state.get("vm_states", {}):
		var key := str(raw_key)
		if key.begins_with(prefix): archive[key] = state.vm_states[raw_key].duplicate(true)
	return archive

static func cancel(game) -> bool:
	var view := preview(game)
	if not bool(view.available): return false
	var state: Dictionary = game.state
	var id := str(view.id)
	var prior_state := state.duplicate(true)
	var prior_assignments: Dictionary = game._assignments.duplicate(true)
	var prior_machine = game._machine
	var prior_machine_key := str(game._machine_key)
	# Capture the live VM and projection before the archive is detached from the
	# active context. Neither operation repairs or resets customer data.
	if game._machine != null and str(game._machine_key).begins_with(id + "/site-"):
		state.vm_states[str(game._machine_key)] = game._machine.export_state()
	game._sync_target()
	game._sync_contract_context()
	var saved_context: Dictionary = state.contract_contexts[id].duplicate(true)
	var archive_vm := _archive_vm_states(state, id)
	var day := int(state.day)
	var client := str(view.client)
	var costs := int(view.costs)
	var satisfaction_before := int(view.satisfaction_before)
	var satisfaction_after := int(view.satisfaction_after)
	var credit_before := int(view.credit_before)
	var credit_after := int(view.credit_after)
	var lost_credit := credit_before - credit_after
	var record := {"kind":"cancellation","id":id,"case_id":str(state.contract.get("case_id", "")),"title":str(view.title),"client":client,"day":day,"plan":str(state.contract_plan),"fee_forgone":int(view.fee_forgone),"costs":costs,"cash_cost":costs,"cash_before":int(view.cash_before),"cash_after":int(view.cash_after),"expense":costs,"material_cost":0,"profit":-costs,"cash_delta":-costs,"late":bool(view.late),"satisfaction_before":satisfaction_before,"satisfaction_after":satisfaction_after,"credit_before":credit_before,"credit_after":credit_after,"rating":"cancelled","archived_context":id}
	var endpoint_impact: Dictionary = saved_context.get("work", {}).get("endpoint_impact", {})
	if not endpoint_impact.is_empty(): record.endpoint_impact = endpoint_impact.duplicate(true)
	state.contract_closeouts[id] = {"kind":"cancellation","id":id,"day":day,"context":saved_context,"vm_states":archive_vm,"record":record.duplicate(true)}
	state.cash = int(state.get("cash", 0)) - costs
	state.profit = int(state.get("profit", 0)) - costs
	state.credit = credit_after
	state.trust = credit_after
	state.credit_loss = int(state.get("credit_loss", 0)) + lost_credit
	var relation: Dictionary = state.customer_relations.get(client, {"satisfaction":70,"completed_count":0,"last_quality":"","last_day":0})
	relation.satisfaction = satisfaction_after
	relation.last_quality = "cancelled"
	relation.last_day = day
	relation.cancellation_count = int(relation.get("cancellation_count", 0)) + 1
	state.customer_relations[client] = relation
	state.history.append(record.duplicate(true))
	while state.history.size() > 100: state.history.pop_front()
	state.last_receipt = record.duplicate(true)
	state.contract_contexts.erase(id)
	state.offer_quotes.erase(id)
	var case_id := str(record.case_id)
	state.market_leads = state.get("market_leads", []).filter(func(raw_id): return str(raw_id) != case_id)
	for offer in state.get("offers", []):
		if offer is Dictionary and str(offer.get("id", "")) == id: offer.market_available = false
	for member_id in game._assignments.keys().duplicate():
		var job: Dictionary = game._assignments[member_id]
		if str(job.get("kind", "normal")) == "normal" and str(job.get("contract_id", "")) == id:
			game._assignments.erase(member_id)
	for member_id in state.get("dispatch_queues", {}).keys().duplicate():
		var kept: Array = []
		for job in state.dispatch_queues[member_id]:
			if not (job is Dictionary and str(job.get("kind", "normal")) == "normal" and str(job.get("contract_id", "")) == id): kept.append(job)
		state.dispatch_queues[member_id] = kept
	state.assignments = game._assignments.duplicate(true)
	state.awaiting_contract = true
	state.accepted = false
	state.inspected = false
	state.current_contract_id = ""
	state.contract = {}
	state.targets = []
	state.target_index = 0
	state.config = game._default_fields(int(state.chapter))
	state.advanced = {}
	state.checks = []
	state.validated_revision = -1
	state.revision = int(state.get("revision", 0)) + 1
	state.work = {"minutes":0.0,"started_at":int(state.get("clock_minutes", DAY_START_MINUTE)),"started_day":day,"restarts_failed":0,"resets":0,"incident_cost":0,"plan":str(state.get("offer_plan", "standard"))}
	state.diagnostics_required = false
	state.restore_preview = 0
	state.baseline_recorded = false
	state.baseline_locked = false
	state.baseline_config = ""
	state.baseline_sha = ""
	state.baseline_report = ""
	state.baseline_report_content = ""
	# Detach the just-closed customer machine before saving the empty workbench.
	# The exact instance/key are held above and restored if persistence fails.
	game._machine = null
	game._machine_key = ""
	if not _persist_cancellation_signal(state, record):
		game.state = prior_state; game._assignments = prior_assignments; game._machine = prior_machine; game._machine_key = prior_machine_key
		return false
	if not game.save_game(false):
		game.state = prior_state; game._assignments = prior_assignments; game._machine = prior_machine; game._machine_key = prior_machine_key
		return false
	game.changed.emit()
	return true

static func _persist_cancellation_signal(state: Dictionary, record: Dictionary) -> bool:
	return CYCLE.record_cancellation(state, str(record.id), record)
