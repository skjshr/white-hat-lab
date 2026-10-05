extends RefCounted
## Capture a completed customer's actual file at acceptance, never on render/load.
const CASE_ID := "branch-order-continuity"
const SOURCE_CASE := "composite-branch-reopen"
const CLIENT := "北斗物流・新支店"
const SOURCE_PATH := "/srv/share/partner-order.csv"
const DESTINATION := "/srv/data/partner-order.csv"

static func source(state: Dictionary) -> Dictionary:
	var result := {}
	# Completed dispatch contexts are cleared at day settlement. Delivery
	# history and the retained VM are the durable sources across that boundary.
	for raw in state.get("history", []):
		if not raw is Dictionary: continue
		var receipt: Dictionary = raw
		var id := str(receipt.get("id", ""))
		if not str(receipt.get("kind", "")).is_empty() or str(receipt.get("case_id", "")) != SOURCE_CASE or str(receipt.get("client", "")) != CLIENT: continue
		if id.is_empty() or id not in state.get("completed_ids", []): continue
		if str(receipt.get("rating", "")) not in ["on_time", "late", "rework"] or not receipt.has("satisfaction_after"): continue
		var machine: Dictionary = state.get("vm_states", {}).get(str(id) + "/site-1", {})
		var files: Dictionary = machine.get("fs", {})
		if not files.get(SOURCE_PATH) is String or str(files[SOURCE_PATH]).is_empty(): continue
		if not result.is_empty() and int(receipt.get("day", 0)) < int(result.day): continue
		result = {"contract_id":str(id),"case_id":SOURCE_CASE,"path":SOURCE_PATH,"content":str(files[SOURCE_PATH]),"sha256":str(files[SOURCE_PATH]).sha256_text(),"day":int(receipt.get("day", 0)),"rating":str(receipt.rating),"satisfaction":int(receipt.satisfaction_after)}
	return result

static func available(state: Dictionary) -> bool:
	var prior := source(state)
	if prior.is_empty(): return false
	var lead: Dictionary = state.get("company_cycle", {}).get("leads", {}).get(CLIENT, {})
	if str(lead.get("case_id", "")) == CASE_ID:
		return str(lead.get("status", "")) in ["pending", "fulfilled"]
	# Old completed saves may enter tomorrow's ordinary market. This does not
	# fabricate an earlier consultation, quality result or saved event.
	return str(prior.rating) == "on_time" and int(prior.satisfaction) >= 40

static func scenario(state: Dictionary, definition: Dictionary) -> Dictionary:
	if not available(state): return {}
	var prior := source(state)
	var result := definition.duplicate(true)
	result.fs_overrides = {DESTINATION:prior.content}
	result.backup_expected_records = {"partner-order.csv":prior.content}
	result.handoff = {"version":1,"source_contract_id":prior.contract_id,"source_case_id":prior.case_id,"source_path":prior.path,"destination_path":DESTINATION,"sha256":prior.sha256,"day":prior.day}
	result.probes = [
		{"id":"branch-offsite","label":"別拠点に退避した受注表","command":"restic -r offsite dump latest " + DESTINATION,"expectation":str(prior.content)},
		{"id":"branch-restored","label":"復元した受注表の照合","command":"sha256sum /restore/srv/data/partner-order.csv","expectation":str(prior.sha256)}
	]
	for probe in result.probes:
		probe.merge({"recorded":false,"passed":false,"fresh":false,"result":"","description":"前回の納品時に扱った受注表を、別拠点への退避と復元の両方で確認する。"})
	return result
