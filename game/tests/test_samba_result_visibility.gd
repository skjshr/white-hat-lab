extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var assertions := 0
var narrow := "--narrow" in OS.get_cmdline_user_args()
var floating := "--floating" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("Samba result visibility timeout"); quit(2))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); print("FAIL ", message)

func frames(count := 5) -> void:
	for _i in count: await process_frame

func control(id: String): return pc.widgets.browser.page.find_child(id, true, false)

func visible_rect(node: Control) -> Rect2:
	if not node.is_visible_in_tree(): return Rect2()
	var rect := node.get_global_rect().intersection(root.get_visible_rect())
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return rect

func fully_visible(id: String) -> void:
	var node = control(id)
	check(node is Control and node.is_visible_in_tree(), "visible in tree " + id)
	if node is Control:
		var actual: Rect2 = node.get_global_rect()
		var clipped := visible_rect(node)
		check(clipped.grow(1).encloses(actual), "fully visible after action " + id + " rect=" + str(actual) + " clipped=" + str(clipped))

func reveal(node: Control) -> void:
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(node)
		ancestor = ancestor.get_parent()
	await frames()

func click(id: String) -> void:
	await frames(6)
	var node = control(id)
	check(node is BaseButton and not node.disabled, "native action enabled " + id)
	if not node is BaseButton or node.disabled: return
	await reveal(node)
	fully_visible(id)
	if not visible_rect(node).grow(1).encloses(node.get_global_rect()): return
	var point: Vector2 = node.get_global_rect().get_center() * Vector2(root.size) / root.get_visible_rect().size
	var count: Array[int] = [0]
	node.pressed.connect(func(): count[0] += 1)
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; Input.parse_input_event(event); Input.flush_buffered_events()
	await frames(10)
	check(count[0] == 1, "exactly one real input press " + id)
	if count[0] != 1: quit(1)

func press(id: String) -> void:
	var node = control(id)
	check(node is BaseButton and not node.disabled, "setup action " + id)
	if node is BaseButton and not node.disabled: node.pressed.emit()

func edit(id: String, value: String) -> void:
	var node = control(id)
	check(node is LineEdit, "editable " + id)
	if node is LineEdit: node.text = value; node.text_changed.emit(value)

func operation(value: String) -> void:
	var picker: OptionButton = control("SambaProbeOperation")
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == value:
			picker.select(index); picker.item_selected.emit(index); return
	check(false, "operation " + value)

func result_visible(content := false, acl := false) -> void:
	# No test scrolling here: the product must reveal the whole observation.
	await frames(10)
	for id in ["SambaProbeResultCard", "SambaProbeResultContext", "SambaProbeResultPath", "SambaProbeResult", "SambaProbeEditInputs"]: fully_visible(id)
	if content: fully_visible("SambaProbeContent")
	if acl: fully_visible("SambaProbeAppliedAcl")
	check(root.gui_get_focus_owner() == control("SambaProbeResultCard"), "result owns focus after execution")

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless": return
	await create_timer(0.6).timeout; await frames(8); await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../../audit/release-candidate/critique/samba-fix")
	DirAccess.make_dir_recursive_absolute(folder)
	var variant := "floating" if floating else "narrow" if narrow else "wide"
	check(root.get_texture().get_image().save_png(folder.path_join(label + "-" + variant + ".png")) == OK, "capture " + label)

func run() -> void:
	Input.use_accumulated_input = false
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames(1)
	game = ui._game(); game.set_process(false)
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	check(ui._new_game(), "isolated company")
	game.set_process(false); game.choose_strategy("advisory")
	check(game.accept_mission(), "tutorial Samba accepted")
	check(game.vm_run("ssh client").contains("Authenticated"), "real customer connection")
	var scale := 1.3 if narrow else 1.0
	var resolution := "960x600" if narrow else "1440x900" if floating else "1920x1080"
	game.set_settings({"resolution":resolution, "text_scale":scale, "window_mode":"windowed", "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900) if floating else Vector2i(1920,1080)
	ui._set_text_scale(scale)
	ui.open_panel("terminal"); pc = ui.desktop; pc._show_app("browser"); await frames()
	if not floating and not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	pc._browse_url(pc.SAMBA_URL, false); await frames()
	press("SambaShare_share"); press("SambaWorkspaceAccess")
	edit("SambaProbeUser", "staff"); operation("put")
	edit("SambaProbeFile", "visibility-order.csv"); edit("SambaProbeLocal", "/srv/data/orders.csv")
	var original: String = game.vm_read("/srv/data/orders.csv")
	var applied: Dictionary = game._vm().state.applied.shares.share.duplicate(true)
	await click("SambaProbeRun")
	check(not bool(pc.samba_ui.probe_result.ok) and str(pc.samba_ui.probe_result.output).contains("ACCESS_DENIED"), "native write observes actual denial")
	check(not game._vm().state.fs.has("/srv/share/visibility-order.csv"), "denied write keeps target absent")
	check(pc.samba_ui.probe_result.applied_context.share == applied, "result stores actual applied ACL")
	check(control("SambaProbeAppliedAcl").text.contains(str(applied.get("write list", ""))), "denial exposes applied write list")
	await result_visible(false, true); await capture("01-denied")
	await click("SambaProbeEditInputs")
	check(root.gui_get_focus_owner() == control("SambaProbeUser"), "retry returns to editable principal")
	# No reveal/helper scrolling after the shortcut: the complete form, including
	# its action, must be available for a repeated request in this viewport.
	for id in ["SambaProbeUser", "SambaProbeOperation", "SambaProbeFilePicker", "SambaProbeFile", "SambaProbeLocal", "SambaProbeRun"]:
		fully_visible(id)
	press("SambaWorkspaceConfig"); edit("SambaWriteList", "staff"); edit("SambaValidUsers", "staff")
	press("SambaWorkspaceAccess")
	await click("SambaProbeRun")
	check(not bool(pc.samba_ui.probe_result.ok), "unsaved settings do not grant write")
	check(pc.samba_ui.probe_result.applied_context.share == applied, "denial context excludes unsaved correct answer")
	await result_visible(false, true)
	press("SambaWorkspaceConfig"); press("SambaSave"); press("SambaRestart"); press("SambaWorkspaceAccess")
	check(str(control("SambaProbeFile").text) == "visibility-order.csv", "ACL editing retains transfer draft")
	var before: Dictionary = game._vm().export_state()
	var save_path: String = game.save_path
	game.save_path = "user://missing-samba-visibility-" + str(OS.get_process_id()) + "/save.json"
	await click("SambaProbeRun"); game.save_path = save_path
	check(not bool(pc.samba_ui.probe_result.ok) and str(pc.samba_ui.probe_result.output).contains("save_failed"), "persistence failure remains an error")
	check(game._vm().export_state() == before, "failed write rolls back exact VM")
	await result_visible(false, true); await capture("02-save-failed")
	await click("SambaProbeRun")
	check(bool(pc.samba_ui.probe_result.ok) and game.vm_read("/srv/share/visibility-order.csv") == original, "retry writes actual bytes")
	operation("get"); edit("SambaProbeLocal", "/home/operator/visibility-order.csv")
	await click("SambaProbeRun")
	check(bool(pc.samba_ui.probe_result.ok), "native read succeeds")
	check(control("SambaProbeContent") is TextEdit and control("SambaProbeContent").text == original, "result contains downloaded bytes")
	await result_visible(true); await capture("03-read-result")
	check(game.save_game() and game.load_game(), "result saves and loads")
	game.set_process(false); pc._load_session(); pc._render_samba(); await frames()
	check(control("SambaProbeContent").text == original and pc.samba_ui.probe_result.applied_context.share == game._vm().state.applied.shares.share, "reopen keeps actual bytes and applied context")
	await click("SambaProbeRun"); await result_visible(true)
	print("SAMBA_RESULT_VISIBILITY_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " failures=", failures.size(), " narrow=", narrow, " floating=", floating)
	quit(0 if failures.is_empty() else 1)
