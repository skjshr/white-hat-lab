extends Control
## Objects describe a saved fetch response, never the live server or a new probe.
const UI = preload("res://scripts/ui_theme.gd")
const PURPLE := Color("714b67")
const MUTED := Color("8c8990")
const GREEN := Color("2f7d4a")
const RED := Color("b42318")
var text_factor := 1.0
var projection: Dictionary = {}
var objects: Array = []

func _ready() -> void:
	resized.connect(layout)
	layout()

func layout() -> void:
	if size.x <= 1: return
	for i in objects.size():
		var item: Dictionary = objects[i]
		var section: Control = item.section
		section.position = Vector2(size.x * [0.015, 0.36, 0.705][i], 0)
		section.size = Vector2(size.x * 0.28, size.y)
		item.button.position = Vector2(0, 26 * text_factor)
		item.button.size = Vector2(section.size.x, 76 * text_factor)
		for pair in [["title", 0], ["detail", 103], ["status", 129]]:
			var label: Label = item[pair[0]]
			label.position = Vector2(0, int(pair[1]) * text_factor)
			label.size = Vector2(section.size.x, 24 * text_factor)
	queue_redraw()

func _color(stage: Dictionary) -> Color:
	return GREEN if str(stage.get("status", "")) == "ok" else RED if str(stage.get("status", "")) == "error" else MUTED

func _draw() -> void:
	if objects.size() != 3: return
	var centers := [Vector2(size.x * 0.155, 64 * text_factor), Vector2(size.x * 0.5, 64 * text_factor), Vector2(size.x * 0.845, 64 * text_factor)]
	var server: Dictionary = projection.server
	var file: Dictionary = projection.file
	var business: Dictionary = projection.business
	var first := "error" if server.status == "error" or file.status == "error" else "ok" if server.status == "ok" and file.status == "ok" else "unknown"
	var second := str(business.status) if file.status == "ok" else "unknown"
	_edge(centers[0] + Vector2(49, 0) * text_factor, centers[1] - Vector2(39, 0) * text_factor, first)
	_edge(centers[1] + Vector2(39, 0) * text_factor, centers[2] - Vector2(52, 0) * text_factor, second)
	_server(centers[0], server)
	_file(centers[1], file)
	_business(centers[2], business)

func _edge(start: Vector2, end: Vector2, status: String) -> void:
	var color := GREEN if status == "ok" else RED if status == "error" else MUTED
	var length := start.distance_to(end)
	if length < 12 * text_factor: return
	if status == "unknown":
		for x in range(0, ceili(length), maxi(1, int(12 * text_factor))):
			draw_line(start + Vector2(x, 0), start + Vector2(minf(x + 5 * text_factor, length), 0), color, 2 * text_factor, true)
	elif status == "error":
		var center := (start + end) * 0.5
		draw_line(start, center - Vector2(11, 0) * text_factor, color, 2 * text_factor, true)
		draw_line(center + Vector2(11, 0) * text_factor, end, MUTED, 1.5 * text_factor, true)
		draw_circle(center, 10 * text_factor, Color("fff1ed"))
		draw_line(center - Vector2(4, 4) * text_factor, center + Vector2(4, 4) * text_factor, color, 2 * text_factor, true)
		draw_line(center + Vector2(-4, 4) * text_factor, center + Vector2(4, -4) * text_factor, color, 2 * text_factor, true)
	else:
		draw_line(start, end, color, 2.5 * text_factor, true)
		draw_colored_polygon(PackedVector2Array([end, end + Vector2(-7, -4) * text_factor, end + Vector2(-7, 4) * text_factor]), color)

func _server(center: Vector2, stage: Dictionary) -> void:
	var edge := _color(stage)
	var box := Rect2(center - Vector2(43, 32) * text_factor, Vector2(86, 64) * text_factor)
	draw_style_box(UI.style(Color("ece7ed"), PURPLE, 0, 0, 3), box)
	for i in 3:
		var slot := Rect2(box.position + Vector2(6, 5 + i * 18) * text_factor, Vector2(74, 14) * text_factor)
		draw_style_box(UI.style(Color("faf8fb"), Color("b9a8b6"), 0, 0, 1), slot)
		draw_circle(slot.position + Vector2(8, 7) * text_factor, 2.5 * text_factor, edge)
		for line in 4:
			var x := slot.position.x + (45 + line * 5) * text_factor
			draw_line(Vector2(x, slot.position.y + 4 * text_factor), Vector2(x, slot.position.y + 10 * text_factor), MUTED, text_factor)

func _file(center: Vector2, stage: Dictionary) -> void:
	var edge := _color(stage)
	var top := center - Vector2(29, 36) * text_factor
	var outline := PackedVector2Array([top, top + Vector2(43, 0) * text_factor, top + Vector2(58, 15) * text_factor, top + Vector2(58, 72) * text_factor, top + Vector2(0, 72) * text_factor])
	if stage.status == "ok": draw_colored_polygon(outline, Color.WHITE)
	draw_polyline(outline + PackedVector2Array([top]), edge, 2 * text_factor, true)
	draw_polyline(PackedVector2Array([top + Vector2(43, 0) * text_factor, top + Vector2(43, 15) * text_factor, top + Vector2(58, 15) * text_factor]), edge, text_factor, true)
	if stage.status == "ok":
		for row in 4:
			draw_line(top + Vector2(8, 29 + row * 8) * text_factor, top + Vector2(50, 29 + row * 8) * text_factor, Color("c1b4c0"), text_factor)
		for column in [22, 37]:
			draw_line(top + Vector2(column, 25) * text_factor, top + Vector2(column, 58) * text_factor, Color("c1b4c0"), text_factor)

func _business(center: Vector2, stage: Dictionary) -> void:
	var edge := _color(stage)
	var known: bool = stage.status == "ok"
	var count := int(projection.get("count", 0)) if known else 0
	var view := str(projection.get("view", "sales"))
	if view == "accounting":
		var box := Rect2(center - Vector2(47, 30) * text_factor, Vector2(94, 60) * text_factor)
		draw_style_box(UI.style(Color("fffdf6") if known else Color("efedf0"), edge, 0, 0, 2), box)
		draw_line(center - Vector2(0, 30) * text_factor, center + Vector2(0, 30) * text_factor, edge, 2 * text_factor)
		if known:
			for row in mini(4, count):
				draw_line(center + Vector2(-39, -18 + row * 12) * text_factor, center + Vector2(-8, -18 + row * 12) * text_factor, PURPLE, text_factor)
				draw_line(center + Vector2(8, -18 + row * 12) * text_factor, center + Vector2(39, -18 + row * 12) * text_factor, PURPLE, text_factor)
	elif view == "customers":
		var box := Rect2(center - Vector2(47, 30) * text_factor, Vector2(94, 60) * text_factor)
		draw_style_box(UI.style(Color.WHITE if known else Color("efedf0"), edge, 0, 0, 4), box)
		if known and count > 0:
			draw_circle(center + Vector2(-23, -8) * text_factor, 8 * text_factor, Color("c8b2c3"))
			draw_arc(center + Vector2(-23, 16) * text_factor, 13 * text_factor, PI, TAU, 16, PURPLE, 3 * text_factor, true)
			for row in mini(3, count): draw_line(center + Vector2(0, -14 + row * 13) * text_factor, center + Vector2(37, -14 + row * 13) * text_factor, PURPLE, 2 * text_factor)
	else:
		var box := Rect2(center - Vector2(30, 35) * text_factor, Vector2(60, 70) * text_factor)
		draw_style_box(UI.style(Color("fffdf6") if known else Color("efedf0"), edge, 0, 0, 1), box)
		for x in range(-24, 30, 12): draw_circle(center + Vector2(x, -35) * text_factor, 2 * text_factor, Color("faf8fa"))
		if known:
			for row in mini(4, count): draw_line(center + Vector2(-21, -16 + row * 10) * text_factor, center + Vector2(21, -16 + row * 10) * text_factor, PURPLE, 2 * text_factor)
			draw_line(center + Vector2(-21, 24) * text_factor, center + Vector2(21, 24) * text_factor, edge, 2 * text_factor)
