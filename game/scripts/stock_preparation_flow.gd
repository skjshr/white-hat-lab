extends Control
## Positions represent the persisted physical stock state, never a planned or
## inferred repair. Moving dots only indicate recorded inbound/outbound transit.
signal unit_selected(id: String)
const M = preload("res://scripts/management_ui.gd")
const ART = preload("res://scripts/equipment_art.gd")
const STOCK = preload("res://scripts/customer_stock.gd")
var ui
var view: Dictionary = {}
var objects: Dictionary = {}
var headings: Array[Label] = []
var ghost: TextureRect
var scale_factor := 1.0

func setup(interface, data: Dictionary) -> void:
	ui = interface
	scale_factor = float(ui.text_scale)
	name = "StockPreparationFlow"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for title in ["入荷・保管", "設定台", "顧客先"]:
		var label: Label = ui._label(title, 15, M.INK)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label); headings.append(label)
	ghost = TextureRect.new(); ghost.name = "PreparationMissingAppliance"
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.modulate.a = 0.22; ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	resized.connect(_layout)
	set_view(data)

func set_view(data: Dictionary) -> void:
	view = data
	var live: Array[String] = []
	for raw in view.get("units", []):
		if not raw is Dictionary: continue
		var unit: Dictionary = raw; var id := str(unit.get("id", "")); live.append(id)
		if not objects.has(id): _make_object(id)
		var item: Dictionary = objects[id]
		var selected := id == str(view.get("selected", ""))
		M.button(item.button, "secondary", selected)
		item.button.tooltip_text = "%s / %s / %s" % [str(unit.get("serial", "")), str(unit.get("model", "")), str(unit.get("owner", "未割当"))]
		item.image.texture = ART.icon(str(STOCK.product(str(unit.get("sku", ""))).get("icon", "")))
		item.model.text = str(unit.get("model", ""))
		item.serial.text = str(unit.get("serial", ""))
		var status := str(unit.get("status", ""))
		var remaining := maxi(0, ceili((STOCK.DELIVERY_WAIT_SECONDS if status == "queued" else STOCK.SHIPPING_SECONDS) - float(unit.get("elapsed_seconds", 0))))
		item.status.text = {"queued":"入荷まで %d秒" % remaining,"ready":"↓ 受取待ち","stored":"棚 %d" % (int(unit.get("shelf_slot", 0)) + 1),"carried":"手持ち","staged":"● 机に接続","shipping":"発送中 %d秒" % remaining,"delivered":"✓ 受領"}.get(status, "? 状態不明")
		item.owner.text = str(unit.get("owner", "")) if not str(unit.get("contract_id", "")).is_empty() else ""
	for id in objects.keys():
		if id not in live: objects[id].button.queue_free(); objects.erase(id)
	ghost.texture = ART.icon(str(view.get("icon", "stock_gateway")))
	ghost.visible = bool(view.get("has_requirement", false)) and not _has_staged() and str(view.get("assigned", {}).get("status", "")) not in ["shipping", "delivered"]
	set_process(view.get("units", []).any(func(unit): return str(unit.get("status", "")) in ["queued", "shipping"]))
	_layout(); queue_redraw()

func _process(_delta: float) -> void:
	var game = ui._game() if is_instance_valid(ui) else null
	if game != null:
		for unit in view.get("units", []):
			if str(unit.get("status", "")) not in ["queued", "shipping"]: continue
			var current: Dictionary = game.customer_stock_for(str(unit.get("id", "")))
			unit["elapsed_seconds"] = float(current.get("elapsed_seconds", 0))
	queue_redraw()

func _make_object(id: String) -> void:
	var button := Button.new(); button.name = "PreparationUnit_" + id.validate_node_name()
	button.pressed.connect(func(): unit_selected.emit(id))
	add_child(button)
	var column := VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6; column.offset_right = -6; column.offset_top = 5; column.offset_bottom = -5
	column.add_theme_constant_override("separation", 0); column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	var image := TextureRect.new(); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.custom_minimum_size.y = 49 * scale_factor
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE; column.add_child(image)
	var labels: Array[Label] = []
	for font_size in [12, 12, 11, 10]:
		var label: Label = ui._label("", font_size, M.INK if labels.size() < 3 else M.MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE; column.add_child(label); labels.append(label)
	objects[id] = {"button":button,"image":image,"model":labels[0],"serial":labels[1],"status":labels[2],"owner":labels[3]}

func _lane(unit: Dictionary) -> int:
	var status := str(unit.get("status", ""))
	return 1 if status == "staged" else 2 if status in ["shipping", "delivered"] else 0

func _has_staged() -> bool:
	for raw in view.get("units", []):
		if raw is Dictionary and str(raw.get("status", "")) == "staged": return true
	return false

func _layout() -> void:
	if headings.size() != 3: return
	var counts: Array[int] = [0, 0, 0]
	var lane_width := size.x / 3.0
	var object_height := 148.0 * scale_factor
	for raw in view.get("units", []):
		if not raw is Dictionary: continue
		var unit: Dictionary = raw; var lane := _lane(unit); var id := str(unit.get("id", ""))
		var columns := 2 if lane == 0 else 1
		var index := counts[lane]; counts[lane] += 1
		var card_width := (lane_width - 18 * scale_factor) / columns
		var button: Button = objects[id].button
		button.position = Vector2(lane_width * lane + 7 * scale_factor + (index % columns) * card_width, 34 * scale_factor + floori(float(index) / columns) * (object_height + 6 * scale_factor))
		button.size = Vector2(card_width - 4 * scale_factor, object_height)
	for index in 3:
		headings[index].position = Vector2(lane_width * index + 10 * scale_factor, 3 * scale_factor)
		headings[index].size = Vector2(lane_width - 20 * scale_factor, 28 * scale_factor)
	ghost.position = Vector2(lane_width + 18 * scale_factor, 55 * scale_factor)
	ghost.size = Vector2(lane_width - 36 * scale_factor, 74 * scale_factor)
	var rows := maxi(ceili(float(counts[0]) / 2.0), maxi(counts[1], counts[2]))
	custom_minimum_size.y = maxf(230 * scale_factor, (34 + rows * 154) * scale_factor)
	queue_redraw()

func _draw() -> void:
	var width := size.x / 3.0
	for lane in 3:
		draw_style_box(M.surface(M.CANVAS if lane != 1 else M.PAPER, 0, true), Rect2(width * lane + 2, 0, width - 4, size.y))
	var table_y := 193.0 * scale_factor
	draw_rect(Rect2(width + 14 * scale_factor, table_y, width - 28 * scale_factor, 8 * scale_factor), M.MUTED)
	for x in [width + 24 * scale_factor, 2 * width - 26 * scale_factor]: draw_line(Vector2(x, table_y + 8 * scale_factor), Vector2(x, table_y + 23 * scale_factor), M.MUTED, 3 * scale_factor)
	for start_x in [width - 4, 2 * width - 4]:
		var point := Vector2(start_x, 92 * scale_factor)
		draw_line(point + Vector2(-10, 0), point + Vector2(9, 0), M.MUTED, 2)
		draw_line(point + Vector2(9, 0), point + Vector2(3, -5), M.MUTED, 2)
		draw_line(point + Vector2(9, 0), point + Vector2(3, 5), M.MUTED, 2)
	if _has_staged():
		# The cable means a physical stock unit is on the persisted setup bench.
		# It does not claim SSH, a policy test, or customer acceptance succeeded.
		draw_line(Vector2(width * 1.35, 183 * scale_factor), Vector2(width * 1.35, table_y), M.ACCENT, 3 * scale_factor)
		draw_circle(Vector2(width * 1.35, table_y), 4 * scale_factor, M.ACCENT)
	for raw in view.get("units", []):
		if not raw is Dictionary or str(raw.get("status", "")) not in ["queued", "shipping"]: continue
		var outbound := str(raw.status) == "shipping"
		var lane := 2 if outbound else 0
		var duration := STOCK.SHIPPING_SECONDS if outbound else STOCK.DELIVERY_WAIT_SECONDS
		var progress := clampf(float(raw.get("elapsed_seconds", 0)) / duration, 0, 1)
		var from := Vector2(width * lane + 14 * scale_factor, size.y - 14 * scale_factor)
		var to := Vector2(width * (lane + 1) - 14 * scale_factor, from.y)
		draw_line(from, to, M.MUTED, 2 * scale_factor)
		draw_line(from, from.lerp(to, progress), M.ACCENT, 4 * scale_factor)
		draw_circle(from.lerp(to, progress), 4 * scale_factor, M.ACCENT)
