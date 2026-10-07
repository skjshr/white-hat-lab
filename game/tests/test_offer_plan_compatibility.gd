extends "res://tests/test_pentest_portal_integration.gd"
## Plan compatibility and saved quote preservation at the public offer boundary.

func _offer(g: Node, case_id: String) -> Dictionary:
	for offer in g.state.get("offers", []):
		if str(offer.get("case_id", "")) == case_id: return offer
	return {}

func run() -> void:
	var g := new_game("operations")
	check(g.start_free_career(), "career offer board")
	g.state.market_leads = ["service-1-case-0", "advanced-portal"]
	g.state.market_day = int(g.state.day)
	g._make_offers()
	var care_offer := _offer(g, "service-1-case-0")
	var advanced_offer := _offer(g, "advanced-portal")
	check(not care_offer.is_empty() and bool(care_offer.get("market_available", false)), "ordinary care-supported offer is available")
	check(not advanced_offer.is_empty() and bool(advanced_offer.get("market_available", false)), "advanced offer is available")
	if care_offer.is_empty() or advanced_offer.is_empty():
		g.queue_free(); quit(1); return

	check(g.set_offer_plan("care"), "select care plan")
	var care_quote: Dictionary = g.contract_quote(care_offer)
	var care_offer_id := str(care_offer.id)
	var care_amount := int(care_quote.quoted_fee)
	check(str(care_quote.selected_plan) == "care" and str(care_quote.reason).is_empty(), "ordinary offer retains a valid care quote")
	check(g.set_offer_quote(care_offer_id, care_amount), "save ordinary care quote")
	check(g.choose_contract(care_offer_id), "accept ordinary care offer")
	check(str(g.state.contract_plan) == "care", "accepted ordinary contract keeps care plan")
	check(g.set_offer_plan("standard"), "change global default without rewriting old draft")
	check(str(g.contract_quote(care_offer).selected_plan) == "care", "saved ordinary draft plan outranks global default")
	check(g.set_offer_plan("standard", care_offer_id), "offer-specific standard selection overrides saved care draft")
	check(str(g.contract_quote(care_offer).selected_plan) == "standard", "offer-specific selection immediately changes quote plan")
	check(int(g.state.offer_quotes[care_offer_id].get("care", -1)) == care_amount, "changing the selected plan preserves the old care amount")
	check(g.set_offer_plan("care", care_offer_id), "offer-specific care selection restores care preview")
	check(str(g.contract_quote(care_offer).selected_plan) == "care", "restored explicit selection matches the original accepted care terms")
	check(g.set_offer_plan("care"), "restore previous global default")

	var advanced_id := str(advanced_offer.id)
	var before_preview := JSON.stringify(g.state)
	var advanced_quote: Dictionary = g.contract_quote(advanced_offer)
	check(str(advanced_quote.selected_plan) == "standard", "unsupported advanced care request falls back to standard")
	check(is_equal_approx(float(advanced_quote.budget), 90.0), "advanced quote uses standard work budget")
	check(str(g.offer_plan()) == "care" and JSON.stringify(g.state) == before_preview, "fallback preview leaves global selection and save state unchanged")
	check(int(g.state.offer_quotes[care_offer_id].get("care", -1)) == care_amount, "fallback preserves the saved ordinary care amount")
	check(str(g.contract_quote(care_offer).selected_plan) == "care", "ordinary saved offer still previews its care plan")
	var good_path := str(g.save_path)
	var bad_path := "user://missing-offer-plan-compat-%d-%d/state.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	g.save_path = bad_path
	var before_failed_selection := JSON.stringify(g.state)
	check(not g.set_offer_plan("priority", advanced_id), "per-offer selection rejects failed save")
	check(JSON.stringify(g.state) == before_failed_selection, "failed selection rolls back its plan map")
	g.save_path = good_path
	check(g.set_offer_plan("priority", advanced_id), "per-offer selection replaces old quote-plan preference")
	advanced_quote = g.contract_quote(advanced_offer)
	check(str(advanced_quote.selected_plan) == "priority" and is_equal_approx(float(advanced_quote.budget), 40.0), "changed selection immediately changes preview plan and deadline")
	check(str(g.offer_plan()) == "care", "per-offer selection leaves global default unchanged")
	check(g.save_game() and g.load_game(), "per-offer selection round trips in generic state save")
	advanced_offer = _offer(g, "advanced-portal")
	check(str(g.offer_plan_for(advanced_offer)) == "priority", "per-offer selection survives reload")
	check(g.set_offer_plan("standard", advanced_id), "switch advanced offer back to standard")
	advanced_quote = g.contract_quote(advanced_offer)
	check(str(advanced_quote.selected_plan) == "standard" and is_equal_approx(float(advanced_quote.budget), 90.0), "second selection change restores standard preview")
	check(g.set_offer_quote(advanced_id, int(advanced_quote.quoted_fee)), "save advanced standard quote")
	check(int(g.state.offer_quotes[advanced_id].get("standard", -1)) == int(advanced_quote.quoted_fee), "advanced amount is stored under its resolved plan")

	g.save_path = bad_path
	var before_failed_accept := JSON.stringify(g.state)
	check(not g.choose_contract(advanced_id), "advanced acceptance rejects failed save")
	check(JSON.stringify(g.state) == before_failed_accept, "failed acceptance rolls back without losing either plan or quote")
	g.save_path = good_path
	check(g.choose_contract(advanced_id), "advanced contract accepts with the same standard plan")
	check(str(g.state.contract_plan) == "standard" and str(g.state.work.get("plan", "")) == "standard", "accepted advanced contract fixes the previewed standard plan")
	check(str(g.state.contract_contexts[care_offer_id].get("contract_plan", "")) == "care", "existing accepted care contract remains unchanged")
	check(int(g.state.offer_quotes[care_offer_id].get("care", -1)) == care_amount, "accepted advanced offer does not alter saved care quote")
	check(failures.is_empty(), "offer plan compatibility assertions")
	g.queue_free()
	print("OFFER_PLAN_COMPATIBILITY_PASS" if failures.is_empty() else "OFFER_PLAN_COMPATIBILITY_FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
