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
	create_timer(70.0).timeout.connect(func(): push_error("linked identity UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func control(id: String):
	if pc == null or not pc.widgets.has("browser"): return null
	var page = pc.widgets.browser.get("page")
	return page.find_child(id, true, false) if page != null else null

func press(id: String) -> void:
	var node = control(id)
	check(node is BaseButton and not node.disabled, "button "+id)
	if node is BaseButton and not node.disabled: node.pressed.emit()

func frames(count: int = 5) -> void:
	for _index in count: await process_frame

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(8)
	await RenderingServer.frame_post_draw
	var suffix := "-narrow" if narrow else "-wide"
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label+suffix+".png")) == OK, "capture "+label)

func select_target(index: int) -> void:
	var selector: OptionButton = pc.target_selector
	check(selector != null and selector.item_count > index, "target selector includes target "+str(index))
	if selector != null and selector.item_count > index:
		selector.select(index)
		selector.item_selected.emit(index)
		await frames(10)

func select_identity(identity_id: String) -> void:
	var selector = control("PortalIdentity")
	check(selector is OptionButton, "portal identity selector")
	if not selector is OptionButton: return
	var found := -1
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == identity_id:
			found = index
			break
	check(found >= 0, "portal identity "+identity_id+" is selectable")
	if found >= 0:
		selector.select(found)
		selector.item_selected.emit(found)
		await frames(6)

func response() -> String:
	return str(pc.portal_ui.get("response", ""))

func _json(raw: String) -> Dictionary:
	var value = JSON.parse_string(raw)
	return value if value is Dictionary else {}

func _capture_composite() -> bool:
	var composite: Dictionary = {}
	for day_index in 60:
		game.state.day = day_index + 1
		game._make_offers()
		for offer_value in game.state.offers:
			if offer_value is Dictionary and bool(offer_value.get("market_available", false)) and str(offer_value.get("case_id", "")) == "composite-former-access":
				composite = offer_value
				break
		if not composite.is_empty(): break
	check(not composite.is_empty(), "composite former access lead available")
	if composite.is_empty(): return false
	var id := str(composite.get("id", ""))
	var reward := int(composite.get("reward", composite.get("base_reward", 0)))
	check(game.set_offer_quote(id, reward), "composite quote saved through production API")
	check(game.choose_contract(id), "composite accepted through production API")
	return bool(game.state.accepted) and game.state.targets.size() >= 2

func run() -> void:
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(2)
	game = ui._game()
	game.set_process(false)
	if not game.save_path.begins_with("user://qa-") or not game.settings_path.begins_with("user://qa-"):
		push_error("Refusing linked identity UI test without isolated QA storage")
		quit(2)
		return
	check(ui._new_game(), "new company through interface")
	check(game.choose_strategy("operations"), "operations strategy")
	game.state.skills = {"operations": 10, "advisory": 10, "response": 10}
	game.state.profit = 1000000
	game.state.peak_profit = 1000000
	check(game.start_free_career(), "career fixture")
	if not await _capture_composite():
		_finish()
		return
	game.vm_run("ssh client")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	capture_dir = ProjectSettings.globalize_path("res://../artifacts/simulator/linked-identity/ui")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	ui.open_panel("terminal")
	pc = ui.desktop
	await frames(10)
	pc._show_app("browser")
	await frames(4)
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()

	# Target 1 is the linked portal.  Select the former session through the
	# actual preview selector and prove it can read before Keycloak logout.
	await select_target(1)
	pc._run_command("ssh client")
	pc._show_app("browser")
	await frames(4)
	pc._browse_url(pc.PORTAL_URL, true)
	await frames(8)
	press("PortalFile_0")
	await frames(4)
	press("PortalPreview")
	await frames(5)
	press("PortalRole_staff")
	await frames(4)
	await select_identity("former-seed-1")
	press("PortalRead")
	await frames(8)
	check(response().begins_with("HTTP/1.1 200"), "former linked session reads portal before logout")
	check(str(pc.browser_identity) == "former-seed-1", "former session is actual selected identity")
	await capture("portal-former-before-logout")

	# Target 0 is the linked identity provider.  Logout is initiated from its
	# rendered session row, so the provider callback and VM transaction are real.
	await select_target(0)
	pc._run_command("ssh client")
	pc._show_app("browser")
	pc._browse_url(pc.IDENTITY_URL, true)
	await frames(8)
	check(control("IdentityUser_former") != null and control("IdentityUser_current") != null, "linked users rendered")
	press("IdentityUser_former")
	await frames(4)
	press("IdentityTab_sessions")
	await frames(4)
	check(control("IdentityLogout_former-seed-1") != null, "former session logout control rendered")
	press("IdentityLogout_former-seed-1")
	await frames(8)
	var provider_sessions: Dictionary = game._vm().identity_snapshot()
	var former_revoked := false
	for session_value in provider_sessions.get("sessions", []):
		if session_value is Dictionary and str(session_value.get("id", "")) == "former-seed-1": former_revoked = bool(session_value.get("revoked", false))
	check(former_revoked, "Keycloak logout callback revokes former session")
	await capture("identity-former-logout")

	# Return to the portal target.  The same selector callback now returns 401
	# for the former session, while the current linked session remains usable.
	await select_target(1)
	pc._run_command("ssh client")
	pc._show_app("browser")
	pc._browse_url(pc.PORTAL_URL, true)
	await frames(8)
	press("PortalFile_0")
	await frames(4)
	press("PortalPreview")
	await frames(5)
	press("PortalRole_staff")
	await frames(4)
	await select_identity("former-seed-1")
	press("PortalRead")
	await frames(8)
	check(response().begins_with("HTTP/1.1 401"), "former linked session denied after logout")
	await capture("portal-former-after-logout")
	await select_identity("current-seed-1")
	press("PortalRead")
	await frames(8)
	check(response().begins_with("HTTP/1.1 200"), "current linked session remains usable")
	check(str(pc.browser_identity) == "current-seed-1", "current session is actual selected identity")
	await capture("portal-current-after-logout")

	# Persist the current session ID through the desktop session and a real save
	# reload, then restore the portal preview without direct state mutation.
	check(pc._save_session() and game.save_game(), "selected linked identity saved")
	check(game.load_game(), "saved linked identity game reload")
	pc._load_session()
	check(str(pc.browser_identity) == "current-seed-1", "selected linked identity restored after reload")
	pc._render_portal()
	await frames(6)
	var restored = control("PortalIdentity")
	check(restored is OptionButton, "portal selector restored after reload")
	if restored is OptionButton:
		var restored_current := false
		for index in restored.item_count:
			if str(restored.get_item_metadata(index)) == "current-seed-1" and restored.selected == index: restored_current = true
		check(restored_current, "current session remains selected in restored portal UI")

	_finish()

func _finish() -> void:
	for failure in failures: push_error(failure)
	print("LINKED_IDENTITY_UI failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
