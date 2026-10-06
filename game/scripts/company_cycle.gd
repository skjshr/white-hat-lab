extends RefCounted

## Customer follow-up work is earned by a new, verified delivery. This module
## never issues payment, changes eligibility, or reconstructs historical quality.
const CATALOG := preload("res://scripts/case_catalog.gd")
const HOTEL_HANDOFF := preload("res://scripts/hotel_handoff.gd")
const FAMILIES := ["permissions", "backup", "network", "identity", "endpoint", "external_sharing"]
const EVENT_LIMIT := 100

static func ensure(state: Dictionary) -> void:
	if not state.has("company_cycle"):
		state.company_cycle = {"version":1,"leads":{},"events":[],"processed_deliveries":{},"completed_cases":{},"hotel_recoveries":{}}

static func _whole(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum

static func validate(value: Variant) -> bool:
	if not value is Dictionary or not _whole(value.get("version", null), 1) or int(value.version) != 1: return false
	if not value.get("leads", null) is Dictionary or not value.get("events", null) is Array or not value.get("processed_deliveries", null) is Dictionary: return false
	for field in ["completed_cases", "earned_goals"]:
		if value.has(field) and not value[field] is Dictionary: return false
	if value.has("hotel_recoveries") and not value.hotel_recoveries is Dictionary: return false
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
	for source_id in value.get("hotel_recoveries", {}):
		var recovery: Variant = value.hotel_recoveries[source_id]
		if not source_id is String or source_id.is_empty() or not recovery is Dictionary: return false
		for field in ["source_contract_id", "client", "case_id", "status", "accepted_contract_id"]:
			if not recovery.get(field, null) is String: return false
		if str(recovery.source_contract_id) != source_id or str(recovery.client) != HOTEL_HANDOFF.CLIENT or str(recovery.case_id) != HOTEL_HANDOFF.CASE_ID: return false
		if str(recovery.status) not in ["pending", "working", "fulfilled"] or not recovery.get("handoff", null) is Dictionary or not HOTEL_HANDOFF.valid_handoff(recovery.handoff): return false
		for field in ["source_day", "created_day", "available_day"]:
			if not _whole(recovery.get(field, null), 1): return false
		if int(recovery.available_day) <= int(recovery.source_day): return false
		if str(recovery.status) == "working" and str(recovery.accepted_contract_id).is_empty(): return false
		if str(recovery.status) == "fulfilled" and str(recovery.accepted_contract_id).is_empty(): return false
		if recovery.has("fulfilled_day") and not _whole(recovery.fulfilled_day, 1): return false
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
		if str(item.get("client", "")) != client or bool(item.get("retired_from_new_offers", false)) or bool(item.get("hotel_recovery_only", false)) or bool(item.get("saas_watch_only", false)): continue
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
	if HOTEL_HANDOFF.is_case(case_id):
		var hotel_result := record_hotel_recovery_delivery(game.state, contract_id, receipt)
		return {"changed":true,"event":hotel_result.get("event", {}),"lead":{}}
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
	# The hotel-specific follow-up is created at the next day boundary from the
	# immutable delivered history and retained VM. Do not substitute a generic,
	# unrelated service lead for this proof-bound handoff.
	if not HOTEL_HANDOFF.capture_source(game.state, contract_id).is_empty():
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

## Called by Game._make_offers only. Backfill is grounded in a completed
## delivery row plus the retained source VM; rendering and loading stay pure.
static func refresh_hotel_recoveries(state: Dictionary, day: int) -> bool:
	if not validate(state.get("company_cycle", {})): return false
	var cycle: Dictionary = state.company_cycle
	if not cycle.has("hotel_recoveries") or not cycle.hotel_recoveries is Dictionary: cycle.hotel_recoveries = {}
	var changed := false
	for row in state.get("history", []):
		if not row is Dictionary: continue
		var source_id := str(row.get("id", ""))
		if source_id.is_empty() or cycle.hotel_recoveries.has(source_id): continue
		var source_day := int(row.get("day", 0))
		if source_day < 1 or day <= source_day: continue
		var handoff := HOTEL_HANDOFF.capture_source(state, source_id)
		if handoff.is_empty(): continue
		cycle.hotel_recoveries[source_id] = {"source_contract_id":source_id,"client":HOTEL_HANDOFF.CLIENT,"case_id":HOTEL_HANDOFF.CASE_ID,"source_day":source_day,"created_day":day,"available_day":source_day + 1,"status":"pending","accepted_contract_id":"","handoff":handoff.duplicate(true)}
		_event(cycle, "hotel_recovery_requested", source_id, HOTEL_HANDOFF.CLIENT, HOTEL_HANDOFF.CASE_ID, day, "前回のF-204受付と証拠原本を確認し、予約端末の復旧相談を翌営業日に追加しました。")
		changed = true
	return changed

static func hotel_recovery_records(state: Dictionary, day: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cycle: Variant = state.get("company_cycle", {})
	if not validate(cycle): return result
	var records: Dictionary = cycle.get("hotel_recoveries", {}) if cycle.get("hotel_recoveries", {}) is Dictionary else {}
	var ids: Array = records.keys(); ids.sort()
	for source_id in ids:
		var record: Variant = records[source_id]
		if not record is Dictionary: continue
		var row: Dictionary = record.duplicate(true)
		row.available = str(row.get("status", "")) == "pending" and int(row.get("available_day", 0)) <= day
		row.waiting = str(row.get("status", "")) == "pending" and not bool(row.available)
		result.append(row)
	return result

static func hotel_recovery_available(state: Dictionary, day: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in hotel_recovery_records(state, day):
		if bool(record.get("available", false)): result.append(record.duplicate(true))
	return result

static func mark_hotel_recovery_working(state: Dictionary, source_contract_id: String, accepted_contract_id: String, day: int) -> bool:
	if not validate(state.get("company_cycle", {})) or accepted_contract_id.is_empty(): return false
	var records: Dictionary = state.company_cycle.get("hotel_recoveries", {})
	if not records.has(source_contract_id): return false
	var record: Dictionary = records[source_contract_id]
	if str(record.get("status", "")) != "pending" or int(record.get("available_day", 0)) > day or not HOTEL_HANDOFF.valid_handoff(record.get("handoff", {})): return false
	record.status = "working"; record.accepted_contract_id = accepted_contract_id
	return true

static func record_hotel_recovery_delivery(state: Dictionary, contract_id: String, receipt: Dictionary) -> Dictionary:
	var source_id := str(receipt.get("hotel_recovery_source_contract_id", state.get("contract", {}).get("hotel_recovery_source_contract_id", "")))
	if source_id.is_empty(): return {"changed":false,"event":{}}
	if not validate(state.get("company_cycle", {})): return {"changed":false,"event":{}}
	var records: Dictionary = state.company_cycle.get("hotel_recoveries", {})
	if not records.has(source_id): return {"changed":false,"event":{}}
	var record: Dictionary = records[source_id]
	if str(record.get("status", "")) != "working" or str(record.get("accepted_contract_id", "")) != contract_id or str(receipt.get("case_id", "")) != HOTEL_HANDOFF.CASE_ID: return {"changed":false,"event":{}}
	var checks: Array = receipt.get("checks", []) if receipt.get("checks", []) is Array else []
	if checks.is_empty() or not checks.all(func(row): return row is Dictionary and bool(row.get("passed", false))): return {"changed":false,"event":{}}
	record.status = "fulfilled"; record.fulfilled_day = int(receipt.get("day", state.get("day", 1)))
	var event := _event(state.company_cycle, "hotel_recovery_fulfilled", contract_id, HOTEL_HANDOFF.CLIENT, HOTEL_HANDOFF.CASE_ID, int(receipt.get("day", state.get("day", 1))), "予約端末の復旧と前回記録の引継ぎを納品しました。")
	return {"changed":true,"event":event.duplicate(true)}

static func record_cancellation(state: Dictionary, contract_id: String, receipt: Dictionary) -> bool:
	ensure(state)
	if contract_id.is_empty() or str(receipt.get("kind", "")) != "cancellation" or not validate(state.company_cycle): return false
	var cycle: Dictionary = state.company_cycle
	# Keep the proof-bound source archive and release the accepted recovery for a
	# fresh next-day quote. This must not pause or overwrite the generic lead.
	var hotel_source := str(receipt.get("hotel_recovery_source_contract_id", state.get("contract", {}).get("hotel_recovery_source_contract_id", "")))
	var hotel_records: Dictionary = cycle.get("hotel_recoveries", {})
	if hotel_source.is_empty():
		for source_key in hotel_records:
			var candidate: Variant = hotel_records[source_key]
			if candidate is Dictionary and str(candidate.get("status", "")) == "working" and str(candidate.get("accepted_contract_id", "")) == contract_id:
				hotel_source = str(source_key)
				break
	if not hotel_source.is_empty() and hotel_records.has(hotel_source):
		var hotel_record: Dictionary = hotel_records[hotel_source]
		if str(hotel_record.get("status", "")) == "working" and str(hotel_record.get("accepted_contract_id", "")) == contract_id:
			hotel_record.status = "pending"
			hotel_record.available_day = int(receipt.get("day", state.get("day", 1))) + 1
			hotel_record.accepted_contract_id = ""
			_event(cycle, "hotel_recovery_cancelled", contract_id, HOTEL_HANDOFF.CLIENT, HOTEL_HANDOFF.CASE_ID, int(receipt.get("day", state.get("day", 1))), "予約端末の復旧案件を中止しました。引継ぎ元を保全し、翌営業日に再見積できます。")
			return true
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

static func recovery_work(state: Dictionary, offers: Array, blocked_cases: Array = []) -> Dictionary:
	# A held consultation can earn an ordinary job in an existing demand slot.
	# It still requires the real quote, work, deadline and customer outcome.
	var cycle: Variant = state.get("company_cycle", {})
	if not validate(cycle): return {}
	var chosen: Dictionary = {}
	var completed := _completed_cases(state)
	var clients: Array = cycle.leads.keys(); clients.sort()
	for client in clients:
		var lead: Dictionary = cycle.leads[client]
		if str(lead.status) != "paused": continue
		var working := false
		for context in state.get("contract_contexts", {}).values():
			if context is Dictionary and not bool(context.get("completed", false)) and str(context.get("contract", {}).get("client", "")) == str(client): working = true; break
		if working: continue
		var eligible: Array = offers.filter(func(offer):
			if not offer is Dictionary or str(offer.get("client", "")) != str(client) or not bool(offer.get("unlocked", false)) or bool(offer.get("retired_from_new_offers", false)): return false
			var id := str(offer.get("id", "")); var case_id := str(offer.get("case_id", ""))
			var supply: Variant = offer.get("supply_requirement", {})
			return not id.is_empty() and not case_id.is_empty() and case_id != str(lead.case_id) and case_id not in blocked_cases and id not in state.get("completed_ids", []) and not state.get("contract_contexts", {}).has(id) and (not supply is Dictionary or supply.is_empty()) and case_id != "endpoint-recovery" and not case_id.begins_with("advanced-") and not case_id.begins_with("composite-"))
		eligible.sort_custom(func(a,b):
			var aq: bool = state.get("offer_quotes", {}).has(str(a.id)); var bq: bool = state.get("offer_quotes", {}).has(str(b.id))
			if aq != bq: return aq
			var ad: bool = completed.has(str(a.case_id)); var bd: bool = completed.has(str(b.case_id))
			if ad != bd: return not ad
			var same_a: bool = str(a.case_id) == str(lead.source_case_id); var same_b: bool = str(b.case_id) == str(lead.source_case_id)
			if same_a != same_b: return not same_a
			if int(a.get("required_level", 1)) != int(b.get("required_level", 1)): return int(a.get("required_level", 1)) < int(b.get("required_level", 1))
			return str(a.case_id) < str(b.case_id))
		if not eligible.is_empty(): chosen[str(client)] = eligible[0].duplicate(true)
	# A hotel recovery is an independently earned opportunity, not the generic
	# one-per-client relationship lead. Keep it under a source-specific key so
	# both can coexist without overwriting that lead.
	for recovery in hotel_recovery_available(state, int(state.get("day", 1))):
		var source_id := str(recovery.get("source_contract_id", ""))
		for offer in offers:
			if not offer is Dictionary or str(offer.get("case_id", "")) != HOTEL_HANDOFF.CASE_ID or str(offer.get("client", "")) != HOTEL_HANDOFF.CLIENT: continue
			if offer.has("hotel_recovery_source_contract_id") and str(offer.hotel_recovery_source_contract_id) != source_id: continue
			var selected: Dictionary = offer.duplicate(true)
			selected.hotel_recovery_source_contract_id = source_id
			chosen["hotel:" + source_id] = selected
			break
	return chosen

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
			lead.recovery_working_id = ""
			for context_id in game.state.get("contract_contexts", {}):
				var context: Dictionary = game.state.contract_contexts[context_id]
				if not bool(context.get("completed", false)) and str(context.get("contract", {}).get("client", "")) == str(client):
					lead.recovery_working_id = str(context_id); lead.recovery_working_title = str(context.get("contract", {}).get("title", "進行中の仕事")); break
			for offer in game.state.get("offers", []):
				if not offer is Dictionary or str(offer.get("client", "")) != str(client): continue
				if bool(offer.get("retired_from_new_offers", false)) or not bool(offer.get("unlocked", false)) or not bool(offer.get("market_available", false)): continue
				if str(offer.get("id", "")) in game.state.get("completed_ids", []) or game.state.get("contract_contexts", {}).has(str(offer.get("id", ""))): continue
				available = offer; break
			lead.recovery_case_id = str(lead.case_id); lead.recovery_offer_id = ""
			var next_step := ""
			lead.recovery_offer = available.duplicate(true)
			if not str(lead.recovery_working_id).is_empty():
				lead.recovery_status = "working"
				next_step = "受注済みの「%s」を進め、期限内の納品で関係を確認します。" % str(lead.recovery_working_title)
			elif not available.is_empty():
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
	# One current hotel recovery shares the existing client row. This projection
	# never changes the saved generic lead; after today's fulfillment expires,
	# that original relationship entry becomes visible again.
	var day := int(game.state.get("day", 1))
	for hotel in hotel_recovery_records(game.state, day):
		var hotel_status := str(hotel.get("status", ""))
		var fulfilled_today := hotel_status == "fulfilled" and int(hotel.get("fulfilled_day", 0)) == day
		if hotel_status == "fulfilled" and not fulfilled_today: continue
		if hotel_status not in ["pending", "working", "fulfilled"]: continue
		var source_id := str(hotel.get("source_contract_id", ""))
		var source_row: Dictionary = {}
		for history_row in game.state.get("history", []):
			if history_row is Dictionary and str(history_row.get("id", "")) == source_id:
				source_row = history_row
				break
		var projected_id := "hotel-recovery:" + source_id
		var recovery_lead: Dictionary = {
			"id":projected_id,
			"client":HOTEL_HANDOFF.CLIENT,
			"case_id":HOTEL_HANDOFF.CASE_ID,
			"title":"白波ホテル 予約端末の復旧と次便取込",
			"work_family":"hotel_reservation_recovery",
			"source_contract_id":source_id,
			"source_case_id":HOTEL_HANDOFF.SOURCE_CASE_ID,
			"source_title":str(source_row.get("title", "前回の予約端末隔離")),
			"source_day":int(hotel.get("source_day", 0)),
			"source_rating":str(source_row.get("rating", "")),
			"source_satisfaction":int(source_row.get("satisfaction_after", -1)),
			"reason":"前回のF-204受付記録と証拠原本を確認し、予約端末の復旧相談が届きました。",
			"required_level":5,
			"required_skills":{"response":2},
			"hotel_recovery_status":hotel_status,
			"hotel_recovery_stage":"completed" if fulfilled_today else ("working" if hotel_status == "working" else ("ready" if bool(hotel.get("available", false)) else "waiting")),
			"market_available":false,
			"offer_id":"",
			"reasons":[],
			"locked_reason":"",
			"last_outcome":{"satisfaction":int(game.state.get("customer_relations", {}).get(HOTEL_HANDOFF.CLIENT, {}).get("satisfaction", -1)),"day":day}
		}
		if fulfilled_today:
			recovery_lead.status = "fulfilled"
			recovery_lead.route_state = "fulfilled"
		elif hotel_status == "working":
			recovery_lead.status = "paused"
			recovery_lead.recovery_status = "working"
			recovery_lead.recovery_working_id = str(hotel.get("accepted_contract_id", ""))
			var working_context: Dictionary = game.state.get("contract_contexts", {}).get(str(recovery_lead.recovery_working_id), {})
			recovery_lead.recovery_working_title = str(working_context.get("contract", {}).get("title", recovery_lead.title))
			recovery_lead.recovery_offer_id = ""
			recovery_lead.recovery_offer = {}
		elif bool(hotel.get("available", false)):
			var recovery_offer: Dictionary = {}
			for offer in game.state.get("offers", []):
				if offer is Dictionary and HOTEL_HANDOFF.is_case(str(offer.get("case_id", ""))) and str(offer.get("hotel_recovery_source_contract_id", "")) == source_id:
					recovery_offer = offer
					break
			if recovery_offer.is_empty():
				recovery_lead.status = "locked"
				recovery_lead.locked_reason = "翌日の相談枠がまだ提示されていません。"
			else:
				recovery_lead.id = str(recovery_offer.get("id", projected_id))
				recovery_lead.offer_id = recovery_lead.id
				recovery_lead.market_available = bool(recovery_offer.get("market_available", false))
				recovery_lead.status = "ready" if recovery_lead.market_available else "locked"
				recovery_lead.reasons = _eligibility(game, recovery_lead)
				recovery_lead.locked_reason = " / ".join(recovery_lead.reasons) if not recovery_lead.reasons.is_empty() else "今日の相談枠は提示済みです。"
				recovery_lead.recovery_status = "available"
				recovery_lead.recovery_offer_id = recovery_lead.id
				recovery_lead.recovery_offer = recovery_offer.duplicate(true)
		else:
			recovery_lead.status = "locked"
			recovery_lead.locked_reason = "翌営業日に予約端末の復旧相談を受注できます。"
		var replaced := false
		for index in leads.size():
			if str(leads[index].get("client", "")) == HOTEL_HANDOFF.CLIENT:
				leads[index] = recovery_lead
				replaced = true
				break
		if not replaced: leads.append(recovery_lead)
	return {"leads":leads,"events":cycle.get("events", []).duplicate(true),"relationship_recovery":recoveries,"hotel_recoveries":hotel_recovery_records(game.state, int(game.state.get("day", 1)))}
