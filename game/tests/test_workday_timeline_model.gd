extends SceneTree

const MODEL = preload("res://scripts/workday_timeline_model.gd")
const BUSINESS = preload("res://scripts/priority_business_brief.gd")
const PRIORITY = preload("res://scripts/saas_priority.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func find_row(result: Dictionary, key: String) -> Dictionary:
	for row in result.get("rows", []):
		if str(row.get("key", "")) == key: return row
	return {}

func find_marker(row: Dictionary, id: String) -> Dictionary:
	for marker in row.get("markers", []):
		if str(marker.get("id", "")) == id: return marker
	return {}

func priority_payload(round_number: int) -> Dictionary:
	return {
		"source_contract_id":"PRIOR-SOURCE-%d" % round_number,
		"source_day":round_number,
		"client":"北斗物流",
		"round":round_number,
		"approved_originals":[
			{"id":"APPROVAL-%d" % round_number,"action":"consent_review","status":200,"data":{}},
			{"id":"RECEIPT-%d" % round_number,"action":"run_business","status":200,"data":{"receipt_id":"PRIOR-RECEIPT-%d" % round_number}},
			{"id":"REPORT-%d" % round_number,"action":"submit_report","status":200,"data":{}}
		],
		"prior_result":{"loss_cost":0},
		"recovery_plan":PRIORITY.plan(round_number)
	}

func run() -> void:
	var now := 20 * 1440 + 552 # DAY20 09:12
	var priority_model: Dictionary = PRIORITY.create_followup(priority_payload(3))
	var priority_context := {"accepted":true,"contract":{"case_id":"advanced-saas-priority","client":"北斗物流"},"advanced":priority_model,"work":{"priority_company_clock_anchor_minute":now-30,"priority_company_clock_anchor_elapsed":0}}
	var actual_business: Dictionary = BUSINESS.from_context(priority_context)
	var state := {
		"day":20,"current_contract_id":"priority-1","accepted":true,
		"contract":{"case_id":"advanced-saas-priority","client":"北斗物流"},
		"work":{"priority_company_clock_anchor_minute":now,"priority_company_clock_anchor_elapsed":0},
		"advanced":priority_model.duplicate(true),
		"contract_contexts":{
			"priority-1":{"accepted":true,"contract":{"case_id":"advanced-saas-priority","client":"北斗物流"},"advanced":priority_model.duplicate(true),"work":{"priority_company_clock_anchor_minute":now-30,"priority_company_clock_anchor_elapsed":0}}
		}
	}
	var snapshot := {
		"day":20,"clock_minute":552,
		"jobs":[
			{"key":"contract:backup:0","id":"backup","contract_id":"backup","client":"北斗運送","title":"通常backup","kind":"normal","status":"working","completed":false,"draft":false,"fee":1200,"target":0,"deadline":{"absolute":20*1440+705,"text":"DAY20 11:45"}},
			{"key":"contract:priority-1:0","id":"priority-1","contract_id":"priority-1","client":"北斗物流","title":"緊急対応","kind":"emergency","status":"pending","completed":false,"draft":false,"fee":5000,"target":0,"deadline":{"absolute":20*1440+672,"text":"DAY20 11:12"},"business":actual_business}
		],
		"people":[{"id":"haru","name":"遥","workload":{"jobs":[{"id":"w1","kind":"normal","contract_id":"backup","target_index":0,"status":"working","start_day":20,"start_minute":552,"finish_day":20,"finish_minute":564,"risk":"on_track"},{"id":"wrong-target","kind":"normal","contract_id":"backup","target_index":1,"status":"queued","start_day":20,"start_minute":564,"finish_day":20,"finish_minute":576,"risk":"on_track"}]}}]
	}
	var state_before := JSON.stringify(state)
	var snapshot_before := JSON.stringify(snapshot)
	var result: Dictionary = MODEL.build(state, snapshot)
	var backup := find_row(result, "contract:backup:0")
	var priority := find_row(result, "contract:priority-1:0")
	check(bool(result.get("available", false)) and int(result.get("now_absolute", -1)) == now and int(result.get("axis_start", -1)) == now, "uses one absolute company-minute axis rooted at current clock")
	check(int(backup.get("deadline_absolute", -1)) == 20*1440+705 and backup.get("segments", []).size() == 1, "normal delivery deadline and only its exact contract-target forecast appear")
	check(backup.segments[0].get("known", false) and int(backup.segments[0].finish_absolute) == 20*1440+564, "employee completion forecast remains a work segment, not delivery completion")
	check(priority.get("markers", []).size() == 3, "priority delivery and two independent business intake deadlines appear")
	var claims: Dictionary = find_marker(priority, "claims")
	var dispatch: Dictionary = find_marker(priority, "dispatch")
	check(bool(actual_business.get("available", false)) and str(claims.kind) == "business" and int(claims.absolute) == now+6 and int(claims.late_cost) == 4500 and not bool(claims.received), "actual business brief schema maps round deadline and potential cost")
	check(int(dispatch.absolute) == now+20 and int(dispatch.late_cost) == 900, "second priority deadline uses the same anchor and authored round-three timing")
	check(int(result.get("axis_end", -1)) == now+180, "mixed delivery deadlines extend the axis to a rounded three-hour span")
	check(JSON.stringify(state) == state_before and JSON.stringify(snapshot) == snapshot_before, "build is deeply read-only")
	var handoff_snapshot: Dictionary = snapshot.duplicate(true)
	handoff_snapshot.jobs[0].status = "pending"
	handoff_snapshot.jobs[0].handoff = {"receipts":[{"member":"haru"}],"acceptance":{"state":"unchecked"}}
	handoff_snapshot.jobs[0].target_count = 2
	handoff_snapshot.jobs[0].target_name = "本社"
	var handoff := find_row(MODEL.build(state, handoff_snapshot), "contract:backup:0")
	check(str(handoff.status_label) == "引継ぎ待ち" and str(handoff.title).ends_with(" / 本社"), "completed employee work is a handoff and same-contract targets remain identifiable")
	var later_snapshot: Dictionary = snapshot.duplicate(true)
	later_snapshot.clock_minute = 558
	var late_model: Dictionary = priority_model.duplicate(true)
	PRIORITY.advance(late_model, 7)
	later_snapshot.jobs[1].business = BUSINESS.from_context({"accepted":true,"contract":{"case_id":"advanced-saas-priority","client":"北斗物流"},"advanced":late_model,"work":{"saas_costs":{"usage_cost":0,"impact_cost":0,"assistant_runs":0,"business_cost":4500}}})
	var later: Dictionary = MODEL.build(state, later_snapshot)
	var later_claims: Dictionary = find_marker(find_row(later, "contract:priority-1:0"), "claims")
	check(int(later.now_absolute) == now+6 and int(later_claims.absolute) == now+6 and bool(later_claims.late), "advancing company time moves now while actual priority view keeps its absolute SLA and late state")

	var legacy_state := {"day":20,"contract_contexts":{"priority-legacy":{"contract":{"case_id":"advanced-saas-priority"},"work":{}}}}
	var legacy_snapshot := {"day":20,"clock_minute":552,"jobs":[{"key":"legacy","id":"priority-legacy","contract_id":"priority-legacy","kind":"emergency","completed":false,"draft":false,"business":{"available":true,"queues":[{"id":"claims","label":"返金","deadline":6,"late_cost":4500,"loss_cost":0,"late":false,"received":false}]}}]}
	var legacy: Dictionary = MODEL.build(legacy_state, legacy_snapshot)
	var legacy_markers: Array = find_row(legacy, "legacy").get("markers", [])
	check(legacy_markers.size() == 1 and not bool(legacy_markers[0].get("known", true)) and int(legacy_markers[0].get("absolute", 0)) == -1 and int(legacy_markers[0].get("relative_minute", -1)) == 6, "missing legacy clock anchor keeps relative SLA visible but absolute time unknown")
	var short_only := MODEL.build({}, {"day":20,"clock_minute":552,"jobs":[{"key":"short","kind":"emergency","completed":false,"draft":false,"business":actual_business}],"people":[]})
	check(int(short_only.axis_end) == now+60, "a short-deadline-only case keeps a minimum one-hour readable axis")
	var long_only := MODEL.build({}, {"day":20,"clock_minute":552,"jobs":[{"key":"long","kind":"normal","completed":false,"draft":false,"deadline":{"absolute":now+500,"text":"far"}}],"people":[]})
	check(int(long_only.axis_end) == now+360, "far deadlines stay visible beyond the six-hour axis edge without stretching the timeline")

	var done_snapshot := {"day":20,"clock_minute":552,"jobs":[{"key":"done","id":"done","contract_id":"done","kind":"normal","completed":true,"draft":false,"deadline":{"absolute":20*1440+600,"text":"past"}}],"people":[{"id":"haru","workload":{"jobs":[{"kind":"normal","contract_id":"done","target_index":0,"status":"done","start_day":20,"start_minute":540,"finish_day":20,"finish_minute":550,"risk":"on_track"}]}}]}
	var done := find_row(MODEL.build({"day":20}, done_snapshot), "done")
	check(int(done.get("deadline_absolute", 0)) == -1 and done.get("markers", []).is_empty() and done.get("segments", []).is_empty(), "completed jobs are excluded from live timeline tracking")

	for failure in failures: push_error("WORKDAY_TIMELINE_MODEL: " + failure)
	print("WORKDAY_TIMELINE_MODEL failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
