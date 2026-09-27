class_name GameTheme
extends RefCounted

# Use navy reading surfaces, cyan navigation accents and green transactions.

const TITLE := Color("00B2FD")
const TABBAR := Color("56CCE8")
const TAB := Color("17628C")
const FILTER := Color("BBDDE9")
const CANVAS := Color("EDF3F7")
const CARD_FRAME := Color("426078")
const CARD := Color("1B3549")
const ACTION := Color("29475F")
const BUY := Color("16814A")
const WHITE := Color("F8FBFD")
const FOOTER := Color("142B3D")
const HEADER := TITLE
const TAB_BAR := TABBAR
const SUCCESS := BUY
const TEXT := WHITE
const MUTED := TAB
const WARNING := Color("FDDB32")
const DANGER := Color("B93449")
const LINE := Color("CAD8E2")

static func surface(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 8, margin: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

static func tab_style(selected: bool) -> StyleBoxFlat:
	var result := surface(ACTION if selected else FOOTER, Color.TRANSPARENT, 4, 8)
	result.border_color = TABBAR if selected else Color.TRANSPARENT
	result.border_width_bottom = 3
	result.anti_aliasing = false
	return result

static func action_style(fill: Color = ACTION) -> StyleBoxFlat:
	return surface(fill, CARD_FRAME, 4, 8)

static func style(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 8, margin: int = 10) -> StyleBoxFlat:
	return surface(fill, border, radius, margin)

static func navigation(button: Button, selected: bool = false) -> void:
	button.add_theme_stylebox_override("normal", tab_style(selected))
	button.add_theme_stylebox_override("hover", tab_style(true))
	button.add_theme_stylebox_override("pressed", tab_style(true))
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_focus_color", WHITE)
	button.add_theme_stylebox_override("focus", focus_style())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = button.text
	button.set_meta("navigation_selected", selected)

static func focus_style() -> StyleBoxFlat:
	var focus := surface(Color.TRANSPARENT, TABBAR, 4, 8)
	focus.set_border_width_all(2)
	return focus

static func primary(button: Button, fill: Color = BUY) -> void:
	button.add_theme_stylebox_override("normal", action_style(fill))
	button.add_theme_stylebox_override("hover", action_style(fill.lightened(0.10)))
	button.add_theme_stylebox_override("pressed", action_style(fill.darkened(0.12)))
	var normal_text := FOOTER if fill in [WHITE,WARNING,FILTER,CANVAS,TABBAR] else WHITE
	button.add_theme_color_override("font_color", normal_text)
	button.add_theme_color_override("font_focus_color", normal_text)
	button.add_theme_color_override("font_hover_color", normal_text)
	button.add_theme_color_override("font_pressed_color", normal_text)
	button.add_theme_stylebox_override("disabled", action_style(CARD_FRAME))
	button.add_theme_color_override("font_disabled_color", FILTER)
	button.add_theme_stylebox_override("focus", focus_style())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func theme(scale: float = 1.0) -> Theme:
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansJP.ttf")
	theme.default_font_size = int(16.0 * scale)
	theme.set_stylebox("normal", "Button", action_style(ACTION))
	theme.set_stylebox("hover", "Button", action_style(TAB))
	theme.set_stylebox("pressed", "Button", action_style(TAB))
	theme.set_color("font_color", "Button", WHITE)
	theme.set_color("font_hover_color", "Button", WHITE)
	theme.set_color("font_pressed_color", "Button", WHITE)
	return theme
