extends RefCounted
## A customer's saved delivery earns one new engagement. Views never seed work.
const CASE_ID := "advanced-saas-sessions"
const MODEL := "saas-partner-v1"
const CLIENT := "北斗物流"
const TITLE := "緊急: 委託先への配車表送付"
const BRIEF := "ミナト配送への配車表送付を開始します。同じ外部保存サービスへの別の資料要求も観測されました。前回の原本と本日のOPS-208を照合し、承認された置き場への受渡を守りながら対応してください。請求BILL-004と配車表120行の受付までが契約です。"

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

static func _used(state: Dictionary, source_id: String) -> bool:
	for row in state.get("history", []):
		if not row is Dictionary or not str(row.get("kind", "")).is_empty(): continue
		if str(row.get("id", "")) not in state.get("completed_ids", []): continue
		if str(row.get("saas_outcome", {}).get("session_case", {}).get("partner_source", {}).get("source_contract_id", "")) == source_id: return true
	for context in state.get("contract_contexts", {}).values():
		if context is Dictionary and bool(context.get("completed", false)) and str(context.get("contract", {}).get("saas_partner_payload", {}).get("source_contract_id", "")) == source_id: return true
	return false

static func payload(state: Dictionary, day: int) -> Dictionary:
	if int(state.get("customer_relations", {}).get(CLIENT, {}).get("satisfaction", 0)) < 40: return {}
	var rows: Array = state.get("history", []).duplicate(); rows.reverse()
	for row in rows:
		if not row is Dictionary or str(row.get("case_id", "")) != CASE_ID or not str(row.get("kind", "")).is_empty(): continue
		var id := str(row.get("id", "")); var source_day := int(row.get("day", 0))
		if id.is_empty() or id not in state.get("completed_ids", []) or source_day < 1 or source_day >= day or _used(state, id): continue
		if str(row.get("rating", "")) != "on_time" or int(row.get("satisfaction_after", 0)) < 40: continue
		var checks: Array = row.get("checks", [])
		if checks.is_empty() or not checks.all(func(check): return check is Dictionary and bool(check.get("passed", false))): continue
		var outcome: Dictionary = row.get("saas_outcome", {})
		if str(outcome.get("model_version", "")) not in ["saas-sessions-v1", "saas-sessions-v2"]: continue
		var originals: Array = []
		for original in outcome.get("report", {}).get("original", {}).get("records", []):
			if original is Dictionary and str(original.get("id", "")) in ["audit-1", "audit-2", "audit-3", "audit-4"] and str(original.get("action", "")) in ["consent_review", "session_issued"]:
				originals.append(original.duplicate(true))
		if originals.size() != 4: continue
		return {"source_contract_id":id,"source_day":source_day,"client":CLIENT,"approved_originals":originals}
	return {}

static func matches_available(state: Dictionary, value: Variant, day: int) -> bool:
	if not value is Dictionary or value.is_empty(): return false
	var current := payload(state, day)
	return not current.is_empty() and _canonical(current) == _canonical(value)

static func lead(game) -> Dictionary:
	var state: Dictionary = game.state
	var source := payload(state, int(state.day) + 1)
	var fulfilled := false
	if source.is_empty():
		var rows: Array = state.get("history", []).duplicate(); rows.reverse()
		for row in rows:
			if not row is Dictionary or str(row.get("client", "")) != CLIENT or not str(row.get("kind", "")).is_empty(): continue
			if str(row.get("saas_outcome", {}).get("model_version", "")) != MODEL: break
			if str(row.get("id", "")) not in state.get("completed_ids", []): break
			source = row.get("saas_outcome", {}).get("session_case", {}).get("partner_source", {}).duplicate(true); fulfilled = true; break
	if source.is_empty(): return {}
	var offer: Dictionary = {}
	for candidate in state.get("offers", []):
		if candidate is Dictionary and _canonical(candidate.get("saas_partner_payload", {})) == _canonical(source):
			offer = candidate; break
	var offer_id := str(offer.get("id", ""))
	var working := false
	for context in state.get("contract_contexts", {}).values():
		if context is Dictionary and not bool(context.get("completed", false)) and _canonical(context.get("contract", {}).get("saas_partner_payload", {})) == _canonical(source): working = true
	var ready: bool = not working and not fulfilled and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)) and not state.get("contract_closeouts", {}).has(offer_id)
	var reasons: Array = []
	if int(game.company_level().get("level", 1)) < 5: reasons.append("会社Lv.5が必要")
	if int(state.get("skills", {}).get("response", 0)) < 1: reasons.append("調査復旧Lv.1が必要")
	var reason := "前回保全した承認原本を引き継ぎ、新しい委託先の送付先と本日の要求を比較します。"
	var wait_reason := "受注した案件一覧から対応を続けてください。" if working else "次の営業日の相談枠で確認できます。"
	return {"id":"saas-partner:"+str(source.source_contract_id),"client":CLIENT,"case_id":CASE_ID,"title":TITLE,"work_family":"saas-sessions","source_contract_id":str(source.source_contract_id),"source_case_id":CASE_ID,"source_title":"承認済み連携の接続調査","source_day":int(source.source_day),"source_rating":"on_time","source_satisfaction":int(state.get("customer_relations", {}).get(CLIENT, {}).get("satisfaction", 0)),"last_outcome":{"satisfaction":int(state.get("customer_relations", {}).get(CLIENT, {}).get("satisfaction", 0)),"day":int(state.day)},"reason":reason,"status":"fulfilled" if fulfilled else "working" if working else "ready" if ready else "locked","required_level":5,"required_skills":{"response":1},"required_skill":{"response":1},"created_day":int(source.source_day)+1,"offer_id":offer_id,"market_available":ready,"reasons":reasons,"locked_reason":" / ".join(reasons) if not reasons.is_empty() else "" if fulfilled else wait_reason}
