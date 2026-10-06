extends SceneTree
## Pure model scenarios; no native-play claims, player saves or fabricated success.
const MODEL = preload("res://scripts/saas_priority.gd")
var failures: Array[String] = []
var world: Dictionary = {}
var originals: Array = []
var usage_total := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("PRIORITY_RECOVERY: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func queue(id: String) -> Dictionary:
	for row in world.priority.queues:
		if str(row.id) == id: return row
	return {}

func perform(action: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = MODEL.act(world,action,args)
	if bool(result.get("changed", false)):
		world = result.state; usage_total += int(result.get("usage_cost", 0))
	return result

func latest(action: String, id: String = "") -> Dictionary:
	var found: Dictionary = {}
	for row in world.records:
		if str(row.action) == action and (id.is_empty() or str(row.data.get("queue_id", "")) == id): found = row
	return found

func configure(id: String) -> void:
	perform("configure",{"queue_id":id,"key":"scope","value":"linked"})
	perform("configure",{"queue_id":id,"key":"recipient","value":str(queue(id).approved_recipient)})

func report() -> Dictionary:
	for id in ["dispatch","claims"]: perform("probe_queue",{"queue_id":id})
	perform("probe_background"); perform("collect_audit")
	return perform("submit_report",{"record_ids":MODEL.view(world).priority.report.required_record_ids})

func source_payload(round_number: int, recovery: bool = true) -> Dictionary:
	var payload := {"source_contract_id":"qa-earned-priority","source_day":5,"client":"北斗物流","round":round_number,"approved_originals":originals.duplicate(true),"prior_result":{"source_model":"saas-priority-v1"}}
	if recovery: payload.recovery_plan = MODEL.plan(round_number)
	return payload

func start(round_number: int) -> void:
	world = MODEL.create_followup(source_payload(round_number)); usage_total = 0

func earn_source_and_legacy_boundary() -> void:
	world = MODEL.create()
	perform("toggle_background",{"enabled":false})
	for id in ["claims","dispatch"]:
		configure(id); perform("run_queue",{"queue_id":id})
	check(bool(report().ok), "previous priority earns its own accepted originals through public actions")
	for row in world.records:
		if str(row.action) == "consent_review": originals.append(row.duplicate(true))
	for row in [latest("run_business","dispatch"),latest("run_business","claims"),latest("submit_report")]:
		var flat: Dictionary = row.duplicate(true); flat.data.erase("records"); flat.data.erase("events"); originals.append(flat)
	var legacy := encoded(world)
	world = JSON.parse_string(JSON.stringify(world))
	MODEL.view(world)
	check(not world.priority.has("recovery") and encoded(world) == legacy and MODEL.checks(world).all(func(row): return bool(row.passed)), "saved v1 work retains its receipts, deadlines, report and absence of recovery data")
	check(not bool(perform("rebuild_connector").get("changed", true)) and not bool(perform("manual_queue",{"queue_id":"claims"}).get("changed", true)) and encoded(world) == legacy, "new recovery operations cannot alter an old accepted world")
	world = MODEL.create_followup(source_payload(3,false))
	check(not world.priority.has("recovery") and int(queue("dispatch").deadline_minute) == 14, "round number alone does not retrofit recovery or new deadlines into a frozen old offer")
	var invalid := source_payload(3); invalid.recovery_plan.manual_cost = 0
	check(MODEL.create_followup(invalid).is_empty(), "a modified or unsupported recovery plan cannot silently start different financial terms")

func odd_emergency_and_even_rebuild() -> void:
	start(3)
	perform("toggle_background",{"enabled":false}); configure("claims")
	var accepted := perform("manual_queue",{"queue_id":"claims"})
	check(bool(accepted.ok) and int(accepted.manual_cost) == 900 and int(accepted.usage_cost) == 900 and int(queue("claims").received_minute) == 5 and str(queue("claims").receipt_channel) == "manual", "odd round can protect the six-minute deadline with one paid manual acceptance")
	var receipt := str(queue("claims").receipt_id); var items := encoded(queue("claims").items); var before := encoded(world)
	var duplicate := perform("manual_queue",{"queue_id":"claims"})
	check(not bool(duplicate.changed) and int(duplicate.cost) == 0 and encoded(world) == before and not bool(MODEL.view(world).priority.queues[1].current), "manual acceptance is idempotent but is not proof of restored normal service")
	world = JSON.parse_string(JSON.stringify(world))
	perform("rebuild_connector"); configure("dispatch"); perform("run_queue",{"queue_id":"dispatch"}); perform("run_queue",{"queue_id":"claims"})
	check(str(queue("claims").receipt_id) == receipt and encoded(queue("claims").items) == items and int(queue("claims").received_minute) == 5 and str(latest("run_business","claims").data.initial_receipt_channel) == "manual" and int(latest("run_business","claims").data.initial_received_minute) == 5, "normal revalidation after JSON resume retains the manual receipt, items, first time and channel")
	var required: Array = MODEL.view(world).priority.report.required_record_ids
	check(str(world.priority.recovery.rebuild_record_id) in required and str(world.priority.recovery.manual_record_id) in required, "report selection requires both the real reconstruction and emergency acceptance originals")
	check(bool(report().ok) and MODEL.checks(world).all(func(row): return bool(row.passed)) and int(MODEL.view(world).priority.loss_cost) == 0 and world.egress.exported_rows.is_empty() and usage_total == 900, "manual then rebuild completes both odd-round jobs without deadline or leakage compensation")
	start(3); perform("toggle_background",{"enabled":false}); perform("rebuild_connector")
	for id in ["claims","dispatch"]: configure(id); perform("run_queue",{"queue_id":id})
	check(int(queue("claims").loss_cost) == 4500 and usage_total == 0, "rebuild first saves manual fees but misses the odd-round emergency deadline")
	start(4); perform("toggle_background",{"enabled":false}); perform("rebuild_connector")
	for id in ["dispatch","claims"]: configure(id); perform("run_queue",{"queue_id":id})
	check(int(queue("dispatch").received_minute) == 11 and int(MODEL.view(world).priority.loss_cost) == 0 and usage_total == 0 and int(world.priority.recovery.manual_remaining) == 1 and bool(report().ok), "even-round deadlines permit reconstruction first and preserve the unused manual budget")

func failures_and_retained_consequences() -> void:
	start(3)
	var failed := perform("run_queue",{"queue_id":"dispatch"})
	check(not bool(failed.ok) and int(failed.data.record.status) == 503 and str(queue("dispatch").receipt_id).is_empty(), "an unavailable shared connector saves a real 503 without accepting the work")
	failed = perform("manual_queue",{"queue_id":"claims"})
	check(not bool(failed.ok) and int(failed.get("manual_cost", -1)) == 0 and int(world.priority.recovery.manual_remaining) == 1 and usage_total == 0, "a wrong manual scope or recipient consumes no slot and charges no manual fee")
	configure("claims"); perform("manual_queue",{"queue_id":"claims"})
	var receipt := str(queue("claims").receipt_id)
	failed = perform("manual_queue",{"queue_id":"dispatch"})
	check(not bool(failed.ok) and int(failed.data.record.status) == 409 and str(world.priority.recovery.manual_queue_id) == "claims" and usage_total == 900, "the second business cannot reuse the single paid emergency slot")
	world = JSON.parse_string(JSON.stringify(world)); perform("rebuild_connector")
	check(bool(world.priority.background.enabled) and world.egress.exported_rows.size() == 12, "rebuilding normal service leaves the old background session independent and both observed leaks saved")
	perform("toggle_background",{"enabled":false}); configure("dispatch")
	for id in ["claims","dispatch"]: perform("run_queue",{"queue_id":id})
	check(bool(report().ok) and MODEL.checks(world).all(func(row): return bool(row.passed)) and int(queue("claims").loss_cost) == 4500 and int(queue("dispatch").loss_cost) == 900 and str(queue("claims").receipt_id) == receipt and int(world.egress.impact_cost) == 6000, "repair and accepted reporting retain the missed deadlines, leaked rows and first manual receipt")
	var before := encoded(world); var projection: Dictionary = MODEL.view(world)
	projection.priority.recovery.manual_remaining = 1; projection.priority.queues[0].items.clear()
	check(encoded(world) == before and encoded(MODEL.view(JSON.parse_string(JSON.stringify(world)))) == encoded(MODEL.view(world)), "projection and JSON resume cannot reset the paid slot, clocks, original records or compensation")
	var repeated := perform("rebuild_connector")
	check(not bool(repeated.changed) and int(repeated.cost) == 0 and MODEL.advance(world,20) == 0 and usage_total == 900, "reconstruction and old scheduled damage cannot be charged twice after completion")

func run() -> void:
	earn_source_and_legacy_boundary()
	if originals.size() == 5:
		odd_emergency_and_even_rebuild(); failures_and_retained_consequences()
	print("SAAS_PRIORITY_RECOVERY ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
