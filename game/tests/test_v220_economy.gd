extends SceneTree

## v2.2 management state regression coverage.  These checks exercise the
## existing Game/CustomerStock APIs and deliberately avoid the security VM.
var failures: Array[String] = []
const BILLING = preload("res://scripts/company_billing.gd")

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func _new_game(suffix: String):
	var node = load("res://scripts/game.gd").new()
	root.add_child(node)
	await process_frame
	var base := "user://qa-v220-"+suffix
	node.save_path = base+".json"; node.backup_path = base+".json.bak"; node.previous_path = base+".previous.json"; node.settings_path = base+"-settings.json"
	check(node.new_game(), suffix+" fresh game")
	check(node.choose_strategy("advisory"), suffix+" strategy")
	check(node.start_free_career(), suffix+" career")
	node.state.cash = 50000
	node.state.skills.advisory = 1; node.state.skills.operations = 1; node.state.peak_profit = 3000
	node.state.market_leads = ["hardware-gateway-install", "hardware-backup-install"]; node.state.market_day = int(node.state.day); node._make_offers()
	return node

func _offer(game, case_id: String = "hardware-gateway-install") -> Dictionary:
	for offer in game.state.get("offers", []):
		if str(offer.get("case_id", "")) == case_id and bool(offer.get("market_available", false)):
			return offer
	return {}

func _pricing_and_acceptance() -> void:
	var game = await _new_game("pricing")
	check(game.pricing_policy() == {"advisory":100,"operations":100,"response":100}, "legacy pricing defaults")
	check(game.set_pricing_policy("advisory",125), "set pricing policy")
	check(int(game.pricing_policy().advisory) == 125, "pricing policy value")
	var before: Dictionary = game.pricing_policy()
	check(not game.set_pricing_policy("advisory",127), "reject non-step pricing")
	check(game.pricing_policy() == before, "invalid pricing leaves state")
	var offer := _offer(game)
	check(not offer.is_empty(), "pricing offer exists")
	if offer.is_empty(): return
	var default_quote: Dictionary = game.contract_quote(offer)
	check(int(default_quote.policy_percent) == 125 and int(default_quote.quoted_fee) == roundi(float(default_quote.reference_fee)*1.25), "policy changes untouched default quote")
	var manual := maxi(0,int(default_quote.reference_fee)-100)
	check(game.set_offer_quote(str(offer.id),manual), "save manual quote")
	check(int(game.contract_quote(offer).quoted_fee) == manual, "manual draft overrides policy")
	check(game.set_pricing_policy("advisory",150), "update policy after draft")
	check(int(game.contract_quote(offer).quoted_fee) == manual, "manual draft survives policy update")
	check(game.choose_contract(str(offer.id)), "accept manual quote")
	var accepted_fee := int(game.state.contract.get("agreed_fee",-1))
	check(accepted_fee == manual, "accepted fee is fixed")
	check(game.set_pricing_policy("advisory",50), "change policy after acceptance")
	check(int(game.state.contract.get("agreed_fee",-1)) == accepted_fee, "accepted agreement remains immutable")
	check(game.save_game(), "save pricing state")
	var resumed = load("res://scripts/game.gd").new(); root.add_child(resumed); await process_frame
	resumed.save_path = game.save_path; resumed.backup_path = game.backup_path; resumed.previous_path = game.previous_path; resumed.settings_path = game.settings_path
	check(resumed.load_game(), "reload pricing state")
	check(int(resumed.pricing_policy().advisory) == 50 and int(resumed.state.contract.get("agreed_fee",-1)) == accepted_fee, "pricing and accepted fee reload")

func _cart_atomicity() -> void:
	var game = await _new_game("cart")
	check(game.set_customer_cart("gateway",2).ok, "set gateway cart")
	check(game.set_customer_cart("backup_appliance",1).ok, "set backup cart")
	var review: Dictionary = game.customer_cart_review()
	check(bool(review.ok) and int(review.quantity) == 3 and int(review.total) == 11200 and int(review.cash_after) == 38800 and int(review.free_capacity) == 3, "multi SKU cart review")
	var history_before: int = game.state.history.size(); var cash_before: int = int(game.state.cash)
	var purchased: Dictionary = game.buy_customer_cart()
	check(bool(purchased.ok) and purchased.ids.size() == 3, "atomic multi SKU purchase")
	check(int(game.state.cash) == cash_before-11200 and game.state.history.size() == history_before+1 and game.procurement_cart().gateway == 0 and game.procurement_cart().backup_appliance == 0, "cart commits cash history and clear together")
	check(game.customer_stock_units().size() == 3 and game.state.history[-1].lines.size() == 2, "serialised multi SKU history")
	check(not game.set_customer_cart("unknown",1).ok, "reject invalid cart SKU")
	var failed = await _new_game("cart-cash")
	failed.state.cash = 100
	check(failed.set_customer_cart("gateway",1).ok, "set unaffordable cart")
	var failed_units: int = failed.customer_stock_units().size(); var failed_history: int = failed.state.history.size()
	var failed_buy: Dictionary = failed.buy_customer_cart()
	check(not bool(failed_buy.ok) and failed.customer_stock_units().size() == failed_units and failed.state.history.size() == failed_history and int(failed.procurement_cart().gateway) == 1, "insufficient cash rolls back atomically")
	var capacity = await _new_game("cart-capacity")
	capacity.state.cash = 100000
	check(capacity.set_customer_cart("gateway",3).ok and capacity.set_customer_cart("backup_appliance",3).ok, "set full capacity cart")
	check(bool(capacity.buy_customer_cart().ok), "buy full capacity cart")
	check(capacity.set_customer_cart("gateway",1).ok and not bool(capacity.buy_customer_cart().ok), "capacity preflight rejects extra purchase")

func _summary_and_preview() -> void:
	var game = await _new_game("summary")
	var offer := _offer(game)
	check(not offer.is_empty(), "summary offer exists")
	if offer.is_empty(): return
	var preview: Dictionary = game.offer_operations_preview(offer)
	check(str(preview.sku) == "gateway" and int(preview.required) == 1 and int(preview.shortage) == 1, "operations preview reports stock shortage")
	check(int(preview.purchase_cost) == 3200 and int(preview.cash_after_purchase) == int(game.state.cash)-3200, "operations preview uses actual purchase cost")
	check(game.choose_contract(str(offer.id)), "summary accepted hardware contract")
	var required: Dictionary = game.customer_stock_summary("gateway")
	check(int(required.required) == 1 and int(required.shortage) == 1, "accepted requirement counted once")
	# _sync_contract_context() may also expose the active contract in contexts;
	# summary must still count it once.
	check(game.customer_stock_summary("gateway").required == required.required, "current/context requirement is deduplicated")
	var same_offer_preview: Dictionary = game.offer_operations_preview(offer)
	check(int(same_offer_preview.required) == 1 and int(same_offer_preview.shortage) == 1, "accepted offer is not promised twice")
	var second_offer := offer.duplicate(true)
	second_offer.id = "synthetic-second-gateway"
	var portfolio_preview: Dictionary = game.offer_operations_preview(second_offer)
	check(int(portfolio_preview.required) == 2 and int(portfolio_preview.shortage) == 2, "second accepted-sized offer adds one portfolio requirement")
	check(game.set_customer_cart("gateway",1).ok and bool(game.buy_customer_cart().ok), "buy stock for accepted requirement")
	var incoming: Dictionary = game.company_operating_summary()
	check(int(incoming.incoming_count) == 1 and int(incoming.receiving_count) == 0, "queued stock is incoming until it arrives")
	check(game.advance_delivery(30.0), "advance inbound stock")
	var supplied: Dictionary = game.customer_stock_summary("gateway")
	check(int(supplied.available) == 1 and int(supplied.inbound) == 0 and int(supplied.shortage) == 0, "available stock covers requirement")
	var operating: Dictionary = game.company_operating_summary()
	check(int(operating.receiving_count) == 1 and int(operating.incoming_count) == 0, "ready stock is receiving inventory")
	for key in ["draft_invoice_count","draft_invoice_total","stock_shortages","receiving_count","installed_equipment_count","pending_equipment_count","staff_count","staff_capacity","open_contracts","free_contract_slots","payroll_due","maintenance_pending"]:
		check(operating.has(key), "operating summary has "+key)

func _rollback_and_reload() -> void:
	var policy = await _new_game("rollback-policy")
	var policy_before := JSON.stringify(policy.state)
	policy.save_path = "user://qa-v220-missing-policy/save.json"; policy.backup_path = "user://qa-v220-missing-policy/save.bak"; policy.previous_path = "user://qa-v220-missing-policy/save.previous.json"
	check(not policy.set_pricing_policy("advisory",125), "pricing save failure rejected")
	check(JSON.stringify(policy.state) == policy_before, "pricing save failure restores entire state")
	var cart = await _new_game("rollback-cart")
	var cart_before := JSON.stringify(cart.state)
	cart.save_path = "user://qa-v220-missing-cart/save.json"; cart.backup_path = "user://qa-v220-missing-cart/save.bak"; cart.previous_path = "user://qa-v220-missing-cart/save.previous.json"
	check(not bool(cart.set_customer_cart("gateway",1).ok), "cart save failure rejected")
	check(JSON.stringify(cart.state) == cart_before, "cart save failure restores entire state")
	var checkout = await _new_game("rollback-checkout")
	check(bool(checkout.set_customer_cart("gateway",1).ok), "checkout cart setup")
	var checkout_before := JSON.stringify(checkout.state)
	checkout.save_path = "user://qa-v220-missing-checkout/save.json"; checkout.backup_path = "user://qa-v220-missing-checkout/save.bak"; checkout.previous_path = "user://qa-v220-missing-checkout/save.previous.json"
	check(not bool(checkout.buy_customer_cart().ok), "checkout save failure rejected")
	check(JSON.stringify(checkout.state) == checkout_before, "checkout save failure restores stock cash history cart")
	var repeated = await _new_game("repeat-checkout")
	check(bool(repeated.set_customer_cart("gateway",1).ok) and bool(repeated.buy_customer_cart().ok), "first checkout succeeds")
	var repeated_state := JSON.stringify(repeated.state); var repeated_units: int = repeated.customer_stock_units().size()
	check(not bool(repeated.buy_customer_cart().ok), "second empty checkout rejected")
	check(JSON.stringify(repeated.state) == repeated_state and repeated.customer_stock_units().size() == repeated_units, "repeated checkout does not double charge")
	var persisted = await _new_game("persist-cart")
	check(bool(persisted.set_customer_cart("backup_appliance",2).ok), "persist cart setup")
	check(persisted.save_game(), "persist cart save")
	var resumed = load("res://scripts/game.gd").new(); root.add_child(resumed); await process_frame
	resumed.save_path = persisted.save_path; resumed.backup_path = persisted.backup_path; resumed.previous_path = persisted.previous_path; resumed.settings_path = persisted.settings_path
	check(resumed.load_game(), "persist cart reload")
	check(int(resumed.procurement_cart().backup_appliance) == 2, "cart survives actual reload")

func _migration_and_rejection() -> void:
	var legacy = await _new_game("legacy")
	check(bool(legacy.set_customer_cart("gateway",1).ok) and bool(legacy.buy_customer_cart().ok), "legacy customer stock fixture")
	legacy.state.erase("pricing_policy"); legacy.state.erase("procurement_cart"); legacy.state.erase("cash_flow_start_day"); legacy.state.day = 4
	check(legacy.save_game(), "write raw legacy save")
	var legacy_reload = load("res://scripts/game.gd").new(); root.add_child(legacy_reload); await process_frame
	legacy_reload.save_path = legacy.save_path; legacy_reload.backup_path = legacy.backup_path; legacy_reload.previous_path = legacy.previous_path; legacy_reload.settings_path = legacy.settings_path
	check(legacy_reload.load_game(), "legacy save reload")
	check(legacy_reload.pricing_policy() == {"advisory":100,"operations":100,"response":100} and legacy_reload.procurement_cart().gateway == 0 and legacy_reload.customer_stock_units().size() == 1, "legacy fields default without customer data loss")
	check(int(legacy_reload.state.cash_flow_start_day) == 5, "legacy cash flow starts next day")
	var malformed = await _new_game("malformed")
	check(bool(malformed.set_customer_cart("gateway",1).ok) and bool(malformed.buy_customer_cart().ok), "malformed customer stock fixture")
	var malformed_before := JSON.stringify(malformed.state)
	var invalid: Dictionary = malformed.state.duplicate(true); invalid.pricing_policy = {"advisory":99,"operations":100,"response":100}
	var file := FileAccess.open(malformed.save_path, FileAccess.WRITE); file.store_string(JSON.stringify(invalid)); file.close()
	malformed.backup_path = "user://qa-v220-no-malformed-backup.json"
	check(not malformed.load_game(), "malformed new field rejected")
	check(JSON.stringify(malformed.state) == malformed_before, "malformed save rejection preserves customer data")

func _stock_states_billing_and_staff() -> void:
	var stock = await _new_game("stock-states")
	check(bool(stock.set_customer_cart("gateway",3).ok) and bool(stock.buy_customer_cart().ok), "stock state fixture")
	check(stock.advance_delivery(30.0), "stock state delivery")
	var units: Array = stock.state.customer_stock.units
	units[0].status = "staged"; units[0].contract_id = "other-contract"; units[0].target_index = 0
	units[1].status = "shipping"; units[1].contract_id = "other-contract"; units[1].target_index = 1; units[1].elapsed_seconds = 0.0
	units[2].status = "delivered"; units[2].contract_id = "other-contract"; units[2].target_index = 2
	var states: Dictionary = stock.customer_stock_summary("gateway")
	check(int(states.available) == 0 and int(states.inbound) == 0 and int(states.reserved) == 2 and int(states.delivered) == 1 and int(states.used) == 1, "staged shipping delivered stay unavailable for other jobs")
	var invoice = await _new_game("unpaid-invoice")
	var cash_before := int(invoice.state.cash)
	var draft := BILLING.create_draft(invoice.state,"v220-invoice",{"client":"client","title":"invoice","payment_days":1},{"client":"client","title":"invoice","fee":1000,"bonus":0,"baseline_bonus":0,"material_cost":0,"material_billable":false})
	check(bool(draft.ok), "create unpaid invoice")
	check(bool(BILLING.post(invoice.state,str(draft.invoice.id)).ok), "post unpaid invoice")
	var billing: Dictionary = invoice.billing_summary(); var operating: Dictionary = invoice.company_operating_summary()
	check(int(billing.receivable_total) == 1000 and int(billing.paid_today) == 0 and int(invoice.state.cash) == cash_before, "unpaid invoice excluded from cash inflow")
	check(int(operating.receivable_total) == 1000 and int(operating.paid_today) == 0 and int(operating.draft_invoice_count) == 0, "operating summary keeps unpaid invoice receivable")
	var workforce = await _new_game("workforce")
	var fresh_workforce: Dictionary = workforce.company_operating_summary()
	check(int(fresh_workforce.staff_count) == 2 and int(fresh_workforce.extra_staff_count) == 0 and int(fresh_workforce.staff_capacity) == 0 and int(fresh_workforce.workforce_capacity) == 2, "base workforce is separate from extra staff capacity")
	workforce.state.equipment = ["teamdesk"]; workforce.state.cash = 50000
	check(workforce.hire_staff("mio"), "hire extra workforce")
	var hired_workforce: Dictionary = workforce.company_operating_summary()
	check(int(hired_workforce.staff_count) == 3 and int(hired_workforce.extra_staff_count) == 1 and int(hired_workforce.staff_capacity) == 1 and int(hired_workforce.workforce_capacity) == 3, "extra staff capacity remains explicit")
	var maintenance = await _new_game("maintenance-summary")
	maintenance.state.maintenance_jobs = [{"day":int(maintenance.state.day)-1,"status":"pending"},{"day":int(maintenance.state.day),"status":"working"},{"day":int(maintenance.state.day),"status":"pending"},{"day":int(maintenance.state.day),"status":"failed"}]
	check(int(maintenance.company_operating_summary().maintenance_pending) == 2, "maintenance summary limits current actionable jobs")

func _story_assignments() -> void:
	var aya = load("res://scripts/game.gd").new(); root.add_child(aya); await process_frame
	aya.save_path = "user://qa-v220-story-aya.json"; aya.backup_path = aya.save_path+".bak"; aya.previous_path = aya.save_path+".previous"; aya.settings_path = aya.save_path+".settings"
	aya._reset_state(); aya.choose_strategy("advisory"); check(aya.accept_mission(), "story Aya contract"); aya.vm_run("help"); aya.assign_colleague("aya")
	check(str(aya.state.assignments.get("aya",{}).get("role","")) == "aya", "story Aya assignment role")
	var ren = load("res://scripts/game.gd").new(); root.add_child(ren); await process_frame
	ren.save_path = "user://qa-v220-story-ren.json"; ren.backup_path = ren.save_path+".bak"; ren.previous_path = ren.save_path+".previous"; ren.settings_path = ren.save_path+".settings"
	ren._reset_state(); ren.choose_strategy("response"); ren.state.chapter = 1; ren.state.config = ren._default_fields(1); ren.state.credit = 8; ren.state.completed_ids = ["share"]; check(ren.accept_mission(), "story Ren contract"); ren.vm_run("help"); ren.assign_colleague("ren")
	check(str(ren.state.assignments.get("ren",{}).get("role","")) == "ren", "story Ren assignment role")
	var failed = load("res://scripts/game.gd").new(); root.add_child(failed); await process_frame
	failed.save_path = "user://qa-v220-story-failed.json"; failed.backup_path = failed.save_path+".bak"; failed.previous_path = failed.save_path+".previous"; failed.settings_path = failed.save_path+".settings"
	failed._reset_state(); failed.choose_strategy("advisory"); check(failed.accept_mission(), "story failed-save contract"); failed.vm_run("help")
	var assignments_before := JSON.stringify(failed.state.assignments); var minutes_before := float(failed.state.work.minutes)
	failed.save_path = "user://qa-v220-story-failed/missing/save.json"; failed.backup_path = failed.save_path+".bak"; failed.previous_path = failed.save_path+".previous"
	failed.assign_colleague("aya")
	check(JSON.stringify(failed.state.assignments) == assignments_before and is_equal_approx(float(failed.state.work.minutes),minutes_before), "story assignment save failure has no job or time")

func _history_cash_retention() -> void:
	var game = await _new_game("history-retention")
	game.state.day = 3
	game.state.retainer_settled_day = -1
	game.state.history = []
	for i in 100:
		game.state.history.append({"day":2,"kind":"old_transaction","amount":1,"sequence":i})
	for i in 120:
		game.state.history.append({"day":3,"kind":"same_day_transaction","amount":1,"sequence":i})
	game._apply_retainer()
	var same_day_rows := 0
	for row in game.state.history:
		if int(row.get("day",-1)) == 3: same_day_rows += 1
	check(same_day_rows == 121, "history trimming preserves every current-day cash row")

func run() -> void:
	await _pricing_and_acceptance()
	await _cart_atomicity()
	await _summary_and_preview()
	await _rollback_and_reload()
	await _migration_and_rejection()
	await _stock_states_billing_and_staff()
	await _story_assignments()
	await _history_cash_retention()
	print("V220_ECONOMY failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)
