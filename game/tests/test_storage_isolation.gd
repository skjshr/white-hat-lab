extends SceneTree
func _init(): call_deferred("run")
func run():
	var game=root.get_node("Game")
	assert(game.save_path.begins_with("user://qa-"))
	assert(game.settings_path.begins_with("user://qa-"))
	assert(game.backup_path!=game.SAVE_BACKUP_NAME)
	assert(game.previous_path!=game.SAVE_PREVIOUS_NAME)
	assert(game.new_game())
	game.set_settings({"volume":0})
	print("STORAGE_ISOLATION PASS ",game.save_path," ",game.settings_path)
	quit()
