extends SceneTree

## Eligibility fixture only: Lv.7 / operations 2 make the authored backup case
## eligible. Cash, time, repair state, evidence, checks and delivery are real.
## This is public Game acceptance coverage, not a new-player progression claim.
const CASE_ID := "service-1-case-3"
const LEDGER := "/srv/data/ledger.txt"
const ORDERS := "/srv/data/orders.csv"
const RECOVERED := "/restore/srv/data/ledger.txt"
var game
var failures: Array[String] = []
var assertions := 0
var save_file := ""

func _init() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("backup integration timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL backup_authorization_integration: ", label)

func wire(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func restore(snapshot: String, target: String = "/restore", source: String = LEDGER) -> String:
	return game.vm_run("restic -r offsite restore %s --target %s --include %s --overwrite always" % [snapshot,target,source])

func measure() -> Array:
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	return game.verify()

func passed(rows: Array) -> bool:
	return not rows.is_empty() and rows.all(func(row): return bool(row.get("passed", false)))

func projection() -> Dictionary:
	return {"vm":game._vm().export_state(),"work":game.state.work,"clock":game.clock_minutes(),"revision":game.state.revision,"validated":game.state.validated_revision,"checks":game.state.checks,"cash":game.state.cash,"profit":game.state.profit,"history":game.state.history,"targets":game.state.targets,"billing":game.state.billing}

func run() -> void:
	await process_frame
	game = root.get_node("Game"); game.set_process(false)
	save_file = "user://backup-authorization-integration-" + str(OS.get_process_id()) + ".json"
	game.save_path = save_file; game.backup_path = save_file + ".bak"; game.previous_path = save_file + ".previous"; game.settings_path = save_file + ".settings"
	check(game.new_game(), "start normal-funded Game")
	check(int(game.state.cash) == 5000 and game.state.history.is_empty(), "no cash or completion injection")
	check(game.choose_strategy("operations"), "choose operations through public API")
	# Explicit capability fixture, no money, time or successful outcome fixture.
	game.state.peak_profit = 35000
	game.state.skills.operations = 2
	check(int(game.company_level().level) == 7, "labelled Lv.7 eligibility fixture remains below multi-site unlock")
	check(game.start_free_career(), "enter ordinary public contract market")
	var offer := {}
	for attempt in 14:
		for candidate in game.state.offers:
			if str(candidate.get("case_id", "")) == CASE_ID and bool(candidate.get("unlocked", false)) and bool(candidate.get("market_available", false)): offer = candidate; break
		if not offer.is_empty(): break
		check(game.end_day(), "advance actual market day while awaiting eligible authored work")
	check(not offer.is_empty(), "authored backup request actually offered within real market rotation")
	if offer.is_empty(): finish(); return
	check(int(game.state.cash) == 5000, "waiting did not inject money")
	check(game.set_offer_plan("standard"), "select standard delivery plan")
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).reference_fee)), "submit actual reference quote")
	check(game.choose_contract(str(offer.id)), "accept real available authored contract")
	check(game.state.targets.size() == 1 and str(game.state.contract.case_id) == CASE_ID, "accepted one actual backup target")
	game.inspect_mission(); game.vm_run("ssh client")
	check(bool(game.vm_info().connected), "connect to customer backup machine")
	check(game.capture_baseline(), "record before-work evidence through public API")
	var machine = game._vm()
	var initial_ledger: String = game.vm_read(LEDGER)
	var initial_orders: String = game.vm_read(ORDERS)
	var authorization: String = wire(machine.state.backup_authorization)
	check(initial_ledger == "CORRUPTED DATA\n", "customer symptom corresponds to actual unreadable ledger bytes")
	var inventory: String = game.vm_run("restic -r offsite snapshots")
	var manifest: String = game.vm_read("/home/operator/recovery-manifest.sha256")
	var expected := ""
	for line in manifest.split("\n"):
		if line.ends_with(RECOVERED): expected = line.get_slice(" ", 0)
	check(expected.length() == 64, "customer manifest names actual isolated restored file path")
	var good := ""; var bad := ""
	# Inspect actual public repository inventory and stored bytes; do not assign
	# scenario.desired or fabricate a successful restoration/check record.
	for snapshot in machine.state.snapshots:
		if str(snapshot.repository) != "offsite": continue
		var id := str(snapshot.id)
		check(inventory.contains(id), "snapshot ID is exposed by real inventory")
		var bytes: String = game.vm_run("restic -r offsite dump %s %s" % [id, LEDGER])
		if bytes.sha256_text() == expected: good = id
		else: bad = id
	check(not good.is_empty() and not bad.is_empty(), "real stored content distinguishes good and bad versions")
	if good.is_empty() or bad.is_empty(): finish(); return
	check(restore(bad).begins_with("restored"), "actual incorrect snapshot restore executes")
	check(not passed(measure()) and not game.can_deliver(), "wrong restored bytes cannot be accepted")
	check(game.vm_read(LEDGER) == initial_ledger and game.vm_read(ORDERS) == initial_orders, "failed candidate restore preserved running source files")
	check(game.save_game(), "save incomplete recovery")
	var before_reload := wire(projection())
	check(game.load_game(), "reopen incomplete recovery")
	check(wire(projection()) == before_reload, "reopen preserves failed restoration, immutable baseline, time and diagnostics")
	var before_failed_write := wire(projection())
	game.save_path = save_file + ".missing/save.json"
	check(restore(good).contains("save_failed"), "failed durable save reports failed restoration")
	game.save_path = save_file
	check(wire(projection()) == before_failed_write, "failed save rolls back restored bytes, origins, baseline, work and checks")
	check(restore(good).begins_with("restored"), "retry correct selected restore succeeds")
	check(passed(measure()) and game.can_deliver(), "correct bytes and preserved original/unrelated data meet actual acceptance")
	check(wire(game._vm().state.backup_authorization) == authorization, "correct restoration never rebases approved intake record")
	check(game.vm_write(LEDGER, "operator replaced the original\n"), "exercise actual original overwrite mistake")
	var original_failed: Array = measure()
	check(not passed(original_failed) and not game.can_deliver(), "correct recovery cannot hide original destruction")
	check(not bool(game._vm().backup_acceptance_view().original_preserved), "failed original condition is reported explicitly")
	check(restore(bad, "/").begins_with("restored"), "restore original intake bytes from the actual damaged snapshot")
	check(restore(good).begins_with("restored"), "recover handoff ledger again after original repair")
	check(game.vm_write(ORDERS, "operator changed unrelated orders\n"), "exercise actual unrelated file change")
	check(not passed(measure()) and not game.can_deliver(), "unrelated live data damage prevents customer acceptance")
	check(not bool(game._vm().backup_acceptance_view().unrelated_preserved), "failed unrelated condition is reported explicitly")
	check(restore(good, "/", ORDERS).begins_with("restored"), "recover original orders bytes via actual repository")
	check(game.vm_read(LEDGER) == initial_ledger and game.vm_read(ORDERS) == initial_orders, "recovery repaired mistakes without replacing the live ledger")
	check(passed(measure()) and game.can_deliver(), "fresh verification allows corrected preservation failures to recover")
	check(wire(game._vm().state.backup_authorization) == authorization, "all writes and reopen preserve original baseline")
	var final_view: Dictionary = game._vm().backup_acceptance_view()
	check(str(final_view.selected_snapshot) == good and str(final_view.restored[0].path) == RECOVERED, "customer handoff evidence names the ledger's actual snapshot and file")
	var before_delivery: String = JSON.stringify(game.state)
	game.save_path = save_file + ".missing/save.json"
	check(not game.deliver(), "delivery refuses failed durable save")
	game.save_path = save_file
	check(JSON.stringify(game.state) == before_delivery, "failed delivery rolls back receipt, finances and completion")
	check(game.deliver(), "retry actual acceptance and delivery succeeds")
	check(passed(game.state.last_receipt.checks), "receipt retains real verification including both preservation checks")
	check(game.state.last_receipt.checks.any(func(row): return str(row.get("label", "")).contains("原本")), "saved receipt records original preservation acceptance")
	check(not str(game.state.last_receipt.get("invoice_id", "")).is_empty(), "normal invoice is created by delivery")
	var completed := wire(projection())
	check(not game.deliver() and wire(projection()) == completed, "duplicate delivery gives no duplicate income or result")
	check(game.save_game(), "save accepted recovery")
	var receipt := wire(game.state.last_receipt)
	var completed_vm := wire(game._vm().export_state())
	check(game.load_game(), "reopen accepted recovery")
	check(wire(game.state.last_receipt) == receipt and wire(game._vm().export_state()) == completed_vm, "reopen preserves immutable receipt and recovered/source bytes")
	print("BACKUP_INTEGRATION_OUTCOME ", JSON.stringify({"eligibility_fixture":"Lv.7 / operations 2","case_id":CASE_ID,"day":game.state.day,"rating":game.state.last_receipt.rating,"cash":game.state.cash,"snapshot":final_view.selected_snapshot,"restored_path":RECOVERED,"production_original_unchanged":game.vm_read(LEDGER) == initial_ledger}))
	finish()

func finish() -> void:
	print("BACKUP_AUTHORIZATION_INTEGRATION ", JSON.stringify({"assertions":assertions,"failures":failures.size(),"details":failures}))
	quit(0 if failures.is_empty() else 1)
