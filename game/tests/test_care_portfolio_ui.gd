extends SceneTree
## Self-contained care-company UI integration. Fixture work is produced by
## the existing public Game APIs in care_fixture.gd and stored in QA only.

const PANEL = preload("res://scripts/care_portfolio_panel.gd")
const MODEL = preload("res://scripts/care_portfolio_view.gd")
const FIXTURE = preload("res://tests/care_fixture.gd")

var game
var ui
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(120.0).timeout.connect(func(): print("CARE_PORTFOLIO_UI_TIMEOUT"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 4) -> void:
	for _i in count: await process_frame

func control(id: String) -> Node:
	return ui.root.find_child(id, true, false) if is_instance_valid(ui) else null

func run() -> void:
	game = root.get_node_or_null("Game")
	check(game != null and str(game.save_path).begins_with("user://qa-"), "isolated QA profile required")
	if game == null or not str(game.save_path).begins_with("user://qa-"):
		await finish(); return
	game.set_process(false)
	var fixture: Dictionary = FIXTURE.build(game)
	check(bool(fixture.get("ok", false)), "existing care fixture builds verified delivered work through Game APIs: " + str(fixture.get("error", "")))
	if not bool(fixture.get("ok", false)):
		await finish(); return
	var clients: Array = game.state.care_agreements.keys()
	check(not clients.is_empty(), "fixture has a real active care customer")
	if clients.is_empty(): await finish(); return
	var client := str(clients[0])
	_test_owner_save_and_reload(client)
	check(bool(game.end_day()), "fixture advances through normal settlement to a fresh care workday")
	root.size = Vector2i(960, 600) if narrow else Vector2i(1440, 900)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames(5)
	ui.controls.menu.hide(); ui.guided_intro.skip(); ui._set_text_scale(1.3 if narrow else 1.0)
	ui.set_meta("company_view", "care"); ui.set_meta("company_client", client)
	var before_state := JSON.stringify(game.state)
	var before_assignments := JSON.stringify(game._assignments)
	var before_clock := int(game.clock_minutes())
	var before_vms := JSON.stringify(game.state.get("vm_states", {}))
	ui.open_panel("company"); await frames(8)
	check(ui.current_kind == "company" and control("CarePortfolio") != null and control("CareBalance") != null, "company care panel renders portfolio and daily balance")
	check(JSON.stringify(game.state) == before_state and JSON.stringify(game._assignments) == before_assignments and int(game.clock_minutes()) == before_clock and JSON.stringify(game.state.get("vm_states", {})) == before_vms, "portfolio rendering leaves game state, time, assignments, and VM snapshots unchanged")
	await _test_owner_focus(client)
	ui.set_meta("company_view", "care"); ui.set_meta("company_client", client); ui.open_panel("company"); await frames(6)
	_test_point_check_updates_income(client)
	await _test_small_layout(client)
	_test_care_offer_route()
	_test_workday_route(client)
	await finish()

func _test_owner_save_and_reload(client: String) -> void:
	var before: Dictionary = game.state.duplicate(true)
	var owner_before: String = str(game.maintenance_owner(client))
	var desired_owner := ""
	for candidate in game.maintenance_owner_candidates():
		var id := str(candidate.get("id", ""))
		if not id.is_empty() and id != owner_before: desired_owner = id; break
	check(not desired_owner.is_empty(), "fixture has a different valid recurring owner for rollback/retry")
	if desired_owner.is_empty(): return
	var good_path := str(game.save_path)
	game.save_path = "user://qa-care-owner-missing-%s/save.json" % OS.get_process_id()
	var failed: bool = bool(game.set_maintenance_owner(client, desired_owner))
	check(not failed and game.state == before and game.maintenance_owner(client) == owner_before, "failed recurring-owner save rolls back without changing the visible owner")
	game.save_path = good_path
	check(bool(game.set_maintenance_owner(client, desired_owner)) and game.maintenance_owner(client) == desired_owner, "owner save retry succeeds")
	check(bool(game.load_game()) and game.maintenance_owner(client) == desired_owner, "saved owner survives reload")

func _test_owner_focus(client: String) -> void:
	var picker_id := "CareOwner_" + client.sha256_text().left(10)
	var picker := control(picker_id) as OptionButton
	check(is_instance_valid(picker), "real recurring-owner OptionButton is rendered")
	if not is_instance_valid(picker): return
	var original := str(game.maintenance_owner(client))
	var first_index := -1
	for index in picker.item_count:
		var id := str(picker.get_item_metadata(index))
		if not id.is_empty() and id != original:
			first_index = index; break
	check(first_index >= 0, "real picker offers another valid recurring owner")
	if first_index < 0: return
	picker.grab_focus()
	check(picker.has_focus(), "focus can be placed on recurring-owner picker")
	picker.select(first_index); picker.item_selected.emit(first_index)
	await frames(8)
	var refreshed := control(picker_id) as OptionButton
	check(is_instance_valid(refreshed) and str(game.maintenance_owner(client)) == str(refreshed.get_item_metadata(refreshed.selected)), "owner change rebuilds the picker with the persisted value")
	check(is_instance_valid(refreshed) and refreshed.has_focus(), "focus remains on the latest owner picker after live refresh")
	if not is_instance_valid(refreshed): return
	var return_index := -1
	for index in refreshed.item_count:
		if str(refreshed.get_item_metadata(index)) == original:
			return_index = index; break
	if return_index < 0: return
	refreshed.grab_focus(); refreshed.select(return_index); refreshed.item_selected.emit(return_index)
	ui.open_panel("staffing")
	await frames(8)
	var focus: Control = ui.get_viewport().gui_get_focus_owner()
	check(ui.current_kind == "staffing", "immediate panel navigation completes after owner refresh")
	check(not is_instance_valid(focus) or not is_instance_valid(refreshed) or focus != refreshed, "deferred owner-focus restoration does not steal focus from the next panel")
	check(not is_instance_valid(focus) or ui.modal.is_ancestor_of(focus), "any retained focus belongs to the newly active staffing panel")

func _test_point_check_updates_income(client: String) -> void:
	game._prepare_maintenance_day()
	var job: Dictionary = game._maintenance_job_for(client)
	check(not job.is_empty() and str(job.get("status", "")) == "pending", "actual delivered target creates today's pending maintenance job")
	var before: Dictionary = MODEL.snapshot(game)
	var before_client: Dictionary = _client_row(before, client)
	check(int(before_client.get("earned_today", -1)) == 0 and int(before.get("earned", -1)) == 0, "pending maintenance is not shown as earned revenue")
	var completed: bool = bool(game.run_maintenance(client))
	check(completed, "real saved VM point check completes through Game API")
	var after: Dictionary = MODEL.snapshot(game)
	var after_client: Dictionary = _client_row(after, client)
	var fee := int(game.state.care_agreements[client].get("fee", 0))
	check(str(game._maintenance_job_for(client).get("status", "")) == "done" and str(after_client.get("result", "")).begins_with("PASS"), "successful real point check is attached to this customer")
	check(int(after_client.get("earned_today", -1)) == fee and int(after.get("earned", -1)) == fee, "successful point check updates customer and company earned income")

func _client_row(model: Dictionary, client: String) -> Dictionary:
	for row in model.get("clients", []):
		if str(row.get("client", "")) == client: return row
	return {}

func _test_care_offer_route() -> void:
	var eligible: Array = PANEL.eligible_offers(game)
	check(not eligible.is_empty(), "normal generated market supplies a care-eligible offer")
	if eligible.is_empty(): return
	for row in eligible:
		var raw := _offer(str(row.get("id", "")))
		check(not raw.is_empty() and bool(raw.get("market_available", false)) and bool(raw.get("unlocked", false)) and str(game.care_case_reason(raw)).is_empty(), "care shortlist includes only available, unlocked, eligible offers")
	var offer := _offer(str(eligible[0].id))
	var unavailable := offer.duplicate(true); unavailable.id = "qa-unavailable-care"; unavailable.client = "QA unavailable client"; unavailable.market_available = false
	game.state.offers.append(unavailable)
	check(not PANEL.eligible_offers(game).any(func(row): return str(row.get("id", "")) == "qa-unavailable-care"), "unavailable inquiry never appears in care shortlist")
	ui.set_meta("company_view", "care"); ui.open_panel("company"); await frames(6)
	var selected_id := str(offer.id)
	var before_selection := JSON.stringify(game.state.get("offer_plan_selections", {}))
	var accepted_before := bool(game.state.accepted)
	var good_path := str(game.save_path)
	game.save_path = "user://qa-care-offer-missing-%s/save.json" % OS.get_process_id()
	PANEL.open_offer(ui, game, selected_id)
	check(ui.current_kind == "company" and JSON.stringify(game.state.get("offer_plan_selections", {})) == before_selection and bool(game.state.accepted) == accepted_before, "failed care-plan save stays on company panel without changing the existing contract")
	game.save_path = good_path
	PANEL.open_offer(ui, game, selected_id); await frames(10)
	check(ui.current_kind == "sales" and str(ui.board_selected_id) == selected_id and str(game.offer_plan_for(offer)) == "care", "successful route opens selected inquiry with saved care quote")
	check(bool(game.state.accepted) == accepted_before and control("ContractPlan") is OptionButton, "sales detail presents the quote without changing acceptance of the existing contract")

func _offer(id: String) -> Dictionary:
	for offer in game.state.get("offers", []):
		if offer is Dictionary and str(offer.get("id", "")) == id: return offer
	return {}

func _test_workday_route(client: String) -> void:
	ui.set_meta("company_view", "care"); ui.open_panel("company"); await frames(6)
	var job: Dictionary = game._maintenance_job_for(client)
	var expected := "maintenance:" + str(job.get("id", ""))
	var workday = control("CareWorkday") as BaseButton
	check(not job.is_empty() and is_instance_valid(workday) and not workday.disabled, "care panel exposes a route for the actual daily job")
	if not is_instance_valid(workday): return
	workday.pressed.emit(); await frames(10)
	check(ui.current_kind == "board" and str(ui.operations_choices.workday_selected) == expected, "care workday route selects the saved maintenance job id")

func _test_small_layout(client: String) -> void:
	game.set_settings({"resolution":"960x600", "window_mode":"windowed", "text_scale":1.3, "volume":0}, false)
	var graphics := root.get_node_or_null("Graphics")
	if graphics != null and graphics.has_method("apply_settings"): graphics.apply_settings(game.settings)
	root.size = Vector2i(960, 600); ui._set_text_scale(1.3); await frames(4)
	ui.set_meta("company_view", "care"); ui.set_meta("company_client", client); ui.open_panel("company"); await frames(8)
	var balance := control("CareBalance") as Control
	var action := control("CareWorkday") as Control
	check(is_instance_valid(balance) and balance.is_visible_in_tree(), "daily balance is visible at 960px and 130% text")
	if is_instance_valid(action):
		await frames(3)
		check(action.is_visible_in_tree() and root.get_visible_rect().intersects(action.get_global_rect()), "care workday footer action is reachable at 960px and 130% text")
	else: check(false, "care workday action remains present in compact layout")

func finish() -> void:
	if is_instance_valid(ui):
		root.remove_child(ui); ui.free(); await process_frame
	if is_instance_valid(game):
		game._machine = null; game._machine_key = ""
	print("CARE_PORTFOLIO_UI_PASS narrow=%s" % str(narrow) if failures.is_empty() else "CARE_PORTFOLIO_UI_FAIL %s" % str(failures))
	quit(0 if failures.is_empty() else 1)
