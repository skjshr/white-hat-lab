extends SceneTree

## Engine-only projection coverage. The accepted branch is a labeled synthetic
## fixture; VM changes and measurements below use normal Game command APIs.
const GameScript = preload("res://scripts/game.gd")
const VmScript = preload("res://scripts/virtual_machine.gd")
var failures: Array[String] = []
var assertions := 0
var path_root := ""
var game

func _init() -> void:
	path_root = "user://qa-branch-monitor-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path_root))
	game = GameScript.new(); root.add_child(game); _set_paths(game)
	check(game.new_game(), "create isolated player save for synthetic monitor case")
	_install_empty_branch_fixture(game)
	_test_uninitialized_projection()
	if failures.is_empty(): await _test_real_branch_snapshots()
	_test_nonbranch_gate()
	for failure in failures: push_error(failure)
	print("BRANCH_MONITOR_SNAPSHOT_PASS assertions=" + str(assertions) if failures.is_empty() else "BRANCH_MONITOR_SNAPSHOT_FAIL count=" + str(failures.size()) + " assertions=" + str(assertions))
	quit(0 if failures.is_empty() else 1)

func _set_paths(target) -> void:
	target.save_path = path_root + "/player.json"
	target.backup_path = path_root + "/player.json.bak"
	target.previous_path = path_root + "/player.json.previous"
	target.settings_path = path_root + "/settings.json"

func _install_empty_branch_fixture(target) -> void:
	# Synthetic contract identity and target list only. No money, skill,
	# measurements, VM snapshot, or result is injected.
	target.state.accepted = true
	target.state.awaiting_contract = false
	target.state.career_mode = false
	target.state.current_contract_id = ""
	target.state.contract = {"case_id":"composite-branch-reopen","client":"Synthetic branch monitor fixture","title":"Synthetic branch monitor"}
	target.state.chapter = 0
	target.state.target_index = 0
	target.state.targets = [
		{"chapter":0,"case_id":"service-0-case-0","name":"Branch file server","config":{},"revision":0,"checks":[]},
		{"chapter":2,"case_id":"service-2-case-0","name":"Branch gateway","config":{},"revision":0,"checks":[]},
		{"chapter":5,"case_id":"service-5-case-0","name":"Partner portal","config":{},"revision":0,"checks":[]}
	]
	target.state.vm_states = {}
	target.state.completed_ids = []
	target._machine = null; target._machine_key = ""

func _test_uninitialized_projection() -> void:
	var before: Dictionary = game.state.duplicate(true)
	var clock: String = game.business_clock()
	var cash := int(game.state.cash)
	var output: Dictionary = game.branch_monitor_snapshot()
	check(bool(output.available) and str(output.case_id) == "composite-branch-reopen" and str(output.client) == "Synthetic branch monitor fixture", "branch aggregation is scoped to accepted branch contract")
	check(output.services.size() == 3 and int(output.current_target) == 0, "three real configured target slots are projected")
	check(output.services.all(func(item): return not bool(item.snapshot.initialized) and not bool(item.snapshot.connected) and item.snapshot.active == null and item.snapshot.probes.is_empty()), "missing schema-2 VMs remain uninitialized and unknown")
	check(output.services[0].current and not output.services[1].current and str(output.services[1].name) == "Branch gateway" and int(output.services[1].chapter) == 2, "service metadata retains index, name, chapter and selected target")
	check(game._machine == null and game._machine_key.is_empty() and game.state == before and game.business_clock() == clock and int(game.state.cash) == cash, "branch rendering does not initialize, switch, measure, charge, or edit Game state")
	var empty_service: Dictionary = game.service_monitor_snapshot(2)
	check(int(empty_service.index) == 2 and not bool(empty_service.current) and str(empty_service.service) == VmScript.SERVICES[5], "arbitrary-target API reads requested target while selection remains on source")
	check(game.state.target_index == 0 and game._machine == null, "arbitrary-target read leaves selected target and VM identity unchanged")

func _test_real_branch_snapshots() -> void:
	# Production contract setup materializes the actual chapter-0 provider and
	# writes only its schema-2 snapshot; this remains synthetic progression.
	game._prepare_linked_business_contract()
	check(game.state.vm_states.has(game._vm_key(0)) and not game.state.vm_states.has(game._vm_key(1)), "branch preparation persists only the real source VM initially")
	var source_ssh: String = game.vm_run("ssh client")
	if not source_ssh.contains("Authenticated"): print("DEBUG source ssh=",source_ssh," accepted=",game.state.accepted," current_done=",game.current_done()," chapter=",game._current_chapter()," key=",game._vm_key())
	check(source_ssh.contains("Authenticated"), "connect source with the normal guest command")
	var samba_cfg: String = game._vm().configuration_text({"staff":"write","guest":"none"})
	check(game.vm_write(str(game.vm_info().config_path), samba_cfg), "stage real source share policy")
	check(game.vm_run("systemctl restart samba").contains("active"), "apply source share policy through guest command")
	game.state.target_index = 1
	check(int(game.state.target_index) == 1, "select actual branch gateway target in synthetic fixture")
	var gateway_ssh: String = game.vm_run("ssh client")
	if not gateway_ssh.contains("Authenticated"): print("DEBUG gateway ssh=",gateway_ssh," accepted=",game.state.accepted," current_done=",game.current_done()," chapter=",game._current_chapter()," key=",game._vm_key())
	check(gateway_ssh.contains("Authenticated"), "connect gateway through normal guest command")
	var firewall_cfg: String = game._vm().configuration_text({"dns":"on","business":"allow","admin_public":"deny","tls":"on"})
	check(game.vm_write(str(game.vm_info().config_path), firewall_cfg), "stage actual linked business gateway policy")
	var firewall_restart: String = game.vm_run("systemctl restart firewall")
	if not firewall_restart.contains("active"): print("DEBUG restart=",firewall_restart," applied=",game._vm().state.get("applied",{}))
	check(firewall_restart.contains("active"), "apply linked business gateway policy")
	var actual_probe: String = game.run_diagnostic("branch-business-orders")
	check(actual_probe.contains("200") and actual_probe.contains(VmScript.RECORDS["orders.csv"].sha256_text()), "record linked-order API measurement from real branch file bytes")
	var live_consumer = game._machine
	var live_key: String = game._machine_key
	var state_before_projection: Dictionary = game.state.duplicate(true)
	var vm_before_projection: Dictionary = live_consumer.export_state()
	var clock_before_projection: String = game.business_clock()
	var cash_before_projection := int(game.state.cash)
	var first_projection: Dictionary = game.branch_monitor_snapshot()
	check(first_projection.services.size() == 3 and int(first_projection.current_target) == 1, "branch snapshot returns all three actual targets with gateway selected")
	var consumer: Dictionary = _service(first_projection, 1)
	var consumer_probe := _probe(consumer.snapshot, "branch-business-orders")
	check(consumer.current and bool(consumer_probe.recorded) and bool(consumer_probe.fresh) and bool(consumer_probe.passed), "gateway snapshot retains its own fresh passing order probe while another service is shown")
	var source: Dictionary = _service(first_projection, 0)
	check(not source.current and bool(source.snapshot.initialized) and bool(source.snapshot.guest_state.fs.has("/srv/share/partner-order.csv")), "nonselected source snapshot exposes actual share file")
	check(game.state == state_before_projection and live_consumer == game._machine and live_consumer.export_state() == vm_before_projection and game._machine_key == live_key and game.business_clock() == clock_before_projection and int(game.state.cash) == cash_before_projection, "branch aggregation is read-only across Game, all guest state, selection, work and funds")
	var arbitrary_gateway: Dictionary = game.service_monitor_snapshot(1)
	check(bool(arbitrary_gateway.current) and int(arbitrary_gateway.index) == 1 and game.state.target_index == 1 and game._machine == live_consumer, "requested current-target projection preserves live VM and target")
	game.state.target_index = 0
	check(int(game.state.target_index) == 0, "switch to source to change its actual shared file")
	var source_resume: String = game.vm_run("ssh client")
	if not source_resume.contains("Authenticated"): print("DEBUG source resume=",source_resume," accepted=",game.state.accepted," chapter=",game._current_chapter()," key=",game._vm_key())
	check(source_resume.contains("Authenticated"), "resume source target before edit")
	var changed_orders := "order,customer,total\n501,101,12900\n"
	check(game.vm_write("/srv/share/partner-order.csv", changed_orders), "change source through actual share write API")
	game.state.target_index = 1
	check(int(game.state.target_index) == 1, "return to gateway without running another order diagnostic")
	var after_source_change: Dictionary = game.branch_monitor_snapshot()
	var stale_probe := _probe(_service(after_source_change, 1).snapshot, "branch-business-orders")
	check(bool(stale_probe.recorded) and not bool(stale_probe.fresh) and str(stale_probe.freshness) == "stale" and not bool(stale_probe.passed), "live provider file change stales the consumer measurement in the cross-service view")
	check(game.save_game(), "persist source and consumer VM snapshots")
	var resumed = GameScript.new(); root.add_child(resumed); _set_paths(resumed)
	check(resumed.load_game(), "reload branch monitoring state in a new Game")
	var resume_state: Dictionary = resumed.state.duplicate(true)
	var resumed_clock := resumed.business_clock()
	var resumed_view: Dictionary = resumed.branch_monitor_snapshot()
	var resumed_probe := _probe(_service(resumed_view, 1).snapshot, "branch-business-orders")
	check(resumed._machine == null and resumed._machine_key.is_empty(), "new Game does not materialize any VM to render branch overview")
	var resumed_source := _service(resumed_view, 0)
	check(not resumed_source.is_empty() and str(resumed_source.get("snapshot", {}).get("guest_state", {}).get("fs", {}).get("/srv/share/partner-order.csv", "")) == changed_orders and bool(resumed_probe.get("recorded", false)) and not bool(resumed_probe.get("fresh", true)), "reload retains changed provider file and stale consumer measurement")
	check(resumed.state == resume_state and resumed.business_clock() == resumed_clock and resumed._machine == null and resumed._machine_key.is_empty(), "saved-only branch view is pure after resume")
	check(_service(resumed_view, 2).snapshot.initialized == false, "unopened portal stays visibly uninitialized after reload")
	resumed.queue_free()

func _test_nonbranch_gate() -> void:
	var previous: Dictionary = game.state.contract.duplicate(true)
	game.state.contract.case_id = "some-other-composite"
	var result: Dictionary = game.branch_monitor_snapshot()
	check(not bool(result.available) and result.services.is_empty(), "non-branch contracts gain no invented branch devices")
	game.state.contract = previous

func _service(snapshot: Dictionary, index: int) -> Dictionary:
	for item in snapshot.get("services", []):
		if int(item.get("index", -1)) == index: return item
	return {}

func _probe(snapshot: Dictionary, id: String) -> Dictionary:
	for item in snapshot.get("probes", []):
		if str(item.get("id", "")) == id: return item
	return {}

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)
		print("FAIL ", label)
