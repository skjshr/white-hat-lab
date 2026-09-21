extends Control
## Small native vector symbols, also used by entity and file previews.
var kind := "device"
var tint := Color("347ac4")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var side := minf(size.x, size.y)
	var offset := (size - Vector2.ONE * side) / 2.0
	draw_set_transform(offset, 0, Vector2.ONE * side / 48.0)
	match kind:
		"device":
			draw_style_box(_box(), Rect2(5, 7, 38, 27))
			draw_line(Vector2(24, 34), Vector2(24, 41), tint, 2, true)
			draw_line(Vector2(15, 42), Vector2(33, 42), tint, 2, true)
		"process":
			draw_style_box(_box(), Rect2(8, 8, 32, 32))
			for i in [15, 24, 33]:
				draw_line(Vector2(i, 3), Vector2(i, 8), tint, 2, true)
				draw_line(Vector2(i, 40), Vector2(i, 45), tint, 2, true)
				draw_line(Vector2(3, i), Vector2(8, i), tint, 2, true)
				draw_line(Vector2(40, i), Vector2(45, i), tint, 2, true)
			draw_rect(Rect2(17, 17, 14, 14), tint, false, 2)
		"network":
			draw_arc(Vector2(24,24),18,0,TAU,40,tint,2,true)
			draw_arc(Vector2(24,24),9,0,TAU,32,tint,1,true)
			draw_line(Vector2(6,24),Vector2(42,24),tint,2,true)
			draw_line(Vector2(24,6),Vector2(24,42),tint,2,true)
		"file":
			draw_style_box(_box(),Rect2(9,4,30,40))
			draw_rect(Rect2(14,17,20,20),tint,false,1.5)
			for i in [23,30]:draw_line(Vector2(14,i),Vector2(34,i),tint,1,true)
			draw_line(Vector2(23,17),Vector2(23,37),tint,1,true)
		"arrow":
			draw_line(Vector2(3,24),Vector2(43,24),tint,2,true)
			draw_line(Vector2(35,17),Vector2(43,24),tint,2,true)
			draw_line(Vector2(35,31),Vector2(43,24),tint,2,true)

func _box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint,0.08)
	box.border_color = tint
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	return box

static func add_to(parent: Node, symbol: String, side := 32.0, color := Color("347ac4")) -> Control:
	var node = load("res://scripts/service_glyph.gd").new()
	node.kind = symbol
	node.tint = color
	node.custom_minimum_size = Vector2(side,side)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(node)
	return node
