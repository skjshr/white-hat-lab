extends Control
## Draws a saved assistant snapshot. Buttons only open its references or a session.
const UI = preload("res://scripts/ui_theme.gd")
const INK = Color("26333b")
const MUTED = Color("687680")
const LINE = Color("b6c2c9")
const BLUE = Color("286c91")
const AMBER = Color("966526")
const GREEN = Color("367764")
var model: Dictionary = {}
var factor := 1.0
var source_action: Callable
var session_action: Callable
var lane_nodes: Array[Dictionary] = []
var lane_height := 121.0
var columns: Array[Rect2] = []

func configure(value: Dictionary, scale: float, open_source: Callable, open_session: Callable) -> void:
	name = "SaasAssistantCompareCanvas"; model = value.duplicate(true); factor = scale
	source_action = open_source; session_action = open_session
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lane in model.get("lanes", []):
		var id := str(lane.get("session_id", ""))
		var session := Button.new(); session.name = "SaasAssistantSession_" + id.replace("-", "_"); session.text = id + " · " + str(lane.get("device", "?")) + " ↗"
		session.set_meta("session_id", id); session.tooltip_text = "Identity でこの接続券を調査 / " + id
		_style(session); session.add_theme_font_size_override("font_size", roundi(13 * factor)); session.pressed.connect(func(): session_action.call(id)); add_child(session)
		var cells: Array[Button] = []
		for part in ["prior", "approval", "request"]:
			var cell: Dictionary = lane.get(part, {}); var ref_id := str(cell.get("record_id", ""))
			var button := Button.new(); button.name = "SaasAssistantSource_" + id.replace("-", "_") + "_" + part
			button.set_meta("record_id", ref_id)
			button.tooltip_text = ("前回原本" if part == "prior" else "今回承認" if part == "approval" else "要求先") + " / " + str(lane.get("device", "")) + " / " + str(cell.get("service", "")) + "/" + str(cell.get("folder", "")) + " / " + ref_id if not ref_id.is_empty() else "選択した原記録内に比較の根拠がありません"
			button.disabled = ref_id.is_empty(); _style(button)
			button.pressed.connect(func(): source_action.call(ref_id)); button.draw.connect(_draw_cell.bind(button, cell, part))
			add_child(button); cells.append(button)
		lane_nodes.append({"lane": lane, "session": session, "cells": cells})
	resized.connect(_layout); _layout.call_deferred()

func _style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(state, UI.style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, BLUE, 0, 0, 2))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, INK)
	button.clip_text = true

func _layout() -> void:
	if size.x <= 0: return
	var logical_width := size.x / factor
	var gap := 30.0 if logical_width >= 540 else 22.0
	var cell_width := maxf(0, (logical_width - 20 - gap * 2) / 3)
	columns.clear()
	for index in 3: columns.append(Rect2((10 + index * (cell_width + gap)) * factor, 0, cell_width * factor, 77 * factor))
	for index in lane_nodes.size():
		var nodes: Dictionary = lane_nodes[index]; var y := (28 + index * lane_height) * factor
		var session: Button = nodes.session; session.position = Vector2(10 * factor, y); session.size = Vector2(minf(285 * factor, size.x - 20 * factor), 23 * factor)
		for cell_index in 3:
			var button: Button = nodes.cells[cell_index]; button.position = Vector2(columns[cell_index].position.x, y + 27 * factor); button.size = columns[cell_index].size
	custom_minimum_size.y = (28 + lane_nodes.size() * lane_height) * factor
	queue_redraw()

func _text(control: Control, text: String, point: Vector2, points: int = 13, color: Color = INK, width: float = -1) -> void:
	control.draw_string(control.get_theme_default_font(), point, text, HORIZONTAL_ALIGNMENT_LEFT, width, roundi(points * factor), color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("fafaf7"))
	if columns.size() != 3: return
	var headers := ["前回の発行原本", "今回の承認", "選択した要求記録"]
	for index in 3: _text(self, headers[index], Vector2(columns[index].position.x + 4 * factor, 18 * factor), 13, BLUE if index == 1 else MUTED, columns[index].size.x - 8 * factor)
	for index in lane_nodes.size():
		var nodes: Dictionary = lane_nodes[index]; var lane: Dictionary = nodes.lane
		var y := (28 + index * lane_height) * factor
		draw_line(Vector2(10 * factor, y + 115 * factor), Vector2(size.x - 10 * factor, y + 115 * factor), LINE, factor)
		var source_status := str(lane.get("record_state", ""))
		_text(self, source_status, Vector2(minf(305 * factor, size.x * .55), y + 17 * factor), 12, MUTED, size.x - minf(305 * factor, size.x * .55) - 10 * factor)
		var line_y := y + 60 * factor
		var old_end := Vector2(columns[0].end.x + 2 * factor, line_y); var new_start := Vector2(columns[1].position.x - 2 * factor, line_y)
		draw_dashed_line(old_end, new_start, LINE, factor, 3 * factor)
		var start := Vector2(columns[1].end.x + 2 * factor, line_y); var end := Vector2(columns[2].position.x - 2 * factor, line_y)
		var result := str(lane.get("result", "unknown")); var symbol := "=" if result == "match" else "≠" if result == "mismatch" else "?"
		var color := GREEN if result == "match" else AMBER if result == "mismatch" else MUTED
		if result == "unknown": draw_dashed_line(start, end, LINE, factor, 3 * factor)
		else: draw_line(start, end, color, 1.5 * factor)
		var center := (start + end) * .5; draw_circle(center, 10 * factor, Color("fafaf7"))
		_text(self, symbol, center + Vector2(-7, 6) * factor, 19, color, 19 * factor)

func _draw_cell(button: Button, cell: Dictionary, part: String) -> void:
	var known := bool(cell.get("known", false)); var width := button.size.x
	var color := BLUE if part == "approval" else MUTED if part == "prior" else INK
	var paper := Rect2(Vector2(2, 3) * factor, Vector2(maxf(0, width - 4 * factor), 58 * factor))
	var service := str(cell.get("service", "")); var folder := str(cell.get("folder", ""))
	if known:
		button.draw_rect(paper, Color("f5efe1") if part == "prior" else Color("eaf2f6") if part == "approval" else Color("f6f7f5"))
		button.draw_rect(paper, color.lerp(Color.WHITE, .45), false, factor)
		if part == "prior":
			button.draw_polyline(PackedVector2Array([Vector2(width - 14 * factor, 3 * factor), Vector2(width - 14 * factor, 13 * factor), Vector2(width - 2 * factor, 13 * factor)]), color, factor)
		else:
			var tab := Rect2(Vector2(8, 26) * factor, Vector2(minf(38 * factor, width - 16 * factor), 5 * factor))
			button.draw_rect(tab, Color("fffefa")); button.draw_line(tab.position, Vector2(tab.end.x, tab.position.y), color, factor)
			button.draw_rect(Rect2(Vector2(8, 31) * factor, Vector2(maxf(0, width - 16 * factor), 24 * factor)), Color("fffefa"))
		_text(button, service, Vector2(9, 21) * factor, 12, color, width - 18 * factor)
		_text(button, folder, Vector2(11, 45) * factor, 15, color, width - 22 * factor)
		if not str(cell.get("device", "")).is_empty(): _text(button, str(cell.get("device", "")), Vector2(11, 60) * factor, 10, color, width - 22 * factor)
	else:
		button.draw_dashed_line(Vector2(5, 56) * factor, Vector2(width - 5 * factor, 56 * factor), LINE, factor, 4 * factor)
		_text(button, "?", Vector2(10, 37) * factor, 24, MUTED, 26 * factor)
		_text(button, str(cell.get("missing", "原記録未選択")), Vector2(41, 32) * factor, 12, MUTED, width - 45 * factor)
	var reference := str(cell.get("record_id", "")); var amount := int(cell.get("rows", -1))
	var footer := ("%d行 · " % amount if amount >= 0 else "") + (reference.trim_prefix("partner-baseline-") if part == "prior" else reference)
	_text(button, footer, Vector2(6, 74) * factor, 11, MUTED, width - 12 * factor)
