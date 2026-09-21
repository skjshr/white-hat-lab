extends SceneTree

var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _init() -> void:
	var vm = preload("res://scripts/virtual_machine.gd").new()
	vm.setup(4, {}, {})
	check(int(vm.state.get("edr_model_version", 1)) == 2, "fresh v2")
	check(int(vm.edr_snapshot().get("code", 0)) == 401, "snapshot requires ssh")
	check(str(vm.run("ssh client")).contains("Authenticated"), "ssh")
	var devices: Dictionary = JSON.parse_string(vm.run("edr devices"))
	check(bool(devices.get("ok", false)) and devices.get("devices", []).size() == 2, "devices")
	var timeline: Dictionary = JSON.parse_string(vm.run("edr timeline pc_a"))
	check(bool(timeline.get("ok", false)) and timeline.get("events", []).size() >= 2, "timeline")
	check(str(vm.run("curl https://edr.client.test/pc-a/outbound")).begins_with("HTTP/1.1 200"), "outbound before isolate")
	var isolated: Dictionary = JSON.parse_string(vm.run("edr isolate pc_a"))
	check(bool(isolated.get("ok", false)) and bool(isolated.get("isolated", false)), "isolate")
	check(str(vm.run("curl https://edr.client.test/pc-a/outbound")).begins_with("HTTP/1.1 403"), "outbound after isolate")
	var collected: Dictionary = JSON.parse_string(vm.run("edr collect"))
	check(bool(collected.get("ok", false)) and bool(collected.get("evidence", {}).get("valid", false)), "collect")
	var evaluated: Array = vm.evaluate()
	check(evaluated.size() == 3 and evaluated.all(func(item): return bool(item)), "evaluate")
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--legacy-fixture="): continue
		var saved=JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--legacy-fixture=")))
		check(saved is Dictionary and not saved.has("edr_model_version"),"authentic pre-v2 fixture")
		if saved is Dictionary:
			var legacy=preload("res://scripts/virtual_machine.gd").new();legacy.setup(4,saved)
			check(int(legacy.state.get("edr_model_version",1))==1,"loaded legacy remains v1")
			check(legacy.evaluate().all(func(item):return bool(item)),"legacy completed work remains valid")
			check(legacy.probes().all(func(item):return bool(item.passed) and bool(item.fresh)),"legacy observations retain validity")
			check(not bool(JSON.parse_string(legacy.run("edr devices")).ok),"new API does not silently migrate legacy")
			check(legacy.run("curl https://edr.client.test/pc-b/business").contains("business session healthy"),"legacy business behavior preserved")
	if failures.is_empty(): print("EDR_V2 PASS")
	else:
		for failure in failures: print("FAIL: ", failure)
		quit(1)
	quit(0)
