extends SceneTree
## Synthetic market eligibility; all guest work below uses the ordinary Game API.
const HOTEL = preload("res://scripts/hotel_frontdesk_model.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")
var game
var paths: Array[String] = []
var failures: Array[String] = []

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("HOTEL_FRONTDESK timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error("HOTEL_FRONTDESK: " + message)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func set_paths(values: Array) -> void:
	game.save_path = str(values[0]); game.backup_path = str(values[1])
	game.previous_path = str(values[2]); game.settings_path = str(values[3])

func hotel_offer() -> Dictionary:
	for item in game.state.offers:
		if str(item.get("case_id", "")) == "service-4-case-0": return item
	return {}

func market() -> Dictionary:
	game._reset_state()
	check(game.choose_strategy("response") and game.start_free_career(), "isolated response career starts")
	game.state.peak_profit = 60000; game.state.skills.response = 2
	game.state.day += 1; game._make_offers()
	return hotel_offer()

func accept(offer: Dictionary) -> void:
	offer.market_available = true
	check(game.choose_contract(str(offer.id)), "accept quoted hotel through Game")

func folio() -> Dictionary:
	for item in game.hotel_snapshot().get("folios", []):
		if str(item.id) == "F-204": return item
	return {}

func customer_csv() -> Dictionary:
	var files := {}
	for name in ["customers.csv", "orders.csv", "ledger.txt"]:
		files[name] = game._vm().state.fs.get("/srv/data/" + name, "")
	return files

func legacy_boundary() -> void:
	var old := market()
	# An already quoted containment-v2 offer from the previous release.
	for spec in old.target_specs:
		spec.scenario.erase("hotel_workflow_version")
		spec.scenario.checks.erase("F-204精算受付確認")
		spec.scenario.brief = str(spec.scenario.brief).get_slice("\nフロントからの依頼:", 0)
	old.brief = str(old.target_specs[0].scenario.brief)
	var prior_specs := encoded(old.target_specs)
	var prior_brief := str(old.brief)
	game._make_offers()
	old = hotel_offer()
	check(encoded(old.target_specs) == prior_specs and str(old.brief) == prior_brief, "same-day hotel offer retains the original signed scope")
	accept(old)
	game.inspect_mission(); game.vm_run("ssh client")
	var before_targets := encoded(game.state.targets)
	var before_files := encoded(game._vm().state.fs)
	var before_checks := encoded(game._vm_checks())
	check(game.save_game() and game.load_game(), "old accepted hotel roundtrips")
	check(not bool(game.hotel_snapshot().get("enabled", false)) and not game._vm().state.fs.has(HOTEL.PATH), "old accepted hotel acquires no front-desk data")
	check(encoded(game.state.targets) == before_targets and encoded(game._vm().state.fs) == before_files and encoded(game._vm_checks()) == before_checks, "old accepted files and acceptance checks remain exact")
	var before := encoded(game.state)
	check(int(game.hotel_action("F-204").code) == 404 and encoded(game.state) == before, "old accepted hotel rejects the new action without changing work")

func failed_send() -> void:
	var state_before := encoded(game.state)
	var vm_before := encoded(game._vm().export_state())
	var missing := "user://qa-hotel-missing-" + str(OS.get_process_id()) + "/missing/save.json"
	set_paths([missing, missing + ".bak", missing + ".previous", missing + ".settings"])
	var result: Dictionary = game.hotel_action("F-204")
	check(int(result.code) == 507 and not bool(result.ok), "send reports a failed save")
	check(encoded(game.state) == state_before and encoded(game._vm().export_state()) == vm_before, "failed save rolls back folio, journal, clock, cost and endpoint state")
	set_paths(paths)

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-hotel-frontdesk-" + str(OS.get_process_id())
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths)
	legacy_boundary()
	var offer := market()
	check(int(offer.target_specs[0].scenario.get("hotel_workflow_version", 0)) == 1 and int(offer.targets) == 1, "new hotel quote freezes one front desk")
	check(not CATALOG.by_id("service-4-case-0").has("hotel_workflow_version"), "catalog fallback cannot retrofit the hotel workflow")
	for item in game.state.offers:
		if str(item.get("case_id", "")) in ["service-4-case-1", "service-4-case-2"]:
			check(item.target_specs.all(func(spec): return not spec.scenario.has("hotel_workflow_version")), "other endpoint jobs retain their scope")
	accept(offer)
	var pristine := encoded(game.state)
	var original_machine = game._machine
	for _i in 5: game.hotel_snapshot()
	check(encoded(game.state) == pristine and game._machine == original_machine, "front-desk display neither materializes a VM nor charges or measures")
	check(game.hotel_snapshot().rooms.size() == 4 and folio().status == "pending" and int(folio().total) == 22800, "four real rooms contain one unsubmitted item with its actual total")
	var cash := int(game.state.cash)
	check(int(game.hotel_action("F-204").code) == 503 and folio().receipt.is_empty(), "disconnected attempt cannot receive a payment")
	game.inspect_mission(); game.vm_run("ssh client")
	var original_csv := encoded(customer_csv())
	game.vm_run("edr isolate pc_a")
	game.vm_run("edr isolate pc_b")
	var prior_cost := int(game.state.work.incident_cost)
	var blocked: Dictionary = game.hotel_action("F-204")
	check(int(blocked.code) == 403 and folio().status == "pending" and int(folio().balance) == 22800, "real PC-B isolation blocks the same folio without losing its balance")
	check(int(game.state.work.incident_cost) == prior_cost + 150 and int(game.state.cash) == cash, "blocked work accrues three minutes of business impact without moving company cash")
	check(game.save_game() and game.load_game() and int(game.hotel_snapshot().last_attempt.code) == 403 and bool(game.hotel_snapshot().isolated), "interrupted 403 and unsubmitted folio survive restart")
	failed_send()
	game.vm_run("edr release pc_b")
	game.vm_run("edr collect")
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	var pending: Array = game.verify()
	check(pending.any(func(row): return str(row.label) == "F-204精算受付確認" and not bool(row.passed)) and not game.can_deliver(), "working EDR alone cannot deliver the newly promised front-desk result")
	failed_send()
	var sent: Dictionary = game.hotel_action("F-204")
	check(bool(sent.ok) and int(sent.code) == 200 and not str(sent.receipt.number).is_empty() and folio().status == "received" and int(folio().balance) == 0, "same folio retries successfully and receives one confirmed number")
	check(str(game._vm().state.applied.pc_a) == "isolated" and str(game._vm().state.applied.pc_b) == "connected" and int(game.state.cash) == cash and encoded(customer_csv()) == original_csv, "receipt preserves containment, company cash and unrelated customer CSVs")
	var work_before := encoded(game.state.work)
	var clock_before := int(game.state.clock_minutes)
	var receipt := encoded(sent.receipt)
	var repeated: Dictionary = game.hotel_action("F-204")
	check(bool(repeated.ok) and bool(repeated.get("duplicate", false)) and encoded(repeated.receipt) == receipt and encoded(game.state.work) == work_before and int(game.state.clock_minutes) == clock_before, "duplicate send returns the same receipt without duplicate payment or work")
	check(game._vm().state.hotel_journal.filter(func(entry): return str(entry.action) == "receive").size() == 1, "hotel journal contains exactly one payment receipt")
	check(game.save_game() and game.load_game() and HOTEL.accepted(game._vm().state), "receipt and its source hash remain valid after JSON save/resume")
	var verified: Array = game.verify()
	check(not verified.is_empty() and verified.all(func(row): return bool(row.passed)) and game.can_deliver() and game.deliver(), "original EDR checks plus actual folio receipt allow delivery")
	var outcome: Dictionary = game.state.last_receipt.get("hotel_workflow", {})
	check(not outcome.is_empty() and encoded(outcome.sites[0].receipt) == receipt and bool(outcome.sites[0].reservation_isolated) and encoded(game.state.history[-1].get("hotel_workflow", {})) == encoded(outcome), "delivery and history retain the guest receipt and isolated reservation handover")
	check(game.save_game() and game.load_game() and encoded(game.state.last_receipt.get("hotel_workflow", {})) == encoded(outcome), "delivered hotel result persists across restart")
	finish()

func finish() -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("HOTEL_FRONTDESK_TEST_PASS" if failures.is_empty() else "HOTEL_FRONTDESK_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
