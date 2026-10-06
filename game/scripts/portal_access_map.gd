extends Control
## Saved sharing policy and recorded traffic. Drawing never runs guest commands.
signal role_selected(role: String)
const UI = preload("res://scripts/ui_theme.gd")
const OBSERVATION = preload("res://scripts/diagnostic_observation.gd")
const BLUE := Color("006a9e")
const INK := Color("253e4d")
const MUTED := Color("637986")
const LINE := Color("cbdde6")
const GROUPS := {
	"staff":["staff-read"],
	"partner":["partner-read", "partner-write"],
	"public":["partner-anonymous", "partner-password-only", "public-read"],
	"links":["week-old-link", "expired-link"],
	"audit":["portal-audit"]
}
var model: Dictionary = {}
var factor := 1.0
var selected := "partner"
var actors: Dictionary = {}
var fields: Array = []
var replay := -1.0
var replay_group := ""

static func project(snapshot: Dictionary, probes: Array, path: String) -> Dictionary:
	var file := {}
	for item in snapshot.get("files", []):
		if str(item.get("path", "")) == path: file = item.duplicate(true); break
	var shares := {}
	for item in snapshot.get("shares", []):
		if str(item.get("path", "")) == path: shares[str(item.get("role", ""))] = item.duplicate(true)
	var measured := {}
	for probe in probes: measured[str(probe.get("id", ""))] = OBSERVATION.project(probe)
	return {"file":file, "shares":shares, "observations":measured, "config":snapshot.get("config", {}).duplicate(true)}

static func group_status(value: Dictionary, group: String) -> String:
	var all_passed := true
	for id in GROUPS.get(group, []):
		var item: Dictionary = value.get("observations", {}).get(id, {})
		if not bool(item.get("recorded", false)): return "未検査"
		if not bool(item.get("fresh", false)): return "変更前"
		all_passed = all_passed and bool(item.get("passed", false))
	return "✓ 一致" if all_passed else "× 不一致"

func setup(value: Dictionary, scale: float, role: String) -> void:
	model = value.duplicate(true); factor = scale; selected = role
	name = "PortalAccessDiagram"; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 321 * factor; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 3:
		var id: String = ["staff", "partner", "public"][index]
		var button := Button.new(); button.name = "PortalAccessActor_" + id; button.flat = true
		button.tooltip_text = "この共有先の権限・期限を編集"; button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, UI.style(Color("dceef8") if id == selected or state == "hover" else Color.TRANSPARENT, BLUE if state == "focus" else Color.TRANSPARENT, 8, 0, 1))
		button.pressed.connect(func(): role_selected.emit(id)); button.draw.connect(_actor.bind(button, id))
		add_child(button); actors[id] = button
		_field("PortalAccessPolicy_" + id, _permission(id), .10, 47 + index * 70, .22, 12)
		_field("PortalAccessObserved_" + id, _traffic(id), .40, 38 + index * 70, .24, 12)
	_field("PortalAccessFile", str(model.file.get("name", "資料なし")), .65, 191, .33, 13)
	_field("PortalAccessFileSize", "%d B" % int(model.file.get("size", 0)), .65, 216, .33, 11)
	var expiry := str(model.shares.get("partner", {}).get("expires", "unlimited"))
	_field("PortalAccessExpiry", "取引先の期限: " + {"7d":"7日", "30d":"30日", "unlimited":"無期限"}.get(expiry, expiry), .02, 255, .30, 12)
	_field("PortalAccessOld8", _link_traffic("week-old-link",8), .38, 289, .29, 12)
	_field("PortalAccessOld31", _link_traffic("expired-link",31), .69, 289, .29, 12)
	resized.connect(_layout); _layout()

func _link_traffic(id: String, age: int) -> String:
	var item: Dictionary = model.observations.get(id,{})
	if not bool(item.get("recorded",false)): return "%d日前 · 未検査" % age
	var prefix := "変更前 " if not bool(item.get("fresh",false)) else "✓ " if bool(item.get("passed",false)) else "× "
	return prefix + "%d日前 · HTTP %d" % [age,int(item.get("status",0))]

func _permission(role: String) -> String:
	return "設定: " + {0:"遮断", 1:"閲覧", 3:"更新"}.get(int(model.shares.get(role, {}).get("permissions", 0)), "不明")

func _traffic(role: String) -> String:
	var id: String = {"staff":"staff-read", "partner":"partner-read", "public":"public-read"}[role]
	var item: Dictionary = model.observations.get(id, {})
	if not bool(item.get("recorded", false)): return "実測: 未検査"
	return ("実測: " if bool(item.get("fresh", false)) else "変更前: ") + "HTTP %d" % int(item.get("status", 0))

func _field(id: String, text: String, x: float, y: float, width: float, points: int) -> void:
	var label := Label.new(); label.name = id; label.text = text
	label.add_theme_font_override("font", UI.font(500)); label.add_theme_font_size_override("font_size", int(points * factor))
	label.add_theme_color_override("font_color", INK); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(label)
	fields.append({"node":label, "x":x, "y":y, "width":width})

func _layout() -> void:
	for index in 3:
		var button: Button = actors[["staff", "partner", "public"][index]]
		button.position = Vector2(size.x * .015, (7 + index * 70) * factor)
		button.size = Vector2(size.x * .32, 63 * factor); button.queue_redraw()
	for field in fields:
		field.node.position = Vector2(size.x * float(field.x), float(field.y) * factor)
		field.node.size = Vector2(size.x * float(field.width), 27 * factor)
	queue_redraw()

func _actor(button: Button, role: String) -> void:
	var center := Vector2(size.x * .04, 25 * factor)
	button.draw_circle(center + Vector2(0,-8)*factor, 7*factor, BLUE)
	button.draw_arc(center + Vector2(0,13)*factor, 13*factor, PI, TAU, 20, BLUE, 3*factor, true)
	if role == "public": button.draw_arc(center, 19*factor, 0,TAU,32,BLUE,1.5*factor,true)
	button.draw_string(UI.font(600), Vector2(size.x*.085, 31*factor), {"staff":"社員", "partner":"取引先", "public":"公開先"}[role], HORIZONTAL_ALIGNMENT_LEFT, size.x*.22, int(14*factor), INK)

func _draw() -> void:
	draw_style_box(UI.style(Color("f4f9fc"), LINE, 6, 0, 1), Rect2(Vector2.ZERO, size))
	var paper := Rect2(Vector2(size.x*.72,19*factor),Vector2(size.x*.19,164*factor))
	draw_style_box(UI.style(Color("fffdf7"), Color("93adb9"), 4, 0, 1), paper)
	var fold := minf(20*factor, paper.size.x*.2)
	draw_colored_polygon(PackedVector2Array([paper.position+Vector2(paper.size.x-fold,0),paper.position+Vector2(paper.size.x,fold),paper.position+Vector2(paper.size.x-fold,fold)]),LINE)
	for index in 5:
		var y := paper.position.y + (48 + index*19)*factor
		draw_line(Vector2(paper.position.x+10*factor,y),Vector2(paper.end.x-10*factor,y),LINE,1.5*factor)
	draw_line(Vector2(paper.position.x+paper.size.x*.55,paper.position.y+29*factor),Vector2(paper.position.x+paper.size.x*.55,paper.end.y-15*factor),LINE,1.5*factor)
	for index in 3:
		var role: String = ["staff", "partner", "public"][index]
		var y := (31 + index*70)*factor
		var enabled := int(model.shares.get(role, {}).get("permissions", 0)) > 0
		var start := Vector2(size.x*.34,y); var end := Vector2(size.x*.70,y)
		if enabled: draw_line(start,end,BLUE,2*factor,true)
		else: draw_dashed_line(start,end,MUTED,2*factor,7*factor,true)
		if enabled:
			draw_polyline(PackedVector2Array([end-Vector2(6,4)*factor,end,end-Vector2(6,-4)*factor]),BLUE,2*factor,true)
		else: _cross(Vector2(size.x*.52,y),8*factor,MUTED)
		if replay >= 0 and (replay_group == role or replay_group == "public" and role == "partner"):
			draw_circle(start.lerp(end,clampf(replay,0,1)),5*factor,BLUE)
	var base := 239*factor; var left := size.x*.37; var right := size.x*.96
	draw_line(Vector2(left,base),Vector2(right,base),LINE,4*factor)
	var expiry := str(model.shares.get("partner", {}).get("expires", "unlimited"))
	var days := 7 if expiry == "7d" else 30 if expiry == "30d" else 31
	var available := int(model.shares.get("partner", {}).get("permissions", 0)) > 0
	if available: draw_line(Vector2(left,base),Vector2(lerpf(left,right,days/31.0),base),BLUE,4*factor)
	if replay >= 0 and replay_group == "links": draw_circle(Vector2(lerpf(left,right,clampf(replay,0,1)),base),5*factor,BLUE)
	for day in [0,7,8,30,31]:
		var x := lerpf(left,right,day/31.0)
		# Closely spaced dates alternate rows, preserving distinct hit-free labels.
		var offset := 12 if day in [0,7,30] else 32
		draw_line(Vector2(x,base-5*factor),Vector2(x,base+5*factor),BLUE,2*factor)
		draw_string(UI.font(500),Vector2(x-9*factor,base+offset*factor),str(day)+"日",HORIZONTAL_ALIGNMENT_LEFT,-1,int(11*factor),INK)
		if day in [8,31] and (not available or expiry != "unlimited" and day > days): _cross(Vector2(x,base-12*factor),5*factor,MUTED)

func _cross(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center,radius+3*factor,Color("f4f9fc"))
	draw_line(center-Vector2.ONE*radius,center+Vector2.ONE*radius,color,2*factor,true)
	draw_line(center+Vector2(-radius,radius),center+Vector2(radius,-radius),color,2*factor,true)

func play_observation(group: String) -> void:
	replay_group = group; replay = 0.0; set_process(true)

func _process(delta: float) -> void:
	if replay < 0: set_process(false); return
	replay += delta / .9
	if replay > 1.4: replay = -1; set_process(false)
	queue_redraw()
