extends SceneTree

const Game = preload("res://scripts/game.gd")
var failures: Array[String] = []

func _assert(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	var game := Game.new(); root.add_child(game); await process_frame
	game.save_path = "user://quality_qa.json"; game.backup_path = "user://quality_qa.json.bak"; game.previous_path = "user://quality_qa.previous.json"; game.settings_path = "user://quality_qa_settings.json"
	_assert(game.new_game({"company":"品質合同会社"}), "new game")
	_assert(game.choose_strategy("advisory"), "strategy")
	_assert(game.accept_mission(), "accept")
	_assert("接続" in game.vm_run("cat /etc/samba/smb.conf"), "disconnected read remains rejected")
	game.vm_run("ssh client")
	_assert(not game.vm_write("/missing/config", "x"), "failed write does not lock baseline")
	game.state.targets = []
	_assert(game.save_game() and game.load_game(), "accepted legacy save load")
	_assert(game.state.targets.size() == 1 and not game.state.targets[0].baseline_locked, "legacy unchanged target can record")
	game.vm_write(game.vm_info().config_path,game._vm().configuration_text({"staff":"write","guest":"none"}))
	game.state.targets=[]
	_assert(game.save_game() and game.load_game() and game.state.targets[0].baseline_locked,"legacy changed target is locked")
	_assert(game.new_game({"company":"品質合同会社"}) and game.choose_strategy("advisory") and game.accept_mission(), "fresh quality case")
	game.vm_run("ssh client")
	var before := game.case_review()
	_assert(before.can_capture and not before.recorded and before.grade == "A", "baseline initially available")
	_assert(game.capture_baseline(), "capture baseline")
	_assert(not game.capture_baseline(), "second capture rejected")
	var recorded := game.case_review()
	_assert(recorded.recorded and recorded.recorded_sites == 1 and recorded.total_sites == 1, "baseline recorded")
	_assert(recorded.bonus > 0 and recorded.grade == "S", "baseline quality bonus")
	_assert(game.save_game() and game.load_game() and game.case_review().recorded, "baseline survives save load")
	var report := game.vm_read("/home/operator/baseline-report.txt")
	game.vm_run("rm /home/operator/baseline-report.txt")
	_assert(not game.case_review().recorded and game.case_review().bonus == 0, "tampered report invalidates record")
	game.vm_write("/home/operator/baseline-report.txt", report)
	_assert(game.case_review().recorded, "restored report validates")
	game.new_game(); game.choose_strategy("advisory"); game.accept_mission(); game.vm_run("ssh client")
	game.vm_write("/tmp/changed.conf", "staff=broken\nguest=read\n")
	game.vm_run("cp /tmp/changed.conf /etc/samba/smb.conf")
	_assert(not game.case_review().can_capture, "cp config change locks baseline")
	game.new_game({"company":"品質合同会社"}); game.choose_strategy("advisory"); game.accept_mission(); game.vm_run("ssh client")
	game.vm_run("sudo systemctl restart samba")
	_assert(game.case_review().can_capture, "unchanged sudo restart keeps baseline available")
	game.vm_run("cd /etc/samba")
	game.vm_write("smb.conf", "staff=broken\nguest=read\n")
	_assert(not game.case_review().can_capture, "relative config edit locks baseline")
	game.new_game({"company":"品質合同会社"}); game.choose_strategy("advisory"); game.accept_mission(); game.vm_run("ssh client"); game.capture_baseline()
	game.state.targets.append({"config":game._default_fields(0),"inspected":false,"checks":[],"revision":0,"validated_revision":-1,"baseline_recorded":false,"baseline_locked":false,"baseline_config":"","baseline_sha":"","baseline_report":"","baseline_report_content":""})
	_assert(not game.case_review().recorded and game.case_review().bonus == 0, "one of two sites earns no record bonus")
	game.select_target(1); game.vm_run("ssh client"); game.capture_baseline()
	var two_sites := game.case_review()
	_assert(two_sites.recorded_sites == 2 and two_sites.bonus > 0, "all sites earn baseline bonus")
	game.new_game({"company":"品質合同会社"}); game.choose_strategy("advisory"); game.accept_mission(); game.vm_run("ssh client"); game.capture_baseline()
	game.vm_write(game.vm_info().config_path, game._vm().configuration_text({"staff":"write","guest":"none"}))
	game.vm_run("systemctl restart samba")
	for pass_index in 3:
		for probe in game.diagnostic_probes():
			if not (probe.recorded and probe.fresh and probe.passed): game.run_diagnostic(str(probe.id))
		if game.diagnostic_probes().all(func(p): return p.recorded and p.fresh and p.passed): break
	game.verify()
	_assert(game.can_deliver(), "safe work can deliver")
	var cash_before := int(game.state.cash)
	_assert(game.deliver(), "deliver once")
	_assert(int(game.state.cash) > cash_before and int(game.completion_receipt().baseline_bonus) > 0, "receipt and cash include quality bonus")
	var receipt: Dictionary=game.completion_receipt()
	_assert(int(receipt.baseline_bonus)==roundi(float(receipt.fee)*0.05) and int(game.state.cash)-cash_before==int(receipt.net), "record bonus is exactly five percent and paid once")
	_assert(int(receipt.bonus)==roundi(float(receipt.fee)*0.1)+int(receipt.baseline_bonus), "record bonus is separate from time quality bonus")
	_assert(not game.deliver(), "duplicate delivery rejected")
	var log := FileAccess.open("user://v13-quality.log", FileAccess.WRITE)
	if log:
		log.store_string("QUALITY failures=%d\n" % failures.size())
		for failure in failures: log.store_string("FAIL: %s\n" % failure)
		log.close()
	print("QUALITY failures=", failures.size(), " log=user://v13-quality.log")
	for failure in failures: print("FAIL: ", failure)
	quit(1 if not failures.is_empty() else 0)
