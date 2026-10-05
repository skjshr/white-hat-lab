extends SceneTree
## Real pre-change accepted save plus new-case file/response boundaries.
const CATALOG = preload("res://scripts/case_catalog.gd")
const VM = preload("res://scripts/virtual_machine.gd")
const BOARD = preload("res://scripts/samba_access_board.gd")
var assertions := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ", label)
func same(a: Variant, b: Variant) -> bool: return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))
func write_row(probes: Array) -> Dictionary:
	return BOARD.project(probes).filter(func(row): return str(row.id) == "staff-write")[0]
func run() -> void:
	var game = root.get_node("Game"); game.set_process(false)
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	var path := OS.get_environment("WHL_OLD_DAILY_FIXTURE")
	var old_text := FileAccess.get_file_as_string(path)
	var old: Variant = JSON.parse_string(old_text)
	if not old is Dictionary or str(old.get("contract", {}).get("case_id", "")) != "service-0-case-0": push_error("genuine old accepted daily-report save required"); quit(2); return
	var file := FileAccess.open(game.save_path, FileAccess.WRITE); file.store_string(old_text); file.close()
	check(game.load_game(), "load actual pre-change accepted daily-report save")
	# The earned company contains earlier contracts of the same case. Compare
	# this accepted contract's actual VM key, never the first matching template.
	var old_vm: Dictionary = old.vm_states[game._vm_key()]
	check(same(game._vm().state.fs, old_vm.fs), "old saved customer bytes remain exact")
	check(same(game._vm().state.scenario.probes, old_vm.scenario.probes), "accepted old probe targets remain exact")
	check(not game._vm().state.fs.has("/srv/data/report.txt"), "old saves are not silently populated with new customer draft")
	check(str(game.diagnostic_probes().filter(func(row): return str(row.id) == "staff-write")[0].command).contains("orders.csv"), "old accepted contract still measures its original order transfer")
	check(game.save_game() and game.load_game() and same(game._vm().state.fs, old_vm.fs), "save/resume retains old actual customer data")
	check(FileAccess.get_file_as_string(path) == old_text, "real pre-change source remains untouched")
	var scenario: Dictionary = CATALOG.all().filter(func(row): return str(row.id) == "service-0-case-0")[0]
	var vm = VM.new(); vm.setup(0, {}, scenario); vm.run("ssh client")
	var prior: String = vm.state.fs["/srv/share/report.txt"]
	var daily: String = vm.state.fs["/srv/data/report.txt"]
	check(prior != daily and daily.contains("本日受付 12件"), "new contract seeds actual distinct daily report bytes")
	check(vm.execute_probe("staff-write") == "NT_STATUS_ACCESS_DENIED" and vm.state.fs["/srv/share/report.txt"] == prior, "denied new report transfer leaves yesterday's report intact")
	check(vm.write_file("/etc/samba/smb.conf", SambaConfig.configuration_text({"staff":"write","guest":"none"})), "backend fixture writes valid restricted configuration via actual file API")
	vm.run("systemctl restart samba")
	check(vm.execute_probe("staff-write") == "putting file report.txt: OK" and vm.state.fs["/srv/share/report.txt"] == daily, "new authorized transfer really replaces yesterday with today's report")
	check(vm.execute_probe("guest-read") == "NT_STATUS_ACCESS_DENIED" and vm.execute_probe("guest-write") == "NT_STATUS_ACCESS_DENIED", "repaired daily report still rejects guest reading and writing")
	var probes: Array = scenario.probes.duplicate(true)
	for probe in probes:
		if str(probe.id) == "staff-write": probe.merge({"recorded":true,"fresh":true,"result":"putting file report.txt: OK","passed":true}, true)
	check(write_row(probes).passed == true and write_row(probes).file == "report.txt", "projection recognizes exact actual daily-report success")
	for probe in probes:
		if str(probe.id) == "staff-write": probe.result = "putting file orders.csv: OK"
	check(write_row(probes).status == "unknown" and write_row(probes).passed == null, "another successful file cannot stand in for daily-report evidence")
	var restored = VM.new(); var saved: Dictionary = vm.export_state(); restored.setup(0, saved, scenario)
	check(same(restored.state.fs, saved.fs) and same(restored.state.scenario.probes, saved.scenario.probes), "new actual report and authored transfer survive restore")
	print("DAILY_REPORT_COMPATIBILITY assertions=", assertions, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
