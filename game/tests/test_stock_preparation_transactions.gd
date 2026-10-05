extends SceneTree

## End-to-end transaction checks for the terminal preparation bench. The
## career gate and funds are QA fixtures; offers, stock, VM behavior, checks,
## shipment, arrival, and delivery all use the real Game APIs.
const GameScript = preload("res://scripts/game.gd")
const STOCK = preload("res://scripts/customer_stock.gd")
const BOARD = preload("res://scripts/stock_preparation_board.gd")

var failures: Array[String] = []
var game: Node
var qa_prefix := ""

func _init() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("STOCK_PREPARATION timed out"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("STOCK_PREPARATION: " + label)

func set_paths(target: Node, prefix: String) -> void:
	target.save_path = "user://" + prefix + ".json"
	target.backup_path = target.save_path + ".bak"
	target.previous_path = target.save_path + ".previous"
	target.settings_path = target.save_path + ".settings"

func offer_for(case_id: String) -> Dictionary:
	for offer in game.state.get("offers", []):
		if str(offer.get("case_id", "")) == case_id and bool(offer.get("market_available", false)): return offer
	return {}

func load_saved_game(label: String) -> Node:
	var loaded: Node = GameScript.new()
	set_paths(loaded, qa_prefix)
	root.add_child(loaded)
	await process_frame
	loaded.set_process(false)
	check(loaded.load_game(), label + " reloads through a new Game instance")
	return loaded

func run() -> void:
	game = GameScript.new()
	qa_prefix = "stock-preparation-" + str(OS.get_process_id())
	set_paths(game, qa_prefix)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._reset_state()
	check(game.choose_strategy("advisory"), "isolated career fixture starts cleanly")
	check(game.start_free_career(), "enter funded career fixture")
	# This test-only progression fixture unlocks the authored equipment case.
	game.state.skills.advisory = 1
	game.state.skills.operations = 1
	game.state.peak_profit = 3000
	game.state.cash = 30000
	var hardware_offer: Dictionary = {}
	for day_offset in 60:
		game.state.day = day_offset + 1
		game.state.market_leads = ["hardware-gateway-install"]
		game.state.market_day = int(game.state.day)
		game._make_offers()
		hardware_offer = offer_for("hardware-gateway-install")
		if not hardware_offer.is_empty(): break
	check(not hardware_offer.is_empty() and bool(hardware_offer.get("unlocked", false)), "authored gateway installation appears on an ordinary market day")
	if hardware_offer.is_empty():
		finish(); return
	check(game.choose_contract(str(hardware_offer.get("id", ""))), "accept the actual gateway contract")
	var contract_id := str(game.state.current_contract_id)
	var purchase: Dictionary = game.buy_customer_stock(3)
	var backup_purchase: Dictionary = game.buy_customer_stock(1, "backup_appliance")
	check(bool(purchase.get("ok", false)) and purchase.get("ids", []).size() == 3, "purchase three real gateway devices")
	check(bool(backup_purchase.get("ok", false)) and backup_purchase.get("ids", []).size() == 1, "purchase a wrong-SKU appliance for rejection coverage")
	if not bool(purchase.get("ok", false)) or not bool(backup_purchase.get("ok", false)):
		finish(); return
	check(game.advance_delivery(30.0), "real inbound orders reach receiving")
	var gateway_a := str(purchase.ids[0])
	var gateway_b := str(purchase.ids[1])
	var backup_id := str(backup_purchase.ids[0])
	check(str(game.customer_stock_for(gateway_a).get("status", "")) == "ready", "gateway serial is available only after arrival")
	check(str(game.prepare_customer_stock(backup_id).get("error", "")) == "sku", "preparation rejects wrong SKU without claiming it")
	var queued: Dictionary = game.buy_customer_stock(1)
	check(bool(queued.get("ok", false)) and str(game.prepare_customer_stock(str(queued.get("ids", [""])[0])).get("error", "")) == "status", "preparation rejects a queued, not-yet-arrived device")
	check(game.take_delivery(backup_id), "legacy 3D pickup API still takes stock")
	check(str(game.prepare_customer_stock(gateway_a).get("error", "")) == "held", "preparation respects the single carried-device constraint")
	check(bool(game.store_customer_stock(backup_id).get("ok", false)), "legacy pickup and shelf-storage APIs still work")
	# Synthetic wrong-contract assignment is created with the real stock model,
	# then exercised on an isolated Game copy so the main unit stays available.
	var other_contract_state: Dictionary = game.state.duplicate(true)
	var other_take: Dictionary = STOCK.take(other_contract_state, gateway_a)
	var other_stage: Dictionary = STOCK.stage(other_contract_state, gateway_a, "fixture-other-contract", 0)
	check(bool(other_take.get("ok", false)) and bool(other_stage.get("ok", false)), "underlying stock model creates a synthetic other-contract assignment")
	if bool(other_stage.get("ok", false)):
		var other_game: Node = GameScript.new()
		set_paths(other_game, qa_prefix + "-other-contract")
		root.add_child(other_game)
		await process_frame
		other_game.set_process(false)
		other_game.state = other_contract_state.duplicate(true)
		other_game._assignments = game._assignments.duplicate(true)
		var other_before := JSON.stringify(other_game.state)
		check(str(other_game.prepare_customer_stock(gateway_a).get("error", "")) == "contract", "preparation refuses hardware assigned by another contract")
		check(JSON.stringify(other_game.state) == other_before, "other-contract rejection leaves the assigned unit unchanged")
		# A legitimately staged then picked-up unit keeps its target assignment.
		# Even within one contract it must not silently move to another site.
		var other_site_state: Dictionary = game.state.duplicate(true)
		check(bool(STOCK.take(other_site_state, gateway_a).get("ok", false)) and bool(STOCK.stage(other_site_state, gateway_a, contract_id, 1).get("ok", false)) and bool(STOCK.take(other_site_state, gateway_a).get("ok", false)), "stock model preserves another target binding while carried")
		other_game.state = other_site_state
		var other_site_before := JSON.stringify(other_game.state)
		check(str(other_game.prepare_customer_stock(gateway_a).get("error", "")) == "contract", "preparation refuses carried hardware assigned to another target in this contract")
		check(JSON.stringify(other_game.state) == other_site_before, "other-target rejection leaves the carried unit and binding unchanged")
		other_game.queue_free()
	# A live unsaved VM snapshot stands in for editor draft state when persistence
	# fails. It must survive exactly, along with assignments and stock positions.
	var machine = game._vm()
	var config_path := str(game.vm_info().get("config_path", ""))
	var draft_text: String = machine.configuration_text({"dns":"off", "business":"deny", "admin_public":"deny", "tls":"on"})
	if not config_path.is_empty(): machine.state.fs[config_path] = draft_text; machine.state.dirty = true
	check(not config_path.is_empty() and bool(machine.state.get("dirty", false)), "seed an unsaved VM editor draft for rollback coverage")
	check(game.take_delivery(gateway_b) and str(game.customer_stock_for(gateway_b).get("status", "")) == "carried", "existing 3D pickup can hand the same device to atomic preparation")
	var state_before_failure: Dictionary = game.state.duplicate(true)
	var assignments_before_failure: Dictionary = game._assignments.duplicate(true)
	var machine_before_failure: Dictionary = machine.export_state()
	var machine_key_before_failure := str(game._machine_key)
	var good_save_path := str(game.save_path)
	set_paths(game, qa_prefix + "-missing-parent/save")
	var failed_prepare: Dictionary = game.prepare_customer_stock(gateway_b)
	set_paths(game, qa_prefix)
	check(str(failed_prepare.get("error", "")) == "save", "failed prepare reports persistence failure")
	check(game.state == state_before_failure and game._assignments == assignments_before_failure, "failed prepare restores exact state, stock position, and assignments")
	check(game._machine == machine and game._machine.export_state() == machine_before_failure and str(game._machine_key) == machine_key_before_failure, "failed prepare restores the exact live VM draft and key")
	check(game.save_path == good_save_path, "retry uses original isolated storage")
	var prepared: Dictionary = game.prepare_customer_stock(gateway_b)
	check(bool(prepared.get("ok", false)) and str(game.customer_stock_for(gateway_b).get("status", "")) == "staged", "atomic prepare picks up and stages the selected physical serial")
	check(str(game.customer_stock_for(gateway_b).get("contract_id", "")) == contract_id and int(game.customer_stock_for(gateway_b).get("target_index", -1)) == 0, "prepared unit is bound to current contract target")
	var occupied_before := JSON.stringify(game.state)
	check(str(game.prepare_customer_stock(gateway_a).get("error", "")) == "assigned" and JSON.stringify(game.state) == occupied_before, "occupied setup bench refuses another serial and restores its pickup")
	check(game.vm_run("ssh client").contains("Connected") or bool(game.vm_info().get("connected", false)), "prepared hardware provides the real VM connection")
	check(str(game.vm_run("dig intranet.client.test")).contains("SERVFAIL"), "actual service is misconfigured before repair")
	var staged_probes: Array = game.diagnostic_probes()
	var probe_to_measure := ""
	for probe in staged_probes:
		if not bool(probe.get("requires_login", false)):
			probe_to_measure = str(probe.get("id", "")); break
	check(not probe_to_measure.is_empty() and not game.run_diagnostic(probe_to_measure).is_empty(), "record a real pre-repair VM measurement for staged reload")
	check(game.save_game(), "persist the staged serial, current VM draft, and real measurement")
	var staged_reload: Node = await load_saved_game("staged stock")
	check(str(staged_reload.customer_stock_for(gateway_b).get("serial", "")) == str(game.customer_stock_for(gateway_b).get("serial", "")) and str(staged_reload.customer_stock_for(gateway_b).get("status", "")) == "staged", "staged reload preserves physical serial and state")
	check(str(staged_reload.customer_stock_for(gateway_b).get("contract_id", "")) == contract_id and int(staged_reload.customer_stock_for(gateway_b).get("target_index", -1)) == 0, "staged reload preserves contract and target binding")
	var staged_key := contract_id + "/site-0"
	var staged_vm: Dictionary = staged_reload.state.get("vm_states", {}).get(staged_key, {})
	check(str(staged_vm.get("fs", {}).get(config_path, "")) == draft_text, "staged reload preserves the actual VM editor configuration")
	var before_projection_json := JSON.stringify(staged_reload.state)
	var before_projection_vm: Dictionary = staged_reload.state.get("vm_states", {}).duplicate(true)
	var before_projection_clock: int = staged_reload.clock_minutes()
	var before_projection_cash := int(staged_reload.state.cash)
	var before_projection_key := str(staged_reload._machine_key)
	var before_projection_machine = staged_reload._machine
	var projected: Dictionary = BOARD.project(staged_reload, gateway_b)
	check(str(projected.get("chosen", {}).get("serial", "")) == str(staged_reload.customer_stock_for(gateway_b).get("serial", "")) and str(projected.get("chosen", {}).get("status", "")) == "staged", "read-only board projection shows the persisted staged serial")
	check(JSON.stringify(staged_reload.state) == before_projection_json and staged_reload.state.vm_states == before_projection_vm and staged_reload.clock_minutes() == before_projection_clock and int(staged_reload.state.cash) == before_projection_cash, "board projection leaves save, VM snapshots, clock, and cash unchanged")
	check(staged_reload._machine == before_projection_machine and str(staged_reload._machine_key) == before_projection_key and staged_reload._machine == null, "board projection does not materialize a VM")
	var persisted_probes: Array = staged_reload.diagnostic_probes()
	check(persisted_probes.any(func(probe): return str(probe.get("id", "")) == probe_to_measure and bool(probe.get("recorded", false)) and bool(probe.get("fresh", false))), "staged reload preserves actual measurement freshness")
	var before_reload: Node = game
	game = staged_reload
	before_reload.queue_free()
	await process_frame
	check(str(game.ship_prepared_customer_stock(gateway_b).get("error", "")) == "checks" and str(game.customer_stock_for(gateway_b).get("status", "")) == "staged", "unverified prepared hardware cannot ship")
	var services: Dictionary = game.firewall_action("services", {"dns":"on", "tls":"on"})
	check(bool(services.get("ok", false)), "repair DNS and TLS using the real firewall editor")
	var lan_rule: Dictionary = {}
	for rule in game._vm().firewall_snapshot().get("rules", []):
		if str(rule.get("id", "")) == "lan-business": lan_rule = rule.duplicate(true)
	check(not lan_rule.is_empty(), "select the real business LAN firewall rule")
	if not lan_rule.is_empty():
		lan_rule.action = "pass"
		check(bool(game.firewall_action("save_rule", {"rule":lan_rule}).get("ok", false)), "save the real LAN firewall rule")
		check(bool(game.firewall_action("apply").get("ok", false)), "apply the measured firewall configuration")
	check(str(game.vm_run("curl https://intranet.client.test")).begins_with("HTTP/1.1 200"), "staff route works after applied configuration")
	check(str(game.vm_run("curl https://admin.client.test:8443")).contains("FIREWALL_DENIED"), "public administration remains denied")
	for probe in game.diagnostic_probes(): game.run_diagnostic(str(probe.get("id", "")))
	var checks: Array = game.verify()
	check(not checks.is_empty() and checks.filter(func(item): return not bool(item.get("hardware", false))).all(func(item): return bool(item.get("passed", false))), "fresh VM checks and measurements pass before device shipment")
	check(not game.can_deliver(), "hardware shipment remains a separate real arrival gate")
	var ship_state_before_failure: Dictionary = game.state.duplicate(true)
	var ship_assignments_before_failure: Dictionary = game._assignments.duplicate(true)
	var ship_machine = game._machine
	var ship_machine_before_failure: Dictionary = ship_machine.export_state()
	var ship_key_before_failure := str(game._machine_key)
	set_paths(game, qa_prefix + "-missing-parent/shipment")
	var failed_ship: Dictionary = game.ship_prepared_customer_stock(gateway_b)
	set_paths(game, qa_prefix)
	check(str(failed_ship.get("error", "")) == "save", "failed shipment reports persistence failure")
	check(game.state == ship_state_before_failure and game._assignments == ship_assignments_before_failure and str(game.customer_stock_for(gateway_b).get("status", "")) == "staged", "failed shipment restores exact stock and assignments")
	check(game._machine == ship_machine and game._machine.export_state() == ship_machine_before_failure and str(game._machine_key) == ship_key_before_failure, "failed shipment restores the exact live VM and key")
	var shipped: Dictionary = game.ship_prepared_customer_stock(gateway_b)
	check(bool(shipped.get("ok", false)) and str(game.customer_stock_for(gateway_b).get("status", "")) == "shipping", "verified preparation atomically picks up and dispatches the physical device")
	check(not game.can_deliver(), "in-transit hardware still blocks contract delivery")
	game.advance_delivery(5.0)
	check(str(game.customer_stock_for(gateway_b).get("status", "")) == "shipping" and float(game.customer_stock_for(gateway_b).get("elapsed_seconds", 0.0)) == 5.0, "shipment remains in transit with persisted elapsed time")
	check(game.save_game(), "persist in-transit elapsed time")
	var shipping_reload: Node = await load_saved_game("shipping stock")
	var shipping_unit: Dictionary = shipping_reload.customer_stock_for(gateway_b)
	check(str(shipping_unit.get("serial", "")) == str(game.customer_stock_for(gateway_b).get("serial", "")) and str(shipping_unit.get("status", "")) == "shipping", "shipping reload preserves the serial and transit state")
	check(str(shipping_unit.get("contract_id", "")) == contract_id and int(shipping_unit.get("target_index", -1)) == 0 and float(shipping_unit.get("elapsed_seconds", 0.0)) == 5.0, "shipping reload preserves contract binding and elapsed transit")
	var before_shipping_projection := JSON.stringify(shipping_reload.state)
	var shipping_cash := int(shipping_reload.state.cash)
	var shipping_clock: int = shipping_reload.clock_minutes()
	check(str(BOARD.project(shipping_reload, gateway_b).get("chosen", {}).get("status", "")) == "shipping", "read-only board projects an in-transit serial")
	check(JSON.stringify(shipping_reload.state) == before_shipping_projection and int(shipping_reload.state.cash) == shipping_cash and shipping_reload.clock_minutes() == shipping_clock and shipping_reload._machine == null, "shipping projection is pure and does not materialize a VM")
	var before_shipping_reload: Node = game
	game = shipping_reload
	before_shipping_reload.queue_free()
	await process_frame
	game.advance_delivery(6.0)
	check(str(game.customer_stock_for(gateway_b).get("status", "")) == "shipping", "remaining transit time is respected after reload")
	check(game.advance_delivery(1.0) and str(game.customer_stock_for(gateway_b).get("status", "")) == "delivered", "physical shipment arrival is recorded after reload")
	check(game.can_deliver() and game.deliver(), "real arrival releases the ordinary delivery and invoice flow")
	var receipt: Dictionary = game.completion_receipt()
	check(str(receipt.get("hardware_serial", "")) == str(game.customer_stock_for(gateway_b).get("serial", "")), "delivery receipt references the prepared serial")
	# Existing hand-operated 3D entry points remain callable for future jobs.
	check(game.has_method("take_delivery") and game.has_method("stage_customer_stock") and game.has_method("dispatch_customer_stock"), "legacy pickup, stage, and dispatch API names remain available")
	finish()

func finish() -> void:
	print("STOCK_PREPARATION failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)
