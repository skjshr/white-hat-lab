extends Control
## A read-only customer maintenance workbench: retained targets, people and
## today's inspection receipt. This drawing never runs or changes a service.

const UI = preload("res://scripts/ui_theme.gd")
const STAFF_ATLAS: Texture2D = preload("res://assets/ui/staff/staff-portraits-v1.png")

const NAVY := Color("17283a")
const NAVY_EDGE := Color("385166")
const NAVY_INK := Color("f0f3f2")
const NAVY_MUTED := Color("b5c5cc")
const TEAL := Color("70c5b3")
const AMBER := Color("e2b75e")
const RED := Color("e6756d")
const BLUE := Color("87b5d0")
const CREAM := Color("f2e7cc")
const PAPER_INK := Color("273848")
const PAPER_LINE := Color("c4b89e")

var data: Dictionary = {}
var scale_factor := 1.0


func configure(client: Dictionary, scale: float) -> void:
	data = client.duplicate(true)
	scale_factor = maxf(0.8, scale)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 210.0 * scale_factor)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_factor, scale_factor))
	var width := size.x / scale_factor
	draw_rect(Rect2(0, 0, width, 210), NAVY)
	draw_rect(Rect2(0.5, 0.5, width - 1.0, 209.0), NAVY_EDGE, false, 1.0)

	var client_name := str(data.get("client", "顧客名不明"))
	_text(Vector2(16, 22), "顧客保守 · " + client_name, 16, NAVY_INK, width * 0.61)
	var agreement_status := str(data.get("status", "unknown"))
	_text(Vector2(width * 0.67, 22), "契約 " + _agreement_label(agreement_status), 12, _agreement_color(agreement_status), width * 0.30)

	var left := 16.0
	var rack_right := width * 0.31
	var person_left := width * 0.37
	var person_right := width * 0.63
	var paper_left := width * 0.69
	var paper_right := width - 16.0
	var rack_mid := (left + rack_right) * 0.5
	var person_mid := (person_left + person_right) * 0.5

	_text(Vector2(left, 43), "保守対象", 12, NAVY_MUTED, rack_right - left)
	_text(Vector2(person_left, 43), "保守担当", 12, NAVY_MUTED, person_right - person_left)
	_text(Vector2(paper_left, 43), "今日の点検控え", 12, NAVY_INK, paper_right - paper_left - 8.0)

	var status := str(data.get("job_status", "unknown"))
	var state: Dictionary = _state_spec(status)
	_draw_route(rack_right - 8.0, person_mid - 42.0, person_mid + 42.0, paper_left + 2.0, state, data)
	_draw_rack(left, rack_right, rack_mid)
	_draw_person(person_left, person_right, person_mid)
	_draw_receipt(paper_left, paper_right, state)

	_draw_scope_names(left, rack_right)
	_draw_people_labels(person_left, person_right)
	_draw_receipt_footer(paper_left, paper_right, status)


func _draw_rack(left: float, right: float, center: float) -> void:
	var x := left + 8.0
	var y := 53.0
	var w := right - left - 16.0
	var h := 96.0
	# Open rails and shelves form a storage rack rather than a data card.
	draw_rect(Rect2(x, y, w, h), Color("21384c"))
	draw_rect(Rect2(x, y, w, h), NAVY_EDGE, false, 1.4)
	draw_rect(Rect2(x + 6.0, y + 5.0, 4.0, h - 10.0), BLUE)
	draw_rect(Rect2(x + w - 10.0, y + 5.0, 4.0, h - 10.0), BLUE)
	for shelf in [y + 35.0, y + 66.0]:
		draw_line(Vector2(x + 8.0, shelf), Vector2(x + w - 8.0, shelf), NAVY_EDGE, 2.0)
	var scope_known := bool(data.get("scope_known", false))
	var scope: Array = data.get("scope", []) if data.get("scope", []) is Array else []
	var count_text := str(scope.size()) + "件" if scope_known else "?件"
	_text(Vector2(x + 15.0, y + 19.0), count_text, 13, NAVY_INK, w - 30.0)
	if not scope_known:
		_text(Vector2(x + 15.0, y + 57.0), "範囲不明", 12, AMBER, w - 30.0)
	elif scope.is_empty():
		_text(Vector2(x + 15.0, y + 57.0), "対象なし", 12, NAVY_MUTED, w - 30.0)


func _draw_scope_names(left: float, right: float) -> void:
	var scope_known := bool(data.get("scope_known", false))
	if not scope_known:
		_text(Vector2(left, 171), "保存範囲を確認", 11, AMBER, right - left)
		return
	var scope: Array = data.get("scope", []) if data.get("scope", []) is Array else []
	if scope.is_empty():
		_text(Vector2(left, 171), "対象 0件", 11, NAVY_MUTED, right - left)
		return
	var show_count := mini(2, scope.size())
	for index in show_count:
		var target: Variant = scope[index]
		if not target is Dictionary:
			continue
		var chapter := int(target.get("chapter", -1))
		var y := 169.0 + float(index) * 20.0
		var badge := "?" if chapter < 0 else "C%d" % (chapter + 1)
		draw_circle(Vector2(left + 12.0, y - 4.0), 9.0, Color("29465c"))
		draw_circle(Vector2(left + 12.0, y - 4.0), 9.0, NAVY_MUTED, false, 1.0)
		_text(Vector2(left + 4.0, y), badge, 8, NAVY_INK, 17.0)
		var name := str(target.get("name", "対象名不明"))
		_text(Vector2(left + 27.0, y), name, 11, NAVY_INK, right - left - 29.0)
	if scope.size() > show_count:
		_text(Vector2(right - 51.0, 205), "+%d件" % (scope.size() - show_count), 10, NAVY_MUTED, 50.0)


func _draw_person(left: float, right: float, center: float) -> void:
	var owner_id := str(data.get("owner", ""))
	var assigned_id := str(data.get("assignee", ""))
	var portrait_id := owner_id
	if portrait_id.is_empty() or portrait_id in ["player", "verified"]:
		portrait_id = assigned_id
	var avatar := Rect2(center - 39.0, 54.0, 78.0, 78.0)
	var atlas_index := ["mio", "haru", "sora"].find(portrait_id)
	if atlas_index >= 0:
		var atlas_size := STAFF_ATLAS.get_size()
		var cell_width := atlas_size.x / 3.0
		draw_texture_rect_region(STAFF_ATLAS, avatar, Rect2(cell_width * atlas_index, 0.0, cell_width, atlas_size.y))
	else:
		_draw_generic_person(center, avatar, portrait_id)


func _draw_generic_person(center: float, avatar: Rect2, member_id: String) -> void:
	var main := Color("91b6b0") if member_id == "aya" else Color("aab7bd")
	var face_center := Vector2(center, avatar.position.y + 27.0)
	draw_circle(face_center + Vector2(1, 2), 17.0, Color("101e2d"))
	draw_circle(face_center, 17.0, Color("d9c5a7"))
	draw_arc(face_center, 17.0, PI, TAU, 24, main, 4.0, true)
	var shoulders := PackedVector2Array([
		Vector2(center - 36.0, avatar.position.y + avatar.size.y),
		Vector2(center - 29.0, avatar.position.y + 57.0),
		Vector2(center, avatar.position.y + 49.0),
		Vector2(center + 29.0, avatar.position.y + 57.0),
		Vector2(center + 36.0, avatar.position.y + avatar.size.y)
	])
	draw_colored_polygon(shoulders, main)
	draw_polyline(PackedVector2Array([shoulders[0], shoulders[1], shoulders[2], shoulders[3], shoulders[4]]), NAVY_EDGE, 1.0, true)
	if member_id.is_empty():
		_text(Vector2(center - 6.0, avatar.position.y + 34.0), "?", 17, PAPER_INK, 15.0)
	else:
		draw_circle(Vector2(center - 6.0, face_center.y), 1.5, PAPER_INK)
		draw_circle(Vector2(center + 6.0, face_center.y), 1.5, PAPER_INK)


func _draw_people_labels(left: float, right: float) -> void:
	var owner_id := str(data.get("owner", ""))
	var actual_id := str(data.get("assignee", ""))
	if actual_id in ["verified", ""]:
		actual_id = ""
	var owner_name := str(data.get("owner_name", ""))
	var actual_name := str(data.get("assignee_name", ""))
	if owner_name.is_empty():
		owner_name = _person_name(owner_id)
	if actual_name.is_empty():
		actual_name = _person_name(actual_id)
	if actual_id.is_empty() and str(data.get("job_status", "")) == "done":
		actual_name = "確認済み"
	var span := right - left
	if not owner_id.is_empty() and owner_id == actual_id:
		_text(Vector2(left, 154), "定期担当 / 今日", 10, NAVY_MUTED, span)
		_text(Vector2(left, 174), owner_name, 12, NAVY_INK, span)
	else:
		_text(Vector2(left, 154), "定期担当", 10, NAVY_MUTED, span * 0.48)
		_text(Vector2(left, 174), owner_name if not owner_name.is_empty() else "未設定", 12, NAVY_INK, span * 0.48)
		_text(Vector2(left + span * 0.52, 154), "今日の実担当", 10, NAVY_MUTED, span * 0.48)
		_text(Vector2(left + span * 0.52, 174), actual_name if not actual_name.is_empty() else "未割当", 12, NAVY_INK, span * 0.48)


func _draw_receipt(left: float, right: float, state: Dictionary) -> void:
	var width := right - left - 8.0
	var x := left + 2.0
	var y := 53.0
	var height := 112.0
	draw_rect(Rect2(x + 2.0, y + 2.0, width, height), Color("0e1c29"))
	draw_rect(Rect2(x, y, width, height), CREAM)
	draw_rect(Rect2(x, y, width, height), PAPER_LINE, false, 1.0)
	var fold := PackedVector2Array([Vector2(x + width - 18.0, y), Vector2(x + width, y + 18.0), Vector2(x + width - 18.0, y + 18.0)])
	draw_colored_polygon(fold, Color("dfd0ad"))
	draw_line(fold[0], fold[1], PAPER_LINE, 1.0)
	draw_line(fold[1], fold[2], PAPER_LINE, 1.0)

	var status := str(data.get("job_status", "unknown"))
	var mark_center := Vector2(x + 20.0, y + 34.0)
	_draw_status_mark(mark_center, status, Color(state.color))
	_text(Vector2(x + 38.0, y + 39.0), str(state.label), 13, PAPER_INK, width - 47.0)

	if status in ["working", "paused", "queued"]:
		var total := float(data.get("total", -1.0))
		var remaining := float(data.get("remaining", -1.0))
		if total > 0.0 and remaining >= 0.0:
			var completed := clampf(total - remaining, 0.0, total)
			var ratio := completed / total
			var bar := Rect2(x + 12.0, y + 54.0, width - 24.0, 7.0)
			draw_rect(bar, Color("d6c9ad"))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(state.color))
			_text(Vector2(x + 12.0, y + 78.0), "作業量 %.0f / %.0f 分" % [completed, total], 10, PAPER_INK, width - 22.0)
		elif status == "working":
			_text(Vector2(x + 12.0, y + 77.0), "進み具合不明", 10, PAPER_INK, width - 22.0)
	else:
		var detail := "結果: 実記録" if status == "done" else "結果: 保存控え" if status == "legacy" else ""
		if not detail.is_empty():
			_text(Vector2(x + 12.0, y + 73.0), detail, 10, PAPER_INK, width - 22.0)
	draw_line(Vector2(x + 12.0, y + 88.0), Vector2(x + width - 12.0, y + 88.0), PAPER_LINE, 1.0)
	_text(Vector2(x + 12.0, y + 104.0), "完了時の見込", 10, PAPER_INK, width * 0.46)
	var fee_value := int(data.get("fee", -1))
	var fee_known := bool(data.get("fee_known", data.has("fee") and fee_value >= 0)) and fee_value >= 0
	var fee_text := "¥%d" % fee_value if fee_known else "?"
	_text(Vector2(x + width * 0.51, y + 104.0), fee_text, 13, PAPER_INK, width * 0.42)


func _draw_receipt_footer(left: float, right: float, job_status: String) -> void:
	var x := left + 5.0
	var width := right - left - 10.0
	_text(Vector2(x, 184), "今日の実収入", 11, NAVY_MUTED, width * 0.49)
	var earned_text := "?"
	if data.has("earned_today"):
		if bool(data.get("earned_today_known", true)) and int(data.get("earned_today", -1)) >= 0:
			earned_text = "¥%d" % int(data.get("earned_today", 0))
	elif job_status == "done" and bool(data.get("fee_known", int(data.get("fee", -1)) >= 0)) and int(data.get("fee", -1)) >= 0:
		earned_text = "¥%d" % int(data.get("fee", 0))
	elif job_status not in ["legacy", "unknown"]:
		earned_text = "¥0"
	var earned_color := TEAL if earned_text != "?" and job_status == "done" else NAVY_INK
	_text(Vector2(x, 204), earned_text, 15, earned_color, width * 0.49)
	var cost_known := data.has("cost") and int(data.get("cost", -1)) >= 0
	var cost_text := "費用 ¥%d" % int(data.get("cost", 0)) if cost_known else "費用 ?"
	if job_status == "legacy":
		cost_text += " · 旧契約"
	_text(Vector2(x + width * 0.52, 201), cost_text, 10, NAVY_MUTED, width * 0.48)


func _draw_route(rack_right: float, person_left: float, person_right: float, paper_left: float, state: Dictionary, source: Dictionary) -> void:
	var y := 104.0
	var status := str(source.get("job_status", "unknown"))
	var tint: Color = state.color
	var segments := [[rack_right, person_left], [person_right, paper_left]]
	for segment in segments:
		var start := float(segment[0])
		var finish := float(segment[1])
		if finish <= start:
			continue
		if status in ["pending", "queued", "paused", "legacy", "unknown"]:
			draw_dashed_line(Vector2(start, y), Vector2(finish, y), tint, 1.5, 5.0)
		elif status == "failed":
			var midpoint := (start + finish) * 0.5
			draw_line(Vector2(start, y), Vector2(midpoint - 5.0, y), tint, 1.8)
			draw_line(Vector2(midpoint + 5.0, y), Vector2(finish, y), tint, 1.8)
		else:
			draw_line(Vector2(start, y), Vector2(finish, y), tint, 2.0)
	if status == "working":
		var total := float(source.get("total", -1.0))
		var remaining := float(source.get("remaining", -1.0))
		if total > 0.0 and remaining >= 0.0:
			var ratio := clampf((total - remaining) / total, 0.0, 1.0)
			var start := rack_right
			var finish := person_left
			draw_circle(Vector2(lerpf(start, finish, ratio), y), 4.0, tint)
	else:
		_draw_status_mark(Vector2((person_right + paper_left) * 0.5, y), status, tint)


func _draw_status_mark(center: Vector2, status: String, color: Color) -> void:
	match status:
		"pending":
			draw_circle(center, 7.0, color, false, 1.8)
		"working":
			draw_colored_polygon(PackedVector2Array([center + Vector2(-5, -6), center + Vector2(6, 0), center + Vector2(-5, 6)]), color)
		"done":
			draw_circle(center, 8.0, color)
			draw_polyline(PackedVector2Array([center + Vector2(-4, 0), center + Vector2(-1, 3), center + Vector2(5, -4)]), PAPER_INK, 2.0, true)
		"failed":
			draw_line(center + Vector2(-6, -6), center + Vector2(6, 6), color, 2.5)
			draw_line(center + Vector2(-6, 6), center + Vector2(6, -6), color, 2.5)
		"queued":
			draw_rect(Rect2(center - Vector2(6, 6), Vector2(12, 12)), color, false, 2.0)
		"paused":
			draw_rect(Rect2(center + Vector2(-5, -7), Vector2(3, 14)), color)
			draw_rect(Rect2(center + Vector2(2, -7), Vector2(3, 14)), color)
		"legacy":
			draw_rect(Rect2(center + Vector2(-6, -7), Vector2(12, 14)), color, false, 1.8)
			draw_line(center + Vector2(-3, -3), center + Vector2(3, -3), color, 1.4)
			draw_line(center + Vector2(-3, 1), center + Vector2(3, 1), color, 1.4)
		_:
			draw_circle(center, 7.0, color, false, 1.8)
			_text(center + Vector2(-3.5, 4.5), "?", 11, color, 8.0)


func _state_spec(status: String) -> Dictionary:
	match status:
		"pending": return {"label":"未着手", "color":AMBER}
		"working": return {"label":"点検中", "color":BLUE}
		"done": return {"label":"正常 · 点検完了", "color":TEAL}
		"failed": return {"label":"不合格 · 要対応", "color":RED}
		"queued": return {"label":"待機中", "color":AMBER}
		"paused": return {"label":"停止中", "color":AMBER}
		"legacy": return {"label":"旧契約 · 範囲不明", "color":NAVY_MUTED}
		_: return {"label":"記録不明", "color":AMBER}


func _agreement_label(status: String) -> String:
	match status:
		"active": return "稼働"
		"pending": return "納品待ち"
		"suspended": return "停止"
		_: return "不明"


func _agreement_color(status: String) -> Color:
	match status:
		"active": return TEAL
		"pending": return AMBER
		"suspended": return RED
		_: return NAVY_MUTED


func _person_name(member_id: String) -> String:
	if member_id.is_empty(): return ""
	if member_id == "player": return "本人"
	if member_id == "verified": return "確認済み"
	if member_id in ["mio", "haru", "sora"]:
		return UI.copy("staff_name_" + member_id, member_id)
	match member_id:
		"aya": return "綾"
		"ren": return "蓮"
		_: return "担当不明"


func _text(at: Vector2, value: String, font_size: int, color: Color, max_width: float = -1.0) -> void:
	var font: Font = UI.font(500)
	var shown := value
	if max_width > 0.0:
		while shown.length() > 1 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			shown = shown.left(shown.length() - 2) + "…"
	draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
