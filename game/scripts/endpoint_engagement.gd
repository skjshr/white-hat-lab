extends RefCounted
## Authored response work. Profiles are frozen on acceptance; old work stays intact.
const REMEDIATION = preload("res://scripts/endpoint_remediation.gd")
const SEND_RATE := 100
const STOP_RATE := 50

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

static func _stopped(saved: Dictionary, scenario: Dictionary) -> bool:
	var id := str(scenario.get("critical_device", "pc_a"))
	if _isolated(saved, scenario, id): return true
	for device in saved.get("edr_devices", []):
		if str(device.get("id", "")) == id: return str(device.get("business_status", "healthy")) != "healthy"
	return false

static func advance(g, minutes: float) -> void:
	if minutes <= 0 or g.current_done(): return
	var ledger: Dictionary = g.state.work.get("endpoint_impact", {}).duplicate(true)
	var before_cost := total_cost(ledger)
	for index in g.state.get("targets", []).size():
		var target: Dictionary = g.state.targets[index]
		var scenario: Dictionary = target.get("scenario", {})
		if int(scenario.get("endpoint_engagement", 0)) != 1: continue
		# Persisted VM state is the state before an action finishes. Rendering and
		# selecting a site add no minutes; a failed save rolls back this work ledger.
		var saved: Dictionary = g.state.get("vm_states", {}).get(g._vm_key(index), {})
		var item: Dictionary = ledger.get(str(index), {"name":str(target.name),"send_minutes":0.0,"stop_minutes":0.0})
		if _sending(saved, scenario): item.send_minutes = float(item.send_minutes) + minutes
		if _stopped(saved, scenario): item.stop_minutes = float(item.stop_minutes) + minutes
		item.cost = roundi(float(item.send_minutes) * SEND_RATE + float(item.stop_minutes) * STOP_RATE)
		ledger[str(index)] = item
	if ledger.is_empty(): return
	g.state.work.endpoint_impact = ledger
	g.state.work.incident_cost = int(g.state.work.get("incident_cost", 0)) + total_cost(ledger) - before_cost

static func total_cost(ledger: Dictionary) -> int:
	var result := 0
	for item in ledger.values(): result += int(item.get("cost", 0))
	return result

static func summary(ledger: Dictionary) -> String:
	var send := 0.0; var stop := 0.0
	for item in ledger.values(): send += float(item.get("send_minutes", 0)); stop += float(item.get("stop_minutes", 0))
	return "外部送信 %d分 · 業務停止 %d分 · 補償 ¥%d" % [roundi(send),roundi(stop),total_cost(ledger)]
