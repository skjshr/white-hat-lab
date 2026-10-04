extends SceneTree

const Roadmap = preload("res://scripts/company_roadmap.gd")
var failures: Array[String] = []
var count := 0

func check(condition: bool, label: String) -> void:
	count += 1
	if not condition: failures.append(label); print("FAIL: ", label)

func goal(state: Dictionary, id: String) -> Dictionary:
	for item in Roadmap.goals(state):
		if str(item.id) == id: return item
	return {}

func row(id: String, family: String, client: String) -> Dictionary:
	return {"id":id,"case_id":"","copy_id":"share","client":client,"work_family":family,"checks":[{"passed":true}]}

func _init() -> void:
	var state := {"day":1,"cash":5000,"history":[],"company_cycle":{"earned_goals":{}},"equipment":[],"delivery_orders":[],"customer_relations":{},"care_agreements":{},"maintenance_targets":{},"staff":{},"staff_payroll":{"due":[]},"retainer_daily":{}}
	check(not bool(goal(state,"first_delivery").met_now), "starting cash is not a delivery achievement")
	state.history.append({"id":"incomplete","checks":[{"passed":false}]})
	check(not bool(goal(state,"first_delivery").met_now), "failed checks are not a verified delivery")
	state.history.append(row("share","permissions","つばさ文具"))
	check(bool(goal(state,"first_delivery").met_now), "actual verified receipt qualifies")
	check(not bool(goal(state,"first_delivery").complete), "qualified milestone is not earned until persisted")
	state.company_cycle.earned_goals = Roadmap.earned_after_save(state)
	check(bool(goal(state,"first_delivery").complete), "persisted achievement stays earned")
	state.history.append({"id":"repeat","case_id":"service-0-case-0","client":"つばさ文具","checks":[{"passed":true}]})
	check(int(goal(state,"independent_lab").requirements[1].current) == 1, "story and career Samba are one service family")
	state.delivery_orders.append({"id":"monitor","status":"ready"})
	check(int(goal(state,"independent_lab").requirements[2].current) == 0, "uninstalled delivery box gives no investment milestone")
	state.equipment.append("plant")
	check(int(goal(state,"independent_lab").requirements[2].current) == 0, "decoration is not operational equipment")
	state.equipment.append("monitor")
	state.history.append(row("backup","backup","青葉デザイン"))
	check(bool(goal(state,"independent_lab").met_now), "two real services, customers and installed equipment qualify with working capital")
	state.cash = 2999
	check(not bool(goal(state,"independent_lab").met_now), "investment cannot hide insufficient operating cash")
	state.cash = 5000
	state.company_cycle.earned_goals = Roadmap.earned_after_save(state)
	state.cash = 0; state.history = []
	check(bool(goal(state,"independent_lab").complete), "earned token survives financial setbacks and bounded history retention")
	state.retainer_daily = {"1":{"maintenance_earned":200,"maintenance_missed":0}}
	check(int(goal(state,"sustainable_team").requirements[2].current) == 0, "legacy recurring income does not invent performed inspections")
	state.retainer_daily["2"] = {"maintenance_earned":200,"maintenance_completed":2,"maintenance_missed":0}
	state.retainer_daily["3"] = {"maintenance_earned":200,"maintenance_completed":1,"maintenance_missed":1}
	check(int(goal(state,"sustainable_team").requirements[2].current) == 1, "only actually completed inspection days without misses count")
	state.staff_payroll.due = [{"amount":600,"paid_amount":0,"expense_recorded":true}]
	check(not bool(goal(state,"sustainable_team").requirements[4].complete), "unpaid settled payroll blocks sustainability")
	var before := JSON.stringify(state)
	Roadmap.goals(state); Roadmap.earned_after_save(state)
	check(JSON.stringify(state) == before, "render and prospective save evaluation are read-only")
	test_trimmed_receipt_progress()
	print("COMPANY_ROADMAP ", count, " assertions / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func test_trimmed_receipt_progress() -> void:
	# Explicit persisted-journal fixture. No completed records are inferred from
	# cash, equipment or a deleted legacy receipt that has no durable journal.
	var state := {"day":30,"cash":5000,"history":[],"equipment":[],"company_cycle":{"earned_goals":{},"completed_cases":{"service-0-case-0":true,"service-1-case-0":true}},"customer_relations":{}}
	var before := JSON.stringify(state)
	var current := goal(state, "independent_lab")
	check(int(current.requirements[0].current) == 2 and int(current.requirements[1].current) == 2, "verified durable cases preserve clients and families after receipt trimming")
	check(int(goal(state,"first_delivery").requirements[0].current) == 2, "durable cases each retain one verified delivery")
	check(not bool(current.met_now) and not bool(current.complete), "missing equipment still blocks unearned goal after history trimming")
	check(JSON.stringify(state) == before, "durable aggregation never backfills or modifies the receipt journal")
	state.equipment = ["monitor"]
	check(bool(goal(state,"independent_lab").met_now) and not bool(goal(state,"independent_lab").complete), "later real investment can qualify previously delivered families without awarding before save")
	state.history.append({"id":"recent-a","case_id":"service-0-case-0","client":"つばさ文具","work_family":"permissions","checks":[{"passed":true}]})
	check(int(goal(state,"first_delivery").requirements[0].current) == 2, "surviving receipt and durable case do not count the same delivery twice")
	state.history.append({"id":"recent-b","case_id":"service-0-case-0","client":"つばさ文具","work_family":"permissions","checks":[{"passed":true}]})
	check(int(goal(state,"first_delivery").requirements[0].current) == 3, "separate surviving repeat deliveries retain their real count")
	state.history = []
	state.company_cycle.completed_cases = {"service-0-case-0":false,"service-1-case-0":1,"not-in-catalog":true}
	check(int(goal(state,"first_delivery").requirements[0].current) == 0, "false, nonboolean and unknown completion markers give no delivery credit")
	current = goal(state,"independent_lab")
	check(int(current.requirements[0].current) == 0 and int(current.requirements[1].current) == 0, "false and unknown cases cannot create clients or service families")
	state.company_cycle = {"earned_goals":{}}
	check(not bool(goal(state,"first_delivery").met_now), "missing legacy history and journal do not invent a past delivery")
