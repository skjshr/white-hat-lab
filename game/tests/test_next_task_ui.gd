extends SceneTree

const UI = preload("res://scripts/interface.gd")

var failures: Array[String] = []
var capture_enabled := false
var narrow := false

func _init() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("next-task UI timeout"); quit(2))
	call_deferred("run")

func run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	narrow = "--narrow" in OS.get_cmdline_user_args()
	var ui := UI.new()
	root.add_child(ui)
	root.size = Vector2i(960, 600) if narrow else Vector2i(1920, 1080)
	await frames(4)
	var game := ui._game()
	game.save_path = "user://qa-next-task-ui.json"
	game.backup_path = "user://qa-next-task-ui.json.bak"
	game.previous_path = "user://qa-next-task-ui.previous.json"
	game.settings_path = "user://qa-next-task-ui-settings.json"
	check(ui._new_game({"company":"Next Task QA","player":"Tester","aya":"Aya","ren":"Ren"}), "isolated new game")
	ui._set_text_scale(1.3 if narrow else 1.0)
	await frames(3)

	# The first-job coach owns the first story action while it is active.
	var coach = ui.guided_intro
	check(coach != null and coach.active(), "first guided intro is active")
	var panel = ui.next_task_guide
	panel.refresh(1.0)
	check(not panel.visible, "next-task panel yields to first guided intro")
	coach.skip()
	await frames(2)

	# Normal story: the guide derives the next real task and its location.
	game.state.strategy = "operations"
	check(not bool(game.state.get("accepted", false)), "story starts before acceptance")
	panel.refresh(1.0)
	if ui._is_management_panel(ui.current_kind):
		check(not panel.visible, "management guide starts closed")
		var guide_action = ui.modal.find_child("ManagementGuide", true, false)
		check(guide_action is Button, "management guide has an explicit action")
		if guide_action is Button: guide_action.pressed.emit()
		await frames(3)
	check(panel.visible, "story guide visible")
	check(panel.task.get("id", "") == "accept", "story next action is acceptance")
	check(panel.find_child("NextTaskLocate", true, false) is Button, "locate control is named")
	check(panel.find_child("NextTaskHint", true, false) is Button, "hint control is named")
	check(panel.find_child("NextTaskToggle", true, false) is Button, "visibility control is named")
	await capture("story-accept")

	# Locate is navigation only. It must not accept the contract.
	var minutes_before_locate: float = float(game.state.get("work", {}).get("minutes", 0.0))
	var revision_before_locate: int = int(game.state.get("revision", 0))
	panel.locate_task()
	await frames(2)
	check(not bool(game.state.get("accepted", false)), "locate does not accept work")
	check(ui.current_kind == "terminal", "locate opens workstation")
	check(is_equal_approx(float(game.state.get("work", {}).get("minutes", 0.0)), minutes_before_locate), "locate does not charge work time")
	check(int(game.state.get("revision", 0)) == revision_before_locate, "locate does not change revision")

	# Preserve an editor draft while locating a different application.
	var desktop = ui.desktop
	if desktop != null:
		desktop._show_app("editor")
		await frames(2)
		if desktop.widgets.has("editor") and is_instance_valid(desktop.widgets.editor.editor):
			var draft_path := "workstation:/home/operator/Documents/qa-draft.txt"
			desktop._open_editor(draft_path)
			desktop.widgets.editor.editor.text = "draft survives locate"
			desktop.editor_path = draft_path
			check(_accept_story(game), "public story acceptance")
			game.state.inspected = true
			panel.refresh(1.0)
			panel.locate_task()
			await frames(2)
			check(str(desktop.drafts.get(draft_path, "")) == "draft survives locate", "locate preserves editor draft")

	# A connected story state exposes the optional baseline and then investigation.
	if not bool(game.state.get("accepted", false)): check(_accept_story(game), "accept story through public API")
	game.state.inspected = true
	game.vm_run("ssh client")
	panel.refresh(1.0)
	check(panel.task.get("id", "") in ["baseline", "investigate"], "connected story derives next observation")

	# Hints come from the resolver; expansion/collapse must not mutate game state.
	var hint_task: Dictionary = panel.task.duplicate(true)
	if str(hint_task.get("hint", "")).is_empty():
		game.state.baseline_recorded = true
		panel.refresh(1.0)
		hint_task = panel.task.duplicate(true)
	check(not str(hint_task.get("hint", "")).is_empty(), "resolver supplies a real hint")
	var hint_revision_before: int = int(game.state.get("revision", 0))
	panel.locate_task()
	await frames(3)
	panel.expanded = false
	panel.toggle_hint()
	check(panel.expanded and panel.hint_scroll.visible, "hint expands")
	await capture("story-diagnostic-hint")
	check(ui.desktop.get_global_rect().position.y >= panel.card.get_global_rect().end.y - 2.0, "expanded guide reserves desktop space")
	panel.toggle_hint()
	check(not panel.expanded and not panel.hint_scroll.visible, "hint collapses")
	check(int(game.state.get("revision", 0)) == hint_revision_before, "hint toggle does not mutate game")

	# Career and advanced work use the board/workbench routes.
	# Start a fresh QA profile so the public career transition is exercised at its
	# supported boundary (before accepting the story contract).
	ui.close_panel(false, false)
	await frames(2)
	check(game.new_game({"company":"Next Task Career QA","player":"Tester","aya":"Aya","ren":"Ren"}), "fresh career QA profile")
	await frames(2)
	ui.guided_intro.skip()
	check(game.choose_strategy("operations"), "public career strategy")
	check(game.start_free_career(), "public free career transition")
	panel.refresh(1.0)
	check(panel.task.get("id", "") == "board" and panel.task.get("route", "") == "board", "career guide opens contract board")
	panel.locate_task()
	await frames(3)
	await capture("career-board")
	check(ui.current_kind == "sales", "career locate opens new orders")
	check(_choose_advanced_hunt(game), "public advanced contract setup")
	panel.refresh(1.0)
	check(not str(panel.task.get("title", "")).is_empty(), "advanced guide has workbench task")
	check(str(panel.task.get("route", "")) in ["advanced", "terminal"], "advanced guide route is native workbench")
	var advanced_minutes_before: float = float(game.state.get("work", {}).get("minutes", 0.0))
	var advanced_revision_before: int = int(game.state.get("revision", 0))
	panel.locate_task()
	await frames(5)
	check(ui.current_kind == "terminal" and ui.desktop.current_app == "advanced", "locate opens advanced workbench")
	check(is_equal_approx(float(game.state.get("work", {}).get("minutes", 0.0)), advanced_minutes_before), "advanced locate does not charge work time")
	check(int(game.state.get("revision", 0)) == advanced_revision_before, "advanced locate does not mutate revision")
	await capture("career-advanced")

	# Preference persists and a failed save restores both state and visible setting.
	game.state.next_task_guide_enabled = true
	check(panel.set_enabled(false), "disable preference saves")
	check(not panel.enabled() and game.load_game(), "disabled preference reloads")
	check(not bool(game.state.get("next_task_guide_enabled", true)), "disabled preference survives load")
	check(panel.set_enabled(true), "re-enable preference saves")
	var old_save: String = str(game.save_path)
	var old_value: bool = panel.enabled()
	game.save_path = "user://qa-next-task-ui-missing-directory/blocked/profile.json"
	check(not panel.set_enabled(false), "failed preference save is reported")
	check(panel.enabled() == old_value, "failed preference save rolls back visibility")
	game.save_path = old_save

	# The panel reserves usable space at both requested capture sizes.
	panel.refresh(1.0)
	check(panel.card.get_global_rect().end.y <= root.size.y + 2.0, "card fits viewport")
	if ui.desktop != null and ui.desktop.visible:
		check(ui.desktop.get_global_rect().position.y >= panel.card.get_global_rect().end.y - 2.0, "desktop begins below guide card")
	for control_name in ["NextTaskLocate", "NextTaskHint", "NextTaskToggle"]:
		var control := panel.find_child(control_name, true, false)
		if control is Control and control.visible:
			check(control.get_global_rect().end.x <= root.size.x + 2.0 and control.get_global_rect().end.y <= root.size.y + 2.0, control_name + " fits viewport")
	for failure in failures: push_error("NEXT_TASK_UI: " + failure)
	print("NEXT_TASK_UI failures=", failures.size(), " narrow=", narrow)
	quit(1 if not failures.is_empty() else 0)

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("FAIL ", label)

func frames(count: int) -> void:
	for _i in count: await process_frame

func capture(label: String) -> void:
	if not capture_enabled: return
	# Native capture is the visual acceptance path. Headless runs still execute
	# every behavior/layout assertion, but RenderingServer.frame_post_draw never
	# arrives there and would leave the QA process hanging.
	if DisplayServer.get_name() == "headless": return
	await frames(2)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/next-task/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix := "-narrow" if narrow else "-wide"
	var image := root.get_texture().get_image()
	check(image.get_size() == (Vector2i(960, 600) if narrow else Vector2i(1920, 1080)), "capture size " + label)
	check(image.save_png(folder.path_join(label + suffix + ".png")) == OK, "capture " + label)

func _accept_story(game) -> bool:
	if game.has_method("accept_case"): return bool(game.accept_case())
	return bool(game.accept_mission())

func _choose_advanced_hunt(game) -> bool:
	game.state.skills = {"advisory":10,"operations":10,"response":10}
	game.state.peak_profit = 1000000000
	game.state.credit = 1000000
	game.state.market_leads = ["advanced-hunt"]
	game.state.market_day = int(game.state.day)
	game._make_offers()
	for item in game.state.offers:
		if str(item.get("case_id", "")) != "advanced-hunt": continue
		item.market_available = true
		var id := str(item.get("id", ""))
		if id.is_empty(): return false
		return bool(game.set_offer_quote(id, int(game.contract_quote(item).estimated_fee))) and bool(game.choose_contract(id))
	return false
