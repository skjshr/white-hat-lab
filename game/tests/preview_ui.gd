extends SceneTree

## Isolated visual preview launcher. It uses preview_ui.* saves and never reads the user's save.

var _args: Array[String] = []
var _game
var _office

func _init() -> void:
	for arg in OS.get_cmdline_user_args(): _args.append(str(arg))
	call_deferred("_start")

func _has(flag: String) -> bool:
	return flag in _args

func _value(prefix: String, fallback: String = "") -> String:
	for arg in _args:
		if str(arg).begins_with(prefix): return str(arg).substr(prefix.length())
	return fallback

func _configure_window() -> void:
	var window := root.get_window()
	if _has("--fullscreen"):
		window.size = Vector2i(1920, 1080)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var size := Vector2i(960, 600) if _has("--narrow") else Vector2i(1280, 720)
	window.size = size
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _preview_resolution() -> String:
	return "1920x1080" if _has("--fullscreen") else ("960x600" if _has("--narrow") else "1280x720")

func _preview_window_mode() -> String:
	return "fullscreen" if _has("--fullscreen") else "windowed"

func _start() -> void:
	await process_frame
	await process_frame
	_game = root.get_node("Game")
	var preview_prefix := "user://preview_ui_"+str(OS.get_process_id())
	_game.save_path = preview_prefix+".json"
	_game.backup_path = preview_prefix+".bak"
	_game.previous_path = preview_prefix+".previous.json"
	_game.settings_path = preview_prefix+"_settings.json"
	_game.new_game()
	if _has("--no-tips"): _game.state.ui_help_seen = {"legacy":true}
	_configure_window()
	var scale := 1.3 if (_has("--large") or _has("--large1.3")) else 1.0
	var resolution := _preview_resolution()
	var window_mode := _preview_window_mode()
	_game.set_settings({"quality":"medium", "max_fps":60, "render_scale":1.0, "msaa":2, "shadows":"off", "resolution":resolution, "window_mode":window_mode, "text_scale":scale, "volume":50, "effects_volume":65, "ambient_volume":12})
	await process_frame
	_office = root.get_node_or_null("Office")
	if _office == null:
		_office = load("res://scripts/office.gd").new()
		_office.name = "PreviewOffice"
		root.add_child(_office)
		await process_frame
	_game.set_settings({"quality":"medium", "max_fps":60, "render_scale":1.0, "msaa":2, "shadows":"off", "resolution":resolution, "window_mode":window_mode, "text_scale":scale, "volume":50, "effects_volume":65, "ambient_volume":12})
	await process_frame
	await process_frame
	if _office == null or _office.ui == null:
		push_error("PREVIEW_FAILED: interface did not load")
		quit(2); return
	_prepare_content()
	for frame in 14: await process_frame
	_capture_if_requested()

func _start_office() -> void:
	if not _office.started: _office._start()
	if _office.ui != null and _office.ui.current_kind != "": _office.ui.close_panel(false)
	if _office.ui != null and _office.ui.controls.has("menu"): _office.ui.controls.menu.hide()

func _ensure_case() -> void:
	if bool(_game.state.get("accepted", false)): return
	_game.choose_strategy("advisory")
	_game.accept_mission()

func _prepare_content() -> void:
	var app := _value("--app=")
	var panel := _value("--panel=")
	if _has("--resume-qa"):
		var saved := FileAccess.get_file_as_string("user://qa-release-v16.json")
		var fixture := FileAccess.open(_game.save_path,FileAccess.WRITE)
		fixture.store_string(saved); fixture.close(); _game.load_game()
		_game.state.ui_help_seen={"legacy":true}
	if _has("--editor"): app = "editor"
	elif _has("--browser"): app = "browser"
	elif _has("--files"): app = "files"
	elif _has("--mail"): app = "mail"
	if _has("--settings"): panel = "settings"
	if _has("--profile"):
		_start_office(); _office.ui._open_new_company(); return
	if _has("--compound"):
		_game.choose_strategy("advisory"); _game.state.peak_profit = 7000; _game.start_free_career()
		for offer in _game.state.offers:
			if offer.case_id == "composite-branch-reopen": _game.choose_contract(offer.id); break
		_start_office(); _office.ui.open_panel("terminal"); _game.vm_run("ssh client")
		if not app.is_empty(): _office.ui.desktop._show_app(app)
		if app == "mail" and _has("--reading"):
			_office.ui.desktop.widgets.mail.reading=true
			_office.ui.desktop._refresh_mail()
		return
	if _has("--work") or _has("--case") or app in ["mail", "files", "terminal", "editor", "browser", "monitor", "verify", "team", "manual", "receipt"]:
		_ensure_case(); _start_office(); _office.ui.open_panel("terminal"); _game.vm_run("ssh client")
		if _has("--diagnostics"): app = "verify"
		if _has("--shell"): app = "terminal"
		if _has("--settings"): panel = "settings"
		if app == "editor": _office.ui.desktop._open_config()
		elif not app.is_empty(): _office.ui.desktop._show_app(app)
		if app == "mail" and _has("--reading"):
			_office.ui.desktop.widgets.mail.reading=true
			_office.ui.desktop._refresh_mail()
		if app == "browser" and not _value("--url=").is_empty():
			_office.ui.desktop.url_edit.text=_value("--url="); _office.ui.desktop._browse()
		if _has("--desktop"):
			for window in _office.ui.desktop.windows.values(): window.hide()
			_office.ui.desktop.current_app=""
		if _has("--coffee"): panel = "coffee"
		if not panel.is_empty(): _office.ui.close_panel(false); _office.ui.open_panel(panel)
		return
	if _has("--board"):
		_game.choose_strategy("advisory"); _game.start_free_career(); _start_office(); _office.ui.open_panel("board"); return
	if _has("--coffee"):
		_start_office(); _office.ui.open_panel("coffee"); return
	if not panel.is_empty():
		_start_office(); _office.ui.open_panel(panel)

func _capture_if_requested() -> void:
	var path := _value("--capture=")
	if path.is_empty(): return
	var texture := root.get_viewport().get_texture()
	if texture == null:
		print("PREVIEW_CAPTURE unavailable: renderer has no viewport texture")
		if _has("--quit-capture"): quit(2)
		return
	var image := texture.get_image()
	if image == null:
		print("PREVIEW_CAPTURE unavailable: renderer returned no image")
		if _has("--quit-capture"): quit(2)
		return
	var err := image.save_png(path)
	print("PREVIEW_CAPTURE path=", path, " error=", err)
	if _has("--quit-capture"): quit(0 if err == OK else 1)
