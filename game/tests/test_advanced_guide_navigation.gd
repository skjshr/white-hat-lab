extends "res://tests/test_next_task_ui.gd"
## Focused navigation fixtures, not a claim about unassisted first play or unlocks.
const CATALOG = preload("res://scripts/case_catalog.gd")
const GUIDE = preload("res://scripts/next_task_guide.gd")
const INITIAL_TARGETS := {
	"advanced-hunt":["HuntTab_timeline","HuntEvents"],"advanced-pentest":["NetworkTab_explore","NetworkResources"],"advanced-recovery":["RecoveryTab_copies","RecoverySnapshots"],
	"advanced-pentest-relay":["NetworkTab_explore","RelayHostCanvas"],
	"advanced-cloud":["SpecialistStage_0","CloudRead_app-19"],"advanced-malware":["SpecialistStage_0","MalwareStatic"],"advanced-detection":["SpecialistStage_0","Spec_rule_process"],
	"advanced-ddos":["SpecialistStage_1","DdosInspectSession"],"advanced-api":["SpecialistStage_0","ApiSend"],"advanced-supplychain":["SpecialistStage_2","SpecEvidence"]
}
var native_clicks := 0
var audit_folder := ""
var requested_case := ""

func accept_fixture(game, case_id: String) -> bool:
	if not game.new_game() or not game.choose_strategy(str(CATALOG.by_id(case_id).category)) or not game.start_free_career(): return false
	game.state.skills={"advisory":10,"operations":10,"response":10};game.state.peak_profit=1000000000;game.state.credit=1000000
	game.state.market_leads=[case_id];game.state.market_day=game.state.day;game._make_offers()
	for item in game.state.offers:
		if str(item.case_id)==case_id:
			item.market_available=true
			return game.set_offer_quote(str(item.id),int(game.contract_quote(item).estimated_fee)) and game.choose_contract(str(item.id))
	return false

func locate_by_mouse(panel) -> void:
	panel.refresh(1.0);await frames(5)
	check(panel.locate.is_visible_in_tree() and not panel.locate.disabled,"guide location button available")
	var button: Button = panel.locate
	var logical: Vector2=button.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(logical),"location button is within viewport")
	# GUI rectangles are logical; Input.parse_input_event consumes window pixels.
	var point := logical * Vector2(root.size) / root.get_visible_rect().size
	var presses: Array[int] = [0]
	var on_press: Callable = func(): presses[0] += 1
	button.pressed.connect(on_press)
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion);Input.flush_buffered_events()
	var hovered := root.gui_get_hovered_control()
	check(hovered == button or (hovered != null and button.is_ancestor_of(hovered)), "pointer reaches actual guide location button")
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event);Input.flush_buffered_events()
	await frames(8)
	check(presses[0] == 1, "one real guide location press is delivered")
	if presses[0] != 1: print("ADVANCED_GUIDE_INPUT_DIAGNOSTIC ", JSON.stringify({"point":str(point),"logical":str(logical),"pixels":str(root.size),"viewport":str(root.get_visible_rect()),"hovered":str(hovered),"presses":presses[0]}))
	native_clicks += presses[0]
	if is_instance_valid(button): button.pressed.disconnect(on_press)

func model_mark(game) -> Dictionary:
	return {"advanced":game.state.advanced.duplicate(true),"revision":game.state.revision,"validated_revision":game.state.validated_revision,"checks":game.state.checks.duplicate(true),"work":game.state.work.duplicate(true),"cash":game.state.cash,"completed_ids":game.state.completed_ids.duplicate()}

func save_capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name()=="headless":return
	await frames(4);await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(audit_folder)
	check(root.get_texture().get_image().save_png(audit_folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): requested_case = arg.trim_prefix("--case=")
	if not requested_case.is_empty() and requested_case != "advanced-portal" and not GUIDE.ADVANCED_REVIEW_TARGETS.has(requested_case):
		check(false, "unknown advanced guide case filter"); quit(1); return
	narrow="--narrow" in OS.get_cmdline_user_args();capture_enabled="--capture" in OS.get_cmdline_user_args()
	audit_folder=OS.get_environment("WHL_CAPTURE_DIR")
	if audit_folder.is_empty():audit_folder=ProjectSettings.globalize_path("res://../artifacts/advanced-guide")
	root.size=Vector2i(960,600) if narrow else Vector2i(1440,900)
	var ui:=UI.new();root.add_child(ui);await frames(5)
	var game=ui._game();game.set_process(false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	for case_id in GUIDE.ADVANCED_REVIEW_TARGETS:
		if not requested_case.is_empty() and requested_case != str(case_id): continue
		if not ui.current_kind.is_empty():ui.close_panel(false,false);await frames(3)
		check(accept_fixture(game,case_id),case_id+" accepted fixture")
		ui.controls.menu.hide();ui.open_panel("terminal");var desk=ui.desktop
		desk._show_app("advanced");await frames(6)
		desk.windows.advanced.maximized=true;desk.windows.advanced.position=Vector2.ZERO;desk.windows.advanced.size=desk.workspace.size;await frames(4)
		var review_tab: Button=desk.find_child(str(GUIDE.ADVANCED_REVIEW_TARGETS[case_id]),true,false)
		check(review_tab!=null,case_id+" different starting view exists")
		if review_tab!=null:review_tab.pressed.emit();await frames(4)
		# Begin in a real non-review view and another application. Locate must open
		# the destination view, not merely bring the application's old view forward.
		desk._show_app("mail");await frames(3)
		var before:=model_mark(game)
		await locate_by_mouse(ui.next_task_guide)
		var expected: String=INITIAL_TARGETS[case_id][0]
		var target: Control=desk.find_child(expected,true,false)
		check(desk.current_app=="advanced",case_id+" brings actual app forward")
		check(target!=null and target.is_visible_in_tree(),case_id+" actual destination control is rendered")
		check(ui.next_task_guide.target_rect.has_area(),case_id+" destination is highlighted")
		var workspace_kind := str(game.state.advanced.get("kind", case_id))
		if workspace_kind in ["advanced-hunt","advanced-pentest","advanced-recovery"]:
			check(str(desk.advanced_ui[workspace_kind].get("tab",""))==expected.get_slice("_",1),case_id+" work view selected")
		else:
			var page: Control=desk.find_child("SpecialistPage_"+expected.trim_prefix("SpecialistStage_"),true,false)
			check(page!=null and page.is_visible_in_tree(),case_id+" actual work page is visible")
		var work_control: Control=desk.find_child(str(INITIAL_TARGETS[case_id][1]),true,false)
		check(work_control!=null and work_control.is_visible_in_tree(),case_id+" real work control is displayed")
		if case_id == "advanced-pentest" and work_control != null:
			var resources: Array = work_control.find_children("*", "Button", true, false).filter(func(button): return str(button.get_meta("path", "")) in ["share01", "evidence"])
			check(not work_control is Tree and resources.size() == 2, "guide reaches selectable scope objects on the diagram")
		if case_id == "advanced-pentest-relay" and work_control != null:
			var relay: Button = work_control.find_child("NetworkHost_relay01", true, false)
			check(not work_control is Tree and relay != null and relay.is_visible_in_tree() and str(relay.get_meta("host", "")) == "relay01", "guide reaches the real selectable relay host in the new engagement")
		check(model_mark(game)==before,case_id+" locate leaves observations, validation, billing and work unchanged")
		if case_id in ["advanced-hunt","advanced-cloud"]:await save_capture(case_id+"-guide")
		await locate_by_mouse(ui.next_task_guide)
		check(model_mark(game)==before,case_id+" repeated locate does not execute any gameplay action")
		var current_target: Control=desk.find_child(expected,true,false)
		check(current_target!=null and current_target.is_visible_in_tree(),case_id+" destination survives repeated navigation")
		print("ADVANCED_GUIDE_CASE ",case_id," target=",expected," visible=",current_target!=null and current_target.is_visible_in_tree()," unchanged=",model_mark(game)==before)
	if not requested_case.is_empty() and requested_case != "advanced-portal":
		print("ADVANCED_GUIDE_NAVIGATION failures=",failures.size()," native_clicks=",native_clicks," narrow=",narrow," case=",requested_case)
		ui.queue_free(); await frames(3); quit(0 if failures.is_empty() else 1); return
	if not ui.current_kind.is_empty():ui.close_panel(false,false);await frames(3)
	check(accept_fixture(game,"advanced-portal"),"incident accepted fixture")
	var start: Dictionary=game.advanced_action("incident_start",{"variant":"mixed","seed":7})
	check(start.get("ok",false),"incident started through actual API")
	ui.controls.menu.hide();ui.open_panel("terminal");ui.desktop._show_app("advanced");await frames(6)
	var request_tab: Button=ui.desktop.find_child("PentestTab_request",true,false)
	if request_tab!=null:request_tab.pressed.emit();await frames(4)
	var incident_before:=model_mark(game)
	await locate_by_mouse(ui.next_task_guide)
	check(str(ui.desktop.pentest_ui.get("tab",""))=="operations","incident guide selects operations from another tab")
	check(model_mark(game)==incident_before,"incident locate neither advances tick nor changes data")
	print("ADVANCED_GUIDE_NAVIGATION failures=",failures.size()," native_clicks=",native_clicks," narrow=",narrow)
	ui.queue_free();await frames(3)
	quit(0 if failures.is_empty() else 1)
