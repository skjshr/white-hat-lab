extends Control
## Backup work diagram. It only renders the supplied projection or saved receipt.
signal route_requested(route: String)

const UI = preload("res://scripts/ui_theme.gd")
const M = preload("res://scripts/management_ui.gd")

var backup_work: Dictionary = {}
var factor: float = 1.0
var mode: String = "plan"
var route_buttons: Array[Button] = []

func configure(value: Dictionary, scale: float, view_mode: String = "plan") -> void:
	backup_work = value.duplicate(true) if value is Dictionary else {}
	factor = maxf(.5, scale)
	mode = view_mode
	name = "StaffBackupCanvas"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = 0
	custom_minimum_size.y = 166.0 * factor
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = M.theme(factor)
	theme.set_color("font_color", "TooltipLabel", M.INK)
	theme.set_stylebox("panel", "TooltipPanel", M.surface(M.PAPER, 8))
	for child in get_children():
		remove_child(child)
		child.queue_free()
	route_buttons.clear()
	_add_route_button("BackupSourceRoute", "backup-plan", "保存計画 / 保存元の作業図")
	_add_route_button("BackupLocalRoute", "backup-local", "local / 同じ拠点を開く")
	_add_route_button("BackupOffsiteRoute", "backup-offsite", "offsite / 別拠点を開く")
	_add_route_button("BackupRestoreRoute", "backup-restore", "復元先を開く")
	_sync_tooltips()
	if not resized.is_connected(_layout): resized.connect(_layout)
	_layout.call_deferred()
	queue_redraw()

func _add_route_button(id: String, route: String, tooltip: String) -> void:
	var button := Button.new()
	button.name = id
	button.text = ""
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", UI.font(500))
	button.add_theme_font_size_override("font_size", roundi(11 * factor))
	M.button(button, "quiet")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := M.surface(Color.TRANSPARENT, 0)
		style.set_corner_radius_all(3)
		if state == "hover":
			style.border_color = M.ACCENT
			style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func(): route_requested.emit(route))
	add_child(button)
	route_buttons.append(button)

func _layout() -> void:
	if size.x <= 0: return
	var width := size.x / factor
	custom_minimum_size.y = 166.0 * factor
	var rects := _node_rects(width)
	for i in mini(rects.size(), route_buttons.size()):
		var rect: Rect2 = rects[i]
		route_buttons[i].position = rect.position * factor
		route_buttons[i].size = rect.size * factor
	queue_redraw()

func _node_rects(width: float) -> Array[Rect2]:
	return [
		Rect2(8, 59, width * .22, 57),
		Rect2(width * .315, 34, width * .35, 44),
		Rect2(width * .315, 87, width * .35, 44),
		Rect2(width * .77, 59, width * .22 - 8, 57)
	]

func _draw() -> void:
	if size.x <= 0: return
	draw_set_transform(Vector2.ZERO, 0, Vector2(factor, factor))
	var width := size.x / factor
	draw_rect(Rect2(0, 0, width, 166), Color("FBF7EA"))
	draw_rect(Rect2(0, 0, width, 166), Color("D6C7A5"), false, 1)
	if mode == "receipt":
		_draw_receipt(width)
	else:
		_draw_plan(width)

func _draw_plan(width: float) -> void:
	var current_known := bool(backup_work.get("available", false)) and bool(backup_work.get("known", false))
	var current_schedule := _schedule_display(_known_text(backup_work.get("schedule", ""), current_known))
	var current_repository := _known_text(backup_work.get("repository", ""), current_known)
	var desired_schedule := _schedule_display(_known_text(backup_work.get("desired_schedule", ""), _present(backup_work.get("desired_schedule", ""))))
	var desired_repository := _known_text(backup_work.get("desired_repository", ""), _present(backup_work.get("desired_repository", "")))
	var dirty := bool(backup_work.get("dirty", false))
	_text(Vector2(9, 17), "現在の計画", 11, M.MUTED)
	_text(Vector2(9, 33), current_schedule + " · " + current_repository + (" · 未適用" if dirty else " · 適用済" if current_known else ""), 12, M.INK if current_known else M.MUTED)
	var right_x := width * .52
	_text(Vector2(right_x, 17), "顧客指定", 11, M.MUTED)
	_text(Vector2(right_x, 33), desired_schedule + " · " + desired_repository, 12, M.ACCENT if _present(backup_work.get("desired_repository", "")) else M.MUTED)
	_draw_plan_routes(width, current_repository, desired_repository, current_known)
	_draw_storage(width, backup_work.get("snapshots", []), current_repository, desired_repository, current_known)
	_draw_source(width, current_schedule, current_known, false)
	_draw_restore(width, backup_work.get("restore", {}), false)

func _draw_plan_routes(width: float, current_repository: String, desired_repository: String, current_known: bool) -> void:
	var source := Vector2(width * .125, 87.5)
	var fork_x := width * .275
	var left := width * .315
	var right := width * .665
	var restore := Vector2(width * .88, 87.5)
	var local_y := 56.0
	var offsite_y := 109.0
	var current_y := local_y if current_repository == "local" else offsite_y if current_repository == "offsite" else -1.0
	var desired_y := local_y if desired_repository == "local" else offsite_y if desired_repository == "offsite" else -1.0
	draw_line(source + Vector2(38, 0), Vector2(fork_x, source.y), M.LINE, 2)
	draw_line(Vector2(fork_x, local_y), Vector2(fork_x, offsite_y), M.LINE, 2)
	for y in [local_y, offsite_y]:
		var is_current: bool = current_known and y == current_y
		var is_desired: bool = y == desired_y
		var color: Color = M.ACCENT if is_current else Color("798B61") if is_desired else M.LINE
		var stroke := 2.5 if is_current or is_desired else 1.0
		draw_line(Vector2(fork_x, y), Vector2(left, y), color, stroke)
		draw_line(Vector2(right, y), Vector2(restore.x - 37, restore.y), M.LINE, 1.5)
		_arrow(Vector2(left, y), color)
	_arrow(Vector2(restore.x - 37, restore.y), M.LINE)
	if current_y >= 0 and current_known: _mark(Vector2(fork_x, current_y), "現", M.ACCENT)
	if desired_y >= 0: _mark(Vector2(fork_x + 12, desired_y), "指", Color("798B61"))
	if not current_known: _text(Vector2(fork_x - 5, source.y - 22), "?", 13, M.WARNING)

func _draw_storage(width: float, snapshots_value: Variant, current_repository: String, desired_repository: String, current_known: bool) -> void:
	var snapshots: Array = snapshots_value if snapshots_value is Array else []
	var snapshot_known := bool(backup_work.get("snapshot_known", backup_work.get("snapshots_known", current_known)))
	var local_count := _snapshot_count(snapshots, "local") if snapshot_known else -1
	var offsite_count := _snapshot_count(snapshots, "offsite") if snapshot_known else -1
	_draw_drive(Vector2(width * .35, 56), "local / 同じ拠点", local_count, current_known and current_repository == "local", desired_repository == "local")
	_draw_building(Vector2(width * .35, 109), "offsite / 別拠点", offsite_count, current_known and current_repository == "offsite", desired_repository == "offsite")

func _draw_source(width: float, detail: String, known: bool, execution_record: bool, source_path: String = "/srv/data") -> void:
	var center := Vector2(width * .125, 87.5)
	var ink: Color = M.INK if known or execution_record else M.MUTED
	# Small server rack with a source line, not a generic text tile.
	for row in 2:
		var r := Rect2(center + Vector2(-16, -17 + row * 18), Vector2(32, 15))
		draw_rect(r, Color("FFFDF6"))
		draw_rect(r, ink, false, 1.5)
		draw_circle(r.position + Vector2(5, 7.5), 2, ink)
		draw_line(r.position + Vector2(11, 7.5), r.end - Vector2(4, 7.5), ink, 1)
	_text(Vector2(8, 130), "保存元 " + (source_path if not execution_record or known else "?"), 11, M.INK if known else M.MUTED)
	_text(Vector2(8, 146), ("実行 " if execution_record else "計画 ") + detail, 11, ink)

func _draw_restore(width: float, restore_value: Variant, execution_record: bool) -> void:
	var center := Vector2(width * .88, 87.5)
	var value: Dictionary = restore_value if restore_value is Dictionary else {}
	var target := str(value.get("target", ""))
	if target.is_empty(): target = "?" if execution_record else "/restore"
	var count := _integer_or_unknown(value.get("file_count", -1))
	# Open file tray and two visible paper edges.
	draw_rect(Rect2(center + Vector2(-20, -15), Vector2(40, 30)), Color("FFFDF6"))
	draw_rect(Rect2(center + Vector2(-20, -15), Vector2(40, 30)), M.INK, false, 1.5)
	for i in 2:
		draw_rect(Rect2(center + Vector2(-10 + i * 8, -21), Vector2(13, 22)), Color("FFFDF6"), false, 1)
	draw_line(center + Vector2(-24, 16), center + Vector2(24, 16), M.INK, 2)
	if execution_record:
		_text(Vector2(width * .77, 130), target, 11, M.INK)
		_text(Vector2(width * .77, 146), "復元 " + _count_text(count) + "件", 11, M.ACCENT if count >= 0 else M.WARNING)
	else:
		_text(Vector2(width * .77, 130), "復元先 " + target, 11, M.INK)
		var is_current_files: bool = bool(value.get("current_files", false))
		var label := "現在 " + _count_text(count) + "ファイル" if is_current_files else "記録 " + _count_text(count) + "件" if not value.is_empty() else "今回の復元 ?"
		_text(Vector2(width * .77, 146), label, 11, M.MUTED if is_current_files or not value.is_empty() else M.WARNING)

func _draw_receipt(width: float) -> void:
	var raw: Variant = backup_work.get("execution", {})
	var execution: Dictionary = raw if raw is Dictionary else {}
	if execution.is_empty():
		_text(Vector2(9, 19), "担当作業の内訳未記録", 12, M.WARNING)
		_text(Vector2(9, 36), "旧い担当記録 · 詳細は原文へ", 11, M.MUTED)
		_draw_receipt_routes(width, "", "unknown")
		_draw_source(width, "?", false, true, "?")
		_draw_receipt_storage(width, "", "", "unknown")
		_draw_restore(width, {}, true)
		return
	var status := str(execution.get("status", "unknown"))
	var repository := str(execution.get("repository", ""))
	var schedule := str(execution.get("schedule", ""))
	var source := str(execution.get("source", ""))
	var snapshot := str(execution.get("snapshot", ""))
	var target := str(execution.get("target", ""))
	var files_value: Variant = execution.get("files", [])
	var files: Array = files_value if files_value is Array else []
	var restored_count := _restored_file_count(files)
	var result_text := _execution_status(status)
	_text(Vector2(9, 18), "担当者の保存・復元実行", 11, M.MUTED)
	_text(Vector2(9, 34), result_text + (" · " + str(execution.get("error", "")) if status == "failed" and not str(execution.get("error", "")).is_empty() else ""), 12, M.INK if status == "restored" else M.WARNING if status == "selection_required" else M.DANGER if status == "failed" else M.MUTED)
	_draw_receipt_routes(width, repository, status)
	var source_detail := _schedule_display(_known_text(schedule, _present(schedule))) + (" · 保存命令 ✓" if bool(execution.get("backup_created", false)) else " · 新規保存なし")
	_draw_source(width, source_detail, _present(source), true, _known_text(source, _present(source)))
	_draw_receipt_storage(width, repository, snapshot, status)
	var restore_value := {"target":target, "file_count":restored_count if status == "restored" else -1}
	_draw_restore(width, restore_value, true)

func _draw_receipt_routes(width: float, repository: String, status: String) -> void:
	var source := Vector2(width * .125, 87.5)
	var left := width * .315
	var right := width * .665
	var destination := Vector2(width * .88, 87.5)
	var local_y := 56.0
	var offsite_y := 109.0
	var recorded_y := local_y if repository == "local" else offsite_y if repository == "offsite" else -1.0
	var completed := status == "restored"
	var error := status == "failed"
	var line_color: Color = M.ACCENT if completed else M.DANGER if error else M.WARNING if status == "selection_required" else M.MUTED
	var fork_x := width * .275
	draw_line(source + Vector2(38, 0), Vector2(fork_x, source.y), line_color if recorded_y >= 0 else M.LINE, 2)
	draw_line(Vector2(fork_x, local_y), Vector2(fork_x, offsite_y), M.LINE, 1.5)
	for y in [local_y, offsite_y]:
		var active: bool = y == recorded_y
		var color: Color = line_color if active else M.LINE
		draw_line(Vector2(fork_x, y), Vector2(left, y), color, 2 if active else 1)
		draw_line(Vector2(right, y), Vector2(destination.x - 37, destination.y), M.ACCENT if active and completed else M.LINE, 2 if active and completed else 1)
		_arrow(Vector2(left, y), color)
	if recorded_y >= 0: _mark(Vector2(fork_x, recorded_y), "記", line_color)
	if completed: _arrow(Vector2(destination.x - 37, destination.y), M.ACCENT)
	elif status == "selection_required": _mark(destination + Vector2(-34, -24), "?", M.WARNING)
	elif error: _mark(destination + Vector2(-34, -24), "×", M.DANGER)

func _draw_receipt_storage(width: float, repository: String, snapshot: String, status: String) -> void:
	var execution_value: Variant = backup_work.get("execution", {})
	var execution: Dictionary = execution_value if execution_value is Dictionary else {}
	var saved := not snapshot.is_empty() or bool(execution.get("backup_created", false))
	var local_active := repository == "local"
	var offsite_active := repository == "offsite"
	var count := 1 if saved else -1
	_draw_drive(Vector2(width * .35, 56), "local / 同じ拠点", count if local_active else 0 if repository == "offsite" else -1, local_active and saved, false, snapshot if local_active else "", true)
	_draw_building(Vector2(width * .35, 109), "offsite / 別拠点", count if offsite_active else 0 if repository == "local" else -1, offsite_active and saved, false, snapshot if offsite_active else "", true)

func _draw_drive(center: Vector2, title: String, count: int, active: bool, desired: bool, snapshot: String = "", execution_record: bool = false) -> void:
	var outline: Color = M.ACCENT if active else Color("8A9A91")
	# Desktop drive silhouette plus paper spines for each saved snapshot.
	var tower := Rect2(center + Vector2(-24, -16), Vector2(31, 32))
	draw_rect(tower, Color("FDFBF3"))
	draw_rect(tower, outline, false, 1.5)
	draw_line(tower.position + Vector2(4, 8), tower.position + Vector2(27, 8), outline, 1)
	draw_circle(tower.position + Vector2(7, 24), 2, outline)
	_pages(center + Vector2(20, 1), count, outline)
	_text(center + Vector2(45, -3), title, 11, M.INK)
	_text(center + Vector2(45, 13), "保存 " + _count_text(count) + "件", 11, M.ACCENT if active else M.MUTED)
	if active: _mark(center + Vector2(5, -19), "記" if execution_record else "現", M.ACCENT)
	if active and desired: _mark(center + Vector2(18, -19), "指", Color("798B61"))
	elif desired: _mark(center + Vector2(5, -19), "指", Color("798B61"))
	if not snapshot.is_empty(): _text(center + Vector2(45, 28), snapshot, 11, M.MUTED)

func _draw_building(center: Vector2, title: String, count: int, active: bool, desired: bool, snapshot: String = "", execution_record: bool = false) -> void:
	var outline: Color = M.ACCENT if active else Color("8A9A91")
	# Separate site is a small warehouse with a roof and doorway.
	var body := Rect2(center + Vector2(-23, -8), Vector2(34, 25))
	draw_rect(body, Color("FDFBF3"))
	draw_rect(body, outline, false, 1.5)
	draw_line(center + Vector2(-27, -8), center + Vector2(-6, -21), outline, 1.5)
	draw_line(center + Vector2(-6, -21), center + Vector2(15, -8), outline, 1.5)
	draw_rect(Rect2(center + Vector2(-10, 5), Vector2(9, 12)), Color("EADDBD"))
	_pages(center + Vector2(22, 2), count, outline)
	_text(center + Vector2(45, -3), title, 11, M.INK)
	_text(center + Vector2(45, 13), "保存 " + _count_text(count) + "件", 11, M.ACCENT if active else M.MUTED)
	if active: _mark(center + Vector2(5, -25), "記" if execution_record else "現", M.ACCENT)
	if active and desired: _mark(center + Vector2(18, -25), "指", Color("798B61"))
	elif desired: _mark(center + Vector2(5, -25), "指", Color("798B61"))
	if not snapshot.is_empty(): _text(center + Vector2(45, 28), snapshot, 11, M.MUTED)

func _pages(center: Vector2, count: int, ink: Color) -> void:
	if count < 0:
		_text(center + Vector2(-4, 4), "?", 12, M.WARNING)
		return
	var shown := mini(count, 4)
	for i in shown:
		var rect := Rect2(center + Vector2(i * 3, -11 - i * 2), Vector2(11, 17))
		draw_rect(rect, Color("FFF9E9"))
		draw_rect(rect, ink, false, 1)
	if count > 4: _text(center + Vector2(14, 3), "+", 11, ink)

func _mark(center: Vector2, text: String, ink: Color) -> void:
	draw_circle(center, 10, Color("FBF7EA"))
	draw_arc(center, 10, 0, TAU, 24, ink, 1.5)
	var width := UI.font(500).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(UI.font(500), center + Vector2(-width / 2, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)

func _update_tooltips_plan(current_known: bool, current_schedule: String, current_repository: String, desired_schedule: String, desired_repository: String) -> void:
	if route_buttons.size() < 4: return
	route_buttons[0].tooltip_text = "現在の計画: " + current_schedule + " / " + current_repository + "\n顧客指定: " + desired_schedule + " / " + desired_repository + ("\n現在の設定は不明" if not current_known else "")
	var snapshots_value: Variant = backup_work.get("snapshots", [])
	var snapshots: Array = snapshots_value if snapshots_value is Array else []
	var snapshot_known := bool(backup_work.get("snapshot_known", backup_work.get("snapshots_known", current_known)))
	var local_count := _snapshot_count(snapshots, "local") if snapshot_known else -1
	var offsite_count := _snapshot_count(snapshots, "offsite") if snapshot_known else -1
	route_buttons[1].tooltip_text = "local / 同じ拠点\n保存 " + _count_text(local_count) + "件" + (" · 現在" if current_known and current_repository == "local" else "") + (" · 顧客指定" if desired_repository == "local" else "")
	route_buttons[2].tooltip_text = "offsite / 別拠点\n保存 " + _count_text(offsite_count) + "件" + (" · 現在" if current_known and current_repository == "offsite" else "") + (" · 顧客指定" if desired_repository == "offsite" else "")
	var restore_value: Variant = backup_work.get("restore", {})
	var restore: Dictionary = restore_value if restore_value is Dictionary else {}
	route_buttons[3].tooltip_text = "復元先を開く。計画に表示する復元記録は今回の担当成果と別です。"
	if bool(restore.get("current_files", false)):
		route_buttons[3].tooltip_text = "現在の復元先にあるファイル数です。\n担当作業の実行件数は「担当の実行記録」へ。"

func _sync_tooltips() -> void:
	if mode == "receipt":
		var raw: Variant = backup_work.get("execution", {})
		var execution: Dictionary = raw if raw is Dictionary else {}
		_update_tooltips_receipt(execution)
	else:
		var known := bool(backup_work.get("available", false)) and bool(backup_work.get("known", false))
		var current_schedule := _schedule_display(_known_text(backup_work.get("schedule", ""), known))
		var current_repository := _known_text(backup_work.get("repository", ""), known)
		var desired_schedule := _schedule_display(_known_text(backup_work.get("desired_schedule", ""), _present(backup_work.get("desired_schedule", ""))))
		var desired_repository := _known_text(backup_work.get("desired_repository", ""), _present(backup_work.get("desired_repository", "")))
		_update_tooltips_plan(known, current_schedule, current_repository, desired_schedule, desired_repository)

func _update_tooltips_receipt(execution: Dictionary) -> void:
	if route_buttons.size() < 4: return
	var status := _execution_status(str(execution.get("status", "unknown")))
	var files_value: Variant = execution.get("files", [])
	var files: Array = files_value if files_value is Array else []
	var paths: Array[String] = []
	for item in files:
		if item is Dictionary and not str(item.get("path", "")).is_empty(): paths.append(str(item.get("path", "")))
	var detail := "\n".join(paths.slice(0, 4)) if not paths.is_empty() else "\n対象path ?"
	route_buttons[0].tooltip_text = "保存元: " + str(execution.get("source", "不明")) + "\n保存命令: " + ("実施" if bool(execution.get("backup_created", false)) else "新規保存なし")
	for index in [1, 2]:
		var repository := "local" if index == 1 else "offsite"
		var same := str(execution.get("repository", "")) == repository
		route_buttons[index].tooltip_text = repository + "\n" + (status + detail if same else "この担当作業での操作なし" if not execution.is_empty() else "実行記録不明") + "\n現在の保存先を開く"
	route_buttons[3].tooltip_text = "復元: " + status + "\n保存先 " + str(execution.get("target", "不明")) + detail

func _snapshot_count(snapshots: Array, repository: String) -> int:
	var count := 0
	for item in snapshots:
		if not item is Dictionary or str(item.get("repository", "")) != repository: continue
		count += 1
	return count

func _restored_file_count(files: Array) -> int:
	var count := 0
	var known := false
	for item in files:
		if not item is Dictionary: continue
		var status := str(item.get("status", ""))
		if status.is_empty(): continue
		known = true
		if status in ["restored", "written", "success", "unchanged"]: count += 1
	return count if known else -1

func _present(value: Variant) -> bool:
	return not str(value).strip_edges().is_empty()

func _known_text(value: Variant, known: bool) -> String:
	return str(value) if known and _present(value) else "?"

func _integer_or_unknown(value: Variant) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)): return -1
	return int(value) if int(value) >= 0 else -1

func _count_text(value: int) -> String:
	return str(value) if value >= 0 else "?"

func _schedule_display(value: String) -> String:
	match value:
		"daily": return "日次"
		"off", "disabled": return "無効"
		_: return value

func _execution_status(value: String) -> String:
	match value:
		"restored": return "✓ 復元完了"
		"selection_required": return "? 対象選択待ち"
		"failed": return "× 実行失敗"
		_: return "? 記録不明"

func _arrow(at: Vector2, ink: Color) -> void:
	draw_line(at - Vector2(6, 4), at, ink, 1.5)
	draw_line(at - Vector2(6, -4), at, ink, 1.5)

func _text(at: Vector2, value: String, points: int, ink: Color) -> void:
	var font_size := maxi(13, points)
	var available := maxf(0.0, size.x / factor - at.x - 8.0)
	var shown := value
	while shown.length() > 1 and UI.font(500).get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		shown = shown.left(shown.length() - 2) + "…"
	draw_string(UI.font(500), at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
