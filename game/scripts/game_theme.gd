class_name GameTheme
extends RefCounted

# Palette sampled from the official Supermarket Simulator market reference:
# https://steamcommunity.com/games/2670630/announcements/detail/4704663339702080532

const TITLE := Color("00B2FD")
const TABBAR := Color("23DCFD")
const TAB := Color("1961AB")
const FILTER := Color("8DEEFD")
const CANVAS := Color("D8F8FD")
const CARD_FRAME := Color("214F6D")
const CARD := Color("18364C")
const ACTION := Color("1D375B")
const BUY := Color("00B61C")
const WHITE := Color("F9FDFD")
const FOOTER := Color("162C46")
const HEADER := TITLE
const TAB_BAR := TABBAR
const SUCCESS := BUY
const TEXT := WHITE
const MUTED := TAB
const WARNING := Color("FDDB32")
const DANGER := Color("FD062E")

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
	return surface(TAB if selected else ACTION, TABBAR if selected else Color.TRANSPARENT, 3, 8)

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

static func primary(button: Button, fill: Color = BUY) -> void:
	button.add_theme_stylebox_override("normal", action_style(fill))
	button.add_theme_stylebox_override("hover", action_style(WHITE))
	button.add_theme_stylebox_override("pressed", action_style(TAB))
	var normal_text := FOOTER if fill in [WHITE,WARNING,FILTER,CANVAS,TABBAR] else WHITE
	button.add_theme_color_override("font_color", normal_text)
	button.add_theme_color_override("font_focus_color", normal_text)
	button.add_theme_color_override("font_hover_color", FOOTER)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_stylebox_override("disabled", action_style(CARD_FRAME))
	button.add_theme_color_override("font_disabled_color", FILTER)

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
