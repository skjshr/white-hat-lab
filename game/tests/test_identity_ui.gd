extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var capture_enabled := false
var narrow := false
var capture_dir := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture": capture_enabled = true
		if arg == "--narrow": narrow = true
	create_timer(55.0).timeout.connect(func(): push_error("identity UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL: ",label)

func control(id: String):
	return pc.widgets.browser.page.find_child(id,true,false)

func press(id: String) -> bool:
	var node = control(id)
	if not node is BaseButton or node.disabled:
		check(false,"missing or disabled control "+id); return false
	node.pressed.emit()
	return true

func input(id: String, value: String) -> void:
	var node = control(id)
	check(node is LineEdit,"input exists "+id)
	if node is LineEdit: node.text=value

func frames(count := 4) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(8)
	await RenderingServer.frame_post_draw
	var file := capture_dir.path_join(label+("-narrow" if narrow else "-wide")+".png")
	check(root.get_texture().get_image().save_png(file)==OK,"capture "+label)

func login(user: String, password: String = "Training-117!") -> void:
	press("IdentityView_login")
	input("IdentityLoginUser",user); input("IdentityLoginPassword",password)
	press("IdentitySignIn")

func output() -> Dictionary:
	return pc.identity_ui.get("output",{})

func select_meta(id: String, value: String) -> void:
	var node = control(id)
	check(node is OptionButton,"selector exists "+id)
	if not node is OptionButton:return
	for index in node.item_count:
		if str(node.get_item_metadata(index))==value:
			node.select(index);node.item_selected.emit(index);return
	check(false,"selector value "+id+" "+value)

func credential_flow() -> String:
	var temporary := "Temporary 'quoted' \"two\" 2026!"
	var permanent := "Account 'new' \"two\" 2026!"
	var previous_token := str(pc.identity_ui.get("token",""))
	press("IdentityView_users");press("IdentityUser_current");press("IdentityTab_credentials")
	check(control("IdentityCredentialsTable")!=null,"credentials table contains real records")
	await capture("identity-credentials")
	var unchanged: Dictionary=game._vm().identity_snapshot().users[1].duplicate(true)
	press("IdentityPasswordChange");input("IdentityPassword",temporary);input("IdentityPasswordConfirmation","mismatch");press("IdentityPasswordSave")
	check(str(output().get("error",""))=="password_mismatch" and game._vm().identity_snapshot().users[1]==unchanged,"password mismatch changes no credential")
	press("IdentityPasswordCancel");press("IdentityPasswordChange")
	input("IdentityPassword",temporary);input("IdentityPasswordConfirmation",temporary)
	await capture("identity-reset-password")
	await frames()
	check(pc.windows.browser.get_global_rect().encloses(control("IdentityPasswordSave").get_global_rect()),"password reset action visible without scrolling")
	press("IdentityPasswordSave")
	check(bool(output().get("ok",false)) and bool(game._vm().identity_snapshot().users[1].password_temporary),"temporary password set through UI")
	check(bool(JSON.parse_string(game.vm_run("identity access "+previous_token)).get("ok",false)),"password reset retains existing application session")
	login("current");check(str(output().get("error",""))=="invalid_credentials","old password rejected after reset")
	login("current",temporary)
	check(str(output().get("required_action",""))=="UPDATE_PASSWORD" and not output().has("token") and control("IdentityPasswordUpdateForm")!=null,"temporary login requires change before session")
	input("IdentityPasswordUpdate",permanent);input("IdentityPasswordUpdateConfirmation","mismatch");press("IdentityPasswordUpdateSubmit")
	check(control("IdentityPasswordUpdateForm")!=null and control("IdentityOtp")==null,"confirmation retry preserves password-update stage")
	input("IdentityPasswordUpdate",permanent);input("IdentityPasswordUpdateConfirmation",permanent)
	await capture("identity-update-password")
	await frames()
	check(pc.windows.browser.get_global_rect().encloses(control("IdentityPasswordUpdateSubmit").get_global_rect()),"password update action visible without scrolling")
	press("IdentityPasswordUpdateSubmit")
	check(str(output().get("error",""))=="mfa_required" and not output().has("token") and control("IdentityOtp")!=null,"password update advances to real MFA challenge")
	input("IdentityOtp","123456");press("IdentityVerifyOtp")
	check(bool(output().get("mfa",false)) and output().has("token"),"new credential completes MFA login")
	press("IdentityView_users");press("IdentityUser_current");press("IdentityTab_credentials");press("IdentityOtpDelete")
	await capture("identity-delete-otp")
	press("IdentityOtpDeleteConfirm")
	check(not bool(game._vm().identity_snapshot().users[1].otp_registered),"OTP removal reaches credential state")
	login("current",permanent)
	check(bool(output().get("enrollment",false)) and not output().has("token"),"removed OTP requires enrollment again")
	input("IdentityOtp","123456");press("IdentityVerifyOtp")
	var token := str(output().get("token",""))
	check(not token.is_empty() and bool(game._vm().identity_snapshot().users[1].otp_registered),"OTP reenrollment issues usable session")
	var current_probe: Dictionary=game.diagnostic_probes().filter(func(p):return str(p.id)=="current-mfa")[0]
	check(bool(current_probe.get("requires_login",false)),"changed credential needs actual login measurement")
	var before_probe: Dictionary=current_probe.duplicate(true)
	check(str(JSON.parse_string(game.run_diagnostic("current-mfa")).get("error",""))=="credentials_required" and game.diagnostic_probes().filter(func(p):return str(p.id)=="current-mfa")[0]==before_probe,"automatic diagnostic does not overwrite evidence with stale password")
	pc._show_app("verify");pc.widgets.verify.selected="current-mfa";pc._refresh_checks();await frames()
	var diagnostic=pc.widgets.verify.right.find_child("DiagnosticRun",true,false)
	check(diagnostic is BaseButton,"diagnostic login action exists")
	if diagnostic is BaseButton:diagnostic.pressed.emit()
	await frames()
	check(control("IdentityLoginUser")!=null and control("IdentityLoginUser").text=="current","diagnostic opens correct user's login")
	input("IdentityLoginPassword",permanent);press("IdentitySignIn")
	check(bool(game.diagnostic_probes().filter(func(p):return str(p.id)=="current-mfa")[0].passed),"actual changed-password login records MFA measurement")
	input("IdentityOtp","123456");press("IdentityVerifyOtp");token=str(output().get("token",""))
	input("IdentityToken",token);press("IdentityAccess")
	press("IdentityView_events");press("IdentityEventsAdminTab");select_meta("IdentityEventUser","current");select_meta("IdentityEventOutcome","success")
	var event: Dictionary=game._vm().identity_snapshot().audit_events.filter(func(e):return str(e.type)=="password_set" and str(e.user)=="current" and str(e.outcome)=="temporary")[0]
	press("IdentityEvent_"+str(event.sequence));await capture("identity-admin-event-detail")
	check(control("IdentityEventDetails")!=null,"selected admin event exposes actual details")
	select_meta("IdentityEventOutcome","");press("IdentityEventsUserTab");await capture("identity-user-events")
	pc._run_command("identity login current "+load("res://scripts/os_identity_console.gd")._shell_arg(permanent))
	check(not pc.terminal_log.contains(permanent) and not JSON.stringify(pc.history).contains(permanent),"terminal echo and history omit supplied credential")
	pc._save_session(false)
	for secret in [temporary,permanent]:check(not JSON.stringify(game.state).contains(secret),"UI state does not save plaintext credential")
	return token

func run() -> void:
	ui=load("res://scripts/interface.gd").new(); root.add_child(ui); await process_frame
	game=ui._game(); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"isolated QA profile")
	game.save_path="user://qa-identity-ui-"+str(OS.get_process_id())+".json"
	game.backup_path=game.save_path+".bak"; game.previous_path=game.save_path+".previous"; game.settings_path=game.save_path+".settings"
	ui._new_game(); game.choose_strategy("advisory")
	game.state.chapter=3; game.state.completed_ids=["share","backup","network"]
	check(game.accept_mission(),"account mission accepted")
	game.vm_run("ssh client")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1280,720)
	ui._set_text_scale(1.3 if narrow else 1.0)
	await frames()
	ui.open_panel("terminal"); pc=ui.desktop; pc._show_app("browser"); await frames()
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	pc._browse_url(pc.IDENTITY_URL,true); await frames()
	capture_dir=ProjectSettings.globalize_path("res://../artifacts/simulator/identity-admin/ui"); DirAccess.make_dir_recursive_absolute(capture_dir)
	check(control("IdentityUser_former")!=null and control("IdentityUser_current")!=null,"real users rendered")
	await capture("identity-users")
	login("former")
	var old_token := str(pc.identity_ui.get("token",""))
	check(not old_token.is_empty() and bool(output().get("ok",false)),"login creates actual token")
	press("IdentityView_users"); press("IdentityUser_former")
	var enabled = control("IdentityEnable"); check(enabled is CheckBox,"enabled checkbox exists")
	if enabled is CheckBox: enabled.button_pressed=false
	press("IdentitySave")
	check(not bool(game._vm().identity_snapshot().users[0].enabled),"disable persisted to VM")
	press("IdentityView_login"); input("IdentityToken",old_token); press("IdentityAccess")
	check(bool(output().get("ok",false)),"same preissued session survives new-login disable")
	login("former"); check(not bool(output().get("ok",true)),"disabled user cannot create another session")
	press("IdentityView_users"); press("IdentityUser_former"); press("IdentityTab_sessions")
	await capture("identity-sessions")
	press("IdentityLogout_"+old_token)
	press("IdentityView_login"); input("IdentityToken",old_token); press("IdentityAccess")
	check(not bool(output().get("ok",true)),"individual logout rejects same token")
	press("IdentityView_users"); press("IdentityUser_former"); press("IdentityTab_sessions")
	press("IdentityLogoutAll_former")
	check(game._vm().identity_snapshot().sessions.filter(func(s):return s.user=="former" and not s.revoked).is_empty(),"all former sessions revoked")
	press("IdentityView_authentication")
	var mfa = control("IdentityMfa"); check(mfa is OptionButton or mfa is CheckBox or mfa is CheckButton,"MFA policy control exists")
	if mfa is OptionButton: mfa.select(1)
	elif mfa is CheckBox or mfa is CheckButton: mfa.button_pressed=true
	press("IdentityApply")
	check(bool(game._vm().identity_snapshot().policy.mfa_required),"MFA policy applied")
	await capture("identity-policy")
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.id))
	game.verify(); check(not game.can_deliver(),"OTP cannot be skipped by setting policy alone")
	login("current")
	check(not str(pc.identity_ui.get("challenge","")).is_empty(),"password login creates challenge")
	await capture("identity-challenge")
	input("IdentityOtp","000000"); press("IdentityVerifyOtp")
	check(not bool(output().get("ok",true)),"wrong OTP denied")
	input("IdentityOtp","123456"); press("IdentityVerifyOtp")
	check(bool(output().get("ok",false)),"OTP completes real authentication")
	var current_token := str(pc.identity_ui.get("token",""))
	input("IdentityToken",current_token); press("IdentityAccess")
	check(bool(output().get("ok",false)) and bool(output().get("mfa",false)),"authenticated current user can access businessapp")
	await capture("identity-authenticated")
	current_token = await credential_flow()
	press("IdentityView_events"); await capture("identity-events")
	for attempt in 3:
		for probe in game.diagnostic_probes():
			if not (probe.recorded and probe.fresh and probe.passed): game.run_diagnostic(str(probe.id))
	game.verify()
	check(game.can_deliver(),"actual admin changes and measured business access satisfy delivery")
	check(pc._save_session() and game.save_game(),"identity and desktop session saved")
	check(game.load_game(),"identity saved game reload")
	pc._load_session()
	check(str(pc.identity_ui.get("token",""))==current_token,"browser token preserved after reload")
	var previous_path: String=game.save_path
	var previous_state: String=JSON.stringify(game.state,"",true)
	var previous_vm: String=JSON.stringify(game._vm().export_state(),"",true)
	game.save_path="user://missing-identity-"+str(OS.get_process_id())+"/cannot-save.json"
	var failed = JSON.parse_string(game.vm_run("identity enable current off"))
	check(failed is Dictionary and not bool(failed.get("ok",true)),"save failure returned")
	check(JSON.stringify(game.state,"",true)==previous_state and JSON.stringify(game._vm().export_state(),"",true)==previous_vm,"save failure rolls back complete gameplay and VM state")
	game.save_path=previous_path
	check(game.deliver(),"measured identity case delivered")
	for failure in failures: push_error(failure)
	print("IDENTITY_UI_PASS" if failures.is_empty() else "IDENTITY_UI_FAIL count="+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
