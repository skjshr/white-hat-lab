extends SceneTree
## Isolated model regression. Prior originals also come from public model work;
## no player save, successful world, receipt or observation is injected.
const MODEL = preload("res://scripts/saas_ai_handoff.gd")
const PREVIOUS = preload("res://scripts/saas_ai_preflight.gd")
var failures: Array[String] = []
var previous: Dictionary = {}
var previous_json := ""
var initial: Dictionary = {}
var world: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_AI_HANDOFF: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func perform(operation: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = MODEL.act(world, operation, args)
	if bool(result.get("changed", false)): world = result.get("state", {})
	return result

func latest(s: Dictionary, operation: String) -> Dictionary:
	var found: Dictionary = {}
	for record in s.get("records", []):
		if str(record.get("action", "")) == operation: found = record
	return found

func project() -> Dictionary:
	var before := encoded(world)
	var data: Dictionary = MODEL.view(world).get("handoff", {})
	check(not data.is_empty() and encoded(world) == before and encoded(MODEL.view(world).get("handoff", {})) == encoded(data), "repeated viewing leaves source originals, time, costs, delivery bags and reports unchanged")
	return data

func source_from_previous_work() -> void:
	previous = PREVIOUS.create()
	for key in ["customers","external"]: previous = PREVIOUS.act(previous,"configure",{"key":key,"enabled":false}).state
	previous = PREVIOUS.act(previous,"run_business").state
	var normal: Dictionary = latest(previous,"run_business").duplicate(true)
	var probe: Dictionary = PREVIOUS.act(previous,"probe_boundaries"); previous = probe.state
	previous = PREVIOUS.act(previous,"collect_audit").state
	var ids: Array = ["AI-301",str(normal.id),str(latest(previous,"collect_audit").id)]
	ids.append_array(probe.data.record_ids)
	var submitted: Dictionary = PREVIOUS.act(previous,"submit_report",{"record_ids":ids}); previous = submitted.state
	check(bool(submitted.get("ok", false)) and PREVIOUS.checks(previous).all(func(row): return bool(row.get("passed", false))), "the prior review earns its approval, business receipt and submitted report through the original model")
	previous_json = encoded(previous)
	var payload := {"source_contract_id":"qa-completed-ai-review","source_day":4,"client":"北斗物流","approved_originals":[previous.records[0].duplicate(true),normal,latest(previous,"submit_report").duplicate(true)],"prior_result":{"exported_rows":0,"loss_cost":0,"receipt_id":str(previous.invoice.receipt_id)}}
	initial = MODEL.create_followup(payload)
	check(not initial.is_empty() and encoded(initial.handoff.source) == encoded(payload) and initial.records.filter(func(row): return str(row.action) == "baseline_reference").size() == 3, "new handoff freezes all three earned originals and the previous customer result")
	var incomplete := payload.duplicate(true); incomplete.approved_originals.pop_back()
	check(MODEL.create_followup(incomplete).is_empty() and MODEL.act(previous,"wait").get("changed", false) == false and encoded(previous) == previous_json, "missing source originals and a previous model cannot become a new handoff world")

func current_report() -> Dictionary:
	check(bool(perform("collect_audit").get("ok", false)), "collect the actual current originals and losses")
	var ids: Array = project().get("report", {}).get("required_record_ids", [])
	return perform("submit_report",{"record_ids":ids})

func scope_and_receipt() -> void:
	world = initial.duplicate(true)
	var data := project()
	check(data.get("business", {}).get("jobs", []).size() == 3 and data.get("flow", {}).get("events", []).is_empty() and not MODEL.checks(world).all(func(row): return bool(row.passed)), "three pending delivery bags are visible without claiming an observation or successful acceptance")
	var failed := perform("run_business")
	check(not bool(failed.get("ok", true)) and failed.get("data", {}).get("record", {}).get("data", {}).get("jobs", []).is_empty() and str(world.invoice.receipt_id).is_empty(), "an unopened dispatch gate cannot invent received delivery bags")
	perform("configure",{"key":"partner_dispatch","enabled":true})
	var broad := perform("run_business")
	check(bool(broad.get("ok", false)) and world.invoice.accepted_jobs.size() == 3 and not bool(MODEL.checks(world)[3].passed), "broad access can run the business while still failing the minimum-scope requirement")
	var accepted := encoded(world.invoice.accepted_jobs); var receipt := str(world.invoice.receipt_id)
	perform("configure",{"key":"contacts","value":"linked"})
	perform("configure",{"key":"partner_archive","enabled":false})
	var probe := perform("probe_boundaries")
	check(int(probe.get("data", {}).get("read_status", 0)) == 403 and int(probe.get("data", {}).get("write_status", 0)) == 403 and world.egress.exported_rows.is_empty(), "linked contacts and the dispatch-only recipient deny unrelated reads and archive writes independently")
	check(bool(perform("run_business").get("ok", false)) and bool(current_report().get("ok", false)) and MODEL.checks(world).all(func(row): return bool(row.passed)), "current boundary originals, three-bag receipt, previous originals and audit permit the normal report")
	var original := encoded(world.report.original)
	MODEL.advance(world, 2)
	check(bool(project().get("report_fresh", false)), "a later blocked scheduled send adds no damage and does not demand a redundant impact supplement")
	perform("configure",{"key":"contacts","value":"off"})
	failed = perform("run_business")
	check(not bool(failed.get("ok", true)) and str(world.invoice.receipt_id) == receipt and encoded(world.invoice.accepted_jobs) == accepted and not bool(project().get("report_fresh", true)), "stopping every contact blocks a recheck but preserves the original accepted bags and exposes stale reporting")
	check(not bool(perform("submit_report",{"record_ids":world.report.original.record_ids}).get("ok", true)) and encoded(world.report.original) == original, "an old successful report cannot certify changed access or overwrite its submitted original")
	world = JSON.parse_string(JSON.stringify(world))
	perform("configure",{"key":"contacts","value":"linked"})
	perform("run_business"); perform("probe_boundaries")
	check(bool(current_report().get("ok", false)) and world.report.supplements.size() == 1 and encoded(world.report.original) == original and encoded(world.invoice.accepted_jobs) == accepted and int(world.handoff.business.loss_cost) == 0, "JSON resume, targeted recovery and current evidence append one supplement while retaining the first receipt and zero loss")
	var before := encoded(world); var duplicate := perform("run_business")
	check(bool(duplicate.get("ok", false)) and not bool(duplicate.get("changed", true)) and encoded(world) == before, "the already-verified receipt cannot generate duplicate work or delivery")
	var ids: Array = world.records.filter(func(row): return str(row.action) in ["consent_review","baseline_reference"]).map(func(row): return str(row.id))
	var organized := perform("organize_records",{"mode":"assistant","record_ids":ids})
	var lanes: Dictionary = project().organization.comparison.lanes
	check(int(organized.get("usage_cost", 0)) == 300 and lanes.values().all(func(lane): return str(lane.get("state", "")) == "unknown"), "the assistant charges only for selected originals and cannot import unselected successful measurements")
	before = encoded(world); ids.reverse()
	check(bool(perform("organize_records",{"mode":"assistant","record_ids":ids}).get("ok", false)) and encoded(world) == before, "the same selected set in another order reuses its saved organization for free")

func irreversible_egress() -> void:
	world = initial.duplicate(true)
	check(MODEL.advance(world,8) == 3000 and world.egress.exported_rows.size() == 6, "the all-contacts archive schedule really copies six contacts at minute eight")
	var first: Dictionary = project().flow.events[0].duplicate(true)
	perform("configure",{"key":"partner_archive","enabled":false})
	check(MODEL.advance(world,7) == 900 and world.egress.exported_rows.size() == 6 and int(world.egress.impact_cost) == 3000 and int(world.handoff.business.loss_cost) == 900, "archive closure stops the second send but cannot erase earlier copies or the missed business deadline")
	var stopped := project()
	check(encoded(stopped.flow.events[0]) == encoded(first) and int(stopped.flow.events[1].read.rows) == 6 and int(stopped.flow.events[1].write.status) == 403, "later current policy never rewrites the historical successful read and archive send")
	world = JSON.parse_string(JSON.stringify(world))
	perform("configure",{"key":"contacts","value":"linked"}); perform("configure",{"key":"partner_dispatch","enabled":true})
	perform("run_business"); perform("probe_boundaries")
	check(bool(current_report().get("ok", false)) and MODEL.checks(world).all(func(row): return bool(row.passed)) and int(world.egress.impact_cost) == 3000 and int(world.handoff.business.loss_cost) == 900 and world.egress.exported_rows.all(func(row): return not str(row.get("record_id", "")).is_empty()), "delayed repair can deliver only with the actual loss originals and keeps separate irreversible compensation")
	check(MODEL.advance(world,20) == 0 and int(world.egress.impact_cost) == 3000 and world.records.filter(func(row): return str(row.action) == "summary_overdue").size() == 1, "later work cannot send or charge a scheduled incident twice")
	world = initial.duplicate(true)
	perform("configure",{"key":"contacts","value":"linked"})
	check(MODEL.advance(world,7) == 1500 and world.egress.exported_rows.size() == 3, "even the three authorized contacts are a real leak when sent to the unauthorized archive path")
	world = initial.duplicate(true)
	perform("configure",{"key":"contacts","value":"off"})
	check(MODEL.advance(world,7) == 0 and world.egress.exported_rows.is_empty() and not bool(perform("run_business").get("ok", true)), "denying all contact reads prevents the archive copy while leaving required normal work unfinished")

func run() -> void:
	source_from_previous_work()
	if not initial.is_empty(): scope_and_receipt(); irreversible_egress()
	check(encoded(previous) == previous_json and not previous.has("handoff"), "the old accepted model and all of its source records remain unchanged after new work")
	print("SAAS_AI_HANDOFF_TEST_PASS" if failures.is_empty() else "SAAS_AI_HANDOFF_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
