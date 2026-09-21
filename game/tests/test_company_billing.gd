extends SceneTree

const BILLING = preload("res://scripts/company_billing.gd")
var game: Node
var failures: Array[String] = []
var qa_id := ""

func _init() -> void:
	qa_id = "company-billing-" + str(OS.get_process_id())
	await process_frame
	game = root.get_node("Game")
	game.set_process(false)
	game.save_path = "user://" + qa_id + ".json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	game._reset_state()
	_expect(game.choose_strategy("advisory"), "strategy fixture")
	_expect(game.start_free_career(), "career fixture")
	# Unlock tier 2/3 offers through the normal level calculation; do not mark
	# contracts, checks, cash, or billing results as completed.
	game.state.peak_profit = 100000
	game.state.credit = 300
	game.state.skills.advisory = 3
	game.state.skills.operations = 3
	game.state.skills.response = 3
	game._make_offers()
	_test_module_boundaries()
	await _test_real_contract(1, 0, true)
	await _test_real_contract(2, 2, false)
	await _test_real_contract(3, 4, false)
	_test_legacy_contract()
	_finish()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL ", label)

func _test_module_boundaries() -> void:
	var malformed := {"billing":[]}
	_expect(not BILLING.ensure(malformed), "malformed billing container rejected")
	var bad_version := {"day":0,"cash":100,"history":[],"billing":{"version":99,"next_invoice":1,"invoices":[],"payments":[]}}
	var bad_version_before := JSON.stringify(bad_version)
	_expect(not BILLING.ensure(bad_version) and JSON.stringify(bad_version) == bad_version_before, "invalid billing version rejected without mutation")
	var fixture := {"day":0,"cash":100,"history":[],"billing":{"version":1,"next_invoice":1,"invoices":[],"payments":[]}}
	var contract := {"payment_days":0,"client":"Fixture"}
	var receipt := {"fee":1000,"bonus":100,"baseline_bonus":0,"material_cost":3200,"client":"Fixture","title":"Fixture"}
	var first := BILLING.create_draft(fixture, "contract-1", contract, receipt)
	_expect(bool(first.ok), "module creates valid draft")
	var duplicate := BILLING.create_draft(fixture, "contract-1", contract, receipt)
	_expect(bool(duplicate.ok) and str(duplicate.invoice.id) == str(first.invoice.id) and fixture.billing.invoices.size() == 1, "duplicate draft is idempotent")
	var invalid := BILLING.create_draft(fixture, "bad", {"payment_days":"x"}, receipt)
	_expect(not bool(invalid.ok) and fixture.billing.invoices.size() == 1, "malformed invoice rejected without append")
	var posted := BILLING.post(fixture, str(first.invoice.id))
	_expect(bool(posted.ok) and fixture.billing.payments.size() == 1 and int(fixture.cash) == 1200, "module day-zero post settles once")
	var repost := BILLING.post(fixture, str(first.invoice.id))
	_expect(bool(repost.ok) and fixture.billing.payments.size() == 1 and int(fixture.cash) == 1200, "module repost is idempotent")
	var duplicate_payment := fixture.duplicate(true)
	duplicate_payment.billing.payments.append(fixture.billing.payments[0].duplicate(true))
	var duplicate_payment_before := JSON.stringify(duplicate_payment)
	_expect(not bool(BILLING.post(duplicate_payment, str(first.invoice.id)).get("ok", false)) and JSON.stringify(duplicate_payment) == duplicate_payment_before, "duplicate payment rejected without mutation")
	var recovering := {"day":1,"cash":-700,"history":[]}
	var recovery_invoice := BILLING.create_draft(recovering, "recovery", contract, receipt)
	_expect(bool(BILLING.post(recovering, str(recovery_invoice.invoice.id)).ok) and int(recovering.cash) == 400, "negative cash can recover through legitimate receipt")
	var invalid_version := {"billing":{"version":{}}}
	_expect(not BILLING.ensure(invalid_version), "malformed version does not throw or reset records")
	var legacy_invoice := {"day":1,"cash":100,"history":[],"billing":{"version":1,"next_invoice":2,"invoices":[{"id":"INV/0001","contract_id":"legacy-hardware","client":"Legacy","title":"Legacy","fee":1000,"bonus":100,"baseline_bonus":0,"material_cost":3200,"amount":1100,"payment_days":0,"created_day":1,"posted_day":-1,"due_day":-1,"paid_day":-1,"status":"draft"}],"payments":[]}}
	var legacy_post := BILLING.post(legacy_invoice, "INV/0001")
	_expect(bool(legacy_post.ok) and int(legacy_invoice.cash)==1200 and int(legacy_invoice.billing.invoices[0].amount)==1100, "legacy hardware invoice total remains unchanged")

func _test_real_contract(tier: int, chapter: int, immediate: bool) -> void:
	var offer: Dictionary = _find_offer(tier, chapter)
	_expect(not offer.is_empty(), "tier%d offer found" % tier)
	if offer.is_empty(): return
	var id := str(offer.get("id", ""))
	_expect(game.choose_contract(id), "tier%d accepted through Game" % tier)
	if not game.state.accepted: return
	var accepted_days := int(game.state.contract.get("payment_days", -1))
	_expect(game.set_offer_plan("care"), "tier%d offer plan can change independently" % tier)
	_expect(int(game.state.contract.get("payment_days", -1)) == accepted_days, "tier%d accepted payment days remain fixed" % tier)
	game.set_offer_plan("standard")
	for target_index in game.state.targets.size():
		_expect(game.select_target(target_index), "tier%d target %d selected" % [tier, target_index])
		game.inspect_mission()
		_expect(_solve_current(), "tier%d target %d real checks" % [tier, target_index])
	_expect(game.can_deliver(), "tier%d deliverable" % tier)
	var cash_before := int(game.state.cash)
	var profit_before := int(game.state.profit)
	var peak_before := int(game.state.peak_profit)
	var path_before_delivery: String = game.save_path
	var bad_delivery_path := "user://missing-company-billing-delivery-" + str(OS.get_process_id()) + "/save.json"
	if tier == 3:
		var delivery_snapshot := JSON.stringify(game.state)
		game.save_path = bad_delivery_path
		_expect(not game.deliver() and JSON.stringify(game.state) == delivery_snapshot, "tier3 delivery save failure rolls back")
		game.save_path = path_before_delivery
	_expect(game.deliver(), "tier%d delivered to billing draft" % tier)
	var invoice_id := str(game.state.get("last_receipt", {}).get("invoice_id", ""))
	_expect(not invoice_id.is_empty(), "tier%d invoice id recorded" % tier)
	var invoices: Array = game.company_invoices()
	var invoice: Dictionary = {}
	for item in invoices:
		if str(item.get("id", "")) == invoice_id: invoice = item
	_expect(str(invoice.get("status", "")) == "draft", "tier%d starts as draft" % tier)
	var cash_after_delivery := int(game.state.cash)
	var receipt: Dictionary = game.completion_receipt()
	var expected_cash_delta := -int(receipt.get("cost", 0)) + int(receipt.get("material_cost", 0))
	_expect(cash_after_delivery - cash_before == expected_cash_delta, "tier%d delivery cash delta equals cost and material" % tier)
	_expect(int(game.state.profit) - profit_before == int(receipt.get("net", 0)), "tier%d delivery records operating profit once" % tier)
	if tier == 3:
		_expect(game.end_day(), "unconfirmed invoice carried to next day")
		_expect(int(game.state.cash) == cash_after_delivery and not game.state.contract_contexts.has(id), "draft persists independently of pruned completed contract")
		_expect(game.company_invoices().any(func(row): return str(row.id) == invoice_id and str(row.status) == "draft"), "unconfirmed draft cannot auto collect")
	var posted: Dictionary = {}
	if tier == 2:
		var post_snapshot := JSON.stringify(game.state)
		game.save_path = bad_delivery_path
		var failed_post: Dictionary = game.post_invoice(invoice_id)
		_expect(not bool(failed_post.get("ok", false)) and JSON.stringify(game.state) == post_snapshot, "tier2 post save failure rolls back")
		game.save_path = path_before_delivery
	posted = game.post_invoice(invoice_id)
	_expect(bool(posted.get("ok", false)), "tier%d invoice posted" % tier)
	if posted.get("invoice", {}) is Dictionary: invoice = posted.invoice
	var amount := int(invoice.get("amount", 0))
	var cash_after_post := int(game.state.cash)
	_expect(int(game.state.profit) == profit_before + int(receipt.get("net", 0)) and int(game.state.peak_profit) == peak_before, "tier%d posting does not add profit or XP" % tier)
	if immediate:
		_expect(cash_after_post == cash_after_delivery + amount, "tier%d day-zero receipt paid once" % tier)
		var repost: Dictionary = game.post_invoice(invoice_id)
		_expect(bool(repost.get("ok", false)) and int(game.state.cash) == cash_after_post, "tier%d repeated post does not pay twice" % tier)
	else:
		_expect(cash_after_post == cash_after_delivery, "tier%d deferred post does not pay immediately" % tier)
		var due_day := int(invoice.get("due_day", -1))
		var guard := 0
		while int(game.state.day) < due_day and guard < 4:
			if tier == 3 and guard == 1:
				var end_snapshot := JSON.stringify(game.state)
				game.save_path = bad_delivery_path
				_expect(not game.end_day() and JSON.stringify(game.state) == end_snapshot, "tier3 end-day save failure rolls back")
				game.save_path = path_before_delivery
			_expect(game.end_day(), "tier%d advance to due day" % tier)
			if tier == 3 and int(game.state.day) < due_day:
				_expect(int(game.state.cash) == cash_after_delivery and int(game.state.profit) == profit_before + int(receipt.get("net", 0)), "tier3 first morning remains unpaid")
			guard += 1
		_expect(int(game.state.cash) == cash_after_delivery + amount, "tier%d due receipt settled once" % tier)
		_expect(int(game.state.profit) == profit_before + int(receipt.get("net",0)), "tier%d receipt does not rebook profit" % tier)
		var latest: Dictionary = game.last_day_ledger()
		_expect(int(latest.get("due_next_day",0)) == amount and int(latest.get("next_cash",0)) == int(game.state.cash), "closeout forecasts actual next morning cash")
		var paid_count: int = game.company_payments().size()
		_expect(game.save_game(), "tier%d payment save" % tier)
		_expect(game.load_game(), "tier%d reload" % tier)
		_expect(game.company_payments().size() == paid_count and int(game.state.cash) == cash_after_delivery + amount, "tier%d reload does not duplicate payment" % tier)

func _test_legacy_contract() -> void:
	# A saved accepted contract without billing_version follows the old immediate
	# settlement path and must not create a company invoice.
	game._reset_state()
	_expect(game.choose_strategy("advisory") and game.start_free_career(), "legacy career fixture")
	game.state.peak_profit = 100000
	game.state.credit = 300
	game.state.skills.advisory = 3
	game._make_offers()
	var offer := _find_offer(1, 0)
	_expect(not offer.is_empty() and game.choose_contract(str(offer.id)), "legacy contract accepted")
	if not game.state.accepted: return
	game.state.contract.erase("billing_version")
	game.state.erase("billing")
	_expect(game.save_game() and game.load_game(), "legacy accepted save migrates empty billing records")
	_expect(not game.state.contract.has("billing_version") and game.company_invoices().is_empty(), "migration does not change accepted payment agreement")
	_expect(game.select_target(0), "legacy target selected")
	game.inspect_mission()
	var cash_before := int(game.state.cash)
	_expect(_solve_current(), "legacy real checks")
	_expect(game.can_deliver() and game.deliver(), "legacy contract delivered")
	_expect(game.company_invoices().is_empty(), "legacy delivery has no invoice")
	_expect(int(game.state.cash) > cash_before, "legacy delivery keeps immediate cash")

func _find_offer(tier: int, chapter: int) -> Dictionary:
	for offer in game.state.offers:
		if bool(offer.get("unlocked", false)) and int(offer.get("grade", 0)) == tier and int(offer.get("chapter", -1)) == chapter and str(offer.get("case_id", "")).begins_with("service-"):
			# Market demand is randomized; expose the selected fixture through the
			# same offer object so choose_contract still enforces its normal guard.
			offer.market_available = true
			return offer
	return {}

func _solve_current() -> bool:
	game.vm_run("ssh client")
	var scenario: Dictionary = game._scenario()
	var config_path := str(game.vm_info().config_path)
	if not game.vm_write(config_path, game._vm().configuration_text(scenario.get("desired", {}))): return false
	if not game.vm_run("systemctl restart " + str(game.vm_info().service)).contains("active"): return false
	if int(game.state.chapter) == 1:
		game.vm_run("restic restore latest --target /restore")
	if int(game.state.chapter) == 4:
		game.vm_run("cp /var/log/evidence.log /evidence/original.log")
	for attempt in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))): game.run_diagnostic(str(probe.get("id", "")))
		if game.diagnostic_probes().all(func(p): return bool(p.get("recorded", false)) and bool(p.get("fresh", false)) and bool(p.get("passed", false))): break
	return game.verify().all(func(check): return bool(check.get("passed", false)))

func _finish() -> void:
	for path in [game.save_path, game.backup_path, game.previous_path, game.settings_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures: push_error("COMPANY_BILLING: " + failure)
	print("COMPANY_BILLING_TEST_", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
