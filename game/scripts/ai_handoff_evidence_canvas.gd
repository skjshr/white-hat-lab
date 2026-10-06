extends Control
## A saved comparison, never a measurement or a policy editor.
const UI = preload("res://scripts/ui_theme.gd")
const PAPER = Color("f2efe5")
const INK = Color("263e4a")
const MUTED = Color("687a80")
const LINE = Color("c5cbc5")
const BLUE = Color("326b86")
const AMBER = Color("966325")
var model: Dictionary = {}
var factor := 1.0
var topic := "contacts"
var current_revision := 0
var open_record: Callable
var navigate_scope: Callable
var rows: Array[Dictionary] = []
var navigate: Button
var row_height := 98.0
var heading_height := 38.0

func configure(comparison: Dictionary, scale: float, open: Callable, navigate_to: Callable, selected_topic: String = "contacts", revision: int = 0) -> void:
	name = "AiHandoffEvidenceCanvas"; model = comparison.duplicate(true); factor = maxf(.5, scale)
	topic = selected_topic if selected_topic in ["contacts", "recipient", "business"] else "contacts"
	current_revision = revision; open_record = open; navigate_scope = navigate_to
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; mouse_filter = Control.MOUSE_FILTER_IGNORE
	var approvals: Dictionary = model.get("approvals", {})
	for key in ["previous", "current"]:
		var approval: Dictionary = approvals.get(key, {}); var known := str(approval.get("state", "missing")) == "present"
		var id := str(approval.get("record_id", "")) if known else ""
		var items := _approval_objects(approval, known)
		_add_row(key, "前回承認" if key == "previous" else "今回承認", str(approval.get("original_id", "")) if known else "? 未選択", items[0], items[1], [id] if not id.is_empty() else [], "approval" if known else "unknown", str(approval.get("detail", "")))
	var lane_key := str({"contacts":"read", "recipient":"write", "business":"business"}[topic])
	var lane: Dictionary = model.get("lanes", {}).get(lane_key, {}); var status := int(lane.get("status", 0))
	var measured_revision := int(lane.get("world_revision", -1)); var stale := status != 0 and measured_revision != current_revision
	var observed := _measured_objects(lane)
	_add_row(lane_key, "選択した実測", "? 未選択" if status == 0 else ("旧設定 " if stale else "設定 ") + "v%d" % measured_revision, observed[0], observed[1], lane.get("record_ids", []), "unknown" if status == 0 else "stale" if stale else "allowed" if status == 200 else "blocked", "保存済みの試験・業務記録です。原本を開いて根拠を確認できます。")
	navigate = Button.new(); navigate.name = "AiHandoffEvidenceNavigate"; navigate.text = "対象の設定へ ↗"; _button_style(navigate)
	navigate.tooltip_text = "現在の設定画面へ移動します。設定の変更や実測は行いません。"
	navigate.disabled = not navigate_scope.is_valid(); navigate.pressed.connect(func():
		if navigate_scope.is_valid(): navigate_scope.call())
	add_child(navigate); resized.connect(_layout); _layout.call_deferred()

func _object(kind: String, title: String, note: String, known: bool = true, count: int = -1) -> Dictionary:
	var object := {"kind":kind, "title":title, "note":note, "known":known}
	if count >= 0: object["count"] = count
	return object

func _approval_objects(approval: Dictionary, present: bool) -> Array:
	if not present: return [_object("paper", "? 原本未選択", "選択した根拠なし", false), _object("people" if topic == "contacts" else "folder", "? 未選択", "", false)]
	var sources: Array = approval.get("sources", []); var source_names: Array[String] = []
	for source in sources: source_names.append(str({"faq":"FAQ", "dispatch":"配送進捗", "contacts":"連絡先"}.get(str(source), str(source))))
	var source_known := bool(approval.get("sources_known", false))
	var source := _object("paper", "資料の対象", "・".join(source_names) if not source_names.is_empty() else "記載なし" if source_known else "? 未記載", source_known)
	if topic == "contacts":
		var scope_known := bool(approval.get("contacts_scope_known", false)); var scope := str(approval.get("contacts_scope", ""))
		var listed := source_known and "contacts" in sources
		var title := "連絡先 · 記載なし" if source_known and not listed else "連絡先 · ? 未記載"
		var note := "参照範囲の記載なし"
		if scope_known:
			title = str({"off":"連絡先 · 参照なし", "linked":"当該便の連絡先", "all":"全連絡先"}.get(scope, "連絡先範囲"))
			note = scope if scope not in ["off", "linked", "all", ""] else "範囲を原本に記載"
		var count := -1
		if bool(approval.get("contact_ids_known", false)):
			count = approval.get("contact_ids", []).size(); note = "対象 %d件" % count
		return [source, _object("people", title, note, scope_known or source_known, count)]
	if topic == "business":
		var shipments_known := bool(approval.get("shipment_ids_known", false))
		var count := int(approval.get("shipment_ids", []).size()) if shipments_known else -1
		source = _object("bags", "配送 %d便" % count if shipments_known else "配送資料", "便IDを原本に記載" if shipments_known else "便ID · ? 未記載", shipments_known or source_known, count)
	var recipient_known := bool(approval.get("recipient_known", false))
	var target := _recipient(str(approval.get("recipient", "")), recipient_known)
	var excluded := str(approval.get("excluded_recipient", ""))
	if topic == "recipient" and bool(approval.get("excluded_recipient_known", false)) and not excluded.is_empty():
		var excluded_label := "/" + excluded.get_slice("/", 1) if excluded.begins_with("minato/") else excluded
		target["note"] = str(target.note) + "\n対象外 " + excluded_label
		target["excluded_destination"] = excluded
	return [source, target]

func _recipient(destination: String, known: bool) -> Dictionary:
	if not known: return _object("folder", "送付先 · ? 未記載", "", false)
	if destination.is_empty(): return _object("folder", "送付先 · 記載なし", "", true)
	if destination in ["desk", "internal-desk"]: return _object("desk", "社内デスク", "承認された送付先")
	if destination.begins_with("minato/"): return _object("archive" if destination.ends_with("/archive") else "folder", "ミナト配送", "/" + destination.get_slice("/", 1))
	return _object("folder", "送付先", destination)

func _measured_objects(lane: Dictionary) -> Array:
	var status := int(lane.get("status", 0)); var data: Dictionary = lane.get("data", {})
	if status == 0: return [_object("paper", "? 実測未選択", "新しい実測は生成しません", false), _object("people" if topic == "contacts" else "folder", "? 結果なし", "", false)]
	var outcome := ("↑ " if status == 200 else "× ") + str(status)
	if topic == "contacts":
		var scope := str(data.get("contacts_scope", ""))
		var setting := str({"off":"参照なし", "linked":"当該便の連絡先", "all":"全連絡先"}.get(scope, "? 設定未記載"))
		var count := int(data.read_rows) if data.has("read_rows") else -1
		var selected_count := int(data.get("contact_ids", []).size()) if data.get("contact_ids") is Array else -1
		return [_object("people", setting, "記録に残る試験時の設定", not scope.is_empty(), selected_count), _object("people", "範囲外の参照試験", outcome + " · 読取%d行" % count if count >= 0 else outcome + " · 件数未記載", count >= 0, count)]
	var target := _recipient(str(data.get("recipient", "")), data.has("recipient"))
	target["note"] = str(target.note) + "  " + outcome
	if topic == "recipient": return [_object("paper", "送付先の試験", "ダミー要求 / 保存通信と別"), target]
	var count := int(data.jobs.size()) if data.get("jobs") is Array else int(data.summary_rows) if data.has("summary_rows") else -1
	return [_object("bags", "受付 %d便" % count if count >= 0 else "受付数 · ? 未記載", "この原記録の業務結果", count >= 0, count), target]

func _add_row(key: String, heading: String, caption: String, left: Dictionary, right: Dictionary, ids: Array, state: String, detail: String) -> void:
	var row := {"key":key, "heading":heading, "caption":caption, "state":state, "objects":[], "references":[]}
	var primary_id := str(ids.back()) if not ids.is_empty() else ""
	for index in 2:
		var data: Dictionary = left if index == 0 else right
		var object := EvidenceObject.new(); object.name = "AiHandoffEvidenceObject_" + key + "_" + str(index)
		object.configure(data, factor); object.tooltip_text = str(data.title) + " / " + str(data.note) + ("\n" + detail if not detail.is_empty() else "") + ("\n原記録 " + primary_id if not primary_id.is_empty() else "")
		object.disabled = primary_id.is_empty(); object.pressed.connect(_open.bind(primary_id)); add_child(object); row.objects.append(object)
	for index in ids.size():
		var id := str(ids[index]); var button := Button.new(); button.name = "AiHandoffEvidenceRecord_" + key + "_" + str(index)
		button.text = "原本 ↗" if key in ["previous", "current"] else "実測 ↗"
		button.tooltip_text = id; button.set_meta("record_id", id); _button_style(button)
		button.pressed.connect(_open.bind(id)); add_child(button); row.references.append(button)
	rows.append(row)

func _button_style(button: Button) -> void:
	button.add_theme_font_override("font", UI.font(500)); button.add_theme_font_size_override("font_size", roundi(12 * factor))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]: button.add_theme_color_override(key, INK)
	for key in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(key, UI.style(Color.TRANSPARENT if key in ["normal", "disabled"] else Color("e0e7e1"), Color.TRANSPARENT, 3, 3, 1))
	button.add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, BLUE, 0, 0, 2))

func _open(id: String) -> void:
	if not id.is_empty() and open_record.is_valid(): open_record.call(id)

func _layout() -> void:
	if size.x <= 0: return
	var width := size.x / factor
	var heading_width := 122.0 if width >= 760 else 108.0
	var object_width := minf(300, (width - heading_width - 54) / 2)
	row_height = 98 if width >= 580 else 114
	heading_height = 38 if width >= 620 else 58
	for index in rows.size():
		var row: Dictionary = rows[index]; var y := heading_height + index * row_height
		var left: EvidenceObject = row.objects[0]; var right: EvidenceObject = row.objects[1]
		left.position = Vector2(heading_width, y + 10) * factor; right.position = Vector2(width - object_width - 12, y + 10) * factor
		left.size = Vector2(object_width, row_height - 16) * factor; right.size = left.size
		for reference_index in row.references.size():
			var reference: Button = row.references[reference_index]
			reference.position = Vector2(12 + reference_index * 46, y + 57) * factor; reference.size = Vector2(70, 26) * factor
		draw_object_labels(left); draw_object_labels(right)
	navigate.position = Vector2(width - 151, 5) * factor; navigate.size = Vector2(141, 27) * factor
	custom_minimum_size.y = (heading_height + rows.size() * row_height + 18) * factor; queue_redraw()

func draw_object_labels(object: EvidenceObject) -> void:
	object.layout_labels(); object.queue_redraw()

func _text(value: String, point: Vector2, points: int, color: Color, width: float = -1) -> void:
	draw_string(UI.font(500), point * factor, value, HORIZONTAL_ALIGNMENT_LEFT, width * factor if width >= 0 else -1, roundi(points * factor), color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var width := size.x / factor; var old := int(model.get("world_revision", -1)) != current_revision
	_text("照合前" if model.is_empty() else "照合 %d分 / v%d%s" % [int(model.get("created_minute", 0)), int(model.get("world_revision", 0)), " · 旧設定" if old else ""], Vector2(12, 23), 12, MUTED, width - 175)
	for index in rows.size():
		var row: Dictionary = rows[index]; var y := heading_height + index * row_height
		draw_line(Vector2(10, y) * factor, Vector2(width - 10, y) * factor, LINE, factor)
		var ink := BLUE if str(row.key) == "current" else AMBER if str(row.state) in ["blocked", "stale"] else INK
		_text(str(row.heading), Vector2(12, y + 23), 13, ink, 105)
		_text(str(row.caption), Vector2(12, y + 44), 12, MUTED, 105)
		var left: Button = row.objects[0]; var right: Button = row.objects[1]
		var start := Vector2(left.position.x + left.size.x + 2 * factor, y * factor + row_height * factor / 2)
		var finish := Vector2(right.position.x - 3 * factor, start.y)
		var state := str(row.state); var middle := start.lerp(finish, .5)
		if state in ["unknown", "stale"]: draw_dashed_line(start, finish, MUTED, factor, 4 * factor)
		else: draw_line(start, finish, ink, factor)
		if state == "blocked":
			draw_line(middle + Vector2(-4, -5) * factor, middle + Vector2(4, 5) * factor, ink, 2 * factor)
			draw_line(middle + Vector2(-4, 5) * factor, middle + Vector2(4, -5) * factor, ink, 2 * factor)
		elif state == "unknown": _text("?", middle / factor + Vector2(-4, -6), 14, MUTED)
		else:
			draw_line(finish, finish + Vector2(-5, -4) * factor, ink, factor); draw_line(finish, finish + Vector2(-5, 4) * factor, ink, factor)
	_text("承認は範囲の記載 / ↑・×は選択した実測", Vector2(12, size.y / factor - 5), 11, MUTED, width - 20)

class EvidenceObject extends Button:
	var data: Dictionary = {}
	var factor := 1.0
	var title_label: Label
	var note_label: Label
	func configure(value: Dictionary, scale: float) -> void:
		data = value; factor = scale
		for key in ["normal", "hover", "pressed", "disabled"]: add_theme_stylebox_override(key, UI.style(Color.TRANSPARENT if key in ["normal", "disabled"] else Color("e0e7e1"), Color.TRANSPARENT, 0, 0, 1))
		add_theme_stylebox_override("focus", UI.style(Color.TRANSPARENT, BLUE, 0, 0, 2))
		title_label = _label(str(data.get("title", "")), 14, INK)
		note_label = _label(str(data.get("note", "")), 12, MUTED)
	func _label(value: String, points: int, color: Color) -> Label:
		var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", UI.font(500)); label.add_theme_font_size_override("font_size", roundi(points * factor)); label.add_theme_color_override("font_color", color); add_child(label); return label
	func layout_labels() -> void:
		var width := size.x / factor; var icon_width := 49.0 if width >= 210 else 37.0
		title_label.position = Vector2(icon_width, 5) * factor; title_label.size = Vector2(maxf(30, width - icon_width - 5), 36) * factor
		note_label.position = Vector2(icon_width, 43) * factor; note_label.size = Vector2(maxf(30, width - icon_width - 5), size.y / factor - 44) * factor
	func _draw() -> void:
		var width := size.x / factor; var small := width < 210; var x := 5.0; var y := 23.0; var span := 28.0 if small else 38.0
		var known := bool(data.get("known", true)); var color := BLUE if known else MUTED; var kind := str(data.get("kind", "paper"))
		if kind in ["people", "bags"]:
			var count := int(data.get("count", -1))
			if count <= 0:
				draw_rect(Rect2(Vector2(x, y - 8) * factor, Vector2(span, 35) * factor), LINE, false, factor)
				draw_string(UI.font(500), Vector2(x + span / 2 - 5, y + 15) * factor, "0" if count == 0 else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(18 * factor), MUTED)
			else:
				for index in mini(count, 6):
					var px := x + (index % 3) * (8 if small else 11); var py := y - 6 + int(index / 3) * 28
					if kind == "people":
						draw_circle(Vector2(px + 4, py) * factor, 3.5 * factor, color)
						draw_rect(Rect2(Vector2(px + 1, py + 6) * factor, Vector2(6, 12) * factor), color)
					else:
						draw_rect(Rect2(Vector2(px, py - 4) * factor, Vector2(13, 24) * factor), Color("d5c59e")); draw_rect(Rect2(Vector2(px, py - 4) * factor, Vector2(13, 24) * factor), color, false, factor)
						draw_line(Vector2(px, py - 4) * factor, Vector2(px + 13, py + 5) * factor, color, factor)
				if count > 6: draw_string(UI.font(500), Vector2(x, y + 55) * factor, "+%d" % (count - 6), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11 * factor), color)
		elif kind in ["folder", "archive"]:
			if kind == "archive":
				for index in 3: draw_rect(Rect2(Vector2(x + index * 2, y - 6 + index * 4) * factor, Vector2(span - 4, 23) * factor), PAPER if index < 2 else Color("d6e1df")); draw_rect(Rect2(Vector2(x + index * 2, y - 6 + index * 4) * factor, Vector2(span - 4, 23) * factor), color, false, factor)
			else:
				draw_rect(Rect2(Vector2(x, y - 8) * factor, Vector2(span * .5, 8) * factor), color)
				draw_rect(Rect2(Vector2(x, y - 2) * factor, Vector2(span, 26) * factor), Color("d6e1df")); draw_rect(Rect2(Vector2(x, y - 2) * factor, Vector2(span, 26) * factor), color, false, factor)
			if data.has("excluded_destination"):
				var origin := Vector2(x + 6, y + 29) * factor; var box := Vector2(span - 6, 19) * factor
				draw_rect(Rect2(origin + Vector2(0, -4) * factor, Vector2(12, 5) * factor), MUTED)
				draw_rect(Rect2(origin, box), PAPER); draw_rect(Rect2(origin, box), MUTED, false, factor)
				draw_line(origin + Vector2(3, 3) * factor, origin + box - Vector2(3, 3) * factor, AMBER, 2 * factor)
				draw_line(origin + Vector2(3 * factor, box.y - 3 * factor), origin + Vector2(box.x - 3 * factor, 3 * factor), AMBER, 2 * factor)
		elif kind == "desk":
			draw_rect(Rect2(Vector2(x, y - 9) * factor, Vector2(span, 25) * factor), color, false, 2 * factor)
			draw_line(Vector2(x + span / 2, y + 16) * factor, Vector2(x + span / 2, y + 23) * factor, color, 2 * factor)
			draw_line(Vector2(x - 2, y + 25) * factor, Vector2(x + span + 2, y + 25) * factor, color, 2 * factor)
		else:
			for index in 2:
				var position := Vector2(x + index * 6, y - 11 + index * 3) * factor
				draw_rect(Rect2(position, Vector2(span - 6, 35) * factor), PAPER); draw_rect(Rect2(position, Vector2(span - 6, 35) * factor), color, false, factor)
				for line in 3: draw_line(position + Vector2(5, 11 + line * 6) * factor, position + Vector2(span - 12, 11 + line * 6) * factor, color, factor)
