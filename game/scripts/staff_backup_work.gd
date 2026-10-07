extends RefCounted
## Read-only projection of the saved backup plan and Ren's saved execution.
## It never creates a VM, measures state, or repairs legacy data.

static func _repository(value: Variant) -> String:
	var repository := str(value)
	return repository if repository in ["local", "offsite"] else ""


static func _schedule(value: Variant) -> String:
	var schedule := str(value)
	if schedule == "daily": return "daily"
	if schedule == "off": return "disabled"
	return ""


static func _integer_count(value: Variant) -> int:
	if typeof(value) == TYPE_DICTIONARY: return value.size()
	if typeof(value) == TYPE_ARRAY: return value.size()
	return -1


static func _saved_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and floorf(float(value)) == float(value)


static func _current_files(fs_value: Variant, target: String) -> Array:
	if not fs_value is Dictionary or target.is_empty(): return []
	var prefix := target.trim_suffix("/") + "/"
	var paths: Array[String] = []
	for raw_path in fs_value.keys():
		var path := str(raw_path)
		if path.begins_with(prefix): paths.append(path)
	paths.sort()
	return paths


static func _valid_execution(value: Variant) -> bool:
	if not value is Dictionary: return false
	var receipt: Dictionary = value
	for key in ["status", "repository", "schedule", "source", "snapshot", "target", "files", "error", "backup_created"]:
		if not receipt.has(key): return false
	if str(receipt.status) not in ["restored", "selection_required", "failed"]: return false
	if str(receipt.repository) not in ["", "local", "offsite"]: return false
	if str(receipt.schedule) not in ["", "daily", "off"]: return false
	if str(receipt.source) != "/srv/data" or not receipt.snapshot is String or not receipt.target is String or not receipt.error is String:
		return false
	if not receipt.backup_created is bool or not receipt.files is Array: return false
	for file_value in receipt.files:
		if not file_value is Dictionary: return false
		var file: Dictionary = file_value
		for key in ["source", "path", "status"]:
			if not file.has(key) or not file[key] is String: return false
	return true


static func _latest_ren_execution(target: Dictionary, contract_id: String, target_index: int) -> Dictionary:
	var receipts_value: Variant = target.get("work_receipts", null)
	if not receipts_value is Array: return {}
	# Work receipts are durable, per-member records. Require both identities so a
	# similarly indexed target from another contract can never leak into this one.
	for i in range(receipts_value.size() - 1, -1, -1):
		var receipt_value: Variant = receipts_value[i]
		if not receipt_value is Dictionary: continue
		var receipt: Dictionary = receipt_value
		if str(receipt.get("member_id", "")) != "ren" and str(receipt.get("role", "")) != "ren": continue
		if str(receipt.get("contract_id", "")) != contract_id or int(receipt.get("target_index", -1)) != target_index: continue
		var execution_value: Variant = receipt.get("backup_execution_v1", null)
		return execution_value.duplicate(true) if _valid_execution(execution_value) else {}
	return {}


static func from_context(context: Dictionary, target_index: int, vm_states: Dictionary) -> Dictionary:
	var targets_value: Variant = context.get("targets", null)
	if not targets_value is Array or target_index < 0 or target_index >= targets_value.size(): return {}
	var target_value: Variant = targets_value[target_index]
	if not target_value is Dictionary: return {}
	var target: Dictionary = target_value
	if int(target.get("chapter", -1)) != 1: return {}

	var contract_id := str(context.get("id", ""))
	var vm_key := contract_id + "/site-" + str(target_index)
	var vm_value: Variant = vm_states.get(vm_key, null)
	var vm: Dictionary = vm_value if vm_value is Dictionary else {}
	var applied_value: Variant = vm.get("applied", null)
	var applied: Dictionary = applied_value if applied_value is Dictionary else {}
	var snapshots_value: Variant = vm.get("snapshots", null)
	var snapshots: Array = []
	var snapshots_known := snapshots_value is Array
	if snapshots_known:
		for snapshot_value in snapshots_value:
			if not snapshot_value is Dictionary: continue
			var snapshot: Dictionary = snapshot_value
			var snapshot_id_value: Variant = snapshot.get("id", null)
			var repository := _repository(snapshot.get("repository", ""))
			var files_value: Variant = snapshot.get("files", null)
			if snapshot_id_value == null or repository.is_empty(): snapshots_known = false
			snapshots.append({"id":str(snapshot_id_value) if snapshot_id_value != null else "","repository":repository,"file_count":_integer_count(files_value)})

	var scenario_value: Variant = target.get("scenario", null)
	var scenario: Dictionary = scenario_value if scenario_value is Dictionary else {}
	var desired_value: Variant = scenario.get("desired", null)
	var desired: Dictionary = desired_value if desired_value is Dictionary else {}
	if desired.is_empty():
		var saved_scenario_value: Variant = vm.get("scenario", null)
		if saved_scenario_value is Dictionary:
			var saved_desired_value: Variant = saved_scenario_value.get("desired", null)
			if saved_desired_value is Dictionary: desired = saved_desired_value
	var desired_repository := _repository(desired.get("repository", ""))
	var desired_schedule := _schedule(desired.get("schedule", ""))
	var repository := _repository(applied.get("repository", ""))
	var schedule := _schedule(applied.get("schedule", ""))
	var has_runtime_flags := vm.has("active") and vm.has("dirty") and typeof(vm.active) == TYPE_BOOL and typeof(vm.dirty) == TYPE_BOOL
	var model_version_value: Variant = vm.get("backup_model_version", null)
	var model_version_known := vm.has("backup_model_version") and _saved_integer(model_version_value)
	var known := not vm.is_empty() and not applied.is_empty() and not repository.is_empty() and not schedule.is_empty() and snapshots_known and has_runtime_flags and model_version_known
	var restore: Dictionary = {}
	var last_restore_value: Variant = vm.get("last_restore", null)
	if last_restore_value is Dictionary and not last_restore_value.is_empty():
		var last_restore: Dictionary = last_restore_value
		var snapshot_id := str(last_restore.get("snapshot", ""))
		var restore_target := str(last_restore.get("target", ""))
		var restore_repository := ""
		for snapshot in snapshots:
			if str(snapshot.get("id", "")) == snapshot_id:
				restore_repository = str(snapshot.get("repository", ""))
				break
		var current_paths := _current_files(vm.get("fs", null), restore_target)
		var fs_known := vm.get("fs", null) is Dictionary and not restore_target.is_empty()
		restore = {"snapshot":snapshot_id,"repository":restore_repository,"target":restore_target,"file_count":current_paths.size() if fs_known else -1,"paths":current_paths,"current_files":fs_known}
	var requires_selection: bool = int(vm.get("backup_model_version", 1)) >= 2 and snapshots_value is Array and snapshots_value.size() > 1
	return {"available":true,"known":known,"snapshots_known":snapshots_known,"source":"/srv/data","repository":repository,"schedule":schedule,"desired_repository":desired_repository,"desired_schedule":desired_schedule,"active":bool(vm.get("active", false)),"dirty":bool(vm.get("dirty", false)),"snapshots":snapshots,"restore":restore,"requires_selection":requires_selection,"execution":_latest_ren_execution(target, contract_id, target_index)}
