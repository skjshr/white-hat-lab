extends SceneTree

var failures: Array[String] = []
var game
var qa_id := str(OS.get_process_id())

func _init() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("business workspace timeout"); quit(2))
	call_deferred("run")

func _assert(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func _json(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}

func _target(chapter: int) -> int:
	for index in game.state.targets.size():
		if int(game.state.targets[index].get("chapter", -1)) == chapter: return index
	return -1

func _ssh(index: int) -> bool:
	_assert(game.select_target(index), "select target %d" % index)
	var response: String = game.vm_run("ssh client")
	_assert(not response.is_empty() and bool(game.vm_info().get("connected", false)), "connect target %d" % index)
	return bool(game.vm_info().get("connected", false))

func _measure_current(label: String) -> void:
	for probe in game.diagnostic_probes():
		var output: String = game.run_diagnostic(str(probe.get("id", "")))
		_assert(not output.is_empty(), "%s probe %s output" % [label, str(probe.get("id", ""))])
	var checks: Array = game.verify()
	_assert(not checks.is_empty(), "%s verification exists" % label)
	_assert(checks.all(func(item): return bool(item is Dictionary and item.get("passed", false))), "%s verification passes" % label)

func _find_known_good_snapshot(output: String) -> String:
	# The test selects from the real restic listing, never inventing an ID.
	for line in output.split("\n"):
		var columns := line.strip_edges().split(" ", false)
		if columns.size() >= 4 and str(columns[0]) != "ID" and str(columns[1]) == "offsite":
			if str(columns[0]) == "00000001": return str(columns[0])
	return ""

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var save_path := "user://qa-business-workspace-" + qa_id + ".json"
	game.save_path = save_path
	game.backup_path = save_path + ".bak"
	game.previous_path = save_path + ".previous"
	game.settings_path = save_path + ".settings"
	game._reset_state()
	_assert(game.choose_strategy("response") and game.start_free_career(), "response career fixture")
	game.state.skills.advisory = 10
	game.state.skills.operations = 10
	game.state.skills.response = 10
	game.state.profit = 1000000
	game.state.peak_profit = 1000000
	game._update_growth()

	var offer: Dictionary = {}
	for day in 60:
		game.state.day = day + 1
		game._make_offers()
		for candidate in game.state.offers:
			if str(candidate.get("case_id", "")) == "composite-corruption-response" and bool(candidate.get("market_available", false)):
				offer = candidate
				break
		if not offer.is_empty(): break
	_assert(not offer.is_empty(), "composite corruption offer available")
	if offer.is_empty():
		_finish()
		return
	_assert(game.set_offer_quote(str(offer.get("id", "")), int(offer.get("reward", offer.get("base_reward", 0)))) and game.choose_contract(str(offer.get("id", ""))), "composite accepted through production APIs")
	_assert(int(game.state.contract.get("linked_business_version", 0)) == 1, "linked business contract version")
	var accepted_raw: String = FileAccess.get_file_as_string(game.save_path)
	var edr_index := _target(4)
	var backup_index := _target(1)
	var firewall_index := _target(2)
	_assert(edr_index >= 0 and backup_index >= 0 and firewall_index >= 0, "three linked targets present")
	if edr_index < 0 or backup_index < 0 or firewall_index < 0:
		_finish()
		return

	# Investigate and contain the actual suspect endpoint, retaining the evidence copy.
	if _ssh(edr_index):
		_assert(game.vm_run("edr devices").contains("pc_b"), "EDR device inventory")
		_assert(game.vm_run("edr timeline pc_b").contains("pc_b"), "EDR suspect timeline")
		var collected := _json(game.vm_run("edr collect"))
		_assert(int(collected.get("code", 0)) == 200 and bool(collected.get("ok", false)), "EDR evidence collected")
		var isolated := _json(game.vm_run("edr isolate pc_b"))
		_assert(int(isolated.get("code", 0)) == 200 and bool(isolated.get("ok", false)), "EDR PC-B isolated")

	# Configure and inspect the backup service through its real command surface.
	var good_snapshot := ""
	if _ssh(backup_index):
		var backup_config := "schedule=daily\nrepository=offsite\n"
		_assert(game.vm_write(str(game.vm_info().get("config_path", "")), backup_config), "backup config staged")
		_assert(game.vm_run("systemctl restart restic").contains("active"), "backup service active")
		var snapshots: String = game.vm_run("restic -r offsite snapshots")
		good_snapshot = _find_known_good_snapshot(snapshots)
		_assert(not good_snapshot.is_empty(), "known good offsite snapshot selected from listing")
		if not good_snapshot.is_empty():
			_assert(game.vm_run("restic -r offsite restore "+good_snapshot+":/srv/data --target /restore").contains("restored"), "restore selected snapshot to staging")
			var staged_ledger: String = game.vm_read("/restore/ledger.txt")
			_assert(staged_ledger.contains("closing=62800"), "staged ledger is known good")

	# Configure the gateway, then prove that staging alone does not change production business data.
	if _ssh(firewall_index):
		var gateway_values := {"dns":"on","business":"allow","admin_public":"deny","tls":"on"}
		var gateway_config: String = game._vm().configuration_text(gateway_values)
		_assert(game.vm_write(str(game.vm_info().get("config_path", "")), gateway_config), "gateway policy staged")
		_assert(game.vm_run("systemctl restart firewall").contains("active"), "gateway service active")
		var before_copy: String = game.vm_run("curl https://intranet.client.test/api/business/ledger")
		_assert(before_copy.contains("422") or before_copy.contains("404"), "production ledger remains invalid before copy")

	# Select the backup target and copy restored content into production, not merely /restore.
	var staged_before: String = ""
	if _ssh(backup_index):
		staged_before = game.vm_read("/restore/ledger.txt")
		_assert(not staged_before.is_empty(), "staging remains available")
		var real_save: String = game.save_path
		game.save_path = "user://qa-business-copy-failure-" + qa_id + "/save.json"
		var failed_copy: String = game.vm_run("cp /restore/ledger.txt /srv/data/ledger.txt")
		game.save_path = real_save
		_assert(failed_copy.contains("save_failed") or failed_copy.contains("507"), "copy save failure is reported")
		_assert(game.vm_read("/srv/data/ledger.txt").contains("CORRUPTED DATA"), "failed copy rolls production back")
		_assert(game.vm_run("cp /restore/ledger.txt /srv/data/ledger.txt") == "", "restored ledger copied into production")

	# The linked gateway must observe the real production file and stale its old measurement.
	if _ssh(firewall_index):
		var linked_response: String = game.vm_run("curl https://intranet.client.test/api/business/ledger")
		_assert(linked_response.contains("200") and linked_response.contains("62800"), "employee business ledger reads restored production data")
		_assert(linked_response.contains(staged_before.sha256_text()), "business response carries actual ledger hash")
		_assert(game.vm_run("curl https://intranet.client.test/api/business/missing").contains("404"), "unknown business resource is 404")
		_assert(game.vm_run("curl -X PUT https://intranet.client.test/api/business/ledger").contains("405"), "business endpoint rejects non-GET")

	# Re-measure every target through the ordinary verification path before testing
	# provider freshness. This establishes a real deliverable state first.
	for index in [edr_index, backup_index, firewall_index]:
		if _ssh(index): _measure_current("linked target %d" % index)
	_assert(game.can_deliver(), "all linked targets deliverable before provider mutation")

	# A missing production file is distinct from a malformed one and must be
	# surfaced by the employee endpoint as a real 404.
	if _ssh(backup_index):
		_assert(game.vm_run("rm /srv/data/ledger.txt").is_empty(), "production ledger removed for missing-file test")
	if _ssh(firewall_index):
		_assert(game.vm_run("curl https://intranet.client.test/api/business/ledger").contains("404"), "missing production ledger returns 404")
	if _ssh(backup_index):
		_assert(game.vm_run("cp /restore/ledger.txt /srv/data/ledger.txt") == "", "production ledger restored after missing-file test")

	# A malformed production ledger is an application-data failure, not a backup
	# service outage; the gateway must observe 422 and invalidate its old probe.
	if _ssh(backup_index):
		_assert(game.vm_write("/srv/data/ledger.txt", "malformed ledger\n"), "malformed production ledger written")
	if _ssh(firewall_index):
		var malformed_response: String = game.vm_run("curl https://intranet.client.test/api/business/ledger")
		_assert(malformed_response.contains("422"), "malformed ledger returns 422")
		_assert(not game.can_deliver(), "provider mutation stales previously passing delivery")
	if _ssh(backup_index):
		var recovery_command := "restic -r local restore 00000001 --target / --include /srv/data/ledger.txt --overwrite always"
		var machine = game._vm()
		# The seed repository is contract data, rather than a UI assumption.
		for snapshot in machine.state.snapshots:
			if str(snapshot.get("id", "")) == "00000001":
				recovery_command = recovery_command.replace("-r local", "-r " + str(snapshot.repository))
		var before_preview: Dictionary = machine.export_state()
		var before_clock: int = game.clock_minutes()
		var before_work: Dictionary = game.state.work.duplicate(true)
		var preview_result: String = game.vm_run(recovery_command + " --dry-run --verbose=2")
		_assert(not preview_result.begins_with("restic:"), "selective production preview accepted")
		_assert(machine.export_state() == before_preview, "restore preview leaves guest files and measurements intact")
		_assert(game.clock_minutes() == before_clock and game.state.work == before_work, "restore preview does not charge work")
		var customers_before: String = game.vm_read("/srv/data/customers.csv")
		var orders_before: String = game.vm_read("/srv/data/orders.csv")
		_assert(game.vm_run(recovery_command).begins_with("restored"), "selected snapshot ledger restored into production")
		_assert(game.vm_read("/srv/data/ledger.txt") == staged_before, "selective production restore recovers exact healthy bytes")
		_assert(game.vm_read("/srv/data/customers.csv") == customers_before and game.vm_read("/srv/data/orders.csv") == orders_before, "selective restore preserves other business files")
		_assert(game.clock_minutes() - before_clock == 15, "actual selective restore consumes restoration work time")
	for index in [edr_index, backup_index, firewall_index]:
		if _ssh(index): _measure_current("linked recovery %d" % index)
	_assert(game.can_deliver(), "linked delivery restored after provider remeasurement")
	_assert(game.save_game() and game.load_game(), "linked provider survives save reload")
	for index in [edr_index, backup_index, firewall_index]:
		if _ssh(index): _measure_current("linked reload %d" % index)
	_assert(game.can_deliver(), "linked delivery remains valid after reload")
	var maintenance_targets: Array = game._capture_maintenance_targets("business-workspace")
	_assert(maintenance_targets.size() == game.state.targets.size(), "maintenance captures every linked target")
	var maintenance_result: Dictionary = game._run_maintenance_job({"targets":maintenance_targets})
	_assert(bool(maintenance_result.get("passed", false)), "maintenance rechecks retained linked files")
	_assert(str(maintenance_result.get("log", "")).contains("/api/business/ledger"), "maintenance log includes linked ledger request")
	var broken_maintenance_targets: Array = maintenance_targets.duplicate(true)
	for maintenance_target in broken_maintenance_targets:
		if int(maintenance_target.get("chapter", -1)) != 1: continue
		var broken_state: Dictionary = maintenance_target.get("vm_state", {})
		var broken_fs: Dictionary = broken_state.get("fs", {})
		broken_fs["/srv/data/ledger.txt"] = "malformed ledger\n"
		broken_state.fs = broken_fs; maintenance_target.vm_state = broken_state
	var broken_maintenance: Dictionary = game._run_maintenance_job({"targets":broken_maintenance_targets})
	_assert(not bool(broken_maintenance.get("passed", false)), "maintenance rejects malformed retained ledger")
	_assert(str(broken_maintenance.get("log", "")).contains("422"), "maintenance records malformed ledger response")
	_assert(game.can_deliver(), "linked composite is deliverable after live measurements")
	_assert(game.deliver(), "linked composite delivered")

	# A standalone v2 gateway reads its own production files, without a linked
	# backup provider. Accounting does not depend on the customer CSV.
	var standalone = load("res://scripts/virtual_machine.gd").new()
	var standalone_state: Dictionary = game.state.vm_states.get(game._vm_key(firewall_index), {}).duplicate(true)
	var standalone_scenario: Dictionary = load("res://scripts/case_catalog.gd").by_id("service-2-case-2")
	standalone_state.scenario = standalone_scenario.duplicate(true)
	standalone_state.scenario.erase("linked_business")
	standalone.setup(2, standalone_state, standalone_scenario)
	_assert(standalone.run("ssh client").contains("Authenticated"), "standalone firewall connected")
	_assert(not standalone.has_linked_business() and int(standalone.state.get("firewall_model_version", 1)) == 2, "standalone v2 fixture")
	standalone.state.fs.erase("/srv/data/ledger.txt")
	var standalone_missing: String = standalone.run("curl https://intranet.client.test/api/business/ledger")
	_assert(standalone_missing.begins_with("HTTP/1.1 404") and standalone_missing.contains("missing_file"), "standalone ledger is truly absent")
	standalone.state.fs["/srv/data/ledger.txt"] = staged_before
	standalone.state.fs.erase("/srv/data/customers.csv")
	var standalone_ledger: String = standalone.run("curl https://intranet.client.test/api/business/ledger")
	_assert(standalone_ledger.begins_with("HTTP/1.1 200") and standalone_ledger.contains(staged_before.sha256_text()), "standalone ledger uses actual bytes without customer CSV")
	var deny_config: String = standalone.configuration_text({"dns":"on","business":"deny","admin_public":"deny","tls":"on"})
	_assert(standalone.write_file(str(standalone.state.config_path), deny_config), "standalone deny config written")
	_assert(standalone.run("systemctl restart firewall").contains("active"), "standalone deny config applied")
	var standalone_denied: String = standalone.run("curl https://intranet.client.test/api/business/ledger")
	_assert(standalone_denied.contains("FIREWALL_DENIED"), "business API follows firewall policy")

	# A pre-link accepted save remains an ordinary composite contract and does
	# not acquire the new linked-business route or probe on load.
	var legacy: Dictionary = JSON.parse_string(accepted_raw)
	if legacy.get("contract", {}) is Dictionary: legacy.contract.erase("linked_business_version")
	for target in legacy.get("targets", []):
		if target is Dictionary: target.erase("scenario")
	for context in legacy.get("contract_contexts", {}).values():
		if context is Dictionary:
			if context.get("contract", {}) is Dictionary: context.contract.erase("linked_business_version")
			for target in context.get("targets", []):
				if target is Dictionary: target.erase("scenario")
	for index in legacy.get("targets", []).size():
		var key := str(legacy.get("current_contract_id", "")) + "/site-" + str(index)
		if legacy.get("vm_states", {}).has(key): legacy.vm_states[key].scenario = load("res://scripts/case_catalog.gd").by_id(str(legacy.targets[index].get("case_id", "")))
	var legacy_path := "user://qa-business-workspace-legacy-" + qa_id + ".json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy)); legacy_file.close()
	var old_game = load("res://scripts/game.gd").new(); root.add_child(old_game); await process_frame
	old_game.save_path = legacy_path; old_game.backup_path = legacy_path + ".bak"; old_game.previous_path = legacy_path + ".previous"; old_game.settings_path = legacy_path + ".settings"
	_assert(old_game.load_game() and bool(old_game.state.accepted), "old accepted composite loads")
	var old_firewall_index := -1
	for old_index in old_game.state.targets.size():
		if int(old_game.state.targets[old_index].get("chapter", -1)) == 2: old_firewall_index = old_index
	_assert(old_firewall_index >= 0 and old_game.select_target(old_firewall_index), "old accepted firewall target selectable")
	_assert(not old_game._vm().has_linked_business(), "old accepted firewall target remains unlinked")
	_assert(not old_game.diagnostic_probes().any(func(probe): return str(probe.get("id", "")) == "linked-business-ledger"), "old accepted save has no linked business probe")
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("BUSINESS_WORKSPACE_TEST_PASS")
	else:
		for failure in failures: push_error(failure)
		print("BUSINESS_WORKSPACE_TEST_FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
