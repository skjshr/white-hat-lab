extends SceneTree

## End-to-end career growth test. It uses the real Game/VM APIs and never edits
## cash, profit, credit, level, sites, or completion state directly.
var game: Node
var graphics: Node
var failures: Array[String] = []
var contracts := 0
var observed_sites_at_8 := 0

func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	graphics = root.get_node("Graphics")
	game.save_path = "user://business-growth.json"
	game.backup_path = "user://business-growth.json.bak"
	game.previous_path = "user://business-growth.previous.json"
	game.settings_path = "user://business-growth-settings.json"
	game._reset_state()
	_assert(CaseCatalog.all().size() == 42, "42案件カタログ（単一36・設備2・複合3・endpoint-recovery）")
	_assert(game.choose_strategy("advisory"), "advisory戦略を選択")
	_assert(not game.work_guidance().is_empty(), "初期ガイダンス")
	_assert(game.start_free_career(), "無料キャリア開始")
	_assert(game.company_level().level == 1, "初期会社レベル")
	_assert(game.state.offers.size() == 42, "初回42案件オファー")
	# Confirm settings are persisted/applied through the real settings and Graphics APIs.
	var initial_settings: Dictionary = game.settings.duplicate(true)
	game.set_settings({"max_fps":30,"quality":"low"})
	var applied: Dictionary = graphics.apply_settings(game.settings)
	_assert(int(applied.max_fps) == 30 and game.settings.max_fps == 30, "設定値と適用値")
	game.set_settings(initial_settings)

	_run_first_contract_with_both_colleagues()
	while int(game.company_level().level) < 15 and contracts < 40 and failures.is_empty():
		_learn_advisory()
		var offer := _best_unlocked_offer()
		if offer.is_empty():
			_fail("Lv%dで受注可能案件なし" % int(game.company_level().level)); break
		var chose: bool = game.choose_contract(str(offer.id))
		_assert(chose, "career契約受注")
		for site in game.state.targets.size():
			game.select_target(site)
			_solve_contract(false)
			if site < game.state.targets.size() - 1: _assert(not game.can_deliver(), "未処理拠点では納品不可")
		var deliverable: bool = game.can_deliver()
		var delivered: bool = game.deliver()
		_assert(deliverable, "通常契約の納品可能")
		_assert(delivered, "通常契約納品")
		contracts += 1
		var before_day := int(game.state.day)
		var ended_loop: bool = game.end_day()
		if int(game.company_level().level) >= 8: observed_sites_at_8 = maxi(observed_sites_at_8, _max_offer_sites())
		_assert(ended_loop and int(game.state.day) == before_day + 1, "終業と次案件")
	_learn_advisory()
	_assert(int(game.company_level().level) >= 15, "Lv15到達")
	_assert(int(game.state.skills.advisory) >= 3, "advisory rank3")
	_assert(int(game.state.offers.size()) == 42, "Lv15でも42案件カタログ")
	_assert(observed_sites_at_8 >= 2, "Lv8で2拠点の案件を観測")
	_assert(_max_offer_sites() >= 3, "Lv15で3拠点の案件を観測")
	_run_three_site_contract()
	print("BUSINESS_GROWTH contracts=",contracts," level=",game.company_level().level," sites=",game.state.targets.size()," failures=",failures.size())
	for failure in failures: push_error("BUSINESS_GROWTH: " + failure)
	quit(1 if not failures.is_empty() else 0)

func _run_first_contract_with_both_colleagues() -> void:
	var offer := _best_unlocked_offer()
	_assert(not offer.is_empty() and game.choose_contract(str(offer.id)), "最初の契約受注")
	game.vm_run("ssh client")
	var desired: Dictionary = game._scenario().get("desired", {})
	var config_path := str(game.vm_info().config_path)
	game.assign_colleague("aya")
	var ren_supported := int(game.state.chapter) in [1, 4]
	if ren_supported: game.assign_colleague("ren")
	# Investigation is read-only. Recovery may restore data and preserve evidence,
	# but neither colleague edits the player's configuration or restarts services.
	_assert(game.vm_write(config_path, _config_text(desired)), "プレイヤー設定編集")
	_tick(30.0)
	var aya_job: Dictionary = game.state.assignments.get("aya", {})
	_assert(aya_job.get("status", "") == "done", "調査担当が読み取りと報告を完了")
	if ren_supported: _assert(game.state.assignments.get("ren", {}).get("status", "") == "done", "復旧担当が調査後に作業を完了")
	_assert(str(game._vm().state.fs.get(config_path, "")) == _config_text(desired), "プレイヤー入力を保持")
	game.vm_run("systemctl restart " + str(game.vm_info().service))
	_measure_all()
	_assert(game.verify().all(func(check): return check.passed), "最初の契約を再検証")
	_assert(game.can_deliver() and game.deliver(), "最初の契約納品")
	contracts += 1
	var ended: bool = game.end_day()
	_assert(ended, "最初の終業")

func _solve_contract(assign_colleagues: bool) -> void:
	game.vm_run("ssh client")
	if assign_colleagues:
		game.assign_colleague("aya")
		game.assign_colleague("ren")
		_tick(20.0)
	var scenario: Dictionary = game._scenario()
	var desired: Dictionary = scenario.get("desired", {})
	_assert(not desired.is_empty(), "対象サービスの実シナリオを解決")
	if desired.is_empty(): return
	var config_path := str(game.vm_info().config_path)
	_assert(game.vm_write(config_path, _config_text(desired)), "案件設定を書き込み")
	game.vm_run("systemctl restart " + str(game.vm_info().service))
	if int(game.state.chapter) == 1:
		if str(scenario.get("seed_snapshot_repository", "")) != str(desired.get("repository", "offsite")):
			game.vm_run("restic backup /srv/data")
		game.vm_run("restic restore 00000001 --target /restore" if scenario.has("latest_snapshot_overrides") else "restic restore latest --target /restore")
	if int(game.state.chapter) == 4:
		game.vm_run("cp /var/log/evidence.log /evidence/original.log")
	preload("res://tests/identity_test_support.gd").authenticate_current(game)
	_measure_all()
	var checks: Array = game.verify()
	if not checks.all(func(check): return check.passed):
		print("BUSINESS_GROWTH_FAILED_CHECK chapter=",game.state.chapter," scenario=",scenario.get("id", "")," checks=",checks," config=",game.vm_read(config_path))
		# A failed real check is retained as a test failure; do not fake completion.
		_fail("実案件検証失敗 chapter=%d" % int(game.state.chapter))

func _measure_all() -> void:
	for attempt in 3:
		for probe in game.diagnostic_probes():
			if not (probe.recorded and probe.fresh and probe.passed): game.run_diagnostic(str(probe.id))
		if game.diagnostic_probes().all(func(probe): return probe.recorded and probe.fresh and probe.passed): break

func _run_three_site_contract() -> void:
	var selected: Dictionary = {}
	for refresh in 6:
		for offer in game.state.offers:
			var supply_requirement = offer.get("supply_requirement", {})
			if offer.unlocked and bool(offer.get("market_available", true)) and int(offer.targets) == 3 and int(offer.required_level) <= int(game.company_level().level) and not str(offer.get("case_id", "")).begins_with("composite-") and (not (supply_requirement is Dictionary) or supply_requirement.is_empty()):
				if selected.is_empty() or int(offer.reward) > int(selected.reward): selected = offer
		if not selected.is_empty(): break
		if refresh < 5: _assert(game.end_day(), "3拠点案件の市場更新")
	_assert(not selected.is_empty(), "3拠点案件を選択可能")
	_assert(game.choose_contract(str(selected.get("id", ""))), "3拠点案件受注")
	_assert(game.state.targets.size() == 3, "3拠点生成")
	for site in 3:
		game.select_target(site)
		_solve_contract(true)
		_assert(game.verify().all(func(check): return check.passed), "拠点%d検証" % (site + 1))
		if site < 2: _assert(not game.can_deliver(), "未処理拠点では納品不可")
	_assert(game.can_deliver(), "全拠点処理後に納品可能")
	_assert(game.deliver(), "3拠点案件納品")
	contracts += 1

func _best_unlocked_offer(allowed_chapters: Array = []) -> Dictionary:
	var best := {}
	for offer in game.state.offers:
		if not allowed_chapters.is_empty() and int(offer.get("chapter", -1)) not in allowed_chapters: continue
		if not bool(offer.get("market_available", true)): continue
		# Hardware contracts have a separate procurement/commissioning gate and
		# are covered by test_procurement.gd; keep this career-growth path on
		# contracts solvable through the normal service workflow.
		var supply_requirement = offer.get("supply_requirement", {})
		if supply_requirement is Dictionary and not supply_requirement.is_empty(): continue
		var case_id := str(offer.get("case_id", ""))
		var already_done := false
		for entry in game.state.history:
			if str(entry.get("case_id", "")) == case_id: already_done = true; break
		if offer.unlocked and not already_done and (best.is_empty() or int(offer.get("reward", 0)) > int(best.get("reward", 0))):
			best = offer
	return best

func _learn_advisory() -> void:
	while int(game.state.skills.advisory) < 3 and game.skill_points() > 0:
		_assert(game.learn_skill("advisory"), "advisoryスキルポイント")

func _max_offer_sites() -> int:
	var maximum := 0
	for offer in game.state.offers:
		if offer.unlocked: maximum = maxi(maximum, int(offer.get("targets", 0)))
	return maximum

func _config_text(values: Dictionary) -> String:
	return game._vm().configuration_text(values)

func _tick(seconds: float) -> void:
	var steps := int(ceil(seconds / 0.5))
	for i in steps: game._process(0.5)

func _assert(value: bool, label: String) -> void:
	if not value: _fail(label)

func _fail(label: String) -> void:
	failures.append(label)
