extends SceneTree

const FILE := "/srv/share/partner-order.csv"
const ORIGINAL := "order,customer,total\n501,101,12800\n"
const UPDATED := "order,customer,total\n501,101,43210\n"
const UI = preload("res://scripts/ui_theme.gd")
var ui
var game
var pc
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(100.0).timeout.connect(func(): push_error("branch UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 4) -> void:
	for _i in count: await process_frame

func control(id: String):
	return pc.widgets.browser.page.find_child(id, true, false)

func press(id: String) -> void:
	var node = control(id)
	check(node is BaseButton and not node.disabled, "button " + id)
	if node is BaseButton and not node.disabled: node.pressed.emit()

func select(id: String, index: int) -> void:
	var node = control(id)
	check(node is OptionButton and index >= 0 and index < node.item_count, "option " + id)
	if node is OptionButton and index >= 0 and index < node.item_count:
		node.select(index)
		node.item_selected.emit(index)

func identity(token: String) -> void:
	var node = control("PortalIdentity")
	if node is OptionButton:
		for i in node.item_count:
			if str(node.get_item_metadata(i)) == token:
				select("PortalIdentity", i)
				return
	check(false, "identity " + token)

func field(id: String, value: String) -> void:
	var node = control(id)
	check(node is LineEdit, "field " + id)
	if node is LineEdit: node.text = value; node.text_changed.emit(value)

func toggle(id: String, value: bool) -> void:
	var node = control(id)
	check(node is BaseButton, "toggle " + id)
	if node is BaseButton and bool(node.button_pressed) != value:
		node.button_pressed = value
		node.toggled.emit(value)

func target(chapter: int) -> int:
	for i in game.state.targets.size():
		if int(game.state.targets[i].chapter) == chapter: return i
	return -1

func connect_target(index: int) -> void:
	check(pc._select_target(index), "switch customer target")
	check(game.vm_run("ssh client").contains("Authenticated"), "connect customer target")

func browse(url: String) -> void:
	pc._show_app("browser")
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	pc._browse_url(url, true)
	await frames(6)

func find_file(name_text: String):
	for button in pc.widgets.browser.page.find_children("PortalFile_*", "Button", true, false):
		if str(button.text) == name_text: return button
	return null

func share(role: String, permission: int, expiry: int) -> void:
	press("PortalNav_all")
	if control("PortalShare_" + role) == null: press("PortalShareFile_0")
	if control("PortalPermission_" + role) == null: press("PortalShare_" + role)
	select("PortalPermission_" + role, permission)
	select("PortalExpiry_" + role, expiry)
	press("PortalApply_" + role)

func response() -> String:
	return str(pc.portal_ui.get("response", ""))

func snap(label: String, visible_id: String = "") -> void:
	if not capture_enabled: return
	await frames(6)
	var scroll: ScrollContainer = pc.widgets.browser.page.get_parent()
	if not visible_id.is_empty() and control(visible_id) != null:
		scroll.ensure_control_visible(control(visible_id))
	else: scroll.scroll_vertical = 0
	await frames(3)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/branch/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func edit_visible_csv(value: String) -> void:
	var editor = control("PortalContent")
	check(editor is TextEdit, "recipient source editor exists")
	if not editor is TextEdit: return
	var body: Node = editor.get_parent()
	var disclosure: Node = body.get_parent().get_child(body.get_index() - 1)
	check(disclosure is Button, "source disclosure button")
	if disclosure is Button and not body.visible: disclosure.pressed.emit()
	await frames(2)
	check(editor.is_visible_in_tree(), "source editor disclosed")
	editor.text = value
	editor.text_changed.emit()

func run() -> void:
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(2)
	game = ui._game()
	game.set_process(false)
	if not game.save_path.begins_with("user://qa-") or not game.settings_path.begins_with("user://qa-"):
		push_error("Refusing branch test without isolated storage"); quit(2); return
	check(ui._new_game(), "new QA game")
	check(game.choose_strategy("advisory") and game.start_free_career(), "free career")
	# Only unlock the market fixture; no completion or validation state is seeded.
	game.state.skills.advisory = 3
	game.state.skills.operations = 3
	game.state.skills.response = 3
	game.state.profit = 200000
	game.state.peak_profit = 200000
	game._update_growth()
	var offer: Dictionary = {}
	for day in 60:
		game.state.day = day + 1
		game._make_offers()
		for item in game.state.offers:
			if str(item.get("case_id", "")) == "composite-branch-reopen" and bool(item.get("market_available", false)):
				offer = item; break
		if not offer.is_empty(): break
	check(not offer.is_empty(), "branch offer available")
	if offer.is_empty(): quit(1); return
	check(game.choose_contract(str(offer.id)), "branch contract accepted")
	var gateway := target(2)
	var samba := target(0)
	var portal := target(5)
	check(gateway >= 0 and samba >= 0 and portal >= 0, "three branch machines")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1280, 720)
	ui.open_panel("terminal")
	pc = ui.desktop
	await frames(4)
	connect_target(gateway)
	var policy: String = game._vm().configuration_text({"dns":"on", "business":"allow", "admin_public":"deny", "tls":"on"})
	check(game.vm_write(str(game.vm_info().config_path), policy), "gateway staged")
	check(game.vm_run("systemctl restart firewall").contains("active"), "gateway applied")
	await browse("https://intranet.client.test/sales")
	check(pc.browser_response.contains("503") and pc.browser_response.contains("provider_unavailable"), "orders fail while the source share is unavailable")
	await snap("orders-before-repair")
	connect_target(portal)
	await browse(pc.PORTAL_URL)
	check(control("BranchStorageError") != null, "Nextcloud shows mounted storage failure")
	check(find_file("partner-order.csv") == null, "Nextcloud does not show stale local file")
	await snap("storage-before-repair", "BranchStorageError")
	connect_target(samba)
	await browse(pc.SAMBA_URL)
	press("SambaShare_share")
	toggle("SambaAvailable", true)
	toggle("SambaReadOnly", true)
	toggle("SambaGuest", false)
	field("SambaPath", "/srv/share")
	field("SambaValidUsers", "staff")
	field("SambaInvalidUsers", "")
	field("SambaWriteList", "staff")
	field("SambaReadList", "")
	press("SambaSave")
	press("SambaTest")
	press("SambaRestart")
	check(game.vm_read(FILE) == ORIGINAL, "repair preserves customer data")
	await snap("share-repaired")
	connect_target(portal)
	await browse(pc.PORTAL_URL)
	var file = find_file("partner-order.csv")
	check(file is Button, "Nextcloud lists mounted order file")
	if file is Button: file.pressed.emit()
	check(control("BranchStorageError") == null, "Nextcloud mounted storage recovered")
	check(control("PortalAdminContent") is TextEdit and control("PortalAdminContent").text == ORIGINAL, "admin preview reads Samba bytes")
	share("partner", 1, 1)
	share("public", 0, 0)
	press("PortalPreview")
	press("PortalRole_staff")
	identity("staff-session")
	press("PortalRead")
	check(response().begins_with("HTTP/1.1 200") and str(pc.portal_ui.get("preview_content", "")) == ORIGINAL, "staff reads mounted bytes")
	await edit_visible_csv(UPDATED)
	press("PortalWrite")
	check(response().begins_with("HTTP/1.1 200"), "staff updates through Nextcloud")
	press("PortalRead")
	check(str(pc.portal_ui.get("preview_content", "")) == UPDATED, "Nextcloud fresh read sees update")
	await snap("shared-orders-updated", "PortalPreviewGrid")
	press("PortalRole_partner")
	identity("partner-mfa-session")
	press("PortalRead")
	check(response().begins_with("HTTP/1.1 200"), "partner MFA read allowed")
	await edit_visible_csv(ORIGINAL)
	press("PortalWrite")
	check(response().begins_with("HTTP/1.1 403"), "partner remains read-only")
	connect_target(samba)
	check(game.vm_read(FILE) == UPDATED, "same Samba file changed, denied partner write did not overwrite")
	connect_target(gateway)
	await browse("https://intranet.client.test/sales")
	check(pc.browser_response.contains("43210") and control("BusinessOrderList") != null, "Odoo orders read changed source")
	press("BusinessOrderOpen_501")
	check(control("BusinessSelectedOrder") != null, "updated sales record opens")
	await snap("sales-after-update")
	check(game.save_game() and game.load_game(), "linked storage disk reload")
	pc._load_session()
	await browse("https://intranet.client.test/sales")
	check(pc.browser_response.contains("43210"), "orders update survives reload")
	print("BRANCH_WORKFLOW_UI failures=", failures.size())
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
