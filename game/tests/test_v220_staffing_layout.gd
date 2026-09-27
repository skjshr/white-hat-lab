extends SceneTree

var ui
var game
var narrow := false
var capture_enabled := false
var failures: Array[String] = []

func _init() -> void:
	narrow = "--narrow" in OS.get_cmdline_user_args()
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	create_timer(30.0).timeout.connect(func(): push_error("v2.2 staffing layout timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count: int = 5) -> void:
	for _index in count: await process_frame

func control(id: String):
	return ui.modal.find_child(id, true, false) if is_instance_valid(ui.modal) else null

func assert_inside(id: String, host: Control) -> void:
	var node: Variant = control(id)
	check(node is Control and host.get_global_rect().encloses(node.get_global_rect()), id + " fits its control row")

func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(3)
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/ui-refinement-20260922/staffing")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	var image: Image = root.get_texture().get_image()
	check(image.save_png(folder.path_join(label + suffix + ".png")) == OK, "capture " + label)

func run() -> void:
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames(3)
	game = ui._game(); game.set_process(false)
	check(ui._new_game(), "new game")
	check(game.choose_strategy("advisory") and game.start_free_career(), "career setup")
	game.state.cash = 30000
	check(game.buy_equipment("teamdesk"), "desk bought")
	game.advance_delivery(30.0)
	check(game.take_delivery("teamdesk") and game.begin_delivery_placement("teamdesk") and game.place_delivery("teamdesk", game.equipment_slot("teamdesk")), "desk installed")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	ui.open_panel("staffing"); await frames(8)
	var candidate_row: Variant = control("CandidateShift_mio")
	check(candidate_row is OptionButton, "candidate shift control")
	var hire: Variant = control("Hire_mio")
	check(hire is Button and not hire.disabled, "hire enabled")
	if hire is Button: assert_inside("CandidateShift_mio", hire.get_parent())
	await capture("candidate")
	if hire is Button and not hire.disabled: hire.pressed.emit()
	await frames(8)
	check(game.state.staff.has("mio"), "hire persists")
	var shift: Variant = control("Shift_mio")
	var release: Variant = control("Release_mio")
	check(shift is OptionButton and release is Button, "hired controls")
	if shift is OptionButton: assert_inside("Shift_mio", shift.get_parent())
	if release is Button: assert_inside("Release_mio", release.get_parent())
	await capture("hired")
	for failure in failures: push_error(failure)
	print("V220_STAFFING_LAYOUT failures=", failures.size(), " narrow=", narrow)
	quit(0 if failures.is_empty() else 1)
