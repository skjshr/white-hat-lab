extends SceneTree

const LEDGER = preload("res://scripts/day_ledger.gd")
var failures: Array[String] = []

class Fixture extends RefCounted:
	var state: Dictionary = {}
	func care_portfolio() -> Dictionary:
		return {"clients":[],"service_cost_daily":0}

func _init() -> void:
	# Same-day purchases are assets, invoice drafts are not money received, and
	# paying yesterday's wages changes today's cash without a second expense.
	var game := Fixture.new()
	game.state = {"day":5,"cash":8700,"cash_flow_start_day":5,"retainer_settled_day":5,
		"care_agreements":{},"maintenance_jobs":[],"contract_contexts":{},"completed_ids":["invoice-job"],
		"staff_payroll":{"due":[{"day":4,"amount":600,"paid_amount":600},{"day":5,"amount":400,"paid_amount":0}]},
		"customer_stock":{"units":[{"unit_cost":3200,"contract_id":""},{"unit_cost":4800,"contract_id":"invoice-job"}]},
		"billing":{"invoices":[{"contract_id":"invoice-job","status":"draft","amount":8800},{"contract_id":"prior-job","status":"paid","amount":5000,"paid_day":5}]},
		"history":[
			{"day":5,"kind":"inventory_purchase","amount":3200},
			{"day":5,"kind":"investment","amount":1000},
			{"day":5,"kind":"staff_cost","amount":200},
			{"day":5,"kind":"invoice_payment","amount":5000},
			{"day":5,"kind":"wage_payment","amount":600},
			{"day":5,"id":"invoice-job","profit":3300,"expense":5500,"material_cost":4800,"billing_version":1,"cash_delta":-700},
			{"day":5,"id":"retainer-day-5","retainer_gross":500,"retainer_cost":100,"retainer_net":400}
		]}
	var before := game.state.duplicate(true)
	var result := LEDGER.preview(game)
	check(result.cash_flow_complete,"complete cash history is indicated")
	check(result.cash_open == 9000,"opening balance excludes actual recorded money movements")
	check(result.cash_in == 5500,"draft excluded from incoming cash")
	check(result.cash_out == 6200,"purchases investment wages and job costs included once")
	check(result.cash_after == 8300 and result.cash_open + result.cash_change == result.cash_after,"closing cash reconciles")
	check(result.total_profit == 3100,"profit excludes purchases/investments and old arrears payment")
	check(result.inventory_value == 3200,"completed customer equipment is not company inventory")
	check(game.state == before,"financial preview never mutates records")
	game.state.cash_flow_start_day = 6
	check(not LEDGER.preview(game).cash_flow_complete,"legacy partial day is not presented as complete")
	game.state.cash_flow_start_day = 5
	game.state.cash = 8300
	game.state.staff_payroll.due[1].paid_amount = 400
	game.state.history.append({"day":5,"kind":"wage_payment","amount":400})
	var settled := LEDGER.settle(game,result)
	check(settled.cash_open == 9000 and settled.cash_after == 8300 and settled.cash_out == 6200,"settled result matches preview")
	game.state.cash = 99999
	check(LEDGER.settle(game) == settled,"settled financial history is immutable")
	var immediate := Fixture.new()
	immediate.state = {"day":1,"cash":10400,"cash_flow_start_day":0,"retainer_settled_day":1,"staff_payroll":{"due":[]},"history":[{"id":"legacy","day":1,"profit":400,"expense":900,"material_cost":0}],"contract_contexts":{}}
	var direct := LEDGER.preview(immediate)
	check(direct.cash_in == 1300 and direct.cash_out == 900 and direct.cash_open == 10000,"legacy direct paid job splits receipts/costs accurately")
	for failure in failures: push_error("V220_CASH_FLOW: " + failure)
	print("V220_CASH_FLOW failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
