extends Control
## A commissioning plan, not a reading of a running customer environment.
## Only authored scope and actual stock are drawn. Inspection is read-only.
const UI = preload("res://scripts/ui_theme.gd")
const ART = preload("res://scripts/equipment_art.gd")
const STOCK = preload("res://scripts/customer_stock.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")
const NAVY := Color("172e43")
const GRID := Color("274257")
const WHITE := Color("e7f1f6")
const BLUE := Color("8bcee9")
const AMBER := Color("f1c87b")
var scale_factor := 1.0
var offer: Dictionary = {}
var preview: Dictionary = {}
var scope: Dictionary = {}
var objects: Array[Button] = []
var titles: Array[Label] = []
var captions: Array[Label] = []
var appliance: TextureRect
var inspection: Label
var selection := -1
var sku := ""

func setup(data: Dictionary, stock_preview: Dictionary, factor: float, procure: Callable) -> void:
	name = "QuoteCommissioningBoard"
	offer = data.duplicate(true); preview = stock_preview.duplicate(true); scale_factor = factor
	sku = str(offer.get("supply_requirement", {}).get("sku", ""))
	for item in CATALOG.all():
		if str(item.get("id", "")) == str(offer.get("case_id", "")): scope = item.duplicate(true); break
	set_meta("projection", "planned")
	set_meta("required_files", scope.get("required_files", []).duplicate())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 218 * factor
	var heading := _label("導入設計  /  " + str(offer.get("client", "")), 13, WHITE)
	heading.name = "QuoteScopeIdentity"; add_child(heading)
	heading.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	heading.offset_left = 14 * factor; heading.offset_top = 9 * factor; heading.offset_right = -14 * factor; heading.offset_bottom = 34 * factor
	for index in 3:
		var object := Button.new(); object.name = ["QuoteSourceObject", "QuoteApplianceObject", "QuoteAcceptanceObject"][index]
		object.tooltip_text = ["依頼の対象を確認", "仕入れと在庫を開く", "顧客の受入条件を確認"][index]
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.5, 0.8, 1.0, 0.07) if state != "normal" else Color.TRANSPARENT
			style.border_color = BLUE if state == "focus" else GRID
			style.set_border_width_all(2 if state == "focus" else 0)
			style.set_corner_radius_all(7); object.add_theme_stylebox_override(state, style)
		if index == 1: object.pressed.connect(procure)
		else: object.pressed.connect(_inspect.bind(index))
		add_child(object); objects.append(object)
		var title := _label(["業務台帳" if sku == STOCK.BACKUP_SKU else "支店の利用者", str(STOCK.product(sku).get("model", "")) + " ×%d" % int(offer.get("supply_requirement", {}).get("quantity", 1)), "復元・内容照合" if sku == STOCK.BACKUP_SKU else "業務サイト"][index], 14, WHITE)
		title.name = ["QuoteSourceTitle", "QuoteApplianceTitle", "QuoteAcceptanceTitle"][index]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(title); titles.append(title)
		var caption := _label(_caption(index), 12, AMBER if index == 1 and int(preview.get("shortage", 0)) > 0 else BLUE)
		caption.name = ["QuoteSourceCount", "QuoteApplianceState", "QuoteAcceptanceState"][index]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(caption); captions.append(caption)
	appliance = TextureRect.new(); appliance.name = "QuoteActualAppliance"
	appliance.texture = ART.icon(str(STOCK.product(sku).get("icon", "")))
	appliance.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; appliance.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	appliance.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(appliance)
	inspection = _label("破線 = 導入予定　 /　稼働・内容は受注後に実測", 12, WHITE)
	inspection.name = "QuoteScopeInspection"; add_child(inspection)
	resized.connect(_layout); _layout()

func _label(value: String, points: int, color: Color) -> Label:
	var label := Label.new(); label.text = value
	label.add_theme_font_override("font", UI.font(400))
	label.add_theme_font_size_override("font_size", roundi(points * scale_factor))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _caption(index: int) -> String:
	if index == 0:
		return "%d資料 / 原本を維持" % scope.get("required_files", []).size() if sku == STOCK.BACKUP_SKU else "通常利用を再開"
	if index == 2: return "/restore / 照合必須" if sku == STOCK.BACKUP_SKU else "管理の外部公開を拒否"
	if int(preview.get("shortage", 0)) > 0: return "＋ 会社の不足 %d台" % int(preview.shortage)
	if int(preview.get("available", 0)) < int(preview.get("required", 0)): return "↓ 入荷待ち %d台" % int(preview.get("inbound", 0))
	return "▣ 在庫 %d台 / 未設定" % int(preview.get("available", 0))

func _inspect(index: int) -> void:
	selection = index
	if index == 0 and sku == STOCK.BACKUP_SKU:
		var paths: Array = scope.get("required_files", [])
		inspection.text = "対象: " + " / ".join(PackedStringArray(paths.map(func(path): return str(path).get_file())))
	elif index == 0: inspection.text = "利用者 → DNS・HTTPS → 社内サイト　 /　受注後に経路を実測"
	elif sku == STOCK.BACKUP_SKU: inspection.text = "毎日 → 拠点内保存 → /restore に復元 → 3資料の内容照合"
	else: inspection.text = "業務利用を許可　 /　外部からの管理操作は拒否　 /　納入前に実測"
	set_meta("inspected", index); queue_redraw()
	_layout()

func _layout() -> void:
	if objects.size() != 3: return
	var width := size.x / 3.0
	for index in 3:
		objects[index].position = Vector2(width * index + 9 * scale_factor, 43 * scale_factor)
		objects[index].size = Vector2(width - 18 * scale_factor, 118 * scale_factor)
		titles[index].position = Vector2(width * index + 8 * scale_factor, 139 * scale_factor)
		titles[index].size = Vector2(width - 16 * scale_factor, 25 * scale_factor)
		captions[index].position = Vector2(width * index + 8 * scale_factor, 167 * scale_factor)
		captions[index].size = Vector2(width - 16 * scale_factor, 25 * scale_factor)
	appliance.position = Vector2(width + 24 * scale_factor, 48 * scale_factor)
	appliance.size = Vector2(width - 48 * scale_factor, 86 * scale_factor)
	inspection.position = Vector2(14 * scale_factor, 195 * scale_factor)
	inspection.size = Vector2(size.x - 28 * scale_factor, 23 * scale_factor)
	custom_minimum_size.y = maxf(224 * scale_factor, 197 * scale_factor + inspection.get_combined_minimum_size().y + 8 * scale_factor)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), NAVY)
	for x in range(0, int(size.x), 24): draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 0.5)
	for y in range(0, int(size.y), 24): draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 0.5)
	var width := size.x / 3.0
	for index in 2:
		var from := Vector2(width * (index + 0.78), 93 * scale_factor)
		var to := Vector2(width * (index + 1.23), from.y)
		draw_dashed_line(from, to, BLUE, 2 * scale_factor, 6 * scale_factor)
		draw_polyline(PackedVector2Array([to + Vector2(-7, -5) * scale_factor, to, to + Vector2(-7, 5) * scale_factor]), BLUE, 2 * scale_factor, true)
	var left := Vector2(width * 0.5, 94 * scale_factor)
	var right := Vector2(width * 2.5, left.y)
	if sku == STOCK.BACKUP_SKU:
		for index in 3:
			var pos := left + Vector2(-34 + index * 20, -36 + (index % 2) * 8) * scale_factor
			draw_style_box(_paper(), Rect2(pos, Vector2(46, 62) * scale_factor))
			for line in 4: draw_line(pos + Vector2(8, 16 + line * 9) * scale_factor, pos + Vector2(36, 16 + line * 9) * scale_factor, GRID, scale_factor)
		draw_rect(Rect2(right + Vector2(-48, 14) * scale_factor, Vector2(96, 15) * scale_factor), BLUE, false, 2 * scale_factor)
		for index in 2:
			var pos := right + Vector2(-29 + index * 24, -32) * scale_factor
			draw_style_box(_paper(), Rect2(pos, Vector2(36, 48) * scale_factor))
			draw_line(pos + Vector2(7, 17) * scale_factor, pos + Vector2(27, 17) * scale_factor, GRID, scale_factor)
		# Empty acceptance stamp: a requirement, never an invented PASS.
		draw_arc(right + Vector2(44, -17) * scale_factor, 14 * scale_factor, 0, TAU, 32, AMBER, 2 * scale_factor, true)
		draw_line(right + Vector2(36, -17) * scale_factor, right + Vector2(52, -17) * scale_factor, AMBER, 2 * scale_factor)
	else:
		draw_rect(Rect2(left + Vector2(-38, -28) * scale_factor, Vector2(76, 48) * scale_factor), BLUE, false, 3 * scale_factor)
		draw_line(left + Vector2(0, 20) * scale_factor, left + Vector2(0, 30) * scale_factor, BLUE, 3 * scale_factor)
		draw_line(left + Vector2(-23, 30) * scale_factor, left + Vector2(23, 30) * scale_factor, BLUE, 3 * scale_factor)
		for index in 3:
			draw_rect(Rect2(right + Vector2(-44, -31 + index * 23) * scale_factor, Vector2(88, 18) * scale_factor), BLUE, false, 2 * scale_factor)
			draw_circle(right + Vector2(30, -22 + index * 23) * scale_factor, 2 * scale_factor, BLUE)
		draw_line(right + Vector2(46, 28) * scale_factor, right + Vector2(61, 43) * scale_factor, AMBER, 3 * scale_factor)
		draw_line(right + Vector2(61, 28) * scale_factor, right + Vector2(46, 43) * scale_factor, AMBER, 3 * scale_factor)
	if int(preview.get("shortage", 0)) > 0:
		var center := Vector2(width * 1.72, 60 * scale_factor)
		draw_circle(center, 13 * scale_factor, AMBER)
		draw_line(center + Vector2(-6, 0) * scale_factor, center + Vector2(6, 0) * scale_factor, NAVY, 2 * scale_factor)
		draw_line(center + Vector2(0, -6) * scale_factor, center + Vector2(0, 6) * scale_factor, NAVY, 2 * scale_factor)

func _paper() -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = Color("f5e9cb"); style.border_color = Color("c4b58d"); style.set_border_width_all(1)
	return style
