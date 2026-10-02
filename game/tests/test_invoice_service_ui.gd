extends SceneTree
## Living-service E2E. Login, search and invoice entry use Godot mouse/key events.
## Supplementary tabs/actions use button signals; concurrency/denials use the
## same public request API as a second client. No business/evidence flags seeded.

var game
var ui
var pc
var failures: Array[String] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var capture_enabled := "--capture" in OS.get_cmdline_user_args()
var invoice_id := ""
var native_clicks := 0
var native_edits := 0
var signal_clicks := 0
var secondary_requests := 0

func _init() -> void:
	create_timer(150).timeout.connect(func(): push_error("INVOICE_SERVICE_UI_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value: failures.append(label); print("FAIL ", label)

func frames(count := 3) -> void:
	for _i in count: await process_frame

func idle() -> void:
	await create_timer(0.35).timeout
	for _i in 180:
		if not bool(pc.widgets.get("advanced", {}).get("busy", false)): break
		await process_frame
	await frames()

func control(id: String) -> Node:
	return pc.find_child(id, true, false) if is_instance_valid(pc) else null

func history() -> Array:
	return game.advanced_view().get("history", [])

func latest() -> Dictionary:
	var rows := history()
	return rows.back() if not rows.is_empty() else {}

func response_data() -> Dictionary:
	return latest().get("response", {}).get("data", {})

func status() -> int:
	return int(latest().get("response", {}).get("status", 0))

func matching(method: String, path: String) -> Array:
	return history().filter(func(row): return str(row.request.method) == method and str(row.request.path) == path)

func label_text(id: String) -> String:
	var node := control(id)
	check(node is Label or node is RichTextLabel, "label " + id)
	return str(node.text) if node is Label or node is RichTextLabel else ""

func one_line(label: Label, context: String) -> void:
	check(is_instance_valid(label), "readable value exists " + context)
	if not is_instance_valid(label): return
	var width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	check(label.get_line_count() == 1 and label.size.x + 1 >= width, "business value readable on one line " + context)

func detail_layout() -> void:
	one_line(control("InvoiceDetailTotal") as Label, "invoice total")
	var badge := control("InvoiceDetailState")
	check(is_instance_valid(badge), "invoice status badge exists")
	if is_instance_valid(badge):
		for label in badge.find_children("*", "Label", true, false): one_line(label, "invoice status")
	var stamp := control("InvoiceApprovedStamp")
	if is_instance_valid(stamp):
		for label in stamp.find_children("*", "Label", true, false): one_line(label, "approval stamp")

func list_layout() -> void:
	var table := control("InvoiceTable")
	check(is_instance_valid(table), "readable invoice table exists")
	if is_instance_valid(table):
		for label in table.find_children("*", "Label", true, false):
			if str(label.text).contains("下書き") or str(label.text).contains("承認済"): one_line(label, "list status")

func history_result_visible() -> void:
	var heading := control("InvoiceActivityHeading") as Control
	var scroll := control("PentestScroll") as ScrollContainer
	check(is_instance_valid(heading) and is_instance_valid(scroll), "business-history destination heading exists")
	if not is_instance_valid(heading) or not is_instance_valid(scroll): return
	var center := heading.get_global_rect().get_center()
	var visible := root.get_visible_rect().has_point(center) and scroll.get_global_rect().has_point(center)
	check(visible, "history action reveals its result without test scrolling")
	if not visible:
		var focused := root.gui_get_focus_owner()
		print("INVOICE_HISTORY_VIEW_DIAGNOSTIC ", JSON.stringify({"heading":str(heading.get_global_rect()),"scroll":str(scroll.get_global_rect()),"scroll_vertical":scroll.scroll_vertical,"scroll_max":scroll.get_v_scroll_bar().max_value,"scroll_page":scroll.get_v_scroll_bar().page,"focus":str(focused.name) if is_instance_valid(focused) else "none"}))

func reachable(node: Control, id: String) -> void:
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(node)
			await frames(2)
		if not is_instance_valid(ancestor) or not is_instance_valid(node): return
		ancestor = ancestor.get_parent()
	await frames()
	if not is_instance_valid(node): return
	var bounds := node.get_global_rect()
	check(root.get_visible_rect().encloses(bounds), "control in viewport " + id)
	ancestor = node.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			check(ancestor.get_global_rect().has_point(bounds.get_center()), "control inside clipping parent " + id)
		ancestor = ancestor.get_parent()

func mouse_click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = position; motion.global_position = position
	Input.parse_input_event(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; event.position = position; event.global_position = position
		Input.parse_input_event(event)

func press(id: String, native := false, twice := false) -> void:
	var button := control(id) as BaseButton
	check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "available " + id)
	if not is_instance_valid(button) or button.disabled: return
	await reachable(button, id)
	button = control(id) as BaseButton
	if not is_instance_valid(button) or button.disabled:
		check(false, "control remains available after scroll " + id); return
	if native:
		var center := button.get_global_rect().get_center()
		mouse_click(center); native_clicks += 1
		if twice: mouse_click(center); native_clicks += 1
	else:
		button.pressed.emit(); signal_clicks += 1
		if twice and is_instance_valid(button): button.pressed.emit(); signal_clicks += 1
	await idle()

func key_event(code: Key, unicode_value := 0, ctrl := false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.unicode = unicode_value; event.ctrl_pressed = ctrl; event.pressed = down
		Input.parse_input_event(event)

func type_text(id: String, value: String) -> void:
	var field := control(id)
	check(field is LineEdit or field is TextEdit, "text input " + id)
	if not (field is LineEdit or field is TextEdit): return
	await reachable(field, id)
	mouse_click(field.get_global_rect().get_center()); native_clicks += 1
	await frames()
	check(field.has_focus(), "mouse focuses " + id)
	key_event(KEY_A, 0, true)
	key_event(KEY_BACKSPACE)
	for index in value.length(): key_event(KEY_NONE, value.unicode_at(index))
	await frames()
	native_edits += 1
	field = control(id)
	check(is_instance_valid(field) and str(field.text) == value, "keyboard enters " + id)

func tab(id: String) -> void:
	await press("PentestTab_" + id)

func capture(label: String) -> void:
	if not capture_enabled or DisplayServer.get_name() == "headless" or not failures.is_empty(): return
	var target: Control = null
	if label == "06-reviewer-approved": target = control("InvoiceApprovedStamp") as Control
	if is_instance_valid(target):
		var scroll := control("PentestScroll") as ScrollContainer
		if is_instance_valid(scroll): scroll.ensure_control_visible(target)
	await frames(8); await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../../audit/living-service/e2e/screens")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func request(method: String, path: String, token: String, body := {}) -> Dictionary:
	secondary_requests += 1
	var result: Dictionary = game.advanced_action("request", {"method":method, "path":path, "session":token, "body":body, "headers":{}})
	check(bool(result.get("ok", false)), "second-client request persisted " + method + " " + path)
	return result.get("response", {})

func login(username: String, password: String) -> bool:
	var before := matching("POST", "/api/auth/login").size()
	await tab("portal")
	await type_text("InvoiceLoginUsername", username)
	await type_text("InvoiceLoginPassword", password)
	await press("InvoiceLoginSubmit", true)
	var rows := matching("POST", "/api/auth/login")
	var ok := rows.size() > before and int(rows.back().response.status) == 200 and str(rows.back().request.get("body", {}).get("username", "")) == username
	check(ok, username + " login accepted")
	if not ok: return false
	check(str(pc.pentest_ui.get("portal_user", {}).get("username", "")) == username, "portal names authenticated user")
	check(not str(pc.pentest_ui.get("portal_session", "")).is_empty() and str(pc.pentest_ui.portal_session) != username, "opaque session issued")
	check(status() == 200 and response_data().has("invoices"), "login opens real invoice list")
	return true

func fill_form(customer: String, quantity := "2", unit_price := "1250") -> void:
	await type_text("InvoiceCustomer", customer)
	await type_text("InvoiceIssueDate", "2026-10-02")
	await type_text("InvoiceDueDate", "2026-10-31")
	await type_text("InvoiceNotes", "E2E ordinary business note")
	await type_text("InvoiceLineDescription_0", "Security review")
	await type_text("InvoiceLineQuantity_0", quantity)
	await type_text("InvoiceLinePrice_0", unit_price)

func tab_through_form() -> void:
	if not narrow: return
	var first := control("InvoiceCustomer") as Control
	check(is_instance_valid(first), "keyboard traversal starts at customer")
	if not is_instance_valid(first): return
	await reachable(first, "tab traversal start")
	mouse_click(first.get_global_rect().get_center()); native_clicks += 1
	await frames()
	var reached_notes := false
	# Deliberately no scroll helper after the initial mouse focus. The application
	# must bring keyboard-focused controls into view by itself.
	for _step in 30:
		key_event(KEY_TAB); await frames(3)
		var focused := root.gui_get_focus_owner()
		check(is_instance_valid(focused), "Tab retains a focus owner")
		if not is_instance_valid(focused): break
		var center := focused.get_global_rect().get_center()
		check(root.get_visible_rect().has_point(center), "Tab focus inside viewport " + str(focused.name))
		var ancestor := focused.get_parent()
		while ancestor != null:
			if ancestor is Control and ancestor.clip_contents: check(ancestor.get_global_rect().has_point(center), "Tab focus follows scroll " + str(focused.name))
			ancestor = ancestor.get_parent()
		if str(focused.name) == "InvoiceNotes": reached_notes = true; break
	check(reached_notes, "native Tab reaches final notes input")

func setup() -> bool:
	game = root.get_node("Game"); game.set_process(false)
	check(str(game.save_path).begins_with("user://qa-"), "isolated QA profile")
	if not str(game.save_path).begins_with("user://qa-"): return false
	check(game.new_game(), "new isolated company")
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1440, 900)
	check(game.choose_strategy("advisory") and game.start_free_career(), "fresh career")
	var selected: Dictionary = {}
	for offer in game.state.offers:
		if str(offer.get("case_id", "")) == "advanced-portal" and bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false)):
			selected = offer; break
	check(not selected.is_empty(), "existing engagement available")
	if selected.is_empty(): return false
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	ui.controls.menu.hide(); ui.guided_intro.skip(); ui._set_text_scale(1.3 if narrow else 1.0)
	ui._select_contract(str(selected.id)); await frames()
	var accept := ui.modal.find_child("AcceptContract", true, false) as Button
	check(is_instance_valid(accept) and not accept.disabled, "accept existing engagement")
	if not is_instance_valid(accept) or accept.disabled: return false
	accept.pressed.emit(); signal_clicks += 1; await frames()
	ui.open_panel("terminal"); await frames(); pc = ui.desktop; pc._show_app("advanced"); await frames(8)
	if not pc.windows.advanced.maximized: pc.windows.advanced.toggle_maximize(); await frames()
	check(control("PentestWorkspace") != null, "portal workspace ready")
	check(history().is_empty(), "opening app makes no hidden requests")
	return control("InvoiceLoginSubmit") != null

func run() -> void:
	if not await setup(): check(false, "service login UI available"); finish(); return
	await press("InvoiceTestAccountsToggle")
	check(control("InvoiceTestAccount_alice") != null, "fictional account credentials are discoverable on login screen")
	await capture("01-login")
	await press("InvoiceTestAccountsToggle")
	await type_text("InvoiceLoginUsername", "alice")
	await type_text("InvoiceLoginPassword", "Wrong-demo-password")
	await press("InvoiceLoginSubmit", true)
	check(status() == 401 and str(pc.pentest_ui.get("portal_session", "")).is_empty(), "bad credentials rejected without active session")
	if not await login("alice", "Alice-demo-27"): finish(); return
	list_layout()
	await capture("02-invoice-list")
	await search_and_create()
	if invoice_id.is_empty() or not failures.is_empty(): finish(); return
	if "--preview-only" in OS.get_cmdline_user_args():
		print("INVOICE_SERVICE_UI_PREVIEW_ONLY failures=" + str(failures.size()))
		quit(0 if failures.is_empty() else 1); return
	await edit_and_conflict()
	if not failures.is_empty(): finish(); return
	await roles_and_history()
	if not failures.is_empty(): finish(); return
	await persistence()
	check(not game.can_deliver(), "ordinary invoice business cannot complete security engagement")
	finish()

func search_and_create() -> void:
	await type_text("InvoiceSearch", "no-such-e2e-customer")
	await press("InvoiceSearchSubmit", true)
	check(status() == 200 and response_data().get("invoices", []).is_empty(), "empty search is a valid empty list")
	await capture("02-empty-search")
	await type_text("InvoiceSearch", "")
	await press("InvoiceSearchSubmit", true)
	check(response_data().get("invoices", []).size() > 0, "clearing search restores tenant list")
	await press("InvoiceNew", true)
	await fill_form("Cancelled customer")
	var count_before := matching("POST", "/api/invoices").size()
	await press("InvoiceCancel")
	check(matching("POST", "/api/invoices").size() == count_before, "cancel creates no invoice and sends no create request")
	await press("InvoiceNew", true)
	await fill_form("")
	await press("InvoiceSave", true)
	check(status() == 422, "server rejects incomplete customer")
	check(not label_text("InvoiceFormErrors").is_empty(), "validation gives visible field feedback")
	check(str(control("InvoiceLineDescription_0").text) == "Security review", "validation preserves typed line items")
	await type_text("InvoiceCustomer", "E2E Acme, Inc.")
	await press("InvoiceAddLine")
	await type_text("InvoiceLineDescription_1", "Follow-up workshop")
	await type_text("InvoiceLineQuantity_1", "3")
	await type_text("InvoiceLinePrice_1", "400")
	await tab_through_form()
	check(label_text("InvoiceFormTotal").replace(",", "").contains("3700"), "form total combines both line items")
	one_line(control("InvoiceFormTotal") as Label, "form total")
	var save := control("InvoiceSave") as Button
	check(is_instance_valid(save) and save.size.y <= 80.0 * (1.3 if narrow else 1.0), "form save action keeps a usable button height")
	await capture("03-create-form")
	count_before = matching("POST", "/api/invoices").size()
	await press("InvoiceSave", true, true)
	var created := matching("POST", "/api/invoices")
	check(created.size() == count_before + 1, "rapid double save sends one create request")
	if created.is_empty(): return
	var data: Dictionary = created.back().response.get("data", {})
	check(int(created.back().response.status) == 201, "create returns real invoice")
	invoice_id = str(data.get("id", ""))
	check(not invoice_id.is_empty() and int(data.get("amount", 0)) == 3700 and data.get("line_items", []).size() == 2, "created record has server total and both lines")
	check(str(data.get("owner", "")) == "alice" and str(data.get("tenant", "")) == "north", "creation assigns authenticated owner and tenant")
	check(label_text("InvoiceDetailTotal").replace(",", "").contains("3700"), "detail shows persisted create total")
	detail_layout()
	await capture("04-created-detail")

func edit_and_conflict() -> void:
	await press("InvoiceEdit")
	await type_text("InvoiceLineQuantity_0", "4")
	await type_text("InvoiceCustomer", "E2E Updated Acme")
	await press("InvoiceSave", true)
	var changed := matching("PATCH", "/api/invoices/" + invoice_id)
	check(not changed.is_empty() and int(changed.back().response.status) == 200, "draft edit persists")
	if changed.is_empty() or int(changed.back().response.status) != 200:
		print("INVOICE_UPDATE_DIAGNOSTIC ", JSON.stringify({"record":latest(), "form":pc.pentest_ui.get("service", {}).get("drafts", {})}))
		return
	var invoice: Dictionary = changed.back().response.data if not changed.is_empty() else {}
	check(int(invoice.get("amount", 0)) == 6200, "update recomputes total")
	check(label_text("InvoiceDetailCustomer").contains("E2E Updated Acme") and label_text("InvoiceDetailTotal").replace(",", "").contains("6200"), "detail refreshes customer and total")
	detail_layout()
	await press("PentestPortalLoad")
	await type_text("InvoiceSearch", "updated acme")
	await press("InvoiceSearchSubmit", true)
	var rows: Array = response_data().get("invoices", [])
	check(rows.size() == 1 and str(rows[0].id) == invoice_id and int(rows[0].amount) == 6200, "search list reflects case-insensitive edited customer and amount")
	await press("PentestInvoice_" + invoice_id.validate_node_name())
	await press("InvoiceEdit")
	await type_text("InvoiceNotes", "Local draft must survive conflict")
	var token := str(pc.pentest_ui.portal_session)
	var remote: Dictionary = invoice.duplicate(true)
	var body := {"customer":remote.customer, "issue_date":remote.issue_date, "due_date":remote.due_date, "notes":"Concurrent client update", "line_items":remote.line_items, "version":remote.version}
	var concurrent := request("PATCH", "/api/invoices/" + invoice_id, token, body)
	check(int(concurrent.get("status", 0)) == 200, "second client updates through same HTTP dispatcher")
	await press("InvoiceSave", true)
	check(status() == 409, "stale form rejected without overwriting newer invoice")
	check(str(control("InvoiceNotes").text) == "Local draft must survive conflict", "stale rejection preserves local input")
	check(not label_text("InvoiceFeedback").is_empty() and control("InvoiceReloadConflict") != null, "stale conflict gives visible recovery feedback and a current-version action")
	await capture("05-stale-conflict")
	await press("InvoiceReloadConflict")
	check(int(response_data().get("version", 0)) == int(concurrent.get("data", {}).get("version", -1)), "conflict recovery observes the newer invoice")
	await press("InvoiceRebaseDraft")
	check(str(control("InvoiceNotes").text) == "Local draft must survive conflict", "explicit rebase retains the user's pending input")
	await press("InvoiceSave", true)
	check(status() == 200 and str(response_data().get("notes", "")) == "Local draft must survive conflict", "explicit conflict recovery saves the pending input successfully")
	check(int(latest().get("request", {}).get("body", {}).get("version", 0)) == int(concurrent.get("data", {}).get("version", -1)), "recovery save uses the observed current version")

func roles_and_history() -> void:
	await press("PentestPortalLoad")
	await type_text("InvoiceSearch", "")
	await press("InvoiceSearchSubmit", true)
	await press("PentestInvoice_" + invoice_id.validate_node_name())
	var approve := control("InvoiceApprove") as BaseButton
	check(not is_instance_valid(approve) or approve.disabled, "employee cannot use approval control")
	var current: Dictionary = response_data()
	var employee_token := str(pc.pentest_ui.portal_session)
	var refused := request("POST", "/api/invoices/" + invoice_id + "/approve", employee_token, {"version":current.get("version", 0)})
	check(int(refused.get("status", 0)) == 403, "employee HTTP approval is denied")
	await press("InvoiceLogout")
	if not await login("noah", "Noah-demo-27"): return
	await press("PentestInvoice_" + invoice_id.validate_node_name())
	var count_before := matching("POST", "/api/invoices/" + invoice_id + "/approve").size()
	await press("InvoiceApprove", true, true)
	var approvals := matching("POST", "/api/invoices/" + invoice_id + "/approve")
	check(approvals.size() == count_before + 1 and int(approvals.back().response.status) == 200, "reviewer double click commits one approval")
	check(str(approvals.back().response.data.get("state", "")) == "approved", "reviewer approval changes persisted state")
	detail_layout()
	await capture("06-reviewer-approved")
	await press("InvoiceLogout")
	if not await login("beth", "Beth-demo-27"): return
	check(not response_data().get("invoices", []).any(func(row): return str(row.id) == invoice_id), "other tenant list excludes north invoice")
	refused = request("GET", "/api/invoices/" + invoice_id, str(pc.pentest_ui.portal_session))
	check(int(refused.get("status", 0)) == 403 and not refused.get("data", {}).has("line_items"), "other tenant direct invoice access denied without details")
	await press("InvoiceLogout")
	if not await login("alice", "Alice-demo-27"): return
	await press("PentestInvoice_" + invoice_id.validate_node_name())
	await press("InvoiceHistory")
	var events: Array = response_data().get("events", [])
	check(events.filter(func(row): return str(row.action) == "created").size() == 1, "business history has one creation")
	check(events.filter(func(row): return str(row.action) == "updated").size() == 3, "business history contains edit, concurrent update and explicit conflict recovery")
	check(events.filter(func(row): return str(row.action) == "approved").size() == 1, "history contains one approval, no rejected writes")
	check(events.any(func(row): return str(row.action) == "approved" and str(row.actor) == "noah"), "business history identifies reviewer")
	history_result_visible()
	await capture("07-business-history")
	var history_record := str(latest().get("id", ""))
	await tab("history")
	check(control("PentestHistory_" + history_record.validate_node_name()) != null, "same business history GET is visible in communication history")
	await capture("08-communication-history")
	await press("PentestHistory_" + history_record.validate_node_name())
	await tab("request")
	check(str(pc.pentest_ui.get("response_id", "")) == history_record and label_text("PentestResponseRequest").contains("/api/invoices/" + invoice_id + "/history"), "communication inspector shows the actual business-history request")
	await tab("portal")

func persistence() -> void:
	var token := str(pc.pentest_ui.portal_session)
	var before: Dictionary = game.state.advanced.duplicate(true)
	check(pc._save_session(), "save portal session and service view")
	check(ui.close_panel(false, false), "close app through normal return")
	await frames(); check(game.load_game(), "reload saved company")
	check(game.state.advanced == JSON.parse_string(JSON.stringify(before)), "invoice/session/business history/request records all survive reload")
	ui.open_panel("terminal"); await frames(); pc = ui.desktop; pc._show_app("advanced"); await frames(8)
	if not pc.windows.advanced.maximized: pc.windows.advanced.toggle_maximize(); await frames()
	await idle()
	check(str(pc.pentest_ui.get("portal_session", "")) == token, "active portal token survives app reopen")
	check(str(pc.pentest_ui.get("portal_user", {}).get("username", "")) == "alice", "original user remains selected")
	await press("PentestPortalLoad")
	await type_text("InvoiceSearch", "Updated Acme")
	await press("InvoiceSearchSubmit", true)
	var rows: Array = response_data().get("invoices", [])
	check(rows.size() == 1 and str(rows[0].id) == invoice_id and int(rows[0].amount) == 6200 and str(rows[0].state) == "approved", "reopened active session reads the saved approved invoice")
	await press("PentestInvoice_" + invoice_id.validate_node_name())
	await press("InvoiceHistory")
	check(response_data().get("events", []).size() == 5, "business history remains complete after reload")
	history_result_visible()
	await capture("09-resumed")

func finish() -> void:
	print("INVOICE_SERVICE_INPUT native_clicks=%d native_edits=%d signal_clicks=%d secondary_http_requests=%d" % [native_clicks, native_edits, signal_clicks, secondary_requests])
	print("INVOICE_SERVICE_UI_PASS narrow=" + str(narrow) if failures.is_empty() else "INVOICE_SERVICE_UI_FAIL count=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
