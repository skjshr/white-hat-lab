extends SceneTree

const VIEW = preload("res://scripts/equipment_activity_view.gd")
const DISPLAY = preload("res://scripts/equipment_activity_display.gd")
class Fixture:
	extends RefCounted
	var state := {"equipment":["monitor"], "assignments":{}, "dispatch_queues":{}, "contract":{"client":"実測顧客", "title":"通常作業"}, "current_contract_id":"contract-a"}
	var _office_clock_paused := false
	var available := true
	var connected := true
	func member_name(id: String) -> String: return id
	func colleague_runtime_availability(_id: String) -> Dictionary: return {"available":available}
	func _colleague_hardware_connected(_job: Dictionary) -> bool: return connected

var failures: Array[String] = []
var assertions := 0
var cues: Array[String] = []
var game
var office
var narrow := false
var render := false
var folder := ""

func _init() -> void:
	narrow = "--narrow" in OS.get_cmdline_user_args()
	render = "--capture" in OS.get_cmdline_user_args()
	folder = OS.get_environment("WHL_CAPTURE_DIR")
	create_timer(135).timeout.connect(func(): push_error("equipment activity timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count := 4) -> void:
	for _i in count: await process_frame

func work(key := "work-a", role := "aya", status := "working") -> Dictionary:
	var actual := 14.0 if role == "ren" else 7.0
	return {"kind":"normal", "status":status, "equipment_work_id":key, "equipment_effects":{"monitor":{"base_minutes":actual+1,"actual_minutes":actual,"saved_minutes":1.0}}, "role":role, "remaining":actual-2, "total":actual, "work_minutes":actual, "contract_id":"contract-a", "target_index":0}

func fixture_checks() -> void:
	var f := Fixture.new()
	for member in ["aya", "ren", "hired_aya", "hired_ren"]:
		var role := "ren" if member.ends_with("ren") else "aya"
		f.state.assignments = {member:work(member,role)}
		var before := JSON.stringify(f.state)
		var projected: Dictionary = VIEW.build(f)
		check(projected.jobs.size() == 1 and projected.jobs[0].mode == "active" and projected.jobs[0].saved_minutes == 1.0, "actual role attribution " + member)
		check(JSON.stringify(f.state) == before, "adapter read-only " + member)
	f.state.assignments = {"aya":work()}
	f.state.equipment = []
	check(VIEW.build(f).jobs.is_empty(), "uninstalled equipment is off")
	f.state.equipment = ["monitor"]
	f.state.assignments.aya.erase("equipment_work_id")
	check(VIEW.build(f).jobs.is_empty(), "legacy no identity is not attributed")
	f.state.assignments.aya = work()
	f.state.assignments.aya.equipment_effects = {}
	check(VIEW.build(f).jobs.is_empty(), "queued before purchase remains unattributed")
	f.state.assignments.aya = work()
	f.state.assignments.aya.kind = "maintenance"
	check(VIEW.build(f).jobs.is_empty(), "maintenance has no ordinary delegation bonus")
	f.state.assignments.aya = work()
	f.state.assignments.aya.status = "cancelled"
	check(VIEW.build(f).jobs.is_empty(), "cancelled work is off")
	f.state.assignments.aya = work()
	f.state.assignments.aya.equipment_effects.monitor.actual_minutes = 6.0
	check(VIEW.build(f).jobs.is_empty(), "inconsistent saved duration is rejected")
	f.state.assignments.aya = work()
	f.available = false
	check(VIEW.build(f).jobs[0].mode == "waiting", "unavailable colleague is not productive")
	f.available = true; f.connected = false
	check(VIEW.build(f).jobs[0].mode == "blocked", "missing customer hardware is not productive")
	f.connected = true; f._office_clock_paused = true
	check(VIEW.build(f).jobs[0].mode == "paused", "office pause freezes activity")
	f._office_clock_paused = false
	f.state.assignments = {}
	f.state.dispatch_queues = {"aya":[work("paused","aya","paused")]}
	check(VIEW.build(f).jobs[0].mode == "paused", "paused queue preserves attributed work")
	f.state.assignments = {"ren":work("active","ren")}
	check(VIEW.build(f).jobs[0].key == "active", "active work is selected ahead of paused work")
	var display := DISPLAY.new()
	root.add_child(display)
	display.activated.connect(func(key): cues.append(key))
	var v: Dictionary = VIEW.build(f)
	display.sync(v,true)
	check(cues.is_empty(), "restored active screen mounts silently")
	check(display.saving.text.begins_with("15 → 14 分"), "actual locked timing comparison renders")
	display.sync({"installed":true,"jobs":[]},true)
	var j: Dictionary = v.jobs[0].duplicate(true)
	j.key = "new-live"; j.mode = "waiting"; j.progress = 0.0
	display.sync({"installed":true,"jobs":[j]},true)
	check(cues.is_empty(), "assignment before real progress is silent")
	j.mode = "active"; j.progress = 0.2
	display.sync({"installed":true,"jobs":[j]},true)
	check(cues == ["new-live"] and display.pulse > 0.0, "actual live advance cues once and animates")
	display.sync({"installed":true,"jobs":[j]},true)
	check(cues.size() == 1, "repeated state is silent")
	j.mode = "paused"
	display.sync({"installed":true,"jobs":[j]},true)
	check(display.pulse == 0.0 and is_equal_approx(display.packet_progress,0.2), "paused diagram freezes without pulse")
	j.mode = "active"; j.progress = 0.4
	display.sync({"installed":true,"jobs":[j]},true,true)
	check(cues.size() == 1 and display.pulse == 0.0 and is_equal_approx(display.packet_progress,0.4), "resume silent and reduced motion static")
	j.key = "restored"; j.progress = 0.5
	display.sync({"installed":true,"jobs":[j]},false)
	display.sync({"installed":true,"jobs":[j]},true)
	check(cues.size() == 1, "title and resume do not replay activation")
	j.key = "future"; j.mode = "queued"; j.progress = 0.0
	display.sync({"installed":true,"jobs":[j]},true)
	j.mode = "active"; j.progress = 0.1
	display.sync({"installed":true,"jobs":[j]},true)
	check(cues == ["new-live","future"], "future queued job cues on first actual progress")
	display.sync({"installed":false,"jobs":[]},true)
	check(display.selected.is_empty() and display.pulse == 0, "off state clears work graphics")
	display.queue_free()

func capture(label: String, surface := false) -> void:
	if not render: return
	await frames(5)
	await RenderingServer.frame_post_draw
	var suffix := "-narrow" if narrow else "-wide"
	var picture: Image = office.monitors.monitor.viewport.get_texture().get_image() if surface else root.get_texture().get_image()
	check(picture.save_png(folder.path_join(label+suffix+".png")) == OK, "capture " + label)

func run() -> void:
	fixture_checks()
	await frames(2)
	cues.clear()
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-equipment-activity-"): quit(2); return
	game.set_process(false)
	check(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(), "normal funded company")
	game.settings.volume = 0
	game.settings.text_scale = 1.3 if narrow else 1.0
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked",false)) and bool(item.get("market_available",true)) and str(item.get("case_id","")) == "service-2-case-0")
	check(not offers.is_empty() and game.choose_contract(str(offers[0].id)), "real available ordinary contract")
	if offers.is_empty(): quit(1); return
	var contract_id: String = game.state.current_contract_id
	# Reserve before purchase: production queue must retain its original duration.
	check(game.dispatch_enqueue("aya",contract_id,0), "reserve real work before purchase")
	var reserved: Dictionary = game.state.dispatch_queues.aya[0].duplicate(true)
	check(reserved.total == 8.0 and reserved.get("equipment_effects",{}).is_empty(), "reserved work has no future bonus")
	check(game.buy_equipment("monitor") and int(game.state.cash) == 1000, "real purchase pays four thousand")
	check(game.team_work_duration("aya") == 8.0, "ordered equipment has no effect")
	office = load("res://scripts/office.gd").new(); root.add_child(office)
	await frames(12)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900)
	office._start(); office.ui.controls.menu.hide(); office.ui.current_kind = ""; office.ui._sync_office_clock_pause()
	office.player.set_physics_process(false)
	office.player.position = Vector3(1.4,0.05,0.6)
	office.player.camera.look_at(Vector3(0,1,-1.03),Vector3.UP)
	if render:
		if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../artifacts/equipment-activity")
		DirAccess.make_dir_recursive_absolute(folder)
	# Delivery advances with real elapsed time, without starting the reserved job.
	game.set_delivery_clock_paused(false)
	var delivery_start := Time.get_ticks_msec()
	if render:
		while str(game.delivery_for("monitor").get("status","")) != "ready" and Time.get_ticks_msec()-delivery_start < 36000:
			var before := Time.get_ticks_usec()
			await process_frame
			game.advance_delivery(float(Time.get_ticks_usec()-before)/1000000.0)
	else:
		game.advance_delivery(30.1)
	var delivery_elapsed := float(Time.get_ticks_msec()-delivery_start)/1000.0
	check(str(game.delivery_for("monitor").get("status","")) == "ready", "delivery reaches ready")
	check(office.delivery.interact("pickup","monitor") and office.delivery.interact("place_start","monitor"), "carry and unpack actual monitor")
	office.delivery.update_placement_preview([0.0,0.8,-1.03],PI/2)
	check(office.delivery.placement_valid() and office.delivery.interact("confirm","monitor"), "valid installed physical monitor")
	check(game.team_work_duration("aya") == 7.0 and int(game.state.cash) == 1000, "installed effect and unchanged actual cash")
	check(game.dispatch_start("aya",str(reserved.id)), "start originally reserved work")
	check(float(game.state.assignments.aya.total) == 8.0 and game.state.assignments.aya.equipment_effects.is_empty(), "old queue start does not invent saving")
	check(VIEW.build(game).jobs.is_empty(), "old queue has no operational attribution")
	game.set_process(true)
	var old_finish_start := Time.get_ticks_msec()
	while game.state.assignments.get("aya",{}).get("status","") == "working" and Time.get_ticks_msec()-old_finish_start < 18000: await process_frame
	game.set_process(false)
	check(game.state.assignments.get("aya",{}).get("status","") == "done", "older reservation finishes at its locked duration")
	office.monitors.monitor.equipment_activated.connect(func(key): cues.append(key))
	await capture("01-installed-idle")
	game.assign_colleague("aya")
	check(game.state.assignments.get("aya",{}).get("status","") == "working", "actual new ordinary assignment")
	var assignment: Dictionary = game.state.assignments.aya.duplicate(true)
	check(assignment.total == 7.0 and assignment.equipment_effects.monitor.saved_minutes == 1.0 and not str(assignment.equipment_work_id).is_empty(), "new job locks real monitor saving")
	game.set_process(true)
	await create_timer(2.1).timeout
	game.set_process(false)
	await frames(2)
	var monitor = office.monitors.monitor
	monitor.refresh(true,true)
	check(monitor.activity_display.selected.get("mode","") == "active" and monitor.activity_display.selected.get("client","") == "港町クリニック", "physical monitor shows actual active client")
	check(cues.size() == 1, "one actual native activation event")
	var sound = root.get_node("Soundscape")
	check(sound._players.all(func(player): return not player.playing), "existing sound path respects muted effects")
	await capture("02-operating-world")
	await capture("03-operating-surface",true)
	check(game.dispatch_pause("aya"), "pause real assisted work")
	monitor.refresh(true,true)
	check(monitor.activity_display.selected.mode == "paused" and monitor.activity_display.pulse == 0, "real pause freezes physical display")
	await capture("04-paused-surface",true)
	var paused: Dictionary = game.state.dispatch_queues.aya[0].duplicate(true)
	check(game.dispatch_start("aya",str(paused.id)), "resume same assisted work")
	monitor.refresh(true,true)
	check(str(game.state.assignments.aya.equipment_work_id) == str(assignment.equipment_work_id) and cues.size() == 1, "real resume keeps identity and remains silent")
	check(game.save_game() and game.load_game(), "save and load actual assisted work")
	monitor.reset_activity_feedback(); monitor.refresh(true,true)
	check(cues.size() == 1, "restored active physical display remains silent")
	var before_state := JSON.stringify(game.state)
	var before_machine = game._machine
	for _i in 12: monitor.refresh(true,true)
	check(JSON.stringify(game.state) == before_state and game._machine == before_machine, "repeated physical rendering does not mutate state or create VM")
	game.set_process(true)
	var finish_start := Time.get_ticks_msec()
	while game.state.assignments.get("aya",{}).get("status","") == "working" and Time.get_ticks_msec()-finish_start < 16000: await process_frame
	game.set_process(false)
	monitor.refresh(true,true)
	check(game.state.assignments.get("aya",{}).get("status","") == "done" and monitor.activity_display.selected.get("mode","") == "done", "actual saved completion resolves result icon")
	check(cues.size() == 1, "completion does not duplicate activation cue")
	await capture("05-completed-surface",true)
	print("EQUIPMENT_ACTIVITY_FIXTURE adapter fixtures explicit; integration normal funds, real purchase and placement; native delivery elapsed seconds=", delivery_elapsed, "; headless only accelerates delivery through public advance_delivery")
	print("EQUIPMENT_ACTIVITY_PASS assertions=",assertions," narrow=",narrow," failures=",failures)
	office.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
