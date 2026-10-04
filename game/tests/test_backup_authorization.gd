extends SceneTree

const VM = preload("res://scripts/virtual_machine.gd")
const CAT = preload("res://scripts/case_catalog.gd")
const CASE_ID := "service-1-case-3"
const ORIGINAL := "/srv/data/ledger.txt"
const UNRELATED := "/srv/data/customers.csv"
const RECOVERED := "/restore/srv/data/ledger.txt"
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		print("FAIL backup_authorization: ",label)

func _wire(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _fresh():
	var vm = VM.new()
	vm.setup(1,{},CAT.by_id(CASE_ID))
	vm.run("ssh client")
	return vm

func _load(saved: Dictionary):
	var vm = VM.new()
	vm.setup(1,JSON.parse_string(JSON.stringify(saved)),CAT.by_id(CASE_ID))
	vm.run("ssh client")
	return vm

func _restore(vm, selector: String, root: String, source: String = ORIGINAL) -> String:
	return vm.run("restic -r offsite restore %s --target %s --include %s --overwrite always" % [selector,root,source])

func _all_pass(vm) -> bool:
	var checks: Array = vm.evaluate()
	return not checks.is_empty() and checks.all(func(item): return bool(item))

func _row(rows: Array, path: String) -> Dictionary:
	for item in rows:
		if item is Dictionary and str(item.get("path","")) == path: return item
	return {}

func run() -> void:
	var vm = _fresh()
	var original_bytes: String = vm.read_file(ORIGINAL)
	var unrelated_bytes: String = vm.read_file(UNRELATED)
	var baseline: Dictionary = vm.state.get("backup_authorization",{}).duplicate(true)
	var baseline_wire := _wire(baseline)
	var view: Dictionary = vm.backup_acceptance_view()
	check(int(vm.state.get("backup_authorization_version",0)) == 1, "fresh save has authorization generation stamp")
	check(int(baseline.get("version",0)) == 1 and str(baseline.get("case_id","")) == CASE_ID, "fresh baseline binds real authored case")
	check(str(baseline.get("restore_root","")) == "/restore" and ORIGINAL in baseline.get("required_files",[]), "baseline records approved destination and requested file")
	check(bool(view.get("available",false)) and bool(view.get("enforced",false)) and not bool(view.get("legacy",true)), "fresh acceptance is enforced")
	check(vm.evaluate().size() == 5 and not _all_pass(vm), "fresh case has five checks and cannot pass without restoration")
	check(bool(view.get("original_preserved",false)) and bool(view.get("unrelated_preserved",false)) and not bool(view.get("restore_valid",true)), "initial corrupt original is protected, but recovery remains incomplete")
	var protected: Dictionary = baseline.get("protected_files",{})
	check(protected.has(ORIGINAL) and protected.has(UNRELATED), "baseline covers original and unrelated customer data")
	for path in protected:
		var metadata: Dictionary = protected[path]
		check(metadata.get("exists") is bool and metadata.get("sha256") is String, "protected metadata uses existence and hash: " + str(path))
		check(not metadata.has("content") and not metadata.has("bytes"), "protected baseline does not store raw file bodies: " + str(path))
	check(str(protected.get(ORIGINAL,{}).get("sha256","")) == original_bytes.sha256_text(), "original hash records corrupted intake bytes, not desired recovery bytes")
	var manifest_path := str(view.get("manifest_path",""))
	check(not manifest_path.is_empty(), "authorization manifest has a readable path")
	check(not vm.read_file(manifest_path).is_empty(), "authorization manifest is available through real VM read")

	# Obtain actual IDs from the advertised snapshot inventory; do not assume names.
	var clean_snapshot := ""
	var clean_bytes := ""
	var listed: String = vm.run("restic -r offsite snapshots")
	for line in listed.split("\n"):
		var fields := line.strip_edges().split(" ",false)
		if fields.size() < 2 or str(fields[1]) != "offsite": continue
		var candidate_id := str(fields[0])
		var candidate_bytes: String = vm.run("restic -r offsite dump %s %s" % [candidate_id,ORIGINAL])
		if candidate_bytes != original_bytes and not candidate_bytes.begins_with("restic:"):
			clean_snapshot = candidate_id; clean_bytes = candidate_bytes; break
	check(not clean_snapshot.is_empty() and not clean_bytes.is_empty(), "seed inventory contains an older healthy ledger")
	if clean_snapshot.is_empty():
		_finish(); return
	check(vm.run("restic -r offsite dump latest " + ORIGINAL) == original_bytes, "actual latest snapshot contains the reported corruption")
	check(_restore(vm,"latest","/restore").begins_with("restored 1 files"), "wrong latest restore really writes one file")
	view = vm.backup_acceptance_view()
	check(vm.read_file(RECOVERED) == original_bytes and not bool(view.get("restore_valid",true)) and not bool(view.get("accepted",true)), "latest corrupt bytes fail recovery acceptance")
	check(not _all_pass(vm), "wrong snapshot cannot satisfy final checks")
	var corrupt_snapshot := str(view.get("selected_snapshot",""))
	check(_restore(vm,clean_snapshot,"/restore","/srv/data/orders.csv").begins_with("restored 1 files"), "healthy snapshot orders-only restore executes")
	view = vm.backup_acceptance_view()
	check(not bool(view.get("restore_valid",true)) and str(view.get("selected_snapshot","")) == corrupt_snapshot, "healthy unrelated restore cannot relabel corrupted ledger provenance")

	check(_restore(vm,clean_snapshot,"/restore-other").begins_with("restored 1 files"), "healthy bytes can be restored to another location")
	check(not bool(vm.backup_acceptance_view().get("restore_valid",true)) and not _all_pass(vm), "prefix lookalike destination is outside authorized /restore")
	check(_restore(vm,clean_snapshot,"/restore").begins_with("restored 1 files"), "selected older ledger restored to approved destination")
	view = vm.backup_acceptance_view()
	var restored_row := _row(view.get("restored",[]),RECOVERED)
	check(vm.read_file(RECOVERED) == clean_bytes and bool(restored_row.get("matched",false)), "approved artifact contains actual selected healthy bytes")
	check(str(restored_row.get("source","")) == ORIGINAL and str(restored_row.get("expected_sha256","")) == clean_bytes.sha256_text() and str(restored_row.get("current_sha256","")) == clean_bytes.sha256_text(), "restored artifact exposes source, actual path and both hashes")
	check(bool(view.get("restore_valid",false)) and bool(view.get("accepted",false)) and _all_pass(vm), "scoped healthy restoration passes all five checks")
	check(str(view.get("selected_snapshot","")) == clean_snapshot, "acceptance identifies actually selected snapshot")
	check(str(restored_row.get("snapshot","")) == clean_snapshot, "restored ledger row identifies its actual source snapshot")
	check(_restore(vm,"latest","/restore","/srv/data/orders.csv").begins_with("restored 1 files"), "latest snapshot orders-only restore executes after healthy ledger")
	view = vm.backup_acceptance_view()
	check(str(view.get("selected_snapshot","")) == clean_snapshot and bool(view.get("accepted",false)), "later unrelated restore does not attribute latest snapshot to healthy ledger")
	check(str(_row(view.get("restored",[]),RECOVERED).get("snapshot","")) == clean_snapshot, "ledger row retains per-file provenance after unrelated restore")
	check(_restore(vm,"latest","/tmp/unrelated-restore","/srv/data/orders.csv").begins_with("restored 1 files"), "unrelated restore to a different destination executes")
	view = vm.backup_acceptance_view()
	check(str(view.get("selected_snapshot","")) == clean_snapshot and bool(view.get("restore_valid",false)) and _all_pass(vm), "later different destination cannot move required ledger artifact")
	var ledger_probes: Array = vm.probes().filter(func(probe): return str(probe.get("id","")) == "restore-ledger.txt")
	check(ledger_probes.size() == 1 and str(ledger_probes[0].get("command","")) == "sha256sum " + RECOVERED, "ledger diagnostic still measures actual approved ledger path")
	var origins_wire := _wire(vm.state.get("backup_restore_origins",{}))
	var provenance_reload = _load(vm.export_state())
	check(_wire(provenance_reload.state.get("backup_restore_origins",{})) == origins_wire, "JSON reload preserves every per-file restore origin")
	check(str(provenance_reload.backup_acceptance_view().get("selected_snapshot","")) == clean_snapshot and _all_pass(provenance_reload), "JSON reload preserves ledger provenance after unrelated destination changes")

	check(vm.write_file(ORIGINAL,clean_bytes), "simulate unauthorized overwrite using real file API")
	view = vm.backup_acceptance_view()
	check(not bool(view.get("original_preserved",true)) and bool(view.get("unrelated_preserved",false)) and not bool(view.get("accepted",true)), "repairing source in place violates original preservation")
	check(not _all_pass(vm), "original overwrite fails final checks")
	var original_row := _row(view.get("protected",[]),ORIGINAL)
	check(str(original_row.get("kind","")) == "original" and not bool(original_row.get("preserved",true)), "original damage is separately identified")
	check(str(original_row.get("expected_sha256","")) == original_bytes.sha256_text() and str(original_row.get("current_sha256","")) == clean_bytes.sha256_text(), "original comparison remains against intake hash")
	var forged := baseline.duplicate(true)
	forged.protected_files[ORIGINAL].sha256 = clean_bytes.sha256_text()
	vm.write_file(manifest_path,JSON.stringify(forged))
	check(_wire(vm.state.backup_authorization) == baseline_wire and not bool(vm.backup_acceptance_view().get("accepted",true)), "editing readable manifest cannot rewrite trusted baseline or grant acceptance")
	var bad_saved: Dictionary = vm.export_state()
	var bad_reload = _load(bad_saved)
	check(_wire(bad_reload.state.get("backup_authorization",{})) == baseline_wire, "reload does not recapture baseline after original overwrite")
	check(not bool(bad_reload.backup_acceptance_view().get("original_preserved",true)) and not _all_pass(bad_reload), "unauthorized original change remains rejected after reload")

	check(_restore(vm,"latest","/").begins_with("restored 1 files"), "latest snapshot restores exact corrupted intake source bytes")
	view = vm.backup_acceptance_view()
	check(vm.read_file(ORIGINAL) == original_bytes and bool(view.get("original_preserved",false)), "source original can be recovered without changing baseline")
	check(not bool(view.get("restore_valid",true)) and not bool(view.get("accepted",true)), "root restore requires a new authorized artifact restore")
	_restore(vm,clean_snapshot,"/restore")
	check(bool(vm.backup_acceptance_view().get("accepted",false)), "approved artifact restore completes recovery after source repair")
	check(vm.write_file(UNRELATED,"UNAUTHORIZED CUSTOMER CHANGE\n"), "unrelated overwrite uses real file API")
	view = vm.backup_acceptance_view()
	check(bool(view.get("original_preserved",false)) and not bool(view.get("unrelated_preserved",true)) and not bool(view.get("accepted",true)), "unrelated customer file change independently blocks acceptance")
	check(str(_row(view.get("protected",[]),UNRELATED).get("kind","")) == "unrelated" and not _all_pass(vm), "unrelated violation is classified and blocks final checks")
	check(_restore(vm,clean_snapshot,"/",UNRELATED).begins_with("restored 1 files") and vm.read_file(UNRELATED) == unrelated_bytes, "selective snapshot restore recovers unrelated original bytes")
	_restore(vm,clean_snapshot,"/restore")
	check(bool(vm.backup_acceptance_view().get("accepted",false)) and _all_pass(vm), "preserved original and unrelated files plus approved artifact pass")
	check(vm.write_file("/srv/data/unauthorized-extra.txt","extra\n"), "new unrelated data can be observed")
	check(not bool(vm.backup_acceptance_view().get("unrelated_preserved",true)) and not _all_pass(vm), "added customer data is an unauthorized unrelated change")
	vm.run("rm /srv/data/unauthorized-extra.txt")
	_restore(vm,clean_snapshot,"/restore")
	check(_all_pass(vm), "removing unauthorized addition and restoring artifact recovers acceptance")
	check(_wire(vm.state.backup_authorization) == baseline_wire, "all real operations preserve immutable authorization hashes")
	var accepted_saved: Dictionary = vm.export_state()
	var reloaded = _load(accepted_saved)
	check(_wire(reloaded.state.get("backup_authorization",{})) == baseline_wire and _all_pass(reloaded), "JSON reload preserves baseline and accepted state")
	_test_legacy(accepted_saved)
	_test_invalid_baseline(accepted_saved)
	_finish()

func _test_legacy(saved: Dictionary) -> void:
	var legacy_saved := saved.duplicate(true)
	legacy_saved.erase("backup_authorization")
	legacy_saved.erase("backup_authorization_version")
	legacy_saved.erase("backup_restore_origins")
	legacy_saved.scenario.erase("backup_preservation_required")
	legacy_saved.scenario.checks = legacy_saved.scenario.checks.slice(0,3)
	var legacy = _load(legacy_saved)
	var view: Dictionary = legacy.backup_acceptance_view()
	check(not legacy.state.has("backup_authorization") and not legacy.state.has("backup_authorization_version"), "saved legacy case does not recapture a new authorization baseline")
	check(not bool(view.get("enforced",true)) and bool(view.get("legacy",false)), "legacy acceptance explicitly reports non-enforced compatibility")
	check(legacy.evaluate().size() == 3 and _all_pass(legacy), "legacy saved case retains old three-check acceptance")

func _test_invalid_baseline(saved: Dictionary) -> void:
	var cases: Array = []
	for value in [null,[],"invalid",{}, {"version":99}]:
		var corrupt := saved.duplicate(true); corrupt.backup_authorization = value
		cases.append({"label":"payload " + str(typeof(value)),"state":corrupt})
	var missing := saved.duplicate(true); missing.erase("backup_authorization")
	cases.append({"label":"known generation missing payload","state":missing})
	var flag_only := saved.duplicate(true)
	flag_only.erase("backup_authorization"); flag_only.erase("backup_authorization_version")
	flag_only.scenario.backup_preservation_required = true
	cases.append({"label":"known scenario flag missing payload and stamp","state":flag_only})
	var future := saved.duplicate(true); future.backup_authorization.version = 99
	cases.append({"label":"unknown payload version","state":future})
	var bad_map := saved.duplicate(true); bad_map.backup_authorization.protected_files = []
	cases.append({"label":"protected map type","state":bad_map})
	for fixture in cases:
		var bad = _load(fixture.state)
		var view: Dictionary = bad.backup_acceptance_view()
		check(not bool(view.get("legacy",false)) and not bool(view.get("accepted",true)), "invalid known authorization fails closed: " + str(fixture.label))
		check(not _all_pass(bad), "invalid authorization cannot pass evaluation: " + str(fixture.label))
		check(_wire(bad.state.get("backup_authorization")) == _wire(fixture.state.get("backup_authorization")), "invalid payload is not silently regenerated: " + str(fixture.label))

func _finish() -> void:
	print("BACKUP_AUTHORIZATION_PASS assertions=%d" % assertions if failures.is_empty() else "BACKUP_AUTHORIZATION_FAIL failures=%d assertions=%d" % [failures.size(),assertions])
	quit(0 if failures.is_empty() else 1)
