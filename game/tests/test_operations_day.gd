extends SceneTree
var ui
var game
var failures: Array[String]=[]
var capture_enabled:=false
var narrow:=false
func _init() -> void:
	capture_enabled="--capture" in OS.get_cmdline_user_args();narrow="--narrow" in OS.get_cmdline_user_args()
	create_timer(45.0).timeout.connect(func():push_error("operations day timeout");quit(2));call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);print("FAIL ",message)
func frames(count:=4) -> void:
	for i in count:await process_frame
func control(id: String):return ui.modal.find_child(id,true,false) if is_instance_valid(ui.modal) else null
func press(id: String) -> void:
	var node=control(id);check(node is BaseButton and not node.disabled,"button "+id)
	if node is BaseButton and not node.disabled:node.pressed.emit()
func select(id: String,index: int) -> void:
	var node=control(id);check(node is OptionButton,"select "+id)
	if node is OptionButton:node.select(index);node.item_selected.emit(index)
func capture(name: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless":return
	await create_timer(0.2).timeout;await frames(3);await RenderingServer.frame_post_draw
	if ui.current_kind=="board":
		check(ui.modal_body.get_global_rect().end.y<=root.size.y and ui.modal_footer.get_global_rect().end.y<=root.size.y,"dispatch content and footer fit viewport")
		check(is_equal_approx(ui.text_scale,1.3 if narrow else 1.0),"native text scale applied")
		var staff_list = control("DispatchStaffScroll")
		if staff_list is ScrollContainer and staff_list.scroll_vertical == 0:
			for member in game.team_members().slice(0,3):
				var staff_select = control("DispatchStaffSelect_"+str(member.id))
				check(staff_select is Control and staff_list.get_global_rect().encloses(staff_select.get_global_rect()), "three staff choices visible " + str(member.id))
	var summary = control("CloseoutSummary")
	if name == "closeout":
		var warnings = control("CloseoutWarnings")
		check(warnings is Control and ui.modal_scroll.get_global_rect().encloses(warnings.get_global_rect()), "unfinished work warning visible before settlement")
	if summary is Control:
		for amount in summary.find_children("*", "Label", true, false):
			if str(amount.text).begins_with("¥"):
				check(amount.autowrap_mode == TextServer.AUTOWRAP_OFF and amount.size.y <= amount.get_theme_font("font").get_height(amount.get_theme_font_size("font_size")) + 2, "currency stays on one line " + amount.text)
	var folder:=ProjectSettings.globalize_path("res://../artifacts/simulator/ui-refinement-20260922/operations" if "--refinement-capture" in OS.get_cmdline_user_args() else "res://../artifacts/simulator/v220/operations" if "--v220-capture" in OS.get_cmdline_user_args() else "res://../artifacts/simulator/dispatch/ui");DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name+("-narrow" if narrow else "-wide")+".png"))==OK,"capture")
func solve_firewall() -> void:
	game.vm_run("ssh client");check(game.capture_baseline(),"real baseline")
	for rule in game._vm().firewall_snapshot().rules:
		rule.action="block" if str(rule.id)=="wan-admin" else "pass"
		check(bool(game.firewall_action("save_rule",{"rule":rule}).get("ok",false)),"real rule save")
	game.firewall_action("services",{"dns":"on","tls":"on"});game.firewall_action("apply")
	for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.id))
	game.verify()
func run() -> void:
	ui=load("res://scripts/interface.gd").new();root.add_child(ui);await frames(1);game=ui._game();game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"isolated storage");ui._new_game();ui.guided_intro.skip();ui._choose_strategy("advisory");if not game.state.career_mode:check(game.start_free_career(),"career fixture transition")
	check(game.state.career_mode and ui.current_kind=="board","new company enters actual operating loop")
	game.state.cash=30000;game.state.credit=200000;game.state.peak_profit=200000;game.state.skills={"advisory":3,"operations":3,"response":3};game.state.equipment=["teamdesk"]
	# This QA day represents two real incoming requests. Seed demand before
	# the normal offer builder so market gating remains exercised.
	game.state.market_day=int(game.state.day);game.state.market_leads=["service-2-case-1","service-2-case-2"];game._make_offers()
	check(game.hire_staff("mio"),"actual employee hired in equipped fixture")
	var wide_size := Vector2i(1920,1080) if "--v220-capture" in OS.get_cmdline_user_args() or "--refinement-capture" in OS.get_cmdline_user_args() else Vector2i(1280,720)
	game.set_settings({"resolution":"960x600" if narrow else "%dx%d" % [wide_size.x,wide_size.y],"window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false);root.size=Vector2i(960,600) if narrow else wide_size
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.open_panel("board");await frames();check(control("OperationsView_contracts")!=null,"board exposes local contract view")
	check(control("OperationsSalesEmpty")!=null,"empty contracts view keeps contextual sales entry")
	press("OperationsSalesEmpty");check(ui.current_kind=="sales","catalog reachable from empty contracts view")
	var first: Dictionary={};var second: Dictionary={}
	for offer in game.state.offers:
		if str(offer.case_id)=="service-2-case-1":first=offer
		if str(offer.case_id)=="service-2-case-2":second=offer
	check(not first.is_empty() and not second.is_empty(),"network client fixtures")
	game.set_offer_plan("care");check(game.choose_contract(str(first.id)),"first actual care contract accepted")
	game.set_offer_plan("standard");check(game.choose_contract(str(second.id)),"parallel contract accepted")
	var active_id:=str(game.state.current_contract_id);ui.open_panel("board");await frames()
	press("DispatchTicket_"+str(first.id));select("DispatchMemberSelector",1);press("DispatchEnqueue");await frames()
	var first_job_id: String="normal|%s|0|aya" % str(first.id)
	var second_job_id: String="normal|%s|0|aya" % str(second.id)
	press("OperationsView_staff");await frames();press("DispatchStart_"+first_job_id);await frames()
	check(str(game.state.current_contract_id)==active_id and str(game.state.assignments.get("aya",{}).get("contract_id",""))==str(first.id),"UI starts other contract without switching PC")
	game._process(1.0);await frames();press("DispatchPause_aya");await frames()
	var remaining: float=game.dispatch_queue("aya")[0].remaining
	await capture("paused")
	press("OperationsView_contracts");await frames();press("DispatchTicket_"+str(second.id));select("DispatchMemberSelector",1);press("DispatchEnqueue");await frames()
	press("OperationsView_staff");await frames();press("DispatchUp_"+second_job_id);await frames()
	check(str(game.dispatch_queue("aya")[0].id)==second_job_id,"UI reorders urgent work ahead of paused work")
	press("DispatchStart_"+second_job_id);await frames();game._process(1.0);await frames()
	await capture("urgent")
	game._process(30.0);await frames()
	check(str(game.state.assignments.get("aya",{}).get("contract_id",""))==str(first.id) and is_equal_approx(float(game.state.assignments.aya.remaining),remaining),"finishing urgent job resumes original remaining effort")
	await capture("morning-workload")
	game._process(30.0);await frames();check(str(game.state.assignments.get("aya",{}).get("status",""))=="done","staff finishes queued work")
	press("OperationsView_contracts");await frames();press("DispatchTicket_"+str(first.id));press("DispatchOpen");await frames();check(ui.current_kind=="terminal" and str(game.state.current_contract_id)==str(first.id),"work row opens correct client PC")
	for index in game.state.targets.size():game.select_target(index);solve_firewall()
	check(game.can_deliver() and game.deliver(),"real repair measured and delivered")
	var same_day:=int(game.state.day);ui.desktop.contracts_requested.emit();await frames()
	check(ui.current_kind=="board" and int(game.state.day)==same_day,"post-delivery next work stays in same operating day")
	press("DispatchTicket_"+str(first.id));press("DispatchReport");await frames();check(ui.current_kind=="terminal" and ui.desktop.windows.receipt.visible,"delivered work opens actual receipt")
	ui.desktop.contracts_requested.emit();await frames()
	await capture("after-delivery")
	var preview: Dictionary=game.day_preview();check(int(preview.contract_net)>0 and int(preview.open_contracts)==1,"profit and unfinished client visible")
	press("OperationsCloseDay");await frames();check(ui.current_kind=="door" and control("DaySettle")!=null,"review precedes day settlement")
	await capture("closeout")
	for group in ["CloseoutOperating", "CloseoutCash"]:
		var disclosure: Button = control(group + "Disclosure")
		disclosure.button_pressed = true; disclosure.pressed.emit(); await frames()
		var rows: Control = control(group + "Rows")
		check(rows.visible, group + " opens actual detail")
		for amount in rows.find_children(group + "Value*", "Label", true, false):
			check(amount.get_line_count() == 1, group + " amount stays on one line")
			check(amount.get_global_rect().end.x <= ui.modal_scroll.get_global_rect().end.x, group + " amount fits width")
		ui.modal_scroll.ensure_control_visible(rows.get_child(0)); await frames()
		await capture("closeout-" + group)
		disclosure.button_pressed = false; disclosure.pressed.emit(); await frames()
	ui.modal_scroll.scroll_vertical = 0
	var before_state: Dictionary=game.state.duplicate(true);var valid_path:=str(game.save_path)
	game.save_path="user://missing-operations-day/save.json";check(not game.end_day(),"failed day save rejected");game.save_path=valid_path
	check(game.state==before_state,"failed close rolls back ledger cash and day")
	press("DaySettle");await frames();check(int(game.state.day)==same_day+1 and ui.current_kind=="day_review","day closes into persisted result")
	var settled: Dictionary=game.last_day_ledger();check(int(settled.day)==same_day and int(settled.total_profit)==int(preview.total_profit) and int(settled.cash_after)==int(preview.cash_after),"review agrees with actual money settlement")
	check(int(settled.payroll_due)>0 and int(settled.paid_wages)==int(settled.payroll_due) and int(settled.hiring_cost)>0,"closeout retains earned wage cost and actual payment")
	await capture("day-result")
	ui.open_panel("shop");await frames();check(ui.current_kind=="shop","global navigation leads into investment")
	var profit_before:=int(game.state.profit);check(game.buy_equipment("monitor"),"equipment order purchased from earned cash")
	check(int(game.day_preview().investment_spending)==game.equipment_price("monitor") and int(game.state.profit)==profit_before,"investment is cash use not operating expense")
	game.advance_delivery(31.0);ui.open_panel("board");await frames();check(control("OperationsReceive")!=null,"delivered purchase visible next to work")
	check(game.save_game() and game.load_game(),"save and reopen day")
	check(game.last_day_ledger()==JSON.parse_string(JSON.stringify(settled)),"ledger survives reopening")
	await maintenance_controls()
	print("OPERATIONS_DAY failures=",failures.size());quit(0 if failures.is_empty() else 1)

func maintenance_controls() -> void:
	var fixture:=ProjectSettings.globalize_path("res://../artifacts/simulator/v122/legacy-v121-care.json")
	check(DirAccess.copy_absolute(fixture,ProjectSettings.globalize_path(game.save_path))==OK and game.load_game(),"load isolated real maintenance fixture")
	check(game.end_day(),"prepare actual maintenance day")
	var client:=str(game.state.care_agreements.keys()[0])
	ui.open_panel("board");await frames();press("OperationsView_maintenance");await frames()
	press("DispatchTicketMaintenance_"+client.sha256_text().left(8));await frames()
	check(control("DispatchSelfCheck").visible and not control("DispatchSelfCheck").disabled,"manual maintenance action remains available")
	select("OperationsCareOwner_"+client.sha256_text().left(8),0);await frames()
	check(game.maintenance_owner(client)=="","maintenance owner menu works")
	select("DispatchMemberSelector",1);press("DispatchEnqueue");await frames()
	var id: String="maintenance|"+client
	press("OperationsView_staff");await frames();press("DispatchStart_"+id);await frames();game._process(1.0);press("DispatchPause_aya");await frames()
	await capture("maintenance-paused")
	press("DispatchStart_"+id);await frames();game._process(20.0);await frames()
	check(str(game._maintenance_job_for(client).get("status","")) in ["done","failed"],"maintenance runs to a measured outcome")
	press("OperationsView_maintenance");await frames();press("DispatchReport");await frames()
	check(ui.current_kind=="terminal" and not game.maintenance_result(client).is_empty(),"maintenance report opens actual result")
