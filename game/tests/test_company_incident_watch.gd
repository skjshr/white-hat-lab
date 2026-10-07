extends SceneTree
## Focused read-only and resume tests for the company-wide priority incident rail.

const WATCH = preload("res://scripts/company_incident_watch.gd")
const BRIEF = preload("res://scripts/priority_business_brief.gd")
const ENGINE = preload("res://scripts/saas_priority.gd")
const PRIOR = preload("res://scripts/saas_ai_handoff.gd")
const CASE_ID := "advanced-saas-priority"

class FakeGame:
	extends RefCounted
	var state: Dictionary = {}

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("COMPANY_INCIDENT_WATCH: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func payload(round_number: int) -> Dictionary:
	var previous: Dictionary = PRIOR.create()
	previous = PRIOR.act(previous, "configure", {"key":"contacts","value":"linked"}).state
	previous = PRIOR.act(previous, "configure", {"key":"partner_archive","enabled":false}).state
	previous = PRIOR.act(previous, "configure", {"key":"partner_dispatch","enabled":true}).state
	previous = PRIOR.act(previous, "run_business").state
	previous = PRIOR.act(previous, "probe_boundaries").state
	previous = PRIOR.act(previous, "collect_audit").state
	var report: Dictionary = PRIOR.act(previous, "submit_report", {"record_ids":PRIOR.view(previous).handoff.report.required_record_ids})
	previous = report.state
	var approvals: Array = []
	for row in previous.records:
		if str(row.get("action", "")) == "consent_review": approvals.append(_flat(row))
	var originals: Array = approvals
	for action in ["run_business", "submit_report"]:
		for row in previous.records:
			if str(row.get("action", "")) == action:
				originals.append(_flat(row))
				break
	return {
		"source_contract_id":"watch-source",
		"source_day":4,
		"client":"北斗物流",
		"round":round_number,
		"approved_originals":originals,
		"prior_result":{"loss_cost":0},
		"recovery_plan":ENGINE.plan(round_number)
	}

func _flat(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	var data_value: Variant = result.get("data", {})
	if data_value is Dictionary:
		data_value.erase("records")
		data_value.erase("events")
	return result

func context_for(model: Dictionary, contract_id: String, target_index: int = 0, title: String = "緊急対応") -> Dictionary:
	var business_loss := 0
	for queue in model.get("priority", {}).get("queues", []): business_loss += int(queue.get("loss_cost", 0))
	var work_costs := {"usage_cost":0,"impact_cost":int(model.get("egress", {}).get("impact_cost", 0)),"assistant_runs":0}
	if business_loss > 0: work_costs.business_cost = business_loss
	var manual_usage := int(model.get("priority", {}).get("recovery", {}).get("manual_usage_cost", 0))
	if manual_usage > 0: work_costs.manual_cost = manual_usage
	return {
		"id":contract_id,
		"accepted":true,
		"completed":false,
		"target_index":target_index,
		"contract":{"case_id":CASE_ID,"client":"北斗物流","title":title},
		"advanced":model,
		"work":{"minutes":int(model.get("elapsed_minutes", 0)),"saas_costs":work_costs}
	}

func add_elapsed(context: Dictionary, minutes: int) -> Dictionary:
	var copy := context.duplicate(true)
	var model: Dictionary = copy.advanced
	ENGINE.advance(model, minutes)
	var new_loss := 0
	for queue in model.get("priority", {}).get("queues", []): new_loss += int(queue.get("loss_cost", 0))
	copy.advanced = model
	copy.work.minutes = int(model.get("elapsed_minutes", 0))
	copy.work.saas_costs.impact_cost = int(model.get("egress", {}).get("impact_cost", 0))
	copy.work.saas_costs.usage_cost = 0
	copy.work.saas_costs.assistant_runs = 0
	if new_loss > 0: copy.work.saas_costs.business_cost = new_loss
	return copy

func perform(model: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = ENGINE.act(model, action, args)
	return result.get("state", model) if bool(result.get("changed", false)) else model

func receive_both_queues() -> Dictionary:
	var model: Dictionary = ENGINE.create_followup(payload(4))
	model = perform(model, "toggle_background", {"enabled":false})
	for index in 5: model = perform(model, "wait")
	model = perform(model, "rebuild_connector")
	for id in ["dispatch", "claims"]:
		var approved_recipient := ""
		for queue in model.get("priority", {}).get("queues", []):
			if str(queue.get("id", "")) == id: approved_recipient = str(queue.get("approved_recipient", ""))
		for setting in [["scope", "linked"], ["recipient", approved_recipient]]:
			model = perform(model, "configure", {"queue_id":id,"key":setting[0],"value":setting[1]})
		model = perform(model, "run_queue", {"queue_id":id})
	return model

func run() -> void:
	var active_model: Dictionary = ENGINE.create_followup(payload(4))
	var older_model: Dictionary = ENGINE.create_followup(payload(3))
	var inactive_late := add_elapsed(context_for(older_model, "case-B", 1, "別件の緊急対応"), 8)
	var state := {
		"accepted":true,
		"current_contract_id":"case-A",
		"completed_ids":["case-D"],
		"target_index":2,
		"contract":{"case_id":CASE_ID,"client":"北斗物流","title":"現在対応中"},
		"advanced":active_model,
		"work":{"minutes":0,"saas_costs":{"usage_cost":0,"impact_cost":0,"assistant_runs":0}},
		"contract_contexts":{
			"case-A":{"accepted":true,"completed":true,"target_index":8,"contract":{"case_id":CASE_ID,"title":"古い重複値"},"advanced":{},"work":{}},
			"case-B":inactive_late,
			"case-C":{"accepted":true,"completed":true,"contract":{"case_id":CASE_ID},"advanced":active_model,"work":{"saas_costs":{"usage_cost":0,"impact_cost":0,"assistant_runs":0}}},
			"case-D":{"accepted":true,"completed":false,"contract":{"case_id":CASE_ID},"advanced":active_model,"work":{"saas_costs":{"usage_cost":0,"impact_cost":0,"assistant_runs":0}}},
			"case-E":{"accepted":true,"completed":false,"target_index":4,"contract":{"case_id":CASE_ID,"title":"保存内容を確認"},"advanced":{},"work":{}}
		}
	}
	var game := FakeGame.new()
	game.state = state
	var before := encoded(game.state)
	var active_projection: Dictionary = WATCH.snapshot(game)
	check(bool(active_projection.available) and bool(active_projection.visible) and int(active_projection.open_count) == 3 and int(active_projection.actionable_count) == 2, "accepted incomplete priority contracts include active, inactive and unknown contexts only")
	check(str(active_projection.priority.contract_id) == "case-B" and str(active_projection.priority.queue_id) == "claims" and bool(active_projection.priority.late), "the most overdue unreceived queue outranks the active but less urgent case")
	var by_id: Dictionary = {}
	for incident in active_projection.incidents: by_id[str(incident.contract_id)] = incident
	check(bool(by_id["case-A"].available) and str(by_id["case-A"].title) == "現在対応中" and int(by_id["case-A"].target_index) == 2 and int(by_id["case-A"].elapsed) == 0, "active fields override the same contract's stale saved context")
	check(not bool(by_id["case-E"].available) and int(by_id["case-E"].loss_cost) == -1 and by_id["case-E"].costs == {"available":false} and str(by_id["case-E"].client) == "顧客記録なし", "missing saved advanced data remains unknown instead of zero-loss or customer success")
	check(encoded(game.state) == before, "projection leaves live state, inactive contexts and nested models unchanged")
	var resumed := FakeGame.new()
	resumed.state = JSON.parse_string(JSON.stringify(game.state))
	var resumed_projection: Dictionary = WATCH.snapshot(resumed)
	check(encoded(resumed_projection) == encoded(active_projection), "JSON save-shaped resume preserves selection, urgency and confirmed costs")
	var switched_state: Dictionary = JSON.parse_string(JSON.stringify(game.state))
	var promoted_context: Dictionary = switched_state.contract_contexts["case-B"]
	switched_state.accepted = true
	switched_state.current_contract_id = "case-B"
	switched_state.contract = promoted_context.contract.duplicate(true)
	switched_state.advanced = promoted_context.advanced.duplicate(true)
	switched_state.work = promoted_context.work.duplicate(true)
	switched_state.target_index = promoted_context.target_index
	resumed.state = switched_state
	var switched_projection: Dictionary = WATCH.snapshot(resumed)
	var switched_b_count := 0
	for incident in switched_projection.incidents:
		if str(incident.contract_id) == "case-B":
			switched_b_count += 1
			check(bool(incident.active), "the formerly inactive contract uses its current active projection after switching")
	check(switched_b_count == 1 and int(switched_projection.open_count) == 2, "active/inactive switching never duplicates the same accepted case or retains the old completed context")
	var done_active := FakeGame.new()
	done_active.state = JSON.parse_string(JSON.stringify(game.state))
	done_active.state.completed = true
	check(int(WATCH.snapshot(done_active).open_count) == 2, "an explicitly completed active projection is omitted even if accepted fields remain")

	var received_model: Dictionary = receive_both_queues()
	var received_context := context_for(received_model, "case-received", 3, "受付済み・納品待ち")
	var received_game := FakeGame.new()
	received_game.state = {"accepted":false,"current_contract_id":"","completed_ids":[],"contract_contexts":{"case-received":received_context}}
	var received_watch: Dictionary = WATCH.snapshot(received_game)
	check(bool(received_watch.available) and int(received_watch.open_count) == 1 and int(received_watch.actionable_count) == 0, "fully receipt-backed but undelivered work stays open without a fake pending action")
	check(str(received_watch.priority.contract_id) == "case-received" and str(received_watch.priority.queue_id) == "" and bool(received_watch.priority.undelivered), "when every queue is received, the rail routes to the open contract for delivery review")
	var received_projection: Dictionary = BRIEF.from_context(received_context)
	check(int(received_projection.loss_cost) > 0 and int(received_projection.loss_cost) == int(received_watch.incidents[0].costs.business), "confirmed late business losses remain attached after both queues are received")
	var closed_game := FakeGame.new()
	closed_game.state = {"accepted":false,"current_contract_id":"","completed_ids":["done"],"contract_contexts":{"done":received_context,"complete-flag":context_with_completed(received_context)}}
	var closed: Dictionary = WATCH.snapshot(closed_game)
	check(not bool(closed.available) and int(closed.open_count) == 0 and closed.priority.is_empty(), "delivered ids and completed contexts disappear from the rail")
	var empty_game := FakeGame.new()
	empty_game.state = {"accepted":false,"current_contract_id":"","contract_contexts":{}}
	check(not bool(WATCH.snapshot(empty_game).visible), "no accepted priority work produces a hidden rail")
	print("COMPANY_INCIDENT_WATCH ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func context_with_completed(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["completed"] = true
	return result
