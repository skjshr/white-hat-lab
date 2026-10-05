extends RefCounted
## Shared visual language for the game and the fictional workstation.
const BG := Color("d4dddf")
const SURFACE := Color("e5e9e8")
const PAPER := Color("eef2f3")
const CHROME := Color("c5d1d5")
const INK := Color("223247")
const MUTED := Color("536476")
const PRIMARY := Color("1266c5")
const SELECTED := Color("dceeff")
const CYAN := Color("00b8e8")
const YELLOW := Color("ffd85a")
const GREEN := Color("247948")
const RED := Color("c44646")
const WARNING := Color("8c5b00")
const BORDER := Color("d5dfea")
## AOBA OS chrome tokens. Keep the document surfaces light while the shell
## uses the deep teal / ivory / yellow system from the approved ecosystem board.
const OS_SHELL := Color("233f46")
const OS_EDGE := Color("17343b")
const OS_IVORY := Color("f5f8f8")
const OS_PANEL := Color("f6f8fa")
const OS_NAV := Color("edf2f4")
const OS_SELECTED := Color("d9eeea")
const OS_BORDER := Color("d6dfe4")
const OS_ACCENT := Color("246b72")
const OS_YELLOW := Color("ffd65b")
const OS_SEAFOAM := Color("72c3b4")
const FONT = preload("res://assets/fonts/NotoSansJP.ttf")
static var _copy: Dictionary = {}

static func copy(key: String, fallback: String = "") -> String:
	if _copy.is_empty():
		for path in ["res://content/ui_copy_v17.json", "res://content/ui_copy_v18.json", "res://content/ui_copy_v19.json", "res://content/ui_copy_v110.json", "res://content/ui_copy_v114.json", "res://content/ui_copy_v115.json", "res://content/ui_copy_v116.json", "res://content/ui_copy_v117.json", "res://content/ui_copy_v118.json", "res://content/ui_copy_v119.json", "res://content/ui_copy_v120.json", "res://content/ui_copy_v121.json", "res://content/ui_copy_v122.json", "res://content/ui_copy_v123.json", "res://content/ui_copy_v124.json", "res://content/ui_copy_operations.json", "res://content/ui_copy_experience.json", "res://content/ui_copy_backup.json", "res://content/ui_copy_service_clone.json", "res://content/ui_copy_samba.json", "res://content/ui_copy_market.json", "res://content/ui_copy_linked_identity.json", "res://content/ui_copy_stock.json", "res://content/ui_copy_business.json", "res://content/ui_copy_billing.json", "res://content/ui_copy_remediation.json", "res://content/ui_copy_fidelity.json", "res://content/ui_copy_branch.json", "res://content/ui_copy_dispatch.json", "res://content/ui_copy_versions.json", "res://content/ui_copy_identity_admin.json", "res://content/ui_copy_stock_catalog.json", "res://content/ui_copy_backup_restore.json", "res://content/ui_copy_workload.json", "res://content/ui_copy_comparison.json", "res://content/ui_copy_board.json", "res://content/ui_copy_guide.json", "res://content/ui_copy_receipt.json", "res://content/ui_copy_firm.json", "res://content/ui_copy_advanced.json", "res://content/ui_copy_next_task.json", "res://content/ui_copy_v220.json", "res://content/ui_copy_realism.json"]:
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null: continue
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				var entries: Dictionary = parsed.get("entries", parsed.get("copy", {}))
				for entry_key in entries: _copy[str(entry_key)] = str(entries[entry_key])
	return str(_copy.get(key, fallback))

static func style(bg: Color, border := Color.TRANSPARENT, x := 12, y := 8, radius := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border; s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = x; s.content_margin_right = x
	s.content_margin_top = y; s.content_margin_bottom = y
	return s

static func font(weight := 400) -> FontVariation:
	var f := FontVariation.new(); f.base_font = FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):weight}
	return f

static func make_theme(scale := 1.0, game := false) -> Theme:
	var t := Theme.new(); t.default_font = font(); t.default_font_size = int((17 if game else 14) * scale)
	for kind in ["Button","OptionButton","MenuButton","LineEdit"]:
		t.set_stylebox("normal",kind,style(SURFACE,BORDER if game or kind == "LineEdit" else Color.TRANSPARENT,12 if game else 8,7 if game else 5))
		t.set_stylebox("hover",kind,style(BG,PRIMARY,12 if game else 8,7 if game else 5))
		t.set_stylebox("pressed",kind,style(SELECTED,PRIMARY,12 if game else 8,7 if game else 5))
		var focus := style(Color.TRANSPARENT,PRIMARY,12 if game else 8,7 if game else 5); focus.set_border_width_all(2)
		t.set_stylebox("focus",kind,focus)
		t.set_stylebox("disabled",kind,style(BG,BORDER,12 if game else 8,7 if game else 5))
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: t.set_color(key,kind,INK)
		t.set_color("font_disabled_color",kind,MUTED)
	t.set_color("font_color","Label",INK)
	t.set_color("font_placeholder_color","LineEdit",MUTED)
	t.set_color("caret_color","LineEdit",INK)
	t.set_color("selection_color","LineEdit",SELECTED)
	t.set_color("font_selected_color","LineEdit",INK)
	t.set_stylebox("panel","PanelContainer",style(SURFACE,BORDER,14,12))
	t.set_stylebox("panel","PopupMenu",style(SURFACE,BORDER,8,8))
	t.set_stylebox("hover","PopupMenu",style(SELECTED,Color.TRANSPARENT,8,6))
	t.set_color("font_color","PopupMenu",INK); t.set_color("font_hover_color","PopupMenu",INK)
	t.set_stylebox("panel","ItemList",style(SURFACE,BORDER,4,4))
	t.set_stylebox("selected","ItemList",style(SELECTED,Color.TRANSPARENT,6,5))
	t.set_stylebox("selected_focus","ItemList",style(SELECTED,PRIMARY,6,5))
	t.set_color("font_color","ItemList",INK); t.set_color("font_selected_color","ItemList",INK)
	t.set_stylebox("panel","Tree",style(SURFACE,BORDER,4,4))
	t.set_stylebox("selected","Tree",style(SELECTED,Color.TRANSPARENT,4,4)); t.set_stylebox("selected_focus","Tree",style(SELECTED,PRIMARY,4,4))
	t.set_stylebox("title_button_normal","Tree",style(BG,BORDER,8,7)); t.set_stylebox("title_button_hover","Tree",style(SELECTED,BORDER,8,7)); t.set_stylebox("title_button_pressed","Tree",style(SELECTED,PRIMARY,8,7))
	for key in ["font_color","font_selected_color","title_button_color"]: t.set_color(key,"Tree",INK)
	t.set_constant("v_separation","Tree",10)
	t.set_stylebox("background","ProgressBar",style(BORDER,Color.TRANSPARENT,0,0))
	t.set_stylebox("fill","ProgressBar",style(PRIMARY,Color.TRANSPARENT,0,0))
	for kind in ["VScrollBar","HScrollBar"]:
		t.set_stylebox("scroll",kind,style(BG,Color.TRANSPARENT,4,4))
		t.set_stylebox("grabber",kind,style(Color("a8b9cd"),Color.TRANSPARENT,4,4))
		t.set_stylebox("grabber_highlight",kind,style(PRIMARY,Color.TRANSPARENT,4,4))
	if not game: _desktop_theme(t)
	return t

static func _desktop_theme(t: Theme) -> void:
	for kind in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new(); line.color = OS_BORDER; line.thickness = 1; line.vertical = kind == "VSeparator"
		t.set_stylebox("separator", kind, line)
	for kind in ["Button", "OptionButton", "MenuButton", "LineEdit"]:
		t.set_stylebox("normal",kind,style(OS_PANEL,Color.TRANSPARENT if kind == "MenuButton" else OS_BORDER,8,5,3))
		t.set_stylebox("hover",kind,style(OS_NAV,OS_BORDER,8,5,3))
		t.set_stylebox("pressed",kind,style(OS_SELECTED,OS_ACCENT,8,5,3))
		t.set_stylebox("disabled",kind,style(OS_PANEL,Color.TRANSPARENT,8,5,3))
		t.set_stylebox("focus",kind,style(Color.TRANSPARENT,OS_ACCENT,8,5,3))
	t.set_stylebox("panel","PanelContainer",style(OS_PANEL,OS_BORDER,12,10,3))
	t.set_stylebox("panel","PopupMenu",style(OS_PANEL,OS_BORDER,8,7,3))
	t.set_stylebox("hover","PopupMenu",style(OS_SELECTED,Color.TRANSPARENT,8,5,2))
	for kind in ["Tree","ItemList"]:
		t.set_stylebox("panel",kind,style(Color.WHITE,Color.TRANSPARENT,4,4,0))
		t.set_stylebox("selected",kind,style(OS_SELECTED,Color.TRANSPARENT,5,4,0))
		t.set_stylebox("selected_focus",kind,style(OS_SELECTED,OS_ACCENT,5,4,0))
		t.set_color("font_color",kind,INK); t.set_color("font_selected_color",kind,INK)
	for kind in ["normal","hover","pressed"]:
		t.set_stylebox("title_button_"+kind,"Tree",style(OS_NAV,Color.TRANSPARENT,8,6,0))
	t.set_constant("v_separation","Tree",8)
	t.set_stylebox("tab_selected","TabBar",style(Color.WHITE,OS_BORDER,12,7,0))
	t.set_stylebox("tab_unselected","TabBar",style(OS_NAV,Color.TRANSPARENT,12,7,0))
	t.set_stylebox("tab_hovered","TabBar",style(OS_SELECTED,Color.TRANSPARENT,12,7,0))
	t.set_color("font_selected_color","TabBar",INK); t.set_color("font_unselected_color","TabBar",MUTED)
	for kind in ["VScrollBar","HScrollBar"]:
		t.set_stylebox("scroll",kind,style(OS_PANEL,Color.TRANSPARENT,3,3,0))
		t.set_stylebox("grabber",kind,style(Color("b9c7ce"),Color.TRANSPARENT,3,3,3))
		t.set_stylebox("grabber_highlight",kind,style(Color("8cabb4"),Color.TRANSPARENT,3,3,3))

static func app_accent(id: String) -> Color:
	return Color({"mail":"0f6cbd", "files":"0067c0", "editor":"007acc", "terminal":"cccccc", "browser":"357bb8", "monitor":"315b91", "verify":"7556ad", "team":"b46675", "receipt":"386f91", "manual":"607086"}.get(id,"246b72"))

static func app_tint(id: String) -> Color:
	return app_accent(id).lerp(Color.WHITE, 0.90)

static func app_background(id: String) -> Color:
	return Color("1e1e1e") if id in ["editor", "terminal"] else Color("f3f3f3")

static func app_theme(id: String, scale: float) -> Theme:
	var t := make_theme(scale)
	var native_font := SystemFont.new(); native_font.font_names = ["Segoe UI", "Yu Gothic UI"]; native_font.fallbacks = [font()]
	t.default_font = native_font
	var accent := app_accent(id)
	var tint := app_tint(id)
	var dark := id in ["editor", "terminal"]
	var ink := Color("cccccc") if dark else Color("242424")
	var surface := Color("1e1e1e") if dark else Color.WHITE
	var nav := Color("252526") if dark else Color("f3f3f3")
	for kind in ["Button", "MenuButton", "OptionButton", "LineEdit"]:
		t.set_stylebox("normal", kind, style(surface,Color.TRANSPARENT if kind == "MenuButton" else (Color("3c3c3c") if dark else Color("d1d1d1")),8,5,3))
		t.set_stylebox("hover",kind,style(nav,accent,8,5,3))
		t.set_stylebox("pressed",kind,style(nav,accent,8,5,3))
		t.set_stylebox("focus",kind,style(Color.TRANSPARENT,accent,8,5,3))
		t.set_stylebox("disabled",kind,style(surface,Color.TRANSPARENT,8,5,3))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: t.set_color(key,kind,ink)
		t.set_color("font_disabled_color",kind,Color("788497") if dark else MUTED)
	for kind in ["Tree", "ItemList"]:
		t.set_stylebox("selected",kind,style(tint,Color.TRANSPARENT,4,4,0))
		t.set_stylebox("selected_focus",kind,style(tint,accent,4,4,0))
	t.set_stylebox("fill","ProgressBar",style(accent,Color.TRANSPARENT,0,0))
	if dark:
		t.set_stylebox("panel","PopupMenu",style(surface,Color("3b4353"),8,7,3))
		t.set_stylebox("hover","PopupMenu",style(nav,accent,8,5,3))
		t.set_color("font_color","PopupMenu",ink); t.set_color("font_hover_color","PopupMenu",ink)
	return t

static func os_primary(button: Button, accent: Color = OS_ACCENT) -> void:
	for key in ["normal","hover","pressed"]:
		button.add_theme_stylebox_override(key,style(accent if key == "normal" else accent.darkened(0.08),Color.TRANSPARENT,12,6,3))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(key,Color.WHITE)

static func os_navigation(button: Button, active: bool, accent: Color = OS_ACCENT) -> void:
	var tint := accent.lerp(Color.WHITE, 0.85)
	var selected := style(tint if active else accent.lerp(Color.WHITE,0.95),Color.TRANSPARENT,10,7,2)
	if active: selected.border_color=accent; selected.border_width_left=3
	button.add_theme_stylebox_override("normal",selected)
	button.add_theme_stylebox_override("hover",style(tint,Color.TRANSPARENT,10,7,2))
	button.add_theme_color_override("font_color",INK)
	button.add_theme_color_override("font_hover_color",INK)

static var _icons: Dictionary = {}
static var _symbols: Dictionary = {}
static var _atlas: Texture2D
const ICON_ORDER := ["mail","files","terminal","editor","browser","monitor","verify","team","manual","receipt"]

static func icon(id: String) -> Texture2D:
	if _icons.has(id): return _icons[id]
	if _atlas == null and ResourceLoader.exists("res://assets/ui/app-icons-v17.png"):
		_atlas = load("res://assets/ui/app-icons-v17.png")
	if _atlas != null and id in ICON_ORDER:
		var index := ICON_ORDER.find(id)
		var cell := Vector2(_atlas.get_width()/5.0,_atlas.get_height()/2.0)
		var texture := AtlasTexture.new(); texture.atlas = _atlas
		texture.region = Rect2(Vector2(index%5,index/5)*cell,cell); texture.filter_clip=true
		_icons[id]=texture
	else:
		_icons[id]=load("res://assets/ui/"+id+".svg") if ResourceLoader.exists("res://assets/ui/"+id+".svg") else symbol("file")
	return _icons[id]

static func symbol(id: String) -> Texture2D:
	if _symbols.has(id): return _symbols[id]
	var paths := {
		"back":"<path d='M13 5l-7 7 7 7M6 12h14'/>",
		"forward":"<path d='M11 5l7 7-7 7M18 12H4'/>",
		"up":"<path d='M5 13l7-7 7 7M12 6v14'/>",
		"refresh":"<path d='M20 10a8 8 0 1 0-2 8M20 4v6h-6'/>",
		"search":"<circle cx='10' cy='10' r='6'/><path d='M15 15l6 6'/>",
		"menu":"<path d='M4 6h16M4 12h16M4 18h16'/>",
		"close":"<path d='M6 6l12 12M6 18L18 6'/>",
		"check":"<path d='M4 12l5 5L20 6'/>",
		"plus":"<path d='M12 4v16M4 12h16'/>",
		"folder":"<path d='M3 6h7l2 3h9v11H3z'/>",
		"file":"<path d='M5 3h9l5 5v13H5zM14 3v6h5M8 13h8M8 17h6'/>",
		"save":"<path d='M4 3h14l3 3v15H3V3zM7 3v6h10V3M7 21v-8h10v8'/>",
		"play":"<path d='M7 4l13 8-13 8z'/>",
		"stop":"<rect x='5' y='5' width='14' height='14' rx='1'/>",
		"link":"<path d='M10 14l4-4M8 16l-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0M16 8l1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0' transform='translate(1 -1) scale(.92)'/>",
		"settings":"<path d='M4 6h16M4 12h16M4 18h16M8 3v6M16 9v6M9 15v6'/>",
		"inbox":"<path d='M5 4h14l3 11v5H2v-5zM2 15h6l2 3h4l2-3h6'/>",
		"archive":"<path d='M3 3h18v5H3zM5 8v13h14V8M9 12h6'/>",
		"reply":"<path d='M9 5l-7 6 7 6v-5c7 0 10 2 13 7-1-8-5-11-13-11z'/>",
		"attachment":"<path d='M8 14l7-7a3 3 0 0 1 4 4l-9 9a5 5 0 0 1-7-7L13 3a4 4 0 0 1 6 0'/>",
		"grid":"<rect x='3' y='3' width='6' height='6' rx='1'/><rect x='15' y='3' width='6' height='6' rx='1'/><rect x='3' y='15' width='6' height='6' rx='1'/><rect x='15' y='15' width='6' height='6' rx='1'/>",
		"person":"<circle cx='12' cy='8' r='4'/><path d='M4 21c0-5 3-8 8-8s8 3 8 8'/>",
		"clock":"<circle cx='12' cy='12' r='9'/><path d='M12 7v6l4 2'/>",
		"money":"<rect x='3' y='6' width='18' height='13' rx='2'/><path d='M7 10h10M7 15h10M12 8v9'/>",
		"chart":"<path d='M4 20V10M10 20V4M16 20v-7M22 20V7'/>",
		"briefcase":"<rect x='3' y='7' width='18' height='13' rx='2'/><path d='M9 7V4h6v3M3 12h18M10 12v2h4v-2'/>",
		"help":"<circle cx='12' cy='12' r='9'/><path d='M9 8a3 3 0 0 1 6 1c0 2-3 2-3 5M12 17v.2'/>",
		"chevron":"<path d='M9 5l7 7-7 7'/>",
		"external":"<path d='M14 3h7v7M21 3L10 14M11 5H4v16h16v-7'/>",
		"code":"<path d='M7 6l-6 6 6 6M17 6l6 6-6 6M14 3l-4 18'/>",
		"copy":"<rect x='8' y='8' width='13' height='13' rx='2'/><path d='M5 16H3V3h13v2'/>",
		"more":"<circle cx='5' cy='12' r='1'/><circle cx='12' cy='12' r='1'/><circle cx='19' cy='12' r='1'/>"
	}
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><g fill='none' stroke='#344b5b' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>"+str(paths.get(id,paths.file))+"</g></svg>"
	var image := Image.new(); image.load_svg_from_string(svg,1.0)
	_symbols[id]=ImageTexture.create_from_image(image)
	return _symbols[id]

static func primary(button: Button, variant := "blue") -> void:
	var color := YELLOW if variant == "yellow" else (CYAN if variant == "cyan" else PRIMARY)
	var ink := INK if variant in ["yellow","cyan"] else Color.WHITE
	for key in ["normal","hover","pressed"]:
		button.add_theme_stylebox_override(key,style(color if key == "normal" else color.darkened(0.08 if key == "hover" else 0.15),Color.TRANSPARENT))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(key,ink)

static func navigation(button: Button, active: bool) -> void:
	button.add_theme_stylebox_override("normal",style(SELECTED if active else SURFACE,PRIMARY if active else BORDER,12,8))
	button.add_theme_stylebox_override("hover",style(SELECTED,Color.TRANSPARENT,12,8))
	button.add_theme_color_override("font_color",PRIMARY if active else INK)
	button.add_theme_color_override("font_hover_color",PRIMARY)

static func shell_navigation(button: Button, active: bool, active_color: Color = OS_SEAFOAM) -> void:
	# Shell navigation is deliberately explicit because the project theme is
	# refreshed when a desktop is rebuilt.  A button's flat flag also suppresses
	# its normal style, so callers that need a visible selected state turn it off.
	var normal := active_color if active else OS_SHELL
	var hover := OS_SEAFOAM if not active else active_color.darkened(0.06)
	button.add_theme_stylebox_override("normal",style(normal,OS_EDGE if active else Color.TRANSPARENT,10,7,2))
	button.add_theme_stylebox_override("hover",style(hover,OS_EDGE,10,7,2))
	button.add_theme_stylebox_override("pressed",style(active_color.darkened(0.12),OS_EDGE,10,7,2))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(key,INK if active else OS_IVORY)
