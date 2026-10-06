extends Control
## The drawing projects applied policy. Only the five explicit gate buttons mutate it.
const UI = preload("res://scripts/ui_theme.gd")
const INK = Color("243b40")
const MUTED = Color("61797c")
const LINE = Color("c2d3cf")
const TEAL = Color("187969")
const AMBER = Color("ae6528")
const PAPER = Color("f5f7ef")
var model: Dictionary = {}
var factor := 1.0
var callback: Callable
var gates: Dictionary = {}
var center := Vector2.ZERO
var compact := false
const NAMES := {"faq":"公開 FAQ", "dispatch":"配送進捗", "customers":"顧客連絡先", "desk":"社内問い合わせ", "external":"support-drop"}
const COUNTS := {"faq":"24件 / 配送案内", "dispatch":"120行 / 配送状況", "customers":"3行 / 個人情報", "desk":"要約 6件の受付", "external":"外部の保存先"}

func configure(data: Dictionary, scale: float, action: Callable) -> void:
	name = "AiGateCanvas"; model = data.duplicate(true); factor = scale; callback = action
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["faq", "dispatch", "customers", "desk", "external"]:
		var button := Button.new(); button.name = "AiGate_" + key
		var allowed := bool(model.get("policy", {}).get(key, false))
		button.tooltip_text = str(NAMES[key]) + ("の許可を外す · 1分" if allowed else "を許可する · 1分")
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT if state == "normal" else Color("d9ebe3"), Color.TRANSPARENT, 0, 0, 1))
		button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, Color("14649a"), 0, 0, 1))
		button.pressed.connect(func(): callback.call(key, not allowed))
		button.draw.connect(_draw_gate.bind(button, key)); gates[key] = button; add_child(button)
	resized.connect(_layout); _layout.call_deferred()

func _layout() -> void:
	if size.x <= 0: return
	var width := size.x / factor
	compact = width < 760
	if compact:
		var item_width := (width - 44) / 3
		for index in 3:
			var item: Button = gates[["faq", "dispatch", "customers"][index]]
			item.position = Vector2(10 + index * (item_width + 12), 39) * factor
			item.size = Vector2(item_width, 110) * factor
		center = Vector2(width / 2, 235) * factor
		for index in 2:
			var item: Button = gates[["desk", "external"][index]]
			item.position = Vector2(width / 2 - item_width - 24 + index * (item_width + 48), 342) * factor
			item.size = Vector2(item_width, 110) * factor
		custom_minimum_size.y = 474 * factor
	else:
		var item_width := minf(252, width * .27)
		for index in 3:
			var item: Button = gates[["faq", "dispatch", "customers"][index]]
			item.position = Vector2(18, 46 + index * 109) * factor
			item.size = Vector2(item_width, 100) * factor
		center = Vector2(width * .51, 203) * factor
		for index in 2:
			var item: Button = gates[["desk", "external"][index]]
			item.position = Vector2(width - item_width - 18, 77 + index * 151) * factor
			item.size = Vector2(item_width, 104) * factor
		custom_minimum_size.y = 390 * factor
	queue_redraw()

func _text(on: Control, value: String, point: Vector2, points: int, color: Color = INK, width: float = -1) -> void:
	on.draw_string(on.get_theme_default_font(), point, value, HORIZONTAL_ALIGNMENT_LEFT, width, roundi(points * factor), color)

func _draw_gate(button: Button, key: String) -> void:
	var allowed := bool(model.get("policy", {}).get(key, false))
	var input := key in ["faq", "dispatch", "customers"]
	var width := button.size.x
	var tint := TEAL if allowed else MUTED
	var object := Rect2(Vector2(2, 12) * factor, Vector2(width - 4 * factor, 70 * factor))
	button.draw_rect(object, Color("e9f1e7") if allowed else Color("edf0ec"))
	button.draw_rect(object, tint, false, factor)
	if input:
		button.draw_rect(Rect2(Vector2(2, 5) * factor, Vector2(minf(width * .52, 105 * factor), 8 * factor)), tint)
	else:
		for index in 3:
			button.draw_line(Vector2(9, 18 + index * 5) * factor, Vector2(width - 9 * factor, (18 + index * 5) * factor), tint.lerp(Color.WHITE, .5), factor)
	_text(button, str(NAMES[key]), Vector2(10, 42) * factor, 16, INK, width - 20 * factor)
	_text(button, str(COUNTS[key]), Vector2(10, 66) * factor, 12, MUTED, width - 20 * factor)
	_text(button, "● 許可 → 拒否" if allowed else "× 拒否 → 許可", Vector2(8, 99) * factor, 13, tint, width - 16 * factor)

func _path(from: Vector2, to: Vector2, enabled: bool) -> void:
	var tint := TEAL if enabled else MUTED
	if enabled: draw_line(from, to, tint, 2 * factor, true)
	else: draw_dashed_line(from, to, LINE, 2 * factor, 6 * factor, true)
	var gate := from.lerp(to, .55)
	draw_circle(gate, 11 * factor, PAPER)
	if enabled:
		draw_arc(gate, 8 * factor, -PI * .35, PI * 1.35, 20, tint, 2 * factor, true)
		draw_line(gate - Vector2(0, 8) * factor, gate + Vector2(6, -13) * factor, tint, 2 * factor, true)
	else:
		draw_rect(Rect2(gate - Vector2(7, 7) * factor, Vector2(14, 14) * factor), tint, false, 2 * factor)
		draw_line(gate - Vector2(4, 4) * factor, gate + Vector2(4, 4) * factor, tint, 2 * factor, true)
		draw_line(gate + Vector2(-4, 4) * factor, gate + Vector2(4, -4) * factor, tint, 2 * factor, true)
	var direction := (from - to).normalized(); var normal := Vector2(-direction.y, direction.x)
	draw_polyline(PackedVector2Array([to + (direction * 6 + normal * 4) * factor, to, to + (direction * 6 - normal * 4) * factor]), tint, factor, true)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	for x in range(10, int(size.x), roundi(24 * factor)):
		for y in range(10, int(size.y), roundi(24 * factor)): draw_circle(Vector2(x, y), .7 * factor, Color("dbe5dc"))
	if center == Vector2.ZERO: return
	_text(self, "参照する資料 / READ", Vector2(18, 25) * factor, 13, MUTED)
	_text(self, "送付先 / SEND", Vector2(18, 324) * factor if compact else Vector2(size.x - gates.desk.size.x - 18 * factor, 25 * factor), 13, MUTED)
	for key in gates:
		var item: Button = gates[key]; var input: bool = key in ["faq", "dispatch", "customers"]
		var from: Vector2; var to: Vector2
		if compact:
			from = item.position + Vector2(item.size.x * .5, item.size.y + 3 * factor) if input else center + Vector2(0, 39) * factor
			to = center - Vector2(0, 39) * factor if input else item.position + Vector2(item.size.x * .5, -3 * factor)
		else:
			from = item.position + Vector2(item.size.x + 2 * factor, 45 * factor) if input else center + Vector2(69, 0) * factor
			to = center - Vector2(69, 0) * factor if input else item.position + Vector2(-2 * factor, 45 * factor)
		_path(from, to, bool(model.get("policy", {}).get(key, false)))
	var chip := Rect2(center - Vector2(64, 37) * factor, Vector2(128, 74) * factor)
	draw_rect(chip, INK)
	for index in 6:
		for side in [-1, 1]:
			var pin := center + Vector2(side * 65, -25 + index * 10) * factor
			draw_line(pin, pin + Vector2(side * 7, 0) * factor, INK, 3 * factor)
	_text(self, "AI-07", center + Vector2(-28, -7) * factor, 20, Color("c6f2d8"))
	_text(self, "問い合わせ要約", center + Vector2(-50, 17) * factor, 14, Color.WHITE)
	_text(self, "適用設定 v%d" % int(model.get("world_revision", 0)), center + Vector2(-48, 58) * factor, 12, MUTED)
