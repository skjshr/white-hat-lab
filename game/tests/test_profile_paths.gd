extends SceneTree

const VM := preload("res://scripts/virtual_machine.gd")
const PATHS := preload("res://scripts/profile_paths.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var vm := VM.new()
	var old_saved := {
		"schema": 2,
		"fs": {"/home/aoba/only.txt":"旧本文", "/home/wakaba/wakaba.txt":"wakaba本文", "/home/operator/conflict.txt":"新本文", "/home/aoba/conflict.txt":"旧本文", "/home/operator/same.txt":"同じ", "/home/aoba/same.txt":"同じ"},
		"dirs": ["/", "/home", "/home/aoba", "/home/aoba/archive", "/home/wakaba", "/home/operator"],
		"cwd": "/home/aoba/archive",
		"applied": {}, "snapshots": [], "events": []
	}
	vm.setup(0, old_saved)
	_assert(vm.state.fs.get("/home/operator/only.txt", "") == "旧本文", "aoba file migrates to operator")
	_assert(vm.state.fs.get("/home/operator/wakaba.txt", "") == "wakaba本文", "wakaba file migrates to operator")
	_assert(vm.state.fs.get("/home/aoba/conflict.txt", "") == "旧本文" and vm.state.fs.get("/home/operator/conflict.txt", "") == "新本文", "conflicting files remain byte distinct")
	_assert(not vm.state.fs.has("/home/aoba/same.txt") and vm.state.fs.get("/home/operator/same.txt", "") == "同じ", "identical legacy file is deduplicated")
	_assert("/home/aoba" in vm.state.dirs and "/home/operator" in vm.state.dirs, "legacy and canonical dirs remain discoverable")
	_assert(vm.state.cwd == "/home/operator/archive", "non-conflicting legacy cwd migrates")
	vm.state.connected = true
	_assert(vm.read_file("/home/aoba/conflict.txt") == "旧本文", "legacy alias prefers old conflicting file")
	_assert(vm.read_file("/home/operator/conflict.txt") == "新本文", "canonical path reads canonical conflict")
	_assert(vm.read_file("/home/wakaba/wakaba.txt") == "wakaba本文", "wakaba alias remains readable")

	var game := root.get_node("Game")
	game.save_path = "user://qa-rv110-profile-paths.json"
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = "user://qa-rv110-profile-paths.settings.json"
	_assert(game.new_game(), "isolated game save")
	game.state.os_files = {"/home/aoba/notes.txt":"旧メモ", "/home/operator/notes.txt":"新メモ"}
	game.state.desktop_sessions = {"story-0/site-0": {"drafts": {"workstation:/home/aoba/draft.ini":"旧下書き", "workstation:/home/operator/draft.ini":"新下書き"}, "editor_path":"workstation:/home/aoba/draft.ini", "directory":"workstation:/home/aoba", "file_history":[{"path":"workstation:/home/aoba/draft.ini", "remote":false}], "file_forward_history":[]}}
	game.state.vm_states = {"story-0/site-0": {"fs": {"/home/aoba/remote.txt":"旧remote", "/home/operator/remote.txt":"新remote"}}}
	_assert(game.save_game() and game.load_game(), "isolated game reload")
	_assert(game.state.os_files.get("/home/aoba/notes.txt", "") == "旧メモ" and game.state.os_files.get("/home/operator/notes.txt", "") == "新メモ", "local conflicting files survive reload")
	var session: Dictionary = game.state.desktop_sessions["story-0/site-0"]
	_assert(session.editor_path == "workstation:/home/aoba/draft.ini", "conflicting editor path keeps legacy access")
	_assert(session.drafts.get("workstation:/home/aoba/draft.ini", "") == "旧下書き" and session.drafts.get("workstation:/home/operator/draft.ini", "") == "新下書き", "conflicting drafts survive reload")
	_assert(session.directory == "workstation:/home/operator", "non-conflicting session directory migrates")

	for failure in failures: push_error("PROFILE_PATHS: " + failure)
	print("PROFILE_PATHS failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)
