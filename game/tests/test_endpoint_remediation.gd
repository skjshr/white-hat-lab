extends SceneTree

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL ", label)

func parsed(vm: RefCounted, command: String) -> Dictionary:
	var value = JSON.parse_string(str(vm.run(command)))
	return value if value is Dictionary else {}

func _init() -> void:
	var scenario := {"id":"endpoint-recovery","edr_recovery_required":true,"suspect":"pc_a","tier":2,"desired":{"pc_a":"connected","pc_b":"connected","logs":"keep","reset":"wait"}}
	var vm = preload("res://scripts/virtual_machine.gd").new()
	vm.setup(4, {}, scenario)
	check(str(vm.run("ssh client")).contains("Authenticated"), "v2 console connection")
	var files := parsed(vm, "edr files pc_a")
	check(bool(files.get("ok",false)) and files.get("files",[]).any(func(item): return str(item.get("id","")) == "pc_a-sync" and str(item.get("name","")) == "sync-agent.exe"), "malicious file is observable")
	check(files.get("files",[]).any(func(item): return str(item.get("id","")) == "pc_a-backup" and str(item.get("name","")) == "backup-agent.exe"), "legitimate backup file is observable")
	var evidence_before := str(vm.state.fs.get("/var/log/evidence.log", ""))
	var collected := parsed(vm, "edr collect")
	check(bool(collected.get("ok",false)) and bool(collected.get("evidence",{}).get("valid",false)), "evidence collection succeeds")
	var evidence_copy := str(vm.state.fs.get("/evidence/original.log", ""))
	var collected_again := parsed(vm, "edr collect")
	check(bool(collected_again.get("ok",false)) and str(vm.state.fs.get("/var/log/evidence.log", "")) == evidence_before and str(vm.state.fs.get("/evidence/original.log", "")) == evidence_copy, "repeated collect preserves immutable evidence")

	var isolated := parsed(vm, "edr isolate pc_a")
	check(bool(isolated.get("ok",false)) and bool(isolated.get("isolated",false)), "isolation changes actual endpoint state")
	check(str(vm.run("curl https://edr.client.test/pc-a/business")).begins_with("HTTP/1.1 403"), "isolated business is interrupted")
	var released_early := parsed(vm, "edr release pc_a")
	check(bool(released_early.get("ok",false)), "premature release remains an observable operation")
	check(not vm.evaluate().all(func(item): return bool(item)), "release alone does not satisfy remediation readiness")

	var scan_before := parsed(vm, "edr scan pc_a")
	check(int(scan_before.get("threat_count",0)) > 0 and not bool(scan_before.get("clean",false)), "scan identifies active threat")
	var quarantined := parsed(vm, "edr quarantine pc_a pc_a-sync")
	check(bool(quarantined.get("ok",false)) and bool(quarantined.get("changed",false)) and int(quarantined.get("quarantine_id",-1)) > 0, "malicious file quarantine removes actual bytes")
	var quarantine_id := int(quarantined.get("quarantine_id",-1))
	var quarantine_record: Dictionary = quarantined.get("quarantine", {}) if quarantined.get("quarantine", {}) is Dictionary else {}
	check(not str(quarantine_record.get("bytes", "")).is_empty() and str(quarantine_record.get("bytes", "")).sha256_text() == str(quarantine_record.get("sha256", "")), "quarantine preserves exact malicious bytes and hash")
	var files_after_quarantine := parsed(vm, "edr files pc_a")
	check(files_after_quarantine.get("files",[]).any(func(item): return str(item.get("id","")) == "pc_a-sync" and not bool(item.get("present",true)) and bool(item.get("quarantined",false)) and str(item.get("current_sha256","")) == ""), "quarantine file projection reflects missing current bytes")
	var repeated_quarantine := parsed(vm, "edr quarantine pc_a pc_a-sync")
	check(bool(repeated_quarantine.get("ok",false)) and not bool(repeated_quarantine.get("changed",true)) and int(repeated_quarantine.get("quarantine_id",-1)) == quarantine_id, "repeated quarantine is idempotent")
	var scan_clean := parsed(vm, "edr scan pc_a")
	check(bool(scan_clean.get("ok",false)) and bool(scan_clean.get("clean",false)) and int(scan_clean.get("threat_count",-1)) == 0, "post-quarantine scan is clean")
	var status_clean := parsed(vm, "edr status pc_a")
	check(bool(status_clean.get("ready",false)), "clean endpoint status is ready")
	var moved_path := "/endpoints/pc_a/renamed.exe"
	check(vm.write_file(moved_path,preload("res://scripts/endpoint_remediation.gd").MALICIOUS_BYTES),"copied threat fixture written through VM")
	check(not bool(parsed(vm,"edr status pc_a").get("scan_current",true)),"unknown endpoint file invalidates prior scan")
	check(int(parsed(vm,"edr scan pc_a").get("threat_count",0)) == 1,"copied threat bytes detected at new path")
	vm.run("rm "+moved_path)
	parsed(vm,"edr scan pc_a")
	check(str(vm.state.fs.get("/var/log/evidence.log", "")) == evidence_before and str(vm.state.fs.get("/evidence/original.log", "")) == evidence_copy, "remediation does not alter evidence bytes")
	check(str(vm.run("curl https://edr.client.test/pc-a/business")).begins_with("HTTP/1.1 200"), "released remediated endpoint serves business")

	var other := preload("res://scripts/virtual_machine.gd").new()
	other.setup(4, {}, scenario)
	other.run("ssh client")
	var wrong := parsed(other, "edr quarantine pc_a pc_a-backup")
	check(bool(wrong.get("ok",false)), "legitimate file quarantine is accepted as an operational mistake")
	check(str(other.run("curl https://edr.client.test/pc-a/business")).begins_with("HTTP/1.1 503"), "missing legitimate business binary causes service unavailable")
	var wrong_id := int(wrong.get("quarantine_id",-1))
	var wrong_record: Dictionary = other.state.edr_quarantine.back().duplicate(true)
	other.write_file(str(wrong_record.get("guest_path","")), "CONFLICTING BYTES")
	var conflict := parsed(other, "edr restore "+str(wrong_id))
	check(not bool(conflict.get("ok",true)) and int(conflict.get("code",0)) == 409, "restore conflict is rejected")
	other.state.fs.erase(str(wrong_record.get("guest_path","")))
	var restored := parsed(other, "edr restore "+str(wrong_id))
	check(bool(restored.get("ok",false)) and bool(restored.get("changed",false)), "legitimate file restores from quarantine")
	check(str(other.run("curl https://edr.client.test/pc-a/business")).begins_with("HTTP/1.1 200"), "business returns after legitimate bytes restore")

	var malicious_restore := parsed(vm, "edr restore "+str(quarantine_id))
	check(bool(malicious_restore.get("ok",false)), "malicious quarantine restore is possible for rollback")
	var stale_status := parsed(vm, "edr status pc_a")
	check(not bool(stale_status.get("scan_current",true)) and not bool(stale_status.get("ready",true)), "restoring bytes stales the previous clean scan")
	var restored_scan := parsed(vm, "edr scan pc_a")
	check(int(restored_scan.get("threat_count",0)) > 0 and not bool(parsed(vm,"edr status pc_a").get("ready",true)), "restoring malicious bytes invalidates clean readiness")

	var roundtrip = preload("res://scripts/virtual_machine.gd").new()
	roundtrip.setup(4, JSON.parse_string(JSON.stringify(vm.export_state())), scenario)
	check(bool(parsed(roundtrip, "edr files pc_a").get("ok",false)), "v2 remediation state survives VM save roundtrip")
	check(str(roundtrip.run("edr status pc_a")).contains("\"ready\":false"), "roundtrip preserves non-ready restored threat")

	var legacy = preload("res://scripts/virtual_machine.gd").new()
	legacy.setup(4, {}, {"id":"legacy-edr","desired":{"pc_a":"isolated","pc_b":"connected","logs":"keep","reset":"wait"}})
	legacy.run("ssh client")
	check(not bool(parsed(legacy, "edr files pc_a").get("ok",true)) and int(parsed(legacy,"edr files pc_a").get("code",0)) == 426, "unlinked chapter4 scenario does not expose remediation API")
	check(not legacy.state.has("edr_files"), "legacy scenario does not initialize remediation files")
	var final_case: Dictionary = preload("res://scripts/case_catalog.gd").by_id("endpoint-recovery")
	var final_vm = preload("res://scripts/virtual_machine.gd").new()
	final_vm.setup(4,{},final_case)
	final_vm.run("ssh client")
	check(int(parsed(final_vm,"edr quarantine pc_a pc_a-office").get("code",0)) == 403,"trusted signed file cannot be quarantined")
	parsed(final_vm,"edr collect")
	parsed(final_vm,"edr quarantine pc_a pc_a-sync")
	parsed(final_vm,"edr scan pc_a")
	check(not final_vm.evaluate().all(func(value):return value),"both endpoints need current scan")
	parsed(final_vm,"edr scan pc_b")
	check(final_vm.evaluate().all(func(value):return value),"catalog recovery case satisfies actual three conditions")
	var reloaded = preload("res://scripts/virtual_machine.gd").new()
	reloaded.setup(4,JSON.parse_string(JSON.stringify(final_vm.export_state())),final_case)
	check(reloaded.evaluate().all(func(value):return value),"JSON save reload preserves current clean fingerprints")
	parsed(reloaded,"edr isolate pc_a")
	check(not bool(parsed(reloaded,"edr status pc_a").get("ready",true)),"clean isolated endpoint is not ready for business")
	parsed(reloaded,"edr release pc_a")
	parsed(reloaded,"edr quarantine pc_a pc_a-backup")
	parsed(reloaded,"edr scan pc_a")
	check(not bool(parsed(reloaded,"edr status pc_a").get("ready",true)),"clean scan cannot hide missing business application")

	if failures.is_empty():
		print("ENDPOINT_REMEDIATION_TEST_PASS")
	else:
		for failure in failures: push_error("ENDPOINT_REMEDIATION: " + failure)
		print("ENDPOINT_REMEDIATION_TEST_FAIL failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
