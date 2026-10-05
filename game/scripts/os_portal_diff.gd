extends RefCounted
## A single aligned sheet keeps the changed values together, even when the
## surrounding file list and sharing pane occupy most of the browser.
const DIFF = preload("res://scripts/portal_version_diff.gd")
const UI = preload("res://scripts/ui_theme.gd")
const BLUE := Color("006a9e")
const LINE := Color("d5dfe5")

static func render(d, parent: VBoxContainer, saved: String, current: String) -> void:
	var diff: Dictionary = DIFF.compare(saved, current)
	var scale: float = float(d.game.settings.get("text_scale", 1.0))
	var comparison_error: String = str(diff.get("error", ""))
	if not comparison_error.is_empty():
		parent.add_child(d._label("表として比較できません · 元の内容を開いて確認してください。", 13, UI.WARNING))
	var summary := HFlowContainer.new(); summary.name = "PortalDiffSummary"; summary.add_theme_constant_override("h_separation", 14); parent.add_child(summary)
	for spec in [["Δ 変更", "changed"], ["＋ 追加", "added"], ["− 削除", "removed"], ["↕ 移動", "moved"]]:
		var count: Label = d._label("%s %d" % [str(spec[0]), int(diff.counts.get(str(spec[1]), 0))], 13, UI.INK)
		count.autowrap_mode = TextServer.AUTOWRAP_OFF; summary.add_child(count)
	var controls := HFlowContainer.new(); controls.add_theme_constant_override("h_separation", 8); parent.add_child(controls)
	var all_rows: bool = bool(d.portal_ui.get("diff_all_rows", false))
	var toggle: Button = d._button("差分だけ表示" if all_rows else "全行を表示", func(): d.portal_ui["diff_all_rows"] = not all_rows; d._save_session(false); d._render_portal())
	toggle.name = "PortalDiffShowAll"; controls.add_child(toggle)
	var next: Button = d._button("次の差分", func(): pass); next.name = "PortalDiffNext"; controls.add_child(next)
	var match_label: String = str(diff.get("matching", "position"))
	var matching: Label = d._label(match_label.trim_prefix("key:") + "で比較" if match_label.begins_with("key:") else "行位置で比較", 12, UI.MUTED)
	matching.autowrap_mode = TextServer.AUTOWRAP_OFF; controls.add_child(matching)
	if bool(diff.get("byte_only", false)):
		parent.add_child(d._label("形式のみ変更 · 元の内容は下の詳細で比較できます。", 13, UI.WARNING))
	var viewport := ScrollContainer.new(); viewport.name = "PortalVersionDiffViewport"; viewport.custom_minimum_size.y = 190 * scale; viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(viewport)
	var columns: Array = diff.columns.slice(0, 32)
	var table := GridContainer.new(); table.name = "PortalVersionDiffGrid"; table.columns = columns.size() + 1; table.add_theme_constant_override("h_separation", 0); table.add_theme_constant_override("v_separation", 0); viewport.add_child(table)
	table.set_meta("comparison", diff.duplicate(true))
	_cell(d, table, "行", "", false, "header", 80 * scale)
	var changes: Array[Control] = []
	for column in columns:
		var before: String = str(column.get("before", "")); var after: String = str(column.get("after", ""))
		var changed: bool = before != after or int(column.get("before_index", -1)) < 0 or int(column.get("after_index", -1)) < 0
		var before_label: String = "—" if int(column.before_index) < 0 else before if not before.is_empty() else "列%d · 見出しなし" % int(column.before_index)
		var after_label: String = "—" if int(column.after_index) < 0 else after if not after.is_empty() else "列%d · 見出しなし" % int(column.after_index)
		var cell: Control = _cell(d, table, before_label, after_label, changed, "header", 112 * scale)
		if changed: changes.append(cell)
		elif int(column.before_index) != int(column.after_index):
			var position: Label = d._label("列 %d→%d" % [int(column.before_index), int(column.after_index)], 11, BLUE)
			cell.get_child(0).add_child(position); changes.append(cell)
	var shown := 0
	for row in diff.rows:
		var kind: String = str(row.kind)
		if not all_rows and kind == "unchanged" and not bool(row.moved): continue
		if shown >= 200: break
		shown += 1
		var symbol: String = {"added":"＋", "removed":"−", "changed":"Δ"}.get(kind, "↕" if bool(row.moved) else "=")
		var position: String = str(row.before_index) + "→" + str(row.after_index) if int(row.before_index) > 0 and int(row.after_index) > 0 and int(row.before_index) != int(row.after_index) else str(maxi(int(row.before_index), int(row.after_index)))
		var gutter: Control = _cell(d, table, symbol + " " + position, "", false, kind, 80 * scale)
		gutter.set_meta("row_kind", kind); gutter.set_meta("moved", bool(row.moved))
		if bool(row.moved): changes.append(gutter)
		for raw in row.cells.slice(0, 32):
			var before: String = _value(str(raw.before), bool(raw.before_present))
			var after: String = _value(str(raw.after), bool(raw.after_present))
			var cell_changed: bool = bool(raw.changed) or kind in ["added", "removed"]
			var cell: Control = _cell(d, table, before, after, cell_changed, kind, 112 * scale)
			cell.set_meta("before", raw.before); cell.set_meta("after", raw.after)
			cell.set_meta("before_present", raw.before_present); cell.set_meta("after_present", raw.after_present)
			if cell_changed: changes.append(cell)
	var displayed_rows: int = diff.rows.size() if all_rows else diff.rows.filter(func(row): return str(row.kind) != "unchanged" or bool(row.moved)).size()
	if diff.columns.size() > 32 or displayed_rows > 200:
		parent.add_child(d._label("先頭32列・200行まで表示 · 残りは元の内容で確認できます。", 12, UI.MUTED))
	if changes.is_empty() and not all_rows and comparison_error.is_empty():
		var outside: bool = int(diff.counts.changed) + int(diff.counts.added) + int(diff.counts.removed) + int(diff.counts.moved) > 0
		parent.add_child(d._label("表示範囲の外に差分があります。元の内容を確認してください。" if outside else "行の内容に差分はありません。", 13, UI.MUTED))
	next.disabled = changes.is_empty()
	var cursor: Array[int] = [-1]
	next.pressed.connect(func():
		cursor[0] = (cursor[0] + 1) % changes.size()
		var outer: Node = viewport.get_parent()
		while outer != null and not outer is ScrollContainer: outer = outer.get_parent()
		if outer is ScrollContainer: outer.ensure_control_visible(viewport)
		viewport.ensure_control_visible(changes[cursor[0]])
		next.text = "次の差分 %d/%d" % [cursor[0] + 1, changes.size()])
	for spec in [["保存内容", saved, "PortalVersionPreviewGridSource"], ["現在内容", current, "PortalVersionCurrentGridSource"]]:
		var source: VBoxContainer = d._disclosure(parent, str(spec[0]) + " · 元の内容")
		var text := TextEdit.new(); text.name = str(spec[2]); text.editable = false; text.text = str(spec[1]); text.custom_minimum_size.y = 120 * scale
		text.add_theme_stylebox_override("normal", UI.style(Color.WHITE, LINE, 10, 10, 3)); text.add_theme_color_override("font_readonly_color", UI.INK)
		if d.mono != null: text.add_theme_font_override("font", d.mono)
		source.add_child(text)

static func _value(value: String, present: bool) -> String:
	return "—" if not present else "(空欄)" if value.is_empty() else value

static func _cell(d, table: GridContainer, before: String, after: String, changed: bool, kind: String, width: float) -> Control:
	var cell := PanelContainer.new(); cell.custom_minimum_size = Vector2(width, 38); table.add_child(cell)
	cell.set_meta("diff_change", changed)
	var bg := Color("edf3f7") if kind == "header" else Color("fff5d8") if changed else Color.WHITE
	cell.add_theme_stylebox_override("panel", UI.style(bg, BLUE if changed else LINE, 7, 5, 0))
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 3); cell.add_child(content)
	for value in (["− " + before, "＋ " + after] if changed else [before]):
		var label: Label = d._label(str(value), 13, UI.INK); label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.clip_text = true; label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; label.tooltip_text = str(value); content.add_child(label)
	return cell
