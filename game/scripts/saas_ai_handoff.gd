extends RefCounted
## Independent offline partner handoff. Views only project saved originals.
const FLOW = preload("res://scripts/ai_incident_projection.gd")
const CASE_ID := "advanced-saas-ai-handoff"
const MODEL_VERSION := "saas-ai-handoff-v1"
const KIND := "advanced-saas-response"
const CLIENT := "北斗物流"
const APPROVAL_ID := "AI-401"
const RECEIPT_ID := "RCPT-MINATO-001"
const RECIPIENT := "minato/dispatch"
const ARCHIVE := "minato/archive"
const POLICY_KEYS := ["dispatch", "contacts", "partner_dispatch", "partner_archive"]
const SHIPMENTS := [
	{"id":"SHP-051","label":"湾岸便 051","contact_id":"CT-051","status_detail":"道路規制による遅延","eta":"15:30","instruction":"到着前に荷受窓口へ連絡"},
	{"id":"SHP-052","label":"中央便 052","contact_id":"CT-052","status_detail":"受取窓口の変更","eta":"16:00","instruction":"東側の荷受口へ案内"},
	{"id":"SHP-053","label":"丘陵便 053","contact_id":"CT-053","status_detail":"再配達の調整","eta":"17:00","instruction":"担当窓口へ再配達時刻を連絡"}
]
const CONTACTS := [
	{"id":"CT-051","shipment_id":"SHP-051","name":"みどり商店 荷受窓口","channel":"みどり商店 配送連絡室"},
	{"id":"CT-052","shipment_id":"SHP-052","name":"白浜工房 東側受付","channel":"白浜工房 配送連絡室"},
	{"id":"CT-053","shipment_id":"SHP-053","name":"高原図書室 配送担当","channel":"高原図書室 配送連絡室"},
	{"id":"CT-091","shipment_id":"SHP-091","name":"若葉書店 荷受窓口","channel":"若葉書店 配送連絡室"},
	{"id":"CT-092","shipment_id":"SHP-092","name":"北坂食堂 仕入担当","channel":"北坂食堂 配送連絡室"},
	{"id":"CT-093","shipment_id":"SHP-093","name":"川辺文具 配送担当","channel":"川辺文具 配送連絡室"}
]

static func _result(ok: bool, changed: bool, minutes: int, usage: int, impact: int, message: String, data: Dictionary = {}) -> Dictionary:
	var details := data.duplicate(true)
	details["usage_cost"] = usage; details["impact_cost"] = impact
	return {"ok":ok,"changed":changed,"observed":changed,"minutes":minutes,"cost":usage + impact,"usage_cost":usage,"impact_cost":impact,"message":message,"data":details}

static func _error(message: String) -> Dictionary:
	return _result(false, false, 0, 0, 0, message)

static func _whole(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0 and float(value) == floorf(float(value))

static func _record(s: Dictionary, operation: String, status: int, target: String, detail: String, data: Dictionary = {}, minute: int = -1) -> Dictionary:
	s.sequence = int(s.sequence) + 1
	var body := data.duplicate(true); body["policy_revision"] = int(s.handoff.policy_revision)
	var row := {"id":"HANDOFF-REC-%03d" % int(s.sequence),"seq":int(s.sequence),"minute":int(s.elapsed_minutes) if minute < 0 else minute,"actor":"analyst","app":"partner-handoff","destination":target,"action":operation,"status":status,"detail":detail,"revision":int(s.world_revision),"world_revision":int(s.world_revision),"data":body}
	s.records.append(row)
	return row

static func _jobs(shipments: Array, contacts: Array) -> Array:
	var jobs: Array = []
	for shipment in shipments:
		for contact in contacts:
			if str(contact.get("id", "")) != str(shipment.get("contact_id", "")): continue
			jobs.append({"id":"HANDOFF-" + str(shipment.id),"shipment_id":str(shipment.id),"shipment_label":str(shipment.label),"contact_id":str(contact.id),"contact_name":str(contact.name),"contact_channel":str(contact.channel),"status_detail":str(shipment.status_detail),"eta":str(shipment.eta),"instruction":str(shipment.instruction),"recipient":RECIPIENT,"receipt_id":"","status":"pending"})
	return jobs

static func create(case_id: String = CASE_ID) -> Dictionary:
	if case_id not in ["", CASE_ID]: return {}
	var shipments: Array = SHIPMENTS.duplicate(true); var contacts: Array = CONTACTS.duplicate(true)
	var linked: Array = contacts.slice(0, 3)
	var business := {"jobs":_jobs(shipments, linked),"approved_dataset":{"shipments":shipments,"contacts":linked,"recipient":RECIPIENT},"all_contacts":contacts,"accepted_jobs":[],"receipt_id":"","verified_revision":-1,"received_minute":-1,"receipt_verified_minute":-1,"deadline_minute":12,"summary_rows":3,"status":"pending","attempts":[],"late":false,"loss_cost":0,"late_record_id":""}
	var s := {"kind":KIND,"case_id":CASE_ID,"model_version":MODEL_VERSION,"revision":0,"world_revision":0,"elapsed_minutes":0,"sequence":0,"records":[],"audit":[],"handoff":{"source":{},"policy":{"dispatch":true,"contacts":"all","partner_dispatch":false,"partner_archive":true},"policy_revision":0,"business":business},"egress":{"schedule":[],"exported_rows":[],"impact_cost":0},"invoice":{"id":"HANDOFF-001","amount":0,"customer":"ミナト配送","status":"pending","receipt_id":"","accepted_jobs":[],"submitted_minute":-1,"verified_revision":-1,"attempts":[]},"report":{"submitted":false,"version":0,"original":{},"latest":{},"supplements":[]},"organization":{},"last_result":{}}
	var approval := _record(s,"consent_review",200,RECIPIENT,"AI-401: 障害対象3便の配送進捗と連絡先をミナト配送 /dispatch へ送付。/archive と他の便の連絡先は対象外。",{"approved_change":APPROVAL_ID,"approved_sources":["dispatch","contacts"],"contacts_scope":"linked","approved_shipment_ids":["SHP-051","SHP-052","SHP-053"],"approved_contact_ids":["CT-051","CT-052","CT-053"],"approved_recipient":RECIPIENT,"excluded_recipient":ARCHIVE,"partner":"ミナト配送"})
	approval.id = APPROVAL_ID; s.records[0] = approval; s.audit.append(approval.duplicate(true))
	for due in [8, 16]: s.egress.schedule.append({"id":"HANDOFF-SYNC-%02d" % (1 if due == 8 else 2),"due_minute":due,"status":"scheduled","read_status":0,"write_status":0,"row_count":0,"record_ids":[]})
	return s

static func _valid_source(payload: Dictionary) -> bool:
	if str(payload.get("source_contract_id", "")).is_empty() or not _whole(payload.get("source_day", -1)) or int(payload.source_day) < 1 or str(payload.get("client", "")) != CLIENT: return false
	var originals: Variant = payload.get("approved_originals", null)
	if not originals is Array or originals.size() != 3 or not payload.get("prior_result", {}) is Dictionary: return false
	var found := {}; var ids := {}
	for row in originals:
		if not row is Dictionary or not row.get("data", null) is Dictionary or int(row.get("status", 0)) != 200: return false
		var id := str(row.get("id", "")); var operation := str(row.get("action", ""))
		if id.is_empty() or ids.has(id) or found.has(operation) or operation not in ["consent_review", "run_business", "submit_report"]: return false
		if operation == "consent_review" and id != "AI-301": return false
		if operation == "run_business" and str(row.data.get("receipt_id", "")).is_empty(): return false
		found[operation] = true; ids[id] = true
	return found.size() == 3

static func create_followup(payload: Dictionary) -> Dictionary:
	if not _valid_source(payload): return {}
	var s := create()
	s.handoff.source = payload.duplicate(true)
	for original in payload.approved_originals:
		var row := _record(s,"baseline_reference",200,"prior-case/" + str(payload.source_contract_id),"前回の承認・正常受付・提出報告の凍結原本。今回の実測ではありません。",{"source_contract_id":str(payload.source_contract_id),"source_day":int(payload.source_day),"source_record_id":str(original.id),"original":original.duplicate(true)})
		row.id = "HANDOFF-BASE-" + str(original.id); s.records[-1] = row; s.audit.append(row.duplicate(true))
	return s

static func _valid(s: Dictionary) -> bool:
	if str(s.get("case_id", "")) != CASE_ID or str(s.get("model_version", "")) != MODEL_VERSION or str(s.get("kind", "")) != KIND: return false
	for key in ["revision","world_revision","elapsed_minutes","sequence"]:
		if not _whole(s.get(key, null)): return false
	for key in ["handoff","egress","invoice","report","organization"]:
		if not s.get(key, null) is Dictionary: return false
	if not s.get("records", null) is Array or not s.get("audit", null) is Array: return false
	var h: Dictionary = s.handoff
	if not h.get("source", null) is Dictionary or (not h.source.is_empty() and not _valid_source(h.source)): return false
	if not h.get("policy", null) is Dictionary or not h.get("business", null) is Dictionary or not _whole(h.get("policy_revision", null)): return false
	if str(h.policy.get("contacts", "")) not in ["off","linked","all"]: return false
	for key in ["dispatch","partner_dispatch","partner_archive"]:
		if not h.policy.get(key, null) is bool: return false
	for key in ["jobs","accepted_jobs","attempts","all_contacts"]:
		if not h.business.get(key, null) is Array: return false
	return h.business.get("approved_dataset", null) is Dictionary and _whole(h.business.get("loss_cost", null)) and h.business.get("late", null) is bool and s.egress.get("schedule", null) is Array and s.egress.get("exported_rows", null) is Array and s.invoice.get("attempts", null) is Array and s.report.get("supplements", null) is Array

static func _contacts(s: Dictionary) -> Array:
	match str(s.handoff.policy.contacts):
		"linked": return s.handoff.business.approved_dataset.contacts.duplicate(true)
		"all": return s.handoff.business.all_contacts.duplicate(true)
	return []

static func advance(s: Dictionary, minutes: int) -> int:
	if not _valid(s) or minutes <= 0: return 0
	var finish := int(s.elapsed_minutes) + minutes; var milestones: Array = []
	for event in s.egress.schedule:
		if str(event.status) == "scheduled" and int(event.due_minute) > int(s.elapsed_minutes) and int(event.due_minute) <= finish: milestones.append({"minute":int(event.due_minute),"event":event})
	if not bool(s.handoff.business.late) and str(s.invoice.receipt_id).is_empty() and int(s.elapsed_minutes) <= 12 and finish > 12: milestones.append({"minute":13})
	milestones.sort_custom(func(a, b): return int(a.minute) < int(b.minute))
	var impact := 0
	for milestone in milestones:
		var minute := int(milestone.minute)
		if not milestone.has("event"):
			s.handoff.business.late = true; s.handoff.business.loss_cost = int(s.handoff.business.loss_cost) + 900; impact += 900
			var late := _record(s,"summary_overdue",429,RECIPIENT,"3便の連絡受付が12分の期限を超えました。補償は復旧後も残ります。",{"deadline_minute":12,"loss_amount":900},minute)
			s.handoff.business.late_record_id = str(late.id)
			continue
		var event: Dictionary = milestone.event; var contacts := _contacts(s)
		var read_status := 403 if contacts.is_empty() else 200
		var send_allowed := bool(s.handoff.policy.partner_archive) and not contacts.is_empty()
		var rows := contacts.size() if send_allowed else 0
		var ids: Array = []
		for contact in contacts: ids.append(str(contact.id))
		var read := _record(s,"scheduled_customer_read",read_status,"contacts","予定された連絡先参照の実結果です。",{"schedule_id":str(event.id),"contacts_scope":str(s.handoff.policy.contacts),"contact_ids":ids,"read_rows":contacts.size()},minute)
		var write := _record(s,"scheduled_external_write",200 if send_allowed else 403,ARCHIVE,"ミナト配送 /archive への実送付結果です。承認済み /dispatch の受付ではありません。",{"schedule_id":str(event.id),"row_count":rows,"contact_ids":ids if send_allowed else [],"recipient_allowed":bool(s.handoff.policy.partner_archive),"blocked_reason":"contact-read-denied" if contacts.is_empty() else "recipient-policy" if not send_allowed else ""},minute)
		if send_allowed:
			for contact in contacts: s.egress.exported_rows.append({"id":str(event.id) + "-" + str(contact.id),"contact_id":str(contact.id),"shipment_id":str(contact.shipment_id),"schedule_id":str(event.id),"minute":minute,"record_id":str(write.id),"data_class":"delivery-contact","cost":500})
			impact += rows * 500; s.egress.impact_cost = int(s.egress.impact_cost) + rows * 500
		event.status = "completed" if send_allowed else "blocked"; event.read_status = read_status; event.write_status = int(write.status); event.row_count = rows; event.record_ids = [str(read.id),str(write.id)]
	s.elapsed_minutes = finish
	return impact

static func _find(s: Dictionary, id: String) -> Dictionary:
	for row in s.records:
		if str(row.get("id", "")) == id: return row
	return {}

static func _latest(s: Dictionary, operation: String) -> Dictionary:
	var found: Dictionary = {}
	for row in s.records:
		if str(row.get("action", "")) == operation and (found.is_empty() or int(row.get("seq", -1)) > int(found.get("seq", -1))): found = row
	return found

static func _flat(row: Dictionary) -> Dictionary:
	var copy := row.duplicate(false); var data: Dictionary = row.get("data", {}).duplicate(false)
	data.erase("events"); data.erase("records"); copy["data"] = data.duplicate(true)
	return copy

static func _ids(s: Dictionary, value: Variant) -> Array:
	if not value is Array or value.is_empty() or value.size() > 32: return []
	var ids: Array = []
	for id in value:
		if not id is String or id.is_empty() or id in ids or _find(s,id).is_empty(): return []
		ids.append(id)
	return ids

static func _input_hash(ids: Array) -> String:
	var sorted := ids.duplicate(); sorted.sort()
	return "|".join(sorted)

static func _proofs(s: Dictionary) -> Dictionary:
	var proofs := {}
	for operation in ["boundary_read","boundary_write","run_business"]:
		var row := _latest(s, operation)
		var valid: bool = int(row.get("world_revision", -1)) == int(s.world_revision) and int(row.get("status", 0)) == (200 if operation == "run_business" else 403)
		if operation == "run_business": valid = valid and str(row.get("data", {}).get("receipt_id", "")) == RECEIPT_ID and row.get("data", {}).get("jobs", []).size() == 3
		proofs[operation] = str(row.get("id", "")) if valid else ""
	return proofs

static func _required(s: Dictionary) -> Array:
	var ids: Array = [APPROVAL_ID]
	for row in s.records:
		if str(row.get("action", "")) == "baseline_reference": ids.append(str(row.id))
	for id in _proofs(s).values():
		if not str(id).is_empty(): ids.append(id)
	var audit := _latest(s,"collect_audit")
	if not audit.is_empty(): ids.append(str(audit.id))
	return ids

static func _report_valid(s: Dictionary, ids: Array) -> bool:
	var proofs := _proofs(s)
	if proofs.values().any(func(id): return str(id).is_empty()): return false
	var required := _required(s)
	if not required.all(func(id): return id in ids): return false
	var audit := _latest(s,"collect_audit")
	if audit.is_empty() or int(audit.get("world_revision", -1)) != int(s.world_revision): return false
	var captured: Array = audit.get("data", {}).get("event_record_ids", [])
	for id in required:
		if id != str(audit.id) and id not in captured: return false
	for copy in s.egress.exported_rows:
		if str(copy.get("record_id", "")) not in captured: return false
	var late_id := str(s.handoff.business.get("late_record_id", ""))
	return late_id.is_empty() or late_id in captured

static func _report_fresh(s: Dictionary) -> bool:
	var latest: Dictionary = s.report.get("latest", {})
	if not bool(s.report.get("submitted", false)) or int(latest.get("world_revision", -1)) != int(s.world_revision): return false
	var captured: Array = latest.get("event_record_ids", [])
	for copy in s.egress.exported_rows:
		if str(copy.get("record_id", "")) not in captured: return false
	var late_id := str(s.handoff.business.get("late_record_id", ""))
	return late_id.is_empty() or late_id in captured

static func _comparison(s: Dictionary, ids: Array) -> Dictionary:
	var lanes := {"read":{"state":"unknown","status":0,"record_ids":[]},"write":{"state":"unknown","status":0,"record_ids":[]},"business":{"state":"unknown","status":0,"record_ids":[]}}
	for id in ids:
		var row := _find(s,str(id)); var lane := str({"boundary_read":"read","boundary_write":"write","run_business":"business"}.get(str(row.get("action", "")), ""))
		if lane.is_empty() or int(row.get("seq", -1)) <= int(lanes[lane].get("seq", -1)): continue
		lanes[lane] = {"state":"observed","status":int(row.status),"record_ids":[id],"seq":int(row.seq),"world_revision":int(row.world_revision),"policy_revision":int(row.data.get("policy_revision", -1)),"data":row.data.duplicate(true)}
	return {"lanes":lanes,"record_ids":ids.duplicate(),"world_revision":int(s.world_revision),"created_minute":int(s.elapsed_minutes),"creates_evidence":false}

static func act(state: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	if not _valid(state): return _error("配送連携の案件データを確認できません。")
	var s := state.duplicate(true); var minutes := 0; var usage := 0; var ids: Array = []
	var key := str(args.get("key", "")); var value: Variant = args.get("value") if key == "contacts" else args.get("enabled")
	match action:
		"configure":
			if key not in POLICY_KEYS or (key == "contacts" and (not value is String or value not in ["off","linked","all"])) or (key != "contacts" and not value is bool): return _error("変更する範囲と設定値を確認してください。")
			if s.handoff.policy[key] == value: return _unchanged(state, "設定はすでにその状態です。")
			minutes = 1
		"run_business":
			if str(s.invoice.receipt_id) == RECEIPT_ID and int(s.invoice.verified_revision) == int(s.world_revision): return _unchanged(state, "現在設定で3便の受付を確認済みです。",{"receipt_id":RECEIPT_ID,"duplicate":true})
			minutes = 2
		"probe_boundaries", "collect_audit": minutes = 2
		"wait": minutes = 3
		"organize_records", "submit_report":
			ids = _ids(s,args.get("record_ids", null))
			if ids.is_empty(): return _error("取得済みの原記録を重複なく32件以内で選択してください。")
			minutes = 2
			if action == "organize_records":
				var mode := str(args.get("mode", ""))
				if mode not in ["manual","assistant"]: return _error("手動または助手を選択してください。")
				if str(s.organization.get("mode", "")) == mode and str(s.organization.get("input_hash", "")) == _input_hash(ids): return _unchanged(state,"同じ原記録の保存済み整理を再表示します。")
				minutes = 5 if mode == "manual" else 2; usage = 300 if mode == "assistant" else 0
		_: return _error("この配送連携で使える操作を選択してください。")
	var impact := advance(s, minutes)
	var result := _result(true,true,minutes,usage,impact,"操作を記録しました。")
	var record: Dictionary = {}
	match action:
		"configure":
			s.handoff.policy[key] = value; s.handoff.policy_revision = int(s.handoff.policy_revision) + 1; s.world_revision = int(s.world_revision) + 1
			record = _record(s,"configure_policy",200,key,"配送連携の権限を適用しました。以前の実測とは設定世代が異なります。",{"key":key,"value":value})
		"probe_boundaries":
			var read_status := 200 if str(s.handoff.policy.contacts) == "all" else 403
			var read := _record(s,"boundary_read",read_status,"contacts/unrelated","当該3便と無関係な連絡先3件へのダミー要求です。",{"read_rows":3 if read_status == 200 else 0,"test_only":true,"contacts_scope":str(s.handoff.policy.contacts)})
			var write_status := 200 if bool(s.handoff.policy.partner_archive) else 403
			record = _record(s,"boundary_write",write_status,ARCHIVE,"同じ配送会社の承認対象外 /archive へのダミー要求です。",{"test_only":true,"recipient":ARCHIVE})
			result.data.merge({"records":[read.duplicate(true),record.duplicate(true)],"record_ids":[str(read.id),str(record.id)],"read_status":read_status,"write_status":write_status})
		"run_business":
			var allowed: bool = bool(s.handoff.policy.dispatch) and str(s.handoff.policy.contacts) != "off" and bool(s.handoff.policy.partner_dispatch)
			var jobs: Array = _jobs(s.handoff.business.approved_dataset.shipments,s.handoff.business.approved_dataset.contacts) if allowed else []
			for job in jobs: job.status = "received"; job.receipt_id = "MN-" + str(job.shipment_id).trim_prefix("SHP-")
			record = _record(s,"run_business",200 if allowed else 403,RECIPIENT,"承認された /dispatch での3便受付結果です。",{"jobs":jobs.duplicate(true),"summary_rows":jobs.size(),"receipt_id":RECEIPT_ID if allowed else str(s.invoice.receipt_id),"recipient":RECIPIENT,"contacts_scope":str(s.handoff.policy.contacts),"shipment_ids":jobs.map(func(job): return str(job.shipment_id))})
			s.invoice.attempts.append(record.duplicate(true)); s.handoff.business.attempts.append(record.duplicate(true))
			if allowed:
				if str(s.invoice.receipt_id).is_empty():
					s.invoice.receipt_id = RECEIPT_ID; s.invoice.submitted_minute = int(s.elapsed_minutes); s.invoice.accepted_jobs = jobs.duplicate(true)
					s.handoff.business.receipt_id = RECEIPT_ID; s.handoff.business.received_minute = int(s.elapsed_minutes); s.handoff.business.receipt_verified_minute = int(s.elapsed_minutes); s.handoff.business.accepted_jobs = jobs.duplicate(true); s.handoff.business.jobs = jobs.duplicate(true)
				s.invoice.status = "submitted"; s.invoice.verified_revision = int(s.world_revision); s.handoff.business.verified_revision = int(s.world_revision); s.handoff.business.status = "completed"
				result.message = "ミナト配送 /dispatch が3便を受け付けました。受付控えを保存しました。"
			else:
				s.invoice.verified_revision = -1; s.handoff.business.verified_revision = -1; s.handoff.business.status = "blocked"
				result.ok = false; result.message = "必要な配送進捗・連絡先または /dispatch の許可がなく、受付できません。"
		"wait": record = _record(s,"wait",200,"case-clock","入力待ちの3分が経過しました。",{"minutes":3})
		"collect_audit":
			var events: Array = []; var event_ids: Array = []
			for row in s.records: events.append(_flat(row)); event_ids.append(str(row.id))
			record = _record(s,"collect_audit",200,"audit-log","承認原本・測定と流出・遅延の履歴を取得しました。",{"event_record_ids":event_ids,"events":events})
		"organize_records":
			s.organization = {"mode":str(args.mode),"record_ids":ids.duplicate(),"input_hash":_input_hash(ids),"created_minute":int(s.elapsed_minutes),"world_revision":int(s.world_revision),"usage_cost":usage,"comparison":_comparison(s,ids)}
			record = _record(s,"organize_" + str(args.mode),200,"case-records","選択原記録だけを整理しました。整理結果は測定証拠ではありません。",{"record_ids":ids.duplicate(),"creates_evidence":false})
		"submit_report":
			if _report_valid(s,ids):
				var originals: Array = []
				for id in ids: originals.append(_flat(_find(s,str(id))))
				var version := int(s.report.get("version", 0)) + 1
				var original := {"version":version,"record_ids":ids.duplicate(),"records":originals,"event_record_ids":_latest(s,"collect_audit").data.event_record_ids.duplicate(),"world_revision":int(s.world_revision),"revision":int(s.world_revision),"policy_revision":int(s.handoff.policy_revision),"accepted_minute":int(s.elapsed_minutes),"input_hash":_input_hash(ids)}
				record = _record(s,"submit_report",200,"incident-report","現在設定の境界試験・3便受付と損失を報告しました。",original)
				original.record_id = str(record.id)
				if not bool(s.report.submitted): s.report.original = original.duplicate(true)
				else: s.report.supplements.append(original.duplicate(true))
				s.report.submitted = true; s.report.version = version; s.report.latest = original.duplicate(true); s.report.record_ids = ids.duplicate(); s.report.input_hash = _input_hash(ids)
				result.message = "提出原本を保存しました。後の変更や損失は追補で報告できます。"
			else:
				record = _record(s,"submit_report",403,"incident-report","現在の実測・承認原本または損失を含む監査が不足しています。",{"selected_record_ids":ids.duplicate()})
				result.ok = false; result.message = "現在世代の試験2件・3便の受付・前回原本と、最新損失を含む監査を選択してください。"
	result.data.record = record.duplicate(true); result.data.record_id = str(record.get("id", "")); result.data.elapsed_minutes = int(s.elapsed_minutes); result.data.world_revision = int(s.world_revision)
	s.revision = int(s.revision) + 1
	s.last_result = {"action":action,"ok":bool(result.ok),"changed":true,"minutes":minutes,"cost":int(result.cost),"message":str(result.message),"data":result.data.duplicate(true)}
	result.state = s
	return result

static func _unchanged(s: Dictionary, message: String, data: Dictionary = {}) -> Dictionary:
	var result := _result(true,false,0,0,0,message,data); result.state = s.duplicate(true)
	return result

static func checks(s: Dictionary) -> Array:
	if not _valid(s): return []
	var proofs := _proofs(s); var p: Dictionary = s.handoff.policy
	var passed := [not str(proofs.boundary_read).is_empty(),not str(proofs.boundary_write).is_empty(),not str(proofs.run_business).is_empty(),bool(p.dispatch) and str(p.contacts) == "linked" and bool(p.partner_dispatch) and not bool(p.partner_archive),_report_fresh(s)]
	var names := [["read","不要な連絡先の参照を拒否"],["write","対象外 /archive への送付を拒否"],["business","対象3便を /dispatch で受付"],["policy","承認された最小範囲を適用"],["report","現在の実測と損失を報告"]]
	var rows: Array = []
	for index in names.size(): rows.append({"id":names[index][0],"label":names[index][1],"label_key":"ai_handoff_check_" + str(names[index][0]),"passed":passed[index]})
	return rows

static func view(s: Dictionary, selected: String = "") -> Dictionary:
	if not _valid(s): return {}
	var h: Dictionary = s.handoff.duplicate(true)
	h.business.current = int(h.business.verified_revision) == int(s.world_revision) and str(h.business.receipt_id) == RECEIPT_ID
	h.business.last_attempt = s.invoice.attempts.back().duplicate(true) if not s.invoice.attempts.is_empty() else {}
	h.records = s.records.duplicate(true); h.report = s.report.duplicate(true); h.report.required_record_ids = _required(s); h.report_fresh = _report_fresh(s)
	h.organization = s.organization.duplicate(true)
	if not h.organization.is_empty():
		h.organization.comparison.fresh = int(h.organization.world_revision) == int(s.world_revision); h.organization.comparison.state = "observed" if bool(h.organization.comparison.fresh) else "stale"
		for lane in h.organization.comparison.lanes.values(): lane.fresh = int(lane.get("world_revision", -1)) == int(s.world_revision)
	h.elapsed_minutes = int(s.elapsed_minutes); h.world_revision = int(s.world_revision); h.egress = s.egress.duplicate(true); h.invoice = s.invoice.duplicate(true); h.schedule = s.egress.schedule.duplicate(true); h.leaked_rows = s.egress.exported_rows.size(); h.impact_cost = int(s.egress.impact_cost); h.selected = selected
	var projection_input := s.duplicate(false); projection_input.ai_preflight = s.handoff
	h.flow = FLOW.build(projection_input)
	var next := -1
	for event in s.egress.schedule:
		if str(event.status) == "scheduled" and (next < 0 or int(event.due_minute) < next): next = int(event.due_minute)
	if str(s.invoice.receipt_id).is_empty() and not bool(s.handoff.business.late) and (next < 0 or next > 13): next = 13
	h.next_event_minute = next
	return {"kind":KIND,"case_id":CASE_ID,"checks":checks(s),"last_result":s.last_result.duplicate(true),"handoff":h}
