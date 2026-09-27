extends Control
const UI = preload("res://scripts/ui_theme.gd")
## Lightweight native Controls: persistent, movable desktop application windows.
signal focused(app: String)
signal minimized(app: String)
signal dismissed(app: String)
var app_id := ""
var content: VBoxContainer
var caption: Label
var titlebar: PanelContainer
var frame: StyleBoxFlat
var title_text := ""
var titlebar_row: HBoxContainer
var chrome_buttons: Array[Button] = []
var title_drag_handle: Control
var maximized := false
var restore_rect := Rect2()
var _dragging := false
var _resizing := false
var _origin := Vector2.ZERO
var _initial := Rect2()
var _desktop_host: Control

func _enter_tree() -> void:
	_connect_desktop_host()

func _exit_tree() -> void:
	if is_instance_valid(_desktop_host) and _desktop_host.resized.is_connected(_parent_resized):
		_desktop_host.resized.disconnect(_parent_resized)
	_desktop_host = null

func _connect_desktop_host() -> void:
	_desktop_host = get_parent_control()
	if is_instance_valid(_desktop_host) and not _desktop_host.resized.is_connected(_parent_resized):
		_desktop_host.resized.connect(_parent_resized)

func _chrome_color(active: bool = true) -> Color:
	if app_id in ["editor", "terminal"]: return Color("323233") if active else Color("282828")
	return Color("dee7f3") if app_id == "browser" else Color("f3f3f3")

func _chrome_ink(active: bool = true) -> Color:
	if app_id in ["editor", "terminal"]: return Color("cccccc") if active else Color("999999")
	return Color("242424") if active else Color("777777")

func configure(id: String, title: String, _accent: Color) -> void:
	app_id = id; name = "Window_" + id
	title_text = title
	custom_minimum_size = Vector2(530, 320)
	clip_contents = true
	frame = StyleBoxFlat.new(); frame.bg_color = UI.app_background(id); frame.border_color = Color("b8c3cd"); frame.set_border_width_all(1); frame.set_corner_radius_all(7); frame.shadow_color = Color(0,0,0,0.22); frame.shadow_size = 9; frame.shadow_offset = Vector2(0,4)
	var panel := PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_theme_stylebox_override("panel",frame); add_child(panel)
	var layout := VBoxContainer.new(); layout.add_theme_constant_override("separation",0); panel.add_child(layout)
	titlebar = PanelContainer.new(); titlebar.custom_minimum_size.y = 34; titlebar.mouse_default_cursor_shape = Control.CURSOR_MOVE; layout.add_child(titlebar)
	var bar := StyleBoxFlat.new(); bar.bg_color = _chrome_color(); bar.content_margin_left = 10; bar.content_margin_right = 0; titlebar.add_theme_stylebox_override("panel",bar)
	var row := HBoxContainer.new(); row.mouse_filter = Control.MOUSE_FILTER_PASS; row.add_theme_constant_override("separation",0); titlebar.add_child(row); titlebar_row = row
	var icon := TextureRect.new(); icon.texture = UI.icon(id); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size = Vector2(21,21); icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(icon)
	caption = Label.new(); caption.text = "  "+title; caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL; caption.add_theme_font_size_override("font_size",13); caption.add_theme_color_override("font_color",UI.INK); caption.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(caption)
	caption.clip_text = true; caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if id == "browser":
		caption.custom_minimum_size.x=240; caption.size_flags_horizontal=Control.SIZE_FILL
		caption.add_theme_stylebox_override("normal",UI.style(Color("f7f9fc"),Color.TRANSPARENT,14,5,6))
		var tab_space:=Control.new(); tab_space.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(tab_space)
	for spec in [["−", "fidelity_minimize"],["□", "fidelity_maximize"],["×", "fidelity_close"]]:
		var b := Button.new(); b.text = spec[0]; b.tooltip_text = UI.copy(spec[1]); b.custom_minimum_size = Vector2(46,32); b.add_theme_font_size_override("font_size",18); b.flat = true; row.add_child(b)
		chrome_buttons.append(b)
		var button_style := StyleBoxFlat.new(); button_style.bg_color = Color.TRANSPARENT; button_style.set_corner_radius_all(2); b.add_theme_stylebox_override("normal",button_style)
		b.add_theme_color_override("font_color",UI.INK)
		if spec[0] == "−": b.pressed.connect(func(): hide(); minimized.emit(app_id))
		elif spec[0] == "□": b.pressed.connect(toggle_maximize)
		else: b.pressed.connect(func(): hide(); dismissed.emit(app_id))
	content = VBoxContainer.new(); content.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",0); layout.add_child(content)
	titlebar.gui_input.connect(_title_input)
	_connect_desktop_host()
	gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed: focused.emit(app_id))
	var grip := Control.new(); grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT); grip.offset_left = -18; grip.offset_top = -18; grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE; add_child(grip)
	grip.gui_input.connect(_resize_input)
	grip.draw.connect(func():
		grip.draw_line(Vector2(7,15),Vector2(15,7),Color("a2acb5"),1)
		grip.draw_line(Vector2(11,15),Vector2(15,11),Color("a2acb5"),1))
	title_drag_handle = Control.new(); title_drag_handle.name = "TitleDragHandle"; title_drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE; title_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(title_drag_handle)
	title_drag_handle.gui_input.connect(_title_input)
	titlebar.resized.connect(_sync_chrome_hit_region)
	titlebar_row.resized.connect(_sync_chrome_hit_region)
	resized.connect(_sync_chrome_hit_region)
	call_deferred("_sync_chrome_hit_region")

func _sync_chrome_hit_region() -> void:
	if not is_instance_valid(title_drag_handle) or not is_instance_valid(titlebar) or chrome_buttons.is_empty(): return
	var bar_rect := titlebar.get_global_rect()
	var first_button_rect := chrome_buttons[0].get_global_rect()
	var right_edge := maxf(0.0, first_button_rect.position.x - bar_rect.position.x - 2.0)
	var height := maxf(0.0, bar_rect.size.y - 6.0)
	title_drag_handle.global_position = Vector2(bar_rect.position.x + 2.0, bar_rect.position.y + 3.0)
	title_drag_handle.size = Vector2(right_edge, height)

func _title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			focused.emit(app_id)
			if event.double_click: toggle_maximize(); return
			_dragging = not maximized
			_origin = event.global_position; _initial = Rect2(position,size)
		else:
			if _dragging: _move_to(event.global_position)
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_move_to(event.global_position); accept_event()

func _resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			focused.emit(app_id); _resizing = not maximized
			_origin = event.global_position; _initial = Rect2(position,size)
		else:
			if _resizing: _resize_to(event.global_position)
			_resizing = false
		accept_event()
	elif event is InputEventMouseMotion and _resizing:
		_resize_to(event.global_position); accept_event()

func _move_to(point: Vector2) -> void:
	position = _initial.position + point - _origin; clamp_to_desktop()

func _resize_to(point: Vector2) -> void:
	if get_parent_control() == null: return
	var area := get_parent_control().size
	var available := Vector2(maxf(0.0, area.x - _initial.position.x), maxf(0.0, area.y - _initial.position.y))
	var minimum := Vector2(minf(custom_minimum_size.x, available.x), minf(custom_minimum_size.y, available.y))
	var requested := _initial.size + point - _origin
	size = Vector2(clampf(requested.x, minimum.x, available.x), clampf(requested.y, minimum.y, available.y))
	clamp_to_desktop()
	queue_redraw()

func clamp_to_desktop() -> void:
	if get_parent_control() == null: return
	var area := get_parent_control().size
	var bounded := _constrain_rect(Rect2(position, size), area)
	position = bounded.position
	size = bounded.size

func _constrain_rect(rect: Rect2, area: Vector2) -> Rect2:
	if area.x <= 0.0 or area.y <= 0.0: return rect
	var bounded_size := Vector2(
		clampf(rect.size.x, minf(custom_minimum_size.x, area.x), area.x),
		clampf(rect.size.y, minf(custom_minimum_size.y, area.y), area.y))
	var max_x := maxf(0.0, area.x - bounded_size.x)
	var max_y := maxf(0.0, area.y - bounded_size.y)
	var bounded_position := Vector2(clampf(rect.position.x, 0.0, max_x), clampf(rect.position.y, 0.0, max_y))
	return Rect2(bounded_position, bounded_size)

func _parent_resized() -> void:
	if get_parent_control() == null: return
	var area := get_parent_control().size
	if area.x <= 0.0 or area.y <= 0.0: return
	if maximized:
		restore_rect = _constrain_rect(restore_rect, area)
		position = Vector2.ZERO
		size = area
	else:
		var bounded := _constrain_rect(Rect2(position, size), area)
		position = bounded.position
		size = bounded.size
	call_deferred("_sync_chrome_hit_region")
	queue_redraw()

func toggle_maximize() -> void:
	if get_parent_control() == null: return
	_dragging = false; _resizing = false
	focused.emit(app_id)
	if maximized:
		var bounded_restore := _constrain_rect(restore_rect, get_parent_control().size)
		position = bounded_restore.position; size = bounded_restore.size
	else:
		restore_rect = _constrain_rect(Rect2(position,size), get_parent_control().size)
		position = Vector2.ZERO; size = get_parent_control().size
	maximized = not maximized
	chrome_buttons[1].text="❐" if maximized else "□"
	frame.set_corner_radius_all(0 if maximized else 7)
	call_deferred("_sync_chrome_hit_region")

func set_active(active: bool) -> void:
	# Keep the document readable in background windows; use the titlebar and border
	# as the focus indicator instead of washing out the whole application.
	modulate = Color.WHITE
	if is_instance_valid(caption):
		caption.text = "  " + title_text
		caption.add_theme_color_override("font_color", _chrome_ink(active))
	for button in chrome_buttons:
		if is_instance_valid(button):
			button.add_theme_stylebox_override("normal", UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 4, 2, 2))
			button.add_theme_stylebox_override("hover", UI.style(Color("c42b1c") if button==chrome_buttons[2] else Color("e0e7ee"), Color.TRANSPARENT, 4, 2, 0))
			button.add_theme_color_override("font_color", _chrome_ink(active))
			button.add_theme_color_override("font_hover_color", Color.WHITE if button==chrome_buttons[2] else UI.INK)
	if is_instance_valid(frame):
		frame.border_color = Color("9aabbc") if active else Color("cbd3db")
		frame.set_border_width_all(1)
		frame.set_corner_radius_all(0 if maximized else 7)
	if is_instance_valid(titlebar):
		titlebar.add_theme_stylebox_override("panel", UI.style(_chrome_color(active), Color.TRANSPARENT, 8, 0, 0))
	if chrome_buttons.size()>1: chrome_buttons[1].text="❐" if maximized else "□"
	if chrome_buttons.size()>1: chrome_buttons[1].tooltip_text=UI.copy("fidelity_restore" if maximized else "fidelity_maximize")
