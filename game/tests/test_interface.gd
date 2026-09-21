extends SceneTree
const UI = preload("res://scripts/interface.gd")
const MAIL = preload("res://scripts/os_business_apps.gd")
const CONFIGS := [
	"[global]\nserver role = standalone server\nmap to guest = Bad User\n[share]\npath = /srv/share\nread only = no\nguest ok = no\nvalid users = staff\n",
	"schedule=daily\nrepository=offsite\n",
	"dns=on\nbusiness=allow\nadmin_public=deny\ntls=on\n",
	"former=disabled\nsessions=revoked\ncurrent=active\nmfa=on\n",
	"pc_a=isolated\npc_b=connected\nlogs=keep\nreset=wait\n",
	"staff=write\npartner=read\npublic=none\nexpires=7d\nmfa=on\ntls=on\naudit=on\n"
]
var ui
var game
var failures: Array[String] = []

func _init() -> void:
	ui = UI.new(); root.add_child(ui)
	await process_frame
	game = ui._game()
	var run_id := str(OS.get_process_id())
	game.save_path = "user://acceptance_vm-"+run_id+".json"; game.backup_path = "user://acceptance_vm-"+run_id+".json.bak"; game.previous_path = "user://acceptance_vm-"+run_id+".previous.json"; game.settings_path = "user://acceptance_vm-"+run_id+"_settings.json"
	ui._new_game(); game.choose_strategy("operations")
	for scenario in game.CASES.all():
		var mail := MAIL._mail_for(scenario)
		_assert(not mail.is_empty() and str(mail.get("body","")).contains(str(scenario.client)),"career mail matches case and client: "+str(scenario.id))
	for chapter in 6:
		_assert(not MAIL._mail_for(game.mission()).is_empty(),"intro mail maps to runtime case ID")
		ui.open_panel("terminal")
		var pc = ui.desktop
		if chapter == 0:
			_assert(not pc.widgets.mail.reading,"mail opens in inbox view")
			var current_mail: Dictionary = MAIL._mail_for(game.mission())
			pc.widgets.mail.selected_subject=str(current_mail.get("subject",game.mission().title)); pc.widgets.mail.reading=true; pc._refresh_mail()
			var plan = pc.widgets.mail.footer.find_child("MailContractPlan",true,false)
			_assert(plan is OptionButton,"mail exposes contract selector")
			if plan is OptionButton: plan.item_selected.emit(1)
			_assert(game.state.contract_plan=="priority","mail contract selector changes actual plan")
			game.set_contract_plan("standard")
		pc._accept()
		_assert(not game.vm_write(game.vm_info().config_path,CONFIGS[chapter]), "disconnected writes refused")
		pc._run_command("ssh client")
		if chapter == 0:
			_assert("200" in game.vm_run("curl https://files.client.test/guest/report.txt"), "guest access initially exposed")
			_assert(game.vm_list("/etc").has("/etc/samba/"), "real file hierarchy")
			pc._show_app("files"); pc.path_edit.text = "/etc/samba"; pc._list_files()
			_assert(pc.file_list.get_root().get_child_count() == 1,"file application lists config")
			pc.file_list.get_root().get_child(0).select(0)
			pc._open_file_item(0)
			pc.editor.text = "staff=broken\nguest=none\n"; pc._save_editor()
			_assert("failed" in game.vm_run("systemctl restart samba"), "invalid config fails service")
			_assert(not game.can_deliver(), "failed service cannot deliver")
			pc._open_editor("workstation:/home/operator/Documents/作業メモ.txt")
			pc.editor.text = "調査メモ"; pc._save_editor(); pc._show_app("terminal"); pc._show_app("editor")
			_assert(pc.editor.text=="調査メモ" and game.state.os_files["/home/operator/Documents/作業メモ.txt"]=="調査メモ","local documents persist across live app windows")
		_finish_current(pc,chapter)
		_assert(game.can_deliver(), "VM solved chapter %d" % chapter)
		if chapter == 0:
			_assert("403" in game.vm_run("curl https://files.client.test/guest/report.txt"), "guest access blocked after changes")
			var before_cash: int = game.state.cash
			pc._report()
			_assert(game.state.cash == before_cash + 800 and game.state.credit == 8,"net profit -> credit")
			_assert(not game.deliver(),"no double payment")
			pc._show_app("browser")
			pc.url_edit.text = "https://files.client.test/staff/report.txt"; pc._browse()
			var closed_page: String = _visible_text(pc.widgets.browser.page)
			_assert(closed_page.contains("報告済み") and not closed_page.contains("接続エラー"),"closed contract browser explains business state without false connection failure")
		else: pc._report()
		_assert(game.end_day(),"day closes after report")
	_assert(game.state.game_complete, "six operational cases completed")
	_assert(game.learn_skill("operations") and game.learn_skill("operations") and game.learn_skill("response"),"specialize and diversify")
	_assert(game.continue_business(),"continuous business")
	for offer in game.state.offers:
		ui._select_contract(str(offer.id))
		var detail: String = _visible_text(ui.modal_body)
		_assert(not detail.contains("%d") and not detail.contains("%s") and detail.contains(preload("res://scripts/ui_theme.gd").copy("board_profit") % (int(offer.reward)-int(offer.estimated_cost))),"contract details format real reward and cost: "+str(offer.id))
	ui._select_contract(str(game.state.offers[0].id))
	var board_plan = ui.modal_body.find_child("ContractPlan", true, false)
	_assert(board_plan is OptionButton, "career board exposes contract plans")
	if board_plan is OptionButton:
		board_plan.select(2); board_plan.item_selected.emit(2)
		var care: Dictionary = game.care_terms(str(game.state.offers[0].client))
		var expected_rates: String = preload("res://scripts/ui_theme.gd").copy("care_contract_rates") % [int(care.fee),int(care.cost),int(care.net)]
		_assert(game.offer_plan() == "care" and _visible_text(ui.modal_body).contains(expected_rates), "career care selection shows agreed price before acceptance")
		var portfolio_before: Dictionary = game.care_portfolio()
		_assert(portfolio_before.reserved_count == 0, "previewing care does not reserve capacity")
		var standard_plan = ui.modal_body.find_child("ContractPlan", true, false)
		standard_plan.select(0); standard_plan.item_selected.emit(0)
		_assert(game.offer_plan() == "standard", "career board restores standard plan")
	ui.board_selected_id = ""
	var largest := 0
	for day in 4:
		var offers: Array = game.state.offers.filter(func(o): return o.unlocked and o.category == "operations")
		var offer: Dictionary = offers[-1]
		_assert(game.choose_contract(offer.id),"select contract")
		largest = maxi(largest,game.state.targets.size())
		for site in game.state.targets.size():
			game.select_target(site); ui.open_panel("terminal")
			var pc = ui.desktop
			pc._show_app("terminal"); pc._run_command("ssh client")
			_finish_current(pc,int(game.state.chapter))
			if site < game.state.targets.size()-1: _assert(not game.can_deliver(),"other sites require work")
		_assert(game.can_deliver() and game.deliver() and game.end_day(),"multi-site delivery")
	_assert(largest >= 2,"larger contracts reached through company growth")
	var expected := 5000
	for entry in game.state.history: expected += int(entry.get("profit",0)) + int(entry.get("retainer",0))
	_assert(game.state.cash == expected and game.state.profit == expected-5000,"accounting reconciles")
	_assert(game.load_game() and game.state.history.filter(func(entry): return not str(entry.get("id", "")).begins_with("retainer-day-")).size()==10,"saved machines and ten completed deliveries restored")
	ui.close_panel(false); ui.open_panel("settings")
	var previous: Dictionary = game.settings.duplicate(true)
	ui._settings_tab("audio")
	_assert(ui.setting_options.volume.control.is_visible_in_tree() and not ui.setting_options.resolution.control.is_visible_in_tree(),"settings categories change visible controls")
	ui._settings_tab("video")
	ui._queue_setting("quality","high"); ui._apply_settings(); ui._process(16)
	_assert(game.settings==previous,"display timeout rollback")
	ui._queue_setting("quality","high"); ui._apply_settings(); ui._keep_settings()
	_assert(game.settings.msaa==4 and game.settings.render_scale==1.0,"confirmed preset applies")
	game.save_game()
	var file := FileAccess.open(game.save_path,FileAccess.WRITE); file.store_string("{ broken"); file.close()
	_assert(game.load_game() and game.state.career_mode,"backup recovery")
	ui.close_panel(false)
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: desktop file editing, command execution, six cases, four career contracts, multiple sites, economy, saves, graphics" if failures.is_empty() else "FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _finish_current(pc, chapter: int) -> void:
	pc._open_config()
	var scenario: Dictionary = game._scenario()
	if scenario.is_empty(): pc.editor.text = CONFIGS[chapter]
	else:
		pc.editor.text = game._vm().configuration_text(scenario.desired)
	pc._save_editor()
	pc._show_app("terminal")
	pc._run_command("systemctl restart " + str(game.vm_info().service))
	if chapter == 1:
		game.verify(); _assert(not game.can_deliver(),"backup configuration alone is insufficient")
		if str(scenario.get("seed_snapshot_repository","")) != str(scenario.get("desired",{}).get("repository","offsite")): pc._run_command("restic backup /srv/data")
		pc._run_command("restic restore 00000001 --target /restore" if scenario.has("latest_snapshot_overrides") else "restic restore latest --target /restore")
		var restored_orders := "/restore/srv/data/orders.csv" if int(game._vm().state.get("backup_model_version", 1)) >= 2 else "/restore/orders.csv"
		_assert(game.vm_read(restored_orders)==game._vm().RECORDS["orders.csv"],"restored data matches the known original")
	if chapter == 4:
		pc._run_command("cp /var/log/evidence.log /evidence/original.log")
	preload("res://tests/identity_test_support.gd").authenticate_current(game)
	for pass_index in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded",false)) and bool(probe.get("fresh",false)) and bool(probe.get("passed",false))):
				pc._run_command(str(probe.command))
	pc._verify()
	_assert(game.state.checks.all(func(c):return c.passed),"service probes pass")

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _visible_text(node: Node) -> String:
	var result := str(node.text) if node is Label else ""
	for child in node.get_children(): result += _visible_text(child)
	return result
