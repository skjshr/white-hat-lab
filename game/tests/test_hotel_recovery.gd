extends SceneTree
## A completed hotel save drives the next working day. Without a supplied save,
## build a synthetic QA company and complete the source job through Game APIs.
## --fixture=ABS or WHL_HOTEL_RECOVERY_FIXTURE keeps an external save read-only.
const HANDOFF = preload("res://scripts/hotel_handoff.gd")
const RECOVERY = preload("res://scripts/hotel_recovery.gd")
const HOTEL = preload("res://scripts/hotel_frontdesk_model.gd")
const CYCLE = preload("res://scripts/company_cycle.gd")
var game
var paths: Array[String] = []
var cancellation_paths: Array[String] = []
var cancellation_fixture_ready := false
var failures: Array[String] = []
var fixture_path := ""
var fixture_hash := ""
var generated_fixture_path := ""

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("HOTEL_RECOVERY timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	if not ok: failures.append(label); push_error("HOTEL_RECOVERY: " + label)
	return ok

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func set_paths(values: Array) -> void:
	game.save_path = str(values[0]); game.backup_path = str(values[1])
	game.previous_path = str(values[2]); game.settings_path = str(values[3])

func command(value: String) -> Dictionary:
	var result: Variant = JSON.parse_string(str(game.vm_run(value)))
	return result if result is Dictionary else {}

func offer() -> Dictionary:
	for item in game.state.offers:
		if str(item.get("case_id", "")) == HANDOFF.CASE_ID: return item
	return {}

func impact() -> Dictionary:
	return game.state.work.get("endpoint_impact", {}).get("0", {})

func reservation() -> Dictionary:
	return game.hotel_snapshot().get("reservation", {})

func read_only_views(label: String) -> void:
	var before := encoded(game.state)
	var machine = game._machine
	var saved := encoded(machine.export_state()) if machine != null else ""
	for _i in 3:
		game.hotel_snapshot(); game.company_cycle_view(); game.market_summary()
		CYCLE.hotel_recovery_records(game.state, int(game.state.day))
		HANDOFF.pending_records(game.state, int(game.state.day))
	check(encoded(game.state) == before and game._machine == machine and (machine == null or encoded(machine.export_state()) == saved), label)

func preserve_check(source: Dictionary, original_vm: Dictionary) -> void:
	var saved: Dictionary = game._vm().state
	check(str(saved.fs.get(HOTEL.PATH, "")) == str(source.folio_content) and encoded(saved.get("hotel_journal", [])) == encoded(source.hotel_journal) and str(saved.fs.get(RECOVERY.EVIDENCE_PATH, "")) == str(source.evidence_content) and RECOVERY.preserved(saved), "previous folio bytes, receipt journal and handoff evidence survive all recovery actions exactly")
	var prior: Dictionary = game.state.vm_states.get(str(source.source_vm_key), {})
	check(encoded(prior.get("fs", {})) == encoded(original_vm.fs) and encoded(prior.get("hotel_journal", [])) == encoded(original_vm.hotel_journal) and encoded(prior.get("scenario", {})) == encoded(original_vm.scenario), "old v1 customer files, journal and agreed scope remain unchanged")

func failed_save() -> void:
	var before := encoded(game.state)
	var saved := encoded(game._vm().export_state())
	var missing := "user://qa-hotel-recovery-missing-" + str(OS.get_process_id()) + "/save.json"
	set_paths([missing, missing + ".bak", missing + ".previous", missing + ".settings"])
	var result: Dictionary = game.hotel_action(RECOVERY.ID)
	check(int(result.get("code", 0)) == 507 and not bool(result.get("ok", true)) and encoded(game.state) == before and encoded(game._vm().export_state()) == saved, "failed reservation save rolls back file, journal, receipt, clock and compensation together")
	set_paths(paths)

func synthetic_fixture(prefix: String) -> String:
	print("HOTEL_RECOVERY_FIXTURE_SYNTHETIC: QA funds, level, skill and market slot; not native-play evidence")
	game._reset_state()
	if not check(game.choose_strategy("response") and game.start_free_career(), "synthetic QA response company starts"):
		return ""
	# Fixture eligibility only. Customer files, evidence, receipts and delivery
	# results below are produced by the same operations as a normal contract.
	game.state.cash = 100000; game.state.peak_profit = 60000
	game.state.skills.response = 2; game.state.day = 9
	if not check(game.end_day() and int(game.state.day) == 10, "synthetic company enters DAY10 through normal day close"):
		return ""
	var hotel: Dictionary = {}
	for candidate in game.state.offers:
		if str(candidate.get("case_id", "")) == HANDOFF.SOURCE_CASE_ID: hotel = candidate
	if not check(not hotel.is_empty(), "synthetic DAY10 has the source hotel quote"):
		return ""
	hotel.market_available = true
	if not check(game.choose_contract(str(hotel.id)) and int(game.state.targets[0].scenario.get("hotel_workflow_version", 0)) == 1, "synthetic source accepts the ordinary v1 hotel scope"):
		return ""
	game.inspect_mission(); game.vm_run("ssh client")
	if not check(bool(command("edr isolate pc_a").get("ok", false)) and bool(game.hotel_action("F-204").get("ok", false)) and bool(command("edr collect").get("ok", false)), "synthetic source actually isolates PC-A, receives F-204 and preserves evidence"):
		return ""
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	var verified: Array = game.verify()
	if not check(not verified.is_empty() and verified.all(func(row): return bool(row.passed)) and game.can_deliver() and game.deliver(), "synthetic source obtains a genuine model delivery record through measurement and delivery"):
		return ""
	var invoice_id := str(game.state.last_receipt.get("invoice_id", ""))
	if not invoice_id.is_empty() and not check(bool(game.post_invoice(invoice_id).get("ok", false)), "synthetic source posts its actual invoice"):
		return ""
	generated_fixture_path = prefix + "-generated-source.json"
	if not check(game.save_game() and DirAccess.copy_absolute(ProjectSettings.globalize_path(paths[0]), ProjectSettings.globalize_path(generated_fixture_path)) == OK, "save the generated DAY10 source in its own QA fixture"):
		return ""
	return ProjectSettings.globalize_path(generated_fixture_path)

func cancellation_path(source: Dictionary, original_vm: Dictionary) -> void:
	# Fork only the already accepted QA save; do not replay the completed work.
	set_paths(cancellation_paths)
	if not check(game.load_game(), "load the independent accepted recovery copy for cancellation"):
		return
	var cancelled_id := str(game.state.current_contract_id)
	var source_id := str(source.source_contract_id)
	var handoff_before := encoded(game.state.company_cycle.hotel_recoveries[source_id].handoff)
	var lead_before := encoded(game.state.company_cycle.leads.get(HANDOFF.CLIENT, {}))
	if not check(game.cancel_current_contract(), "cancel the accepted recovery through the normal closeout API"):
		return
	var record: Dictionary = game.state.company_cycle.hotel_recoveries[source_id]
	check(str(record.status) == "pending" and int(record.available_day) == 12 and str(record.accepted_contract_id).is_empty() and encoded(record.handoff) == handoff_before and encoded(game.state.company_cycle.leads.get(HANDOFF.CLIENT, {})) == lead_before, "cancellation preserves the original source and unrelated consultation while postponing re-quotation")
	var before := encoded(game.state)
	check(not game.choose_contract(cancelled_id) and CYCLE.hotel_recovery_available(game.state, 11).is_empty() and encoded(game.state) == before, "cancelled recovery cannot be accepted again on the same day")
	if not check(game.save_game() and game.load_game() and game.end_day(), "cancelled recovery survives restart and advances to its next quotation day"):
		return
	var next_offer := offer()
	if not check(int(game.state.day) == 12 and not next_offer.is_empty() and bool(next_offer.get("market_available", false)) and str(next_offer.get("id", "")) != cancelled_id and str(next_offer.get("hotel_recovery_source_contract_id", "")) == source_id, "next business day offers one fresh quote for the same preserved source"):
		return
	var quote: Dictionary = game.contract_quote(next_offer)
	if not check(not quote.is_empty() and bool(quote.get("affordable", false)) and game.choose_contract(str(next_offer.id)), "fresh quote can be accepted through the regular contract flow"):
		return
	check(encoded(game.state.targets[0].scenario.get("hotel_handoff", {})) == handoff_before and game.state.contract_closeouts.has(cancelled_id), "re-acceptance retains both immutable handoff and the earlier cancellation record")
	preserve_check(source, original_vm)

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-hotel-recovery-" + str(OS.get_process_id())
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	cancellation_paths.assign([prefix + "-cancel.json", prefix + "-cancel.json.bak", prefix + "-cancel.json.previous", prefix + "-cancel.settings"])
	set_paths(paths)
	fixture_path = OS.get_environment("WHL_HOTEL_RECOVERY_FIXTURE")
	var external_fixture := not fixture_path.is_empty()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): fixture_path = arg.trim_prefix("--fixture="); external_fixture = true
	if not external_fixture: fixture_path = synthetic_fixture(prefix)
	else: print("HOTEL_RECOVERY_FIXTURE_EXTERNAL_READ_ONLY: ", fixture_path)
	if not check(not fixture_path.is_empty() and FileAccess.file_exists(fixture_path), "completed hotel source fixture exists"):
		finish(); return
	fixture_hash = FileAccess.get_sha256(fixture_path)
	var original: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not check(original is Dictionary, "source fixture parses as a save dictionary"):
		finish(); return
	var original_encoded := encoded(original)
	var source: Dictionary = {}
	for row in original.get("history", []):
		var candidate := HANDOFF.capture_source(original, str(row.get("id", "")))
		if not candidate.is_empty(): source = candidate
	if not check(not source.is_empty() and int(source.day) == 10, "saved DAY10 delivery proves F-204, isolated PC-A and measured evidence"):
		finish(); return
	var old_vm: Dictionary = original.vm_states[str(source.source_vm_key)].duplicate(true)
	check(encoded(original) == original_encoded and HANDOFF.scenario(source, 10).is_empty(), "source capture is pure and cannot manufacture a same-day follow-up")
	var missing: Dictionary = original.duplicate(true)
	missing.vm_states[str(source.source_vm_key)].fs.erase("/evidence/original.log")
	var missing_before := encoded(missing)
	check(HANDOFF.capture_source(missing, str(source.source_contract_id)).is_empty() and encoded(missing) == missing_before and HANDOFF.scenario({}, 11).is_empty(), "missing original evidence rejects the source without inventing replacement data")
	CYCLE.refresh_hotel_recoveries(missing, 11)
	check(CYCLE.hotel_recovery_available(missing, 11).is_empty(), "missing-source save receives no bookable recovery request")
	if not check(DirAccess.copy_absolute(fixture_path, ProjectSettings.globalize_path(paths[0])) == OK and game.load_game(), "load an isolated copy of the completed DAY10 save"):
		finish(); return
	read_only_views("history, market and old hotel views do not backfill requests or change work")
	check(not game.state.vm_states[str(source.source_vm_key)].fs.has(RECOVERY.PATH) and int(game.hotel_snapshot().get("workflow_version", 0)) == 1, "loaded v1 delivery gains no reservation file or new delivery condition")
	if not check(game.end_day() and int(game.state.day) == 11 and not offer().is_empty(), "ordinary DAY10 close produces the DAY11 proof-bound recovery offer"):
		finish(); return
	read_only_views("DAY11 market reads leave the saved offer and source record untouched")
	var selected := offer()
	if not check(bool(selected.get("market_available", false)) and game.choose_contract(str(selected.id)), "accept the offered follow-up without changing eligibility or market flags"):
		finish(); return
	cancellation_fixture_ready = DirAccess.copy_absolute(ProjectSettings.globalize_path(paths[0]), ProjectSettings.globalize_path(cancellation_paths[0])) == OK
	check(cancellation_fixture_ready, "copy the accepted QA save for the independent cancellation path")
	var contract_id := str(game.state.current_contract_id)
	check(int(game.state.targets[0].scenario.get("hotel_workflow_version", 0)) == 2 and bool(reservation().get("isolated", false)) and int(reservation().get("arrival_day", 0)) == 12 and str(reservation().get("status", "")) == "pending", "new contract starts with isolated PC-A and one DAY12 reservation")
	game.inspect_mission(); game.vm_run("ssh client")
	var cash_before := int(game.state.cash)
	var blocked: Dictionary = game.hotel_action(RECOVERY.ID)
	check(int(blocked.get("code", 0)) == 403 and str(reservation().status) == "pending" and reservation().receipt.is_empty(), "isolation blocks the actual pending reservation with no booking number")
	command("edr collect")
	check(bool(command("edr release pc_a").get("ok", false)), "premature release applies to the real reservation endpoint")
	var send_before := float(impact().get("send_minutes", 0))
	var scan := command("edr scan pc_a")
	check(float(impact().get("send_minutes", 0)) > send_before and int(scan.get("threat_count", 0)) > 0 and not game._vm().evaluate().all(func(value): return bool(value)), "premature release resumes malicious send compensation and cannot satisfy security delivery")
	check(bool(RECOVERY.plan(game._vm().state, RECOVERY.ID, int(game.state.day), game.business_clock()).get("ok", false)), "business transport can work before remediation without pretending the endpoint is safe")
	var wrong := command("edr quarantine pc_a pc_a-backup")
	var quarantine_id := int(wrong.get("quarantine_id", -1))
	var stop_before := float(impact().get("stop_minutes", 0))
	var unavailable: Dictionary = game.hotel_action(RECOVERY.ID)
	check(quarantine_id > 0 and int(unavailable.get("code", 0)) == 503 and str(reservation().status) == "pending" and float(impact().get("stop_minutes", 0)) > stop_before, "quarantining the approved backup stops the same reservation and adds business compensation")
	var interrupted := encoded(game._vm().export_state())
	var cost_before := encoded(game.state.work)
	if not check(game.save_game() and game.load_game(), "save and JSON reload during the interrupted recovery"):
		finish(); return
	check(encoded(game._vm().export_state()) == interrupted and encoded(game.state.work) == cost_before and int(reservation().last_attempt.code) == 503, "restart retains the exact quarantine, pending reservation, response and compensation")
	check(bool(command("edr restore " + str(quarantine_id)).get("ok", false)) and bool(reservation().business_available), "restoring that quarantine entry returns the actual business file")
	check(bool(command("edr quarantine pc_a pc_a-sync").get("ok", false)) and bool(command("edr scan pc_a").get("clean", false)) and bool(command("edr scan pc_b").get("clean", false)), "remove actual malicious bytes and scan both endpoints")
	var pending: Array = game._vm().evaluate()
	check(pending.size() == 5 and bool(pending[0]) and bool(pending[1]) and bool(pending[2]) and not bool(pending[3]) and bool(pending[4]), "healthy endpoints and intact evidence still require the promised reservation")
	failed_save()
	var received: Dictionary = game.hotel_action(RECOVERY.ID)
	if not check(bool(received.get("ok", false)) and str(reservation().status) == "imported" and not str(received.get("receipt", {}).get("bookingno", "")).is_empty(), "retry imports the same reservation and returns its confirmed booking number"):
		finish(); return
	var receipt := encoded(received.receipt)
	var work_before := encoded(game.state.work)
	var clock_before := int(game.state.clock_minutes)
	var repeated: Dictionary = game.hotel_action(RECOVERY.ID)
	check(bool(repeated.get("ok", false)) and bool(repeated.get("duplicate", false)) and encoded(repeated.get("receipt", {})) == receipt and encoded(game.state.work) == work_before and int(game.state.clock_minutes) == clock_before and int(game.state.cash) == cash_before and game._vm().state.reservation_journal.filter(func(entry): return str(entry.get("action", "")) == "import").size() == 1, "duplicate import keeps one receipt and adds neither time, compensation nor company payment")
	preserve_check(source, old_vm)
	read_only_views("front desk, history and market remain pure after recovery")
	check(game.save_game() and game.load_game() and RECOVERY.accepted(game._vm().state), "confirmed reservation and journal survive JSON restart")
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	var checks: Array = game.verify()
	if not check(not checks.is_empty() and checks.all(func(row): return bool(row.passed)) and game.can_deliver() and game.deliver(), "measured recovery, reservation receipt and preserved prior records permit delivery"):
		finish(); return
	var delivered: Dictionary = game.state.last_receipt.get("hotel_workflow", {})
	var archived: Array = game.state.history.filter(func(row): return str(row.get("id", "")) == contract_id)
	check(not delivered.get("sites", []).is_empty() and int(delivered.sites[0].get("workflow_version", 0)) == 2 and encoded(delivered.sites[0].get("reservation", {}).get("receipt", {})) == receipt and bool(delivered.sites[0].reservation.get("handoff_preserved", false)) and archived.size() == 1 and encoded(archived[0].get("hotel_workflow", {})) == encoded(delivered), "delivery receipt and history retain the real booking and prior-file preservation result")
	var record: Dictionary = game.state.company_cycle.get("hotel_recoveries", {}).get(str(source.source_contract_id), {})
	check(str(record.get("status", "")) == "fulfilled" and str(record.get("accepted_contract_id", "")) == contract_id, "delivery fulfills this source request")
	var events_before: int = game.state.company_cycle.events.filter(func(entry): return str(entry.get("kind", "")) == "hotel_recovery_requested" and str(entry.get("contract_id", "")) == str(source.source_contract_id)).size()
	check(game.end_day() and offer().is_empty() and HANDOFF.pending_records(game.state, int(game.state.day)).is_empty() and game.state.company_cycle.events.filter(func(entry): return str(entry.get("kind", "")) == "hotel_recovery_requested" and str(entry.get("contract_id", "")) == str(source.source_contract_id)).size() == events_before, "following business day cannot generate the fulfilled source a second time")
	if cancellation_fixture_ready: cancellation_path(source, old_vm)
	finish()

func finish() -> void:
	if not fixture_hash.is_empty(): check(FileAccess.get_sha256(fixture_path) == fixture_hash, "source fixture remains byte-for-byte untouched")
	if not generated_fixture_path.is_empty() and FileAccess.file_exists(generated_fixture_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(generated_fixture_path))
	for path in paths + cancellation_paths + ([str(paths[0]) + ".tmp", str(cancellation_paths[0]) + ".tmp"] if not paths.is_empty() else []):
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("HOTEL_RECOVERY_TEST_PASS" if failures.is_empty() else "HOTEL_RECOVERY_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
