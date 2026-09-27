extends SceneTree

var game
var office
var ui
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var narrow := "--narrow" in OS.get_cmdline_user_args()
var folder := "res://../artifacts/simulator/ui-refinement-20260922/screens"

func _init() -> void:
	create_timer(100).timeout.connect(func(): push_error("REFINEMENT timeout"); quit(2))
	call_deferred("run")

func frames(count: int = 8) -> void:
	for _i in count: await process_frame

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); print("FAIL ", message)

func node(id: String):
	return ui.modal.find_child(id, true, false) if is_instance_valid(ui.modal) else null

func visible(control: Control) -> bool:
	if not control.is_visible_in_tree(): return false
	var rect := control.get_global_rect()
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	var parent := control.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents: bounds = bounds.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return bounds.encloses(rect) and rect.has_area()

func capture(label: String) -> void:
	await frames(12)
	var labels := 0; var characters := 0; var buttons := 0
	for child in ui.modal.find_children("*", "Control", true, false):
		if not visible(child): continue
		if child is Label and not child.text.is_empty(): labels += 1; characters += child.text.length()
		if child is BaseButton: buttons += 1
	evidence.append({"screen":label,"labels":labels,"characters":characters,"buttons":buttons})
	check(visible(node("ManagementClose")), label + " close reachable")
	check(visible(node("ManagementTabs")), label + " single navigation fits")
	check(node("ManagementTabs").get_parent() == node("ManagementHeader").get_child(0), label + " navigation in one header")
	check(not ui.next_task_guide.visible, label + " no unsolicited guidance strip")
	check(ui.modal_scroll.get_h_scroll_bar().max_value <= ui.modal_scroll.size.x + 1, label + " no horizontal overflow")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path(folder); DirAccess.make_dir_recursive_absolute(path)
		var rendered := root.get_texture().get_image()
		check(rendered.get_size() == (Vector2i(960,600) if narrow else Vector2i(1920,1080)), label + " capture dimensions")
		check(rendered.save_png(path.path_join(label + ("-narrow" if narrow else "-wide") + ".png")) == OK, label + " captured")

func press(id: String) -> void:
	var target = node(id)
	check(target is BaseButton, "button " + id)
	if target is BaseButton: target.pressed.emit()

func run() -> void:
	game = root.get_node("Game")
	check(str(game.save_path).begins_with("user://qa-"), "isolated QA")
	game.set_process(false)
	game.new_game()
	game.choose_strategy("operations"); game.start_free_career()
	game.state.cash = 16000
	game.state.skills = {"advisory": 3, "operations": 3, "response": 3}
	game.state.peak_profit = 40000
	game._make_offers()
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080", "window_mode":"windowed" if narrow else "borderless", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	office = load("res://scripts/office.gd").new(); root.add_child(office); await frames(16)
	ui = office.ui; office.started = true; ui.controls.menu.hide(); ui.guided_intro.skip()
	ui._set_text_scale(1.3 if narrow else 1.0)
	ui.open_panel("company"); await capture("company-overview")
	check(node("CompanyGrowthDetails") == null, "growth is a separate view")
	press("CompanyView_growth"); await capture("company-growth")
	press("CompanyView_care"); await capture("company-customers")
	ui.open_panel("sales"); await capture("sales")
	press("SalesPricingTab"); await capture("pricing")
	for offer in game.state.offers:
		if bool(offer.get("market_available", false)) and bool(offer.get("unlocked", false)):
			ui._select_contract(str(offer.id)); break
	await capture("quote")
	check(visible(node("OfferPrice")), "quote amount visible")
	check(visible(node("AcceptContract")), "quote primary visible")
	ui.board_selected_id = ""
	game.set_customer_cart("gateway", 1); game.set_customer_cart("backup_appliance", 2)
	ui.shop_view = "stock"; ui.set_meta("stock_view", "catalog"); ui.open_panel("shop"); await capture("procurement")
	ui.set_meta("stock_view", "inventory"); ui.open_panel("shop"); await capture("inventory")
	ui.shop_view = "equipment"; ui.open_panel("shop"); await capture("equipment")
	ui.open_panel("staffing"); await capture("staffing")
	ui.open_panel("board"); await capture("operations")
	ui.open_panel("door"); await capture("closeout")
	ui.open_panel("company"); press("ManagementGuide"); await frames(10)
	check(ui.next_task_guide.visible, "requested guidance opens")
	press("ManagementGuide"); await frames(10)
	check(not ui.next_task_guide.visible, "requested guidance closes")
	press("ManagementGuide"); await frames(6)
	var cancel := InputEventAction.new(); cancel.action = "ui_cancel"; cancel.pressed = true
	ui._unhandled_key_input(cancel); await frames(6)
	check(not ui.next_task_guide.visible and ui.current_kind == "company", "escape dismisses guidance before its workspace")
	var path := ProjectSettings.globalize_path(folder); DirAccess.make_dir_recursive_absolute(path)
	var stats := FileAccess.open(path.path_join("density" + ("-narrow" if narrow else "-wide") + ".json"), FileAccess.WRITE)
	stats.store_string(JSON.stringify(evidence,"  ")); stats.close()
	root.get_node("Soundscape").set_workspace(false); root.get_node("Soundscape").set_title_active(false); root.get_node("Soundscape").unmount_world(office)
	office.queue_free(); await create_timer(0.2).timeout
	print("UI_REFINEMENT failures=", failures.size(), " screens=", evidence.size())
	quit(0 if failures.is_empty() else 1)
