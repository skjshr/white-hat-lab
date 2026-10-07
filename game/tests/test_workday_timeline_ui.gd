extends SceneTree
## Self-contained UI regression for the workday timeline. The ordinary job is
## completed through real Game APIs; only the prior-source metadata for the
## accepted priority engagement is a synthetic, isolated QA fixture.

const CARE_FIXTURE = preload("res://tests/care_fixture.gd")
const PRIORITY = preload("res://scripts/saas_priority.gd")
const WORKDAY = preload("res://scripts/company_workday.gd")

var game
var ui
var failures: Array[String] = []
var files: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(100.0).timeout.connect(func(): push_error("workday timeline UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count := 5) -> void:
	for _i in count: await process_frame

func find_control(id: String) -> Node:
	return ui.root.find_child(id, true, false) if is_instance_valid(ui) else null

func activate_button(button: Button) -> void:
	check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "visible enabled button " + (str(button.name) if is_instance_valid(button) else "missing"))
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled: return
	for scroll in _scroll_ancestors(button):
		scroll.ensure_control_visible(button)
	await frames(2)
	check(root.get_visible_rect().has_point(button.get_global_rect().get_center()), "button remains reachable " + str(button.name))
	# Emit the real Button signal after checking its rendered/scroll-reachable geometry.
	# This keeps the integration test reliable under headless rendering too.
	button.pressed.emit()
	await frames(8)

func _scroll_ancestors(node: Node) -> Array[ScrollContainer]:
	var result: Array[ScrollContainer] = []
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: result.append(ancestor)
		ancestor = ancestor.get_parent()
	return result

func _offer(case_id: String) -> Dictionary:
	game.state.market_leads = [case_id]
	game.state.market_day = int(game.state.day)
	game._make_offers()
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == case_id and bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)): return offer
	return {}

func _qa_priority_context(id: String) -> Dictionary:
	var approved := [
		{"id":"QA-APPROVAL","action":"consent_review","status":200,"data":{}},
		{"id":"QA-RUN","action":"run_business","status":200,"data":{"receipt_id":"QA-RECEIPT"}},
		{"id":"QA-REPORT","action":"submit_report","status":200,"data":{}}
	]
	var payload := {"source_contract_id":"qa-prior-paid-source","source_day":1,"round":3,"client":PRIORITY.CLIENT,"approved_originals":approved,"prior_result":{"rating":"A"}}
	var advanced: Dictionary = PRIORITY.create_followup(payload)
	if advanced.is_empty(): return {}
	var day := int(game.state.day)
	var minute := int(game.clock_minutes())
	var target := {"chapter":0,"case_id":PRIORITY.CASE_ID,"name":"北斗物流・業務連携","config":{},"checks":[],"revision":0,"validated_revision":-1,"advanced":advanced.duplicate(true)}
	var contract := {"id":id,"case_id":PRIORITY.CASE_ID,"client":PRIORITY.CLIENT,"title":"緊急・業務連携","target_specs":[{"name":"業務連携"}],"agreed_fee":6000,"agreed_budget":180.0}
	var work := {"started_day":day,"started_at":minute,"incident_cost":0,"saas_costs":{"usage_cost":0,"impact_cost":0,"assistant_runs":0},"priority_company_clock_anchor_minute":day*1440+minute,"priority_company_clock_anchor_elapsed":int(advanced.elapsed_minutes)}
	return {"id":id,"chapter":0,"contract":contract,"contract_plan":"standard","accepted":true,"inspected":false,"targets":[target],"target_index":0,"config":{},"checks":[],"revision":0,"validated_revision":-1,"work":work,"advanced":advanced,"completed":false}

func _find_row(rows: Array, key: String) -> Dictionary:
	for item in rows:
		if item is Dictionary and str(item.get("key", "")) == key: return item
	return {}

func _finish() -> void:
	if is_instance_valid(ui): ui.queue_free()
	if is_instance_valid(game): game.set_process(false)
	for path in files:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty(): print("WORKDAY_TIMELINE_UI_PASS narrow=", narrow)
	else: print("WORKDAY_TIMELINE_UI_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game = root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload available")
		_finish()
		return
	game.set_process(false)
	var stem := "user://qa-workday-timeline-%d" % OS.get_process_id()
	files.assign([stem + ".json", stem + ".bak", stem + ".previous", stem + ".settings", stem + ".tmp"])
	game.save_path = files[0]
	game.backup_path = files[1]
	game.previous_path = files[2]
	game.settings_path = files[3]
	check(game.new_game() and game.choose_strategy("operations"), "isolated career starts")
	game.state.cash = 100000
	game.state.credit = 100
	game.state.equipment = ["teamdesk"]
	check(game.learn_skill("advisory") and game.start_free_career() and game.hire_staff("mio"), "company fixture meets career and staffing prerequisites")
	if narrow:
		game.set_settings({"resolution":"960x600","window_mode":"windowed","text_scale":1.3,"volume":0}, false)
		root.get_node("Graphics").apply_settings(game.settings)
		await frames(3)
		if DisplayServer.get_name() == "headless": check(is_equal_approx(float(game.settings.get("text_scale", 1.0)), 1.3), "headless narrow run retains 130 percent UI scale")
		else: check(is_equal_approx(root.get_visible_rect().size.x, 960.0), "narrow run uses 960 logical width")
	var offer := _offer("service-1-case-0")
	check(not offer.is_empty() and game.set_offer_plan("care") and game.choose_contract(str(offer.get("id", ""))), "ordinary care work accepted through the market")
	if offer.is_empty() or not bool(game.state.accepted): _finish(); return
	var normal_id := str(game.state.current_contract_id)
	var priority_id := "qa-priority-timeline"
	game._sync_contract_context()
	game.state.contract_contexts[priority_id] = _qa_priority_context(priority_id)
	check(not game.state.contract_contexts[priority_id].is_empty(), "self-contained advanced priority follow-up fixture created")
	# Warm the existing company-workday reader before taking the immutability baseline.
	var initial_snapshot: Dictionary = WORKDAY.snapshot(game)
	var priority_row: Dictionary = {}
	var normal_row: Dictionary = {}
	for row in initial_snapshot.get("jobs", []):
		if str(row.get("contract_id", "")) == priority_id: priority_row = row
		if str(row.get("contract_id", "")) == normal_id: normal_row = row
	check(not priority_row.is_empty() and bool(priority_row.get("business", {}).get("available", false)), "timeline input contains advanced priority business deadlines, not just a priority quote")
	check(not normal_row.is_empty() and str(normal_row.get("kind", "")) == "normal", "timeline input includes an ordinary customer contract")
	if priority_row.is_empty() or normal_row.is_empty(): _finish(); return
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(8)
	ui.controls.menu.hide()
	ui.guided_intro.skip()
	ui._set_text_scale(1.3 if narrow else 1.0)
	var stable_state := JSON.stringify(game.state)
	ui.open_panel("board")
	await frames(10)
	check(ui.current_kind == "board", "workday board opens")
	check(JSON.stringify(game.state) == stable_state and int(game.clock_minutes()) == int(initial_snapshot.clock_minute), "building the timeline is read-only for game state and clock")
	var timeline = find_control("WorkdayTimeline")
	check(is_instance_valid(timeline) and str(timeline.name) == "WorkdayTimeline", "workday timeline mounted in the existing board")
	if not is_instance_valid(timeline): _finish(); return
	var normal_key := str(normal_row.key)
	var priority_key := str(priority_row.key)
	var actual_timeline_model: Dictionary = timeline.model.duplicate(true)
	var late_received_model: Dictionary = actual_timeline_model.duplicate(true)
	var late_received_fixture := false
	for row in late_received_model.get("rows", []):
		if str(row.get("key", "")) != priority_key: continue
		for marker in row.get("markers", []):
			if str(marker.get("kind", "")) == "business" and str(marker.get("id", "")) == "claims":
				marker.received = true
				marker.late = true
				late_received_fixture = true
	timeline.configure(late_received_model, str(timeline.selected_key), float(ui.text_scale))
	await frames(2)
	var late_received_button: Button = timeline.business_buttons.get(priority_key + "|claims") as Button
	check(late_received_fixture and is_instance_valid(late_received_button) and late_received_button.text.contains("遅延受付"), "received and overdue business marker stays visibly labeled as delayed receipt")
	timeline.configure(actual_timeline_model, str(timeline.selected_key), float(ui.text_scale))
	var normal_button := timeline.row_buttons.get(normal_key) as Button
	check(is_instance_valid(normal_button), "normal work row is selectable on the timeline")
	await activate_button(normal_button)
	timeline = find_control("WorkdayTimeline")
	check(str(ui.operations_choices.get("workday_selected", "")) == normal_key and is_instance_valid(find_control("WorkdayFlowCanvas")), "selecting ordinary row returns to its existing work controls")
	var selected_button := find_control("WorkdaySelect_" + normal_key.validate_node_name()) as Button
	check(is_instance_valid(selected_button) and selected_button.has_focus(), "job selection rebuild retains keyboard focus on the selected job")
	var feedback := find_control("WorkdaySelectedFeedback") as Label
	check(is_instance_valid(feedback) and feedback.text.contains("本人が対応"), "ordinary selection updates the existing footer")
	var before_clock := int(game.clock_minutes())
	var priority_deadline_before := -1
	for marker in _find_row(timeline.model.get("rows", []), priority_key).get("markers", []):
		if str(marker.get("kind", "")) == "business" and str(marker.get("id", "")) == "claims": priority_deadline_before = int(marker.get("absolute", -1))
	check(priority_deadline_before >= 0, "priority business deadline has a known absolute anchor")
	var normal_deadline_before := int(_find_row(timeline.model.get("rows", []), normal_key).get("deadline_absolute", -1))
	check(game.advance_office_time(1.0), "one minute of company time advances through the normal Game API")
	await frames(10)
	timeline = find_control("WorkdayTimeline")
	check(is_instance_valid(timeline) and int(timeline.model.now_absolute) == int(game.state.day) * 1440 + before_clock + 1, "clock change moves the visible now marker")
	var refreshed_priority := _find_row(timeline.model.get("rows", []), priority_key)
	var refreshed_normal := _find_row(timeline.model.get("rows", []), normal_key)
	check(int(refreshed_normal.get("deadline_absolute", -2)) == normal_deadline_before, "clock refresh retains the ordinary contract delivery deadline")
	var deadline_stays_fixed := false
	for marker in refreshed_priority.get("markers", []):
		if str(marker.get("kind", "")) == "business" and str(marker.get("id", "")) == "claims":
			deadline_stays_fixed = int(marker.get("absolute", -2)) == priority_deadline_before
	check(deadline_stays_fixed, "clock refresh moves now while the priority receipt deadline stays anchored")
	check(CARE_FIXTURE._solve(game) and game.deliver(), "ordinary accepted work completes through existing verification and delivery APIs")
	await frames(12)
	timeline = find_control("WorkdayTimeline")
	var completed_row: Dictionary = {}
	for row in timeline.model.get("rows", []):
		if str(row.get("key", "")).begins_with("contract:" + normal_id + ":") and bool(row.get("completed", false)): completed_row = row
	check(not completed_row.is_empty() and bool(completed_row.get("draft", false)) and completed_row.get("markers", []).is_empty() and completed_row.get("segments", []).is_empty(), "completed ordinary job updates to a compact invoice outcome with no active work segment")
	var footer_after_delivery := find_control("WorkdaySelectedFeedback") as Label
	check(is_instance_valid(footer_after_delivery) and not is_instance_valid(find_control("WorkdayFlowCanvas")), "completion refresh removes active assignment controls and updates the footer")
	# Re-select the priority job, then follow one of its actual business deadline controls.
	var priority_button := timeline.row_buttons.get(priority_key) as Button
	await activate_button(priority_button)
	timeline = find_control("WorkdayTimeline")
	var priority_feedback := find_control("WorkdaySelectedFeedback") as Label
	check(str(ui.operations_choices.get("workday_selected", "")) == priority_key and is_instance_valid(priority_feedback) and priority_feedback.text.contains("本人が対応"), "priority row selection updates its own footer")
	var business_button: Button = timeline.business_buttons.get(priority_key + "|claims") as Button
	check(is_instance_valid(business_button), "priority SLA is a selectable queue route")
	if narrow and is_instance_valid(business_button):
		check(business_button.is_visible_in_tree() and business_button.get_global_rect().size.x > 0.0 and business_button.get_global_rect().size.y > 0.0 and is_instance_valid(ui.modal_footer) and ui.modal_footer.is_visible_in_tree(), "960x600 at 130 percent keeps SLA route and existing footer accessible")
	var before_route_clock := int(game.clock_minutes())
	var before_route_elapsed := int(game.state.contract_contexts[priority_id].advanced.elapsed_minutes)
	await activate_button(business_button)
	await frames(10)
	var desktop_ready := is_instance_valid(ui.desktop)
	var advanced_state: Dictionary = preload("res://scripts/investigation_ui.gd").state(ui.desktop, PRIORITY.CASE_ID) if desktop_ready else {}
	check(ui.current_kind == "terminal" and desktop_ready and ui.desktop.current_app == "advanced" and str(advanced_state.get("queue_id", "")) == "claims", "deadline selection opens the matching advanced customer queue")
	check(str(game.state.current_contract_id) == priority_id and int(game.clock_minutes()) == before_route_clock and int(game.state.advanced.elapsed_minutes) == before_route_elapsed, "queue route switches to its source contract without advancing time")
	_finish()
