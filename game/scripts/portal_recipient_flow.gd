extends Control
## The recipient's recorded operations, pending input and actual storage reply.
## These objects never issue commands or infer success from a sharing policy.
const UI = preload("res://scripts/ui_theme.gd")
const BLUE := Color("006a9e")
const INK := Color("253e4d")
const MUTED := Color("637986")
var stages: Array = []
var factor := 1.0
var compact := false
var labels: Array[Label] = []

static func signature(snapshot: Dictionary, identities: Array) -> String:
	return JSON.stringify({"files":snapshot.get("files",[]),"shares":snapshot.get("shares",[]),"config":snapshot.get("config",{}),"active":snapshot.get("active",false),"storage":snapshot.get("external_storage",{}),"identities":identities}).sha256_text()

static func record(history: Dictionary, key: String, method: String, response: String, stamp: String) -> Dictionary:
	var result := history.duplicate(true)
	var entry: Dictionary = result.get(key, {}).duplicate(true)
	entry[method] = {"ok":response.begins_with("HTTP/1.1 200"),"status":response.get_slice("\n",0),"stamp":stamp}
	result[key] = entry
	return result

static func project(history: Dictionary, key: String, stamp: String, dirty: bool) -> Array:
	var entry: Dictionary = history.get(key,{})
	var get: Dictionary = entry.get("GET",{})
	var put: Dictionary = entry.get("PUT",{})
	return [
		_stage(get,stamp,"資料を開く","未読込","読込済み","開けません"),
		{"kind":"draft" if dirty else "idle","text":"表を編集\n"+("未提出の入力" if dirty else "未編集")},
		_stage(put,stamp,"共有へ保存","未提出","保存済み","提出できません")
	]

static func _stage(value: Dictionary, stamp: String, title: String, pending: String, success: String, failure: String) -> Dictionary:
	if value.is_empty(): return {"kind":"idle","text":title+"\n"+pending}
	if str(value.get("stamp","")) != stamp: return {"kind":"stale","text":title+"\n変更前の結果"}
	return {"kind":"ok" if bool(value.get("ok",false)) else "blocked","text":title+"\n"+(success if bool(value.get("ok",false)) else failure)}

func setup(value: Array, scale: float, small: bool = false) -> void:
	name = "PortalRecipientFlow"; stages = value.duplicate(true); factor = scale
	compact = small
	custom_minimum_size.y = (90 if compact else 127) * factor; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for stage in stages:
		var label := Label.new(); label.text = str(stage.text)
		label.name = "PortalWorkStage_" + str(labels.size())
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font",UI.font(500))
		label.add_theme_font_size_override("font_size",int(12*factor))
		label.add_theme_color_override("font_color",INK); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label); labels.append(label)
	resized.connect(_layout); _layout()

func _layout() -> void:
	for index in labels.size():
		labels[index].position = Vector2(size.x*(.02+index*.34),(49 if compact else 75)*factor)
		labels[index].size = Vector2(size.x*.28,(40 if compact else 48)*factor)
	queue_redraw()

func _draw() -> void:
	for index in 3:
		var center := Vector2(size.x*(.16+index*.34),(24 if compact else 35)*factor)
		var glyph_scale := factor * (.62 if compact else 1.0)
		var kind := str(stages[index].kind)
		var color := BLUE if kind in ["ok","draft"] else MUTED
		if index < 2:
			var from := center+Vector2(40,0)*glyph_scale; var to := Vector2(size.x*(.50+index*.34)-40*glyph_scale,center.y)
			draw_dashed_line(from,to,MUTED,1.5*factor,5*factor)
			draw_polyline(PackedVector2Array([to-Vector2(5,3)*factor,to,to-Vector2(5,-3)*factor]),MUTED,1.5*factor,true)
		if index == 2:
			for shelf in 3:
				var box := Rect2(center+Vector2(-29,-27+shelf*20)*glyph_scale,Vector2(58,17)*glyph_scale)
				draw_style_box(UI.style(Color("edf4f7"),color,3,0,1),box)
				draw_circle(box.end-Vector2(9,8)*glyph_scale,2*glyph_scale,color)
		else:
			var paper := Rect2(center-Vector2(25,30)*glyph_scale,Vector2(50,60)*glyph_scale)
			draw_style_box(UI.style(Color("fffdf7"),color,2,0,1),paper)
			for line in 4: draw_line(center+Vector2(-16,-12+line*10)*glyph_scale,center+Vector2(16,-12+line*10)*glyph_scale,Color("cad9e2"),1.5*factor)
			if index == 1 and kind == "draft":
				draw_line(center+Vector2(12,20)*glyph_scale,center+Vector2(34,-10)*glyph_scale,BLUE,5*glyph_scale,true)
				draw_circle(center+Vector2(12,20)*glyph_scale,2*glyph_scale,INK)
		if kind in ["ok","blocked","stale"]:
			var badge := center+Vector2(28,24)*glyph_scale
			draw_circle(badge,12*glyph_scale,Color.WHITE)
			draw_arc(badge,11*glyph_scale,0,TAU,32,color,1.5*glyph_scale,true)
			if kind == "ok": draw_polyline(PackedVector2Array([badge+Vector2(-6,0)*glyph_scale,badge+Vector2(-1,5)*glyph_scale,badge+Vector2(6,-5)*glyph_scale]),BLUE,2.5*glyph_scale,true)
			elif kind == "blocked":
				draw_line(badge-Vector2.ONE*5*glyph_scale,badge+Vector2.ONE*5*glyph_scale,MUTED,2*glyph_scale,true)
				draw_line(badge+Vector2(-5,5)*glyph_scale,badge+Vector2(5,-5)*glyph_scale,MUTED,2*glyph_scale,true)
			else: draw_arc(badge,6*glyph_scale,0,PI*1.6,20,MUTED,2*glyph_scale,true)
