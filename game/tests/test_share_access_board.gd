extends SceneTree
## Native input through the real first-story accept/repair/deliver loop.
## Setup, comparison-baseline capture, interruption, and reload use public APIs.
## Acceptance, navigation, measurement, config editing, restart, and delivery use input.

var ui
var game
var pc
var failures: Array[String] = []
var assertions := 0
var clicks := 0
var keys := 0
var wheels := 0
var narrow := "--narrow" in OS.get_cmdline_user_args()
const IDS := ["staff-read", "staff-write", "guest-read", "guest-write"]
const CONFIG := "[global]\nserver role = standalone server\nmap to guest = Bad User\n[share]\npath = /srv/share\nread only = no\nguest ok = no\nvalid users = staff\n"

func _init() -> void:
	create_timer(120).timeout.connect(func(): push_error("SHARE_BOARD_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); print("FAIL ", message)

func frames(count := 6) -> void:
	for _i in count: await process_frame

func node(id: String): return pc.find_child(id, true, false)

func visible_rect(c: Control) -> Rect2:
	if c == null or not c.is_visible_in_tree(): return Rect2()
	var rect := c.get_global_rect().intersection(root.get_visible_rect())
	var parent := c.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return rect

func mouse(point: Vector2, button: MouseButton) -> void:
	var pixel := point * Vector2(root.size) / root.get_visible_rect().size
	var motion := InputEventMouseMotion.new(); motion.position = pixel; motion.global_position = pixel
	Input.parse_input_event(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = pixel; event.global_position = pixel
		event.button_index = button; event.pressed = down; Input.parse_input_event(event)
		await frames(1)

func reveal(c: Control) -> bool:
	for _attempt in 60:
		if not is_instance_valid(c) or not c.is_visible_in_tree(): return false
		if visible_rect(c).grow(1).encloses(c.get_global_rect()): return true
		var parent := c.get_parent()
		var scroll: ScrollContainer
		while parent != null:
			if parent is ScrollContainer: scroll = parent; break
			parent = parent.get_parent()
		if scroll == null: return false
		var direction := MOUSE_BUTTON_WHEEL_DOWN if c.get_global_rect().get_center().y > scroll.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP
		await mouse(scroll.get_global_rect().get_center(), direction); wheels += 1; await frames(2)
	return false

func click(id: String) -> void:
	await frames()
	var c = node(id)
	check(c is Control and c.is_visible_in_tree(), "visible native action " + id)
	if not c is Control or not c.is_visible_in_tree(): return
	if c is BaseButton:
		check(not c.disabled, "enabled native action " + id)
		if c.disabled: return
	var reachable: bool = await reveal(c)
	check(reachable, "reachable native action " + id)
	if not reachable: return
	await frames(4)
	await mouse(visible_rect(c).get_center(), MOUSE_BUTTON_LEFT); clicks += 1
	await frames(8)

func key(code: Key, ctrl := false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code
		event.ctrl_pressed = ctrl; event.pressed = down; Input.parse_input_event(event)
		await frames(1)
	keys += 1

func type_config() -> void:
	await click("SambaOpenConfig")
	await click("ConfigEditor")
	await key(KEY_A, true)
	for character in CONFIG:
		var event := InputEventKey.new(); event.unicode = character.unicode_at(0); event.pressed = true
		if character == "\n": event.keycode = KEY_ENTER
		Input.parse_input_event(event)
	await frames()
	check(str(node("ConfigEditor").text) == CONFIG, "real text input edits configuration")
	await key(KEY_S, true)
	check(game.vm_read("/etc/samba/smb.conf") == CONFIG, "real Ctrl S saves exact config bytes")
	await click("TaskbarApp_browser"); await click("SambaTabShares")

func probe(id: String) -> Dictionary:
	for p in game.diagnostic_probes():
		if str(p.id) == id: return p
	return {}

func board_geometry() -> void:
	for id in ["ExitDesktop", "DesktopReturn", "ShowDesktop"]:
		var action = pc.find_child(id, true, false)
		if action is Control and action.is_visible_in_tree():
			check(visible_rect(action).grow(1).encloses(action.get_global_rect()), "desktop exit and return fully visible " + id)
	for id in IDS:
		var c = node("SambaAccess_" + id)
		check(c is Button and c.is_visible_in_tree(), "board operation " + id)
		if c is Button:
			check(c.get_global_rect().size.y >= 30, "usable action height " + id)
			check(c.get_global_rect().position.x >= 0 and c.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "no horizontal action clipping " + id)
			check(visible_rect(c).grow(1).encloses(c.get_global_rect()), "four actions visible together " + id)
		var result = node("SambaAccessResult_" + id)
		if result is Label:
			check(result.size.y >= result.get_minimum_size().y and visible_rect(result).grow(1).encloses(result.get_global_rect()), "current result and requirement fully visible " + id + " size=" + str(result.size) + " minimum=" + str(result.get_minimum_size()))
	check(is_equal_approx(float(game.settings.text_scale), 1.3 if narrow else 1.0) and is_equal_approx(ui.text_scale, 1.3 if narrow else 1.0), "Game and Interface use actual requested font scale")

func capture(label: String) -> void:
	await frames(8)
	for id in ["ExitDesktop", "DesktopReturn", "ShowDesktop"]:
		var action = pc.find_child(id, true, false)
		if action is Control and action.is_visible_in_tree():
			check(visible_rect(action).grow(1).encloses(action.get_global_rect()), "desktop controls visible at " + label + " " + id)
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../../audit/share-20261005/" + ("narrow" if narrow else "wide"))
	if not OS.get_environment("WHL_CAPTURE_DIR").is_empty(): folder = OS.get_environment("WHL_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "capture " + label)

func run() -> void:
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	game = ui._game(); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"), "QA isolated from player save")
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	check(ui._new_game(), "new company starts with normal funds")
	game.set_process(false); game.choose_strategy("advisory"); ui.guided_intro.skip()
	var scale := 1.3 if narrow else 1.0
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "text_scale":scale, "window_mode":"windowed" if narrow else "borderless", "volume":0}, false)
	ui._set_text_scale(scale); root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	root.get_node("Graphics").apply_settings(game.settings)
	check(root.get_visible_rect().size.is_equal_approx(Vector2(960,600) if narrow else Vector2(1280,720)), "native test uses actual game content scale")
	ui.open_panel("terminal"); pc = ui.desktop; pc._show_app("mail"); await frames()
	if not pc.windows.mail.maximized: pc.windows.mail.toggle_maximize()
	await click("GuideMailMessage"); await click("GuideMailAccept")
	check(bool(game.state.accepted), "native email click accepts first story")
	if not game.state.accepted: quit(1); return
	await frames()
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	await click("SambaConnect")
	check(bool(game.vm_info().connected), "native connection opens customer")
	check(game.capture_baseline(), "public API captures original evidence for delivery rating")
	pc._render_samba(); await frames()
	check(node("SambaAccessBoard") != null, "single-share home is object workbench")
	if node("SambaAccessBoard") == null: quit(1); return
	board_geometry(); await capture("01-unmeasured")
	var before_view := JSON.stringify(game.state)
	pc._render_samba(); await frames()
	check(JSON.stringify(game.state) == before_view, "board rendering performs no hidden work")
	for id in IDS:
		var minutes: float = game.state.work.minutes
		if id == "staff-write":
			await key(KEY_TAB)
			check(root.gui_get_focus_owner() == node("SambaAccess_" + id), "Tab reaches next document operation")
			if root.gui_get_focus_owner() == node("SambaAccess_" + id): await key(KEY_SPACE); await frames(10)
			else: await click("SambaAccess_" + id)
		else: await click("SambaAccess_" + id)
		check(bool(probe(id).get("recorded", false)), "native probe recorded " + id)
		check(root.gui_get_focus_owner() == node("SambaAccess_" + id), "completed action retains keyboard focus " + id)
		check(is_equal_approx(float(game.state.work.minutes) - minutes, game.action_minutes("measurement", 3.0)), "exactly one measured work charge " + id)
		var output := str(probe(id).get("result", ""))
		check(output.contains("ACCESS_DENIED") if id == "staff-write" else not output.contains("NT_STATUS_"), "actual initial access " + id)
		if id == "guest-read": await capture("02a-business-blocked-and-exposed")
	await capture("02-unsafe-access")
	var original_relation = game.state.customer_relations.duplicate(true)
	check(not game.can_deliver(), "unsafe access cannot be delivered")
	await click("SambaShare_share")
	check(node("SambaWorkspaceConfig") != null, "folder opens existing real configuration workspace")
	await click("SambaTabShares")
	check(node("SambaAccessBoard") != null, "native navigation returns to measured object home")
	await type_config()
	check(bool(game._vm().state.dirty), "saved config is pending")
	check(str(game._vm().state.applied.guest) == "write", "saving alone leaves unsafe guest access in effect")
	await capture("03-saved-not-applied")
	await click("SambaRestart")
	check(str(game._vm().state.applied.staff) == "write" and str(game._vm().state.applied.guest) == "none", "native restart applies player correction")
	for id in IDS: check(not bool(probe(id).get("fresh", false)), "changed config invalidates measurement " + id)
	await capture("04-retest-needed")
	var valid_path: String = game.save_path
	game.save_path = "user://share-board-nonexistent-parent/sub/save.json"
	var before_failure := JSON.stringify(game.state)
	var vm_before_failure := JSON.stringify(game._vm().export_state())
	await click("SambaAccess_staff-write")
	check(JSON.stringify(game.state) == before_failure and JSON.stringify(game._vm().export_state()) == vm_before_failure, "failed durable action restores VM evidence clock and costs")
	check(not bool(probe("staff-write").fresh), "failed save cannot create success evidence")
	var action_error = node("SambaAccessActionError")
	check(action_error is Label and action_error.text.contains("保存失敗") and visible_rect(action_error).grow(1).encloses(action_error.get_global_rect()), "save failure has fully visible inline action feedback")
	game.save_path = valid_path
	await capture("05-save-failure")
	for _round in 3:
		for id in IDS:
			if not bool(probe(id).get("fresh", false)) or not bool(probe(id).get("passed", false)): await click("SambaAccess_" + id)
	check(game.vm_read("/srv/share/orders.csv") == game.vm_read("/srv/data/orders.csv"), "successful staff save transfers real source bytes")
	for id in IDS: check(bool(probe(id).fresh) and bool(probe(id).passed), "all legitimate and forbidden actions confirmed " + id)
	await capture("06-repaired")
	var measured := JSON.stringify(game.diagnostic_probes())
	ui.open_panel("board"); await frames(); ui.open_panel("terminal"); pc = ui.desktop
	if pc.current_app != "browser": await click("TaskbarApp_browser")
	await click("SambaTabShares")
	check(JSON.stringify(game.diagnostic_probes()) == measured, "interruption keeps measured customer state")
	check(game.save_game() and game.load_game(), "real save and resume")
	pc._load_session()
	if pc.current_app != "browser": await click("TaskbarApp_browser")
	await click("SambaTabShares")
	check(JSON.stringify(game.diagnostic_probes()) == measured, "resume preserves measurement freshness and bytes")
	board_geometry(); await capture("07-resumed")
	await click("StartButton"); await click("StartApp_verify"); await click("DiagnosticValidate")
	check(game.can_deliver(), "actual measurements satisfy delivery conditions")
	var cash: int = game.state.cash
	await click("GuideDeliver")
	check(game.current_done() and int(game.state.cash) > cash, "native delivery pays actual contract")
	check(game.state.customer_relations != original_relation, "delivery records customer outcome")
	check(not game.company_cycle_view().get("opportunities", []).is_empty(), "real delivery creates next customer consultation")
	await capture("08-result")
	check(game.save_game() and game.load_game() and game.current_done(), "delivery aftermath survives reload")
	print("SHARE_BOARD assertions=", assertions, " failures=", failures.size(), " clicks=", clicks, " keys=", keys, " wheels=", wheels, " cash=", game.state.cash, " rating=", game.state.last_receipt.get("rating", ""))
	quit(0 if failures.is_empty() else 1)
