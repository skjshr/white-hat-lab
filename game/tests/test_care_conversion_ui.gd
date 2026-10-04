extends "res://tests/test_care_contract_support.gd"
const INTERFACE = preload("res://scripts/interface.gd")
var native_clicks := 0
var narrow := false
var capture_dir := ""

func frames(count: int = 3) -> void:
	for _i in count: await process_frame

func click(button: BaseButton, label: String) -> void:
	check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, label + " available")
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled: return
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(button); await frames(2)
		ancestor=ancestor.get_parent()
	# Refresh may have just changed the guide's text/theme. Read the center only
	# after its deferred container layout settles, even on very fast headless frames.
	var stable:=0
	var previous:=Rect2()
	for _attempt in 24:
		await frames(1)
		var rect:=button.get_global_rect().intersection(root.get_visible_rect())
		ancestor=button.get_parent()
		while ancestor!=null:
			if ancestor is Control and ancestor.clip_contents: rect=rect.intersection(ancestor.get_global_rect())
			ancestor=ancestor.get_parent()
		stable=stable+1 if rect==previous and rect.size.y>=25 else 0
		previous=rect
		if stable>=3:break
	check(stable>=3,label+" visible clipped rectangle settled")
	if stable<3:return
	var point:=button.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(point), label + " in viewport")
	ancestor=button.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: check(ancestor.get_global_rect().has_point(point), label + " within clip")
		ancestor=ancestor.get_parent()
	# Input.parse_input_event takes window pixels; controls use the stretched
	# logical viewport. These differ with the headless display's window sizing.
	var pixel:=point * Vector2(root.size) / root.get_visible_rect().size
	var pressed: Array[int]=[0]
	button.pressed.connect(func(): pressed[0]+=1)
	var motion:=InputEventMouseMotion.new();motion.position=pixel;motion.global_position=pixel;Input.parse_input_event(motion)
	await frames(2)
	var hovered: Control=root.gui_get_hovered_control()
	check(hovered==button or (hovered!=null and button.is_ancestor_of(hovered)),label+" pointer reaches target")
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=pixel;event.global_position=pixel;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event);await frames(2)
	native_clicks+=1;await frames(6)
	check(pressed[0]==1,label+" dispatched exactly one real press")

func capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name()=="headless":return
	await frames(5);await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_dir)
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,label+" capture")

func run() -> void:
	narrow="--narrow" in OS.get_cmdline_user_args();capture_dir=OS.get_environment("WHL_CAPTURE_DIR")
	check("--qa-profile=care-conversion-ui" in OS.get_cmdline_user_args(),"isolated UI storage")
	if not failures.is_empty():quit(1);return
	root.size=Vector2i(960,600) if narrow else Vector2i(1440,900)
	var ui:=INTERFACE.new();root.add_child(ui);await frames(5)
	var g=ui._game();g.set_process(false)
	check(g.new_game() and g.choose_strategy("operations"),"new underlying game")
	legacy_portal(g);complete_portal(g)
	check(g.load_game(),"open authentic serialized compatibility fixture")
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.controls.menu.hide();ui.open_panel("terminal")
	var desk=ui.desktop;desk._show_app("advanced");await frames(8)
	print("CARE_UI_INPUT_COORDINATES pixels=",root.size," logical=",root.get_visible_rect().size)
	var mark:=terms_mark(g)
	ui.next_task_guide.refresh(1.0)
	await click(ui.next_task_guide.locate,"guide contract navigation")
	check(desk.current_app=="receipt","guide brings actual receipt forward")
	check(terms_mark(g)==mark and bool(g.care_conversion_offer().available),"navigation does not change agreement")
	if desk.current_app!="receipt" or not desk.widgets.has("receipt"):
		print("CARE_CONVERSION_UI_FAIL ",failures)
		ui.queue_free();await frames(3);quit(1);return
	var button: BaseButton=desk.widgets.receipt.body.find_child("CareConvertStandard",true,false)
	check(button!=null,"explicit conversion control exists")
	check(ui.next_task_guide.target_rect.has_area(),"conversion control highlighted")
	await capture("01-legacy-contract-review")
	var good_path:=str(g.save_path);g.save_path="user://missing-care-ui-%s/save.json" % OS.get_process_id()
	await click(button,"failed save conversion")
	check(terms_mark(g)==mark and bool(g.care_conversion_offer().available),"failed native action preserves state")
	g.save_path=good_path
	button=desk.widgets.receipt.body.find_child("CareConvertStandard",true,false)
	await click(button,"explicit standard conversion")
	check(not bool(g.care_conversion_offer().available) and g.can_deliver(),"native conversion unlocks verified delivery")
	check(terms_mark(g)==mark,"UI conversion keeps negotiated terms and proof")
	await capture("02-converted-ready")
	var deliver: BaseButton=desk.widgets.receipt.footer.find_child("GuideDeliver",true,false)
	await click(deliver,"native verified delivery")
	check(g.current_done() and not str(g.completion_receipt().get("invoice_id","")).is_empty(),"receipt and actual invoice created")
	await capture("03-converted-delivered")
	print("CARE_CONVERSION_UI_PASS native_clicks=%d narrow=%s" % [native_clicks,str(narrow)] if failures.is_empty() else "CARE_CONVERSION_UI_FAIL "+str(failures))
	ui.queue_free();await frames(3)
	quit(0 if failures.is_empty() else 1)
