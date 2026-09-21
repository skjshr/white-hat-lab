extends SceneTree

const UI = preload("res://scripts/interface.gd")
var ui
var game
var narrow := "--narrow" in OS.get_cmdline_user_args()
var before := "--before" in OS.get_cmdline_user_args()
var failures: Array[String] = []

func _init() -> void:
	create_timer(70).timeout.connect(func(): push_error("board navigation timeout"); quit(2))
	call_deferred("run")

func frames(count := 5) -> void:
	for _i in count: await process_frame

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func node(id: String):
	return ui.modal.find_child(id, true, false) if is_instance_valid(ui.modal) else null

func press(id: String) -> void:
	var control = node(id)
	check(control is BaseButton and control.is_visible_in_tree() and not control.disabled, "available " + id)
	if control is BaseButton and not control.disabled: control.pressed.emit()

func visible_action(id: String, rightmost := false) -> void:
	var control = node(id)
	check(control is Control and control.is_visible_in_tree(), "visible " + id)
	if not control is Control: return
	var rect: Rect2 = control.get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect), "viewport contains " + id)
	if rightmost: check(rect.end.x > root.size.x - 70, "right edge " + id)

func capture(label: String) -> void:
	await frames(8)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/board-navigation/" + ("before" if before else "after"))
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui = UI.new(); root.add_child(ui)
	await frames()
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	check(ui._new_game({"company":"風の森セキュリティ", "player":"春山", "aya":"小川", "ren":"星野"}), "new QA company")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.guided_intro.skip()
	check(game.choose_strategy("advisory"), "story strategy")
	if not before:
		ui.open_panel("board"); await capture("00-story-board")
		visible_action("GuidePC", true)
		ui.open_panel("door"); await capture("00-story-closeout")
		visible_action("DaySettle", true)
	check(game.start_free_career(), "career setup")
	ui.open_panel("board"); await capture("01-board-empty")
	if not before:
		visible_action("OperationsCloseDay", true)
		check(node("DispatchStaffGrid") == null, "ordinary work does not contain staff queue")
		check(node("OperationsBilling") == null, "finance is outside the work board")
		check(node("CloseButton") == null, "no duplicate management footer close")
		var mounted: int = ui.modal.get_instance_id()
		var state_before: Dictionary = game.state.duplicate(true)
		press("OperationsView_maintenance"); await capture("08-maintenance-empty")
		check(node("DispatchStaffGrid") == null, "maintenance view does not contain staff queue")
		press("OperationsView_staff"); await capture("09-staff")
		check(node("DispatchStaffGrid") != null and node("DispatchTickets") == null, "staff view only owns assignments and queue")
		press("OperationsView_contracts"); await frames()
		check(ui.modal.get_instance_id() == mounted, "view switching keeps shell mounted")
		check(game.state == state_before, "view switching leaves business data untouched")
	ui.open_panel("sales"); await capture("02-sales")
	if not before:
		var visible_rows := 0
		for item in ui.modal_body.find_children("SalesOffer_*", "Button", true, false):
			if item.is_visible_in_tree() and ui.modal_scroll.get_global_rect().encloses(item.get_global_rect()): visible_rows += 1
		check(visible_rows >= 3, "three complete inquiries visible with guidance and enlarged text")
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked", false)) and bool(item.get("market_available", true)))
	check(not offers.is_empty(), "available inquiry")
	if not offers.is_empty():
		ui._select_contract(str(offers[0].id)); await capture("03-quote")
		if before:
			check(game.choose_contract(str(offers[0].id)), "accept real contract")
		else:
			visible_action("AcceptContract", true)
			check(ui.modal_footer.get_global_rect().encloses(node("AcceptContract").get_global_rect()), "quote submit stays outside scrolling content")
			press("AcceptContract"); await frames()
			check(bool(game.state.accepted) and str(game.state.current_contract_id) == str(offers[0].id), "visible quote action accepts the selected real contract")
	ui.open_panel("board"); await capture("04-board-active")
	if not before and not offers.is_empty():
		visible_action("DispatchTicket_" + str(offers[0].id))
		press("DispatchTicket_" + str(offers[0].id)); await frames()
		visible_action("DispatchOpen")
		var member = node("DispatchMemberSelector")
		if member is OptionButton:
			member.select(1); member.item_selected.emit(1)
		var selected: Dictionary = ui.operations_choices.get("dispatch_selected", {}).duplicate(true)
		press("OperationsView_staff"); await frames()
		press("OperationsView_contracts"); await frames()
		check(ui.operations_choices.get("dispatch_selected", {}) == selected, "case target and staff survive view switch")
		await capture("10-selected-work")
	ui.open_panel("door"); await capture("05-closeout")
	if not before:
		visible_action("DaySettle", true)
		check(ui.modal_footer.get_global_rect().encloses(node("DaySettle").get_global_rect()), "next day remains outside scrolling content")
	ui.open_panel("pause"); ui._open_settings(); await capture("06-settings")
	if not before:
		check(not ui._is_management_panel("settings"), "settings is independent from management")
		for forbidden in ["ManagementTabs", "ManagementCash", "ManagementClock", "CompanyBrand"]:
			check(node(forbidden) == null, "settings excludes " + forbidden)
		check(not ui.next_task_guide.visible and not ui.guided_intro.visible, "work guidance hidden in settings")
		visible_action("SettingsApply", true)
	ui._settings_tab("audio"); await capture("07-settings-audio")
	if not before:
		var audio: float = float(game.settings.volume)
		ui._queue_setting("volume", 23)
		press("SettingsApply"); await frames()
		check(float(game.settings.volume) == 23, "options apply saves actual value")
		ui._queue_setting("volume", audio); press("SettingsApply"); await frames()
		var previous: Dictionary = game.settings.duplicate(true)
		ui._queue_setting("max_fps", 30 if int(previous.max_fps) != 30 else 60)
		press("SettingsApply"); await frames()
		check(ui.current_kind == "confirm_display", "display changes still require confirmation")
		ui._process(16); await frames()
		check(game.settings == previous and ui.current_kind == "settings", "confirmation timeout restores settings and returns to options")
		var cancel := InputEventAction.new(); cancel.action = "ui_cancel"; cancel.pressed = true
		ui._queue_setting("max_fps", 30 if int(previous.max_fps) != 30 else 60)
		press("SettingsApply"); await frames()
		ui._unhandled_key_input(cancel); await frames()
		check(game.settings == previous and ui.current_kind == "settings", "Escape cancels display preview within options")
		ui._unhandled_key_input(cancel); await frames()
		check(ui.current_kind == "pause" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape returns to pause without capturing cursor")
	print("BOARD_NAVIGATION failures=", failures.size(), " narrow=", narrow, " before=", before)
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
