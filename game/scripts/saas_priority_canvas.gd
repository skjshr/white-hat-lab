extends Control
## A two-lane dispatch board built only from the saved queue projection.
const UI = preload("res://scripts/ui_theme.gd")
const BG = Color("132b36")
const INK = Color("f0eee3")
const MUTED = Color("b5c7cd")
const LINE = Color("54717b")
const AMBER = Color("edb767")
const PAPER = Color("e9dfc6")
const MINT = Color("9ed5c2")
var model: Dictionary = {}
var factor := 1.0
var selected := "dispatch"
var rows: Array[Dictionary] = []
var select_action: Callable
var open_action: Callable
var item_action: Callable
var timeline_height := 63.0
var row_height := 140.0
var recovery_height := 0.0
var recovery_references: Dictionary = {}

static func tooltip_theme(scale: float) -> Theme:
	var local := Theme.new()
	local.set_color("font_color", "TooltipLabel", INK)
	local.set_font("font", "TooltipLabel", UI.font(500))
	local.set_font_size("font_size", "TooltipLabel", roundi(14 * scale))
	local.set_stylebox("panel", "TooltipPanel", UI.style(Color("10232d"), Color("9bb8c0"), 8, 9, 6))
	return local

func configure(data: Dictionary, scale: float, selected_queue: String, select_queue: Callable, open_record: Callable, open_item: Callable) -> void:
	name = "SaasPriorityCanvas"; model = data.duplicate(true); factor = maxf(.5, scale); selected = selected_queue
	theme = tooltip_theme(factor)
	select_action = select_queue; open_action = open_record; item_action = open_item
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for value in model.get("queues", []):
		var queue: Dictionary = value; var id := str(queue.get("id", ""))
		var lane := Button.new(); lane.name = "PriorityQueue_" + id; lane.set_meta("queue_id", id)
		_style(lane); lane.pressed.connect(func(): select_action.call(id)); lane.draw.connect(_draw_lane.bind(lane, queue)); add_child(lane)
		lane.tooltip_text = str(queue.get("label", id)) + "を選択。選択だけでは時間や設定を変更しません。"
		var approval := Button.new(); approval.name = "PriorityApproval_" + id; approval.text = str(queue.get("approval_id", "")) + " ↗"
		_small(approval); approval.tooltip_text = "承認原本 " + str(queue.get("approval_id", "")); approval.pressed.connect(func(): open_action.call(str(queue.get("approval_id", "")))); add_child(approval)
		var record := _latest(id, ["run_business"]); var record_id := str(record.get("id", ""))
		var receipt := Button.new(); receipt.name = "PriorityReceipt_" + id; receipt.text = "実測 ↗"; receipt.disabled = record_id.is_empty(); _small(receipt)
		receipt.tooltip_text = record_id; receipt.pressed.connect(func(): open_action.call(record_id)); add_child(receipt)
		var item_buttons: Array[Button] = []
		var items: Array = queue.get("items", [])
		for index in items.size():
			var button := Button.new(); button.name = "PriorityItem_" + id + "_" + str(index); _style(button)
			button.tooltip_text = str(items[index].get("id", "")) + " / " + str(items[index].get("label", ""))
			button.pressed.connect(func(): item_action.call(id, index)); add_child(button); item_buttons.append(button)
		rows.append({"queue":queue, "lane":lane, "approval":approval, "receipt":receipt, "items":item_buttons})
	if _has_recovery():
		var recovery: Dictionary = model.recovery
		var connector_id := str(recovery.get("rebuild_record_id", ""))
		if connector_id.is_empty(): connector_id = str(recovery.get("initial_record_id", ""))
		var legacy_id := str(recovery.get("initial_record_id", ""))
		for record in model.get("records", []):
			if str(record.get("action", "")) in ["scheduled_background_send", "probe_background", "configure_background"]: legacy_id = str(record.get("id", ""))
		var ids := {"connector":connector_id, "manual":str(recovery.get("manual_record_id", "")), "legacy":legacy_id}
		for key in ids:
			var record_id := str(ids[key]); var reference := Button.new(); reference.name = "PriorityRecoveryRecord_" + str(key)
			_style(reference)
			for state in ["hover", "pressed"]: reference.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 1))
			reference.tooltip_text = str({"connector":"新連携の停止・復旧原本", "manual":"手動受付の原本", "legacy":"旧セッションの独立した背景同期"}[key]) + (" / " + record_id if not record_id.is_empty() else " / まだ使用していません")
			reference.disabled = record_id.is_empty(); reference.pressed.connect(func(): open_action.call(record_id)); add_child(reference); recovery_references[key] = reference
	resized.connect(_layout); _layout.call_deferred()

func _has_recovery() -> bool:
	return model.get("recovery") is Dictionary and not model.recovery.is_empty()

func _style(button: Button) -> void:
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color.TRANSPARENT if key in ["normal", "disabled"] else Color("26444e"), Color.TRANSPARENT, 0, 0, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))

func _small(button: Button) -> void:
	button.add_theme_font_override("font", UI.font(500)); button.add_theme_font_size_override("font_size", roundi(12 * factor))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]: button.add_theme_color_override(key, INK)
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color("25414c"), LINE, 4, 3, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))

func _latest(queue_id: String, actions: Array) -> Dictionary:
	var found: Dictionary = {}
	for record in model.get("records", []):
		if str(record.get("action", "")) in actions and str(record.get("data", {}).get("queue_id", "")) == queue_id: found = record
	return found

func _layout() -> void:
	if size.x <= 0: return
	var width := size.x / factor
	row_height = 145 if width >= 720 else 181
	recovery_height = (90 if width >= 720 else 112) if _has_recovery() else 0
	for index in rows.size():
		var row: Dictionary = rows[index]; var y: float = timeline_height + index * row_height + (recovery_height if index > 0 else 0.0)
		var lane: Button = row.lane; lane.position = Vector2(8, y) * factor; lane.size = Vector2(width - 16, row_height - 5) * factor
		var approval: Button = row.approval; approval.position = Vector2(width - 161, y + 5) * factor; approval.size = Vector2(144, 25) * factor
		var receipt: Button = row.receipt; receipt.position = Vector2(width - 92, y + row_height - 35) * factor; receipt.size = Vector2(74, 25) * factor
		var compact := width < 720
		var item_y: float = y + (67.0 if compact else 51.0)
		for item_index in row.items.size():
			var item: Button = row.items[item_index]
			item.position = Vector2(24 + item_index * 30, item_y) * factor; item.size = Vector2(27, 40) * factor
		lane.queue_redraw()
	if _has_recovery():
		var center_y := timeline_height + row_height + recovery_height / 2
		var shapes := {"connector":Rect2(width * .35, center_y - 22, width * .16, 44), "manual":Rect2(17, center_y - 33, minf(180, width * .29), 68), "legacy":Rect2(width * .66, center_y - 33, width * .32 - 10, 68)}
		for key in recovery_references:
			var button: Button = recovery_references[key]; var shape: Rect2 = shapes[key]
			button.position = shape.position * factor; button.size = shape.size * factor
	custom_minimum_size.y = (timeline_height + rows.size() * row_height + recovery_height + 7) * factor; queue_redraw()

func _text(on: Control, value: String, point: Vector2, points: int = 14, color: Color = INK, width: float = -1) -> void:
	on.draw_string(UI.font(500), point * factor, value, HORIZONTAL_ALIGNMENT_LEFT, width * factor if width >= 0 else -1, roundi(points * factor), color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var width := size.x / factor; var now := int(model.get("elapsed_minutes", 0)); var start := 62.0; var end := width - 28
	var ticks: Dictionary = {}
	for queue in model.get("queues", []): ticks[int(queue.get("deadline_minute", 0))] = "期限"
	for event in model.get("background", {}).get("schedule", []): ticks[int(event.get("due_minute", 0))] = "同期"
	var maximum := maxi(18, now + 1)
	for time in ticks: maximum = maxi(maximum, int(time) + 2)
	draw_line(Vector2(start, 28) * factor, Vector2(end, 28) * factor, LINE, 2 * factor)
	_text(self, "%02d分" % now, Vector2(10, 28), 16, AMBER)
	for time in ticks:
		var x := lerpf(start, end, float(time) / maximum)
		var background := str(ticks[time]) == "同期"
		draw_line(Vector2(x, 22) * factor, Vector2(x, 35) * factor, MUTED if background else AMBER, factor)
		_text(self, "%d" % time, Vector2(x - 7, 18), 12, MUTED if background else AMBER)
		_text(self, "同期" if background else "期限", Vector2(x - 12, 48), 11, MUTED if background else AMBER)
	var current_x := lerpf(start, end, float(now) / maximum)
	draw_colored_polygon(PackedVector2Array([Vector2(current_x - 5, 22) * factor, Vector2(current_x + 5, 22) * factor, Vector2(current_x, 30) * factor]), INK)
	if _has_recovery(): _draw_recovery()

func _route(from: Vector2, to: Vector2, color: Color, available: bool) -> void:
	if available: draw_line(from * factor, to * factor, color, 1.5 * factor)
	else: draw_dashed_line(from * factor, to * factor, color, factor, 5 * factor)

func _draw_recovery() -> void:
	var width := size.x / factor; var recovery: Dictionary = model.recovery; var ready := str(recovery.get("connector_status", "stopped")) == "ready"
	var cy := timeline_height + row_height + recovery_height / 2; var left := width * .35; var right := width * .51
	var connector_ink := MINT if ready else MUTED
	for row in rows:
		var lane: Button = row.lane; var lane_width := lane.size.x / factor
		var y := lane.position.y / factor + (67 if width < 720 else 51) + 20
		var start := Vector2(lane.position.x / factor + minf(206, lane_width * .35), y)
		var end := Vector2(lane.position.x / factor + lane_width * .53 - 7, y)
		_route(start, Vector2(left - 9, y), connector_ink, ready); _route(Vector2(left - 9, y), Vector2(left - 9, cy), connector_ink, ready)
		_route(Vector2(left - 9, cy), Vector2(left, cy), connector_ink, ready)
		_route(Vector2(right, cy), Vector2(right + 7, cy), connector_ink, ready); _route(Vector2(right + 7, cy), Vector2(right + 7, y), connector_ink, ready); _route(Vector2(right + 7, y), end, connector_ink, ready)
		if not ready:
			_text(self, "×", Vector2(right + 2, y - 6), 15, MUTED)
		draw_line(end * factor, (end + Vector2(-5, -4)) * factor, connector_ink, factor); draw_line(end * factor, (end + Vector2(-5, 4)) * factor, connector_ink, factor)
	draw_rect(Rect2(Vector2(left, cy - 22) * factor, Vector2(right - left, 44) * factor), Color("284854")); draw_rect(Rect2(Vector2(left, cy - 22) * factor, Vector2(right - left, 44) * factor), connector_ink, false, 2 * factor)
	_text(self, "新連携", Vector2(left + 10, cy - 5), 14, INK, right - left - 17)
	_text(self, "✓ 復旧済" if ready else "× 停止", Vector2(left + 10, cy + 14), 13, connector_ink, right - left - 17)
	var remaining := int(recovery.get("manual_remaining", 0)); var used := str(recovery.get("manual_queue_id", "")); var label := ""
	for queue in model.get("queues", []):
		if str(queue.get("id", "")) == used: label = str(queue.get("label", used))
	var manual_width := minf(180, width * .29)
	draw_rect(Rect2(Vector2(19, cy - 28) * factor, Vector2(25, 31) * factor), PAPER if remaining > 0 else BG)
	draw_rect(Rect2(Vector2(19, cy - 28) * factor, Vector2(25, 31) * factor), AMBER if remaining > 0 else LINE, false, factor)
	_text(self, "1" if remaining > 0 else "0", Vector2(27, cy - 6), 17, BG if remaining > 0 else MUTED)
	draw_line(Vector2(16, cy + 8) * factor, Vector2(51, cy + 8) * factor, AMBER, 2 * factor)
	draw_circle(Vector2(23, cy + 14) * factor, 4 * factor, AMBER, false, factor); draw_circle(Vector2(45, cy + 14) * factor, 4 * factor, AMBER, false, factor)
	_text(self, "手動 %d/%d枠" % [remaining, int(recovery.get("manual_limit", 1))], Vector2(59, cy - 10), 13, AMBER, manual_width - 43)
	_text(self, "未使用" if remaining > 0 else "✓ " + label, Vector2(59, cy + 11), 12, MUTED, manual_width - 43)
	if remaining <= 0: _text(self, "%d分 / ¥%d" % [int(recovery.get("manual_used_minute", 0)), int(recovery.get("manual_usage_cost", 0))], Vector2(19, cy + 34), 12, MUTED, manual_width)
	var manual_target := used if not used.is_empty() else selected
	for row in rows:
		if str(row.queue.get("id", "")) != manual_target: continue
		var lane: Button = row.lane
		var receipt_y := lane.position.y / factor + (67 if width < 720 else 51) + 20
		var via_x := width - 11; var via_y := cy + 38
		_route(Vector2(19 + manual_width, via_y), Vector2(via_x, via_y), AMBER if not used.is_empty() else LINE, not used.is_empty())
		_route(Vector2(via_x, via_y), Vector2(via_x, receipt_y), AMBER if not used.is_empty() else LINE, not used.is_empty())
		_route(Vector2(via_x, receipt_y), Vector2(width - 20, receipt_y), AMBER if not used.is_empty() else LINE, not used.is_empty())
	var legacy_x := width * .66; var background: Dictionary = model.get("background", {}); var background_on := bool(background.get("enabled", false))
	draw_circle(Vector2(legacy_x + 9, cy - 18) * factor, 6 * factor, AMBER if background_on else MUTED, false, 2 * factor)
	draw_line(Vector2(legacy_x + 15, cy - 18) * factor, Vector2(legacy_x + 30, cy - 18) * factor, AMBER if background_on else MUTED, 2 * factor)
	_text(self, "旧セッション", Vector2(legacy_x + 36, cy - 13), 13, INK, width - legacy_x - 46)
	_route(Vector2(legacy_x + 7, cy + 1), Vector2(width - 24, cy + 1), AMBER if background_on else LINE, background_on)
	_text(self, "ON ↑ /shared" if background_on else "OFF × /shared", Vector2(legacy_x + 3, cy + 25), 13, AMBER if background_on else MUTED, width - legacy_x - 12)

func _draw_lane(on: Button, queue: Dictionary) -> void:
	var width := on.size.x / factor; var height := on.size.y / factor; var compact := width + 16 < 720
	var id := str(queue.get("id", "")); var selected_lane := id == selected; var policy: Dictionary = queue.get("policy", {})
	var scope := str(policy.get("scope", "off")); var all_count := int(queue.get("all_count", 0)); var approved_count := int(queue.get("approved_count", 0))
	var count := all_count if scope == "all" else approved_count if scope == "linked" else 0
	on.draw_line(Vector2(5, 1) * factor, Vector2(width - 5, 1) * factor, LINE, factor)
	if selected_lane: on.draw_rect(Rect2(Vector2(0, 5) * factor, Vector2(4, height - 10) * factor), AMBER)
	_text(on, ("▶ " if selected_lane else "   ") + str(queue.get("label", id)), Vector2(12, 23), 16, AMBER if selected_lane else INK, width - 175)
	var deadline := int(queue.get("deadline_minute", 0)); var late := bool(queue.get("late", false))
	var deadline_text := "%d分まで / 遅延時 ¥%d" % [deadline, int(queue.get("late_cost", 0))]
	if late: deadline_text = "! 期限超過 / 補償 ¥%d" % int(queue.get("loss_cost", 0))
	_text(on, deadline_text, Vector2(20 if compact else 193, 46 if compact else 23), 12, AMBER if late else MUTED, width - 190 if compact else width - 363)
	var item_y := 67.0 if compact else 51.0
	var items: Array = queue.get("items", [])
	for index in mini(count, 6):
		var x := 16 + index * 30
		var rect := Rect2(Vector2(x, item_y) * factor, Vector2(25, 38) * factor)
		on.draw_rect(rect, PAPER if index < items.size() else Color("8da2a6")); on.draw_rect(rect, MUTED, false, factor)
		if id == "claims":
			_text(on, "¥", Vector2(x + 6, item_y + 18), 13, BG)
			for line in 2: on.draw_line(Vector2(x + 5, item_y + 24 + line * 5) * factor, Vector2(x + 20, item_y + 24 + line * 5) * factor, BG, factor)
		else:
			on.draw_line(Vector2(x, item_y) * factor, Vector2(x + 25, item_y + 14) * factor, LINE, factor)
			on.draw_line(Vector2(x + 25, item_y) * factor, Vector2(x, item_y + 14) * factor, LINE, factor)
	if count == 0:
		on.draw_rect(Rect2(Vector2(16, item_y) * factor, Vector2(86, 38) * factor), LINE, false, factor); _text(on, "0件", Vector2(42, item_y + 25), 16, MUTED)
	_text(on, "現設定 %d件 / 承認 %d件" % [count, approved_count], Vector2(16, item_y + 58), 12, INK, 215)
	var door_x := width * .53; var door_width := width * .21
	var recipient := str(policy.get("recipient", "")); var approved := str(queue.get("approved_recipient", ""))
	var line_y := item_y + 20
	if not _has_recovery(): on.draw_line(Vector2(minf(206, width * .35), line_y) * factor, Vector2(door_x - 7, line_y) * factor, LINE, 2 * factor)
	on.draw_rect(Rect2(Vector2(door_x, item_y - 2) * factor, Vector2(door_width, 44) * factor), Color("2c4b57")); on.draw_rect(Rect2(Vector2(door_x, item_y - 2) * factor, Vector2(door_width, 44) * factor), LINE, false, 2 * factor)
	_text(on, _path(recipient), Vector2(door_x + 8, item_y + 25), 15, INK, door_width - 13)
	_text(on, "許可札 " + _path(approved), Vector2(door_x, item_y + 61), 12, AMBER, width - door_x - 8)
	var record := _latest(id, ["run_business"]); var status := int(record.get("status", 0))
	var stale := not record.is_empty() and int(record.get("data", {}).get("policy_revision", -1)) != int(queue.get("policy_revision", 0))
	var before_rebuild := _has_recovery() and not record.is_empty() and str(record.get("data", {}).get("connector_record_id", "")) != str(model.recovery.get("rebuild_record_id", ""))
	var stamp_x := width * .78; var receipt := str(queue.get("receipt_id", ""))
	on.draw_rect(Rect2(Vector2(stamp_x, item_y) * factor, Vector2(width - stamp_x - 12, 43) * factor), MINT if not receipt.is_empty() else LINE, false, 2 * factor)
	var receipt_title := "✓ 受付控え" if not receipt.is_empty() else "… 未受付"
	if _has_recovery() and not receipt.is_empty(): receipt_title = "手動 %d分" % int(queue.get("received_minute", -1)) if str(queue.get("receipt_channel", "")) == "manual" else "通常 %d分" % int(queue.get("received_minute", -1))
	_text(on, receipt_title, Vector2(stamp_x + 7, item_y + 19), 13, MINT if not receipt.is_empty() else MUTED, width - stamp_x - 20)
	_text(on, receipt.trim_prefix("RCPT-") if not receipt.is_empty() else "番号なし", Vector2(stamp_x + 7, item_y + 36), 10, MUTED, width - stamp_x - 20)
	var measurement := "? 未実行" if record.is_empty() else ("旧設定 " if stale else "") + ("↑ " if status == 200 else "× ") + str(status)
	if _has_recovery(): measurement = "通常接続 ? 未確認" if record.is_empty() else ("復旧前 " if before_rebuild else "旧設定 " if stale else "") + "通常 " + ("↑ " if status == 200 else "× ") + "%d · %d分" % [status, int(record.get("minute", 0))]
	_text(on, measurement, Vector2(16, height - 10), 12, MUTED, 180)
	var probe := _latest(id, ["probe_queue"]); var probe_status := int(probe.get("status", 0))
	var old_probe := not probe.is_empty() and int(probe.get("data", {}).get("policy_revision", -1)) != int(queue.get("policy_revision", 0))
	var old_connector := _has_recovery() and not probe.is_empty() and str(probe.get("data", {}).get("connector_record_id", "")) != str(model.recovery.get("rebuild_record_id", ""))
	_text(on, "境界 ?" if probe.is_empty() else ("復旧前 " if old_connector else "旧設定 " if old_probe else "") + "境界 " + ("↑ " if probe_status == 200 else "× ") + str(probe_status), Vector2(197, height - 10), 12, MUTED, width - 295)

func _path(path: String) -> String:
	return "/" + path.get_slice("/", 1) if path.begins_with("minato/") else path

class Background extends Control:
	var model: Dictionary = {}
	var factor := 1.0
	func configure(data: Dictionary, scale: float) -> void:
		name = "PriorityBackgroundFlow"; model = data.duplicate(true); factor = scale
		size_flags_horizontal = Control.SIZE_EXPAND_FILL; custom_minimum_size.y = 91 * factor; mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var width := size.x / factor; var background: Dictionary = model.get("background", {}); var enabled := bool(background.get("enabled", false))
		draw_rect(Rect2(Vector2.ZERO, size), Color("0c1e27"))
		var font := UI.font(500)
		draw_string(font, Vector2(12, 24) * factor, "背景同期 / 全名簿%d件" % int(background.get("row_count", 0)), HORIZONTAL_ALIGNMENT_LEFT, 250 * factor, roundi(14 * factor), INK)
		var a := Vector2(175, 47) * factor; var b := Vector2(width - 170, 47) * factor
		if enabled: draw_line(a, b, AMBER, 2 * factor)
		else: draw_dashed_line(a, b, LINE, factor, 6 * factor)
		draw_string(font, Vector2(12, 54) * factor, "ON →" if enabled else "OFF ×", HORIZONTAL_ALIGNMENT_LEFT, 140 * factor, roundi(17 * factor), AMBER if enabled else MUTED)
		draw_string(font, Vector2(width - 161, 54) * factor, str(background.get("recipient", "")), HORIZONTAL_ALIGNMENT_LEFT, 150 * factor, roundi(14 * factor), INK)
		draw_string(font, Vector2(12, 79) * factor, "保存累計 ↑%d行 / 流出補償 ¥%d" % [int(model.get("leaked_rows", 0)), int(model.get("impact_cost", 0))], HORIZONTAL_ALIGNMENT_LEFT, (width - 25) * factor, roundi(12 * factor), MUTED)
