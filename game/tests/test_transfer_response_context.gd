extends SceneTree
## UI/API fixture: identical raw errors from different operations/identities.
var assertions := 0
var failures: Array[String] = []
var ui
var desk
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ",label)
func frames(count := 6) -> void:
	for _frame in count: await process_frame
func object(id: String) -> Node: return desk.find_child(id,true,false)
func run() -> void:
	var game = root.get_node("Game"); game.set_process(false)
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	var source := OS.get_environment("WHL_ORDINARY_FIXTURE")
	var original := FileAccess.get_file_as_string(source)
	if original.is_empty(): push_error("earned source required"); quit(2); return
	var output := FileAccess.open(game.save_path,FileAccess.WRITE); output.store_string(original); output.close()
	check(game.load_game() and game.current_done(),"copy earned paid company only to QA")
	var offer: Dictionary = {}
	for row in game.state.offers:
		if str(row.case_id) == "service-0-case-0" and bool(row.unlocked) and bool(row.market_available): offer = row; break
	check(not offer.is_empty(),"ordinary case actually available")
	if offer.is_empty(): quit(1); return
	check(game.choose_contract(str(offer.id)),"public acceptance creates actual daily-report model")
	game.set_process(false); check(str(game.vm_run("ssh client")).contains("Authenticated"),"actual fictional connection")
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	ui.guided_intro.skip(); ui.next_task_guide.set_enabled(false); ui.open_panel("terminal"); await frames(); desk = ui.desktop
	desk._open_samba_share(); await frames()
	check(desk._smb_get("report.txt","/home/operator/report.txt"),"actual staff GET creates saved copy")
	check(not desk._smb_put("/home/operator/report.txt","report.txt"),"actual staff PUT is refused")
	desk._render_smb(); await frames()
	var record: Dictionary = desk.samba_ui.last_transfer.duplicate(true)
	check(object("SmbTransferReceipt") != null and str(desk.samba_ui.access_operation) == "upload", "actual failed upload has its own receipt")
	var user := object("SmbUser") as OptionButton
	user.select(1); user.item_selected.emit(1); await frames()
	check(str(desk.samba_ui.access_user) == "guest" and str(desk.samba_ui.access_output) == str(record.response),"guest LS produces the exact same refused response")
	check(str(desk.samba_ui.access_operation) == "list" and object("SmbTransferReceipt") == null,"guest listing never borrows staff upload receipt")
	check(object("SmbOutput") != null and str(object("SmbOutput").text) == "NT_STATUS_ACCESS_DENIED", "listing shows its own actual error")
	check(str(desk.samba_ui.access_preview) == "" and str(desk.samba_ui.access_selected) == "" and desk.samba_ui.last_transfer == record,"identity change clears private preview and preserves historical request")
	check(desk._save_session() and game.save_game(),"save actual listing and old request separately")
	ui.queue_free(); await frames(); check(game.load_game(),"resume actual listing context")
	game.set_process(false); ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames(); ui.open_panel("terminal"); await frames(); desk = ui.desktop; desk._show_app("files"); await frames()
	check(object("SmbTransferReceipt") == null and str(desk.samba_ui.access_operation) == "list", "resumed guest listing still never becomes a staff transfer")
	check(FileAccess.get_file_as_string(source) == original,"original earned source remains exact")
	print("TRANSFER_RESPONSE_CONTEXT assertions=",assertions," failures=",failures)
	quit(0 if failures.is_empty() else 1)
