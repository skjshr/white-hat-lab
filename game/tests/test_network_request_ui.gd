extends "res://tests/test_release_journey.gd"
## Normal funds and an actually available day-one contract. Setup uses public
## career APIs; all connection, investigation, repair and delivery actions use
## mouse/key dispatch. No answer, money, skill, clock or VM-state injection.
const INTERFACE = preload("res://scripts/interface.gd")
const BUSINESS_URL := "https://intranet.client.test/sales"
var assertions := 0
var measurements: Array[Dictionary] = []
var finishing := false
var journey_completed := false

func expect(value: bool, label: String) -> bool:
	assertions += 1
	return super.expect(value, label)

func press_control(target: Control, description: String) -> bool:
	if not expect(is_instance_valid(target) and target.is_visible_in_tree(), description + " visible"): return false
	if target is BaseButton and not expect(not target.disabled, description + " enabled"): return false
	# Scroll by input rather than ensure_control_visible. The stable rectangle
	# prevents a refresh/layout race from masquerading as failed keyboard routing.
	for _attempt in 36:
		var rect := clipped_rect(target)
		if rect.size.y >= minf(24, target.size.y) and rect.has_point(target.get_global_rect().get_center()): break
		var parent := target.get_parent()
		while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
		if not parent is ScrollContainer: break
		mouse(parent.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN if target.get_global_rect().get_center().y > parent.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP)
		await frames(3)
	var previous := Rect2(); var stable := 0
	for _attempt in 24:
		await frames(1)
		var rect := clipped_rect(target)
		stable = stable + 1 if rect == previous and rect.size.y >= minf(24, target.size.y) else 0
		previous = rect
		if stable >= 3: break
	if not expect(stable >= 3 and previous.has_point(target.get_global_rect().get_center()), description + " clipped geometry stable"): return false
	var point := previous.get_center() * Vector2(root.size) / root.get_visible_rect().size
	var count: Array[int] = [0]
	var is_button := target is BaseButton
	if is_button: target.pressed.connect(func(): count[0] += 1)
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; Input.parse_input_event(motion)
	await frames(2)
	var hovered: Control = root.gui_get_hovered_control()
	if not expect(hovered == target or (hovered != null and target.is_ancestor_of(hovered)), description + " pointer reaches control"): return false
	record("native_click", description)
	for down in [true,false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; Input.parse_input_event(event); await frames(2)
	clicks += 1
	await frames(8)
	if is_button and not expect(count[0] == 1, description + " exactly one real press"): return false
	return true

func press(id: String) -> bool:
	return await press_control(control(id), id)

func edit_control(field: LineEdit, value: String, description: String) -> bool:
	if not await press_control(field, description): return false
	if not expect(field.has_focus(), description + " actual input focus"): return false
	key(KEY_A,true,0,true); await frames(1); key(KEY_A,false,0,true)
	await tap(KEY_BACKSPACE)
	for index in value.length(): key(KEY_NONE,true,value.unicode_at(index)); key(KEY_NONE,false,value.unicode_at(index))
	await frames(5)
	record("native_text", description + "=" + value)
	return expect(field.text == value, description + " actual characters received")

func edit(id: String, value: String) -> bool:
	return await edit_control(control(id) as LineEdit, value, id)

func key(code: Key, pressed: bool, unicode_value := 0, ctrl := false) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.unicode = unicode_value; event.ctrl_pressed = ctrl; event.pressed = pressed
	# Native PopupMenus are separate OS windows. Route keys to the currently
	# visible popup, just as OS keyboard delivery does; do not emit selection.
	if is_instance_valid(ui):
		for choice in ui.find_children("*","OptionButton",true,false):
			var popup: PopupMenu = choice.get_popup()
			if popup.visible: event.window_id = popup.get_window_id(); break
	Input.parse_input_event(event)
	if pressed: keys += 1

func select_option(id: String, index: int) -> bool:
	var option := control(id) as OptionButton
	if not expect(is_instance_valid(option) and index < option.item_count, id + " actual choices exist"): return false
	if not await press(id): return false
	var popup := option.get_popup()
	if not expect(popup.visible, id + " native popup opened"): return false
	record("popup_state", id + " window_focus=" + str(root.has_focus()) + " popup_focus=" + str(popup.has_focus()) + " focused=" + str(popup.get_focused_item()))
	await tap(KEY_HOME)
	for _attempt in option.item_count + 1:
		if popup.get_focused_item() == index: break
		await tap(KEY_DOWN)
	if not expect(popup.get_focused_item() == index, id + " keyboard moved popup focus"): return false
	await tap(KEY_ENTER)
	return expect(option.selected == index and not popup.visible, id + " keyboard committed selection")

func text_in(node: Node) -> String:
	var result := ""
	if node is Label or node is RichTextLabel or node is Button: result += str(node.text) + "\n"
	for child in node.get_children(): result += text_in(child)
	return result

func checkpoint(label: String) -> void:
	var state: Dictionary = game.network_request_view(BUSINESS_URL)
	measurements.append({"stage":label,"request":state.duplicate(true),"clock":game.business_clock(),"cash":game.state.cash,"firewall":game._vm().firewall_snapshot(),"applied":game._vm().state.applied.duplicate(true),"work":game.work_status()})
	await capture(label)

func scroll_to(target: Control, to_top := false) -> bool:
	var scroller := target.get_parent()
	while scroller != null and not scroller is ScrollContainer: scroller = scroller.get_parent()
	if not expect(scroller is ScrollContainer, "result belongs to scrollable work area"): return false
	for _attempt in 24:
		if (to_top and scroller.scroll_vertical == 0) or (not to_top and clipped_rect(target).has_point(target.get_global_rect().get_center())): break
		mouse(scroller.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP if to_top or target.get_global_rect().get_center().y < scroller.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_DOWN)
		await frames(3)
	return expect(clipped_rect(target).has_point(target.get_global_rect().get_center()), "observed target visible after real wheel movement")

func run() -> void:
	game = root.get_node("Game")
	if not expect("--qa-profile=network-request-ui" in OS.get_cmdline_user_args(), "isolated network QA profile"): finish(); return
	game.set_process(false)
	game.set_settings({"resolution":"960x600" if narrow else "1440x900","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	if not expect(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(), "public normal funded career setup"): finish(); return
	if not expect(int(game.state.cash) == 5000 and int(game.state.day) == 1, "ordinary starting funds and day"): finish(); return
	var offers: Array = game.state.offers.filter(func(item): return bool(item.get("unlocked",false)) and bool(item.get("market_available",true)) and str(item.get("case_id","")) == "service-2-case-0")
	if not expect(not offers.is_empty() and game.choose_contract(str(offers[0].id)), "naturally available contract accepted by public API"): finish(); return
	record("setup_api", "new_game / advisory / free_career / naturally available contract accept; real-time background paused, action costs retained")
	ui = INTERFACE.new(); root.add_child(ui); await frames(8)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900)
	ui._set_text_scale(1.3 if narrow else 1.0); ui.controls.menu.hide(); ui.open_panel("terminal"); await frames(10)
	root.grab_focus(); await frames(3)
	record("window", "focus="+str(root.has_focus())+" pixels="+str(root.size)+" logical="+str(root.get_visible_rect().size))
	if not await route("mail"): finish(); return
	var mail_row: Button = null
	for candidate in ui.desktop.widgets.mail.list.find_children("*","Button",true,false):
		if text_in(candidate).contains(str(game.mission().title)): mail_row = candidate; break
	if not await press_control(mail_row, "actual customer message"): finish(); return
	var body := control("MailMessageBody") as Label
	if not expect(is_instance_valid(body) and body.text.contains(BUSINESS_URL), "customer supplies exact reproduction URL"): finish(); return
	await checkpoint("01-customer-request")
	if not await route("terminal"): finish(); return
	if not await edit_control(ui.desktop.widgets.terminal.command, "ssh client", "terminal connection command"): finish(); return
	await tap(KEY_ENTER)
	if not expect(bool(game.vm_info().connected), "native terminal authenticated to customer"): finish(); return
	if not await route("browser"): finish(); return
	if not await edit("BrowserAddress", BUSINESS_URL): finish(); return
	await tap(KEY_ENTER)
	if not expect(ui.desktop.browser_url == BUSINESS_URL and not ui.desktop.browser_response.contains("HTTP/1.1 200"), "same customer business request actually fails"): finish(); return
	if not expect(str(game.network_request_view(BUSINESS_URL).status) == "unobserved", "browsing does not manufacture observations"): finish(); return
	await checkpoint("02-business-failure-unobserved")
	if not await press("NetworkRequestTest"): finish(); return
	var initial: Dictionary = game.network_request_view(BUSINESS_URL)
	if not expect(str(initial.status) == "current" and not bool(initial.passed), "explicit request measurement observes actual failure"): finish(); return
	await checkpoint("03-observed-failure")
	var original_rules: Array = game._vm().firewall_snapshot().applied_rules.duplicate(true)
	if not await press("NetworkRequestSettings"): finish(); return
	if not expect(str(ui.desktop.firewall_ui.get("view","")) == "services", "same request opens actual service editor"): finish(); return
	if not await select_option("FirewallDNS",1): finish(); return
	if not expect(str((control("FirewallTLS") as OptionButton).get_item_metadata((control("FirewallTLS") as OptionButton).selected)) == "on", "TLS remains enabled in real editor"): finish(); return
	if not await press("FirewallServicesSave"): finish(); return
	if not expect(bool(game._vm().firewall_snapshot().pending) and str(game._vm().state.applied.dns) == "off", "saved DNS choice remains unapplied"): finish(); return
	await checkpoint("04-saved-pending")
	if not await press("NetworkRequestReturn"): finish(); return
	if not expect(ui.desktop.browser_url == BUSINESS_URL, "return preserves exact customer URL"): finish(); return
	if not await press("NetworkRequestTest"): finish(); return
	if not expect(not bool(game.network_request_view(BUSINESS_URL).passed), "same explicit request still fails while change pending"): finish(); return
	await checkpoint("05-pending-still-fails")
	if not await press("NetworkRequestSettings"): finish(); return
	if not await press("FirewallApply"): finish(); return
	if not expect(str(game.network_request_view(BUSINESS_URL).status) == "stale", "applied change invalidates old measurement"): finish(); return
	if not expect(str(game._vm().state.applied.tls) == "on" and game._vm().firewall_snapshot().applied_rules == original_rules, "repair preserves TLS and exact ordered rules"): finish(); return
	await checkpoint("06-applied-old-measurement")
	if not await press("NetworkRequestReturn"): finish(); return
	if not await press("NetworkRequestTest"): finish(); return
	if not expect(bool(game.network_request_view(BUSINESS_URL).passed), "fresh exact request and protective regression pass"): finish(); return
	if not expect(text_in(control("NetworkRequestAdmin")).contains("遮断"), "WAN administrative denial is visible as required protection"): finish(); return
	await checkpoint("07-business-restored-and-admin-denied")
	if narrow:
		var before: Dictionary = game.network_request_view(BUSINESS_URL).duplicate(true)
		if not await scroll_to(control("NetworkRequestTest"), true): finish(); return
		if not expect(game.network_request_view(BUSINESS_URL) == before, "scrolling reveals actions without rerunning measurement"): finish(); return
		await capture("07b-request-actions-at-top")
	if not await edit("BusinessSearch","Aoba"): finish(); return
	var row := control("BusinessOrder_501")
	if not expect(is_instance_valid(row) and row.visible and int(row.get_meta("business_order",{}).get("total",0)) == 12800 and str(row.get_meta("business_order",{}).get("customer","")) == "Aoba", "search filters real order 501 Aoba 12800"): finish(); return
	if not await press("BusinessOrderOpen_501"): finish(); return
	if not expect(str(ui.desktop.business_ui.selected_order) == "501" and text_in(ui.desktop.widgets.browser.page).contains("12,800"), "real selected business record contains actual amount"): finish(); return
	await checkpoint("08-customer-record-selected")
	if narrow:
		var customer: Label = null
		for label in ui.desktop.widgets.browser.page.find_children("*","Label",true,false):
			if label.text == "Aoba": customer = label; break
		if not expect(customer != null, "selected detail contains actual customer"): finish(); return
		if not await scroll_to(customer): finish(); return
		await capture("08b-selected-customer-detail")
	if not await press("NetworkRequestSettings"): finish(); return
	if not await press("NetworkRequestReturn"): finish(); return
	if not expect(ui.desktop.browser_url == BUSINESS_URL and str(ui.desktop.business_ui.selected_order) == "501", "editor round trip preserves URL and selected record"): finish(); return
	if not await route("verify"): finish(); return
	if not await press("DiagnosticValidate"): finish(); return
	if not expect(game.can_deliver(), "fresh actual probes and existing verification permit delivery"): finish(); return
	await checkpoint("09-verified-delivery")
	if not await press("GuideDeliver"): finish(); return
	var receipt: Dictionary = game.completion_receipt()
	if not expect(game.current_done() and not str(receipt.get("invoice_id","")).is_empty(), "actual accepted delivery creates real customer invoice"): finish(); return
	if not expect(game.state.cash >= 0, "normal funds remain solvent"): finish(); return
	if not await press("ReceiptEvaluationTab"): finish(); return
	if not expect(is_instance_valid(control("ReceiptCustomerOutcome")) and text_in(control("ReceiptEvaluation")).contains("✓"), "customer result shows actual saved acceptance checks"): finish(); return
	await checkpoint("10-customer-completion-receipt")
	journey_completed = true
	finish()

func finish() -> void:
	if finishing: return
	finishing = true
	if not journey_completed and failures.is_empty(): failures.append("journey stopped before customer completion")
	var report := {"assertions":assertions,"narrow":narrow,"clicks":clicks,"keys":keys,"scrolls":scrolls,"failures":failures,"events":events,"measurements":measurements,"method":"Public normal-funded day-one career acceptance setup; simulated background realtime paused; actual action costs retained. Repair, connection, search, verify, delivery by Godot Input mouse/key dispatch; zero direct signal emits or VM/desired/state overrides; known node IDs, not human usability proof."}
	var file := FileAccess.open(folder.path_join("network-native.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"  ")); file.close()
	print("NETWORK_REQUEST_UI_", "PASS" if failures.is_empty() else "FAIL", " assertions=",assertions," clicks=",clicks," keys=",keys," scrolls=",scrolls," failures=",failures)
	if is_instance_valid(ui): ui.queue_free(); await frames(5)
	quit(0 if failures.is_empty() else 1)
