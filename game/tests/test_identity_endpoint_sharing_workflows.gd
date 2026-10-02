extends SceneTree
const SHARING = preload("res://scripts/os_portal_console.gd")
var ui
var game
var pc
var failures: Array[String] = []
var assertions := 0
var capture_enabled := "--capture" in OS.get_cmdline_user_args()
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(160.0).timeout.connect(func(): push_error("identity endpoint sharing workflows timeout"); quit(2))
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures.append(message); print("FAIL ", message)
func frames(count := 4) -> void:
	for _index in count: await process_frame
func control(id: String): return pc.widgets.browser.page.find_child(id, true, false)
func press(id: String) -> void:
	var item = control(id)
	check(item is BaseButton and not item.disabled, "enabled " + id)
	if item is BaseButton and not item.disabled: item.pressed.emit()
func choose(id: String, index: int) -> void:
	var item = control(id)
	check(item is OptionButton, "select " + id)
	if item is OptionButton: item.select(index); item.item_selected.emit(index)
func visible_without_scroll(id: String) -> void:
	if not capture_enabled: return
	await frames(6)
	var target := pc.find_child(id, true, false) as Control
	var visible := is_instance_valid(target) and target.is_visible_in_tree()
	if visible:
		var bounds := target.get_global_rect()
		visible = Rect2(Vector2.ZERO, Vector2(root.size)).encloses(bounds)
		var ancestor: Node = target.get_parent()
		while ancestor != null:
			if ancestor is Control and ancestor.clip_contents: visible = visible and ancestor.get_global_rect().encloses(bounds)
			ancestor = ancestor.get_parent()
	check(visible, id + " fully visible without helper scrolling")
func capture(label: String, reveal := "", reset_scroll := true) -> void:
	if not capture_enabled: return
	await frames(6)
	if pc.current_app == "browser":
		var scroll: ScrollContainer = pc.widgets.browser.page.get_parent()
		if reveal.is_empty() and reset_scroll: scroll.scroll_vertical = 0
		await frames(3)
		check(pc.widgets.browser.page.get_global_rect().end.x <= root.size.x + 2, label + " fits width")
	if not reveal.is_empty():
		var target: Node = pc.find_child(reveal, true, false)
		if target is Control:
			var ancestor: Node = target.get_parent()
			while ancestor != null:
				if ancestor is ScrollContainer: ancestor.ensure_control_visible(target); await frames(3)
				ancestor = ancestor.get_parent()
			check(target.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(root.size))), label + " target reachable")
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("WHL_CAPTURE_DIR")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../../audit/all-services/identity-endpoint-sharing-" + ("narrow" if narrow else "wide") + "/screens")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "capture " + label)
func start(chapter: int) -> void:
	if is_instance_valid(ui): ui.queue_free(); await frames()
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames(1)
	game = ui._game(); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"), "isolated QA profile")
	ui._new_game(); game.choose_strategy("operations"); game.accept_mission()
	var case_id := "service-%d-case-0" % chapter
	game.state.targets = [{"chapter":chapter, "case_id":case_id, "name":"workflow"}]
	game.state.target_index = 0; game.state.chapter = chapter; game.state.contract = {"case_id":case_id}
	game.state.accepted = true; game.state.vm_states = {}; game._machine = null
	game.vm_run("ssh client")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080); ui._set_text_scale(1.3)
	ui.open_panel("terminal"); pc = ui.desktop; pc._show_app("browser"); await frames()
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	pc._browse_url(["", "", "", pc.IDENTITY_URL, pc.EDR_URL, pc.PORTAL_URL][chapter], true); await frames()

func identity() -> void:
	await start(3); press("IdentityUser_former")
	await visible_without_scroll("IdentitySave")
	await capture("00-identity-entry", "", false)
	check(control("IdentityAccountLifecycle") != null, "account lifecycle separates new login and existing sessions")
	press("IdentityLoginAs_former"); control("IdentityLoginPassword").text = "Training-117!"; press("IdentitySignIn")
	if control("IdentityOtp") is LineEdit: control("IdentityOtp").text = "123456"; press("IdentityVerifyOtp")
	var session_id := str(pc.identity_ui.get("token", ""))
	check(not session_id.is_empty(), "actual login issues session")
	press("IdentityView_users"); press("IdentityUser_former")
	var toggle = control("IdentityEnable")
	if toggle is CheckBox: toggle.button_pressed = false; toggle.toggled.emit(false)
	press("IdentityTab_sessions"); press("IdentityTab_details")
	check(not control("IdentityEnable").button_pressed, "unsaved account choice survives navigation")
	press("IdentitySave")
	await visible_without_scroll("IdentityActionFeedback")
	await capture("00b-identity-account-saved", "", false)
	check(not bool(game._vm().identity_snapshot().users[0].enabled), "save changes actual account")
	press("IdentityTab_sessions"); press("IdentitySessionAccess_" + session_id)
	check(bool(pc.identity_ui.output.get("ok", false)), "account stop leaves already-issued session usable")
	check(control("IdentityActionFeedback").text.contains("アクセス成功"), "access result describes real response")
	check(control("IdentityActionFeedback").text.contains(session_id), "result retains the tested session identity")
	await visible_without_scroll("IdentityActionFeedback")
	await capture("01a-identity-result-visible", "", false)
	await capture("01-identity-session-before", "IdentitySessionAccess_" + session_id)
	press("IdentityLogout_" + session_id)
	check(control("IdentitySessionResult_" + session_id).text.begins_with("変更前"), "revocation makes prior observation stale")
	check(control("IdentityLogout_" + session_id).disabled, "revoked row remains without reactivation")
	press("IdentitySessionAccess_" + session_id)
	check(not bool(pc.identity_ui.output.get("ok", true)) and str(pc.identity_ui.output.get("error", "")) == "revoked_session", "revoked session denies actual access")
	await capture("02-identity-session-revoked", "IdentitySessionResult_" + session_id)
	press("IdentityLoginAs_former"); check(control("IdentityLoginUser").text == "former", "selected person opens actual login")
	pc._show_app("monitor"); await frames()
	await capture("02b-monitor-entry", "", false)
	var open = pc.widgets.monitor.body.find_child("ServiceOpenWorkspace", true, false)
	check(open is BaseButton, "monitor routes to dedicated workspace")
	if open is BaseButton: open.pressed.emit()
	check(pc.current_app == "browser" and pc.browser_url == pc.IDENTITY_URL, "monitor opens correct console")

func endpoint() -> void:
	await start(4); await capture("02c-edr-entry", "", false)
	press("EdrDevice_pc_b"); await capture("02d-edr-device", "", false)
	press("EdrBusinessProbe_pc_b")
	check(str(pc.edr_ui.business_observations.pc_b.response).begins_with("HTTP/1.1 200"), "normal endpoint GET succeeds")
	press("EdrIsolate_pc_b")
	check(control("EdrBusinessResult_pc_b").text.begins_with("変更前"), "isolation invalidates prior normal observation")
	press("EdrBusinessProbe_pc_b")
	check(str(pc.edr_ui.business_observations.pc_b.response).begins_with("HTTP/1.1 403"), "isolation blocks actual business GET")
	check(control("EdrBusinessResult_pc_b").text.contains("業務接続は拒否"), "business refusal has operational meaning")
	await visible_without_scroll("EdrBusinessResult_pc_b")
	await capture("03a-edr-result-visible", "", false)
	await capture("03-edr-isolated", "EdrBusinessVerification")
	press("EdrRelease_pc_b"); press("EdrBusinessProbe_pc_b")
	check(str(pc.edr_ui.business_observations.pc_b.response).begins_with("HTTP/1.1 200"), "release restores actual business GET")
	check(str(pc.edr_ui.business_observations.pc_b.previous).begins_with("HTTP/1.1 403"), "recovery retains previous refusal")
	press("EdrRefresh_pc_b")
	check(str(pc.edr_ui.device) == "pc_b" and control("EdrBusinessResult_pc_b") != null, "refresh preserves selected device and observation")
	await capture("04-edr-recovered", "EdrBusinessVerification")

func share_form(permission: int) -> void:
	press("PortalNav_all")
	if control("PortalShare_partner") == null: press("PortalShareFile_0")
	if control("PortalPermission_partner") == null: press("PortalShare_partner")
	choose("PortalPermission_partner", permission); choose("PortalExpiry_partner", 1)

func sharing() -> void:
	await start(5)
	await capture("04a-sharing-entry", "", false)
	var original: String = game.vm_read("/srv/share/partner-order.csv")
	share_form(1); press("PortalShare_partner"); press("PortalShare_partner")
	check(control("PortalPermission_partner").get_selected_id() == 1 and control("PortalExpiry_partner").selected == 1, "permission and expiry draft survive editor close")
	await capture("05-sharing-draft", "PortalApply_partner")
	var paths: Array = [game.save_path, game.backup_path, game.previous_path, game.settings_path]
	var before: Dictionary = game._vm().state.applied.duplicate(true)
	game.save_path = "user://missing-sharing-workflow-" + str(OS.get_process_id()) + "/save.json"
	game.backup_path = game.save_path + ".bak"; game.previous_path = game.save_path + ".previous"; game.settings_path = game.save_path + ".settings"
	press("PortalApply_partner")
	check(not bool(pc.portal_ui.command_result.get("ok", true)) and game._vm().state.applied == before, "save failure leaves real grant unchanged")
	check(control("PortalPermission_partner").get_selected_id() == 1 and control("PortalShareDraft_partner").text.contains("未保存"), "save failure preserves permission draft for retry")
	game.save_path = paths[0]; game.backup_path = paths[1]; game.previous_path = paths[2]; game.settings_path = paths[3]
	press("PortalApply_partner"); check(str(game._vm().state.applied.partner) == "read", "share save changes actual grant")
	press("PortalPreview"); choose("PortalIdentity", 2); press("PortalRead")
	check(str(pc.portal_ui.response).begins_with("HTTP/1.1 200"), "partner loads real document")
	press("PortalEditRows")
	var cell = control("PortalCell_1_1"); check(cell is LineEdit, "direct table input exists")
	if cell is LineEdit: cell.text = "新規, 顧客 \"確認\""; cell.text_changed.emit(cell.text)
	var draft: String = str(pc.portal_ui.preview_content)
	check(SHARING._csv_rows(draft)[1][1] == "新規, 顧客 \"確認\"", "CSV input preserves comma and quote")
	press("PortalWrite")
	check(str(pc.portal_ui.response).begins_with("HTTP/1.1 403") and game.vm_read("/srv/share/partner-order.csv") == original, "read-only submission leaves actual bytes unchanged")
	check(str(pc.portal_ui.preview_content) == draft and bool(pc.portal_ui.draft_dirty), "denial retains draft for retry")
	check(control("PortalResponseStatus").text.contains("提出できませんでした") and control("PortalResponseStatus").text.contains("入力は保持"), "submission denial explains retained draft")
	await visible_without_scroll("PortalResponseStatus")
	await capture("06a-sharing-result-visible", "", false)
	await capture("06-sharing-denied", "PortalEditRows")
	await capture("06b-sharing-table", "PortalEntryTable")
	share_form(2); press("PortalApply_partner"); press("PortalPreview"); choose("PortalIdentity", 2); press("PortalRead")
	check(str(pc.portal_ui.preview_content) == draft, "return to same recipient restores submission draft")
	press("PortalWrite")
	check(str(pc.portal_ui.response).begins_with("HTTP/1.1 200") and game.vm_read("/srv/share/partner-order.csv") == draft, "permitted submission updates actual bytes")
	check(not bool(pc.portal_ui.draft_dirty), "successful submission clears draft")
	check(control("PortalResponseStatus").text.contains("提出しました"), "successful real PUT confirms submission")
	var snapshot: Dictionary = game._vm().portal_snapshot()
	check(snapshot.get("versions", []).size() >= 1 and snapshot.get("activity", []).size() >= 1, "submission creates version and activity")
	choose("PortalAge", 1); press("PortalRead")
	check(str(pc.portal_ui.response).begins_with("HTTP/1.1 410"), "real link expires")
	await capture("07-sharing-expired", "PortalRead")
	choose("PortalAge", 0); press("PortalRead"); await capture("08-sharing-submitted", "PortalEditRows")
	press("PortalNav_all"); press("PortalShareFile_0"); press("PortalDetailVersions")
	await capture("09-sharing-history", "PortalDetailVersions")
	pc._show_app("verify"); await frames()
	if not pc.windows.verify.maximized: pc.windows.verify.toggle_maximize()
	await capture("09a-diagnostics-entry", "", false)
	var mode = pc.widgets.verify.left.find_child("DiagnosticMode_http", true, false)
	check(mode is BaseButton, "HTTP workspace available")
	if not mode is BaseButton: return
	mode.pressed.emit()
	var url = pc.widgets.verify.right.find_child("DiagnosticRequestUrl", true, false)
	url.text = "https://portal.client.test/partner?link=current"; url.text_changed.emit(url.text)
	var auth = pc.widgets.verify.right.find_child("DiagnosticRequestIdentity", true, false)
	auth.select(2); auth.item_selected.emit(2)
	var configuration: Dictionary = game._vm().state.applied.duplicate(true)
	pc.widgets.verify.right.find_child("DiagnosticRequestRun", true, false).pressed.emit()
	check(pc.diagnostic_ui.observations.size() == 1 and str(pc.diagnostic_ui.observations[0].response).contains(draft), "custom GET observes actual submitted file")
	check(game._vm().state.applied == configuration, "HTTP test changes no policy")
	check(pc.widgets.verify.right.find_child("DiagnosticObservation_0", true, false).text.contains("読み込み成功"), "HTTP result explains response without claiming mission success")
	await visible_without_scroll("DiagnosticObservation_0")
	await capture("09b-diagnostics-result-visible", "", false)
	pc.widgets.verify.right.find_child("DiagnosticReplay_0", true, false).pressed.emit()
	check(pc.diagnostic_ui.observations.size() == 2, "captured GET can be replayed")
	url = pc.widgets.verify.right.find_child("DiagnosticRequestUrl", true, false)
	url.text = "not a URL"; pc.widgets.verify.right.find_child("DiagnosticRequestRun", true, false).pressed.emit()
	check(pc.diagnostic_ui.observations.size() == 2 and not str(pc.diagnostic_ui.get("error", "")).is_empty(), "invalid request preserves editable draft and observations")
	url = pc.widgets.verify.right.find_child("DiagnosticRequestUrl", true, false)
	url.text = "https://portal.client.test/partner?link=current"; url.text_changed.emit(url.text)
	pc.widgets.verify.right.find_child("DiagnosticRequestRun", true, false).pressed.emit()
	pc._save_session(false); check(game.save_game(), "desktop workflow saved")
	var saved: Dictionary = pc.diagnostic_ui.duplicate(true)
	pc.diagnostic_ui = {}; pc._load_session()
	check(pc.diagnostic_ui == saved, "request draft and observations restore from session")
	pc.widgets.verify.signature = ""; pc._refresh_checks(); await capture("10-diagnostic-requests")
	await capture("10b-diagnostic-observation", "DiagnosticObservation_2")

func run() -> void:
	await identity(); await endpoint(); await sharing()
	print("IDENTITY_ENDPOINT_SHARING_WORKFLOWS_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " failures=", failures.size(), " scale=1.3 narrow=", narrow)
	quit(0 if failures.is_empty() else 1)
