extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var game = root.get_node("Game")
	var prefix := "user://qa-automatic-" + str(OS.get_process_id())
	for path in [game.save_path, game.backup_path, game.previous_path, game.settings_path]:
		if not str(path).begins_with(prefix):
			push_error("Unisolated QA path: " + str(path))
			quit(1)
			return
	print("QA_STORAGE_PASS display=", DisplayServer.get_name())
	quit(0)
