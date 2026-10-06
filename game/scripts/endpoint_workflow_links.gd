extends Control
## Configuration is solid; event history is dashed. Neither implies a new probe.
var business: Control
var device: Control
var evidence: Control
var isolated := false
var text_factor := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func bind_controls(job: Control, endpoint: Control, record: Control, blocked: bool, factor: float) -> void:
	business=job;device=endpoint;evidence=record;isolated=blocked;text_factor=factor
	for node in [business, device, evidence]:
		node.item_rect_changed.connect(queue_redraw)
	queue_redraw.call_deferred()

func _draw() -> void:
	if not is_instance_valid(business) or not is_instance_valid(device) or not is_instance_valid(evidence): return
	var y := device.position.y + 53 * text_factor
	var start := Vector2(business.position.x + business.size.x * 0.5 + 34 * text_factor, y)
	var finish := Vector2(device.position.x + device.size.x * 0.5 - 54 * text_factor, y)
	var middle := (start + finish) * 0.5
	if isolated:
		draw_line(start, middle - Vector2(6, 0), Color("8a8886"), 2, true)
		draw_line(middle + Vector2(6, 0), finish, Color("8a8886"), 2, true)
		draw_line(middle - Vector2(4, 4), middle + Vector2(4, 4), Color("a4262c"), 2, true)
		draw_line(middle + Vector2(-4, 4), middle + Vector2(4, -4), Color("a4262c"), 2, true)
	else:
		draw_line(start, finish, Color("0078d4"), 2, true)
		draw_circle(middle, 3, Color("0078d4"))
	start = Vector2(device.position.x + device.size.x * 0.5 + 54 * text_factor, y)
	finish = Vector2(evidence.position.x + evidence.size.x * 0.5 - 30 * text_factor, y)
	draw_dashed_line(start, finish, Color("8a8886"), 1.5, 4, true)
