extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	create_timer(30.0).timeout.connect(func(): print("FAIL: RV profile test timed out"); quit(2))
	call_deferred("run")

func run() -> void:
	var game = root.get_node("Game")
	game.save_path = "user://rv18_profile.json"
	game.backup_path = game.save_path+".bak"
	game.previous_path = game.save_path+".previous"
	game.settings_path = "user://rv18_profile-settings.json"
	check(game.new_game({"company":"光と森 株式会社","player":"真白 [主]","aya":"調査 花子","ren":"復旧 太郎"}),"create custom identity")
	game.choose_strategy("advisory")
	game.accept_mission()
	check(game.vm_run("whoami") == "真白 [主]","local terminal operator identity")
	game.vm_run("ssh client")
	var config_before: String = game.vm_read(game.vm_info().config_path)
	var evidence_before: String = game.vm_read("/var/log/evidence.log")
	game._vm().cooperate("aya")
	var report: String = game.vm_read("/home/operator/aya-inspection.txt")
	check(report.contains("光と森 株式会社") and report.contains("調査 花子") and report.contains("真白 [主]"),"generated investigation uses profile")
	check(game.set_profile({"company":"綾の会社","player":"蓮太","aya":"星","ren":"月"}),"rename live profile")
	check(game.vm_read(game.vm_info().config_path)==config_before and game.vm_read("/var/log/evidence.log")==evidence_before,"rename leaves config and evidence byte-identical")
	check(game.vm_read("/home/operator/aya-inspection.txt")==report,"rename keeps historical report author")
	game._vm().cooperate("ren")
	check(game.vm_read("/home/operator/ren-verification.txt").contains("担当: 月"),"new report uses renamed teammate")
	var ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await process_frame
	ui.open_panel("terminal")
	var desktop = ui.desktop
	var current_mail: Dictionary = preload("res://scripts/os_business_apps.gd")._mail_for(game.mission(), game)
	desktop.widgets.mail.selected_subject = str(current_mail.get("subject", game.mission().title))
	desktop.widgets.mail.reading = true
	desktop._refresh_mail()
	check(desktop.widgets.mail.recipient.text.contains("綾の会社 / 蓮太"),"mail recipient uses company and player")
	check(ui.controls.company_title.text == "ホワイトハッカーラボ", "title remains fixed after profile rename")
	desktop._show_app("team")
	check(desktop.widgets.team.cards[0].name.text=="星" and str(desktop.widgets.team.cards[0].member.name)=="星","team name and member identity match")
	check(game.set_profile({"company":"わかば株式会社","player":"空","aya":"風","ren":"雲"}),"change to previous company name")
	await process_frame
	check(desktop.system_company.text=="わかば株式会社","shell shows live previous company")
	game.set_profile({"company":"海の会社","player":"空","aya":"風","ren":"雲"})
	await process_frame
	check(desktop.widgets.mail.recipient.text.contains("海の会社 / 空"),"open mail reflects rename")
	check(desktop.widgets.mail.recipient_details.text.contains("海の会社 / 空"),"expanded mail headers reflect rename")
	check(desktop.system_company.text=="海の会社" and desktop.brand_label.text=="海の会社","shell and wallpaper identity reflect rename")
	check(ui.controls.company_title.text=="ホワイトハッカーラボ","existing title remains fixed after repeated rename")
	check(desktop.widgets.team.cards[0].name.text=="風" and str(desktop.widgets.team.cards[0].member.name)=="風","open team reflects rename")
	var mail = load("res://scripts/os_business_apps.gd")
	for scenario in game.CASES.all():
		if str(scenario.client)=="青葉デザイン":
			check(str(mail._mail_for(scenario,game).get("company",""))=="青葉デザイン","client identity remains unchanged")
			break
	check(game.load_game() and game.company_name()=="海の会社" and game.player_name()=="空","renamed profile persists")
	ui.queue_free()
	await process_frame
	print("RV_PROFILE failures=",failures.size())
	for failure in failures: print("FAIL: ",failure)
	quit(0 if failures.is_empty() else 1)
