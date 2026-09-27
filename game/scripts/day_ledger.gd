extends RefCounted
class_name DayLedger

static func _state(game) -> Dictionary:
	return game.state if game != null and game.get("state") is Dictionary else {}

static func _history_for_day(game, day: int) -> Array:
	var rows: Array = []
	for raw in _state(game).get("history", []):
		if raw is Dictionary and int(raw.get("day", -1)) == day: rows.append(raw)
	return rows

static func _open_contracts(game) -> int:
	var count: int = 0
	for raw in _state(game).get("contract_contexts", {}).values():
		if raw is Dictionary and not bool(raw.get("completed", false)): count += 1
	return count

static func _payroll(game, day: int) -> Dictionary:
	var outstanding: int = 0
	var today_cost: int = 0
	var paid_today: int = 0
	for raw in _state(game).get("staff_payroll", {}).get("due", []):
		if not raw is Dictionary: continue
		var amount: int = int(raw.get("amount", 0))
		var paid_amount: int = clampi(int(raw.get("paid_amount", 0)), 0, amount)
		outstanding += maxi(0, amount - paid_amount)
		if int(raw.get("day", -1)) == day:
			today_cost += amount
			paid_today += paid_amount
	return {"due":outstanding,"today_cost":today_cost,"paid":paid_today,"arrears":outstanding}

static func _care_for_day(game, day: int) -> Dictionary:
	var state: Dictionary = _state(game)
	var active: Array[String] = []
	if game != null and game.has_method("care_portfolio"):
		for account in game.care_portfolio().get("clients", []):
			if str(account.get("status", "")) == "active": active.append(str(account.get("client", "")))
	var gross: int = 0
	var missed: int = 0
	for client in state.get("care_agreements", {}).keys():
		var name: String = str(client)
		var agreement: Dictionary = state.care_agreements[name]
		if name not in active: continue
		var legacy: bool = bool(agreement.get("maintenance_legacy", false))
		var no_targets: bool = game.has_method("_maintenance_targets_for") and game._maintenance_targets_for(name).is_empty()
		if legacy or no_targets: gross += int(agreement.get("fee", 150))
	for raw in state.get("maintenance_jobs", []):
		if not raw is Dictionary or int(raw.get("day", -1)) != day or str(raw.get("client", "")) not in active: continue
		match str(raw.get("status", "")):
			"done":
				if not bool(raw.get("paid", false)): gross += int(raw.get("fee", 0))
			"pending", "working", "failed", "queued", "paused": missed += 1
	var cost: int = 0
	if game != null and game.has_method("care_portfolio"): cost = int(game.care_portfolio().get("service_cost_daily", 0))
	return {"gross":gross,"cost":cost,"net":gross-cost,"missed":missed}

static func _from_records(game, day: int) -> Dictionary:
	var contract_net: int = 0
	var care_gross: int = 0
	var care_cost: int = 0
	var care_net: int = 0
	var hiring_cost: int = 0
	var payroll_expense: int = 0
	var investment_spending: int = 0
	var inventory_spending: int = 0
	var missed: int = 0
	for row in _history_for_day(game, day):
		var kind: String = str(row.get("kind", ""))
		var id: String = str(row.get("id", ""))
		if id.begins_with("retainer-day-"):
			care_gross += int(row.get("retainer_gross", 0)); care_cost += int(row.get("retainer_cost", 0)); care_net += int(row.get("retainer_net", row.get("retainer", 0))); missed += int(row.get("maintenance_missed", 0))
		elif kind == "staff_cost": hiring_cost += int(row.get("amount", row.get("expense", 0)))
		elif kind == "payroll": payroll_expense += int(row.get("expense", row.get("amount", 0)))
		elif kind == "investment": investment_spending += int(row.get("amount", row.get("expense", 0)))
		elif kind == "inventory_purchase": inventory_spending += int(row.get("amount",0))
		elif kind.is_empty(): contract_net += int(row.get("profit", 0))
	var payroll: Dictionary = _payroll(game, day)
	return {"contract_net":contract_net,"care_gross":care_gross,"care_cost":care_cost,"care_net":care_net,"hiring_cost":hiring_cost,"payroll_due":int(payroll.today_cost),"payroll_outstanding":int(payroll.due),"today_wage_cost":int(payroll.today_cost),"paid_wages":int(payroll.paid),"arrears":int(payroll.arrears),"payroll_expense":payroll_expense,"inventory_spending":inventory_spending,"investment_spending":investment_spending,"missed_maintenance":missed}

static func _assemble(game, day: int, records: Dictionary, cash_after: int) -> Dictionary:
	var total_profit: int = int(records.contract_net) + int(records.care_net) - int(records.hiring_cost) - int(records.get("today_wage_cost", records.get("payroll_expense", 0)))
	var billing: Dictionary = preload("res://scripts/company_billing.gd").summary(_state(game), day)
	return {"day":day,"contract_net":int(records.contract_net),"care_gross":int(records.care_gross),"care_cost":int(records.care_cost),"care_net":int(records.care_net),"hiring_cost":int(records.hiring_cost),"payroll_due":int(records.payroll_due),"payroll_outstanding":int(records.get("payroll_outstanding",records.payroll_due)),"total_profit":total_profit,"cash_current":int(_state(game).get("cash",0)),"cash_after":cash_after,"paid_wages":int(records.paid_wages),"arrears":int(records.arrears),"open_contracts":_open_contracts(game),"missed_maintenance":int(records.missed_maintenance),"inventory_spending":int(records.get("inventory_spending",0)),"investment_spending":int(records.get("investment_spending",0)),"draft_total":int(billing.draft_total),"receivable_total":int(billing.receivable_total),"paid_today":int(billing.paid_today),"due_next_day":int(billing.due_next_day),"next_cash":cash_after+int(billing.due_next_day)}

static func _cash_activity(game, day: int) -> Dictionary:
	# A wage expense belongs to its work day; a wage payment belongs to the day
	# cash actually leaves. Invoice drafts and receivables are never cash receipts.
	var flow := {"invoice_collections":0,"job_receipts":0,"job_costs":0,"care_receipts":0,"care_costs":0,"stock_purchases":0,"investment":0,"recruitment":0,"wages_paid":0}
	var invoice_contracts := {}
	for invoice in _state(game).get("billing", {}).get("invoices", []):
		if invoice is Dictionary: invoice_contracts[str(invoice.get("contract_id", ""))] = true
	for row in _history_for_day(game, day):
		var kind := str(row.get("kind", ""))
		var id := str(row.get("id", ""))
		if id.begins_with("retainer-day-"):
			flow.care_receipts += int(row.get("retainer_gross", maxi(0, int(row.get("retainer", 0)))))
			flow.care_costs += int(row.get("retainer_cost", maxi(0, -int(row.get("retainer", 0)))))
		elif kind == "invoice_payment": flow.invoice_collections += int(row.get("amount", 0))
		elif kind == "inventory_purchase": flow.stock_purchases += int(row.get("amount", 0))
		elif kind == "investment": flow.investment += int(row.get("amount", 0))
		elif kind == "staff_cost": flow.recruitment += int(row.get("amount", row.get("expense", 0)))
		elif kind == "wage_payment": flow.wages_paid += int(row.get("amount", 0))
		elif kind.is_empty() and not id.is_empty():
			var expense := int(row.get("expense", 0))
			var material := int(row.get("material_cost", 0))
			flow.job_costs += maxi(0, expense - material)
			if not invoice_contracts.has(id) and int(row.get("billing_version", 0)) != 1:
				flow.job_receipts += int(row.get("profit", 0)) + expense
	return flow

static func _cash_in(flow: Dictionary) -> int:
	return int(flow.invoice_collections) + int(flow.job_receipts) + int(flow.care_receipts)

static func _cash_out(flow: Dictionary) -> int:
	return int(flow.job_costs) + int(flow.care_costs) + int(flow.stock_purchases) + int(flow.investment) + int(flow.recruitment) + int(flow.wages_paid)

static func _add_cash_flow(game, result: Dictionary, forecast_care: Dictionary = {}, forecast_wages: int = 0) -> void:
	var state := _state(game)
	var day := int(result.day)
	var flow := _cash_activity(game, day)
	var actual_change := _cash_in(flow) - _cash_out(flow)
	result.cash_open = int(state.get("cash", 0)) - actual_change
	if not forecast_care.is_empty():
		flow.care_receipts += int(forecast_care.get("gross", 0))
		flow.care_costs += int(forecast_care.get("cost", 0))
	flow.wages_paid += forecast_wages
	result.cash_flow = flow
	result.cash_in = _cash_in(flow)
	result.cash_out = _cash_out(flow)
	result.cash_change = int(result.cash_in) - int(result.cash_out)
	result.cash_flow_complete = day >= int(state.get("cash_flow_start_day", day + 1))
	var inventory_value := 0
	for unit in state.get("customer_stock", {}).get("units", []):
		if not unit is Dictionary: continue
		var contract_id := str(unit.get("contract_id", ""))
		if contract_id.is_empty() or contract_id not in state.get("completed_ids", []):
			inventory_value += int(unit.get("unit_cost", 0))
	result.inventory_value = inventory_value

static func preview(game) -> Dictionary:
	var state: Dictionary = _state(game)
	var day: int = int(state.get("day", 0))
	var records: Dictionary = _from_records(game, day)
	if int(state.get("retainer_settled_day", -1)) != day:
		var care: Dictionary = _care_for_day(game, day)
		records.care_gross = int(care.gross); records.care_cost = int(care.cost); records.care_net = int(care.net); records.missed_maintenance = int(care.missed)
	var current_cash: int = int(state.get("cash", 0))
	var care_cash: int = int(records.care_net) if int(state.get("retainer_settled_day", -1)) != day else 0
	var payment: int = mini(maxi(0, current_cash + care_cash), int(records.get("payroll_outstanding", 0)))
	var result: Dictionary = _assemble(game, day, records, current_cash + care_cash - payment)
	result.paid_wages = payment; result.arrears = maxi(0, int(records.get("payroll_outstanding", 0)) - payment); result.preview = true
	var forecast_care := {"gross":int(records.care_gross),"cost":int(records.care_cost)} if int(state.get("retainer_settled_day", -1)) != day else {}
	_add_cash_flow(game, result, forecast_care, payment)
	return result

static func settle(game, before: Dictionary = {}) -> Dictionary:
	var state: Dictionary = _state(game)
	var day: int = int(state.get("day", 0))
	if not state.has("day_ledgers") or not state.day_ledgers is Array: state.day_ledgers = []
	for existing in state.day_ledgers:
		if existing is Dictionary and int(existing.get("day", -1)) == day: return existing.duplicate(true)
	var records: Dictionary = _from_records(game, day)
	var ledger: Dictionary = _assemble(game, day, records, int(state.get("cash", 0)))
	if not before.is_empty(): ledger.paid_wages = maxi(0, int(before.get("payroll_outstanding", before.get("payroll_due", 0))) - int(records.arrears))
	ledger.preview = false
	_add_cash_flow(game, ledger)
	state.day_ledgers.append(ledger)
	if state.day_ledgers.size() > 60: state.day_ledgers = state.day_ledgers.slice(-60)
	return ledger.duplicate(true)

static func latest(game) -> Dictionary:
	var rows: Array = _state(game).get("day_ledgers", [])
	return rows.back().duplicate(true) if not rows.is_empty() and rows.back() is Dictionary else {}
