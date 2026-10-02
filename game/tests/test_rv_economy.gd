extends SceneTree

## Focused regression coverage for the day clock, deadline accounting, skills,
## and persistent economy. It uses public Game APIs wherever possible.
var game: Node
var failures: Array[String] = []

func _init() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	var qa_id := str(OS.get_process_id())
	game.save_path = "user://rv-economy-"+qa_id+".json"
	game.backup_path = "user://rv-economy-"+qa_id+".json.bak"
	game.previous_path = "user://rv-economy-"+qa_id+".previous.json"
	game.settings_path = "user://rv-economy-"+qa_id+"-settings.json"
	game._reset_state()
	_assert(game.choose_strategy("advisory"), "専門分野を開始")
	_assert(game.clock_minutes() == 540 and game.business_clock() == "09:00", "営業開始は09:00")
	_assert(game.accept_mission(), "案件を受注")
	var start_work: Dictionary = game.work_status()
	_assert(game.clock_minutes() == 540 and start_work.elapsed_minutes == 0, "受注直後の経過時間")
	var before_minutes := float(game.state.work.minutes)
	_assert(game.advance_office_time(4.0), "オフィス移動時間を加算")
	_assert(game.clock_minutes() == 544 and float(game.state.work.minutes) == before_minutes, "移動は時計だけを進める")
	_assert(game.vm_run("help") != "", "作業コマンドを実行")
	_assert(game.clock_minutes() == 545 and game.work_status().elapsed_minutes == 5, "作業時間と時計が一致")

	var catalog: Array = game.equipment_catalog()
	_assert(catalog.size() == 8, "設備カタログ8件")
	game.state.cash = 100000
	for item in catalog:
		if str(item.id) in ["annexdesk_a", "annexdesk_b"]: continue
		_assert(game.buy_equipment(str(item.id)), "設備を購入: "+str(item.id))
		game.advance_delivery(30.0)
		_assert(game.take_delivery(str(item.id)), "配送箱を受取: "+str(item.id))
		_assert(game.begin_delivery_placement(str(item.id)), "設置モード: "+str(item.id))
		_assert(game.place_delivery(str(item.id), game.equipment_slot(str(item.id))), "設備を設置: "+str(item.id))
	_assert(game.state.equipment.size() == 6, "6設備が所有状態に反映")
	# Annex desks require the career-only room order to complete on the next day.
	var annex_game: Node = load("res://scripts/game.gd").new()
	root.add_child(annex_game)
	var annex_id := str(OS.get_process_id())
	annex_game.save_path = "user://rv-annex-"+annex_id+".json"
	annex_game.backup_path = "user://rv-annex-"+annex_id+".json.bak"
	annex_game.previous_path = "user://rv-annex-"+annex_id+".previous.json"
	annex_game.settings_path = "user://rv-annex-"+annex_id+"-settings.json"
	annex_game._reset_state()
	_assert(annex_game.choose_strategy("advisory") and annex_game.start_free_career(), "annex career start")
	annex_game.state.cash = 100000
	_assert(annex_game.buy_office_expansion(), "annex expansion order")
	_assert(annex_game.end_day(), "annex next business day")
	_assert(annex_game.office_expanded(), "annex expansion completed")
	for annex_item in ["annexdesk_a", "annexdesk_b"]:
		_assert(annex_game.buy_equipment(annex_item), "annex equipment purchase: "+annex_item)
		annex_game.advance_delivery(30.0)
		_assert(annex_game.take_delivery(annex_item), "annex delivery receipt: "+annex_item)
		_assert(annex_game.begin_delivery_placement(annex_item), "annex placement mode: "+annex_item)
		_assert(annex_game.place_delivery(annex_item, annex_game.equipment_slot(annex_item)), "annex equipment install: "+annex_item)
	_assert(annex_game.state.equipment.size() == 2 and annex_game.contract_capacity() == 5, "annex capacity")
	_assert(game.action_minutes("edit", 8.0) == 6.0, "ワークステーションの編集短縮")
	_assert(game.action_minutes("diagnostic", 6.0) == 4.0, "診断コンソールの検証短縮")
	_assert(game.team_work_duration("aya") == 4.0, "チームデスクを含む作業短縮")

	var config_path := str(game.vm_info().config_path)
	_assert(game.vm_run("ssh client") != "", "顧客VMへ接続")
	config_path = str(game.vm_info().config_path)
	var desired_text := ""
	for field in game.mission().fields: desired_text += str(field.id)+"="+str(field.options[int(field.desired)])+"\n"
	var before_edit := float(game.state.work.minutes)
	_assert(game.vm_write(config_path, desired_text), "実VM設定を書き込み")
	_assert(float(game.state.work.minutes) - before_edit == 6.0, "設備購入後の実編集時間")
	var probes: Array = game.diagnostic_probes()
	if not probes.is_empty():
		var before_measure := float(game.state.work.minutes)
		game.run_diagnostic(str(probes[0].id))
		_assert(float(game.state.work.minutes) - before_measure == 2.0, "設備購入後の実測定時間")
	var before_verify := float(game.state.work.minutes)
	game.verify()
	_assert(float(game.state.work.minutes) - before_verify == 4.0, "設備購入後の実検証時間")
	var before_team := float(game.state.work.minutes)
	game.assign_colleague("aya")
	var paused_remaining := float(game.state.assignments.aya.remaining)
	game.set_office_clock_paused(true)
	game._process(5.0)
	_assert(is_equal_approx(float(game.state.assignments.aya.remaining), paused_remaining), "一時停止中は同僚の時計を進めない")
	game.set_office_clock_paused(false)
	game._process(5.0)
	_assert(float(game.state.work.minutes) - before_team == 4.0, "設備購入後の実チーム作業時間")
	var expected_clock: int = game.clock_minutes()
	_assert(game.work_status().deadline_text == "10:30", "納期表示")
	_assert(game.work_status().remaining > 0, "納期までの残り時間")

	var skills: Array = game.skill_catalog()
	_assert(skills.all(func(skill): return int(skill.max_rank) == 10 and skill.nodes.size() == 10), "各専門分野は10段階")
	game.state.credit = 8200
	game.state.profit = 820000
	game._update_growth()
	_assert(game.skill_points() >= 30, "長期成長で30以上の習得ポイント")
	_assert(game.skill_effect("advisory", 10) == "診断案件の報酬 +105%", "診断Lv10効果")
	_assert(game.skill_effect("response", 10) == "対応案件の報酬 +155%", "対応Lv10効果")
	_assert(game.skill_effect("operations", 10) == "新規保守契約 ¥6150/日（契約時固定）・枠 +10", "運用Lv10効果")
	while int(game.state.skills.advisory) < 10:
		_assert(game.learn_skill("advisory"), "APIでスキルを習得")
	_assert(int(game.state.skills.advisory) == 10, "API習得でLv10到達")
	var expected_equipment: Array = game.state.equipment.duplicate(true)
	var expected_cash := int(game.state.cash)
	var original_save_path: String = game.save_path
	var original_backup_path: String = game.backup_path
	game.state.equipment.erase("plant")
	game.state.delivery_orders = game.state.delivery_orders.filter(func(order): return str(order.get("id", "")) != "plant")
	game.save_path = "user://missing-parent-rv-economy/save.json"
	game.backup_path = "user://missing-parent-rv-economy/save.json.bak"
	var failed_purchase: bool = game.buy_equipment("plant")
	_assert(not failed_purchase, "保存失敗時の購入拒否")
	_assert(int(game.state.cash) == expected_cash and "plant" not in game.state.equipment, "保存失敗時の残高・設備ロールバック")
	game.state.equipment = expected_equipment.duplicate(true)
	game.save_path = original_save_path
	game.backup_path = original_backup_path
	_assert(game.save_game(), "経済状態を保存")
	_assert(game.load_game(), "経済状態を再読込")
	_assert(int(game.state.skills.advisory) == 10 and game.state.equipment.size() == 6 and game.clock_minutes() == expected_clock, "保存再読込で時計・設備・スキルを保持")

	# Explicit care contracts: signing reserves a fixed fee, but billing starts only after delivery.
	game.state.strategy = "operations"
	game.state.contract_plan = "standard"
	game.state.skills.operations = 0
	game.state.equipment = []
	game.state.customer_relations = {}
	game.state.care_agreements = {}
	game.state.recurring_clients = []
	_assert(game.recurring_income() == 0, "通常契約は継続収入を作らない")
	_assert(game.care_eligibility("care-a").is_empty(), "新規保守契約は枠内")
	_assert(game._agree_care("care-a"), "保守契約を締結")
	_assert(game.care_portfolio().active_count == 0 and game.care_portfolio().gross_daily == 0 and int(game.care_portfolio().get("reserved_count", -1)) == 1, "締結直後は請求開始しない")
	_assert(int(game.state.care_agreements["care-a"].fee) == 150, "契約時料金を固定")
	_assert(game.care_terms("care-a").fee == 150 and game.care_terms("care-a").cost == 100 and game.care_terms("care-a").net == 50, "care terms match agreement")
	game.state.skills.operations = 5
	_assert(int(game.state.care_agreements["care-a"].fee) == 150, "スキル上昇で既存料金を変更しない")
	_assert(game.care_terms("care-a").fee == 150 and game.care_terms("new-care").fee == 3150, "care terms lock existing fee and quote new fee")
	game.state.skills.operations = 0
	_assert(game._agree_care("care-b"), "枠内の保守契約を締結")
	_assert(not game.care_eligibility("care-c").is_empty(), "保守契約枠を超えて締結できない")

	# Satisfaction suspension/reactivation and idempotent retainer settlement.
	game.state.customer_relations["care-a"] = {"satisfaction":35,"completed_count":1,"last_quality":"late","last_day":1}
	game._suspend_care("care-a")
	_assert(game.care_portfolio().active_count == 0 and game.state.recurring_clients.is_empty(), "低満足度で保守契約を停止")
	game.state.customer_relations["care-a"].satisfaction = 70
	game._activate_care("care-a")
	_assert(game.care_portfolio().active_count == 1 and "care-a" in game.state.recurring_clients, "満足度回復で保守契約を再開")
	game.state.day = 21; game.state.retainer_settled_day = -1; game.state.cash = 0; game.state.profit = 0; game.state.history = [{}]
	game._apply_retainer(); var settled_cash := int(game.state.cash); game._apply_retainer()
	_assert(settled_cash == 50 and int(game.state.cash) == settled_cash, "継続収入を同日に二重精算しない")
	var rollback_save_path: String = game.save_path
	var rollback_backup_path: String = game.backup_path
	var rollback_previous: Dictionary = game.state.duplicate(true)
	game.state.career_mode = true; game.state.current_contract_id = "rollback-contract"; game.state.completed_ids.append("rollback-contract"); game.state.day = 30; game.state.retainer_settled_day = 30
	game.save_path = "user://missing-parent-rv-economy-end/save.json"; game.backup_path = "user://missing-parent-rv-economy-end/save.json.bak"
	_assert(not game.end_day(), "終業の保存失敗を拒否")
	_assert(int(game.state.day) == 30 and int(game.state.cash) == int(rollback_previous.cash), "終業の保存失敗で状態を復元")
	game.save_path = rollback_save_path; game.backup_path = rollback_backup_path

	# End-to-end care lifecycle on the real VM APIs, reusing the same story client.
	var care_game: Node = load("res://scripts/game.gd").new()
	root.add_child(care_game)
	var test_id := str(OS.get_process_id())
	care_game.save_path = "user://rv-care-lifecycle-"+test_id+".json"
	care_game.backup_path = "user://rv-care-lifecycle-"+test_id+".json.bak"
	care_game.previous_path = "user://rv-care-lifecycle-"+test_id+".previous.json"
	care_game.settings_path = "user://rv-care-lifecycle-"+test_id+"-settings.json"
	care_game._reset_state()
	_assert(care_game.choose_strategy("advisory"), "care lifecycle strategy")
	_assert(care_game.set_contract_plan("care") and care_game.accept_mission(), "care lifecycle agreement")
	var care_client: String = str(care_game.mission().get("client", ""))
	_assert(_solve_public_case(care_game, false), "care delivery verification")
	var locked_fee: int = int(care_game.state.care_agreements[care_client].fee)
	_assert(care_game.deliver(), "care delivery succeeds")
	_assert(care_game.care_portfolio().active_count == 1 and int(care_game.care_portfolio().get("pending_count", -1)) == 0 and int(care_game.care_portfolio().get("reserved_count", -1)) == 1, "care delivery activates billing")
	_assert(care_game.care_eligibility(care_client).is_empty(), "active care renewal does not reserve another slot")
	care_game.state.customer_relations[care_client].satisfaction = 45

	# Chapter 5 uses the same authored client. A late standard job must suspend care.
	care_game.state.chapter = 5; care_game.state.accepted = false; care_game.state.contract_plan = "standard"; care_game.state.credit = 160
	_assert(care_game.accept_mission(), "standard late job for same client")
	_assert(_solve_public_case(care_game, true) and care_game.deliver(), "late standard delivery")
	_assert(int(care_game.state.customer_relations[care_client].satisfaction) == 30, "late job lowers satisfaction")
	_assert(care_game.care_portfolio().active_count == 0, "late standard job suspends care")

	# A good standard job raises 30 to 35; it remains suspended below 40.
	care_game.state.chapter = 0; care_game.state.accepted = false; care_game.state.contract_plan = "standard"; care_game.state.completed_ids = []
	_assert(care_game.accept_mission() and _solve_public_case(care_game, false) and care_game.deliver(), "standard recovery job")
	_assert(int(care_game.state.customer_relations[care_client].satisfaction) == 35 and care_game.care_portfolio().active_count == 0, "standard recovery does not reactivate care")
	care_game.state.accepted = false; care_game.state.contract_plan = "care"; care_game.state.completed_ids = []
	var suspended_snapshot: Dictionary = care_game.state.duplicate(true)
	_assert(not care_game.care_eligibility(care_client).is_empty() and not care_game.accept_mission(), "suspended care below threshold is rejected")
	_assert(not care_game.state.accepted and care_game.state.care_agreements[care_client] == suspended_snapshot.care_agreements[care_client], "rejected suspended care leaves state unchanged")
	care_game.state.customer_relations[care_client].satisfaction = 40
	care_game.state.accepted = false; care_game.state.contract_plan = "care"; care_game.state.completed_ids = []
	_assert(care_game.accept_mission(), "care renewal at capacity")
	_assert(int(care_game.state.care_agreements[care_client].fee) == locked_fee, "care renewal keeps agreed fee")
	_assert(_solve_public_case(care_game, false), "care renewal verification")
	var failed_cash: int = int(care_game.state.cash)
	var failed_completed: Array = care_game.state.completed_ids.duplicate(true)
	var failed_relation: Dictionary = care_game.state.customer_relations[care_client].duplicate(true)
	var care_save_path: String = care_game.save_path
	var care_backup_path: String = care_game.backup_path
	care_game.save_path = "user://missing-parent-rv-care-deliver/save.json"; care_game.backup_path = "user://missing-parent-rv-care-deliver/save.json.bak"
	_assert(not care_game.deliver(), "care delivery save failure")
	_assert(int(care_game.state.cash) == failed_cash and care_game.state.completed_ids == failed_completed and care_game.state.customer_relations[care_client] == failed_relation, "care delivery save failure rolls back")
	care_game.save_path = care_save_path; care_game.backup_path = care_backup_path
	_assert(care_game.deliver(), "care delivery retry succeeds")
	_assert(care_game.care_portfolio().active_count == 1 and int(care_game.state.customer_relations[care_client].satisfaction) == 45, "care delivery reactivates after successful retry")

	# Legacy migration: a zero placeholder is unpaid; a positive same-day retainer is settled.
	var migration_game: Node = load("res://scripts/game.gd").new(); root.add_child(migration_game)
	migration_game.save_path = "user://rv-care-migration-"+test_id+".json"; migration_game.backup_path = "user://rv-care-migration-"+test_id+".json.bak"; migration_game.previous_path = "user://rv-care-migration-"+test_id+".previous.json"; migration_game.settings_path = "user://rv-care-migration-"+test_id+"-settings.json"
	migration_game._reset_state(); migration_game.state.day = 1; migration_game.state.cash = 0; migration_game.state.customer_relations = {"legacy": {"satisfaction":70,"completed_count":1,"last_quality":"on_time","last_day":1}}; migration_game.state.care_agreements = {"legacy": {"fee":150,"active":true,"pending":false,"agreed_day":1,"grandfathered":true}}; migration_game.state.recurring_clients = ["legacy"]; migration_game.state.history = [{"day":1,"retainer":0}]
	_assert(migration_game.save_game(), "write legacy zero-retainer save")
	var legacy_zero: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(migration_game.save_path)); legacy_zero.erase("retainer_settled_day"); var legacy_file: FileAccess = FileAccess.open(migration_game.save_path, FileAccess.WRITE); legacy_file.store_string(JSON.stringify(legacy_zero)); legacy_file.close()
	_assert(migration_game.load_game(), "load legacy zero-retainer save"); migration_game._apply_retainer(); var zero_paid_cash := int(migration_game.state.cash); migration_game._apply_retainer(); _assert(zero_paid_cash == 50 and int(migration_game.state.cash) == zero_paid_cash, "legacy zero retainer settles once")
	migration_game.state.cash = 0; migration_game.state.history = [{"day":1,"retainer":50}]; migration_game.state.retainer_settled_day = -1; _assert(migration_game.save_game(), "write legacy paid-retainer save")
	var legacy_paid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(migration_game.save_path)); legacy_paid.erase("retainer_settled_day"); legacy_file = FileAccess.open(migration_game.save_path, FileAccess.WRITE); legacy_file.store_string(JSON.stringify(legacy_paid)); legacy_file.close()
	_assert(migration_game.load_game(), "load legacy paid-retainer save"); migration_game._apply_retainer(); _assert(int(migration_game.state.cash) == 0, "legacy paid retainer does not settle twice")

	# Quote parity: ordinary, multi-site, and composite offers use work_status' exact budget.
	var quote_game: Node = load("res://scripts/game.gd").new(); root.add_child(quote_game); quote_game.save_path = "user://rv-care-quotes-"+test_id+".json"; quote_game.backup_path = "user://rv-care-quotes-"+test_id+".json.bak"; quote_game.previous_path = "user://rv-care-quotes-"+test_id+".previous.json"; quote_game.settings_path = "user://rv-care-quotes-"+test_id+"-settings.json"
	for plan_id in ["standard", "priority", "care"]:
		_assert(_quote_matches_work_status(quote_game, plan_id, {"id":"quote-ordinary-"+plan_id,"case_id":"service-0-case-0","chapter":0,"targets":1,"target_specs":[],"reward":2400,"client":"quote-client","required_level":1,"required_rank":1,"required_credit":0,"unlocked":true}), "quote ordinary "+plan_id)
		_assert(_quote_matches_work_status(quote_game, plan_id, {"id":"quote-multi-"+plan_id,"case_id":"service-0-case-0","chapter":0,"targets":2,"target_specs":[],"reward":4800,"client":"quote-multi","required_level":1,"required_rank":1,"required_credit":0,"unlocked":true}), "quote multisite "+plan_id)
		_assert(_quote_matches_work_status(quote_game, plan_id, {"id":"quote-composite-"+plan_id,"case_id":"composite-branch-reopen","chapter":2,"targets":3,"target_specs":[{"chapter":0,"case_id":"service-0-case-0"},{"chapter":1,"case_id":"service-1-case-0"},{"chapter":5,"case_id":"service-5-case-0"}],"reward":16000,"client":"quote-composite","required_level":1,"required_rank":1,"required_credit":0,"unlocked":true}), "quote composite "+plan_id)

	# Editable quote: budget rejection, persisted revision, price reaction, and fee lock.
	var price_game: Node = load("res://scripts/game.gd").new(); root.add_child(price_game); price_game.save_path = "user://rv-price-"+test_id+".json"; price_game.backup_path = "user://rv-price-"+test_id+".json.bak"; price_game.previous_path = "user://rv-price-"+test_id+".previous.json"; price_game.settings_path = "user://rv-price-"+test_id+"-settings.json"
	price_game._reset_state(); _assert(price_game.choose_strategy("advisory"), "価格テストの専門分野"); _assert(price_game.start_free_career(), "価格テストのキャリア開始")
	var price_offer: Dictionary = {}
	for candidate in price_game.state.offers:
		if bool(candidate.get("unlocked", false)):
			price_offer = candidate; break
	var price_id := str(price_offer.get("id", ""))
	_assert(not price_id.is_empty(), "価格テストの実案件")
	var reference_fee: int = int(price_game.contract_quote(price_offer).reference_fee); var budget_limit: int = int(price_game.contract_quote(price_offer).budget_limit)
	var over_budget: int = budget_limit + 100
	_assert(price_game.set_offer_quote(price_id, over_budget), "set over-budget quote")
	_assert(price_game.load_game() and int(price_game.state.offer_quotes[price_id]["standard"]) == over_budget, "quote persists through load")
	var before_decline_cash: int = int(price_game.state.cash)
	_assert(not price_game.choose_contract(price_id) and price_game.state.awaiting_contract and int(price_game.state.cash) == before_decline_cash, "over-budget quote rejected without acceptance")
	var declined_count: int = price_game.state.quote_decisions.filter(func(entry): return str(entry.get("decision", "")) == "declined").size()
	_assert(not price_game.choose_contract(price_id) and price_game.state.quote_decisions.filter(func(entry): return str(entry.get("decision", "")) == "declined").size() == declined_count, "duplicate decline is idempotent")
	var discounted_fee: int = roundi(float(reference_fee) * 0.85)
	_assert(price_game.set_offer_quote(price_id, discounted_fee), "revise quote below reference")
	_assert(price_game.choose_contract(price_id), "revised quote accepted")
	price_game.state.skills.advisory = 10
	_assert(int(price_game.work_status().estimated_fee) == discounted_fee, "accepted fee remains locked after skill change")
	_assert(_solve_public_case(price_game, false) and price_game.deliver(), "discounted quote delivered")
	var price_receipt: Dictionary = price_game.completion_receipt()
	_assert(int(price_receipt.get("agreed_fee", -1)) == discounted_fee and int(price_receipt.get("reference_fee", -1)) == reference_fee and int(price_receipt.get("price_satisfaction_delta", -1)) == 3, "receipt records price reaction")
	var rollback_quotes: Dictionary = price_game.state.offer_quotes.duplicate(true); price_game.state.awaiting_contract = true; price_game.state.accepted = false; price_game.save_path = "user://missing-parent-rv-price/save.json"; price_game.backup_path = "user://missing-parent-rv-price/save.json.bak"
	_assert(not price_game.set_offer_quote(price_id, reference_fee), "quote save failure rejected")
	_assert(price_game.state.offer_quotes == rollback_quotes, "quote save failure rolls back")

	_maintenance_flow()
	_staffing_flow()
	for failure in failures: push_error("RV_ECONOMY: " + failure)
	print("PASS: RV economy clock/equipment/skills" if failures.is_empty() else "FAIL count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _assert(value: bool, label: String) -> void:
	if not value: failures.append(label)

func _staffing_flow() -> void:
	var g: Node = load("res://scripts/game.gd").new(); root.add_child(g); g.set_process(false)
	g.save_path = "user://rv-staff-"+str(OS.get_process_id())+".json"; g.backup_path=g.save_path+".bak"; g.previous_path=g.save_path+".previous"; g.settings_path=g.save_path+".settings"
	g._reset_state(); g.choose_strategy("operations"); _assert(g.start_free_career(),"staff career start")
	g.state.cash=20000
	_assert(g.staff_capacity()==0 and not g.hire_staff("mio"),"physical desk required")
	g.state.equipment=["teamdesk"]
	_assert(g.staff_capacity()==1 and g.staff_summary().count==0 and g.team_members().all(func(item): return not bool(item.hired)),"capacity excludes two original workers")
	_assert(g.colleague_result_path("aya")=="/home/operator/aya-inspection.txt" and g.colleague_result_path("ren")=="/home/operator/ren-verification.txt","old result paths retained")
	_staff_save_failure(g,func(): return g.hire_staff("mio","afternoon"),"hire")
	_assert(g.hire_staff("mio","afternoon"),"afternoon staff can be hired before arrival")
	_assert(not g.staff_availability("mio").is_empty() and int(g.staff_summary().due)==300,"hire records shift wage but blocks work before shift")
	_assert(g.team_members().any(func(item): return str(item.id)=="mio" and int(item.daily_wage)==300),"roster shows selected shift wage")
	_assert(not g.hire_staff("haru"),"occupied additional seat blocks another hire")
	_staff_save_failure(g,func(): return g.release_staff("mio"),"release")
	g.state.clock_minutes=780
	_assert(g.staff_availability("mio").is_empty(),"afternoon work available at start")
	g.state.clock_minutes=1068
	_assert(g.staff_availability("mio","maintenance").is_empty(),"twelve-minute maintenance fits shift boundary")
	g.state.clock_minutes=1069
	_assert(not g.staff_availability("mio","maintenance").is_empty() and g.staff_availability("mio").is_empty(),"maintenance uses twelve minutes, normal investigation uses equipment-adjusted six")
	_assert(g.release_staff("mio") and int(g.staff_summary().due)==300,"release preserves current wage")
	_assert(g.hire_staff("mio","afternoon") and int(g.staff_summary().due)==300,"same-day rehire cannot duplicate wage")
	_assert(g.state.staff_payroll.due.size()==1,"same-day worker wage has one obligation")
	_staff_save_failure(g,func(): return g.set_staff_shift("mio","morning"),"shift")
	_assert(g.set_staff_shift("mio","morning") and str(g.state.staff.mio.shift)=="afternoon" and int(g.staff_summary().due)==300,"shift change leaves current terms unchanged")
	var profit_before := int(g.state.profit); g.state.cash=100
	_staff_save_failure(g,func(): return g.end_day(),"payroll end day")
	_assert(g.end_day(),"public day settlement")
	_assert(int(g.state.profit)==profit_before-300 and int(g.state.cash)==0 and int(g.staff_summary().arrears)==200,"payroll expenses once and preserves partial debt")
	_assert(str(g.state.staff.mio.shift)=="morning" and str(g.state.staff.mio.pending_shift).is_empty() and int(g.staff_summary().due)==300,"next shift applies, pending clears, next wage exists")
	_assert(not g.staff_availability("mio").is_empty() and g.staff_availability("aya").is_empty(),"arrears block new workers without blocking original team")
	_assert(not g.pay_staff_arrears(),"zero-cash payment rejected")
	g.state.cash=100
	_staff_save_failure(g,func(): return g.pay_staff_arrears(),"arrears")
	var expensed_profit := int(g.state.profit)
	_assert(g.pay_staff_arrears() and int(g.staff_summary().arrears)==100 and int(g.state.cash)==0 and int(g.state.profit)==expensed_profit,"partial repayment preserves residual and does not re-expense")
	g.state.cash=500
	_assert(g.pay_staff_arrears() and int(g.staff_summary().arrears)==0 and int(g.state.cash)==400 and int(g.state.profit)==expensed_profit,"exact residual repayment restores work")
	_assert(g.staff_availability("mio").is_empty(),"paid employee can work again")
	_assert(g.release_staff("mio") and int(g.staff_summary().due)==300,"next-day release retains that day's obligation")
	_assert(g.end_day() and int(g.state.cash)==100 and int(g.state.profit)==expensed_profit-300,"second day costs exactly one salary")
	var ended_profit := int(g.state.profit)
	_assert(g.end_day() and int(g.state.profit)==ended_profit and int(g.staff_summary().due)==0,"inactive staff creates no future salary")
	g.state.cash=10000; _assert(g.hire_staff("sora"),"released seat accepts maintenance specialist")
	_assert(not g.staff_availability("sora").is_empty(),"maintenance specialist cannot do normal assignment")
	g.state.clock_minutes=1072
	_assert(g.staff_availability("sora","maintenance").is_empty(),"eight-minute specialist work fits")
	g.state.clock_minutes=1073
	_assert(not g.staff_availability("sora","maintenance").is_empty(),"specialist work cannot start past remaining shift")
	g.state.clock_minutes=1080; _assert(g.release_staff("sora") and not g.hire_staff("haru"),"hiring rejected after shift end")
	# A pre-staffing career save migrates without inventing historical wages.
	g.state.staff={}; g.state.staff_payroll={"enabled":false,"due":[],"last_settled_day":-1}
	g.state.erase("staff"); g.state.erase("staff_payroll"); _assert(g.save_game() and g.load_game(),"legacy career migration")
	_assert(g.team_members().size()==2 and g.staff_summary().due==0 and g.staff_summary().arrears==0,"migration leaves original staffing and finances unchanged")

func _staff_save_failure(g: Node, action: Callable, label: String) -> void:
	var before: Dictionary=g.state.duplicate(true); var assignments: Dictionary=g._assignments.duplicate(true)
	var good: String=g.save_path; g.save_path="user://missing-staff-rollback/save.json"
	_assert(not bool(action.call()),label+" rejects failed save")
	_assert(g.state==before and g._assignments==assignments,label+" restores all state on failed save")
	g.save_path=good

func _maintenance_flow() -> void:
	var g: Node = load("res://scripts/game.gd").new(); root.add_child(g)
	var id := str(OS.get_process_id())
	g.save_path = "user://rv-maint-"+id+".json"; g.backup_path = g.save_path+".bak"; g.previous_path = g.save_path+".previous"; g.settings_path = "user://rv-maint-"+id+"-settings.json"
	g._reset_state(); _assert(g.choose_strategy("operations") and g.set_contract_plan("care") and g.accept_mission(), "maintenance care acceptance")
	var client := str(g.mission().get("client", "")); _assert(_solve_public_case(g, false), "maintenance care real delivery verification")
	var before_vm: Dictionary = g.state.vm_states.duplicate(true); _assert(g.deliver(), "maintenance care delivery")
	_assert(g.state.maintenance_targets.has(client) and g.state.maintenance_jobs.size() == 1 and str(g.state.maintenance_jobs[0].status) == "done", "delivery stores verified maintenance target")
	var fee := int(g.state.maintenance_jobs[0].fee); var cash_before := int(g.state.cash); _assert(g.end_day(), "maintenance first day closes")
	_assert(g.maintenance_jobs().any(func(item): return str(item.client) == client and str(item.status) == "pending"), "next day maintenance pending")
	_assert(g.assign_maintenance(client, "aya"), "colleague maintenance assignment")
	_assert(not g.assign_maintenance(client, "ren"), "duplicate maintenance assignment rejected")
	g._process(12.5)
	var completed_job: Dictionary = g.maintenance_jobs().filter(func(item): return str(item.client) == client)[0]
	_assert(str(completed_job.status) == "done" and not g.maintenance_result(client).is_empty(), "maintenance completes with raw result")
	_assert(not g.run_maintenance(client), "completed maintenance cannot run twice")
	_assert(g.state.vm_states == before_vm, "maintenance leaves normal VM state unchanged")
	g._apply_retainer(); var settled_cash := int(g.state.cash)
	_assert(int(g.state.last_receipt.get("maintenance_earned", 0)) == fee and int(g.state.last_receipt.get("maintenance_cost", g.state.last_receipt.get("retainer_cost", 0))) >= 0, "completed maintenance settles fee")
	g._apply_retainer(); _assert(int(g.state.cash) == settled_cash, "maintenance settlement is idempotent")
	var saved_path: String = g.save_path; var saved_backup: String = g.backup_path; g.state.day += 1; g.state.retainer_settled_day = -1; g._prepare_maintenance_day(); var old_state: Dictionary = g.state.duplicate(true); g.save_path = "user://missing-maint-rollback/save.json"; g.backup_path = g.save_path+".bak"
	_assert(not g.run_maintenance(client), "maintenance save failure rejected"); _assert(g.state == old_state, "maintenance save failure rollback")
	g.save_path = saved_path; g.backup_path = saved_backup
	# An unhandled daily job earns no fee, still incurs service cost, and lowers satisfaction once.
	g.state.day += 1; g.state.retainer_settled_day = -1; g._prepare_maintenance_day(); var satisfaction_before := int(g.state.customer_relations[client].satisfaction)
	# Corrupt only the independent maintenance snapshot so the real inspection fails.
	var pending_index := -1
	for i in g.state.maintenance_jobs.size():
		if str(g.state.maintenance_jobs[i].get("client", "")) == client and int(g.state.maintenance_jobs[i].get("day", -1)) == int(g.state.day) and str(g.state.maintenance_jobs[i].get("status", "")) == "pending": pending_index = i; break
	_assert(pending_index >= 0, "failed maintenance pending job exists")
	if pending_index >= 0:
		g.state.maintenance_jobs[pending_index]["targets"][0]["vm_state"]["applied"]["staff"] = "none"
		g.state.maintenance_jobs[pending_index]["targets"][0]["vm_state"]["applied"]["shares"]["share"]["write list"] = ""
	_assert(g.run_maintenance(client), "failed maintenance job executes and records failure")
	_assert(str(g._maintenance_job_for(client).get("status", "")) == "failed" and g.maintenance_result(client).begins_with("FAIL"), "failed maintenance stores failed result")
	var prior_done := {"id":"maintenance-old-unpaid","client":client,"day":int(g.state.day)-1,"status":"done","fee":999,"cost":100,"paid":false}
	var receipt_before_settlement: Dictionary = g.state.last_receipt.duplicate(true)
	g.state.maintenance_jobs.append(prior_done); g.state.retainer_settled_day = -1; g._apply_retainer(); var failed_summary: Dictionary = g.maintenance_summary()
	_assert(int(g.state.customer_relations[client].satisfaction) == satisfaction_before - 8, "failed maintenance applies one daily satisfaction penalty")
	_assert(int(failed_summary.get("earned", 0)) == 0 and int(failed_summary.get("service_cost", 0)) >= 100 and int(failed_summary.get("net", 0)) <= -100, "failed maintenance has no fee and keeps service cost")
	_assert(not g.maintenance_summary().has("maintenance-old-unpaid") and int(g.state.retainer_daily[str(g.state.day)].get("maintenance_earned", -1)) == 0, "previous-day unpaid done job is excluded from todays settlement")
	_assert(g.state.last_receipt == receipt_before_settlement, "previous receipt is not rewritten by later settlement")
	var legacy: Node = load("res://scripts/game.gd").new(); root.add_child(legacy); legacy._reset_state(); legacy.state.customer_relations = {"old": {"satisfaction":70}}; legacy.state.care_agreements = {"old": {"fee":321,"active":true,"maintenance_legacy":true}}; legacy.state.day = 7
	_assert(legacy.maintenance_jobs().any(func(item): return str(item.status) == "legacy" and int(item.fee) == 321) and int(legacy.maintenance_summary().legacy) == 1, "legacy maintenance is visible with locked fee")
	# A care delivery cannot activate or bill when any real target snapshot is missing.
	var missing: Node = load("res://scripts/game.gd").new(); root.add_child(missing); missing.save_path = "user://rv-maint-missing-"+id+".json"; missing.backup_path = missing.save_path+".bak"; missing.previous_path = missing.save_path+".previous"; missing.settings_path = "user://rv-maint-missing-"+id+"-settings.json"
	missing._reset_state(); missing.choose_strategy("operations"); missing.set_contract_plan("care"); missing.accept_mission(); _solve_public_case(missing, false); missing.state.vm_states = {}; missing._machine = null; var missing_before: Dictionary = missing.state.duplicate(true)
	_assert(not missing.deliver(), "missing maintenance target rejects care delivery"); _assert(missing.state.cash == missing_before.cash and missing.state.completed_ids == missing_before.completed_ids and missing.state.care_agreements == missing_before.care_agreements and missing.state.maintenance_jobs == missing_before.maintenance_jobs, "missing target delivery rolls back ledger")
	# Completion save failure restores both the assignment ledger and job state.
	g.state.day += 1; g.state.retainer_settled_day = -1; g._prepare_maintenance_day(); _assert(g.assign_maintenance(client, "aya"), "maintenance rollback assignment setup")
	var assignment_before: Dictionary = g._assignments.duplicate(true); var job_state_before: Array = g.state.maintenance_jobs.duplicate(true); var good_save: String = g.save_path; var good_backup: String = g.backup_path
	g.save_path = "user://missing-maint-finish-rollback/save.json"; g.backup_path = g.save_path+".bak"; g._process(12.5)
	_assert(g._assignments.has("aya") and str(g._assignments.aya.get("status", "")) == "working" and is_equal_approx(float(g._assignments.aya.get("remaining", 0.0)), 12.0), "maintenance completion save failure restores assignment")
	var restored_job: Dictionary = g.state.maintenance_jobs.filter(func(item): return str(item.get("client", "")) == client and int(item.get("day", -1)) == int(g.state.day))[0] if not g.state.maintenance_jobs.filter(func(item): return str(item.get("client", "")) == client and int(item.get("day", -1)) == int(g.state.day)).is_empty() else {}
	_assert(str(restored_job.get("status", "")) == "working" and int(restored_job.get("missed_day", -1)) == -1, "maintenance completion save failure restores job ledger")
	g.save_path = good_save; g.backup_path = good_backup

func _solve_public_case(target: Node, late: bool) -> bool:
	if str(target.state.contract.get("case_id", "")) == "advanced-portal": return _solve_portal_case(target, late)
	if target.vm_run("ssh client").is_empty(): return false
	var config_path: String = str(target.vm_info().config_path)
	var desired_text := ""
	if int(target.state.chapter) == 0:
		desired_text = target._vm()._config_text({"staff":"write","guest":"none"})
	elif int(target.state.chapter) == 5:
		desired_text = "staff=write\npartner=read\npublic=none\nexpires=7d\nmfa=on\ntls=on\naudit=on\n"
	else:
		for entry in target.RULES[int(target.state.chapter)].fields:
			var key: String = str(entry[0])
			desired_text += key+"="+_raw_option(key, int(entry[2]))+"\n"
	if not target.vm_write(config_path, desired_text): return false
	if target.vm_run("systemctl restart "+str(target.vm_info().service)).is_empty(): return false
	for pass_index in 3:
		var probes: Array = target.diagnostic_probes()
		probes.sort_custom(func(a,b): return _probe_mutates(a) and not _probe_mutates(b))
		for probe in probes:
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))): target.run_diagnostic(str(probe.id))
	if late:
		for i in 15: target.advance_office_time(10.0)
	var checks: Array = target.verify()
	return checks.all(func(check): return check.passed)

func _portal_request(target: Node, args: Dictionary, expected: int, label: String) -> Dictionary:
	var result: Dictionary = target.advanced_action("request", args)
	_assert(bool(result.get("ok", false)) and int(result.get("response", {}).get("status", 0)) == expected, "quote portal "+label)
	return result

func _solve_portal_case(target: Node, late: bool) -> bool:
	# The first free-career quote can be the portal. Earn its delivery through
	# actual authenticated evidence and retests, just as ordinary quotes use probes.
	var failures_before := failures.size()
	var sessions := {}
	for account in target.advanced_view().get("accounts", []):
		var username := str(account.get("username", ""))
		if username not in ["alice", "beth"]: continue
		var login := _portal_request(target, {"method":"POST","path":"/api/auth/login","body":{"username":username,"password":str(account.get("password", ""))}}, 200, "login "+username)
		sessions[username] = str(login.get("response", {}).get("data", {}).get("session", ""))
	if str(sessions.get("alice", "")).is_empty() or str(sessions.get("beth", "")).is_empty(): return false
	var listed := _portal_request(target, {"method":"GET","path":"/api/invoices","session":sessions.alice}, 200, "normal listing")
	var invoices: Array = listed.get("response", {}).get("data", {}).get("invoices", [])
	if invoices.is_empty(): return false
	var created := _portal_request(target, {"method":"POST","path":"/api/exports","session":sessions.alice,"body":{"invoice_id":str(invoices[0].id)},"headers":{"idempotency-key":"quote-export"}}, 202, "create export")
	var job: Dictionary = created.get("response", {}).get("data", {})
	if not job.has("status_url") or not job.has("download_url"): return false
	_portal_request(target, {"method":"GET","path":str(job.status_url),"session":sessions.alice}, 202, "export processing")
	_portal_request(target, {"method":"GET","path":str(job.status_url),"session":sessions.alice}, 200, "export ready")
	var normal_request := {"method":"GET","path":str(job.download_url),"session":sessions.alice}
	var attack_request := normal_request.duplicate(true)
	attack_request.session = sessions.beth
	var normal := _portal_request(target, normal_request, 200, "own CSV")
	var attack := _portal_request(target, attack_request, 200, "cross tenant CSV")
	_assert(normal.get("response", {}).get("body", "") == attack.get("response", {}).get("body", ""), "quote portal observes original CSV bytes")
	for record in [normal, attack]:
		_assert(bool(target.advanced_action("pin", {"id":str(record.get("request_id", ""))}).get("ok", false)), "quote portal pins proof")
	_assert(bool(target.advanced_action("submit_report", {"claim":"authenticated_cross_tenant_read","evidence_ids":[normal.get("request_id", ""),attack.get("request_id", "")]}).get("ok", false)), "quote portal reports actual evidence")
	_assert(bool(target.advanced_action("customer_fix").get("ok", false)), "quote portal receives customer fix")
	for args in [normal_request, attack_request]:
		var replay := _portal_request(target, args, 200 if str(args.session) == str(sessions.alice) else 403, "original request retest")
		_assert(bool(target.advanced_action("pin", {"id":str(replay.get("request_id", ""))}).get("ok", false)), "quote portal pins retest")
	if late:
		for i in 15: target.advance_office_time(10.0)
	var checks: Array = target.verify()
	return failures.size() == failures_before and not checks.is_empty() and checks.all(func(check): return bool(check.passed))

func _probe_mutates(probe: Dictionary) -> bool:
	var command := str(probe.get("command", "")).to_lower()
	return command.contains(" put ") or command.contains(" backup ") or command.contains(" restore ") or command.begins_with("cp ")

func _raw_option(id: String, index: int) -> String:
	var values := {
		"staff":["none","read","write"],"guest":["none","read","write"],"partner":["none","read","write"],"public":["none","read","write"],
		"schedule":["off","daily"],"location":["local","offsite"],"restore":["unverified","tested"],"dns":["off","on"],"tls":["off","on"],"mfa":["off","on"],
		"partner_mfa":["off","on"],"transfer_tls":["http","https"],"audit":["off","on"],"expires":["unlimited","7d","30d"],
		"business":["deny","allow"],"admin_public":["deny","allow"],"former":["active","disabled"],"sessions":["keep","revoked"],"current":["disabled","active"],
		"endpoint":["connected","isolated"],"healthy":["connected","isolated"],"logs":["erase","keep"],"reset":["wait","wipe"]}
	var options: Array = values.get(id, ["unset","set"])
	return str(options[clampi(index, 0, options.size() - 1)])

func _quote_matches_work_status(target: Node, plan_id: String, offer: Dictionary) -> bool:
	target._reset_state(); target.state.career_mode = true; target.state.awaiting_contract = true; target.state.offers = [offer]; target.state.contract_plan = "standard"; target.state.offer_plan = "standard"; target.state.skills.advisory = 1; target.state.skills.operations = 1; target.state.skills.response = 1; target.set_offer_plan(plan_id)
	var quote: Dictionary = target.contract_quote(offer)
	if not target.choose_contract(str(offer.id)): return false
	var actual: Dictionary = target.work_status()
	return str(quote.selected_plan) == plan_id and int(quote.estimated_fee) == int(actual.estimated_fee) and is_equal_approx(float(quote.budget), float(actual.budget)) and int(quote.costs) == int(actual.costs) and str(quote.deadline_text) == str(actual.deadline_text) and int(quote.net) == int(actual.net)
