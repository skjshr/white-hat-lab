extends "res://scripts/saas_session_canvas.gd"
## Current approval and the selected saved request share the same object scale.
var comparison_y := 0.0

func configure(value: Dictionary, scale: float, selection: String, action: Callable) -> void:
	super.configure(value, scale, selection, action)
	name = "SaasPartnerCompareCanvas"

func _layout() -> void:
	if size.x <= 0: return
	wide = true
	var columns := 3 if size.x / factor >= 540 else 2 if size.x / factor >= 360 else 1
	var width := size.x / columns; var index := 0
	for id in tickets:
		var button: Button = tickets[id]; var tile_width := minf(172 * factor, width - 12 * factor)
		button.position = Vector2((index % columns) * width + (width - tile_width) * .5, (56 + floori(float(index) / columns) * 109) * factor)
		button.size = Vector2(tile_width, 80 * factor)
		index += 1
	comparison_y = (56 + ceili(float(index) / columns) * 109 + 5) * factor
	custom_minimum_size.y = comparison_y + 166 * factor
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	_text(self, str(model.get("app", "")) + " / " + str(model.get("label", "")), Vector2(10, 21) * factor, 16, INK, size.x - 20 * factor)
	_text(self, str(model.get("approval", "")), Vector2(10, 42) * factor, 13, MUTED, size.x - 20 * factor)
	for id in tickets:
		var button: Button = tickets[id]; var row: Dictionary = rows[id]
		if button.position.y <= 56 * factor:
			draw_line(Vector2(10 * factor, 50 * factor), Vector2(button.get_rect().get_center().x, 50 * factor), LINE, factor)
			draw_line(Vector2(button.get_rect().get_center().x, 50 * factor), Vector2(button.get_rect().get_center().x, button.position.y), LINE, factor)
		_text(self, str(row.get("device", "")), button.position + Vector2(9 * factor, button.size.y + 18 * factor), 13, INK, button.size.x - 18 * factor)
	var selected_row: Dictionary = rows.get(selected, {})
	var requested := str(selected_row.get("requested_destination", "")); var approved: Dictionary = {}
	var approvals: Array = model.get("approved_destinations", [])
	if not requested.is_empty():
		for target in approvals:
			if str(target.get("destination", "")).get_slice("/", 0) == requested.get_slice("/", 0): approved = target; break
	var gap := 44 * factor; var width := (size.x - gap - 20 * factor) * .5
	var left := Rect2(10 * factor, comparison_y, width, 158 * factor)
	var right := Rect2(left.end.x + gap, comparison_y, width, 158 * factor)
	if approved.is_empty():
		_text(self, "承認原本 " + str(model.get("approved_change", "")), left.position + Vector2(0, 14) * factor, 13, MUTED, left.size.x)
		for index in approvals.size():
			var entry: Dictionary = approvals[index]
			var y := left.position.y + (43 + index * 40) * factor
			draw_rect(Rect2(left.position.x, y - 15 * factor, 14 * factor, 18 * factor), LINE, false, factor)
			_text(self, str(entry.get("destination", "")), Vector2(left.position.x + 22 * factor, y), 12, INK, left.size.x - 22 * factor)
	else:
		_storage(left, "承認された置き場", str(approved.get("destination", "")), int(approved.get("rows", -1)), str(model.get("approved_change", "")))
	_storage(right, "今回の要求先" + (" / " + selected if not selected_row.is_empty() else ""), requested, int(selected_row.get("read_rows", -1)), str(selected_row.get("request_record_id", "")))
	_text(self, "比較", Vector2(left.end.x + 7 * factor, comparison_y + 75 * factor), 12, MUTED, gap - 10 * factor)
	if not selected_row.is_empty(): _text(self, str(selected_row.get("measurement", "? 未実測")), Vector2(right.position.x, comparison_y + 157 * factor), 12, MUTED, right.size.x)

func _storage(rect: Rect2, title: String, destination: String, count: int, source: String) -> void:
	_text(self, title, rect.position + Vector2(0, 14) * factor, 13, MUTED, rect.size.x)
	if destination.is_empty() or destination == "unknown":
		draw_arc(rect.position + Vector2(rect.size.x * .5, 73 * factor), 25 * factor, 0, TAU, 32, LINE, factor, true)
		_text(self, "?", rect.position + Vector2(rect.size.x * .5 - 7 * factor, 81 * factor), 24, MUTED)
		_text(self, "要求未調査", rect.position + Vector2(4, 122) * factor, 13, MUTED, rect.size.x - 8 * factor)
		return
	var service := destination.get_slice("/", 0); var folder := destination.trim_prefix(service + "/")
	var cabinet := Rect2(rect.position + Vector2(0, 27) * factor, Vector2(rect.size.x, 80 * factor))
	draw_rect(cabinet, Color("edf2f3")); draw_rect(cabinet, LINE, false, factor)
	_text(self, service + (" · " + str(model.get("partner_name", "")) if service == "partner-vault" else ""), cabinet.position + Vector2(9, 20) * factor, 14, INK, cabinet.size.x - 18 * factor)
	var drawer := Rect2(cabinet.position + Vector2(9, 38) * factor, Vector2(cabinet.size.x - 18 * factor, 34 * factor))
	draw_rect(drawer, Color("fbfaf4")); draw_rect(drawer, MUTED, false, factor)
	if service == "invoice":
		draw_polyline(PackedVector2Array([drawer.position + Vector2(drawer.size.x - 11 * factor, 0), drawer.position + Vector2(drawer.size.x - 11 * factor, 8 * factor), drawer.position + Vector2(drawer.size.x, 8 * factor)]), MUTED, factor)
	else:
		draw_rect(Rect2(drawer.position - Vector2(0, 7) * factor, Vector2(minf(53 * factor, drawer.size.x), 7 * factor)), Color("fbfaf4"))
		draw_polyline(PackedVector2Array([drawer.position, drawer.position - Vector2(0, 7) * factor, drawer.position + Vector2(minf(53 * factor, drawer.size.x), -7 * factor)]), MUTED, factor)
	_text(self, folder, drawer.position + Vector2(8, 25) * factor, 18, INK, drawer.size.x - 16 * factor)
	_text(self, "%d行" % count if count >= 0 else "? 行", rect.position + Vector2(2, 126) * factor, 13, MUTED, rect.size.x * .35)
	_text(self, source, rect.position + Vector2(rect.size.x * .37, 126 * factor), 11, MUTED, rect.size.x * .63)
