extends Button
## Select a saved site's evidence; the seal is a delivery-check summary.
const UI = preload("res://scripts/ui_theme.gd")
var passed := 0
var total := 0
var text_factor := 1.0

func _draw() -> void:
	var f := text_factor
	var top := Vector2(14, 10) * f
	var paper := PackedVector2Array([top, top + Vector2(22, 0) * f, top + Vector2(32, 10) * f, top + Vector2(32, 45) * f, top + Vector2(0, 45) * f, top])
	var color := Color("276b57") if total > 0 and passed == total else Color("a64032") if total > 0 else Color("77766d")
	draw_colored_polygon(paper, Color("fffcf2")); draw_polyline(paper, color, 1.5 * f, true)
	draw_polyline(PackedVector2Array([top + Vector2(22, 0) * f, top + Vector2(22, 10) * f, top + Vector2(32, 10) * f]), color, f)
	if total == 0:
		draw_line(top + Vector2(7, 27) * f, top + Vector2(25, 27) * f, color, 2 * f)
	elif passed == total:
		draw_polyline(PackedVector2Array([top + Vector2(7, 27) * f, top + Vector2(13, 33) * f, top + Vector2(26, 19) * f]), color, 2.5 * f, true)
	else:
		for line in [[Vector2(9, 21), Vector2(24, 36)], [Vector2(24, 21), Vector2(9, 36)]]: draw_line(top + line[0] * f, top + line[1] * f, color, 2.5 * f)
