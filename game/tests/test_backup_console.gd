extends SceneTree

const CATALOG = preload("res://scripts/case_catalog.gd")
const VM = preload("res://scripts/virtual_machine.gd")
const LEDGER_PATH := "/srv/data/ledger.txt"
const RESTORE_PATH := "/restore/srv/data/ledger.txt"

var ui
var game
var pc
var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(55.0).timeout.connect(func(): push_error("backup UI timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func control(id: String):
	if pc == null or not pc.widgets.has("browser"):
		return null
	var page = pc.widgets.browser.get("page")
	return page.find_child(id, true, false) if page != null else null

func press(id: String) -> void:
	var node = control(id)
	check(node is BaseButton and not node.disabled, "button " + id)
	if node is BaseButton and not node.disabled:
		node.pressed.emit()

func select(id: String, index: int) -> void:
	var node = control(id)
	check(node is OptionButton, "option " + id)
	if node is OptionButton and index >= 0 and index < node.item_count:
		node.select(index)
		node.item_selected.emit(index)

func find_tree_path(item: TreeItem, path: String) -> TreeItem:
	if str(item.get_metadata(0)) == path: return item
	var child := item.get_first_child()
	while child != null:
		var found := find_tree_path(child, path)
		if found != null: return found
		child = child.get_next()
	return null

func select_path(path: String) -> void:
	var tree = control("BackupSnapshotTree")
	check(tree is Tree, "snapshot file tree exists")
	if not tree is Tree: return
	var item := find_tree_path(tree.get_root(), path)
	check(item != null, "tree path " + path)
	if item == null: return
	item.select(0)
	tree.item_selected.emit()
	await frames()
	# This suite covers the retained full console. The selected required file
	# now opens its object workbench; use its actual File route to return before
	# continuing the existing full-console assertions. The workbench has its own
	# integration and native input tests.
	if control("BackupWorkbench") != null:
		press("BackupFileToggle")
		await frames()

func review_restore(all_files: bool = true) -> void:
	press("BackupRestore" if all_files else "BackupRestoreToPath")
	await frames()
	press("BackupPreviewChanges")
	await frames()

func frames(count: int = 4) -> void:
	for _i in count:
		await process_frame

func response() -> String:
	return str(pc.backup_ui.get("output", ""))

func failed_save_action(id: String) -> void:
	var before_vm: Dictionary=game._vm().export_state()
	var before_work: Dictionary=game.state.work.duplicate(true)
	var before_clock: int=game.clock_minutes()
	var before_revision: int=game.state.revision
	var before_validated: int=game.state.validated_revision
	var before_checks: Array=game.state.checks.duplicate(true)
	var valid_path: String=game.save_path
	game.save_path="user://qa-backup-save-failure-"+str(OS.get_process_id())+"/save.json"
	press(id)
	game.save_path=valid_path
	check(response().contains("save_failed"),id+" reports persistence failure")
	check(game._vm().export_state()==before_vm,id+" restores all VM data after persistence failure")
	check(game.clock_minutes()==before_clock and game.state.work==before_work,id+" does not charge failed persistence")
	check(game.state.revision==before_revision and game.state.validated_revision==before_validated and game.state.checks==before_checks,id+" preserves validation after failed persistence")

func reveal(id: String) -> void:
	var node = control(id)
	check(node is Control, "reveal control " + id)
	if not node is Control:
		return
	var ancestor: Node = node.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible(node)
		await frames(3)

func assert_bounds(ids: Array[String]) -> void:
	if not narrow:
		return
	var viewport: Rect2 = pc.windows.browser.get_global_rect()
	for id in ids:
		var node = control(id)
		if node is Control and node.visible:
			var rect: Rect2 = node.get_global_rect()
			check(rect.position.x >= viewport.position.x - 2.0 and rect.end.x <= viewport.end.x + 2.0, id + " stays inside narrow browser")

func plan_status(source: String) -> String:
	var plan = pc.backup_ui.get("restore_plan", {})
	if not plan is Dictionary:
		return ""
	for entry in plan.get("entries", []):
		if entry is Dictionary and str(entry.get("source", "")) == source:
			return str(entry.get("status", ""))
	return ""

func capture(label: String) -> void:
	if not capture_enabled:
		return
	await frames(6)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/backup/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func legacy_route() -> void:
	var scenario: Dictionary = CATALOG.by_id("service-1-case-3")
	var source = VM.new()
	source.setup(1, {}, scenario)
	var saved: Dictionary = source.export_state()
	saved.erase("backup_model_version")
	var loaded = VM.new()
	loaded.setup(1, saved, scenario)
	loaded.run("ssh client")
	check(int(loaded.state.get("backup_model_version", 0)) == 1, "legacy backup model retained")
	var result := loaded.run("restic restore latest --target /restore")
	check(result.begins_with("restored") and loaded.state.fs.has("/restore/ledger.txt"), "legacy latest restore route remains usable")

func run() -> void:
	legacy_route()
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(1)
	game = ui._game()
	game.set_process(false)
	if not game.save_path.begins_with("user://qa-") or not game.settings_path.begins_with("user://qa-"):
		push_error("Refusing backup test without isolated storage")
		quit(2)
		return
	ui._new_game()
	check(game.choose_strategy("advisory"), "advisory strategy")
	game.state.peak_profit = 200000
	game.state.profit = 1000000
	game.state.cash = 100000
	game.state.skills = {"operations":10, "advisory":10, "response":10}
	check(game.start_free_career(), "free career")
	var offer: Dictionary = {}
	game._update_growth()
	for day_index in 60:
		game.state.day = day_index + 1
		game._make_offers()
		for item in game.state.offers:
			if str(item.get("case_id", "")) == "service-1-case-3" and bool(item.get("market_available", false)):
				offer = item
				break
		if not offer.is_empty():
			break
	if offer.is_empty():
		push_error("BACKUP_UI: explicit case fixture was not offered")
		quit(1)
		return
	if not game.choose_contract(str(offer.get("id", ""))):
		push_error("BACKUP_UI: explicit case fixture could not be accepted")
		quit(1)
		return
	check(true, "corrupted ledger contract accepted")
	check(int(game._vm().state.get("backup_model_version", 0)) == 2, "fresh backup model v2")
	check(game.vm_run("ssh client").contains("Authenticated"), "customer shell connected")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	ui.open_panel("terminal")
	pc = ui.desktop
	pc._show_app("browser")
	await frames()
	if not pc.windows.browser.maximized:
		pc.windows.browser.toggle_maximize()
	check(str(game.work_guidance().get("app",""))=="browser","backup work guidance opens the existing console")
	pc._open_guidance()
	check(pc.browser_url==pc.BACKUP_URL,"backup guidance resolves Backrest URL")
	await frames()
	var browse_started: int = game.clock_minutes()
	press("BackupRefresh")
	await frames()
	check(response().contains("00000001") and response().contains("00000002"), "real snapshot inventory shows older and latest")
	assert_bounds(["BackupRefresh", "BackupNow", "BackupSnapshotTable"])
	await capture("backup-snapshots")

	# The latest selected snapshot is corrupt; inspect and restore it first so the
	# verification result proves the UI selection is authoritative.
	press("BackupSnapshot_00000002")
	await frames()
	await select_path(LEDGER_PATH)
	await frames()
	check(str(pc.backup_ui.get("snapshot", "")) == "00000002", "latest snapshot selection persists")
	var corrupt_preview = control("BackupPreview")
	check(corrupt_preview is TextEdit and str(corrupt_preview.text).contains("CORRUPTED DATA"), "latest snapshot inspection shows corrupt bytes")
	check(control("BackupDestination") == null, "file inspection does not auto-open restore form")
	check(game.clock_minutes() == browse_started, "snapshot navigation and file inspection do not charge work time")
	await capture("backup-file-browser")
	await review_restore(false)
	assert_bounds(["BackupSnapshotTree", "BackupPreviewChanges", "BackupExecuteRestore", "BackupDestination"])
	await reveal("BackupPreviewChanges")
	var top_scroll: Node = pc.widgets.browser.page.get_parent()
	while top_scroll != null and not top_scroll is ScrollContainer:top_scroll=top_scroll.get_parent()
	if top_scroll is ScrollContainer:top_scroll.scroll_vertical=0
	await capture("backup-selected-preview-top")
	await reveal("BackupPlanEntries")
	await reveal("BackupExecuteRestore")
	assert_bounds(["BackupPreviewChanges", "BackupPlanEntries", "BackupExecuteRestore"])
	await capture("backup-selected-preview-bottom")
	# A destination changed after preview invalidates the plan and cannot charge work.
	var stale_clock: int = game.clock_minutes()
	game._vm().state.fs[RESTORE_PATH] = "EXTERNAL CHANGE\n"
	press("BackupExecuteRestore")
	await frames()
	check(game.clock_minutes() == stale_clock, "stale restore preview does not charge work")
	check(str(pc.backup_ui.get("restore_result", "")) == "preview_stale", "stale restore preview is rejected")
	press("BackupPreviewChanges")
	await frames()
	var restore_started_1: int=game.clock_minutes()
	press("BackupExecuteRestore")
	check(game.clock_minutes()-restore_started_1==15,"repository-selected restore consumes actual restoration work time")
	await frames()
	check(str(game._vm().state.get("last_restore", {}).get("snapshot", "")) == "00000002", "restore uses selected latest snapshot")
	check(str(game._vm().state.fs.get(RESTORE_PATH, "")) == "CORRUPTED DATA\n", "latest restore exposes corrupt bytes")
	for probe in game.diagnostic_probes():
		if str(probe.get("id", "")).begins_with("restore-"):
			game.run_diagnostic(str(probe.id))
	var bad_checks: Array = game.verify()
	check(not bad_checks.all(func(item): return bool(item.passed)), "corrupt restore fails existing diagnostics")

	# Navigate back, choose the older snapshot explicitly, and restore it.
	press("BackupBackSnapshots")
	await frames()
	press("BackupSnapshot_00000001")
	await frames()
	await select_path(LEDGER_PATH)
	await frames()
	var healthy_preview = control("BackupPreview")
	check(healthy_preview is TextEdit and str(healthy_preview.text) == VM.RECORDS["ledger.txt"], "older snapshot inspection shows healthy bytes")
	check(control("BackupDestination") == null, "healthy file inspection leaves restore form closed")
	await review_restore()
	assert_bounds(["BackupPreviewChanges", "BackupExecuteRestore", "BackupDestination"])
	# Never-overwrite preserves an existing corrupt destination while allowing
	# the other files in the all-files plan to proceed.
	game._vm().state.fs[RESTORE_PATH] = "DO NOT OVERWRITE\n"
	select("BackupOverwrite", 1)
	press("BackupPreviewChanges")
	await frames()
	check(plan_status(LEDGER_PATH) == "skipped", "overwrite-never marks corrupt destination skipped")
	press("BackupExecuteRestore")
	await frames()
	check(str(game._vm().state.fs.get(RESTORE_PATH, "")) == "DO NOT OVERWRITE\n", "overwrite-never preserves corrupt destination")
	select("BackupOverwrite", 0)
	press("BackupPreviewChanges")
	await frames()
	failed_save_action("BackupExecuteRestore")
	await frames()
	check(str(pc.backup_ui.get("restore_result", "")) == "failed", "latest failed restore replaces current success state")
	press("BackupPreviewChanges")
	await frames()
	press("BackupExecuteRestore")
	await frames()
	check(str(game._vm().state.get("last_restore", {}).get("snapshot", "")) == "00000001", "restore uses selected older snapshot")
	check(str(game._vm().state.fs.get(RESTORE_PATH, "")) == VM.RECORDS["ledger.txt"], "older restore recovers exact bytes")
	press("BackupCloseRestore")
	await frames()
	await select_path("/srv/data")
	check(str(pc.backup_ui.get("path", "")) == "/srv/data", "folder tree selection stores absolute source path")
	check(str(pc.backup_ui.get("restore_scope", "")) == "selected", "folder tree selection chooses selected scope")
	check(control("BackupDestination") == null, "folder selection does not auto-open restore form")
	await review_restore(false)
	check(pc.backup_ui.get("restore_plan", {}).get("entries", []).size() == 3, "folder restore plan contains all three files")
	press("BackupExecuteRestore")
	await frames()
	check(str(game._vm().state.fs.get("/restore/srv/data/customers.csv", "")) == VM.RECORDS["customers.csv"], "folder restore recovers customers")
	check(str(game._vm().state.fs.get("/restore/srv/data/orders.csv", "")) == VM.RECORDS["orders.csv"], "folder restore recovers orders")
	check(str(game._vm().state.fs.get(RESTORE_PATH, "")) == VM.RECORDS["ledger.txt"], "folder restore recovers ledger")
	for attempt in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
				game.run_diagnostic(str(probe.id))
	game.verify()
	check(game.diagnostic_probes().all(func(item): return bool(item.passed)), "healthy restore passes diagnostics")
	press("BackupOpenFiles")
	await frames()
	check(str(pc.current_app) == "files" and str(pc.file_directory) == "/restore", "open restored target routes to real files app")
	pc._show_app("browser")
	pc._browse_url(pc.BACKUP_URL, true)
	await frames()
	await capture("backup-restore")

	# Repository navigation is a real repository filter: local has no seeded
	# snapshots, then returning to offsite must reveal both original snapshots.
	press("BackupRepo_local")
	await frames()
	press("BackupRefresh")
	await frames()
	check(response().contains("no snapshots") and not response().contains("00000001"), "local repository does not leak offsite snapshots")
	press("BackupRepo_offsite")
	await frames()
	press("BackupRefresh")
	await frames()
	check(response().contains("00000001") and response().contains("00000002"), "offsite repository restores its own inventory")
	# Repository navigation intentionally clears stale selection. Re-select the
	# healthy snapshot and destination before exercising plan and session save.
	press("BackupSnapshot_00000001")
	await frames()
	await select_path(LEDGER_PATH)
	await frames()
	check(str(pc.backup_ui.get("snapshot", "")) == "00000001", "healthy snapshot reselected after repository switch")
	await review_restore()
	var destination = control("BackupDestination")
	check(destination is LineEdit, "restore destination remains editable")
	if destination is LineEdit:
		destination.text = "/restore"
		destination.text_changed.emit(destination.text)

	# Save the plan through the actual console controls, then restore the desired
	# plan. This exercises config write, service restart, and repository state.
	select("BackupSchedule", 0)
	select("BackupPlanRepository", 0)
	press("BackupSavePlan")
	await frames()
	check(str(game._vm().state.applied.get("schedule", "")) == "off" and str(game._vm().state.applied.get("repository", "")) == "local", "plan save applies selected local disabled plan")
	select("BackupSchedule", 1)
	select("BackupPlanRepository", 1)
	press("BackupSavePlan")
	await frames()
	check(str(game._vm().state.applied.get("schedule", "")) == "daily" and str(game._vm().state.applied.get("repository", "")) == "offsite", "plan save restores daily offsite plan")

	failed_save_action("BackupNow")
	var backup_started: int=game.clock_minutes()
	var prior_snapshots: int=game._vm().state.snapshots.size()
	press("BackupNow")
	await frames()
	check(game.clock_minutes()-backup_started==12 and game._vm().state.snapshots.size()==prior_snapshots+1,"repository-selected backup consumes backup work time and creates real snapshot")

	var saved_bytes := str(game._vm().state.fs.get(RESTORE_PATH, ""))
	var saved_snapshot := str(pc.backup_ui.get("snapshot", ""))
	var saved_destination := str(pc.backup_ui.get("destination", ""))
	check(saved_snapshot == "00000001" and saved_destination == "/restore", "selected healthy snapshot and destination ready for save")
	check(game.save_game() and game.load_game(), "backup session save and reload")
	pc._load_session()
	pc._render_backup()
	await frames()
	check(str(game._vm().state.fs.get(RESTORE_PATH, "")) == saved_bytes, "restored bytes survive reload")
	check(str(pc.backup_ui.get("snapshot", "")) == saved_snapshot and str(pc.backup_ui.get("destination", "")) == saved_destination, "selected snapshot and destination survive reload")
	for failure in failures:
		push_error("BACKUP_UI: " + failure)
	print("BACKUP_UI failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
