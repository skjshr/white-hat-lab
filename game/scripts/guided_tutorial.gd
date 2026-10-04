extends Control
## Optional first-job coaching. Navigation is assisted; work is always performed
## through the real workstation. No copied configuration or synthetic checks.
const UI = preload("res://scripts/ui_theme.gd")
const SAMBA = preload("res://scripts/samba_config.gd")
const STEPS := ["strategy","walk","desk","mail","accept","connect","baseline","observe","edit","read_only","guest","users","save","restart","diagnose","validate","deliver","done"]
var ui
var game
var current_step := ""
var target_rect := Rect2()
var _card: PanelContainer
var _title: Label
var _body: Label
var _progress: Label
var _keys: Label
var _locate: Button
var _skip: Button
var _elapsed := 0.0
var _last_position := Vector3.ZERO
var _last_rotation := Vector2.ZERO
var _motion_sampled := false
var _distance := 0.0
var _turn := 0.0
var _scale := -1.0
var _target_id := 0
var _probe_id := ""
var _details: Button
var _expanded := false
var _reserved: Control
var _original_top := 0.0

func setup(owner_ui) -> void:
	ui = owner_ui; game = ui._game()
	name = "GuidedTutorial"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new(); _card.name="GuidedTutorialCard"; add_child(_card)
	var style := UI.style(Color.WHITE, UI.BORDER, 12, 7, 0)
	style.border_width_bottom = 2
	_card.add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",5); _card.add_child(box)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",10); box.add_child(row)
	var heading := VBoxContainer.new(); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(heading)
	_progress = Label.new(); _progress.add_theme_color_override("font_color",UI.PRIMARY); heading.add_child(_progress)
	_title = Label.new(); _title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _title.add_theme_color_override("font_color",UI.INK); heading.add_child(_title)
	_body = Label.new(); _body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _body.add_theme_color_override("font_color",UI.INK); box.add_child(_body)
	_keys = Label.new(); _keys.add_theme_color_override("font_color",UI.PRIMARY); box.add_child(_keys)
	_locate=Button.new(); _locate.name="GuidedTutorialLocate"; _locate.text=UI.copy("guide_locate"); _locate.pressed.connect(_locate_target); row.add_child(_locate)
	_details = Button.new(); _details.name = "GuidedTutorialDetails"; _details.text = UI.copy("next_hint"); _details.toggle_mode = true
	_details.toggled.connect(func(value): _expanded = value; _render(false)); row.add_child(_details)
	_skip=Button.new(); _skip.name="GuidedTutorialSkip"; _skip.text=UI.copy("guide_skip"); _skip.flat=true; _skip.pressed.connect(skip); row.add_child(_skip)
	_card.minimum_size_changed.connect(_fit_card.call_deferred)
	hide()

func _data() -> Dictionary:
	var value = game.state.get("guided_intro",{}) if game != null else {}
	return value if value is Dictionary else {}

func active() -> bool:
	return bool(_data().get("enabled",false)) and not bool(_data().get("completed",false)) and not bool(game.state.get("career_mode",false)) and int(game.state.get("chapter",0))==0

func _persist(changes: Dictionary) -> bool:
	var existed: bool=game.state.has("guided_intro")
	var before := _data().duplicate(true)
	var after := before.duplicate(true); after.merge(changes,true); game.state.guided_intro=after
	if game.save_game(): return true
	if existed: game.state.guided_intro=before
	else: game.state.erase("guided_intro")
	return false

func begin() -> bool:
	_motion_sampled=false; _distance=0.0; _turn=0.0; current_step=""
	return _persist({"enabled":true,"completed":false,"moved":false,"looked":false,"desktop_opened":false,"observed":false})

func resume() -> void:
	if _data().is_empty() or bool(_data().get("completed",false)): return
	if _persist({"enabled":true}): refresh(0.2)

func skip() -> void:
	if _persist({"enabled":false,"completed":current_step=="done"}): hide(); _reserve(null, 0)

func _desktop():
	return ui.desktop if ui.current_kind=="terminal" and is_instance_valid(ui.desktop) else null

func _player():
	var office=ui.get_parent()
	return office.get("player") if office is Node3D else null

func _observe_motion() -> void:
	var player=_player()
	if player==null or not player.enabled or not ui.current_kind.is_empty():
		_motion_sampled=false; return
	var rotation := Vector2(float(player.rotation.y),float(player.pitch))
	if _motion_sampled:
		_distance+=player.position.distance_to(_last_position)
		_turn+=absf(angle_difference(_last_rotation.x,rotation.x))+absf(rotation.y-_last_rotation.y)
	_last_position=player.position; _last_rotation=rotation; _motion_sampled=true
	var changes := {}
	if _distance>=0.7 and not bool(_data().get("moved",false)): changes.moved=true
	if _turn>=0.20 and not bool(_data().get("looked",false)): changes.looked=true
	if not changes.is_empty(): _persist(changes)

func refresh(delta: float = 0.2) -> void:
	if not active(): hide(); _reserve(null, 0); return
	if ui.controls.menu.visible or ui.current_kind in ["pause","settings","confirm_display","help","profile","credits"]:
		hide(); _reserve(null, 0); _motion_sampled=false; return
	show(); _observe_motion()
	_elapsed+=delta
	if _elapsed<0.12: return
	_elapsed=0.0
	var desktop=_desktop()
	if desktop!=null and not bool(_data().get("desktop_opened",false)): _persist({"desktop_opened":true})
	var next := _derive_step()
	var changed := next!=current_step
	current_step=next
	if _scale!=float(ui.text_scale):
		_scale=float(ui.text_scale); theme=UI.make_theme(_scale)
		_progress.add_theme_font_size_override("font_size",int(12*_scale))
		_title.add_theme_font_size_override("font_size",int(18*_scale))
		_body.add_theme_font_size_override("font_size",int(14*_scale))
		_keys.add_theme_font_size_override("font_size",int(18*_scale))
	_render(changed)

func _derive_step() -> String:
	if game.current_done(): return "done"
	if str(game.state.get("strategy","")).is_empty(): return "strategy"
	var data := _data()
	var accepted: bool=game.state.get("accepted",false)
	if not accepted and not bool(data.get("desktop_opened",false)):
		if not bool(data.get("moved",false)) or not bool(data.get("looked",false)): return "walk"
		return "desk"
	var desktop=_desktop()
	if not accepted:
		if desktop==null or desktop.current_app!="mail" or not bool(desktop.widgets.get("mail",{}).get("reading",false)): return "mail"
		return "accept"
	if not bool(game.vm_info().get("connected",false)): return "connect"
	var review: Dictionary=game.case_review()
	if not bool(game.state.get("baseline_recorded",false)) and bool(review.get("can_capture",false)): return "baseline"
	var probes: Array=game.diagnostic_probes()
	if not bool(data.get("observed",false)):
		var recorded: bool=probes.any(func(p): return str(p.id)=="staff-write" and bool(p.get("recorded",false)))
		if not recorded: _probe_id="staff-write"; return "observe"
		_persist({"observed":true})
	var vm=game._vm()
	var path: String=str(vm.state.config_path)
	var parsed: Dictionary=SAMBA.parse(str(vm.state.fs.get(path,"")))
	var values: Dictionary=parsed.get("values",{})
	var draft: Dictionary={}
	if desktop!=null: draft=desktop.samba_ui.get("share_drafts",{}).get("share",{})
	var saved_ok: bool=str(parsed.get("error","" )).is_empty() and str(values.get("staff",""))=="write" and str(values.get("guest",""))=="none" and str(values.get("path",""))=="/srv/share"
	if not saved_ok or not draft.is_empty():
		if desktop==null or desktop.current_app!="browser" or _find("SambaReadOnly")==null: return "edit"
		var fields: Dictionary=draft if not draft.is_empty() else values.get("shares",{}).get("share",{})
		if bool(fields.get("read only",true)): return "read_only"
		if bool(fields.get("guest ok",false)): return "guest"
		if str(fields.get("valid users","" )).strip_edges()!="staff": return "users"
		return "save"
	if bool(vm.state.get("dirty",false)) or not bool(vm.state.get("active",false)): return "restart"
	for probe in probes:
		if not bool(probe.get("fresh",false)) or not bool(probe.get("passed",false)):
			_probe_id=str(probe.id); return "diagnose"
	if not game.can_deliver(): return "validate"
	return "deliver"

func _route() -> String:
	return {"mail":"mail","accept":"mail","connect":"browser","baseline":"receipt","observe":"verify","edit":"browser","read_only":"browser","guest":"browser","users":"browser","save":"browser","restart":"browser","diagnose":"verify","validate":"verify","deliver":"receipt","done":"receipt"}.get(current_step,"")

func _target_name() -> String:
	if current_step in ["observe","diagnose"]:
		var desktop=_desktop()
		if desktop!=null and str(desktop.widgets.get("verify",{}).get("selected",""))!=_probe_id: return "DiagnosticProbe_"+_probe_id
		return "DiagnosticRun"
	return {"mail":"GuideMailMessage","accept":"GuideMailAccept","connect":"SambaConnect","baseline":"GuideBaseline","edit":"SambaEdit_share","read_only":"SambaReadOnly","guest":"SambaGuest","users":"SambaValidUsers","save":"SambaSave","restart":"SambaRestart","validate":"DiagnosticValidate","deliver":"GuideDeliver"}.get(current_step,"")

func _find(id: String) -> Control:
	if id.is_empty(): return null
	var node=ui.root.find_child(id,true,false)
	return node if node is Control and node.is_visible_in_tree() and not node.is_queued_for_deletion() else null

func _target_control() -> Control:
	var route:=_route()
	if not route.is_empty():
		var desktop=_desktop()
		if desktop==null: return null
		if desktop.current_app!=route: return _find("TaskbarApp_"+route)
	return _find(_target_name())

func _scroll_to(control: Control) -> void:
	if not is_instance_valid(control): return
	var ancestor: Node=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
			var center: float=control.get_global_rect().get_center().y
			var bottom: float=ancestor.get_global_rect().end.y-48
			if center>bottom: ancestor.scroll_vertical+=ceili(center-bottom)
		ancestor=ancestor.get_parent()

func _visible_rect(control: Control) -> Rect2:
	var rect: Rect2=control.get_global_rect()
	var ancestor: Node=control.get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents: rect=rect.intersection(ancestor.get_global_rect())
		ancestor=ancestor.get_parent()
	return rect.intersection(get_viewport_rect())

func _render(changed: bool) -> void:
	_progress.text=UI.copy("guide_progress")+"  ·  %02d / %02d" % [STEPS.find(current_step)+1,STEPS.size()]
	_title.text=UI.copy("guide_"+current_step+"_title")
	_body.text=UI.copy("guide_"+current_step+"_body")
	_body.visible = _expanded or ui.current_kind.is_empty() or current_step == "strategy"
	_keys.visible=current_step in ["walk","desk"]
	_keys.text=(("✓  " if bool(_data().get("moved",false)) else "")+"W  A  S  D   ·   "+("✓  " if bool(_data().get("looked",false)) else "")+"↔") if current_step=="walk" else "E   /   F"
	_skip.text=UI.copy("guide_finish" if current_step=="done" else "guide_skip")
	var target:=_target_control()
	target_rect=Rect2()
	if target!=null:
		var id:=target.get_instance_id()
		if changed or id!=_target_id: _scroll_to(target); _target_id=id
		target_rect=_visible_rect(target)
	elif current_step=="desk" and ui.current_kind.is_empty(): _world_target()
	var desktop=_desktop()
	var elsewhere: bool=not _route().is_empty() and (desktop==null or desktop.current_app!=_route())
	_locate.visible=(elsewhere or not target_rect.has_area()) and (current_step!="walk" or not ui.current_kind.is_empty()) and (current_step!="done" or elsewhere)
	if current_step == "strategy" and ui.current_kind == "board": _locate.hide()
	_locate.text=UI.copy("guide_return" if current_step=="walk" else "guide_locate")
	var surface: Control = _desktop()
	if surface == null and ui._is_management_panel(ui.current_kind): surface = ui.modal
	var width: float = surface.size.x if is_instance_valid(surface) else minf(520.0*_scale,get_viewport_rect().size.x-24)
	_card.size=Vector2(width,0)
	_fit_card.call_deferred()
	queue_redraw()

func _fit_card() -> void:
	if not visible or not is_instance_valid(_card): return
	_card.size.y = _card.get_combined_minimum_size().y
	var surface: Control = _desktop()
	if surface == null and ui._is_management_panel(ui.current_kind): surface = ui.modal
	_reserve(surface, _card.size.y + 4.0)
	if is_instance_valid(surface):
		_card.position = surface.get_global_rect().position - Vector2(0, _card.size.y + 4.0)
	else:
		_card.position = _card_position(_card.size)

func _reserve(surface: Control, height: float) -> void:
	if _reserved != surface:
		if is_instance_valid(_reserved): _reserved.offset_top = _original_top
		if is_instance_valid(surface) and is_instance_valid(ui.next_task_guide):
			# Resume can happen while the ordinary guide still owns the top inset.
			ui.next_task_guide._reserve(null, 0)
		_reserved = surface
		if is_instance_valid(surface): _original_top = surface.offset_top
	if is_instance_valid(surface) and not is_equal_approx(surface.offset_top, _original_top + height):
		surface.offset_top = _original_top + height

func _world_target() -> void:
	var player=_player()
	if player==null: return
	var marker=ui.get_parent().get("player_desk_label")
	if not marker is Node3D: return
	var point: Vector3=marker.global_position
	var screen: Vector2=player.camera.unproject_position(point)
	var bounds:=get_viewport_rect().size
	if player.camera.is_position_behind(point): screen=Vector2(40,bounds.y*0.5)
	screen=screen.clamp(Vector2(36,36),bounds-Vector2(36,36))
	target_rect=Rect2(screen-Vector2(24,24),Vector2(48,48))

func _card_position(card_size: Vector2) -> Vector2:
	if current_step=="strategy": return Vector2(16,16)
	var bounds:=get_viewport_rect().size
	var candidates: Array[Vector2]=[Vector2(bounds.x-card_size.x-16,16),Vector2(bounds.x-card_size.x-16,bounds.y-card_size.y-64),Vector2(16,16),Vector2(16,bounds.y-card_size.y-64)]
	var best: Vector2=candidates[0]; var best_cost:=INF
	for candidate in candidates:
		candidate=candidate.max(Vector2(12,12))
		var rect:=Rect2(candidate,card_size)
		var cost:=rect.intersection(target_rect.grow(24)).get_area()*1000.0
		if target_rect.has_area(): cost+=rect.get_center().distance_to(target_rect.get_center())
		if cost<best_cost: best=candidate; best_cost=cost
	return best

func _draw() -> void:
	if not target_rect.has_area(): return
	var ring:=target_rect.grow(4)
	draw_rect(ring.grow(2),Color.WHITE,false,5.0)
	draw_rect(ring,UI.PRIMARY,false,3.0)
	var tip:=Vector2(ring.position.x+ring.size.x*0.5,ring.position.y-3)
	if tip.y<25: tip=Vector2(ring.end.x+3,ring.get_center().y)
	else:
		draw_colored_polygon(PackedVector2Array([tip,tip+Vector2(-6,-10),tip+Vector2(6,-10)]),UI.PRIMARY)

func _locate_target() -> void:
	if current_step=="strategy": ui.open_panel("board")
	elif current_step=="walk": ui.close_panel()
	elif current_step=="desk": ui.open_panel("terminal")
	else:
		if _desktop()==null: ui.open_panel("terminal")
		var desktop=_desktop()
		if desktop==null: return
		var route:=_route()
		if not route.is_empty(): desktop._show_app(route)
		if route=="browser" and desktop.browser_url!=desktop.SAMBA_URL: desktop._browse_url(desktop.SAMBA_URL,true)
		if current_step in ["mail","accept"]:
			desktop.widgets.mail.folder="inbox"; desktop.widgets.mail.search.text=""; desktop._refresh_mail()
		if current_step == "baseline":
			var section = desktop.widgets.receipt.body.find_child("ReceiptBaselineSection", true, false)
			if section is Control and not section.visible:
				var toggle = section.get_parent().get_child(section.get_index() - 1)
				if toggle is Button: toggle.pressed.emit()
			await get_tree().process_frame
	var target:=_target_control()
	if target!=null: _scroll_to(target)
	refresh(0.2)
