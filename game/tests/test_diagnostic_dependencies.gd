extends SceneTree
## VM fixtures test evidence dependencies; the native journey owns real play.
const VM = preload("res://scripts/virtual_machine.gd")
var assertions := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ", label)

func row(vm, id: String) -> Dictionary:
	for probe in vm.probes():
		if str(probe.id) == id: return probe
	return {}

func source(vm, id: String) -> Dictionary:
	for probe in vm._active_probes():
		if str(probe.id) == id: return probe
	return {}

func fixture():
	var vm = VM.new()
	vm.setup(0, {}, {"probes":[
		{"id":"orders", "command":"sha256sum /srv/data/orders.csv", "expectation":VM.RECORDS["orders.csv"].sha256_text()},
		{"id":"customers", "command":"sha256sum /srv/data/customers.csv", "expectation":VM.RECORDS["customers.csv"].sha256_text()},
		{"id":"access", "command":"smbclient //client/share -U staff -c ls", "expectation":"report.txt"}]})
	vm.run("ssh client")
	return vm

func _init() -> void: call_deferred("run")

func run() -> void:
	var vm = fixture()
	check(not row(vm,"orders").recorded, "opening unmeasured file grants no result")
	for id in ["orders", "customers", "access"]: vm.execute_probe(id)
	var measured := row(vm,"orders"); var original := str(vm.state.fs["/srv/data/orders.csv"])
	check(measured.fresh and measured.passed and measured.fingerprint_kind == "local-file-v1", "real local SHA creates a scoped proof")
	check(row(vm,"access").fresh and not row(vm,"access").has("fingerprint_kind"), "SMB keeps its service proof")
	vm.write_file(vm.state.config_path, str(vm.state.fs[vm.state.config_path]) + "\n# draft\n")
	check(row(vm,"orders").fresh and row(vm,"orders").fingerprint == measured.fingerprint, "configuration draft does not invalidate an unchanged original")
	vm.run("cd /srv/share")
	check(row(vm,"orders").fresh, "absolute file proof is independent of working directory")
	check(not row(vm,"access").fresh, "configuration still expires actual service access evidence")
	vm.run("systemctl restart smbd")
	check(row(vm,"orders").fresh, "service apply does not expire local byte comparison")
	vm.write_file("/srv/data/customers.csv", str(vm.state.fs["/srv/data/customers.csv"]) + "103,New\n")
	check(row(vm,"orders").fresh and not row(vm,"customers").fresh, "another file expires only its own local comparison")
	vm.write_file("/srv/data/orders.csv", original)
	check(row(vm,"orders").fresh, "byte-identical save keeps measured content proof")
	vm.write_file("/srv/data/orders.csv", original.replace("12800","12900"))
	check(not row(vm,"orders").fresh and row(vm,"orders").result == measured.result, "actual content change expires proof without inventing another result")
	vm.execute_probe("orders")
	check(row(vm,"orders").fresh and not row(vm,"orders").passed, "actual remeasure records changed original failure")
	vm.write_file("/srv/data/orders.csv", original)
	check(not row(vm,"orders").fresh, "restore expires the measured wrong bytes")
	vm.execute_probe("orders")
	check(row(vm,"orders").fresh and row(vm,"orders").passed, "explicit retry after restore succeeds")
	vm.run("rm /srv/data/orders.csv")
	check(not row(vm,"orders").fresh, "deletion expires a present-file proof")
	vm.execute_probe("orders")
	check(row(vm,"orders").fresh and not row(vm,"orders").passed and row(vm,"orders").result == "sha256sum: file missing", "actual missing-file failure has its own presence dependency")
	vm.write_file(vm.state.config_path, str(vm.state.fs[vm.state.config_path]) + "\n# another draft\n")
	check(row(vm,"orders").fresh and not row(vm,"orders").passed, "unrelated draft preserves measured absence rather than granting success")
	vm.write_file("/srv/data/orders.csv", original)
	check(not row(vm,"orders").fresh, "recreation expires absence evidence")
	vm.execute_probe("orders")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(vm.export_state()))
	var resumed = VM.new(); resumed.setup(0, saved)
	check(row(resumed,"orders").fresh and row(resumed,"orders").fingerprint == row(vm,"orders").fingerprint, "JSON resume retains exact file proof")
	var before: Dictionary = resumed.export_state()
	resumed.probes(); resumed.probes()
	check(resumed.export_state() == before, "querying freshness never mutates observations or measurements")
	var proof := source(resumed,"orders")
	proof.expectation = "b".repeat(64)
	check(not row(resumed,"orders").fresh, "changed acceptance condition expires proof")
	proof.expectation = measured.expectation; proof.command = "sha256sum /srv/data/customers.csv"
	check(not row(resumed,"orders").fresh, "changed command target expires proof")
	proof.command = measured.command; resumed.state.host = "other.client.test"
	check(not row(resumed,"orders").fresh, "another host cannot inherit local evidence")
	resumed.state.host = vm.state.host; proof.fingerprint_kind = "unknown-kind"
	check(not row(resumed,"orders").fresh, "unknown dependency marker fails closed")
	proof.fingerprint_kind = "local-file-v1"; proof.fingerprint = ""
	check(not row(resumed,"orders").fresh, "incomplete marker has no valid evidence")
	proof.command = "sha256sum"; proof.fingerprint = ""
	check(not row(resumed,"orders").fresh, "malformed arity cannot pass with empty stamps")
	var relative = fixture(); var relative_probe := source(relative,"orders")
	relative_probe.command = "sha256sum orders.csv"; relative.run("cd /srv/data"); relative.execute_probe("orders")
	check(row(relative,"orders").fresh and row(relative,"orders").passed, "relative target is bound to actual resolved file")
	relative.run("cd /srv/share")
	check(not row(relative,"orders").fresh, "relative working directory changes the target")
	var alias = fixture(); var alias_probe := source(alias,"orders")
	alias.write_file(VM.OPERATOR_HOME + "/proof.csv", original)
	alias_probe.command = "sha256sum " + str(VM.LEGACY_HOMES[0]) + "/proof.csv"; alias.execute_probe("orders")
	check(row(alias,"orders").fresh and row(alias,"orders").passed, "legacy-home alias binds to VM-resolved operator file")
	# Synthetic shadow-file fixture, then query without measuring its bytes.
	alias.state.fs[str(VM.LEGACY_HOMES[0]) + "/proof.csv"] = original
	check(not row(alias,"orders").fresh, "another actual legacy-home file cannot inherit alias evidence even with same bytes")
	var empty_file = fixture(); empty_file.write_file("/srv/data/orders.csv", ""); source(empty_file,"orders").expectation = "".sha256_text(); empty_file.execute_probe("orders")
	check(row(empty_file,"orders").fresh and row(empty_file,"orders").passed, "empty existing file has a valid byte proof")
	empty_file.run("rm /srv/data/orders.csv")
	check(not row(empty_file,"orders").fresh, "empty file and absent file are different dependencies")
	var backup = VM.new(); backup.setup(1, {}, {"probes":[{"id":"restore-proof", "command":"sha256sum /restore/srv/data/orders.csv", "expectation":original.sha256_text()}]}); backup.run("ssh client")
	source(backup,"restore-proof").command = "sha256sum /restore/orders.csv"; backup.write_file("/restore/orders.csv", original); backup.execute_probe("restore-proof")
	check(row(backup,"restore-proof").fresh, "old backup target has an actual measured proof before migration")
	backup._normalize_backup_probes()
	check(not row(backup,"restore-proof").recorded and not row(backup,"restore-proof").has("fingerprint_kind"), "backup target migration clears marker and prior acceptance")
	var legacy = fixture(); legacy.execute_probe("orders")
	source(legacy,"orders").erase("fingerprint_kind"); source(legacy,"orders").fingerprint = legacy._fingerprint()
	var legacy_saved := legacy.export_state(); var old = VM.new(); old.setup(0, legacy_saved)
	check(row(old,"orders").fresh and not row(old,"orders").has("fingerprint_kind"), "unmarked legacy result retains existing freshness")
	old.write_file(old.state.config_path, str(old.state.fs[old.state.config_path]) + "\n# legacy change\n")
	var old_before := old.export_state(); old.probes()
	check(not row(old,"orders").fresh and old.export_state() == old_before and not row(old,"orders").has("fingerprint_kind"), "legacy stale result is never promoted by display")
	old.execute_probe("orders")
	check(row(old,"orders").fresh and row(old,"orders").fingerprint_kind == "local-file-v1", "only actual legacy remeasure captures scoped proof")
	old.run("reset-lab --confirm")
	check(not row(old,"orders").recorded and not row(old,"orders").has("fingerprint_kind"), "reset clears measured dependency metadata")
	var disconnected = fixture(); disconnected.run("exit"); disconnected.execute_probe("orders")
	check(not row(disconnected,"orders").has("fingerprint_kind") and not row(disconnected,"orders").passed, "not-connected response cannot become a local file proof")
	await transaction()
	print("DIAGNOSTIC_DEPENDENCIES assertions=", assertions, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func transaction() -> void:
	var game = root.get_node("Game"); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"), "isolated save transaction")
	if not game.save_path.begins_with("user://qa-"): return
	check(game.new_game() and game.choose_strategy("operations") and game.accept_mission(), "ordinary company accepts first job for transaction fixture")
	game.vm_run("ssh client")
	game._vm()._active_probes().append({"id":"qa-local", "command":"sha256sum /srv/data/orders.csv", "expectation":VM.RECORDS["orders.csv"].sha256_text()})
	var before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock(); var path: String = game.save_path
	game.save_path = "user://missing-dependency-%d/save.json" % OS.get_process_id()
	var output: String = game.run_diagnostic("qa-local"); game.save_path = path
	check(output.contains("測定結果を保存できませんでした") and game._vm().export_state() == before and int(game.state.cash) == cash and game.business_clock() == clock, "failed save rolls back new marker, evidence, work and funds")
	game.run_diagnostic("qa-local")
	var measured := row(game._vm(),"qa-local")
	check(measured.fresh and measured.passed and measured.fingerprint_kind == "local-file-v1", "retry commits actual file proof")
	check(game.save_game() and game.load_game() and row(game._vm(),"qa-local").fingerprint == measured.fingerprint and row(game._vm(),"qa-local").fresh, "save/load preserves committed proof")
