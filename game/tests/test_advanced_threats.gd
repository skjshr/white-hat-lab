extends SceneTree

const AdvancedThreats = preload("res://scripts/advanced_threats.gd")

var failures: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_cloud()
	_test_malware()
	_test_detection()
	if failures.is_empty():
		print("advanced-threats: PASS")
		quit(0)
	else:
		for item in failures: push_error(str(item))
		quit(1)

func _check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)

func _all_passed(items: Array) -> bool:
	if items.is_empty(): return false
	for item in items:
		if not bool(item.get("passed", false)): return false
	return true

func _round_trip(state: Dictionary, label: String) -> Dictionary:
	var encoded := JSON.stringify(state)
	var decoded = JSON.parse_string(encoded)
	_check(decoded is Dictionary, label + " json")
	return decoded if decoded is Dictionary else {}

func _test_cloud() -> void:
	var wrong := AdvancedThreats.create("advanced-cloud")
	var bad := AdvancedThreats.act(wrong, "disable_grant", {"target":"app-19"})
	AdvancedThreats.act(wrong, "one_probe", {"target":"app-19"})
	_check(bool(bad.get("ok", false)), "cloud wrong action rejected")
	_check(not _all_passed(AdvancedThreats.checks(wrong)), "cloud wrong remediation passed")

	var s := AdvancedThreats.create("advanced-cloud")
	AdvancedThreats.act(s, "password_reset", {"target":"user-7"})
	AdvancedThreats.act(s, "probe_request", {"target":"app-72"})
	_check(bool(s.requests[-1].get("allowed",false)), "cloud password reset incorrectly blocked app")
	AdvancedThreats.act(s, "probe_request", {"target":"app-19"})
	AdvancedThreats.act(s, "pin", {"target":"audit-2"})
	AdvancedThreats.act(s, "disable_grant", {"target":"app-72"})
	AdvancedThreats.act(s, "revoke_app_session", {"target":"app-72"})
	AdvancedThreats.act(s, "probe_request", {"target":"app-72"})
	AdvancedThreats.act(s, "probe_request", {"target":"app-19"})
	var verified := AdvancedThreats.act(s, "verify")
	_check(bool(verified.get("ok", false)), "cloud verify")
	_check(_all_passed(AdvancedThreats.checks(s)), "cloud legitimate or malicious checks")
	var resumed := _round_trip(s, "cloud")
	_check(int(resumed.get("revision", -1)) == int(s.get("revision", -2)), "cloud revision resume")
	AdvancedThreats.act(s, "disable_grant", {"target":"app-19"})
	var stale_cloud := AdvancedThreats.act(s, "verify")
	_check(not bool(stale_cloud.get("ok",true)), "cloud stale request verified after mutation")

func _test_malware() -> void:
	var s := AdvancedThreats.create("advanced-malware")
	var wrong := AdvancedThreats.act(s, "quarantine", {"target":"endpoint-a"})
	_check(not bool(wrong.get("ok", true)), "malware premature quarantine")
	AdvancedThreats.act(s, "run_scan")
	AdvancedThreats.act(s, "compare_normal")
	AdvancedThreats.act(s, "set_network", {"option":"on"})
	AdvancedThreats.act(s, "run_live_probe")
	var network_observation: Dictionary = s.observations[-1].duplicate(true)
	AdvancedThreats.act(s, "set_network", {"option":"off"})
	AdvancedThreats.act(s, "run_live_probe")
	_check(bool(network_observation.get("network",false)) and not bool(s.observations[-1].get("network",true)), "malware sandbox network had no behavioral effect")
	AdvancedThreats.act(s, "derive_indicators")
	AdvancedThreats.act(s, "hunt_indicators")
	AdvancedThreats.act(s, "quarantine")
	AdvancedThreats.act(s, "quarantine_file", {"target":"endpoint-a"})
	AdvancedThreats.act(s, "quarantine_persistence")
	var done := AdvancedThreats.act(s, "rescan")
	_check(bool(done.get("ok", false)), "malware rescan")
	_check(bool(s.get("normal_admin_ok", false)), "malware normal admin preserved")
	_check(_all_passed(AdvancedThreats.checks(s)), "malware checks")
	var normal := AdvancedThreats.create("advanced-malware")
	AdvancedThreats.act(normal, "run_scan")
	AdvancedThreats.act(normal, "execute_sandbox")
	AdvancedThreats.act(normal, "derive_indicators")
	AdvancedThreats.act(normal, "quarantine", {"target":"endpoint-b"})
	AdvancedThreats.act(normal, "quarantine_persistence")
	var broken := AdvancedThreats.act(normal, "rescan")
	_check(not bool(broken.get("ok",true)) and not bool(normal.get("normal_admin_ok",true)), "malware normal admin quarantine did not break business")
	AdvancedThreats.act(normal, "restore_quarantine", {"target":"endpoint-b"})
	_check(bool(normal.endpoints[1].business_ok) and not normal.endpoints[1].processes.is_empty(), "malware restore did not recover business")
	var resumed := _round_trip(s, "malware")
	_check(_all_passed(AdvancedThreats.checks(resumed)), "malware json checks")
	AdvancedThreats.act(resumed, "set_profile", {"option":"restricted"})
	_check(not _all_passed(AdvancedThreats.checks(resumed)), "malware stale result accepted")

func _test_detection() -> void:
	var s := AdvancedThreats.create("advanced-detection")
	AdvancedThreats.act(s, "set_source", {"option":"endpoint", "enabled":false})
	var failed := AdvancedThreats.act(s, "replay")
	_check(not bool(failed.get("ok", true)), "detection disabled source replay")
	_check(not s.get("raw_events", []).is_empty(), "detection raw events preserved")
	AdvancedThreats.act(s, "set_source", {"option":"endpoint", "enabled":true})
	AdvancedThreats.act(s, "set_source", {"option":"network", "enabled":true})
	AdvancedThreats.act(s, "set_exclusion", {"option":"invoice_update.exe"})
	var broad := AdvancedThreats.act(s, "replay")
	_check(not bool(broad.get("ok", true)), "detection broad exclusion replay")
	AdvancedThreats.act(s, "set_exclusion", {"option":""})
	AdvancedThreats.act(s, "set_process", {"option":"invoice_update.exe"})
	AdvancedThreats.act(s, "set_threshold", {"value":2})
	AdvancedThreats.act(s, "set_notification", {"option":"on"})
	var replay := AdvancedThreats.act(s, "replay")
	_check(bool(replay.get("ok", false)), "detection corrected replay")
	AdvancedThreats.act(s, "verify")
	_check(_all_passed(AdvancedThreats.checks(s)), "detection checks")
	var resumed := _round_trip(s, "detection")
	_check(_all_passed(AdvancedThreats.checks(resumed)), "detection json checks")
	AdvancedThreats.act(resumed, "set_notification", {"option":"off"})
	_check(not _all_passed(AdvancedThreats.checks(resumed)), "detection stale notification accepted")
	AdvancedThreats.act(s, "set_process", {"option":"admin_tool.exe"})
	var stale_detection := AdvancedThreats.act(s, "verify")
	_check(not bool(stale_detection.get("ok",true)), "detection stale replay verified after rule mutation")
