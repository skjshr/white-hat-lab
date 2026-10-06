extends RefCounted
## Authored response work. Profiles are frozen on acceptance; old work stays intact.
const REMEDIATION = preload("res://scripts/endpoint_remediation.gd")
const SEND_RATE := 100
const UNCONTAINED_RATE := 100
const STOP_RATE := 50
const SATISFACTION_STEP_MINUTES := 6
const SATISFACTION_MAX_PENALTY := 15
const CONTAINMENT_CASES := ["service-4-case-0", "service-4-case-1", "service-4-case-2"]

static func containment_case(case_id: String) -> bool:
	return case_id in CONTAINMENT_CASES

static func containment_specs(base: Dictionary, sites: int) -> Array:
	var case_id := str(base.get("id", ""))
	if not containment_case(case_id): return []
	var roles: Dictionary = {
		"service-4-case-0":{"pc_a":"予約台帳", "pc_b":"当日精算"},
		"service-4-case-1":{"pc_a":"請求確認", "pc_b":"会計資料取込"},
		"service-4-case-2":{"pc_a":"在庫確認", "pc_b":"受注明細照合"},
	}[case_id]
	var result: Array = []
	for index in sites:
		var scenario := base.duplicate(true)
		scenario.erase("targets")
		scenario.endpoint_engagement = 2
		scenario.suspect = str(base.get("suspect", "pc_a"))
		scenario.endpoint_business = roles.duplicate(true)
		scenario.critical_device = "pc_a" if scenario.suspect == "pc_b" else "pc_b"
		scenario.endpoint_uncontained_rate = UNCONTAINED_RATE
		scenario.endpoint_stop_rate = STOP_RATE
		scenario.brief = "%s\nPC-Aは%s、PC-Bは%sに使用しています。対応作業中の未封じ込めは¥%d/分、正常端末の業務誤停止は¥%d/分の補償対象です。" % [str(base.get("brief", "")), str(roles.pc_a), str(roles.pc_b), UNCONTAINED_RATE, STOP_RATE]
		if case_id == "service-4-case-0":
			scenario.hotel_workflow_version = 1
			scenario.checks.append("F-204精算受付確認")
			scenario.brief += "\nフロントからの依頼: 204号室の未送信精算票 F-204 1件をPC-Bから再送し、受付番号を確認してください。PC-Aの予約業務は隔離を維持して引き継ぎます。ほかの3室は在室中のため精算不要です。"
		result.append({"chapter":4, "case_id":case_id, "name":"拠点%d" % (index + 1), "scenario":scenario})
	return result

static func profiles(base: Dictionary) -> Array:
	var result: Array = []
	for index in 2:
		var scenario := base.duplicate(true)
		scenario.erase("targets")
		scenario.endpoint_engagement = 1
		scenario.brief = str(base.get("engagement_brief", base.get("brief", "")))
		scenario.host = "design-office.client.test" if index == 0 else "design-press.client.test"
		scenario.suspect = "pc_a" if index == 0 else "none"
		scenario.initial = {"pc_a":"connected" if index == 0 else "isolated","pc_b":"connected","logs":"keep","reset":"wait"}
		scenario.endpoint_business = {"pc_a":"制作資料の編集","pc_b":"校正PDFの確認"} if index == 0 else {"pc_a":"印刷データの入稿","pc_b":"承認済みの素材退避"}
		scenario.critical_device = "pc_a"
		result.append({"chapter":4,"case_id":"endpoint-recovery","name":"本社・制作" if index == 0 else "入稿室","scenario":scenario})
	return result

static func _isolated(saved: Dictionary, scenario: Dictionary, id: String) -> bool:
	for device in saved.get("edr_devices", []):
		if str(device.get("id", "")) == id: return bool(device.get("isolated", false))
	return str(scenario.get("initial", {}).get(id, "connected")) == "isolated"

static func _sending(saved: Dictionary, scenario: Dictionary) -> bool:
	if saved.is_empty():
		var suspect := str(scenario.get("suspect", "none"))
		return suspect in ["pc_a", "pc_b"] and not _isolated(saved, scenario, suspect)
	for process in saved.get("edr_processes", []):
		if bool(process.get("running", false)) and str(process.get("sha256", "")) == REMEDIATION.MALICIOUS_SHA256 and not _isolated(saved, scenario, str(process.get("device", ""))): return true
	return false

static func _uncontained(saved: Dictionary, scenario: Dictionary) -> bool:
	# Ordinary investigations have historical events, not executable processes.
	# Measure the authored source's lack of containment, never invented traffic.
	var suspect := str(scenario.get("suspect", "pc_a"))
	if suspect not in ["pc_a", "pc_b"]: return false
	var applied: Dictionary = saved.get("applied", {})
	if applied.has(suspect): return str(applied[suspect]) != "isolated"
	return not _isolated(saved, scenario, suspect)

static func _stopped(saved: Dictionary, scenario: Dictionary) -> bool:
	var id := str(scenario.get("critical_device", "pc_a"))
	if _isolated(saved, scenario, id): return true
	for device in saved.get("edr_devices", []):
		if str(device.get("id", "")) == id: return str(device.get("business_status", "healthy")) != "healthy"
	return false

static func advance(g, minutes: float) -> void:
	if minutes <= 0 or g.current_done(): return
	var snapshots: Array = []
	for index in g.state.get("targets", []).size():
		snapshots.append(g.state.get("vm_states", {}).get(g._vm_key(index), {}))
	_advance_work(g.state.work, g.state.get("targets", []), snapshots, minutes)

static func advance_context(context: Dictionary, vm_states: Dictionary, contract_id: String, minutes: float) -> void:
	if minutes <= 0 or bool(context.get("completed", false)) or not bool(context.get("accepted", false)): return
	var snapshots: Array = []
	var targets: Array = context.get("targets", [])
	for index in targets.size():
		snapshots.append(vm_states.get("%s/site-%d" % [contract_id, index], {}))
	_advance_work(context.work, targets, snapshots, minutes)

static func _advance_work(work: Dictionary, targets: Array, snapshots: Array, minutes: float) -> void:
	var ledger: Dictionary = work.get("endpoint_impact", {}).duplicate(true)
	var before_cost := total_cost(ledger)
	for index in targets.size():
		var target: Dictionary = targets[index]
		var scenario: Dictionary = target.get("scenario", {})
		var version := int(scenario.get("endpoint_engagement", 0))
		if version not in [1, 2]: continue
		# Persisted VM state is the state before an action finishes. Rendering and
		# selecting a site add no minutes; a failed save rolls back this work ledger.
		var saved: Dictionary = snapshots[index]
		var initial := {"name":str(target.name), "stop_minutes":0.0}
		initial["uncontained_minutes" if version == 2 else "send_minutes"] = 0.0
		var item: Dictionary = ledger.get(str(index), initial)
		if version == 2:
			if _uncontained(saved, scenario): item.uncontained_minutes = float(item.get("uncontained_minutes", 0.0)) + minutes
		elif _sending(saved, scenario): item.send_minutes = float(item.send_minutes) + minutes
		if _stopped(saved, scenario): item.stop_minutes = float(item.stop_minutes) + minutes
		if version == 2:
			item.cost = roundi(float(item.get("uncontained_minutes", 0.0)) * int(scenario.get("endpoint_uncontained_rate", UNCONTAINED_RATE)) + float(item.stop_minutes) * int(scenario.get("endpoint_stop_rate", STOP_RATE)))
		else:
			item.cost = roundi(float(item.send_minutes) * SEND_RATE + float(item.stop_minutes) * STOP_RATE)
		ledger[str(index)] = item
	if ledger.is_empty(): return
	work.endpoint_impact = ledger
	work.incident_cost = int(work.get("incident_cost", 0)) + total_cost(ledger) - before_cost

static func total_cost(ledger: Dictionary) -> int:
	var result := 0
	for item in ledger.values(): result += int(item.get("cost", 0))
	return result

static func satisfaction_delta(ledger: Dictionary) -> int:
	var stopped := 0.0
	for item in ledger.values():
		if item is Dictionary and item.has("uncontained_minutes"):
			stopped += maxf(0.0, float(item.get("stop_minutes", 0)))
	return -mini(SATISFACTION_MAX_PENALTY, ceili(stopped / float(SATISFACTION_STEP_MINUTES)))

static func summary(ledger: Dictionary, version: int = 0) -> String:
	var send := 0.0; var stop := 0.0; var uncontained := 0.0
	var containment := version == 2
	for item in ledger.values():
		send += float(item.get("send_minutes", 0)); stop += float(item.get("stop_minutes", 0))
		uncontained += float(item.get("uncontained_minutes", 0))
		containment = containment or item.has("uncontained_minutes")
	if containment:
		return "未封じ込め %d分 · 業務誤停止 %d分 · 補償 ¥%d" % [roundi(uncontained), roundi(stop), total_cost(ledger)]
	return "外部送信 %d分 · 業務停止 %d分 · 補償 ¥%d" % [roundi(send),roundi(stop),total_cost(ledger)]
