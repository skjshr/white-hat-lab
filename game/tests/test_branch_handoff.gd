extends SceneTree
const HANDOFF = preload("res://scripts/branch_handoff.gd")
const CAT = preload("res://scripts/case_catalog.gd")
const VM = preload("res://scripts/virtual_machine.gd")
var assertions := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ", label)

func run() -> void:
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("WHL_HANDOFF_FIXTURE")))
	var before := JSON.stringify(state)
	check(HANDOFF.available(state), "real on-time completed branch is eligible on an old save without inventing consultation")
	var prior := HANDOFF.source(state)
	var authored := HANDOFF.scenario(state, CAT.by_id(HANDOFF.CASE_ID))
	check(not prior.is_empty() and str(authored.fs_overrides[HANDOFF.DESTINATION]) == str(prior.content), "capture actual shared-file bytes")
	check(JSON.stringify(state) == before, "source reads and scenario construction do not mutate old save")
	var settled := state.duplicate(true); settled.contract_contexts = {}
	check(HANDOFF.available(settled) and HANDOFF.source(settled).sha256 == prior.sha256, "cleared day-close dispatch contexts retain durable source and acceptance")
	var missing := state.duplicate(true)
	missing.vm_states[str(prior.contract_id) + "/site-1"].fs.erase(HANDOFF.SOURCE_PATH)
	check(not HANDOFF.available(missing) and HANDOFF.scenario(missing, CAT.by_id(HANDOFF.CASE_ID)).is_empty(), "missing old customer file cannot become a sample handoff")
	var game = root.get_node("Game"); game.set_process(false); game.state = missing.duplicate(true)
	# Display-only model fixture using the genuine delivery record; no save.
	game.state.company_cycle.leads[HANDOFF.CLIENT] = {"id":"follow-up:"+str(prior.contract_id),"client":HANDOFF.CLIENT,"case_id":HANDOFF.CASE_ID,"title":str(authored.title),"work_family":"backup","source_contract_id":str(prior.contract_id),"source_case_id":HANDOFF.SOURCE_CASE,"source_title":"支店の業務再開","source_day":int(prior.day),"source_rating":str(prior.rating),"source_satisfaction":int(prior.satisfaction),"reason":"実納品の引継確認","status":"pending","required_level":2,"required_skills":{"operations":1},"created_day":int(prior.day)}
	var display_before := JSON.stringify(game.state)
	var blocked: Array = game.company_cycle_view().opportunities.filter(func(item):return str(item.client)==HANDOFF.CLIENT)
	check(blocked.size()==1 and bool(blocked[0].get("handoff_unavailable",false)) and str(blocked[0].locked_reason).contains("保存記録"), "missing source explains real data gap instead of endlessly promising tomorrow")
	check(JSON.stringify(game.state)==display_before, "missing-source display does not repair or overwrite legacy state")
	var changed := state.duplicate(true)
	changed.vm_states[str(prior.contract_id) + "/site-1"].fs[HANDOFF.SOURCE_PATH] += "502,102,17600\n"
	var captured := HANDOFF.scenario(changed, CAT.by_id(HANDOFF.CASE_ID))
	check(captured.handoff.sha256 != authored.handoff.sha256, "changed actual customer bytes change immutable acceptance hash")
	changed.vm_states[str(prior.contract_id) + "/site-1"].fs[HANDOFF.SOURCE_PATH] = "later edit"
	check(str(captured.fs_overrides[HANDOFF.DESTINATION]).contains("17600"), "accepted copy does not follow later source edits")
	var paused := state.duplicate(true)
	paused.company_cycle.leads[HANDOFF.CLIENT] = {"case_id":HANDOFF.CASE_ID,"status":"paused"}
	check(not HANDOFF.available(paused), "paused customer cannot bypass consultation through ordinary handoff offers")
	# Labelled VM integration fixture: authored scope, actual backup/restore bytes.
	var vm = VM.new(); vm.setup(1, {}, captured); vm.run("ssh client")
	check(vm.state.fs[HANDOFF.DESTINATION] == captured.fs_overrides[HANDOFF.DESTINATION], "new VM contains captured file, not common orders sample")
	check(vm.state.fs["/home/operator/recovery-manifest.sha256"].contains(str(captured.handoff.sha256)), "customer manifest includes handoff hash")
	vm.state.fs[vm.state.config_path] = "schedule=daily\nrepository=offsite\n"; vm.run("systemctl restart restic")
	vm.run("restic -r local backup /srv/data"); vm.run("restic -r local restore latest --target /restore")
	check(not vm.evaluate().all(func(value):return value), "local-only copy cannot satisfy separate-site requirement")
	vm.run("restic -r offsite backup /srv/data"); vm.run("restic -r offsite restore latest --target /restore")
	check(vm.backup_acceptance_view().accepted and vm.evaluate().all(func(value):return value), "actual offsite snapshot and preserved-source restore satisfy authored scope")
	var saved := vm.export_state(); var resumed = VM.new(); resumed.setup(1, JSON.parse_string(JSON.stringify(saved)), {})
	check(resumed.state.scenario.handoff == JSON.parse_string(JSON.stringify(captured.handoff)) and resumed.backup_acceptance_view().accepted, "save/load keeps acceptance hash and real restore provenance")
	resumed.state.fs["/restore/srv/data/partner-order.csv"] = VM.RECORDS["orders.csv"]
	check(not resumed.backup_acceptance_view().accepted, "common sample cannot pass a non-default customer's restore")
	resumed.state.fs[HANDOFF.DESTINATION] = "changed original"
	check(not resumed.backup_acceptance_view().original_preserved, "original changes remain a real delivery failure")
	print("BRANCH_HANDOFF_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
