extends RefCounted
## AOBA OS terminal surface. Commands are entered and executed by desktop.gd.

const UI = preload("res://scripts/ui_theme.gd")
const INK := UI.INK
const MUTED := UI.MUTED
const TEAL := UI.PRIMARY
const PANEL := UI.BG
const TERMINAL := Color("0c0c0c")
const TERMINAL_TAB := Color("202020")
const TERMINAL_BORDER := Color("3f3f46")
const TERMINAL_TEXT := Color("f2f2f2")

static func build(os, parent: VBoxContainer) -> void:
	var p = os._pad(parent, 0)
	var session_strip := PanelContainer.new()
	session_strip.add_theme_stylebox_override("panel", UI.style(TERMINAL_TAB, TERMINAL_BORDER, 0, 0, 0))
	p.add_child(session_strip)
	var session = os._row(session_strip, 4)
	session.custom_minimum_size.y = 30
	var session_tab := PanelContainer.new()
	session_tab.custom_minimum_size = Vector2(220, 30)
	session_tab.add_theme_stylebox_override("panel", UI.style(TERMINAL, TERMINAL_BORDER, 0, 5, 0))
	session.add_child(session_tab)
	var session_label = os._label(UI.copy("fidelity_terminal_local", "ローカル PC")+"  /  未接続", 13, TERMINAL_TEXT); session_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; session_label.autowrap_mode = TextServer.AUTOWRAP_OFF; session_label.clip_text = true; session_tab.add_child(session_label)
	var session_spacer := Control.new(); session_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; session.add_child(session_spacer)
	var connect_button = os._primary(UI.copy("fidelity_connect", "接続"), func(): os._run_command("ssh client")); connect_button.custom_minimum_size.y = 28; session.add_child(connect_button)
	connect_button.name = "TerminalConnect"
	var disconnect_button = os._button(UI.copy("fidelity_disconnect", "切断"), func(): os._run_command("exit")); disconnect_button.custom_minimum_size.y = 28; session.add_child(disconnect_button)
	var read_button = os._button("依頼内容を確認", func(): os._show_app("mail")); read_button.queue_free()
	var config_button = os._button("設定を開く", os._open_config); config_button.hide(); session.add_child(config_button)

	var status = os._label("", 13, MUTED); status.autowrap_mode = TextServer.AUTOWRAP_OFF; status.clip_text = true; status.hide(); p.add_child(status)
	var terminal_panel := PanelContainer.new(); terminal_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL; terminal_panel.add_theme_stylebox_override("panel", UI.style(TERMINAL, TERMINAL_BORDER, 0, 0, 0)); p.add_child(terminal_panel)
	var terminal_box = os._box(terminal_panel, 8)
	var log := RichTextLabel.new(); log.name = "TerminalOutput"; log.selection_enabled = true; log.scroll_following = true; log.fit_content = false; log.size_flags_vertical = Control.SIZE_EXPAND_FILL; log.add_theme_font_override("normal_font", os.mono); log.add_theme_font_size_override("normal_font_size", int(16 * float(os.game.settings.get("text_scale",1.0)))); log.add_theme_color_override("default_color", TERMINAL_TEXT); log.text = ""; terminal_box.add_child(log)
	var input_row = os._row(terminal_box, 6)
	var local_name: String = str(os._personalize("自席PC（"+os._company_name()+" / "+os._player_display_name()+"）"))
	var prompt = os._label("自席PC $", 16, TERMINAL_TEXT); prompt.autowrap_mode = TextServer.AUTOWRAP_OFF; prompt.clip_text = true; prompt.custom_minimum_size.x = 88; prompt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; prompt.tooltip_text = local_name; input_row.add_child(prompt)
	var input := LineEdit.new(); input.name = "CommandInput"; input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; input.custom_minimum_size.y = 42; input.placeholder_text = "コマンドを入力…"; input.add_theme_font_override("font", os.mono); input.add_theme_font_size_override("font_size", int(16 * float(os.game.settings.get("text_scale",1.0)))); input.text_submitted.connect(os._run_command); input.gui_input.connect(os._terminal_input); input_row.add_child(input)
	input.add_theme_stylebox_override("normal",UI.style(TERMINAL,Color.TRANSPARENT,2,3,0)); input.add_theme_stylebox_override("focus",UI.style(TERMINAL,Color("0078d4"),2,3,0)); input.add_theme_color_override("font_color",TERMINAL_TEXT); input.add_theme_color_override("caret_color",TERMINAL_TEXT); input.add_theme_color_override("font_placeholder_color",Color("9a9a9a"))
	os.widgets.terminal = {"output": log, "command": input, "prompt": prompt, "session": session_label, "status": status, "connect": connect_button, "disconnect": disconnect_button, "config":config_button, "suggestions": null}
	os.output = log; os.command = input; os.prompt = prompt
	var guide: Button
	guide = os._button("入力補助", func():
		var suggestions: Control = os.widgets.terminal.get("suggestions")
		if is_instance_valid(suggestions):
			suggestions.visible = not suggestions.visible
			os.widgets.terminal.guide.text = "⌃" if suggestions.visible else "⌄"
			os.widgets.terminal.footer.visible = false
	); guide.custom_minimum_size.y = 28; session.add_child(guide)
	guide.text = "⌄"
	guide.tooltip_text = UI.copy("fidelity_command_suggestions", "コマンド候補")
	var suggestions = os._box(p, 5); suggestions.visible = false; os.widgets.terminal.suggestions = suggestions
	os.widgets.terminal.guide = guide
	guide.text = "⌄"
	var hint = os._label("候補を選択", 13, MUTED); hint.visible = false; suggestions.add_child(hint)
	var picker_row = os._row(suggestions, 8)
	var picker := OptionButton.new(); picker.name = "CommandPicker"; picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; picker.custom_minimum_size.y = 38
	var command_values: Array = [
		["ssh client", "顧客端末へ接続"],
		["help", "使用可能なコマンド・操作を確認"],
		["cat /home/operator/requirements.txt", "依頼条件を確認"],
		["ls /etc", "設定ファイルの場所を調べる"],
		["systemctl status "+str(os.game.vm_info().service), "サービスの稼働状態を確認"],
		["journalctl", "操作ログとサービスログを確認"]
	]
	var info: Dictionary = os.game.vm_info()
	if str(info.get("service","")) == "samba": command_values.append(["testparm -s", "Samba設定の構文を確認"])
	if not str(info.get("config_path", "")).is_empty(): command_values.append(["cat "+str(info.config_path), "設定ファイルの内容を確認"])
	if os.game.has_method("diagnostic_probes"):
		for probe in os.game.diagnostic_probes():
			var probe_command := str(probe.get("command", ""))
			if not probe_command.is_empty(): command_values.append([probe_command, "診断: "+str(probe.get("label", ""))])
	var preview = os._label("", 13, MUTED); preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; suggestions.add_child(preview)
	for item in command_values: picker.add_item(str(item[1])); picker.set_item_metadata(picker.item_count - 1, str(item[0]))
	picker.item_selected.connect(func(index):
		preview.text = str(command_values[index][0])
	)
	var initial := 4 if info.connected else 0
	picker.select(initial); preview.text = str(command_values[initial][0])
	picker_row.add_child(picker)
	var enter = os._button("コマンドを入力", func():
		var index := picker.selected
		if index < 0 or index >= command_values.size(): return
		input.text = str(picker.get_item_metadata(index)); input.caret_column = input.text.length()
		input.grab_focus(); input.caret_column = input.text.length()
	); enter.custom_minimum_size.y = 38; picker_row.add_child(enter)
	var footer = os._row(p, 5)
	os.widgets.terminal.footer = footer; footer.hide()
	footer.add_child(os._button("診断ラボを開く", os._show_app.bind("verify")))
	footer.add_child(os._button("ログを消去", os._run_command.bind("clear")))
	footer.add_child(os._label("↑↓ 履歴  /  Tab 補完  /  Ctrl+L 消去", 13, MUTED))
	refresh(os)

static func refresh(os) -> void:
	if not os.widgets.has("terminal"): return
	var w: Dictionary = os.widgets.terminal
	var info: Dictionary = os.game.vm_info()
	var connected := bool(info.get("connected", false))
	var host := str(info.get("host", "client")) if connected else local_display(os)
	var service := str(info.get("service", ""))
	var cwd := str(info.get("cwd", "~")) if connected else "~"
	if is_instance_valid(w.get("session")): w.session.text = host+"  ·  "+cwd
	if is_instance_valid(w.get("status")): w.status.text = ("接続中  ·  "+host+"  ·  "+cwd) if connected else "未接続  ·  "+host
	if is_instance_valid(w.get("prompt")):
		w.prompt.text = host.get_slice(".", 0)+" $" if connected else "自席PC $"
		w.prompt.tooltip_text = host
	if is_instance_valid(w.get("connect")): w.connect.visible = not connected
	if is_instance_valid(w.get("disconnect")): w.disconnect.visible = connected
	if is_instance_valid(w.get("config")): w.config.disabled = not connected
	var next_log: String = os.terminal_log
	if is_instance_valid(w.get("output")) and w.output.text != next_log: w.output.text = next_log

static func local_display(os) -> String:
	return os._personalize("自席PC（"+os._company_name()+" / "+os._player_display_name()+"）")
