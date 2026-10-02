extends RefCounted
## Reconstructed maintenance-scope migration fixture, NOT a historical save.
## Source contract: maintenance_scope.gd::migrate and Game.load_game.
## Healthy VMs and completed care receipts are generated through real APIs;
## only the documented older lost-scope representation is then reconstructed.

static func build(g) -> Dictionary:
	if not str(g.save_path).begins_with("user://qa-"): return {"ok":false,"error":"isolated QA storage required"}
	g.set_process(false)
	if not g.new_game() or not g.choose_strategy("advisory"): return {"ok":false,"error":"new career"}
	# Company resources/workplace are fixture inputs, not migrated outcomes.
	g.state.cash=100000;g.state.peak_profit=200000;g.state.skills={"advisory":3,"operations":3,"response":3}
	g.state.equipment=["teamdesk"]
	if not g.start_free_career() or not g.hire_staff("sora"): return {"ok":false,"error":"staffed career"}
	if not g.set_offer_plan("care"): return {"ok":false,"error":"care terms"}
	var client:=""
	for case_id in ["service-1-case-0","service-0-case-1"]:
		g.state.market_leads=[case_id];g.state.market_day=int(g.state.day);g._make_offers()
		var offer_id:=""
		for offer in g.state.offers:
			if str(offer.get("case_id",""))==case_id and bool(offer.get("market_available",false)) and bool(offer.get("unlocked",false)):
				offer_id=str(offer.id)
				if client.is_empty():client=str(offer.client)
				elif client!=str(offer.client):return {"ok":false,"error":"fixture requires same customer"}
				break
		if offer_id.is_empty() or not g.choose_contract(offer_id):return {"ok":false,"error":"accept "+case_id}
		if not _solve(g) or not g.deliver():return {"ok":false,"error":"verified delivery "+case_id}
	if not g.save_game():return {"ok":false,"error":"persist generated deliveries"}
	var legacy: Dictionary=JSON.parse_string(JSON.stringify(g.state))
	var latest: Array=[]
	for target in legacy.maintenance_targets.get(client,[]):
		if int(target.get("chapter",-1))==0:latest.append(target.duplicate(true))
	if latest.size()!=1 or legacy.maintenance_targets[client].size()!=2:return {"ok":false,"error":"two distinct recorded services required"}
	# Before scope-v2, a later delivery replaced the current retained list. The
	# older contract_context and its vm_states survived, enabling loader recovery.
	legacy.erase("maintenance_scope_version")
	legacy.maintenance_targets[client]=latest
	for job in legacy.maintenance_jobs:
		if str(job.get("client",""))==client:job.targets=latest.duplicate(true)
	return {"ok":true,"state":legacy,"client":client}

static func load_into(g, state: Dictionary) -> bool:
	if not str(g.save_path).begins_with("user://qa-") or state.is_empty():return false
	var file:=FileAccess.open(str(g.save_path),FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(state));file.close()
	var loaded: bool=g.load_game()
	g.set_process(false)
	return loaded and str(g.last_load_error).is_empty()

static func _solve(g) -> bool:
	g.inspect_mission()
	if not bool(g.state.inspected):return false
	for index in g.state.targets.size():
		if not g.select_target(index):return false
		g.vm_run("ssh client")
		var scenario: Dictionary=g._scenario()
		if not g.vm_write(str(g.vm_info().config_path),g._vm().configuration_text(scenario.desired)):return false
		g.vm_run("systemctl restart "+str(g.vm_info().service))
		if int(g._current_chapter())==1:
			g.vm_run("restic backup /srv/data");g.vm_run("restic restore latest --target /restore")
		for _round in 3:
			for probe in g.diagnostic_probes():g.run_diagnostic(str(probe.id))
		g.verify()
	return bool(g.can_deliver())
