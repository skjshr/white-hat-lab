extends SceneTree

const UI = preload("res://scripts/interface.gd")
var ui
var game
var failures: Array[String] = []

func _init() -> void:
	ui = UI.new()
	root.add_child(ui)
	await process_frame
	game = ui._game()
	game.save_path = "user://qa-service-apps.json"
	game.backup_path = "user://qa-service-apps.json.bak"
	game.previous_path = "user://qa-service-apps.previous.json"
	game.settings_path = "user://qa-service-apps-settings.json"
	ui._new_game()
	game.state.accepted = true
	game.vm_run("ssh client")
	ui.open_panel("terminal")
	var pc = ui.desktop
	pc._show_app("monitor")
	await process_frame
	var monitor: Dictionary = pc.widgets.monitor
	_assert(monitor.has("body") and is_instance_valid(monitor.body), "service monitor keeps body API")
	var service_tree: Tree = monitor.get("service_tree")
	var service_item: TreeItem = service_tree.get_root().get_first_child() if service_tree != null and service_tree.get_root() != null else null
	_assert(service_item != null and str(service_item.get_metadata(0)) == str(game.vm_info().service), "real service tree contains selected service")
	if service_item != null:
		service_item.select(0)
		service_tree.item_selected.emit()
	var logs_button: Button = _find_button(monitor.body, "ログ")
	_assert(logs_button != null, "service tabs expose log view")
	if logs_button != null: logs_button.emit_signal("pressed")
	await process_frame
	var detail_button: Button = _find_button(monitor.body, "詳細")
	if detail_button != null: detail_button.emit_signal("pressed")
	await process_frame
	var before_events: int = game._vm().state.events.size()
	var restart: Button = _find_button(monitor.body, "再起動")
	_assert(restart != null, "service detail exposes restart action")
	if restart != null: restart.emit_signal("pressed")
	await process_frame
	_assert(game._vm().state.events.size() > before_events, "restart appends a real service event")
	_assert(str(monitor.get("operation_feedback", "")) == "再起動完了", "restart feedback uses successful VM response")
	var config_path: String = str(game.vm_info().config_path)
	var saved_config: String = game.vm_read(config_path)
	game.vm_write(config_path, "invalid configuration")
	monitor.body.find_child("ServiceRestart", true, false).pressed.emit()
	_assert(not bool(game._vm().state.active) and not bool(monitor.get("operation_ok", true)), "invalid configuration restart reports actual failure")
	game.vm_write(config_path, saved_config)
	monitor.body.find_child("ServiceRestart", true, false).pressed.emit()
	_assert(bool(game._vm().state.active) and bool(monitor.get("operation_ok", false)), "corrected configuration can restart successfully")
	var paths := [game.save_path, game.backup_path, game.previous_path, game.settings_path]
	game.save_path = "user://missing-monitor-" + str(OS.get_process_id()) + "/save.json"
	game.backup_path = game.save_path + ".bak"; game.previous_path = game.save_path + ".previous"; game.settings_path = game.save_path + ".settings"
	monitor.body.find_child("ServiceRestart", true, false).pressed.emit()
	_assert(bool(game._vm().state.active) and str(monitor.get("operation_feedback", "")).contains("保存できませんでした"), "save failure cannot be reported successful merely because rollback remains active")
	game.save_path = paths[0]; game.backup_path = paths[1]; game.previous_path = paths[2]; game.settings_path = paths[3]
	monitor.body.find_child("ServiceRestart", true, false).pressed.emit()
	_assert(bool(monitor.get("operation_ok", false)), "restart succeeds after storage is restored")
	pc._show_app("monitor")
	await process_frame
	var log_tab: Button = _find_button(pc.widgets.monitor.body, "ログ")
	if log_tab != null: log_tab.emit_signal("pressed")
	await process_frame
	var search: LineEdit = _find_line_edit(pc.widgets.monitor.body)
	_assert(search != null, "log view exposes search input")
	if search != null:
		var original = search
		search.grab_focus()
		var query := ""
		for character in "restart":
			query += character
			search.text = query
			search.text_changed.emit(query)
			_assert(search.has_focus(), "log search retains focus after each character")
		await process_frame
		_assert(is_instance_valid(original) and original == _find_line_edit(pc.widgets.monitor.body), "log search keeps its input control")
		_assert(search.has_focus(), "log search retains focus while filtering")
		_assert(int(pc.widgets.monitor.log_query.length()) == 7, "log search query is retained")
		_assert(pc.widgets.monitor.log_view.get_child_count() > 0, "log search filters a live log view")
	for failure in failures: push_error(failure)
	print("PASS: service tree, tabs, restart event, and focused log search" if failures.is_empty() else "FAIL count=%d" % failures.size())
	ui.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

func _find_button(node: Node, text: String):
	for child in node.get_children():
		if child is Button and str(child.text) == text: return child
		var nested = _find_button(child, text)
		if nested != null: return nested
	return null

func _find_line_edit(node: Node):
	for child in node.get_children():
		if child is LineEdit: return child
		var nested = _find_line_edit(child)
		if nested != null: return nested
	return null

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)
