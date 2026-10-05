extends SceneTree

## Engine-only monitor projection tests. The accepted story case below is a
## synthetic test fixture; it injects no cash, skill, result, or clock values.
const GameScript = preload("res://scripts/game.gd")
const VmScript = preload("res://scripts/virtual_machine.gd")
var game
var failures: Array[String] = []
var assertions := 0
var path_root := ""

func _init() -> void:
	path_root = "user://qa-service-monitor-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path_root))
	game = GameScript.new()
	root.add_child(game)
	_set_paths(game)
	check(game.new_game(), "create isolated empty player save")
	_install_synthetic_firewall_case(game)
	var untouched_state: Dictionary = game.state.duplicate(true)
	var untouched_clock: String = game.business_clock()
	var untouched_work: Dictionary = game.work_status()
	var empty: Dictionary = game.service_monitor_snapshot()
	check(not bool(empty.initialized) and not bool(empty.connected) and empty.active == null and empty.probes.is_empty(), "unsaved VM projects uninitialized, disconnected, unknown-active and no probes")
	check(str(empty.host) == VmScript.HOSTS[2] and str(empty.service) == VmScript.SERVICES[2] and str(empty.config_path) == VmScript.PATHS[2], "uninitialized projection uses current chapter constants")
	check(game._machine == null and game._machine_key.is_empty() and game.state == untouched_state and game.business_clock() == untouched_clock and game.work_status() == untouched_work, "empty projection leaves game, VM, work and clock untouched")

	var ssh_output: String = game.vm_run("ssh client")
	check(ssh_output.contains("Authenticated"), "synthetic fixture connects to actual local VM through public command")
	var live_machine = game._machine
	var live_key: String = game._machine_key
	var state_before_projection: Dictionary = game.state.duplicate(true)
	var vm_before_projection: Dictionary = live_machine.export_state()
	var clock_before_projection: String = game.business_clock()
	var work_before_projection: Dictionary = game.work_status()
	var cash_before_projection := int(game.state.cash)
	var live_snapshot: Dictionary = game.service_monitor_snapshot()
	check(bool(live_snapshot.initialized) and bool(live_snapshot.connected) and live_snapshot.active == true and bool(live_snapshot.freshness_known), "matching live VM projects real active and connection state")
	check(not live_snapshot.probes.is_empty() and live_snapshot.probes.all(func(probe): return not bool(probe.get("recorded", false))), "live probes are shown unmeasured before diagnostics")
	check(live_snapshot.guest_state is Dictionary and live_snapshot.applied is Dictionary and live_snapshot.models.firewall_model_version == 2, "snapshot includes independent guest-state, applied configuration and model metadata")
	check(game.state == state_before_projection and live_machine.export_state() == vm_before_projection and game._machine == live_machine and game._machine_key == live_key and game.business_clock() == clock_before_projection and game.work_status() == work_before_projection and int(game.state.cash) == cash_before_projection, "live projection does not alter state, VM identity, key, work, clock or cash")
	var original_probe_result := str(live_snapshot.probes[0].get("result", ""))
	live_snapshot.probes[0].result = "caller mutation"
	live_snapshot.events.append("caller mutation")
	live_snapshot.observations.append({"output":"caller mutation"})
	live_snapshot.guest_state.fs["/etc/smb.conf"] = "caller mutation"
	var detached: Dictionary = game.service_monitor_snapshot()
	check(str(detached.probes[0].get("result", "")) == original_probe_result and not detached.events.has("caller mutation") and detached.observations.all(func(row): return str(row.get("output", "")) != "caller mutation") and not str(detached.guest_state.fs.get("/etc/smb.conf", "")).contains("caller mutation"), "returned probes, histories and guest state do not alias live VM")
	var help_output: String = game.vm_run("help")
	check(not help_output.is_empty(), "help command produces an actual unmatched guest observation")
	var old_observation: Dictionary = game._machine.state.observations.back().duplicate(true)
	check(not old_observation.has("probe_id") and not old_observation.has("probe_passed") and not old_observation.has("probe_expectation"), "unmatched observation receives no diagnostic annotation")

	var failed_output: String = game.run_diagnostic("dns-check")
	var failed_snapshot: Dictionary = game.service_monitor_snapshot()
	var failed_probe := _probe(failed_snapshot, "dns-check")
	var failed_observation: Dictionary = failed_snapshot.observations.back()
	check(failed_output.contains("SERVFAIL") and bool(failed_probe.get("recorded", false)) and bool(failed_probe.get("fresh", false)) and not bool(failed_probe.get("passed", true)), "actual DNS diagnostic records its failed expectation and fresh fingerprint")
	check(str(failed_observation.get("probe_id", "")) == "dns-check" and failed_observation.get("probe_passed", null) is bool and not bool(failed_observation.probe_passed) and str(failed_observation.probe_expectation) == str(failed_probe.expectation), "new observation stores the probe id, actual-time result and then-current expectation")
	var pre_apply: Dictionary = game.firewall_action("services", {"dns":"on"})
	var pending_snapshot: Dictionary = game.service_monitor_snapshot()
	var pending_probe := _probe(pending_snapshot, "dns-check")
	check(bool(pre_apply.get("ok", false)) and bool(pending_snapshot.dirty) and str(pending_snapshot.pending.get("dns", "")) == "on" and str(pending_snapshot.applied.get("dns", "")) == "off", "pending service config remains distinct from applied state")
	check(bool(pending_probe.get("recorded", false)) and not bool(pending_probe.get("fresh", true)) and str(pending_probe.get("freshness", "")) == "stale", "saved failed sample becomes stale after a real pending config edit")
	var observations_before_apply: Array = pending_snapshot.observations.duplicate(true)
	var apply_result: Dictionary = game.firewall_action("apply")
	var applied_snapshot: Dictionary = game.service_monitor_snapshot()
	check(bool(apply_result.get("ok", false)) and str(applied_snapshot.applied.get("dns", "")) == "on" and not bool(applied_snapshot.dirty), "explicit firewall apply updates actual applied service configuration")
	var pass_output: String = game.run_diagnostic("dns-check")
	var pass_snapshot: Dictionary = game.service_monitor_snapshot()
	var pass_probe := _probe(pass_snapshot, "dns-check")
	var pass_observation: Dictionary = pass_snapshot.observations.back()
	check(pass_output.contains("NOERROR") and bool(pass_probe.get("fresh", false)) and bool(pass_probe.get("passed", false)), "second actual DNS diagnostic records a fresh pass")
	check(bool(pass_observation.get("probe_passed", false)) and str(pass_observation.get("probe_expectation", "")) == str(pass_probe.expectation), "pass metadata records the observed expectation at measurement time")
	var historical_failure: Dictionary = {}
	for row in observations_before_apply:
		if str(row.get("probe_id", "")) == "dns-check": historical_failure = row; break
	check(str(historical_failure.get("probe_expectation", "")) == str(failed_observation.get("probe_expectation", "")) and historical_failure.get("probe_passed", null) is bool and not bool(historical_failure.get("probe_passed", true)), "historical failed observation is not rescored after repair")

	check(game.save_game(), "persist real pending/applied VM, probe and observation state")
	var resumed = GameScript.new()
	root.add_child(resumed); _set_paths(resumed)
	check(resumed.load_game(), "load persisted monitor fixture in a new Game")
	game = resumed
	check(game._machine == null and game._machine_key.is_empty(), "new Game starts from saved-only VM projection")
	var resumed_state_before: Dictionary = game.state.duplicate(true)
	var saved_only_snapshot: Dictionary = game.service_monitor_snapshot()
	var saved_only_failed := _probe(saved_only_snapshot, "dns-check")
	var stored_failure: Dictionary = _observation(saved_only_snapshot, "dns-check", false)
	var stored_pass: Dictionary = _observation(saved_only_snapshot, "dns-check", true)
	check(bool(saved_only_snapshot.initialized) and bool(saved_only_snapshot.connected) and bool(saved_only_snapshot.freshness_known), "saved VM preview is initialized without installing it as the live Game VM")
	check(bool(saved_only_failed.get("passed", false)) and stored_failure.get("probe_passed", null) is bool and not bool(stored_failure.probe_passed) and bool(stored_pass.get("probe_passed", false)), "save/load retains current pass and separate historical failed/pass records")
	check(not stored_failure.has("timestamp") and not stored_pass.has("timestamp") and str(stored_failure.get("probe_expectation", "")) == str(failed_observation.probe_expectation), "history preserves real measurement order without inventing timestamps or rewriting expectations")
	var legacy_retained: bool = saved_only_snapshot.observations.any(func(row): return not row.has("probe_id") and str(row.get("command", "")) == str(old_observation.get("command", "")))
	check(legacy_retained and game.state == resumed_state_before and game._machine == null and game._machine_key.is_empty(), "saved-only projection migrates only its copy and retains legacy unmatched observation")
	check(game.vm_run("ssh client").contains("Authenticated"), "resume saved-only VM into a live instance before rollback test")
	var saved_snapshot_state: Dictionary = game.state.duplicate(true)
	var failed_save_vm = game._machine
	var failed_save_vm_key: String = game._machine_key
	var failed_save_vm_state: Dictionary = failed_save_vm.export_state()
	var failed_save_assignments: Dictionary = game._assignments.duplicate(true)
	var failed_save_clock: String = game.business_clock()
	var failed_save_work: Dictionary = game.work_status()
	var failed_save_cash := int(game.state.cash)
	var original_path: String = game.save_path; var original_backup: String = game.backup_path; var original_previous: String = game.previous_path
	game.save_path = path_root + "/missing-parent/save.json"; game.backup_path = game.save_path + ".bak"; game.previous_path = game.save_path + ".previous"
	var rejected_measurement: String = game.run_diagnostic("dns-check")
	game.save_path = original_path; game.backup_path = original_backup; game.previous_path = original_previous
	check(rejected_measurement.contains("保存できませんでした"), "diagnostic save failure reports a Japanese rollback message")
	check(game.state == saved_snapshot_state and game._machine == failed_save_vm and game._machine_key == failed_save_vm_key and game._machine.export_state() == failed_save_vm_state, "save failure restores Game state and the exact live guest before no phantom observation")
	check(game._assignments == failed_save_assignments and game.business_clock() == failed_save_clock and game.work_status() == failed_save_work and int(game.state.cash) == failed_save_cash, "failed diagnostic save rolls back assignments, work, clock and cash")
	var after_rejected_snapshot: Dictionary = game.service_monitor_snapshot()
	var restored_previous_pass := _probe(after_rejected_snapshot, "dns-check")
	check(bool(restored_previous_pass.get("recorded", false)) and bool(restored_previous_pass.get("fresh", false)) and bool(restored_previous_pass.get("passed", false)), "failed remeasurement preserves the prior durable pass without claiming the failed attempt passed")
	check(not after_rejected_snapshot.observations.any(func(row): return str(row.get("probe_id", "")) == "dns-check" and str(row.get("output", "")) == rejected_measurement), "failed-save diagnostic is absent from persisted/projected observation history")

	_test_unreferenced_provider_unknown()
	var invalid = GameScript.new(); root.add_child(invalid); _set_paths(invalid)
	check(invalid.new_game(), "create malformed-snapshot fixture")
	_install_synthetic_firewall_case(invalid)
	invalid.state.vm_states[invalid._vm_key()] = {"schema":2,"fs":{},"applied":{},"events":[]}
	var malformed_before: Dictionary = invalid.state.duplicate(true)
	var malformed: Dictionary = invalid.service_monitor_snapshot()
	check(not bool(malformed.initialized) and malformed.probes.is_empty() and invalid.state == malformed_before and invalid._machine == null, "incomplete saved guest stays unknown instead of synthesizing a fresh customer VM")
	invalid.queue_free()
	_test_linked_portal_files()
	for failure in failures: push_error(failure)
	print("SERVICE_MONITOR_SNAPSHOT_PASS assertions=" + str(assertions) if failures.is_empty() else "SERVICE_MONITOR_SNAPSHOT_FAIL count=" + str(failures.size()) + " assertions=" + str(assertions))
	quit(0 if failures.is_empty() else 1)

func _test_unreferenced_provider_unknown() -> void:
	var linked = GameScript.new(); root.add_child(linked); _set_paths(linked)
	check(linked.new_game(), "create second isolated provider fixture")
	_install_synthetic_firewall_case(linked, true)
	check(not linked.vm_run("ssh client").is_empty() and str(linked.run_diagnostic("dns-check")).contains("SERVFAIL"), "linked fixture records an actual local probe before provider snapshot is absent")
	check(linked.save_game(), "persist linked probe observation without provider target")
	var reloaded = GameScript.new(); root.add_child(reloaded); _set_paths(reloaded)
	check(reloaded.load_game(), "reload saved-only linked provider fixture")
	var snapshot: Dictionary = reloaded.service_monitor_snapshot()
	var probe := _probe(snapshot, "dns-check")
	check(not bool(snapshot.freshness_known) and not bool(probe.get("freshness_known", true)) and str(probe.get("freshness", "")) == "unknown" and not bool(probe.get("passed", true)), "saved-only linked-provider fingerprint is unknown when provider data is not persisted or referenced")
	check(reloaded._machine == null and reloaded._machine_key.is_empty(), "unknown linked-provider snapshot does not materialize Game VM")
	linked.queue_free(); reloaded.queue_free()

func _test_linked_portal_files() -> void:
	var linked = GameScript.new(); root.add_child(linked); _set_paths(linked)
	check(linked.new_game(), "create isolated linked portal file fixture")
	var scenario: Dictionary = GameScript.CASES.by_id("service-5-case-0").duplicate(true)
	scenario.linked_branch_storage = true
	linked.state.chapter = 5; linked.state.accepted = true; linked.state.career_mode = true
	linked.state.current_contract_id = "synthetic-linked-monitor"
	linked.state.contract = {"case_id":"composite-branch-reopen","client":"Synthetic linked monitor fixture"}
	linked.state.targets = [{"chapter":0,"case_id":"service-0-case-0","scenario":GameScript.CASES.by_id("service-0-case-0").duplicate(true)}, {"chapter":5,"case_id":"service-5-case-0","scenario":scenario}]
	linked.state.target_index = 1; linked.state.completed_ids = []; linked.state.vm_states = {}
	var source = VmScript.new(); source.setup(0, {}, GameScript.CASES.by_id("service-0-case-0"))
	var real_content := "source-only,123\n"
	source.state.fs["/srv/share/partner-order.csv"] = real_content
	linked.state.vm_states[linked._vm_key(0)] = source.export_state()
	var portal = VmScript.new(); portal.setup(5, {}, scenario)
	portal.state.connected = true
	linked.state.vm_states[linked._vm_key(1)] = portal.export_state()
	var before: Dictionary = linked.state.duplicate(true)
	var projection: Dictionary = linked.service_monitor_snapshot()
	check(projection.portal_files.size() == 1 and int(projection.portal_files[0].size) == real_content.to_utf8_buffer().size() and str(projection.portal_files[0].sha256) == real_content.sha256_text(), "portal configuration projects actual linked storage bytes rather than local guest copy")
	check(linked.state == before and linked._machine == null, "linked file projection does not modify either saved service or initialize Game VM")
	linked.queue_free()

func _install_synthetic_firewall_case(target, linked := false) -> void:
	var scenario: Dictionary = GameScript.CASES.by_id("service-2-case-0").duplicate(true)
	if linked: scenario.linked_business = true
	target.state.chapter = 2
	target.state.accepted = true
	target.state.career_mode = false
	target.state.current_contract_id = ""
	target.state.contract = {"case_id":"service-2-case-0","client":"Synthetic firewall monitor fixture","title":"Synthetic service monitor case"}
	target.state.targets = [{"chapter":2,"case_id":"service-2-case-0","scenario":scenario,"revision":0,"validated_revision":-1,"checks":[]}]
	target.state.target_index = 0
	target.state.completed_ids = []
	target.state.vm_states = {}
	target._machine = null; target._machine_key = ""

func _set_paths(target) -> void:
	target.save_path = path_root + "/player.json"
	target.backup_path = path_root + "/player.json.bak"
	target.previous_path = path_root + "/player.json.previous"
	target.settings_path = path_root + "/settings.json"

func _probe(snapshot: Dictionary, id: String) -> Dictionary:
	for probe in snapshot.get("probes", []):
		if str(probe.get("id", "")) == id: return probe
	return {}

func _observation(snapshot: Dictionary, id: String, passed: bool) -> Dictionary:
	for row in snapshot.get("observations", []):
		if str(row.get("probe_id", "")) == id and row.get("probe_passed", null) is bool and bool(row.probe_passed) == passed: return row
	return {}

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ", label)
