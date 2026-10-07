extends SceneTree

const PREVIEW = preload("res://scripts/staffing_work_preview.gd")
const GAME = preload("res://scripts/game.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func setup_game():
	var g = GAME.new()
	root.add_child(g)
	g.set_process(false)
	g._reset_state()
	g.state.career_mode = true
	g.state.accepted = true
	g.state.day = 8
	g.state.clock_minutes = 600
	g.state.cash = 100000
	g.state.equipment = ["teamdesk", "annexdesk_a"]
	g.state.staff_payroll.enabled = true
	g.state.contract_contexts = {
		"ordinary-1":{
			"id":"ordinary-1","accepted":true,"completed":false,"chapter":1,"contract_plan":"standard",
			"contract":{"case_id":"basic-operations","client":"顧客A","title":"通常の確認作業","agreed_fee":1200,"agreed_budget":420.0,"target_specs":[]},
			"work":{"started_day":8,"started_at":540},
			"targets":[{"name":"拠点A","chapter":1,"revision":1,"validated_revision":0,"inspected":false,"checks":[],"work_receipts":[]}]
		}
	}
	return g

func find_job(result: Dictionary, key: String) -> Dictionary:
	for job in result.get("jobs", []):
		if str(job.get("key", "")) == key: return job
	return {}

func run() -> void:
	var g = setup_game()
	var before_state := JSON.stringify(g.state)
	var before_settings := JSON.stringify(g.settings)
	var before_assignments := JSON.stringify(g._assignments)
	var before_runtime := JSON.stringify([g._crew_runtime_available,g._crew_runtime_registered])
	var signature_state_before := JSON.stringify(g.state)
	var signature_assignments_before := JSON.stringify(g._assignments)
	var base_signature := PREVIEW.signature(g)
	g._assignments["aya"] = {"status":"working","kind":"normal","contract_id":"ordinary-1","target_index":0,"remaining":12.0}
	var assigned_signature := PREVIEW.signature(g)
	g._assignments["aya"]["remaining"] = 4.0
	check(assigned_signature == PREVIEW.signature(g), "signature ignores ticking remaining-work seconds")
	g._assignments.clear()
	g.state.cash += 1
	check(base_signature != PREVIEW.signature(g), "signature changes when hiring affordability changes")
	g.state.cash -= 1
	g.state.clock_minutes += 1
	check(base_signature != PREVIEW.signature(g), "signature changes with business clock")
	g.state.clock_minutes -= 1
	g.state.contract_contexts["ordinary-1"].targets[0].revision += 1
	check(base_signature != PREVIEW.signature(g), "signature changes with target revision")
	g.state.contract_contexts["ordinary-1"].targets[0].revision -= 1
	check(JSON.stringify(g.state) == signature_state_before and JSON.stringify(g._assignments) == signature_assignments_before, "signature probes restore and do not mutate live state")
	var morning: Dictionary = PREVIEW.snapshot(g, "mio", "morning")
	var afternoon: Dictionary = PREVIEW.snapshot(g, "haru", "afternoon")
	var morning_job := find_job(morning, "contract:ordinary-1:0")
	var afternoon_job := find_job(afternoon, "contract:ordinary-1:0")
	check(str(morning.get("role", "")) == "aya" and int(morning.get("shift_start", -1)) == 540 and int(morning.get("shift_end", -1)) == 780, "candidate morning uses catalog shift and Aya role")
	check(str(afternoon.get("role", "")) == "ren" and int(afternoon.get("shift_start", -1)) == 780 and int(afternoon.get("shift_end", -1)) == 1080, "different candidate afternoon uses catalog shift and Ren role")
	check(bool(morning_job.get("can_enqueue", false)) and bool(afternoon_job.get("can_enqueue", false)), "seat availability does not falsify candidate task fit")
	check(str(morning_job.get("target_name", "")) == "拠点A" and bool(morning_job.get("demand", false)) and not bool(morning_job.get("prior_work", true)), "target identity and unallocated demand are explicit")
	check(int(morning_job.get("finish_day", -1)) == 8 and int(afternoon_job.get("finish_day", -1)) == 8, "independent candidate forecasts use current workday")
	check(int(morning.get("hire_fee", 0)) == 2400 and int(morning.get("wage", 0)) == 300 and int(morning.get("day_payroll_after", -1)) == int(morning.get("day_payroll_before", 0)) + 300, "candidate fee and half-shift payroll use catalog values once")
	g.state.staff["mio"] = {"active":true,"role":"aya","shift":"afternoon","daily_wage":600,"minutes_day":8,"minutes_used":0.0}
	g.state.staff_payroll.due.append({"day":8,"staff_id":"mio","amount":300,"paid_amount":100,"paid":false,"expense_recorded":false})
	var active_preview: Dictionary = PREVIEW.snapshot(g, "mio", "morning")
	check(bool(active_preview.get("hired", false)) and str(active_preview.get("shift", "")) == "afternoon" and int(active_preview.get("shift_start", -1)) == 780, "active candidate uses its saved shift rather than selector default")
	check(str(active_preview.get("forecast_basis", "")) == "現在の在籍状態" and not active_preview.has("hire_fee") and int(active_preview.get("day_payroll_after", -1)) == int(active_preview.get("day_payroll_before", -2)), "active payroll is not presented as a new hire cost")
	g.state.staff.erase("mio")
	g.state.staff_payroll.due.clear()
	check(JSON.stringify(g.state) == before_state and JSON.stringify(g.settings) == before_settings and JSON.stringify(g._assignments) == before_assignments and JSON.stringify([g._crew_runtime_available,g._crew_runtime_registered]) == before_runtime, "nested live state and runtime dictionaries remain unchanged")

	# Prior work stays visible separately from demand, and the workday API keeps
	# authority over whether that row can actually be dispatched again.
	g._assignments["aya"] = {"status":"working","kind":"normal","contract_id":"ordinary-1","target_index":0}
	g.state.staff_payroll.due.append({"day":8,"staff_id":"mio","amount":600,"paid_amount":200,"paid":false,"expense_recorded":false})
	g.state.cash = 500
	var assigned: Dictionary = PREVIEW.snapshot(g, "mio", "afternoon")
	var assigned_job := find_job(assigned, "contract:ordinary-1:0")
	check(not assigned_job.is_empty() and not bool(assigned_job.get("demand", true)) and bool(assigned_job.get("prior_work", false)), "same-role assigned work remains visible but is not counted as new demand")
	check(not bool(assigned_job.get("can_enqueue", true)) and not str(assigned_job.get("reason", "")).is_empty(), "duplicate assignment retains the existing API block")
	check(not find_job(PREVIEW.snapshot(g, "haru", "afternoon"), "contract:ordinary-1:0").is_empty(), "different-role work remains visible as a distinct specialist task")
	check(int(assigned.get("day_payroll_after", -1)) == int(assigned.get("day_payroll_before", -2)), "existing same-day payroll entry is not double-counted on rehire preview")
	check(not str(assigned.get("hire_reason", "")).is_empty(), "actual live hiring blocker remains visible")

	# Manual-only work stays visible with the actual blocked reason. Completed
	# targets disappear, but a failed receipt remains visible and retryable.
	g._assignments.clear()
	g.state.staff_payroll.due.clear()
	var manual_context: Dictionary = g.state.contract_contexts["ordinary-1"].duplicate(true)
	manual_context.contract.case_id = "advanced-saas-priority"
	manual_context.contract.title = "手動限定案件"
	g.state.contract_contexts["manual-1"] = manual_context
	var manual: Dictionary = PREVIEW.snapshot(g, "mio")
	var manual_job := find_job(manual, "contract:manual-1:0")
	check(not manual_job.is_empty() and not bool(manual_job.get("can_enqueue", true)) and not str(manual_job.get("reason", "")).is_empty(), "manual-only advanced work retains its dispatch restriction")
	manual_context.completed = true
	g.state.contract_contexts["done-1"] = manual_context
	var receipt_context: Dictionary = g.state.contract_contexts["ordinary-1"].duplicate(true)
	receipt_context.targets[0].work_receipts = [{"member_id":"aya","role":"aya","phase":"復元結果を保存","result":"restore_failed","revision":1}]
	g.state.contract_contexts["receipt-1"] = receipt_context
	var filtered: Dictionary = PREVIEW.snapshot(g, "mio")
	var retry_job := find_job(filtered, "contract:receipt-1:0")
	check(find_job(filtered, "contract:done-1:0").is_empty(), "completed contracts are hidden")
	check(not retry_job.is_empty() and not bool(retry_job.get("demand", true)) and bool(retry_job.get("prior_work", false)), "failed-receipt work remains visible as prior work, not new demand")
	check(bool(retry_job.get("can_enqueue", false)) and bool(retry_job.get("can_finish", false)), "failed receipt does not hide the existing retry route")

	# The normalizer must tolerate pre-migration saves without optional arrays.
	var legacy = setup_game()
	legacy.state.erase("dispatch_queues")
	legacy.state.erase("maintenance_jobs")
	legacy.state.erase("staff_payroll")
	var legacy_projection: Dictionary = PREVIEW.snapshot(legacy, "sora", "morning")
	check(str(legacy_projection.get("id", "")) == "sora" and legacy_projection.get("jobs", []) is Array, "legacy saves missing queue and payroll arrays still project safely")
	check(not legacy.state.has("dispatch_queues") and not legacy.state.has("maintenance_jobs") and not legacy.state.has("staff_payroll"), "legacy normalization does not write missing arrays back")

	print("STAFFING_WORK_PREVIEW_PASS" if failures.is_empty() else "STAFFING_WORK_PREVIEW_FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
