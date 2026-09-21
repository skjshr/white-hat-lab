extends SceneTree

const VM = preload("res://scripts/virtual_machine.gd")
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)

func response(raw: String) -> Dictionary:
	var value: Variant = JSON.parse_string(raw)
	return value if value is Dictionary else {}

func run_identity(vm: RefCounted, command: String) -> Dictionary:
	var result := response(str(vm.run(command)))
	check(not result.is_empty(), "JSON response: %s" % command)
	return result

func _init() -> void:
	var first := VM.new()
	var second := VM.new()
	first.setup(3); second.setup(3)
	check(first.run("ssh client") != "" and second.run("ssh client") != "", "isolated identity shells")

	var set_temporary := run_identity(first, "identity password-set current Temp-Password-117! temporary")
	check(bool(set_temporary.get("ok", false)) and bool(set_temporary.get("temporary", false)), "temporary password set")
	var old_login := run_identity(first, "identity login current Training-117!")
	check(str(old_login.get("error", "")) == "invalid_credentials" and not old_login.has("token"), "old password rejected")
	var temporary_login := run_identity(first, "identity login current Temp-Password-117!")
	check(int(temporary_login.get("code", 0)) == 401 and str(temporary_login.get("error", "")) == "password_update_required", "temporary login requires update")
	check(not temporary_login.has("token") and str(temporary_login.get("required_action", "")) == "UPDATE_PASSWORD", "temporary login has no session")
	var update := run_identity(first, "identity password-update %s Permanent-Password-117!" % str(temporary_login.get("challenge", "")))
	check(bool(update.get("ok", false)) and str(update.get("error", "")) == "ok", "password challenge update")
	check(str(run_identity(first, "identity otp %s 123456" % str(temporary_login.get("challenge", ""))).get("error", "")) in ["challenge_used", "invalid_challenge", "unknown_challenge"], "OTP cannot satisfy password-update challenge")
	var permanent_login := run_identity(first, "identity login current Permanent-Password-117!")
	var current_token := str(permanent_login.get("token", ""))
	if permanent_login.has("challenge"):
		var otp := run_identity(first, "identity otp %s 123456" % str(permanent_login.get("challenge", "")))
		current_token = str(otp.get("token", ""))
	check(not current_token.is_empty(), "new password issues authenticated session")
	check(bool(run_identity(first, "identity access %s" % current_token).get("ok", false)), "new session access")

	# Replacing a credential invalidates an outstanding password-update challenge,
	# while leaving already issued application sessions usable.
	var second_temporary := run_identity(first, "identity password-set current Temp-Again-117! temporary")
	check(bool(second_temporary.get("ok", false)), "second temporary password set")
	var reset_challenge := run_identity(first, "identity login current Temp-Again-117!")
	check(str(reset_challenge.get("error", "")) == "password_update_required", "second update challenge")
	var reset := run_identity(first, "identity password-set current Reset-117! permanent")
	check(bool(reset.get("ok", false)), "admin reset during challenge")
	var reset_again := run_identity(first, "identity password-set current Reset-117! permanent")
	check(bool(reset_again.get("ok", false)) and not bool(reset_again.get("changed", true)), "same password set is idempotent")
	var stale_update := run_identity(first, "identity password-update %s Never-Used-117!" % str(reset_challenge.get("challenge", "")))
	check(not bool(stale_update.get("ok", true)) and str(stale_update.get("error", "")) in ["challenge_used", "unknown_challenge", "credential_changed"], "reset invalidates old challenge")
	check(bool(run_identity(first, "identity access %s" % current_token).get("ok", false)), "credential reset preserves existing session")

	# OTP deletion is scoped to the user and does not revoke an existing session.
	var former_session := run_identity(first, "identity access former-seed-1")
	check(bool(former_session.get("ok", false)), "seed former session available")
	var otp_deleted := run_identity(first, "identity otp-delete former")
	check(bool(otp_deleted.get("ok", false)) and not bool(otp_deleted.get("otp_registered", true)), "OTP credential deleted")
	var otp_deleted_again := run_identity(first, "identity otp-delete former")
	check(bool(otp_deleted_again.get("ok", false)) and not bool(otp_deleted_again.get("changed", true)), "same OTP deletion is idempotent")
	check(bool(run_identity(first, "identity access former-seed-1").get("ok", false)), "OTP delete keeps old session")
	check(bool(run_identity(first, "identity mfa on").get("ok", false)), "MFA policy for re-enrollment")
	var former_login := run_identity(first, "identity login former Training-117!")
	check(str(former_login.get("error", "")) == "mfa_required" and bool(former_login.get("enrollment", false)), "OTP deletion requires reenrollment")
	var former_otp := run_identity(first, "identity otp %s 123456" % str(former_login.get("challenge", "")))
	check(bool(former_otp.get("ok", false)) and bool(first.identity_snapshot().users[0].otp_registered), "OTP reenrollment")
	check(str(run_identity(first, "identity otp %s 123456" % str(former_login.get("challenge", ""))).get("error", "")) == "challenge_used", "consumed OTP challenge cannot replay")
	check(str(run_identity(first, "identity password-update %s Another-117!" % str(former_login.get("challenge", ""))).get("error", "")) in ["challenge_used", "unknown_challenge", "invalid_challenge"], "password update cannot satisfy OTP challenge")

	# With MFA required, a temporary-password update transitions to a second,
	# independent MFA challenge and cannot issue a business token early.
	var mfa_vm := VM.new(); mfa_vm.setup(3); mfa_vm.run("ssh client")
	check(bool(run_identity(mfa_vm, "identity mfa on").get("ok", false)), "mandatory MFA setup")
	check(bool(run_identity(mfa_vm, "identity password-set current MFA-Temp-117! temporary").get("ok", false)), "MFA temporary password set")
	var mfa_temp := run_identity(mfa_vm, "identity login current MFA-Temp-117!")
	check(str(mfa_temp.get("error", "")) == "password_update_required" and not mfa_temp.has("token"), "MFA temporary login has no token")
	var mfa_updated := run_identity(mfa_vm, "identity password-update %s MFA-Permanent-117!" % str(mfa_temp.get("challenge", "")))
	check(str(mfa_updated.get("error", "")) == "mfa_required" and not mfa_updated.has("token"), "password update leads to MFA challenge")
	var mfa_token := run_identity(mfa_vm, "identity otp %s 123456" % str(mfa_updated.get("challenge", "")))
	check(bool(mfa_token.get("ok", false)) and not str(mfa_token.get("token", "")).is_empty(), "MFA challenge issues token only after OTP")

	# Credential-bearing commands may contain quoted values. The matching probe
	# follows the authenticated user, while an unrelated identity URL cannot
	# overwrite the current user's measurement; every password query is redacted.
	var quoted_vm := VM.new(); quoted_vm.setup(3); quoted_vm.run("ssh client")
	check(bool(run_identity(quoted_vm, "identity mfa on").get("ok", false)), "quoted credential MFA setup")
	check(bool(run_identity(quoted_vm, "identity password-set current 'Quoted Pass-117!' permanent").get("ok", false)), "quoted permanent password set")
	quoted_vm.run("identity login current wrong-password")
	var quoted_login := run_identity(quoted_vm, "sudo identity login 'current' 'Quoted Pass-117!'")
	check(str(quoted_login.get("error", "")) == "mfa_required" and not quoted_login.has("token"), "quoted login reaches MFA challenge")
	var current_probe: Dictionary = quoted_vm.probes().filter(func(item): return str(item.get("id", "")) == "current-mfa")[0]
	check(bool(current_probe.get("passed", false)) and str(current_probe.get("result", "")).contains("mfa_required"), "quoted login records current MFA probe")
	var current_probe_result := str(current_probe.get("result", ""))
	quoted_vm.run("curl https://identity.client.test/former/login?password=Training-117!")
	current_probe = quoted_vm.probes().filter(func(item): return str(item.get("id", "")) == "current-mfa")[0]
	check(str(current_probe.get("result", "")) == current_probe_result, "unrelated identity path cannot overwrite current probe")
	quoted_vm.run("curl https://identity.client.test/current/login?password=wrong https://unrelated.client.test/current/login?password=wrong")
	check(str(quoted_vm.probes().filter(func(item): return str(item.id) == "current-mfa")[0].result) == current_probe_result, "measurement follows executed URL rather than unused URL argument")
	quoted_vm.run("curl 'https://identity.client.test/current/login?password=Quoted Pass-117!'")
	check(not str(quoted_vm.state.observations.back().command).contains("Pass-117!"), "quoted URL password suffix is redacted")
	quoted_vm.run("curl https://identity.client.test/current/login?password=First-117!&password=Second-117!")
	quoted_vm.run("curl https://identity.client.test/current/login?password=<redacted>&password=Third-117!")
	var last_observation: Dictionary = quoted_vm.state.get("observations", []).back() if not quoted_vm.state.get("observations", []).is_empty() else {}
	var redacted_command := str(last_observation.get("command", ""))
	check(redacted_command.count("<redacted>") >= 2 and not redacted_command.contains("Third-117!"), "multiple password query values are redacted")

	# A second VM has independent credentials, sessions, and audit state.
	var other_old := run_identity(second, "identity login current Training-117!")
	check(bool(other_old.get("ok", false)) and not other_old.has("challenge"), "other VM keeps old password")
	check(str(run_identity(second, "identity login current Reset-117!").get("error", "")) == "invalid_credentials", "other VM rejects reset password")

	# Secrets must never be serialized into state, identity snapshots, or audit text.
	var exported := JSON.stringify(first.export_state())
	var snapshot := JSON.stringify(first.identity_snapshot())
	for secret in ["Temp-Password-117!", "Permanent-Password-117!", "Temp-Again-117!", "Reset-117!", "Never-Used-117!"]:
		check(not exported.contains(secret), "credential absent from save snapshot: "+secret)
		check(not snapshot.contains(secret), "credential absent from identity snapshot: "+secret)
		for event in first.state.get("events", []): check(not str(event).contains(secret), "credential absent from event log: "+secret)
		for event in first.state.get("identity_events", []): check(not JSON.stringify(event).contains(secret), "credential absent from identity audit: "+secret)
		for observation in first.state.get("observations", []): check(not JSON.stringify(observation).contains(secret), "credential absent from observations: "+secret)

	var reloaded := VM.new(); reloaded.setup(3, first.export_state()); reloaded.run("ssh client")
	check(bool(run_identity(reloaded, "identity login current Reset-117!").get("ok", false)), "credential survives reload")
	check(bool(run_identity(reloaded, "identity access %s" % current_token).get("ok", false)), "session survives reload")

	# A v2 save with no newly added credential metadata is migrated without
	# inventing credential events, while the legacy password remains usable.
	var legacy_source := VM.new(); legacy_source.setup(3)
	var legacy := legacy_source.export_state()
	legacy.erase("identity_events"); legacy.erase("identity_event_sequence")
	for user in ["former", "current"]:
		if legacy.get("identity_users", {}).get(user, {}) is Dictionary:
			legacy.identity_users[user].erase("password_sha256")
			legacy.identity_users[user].erase("password_temporary")
			legacy.identity_users[user].erase("credential_revision")
			legacy.identity_users[user].erase("required_actions")
	var legacy_fingerprint := legacy_source._fingerprint()
	var migrated := VM.new(); migrated.setup(3, legacy); migrated.run("ssh client")
	check(migrated._fingerprint() == legacy_fingerprint, "v2 migration preserves credential fingerprint")
	check(migrated.state.get("identity_events", []).is_empty(), "legacy migration creates no credential audit events")
	var migrated_login := run_identity(migrated, "identity login current Training-117!")
	check(bool(migrated_login.get("ok", false)), "v2 credential metadata migration keeps login")
	await _game_save_rollback()

	if failures.is_empty(): print("IDENTITY_CREDENTIALS_TEST_PASS")
	else: print("IDENTITY_CREDENTIALS_TEST_FAIL count=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _game_save_rollback() -> void:
	var game: Node = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	var qa_id := str(OS.get_process_id())
	var base := "user://qa-identity-credentials-game-"+qa_id+".json"
	game.save_path = base; game.backup_path = base+".bak"; game.previous_path = base+".previous"; game.settings_path = base+".settings"
	game._reset_state(); game.set_process(false)
	check(game.choose_strategy("operations") and game.start_free_career(), "Game credential transaction career")
	game.state.skills.advisory = 10; game.state.skills.operations = 10; game.state.skills.response = 10; game.state.profit = 1000000; game._update_growth()
	var offer: Dictionary = {}
	for day_index in 60:
		game.state.day = day_index + 1; game._make_offers()
		for candidate in game.state.offers:
			if bool(candidate.get("market_available", false)) and str(candidate.get("case_id", "")) == "composite-former-access": offer = candidate; break
		if not offer.is_empty(): break
	check(not offer.is_empty(), "Game credential transaction offer")
	if offer.is_empty(): return
	check(game.set_offer_quote(str(offer.id), int(offer.reward)) and game.choose_contract(str(offer.id)), "Game credential transaction accept")
	check(game.select_target(0) and game.vm_run("ssh client") != "", "Game credential transaction identity target")
	var before_state: String = JSON.stringify(game.state)
	var before_vm: String = JSON.stringify(game._vm().export_state())
	var real_path: String = str(game.save_path)
	game.save_path = "user://qa-identity-credentials-missing-"+qa_id+"/save.json"
	var failed: String = str(game.vm_run("identity password-set current Game-Rollback-117! permanent"))
	game.save_path = real_path
	check(failed.contains("save_failed") or failed.contains("507"), "Game credential save failure reported")
	check(JSON.stringify(game.state) == before_state and JSON.stringify(game._vm().export_state()) == before_vm, "Game credential save failure rolls back state and VM")
	check(str(run_identity(game._vm(), "identity login current Game-Rollback-117!").get("error", "")) == "invalid_credentials", "rolled back password is not usable")
	check(bool(run_identity(game._vm(), "identity login current Training-117!").get("ok", false)), "rolled back original password remains usable")
