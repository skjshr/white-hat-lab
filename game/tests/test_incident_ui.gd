extends "res://tests/test_invoice_service_ui.gd"
## Exercise targets are selected from observed audit/session/version data only.
## Parent state snapshots are assertions of isolation, never a source of answers.

var original_case: Dictionary = {}
var original_company: Dictionary = {}
var original_request_draft: Dictionary = {}
var original_invoice_drafts: Dictionary = {}
var run_request_draft: Dictionary = {}
var exercise_id := ""
var target_invoice := ""
var observed_session := ""
var normal_session := ""
var anomaly: Dictionary = {}
var initial_invoice: Dictionary = {}
var before_restoration: Dictionary = {}
var initial_fingerprint := ""

func exercise() -> Dictionary:
	return game.advanced_view().get("exercise", {})

func observed_events() -> Array:
	return exercise().get("events", [])

func observed_sessions() -> Array:
	return exercise().get("sessions", [])

func parent_case() -> Dictionary:
	var parent: Dictionary = game.state.advanced.duplicate(true)
	parent.erase("exercise")
	return JSON.parse_string(JSON.stringify(parent))

func company_state() -> Dictionary:
	var out: Dictionary = {}
	for key in ["cash", "profit", "clock_minutes", "work", "checks", "validated_revision", "inspected", "current_contract_id", "completed_ids", "billing"]:
		out[key] = game.state.get(key)
	return JSON.parse_string(JSON.stringify(out))

func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func normal_case_unchanged(label: String) -> void:
	check(parent_case() == original_case, label + " preserves original model, evidence, history and report")
	check(company_state() == original_company, label + " preserves company time, work, checks and finances")

func incident_press(id: String, twice := false) -> void:
	await press(id, true, twice)

func incident_tab(id: String) -> void:
	await incident_press("IncidentTab_" + id)

func choose(id: String, metadata: Variant) -> void:
	var node := control(id) as OptionButton
	check(is_instance_valid(node), "selector " + id)
	if not is_instance_valid(node): return
	await reachable(node, id)
	for index in node.item_count:
		if str(node.get_item_metadata(index)) == str(metadata):
			node.select(index); node.item_selected.emit(index); signal_clicks += 1
			await idle(); return
	check(false, "public option exists " + id + " " + str(metadata))

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless" or not failures.is_empty(): return
	await frames(8); await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../../audit/incident-response/e2e/screens")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func open_observed_invoice(id: String) -> Dictionary:
	await tab("portal")
	var username := str(anomaly.get("principal", "alice"))
	var current := str(pc.pentest_ui.get("portal_user", {}).get("username", ""))
	if not current.is_empty() and current != username: await press("InvoiceLogout")
	if control("InvoiceLoginSubmit") != null:
		var accounts: Array = game.advanced_view().get("accounts", [])
		var matching_accounts: Array = accounts.filter(func(row): return str(row.get("username", "")) == username)
		check(not matching_accounts.is_empty(), "observed principal has a supplied fictional account")
		if matching_accounts.is_empty() or not await login(username, str(matching_accounts[0].get("password", ""))): return {}
	if control("InvoiceCancel") != null: await press("InvoiceCancel")
	await press("PentestPortalLoad")
	if control("InvoiceSearch") != null:
		await type_text("InvoiceSearch", id); await press("InvoiceSearchSubmit", true)
	var listed: Array = response_data().get("invoices", [])
	check(listed.any(func(row): return str(row.get("id", "")) == id), "observed target appears in authenticated business list")
	if not listed.any(func(row): return str(row.get("id", "")) == id): return {}
	await press("PentestInvoice_" + id.validate_node_name(), true)
	check(status() == 200 and str(response_data().get("id", "")) == id, "invoice display comes from a real matching GET")
	return response_data().duplicate(true)

func prepare_original_drafts() -> bool:
	if not await login("alice", "Alice-demo-27"): return false
	var invoices: Array = response_data().get("invoices", [])
	var editable: Array = invoices.filter(func(row): return str(row.get("state", "")) == "draft" and str(row.get("owner", "")) == "alice")
	check(not editable.is_empty(), "normal account has an observed editable invoice")
	if editable.is_empty(): return false
	await press("PentestInvoice_" + str(editable[0].id).validate_node_name())
	await press("InvoiceEdit")
	await type_text("InvoiceNotes", "NORMAL CASE pending notes")
	await tab("request")
	await type_text("PentestPath", "/api/invoices/normal-unsent-request")
	await type_text("PentestBody", "{\"note\":\"NORMAL unsent body\"}")
	original_request_draft = pc.pentest_ui.draft.duplicate(true)
	original_invoice_drafts = pc.pentest_ui.service.drafts.duplicate(true)
	check(pc._save_session(), "store original case drafts before exercise")
	original_case = parent_case(); original_company = company_state()
	return failures.is_empty()

func select_event(event: Dictionary) -> void:
	await incident_tab("events")
	if control("IncidentEventBack") != null: await incident_press("IncidentEventBack")
	await incident_press("IncidentEvent_" + str(event.get("id", "")).validate_node_name())
	var detail := control("IncidentEventDetail")
	check(is_instance_valid(detail) and str(detail.get_meta("event_id", "")) == str(event.get("id", "")), "event selection identifies the observed record")

func select_session(id: String) -> void:
	await incident_tab("sessions")
	if control("IncidentSessionBack") != null: await incident_press("IncidentSessionBack")
	await incident_press("IncidentSession_" + id.validate_node_name())
	var detail := control("IncidentSessionDetail")
	check(is_instance_valid(detail) and str(detail.get_meta("session_id", "")) == id, "session selection matches the correlated public session")

func start_and_observe() -> bool:
	await tab("operations")
	await choose("IncidentVariant", "mixed")
	await type_text("IncidentSeed", "101")
	await capture("00-start-entry")
	await incident_press("IncidentStart", true)
	exercise_id = str(exercise().get("run_id", ""))
	check(not exercise_id.is_empty() and bool(exercise().get("active", false)), "explicit start opens one exercise")
	check(int(exercise().get("tick", -1)) == 0, "double start does not advance the new exercise")
	check(str(pc.pentest_ui.get("_context_key", "")) == exercise_id, "exercise has a separate UI context")
	normal_case_unchanged("exercise start")
	await incident_tab("events")
	await incident_press("IncidentRefresh")
	var patches: Array = observed_events().filter(func(row): return str(row.get("method", "")) == "PATCH" and int(row.get("status", 0)) in [200, 201])
	check(not patches.is_empty(), "the anomaly is an actual successful HTTP write")
	if patches.is_empty(): return false
	# The public brief says unit-price changes were not requested. The request
	# and changed field, not a private actor classification, identify the lead.
	var candidates: Array = patches.filter(func(row): return row.get("changes", {}).has("line_items"))
	check(not candidates.is_empty(), "audit discloses the unexpected line-item change")
	if candidates.is_empty(): return false
	anomaly = candidates[0].duplicate(true)
	target_invoice = str(anomaly.get("invoice_id", "")); observed_session = str(anomaly.get("session_id", ""))
	check(not target_invoice.is_empty() and not observed_session.is_empty(), "observed audit record links invoice and session")
	initial_fingerprint = JSON.stringify([target_invoice, anomaly.get("device", ""), anomaly.get("source", ""), anomaly.get("path", "")])
	await select_event(anomaly); await incident_press("IncidentPinEvent", true)
	var notes: Array = observed_events().filter(func(row): return str(row.get("kind", "")) == "customer_note")
	check(not notes.is_empty(), "customer work authorization is independently observable")
	if not notes.is_empty():
		await select_event(notes[0]); await incident_press("IncidentPinEvent")
		await capture("00-customer-authorization")
	await select_event(anomaly)
	await capture("01-observed-anomaly")
	if narrow:
		var detail := control("IncidentEventDetail") as Control
		if is_instance_valid(detail) and detail.get_child_count() > 0:
			await reachable(detail.get_child(detail.get_child_count() - 1) as Control, "observed field changes")
		await capture("01-observed-change")
	initial_invoice = await open_observed_invoice(target_invoice)
	check(not initial_invoice.is_empty(), "business screen observes incident-changed invoice")
	await capture("02-altered-business-record")
	await tab("operations")
	return failures.is_empty()

func session(id: String) -> Dictionary:
	for row in observed_sessions():
		if str(row.get("session_id", "")) == id: return row
	return {}

func wrong_response() -> bool:
	var legitimate: Array = []
	for _step in 5:
		legitimate = observed_events().filter(func(row): return str(row.get("invoice_id", "")) == target_invoice and str(row.get("method", "")) == "PATCH" and int(row.get("status", 0)) == 200 and row.get("changes", {}).has("notes") and str(row.get("session_id", "")) != observed_session)
		if not legitimate.is_empty(): break
		await incident_press("IncidentAdvance")
	check(not legitimate.is_empty(), "authorized later notes edit is observed through audit")
	if legitimate.is_empty(): return false
	normal_session = str(legitimate[0].session_id)
	check(str(session(normal_session).get("principal", "")) == str(session(observed_session).get("principal", "")), "one principal has distinct normal and unexpected sessions")
	before_restoration = await open_observed_invoice(target_invoice)
	check(str(before_restoration.get("notes", "")) == str(legitimate[0].get("changes", {}).get("notes", {}).get("after", "missing")), "real GET displays the observed background business change")
	await tab("operations")
	await select_session(normal_session)
	var tick := int(exercise().tick)
	await incident_press("IncidentRevokeSession", true)
	check(bool(session(normal_session).get("revoked", false)) and not bool(session(observed_session).get("revoked", true)), "wrong response revokes only the chosen normal session")
	check(int(exercise().tick) == tick + 1, "double revoke consumes one exercise minute")
	await incident_press("IncidentExportPause")
	check(bool(exercise().get("export_paused", false)), "temporary export pause is active")
	var known_sessions: Array = observed_sessions().map(func(row): return str(row.session_id))
	await incident_press("IncidentBusinessProbe")
	var probe: Dictionary = pc.pentest_ui.incident_ui.probe
	var steps: Array = probe.get("steps", [])
	check(not bool(probe.get("passed", true)) and steps.any(func(row): return str(row.get("path", "")).contains("/exports") and int(row.get("status", 0)) >= 400), "export pause causes a real legitimate export failure")
	check(steps.any(func(row): return str(row.get("method", "")) == "GET" and int(row.get("status", 0)) == 401), "revoked legitimate session actually fails before recovery login")
	check(bool(session(normal_session).get("revoked", false)), "recovery never reactivates the revoked token")
	check(observed_sessions().any(func(row): return str(row.get("session_id", "")) not in known_sessions and str(row.get("principal", "")) == str(anomaly.get("principal", "")) and not bool(row.get("revoked", false))), "business recovery creates a fresh session for the same principal")
	await incident_press("IncidentAssess")
	check(not bool(exercise().get("assessment", {}).get("complete", true)), "wrong response cannot pass the exercise")
	await capture("03-wrong-response")
	normal_case_unchanged("wrong response")
	return failures.is_empty()

func preserve_and_resume() -> bool:
	await tab("request")
	await type_text("PentestPath", "/api/invoices/exercise-unsent-request")
	await type_text("PentestBody", "{\"note\":\"EXERCISE pending body\"}")
	run_request_draft = pc.pentest_ui.draft.duplicate(true)
	await tab("operations")
	var tick := int(exercise().tick)
	await incident_press("IncidentLeave")
	check(not bool(exercise().active) and str(pc.pentest_ui.get("_context_key", "")) == "main", "leave restores normal context")
	check(pc.pentest_ui.draft == original_request_draft and pc.pentest_ui.service.drafts == original_invoice_drafts, "leaving restores both original unsent drafts")
	normal_case_unchanged("leaving exercise")
	await incident_press("IncidentResume")
	check(str(exercise().run_id) == exercise_id and int(exercise().tick) == tick, "resume keeps the same run and minute")
	check(pc.pentest_ui.draft == run_request_draft, "resume restores exercise request draft")
	check(pc._save_session(), "save active exercise UI")
	check(ui.close_panel(false, false), "close exercise without data loss")
	await frames(); check(game.load_game(), "load persisted exercise")
	ui.open_panel("terminal"); await frames(); pc = ui.desktop; pc._show_app("advanced"); await frames(8)
	if not pc.windows.advanced.maximized: pc.windows.advanced.toggle_maximize(); await frames()
	await idle()
	check(str(exercise().run_id) == exercise_id and int(exercise().tick) == tick, "save load and automatic observations preserve exercise time")
	check(pc.pentest_ui.draft == run_request_draft, "unsent exercise request survives close and reload")
	check(bool(session(normal_session).get("revoked", false)) and bool(exercise().get("export_paused", false)), "actual response state survives reload")
	normal_case_unchanged("save load")
	await tab("operations"); await capture("04-resumed-exercise")
	return failures.is_empty()

func recover_selectively() -> bool:
	await select_session(observed_session)
	await incident_press("IncidentRevokeSession", true)
	check(bool(session(observed_session).get("revoked", false)), "correlated unexpected session is revoked")
	before_restoration = await open_observed_invoice(target_invoice)
	await tab("operations"); await incident_tab("versions")
	await type_text("IncidentInvoiceId", target_invoice)
	await incident_press("IncidentLoadVersions")
	var versions: Dictionary = pc.pentest_ui.incident_ui.versions
	var candidates: Array = versions.get("versions", []).filter(func(row): return int(row.get("version", 0)) < int(anomaly.get("version", 0)))
	check(not candidates.is_empty(), "observed version history provides a prior comparison")
	if candidates.is_empty(): return false
	candidates.sort_custom(func(a,b): return int(a.version) > int(b.version))
	var source: Dictionary = candidates[0]
	await choose("IncidentSourceVersion", int(source.version))
	var field := control("IncidentField_line_items") as CheckBox
	check(is_instance_valid(field) and not field.disabled, "changed invoice field can be selected for recovery")
	if not is_instance_valid(field) or field.disabled: return false
	await reachable(field, "IncidentField_line_items")
	field.button_pressed = true; field.toggled.emit(true); signal_clicks += 1; await idle()
	check(pc.pentest_ui.incident_ui.fields == ["line_items"], "recovery selects only the disputed line items")
	await capture("05-selective-version-recovery")
	if narrow:
		await reachable(control("IncidentRestoreVersion") as Control, "selective recovery action")
		await capture("05-preserved-notes-and-recovery")
	var tick := int(exercise().tick)
	await incident_press("IncidentRestoreVersion", true)
	check(int(exercise().tick) == tick + 1, "double restoration commits once")
	var recovered := await open_observed_invoice(target_invoice)
	check(recovered.get("line_items", []) == source.get("fields", {}).get("line_items", []) and int(recovered.get("amount", 0)) == int(source.get("fields", {}).get("amount", -1)), "real business GET shows selected line items and recomputed total restored")
	check(str(recovered.get("notes", "")) == str(before_restoration.get("notes", "")), "selected field restoration preserves the later authorized notes")
	check(int(recovered.get("version", 0)) == int(before_restoration.get("version", 0)) + 1, "restoration appends exactly one version")
	await capture("06-restored-business-record")
	await tab("operations")
	await incident_press("IncidentExportPause")
	check(not bool(exercise().get("export_paused", true)), "ordinary exports are resumed")
	await incident_press("IncidentBusinessProbe")
	var probe: Dictionary = pc.pentest_ui.incident_ui.probe
	check(bool(probe.get("passed", false)) and probe.get("steps", []).all(func(row): return int(row.get("status", 0)) >= 200 and int(row.get("status", 0)) < 300), "real login/create/read/approve/export/download workflow recovers")
	var refused: Array = []
	for _step in 8:
		refused = observed_events().filter(func(row): return str(row.get("session_id", "")) == observed_session and int(row.get("status", 0)) == 401)
		if not refused.is_empty(): break
		await incident_press("IncidentAdvance")
	check(not refused.is_empty(), "later use of contained session produces an actual 401")
	if not refused.is_empty():
		await select_event(refused[0]); await incident_press("IncidentPinEvent")
	await incident_press("IncidentAssess")
	var assessment: Dictionary = exercise().get("assessment", {})
	check(bool(assessment.get("complete", false)), "containment integrity recovery and corroborated evidence all pass")
	if not bool(assessment.get("complete", false)): print("INCIDENT_ASSESS_DIAGNOSTIC ", JSON.stringify(assessment))
	await capture("07-recovered-service")
	normal_case_unchanged("correct response")
	return failures.is_empty()

func result_content() -> void:
	var result: Dictionary = exercise().get("result", {})
	for key in ["disclosure_count", "remaining_damage", "legitimate_failures", "evidence_count"]:
		var label := control("IncidentMetric_" + key) as Label
		check(is_instance_valid(label) and str(label.text).begins_with(str(int(result.get("metrics", {}).get(key, -1))) + " "), "result displays measured " + key)
		one_line(label, "incident result " + key)
	check(label_text("IncidentDebriefSummary") == str(result.get("debrief", {}).get("summary", "missing")), "result renders concrete debrief summary")
	check(label_text("IncidentDebriefNotes") == str(result.get("debrief", {}).get("notes", "missing")), "result renders recovery consequences")

func result_visible(context := "finish") -> void:
	var scroll := control("PentestScroll") as ScrollContainer
	for id in ["IncidentResultSummary", "IncidentMetric_disclosure_count"]:
		var node := control(id) as Control
		check(is_instance_valid(node) and is_instance_valid(scroll), "result destination exists " + id)
		if not is_instance_valid(node) or not is_instance_valid(scroll): continue
		var center := node.get_global_rect().get_center()
		var visible := root.get_visible_rect().has_point(center) and scroll.get_global_rect().has_point(center)
		check(visible, context + " reveals its measured result without test scrolling " + id)
		if not visible: print("INCIDENT_RESULT_VIEW_DIAGNOSTIC ", JSON.stringify({"id":id,"node":str(node.get_global_rect()),"scroll":str(scroll.get_global_rect()),"vertical":scroll.scroll_vertical,"focus":str(root.gui_get_focus_owner())}))

func concluded_snapshot() -> Dictionary:
	# This is an isolation assertion only. Targets still come exclusively from
	# public event/session/version observations. Pause/resume may change these
	# two lifecycle values but must not change the finished exercise itself.
	var saved: Dictionary = game.state.advanced.get("exercise", {}).duplicate(true)
	saved.erase("active"); saved.erase("revision")
	return canonical(saved)

func disabled_action(id: String) -> void:
	var button := control(id) as BaseButton
	check(is_instance_valid(button) and button.is_visible_in_tree() and button.disabled, "concluded action is visibly disabled " + id)
	if not is_instance_valid(button) or not button.disabled: return
	await reachable(button, id)
	mouse_click(button.get_global_rect().get_center()); native_clicks += 1
	await idle()

func concluded_navigation() -> bool:
	var saved := concluded_snapshot()
	var pinned_ids: Array = exercise().get("evidence", []).map(func(row): return str(row.get("id", "")))
	check(str(anomaly.get("id", "")) in pinned_ids, "finished run retains the investigated saved event")
	await select_event(anomaly)
	await disabled_action("IncidentUnpinEvent")
	var unsaved: Array = observed_events().filter(func(row): return str(row.get("id", "")) not in pinned_ids)
	check(not unsaved.is_empty(), "finished audit has an observed unsaved record to inspect")
	if unsaved.is_empty(): return false
	await select_event(unsaved[0]); await disabled_action("IncidentPinEvent")
	await select_event(anomaly); await incident_press("IncidentEventSession")
	var detail := control("IncidentSessionDetail")
	check(is_instance_valid(detail) and str(detail.get_meta("session_id", "")) == observed_session, "concluded event still opens its observed session")
	await disabled_action("IncidentRevokeSession")
	await select_event(anomaly); await incident_press("IncidentEventVersions")
	check(str(pc.pentest_ui.incident_ui.versions.get("invoice_id", "")) == target_invoice, "concluded event still loads public invoice versions")
	await disabled_action("IncidentRestoreVersion")
	check(concluded_snapshot() == saved, "read-only event/session/version browsing cannot mutate the concluded run")
	await tab("portal")
	check(label_text("IncidentPortalFinished").contains("終了"), "concluded portal clearly explains that the exercise ended")
	for id in ["InvoiceLoginSubmit", "InvoiceNew", "InvoiceEdit", "InvoiceSave", "InvoiceApprove", "InvoiceLogout", "PentestCreateExport", "PentestPollExport", "PentestDownloadExport"]:
		var button := control(id) as BaseButton
		check(not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled, "concluded portal has no enabled business mutation " + id)
	for id in ["IncidentPortalResult", "IncidentPortalLeave"]:
		var button := control(id) as BaseButton
		check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "concluded portal offers an available route " + id)
	await capture("08-ended-portal")
	await incident_press("IncidentPortalResult")
	check(str(pc.pentest_ui.tab) == "operations" and str(pc.pentest_ui.incident_ui.section) == "result", "ended portal route opens result and replay")
	result_visible("ended portal route")
	check(control("IncidentRestart") != null, "ended portal result offers replay")
	await tab("portal"); await incident_press("IncidentPortalLeave")
	check(not bool(exercise().active) and str(pc.pentest_ui.get("_context_key", "")) == "main", "ended portal leave returns to normal workspace")
	check(canonical(pc.pentest_ui.draft) == canonical(original_request_draft) and canonical(pc.pentest_ui.service.drafts) == canonical(original_invoice_drafts), "ended portal leave restores original pending work")
	await incident_press("IncidentResume")
	result_visible("ended portal resume")
	# Reproduce the former stale section: leave while examining events, then
	# use the lobby's result action rather than a direct results tab.
	await incident_tab("events")
	check(str(pc.pentest_ui.incident_ui.section) == "events", "concluded departure starts from the audit section")
	await incident_press("IncidentLeave")
	var resume := control("IncidentResume") as Button
	check(is_instance_valid(resume) and resume.text.contains("結果"), "lobby labels concluded resume as a result route")
	await incident_press("IncidentResume")
	check(str(pc.pentest_ui.tab) == "operations" and str(pc.pentest_ui.incident_ui.section) == "result", "lobby result route overrides the saved events section")
	result_visible("lobby result resume")
	result_content()
	await capture("08-resumed-concluded-result")
	check(concluded_snapshot() == saved, "concluded navigation preserves complete branch, result, tick, events and evidence")
	normal_case_unchanged("concluded navigation")
	return failures.is_empty()

func conclude_and_replay() -> void:
	var observed_downloads: Array = observed_events().filter(func(row): return str(row.get("session_id", "")) == observed_session and str(row.get("path", "")).ends_with("/file") and int(row.get("status", 0)) == 200)
	await incident_press("IncidentFinish", true)
	check(str(exercise().phase) == "concluded" and bool(exercise().get("result", {}).get("complete", false)), "finish produces a measured successful conclusion")
	check(not exercise().get("result", {}).get("debrief", {}).is_empty(), "conclusion gives a concrete debrief")
	check(int(exercise().get("result", {}).get("metrics", {}).get("disclosure_count", -1)) == observed_downloads.size(), "concluded disclosure count matches actual observed downloads")
	result_content()
	result_visible()
	await capture("08-concluded-result")
	var debrief := control("IncidentDebriefNotes") as Control
	if is_instance_valid(debrief): await reachable(debrief, "IncidentDebriefSummary")
	await capture("08-concluded-debrief")
	if narrow:
		await reachable(control("IncidentRestart") as Control, "IncidentRestart")
		await capture("08-replay-controls")
	if not await concluded_navigation(): return
	await choose("IncidentVariant", "exfil"); await type_text("IncidentSeed", "202")
	await incident_press("IncidentRestart", true)
	check(str(exercise().get("run_id", "")) != exercise_id and int(exercise().tick) == 0 and str(exercise().variant) == "exfil", "double replay starts one clean new variant")
	check(exercise().get("results", []).size() == 1, "replay retains one previous outcome")
	var downloads: Array = observed_events().filter(func(row): return str(row.get("method", "")) == "GET" and str(row.get("path", "")).ends_with("/file") and int(row.get("status", 0)) == 200)
	check(not downloads.is_empty(), "new exfil variant starts with an actual disclosed file")
	if not downloads.is_empty():
		var observed: Dictionary = downloads[0]
		var fingerprint := JSON.stringify([observed.get("invoice_id", ""), observed.get("device", ""), observed.get("source", ""), observed.get("path", "")])
		check(fingerprint != initial_fingerprint, "new seed changes observable incident circumstances")
		await select_event(observed)
	await capture("09-new-seed-replay")
	await incident_press("IncidentAssess"); await incident_press("IncidentFinish")
	check(str(exercise().phase) == "concluded" and not bool(exercise().get("result", {}).get("complete", true)), "an incomplete response can conclude with a failed measured result")
	check(int(exercise().get("result", {}).get("metrics", {}).get("disclosure_count", 0)) >= 1, "early disclosure remains in the replay's final outcome")
	result_content()
	result_visible()
	await capture("10-incomplete-result")
	await incident_press("IncidentLeave")
	var restored: bool = canonical(pc.pentest_ui.draft) == canonical(original_request_draft) and canonical(pc.pentest_ui.service.drafts) == canonical(original_invoice_drafts)
	check(restored, "after both replays the original pending work is restored")
	if not restored or pc.pentest_ui.draft != original_request_draft or pc.pentest_ui.service.drafts != original_invoice_drafts:
		print("INCIDENT_DRAFT_DIAGNOSTIC ", JSON.stringify({"canonical_equal":restored,"context":pc.pentest_ui.get("_context_key"),"original_request":original_request_draft,"actual_request":pc.pentest_ui.draft,"original_forms":original_invoice_drafts,"actual_forms":pc.pentest_ui.service.drafts}))
	normal_case_unchanged("final return")

func run() -> void:
	if not await setup(): check(false, "invoice service available"); finish(); return
	if not await prepare_original_drafts(): finish(); return
	if not await start_and_observe(): finish(); return
	if not await wrong_response(): finish(); return
	if not await preserve_and_resume(): finish(); return
	if not await recover_selectively(): finish(); return
	await conclude_and_replay()
	finish()

func finish() -> void:
	print("INCIDENT_UI_INPUT native_clicks=%d native_edits=%d signal_clicks=%d secondary_http_requests=%d" % [native_clicks, native_edits, signal_clicks, secondary_requests])
	print("INCIDENT_UI_PASS narrow=" + str(narrow) if failures.is_empty() else "INCIDENT_UI_FAIL count=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
