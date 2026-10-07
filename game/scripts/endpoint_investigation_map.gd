extends RefCounted
## A read-only view of saved endpoint records. Dotted links never imply live traffic.
const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const Workstation = preload("res://assets/ui/endpoint/workstation-v1.png")
const INK := Color("323130")
const MUTED := Color("605e5c")
const BLUE := Color("0078d4")
const MIN_COMPARE_WIDTH := 580.0

class RecordLinks extends Control:
	var edges: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func connect_objects(source: Control, destination: Control, source_area: Control, destination_area: Control) -> void:
		edges.append([source, destination, source_area, destination_area])
		for node in [source, destination, source_area, destination_area]:
			if not node.item_rect_changed.is_connected(queue_redraw):
				node.item_rect_changed.connect(queue_redraw)
		queue_redraw.call_deferred()

	func _draw() -> void:
		var local := get_global_transform().affine_inverse()
		for pair in edges:
			var source: Control = pair[0]
			var destination: Control = pair[1]
			var source_area: Control = pair[2]
			var destination_area: Control = pair[3]
			if not is_instance_valid(source) or not is_instance_valid(destination) or not is_instance_valid(source_area) or not is_instance_valid(destination_area): continue
			var a := source.get_global_rect()
			var b := destination.get_global_rect()
			var start := local * Vector2(a.end.x, a.get_center().y)
			var finish := local * Vector2(b.position.x, b.get_center().y)
			# End at the actual pictures; keep the vertical branch in the column
			# gutter so it cannot cross the labels below a process symbol.
			var source_bounds := source_area.get_global_rect()
			var destination_bounds := destination_area.get_global_rect()
			var gutter := local * Vector2((source_bounds.end.x + destination_bounds.position.x) * 0.5, a.get_center().y)
			var middle_x := gutter.x
			var elbow_a := Vector2(middle_x, start.y)
			var elbow_b := Vector2(middle_x, finish.y)
			for segment in [[start, elbow_a], [elbow_a, elbow_b], [elbow_b, finish]]:
				if segment[0].distance_to(segment[1]) > 0.5:
					draw_dashed_line(segment[0], segment[1], Color("a19f9d"), 1.5, 4, true)
			draw_circle(finish, 2.0, Color("8a8886"))

class BusinessLink extends Control:
	var isolated := false
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var center:=size*0.5
		var ink:=Color("8a8886") if isolated else Color("0078d4")
		if isolated:
			draw_line(Vector2(center.x,0),Vector2(center.x,center.y-6),ink,2,true)
			draw_line(Vector2(center.x,center.y+6),Vector2(center.x,size.y),ink,2,true)
			for sign in [-1,1]:draw_line(center+Vector2(-4,-4*sign),center+Vector2(4,4*sign),ink,2,true)
		else:draw_line(Vector2(center.x,0),Vector2(center.x,size.y),ink,2,true)

static func render(d, parent: VBoxContainer, snap: Dictionary, on_device: Callable, on_record: Callable, query: String = "", business: Dictionary = {}) -> void:
	var factor := float(d.game.settings.get("text_scale", 1.0))
	var root := VBoxContainer.new()
	root.name = "EdrInvestigationMap"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", roundi(12 * factor))
	var map_theme: Theme = d.get_theme().duplicate() as Theme
	map_theme.set_color("font_color", "TooltipLabel", INK)
	map_theme.set_stylebox("panel", "TooltipPanel", UI.style(Color("fffdf5"), Color("8a999b"), 7, 5, 4))
	root.theme = map_theme
	parent.add_child(root)
	var lanes := BoxContainer.new()
	lanes.name = "EdrInvestigationLanes"
	lanes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lanes.add_theme_constant_override("separation", roundi(20 * factor))
	root.add_child(lanes)
	var devices: Array = snap.get("devices", []) if snap.get("devices", []) is Array else []
	for raw in devices:
		if not raw is Dictionary: continue
		var device: Dictionary = raw
		_lane(lanes, device, query, factor, on_device, on_record, business)
	if lanes.get_child_count() == 0:
		_text(root, "一致する記録はありません", factor, 13, MUTED)
	_text(root, str(business.get("legend", "点線: 過去の記録   実線 / ×: 現在の接続設定   業務の図を押して実測")) if not business.is_empty() else "点線: 過去の記録の関係   ○ 接続許可 / × 隔離: 現在の端末設定", factor, 11, MUTED)
	var resize_lanes := func():
		# Keep two endpoints comparable at 960x600; stack only when each lane
		# would otherwise lose its business-to-event layout.
		lanes.vertical = root.size.x < MIN_COMPARE_WIDTH * factor
	lanes.resized.connect(resize_lanes)
	root.resized.connect(resize_lanes)
	resize_lanes.call()

static func _visible_events(device: Dictionary, query: String) -> Array:
	var result: Array = []
	var needle := query.strip_edges().to_lower()
	var id := str(device.get("id", ""))
	var device_match := needle.is_empty() or id.to_lower().contains(needle) or id.replace("_", "-").to_lower().contains(needle)
	var events: Array = device.get("events", []) if device.get("events", []) is Array else []
	for index in events.size():
		if not events[index] is Dictionary: continue
		var event: Dictionary = events[index]
		if not device_match and not JSON.stringify(event).to_lower().contains(needle): continue
		result.append({"index":index, "record":event})
	return result

static func _lane(parent: Control, device: Dictionary, query: String, factor: float, on_device: Callable, on_record: Callable, business: Dictionary) -> void:
	var id := str(device.get("id", ""))
	var lane := HBoxContainer.new()
	lane.name = "EdrInvestigationLane_" + id
	lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lane.size_flags_stretch_ratio = 1.0
	lane.add_theme_constant_override("separation", roundi(10 * factor))
	parent.add_child(lane)
	var links := RecordLinks.new()
	lane.add_child(links)
	var endpoint_column := VBoxContainer.new()
	endpoint_column.name = "EdrMapEndpointColumn_" + id
	endpoint_column.custom_minimum_size.x = 105 * factor
	endpoint_column.size_flags_horizontal = Control.SIZE_FILL
	endpoint_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	endpoint_column.add_theme_constant_override("separation", 0)
	lane.add_child(endpoint_column)
	if business.get("names",{}).has(id):
		var observation:Dictionary=business.get("observations",{}).get(id,{})
		var job := _object(endpoint_column, ("EdrBusinessOpen_" if bool(observation.get("opens_app", false)) else "EdrBusinessProbe_") + id, 52 * factor, func(): business.on_probe.call(id))
		var job_box:=_contents(job,factor)
		var job_name:=str(business.names[id])
		var glyph:=Glyph.add_to(job_box,"receipt" if job_name.contains("精算") or job_name.contains("請求") else "ledger",32*factor,MUTED)
		glyph.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		_text(job_box,job_name,factor,12,INK,600).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var result:=str(observation.get("label","? 未測定"))
		_text(job_box,result,factor,12,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		job.tooltip_text=str(observation.get("tooltip",job_name+"の接続を実測\n"+str(observation.get("response",""))))
		_ignore_children(job_box)
		var stem := BusinessLink.new()
		stem.name = "EdrBusinessConnection_" + id
		stem.isolated = bool(device.get("isolated", false))
		stem.custom_minimum_size.y = 18 * factor
		endpoint_column.add_child(stem)
	var endpoint := _object(endpoint_column, "EdrDevice_" + id, 112 * factor, func(): on_device.call(id))
	endpoint.custom_minimum_size.x = 112 * factor
	endpoint.size_flags_horizontal = Control.SIZE_FILL
	endpoint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	endpoint.tooltip_text = id.to_upper().replace("_", "-") + " を調査"
	var endpoint_body := _contents(endpoint, factor)
	var image := TextureRect.new()
	image.texture = Workstation
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size.y = 62 * factor
	endpoint_body.add_child(image)
	_text(endpoint_body, id.to_upper().replace("_", "-"), factor, 13, INK, 600).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text(endpoint_body, "× 隔離" if bool(device.get("isolated", false)) else "○ 接続許可", factor, 12, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ignore_children(endpoint_body)
	var records := VBoxContainer.new()
	records.name = "EdrMapEvents_" + id
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	records.add_theme_constant_override("separation", roundi(3 * factor))
	lane.add_child(records)
	var visible := _visible_events(device, query)
	if visible.is_empty():
		_text(records, "一致する記録はありません" if not query.strip_edges().is_empty() else "保存されたイベントはありません", factor, 13, MUTED)
	for item in visible:
		var index := int(item.index)
		var event: Dictionary = item.record
		var record := _record(records, id, index, event, factor, on_record)
		var record_glyph := record.find_child("EdrMapRecordGlyph", true, false) as Control
		links.connect_objects(image, record_glyph, endpoint, record)

static func _record(parent: VBoxContainer, device_id: String, index: int, event: Dictionary, factor: float, on_record: Callable) -> Button:
	var node := _object(parent, "EdrMapEvent_" + device_id + "_" + str(index), 61 * factor, func(): on_record.call(device_id, index))
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind := str(event.get("type", ""))
	var type_name := str({"outbound":"送信", "dns":"DNS", "file_read":"ファイル参照"}.get(kind, kind if not kind.is_empty() else "イベント"))
	var symbol := str({"outbound":"arrow", "dns":"network", "file_read":"file"}.get(kind, "file"))
	var body := _contents(node, factor)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", roundi(5 * factor))
	body.add_child(heading)
	var record_glyph := Glyph.add_to(heading, symbol, 18 * factor, BLUE if kind == "outbound" else MUTED)
	record_glyph.name = "EdrMapRecordGlyph"
	_text(heading, str(event.get("time", "—")) + "  " + type_name, factor, 12, INK, 600)
	var process := str(event.get("process", ""))
	var publisher := str(event.get("publisher", ""))
	_text(body, (process if not process.is_empty() else "名称の記録なし") + " · " + (publisher if not publisher.is_empty() else "発行元の記録なし"), factor, 12, INK)
	var address := str(event.get("remote_address", ""))
	var relation_label := "関連先 " if kind == "file_read" else "宛先 "
	_text(body, relation_label + (address if not address.is_empty() else "記録なし"), factor, 12, MUTED)
	var reference := str(event.get("change_ref", ""))
	_text(body, "変更 " + (reference if not reference.is_empty() else "参照なし"), factor, 11, MUTED)
	var time := str(event.get("time", "")).strip_edges()
	if time.is_empty(): time = "時刻未記録"
	node.tooltip_text = device_id.to_upper().replace("_", "-") + " / " + time + " の記録を開く"
	_ignore_children(body)
	return node

static func _object(parent: Node, name: String, height: float, callback: Callable) -> Button:
	var node := Button.new()
	node.name = name
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.custom_minimum_size.y = height
	node.pressed.connect(callback)
	for pair in [["normal", Color.TRANSPARENT], ["hover", Color(Color("f0f6fc"), 0.35)], ["pressed", Color(Color("deecf9"), 0.45)]]:
		var style := UI.style(pair[1], Color.TRANSPARENT, 4, 4, 3)
		style.set_border_width_all(0)
		node.add_theme_stylebox_override(pair[0], style)
	var focus := UI.style(Color.TRANSPARENT, BLUE, 4, 4, 3)
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus", focus)
	parent.add_child(node)
	return node

static func _contents(parent: Button, factor: float) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, roundi(5 * factor))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	var base_height := parent.custom_minimum_size.y
	margin.minimum_size_changed.connect(func():
		parent.custom_minimum_size.y = maxf(base_height, margin.get_combined_minimum_size().y))
	return box

static func _text(parent: Node, value: String, factor: float, size: int, tint: Color, weight: int = 400) -> Label:
	var node := Label.new()
	node.text = value
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_override("font", UI.font(weight))
	node.add_theme_font_size_override("font_size", roundi(size * factor))
	node.add_theme_color_override("font_color", tint)
	parent.add_child(node)
	return node

static func _ignore_children(parent: Control) -> void:
	parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in parent.get_children():
		if child is Control: _ignore_children(child)
