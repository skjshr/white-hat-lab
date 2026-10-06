extends SceneTree
## Focused model paths only. No real saves, GUI or injected successful receipts.
const MODEL = preload("res://scripts/saas_priority.gd")
const PRIOR = preload("res://scripts/saas_ai_handoff.gd")
var failures: Array[String] = []
var world: Dictionary = {}
var odd: Dictionary = {}
var even: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_PRIORITY: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func latest(s: Dictionary, action: String, queue_id: String = "") -> Dictionary:
	var result: Dictionary = {}
	for row in s.records:
		if str(row.action) == action and (queue_id.is_empty() or str(row.data.get("queue_id", "")) == queue_id): result = row
	return result

func flat(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true); result.data.erase("records"); result.data.erase("events"); return result

func perform(action: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = MODEL.act(world,action,args)
	if bool(result.get("changed", false)): world = result.state
	return result

func queue(id: String) -> Dictionary:
	for q in world.priority.queues:
		if str(q.id) == id: return q
	return {}

func loss() -> int:
	return int(queue("dispatch").loss_cost) + int(queue("claims").loss_cost)

func prepare() -> void:
	var previous: Dictionary = PRIOR.create()
	previous = PRIOR.act(previous,"configure",{"key":"contacts","value":"linked"}).state
	previous = PRIOR.act(previous,"configure",{"key":"partner_archive","enabled":false}).state
	previous = PRIOR.act(previous,"configure",{"key":"partner_dispatch","enabled":true}).state
	previous = PRIOR.act(previous,"run_business").state
	previous = PRIOR.act(previous,"probe_boundaries").state
	previous = PRIOR.act(previous,"collect_audit").state
	var submitted: Dictionary = PRIOR.act(previous,"submit_report",{"record_ids":PRIOR.view(previous).handoff.report.required_record_ids}); previous = submitted.state
	check(bool(submitted.ok) and PRIOR.checks(previous).all(func(row): return bool(row.passed)), "the previous handoff source earns its originals through the unchanged model")
	var before := encoded(previous)
	var payload := {"source_contract_id":"qa-priority-source","source_day":4,"client":"北斗物流","round":1,"approved_originals":[flat(previous.records[0]),flat(latest(previous,"run_business")),flat(latest(previous,"submit_report"))],"prior_result":{"loss_cost":0}}
	odd = MODEL.create_followup(payload)
	check(not odd.is_empty() and encoded(previous) == before and not bool(MODEL.act(previous,"wait").get("changed", true)), "the new engagement freezes the earned source without changing or accepting the legacy world")
	var incomplete := payload.duplicate(true); incomplete.approved_originals.pop_back()
	check(MODEL.create_followup(incomplete).is_empty(), "a source missing its submitted original cannot start a repeat engagement")

func jobs_in_order(first: String, second: String) -> void:
	perform("toggle_background",{"enabled":false})
	for id in [first,second]:
		perform("configure",{"queue_id":id,"key":"scope","value":"linked"})
		perform("configure",{"queue_id":id,"key":"recipient","value":str(queue(id).approved_recipient)})
		check(bool(perform("run_queue",{"queue_id":id}).get("ok", false)), "the selected business reaches its approved recipient: " + id)

func report() -> Dictionary:
	perform("probe_queue",{"queue_id":"dispatch"}); perform("probe_queue",{"queue_id":"claims"})
	perform("probe_background"); perform("collect_audit")
	var selected: Array = MODEL.view(world).priority.report.required_record_ids
	return perform("submit_report",{"record_ids":selected})

func order_and_local_revisions() -> void:
	world = odd.duplicate(true); jobs_in_order("claims","dispatch")
	check(loss() == 0 and int(queue("claims").received_minute) == 6 and int(queue("dispatch").received_minute) <= 14 and world.egress.exported_rows.is_empty(), "odd round: claims first meets the short deadline while both businesses continue with zero loss")
	check(bool(report().ok) and MODEL.checks(world).all(func(row): return bool(row.passed)), "current queue proofs and stopped-background originals support the accepted report")
	var originals: Array = []
	for row in world.records:
		if str(row.action) == "consent_review": originals.append(flat(row))
	for id in ["dispatch","claims"]: originals.append(flat(latest(world,"run_business",id)))
	originals.append(flat(latest(world,"submit_report")))
	even = MODEL.create_followup({"source_contract_id":"qa-priority-round-1","source_day":5,"client":"北斗物流","round":2,"approved_originals":originals,"prior_result":{"loss_cost":0}})
	var receipt := str(queue("claims").receipt_id); var accepted := encoded(queue("claims").items); var original_report := encoded(world.report.original)
	perform("configure",{"queue_id":"claims","key":"recipient","value":"minato/archive"})
	var view: Dictionary = MODEL.view(world).priority
	check(view.queues[0].current and not view.queues[1].current and not view.report_fresh, "changing claims invalidates only its receipt proof and the report, not the dispatch receipt")
	check(not bool(perform("run_queue",{"queue_id":"claims"}).ok) and str(queue("claims").receipt_id) == receipt and encoded(queue("claims").items) == accepted, "a wrong-recipient retry retains the first accepted items and receipt")
	world = JSON.parse_string(JSON.stringify(world))
	perform("configure",{"queue_id":"claims","key":"recipient","value":"minato/claims"}); perform("run_queue",{"queue_id":"claims"})
	check(bool(report().ok) and encoded(world.report.original) == original_report and world.report.supplements.size() == 1 and str(queue("claims").receipt_id) == receipt and loss() == 0, "save-shaped resume and retry append a report without losing original acceptance or charging a new deadline")
	world = odd.duplicate(true); jobs_in_order("dispatch","claims")
	check(loss() == 4500 and int(queue("claims").loss_cost) == 4500 and world.egress.exported_rows.is_empty(), "the same odd-round final policy loses 4500 when dispatch is restored before urgent claims")
	world = even.duplicate(true); jobs_in_order("dispatch","claims")
	check(str(queue("claims").approved_recipient) == "minato/archive" and loss() == 0 and world.egress.exported_rows.is_empty(), "even round changes the claims recipient and makes dispatch the zero-loss first priority")
	world = even.duplicate(true); jobs_in_order("claims","dispatch")
	check(int(queue("dispatch").loss_cost) == 4500 and int(queue("claims").loss_cost) == 0, "blindly repeating the previous priority delays dispatch in the next round")

func irreversible_losses_and_selection() -> void:
	world = odd.duplicate(true)
	check(MODEL.advance(world,16) == 11400 and world.egress.exported_rows.size() == 12 and loss() == 5400, "both scheduled background sends and both missed deadlines leave distinct irreversible losses")
	check(not bool(perform("run_queue",{"queue_id":"claims"}).ok) and str(queue("claims").receipt_id).is_empty(), "the inherited recipient cannot accept the new claims work")
	perform("run_queue",{"queue_id":"dispatch"})
	perform("configure",{"queue_id":"claims","key":"recipient","value":"minato/claims"}); perform("run_queue",{"queue_id":"claims"})
	check(world.egress.exported_rows.size() == 18 and int(world.egress.impact_cost) == 9000 and loss() == 5400, "overbroad first acceptance also copies each queue's three unrelated rows")
	var receipts := [str(queue("dispatch").receipt_id),str(queue("claims").receipt_id)]
	var copies := encoded(world.egress.exported_rows)
	perform("configure",{"queue_id":"claims","key":"recipient","value":"minato/archive"}); perform("run_queue",{"queue_id":"claims"})
	perform("configure",{"queue_id":"claims","key":"recipient","value":"minato/claims"}); perform("run_queue",{"queue_id":"claims"})
	check(encoded(world.egress.exported_rows) == copies and bool(latest(world,"run_business","claims").data.verification_only), "an accepted queue rechecks a changed policy without resending either its business or unrelated rows")
	perform("toggle_background",{"enabled":false})
	for id in ["dispatch","claims"]:
		perform("configure",{"queue_id":id,"key":"scope","value":"linked"}); perform("run_queue",{"queue_id":id})
	check(bool(report().ok) and MODEL.checks(world).all(func(row): return bool(row.passed)) and encoded(world.egress.exported_rows) == copies and loss() == 5400, "explicit background testing allows recovery after both scheduled sends while report and settlement retain every loss")
	check([str(queue("dispatch").receipt_id),str(queue("claims").receipt_id)] == receipts and MODEL.advance(world,30) == 0, "revalidation preserves first receipt numbers and cannot charge old sends or deadlines twice")
	var before := encoded(world); var view: Dictionary = MODEL.view(world)
	view.priority.queues[0].items.clear()
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(world))
	check(encoded(world) == before and encoded(MODEL.view(resumed)) == encoded(MODEL.view(world)), "views and JSON resume preserve queue objects, clock, raw records and losses")
	var selected: Array = ["AP-CLAIMS"]
	var organized := perform("organize_records",{"mode":"assistant","record_ids":selected})
	check(int(organized.usage_cost) == 300 and world.organization.records.size() == 1 and str(world.organization.records[0].id) == "AP-CLAIMS", "assistant use saves only the selected original, without importing unselected proofs")
	before = encoded(world)
	var duplicate := perform("organize_records",{"mode":"assistant","record_ids":selected})
	check(not bool(duplicate.changed) and int(duplicate.cost) == 0 and encoded(world) == before and not bool(perform("run_queue",{"queue_id":"dispatch"}).changed), "saved organization and already-confirmed receipt rechecks are free no-ops")
	for request in [["configure",{"queue_id":"dispatch","key":"scope","value":"invented"}],["run_queue",{"queue_id":"missing"}],["organize_records",{"mode":"assistant","record_ids":["AP-CLAIMS","AP-CLAIMS"]}],["submit_report",{"record_ids":["unknown"]}]]:
		var rejected := perform(str(request[0]),request[1])
		check(not bool(rejected.get("changed", true)) and encoded(world) == before, "invalid arguments cannot spend time, charge fees or create records")

func run() -> void:
	prepare()
	if not odd.is_empty(): order_and_local_revisions()
	if not even.is_empty(): irreversible_losses_and_selection()
	print("SAAS_PRIORITY ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
