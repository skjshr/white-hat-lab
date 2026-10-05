extends Control
## Explorer's retrieved document and editable copy. No requests while drawing.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("243641")
var factor := 1.0
var paper_height := 106.0
var copy_present := false
var copy_dirty := false
var items: Dictionary = {}

func setup(d, filename: String, path: String, upload: Callable) -> void:
	name = "SmbDocumentDesk"; factor = float(d.game.settings.get("text_scale", 1.0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label("SmbDocumentName", filename, 15)
	_label("SmbDocumentSnapshot", "取得時の内容", 12)
	_label("SmbCopyTitle", "編集用コピー", 13)
	var present: bool = not path.is_empty() and d.game.vm_list(path.get_base_dir()).has(path)
	var dirty: bool = not path.is_empty() and d.drafts.has(path) and str(d.drafts[path]) != str(d.game.vm_read(path))
	var changed: bool = present and str(d.game.vm_read(path)) != str(d.samba_ui.get("access_preview", ""))
	copy_present = present; copy_dirty = dirty
	var state := "? コピーなし" if not present else "● 未保存の編集" if dirty else "✓ コピーを保存済み" if changed else "✓ 取得時と同じ"
	_label("SmbCopyState", state, 12)
	var preview := TextEdit.new(); preview.name = "SmbPreview"; preview.editable = false; preview.tab_input_mode = false
	preview.text = str(d.samba_ui.get("access_preview", ""))
	preview.add_theme_font_override("font", UI.font(400)); preview.add_theme_font_size_override("font_size", roundi(13 * factor))
	paper_height = maxf(106 * factor, preview.get_theme_font("font").get_height(preview.get_theme_font_size("font_size")) * 5 + 10 * factor)
	custom_minimum_size = Vector2(0, paper_height + 62 * factor)
	for kind in ["normal", "read_only"]: preview.add_theme_stylebox_override(kind, UI.style(Color("fffdf5"), Color.TRANSPARENT, 5, 5, 0))
	for kind in ["font_color", "font_readonly_color", "font_uneditable_color"]: preview.add_theme_color_override(kind, INK)
	add_child(preview); items.preview = preview
	var edit: Button = d._button("編集", func(): d._open_editor(path)); edit.name = "SmbEdit"; edit.disabled = path.is_empty()
	var send: Button = d._button("共有へ送信", upload); send.name = "SmbUploadEdited"; send.disabled = path.is_empty()
	for button in [edit, send]:
		for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(color, INK)
		for kind in ["normal", "hover", "pressed", "focus"]: button.add_theme_stylebox_override(kind, UI.style(Color("e8f1f8"), Color("6f92a7"), 7, 5, 3))
		add_child(button)
	items.edit = edit; items.send = send
	resized.connect(_layout)
	if d.smb_document_focus:
		d.smb_document_focus = false
		_focus_document.call_deferred(d)

func _label(id: String, value: String, font_size: int) -> void:
	var label := Label.new(); label.name = id; label.text = value
	label.add_theme_font_override("font", UI.font(400)); label.add_theme_font_size_override("font_size", roundi(font_size * factor))
	label.add_theme_color_override("font_color", INK); label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true; label.tooltip_text = value
	add_child(label); items[id] = label

func _ready() -> void: _layout()
func _focus_document(d) -> void:
	for _frame in 3:
		await d.get_tree().process_frame
		if not is_instance_valid(self) or not is_inside_tree(): return
	if d.current_app != "files" or not is_visible_in_tree(): return
	items.edit.grab_focus()
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(self)
		ancestor = ancestor.get_parent()
func _place(id: String, rect: Rect2) -> void:
	var item: Control = items[id]; item.position = rect.position; item.size = rect.size
func _layout() -> void:
	if size.x <= 1: return
	var w := size.x
	_place("SmbDocumentName", Rect2(12 * factor, 4 * factor, w * .61 - 24 * factor, 25 * factor))
	_place("preview", Rect2(8 * factor, 31 * factor, w * .64 - 16 * factor, paper_height))
	_place("SmbDocumentSnapshot", Rect2(12 * factor, paper_height + 35 * factor, w * .61, 23 * factor))
	_place("SmbCopyTitle", Rect2(w * .76, 5 * factor, w * .23, 23 * factor))
	_place("SmbCopyState", Rect2(w * .69, 37 * factor, w * .30, 25 * factor))
	_place("edit", Rect2(w * .71, 71 * factor, w * .28, 33 * factor))
	_place("send", Rect2(w * .71, 116 * factor, w * .28, 33 * factor))
	queue_redraw()
func _draw() -> void:
	var w := size.x
	draw_style_box(UI.style(Color("fffdf5"), Color("c8c1b2"), 0, 0, 2), Rect2(0, 0, w * .64, paper_height + 60 * factor))
	var corner := Vector2(w * .64, 0)
	draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(-14, 0) * factor, corner + Vector2(0, 14) * factor]), Color("e5dcc7"))
	draw_line(Vector2(10 * factor, 30 * factor), Vector2(w * .64 - 10 * factor, 30 * factor), Color("d8d3c5"), factor)
	# The large paper is the fetched response; the small sheet is the copy.
	var copy_origin := Vector2(w * .69, 3 * factor)
	var copy_rect := Rect2(copy_origin, Vector2(23, 27) * factor)
	if copy_present:
		draw_rect(Rect2(copy_origin + Vector2(3, 3) * factor, copy_rect.size), Color("c2d3de"))
		draw_style_box(UI.style(Color("f8fbfd"), Color("7293a2"), 0, 0, 0), copy_rect)
		for line in 3:
			draw_line(copy_origin + Vector2(5, 9 + line * 5) * factor, copy_origin + Vector2(18, 9 + line * 5) * factor, Color("7293a2"), factor)
		if copy_dirty:
			draw_line(copy_origin + Vector2(17, 25) * factor, copy_origin + Vector2(27, 15) * factor, Color("ad6924"), 3 * factor, true)
	else: draw_rect(copy_rect, Color("7293a2"), false, factor)
	draw_line(Vector2(w * .65, 84 * factor), Vector2(w * .70, 84 * factor), Color("7293a2"), 2 * factor, true)
	draw_colored_polygon(PackedVector2Array([Vector2(w * .70, 84 * factor), Vector2(w * .70 - 7 * factor, 80 * factor), Vector2(w * .70 - 7 * factor, 88 * factor)]), Color("7293a2"))
