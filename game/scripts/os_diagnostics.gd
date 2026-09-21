extends RefCounted
## Compact Cockpit-like diagnostic view. Responses remain sourced from the guest VM.

const UI = preload("res://scripts/ui_theme.gd")
const Comparison = preload("res://scripts/text_comparison.gd")
const INK := UI.INK
const MUTED := UI.MUTED
const BLUE := UI.PRIMARY
const GREEN := UI.GREEN
const RED := UI.RED
const BORDER := UI.BORDER
const OS_PANEL := UI.OS_PANEL
const OS_NAV := UI.OS_NAV
const OS_SELECTED := UI.OS_SELECTED
const OS_BORDER := UI.OS_BORDER
const OS_ACCENT := UI.OS_ACCENT
const DIAG_ACCENT := Color("7556ad")
const DIAG_PANEL := Color("faf8fc")

static func _copy(key: String, fallback: String) -> String:
	return UI.copy(key, fallback)

static func _tool(d, symbol: String, tooltip: String, callback: Callable, label := "") -> Button:
	var b: Button
	if d.has_method("_tool_button"):
		b = d._tool_button(symbol, tooltip, callback)
		if not label.is_empty(): b.text = label
	else:
		b = d._button(label, callback)
	b.tooltip_text = tooltip
	b.custom_minimum_size.y = 30
	if label.is_empty(): b.text = ""
	return b

static func build(d, parent: VBoxContainer) -> void:
	var p = d._pad(parent, 8)
	var header = d._row(p, 6)
	var title = d._label("診断ラボ", 18, DIAG_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var tally = d._label("", 13, BLUE)
	tally.add_theme_color_override("font_color", DIAG_ACCENT)
	header.add_child(tally)
	var split = d._row(p, 6)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rail := PanelContainer.new()
	rail.custom_minimum_size.x = 220
	rail.size_flags_horizontal = Control.SIZE_FILL
	rail.add_theme_stylebox_override("panel", d._style(OS_NAV, OS_BORDER, 6, 5))
	split.add_child(rail)
	var left = d._scroll(rail)
	left.add_theme_constant_override("separation", 2)
	var right = d._scroll(split)
	right.size_flags_stretch_ratio = 3
	var footer = d._row(p, 4)
	d.widgets.verify = {"left": left, "right": right, "body": right, "footer": footer, "selected": "", "tally": tally, "signature": "", "raw_visible": false}
	refresh(d)

static func _status(probe: Dictionary) -> String:
	if not probe.get("recorded", false): return _copy("os_result_none", "未実行")
	if not probe.get("fresh", false): return _copy("os_result_stale", "過去の診断結果")
	return _copy("os_result_pass", "合格") if probe.get("passed", false) else _copy("os_result_fail", "不合格")

static func _status_icon(probe: Dictionary) -> String:
	if not probe.get("recorded", false): return "○"
	if not probe.get("fresh", false): return "↻"
	return "✓" if probe.get("passed", false) else "!"

static func _status_color(probe: Dictionary) -> Color:
	if not probe.get("recorded", false): return MUTED
	if not probe.get("fresh", false): return BLUE
	return GREEN if probe.get("passed", false) else RED

static func refresh(d) -> void:
	var w: Dictionary = d.widgets.verify
	var probes: Array = d.game.diagnostic_probes()
	var ready: bool = d.game.can_deliver()
	var signature := str(probes) + str(ready) + str(d.game.vm_info().connected) + str(d.game.state.get("validated_revision", -1)) + str(w.selected) + str(w.raw_visible)
	if str(w.signature) == signature: return
	w.signature = signature
	var left: VBoxContainer = w.left
	var right: VBoxContainer = w.right
	var footer: HBoxContainer = w.footer
	d._clear(left)
	d._clear(right)
	d._clear(footer)
	var passed_count := 0
	for item in probes:
		if item.get("passed", false) and item.get("fresh", false): passed_count += 1
	w.tally.text = "%d / %d" % [passed_count, probes.size()]
	left.add_child(d._label("検証項目", 12, DIAG_ACCENT))
	if probes.is_empty():
		right.add_child(d._label(_copy("os_result_none", "未実行"), 14, MUTED))
		footer.add_child(_tool(d, "inbox", "メール表示", d._show_app.bind("mail"), "メール表示"))
		return
	var selected := str(w.selected)
	if not probes.any(func(probe): return str(probe.id) == selected):
		selected = str(probes[0].id)
		w.selected = selected
	var current: Dictionary = {}
	for probe in probes:
		var id := str(probe.id)
		if id == selected: current = probe
		var button = d._button("", _select.bind(d, id))
		button.name = "DiagnosticProbe_" + id
		button.custom_minimum_size = Vector2(0, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.os_navigation(button, id == selected, DIAG_ACCENT)
		var item_style = UI.style(OS_SELECTED if id == selected else OS_NAV, Color.TRANSPARENT, 0, 5, 0)
		if id == selected:
			item_style.border_color = DIAG_ACCENT
			item_style.border_width_left = 3
			item_style.border_width_top = 0
			item_style.border_width_right = 0
			item_style.border_width_bottom = 0
		button.add_theme_stylebox_override("normal", item_style)
		left.add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_top", 3)
		margin.add_theme_constant_override("margin_bottom", 3)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		var row = d._row(margin, 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon = d._label(_status_icon(probe), 16, _status_color(probe))
		icon.custom_minimum_size.x = 20
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var col = d._box(row, 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label = d._label(str(probe.label), 13, INK)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(label)
		var note = d._label(_status(probe), 11, _status_color(probe))
		note.autowrap_mode = TextServer.AUTOWRAP_OFF
		note.clip_text = true
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(note)
		button.tooltip_text = str(probe.label) + " / " + _status(probe)

	var state_color := _status_color(current)
	var top = d._row(right, 5)
	var current_title = d._label(str(current.label), 18, INK)
	current_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(current_title)
	var status = d._label(_status(current), 13, state_color)
	top.add_child(status)
	var host = d.game.vm_info()
	right.add_child(d._label(("顧客端末  ·  " + str(host.get("host", ""))) if bool(host.get("connected", false)) else "顧客端末  ·  未接続", 12, MUTED))
	var details = d._disclosure(right, "検査詳細")
	var expectation = d._label(str(current.get("description", current.get("expectation", ""))), 13, INK)
	expectation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(expectation)
	var command_row = d._row(right, 5)
	var requires_login := bool(current.get("requires_login",false))
	var command_text := UI.copy("identity_username")+": "+str(current.get("user","")) if requires_login else _copy("os_command", "コマンド")+"  $ " + str(current.command)
	var command = d._label(command_text, 13, BLUE)
	command.add_theme_font_override("font", d.mono)
	command.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_row.add_child(command)
	var run = d._primary(UI.copy("identity_test_login") if requires_login else "検査実行", func():
		d._trace("diagnostic", selected)
		if requires_login: d._open_identity_login(str(current.get("user","current")))
		else: d.game.run_diagnostic(selected); refresh(d))
	run.name = "DiagnosticRun"
	UI.os_primary(run, DIAG_ACCENT)
	run.disabled = not d.game.vm_info().connected or d.game.current_done()
	command_row.add_child(run)
	if not d.game.vm_info().connected:
		command_row.add_child(_tool(d, "link", "顧客端末に接続", func(): d.game.vm_run("ssh client"); refresh(d), "接続"))
	else:
		if not requires_login: command_row.add_child(_tool(d, "code", "端末入力", d._type_command.bind(str(current.command)), "端末入力"))

	var result_text := str(current.get("result", ""))
	var summary := "未実行"
	if not result_text.is_empty(): summary = result_text.get_slice("\n", 0)
	var result_panel := PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", d._style(DIAG_PANEL, DIAG_ACCENT, 5, 6))
	right.add_child(result_panel)
	var result_row = d._row(result_panel, 6)
	result_row.add_child(d._label(_copy("os_response", "結果"), 12, MUTED))
	var result_label = d._label(summary, 13, INK)
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	result_label.clip_text = true
	result_row.add_child(result_label)
	var compare_label := UI.copy("compare_close" if bool(w.raw_visible) else "compare_results")
	var raw_toggle: Button = _tool(d, "code", compare_label, func(): w.raw_visible = not bool(w.raw_visible); refresh(d), compare_label)
	raw_toggle.name = "DiagnosticCompare"
	raw_toggle.disabled = not bool(current.get("recorded", false))
	result_row.add_child(raw_toggle)
	if bool(w.raw_visible):
		_build_comparison(d, right, current)

	footer.add_child(_tool(d, "settings", "設定編集", d._open_config, "設定編集"))
	footer.add_child(_tool(d, "grid", "サービス管理", d._show_app.bind("monitor"), "サービス管理"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var report = d._primary("納品条件確認", func(): d._trace("validate_delivery", ""); d.game.verify(); d._show_app("receipt"))
	report.name = "DiagnosticValidate"
	UI.os_primary(report, DIAG_ACCENT)
	report.disabled = probes.is_empty()
	footer.add_child(report)

static func _select(d, id: String) -> void:
	d.widgets.verify.selected = id
	refresh(d)

static func _build_comparison(d, parent: Control, probe: Dictionary) -> void:
	if not bool(probe.get("recorded", false)): return
	var latest := str(probe.get("result", ""))
	# Old saves without a first observation must not acquire a fictional one.
	if not probe.has("initial_result"):
		_output(d, parent, "DiagnosticLatest", UI.copy("compare_latest"), latest, [], Color.TRANSPARENT)
		return
	var initial := str(probe.initial_result)
	var diff := Comparison.compare(initial, latest)
	if initial == latest:
		parent.add_child(d._label(UI.copy("compare_unchanged"), 12, MUTED))
	var panes := BoxContainer.new()
	panes.name = "DiagnosticComparison"
	panes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panes.add_theme_constant_override("separation", 8)
	parent.add_child(panes)
	panes.resized.connect(func(): panes.vertical = panes.size.x < 720)
	panes.vertical = panes.size.x < 720
	_output(d, panes, "DiagnosticFirst", UI.copy("compare_first"), initial, diff.removed, Color("633739"))
	_output(d, panes, "DiagnosticLatest", UI.copy("compare_latest"), latest, diff.added, Color("254e3d"))

static func _output(d, parent: Control, id: String, title: String, text: String, changed: Array, tint: Color) -> void:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	panel.add_child(d._label(title, 13, INK))
	var output := CodeEdit.new()
	output.name = id
	output.editable = false
	output.text = text
	var font_size := maxi(13, int(13 * float(d.game.settings.get("text_scale", 1.0))))
	output.custom_minimum_size = Vector2(0, clampi(text.split("\n").size() * (font_size + 5) + 24, 76, 220))
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.gutters_draw_line_numbers = true
	output.highlight_current_line = false
	output.add_theme_font_override("font", d.mono)
	output.add_theme_font_size_override("font_size", font_size)
	output.add_theme_color_override("background_color", Color("20262e"))
	output.add_theme_color_override("font_color", Color("f1f4f8"))
	output.add_theme_color_override("font_readonly_color", Color("f1f4f8"))
	output.add_theme_color_override("line_number_color", Color("acb9ca"))
	panel.add_child(output)
	for line in changed:
		output.set_line_background_color(int(line), tint)
