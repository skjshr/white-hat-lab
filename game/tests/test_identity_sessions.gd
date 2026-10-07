extends SceneTree

const VM = preload("res://scripts/virtual_machine.gd")
var failures := 0

func expect(condition: bool, label: String) -> void:
	if not condition: failures += 1; print("FAIL ", label)

func json_of(value: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(value)
	return parsed if parsed is Dictionary else {}

func _init() -> void:
	var vm = VM.new(); vm.setup(3)
	expect(int(vm.state.get("identity_model_version", 0)) == 2, "new v2 stamp")
	# Resume an alphabetically serialized chapter-3 contract after only the
	# current account has drifted. Verdicts must remain paired with authored labels.
	var ordered_scenario := json_of("{\"desired\":{\"current\":\"active\",\"former\":\"disabled\",\"mfa\":\"on\",\"sessions\":\"revoked\"},\"checks\":[\"退職者は新しくログインできない\",\"退職者の既存セッションも利用できない\",\"在籍者はログインできる\",\"利用者の追加認証を必須化\"],\"probes\":[]}")
	var order_vm = VM.new(); order_vm.setup(3, {}, ordered_scenario)
	order_vm.run("ssh client")
	var expected_identity := {"former":"disabled", "sessions":"revoked", "current":"active", "mfa":"on"}
	order_vm.write_file(str(order_vm.state.config_path), order_vm.configuration_text(expected_identity))
	order_vm.run("systemctl restart identity")
	var drifted_identity := expected_identity.duplicate(true); drifted_identity.current = "disabled"
	order_vm.write_file(str(order_vm.state.config_path), order_vm.configuration_text(drifted_identity))
	order_vm.run("systemctl restart identity")
	var saved_identity: Dictionary = JSON.parse_string(JSON.stringify(order_vm.export_state()))
	var resumed_identity = VM.new(); resumed_identity.setup(3, saved_identity)
	var resumed_checks := resumed_identity.snapshot()
	expect(resumed_checks.size() == 4 and resumed_checks[0].operation == "退職者は新しくログインできない" and resumed_checks[0].ok, "JSON reload aligns former-login PASS")
	expect(resumed_checks[1].operation == "退職者の既存セッションも利用できない" and resumed_checks[1].ok, "JSON reload aligns former-session PASS")
	expect(resumed_checks[2].operation == "在籍者はログインできる" and not resumed_checks[2].ok, "JSON reload aligns current-login FAIL")
	expect(resumed_checks[3].operation == "利用者の追加認証を必須化" and resumed_checks[3].ok, "JSON reload aligns current-MFA PASS")
	expect(str(vm.run("identity users")) == "Not connected. ssh client で顧客端末に接続してください。", "disconnected identity denied")
	vm.run("ssh client")
	var users := json_of(vm.run("identity users")); expect(bool(users.get("ok",false)) and int(users.get("code",0)) == 200, "users json status")
	var seeded := json_of(vm.run("identity access former-seed-1")); expect(bool(seeded.get("ok",false)) and int(seeded.get("code",0)) == 200, "seed access")
	expect(vm.run("curl https://identity.client.test/former/session").begins_with("HTTP/1.1 200"), "seed HTTP session")
	vm.run("identity enable former off")
	expect(json_of(vm.run("identity access former-seed-1")).get("ok",false), "disabled account keeps issued app session")
	expect(json_of(vm.run("identity logout former-seed-1")).get("ok",false), "single revoke")
	expect(str(json_of(vm.run("identity access former-seed-1")).get("error","")) == "revoked_session", "revoked seed denied")
	var login_current := json_of(vm.run("identity login current Training-117!")); expect(bool(login_current.get("ok",false)) and int(login_current.get("code",0)) == 200, "password login without mfa")
	var current_token := str(login_current.get("token","")); expect(bool(json_of(vm.run("identity access "+current_token)).get("ok",false)), "current access")
	# A valid password is still an observable MFA boundary: with policy off the
	# v2 probe must fail its MFA-required expectation, then pass on the challenge.
	var mfa_probe_vm := VM.new(); mfa_probe_vm.setup(3); mfa_probe_vm.run("ssh client")
	var mfa_probe_before: Dictionary = mfa_probe_vm.probes().filter(func(p):return p.id=="current-mfa")[0]
	var mfa_command := str(mfa_probe_before.command)
	var missing_password := mfa_probe_vm.run("curl https://identity.client.test/current/login")
	var missing_probe: Dictionary = mfa_probe_vm.probes().filter(func(p):return p.id=="current-mfa")[0]
	expect(not bool(missing_probe.get("recorded",false)) and missing_password.contains("invalid_credentials"), "missing password cannot record current MFA probe")
	mfa_probe_vm.run(mfa_command)
	var off_probe: Dictionary = mfa_probe_vm.probes().filter(func(p):return p.id=="current-mfa")[0]
	expect(bool(off_probe.get("recorded",false)) and not bool(off_probe.get("passed",false)), "valid password fails while MFA is off")
	mfa_probe_vm.run("identity mfa on")
	mfa_probe_vm.run(mfa_command)
	var challenge_probe: Dictionary = mfa_probe_vm.probes().filter(func(p):return p.id=="current-mfa")[0]
	expect(bool(challenge_probe.get("passed",false)) and str(challenge_probe.get("result","")).contains("mfa_required"), "valid password records MFA challenge")
	var disabled_probe_vm := VM.new(); disabled_probe_vm.setup(3); disabled_probe_vm.run("ssh client"); disabled_probe_vm.run("identity enable current off")
	var disabled_command: String = str(disabled_probe_vm.probes().filter(func(p):return p.id=="current-mfa")[0].command)
	var disabled_wrong := disabled_probe_vm.run("curl https://identity.client.test/current/login?password=wrong-password")
	var disabled_probe: Dictionary = disabled_probe_vm.probes().filter(func(p):return p.id=="current-mfa")[0]
	expect(disabled_wrong.contains("invalid_credentials") and not bool(disabled_probe.get("passed",false)), "disabled wrong password is not account-disabled probe success")
	# Simulate a v1.20 v2 save that contains an old passwordless definition and
	# a cached PASS. Reloading must preserve observations but remeasure the
	# changed contract instead of trusting that stale result.
	var stale_vm := VM.new(); stale_vm.setup(3); stale_vm.run("ssh client")
	var stale_probe: Dictionary = stale_vm._active_probes().filter(func(p):return p.id=="current-mfa")[0]
	stale_probe.command = "curl https://identity.client.test/current/login"
	stale_probe.expectation = "status:401"
	stale_probe.recorded = true; stale_probe.passed = true; stale_probe.fresh = true
	stale_probe.result = "HTTP/1.1 401 Unauthorized\n{\"ok\":false,\"code\":401,\"error\":\"invalid_credentials\"}"
	stale_probe.fingerprint = stale_vm._fingerprint()
	expect(bool(stale_probe.recorded) and bool(stale_probe.passed) and bool(stale_probe.fresh), "old v2 probe fixture contains a cached PASS")
	var stale_loaded := VM.new(); stale_loaded.setup(3, stale_vm.export_state()); stale_loaded.run("ssh client")
	var reloaded_probe: Dictionary = stale_loaded.probes().filter(func(p):return p.id=="current-mfa")[0]
	expect(str(reloaded_probe.command).contains("password=Training-117!") and not bool(reloaded_probe.get("recorded",false)) and not bool(reloaded_probe.get("passed",false)), "changed v2 probe invalidates stale saved measurement")
	stale_loaded.run("curl https://identity.client.test/current/login")
	expect(not bool(stale_loaded.probes().filter(func(p):return p.id=="current-mfa")[0].get("recorded",false)), "old passwordless command cannot re-record changed probe")
	vm.run("identity mfa on")
	var challenge := json_of(vm.run("identity login current Training-117!")); expect(bool(challenge.get("ok",false)) and str(challenge.get("error","")) == "mfa_required" and not challenge.has("token"), "mfa challenge no token")
	expect(str(json_of(vm.run("identity otp "+str(challenge.get("challenge",""))+" 000000")).get("error","")) == "invalid_otp", "invalid otp")
	var verified := json_of(vm.run("identity otp "+str(challenge.get("challenge",""))+" 123456")); expect(bool(verified.get("ok",false)) and bool(verified.get("mfa",false)), "verified session")
	var latest := json_of(vm.run("identity access-current-latest")); expect(bool(latest.get("ok",false)) and bool(latest.get("mfa",false)), "latest current access")
	vm.run("identity logout-all current"); expect(str(json_of(vm.run("identity access "+str(verified.get("token","")))).get("error","")) == "revoked_session", "logout all")
	var saved: Dictionary = vm.export_state(); var reloaded = VM.new(); reloaded.setup(3,saved); reloaded.run("ssh client")
	expect(int(reloaded.state.get("identity_model_version",0)) == 2 and str(json_of(reloaded.run("identity access former-seed-1")).get("error","")) == "revoked_session", "reload preserves state")
	var legacy = VM.new(); legacy.setup(3); var old: Dictionary = legacy.export_state(); old.erase("identity_model_version"); var legacy_loaded = VM.new(); legacy_loaded.setup(3,old); expect(int(legacy_loaded.state.get("identity_model_version",0)) == 1, "legacy stays v1")
	var broken = VM.new(); broken.setup(3); broken.run("ssh client"); broken.write_file(str(broken.state.config_path), "former=bad\n"); broken.run("systemctl restart identity"); expect(str(json_of(broken.run("identity users")).get("error","")) == "service_unavailable", "failed service blocks identity")
	# A single logout must not disguise other surviving sessions.
	var multi = VM.new(); multi.setup(3); multi.run("ssh client")
	var additional := json_of(multi.run("identity login former Training-117!"))
	multi.run("identity enable former off"); multi.run("identity logout former-seed-1")
	expect(str(multi.state.applied.sessions)=="valid" and not multi.evaluate()[1],"one logout leaves other former session and fails outcome")
	expect(bool(json_of(multi.run("identity access "+str(additional.token))).get("ok",false)),"other session remains usable")
	multi.run("identity logout-all former")
	multi.run("identity login current Training-117!")
	multi.run("identity mfa on")
	expect(multi.probes().any(func(p):return p.id=="current-business"),"business probe exists before authentication")
	for probe in multi.probes(): multi.run(str(probe.command))
	expect(not multi.probes().filter(func(p):return p.id=="current-business")[0].passed,"policy alone cannot pass business probe")
	var pending := json_of(multi.run("identity login current Training-117!"))
	expect(bool(pending.get("enrollment",false)) and int(pending.code)==401,"unregistered current user has enrollment challenge")
	multi.run("identity enable current off")
	expect(not bool(json_of(multi.run("identity otp "+str(pending.challenge)+" 123456")).get("ok",true)),"disable blocks previously pending OTP")
	multi.run("identity enable current on")
	var complete := json_of(multi.run("identity otp "+str(pending.challenge)+" 123456"))
	expect(bool(complete.get("ok",false)) and bool(multi.identity_snapshot().users[1].otp_registered),"valid OTP enrolls and issues session")
	for probe in multi.probes(): multi.run(str(probe.command))
	expect(multi.probes().all(func(p):return p.recorded and p.fresh and p.passed),"measured identity probes remain fresh after authentication")
	multi.run("systemctl restart identity")
	expect(not bool(multi.identity_snapshot().users[0].enabled) and bool(multi.identity_snapshot().policy.mfa_required),"admin policy survives service restart")
	expect(bool(json_of(multi.run("identity access "+str(complete.token))).get("ok",false)),"restarting config never revokes current user session")
	var isolated=VM.new(); isolated.setup(3); isolated.run("ssh client")
	expect(not bool(json_of(isolated.run("identity access "+str(complete.token))).get("ok",true)),"tokens isolated between customer VMs")
	var untrusted := json_of(multi.run("identity login current wrong-password"))
	expect(not bool(untrusted.get("ok",true)) and not untrusted.has("token"),"wrong password issues no token")
	var pending2 := json_of(multi.run("identity login current Training-117!"))
	multi.run("identity logout-all current")
	expect(not bool(json_of(multi.run("identity otp "+str(pending2.challenge)+" 123456")).get("ok",true)),"logout-all invalidates pending auth")
	print("IDENTITY sessions failures=%d" % failures)
	quit(1 if failures > 0 else 0)
