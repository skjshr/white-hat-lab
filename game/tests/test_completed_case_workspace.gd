extends SceneTree

const GAME = preload("res://scripts/game.gd")
const WORKSPACE = preload("res://scripts/completed_case_workspace.gd")

class DesktopStub extends RefCounted:
	const CASE_WORKSPACE = preload("res://scripts/completed_case_workspace.gd")
	signal customer_requested(client: String)
	var game
	var mail_ui: Dictionary = {}
	var widgets: Dictionary = {}
	var save_ok := true
	var saves := 0
	var archive_ids: Array[String] = []
	var invoice_ids: Array[String] = []
	var contract_routes := 0
	var notices: Array[String] = []
	func _init(value): game = value
	func _save_session() -> bool: saves += 1; return save_ok
	func _notify(value: String) -> void: notices.append(value)
	func open_delivery_history(id: String) -> bool:
		if CASE_WORKSPACE.delivery_for(game.state, id).is_empty() or not _save_session(): return false
		archive_ids.append(id); return true
	func _contracts() -> void:
		if _save_session(): contract_routes += 1
	func open_invoice(id: String) -> void: invoice_ids.append(id)

var errors: Array[String] = []
var paths: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); print("FAIL ", message)

func finish() -> void:
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COMPLETED_CASE_WORKSPACE_PASS" if errors.is_empty() else "COMPLETED_CASE_WORKSPACE_FAIL ", errors)
	quit(0 if errors.is_empty() else 1)

func run() -> void:
	check(load("res://scripts/desktop.gd") != null, "desktop completion routes parse")
	var game = GAME.new()
	var stem := "user://qa-completed-case-%d" % OS.get_process_id()
	game.save_path = stem + ".json"; game.backup_path = stem + ".bak"; game.previous_path = stem + ".previous"; game.settings_path = stem + ".settings"
	paths.assign([game.save_path, game.backup_path, game.previous_path, game.settings_path])
	root.add_child(game); game.set_process(false)
	check(game.new_game(), "isolated game starts")
	game.state.career_mode = true
	game.state.current_contract_id = "job-new"
	game.state.contract = {"client":"New customer", "title":"Current job"}
	game.state.completed_ids = ["job-old", "job-new", "job-legacy"]
	game.state.last_receipt = {"client":"Wrong latest client", "title":"Wrong latest job", "profit":999999}
	game.state.history = [
		{"id":"job-old", "kind":"delivery", "client":"Old customer", "title":"Old delivered job", "day":4, "grade":"B", "profit":1234, "satisfaction_before":50, "satisfaction_after":62, "invoice_id":"invoice-old"},
		{"id":"job-new", "kind":"delivery", "client":"New customer", "title":"Current job", "day":5, "grade":"A", "profit":9000},
		{"id":"job-legacy", "kind":"delivery", "client":"Legacy customer", "title":"Legacy job"}
	]
	game.state.billing = {"invoices":[
		{"id":"invoice-wrong", "contract_id":"job-new", "status":"paid", "amount":9000},
		{"id":"invoice-old", "contract_id":"job-old", "status":"posted", "amount":1400, "reference":"BANK/OLD"},
		{"id":"invoice-draft", "contract_id":"draft-job", "status":"draft", "amount":800},
		{"id":"invoice-orphan", "contract_id":"retired-job", "status":"draft", "amount":700}
	]}
	game.state.contract_contexts = {
		"open-job":{"completed":false,"targets":[{},{}]},
		"draft-job":{"completed":true,"targets":[{}]},
		"paid-job":{"completed":true,"targets":[{}]}
	}
	game.state.maintenance_jobs = [{"id":"care-today", "client":"Care customer", "day":int(game.state.day), "status":"pending"}]
	var expected_pending := 5 # two open target jobs, two draft invoices, and today's care job
	var state_reference: Dictionary = game.state
	var billing_reference: Dictionary = game.state.billing
	var contexts_reference: Dictionary = game.state.contract_contexts
	var maintenance_reference: Array = game.state.maintenance_jobs
	var before := JSON.stringify(game.state)
	var old_view := WORKSPACE.view_for(game, "job-old")
	check(str(old_view.id) == "job-old" and str(old_view.client) == "Old customer" and str(old_view.title) == "Old delivered job", "historical view follows its exact contract id")
	check(str(old_view.grade) == "B" and int(old_view.profit) == 1234 and int(old_view.satisfaction_before) == 50 and int(old_view.satisfaction_after) == 62, "result values come from that delivery history row")
	check(str(old_view.invoice.id) == "invoice-old" and str(old_view.invoice.contract_id) == "job-old" and str(old_view.invoice.reference) == "BANK/OLD", "invoice lookup requires the same contract id")
	check(int(old_view.pending_count) == expected_pending, "pending count matches the existing company workday jobs, including draft work")
	check(JSON.stringify(game.state) == before and is_same(game.state, state_reference) and is_same(game.state.billing, billing_reference) and is_same(game.state.contract_contexts, contexts_reference) and is_same(game.state.maintenance_jobs, maintenance_reference), "view keeps the live state and nested dictionary references unchanged")
	var old_save: Dictionary = game.state.duplicate(true)
	old_save.erase("maintenance_jobs")
	old_save.care_agreements = {"Legacy Care":{"active":true,"fee":250}}
	old_save.maintenance_targets = {"Legacy Care":[{}]}
	game.state = old_save
	var old_state_reference: Dictionary = game.state
	var old_care_reference: Dictionary = game.state.care_agreements
	var old_save_before := JSON.stringify(game.state)
	var old_save_view := WORKSPACE.view_for(game, "job-old")
	check(int(old_save_view.pending_count) == expected_pending, "old save projects the unprepared current-day maintenance job into the displayed count")
	check(JSON.stringify(game.state) == old_save_before and is_same(game.state, old_state_reference) and is_same(game.state.care_agreements, old_care_reference) and not game.state.has("maintenance_jobs"), "old save display preserves original dictionary references and does not persist a prepared job")
	var missing := WORKSPACE.view_for(game, "missing-job")
	check(not bool(missing.record_available) and str(missing.grade).is_empty() and missing.profit == null and missing.satisfaction_before == null and missing.day == -1 and missing.invoice.is_empty(), "missing delivery and invoice stay explicitly unknown")
	var legacy := WORKSPACE.view_for(game, "job-legacy")
	check(bool(legacy.record_available) and legacy.day == -1 and str(legacy.grade).is_empty() and legacy.profit == null and legacy.satisfaction_after == null, "legacy history omissions remain unknown")
	game.state.current_contract_id = "job-new"; game.state.contract = {"client":"New customer", "title":"Current job"}
	check(str(WORKSPACE.view_for(game, "job-old").client) == "Old customer", "switching the active contract cannot replace the selected history")
	game.state.contract_contexts = {}; game.state.current_contract_id = ""; game.state.contract = {}
	check(str(WORKSPACE.view_for(game, "job-old").title) == "Old delivered job", "day settlement retains exact delivery view after contexts retire")
	var desktop := DesktopStub.new(game)
	var customer_count := [0]; var customer_clients: Array[String] = []
	desktop.customer_requested.connect(func(client): customer_count[0] += 1; customer_clients.append(str(client)))
	game.state.history.append({"id":"job-no-client","kind":"delivery"})
	game.state.completed_ids.append("job-no-client")
	check(not bool(WORKSPACE.view_for(game,"job-no-client").customer_available), "legacy history without a client has no customer route")
	WORKSPACE.actions_for(desktop,"job-no-client").customer.call()
	check(customer_count[0] == 0 and desktop.saves == 0, "missing client cannot open a default customer's work")
	var actions := WORKSPACE.actions_for(desktop, "job-old")
	desktop.save_ok = false
	actions.customer.call(); actions.workday.call(); actions.invoice.call(); actions.archive.call()
	check(customer_count[0] == 0 and desktop.contract_routes == 0 and desktop.invoice_ids.is_empty() and desktop.archive_ids.is_empty(), "save failure blocks every route away from the completed field")
	desktop.save_ok = true
	actions.customer.call(); actions.workday.call(); actions.invoice.call(); actions.archive.call()
	check(customer_count[0] == 1 and customer_clients == ["Old customer"] and desktop.contract_routes == 1 and desktop.invoice_ids == ["invoice-old"] and desktop.archive_ids == ["job-old"], "four exits keep the delivered customer, archive id and invoice id exact")
	var stale_actions := WORKSPACE.actions_for(desktop, "job-old")
	game.state.history = game.state.history.filter(func(row): return str(row.get("id", "")) != "job-old")
	game.state.billing.invoices = game.state.billing.invoices.filter(func(row): return str(row.get("id", "")) != "invoice-old")
	var saves_before: int = desktop.saves; var customers_before: int = customer_count[0]
	stale_actions.customer.call(); stale_actions.workday.call(); stale_actions.invoice.call(); stale_actions.archive.call()
	check(desktop.saves == saves_before + 1 and customer_count[0] == customers_before and desktop.contract_routes == 2 and desktop.invoice_ids.size() == 1 and desktop.archive_ids.size() == 1, "missing legacy record blocks case-specific routes while the company workday route uses its own single save gate")
	finish()

func _init() -> void:
	create_timer(30).timeout.connect(func(): push_error("COMPLETED_CASE_WORKSPACE_TIMEOUT"); quit(2))
	call_deferred("run")
