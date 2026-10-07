extends SceneTree

const HANDOFF = preload("res://scripts/staff_work_handoff.gd")
const GAME = preload("res://scripts/game.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func run() -> void:
	var context := {
		"id":"contract-A","accepted":true,"completed":false,
		"targets":[
			{"name":"拠点A","inspected":true,"revision":4,"validated_revision":4,"checks":[{"id":"read","passed":true},{"id":"write","passed":true}],"work_receipts":[{"job_id":"job-A-aya","contract_id":"contract-A","target_index":0,"member_id":"aya","member_name":"綾","role":"aya","phase":"調査ログを保存しました","result":"ログ本文\n追記","result_path":"/home/operator/aya-inspection.txt","revision":4,"completed_day":7,"completed_minute":675,"time_known":true,"work_minutes":12.0,"legacy":false}]},
			{"name":"拠点B","inspected":true,"revision":3,"validated_revision":2,"checks":[{"id":"old","passed":true}]}
		]
	}
	var assignments := {
		"aya":{"status":"working","contract_id":"contract-A","target_index":0,"job_id":"job-current","role":"aya","phase":"診断結果を整理中","result_path":"/home/operator/aya-inspection.txt","total":12.0},
		"ren":{"status":"done","contract_id":"contract-A","target_index":0,"role":"ren","phase":"復旧・証拠保全完了","result":"保存された復旧ログ","result_path":"/home/operator/ren-recovery.txt","revision":4,"work_minutes_accounted":18.0},
		"mio":{"status":"done","contract_id":"contract-B","target_index":0,"role":"aya","result":"別案件ログ"}
	}
	var context_before := JSON.stringify(context)
	var assignments_before := JSON.stringify(assignments)
	var projection: Dictionary = HANDOFF.from_context(context, 0, assignments)
	check(bool(projection.get("available", false)), "known target projects available")
	check(str(projection.get("contract_id", "")) == "contract-A" and not bool(projection.get("completed", true)), "contract identity and undelivered state remain explicit")
	check(str(projection.acceptance.state) == "ready" and int(projection.acceptance.passed) == 2 and int(projection.acceptance.total) == 2, "ready describes saved checks, not delivery")
	check(projection.current_jobs.size() == 1 and str(projection.current_jobs[0].job_id) == "job-current", "current work is separate from completed receipt")
	check(projection.receipts.size() == 2, "saved and matching legacy receipt retained")
	var saved_receipt: Dictionary = {}
	var legacy_receipt: Dictionary = {}
	for receipt in projection.receipts:
		if str(receipt.get("member_id", "")) == "aya": saved_receipt = receipt
		if str(receipt.get("member_id", "")) == "ren": legacy_receipt = receipt
	check(str(saved_receipt.result) == "ログ本文\n追記" and str(saved_receipt.result_path) == "/home/operator/aya-inspection.txt", "saved detail log preserved")
	check(bool(legacy_receipt.legacy) and not bool(legacy_receipt.time_known) and int(legacy_receipt.completed_day) == -1 and int(legacy_receipt.completed_minute) == -1, "old done assignment keeps unknown completion time unknown")
	check(str(legacy_receipt.member_name).is_empty() and str(legacy_receipt.member_id) == "ren", "legacy UI can label from member identity")
	var stale: Dictionary = HANDOFF.from_context(context, 1, assignments)
	check(str(stale.acceptance.state) == "stale", "revision mismatch marks saved checks stale")
	check(stale.receipts.is_empty() and stale.current_jobs.is_empty(), "other target work is not mixed into this target")
	var failed_context := context.duplicate(true)
	failed_context.targets[0].checks[1].passed = false
	var failed: Dictionary = HANDOFF.from_context(failed_context, 0, {})
	check(str(failed.acceptance.state) == "failed" and int(failed.acceptance.passed) == 1, "current saved failed check remains failed")
	var unknown: Dictionary = HANDOFF.from_context({"id":"contract-C","accepted":true,"targets":[{}]}, 0, {})
	check(bool(unknown.available) and str(unknown.acceptance.state) == "unknown" and int(unknown.acceptance.total) == 0, "missing saved checks stay unknown")
	check(not bool(HANDOFF.from_context(context, 9, {}).get("available", true)), "missing target stays unavailable")
	check(JSON.stringify(context) == context_before and JSON.stringify(assignments) == assignments_before, "projection does not mutate saved inputs")
	var game: Node = GAME.new()
	root.add_child(game)
	game.set_process(false)
	game._reset_state()
	var legacy_target := {"name":"旧拠点","inspected":false,"revision":2,"validated_revision":-1,"checks":[]}
	game.state.accepted = true
	game.state.career_mode = true
	game.state.current_contract_id = "legacy-contract"
	game.state.targets = [legacy_target]
	game.state.contract_contexts = {"legacy-contract":{"id":"legacy-contract","accepted":true,"completed":false,"targets":[legacy_target.duplicate(true)]}}
	game._assignments = {
		"ren":{"kind":"normal","status":"done","contract_id":"legacy-contract","target_index":0,"role":"ren","phase":"復旧・証拠保全完了","result":"旧ログ","result_path":"/home/operator/ren-recovery.txt","revision":2,"work_minutes_accounted":18.0},
		"aya":{"kind":"maintenance","status":"done","contract_id":"legacy-contract","target_index":0,"result":"保守ログ"}
	}
	game.state.assignments = game._assignments.duplicate(true)
	game.save_path = "user://qa-staff-work-handoff-%s.json" % OS.get_process_id()
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	check(game.save_game(), "legacy assignment fixture saved without receipts")
	check(game.load_game(), "legacy completed assignment loads and migrates")
	var migrated_context: Dictionary = HANDOFF.from_context(game.state.contract_contexts["legacy-contract"], 0, game.state.assignments)
	check(migrated_context.receipts.size() == 1 and bool(migrated_context.receipts[0].legacy) and not bool(migrated_context.receipts[0].time_known), "legacy receipt is durable-shaped without invented time")
	check(str(migrated_context.receipts[0].member_id) == "ren" and str(migrated_context.receipts[0].result) == "旧ログ", "legacy receipt preserves identity and log")
	check(not game._migrate_legacy_colleague_receipts() and game.state.contract_contexts["legacy-contract"].targets[0].work_receipts.size() == 1, "legacy migration is idempotent")
	check(game.save_game() and game.load_game(), "migrated legacy receipt persists through reload")
	migrated_context = HANDOFF.from_context(game.state.contract_contexts["legacy-contract"], 0, game.state.assignments)
	check(migrated_context.receipts.size() == 1 and bool(migrated_context.receipts[0].legacy) and not bool(migrated_context.receipts[0].time_known), "reloaded legacy receipt remains factual and unique")
	game.state.inspected = true
	game.state.revision = 2
	game.state.validated_revision = 2
	game.state.checks = [{"label":"保存済み検査","passed":true}]
	game._store_last_acceptance(game.state.checks)
	game._sync_contract_context()
	check(game.save_game(), "formal acceptance record saves with its target")
	game.state.revision = 3
	game.state.inspected = false
	game.state.validated_revision = -1
	game.state.checks = []
	game._sync_contract_context()
	check(game.save_game() and game.load_game(), "later configuration save preserves the prior acceptance record")
	var historical_projection: Dictionary = HANDOFF.from_context(game.state.contract_contexts["legacy-contract"], 0, game.state.assignments)
	check(bool(historical_projection.acceptance.get("historical", false)) and str(historical_projection.acceptance.state) == "stale", "prior formal checks remain visible as stale after target revision changes")
	check(int(historical_projection.acceptance.total) == 1 and int(historical_projection.acceptance.passed) == 1 and int(historical_projection.acceptance.revision) == 3 and int(historical_projection.acceptance.validated_revision) == 2, "historical acceptance shows saved result and current-versus-validated revisions")
	var reused_revision: Dictionary = game.state.contract_contexts["legacy-contract"].duplicate(true)
	reused_revision.targets[0].revision = 2; reused_revision.targets[0].inspected = true
	check(str(HANDOFF.from_context(reused_revision, 0, {}).acceptance.state) == "stale", "cleared live checks cannot inherit a historical PASS even at the same revision")
	game.queue_free()
	print("STAFF_WORK_HANDOFF failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
