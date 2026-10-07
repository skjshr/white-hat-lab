extends SceneTree

const BACKUP = preload("res://scripts/staff_backup_work.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func run() -> void:
	var execution := {"status":"restored","repository":"local","schedule":"daily","source":"/srv/data","snapshot":"00000001","target":"/restore","files":[{"source":"/srv/data/orders.csv","path":"/restore/orders.csv","status":"restored"}],"error":"","backup_created":true}
	var context := {"id":"contract-A","targets":[{"chapter":1,"case_id":"service-1-case-0","scenario":{"desired":{"repository":"offsite","schedule":"daily"}},"work_receipts":[
		{"contract_id":"other-contract","target_index":0,"member_id":"ren","backup_execution_v1":execution.duplicate(true)},
		{"contract_id":"contract-A","target_index":0,"member_id":"backup-ren-id","role":"ren","backup_execution_v1":execution.duplicate(true)}
	]}]}
	var vm := {"contract-A/site-0":{"backup_model_version":2,"active":true,"dirty":false,"applied":{"repository":"local","schedule":"off"},"scenario":{"desired":{"repository":"local","schedule":"off"}},"snapshots":[{"id":"00000001","repository":"local","files":{"orders.csv":"x","ledger.csv":"y"}},{"id":"00000002","repository":"offsite","files":{}}],"last_restore":{"snapshot":"00000001","target":"/restore","includes":[],"overwrite":"always"},"fs":{"/restore/orders.csv":"x","/restore/ledger.txt":"y","/restore-other/ignore.txt":"z"}}}
	var context_before := JSON.stringify(context)
	var vm_before := JSON.stringify(vm)
	var projection: Dictionary = BACKUP.from_context(context, 0, vm)
	check(bool(projection.get("available", false)) and bool(projection.get("known", false)), "saved chapter one plan is available and known")
	check(str(projection.get("repository", "")) == "local" and str(projection.get("schedule", "")) == "disabled" and str(projection.get("desired_repository", "")) == "offsite" and str(projection.get("desired_schedule", "")) == "daily", "current VM settings remain separate from saved customer requirements")
	check(bool(projection.get("requires_selection", false)) and projection.get("snapshots", []).size() == 2 and int(projection.snapshots[0].file_count) == 2, "multiple saved snapshots require selection and expose saved file counts")
	check(str(projection.restore.repository) == "local" and int(projection.restore.file_count) == 2 and bool(projection.restore.current_files) and projection.restore.paths == ["/restore/ledger.txt", "/restore/orders.csv"], "restore field reports current files under the saved target, not employee execution count")
	check(projection.execution == execution, "latest matching Ren receipt is retained exactly")
	projection.execution.files[0].path = "/changed"
	projection.snapshots[0].id = "changed"
	check(JSON.stringify(context) == context_before and JSON.stringify(vm) == vm_before, "projection and returned nested edits leave original save untouched")
	var roundtrip_context: Variant = JSON.parse_string(JSON.stringify(context))
	var roundtrip_vm: Variant = JSON.parse_string(JSON.stringify(vm))
	var roundtrip: Dictionary = BACKUP.from_context(roundtrip_context, 0, roundtrip_vm)
	check(bool(roundtrip.known) and int(roundtrip.snapshots[0].file_count) == 2 and bool(roundtrip.requires_selection), "JSON save/load numeric types preserve a known projected plan")
	var vm_desired_context := {"id":"contract-A","targets":[{"chapter":1,"scenario":null,"work_receipts":[]}]}
	var vm_desired_state := vm.duplicate(true)
	vm_desired_state["contract-A/site-0"].scenario.desired = {"repository":"offsite","schedule":"daily"}
	var vm_desired: Dictionary = BACKUP.from_context(vm_desired_context, 0, vm_desired_state)
	check(str(vm_desired.desired_repository) == "offsite" and str(vm_desired.desired_schedule) == "daily", "saved VM desired settings are used when target scenario is absent")
	var desired_unknown_state := vm.duplicate(true)
	desired_unknown_state["contract-A/site-0"].scenario.erase("desired")
	var desired_unknown: Dictionary = BACKUP.from_context(vm_desired_context, 0, desired_unknown_state)
	check(bool(desired_unknown.known) and str(desired_unknown.desired_repository).is_empty() and bool(desired_unknown.snapshots_known), "unknown customer requirement is separate from a known current VM structure")

	var legacy_target := {"chapter":1,"scenario":{"desired":{"repository":"offsite","schedule":"daily"}},"work_receipts":[]}
	var legacy := BACKUP.from_context({"id":"legacy","targets":[legacy_target]}, 0, {"legacy/site-0":{"applied":{},"snapshots":[]}})
	check(bool(legacy.available) and not bool(legacy.known) and str(legacy.desired_repository) == "offsite" and legacy.execution.is_empty(), "legacy partial VM state remains unknown without losing saved requirements")
	check(not bool(BACKUP.from_context({"id":"missing","targets":[{"chapter":1}]}, 0, {}).known), "missing VM is unknown instead of an empty successful state")
	check(BACKUP.from_context({"id":"contract-A","targets":[{"chapter":2}]}, 0, vm).is_empty(), "non backup chapters have no backup projection")
	check(not bool(BACKUP.from_context(context, 0, {"another-contract/site-0":vm["contract-A/site-0"]}).known), "a VM from another contract is never borrowed")

	var malformed_context := {"id":"contract-A","targets":[{"chapter":1,"work_receipts":[{"contract_id":"contract-A","target_index":0,"member_id":"ren","backup_execution_v1":{"status":"restored","repository":"local"}}]}]}
	var malformed := BACKUP.from_context(malformed_context, 0, vm)
	check(malformed.execution.is_empty(), "incomplete historical execution receipt stays unknown")
	var changed_vm := vm.duplicate(true)
	changed_vm["contract-A/site-0"].applied.repository = "offsite"
	var after_config_change := BACKUP.from_context(context, 0, changed_vm)
	check(str(after_config_change.repository) == "offsite" and after_config_change.execution == execution and str(after_config_change.execution.files[0].path) == "/restore/orders.csv", "current config changes do not rewrite the saved employee result")

	print("STAFF_BACKUP_WORK failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
