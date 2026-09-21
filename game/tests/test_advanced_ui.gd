extends SceneTree

const CaseCatalog = preload("res://scripts/case_catalog.gd")
const GAME = preload("res://scripts/game.gd")
const ASSURANCE_TEST = preload("res://tests/test_advanced_assurance.gd")

var game: Node
var office: Node3D
var failures: Array[String] = []
var narrow := false

func _init() -> void:
	narrow = "--narrow" in OS.get_cmdline_user_args()
	create_timer(70.0).timeout.connect(func(): push_error("Advanced UI timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int = 5) -> void:
	for _i in count:
		await process_frame

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await frames()
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/advanced/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	check(root.get_texture().get_image().save_png(folder.path_join(label + suffix + ".png")) == OK, "capture " + label)

func named(root_node: Node, node_name: String) -> Node:
	return root_node.find_child(node_name, true, false)

func named_prefix(root_node: Node, prefix: String) -> Node:
	for child in root_node.find_children("*", "Node", true, false):
		if str(child.name).begins_with(prefix): return child
	return null

func check_public_advanced_cases() -> void:
	var cases: Array[String] = ["advanced-hunt","advanced-pentest","advanced-recovery","advanced-ddos","advanced-api","advanced-supplychain","advanced-cloud","advanced-malware","advanced-detection"]
	for case_id in cases:
		var candidate_game: Node = GAME.new()
		root.add_child(candidate_game)
		candidate_game.save_path = "user://qa-advanced-ui-%s-%s.json" % [str(OS.get_process_id()), case_id]
		candidate_game.backup_path = candidate_game.save_path + ".bak"
		candidate_game.previous_path = candidate_game.save_path + ".previous"
		candidate_game.settings_path = candidate_game.save_path + ".settings"
		candidate_game._reset_state()
		var definition: Dictionary = CaseCatalog.by_id(case_id)
		check(candidate_game.choose_strategy(str(definition.get("category", "response"))), case_id + " public strategy")
		check(candidate_game.start_free_career(), case_id + " public career")
		candidate_game.state.skills = {"advisory":10,"operations":10,"response":10}
		candidate_game.state.peak_profit = 1000000000
		candidate_game.state.credit = 1000000
		candidate_game.state.market_leads = [case_id]
		candidate_game.state.market_day = int(candidate_game.state.day)
		candidate_game._make_offers()
		var selected: Dictionary = {}
		for item in candidate_game.state.offers:
			if str(item.get("case_id", "")) == case_id:
				item.market_available = true
				selected = item
				break
		check(not selected.is_empty(), case_id + " public offer")
		if not selected.is_empty():
			var id := str(selected.id)
			check(candidate_game.set_offer_quote(id, int(candidate_game.contract_quote(selected).estimated_fee)), case_id + " public quote")
			check(candidate_game.choose_contract(id), case_id + " public accept")
			var rendered: Dictionary = candidate_game.advanced_view()
			check(not rendered.is_empty() and not rendered.get("actions", []).is_empty(), case_id + " view actions")
			if case_id in ["advanced-hunt", "advanced-pentest", "advanced-recovery", "advanced-cloud", "advanced-malware", "advanced-detection"]:
				check(not rendered.get("records", []).is_empty(), case_id + " initial records")
			candidate_game.settings.text_scale = 1.3 if narrow else 1.0
			var desk: Control = load("res://scripts/desktop.gd").new()
			root.add_child(desk); desk.setup(candidate_game); desk._show_app("advanced")
			await frames(3)
			for step in _solution(case_id): await _ui_step(candidate_game, desk, step, case_id)
			var verify: Button = named(desk, "AdvancedVerify")
			verify.pressed.emit(); await frames(2)
			check(candidate_game.can_deliver(), case_id + " all controls solve case")
			desk.advanced_ui.view = "results"; desk._refresh_advanced(); await frames(2)
			await capture(case_id)
			desk.queue_free(); await frames(2)
		candidate_game.queue_free()

func _solution(case_id: String) -> Array:
	match case_id:
		"advanced-hunt": return [["correlate_gateway"],["correlate_workstation"],["correlate_fileserver"],["pin","evt-05"],["pin","evt-06"],["revoke_session","sid-r44"],["disable_task","task-sync"],["probe_security"],["probe_business"]]
		"advanced-pentest": return [["discover_assets"],["inspect_permissions"],["connect_target","share01"],["read_credential","share01"],["authenticate_service","svc-report"],["read_proof","evidence/proof.csv"],["modify_grant","share01"],["retest_path","evidence/proof.csv"]]
		"advanced-recovery": return [["compare_snapshots","snap-1405"],["stage_restore"],["scan_stage"],["remove_persistence"],["scan_stage"],["isolate_network"],["repair_identity"],["restore_business"],["reconnect_business"]]
		"advanced-cloud": return [["disable_grant","app-72"],["revoke_app_session","app-72"],["one_probe","app-19"],["one_probe","app-72"],["pin","audit-2"],["verify"]]
		"advanced-malware": return [["static_scan"],["compare_normal"],["sandbox_network","on"],["execute_sandbox"],["derive_indicators"],["hunt_indicators"],["quarantine_file","endpoint-a"],["quarantine","endpoint-a"],["quarantine_persistence"],["rescan"]]
		"advanced-detection": return [["set_source","network"],["set_process","invoice_update.exe"],["set_threshold","2"],["set_exclusion",""],["set_notification","on"],["replay"],["verify"]]
	return ASSURANCE_TEST.solution(case_id)

func _ui_step(g: Node, desk: Control, step: Array, case_id: String) -> void:
	var action := str(step[0]); var operand := str(step[1]) if step.size() > 1 else ""
	var option_id := str(step[2]) if step.size() > 2 else operand
	if action == "pin":
		var data: Dictionary = g.advanced_view()
		var in_events: bool = data.events.any(func(row: Dictionary): return str(row.id) == operand)
		desk.advanced_ui.view = "events" if in_events else "records"; desk.advanced_ui.filter = ""; desk._refresh_advanced(); await frames(2)
		var tree: Tree = named(desk, "AdvancedEvents" if in_events else "AdvancedRecords")
		var row := tree.get_root().get_first_child(); var found := false
		while row != null:
			if str(row.get_metadata(0).get("id", "")) == operand:
				row.select(0); tree.item_selected.emit(); found = true; break
			row = row.get_next()
		check(found, case_id + " visible evidence " + operand)
		await frames(2)
		var pin: Button = named(desk, "AdvancedPin")
		check(is_instance_valid(pin), case_id + " evidence pin control")
		if is_instance_valid(pin): pin.pressed.emit()
		await frames(2); return
	var chosen: Dictionary = {}; var node_id := ""
	var nodes: Array = g.advanced_view().nodes
	for node in nodes:
		for candidate in g.advanced_view(str(node.id)).get("actions", []):
			if str(candidate.id) != action: continue
			if step.size() > 2 and str(candidate.target) != operand: continue
			var choices: Array = candidate.get("options", [])
			if choices.is_empty() and not operand.is_empty() and str(candidate.target) != operand: continue
			if not choices.is_empty() and not choices.any(func(choice: Dictionary): return str(choice.id) == option_id): continue
			var candidate_target := str(candidate.get("target", ""))
			var node_target: bool = nodes.any(func(n: Dictionary): return str(n.id) == candidate_target)
			if node_target and candidate_target != str(node.id): continue
			chosen = candidate; node_id = str(node.id); break
		if not chosen.is_empty(): break
	check(not chosen.is_empty(), case_id + " action reachable " + action)
	if chosen.is_empty(): return
	desk.advanced_ui.view = "network"; desk._refresh_advanced(); await frames(2)
	var node_button: Button = named(desk, "AdvancedNode_" + node_id.validate_node_name())
	check(is_instance_valid(node_button), case_id + " node control " + node_id)
	if not is_instance_valid(node_button): return
	node_button.pressed.emit(); await frames(2)
	var action_key := (action + "_" + str(chosen.target)).validate_node_name()
	if not chosen.get("options", []).is_empty():
		var choice: OptionButton = named(desk, "AdvancedOption_" + action_key)
		check(is_instance_valid(choice), case_id + " operand " + action)
		if not is_instance_valid(choice): return
		var before: int = int(g.state.revision)
		for index in choice.item_count:
			if str(choice.get_item_metadata(index)) == option_id: choice.select(index); choice.item_selected.emit(index); break
		check(int(g.state.revision) == before, case_id + " operand only selects " + action)
	var button: Button = named(desk, "AdvancedAction_" + action_key)
	check(is_instance_valid(button), case_id + " apply control " + action)
	if is_instance_valid(button):
		var revision: int = int(g.state.revision); button.pressed.emit(); await frames(2)
		check(int(g.state.revision) > revision, case_id + " applied " + action)

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-advanced-"):
		push_error("Advanced QA needs isolated profile")
		quit(2)
		return
	game.set_process(false)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	await check_public_advanced_cases()
	check(game.new_game(), "new isolated game")
	check(game.choose_strategy("advisory") and game.start_free_career(), "start career")
	game.state.skills = {"advisory":10,"operations":10,"response":10}
	game.state.peak_profit = 1000000000
	game.state.credit = 1000000
	var advanced_definitions: Array = ["advanced-hunt","advanced-pentest","advanced-recovery","advanced-ddos","advanced-api","advanced-supplychain","advanced-cloud","advanced-malware","advanced-detection"]
	game.state.market_leads = advanced_definitions
	game.state.market_day = int(game.state.day)
	game._make_offers()
	var offer: Dictionary = {}
	for candidate in game.state.get("offers", []):
		if str(candidate.get("case_id", "")) == "advanced-hunt":
			candidate.market_available = true
			offer = candidate
			break
	check(not offer.is_empty(), "advanced offer available")
	if offer.is_empty():
		_finish()
		return
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)), "advanced quote set")
	check(game.choose_contract(str(offer.id)), "advanced quote accepted")
	game.settings.text_scale = 1.3 if narrow else 1.0
	office = load("res://scripts/office.gd").new()
	root.add_child(office)
	await frames(12)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	await frames(5)
	office.started = true
	office.ui.controls.menu.hide()
	office.ui.current_kind = ""
	office.player.set_physics_process(false)
	office.player.position = Vector3(-0.5, 0.05, 0.5)
	office.player.camera.look_at(Vector3(-0.5, 1.02, -1.1), Vector3.UP)
	office.ui.open_panel("terminal")
	office.ui.desktop._show_app("advanced")
	await frames(12)
	var advanced: Control = named(office.ui.desktop, "AdvancedWorkbench")
	check(is_instance_valid(advanced), "advanced workbench visible")
	check(not game.advanced_view().is_empty(), "advanced view has state")
	await capture("01-network")
	var verify: Button = named(office.ui.desktop, "AdvancedVerify")
	check(is_instance_valid(verify) and not verify.disabled, "verify control enabled")
	var advanced_ui: Dictionary = office.ui.desktop.advanced_ui
	var selected_before := str(advanced_ui.get("selected", ""))
	var network: Control = named(office.ui.desktop, "AdvancedNetworkMap")
	if is_instance_valid(network):
		var first_node := network.get_child(0)
		if first_node is Button:
			first_node.pressed.emit()
			await frames(4)
			check(str(office.ui.desktop.advanced_ui.get("selected", "")) != selected_before, "selected asset persists")
	var search: LineEdit = named(office.ui.desktop, "AdvancedSearch")
	var initial_events: Button = named(office.ui.desktop, "AdvancedTab_events")
	initial_events.pressed.emit(); await frames(2)
	check(is_instance_valid(search), "search control visible")
	if is_instance_valid(search):
		search.grab_focus()
		search.text = "sid"
		search.text_changed.emit("sid")
		await frames(3)
		check(search.has_focus(), "search retains focus")
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "search does not change pointer mode")
	var events_tab: Button = named(office.ui.desktop, "AdvancedTab_events")
	check(is_instance_valid(events_tab), "events tab visible")
	if is_instance_valid(events_tab):
		events_tab.pressed.emit()
		await frames(5)
	await capture("02-events-search")
	var tree: Tree = named(office.ui.desktop, "AdvancedEvents")
	check(is_instance_valid(tree), "event records visible")
	check(is_instance_valid(tree) and tree.get_root() != null and tree.get_root().get_first_child() != null, "event tree has rows")
	if is_instance_valid(tree) and tree.get_root() != null and tree.get_root().get_first_child() != null:
		tree.get_root().get_first_child().select(0)
		tree.item_selected.emit()
		await frames(4)
	var pin: Button = named(office.ui.desktop, "AdvancedPin")
	check(is_instance_valid(pin), "pin control visible for selected event")
	if is_instance_valid(pin):
		var before_pin := JSON.stringify(game.advanced_view().get("events", []))
		pin.pressed.emit()
		await frames(5)
		check(JSON.stringify(game.advanced_view().get("events", [])) != before_pin, "pin invokes real action")
	var records_tab: Button = named(office.ui.desktop, "AdvancedTab_records")
	if is_instance_valid(search):
		search.text = ""
		search.text_changed.emit("")
	if is_instance_valid(records_tab):
		records_tab.pressed.emit()
		await frames(5)
	await capture("03-records")
	var option: OptionButton = named_prefix(office.ui.desktop, "AdvancedOption_")
	var revision_before := int(game.state.advanced.get("revision", 0))
	check(is_instance_valid(option), "action operand control visible")
	if is_instance_valid(option) and option.item_count > 1:
		option.select(1)
		option.item_selected.emit(1)
		await frames(2)
		check(int(game.state.advanced.get("revision", 0)) == revision_before, "option selection does not mutate")
		var apply: Button = named_prefix(office.ui.desktop, "AdvancedAction_")
		check(is_instance_valid(apply), "apply control visible")
		if is_instance_valid(apply):
			apply.pressed.emit()
			await frames(5)
			check(int(game.state.advanced.get("revision", 0)) > revision_before, "apply invokes actual action")
	else:
		check(false, "action operand has multiple real choices")
	await capture("04-action")
	var results: Button = named(office.ui.desktop, "AdvancedTab_results")
	if is_instance_valid(results):
		results.pressed.emit()
		await frames(5)
	await capture("05-results")
	check(office.ui.close_panel(false, false), "close advanced app")
	office.queue_free()
	await frames(3)
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("ADVANCED_UI_PASS")
	else:
		for failure in failures:
			push_error("ADVANCED_UI: " + failure)
		print("ADVANCED_UI_FAIL count=", failures.size())
	quit(0 if failures.is_empty() else 1)
