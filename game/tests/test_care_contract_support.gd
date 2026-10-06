extends "res://tests/test_pentest_portal_integration.gd"
## Compatibility fixture reconstructs only an older accepted care contract.
## Investigation, evidence, retests, verification and delivery use real APIs.
const SUPPORT = preload("res://scripts/care_contract_support.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")

func legacy_portal(g: Node) -> void:
	check(g.start_free_career(), "legacy career")
	var offer := portal_offer(g)
	g.set_offer_plan("care")
	var old_quote: Dictionary = g.contract_quote(offer)
	g.set_offer_plan("standard")
	check(g.set_offer_quote(str(offer.id), int(old_quote.quoted_fee)) and g.choose_contract(str(offer.id)), "legacy base contract")
	# Schema reconstruction, not a way for current players to bypass eligibility.
	g.state.contract_plan = "care"; g.state.work.plan = "care"
	g.state.contract.agreed_budget = float(old_quote.budget)
	check(g._agree_care(str(offer.client)), "legacy pending reservation fixture")
	g._sync_contract_context()
	check(g.save_game(), "legacy accepted save")

func complete_portal(g: Node) -> void:
	var alice := str(request(g, {"method":"POST","path":"/api/auth/login","body":{"username":"alice","password":"Alice-demo-27"}}, 200, "alice").response.data.session)
	var beth := str(request(g, {"method":"POST","path":"/api/auth/login","body":{"username":"beth","password":"Beth-demo-27"}}, 200, "beth").response.data.session)
	var normal_request := {"method":"GET","path":"/api/invoices/INV-N204","session":alice}
	var normal := pin(g, request(g, normal_request, 200, "normal evidence"))
	var job: Dictionary = request(g, {"method":"POST","path":"/api/exports","session":beth,"body":{"invoice_id":"INV-S108"}}, 202, "export").response.data
	request(g, {"method":"GET","path":job.status_url,"session":beth}, 202, "processing")
	request(g, {"method":"GET","path":job.status_url,"session":beth}, 200, "ready")
	var attack_request := {"method":"GET","path":job.download_url,"session":alice}
	var attack := pin(g, request(g, attack_request, 200, "cross tenant evidence"))
	check(bool(g.advanced_action("submit_report", {"claim":"authenticated_cross_tenant_read","evidence_ids":[normal,attack],"narrative":"許可範囲と応答を比較した。"}).ok), "report")
	check(bool(g.advanced_action("customer_fix").ok), "customer fix")
	pin(g, request(g, attack_request, 403, "same attack denied"))
	pin(g, request(g, normal_request, 200, "normal still works"))
	check(g.verify().all(func(row): return bool(row.passed)), "real acceptance checks")

func terms_mark(g: Node) -> Dictionary:
	return {"advanced":g.state.advanced.duplicate(true),"checks":g.state.checks.duplicate(true),"revision":g.state.revision,"validated_revision":g.state.validated_revision,"fee":g.state.contract.agreed_fee,"budget":g.state.contract.agreed_budget,"cash":g.state.cash,"minutes":g.state.work.minutes,"started_at":g.state.work.started_at,"started_day":g.state.work.started_day}

func run() -> void:
	check("--qa-profile=care-support" in OS.get_cmdline_user_args(), "isolated storage")
	var g := new_game("operations")
	check(g.start_free_career() and g.set_offer_plan("care"), "care board")
	for id in SUPPORT.UNSUPPORTED:
		var definition: Dictionary = CATALOG.by_id(id)
		check(not definition.is_empty() and not g.care_case_reason(definition).is_empty(), id + " unsupported case reason")
		var offer: Dictionary = {}
		for candidate in g.state.offers:
			if str(candidate.get("case_id", ""))==id: offer=candidate;break
		if bool(definition.get("saas_watch_only", false)):
			check(offer.is_empty(), id + " requires a previous delivery and is absent from the initial market")
			# Quote the catalog scope without fabricating an earned alert or
			# inserting an offer. Catalog targets are specs, quote targets a count.
			var scope: Dictionary = definition.duplicate(true)
			scope.case_id = id
			scope.target_specs = definition.get("targets", []).duplicate(true)
			scope.targets = scope.target_specs.size()
			var quote: Dictionary = g.contract_quote(scope, 0)
			check(str(quote.selected_plan) == "care" and str(quote.reason) == SUPPORT.REASON, id + " quote explicitly rejects unsupported care even within budget")
		else:
			check(not offer.is_empty() and not str(g.contract_quote(offer).reason).is_empty(), id + " quote explains exclusion")
	var before := JSON.stringify(g.state)
	check(not g.choose_contract(str(portal_offer(g).id)), "new unsupported care rejected")
	check(JSON.stringify(g.state)==before, "rejected care creates no reservation or decline")
	check(g.care_case_reason(CATALOG.by_id("service-1-case-0")).is_empty(), "normal backup care stays supported")
	check(not g.care_case_reason({"case_id":"composite", "target_specs":[{"case_id":"service-1-case-0"},{"case_id":"advanced-api"}]}).is_empty(), "mixed scope with unsupported engine rejected")
	g.queue_free()
	g = new_game("operations"); legacy_portal(g)
	check(str(GUIDE.resolve(g).target)=="CareConvertStandard", "legacy guide points to explicit contract action")
	complete_portal(g)
	check(not g.can_deliver() and not g.deliver(), "legacy unsupported promise is visibly blocked")
	var old := g; g=resume(old); old.queue_free()
	var mark := terms_mark(g)
	var proposal: Dictionary = g.care_conversion_offer()
	check(bool(proposal.available) and bool(proposal.cancel_pending), "loaded legacy reservation is recoverable")
	var path := str(g.save_path); before=JSON.stringify(g.state)
	g.save_path="user://missing-care-conversion-%s/state.json" % OS.get_process_id()
	check(not g.convert_current_care_to_standard(), "save failure rejects conversion")
	check(JSON.stringify(g.state)==before, "save failure preserves promise, terms and proof")
	g.save_path=path
	check(g.convert_current_care_to_standard(), "explicit conversion")
	check(terms_mark(g)==mark, "agreed fee deadline and all investigation evidence preserved")
	check(str(g.state.contract_plan)=="standard" and str(g.state.work.plan)=="standard" and str(g.state.contract_contexts[str(g.state.current_contract_id)].contract_plan)=="standard", "current and saved context agree")
	check(not g.state.care_agreements.has(str(proposal.client)), "only unsupported reservation removed")
	check(g.can_deliver(), "actual verified legacy work now delivers")
	before=JSON.stringify(g.state)
	check(not g.convert_current_care_to_standard() and JSON.stringify(g.state)==before, "repeat conversion is read only")
	old=g;g=resume(old);old.queue_free()
	check(not bool(g.care_conversion_offer().available) and g.can_deliver(), "conversion survives reload")
	check(g.deliver(), "converted delivery succeeds")
	check(int(g.completion_receipt().get("agreed_fee", -1))==int(mark.fee), "invoice retains agreed single fee")
	g.queue_free()
	# Pre-agreed-fields schema: load it and preserve the actual former terms,
	# not the standard plan's fallback price/deadline.
	g=new_game("operations");legacy_portal(g);complete_portal(g)
	g.state.contract.erase("agreed_fee");g.state.contract.erase("agreed_budget")
	g._sync_contract_context();check(g.save_game() and g.load_game(), "old missing-term schema reload")
	var effective: Dictionary=g.work_status()
	var fallback: Dictionary=g.care_conversion_offer()
	check(int(fallback.fee)==int(effective.estimated_fee) and float(fallback.budget)==float(effective.budget), "proposal displays effective legacy terms")
	check(g.convert_current_care_to_standard(), "missing-term conversion")
	check(int(g.work_status().estimated_fee)==int(effective.estimated_fee) and float(g.work_status().budget)==float(effective.budget), "conversion locks old effective terms")
	check(g.save_game() and g.load_game() and g.deliver(), "missing-term conversion reload and real delivery")
	check(int(g.completion_receipt().agreed_fee)==int(effective.estimated_fee), "missing-term invoice preserves one-off fee")
	g.queue_free()
	g=new_game("operations");legacy_portal(g)
	g.state.contract.agreed_fee=0;g.state.contract.agreed_budget=0.0
	check(int(g.care_conversion_offer().fee)==0 and float(g.care_conversion_offer().budget)==0.0, "explicit zero terms are not replaced by defaults")
	check(g.convert_current_care_to_standard() and int(g.state.contract.agreed_fee)==0 and float(g.state.contract.agreed_budget)==0.0, "explicit zero terms survive conversion")
	g.queue_free()
	# Isolated protection fixtures: one initialized VM, another pending reservation,
	# or an active legacy agreement. These are not earned-care/economy claims.
	for protect in ["targets", "other-pending", "active-legacy"]:
		g=new_game("operations");legacy_portal(g)
		var client:=str(g.state.contract.client)
		if protect=="targets":
			var vm=load("res://scripts/virtual_machine.gd").new();vm.setup(1,{},CATALOG.by_id("service-1-case-0"))
			g.state.maintenance_targets[client]=[{"asset_id":"service-1/site-0","chapter":1,"vm_state":vm.export_state()}]
		elif protect=="other-pending":
			g.state.contract_contexts["another-care"]={"completed":false,"accepted":true,"contract_plan":"care","contract":{"client":client,"case_id":"service-1-case-0"}}
		else:g.state.care_agreements[client].active=true
		var agreement: Dictionary=g.state.care_agreements[client].duplicate(true)
		var targets: Dictionary=g.state.maintenance_targets.duplicate(true)
		check(g.convert_current_care_to_standard(),protect+" conversion")
		check(g.state.care_agreements[client]==agreement and g.state.maintenance_targets==targets,protect+" unrelated maintenance survives")
		g.queue_free()
	print("CARE_CONTRACT_SUPPORT_PASS" if failures.is_empty() else "CARE_CONTRACT_SUPPORT_FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
