extends Control
## Reception deadlines use the same relative scale, separate from delivery time.
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
var rows: Array = []
var factor := 1.0

func setup(queues: Array, scale: float) -> void:
	rows = queues.duplicate(true)
	factor = scale
	custom_minimum_size.y = rows.size()*29*factor
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _text(value: String, x: float, y: float, width: float, color: Color) -> void:
	if width > 0: draw_string(UI.font(500),Vector2(x,y)*factor,value,HORIZONTAL_ALIGNMENT_LEFT,width*factor,roundi(12*factor),color)

func _draw() -> void:
	var w := size.x/factor
	var max_time := 1
	for row in rows: max_time=maxi(max_time,int(row.get("deadline_minute",0)))
	var start := 88.0
	var end := maxf(start+25,w-210)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y := 7.0+i*29
		_text(str(row.get("label","")),0,y+11,84,M.INK)
		draw_line(Vector2(start,y+5)*factor,Vector2(end,y+5)*factor,M.LINE,4*factor)
		var x := start+(end-start)*float(row.get("deadline_minute",0))/max_time
		draw_line(Vector2(start,y+5)*factor,Vector2(x,y+5)*factor,M.DANGER,4*factor)
		draw_circle(Vector2(x,y+5)*factor,4*factor,M.DANGER)
		_text("%d分以内" % int(row.get("deadline_minute",0)),end+12,y+11,80,M.DANGER)
		_text("遅延 ¥%d" % int(row.get("late_compensation",0)),end+94,y+11,w-end-96,M.MUTED)
