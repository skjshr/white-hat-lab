extends RefCounted
## A read-only projection of the agreed fee and recorded operating costs.
const UI = preload("res://scripts/ui_theme.gd")

class CostBar extends Control:
	var fee := 0
	var base_cost := 0
	var compensation := 0
	var factor := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var width := maxf(0.0, size.x)
		if width <= 0.0: return
		var costs := base_cost + compensation
		var maximum := maxf(1.0, maxf(float(fee), float(costs)))
		var bar := Rect2(0, 3 * factor, width, 10 * factor)
		draw_rect(bar, UI.BORDER)
		var base_end := width * float(base_cost) / maximum
		var cost_end := width * float(costs) / maximum
		var fee_end := width * float(fee) / maximum
		if base_end > 0.0:
			draw_rect(Rect2(bar.position, Vector2(base_end, bar.size.y)), UI.MUTED)
		if cost_end > base_end:
			draw_rect(Rect2(base_end, bar.position.y, cost_end - base_end, bar.size.y), UI.WARNING)
		if fee_end > cost_end:
			draw_rect(Rect2(cost_end, bar.position.y, fee_end - cost_end, bar.size.y), UI.GREEN)
		for boundary in [base_end, cost_end]:
			if boundary > 0.0 and boundary < width:
				draw_line(Vector2(boundary, bar.position.y), Vector2(boundary, bar.end.y), UI.PAPER, maxf(1.0, factor))
		if costs > fee:
			# The fee marker separates covered costs from the real shortfall.
			# Clip each stripe mathematically rather than drawing beyond the bar.
			var step := maxf(4.0, 7 * factor)
			var stripe := fee_end - bar.size.y
			while stripe < cost_end:
				var left := maxf(fee_end, stripe)
				var right := minf(cost_end, stripe + bar.size.y)
				if right > left:
					draw_line(Vector2(left, bar.end.y - (left - stripe)), Vector2(right, bar.end.y - (right - stripe)), UI.PAPER, maxf(1.0, factor))
				stripe += step
			draw_line(Vector2(fee_end, 0), Vector2(fee_end, bar.end.y + 3 * factor), UI.RED, 2 * factor)

static func add_to(parent: Node, factor: float, fee: int, base_cost: int, compensation: int, compact := false) -> Control:
	var scale := maxf(0.5, factor)
	var revenue := maxi(0, fee)
	var operating := maxi(0, base_cost)
	var impact := maxi(0, compensation)
	var profit := revenue - operating - impact
	var root := VBoxContainer.new()
	root.name = "EndpointBusinessStrip"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", roundi(5 * scale))
	parent.add_child(root)
	var heading := _flow(root, scale)
	_label(heading, "BusinessStripFee", "報酬 ¥%d" % revenue, 13, scale, UI.INK)
	var profit_text := "補償後の見込利益 " + ("−¥%d（赤字）" % absi(profit) if profit < 0 else "¥%d" % profit)
	var margin := _label(heading, "BusinessStripProfit", profit_text, 13, scale, UI.RED if profit < 0 else UI.INK, 600)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar := CostBar.new()
	bar.name = "BusinessStripBar"
	bar.fee = revenue; bar.base_cost = operating; bar.compensation = impact; bar.factor = scale
	bar.custom_minimum_size.y = 16 * scale
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(bar)
	if compact:
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.tooltip_text = "基本・作業経費 ¥%d\n補償 ¥%d\n%s" % [operating, impact, profit_text]
		_fit_labels.call_deferred(heading)
		return root
	var legend := _flow(root, scale)
	_label(legend, "BusinessStripBaseCost", "基本・作業経費 ¥%d" % operating, 11, scale, UI.MUTED)
	_label(legend, "BusinessStripCompensation", "補償 ¥%d" % impact, 11, scale, UI.WARNING)
	_label(legend, "BusinessStripBalance", "斜線: 赤字 ¥%d" % absi(profit) if profit < 0 else "残利益 ¥%d" % profit, 11, scale, UI.RED if profit < 0 else UI.GREEN)
	_fit_labels.call_deferred(heading)
	_fit_labels.call_deferred(legend)
	return root

static func _flow(parent: Node, factor: float) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", roundi(16 * factor))
	flow.add_theme_constant_override("v_separation", roundi(3 * factor))
	parent.add_child(flow)
	flow.resized.connect(func(): _fit_labels(flow))
	return flow

static func _label(parent: Node, id: String, value: String, points: int, factor: float, color: Color, weight: int = 400) -> Label:
	var label := Label.new()
	label.name = id; label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UI.font(weight))
	label.add_theme_font_size_override("font_size", roundi(points * factor))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

static func _fit_labels(flow: HFlowContainer) -> void:
	if not is_instance_valid(flow): return
	var available := maxf(1.0, flow.size.x)
	for child in flow.get_children():
		if not child is Label: continue
		var label: Label = child
		var natural := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		label.custom_minimum_size.x = minf(available, ceilf(natural))
