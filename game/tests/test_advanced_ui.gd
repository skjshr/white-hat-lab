extends "res://tests/test_investigation_ui.gd"
# All nine non-portal cases use their production specialist workspace.
# No hidden generic five-tab controls or bypass solver is installed.
func run() -> void:
	game=root.get_node("Game"); game.set_process(false)
	root.size=Vector2i(960,600) if narrow else Vector2i(1440,900)
	await run_investigation_cases()
	await run_specialist_cases()
	if is_instance_valid(desk): desk.queue_free(); await frames()
	print("ADVANCED_UI_", "PASS" if failures.is_empty() else "FAIL", " assertions=",assertions," engine_clicks=",clicks," native_edits=",native_edits," raw_record_checks=",row_selections," native_resource_clicks=",resource_clicks," native_record_clicks=",native_record_clicks," selection_signals=",selections," field_signals=",edits," narrow=",narrow)
	quit(0 if failures.is_empty() else 1)
