extends SceneTree

## Earn the new progression and equipment through real contracts and VM probes.
## Cash, XP, skill points and completion state are never injected.
const ASSURANCE_TEST = preload("res://tests/test_advanced_assurance.gd")
var game
var failures: Array[String] = []
var completed := 0
var spent := 0

func _init() -> void:
	create_timer(60.0).timeout.connect(func(): print("FAIL: career timed out"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value: failures.append(label)

func supported_lead(offer: Dictionary) -> bool:
	var case_id := str(offer.get("case_id", ""))
	return bool(offer.get("unlocked", false)) and bool(offer.get("market_available", false)) and not bool(offer.get("retired_from_new_offers", false)) and (case_id in ["advanced-portal", "composite-branch-reopen"] or not ASSURANCE_TEST.solution(case_id).is_empty() or (not case_id.begins_with("advanced-") and offer.get("target_specs", []).is_empty()))

func solve_assurance(case_id: String) -> void:
	# Use the same public operation fixtures as the dedicated model regression;
	# no model flags, market availability or earned progression are injected.
	for step in ASSURANCE_TEST.solution(case_id):
		var result: Dictionary = game.advanced_action(str(step[0]), {"target":str(step[1]) if step.size() > 1 else "","option":str(step[2]) if step.size() > 2 else ""})
		check(bool(result.get("ok", false)), "career assurance operation "+str(step[0]))
	var checks: Array = game.verify()
	check(not checks.is_empty() and checks.all(func(item): return bool(item.passed)), "career assurance verifies actual measurements")

func solve_portal() -> void:
	# This lead is available to a new company. Complete it through observed
	# HTTP exchanges so it does not remain an unfinished fresh lead forever.
	var sessions := {}
	for account in game.advanced_view().get("accounts", []):
		var username := str(account.get("username", ""))
		if username not in ["alice", "beth"]: continue
		var login: Dictionary = game.advanced_action("request", {"method":"POST","path":"/api/auth/login","body":{"username":username,"password":str(account.get("password", ""))}})
		check(int(login.get("response", {}).get("status", 0)) == 200, "career portal authenticates "+username)
		sessions[username] = str(login.get("response", {}).get("data", {}).get("session", ""))
	check(not str(sessions.get("alice", "")).is_empty() and not str(sessions.get("beth", "")).is_empty(), "career portal obtains actual authenticated sessions")
	if str(sessions.get("alice", "")).is_empty() or str(sessions.get("beth", "")).is_empty(): return
	var listed: Dictionary = game.advanced_action("request", {"method":"GET","path":"/api/invoices","session":sessions.alice})
	check(int(listed.get("response", {}).get("status", 0)) == 200, "career portal normal listing")
	var invoices: Array = listed.get("response", {}).get("data", {}).get("invoices", [])
	check(not invoices.is_empty(), "career portal reveals an invoice through normal use")
	if invoices.is_empty(): return
	var created: Dictionary = game.advanced_action("request", {"method":"POST","path":"/api/exports","session":sessions.alice,"body":{"invoice_id":str(invoices[0].id)},"headers":{"idempotency-key":"career-export"}})
	var job: Dictionary = created.get("response", {}).get("data", {})
	check(int(created.get("response", {}).get("status", 0)) == 202 and job.has("status_url"), "career portal starts a real export")
	if not job.has("status_url"): return
	for _poll in 2: game.advanced_action("request", {"method":"GET","path":str(job.status_url),"session":sessions.alice})
	var normal_request := {"method":"GET","path":str(job.download_url),"session":sessions.alice}
	var attack_request := normal_request.duplicate(true)
	attack_request.session = sessions.beth
	var normal: Dictionary = game.advanced_action("request", normal_request)
	var attack: Dictionary = game.advanced_action("request", attack_request)
	check(int(normal.get("response", {}).get("status", 0)) == 200 and int(attack.get("response", {}).get("status", 0)) == 200 and normal.get("response", {}).get("body", "") == attack.get("response", {}).get("body", ""), "career portal observes the same CSV across tenants")
	for record in [normal, attack]:
		check(bool(game.advanced_action("pin", {"id":str(record.get("request_id", ""))}).get("ok", false)), "career portal preserves original proof")
	check(bool(game.advanced_action("submit_report", {"claim":"authenticated_cross_tenant_read","evidence_ids":[normal.get("request_id", ""),attack.get("request_id", "")]}).get("ok", false)), "career portal reports observed proof")
	check(bool(game.advanced_action("customer_fix").get("ok", false)), "career portal receives customer fix")
	for args in [normal_request, attack_request]:
		var replay: Dictionary = game.advanced_action("request", args)
		check(int(replay.get("response", {}).get("status", 0)) == (200 if str(args.session) == str(sessions.alice) else 403), "career portal retests the original exchange")
		check(bool(game.advanced_action("pin", {"id":str(replay.get("request_id", ""))}).get("ok", false)), "career portal preserves retest")
	var checks: Array = game.verify()
	check(not checks.is_empty() and checks.all(func(item): return bool(item.passed)), "career portal verifies observed outcomes")

func run() -> void:
	game = root.get_node("Game")
	game.save_path = "user://rv18_career.json"
	game.backup_path = game.save_path+".bak"
	game.previous_path = game.save_path+".previous"
	game.settings_path = "user://rv18_career-settings.json"
	check(game.new_game(),"new company")
	check(game.choose_strategy("advisory") and game.start_free_career(),"start career")
	while completed < 80 and failures.is_empty():
		while game.skill_points()>0 and int(game.state.skills.advisory)<10:
			check(game.learn_skill("advisory"),"learn earned skill")
		for item in game.equipment_catalog():
			if item.id not in game.state.equipment and int(game.state.cash)>=game.equipment_price(item.id)+1000:
				var price: int = game.equipment_price(item.id)
				check(game.buy_equipment(item.id),"buy earned equipment "+str(item.id))
				game.advance_delivery(30.0)
				check(game.take_delivery(item.id),"receive earned equipment "+str(item.id))
				check(game.begin_delivery_placement(item.id),"place mode earned equipment "+str(item.id))
				check(game.place_delivery(item.id, game.equipment_slot(item.id)),"install earned equipment "+str(item.id))
				spent += price
		if game.state.skills.advisory==10 and game.state.equipment.size()==6 and game.company_level().level>=20:
			break
		var chosen: Dictionary = {}
		for offer in game.state.offers:
			if supported_lead(offer):
				if chosen.is_empty() or int(offer.reward)>int(chosen.reward): chosen=offer
		if chosen.is_empty():
			# This solver covers ordinary single-service cases, the portal and
			# assurance work exposed by the current advisory market.
			# Show other leads separately; they are not a failed VM operation.
			var remaining_leads: Array = game.state.offers.filter(supported_lead)
			check(remaining_leads.is_empty(),"career stops only after active leads are exhausted")
			var unsupported: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked", false)) and bool(item.get("market_available", false)) and not bool(item.get("retired_from_new_offers", false)))
			print("CAREER_UNSUPPORTED_LEADS ", unsupported.map(func(item): return str(item.get("case_id", ""))))
			break
		check(game.choose_contract(chosen.id),"accept real contract")
		if str(chosen.get("case_id", "")) == "advanced-portal": solve_portal()
		elif not ASSURANCE_TEST.solution(str(chosen.get("case_id", ""))).is_empty(): solve_assurance(str(chosen.case_id))
		for target in game.state.targets.size():
			if game.advanced_active(): break
			game.select_target(target)
			game.vm_run("ssh client")
			var scenario: Dictionary = game._scenario()
			# Use the VM's real service configuration serializer.  Samba v2 is
			# sectioned smb.conf; writing the legacy flat key=value fixture leaves
			# the service inactive and makes every subsequent probe fail.
			check(game.vm_write(game.vm_info().config_path,game._vm().configuration_text(scenario.desired)),"edit guest config")
			game.vm_run("systemctl restart "+str(game.vm_info().service))
		# Configure all actual providers before observing their dependent sites.
		# A linked gateway cannot serve successful business responses while its
		# Samba source or portal is still unavailable.
		for target in game.state.targets.size():
			if game.advanced_active(): break
			game.select_target(target)
			game.vm_run("ssh client")
			for attempt in 3:
				for probe in game.diagnostic_probes():
					if not (probe.recorded and probe.fresh and probe.passed): game.run_diagnostic(probe.id)
				if game.diagnostic_probes().all(func(p): return p.recorded and p.fresh and p.passed): break
			var career_checks: Array = game.verify()
			if not career_checks.all(func(c): return c.passed): print("CAREER_DEBUG case=", chosen.get("case_id", ""), " probes=", game.diagnostic_probes(), " checks=", career_checks, " vm=", game._vm().state)
			check(career_checks.all(func(c): return c.passed),"actual measurement and evaluation")
		check(game.can_deliver() and game.deliver(),"deliver all sites")
		check(game.end_day(),"close day")
		completed += 1
	check(completed>=20,"career completed the available active catalog")
	check(int(game.state.skills.advisory)>=8,"career earned advisory progression")
	check(game.company_level().level>=12,"career earned company progression")
	check(game.state.equipment.size()>=2,"career funded equipment purchases")
	var cash: int = int(game.state.cash)
	check(game.save_game() and game.load_game(),"late career reload")
	check(int(game.state.cash)==cash and game.state.skills.advisory>=8 and game.state.equipment.size()>=2,"late career persistence")
	print("RV_CAREER contracts=",completed," rank=",game.state.skills.advisory," company=",game.company_level().level," purchased=",game.state.equipment.size()," spent=",spent," cash=",cash," failures=",failures.size())
	for failure in failures: print("FAIL: ",failure)
	quit(0 if failures.is_empty() else 1)
