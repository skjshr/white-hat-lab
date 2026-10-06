extends RefCounted
## Market provenance for successive North Star Logistics priority-response cases.
## This helper only projects saved delivery records; it never changes Game state.

const CASE_ID := "advanced-saas-priority"
const MODEL := "saas-priority-v1"
const HANDOFF_CASE_ID := "advanced-saas-ai-handoff"
const HANDOFF_MODEL := "saas-ai-handoff-v1"
const CLIENT := "北斗物流"
const TITLE := "緊急対応: 二つの業務の復旧順序"
const BRIEF := "前回の委託先業務を受け継ぎ、返金照合と配送連絡の受付を復旧します。承認原本、宛先、業務ごとの締切と損失を確認してください。"

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

static func _whole(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT) or (typeof(value) == TYPE_FLOAT and is_finite(float(value)) and floorf(float(value)) == float(value))

static func _latest_record(records: Array, action: String, predicate: Callable = Callable()) -> Dictionary:
	var selected: Dictionary = {}
	for raw in records:
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("action", "")) != action or int(row.get("status", 0)) != 200: continue
		if predicate.is_valid() and not predicate.call(row): continue
		if selected.is_empty() or int(row.get("seq", -1)) > int(selected.get("seq", -1)): selected = row
	return selected

static func _flat_original(row: Dictionary) -> Dictionary:
	var copy := row.duplicate(false)
	copy.erase("records")
	copy.erase("events")
	for key in copy.keys():
		if key == "data": continue
		var value: Variant = copy[key]
		if value is Dictionary or value is Array: copy[key] = value.duplicate(true)
	var data_value: Variant = row.get("data", {})
	if data_value is Dictionary:
		var data: Dictionary = data_value.duplicate(false)
		data.erase("records")
		data.erase("events")
		copy["data"] = data.duplicate(true)
	else:
		copy.erase("data")
	return copy

static func _outcome_source(outcome: Dictionary) -> Dictionary:
	var model := str(outcome.get("model_version", ""))
	if model == HANDOFF_MODEL:
		var handoff_value: Variant = outcome.get("handoff", {})
		return {"model":model,"source":outcome.get("source_contract_id", ""),"round":0,"area":handoff_value}
	if model == MODEL:
		var priority_value: Variant = outcome.get("priority", {})
		if not priority_value is Dictionary: return {}
		var priority: Dictionary = priority_value
		return {"model":model,"source":priority.get("source", {}),"round":priority.get("round", 0),"area":priority}
	return {}

static func _area(outcome: Dictionary, source_info: Dictionary) -> Dictionary:
	var value: Variant = source_info.get("area", {})
	if not value is Dictionary: return {}
	var model := str(source_info.get("model", ""))
	if model == HANDOFF_MODEL:
		var business: Variant = value.get("business", {})
		return {"business":business if business is Dictionary else {},"source":value.get("source", {}) if value.get("source", {}) is Dictionary else {}}
	return value

static func _queue_key(row: Dictionary) -> String:
	var data_value: Variant = row.get("data", {})
	if data_value is Dictionary:
		var queue := str(data_value.get("queue_id", ""))
		if queue in ["claims", "dispatch"]: return queue
	return ""

static func _successful_runs(records: Array, model: String) -> Array:
	var best := {"claims":{},"dispatch":{},"single":{}}
	for raw in records:
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("action", "")) != "run_business" or int(row.get("status", 0)) != 200: continue
		var data_value: Variant = row.get("data", {})
		if not data_value is Dictionary or str(data_value.get("receipt_id", "")).is_empty(): continue
		var queue := _queue_key(row)
		if model == MODEL:
			if queue not in ["claims", "dispatch"]: continue
			if best[queue].is_empty() or int(row.get("seq", -1)) > int(best[queue].get("seq", -1)): best[queue] = row
		else:
			if best.single.is_empty() or int(row.get("seq", -1)) > int(best.single.get("seq", -1)): best.single = row
	var result: Array = []
	if model == MODEL:
		if best.claims.is_empty() or best.dispatch.is_empty(): return []
		result.append(best.claims)
		result.append(best.dispatch)
	else:
		if best.single.is_empty(): return []
		result.append(best.single)
	return result

static func _originals(outcome: Dictionary, source_info: Dictionary) -> Array:
	var raw_records: Variant = outcome.get("records", [])
	if not raw_records is Array: return []
	var records: Array = raw_records
	var approvals: Array = []
	for raw in records:
		if raw is Dictionary and str(raw.get("action", "")) == "consent_review" and int(raw.get("status", 0)) == 200:
			approvals.append(raw)
	if approvals.is_empty(): return []
	var runs := _successful_runs(records, str(source_info.get("model", "")))
	if runs.is_empty(): return []
	var report := _latest_record(records, "submit_report")
	var report_value: Variant = outcome.get("report", {})
	if report.is_empty() or not report_value is Dictionary or not bool(report_value.get("submitted", false)): return []
	var selected: Array = []
	for raw in approvals: selected.append(_flat_original(raw))
	for raw in runs: selected.append(_flat_original(raw))
	selected.append(_flat_original(report))
	var ids: Dictionary = {}
	for row in selected:
		var id := str(row.get("id", ""))
		if id.is_empty() or ids.has(id): return []
		ids[id] = true
	return selected

static func _business_loss(outcome: Dictionary, info: Dictionary) -> int:
	var area := _area(outcome, info)
	var explicit := maxi(0, int(area.get("loss_cost", area.get("business_loss_cost", 0))))
	if explicit > 0: return explicit
	var queues_value: Variant = area.get("queues", [])
	var total := 0
	if queues_value is Array:
		for queue_entry in queues_value:
			if queue_entry is Dictionary: total += maxi(0, int(queue_entry.get("loss_cost", 0)))
	elif queues_value is Dictionary:
		for queue_value in queues_value.values():
			if queue_value is Dictionary: total += maxi(0, int(queue_value.get("loss_cost", 0)))
	return total

static func _queue_receipts(area: Dictionary) -> Dictionary:
	var receipts: Dictionary = {}
	var queues_value: Variant = area.get("queues", [])
	if queues_value is Array:
		for queue in queues_value:
			if not queue is Dictionary: continue
			var key := str(queue.get("id", queue.get("queue_id", "")))
			var receipt_text := str(queue.get("receipt_id", ""))
			if not key.is_empty() and not receipt_text.is_empty(): receipts[key] = receipt_text
	elif queues_value is Dictionary:
		for raw_key in queues_value.keys():
			var queue_value: Variant = queues_value[raw_key]
			if not queue_value is Dictionary: continue
			var receipt := str(queue_value.get("receipt_id", ""))
			if not receipt.is_empty(): receipts[str(raw_key)] = receipt
	return receipts

static func _make_payload(row: Dictionary) -> Dictionary:
	var outcome_value: Variant = row.get("saas_outcome", {})
	if not outcome_value is Dictionary: return {}
	var outcome: Dictionary = outcome_value
	var info := _outcome_source(outcome)
	if info.is_empty(): return {}
	var model := str(info.get("model", ""))
	var records := _originals(outcome, info)
	if records.is_empty(): return {}
	var round := 1
	if model == MODEL:
		if not _whole(info.get("round", null)) or int(info.round) < 1: return {}
		round = int(info.round) + 1
	var egress_value: Variant = outcome.get("egress", {})
	var exported: Variant = egress_value.get("exported_rows", []) if egress_value is Dictionary else []
	var source_id := str(row.get("id", ""))
	var source_day := int(row.get("day", 0))
	if source_id.is_empty() or source_day < 1: return {}
	var area := _area(outcome, info)
	var business_value: Variant = area.get("business", {})
	var business: Dictionary = business_value if business_value is Dictionary else area
	var receipts := _queue_receipts(area)
	var receipt_id := str(business.get("receipt_id", ""))
	if receipt_id.is_empty() and not receipts.is_empty():
		var receipt_keys: Array = receipts.keys(); receipt_keys.sort()
		var joined := ""
		for receipt_key in receipt_keys:
			if not joined.is_empty(): joined += ","
			joined += str(receipt_key) + "=" + str(receipts[receipt_key])
		receipt_id = joined
	var prior := {"source_model":model,"source_round":int(info.get("round", 0)),"exported_rows":exported.size() if exported is Array else 0,"loss_cost":_business_loss(outcome, info),"receipt_id":receipt_id,"receipts":receipts,"grade":str(row.get("grade", "")),"satisfaction_after":int(row.get("satisfaction_after", -1))}
	return {"source_contract_id":source_id,"source_day":source_day,"client":CLIENT,"round":round,"approved_originals":records,"prior_result":prior}

static func _all_passed(row: Dictionary) -> bool:
	var checks_value: Variant = row.get("checks", [])
	if not checks_value is Array or checks_value.is_empty(): return false
	for check in checks_value:
		if not check is Dictionary or not bool(check.get("passed", false)): return false
	return true

static func _already_used(state: Dictionary, source_id: String) -> bool:
	for raw in state.get("history", []):
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("case_id", "")) != CASE_ID or str(row.get("id", "")) not in state.get("completed_ids", []): continue
		var outcome: Variant = row.get("saas_outcome", {})
		if outcome is Dictionary:
			var priority: Variant = outcome.get("priority", {})
			if priority is Dictionary:
				var source_value: Variant = priority.get("source", {})
				if source_value is Dictionary and str(source_value.get("source_contract_id", "")) == source_id: return true
	for context_value in state.get("contract_contexts", {}).values():
		if not context_value is Dictionary or not bool(context_value.get("completed", false)): continue
		var contract: Variant = context_value.get("contract", {})
		if contract is Dictionary:
			var payload_value: Variant = contract.get("saas_priority_payload", {})
			if payload_value is Dictionary and str(payload_value.get("source_contract_id", "")) == source_id: return true
	return false

static func _working(state: Dictionary, source_id: String) -> bool:
	for context_value in state.get("contract_contexts", {}).values():
		if not context_value is Dictionary or bool(context_value.get("completed", false)): continue
		var contract: Variant = context_value.get("contract", {})
		if contract is Dictionary:
			var payload_value: Variant = contract.get("saas_priority_payload", {})
			if payload_value is Dictionary and str(payload_value.get("source_contract_id", "")) == source_id: return true
	return false

static func _source_id_from_record(record: Dictionary) -> String:
	var payload_value: Variant = record.get("saas_priority_payload", {})
	if payload_value is Dictionary and not str(payload_value.get("source_contract_id", "")).is_empty(): return str(payload_value.get("source_contract_id", ""))
	var contract_value: Variant = record.get("contract", {})
	if contract_value is Dictionary:
		payload_value = contract_value.get("saas_priority_payload", {})
		if payload_value is Dictionary and not str(payload_value.get("source_contract_id", "")).is_empty(): return str(payload_value.get("source_contract_id", ""))
	var outcome_value: Variant = record.get("saas_outcome", {})
	if outcome_value is Dictionary:
		var priority_value: Variant = outcome_value.get("priority", {})
		if priority_value is Dictionary:
			var source_value: Variant = priority_value.get("source", {})
			if source_value is Dictionary: return str(source_value.get("source_contract_id", ""))
	return ""

static func _closed_today(state: Dictionary, source_id: String, day: int) -> bool:
	for archive_value in state.get("contract_closeouts", {}).values():
		if not archive_value is Dictionary or int(archive_value.get("day", -1)) != day: continue
		var record_value: Variant = archive_value.get("record", {})
		if record_value is Dictionary and _source_id_from_record(record_value) == source_id: return true
		var context_value: Variant = archive_value.get("context", {})
		if context_value is Dictionary:
			var contract_value: Variant = context_value.get("contract", {})
			if contract_value is Dictionary and str(contract_value.get("case_id", "")) == CASE_ID:
				var payload_value: Variant = contract_value.get("saas_priority_payload", {})
				if payload_value is Dictionary and str(payload_value.get("source_contract_id", "")) == source_id: return true
	return false

static func _closed_payloads(state: Dictionary, day: int) -> Array:
	var result: Array = []
	for archive_value in state.get("contract_closeouts", {}).values():
		if not archive_value is Dictionary or int(archive_value.get("day", -1)) >= day: continue
		var context_value: Variant = archive_value.get("context", {})
		if not context_value is Dictionary: continue
		var contract_value: Variant = context_value.get("contract", {})
		if not contract_value is Dictionary or str(contract_value.get("case_id", "")) != CASE_ID: continue
		var payload_value: Variant = contract_value.get("saas_priority_payload", {})
		if not _valid_payload(payload_value): continue
		var source_id := str(payload_value.get("source_contract_id", ""))
		if source_id.is_empty() or _already_used(state, source_id) or _working(state, source_id) or _closed_today(state, source_id, day): continue
		result.append(payload_value.duplicate(true))
	return result

static func _source_rows(state: Dictionary, day: int) -> Array:
	var history: Array = state.get("history", []).duplicate(true)
	history.reverse()
	var eligible: Array = []
	for raw in history:
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("case_id", "")) not in [HANDOFF_CASE_ID, CASE_ID] or str(row.get("client", "")) != CLIENT or not str(row.get("kind", "")).is_empty(): continue
		var source_id := str(row.get("id", "")); var source_day := int(row.get("day", 0))
		if source_id.is_empty() or source_id not in state.get("completed_ids", []) or source_day < 1 or source_day >= day: continue
		if str(row.get("grade", "")) not in ["S", "A"] or not _all_passed(row): continue
		if _already_used(state, source_id) or _working(state, source_id) or _closed_today(state, source_id, day): continue
		var payload_value := _make_payload(row)
		if not payload_value.is_empty(): eligible.append({"row":row,"payload":payload_value})
	return eligible

static func payload(state: Dictionary, day: int) -> Dictionary:
	var eligible := _source_rows(state, day)
	if not eligible.is_empty(): return eligible[0].payload.duplicate(true)
	var closed := _closed_payloads(state, day)
	return closed[0].duplicate(true) if not closed.is_empty() else {}

static func _valid_payload(value: Variant) -> bool:
	if not value is Dictionary: return false
	var payload_value: Dictionary = value
	if str(payload_value.get("source_contract_id", "")).is_empty() or not _whole(payload_value.get("source_day", null)) or int(payload_value.source_day) < 1 or str(payload_value.get("client", "")) != CLIENT: return false
	if not _whole(payload_value.get("round", null)) or int(payload_value.round) < 1 or not payload_value.get("prior_result", null) is Dictionary: return false
	var originals: Variant = payload_value.get("approved_originals", null)
	if not originals is Array or originals.is_empty() or originals.size() > 32: return false
	var ids: Dictionary = {}; var consent_count := 0; var report_count := 0; var run_queues: Dictionary = {}; var source_model := str(payload_value.prior_result.get("source_model", ""))
	if source_model not in [HANDOFF_MODEL, MODEL]: return false
	for raw in originals:
		if not raw is Dictionary: return false
		var record: Dictionary = raw
		var id := str(record.get("id", "")); var action := str(record.get("action", ""))
		if id.is_empty() or ids.has(id) or int(record.get("status", 0)) != 200 or not record.get("data", null) is Dictionary: return false
		ids[id] = true
		match action:
			"consent_review": consent_count += 1
			"run_business":
				var queue := _queue_key(record)
				if source_model == MODEL and queue not in ["claims", "dispatch"]: return false
				var data: Dictionary = record.data
				if str(data.get("receipt_id", "")).is_empty(): return false
				run_queues[queue if not queue.is_empty() else "single"] = true
			"submit_report": report_count += 1
			_: return false
	return consent_count > 0 and report_count == 1 and (run_queues.size() == 1 if source_model == HANDOFF_MODEL else run_queues.has("claims") and run_queues.has("dispatch"))

static func matches_available(state: Dictionary, value: Variant, day: int) -> bool:
	if not _valid_payload(value): return false
	var current := payload(state, day)
	return not current.is_empty() and _canonical(current) == _canonical(value)

static func _latest_source_payload(state: Dictionary) -> Dictionary:
	var history: Array = state.get("history", []).duplicate(true)
	history.reverse()
	for raw in history:
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("case_id", "")) not in [HANDOFF_CASE_ID, CASE_ID] or str(row.get("client", "")) != CLIENT or not str(row.get("kind", "")).is_empty(): continue
		if str(row.get("id", "")) not in state.get("completed_ids", []) or str(row.get("grade", "")) not in ["S", "A"] or not _all_passed(row): continue
		var outcome_value: Variant = row.get("saas_outcome", {})
		if not outcome_value is Dictionary: continue
		var source_id := str(row.get("id", "")); var source_day := int(row.get("day", 0))
		if source_id.is_empty() or source_day < 1: continue
		var payload_value := _make_payload(row)
		if not payload_value.is_empty(): return payload_value
	var latest_payload: Dictionary = {}; var latest_day := -1
	for archive_value in state.get("contract_closeouts", {}).values():
		if not archive_value is Dictionary: continue
		var context_value: Variant = archive_value.get("context", {})
		if context_value is Dictionary:
			var contract_value: Variant = context_value.get("contract", {})
			if contract_value is Dictionary and str(contract_value.get("case_id", "")) == CASE_ID:
				var context_payload: Variant = contract_value.get("saas_priority_payload", {})
				if _valid_payload(context_payload) and int(archive_value.get("day", -1)) > latest_day:
					latest_day = int(archive_value.get("day", -1)); latest_payload = context_payload.duplicate(true)
		var record_value: Variant = archive_value.get("record", {})
		if not record_value is Dictionary or str(record_value.get("case_id", "")) != CASE_ID: continue
		var archive_outcome: Variant = record_value.get("saas_outcome", {})
		if not archive_outcome is Dictionary: continue
		var priority_value: Variant = archive_outcome.get("priority", {})
		if not priority_value is Dictionary: continue
		var archived_payload: Variant = priority_value.get("source", {})
		if _valid_payload(archived_payload) and int(archive_value.get("day", -1)) > latest_day:
			latest_day = int(archive_value.get("day", -1)); latest_payload = archived_payload.duplicate(true)
	if not latest_payload.is_empty(): return latest_payload
	return {}

static func _fulfilled(state: Dictionary, source_id: String) -> bool:
	for raw in state.get("history", []):
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("case_id", "")) != CASE_ID or str(row.get("id", "")) not in state.get("completed_ids", []): continue
		var outcome_value: Variant = row.get("saas_outcome", {})
		if outcome_value is Dictionary:
			var priority_value: Variant = outcome_value.get("priority", {})
			if priority_value is Dictionary:
				var source_value: Variant = priority_value.get("source", {})
				if source_value is Dictionary and str(source_value.get("source_contract_id", "")) == source_id: return true
	return false

static func _source_receipt(state: Dictionary, source_id: String) -> Dictionary:
	for raw in state.get("history", []):
		if raw is Dictionary and str(raw.get("id", "")) == source_id: return raw
	return {}

static func brief(source: Dictionary) -> String:
	var round := maxi(1, int(source.get("round", 1)))
	var claims_fast := round % 2 == 1
	var claims_path := "minato/claims" if claims_fast else "minato/archive"
	var claims_deadline := 6 if claims_fast else 14
	var claims_loss := 4500 if claims_fast else 900
	var dispatch_deadline := 14 if claims_fast else 6
	var dispatch_loss := 900 if claims_fast else 4500
	return BRIEF + " 第%d回。返金受付の締めは%d分、遅延補償¥%d、宛先 %s。出発便の連絡期限は%d分、遅延補償¥%d、宛先 minato/dispatch。" % [round,claims_deadline,claims_loss,claims_path,dispatch_deadline,dispatch_loss]

static func lead(game) -> Dictionary:
	var state: Dictionary = game.state
	var source := payload(state, int(state.day) + 1)
	var fulfilled := false
	var closed := false
	if source.is_empty():
		source = _latest_source_payload(state)
		var source_id := str(source.get("source_contract_id", ""))
		fulfilled = not source_id.is_empty() and _fulfilled(state, source_id)
		closed = not source_id.is_empty() and _closed_today(state, source_id, int(state.day))
	if source.is_empty(): return {}
	var offer: Dictionary = {}
	for candidate in state.get("offers", []):
		if candidate is Dictionary and _canonical(candidate.get("saas_priority_payload", {})) == _canonical(source): offer = candidate; break
	var offer_id := str(offer.get("id", ""))
	var working := _working(state, str(source.get("source_contract_id", "")))
	var available: bool = bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)) and not state.get("contract_closeouts", {}).has(offer_id)
	var reasons: Array = []
	if int(game.company_level().get("level", 1)) < 8: reasons.append("会社Lv.8が必要")
	if int(state.get("skills", {}).get("response", 0)) < 1: reasons.append("調査復旧Lv.1が必要")
	var status := "fulfilled" if fulfilled else "working" if working else "paused" if closed else "ready" if available else "locked"
	var reason_text := " / ".join(reasons)
	if reason_text.is_empty() and status == "locked": reason_text = "次の営業日の相談枠で確認できます。"
	if status == "working": reason_text = "受注済み案件から対応を続けてください。"
	var source_receipt := _source_receipt(state, str(source.get("source_contract_id", "")))
	var prior: Dictionary = source.get("prior_result", {}).duplicate(true)
	return {"id":"saas-priority:" + str(source.get("source_contract_id", "")),"client":CLIENT,"case_id":CASE_ID,"title":TITLE,"route_detail":"SaaS Priority・業務順序","work_family":"saas-priority","source_contract_id":str(source.get("source_contract_id", "")),"source_case_id":str(source_receipt.get("case_id", "")),"source_day":int(source.get("source_day", 0)),"source_rating":str(source_receipt.get("rating", "unknown")) if not source_receipt.is_empty() else "unknown","source_grade":str(source_receipt.get("grade", "unknown")) if not source_receipt.is_empty() else "unknown","source_satisfaction":int(source_receipt.get("satisfaction_after", -1)) if not source_receipt.is_empty() else -1,"source_result_unknown":source_receipt.is_empty(),"last_outcome":{"rating":str(source_receipt.get("rating", "unknown")) if not source_receipt.is_empty() else "unknown","grade":str(source_receipt.get("grade", "unknown")) if not source_receipt.is_empty() else "unknown","satisfaction":int(source_receipt.get("satisfaction_after", -1)) if not source_receipt.is_empty() else -1,"day":int(source_receipt.get("day", source.get("source_day", 0))) if not source_receipt.is_empty() else int(source.get("source_day", 0))},"reason":brief(source),"status":status,"required_level":8,"required_skills":{"response":1},"required_skill":{"response":1},"created_day":int(source.get("source_day", 0))+1,"offer_id":offer_id,"market_available":available,"reasons":reasons,"locked_reason":reason_text,"prior_result":prior}
