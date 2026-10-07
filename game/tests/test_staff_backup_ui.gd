extends SceneTree
## Focused route, read-only and report-viewer integration for the backup workday card.

const CASE_ID := "service-1-case-0"
const INTERFACE := preload("res://scripts/interface.gd")

var game
var ui
var paths: Array[String] = []
var failures: Array[String] = []
var contract_id := ""

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("STAFF_BACKUP_UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL staff_backup_ui: ", label)

func frames(count: int = 5) -> void:
	for _index in count: await process_frame

func set_paths(values: Array[String]) -> void:
	paths = values.duplicate()
	game.save_path = paths[0]
	game.backup_path = paths[1]
	game.previous_path = paths[2]
	game.settings_path = paths[3]

func control(id: String) -> Node:
	return ui.find_child(id, true, false) if is_instance_valid(ui) else null

func handoff_reports() -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(ui): return result
	for candidate in ui.find_children("*", "RichTextLabel", true, false):
		if str(candidate.name).begins_with("HandoffReport_"): result.append(candidate)
	return result

func route_from_workday(id: String) -> bool:
	var button := control(id) as Button
	check(button != null, "workday card exposes " + id)
	if button == null: return false
	button.pressed.emit()
	await frames(8)
	return true

func measure_key() -> String:
	var key: String = str(game._vm_key())
	return JSON.stringify({
		"clock":game.clock_minutes(),
		"work":game.state.get("work", {}),
		"cash":game.state.get("cash", 0),
		"revision":game.state.get("revision", -1),
		"checks":game.state.get("checks", []),
		"vm":game.state.get("vm_states", {}).get(key, {})
	})

func finish_worker(member_id: String, minutes: float) -> void:
	game._finish_colleague(member_id, {"kind":"normal","status":"working","contract_id":contract_id,"target_index":0,"total":minutes,"work_minutes":minutes,"remaining":0.0})

func setup_case() -> bool:
	ui = INTERFACE.new()
	root.add_child(ui)
	await frames(5)
	game = ui._game()
	if game == null:
		check(false, "interface resolves the isolated Game")
		return false
	game.set_process(false)
	var prefix := "user://qa-staff-backup-ui-%s" % OS.get_process_id()
	set_paths([prefix + ".json", prefix + ".bak", prefix + ".previous", prefix + ".settings"])
	check(ui._new_game(), "new company uses isolated QA storage")
	check(game.choose_strategy("operations"), "choose operations strategy through Game")
	check(game.start_free_career(), "enter the ordinary contract market through Game")
	game.state.peak_profit = 35000
	game.state.skills.operations = 2
	game._update_growth()
	game.state.market_day = int(game.state.day)
	game.state.market_leads = [CASE_ID]
	game._make_offers()
	var offer: Dictionary = {}
	for item in game.state.offers:
		if str(item.get("case_id", "")) == CASE_ID and bool(item.get("market_available", false)):
			offer = item.duplicate(true)
			break
	check(not offer.is_empty(), "actual backup case is available in the QA market")
	if offer.is_empty(): return false
	check(game.set_offer_plan("standard"), "select the standard plan")
	check(game.choose_contract(str(offer.id)), "accept through Game.choose_contract")
	contract_id = str(game.state.current_contract_id)
	check(game.state.targets.size() == 1 and game._current_chapter() == 1, "accepted contract selects its exact backup target")
	if contract_id.is_empty() or game.state.targets.is_empty(): return false
	game.inspect_mission()
	check(str(game.vm_run("ssh client")).contains("Authenticated"), "connect through the actual VM action")
	finish_worker("aya", 12.0)
	finish_worker("ren", 18.0)
	check(game.state.targets[0].get("work_receipts", []).size() == 2, "both actual colleague receipts are saved on the target")
	ui.operations_choices.workday_selected = "contract:%s:0" % contract_id
	ui.operations_choices.workday_record_open = true
	ui.open_panel("board")
	await frames(8)
	return true

func run() -> void:
	if not await setup_case(): await finish(); return
	var selector := control("HandoffRecordChoice") as OptionButton
	check(selector != null and selector.item_count == 2, "report viewer offers the two saved colleagues")
	var report := control("HandoffReport_ren") as RichTextLabel
	var reports := handoff_reports()
	check(report != null and reports.size() == 1 and str(report.text).contains("担当: 蓮"), "latest Ren receipt is the single default report")
	if selector != null and selector.item_count > 1:
		check(selector.get_item_text(0).begins_with("蓮") and selector.get_item_text(1).begins_with("綾"), "selector defaults to latest Ren and retains the older Aya record")
		selector.select(1)
		selector.item_selected.emit(1)
		await frames(6)
		check(control("HandoffReport_aya") is RichTextLabel and handoff_reports().size() == 1, "selector can show the older Aya report without duplicating viewers")
		ui.operations_choices.workday_record_index = 1
		ui.operations_choices.workday_record_open = true
		ui.open_panel("board")
		await frames(6)
	var original_id := str(game.state.current_contract_id)
	var original_target := int(game.state.target_index)
	var baseline := measure_key()
	check(await route_from_workday("BackupSourceRoute"), "open the workday plan route")
	check(ui.current_kind == "terminal" and str(game.state.current_contract_id) == original_id and int(game.state.target_index) == original_target, "plan route returns to the exact contract target")
	check(is_instance_valid(ui.desktop) and ui.desktop.current_app == "browser" and bool(ui.desktop.backup_ui.get("plan_open", false)), "plan route lands on the open backup plan")
	check(measure_key() == baseline, "opening the workday plan does not alter time, VM state, diagnostics or cost")
	var desktop = ui.desktop
	desktop._show_app("editor")
	desktop._open_editor("workstation:/home/operator/Documents/backup-route-draft.txt")
	var draft := "unsaved route draft must survive a failed save"
	desktop.widgets.editor.editor.text = draft
	var valid_paths := paths.duplicate()
	var missing_prefix := "user://qa-staff-backup-missing-%s/save.json" % OS.get_process_id()
	set_paths([missing_prefix, missing_prefix + ".bak", missing_prefix + ".previous", missing_prefix + ".settings"])
	ui._open_backup_work(original_id, original_target, "backup-offsite")
	await frames(2)
	check(ui.current_kind == "terminal" and ui.desktop == desktop and str(game.state.current_contract_id) == original_id, "failed session save blocks the route switch")
	check(str(desktop.current_app) == "editor" and str(desktop.widgets.editor.editor.text) == draft, "failed route save keeps the old editor draft mounted")
	set_paths(valid_paths)
	baseline = measure_key()
	ui._open_backup_work(original_id, original_target, "backup-offsite")
	await frames(8)
	check(ui.current_kind == "terminal" and ui.desktop != desktop and str(game.state.current_contract_id) == original_id and int(game.state.target_index) == original_target, "retry completes routing to the same accepted target")
	check(is_instance_valid(ui.desktop) and str(ui.desktop.backup_ui.get("repository", "")) == "offsite" and not bool(ui.desktop.backup_ui.get("plan_open", true)), "offsite route selects only the separate repository view")
	var saved_session: Dictionary = game.state.get("desktop_sessions", {}).get(ui.desktop.session_key, {})
	check(str(saved_session.get("drafts", {}).get("workstation:/home/operator/Documents/backup-route-draft.txt", "")) == draft, "successful retry saves the original desktop draft before switching")
	check(measure_key() == baseline, "offsite route is read-only with respect to VM execution, time and costs")
	ui._open_backup_work(original_id, original_target, "backup-local")
	await frames(8)
	check(str(ui.desktop.backup_ui.get("repository", "")) == "local", "local route selects the same-site repository")
	check(measure_key() == baseline, "local route does not measure or change the accepted VM")
	ui._open_backup_work(original_id, original_target, "backup-restore")
	await frames(8)
	check(ui.desktop.current_app == "files" and bool(ui.desktop.file_remote) and str(ui.desktop.file_directory) == "/restore", "restore route opens the remote recovery folder")
	check(measure_key() == baseline, "opening the restored folder does not run another VM operation")
	await finish()

func finish() -> void:
	if is_instance_valid(ui): ui.queue_free()
	await frames(2)
	var cleanup := paths.duplicate()
	if not cleanup.is_empty(): cleanup.append(str(cleanup[0]) + ".tmp")
	for path in cleanup:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("STAFF_BACKUP_UI_TEST_PASS" if failures.is_empty() else "STAFF_BACKUP_UI_TEST_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
