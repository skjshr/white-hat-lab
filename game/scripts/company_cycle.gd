extends RefCounted

## Customer follow-up work is earned by a new, verified delivery. This module
## never issues payment, changes eligibility, or reconstructs historical quality.
const CATALOG := preload("res://scripts/case_catalog.gd")
const FAMILIES := ["permissions", "backup", "network", "identity", "endpoint", "external_sharing"]
const EVENT_LIMIT := 100

static func ensure(state: Dictionary) -> void:
	if not state.has("company_cycle"):
		state.company_cycle = {"version":1,"leads":{},"events":[],"processed_deliveries":{},"completed_cases":{}}

static func _whole(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum

static func validate(value: Variant) -> bool:
	if not value is Dictionary or not _whole(value.get("version", null), 1) or int(value.version) != 1: return false
	if not value.get("leads", null) is Dictionary or not value.get("events", null) is Array or not value.get("processed_deliveries", null) is Dictionary: return false
	for field in ["completed_cases", "earned_goals"]:
		if value.has(field) and not value[field] is Dictionary: return false
	for field in ["processed_deliveries", "completed_cases"]:
		for key in value.get(field, {}):
			if not key is String or key.is_empty() or not value[field][key] is bool: return false
	for client in value.leads:
		var lead: Variant = value.leads[client]
		if not client is String or client.is_empty() or not lead is Dictionary: return false
		for field in ["id", "client", "case_id", "work_family", "source_contract_id", "source_case_id", "source_title", "title", "reason", "source_rating", "status"]:
			if not lead.get(field, null) is String: return false
		if str(lead.client) != client or str(lead.id).is_empty() or str(lead.case_id).is_empty() or str(lead.source_contract_id).is_empty(): return false
		if str(lead.status) not in ["pending", "paused", "fulfilled"] or str(lead.source_rating) not in ["on_time", "late", "rework"]: return false
		for field in ["source_day", "created_day", "required_level"]:
			if not _whole(lead.get(field, null), 1): return false
		if not _whole(lead.get("source_satisfaction", null)) or int(lead.source_satisfaction) > 100: return false
		if not lead.get("required_skills", null) is Dictionary: return false
		for skill in lead.required_skills:
			if not skill is String or not _whole(lead.required_skills[skill]): return false
		if lead.has("fulfilled_day") and not _whole(lead.fulfilled_day, 1): return false
		if lead.has("fulfilled_contract_id") and not lead.fulfilled_contract_id is String: return false
		if lead.has("last_outcome") and not lead.last_outcome is Dictionary: return false
	for event in value.events:
		if not event is Dictionary: return false
		for field in ["kind", "contract_id", "client", "case_id", "message"]:
			if not event.get(field, null) is String: return false
		if not _whole(event.get("day", null), 1): return false
	for key in value.get("earned_goals", {}):
		var goal: Variant = value.earned_goals[key]
		if not key is String or not goal is Dictionary or not _whole(goal.get("day", null), 1) or not goal.get("title", null) is String: return false
	return true

static func _completed_cases(state: Dictionary) -> Dictionary:
	var completed: Dictionary = state.get("company_cycle", {}).get("completed_cases", {}).duplicate(true)
	# The authored first story already repairs Tsubasa's employee/guest sharing
	# access. Exclude its catalog reprise without rewriting the story receipt's
	# empty case_id or inventing its historical quality. Other stories do not have
	# an assumed one-to-one mapping to a basic catalog case.
	if "share" in state.get("completed_ids", []): completed["service-0-case-0"] = true
	for row in state.get("history", []):
		if row is Dictionary and str(row.get("kind", "")).is_empty():
			var case_id := str(row.get("case_id", ""))
			if not case_id.is_empty(): completed[case_id] = true
	return completed

static func _source_family(state: Dictionary, source: Dictionary) -> String:
	if not source.is_empty(): return str(source.get("work_family", ""))
	return FAMILIES[clampi(int(state.get("chapter", 0)), 0, FAMILIES.size() - 1)]

static func _candidate(state: Dictionary, client: String, family: String, source_id: String) -> Dictionary:
	var completed := _completed_cases(state)
	var choices: Array = []
	for item in CATALOG.all():
		if not item is Dictionary: continue
		if str(item.get("client", "")) != client or bool(item.get("retired_from_new_offers", false)): continue
		var id := str(item.get("id", ""))
		if id.is_empty() or id == source_id or completed.has(id): continue
		if str(item.get("work_family", "")) == family: continue
		choices.append(item)
	choices.sort_custom(func(a: Dictionary, b: Dictionary):
		var left := int(a.get("required_level", 1)); var right := int(b.get("required_level", 1))
		if left != right: return left < right
		return str(a.id) < str(b.id))
	return {} if choices.is_empty() else choices[0]

static func _valid_delivery(state: Dictionary, contract_id: String, receipt: Dictionary) -> bool:
	if contract_id.is_empty() or contract_id not in state.get("completed_ids", []): return false
	if str(receipt.get("client", "")).is_empty() or str(receipt.get("rating", "")) not in ["on_time", "late", "rework"]: return false
	if not receipt.has("satisfaction_after"): return false
	var checks: Variant = receipt.get("checks", [])
	if not checks is Array or checks.is_empty(): return false
	for check in checks:
		if not check is Dictionary or not bool(check.get("passed", false)): return false
	var case_id := str(receipt.get("case_id", ""))
	var source: Dictionary = CATALOG.by_id(case_id) if not case_id.is_empty() else {}
	if not case_id.is_empty() and (source.is_empty() or str(source.get("client", "")) != str(receipt.client)): return false
	for row in state.get("history", []):
		if row is Dictionary and str(row.get("id", "")) == contract_id and str(row.get("case_id", "")) == case_id and str(row.get("kind", "")).is_empty(): return true
	return false

static func _event(cycle: Dictionary, kind: String, contract_id: String, client: String, case_id: String, day: int, message: String) -> Dictionary:
	var event := {"kind":kind,"contract_id":contract_id,"client":client,"case_id":case_id,"day":day,"message":message}
	cycle.events.append(event)
	while cycle.events.size() > EVENT_LIMIT: cycle.events.pop_front()
	return event

static func record_delivery(game, contract_id: String, receipt: Dictionary) -> Dictionary:
	ensure(game.state)
	if not validate(game.state.company_cycle): return {"changed":false,"event":{},"lead":{}}
	var cycle: Dictionary = game.state.company_cycle
	if cycle.processed_deliveries.has(contract_id): return {"changed":false,"event":{},"lead":{}}
	if not _valid_delivery(game.state, contract_id, receipt): return {"changed":false,"event":{},"lead":{}}
	cycle.processed_deliveries[contract_id] = true
	var client := str(receipt.client)
	var case_id := str(receipt.get("case_id", ""))
	var rating := str(receipt.rating)
	if not cycle.has("completed_cases"): cycle.completed_cases = {}
	if not case_id.is_empty(): cycle.completed_cases[case_id] = true
	var satisfaction := clampi(int(receipt.satisfaction_after), 0, 100)
	var day := int(receipt.get("day", game.state.get("day", 1)))
	var good := rating == "on_time" and satisfaction >= 40
	var lead: Dictionary = cycle.leads.get(client, {})
	if not lead.is_empty(): lead.last_outcome = {"contract_id":contract_id,"rating":rating,"satisfaction":satisfaction,"day":day}
	var event := {}
	if not lead.is_empty() and str(lead.get("status", "")) != "fulfilled":
		if str(lead.get("case_id", "")) == case_id:
			lead.status = "fulfilled"; lead.fulfilled_contract_id = contract_id; lead.fulfilled_day = day
			event = _event(cycle, "fulfilled", contract_id, client, case_id, day, "指名相談の仕事を納品しました。")
		else:
			if not good:
				lead.status = "paused"
				event = _event(cycle, "paused", contract_id, client, str(lead.case_id), day, "納期・手戻り・顧客との関係を確認するため、指名相談を保留しました。")
			elif str(lead.get("status", "")) == "paused":
				lead.status = "pending"
				event = _event(cycle, "resumed", contract_id, client, str(lead.case_id), day, "期限内の納品と顧客満足の回復を受け、指名相談が再開しました。")
			return {"changed":true,"event":event,"lead":lead.duplicate(true)}
	var source: Dictionary = CATALOG.by_id(case_id) if not case_id.is_empty() else {}
	var candidate := _candidate(game.state, client, _source_family(game.state, source), case_id)
	if candidate.is_empty(): return {"changed":true,"event":event,"lead":lead.duplicate(true)}
	var source_title := str(receipt.get("title", source.get("title", "前回の仕事")))
	var reason := "「%s」の納品を受け、同じ顧客から別のサービスについて相談が届きました。" % source_title
	lead = {"id":"follow-up:"+contract_id,"client":client,"case_id":str(candidate.id),"title":str(candidate.title),"work_family":str(candidate.work_family),"source_contract_id":contract_id,"source_case_id":case_id,"source_title":source_title,"source_day":day,"source_rating":rating,"source_satisfaction":satisfaction,"reason":reason,"status":"pending" if good else "paused","required_level":int(candidate.get("required_level", 1)),"required_skills":candidate.get("required_skills", {}).duplicate(true),"created_day":day,"last_outcome":{"contract_id":contract_id,"rating":rating,"satisfaction":satisfaction,"day":day}}
	cycle.leads[client] = lead
	event = _event(cycle, "requested" if good else "paused", contract_id, client, str(candidate.id), day, reason if good else "次の指名相談は保留中です。通常の依頼で納品と顧客との関係を改善できます。")
	return {"changed":true,"event":event,"lead":lead.duplicate(true)}

static func record_cancellation(state: Dictionary, contract_id: String, receipt: Dictionary) -> bool:
	ensure(state)
	if contract_id.is_empty() or str(receipt.get("kind", "")) != "cancellation" or not validate(state.company_cycle): return false
	var cycle: Dictionary = state.company_cycle
	var client := str(receipt.get("client", ""))
	if client.is_empty(): return true
	var lead: Dictionary = cycle.leads.get(client, {})
	if lead.is_empty() or str(lead.get("status", "")) == "fulfilled": return true
	lead.status = "paused"
	lead.last_outcome = {"contract_id":contract_id,"rating":"cancelled","satisfaction":int(receipt.get("satisfaction_after",0)),"day":int(receipt.get("day",state.get("day",1)))}
	cycle.leads[client] = lead
	_event(cycle, "cancelled", contract_id, client, str(lead.get("case_id", "")), int(receipt.get("day", state.get("day", 1))), "案件が中止されたため、指名相談をいったん保留しました。")
	return true

static func _eligibility(game, lead: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	var level := int(game.company_level().get("level", 1))
	var needed := int(lead.get("required_level", 1))
	if level < needed: reasons.append("会社Lv.%dが必要（現在Lv.%d）" % [needed, level])
	var labels := {"advisory":"診断・助言","operations":"運用","response":"事故対応"}
	var requirements: Dictionary = lead.get("required_skills", {})
	var keys := requirements.keys(); keys.sort()
	for skill in keys:
		var current := int(game.state.get("skills", {}).get(skill, 0))
		if current < int(requirements[skill]): reasons.append("%sスキル%dが必要（現在%d）" % [str(labels.get(skill, skill)), int(requirements[skill]), current])
	return reasons

static func priority_case_ids(game) -> Array[String]:
	var ids: Array[String] = []
	for lead in view(game).leads:
		if str(lead.status) == "ready" and str(lead.case_id) not in ids: ids.append(str(lead.case_id))
	return ids

static func view(game) -> Dictionary:
	# Rendering never migrates or mutates the saved company.
	var raw: Variant = game.state.get("company_cycle", null)
	if not validate(raw): return {"leads":[],"events":[],"relationship_recovery":[]}
	var cycle: Dictionary = raw
	var leads: Array = []
	var recoveries: Array = []
	var names: Array = cycle.get("leads", {}).keys(); names.sort()
	for client in names:
		var stored: Variant = cycle.leads[client]
		if not stored is Dictionary: continue
		var lead: Dictionary = stored.duplicate(true)
		var definition: Dictionary = CATALOG.by_id(str(lead.get("case_id", "")))
		if definition.is_empty() or bool(definition.get("retired_from_new_offers", false)): continue
		var reasons := _eligibility(game, lead)
		var status := str(lead.get("status", "pending"))
		if status == "pending": status = "ready" if reasons.is_empty() else "locked"
		lead.status = status; lead.reasons = reasons; lead.locked_reason = " / ".join(reasons)
		lead.required_skill = lead.get("required_skills", {}).duplicate(true)
		lead.offer_id = ""; lead.market_available = false
		for offer in game.state.get("offers", []):
			if offer is Dictionary and str(offer.get("case_id", "")) == str(lead.case_id):
				lead.offer_id = str(offer.get("id", "")); lead.market_available = bool(offer.get("market_available", false)); break
		if status == "paused":
			var available := {}
			for offer in game.state.get("offers", []):
				if not offer is Dictionary or str(offer.get("client", "")) != str(client): continue
				if bool(offer.get("retired_from_new_offers", false)) or not bool(offer.get("unlocked", false)) or not bool(offer.get("market_available", false)): continue
				if str(offer.get("id", "")) in game.state.get("completed_ids", []) or game.state.get("contract_contexts", {}).has(str(offer.get("id", ""))): continue
				available = offer; break
			lead.recovery_case_id = str(lead.case_id); lead.recovery_offer_id = ""
			var next_step := ""
			if not available.is_empty():
				lead.recovery_case_id = str(available.get("case_id", "")); lead.recovery_offer_id = str(available.get("id", "")); lead.recovery_status = "available"
				next_step = "今日の通常依頼「%s」で、見積と受注条件を確認できます。" % str(available.get("title", available.get("case_id", "")))
			elif not reasons.is_empty():
				lead.recovery_status = "locked"
				next_step = "次の同顧客の仕事「%s」には%s。今はほかの依頼で会社を育て、必要な専門スキルを準備してください。" % [str(lead.title), " / ".join(reasons)]
			else:
				lead.recovery_status = "not_requested"
				next_step = "「%s」の受注条件は満たしていますが、今日の通常市場にはこの顧客の未受注依頼がありません。ほかの仕事を進め、翌日の依頼を確認してください。" % str(lead.title)
			lead.recovery_goal = "この顧客への期限内納品と顧客満足度40以上で指名相談を再開します。" + next_step
			recoveries.append({"client":str(client),"case_id":str(lead.case_id),"goal":str(lead.recovery_goal),"recovery_case_id":str(lead.recovery_case_id),"recovery_offer_id":str(lead.recovery_offer_id),"status":str(lead.recovery_status),"required_level":int(lead.required_level),"required_skills":lead.required_skills.duplicate(true),"satisfaction":int(game.state.get("customer_relations", {}).get(client, {}).get("satisfaction", lead.get("source_satisfaction", 0)))})
		leads.append(lead)
	return {"leads":leads,"events":cycle.get("events", []).duplicate(true),"relationship_recovery":recoveries}
