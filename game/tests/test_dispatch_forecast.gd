extends SceneTree

var game
var failures: Array[String] = []

func _init() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("dispatch forecast timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL: ",label)

func offers() -> Array:
	return game.state.offers.filter(func(item): return item is Dictionary and bool(item.get("unlocked",false)) and bool(item.get("market_available",true)))

func run() -> void:
	game=load("res://scripts/game.gd").new();root.add_child(game);await process_frame;game.set_process(false)
	var suffix: String = "forecast-%d" % OS.get_process_id();game.save_path="user://qa-"+suffix+".json";game.backup_path=game.save_path+".bak";game.previous_path=game.save_path+".previous";game.settings_path=game.save_path+".settings";game._reset_state()
	check(game.choose_strategy("advisory") and game.start_free_career(),"career setup")
	game.state.credit=1000000;game.state.peak_profit=1000000;game.state.skills={"advisory":10,"operations":10,"response":10};game._make_offers()
	var available:=offers();check(available.size()>=2,"two forecast contracts")
	if available.size()<2: quit(1);return
	var a:=str(available[0].id);var b:=str(available[1].id);var specialist_offer: Dictionary={}
	for offer in available:
		if int(offer.get("chapter",-1)) == 1 and int(offer.get("targets",1)) >= 2:
			specialist_offer=offer;break
	var c:=str(specialist_offer.get("id", ""));check(not c.is_empty() and game.choose_contract(a) and game.choose_contract(b) and game.choose_contract(c),"accept forecast contracts")
	check(game.staff_workload("aya").get("jobs",[]).is_empty(),"empty workload has no jobs")
	check(game.dispatch_enqueue("aya",a,0),"enqueue active forecast job")
	var queued: Dictionary=game.staff_workload("aya");check(queued.jobs.size()==1 and float(queued.jobs[0].remaining_minutes)>0.0,"queued job has labor duration")
	var quote: Dictionary=game.dispatch_quote_forecast("aya",b,0);check(str(quote.get("blocked_reason",""))!="staffing_busy","candidate forecast is not falsely blocked by current queue")
	check(game.dispatch_enqueue("aya",c,0),"enqueue observer job on supported chapter")
	var ren_wait: Dictionary=game.dispatch_quote_forecast("ren",c,0);check(str(ren_wait.get("blocked_reason",""))=="dispatch_waiting","Ren forecast waits for Aya on the same target")
	var id:=str(game.state.dispatch_queues.aya[0].id);check(game.dispatch_start("aya",id),"start active forecast job");game._process(1.0)
	var active: Dictionary=game._assignments.aya
	var original_active: Dictionary=active.duplicate(true)
	active.total=30.0;active.remaining=15.0;active.work_minutes=12.0;active.work_started_at=540.0;active.work_started_day=game.state.day;active.segment_minutes=12.0
	var forecast: Dictionary=game.staff_workload("aya")
	check(is_equal_approx(float(forecast.jobs[0].remaining_minutes),6.0) and int(forecast.jobs[0].finish_minute)==552,"legacy runtime seconds convert to labor and anchored finish")
	game._assignments.aya=original_active
	check(game.dispatch_pause("aya"),"pause forecast job");var held: Dictionary=game.staff_workload("aya");check(bool(held.held),"pause exposes manual hold");var held_quote: Dictionary=game.dispatch_quote_forecast("aya",b,0);check(str(held_quote.blocked_reason)=="dispatch_hold" and int(held_quote.job.finish_minute)==-1,"held worker forecast is blocked without a finish promise")
	# A real supply requirement with no assigned unit exposes the hardware blocker.
	game.state.dispatch_holds.erase("aya")
	check(game.switch_contract(a),"activate real hardware fixture context")
	game.state.contract.supply_requirement={"sku":"gateway","quantity":1,"target_index":0}
	var hardware_quote: Dictionary=game.dispatch_quote_forecast("aya",a,0);check(str(hardware_quote.blocked_reason)=="stock_error_hardware","hardware blocker is visible before staging")
	game.state.contract.erase("supply_requirement");game._sync_contract_context()
	# Hired worker at the end of a day rolls whole work to the next eligible shift.
	game.state.clock_minutes=1075;game.state.equipment.append("teamdesk");game.state.cash=100000
	check(game.hire_staff("mio","day"),"hire forecast worker")
	check(game.set_staff_shift("mio","afternoon"),"future shift is accepted")
	check(game.dispatch_enqueue("mio",b,0),"late-day worker queues a real accepted contract")
	var second_ok: bool=game.dispatch_enqueue("mio",c,1);check(second_ok,"second real target queues behind the first")
	var hired_quote: Dictionary=game.dispatch_quote_forecast("mio",b,0);check(int(hired_quote.job.start_day)>int(game.state.day) and int(hired_quote.job.start_minute)>=780,"late-day hired work rolls to next day pending shift")
	var mio_queue: Dictionary=game.staff_workload("mio");check(mio_queue.jobs.size()>=2 and int(mio_queue.jobs[1].start_day)>=int(mio_queue.jobs[0].finish_day) and (int(mio_queue.jobs[1].start_day)>int(mio_queue.jobs[0].start_day) or int(mio_queue.jobs[1].start_minute)>=int(mio_queue.jobs[0].finish_minute)),"future jobs are sequential")
	# An active job's anchor must not move backward when the wall clock and raw runtime diverge.
	game.state.contract.erase("supply_requirement");game._sync_contract_context()
	game.state.dispatch_holds.erase("aya");var active_id:=str(game.state.dispatch_queues.aya[0].id);check(game.dispatch_start("aya",active_id),"restart paused real job")
	game.state.clock_minutes=552
	var anchored: Dictionary=game.staff_workload("aya");var anchor_job: Dictionary=game._assignments.aya;var anchor_expected:=int(anchor_job.get("work_started_day",game.state.day))*1440+int(anchor_job.get("work_started_at",540))+int(anchor_job.get("segment_minutes",0));var anchor_finish:=int(anchored.jobs[0].finish_day)*1440+int(anchored.jobs[0].finish_minute);check(anchored.jobs.size()>0 and anchor_finish>=anchor_expected and anchor_finish>=int(game.state.day)*1440+552,"active anchor remains at or after 09:12")
	# Used minutes reduce daily capacity once; they do not consume the wall-clock window a second time.
	game.state.clock_minutes=1020;game.state.staff.mio.minutes_day=game.state.day;game.state.staff.mio.minutes_used=10.0;var mio_work: Dictionary=game.staff_workload("mio");check(is_equal_approx(float(mio_work.get("capacity_minutes",0.0)),60.0),"used minutes do not double subtract wall-clock capacity")
	var before: Dictionary=game.state.duplicate(true);var workload: Dictionary=game.staff_workload("mio");check(game.state==before,"forecast is read-only")
	if failures.is_empty():print("DISPATCH_FORECAST_TEST_PASS")
	else:print("DISPATCH_FORECAST_TEST_FAIL count=%d"%failures.size())
	quit(1 if not failures.is_empty() else 0)
