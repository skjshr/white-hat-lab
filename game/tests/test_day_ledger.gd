extends SceneTree

const LEDGER = preload("res://scripts/day_ledger.gd")
var failures: Array[String] = []

class FakeGame extends RefCounted:
	var state: Dictionary = {}
	var targets: Dictionary = {"alice":["check"],"bob":["check"],"legacy":[]}
	func care_portfolio() -> Dictionary:
		var count: int = 0
		for name in state.get("care_agreements", {}).keys():
			if bool(state.care_agreements[name].get("active", false)): count += 1
		return {"clients":state.get("care_accounts", []),"service_cost_daily":count * 100}
	func _maintenance_targets_for(client: String) -> Array:
		return targets.get(client, ["check"])

func _init() -> void:
	var ordinary := FakeGame.new()
	ordinary.state = {
		"day":4,"cash":50,"retainer_settled_day":-1,
		"care_agreements":{"alice":{"active":true,"fee":150},"bob":{"active":true,"fee":150},"legacy":{"active":true,"fee":150,"maintenance_legacy":true}},
		"care_accounts":[{"client":"alice","status":"active"},{"client":"bob","status":"active"},{"client":"legacy","status":"active"}],
		"maintenance_jobs":[{"day":4,"client":"alice","status":"done","fee":250,"paid":false},{"day":4,"client":"bob","status":"pending","fee":300,"paid":false}],
		"staff_payroll":{"due":[{"day":4,"amount":200,"paid_amount":0},{"day":3,"amount":500,"paid_amount":400}]},
		"history":[{"day":4,"id":"contract-1","profit":1000},{"day":4,"kind":"staff_cost","amount":100} ],
		"contract_contexts":{"open":{"completed":false}}
	}
	var before: Dictionary = ordinary.state.duplicate(true)
	var preview: Dictionary = LEDGER.preview(ordinary)
	_check(int(preview.care_gross)==400 and int(preview.care_cost)==300 and int(preview.care_net)==100,"earned care excludes unfinished job")
	_check(int(preview.missed_maintenance)==1,"unfinished maintenance counted")
	_check(int(preview.total_profit)==800,"profit uses contract care hiring and today's wage cost")
	_check(int(preview.paid_wages)==150 and int(preview.arrears)==150 and int(preview.cash_after)==0,"cash clamp pays old arrears without negative cash")
	_check(ordinary.state == before,"preview is read only")
	var settled: Dictionary = LEDGER.settle(ordinary,{"payroll_outstanding":300})
	_check(int(settled.investment_spending)==0 and ordinary.state.day_ledgers.size()==1,"settle stores one ledger")
	_check(int(LEDGER.settle(ordinary).day)==4 and ordinary.state.day_ledgers.size()==1,"settle is idempotent")

	var negative := FakeGame.new(); negative.state = ordinary.state.duplicate(true); negative.state.day_ledgers=[]; negative.state.cash=-20
	var negative_preview: Dictionary = LEDGER.preview(negative)
	_check(int(negative_preview.paid_wages)==80 and int(negative_preview.cash_after)==0 and int(negative_preview.arrears)==220,"negative cash clamps payment")

	var settled_state := FakeGame.new(); settled_state.state = ordinary.state.duplicate(true); settled_state.state.day_ledgers=[]; settled_state.state.cash=700; settled_state.state.retainer_settled_day=4
	settled_state.state.history.append({"id":"retainer-day-4","day":4,"retainer_gross":400,"retainer_cost":300,"retainer_net":100,"maintenance_missed":1})
	var settled_preview: Dictionary = LEDGER.preview(settled_state)
	_check(int(settled_preview.care_net)==100 and int(settled_preview.payroll_due)==200 and int(settled_preview.cash_after)==400,"settled day does not double forecast")

	var investment := FakeGame.new(); investment.state = ordinary.state.duplicate(true); investment.state.day_ledgers=[]; investment.state.history.append({"day":4,"kind":"investment","amount":500})
	investment.state.history.append({"id":"retainer-day-4","day":4,"retainer_gross":400,"retainer_cost":300,"retainer_net":100,"maintenance_missed":1})
	var investment_ledger: Dictionary = LEDGER.settle(investment)
	_check(int(investment_ledger.investment_spending)==500 and int(investment_ledger.total_profit)==800,"investment is reported but excluded from profit")
	for failure in failures: push_error("DAY_LEDGER: "+failure)
	print("DAY_LEDGER failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, label: String) -> void:
	if not value: failures.append(label)
