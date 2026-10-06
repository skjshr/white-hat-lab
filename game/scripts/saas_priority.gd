extends RefCounted
## Offline recurring response. Saved approvals, queue clocks and receipts belong
## to this engagement; views never perform work or replace earlier evidence.
const CASE_ID := "advanced-saas-priority"
const MODEL_VERSION := "saas-priority-v1"
const KIND := "advanced-saas-response"
const CLIENT := "北斗物流"
const RECIPIENTS := ["minato/dispatch","minato/claims","minato/archive"]

static func _result(ok: bool, changed: bool, minutes: int, usage: int, impact: int, message: String) -> Dictionary:
	return {"ok":ok,"changed":changed,"observed":changed,"minutes":minutes,"cost":usage + impact,"usage_cost":usage,"impact_cost":impact,"message":message,"data":{}}

static func _error(message: String) -> Dictionary:
	return _result(false,false,0,0,0,message)

static func _unchanged(s: Dictionary, message: String) -> Dictionary:
	var result := _result(true,false,0,0,0,message); result.state = s.duplicate(true)
	return result

static func _whole(value: Variant, minimum: int = 0) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) == floorf(float(value))

static func _record(s: Dictionary, action: String, status: int, destination: String, detail: String, data: Dictionary = {}, minute: int = -1) -> Dictionary:
	s.sequence = int(s.sequence) + 1
	var row := {"id":"PRIORITY-REC-%03d" % int(s.sequence),"seq":int(s.sequence),"minute":int(s.elapsed_minutes) if minute < 0 else minute,"actor":"analyst","app":"priority-response","action":action,"status":status,"destination":destination,"detail":detail,"world_revision":int(s.world_revision),"revision":int(s.world_revision),"data":data.duplicate(true)}
	s.records.append(row)
	return row

static func _queue(s: Dictionary, id: String) -> Dictionary:
	for row in s.priority.queues:
		if str(row.id) == id: return row
	return {}

static func _make_queue(id: String, round_number: int) -> Dictionary:
	var dispatch := id == "dispatch"
	var urgent := dispatch == (round_number % 2 == 0)
	var recipient := "minato/dispatch" if dispatch else "minato/claims" if round_number % 2 == 1 else "minato/archive"
	var items: Array = []
	if dispatch:
		for index in 3:
			items.append({"id":"SHP-%02d-%03d" % [round_number,51 + index],"label":["湾岸便の遅延連絡","中央便の受取口変更","丘陵便の再配達連絡"][index],"detail":["道路規制 / 荷受窓口へ到着時刻を連絡","東側荷受口へ配送指示を変更","再配達予定を担当者へ連絡"][index],"contact_id":"CT-%02d-%03d" % [round_number,51 + index],"contact_name":["みどり商店 荷受窓口","白浜工房 東側受付","高原図書室 配送担当"][index],"status":"pending","receipt_id":""})
	else:
		for index in 2:
			items.append({"id":"REF-%02d-%03d" % [round_number,21 + index],"label":["みどり商店の送料返金","白浜工房の重複請求照合"][index],"detail":["遅延配送の送料と承認番号を照合","同一配送の二重請求分を照合"][index],"amount":[1800,3200][index],"status":"pending","receipt_id":""})
	var extras: Array = []
	for index in 3: extras.append({"id":"EXTRA-%s-%02d-%d" % [id,round_number,index + 1],"label":"対象外の配送連絡先" if dispatch else "対象外の返金記録"})
	return {"id":id,"label":"配送連絡" if dispatch else "返金照合","approval_id":"AP-DISPATCH" if dispatch else "AP-CLAIMS","items":items,"extra_items":extras,"all_count":6 if dispatch else 5,"approved_count":items.size(),"approved_recipient":recipient,"deadline_minute":6 if urgent else 14,"late_cost":4500 if urgent else 900,"late":false,"loss_cost":0,"late_record_id":"","policy":{"scope":"all","recipient":"minato/dispatch"},"policy_revision":0,"receipt_id":"","received_minute":-1,"verified_revision":-1,"attempts":[],"last_attempt":{}}

static func _create(round_number: int) -> Dictionary:
	var s := {"kind":KIND,"case_id":CASE_ID,"model_version":MODEL_VERSION,"revision":0,"world_revision":0,"elapsed_minutes":0,"sequence":0,"records":[],"audit":[],"invoice":{},"organization":{},"report":{"submitted":false,"version":0,"original":{},"latest":{},"supplements":[]},"last_result":{},"egress":{"exported_rows":[],"impact_cost":0},"priority":{"source":{},"round":round_number,"queues":[_make_queue("dispatch",round_number),_make_queue("claims",round_number)],"background":{"enabled":true,"recipient":"minato/shared","row_count":6,"policy_revision":0,"schedule":[],"last_attempt":{}}}}
	for q in s.priority.queues:
		var approval := _record(s,"consent_review",200,str(q.approved_recipient),"%s: 対象%d件を %s へ%d分以内に受付。全名簿と他の送付口は対象外。" % [str(q.label),int(q.approved_count),str(q.approved_recipient),int(q.deadline_minute)],{"queue_id":str(q.id),"approved_sources":["shipment-status","linked-contacts"] if str(q.id) == "dispatch" else ["refund-requests","payment-ledger"],"approved_count":int(q.approved_count),"approved_ids":q.items.map(func(item): return str(item.id)),"approved_recipient":str(q.approved_recipient),"deadline_minute":int(q.deadline_minute),"late_cost":int(q.late_cost)})
		approval.id = str(q.approval_id); s.audit.append(approval.duplicate(true))
	for due in [8,16]: s.priority.background.schedule.append({"id":"PRIORITY-SYNC-%d" % due,"due_minute":due,"status":"scheduled","status_code":0,"rows":0,"record_id":""})
	return s

static func create(case_id: String = CASE_ID) -> Dictionary:
	return _create(1) if case_id in ["",CASE_ID] else {}

static func _valid_source(payload: Dictionary) -> bool:
	if str(payload.get("source_contract_id", "")).is_empty() or not _whole(payload.get("source_day"),1) or not _whole(payload.get("round"),1) or str(payload.get("client", "")) != CLIENT: return false
	if not payload.get("approved_originals") is Array or not payload.get("prior_result", {}) is Dictionary: return false
	var seen := {}; var kinds := {}
	for value in payload.approved_originals:
		if not value is Dictionary or not value.get("data") is Dictionary or int(value.get("status", 0)) != 200: return false
		var id := str(value.get("id", "")); var action := str(value.get("action", ""))
		if id.is_empty() or seen.has(id) or action not in ["consent_review","run_business","submit_report"]: return false
		if action == "run_business" and str(value.data.get("receipt_id", "")).is_empty(): return false
		seen[id] = true; kinds[action] = true
	return kinds.size() == 3

static func create_followup(payload: Dictionary) -> Dictionary:
	if not _valid_source(payload): return {}
	var s := _create(int(payload.round)); s.priority.source = payload.duplicate(true)
	for original in payload.approved_originals:
		var row := _record(s,"baseline_reference",200,"prior-case/" + str(payload.source_contract_id),"前回納品の原本。今回の承認・実測とは別の記録です。",{"source_contract_id":str(payload.source_contract_id),"source_day":int(payload.source_day),"source_record_id":str(original.id),"original":original.duplicate(true)})
		row.id = "PRIOR-" + str(original.id); s.audit.append(row.duplicate(true))
	return s

static func _valid(s: Dictionary) -> bool:
	if str(s.get("case_id", "")) != CASE_ID or str(s.get("model_version", "")) != MODEL_VERSION or str(s.get("kind", "")) != KIND: return false
	for key in ["elapsed_minutes","world_revision","revision","sequence"]:
		if not _whole(s.get(key)): return false
	for key in ["priority","egress","report","organization"]:
		if not s.get(key) is Dictionary: return false
	if not s.get("records") is Array or not s.get("audit") is Array or not s.priority.get("queues") is Array or s.priority.queues.size() != 2 or not s.priority.get("background") is Dictionary: return false
	if not _whole(s.priority.get("round"),1) or not s.priority.get("source") is Dictionary: return false
	if not s.priority.source.is_empty() and not _valid_source(s.priority.source): return false
	for q in s.priority.queues:
		if not q is Dictionary or str(q.get("id", "")) not in ["dispatch","claims"] or not q.get("policy") is Dictionary or not q.get("items") is Array or not q.get("extra_items") is Array or not q.get("attempts") is Array: return false
		if str(q.policy.get("scope", "")) not in ["off","linked","all"] or str(q.policy.get("recipient", "")) not in RECIPIENTS or not _whole(q.get("policy_revision")) or not _whole(q.get("loss_cost")): return false
	return not _queue(s,"dispatch").is_empty() and not _queue(s,"claims").is_empty() and s.priority.background.get("enabled") is bool and _whole(s.priority.background.get("policy_revision")) and s.priority.background.get("schedule") is Array and s.egress.get("exported_rows") is Array and s.report.get("supplements") is Array

static func _leak(s: Dictionary, rows: Array, record: Dictionary, origin: String) -> int:
	for item in rows: s.egress.exported_rows.append({"id":str(record.id) + ":" + str(item.id),"item_id":str(item.id),"origin":origin,"minute":int(record.minute),"record_id":str(record.id),"recipient":str(record.destination),"cost":500})
	var cost := rows.size() * 500; s.egress.impact_cost = int(s.egress.impact_cost) + cost
	return cost

static func advance(s: Dictionary, minutes: int) -> int:
	if not _valid(s) or minutes <= 0: return 0
	var finish := int(s.elapsed_minutes) + minutes; var milestones: Array = []
	for q in s.priority.queues:
		if str(q.receipt_id).is_empty() and not bool(q.late) and int(s.elapsed_minutes) <= int(q.deadline_minute) and finish > int(q.deadline_minute): milestones.append({"minute":int(q.deadline_minute) + 1,"queue_id":str(q.id)})
	for event in s.priority.background.schedule:
		if str(event.status) == "scheduled" and int(event.due_minute) > int(s.elapsed_minutes) and int(event.due_minute) <= finish: milestones.append({"minute":int(event.due_minute),"event":event})
	milestones.sort_custom(func(a,b): return int(a.minute) < int(b.minute))
	var impact := 0
	for milestone in milestones:
		var minute := int(milestone.minute)
		if milestone.has("queue_id"):
			var q := _queue(s,str(milestone.queue_id)); q.late = true; q.loss_cost = int(q.loss_cost) + int(q.late_cost); impact += int(q.late_cost)
			var late := _record(s,"queue_overdue",429,str(q.approved_recipient),str(q.label) + "の受付期限を超えました。補償は復旧後も残ります。",{"queue_id":str(q.id),"deadline_minute":int(q.deadline_minute),"loss_amount":int(q.late_cost)},minute)
			q.late_record_id = str(late.id)
		else:
			var background: Dictionary = s.priority.background; var event: Dictionary = milestone.event; var enabled := bool(background.enabled)
			var record := _record(s,"scheduled_background_send",200 if enabled else 403,str(background.recipient),"既存の一括名簿同期。通常2業務とは別の送付経路です。",{"schedule_id":str(event.id),"background_revision":int(background.policy_revision),"enabled":enabled,"rows":6 if enabled else 0},minute)
			background.last_attempt = record.duplicate(true)
			if enabled:
				var rows: Array = []
				for index in 6: rows.append({"id":"DIRECTORY-%d" % (index + 1)})
				impact += _leak(s,rows,record,"background")
			event.status = "completed" if enabled else "blocked"; event.status_code = int(record.status); event.rows = 6 if enabled else 0; event.record_id = str(record.id)
	s.elapsed_minutes = finish
	return impact

static func _flat(row: Dictionary) -> Dictionary:
	var copy := row.duplicate(false); var data: Dictionary = row.get("data", {}).duplicate(false)
	data.erase("records"); data.erase("events"); copy.data = data.duplicate(true)
	return copy

static func _find(s: Dictionary, id: String) -> Dictionary:
	for row in s.records:
		if str(row.get("id", "")) == id: return row
	return {}

static func _latest(s: Dictionary, action: String, queue_id: String = "") -> Dictionary:
	var result: Dictionary = {}
	for row in s.records:
		if str(row.get("action", "")) == action and (queue_id.is_empty() or str(row.get("data", {}).get("queue_id", "")) == queue_id): result = row
	return result

static func _ids(s: Dictionary, value: Variant) -> Array:
	if not value is Array or value.is_empty() or value.size() > 32: return []
	var ids: Array = []
	for id in value:
		if not id is String or id.is_empty() or id in ids or _find(s,id).is_empty(): return []
		ids.append(id)
	return ids

static func _hash(ids: Array) -> String:
	var sorted := ids.duplicate(); sorted.sort(); return "|".join(sorted)

static func _queue_proof(s: Dictionary, q: Dictionary, action: String) -> Dictionary:
	var row := _latest(s,action,str(q.id)); var data: Dictionary = row.get("data", {})
	if int(data.get("policy_revision", -1)) != int(q.policy_revision) or int(row.get("status", 0)) != (200 if action == "run_business" else 403): return {}
	if action == "run_business" and (str(data.get("receipt_id", "")).is_empty() or data.get("jobs", []).size() != int(q.approved_count)): return {}
	return row

static func _background_proof(s: Dictionary) -> Dictionary:
	var background: Dictionary = s.priority.background; var result: Dictionary = {}
	if bool(background.enabled): return result
	for row in s.records:
		if str(row.get("action", "")) in ["scheduled_background_send","probe_background"] and int(row.get("status", 0)) == 403 and int(row.get("data", {}).get("background_revision", -1)) == int(background.policy_revision): result = row
	return result

static func _required(s: Dictionary) -> Array:
	var ids: Array = []
	for row in s.records:
		if str(row.action) in ["consent_review","baseline_reference"]: ids.append(str(row.id))
	for q in s.priority.queues:
		for action in ["run_business","probe_queue"]:
			var row := _queue_proof(s,q,action)
			if not row.is_empty(): ids.append(str(row.id))
	var stop := _latest(s,"configure_background"); var proof := _background_proof(s); var audit := _latest(s,"collect_audit")
	for row in [stop,proof,audit]:
		if not row.is_empty(): ids.append(str(row.id))
	return ids

static func _damage_captured(s: Dictionary, captured: Array) -> bool:
	for copy in s.egress.exported_rows:
		if str(copy.get("record_id", "")) not in captured: return false
	for q in s.priority.queues:
		if not str(q.late_record_id).is_empty() and str(q.late_record_id) not in captured: return false
	return true

static func _report_fresh(s: Dictionary) -> bool:
	var latest: Dictionary = s.report.get("latest", {})
	return bool(s.report.get("submitted", false)) and int(latest.get("world_revision", -1)) == int(s.world_revision) and _damage_captured(s,latest.get("event_record_ids", []))

static func _report_valid(s: Dictionary, ids: Array) -> bool:
	for q in s.priority.queues:
		if _queue_proof(s,q,"run_business").is_empty() or _queue_proof(s,q,"probe_queue").is_empty(): return false
	if _background_proof(s).is_empty(): return false
	var stop := _latest(s,"configure_background"); var audit := _latest(s,"collect_audit")
	if stop.is_empty() or bool(stop.get("data", {}).get("enabled", true)) or audit.is_empty() or int(audit.world_revision) != int(s.world_revision): return false
	var captured: Array = audit.get("data", {}).get("event_record_ids", [])
	for id in _required(s):
		if id not in ids or (id != str(audit.id) and id not in captured): return false
	return _damage_captured(s,captured)

static func act(state: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	if not _valid(state): return _error("緊急業務の保存状態を確認できません。")
	var s := state.duplicate(true); var minutes := 0; var usage := 0; var ids: Array = []
	var q := _queue(s,str(args.get("queue_id", ""))); var key := str(args.get("key", "")); var value: Variant = args.get("value")
	match action:
		"configure":
			if q.is_empty() or key not in ["scope","recipient"] or not value is String or (key == "scope" and value not in ["off","linked","all"]) or (key == "recipient" and value not in RECIPIENTS): return _error("対象業務と設定値を選んでください。")
			if q.policy[key] == value: return _unchanged(state,"同じ設定が適用済みです。")
			minutes = 1
		"toggle_background":
			if not args.get("enabled") is bool: return _error("一括同期の設定値を選んでください。")
			if bool(args.enabled) == bool(s.priority.background.enabled): return _unchanged(state,"一括同期は同じ設定です。")
			minutes = 1
		"run_queue":
			if q.is_empty(): return _error("受付する業務を選んでください。")
			if not str(q.receipt_id).is_empty() and int(q.verified_revision) == int(q.policy_revision): return _unchanged(state,"現在設定の受付確認済みです。受付番号は変わりません。")
			minutes = 3
		"probe_queue":
			if q.is_empty(): return _error("試験する業務を選んでください。")
			minutes = 2
		"probe_background", "collect_audit": minutes = 2
		"wait": minutes = 3
		"organize_records", "submit_report":
			ids = _ids(s,args.get("record_ids"))
			if ids.is_empty(): return _error("取得済み原本を重複なく32件以内で選んでください。")
			minutes = 2
			if action == "organize_records":
				var mode := str(args.get("mode", ""))
				if mode not in ["manual","assistant"]: return _error("整理方法を選んでください。")
				if str(s.organization.get("mode", "")) == mode and str(s.organization.get("input_hash", "")) == _hash(ids): return _unchanged(state,"同じ選択原本の保存済み整理を再表示します。")
				minutes = 5 if mode == "manual" else 2; usage = 300 if mode == "assistant" else 0
		_: return _error("この緊急案件で使える操作を選んでください。")
	var impact := advance(s,minutes); var result := _result(true,true,minutes,usage,impact,"操作を記録しました。")
	var record: Dictionary = {}
	match action:
		"configure":
			q.policy[key] = value; q.policy_revision = int(q.policy_revision) + 1; s.world_revision = int(s.world_revision) + 1
			record = _record(s,"configure_policy",200,str(q.id),str(q.label) + "の設定を変更しました。",{"queue_id":str(q.id),"policy_revision":int(q.policy_revision),"key":key,"value":value})
		"toggle_background":
			var background: Dictionary = s.priority.background; background.enabled = bool(args.enabled); background.policy_revision = int(background.policy_revision) + 1; s.world_revision = int(s.world_revision) + 1
			record = _record(s,"configure_background",200,str(background.recipient),"一括同期の設定を変更しました。通常業務の送付口は別設定です。",{"enabled":bool(background.enabled),"background_revision":int(background.policy_revision)})
		"run_queue":
			var allowed: bool = str(q.policy.scope) != "off" and str(q.policy.recipient) == str(q.approved_recipient)
			var verification_only := not str(q.receipt_id).is_empty()
			var receipt := "RCPT-%s-%02d" % [str(q.id).to_upper(),int(s.priority.round)] if allowed else str(q.receipt_id)
			var jobs: Array = q.items.duplicate(true) if allowed else []
			for index in jobs.size(): jobs[index].status = "received"; jobs[index].recipient = str(q.approved_recipient); jobs[index].receipt_id = receipt + "-%d" % (index + 1)
			var excess: Array = q.extra_items if allowed and not verification_only and str(q.policy.scope) == "all" else []
			record = _record(s,"run_business",200 if allowed else 403,str(q.policy.recipient),str(q.label) + (("の現在設定を再確認しました。受付控えは保持されています。" if verification_only else "を受け付けました。") if allowed else "の受付に必要な範囲または送付先が一致しません。"),{"queue_id":str(q.id),"policy_revision":int(q.policy_revision),"receipt_id":receipt,"jobs":jobs,"scope":str(q.policy.scope),"recipient":str(q.policy.recipient),"verification_only":verification_only,"excess_rows":excess.size()})
			q.attempts.append(record.duplicate(true)); q.last_attempt = record.duplicate(true)
			if allowed:
				if str(q.receipt_id).is_empty(): q.receipt_id = receipt; q.received_minute = int(s.elapsed_minutes); q.items = jobs.duplicate(true)
				q.verified_revision = int(q.policy_revision); impact += _leak(s,excess,record,str(q.id))
			else: q.verified_revision = -1; result.ok = false
		"probe_queue":
			var denied: bool = str(q.policy.scope) == "linked" and str(q.policy.recipient) == str(q.approved_recipient)
			record = _record(s,"probe_queue",403 if denied else 200,str(q.approved_recipient),str(q.label) + "の承認外参照・送付のダミー試験です。",{"queue_id":str(q.id),"policy_revision":int(q.policy_revision),"scope":str(q.policy.scope),"recipient":str(q.policy.recipient),"approved_recipient":str(q.approved_recipient),"test_only":true})
		"probe_background":
			var background: Dictionary = s.priority.background
			record = _record(s,"probe_background",200 if bool(background.enabled) else 403,str(background.recipient),"一括同期送付口へのダミー試験です。名簿は送付しません。",{"background_revision":int(background.policy_revision),"enabled":bool(background.enabled),"test_only":true})
			background.last_attempt = record.duplicate(true)
		"wait": record = _record(s,"wait",200,"case-clock","3分が経過しました。")
		"collect_audit":
			var events: Array = []; var event_ids: Array = []
			for row in s.records: events.append(_flat(row)); event_ids.append(str(row.id))
			record = _record(s,"collect_audit",200,"audit-log","取得時点までの業務・承認・同期・損失原本を保存しました。",{"event_record_ids":event_ids,"events":events})
		"organize_records":
			var originals: Array = []
			for id in ids: originals.append(_flat(_find(s,str(id))))
			s.organization = {"mode":str(args.mode),"record_ids":ids.duplicate(),"records":originals,"input_hash":_hash(ids),"created_minute":int(s.elapsed_minutes),"world_revision":int(s.world_revision),"usage_cost":usage}
			record = _record(s,"organize_" + str(args.mode),200,"case-records","選択された原本だけを整理しました。測定は追加していません。",{"record_ids":ids.duplicate(),"creates_evidence":false})
		"submit_report":
			if _report_valid(s,ids):
				var originals: Array = []
				for id in ids: originals.append(_flat(_find(s,str(id))))
				var original := {"version":int(s.report.version) + 1,"record_ids":ids.duplicate(),"records":originals,"event_record_ids":_latest(s,"collect_audit").data.event_record_ids.duplicate(),"world_revision":int(s.world_revision),"accepted_minute":int(s.elapsed_minutes)}
				record = _record(s,"submit_report",200,"incident-report","2業務の受付と最小範囲、一括同期停止と損失を報告しました。",original)
				original.record_id = str(record.id)
				if not bool(s.report.submitted): s.report.original = original.duplicate(true)
				else: s.report.supplements.append(original.duplicate(true))
				s.report.submitted = true; s.report.version = int(original.version); s.report.latest = original.duplicate(true)
			else:
				record = _record(s,"submit_report",403,"incident-report","今回の承認・現在設定の受付と境界・一括同期停止の実測・損失監査が不足しています。",{"record_ids":ids.duplicate()}); result.ok = false
	result.impact_cost = impact; result.cost = usage + impact; result.message = str(record.get("detail", "操作を記録しました。"))
	result.data = {"record":record.duplicate(true),"record_id":str(record.get("id", "")),"usage_cost":usage,"impact_cost":impact,"elapsed_minutes":int(s.elapsed_minutes),"world_revision":int(s.world_revision)}
	s.revision = int(s.revision) + 1; s.last_result = {"action":action,"ok":bool(result.ok),"changed":true,"minutes":minutes,"cost":int(result.cost),"message":str(result.message),"data":result.data.duplicate(true)}
	result.state = s
	return result

static func checks(s: Dictionary) -> Array:
	if not _valid(s): return []
	var result: Array = []
	for q in s.priority.queues:
		result.append({"id":str(q.id) + "_receipt","label":str(q.label) + "を正規送付先で受付","passed":not _queue_proof(s,q,"run_business").is_empty()})
		result.append({"id":str(q.id) + "_boundary","label":str(q.label) + "を承認された最小範囲で実測","passed":not _queue_proof(s,q,"probe_queue").is_empty()})
	result.append({"id":"background","label":"別経路の一括同期を停止して実測","passed":not _background_proof(s).is_empty()})
	result.append({"id":"report","label":"今回の承認・実測・損失を報告","passed":_report_fresh(s)})
	return result

static func view(s: Dictionary, selected: String = "") -> Dictionary:
	if not _valid(s): return {}
	var p: Dictionary = s.priority.duplicate(true); var loss := 0
	for q in p.queues:
		q.current = not _queue_proof(s,q,"run_business").is_empty(); q.probe = _latest(s,"probe_queue",str(q.id)).duplicate(true); loss += int(q.loss_cost)
	p.background.current_probe = _background_proof(s).duplicate(true)
	p.records = s.records.duplicate(true); p.organization = s.organization.duplicate(true)
	if not p.organization.is_empty(): p.organization.fresh = int(p.organization.world_revision) == int(s.world_revision)
	p.report = s.report.duplicate(true); p.report.required_record_ids = _required(s); p.report_fresh = _report_fresh(s)
	p.elapsed_minutes = int(s.elapsed_minutes); p.world_revision = int(s.world_revision); p.egress = s.egress.duplicate(true); p.leaked_rows = s.egress.exported_rows.size(); p.impact_cost = int(s.egress.impact_cost); p.loss_cost = loss; p.selected = selected; p.recipient_options = RECIPIENTS.duplicate()
	return {"kind":KIND,"case_id":CASE_ID,"checks":checks(s),"last_result":s.last_result.duplicate(true),"priority":p}
