extends SceneTree

const Game = preload("res://scripts/game.gd")
var failures: Array[String] = []

func _assert(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _init() -> void:
	var game := Game.new(); root.add_child(game)
	game.save_path = "user://save-recovery-qa.json"
	game.backup_path = "user://save-recovery-qa.json.bak"
	game.previous_path = "user://save-recovery-qa.json.previous.json"
	game.settings_path = "user://save-recovery-qa-settings.json"
	for path in [game.save_path, game.backup_path, game.previous_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_assert(game.new_game(), "new game")
	game.state.cash = 6200
	_assert(game.save_game(), "initial save")
	game.state.cash = 7100
	_assert(game.save_game(), "backup save")
	var corrupt := FileAccess.open(game.save_path, FileAccess.WRITE)
	corrupt.store_string("{ broken")
	corrupt.close()
	_assert(game.load_game(), "recover corrupt primary")
	_assert(game.last_load_error == "backup_recovered_primary_invalid", "corrupt recovery status")
	_assert(int(game.state.cash) == 6200, "backup state restored")
	_assert(game.state.ui_help_seen is Dictionary, "help state migrated")
	game.state.cash = 8300
	_assert(game.save_game(), "post recovery save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	_assert(game.load_game(), "recover missing primary")
	_assert(game.last_load_error == "backup_recovered_primary_missing", "missing recovery status")
	_assert(int(game.state.cash) == 6200, "missing primary backup state restored")
	_assert(game.save_game(), "restore primary before failure checks")
	var previous_bytes := FileAccess.get_file_as_string(game.save_path)
	var protected_backup := FileAccess.get_file_as_string(game.backup_path)
	var normal_backup := game.backup_path
	game.backup_path = "user://save-recovery-unavailable-folder/backup.json"
	game.state.cash = 99999
	_assert(not game.save_game(), "backup failure rejects save")
	_assert(FileAccess.get_file_as_string(game.save_path) == previous_bytes, "backup failure preserves primary")
	game.backup_path = normal_backup
	_assert(FileAccess.get_file_as_string(game.backup_path) == protected_backup, "backup failure preserves last valid backup")
	var log := FileAccess.open("user://v15-save-recovery.log", FileAccess.WRITE)
	if log:
		log.store_string("SAVE_RECOVERY failures=%d\n" % failures.size())
		for failure in failures: log.store_string("FAIL: %s\n" % failure)
		log.close()
	print("SAVE_RECOVERY failures=", failures.size(), " log=user://v15-save-recovery.log")
	for failure in failures: print("FAIL: ", failure)
	quit(1 if not failures.is_empty() else 0)
