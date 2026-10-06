extends "res://tests/test_saas_partner.gd"
## Uses a read-only native delivery and its ordinary follow-up. Comparisons are
## created only by public actions; this model test does not replace UI play.
const SAAS_ENGINE = preload("res://scripts/saas_response.gd")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_ASSISTANT_COMPARE: " + label)

func load_source() -> bool:
	game = root.get_node("Game"); game.set_process(false)
	var prefix := "user://qa-saas-assistant-compare-%s" % OS.get_process_id()
	paths.assign([prefix + ".json", prefix + ".json.bak", prefix + ".json.previous", prefix + ".settings"])
	set_paths(paths)
	source_path = OS.get_environment("WHL_SAAS_PARTNER_SOURCE")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		check(false, "WHL_SAAS_PARTNER_SOURCE identifies the read-only native v2 delivery"); return false
	source_hash = FileAccess.get_sha256(source_path)
	var file := FileAccess.open(paths[0], FileAccess.WRITE)
	if file == null: check(false, "the isolated QA copy can be written"); return false
	file.store_string(FileAccess.get_file_as_string(source_path)); file.close()
	if not game.load_game(): check(false, "the native delivery loads through its QA copy"); return false
	source_id = str(game.state.current_contract_id)
	source_history = encoded(source_record())
	check(game.current_done() and str(game.state.advanced.get("model_version", "")) == "saas-sessions-v2", "the actual source keeps its completed v2 model")
	return true

func legacy_organization() -> void:
	var old_world := encoded(game.state.advanced)
	var old_organization: Dictionary = game.state.advanced.get("organization", {}).duplicate(true)
	check(not str(old_organization.get("input_hash", "")).is_empty(), "the native fixture includes an actual pre-comparison organization")
	for _i in 3: game.advanced_view()
	check(game.save_game() and game.load_game() and encoded(game.state.advanced) == old_world and encoded(source_record()) == source_history, "reading and JSON-resuming an older organization never recalculates the saved result or its delivery")
	# Explicit schema fixture only: v1 predates optional scheduled business. Keep
	# its actual records and organization; never manufacture a successful result.
	var legacy: Dictionary = game.state.advanced.duplicate(true)
	legacy.model_version = "saas-sessions-v1"; legacy.session_case.version = 1
	legacy.session_case.erase("business")
	legacy = JSON.parse_string(JSON.stringify(legacy))
	var frozen := encoded(legacy)
	var view: Dictionary = SAAS_ENGINE.view(legacy)
	var result: Dictionary = SAAS_ENGINE.act(legacy, "organize_records", {"mode":str(old_organization.get("mode", "assistant")),"record_ids":old_organization.get("record_ids", [])})
	check(view.get("checks", []).size() == 6 and encoded(view.get("saas", {}).get("organization", {})) == encoded(old_organization) and bool(result.get("ok", false)) and not bool(result.get("changed", true)) and encoded(legacy) == frozen, "v1 compatibility projection and an identical organization request preserve the old result without a charge")

func organization_view() -> Dictionary:
	return game.advanced_view().get("saas", {}).get("organization", {})

func comparison() -> Dictionary:
	return organization_view().get("comparison", {})

func matches(snapshot: Dictionary) -> Dictionary:
	var result := {}
	for lane in snapshot.get("lanes", []):
		result[str(lane.get("session_id", ""))] = str(lane.get("approval_match", ""))
	return result

func selected_citations(snapshot: Dictionary, ids: Array) -> bool:
	var references: Array = [str(snapshot.get("approval", {}).get("current_record_id", ""))]
	for prior in snapshot.get("approval", {}).get("prior", []):
		references.append(str(prior.get("reference_record_id", "")))
	for lane in snapshot.get("lanes", []):
		for field in ["issued_record_id", "inspection_record_id", "approval_record_id"]:
			references.append(str(lane.get(field, "")))
		references.append(str(lane.get("prior_issue", {}).get("record_id", "")))
	for id in references:
		if not str(id).is_empty() and id not in ids: return false
	return not snapshot.is_empty() and encoded(snapshot.get("record_ids", [])) == encoded(ids)

func organize(ids: Array) -> Dictionary:
	var minutes := int(game.state.work.minutes)
	var usage := cost("usage_cost")
	var observed_before: Array = game.state.advanced.get("records", []).filter(func(row): return str(row.get("action", "")) in ["inspect_connection", "probe_session"])
	var result := action("organize_records", {"mode":"assistant", "record_ids":ids})
	var observed_after: Array = game.state.advanced.get("records", []).filter(func(row): return str(row.get("action", "")) in ["inspect_connection", "probe_session"])
	check(bool(result.get("ok", false)) and bool(result.get("changed", false)) and int(game.state.work.minutes) == minutes + 2 and cost("usage_cost") == usage + 300 and encoded(observed_after) == encoded(observed_before), "an explicit comparison costs two minutes and one assistant use without inventing investigation or measurement")
	return comparison()

func comparison_flow() -> void:
	var originals: Array = ["audit-1", "audit-2", "audit-3", "audit-4"]
	for record in game.advanced_view().get("saas", {}).get("records", []):
		if str(record.get("action", "")) == "baseline_reference": originals.append(str(record.get("id", "")))
	var unobserved := organize(originals)
	check(matches(unobserved) == {"SES-201":"unknown", "SES-202":"unknown", "SES-203":"unknown"} and not encoded(unobserved).contains("partner-vault/archive") and selected_citations(unobserved, originals), "issued and prior originals cannot reveal the three uninspected requests or identify the hidden archive destination")
	var inspections: Array = []
	for id in ["SES-201", "SES-202", "SES-203"]:
		inspections.append(str(observe("inspect_connection", {"session_id":id}, 200).get("id", "")))
	var no_approval := organize(inspections)
	check(matches(no_approval) == {"SES-201":"unknown", "SES-202":"unknown", "SES-203":"unknown"} and str(no_approval.get("approval", {}).get("state", "")) == "unknown" and no_approval.get("approval", {}).get("destinations", []).is_empty() and selected_citations(no_approval, inspections), "inspection-only input cannot borrow the unselected approval or cite unselected issuance originals")
	var selected := originals.duplicate(); selected.append_array(inspections)
	var full := organize(selected)
	check(matches(full) == {"SES-201":"mismatch", "SES-202":"match", "SES-203":"match"} and selected_citations(full, selected) and str(full.get("approval", {}).get("current_record_id", "")) == "audit-1" and bool(organization_view().get("comparison_fresh", false)) and not bool(full.get("creates_evidence", true)) and not game.can_deliver(), "the selected current approval and real requests explain all three matches without replacing required containment or measurement")
	var saved := encoded(game.state.advanced.organization)
	var pure := encoded(game.state)
	for _i in 3: game.advanced_view()
	var detached := comparison()
	if not detached.get("lanes", []).is_empty(): detached.lanes[0].approval_match = "changed-in-view"
	check(encoded(game.state) == pure and encoded(game.state.advanced.organization) == saved, "repeated projections and edits to returned comparison data do not recompute or alter the saved analysis")
	var repeated := action("organize_records", {"mode":"assistant", "record_ids":selected})
	check(bool(repeated.get("ok", false)) and not bool(repeated.get("changed", true)) and encoded(game.state) == pure, "redisplaying the same selected originals is a free unchanged result")
	check(game.save_game() and game.load_game() and encoded(game.state.advanced.organization) == saved and encoded(comparison()) == encoded(full), "the exact comparison and citations survive JSON resume without recalculation")
	observe("revoke_connection", {"session_id":"SES-201"}, 200)
	var stale_view := organization_view()
	check(encoded(game.state.advanced.organization) == saved and str(stale_view.get("comparison_state", "")) == "stale" and not bool(stale_view.get("comparison_fresh", true)) and stale_view.get("comparison", {}).get("lanes", []).all(func(lane): return not bool(lane.get("inspection_fresh", true))), "revocation changes the live generation while the prior comparison and observations remain visibly stale")
	var stale_state := encoded(game.state)
	repeated = action("organize_records", {"mode":"assistant", "record_ids":selected})
	check(bool(repeated.get("ok", false)) and not bool(repeated.get("changed", true)) and encoded(game.state) == stale_state and str(organization_view().get("comparison_state", "")) == "stale", "retrying the old input cannot charge again or relabel stale evidence as a current measurement")
	var fresh_probe := observe("probe_session", {"session_id":"SES-201"}, 403)
	selected.append(str(fresh_probe.get("id", "")))
	failed_save(func(): return action("organize_records", {"mode":"assistant", "record_ids":selected}), "failed comparison save restores analysis, original records, clock and all costs together")
	check(game.save_game() and game.load_game() and encoded(game.state.advanced.organization) == saved and str(organization_view().get("comparison_state", "")) == "stale" and encoded(source_record()) == source_history, "stale analysis resumes intact and never rewrites the previous customer's accepted report")

func run() -> void:
	if not load_source(): finish(); return
	legacy_organization()
	check(game.end_day(), "ordinary next-day settlement publishes the customer follow-up")
	var offer := partner_offer()
	if offer.is_empty() or not available_partner(): check(false, "the earned partner offer is available"); finish(); return
	check(game.set_offer_quote(str(offer.id), int(game.contract_quote(offer).estimated_fee)) and game.choose_contract(str(offer.id)), "quote and accept the real partner follow-up")
	check(game.buy_record_assistant() and bool(game.record_assistant_status().owned), "the company owns the assistant through its purchase API")
	comparison_flow()
	finish()

func finish() -> void:
	if not source_hash.is_empty(): check(FileAccess.get_sha256(source_path) == source_hash, "the native source file remains byte-for-byte unchanged")
	for path in paths + [str(paths[0]) + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SAAS_ASSISTANT_COMPARE_TEST_PASS" if failures.is_empty() else "SAAS_ASSISTANT_COMPARE_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
