extends SceneTree

const UI = preload("res://scripts/interface.gd")

var game
var ui
var failures: Array[String] = []
var paths: Array[String] = []

func _init() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("equipment arrival UI QA timed out"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 3) -> void:
	for _i in count: await process_frame

func cleanup() -> void:
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	game = root.get_node("Game")
	game.set_process(false)
	var prefix := "user://qa-equipment-arrival-%s-%s" % [OS.get_process_id(), Time.get_ticks_msec()]
	paths = [prefix + ".json", prefix + ".bak", prefix + ".previous", prefix + "-settings.json"]
	game.save_path = paths[0]; game.backup_path = paths[1]; game.previous_path = paths[2]; game.settings_path = paths[3]
	ui = UI.new(); root.add_child(ui)
	await frames()
	check(game.new_game(), "isolated company starts in a QA save")
	game.state.cash = 200000
	game.state.office_expansion = {"status":"open", "price":28000}
	check(game.buy_equipment("annexdesk_a"), "annex desk enters delivery")
	ui.set_meta("equipment_selected", "annexdesk_a")
	ui.shop_view = "equipment"
	ui.open_panel("shop")
	await frames(5)
	var old_modal = ui.modal
	check(ui.current_kind == "shop" and ui.shop_view == "equipment", "equipment catalog stays open")
	var row: Button = ui.modal_body.find_child("EquipmentSelect_annexdesk_a", true, false)
	check(is_instance_valid(row), "selected annex desk row is mounted")
	if is_instance_valid(row): row.grab_focus()
	var selector := ui.modal.find_child("EquipmentSelectorScroll", true, false) as ScrollContainer
	check(is_instance_valid(selector), "catalog selector scroll exists")
	var saved_scroll := 0
	if is_instance_valid(selector):
		saved_scroll = mini(30, int(selector.get_v_scroll_bar().max_value))
		selector.scroll_vertical = saved_scroll
	await frames()
	if is_instance_valid(selector): saved_scroll = selector.scroll_vertical
	var previous_text := str((ui.modal_footer.find_child("Buy_annexdesk_a", true, false) as Button).text)

	var valid_path := str(game.save_path)
	game.save_path = "user://missing-equipment-arrival-%s-%s/save.json" % [OS.get_process_id(), Time.get_ticks_msec()]
	check(not game.advance_delivery(30.0), "arrival save failure is rejected")
	game.save_path = valid_path
	check(str(game.delivery_for("annexdesk_a").get("status", "")) == "queued", "failed arrival save keeps delivery queued")
	check(str((ui.modal_footer.find_child("Buy_annexdesk_a", true, false) as Button).text) == previous_text, "failed arrival does not show a ready catalog")

	check(game.advance_delivery(30.0), "arrival retry persists successfully")
	await frames(6)
	check(ui.modal == old_modal and ui.current_kind == "shop" and ui.shop_view == "equipment", "refresh keeps the same open catalog shell")
	check(str(game.delivery_for("annexdesk_a").get("status", "")) == "ready", "delivery is saved as ready")
	var plan = ui.modal_footer.find_child("EquipmentPlan_annexdesk_a", true, false)
	var buy = ui.modal_footer.find_child("Buy_annexdesk_a", true, false) as Button
	check(is_instance_valid(plan), "ready delivery exposes its placement action without re-entry")
	check(is_instance_valid(buy) and buy.text != previous_text, "ready delivery state updates in the selected catalog card")
	check(str(ui.get_meta("equipment_selected", "")) == "annexdesk_a", "selected equipment is retained")
	var refreshed_selector := ui.modal.find_child("EquipmentSelectorScroll", true, false) as ScrollContainer
	check(is_instance_valid(refreshed_selector) and refreshed_selector.scroll_vertical == saved_scroll, "catalog selector scroll is retained")
	var focused = ui.get_viewport().gui_get_focus_owner()
	check(is_instance_valid(focused) and str(focused.name) == "EquipmentSelect_annexdesk_a", "focused selection is restored after refresh")
	var ready_state := JSON.stringify(game.state)
	await frames()
	check(JSON.stringify(game.state) == ready_state, "catalog refresh does not mutate the saved company state")

	check(game.buy_equipment("teamdesk"), "second item enters delivery for no-focus refresh")
	ui.set_meta("equipment_selected", "teamdesk")
	ui.open_panel("shop"); await frames(4)
	ui.get_viewport().gui_release_focus()
	check(ui.get_viewport().gui_get_focus_owner() == null, "focus is empty before the second arrival")
	check(game.advance_delivery(30.0), "second delivery reaches ready")
	await frames(5)
	check(ui.current_kind == "shop" and is_instance_valid(ui.modal_footer.find_child("EquipmentPlan_teamdesk", true, false)), "arrival without focus refreshes the open catalog")
	check(ui.get_viewport().gui_get_focus_owner() == null, "empty focus remains empty after arrival refresh")

	check(game.buy_equipment("backup"), "third item enters delivery for stale-route guard")
	ui.set_meta("equipment_selected", "backup")
	ui.open_panel("shop"); await frames(4)
	check(game.advance_delivery(30.0), "third delivery reaches ready")
	ui.open_panel("company")
	await frames(5)
	check(ui.current_kind == "company" and is_instance_valid(ui.modal_body.find_child("CompanyViews", true, false)), "deferred arrival refresh cannot overwrite a newly opened company panel")
	check(not is_instance_valid(ui.modal_body.find_child("EquipmentPanes", true, false)), "stale equipment refresh does not render into another panel")

	print("EQUIPMENT_ARRIVAL_UI_TEST_PASS" if failures.is_empty() else "EQUIPMENT_ARRIVAL_UI_TEST_FAIL " + str(failures))
	ui.queue_free(); await frames()
	cleanup()
	quit(0 if failures.is_empty() else 1)
