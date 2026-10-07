extends SceneTree

const VIEW = preload("res://scripts/care_portfolio_view.gd")
const GAME = preload("res://scripts/game.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func find_client(result: Dictionary, name: String) -> Dictionary:
	for client in result.get("clients", []):
		if str(client.get("client", "")) == name: return client
	return {}

func run() -> void:
	var game = GAME.new()
	root.add_child(game)
	game.set_process(false)
	game._reset_state()
	var day := int(game.state.day)
	game.state.skills.operations = 1
	game.state.equipment = ["monitor", "teamdesk"]
	var client_a := "白波ホテル"
	var client_b := "北斗運送"
	game.state.care_agreements = {
		client_a:{"active":true,"pending":false,"fee":650,"maintenance_owner":"sora"},
		client_b:{"active":true,"pending":false,"fee":400,"maintenance_owner":"aya"},
		"停止中顧客":{"active":true,"pending":false,"fee":900,"maintenance_owner":"","maintenance_legacy":true}
	}
	game.state.customer_relations = {client_a:{"satisfaction":74},client_b:{"satisfaction":61},"停止中顧客":{"satisfaction":35}}
	game.state.maintenance_targets = {
		client_a:[{"asset_id":"hotel/front","chapter":1,"scenario":{"id":"hotel-front","title":"宿泊予約端末"},"vm_state":{"secret":"must-not-leak"}}],
		client_b:[{"asset_id":"hokuto/backup","chapter":0,"scenario":{"id":"hokuto-backup","title":"配送バックアップ"}}]
	}
	game.state.maintenance_jobs = [
		{"id":"hotel-day","client":client_a,"day":day,"status":"done","assignee":"sora","remaining":0.0,"total":8.0,"fee":650,"cost":100,"paid":false,"result":"PASS: saved inspection"},
		{"id":"hokuto-day","client":client_b,"day":day,"status":"working","assignee":"aya","remaining":5.0,"total":12.0,"fee":400,"cost":100,"paid":false,"result":""}
	]
	game._assignments = {
		"sora":{"kind":"maintenance","client":client_a,"status":"done","result":"PASS: saved inspection"},
		"aya":{"kind":"maintenance","client":client_b,"status":"working","remaining":5.0,"total":12.0}
	}
	game.state.assignments = game._assignments.duplicate(true)
	game.state.care_incidents = {
		client_a:{"id":"latent-a","client":client_a,"status":"latent","kind":"account"},
		client_b:{"id":"detected-b","client":client_b,"status":"detected","kind":"backup","inspection_result":"saved public note"}
	}
	game.state.staff_payroll = {"enabled":true,"due":[
		{"day":day,"staff_id":"sora","amount":700,"paid_amount":700,"paid":true,"expense_recorded":true},
		{"day":day,"staff_id":"aya","amount":300,"paid_amount":0,"paid":false,"expense_recorded":true},
		{"day":day-1,"staff_id":"mio","amount":500,"paid_amount":0,"paid":false,"expense_recorded":true}
	]}
	game.state.retainer_settled_day = -1
	var before_state := JSON.stringify(game.state)
	var before_assignments := JSON.stringify(game._assignments)
	var result: Dictionary = VIEW.snapshot(game)
	var hotel := find_client(result, client_a)
	var hokuto := find_client(result, client_b)
	check(bool(result.get("available", false)) and int(result.get("capacity", -1)) == 7 and int(result.get("reserved_count", -1)) == 2, "capacity and reserved agreements use saved active state")
	check(int(result.get("expected_revenue", -1)) == 1050 and int(result.get("earned", -1)) == 650 and int(result.get("service_cost", -1)) == 200, "pending work is not earned and only passing saved check contributes")
	check(int(result.get("company_payroll", -1)) == 1000 and bool(result.get("payroll_known", false)), "today payroll includes paid and unpaid expenses but excludes prior days")
	check(int(result.get("expected_after_payroll", 0)) == -150 and int(result.get("actual_after_payroll", 0)) == -550, "care projections compare service margin against whole-company payroll")
	check(bool(hotel.get("scope_known", false)) and hotel.get("scope", []).size() == 1 and str(hotel.scope[0].get("name", "")) == "宿泊予約端末" and int(hotel.scope[0].get("chapter", -1)) == 1, "scope names come from retained saved target")
	check(str(hotel.get("owner", "")) == "sora" and str(hotel.get("owner_name", "")).length() > 0 and str(hotel.get("assignee", "")) == "sora", "recurring owner and actual job assignee are connected separately")
	check(int(hotel.get("earned_today", -1)) == 650 and int(hokuto.get("earned_today", -1)) == 0 and str(hokuto.get("job_status", "")) == "working", "per-client earned amount distinguishes completed and unfinished inspection")
	check(str(find_client(result, "停止中顧客").get("status", "")) == "suspended" and int(find_client(result, "停止中顧客").get("earned_today", -1)) == 0, "low satisfaction does not earn a suspended legacy agreement")
	check(hotel.get("incident", {}).is_empty() and str(hokuto.get("incident", {}).get("status", "")) == "detected", "latent incident is hidden while a saved detected incident is visible")
	check(not JSON.stringify(result).contains("must-not-leak"), "projection never exposes retained VM contents")
	check(JSON.stringify(game.state) == before_state and JSON.stringify(game._assignments) == before_assignments, "snapshot does not mutate nested live save or assignments")
	game.state.care_agreements["旧保守契約"] = {"active":true,"pending":false,"fee":225,"maintenance_legacy":true}
	var legacy_portfolio: Dictionary = VIEW.snapshot(game)
	var legacy_contract := find_client(legacy_portfolio, "旧保守契約")
	check(not bool(legacy_contract.get("scope_known", true)) and legacy_contract.get("scope", []).is_empty() and int(legacy_contract.get("earned_today", -1)) == 225, "legacy guaranteed fee remains known while retained target scope stays unknown")
	game.state.care_agreements.erase("旧保守契約")

	# Once today's ledger is saved, use its aggregate as authority instead of
	# counting the same completed job a second time.
	game.state.maintenance_jobs[0].paid = true
	game.state.retainer_settled_day = day
	game.state.retainer_daily = {str(day):{"day":day,"maintenance_earned":650,"retainer_cost":200}}
	var settled: Dictionary = VIEW.snapshot(game)
	check(int(settled.get("earned", -1)) == 650 and int(settled.get("expected_revenue", -1)) == 650 and int(settled.get("actual_after_payroll", 0)) == -550, "settled day does not accrue or count today's maintenance earnings twice")
	check(int(find_client(settled, client_a).get("earned_today", -1)) == 650, "settled client's paid inspection remains attached to its customer")

	# Incomplete legacy data must remain visibly unknown rather than becoming a
	# zero-cost, zero-scope or successful inspection.
	var legacy_before: Dictionary = game.state.duplicate(true)
	game.state.erase("maintenance_targets")
	game.state.erase("maintenance_jobs")
	game.state.erase("staff_payroll")
	game.state.retainer_settled_day = day - 1
	game.state.care_agreements[client_a].erase("fee")
	var legacy: Dictionary = VIEW.snapshot(game)
	var legacy_client := find_client(legacy, client_a)
	check(bool(legacy.get("available", false)) and not bool(legacy_client.get("fee_known", true)) and not bool(legacy_client.get("scope_known", true)) and not bool(legacy_client.get("job_known", true)), "old save gaps remain explicitly unknown")
	check(int(legacy_client.get("fee", 0)) < 0 and int(legacy.get("expected_revenue", 0)) < 0 and int(legacy.get("company_payroll", 0)) < 0 and not bool(legacy.get("payroll_known", true)), "missing legacy amounts never become zero success")
	game.state = legacy_before

	for failure in failures: push_error("CARE_PORTFOLIO_VIEW: " + failure)
	print("CARE_PORTFOLIO_VIEW failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
