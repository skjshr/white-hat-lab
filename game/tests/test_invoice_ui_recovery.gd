extends SceneTree
## Limited recovery integration: real Game persistence failures and UI controls.
## Buttons use their signals; input signals exercise the production form handlers.

var game
var ui
var pc
var failures: Array[String] = []
var assertions := 0
var save_path := ""

func _init() -> void:
	create_timer(75.0).timeout.connect(func(): push_error("INVOICE_UI_RECOVERY_TIMEOUT"); quit(2))
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label); print("FAIL ", label)

func frames(count := 3) -> void:
	for _index in count: await process_frame

func idle() -> void:
	await create_timer(0.4).timeout
	for _index in 120:
		if not bool(pc.widgets.get("advanced", {}).get("busy", false)): break
		await process_frame
	await frames()

func control(id: String) -> Node:
	return pc.find_child(id, true, false) if is_instance_valid(pc) else null

func press(id: String) -> void:
	var button := control(id) as BaseButton
	check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "available UI action " + id)
	if not is_instance_valid(button) or button.disabled: return
	button.pressed.emit()
	await idle()

func enter(id: String, value: String) -> void:
	var field := control(id)
	check(field is LineEdit or field is TextEdit, "available UI input " + id)
	if field is LineEdit:
		field.text = value; field.text_changed.emit(value)
	elif field is TextEdit:
		field.text = value; field.text_changed.emit()

func service() -> Dictionary:
	return pc.pentest_ui.get("service", {})

func latest() -> Dictionary:
	var history: Array = game.advanced_view().get("history", [])
	return history.back() if not history.is_empty() else {}

func request(method: String, path: String, token: String, body := {}) -> Dictionary:
	var result: Dictionary = game.advanced_action("request", {"method":method,"path":path,"session":token,"body":body,"headers":{},"origin":"replay"})
	check(bool(result.get("ok", false)), "persist supplementary request " + method + " " + path)
	return result.get("response", {})

func fail_saving(stage: String) -> void:
	var missing := "user://missing-invoice-recovery-%s-%d" % [stage, OS.get_process_id()]
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(missing)), "save failure uses an absent QA directory")
	game.save_path = missing + "/cannot-save.json"

func login() -> String:
	await press("PentestTab_portal")
	enter("InvoiceLoginUsername", "alice")
	enter("InvoiceLoginPassword", "Alice-demo-27")
	await press("InvoiceLoginSubmit")
	var token := str(pc.pentest_ui.get("portal_session", ""))
	check(not token.is_empty() and token != "alice", "normal UI receives an opaque session")
	check(str(pc.pentest_ui.get("portal_user", {}).get("username", "")) == "alice" and bool(service().get("session_checked", false)), "normal UI identifies the authenticated user")
	check(control("InvoiceLogout") != null and not service().get("invoices", []).is_empty(), "normal UI displays authenticated invoice list")
	return token

func setup() -> bool:
	game = root.get_node("Game"); game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "isolated QA save profile")
	if not str(game.save_path).begins_with("user://qa-"): return false
	save_path = str(game.save_path)
	check(game.new_game(), "create isolated company")
	game.set_settings({"resolution":"1440x900","window_mode":"windowed","text_scale":1.0,"volume":0},false)
	root.size = Vector2i(1440,900)
	check(game.choose_strategy("advisory") and game.start_free_career(), "start eligible career")
	var selected: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == "advanced-portal" and bool(offer.get("market_available",false)) and bool(offer.get("unlocked",false)):
			selected = offer; break
	check(not selected.is_empty(), "existing portal engagement is offered")
	if selected.is_empty(): return false
	check(game.choose_contract(str(selected.id)), "accept existing engagement through real API")
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	ui.controls.menu.hide(); ui.guided_intro.skip()
	ui.open_panel("terminal"); await frames(); pc = ui.desktop; pc._show_app("advanced"); await frames(8)
	if not pc.windows.advanced.maximized: pc.windows.advanced.toggle_maximize(); await frames()
	return control("InvoiceLoginSubmit") != null

func failed_logout(token: String) -> void:
	var before: Dictionary = game.state.advanced.duplicate(true)
	var cached: Array = service().get("invoices", []).duplicate(true)
	var revision := int(game.state.revision)
	fail_saving("logout")
	await press("InvoiceLogout")
	check(game.state.advanced == before and int(game.state.revision) == revision, "failed logout rolls back the model, HTTP history and revision")
	check(str(pc.pentest_ui.get("portal_session", "")) == token and str(pc.pentest_ui.get("portal_user", {}).get("username", "")) == "alice", "failed logout retains the actual logged-in principal")
	check(bool(service().get("session_checked",false)) and service().get("invoices",[]) == cached, "failed logout keeps authenticated cached invoices")
	check(bool(service().get("error",false)) and not str(service().get("feedback","")).is_empty() and not str(service().get("feedback","")).contains("ログアウトしました"), "failed logout presents failure rather than success")
	check(control("InvoiceLogout") != null and control("InvoiceLoginSubmit") == null, "failed logout does not replace the app with a login form")
	game.save_path = save_path
	check(int(request("GET","/api/auth/session",token).get("status",0)) == 200, "rolled-back session remains authorized")
	await press("PentestPortalLoad")
	check(not bool(service().get("error",true)) and not service().get("invoices",[]).is_empty(), "same user continues normal business after storage recovers")

func resume_retry(token: String) -> void:
	check(pc._save_session(), "persist portal session before revisit")
	check(ui.close_panel(false,false), "close desktop normally")
	await frames()
	check(game.load_game(), "reload actual saved company")
	var before: Dictionary = game.state.advanced.duplicate(true)
	fail_saving("resume")
	ui.open_panel("terminal"); await frames(); pc = ui.desktop; pc._show_app("advanced"); await frames(8)
	if not pc.windows.advanced.maximized: pc.windows.advanced.toggle_maximize(); await frames()
	await idle()
	check(game.state.advanced == before, "failed session-check persistence rolls back its HTTP observation")
	check(str(pc.pentest_ui.get("portal_session", "")) == token and str(pc.pentest_ui.get("portal_user",{}).get("username","")) == "alice", "resume-check failure retains the saved identity for retry")
	check(not bool(service().get("session_checked",true)) and bool(service().get("error",false)), "revisit waits for a successful session check")
	check(control("InvoiceLoginSubmit") == null and control("InvoiceResumeSession") != null, "session-check failure exposes an explicit retry action")
	game.save_path = save_path
	await press("InvoiceResumeSession")
	check(str(pc.pentest_ui.get("portal_session","")) == token and bool(service().get("session_checked",false)), "retry confirms the original session without another login")
	check(not bool(service().get("error",true)) and not service().get("invoices",[]).is_empty(), "retry repopulates the normal invoice list")
	check(control("InvoiceResumeSession") == null and control("InvoiceLogout") != null, "successful retry returns to the authenticated UI")

func workbench_logout(token: String) -> void:
	await press("PentestTab_request")
	enter("PentestMethod", "POST")
	enter("PentestPath", "/api/auth/logout")
	enter("PentestSession", token)
	enter("PentestBody", "{}")
	await press("PentestSend")
	check(str(latest().get("request",{}).get("session","")) == token and str(latest().get("request",{}).get("path","")) == "/api/auth/logout" and int(latest().get("response",{}).get("status",0)) == 200, "workbench records logout for the submitted session")

func cache_invalidation(token: String, unrelated: String) -> void:
	check(not unrelated.is_empty() and unrelated != token, "older session belongs to the same principal but is distinct")
	var cached: Array = service().get("invoices",[]).duplicate(true)
	await workbench_logout(unrelated)
	check(str(pc.pentest_ui.get("portal_session","")) == token and str(pc.pentest_ui.get("portal_user",{}).get("username","")) == "alice", "logout of another token does not clear current identity")
	check(bool(service().get("session_checked",false)) and service().get("invoices",[]) == cached, "logout of another token preserves current normal cache")
	await press("PentestTab_portal")
	check(control("InvoiceLogout") != null and control("InvoiceLoginSubmit") == null, "unrelated logout leaves normal UI signed in")
	check(int(request("GET","/api/auth/session",token).get("status",0)) == 200 and int(request("GET","/api/auth/session",unrelated).get("status",0)) == 401, "only the explicitly logged-out token was revoked")
	await workbench_logout(token)
	check(str(pc.pentest_ui.get("portal_session", "")).is_empty() and pc.pentest_ui.get("portal_user",{}).is_empty(), "workbench logout of current token clears normal identity")
	check(not bool(service().get("session_checked",true)) and service().get("invoices",[]).is_empty() and service().get("invoice",{}).is_empty() and service().get("events",[]).is_empty(), "workbench logout invalidates normal business cache")
	await press("PentestTab_portal")
	check(control("InvoiceLoginSubmit") != null and control("InvoiceLogout") == null and control("InvoiceTable") == null, "normal tab shows login and no stale invoice list")
	check(int(request("GET","/api/auth/session",token).get("status",0)) == 401, "current token is revoked by persisted workbench logout")
	var fresh := await login()
	check(not fresh.is_empty() and fresh != token, "normal UI can log in again after workbench logout")

func run() -> void:
	if not await setup(): check(false,"recovery setup"); finish(); return
	var older_login := request("POST","/api/auth/login","",{"username":"alice","password":"Alice-demo-27"})
	var older_token := str(older_login.get("data",{}).get("session",""))
	var token := await login()
	if token.is_empty(): finish(); return
	await failed_logout(token)
	await resume_retry(token)
	await cache_invalidation(token,older_token)
	finish()

func finish() -> void:
	if game != null and not save_path.is_empty(): game.save_path = save_path
	print("INVOICE_UI_RECOVERY_PASS assertions="+str(assertions) if failures.is_empty() else "INVOICE_UI_RECOVERY_FAIL count="+str(failures.size())+" assertions="+str(assertions))
	quit(0 if failures.is_empty() else 1)
