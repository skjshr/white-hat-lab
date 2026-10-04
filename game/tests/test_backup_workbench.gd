extends SceneTree

## Focused integration regression for the direct-object route. The labelled
## eligibility fixture does not create money, successful checks or repaired VM
## contents. Control signals exercise callbacks here; native input is covered
## separately by test_backup_recovery_ui.gd.
const CASE_ID := "service-1-case-3"
const LEDGER := "/srv/data/ledger.txt"
const CUSTOMERS := "/srv/data/customers.csv"
const RECOVERED := "/restore/srv/data/ledger.txt"
var game
var ui
var pc
var good_id := ""
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("backup workbench integration timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL backup_workbench: ", label)

func frames(count := 4) -> void:
	for _index in count: await process_frame

func wire(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func projection() -> Dictionary:
	return {"vm":game._vm().export_state(),"work":game.state.work.duplicate(true),"clock":game.clock_minutes(),"revision":game.state.revision,"validated":game.state.validated_revision,"checks":game.state.checks.duplicate(true),"cash":game.state.cash,"history":game.state.history.duplicate(true)}

func control(id: String) -> Node:
	if not is_instance_valid(pc) or not pc.widgets.has("browser"): return null
	var page: Node = pc.widgets.browser.get("page")
	return page.find_child(id,true,false) if is_instance_valid(page) else null

func metadata(id: String, key: String) -> Variant:
	var node := control(id)
	check(node != null and node.has_meta(key), "metadata " + id + "/" + key)
	return node.get_meta(key) if node != null and node.has_meta(key) else null

func text_of(id: String) -> String:
	var node := control(id)
	check(node is Label or node is TextEdit or node is LineEdit, "text control " + id)
	return str(node.text) if node is Label or node is TextEdit or node is LineEdit else ""

func press(id: String) -> void:
	var node := control(id) as BaseButton
	check(node != null and not node.disabled, "enabled action " + id)
	if node != null and not node.disabled: node.pressed.emit()
	await frames()

func tree_path(item: TreeItem, path: String) -> TreeItem:
	if item == null: return null
	if str(item.get_metadata(0)) == path: return item
	var child := item.get_first_child()
	while child != null:
		var found := tree_path(child,path)
		if found != null: return found
		child = child.get_next()
	return null

func choose_file(path: String) -> bool:
	var tree := control("BackupSnapshotTree") as Tree
	check(tree != null,"existing file chooser is available")
	if tree == null: return false
	var item := tree_path(tree.get_root(),path)
	check(item != null,"actual file is present in snapshot: " + path)
	if item == null: return false
	item.select(0)
	tree.item_selected.emit()
	await frames()
	return true

func plan_cards(node: Node) -> Array:
	var result: Array = []
	if node.has_meta("restore_entry"): result.append(node.get_meta("restore_entry"))
	for child in node.get_children(): result.append_array(plan_cards(child))
	return result

func passive_render(label: String) -> void:
	var before := wire(projection())
	var before_ui := wire(pc.backup_ui)
	for _index in 3:
		pc._render_backup()
		await frames()
	check(wire(projection()) == before,label + " does not mutate VM, work, time, checks or money")
	check(wire(pc.backup_ui) == before_ui,label + " does not manufacture inspected content or a confirmed plan")

func setup_case() -> bool:
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames()
	game = ui._game(); game.set_process(false)
	if not game.save_path.begins_with("user://qa-") or not game.settings_path.begins_with("user://qa-"):
		push_error("Refusing backup workbench test without isolated storage"); return false
	ui._new_game()
	check(int(game.state.cash) == 5000,"ordinary initial funds")
	check(game.choose_strategy("operations"),"choose public operations strategy")
	game.state.peak_profit = 35000
	game.state.skills.operations = 2
	check(game.start_free_career(),"enter ordinary contract market with labelled Lv.7/operations2 eligibility")
	var offer: Dictionary = {}
	for _day in 14:
		for candidate in game.state.offers:
			if str(candidate.get("case_id","")) == CASE_ID and bool(candidate.get("unlocked",false)) and bool(candidate.get("market_available",false)):
				offer = candidate; break
		if not offer.is_empty(): break
		check(game.end_day(),"advance actual market day")
	check(not offer.is_empty(),"representative case offered by actual market")
	if offer.is_empty(): return false
	check(game.set_offer_plan("standard"),"select public standard plan")
	check(game.set_offer_quote(str(offer.id),int(game.contract_quote(offer).reference_fee)),"submit actual quote")
	check(game.choose_contract(str(offer.id)),"accept actual backup contract")
	check(game.state.targets.size() == 1,"exactly one actual target")
	game.inspect_mission()
	check(game.vm_run("ssh client").contains("Authenticated"),"connect through actual VM command")
	var expected := str(game._vm().state.backup_authorization.expected_files[LEDGER])
	for snapshot in game._vm().state.snapshots:
		if str(snapshot.repository) == "offsite" and str(snapshot.files.get("ledger.txt","")).sha256_text() == expected: good_id = str(snapshot.id)
	check(not good_id.is_empty(),"actual snapshot bytes match authoritative customer ledger hash")
	if good_id.is_empty(): return false
	game.set_settings({"resolution":"1920x1080","window_mode":"windowed","text_scale":1.0,"volume":0},false)
	root.size = Vector2i(1920,1080)
	ui.open_panel("terminal"); pc = ui.desktop
	pc._show_app("browser"); pc._browse_url(pc.BACKUP_URL,true)
	await frames()
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	await frames()
	return true

func run() -> void:
	if not await setup_case(): await finish(); return
	check(control("BackupWorkbench") == null,"no workbench before explicit file selection")
	await press("BackupSnapshot_" + good_id)
	if not await choose_file(LEDGER): await finish(); return
	check(control("BackupWorkbench") != null,"selected required file enters workbench")
	await passive_render("selected-file rendering")
	var before_plan := wire(projection())
	await press("BackupRestoreToPath")
	check(wire(projection()) == before_plan,"preparing actual single-file plan is read-only")
	check(pc.backup_ui.restore_plan.entries.size() == 1,"selected-file preview contains exactly one real entry")
	await press("BackupExecuteRestore")
	check(game.vm_read(RECOVERED).sha256_text() == str(game._vm().state.backup_authorization.expected_files[LEDGER]),"UI confirmation restores actual authorized ledger bytes")
	check(str(metadata("BackupRecoveryGuard","state")) == "matched","ledger tray reflects actual ledger acceptance")

	# A valid ledger does not authorize a green result on a different selected file.
	await press("BackupFileToggle")
	if not await choose_file(CUSTOMERS): await finish(); return
	check(bool(game._vm().backup_acceptance_view().restore_valid),"ledger remains valid for this wrong-object regression")
	check(not game._vm().state.fs.has("/restore/srv/data/customers.csv"),"other selected file has not been restored")
	check(control("BackupWorkbench") == null and control("BackupContentComparison") != null,"non-required file keeps ordinary console instead of a falsely matched tray")
	if not await choose_file(LEDGER): await finish(); return

	# Build and persist the real old-console all-file preview. It must remain a
	# full plan after reopen, even though a required file is already selected.
	await press("BackupFileToggle")
	await press("BackupRestore")
	await press("BackupPreviewChanges")
	var all_entries: Array = pc.backup_ui.restore_plan.entries.duplicate(true)
	check(all_entries.size() > 1 and str(pc.backup_ui.restore_scope) == "all","actual legacy preview includes multiple files")
	pc._save_session(false)
	check(game.save_game() and game.load_game(),"save and reopen existing all-file preview")
	await frames()
	pc = ui.desktop; pc._load_session(); pc._render_backup()
	await frames()
	check(str(pc.backup_ui.path) == LEDGER and bool(pc.backup_ui.restore_open),"reopened plan retains selected file and open confirmation")
	check(control("BackupWorkbench") == null,"saved all-file confirmation does not become a one-sheet workbench")
	var cards := plan_cards(pc.widgets.browser.page)
	check(cards.size() == all_entries.size(),"every entry of saved all-file plan remains visible in full-plan UI")
	for entry in all_entries:
		check(cards.any(func(card): return str(card.source) == str(entry.source) and str(card.path) == str(entry.path)),"full preview retains actual source and target " + str(entry.source))
	await passive_render("reopened full-plan rendering")
	await press("BackupCloseRestore")
	# The explicit File route also retains its existing selected-file form after
	# a real successful write. Only the workbench returns directly to its tray.
	await press("BackupRestoreToPath")
	var legacy_destination := control("BackupDestination") as LineEdit
	check(legacy_destination != null,"legacy selected-file form exposes its destination")
	if legacy_destination == null: await finish(); return
	legacy_destination.text = "/restore/legacy-copy"
	legacy_destination.text_changed.emit(legacy_destination.text)
	await press("BackupPreviewChanges")
	check(str(pc.backup_ui.restore_scope) == "selected" and pc.backup_ui.restore_plan.entries.size() == 1,"legacy confirmation has a real single-file plan")
	await press("BackupExecuteRestore")
	check(game._vm().state.fs.has("/restore/legacy-copy/srv/data/ledger.txt") and str(pc.backup_ui.restore_result) == "succeeded","legacy selected-file action actually writes its new destination")
	check(control("BackupWorkbench") == null and bool(pc.backup_ui.restore_open),"successful legacy selected-file restore retains its open confirmation")
	check(control("BackupCloseRestore") is BaseButton,"legacy selected-file continuation retains CloseRestore")
	await press("BackupCloseRestore")
	if not await choose_file(LEDGER): await finish(); return

	# Alternate destination is an actual write; the tray must follow its per-file
	# provenance and cannot borrow success from the earlier /restore copy.
	await press("BackupRestoreToPath")
	await press("BackupRestoreSettings")
	var destination := control("BackupDestination") as LineEdit
	check(destination != null,"destination setting is available")
	if destination == null: await finish(); return
	destination.text = "/restore-other"; destination.text_changed.emit(destination.text)
	check((control("BackupExecuteRestore") as BaseButton).disabled,"destination change invalidates old confirmation")
	await press("BackupPreviewChanges")
	check(text_of("BackupPlanRoute") == "/restore-other/srv/data/ledger.txt","preview uses actual alternate target")
	await press("BackupExecuteRestore")
	check(game._vm().state.fs.has("/restore-other/srv/data/ledger.txt"),"alternate destination was actually written")
	check(str(metadata("BackupDestinationTray","destination")) == "/restore-other/srv/data/ledger.txt","tray follows actual per-file restore path")
	check(text_of("BackupDestinationLabel") == "/restore-other/srv/data","tray label describes its real directory")
	check(str(metadata("BackupRecoveryGuard","state")) != "matched","outside-authorized destination is not green despite an earlier valid copy")

	# Cause a real restic read failure through an invalid saved configuration,
	# then inspect the existing sheet. Cache must not override that read failure.
	var config_path := str(game._vm().state.config_path)
	var valid_config: String = game.vm_read(config_path)
	check(game.vm_write(config_path,"schedule=invalid\nrepository=offsite\n"),"write explicit service-error configuration")
	check(game.vm_run("systemctl restart restic").begins_with("Job failed") and not bool(game._vm().state.active),"real service restart fails")
	pc._render_backup(); await frames()
	await press("BackupSnapshot_" + good_id)
	var failed_doc: Variant = metadata("BackupSnapshot_" + good_id,"document")
	check(failed_doc is Dictionary and str(failed_doc.kind) == "unread" and bool(failed_doc.get("read_error",false)),"failed explicit dump remains unread even with old valid cache")
	check(not bool(metadata("BackupSnapshot_" + good_id,"observed")),"failed read has no current observation seal")
	if not bool(pc.backup_ui.get("content_details",false)): await press("BackupContentDetails")
	check(text_of("BackupPreview").contains("service configuration failed"),"details retain actual dump failure")
	check(not text_of("BackupPreview").contains("opening=50000"),"details do not disclose raw snapshot bytes after failed read")
	await passive_render("failed-inspection rendering")
	check(game.vm_write(config_path,valid_config),"restore real valid configuration")
	check(game.vm_run("systemctl restart restic").contains("active (running)"),"recover service through real restart")

	# Labelled stale desktop-cache fixture only; VM snapshots remain untouched.
	var cache_key := JSON.stringify(["offsite",good_id,LEDGER])
	pc.backup_ui.inspected_files[cache_key] = "STALE_UI_CACHE_SENTINEL"
	pc.backup_ui.erase("preview")
	pc._render_backup(); await frames()
	var stale_doc: Variant = metadata("BackupSnapshot_" + good_id,"document")
	check(stale_doc is Dictionary and str(stale_doc.kind) == "unread","stale cache does not become a current candidate")
	check(text_of("BackupPreview") == "未確認","details reject stale cache bytes as well")
	await passive_render("stale-cache rendering")
	await press("BackupSnapshot_" + good_id)
	check(bool(metadata("BackupSnapshot_" + good_id,"observed")),"new successful real dump refreshes inspected candidate")
	check(text_of("BackupPreview").contains("opening=50000"),"details show actual bytes only after successful read")
	await finish()

func finish() -> void:
	if is_instance_valid(ui): ui.queue_free(); await frames()
	print("BACKUP_WORKBENCH_INTEGRATION ",JSON.stringify({"assertions":assertions,"failures":failures.size(),"details":failures}))
	quit(0 if failures.is_empty() else 1)
