extends SceneTree
## Semantic boundaries: real VM responses plus explicitly malformed evidence.
const BOARD = preload("res://scripts/samba_access_board.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")
var failures: Array[String] = []
var assertions := 0

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ", label)
func item(probes: Array, id: String) -> Dictionary:
	for p in BOARD.project(probes):
		if str(p.id) == id: return p
	return {}
func fixture(id: String, output: String, expectation: String, passed := false) -> Array:
	var probes: Array = CATALOG._probes(0, {"staff":"write", "guest":"none"}, {})
	for p in probes:
		if str(p.id) == id: p.merge({"recorded":true, "fresh":true, "result":output, "expectation":expectation, "passed":passed}, true)
	return probes
func run() -> void:
	var game := root.get_node("Game"); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"), "isolated QA save")
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	check(game.new_game() and game.choose_strategy("advisory") and game.accept_mission(), "normal first contract")
	game.vm_run("ssh client")
	var before := JSON.stringify(game.state)
	var unmeasured: Array = game.diagnostic_probes()
	var copy := unmeasured.duplicate(true)
	var projected: Array = BOARD.project(unmeasured)
	check(projected.size() == 4, "four distinct employee and visitor operations")
	for p in projected: check(str(p.status) == "unknown" and p.passed == null, "unmeasured has no success " + str(p.id))
	check(unmeasured == copy and JSON.stringify(game.state) == before, "projection leaves evidence and game untouched")
	game.run_diagnostic("staff-write")
	check(str(item(game.diagnostic_probes(),"staff-write").status) == "denied" and item(game.diagnostic_probes(),"staff-write").passed == false, "real employee write failure is unmet business requirement")
	game.run_diagnostic("guest-read")
	check(str(item(game.diagnostic_probes(),"guest-read").status) == "allowed" and item(game.diagnostic_probes(),"guest-read").passed == false, "real visitor access success is security failure")
	var probes := fixture("guest-read", "NT_STATUS_ACCESS_DENIED", "DENIED", true)
	check(item(probes,"guest-read").passed == true, "actual ACL refusal can satisfy guest requirement")
	for output in ["NT_STATUS_CONNECTION_REFUSED: service is not running", "NT_STATUS_BAD_NETWORK_NAME", "NT_STATUS_LOGON_FAILURE", '{"ok":false,"code":507,"error":"save_failed"}']:
		var result := item(fixture("guest-read",output,"DENIED",true),"guest-read")
		check(str(result.status) in ["error","unknown"] and result.passed == null, "failure cannot masquerade as safe refusal: " + output)
	var empty := item(fixture("staff-read", "0 files", "report.txt", false), "staff-read")
	check(str(empty.status) == "allowed" and empty.passed == false, "empty folder access does not satisfy required report")
	var invented := item(fixture("staff-read", "everything fine", "report.txt", true), "staff-read")
	check(str(invented.status) in ["unknown","error"] and invented.passed == null, "unrecognized response cannot invent successful access")
	var wrong_file := item(fixture("staff-write", "putting file other.txt: OK", "OK", true), "staff-write")
	check(str(wrong_file.status) == "unknown" and wrong_file.passed == null, "another file cannot satisfy the business transfer")
	var stale := fixture("guest-read", "NT_STATUS_ACCESS_DENIED", "DENIED", true)
	for p in stale:
		if str(p.id) == "guest-read": p.fresh = false
	check(str(item(stale,"guest-read").status) == "stale" and item(stale,"guest-read").passed == null, "old refusal cannot satisfy present contract")
	var wrong_actor := fixture("staff-read", "report.txt", "report.txt", true)
	for p in wrong_actor:
		if str(p.id) == "staff-read": p.command = "smbclient //client/share -U staff-other -c ls"
	check(not bool(item(wrong_actor,"staff-read").recorded), "different identity cannot be labelled employee evidence")
	var wrong_share := fixture("guest-read", "NT_STATUS_ACCESS_DENIED", "DENIED", true)
	for p in wrong_share:
		if str(p.id) == "guest-read": p.command = "smbclient //client/archive -U guest -c ls"
	check(not bool(item(wrong_share,"guest-read").recorded), "other share cannot become selected-folder evidence")
	print("SHARE_PROJECTION assertions=",assertions," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
