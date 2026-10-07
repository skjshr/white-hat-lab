extends Control
## Saved assignments share one time axis; the projection never advances work.
const MODEL = preload("res://scripts/intake_decision_model.gd")
const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")
var game
var factor := 1.0
var snapshot: Dictionary = {}
var refresh := 0.0
var all_standby := true
var retained_logical_height := 0.0
var route: Button

func setup(g, scale: float) -> void:
	game = g
	factor = scale
	name = "IntakeCapacityCanvas"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_update()

func set_route(button: Button) -> void:
	route = button
	add_child(route)
	_layout()

func _layout() -> void:
	if is_instance_valid(route):
		route.position = Vector2(maxf(0,size.x-195*factor),size.y-34*factor)
		route.size = Vector2(190,30)*factor
	queue_redraw()

func _process(delta: float) -> void:
	refresh += delta
	if refresh >= .5:
		refresh = 0
		_update()

func _update() -> void:
	if not is_instance_valid(game): return
	var next := MODEL.company(game)
	if next == snapshot: return
	snapshot = next
	all_standby = true
	for person in snapshot.get("people", []):
		if not person.get("jobs", []).is_empty(): all_standby = false
	_update_content_height(snapshot.get("people", []).size(), all_standby)
	_layout()

func _update_content_height(people_count: int, standby: bool) -> void:
	var required := 108.0 if standby or people_count <= 0 else 72.0 + people_count * 34.0
	# Keep the current sales rows stationary while a colleague finishes work.
	# A newly opened canvas starts fresh; a roster increase may still expand it.
	retained_logical_height = maxf(retained_logical_height, required)
	custom_minimum_size.y = retained_logical_height * factor

func _text(value: String, x: float, y: float, points: int, color: Color, width: float) -> void:
	if width > 0: draw_string(UI.font(500), Vector2(x,y)*factor, value, HORIZONTAL_ALIGNMENT_LEFT, width*factor, roundi(points*factor), color)

func _rect(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(Vector2(x,y)*factor, Vector2(w,h)*factor), color)

func _draw() -> void:
	var w := size.x / factor
	var rows: Array = snapshot.get("people", [])
	var now := int(snapshot.get("clock_minute", 540))
	var day := int(snapshot.get("day", 1))
	var horizon := 30
	for person in rows:
		for job in person.get("jobs", []):
			if bool(job.get("time_known", false)):
				horizon = maxi(horizon, (int(job.finish_day)-day)*1440+int(job.finish_minute)-now)
	var left := 112.0
	var right := w - 155
	var span := maxf(50, right - left)
	_rect(0,0,w,size.y/factor,M.PAPER)
	_text("現在の担当",12,22,14,M.INK,100)
	_text(str(snapshot.get("clock_text", "")),left,22,13,M.ACCENT,80)
	if not all_standby:
		_text("+%d分" % horizon,right-50,22,12,M.MUTED,60)
		_text("終了見込み",right+14,22,12,M.MUTED,130)
	for i in rows.size():
		var person: Dictionary = rows[i]
		if all_standby:
			var cell := w/maxi(1,rows.size())
			var x := 12+i*cell
			draw_circle(Vector2(x+11,46)*factor,7*factor,M.ACCENT)
			draw_arc(Vector2(x+11,64)*factor,13*factor,PI,TAU,16,M.ACCENT,3*factor,true)
			_text(str(person.get("name", "")),x+32,48,14,M.INK,cell-40)
			_text("待機" if bool(person.get("runtime_available", true)) else "稼働外",x+32,68,12,M.MUTED,cell-40)
			continue
		var y := 32.0 + i * 34
		var jobs: Array = person.get("jobs", [])
		var blocked := not str(person.get("blocked_reason", "")).is_empty() or not bool(person.get("runtime_available", true))
		_text(str(person.get("name", "")),12,y+20,14,M.INK,92)
		_rect(left,y+3,span,23,M.CANVAS)
		for step in [0,.5,1]:
			draw_line(Vector2(left+span*step,y+2)*factor,Vector2(left+span*step,y+28)*factor,M.LINE,factor)
		var finish := "待機 · 割当なし"
		if blocked: finish = "Ⅱ 中断 / 稼働外"
		for job in jobs:
			if not bool(job.get("time_known",false)):
				finish = "? 終了時刻未定"
				continue
			var start := (int(job.start_day)-day)*1440+int(job.start_minute)-now
			var end := (int(job.finish_day)-day)*1440+int(job.finish_minute)-now
			var x := left + span * clampf(float(start)/horizon,0,1)
			var end_x := left + span * clampf(float(end)/horizon,0,1)
			var color := M.WARNING if bool(job.get("blocked",false)) else M.ACCENT
			_rect(x,y+5,maxf(3,end_x-x),19,color)
			if end_x-x > 65: _text(str(job.get("client","作業")),x+5,y+19,11,M.WHITE,end_x-x-8)
			finish = "%02d:%02d" % [int(job.finish_minute)/60,int(job.finish_minute)%60]
			if int(job.finish_day) != day: finish = "D%d " % int(job.finish_day) + finish
			if bool(job.get("blocked",false)): finish = "Ⅱ " + finish
		if jobs.is_empty(): _text("—",left+8,y+20,14,M.MUTED,30)
		_text(finish,right+14,y+20,13,M.INK,w-right-24)
	var bottom := size.y/factor-10
	_text("受注 %d/%d   本人専任 %d   保守待ち %d" % [int(snapshot.get("open_contracts",0)),int(snapshot.get("contract_capacity",0)),int(snapshot.get("own_unfinished_count",0)),int(snapshot.get("pending_care",0))],12,bottom,12,M.MUTED,w-210)
