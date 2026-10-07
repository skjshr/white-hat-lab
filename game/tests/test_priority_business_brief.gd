extends SceneTree
## Pure read-only projections for the customer-facing priority brief.

const BRIEF = preload("res://scripts/priority_business_brief.gd")
const ENGINE = preload("res://scripts/saas_priority.gd")
const FOLLOWUP = preload("res://scripts/saas_priority_followup.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("PRIORITY_BUSINESS_BRIEF: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func payload(round_number: int, include_plan: bool = true) -> Dictionary:
	var value := {
		"source_contract_id":"PRIOR-SOURCE-%d" % round_number,
		"source_day":round_number,
		"client":"北斗物流",
		"round":round_number,
		"approved_originals":[
			{"id":"APPROVAL-%d" % round_number,"action":"consent_review","status":200,"data":{}},
			{"id":"RECEIPT-%d" % round_number,"action":"run_business","status":200,"data":{"receipt_id":"PRIOR-RECEIPT-%d" % round_number}},
			{"id":"REPORT-%d" % round_number,"action":"submit_report","status":200,"data":{}}
		],
		"prior_result":{"loss_cost":0}
	}
	if include_plan and round_number >= 3: value.recovery_plan = ENGINE.plan(round_number)
	return value

func context_for(model: Dictionary, costs: Dictionary = {}) -> Dictionary:
	var work := {"minutes":int(model.get("elapsed_minutes",0))}
	if not costs.is_empty(): work.saas_costs = costs.duplicate(true)
	return {"contract":{"case_id":"advanced-saas-priority"},"accepted":true,"advanced":model,"work":work}

func run() -> void:
	var original_payload := payload(4)
	var offer := {"case_id":"advanced-saas-priority","saas_priority_payload":original_payload}
	var payload_before := encoded(offer)
	var even: Dictionary = BRIEF.from_offer(offer)
	check(bool(even.get("available",false)) and bool(even.get("preview",false)) and str(even.get("client","")) == "北斗物流", "a valid round-four offer projects its client-facing brief")
	check(str(even.get("clock_label","")) == "対応開始から" and int(even.get("elapsed",-1)) == 0, "offer timing is identified as starting from response acceptance")
	var by_id: Dictionary = {}
	for queue in even.get("queues",[]): by_id[str(queue.get("id",""))] = queue
	check(int(by_id.get("dispatch",{}).get("deadline",-1)) == 12 and int(by_id.get("claims",{}).get("deadline",-1)) == 22, "even round exposes its actual 12- and 22-minute service deadlines")
	check(int(by_id.get("dispatch",{}).get("late_cost",-1)) == 4500 and int(by_id.get("claims",{}).get("late_cost",-1)) == 900, "the two queue-specific deadline losses are visible before acceptance")
	check(encoded(offer) == payload_before, "offer projection leaves the frozen offer payload untouched")
	var odd: Dictionary = BRIEF.from_offer({"case_id":"advanced-saas-priority","saas_priority_payload":payload(3)})
	by_id.clear()
	for queue in odd.get("queues",[]): by_id[str(queue.get("id",""))] = queue
	check(int(by_id.get("dispatch",{}).get("deadline",-1)) == 20 and int(by_id.get("claims",{}).get("deadline",-1)) == 6, "odd round exposes its authored 20- and 6-minute deadlines")
	var legacy_payload: Dictionary = payload(4,false)
	var legacy: Dictionary = BRIEF.from_offer({"case_id":"advanced-saas-priority","saas_priority_payload":legacy_payload})
	check(bool(legacy.get("available",false)) and int(legacy.get("rebuild_minutes",-1)) == 0, "legacy frozen offers without a recovery plan remain readable without invented connector work")
	check(BRIEF.from_offer({"case_id":"ordinary-case"}).is_empty(), "unrelated offers do not receive this brief")
	check(not bool(BRIEF.from_offer({"case_id":"advanced-saas-priority"}).get("available",true)), "a priority offer missing its provenance payload is explicitly unavailable")
	check(not bool(BRIEF.from_context({"contract":{"case_id":"advanced-saas-priority"},"accepted":true,"advanced":{}}).get("available",true)), "a broken saved context is unknown instead of a zero-cost success")

	var model: Dictionary = ENGINE.create_followup(original_payload)
	var context := context_for(model)
	var before := encoded(context)
	var initial: Dictionary = BRIEF.from_context(context)
	check(bool(initial.get("available",false)) and not bool(initial.get("preview",true)) and str(initial.get("clock_label","")) == "対応経過", "saved accepted work uses the response elapsed-time label")
	check(encoded(context) == before, "saved-context projection does not change advanced or work data")
	var result: Dictionary = ENGINE.act(model,"toggle_background",{"enabled":false})
	model = result.get("state",model)
	result = ENGINE.act(model,"rebuild_connector")
	model = result.get("state",model)
	result = ENGINE.act(model,"configure",{"queue_id":"dispatch","key":"scope","value":"linked"})
	model = result.get("state",model)
	result = ENGINE.act(model,"run_queue",{"queue_id":"dispatch"})
	model = result.get("state",model)
	var work_costs := {"usage_cost":0,"impact_cost":0,"assistant_runs":0}
	var received_context := context_for(model,work_costs)
	var received: Dictionary = BRIEF.from_context(received_context)
	by_id.clear()
	for queue in received.get("queues",[]): by_id[str(queue.get("id",""))] = queue
	check(bool(received.get("available",false)) and int(by_id.get("dispatch",{}).get("received_count",-1)) == 3 and bool(by_id.get("dispatch",{}).get("received",false)), "a saved queue receipt reports only its three receipt-backed jobs")
	check(bool(by_id.get("dispatch",{}).get("current",false)) and int(received.get("manual_fee",0)) == 900 and int(received.get("manual_remaining",-1)) == 1, "current state comes from the engine view and connector recovery terms come from the saved model")

	model = ENGINE.create_followup(original_payload)
	var overdue_impact: int = ENGINE.advance(model,23)
	var overdue_context := context_for(model,{"usage_cost":0,"impact_cost":6000,"assistant_runs":0,"business_cost":5400})
	var overdue: Dictionary = BRIEF.from_context(overdue_context)
	by_id.clear()
	for queue in overdue.get("queues",[]): by_id[str(queue.get("id",""))] = queue
	check(overdue_impact == 11400 and bool(overdue.get("available",false)) and int(overdue.get("loss_cost",-1)) == 5400 and int(overdue.get("impact_cost",-1)) == 6000, "late queue losses remain distinct from the two scheduled 3,000-yen sync impacts")
	check(bool(by_id.get("dispatch",{}).get("late",false)) and bool(by_id.get("claims",{}).get("late",false)) and int(by_id.get("claims",{}).get("remaining",-1)) == 0, "elapsed work marks both authored deadlines late without recomputing a fake receipt")

	print("PRIORITY_BUSINESS_BRIEF ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
