extends SceneTree

## Integration QA for concurrent career contracts.  This deliberately uses the
## desktop command/editor/browser paths and real VM probes; it never writes
## passed checks or completion flags directly.

const UI = preload("res://scripts/interface.gd")
var ui
var game
var pc
var failures: Array[String] = []

func _init() -> void:
	create_timer(45.0).timeout.connect(func():
		push_error("contract queue QA timed out")
		quit(2))
	call_deferred("run")

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _wait_frame() -> void:
	await process_frame

func run() -> void:
	ui = UI.new()
	root.add_child(ui)
	await _wait_frame()
	game = ui._game()
	var suffix := str(OS.get_process_id())
	game.save_path = "user://contract-queue-"+suffix+".json"
	game.backup_path = game.save_path+".bak"
	game.previous_path = game.save_path+".previous"
	game.settings_path = "user://contract-queue-"+suffix+"-settings.json"
	ui._new_game()
	_assert(game.choose_strategy("advisory"), "advisory strategy selected")
	_assert(game.start_free_career(), "free career started")
	var offer_a := _ordinary_offer("service-0-case-0")
	var offer_b := _ordinary_offer("service-2-case-0")
	var unlocked: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked",false)) and bool(item.get("market_available",false)))
	_assert(unlocked.size() >= 2, "at least two real offers are available")
	_assert(not offer_a.is_empty(), "ordinary contract A is available")
	if unlocked.size() < 2 or offer_a.is_empty():
		_finish()
		return
	_assert(not offer_b.is_empty() and str(offer_b.get("case_id","")) != str(offer_a.get("case_id","")), "two distinct contract cases selected")
	if offer_b.is_empty():
		_finish()
		return

	_assert(game.choose_contract(str(offer_a.id)), "contract A accepted through offer API")
	ui.open_panel("terminal")
	pc = ui.desktop
	pc._show_app("terminal")
	pc._run_command("ssh client")
	await _wait_frame()
	var a_key := str(offer_a.id)
	var a_vm_key: String = str(game._vm_key())
	# Queue the colleague before the player finishes the target.  The public
	# operations API correctly rejects assigning work to an already verified
	# target; the real concurrent workflow is operator and teammate working on
	# the same open target before delivery.
	game.assign_colleague("aya")
	_assert(_solve_current_through_desktop(pc), "A real save, restart, probes, and verify pass")
	var a_fs_before: Dictionary = game._vm().state.fs.duplicate(true)
	var a_checks: Array = game.state.checks.duplicate(true)
	_assert(not game.can_deliver(), "A delivery remains blocked while the teammate is working")
	_set_desktop_identity_and_draft(pc, "staff-session", "https://files.client.test/staff/report.txt", "A unsaved draft must stay local")
	pc._run_command("pwd")
	var a_history: Array = pc.history.duplicate(true)
	_assert(not a_history.is_empty(), "A terminal history recorded through desktop")
	var a_work_before_switch: Dictionary = game.state.work.duplicate(true)
	
	_assert(pc._save_session(), "A desktop session saved before accepting B")
	_assert(not game.can_deliver(), "active colleague work prevents premature delivery")
	var a_agreed: Dictionary = game.state.contract.duplicate(true)
	var common_clock_before_accept := int(game.state.clock_minutes)
	_assert(game.set_offer_plan("priority"), "B quote plan selected while A is active")
	var b_quote: Dictionary = game.contract_quote(offer_b)
	var b_agreed_fee := int(round(float(b_quote.reference_fee) * 0.88))
	_assert(game.set_offer_quote(str(offer_b.id), b_agreed_fee), "B custom quote stored while A is active")
	_assert(game.state.contract_plan == "standard" and game.state.contract == a_agreed, "B quotation preserves A plan and agreed contract")
	_assert(game.choose_contract(str(offer_b.id)), "contract B accepted while A remains open")
	_assert(int(game.state.clock_minutes) == common_clock_before_accept, "additional acceptance cannot reset the common clock")
	_assert(int(game.state.contract.agreed_fee) == b_agreed_fee and game.state.contract_plan == "priority", "B fixes the selected plan and custom fee")
	_assert(str(game.state.assignments.get("aya",{}).get("status","")) == "working", "accepting B preserves A colleague assignment")
	pc._reload_contract_session()
	await _wait_frame()
	var b_vm_key: String = str(game._vm_key())
	pc._show_app("terminal")
	pc._run_command("ssh client")
	_assert(_save_current_config_through_desktop(pc), "B config saved and service restarted through desktop")
	var b_fs_before: Dictionary = game._vm().state.fs.duplicate(true)
	_set_desktop_identity_and_draft(pc, "partner-mfa-session", "https://portal.client.test/partner", "B unsaved draft must stay local")
	pc._run_command("history-b-check")
	var b_history: Array = pc.history.duplicate(true)
	_assert(a_history != b_history, "B has an independent desktop history")
	_assert(not game.can_deliver(), "B is not made deliverable by A checks")
	_assert(game._vm().state.fs == b_fs_before, "B VM filesystem is unchanged by its unsaved draft")

	var b_clock_before_switch: int = int(game.state.clock_minutes)
	_assert(pc._switch_contract(a_key), "desktop switches B to A")
	await _wait_frame()
	_assert(game.state.work == a_work_before_switch, "contract switch restores A work without adding time")
	_assert(int(game.state.clock_minutes) == b_clock_before_switch, "contract switch leaves the common clock unchanged")
	_assert(str(game.state.current_contract_id) == a_key, "A is active after desktop switch")
	_assert(str(pc.browser_identity) == "staff-session" and str(pc.browser_url) == "https://files.client.test/staff/report.txt", "A browser identity and URL restored")
	_assert(str(pc.editor.text) == "A unsaved draft must stay local", "A editor draft restored")
	_assert(pc.history == a_history, "A terminal history restored")
	_assert(game._vm().state.fs == a_fs_before, "A VM filesystem is unchanged by its unsaved draft and switches")
	_assert(game.state.checks == a_checks, "A verified checks remain isolated while its colleague is working")

	# A teammate runs in the background while B is the active contract. The
	# contract_id captured by assign_colleague is the isolation boundary.
	game.assign_colleague("aya")
	var aya_minutes := int(game.state.assignments.get("aya",{}).get("work_minutes",0))
	_assert(str(game.state.assignments.get("aya",{}).get("status","")) == "working" and str(game.state.assignments.get("aya",{}).get("contract_id","")) == a_key, "Aya assignment is bound to A")
	var b_work_before: Dictionary = game.state.contract_contexts[str(offer_b.id)].get("work",{}).duplicate(true)
	var b_fs_before_aya: Dictionary = game.state.vm_states.get(b_vm_key,{}).get("fs",{}).duplicate(true)
	var b_clock_before_aya: int = int(game.state.clock_minutes)
	_assert(pc._switch_contract(str(offer_b.id)), "desktop switches A back to B")
	await _wait_frame()
	var observed_active_ids: Array[String] = []
	var active_b := str(offer_b.id)
	var active_watch := func():
		observed_active_ids.append(str(game.state.current_contract_id))
	game.changed.connect(active_watch)
	game._process(30.0)
	await _wait_frame()
	game.changed.disconnect(active_watch)
	_assert(game.state.contract_contexts[str(offer_b.id)].get("work",{}) == b_work_before, "Aya does not change B work")
	_assert(game.state.vm_states.get(b_vm_key,{}).get("fs",{}) == b_fs_before_aya, "Aya does not change B VM")
	_assert(b_clock_before_aya-common_clock_before_accept>=aya_minutes,"player's B work outlasted concurrent Aya work")
	_assert(int(game.state.clock_minutes) == b_clock_before_aya,"concurrent Aya completion does not charge elapsed player time again")
	_assert(not observed_active_ids.is_empty() and observed_active_ids.all(func(id): return id == active_b), "background Aya completion never exposes A as the active UI contract")
	_assert(str(game.state.assignments.get("aya",{}).get("status","")) == "done", "Aya result is retained after background completion")

	_assert(pc._switch_contract(a_key), "desktop returns to A after Aya")
	await _wait_frame()
	_assert(str(game.state.assignments.get("aya",{}).get("status","")) == "done", "A teammate result remains visible")
	_assert(a_key in game.state.contract_contexts and str(game.state.contract_contexts[a_key].get("id",a_key)) == a_key, "A context remains persisted")

	# A failed game save must leave the active contract, VM, and desktop session
	# untouched. Restore the path before the final persistence check.
	_assert(pc._save_session(), "A desktop session persisted before save failure snapshot")
	var before_failure_state: Dictionary = game.state.duplicate(true)
	var before_failure_key := str(game._vm_key())
	var before_failure_session: String = pc.session_key
	var valid_save_path: String = game.save_path
	game.save_path = "user://missing-contract-queue-save/queue.json"
	_assert(not pc._switch_contract(str(offer_b.id)), "failed contract switch is rejected")
	game.save_path = valid_save_path
	_assert(game.state == before_failure_state and str(game._vm_key()) == before_failure_key and pc.session_key == before_failure_session, "failed switch rolls back state, VM context, and desktop session")

	_assert(game.save_game() and game.load_game(), "two-contract state reloads")
	_assert(game.state.contract_contexts.has(a_key) and game.state.contract_contexts.has(str(offer_b.id)), "both contract contexts survive reload")
	_assert(not bool(game.state.contract_contexts[a_key].get("completed",false)) and not bool(game.state.contract_contexts[str(offer_b.id)].get("completed",false)), "unfinished contracts remain open after reload")
	pc._reload_contract_session()
	var day_before := int(game.state.day)
	var elapsed_before := float(game.work_status().elapsed_minutes)
	var deadline_before: Dictionary = game.contract_queue()[0].duplicate(true)
	ui.open_panel("door")
	# Career mode routes the door to OperationsPanel.closeout(), where the
	# actual end-day action is nested beside the per-contract controls.
	var overnight_node: Node = ui.modal_footer.find_child("DaySettle", true, false)
	var overnight_button: Button = overnight_node as Button
	_assert(overnight_button != null and not overnight_button.disabled, "unfinished career contract enables the actual overnight button")
	if overnight_button != null: overnight_button.pressed.emit()
	ui.open_panel("terminal"); pc = ui.desktop
	_assert(int(game.state.day) == day_before + 1 and game.state.contract_contexts.size() == 2, "overnight keeps both unfinished contexts")
	_assert(float(game.work_status().elapsed_minutes) > elapsed_before and int(game.work_status().late_minutes) > 0, "overnight elapsed and lateness include the day boundary")
	_assert(str(game.contract_queue()[0].deadline_text) == str(deadline_before.deadline_text), "overnight preserves the original deadline")
	_assert(str(pc.editor.text) == "A unsaved draft must stay local", "overnight preserves A local editor draft")
	_assert(_solve_current_through_desktop(pc) and game.deliver(), "A delivers after real overnight verification")
	var first_receipt: Dictionary = game.completion_receipt().duplicate(true)
	var cash_after_a := int(game.state.cash)
	_assert(not game.deliver() and int(game.state.cash) == cash_after_a, "A cannot pay twice")
	_assert(not game.choose_contract(a_key), "completed contract ID cannot be accepted again")
	_assert(pc._switch_contract(str(offer_b.id)), "B resumes after A delivery")
	_assert(int(game.state.contract.agreed_fee) == b_agreed_fee and game.state.contract_plan == "priority", "B agreed quote survives overnight and reload")
	_assert(_solve_current_through_desktop(pc) and game.deliver(), "B delivers after real verification")
	_assert(int(game.completion_receipt().agreed_fee) == b_agreed_fee and int(game.state.contracts_completed) == 2, "both distinct deliveries count once at their agreed fees")
	_assert(game.state.contract_contexts[a_key].last_receipt == first_receipt, "B delivery does not overwrite A receipt")
	var delivered_history: Array = game.state.history.duplicate(true)
	_assert(game.end_day() and game.state.contract_contexts.is_empty(), "next day removes completed contexts from the queue")
	_assert(game.state.history.slice(0, delivered_history.size()) == delivered_history, "daily settlement preserves earlier delivery and retainer records")
	var settled_receipt: Dictionary = game.state.last_receipt.duplicate(true)
	_assert(game.end_day(), "empty career day can advance")
	_assert(game.state.last_receipt == settled_receipt, "later empty day cannot overwrite an earlier receipt")
	pc._show_app("mail"); pc.widgets.mail.folder = "history"
	load("res://scripts/os_business_apps.gd").refresh_mail(pc)
	_assert(pc.widgets.mail.list.get_children().filter(func(node): return node is Button).size() == 2, "completed mail list shows only the two real deliveries")
	await _verify_multitarget_background()

	_finish()

func _ordinary_offer(case_id: String) -> Dictionary:
	# This fixture tests VM isolation. Advanced engagements use another work model.
	# Publish fixed ordinary leads without bypassing unlock or acceptance checks.
	if case_id not in game.state.market_leads: game.state.market_leads.append(case_id)
	game.state.market_day = int(game.state.day)
	game._make_offers()
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) != case_id: continue
		_assert(bool(offer.get("unlocked", false)), "ordinary fixture unlocked: " + case_id)
		_assert(bool(offer.get("market_available", false)), "ordinary fixture on market: " + case_id)
		if bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)): return offer
	return {}

func _verify_multitarget_background() -> void:
	# Unlock an existing multi-site catalog fixture; all work still uses live VMs.
	game.state.credit = 1000; game.state.peak_profit = 100000
	game.state.skills = {"advisory":3,"operations":3,"response":3}
	game._make_offers(); game.set_offer_plan("standard")
	var multi_offers: Array = game.state.offers.filter(func(item): return bool(item.unlocked) and int(item.targets) > 1)
	_assert(not multi_offers.is_empty(), "multi-site catalog fixture available")
	if multi_offers.is_empty(): return
	_assert(game.choose_contract(str(multi_offers[0].id)), "multi-site contract accepted")
	pc._reload_contract_session(); pc._run_command("ssh client")
	var owner_key: String = game._vm_key()
	game.assign_colleague("aya")
	_assert(pc._select_target(1), "desktop switches site while Aya keeps the original site")
	pc._run_command("ssh client")
	var active_key: String = game._vm_key()
	var active_fs: Dictionary = game._vm().state.fs.duplicate(true)
	game._process(30.0)
	_assert(int(game.state.target_index) == 1 and game._vm_key() == active_key and game._vm().state.fs == active_fs, "background work restores the active site and its VM")
	_assert(str(game.state.assignments.aya.vm_key) == owner_key and str(game.state.assignments.aya.status) == "done", "Aya result remains bound to the original site")
	game.assign_colleague("aya")
	_assert(pc._select_target(0), "second Aya job continues across a site switch")
	_assert(pc._save_session(), "multi-site save failure baseline persisted")
	var before_work: Dictionary = game.state.work.duplicate(true)
	var before_clock := int(game.state.clock_minutes)
	var before_vm: Dictionary = game._vm().export_state()
	var before_remaining := float(game.state.assignments.aya.remaining)
	var good_path: String = game.save_path
	game.save_path = "user://missing-contract-queue-save/queue.json"
	game._process(30.0)
	game.save_path = good_path
	_assert(game.state.work == before_work and int(game.state.clock_minutes) == before_clock and game._vm().export_state() == before_vm and int(game.state.target_index) == 0, "failed background save rolls back cost, clock, and active VM")
	_assert(str(game.state.assignments.aya.status) == "working" and is_equal_approx(float(game.state.assignments.aya.remaining),before_remaining), "failed background save preserves remaining time")
	game._process(30.0)
	_assert(str(game.state.assignments.aya.status) == "done" and int(game.state.target_index) == 0, "background completion retries safely after storage recovers")
	await _wait_frame()

func _set_desktop_identity_and_draft(desktop, identity: String, url: String, draft: String) -> void:
	desktop._show_app("editor")
	desktop._open_editor(str(game.vm_info().config_path))
	desktop.editor.text = draft
	desktop._state_changed()
	desktop._show_app("browser")
	desktop.browser_identity = identity
	desktop.browser_url = url
	if desktop.widgets.browser.has("url"): desktop.widgets.browser.url.text = url
	desktop._save_session(false)

func _solve_current_through_desktop(desktop) -> bool:
	desktop._show_app("terminal")
	var scenario: Dictionary = game._scenario()
	var config_path := str(game.vm_info().config_path)
	desktop._open_editor(config_path)
	desktop.editor.text = game._vm().configuration_text(scenario.get("desired",{}))
	desktop._save_editor()
	desktop._show_app("terminal")
	desktop._run_command("systemctl restart "+str(game.vm_info().service))
	preload("res://tests/identity_test_support.gd").authenticate_current(game)
	for round_index in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded",false)) and bool(probe.get("fresh",false)) and bool(probe.get("passed",false))): desktop._run_command(str(probe.get("command","")))
		var ready := true
		for probe_after in game.diagnostic_probes():
			if not (bool(probe_after.get("recorded",false)) and bool(probe_after.get("fresh",false)) and bool(probe_after.get("passed",false))): ready = false
		if ready: break
	var result: Array = game.verify()
	return not result.is_empty() and result.all(func(item): return bool(item.get("passed",false)))

func _save_current_config_through_desktop(desktop) -> bool:
	var scenario: Dictionary = game._scenario()
	desktop._show_app("editor")
	desktop._open_editor(str(game.vm_info().config_path))
	desktop.editor.text = game._vm().configuration_text(scenario.get("desired",{}))
	desktop._save_editor()
	desktop._show_app("terminal")
	desktop._run_command("systemctl restart "+str(game.vm_info().service))
	return bool(game._vm().state.get("active",false))

func _finish() -> void:
	for failure in failures: push_error(failure)
	print("CONTRACT_QUEUE failures=%d contexts=%d" % [failures.size(), game.state.get("contract_contexts",{}).size()] if game != null else "CONTRACT_QUEUE failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
