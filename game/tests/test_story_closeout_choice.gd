extends SceneTree
## Focused native-input regression, not an unbriefed usability session.
## New companies use ordinary starting funds. Receipt setup is a disclosed repair
## fixture through public VM APIs; it does not assign cash, checks, or receipts.
const REPAIR_FIXTURE := "[global]\nserver role = standalone server\nmap to guest = Bad User\n[share]\npath = /srv/share\nread only = no\nguest ok = no\nvalid users = staff\n"
var game
var ui
var failures: Array[String] = []
var assertions := 0
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("STORY_CLOSEOUT_CHOICE_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); print("FAIL ", message)

func frames(count := 8) -> void:
	for _i in count: await process_frame

func control(id: String) -> Control:
	return ui.find_child(id, true, false) as Control

func visible_rect(node: Control) -> Rect2:
	if node == null or not node.is_visible_in_tree(): return Rect2()
	var rect := node.get_global_rect()
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return rect.intersection(root.get_visible_rect())

func click(id: String) -> void:
	var node := control(id)
	check(node is BaseButton and node.is_visible_in_tree() and not node.disabled, "enabled native control " + id)
	if not node is BaseButton or not node.is_visible_in_tree() or node.disabled: return
	var rect := visible_rect(node)
	check(rect.size.y >= 20, "reachable native control " + id)
	if rect.size.y < 20: return
	# Input.parse_input_event expects native window pixels, including canvas scale.
	var point := rect.get_center() * Vector2(root.size) / root.get_visible_rect().size
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; Input.parse_input_event(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; Input.parse_input_event(event)
	await frames(12)

func label_text(id: String) -> String:
	var node := control(id)
	check(node is Label and node.is_visible_in_tree(), "visible closeout label " + id)
	return str(node.text) if node is Label else ""

func economy_snapshot() -> Dictionary:
	var snapshot := {}
	for key in ["cash", "profit", "accepted", "day", "chapter", "completed_ids", "history"]:
		snapshot[key] = game.state.get(key)
	snapshot.receipt = receipt_snapshot(game.completion_receipt())
	# Compare the persisted representation, including JSON's numeric types.
	return JSON.parse_string(JSON.stringify(snapshot))

func receipt_snapshot(receipt: Dictionary) -> Dictionary:
	# Day settlement may append its own retainer metadata; recorded delivery
	# identity, money, and customer evidence must remain unchanged.
	var snapshot := {}
	for key in ["day", "client", "title", "fee", "bonus", "cost", "net", "checks", "delivery_results"]:
		snapshot[key] = receipt.get(key)
	return JSON.parse_string(JSON.stringify(snapshot))

func closeout_text() -> Dictionary:
	var result := {}
	for id in ["StoryCloseoutTitle", "StoryCloseoutSummary", "StoryCloseoutProfit", "StoryCloseoutCash", "StoryCloseoutNext"]:
		result[id] = label_text(id)
	return result

func open_closeout() -> void:
	var before := economy_snapshot()
	ui.open_panel("door"); await frames()
	check(economy_snapshot() == before, "opening closeout never accepts, settles, or rewards")

func assert_unfinished() -> void:
	var settle := control("DaySettle") as Button
	check(settle != null and settle.disabled, "unfinished day cannot settle")
	var title := label_text("StoryCloseoutTitle")
	check(not title.is_empty() and not title.contains("納品完了"), "unfinished day has no success heading")
	var summary := label_text("StoryCloseoutSummary")
	check(summary.contains("未納品") or summary.contains("まだ引き受けていません"), "unfinished summary reports actual blocker instead of success")
	var next := label_text("StoryCloseoutNext")
	check(next.contains("納品"), "unfinished day explains delivery blocker")

func solve_receipt_fixture() -> void:
	print("STORY_CLOSEOUT_FIXTURE public VM configuration, service restart, recorded diagnostics; ordinary funds retained")
	check(game.accept_mission(), "fixture accepts normal first story")
	check(str(game.vm_run("ssh client")).contains("Authenticated"), "fixture connects real customer VM")
	check(game.capture_baseline(), "fixture captures actual baseline")
	check(game.vm_write(str(game.vm_info().config_path), REPAIR_FIXTURE), "fixture writes configuration through VM API")
	game.vm_run("systemctl restart " + str(game.vm_info().service))
	for _round in 3:
		for probe in game.diagnostic_probes():
			if not bool(probe.get("fresh", false)) or not bool(probe.get("passed", false)): game.run_diagnostic(str(probe.id))
		game.verify()
		if game.can_deliver(): break
	check(game.can_deliver(), "fixture has actual fresh passing observations")

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"):
		push_error("Requires an isolated QA profile"); quit(2); return
	game.set_process(false)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900); ui._set_text_scale(1.3 if narrow else 1.0)
	check(ui._new_game(), "normal funded new company")
	await frames()
	var before_choice := economy_snapshot()
	ui.open_panel("board"); await frames()
	check(economy_snapshot() == before_choice, "showing strategy choice has no economic side effects")
	for id in ["operations", "advisory", "response"]:
		var choice := control("GuideStrategy_" + id) as Button
		check(choice != null and choice.is_visible_in_tree() and not choice.disabled, "strategy available " + id)
	check(ui.guided_intro._body.is_visible_in_tree() and str(ui.guided_intro._body.text).contains("どれを選んでも"), "free choice explanation visible without opening hint")
	check(not ui.guided_intro.target_rect.has_area(), "guide does not prescribe one specialization")
	await click("GuideStrategy_advisory")
	check(str(game.state.strategy) == "advisory" and not game.state.career_mode, "alternative choice enters normal guided story")
	check(int(game.state.cash) == int(before_choice.cash) and not game.state.accepted, "choice neither spends cash nor accepts customer work")
	await open_closeout(); assert_unfinished()
	ui.close_panel(false, false)
	solve_receipt_fixture()
	ui.open_panel("terminal"); ui.desktop._show_app("receipt"); await frames()
	var cash_before_delivery := int(game.state.cash)
	await click("GuideDeliver")
	check(game.current_done(), "native delivery creates actual receipt")
	var receipt: Dictionary = game.completion_receipt().duplicate(true)
	check(not receipt.is_empty() and int(receipt.get("day", -1)) == int(game.state.day), "receipt belongs to current day")
	if receipt.is_empty(): finish(); return
	check(int(game.state.cash) == cash_before_delivery + int(receipt.net) + int(receipt.get("material_cost", 0)), "delivery cash agrees with actual receipt")
	await open_closeout()
	var rendered := closeout_text()
	var summary := str(rendered.StoryCloseoutSummary).replace(",", "")
	check(summary.contains("納品済み"), "completed day announces delivered status")
	check(summary.contains(str(receipt.client)) and summary.contains(str(receipt.title)), "closeout identifies delivered customer and job")
	check(str(rendered.StoryCloseoutProfit).replace(",", "").contains("¥" + str(int(receipt.net))), "closeout profit agrees with actual receipt")
	check(str(rendered.StoryCloseoutCash).replace(",", "").contains("¥" + str(int(game.state.cash))), "closeout cash agrees with actual balance")
	check(not str(rendered.StoryCloseoutNext).is_empty(), "closeout explains next step")
	var settle := control("DaySettle") as Button
	check(settle != null and not settle.disabled, "completed day can settle")
	var delivered := economy_snapshot()
	await open_closeout()
	check(economy_snapshot() == delivered, "reopening summary does not duplicate delivery")
	check(game.save_game(), "save completed closeout")
	ui.open_main_menu(); await frames(); await click("ResumeButton")
	check(not ui.controls.menu.visible and economy_snapshot() == delivered, "native resume retains delivered economy")
	await open_closeout()
	check(closeout_text() == rendered, "save and resume retain rendered summary")
	check(receipt_snapshot(game.completion_receipt()) == receipt_snapshot(receipt), "save and resume retain delivery evidence and amounts")
	await click("DaySettle")
	check(int(game.state.day) == int(delivered.day) + 1 and int(game.state.chapter) == int(delivered.chapter) + 1, "native settlement advances exactly one story day")
	check(int(game.state.cash) == int(delivered.cash) and int(game.state.profit) == int(delivered.profit), "standard settlement pays no second delivery reward")
	check(game.state.completed_ids == delivered.completed_ids and receipt_snapshot(game.completion_receipt()) == receipt_snapshot(receipt), "settlement preserves single delivery and frozen evidence")
	await open_closeout(); assert_unfinished()
	check(not label_text("StoryCloseoutSummary").contains(str(receipt.title)), "yesterday receipt is not presented as today's completion")
	var next_day := economy_snapshot()
	check(not game.end_day() and economy_snapshot() == next_day, "unfinished next day cannot settle or reward again")
	finish()

func finish() -> void:
	print("STORY_CLOSEOUT_CHOICE_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " narrow=", narrow, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
