extends SceneTree

const FILE := "/srv/share/partner-order.csv"
const ORIGINAL := "order,customer,total\n501,101,12800\n"
const UPDATED := "order,customer,total\n501,101,43210\n"

var failures: Array[String] = []
var game: Node
var qa_id := str(OS.get_process_id())

func _init() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("branch workflow timeout"); quit(2))
	call_deferred("run")

func _assert(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func _target(chapter: int) -> int:
	for i in game.state.targets.size():
		if int(game.state.targets[i].get("chapter", -1)) == chapter: return i
	return -1

func _connect(index: int) -> bool:
	var selected := bool(game.select_target(index))
	_assert(selected, "select target %d" % index)
	if not selected: return false
	var response := str(game.vm_run("ssh client"))
	var connected := bool(game.vm_info().get("connected", false))
	_assert(connected, "ssh target %d: %s" % [index, response])
	return connected

func _find_offer() -> Dictionary:
	for day in 60:
		game.state.day = day + 1
		game._make_offers()
		for item in game.state.offers:
			if str(item.get("case_id", "")) == "composite-branch-reopen" and bool(item.get("market_available", false)):
				return item
	return {}

func _configure(index: int, values: Dictionary, service: String) -> bool:
	if not _connect(index): return false
	var config := str(game._vm().configuration_text(values))
	var path := str(game.vm_info().get("config_path", ""))
	_assert(game.vm_write(path, config), "stage %s configuration" % service)
	var restarted := str(game.vm_run("systemctl restart %s" % service))
	_assert(restarted.contains("active"), "restart %s" % service)
	return true

func _measure(index: int) -> void:
	if not _connect(index): return
	var settled := false
	for _round in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
				var output := str(game.run_diagnostic(str(probe.get("id", ""))))
				_assert(not output.is_empty(), "probe output %s" % str(probe.get("id", "")))
		var checks: Array = game.verify()
		settled = not checks.is_empty() and checks.all(func(item): return bool(item is Dictionary and item.get("passed", false)))
		if settled: break
	_assert(settled, "verification passes target %d" % index)

func _source_read() -> String:
	if not _connect(_target(0)): return ""
	return str(game.vm_read(FILE))

func _portal_read() -> String:
	return str(game._vm().portal_storage_read(FILE)) if game._vm().has_method("portal_storage_read") else ""

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.save_path = "user://qa-branch-workflow-%s.json" % qa_id
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	if not game.save_path.begins_with("user://qa-"):
		push_error("refusing non-QA save path"); quit(2); return
	game._reset_state()
	_assert(game.choose_strategy("advisory") and game.start_free_career(), "career starts")
	game.state.skills.advisory = 3
	game.state.skills.operations = 3
	game.state.skills.response = 3
	game.state.profit = 200000
	game.state.peak_profit = 200000
	game._update_growth()

	var offer := _find_offer()
	_assert(not offer.is_empty(), "branch offer available through market")
	if offer.is_empty(): quit(1); return
	var offer_id := str(offer.get("id", ""))
	_assert(game.set_offer_quote(offer_id, int(offer.get("reward", offer.get("base_reward", 0)))) and game.choose_contract(offer_id), "branch accepted through public API")
	_assert(int(game.state.contract.get("linked_branch_version", 0)) == 1, "branch linkage prepared")
	var gateway := _target(2)
	var samba := _target(0)
	var portal := _target(5)
	_assert(gateway >= 0 and samba >= 0 and portal >= 0, "branch has gateway, share and portal targets")
	if gateway < 0 or samba < 0 or portal < 0: quit(1); return

	_configure(gateway, {"dns":"on", "business":"allow", "admin_public":"deny", "tls":"on"}, "firewall")
	var outage := str(game.vm_run("curl https://intranet.client.test/api/business/orders"))
	_assert(outage.contains("503") or outage.contains("403"), "gateway reports source outage without stale fallback")

	_configure(samba, {"staff":"write", "guest":"none"}, "samba")
	_assert(game.vm_read("/srv/share/customers.csv") != "" and game.vm_read(FILE) == ORIGINAL, "canonical source files and order 501 exist")
	var source_before: Dictionary = game._vm().export_state()
	_assert(str(source_before.fs.get(FILE, "")) == ORIGINAL, "source order is original")

	_configure(portal, {"staff":"write", "partner":"read", "public":"none", "expires":"7d", "mfa":"on", "tls":"on", "audit":"on"}, "portal")
	var partner_read := str(game.portal_request("partner", "GET", "current", "partner-mfa-session"))
	_assert(partner_read.contains("200") and partner_read.contains("12800"), "partner MFA read sees shared source")
	_assert(str(game.portal_request("partner", "PUT", "current", "partner-mfa-session", UPDATED)).contains("403"), "partner read cannot write")
	_assert(str(game.portal_request("partner", "GET", "month-old", "partner-mfa-session")).contains("410"), "expired partner link is denied")
	_assert(str(game.portal_request("public", "GET", "current", "partner-mfa-session")).contains("403"), "public share remains denied")
	_configure(samba, {"staff":"read", "guest":"none"}, "samba")
	_assert(_connect(portal), "portal with read-only SMB mount")
	_assert(str(game.portal_request("staff", "GET", "current", "staff-session")).contains("12800"), "SMB read-only mount still serves reads")
	var read_only_put := str(game.portal_request("staff", "PUT", "current", "staff-session", UPDATED))
	_assert(read_only_put.contains("403") and read_only_put.contains("storage_denied"), "SMB read-only mode blocks an otherwise authorized portal write")
	_configure(samba, {"staff":"write", "guest":"none"}, "samba")
	game.vm_run("exit")
	_assert(not bool(game.vm_info().connected), "operator disconnects SSH")
	_assert(_connect(portal) and str(game.portal_request("staff", "GET", "current", "staff-session")).contains("12800"), "Samba service remains usable after SSH disconnect")
	var direct_put := str(game.portal_request("staff", "PUT", "current", "staff-session", UPDATED))
	_assert(direct_put.contains("200"), "staff portal PUT succeeds")
	_assert(_source_read() == UPDATED, "portal PUT changes canonical Samba source")
	_assert(_connect(portal), "return to portal for curl PUT")
	var curl_payload := "order,customer,total\n501,101,44550\n"
	var curl_command := "curl -X PUT -H 'Authorization: Bearer staff-session' --data-raw '" + curl_payload + "' https://portal.client.test/staff?link=current"
	var curl_put := str(game.vm_run(curl_command))
	_assert(curl_put.contains("200") and _portal_read().contains("44550"), "staff curl PUT changes canonical Samba source")
	_assert(_connect(gateway) and str(game.vm_run("curl https://intranet.client.test/api/business/orders")).contains("44550"), "gateway reads changed canonical source")

	_assert(_connect(portal), "return to portal for malformed-source test")
	_assert(str(game.portal_request("staff", "PUT", "current", "staff-session", "malformed bytes\n")).contains("200"), "arbitrary source bytes are accepted")
	_assert(_connect(gateway) and str(game.vm_run("curl https://intranet.client.test/api/business/orders")).contains("422"), "malformed source is surfaced as 422")
	_assert(_connect(portal) and _portal_read().contains("malformed bytes"), "portal reads malformed source bytes")
	_assert(_connect(samba) and game.vm_run("rm %s" % FILE).is_empty(), "source order can be removed")
	_assert(_connect(gateway) and str(game.vm_run("curl https://intranet.client.test/api/business/orders")).contains("404"), "missing source is 404 without local fallback")

	_assert(_connect(samba) and game.vm_write(FILE, ORIGINAL), "restore canonical source bytes")
	var source_snapshot: Dictionary = game._vm().export_state()
	_assert(_connect(portal), "return to portal for rollback")
	var state_snapshot: String = JSON.stringify(game.state)
	var real_save: String = str(game.save_path)
	game.save_path = "user://qa-branch-save-failure-%s/missing/save.json" % qa_id
	var failed_put := str(game.portal_request("staff", "PUT", "current", "staff-session", UPDATED))
	game.save_path = real_save
	_assert(failed_put.contains("507") or failed_put.contains("save_failed"), "portal PUT save failure surfaced")
	_assert(JSON.stringify(game.state) == state_snapshot, "portal save failure restores state and source context")
	_assert(_source_read() == ORIGINAL, "portal save failure restores canonical source")
	_assert(_connect(portal), "return to portal for curl rollback")
	var curl_state_snapshot: String = JSON.stringify(game.state)
	var curl_real_save: String = str(game.save_path)
	game.save_path = "user://qa-branch-curl-failure-%s/missing/save.json" % qa_id
	var failed_curl := str(game.vm_run("curl -X PUT -H 'Authorization: Bearer staff-session' --data-raw 'order,customer,total\\n501,101,44550\\n' https://portal.client.test/staff?link=current"))
	game.save_path = curl_real_save
	_assert(failed_curl.contains("507") or failed_curl.contains("save_failed"), "curl PUT save failure surfaced")
	_assert(JSON.stringify(game.state) == curl_state_snapshot and _source_read() == ORIGINAL, "curl PUT save failure restores both VMs")

	_assert(_connect(portal) and str(game.portal_request("partner", "GET", "current", "partner-mfa-session")).contains("12800"), "partner read restored")
	_measure(gateway); _measure(samba); _measure(portal)
	_assert(game.can_deliver(), "all branch targets deliverable after source repair")
	_assert(_connect(portal) and str(game.portal_request("staff", "PUT", "current", "staff-session", UPDATED)).contains("200"), "shared source mutation accepted after measurement")
	_assert(not game.can_deliver(), "shared source mutation invalidates prior evidence")
	_assert(str(game.portal_request("staff", "PUT", "current", "staff-session", ORIGINAL)).contains("200"), "shared source restored after stale evidence")
	_measure(gateway); _measure(samba); _measure(portal)
	_assert(game.can_deliver(), "remeasurement restores delivery eligibility")
	var maintenance_targets: Array = game._capture_maintenance_targets("branch-workflow")
	var maintenance_result: Dictionary = game._run_maintenance_job({"targets":maintenance_targets})
	_assert(bool(maintenance_result.get("passed", false)), "maintenance rechecks shared source")
	var broken_maintenance: Array = maintenance_targets.duplicate(true)
	for item in broken_maintenance:
		if int(item.get("chapter", -1)) == 0: item.vm_state.active = false
	_assert(not bool(game._run_maintenance_job({"targets":broken_maintenance}).get("passed", true)), "maintenance fails when shared storage is stopped")
	_assert(game.save_game() and game.load_game(), "branch saves and reloads")
	_assert(game.can_deliver() and game.deliver(), "verified branch is actually delivered after disk reload")

	if failures.is_empty(): print("BRANCH_WORKFLOW_TEST_PASS")
	else: print("BRANCH_WORKFLOW_TEST_FAIL count=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)
