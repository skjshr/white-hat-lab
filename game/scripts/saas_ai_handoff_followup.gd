extends RefCounted
## A one-time follow-up grounded in the delivered AI preflight records.

const CASE_ID := "advanced-saas-ai-handoff"
const MODEL := "saas-ai-handoff-v1"
const SOURCE_CASE_ID := "advanced-saas-ai-preflight"
const SOURCE_MODEL := "saas-ai-preflight-v1"
const CLIENT := "北斗物流"
const TITLE := "緊急対応: 配送障害の委託先連絡"
const BRIEF := "AI-401で当該3便の連絡先と配送進捗をミナト配送の /dispatch へ12分以内に送ります。全名簿6件と /archive は承認範囲外です。同じ委託先でもフォルダーごとの承認を確認してください。"

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

static func _latest_record(records: Array, action: String, predicate: Callable = Callable()) -> Dictionary:
	var selected: Dictionary = {}
	for raw in records:
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("action", "")) != action or int(row.get("status", 0)) != 200: continue
		if predicate.is_valid() and not predicate.call(row): continue
		if selected.is_empty() or int(row.get("seq", -1)) > int(selected.get("seq", -1)): selected = row
	return selected

static func _record_set(outcome: Dictionary) -> Array:
	var raw: Variant = outcome.get("records", [])
	return raw if raw is Array else []

static func _handoff_source(outcome: Dictionary) -> Dictionary:
	var handoff: Variant = outcome.get("handoff", {})
	if handoff is Dictionary and handoff.get("source", {}) is Dictionary:
		return handoff.get("source", {}).duplicate(true)
	return {}

static func _already_used(state: Dictionary, source_id: String) -> bool:
	for row in state.get("history", []):
		if not row is Dictionary or not str(row.get("kind", "")).is_empty(): continue
		if str(row.get("id", "")) not in state.get("completed_ids", []): continue
		if str(_handoff_source(row.get("saas_outcome", {})).get("source_contract_id", "")) == source_id: return true
	for context in state.get("contract_contexts", {}).values():
		if not context is Dictionary: continue
		var contract: Variant = context.get("contract", {})
		if context.get("completed", false) and contract is Dictionary and str(contract.get("saas_ai_handoff_payload", {}).get("source_contract_id", "")) == source_id: return true
	return false

static func _working(state: Dictionary, source_id: String) -> bool:
	for context in state.get("contract_contexts", {}).values():
		if not context is Dictionary or bool(context.get("completed", false)): continue
		var contract: Variant = context.get("contract", {})
		if contract is Dictionary and str(contract.get("saas_ai_handoff_payload", {}).get("source_contract_id", "")) == source_id: return true
	return false

static func _closed_today(state: Dictionary, source_id: String, day: int) -> bool:
	for archive in state.get("contract_closeouts", {}).values():
		if not archive is Dictionary or int(archive.get("day", -1)) != day: continue
		var record: Variant = archive.get("record", {})
		if record is Dictionary and str(_handoff_source(record.get("saas_outcome", {})).get("source_contract_id", "")) == source_id: return true
	return false

static func _make_payload(row: Dictionary) -> Dictionary:
	var outcome_value: Variant = row.get("saas_outcome", {})
	if not outcome_value is Dictionary: return {}
	var outcome: Dictionary = outcome_value
	if str(outcome.get("model_version", "")) != SOURCE_MODEL: return {}
	var preflight_value: Variant = outcome.get("ai_preflight", {})
	if not preflight_value is Dictionary: return {}
	var preflight: Dictionary = preflight_value
	var report_value: Variant = outcome.get("report", {})
	if not report_value is Dictionary or not bool(report_value.get("submitted", false)): return {}
	var records := _record_set(outcome)
	var approval := _latest_record(records, "consent_review", func(item: Dictionary) -> bool:
		return str(item.get("id", "")) == "AI-301" or str(item.get("data", {}).get("approved_change", "")) == "AI-301"
	)
	var business_run := _latest_record(records, "run_business", func(item: Dictionary) -> bool:
		var data_value: Variant = item.get("data", {})
		if not data_value is Dictionary: return false
		var data: Dictionary = data_value
		var summaries: Variant = data.get("summaries", [])
		return str(data.get("receipt_id", "")) == "RCPT-SUM-001" and summaries is Array and summaries.size() == 6
	)
	var report_record := _latest_record(records, "submit_report")
	if approval.is_empty() or business_run.is_empty() or report_record.is_empty(): return {}
	var originals := [approval.duplicate(true), business_run.duplicate(true), report_record.duplicate(true)]
	var egress_value: Variant = outcome.get("egress", {})
	var egress: Dictionary = egress_value if egress_value is Dictionary else {}
	var copied_rows: Variant = egress.get("exported_rows", [])
	var business: Dictionary = preflight.get("business", {}) if preflight.get("business", {}) is Dictionary else {}
	var prior := {
		"exported_rows":copied_rows.size() if copied_rows is Array else 0,
		"loss_cost":maxi(0, int(business.get("loss_cost", 0))),
		"receipt_id":str(business.get("receipt_id", "")),
		"grade":str(row.get("grade", ""))
	}
	return {
		"source_contract_id":str(row.get("id", "")),
		"source_day":int(row.get("day", 0)),
		"client":CLIENT,
		"approved_originals":originals,
		"prior_result":prior
	}

static func payload(state: Dictionary, day: int) -> Dictionary:
	var rows: Array = state.get("history", []).duplicate(true)
	rows.reverse()
	for raw in rows:
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("case_id", "")) != SOURCE_CASE_ID or str(row.get("client", "")) != CLIENT or not str(row.get("kind", "")).is_empty(): continue
		var source_id := str(row.get("id", ""))
		var source_day := int(row.get("day", 0))
		if source_id.is_empty() or source_id not in state.get("completed_ids", []) or source_day < 1 or source_day >= day: continue
		if str(row.get("grade", "")) not in ["S", "A"]: continue
		var checks: Array = row.get("checks", [])
		if checks.is_empty() or not checks.all(func(check): return check is Dictionary and bool(check.get("passed", false))): continue
		if _already_used(state, source_id) or _working(state, source_id) or _closed_today(state, source_id, day): continue
		var result := _make_payload(row)
		if not result.is_empty(): return result
	return {}

static func matches_available(state: Dictionary, value: Variant, day: int) -> bool:
	if not value is Dictionary or value.is_empty(): return false
	var current := payload(state, day)
	return not current.is_empty() and _canonical(current) == _canonical(value)

static func _history_payload(state: Dictionary) -> Dictionary:
	var rows: Array = state.get("history", []).duplicate(true)
	rows.reverse()
	for raw in rows:
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("case_id", "")) != CASE_ID or str(row.get("client", "")) != CLIENT or not str(row.get("kind", "")).is_empty(): continue
		var source := _handoff_source(row.get("saas_outcome", {}))
		if not source.is_empty(): return source
	for archive in state.get("contract_closeouts", {}).values():
		if not archive is Dictionary: continue
		var record: Variant = archive.get("record", {})
		if record is Dictionary and str(record.get("case_id", "")) == CASE_ID:
			var source := _handoff_source(record.get("saas_outcome", {}))
			if not source.is_empty(): return source
	for context in state.get("contract_contexts", {}).values():
		if not context is Dictionary: continue
		var contract: Variant = context.get("contract", {})
		if contract is Dictionary and str(contract.get("case_id", "")) == CASE_ID:
			var source: Variant = contract.get("saas_ai_handoff_payload", {})
			if source is Dictionary and not source.is_empty(): return source.duplicate(true)
	return {}

static func _source_fulfilled(state: Dictionary, source_id: String) -> bool:
	for row in state.get("history", []):
		if row is Dictionary and str(row.get("case_id", "")) == CASE_ID and str(row.get("id", "")) in state.get("completed_ids", []) and str(_handoff_source(row.get("saas_outcome", {})).get("source_contract_id", "")) == source_id: return true
	return false

static func _source_closed(state: Dictionary, source_id: String) -> bool:
	for archive in state.get("contract_closeouts", {}).values():
		if not archive is Dictionary: continue
		var record: Variant = archive.get("record", {})
		if record is Dictionary and str(record.get("case_id", "")) == CASE_ID and str(_handoff_source(record.get("saas_outcome", {})).get("source_contract_id", "")) == source_id: return true
	return false

static func _source_receipt(state: Dictionary, source_id: String) -> Dictionary:
	for raw in state.get("history", []):
		if not raw is Dictionary: continue
		var row: Dictionary = raw
		if str(row.get("id", "")) != source_id or str(row.get("case_id", "")) != SOURCE_CASE_ID or not str(row.get("kind", "")).is_empty(): continue
		return row
	return {}

static func brief(source: Dictionary) -> String:
	var prior: Dictionary = source.get("prior_result", {}) if source.get("prior_result", {}) is Dictionary else {}
	var rows := int(prior.get("exported_rows", 0))
	var loss := int(prior.get("loss_cost", 0))
	var context := "前回は外部流出・期限補償ともに記録されていません。今回の承認範囲変更を実測してください。"
	if rows > 0 or loss > 0:
		context = "前回記録: 外部送信%d行、期限補償¥%d。今回の対応で既存の送信物や受付記録を消さないでください。" % [rows, loss]
	return BRIEF + " " + context

static func lead(game) -> Dictionary:
	var state: Dictionary = game.state
	var source := payload(state, int(state.day) + 1)
	var fulfilled := false
	var closed := false
	if source.is_empty():
		source = _history_payload(state)
		var source_id := str(source.get("source_contract_id", ""))
		fulfilled = not source_id.is_empty() and _source_fulfilled(state, source_id)
		closed = not source_id.is_empty() and _source_closed(state, source_id)
	if source.is_empty(): return {}
	var offer: Dictionary = {}
	for candidate in state.get("offers", []):
		if candidate is Dictionary and _canonical(candidate.get("saas_ai_handoff_payload", {})) == _canonical(source): offer = candidate; break
	var offer_id := str(offer.get("id", ""))
	var working := false
	for context in state.get("contract_contexts", {}).values():
		if context is Dictionary and not bool(context.get("completed", false)) and _canonical(context.get("contract", {}).get("saas_ai_handoff_payload", {})) == _canonical(source): working = true
	var available: bool = bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)) and not state.get("contract_closeouts", {}).has(offer_id)
	var reasons: Array = []
	if int(game.company_level().get("level", 1)) < 8: reasons.append("会社Lv.8が必要")
	if int(state.get("skills", {}).get("response", 0)) < 1: reasons.append("調査復旧Lv.1が必要")
	var status := "fulfilled" if fulfilled else "working" if working else "paused" if closed else "ready" if available else "locked"
	var reasons_text := " / ".join(reasons)
	if reasons_text.is_empty() and status == "locked": reasons_text = "次の営業日の相談枠で確認できます。"
	if status == "working": reasons_text = "受注済み案件から対応を続けてください。"
	var prior_value: Variant = source.get("prior_result", {})
	var prior: Dictionary = prior_value.duplicate(true) if prior_value is Dictionary else {}
	var source_receipt := _source_receipt(state, str(source.get("source_contract_id", "")))
	var source_rating := str(source_receipt.get("rating", "unknown")) if not source_receipt.is_empty() else "unknown"
	var source_grade := str(source_receipt.get("grade", "unknown")) if not source_receipt.is_empty() else "unknown"
	var source_satisfaction := int(source_receipt.get("satisfaction_after", -1)) if not source_receipt.is_empty() else -1
	var source_day := int(source_receipt.get("day", source.get("source_day", 0))) if not source_receipt.is_empty() else int(source.get("source_day", 0))
	var source_last := {"satisfaction":source_satisfaction,"day":source_day,"rating":source_rating,"grade":source_grade}
	return {"id":"saas-ai-handoff:"+str(source.get("source_contract_id", "")),"client":CLIENT,"case_id":CASE_ID,"title":TITLE,"route_detail":"Dispatch Control・委託先連絡","work_family":"saas-ai-handoff","source_contract_id":str(source.get("source_contract_id", "")),"source_case_id":SOURCE_CASE_ID,"source_title":"公開前審査: AI問い合わせ要約","source_day":int(source.get("source_day", 0)),"source_rating":source_rating,"source_grade":source_grade,"source_satisfaction":source_satisfaction,"source_result_unknown":source_receipt.is_empty(),"last_outcome":source_last,"reason":brief(source),"status":status,"required_level":8,"required_skills":{"response":1},"required_skill":{"response":1},"created_day":int(source.get("source_day", 0))+1,"offer_id":offer_id,"market_available":available,"reasons":reasons,"locked_reason":reasons_text,"prior_result":prior}
