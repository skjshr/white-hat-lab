class_name SalesChart
extends Control

var values: Array[float] = []
var colors: Array[Color] = []
var chart_kind := "donut"

func configure(kind: String, next_values: Array, next_colors: Array) -> void:
	chart_kind = kind
	values.clear()
	colors.clear()
	for value in next_values:
		values.append(maxf(0.0, float(value)))
	for color in next_colors:
		colors.append(color as Color)
	queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if chart_kind == "stacked":
		_draw_stacked()
	else:
		_draw_donut()

func _draw_donut() -> void:
	var total := 0.0
	for value in values:
		total += value
	var center := size * 0.5
	var radius := maxf(8.0, minf(size.x, size.y) * 0.5 - 9.0)
	draw_arc(center, radius, 0.0, TAU, 72, Color("214f6d"), 11.0, true)
	if total <= 0.0:
		return
	var angle := -PI * 0.5
	for index in values.size():
		if values[index] <= 0.0:
			continue
		var next_angle := angle + TAU * values[index] / total
		draw_arc(center, radius, angle, next_angle, 32, colors[index % colors.size()], 11.0, true)
		angle = next_angle

func _draw_stacked() -> void:
	var total := 0.0
	for value in values:
		total += value
	var background := Rect2(Vector2(0.0, size.y * 0.34), Vector2(size.x, maxf(8.0, size.y * 0.32)))
	draw_rect(background, Color("214f6d"), true)
	if total <= 0.0:
		return
	var cursor := 0.0
	for index in values.size():
		var width := size.x * values[index] / total
		draw_rect(Rect2(Vector2(cursor, background.position.y), Vector2(width, background.size.y)), colors[index % colors.size()], true)
		cursor += width
