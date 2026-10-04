extends SceneTree
## Display fixtures for existing investment mechanics; no claimed gameplay earnings.
## Equipment selection uses actual pointer events. Skill/equipment fixtures remain
## isolated in the QA profile and are never purchased or saved as player progress.
var game
var ui
var failures: Array[String] = []
var assertions := 0
var clicks := 0
var wheels := 0
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(90).timeout.connect(func(): push_error("INVESTMENT_CHOICE_UI_TIMEOUT"); quit(2))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); print("FAIL ", message)

func frames(count := 8) -> void:
	for _i in count: await process_frame

func node(id: String) -> Control:
	return ui.find_child(id, true, false) as Control

func visible_rect(control: Control) -> Rect2:
	if control == null or not control.is_visible_in_tree(): return Rect2()
	var rect := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return rect.intersection(root.get_visible_rect())

func pointer(point: Vector2, button: MouseButton) -> void:
	var pixel := point * Vector2(root.size) / root.get_visible_rect().size
	var move := InputEventMouseMotion.new(); move.position = pixel; move.global_position = pixel; Input.parse_input_event(move)
	await frames(1)
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.position = pixel; event.global_position = pixel; event.button_index = button; event.pressed = down; Input.parse_input_event(event)
		await frames(2)

func click(id: String) -> void:
	var button := node(id) as Button
	check(button != null and button.is_visible_in_tree() and not button.disabled, "available control " + id)
	if button == null or not button.is_visible_in_tree() or button.disabled: return
	var scroll := node("EquipmentSelectorScroll") as ScrollContainer
	for _attempt in 24:
		if visible_rect(button).size.y >= 30: break
		if scroll == null: break
		await pointer(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN if button.get_global_rect().get_center().y > scroll.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP)
	var stable := 0
	var previous := Rect2()
	for _attempt in 24:
		await frames(1)
		var rect := visible_rect(button)
		stable = stable + 1 if rect == previous and rect.size.y >= 30 else 0
		previous = rect
		if stable >= 3: break
	check(stable >= 3, "stable visible control " + id)
	if stable < 3: return
	var pressed := [0]
	button.pressed.connect(func(): pressed[0] += 1)
	await pointer(previous.get_center(), MOUSE_BUTTON_LEFT)
	await frames(12)
	clicks += 1
	check(pressed[0] == 1, "one actual pressed signal " + id)

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var folder := OS.get_environment("WHL_CAPTURE_DIR")
	if folder.is_empty(): return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + label)

func assert_fits(control: Control, message: String) -> void:
	check(control != null, "exists " + message)
	if control == null: return
	# A narrow management panel may scroll vertically. Reach the actual text
	# with wheel input, then verify it is neither clipped nor occluded.
	for _attempt in 24:
		if visible_rect(control).size.y >= control.size.y - 1: break
		var scroll: ScrollContainer = ui.modal_scroll
		await pointer(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN if control.get_global_rect().get_center().y > scroll.get_global_rect().get_center().y else MOUSE_BUTTON_WHEEL_UP)
		wheels += 1
		await frames(3)
	var rect := control.get_global_rect()
	check(rect.position.x >= -1 and rect.end.x <= root.get_visible_rect().end.x + 1, "horizontal viewport fit " + message)
	check(visible_rect(control).size.x >= rect.size.x - 1, "no horizontal ancestor clipping " + message)
	if control is Label:
		check(control.autowrap_mode != TextServer.AUTOWRAP_OFF, "wrapping enabled " + message)
	check(visible_rect(control).size.y >= rect.size.y - 1, "entire explanation visible " + message)

func catalog(id: String) -> Dictionary:
	for item in game.equipment_catalog():
		if str(item.id) == id: return item
	return {}

func mechanics() -> void:
	var original: Array = game.state.equipment.duplicate(true)
	game.state.equipment = []
	var slots := int(game.contract_capacity())
	game.state.equipment = ["teamdesk"]
	check(int(game.contract_capacity()) == slots + 2, "advertised team desk adds two real contract slots")
	check(int(game.staff_capacity()) == 1, "advertised team desk adds one real hire")
	game.state.equipment = ["plant"]
	for kind in ["edit", "diagnostic", "measurement"]:
		check(is_equal_approx(float(game.action_minutes(kind, 6)), 6.0), "plant leaves action minutes unchanged " + kind)
	game.state.equipment = ["diagnostic"]
	check(is_equal_approx(float(game.action_minutes("diagnostic", 6)), 4.0), "diagnostic desk verification six to four")
	check(is_equal_approx(float(game.action_minutes("measurement", 4)), 3.0), "diagnostic desk measurement minus one")
	game.state.equipment = original

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): push_error("Requires isolated QA profile"); quit(2); return
	game.set_process(false)
	ui = load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1440,900); ui._set_text_scale(1.3 if narrow else 1.0)
	check(ui._new_game() and game.choose_strategy("advisory"), "ordinary company before isolated display fixtures")
	await frames(12)
	await click("GuidedTutorialSkip")
	print("INVESTMENT_CHOICE_UI_FIXTURE skills and equipment only; cash remains normal starting funds; no purchase, delivery, or save claim")
	mechanics()
	ui.open_panel("shop"); await frames(12)
	var before := JSON.stringify(game.state)
	await click("EquipmentSelect_monitor")
	check(node("EquipmentDiscount") == null, "no discount is advertised without operations skill")
	check(str(node("EquipmentPrice").text) == "¥%d" % int(catalog("monitor").price), "unskilled price equals catalog price")
	check(JSON.stringify(game.state) == before, "item selection does not mutate game state")
	game.state.skills.operations = 1
	ui.open_panel("shop"); await frames(12)
	before = JSON.stringify(game.state)
	for id in ["backup", "monitor"]:
		await click("EquipmentSelect_" + id)
		var base := int(catalog(id).price)
		var actual := int(game.equipment_price(id))
		check(actual == roundi(base * 0.8), "operations gives actual twenty percent price " + id)
		var discount := node("EquipmentDiscount") as Label
		check(discount != null and discount.text.contains(str(base)) and discount.text.contains(str(actual)) and discount.text.contains("20%"), "discount explains actual before and after " + id)
		await assert_fits(discount, "discount " + id)
		if id == "monitor": await capture("02-monitor-discount-fixture")
	await click("EquipmentSelect_teamdesk")
	check(node("EquipmentDiscount") == null, "operations does not falsely discount team desk")
	check(str(node("EquipmentEffect").text).contains("同時受注枠 +2"), "team desk describes real additional contract capacity")
	await assert_fits(node("EquipmentEffect"), "team desk effect")
	await capture("01-teamdesk-effects-fixture")
	await click("EquipmentSelect_plant")
	check(str(node("EquipmentEffect").text).contains("作業速度") and str(node("EquipmentEffect").text).contains("なし"), "plant clearly explains no speed effect")
	await click("EquipmentSelect_diagnostic")
	check(str(node("EquipmentEffect").text).contains("計測") and str(node("EquipmentEffect").text).contains("-1"), "diagnostic detail includes individual measurement reduction")
	check(JSON.stringify(game.state) == before, "all investment rendering remains read only")
	# Rank-zero operations at company level one has authored unlocks. This
	# specifically catches numeric next benefit being replaced by their titles.
	game.state.skills.operations = 0
	before = JSON.stringify(game.state)
	ui._select_company_view("growth"); await frames(12)
	await capture("03-growth-benefits-fixture")
	var unlock_count := 0
	for skill in game.skill_catalog():
		var next_label := node("SkillNext_" + str(skill.id)) as Label
		check(next_label != null and next_label.text.contains(str(skill.next_effect)), "quantitative next benefit survives case unlocks " + str(skill.id))
		await assert_fits(next_label, "next benefit " + str(skill.id))
		var unlocks: Array = game.skill_case_unlocks(str(skill.id))
		if not unlocks.is_empty():
			unlock_count += 1
			var unlock_label := node("SkillUnlocks_" + str(skill.id)) as Label
			check(unlock_label != null and unlock_label.tooltip_text.contains(str(unlocks[0])), "separate unlock detail retains actual case " + str(skill.id))
			await assert_fits(unlock_label, "unlocks " + str(skill.id))
		await assert_fits(node("LearnSkill_" + str(skill.id)), "learn button " + str(skill.id))
	check(unlock_count > 0, "fixture includes real next-rank case unlocks")
	check(JSON.stringify(game.state) == before, "growth display does not spend points or change progression")
	await capture("04-growth-lower-benefits-fixture")
	print("INVESTMENT_CHOICE_UI assertions=", assertions, " failures=", failures.size(), " clicks=", clicks, " wheels=", wheels, " narrow=", narrow)
	ui.queue_free(); await frames()
	quit(0 if failures.is_empty() else 1)
