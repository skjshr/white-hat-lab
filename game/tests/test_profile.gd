extends SceneTree

const Game = preload("res://scripts/game.gd")
var failures: Array[String] = []

func _assert(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	var game := Game.new()
	root.add_child(game)
	await process_frame
	game.save_path = "user://profile_qa_save.json"
	game.backup_path = "user://profile_qa_save.json.bak"
	game.previous_path = "user://profile_qa_save.json.previous.json"
	game.settings_path = "user://profile_qa_settings.json"
	_assert(game.new_game({"company":"青葉ラボ合同会社","player":"真白","aya":"調査主任","ren":"復旧主任"}), "custom profile new game")
	_assert(game.company_name() == "青葉ラボ合同会社" and game.player_name() == "真白", "profile names applied")
	game.state.cash = 4321
	game.state.skills = {"operations":2,"advisory":1,"response":0}
	game.state.vm_states = {"profile-vm": {"marker":"persisted-vm"}}
	_assert(game.save_game(), "all four names and progress save")
	_assert(game.set_profile({"company":"別会社","player":"別主人公","aya":"別調査","ren":"別復旧"}), "rename profile")
	_assert(game.load_game(), "renamed profile load")
	_assert(game.company_name() == "別会社" and game.player_name() == "別主人公" and game.member_name("aya") == "別調査" and game.member_name("ren") == "別復旧", "all four names round trip")
	_assert(int(game.state.cash) == 4321 and game.state.skills.operations == 2 and game.state.vm_states["profile-vm"].marker == "persisted-vm", "progress and VM preserved through rename")
	_assert(game.set_profile({"company":"青葉ラボ合同会社","player":"真白","aya":"調査主任","ren":"復旧主任"}), "restore profile for personalization")
	_assert(game.personalize("あおばセキュリティ相談所 / 青葉 / 綾 / 蓮") == "青葉ラボ合同会社 / 真白 / 調査主任 / 復旧主任", "personalize defaults")
	_assert(game.set_profile({"company":"綾"}), "short profile update")
	_assert(game.personalize("あおばセキュリティ相談所と綾") == "綾と調査主任", "non chained replacement")
	_assert(not game.set_profile({"player":"   "}), "blank profile rejected")
	_assert(not game.set_profile({"ren":123}), "non string profile rejected")
	_assert(game.set_profile({"company":"あ".repeat(40),"player":"名".repeat(20),"aya":"調".repeat(20),"ren":"復".repeat(20)}), "length boundaries accepted")
	_assert(not game.set_profile({"company":"あ".repeat(41)}), "company length over boundary rejected")
	_assert(not game.set_profile({"player":"名".repeat(21)}), "person length over boundary rejected")
	_assert(not game.set_profile({"aya":"調\n査"}), "control character rejected")
	_assert(game.save_game(), "profile save")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	parsed.profile = {"company":123,"player":"   ","aya":true,"ren":[]}
	var old_file := FileAccess.open(game.save_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(parsed)); old_file.close()
	_assert(game.load_game(), "malformed profile load")
	_assert(int(game.state.cash) == 4321 and game.state.skills.operations == 2, "malformed profile leaves progress")
	_assert(game.company_name() == "あおばセキュリティ相談所" and game.member_name("aya") == "綾", "malformed profile defaults")
	parsed.erase("profile")
	old_file = FileAccess.open(game.save_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(parsed)); old_file.close()
	_assert(game.load_game() and game.company_name() == "あおばセキュリティ相談所" and int(game.state.cash) == 4321, "legacy save without profile preserves progress")
	_assert(game.new_game({"company":"  空色相談所  ","player":"  春  "}), "trimmed profile new game")
	_assert(game.state.profile.company == "空色相談所" and game.state.profile.player == "春", "new profile stored without outer spaces")
	var log := FileAccess.open("user://v121-profile.log", FileAccess.WRITE)
	if log:
		log.store_string("PROFILE failures=%d\n" % failures.size())
		for failure in failures: log.store_string("FAIL: %s\n" % failure)
		log.close()
	print("PROFILE failures=", failures.size(), " log=user://v121-profile.log")
	for failure in failures: print("FAIL: ", failure)
	quit(1 if not failures.is_empty() else 0)
