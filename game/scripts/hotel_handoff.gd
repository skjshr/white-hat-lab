extends RefCounted
## Proof-bound follow-up from a delivered hotel containment job.
## This helper only projects saved history and VM exports; it never creates a VM.
const CASE_ID := "hotel-reservation-recovery"
const CLIENT := "白波ホテル"
const SOURCE_CASE_ID := "service-4-case-0"
const HOTEL := preload("res://scripts/hotel_frontdesk_model.gd")

static func is_case(case_id: String) -> bool:
	return case_id == CASE_ID

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

static func _history_row(state: Dictionary, contract_id: String) -> Dictionary:
	for row in state.get("history", []):
		if row is Dictionary and str(row.get("id", "")) == contract_id and str(row.get("kind", "")).is_empty(): return row
	return {}

static func _folio_received(content: String, journal: Array, expected: Dictionary) -> bool:
	var parsed: Variant = JSON.parse_string(content)
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1 or not parsed.get("folios", []) is Array: return false
	var found := false
	for folio in parsed.folios:
		if not folio is Dictionary or str(folio.get("id", "")) != "F-204": continue
		if str(folio.get("status", "")) != "received" or int(folio.get("balance", -1)) != 0: return false
		var receipt: Dictionary = folio.get("receipt", {})
		if str(receipt.get("folio_id", "")) != "F-204" or str(receipt.get("number", "")) != str(expected.get("number", "")) or str(receipt.get("folio_sha256", "")) != str(expected.get("folio_sha256", "")): return false
		found = journal.any(func(entry): return entry is Dictionary and str(entry.get("action", "")) == "receive" and _canonical(entry.get("receipt", {})) == _canonical(receipt))
	return found

## Validate a completed source delivery and capture its immutable handoff bytes.
## Call only from delivery/migration mutation paths, never from UI rendering.
static func capture_source(state: Dictionary, source_contract_id: String) -> Dictionary:
	if source_contract_id.is_empty(): return {}
	var row := _history_row(state, source_contract_id)
	if row.is_empty() or str(row.get("case_id", "")) != SOURCE_CASE_ID or str(row.get("client", "")) != CLIENT: return {}
	var checks: Array = row.get("checks", []) if row.get("checks", []) is Array else []
	if checks.is_empty() or not checks.all(func(item): return item is Dictionary and bool(item.get("passed", false))): return {}
	var workflow: Dictionary = row.get("hotel_workflow", {}) if row.get("hotel_workflow", {}) is Dictionary else {}
	var sites: Array = workflow.get("sites", []) if workflow.get("sites", []) is Array else []
	if sites.size() != 1: return {}
	var site: Dictionary = sites[0] if sites[0] is Dictionary else {}
	var source_receipt: Dictionary = site.get("receipt", {}) if site.get("receipt", {}) is Dictionary else {}
	if str(site.get("status", "")) != "received" or int(site.get("balance", -1)) != 0 or str(site.get("folio_id", "")) != "F-204": return {}
	if not bool(site.get("reservation_isolated", false)) or str(site.get("reservation_device", "")) != "pc_a": return {}
	if str(source_receipt.get("number", "")).is_empty() or str(source_receipt.get("folio_sha256", "")).length() != 64: return {}
	var key := source_contract_id + "/site-0"
	var vm: Variant = state.get("vm_states", {}).get(key, {})
	if not vm is Dictionary or int(vm.get("schema", 0)) != 2: return {}
	var scenario: Dictionary = vm.get("scenario", {}) if vm.get("scenario", {}) is Dictionary else {}
	if int(scenario.get("hotel_workflow_version", 0)) != 1 or str(scenario.get("id", "")) != SOURCE_CASE_ID: return {}
	var applied: Dictionary = vm.get("applied", {}) if vm.get("applied", {}) is Dictionary else {}
	if str(applied.get("pc_a", "")) != "isolated" or str(applied.get("pc_b", "")) != "connected": return {}
	var fs: Dictionary = vm.get("fs", {}) if vm.get("fs", {}) is Dictionary else {}
	var folio_content := str(fs.get(HOTEL.PATH, ""))
	var journal: Array = vm.get("hotel_journal", []) if vm.get("hotel_journal", []) is Array else []
	if not _folio_received(folio_content, journal, source_receipt): return {}
	var evidence_content := str(fs.get("/var/log/evidence.log", ""))
	if evidence_content.is_empty() or evidence_content != str(vm.get("evidence_original", "")) or evidence_content != str(fs.get("/evidence/original.log", "")): return {}
	var evidence_sha256 := evidence_content.sha256_text()
	var measured := false
	for target_result in row.get("delivery_results", []):
		if not target_result is Dictionary: continue
		for probe in target_result.get("probes", []):
			if not probe is Dictionary or str(probe.get("id", "")) != "evidence-log": continue
			var output := str(probe.get("result", ""))
			measured = bool(probe.get("recorded", false)) and bool(probe.get("passed", false)) and output.contains(evidence_sha256)
	if not measured: return {}
	return {"source_contract_id":source_contract_id,"day":int(row.get("day", 0)),"folio_content":folio_content,"hotel_journal":journal.duplicate(true),"evidence_content":evidence_content,"evidence_sha256":evidence_sha256,"source_folio_receipt":str(source_receipt.get("number", "")),"source_folio_sha256":str(source_receipt.get("folio_sha256", "")),"source_vm_key":key}

static func catalog_definition(remediation_case: Dictionary) -> Dictionary:
	var result := remediation_case.duplicate(true)
	result.merge({"id":CASE_ID,"title":"白波ホテル 予約端末の復旧と次便取込","client":CLIENT,"chapter":4,"category":"response","tier":2,"required_level":5,"required_rank":2,"required_skills":{"response":2},"work_family":"hotel_reservation_recovery","hotel_recovery_only":true,"retired_from_new_offers":true,"brief":"F-204の精算受付後、予約台帳を扱うPC-Aは隔離状態で引き継がれています。前回の受付記録と証拠原本を保全したまま、PC-Aの安全を確認して予約業務を再開し、翌日到着の予約を取り込んでください。","initial":{"pc_a":"isolated","pc_b":"connected","logs":"keep","reset":"wait"},"desired":{"pc_a":"connected","pc_b":"connected","logs":"keep","reset":"wait"},"checks":["PC-A・PC-Bの業務通信とファイル利用可を確認する","両端末の脅威除去と最新スキャンを確認する","今回の証拠原本を保全する","翌日到着分の予約を受付する","前回F-204と引継ぎ原本を保全する"],"targets":[{"chapter":4,"case_id":CASE_ID,"name":"PC-A・予約端末"}],"reward":8200,"suspect":"pc_a","critical_device":"pc_a","edr_recovery_required":true,"endpoint_engagement":1,"endpoint_business":{"pc_a":"予約台帳","pc_b":"当日精算"},"hotel_workflow_version":2,"hotel_recovery":true},true)
	return result

static func scenario(handoff: Dictionary, recovery_day: int) -> Dictionary:
	if not valid_handoff(handoff) or recovery_day < int(handoff.get("day", 0)) + 1: return {}
	var result := {"id":CASE_ID,"client":CLIENT,"chapter":4,"initial":{"pc_a":"isolated","pc_b":"connected","logs":"keep","reset":"wait"},"desired":{"pc_a":"connected","pc_b":"connected","logs":"keep","reset":"wait"},"suspect":"pc_a","critical_device":"pc_a","edr_recovery_required":true,"endpoint_engagement":1,"endpoint_business":{"pc_a":"予約台帳","pc_b":"当日精算"},"checks":["PC-A・PC-Bの業務通信とファイル利用可を確認する","両端末の脅威除去と最新スキャンを確認する","今回の証拠原本を保全する","翌日到着分の予約を受付する","前回F-204と引継ぎ原本を保全する"],"hotel_workflow_version":2,"hotel_recovery":true,"hotel_recovery_day":recovery_day,"hotel_handoff":handoff.duplicate(true)}
	var base := CATALOG_DEFINITION_TEMPLATE
	result.probes = base.get("probes", []).duplicate(true)
	return result

const CATALOG_DEFINITION_TEMPLATE := {"probes":[
	{"id":"recovery-business-a","label":"PC-Aの予約業務","command":"curl https://edr.client.test/pc-a/business","expectation":"status:200|business session healthy","description":"PC-Aの業務セッションが回復していることを確認します。","recorded":false,"passed":false,"fresh":false,"result":""},
	{"id":"recovery-clean-a","label":"PC-Aの安全状態","command":"edr status pc_a","expectation":"\"ready\":true","description":"PC-Aの現行スキャン結果と脅威数を確認します。","recorded":false,"passed":false,"fresh":false,"result":""},
	{"id":"recovery-business-b","label":"PC-Bの精算業務","command":"curl https://edr.client.test/pc-b/business","expectation":"status:200|business session healthy","description":"精算業務が継続していることを確認します。","recorded":false,"passed":false,"fresh":false,"result":""},
	{"id":"recovery-clean-b","label":"PC-Bの安全状態","command":"edr status pc_b","expectation":"\"ready\":true","description":"PC-Bの現行スキャン結果と脅威数を確認します。","recorded":false,"passed":false,"fresh":false,"result":""},
	{"id":"evidence-log","label":"証拠原本の完全性","command":"sha256sum /var/log/evidence.log","expectation":"pending-evidence-hash","description":"証拠原本のハッシュを確認します。","recorded":false,"passed":false,"fresh":false,"result":""}
]}

static func valid_handoff(handoff: Dictionary) -> bool:
	if str(handoff.get("source_contract_id", "")).is_empty() or int(handoff.get("day", 0)) < 1: return false
	var folio := str(handoff.get("folio_content", "")); var evidence := str(handoff.get("evidence_content", ""))
	if folio.is_empty() or evidence.is_empty() or str(handoff.get("evidence_sha256", "")) != evidence.sha256_text(): return false
	if str(handoff.get("source_folio_receipt", "")).is_empty() or str(handoff.get("source_folio_sha256", "")).length() != 64: return false
	var parsed: Variant = JSON.parse_string(folio)
	if not parsed is Dictionary or not parsed.get("folios", []) is Array or not handoff.get("hotel_journal", []) is Array: return false
	return _folio_received(folio, handoff.get("hotel_journal", []), {"number":str(handoff.source_folio_receipt),"folio_sha256":str(handoff.source_folio_sha256)})

static func pending_records(state: Dictionary, day: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var records: Variant = state.get("company_cycle", {}).get("hotel_recoveries", {})
	if not records is Dictionary: return result
	var ids: Array = records.keys(); ids.sort()
	for source_id in ids:
		var record: Variant = records[source_id]
		if not record is Dictionary or str(record.get("status", "")) != "pending" or int(record.get("available_day", 0)) > day: continue
		var handoff: Variant = record.get("handoff", {})
		if handoff is Dictionary and valid_handoff(handoff): result.append(record.duplicate(true))
	return result
