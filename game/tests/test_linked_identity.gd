extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var qa_id := str(OS.get_process_id())
	var game: Node = await _new_game(qa_id)
	game.set_process(false)
	_assert(game.choose_strategy("operations") and game.start_free_career(), "career fixture")
	game.state.skills.advisory = 10; game.state.skills.operations = 10; game.state.skills.response = 10
	game.state.profit = 1000000; game._update_growth()
	var composite: Dictionary = {}
	for day_index in 60:
		game.state.day = day_index + 1; game._make_offers()
		for offer in game.state.offers:
			if bool(offer.get("market_available", false)) and str(offer.get("case_id", "")) == "composite-former-access": composite = offer; break
		if not composite.is_empty(): break
	_assert(not composite.is_empty(), "composite lead available")
	if composite.is_empty(): _finish(); return
	_assert(game.set_offer_quote(str(composite.id), int(composite.reward)) and game.choose_contract(str(composite.id)), "composite accepted through production APIs")
	_assert(int(game.state.contract.get("linked_identity_version", 0)) == 1, "linked identity contract version")
	_assert(game.state.targets.size() >= 2 and bool(game.state.targets[1].get("scenario", {}).get("linked_identity", false)), "portal target linked flag")
	if game.state.targets.size() < 2: _finish(); return
	_assert(game.select_target(0), "select identity target")
	_assert(game.vm_run("ssh client") != "", "identity SSH")
	var former_initial: Dictionary = _json(game.vm_run("identity access former-seed-1")); _assert(int(former_initial.get("code", 0)) == 200, "seed former session initially allowed")
	_assert(bool(_json(game.vm_run("identity enable former off")).get("ok",false)) and not bool(game._vm().state.identity_users.former.enabled), "disable former user")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "", "select portal target")
	var portal_before: String = game.portal_request("staff", "GET", "current", "former-seed-1"); _assert(portal_before.begins_with("HTTP/1.1 200"), "portal accepts existing former session")
	_assert(game.portal_request("public", "GET", "current", "staff-session").begins_with("HTTP/1.1 401"), "fixed staff token cannot bypass public link MFA")
	_assert(game.select_target(0) and game.vm_run("ssh client") != "", "return identity target")
	_assert(bool(_json(game.vm_run("identity logout former-seed-1")).get("ok",false)), "logout former seed")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "", "return portal after former logout")
	var portal_revoked: String = game.portal_request("staff", "GET", "current", "former-seed-1"); _assert(portal_revoked.begins_with("HTTP/1.1 401"), "portal rejects revoked former session")
	_assert(game.select_target(0) and game.vm_run("ssh client") != "", "identity target for current login")
	var current_token: String = _authenticate_current(game)
	_assert(not current_token.is_empty(), "current authentication")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "", "portal target for current login")
	_assert(game.portal_request("staff", "GET", "current", current_token).begins_with("HTTP/1.1 200"), "current portal access")
	_assert(game.portal_request("staff", "GET", "current", "staff-session").begins_with("HTTP/1.1 401"), "fixed staff token denied")
	_assert(game.portal_request("partner", "GET", "current", current_token).begins_with("HTTP/1.1 401"), "external partner role denied")
	# Correct the portal through its real config/restart path, then measure and verify.
	var desired := "staff=write\npartner=read\npublic=none\nexpires=7d\nmfa=on\ntls=on\naudit=on\n"
	_assert(game.vm_write(str(game.vm_info().config_path), desired), "portal config correction")
	_assert(game.vm_run("systemctl restart portal").begins_with("portal.service: active"), "portal restart")
	_measure(game, "portal")
	_assert(game.select_target(0) and game.vm_run("ssh client") != "", "identity target for measurement")
	_measure(game, "identity")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "" and game.can_deliver(), "linked composite can deliver after measurement")
	_assert(game.select_target(0) and game.vm_run("ssh client") != "", "identity target for provider snapshot")
	var provider_snapshot: Dictionary = game._vm().identity_snapshot() if game._vm().has_method("identity_snapshot") else {}
	_assert(not provider_snapshot.is_empty(), "identity provider snapshot exists")
	var provider_sessions: Array = provider_snapshot.get("sessions", []) if provider_snapshot.get("sessions", []) is Array else []
	_assert(provider_sessions.any(func(item): return str(item.get("id", "")) == current_token and not bool(item.get("revoked", false))), "current provider session persisted")
	_assert(game.save_game() and game.load_game(), "linked provider save reload")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "" and game.portal_request("staff", "GET", "current", current_token).begins_with("HTTP/1.1 200"), "reloaded provider remains authoritative")
	# A failed persistence boundary must leave the real provider session unchanged.
	var before_logout: String = game.portal_request("staff", "GET", "current", current_token)
	var real_save: String = game.save_path
	var logout_selected: bool = game.select_target(0)
	_assert(logout_selected, "identity target for logout rollback")
	_assert(game.vm_run("ssh client") != "", "identity SSH for logout rollback")
	game.save_path = "user://qa-linked-identity-missing-"+qa_id+"/save.json"
	var failed_logout: String = game.vm_run("identity logout "+current_token)
	game.save_path = real_save
	_assert(failed_logout.contains("save_failed") or failed_logout.contains("507"), "identity logout save failure reported")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "" and game.portal_request("staff", "GET", "current", current_token) == before_logout, "identity logout rollback preserves provider session")
	_assert(game.select_target(0), "identity target for service failure")
	var identity_path: String = game.vm_info().config_path
	var identity_config: String = game.vm_read(identity_path)
	_assert(game.vm_write(identity_path,identity_config.replace("mfa=on","mfa=invalid")), "invalid identity configuration saved")
	_assert(game.vm_run("systemctl restart identity").begins_with("Job failed:") and not bool(game._vm().state.active), "identity provider fails from invalid config")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "", "portal target during provider outage")
	var outage_response: String = game.portal_request("staff", "GET", "current", current_token)
	_assert(outage_response.begins_with("HTTP/1.1 503"), "portal reports provider outage")
	_assert(game.select_target(0) and game.vm_write(identity_path,identity_config), "identity configuration restored")
	_assert(game.vm_run("systemctl restart identity").begins_with("identity.service: active"), "identity provider restarted")
	var new_current_token: String = _authenticate_current(game)
	_assert(not new_current_token.is_empty(), "current reauthentication")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "" and game.portal_request("staff", "GET", "current", new_current_token).begins_with("HTTP/1.1 200"), "reauthenticated portal access")
	_measure(game, "portal before logout")
	_assert(game.select_target(0), "identity before logout")
	_measure(game, "identity before logout")
	_assert(game.can_deliver(), "delivery valid immediately before logout")
	_assert(bool(_json(game.vm_run("identity logout "+new_current_token)).get("ok",false)), "current logout invalidates provider session")
	_measure(game, "identity after logout")
	_assert(game.select_target(1) and not game.can_deliver(), "portal measurements stale despite reverified provider")
	_assert(game.diagnostic_probes().all(func(probe):return not bool(probe.get("fresh",false))), "provider change invalidates portal fingerprint")
	_assert(game.portal_request("staff","GET","current",new_current_token).begins_with("HTTP/1.1 401"), "logged out current session denied")
	_assert(game.select_target(0) and game.vm_run("ssh client") != "", "identity target for recovery login")
	_assert(bool(_json(game.vm_run("identity logout-all current")).get("ok",false)), "all current sessions logged out")
	var recovered_token: String = _authenticate_current(game)
	_assert(not recovered_token.is_empty(), "current recovery authentication")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "" and game.portal_request("staff", "GET", "current", recovered_token).begins_with("HTTP/1.1 200"), "recovered current portal access")
	_measure(game, "recovered portal")
	_assert(game.select_target(0) and game.vm_run("ssh client") != "", "identity remeasure target")
	_measure(game, "recovered identity")
	_assert(game.select_target(1) and game.vm_run("ssh client") != "" and game.can_deliver(), "recovered linked delivery")
	# Model a pre-link accepted save using the original target scenarios.
	var raw: String = FileAccess.get_file_as_string(game.save_path); var legacy: Dictionary = JSON.parse_string(raw)
	if legacy.get("contract", {}) is Dictionary: legacy.contract.erase("linked_identity_version")
	for target in legacy.get("targets", []):
		if target is Dictionary: target.erase("scenario")
	for legacy_context in legacy.get("contract_contexts", {}).values():
		if legacy_context is Dictionary:
			if legacy_context.get("contract", {}) is Dictionary: legacy_context.contract.erase("linked_identity_version")
			for legacy_target in legacy_context.get("targets", []):
				if legacy_target is Dictionary: legacy_target.erase("scenario")
	for target_index in legacy.targets.size():
		var vm_key := str(legacy.current_contract_id)+"/site-"+str(target_index)
		if legacy.vm_states.has(vm_key): legacy.vm_states[vm_key].scenario = preload("res://scripts/case_catalog.gd").by_id(str(legacy.targets[target_index].case_id))
	var legacy_path := "user://qa-linked-identity-legacy-"+qa_id+".json"; var file := FileAccess.open(legacy_path, FileAccess.WRITE); file.store_string(JSON.stringify(legacy)); file.close()
	var old_game: Node = await _new_game("legacy-"+qa_id, legacy_path); _assert(old_game.load_game(), "legacy linked composite load")
	_assert(bool(old_game.state.accepted), "legacy accepted composite remains playable")
	_assert(old_game.select_target(1) and old_game.vm_run("ssh client") != "" and not old_game._vm().has_linked_identity(), "legacy composite remains unlinked")
	_assert(old_game.portal_request("staff", "GET", "current", "staff-session").begins_with("HTTP/1.1 200"), "legacy portal fixed staff access preserved")
	_assert(not old_game.diagnostic_probes().any(func(probe):return str(probe.get("id",""))=="linked-former-session"), "legacy does not acquire linked delivery gate")
	_finish()

func _authenticate_current(game: Node) -> String:
	var login := _json(game.vm_run("identity login current Training-117!"))
	if str(login.get("token", "")).is_empty() and not str(login.get("challenge", "")).is_empty():
		login = _json(game.vm_run("identity otp "+str(login.challenge)+" 123456"))
	return str(login.get("token", ""))

func _measure(game: Node, label: String) -> void:
	for probe in game.diagnostic_probes():
		var result: String = game.run_diagnostic(str(probe.id)); _assert(not result.is_empty(), label+" probe "+str(probe.id))
	var checks: Array = game.verify(); _assert(not checks.is_empty() and checks.all(func(item): return bool(item is Dictionary and item.get("passed", false))), label+" verify")

func _json(raw: String) -> Dictionary:
	var value = JSON.parse_string(raw)
	return value if value is Dictionary else {}

func _new_game(label: String, path: String = "") -> Node:
	var game: Node = load("res://scripts/game.gd").new(); root.add_child(game); await process_frame
	var base := path if not path.is_empty() else "user://qa-linked-identity-"+label+".json"
	game.save_path = base; game.backup_path = base+".bak"; game.previous_path = base+".previous"; game.settings_path = base+".settings"; game._reset_state()
	return game

func _finish() -> void:
	if failures.is_empty(): print("LINKED_IDENTITY_TEST_PASS")
	else:
		for failure in failures: push_error(failure)
		print("LINKED_IDENTITY_TEST_FAIL count=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _assert(condition: bool, label: String) -> void:
	if not condition: failures.append(label)
