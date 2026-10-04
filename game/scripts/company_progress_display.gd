extends Node3D
## The office keeps visible souvenirs of saved company goals. All input is a
## read-only view: this display never awards progress or writes game state.

const GOALS := ["first_delivery", "independent_lab", "sustainable_team"]
const SHORT_TITLES := ["開業の一歩", "頼られる会社", "続く会社へ"]
const INK := Color("284943")
const MUTED := Color("687b78")
const GOLD := Color("c99a38")
const GREEN := Color("287864")
const PALE := Color("d6ded4")

var _font: Font
var _tokens: Array[Node3D] = []
var _cores: Array[MeshInstance3D] = []
var _rims: Array[MeshInstance3D] = []
var _marks: Array[Label3D] = []
var _labels: Array[Label3D] = []
var _bars: Array[MeshInstance3D] = []
var _status: Label3D
var _footer: Label3D
var _seen_earned: Dictionary = {}
var _initialized := false
var _signature := ""
var _tweens: Dictionary = {}

func setup(font: Font) -> void:
	_font = font
	_label("会社の歩み", Vector3(0, 0.48, 0.015), 28, INK)
	for index in GOALS.size():
		var x := (float(index) - 1.0) * 0.74
		if index < GOALS.size() - 1:
			_box(Vector3(0.42, 0.022, 0.015), Vector3(x + 0.37, 0.17, 0), PALE)
		var token := Node3D.new(); token.name = "GoalToken_" + str(GOALS[index]); token.position = Vector3(x, 0.17, 0.028); add_child(token); _tokens.append(token)
		_rims.append(_disc(token, 0.145, 0.018, MUTED))
		_cores.append(_disc(token, 0.12, 0.026, PALE))
		var mark := _label("%02d" % (index + 1), Vector3(0, 0, 0.024), 23, MUTED, token); _marks.append(mark)
		_labels.append(_label(SHORT_TITLES[index], Vector3(x, -0.045, 0.018), 21, INK))
		_box(Vector3(0.56, 0.028, 0.015), Vector3(x, -0.19, 0), PALE)
		var progress := _box(Vector3(1.0, 0.028, 0.019), Vector3(x - 0.28, -0.19, 0.013), GREEN); progress.name = "GoalProgress_" + str(GOALS[index]); progress.visible = false; _bars.append(progress)
	_status = _label("次の一歩は案件ボードへ", Vector3(0, -0.335, 0.019), 19, INK)
	_status.name = "CompanyProgressStatus"
	_footer = _label("", Vector3(0, -0.51, 0.018), 16, MUTED)
	_footer.name = "CompanyProgressFooter"

func sync(view: Dictionary, metadata: Dictionary, animate: bool = false) -> Array[String]:
	var earned: Dictionary = view.get("earned_goals", {})
	var goals: Array = view.get("goals", [])
	var opportunities: Array = view.get("opportunities", [])
	var signature := JSON.stringify([earned, goals, opportunities, metadata])
	var gained: Array[String] = []
	if signature == _signature: return gained
	_signature = signature
	var ready := 0
	var paused := 0
	var preparing := 0
	for item in opportunities:
		if not item is Dictionary: continue
		match str(item.get("status", "")):
			"ready": ready += 1
			"paused": paused += 1
			"locked": preparing += 1
	for index in GOALS.size():
		var id: String = GOALS[index]
		var goal := {}
		for item in goals:
			if item is Dictionary and str(item.get("id", "")) == id: goal = item; break
		# The receipt of an award is distinct from currently meeting conditions.
		# On older saves the model supplies its persisted earned_goals explicitly.
		var complete := earned.has(id)
		var progress := 1.0 if complete else clampf(float(goal.get("progress", 0.0)), 0.0, 1.0)
		set_meta("earned_" + id, complete)
		_material(_cores[index], GREEN if complete else PALE)
		_material(_rims[index], GOLD if complete else MUTED)
		_marks[index].text = "✓" if complete else "%02d" % (index + 1)
		_marks[index].modulate = Color("fff3d2") if complete else MUTED
		_labels[index].text = SHORT_TITLES[index] + ("  達成" if complete else "")
		_labels[index].font_size = 18 if complete else 21
		_bars[index].visible = progress > 0.001
		_bars[index].scale.x = maxf(0.001, 0.56 * progress)
		_bars[index].position.x = (float(index) - 1.0) * 0.74 - 0.28 + 0.28 * progress
		if complete and not _seen_earned.has(id) and _initialized and animate:
			gained.append(str(goal.get("title", SHORT_TITLES[index])))
			_celebrate(index)
	_status.text = "指名相談 %d件  /  経営 [4] で確認" % ready if ready > 0 else "相談を保留中  /  経営 [4] で確認" if paused > 0 else "相談の準備 %d件  /  経営 [4]" % preparing if preparing > 0 else "次の一歩は案件ボード [Tab]"
	_footer.text = "DAY %d  ·  Lv.%d  ·  営業 %d件" % [int(metadata.get("day", 1)), int(metadata.get("level", 1)), int(metadata.get("catalog_count", 0))]
	_seen_earned = earned.duplicate(true)
	_initialized = true
	return gained

func _celebrate(index: int) -> void:
	if _tweens.has(index) and _tweens[index].is_valid(): _tweens[index].kill()
	var token := _tokens[index]
	token.scale = Vector3.ONE * 0.82
	var tween := create_tween()
	tween.tween_property(token, "scale", Vector3.ONE * 1.1, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(token, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tweens[index] = tween

func _material(mesh: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material

func _disc(parent: Node3D, radius: float, height: float, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var shape := CylinderMesh.new(); shape.top_radius = radius; shape.bottom_radius = radius; shape.height = height; shape.radial_segments = 32
	result.mesh = shape; result.rotation.x = PI / 2.0
	_material(result, color); parent.add_child(result); return result

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var shape := BoxMesh.new(); shape.size = size; result.mesh = shape; result.position = at
	_material(result, color); add_child(result); return result

func _label(text: String, at: Vector3, size: int, color: Color, parent: Node3D = self) -> Label3D:
	var result := Label3D.new(); result.text = text; result.font = _font; result.font_size = size; result.pixel_size = 0.0045
	result.position = at; result.modulate = color; result.outline_size = 0; result.no_depth_test = false
	parent.add_child(result); return result
