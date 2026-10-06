extends SceneTree
## Synthetic model/UI regression only; no player save or native-play evidence.
const MODEL = preload("res://scripts/saas_priority.gd")
const CANVAS = preload("res://scripts/saas_priority_canvas.gd")
var failures: Array[String] = []
var opened: Array[String] = []
var operation_calls := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("SAAS_PRIORITY_CANVAS: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func frames(count: int) -> void:
	for index in count: await process_frame

func click(button: Button) -> void:
	var logical := button.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(logical), "saved observation link is inside the test viewport")
	# Match the application's existing input fixtures under canvas stretching.
	var point := logical * Vector2(root.size) / root.get_visible_rect().size
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	Input.parse_input_event(motion); Input.flush_buffered_events()
	check(root.gui_get_hovered_control() == button, "pointer reaches the displayed observation link")
	for down in [true,false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		Input.parse_input_event(event); Input.flush_buffered_events()
	await frames(2)

func run() -> void:
	var world: Dictionary = MODEL.create()
	var probed: Dictionary = MODEL.act(world,"probe_background")
	check(bool(probed.get("ok",false)) and int(probed.get("data",{}).get("record",{}).get("status",0)) == 200, "public probe produces the original successful background observation")
	world = probed.get("state",world)
	var probe_id := str(probed.get("data",{}).get("record_id",""))
	var stopped: Dictionary = MODEL.act(world,"toggle_background",{"enabled":false})
	world = stopped.get("state",world)
	var stop_id := str(stopped.get("data",{}).get("record_id",""))
	check(bool(stopped.get("ok",false)) and not probe_id.is_empty() and probe_id != stop_id and not bool(world.priority.background.enabled) and not world.priority.has("recovery"), "legacy fixture changes the setting after the measured response without fabricating recovery")
	var before := encoded(world)
	var board := CANVAS.new(); root.add_child(board)
	board.size = Vector2(minf(960,root.get_visible_rect().size.x),320)
	board.configure(MODEL.view(world).priority,1.0,"dispatch",Callable(),func(id: String): opened.append(id),Callable(),func(_action: String,_args: Dictionary): operation_calls += 1)
	await frames(3)
	var button := board.get_node_or_null("PriorityRecoveryRecord_legacy") as Button
	check(button != null and not button.disabled, "canvas exposes the actual saved background original")
	if button != null:
		check(button.text.contains("OFF") and button.text.contains("旧 試験↑200"), "current OFF setting and earlier successful probe remain distinct")
		await click(button)
		check(opened == [probe_id] and stop_id not in opened, "the displayed old measurement opens its probe original, not the newer configuration record")
	check(board.find_children("PriorityRebuild","Button",true,false).is_empty() and board.find_children("PriorityManual_*","Button",true,false).is_empty() and board.get_node_or_null("PriorityRecoveryRecord_connector") == null, "legacy worlds do not generate reconstruction or manual-reception controls")
	check(encoded(world) == before and operation_calls == 0, "rendering and opening evidence cannot advance the model clock, create records or execute business actions")
	board.queue_free(); await frames(1)
	print("SAAS_PRIORITY_CANVAS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
