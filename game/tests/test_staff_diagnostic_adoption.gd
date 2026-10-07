extends SceneTree

const Game = preload("res://scripts/game.gd")
const VM = preload("res://scripts/virtual_machine.gd")

var failures: Array[String] = []
var assertions := 0

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func _init() -> void:
	call_deferred("run")

func _new_game(tag: String) -> Game:
	var game := Game.new()
	root.add_child(game)
	var qa := "user://qa-staff-diagnostic-%s-%d" % [tag, OS.get_process_id()]
	game.save_path = qa + ".json"
	game.backup_path = qa + ".json.bak"
	game.previous_path = qa + ".previous.json"
	game.settings_path = qa + "-settings.json"
	game.new_game()
	game.choose_strategy("operations")
	game.state.credit = 999999
	game.state.chapter = 0
	game.state.completed_ids = []
	game.state.contract = {"case_id":"share"}
	game.state.current_contract_id = ""
	check(game.accept_mission(), "accept isolated share engagement " + tag)
	game.vm_run("ssh client")
	var machine = game._vm()
	var observations: Array = [
		{"id":"staff-pass","command":"sha256sum /srv/data/orders.csv","expectation":str(VM.RECORDS["orders.csv"]).sha256_text(),"initial_result":"keep first result"},
		{"id":"staff-fail","command":"smbclient //client/share -U staff -c ls","expectation":"a result that cannot match"}
	]
	machine.state.scenario.probes = observations
	return game

func _complete_aya(game: Game) -> void:
	game.assign_colleague("aya")
	if game._assignments.has("aya"):
		game._finish_colleague("aya", game._assignments["aya"])

func _find(rows: Array, probe_id: String, member_id: String = "aya") -> Dictionary:
	for row in rows:
		if str(row.get("probe_id", "")) == probe_id and str(row.get("member_id", "")) == member_id:
			return row
	return {}

func _cleanup(game: Game) -> void:
	for path in [game.save_path, game.backup_path, game.previous_path, game.settings_path, game.save_path + ".tmp"]:
		var absolute := ProjectSettings.globalize_path(str(path))
		if FileAccess.file_exists(str(path)): DirAccess.remove_absolute(absolute)
	game.queue_free()

func run() -> void:
	var game := _new_game("success")
	var before_observations: int = game._vm().state.get("observations", []).size()
	var before_probes := game.diagnostic_probes()
	check(before_probes.all(func(row): return not bool(row.get("recorded", false))), "no player measurement exists before colleague work")
	_complete_aya(game)
	var receipts: Array = game.state.targets[0].get("work_receipts", [])
	check(not receipts.is_empty(), "completed investigation creates a target receipt")
	var receipt: Dictionary = receipts.back() if not receipts.is_empty() else {}
	var stored: Array = receipt.get("diagnostic_observations_v1", [])
	check(stored.size() == 2, "receipt keeps structured read-only outputs")
	check(game._vm().state.get("observations", []).size() == before_observations, "cooperation does not create ordinary probe measurements")
	check(game.diagnostic_probes().all(func(row): return not bool(row.get("recorded", false))), "cooperation alone does not record a probe result")
	var rows: Array = game.staff_diagnostic_observations()
	var passing := _find(rows, "staff-pass")
	var failing := _find(rows, "staff-fail")
	check(passing.get("fresh", false) and passing.get("passed", false) and passing.get("can_adopt", false), "fresh passing output is adoptable")
	check(failing.get("recorded", false) and failing.get("fresh", false) and not failing.get("passed", true) and failing.get("can_adopt", false), "fresh failing output remains adoptable as a real failure")
	check(not passing.get("fingerprint_kind", "").is_empty(), "local SHA observation keeps its scoped dependency marker")
	var state_before_adopt := JSON.stringify(game.state)
	var clock_before := game.business_clock()
	var cash_before := int(game.state.cash)
	var machine_before := JSON.stringify(game._vm().export_state())
	var saved_path := game.save_path
	game.save_path = "user://qa-staff-diagnostic-missing-%d/save.json" % OS.get_process_id()
	var failed_save := game.adopt_staff_diagnostic("staff-pass", "aya")
	check(not failed_save.ok and JSON.stringify(game.state) == state_before_adopt and JSON.stringify(game._vm().export_state()) == machine_before, "save failure rolls back adopted probe and company state")
	game.save_path = saved_path
	var adopted_pass := game.adopt_staff_diagnostic("staff-pass", "aya")
	check(adopted_pass.ok, "retry adopts the saved real observation")
	var pass_probe := game.diagnostic_probes().filter(func(row): return str(row.get("id", "")) == "staff-pass")
	check(pass_probe.size() == 1 and pass_probe[0].recorded and pass_probe[0].fresh and pass_probe[0].passed, "adoption copies the passing result into normal probe evidence")
	check(str(pass_probe[0].get("initial_result", "")) == "keep first result", "adoption preserves an existing initial result")
	check(pass_probe[0].get("staff_observation_source", {}).get("member_id", "") == "aya", "adopted evidence retains colleague attribution")
	check(game.business_clock() == clock_before and int(game.state.cash) == cash_before, "adoption adds no work time or cost")
	var repeat_before := JSON.stringify(game._vm().export_state())
	var repeat := game.adopt_staff_diagnostic("staff-pass", "aya")
	check(repeat.ok and JSON.stringify(game._vm().export_state()) == repeat_before, "duplicate adoption is idempotent")
	var adopted_fail := game.adopt_staff_diagnostic("staff-fail", "aya")
	check(adopted_fail.ok, "failing real response can be adopted")
	var fail_probe := game.diagnostic_probes().filter(func(row): return str(row.get("id", "")) == "staff-fail")
	check(fail_probe.size() == 1 and fail_probe[0].recorded and fail_probe[0].fresh and not fail_probe[0].passed, "adopted failure stays a failure")
	check(game.save_game() and game.load_game(), "adopted result survives save and reload")
	var loaded_pass := game.diagnostic_probes().filter(func(row): return str(row.get("id", "")) == "staff-pass")
	check(loaded_pass.size() == 1 and loaded_pass[0].fresh and loaded_pass[0].passed and loaded_pass[0].staff_observation_source.member_id == "aya", "reload restores proof and source attribution")
	var loaded_rows: Array = game.staff_diagnostic_observations()
	check(_find(loaded_rows, "staff-pass").adopted, "read projection marks the adopted source")
	game.run_diagnostic("staff-pass")
	var remeasured: Array = game._vm()._active_probes().filter(func(row): return str(row.get("id", "")) == "staff-pass")
	check(remeasured.size() == 1 and not remeasured[0].has("staff_observation_source"), "player remeasurement removes old colleague attribution")
	# A legacy receipt keeps its report but cannot be reparsed into structured evidence.
	var target: Dictionary = game.state.targets[0]
	var legacy_receipts: Array = target.work_receipts.duplicate(true)
	for old_receipt in legacy_receipts: old_receipt.erase("diagnostic_observations_v1")
	target.work_receipts = legacy_receipts
	game.state.targets[0] = target
	check(game.save_game() and game.load_game(), "legacy receipt fixture reloads without migration failure")
	check(game.staff_diagnostic_observations().is_empty(), "legacy report text is not promoted into observations")
	var legacy_reject := game.adopt_staff_diagnostic("staff-pass", "aya")
	check(not legacy_reject.ok, "legacy report cannot be adopted")
	_cleanup(game)

	var stale_game := _new_game("stale")
	_complete_aya(stale_game)
	var stale_row := _find(stale_game.staff_diagnostic_observations(), "staff-pass")
	var config_path := str(stale_game.vm_info().get("config_path", ""))
	stale_game.vm_write(config_path, str(stale_game._vm().state.fs.get(config_path, "")) + "\n# changed after observation\n")
	var after_change := _find(stale_game.staff_diagnostic_observations(), "staff-pass")
	var service_after_change := _find(stale_game.staff_diagnostic_observations(), "staff-fail")
	check(not stale_row.is_empty() and after_change.get("fresh", false) and after_change.get("can_adopt", false), "local SHA proof ignores unrelated configuration changes")
	check(not service_after_change.get("fresh", true) and not service_after_change.get("can_adopt", true), "configuration change expires whole-VM colleague proof")
	check(not stale_game.adopt_staff_diagnostic("staff-fail", "aya").ok, "stale service observation is refused")
	stale_game.vm_write("/srv/data/orders.csv", "changed after observation\n")
	var file_after_change := _find(stale_game.staff_diagnostic_observations(), "staff-pass")
	check(not file_after_change.get("fresh", true) and not file_after_change.get("can_adopt", true), "changing the observed file expires its local SHA proof")
	check(not stale_game.adopt_staff_diagnostic("staff-pass", "aya").ok, "stale local SHA observation is refused")
	_cleanup(stale_game)

	print("STAFF_DIAGNOSTIC_ADOPTION assertions=", assertions, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
