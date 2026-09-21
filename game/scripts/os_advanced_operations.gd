class_name AdvancedOperationsWorkspace
extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")

class NetworkMap extends Control:
	var nodes: Array = []
	var edges: Array = []
	var positions: Dictionary = {}
	func configure(data: Dictionary, selected: String, callback: Callable) -> void:
		nodes = data.get("nodes", []); edges = data.get("edges", [])
		for item in nodes:
			var button := Button.new()
			button.name = "AdvancedNode_" + str(item.id).validate_node_name()
			button.text = AdvancedOperationsWorkspace._text(str(item.get("label", item.id)))
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.tooltip_text = button.text + "\n" + str(item.get("detail", ""))
			button.custom_minimum_size = Vector2(126, 42)
			button.size = Vector2(150, 42)
			button.clip_text = true
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_stylebox_override("normal", UI.style(Color("e5f1ff") if str(item.id) == selected else Color.WHITE, UI.PRIMARY if str(item.id) == selected else UI.BORDER, 8, 7, 3))
			button.pressed.connect(callback.bind(str(item.id)))
			add_child(button)
			positions[str(item.id)] = button
		resized.connect(_arrange)
		_arrange.call_deferred()
	func _arrange() -> void:
		var min_x := 1.0; var max_x := 0.0; var min_y := 1.0; var max_y := 0.0
		for item in nodes:
			min_x = minf(min_x, float(item.x)); max_x = maxf(max_x, float(item.x))
			min_y = minf(min_y, float(item.y)); max_y = maxf(max_y, float(item.y))
		for item in nodes:
			var button: Button = positions[str(item.id)]
			button.custom_minimum_size.x = minf(150, maxf(105, (size.x - 48) / 4))
			button.size.x = button.custom_minimum_size.x
			var nx: float = (float(item.x) - min_x) / maxf(0.01, max_x - min_x)
			var ny: float = 0.5 if max_y == min_y else 0.18 + 0.64 * (float(item.y) - min_y) / (max_y - min_y)
			button.position = Vector2(8 + nx * maxf(0, size.x - button.size.x - 16), ny * maxf(0, size.y - button.size.y))
		queue_redraw()
	func _draw() -> void:
		for edge in edges:
			if not positions.has(str(edge.get("from", ""))) or not positions.has(str(edge.get("to", ""))): continue
			var a: Button = positions[str(edge.from)]; var b: Button = positions[str(edge.to)]
			var start := a.position + a.size / 2; var end := b.position + b.size / 2
			draw_line(start, end, Color("8dabc3"), 2, true)
			var middle := start.lerp(end, 0.58); var direction := (end - start).normalized()
			draw_colored_polygon(PackedVector2Array([middle + direction * 7, middle - direction.rotated(0.55) * 7, middle - direction.rotated(-0.55) * 7]), UI.PRIMARY)

static func _text(value: String) -> String:
	return UI.copy(value, value) if value.begins_with("adv_") else value

static func build(d, parent: VBoxContainer) -> void:
	parent.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new(); parent.add_child(header)
	var title: Label = d._label(UI.copy("adv_app"), 18, UI.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size.y = 32
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var verify: Button = d._button(UI.copy("adv_verify"), func(): d.game.verify(); refresh(d))
	verify.name = "AdvancedVerify"; header.add_child(verify)
	var delivery: Button = d._button(UI.copy("adv_delivery"), d._show_app.bind("receipt"))
	delivery.name = "AdvancedDelivery"; header.add_child(delivery)
	var nav := HBoxContainer.new(); nav.add_theme_constant_override("separation", 4); parent.add_child(nav)
	var tabs: Dictionary = {}
	for spec in [["network", "adv_nav_network"], ["events", "adv_nav_events"], ["records", "adv_nav_records"], ["evidence", "adv_nav_evidence"], ["results", "adv_results"]]:
		var button: Button = d._button(UI.copy(spec[1]), func(): d.advanced_ui.view = spec[0]; refresh(d))
		button.name = "AdvancedTab_" + spec[0]; button.toggle_mode = true; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE; nav.add_child(button); tabs[spec[0]] = button
	var filters := HBoxContainer.new(); parent.add_child(filters)
	var search := LineEdit.new(); search.name = "AdvancedSearch"; search.placeholder_text = UI.copy("adv_search")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text = str(d.advanced_ui.get("filter", "")); filters.add_child(search)
	search.text_changed.connect(func(value: String): d.advanced_ui.filter = value; refresh(d))
	var source := OptionButton.new(); source.name = "AdvancedSource"; source.custom_minimum_size.x = 170; filters.add_child(source)
	source.item_selected.connect(func(index: int): d.advanced_ui.source = str(source.get_item_metadata(index)); refresh(d))
	var body := HBoxContainer.new(); body.name = "AdvancedWorkbench"; body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12); parent.add_child(body)
	var status: Label = d._label("", 12, UI.MUTED); status.name = "AdvancedStatus"; status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(status)
	d.widgets.advanced = {"body":body,"search":search,"source":source,"tabs":tabs,"status":status,"title":title,"verify":verify,"delivery":delivery,"signature":""}
	refresh(d)

static func refresh(d) -> void:
	if not d.widgets.has("advanced"): return
	var w: Dictionary = d.widgets.advanced
	if not is_instance_valid(w.body): return
	var state: Dictionary = d.advanced_ui
	var data: Dictionary = d.game.advanced_view(str(state.get("selected", "")))
	var mode := str(state.get("view", "network"))
	var signature := JSON.stringify([data, state, d.game.can_deliver()])
	if signature == str(w.signature): return
	w.signature = signature
	for key in w.tabs: w.tabs[key].set_pressed_no_signal(key == mode)
	w.delivery.disabled = not d.game.can_deliver(); w.verify.disabled = data.is_empty()
	w.title.text = str(d.game.mission().get("title", UI.copy("adv_app")))
	w.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	w.title.clip_text = true
	var source: OptionButton = w.source
	var selected_source := str(state.get("source", ""))
	source.clear(); source.add_item(UI.copy("adv_all_sources")); source.set_item_metadata(0, "")
	var sources: Array[String] = []
	for event in data.get("events", []):
		var value := str(event.get("source", ""))
		if not value.is_empty() and not value in sources: sources.append(value)
	for value in sources:
		source.add_item(value); source.set_item_metadata(source.item_count - 1, value)
		if value == selected_source: source.select(source.item_count - 1)
	source.visible = mode in ["events", "evidence"]
	w.search.get_parent().visible = mode in ["events", "evidence", "records"]
	for child in w.body.get_children(): w.body.remove_child(child); child.queue_free()
	var primary := VBoxContainer.new(); primary.name = "AdvancedPrimary"; primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.body.add_child(primary)
	if data.is_empty(): primary.add_child(d._label(UI.copy("adv_no_case"), 14, UI.MUTED)); return
	if mode == "results":
		var results := _scroll(primary)
		for row in data.get("checks", []):
			var label: Label = d._label(("✓  " if row.get("passed", false) else "○  ") + UI.copy(str(row.get("label_key", ""))), 15, UI.GREEN if row.get("passed", false) else UI.INK)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; results.add_child(label)
	elif mode == "network":
		var graph := NetworkMap.new(); graph.name = "AdvancedNetworkMap"; graph.custom_minimum_size.y = 200; graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		primary.add_child(graph); graph.configure(data, str(state.get("selected", "")), func(id: String): state.selected = id; state.record = ""; refresh(d))
	else: _records(d, primary, data, mode)
	if mode != "results":
		var divider := VSeparator.new(); w.body.add_child(divider)
		var side := VBoxContainer.new(); side.name = "AdvancedDetails"; side.custom_minimum_size.x = 290; w.body.add_child(side)
		_details(d, _scroll(side), data)
	var result: Dictionary = data.get("last_result", {})
	var message := str(state.get("message", ""))
	if message.is_empty() and result.has("result_key"):
		message = UI.copy(str(result.result_key))
		if not result.get("result_args", []).is_empty(): message = message % result.result_args
	w.status.text = message

static func _scroll(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var contents := VBoxContainer.new(); contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL; contents.add_theme_constant_override("separation", 9); scroll.add_child(contents)
	return contents

static func _records(d, parent: Control, data: Dictionary, mode: String) -> void:
	var state: Dictionary = d.advanced_ui
	var events := mode in ["events", "evidence"]
	var tree := Tree.new(); tree.name = "AdvancedEvents" if events else "AdvancedRecords"; tree.columns = 4 if events else 2
	tree.hide_root = true; tree.column_titles_visible = true; tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.select_mode = Tree.SELECT_ROW; tree.allow_reselect = true; parent.add_child(tree)
	var titles: Array = ["adv_time", "adv_source", "adv_asset", "adv_event"] if events else ["adv_record", "adv_detail"]
	for index in range(titles.size()):
		tree.set_column_title(index, UI.copy(titles[index])); tree.set_column_clip_content(index, true)
		tree.set_column_custom_minimum_width(index, 68 if index == 0 else 85)
		tree.set_column_expand(index, index == titles.size() - 1)
	var root := tree.create_item()
	for record in data.get("events" if events else "records", []):
		if mode == "evidence" and not bool(record.get("pinned", false)): continue
		if events and not str(state.get("source", "")).is_empty() and str(record.get("source", "")) != str(state.source): continue
		if not _matches(JSON.stringify(record), str(state.get("filter", ""))): continue
		var row := tree.create_item(root)
		var values: Array = [record.get("time", ""), record.get("source", ""), record.get("asset", ""), record.get("detail", "")] if events else [record.get("label", record.get("id", "")), record.get("detail", "")]
		for index in range(values.size()): row.set_text(index, _text(str(values[index]))); row.set_tooltip_text(index, _text(str(values[index])))
		row.set_metadata(0, record.duplicate(true))
		if str(record.get("id", "")) == str(state.get("record", "")): row.select(0)
	tree.item_selected.connect(func():
		var item := tree.get_selected()
		if item == null: return
		state.record = str(item.get_metadata(0).get("id", "")); refresh(d)
	)

static func _details(d, parent: VBoxContainer, data: Dictionary) -> void:
	var state: Dictionary = d.advanced_ui
	var selected := str(state.get("selected", ""))
	var record_id := str(state.get("record", ""))
	var record: Dictionary = {}; var event_selected := false
	for event in data.get("events", []):
		if str(event.get("id", "")) == record_id and not record_id.is_empty(): record = event; event_selected = true; break
	if record.is_empty():
		for row in data.get("records", []):
			if str(row.get("id", "")) == record_id and not record_id.is_empty(): record = row; break
	if not record.is_empty():
		var detail: Label = d._label(_text(str(record.get("label", record_id))), 16, UI.INK); detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(detail)
		var raw := TextEdit.new(); raw.name = "AdvancedRawRecord"; raw.editable = false; raw.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; raw.custom_minimum_size.y = 160
		raw.text = str(record.get("detail", JSON.stringify(record, "  "))); parent.add_child(raw)
		if (event_selected and bool(record.get("pinnable", true))) or bool(record.get("pinnable", false)):
			var pin: Button = d._button(UI.copy("adv_pin"), func(): _act(d, "pin", record_id, "")); pin.name = "AdvancedPin"; parent.add_child(pin)
	var node: Dictionary = {}
	for item in data.get("nodes", []):
		if str(item.id) == selected: node = item; break
	var title: Label = d._label(_text(str(node.get("label", "adv_select_asset"))), 16, UI.INK)
	title.name = "AdvancedSelectedAsset"; title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(title)
	if not node.is_empty() and str(node.get("detail", "")) != str(node.get("label", "")):
		var info: Label = d._label(_text(str(node.get("detail", ""))), 12, UI.MUTED); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(info)
	if not state.has("options"): state.options = {}
	for action in data.get("actions", []):
		if str(action.id) in ["pin", "pin_event"]: continue
		var target := str(action.get("target", ""))
		# Fixed node actions belong to the selected node; global and non-node actions remain available.
		var node_target := false
		for item in data.get("nodes", []):
			if str(item.id) == target: node_target = true; break
		if node_target and target != selected: continue
		var action_key := str(action.id) + "_" + target
		var choices: Array = action.get("options", [])
		var caption := UI.copy(str(action.get("label_key", "")))
		if not choices.is_empty():
			parent.add_child(d._label(caption, 12, UI.MUTED))
			var option := OptionButton.new(); option.name = "AdvancedOption_" + action_key.validate_node_name()
			option.clip_text = true; option.custom_minimum_size.x = 0; option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var selected_option := str(state.options.get(action_key, choices[0].id))
			for choice in choices:
				option.add_item(_text(str(choice.get("label", choice.id)))); option.set_item_metadata(option.item_count - 1, str(choice.id))
				if str(choice.id) == selected_option: option.select(option.item_count - 1)
			state.options[action_key] = str(option.get_item_metadata(option.selected))
			option.item_selected.connect(func(index: int): state.options[action_key] = str(option.get_item_metadata(index)))
			parent.add_child(option)
		var button: Button = d._button(caption if choices.is_empty() else UI.copy("adv_apply"), func(): _act(d, str(action.id), target, str(state.options.get(action_key, ""))))
		button.name = "AdvancedAction_" + action_key.validate_node_name(); button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(button)

static func _act(d, action: String, target: String, option: String) -> void:
	var args: Dictionary = {"target":target}
	if not option.is_empty() or action in ["set_exclusion", "set_rule_exclusion"]: args.option = option
	var result: Dictionary = d.game.advanced_action(action, args)
	d.advanced_ui.message = str(result.get("message", ""))
	refresh(d)

static func _matches(value: String, query: String) -> bool:
	return query.strip_edges().is_empty() or value.to_lower().contains(query.strip_edges().to_lower())
