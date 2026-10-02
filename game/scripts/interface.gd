extends CanvasLayer
const UI = preload("res://scripts/ui_theme.gd")
const EQUIPMENT_PANEL = preload("res://scripts/equipment_panel.gd")
const OPERATIONS_PANEL = preload("res://scripts/operations_panel.gd")
const SALES_PANEL = preload("res://scripts/sales_panel.gd")
const PROCUREMENT_PANEL = preload("res://scripts/procurement_panel.gd")
const GAME_THEME = preload("res://scripts/game_theme.gd")
const M = preload("res://scripts/management_ui.gd")
## White Hat Lab interface. All learner-facing narrative is read from Game.copy.

class CoffeeCup extends Control:

	var phase := "idle"
	var progress := 0.0

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y * 0.6)
		var ceramic := Color("d7e6dc")
		_fill_oval(center+Vector2(0,40),Vector2(76,12),Color("bdc9c0"))
		draw_arc(center+Vector2(50,0),23.0,-PI*0.5,PI*0.5,28,ceramic,9.0,true)
		_fill_oval(center+Vector2(0,23),Vector2(52,13),ceramic)
		draw_rect(Rect2(center-Vector2(52,25),Vector2(104,49)),ceramic)
		_fill_oval(center-Vector2(0,25),Vector2(52,13),Color("ded8cc"))
		if phase in ["ready","brewing"]:
			_fill_oval(center-Vector2(0,25),Vector2(46,9),Color("744932"))
		draw_rect(Rect2(center-Vector2(18,4),Vector2(36,15)),Color("3d8278"))
		if phase in ["brewing","ready"]:
			for x in [-22.0,0.0,22.0]:
				var points := PackedVector2Array()
				for i in 12:
					points.append(center+Vector2(x+sin(float(i)*0.6+progress*4.0)*4.0,-44.0-float(i)*2.2))
				draw_polyline(points,Color("7e918a"),2.0,true)

	func _fill_oval(center: Vector2, radius: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for i in 32:
			var angle := TAU * float(i) / 32.0
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_colored_polygon(points, color)

signal closed
signal started
signal desktop_preview_ready(texture: Texture2D)
signal quit_requested

const BG := UI.BG
const SURFACE := UI.SURFACE
const SURFACE_2 := UI.CHROME
const INK := GAME_THEME.FOOTER
const MUTED := GAME_THEME.TAB
const TEAL := GAME_THEME.TAB
const ORANGE := GAME_THEME.WARNING
const RED := Color("c44646")
const CYAN := Color("00b8e8")
const GREEN := Color("247948")
const WARNING := Color("8c5b00")
const BORDER := Color("d5dfea")
const MANAGEMENT_NAV := Color("17494a")
const MANAGEMENT_SURFACE := Color("eef2f3")
const MANAGEMENT_CHROME := Color("d9e2e4")
const MANAGEMENT_SELECTED := Color("7bc7bd")
const MANAGEMENT_PRIMARY := Color("ffd457")
const TUTORIAL_PAGES := [
	{
		"id":"office","tab":"移動・操作","eyebrow":"OFFICE BASICS","title":"まず、自分の席へ",
		"body":"オフィスを歩き、目の前の物を操作します。照準を合わせると、左下にできる操作が表示されます。",
		"keys":[["W A S D","移動"],["マウス","視点"],["Shift","早歩き"],["E","操作"]],
		"steps":["室内を歩く","自席を見つける","EでPCを使う"],
		"note":"迷ったら左下の操作表示を確認。Escでいつでも中断できます。"
	},
	{
		"id":"contract","tab":"案件受付","eyebrow":"FIRST JOB","title":"依頼を選び、仕事を始める",
		"body":"案件ボードで依頼内容、報酬、経費、納期を確認します。受注後は同じ画面から対象PCを開けます。",
		"keys":[["Tab","案件一覧"],["F","自席PC"],["E","決定"],["Esc","戻る"]],
		"steps":["案件を見る","条件を比べる","見積を送る","対象PCを開く"],
		"note":"最初は短い案件で、調査から納品までの一周を覚えます。"
	},
	{
		"id":"workstation","tab":"業務PC","eyebrow":"OUTWATCH + AOBA OS","title":"Outwatchから作業を始める",
		"body":"Outwatchで依頼を読み、顧客端末へ接続します。ファイル、エディタ、ターミナル、サービス管理を切り替えて作業します。",
		"keys":[["Alt + Tab","アプリ切替"],["Ctrl + S","保存"],["Enter","コマンド実行"],["Esc","PCを閉じる"]],
		"steps":["メールを読む","顧客へ接続","設定を調べる","作業メモを残す"],
		"note":"自席PCの文書と顧客端末のファイルは別です。保存先を確認します。"
	},
	{
		"id":"repair","tab":"設定作業","eyebrow":"INSPECT → REPAIR","title":"調べてから、直す",
		"body":"設定ファイルとログを確認し、必要な箇所だけを変更します。保存した設定はサービスへ反映して、稼働状態を確認します。",
		"keys":[["help","使える操作"],["cat","内容を確認"],["Ctrl + S","設定を保存"],["systemctl","設定を反映"]],
		"steps":["現状を観察","原因を絞る","必要箇所を修正","サービスへ反映"],
		"note":"変更前の記録を残すと、失敗時に戻せて納品評価にも反映されます。"
	},
	{
		"id":"verify","tab":"検証・納品","eyebrow":"PROVE THE FIX","title":"直ったことを測ってから納品",
		"body":"設定しただけでは完了しません。必要な操作が成功し、不要なアクセスが拒否されることを診断ラボで確認します。",
		"keys":[["診断ラボ","検査を実行"],["サービス管理","稼働を確認"],["納品・精算","結果を報告"],["Tab","案件へ戻る"]],
		"steps":["正常操作を測る","拒否操作を測る","納品条件を確認","報告して精算"],
		"note":"設定やデータを変えた後は、古い検証結果を使わず再検証します。"
	},
	{
		"id":"business","tab":"会社運営","eyebrow":"GROW THE COMPANY","title":"利益を次の仕事へ戻す",
		"body":"納品で得た利益と信用を、スキル、設備、仲間へ投資します。設備は案件の解放ではなく、実際の作業時間を短くします。",
		"keys":[["1","調査を依頼"],["2","復元を依頼"],["3","設備購入"],["4","会社・スキル"]],
		"steps":["納品する","利益を確認","設備を受け取る","次の案件を選ぶ"],
		"note":"同僚へ任せても、設定の判断、再測定、納品はプレイヤーが担当します。"
	}
]

var root: Control
var content: Control
var modal: PanelContainer
var modal_body: VBoxContainer
var modal_footer: HBoxContainer
var modal_scroll: ScrollContainer
var hud: Control
var prompt: Label
var title_label: Label
var status_label: Label
var current_kind := ""
var settings_return_kind := ""
var desktop_return_kind := ""
var desktop_return_scroll: Dictionary = {}
var text_scale := 1.0
var controls: Dictionary = {}
var pending_settings: Dictionary = {}
var previous_settings: Dictionary = {}
var preview_seconds := 0.0
var setting_options: Dictionary = {}
var desktop: Control
var _desktop_preview_drawn := false
var modal_shade: ColorRect
var heading_font: Font
var board_filter := "all"
var board_available := true
var board_page := 0
var board_selected_id := ""
var sales_view := "inquiries"
var sales_stage := "all"
var sales_expanded_id := ""
var sales_search := ""
var pricing_drafts: Dictionary = {}
var sales_quote_drafts: Dictionary = {}
var shop_view := "equipment"
var operations_choices: Dictionary = {}
var menu_sound: AudioStreamPlayer
var settings_category := "video"
var profile_inputs: Dictionary = {}
var creating_company := false
var _maintenance_ui_signature := ""
var _operating_ui_signature := ""
var _maintenance_progress_labels: Dictionary = {}
var coffee_phase := "idle"
var coffee_elapsed := 0.0
var coffee_progress: ProgressBar
var coffee_status: Label
var coffee_action: Button
var coffee_cup: CoffeeCup
var management_rail: VBoxContainer
var tutorial_page := 0
var guided_intro: Control
var next_task_guide: Control
func _process(delta: float) -> void:
	if is_instance_valid(guided_intro): guided_intro.refresh(delta)
	if is_instance_valid(next_task_guide): next_task_guide.refresh(delta)
	if not previous_settings.is_empty():
		preview_seconds -= delta
		if controls.has("countdown") and is_instance_valid(controls.countdown): controls.countdown.text = "%s　残り%d秒" % [_copy_short("opt_revert_timer","設定を維持しますか？",24), ceili(preview_seconds)]
		if preview_seconds <= 0: _revert_settings()
	if coffee_phase == "brewing":
		coffee_elapsed = minf(2.0, coffee_elapsed + delta)
		if is_instance_valid(coffee_progress): coffee_progress.value = coffee_elapsed / 2.0 * 100.0
		if is_instance_valid(coffee_cup): coffee_cup.progress=coffee_elapsed/2.0; coffee_cup.queue_redraw()
		if coffee_elapsed >= 2.0:
			coffee_phase = "ready"
			if is_instance_valid(coffee_cup): coffee_cup.phase = coffee_phase; coffee_cup.progress = 1.0; coffee_cup.queue_redraw()
			if is_instance_valid(coffee_status): coffee_status.text = UI.copy("coffee_ready","コーヒーが淹れ上がりました")
			if is_instance_valid(coffee_action): coffee_action.text = UI.copy("coffee_drink","飲む"); coffee_action.disabled = false

func _ready() -> void:
	var initial_game := _game()
	if initial_game != null and initial_game.settings.has("text_scale"):
		text_scale = float(initial_game.settings.text_scale)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	menu_sound = AudioStreamPlayer.new(); menu_sound.stream = load("res://assets/audio/click_001.ogg"); menu_sound.volume_db = -15; add_child(menu_sound)
	_build_theme()
	_build_hud()
	_build_main_menu()
	var guide_layer := CanvasLayer.new(); guide_layer.layer = layer + 2; add_child(guide_layer)
	guided_intro = load("res://scripts/guided_tutorial.gd").new(); guide_layer.add_child(guided_intro); guided_intro.setup(self)
	next_task_guide = load("res://scripts/next_task_panel.gd").new(); guide_layer.add_child(next_task_guide); next_task_guide.setup(self)
	root.resized.connect(_layout_main_menu)
	root.resized.connect(_layout_management)
	_layout_main_menu.call_deferred()
	_sync_office_clock_pause()
	if _game() != null and _game().has_signal("changed"):
		_game().changed.connect(_on_game_changed)
	update_hud()

func _game() -> Node:
	return get_node_or_null("/root/Game")

func _sync_office_clock_pause() -> void:
	var g := _game()
	if g == null or not g.has_method("set_office_clock_paused"): return
	var title_visible: bool = controls.has("menu") and is_instance_valid(controls.menu) and controls.menu.visible
	g.set_office_clock_paused(title_visible or current_kind in ["pause", "settings", "confirm_display"])
	var sound := get_node_or_null("/root/Soundscape")
	if sound != null:
		sound.set_title_active(title_visible)
		sound.set_paused(current_kind in ["pause", "confirm_display", "ending"])

func _copy_short(key: String, fallback: String, limit: int) -> String:
	var value := UI.copy(key,fallback)
	return value if value.length() <= limit else fallback

func _build_theme() -> void:
	var theme := UI.make_theme(text_scale,true)
	var font := FontVariation.new(); font.base_font = load("res://assets/fonts/NotoSansJP.ttf"); font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500}
	var heavy := FontVariation.new(); heavy.base_font = font.base_font; heavy.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):700}; heading_font = load("res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf") if ResourceLoader.exists("res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf") else heavy
	theme.default_font = font; theme.default_font_size = maxi(14, int(18 * text_scale))
	var normal := GAME_THEME.action_style()
	var hover := GAME_THEME.action_style(GAME_THEME.TAB)
	var pressed := GAME_THEME.action_style(GAME_THEME.TAB)
	var disabled := GAME_THEME.action_style(GAME_THEME.FILTER)
	var focus := _surface(Color.TRANSPARENT,GAME_THEME.WARNING,12,8); focus.set_border_width_all(2)
	for kind in ["Button","OptionButton"]:
		theme.set_stylebox("normal",kind,normal); theme.set_stylebox("hover",kind,hover); theme.set_stylebox("pressed",kind,pressed); theme.set_stylebox("focus",kind,focus); theme.set_stylebox("disabled",kind,disabled)
		for state_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: theme.set_color(state_name,kind,GAME_THEME.WHITE)
		theme.set_color("font_disabled_color",kind,GAME_THEME.TAB)
	theme.set_stylebox("normal","LineEdit",GAME_THEME.surface(GAME_THEME.WHITE,GAME_THEME.TAB,4,8)); theme.set_stylebox("focus","LineEdit",focus); theme.set_color("font_color","LineEdit",INK)
	theme.set_stylebox("panel","PanelContainer",_surface(SURFACE,BORDER,16,14))
	theme.set_stylebox("panel","PopupMenu",GAME_THEME.surface(GAME_THEME.ACTION,GAME_THEME.CARD_FRAME,4,8)); theme.set_stylebox("hover","PopupMenu",hover); theme.set_color("font_color","PopupMenu",GAME_THEME.WHITE); theme.set_color("font_hover_color","PopupMenu",GAME_THEME.WHITE)
	theme.set_color("font_color","Label",INK); theme.set_color("font_color","CheckButton",INK); theme.set_color("font_hover_color","CheckButton",INK); theme.set_color("font_pressed_color","CheckButton",INK); theme.set_color("font_focus_color","CheckButton",INK)
	theme.set_color("font_placeholder_color","LineEdit",MUTED)
	theme.set_stylebox("background","ProgressBar",_surface(GAME_THEME.CARD_FRAME,Color.TRANSPARENT,0,0)); theme.set_stylebox("fill","ProgressBar",_surface(GAME_THEME.BUY,Color.TRANSPARENT,0,0))
	for kind in ["VScrollBar","HScrollBar"]:
		theme.set_stylebox("scroll",kind,_surface(Color("e8eef5"),Color.TRANSPARENT,4,4)); theme.set_stylebox("grabber",kind,_surface(Color("9fb6c9"),Color.TRANSPARENT,4,4)); theme.set_stylebox("grabber_highlight",kind,_surface(TEAL,Color.TRANSPARENT,4,4))
	root.theme = theme

func _surface(fill: Color, border: Color, x: int, y: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = fill; style.border_color = border; style.set_border_width_all(2); style.set_corner_radius_all(5)
	style.content_margin_left = x; style.content_margin_right = x; style.content_margin_top = y; style.content_margin_bottom = y
	return style

func _label(text: String, size := 20, color := INK) -> Label:
	var x := Label.new(); x.text = text; x.add_theme_font_size_override("font_size", maxi(14, int(size * text_scale))); x.add_theme_color_override("font_color", color); x.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size >= 22 and heading_font != null: x.add_theme_font_override("font",heading_font)
	x.set_meta("base_font_size", size)
	return x

func _button(text: String, action: Callable = Callable()) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = Vector2(0, 46); b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = text
	b.pressed.connect(func(): get_node("/root/Soundscape").play_ui("click"))
	b.mouse_entered.connect(func(): if not b.disabled: get_node("/root/Soundscape").play_ui("hover"))
	if action.is_valid(): b.pressed.connect(action)
	if _is_management_panel(current_kind):
		b.custom_minimum_size.y = 38
		b.add_theme_font_size_override("font_size", roundi(14 * text_scale))
		M.button(b)
	return b

func _ribbon(text: String, color: Color, action: Callable) -> Button:
	var b := _button(text, action); b.custom_minimum_size = Vector2(320, 58)
	var fill := GAME_THEME.BUY if color == TEAL else GAME_THEME.WARNING if color == ORANGE else GAME_THEME.DANGER if color == RED else GAME_THEME.ACTION
	GAME_THEME.primary(b,fill)
	b.add_theme_font_size_override("font_size",maxi(14, int(24 * text_scale))); b.add_theme_font_override("font",heading_font)
	return b

func _panel(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 12); parent.add_child(box)
	if title != "":
		var h := _label(title, 26, TEAL); h.name = "PanelTitle"; box.add_child(h)
	return box

func _clear(c: Node) -> void:
	for n in c.get_children(): n.queue_free()

func _build_hud() -> void:
	hud=Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; root.add_child(hud)
	var case_panel:=PanelContainer.new(); case_panel.set_anchors_preset(Control.PRESET_TOP_LEFT); case_panel.offset_left=18; case_panel.offset_top=18; case_panel.offset_right=338; case_panel.offset_bottom=74; case_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE; case_panel.add_theme_stylebox_override("panel",_surface(Color(0.08,0.14,0.22,0.78),Color.TRANSPARENT,10,7)); hud.add_child(case_panel)
	var case_col:=VBoxContainer.new(); case_col.add_theme_constant_override("separation",0); case_panel.add_child(case_col)
	status_label=_label("作業なし",16,Color.WHITE); status_label.autowrap_mode=TextServer.AUTOWRAP_OFF; status_label.clip_text=true; case_col.add_child(status_label)
	var work_state:=_label("",11,Color("c2d2df")); work_state.autowrap_mode=TextServer.AUTOWRAP_OFF; work_state.clip_text=true; case_col.add_child(work_state); controls.work_state=work_state
	var stats:=VBoxContainer.new(); stats.set_anchors_preset(Control.PRESET_TOP_RIGHT); stats.offset_left=-220; stats.offset_top=18; stats.offset_right=-18; stats.offset_bottom=72; stats.add_theme_constant_override("separation",1); hud.add_child(stats)
	var clock:=_label("09:00",24,Color("fff7db")); clock.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; clock.autowrap_mode=TextServer.AUTOWRAP_OFF; stats.add_child(clock); controls.clock=clock
	clock.add_theme_color_override("font_outline_color",INK); clock.add_theme_constant_override("outline_size",6)
	var deadline:=_label("納期 --:--",12,Color("d5e6f0")); deadline.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; deadline.autowrap_mode=TextServer.AUTOWRAP_OFF; stats.add_child(deadline); controls.deadline=deadline
	var cash:=_label("",26,Color("ffd85a")); cash.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; cash.autowrap_mode=TextServer.AUTOWRAP_OFF; stats.add_child(cash); controls.cash=cash
	cash.add_theme_color_override("font_outline_color",INK); cash.add_theme_constant_override("outline_size",6)
	var meta:=_label("",14,Color.WHITE); meta.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; meta.autowrap_mode=TextServer.AUTOWRAP_OFF; stats.add_child(meta); controls.meta=meta
	meta.add_theme_color_override("font_outline_color",INK); meta.add_theme_constant_override("outline_size",4)
	var xp:=ProgressBar.new(); xp.custom_minimum_size=Vector2(160,5); xp.size_flags_horizontal=Control.SIZE_SHRINK_END; xp.show_percentage=false; xp.add_theme_stylebox_override("background",_surface(Color("405267"),Color.TRANSPARENT,0,0)); xp.add_theme_stylebox_override("fill",_surface(CYAN,Color.TRANSPARENT,0,0)); stats.add_child(xp); controls.xp=xp
	var hint:=PanelContainer.new(); hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT); hint.offset_left=20; hint.offset_right=360; hint.offset_top=-58; hint.offset_bottom=-20; hint.mouse_filter=Control.MOUSE_FILTER_IGNORE; hint.add_theme_stylebox_override("panel",_surface(Color(0.08,0.14,0.22,0.84),Color.TRANSPARENT,10,7)); hint.visible=false; hud.add_child(hint)
	prompt=_label("",13,Color("e8f2f7")); prompt.autowrap_mode=TextServer.AUTOWRAP_OFF; prompt.clip_text=true; prompt.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; hint.add_child(prompt); controls.focus_hint=hint
	var team:=VBoxContainer.new(); team.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT); team.offset_left=-310; team.offset_right=-22; team.offset_top=-78; team.offset_bottom=-20; team.add_theme_constant_override("separation",3); hud.add_child(team); controls.team_hud={}
	for id in ["aya","ren"]:
		var member:=_label("",13,Color("e8f2f7")); member.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; member.autowrap_mode=TextServer.AUTOWRAP_OFF; member.clip_text=true; team.add_child(member); controls.team_hud[id]=member
	controls.work_steps=[]

func _build_main_menu() -> void:
	var menu := Control.new(); menu.name = "MainMenu"; menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); menu.mouse_filter=Control.MOUSE_FILTER_STOP; root.add_child(menu); controls.menu=menu
	var artwork := TextureRect.new(); artwork.name="TitleArtwork"; artwork.texture=load("res://assets/ui/menu_backdrop.svg"); artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); artwork.mouse_filter=Control.MOUSE_FILTER_IGNORE; menu.add_child(artwork)
	var layout := VBoxContainer.new(); layout.position=Vector2(76,75); layout.custom_minimum_size.x=440; layout.size.x=440; layout.add_theme_constant_override("separation",8); menu.add_child(layout); controls.menu_layout=layout
	var branding := HBoxContainer.new(); branding.add_theme_constant_override("separation",16); layout.add_child(branding)
	var mark := TextureRect.new(); mark.texture=load("res://assets/ui/mark.svg"); mark.custom_minimum_size=Vector2(48,64); mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; branding.add_child(mark)
	var title := _label("ホワイトハッカーラボ",36,GAME_THEME.TEXT); title.name="CompanyTitle"; title.add_theme_font_override("font",UI.font(700)); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.autowrap_mode=TextServer.AUTOWRAP_OFF; title.clip_text=true; title.tooltip_text=title.text; controls.company_title=title; branding.add_child(title); title.resized.connect(_fit_company_title)
	controls.menu_title=title
	var gap := Control.new(); gap.custom_minimum_size.y=9; layout.add_child(gap)
	var resume := _ribbon(UI.copy("title_continue","続きから"),ORANGE,_resume_game); resume.name="ResumeButton"; layout.add_child(resume); controls.resume=resume
	GAME_THEME.primary(resume,GAME_THEME.TABBAR); resume.alignment=HORIZONTAL_ALIGNMENT_LEFT; resume.add_theme_font_override("font",UI.font(700))
	var load_error := _label("",14,Color("ffd5d5")); load_error.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; load_error.custom_minimum_size.x=420; load_error.hide(); layout.add_child(load_error); controls.load_error=load_error
	var start := _ribbon(UI.copy("title_new","新しく始める"),TEAL,_open_new_company); start.name="NewCompanyButton"; start.alignment=HORIZONTAL_ALIGNMENT_LEFT; start.add_theme_font_override("font",UI.font(700)); GAME_THEME.primary(start,GAME_THEME.ACTION); layout.add_child(start)
	for entry in [[UI.copy("title_manual","チュートリアル"),"help"],[UI.copy("title_options","オプション"),"settings"],[UI.copy("title_credits","クレジット"),"credits"],[UI.copy("title_exit","終了"),"quit"]]:
		var button := _button("›   "+str(entry[0]),_quit if entry[1]=="quit" else open_panel.bind(entry[1])); button.custom_minimum_size=Vector2(260,38); button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_stylebox_override("normal",_surface(Color.TRANSPARENT,Color.TRANSPARENT,14,4)); button.add_theme_stylebox_override("hover",_surface(Color(1,1,1,0.12),Color.TRANSPARENT,14,4)); button.add_theme_stylebox_override("pressed",_surface(Color(1,1,1,0.2),Color.TRANSPARENT,14,4))
		for state_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(state_name,Color("f5f8f8"))
		layout.add_child(button)
	var version := _label("VERSION "+str(ProjectSettings.get_setting("application/config/version",""))+"  /  OFFLINE",14,Color.WHITE); version.autowrap_mode=TextServer.AUTOWRAP_OFF; version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT); version.position=Vector2(-290,-34); menu.add_child(version)

func _layout_main_menu() -> void:
	if not controls.has("menu_layout"): return
	var compact := root.size.y < 800
	controls.menu_layout.position=Vector2(40,56) if compact else Vector2(76,75)
	var menu_width := clampf(root.size.x * 0.36, 360.0, 460.0)
	controls.menu_layout.custom_minimum_size.x=menu_width; controls.menu_layout.size.x=menu_width
	controls.load_error.custom_minimum_size.x=menu_width
	controls.menu_layout.add_theme_constant_override("separation",4 if compact else 8)
	_fit_company_title()

func _fit_company_title() -> void:
	if not controls.has("company_title"): return
	var title: Label = controls.company_title
	var size := int(36 * minf(text_scale, 1.15))
	var font: Font = title.get_theme_font("font")
	while size > 18 and font.get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > title.size.x:
		size -= 1
	title.add_theme_font_size_override("font_size",size)

func _new_game(initial_profile: Dictionary = {}) -> bool:
	if _game() == null or not _game().new_game(initial_profile): return false
	if is_instance_valid(guided_intro): guided_intro.begin()
	operations_choices.clear();board_selected_id="";board_page=0;sales_view="inquiries";sales_search="";board_filter="all";pricing_drafts.clear();sales_quote_drafts.clear()
	_reset_coffee()
	close_panel(false)
	controls.menu.visible = false; hud.visible = true; _sync_office_clock_pause(); emit_signal("started"); update_hud()
	if _game() != null and _game().has_method("strategy_catalog") and str(_game().state.get("strategy", "")) == "": open_panel("board")
	return true

func _open_new_company() -> void:
	creating_company=true; open_panel("profile")

func _open_profile_editor() -> void:
	creating_company=false; open_panel("profile")

func _profile_editor() -> void:
	var g:=_game()
	var values: Dictionary=g.profile_defaults() if creating_company else g.profile()
	profile_inputs.clear()
	for spec in [["company",UI.copy("profile_company","会社名（40文字以内）"),40],["player",UI.copy("profile_player","主人公名（20文字以内）"),20],["aya",UI.copy("profile_member_a","同僚1の名前（20文字以内）"),20],["ren",UI.copy("profile_member_b","同僚2の名前（20文字以内）"),20]]:
		var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",16); modal_body.add_child(row)
		var label:=_label(str(spec[1]).get_slice("（",0),18); label.custom_minimum_size.x=180; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; row.add_child(label)
		var input:=LineEdit.new(); input.name="Profile_"+str(spec[0]); input.text=str(values[spec[0]]); input.max_length=int(spec[2]); input.custom_minimum_size.y=46; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; input.placeholder_text="%d文字以内" % int(spec[2]); input.tooltip_text="日本語・英数字・空白・記号使用可（%d文字以内）" % int(spec[2]); row.add_child(input); profile_inputs[spec[0]]=input
		input.text_changed.connect(func(_value): _update_profile_form())
	var feedback:=_label("",16,MUTED); modal_body.add_child(feedback); controls.profile_feedback=feedback
	var preview:=_label("",19,TEAL); modal_body.add_child(preview); controls.profile_preview=preview
	var confirm:=_ribbon("この会社で開始" if creating_company else UI.copy("profile_save","名前を保存"),TEAL,_confirm_profile); confirm.name="ConfirmProfile"; confirm.custom_minimum_size=Vector2(260,52); modal_footer.add_child(confirm); controls.profile_confirm=confirm
	_update_profile_form()
	profile_inputs.company.call_deferred("grab_focus")

func _profile_values() -> Dictionary:
	var values: Dictionary={}
	for id in profile_inputs: values[id]=profile_inputs[id].text
	return values

func _update_profile_form() -> void:
	var values:=_profile_values(); var error: String=_game().profile_error(values)
	controls.profile_confirm.disabled=not error.is_empty()
	var missing := false
	for value in values.values():
		if str(value).strip_edges().is_empty(): missing = true; break
	controls.profile_feedback.text=UI.copy("profile_required","空欄では登録できません") if missing else (error if not error.is_empty() else "会社名は40文字以内、氏名は20文字以内")
	controls.profile_feedback.add_theme_color_override("font_color",RED if not error.is_empty() else MUTED)
	controls.profile_preview.text=str(values.get("company","")).strip_edges()+"  /  代表  "+str(values.get("player","")).strip_edges()

func _confirm_profile() -> void:
	var values:=_profile_values()
	if not _game().profile_error(values).is_empty(): _update_profile_form(); return
	if creating_company:
		if not _new_game(values): controls.profile_feedback.text=UI.copy("save_failed","保存失敗。既存データ保持")
	elif _game().set_profile(values): open_panel("company")
	else: controls.profile_feedback.text=UI.copy("save_failed","保存失敗。既存データ保持")

func _resume_game() -> void:
	var loaded := false
	if _game() != null and _game().has_method("load_game"): loaded = _game().load_game()
	if not loaded:
		var detail := "セーブデータ読み込み失敗。既存データ保持。"
		if _game() != null and _game().get("last_load_error") != null and not str(_game().get("last_load_error")).is_empty(): detail = str(_game().get("last_load_error"))
		if controls.has("load_error"): controls.load_error.text = detail; controls.load_error.show()
		status_label.text = UI.copy("save_missing","読み込み失敗。復元元データなし")
		return
	_reset_coffee()
	if controls.has("load_error"): controls.load_error.text = ""
	controls.menu.visible = false; hud.visible = true; _sync_office_clock_pause(); emit_signal("started"); update_hud()

func _reset_coffee() -> void:
	coffee_phase = "idle"; coffee_elapsed = 0.0; coffee_cup = null

func open_main_menu() -> void:
	_reset_coffee()
	close_panel(false); controls.menu.visible = true; hud.visible = false
	_sync_office_clock_pause()
	_show_ui_cursor()
	if controls.has("resume"): controls.resume.disabled = not (_game() != null and _game().has_method("has_save") and _game().has_save())

func is_open() -> bool:
	return current_kind != "" or (controls.has("menu") and controls.menu.visible)

func _is_management_panel(kind: String) -> bool:
	return kind in ["board", "sales", "door", "day_review", "company", "shop", "staffing"]

func _show_ui_cursor() -> void:
	# The UI owns a visible cursor for its whole lifetime.  Reassert the mode
	# only when handing ownership back from gameplay; changing it while already
	# visible can make the platform reposition the pointer during panel rebuilds.
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _management_rail_button(label: String, kind: String, selected: bool) -> Button:
	var button := _button(label, open_panel.bind(kind))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 16)
	var fill := MANAGEMENT_PRIMARY if selected else Color(0,0,0,0)
	var hover := Color("2f6564") if not selected else Color("ffe27a")
	button.add_theme_stylebox_override("normal", _surface(fill, Color.TRANSPARENT, 12, 8))
	button.add_theme_stylebox_override("hover", _surface(hover, Color.TRANSPARENT, 12, 8))
	button.add_theme_stylebox_override("pressed", _surface(MANAGEMENT_SELECTED, Color.TRANSPARENT, 12, 8))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, INK if selected else Color("f4fbfb"))
	return button

func _management_tab(label: String, kind: String, selected: bool) -> Button:
	var button := _button(label, _navigate_management.bind(kind))
	button.name = "ManagementTab_%s" % kind
	button.set_meta("navigation_selected", selected)
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", roundi(14 * text_scale))
	M.button(button, "tab", selected)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, M.WHITE if selected else Color("B9CDCF"))
	for state in ["normal", "hover", "pressed"]:
		var style := M.surface(M.ACCENT if selected else M.DARK.lightened(0.06) if state != "normal" else Color.TRANSPARENT, 10)
		style.content_margin_top = 8; style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	return button

func _navigate_management(kind: String) -> void:
	# A top-level tab always opens its list, never a previously visited quote.
	if kind == "sales": board_selected_id = ""
	open_panel(kind)

func _return_from_desktop() -> void:
	if not _is_management_panel(desktop_return_kind): close_panel(); return
	var destination := desktop_return_kind
	open_panel(destination)
	if current_kind != destination: return
	if is_instance_valid(modal_scroll): modal_scroll.set_deferred("scroll_vertical", int(desktop_return_scroll.get("outer", 0)))
	for id in desktop_return_scroll:
		var scroll = modal_body.find_child(str(id), true, false)
		if scroll is ScrollContainer: scroll.set_deferred("scroll_vertical", int(desktop_return_scroll[id]))

func _return_to_sales_list() -> void:
	board_selected_id = ""
	open_panel("sales")

func _management_header(kind: String) -> PanelContainer:
	var header := PanelContainer.new(); header.name = "ManagementHeader"
	header.add_theme_stylebox_override("panel", M.surface(M.DARK, 8))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); header.add_child(row)
	row.add_child(_management_tabs(kind))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(spacer)
	var status := VBoxContainer.new(); status.name = "ManagementStatus"; status.add_theme_constant_override("separation", 0); status.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(status)
	var cash := _label("¥%s" % _group_number(int(_game().state.get("cash", 0))), 17, M.WHITE); cash.name = "ManagementCash"; cash.autowrap_mode = TextServer.AUTOWRAP_OFF; cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; status.add_child(cash)
	var clock := _label("DAY %02d  %s" % [int(_game().state.get("day", 1)), str(_game().business_clock())], 11, Color("B9CDCF")); clock.name = "ManagementClock"; clock.autowrap_mode = TextServer.AUTOWRAP_OFF; clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; status.add_child(clock)
	var guide := _button("?", _toggle_management_guide); guide.name = "ManagementGuide"; guide.tooltip_text = UI.copy("next_guide"); guide.custom_minimum_size = Vector2(34, 36); M.button(guide, "quiet"); guide.add_theme_color_override("font_color", M.WHITE); row.add_child(guide)
	var close := _button("×", close_panel); close.name = "ManagementClose"; close.custom_minimum_size = Vector2(34, 36); M.button(close, "quiet"); close.add_theme_color_override("font_color", M.WHITE); row.add_child(close)
	return header

func _group_number(value: int) -> String:
	var text := str(absi(value)); var result := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0: result += ","
		result += text[i]
	return ("−" if value < 0 else "") + result

func _toggle_management_guide() -> void:
	if is_instance_valid(next_task_guide): next_task_guide.open_management()

func _options_header() -> PanelContainer:
	var header := PanelContainer.new()
	header.name = "OptionsHeader"
	header.custom_minimum_size.y = 52
	var header_style := GAME_THEME.surface(GAME_THEME.FOOTER, Color.TRANSPARENT, 4, 9)
	header_style.border_color = GAME_THEME.TAB_BAR
	header_style.border_width_bottom = 3
	header.add_theme_stylebox_override("panel", header_style)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 9); header.add_child(row)
	var title := _label(UI.copy("title_options", "オプション"), 21, GAME_THEME.WHITE)
	title.add_theme_font_override("font", heading_font); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(title)
	var close := _button("×", _close_settings); close.name = "SettingsClose"; close.custom_minimum_size = Vector2(38, 38); close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", maxi(20, int(24 * text_scale))); close.add_theme_stylebox_override("normal", GAME_THEME.surface(GAME_THEME.ACTION, GAME_THEME.LINE, 3, 2)); close.add_theme_stylebox_override("hover", GAME_THEME.surface(GAME_THEME.TAB, GAME_THEME.TAB_BAR, 3, 2)); close.add_theme_stylebox_override("pressed", GAME_THEME.surface(GAME_THEME.TAB, GAME_THEME.TAB_BAR, 3, 2)); close.add_theme_color_override("font_color", GAME_THEME.WHITE); close.add_theme_color_override("font_hover_color", GAME_THEME.WHITE); close.add_theme_color_override("font_pressed_color", GAME_THEME.WHITE); row.add_child(close)
	return header

func _management_tabs(kind: String) -> HBoxContainer:
	var tabs := HBoxContainer.new(); tabs.name = "ManagementTabs"; tabs.add_theme_constant_override("separation", 2)
	for entry in [[UI.copy("board_list"), "board"], [UI.copy("ops_sales").get_slice("・", 0), "sales"], ["会社", "company"], [UI.copy("staffing_title"), "staffing"], ["設備", "shop"], ["PC", "terminal"]]:
		tabs.add_child(_management_tab(str(entry[0]), str(entry[1]), kind == str(entry[1]) or (kind in ["door", "day_review"] and str(entry[1]) == "board")))
	return tabs

func _build_management_rail(kind: String) -> VBoxContainer:
	var rail := VBoxContainer.new()
	rail.name = "ManagementRail"
	rail.custom_minimum_size.x = 180
	rail.add_theme_constant_override("separation", 6)
	var g := _game()
	var mark := _label(str(_game().company_name()), 25, GAME_THEME.TEXT)
	mark.add_theme_constant_override("line_spacing", -5)
	mark.custom_minimum_size.y = 88
	rail.add_child(mark)
	var subtitle := _label(str(g.company_name()) if g != null and g.has_method("company_name") else "セキュリティ相談所", 12, Color("b7d7d3"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rail.add_child(subtitle)
	var gap := Control.new(); gap.custom_minimum_size.y = 10; rail.add_child(gap)
	for entry in [[UI.copy("ops_title"), "board"], [UI.copy("ops_sales"), "sales"], ["▥  会社・スキル", "company"], [UI.copy("staffing_title"), "staffing"], ["▰  設備購入", "shop"], ["▤  業務デスクトップ", "terminal"]]:
		rail.add_child(_management_rail_button(str(entry[0]), str(entry[1]), kind == str(entry[1])))
	var divider := HSeparator.new(); divider.add_theme_constant_override("separation", 14); rail.add_child(divider)
	rail.add_child(_management_rail_button("◌  チュートリアル", "help", false))
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; rail.add_child(spacer)
	var clock := _label("", 13, Color("c4dfdb")); clock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; rail.add_child(clock)
	if g != null and g.has_method("business_clock"): clock.text = "DAY %02d\n%s" % [int(g.state.get("day", 1)), g.business_clock()]
	return rail

func _layout_management() -> void:
	if not is_instance_valid(modal) or not _is_management_panel(current_kind): return
	var viewport_size := root.size
	var quote_detail := current_kind == "sales" and not board_selected_id.is_empty()
	var width := minf(1060.0 if quote_detail else 1440.0, viewport_size.x - 24.0)
	var desired_height := 940.0
	if quote_detail and is_instance_valid(modal_body):
		desired_height = maxf(380.0, modal_body.get_combined_minimum_size().y + 194.0)
	var height := minf(desired_height, viewport_size.y - 24.0)
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.offset_left = -width / 2; modal.offset_right = width / 2
	modal.offset_top = -height / 2; modal.offset_bottom = height / 2
	if current_kind == "sales" and is_instance_valid(modal_scroll):
		modal_scroll.custom_minimum_size.x = minf(1180.0, width - 40.0)

func open_panel(kind: String) -> void:
	# UI -> UI is one continuous visible-cursor session.  Do not hand the
	# pointer back to gameplay while replacing the panel tree.
	var previous_kind := current_kind
	var return_scroll: Dictionary = {}
	if kind == "terminal" and _is_management_panel(previous_kind) and is_instance_valid(modal_body):
		return_scroll.outer = modal_scroll.scroll_vertical
		for scroll in modal_body.find_children("*", "ScrollContainer", true, false):
			return_scroll[str(scroll.name)] = scroll.scroll_vertical
	if previous_kind == "sales" and is_instance_valid(modal_body):
		var quote_input = modal_body.find_child("OfferPrice", true, false)
		if quote_input is SpinBox: quote_input.apply()
	var management_switch := not previous_kind.is_empty() and _is_management_panel(previous_kind) and _is_management_panel(kind)
	if management_switch and is_instance_valid(next_task_guide): next_task_guide.management_open = false
	if kind == "settings" and settings_return_kind.is_empty() and not previous_kind.is_empty(): settings_return_kind = previous_kind
	if current_kind != "":
		if not close_panel(false, false): return
	if kind == "terminal" and previous_kind != "terminal":
		desktop_return_kind = previous_kind if _is_management_panel(previous_kind) else ""
		desktop_return_scroll = return_scroll
	current_kind = kind
	if _is_management_panel(kind): hud.hide()
	if kind == "settings":
		if is_instance_valid(next_task_guide): next_task_guide.hide()
		if is_instance_valid(guided_intro): guided_intro.hide()
	_sync_office_clock_pause()
	_show_ui_cursor()
	if kind == "terminal":
		hud.visible = false
		desktop = load("res://scripts/desktop.gd").new()
		root.add_child(desktop)
		desktop.setup(_game())
		_desktop_preview_drawn = false
		if DisplayServer.get_name() != "headless" and not desktop_preview_ready.get_connections().is_empty():
			var opened_desktop := desktop
			RenderingServer.frame_post_draw.connect(func():
				if is_instance_valid(opened_desktop) and desktop == opened_desktop:
					_desktop_preview_drawn = true, CONNECT_ONE_SHOT)
		desktop.close_requested.connect(close_panel)
		if desktop.has_signal("return_requested"):
			desktop.connect("return_requested", _return_from_desktop)
		if desktop.has_method("configure_return"):
			var return_label := UI.copy("board_list") if desktop_return_kind == "board" else _panel_title(desktop_return_kind)
			desktop.configure_return(return_label if not desktop_return_kind.is_empty() else "")
		desktop.company_requested.connect(func(): open_panel("company"))
		desktop.staffing_requested.connect(func(): open_panel("staffing"))
		desktop.contracts_requested.connect(func(): open_panel("board"))
		desktop.next_task_requested.connect(next_task_guide.locate_task)
		desktop.sales_requested.connect(func():
			board_selected_id = ""
			sales_view = "inquiries"
			open_panel("sales"))
		desktop.equipment_requested.connect(func(): open_panel("shop"))
		return
	if controls.menu.visible: controls.menu.modulate.a = 0.0
	modal_shade = ColorRect.new(); modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); modal_shade.color = Color(0.10,0.19,0.23,0.42); root.add_child(modal_shade)
	if kind == "ending": _show_ending()
	else:
		var management := _is_management_panel(kind)
		var options_shell := kind == "settings"
		modal = PanelContainer.new(); modal.name = "Panel_%s" % kind; modal.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(modal)
		var layout: VBoxContainer
		if management:
			modal.theme = M.theme(text_scale)
			var background := M.surface(M.PAPER, 0)
			background.shadow_color = Color(0.02, 0.06, 0.07, 0.3); background.shadow_size = 18
			modal.add_theme_stylebox_override("panel", background)
			var shell := VBoxContainer.new(); shell.add_theme_constant_override("separation", 0); modal.add_child(shell)
			shell.add_child(_management_header(kind))
			var content_margin := MarginContainer.new(); content_margin.name = "ManagementContent"; content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
			for side in ["left", "right", "top", "bottom"]: content_margin.add_theme_constant_override("margin_" + side, 18)
			shell.add_child(content_margin)
			layout = VBoxContainer.new(); layout.add_theme_constant_override("separation", 14); content_margin.add_child(layout)
			management_rail = null
		else:
			if options_shell:
				modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				modal.add_theme_stylebox_override("panel", GAME_THEME.surface(GAME_THEME.FOOTER, Color.TRANSPARENT, 0, 0))
				var options_outer := MarginContainer.new(); options_outer.add_theme_constant_override("margin_left", 16); options_outer.add_theme_constant_override("margin_right", 16); options_outer.add_theme_constant_override("margin_top", 16); options_outer.add_theme_constant_override("margin_bottom", 16); modal.add_child(options_outer)
				layout = VBoxContainer.new(); layout.add_theme_constant_override("separation", 8); options_outer.add_child(layout)
				layout.add_child(_options_header())
			else:
				modal.set_anchors_preset(Control.PRESET_CENTER); modal.offset_left = -430; modal.offset_top = -280; modal.offset_right = 430; modal.offset_bottom = 280
				if kind == "pause":
					modal.offset_left=-208; modal.offset_right=208; modal.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
				else:
					var paper := _surface(SURFACE,INK,0,0); paper.shadow_color=Color(0.08,0.15,0.16,0.45); paper.shadow_size=2; paper.shadow_offset=Vector2(5,6); modal.add_theme_stylebox_override("panel",paper)
				var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", 28); margin.add_theme_constant_override("margin_right", 28); margin.add_theme_constant_override("margin_top", 24); margin.add_theme_constant_override("margin_bottom", 24); modal.add_child(margin)
				layout = VBoxContainer.new(); layout.add_theme_constant_override("separation", 12); margin.add_child(layout)
		if not management and not options_shell:
			var heading:=_label(_panel_title(kind),32,Color("f5f8f8") if kind=="pause" else INK); heading.add_theme_font_override("font",heading_font)
			heading.name="PanelTitle"
			if kind=="pause": heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; heading.add_theme_constant_override("outline_size",7); heading.add_theme_color_override("font_outline_color",INK)
			layout.add_child(heading)
		var content_host: Control = layout
		if kind == "settings":
			var nav := HBoxContainer.new(); nav.add_theme_constant_override("separation", 8); layout.add_child(nav)
			controls.settings_tabs={}
			for entry in [[UI.copy("opt_tab_video","映像"),"video"],[UI.copy("opt_tab_controls","操作"),"control"],[UI.copy("opt_tab_audio","音声"),"audio"],["読みやすさ","accessibility"]]:
				var tab:=_button(entry[0],_settings_tab.bind(entry[1])); tab.toggle_mode=true; tab.button_pressed=entry[1]=="video"; tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tab.add_theme_font_size_override("font_size", maxi(14, int(16 * text_scale))); GAME_THEME.navigation(tab, entry[1] == "video"); nav.add_child(tab); controls.settings_tabs[entry[1]]=tab
			var options_content := PanelContainer.new(); options_content.size_flags_vertical=Control.SIZE_EXPAND_FILL; options_content.add_theme_stylebox_override("panel",GAME_THEME.surface(GAME_THEME.CANVAS,GAME_THEME.LINE,5,12)); layout.add_child(options_content)
			var options_layout := VBoxContainer.new(); options_layout.add_theme_constant_override("separation",8); options_content.add_child(options_layout); content_host=options_layout
		modal_scroll = ScrollContainer.new(); modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; content_host.add_child(modal_scroll)
		modal_scroll.follow_focus = true
		modal_body = VBoxContainer.new(); modal_body.add_theme_constant_override("separation", 14); modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; modal_scroll.add_child(modal_body)
		if kind == "sales":
			# Keep the quote and sales reading column legible on wide displays while
			# leaving the footer in the shell's full width row.
			modal_scroll.custom_maximum_size.x = 1180
			modal_scroll.custom_minimum_size.x = minf(1180.0, root.size.x - 64.0)
			modal_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		modal_footer = HBoxContainer.new(); modal_footer.add_theme_constant_override("separation", 12)
		if management:
			var footer_panel := PanelContainer.new(); footer_panel.name = "ManagementFooter"
			var footer_style := M.surface(M.PAPER, 0); footer_style.border_width_top = 1; footer_style.border_color = M.LINE; footer_style.content_margin_top = 12
			footer_panel.add_theme_stylebox_override("panel", footer_style); layout.add_child(footer_panel); footer_panel.add_child(modal_footer)
		else:
			content_host.add_child(modal_footer)
		match kind:
			"profile": _profile_editor()
			"board": _board()
			"sales": _sales_board()
			"day_review": OPERATIONS_PANEL.closeout(self,true)
			"company": _company()
			"staffing": _staffing()
			"aya", "ren": _crew(kind)
			"shop": _shop()
			"door": _door()
			"pause": _pause()
			"help": _help()
			"coffee": _coffee()
			"credits": _credits()
			"settings": _settings()
			"confirm_display": _confirm_display()
		if kind not in ["confirm_display","pause","settings"] and not management: _add_close()
		for footer_child in modal_footer.get_children():
			if footer_child is Label: footer_child.autowrap_mode=TextServer.AUTOWRAP_OFF; footer_child.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		if management:
			_layout_management()
			if kind == "sales" and not board_selected_id.is_empty():
				modal_body.minimum_size_changed.connect(_layout_management.call_deferred)
			var footer_panel := modal.find_child("ManagementFooter", true, false)
			if footer_panel is Control: footer_panel.visible = not modal_footer.get_children().is_empty()
		# Management tabs are one continuous workspace. Recreating the shell with
		# a fade from zero made every tab click flash; keep it fully opaque while
		# the old queued tree covers the same frame.
		if management_switch:
			modal.modulate = Color.WHITE
		else:
			modal.modulate.a=0.0; create_tween().tween_property(modal,"modulate:a",1.0,0.12)

func _panel_title(kind: String) -> String:
	if kind == "company": return UI.copy("v220_operating_desk")
	if kind=="board":return UI.copy("ops_title")
	if kind=="sales":return UI.copy("ops_sales")
	if kind=="day_review":return UI.copy("ops_settlement")
	if kind == "staffing": return UI.copy("staffing_title")
	if kind=="profile":return "会社をつくろう" if creating_company else "会社とメンバーの名前"
	if kind in ["aya","ren"]:return _game().member_name(kind)+(" / 調査担当" if kind=="aya" else " / 復旧担当")
	return {"terminal":"端末 / 作業", "board":"案件ボード", "company":"会社のスキル", "aya":"調査担当", "ren":"復旧担当", "shop":"設備と道具", "door":"一日の終わり", "pause":"一時停止", "help":UI.copy("title_manual","チュートリアル"), "coffee":"コーヒー休憩", "credits":UI.copy("title_credits","クレジット"), "settings":UI.copy("title_options","オプション"), "confirm_display":"設定の確認", "ending":"6日間の記録"}.get(kind, kind)

func _add_close() -> void:
	var space := Control.new(); space.size_flags_horizontal = Control.SIZE_EXPAND_FILL; modal_footer.add_child(space)
	var b := _button("閉じる (Esc)", Callable(self, "close_panel")); b.name = "CloseButton"
	if _is_management_panel(current_kind): GAME_THEME.primary(b, GAME_THEME.ACTION)
	modal_footer.add_child(b)

func close_panel(emit := true, restore_input := true) -> bool:
	if is_instance_valid(desktop) and desktop.has_method("_save_session"):
		if not bool(desktop._save_session()):
			return false
		_capture_desktop_preview()
	if not previous_settings.is_empty():
		_restore_settings()
	if modal != null: modal.queue_free(); modal = null
	if is_instance_valid(modal_shade): modal_shade.queue_free(); modal_shade = null
	if controls.has("menu"): controls.menu.modulate = Color.WHITE
	if is_instance_valid(desktop):
		desktop.queue_free(); desktop = null
	_desktop_preview_drawn = false
	if controls.has("menu") and not controls.menu.visible: hud.visible = true
	controls.erase("verify_result")
	controls.erase("DeliverButton")
	controls.erase("hint_label")
	current_kind = ""
	_sync_office_clock_pause()
	if restore_input and (not controls.has("menu") or not controls.menu.visible):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if emit: emit_signal("closed")
	return true

func _capture_desktop_preview() -> void:
	# Use the last presented app frame before the UI tree is replaced. This is
	# only an in-memory monitor image: it never touches player saves or disk.
	if not _desktop_preview_drawn or DisplayServer.get_name() == "headless": return
	if desktop_preview_ready.get_connections().is_empty(): return
	if not is_instance_valid(desktop) or not desktop.is_visible_in_tree(): return
	var viewport := get_viewport()
	var frame := viewport.get_texture().get_image()
	if frame == null or frame.is_empty(): return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0: return
	var ratio := Vector2(frame.get_width(), frame.get_height()) / viewport_size
	var desktop_rect := desktop.get_global_rect()
	var region := Rect2i(desktop_rect.position * ratio, desktop_rect.size * ratio)
	region = region.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if not region.has_area(): return
	var preview := frame.get_region(region)
	if preview.get_width() > 1024:
		preview.resize(1024, maxi(1, roundi(float(preview.get_height()) * 1024.0 / preview.get_width())), Image.INTERPOLATE_LANCZOS)
	desktop_preview_ready.emit(ImageTexture.create_from_image(preview))

func _board() -> void:
	var g := _game()
	if g==null:return
	if str(g.state.strategy).is_empty() or not bool(g.state.get("career_mode",false)):_sales_board();return
	OPERATIONS_PANEL.build(self)

func _refresh_operations() -> void:
	if current_kind!="board":return
	var scroll:=modal_scroll.scroll_vertical
	var positions: Dictionary={}
	for id in ["DispatchStaffScroll","DispatchTicketScroll"]:
		var node=modal_body.find_child(id,true,false)
		if node is ScrollContainer:positions[id]=node.scroll_vertical
	open_panel("board")
	modal_scroll.set_deferred("scroll_vertical",scroll)
	for id in positions:
		var node=modal_body.find_child(id,true,false)
		if node is ScrollContainer:node.set_deferred("scroll_vertical",int(positions[id]))

func _operations_feedback(message: String) -> void:
	_management_feedback(message)

func _management_feedback(message: String) -> void:
	# Keep an action failure beside the persistent actions, including when the
	# reading area is scrolled. Replace the previous message on repeated clicks.
	if not is_instance_valid(modal): return
	var feedback = modal.find_child("ManagementActionFeedback", true, false)
	if not feedback is Label:
		feedback = _label("", maxi(13, roundi(14 * text_scale)), WARNING)
		feedback.name = "ManagementActionFeedback"
		feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var footer = modal.find_child("ManagementFooter", true, false)
		if footer is Control:
			var host = footer.get_parent()
			host.add_child(feedback)
			host.move_child(feedback, footer.get_index())
		else: modal_body.add_child(feedback)
	feedback.text = message
	feedback.visible = not message.is_empty()

func _operations_open(id: String, target_index: int, app: String = "") -> void:
	var g:=_game()
	if not g.switch_contract(id):_operations_feedback(UI.copy("ops_result_failed"));return
	if target_index>=0 and not g.select_target(target_index):_operations_feedback(UI.copy("ops_result_failed"));return
	open_panel("terminal")
	if not app.is_empty():desktop._show_app(app)

func _sales_board() -> void:
	var g := _game(); if g == null: return
	var level: Dictionary = g.company_level()
	if str(g.state.strategy).is_empty():
		modal_body.add_child(_label("得意分野",28))
		for strategy in g.strategy_catalog():
			var card := PanelContainer.new(); modal_body.add_child(card); var row := HBoxContainer.new(); row.add_theme_constant_override("separation",18); card.add_child(row)
			var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(col); col.add_child(_label(strategy.title,23,TEAL)); col.add_child(_label(strategy.benefit,16,MUTED))
			var choice := _button("この分野で開始",_choose_strategy.bind(strategy.id)); choice.name = "GuideStrategy_" + str(strategy.id); row.add_child(choice)
		return
	var contract_queue: Array = g.contract_queue() if g.has_method("contract_queue") else []
	if not contract_queue.is_empty() and not g.state.career_mode:
		_render_contract_queue(contract_queue)
	if g.state.career_mode:
		if not board_selected_id.is_empty():
			for offer in g.state.offers:
				if str(offer.id) == board_selected_id:
					var sales_back := _button("← "+UI.copy("ops_sales"), _return_to_sales_list); sales_back.name = "QuoteBack"; modal_footer.add_child(sales_back)
					if modal_footer.get_child_count() > 1: modal_footer.move_child(sales_back, 1)
					_contract_detail(offer)
					_sales_fonts(modal_body)
					return
		SALES_PANEL.build(self)
		return
	var m: Dictionary = g.mission()
	modal_body.add_child(_label("DAY %02d  /  会社 Lv.%d" % [g.state.day,level.level],16,TEAL))
	modal_body.add_child(_label(m.title,27)); modal_body.add_child(_label(m.brief,18,MUTED))
	modal_body.add_child(_label("報酬 ¥%d   経費 ¥%d   見込み利益 ¥%d" % [m.reward,m.estimated_cost,m.expected_profit],18,TEAL))
	if not g.state.career_mode and (not g.state.accepted or g.current_done()):
		modal_body.add_child(_button("営業カタログへ",_start_free_career))
	modal_footer.add_child(_button("会社・スキル",open_panel.bind("company")))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; modal_footer.add_child(spacer)
	var pc := _button(UI.copy("office_pc","自席PCを使う")+"  [F]",open_panel.bind("terminal")); pc.name="GuidePC"; M.button(pc,"primary"); modal_footer.add_child(pc)

func _refresh_sales_panel(reset_scroll: bool = false) -> void:
	# Sales subtabs, filters, and accordions replace only their content. The
	# modal/shade/footer remain mounted, so there is no close/open flash.
	if current_kind != "sales" or not is_instance_valid(modal_body):
		open_panel("sales")
		return
	var previous_scroll := modal_scroll.scroll_vertical if is_instance_valid(modal_scroll) else 0
	SALES_PANEL.build(self)
	if is_instance_valid(modal_scroll):
		modal_scroll.set_deferred("scroll_vertical", 0 if reset_scroll else previous_scroll)

func _queue_copy(key: String, fallback: String = "") -> String:
	var value := UI.copy(key, fallback)
	return value if not value.is_empty() else fallback

func _queue_deadline(raw: String) -> String:
	var parts := raw.split(" ", false)
	if parts.size() >= 3 and parts[0] == "DAY": return _queue_copy("queue_deadline", "%s") % [int(parts[1]), str(parts[2])]
	return raw

func _render_contract_queue(queue: Array) -> void:
	var g := _game()
	var title := _queue_copy("queue_title", "")
	if not title.is_empty(): modal_body.add_child(_label(title, 22, TEAL))
	if g != null and g.has_method("contract_capacity"):
		var cap := int(g.contract_capacity())
		var active_count := 0
		for queue_item in queue:
			if not bool(queue_item.get("completed", false)): active_count += 1
		modal_body.add_child(_label(_queue_copy("queue_capacity", "") % [active_count, cap], 14, MUTED))
	if queue.is_empty():
		var empty := _queue_copy("queue_empty", "")
		if not empty.is_empty(): modal_body.add_child(_label(empty, 14, MUTED))
		return
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation", 4); modal_body.add_child(list)
	for item in queue:
		var id := str(item.get("id", "")); var active := bool(item.get("active", false)); var completed := bool(item.get("completed", false))
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); list.add_child(row)
		var scope := _queue_copy("queue_scope", "%s") % id
		var state_key := "queue_done" if completed else "queue_current" if active else "queue_open"
		var status := _queue_copy(state_key, "")
		var deadline := _queue_deadline(str(item.get("deadline_text", "")))
		var text := _label("%s  /  %s  /  %s\n%s" % [str(item.get("client", "")), str(item.get("title", "")), status, deadline], 13, TEAL if active else INK)
		text.tooltip_text = scope
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; row.add_child(text)
		var switch_button := _button(_queue_copy("queue_current", "") if active else _queue_copy("queue_switch", ""), _switch_contract_ui.bind(id))
		switch_button.disabled = active or id.is_empty(); row.add_child(switch_button)

func _switch_contract_ui(id: String) -> void:
	var g := _game(); if g == null or id.is_empty(): return
	var ok := false
	if is_instance_valid(desktop) and desktop.has_method("_switch_contract"):
		ok = bool(desktop._switch_contract(id))
	elif g.has_method("switch_contract"):
		ok = bool(g.switch_contract(id))
	if ok:
		open_panel("terminal")
	else:
		open_panel("board")

func _contract_ticket(offer: Dictionary) -> void:
	var accent: Color={"advisory":TEAL,"operations":Color("3a7898"),"response":ORANGE}.get(str(offer.category),TEAL)
	var card:=PanelContainer.new(); var paper:=_surface(SURFACE if offer.unlocked else Color("eef2f6"),BORDER,14,12); paper.set_border_width_all(1); paper.border_width_left=4; paper.border_color=accent; card.add_theme_stylebox_override("panel",paper); modal_body.add_child(card)
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",12); card.add_child(row)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",3); row.add_child(column)
	var top:=_label("%s  /  %d拠点  /  Lv.%d" % [offer.client,offer.targets,offer.required_level],13,accent); top.autowrap_mode=TextServer.AUTOWRAP_OFF; column.add_child(top)
	var title:=_label(str(offer.title),18,INK); title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(title)
	var summary:=_label("顧客: %s　分類: %s　対象: %d拠点\n参考価格 ¥%d　経費 ¥%d　期限 %s" % [str(offer.client),str(offer.service),int(offer.targets),int(offer.reward),int(offer.get("estimated_cost",0)),str(offer.get("deadline_text","--:--"))],13,MUTED); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(summary)
	var detail:=_button("詳細表示",_select_contract.bind(str(offer.id))); detail.custom_minimum_size=Vector2(128,38); row.add_child(detail)

func _select_contract(id: String) -> void:
	for item in _game().contract_queue():
		if str(item.get("id", "")) == id:
			operations_choices.view = "contracts"
			operations_choices.dispatch_selected = {"kind":"contract", "id":id, "target":int(item.get("target_index",0)), "member":""}
			open_panel("board")
			return
	board_selected_id=id
	open_panel("sales")

func _open_billing(invoice_id: String = "") -> void:
	open_panel("terminal")
	if is_instance_valid(desktop): desktop.open_invoice(invoice_id)

func _contract_detail(offer: Dictionary) -> void:
	var g := _game()
	var card:=PanelContainer.new(); card.add_theme_stylebox_override("panel",_surface(GAME_THEME.WHITE,Color.TRANSPARENT,12,10)); modal_body.add_child(card)
	var body:=VBoxContainer.new(); body.add_theme_constant_override("separation",4); card.add_child(body)
	var identity := HBoxContainer.new(); identity.add_theme_constant_override("separation",12); body.add_child(identity)
	var job_title := _label(str(offer.title),20,INK); job_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; identity.add_child(job_title)
	var client_title := _label(str(offer.client),13,UI.MUTED); client_title.autowrap_mode=TextServer.AUTOWRAP_OFF; client_title.size_flags_vertical=Control.SIZE_SHRINK_CENTER; identity.add_child(client_title)
	var reasons: Array = g.contract_eligibility(offer) if g.has_method("contract_eligibility") else (["受注可能"] if bool(offer.unlocked) else ["受注条件未達"])
	var quote: Dictionary = g.contract_quote(offer)
	body.add_child(_label(UI.copy("board_facts") % [int(offer.targets),int(quote.budget),int(quote.costs)],14,INK))
	if not offer.unlocked:
		var eligibility := _label(" / ".join(PackedStringArray(reasons)),14,WARNING)
		eligibility.name = "ContractEligibility"
		body.add_child(eligibility)
	var inputs := HBoxContainer.new(); inputs.add_theme_constant_override("separation",20); body.add_child(inputs)
	var plan_row := HBoxContainer.new(); plan_row.add_theme_constant_override("separation",12); plan_row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; inputs.add_child(plan_row)
	var plan_label := _label(UI.copy("board_plan"),14,UI.MUTED); plan_label.autowrap_mode=TextServer.AUTOWRAP_OFF; plan_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER; plan_row.add_child(plan_label)
	var plan := OptionButton.new(); plan.name="ContractPlan"; plan.size_flags_horizontal=Control.SIZE_EXPAND_FILL; var plans: Array = g.contract_plans()
	for item in plans: plan.add_item(str(item.label))
	var selected_plan := str(g.offer_plan()) if g.has_method("offer_plan") else str(g.state.contract_plan)
	for index in plans.size():
		if plans[index].id == selected_plan: plan.select(index)
	plan.item_selected.connect(func(index):
		var input = body.find_child("OfferPrice", true, false)
		if input is SpinBox: input.apply()
		var draft_amount := roundi(input.value) if input is SpinBox else int(quote.quoted_fee)
		var changed: bool = bool(g.set_offer_plan(str(plans[index].id))) if g.has_method("set_offer_plan") else bool(g.set_contract_plan(str(plans[index].id)))
		if changed:
			_select_contract(str(offer.id))
			if draft_amount != int(quote.quoted_fee):
				var next_input = modal_body.find_child("OfferPrice", true, false)
				if next_input is SpinBox: next_input.value = draft_amount
	)
	plan_row.add_child(plan)
	var price_row := HBoxContainer.new(); price_row.add_theme_constant_override("separation",12); price_row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; inputs.add_child(price_row)
	var supply_requirement: Dictionary = offer.get("supply_requirement", {}) if offer.get("supply_requirement", {}) is Dictionary else {}
	var has_billable_material := not supply_requirement.is_empty()
	var supply_cost := maxi(0, int(quote.get("invoice_total", quote.quoted_fee)) - int(quote.quoted_fee))
	var price_label := _label(UI.copy("billing_fee") if has_billable_material else UI.copy("board_price"),14,UI.MUTED); price_label.autowrap_mode=TextServer.AUTOWRAP_OFF; price_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER; price_row.add_child(price_label)
	var price := SpinBox.new(); price.name="OfferPrice"; price.min_value=0; price.max_value=maxi(1,int(quote.reference_fee)*10); price.step=1; price.value=int(sales_quote_drafts.get(str(offer.id), quote.quoted_fee)); price.prefix="¥"; price.custom_minimum_size.x=150; price.size_flags_horizontal=Control.SIZE_EXPAND_FILL; price_row.add_child(price); M.field(price); M.field(plan)
	var material_totals: HBoxContainer
	var material_cost_label: Label
	var invoice_total_label: Label
	if has_billable_material and supply_cost > 0:
		material_totals = HBoxContainer.new(); material_totals.name="QuoteHardwareAmounts"; material_totals.add_theme_constant_override("separation",16); material_totals.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.add_child(material_totals)
		material_cost_label = _label(UI.copy("stock_material_cost") + "  ¥%d" % supply_cost,13,UI.MUTED); material_cost_label.name="QuoteHardwareMaterial"; material_cost_label.autowrap_mode=TextServer.AUTOWRAP_OFF; material_cost_label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; material_totals.add_child(material_cost_label)
		invoice_total_label = _label(UI.copy("billing_total") + "  ¥%d" % int(quote.get("invoice_total", quote.quoted_fee)),14,INK); invoice_total_label.name="QuoteHardwareTotal"; invoice_total_label.autowrap_mode=TextServer.AUTOWRAP_OFF; invoice_total_label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; material_totals.add_child(invoice_total_label)
	var quote_totals := HBoxContainer.new(); quote_totals.add_theme_constant_override("separation",12); body.add_child(quote_totals)
	var quote_limits := _label(UI.copy("board_quote_limits") % [int(quote.reference_fee),int(quote.budget_limit)],12,UI.MUTED); quote_limits.autowrap_mode=TextServer.AUTOWRAP_OFF; quote_limits.size_flags_vertical=Control.SIZE_SHRINK_CENTER; quote_totals.add_child(quote_limits)
	var price_preview := _label("",14,INK); price_preview.name="QuotePreview"; price_preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL; price_preview.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; quote_totals.add_child(price_preview)
	var update_preview := func(_amount: float) -> void:
		var proposed: Dictionary = g.contract_quote(offer,roundi(price.value))
		if is_instance_valid(invoice_total_label): invoice_total_label.text = UI.copy("billing_total") + "  ¥%d" % int(proposed.get("invoice_total", proposed.get("quoted_fee", 0)))
		var reaction := str(proposed.price_reaction)
		var reaction_text: String = {"discount":"割安 · 顧客評価 +3","fair":"相場内 · 顧客評価 ±0","premium":"高め · 顧客評価 -3"}.get(reaction,reaction)
		price_preview.text=(UI.copy("board_profit") % int(proposed.net)) + "  ·  " + reaction_text
		if not bool(proposed.affordable): price_preview.text += "\n顧客予算超過。成約不可。"
		elif int(proposed.net) < 0: price_preview.text += "\n基本経費を下回る赤字見積です。"
		price_preview.add_theme_color_override("font_color", WARNING if not bool(proposed.affordable) or int(proposed.net)<0 else INK)
	price.value_changed.connect(update_preview); update_preview.call(price.value)
	price.value_changed.connect(func(value: float): sales_quote_drafts[str(offer.id)] = roundi(value))
	var operating_preview: Dictionary = g.offer_operations_preview(offer)
	if int(operating_preview.get("required", 0)) > 0 or int(operating_preview.get("shortage", 0)) > 0:
		_contract_operations_preview(body, offer, g)
	var disclosures := HBoxContainer.new(); disclosures.add_theme_constant_override("separation",24); body.add_child(disclosures)
	var brief := _sales_disclosure(body, UI.copy("board_brief"), disclosures)
	brief.add_child(_label(str(offer.brief),14,INK))
	var conditions := _sales_disclosure(body, UI.copy("board_conditions"), disclosures)
	conditions.add_child(_label(UI.copy("billing_terms") + "  " + str(g.invoice_terms(offer).label),14,INK))
	conditions.add_child(_label("%s · 会社Lv.%d / 専門Lv.%d / 難度%d" % [str(offer.service),offer.required_level,offer.required_rank,offer.grade],14,INK))
	if int(operating_preview.get("required", 0)) == 0 and int(operating_preview.get("shortage", 0)) == 0:
		_contract_operations_preview(conditions, offer, g, true)
	var care_reason := ""
	if selected_plan == "care":
		var terms: Dictionary = g.care_terms(str(offer.client)); care_reason=str(terms.reason)
		var rates_template := UI.copy("care_contract_rates", ""); var billing := UI.copy("care_billing", "")
		if not rates_template.is_empty(): body.add_child(_label((rates_template % [int(terms.fee),int(terms.cost),int(terms.net)]) + ("\n" + billing if not billing.is_empty() else ""),14,TEAL))
		if not care_reason.is_empty(): body.add_child(_label(care_reason,14,WARNING))
	var actions := HBoxContainer.new(); actions.name = "QuoteActions"; actions.add_theme_constant_override("separation",10); modal_footer.add_child(actions)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.alignment = BoxContainer.ALIGNMENT_END
	var save_draft:=_button(UI.copy("board_save_draft"),func():
		price.apply()
		if g.set_offer_quote(str(offer.id),roundi(price.value)):
			sales_quote_drafts.erase(str(offer.id)); board_selected_id="";sales_view="inquiries";open_panel("sales")
		else: _management_feedback("見積を保存できませんでした。入力を残しています。受注状況と保存先を確認して再試行してください。"))
	save_draft.name="SaveQuoteDraft";save_draft.disabled=not offer.unlocked or not bool(offer.get("market_available",true));actions.add_child(save_draft)
	var accept:=_button(UI.copy("board_send_quote"),func(): price.apply(); _submit_quote(str(offer.id),roundi(price.value))); accept.name="AcceptContract"; accept.disabled=not offer.unlocked or not bool(offer.get("market_available",true)) or not care_reason.is_empty(); actions.add_child(accept); M.button(accept,"primary")
	var existing_contract := false
	var active_contracts := 0
	if g.has_method("contract_queue"):
		for queued in g.contract_queue():
			if str(queued.get("id", "")) == str(offer.id): existing_contract = true
			if not bool(queued.get("completed", false)): active_contracts += 1
	if existing_contract: save_draft.disabled = true
	var capacity_full := not existing_contract and g.has_method("contract_capacity") and active_contracts >= int(g.contract_capacity())
	var queue_reason := _queue_copy("queue_already", "") if existing_contract else _queue_copy("queue_full", "") if capacity_full else ""
	if not queue_reason.is_empty():
		accept.disabled = true
		body.add_child(_label(queue_reason, 14, WARNING))
		if capacity_full:
			var capacity_routes := HFlowContainer.new()
			capacity_routes.name = "CapacityResolutionActions"
			capacity_routes.add_theme_constant_override("h_separation", 8)
			capacity_routes.add_theme_constant_override("v_separation", 4)
			body.add_child(capacity_routes)
			var open_work := _button(UI.copy("queue_resume"), Callable(self, "_open_capacity_operations").bind(str(offer.id), price))
			open_work.name = "CapacityOpenOperations"
			open_work.custom_minimum_size.y = 30
			open_work.add_theme_font_size_override("font_size", maxi(12, int(12 * text_scale)))
			capacity_routes.add_child(open_work)
			var equipment_target := _capacity_equipment_target(g)
			if not equipment_target.is_empty():
				var open_equipment := _button(UI.copy("stock_equipment_tab"), Callable(self, "_open_capacity_equipment").bind(str(offer.id), price, equipment_target))
				open_equipment.name = "CapacityOpenEquipment"
				open_equipment.custom_minimum_size.y = 30
				open_equipment.add_theme_font_size_override("font_size", maxi(12, int(12 * text_scale)))
				capacity_routes.add_child(open_equipment)

	var decisions: Array = g.state.get("quote_decisions",[])
	if not decisions.is_empty():
		var decision: Dictionary = decisions[-1]
		if str(decision.get("offer_id","")) == str(offer.id) and str(decision.get("decision","")) == "declined":
			var declined := _label("前回: ¥%d / 予算超過" % int(decision.amount),14,WARNING); declined.name = "QuoteDeclined"; body.add_child(declined)

func _contract_operations_preview(body: VBoxContainer, offer: Dictionary, g, details_open: bool = false) -> void:
	if not g.has_method("offer_operations_preview"):
		return
	var preview: Dictionary = g.offer_operations_preview(offer)
	var panel := PanelContainer.new()
	panel.name = "OperationsPreview"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", M.surface(M.CANVAS, 12))
	body.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	var heading := HBoxContainer.new(); heading.add_theme_constant_override("separation",10); content.add_child(heading)
	var title := _label(UI.copy("v220_stock_coverage"), 14, M.INK)
	title.add_theme_font_override("font", heading_font); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var shortage := int(preview.get("shortage", 0)) > 0
	var summary := _label(UI.copy("v220_stock_required_count") % [int(preview.get("required",0)),int(preview.get("available",0)),int(preview.get("inbound",0))] + "  ·  " + UI.copy("v220_stock_shortage_count") % int(preview.get("shortage",0)) + "  ·  " + UI.copy("v220_purchase_needed") + " ¥%d" % int(preview.get("purchase_cost",0)),12,M.INK)
	summary.name="OperationsStockSummary"; content.add_child(summary); summary.visible = int(preview.get("required", 0)) > 0 or int(preview.get("shortage", 0)) > 0
	var facts := HFlowContainer.new()
	facts.name = "OperationsPreviewFacts"
	facts.add_theme_constant_override("h_separation", 6)
	facts.add_theme_constant_override("v_separation", 4)
	content.add_child(facts); facts.visible = details_open
	_preview_fact(facts, UI.copy("v220_stock_required"), preview.get("required", 0))
	_preview_fact(facts, UI.copy("v220_stock_available"), preview.get("available", 0))
	_preview_fact(facts, UI.copy("v220_stock_inbound"), preview.get("inbound", 0))
	_preview_fact(facts, UI.copy("v220_stock_reserved"), preview.get("reserved", 0))
	_preview_fact(facts, UI.copy("v220_stock_shortage"), preview.get("shortage", 0))
	_preview_fact(facts, UI.copy("v220_purchase_needed"), "¥%d" % int(preview.get("purchase_cost", 0)))
	_preview_fact(facts, UI.copy("v220_after_purchase"), "¥%d" % int(preview.get("cash_after_purchase", g.state.get("cash", 0))))
	var capacity_text := "%d / %d" % [int(preview.get("open_contracts", 0)), int(preview.get("contract_capacity", 0))]
	var staff_text := "%d / %d" % [int(preview.get("staff_count", 0)), int(preview.get("workforce_capacity", 2 + int(preview.get("staff_capacity", 0))))]
	_preview_fact(facts, UI.copy("v220_contract_slots"), capacity_text)
	_preview_fact(facts, UI.copy("v220_staff_seats"), staff_text)
	_preview_fact(facts, UI.copy("ops_payroll"), "¥%d" % int(preview.get("payroll_due", 0)))
	var details := _button(UI.copy("market_detail")); details.name="OperationsPreviewDetails"; details.toggle_mode=true; details.custom_minimum_size.y=30; details.add_theme_font_size_override("font_size",maxi(14,int(12*text_scale))); details.toggled.connect(func(expanded): facts.visible=expanded); heading.add_child(details)
	details.visible = not details_open
	var actions := HBoxContainer.new()
	actions.name = "OperationsPreviewActions"
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(actions)
	var procurement := _button(UI.copy("v220_prepare_stock"), Callable(self, "_open_quote_procurement").bind(str(offer.id)))
	procurement.name = "OperationsProcurement"
	procurement.custom_minimum_size.y = 30
	procurement.add_theme_font_size_override("font_size", maxi(12, int(12 * text_scale)))
	procurement.visible = shortage
	actions.add_child(procurement)
	var team := _button(UI.copy("v220_prepare_staff"), Callable(self, "_open_quote_team").bind(str(offer.id)))
	team.name = "OperationsStaffing"
	team.custom_minimum_size.y = 30
	team.add_theme_font_size_override("font_size", maxi(12, int(12 * text_scale)))
	# The team view remains useful when every seat is occupied (queues and shifts).
	team.disabled = false
	actions.add_child(team); team.visible = details_open
	details.toggled.connect(func(opened): team.visible = opened)

func _preview_fact(host: Container, label_text: String, value: Variant) -> void:
	var item := VBoxContainer.new()
	item.custom_minimum_size.x = 72
	item.add_theme_constant_override("separation", 1)
	host.add_child(item)
	item.add_child(_label(label_text, 10, GAME_THEME.FILTER))
	var value_label := _label(str(value), 12, GAME_THEME.WHITE)
	value_label.name = "Value"
	value_label.add_theme_font_override("font", UI.font(700))
	item.add_child(value_label)

func _open_quote_procurement(id: String) -> void:
	board_selected_id = id
	shop_view = "stock"
	open_panel("shop")

func _open_quote_team(id: String) -> void:
	board_selected_id = id
	open_panel("terminal")
	if is_instance_valid(desktop): desktop._show_app("team")

func _save_quote_route_draft(id: String, price: SpinBox) -> void:
	if not is_instance_valid(price): return
	price.apply()
	sales_quote_drafts[id] = roundi(price.value)

func _open_capacity_operations(id: String, price: SpinBox) -> void:
	_save_quote_route_draft(id, price)
	operations_choices.view = "contracts"
	open_panel("board")

func _capacity_equipment_target(g) -> String:
	for id in ["teamdesk", "annexdesk_a", "annexdesk_b"]:
		if id in g.state.get("equipment", []): continue
		var delivery: Dictionary = g.delivery_for(id) if g.has_method("delivery_for") else {}
		if not delivery.is_empty() or str(g.equipment_unavailable_reason(id)).is_empty(): return id
	var expansion: Dictionary = g.office_expansion_status() if g.has_method("office_expansion_status") else {}
	if not g.office_expanded() and str(expansion.get("status", "locked")) in ["locked", "ordered"]: return "office_expansion"
	return ""

func _open_capacity_equipment(id: String, price: SpinBox, equipment_id: String) -> void:
	_save_quote_route_draft(id, price)
	shop_view = "equipment"
	set_meta("equipment_selected", equipment_id)
	open_panel("shop")

func _sales_disclosure(parent: VBoxContainer, title: String, header: Container) -> VBoxContainer:
	var content := VBoxContainer.new()
	var toggle := _button(title)
	toggle.name = "QuoteConditions" if title == UI.copy("board_conditions") else "QuoteBrief"
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size.y = 28
	toggle.add_theme_font_size_override("font_size",maxi(14, int(14*text_scale)))
	for state in ["normal","pressed"]: toggle.add_theme_stylebox_override(state,UI.style(GAME_THEME.WHITE,Color.TRANSPARENT,0,2,0))
	toggle.add_theme_stylebox_override("hover",UI.style(GAME_THEME.CANVAS,Color.TRANSPARENT,0,2,0))
	for state in ["font_color","font_pressed_color","font_hover_color","font_focus_color"]: toggle.add_theme_color_override(state,INK)
	toggle.text="▸ " + title
	toggle.toggled.connect(func(opened): content.visible=opened; toggle.text=("▾ " if opened else "▸ ") + title)
	header.add_child(toggle)
	parent.add_child(content)
	content.hide()
	return content

func _sales_fonts(node: Node) -> void:
	if node is Control: node.add_theme_font_override("font",UI.font(400))
	for child in node.get_children(): _sales_fonts(child)

func _submit_quote(id: String, amount: int) -> void:
	var g := _game()
	if is_instance_valid(desktop) and desktop.has_method("_save_session"):
		if not bool(desktop._save_session()):
			var failed := _queue_copy("queue_save_failed", "")
			if not failed.is_empty() and is_instance_valid(status_label): status_label.text = failed
			return
	var quote_ok: bool = bool(g.set_offer_quote(id,amount))
	if not quote_ok:
		_management_feedback("見積を送信できませんでした。入力を残しています。受注済み・受付終了の案件でないか確認し、再試行してください。")
		return
	sales_quote_drafts.erase(id)
	if g.choose_contract(id):
		board_selected_id = ""
		_select_contract(id)
	else: _select_contract(id)


func _filter_board(value: String) -> void:
	board_filter=value; board_page=0; open_panel("sales")
func _page_board(delta: int) -> void:
	board_page+=delta; open_panel("sales")
func _start_free_career() -> void:
	if _game().start_free_career(): board_page=0; open_panel("board")

func _crew(kind: String) -> void:
	var g:=_game(); var job: Dictionary=g.state.assignments.get(kind,{})
	var crew_minutes: float = g.team_work_duration(kind) if g.has_method("team_work_duration") else (8.0 if kind=="aya" else 15.0)
	modal_body.add_child(_label("作業 %d分 / 費用 ¥100" % int(ceil(crew_minutes)),15,TEAL))
	var progress:=ProgressBar.new(); progress.custom_minimum_size.y=12; progress.show_percentage=false; modal_body.add_child(progress)
	var state_label:=_label(str(job.get("phase","待機中")),18); modal_body.add_child(state_label); controls.crew_progress=progress; controls.crew_status=state_label; controls.crew_id=kind
	var unavailable:=str(g.staff_availability(kind))
	var assign:=_button("作業を依頼する",_assign_colleague.bind(kind)); assign.disabled=not g.state.accepted or g.current_done() or not unavailable.is_empty(); assign.tooltip_text=unavailable; modal_body.add_child(assign)
	if not unavailable.is_empty():modal_body.add_child(_label(unavailable,14,MUTED))
	modal_body.add_child(_button("PCで成果確認",_open_team))
	_update_crew_status()

func _open_team() -> void:
	open_panel("terminal"); desktop._show_app("team")

func _update_crew_status() -> void:
	if not controls.has("crew_status") or not is_instance_valid(controls.crew_status): return
	var job: Dictionary=_game().state.assignments.get(controls.get("crew_id",""),{})
	controls.crew_status.text=str(job.get("phase","待機中"))
	controls.crew_progress.value=(1.0-float(job.get("remaining",0.0))/maxf(1.0,float(job.get("total",1.0))))*100.0 if not job.is_empty() else 0.0

func _choose_strategy(id: String) -> void:
	var g := _game()
	if g != null and g.has_method("choose_strategy"):
		if not g.choose_strategy(id):return
		if is_instance_valid(guided_intro) and guided_intro.active():
			close_panel(); return
		if not g.state.get("career_mode",false):g.start_free_career()
		open_panel("board")

func _choose_contract(id: String) -> void:
	var g := _game()
	if g != null and g.has_method("choose_contract"):
		if g.choose_contract(id): open_panel("terminal")

func _staffing() -> void:
	preload("res://scripts/staffing_panel.gd").build(self)

func _company() -> void:
	var g := _game(); if g == null: return
	_maintenance_progress_labels.clear()
	_maintenance_ui_signature = _maintenance_signature(g)
	_operating_ui_signature = _operating_signature(g)
	var view := str(get_meta("company_view", "overview"))
	var nav := HBoxContainer.new(); nav.name = "CompanyViews"; nav.add_theme_constant_override("separation", 12); modal_body.add_child(nav)
	for spec in [["overview", UI.copy("rmd_overview")], ["growth", UI.copy("v220_growth")], ["care", "顧客保守"]]:
		var tab := _button(str(spec[1]), _select_company_view.bind(str(spec[0])))
		tab.name = "CompanyView_" + str(spec[0]); M.button(tab, "tab", view == str(spec[0])); nav.add_child(tab)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; nav.add_child(spacer)
	var menu := MenuButton.new(); menu.text = "···"; menu.name = "CompanyMenu"; M.button(menu, "quiet"); nav.add_child(menu)
	menu.get_popup().add_item("名前の変更", 0); menu.get_popup().add_item("営業記録書き出し", 1)
	menu.get_popup().id_pressed.connect(func(id): _open_profile_editor() if id == 0 else _report())
	modal_body.add_child(M.rule())
	match view:
		"growth": _company_growth(g)
		"care": _company_care(g)
		_: _company_operating_desk(g, g.company_operating_summary())

func _select_company_view(view: String) -> void:
	set_meta("company_view", view); open_panel("company")

func _company_growth(g) -> void:
	var level: Dictionary = g.company_level()
	var details := modal_body
	details.add_child(_label("Lv.%d   ·   保有pt %d" % [level.level,g.skill_points()],16,TEAL))
	var unlock:=_label("次の解放: %s" % level.next_unlock,13,MUTED); unlock.tooltip_text="あと %d XP" % maxi(0,int(level.next_threshold)-int(level.xp)); details.add_child(unlock)
	var xp := ProgressBar.new(); xp.value=float(level.progress)*100.0; xp.show_percentage=false; xp.custom_minimum_size.y=6; details.add_child(xp)
	var branches := VBoxContainer.new(); branches.size_flags_vertical = Control.SIZE_SHRINK_BEGIN; branches.add_theme_constant_override("separation", 10); details.add_child(branches)
	for skill in g.skill_catalog():
		var card := PanelContainer.new(); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN; card.add_theme_stylebox_override("panel", M.surface(M.CANVAS, 12)); branches.add_child(card)
		var row := HBoxContainer.new(); row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN; row.add_theme_constant_override("separation", 18); card.add_child(row)
		var column := VBoxContainer.new(); column.size_flags_vertical = Control.SIZE_SHRINK_CENTER; column.custom_minimum_size.x = 220; column.add_theme_constant_override("separation", 3); row.add_child(column)
		var skill_title := _label(skill.title, 16, M.INK); skill_title.autowrap_mode = TextServer.AUTOWRAP_OFF; skill_title.clip_text = true; skill_title.tooltip_text = str(skill.title); column.add_child(skill_title)
		column.add_child(_label("Lv.%d / %d" % [int(skill.rank),int(skill.max_rank)], 12, M.MUTED))
		var stages:=HBoxContainer.new(); stages.size_flags_horizontal=Control.SIZE_EXPAND_FILL; stages.size_flags_vertical=Control.SIZE_SHRINK_CENTER; stages.custom_minimum_size.y=7; stages.add_theme_constant_override("separation",3); column.add_child(stages)
		for i in 10:
			var stage:=PanelContainer.new(); stage.custom_minimum_size=Vector2(12,7); stage.size_flags_horizontal=Control.SIZE_EXPAND_FILL; stage.size_flags_vertical=Control.SIZE_SHRINK_CENTER; stage.add_theme_stylebox_override("panel",M.surface(M.ACCENT if i < skill.rank else M.LINE,0)); stages.add_child(stage)
		var effects := VBoxContainer.new(); effects.size_flags_horizontal=Control.SIZE_EXPAND_FILL; effects.size_flags_vertical=Control.SIZE_SHRINK_CENTER; effects.add_theme_constant_override("separation",4); row.add_child(effects)
		effects.add_child(_label("現在: %s" % str(skill.get("current_effect", "未習得")), 12, M.INK))
		var case_unlocks: Array = g.skill_case_unlocks(str(skill.id))
		var next_effect := "次: %s" % (str(skill.get("next_effect", "最大ランク")) if skill.rank < int(skill.max_rank) else "最大ランク")
		if not case_unlocks.is_empty(): next_effect = UI.copy("firm_unlocks") % " / ".join(case_unlocks.slice(0,2))
		var next_label := _label(next_effect, 12, M.MUTED)
		next_label.name = "SkillNext_" + str(skill.id)
		next_label.tooltip_text = "\n".join(case_unlocks)
		effects.add_child(next_label)
		var learn := _button("習得 / 1 pt", Callable(self, "_learn_skill").bind(skill.id)); learn.custom_minimum_size=Vector2(106,40); learn.size_flags_vertical=Control.SIZE_SHRINK_CENTER; learn.disabled = skill.rank >= int(skill.max_rank) or g.skill_points() <= 0 or str(g.state.strategy) == ""; M.button(learn, "primary"); row.add_child(learn)

func _company_care(g) -> void:
	var portfolio: Dictionary = g.care_portfolio()
	var details := modal_body
	var compact_company := root.size.x < 1100
	if portfolio.get("clients", []).is_empty():
		details.add_child(_label("保守契約なし", 20, M.MUTED))
		var browse := _button(UI.copy("ops_sales").get_slice("・", 0), open_panel.bind("sales")); M.button(browse, "primary"); browse.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; details.add_child(browse)
		return
	if not portfolio.get("clients", []).is_empty():
		var contract_rates := UI.copy("care_contract_rates", "")
		var contract_text := contract_rates % [int(portfolio.get("gross_daily", 0)), int(portfolio.get("service_cost_daily", 0)), int(portfolio.get("net_daily", 0))] if not contract_rates.is_empty() else ""
		var summary := _label(contract_text, 15, TEAL); summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; details.add_child(summary)
		if g.has_method("maintenance_summary"):
			var maintenance_summary: Dictionary = g.maintenance_summary()
			var count_template := UI.copy("care_summary", "")
			if not count_template.is_empty() and int(maintenance_summary.get("pending", 0)) + int(maintenance_summary.get("working", 0)) + int(maintenance_summary.get("failed", 0)) > 0: details.add_child(_label(count_template % [int(maintenance_summary.get("pending", 0)), int(maintenance_summary.get("working", 0)), int(maintenance_summary.get("done", 0)), int(maintenance_summary.get("failed", 0))], 14, MUTED))
			var today_template := UI.copy("care_today", "")
			if not today_template.is_empty() and int(maintenance_summary.get("earned", 0)) + int(maintenance_summary.get("service_cost", 0)) > 0: details.add_child(_label(today_template % [int(maintenance_summary.get("earned", 0)), int(maintenance_summary.get("service_cost", 0)), int(maintenance_summary.get("net", 0))], 14, TEAL))
	var table := VBoxContainer.new(); table.size_flags_horizontal = Control.SIZE_EXPAND_FILL; table.add_theme_constant_override("separation", 4); details.add_child(table)
	var widths: Array = [150, 88, 100, 84, 64] if compact_company else [220, 100, 120, 100, 80]
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation", 8); table.add_child(header)
	for index in 5:
		var heading: Label = _label(["顧客", "日額", "満足度", "状態", "実績"][index], 12, MUTED); heading.custom_minimum_size.x = widths[index]; heading.autowrap_mode = TextServer.AUTOWRAP_OFF; header.add_child(heading)
	if portfolio.get("clients", []).is_empty(): table.add_child(_label("保守契約なし", 14, MUTED))
	for client in portfolio.get("clients", []):
		var relation: Dictionary = client
		var client_name := str(relation.get("client", ""))
		var history_relation: Dictionary = g.state.get("customer_relations", {}).get(client_name, {})
		var status_text: String = {"active":"稼働","pending":"納品待ち","suspended":"停止"}.get(str(relation.get("status", "")),"停止")
		var client_box := VBoxContainer.new(); client_box.add_theme_constant_override("separation", 3); table.add_child(client_box)
		var care_top_row := HBoxContainer.new(); care_top_row.add_theme_constant_override("separation", 8); client_box.add_child(care_top_row)
		var values: Array = [client_name, "¥%d" % int(relation.get("fee", 0)), "%d / 100" % int(relation.get("satisfaction", 70)), status_text, "%d件" % int(history_relation.get("completed_count", 0))]
		var colors: Array = [INK, TEAL, INK, TEAL if status_text == "稼働" else ORANGE, MUTED]
		for index in values.size():
			var cell: Label = _label(str(values[index]), 13, colors[index]); cell.custom_minimum_size.x = widths[index]; cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; cell.autowrap_mode = TextServer.AUTOWRAP_OFF; cell.clip_text = true; cell.tooltip_text = str(values[index]); care_top_row.add_child(cell)
		var choose := _button(UI.copy("market_detail"), func(): set_meta("company_client", client_name); _refresh_maintenance_panel())
		choose.name = "CompanyClient_" + client_name.sha256_text().left(10); M.button(choose, "quiet", str(get_meta("company_client", "")) == client_name); care_top_row.add_child(choose)
		if g.has_method("maintenance_jobs") and str(get_meta("company_client", "")) == client_name:
			var owner_row:=HFlowContainer.new();owner_row.add_theme_constant_override("h_separation",8);owner_row.add_theme_constant_override("v_separation",5);client_box.add_child(owner_row)
			var scope_label:=_label(UI.copy("care_scope_count") % g._maintenance_targets_for(client_name).size(),12,MUTED);scope_label.autowrap_mode=TextServer.AUTOWRAP_OFF;scope_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER;owner_row.add_child(scope_label)
			var owner_label:=_label(UI.copy("care_owner"),12,MUTED);owner_label.autowrap_mode=TextServer.AUTOWRAP_OFF;owner_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER;owner_row.add_child(owner_label)
			var owner_select:=OptionButton.new();owner_select.name="CareOwner_"+client_name.sha256_text().left(10);owner_select.custom_minimum_size.x=150
			owner_select.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			owner_select.add_item(UI.copy("care_owner_manual"));owner_select.set_item_metadata(0,"")
			var chosen:=str(g.maintenance_owner(client_name));var found_owner:=chosen.is_empty()
			for member in g.maintenance_owner_candidates():
				owner_select.add_item(str(member.name));owner_select.set_item_metadata(owner_select.item_count-1,str(member.id))
				if str(member.id)==chosen:owner_select.select(owner_select.item_count-1);found_owner=true
			if not found_owner:
				owner_select.add_item(UI.copy("care_owner_unavailable"));owner_select.select(owner_select.item_count-1);owner_select.set_item_disabled(owner_select.item_count-1,true)
			owner_select.item_selected.connect(func(index):
				g.set_maintenance_owner(client_name,str(owner_select.get_item_metadata(index)))
				_refresh_maintenance_panel())
			owner_row.add_child(owner_select)
			var maintenance: Dictionary = {}
			for job in g.maintenance_jobs():
				if str(job.get("client", "")) == client_name: maintenance = job; break
			var care_row := HFlowContainer.new(); care_row.add_theme_constant_override("h_separation", 6); care_row.add_theme_constant_override("v_separation", 6); client_box.add_child(care_row)
			var care_status := str(maintenance.get("status", ""))
			var care_key := "care_status_" + (care_status if not care_status.is_empty() else "idle")
			var care_state := _label(UI.copy(care_key, ""), 12, TEAL if care_status in ["done", "legacy"] else ORANGE if care_status in ["working", "failed"] else MUTED); care_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL; care_state.autowrap_mode = TextServer.AUTOWRAP_OFF; care_row.add_child(care_state)
			var incident: Dictionary = g.care_incident(client_name) if g.has_method("care_incident") else {}
			var incident_status := str(incident.get("status", ""))
			if incident_status in ["detected", "working", "recheck"]:
				care_state.text = UI.copy("care_incident_"+incident_status)
			var current_assignee := str(maintenance.get("assignee", "")); var assignee_text := UI.copy("care_assignee_unassigned", "")
			if not g.colleague_role(current_assignee).is_empty():
				var member_template := UI.copy("care_assignee_member", ""); assignee_text = member_template % g.member_name(current_assignee) if not member_template.is_empty() else g.member_name(current_assignee)
			elif current_assignee == "player":
				var self_template := UI.copy("care_assignee_self", ""); assignee_text = self_template % g.player_name() if not self_template.is_empty() else g.player_name()
			elif current_assignee == "verified": assignee_text = UI.copy("care_maintenance_signed")
			var assignee_label := _label(assignee_text, 12, MUTED); assignee_label.custom_minimum_size.x = 74; assignee_label.autowrap_mode = TextServer.AUTOWRAP_OFF; care_row.add_child(assignee_label)
			if care_status == "working":
				var progress_template := UI.copy("care_progress", "")
				if not progress_template.is_empty():
					var progress_label := _label(progress_template % [int(float(maintenance.get("total", 0)) - float(maintenance.get("remaining", 0))), int(maintenance.get("total", 0))], 12, MUTED); progress_label.custom_minimum_size.x = 72; care_row.add_child(progress_label)
					_maintenance_progress_labels[client_name] = progress_label
			var result := _button(UI.copy("care_result", ""), Callable(self, "_show_maintenance_result").bind(client_name)); result.name = "CareResult_" + client_name.sha256_text().left(10); result.disabled = care_status not in ["done", "failed"]; care_row.add_child(result)
			var self_check_text := UI.copy("care_incident_reinspect", "") if incident_status == "recheck" else UI.copy("care_self_check", "")
			var self_check := _button(self_check_text, Callable(self, "_run_maintenance").bind(client_name)); self_check.name = "CareSelfCheck_" + client_name.sha256_text().left(10); self_check.disabled = not g.has_method("can_run_maintenance") or not g.can_run_maintenance(client_name); care_row.add_child(self_check)
			if incident_status in ["detected", "working"] and g.has_method("open_maintenance_incident"):
				var incident_button := _button(UI.copy("care_incident_open", ""), Callable(self, "_open_maintenance_incident").bind(client_name)); incident_button.name = "CareIncident_"+client_name.sha256_text().left(10)
				var incident_reason := str(g.maintenance_incident_reason(client_name)) if g.has_method("maintenance_incident_reason") else ""
				incident_button.disabled = not incident_reason.is_empty(); incident_button.tooltip_text = incident_reason; care_row.add_child(incident_button)
			for member in g.team_members():
				var assignee := str(member.id)
				var delegate_template := UI.copy("care_assign_member", ""); var delegate_text: String = delegate_template % str(member.name) if not delegate_template.is_empty() else str(member.name)
				var delegate := _button(delegate_text, Callable(self, "_assign_maintenance").bind(client_name, assignee))
				var unavailable := str(g.staff_availability(assignee,"maintenance"))
				delegate.name = "Maintenance_"+assignee
				delegate.disabled = not g.can_run_maintenance(client_name) or not unavailable.is_empty()
				delegate.tooltip_text = unavailable; care_row.add_child(delegate)

func _company_operating_desk(g, summary: Dictionary) -> void:
	var panel := VBoxContainer.new(); panel.name = "OperatingDesk"; panel.add_theme_constant_override("separation", 18); modal_body.add_child(panel)
	var identity := HBoxContainer.new(); identity.add_theme_constant_override("separation", 16); panel.add_child(identity)
	var company := _label(g.company_name(), 26, M.INK); company.name = "CompanyBrand"; company.clip_text = true; company.autowrap_mode = TextServer.AUTOWRAP_OFF; company.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; company.tooltip_text = g.company_name(); company.size_flags_horizontal = Control.SIZE_EXPAND_FILL; identity.add_child(company)
	var level: Dictionary = g.company_level(); var level_label := _label("Lv.%d" % int(level.level), 18, M.ACCENT); level_label.autowrap_mode = TextServer.AUTOWRAP_OFF; identity.add_child(level_label)
	var metrics := HBoxContainer.new(); metrics.name = "OperatingMetrics"; metrics.add_theme_constant_override("separation", 36); panel.add_child(metrics)
	_operating_metric(metrics, UI.copy("billing_receivable_total"), "¥" + _group_number(_summary_number(summary, "receivables", summary.get("receivable_total", 0))))
	_operating_metric(metrics, UI.copy("ops_payroll"), "¥" + _group_number(_summary_number(summary, "payroll_due", 0)))
	_operating_metric(metrics, UI.copy("v220_contract_slots"), "%d / %d" % [_summary_number(summary, "open_contracts", 0), _summary_number(summary, "contract_capacity", 0)])
	panel.add_child(M.rule())
	var attention := VBoxContainer.new(); attention.name = "OperatingAttention"; attention.add_theme_constant_override("separation", 12); panel.add_child(attention)
	var attention_heading := _label(UI.copy("v220_attention"), 14, M.MUTED); attention.add_child(attention_heading)
	var count := 0
	for item in [["receiving_count", "v220_receive_count", _open_company_receiving], ["stock_shortage_total", "v220_stock_shortage_count", _open_company_procurement], ["draft_invoice_count", "v220_invoice_count", _open_company_billing], ["maintenance_pending", "v220_maintenance_count", _open_company_maintenance]]:
		var amount := _summary_number(summary, str(item[0]), 0)
		if amount > 0:
			_operating_attention_row(attention, UI.copy(str(item[1])), amount, item[2]); count += 1
	var arrears := _summary_number(summary, "payroll_arrears", 0)
	if arrears > 0:
		var debt := _label(UI.copy("ops_arrears") + "  ¥" + _group_number(arrears), 15, M.DANGER); attention.add_child(debt)
		var payroll := _button(UI.copy("staffing_title"), open_panel.bind("staffing")); M.button(payroll, "quiet"); attention.add_child(payroll); count += 1
	attention_heading.visible = count > 0
	if count == 0:
		attention.add_child(_label(UI.copy("v220_attention_clear"), 17, M.ACCENT))
		var browse := _button(UI.copy("ops_sales").get_slice("・", 0), open_panel.bind("sales")); browse.name = "CompanyNext"; browse.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; M.button(browse, "primary"); attention.add_child(browse)
	var capacity := HBoxContainer.new(); capacity.name = "OperatingCapacity"; capacity.add_theme_constant_override("separation", 32); panel.add_child(capacity)
	var staff_current := _summary_number(summary, "staff_count", 0)
	_operating_metric(capacity, UI.copy("v220_staff_seats"), "%d / %d" % [staff_current, _summary_number(summary, "workforce_capacity", staff_current)])
	_operating_metric(capacity, UI.copy("v220_installed"), str(_summary_number(summary, "installed_equipment_count", 0)))
	if _summary_number(summary, "pending_equipment_count", 0) > 0:
		_operating_metric(capacity, UI.copy("v220_equipment_pending"), str(_summary_number(summary, "pending_equipment_count", 0)))

func _summary_number(summary: Dictionary, key: String, fallback: Variant = 0) -> int:
	var value: Variant = summary.get(key, fallback)
	if value is Dictionary:
		var data: Dictionary = value
		return int(data.get("count", data.get("total", data.get("value", fallback))))
	return int(value)

func _operating_metric(host: Container, title: String, value: String) -> void:
	var item := VBoxContainer.new()
	item.custom_minimum_size.x = 154
	item.add_theme_constant_override("separation", 1)
	host.add_child(item)
	item.add_child(_label(title, 11, M.MUTED))
	var amount := _label(value, 23, M.INK)
	amount.add_theme_font_override("font", UI.font(700))
	item.add_child(amount)

func _operating_attention_row(host: VBoxContainer, title: String, count: int, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.name = "OperatingAttention_" + str(host.get_child_count())
	row.add_theme_constant_override("separation", 8)
	host.add_child(row)
	var row_text := title % count if title.contains("%") else "%s  %d" % [title, count]
	var label := _label(row_text, 12, M.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := _button(UI.copy("business_details", "開く"), action)
	if action.get_method() == "_open_company_billing": button.name = "CompanyBilling"
	button.custom_minimum_size.x = 70
	M.button(button, "primary" if host.get_child_count() == 2 else "quiet")
	row.add_child(button)

func _open_company_procurement() -> void:
	shop_view = "stock"
	set_meta("stock_view", "catalog")
	open_panel("shop")

func _open_company_receiving() -> void:
	shop_view = "stock"
	set_meta("stock_view", "inventory")
	open_panel("shop")

func _open_company_maintenance() -> void:
	operations_choices.view = "maintenance"
	open_panel("board")

func _open_company_billing() -> void:
	_open_billing()

func _return_to_quote() -> void:
	open_panel("sales")

func _learn_skill(id: String) -> void:
	var g := _game()
	if g != null and g.has_method("learn_skill") and g.learn_skill(id): open_panel("company")

func _assign_colleague(kind: String) -> void:
	var g := _game()
	if g != null:
		g.assign_colleague(kind)
		open_panel(kind)

func _run_maintenance(client: String) -> void:
	var g := _game()
	if g != null and g.has_method("run_maintenance") and g.run_maintenance(client): open_panel("company")

func _open_maintenance_incident(client: String) -> void:
	var g := _game()
	if g == null or not g.has_method("open_maintenance_incident"): return
	if is_instance_valid(desktop) and desktop.has_method("_save_session") and not desktop._save_session(): return
	if g.open_maintenance_incident(client): open_panel("terminal")

func _assign_maintenance(client: String, assignee: String) -> void:
	var g := _game()
	if g != null and g.has_method("assign_maintenance") and g.assign_maintenance(client, assignee): open_panel("company")

func _show_maintenance_result(client: String) -> void:
	var g := _game()
	if g == null or not g.has_method("maintenance_result"): return
	open_panel("terminal")
	var result := str(g.maintenance_result(client)); var title_template := UI.copy("care_result_title", ""); var title := title_template % client if not title_template.is_empty() else client
	if is_instance_valid(desktop) and desktop.has_method("_append"): desktop._append(title + "\n" + (result if not result.is_empty() else UI.copy("care_result_empty", "")))

func _shop() -> void:
	EQUIPMENT_PANEL.build(self)

func _show_delivery_help() -> void:
	if is_instance_valid(status_label): status_label.text = ""


func _buy(id: String) -> void:
	var g := _game()
	if g == null: return
	if g.buy_equipment(id): open_panel("shop")
	else:
		var reason := str(g.equipment_unavailable_reason(id))
		if reason.is_empty() and int(g.state.cash) < int(g.equipment_price(id)): reason = "購入資金が不足しています。"
		_management_feedback(reason if not reason.is_empty() else "発注を保存できませんでした。残高と注文を確認して再試行してください。")

func _door() -> void:
	var g := _game(); if g == null: return
	if g.state.get("career_mode",false):OPERATIONS_PANEL.closeout(self,false);return
	modal_body.add_child(_label("現在時刻  %s" % (g.business_clock() if g.has_method("business_clock") else "09:00"),22,TEAL))
	if g.state.game_complete:
		modal_body.add_child(_button("初週決算確認", Callable(self, "open_panel").bind("ending")))
		modal_body.add_child(_button("営業を続ける", Callable(self, "_continue_business")))
		return
	var footer_space := Control.new(); footer_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL; modal_footer.add_child(footer_space)
	var end_reason := str(g.end_day_reason()) if g.has_method("end_day_reason") else (str(g.maintenance_end_day_reason()) if g.has_method("maintenance_end_day_reason") else ""); var b := _button(_queue_copy("queue_overnight", ""), Callable(self, "_end_day")); b.name="DaySettle"; b.disabled = g.has_method("can_end_day") and not bool(g.can_end_day()) or (not g.has_method("can_end_day") and not end_reason.is_empty()); b.tooltip_text = end_reason if not end_reason.is_empty() else ""; M.button(b,"primary"); modal_footer.add_child(b)
	if not end_reason.is_empty(): modal_body.add_child(_label(end_reason,16,WARNING))

func _end_day() -> void:
	var g := _game()
	if g != null and g.end_day():
		close_panel()
		update_hud()
		if g.state.get("game_complete", false): open_panel("ending")
		elif g.state.get("career_mode",false):open_panel("day_review")
	elif g != null and g.has_method("end_day_reason") and not str(g.end_day_reason()).is_empty() and is_instance_valid(status_label):
		status_label.text = str(g.end_day_reason())
	elif g != null and g.state.get("career_mode",false):
		_operations_feedback(UI.copy("ops_result_failed"))

func _pause() -> void:
	modal_body.add_child(_ribbon(UI.copy("pause_resume","続ける"),ORANGE,close_panel))
	modal_body.add_child(_ribbon("セーブ",TEAL,_save))
	modal_body.add_child(_ribbon(UI.copy("title_options","オプション"),SURFACE,_open_settings))
	modal_body.add_child(_ribbon(UI.copy("title_manual","チュートリアル"),SURFACE,open_panel.bind("help")))
	modal_body.add_child(_ribbon("タイトルへ戻る",RED,open_main_menu))
	var note:=_label("Esc で戻る",16,Color.WHITE); note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; modal_body.add_child(note)
	var feedback:=_label("",16,Color.WHITE); feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; modal_body.add_child(feedback); controls.pause_feedback=feedback

func _save() -> void:
	var g := _game()
	if g != null:
		var message := UI.copy("save_ok","保存完了") if g.save_game() else UI.copy("save_failed","保存失敗。既存データ保持")
		status_label.text=message
		if controls.has("pause_feedback") and is_instance_valid(controls.pause_feedback): controls.pause_feedback.text=message

func _report() -> void:
	var g := _game()
	if g != null and g.has_method("export_report"):
		var path: String = g.export_report()
		status_label.text = "書き出し: %s" % path if not path.is_empty() else "書き出し失敗"

func _help() -> void:
	if is_instance_valid(next_task_guide):
		var next_toggle := _button(UI.copy("next_hide" if next_task_guide.enabled() else "next_show"), func():
			next_task_guide.set_enabled(not next_task_guide.enabled()); open_panel("help"))
		next_toggle.name = "NextTaskHelpToggle"; modal_body.add_child(next_toggle)
	if is_instance_valid(guided_intro) and _game().state.has("guided_intro") and not bool(_game().state.get("career_mode",false)) and int(_game().state.get("chapter",0))==0 and not bool(_game().state.guided_intro.get("completed",false)):
		var resume := _button(UI.copy("guide_resume"),func():
			guided_intro.resume(); close_panel())
		resume.name="GuideResume"; modal_body.add_child(resume)
	var page: Dictionary = TUTORIAL_PAGES[tutorial_page]
	var progress := HBoxContainer.new(); progress.add_theme_constant_override("separation",6); modal_body.add_child(progress)
	for index in TUTORIAL_PAGES.size():
		var tab := _button(str(index + 1)); tab.name="TutorialTab_%d" % index; tab.tooltip_text=str(TUTORIAL_PAGES[index].tab); tab.custom_minimum_size=Vector2(44,34); tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tab.add_theme_font_size_override("font_size",14)
		tab.add_theme_stylebox_override("normal",_surface(GAME_THEME.BUY if index==tutorial_page else Color("dce5e7"),Color.TRANSPARENT,4,2))
		tab.add_theme_stylebox_override("hover",_surface(GAME_THEME.WARNING,Color.TRANSPARENT,4,2)); tab.add_theme_color_override("font_color",GAME_THEME.FOOTER)
		tab.pressed.connect(_tutorial_select.bind(index)); progress.add_child(tab)
	var card := PanelContainer.new(); card.name="TutorialCard"; card.add_theme_stylebox_override("panel",_surface(GAME_THEME.FOOTER,GAME_THEME.TAB,20,18)); modal_body.add_child(card)
	var content_box := VBoxContainer.new(); content_box.add_theme_constant_override("separation",10); card.add_child(content_box)
	var heading := HBoxContainer.new(); heading.add_theme_constant_override("separation",16); content_box.add_child(heading)
	var number := _label("%02d" % (tutorial_page + 1),38,GAME_THEME.BUY); number.custom_minimum_size.x=70; number.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; heading.add_child(number)
	var titles := VBoxContainer.new(); titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL; titles.add_theme_constant_override("separation",0); heading.add_child(titles)
	var eyebrow := _label(str(page.eyebrow),11,CYAN); eyebrow.autowrap_mode=TextServer.AUTOWRAP_OFF; titles.add_child(eyebrow)
	var title := _label(str(page.title),25,GAME_THEME.WHITE); title.name="TutorialTitle"; titles.add_child(title)
	var body := _label(str(page.body),16,Color("dce9ed")); body.name="TutorialBody"; body.add_theme_constant_override("line_spacing",4); content_box.add_child(body)
	var details := GridContainer.new(); details.columns=1 if root.size.x<1040 or text_scale>1.15 else 2; details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; details.add_theme_constant_override("h_separation",18); details.add_theme_constant_override("v_separation",10); content_box.add_child(details)
	var key_panel := PanelContainer.new(); key_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; key_panel.add_theme_stylebox_override("panel",_surface(Color("16333b"),Color("31545d"),12,10)); details.add_child(key_panel)
	var key_box := VBoxContainer.new(); key_box.add_theme_constant_override("separation",5); key_panel.add_child(key_box); key_box.add_child(_label("使う操作",13,CYAN))
	for entry in page.keys:
		var key_row := HBoxContainer.new(); key_row.add_theme_constant_override("separation",10); key_box.add_child(key_row)
		var cap_panel := PanelContainer.new(); cap_panel.custom_minimum_size.x=94; cap_panel.add_theme_stylebox_override("panel",_surface(Color("f5f8f8"),Color("8ea5ac"),6,3)); key_row.add_child(cap_panel)
		var cap := _label(str(entry[0]),13,GAME_THEME.FOOTER); cap.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; cap_panel.add_child(cap)
		var action := _label(str(entry[1]),14,Color("dce9ed")); action.size_flags_horizontal=Control.SIZE_EXPAND_FILL; key_row.add_child(action)
	var task_panel := PanelContainer.new(); task_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; task_panel.add_theme_stylebox_override("panel",_surface(Color("16333b"),Color("31545d"),12,10)); details.add_child(task_panel)
	var task_box := VBoxContainer.new(); task_box.add_theme_constant_override("separation",5); task_panel.add_child(task_box); task_box.add_child(_label("この画面で覚えること",13,CYAN))
	for index in page.steps.size():
		var task := _label("%d　%s" % [index+1,str(page.steps[index])],14,GAME_THEME.WHITE); task.name="TutorialStep_%d" % index; task_box.add_child(task)
	var note_panel := PanelContainer.new(); note_panel.add_theme_stylebox_override("panel",_surface(Color("fff3c7"),GAME_THEME.WARNING,12,7)); content_box.add_child(note_panel)
	var note := _label(str(page.note),14,GAME_THEME.FOOTER); note.name="TutorialNote"; note_panel.add_child(note)
	var previous := _button("← 前へ",_tutorial_select.bind(tutorial_page-1)); previous.name="TutorialPrevious"; previous.disabled=tutorial_page==0; modal_footer.add_child(previous)
	var page_label := _label("%d / %d　%s" % [tutorial_page+1,TUTORIAL_PAGES.size(),str(page.tab)],14,MUTED); page_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; modal_footer.add_child(page_label)
	var next_text := "完了" if tutorial_page==TUTORIAL_PAGES.size()-1 else "次へ →"
	var next_action: Callable = close_panel if tutorial_page==TUTORIAL_PAGES.size()-1 else _tutorial_select.bind(tutorial_page+1)
	var next := _button(next_text,next_action); next.name="TutorialNext"; GAME_THEME.primary(next,GAME_THEME.BUY); modal_footer.add_child(next)

func _tutorial_select(index: int) -> void:
	tutorial_page=clampi(index,0,TUTORIAL_PAGES.size()-1)
	open_panel("help")

func _coffee() -> void:
	coffee_cup = CoffeeCup.new(); coffee_cup.custom_minimum_size = Vector2(260, 112); coffee_cup.phase = coffee_phase; coffee_cup.progress = coffee_elapsed / 2.0; modal_body.add_child(coffee_cup)
	coffee_progress = ProgressBar.new(); coffee_progress.max_value = 100.0; coffee_progress.value = 100.0 if coffee_phase in ["ready", "drunk"] else (coffee_elapsed / 2.0 * 100.0); coffee_progress.show_percentage = false; coffee_progress.custom_minimum_size.y = 14; modal_body.add_child(coffee_progress)
	coffee_status = _label("", 19, INK); modal_body.add_child(coffee_status)
	if coffee_phase == "brewing": coffee_status.text = "抽出中…"
	elif coffee_phase == "ready": coffee_status.text = UI.copy("coffee_ready","コーヒーが淹れ上がりました")
	elif coffee_phase == "drunk": coffee_status.text = UI.copy("coffee_finish","休憩を終える")
	coffee_action = _button(UI.copy("coffee_brew","淹れる") if coffee_phase == "idle" else (UI.copy("coffee_drink","飲む") if coffee_phase == "ready" else UI.copy("coffee_finish","休憩を終える")), _coffee_action)
	coffee_action.disabled = coffee_phase == "brewing"; modal_footer.add_child(coffee_action)

func _coffee_action() -> void:
	if coffee_phase == "idle":
		coffee_phase = "brewing"; coffee_elapsed = 0.0
		if is_instance_valid(coffee_cup): coffee_cup.phase = coffee_phase; coffee_cup.progress = 0.0; coffee_cup.queue_redraw()
		if is_instance_valid(coffee_action): coffee_action.disabled = true; coffee_action.text = UI.copy("coffee_brew","淹れる")+"…"
		if is_instance_valid(coffee_status): coffee_status.text = "抽出中…"
	elif coffee_phase == "ready":
		coffee_phase = "drunk"
		if is_instance_valid(coffee_cup): coffee_cup.phase = coffee_phase; coffee_cup.queue_redraw()
		if is_instance_valid(coffee_status): coffee_status.text = UI.copy("coffee_finish","休憩を終える")
		if is_instance_valid(coffee_action): coffee_action.text = UI.copy("coffee_finish","休憩を終える"); coffee_action.disabled = false
	elif coffee_phase == "drunk":
		coffee_phase = "idle"; coffee_elapsed = 0.0; coffee_cup = null
		close_panel()

func _credits() -> void:
	modal_body.add_child(_label(str(_game().company_name()), 24, INK)); modal_body.add_child(_label("Godot (MIT)\nWhimfoome / FirstPersonStarter (MIT)\nKenney furniture & interface sounds (CC0)\nQuaternius modular characters (CC0)\nNoto Sans JP / Google & Adobe (SIL OFL 1.1)\nM PLUS Rounded 1c / M+ FONTS (SIL OFL 1.1)\n\nライセンス全文は配布フォルダーの licenses に収録しています。", 19, MUTED))

	modal_body.add_child(_label("Calm Track / pmiller (CC0)", 17, MUTED))

func _open_settings() -> void:
	settings_return_kind = current_kind
	open_panel("settings")

func _close_settings() -> void:
	var return_kind := settings_return_kind
	settings_return_kind = ""
	if not close_panel(false, false):
		return
	if not return_kind.is_empty():
		open_panel(return_kind)


func _settings_tab(tab: String) -> void:
	settings_category=tab
	for id in controls.get("settings_tabs",{}):
		if is_instance_valid(controls.settings_tabs[id]):
			controls.settings_tabs[id].button_pressed=id==tab
			GAME_THEME.navigation(controls.settings_tabs[id], id == tab)
	for child in modal_body.get_children(): child.visible = child.get_meta("category","video") == tab and not child.get_meta("folded",false)
	modal_scroll.scroll_vertical = 0

func _settings() -> void:
	var g:=_game(); if g==null:return
	pending_settings=g.settings.duplicate(true); setting_options.clear()
	var spec:Dictionary=_graphics().hardware()
	modal_body.add_child(_label("映像・性能",23,INK))
	modal_body.add_child(_label("%s  /  RAM %.0f GB" % [spec.gpu,spec.ram_gb],15,MUTED))
	modal_body.add_child(_button(_copy_short("opt_fhd_preset","フルHD適用",16),func():
		pending_settings.merge({"window_mode":"fullscreen","resolution":"1920x1080","render_scale":1.0,"max_fps":60},true)
		_apply_settings()))
	_add_setting_option("画質プリセット",["軽量 / 60 FPS","標準 / 60 FPS","高画質 / 60 FPS"],["low","medium","high"],pending_settings.quality,func(v):_queue_setting("quality",v))
	_add_setting_option("画面モード",["ウィンドウ","ボーダーレス","フルスクリーン"],["windowed","borderless","fullscreen"],pending_settings.window_mode,func(v):_queue_setting("window_mode",v))
	_add_setting_option("解像度",["960 × 600","1280 × 720 / HD","1600 × 900","1920 × 1080 / フルHD"],["960x600","1280x720","1600x900","1920x1080"],pending_settings.resolution,func(v):_queue_setting("resolution",v))
	_add_setting_option("最大FPS",["30 FPS","60 FPS","120 FPS","制限なし"],[30,60,120,0],pending_settings.max_fps,func(v):_queue_setting("max_fps",v))
	_add_setting_option("垂直同期",["オフ","オン"],[false,true],pending_settings.vsync,func(v):_queue_setting("vsync",v))
	_add_setting_option("描画解像度",["50%","67%","85%","100%"],[0.5,0.67,0.85,1.0],pending_settings.render_scale,func(v):_queue_setting("render_scale",v))
	_add_setting_option("アンチエイリアス",["なし","2x MSAA","4x MSAA"],[0,2,4],pending_settings.msaa,func(v):_queue_setting("msaa",v))
	_add_setting_option("影",["オフ","低","高"],["off","low","high"],pending_settings.shadows,func(v):_queue_setting("shadows",v))
	_add_setting_slider("視野角","fov",60,90,1,"°","video")
	var mouse_title:=_label("マウスと移動",23); mouse_title.set_meta("category","control"); modal_body.add_child(mouse_title)
	_add_setting_slider(UI.copy("opt_mouse_sens","マウス感度（0.1〜3.0）"),"mouse_sensitivity",0.1,3.0,0.05," ×","control")
	_add_setting_option(UI.copy("opt_mouse_invert","上下反転"),["オフ","オン"],[false,true],pending_settings.get("invert_y",false),func(v):_queue_setting("invert_y",v))
	var reset:=_button("操作設定初期化",func(): pending_settings.mouse_sensitivity=1.0; pending_settings.invert_y=false; _refresh_setting_options()); reset.set_meta("category","control"); modal_body.add_child(reset)
	var binds:=_label(g.personalize("W A S D   移動      Shift   早歩き\nE   目の前を操作      F   PCを開く\nTab   案件      Esc   戻る / 中断\n1   綾      2   蓮      3   設備      4   会社"),17,INK); binds.set_meta("category","control"); binds.visible=false; binds.set_meta("folded",true); var bind_toggle: Button; bind_toggle=_button("キー割当表示",func(): binds.visible=not binds.visible; binds.set_meta("folded",not binds.visible); bind_toggle.text="キー割当非表示" if binds.visible else "キー割当表示"); bind_toggle.set_meta("category","control"); modal_body.add_child(bind_toggle); modal_body.add_child(binds)
	_add_setting_slider("全体の音量","volume",0,100,1,"%","audio")
	_add_setting_slider("効果音","effects_volume",0,100,1,"%","audio")
	_add_setting_slider("環境音","ambient_volume",0,100,1,"%","audio")
	_add_setting_slider(UI.copy("audio_music"),"music_volume",0,100,1,"%","audio")
	var music_player := get_node_or_null("/root/Soundscape")
	var music_row := VBoxContainer.new(); music_row.set_meta("category", "audio"); music_row.add_theme_constant_override("separation", 6); modal_body.add_child(music_row)
	var music_header := HBoxContainer.new(); music_header.add_theme_constant_override("separation", 12); music_row.add_child(music_header)
	var music_label := _label(UI.copy("music_playlist"), 16); music_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; music_header.add_child(music_label)
	var music_title := _label(str(music_player.call("current_music_title")) if music_player != null and music_player.has_method("current_music_title") else "", 14, MUTED)
	music_title.name = "MusicTrackTitle"; music_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var skip_music := _button(UI.copy("music_next"), func():
		if music_player != null and music_player.has_method("next_music_track"):
			music_player.call("next_music_track")
			music_title.text = str(music_player.call("current_music_title")))
	skip_music.name = "MusicNextTrack"; music_header.add_child(skip_music); music_row.add_child(music_title)
	_add_setting_option("文字サイズ",["標準 / 100%","大 / 115%","特大 / 130%"],[1.0,1.15,1.3],pending_settings.text_scale,func(v):_queue_setting("text_scale",v))
	var feedback:=_label("「適用」で保存",14,UI.MUTED); feedback.autowrap_mode=TextServer.AUTOWRAP_OFF; feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL; modal_footer.add_child(feedback); controls.settings_feedback=feedback
	var recommend := _button("PC構成に合わせる",_recommend_settings); recommend.size_flags_horizontal=Control.SIZE_SHRINK_END; modal_footer.add_child(recommend)
	var apply:=_button("適用",_apply_settings); apply.name = "SettingsApply"; apply.custom_minimum_size.x=100; apply.size_flags_horizontal=Control.SIZE_SHRINK_END; GAME_THEME.primary(apply); modal_footer.add_child(apply)
	_settings_tab(settings_category)

func _graphics() -> Node:
	return get_node_or_null("/root/Graphics")

func _graphics_recommendation() -> Dictionary:
	var gfx := _graphics()
	if gfx != null and gfx.has_method("recommendation"): return gfx.recommendation()
	return {"preset":"low", "reason":"720p/60fps基準（安定動作優先）"}

func _queue_setting(key: String, value) -> void:
	pending_settings[key] = value
	if key == "quality":
		pending_settings.merge(_graphics().preset_values(str(value)), true)
		_refresh_setting_options()

func _recommend_settings() -> void:
	var recommendation := _graphics_recommendation()
	var preset: String = recommendation.get("preset", "low")
	var gfx := _graphics()
	if gfx != null and gfx.has_method("preset_values"): pending_settings.merge(gfx.preset_values(preset), true)
	else: pending_settings.merge({"quality":preset,"render_scale":0.67 if preset == "low" else 0.85,"max_fps":60,"shadows":"off" if preset == "low" else "low"}, true)
	if is_instance_valid(controls.get("settings_feedback")): controls.settings_feedback.text="推奨を選択しました"
	_refresh_setting_options()

func _apply_settings() -> void:
	var g:=_game(); if g==null:return
	var display_changed:=false
	for key in ["window_mode","resolution","render_scale","msaa","shadows","max_fps","vsync"]:
		if pending_settings.get(key)!=g.settings.get(key): display_changed=true
	if not display_changed:
		g.set_settings(pending_settings); _set_text_scale(float(g.settings.text_scale))
		if is_instance_valid(controls.get("settings_feedback")):controls.settings_feedback.text="適用しました"
		return
	close_panel(false, false); previous_settings=g.settings.duplicate(true); preview_seconds=15.0; g.set_settings(pending_settings,false); _set_text_scale(float(g.settings.text_scale)); open_panel("confirm_display")

func _confirm_display() -> void:
	var label := _label("設定を維持しますか？", 24, INK); controls.countdown = label; modal_body.add_child(label)
	modal_footer.add_child(_button("この設定を使う", Callable(self, "_keep_settings")))
	modal_footer.add_child(_button("元に戻す", Callable(self, "_revert_settings")))

func _keep_settings() -> void:
	previous_settings.clear(); _game().set_settings(pending_settings); close_panel(false, false); open_panel("settings")

func _restore_settings() -> void:
	var old := previous_settings.duplicate(true); previous_settings.clear()
	_game().set_settings(old, false); _set_text_scale(float(old.text_scale))

func _revert_settings() -> void:
	_restore_settings(); close_panel(false, false); open_panel("settings")

func _refresh_setting_options() -> void:
	for key in setting_options:
		var item:Dictionary=setting_options[key]
		if item.get("slider",false): item.control.value=float(pending_settings[key]); continue
		for i in item.values.size():
			if item.values[i]==pending_settings[key]:item.control.select(i)

func _add_setting_option(label_text: String, labels: Array, values: Array, current, callback: Callable) -> void:
	var category:="accessibility" if label_text=="文字サイズ" else ("control" if label_text=="上下反転" else "video")
	var row:=_setting_row(label_text,category)
	var keys:={"画質プリセット":"quality","画面モード":"window_mode","解像度":"resolution","描画解像度":"render_scale","アンチエイリアス":"msaa","影":"shadows","最大FPS":"max_fps","垂直同期":"vsync","上下反転":"invert_y","文字サイズ":"text_scale"}
	var key:=str(keys.get(label_text,""))
	var o:=OptionButton.new(); o.custom_minimum_size=Vector2(230,42); o.size_flags_horizontal=Control.SIZE_SHRINK_END
	for x in labels:o.add_item(str(x))
	var index:=0
	for i in values.size():
		if values[i]==current or (values[i] is float and is_equal_approx(float(values[i]),float(current))):index=i
	o.select(index); o.item_selected.connect(func(i:int): callback.call(values[i])); row.add_child(o)
	if not key.is_empty(): setting_options[key]={"control":o,"values":values}


func _setting_row(title: String, category: String) -> HBoxContainer:
	var panel:=PanelContainer.new(); panel.set_meta("category",category); panel.add_theme_stylebox_override("panel",GAME_THEME.surface(GAME_THEME.FILTER,Color.TRANSPARENT,4,8)); modal_body.add_child(panel)
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",12); panel.add_child(row)
	var label:=_label(title,18,INK); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; row.add_child(label); return row

func _add_setting_slider(title: String, key: String, low: float, high: float, step_value: float, suffix: String, category: String) -> void:
	var row:=_setting_row(title,category)
	var number:=_label("",17,TEAL); number.custom_minimum_size.x=72; number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(number)
	var slider:=HSlider.new(); slider.name="Setting_"+key; slider.min_value=low; slider.max_value=high; slider.step=step_value; slider.value=float(pending_settings.get(key,low)); slider.custom_minimum_size=Vector2(174,38); slider.mouse_filter=Control.MOUSE_FILTER_STOP; slider.scrollable=false; row.add_child(slider)
	var format_value:=func(v): number.text=("%.2f" % v if step_value<1.0 else "%d" % int(v))+suffix
	format_value.call(slider.value); slider.value_changed.connect(func(v): _queue_setting(key,v); format_value.call(v))
	setting_options[key]={"control":slider,"values":[],"slider":true}

func _set_text_scale(value: float) -> void:
	text_scale = value
	root.theme.default_font_size = int(18 * value)
	_apply_text_scale(root)
	_layout_main_menu()

func _apply_text_scale(node: Node) -> void:
	for child in node.get_children():
		if child is Control and child.has_meta("base_font_size"):
			child.add_theme_font_size_override("font_size", int(float(child.get_meta("base_font_size")) * text_scale))
		_apply_text_scale(child)

func _show_ending() -> void:
	modal = PanelContainer.new(); modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(modal)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,40)
	modal.add_child(margin)
	var layout := VBoxContainer.new(); layout.add_theme_constant_override("separation",22); margin.add_child(layout)
	layout.add_child(_label("設立初週の決算",34,INK))
	var g := _game(); var metrics := HBoxContainer.new(); metrics.add_theme_constant_override("separation",36); layout.add_child(metrics)
	for pair in [["完了案件","%d / 6" % g.state.get("completed_ids",[]).size()],["累計利益","¥%d" % g.state.get("profit",0)],["会社レベル",str(g.company_level().level)]]:
		var column := VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; metrics.add_child(column); column.add_child(_label(pair[0],15,MUTED)); column.add_child(_label(pair[1],32,TEAL))
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; layout.add_child(scroll)
	var message:=_label(str(g.copy.get("ending","")),16,INK); message.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(message)
	var actions:=HBoxContainer.new(); actions.add_theme_constant_override("separation",12); layout.add_child(actions)
	var next:=_button("営業を続ける",_continue_business); UI.primary(next); actions.add_child(next); actions.add_child(_button("結果書き出し",_report)); actions.add_child(_button("タイトルへ",open_main_menu)); current_kind="ending"

func _continue_business() -> void:
	var g := _game()
	if g != null and g.has_method("continue_business"): g.continue_business()
	close_panel()
	open_panel("board")

func update_hud() -> void:
	var g := _game(); if g == null: return
	if g.state.is_empty(): return
	if controls.has("cash"): controls.cash.text = "¥%d" % int(g.state.get("cash", 0))
	var work: Dictionary = g.work_status() if g.has_method("work_status") else {}
	if controls.has("clock"): controls.clock.text = "DAY %02d  %s" % [int(g.state.get("day", 1)), str(g.business_clock()) if g.has_method("business_clock") else "09:00"]
	if controls.has("deadline"):
		controls.deadline.text = "納期 %s" % str(work.get("deadline_text", "--:--")) if g.state.get("accepted", false) and not g.current_done() else "納期 --:--"
		controls.deadline.add_theme_color_override("font_color", Color("ffbd74") if int(work.get("late_minutes",0)) > 0 else Color("d5e6f0"))
	var level: Dictionary = g.company_level() if g.has_method("company_level") else {"level":1,"progress":0.0}
	if controls.has("meta"): controls.meta.text = "Lv.%d" % int(level.level)
	if controls.has("xp"): controls.xp.value=float(level.progress)*100.0
	if status_label != null: status_label.text = str(g.mission().title)
	if controls.has("work_state"):
		var phase := "メールで案件受注"
		if g.state.accepted:
			phase = "顧客端末に接続" if not g.vm_info().connected else "調査・設定を進める"
			if not g.state.checks.is_empty(): phase = "検証結果確認"
			if g.can_deliver(): phase = "検証完了 / 納品"
		if g.current_done(): phase = "納品完了 / 退勤可能"
		controls.work_state.text = phase
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_title("ホワイトハッカーラボ")
	if is_instance_valid(modal):
		var brand=modal.find_child("CompanyBrand",true,false)
		if brand is Label: brand.text=g.company_name(); brand.tooltip_text=g.company_name()
		var cash=modal.find_child("ManagementCash",true,false)
		if cash is Label: cash.text="¥%s" % _group_number(int(g.state.get("cash",0)))
		var clock=modal.find_child("ManagementClock",true,false)
		if clock is Label: clock.text="DAY %02d  %s" % [int(g.state.get("day",1)),str(g.business_clock())]
	if controls.has("resume"): controls.resume.disabled = not (g.has_method("has_save") and g.has_save())
	if controls.has("work_steps"):
		var stage := 0
		if g.state.accepted: stage=2 if g.vm_info().connected else 1
		if g.can_deliver() or g.current_done(): stage=3
		for i in controls.work_steps.size():
			var item: Dictionary=controls.work_steps[i]
			item.panel.add_theme_stylebox_override("panel",_surface(TEAL if i==stage else (Color("d8e9df") if i<stage else SURFACE_2),Color.TRANSPARENT,7,3))
			item.label.add_theme_color_override("font_color",Color.WHITE if i==stage else (TEAL if i<stage else MUTED))
	if controls.has("team_hud"):
		for id in controls.team_hud:
			var job: Dictionary=g.state.assignments.get(id,{})
			var status:=str(job.get("status",""))
			var visible:=status in ["working","done"]
			controls.team_hud[id].visible=visible
			if visible:
				var phase: String={"working":"作業中","done":"完了"}.get(status,status)
				controls.team_hud[id].text="%s  %s" % [g.member_name(id),phase]
				controls.team_hud[id].tooltip_text=str(job.get("phase",phase))

func _maintenance_signature(g) -> String:
	var rows: Array = []
	for client in g.state.care_agreements:rows.append([client,g.maintenance_owner(str(client)),g._maintenance_targets_for(str(client)).size()])
	for job in g.maintenance_jobs():
		var client := str(job.get("client", "")); var incident: Dictionary = g.care_incident(client) if g.has_method("care_incident") else {}
		rows.append([job.get("id", ""), job.get("status", ""), job.get("assignee", ""), incident.get("id", ""), incident.get("status", "")])
	for member in g.team_members(): rows.append([member.id, g.state.assignments.get(member.id, {}).get("status", ""), g.staff_availability(str(member.id),"maintenance")])
	return str(g.maintenance_summary()) + str(rows)

func _operating_signature(g) -> String:
	if g == null or not g.has_method("company_operating_summary"): return ""
	return str(g.company_operating_summary())

func _refresh_maintenance_panel() -> void:
	if current_kind != "company": return
	var scroll := modal_scroll.scroll_vertical
	open_panel("company")
	modal_scroll.set_deferred("scroll_vertical", scroll)

func _on_game_changed() -> void:
	update_hud(); _update_crew_status()
	if current_kind=="board" and is_instance_valid(modal_body) and _game().state.get("career_mode",false):OPERATIONS_PANEL.refresh_live(self)
	if current_kind=="shop" and shop_view=="stock" and is_instance_valid(modal_body):PROCUREMENT_PANEL.refresh_live(self)
	if current_kind=="shop" and shop_view=="stock": PROCUREMENT_PANEL.refresh_live(self)
	if current_kind == "company":
		var g := _game()
		if g != null and g.has_method("maintenance_jobs"):
			var maintenance_signature := _maintenance_signature(g)
			var operating_signature := _operating_signature(g)
			if maintenance_signature != _maintenance_ui_signature or operating_signature != _operating_ui_signature:
				_maintenance_ui_signature = maintenance_signature
				_operating_ui_signature = operating_signature
				call_deferred("_refresh_maintenance_panel")
			else:
				for job in g.maintenance_jobs():
					var progress_label = _maintenance_progress_labels.get(str(job.get("client", "")))
					if is_instance_valid(progress_label):
						progress_label.text = UI.copy("care_progress") % [int(float(job.get("total", 0)) - float(job.get("remaining", 0))), int(job.get("total", 0))]

func set_focus_prompt(text: String) -> void:
	if prompt != null:
		prompt.text = text.strip_edges()
		if controls.has("focus_hint") and is_instance_valid(controls.focus_hint):
			controls.focus_hint.visible = not prompt.text.is_empty()
			var width := prompt.get_theme_font("font").get_string_size(prompt.text,HORIZONTAL_ALIGNMENT_LEFT,-1,prompt.get_theme_font_size("font_size")).x + 28
			controls.focus_hint.offset_right = minf(root.size.x - 20, maxf(360, width + 20))

func _input(event: InputEvent) -> void:
	# LineEdit consumes Escape before unhandled input; the name form must still cancel.
	if current_kind == "profile" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _is_management_panel(current_kind) and is_instance_valid(next_task_guide) and next_task_guide.management_open:
			next_task_guide.open_management()
		elif current_kind == "settings": _close_settings()
		elif current_kind == "confirm_display": _revert_settings()
		elif current_kind == "sales" and not board_selected_id.is_empty(): _return_to_sales_list()
		elif current_kind != "": close_panel()
		elif controls.has("menu") and not controls.menu.visible: open_panel("pause")

func _quit() -> void:
	if not previous_settings.is_empty(): _restore_settings()
	emit_signal("quit_requested")
