extends RefCounted
## Milestones summarize real company activity. They grant no synthetic cash,
## skills or repaired assets. Earned tokens are committed with the save file.
const CATALOG = preload("res://scripts/case_catalog.gd")
const FAMILIES := ["permissions", "backup", "network", "identity", "endpoint", "external_sharing"]

static func _requirement(label: String, current: int, target: int) -> Dictionary:
	return {"label":label,"current":current,"target":target,"complete":current >= target}

static func goals(state: Dictionary) -> Array:
	var deliveries := 0
	var families := {}
	var clients := {}
	var cases := {}
	var cases_in_history := {}
	for item in CATALOG.all(): cases[str(item.id)] = item
	var story_chapters := {"share":0,"backup":1,"network":2,"account":3,"incident":4,"transfer":5}
	for row in state.get("history", []):
		if not row is Dictionary or not str(row.get("kind", "")).is_empty(): continue
		var checks: Array = row.get("checks", []) if row.get("checks", []) is Array else []
		if checks.is_empty() or not checks.all(func(check): return check is Dictionary and bool(check.get("passed", false))): continue
		if row.has("maintenance_incident_id"): continue
		deliveries += 1
		var case_id := str(row.get("case_id", ""))
		if not case_id.is_empty(): cases_in_history[case_id] = true
		var family := str(row.get("work_family", ""))
		if not family.is_empty(): families[family] = true
		if cases.has(case_id):
			var item: Dictionary = cases[case_id]
			if family.is_empty(): families[str(item.get("work_family", "chapter-" + str(item.chapter)))] = true
			clients[str(row.get("client", item.get("client", "")))] = true
		else:
			var copy_id := str(row.get("copy_id", row.get("id", "")))
			if family.is_empty() and story_chapters.has(copy_id): families[FAMILIES[int(story_chapters[copy_id])]] = true
			var client := str(row.get("client", ""))
			if not client.is_empty(): clients[client] = true
	# This journal is written only by validated deliveries and survives receipt
	# trimming. Count a known completed case at least once without double-counting
	# any surviving receipt, and never turn unknown/false entries into history.
	for case_id in state.get("company_cycle", {}).get("completed_cases", {}):
		var completed: Variant = state.company_cycle.completed_cases[case_id]
		if not completed is bool or not completed or not cases.has(str(case_id)): continue
		var item: Dictionary = cases[str(case_id)]
		if not cases_in_history.has(str(case_id)): deliveries += 1
		var family := str(item.get("work_family", ""))
		if not family.is_empty(): families[family] = true
		var client := str(item.get("client", ""))
		if not client.is_empty(): clients[client] = true
	# Relations are retained beyond the bounded detailed history.
	for client in state.get("customer_relations", {}):
		if int(state.customer_relations[client].get("completed_count", 0)) > 0: clients[str(client)] = true
	var installed := 0
	for id in state.get("equipment", []):
		if str(id) in ["backup", "monitor", "workstation", "diagnostic", "teamdesk", "annexdesk_a", "annexdesk_b"]: installed += 1
	var retained := 0
	for client in state.get("care_agreements", {}):
		var agreement: Dictionary = state.care_agreements[client]
		var targets: Array = state.get("maintenance_targets", {}).get(client, [])
		if bool(agreement.get("active", false)) and not bool(agreement.get("maintenance_legacy", false)) and not targets.is_empty(): retained += 1
	var care_days := 0
	for ledger in state.get("retainer_daily", {}).values():
		if int(ledger.get("maintenance_completed", 0)) > 0 and int(ledger.get("maintenance_earned", 0)) > 0 and int(ledger.get("maintenance_missed", 0)) == 0: care_days += 1
	var staff := 0
	for worker in state.get("staff", {}).values():
		if bool(worker.get("active", false)): staff += 1
	var arrears := 0
	for wage in state.get("staff_payroll", {}).get("due", []):
		if bool(wage.get("expense_recorded", false)): arrears += maxi(0, int(wage.get("amount", 0)) - int(wage.get("paid_amount", 0)))
	var cash := int(state.get("cash", 0))
	var definitions := [
		{"id":"first_delivery","title":"開業の一歩","description":"顧客の業務を直して納品する。実績が次の相談の出発点になります。","route":"sales","requirements":[_requirement("検証して納品", deliveries, 1)]},
		{"id":"independent_lab","title":"頼られる技術会社","description":"別の業務も任される会社へ。設備を実際に設置し、次の仕事の運転資金を残します。","route":"shop","requirements":[_requirement("支援した顧客", clients.size(), 2),_requirement("納品したサービス系統", families.size(), 2),_requirement("設置済みの業務設備", installed, 1),_requirement("運転資金（円）", cash, 3000)]},
		{"id":"sustainable_team","title":"続く会社へ","description":"担当者と実際の保守環境を持ち、点検を続けながら給与を払えるチームに育てます。","route":"care","requirements":[_requirement("支援した顧客", clients.size(), 3),_requirement("実環境を引き継いだ保守先", retained, 2),_requirement("点検収入があり未実施ゼロの日", care_days, 3),_requirement("雇用中の社員", staff, 1),_requirement("確定給与の未払いなし", 1 if arrears == 0 else 0, 1),_requirement("運転資金（円）", cash, 6000)]}
	]
	var earned: Dictionary = state.get("company_cycle", {}).get("earned_goals", {})
	for goal in definitions:
		var progress := 0.0
		for requirement in goal.requirements: progress += clampf(float(requirement.current) / maxi(1, int(requirement.target)), 0.0, 1.0)
		goal.progress = progress / goal.requirements.size()
		goal.met_now = goal.requirements.all(func(requirement): return bool(requirement.complete))
		goal.complete = earned.has(str(goal.id))
		goal.earned_day = int(earned.get(str(goal.id), {}).get("day", 0))
	return definitions

static func earned_after_save(state: Dictionary) -> Dictionary:
	var earned: Dictionary = state.get("company_cycle", {}).get("earned_goals", {}).duplicate(true)
	for goal in goals(state):
		if bool(goal.met_now) and not earned.has(str(goal.id)):
			earned[str(goal.id)] = {"day":int(state.get("day", 1)),"title":str(goal.title)}
	return earned
