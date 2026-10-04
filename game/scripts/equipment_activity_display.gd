extends Control
## A physical equipment screen. Motion follows observed work progress, and the
## activation signal is a live presentation event, never a saved-game mutation.
signal activated(work_key: String)
signal animation_frame

const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("e5f4eb")
const MUTED := Color("93b5ae")
const GREEN := Color("71dbb1")
const GOLD := Color("efc765")
var view: Dictionary = {}
var selected: Dictionary = {}
var seen: Dictionary = {}
var initialized := false
var packet_progress := 0.0
var pulse := 0.0
var motion: Tween
var heading: Label
var client: Label
var worker: Label
var result_label: Label
var saving: Label
var detail: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	heading = _label("設備待機", Vector2(28,16), Vector2(584,42), 28, INK)
	client = _label("委任した仕事を、この設備が支えます", Vector2(28,61), Vector2(584,36), 21, MUTED)
	worker = _label("担当", Vector2(22,221), Vector2(160,30), 19, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label("監視モニター", Vector2(218,221), Vector2(204,30), 20, INK, HORIZONTAL_ALIGNMENT_CENTER)
	result_label = _label("作業記録", Vector2(458,221), Vector2(160,30), 19, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	saving = _label("", Vector2(28,268), Vector2(584,35), 24, GOLD)
	detail = _label("通常の委任作業で稼働", Vector2(28,311), Vector2(584,28), 17, MUTED)
	queue_redraw()

func _label(text: String, at: Vector2, extent: Vector2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text; label.position = at; label.size = extent
	label.add_theme_font_override("font", UI.font(600))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func reset_feedback() -> void:
	initialized = false
	seen.clear()

func sync(next_view: Dictionary, live := false, reduced_motion := false) -> void:
	var previous := selected
	view = next_view.duplicate(true)
	var jobs: Array = view.get("jobs", [])
	selected = jobs[0] if not jobs.is_empty() else {}
	for job in jobs:
		var key := str(job.get("key", ""))
		var mode := str(job.get("mode", ""))
		if key.is_empty(): continue
		if (not initialized or not live) and mode != "queued": seen[key] = true
		elif mode in ["paused", "done"]: seen[key] = true
		elif mode == "active" and not seen.has(key):
			seen[key] = true
			activated.emit(key)
	initialized = true
	var mode := str(selected.get("mode", "idle"))
	var advancing := mode == "active" and (str(previous.get("key", "")) != str(selected.get("key", "")) or float(selected.get("progress", 0.0)) > float(previous.get("progress", 0.0)) + 0.00001)
	if motion != null and motion.is_valid(): motion.kill()
	pulse = 0.0
	var destination := float(selected.get("progress", 0.0))
	if advancing and live and not reduced_motion:
		pulse = 1.0
		if str(previous.get("key", "")) != str(selected.get("key", "")): packet_progress = 0.0
		motion = create_tween().set_parallel(true)
		motion.tween_property(self, "packet_progress", destination, 0.22)
		motion.tween_property(self, "pulse", 0.0, 0.42)
		motion.finished.connect(func(): set_process(false); queue_redraw())
		set_process(true)
	else:
		packet_progress = destination
		set_process(false)
	if not is_instance_valid(heading): return
	heading.text = str({"active":"設備稼働中", "done":"委任作業 完了", "paused":"一時停止", "queued":"委任待ち", "waiting":"作業開始を待機", "blocked":"接続を待機"}.get(mode, "設備待機"))
	client.text = str(selected.get("client", "")) if not selected.is_empty() else "委任した仕事を、この設備が支えます"
	if client.text.is_empty(): client.text = str(selected.get("title", "通常の委任作業"))
	worker.text = str(selected.get("member_name", "担当"))
	result_label.text = "復旧・証拠保全" if str(selected.get("role", "")) == "ren" else "調査記録"
	saving.text = "%.0f → %.0f 分  ·  設備で %.0f 分短縮" % [float(selected.get("base_minutes", 0)), float(selected.get("actual_minutes", 0)), float(selected.get("saved_minutes", 0))] if not selected.is_empty() else ""
	detail.text = "担当の成果はチーム画面で確認" if mode == "done" else "作業が進むと設備も動きます" if mode in ["waiting", "queued", "paused", "blocked"] else "残り %d 分%s" % [ceili(float(selected.get("remaining", 0))), "  /  ほか %d 件" % (jobs.size() - 1) if jobs.size() > 1 else ""] if mode == "active" else "通常の委任作業で稼働"
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()
	animation_frame.emit()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(640,360)), Color("173a38"))
	draw_line(Vector2(28,106), Vector2(612,106), Color("315552"), 2)
	var mode := str(selected.get("mode", "idle"))
	var engaged := mode in ["active", "done"]
	var color := GREEN if engaged else GOLD if mode in ["paused", "blocked"] else MUTED
	var a := Vector2(102,165); var b := Vector2(320,165); var c := Vector2(538,165)
	draw_line(a, c, Color("42615c"), 8, true)
	if not selected.is_empty(): draw_line(a, a.lerp(c, clampf(packet_progress,0,1)), color, 8, true)
	for point in [a,b,c]:
		draw_circle(point, 43, Color("254944"))
		draw_arc(point, 43, 0, TAU, 48, color, 3, true)
	if pulse > 0.0:
		draw_arc(b, 48 + (1.0-pulse)*8, 0, TAU, 48, Color(GREEN, pulse * 0.7), 3, true)
	# Person, monitor, and resulting document are large enough to read in-world.
	draw_circle(a + Vector2(0,-12), 10, color)
	draw_arc(a + Vector2(0,20), 21, PI, TAU, 24, color, 7, true)
	draw_rect(Rect2(b + Vector2(-27,-21), Vector2(54,37)), color, false, 4)
	draw_line(b+Vector2(0,16),b+Vector2(0,25),color,4)
	draw_line(b+Vector2(-16,25),b+Vector2(16,25),color,4)
	if mode in ["paused", "blocked"]:
		for x in [-7,7]: draw_line(b+Vector2(x,-10),b+Vector2(x,6),color,5)
	elif mode == "active":
		draw_polyline(PackedVector2Array([b+Vector2(-19,2),b+Vector2(-10,2),b+Vector2(-4,-10),b+Vector2(4,9),b+Vector2(10,-1),b+Vector2(20,-1)]), color, 3, true)
	draw_rect(Rect2(c+Vector2(-17,-24),Vector2(34,46)),color,false,3)
	if mode == "done":
		draw_polyline(PackedVector2Array([c+Vector2(-10,0),c+Vector2(-2,8),c+Vector2(12,-10)]),color,4,true)
	else:
		for y in [-12,0,12]: draw_line(c+Vector2(-10,y),c+Vector2(10,y),color,3)
	if mode == "active":
		var packet := a.lerp(c, clampf(packet_progress,0,1))
		draw_circle(packet,8,INK)
