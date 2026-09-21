extends Control
## State-derived coaching. Opening a location never performs the task itself.
const UI = preload("res://scripts/ui_theme.gd")
const GUIDE = preload("res://scripts/next_task_guide.gd")
var ui
var game
var task: Dictionary = {}
var card: PanelContainer
var title: Label
var body: Label
var hint: Label
var hint_scroll: ScrollContainer
var locate: Button
var details: Button
var toggle: Button
var expanded := false
var target_rect := Rect2()
var _highlight_seconds := 0.0
var _elapsed := 0.0
var _scale := -1.0
var _reserved: Control
var _original_top := 0.0
var _identity := ""

func setup(owner_ui) -> void:
	ui = owner_ui; game = ui._game(); name = "NextTaskGuide"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card = PanelContainer.new(); card.name = "NextTaskCard"; add_child(card)
	card.minimum_size_changed.connect(_fit_card.call_deferred)
	card.add_theme_stylebox_override("panel", UI.style(Color("f5faff"), UI.BORDER, 14, 7, 0))
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 3); card.add_child(box)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); box.add_child(row)
	title = Label.new(); title.name = "NextTaskTitle"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; title.add_theme_color_override("font_color", UI.PRIMARY); row.add_child(title)
	locate = _button("NextTaskLocate", UI.copy("guide_locate"), locate_task); row.add_child(locate)
	details = _button("NextTaskHint", UI.copy("next_hint"), toggle_hint); row.add_child(details)
	toggle = _button("NextTaskToggle", "", func(): set_enabled(not enabled())); row.add_child(toggle)
	body = Label.new(); body.name = "NextTaskBody"; body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(body)
	hint_scroll = ScrollContainer.new(); hint_scroll.name = "NextTaskHintScroll"; hint_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hint_scroll.custom_minimum_size.y = 84; box.add_child(hint_scroll)
	hint = Label.new(); hint.name = "NextTaskHintText"; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hint.add_theme_color_override("font_color", UI.MUTED); hint_scroll.add_child(hint)
	hide()

func _button(id: String, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.name = id; button.text = text; button.pressed.connect(callback)
	return button

func enabled() -> bool:
	return bool(game.state.get("next_task_guide_enabled", true))

func set_enabled(value: bool) -> bool:
	var existed: bool = game.state.has("next_task_guide_enabled")
	var previous: bool = enabled()
	game.state.next_task_guide_enabled = value
	if not game.save_game():
		if existed: game.state.next_task_guide_enabled = previous
		else: game.state.erase("next_task_guide_enabled")
		return false
	expanded = false; _highlight_seconds = 0.0; refresh(1.0)
	return true

func toggle_hint() -> void:
	expanded = not expanded
	refresh(1.0)

func _desktop():
	return ui.desktop if ui.current_kind == "terminal" and is_instance_valid(ui.desktop) else null

func refresh(delta := 0.2) -> void:
	if game == null or game.state.is_empty(): return
	_elapsed += delta; _highlight_seconds = maxf(0.0, _highlight_seconds - delta)
	if _elapsed < 0.2: return
	_elapsed = 0.0
	var intro: bool = is_instance_valid(ui.guided_intro) and ui.guided_intro.active()
	if ui.controls.menu.visible or intro or ui.current_kind not in ["", "terminal", "board", "sales", "shop"]:
		hide(); _reserve(null, 0); target_rect = Rect2(); queue_redraw(); return
	show()
	if _scale != float(ui.text_scale):
		_scale = float(ui.text_scale); theme = UI.make_theme(_scale)
		title.add_theme_font_size_override("font_size", int(15 * _scale))
		body.add_theme_font_size_override("font_size", int(13 * _scale))
		hint.add_theme_font_size_override("font_size", int(13 * _scale))
	var on := enabled()
	task = GUIDE.resolve(game) if on else {}
	var identity := str(task.get("id", "")) + str(task.get("probe_id", "")) + str(game.state.get("current_contract_id", "")) + str(game.state.get("target_index", 0)) + str(game.state.get("chapter", 0))
	if identity != _identity:
		expanded = false; _highlight_seconds = 0.0; hint_scroll.scroll_vertical = 0; _identity = identity
	title.text = UI.copy("next_task") + "  ·  " + str(task.get("title", "")) if on else UI.copy("next_guide")
	title.tooltip_text = title.text
	body.text = str(task.get("body", "")); body.visible = on and not body.text.is_empty()
	hint.text = str(task.get("hint", "")); hint_scroll.visible = on and expanded and not hint.text.is_empty()
	locate.visible = on; locate.disabled = str(task.get("route", "")).is_empty()
	details.visible = on and not hint.text.is_empty(); details.text = UI.copy("next_hide_hint" if expanded else "next_hint")
	toggle.text = UI.copy("next_hide" if on else "next_show")
	var bounds := get_viewport_rect().size
	card.size = Vector2(bounds.x, 0)
	card.position = Vector2.ZERO
	if ui.current_kind.is_empty():
		# Office input is captured. Keep this as a compact, non-blocking reminder.
		locate.hide(); details.hide(); toggle.hide(); hint_scroll.hide()
		card.size = Vector2(minf(420.0 * _scale, bounds.x - 32), 0)
		card.position = Vector2(bounds.x - card.size.x - 16, bounds.y - card.size.y - 54)
		card.visible = on
	else:
		toggle.show()
	var surface: Control = _desktop() if ui.current_kind == "terminal" else (ui.modal if ui.current_kind in ["board", "sales", "shop"] else null)
	_reserve(surface, card.size.y if visible else 0.0)
	_fit_card.call_deferred()
	target_rect = Rect2()
	if _highlight_seconds > 0:
		var target := _target_control()
		if target != null: target_rect = target.get_global_rect().intersection(get_viewport_rect())
	queue_redraw()

func _fit_card() -> void:
	if not visible or not is_instance_valid(card): return
	# Wrapped labels settle after their new width/theme is assigned. Use that
	# measured height before reserving board space, including the first frame.
	card.size.y = card.get_combined_minimum_size().y
	if ui.current_kind.is_empty():
		card.position.y = get_viewport_rect().size.y - card.size.y - 54
	else:
		var surface: Control = _desktop() if ui.current_kind == "terminal" else (ui.modal if ui.current_kind in ["board", "sales", "shop"] else null)
		_reserve(surface, card.size.y)

func _reserve(surface: Control, height: float) -> void:
	if _reserved != surface:
		if is_instance_valid(_reserved): _reserved.offset_top = _original_top
		_reserved = surface
		if is_instance_valid(surface): _original_top = surface.offset_top
	if is_instance_valid(surface) and not is_equal_approx(surface.offset_top, _original_top + height):
		surface.offset_top = _original_top + height

func _target_control() -> Control:
	var id := str(task.get("target", ""))
	if id.is_empty(): return null
	var node = ui.root.find_child(id, true, false)
	return node if node is Control and node.is_visible_in_tree() and not node.is_queued_for_deletion() else null

func locate_task() -> void:
	# Re-read at click time so a just-completed task cannot trigger stale navigation.
	task = GUIDE.resolve(game)
	var route := str(task.get("route", ""))
	if route.is_empty(): return
	if route == "board":
		var destination := "sales" if str(task.get("id", "")) == "board" else "board"
		if ui.current_kind != destination: ui.open_panel(destination)
	elif route == "shop":
		if ui.current_kind != "shop" or ui.shop_view != "stock":
			ui.shop_view = "stock"; ui.open_panel("shop")
	elif route == "office": ui.close_panel()
	else:
		if _desktop() == null: ui.open_panel("terminal")
		var desktop = _desktop()
		if desktop == null: return
		if task.has("target_index") and int(task.target_index) != int(game.state.get("target_index", 0)):
			if not desktop._select_target(int(task.target_index)): return
		var url := str(task.get("url", ""))
		if route == "browser" and not url.is_empty(): desktop.show_guide_service(url)
		else: desktop._show_app(route)
		if route == "editor" and not str(task.get("config_path", "")).is_empty(): desktop._open_editor(str(task.config_path))
		if route == "monitor" and str(task.get("id", "")) == "apply":
			desktop.widgets.monitor.tab = "overview"; desktop._refresh_monitor()
		if route == "verify" and not str(task.get("probe_id", "")).is_empty():
			desktop.widgets.verify.selected = str(task.probe_id)
			desktop.DIAGNOSTICS.refresh(desktop)
	var target := _target_control()
	if target != null:
		var ancestor: Node = target.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer: ancestor.ensure_control_visible(target)
			ancestor = ancestor.get_parent()
	_highlight_seconds = 5.0
	refresh(1.0)

func _draw() -> void:
	if target_rect.has_area():
		draw_rect(target_rect.grow(3), Color.WHITE, false, 5.0)
		draw_rect(target_rect.grow(3), UI.PRIMARY, false, 2.0)
