extends "res://tests/test_branch_equipment_native.gd"
## Extend the actual accepted branch journey, never seed an answer or company.
var source_baseline_checked := false
var share_retry_checked := false
var share_samples := 0
var inspecting_share := false
var changed_hash_checked := false

func qa_profile() -> String: return "share-diagnostic-native"
func report_name() -> String: return "share-diagnostic-native"
func journey_timeout() -> float: return 600.0

func refresh_sales() -> bool:
	if not await super.refresh_sales(): return false
	if not changed_hash_checked and ui.desktop.browser_response.contains("12900"):
		changed_hash_checked = true
		if not await connect_machine(1) or not await route("verify") or not await press("DiagnosticProbe_branch-source-orders"): return false
		var previous: Dictionary = control("ShareDiagnosticWorkbench").observation
		if not expect(previous.recorded and not previous.fresh and previous.hash_match == "match", "cross-software order edit retains old local match only as stale evidence"): return false
		var customers: Dictionary = game.diagnostic_probes().filter(func(item): return str(item.id) == "branch-source-customers")[0]
		if not expect(customers.fresh and customers.passed, "changing actual orders leaves unchanged customer original proof current"): return false
		await capture("share-original-stale-after-portal-edit")
		if not await press("DiagnosticRun"): return false
		var current: Dictionary = control("ShareDiagnosticWorkbench").observation
		if not expect(current.outcome == "hash_read" and current.hash_match == "different" and not current.passed, "actual valid 12900 business order fails local original preservation after remeasure"): return false
		await capture("share-original-changed-after-portal-edit")
		if not await connect_machine(0) or not await route("browser"): return false
	return true

func connect_machine(index: int) -> bool:
	if not await super.connect_machine(index): return false
	if index == 1 and not source_baseline_checked:
		source_baseline_checked = true
		if not await route("verify"): return false
		for id in ["branch-source-orders", "branch-source-customers", "staff-read", "guest-read"]:
			if not await press("DiagnosticProbe_" + id): return false
			var bench = control("ShareDiagnosticWorkbench")
			if not expect(bench != null and not bool(bench.observation.recorded), "source baseline starts without invented measured access or SHA " + id): return false
			if not await press("DiagnosticRun"): return false
			var value: Dictionary = control("ShareDiagnosticWorkbench").observation
			if id.begins_with("branch-source-"):
				if not expect(value.outcome == "hash_read" and value.hash_match == "match" and value.transport == "local", "actual local source original intact before unavailable SMB is repaired"): return false
			else:
				if not expect(value.outcome == "share_missing" and value.stop_at == "share" and value.files.is_empty(), "actual share outage does not become ACL refusal or file-content evidence"): return false
				if id == "guest-read" and not expect(bool(value.passed), "public DENIED acceptance remains distinct from actual missing share"): return false
			await capture("share-baseline-" + id)
		var before: Dictionary = game._vm().export_state()
		if not expect(ui.desktop._save_session() and game.save_game(), "save actual local match and unavailable share checkpoint"): return false
		ui.queue_free(); await frames(6)
		if not expect(game.load_game(), "reload interrupted shared diagnosis"): return false
		game.set_process(false); await build_ui()
		if not await route("verify"): return false
		if not expect(control("ShareDiagnosticWorkbench").observation.outcome == "share_missing", "resume selects actual saved missing-share observation"): return false
		# JSON persistence normalizes numeric types. Compare the same serialized
		# representation, rather than declaring an int/float distinction data loss.
		if not expect(JSON.parse_string(JSON.stringify(game._vm().export_state())) == JSON.parse_string(JSON.stringify(before)), "resume retains actual share failure, acceptance and preserved file bytes"): return false
		await capture("share-baseline-resumed")
	return true

func press(id: String) -> bool:
	if id in ["SambaSave", "SambaRestart"] and int(game.state.get("target_index", -1)) == 1:
		var clicked: bool = await super.press(id)
		if not clicked: return false
		var original: Dictionary = game.diagnostic_probes().filter(func(item): return str(item.id) == "branch-source-orders")[0]
		if not expect(original.fresh and original.passed and str(original.get("fingerprint_kind", "")) == "local-file-v1", "actual share draft/apply preserves unchanged local original " + id): return false
		await capture("original-current-after-" + id)
		return true
	if id != "DiagnosticRun" or inspecting_share or int(game.state.get("target_index", -1)) != 1: return await super.press(id)
	var bench = control("ShareDiagnosticWorkbench")
	if bench == null: return await super.press(id)
	var selected: String = str(ui.desktop.widgets.verify.selected)
	if selected == "staff-write" and not share_retry_checked:
		# The last local measurement was the changed 12900 order. Restore made
		# that failure historical; actually remeasure the restored original first.
		if not await super.press("DiagnosticProbe_branch-source-orders") or not await super.press("DiagnosticRun"): return false
		var original: Dictionary = game.diagnostic_probes().filter(func(item): return str(item.id) == "branch-source-orders")[0]
		if not expect(original.fresh and original.passed, "actual restored original remeasured before another-file PUT"): return false
		await capture("original-remeasured-before-other-put")
		if not await super.press("DiagnosticProbe_staff-write"): return false
		bench = control("ShareDiagnosticWorkbench")
		var before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
		var durable: Dictionary = bench.observation.duplicate(true); var path: String = game.save_path
		game.save_path = "user://missing-share-diagnostic-%d/save.json" % OS.get_process_id()
		var clicked: bool = await super.press(id)
		game.save_path = path
		if not clicked: return false
		if not expect(game._vm().export_state() == before and int(game.state.cash) == cash and game.business_clock() == clock, "failed actual SMB PUT save rolls back customer bytes, work, funds and clock"): return false
		if not expect(shown("DiagnosticOperationFailure") and control("ShareDiagnosticWorkbench").observation == durable, "failed SMB persistence displays exact prior durable observation"): return false
		await capture("share-put-save-failed")
		share_retry_checked = true
	if not await super.press(id): return false
	share_samples += 1
	return await inspect_share(selected)

func inspect_share(id: String) -> bool:
	inspecting_share = true
	var ok := await _inspect_share(id)
	inspecting_share = false
	return ok

func _inspect_share(id: String) -> bool:
	var bench = control("ShareDiagnosticWorkbench")
	if not await scroll_to(bench): return false
	if not expect(clipped_rect(bench).grow(1).encloses(bench.get_global_rect()), "whole share specimen bench fits actual native viewport and text size"): return false
	for object in bench.objects.values():
		if not expect(bench.get_global_rect().grow(1).encloses(object.get_global_rect()) and clipped_rect(object).grow(1).encloses(object.get_global_rect()), "each graphical access/file/seal object is reachable"): return false
	var value: Dictionary = bench.observation.duplicate(true)
	if not expect(is_equal_approx(float(game.settings.text_scale), 1.3 if narrow else 1.0) and is_equal_approx(float(bench.scale_factor), 1.3 if narrow else 1.0), "actual share diagram respects requested game text scale"): return false
	var probe: Dictionary = game.diagnostic_probes().filter(func(item): return str(item.id) == id)[0]
	if not expect(value.recorded and value.fresh and value.passed == probe.passed, "graphic keeps saved actual response and authoritative public verdict"): return false
	if id == "staff-write":
		if not expect(value.outcome == "written" and game.vm_read("/srv/share/orders.csv") == game.vm_read("/srv/data/orders.csv") and value.hash.is_empty(), "actual PUT changes real shared bytes but never fabricates their hash from receipt"): return false
		var original: Dictionary = game.diagnostic_probes().filter(func(item): return str(item.id) == "branch-source-orders")[0]
		if not expect(original.fresh and original.passed, "actual PUT of another file preserves unchanged source-original measurement"): return false
	elif id == "staff-read" and source_baseline_checked and str(value.outcome) == "listed":
		if not expect(value.files.has("report.txt") and value.files.has("orders.csv") and value.hash.is_empty(), "actual post-repair LS names reflect prior real PUT without claiming content match"): return false
	elif id.begins_with("guest") and str(value.outcome) != "share_missing":
		if not expect(value.outcome == "access_denied" and value.stop_at == "operation" and value.passed, "real guest ACL refusal is a different measured stage from missing share"): return false
	await capture("share-%02d-" % share_samples + id + "-objects")
	var before: Dictionary = game._vm().export_state(); var cash := int(game.state.cash); var clock: String = game.business_clock()
	if not await press("DiagnosticReplayObservation"): return false
	if not expect(control("ShareDiagnosticWorkbench").replay_position >= 0, "recorded access replay animates without a new request"): return false
	for object in ["request", "gate", "specimen", "seal"]:
		if not await press("DiagnosticObject_" + object): return false
		var inspector = control("DiagnosticInspector")
		if not expect(shown("DiagnosticInspector") and clipped_rect(inspector).grow(1).encloses(inspector.get_global_rect()), "shape selection reveals complete actual share evidence " + object): return false
		if not expect(control("DiagnosticActual").tooltip_text == str(probe.result), "object inspector preserves exact saved raw response"): return false
	if not await keyboard_activate("DiagnosticObject_gate", str(value.protocol) == "smb") or not await press("DiagnosticInspectorClose"): return false
	if not await press("DiagnosticCompare"): return false
	if not expect(shown("DiagnosticLatest") and control("DiagnosticLatest").text == str(probe.result), "first/latest on-demand display retains full actual response"): return false
	if not await press("DiagnosticCompare"): return false
	await frames(90)
	if not expect(control("ShareDiagnosticWorkbench").replay_position < 0 and game._vm().export_state() == before and int(game.state.cash) == cash and game.business_clock() == clock, "finite replay, selection and raw comparison never change real work or customer state"): return false
	return true
