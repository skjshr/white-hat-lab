extends SceneTree

const VM = preload("res://scripts/virtual_machine.gd")
var failures: Array[String] = []
var vm: RefCounted

func _init() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("restic selection timeout"); quit(2))
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL ", label)

func _new_vm() -> RefCounted:
	var machine = VM.new()
	var probes := [{"id":"restore-ledger.txt","command":"sha256sum /restore/srv/data/ledger.txt","expectation":VM.RECORDS["ledger.txt"].sha256_text(),"recorded":false,"passed":false,"fresh":false,"result":""}]
	machine.setup(1, {}, {"initial":{"schedule":"daily","repository":"local"},"desired":{"schedule":"daily","repository":"local"},"seed_snapshot_repository":"local","probes":probes})
	machine.state.connected = true
	return machine

func _probe(id: String) -> Dictionary:
	var probes: Array = vm.state.get("scenario", {}).get("probes", []) if vm.state.get("scenario", {}) is Dictionary and not vm.state.get("scenario", {}).is_empty() else vm.state.get("probes", [])
	for item in probes:
		if str(item.get("id", "")) == id: return item
	return {}

func run() -> void:
	vm = _new_vm()
	var plan: Dictionary = vm.restic_restore_plan("local", "00000001:/srv/data", "/restore", ["/ledger.txt"])
	check(bool(plan.get("ok", false)) and plan.get("entries", []).size() == 1, "single-file restore plan")
	if bool(plan.get("ok", false)):
		var entry: Dictionary = plan.entries[0]
		check(str(entry.get("path", "")) == "/restore/ledger.txt" and str(entry.get("status", "")) == "new", "subfolder plan maps selected file")
	var scope_free: Dictionary = vm.restic_restore_plan("local", "00000001", "/restore-free", ["/srv/data/ledger.txt"])
	check(bool(scope_free.get("ok", false)) and str(scope_free.entries[0].path) == "/restore-free/srv/data/ledger.txt", "scope-free include preserves source path")
	check(vm.run("restic restore 00000001 --target /restore-free --include /srv/data/ledger.txt").begins_with("restored 1 files"), "scope-free selective restore auto-creates target")
	check(str(vm.state.fs.get("/restore-free/srv/data/ledger.txt", "")) == VM.RECORDS["ledger.txt"], "scope-free restored bytes")
	var before_plan: Dictionary = vm.export_state()
	var dry_raw: String = vm.run("restic restore 00000001:/srv/data --target /restore --include /ledger.txt --dry-run --verbose=2")
	check(dry_raw.contains("dry-run restore") and dry_raw.contains("restored"), "CLI dry-run reports readable status")
	check(JSON.stringify(vm.export_state()) == JSON.stringify(before_plan), "dry-run is immutable")
	check(vm.run("restic restore 00000001:/srv/data --target /restore --include /ledger.txt").begins_with("restored 1 files"), "CLI selective restore executes plan")
	check(str(vm.state.fs.get("/restore/ledger.txt", "")) == VM.RECORDS["ledger.txt"], "selected bytes restored")
	var before_path_probe: Dictionary = _probe("restore-ledger.txt")
	check(str(before_path_probe.get("command", "")) == "sha256sum /restore/ledger.txt", "restore probe maps initial target")
	vm.run(str(before_path_probe.get("command", "")))
	check(bool(before_path_probe.get("recorded", false)) and bool(before_path_probe.get("fresh", false)), "initial restore probe is measured")
	check(vm.run("restic restore 00000001:/srv/data --target /tmp/recovered --include /ledger.txt").begins_with("restored 1 files"), "alternate target restore executes")
	var alternate_probe: Dictionary = _probe("restore-ledger.txt")
	check(str(alternate_probe.get("command", "")) == "sha256sum /tmp/recovered/ledger.txt" and not bool(alternate_probe.get("fresh", false)), "target change clears stale probe")
	vm.run(str(alternate_probe.get("command", "")))
	var measured_fingerprint: String = str(alternate_probe.get("fingerprint", ""))
	check(bool(alternate_probe.get("passed", false)) and measured_fingerprint == vm._fingerprint(), "alternate target measurement matches current data")
	vm.state.fs["/tmp/recovered/ledger.txt"] = "tampered\n"
	check(measured_fingerprint != vm._fingerprint(), "editing arbitrary restore destination invalidates prior measurement")
	var tampered_output: String = vm.run(str(alternate_probe.get("command", "")))
	check(not bool(alternate_probe.get("passed", false)) and not tampered_output.is_empty(), "changed restored bytes fail measurement")
	vm.state.fs["/restore/ledger.txt"] = "changed\n"
	var never: Dictionary = vm.restic_restore_plan("local", "00000001:/srv/data", "/restore", ["/ledger.txt"], "never")
	check(bool(never.get("ok", false)) and str(never.entries[0].status) == "skipped", "overwrite never reports skipped")
	check(vm.run("restic restore 00000001:/srv/data --target /restore --include /ledger.txt --overwrite never").begins_with("restored 0 files"), "overwrite never leaves existing bytes")
	check(str(vm.state.fs.get("/restore/ledger.txt", "")) == "changed\n", "overwrite never preserves current file")
	vm.state.snapshots.append({"id":"00000002","repository":"local","paths":["/srv/data"],"files":{"nested/a.txt":"A\n","nested/b.txt":"B\n"}})
	var folder: Dictionary = vm.restic_restore_plan("local", "00000002:/srv/data/nested", "/restore", [])
	check(bool(folder.get("ok", false)) and folder.entries.size() == 2, "folder prefix selects nested files")
	check(vm.run("restic restore 00000002:/srv/data/nested --target /restore").begins_with("restored 2 files"), "nested selection executes")
	check(str(vm.state.fs.get("/restore/a.txt", "")) == "A\n", "nested file restored")
	vm.state.fs["/restore/conflict"] = "blocking file\n"
	var conflict_before: Dictionary = vm.export_state()
	var conflict: Dictionary = vm.restic_restore_plan("local", "00000002:/srv/data", "/restore/conflict")
	check(not bool(conflict.get("ok", false)) and str(conflict.get("error", "")).contains("conflicts"), "file-directory conflict rejected")
	check(JSON.stringify(vm.export_state()) == JSON.stringify(conflict_before), "conflict plan is atomic")
	check(not bool(vm.restic_restore_plan("local", "deadbeef", "/restore").get("ok", false)), "unknown snapshot rejected")
	var legacy_saved: Dictionary = vm.export_state()
	legacy_saved.erase("backup_model_version")
	legacy_saved.snapshots = [legacy_saved.snapshots[0]]
	var legacy = VM.new()
	legacy.setup(1, legacy_saved, {})
	legacy.state.connected = true
	check(int(legacy.state.get("backup_model_version", 0)) == 1, "legacy save remains v1")
	check(legacy.run("restic restore latest --target /restore").begins_with("restored"), "legacy restore remains available")
	check(legacy.state.fs.has("/restore/customers.csv"), "legacy restore path preserved")
	_finish()

func _finish() -> void:
	if failures.is_empty(): print("RESTIC_SELECTION_PASS")
	else:
		for failure in failures: push_error("RESTIC_SELECTION: " + failure)
		print("RESTIC_SELECTION_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
