extends "res://tests/test_saas_priority_market.gd"
## Routes from an unrelated live desktop to an actually accepted priority case.

const WATCH = preload("res://scripts/company_incident_watch.gd")

var ui

func frames(count: int = 5) -> void:
	for _index in count:
		await process_frame

func run() -> void:
	game = root.get_node("Game")
	game.set_process(false)
	var prefix := "user://qa-company-incident-ui-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".bak", prefix + ".previous", prefix + ".settings"])
	set_paths(paths)
	source_path = OS.get_environment("WHL_PRIORITY_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_PRIORITY_SOURCE points to the read-only paid handoff save")
		finish()
		return
	source_hash = FileAccess.get_sha256(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	if file == null:
		check(false, "write an isolated company-incident QA copy")
		finish()
		return
	file.store_string(FileAccess.get_file_as_string(source_path))
	file.close()
	if not game.load_game():
		check(false, "load source from isolated QA save")
		finish()
		return
	source_id = str(game.state.current_contract_id)
	game._make_offers()
	check(game.end_day(), "publish the next-day priority offer through settlement")
	var priority: Dictionary = priority_offer().duplicate(true)
	if priority.is_empty() or not bool(priority.get("market_available", false)):
		check(false, "priority case is available from the real market")
		finish()
		return
	check(game.set_offer_quote(str(priority.id), int(game.contract_quote(priority).estimated_fee)) and game.choose_contract(str(priority.id)), "accept priority case through the real market")
	var priority_id := str(game.state.current_contract_id)

	# Keep a second, ordinary accepted case active as the workstation we leave.
	var ordinary: Dictionary = {}
	for offer in game.state.offers:
		if not offer is Dictionary or not bool(offer.get("unlocked", false)) or not bool(offer.get("market_available", false)): continue
		if str(offer.get("case_id", "")) == PRIORITY or str(offer.get("case_id", "")).begins_with("advanced-"): continue
		var quote: Dictionary = game.contract_quote(offer)
		if bool(quote.get("affordable", false)):
			ordinary = offer.duplicate(true)
			break
	check(not ordinary.is_empty(), "an ordinary market case can occupy the other contract slot")
	if ordinary.is_empty() or not game.set_offer_quote(str(ordinary.id), int(game.contract_quote(ordinary).estimated_fee)) or not game.choose_contract(str(ordinary.id)):
		check(false, "accept the ordinary case through the real market")
		finish()
		return
	var ordinary_id := str(game.state.current_contract_id)
	var live_incidents: Array = WATCH.snapshot(game).get("incidents", [])
	var incident: Dictionary = {}
	for row in live_incidents:
		if str(row.get("contract_id", "")) == priority_id:
			incident = row
			break
	if incident.is_empty():
		check(false, "accepted priority case is present in the live incident projection")
		finish()
		return
	var target_index := int(incident.get("target_index", -1))
	var queue_id := "claims"
	if not incident.get("queues", []).any(func(row): return str(row.get("id", "")) == queue_id):
		check(false, "live priority case exposes the claims queue")
		finish()
		return

	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(8)
	ui.controls.menu.hide()
	ui.guided_intro.skip()
	ui.open_panel("terminal")
	await frames(8)
	var old_desktop = ui.desktop
	var old_session_key := str(old_desktop.session_key)
	old_desktop._show_app("verify")
	old_desktop._open_editor("workstation:/home/operator/Documents/route-draft.txt")
	await frames(3)
	var draft_text := "ordinary contract draft survives incident routing"
	old_desktop.widgets.editor.editor.text = draft_text
	var old_app := str(old_desktop.current_app)
	var old_contract := str(game.state.current_contract_id)
	check(old_contract == ordinary_id and old_app == "editor", "fixture is an ordinary-case desktop with an unsaved editor draft")

	# The existing QA-save failure path makes the close preflight fail before the
	# contract changes; the live desktop and active contract must remain mounted.
	var missing_prefix := "user://qa-company-incident-missing-%s/save.json" % OS.get_process_id()
	set_paths([missing_prefix, missing_prefix + ".bak", missing_prefix + ".previous", missing_prefix + ".settings"])
	ui._open_incident_work(priority_id, target_index, queue_id)
	await frames(2)
	check(ui.current_kind == "terminal" and ui.desktop == old_desktop, "failed workstation save keeps the same desktop open")
	check(str(game.state.current_contract_id) == ordinary_id and str(ui.desktop.current_app) == old_app and str(ui.desktop.widgets.editor.editor.text) == draft_text, "failed save preserves the selected ordinary contract and editor draft")
	set_paths(paths)

	ui._open_incident_work(priority_id, target_index, queue_id)
	check(old_desktop.widgets.has("verify"), "old desktop has diagnostics mounted during incident routing")
	check(old_desktop.is_queued_for_deletion() and not old_desktop.refreshing, "queued old diagnostics desktop ignores the synchronous contract-change refresh")
	await frames(10)
	check(str(game.state.current_contract_id) == priority_id and int(game.state.target_index) == target_index, "successful route switches to the exact open priority target")
	check(ui.current_kind == "terminal" and str(ui.desktop.current_app) == "advanced", "successful route returns to the priority workspace")
	var advanced_selection: Dictionary = ui.desktop.advanced_ui.get(PRIORITY, {})
	check(str(advanced_selection.get("queue_id", "")) == queue_id and str(advanced_selection.get("tab", "")) == "board", "successful route selects the requested queue")
	var old_session: Dictionary = game.state.get("desktop_sessions", {}).get(old_session_key, {})
	check(str(old_session.get("drafts", {}).get("workstation:/home/operator/Documents/route-draft.txt", "")) == draft_text, "routing away persists the ordinary-case draft in its own session")

	# Isolate a malformed accepted-case projection in this QA copy. The ribbon
	# still knows which incident it is, but must not guess a queue or open the
	# delivery receipt when the saved business brief cannot be trusted.
	var priority_work: Dictionary = game.state.get("work", {}).duplicate(true)
	var recorded_costs: Dictionary = priority_work.get("saas_costs", {}).duplicate(true)
	recorded_costs.erase("assistant_runs")
	priority_work.saas_costs = recorded_costs
	game.state.work = priority_work
	game._sync_target()
	game._sync_contract_context()
	var unknown_incident: Dictionary = {}
	for row in WATCH.snapshot(game).get("incidents", []):
		if str(row.get("contract_id", "")) == priority_id:
			unknown_incident = row
			break
	check(not unknown_incident.is_empty() and not bool(unknown_incident.get("available", true)) and unknown_incident.get("queues", []).is_empty(), "malformed accepted-case QA record keeps incident identity while its business brief is unavailable")
	var before_unknown_clock := int(game.state.get("clock_minutes", 0))
	var before_unknown_work: Dictionary = game.state.get("work", {}).duplicate(true)
	ui._open_incident_work(priority_id, target_index, "")
	await frames(10)
	check(ui.current_kind == "terminal" and str(ui.desktop.current_app) == "advanced", "unavailable incident opens its investigation records instead of delivery")
	var unknown_selection: Dictionary = ui.desktop.advanced_ui.get(PRIORITY, {})
	check(str(unknown_selection.get("tab", "")) == "records" and int(unknown_selection.get("item_index", -2)) == -1 and str(unknown_selection.get("open_record", "not-empty")) == "", "unavailable incident clears stale record selection and opens records")
	check(int(game.state.get("clock_minutes", 0)) == before_unknown_clock and game.state.get("work", {}) == before_unknown_work, "opening unavailable incident does not change company time or costs")

	# A delivered source ID and an arbitrary stale ID are not routable from the
	# current ribbon snapshot and must not replace the live priority desktop.
	var current_desktop = ui.desktop
	for stale_id in [source_id, "qa-stale-incident-id"]:
		ui._open_incident_work(stale_id, 0, "claims")
		await frames(2)
		check(ui.desktop == current_desktop and str(game.state.current_contract_id) == priority_id, "closed or stale incident ID is ignored: " + stale_id)
	finish()

func finish() -> void:
	if is_instance_valid(ui): ui.queue_free()
	await frames(2)
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "read-only source remains byte identical")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COMPANY_INCIDENT_UI_TEST_PASS" if failures.is_empty() else "COMPANY_INCIDENT_UI_TEST_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
