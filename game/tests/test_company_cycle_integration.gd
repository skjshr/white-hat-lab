extends SceneTree

## Real Game journey for the first delivery and same-customer follow-up.
## Configurations are edited through VM APIs; no desired dictionaries, passing
## checks, or completed contracts are injected. Market-cap checks below use an
## explicitly synthetic list, and the low-trust test is a labelled state fixture.
const CYCLE = preload("res://scripts/company_cycle.gd")
const MARKET = preload("res://scripts/market_demand.gd")
var game
var failures: Array[String] = []
var assertions := 0
var save_file := ""

func _init() -> void:
	create_timer(75.0).timeout.connect(func(): push_error("company cycle integration timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL company_cycle_integration: ", label)

func normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func run() -> void:
	await process_frame
	game = root.get_node("Game"); game.set_process(false)
	save_file = "user://company-cycle-integration-" + str(OS.get_process_id()) + ".json"
	game.save_path = save_file; game.backup_path = save_file + ".bak"; game.previous_path = save_file + ".previous"; game.settings_path = save_file + ".settings"
	check(game.new_game(), "fresh real Game save")
	check(int(game.state.cash) == 5000 and game.state.history.is_empty(), "initial funds and no completed work")
	check(game.choose_strategy("advisory"), "choose specialty through API")
	check(game.set_contract_plan("standard") and game.accept_mission(), "accept real first story")
	game.inspect_mission()
	game.vm_run("ssh client")
	check(bool(game.vm_info().connected), "connect to first customer's VM")
	check(str(game.vm_run("smbclient //client/share -U staff -c \"put /srv/data/orders.csv\"")).contains("DENIED"), "first customer's reported save failure is real")
	check(game.capture_baseline(), "preserve actual before state")
	var config := "[global]\n    map to guest = Never\n[share]\n    path = /srv/share\n    available = yes\n    guest ok = no\n    valid users = staff\n    read only = yes\n    write list = staff\n"
	check(game.vm_write("/etc/samba/smb.conf", config), "write explicit reviewed sharing policy")
	check(str(game.vm_run("systemctl restart " + str(game.vm_info().service))).contains("active"), "apply sharing policy")
	check(str(game.vm_run("smbclient //client/share -U staff -c \"put /srv/data/orders.csv\"")).contains("OK"), "staff can now write real file")
	check(str(game.vm_run("smbclient //client/share -U guest -c ls")).contains("DENIED"), "guest cannot read after repair")
	measure()
	check(game.can_deliver(), "real first story passes verification")
	if not game.can_deliver(): finish(); return
	var before_failure: String = JSON.stringify(game.state)
	game.save_path = "user://missing-company-cycle-" + str(OS.get_process_id()) + "/save.json"
	check(not game.deliver(), "delivery rejects failed durable save")
	check(JSON.stringify(game.state) == before_failure, "failed delivery restores entire state including cash, cycle, history and earned goals")
	game.save_path = save_file
	check(game.deliver(), "retry actual delivery succeeds")
	check(str(game.state.last_receipt.rating) == "on_time", "first story has actual on-time outcome")
	var lead: Dictionary = game.state.company_cycle.leads.get("つばさ文具", {})
	check(str(lead.get("source_contract_id", "")) == "share" and str(lead.get("source_case_id", "unknown")) == "", "story origin is preserved without invented catalog ID")
	check(str(lead.get("case_id", "")) == "service-5-case-1", "real first customer creates different-service consultation")
	check(game.state.company_cycle.earned_goals.has("first_delivery"), "earned first-company goal commits with successful delivery")
	var completed := normalized(game.state)
	check(not game.deliver() and normalized(game.state) == completed, "duplicate delivery grants neither second reward nor second consultation")
	await reload_projection("first story")
	check(game.start_free_career(), "first story enters career through public API")
	var choice := find_offer("service-5-case-1")
	check(not choice.is_empty() and bool(choice.get("unlocked", false)) and bool(choice.get("market_available", false)), "earned different-service request is reachable in actual market")
	check(int(game.company_level().level) >= 2, "actual first-work profit unlocked required level without fixture")
	if choice.is_empty() or not bool(choice.get("market_available", false)): finish(); return
	var stable := normalized(game.state.company_cycle.leads)
	check(game.end_day(), "unaccepted consultation carries to next real day")
	check(normalized(game.state.company_cycle.leads) == stable, "day change preserves consultation identity, source and reason")
	choice = find_offer("service-5-case-1")
	check(bool(choice.get("market_available", false)), "eligible consultation remains surfaced next day")
	check(game.set_offer_quote(str(choice.id), int(game.contract_quote(choice).reference_fee)), "quote earned follow-up")
	var quote_copy := normalized(game.state.offer_quotes)
	game._make_offers()
	check(normalized(game.state.offer_quotes) == quote_copy and str(choice.case_id) in game.state.market_leads, "market refresh preserves prepared quote and lead")
	await reload_projection("quoted follow-up")
	check(game.choose_contract(str(choice.id)), "accept actual same-customer different-service request")
	game.inspect_mission(); game.vm_run("ssh client")
	check(int(game.state.chapter) == 5, "follow-up opens external sharing engine")
	var path := str(game.vm_info().config_path)
	var text := str(game.vm_read(path))
	check(text.contains("expires=unlimited"), "follow-up's actual configuration has reported missing expiry")
	check(game.capture_baseline(), "preserve follow-up original state")
	check(game.vm_write(path, text.replace("expires=unlimited", "expires=7d")), "change real expiry while retaining other settings")
	check(str(game.vm_run("systemctl restart " + str(game.vm_info().service))).contains("active"), "apply actual external-sharing change")
	measure()
	check(game.can_deliver(), "external-sharing normal and forbidden operations pass")
	# Simulate a player's delay through the clock API, not fake completion flags.
	while float(game.work_status().elapsed_minutes) <= float(game.work_status().budget): game.advance_office_time(10)
	check(game.deliver(), "technically successful but late follow-up can be delivered")
	lead = game.state.company_cycle.leads.get("つばさ文具", {})
	check(str(game.state.last_receipt.rating) == "late", "real elapsed-time failure is recorded")
	check(str(lead.get("case_id", "")) == "service-4-case-2" and str(lead.get("status", "")) == "paused", "late target fulfillment preserves a paused next different-service consultation")
	check(game.state.company_cycle.events.any(func(event): return str(event.get("kind", "")) == "fulfilled" and str(event.get("case_id", "")) == "service-5-case-1"), "technical fulfillment remains a real event despite poor timing")
	await reload_projection("late follow-up")
	market_caps_fixture()
	low_trust_observation()
	malformed_save_boundaries()
	finish()

func measure() -> void:
	for attempt in 4:
		for probe in game.diagnostic_probes():
			if not bool(probe.get("fresh", false)) or not bool(probe.get("passed", false)): game.run_diagnostic(str(probe.id))
		if game.diagnostic_probes().all(func(probe): return bool(probe.get("fresh", false)) and bool(probe.get("passed", false))): break
	var checks: Array = game.verify()
	check(not checks.is_empty() and checks.all(func(row): return bool(row.get("passed", false))), "actual VM diagnostics and verification pass")

func find_offer(case_id: String) -> Dictionary:
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == case_id: return offer
	return {}

func projection() -> Dictionary:
	return {"cycle":game.state.company_cycle,"history":game.state.history,"cash":game.state.cash,"profit":game.state.profit,"credit":game.state.credit,"vm_states":game.state.vm_states,"relations":game.state.customer_relations,"quotes":game.state.offer_quotes,"billing":game.state.billing}

func reload_projection(label: String) -> void:
	check(game.save_game(), label + " saves")
	var before := normalized(projection())
	check(game.load_game(), label + " reloads")
	check(normalized(projection()) == before, label + " reload preserves cycle/history/goals/economy/VM/quotes/billing exactly")
	await process_frame

func market_caps_fixture() -> void:
	# Synthetic candidate list tests the integration selection function without
	# relying on whichever day-specific jobs happen to occupy a market slot.
	var candidates: Array = []
	for id in ["quoted", "carried", "ordinary", "referral"]: candidates.append({"case_id":id,"category":"advisory","unlocked":true})
	var result: Array = MARKET.prioritize_relationships(candidates, ["quoted", "carried", "ordinary"], ["referral"], ["quoted", "carried"], 1)
	check(result.size() == 3 and "referral" in result, "referral replaces a normal slot without expanding demand cap")
	check("quoted" in result and "carried" in result and "ordinary" not in result, "quoted and accepted choices are preserved")
	var full: Array = MARKET.prioritize_relationships(candidates, ["quoted", "carried", "ordinary"], ["referral"], ["quoted", "carried", "ordinary"], 1)
	check(full == ["quoted", "carried", "ordinary"], "all protected market choices defer referral rather than disappearing")

func low_trust_observation() -> void:
	# Explicit relationship fixture: completed work/VM remain genuine; only the
	# relationship is lowered to inspect the availability of recovery choices.
	game.state.customer_relations["つばさ文具"].satisfaction = 30
	game._make_offers()
	var ordinary: Array = game.state.offers.filter(func(offer): return str(offer.get("client", "")) == "つばさ文具" and str(offer.get("id", "")) not in game.state.completed_ids and bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false)))
	print("RECOVERY_OBSERVATION client=つばさ文具 satisfaction=30 company_level=", game.company_level().level, " same_client_available=", ordinary.map(func(offer): return str(offer.case_id)), " pipeline=", game.company_cycle_view().get("relationship_recovery", []))
	check(game.state.offers.any(func(offer): return bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false))), "low relationship never removes ordinary company-wide work")
	var repaired := 0
	for attempt in 4:
		if str(game.state.company_cycle.leads["つばさ文具"].status) != "paused": break
		check(game.end_day(), "advance real day to seek ordinary relationship recovery")
		var available: Array = game.state.offers.filter(func(offer): return str(offer.get("client", "")) == "つばさ文具" and str(offer.get("case_id", "")) in ["service-0-case-0", "service-5-case-1"] and str(offer.get("id", "")) not in game.state.completed_ids and bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false)))
		print("RECOVERY_DAY day=", game.state.day, " actual_available=", available.map(func(offer): return str(offer.case_id)))
		if available.is_empty(): continue
		var offer: Dictionary = available[0]
		check(game.choose_contract(str(offer.id)), "paused referral does not prevent ordinary same-customer re-engagement")
		if not game.state.accepted: continue
		game.inspect_mission(); game.vm_run("ssh client")
		var path := str(game.vm_info().config_path)
		var text := str(game.vm_read(path))
		game.capture_baseline()
		if int(game.state.chapter) == 5:
			check(text.contains("expires=unlimited"), "ordinary recovery is a real authored sharing job, not free relationship credit")
			check(game.vm_write(path, text.replace("expires=unlimited", "expires=7d")), "repair ordinary recovery job through file API")
		else:
			check(str(game.vm_run("smbclient //client/share -U staff -c \"put /srv/data/orders.csv\"")).contains("DENIED"), "ordinary recovery is a real authored Samba failure")
			check(game.vm_write(path, "[global]\n    map to guest = Never\n[share]\n    path = /srv/share\n    available = yes\n    guest ok = no\n    valid users = staff\n    read only = yes\n    write list = staff\n"), "repair ordinary Samba through file API")
		game.vm_run("systemctl restart " + str(game.vm_info().service))
		measure()
		check(game.deliver(), "complete and bill real work to improve customer relation")
		check(str(game.state.last_receipt.rating) == "on_time", "relationship improvement uses actual on-time delivery")
		repaired += 1
	print("RECOVERY_RESULT real_reengagements=", repaired, " satisfaction=", game.state.customer_relations["つばさ文具"].satisfaction, " pipeline_status=", game.state.company_cycle.leads["つばさ文具"].status)
	check(repaired > 0 and int(game.state.customer_relations["つばさ文具"].satisfaction) > 30, "real ordinary work improves a low-trust relationship")
	# No contract promises full recovery in four idle days. Preserve the observed
	# boundary: progress remains paused until the actual required outcome occurs.
	if int(game.state.customer_relations["つばさ文具"].satisfaction) < 40:
		check(str(game.state.company_cycle.leads["つばさ文具"].status) == "paused", "waiting and partial recovery do not grant free trust or unpause the pipeline")
	var next := find_offer("service-4-case-2")
	print("RECOVERY_REMAINING next_case=", next.get("case_id", ""), " required_level=", next.get("required_level", 0), " required_skills=", next.get("required_skills", {}), " company_level=", game.company_level().level, " skills=", game.state.skills)
	var feedback: Array = game.company_cycle_view().get("relationship_recovery", [])
	if int(game.state.customer_relations["つばさ文具"].satisfaction) >= 40:
		# Successful paid jobs can restore trust within this window. The next
		# specialty must still require training after that real recovery.
		var opportunities: Array = game.company_cycle_view().get("opportunities", []).filter(func(item): return str(item.get("client", "")) == "つばさ文具")
		check(not opportunities.is_empty() and str(opportunities[0].get("status", "")) == "locked" and str(opportunities[0].get("locked_reason", "")).contains("事故対応スキル2"), "restored trust does not bypass the next consultation's required specialty")
	else:
		check(not feedback.is_empty() and str(feedback[0].get("status", "")) == "locked", "recovery accurately reports the next same-customer work is not yet eligible")
		if not feedback.is_empty():
			check(str(feedback[0].get("goal", "")).contains(str(next.get("title", ""))) and str(feedback[0].get("goal", "")).contains("事故対応スキル2"), "recovery names the authored next job and its real skill requirement")
			check(str(feedback[0].get("goal", "")).contains("ほかの依頼"), "recovery points honestly to preparation through other actual jobs")
	check(game.state.offers.any(func(offer): return str(offer.get("id", "")) not in game.state.completed_ids and bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false))), "other real eligible work remains for company growth while relationship recovery waits")

func malformed_save_boundaries() -> void:
	check(game.save_game(), "persist valid state before malformed-save fixtures")
	var original: Dictionary = game.state.duplicate(true)
	var bytes := FileAccess.get_file_as_string(save_file)
	for field in ["company_cycle", "earned_goals"]:
		game.state = original.duplicate(true)
		if field == "company_cycle": game.state.company_cycle = []
		else: game.state.company_cycle.earned_goals = []
		var bad_state := JSON.stringify(game.state)
		check(not game.save_game(), "malformed " + field + " returns save failure without exception")
		check(FileAccess.get_file_as_string(save_file) == bytes, "malformed " + field + " preserves exact existing save bytes")
		check(not FileAccess.file_exists(save_file + ".tmp"), "malformed " + field + " leaves no staged file")
		check(JSON.stringify(game.state) == bad_state, "malformed " + field + " is not silently reset")
	game.state = original
	check(game.save_game(), "restored valid state saves after malformed fixtures")

func finish() -> void:
	print("COMPANY_CYCLE_INTEGRATION_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " failures=", failures.size())
	print("QA_STORAGE ", save_file)
	quit(0 if failures.is_empty() else 1)
