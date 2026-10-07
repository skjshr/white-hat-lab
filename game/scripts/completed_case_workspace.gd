extends RefCounted
## Read-only company handoff shown when a customer workspace is already delivered.
const COMPANY_WORKDAY = preload("res://scripts/company_workday.gd")
const CANVAS = preload("res://scripts/completed_case_canvas.gd")

static func current_id(game) -> String:
	return str(game.state.get("current_contract_id", "")) if bool(game.state.get("career_mode", false)) else str(game.mission().get("id", ""))

static func delivery_for(state: Dictionary, contract_id: String) -> Dictionary:
	if contract_id.is_empty() or contract_id not in state.get("completed_ids", []): return {}
	for raw in state.get("history", []):
		if raw is Dictionary and str(raw.get("id", "")) == contract_id and str(raw.get("kind", "delivery")) == "delivery": return raw.duplicate(true)
	return {}

static func invoice_for(state: Dictionary, contract_id: String, receipt: Dictionary = {}) -> Dictionary:
	if contract_id.is_empty(): return {}
	var invoices: Variant = state.get("billing", {}).get("invoices", [])
	if not invoices is Array: return {}
	var preferred := str(receipt.get("invoice_id", ""))
	var fallback: Dictionary = {}
	for raw in invoices:
		if not raw is Dictionary or str(raw.get("contract_id", "")) != contract_id: continue
		if not preferred.is_empty() and str(raw.get("id", "")) == preferred: return raw.duplicate(true)
		if fallback.is_empty(): fallback = raw.duplicate(true)
	return fallback

static func _pending_count(game) -> int:
	# Workday's existing read model prepares contract and care-job state. Project
	# once on an unattached Game with copied inputs so rendering cannot mutate the
	# live state or its nested dictionaries. A VM is intentionally not copied:
	# pending/draft job counts do not depend on VM measurements.
	var projection = game.get_script().new()
	projection.state = game.state.duplicate(true)
	projection.settings = game.settings.duplicate(true)
	projection._assignments = game._assignments.duplicate(true)
	projection._crew_runtime_available = game._crew_runtime_available.duplicate(true)
	projection._crew_runtime_registered = game._crew_runtime_registered.duplicate(true)
	# Older saves can lack the array; workday preparation expects it to exist.
	if not projection.state.has("maintenance_jobs"): projection.state["maintenance_jobs"] = []
	var jobs: Array = COMPANY_WORKDAY.snapshot(projection).get("jobs", [])
	projection.free()
	var count := 0
	for job in jobs:
		if not bool(job.get("completed", false)) or bool(job.get("draft", false)): count += 1
	return count

static func view_for(game, contract_id: String) -> Dictionary:
	var record := delivery_for(game.state, contract_id)
	var contract: Dictionary = game.state.get("contract", {}) if str(game.state.get("current_contract_id", "")) == contract_id else {}
	var invoice := invoice_for(game.state, contract_id, record)
	var view := {
		"id":contract_id,
		"client":str(record.get("client", contract.get("client", "不明"))),
		"title":str(record.get("title", contract.get("title", "不明"))),
		"day":int(record.get("day", -1)) if record.has("day") else -1,
		"grade":str(record.get("grade", "")),
		"profit":record.get("profit", record.get("net", null)),
		"satisfaction_before":record.get("satisfaction_before", null),
		"satisfaction_after":record.get("satisfaction_after", null),
		"record_available":not record.is_empty(),
		"customer_available":not str(record.get("client", "")).is_empty(),
		"invoice":invoice,
		"pending_count":_pending_count(game)
	}
	return view

static func render(d, parent: VBoxContainer) -> void:
	var id := current_id(d.game)
	var view := view_for(d.game, id)
	var actions := actions_for(d, id)
	var canvas := CANVAS.new()
	canvas.name = "CompletedCaseCanvas"
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(canvas)
	canvas.configure(view, float(d.game.settings.get("text_scale", 1.0)), actions)

static func actions_for(d, contract_id: String) -> Dictionary:
	return {
		"archive":func(): _open_archive(d, contract_id),
		"customer":func(): _open_customer(d, contract_id),
		"workday":func(): _open_workday(d, contract_id),
		"invoice":func(): _open_invoice(d, contract_id)
	}

static func _notify(d, message: String) -> void:
	if is_instance_valid(d) and d.has_method("_notify"): d._notify(message)

static func _prepare_exit(d, contract_id: String, invoice_required := false) -> bool:
	if delivery_for(d.game.state, contract_id).is_empty():
		_notify(d, "この案件の納品履歴を確認できません。")
		return false
	var invoice := invoice_for(d.game.state, contract_id, delivery_for(d.game.state, contract_id))
	if invoice_required and invoice.is_empty():
		_notify(d, "この案件の請求記録を確認できません。")
		return false
	return d._save_session()

static func _open_archive(d, contract_id: String) -> void:
	if d.has_method("open_delivery_history"):
		d.open_delivery_history(contract_id)
	else:
		_notify(d, "この案件の納品履歴を確認できません。")

static func _open_customer(d, contract_id: String) -> void:
	var record := delivery_for(d.game.state, contract_id)
	if record.is_empty(): _notify(d, "この案件の納品履歴を確認できません。"); return
	if str(record.get("client", "")).is_empty(): _notify(d, "この案件の顧客記録を確認できません。"); return
	if not _prepare_exit(d, contract_id): return
	d.customer_requested.emit(str(record.get("client", "")))

static func _open_workday(d, contract_id: String) -> void:
	# This is a company-wide route, so it remains available even when an old
	# delivery row is missing. _contracts owns its save gate.
	d._contracts()

static func _open_invoice(d, contract_id: String) -> void:
	var invoice := invoice_for(d.game.state, contract_id, delivery_for(d.game.state, contract_id))
	if invoice.is_empty(): _notify(d, "この案件の請求記録を確認できません。"); return
	if not _prepare_exit(d, contract_id, true): return
	d.open_invoice(str(invoice.get("id", "")))
