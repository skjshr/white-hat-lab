extends SceneTree

const VM = preload("res://scripts/virtual_machine.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")
var failures := 0
var tested_individual := 0
var skipped_composites := 0

func _endpoint_result(vm: RefCounted, command: String) -> Dictionary:
	var value: Variant = JSON.parse_string(str(vm.run(command)))
	return value if value is Dictionary else {}

func _init() -> void:
	var cases: Array = CATALOG.all()
	if cases.size() < 36: failures += 1
	for item in cases:
		if item.has("targets") and item.targets is Array and not item.targets.is_empty(): skipped_composites += 1; continue
		tested_individual += 1
		var vm = VM.new(); vm.setup(int(item.chapter), {}, item)
		var initial: Array = vm.evaluate()
		if initial.all(func(v): return v): failures += 1; print("initial unexpectedly pass ", item.id)
		vm.run("ssh client")
		var before_config := str(vm.state.get("fs", {}).get(vm.state.config_path, ""))
		var before_fs: Dictionary = vm.state.get("fs", {}).duplicate(true)
		var before_snapshots: Array = vm.state.get("snapshots", []).duplicate(true)
		var before_evidence := str(vm.state.get("evidence_original", ""))
		var before_evidence_file := str(vm.state.get("fs", {}).get("/var/log/evidence.log", ""))
		var probe_before: Dictionary = {}
		for probe in vm._active_probes():
			probe_before[str(probe.get("id", ""))] = {"recorded":probe.get("recorded",null),"passed":probe.get("passed",null),"fresh":probe.get("fresh",null),"result":probe.get("result",null)}
		vm.cooperate("aya", {"name":"observer", "observed_day":"1", "observed_time":"09:00", "report_path":"/home/operator/observer-result.txt"})
		var observer_report := str(vm.state.fs.get("/home/operator/observer-result.txt", ""))
		if not observer_report.contains("$ ") or observer_report.contains("$ curl -X PUT") or observer_report.contains("$ restic restore") or observer_report.contains("$ systemctl restart"): failures += 1; print("aya report missing safe observations or included write operation ", item.id)
		var eligible_probe_count := 0
		for probe in vm._active_probes():
			var probe_command := str(probe.get("command", "")).strip_edges()
			var eligible := (probe_command.begins_with("smbclient ") and probe_command.contains(" -c ls")) or probe_command.begins_with("restic snapshots") or probe_command.begins_with("restic ls ") or probe_command.begins_with("restic dump ") or probe_command.begins_with("dig ") or (probe_command.begins_with("curl ") and not probe_command.contains("-X") and not probe_command.contains("--request") and not probe_command.contains("--data") and not probe_command.contains(" -d ") and not probe_command.contains(" -T ") and not probe_command.contains("/login")) or probe_command.begins_with("identity users") or probe_command.begins_with("identity sessions") or probe_command.begins_with("edr devices") or probe_command.begins_with("edr timeline ") or probe_command.begins_with("sha256sum ")
			if not eligible: continue
			eligible_probe_count += 1
			var marker := "$ " + probe_command
			var marker_at := observer_report.find(marker)
			var output_after := observer_report.substr(marker_at + marker.length()) if marker_at >= 0 else ""
			if marker_at < 0 or output_after.strip_edges().is_empty() or output_after.strip_edges().begins_with("$"): failures += 1; print("aya report missing exact probe output ", item.id, " ", probe_command)
		if eligible_probe_count > 0 and not observer_report.contains("$ "): failures += 1; print("aya report has eligible probes but no observations ", item.id)
		for probe in vm._active_probes():
			var before_probe: Dictionary = probe_before.get(str(probe.get("id", "")), {})
			for field in ["recorded","passed","fresh","result"]:
				if probe.get(field, null) != before_probe.get(field, null): failures += 1; print("aya changed diagnostic measurement ", item.id, " ", probe.get("id", ""), " field=", field, " before=", before_probe.get(field, null), " after=", probe.get(field, null))
		if str(vm.state.get("fs", {}).get(vm.state.config_path, "")) != before_config: failures += 1; print("aya changed config ", item.id)
		if vm.state.get("snapshots", []) != before_snapshots or str(vm.state.get("evidence_original", "")) != before_evidence or str(vm.state.get("fs", {}).get("/var/log/evidence.log", "")) != before_evidence_file: failures += 1; print("aya changed protected evidence or snapshots ", item.id)
		var fs_after: Dictionary = vm.state.get("fs", {}).duplicate(true); fs_after.erase("/home/operator/observer-result.txt"); before_fs.erase("/home/operator/observer-result.txt")
		if fs_after != before_fs: failures += 1; print("aya changed non-report VM files ", item.id)
		vm.cooperate("ren")
		if item.has("latest_snapshot_overrides"):
			var colon_vm = VM.new(); colon_vm.setup(1, {}, item); colon_vm.run("ssh client")
			colon_vm.write_file(str(colon_vm.state.config_path), colon_vm._config_text(item.desired)); colon_vm.run("systemctl restart restic")
			colon_vm.run("restic restore 00000001:/srv/data --target /restore")
			for colon_probe in colon_vm.probes(): colon_vm.run(str(colon_probe.command))
			if not colon_vm.evaluate().all(func(v): return v) or colon_vm.state.fs.get("/restore/ledger.txt", "") != colon_vm.RECORDS["ledger.txt"]: failures += 1; print("colon-only restore did not satisfy measured case ",item.id)
		if not item.desired.is_empty():
			vm.write_file(str(vm.state.config_path), vm._config_text(item.desired))
			vm.run("systemctl restart "+str(vm.state.service))
		if int(item.chapter) == 1:
			if item.has("latest_snapshot_overrides"):
				var before_unknown := vm._fingerprint()
				if not vm.run("restic snapshots").contains("00000001") or not vm.run("restic ls 00000001").contains("/srv/data/ledger.txt"): failures += 1; print("snapshot inventory missing ",item.id)
				if not vm.run("restic dump 00000002 /srv/data/ledger.txt").contains("CORRUPTED DATA"): failures += 1; print("latest bad snapshot not observable ",item.id)
				if not vm.run("restic restore deadbeef --target /restore").contains("snapshot not found") or vm._fingerprint() != before_unknown: failures += 1; print("unknown snapshot mutated state ",item.id)
				var before_invalid := vm._fingerprint()
				if not vm.run("restic restore 0000000 --target /restore").contains("ambiguous") or vm._fingerprint() != before_invalid: failures += 1; print("ambiguous snapshot prefix accepted ",item.id)
				if not vm.run("restic -r local snapshots").contains("no snapshots") or not vm.run("restic snapshots --unknown").contains("invalid snapshots flags"): failures += 1; print("repository or unknown flag handling failed ",item.id)
			if not item.has("seed_snapshot_repository") or str(item.seed_snapshot_repository) != str(item.desired.get("repository", "")): vm.run("restic backup /srv/data")
			vm.run("restic restore 00000001 --target /restore" if item.has("latest_snapshot_overrides") else "restic restore latest --target /restore")
			if item.has("latest_snapshot_overrides"):
				if not vm.run("restic restore 00000001:/srv/data --target /restore").contains("restored") or vm.state.fs.get("/restore/ledger.txt", "") != vm.RECORDS["ledger.txt"]: failures += 1; print("subfolder restore failed ",item.id)
		if int(item.chapter) == 4:
			vm.run("cp /var/log/evidence.log /evidence/original.log")
		# Endpoint recovery has an operational EDR workflow in addition to the
		# shared config projection above.  Exercise those real commands before
		# evaluating the catalog probes; a config-only solve would leave the
		# threat and endpoint scans stale.
		if bool(item.get("edr_recovery_required", false)):
			var collected := _endpoint_result(vm, "edr collect")
			if not bool(collected.get("ok", false)) or not bool(collected.get("evidence", {}).get("valid", false)):
				failures += 1; print("endpoint evidence collection failed ", item.id, " result=", collected)
			var quarantined := _endpoint_result(vm, "edr quarantine pc_a pc_a-sync")
			if not bool(quarantined.get("ok", false)) or not bool(quarantined.get("changed", false)):
				failures += 1; print("endpoint threat quarantine failed ", item.id, " result=", quarantined)
			var scan_a := _endpoint_result(vm, "edr scan pc_a")
			var scan_b := _endpoint_result(vm, "edr scan pc_b")
			if not bool(scan_a.get("ok", false)) or not bool(scan_a.get("clean", false)) or not bool(scan_b.get("ok", false)) or not bool(scan_b.get("clean", false)):
				failures += 1; print("endpoint clean scans failed ", item.id, " pc_a=", scan_a, " pc_b=", scan_b)
		var result: Array = vm.evaluate()
		# The catalog owns the complete condition list, including newer
		# preservation checks added to appliance commissioning.
		var expected_checks: int = item.checks.size()
		if result.size() != expected_checks or not result.all(func(v): return v): failures += 1; print("manual solve fail ", item.id, " result=", result, " expected=", expected_checks)
		var saved: Dictionary = vm.export_state()
		var restored = VM.new(); restored.setup(int(item.chapter), saved, item)
		if restored.evaluate() != result: failures += 1; print("restore mismatch ", item.id)
		if int(item.chapter) >= 0:
			restored.write_file(str(restored.state.config_path), "dirty=true\n")
			if restored.evaluate().all(func(v): return v): failures += 1
	for chapter in range(6):
		var legacy = VM.new(); legacy.setup(chapter); legacy.run("ssh client"); legacy.cooperate("aya"); legacy.cooperate("ren")
		if legacy.evaluate().all(func(v): return v): failures += 1; print("legacy NPC unexpectedly solved ", chapter)
	var old_source = VM.new(); old_source.setup(1, {}, CATALOG.by_id("service-1-case-3"))
	var old_saved: Dictionary = old_source.export_state(); old_saved.erase("backup_model_version")
	var old_loaded = VM.new(); old_loaded.setup(1, old_saved, CATALOG.by_id("service-1-case-3")); old_loaded.run("ssh client")
	if int(old_loaded.state.get("backup_model_version", 0)) != 1 or not old_loaded.run("restic restore latest --target /restore").contains("restored") or not old_loaded.state.fs.has("/restore/ledger.txt"): failures += 1; print("legacy backup restore compatibility failed")
	# Worker metadata may identify the contributor and relocate only the report;
	# the bounded role operation and old one-argument API remain unchanged.
	var worker_vm = VM.new(); worker_vm.setup(0, {}, CATALOG.by_id("service-0-case-0")); worker_vm.run("ssh client")
	worker_vm.cooperate("aya", {"name":"水野 美緒", "report_path":"/home/operator/mio-result.txt"})
	var mio_report := str(worker_vm.state.fs.get("/home/operator/mio-result.txt", ""))
	if not mio_report.contains("担当: 水野 美緒") or worker_vm.state.fs.has("/home/operator/aya-inspection.txt"): failures += 1; print("worker report attribution/path failed")
	if not mio_report.contains("$ ") or mio_report.contains("$ smbclient //client/share -U staff -c put"): failures += 1; print("worker report missing measured probe output")
	worker_vm.cooperate("aya")
	if not worker_vm.state.fs.has("/home/operator/aya-inspection.txt"): failures += 1; print("legacy aya report path changed")
	var ren_worker = VM.new(); ren_worker.setup(1, {}, CATALOG.by_id("service-1-case-3")); ren_worker.run("ssh client")
	ren_worker.cooperate("ren", {"name":"佐々木 遥", "report_path":"/home/operator/haru-recovery.txt"})
	var ren_report := str(ren_worker.state.fs.get("/home/operator/haru-recovery.txt", ""))
	if not ren_report.contains("担当: 佐々木 遥") or not bool(ren_worker.state.get("cooperation_requires_selection", false)): failures += 1; print("worker recovery report/selection gate failed")
	# A changed service result must be reflected in a later investigation report.
	var changing_vm := VM.new(); changing_vm.setup(2, {}, CATALOG.by_id("service-2-case-0")); changing_vm.run("ssh client")
	changing_vm.cooperate("aya", {"report_path":"/home/operator/first-observation.txt"})
	var first_observation := str(changing_vm.state.fs.get("/home/operator/first-observation.txt", ""))
	changing_vm.write_file(str(changing_vm.state.config_path), changing_vm._config_text(CATALOG.by_id("service-2-case-0").desired)); changing_vm.run("systemctl restart firewall")
	changing_vm.cooperate("aya", {"report_path":"/home/operator/second-observation.txt"})
	var second_observation := str(changing_vm.state.fs.get("/home/operator/second-observation.txt", ""))
	if first_observation == second_observation or not first_observation.contains("SERVFAIL") or not second_observation.contains("NOERROR"): failures += 1; print("aya report did not reflect changed diagnostic output")
	print("VM cooperation catalog=%d individual=%d composites_skipped=%d failures=%d" % [cases.size(), tested_individual, skipped_composites, failures])
	quit(1 if failures > 0 else 0)
