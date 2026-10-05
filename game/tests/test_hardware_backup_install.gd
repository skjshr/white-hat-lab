extends SceneTree

const STOCK = preload("res://scripts/customer_stock.gd")
var failures: Array[String] = []
var game
var qa_id := "hardware-backup-install-" + str(OS.get_process_id())

func _init() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("hardware backup install timeout"); quit(2))
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL ", label)

func _offer() -> Dictionary:
	for item in game.state.get("offers", []):
		if str(item.get("case_id", "")) == "hardware-backup-install" and bool(item.get("market_available", false)):
			return item
	return {}

func _find_snapshot(raw: String) -> String:
	for line in raw.split("\n"):
		var fields := line.strip_edges().split(" ", false)
		if fields.size() >= 1 and str(fields[0]) != "ID" and not str(fields[0]).is_empty():
			return str(fields[0])
	return ""

func _measure_all() -> void:
	for probe in game.diagnostic_probes():
		game.run_diagnostic(str(probe.get("id", "")))
	var checks: Array = game.verify()
	var diagnostic_checks := checks.filter(func(item): return bool(item is Dictionary and not bool(item.get("hardware", false))))
	check(not diagnostic_checks.is_empty() and diagnostic_checks.all(func(item): return bool(item is Dictionary and item.get("passed", false))), "backup commissioning verification uses real probes")

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.save_path = "user://qa-" + qa_id + ".json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	game._reset_state()
	check(game.choose_strategy("operations") and game.start_free_career(), "operations career fixture")
	game.state.skills.operations = 2
	game.state.peak_profit = 30000
	game.state.cash = 30000
	var offer := {}
	for day in 60:
		game.state.day = day + 1
		game._make_offers()
		offer = _offer()
		if not offer.is_empty(): break
	check(not offer.is_empty(), "backup appliance offer available")
	if offer.is_empty():
		_finish()
		return
	check(game.choose_contract(str(offer.get("id", ""))), "backup appliance contract accepted")
	check(str(game.state.contract.get("case_id", "")) == "hardware-backup-install", "accepted case identity")
	var quote: Dictionary = game.contract_quote(offer)
	check(int(quote.get("costs", 0)) == 5500, "quote includes operating and appliance cost")
	check(int(quote.get("invoice_total", 0)) == int(quote.get("quoted_fee", 0)) + 4800, "quote invoice total includes one appliance")
	check(int(quote.get("net", 0)) == int(quote.get("quoted_fee", 0)) - 700, "quote net excludes pass-through appliance cost")
	var wrong: Dictionary = game.buy_customer_stock(1, "gateway")
	check(bool(wrong.get("ok", false)) and wrong.get("ids", []).size() == 1, "other SKU can be stocked before assignment")
	var wrong_id := str(wrong.get("ids", [""])[0]) if wrong.get("ids", []).size() == 1 else ""
	var purchase: Dictionary = game.buy_customer_stock(1, "backup_appliance")
	check(bool(purchase.get("ok", false)) and purchase.get("ids", []).size() == 1, "backup appliance purchased")
	check(STOCK.validate(game.state.get("customer_stock", {})), "mixed SKU stock metadata validates")
	var corrupt_stock: Dictionary = game.state.get("customer_stock", {}).duplicate(true)
	if corrupt_stock.get("units", []).size() >= 2:
		corrupt_stock.units[1].id = corrupt_stock.units[0].id
		check(not STOCK.validate(corrupt_stock), "duplicate stock ID rejected")
	var invalid_stock: Dictionary = game.state.get("customer_stock", {}).duplicate(true)
	if invalid_stock.get("units", []).size() >= 1:
		invalid_stock.units[0].model = "wrong-model"
		check(not STOCK.validate(invalid_stock), "corrupt stock metadata rejected")
	if not bool(purchase.get("ok", false)):
		_finish()
		return
	var stock_id := str(purchase.ids[0])
	check(game.advance_delivery(30.0), "appliance delivery advances")
	check(not wrong_id.is_empty() and game.take_delivery(wrong_id), "other SKU received")
	var before_wrong_stage: String = game._vm()._fingerprint()
	var wrong_stage: Dictionary = game.stage_customer_stock(wrong_id)
	check(not bool(wrong_stage.get("ok", false)) and str(game.customer_stock_for(wrong_id).get("contract_id", "")).is_empty(), "wrong SKU cannot be staged on this contract")
	check(game._vm()._fingerprint() == before_wrong_stage, "wrong SKU stage leaves VM unchanged")
	check(bool(game.store_customer_stock(wrong_id).get("ok", false)), "unassigned other SKU can be stored")
	check(game.take_delivery(stock_id), "appliance received")
	check(bool(game.stage_customer_stock(stock_id).get("ok", false)), "appliance staged on backup target")
	var staged_status: Dictionary = game.work_status()
	check(int(staged_status.get("costs", 0)) == int(quote.get("costs", 0)), "work status retains quoted cost after staging")
	check(game.vm_run("ssh client").contains("Connected") or bool(game.vm_info().get("connected", false)), "staged backup target connected")
	var config: String = game._vm().configuration_text({"schedule":"daily", "repository":"local"})
	check(game.vm_write(str(game.vm_info().get("config_path", "")), config), "backup schedule staged")
	check(game.vm_run("systemctl restart restic").contains("active"), "backup service restarted")
	check(game.vm_run("restic -r local backup /srv/data").contains("snapshot"), "real backup snapshot created")
	var snapshots: String = game.vm_run("restic -r local snapshots")
	var snapshot_id := _find_snapshot(snapshots)
	check(not snapshot_id.is_empty(), "real local snapshot selected")
	var before_bad: String = game._vm()._fingerprint()
	check(game.vm_run("restic restore deadbeef --target /restore").contains("snapshot not found"), "unknown restore rejected")
	check(game._vm()._fingerprint() == before_bad, "unknown restore has no side effect")
	if not snapshot_id.is_empty():
		var save_path: String = game.save_path
		var before_failed_restore: Dictionary = game._vm().export_state()
		game.save_path = "user://missing-hardware-restore-" + qa_id + "/save.json"
		var failed_restore: String = game.vm_run("restic restore " + snapshot_id + " --target /restore")
		game.save_path = save_path
		check(failed_restore.contains("save_failed") or failed_restore.contains("507"), "restore save failure is reported")
		check(JSON.stringify(game._vm().export_state()) == JSON.stringify(before_failed_restore), "failed restore rolls VM state back")
		var restore_output: String = game.vm_run("restic restore " + snapshot_id + " --target /restore")
		check(restore_output.contains("restored"), "selected snapshot restored")
		for path in ["/srv/data/customers.csv", "/srv/data/orders.csv", "/srv/data/ledger.txt"]:
			check(not game.vm_read("/restore" + path).is_empty(), "restored required file " + path)
	_measure_all()
	check(game.take_delivery(stock_id), "verified appliance picked for dispatch")
	var dispatch_result: Dictionary = game.dispatch_customer_stock(stock_id)
	check(bool(dispatch_result.get("ok", false)), "verified appliance dispatched")
	check(game.advance_delivery(12.0), "appliance reaches customer")
	check(str(game.customer_stock_for(stock_id).get("status", "")) == "delivered", "appliance delivery completed")
	check(game.deliver(), "backup commissioning delivered")
	var receipt: Dictionary = game.completion_receipt()
	check(int(receipt.get("material_cost", 0)) == 4800 and str(receipt.get("hardware_serial", "")) == str(game.customer_stock_for(stock_id).get("serial", "")), "invoice preserves appliance cost and serial")
	check(int(receipt.get("net", 0)) == int(receipt.get("fee", 0)) + int(receipt.get("bonus", 0)) + 4800 - int(receipt.get("cost", 0)), "receipt margin includes appliance exactly once")
	var invoices: Array = game.state.get("billing", {}).get("invoices", [])
	var invoice: Dictionary = invoices[invoices.size() - 1] if not invoices.is_empty() and invoices.back() is Dictionary else {}
	check(int(invoice.get("material_cost", 0)) == 4800 and int(invoice.get("amount", 0)) == int(invoice.get("fee", 0)) + int(invoice.get("bonus", 0)) + 4800, "billing invoice has one equipment line")
	check(game.save_game() and game.load_game(), "commissioning survives save reload")
	var completed_vm: Dictionary = game._vm().export_state()
	check(bool(game._vm().backup_acceptance_view().get("enforced", false)) and game._vm().evaluate().size() == 5, "newly accepted appliance has separate restoration and original-preservation gates")
	var changed_original = load("res://scripts/virtual_machine.gd").new()
	changed_original.setup(1, completed_vm)
	changed_original.state.fs["/srv/data/ledger.txt"] = "changed after backup"
	check(not bool(changed_original.backup_acceptance_view().get("original_preserved", true)) and not changed_original.evaluate().all(func(value): return bool(value)), "independent negative model fixture rejects changed original even with matching restored copy")
	# Explicit compatibility model fixture: remove the new authored stamp from
	# a completed export to reproduce the pre-change appliance save contract.
	# This fixture does not supply the native journey's funds or success.
	var older: Dictionary = game._vm().export_state()
	older.erase("backup_authorization"); older.erase("backup_authorization_version"); older.erase("backup_restore_origins")
	older.scenario.erase("backup_preservation_required")
	older.scenario.checks = ["3台帳の日次退避、別フォルダー復元、ハッシュ照合の完了"]
	var old_files: Dictionary = older.fs.duplicate(true)
	var legacy_vm = load("res://scripts/virtual_machine.gd").new()
	legacy_vm.setup(1, JSON.parse_string(JSON.stringify(older)), load("res://scripts/case_catalog.gd").by_id("hardware-backup-install"))
	check(not legacy_vm.state.has("backup_authorization") and not bool(legacy_vm.backup_acceptance_view().get("enforced", true)), "legacy appliance is not backfilled from current catalog")
	check(legacy_vm.state.fs == old_files and legacy_vm.evaluate().size() == 3 and legacy_vm.evaluate().all(func(value): return bool(value)), "old completed appliance retains its files and original three-check acceptance")
	_finish()

func _finish() -> void:
	if failures.is_empty(): print("HARDWARE_BACKUP_INSTALL_PASS")
	else:
		for failure in failures: push_error("HARDWARE_BACKUP_INSTALL: " + failure)
		print("HARDWARE_BACKUP_INSTALL_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
