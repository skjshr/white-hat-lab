extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var assertions := 0
var narrow := false
var capture_enabled := false

func _init() -> void:
	narrow = "--narrow" in OS.get_cmdline_user_args()
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	create_timer(90).timeout.connect(func(): push_error("service workflows timeout"); quit(2))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); print("FAIL ", message)

func frames(count := 3) -> void:
	for _i in count: await process_frame

func control(id: String):
	return pc.widgets.browser.page.find_child(id, true, false)

func press(id: String) -> void:
	var node = control(id)
	check(node is BaseButton and not node.disabled, "available action " + id)
	if node is BaseButton and not node.disabled: node.pressed.emit()

func edit(id: String, value: String) -> void:
	var node = control(id)
	check(node is LineEdit, "editable field " + id)
	if node is LineEdit: node.text = value; node.text_changed.emit(value)

func choose(id: String, value: String) -> void:
	var node = control(id)
	check(node is OptionButton, "option " + id)
	if not node is OptionButton: return
	for index in node.item_count:
		if str(node.get_item_metadata(index)) == value: node.select(index); node.item_selected.emit(index); return
	check(false, "option value " + value)

func setup_case(case_id: String, url: String) -> void:
	ui._new_game(); game.set_process(false); game.choose_strategy("advisory")
	if case_id.is_empty(): check(game.accept_mission(), "Samba tutorial accepted")
	else:
		game.state.peak_profit = 200000; game.state.profit = 1000000; game.state.cash = 100000
		game.state.skills = {"operations":10, "advisory":10, "response":10}
		check(game.start_free_career(), "career fixture")
		game._update_growth()
		var offer_id := ""
		for day in 60:
			game.state.day = day + 1; game._make_offers()
			for offer in game.state.offers:
				if str(offer.get("case_id", "")) == case_id and bool(offer.get("market_available", false)): offer_id = str(offer.id); break
			if not offer_id.is_empty(): break
		check(not offer_id.is_empty() and game.choose_contract(offer_id), "explicit ordinary contract " + case_id)
	check(game.vm_run("ssh client").contains("Authenticated"), "customer connected")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "text_scale":1.3 if narrow else 1.0, "window_mode":"windowed", "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	ui.open_panel("terminal"); pc = ui.desktop; pc._show_app("browser")
	await frames()
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	pc._browse_url(url, false)
	await frames()

func reload_session() -> void:
	check(game.save_game() and game.load_game(), "real save and reload")
	game.set_process(false); pc._load_session()

func reveal(id: String) -> void:
	await frames(5)
	var node = control(id)
	if not node is Control: return
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is ScrollContainer and parent.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: break
		parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(node)
	await frames()

func capture(name: String, focus: String) -> void:
	await reveal(focus)
	var node = control(focus)
	if node is Control and narrow:
		var bounds: Rect2 = pc.windows.browser.get_global_rect()
		check(node.get_global_rect().position.x >= bounds.position.x - 2 and node.get_global_rect().end.x <= bounds.end.x + 2, "narrow horizontal bounds " + focus)
	if not capture_enabled: return
	await frames(5); await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../../audit/all-services/basic")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + name)

func samba() -> void:
	await setup_case("", "http://files01.client.test:9090")
	pc._browse_url(pc.SAMBA_URL, false); await frames()
	press("SambaShare_share"); press("SambaWorkspaceAccess")
	edit("SambaProbeUser", "staff"); choose("SambaProbeOperation", "put")
	edit("SambaProbeFile", "workflow-copy.csv"); edit("SambaProbeLocal", "/srv/data/orders.csv")
	var original: String = game.vm_read("/srv/data/orders.csv")
	press("SambaProbeRun")
	check(not bool(pc.samba_ui.probe_result.ok) and str(pc.samba_ui.probe_result.output).contains("ACCESS_DENIED"), "staff denial uses actual ACL")
	check(not game._vm().state.fs.has("/srv/share/workflow-copy.csv"), "denied write leaves target absent")
	await capture("samba-access-denied", "SambaProbeResult")
	press("SambaWorkspaceConfig")
	edit("SambaWriteList", "staff"); edit("SambaValidUsers", "staff")
	var guest = control("SambaGuest"); guest.button_pressed = false; guest.toggled.emit(false)
	press("SambaSave"); press("SambaRestart"); press("SambaWorkspaceAccess")
	check(str(control("SambaProbeFile").text) == "workflow-copy.csv", "access input survives ACL edit and restart")
	var before: Dictionary = game._vm().export_state()
	var save_path: String = game.save_path
	game.save_path = "user://missing-service-" + str(OS.get_process_id()) + "/save.json"
	press("SambaProbeRun"); game.save_path = save_path
	check(not bool(pc.samba_ui.probe_result.ok) and str(pc.samba_ui.probe_result.output).contains("save_failed"), "failed persistence reported beside access action")
	check(game._vm().export_state() == before, "failed transfer rolls back exact VM")
	check(str(control("SambaProbeLocal").text) == "/srv/data/orders.csv", "failed transfer retains source")
	press("SambaProbeRun")
	check(bool(pc.samba_ui.probe_result.ok) and game.vm_read("/srv/share/workflow-copy.csv") == original, "retry uploads exact bytes")
	choose("SambaProbeOperation", "get"); edit("SambaProbeLocal", "/home/operator/workflow-copy.csv"); press("SambaProbeRun")
	check(control("SambaProbeContent") is TextEdit and control("SambaProbeContent").text == original, "real downloaded bytes visible")
	await reload_session(); pc._render_samba(); await frames()
	check(control("SambaProbeContent") is TextEdit and control("SambaProbeContent").text == original, "reopen retains measured bytes and selected workspace")
	edit("SambaProbeUser", ""); press("SambaProbeRun")
	check(not bool(pc.samba_ui.probe_result.ok), "guest is denied after ACL repair")
	edit("SambaProbeUser", "staff"); press("SambaProbeRun")
	check(bool(pc.samba_ui.probe_result.ok), "normal staff read remains available")
	await capture("samba-access-result", "SambaProbeResult")

func tree_item(item: TreeItem, path: String) -> TreeItem:
	if str(item.get_metadata(0)) == path: return item
	var child := item.get_first_child()
	while child != null:
		var found := tree_item(child, path)
		if found != null: return found
		child = child.get_next()
	return null

func select_file(path: String) -> void:
	var tree = control("BackupSnapshotTree")
	var item := tree_item(tree.get_root(), path)
	check(item != null, "snapshot contains selected file")
	if item != null: item.select(0); tree.item_selected.emit()
	await frames()

func backup() -> void:
	await setup_case("service-1-case-3", "http://backup01.client.test:9898")
	pc._browse_url(pc.BACKUP_URL, false); await frames()
	press("BackupSnapshot_00000001"); await select_file("/srv/data/ledger.txt")
	check(control("BackupPreview") is TextEdit and control("BackupCurrentPreview") is TextEdit, "saved and live bytes shown together")
	var saved: String = control("BackupPreview").text
	check(saved != control("BackupCurrentPreview").text and str(control("BackupComparisonStatus").text).contains("異なり"), "earlier recovery point differs from damaged live file")
	await capture("backup-content-comparison", "BackupContentComparison")
	press("BackupRestoreToPath"); press("BackupPreviewChanges")
	var before: Dictionary = game._vm().export_state()
	var save_path: String = game.save_path
	game.save_path = "user://missing-backup-workflow-" + str(OS.get_process_id()) + "/save.json"
	press("BackupExecuteRestore"); game.save_path = save_path
	check(game._vm().export_state() == before and str(pc.backup_ui.restore_result) == "failed", "restore failure rolls back and shows result")
	press("BackupPreviewChanges"); press("BackupExecuteRestore")
	check(game.vm_read("/restore/srv/data/ledger.txt") == saved, "retry restores selected version bytes")
	press("BackupCloseRestore"); press("BackupCompareRestored")
	check(str(control("BackupComparisonStatus").text).contains("内容が一致"), "restore comparison verifies actual destination")
	check(control("BackupCurrentPreview").text == saved, "restored bytes visible")
	await reload_session(); pc._render_backup(); await frames()
	check(str(pc.backup_ui.get("snapshot", "")) == "00000001" and str(control("BackupComparisonStatus").text).contains("内容が一致"), "saved selected recovery point and comparison survive reopen")
	await capture("backup-restored-comparison", "BackupContentComparison")
	press("BackupCompareLive")
	check(control("BackupCurrentPreview").text != saved, "restore preview distinguishes original damaged live file")

func firewall() -> void:
	await setup_case("service-2-case-0", "https://firewall.client.test")
	pc._browse_url(pc.FIREWALL_URL, false); await frames()
	check(not game.vm_run("curl https://intranet.client.test").contains("200"), "accepted DNS incident affects actual business request")
	press("FirewallNav_services"); choose("FirewallDNS", "on"); press("FirewallServicesSave"); press("FirewallApply"); press("FirewallNav_rules")
	check(game.vm_run("curl https://intranet.client.test").contains("200"), "DNS UI repair restores actual business request")
	# Exercise ordered-rule editing on the currently available contract. This
	# deliberate temporary rule change is test setup, not a retired market offer.
	press("FirewallEdit_wan-admin"); choose("FirewallEditor_action", "pass"); press("FirewallSave"); press("FirewallApply")
	check(control("FirewallRuleTrace") != null, "rule list includes real traffic workspace")
	press("FirewallTraceReplay")
	check(str(game._vm().firewall_snapshot().last_trace.action) == "pass", "default normal LAN request passes")
	press("FirewallTraceEdit"); choose("FirewallTrace_interface", "wan")
	edit("FirewallTrace_source", "203.0.113.10"); edit("FirewallTrace_destination", "198.51.100.1"); edit("FirewallTrace_destination_port", "8443")
	press("FirewallTraceRun"); press("FirewallNav_rules")
	check(str(game._vm().firewall_snapshot().last_trace.rule_id) == "wan-admin", "external trace reports real first matching rule")
	press("FirewallEdit_wan-admin"); choose("FirewallEditor_action", "block"); press("FirewallSave")
	press("FirewallTraceReplay")
	check(str(game._vm().firewall_snapshot().last_trace.action) == "pass", "pending edit does not change actual trace")
	press("FirewallApply")
	check(str(control("FirewallTraceContextStatus").text).contains("再検査"), "stale result explicitly distinguished after apply")
	press("FirewallTraceReplay")
	check(str(game._vm().firewall_snapshot().last_trace.action) == "block", "same external request is blocked after apply")
	check(game.vm_run("curl https://intranet.client.test").contains("200"), "normal business remains available")
	if narrow:
		check(control("FirewallRoute_wan-admin") != null and control("FirewallRuleTable").horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "narrow rules show readable route cards")
	await capture("firewall-rule-trace", "FirewallRule_wan-admin")
	await reload_session(); pc._render_firewall(); await frames()
	check(not str(control("FirewallTraceContextStatus").text).contains("再検査"), "reopen retains valid measured-policy association")
	press("FirewallTraceReplay")
	check(str(game._vm().firewall_snapshot().last_trace.action) == "block", "reopened request replays against saved policy")

func run() -> void:
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames(1)
	game = ui._game(); game.set_process(false)
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	await samba(); await backup(); await firewall()
	print("SERVICE_WORKFLOWS assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
