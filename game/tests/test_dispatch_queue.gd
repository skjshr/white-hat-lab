extends SceneTree

var game
var failures: Array[String] = []

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("dispatch queue timeout"); quit(2))
	call_deferred("run")

func _assert(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func _ok(value: Variant) -> bool:
	if value is bool: return value
	if value is Dictionary: return bool(value.get("ok", false))
	return false

func _call(name: String, args: Array = []) -> Variant:
	if not game.has_method(name):
		_assert(false, "missing dispatch API " + name)
		return null
	return game.callv(name, args)

func _queue(member: String) -> Array:
	var queues: Variant = game.state.get("dispatch_queues", {})
	if queues is Dictionary:
		var value: Variant = queues.get(member, [])
		return value if value is Array else []
	return []

func _queue_item(member: String, job_id: String = "") -> Dictionary:
	for raw in _queue(member):
		if raw is Dictionary and (job_id.is_empty() or str(raw.get("id", "")) == job_id):
			return raw
	return {}

func _first_offers() -> Array:
	var result: Array = []
	for offer in game.state.get("offers", []):
		if offer is Dictionary and str(offer.get("case_id", "")) in ["service-0-case-0", "service-2-case-0"] and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", true)):
			result.append(offer)
	return result

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.save_path = "user://qa-dispatch-queue-%d.json" % OS.get_process_id()
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	game._reset_state()
	_assert(game.choose_strategy("advisory"), "strategy")
	_assert(game.start_free_career(), "career")
	game.state.credit = 1000000
	game.state.peak_profit = 1000000
	game.state.skills = {"advisory":10,"operations":10,"response":10}
	# Dispatch applies to ordinary client VMs. Catalog order may place a manual-only
	# advanced investigation first, so request two stable eligible ordinary leads.
	game.state.market_leads = ["service-0-case-0", "service-2-case-0"]
	game.state.market_day = int(game.state.day)
	game._make_offers()
	var offers := _first_offers()
	_assert(offers.size() >= 2, "two queue contracts available")
	if offers.size() < 2:
		_finish()
		return
	var first_id := str(offers[0].get("id", ""))
	var second_id := str(offers[1].get("id", ""))
	_assert(game.choose_contract(first_id), "first contract accepted")
	_assert(game.choose_contract(second_id), "second contract accepted")
	_assert(not _ok(_call("dispatch_enqueue", ["aya", "missing-contract", 0])), "stale contract selection rejected")
	var first_context: Dictionary = game.state.contract_contexts.get(first_id, {})
	var first_targets: Array = first_context.get("targets", []) if first_context.get("targets", []) is Array else []
	_assert(not first_targets.is_empty(), "first target exists")
	if first_targets.is_empty():
		_finish()
		return
	var active_before := str(game.state.current_contract_id)
	var vm_before: Dictionary = game.state.vm_states.duplicate(true)
	_assert(_ok(_call("dispatch_enqueue", ["aya", first_id, 0])), "enqueue Aya")
	_assert(not _ok(_call("dispatch_enqueue", ["aya", first_id, 0])), "duplicate same-role job rejected")
	_assert(_ok(_call("dispatch_enqueue", ["aya", second_id, 0])), "enqueue second Aya job")
	var queue_before: Array = _queue("aya")
	_assert(queue_before.size() == 2, "queue stores two Aya jobs")
	if queue_before.size() != 2: _finish(); return
	var first_job_id := str(queue_before[0].get("id", ""))
	var second_job_id := str(queue_before[1].get("id", ""))
	_assert(_ok(_call("dispatch_move", ["aya", second_job_id, -1])), "urgent job moves to front")
	var remaining_before := float(_queue_item("aya", second_job_id).get("remaining", 0.0))
	_assert(_ok(_call("dispatch_start", ["aya", second_job_id])), "start urgent queued work")
	game._process(1.0)
	_assert(_ok(_call("dispatch_pause", ["aya"])), "pause active work")
	var paused_queue: Dictionary = _queue_item("aya", second_job_id)
	_assert(is_equal_approx(float(paused_queue.get("remaining", 0.0)), remaining_before - 1.0), "pause records elapsed work")
	_assert(game.state.vm_states == vm_before, "pause does not mutate target VM")
	_assert(str(game.state.current_contract_id) == active_before, "pause keeps active contract")
	_assert(_ok(_call("dispatch_start", ["aya", second_job_id])), "resume queued work")
	game._process(1.0)
	var active_after_start: Dictionary = game._assignments.get("aya", {})
	_assert(str(active_after_start.get("contract_id", "")) == second_id, "active assignment targets urgent contract")
	var partial_remaining := float(active_after_start.get("remaining", 0.0))
	var partial_assignments: Dictionary = game._assignments.duplicate(true)
	_assert(game.save_game(), "partial queue saves")
	_assert(game.load_game(), "partial queue reloads")
	_assert(is_equal_approx(float(game._assignments.get("aya", {}).get("remaining", 0.0)), partial_remaining), "partial remaining survives reload")
	var reloaded_assignment: Dictionary = game._assignments.get("aya", {})
	_assert(str(reloaded_assignment.get("contract_id", "")) == str(partial_assignments.get("aya", {}).get("contract_id", "")) and str(reloaded_assignment.get("vm_key", "")) == str(partial_assignments.get("aya", {}).get("vm_key", "")) and is_equal_approx(float(reloaded_assignment.get("remaining", 0.0)), partial_remaining) and str(reloaded_assignment.get("status", "")) == "working", "active assignment survives reload")
	var valid_path := str(game.save_path)
	var before_failed: Dictionary = game.state.duplicate(true)
	game.save_path = "user://missing-dispatch-queue-save/queue.json"
	var failed: Variant = _call("dispatch_remove", ["aya", first_job_id])
	game.save_path = valid_path
	_assert(not _ok(failed), "failed queue save rejected")
	_assert(game.state == before_failed, "failed queue save rolls state back")
	_assert(game.save_game() and game.load_game(), "final queue save reload")
	_staff_partial_probe(first_id)
	_maintenance_queue_probe()
	if failures.is_empty(): print("DISPATCH_QUEUE_TEST_PASS")
	else: print("DISPATCH_QUEUE_TEST_FAIL count=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _finish() -> void:
	print("DISPATCH_QUEUE_TEST_FAIL count=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _staff_partial_probe(contract_id: String) -> void:
	# Drain the two original jobs, then exercise a hired same-role worker on the
	# real target.  This keeps the queue duplicate and payroll checks separate
	# from the original Aya/Ren compatibility path.
	game._process(30.0)
	game._process(30.0)
	if "teamdesk" not in game.state.equipment:
		game.state.equipment.append("teamdesk")
	_assert(game.hire_staff("mio", "day"), "hire same-role worker")
	_assert(_ok(_call("dispatch_enqueue", ["aya", contract_id, 0])), "queue original same-role target")
	_assert(not _ok(_call("dispatch_enqueue", ["mio", contract_id, 0])), "same-role target duplicate rejected")
	var aya_job_id := str(_queue_item("aya").get("id", ""))
	_assert(_ok(_call("dispatch_remove", ["aya", aya_job_id])), "remove unstarted duplicate fixture")
	_assert(_ok(_call("dispatch_enqueue", ["mio", contract_id, 0])), "queue hired worker")
	var mio_job_id := str(_queue_item("mio").get("id", ""))
	_assert(_ok(_call("dispatch_start", ["mio", mio_job_id])), "start hired worker")
	game._process(1.0)
	var pause_state: Dictionary = game.state.duplicate(true)
	var pause_assignments: Dictionary = game._assignments.duplicate(true)
	var valid_path := str(game.save_path)
	game.save_path = "user://missing-dispatch-pause/queue.json"
	var failed_pause: Variant = _call("dispatch_pause", ["mio"])
	game.save_path = valid_path
	_assert(not _ok(failed_pause), "failed pause save rejected")
	_assert(game.state == pause_state and game._assignments == pause_assignments, "failed pause save rolls active job and staff state back")
	_assert(_ok(_call("dispatch_pause", ["mio"])), "pause hired worker")
	var used_before := float(game.state.staff.get("mio", {}).get("minutes_used", 0.0))
	_assert(is_equal_approx(used_before, 1.0), "hired worker partial minute accounted exactly once")
	_assert(not game.release_staff("mio"), "release blocked while queued")
	_assert(_ok(_call("dispatch_start", ["mio", mio_job_id])), "resume hired worker")
	game._process(1.0)
	_assert(_ok(_call("dispatch_pause", ["mio"])), "pause resumed hired worker")
	var used_after := float(game.state.staff.get("mio", {}).get("minutes_used", 0.0))
	_assert(is_equal_approx(used_after, 2.0), "resume accounts only remaining hired minute exactly once")
	var carried_remaining := float(_queue_item("mio", mio_job_id).get("remaining", 0.0))
	var old_staff_day := int(game.state.day)
	_assert(game.end_day(), "paused hired work carries to next day")
	_assert(int(game.state.staff.get("mio", {}).get("minutes_day", -1)) == int(game.state.day) and is_equal_approx(float(game.state.staff.get("mio", {}).get("minutes_used", 0.0)), 0.0), "new day resets hired worker minutes")
	_assert(is_equal_approx(float(_queue_item("mio", mio_job_id).get("remaining", 0.0)), carried_remaining), "hired work remaining carries across day")
	_assert(int(game.state.day) == old_staff_day + 1 and _ok(_call("dispatch_start", ["mio", mio_job_id])), "resume carried hired work")
	game._process(10.0)
	_assert(is_equal_approx(float(game.state.staff.get("mio", {}).get("minutes_used", 0.0)), carried_remaining), "next-day hired work accounts remaining minutes once")

func _maintenance_queue_probe() -> void:
	var fixture=preload("res://tests/care_fixture.gd")
	var rebuilt: Dictionary=fixture.build(game)
	_assert(bool(rebuilt.get("ok",false)),"build reconstructed care fixture: "+str(rebuilt.get("error","")))
	if not bool(rebuilt.get("ok",false)):return
	_assert(fixture.load_into(game,rebuilt.state),"load reconstructed legacy-scope fixture")
	var agreements: Dictionary = game.state.get("care_agreements", {})
	_assert(not agreements.is_empty(), "care agreement available for maintenance queue")
	if agreements.is_empty(): return
	var client := str(agreements.keys()[0])
	_assert(game.end_day(), "maintenance day rolls over")
	var job: Dictionary = game._maintenance_job_for(client)
	_assert(str(job.get("status", "")) == "pending", "maintenance job is pending after rollover")
	_assert(_ok(_call("dispatch_enqueue_maintenance", ["aya", client])), "enqueue maintenance")
	var job_id := str(_queue_item("aya").get("id", ""))
	_assert(_ok(_call("dispatch_start", ["aya", job_id])), "start maintenance")
	game._process(1.0)
	_assert(_ok(_call("dispatch_pause", ["aya"])), "pause maintenance")
	var paused: Dictionary = _queue_item("aya", job_id)
	var remaining := float(paused.get("remaining", 0.0))
	var queue_before_delivery: Dictionary = game.state.dispatch_queues.duplicate(true)
	var stored_before_delivery: Dictionary = game._maintenance_job_for(client).duplicate(true)
	game.MAINTENANCE_SCOPE.retain_delivery(game, client, game._maintenance_targets_for(client).duplicate(true))
	var retained_job: Dictionary = game._maintenance_job_for(client)
	_assert(str(retained_job.get("id", "")) == str(stored_before_delivery.get("id", "")) and str(retained_job.get("status", "")) == "paused" and is_equal_approx(float(retained_job.get("remaining", 0.0)), float(stored_before_delivery.get("remaining", 0.0))), "delivery preserves paused maintenance identity and effort")
	_assert(game.state.dispatch_queues == queue_before_delivery, "delivery does not rewrite paused maintenance queue")
	var old_day := int(game.state.day)
	var old_targets := JSON.stringify(game._maintenance_targets_for(client))
	game.state.care_agreements[client].next_incident_day = old_day + 1
	_assert(remaining > 0.0 and str(game._maintenance_job_for(client).get("status", "")) == "paused", "maintenance pause preserves remaining work")
	_assert(game.save_game() and game.load_game(), "maintenance queue reloads")
	_assert(is_equal_approx(float(_queue_item("aya", job_id).get("remaining", 0.0)), remaining), "maintenance remaining survives reload")
	_assert(game.end_day(), "paused maintenance rolls to next day")
	var carried: Dictionary = _queue_item("aya", job_id)
	_assert(str(carried.get("id", "")) == job_id and is_equal_approx(float(carried.get("remaining", 0.0)), remaining), "paused maintenance carries same job and remaining")
	_assert(JSON.stringify(game._maintenance_targets_for(client)) != old_targets, "maintenance drift changes live targets")
	var previous_ledger: Dictionary = game.state.get("retainer_daily", {}).get(str(old_day), {})
	_assert(int(previous_ledger.get("maintenance_missed", 0)) == 1 and previous_ledger.has("retainer_gross") and int(previous_ledger.get("retainer_gross", 0)) == 0, "missed day has no maintenance fee")
	_assert(_ok(_call("dispatch_start", ["aya", job_id])), "resume carried maintenance")
	_assert(game._assignments.get("aya", {}).get("targets", []) == game._maintenance_targets_for(client), "resume binds live maintenance targets")
	var day_start_clock: int = game.clock_minutes()
	game._process(20.0)
	var finished: Dictionary = game._maintenance_job_for(client)
	_assert(str(finished.get("status", "")) == "failed", "stale maintenance work does not report healthy after drift")
	_assert(game.clock_minutes() == day_start_clock + int(ceil(remaining)), "maintenance clock advances by carried remaining work")
