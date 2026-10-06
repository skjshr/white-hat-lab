extends RefCounted
## Offline, deterministic pre-release review of a SaaS summarization workflow.
## Projections are pure; only explicit actions advance the incident clock.

const CASE_ID := "advanced-saas-ai-preflight"
const KIND := "advanced-saas-response"
const MODEL_VERSION := "saas-ai-preflight-v1"
const CLIENT := "北斗物流"
const APPROVAL_ID := "AI-301"
const SUMMARY_ID := "SUM-001"
const SUMMARY_RECEIPT := "RCPT-SUM-001"
const EGRESS_DUE := [12, 18]
const ROW_COST := 1500
const LATE_COST := 900
const ASSISTANT_COST := 300
const COMPARISON_VERSION := 1
const POLICY_KEYS := ["faq", "dispatch", "customers", "desk", "external"]
const REQUIRED_SUMMARY_KEYS := ["faq", "dispatch", "desk"]
const REQUESTS := [
	{"id":"REQ301","shipment_id":"SHP-041","subject":"到着予定の確認","faq_key":"delivery_window"},
	{"id":"REQ302","shipment_id":"SHP-041","subject":"不在時の再配達","faq_key":"redelivery"},
	{"id":"REQ303","shipment_id":"SHP-041","subject":"遅延時の案内","faq_key":"delay_contact"},
	{"id":"REQ304","shipment_id":"SHP-042","subject":"現在の配送状況","faq_key":"delivery_window"},
	{"id":"REQ305","shipment_id":"SHP-042","subject":"受取日時の変更","faq_key":"redelivery"},
	{"id":"REQ306","shipment_id":"SHP-043","subject":"予定未確定の案内","faq_key":"delay_contact"}
]
const KNOWLEDGE := {
	"faq_total_count":24,
	"shipment_total_count":120,
	"faq": {
		"delivery_window":"配送状況に表示された予定時刻が目安です。",
		"redelivery":"不在票の案内から配送会社へ再配達を依頼できます。",
		"delay_contact":"予定が未確定の場合は配送状況を確認し、確定後に案内します。"
	},
	"shipments": {
		"SHP-041":{"status":"出荷準備中","eta":"本日午後"},
		"SHP-042":{"status":"配送中","eta":"明日午前"},
		"SHP-043":{"status":"集荷確認中","eta":"未確定"}
	}
}

static func _result(ok: bool, changed: bool, observed: bool, minutes: int, usage_cost: int, impact_cost: int, message: String, data: Dictionary = {}) -> Dictionary:
	var actual_data: Dictionary = data.duplicate(true)
	actual_data["usage_cost"] = usage_cost
	actual_data["impact_cost"] = impact_cost
	return {"ok":ok,"changed":changed,"observed":observed,"minutes":minutes,"cost":usage_cost + impact_cost,"usage_cost":usage_cost,"impact_cost":impact_cost,"message":message,"data":actual_data}

static func _error(message: String) -> Dictionary:
	return _result(false, false, false, 0, 0, 0, message)

static func _whole(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

static func create(case_id: String = CASE_ID) -> Dictionary:
	if case_id != CASE_ID: return {}
	var approval := {"id":APPROVAL_ID,"seq":1,"minute":0,"actor":"operations-owner","app":"summary-assistant","destination":"internal-desk","action":"consent_review","status":200,"revision":0,"world_revision":0,"detail":"AI-301: 配送進捗を社内問い合わせデスクで要約する申請。顧客連絡先と外部送付は含まれません。","data":{"approved_change":"AI-301","client":CLIENT,"approved_sources":["faq","dispatch"],"approved_recipient":"desk","approved_by":"operations-owner"}}
	var state := {
		"kind":KIND,"case_id":CASE_ID,"model_version":MODEL_VERSION,"revision":0,"world_revision":0,"elapsed_minutes":0,"sequence":1,
		"source":{},"records":[approval.duplicate(true)],"audit":[approval.duplicate(true)],
		"ai_preflight":{"policy":{"faq":true,"dispatch":true,"customers":true,"desk":true,"external":true},"policy_revision":0,"business":{"status":"pending","receipt_id":"","verified_revision":-1,"receipt_verified_minute":-1,"attempts":[],"summary_rows":6,"accepted_summaries":[],"deadline_minute":14,"late":false,"deadline_late_charged":false,"loss_cost":0,"late_record_id":""},"requests":REQUESTS.duplicate(true),"knowledge":KNOWLEDGE.duplicate(true),"schedule":[],"organization":{"mode":"","record_ids":[],"input_hash":"","usage_cost":0,"impact_cost":0,"created_minute":-1,"world_revision":-1,"policy_revision":-1,"comparison":{}},"report":{"submitted":false,"version":0,"record_ids":[],"input_hash":"","accepted_minute":-1,"revision":-1,"original":{},"latest":{},"supplements":[]},"impact_cost":0},
		"egress":{"schedule":[],"exported_rows":[],"impact_cost":0},
		"invoice":{"id":SUMMARY_ID,"customer":CLIENT,"amount":0,"status":"pending","attempts":[],"receipt_id":"","accepted_summaries":[],"submitted_minute":-1,"verified_revision":-1},
		"organization":{"mode":"","record_ids":[],"input_hash":"","usage_cost":0,"impact_cost":0,"created_minute":-1,"world_revision":-1,"policy_revision":-1,"comparison":{}},
		"report":{"submitted":false,"version":0,"record_ids":[],"input_hash":"","accepted_minute":-1,"revision":-1,"original":{},"latest":{},"supplements":[]},"last_result":{}
	}
	for index in EGRESS_DUE.size():
		var item := {"id":"AI-SYNC-%02d" % (index + 1),"due_minute":int(EGRESS_DUE[index]),"status":"scheduled","read_status":0,"write_status":0,"row_count":0,"record_ids":[]}
		state.egress.schedule.append(item.duplicate(true))
		state.ai_preflight.schedule.append(item.duplicate(true))
	return state

static func _valid_previous_source(payload: Variant) -> bool:
	if not payload is Dictionary: return false
	if str(payload.get("source_contract_id", "")).is_empty() or not _whole(payload.get("source_day", null), 1): return false
	if str(payload.get("client", "")) != CLIENT: return false
	var originals: Variant = payload.get("approved_originals", null)
	if not originals is Array or originals.size() != 4: return false
	var expected := {"audit-1":"consent_review","audit-2":"session_issued","audit-3":"session_issued","audit-4":"session_issued"}
	var found: Dictionary = {}
	for row in originals:
		if not row is Dictionary: return false
		var record_id := str(row.get("id", ""))
		if not expected.has(record_id) or found.has(record_id) or str(row.get("action", "")) != str(expected[record_id]) or int(row.get("status", 0)) != 200: return false
		if not row.get("data", null) is Dictionary: return false
		found[record_id] = true
	if found.size() != expected.size(): return false
	var report: Variant = payload.get("prior_report", {})
	if not report is Dictionary: return false
	if not str(report.get("record_id", "")).is_empty() and not report.get("records", null) is Array: return false
	return true

static func create_followup(payload: Dictionary) -> Dictionary:
	if not _valid_previous_source(payload): return {}
	var state := create()
	if state.is_empty(): return {}
	var source := {"source_contract_id":str(payload.source_contract_id),"source_day":int(payload.source_day),"client":CLIENT,"approved_originals":payload.approved_originals.duplicate(true),"prior_report":payload.get("prior_report", {}).duplicate(true)}
	state["source"] = source.duplicate(true)
	state.ai_preflight.source = source.duplicate(true)
	var records: Array = state.get("records", []).duplicate(true)
	var sequence := 1
	for prior in source.approved_originals:
		sequence += 1
		var source_id := str(prior.get("id", ""))
		var row := {"id":"AI-BASE-%s" % source_id,"seq":sequence,"minute":0,"actor":"prior-case","app":"","destination":"prior-case/%s" % source.source_contract_id,"action":"baseline_reference","status":200,"revision":int(prior.get("world_revision", prior.get("revision", 0))),"world_revision":0,"detail":"前回の承認原記録の参照です。今回の測定ではありません。","data":{"source_contract_id":source.source_contract_id,"source_day":source.source_day,"source_record_id":source_id,"original":prior.duplicate(true)}}
		records.append(row)
	state["records"] = records
	state["sequence"] = sequence
	var audit: Array = state.get("audit", []).duplicate(true)
	for row in records:
		if str(row.get("action", "")) == "baseline_reference": audit.append(row.duplicate(true))
	state["audit"] = audit
	return state

static func _valid_state(state: Dictionary) -> bool:
	if str(state.get("kind", "")) != KIND or str(state.get("case_id", "")) != CASE_ID or str(state.get("model_version", "")) != MODEL_VERSION: return false
	for key in ["revision", "world_revision", "elapsed_minutes", "sequence"]:
		if not _whole(state.get(key, null)): return false
	for key in ["source", "ai_preflight", "egress", "invoice", "organization", "report"]:
		if not state.get(key, null) is Dictionary: return false
	var source: Dictionary = state.source
	if not source.is_empty() and not _valid_previous_source(source): return false
	var preflight: Dictionary = state.ai_preflight
	var policy: Variant = preflight.get("policy", null)
	if not policy is Dictionary: return false
	for key in POLICY_KEYS:
		if not policy.get(key, null) is bool: return false
	if not _whole(preflight.get("policy_revision", null)): return false
	var business: Variant = preflight.get("business", null)
	if not business is Dictionary: return false
	for key in ["attempts"]:
		if not business.get(key, null) is Array: return false
	if not _whole(business.get("loss_cost", null)) or not _whole(business.get("summary_rows", null), 1): return false
	if typeof(business.get("late", null)) != TYPE_BOOL: return false
	if not preflight.get("schedule", null) is Array or not preflight.get("report", null) is Dictionary or not preflight.get("organization", null) is Dictionary: return false
	if not state.get("records", null) is Array or not state.get("audit", null) is Array: return false
	if not state.egress.get("schedule", null) is Array or not state.egress.get("exported_rows", null) is Array: return false
	if not state.invoice.get("attempts", null) is Array or not state.report.get("supplements", null) is Array: return false
	return true

static func _append_record(state: Dictionary, action: String, status: int, destination: String, detail: String, data: Dictionary = {}, minute_override: int = -1) -> Dictionary:
	state.sequence = int(state.get("sequence", 0)) + 1
	var minute := int(state.get("elapsed_minutes", 0)) if minute_override < 0 else minute_override
	var row := {"id":"AI-REC-%03d" % int(state.sequence),"seq":int(state.sequence),"minute":minute,"actor":"analyst","app":"summary-assistant","destination":destination,"action":action,"status":status,"detail":detail,"revision":int(state.get("world_revision", 0)),"world_revision":int(state.get("world_revision", 0)),"data":data.duplicate(true)}
	state.records.append(row)
	return row

static func _flat_record(source: Dictionary) -> Dictionary:
	var row: Dictionary = source.duplicate(false)
	var data: Dictionary = source.get("data", {}).duplicate(false)
	data.erase("records")
	data.erase("events")
	row["data"] = data
	return row

static func _advance_scheduled_event(state: Dictionary, schedule_index: int) -> int:
	var ai: Dictionary = state.ai_preflight
	var egress: Dictionary = state.egress
	var schedules: Array = egress.get("schedule", [])
	if schedule_index < 0 or schedule_index >= schedules.size(): return 0
	var event: Dictionary = schedules[schedule_index]
	if str(event.get("status", "")) != "scheduled": return 0
	var policy: Dictionary = ai.get("policy", {})
	var read_status := 200 if bool(policy.get("customers", false)) else 403
	var write_status := 200 if bool(policy.get("external", false)) else 403
	var row_count := 3 if read_status == 200 and write_status == 200 else 0
	var row_ids: Array[String] = []
	var impact_added := 0
	if row_count > 0:
		impact_added = ROW_COST
		ai.impact_cost = int(ai.get("impact_cost", 0)) + ROW_COST
		egress.impact_cost = int(egress.get("impact_cost", 0)) + ROW_COST
		for row_index in row_count:
			var leaked := {"id":"%s-ROW-%d" % [str(event.get("id", "AI-SYNC")),row_index+1],"schedule_id":str(event.get("id", "")),"minute":int(event.get("due_minute", state.elapsed_minutes)),"record_id":"","data_class":"customer-contact","cost":int(ROW_COST/row_count)}
			row_ids.append(str(leaked.id))
			egress.exported_rows.append(leaked)
	var due_minute := int(event.get("due_minute", state.elapsed_minutes))
	var read_record := _append_record(state,"scheduled_customer_read",read_status,"customers/contact","定時要約同期の顧客連絡先読取結果を記録しました。",{"schedule_id":str(event.get("id", "")),"policy_revision":int(ai.policy_revision),"read_rows":3 if read_status == 200 else 0,"world_revision":int(state.world_revision)},due_minute)
	var write_record := _append_record(state,"scheduled_external_write",write_status if row_count > 0 else 403,"external-support-drop","定時送付の結果を記録しました。",{"schedule_id":str(event.get("id", "")),"policy_revision":int(ai.policy_revision),"row_count":row_count,"blocked":row_count == 0,"recipient_allowed":bool(policy.get("external", false)),"blocked_reason":"customer-read-denied" if read_status != 200 else "recipient-policy" if write_status != 200 else "","leaked_row_ids":row_ids,"world_revision":int(state.world_revision)},due_minute)
	if row_count > 0:
		for leaked_value in egress.exported_rows:
			var leaked: Dictionary = leaked_value
			if str(leaked.get("schedule_id", "")) == str(event.get("id", "")):
				leaked["record_id"] = str(write_record.get("id", ""))
	var updated: Dictionary = event.duplicate(true)
	updated["status"] = "completed" if row_count > 0 else "blocked"
	updated["read_status"] = read_status
	updated["write_status"] = write_record.get("status", 403)
	updated["row_count"] = row_count
	updated["record_ids"] = [str(read_record.get("id", "")),str(write_record.get("id", ""))]
	schedules[schedule_index] = updated
	var ai_schedule: Array = ai.get("schedule", [])
	if schedule_index < ai_schedule.size(): ai_schedule[schedule_index] = updated.duplicate(true)
	egress["schedule"] = schedules
	ai["schedule"] = ai_schedule
	state["egress"] = egress
	state["ai_preflight"] = ai
	return impact_added

static func _advance_business_deadline(state: Dictionary) -> int:
	var ai: Dictionary = state.ai_preflight
	var business: Dictionary = ai.get("business", {})
	if bool(business.get("deadline_late_charged", false)) or int(business.get("receipt_verified_minute", -1)) >= 0: return 0
	business["late"] = true
	business["deadline_late_charged"] = true
	business["loss_cost"] = int(business.get("loss_cost", 0)) + LATE_COST
	var late_record := _append_record(state,"summary_overdue",429,"internal-desk","要約受付が期限を超えました。遅延費用を一度記録しました。",{"deadline_minute":14,"loss_amount":LATE_COST,"policy_revision":int(ai.policy_revision)},15)
	business["late_record_id"] = str(late_record.get("id", ""))
	ai["business"] = business
	state["ai_preflight"] = ai
	return LATE_COST

static func _advance(state: Dictionary, minutes: int) -> int:
	if minutes <= 0: return 0
	var start := int(state.get("elapsed_minutes", 0))
	var finish := start + minutes
	var milestones: Array[Dictionary] = []
	var schedules: Array = state.egress.get("schedule", [])
	for schedule_index in schedules.size():
		var event: Dictionary = schedules[schedule_index]
		var due := int(event.get("due_minute", -1))
		if str(event.get("status", "")) == "scheduled" and due > start and due <= finish:
			milestones.append({"minute":due,"kind":"egress","index":schedule_index})
	var business_before: Dictionary = state.ai_preflight.get("business", {})
	if not bool(business_before.get("deadline_late_charged", false)) and int(business_before.get("receipt_verified_minute", -1)) < 0 and start <= 14 and finish > 14:
		milestones.append({"minute":15,"kind":"deadline","index":-1})
	milestones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("minute", 0)) == int(b.get("minute", 0)): return str(a.get("kind", "")) < str(b.get("kind", ""))
		return int(a.get("minute", 0)) < int(b.get("minute", 0)))
	var impact_added := 0
	for milestone in milestones:
		if str(milestone.get("kind", "")) == "egress": impact_added += _advance_scheduled_event(state,int(milestone.get("index", -1)))
		else: impact_added += _advance_business_deadline(state)
	state.elapsed_minutes = finish
	return impact_added

static func advance(state: Dictionary, minutes: int) -> int:
	if not _valid_state(state) or not _whole(minutes): return 0
	return _advance(state, int(minutes))

static func _input_hash(ids: Array[String]) -> String:
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	return "|".join(sorted_ids)

static func _record_by_id(state: Dictionary, record_id: String) -> Dictionary:
	for raw in state.get("records", []):
		if str(raw.get("id", "")) == record_id: return raw
	return {}

static func _selected_records(state: Dictionary, ids: Array[String]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record_id in ids:
		var row := _record_by_id(state, record_id)
		if row.is_empty(): return []
		rows.append(row)
	return rows

static func _request_dataset(state: Dictionary) -> Array:
	var value: Variant = state.get("ai_preflight", {}).get("requests", null)
	return value.duplicate(true) if value is Array and not value.is_empty() else REQUESTS.duplicate(true)

static func _knowledge_dataset(state: Dictionary) -> Dictionary:
	var value: Variant = state.get("ai_preflight", {}).get("knowledge", null)
	return value.duplicate(true) if value is Dictionary and not value.is_empty() else KNOWLEDGE.duplicate(true)

static func _derive_summaries(state: Dictionary) -> Array[Dictionary]:
	var knowledge := _knowledge_dataset(state)
	var faq: Dictionary = knowledge.get("faq", {})
	var shipments: Dictionary = knowledge.get("shipments", {})
	var summaries: Array[Dictionary] = []
	for request_value in _request_dataset(state):
		if not request_value is Dictionary: continue
		var request: Dictionary = request_value
		var request_id := str(request.get("id", ""))
		var subject := str(request.get("subject", ""))
		var shipment_id := str(request.get("shipment_id", ""))
		var faq_key := str(request.get("faq_key", ""))
		var shipment_value: Variant = shipments.get(shipment_id, null)
		var faq_text := str(faq.get(faq_key, ""))
		if request_id.is_empty() or subject.is_empty() or not shipment_value is Dictionary or faq_text.is_empty(): continue
		var shipment: Dictionary = shipment_value
		var status := str(shipment.get("status", "状況確認中"))
		var eta := str(shipment.get("eta", "未確定"))
		var summary := "%sは%s、予定は%sです。%s" % [shipment_id,status,eta,faq_text]
		summaries.append({"request_id":request_id,"shipment_id":shipment_id,"subject":subject,"status":status,"eta":eta,"guidance":faq_text,"summary":summary,"faq_key":faq_key})
	return summaries

static func _audit_event_ids(record: Dictionary) -> Array:
	var result: Array = []
	var data: Dictionary = record.get("data", {})
	for value in data.get("event_record_ids", []): result.append(str(value))
	return result

static func _report_current(state: Dictionary) -> bool:
	var report: Dictionary = state.get("report", {})
	if not bool(report.get("submitted", false)): return false
	var latest: Dictionary = report.get("latest", report.get("original", {}))
	if latest.is_empty() or int(latest.get("policy_revision", -1)) != int(state.ai_preflight.policy_revision): return false
	var selected: Array = latest.get("record_ids", [])
	var captured: Dictionary = {}
	for raw in latest.get("records", []):
		if str(raw.get("action", "")) == "collect_audit":
			for event_id in _audit_event_ids(raw): captured[str(event_id)] = true
	for leaked in state.egress.get("exported_rows", []):
		var record_id := str(leaked.get("record_id", ""))
		if not record_id.is_empty() and record_id not in selected and not captured.has(record_id): return false
	var business: Dictionary = state.ai_preflight.get("business", {})
	var late_id := str(business.get("late_record_id", ""))
	if not late_id.is_empty() and late_id not in selected and not captured.has(late_id): return false
	return true

static func _report_requirements(state: Dictionary) -> bool:
	if not _report_current(state): return false
	var latest: Dictionary = state.report.get("latest", state.report.get("original", {}))
	var ids: Array = latest.get("record_ids", [])
	if APPROVAL_ID not in ids: return false
	for prior in state.get("source", {}).get("approved_originals", []):
		if ("AI-BASE-%s" % str(prior.get("id", ""))) not in ids: return false
	var selected: Dictionary = {}
	for row in latest.get("records", []): selected[str(row.get("id", ""))] = row
	var read_ok := false
	var write_ok := false
	var business_ok := false
	var current_audit := false
	for row in selected.values():
		var action := str(row.get("action", ""))
		if action == "boundary_read" and int(row.get("status", 0)) == 403 and int(row.get("world_revision", -1)) == int(state.world_revision): read_ok = true
		if action == "boundary_write" and int(row.get("status", 0)) == 403 and int(row.get("world_revision", -1)) == int(state.world_revision): write_ok = true
		if action == "run_business" and int(row.get("status", 0)) == 200 and int(row.get("world_revision", -1)) == int(state.world_revision) and str(row.get("data", {}).get("receipt_id", "")) == SUMMARY_RECEIPT: business_ok = true
		if action == "collect_audit":
			var event_ids := _audit_event_ids(row)
			var required: Array[String] = []
			for source_id in ids:
				var selected_id := str(source_id)
				if selected_id != APPROVAL_ID and selected_id.begins_with("AI-BASE-"): required.append(selected_id)
				if selected_id in selected and str(selected[selected_id].get("action", "")) in ["boundary_read", "boundary_write", "run_business"]: required.append(selected_id)
			for leaked in state.egress.get("exported_rows", []):
				var write_record_id := str(leaked.get("record_id", ""))
				if not write_record_id.is_empty(): required.append(write_record_id)
			var late_record_id := str(state.ai_preflight.business.get("late_record_id", ""))
			if not late_record_id.is_empty(): required.append(late_record_id)
			if required.all(func(id): return id in event_ids): current_audit = true
	return read_ok and write_ok and business_ok and current_audit

static func _append_audit(state: Dictionary) -> Dictionary:
	var audit_ids: Array[String] = []
	var event_ids: Array[String] = []
	var events: Array[Dictionary] = []
	for raw in state.get("audit", []): audit_ids.append(str(raw.get("id", "")))
	for raw in state.get("records", []):
		var id := str(raw.get("id", ""))
		if id.is_empty(): continue
		event_ids.append(id)
		events.append(_flat_record(raw))
	return _append_record(state,"collect_audit",200,"audit-log","承認原本と取得時点までの実操作履歴を取得しました。",{"audit_ids":audit_ids,"event_record_ids":event_ids,"events":events,"policy_revision":int(state.ai_preflight.policy_revision)})

static func _act(state: Dictionary, action: String, args: Dictionary) -> Dictionary:
	var minutes := 0
	var usage_cost := 0
	var impact_cost := 0
	var key := str(args.get("key", ""))
	var enabled_value: Variant = args.get("enabled", null)
	var ids_value: Variant = args.get("record_ids", [])
	match action:
		"configure":
			if key not in POLICY_KEYS or not enabled_value is bool: return _error("読取範囲または送付先を選び直してください。")
			if bool(state.ai_preflight.policy.get(key, false)) == bool(enabled_value): return _result(true,false,false,0,0,0,"設定はすでにその状態です。")
			minutes = 1
		"run_business":
			var invoice: Dictionary = state.invoice
			if str(invoice.get("receipt_id", "")) == SUMMARY_RECEIPT and int(invoice.get("verified_revision", -1)) == int(state.world_revision):
				return _result(true,false,false,0,0,0,"現在世代の要約受付は完了しています。",{"receipt_id":SUMMARY_RECEIPT,"duplicate":true})
			minutes = 2
		"probe_boundaries": minutes = 2
		"wait":
			minutes = 3
		"collect_audit": minutes = 2
		"organize_records":
			var mode := str(args.get("mode", ""))
			if mode not in ["manual", "assistant"] or not ids_value is Array or ids_value.is_empty() or ids_value.size() > 32: return _error("整理方法と原記録を選んでください。")
			var ids: Array[String] = []
			for value in ids_value:
				var record_id := str(value)
				if record_id.is_empty() or record_id in ids or _record_by_id(state, record_id).is_empty(): return _error("未取得または重複した原記録が含まれています。")
				ids.append(record_id)
			var input_hash := _input_hash(ids)
			var previous: Dictionary = state.organization
			if str(previous.get("input_hash", "")) == input_hash and str(previous.get("mode", "")) == mode:
				return _result(true,false,false,0,0,0,"同じ選択の整理結果を再表示します。",{"input_hash":input_hash,"record_ids":ids})
			minutes = 5 if mode == "manual" else 2
			usage_cost = ASSISTANT_COST if mode == "assistant" else 0
		"submit_report":
			if not ids_value is Array or ids_value.is_empty() or ids_value.size() > 32: return _error("報告する原記録を選んでください。")
			var report_ids: Array[String] = []
			for value in ids_value:
				var report_id := str(value)
				if report_id.is_empty() or report_id in report_ids or _record_by_id(state, report_id).is_empty(): return _error("未取得または重複した原記録が含まれています。")
				report_ids.append(report_id)
			minutes = 2
		_:
			return _error("この公開前審査の操作を選んでください。")

	impact_cost += _advance(state, minutes)
	var changed := true
	var observed := true
	var result := _result(true,true,true,minutes,usage_cost,impact_cost,"操作を記録しました。")
	var record: Dictionary = {}
	match action:
		"configure":
			state.ai_preflight.policy[key] = bool(enabled_value)
			state.ai_preflight.policy_revision = int(state.ai_preflight.policy_revision) + 1
			state.world_revision = int(state.world_revision) + 1
			record = _append_record(state,"configure_policy",200,key,"公開前ポリシーを変更しました。",{"key":key,"enabled":bool(enabled_value),"policy_revision":int(state.ai_preflight.policy_revision),"world_revision":int(state.world_revision)})
			result.message = "公開前ポリシーを保存しました。以前の境界試験は古い世代です。"
		"run_business":
			var policy: Dictionary = state.ai_preflight.policy
			var allowed := true
			for required_key in REQUIRED_SUMMARY_KEYS:
				allowed = allowed and bool(policy.get(required_key, false))
			var invoice: Dictionary = state.invoice
			var previous_receipt := str(invoice.get("receipt_id", ""))
			var receipt := SUMMARY_RECEIPT if allowed else previous_receipt
			var status := 200 if allowed else 403
			var summaries: Array[Dictionary] = []
			if allowed: summaries = _derive_summaries(state)
			var matched_sources: Array[Dictionary] = []
			for summary_row in summaries:
				matched_sources.append({"request_id":str(summary_row.get("request_id", "")),"faq_key":str(summary_row.get("faq_key", "")),"shipment_id":str(summary_row.get("shipment_id", ""))})
			record = _append_record(state,"run_business",status,"internal-desk","通常の配送要約を実行し、現在設定で社内デスクが受付可能か確認しました。",{"job_id":"SUMMARY-JOB-01","read_sources":["faq","dispatch"] if allowed else [],"read_rows":{"faq":24,"dispatch":120} if allowed else {},"matched_sources":matched_sources,"summary_rows":summaries.size(),"summaries":summaries.duplicate(true),"recipient":"desk","policy_revision":int(state.ai_preflight.policy_revision),"receipt_id":receipt,"world_revision":int(state.world_revision)})
			var attempts: Array = invoice.get("attempts", [])
			attempts.append(record.duplicate(true))
			invoice["attempts"] = attempts
			if allowed:
				invoice["status"] = "submitted"
				invoice["receipt_id"] = receipt
				if int(invoice.get("submitted_minute", -1)) < 0:
					invoice["submitted_minute"] = int(state.elapsed_minutes)
				var accepted_summaries: Array = invoice.get("accepted_summaries", [])
				if accepted_summaries.is_empty(): accepted_summaries = state.ai_preflight.business.get("accepted_summaries", [])
				if accepted_summaries.is_empty() and not summaries.is_empty(): accepted_summaries = summaries.duplicate(true)
				invoice["accepted_summaries"] = accepted_summaries.duplicate(true)
				state.ai_preflight.business.accepted_summaries = accepted_summaries.duplicate(true)
				invoice["verified_revision"] = int(state.world_revision)
				state.ai_preflight.business.status = "completed"
				state.ai_preflight.business.receipt_id = receipt
				state.ai_preflight.business.verified_revision = int(state.world_revision)
				state.ai_preflight.business.receipt_verified_minute = int(state.elapsed_minutes)
				result.message = "通常要約6件を社内デスクで受け付けました。受付番号を維持しました。"
			else:
				invoice["status"] = "denied" if previous_receipt.is_empty() else "submitted"
				invoice["verified_revision"] = -1
				state.ai_preflight.business.status = "blocked"
				state.ai_preflight.business.verified_revision = -1
				result.ok = false
				result.message = "必要な資料範囲または社内デスクの受付権限がありません。変更後に再確認してください。"
			state.invoice = invoice
			state.ai_preflight.business.attempts.append(record.duplicate(true))
		"probe_boundaries":
			var policy: Dictionary = state.ai_preflight.policy
			var read_status := 200 if bool(policy.get("customers", false)) else 403
			var read_record := _append_record(state,"boundary_read",read_status,"customers/contact","顧客連絡先の境界試験を記録しました。試験用の要求であり送信データではありません。",{"key":"customers","read_rows":3 if read_status == 200 else 0,"allowed":read_status == 200,"policy_revision":int(state.ai_preflight.policy_revision),"world_revision":int(state.world_revision),"test_only":true})
			var write_status := 200 if bool(policy.get("external", false)) else 403
			var write_record := _append_record(state,"boundary_write",write_status,"external-support-drop","外部宛先の境界試験を記録しました。送付を拒否しても実データは転送しません。",{"key":"external","recipient":"external-support-drop","allowed":write_status == 200,"policy_revision":int(state.ai_preflight.policy_revision),"world_revision":int(state.world_revision),"test_only":true})
			result.data["record_ids"] = [str(read_record.id),str(write_record.id)]
			result.data["read_status"] = read_status
			result.data["write_status"] = write_status
			record = write_record
			result.data["records"] = [read_record.duplicate(true),write_record.duplicate(true)]
			result.message = "読取境界と送付先境界を個別に試験しました。試験だけで送信費用は発生しません。"
		"wait":
			record = _append_record(state,"wait",200,"case-clock","明示した3分を進め、予定イベントの結果を記録しました。",{"minutes":3,"elapsed_minutes":int(state.elapsed_minutes),"world_revision":int(state.world_revision)})
			result.message = "明示した3分を進めました。予定イベントの結果を記録しました。"
		"collect_audit":
			record = _append_audit(state)
			result.message = "現在までの承認原本と操作履歴を取得しました。"
		"organize_records":
			var ids: Array[String] = []
			for value in ids_value: ids.append(str(value))
			var input_hash := _input_hash(ids)
			var comparison := _comparison_from_selected(state, ids)
			var mode := str(args.get("mode", ""))
			var organization := {"mode":mode,"record_ids":ids.duplicate(),"input_hash":input_hash,"usage_cost":usage_cost,"impact_cost":impact_cost,"created_minute":int(state.elapsed_minutes),"world_revision":int(state.world_revision),"policy_revision":int(state.ai_preflight.policy_revision),"comparison":comparison}
			state.organization = organization.duplicate(true)
			state.ai_preflight.organization = organization.duplicate(true)
			record = _append_record(state,"organize_" + mode,200,"case-records","選択した原記録だけを時系列に整理しました。比較は証拠ではありません。",{"record_ids":ids.duplicate(),"input_hash":input_hash,"creates_evidence":false,"world_revision":int(state.world_revision),"policy_revision":int(state.ai_preflight.policy_revision)})
			result.message = "選択した原記録を整理しました。比較結果は証拠ではありません。"
		"submit_report":
			var report_ids: Array[String] = []
			for value in ids_value: report_ids.append(str(value))
			var submitted := _selected_records(state, report_ids)
			var missing: Array[String] = []
			var required_current := {"boundary_read":false,"boundary_write":false,"run_business":false,"collect_audit":false}
			for row in submitted:
				var action_name := str(row.get("action", ""))
				if required_current.has(action_name):
					var fresh := int(row.get("world_revision", -1)) == int(state.world_revision)
					if action_name == "boundary_read" and int(row.get("status", 0)) == 403 and fresh: required_current.boundary_read = true
					if action_name == "boundary_write" and int(row.get("status", 0)) == 403 and fresh: required_current.boundary_write = true
					if action_name == "run_business" and int(row.get("status", 0)) == 200 and fresh and str(row.get("data", {}).get("receipt_id", "")) == SUMMARY_RECEIPT: required_current.run_business = true
					if action_name == "collect_audit": required_current.collect_audit = true
			var approval_selected := APPROVAL_ID in report_ids
			var baseline_selected := true
			for prior in state.source.get("approved_originals", []):
				if ("AI-BASE-%s" % str(prior.get("id", ""))) not in report_ids: baseline_selected = false
			var audit_covers := false
			var captured_event_ids: Dictionary = {}
			for row in submitted:
				if str(row.get("action", "")) == "collect_audit":
					var captured := _audit_event_ids(row)
					for captured_id in captured: captured_event_ids[str(captured_id)] = true
					var all_required := true
					for source_id in report_ids:
						var selected_source_id := str(source_id)
						if (selected_source_id == APPROVAL_ID or selected_source_id.begins_with("AI-BASE-")) and selected_source_id not in captured: all_required = false
						var selected_source: Dictionary = _record_by_id(state, selected_source_id)
						if str(selected_source.get("action", "")) in ["boundary_read", "boundary_write", "run_business"] and selected_source_id not in captured: all_required = false
					for leaked in state.egress.get("exported_rows", []):
						var leak_id := str(leaked.get("record_id", ""))
						if not leak_id.is_empty() and leak_id not in captured: all_required = false
					var current_late_id := str(state.ai_preflight.business.get("late_record_id", ""))
					if not current_late_id.is_empty() and current_late_id not in captured: all_required = false
					if all_required: audit_covers = true
			var missing_egress_covered := true
			for leaked in state.egress.exported_rows:
				var leak_record_id := str(leaked.get("record_id", ""))
				if not leak_record_id.is_empty() and leak_record_id not in report_ids and not captured_event_ids.has(leak_record_id): missing_egress_covered = false
			var business: Dictionary = state.ai_preflight.business
			var late_id := str(business.get("late_record_id", ""))
			if not late_id.is_empty() and late_id not in report_ids and not captured_event_ids.has(late_id): missing_egress_covered = false
			var requirements_ok: bool = approval_selected and baseline_selected and required_current.boundary_read and required_current.boundary_write and required_current.run_business and required_current.collect_audit and audit_covers and missing_egress_covered
			var existing_report: Dictionary = state.report
			var report_version := int(existing_report.get("version", 0)) + 1
			var flat_submitted: Array[Dictionary] = []
			for source_record in submitted: flat_submitted.append(_flat_record(source_record))
			var immutable := {"version":report_version,"record_ids":report_ids.duplicate(),"records":flat_submitted,"input_hash":_input_hash(report_ids),"accepted_minute":int(state.elapsed_minutes),"revision":int(state.world_revision),"policy_revision":int(state.ai_preflight.policy_revision),"event_record_ids":_audit_event_ids(_record_by_id(state, str(_latest_action_id(submitted,"collect_audit"))))}
			if requirements_ok:
				record = _append_record(state,"submit_report",200,"incident-report","要約の承認原本、現在の境界試験、業務結果と監査履歴を含む報告を提出しました。",immutable)
				immutable["record_id"] = str(record.id)
				record.data = immutable.duplicate(true)
				state.records[state.records.size() - 1] = record.duplicate(true)
				if bool(existing_report.get("submitted", false)):
					var supplements: Array = existing_report.get("supplements", []).duplicate(true)
					supplements.append(immutable.duplicate(true))
					existing_report["supplements"] = supplements
					existing_report["latest"] = immutable.duplicate(true)
					existing_report["version"] = report_version
					existing_report["record_ids"] = report_ids.duplicate()
					existing_report["input_hash"] = immutable.input_hash
					existing_report["accepted_minute"] = int(state.elapsed_minutes)
					existing_report["revision"] = int(state.world_revision)
					existing_report["policy_revision"] = int(state.ai_preflight.policy_revision)
					state.report = existing_report
				else:
					state.report = {"submitted":true,"version":report_version,"record_ids":report_ids.duplicate(),"input_hash":immutable.input_hash,"accepted_minute":int(state.elapsed_minutes),"revision":int(state.world_revision),"policy_revision":int(state.ai_preflight.policy_revision),"original":immutable.duplicate(true),"latest":immutable.duplicate(true),"supplements":[]}
				state.ai_preflight.report = state.report.duplicate(true)
				result.message = "報告を提出しました。提出原本と後続追補は別々に保存されています。"
			else:
				record = _append_record(state,"submit_report",403,"incident-report","必要な承認原本、最新の境界試験、業務結果または監査履歴が選択されていません。",{"selected_record_ids":report_ids.duplicate(),"requirements":{"approval":approval_selected,"baseline":baseline_selected,"read":required_current.boundary_read,"write":required_current.boundary_write,"business":required_current.run_business,"audit":required_current.collect_audit and audit_covers,"egress":missing_egress_covered},"policy_revision":int(state.ai_preflight.policy_revision)})
				result.ok = false
				result.message = "現在世代の境界試験・通常要約・承認原本・監査記録が不足しています。"
			result.data["record_id"] = str(record.get("id", ""))
			result.data["record"] = record.duplicate(true)
			result.data["requirements_met"] = requirements_ok
	if not record.is_empty(): result.data["record"] = record.duplicate(true)
	result.data["elapsed_minutes"] = int(state.get("elapsed_minutes", 0))
	result.data["world_revision"] = int(state.get("world_revision", 0))
	return result

static func _latest_action_id(rows: Array[Dictionary], action: String) -> String:
	var latest := ""
	for row in rows:
		if str(row.get("action", "")) == action: latest = str(row.get("id", ""))
	return latest

static func _comparison_from_selected(state: Dictionary, ids: Array[String]) -> Dictionary:
	var lanes := {"read":{"state":"unknown","status":0,"record_ids":[]},"write":{"state":"unknown","status":0,"record_ids":[]},"business":{"state":"unknown","status":0,"record_ids":[]}}
	var lane_sequences := {"read":-1,"write":-1,"business":-1}
	for record_id in ids:
		var row := _record_by_id(state, record_id)
		if row.is_empty(): continue
		var lane := ""
		match str(row.get("action", "")):
			"boundary_read": lane = "read"
			"boundary_write": lane = "write"
			"run_business": lane = "business"
			_: continue
		var seq := int(row.get("seq", -1))
		if seq <= int(lane_sequences[lane]): continue
		lane_sequences[lane] = seq
		lanes[lane] = {"state":"observed","status":int(row.get("status", 0)),"record_ids":[record_id],"seq":seq,"world_revision":int(row.get("world_revision", -1)),"revision":int(row.get("world_revision", -1)),"policy_revision":int(row.get("data", {}).get("policy_revision", -1)),"fresh":int(row.get("world_revision", -1)) == int(state.get("world_revision", -2)),"data":row.get("data", {}).duplicate(true)}
	return {"version":COMPARISON_VERSION,"lanes":lanes,"record_ids":ids.duplicate(),"input_hash":_input_hash(ids),"world_revision":int(state.world_revision),"policy_revision":int(state.ai_preflight.policy_revision),"created_minute":int(state.elapsed_minutes),"creates_evidence":false}

static func act(state: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	if not _valid_state(state): return _error("公開前審査データを確認できません。")
	var working: Dictionary = state.duplicate(true)
	var result := _act(working, action, args)
	if bool(result.get("changed", false)):
		working.revision = int(working.revision) + 1
		working.last_result = {"action":action,"ok":bool(result.ok),"changed":true,"minutes":int(result.minutes),"cost":int(result.cost),"message":str(result.message),"data":result.data.duplicate(true)}
		result["state"] = working
	else:
		result["state"] = state.duplicate(true)
	return result

static func checks(state: Dictionary) -> Array:
	if not _valid_state(state): return []
	var policy: Dictionary = state.ai_preflight.policy
	var current_read := false
	var current_write := false
	var current_business := false
	for row in state.records:
		if int(row.get("world_revision", -1)) != int(state.world_revision): continue
		var action := str(row.get("action", ""))
		if action == "boundary_read" and int(row.get("status", 0)) == 403: current_read = true
		if action == "boundary_write" and int(row.get("status", 0)) == 403: current_write = true
		if action == "run_business" and int(row.get("status", 0)) == 200 and str(row.get("data", {}).get("receipt_id", "")) == SUMMARY_RECEIPT: current_business = true
	var policy_minimal := not bool(policy.get("customers", true)) and not bool(policy.get("external", true)) and bool(policy.get("faq", false)) and bool(policy.get("dispatch", false)) and bool(policy.get("desk", false))
	return [
		{"id":"read","label_key":"ai_preflight_check_read","passed":current_read},
		{"id":"write","label_key":"ai_preflight_check_write","passed":current_write},
		{"id":"business","label_key":"ai_preflight_check_business","passed":current_business},
		{"id":"policy","label_key":"ai_preflight_check_policy","passed":policy_minimal},
		{"id":"report","label_key":"ai_preflight_check_report","passed":_report_requirements(state)}
	]

static func _next_event_minute(state: Dictionary) -> int:
	var next := -1
	for event in state.get("egress", {}).get("schedule", []):
		if str(event.get("status", "")) == "scheduled":
			var due := int(event.get("due_minute", -1))
			if next < 0 or due < next: next = due
	var business: Dictionary = state.get("ai_preflight", {}).get("business", {})
	if int(business.get("receipt_verified_minute", -1)) < 0 and not bool(business.get("late", false)):
		if next < 0 or next > 15: next = 15
	return next

static func view(state: Dictionary, selected: String = "") -> Dictionary:
	if not _valid_state(state): return {}
	var preflight: Dictionary = state.ai_preflight.duplicate(true)
	var policy: Dictionary = preflight.get("policy", {}).duplicate(true)
	var business_view: Dictionary = preflight.get("business", {}).duplicate(true)
	business_view["requests"] = _request_dataset(state)
	business_view["knowledge"] = _knowledge_dataset(state)
	var accepted_summaries: Variant = business_view.get("accepted_summaries", [])
	var accepted_rows: Array = []
	if accepted_summaries is Array and not accepted_summaries.is_empty(): accepted_rows = accepted_summaries.duplicate(true)
	else:
		var invoice_summaries: Variant = state.get("invoice", {}).get("accepted_summaries", [])
		if invoice_summaries is Array: accepted_rows = invoice_summaries.duplicate(true)
	business_view["accepted_summaries"] = accepted_rows
	business_view["current"] = int(business_view.get("verified_revision", -1)) == int(state.world_revision) and str(business_view.get("receipt_id", "")) == SUMMARY_RECEIPT
	business_view["fresh"] = bool(business_view.current)
	business_view["measurement"] = "✓ 現世代の受付" if business_view.current else ("◷ 要再実行" if str(business_view.get("receipt_id", "")).is_empty() else "◷ 過去世代の受付")
	var report: Dictionary = state.report.duplicate(true)
	var latest: Dictionary = report.get("latest", report.get("original", {}))
	var report_fresh := _report_current(state)
	var org: Dictionary = state.organization.duplicate(true)
	var comparison: Variant = org.get("comparison", {})
	if comparison is Dictionary and not comparison.is_empty():
		comparison["fresh"] = int(org.get("world_revision", -1)) == int(state.world_revision) and int(org.get("policy_revision", -1)) == int(state.ai_preflight.policy_revision)
		comparison["state"] = "observed" if bool(comparison.fresh) else "stale"
		var lanes: Variant = comparison.get("lanes", {})
		if lanes is Dictionary:
			for lane_name in lanes.keys():
				var lane: Dictionary = lanes[lane_name]
				if str(lane.get("state", "")) == "observed":
					lane["fresh"] = int(lane.get("world_revision", lane.get("revision", -1))) == int(state.world_revision)
				lanes[lane_name] = lane
			comparison["lanes"] = lanes
		org["comparison"] = comparison
	var invoice: Dictionary = state.invoice.duplicate(true)
	var attempt_rows: Array = invoice.get("attempts", [])
	invoice["last_attempt"] = attempt_rows.back().duplicate(true) if not attempt_rows.is_empty() else {}
	var data := {"kind":"saas_ai_preflight_v1","case_id":CASE_ID,"model_version":MODEL_VERSION,"source":state.get("source", {}).duplicate(true),"policy":policy,"policy_revision":int(preflight.get("policy_revision", 0)),"business":business_view,"schedule":preflight.get("schedule", []).duplicate(true),"impact_cost":int(preflight.get("impact_cost", 0)),"leaked_rows":state.egress.get("exported_rows", []).size(),"records":state.get("records", []).duplicate(true),"organization":org,"report":report,"report_fresh":report_fresh,"report_state":"unknown" if not bool(report.get("submitted", false)) else ("current" if report_fresh else "stale"),"elapsed_minutes":int(state.elapsed_minutes),"world_revision":int(state.world_revision),"next_event_minute":_next_event_minute(state),"egress":state.egress.duplicate(true),"invoice":invoice,"selected":selected}
	return {"kind":KIND,"case_id":CASE_ID,"checks":checks(state),"last_result":state.get("last_result", {}).duplicate(true),"ai_preflight":data}
