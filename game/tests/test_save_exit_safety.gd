extends SceneTree
## Real save failures must keep the live editor available; a later successful
## window-close request must persist that draft and actually terminate the loop.

class DesktopHolder:
	extends CanvasLayer
	var desktop: Control
	func is_open() -> bool:
		return true

const SAVED := "saved before storage failure"
const PENDING := "player draft retained after failed exit"
const NOTE := "workstation:/home/operator/Documents/save-exit-safety.txt"
const CHILD_COMPLETE := "SAVE_EXIT_CHILD_COMPLETE"
var game: Node
var failed := false

func _initialize() -> void:
	call_deferred("run" if "--save-exit-child" in OS.get_cmdline_user_args() else "run_parent")

func run_parent() -> void:
	# A regression can call quit(0) before any child assertion. Only the parent
	# reports PASS, after checking both process status and the completion marker.
	var profile := "save-exit-child-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", get_script().resource_path, "--quit-after", "300", "--", "--save-exit-child", "--qa-profile=" + profile])
	var captured: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), args, captured, true)
	var output := ""
	for chunk in captured: output += str(chunk)
	print(output)
	print("SAVE_EXIT_CHILD_EXIT ", exit_code)
	if not check(exit_code == 0, "child exited successfully"): return
	var completed := false
	for line in output.split("\n"):
		if line.strip_edges() == CHILD_COMPLETE: completed = true
	if not check(completed, "child reached every save/exit assertion before terminating"): return
	if not check(not output.contains("SCRIPT ERROR") and not output.contains("SAVE_EXIT_FAIL"), "child has no script or assertion errors"): return
	print("SAVE_EXIT_SAFETY_PASS: child completed failure retention and successful retry, then exited")
	quit(0)

func office_source() -> String:
	return "extends \"res://scripts/office.gd\"\nfunc _ready() -> void:\n\tget_tree().auto_accept_quit = false\nfunc _process(_delta: float) -> void:\n\tpass\n"

func check(condition: bool, message: String) -> bool:
	if condition:
		print("CHECK_OK ", message)
		return true
	failed = true
	push_error("SAVE_EXIT_FAIL " + message)
	quit(1)
	return false

func saved_draft(path: String, session: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return ""
	return str(parsed.get("desktop_sessions", {}).get(session, {}).get("drafts", {}).get(NOTE, ""))

func run() -> void:
	game = root.get_node("Game")
	game.set_process(false)
	if not check(str(game.save_path).begins_with("user://qa-"), "isolated QA save"): return
	if not check(game.new_game(), "fresh QA company"): return
	game.set_settings({"volume":0}, false)
	var good_path := str(game.save_path)
	var holder := DesktopHolder.new()
	root.add_child(holder)
	var desktop = load("res://scripts/desktop.gd").new()
	holder.desktop = desktop
	holder.add_child(desktop)
	desktop.setup(game)
	desktop.set_process(false)
	game.state.os_files[NOTE.trim_prefix("workstation:")] = ""
	desktop._open_editor(NOTE)
	var editor: TextEdit = desktop.widgets.editor.editor
	editor.text = SAVED
	if not check(desktop._save_session(), "baseline draft saved by real Desktop"): return
	var session := str(desktop.session_key)
	if not check(saved_draft(good_path, session) == SAVED, "baseline on disk"): return
	editor.text = PENDING
	var blocked_path := good_path + ".io-blocker"
	var blocker := FileAccess.open(blocked_path, FileAccess.WRITE)
	if not check(blocker != null, "create isolated file-as-directory failure"): return
	blocker.store_string("not a directory")
	blocker.close()
	game.save_path = blocked_path.path_join("save.json")
	if not check(not game.save_game(), "real save reports IO failure"): return
	# Compile after autoloads exist. Inherit production _quit/_notification;
	# skip only Office's unrelated 3D setup and per-frame simulation.
	var office_script := GDScript.new()
	office_script.source_code = office_source()
	if not check(office_script.reload() == OK, "minimal Office subclass compiles"): return
	var office = office_script.new()
	root.add_child(office)
	office.ui = holder
	office.started = true
	office.notice = Label.new()
	office.add_child(office.notice)
	print("BEFORE_FAILED_MENU_EXIT")
	office._quit()
	await process_frame
	await process_frame
	if not check(is_instance_valid(desktop) and editor.text == PENDING, "failed menu exit keeps editor and draft alive"): return
	if not check(not str(office.notice.text).is_empty(), "failed exit explains it was cancelled"): return
	if not check(saved_draft(good_path, session) == SAVED, "failed exit retains last good save"): return
	print("BEFORE_FAILED_WM_EXIT")
	office._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	await process_frame
	if not check(editor.text == PENDING, "failed window close keeps draft"): return
	# The no-desktop exit path must also stop on a game-state save failure.
	holder.desktop = null
	office._quit()
	await process_frame
	await process_frame
	holder.desktop = desktop
	if not check(is_instance_valid(office), "failed company-state save keeps office alive"): return
	editor.grab_focus()
	editor.set_caret_column(editor.text.length())
	editor.insert_text_at_caret("; edited after failure")
	var final_draft := PENDING + "; edited after failure"
	if not check(editor.text == final_draft, "input still works after failed exits"): return
	game.save_path = good_path
	print("BEFORE_SUCCESSFUL_WM_EXIT")
	office._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	if not check(saved_draft(good_path, session) == final_draft, "retry persists the live draft"): return
	print(CHILD_COMPLETE)
	await process_frame
	await process_frame
	check(false, "successful window close must terminate the process")
