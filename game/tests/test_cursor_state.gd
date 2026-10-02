extends SceneTree

const UI = preload("res://scripts/interface.gd")

var failures: Array[String] = []

func _init() -> void:
	await process_frame
	var interface := UI.new()
	root.add_child(interface)
	await process_frame
	var game := root.get_node("Game")
	game.save_path = "user://cursor_state_qa.json"
	game.backup_path = "user://cursor_state_qa.json.bak"
	game.previous_path = "user://cursor_state_qa.previous.json"
	game.settings_path = "user://cursor_state_qa_settings.json"
	_assert(interface._new_game(), "new game starts UI cursor test")
	_assert(game.choose_strategy("operations") and game.start_free_career(), "career offers available for cursor test")

	# This is intentionally a real viewport coordinate, rather than checking
	# only Input.mouse_mode.  Run the same script with the GPU QA profile for
	# native Windows pointer evidence.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(Vector2(173, 241))
	await process_frame
	var before := root.get_viewport().get_mouse_position()
	_assert(before.distance_to(Vector2(173,241)) <= 1.5, "native pointer moved to the requested viewport coordinate")
	interface.open_panel("shop")
	await process_frame
	interface.open_panel("company")
	await process_frame
	_assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "UI to UI stays visible")
	var after := root.get_viewport().get_mouse_position()
	_assert(after.distance_to(before) <= 1.5, "UI to UI preserves pointer coordinate")

	# A real OptionButton popup callback rebuilds the sales panel.  Move to the
	# popup item deliberately, then ensure that rebuilding the panel does not
	# add another OS-pointer movement of its own.
	interface.open_panel("sales")
	await process_frame
	var offers: Array = game.state.get("offers", [])
	_assert(not offers.is_empty(), "sales offers available for popup cursor test")
	if not offers.is_empty():
		interface._select_contract(str(offers[0].id))
		await process_frame
		var plan: OptionButton = interface.modal_body.find_child("ContractPlan", true, false)
		_assert(is_instance_valid(plan) and plan.item_count > 1, "contract plan popup exists")
		if is_instance_valid(plan) and plan.item_count > 1:
			var choice_index := 1 if plan.selected == 0 else 0
			plan.show_popup()
			await process_frame
			var popup: PopupMenu = plan.get_popup()
			var item_height: float = popup.size.y / float(plan.item_count)
			var item_position: Vector2 = Vector2(popup.position) + Vector2(popup.size.x * 0.5, item_height * (float(choice_index) + 0.5))
			Input.warp_mouse(item_position)
			await process_frame
			var before_option := root.get_viewport().get_mouse_position()
			await _mouse_click(item_position)
			await process_frame
			var after_option := root.get_viewport().get_mouse_position()
			_assert(after_option.distance_to(before_option) <= 1.5, "option rebuild preserves pointer coordinate")

	interface.close_panel(false)
	_assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "UI to 3D captures only after closing UI")
	interface.open_panel("shop")
	await process_frame
	_assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "3D to UI makes pointer visible")
	var restored := root.get_viewport().get_mouse_position()
	interface.close_panel(false)

	for failure in failures: push_error("CURSOR_STATE: " + failure)
	print("CURSOR_STATE failures=", failures.size(), " before=", before, " after=", after, " restored=", restored)
	quit(1 if not failures.is_empty() else 0)

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _mouse_click(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = position; down.global_position = position; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = position; up.global_position = position; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
	Input.parse_input_event(up)
	await process_frame
