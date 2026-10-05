extends RefCounted
## Observation bench. Responses remain sourced from the guest VM.

const UI = preload("res://scripts/ui_theme.gd")
const Comparison = preload("res://scripts/text_comparison.gd")
const Observation = preload("res://scripts/diagnostic_observation.gd")
const Workbench = preload("res://scripts/diagnostic_workbench.gd")
const ShareObservation = preload("res://scripts/share_diagnostic_observation.gd")
const ShareWorkbench = preload("res://scripts/share_diagnostic_workbench.gd")
const INK := UI.INK
const MUTED := UI.MUTED
const BLUE := UI.PRIMARY
const GREEN := UI.GREEN
const RED := UI.RED
const BORDER := UI.BORDER
const OS_PANEL := UI.OS_PANEL
const OS_NAV := UI.OS_NAV
const OS_BORDER := UI.OS_BORDER
const OS_ACCENT := UI.OS_ACCENT
const DIAG_ACCENT := Color("7556ad")
const DIAG_PANEL := Color("faf8fc")
const DIAG_SELECTED := Color("e6deef")

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
	var split := BoxContainer.new()
	split.add_theme_constant_override("separation", 6)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(split)
	var rail := PanelContainer.new()
	rail.custom_minimum_size.x = 220
	rail.size_flags_horizontal = Control.SIZE_FILL
	rail.add_theme_stylebox_override("panel", d._style(OS_NAV, OS_BORDER, 6, 5))
	split.add_child(rail)
	var left = d._scroll(rail)
	left.add_theme_constant_override("separation", 2)
	var right = d._scroll(split)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 3
	var reflow := func() -> void:
		var stacked := split.size.x < 700.0
		split.vertical = stacked
		rail.custom_minimum_size = Vector2(0, 54 if str(d.diagnostic_ui.get("mode", "checks")) == "http" else 115) if stacked else Vector2(220, 0)
		left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if stacked else Control.SIZE_EXPAND_FILL
		right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.resized.connect(reflow)
	reflow.call_deferred()
	d.widgets.verify = {"left": left, "right": right, "body": right, "footer": null, "selected": "", "tally": tally, "signature": "", "raw_visible": false, "object": "", "replay": false}
	d.widgets.verify.selected = str(d.diagnostic_ui.get("selected", ""))
	d.widgets.verify.reflow = reflow
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

static func _probe_label(probe: Dictionary) -> String:
	if str(probe.get("command", "")).begins_with("sha256sum "):
		var args := ShareObservation.tokens(str(probe.command))
		if args.size() == 2: return args[1].get_file()
	return str(probe.get("label", ""))

static func _expected_outcome(probe: Dictionary) -> String:
	# Describe the public acceptance criterion, never hidden configuration values.
	var expectation := str(probe.get("expectation", ""))
	var command := str(probe.get("command", ""))
	var operation := "保存" if command.contains("put ") else "閲覧"
	if command.begins_with("smbclient "):
		if expectation == "DENIED" or expectation.contains("ACCESS_DENIED"):
			return operation + "を拒否する"
		return operation + "できる"
	if command.begins_with("sha256sum "): return "ファイル内容が保全した原本と一致する"
	var description := str(probe.get("description", ""))
	return description if not description.is_empty() else expectation

static func _actual_outcome(probe: Dictionary) -> String:
	if not bool(probe.get("recorded", false)): return "未計測です。検査実行で実際の動作を確かめます。"
	var response := str(probe.get("result", "")).strip_edges()
	var command := str(probe.get("command", ""))
	var outcome := response.get_slice("\n", 0)
	var operation := "保存" if command.contains("put ") else "閲覧"
	if response == "NT_STATUS_ACCESS_DENIED": outcome = operation + "が拒否されました"
	elif response.begins_with("NT_STATUS_BAD_NETWORK_NAME"): outcome = "共有に接続できませんでした"
	elif response.begins_with("putting file ") and response.ends_with(": OK"): outcome = "保存できました"
	elif response.begins_with("getting file ") and response.ends_with(": OK"): outcome = "読み込みできました"
	elif command.begins_with("sha256sum ") and response.get_slice(" ", 0).length() == 64:
		outcome = "ファイル内容が原本と一致しました" if response.get_slice(" ", 0) == str(probe.get("expectation", "")) else "ファイル内容が原本と異なります"
	if outcome.is_empty(): outcome = "応答は空でした"
	return ("変更前の記録：" if not bool(probe.get("fresh", false)) else "") + outcome

static func _reveal_result(d) -> void:
	if not is_instance_valid(d): return
	var result = d.widgets.verify.right.find_child("DiagnosticResult", true, false)
	if not is_instance_valid(result): return
	var scroll = d.widgets.verify.right.get_parent()
	if scroll is ScrollContainer: scroll.ensure_control_visible(result)

static func refresh(d) -> void:
	var w: Dictionary = d.widgets.verify
	var probes: Array = d.game.diagnostic_probes()
	var ready: bool = d.game.can_deliver()
	var mode := str(d.diagnostic_ui.get("mode", "checks"))
	var signature := str(probes) + str(ready) + str(d.game.vm_info().connected) + str(d.game.state.get("validated_revision", -1)) + str(w.selected) + str(w.raw_visible) + mode + str(d.diagnostic_ui.get("observations", [])) + str(w.get("operation_error", "")) + str(w.get("object", ""))
	if str(w.signature) == signature: return
	w.signature = signature
	if w.has("reflow"): w.reflow.call()
	var left: VBoxContainer = w.left
	var right: VBoxContainer = w.right
	d._clear(left)
	d._clear(right)
	var passed_count := 0
	for item in probes:
		if item.get("passed", false) and item.get("fresh", false): passed_count += 1
	w.tally.text = "%d / %d" % [passed_count, probes.size()]
	var modes := HFlowContainer.new(); modes.add_theme_constant_override("h_separation", 6); left.add_child(modes)
	for entry in [["checks", "受入条件の計測"], ["http", "HTTP試験"]]:
		var choice: Button = d._button(str(entry[1]), func(): d.diagnostic_ui["mode"] = str(entry[0]); d._save_session(false); refresh(d))
		choice.name = "DiagnosticMode_" + str(entry[0]); choice.toggle_mode = true; choice.button_pressed = mode == str(entry[0]); modes.add_child(choice)
	if mode == "http":
		_request_workspace(d, right)
		return
	left.add_child(d._label("検証項目", 12, DIAG_ACCENT))
	if probes.is_empty():
		right.add_child(d._label(_copy("os_result_none", "未実行"), 14, MUTED))
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
		var item_style = UI.style(DIAG_SELECTED if id == selected else OS_NAV, Color.TRANSPARENT, 0, 5, 0)
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
		var label = d._label(_probe_label(probe), 13, INK)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(label)
		var note = d._label(("原本 · " if str(probe.command).begins_with("sha256sum ") else "") + _status(probe), 11, _status_color(probe))
		note.autowrap_mode = TextServer.AUTOWRAP_OFF
		note.clip_text = true
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(note)
		button.tooltip_text = str(probe.label) + " / " + _status(probe)

	var state_color := _status_color(current)
	var top = d._row(right, 5)
	var current_title = d._label(_probe_label(current) + " · 原本照合" if str(current.command).begins_with("sha256sum ") else str(current.label), 18, INK)
	current_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(current_title)
	var status = d._label(_status(current), 13, state_color)
	top.add_child(status)
	var host = d.game.vm_info()
	right.add_child(d._label(("顧客端末  ·  " + str(host.get("host", ""))) if bool(host.get("connected", false)) else "顧客端末  ·  未接続", 12, MUTED))
	var expectation := str(current.get("expectation", current.get("description", "")))
	var description := str(current.get("description", ""))
	if not description.is_empty() and description != expectation:
		var details = d._disclosure(right, "検査詳細")
		var description_label = d._label(description, 13, INK)
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(description_label)
	var command_row = d._row(right, 5)
	var requires_login := bool(current.get("requires_login",false))
	var command_text := UI.copy("identity_username")+": "+str(current.get("user","")) if requires_login else _copy("os_command", "コマンド")+"  $ " + str(current.command)
	var graphical := str(current.command).begins_with("curl ") or str(current.command).begins_with("smbclient ") or str(current.command).begins_with("sha256sum ")
	if not graphical:
		var command = d._label(command_text, 13, BLUE)
		command.add_theme_font_override("font", d.mono)
		command.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		command_row.add_child(command)
	var run = d._primary(UI.copy("identity_test_login") if requires_login else "検査実行", func():
		d._trace("diagnostic", selected)
		if requires_login: d._open_identity_login(str(current.get("user","current")))
		else:
			w["object"] = ""
			var response: String = d.game.run_diagnostic(selected)
			w["operation_error"] = response if response.contains("測定結果を保存できませんでした") else ""
			w["operation_probe"] = selected
			w["replay"] = str(w.operation_error).is_empty()
			if not str(w.operation_error).is_empty(): d._notify(str(w.operation_error))
			refresh(d)
			_reveal_result.call_deferred(d))
	run.name = "DiagnosticRun"
	UI.os_primary(run, DIAG_ACCENT)
	run.disabled = not d.game.vm_info().connected or d.game.current_done()
	command_row.add_child(run)
	if not d.game.vm_info().connected:
		command_row.add_child(_tool(d, "link", "顧客端末に接続", func(): d.game.vm_run("ssh client"); refresh(d), "接続"))
	else:
		if not requires_login and not graphical: command_row.add_child(_tool(d, "code", "端末入力", d._type_command.bind(str(current.command)), "端末入力"))
	if graphical:
		_graphical_result(d, right, current, command_row)
		_delivery_action(d, right, probes)
		return

	var result_text := str(current.get("result", ""))
	var summary := "未実行"
	if not result_text.is_empty(): summary = result_text.get_slice("\n", 0)
	var result_panel := PanelContainer.new()
	result_panel.name = "DiagnosticResult"
	result_panel.add_theme_stylebox_override("panel", d._style(DIAG_PANEL, DIAG_ACCENT, 5, 6))
	right.add_child(result_panel)
	var result_content = d._box(result_panel, 5)
	if str(w.get("operation_probe", "")) == selected and not str(w.get("operation_error", "")).is_empty():
		var failure: Label = d._label(str(w.operation_error) + "\n以下は保存された前回の結果です。", 13, RED)
		failure.name = "DiagnosticOperationFailure"; result_content.add_child(failure)
	var result_header = d._row(result_content, 6)
	result_header.add_child(d._label("期待する結果", 12, MUTED))
	var expected = d._label(_expected_outcome(current), 13, INK)
	expected.name = "DiagnosticExpected"
	expected.tooltip_text = expectation
	expected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	expected.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_header.add_child(expected)
	result_content.add_child(HSeparator.new())
	var response_header = d._row(result_content, 6)
	response_header.add_child(d._label("今回の結果" if bool(current.get("fresh", false)) else "記録した結果", 12, MUTED))
	var result_state = d._label(_status(current), 12, state_color)
	result_state.name = "DiagnosticResultStatus"
	response_header.add_child(result_state)
	var result_label = d._label(_actual_outcome(current), 14, INK)
	result_label.name = "DiagnosticActual"
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.tooltip_text = result_text
	result_content.add_child(result_label)
	if bool(current.get("recorded", false)):
		var raw_summary = d._label(summary, 12, MUTED)
		raw_summary.name = "DiagnosticRawResponse"
		raw_summary.autowrap_mode = TextServer.AUTOWRAP_OFF
		raw_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		raw_summary.clip_text = true
		raw_summary.tooltip_text = result_text
		result_content.add_child(raw_summary)
	var compare_label := UI.copy("compare_close" if bool(w.raw_visible) else "compare_results")
	var raw_toggle: Button = _tool(d, "code", compare_label, func(): w.raw_visible = not bool(w.raw_visible); refresh(d), compare_label)
	raw_toggle.name = "DiagnosticCompare"
	raw_toggle.disabled = not bool(current.get("recorded", false))
	result_content.add_child(raw_toggle)
	if bool(w.raw_visible):
		_build_comparison(d, result_content, current)

	_delivery_action(d, right, probes)

static func _delivery_action(d, right: Control, probes: Array) -> void:
	var report = d._primary("納品条件確認", func(): d._trace("validate_delivery", ""); d.game.verify(); d._show_app("receipt"))
	report.name = "DiagnosticValidate"
	UI.os_primary(report, DIAG_ACCENT)
	report.disabled = probes.is_empty()
	report.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(report)

static func _graphical_result(d, parent: Control, probe: Dictionary, command_row: Control) -> void:
	var w: Dictionary = d.widgets.verify
	var shared := str(probe.command).begins_with("smbclient ") or str(probe.command).begins_with("sha256sum ")
	var value: Dictionary = ShareObservation.project(probe) if shared else Observation.project(probe)
	var content := VBoxContainer.new()
	content.name = "DiagnosticResult"
	content.add_theme_constant_override("separation", 6)
	parent.add_child(content)
	if str(w.get("operation_probe", "")) == str(probe.id) and not str(w.get("operation_error", "")).is_empty():
		var failure: Label = d._label(str(w.operation_error) + "\n作業台は保存済みの観測を表示しています。", 13, RED)
		failure.name = "DiagnosticOperationFailure"; content.add_child(failure)
	var address: Label = d._label(str(value.method) + "  " + str(value.path), 14, MUTED)
	address.name = "DiagnosticRequestPath"
	address.tooltip_text = str(probe.command)
	address.add_theme_font_override("font", d.mono)
	address.autowrap_mode = TextServer.AUTOWRAP_OFF
	address.clip_text = true
	content.add_child(address)
	var bench = ShareWorkbench.new() if shared else Workbench.new()
	content.add_child(bench)
	bench.setup(d, value, str(w.get("object", "")))
	bench.object_selected.connect(func(id: String):
		w["object"] = id
		refresh(d)
		var object = w.right.find_child("DiagnosticObject_" + id, true, false)
		if is_instance_valid(object): object.grab_focus()
		_reveal_inspector.call_deferred(d))
	if bool(w.get("replay", false)):
		w["replay"] = false
		bench.replay()
	var tools := HFlowContainer.new(); tools.add_theme_constant_override("h_separation", 6); content.add_child(tools)
	for action in command_row.get_children():
		command_row.remove_child(action); tools.add_child(action)
	parent.remove_child(command_row); command_row.queue_free()
	var replay: Button = d._button("観測を再生", bench.replay)
	replay.name = "DiagnosticReplayObservation"; replay.disabled = not bool(value.recorded) or str(value.transport) == "unknown"; tools.add_child(replay)
	var compare_label := UI.copy("compare_close" if bool(w.raw_visible) else "compare_results")
	var compare: Button = d._button(compare_label, func(): w.raw_visible = not bool(w.raw_visible); refresh(d))
	compare.name = "DiagnosticCompare"; compare.disabled = not bool(value.recorded); tools.add_child(compare)
	var details: Button = d._button("要求と受入条件", func():
		w["object"] = "request" if str(w.get("object", "")) != "request" else ""
		refresh(d)
		if not str(w.object).is_empty(): _reveal_inspector.call_deferred(d)
		else: _reveal_result.call_deferred(d))
	details.name = "DiagnosticDetails"; tools.add_child(details)
	if shared:
		var order: Array = ["request", "seal", "specimen", "gate"] if str(value.protocol) == "hash" else ["request", "gate", "specimen", "seal"]
		var first: Button = bench.objects[order[0]]
		var last: Button = bench.objects[order.back()]
		var probes: Array = w.left.find_children("DiagnosticProbe_*", "Button", true, false)
		if not probes.is_empty():
			var entry: Button = probes.back()
			entry.focus_next = entry.get_path_to(first); first.focus_previous = first.get_path_to(entry)
		var run: Button = tools.find_child("DiagnosticRun", true, false)
		if run != null: last.focus_next = last.get_path_to(run); run.focus_previous = run.get_path_to(last)
	if not str(w.get("object", "")).is_empty(): _inspect_object(d, content, probe, value, str(w.object))
	if bool(w.raw_visible): _build_comparison(d, content, probe)

static func _inspect_object(d, parent: Control, probe: Dictionary, value: Dictionary, id: String) -> void:
	if str(value.protocol) in ["smb", "hash"]:
		_inspect_share(d, parent, probe, value, id)
		return
	var body := VBoxContainer.new(); body.name = "DiagnosticInspector"; body.add_theme_constant_override("separation", 4); parent.add_child(body)
	var title := str({"request":"送信要求", "gate":"通信経路", "server":"サーバー応答", "specimen":"取得した資料", "seal":"原本照合"}.get(id, "観測"))
	var head = d._row(body, 6)
	var heading: Label = d._label(title, 16, DIAG_ACCENT); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(heading)
	var close: Button = d._button("閉じる", func(): d.widgets.verify["object"] = ""; refresh(d); _reveal_result.call_deferred(d)); close.name = "DiagnosticInspectorClose"; head.add_child(close)
	if id == "request":
		var command: Label = d._label(str(probe.command), 13, INK); command.add_theme_font_override("font", d.mono); body.add_child(command)
		if bool(d.game.vm_info().get("connected", false)) and not bool(probe.get("requires_login", false)):
			body.add_child(_tool(d, "code", "端末入力", d._type_command.bind(str(probe.command)), "端末入力"))
		var expected: Label = d._label(("HTTP %d" % int(value.expected_status) if int(value.expected_status) > 0 else _expected_outcome(probe)) + (" · 原本と一致" if not str(value.expected_hash).is_empty() else ""), 14, INK)
		expected.name = "DiagnosticExpected"; expected.tooltip_text = str(probe.get("expectation", "")); body.add_child(expected)
	elif id == "gate":
		var transport := str(value.transport)
		body.add_child(d._label("応答未観測" if not bool(value.recorded) else "遮断ルール · " + str(value.rule) if transport == "firewall" else "名前解決で停止" if transport == "dns" else "接続できず" if transport == "unreachable" else "サーバー応答まで到達" if transport == "replied" else "経路を特定できません", 14, INK))
		if transport == "firewall" and d._firewall_v2():
			var open: Button = d._button("pfSenseのルールへ", func(): d._show_app("browser"); d._browse_url(d.FIREWALL_URL, true))
			open.name = "DiagnosticOpenFirewall"; body.add_child(open)
	elif id == "server":
		body.add_child(d._label(str(value.host), 14, INK))
		var actual: Label = d._label("HTTP %d" % int(value.status) if int(value.status) > 0 else "応答未取得", 16, INK)
		actual.name = "DiagnosticActual"; actual.tooltip_text = str(probe.get("result", "")); body.add_child(actual)
		if not str(value.error).is_empty(): body.add_child(d._label(str(value.error), 13, RED))
	elif id == "specimen":
		var source: Dictionary = value.source
		if not source.is_empty():
			body.add_child(d._label(str(source.get("host", "")) + "  " + str(source.get("path", "")), 13, MUTED))
			if source.has("ok"): body.add_child(d._label("✓ 共有元を読み取り済み" if bool(source.ok) else "× 共有元から取得不可", 14, GREEN if bool(source.ok) else RED))
		var rows: Array = value.rows
		if rows.is_empty(): body.add_child(d._label(str(value.error) if not str(value.error).is_empty() else "資料は未取得です。" if not bool(value.recorded) or str(value.transport) != "replied" else "応答に業務レコードはありません。", 14, INK))
		else:
			var table := Tree.new(); table.name = "DiagnosticSpecimenRows"; table.columns = 3; table.hide_root = true; table.column_titles_visible = true; table.custom_minimum_size.y = 120
			for column in 3: table.set_column_title(column, str(["注文", "顧客", "金額"][column] if str(value.specimen) == "orders" else ["ID", "氏名", ""][column]))
			body.add_child(table); var root := table.create_item()
			for row in rows:
				if not row is Dictionary: continue
				var item := table.create_item(root)
				for column in 3: item.set_text(column, str(row.get(["order", "customer", "total"][column] if str(value.specimen) == "orders" else ["id", "name", ""][column], "")))
	elif id == "seal":
		body.add_child(d._label("原本と一致" if str(value.hash_match) == "match" else "原本と異なる" if str(value.hash_match) == "different" else "取得した応答に照合値がありません。", 16, GREEN if str(value.hash_match) == "match" else RED if str(value.hash_match) == "different" else MUTED))
		for entry in [["原本", str(value.expected_hash)], ["取得", str(value.hash)]]:
			var label: Label = d._label(str(entry[0]) + "  " + (str(entry[1]) if not str(entry[1]).is_empty() else "未取得"), 12, MUTED); label.add_theme_font_override("font", d.mono); label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; body.add_child(label)
	if bool(value.recorded):
		var raw: Label = d._label(str(probe.get("result", "")).get_slice("\n", 0), 12, MUTED)
		raw.name = "DiagnosticRawResponse"; raw.tooltip_text = str(probe.get("result", "")); raw.clip_text = true; raw.autowrap_mode = TextServer.AUTOWRAP_OFF; body.add_child(raw)
	var state: Label = d._label(_status(probe), 13, _status_color(probe)); state.name = "DiagnosticResultStatus"; body.add_child(state)

static func _inspect_share(d, parent: Control, probe: Dictionary, value: Dictionary, id: String) -> void:
	var body := VBoxContainer.new(); body.name = "DiagnosticInspector"; body.add_theme_constant_override("separation", 4); parent.add_child(body)
	var local := str(value.protocol) == "hash"
	var title := str({"request":"保全した原本" if local else "要求と受入条件", "gate":"手元の検査" if local else "応答と停止した段階", "specimen":"手元のファイル" if local else "取得した資料", "seal":"原本照合" if local else "保存された受入判定"}.get(id, "観測"))
	var head = d._row(body, 6)
	var heading: Label = d._label(title, 16, DIAG_ACCENT); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(heading)
	var close: Button = d._button("閉じる", func(): d.widgets.verify["object"] = ""; refresh(d); _reveal_result.call_deferred(d)); close.name = "DiagnosticInspectorClose"; head.add_child(close)
	if id == "request":
		var command: Label = d._label(str(probe.command), 13, INK); command.add_theme_font_override("font", d.mono); body.add_child(command)
		if bool(d.game.vm_info().get("connected", false)): body.add_child(_tool(d, "code", "端末入力", d._type_command.bind(str(probe.command)), "端末入力"))
		var expected: Label = d._label(_expected_outcome(probe), 14, INK); expected.name = "DiagnosticExpected"; expected.tooltip_text = str(probe.get("expectation", "")); body.add_child(expected)
	elif id == "specimen":
		if str(value.outcome) == "listed":
			var table := Tree.new(); table.name = "DiagnosticShareFiles"; table.hide_root = true; table.custom_minimum_size.y = 100
			for color in ["font_hovered_color", "font_hovered_dimmed_color", "font_hovered_selected_color"]: table.add_theme_color_override(color, INK)
			body.add_child(table)
			var root := table.create_item()
			for file in value.files: var item := table.create_item(root); item.set_text(0, str(file))
			body.add_child(d._label("一覧で取得したファイル名です。内容と原本の一致は別の検査で確認します。", 13, MUTED))
		elif str(value.outcome) in ["written", "downloaded"]:
			body.add_child(d._label(str(value.remote_name), 16, INK))
			if not str(value.local_path).is_empty(): body.add_child(d._label("手元  " + str(value.local_path), 13, MUTED))
			body.add_child(d._label("この応答にはファイル内容と照合値は含まれていません。", 13, MUTED))
		elif local: body.add_child(d._label(str(value.path), 14, INK))
		else: body.add_child(d._label("ファイル一覧・内容は未取得です。", 14, MUTED))
	elif id == "gate":
		body.add_child(d._label("手元のファイルだけを検査しています。共有接続の成否はこの結果から判断できません。" if local else "停止した段階  " + str({"identity":"利用者の認証", "share":"共有先への接続", "operation":"要求した操作", "specimen":"共有内の対象", "local_file":"手元のファイル", "request":"要求の形式"}.get(str(value.stop_at), "なし" if str(value.outcome) in ["listed", "written", "downloaded"] else "未特定")), 13, MUTED))
	if local and id in ["seal", "request", "specimen"]:
		for entry in [["原本", str(value.expected_hash)], ["手元", str(value.hash)]]:
			var fingerprint: Label = d._label(str(entry[0]) + "  " + (str(entry[1]) if not str(entry[1]).is_empty() else "未取得"), 12, MUTED); fingerprint.add_theme_font_override("font", d.mono); fingerprint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; body.add_child(fingerprint)
	var actual: Label = d._label(("変更前の記録 · " if bool(value.recorded) and not bool(value.fresh) else "") + ShareObservation.caption(value), 16, INK); actual.name = "DiagnosticActual"; actual.tooltip_text = str(probe.get("result", "")); body.add_child(actual)
	if bool(value.recorded):
		var raw: Label = d._label(str(probe.get("result", "")).get_slice("\n", 0), 12, MUTED); raw.name = "DiagnosticRawResponse"; raw.tooltip_text = str(probe.get("result", "")); raw.clip_text = true; raw.autowrap_mode = TextServer.AUTOWRAP_OFF; body.add_child(raw)
	var state: Label = d._label("受入判定 · " + _status(probe), 13, _status_color(probe)); state.name = "DiagnosticResultStatus"; body.add_child(state)

static func _reveal_inspector(d) -> void:
	if not is_instance_valid(d): return
	# Container layout and follow_focus settle after the shape was selected.
	# Scrolling before then can reveal only the inspector's empty header.
	await d.get_tree().process_frame
	await d.get_tree().process_frame
	if not is_instance_valid(d) or not d.widgets.has("verify"): return
	var inspector = d.widgets.verify.right.find_child("DiagnosticInspector", true, false)
	var scroll = d.widgets.verify.right.get_parent()
	if is_instance_valid(inspector) and scroll is ScrollContainer: scroll.ensure_control_visible(inspector)

static func _select(d, id: String) -> void:
	d.widgets.verify.selected = id
	d.widgets.verify["object"] = ""
	d.diagnostic_ui["selected"] = id
	d._save_session(false)
	refresh(d)

static func _request_workspace(d, parent: VBoxContainer) -> void:
	parent.add_child(d._label("要求URL", 13, MUTED))
	var url := LineEdit.new(); url.name = "DiagnosticRequestUrl"; url.placeholder_text = "https://..."; url.text = str(d.diagnostic_ui.get("url", "")); url.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(url)
	url.text_changed.connect(func(value): d.diagnostic_ui["url"] = value; d._save_session(false))
	var options: Array = [{"id":"", "label":"未認証"}]
	if d._portal_v2(): options = d.browser_identities()
	elif d._identity_v2():
		for session in d.game._vm().identity_snapshot().get("sessions", []):
			options.append({"id":str(session.id), "label":str(session.user) + " · " + str(session.id) + (" · 失効済み" if bool(session.get("revoked", false)) else "")})
	var controls := HFlowContainer.new(); controls.add_theme_constant_override("h_separation", 8); parent.add_child(controls)
	var identity := OptionButton.new(); identity.name = "DiagnosticRequestIdentity"; identity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; controls.add_child(identity)
	for option in options:
		identity.add_item(str(option.label)); identity.set_item_metadata(identity.item_count - 1, str(option.id))
		if str(option.id) == str(d.diagnostic_ui.get("identity", "")): identity.select(identity.item_count - 1)
	identity.item_selected.connect(func(index): d.diagnostic_ui["identity"] = str(identity.get_item_metadata(index)); d._save_session(false))
	var run: Button = d._primary("GETを実行", func(): _request(d, url.text, str(identity.get_item_metadata(identity.selected))))
	run.name = "DiagnosticRequestRun"; run.disabled = not bool(d.game.vm_info().get("connected", false)) or d.game.current_done(); run.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; controls.add_child(run)
	var error := str(d.diagnostic_ui.get("error", ""))
	if not error.is_empty(): parent.add_child(d._label(error, 13, RED))
	var observations: Array = d.diagnostic_ui.get("observations", [])
	if observations.is_empty(): parent.add_child(d._label("要求はまだ送信していません。", 13, MUTED)); return
	for index in range(observations.size() - 1, -1, -1):
		var observation: Dictionary = observations[index]
		var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel", d._style(DIAG_PANEL, BORDER, 8, 8)); parent.add_child(panel)
		var body: VBoxContainer = d._box(panel, 5)
		var response := str(observation.get("response", ""))
		var status: Label = d._label(_response_summary(response), 14, INK); status.name = "DiagnosticObservation_%d" % index; body.add_child(status)
		body.add_child(d._label("GET " + str(observation.get("url", "")), 13, INK))
		var fresh := str(observation.get("fingerprint", "")) == str(d.game._vm()._fingerprint())
		body.add_child(d._label(("現在の状態で観測" if fresh else "状態変更前の観測") + " · " + str(observation.get("identity_label", "未認証")), 12, MUTED))
		var detail: VBoxContainer = d._disclosure(body, "応答本文")
		var raw := CodeEdit.new(); raw.editable = false; raw.text = response; raw.custom_minimum_size.y = 140; detail.add_child(raw)
		var retry: Button = d._button("この要求を再送", func(): _request(d, str(observation.get("url", "")), str(observation.get("identity", ""))))
		retry.name = "DiagnosticReplay_%d" % index; retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; retry.disabled = run.disabled; body.add_child(retry)

static func _request(d, raw_url: String, identity: String) -> void:
	var url := raw_url.strip_edges()
	d.diagnostic_ui["url"] = raw_url; d.diagnostic_ui["identity"] = identity
	if (not url.begins_with("https://") and not url.begins_with("http://")) or url.length() > 2048 or url.contains("\n") or url.contains("\r") or url.contains("\t") or url.contains(" "):
		d.diagnostic_ui["error"] = "http:// または https:// から始まるURLを入力してください。"
	else:
		d.diagnostic_ui.erase("error")
		var command := "curl "
		if not identity.is_empty(): command += "-H 'Authorization: Bearer " + identity.replace("'", "'\"'\"'") + "' "
		command += "'" + url.replace("'", "'\"'\"'") + "'"
		var response: String = d.game.vm_run(command)
		var observations: Array = d.diagnostic_ui.get("observations", [])
		observations.append({"url":url, "identity":identity, "identity_label":identity if not identity.is_empty() else "未認証", "response":response, "fingerprint":str(d.game._vm()._fingerprint())})
		if observations.size() > 8: observations.pop_front()
		d.diagnostic_ui["observations"] = observations
	d._save_session(false)
	d.widgets.verify.signature = ""
	refresh(d)

static func _response_summary(response: String) -> String:
	var status := response.get_slice("\n", 0)
	var code := status.get_slice(" ", 1)
	var meaning := str({"200":"読み込み成功", "401":"認証できませんでした", "403":"アクセス拒否", "404":"対象が見つかりません", "410":"リンク期限切れ", "503":"サービス利用不可"}.get(code, "要求の結果"))
	return meaning + " · " + status

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
