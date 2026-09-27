extends SceneTree

var ui
var game
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(65).timeout.connect(func(): push_error("UI polish timeout"); quit(2))
	call_deferred("run")

func frames(count := 8) -> void:
	for _i in count: await process_frame

func check(value: bool, label: String) -> void:
	if not value: failures.append(label); print("FAIL ", label)

func capture(label: String) -> void:
	await frames()
	if not capture_enabled or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/v220/ui" if "--v220-capture" in OS.get_cmdline_user_args() else "res://../artifacts/simulator/ui-refinement-20260922/ui-polish")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func check_chrome() -> void:
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	for id in ["ManagementHeader", "ManagementTabs", "ManagementFooter", "ManagementClose"]:
		var control = ui.modal.find_child(id, true, false)
		check(control is Control and viewport.encloses(control.get_global_rect()), "visible " + id)
	var tabs = ui.modal.find_child("ManagementTabs", true, false)
	if tabs != null:
		var selected := 0
		for tab in tabs.get_children():
			if bool(tab.get_meta("navigation_selected", false)): selected += 1
			check(tab.size.x >= tab.get_minimum_size().x, "tab label fits " + tab.name)
		check(selected == 1, "exactly one selected management tab")

func check_shop() -> void:
	var selectors: Array[Node] = ui.modal_body.find_children("EquipmentSelect_*", "Button", true, false)
	check(selectors.size() == game.equipment_catalog().size() + 1, "all equipment and expansion selectors retained")
	for selector in selectors:
		for label in selector.find_children("*", "Label", true, false):
			check(label.get_global_rect().end.x <= selector.get_global_rect().end.x + 1, "selector label fits " + str(label.text))
	var actions: Array[Node] = []
	for candidate in ui.modal_footer.find_children("*", "Button", true, false):
		if str(candidate.name).begins_with("Buy_") or candidate.name == "BuyOfficeExpansion": actions.append(candidate)
	check(actions.size() == 1, "one selected equipment action in footer")
	if actions.size() == 1:
		check(ui.modal_footer.get_global_rect().encloses(actions[0].get_global_rect()), "selected action inside footer")
		check(actions[0].get_global_rect().end.x <= root.size.x - 12, "selected action inside screen")
	check(ui.modal_scroll.get_h_scroll_bar().max_value <= ui.modal_scroll.size.x + 1, "shop has no hidden horizontal overflow")

func select_equipment(id: String) -> void:
	var selector = ui.modal.find_child("EquipmentSelect_" + id, true, false)
	check(selector is Button and selector.is_visible_in_tree(), "selector visible " + id)
	if selector is Button:
		var selector_scroll = ui.modal.find_child("EquipmentSelectorScroll", true, false)
		if selector_scroll is ScrollContainer:
			selector_scroll.ensure_control_visible(selector)
			await frames(2)
			check(selector_scroll.get_global_rect().encloses(selector.get_global_rect()), "selector scrolls into view " + id)
		selector.pressed.emit(); await frames(4)
		check(str(ui.get_meta("equipment_selected", "")) == id, "selection persists " + id)
		var action = ui.modal_footer.find_child("Buy_" + id, true, false)
		check(action is Button, "footer action follows selection " + id)

func check_equipment_states() -> void:
	game.state.equipment = ["backup"]
	ui.open_panel("shop"); await frames(4)
	await select_equipment("backup")
	var owned = ui.modal_footer.find_child("Buy_backup", true, false)
	check(owned is Button and owned.disabled, "owned equipment action disabled")
	game.state.cash = 100000
	check(game.buy_equipment("monitor"), "inbound equipment order created")
	ui.open_panel("shop"); await frames(4)
	await select_equipment("monitor")
	var inbound = ui.modal_footer.find_child("Buy_monitor", true, false)
	check(inbound is Button and inbound.disabled, "inbound equipment action disabled")
	game.state.cash = 0
	ui.open_panel("shop"); await frames(4)
	for id in ["plant", "workstation", "diagnostic", "teamdesk", "annexdesk_a", "annexdesk_b"]:
		await select_equipment(id)
		var action = ui.modal_footer.find_child("Buy_" + id, true, false)
		check(action is Button and action.disabled, "unaffordable equipment action disabled " + id)

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	game.new_game({"company":"風の森セキュリティ", "player":"春山", "aya":"小川", "ren":"星野"})
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.open_main_menu(); await capture("title")
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	for button in ui.controls.menu.find_children("*", "Button", true, false):
		if button.is_visible_in_tree(): check(viewport.encloses(button.get_global_rect()), "menu button inside viewport " + str(button.text))
	game.choose_strategy("advisory"); game.start_free_career()
	game.state.cash = 100000; game.state.credit = 100000
	game.state.skills = {"advisory":5, "operations":5, "response":5}
	ui.controls.menu.hide(); ui.guided_intro.skip()
	ui.open_panel("shop"); await capture("equipment"); check_chrome(); check_shop()
	for id in ["backup", "monitor", "plant", "workstation", "diagnostic", "teamdesk", "annexdesk_a", "annexdesk_b"]:
		await select_equipment(id)
	var expansion_selector = ui.modal.find_child("EquipmentSelect_office_expansion", true, false)
	check(expansion_selector is Button, "expansion selector retained")
	if expansion_selector is Button:
		var selector_scroll = ui.modal.find_child("EquipmentSelectorScroll", true, false)
		if selector_scroll is ScrollContainer:
			selector_scroll.ensure_control_visible(expansion_selector)
			await frames(2)
			check(selector_scroll.get_global_rect().encloses(expansion_selector.get_global_rect()), "selector scrolls into view office_expansion")
		expansion_selector.pressed.emit(); await frames(4)
		check(ui.get_meta("equipment_selected", "") == "office_expansion", "expansion selection persists")
		check(ui.modal_footer.find_child("BuyOfficeExpansion", true, false) is Button, "expansion footer action retained")
	var buy = ui.modal_footer.find_child("BuyOfficeExpansion", true, false)
	if buy is Button: buy.grab_focus(); await capture("equipment-focus")
	ui.modal_scroll.scroll_vertical = 99999; await capture("equipment-bottom")
	# Resize the existing catalog without reconstructing the panel or its controls.
	var mounted: int = ui.modal.get_instance_id()
	var original := root.size
	root.size = Vector2i(1180, 740) if narrow else Vector2i(960, 600)
	await frames(12); check_shop()
	check(ui.modal.get_instance_id() == mounted, "resize retains panel")
	check(str(ui.get_meta("equipment_selected", "")) == "office_expansion", "resize retains selected expansion")
	root.size = original; await frames(12)
	await check_equipment_states()
	await capture("equipment-unavailable")
	for kind in ["company", "staffing"]:
		ui.open_panel(kind); await capture(kind); check_chrome()
	ui.open_panel("settings"); await capture("options")
	print("UI_POLISH failures=", failures.size(), " narrow=", narrow)
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
