extends SceneTree

const GAME = preload("res://scripts/game.gd")
const GUIDE = preload("res://scripts/next_task_guide.gd")
var failures: Array[String] = []
var assertions := 0
var serial := 0

func _init() -> void:
	create_timer(80.0).timeout.connect(func(): push_error("INCIDENT_INTEGRATION_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ",label)

func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func without_exercise(value: Variant) -> Variant:
	if value is Dictionary:
		var output: Dictionary = {}
		for key in value:
			if str(key) != "exercise": output[key] = without_exercise(value[key])
		return output
	if value is Array:
		var output: Array = []
		for item in value: output.append(without_exercise(item))
		return output
	return value

func original_state(game: Node) -> String:
	return canonical(without_exercise(game.state))

func new_game() -> Node:
	serial += 1
	var game: Node = GAME.new(); root.add_child(game); game.set_process(false)
	var stem := "user://qa-incident-integration-%d-%d" % [OS.get_process_id(),serial]
	game.save_path = stem+".json"; game.backup_path = stem+".bak"; game.previous_path = stem+".previous"; game.settings_path = stem+".settings"
	game._reset_state()
	check(game.choose_strategy("advisory") and game.start_free_career(),"start ordinary company")
	var selected: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id","")) == "advanced-portal" and bool(offer.get("unlocked",false)) and bool(offer.get("market_available",false)):
			selected = offer; break
	check(not selected.is_empty(),"existing portal case is available without unlock cheats")
	check(not selected.is_empty() and game.choose_contract(str(selected.get("id",""))),"accept existing case using public API")
	# Start from a real reopened case, including load_game's last_load_error metadata.
	# Keep every later deep equality assertion exact; do not omit persisted fields.
	check(game.save_game() and game.load_game(),"initialize ordinary saved-case bookkeeping through real save/load")
	return game

func request(game: Node, method: String, path: String, token := "", body: Dictionary = {}) -> Dictionary:
	var result: Dictionary = game.advanced_action("request",{"method":method,"path":path,"session":token,"body":body,"headers":{}})
	check(bool(result.get("ok",false)),"persist real HTTP request "+method+" "+path)
	return result

func login(game: Node, username: String) -> String:
	var password: String = {"alice":"Alice-demo-27","beth":"Beth-demo-27"}[username]
	var result := request(game,"POST","/api/auth/login","",{"username":username,"password":password})
	check(int(result.get("response",{}).get("status",0)) == 200,"authenticate normal case "+username)
	return str(result.get("response",{}).get("data",{}).get("session",""))

func pin(game: Node, result: Dictionary) -> void:
	check(bool(game.advanced_action("pin",{"id":str(result.get("request_id",""))}).get("ok",false)),"preserve actual normal-case evidence")

func exercise_action(game: Node, action: String, args: Dictionary = {}) -> Dictionary:
	var before := original_state(game)
	var result: Dictionary = game.advanced_action(action,args)
	check(bool(result.get("exercise_only",false)) and float(result.get("minutes",-1)) == 0,action+" uses exercise-only transaction")
	check(original_state(game) == before,action+" preserves company clock/work/economy/verification and all original case state")
	return result

func op(game: Node, operation: String, args: Dictionary = {}, command := "") -> Dictionary:
	var request_args := args.duplicate(true)
	request_args.run_id = str(game.state.advanced.get("exercise",{}).get("run_id","")); request_args.op = operation
	if not command.is_empty(): request_args.command_id = command
	return exercise_action(game,"incident_action",request_args)

func fail_saving(game: Node, action: String, args: Dictionary, label: String) -> void:
	var good_path := str(game.save_path)
	var before := canonical(game.state)
	var assignments: Dictionary = game._assignments.duplicate(true)
	game.save_path = "user://missing-incident-%d-%d/save.json" % [OS.get_process_id(),serial]
	var result: Dictionary = game.advanced_action(action,args)
	check(not bool(result.get("ok",true)) and not bool(result.get("changed",true)),label+" rejects unpersisted operation")
	check(canonical(game.state) == before and game._assignments == assignments,label+" rolls back entire state, branch, event IDs, time and assignments")
	game.save_path = good_path

func resume(game: Node) -> Node:
	check(game.save_game(),"save incident checkpoint")
	var before := canonical(game.state)
	var restored: Node = GAME.new(); root.add_child(restored); restored.set_process(false)
	for key in ["save_path","backup_path","previous_path","settings_path"]: restored.set(key,game.get(key))
	check(restored.load_game(),"load real incident checkpoint")
	check(canonical(restored.state) == before,"save/load preserves source, branch, decisions and original evidence")
	game.queue_free()
	return restored

func test_lifecycle_and_rollback() -> void:
	var game := new_game()
	var alice := login(game,"alice")
	var baseline := request(game,"GET","/api/invoices/INV-N204",alice); pin(game,baseline)
	game.verify()
	var source_before := original_state(game)
	var parent_history := canonical(game.advanced_view().get("history",[]))
	fail_saving(game,"incident_start",{"variant":"mixed","seed":23},"failed start")
	check(bool(exercise_action(game,"incident_start",{"variant":"mixed","seed":23}).get("ok",false)),"start succeeds once storage recovers")
	if not game.state.advanced.has("exercise"): game.queue_free(); return
	var run_id := str(game.state.advanced.exercise.run_id)
	check(game.incident_active(),"game detects active exercise")
	check(str(GUIDE.resolve(game).get("id","")) == "incident","active exercise guide directs the operator to response work")
	var before_verify := canonical(game.state)
	check(game.verify().is_empty() and not game.can_deliver() and not game.deliver(),"exercise cannot verify or deliver original case")
	check(canonical(game.state) == before_verify,"blocked verification/delivery does not mutate original or branch")
	var event: Dictionary = {}
	for row in op(game,"audit").get("response",{}).get("data",{}).get("events",[]):
		if str(row.get("method","")) == "PATCH" and int(row.get("status",0)) == 200: event = row; break
	check(not event.is_empty(),"branch has a real initial alteration")
	if event.is_empty(): game.queue_free(); return
	fail_saving(game,"incident_action",{"run_id":run_id,"op":"revoke_session","session_id":str(event.session_id),"command_id":"durable-revoke"},"failed containment")
	var tick_before := int(game.state.advanced.exercise.tick)
	var revoked := op(game,"revoke_session",{"session_id":str(event.session_id)},"durable-revoke")
	check(bool(revoked.get("ok",false)) and int(game.state.advanced.exercise.tick) == tick_before+1,"retry applies containment exactly once")
	var after_revoke := canonical(game.state)
	var duplicate := op(game,"revoke_session",{"session_id":str(event.session_id)},"durable-revoke")
	check(bool(duplicate.get("duplicate",false)) and canonical(game.state) == after_revoke,"duplicate containment cannot charge a second tick")
	fail_saving(game,"incident_action",{"run_id":run_id,"op":"advance","command_id":"durable-advance"},"failed tick")
	check(bool(op(game,"advance",{},"durable-advance").get("ok",false)),"failed tick retries normally")
	check(original_state(game) == source_before,"damage and containment never alter parent case progress")
	game = resume(game)
	check(game.incident_active() and str(game.state.advanced.exercise.run_id) == run_id,"active run resumes after reload")
	var advance_snapshot := canonical(game.state)
	check(bool(op(game,"advance",{},"durable-advance").get("duplicate",false)) and canonical(game.state) == advance_snapshot,"command idempotency survives disk reload")
	fail_saving(game,"incident_leave",{},"failed leave")
	var leave_tick := int(game.state.advanced.exercise.tick)
	check(bool(exercise_action(game,"incident_leave").get("ok",false)) and not game.incident_active(),"leave returns to original case")
	check(str(GUIDE.resolve(game).get("id","")) != "incident","leaving restores the ordinary case guide")
	check(canonical(game.advanced_view().get("history",[])) == parent_history,"paused view returns exact original communications")
	game = resume(game)
	check(not game.incident_active() and int(game.state.advanced.exercise.tick) == leave_tick,"paused run does not advance during reload")
	fail_saving(game,"incident_resume",{},"failed resume")
	check(bool(exercise_action(game,"incident_resume").get("ok",false)) and int(game.state.advanced.exercise.tick) == leave_tick,"resume restores the same paused run")
	var normal_report: Dictionary = game.advanced_action("submit_report",{"claim":"authenticated_cross_tenant_read","evidence_ids":[]})
	check(not bool(normal_report.get("ok",true)) and original_state(game) == source_before,"exercise activity cannot be submitted as parent penetration-test evidence")
	var finished := op(game,"finish",{},"finish-once")
	check(bool(finished.get("ok",false)),"incomplete response can conclude honestly")
	var before_restart := canonical(game.state)
	fail_saving(game,"incident_restart",{"variant":"exfil","seed":19,"command_id":"restart-once"},"failed replay")
	check(canonical(game.state) == before_restart,"failed replay keeps concluded run and summaries")
	check(bool(exercise_action(game,"incident_restart",{"variant":"exfil","seed":19,"command_id":"restart-once"}).get("ok",false)),"explicit replay starts after persistence recovers")
	check(str(game.state.advanced.exercise.run_id) != run_id and original_state(game) == source_before,"replay changes run identity without changing original case")
	game.queue_free()

func deliver_parent(game: Node) -> bool:
	var alice := login(game,"alice"); var beth := login(game,"beth")
	var normal := request(game,"GET","/api/invoices/INV-N204",alice); pin(game,normal)
	var created := request(game,"POST","/api/exports",beth,{"invoice_id":"INV-S108"})
	var job: Dictionary = created.get("response",{}).get("data",{})
	if not job.has("status_url"): return false
	request(game,"GET",str(job.status_url),beth); request(game,"GET",str(job.status_url),beth)
	var attack := request(game,"GET",str(job.download_url),alice); pin(game,attack)
	check(bool(game.advanced_action("submit_report",{"claim":"authenticated_cross_tenant_read","evidence_ids":[str(normal.request_id),str(attack.request_id)]}).get("ok",false)),"normal case report accepted")
	check(bool(game.advanced_action("customer_fix").get("ok",false)),"normal case receives its patch")
	pin(game,request(game,"GET",str(job.download_url),alice)); pin(game,request(game,"GET","/api/invoices/INV-N204",alice))
	check(game.verify().all(func(row): return bool(row.passed)) and game.can_deliver(),"normal case passes real original-request retests")
	return game.deliver()

func test_delivered_case_safety() -> void:
	var game := new_game()
	check(deliver_parent(game),"deliver real parent case before later exercise")
	check(game.current_done(),"parent case is already delivered")
	game = resume(game)
	var original := original_state(game)
	var receipt := canonical(game.completion_receipt())
	check(bool(exercise_action(game,"incident_start",{"variant":"exfil","seed":7}).get("ok",false)),"delivered case still supports explicit exercise")
	check(str(GUIDE.resolve(game).get("id","")) == "incident","delivered case guide prioritizes its active exercise")
	if not game.state.advanced.has("exercise"): game.queue_free(); return
	check(bool(op(game,"advance",{},"after-delivery-tick").get("ok",false)),"delivered exercise has real ongoing activity")
	check(bool(op(game,"finish",{},"after-delivery-finish").get("ok",false)),"delivered exercise can conclude")
	check(bool(exercise_action(game,"incident_restart",{"variant":"mixed","seed":11}).get("ok",false)),"delivered exercise can replay")
	check(bool(exercise_action(game,"incident_leave").get("ok",false)),"leave returns to delivered normal case")
	check(str(GUIDE.resolve(game).get("id","")) != "incident","delivered guide returns to ordinary next work after leave")
	check(original_state(game) == original and canonical(game.completion_receipt()) == receipt,"exercise cannot change completed receipt, grade, billing or company income")
	var before := canonical(game.state)
	check(not bool(game.advanced_action("request",{"method":"GET","path":"/api/invoices","session":"alice"}).get("changed",true)),"ordinary request after delivered exercise remains rejected")
	check(not game.deliver() and canonical(game.state) == before,"leaving exercise cannot enable duplicate delivery or mutate the saved case")
	game.queue_free()

func test_background_clock_isolation() -> void:
	var game := new_game()
	var portal_id := str(game.state.current_contract_id)
	game.state.market_leads.append("service-0-case-0"); game.state.market_day = int(game.state.day); game._make_offers()
	var ordinary: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id","")) == "service-0-case-0" and bool(offer.get("unlocked",false)) and bool(offer.get("market_available",false)): ordinary = offer; break
	check(not ordinary.is_empty() and game.choose_contract(str(ordinary.get("id",""))),"accept real parallel VM work for background clock test")
	game.vm_run("ssh client"); game.assign_colleague("aya")
	check(str(game.state.assignments.get("aya",{}).get("status","")) == "working","real colleague assignment is running")
	var purchased := false
	for item in game.equipment_catalog():
		if game.equipment_unavailable_reason(str(item.id)).is_empty() and game.buy_equipment(str(item.id)): purchased = true; break
	check(purchased and not game.state.delivery_orders.is_empty(),"real equipment purchase has a delivery timer")
	check(game.switch_contract(portal_id),"return to invoice case with real background work pending")
	game.set_delivery_clock_enabled(true); game.set_delivery_clock_paused(false)
	check(bool(exercise_action(game,"incident_start",{"variant":"mixed","seed":37}).get("ok",false)),"start exercise while ordinary background work is active")
	var before := canonical(game.state)
	var runtime_assignments := canonical(game._assignments)
	var before_update := float(game._crew_update)
	var before_dispatch := float(game._maintenance_dispatch_elapsed)
	game._process(3.0)
	check(canonical(game.state) == before and canonical(game._assignments) == runtime_assignments,"active exercise freezes real delivery, crew and ordinary company state")
	check(float(game._crew_update) == before_update and float(game._maintenance_dispatch_elapsed) == before_dispatch,"active exercise does not accumulate deferred crew or maintenance time")
	check(bool(exercise_action(game,"incident_leave").get("ok",false)),"leave isolated exercise with background work intact")
	var remaining := float(game._assignments.get("aya",{}).get("remaining",0))
	var delivery_elapsed := float(game.state.delivery_orders[0].get("elapsed_seconds",0)) if not game.state.delivery_orders.is_empty() else -1.0
	game._process(1.0)
	check(float(game._assignments.get("aya",{}).get("remaining",remaining)) < remaining,"ordinary colleague work resumes after leaving")
	check(not game.state.delivery_orders.is_empty() and float(game.state.delivery_orders[0].get("elapsed_seconds",0)) > delivery_elapsed,"ordinary delivery clock resumes after leaving")
	game.queue_free()

func run() -> void:
	test_lifecycle_and_rollback()
	test_delivered_case_safety()
	test_background_clock_isolation()
	print("INCIDENT_INTEGRATION_PASS assertions="+str(assertions) if failures.is_empty() else "INCIDENT_INTEGRATION_FAIL count="+str(failures.size())+" assertions="+str(assertions))
	quit(0 if failures.is_empty() else 1)
