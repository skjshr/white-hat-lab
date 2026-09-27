extends SceneTree

const WINDOW = preload("res://scripts/os_window.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)

func _inside_parent(window: Control, host: Control) -> bool:
	var rect: Rect2 = Rect2(window.position, window.size)
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= host.size.x + 0.1 and rect.end.y <= host.size.y + 0.1

func _buttons_inside_parent(window: Control, host: Control) -> bool:
	for button in window.chrome_buttons:
		var rect: Rect2 = button.get_global_rect()
		var host_rect: Rect2 = host.get_global_rect()
		if rect.position.x < host_rect.position.x - 0.1 or rect.end.x > host_rect.end.x + 0.1:
			return false
		if rect.position.y < host_rect.position.y - 0.1 or rect.end.y > host_rect.end.y + 0.1:
			return false
	return true

func _drag_region_stops_before_buttons(window: Control) -> bool:
	var drag_rect: Rect2 = window.title_drag_handle.get_global_rect()
	var first_button: Rect2 = window.chrome_buttons[0].get_global_rect()
	return drag_rect.end.x <= first_button.position.x + 0.1 and drag_rect.position.y < first_button.end.y and drag_rect.end.y > first_button.position.y

func run() -> void:
	var host := Control.new()
	host.size = Vector2(960, 600)
	root.add_child(host)
	var window: Control = WINDOW.new()
	host.add_child(window)
	window.configure("mail", "Outwatch", Color.WHITE)
	window.position = Vector2(220, 180)
	window.size = Vector2(530, 320)
	await process_frame
	await process_frame
	check(_inside_parent(window, host), "initial window fits desktop area")
	check(_buttons_inside_parent(window, host), "initial title buttons stay reachable")
	check(_drag_region_stops_before_buttons(window), "drag region follows actual chrome buttons")

	window.position = Vector2(900, 560)
	window.clamp_to_desktop()
	check(_inside_parent(window, host), "drag clamp uses window bounds")
	check(_buttons_inside_parent(window, host), "drag clamp keeps title buttons reachable")

	window.toggle_maximize()
	check(window.maximized and window.position == Vector2.ZERO and window.size == host.size, "maximize fills current desktop")
	host.size = Vector2(600, 340)
	await process_frame
	check(window.maximized and window.position == Vector2.ZERO and window.size == host.size, "maximized window follows parent resize")
	check(_buttons_inside_parent(window, host), "maximized title buttons stay reachable")

	window.toggle_maximize()
	await process_frame
	check(not window.maximized and _inside_parent(window, host), "restore is clamped after parent resize")
	check(_buttons_inside_parent(window, host), "restored title buttons stay reachable")

	# Switching contracts removes desktop windows before deferred deletion.
	# Their previous host can still resize while the replacement view is built.
	host.remove_child(window)
	check(not host.resized.is_connected(window._parent_resized), "detached window disconnects old desktop resize")
	host.size = Vector2(960, 600)
	await process_frame
	host.add_child(window)
	check(host.resized.is_connected(window._parent_resized), "reattached window observes current desktop")
	window.toggle_maximize()
	host.size = Vector2(720, 480)
	await process_frame
	check(_inside_parent(window, host), "reattached window still follows resize")

	if failures.is_empty():
		print("WINDOW_LAYOUT_OK")
		quit(0)
	else:
		print("WINDOW_LAYOUT_FAIL count=", failures.size())
		quit(1)
