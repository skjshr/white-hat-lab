extends SceneTree

const INTERFACE = preload("res://scripts/interface.gd")
const ROUTES := [
	{"initial":"https://files.client.test/guest/report.txt", "label":"社員", "target":"https://files.client.test/staff/report.txt"},
	{"initial":"https://intranet.client.test", "label":"社内ポータル", "target":"https://intranet.client.test"},
	{"initial":"https://intranet.client.test", "label":"管理", "target":"https://admin.client.test"},
	{"initial":"https://identity.client.test/current/login", "label":"退職", "target":"https://identity.client.test/former/login"},
	{"initial":"https://edr.client.test/pc-a/outbound", "label":"PC-B", "target":"https://edr.client.test/pc-b/business"},
	{"initial":"https://portal.client.test/staff", "label":"取引先", "target":"https://portal.client.test/partner"}
]
const APPLIED := [
	{"staff":"write", "guest":"none"},
	{"schedule":"daily", "repository":"offsite"},
	{"dns":"on", "business":"allow", "admin_public":"deny", "tls":"on"},
	{"former":"disabled", "sessions":"revoked", "current":"active", "mfa":"on"},
	{"pc_a":"isolated", "pc_b":"connected", "logs":"keep", "reset":"wait"},
	{"staff":"write", "partner":"read", "public":"none", "expires":"7d", "mfa":"on", "tls":"on", "audit":"on"}
]

var failures: Array[String] = []

func _init() -> void:
	for chapter in ROUTES.size():
		await _check_chapter(chapter)
	for failure in failures: push_error(failure)
	print("PASS: browser service routes, responses, and history" if failures.is_empty() else "FAIL count=%d" % failures.size())
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

func _check_chapter(chapter: int) -> void:
	var ui = INTERFACE.new()
	root.add_child(ui)
	await process_frame
	var game = ui._game()
	var suffix := "browser-%d-%d" % [OS.get_process_id(),chapter]
	game.save_path = "user://%s.json" % suffix
	game.backup_path = "user://%s.json.bak" % suffix
	game.previous_path = "user://%s.previous.json" % suffix
	game.settings_path = "user://%s-settings.json" % suffix
	ui._new_game()
	game.choose_strategy("operations")
	game.accept_mission()
	var case_id := "service-%d-case-0" % chapter
	game.state.targets = [{"chapter":chapter, "case_id":case_id, "name":"browser-site"}]
	game.state.target_index = 0
	game.state.chapter = chapter
	game.state.contract = {"case_id":case_id}
	game.state.accepted = true
	game.state.vm_states = {}
	game._machine = null
	game.vm_run("ssh client")
	game.vm_write(game.vm_info().config_path,game._vm().configuration_text(APPLIED[chapter]))
	game.vm_run("systemctl restart "+str(game.vm_info().service))
	if chapter == 2:
		var legacy_network: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../artifacts/simulator/v124/legacy-v123-firewall.json")))
		game._vm().setup(2,legacy_network)
		game.state.vm_states[game._vm_key()]=game._vm().export_state()
	if chapter == 5:
		# Retain the released HTTP page coverage; test_portal_ui covers the new Files console.
		var legacy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../artifacts/simulator/v123/legacy-v122-portal.json")))
		game._vm().setup(5,legacy)
		game.state.vm_states[game._vm_key()]=game._vm().export_state()
	ui.open_panel("terminal")
	await process_frame
	var pc = ui.desktop
	pc._show_app("browser")
	await process_frame
	var route: Dictionary = ROUTES[chapter]
	pc._browse_url(str(route.initial), true)
	await process_frame
	var nav_button: Button = _find_button(pc.widgets.browser.page, str(route.label))
	_assert(nav_button != null, "chapter %d renders route button %s" % [chapter, route.label])
	if nav_button != null:
		nav_button.pressed.emit()
		await process_frame
		_assert(pc.browser_url == str(route.target), "chapter %d uses existing browser route" % chapter)
		_assert(pc.browser_history.has(str(route.target)), "chapter %d records browser history" % chapter)
		var response := str(game.vm_run("curl "+str(route.target)))
		_assert(response.begins_with("HTTP/") or response.begins_with("curl:"), "chapter %d exposes real VM response" % chapter)
	if chapter == 5:
		_assert(pc.widgets.browser.has("account"), "new portal exposes access-test sessions")
		pc.widgets.browser.account.select(1); pc.widgets.browser.account.item_selected.emit(1)
		_assert(_page_text(pc.widgets.browser.page).contains("要追加認証"), "password-only session displays MFA requirement")
		pc.widgets.browser.account.select(2); pc.widgets.browser.account.item_selected.emit(2)
		_assert(_page_text(pc.widgets.browser.page).contains("HTTP 200"), "verified partner reads the actual document")
		pc.widgets.browser.link.select(1); pc.widgets.browser.link.item_selected.emit(1)
		_assert(_page_text(pc.widgets.browser.page).contains("共有リンク期限切れ"), "eight-day link expires under seven-day policy")
		pc._browser_back()
		_assert(_page_text(pc.widgets.browser.page).contains("HTTP 200") and pc.widgets.browser.link.selected == 0, "browser back restores live link and selected age")
		pc._save_session(); pc.browser_identity=""; pc._load_session()
		_assert(pc.browser_identity == "partner-mfa-session", "session selection survives desktop state persistence")
	ui.free()
	await process_frame

func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and str(child.text) == text: return child
		var nested := _find_button(child, text)
		if nested != null: return nested
	return null

func _page_text(node: Node) -> String:
	var result := str(node.text) if node is Label else ""
	for child in node.get_children(): result += "\n"+_page_text(child)
	return result

func _assert(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
