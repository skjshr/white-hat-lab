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
	var catalog_count := CaseCatalog.all().size()
	_assert(catalog_count == 60, "現行案件カタログ（単一36・設備2・複合3・endpoint-recovery・専門案件）")
	_assert(game.choose_strategy("advisory"), "advisory戦略を選択")
	_assert(not game.work_guidance().is_empty(), "初期ガイダンス")
	_assert(game.start_free_career(), "無料キャリア開始")
	_assert(game.company_level().level == 1, "初期会社レベル")
	_assert(game.state.offers.size() == catalog_count, "初回案件オファー")
	# Confirm settings are persisted/applied through the real settings and Graphics APIs.
	var initial_settings: Dictionary = game.settings.duplicate(true)
	game.set_settings({"max_fps":30,"quality":"low"})
	var applied: Dictionary = graphics.apply_settings(game.settings)
	_assert(int(applied.max_fps) == 30 and game.settings.max_fps == 30, "設定値と適用値")
	game.set_settings(initial_settings)

	_run_first_contract_with_both_colleagues()
	while int(game.company_level().level) < 15 and contracts < 40 and failures.is_empty():
		_learn_growth_skills()
		var offer := _best_unlocked_offer()
		if offer.is_empty():
			_fail("Lv%dで受注可能案件なし" % int(game.company_level().level)); break
		var chose: bool = game.choose_contract(str(offer.id))
		_assert(chose, "career契約受注")
		if str(offer.get("case_id", "")).begins_with("composite-"):
			_solve_contract(false)
		else:
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
	_assert(int(game.state.offers.size()) == catalog_count, "Lv15でも案件カタログ")
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
	var case_id := str(game.state.contract.get("case_id", ""))
	if case_id == "composite-branch-reopen":
		_solve_branch_composite()
		return
	if case_id == "composite-former-access":
		_solve_former_composite()
		return
	if case_id == "composite-corruption-response":
		_solve_corruption_composite()
		return
	game.vm_run("ssh client")
	if assign_colleagues:
		game.assign_colleague("aya")
		game.assign_colleague("ren")
		_tick(40.0)
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

func _target_for_chapter(chapter: int) -> int:
	for index in game.state.targets.size():
		if int(game.state.targets[index].get("chapter", -1)) == chapter: return index
	return -1

func _connect_target(index: int) -> bool:
	_assert(index >= 0 and game.select_target(index), "複合案件の対象を選択")
	if index < 0: return false
	var output := str(game.vm_run("ssh client"))
	_assert(bool(game.vm_info().get("connected", false)) and not output.is_empty(), "複合案件のSSH接続")
	return bool(game.vm_info().get("connected", false))

func _configure_target(index: int, values: Dictionary, service: String) -> bool:
	if not _connect_target(index): return false
	var path := str(game.vm_info().get("config_path", ""))
	_assert(game.vm_write(path, game._vm().configuration_text(values)), "複合案件の設定を書き込み")
	_assert(str(game.vm_run("systemctl restart %s" % service)).contains("active"), "複合案件のサービス再起動")
	return true

func _measure_target(index: int) -> void:
	if not _connect_target(index): return
	var checks: Array = []
	for _round in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
				_assert(not str(game.run_diagnostic(str(probe.get("id", "")))).is_empty(), "複合案件の実測")
		checks = game.verify()
		if not checks.is_empty() and checks.all(func(item): return bool(item.get("passed", false))): break
	_assert(not checks.is_empty() and checks.all(func(item): return bool(item.get("passed", false))), "複合案件の検証")

func _solve_branch_composite() -> void:
	# Reuse the same public VM/configuration path as test_branch_workflow: the
	# branch contract is complete only when all three linked services measure
	# the shared source, so a generic single-VM write is insufficient.
	var gateway := _target_for_chapter(2)
	var share := _target_for_chapter(0)
	var portal := _target_for_chapter(5)
	_assert(gateway >= 0 and share >= 0 and portal >= 0, "支店案件の3対象")
	if gateway < 0 or share < 0 or portal < 0: return
	_configure_target(gateway, {"dns":"on", "business":"allow", "admin_public":"deny", "tls":"on"}, "firewall")
	_configure_target(share, {"staff":"write", "guest":"none"}, "samba")
	_configure_target(portal, {"staff":"write", "partner":"read", "public":"none", "expires":"7d", "mfa":"on", "tls":"on", "audit":"on"}, "portal")
	_measure_target(gateway)
	_measure_target(share)
	_measure_target(portal)

func _authenticate_current() -> String:
	var login: Variant = JSON.parse_string(str(game.vm_run("identity login current Training-117!")))
	if not login is Dictionary: return ""
	if str(login.get("token", "")).is_empty() and not str(login.get("challenge", "")).is_empty():
		login = JSON.parse_string(str(game.vm_run("identity otp %s 123456" % str(login.get("challenge", "")))))
	return str(login.get("token", "")) if login is Dictionary else ""

func _solve_former_composite() -> void:
	# This follows the existing linked-identity solver: revoke the real former
	# session, establish a current session, then verify the linked portal.
	var identity := _target_for_chapter(3)
	var portal := _target_for_chapter(5)
	_assert(identity >= 0 and portal >= 0, "退職者案件の2対象")
	if identity < 0 or portal < 0: return
	if _connect_target(identity):
		var initial: Variant = JSON.parse_string(str(game.vm_run("identity access former-seed-1")))
		_assert(initial is Dictionary and int(initial.get("code", 0)) == 200, "旧セッションの確認")
		var disabled: Variant = JSON.parse_string(str(game.vm_run("identity enable former off")))
		_assert(disabled is Dictionary and bool(disabled.get("ok", false)), "退職者アカウント停止")
		var revoked: Variant = JSON.parse_string(str(game.vm_run("identity logout former-seed-1")))
		_assert(revoked is Dictionary and bool(revoked.get("ok", false)), "旧セッション失効")
	var current_token := ""
	if _connect_target(identity): current_token = _authenticate_current()
	_assert(not current_token.is_empty(), "在籍者の再認証")
	_configure_target(portal, {"staff":"write", "partner":"read", "public":"none", "expires":"7d", "mfa":"on", "tls":"on", "audit":"on"}, "portal")
	_measure_target(identity)
	_measure_target(portal)

func _solve_corruption_composite() -> void:
	# The production business-workspace solver is the source for this linked
	# path: contain the endpoint, restore the known snapshot into staging, copy
	# the bytes into production, and then verify the linked gateway.
	var edr := _target_for_chapter(4)
	var backup := _target_for_chapter(1)
	var gateway := _target_for_chapter(2)
	_assert(edr >= 0 and backup >= 0 and gateway >= 0, "破損対応案件の3対象")
	if edr < 0 or backup < 0 or gateway < 0: return
	if _connect_target(edr):
		_assert(str(game.vm_run("edr devices")).contains("pc_b"), "不審端末を列挙")
		_assert(str(game.vm_run("edr timeline pc_b")).contains("pc_b"), "不審端末の時系列")
		var collected: Variant = JSON.parse_string(str(game.vm_run("edr collect")))
		_assert(collected is Dictionary and bool(collected.get("ok", false)), "証拠を収集")
		var isolated: Variant = JSON.parse_string(str(game.vm_run("edr isolate pc_b")))
		_assert(isolated is Dictionary and bool(isolated.get("ok", false)), "不審端末を隔離")
		_assert(game.vm_run("cp /var/log/evidence.log /evidence/original.log").is_empty(), "証拠原本を保全")
	if _configure_target(backup, {"schedule":"daily", "repository":"offsite"}, "restic"):
		var restored := str(game.vm_run("restic -r offsite restore 00000001:/srv/data --target /restore"))
		_assert(restored.contains("restored"), "既知スナップショットを復元")
		_assert(not game.vm_read("/restore/ledger.txt").is_empty(), "復元先の台帳を確認")
		_assert(game.vm_run("cp /restore/ledger.txt /srv/data/ledger.txt").is_empty(), "復元台帳を本番へ展開")
	_configure_target(gateway, {"dns":"on", "business":"allow", "admin_public":"deny", "tls":"on"}, "firewall")
	_measure_target(edr)
	_measure_target(backup)
	_measure_target(gateway)

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
	var repeatable := {}
	for offer in game.state.offers:
		if not allowed_chapters.is_empty() and int(offer.get("chapter", -1)) not in allowed_chapters: continue
		if not bool(offer.get("market_available", true)): continue
		# Hardware contracts have a separate procurement/commissioning gate and
		# are covered by test_procurement.gd; keep this career-growth path on
		# contracts solvable through the normal service workflow.
		var supply_requirement = offer.get("supply_requirement", {})
		if supply_requirement is Dictionary and not supply_requirement.is_empty(): continue
		var case_id := str(offer.get("case_id", ""))
		if case_id == "endpoint-recovery" or case_id.begins_with("advanced-"): continue
		var already_done := false
		for entry in game.state.history:
			if str(entry.get("case_id", "")) == case_id: already_done = true; break
		if not offer.unlocked: continue
		if already_done:
			if repeatable.is_empty() or int(offer.get("reward", 0)) > int(repeatable.get("reward", 0)): repeatable = offer
		elif best.is_empty() or int(offer.get("reward", 0)) > int(best.get("reward", 0)):
			best = offer
	return best if not best.is_empty() else repeatable

func _learn_advisory() -> void:
	while int(game.state.skills.advisory) < 3 and game.skill_points() > 0:
		_assert(game.learn_skill("advisory"), "advisoryスキルポイント")

func _learn_growth_skills() -> void:
	while game.skill_points() > 0:
		var selected := ""
		var selected_rank := 99
		# Keep the three real disciplines moving together.  Response rank 3 is
		# needed for the corruption-response composite that unlocks the Lv7+
		# progression; advisory rank 3 remains asserted at the end.
		for skill_id in ["response", "advisory", "operations"]:
			var rank := int(game.state.skills.get(skill_id, 0))
			if rank < 10 and rank < selected_rank:
				selected = skill_id; selected_rank = rank
		if selected.is_empty() or not game.learn_skill(selected): break

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
