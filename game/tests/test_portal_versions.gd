extends SceneTree

const PATH := "/srv/share/partner-order.csv"
const ORIGINAL := "order,customer,total\n501,101,12800\n"
const UPDATED := "order,customer,total\n501,101,43210\n"
const RESTORED := "order,customer,total\n501,101,77700\n"

var game: Node
var failures: Array[String] = []

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("portal versions timeout"); quit(2))
	call_deferred("run")

func _assert(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func _json(raw: String) -> Dictionary:
	var value: Variant = JSON.parse_string(raw)
	return value if value is Dictionary else {}

func _find_offer() -> Dictionary:
	for day in 60:
		game.state.day = day + 1
		game._make_offers()
		for offer in game.state.offers:
			if str(offer.get("case_id", "")) == "service-5-case-0" and bool(offer.get("market_available", false)):
				return offer
	return {}

func _portal_version(id: String) -> Dictionary:
	return _json(str(game.vm_run("portal version " + id)))

func _branch_offer(branch: Node) -> Dictionary:
	for day in 60:
		branch.state.day = day + 1
		branch._make_offers()
		for offer in branch.state.offers:
			if str(offer.get("case_id", "")) == "composite-branch-reopen" and bool(offer.get("market_available", false)):
				return offer
	return {}

func _branch_connect(branch: Node, index: int) -> bool:
	if index < 0 or not branch.select_target(index): return false
	branch.vm_run("ssh client")
	return bool(branch.vm_info().get("connected", false))

func _branch_configure(branch: Node, index: int, values: Dictionary, service: String) -> bool:
	if not _branch_connect(branch, index): return false
	var config: String = str(branch._vm().configuration_text(values))
	var path: String = str(branch.vm_info().get("config_path", ""))
	if not branch.vm_write(path, config): return false
	return str(branch.vm_run("systemctl restart " + service)).contains("active")

func _branch_boundary() -> void:
	var branch: Node = load("res://scripts/game.gd").new()
	root.add_child(branch)
	await process_frame
	branch.set_process(false)
	branch.save_path = "user://qa-portal-versions-branch-%d.json" % OS.get_process_id()
	branch.backup_path = branch.save_path + ".bak"
	branch.previous_path = branch.save_path + ".previous"
	branch.settings_path = branch.save_path + ".settings"
	branch._reset_state()
	_assert(branch.choose_strategy("advisory") and branch.start_free_career(), "branch career starts")
	branch.state.cash = 1000000
	branch.state.peak_profit = 1000000
	branch.state.skills = {"advisory":10,"operations":10,"response":10}
	var offer: Dictionary = _branch_offer(branch)
	_assert(not offer.is_empty() and branch.choose_contract(str(offer.get("id", ""))), "linked branch contract accepted")
	var samba: int = -1
	var gateway: int = -1
	var portal: int = -1
	for i in branch.state.targets.size():
		var chapter: int = int(branch.state.targets[i].get("chapter", -1))
		if chapter == 0: samba = i
		elif chapter == 2: gateway = i
		elif chapter == 5: portal = i
	_assert(samba >= 0 and gateway >= 0 and portal >= 0, "linked branch has shared targets")
	if samba < 0 or gateway < 0 or portal < 0: return
	_assert(_branch_configure(branch, samba, {"staff":"write", "guest":"none"}, "samba"), "linked source writable")
	_assert(_branch_configure(branch, gateway, {"dns":"on", "business":"allow", "admin_public":"deny", "tls":"on"}, "firewall"), "linked gateway configured")
	_assert(_branch_configure(branch, portal, {"staff":"write", "partner":"read", "public":"none", "expires":"7d", "mfa":"on", "tls":"on", "audit":"on"}, "portal"), "linked portal configured")
	_assert(str(branch.portal_request("staff", "PUT", "current", "staff-session", UPDATED)).contains("200"), "linked portal PUT succeeds")
	var source_read: String = ""
	if _branch_connect(branch, samba): source_read = str(branch.vm_read(PATH))
	_assert(source_read == UPDATED, "linked PUT reaches Samba source")
	_assert(_branch_connect(branch, gateway) and str(branch.vm_run("curl https://intranet.client.test/api/business/orders")).contains("43210"), "linked PUT reaches business consumer")
	_assert(_branch_connect(branch, portal), "linked portal reconnects for restore")
	var branch_versions: Array = branch._vm().portal_snapshot().get("versions", [])
	var branch_version_id: String = str(branch_versions.back().get("id", "")) if not branch_versions.is_empty() else ""
	_assert(not branch_version_id.is_empty(), "linked PUT has restore version")
	_assert(_json(str(branch.vm_run("portal restore " + branch_version_id))).get("ok", false), "linked restore succeeds")
	var restored_branch_versions: Array = branch._vm().portal_snapshot().get("versions", [])
	var replaced_branch_id: String = str(restored_branch_versions[0].get("id", "")) if not restored_branch_versions.is_empty() else ""
	_assert(_branch_connect(branch, samba) and str(branch.vm_read(PATH)) == ORIGINAL, "linked restore reaches Samba source")
	_assert(_branch_connect(branch, gateway) and str(branch.vm_run("curl https://intranet.client.test/api/business/orders")).contains("12800"), "linked restore reaches business consumer")
	_assert(_branch_connect(branch, samba), "linked provider outage target connects")
	var samba_config_path: String = str(branch.vm_info().get("config_path", ""))
	_assert(branch.vm_write(samba_config_path, "[share]\npath = /srv/share\nthis is invalid\n"), "linked provider outage config staged")
	_assert(str(branch.vm_run("systemctl restart samba")).contains("failed"), "linked provider restart fails")
	_assert(not bool(branch._vm().state.get("active", true)), "linked provider is inactive after failed restart")
	_assert(_branch_connect(branch, portal), "linked portal reconnects during outage")
	var outage_portal: String = str(branch.portal_request("staff", "GET", "current", "staff-session"))
	_assert(outage_portal.contains("503") and outage_portal.contains("provider_unavailable"), "provider outage fails portal closed")
	var outage_business: String = str(branch.vm_run("curl https://intranet.client.test/api/business/orders")) if _branch_connect(branch, gateway) else "connect_failed"
	_assert(outage_business.contains("503") and outage_business.contains("provider_unavailable") and not outage_business.contains("12800"), "provider outage fails business consumer closed")
	_assert(_branch_configure(branch, samba, {"staff":"read", "guest":"none"}, "samba"), "linked provider read-only restore")
	_assert(_branch_connect(branch, portal), "linked portal reconnects read-only")
	var readonly_snapshot: Dictionary = branch._vm().portal_snapshot()
	_assert(not bool(readonly_snapshot.get("external_storage", {}).get("writable", true)), "linked read-only provider reports non-writable")
	var readonly_put: String = str(branch.portal_request("staff", "PUT", "current", "staff-session", UPDATED))
	_assert(readonly_put.contains("403") and readonly_put.contains("storage_denied"), "linked read-only provider rejects PUT exactly")
	var readonly_restore: Dictionary = _json(str(branch.vm_run("portal restore " + replaced_branch_id)))
	_assert(not bool(readonly_restore.get("ok", false)) and str(readonly_restore.get("error", "")) == "storage_denied", "linked read-only provider rejects restore exactly")
	var after_readonly: Dictionary = branch._vm().portal_snapshot()
	_assert(after_readonly.get("versions", []) == readonly_snapshot.get("versions", []) and branch._vm().portal_storage_read(PATH) == ORIGINAL, "read-only restore preserves content and history")

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.save_path = "user://qa-portal-versions-%d.json" % OS.get_process_id()
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	game._reset_state()
	_assert(game.choose_strategy("advisory") and game.start_free_career(), "career starts")
	game.state.cash = 1000000
	game.state.peak_profit = 1000000
	game.state.skills = {"advisory":10,"operations":10,"response":10}
	var offer := _find_offer()
	_assert(not offer.is_empty() and game.choose_contract(str(offer.get("id", ""))), "portal contract accepted")
	_assert(not str(game.vm_run("ssh client")).is_empty() and bool(game.vm_info().get("connected", false)), "portal VM connected")
	var original_content: String = game._vm().portal_storage_read(PATH)
	_assert(not original_content.is_empty(), "portal source has actual initial bytes")
	var initial: Dictionary = game._vm().portal_snapshot()
	_assert(int(initial.get("model_version", 1)) >= 2, "v2 portal model")
	var initial_versions: Array = initial.get("versions", []) if initial.get("versions", []) is Array else []
	_assert(initial_versions.is_empty(), "v2 save has no fabricated version history")
	var portal_probe_id: String = ""
	var portal_probe_fingerprint: String = ""
	for probe in game.diagnostic_probes():
		var probe_command: String = str(probe.get("command", ""))
		if probe_command.contains("portal.client.test"):
			portal_probe_id = str(probe.get("id", ""))
			game.run_diagnostic(portal_probe_id)
			break
	if not portal_probe_id.is_empty():
		for probe in game.diagnostic_probes():
			if str(probe.get("id", "")) == portal_probe_id:
				portal_probe_fingerprint = str(probe.get("fingerprint", ""))
				_assert(bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)), "portal verification records fresh observation")
				break
	else:
		_assert(false, "portal verification probe exists")
	var put: String = game.portal_request("staff", "PUT", "current", "staff-session", UPDATED)
	_assert(put.begins_with("HTTP/1.1 200"), "authorized PUT succeeds")
	var after_put: Dictionary = game._vm().portal_snapshot()
	if not portal_probe_id.is_empty():
		for probe in game.diagnostic_probes():
			if str(probe.get("id", "")) == portal_probe_id:
				_assert(not bool(probe.get("fresh", false)) or str(probe.get("fingerprint", "")) != portal_probe_fingerprint, "portal PUT invalidates prior verification")
				break
	var versions: Array = after_put.get("versions", [])
	var activity: Array = after_put.get("activity", [])
	_assert(versions.size() == 1 and activity.size() >= 1, "authorized PUT creates one version and activity")
	var first: Dictionary = versions[versions.size() - 1] if not versions.is_empty() else {}
	var first_id: String = str(first.get("id", ""))
	_assert(not first_id.is_empty() and str(first.get("path", "")) == PATH, "version metadata records path")
	var first_metadata: Dictionary = first
	_assert(str(first_metadata.get("sha256", "")) == original_content.sha256_text() and int(first_metadata.get("size", -1)) == original_content.to_utf8_buffer().size(), "version metadata records exact before bytes")
	var first_content: Dictionary = _portal_version(first_id)
	_assert(bool(first_content.get("ok", false)) and str(first_content.get("version", {}).get("content", "")) == original_content, "version content matches exact before bytes")
	var before_rejected: Dictionary = after_put.duplicate(true)
	_assert(not game.portal_request("partner", "PUT", "current", "partner-session", RESTORED).begins_with("HTTP/1.1 200"), "password-only/restricted PUT denied")
	_assert(not game.portal_request("partner", "GET", "month-old", "partner-mfa-session").begins_with("HTTP/1.1 200"), "expired read denied")
	var after_rejected: Dictionary = game._vm().portal_snapshot()
	_assert(after_rejected.get("versions", []) == before_rejected.get("versions", []) and after_rejected.get("activity", []).size() == activity.size(), "rejected requests create no versions or activity")
	var share_read: String = game.vm_run("portal share partner read 7d")
	_assert(_json(share_read).get("ok", false), "partner read permission configured")
	var readonly_before: int = game._vm().portal_snapshot().get("versions", []).size()
	_assert(not game.portal_request("partner", "PUT", "current", "partner-mfa-session", RESTORED).begins_with("HTTP/1.1 200"), "partner read-only PUT denied independently")
	_assert(game._vm().portal_snapshot().get("versions", []).size() == readonly_before, "read-only PUT creates no version")
	var noop: String = game.portal_request("staff", "PUT", "current", "staff-session", UPDATED)
	_assert(noop.begins_with("HTTP/1.1 200"), "same-bytes PUT remains successful")
	_assert(game._vm().portal_snapshot().get("versions", []).size() == 1, "same-bytes PUT is a version no-op")
	var second: String = game.portal_request("staff", "PUT", "current", "staff-session", RESTORED)
	_assert(second.begins_with("HTTP/1.1 200"), "second authorized PUT succeeds")
	var versions_after_second: Array = game._vm().portal_snapshot().get("versions", [])
	_assert(versions_after_second.size() == 2, "changed PUT creates next version")
	var replaced_id := str(versions_after_second[0].get("id", ""))
	var replaced_version: Dictionary = _portal_version(replaced_id).get("version", {})
	_assert(str(replaced_version.get("content", "")) == UPDATED and str(versions_after_second[0].get("sha256", "")) == UPDATED.sha256_text(), "restore source retains replaced bytes")
	var restore_raw := str(game.vm_run("portal restore " + first_id))
	var restored := _json(restore_raw)
	_assert(bool(restored.get("ok", false)) and bool(restored.get("changed", false)), "restore version succeeds")
	_assert(game._vm().portal_storage_read(PATH) == original_content, "restore returns actual selected bytes")
	_assert(game._vm().portal_snapshot().get("versions", []).size() == 3, "restore creates a new version")
	var restore_version: Dictionary = game._vm().portal_snapshot().get("versions", [])[0]
	_assert(str(restore_version.get("reason", "")) == "restore" and str(_portal_version(str(restore_version.get("id", ""))).get("version", {}).get("content", "")) == RESTORED, "restore version retains replaced current bytes")
	var before_failed: Dictionary = game._vm().portal_snapshot().duplicate(true)
	var before_failed_state: Dictionary = game.state.duplicate(true)
	var before_failed_vm: Dictionary = game._vm().export_state()
	var before_failed_clock: int = game.clock_minutes()
	var valid_path := str(game.save_path)
	game.save_path = "user://missing-portal-version-save/portal.json"
	var failed_restore: String = game.vm_run("portal restore " + replaced_id)
	game.save_path = valid_path
	var failed_restore_json: Dictionary = _json(failed_restore)
	_assert(not bool(failed_restore_json.get("ok", false)), "failed restore save is rejected")
	_assert(game.state == before_failed_state and game._vm().export_state() == before_failed_vm and game.clock_minutes() == before_failed_clock and game._vm().portal_snapshot() == before_failed and game._vm().portal_storage_read(PATH) == original_content, "failed restore rolls back state VM provider and history")
	_assert(game.save_game() and game.load_game(), "portal versions reload")
	_assert(game._vm().portal_storage_read(PATH) == original_content and game._vm().portal_snapshot().get("versions", []).size() == 3, "versions survive reload")
	await _branch_boundary()
	_legacy_boundary()
	if failures.is_empty(): print("PORTAL_VERSIONS_TEST_PASS")
	else: print("PORTAL_VERSIONS_TEST_FAIL count=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _legacy_boundary() -> void:
	var saved: Variant = preload("res://tests/legacy_service_fixture.gd").measured(5)
	_assert(saved is Dictionary and not saved.is_empty(), "representative legacy portal fixture was constructed")
	_assert(saved is Dictionary, "legacy portal fixture survives JSON roundtrip")
	if not saved is Dictionary: return
	var machine = load("res://scripts/virtual_machine.gd").new()
	_assert(not saved.has("portal_model_version"), "legacy portal fixture has no v2 marker")
	machine.setup(5, saved)
	var snapshot: Dictionary = machine.portal_snapshot()
	_assert(int(snapshot.get("model_version", 1)) == 1 and snapshot.get("versions", []).is_empty(), "legacy portal save remains v1")
