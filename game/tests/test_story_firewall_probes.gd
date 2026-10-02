extends SceneTree

const VM = preload("res://scripts/virtual_machine.gd")
var failures: Array[String] = []
var assertions := 0

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ", label)

func admin_probe(vm) -> Dictionary:
	for probe in vm.probes():
		if str(probe.id) == "admin-check": return probe
	return {}

func configure(vm, desired: Dictionary) -> void:
	check(vm.run("ssh client").contains("Authenticated"), "connect actual firewall")
	check(vm.write_file(str(vm.state.config_path), vm.configuration_text(desired)), "write actual rule configuration")
	check(not vm.run("systemctl restart firewall").begins_with("Job failed"), "apply actual rules")

func _init() -> void:
	var desired := {"dns":"on","business":"allow","admin_public":"deny","tls":"on"}
	var story = VM.new()
	story.setup(2)
	check(story.state.scenario.is_empty(), "story has no scenario desired override")
	check(str(admin_probe(story).get("expectation", "")) == "FIREWALL_DENIED", "story keeps its legacy deny requirement")
	configure(story, desired)
	check(story.run("curl https://admin.client.test:8443").contains("FIREWALL_DENIED"), "story rejects external administration")
	check(story.run("curl https://intranet.client.test").begins_with("HTTP/1.1 200"), "story retains normal business HTTP response")
	for probe in story.probes(): story.execute_probe(str(probe.id))
	check(story.probes().all(func(probe): return bool(probe.passed) and bool(probe.fresh)), "story real probes pass together")
	check(story.evaluate().all(func(passed): return bool(passed)), "story final evaluation agrees with requests")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(story.export_state()))
	# Simulate a save made before the normalization fix. A previous observation
	# must not count as fresh when its expected response changes on reopen.
	for probe in saved.probes:
		if str(probe.id) == "admin-check":
			probe.expectation = "status:200|Management console"
			probe.recorded = true; probe.passed = true; probe.fresh = true
	var reopened = VM.new()
	reopened.setup(2, saved)
	check(str(admin_probe(reopened).expectation) == "FIREWALL_DENIED" and not bool(admin_probe(reopened).get("recorded", false)), "reopen corrects obsolete expectation and invalidates measurement")
	reopened.execute_probe("admin-check")
	check(bool(admin_probe(reopened).passed), "reopened story remeasures actual denial")
	for policy in ["allow", "deny"]:
		var target := desired.duplicate(true)
		target.admin_public = policy
		var scenario := {"initial":target.duplicate(true),"desired":target.duplicate(true),"probes":[{"id":"admin-check","label":"Management access","command":"curl https://admin.client.test","expectation":"legacy"}]}
		var custom = VM.new()
		custom.setup(2, {}, scenario)
		configure(custom, target)
		var raw: String = custom.execute_probe("admin-check")
		check(raw.begins_with("HTTP/1.1 200") if policy == "allow" else raw.contains("FIREWALL_DENIED"), "explicit "+policy+" scenario observes required response")
		check(bool(admin_probe(custom).passed), "explicit "+policy+" scenario keeps its own contract")
	print("STORY_FIREWALL_PROBES_PASS assertions="+str(assertions) if failures.is_empty() else "STORY_FIREWALL_PROBES_FAIL count="+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
