extends SceneTree
## Focused projection test: fixtures are local objects and no game state is saved.

const MODEL = preload("res://scripts/intake_decision_model.gd")
const GAME_SCRIPT = preload("res://scripts/game.gd")

class FakeCompany extends RefCounted:
	var state: Dictionary = {}
	var members: Array = []
	var workloads: Dictionary = {}
	var runtime: Dictionary = {}
	var quote: Dictionary = {}
	var supply: Dictionary = {}
	var capacity := 4

	func clock_minutes() -> int:
		return int(state.get("clock_minutes", -1))

	func contract_capacity() -> int:
		return capacity

	func team_members() -> Array:
		return members.duplicate(true)

	func staff_workload(id: String) -> Dictionary:
		return workloads.get(id, {}).duplicate(true)

	func colleague_runtime_availability(id: String) -> Dictionary:
		return runtime.get(id, {"available":true,"registered":false}).duplicate(true)

	func contract_quote(_offer: Dictionary) -> Dictionary:
		return quote.duplicate(true)

	func offer_operations_preview(_offer: Dictionary) -> Dictionary:
		return supply.duplicate(true)


var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error("INTAKE_DECISION_MODEL: " + label)

func run() -> void:
	_test_company_projection()
	_test_offer_projection()
	_test_real_company_save_if_provided()
	print("INTAKE_DECISION_MODEL_TEST_PASS" if failures.is_empty() else "INTAKE_DECISION_MODEL_TEST_FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _fixture() -> FakeCompany:
	var g := FakeCompany.new()
	g.state = {
		"day":13,
		"clock_minutes":552,
		"career_mode":true,
		"current_contract_id":"priority-active",
		"accepted":true,
		"contract":{"case_id":"advanced-saas-priority","client":"北斗物流","title":"配送優先対応"},
		"contract_plan":"standard",
		"completed_ids":["done-1"],
		"contract_contexts":{
			"priority-active":{"accepted":true,"completed":false,"contract":{"case_id":"advanced-saas-priority","client":"北斗物流","title":"古い複製"}},
			"normal-open":{"accepted":true,"completed":false,"contract":{"case_id":"service-0-case-0","client":"白波ホテル","title":"通常調査"}},
			"done-1":{"accepted":true,"completed":true,"contract":{"case_id":"advanced-old","client":"完了先","title":"完了"}}
		},
		"care_agreements":{"pending":{"pending":true,"active":false},"active":{"pending":false,"active":true}},
		"maintenance_jobs":[
			{"id":"today-pending","day":13,"status":"pending","client":"白波ホテル","remaining":12.0,"total":12.0},
			{"id":"today-working","day":13,"status":"working","client":"稼働中","remaining":5.0,"total":12.0},
			{"id":"yesterday-pending","day":12,"status":"pending","client":"昨日分","remaining":12.0,"total":12.0}
		],
		"staff":{}
	}
	g.members = [
		{"id":"aya","name":"綾","role":"aya","hired":false},
		{"id":"ren","name":"蓮","role":"ren","hired":false},
		{"id":"mio","name":"美緒","role":"maintenance","hired":true}
	]
	g.workloads = {
		"aya":{"capacity_minutes":-1.0,"available_minutes":-1.0,"reserved_minutes":24.0,"used_minutes":0.0,"jobs":[
			{"id":"job-running","contract_id":"normal-open","client":"","kind":"normal","status":"working","start_day":13,"start_minute":552,"finish_day":13,"finish_minute":564,"remaining_minutes":12.0,"risk":"on_track","blocked_reason":""},
			{"id":"job-waiting","contract_id":"normal-open","kind":"normal","status":"queued","start_day":13,"start_minute":564,"finish_day":13,"finish_minute":576,"remaining_minutes":12.0,"risk":"late","blocked_reason":""}
		]},
		"ren":{"capacity_minutes":-1.0,"available_minutes":-1.0,"jobs":[]},
		"mio":{"capacity_minutes":8.0,"available_minutes":-1.0,"blocked_reason":"npc_returning","jobs":[
			{"id":"job-unknown","contract_id":"normal-open","kind":"maintenance","status":"queued","start_day":-1,"start_minute":-1,"finish_day":-1,"finish_minute":-1,"remaining_minutes":8.0,"risk":"blocked","blocked_reason":"npc_returning"}
		]}
	}
	g.runtime = {"aya":{"available":true,"registered":false},"ren":{"available":true,"registered":false},"mio":{"available":false,"registered":true}}
	g.quote = {"estimated_fee":5400,"costs":700,"net":4700,"invoice_total":5400,"budget":40.0,"deadline_text":"09:40","reference_fee":6000,"budget_limit":7000}
	g.supply = {"sku":"backup-unit","required":2,"own_required":1,"available":0,"inbound":1,"shortage":1,"purchase_cost":800}
	return g

func _test_company_projection() -> void:
	var g := _fixture()
	var state_before := JSON.stringify(g.state)
	var workload_before := JSON.stringify(g.workloads)
	var view: Dictionary = MODEL.company(g)
	check(int(view.day) == 13 and int(view.clock_minute) == 552 and str(view.clock_text) == "09:12", "company time comes from the current state")
	check(int(view.open_contracts) == 2 and int(view.contract_capacity) == 4 and int(view.free_contract_slots) == 2, "open and completed contracts are counted separately")
	check(int(view.pending_care) == 1 and int(view.own_unfinished_count) == 1 and str(view.own_unfinished[0].id) == "priority-active", "today's waiting care jobs and self-handled advanced work remain distinct from agreements and ordinary work")
	var aya := _person(view.people, "aya")
	check(str(aya.work_state) == "working" and aya.jobs.size() == 2, "active and queued work are represented on the colleague timeline")
	check(str(aya.jobs[0].state) == "working" and int(aya.jobs[0].finish_minute) == 564 and bool(aya.jobs[0].time_known), "active job keeps its forecast finish")
	check(str(aya.jobs[0].client) == "白波ホテル" and str(aya.jobs[0].contract_title) == "通常調査", "empty assignment client falls back to its accepted contract context")
	check(str(aya.jobs[1].state) == "waiting" and str(aya.jobs[1].risk) == "late", "queued work is waiting and preserves its lateness risk")
	check(aya.get("capacity_minutes", null) == null and not bool(aya.capacity_known) and aya.get("available_minutes", null) == null, "forecast sentinel -1 is shown as unknown capacity, never infinity")
	var ren := _person(view.people, "ren")
	check(str(ren.work_state) == "standby" and ren.jobs.is_empty(), "a colleague without assigned work is distinct from a queued worker")
	var mio := _person(view.people, "mio")
	check(not bool(mio.runtime_available) and bool(mio.runtime_registered) and str(mio.work_state) == "unknown_time", "runtime unavailability and missing finish time are explicit")
	check(str(mio.jobs[0].state) == "unknown_time" and bool(mio.jobs[0].blocked) and not bool(mio.jobs[0].time_known), "blocked work does not receive a fabricated schedule")
	aya.jobs[0].finish_minute = 0
	view.own_unfinished[0].title = "caller mutation"
	check(JSON.stringify(g.state) == state_before and JSON.stringify(g.workloads) == workload_before, "render projection and caller edits do not mutate source state or forecasts")

func _test_offer_projection() -> void:
	var g := _fixture()
	var regular := {"id":"normal-offer","case_id":"service-0-case-0","category":"operations","client":"白波ホテル","title":"通常作業","targets":2,"target_specs":[{"name":"店舗端末"},{"name":"受付PC"}]}
	var regular_before := JSON.stringify(regular)
	var state_before := JSON.stringify(g.state)
	var ordinary: Dictionary = MODEL.offer(g, regular)
	check(str(ordinary.category) == "operations" and str(ordinary.client) == "白波ホテル" and int(ordinary.target_count) == 2 and ordinary.targets.size() == 2, "offer projection preserves customer, category and work targets")
	check(int(ordinary.fee) == 5400 and int(ordinary.base_cost) == 700 and int(ordinary.profit) == 4700 and int(ordinary.invoice_total) == 5400, "latest quote projects fee, cost, invoice and net")
	check(float(ordinary.deadline_budget_minutes) == 40.0 and str(ordinary.delivery_deadline_text) == "09:40" and str(ordinary.deadline_budget_semantics) == "delivery_deadline_budget" and not ordinary.has("work_minutes"), "quote budget is labeled as delivery timing, never as work duration")
	check(str(ordinary.handling_mode) == "dispatch_after_acceptance" and int(ordinary.supply_shortage) == 1 and int(ordinary.supply_shortage_cost) == 800, "ordinary work is allocated after acceptance and supply shortage is visible")
	var payload := {
		"source_contract_id":"delivered-1",
		"source_day":12,
		"round":1,
		"client":"北斗物流",
		"approved_originals":[
			{"id":"approval-1","status":200,"action":"consent_review","data":{}},
			{"id":"receipt-1","status":200,"action":"run_business","data":{"receipt_id":"receipt-1"}},
			{"id":"report-1","status":200,"action":"submit_report","data":{}}
		]
	}
	var urgent := {"id":"priority-offer","case_id":"advanced-saas-priority","category":"response","client":"北斗物流","title":"優先対応","targets":1,"target_specs":[{"name":"業務キュー"}],"saas_priority_payload":payload}
	var priority: Dictionary = MODEL.offer(g, urgent)
	check(bool(priority.advanced) and str(priority.handling_mode) == "self_after_acceptance", "advanced offer is identified as the player's own post-acceptance work")
	check(bool(priority.priority_business.available) and priority.priority_business.queues.size() == 2, "priority offer derives both business queues from the saved source brief")
	var dispatch := _queue(priority.priority_business.queues, "dispatch")
	var claims := _queue(priority.priority_business.queues, "claims")
	check(int(claims.deadline_minute) == 6 and int(claims.late_compensation) == 4500 and int(dispatch.deadline_minute) == 14 and int(dispatch.late_compensation) == 900 and int(priority.deadline_budget_minutes) == 40, "priority round-one queue deadlines and compensations stay separate from contract delivery budget")
	check(JSON.stringify(g.state) == state_before and JSON.stringify(regular) == regular_before, "offer quotation and priority briefing are read-only")
	ordinary.quote.estimated_fee = 1
	check(JSON.stringify(g.quote.estimated_fee) == "5400" and JSON.stringify(urgent.saas_priority_payload) == JSON.stringify(payload), "returned quote and brief cannot mutate source offer or company data")

func _test_real_company_save_if_provided() -> void:
	var source_path := OS.get_environment("WHL_INTAKE_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		print("INTAKE_DECISION_MODEL_REAL_SAVE_SKIPPED set WHL_INTAKE_SOURCE to baseline-backup-accepted.json")
		return
	var prefix := "user://qa-intake-decision-%s" % OS.get_process_id()
	var save_path := prefix + ".json"
	var paths := [save_path,save_path + ".bak",save_path + ".previous",prefix + ".settings"]
	var source_hash := FileAccess.get_sha256(source_path)
	var source_text := FileAccess.get_file_as_string(source_path)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		check(false, "real-save QA copy can be opened")
		return
	file.store_string(source_text)
	file.close()
	var g = GAME_SCRIPT.new()
	g.name = "IntakeDecisionReadOnlyFixture"
	g.save_path = save_path
	g.backup_path = paths[1]
	g.previous_path = paths[2]
	g.settings_path = paths[3]
	root.add_child(g)
	g.set_process(false)
	if not g.load_game():
		check(false, "real baseline QA copy loads")
		g.queue_free()
		_cleanup(paths)
		return
	var state_before := JSON.stringify(g.state)
	var assignments_before: Dictionary = g._assignments.duplicate(true)
	var view: Dictionary = MODEL.company(g)
	var expected_care := 0
	for raw in g.state.get("maintenance_jobs", []):
		if int(raw.get("day", g.state.day)) == int(g.state.day) and str(raw.get("status", "")) in ["pending", "queued", "paused"]: expected_care += 1
	check(int(view.day) == int(g.state.day) and int(view.clock_minute) == int(g.clock_minutes()), "real save publishes its actual company day and clock")
	check(int(view.open_contracts) == int(g._open_contract_count()) and int(view.contract_capacity) == int(g.contract_capacity()), "real save open count and capacity match existing company APIs")
	check(int(view.pending_care) == expected_care and expected_care == 1, "real save's today-only pending maintenance matches the workday state")
	check(int(view.own_unfinished_count) == 0 and str(g.state.contract.get("case_id", "")).begins_with("service-"), "accepted ordinary case is not mislabeled as an advanced-only self case")
	for member in g.team_members():
		var person := _person(view.people, str(member.id))
		var forecast: Dictionary = g.staff_workload(str(member.id))
		check(person.has("id") and person.jobs.size() == forecast.get("jobs", []).size(), "real member workload mirrors existing staff forecast for " + str(member.id))
		var runtime: Dictionary = g.colleague_runtime_availability(str(member.id))
		check(person.get("runtime_available", null) == runtime.get("available", null) and bool(person.runtime_registered) == bool(runtime.get("registered", false)), "real member runtime availability mirrors Game for " + str(member.id))
	check(JSON.stringify(g.state) == state_before and g._assignments == assignments_before, "real company rendering does not synchronize contexts or mutate assignments")
	check(FileAccess.get_sha256(source_path) == source_hash, "read-only integration fixture remains byte-identical")
	g.queue_free()
	_cleanup(paths)

func _cleanup(paths: Array) -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _person(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id", "")) == id: return row
	return {}

func _queue(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id", "")) == id: return row
	return {}
