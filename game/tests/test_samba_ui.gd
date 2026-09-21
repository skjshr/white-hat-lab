extends SceneTree

const CONFIG_PATH := "/etc/samba/smb.conf"
const SHARE_PATH := "/srv/share"
const SOURCE_PATH := "/srv/data/orders.csv"
const REMOTE_NAME := "orders-upload.csv"
const REMOTE_PATH := SHARE_PATH + "/" + REMOTE_NAME
const REPORT_PATH := SHARE_PATH + "/report.txt"
const COPY_PATH := "/home/operator/smb-report-copy.txt"

var ui
var game
var pc
var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func(): push_error("Samba UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func browser_control(id: String):
	if pc == null or not pc.widgets.has("browser"):
		return null
	var page = pc.widgets.browser.get("page")
	return page.find_child(id, true, false) if page != null else null

func network_control(id: String):
	if pc == null or not pc.widgets.has("files"):
		return null
	var network = pc.widgets.files.get("network")
	return network.find_child(id, true, false) if network != null else null

func press_browser(id: String) -> void:
	var node = browser_control(id)
	check(node is BaseButton and not node.disabled, "browser button " + id)
	if node is BaseButton and not node.disabled:
		node.pressed.emit()

func press_network(id: String) -> void:
	var node = network_control(id)
	check(node is BaseButton and not node.disabled, "network button " + id)
	if node is BaseButton and not node.disabled:
		node.pressed.emit()

func select_network(id: String, index: int) -> void:
	var node = network_control(id)
	check(node is OptionButton, "network option " + id)
	if node is OptionButton and index >= 0 and index < node.item_count:
		node.select(index)
		node.item_selected.emit(index)

func edit_browser(id: String, value: String) -> void:
	var node = browser_control(id)
	check(node is LineEdit or node is TextEdit, "browser field " + id)
	if node is LineEdit:
		node.text = value
		node.text_changed.emit(value)
	elif node is TextEdit:
		node.text = value
		node.text_changed.emit()

func edit_network(id: String, value: String) -> void:
	var node = network_control(id)
	check(node is LineEdit or node is TextEdit, "network field " + id)
	if node is LineEdit:
		node.text = value
		node.text_changed.emit(value)
	elif node is TextEdit:
		node.text = value
		node.text_changed.emit()

func set_check(id: String, value: bool) -> void:
	var node = browser_control(id)
	check(node is BaseButton, "checkbox " + id)
	if node is BaseButton:
		if bool(node.button_pressed) != value:
			node.button_pressed = value
			node.emit_signal("toggled", value)

func frames(count: int = 4) -> void:
	for _i in count:
		await process_frame

func capture(label: String) -> void:
	if not capture_enabled:
		return
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/experience/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func smb_output() -> String:
	return str(pc.samba_ui.get("access_output", ""))

func run() -> void:
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(1)
	game = ui._game()
	game.set_process(false)
	# Never let a normal player save or settings file be touched by this UI test.
	if not game.save_path.begins_with("user://qa-") or not game.settings_path.begins_with("user://qa-"):
		push_error("Refusing Samba UI test without isolated storage")
		quit(2)
		return

	# The first tutorial uses the real v2 Samba host with staff read / guest write
	# as the incident state, so both the unsafe guest access and staff write denial
	# are observable before the repair.
	ui._new_game()
	game.choose_strategy("advisory")
	check(game.accept_mission(), "first Samba tutorial accepted")
	check(int(game._vm().state.get("samba_model_version", 0)) == 2, "fresh Samba model v2")
	check(game.vm_run("ssh client").contains("Authenticated"), "customer shell connected")
	check(game.capture_baseline(), "Samba baseline captured")

	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	ui.open_panel("terminal")
	pc = ui.desktop
	pc._show_app("browser")
	await frames()
	if not pc.windows.browser.maximized:
		pc.windows.browser.toggle_maximize()
	check(str(game.work_guidance().get("app",""))=="browser","first share job guidance opens its actual console")
	pc._open_guidance()
	check(pc.browser_url==pc.SAMBA_URL,"first share job guidance resolves Cockpit")
	await frames()
	check(pc._samba_v2(), "Samba console route is v2")
	check(browser_control("SambaShare_share") != null, "share list has real share")
	await capture("samba-console")
	press_browser("SambaShare_share")
	await frames()
	check(browser_control("SambaSave") != null, "share editor save control")
	check(browser_control("SambaTest") == null and browser_control("SambaRestart") == null, "test and restart hidden before pending change")
	await capture("samba-editor")

	# Exercise the network panel through the actual Files UI, before changing the
	# share. Staff is read-only while the seeded guest access can list the share.
	pc._open_samba_share("share")
	await frames()
	check(pc.widgets.files.has("network"), "Files app has SMB network widget")
	if not pc.windows.files.maximized:
		pc.windows.files.toggle_maximize()
	await frames()
	select_network("SmbUser", 0)
	press_network("SmbUploadOpen")
	edit_network("SmbSource", SOURCE_PATH)
	edit_network("SmbRemoteName", REMOTE_NAME)
	press_network("SmbUpload")
	check(smb_output().contains("ACCESS_DENIED"), "initial staff upload denied")
	check(not game._vm().state.fs.has(REMOTE_PATH), "denied staff upload does not create file")
	select_network("SmbUser", 1)
	press_network("SmbRefresh")
	await frames()
	check(pc.samba_ui.get("access_files", []).size() > 0, "initial guest listing allowed")
	check(network_control("SmbFile_report_txt") != null, "guest sees real report file")

	# Configure the existing share in the real editor. The pending disk text is
	# intentionally different from applied state until service restart.
	pc._show_app("browser")
	pc._browse_url(pc.SAMBA_URL, false)
	await frames()
	press_browser("SambaShare_share")
	await frames()
	var raw_config := str(game._vm().state.fs.get(CONFIG_PATH, ""))
	var preserved_config := raw_config + "\n# preserve this administrator note\n[archive]\n    path = /srv/share\n    read only = yes\n"
	check(game.vm_write(CONFIG_PATH, preserved_config), "existing raw Samba config change accepted")
	pc._render_samba()
	await frames()
	set_check("SambaAvailable", true)
	set_check("SambaReadOnly", true)
	set_check("SambaGuest", false)
	edit_browser("SambaPath", SHARE_PATH)
	edit_browser("SambaValidUsers", "staff")
	edit_browser("SambaInvalidUsers", "")
	edit_browser("SambaWriteList", "staff")
	edit_browser("SambaReadList", "")
	press_browser("SambaSave")
	await frames()
	check(bool(game._vm().state.get("dirty", false)), "Samba save stages dirty config")
	check(str(game._vm().state.applied.get("staff", "")) == "read" and str(game._vm().state.applied.get("guest", "")) == "write", "Samba applied state unchanged before restart")
	check(str(game._vm().state.fs.get(CONFIG_PATH, "")).contains("write list = staff") and str(game._vm().state.fs.get(CONFIG_PATH, "")).contains("preserve this administrator note") and str(game._vm().state.fs.get(CONFIG_PATH, "")).contains("[archive]"), "Samba pending config preserves unrelated text")
	check(browser_control("SambaTest") != null and browser_control("SambaRestart") != null, "test and restart visible with pending change")
	press_browser("SambaTest")
	await frames()
	var testparm: String = str(pc.samba_ui.get("output", ""))
	check(testparm.contains("Loaded services") or testparm.contains("OK"), "testparm accepts staged Samba config")
	await capture("samba-pending")
	press_browser("SambaRestart")
	await frames()
	check(not bool(game._vm().state.get("dirty", false)) and str(game._vm().state.applied.get("staff", "")) == "write" and str(game._vm().state.applied.get("guest", "")) == "none", "restart applies staff write and guest denial")

	# Staff can now upload the real source bytes; the guest request is denied and
	# must clear the old listing/preview instead of displaying stale files.
	pc._show_app("files")
	await frames()
	select_network("SmbUser", 0)
	press_network("SmbUploadOpen")
	edit_network("SmbSource", SOURCE_PATH)
	edit_network("SmbRemoteName", REMOTE_NAME)
	press_network("SmbUpload")
	check(smb_output().contains("OK"), "authorized staff upload succeeds")
	check(str(game._vm().state.fs.get(REMOTE_PATH, "")) == str(game._vm().state.fs.get(SOURCE_PATH, "")), "SMB upload preserves exact source bytes")
	select_network("SmbUser", 1)
	press_network("SmbRefresh")
	await frames()
	check(smb_output().contains("ACCESS_DENIED"), "guest listing denied after restart")
	check(pc.samba_ui.get("access_files", []).is_empty() and str(pc.samba_ui.get("access_preview", "")).is_empty(), "denied SMB request clears stale listing and preview")
	await capture("samba-guest-denied")

	# Read and preview are served by SMB get against the actual remote bytes.
	select_network("SmbUser", 0)
	press_network("SmbRefresh")
	await frames()
	check(network_control("SmbFile_report_txt") != null, "staff sees real report file")
	press_network("SmbFile_report_txt")
	press_network("SmbDownloadOpen")
	edit_network("SmbDestination", COPY_PATH)
	press_network("SmbDownload")
	check(smb_output().contains("OK") and str(game._vm().state.fs.get(COPY_PATH, "")) == str(game._vm().state.fs.get(REPORT_PATH, "")), "SMB download preserves real bytes")
	var preview = network_control("SmbPreview")
	check(preview is TextEdit and str(preview.text) == str(game._vm().state.fs.get(REPORT_PATH, "")), "SMB preview reads real bytes")
	await capture("samba-authorized")

	# Keep an unsaved editor draft separate from the Files access identity, then
	# persist/reopen the desktop session and verify both pieces independently.
	pc._show_app("browser")
	pc._browse_url(pc.SAMBA_URL, false)
	await frames()
	press_browser("SambaShare_share")
	await frames()
	edit_browser("SambaWriteList", "staff nobody")
	pc._show_app("files")
	await frames()
	select_network("SmbUser", 0)
	check(game.save_game() and game.load_game(), "Samba session save and reload")
	pc._load_session()
	pc._show_app("browser")
	pc._render_samba()
	pc._show_app("files")
	pc._render_smb()
	await frames()
	check(str(browser_control("SambaWriteList").text) == "staff nobody", "Samba editor draft survives reload")
	var reloaded_user = network_control("SmbUser")
	check(reloaded_user is OptionButton and reloaded_user.selected == 0, "SMB access user survives separately")
	check(str(game._vm().state.applied.get("staff", "")) == "write" and str(game._vm().state.applied.get("guest", "")) == "none", "reload keeps applied Samba policy")

	# A valid editor change must still roll back the VM, clock, revision, and
	# editor draft when the enclosing game save cannot create its target path.
	pc._show_app("browser")
	pc._browse_url(pc.SAMBA_URL, false)
	await frames()
	press_browser("SambaShare_share")
	await frames()
	edit_browser("SambaReadList", "staff")
	var config_before_failure: Dictionary = game._vm().state.fs.duplicate(true)
	var clock_before_failure := int(game.clock_minutes())
	var revision_before_failure := int(game.state.revision)
	var valid_save_path := str(game.save_path)
	game.save_path = "user://qa-samba-save-failure-" + str(OS.get_process_id()) + "/save.json"
	var failed_save: bool = pc._samba_save("share", {"read list":"staff"})
	game.save_path = valid_save_path
	check(not failed_save, "Samba save failure is reported")
	check(game._vm().state.fs == config_before_failure and int(game.clock_minutes()) == clock_before_failure and int(game.state.revision) == revision_before_failure, "failed Samba save rolls back VM, clock, and revision")
	check(str(browser_control("SambaReadList").text) == "staff", "failed Samba save preserves editor draft")

	# A valid SMB upload must roll back its remote bytes and work time when the
	# enclosing game save fails. Normal access-denied requests remain real work.
	pc._show_app("files")
	await frames()
	select_network("SmbUser", 0)
	press_network("SmbUploadOpen")
	edit_network("SmbSource", SOURCE_PATH)
	edit_network("SmbRemoteName", "failed-upload.csv")
	var failed_upload_clock := int(game.clock_minutes())
	game.save_path = "user://qa-samba-upload-failure-" + str(OS.get_process_id()) + "/save.json"
	var failed_upload: bool = pc._smb_put(SOURCE_PATH, "failed-upload.csv")
	game.save_path = valid_save_path
	check(not failed_upload and not game._vm().state.fs.has(SHARE_PATH + "/failed-upload.csv") and int(game.clock_minutes()) == failed_upload_clock, "failed SMB upload rolls back without time charge")

	# Use the production diagnostics and delivery gate after the UI flow.
	pc._show_app("browser")
	for _round in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
				game.run_diagnostic(str(probe.get("id", "")))
	game.verify()
	check(game.can_deliver(), "Samba diagnostics and verification pass")
	check(game.deliver(), "Samba tutorial delivers after real UI repair")
	for failure in failures:
		push_error("SAMBA_UI: " + failure)
	print("SAMBA_UI failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
