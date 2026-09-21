extends SceneTree

const ADV = preload("res://scripts/advanced_operations.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func _assert(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("FAIL ", label)

func _ok(result: Dictionary, label: String) -> void:
	_assert(bool(result.get("ok", false)), label + " ok")
	_assert(bool(result.get("changed", false)), label + " changed")

func _shape(state: Dictionary, label: String) -> void:
	var rendered := ADV.view(state)
	for key in ["kind","revision","nodes","edges","events","records","actions","checks","last_result"]: _assert(rendered.has(key), label + " view " + key)
	for node in rendered.nodes: _assert(node.has_all(["id","label","detail","status_key","x","y"]), label + " node shape")
	for edge in rendered.edges: _assert(edge.has_all(["from","to","label"]), label + " edge shape")
	for action in rendered.actions: _assert(action.has_all(["id","label_key","target","options"]), label + " action shape")

func _hunt() -> void:
	var state := ADV.create("advanced-hunt")
	_shape(state, "hunt")
	_ok(ADV.act(state,"correlate_gateway"), "hunt gateway")
	_ok(ADV.act(state,"correlate_workstation"), "hunt workstation")
	_ok(ADV.act(state,"correlate_fileserver"), "hunt file server")
	_ok(ADV.act(state,"pin_event",{"target":"evt-05"}), "hunt pin event")
	_ok(ADV.act(state,"pin_event",{"target":"evt-06"}), "hunt pin second event")
	var pin_count: int = state.world.get("pinned", []).size()
	_ok(ADV.act(state,"pin_event",{"target":"evt-06"}), "hunt duplicate pin idempotent")
	_assert(state.world.get("pinned", []).size() == pin_count, "hunt duplicate pin adds no evidence")
	_ok(ADV.act(state,"isolate_host",{"target":"gw01"}), "hunt isolate normal host allowed")
	_ok(ADV.act(state,"probe_business"), "hunt observe business failure")
	_ok(ADV.act(state,"reconnect_host",{"target":"gw01"}), "hunt reconnect normal host")
	_ok(ADV.act(state,"probe_security"), "hunt observe attacker before containment")
	_ok(ADV.act(state,"isolate_host",{"target":"ws17"}), "hunt isolate infected host")
	_ok(ADV.act(state,"revoke_session",{"target":"sid-r44"}), "hunt revoke session")
	_ok(ADV.act(state,"disable_task",{"target":"task-sync"}), "hunt disable persistence")
	_ok(ADV.act(state,"enable_task",{"target":"task-sync"}), "hunt undo mistaken task choice")
	_ok(ADV.act(state,"disable_task",{"target":"task-sync"}), "hunt disable persistence again")
	_ok(ADV.act(state,"probe_security"), "hunt remeasure clean security")
	_ok(ADV.act(state,"probe_security"), "hunt observe clean security")
	_ok(ADV.act(state,"reconnect_host",{"target":"ws17"}), "hunt reconnect infected host")
	_ok(ADV.act(state,"probe_security"), "hunt final security measurement")
	_ok(ADV.act(state,"probe_business"), "hunt observe restored business")
	_assert(ADV.checks(state).all(func(item): return bool(item.get("passed",false))), "hunt checks all pass")
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(state))
	_ok(ADV.act(resumed,"restore_business"), "hunt JSON resume idempotent action")

func _pentest() -> void:
	var state := ADV.create("advanced-pentest")
	_shape(state, "pentest")
	_assert(not bool(ADV.act(state,"connect_target",{"target":"share01"}).get("ok",false)), "pentest needs discovery")
	_ok(ADV.act(state,"discover_assets"), "pentest discovery")
	_ok(ADV.act(state,"inspect_permissions"), "pentest permissions")
	_ok(ADV.act(state,"connect_target",{"target":"share01"}), "pentest share edge")
	_ok(ADV.act(state,"read_credential",{"target":"share01"}), "pentest read inert credential")
	_ok(ADV.act(state,"authenticate_service",{"target":"svc-report"}), "pentest authenticate service")
	_ok(ADV.act(state,"read_proof",{"target":"evidence/proof.csv"}), "pentest proof file")
	_ok(ADV.act(state,"modify_grant",{"target":"share01"}), "pentest remediation")
	_assert(not bool(ADV.act(state,"read_credential",{"target":"share01"}).get("ok",false)), "pentest credential read denied after grant repair")
	_assert(not bool(ADV.act(state,"connect_target",{"target":"share01"}).get("ok",false)), "pentest denied after grant repair")
	_ok(ADV.act(state,"retest_path",{"target":"evidence/proof.csv"}), "pentest retest")
	_assert(ADV.checks(state).all(func(item): return bool(item.get("passed",false))), "pentest checks all pass")

func _recovery() -> void:
	var state := ADV.create("advanced-recovery")
	_shape(state, "recovery")
	_assert(not bool(ADV.act(state,"compare_snapshots",{"target":"missing"}).get("ok",false)), "recovery rejects unknown snapshot")
	_assert(not bool(ADV.act(state,"stage_restore").get("ok",false)), "recovery requires snapshot review")
	_ok(ADV.act(state,"compare_snapshots",{"target":"snap-1410"}), "recovery inspect latest snapshot")
	_ok(ADV.act(state,"stage_restore"), "recovery stage")
	_ok(ADV.act(state,"scan_stage"), "recovery scan")
	_assert(not bool(ADV.act(state,"restore_business").get("ok",false)), "recovery app dependency guard")
	_ok(ADV.act(state,"isolate_network"), "recovery isolate network")
	_assert(not bool(ADV.act(state,"reconnect_business").get("ok",false)), "recovery observes reinfection")
	_ok(ADV.act(state,"compare_snapshots",{"target":"snap-0730"}), "recovery select clean snapshot")
	_ok(ADV.act(state,"stage_restore"), "recovery restage clean")
	_ok(ADV.act(state,"scan_stage"), "recovery rescan")
	_ok(ADV.act(state,"repair_identity"), "recovery identity")
	_ok(ADV.act(state,"remove_persistence"), "recovery persistence")
	_ok(ADV.act(state,"scan_stage"), "recovery rescan after persistence removal")
	_ok(ADV.act(state,"restore_business"), "recovery restore")
	_ok(ADV.act(state,"reconnect_business"), "recovery reconnect")
	_assert(ADV.checks(state).all(func(item): return bool(item.get("passed",false))), "recovery checks all pass")
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(state))
	_assert(ADV.checks(resumed).all(func(item): return bool(item.get("passed",false))), "recovery JSON checks survive")
	var alternate: Dictionary = ADV.create("advanced-recovery")
	var recovery_view: Dictionary = ADV.view(alternate)
	_assert(JSON.stringify(recovery_view.get("records", [])).contains("id,amount"), "recovery view exposes snapshot bytes")
	_ok(ADV.act(alternate,"compare_snapshots",{"target":"snap-1405"}), "recovery alternate snapshot")
	_ok(ADV.act(alternate,"stage_restore"), "recovery alternate stage")
	_ok(ADV.act(alternate,"scan_stage"), "recovery alternate initial scan")
	_ok(ADV.act(alternate,"remove_persistence"), "recovery alternate persistence cleanup")
	_ok(ADV.act(alternate,"scan_stage"), "recovery alternate rescan")
	_ok(ADV.act(alternate,"repair_identity"), "recovery alternate identity")
	_ok(ADV.act(alternate,"isolate_network"), "recovery alternate isolation")
	_ok(ADV.act(alternate,"restore_business"), "recovery alternate business")
	_assert(bool(ADV.checks(alternate)[0].get("passed",false)), "recovery alternate accepted without fixed snapshot id")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	_assert("--qa-profile=advanced-core" in args, "advanced QA profile guard")
	if not failures.is_empty():
		_finish(); return
	await _hunt(); await _pentest(); await _recovery()
	_finish()

func _finish() -> void:
	if failures.is_empty(): print("ADVANCED_OPERATIONS_PASS")
	else:
		for failure in failures: push_error("ADVANCED_OPERATIONS: " + failure)
		print("ADVANCED_OPERATIONS_FAIL count=", failures.size())
	quit(0 if failures.is_empty() else 1)
