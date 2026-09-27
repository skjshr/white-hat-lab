class_name ManagementUI
extends RefCounted
## Quiet business surfaces. Native service applications keep their own themes.
const INK := Color("243940")
const MUTED := Color("64777B")
const PAPER := Color("FBFCF9")
const CANVAS := Color("EEF1EC")
const LINE := Color("D4DDDA")
const ACCENT := Color("247C72")
const SELECTED := Color("DFEDE6")
const DARK := Color("172D35")
const WHITE := Color("FAFCF9")
const DANGER := Color("B84639")
const WARNING := Color("93681E")

static func surface(fill: Color = PAPER, margin: int = 16, border: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = LINE
	style.set_border_width_all(1 if border else 0)
	style.set_corner_radius_all(4)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

static func rule() -> HSeparator:
	var separator := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = LINE
	style.thickness = 1
	separator.add_theme_stylebox_override("separator", style)
	return separator

static func button(node: Button, role: String = "secondary", selected: bool = false) -> void:
	var fill: Color = ACCENT if role == "primary" else SELECTED if selected else PAPER
	var ink: Color = WHITE if role == "primary" else ACCENT if selected else INK
	if role == "quiet" or role == "tab": fill = SELECTED if selected else Color.TRANSPARENT
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color: Color = fill
		if state == "hover": color = ACCENT.lightened(0.08) if role == "primary" else SELECTED
		if state == "pressed": color = ACCENT.darkened(0.10) if role == "primary" else SELECTED.darkened(0.03)
		if state == "disabled": color = CANVAS
		var style := surface(color, 10, role == "secondary")
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		if role == "tab":
			style.set_corner_radius_all(0)
			style.border_width_bottom = 2 if selected else 0
			style.border_color = ACCENT
		node.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, ink)
	node.add_theme_color_override("font_disabled_color", MUTED)
	var focus := surface(Color.TRANSPARENT, 8, true)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus", focus)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.set_meta("management_role", role)

static func field(node: Control) -> void:
	var normal := surface(PAPER, 8, true)
	node.add_theme_stylebox_override("normal", normal)
	var focus := surface(PAPER, 8, true)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus", focus)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("font_placeholder_color", MUTED)
	if node is SpinBox: field(node.get_line_edit())
	if node is OptionButton: button(node)

static func theme(scale: float) -> Theme:
	var result := Theme.new()
	result.default_font = preload("res://scripts/ui_theme.gd").font(500)
	result.default_font_size = roundi(15 * scale)
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", INK)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_color("font_disabled_color", "Button", MUTED)
	result.set_stylebox("normal", "Button", surface(PAPER, 8, true))
	result.set_stylebox("hover", "Button", surface(SELECTED, 8))
	result.set_stylebox("pressed", "Button", surface(SELECTED, 8))
	result.set_stylebox("normal", "LineEdit", surface(PAPER, 8, true))
	result.set_color("font_color", "LineEdit", INK)
	result.set_stylebox("background", "ProgressBar", surface(LINE, 0))
	result.set_stylebox("fill", "ProgressBar", surface(ACCENT, 0))
	return result
