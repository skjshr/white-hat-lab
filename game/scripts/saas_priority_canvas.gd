extends Control
## Compact saved-state conveyor. Only explicit controls call the supplied action.
const UI = preload("res://scripts/ui_theme.gd")
const BG = Color("132b36")
const INK = Color("f0eee3")
const MUTED = Color("b5c7cd")
const LINE = Color("54717b")
const AMBER = Color("edb767")
const PAPER = Color("e9dfc6")
const MINT = Color("9ed5c2")
const TIMELINE_HEIGHT: float = 36.0
const LANE_HEIGHT: float = 86.0
const CONNECTION_HEIGHT: float = 54.0
const LOSS_HEIGHT: float = 24.0
var model: Dictionary = {}
var factor: float = 1.0
var selected: String = "dispatch"
var rows: Array[Dictionary] = []
var select_action: Callable
var open_action: Callable
var item_action: Callable
var send_action: Callable
var shared: Dictionary = {}

static func tooltip_theme(scale: float) -> Theme:
	var local: Theme = Theme.new()
	local.set_color("font_color", "TooltipLabel", INK)
	local.set_font("font", "TooltipLabel", UI.font(500))
	local.set_font_size("font_size", "TooltipLabel", roundi(14 * scale))
	local.set_stylebox("panel", "TooltipPanel", UI.style(Color("10232d"), Color("9bb8c0"), 8, 9, 6))
	return local

func configure(data: Dictionary, scale: float, selected_queue: String, select_queue: Callable, open_record: Callable, open_item: Callable, dispatch_action: Callable = Callable()) -> void:
	name = "SaasPriorityCanvas"; model = data.duplicate(true); factor = maxf(.5, scale); selected = selected_queue
	select_action = select_queue; open_action = open_record; item_action = open_item; send_action = dispatch_action
	theme = tooltip_theme(factor); size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children(): remove_child(child); child.queue_free()
	rows.clear(); shared.clear()
	for value in model.get("queues", []):
		var queue: Dictionary = value
		_add_lane(queue)
	_add_shared()
	custom_minimum_size.y = (TIMELINE_HEIGHT + LANE_HEIGHT * rows.size() + CONNECTION_HEIGHT + LOSS_HEIGHT) * factor
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout.call_deferred()

func _add_lane(queue: Dictionary) -> void:
	var id: String = str(queue.get("id", ""))
	var title: String = str(queue.get("label", id))
	var lane: Button = Button.new(); lane.name = "PriorityQueue_" + id; lane.set_meta("queue_id", id)
	_style(lane); lane.pressed.connect(func(): if select_action.is_valid(): select_action.call(id))
	lane.draw.connect(_draw_lane.bind(lane, queue)); lane.tooltip_text = title + "を選択 · 時間は進みません"; add_child(lane)
	var approval: Button = _reference("承認 ↗", "PriorityApproval_" + id, str(queue.get("approval_id", "")), title + "の承認原本 / " + str(queue.get("approval_id", "")))
	var receipt_record: Dictionary = _initial_receipt(queue)
	var receipt_id: String = str(receipt_record.get("id", ""))
	var receipt: Button = _reference("受付 ↗", "PriorityReceipt_" + id, receipt_id, "初回の受付原本 / " + str(queue.get("receipt_id", "")))
	var scope: OptionButton = _option("PriorityScope_" + id)
	var scope_values: Array[String] = ["off", "linked", "all"]
	scope.add_item("0件 / 停止"); scope.add_item("当該 %d件" % int(queue.get("approved_count", 0))); scope.add_item("全 %d件" % int(queue.get("all_count", 0)))
	scope.select(scope_values.find(str(queue.get("policy", {}).get("scope", "off"))))
	scope.tooltip_text = title + "の参照範囲を適用 · 1分"
	scope.item_selected.connect(func(index: int): _send("configure", {"queue_id":id, "key":"scope", "value":scope_values[index]}))
	var recipient: OptionButton = _option("PriorityRecipient_" + id)
	var options: Array = model.get("recipient_options", ["minato/dispatch", "minato/claims", "minato/archive"])
	for path in options: recipient.add_item(str(path))
	recipient.select(options.find(str(queue.get("policy", {}).get("recipient", ""))))
	recipient.tooltip_text = title + "の送付扉を適用 · 1分 / 承認: " + str(queue.get("approved_recipient", ""))
	recipient.item_selected.connect(func(index: int): _send("configure", {"queue_id":id, "key":"recipient", "value":str(options[index])}))
	var current: bool = bool(queue.get("current", false))
	var received: bool = not str(queue.get("receipt_id", "")).is_empty()
	var run: Button = _action("✓ 確認済" if current else "再確認 3分" if received else "送付 3分", "PriorityRun_" + id, "run_queue", {"queue_id":id}, title + "を通常連携で送付・再確認 · 3分。既受付の再送はありません。")
	run.disabled = current or not send_action.is_valid()
	var probe: Button = _action("境界試験 2分", "PriorityProbe_" + id, "probe_queue", {"queue_id":id}, title + "の範囲外要求をダミー試験 · 2分")
	var manual: Button = null
	if _has_recovery():
		var recovery: Dictionary = model.recovery
		var available: bool = int(recovery.get("manual_remaining", 0)) > 0
		var manual_title: String = "手動 %d分 ¥%d" % [int(recovery.get("manual_minutes", 2)), int(recovery.get("manual_cost", 900))]
		if received: manual_title = "受付済 / 手動不要"
		elif not available: manual_title = "手動枠 使用済"
		manual = _action(manual_title, "PriorityManual_" + id, "manual_queue", {"queue_id":id}, title + "だけを手動受付 · %d分 / ¥%d / 残%d枠。通常連携・旧同期の設定は変わりません。" % [int(recovery.get("manual_minutes", 2)), int(recovery.get("manual_cost", 900)), int(recovery.get("manual_remaining", 0))])
		manual.disabled = received or not available or not send_action.is_valid()
	var items: Array[Button] = []
	for index in queue.get("items", []).size():
		var item: Dictionary = queue.items[index]
		var button: Button = Button.new(); button.name = "PriorityItem_" + id + "_" + str(index); _style(button)
		button.tooltip_text = str(item.get("id", "")) + " / " + str(item.get("label", ""))
		button.pressed.connect(func(): if item_action.is_valid(): item_action.call(id, index)); add_child(button); items.append(button)
	var normal: Dictionary = _latest(id, ["run_business"])
	var normal_button: Button = _reference(_measurement(queue, normal, "通常"), "PriorityNormalRecord_" + id, str(normal.get("id", "")), title + "の通常連携の保存実測 / " + str(normal.get("id", "")))
	var boundary: Dictionary = _latest(id, ["probe_queue"])
	var boundary_button: Button = _reference(_measurement(queue, boundary, "境界"), "PriorityBoundaryRecord_" + id, str(boundary.get("id", "")), title + "の境界試験原本 / " + str(boundary.get("id", "")))
	rows.append({"queue":queue,"lane":lane,"approval":approval,"receipt":receipt,"scope":scope,"recipient":recipient,"run":run,"probe":probe,"manual":manual,"items":items,"normal":normal_button,"boundary":boundary_button})

func _add_shared() -> void:
	var background: Dictionary = model.get("background", {})
	var enabled: bool = bool(background.get("enabled", false))
	var latest: Dictionary = _latest("", ["scheduled_background_send", "probe_background"])
	var original: Dictionary = latest if not latest.is_empty() else _latest("", ["configure_background"])
	var latest_label: String = "?未実測"
	if latest.is_empty() and not original.is_empty(): latest_label += " · 設定 ↗"
	if not latest.is_empty():
		var old: bool = int(latest.get("data", {}).get("background_revision", -1)) != int(background.get("policy_revision", 0))
		latest_label = ("旧 " if old else "") + ("試験" if str(latest.get("action", "")) == "probe_background" else "通信") + ("↑" if int(latest.get("status", 0)) == 200 else "×") + str(int(latest.get("status", 0)))
	shared.legacy = _reference(("旧 " if _has_recovery() else "背景 ") + ("ON → /shared" if enabled else "OFF × /shared") + " · " + latest_label, "PriorityRecoveryRecord_legacy", str(original.get("id", "")), "全名簿%d件の独立した背景同期 / " % int(background.get("row_count", 0)) + latest_label + " / " + str(original.get("id", "")))
	shared.toggle = _action("停止 1分" if enabled else "有効化 1分", "PriorityBackground", "toggle_background", {"enabled":not enabled}, "旧一括同期だけを" + ("停止" if enabled else "有効化") + " · 1分。通常の二つの業務とは別経路です。")
	shared.probe = _action("同期口試験 2分", "PriorityProbeBackground", "probe_background", {}, "背景同期の送付口をダミー試験 · 2分 / 実送出なし")
	if _has_recovery():
		var recovery: Dictionary = model.recovery
		var ready: bool = str(recovery.get("connector_status", "stopped")) == "ready"
		var connector_id: String = str(recovery.get("rebuild_record_id", "")) if ready else str(recovery.get("initial_record_id", ""))
		shared.connector = _reference("新連携 ✓ 復旧済" if ready else "新連携 × 停止", "PriorityRecoveryRecord_connector", connector_id, "通常業務の共用接続 / " + connector_id)
		shared.rebuild = _action("✓ 復旧済 %d分" % int(recovery.get("rebuilt_minute", 0)) if ready else "復旧 %d分" % int(recovery.get("rebuild_minutes", 6)), "PriorityRebuild", "rebuild_connector", {}, "二つの通常業務の共用連携を復旧 · %d分。旧一括同期は残ります。" % int(recovery.get("rebuild_minutes", 6)))
		shared.rebuild.disabled = ready or not send_action.is_valid()
		shared.manual = _reference("", "PriorityRecoveryRecord_manual", str(recovery.get("manual_record_id", "")), "手動の初回受付原本 / " + str(recovery.get("manual_receipt_id", "")))

func _has_recovery() -> bool:
	return model.get("recovery") is Dictionary and not model.recovery.is_empty()

func _send(action: String, args: Dictionary) -> void:
	if send_action.is_valid(): send_action.call(action, args)

func _style(button: Button) -> void:
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color.TRANSPARENT if key in ["normal", "disabled"] else Color("26444e"), Color.TRANSPARENT, 0, 0, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))

func _control_style(button: BaseButton, filled: bool = true) -> void:
	button.add_theme_font_override("font", UI.font(500)); button.add_theme_font_size_override("font_size", roundi(12 * factor))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: button.add_theme_color_override(key, INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color("25414c") if filled else Color.TRANSPARENT, LINE if filled else Color.TRANSPARENT, 3, 2, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, AMBER, 0, 0, 2))

func _reference(value: String, id: String, record_id: String, hint: String) -> Button:
	var button: Button = Button.new(); button.name = id; button.text = value; button.tooltip_text = hint
	_control_style(button, false); button.disabled = record_id.is_empty(); button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func(): if open_action.is_valid(): open_action.call(record_id)); add_child(button); return button

func _action(value: String, id: String, action: String, args: Dictionary, hint: String) -> Button:
	var button: Button = Button.new(); button.name = id; button.text = value; button.tooltip_text = hint
	_control_style(button); button.disabled = not send_action.is_valid(); button.pressed.connect(_send.bind(action, args)); add_child(button); return button

func _option(id: String) -> OptionButton:
	var button: OptionButton = OptionButton.new(); button.name = id; _control_style(button); button.disabled = not send_action.is_valid(); add_child(button)
	var popup: PopupMenu = button.get_popup(); popup.add_theme_stylebox_override("panel", UI.style(BG, LINE, 4, 4, 2))
	popup.add_theme_font_override("font", UI.font(500)); popup.add_theme_font_size_override("font_size", roundi(12 * factor))
	for key in ["font_color", "font_hover_color", "font_disabled_color"]: popup.add_theme_color_override(key, INK)
	popup.add_theme_stylebox_override("hover", UI.style(Color("405761"), AMBER, 3, 2, 1)); return button

func _latest(queue_id: String, actions: Array) -> Dictionary:
	var found: Dictionary = {}
	for value in model.get("records", []):
		var record: Dictionary = value
		if str(record.get("action", "")) in actions and str(record.get("data", {}).get("queue_id", "")) == queue_id: found = record
	return found

func _initial_receipt(queue: Dictionary) -> Dictionary:
	var wanted: String = str(queue.get("receipt_id", ""))
	if wanted.is_empty(): return {}
	for value in model.get("records", []):
		var record: Dictionary = value
		if str(record.get("action", "")) in ["run_business", "manual_business"] and int(record.get("status", 0)) == 200 and str(record.get("data", {}).get("queue_id", "")) == str(queue.get("id", "")) and str(record.get("data", {}).get("receipt_id", "")) == wanted: return record
	return {}

func _measurement(queue: Dictionary, record: Dictionary, title: String) -> String:
	if record.is_empty(): return title + " ? 未実測"
	var data: Dictionary = record.get("data", {})
	var before: bool = _has_recovery() and str(data.get("connector_record_id", "")) != str(model.recovery.get("rebuild_record_id", ""))
	var old: bool = int(data.get("policy_revision", -1)) != int(queue.get("policy_revision", 0))
	return ("復旧前 " if before else "旧設定 " if old else "") + title + (" ↑" if int(record.get("status", 0)) == 200 else " ×") + "%d · %d分 ↗" % [int(record.get("status", 0)), int(record.get("minute", 0))]

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position * factor; control.size = rect.size * factor

func _layout() -> void:
	if size.x <= 0: return
	var width: float = size.x / factor
	for index in rows.size():
		var row: Dictionary = rows[index]
		var y: float = TIMELINE_HEIGHT + index * LANE_HEIGHT + (CONNECTION_HEIGHT if index > 0 else 0.0)
		_place(row.lane, Rect2(8, y, width - 16, LANE_HEIGHT))
		_place(row.approval, Rect2(width - 154, y + 1, 68, 21)); _place(row.receipt, Rect2(width - 82, y + 1, 68, 21))
		var inner: float = width - 28; var gap: float = 7.0
		var scope_width: float = clampf(inner * .16, 88, 112)
		var recipient_width: float = clampf(inner * .235, 130, 165)
		var run_width: float = 96.0; var probe_width: float = 108.0
		var x: float = 14.0
		_place(row.scope, Rect2(x, y + 39, scope_width, 25)); x += scope_width + gap
		_place(row.recipient, Rect2(x, y + 39, recipient_width, 25)); x += recipient_width + gap
		_place(row.run, Rect2(x, y + 39, run_width, 25)); x += run_width + gap
		_place(row.probe, Rect2(x, y + 39, probe_width, 25)); x += probe_width + gap
		if row.manual != null: _place(row.manual, Rect2(x, y + 39, maxf(108, width - 14 - x), 25))
		_place(row.normal, Rect2(14, y + 65, 232, 20)); _place(row.boundary, Rect2(255, y + 65, 230, 20))
		for item_index in row.items.size(): _place(row.items[item_index], Rect2(20 + item_index * 16, y + 22, 15, 14))
		row.lane.queue_redraw()
	var cy: float = TIMELINE_HEIGHT + LANE_HEIGHT
	var legacy_x: float = width * .59
	_place(shared.legacy, Rect2(legacy_x, cy + 2, width - legacy_x - 12, 22))
	var legacy_width: float = (width - legacy_x - 19) / 2
	_place(shared.toggle, Rect2(legacy_x, cy + 26, legacy_width, 25)); _place(shared.probe, Rect2(legacy_x + legacy_width + 7, cy + 26, legacy_width, 25))
	if _has_recovery():
		_place(shared.connector, Rect2(16, cy + 2, 166, 22)); _place(shared.rebuild, Rect2(16, cy + 26, 164, 25))
		_place(shared.manual, Rect2(200, cy + 2, legacy_x - 212, 48))
	queue_redraw()

func _text(on: Control, value: String, point: Vector2, points: int = 12, color: Color = INK, width: float = -1) -> void:
	on.draw_string(UI.font(500), point * factor, value, HORIZONTAL_ALIGNMENT_LEFT, width * factor if width >= 0 else -1, roundi(points * factor), color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_draw_timeline(); _draw_shared(); _draw_losses()

func _draw_timeline() -> void:
	var width: float = size.x / factor; var now: int = int(model.get("elapsed_minutes", 0)); var start: float = 64.0; var end: float = width - 20
	var maximum: int = maxi(18, now + 1)
	for queue in model.get("queues", []): maximum = maxi(maximum, int(queue.get("deadline_minute", 0)) + 2)
	draw_line(Vector2(start, 19) * factor, Vector2(end, 19) * factor, LINE, factor)
	_text(self, "%02d分" % now, Vector2(10, 23), 16, AMBER)
	for queue in model.get("queues", []):
		var minute: int = int(queue.get("deadline_minute", 0)); var x: float = lerpf(start, end, float(minute) / maximum)
		var text: String = ("配送" if str(queue.get("id", "")) == "dispatch" else "返金") + str(minute)
		draw_line(Vector2(x, 8) * factor, Vector2(x, 23) * factor, AMBER, factor); _text(self, text, Vector2(x - 20, 11), 11, AMBER)
	for event in model.get("background", {}).get("schedule", []):
		var minute: int = int(event.get("due_minute", 0)); var x: float = lerpf(start, end, float(minute) / maximum)
		draw_line(Vector2(x, 17) * factor, Vector2(x, 26) * factor, MUTED, factor); _text(self, "同期%d" % minute, Vector2(x - 19, 34), 10, MUTED)
	var current_x: float = lerpf(start, end, float(now) / maximum)
	draw_colored_polygon(PackedVector2Array([Vector2(current_x - 4, 14) * factor, Vector2(current_x + 4, 14) * factor, Vector2(current_x, 21) * factor]), INK)

func _draw_shared() -> void:
	var width: float = size.x / factor; var y: float = TIMELINE_HEIGHT + LANE_HEIGHT; var background: Dictionary = model.get("background", {})
	draw_rect(Rect2(Vector2(8, y) * factor, Vector2(width - 16, CONNECTION_HEIGHT) * factor), Color("0d222c"))
	var ready: bool = not _has_recovery() or str(model.recovery.get("connector_status", "stopped")) == "ready"
	var line_ink: Color = MINT if ready else MUTED
	for row in rows:
		var lane: Button = row.lane; var target_y: float = lane.position.y / factor + 51
		_route(Vector2(6, y + 27), Vector2(6, target_y), line_ink, ready); _route(Vector2(6, target_y), Vector2(13, target_y), line_ink, ready)
		if not ready: _text(self, "×", Vector2(0, target_y + 4), 11, MUTED)
	_route(Vector2(6, y + 27), Vector2(14, y + 27), line_ink, ready)
	if _has_recovery():
		var recovery: Dictionary = model.recovery; var remaining: int = int(recovery.get("manual_remaining", 0)); var x: float = 202
		draw_rect(Rect2(Vector2(x, y + 8) * factor, Vector2(19, 23) * factor), PAPER if remaining > 0 else BG)
		draw_rect(Rect2(Vector2(x, y + 8) * factor, Vector2(19, 23) * factor), AMBER, false, factor)
		_text(self, str(remaining), Vector2(x + 5, y + 25), 14, BG if remaining > 0 else AMBER)
		draw_line(Vector2(x - 3, y + 35) * factor, Vector2(x + 24, y + 35) * factor, AMBER, 2 * factor)
		for wheel in [x + 3, x + 20]: draw_circle(Vector2(wheel, y + 39) * factor, 3 * factor, AMBER, false, factor)
		_text(self, "手動 %d/%d枠 · ¥%d" % [remaining, int(recovery.get("manual_limit", 1)), int(recovery.get("manual_cost", 900))], Vector2(x + 30, y + 20), 12, AMBER, width * .59 - x - 39)
		var used: String = str(recovery.get("manual_queue_id", ""))
		var manual_text: String = "未使用" if used.is_empty() else ("配送" if used == "dispatch" else "返金") + " ✓ %d分受付 ↗" % int(recovery.get("manual_used_minute", 0))
		_text(self, manual_text, Vector2(x + 30, y + 40), 11, MUTED, width * .59 - x - 39)
	else:
		_text(self, "通常業務 → 二つの送付扉", Vector2(20, y + 22), 13, INK, width * .55 - 24)
		_text(self, "背景同期は別経路", Vector2(20, y + 42), 12, MUTED)
	var legacy_x: float = width * .59 - 10
	draw_line(Vector2(legacy_x, y + 5) * factor, Vector2(legacy_x, y + 49) * factor, LINE, factor)

func _route(from: Vector2, to: Vector2, color: Color, available: bool) -> void:
	if available: draw_line(from * factor, to * factor, color, 1.5 * factor)
	else: draw_dashed_line(from * factor, to * factor, color, factor, 4 * factor)

func _draw_lane(on: Button, queue: Dictionary) -> void:
	var width: float = on.size.x / factor; var id: String = str(queue.get("id", "")); var policy: Dictionary = queue.get("policy", {})
	var count: int = int(queue.get("all_count", 0)) if str(policy.get("scope", "")) == "all" else int(queue.get("approved_count", 0)) if str(policy.get("scope", "")) == "linked" else 0
	on.draw_line(Vector2(0, 0) * factor, Vector2(width, 0) * factor, LINE, factor)
	if id == selected: on.draw_rect(Rect2(Vector2(0, 3) * factor, Vector2(3, 81) * factor), AMBER)
	_text(on, str(queue.get("label", id)), Vector2(8, 17), 14, INK, 140)
	var loss: int = int(queue.get("loss_cost", 0)); var received: bool = not str(queue.get("receipt_id", "")).is_empty()
	var deadline_text: String = "%d分期限 / 遅延時 ¥%d" % [int(queue.get("deadline_minute", 0)), int(queue.get("late_cost", 0))]
	if loss > 0: deadline_text = "× 締切%d分 / 補償 ¥%d" % [int(queue.get("deadline_minute", 0)), loss]
	elif received: deadline_text = "✓ %d分期限内 / 補償 ¥0" % int(queue.get("deadline_minute", 0))
	_text(on, deadline_text, Vector2(160, 17), 12, AMBER if loss > 0 or not received else MINT, width - 312)
	for index in mini(count, 6):
		var x: float = 12 + index * 16; var rect: Rect2 = Rect2(Vector2(x, 23) * factor, Vector2(13, 12) * factor)
		on.draw_rect(rect, PAPER if index < int(queue.get("approved_count", 0)) else Color("859ca4")); on.draw_rect(rect, MUTED, false, factor)
		if id == "claims": _text(on, "¥", Vector2(x + 2, 33), 9, BG)
		else: on.draw_line(Vector2(x, 23) * factor, Vector2(x + 6, 29) * factor, BG, factor); on.draw_line(Vector2(x + 6, 29) * factor, Vector2(x + 13, 23) * factor, BG, factor)
	if count == 0: on.draw_rect(Rect2(Vector2(12, 23) * factor, Vector2(87, 12) * factor), LINE, false, factor)
	_text(on, "現在%d / 承認%d件" % [count, int(queue.get("approved_count", 0))], Vector2(114, 34), 11, INK, 133)
	_text(on, "許可札 " + _path(str(queue.get("approved_recipient", ""))), Vector2(253, 34), 11, AMBER, 151)
	var stamp_x: float = maxf(419, width - 225)
	on.draw_rect(Rect2(Vector2(stamp_x, 22) * factor, Vector2(width - stamp_x - 5, 15) * factor), MINT if received else LINE, false, factor)
	var stamp: String = "… 未受付"
	if received:
		stamp = ("手動" if str(queue.get("receipt_channel", "")) == "manual" else "通常") + "%d分 · " % int(queue.get("received_minute", 0)) + str(queue.get("receipt_id", "")).trim_prefix("RCPT-")
	_text(on, stamp, Vector2(stamp_x + 4, 34), 10, MINT if received else MUTED, width - stamp_x - 12)

func _draw_losses() -> void:
	var width: float = size.x / factor; var y: float = TIMELINE_HEIGHT + LANE_HEIGHT * rows.size() + CONNECTION_HEIGHT
	draw_line(Vector2(8, y) * factor, Vector2(width - 8, y) * factor, LINE, factor)
	var lost: int = int(model.get("leaked_rows", 0)); var loss: int = int(model.get("loss_cost", 0))
	_text(self, "累積 ↑%d行 / 流出補償 ¥%d" % [lost, int(model.get("impact_cost", 0))], Vector2(12, y + 17), 12, AMBER if lost > 0 else MUTED, width * .44 - 12)
	_text(self, ("× " if loss > 0 else "") + "遅延補償 ¥%d" % loss, Vector2(width * .44, y + 17), 12, AMBER if loss > 0 else MUTED, width * .28 - 10)
	if _has_recovery(): _text(self, "手動費 ¥%d" % int(model.recovery.get("manual_usage_cost", 0)), Vector2(width * .72, y + 17), 12, MUTED, width * .28 - 12)

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
