extends RefCounted
## Recurring inspection currently executes retained basic-service VMs. The
## independent specialist engines must not promise that different service.
const UNSUPPORTED := ["advanced-hunt", "advanced-pentest", "advanced-pentest-relay", "advanced-recovery", "advanced-ddos", "advanced-api", "advanced-supplychain", "advanced-cloud", "advanced-saas-response", "advanced-saas-watch", "advanced-saas-sessions", "advanced-saas-ai-preflight", "advanced-saas-ai-handoff", "advanced-saas-priority", "advanced-malware", "advanced-detection", "advanced-portal"]
const REASON := "この専門案件は継続保守の対象外です。標準または特急の単発契約を選んでください。"

static func reason(offer: Dictionary) -> String:
	if str(offer.get("case_id", offer.get("id", ""))) in UNSUPPORTED: return REASON
	for target in offer.get("target_specs", []):
		if target is Dictionary and str(target.get("case_id", "")) in UNSUPPORTED: return REASON
	return ""

static func _other_pending_care(g, client: String, current_id: String) -> bool:
	for id in g.state.get("contract_contexts", {}):
		if str(id) == current_id: continue
		var context: Dictionary = g.state.contract_contexts[id]
		if not bool(context.get("completed", false)) and str(context.get("contract_plan", "")) == "care" and str(context.get("contract", {}).get("client", "")) == client: return true
	return false

static func conversion(g) -> Dictionary:
	var s: Dictionary = g.state
	var contract: Dictionary = s.get("contract", {})
	if not bool(s.get("accepted", false)) or str(s.get("contract_plan", "")) != "care" or reason(contract).is_empty() or g.current_done(): return {"available":false}
	var client := str(contract.get("client", ""))
	var id := str(s.get("current_contract_id", ""))
	var agreement: Dictionary = s.get("care_agreements", {}).get(client, {})
	var retained: bool = not s.get("maintenance_targets", {}).get(client, []).is_empty() or bool(agreement.get("active", false)) or _other_pending_care(g, client, id)
	var effective: Dictionary = g.work_status()
	return {"available":true,"reason":REASON,"contract_id":id,"client":client,"fee":int(contract.get("agreed_fee", effective.estimated_fee)),"budget":float(contract.get("agreed_budget", effective.budget)),"retained_care":retained,"cancel_pending":not retained and bool(agreement.get("pending", false))}

static func convert(g) -> bool:
	var proposal := conversion(g)
	if not bool(proposal.get("available", false)): return false
	var previous: Dictionary = g.state.duplicate(true)
	g._sync_contract_context()
	# Older saves derived these terms from their plan. Lock the old effective
	# terms before changing that plan, including explicit zero-valued terms.
	if not g.state.contract.has("agreed_fee"): g.state.contract.agreed_fee = int(proposal.fee)
	if not g.state.contract.has("agreed_budget"): g.state.contract.agreed_budget = float(proposal.budget)
	g.state.contract_plan = "standard"
	g.state.work.plan = "standard"
	g.state.contract.care_conversion = {"from":"care","to":"standard","day":int(g.state.day),"agreed_fee":proposal.fee,"agreed_budget":proposal.budget,"pending_care_cancelled":proposal.cancel_pending}
	if bool(proposal.cancel_pending):
		g.state.care_agreements.erase(str(proposal.client))
		g.state.recurring_clients.erase(str(proposal.client))
	g._sync_contract_context()
	if not g.save_game():
		g.state = previous
		return false
	g.changed.emit()
	return true
