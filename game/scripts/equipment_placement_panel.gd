extends RefCounted
const RULES = preload("res://scripts/placement_rules.gd")
const CANVAS = preload("res://scripts/equipment_placement_canvas.gd")
const M = preload("res://scripts/management_ui.gd")

static func open(ui, id: String) -> void:
	if id not in RULES.FLOOR_IDS: return
	if str(ui.get_meta("equipment_plan_id", "")) != id:
		var at: Vector2 = RULES.FIXED_SLOTS.get(id, Vector2.ZERO)
		ui.set_meta("equipment_plan_position", at)
		ui.set_meta("equipment_plan_rotation", PI if id in ["teamdesk", "workstation"] else 0.0)
	ui.set_meta("equipment_plan_id", id)
	ui.open_panel("shop")

static func _delivery(ui):
	var office: Node = ui.get_parent()
	return office.get_node_or_null("EquipmentDelivery") if office != null else null

static func _button(ui, text: String, callback: Callable, id: String, role := "quiet") -> Button:
	var button: Button = ui._button(text, callback)
	button.name = id; M.button(button, role)
	ui.modal_footer.add_child(button)
	return button

static func _leave(ui) -> void:
	ui.set_meta("equipment_selected", str(ui.get_meta("equipment_plan_id", "")))
	ui.set_meta("equipment_plan_id", "")
	ui.open_panel("shop")

static func build(ui) -> void:
	for host in [ui.modal_body, ui.modal_footer]:
		for child in host.get_children(): host.remove_child(child); child.queue_free()
	var g = ui._game()
	var id := str(ui.get_meta("equipment_plan_id", ""))
	var title := id
	for item in g.equipment_catalog():
		if str(item.id) == id: title = str(item.title)
	ui.modal_body.add_theme_constant_override("separation", 6)
	ui.modal_body.add_child(ui._label(title + " / 配置図", 19, M.INK))
	ui.modal_body.add_child(ui._label("床を選択 → 向きを調整 → 設置　/　矢印キーでも移動", 13, M.MUTED))
	var map = CANVAS.new()
	ui.modal_body.add_child(map)
	map.configure(id, g.delivery_orders(), g.office_expanded(), float(ui.text_scale), {"aya":g.member_name("aya"), "ren":g.member_name("ren")}, func(at: Vector2):
		ui.set_meta("equipment_plan_position", at); _refresh(ui)
	)
	var response: Label = ui._label("", 14, M.INK)
	response.name = "EquipmentPlanResponse"; response.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.modal_body.add_child(response)
	_button(ui, "カタログへ戻る", func(): _leave(ui), "EquipmentPlanBack")
	_button(ui, "↻ 90°", func():
		ui.set_meta("equipment_plan_rotation", fposmod(float(ui.get_meta("equipment_plan_rotation", 0.0)) + PI / 2, TAU)); _refresh(ui)
	, "EquipmentPlanRotate", "secondary")
	var space := Control.new(); space.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ui.modal_footer.add_child(space)
	_button(ui, "この位置に設置", func(): _install(ui), "EquipmentPlanConfirm", "primary")
	_refresh(ui)

static func _refresh(ui) -> void:
	if not is_instance_valid(ui.modal): return
	var map = ui.modal.find_child("EquipmentPlacementMap", true, false)
	var response = ui.modal.find_child("EquipmentPlanResponse", true, false)
	var confirm = ui.modal.find_child("EquipmentPlanConfirm", true, false)
	if map == null or response == null or confirm == null: return
	var id := str(ui.get_meta("equipment_plan_id", ""))
	var at: Vector2 = ui.get_meta("equipment_plan_position", Vector2.ZERO)
	var rotation: float = float(ui.get_meta("equipment_plan_rotation", 0.0))
	var delivery = _delivery(ui)
	var reason: String = "オフィスの搬入担当が不在です。" if delivery == null else str(delivery.plan_error(id, [at.x, 0.0, at.y], rotation))
	map.set_candidate(at, rotation, reason.is_empty())
	confirm.disabled = not reason.is_empty()
	response.text = "✓ この位置に設置できます" if reason.is_empty() else "× " + reason
	response.add_theme_color_override("font_color", M.ACCENT if reason.is_empty() else M.DANGER)

static func _install(ui) -> void:
	var delivery = _delivery(ui)
	if delivery == null: return
	var id := str(ui.get_meta("equipment_plan_id", ""))
	var at: Vector2 = ui.get_meta("equipment_plan_position", Vector2.ZERO)
	var result: Dictionary = delivery.install_from_plan(id, [at.x, 0.0, at.y], float(ui.get_meta("equipment_plan_rotation", 0.0)))
	if bool(result.get("ok", false)):
		_leave(ui)
	else:
		_refresh(ui)
		var response = ui.modal.find_child("EquipmentPlanResponse", true, false)
		if response is Label:
			response.text = "× " + str(result.get("error", "設置できませんでした。"))
			response.add_theme_color_override("font_color", M.DANGER)
