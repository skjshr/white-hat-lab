extends RefCounted
const UI = preload("res://scripts/ui_theme.gd")

static func render(d, body: VBoxContainer, footer: HBoxContainer) -> bool:
	var g = d.game
	if not g.has_method("contract_closeout_preview"): return false
	var receipt: Dictionary = g.completion_receipt()
	if bool(g.state.get("career_mode", false)) and not bool(g.state.get("accepted", false)) and str(receipt.get("kind", "")) == "cancellation":
		_result(d, body, footer, receipt); return true
	var w: Dictionary = d.widgets.receipt
	if not bool(w.get("closeout_open", false)): return false
	var preview: Dictionary = g.contract_closeout_preview()
	if not bool(preview.get("available", false)) or str(w.get("closeout_id", "")) != str(preview.get("id", "")):
		w.closeout_open = false; return false
	body.add_child(d._label("案件の中止", 27, UI.INK))
	var title: Label = d._label(str(preview.get("title", "")), 17); title.name = "CloseoutTitle"; body.add_child(title)
	body.add_child(d._label(str(preview.get("client", "")), 14, UI.MUTED))
	_numbers(d, body, preview)
	var queue_count: int = preview.get("queued_jobs", []).size()
	if queue_count > 0: body.add_child(d._label("この案件の作業配分 %d 件を停止" % queue_count, 14, UI.WARNING))
	body.add_child(d._label("受注枠 %d / %d → %d / %d" % [int(preview.open_before), int(preview.capacity), int(preview.open_after), int(preview.capacity)], 14, UI.INK))
	body.add_child(d._label("調査・保存済み設定・測定結果を受注履歴に残します。", 14, UI.MUTED))
	_error(d, body, str(w.get("closeout_error", "")))
	var back: Button = d._primary("作業を続ける", func(): w.closeout_open = false; w.closeout_error = ""; w.closeout_focus = "CloseoutOpen"; d._refresh_receipt())
	back.name = "CloseoutContinue"; footer.add_child(back)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(spacer)
	var confirm: Button = d._button("中止・¥%s を精算" % d._money(preview.get("cash_cost", preview.get("costs", 0))), _submit.bind(d, preview.duplicate(true)))
	confirm.name = "CloseoutConfirm"; confirm.add_theme_color_override("font_color", UI.RED); footer.add_child(confirm)
	if not str(w.get("closeout_focus", "")).is_empty():
		_focus.call_deferred(d, str(w.closeout_focus)); w.closeout_focus = ""
	return true

static func add_action(d, body: VBoxContainer) -> void:
	var g = d.game
	if not g.has_method("contract_closeout_preview"): return
	var preview: Dictionary = g.contract_closeout_preview()
	if not bool(preview.get("available", false)): return
	var open: Button = d._button("案件の中止を検討…", func():
		d.widgets.receipt.closeout_id = str(preview.id)
		d.widgets.receipt.closeout_open = true
		d.widgets.receipt.closeout_error = ""
		d.widgets.receipt.closeout_focus = "CloseoutContinue"
		d._refresh_receipt()
	)
	open.name = "CloseoutOpen"; open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; body.add_child(open)
	if str(d.widgets.receipt.get("closeout_focus", "")) == "CloseoutOpen":
		d.widgets.receipt.closeout_focus = ""; _focus.call_deferred(d, "CloseoutOpen")

static func _focus(d, id: String) -> void:
	for _frame in 3: await d.get_tree().process_frame
	if not is_instance_valid(d) or d.current_app != "receipt" or not d.windows.has("receipt"): return
	var action := d.windows.receipt.find_child(id, true, false) as Control
	var error := d.windows.receipt.find_child("CloseoutError", true, false) as Control
	if error != null and error.is_visible_in_tree():
		var parent := error.get_parent()
		while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
		if parent is ScrollContainer: parent.ensure_control_visible(error)
	if action != null and action.is_visible_in_tree(): action.grab_focus()

static func _numbers(d, body: VBoxContainer, data: Dictionary) -> void:
	var grid := GridContainer.new(); grid.name = "CloseoutNumbers"; grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24); grid.add_theme_constant_override("v_separation", 10); body.add_child(grid)
	var rows := [
		["報酬", "¥%s → ¥0" % d._money(data.get("fee_forgone", 0))],
		["経費", "¥%s" % d._money(data.get("costs", 0))],
		["現金", "¥%s → ¥%s" % [d._money(data.get("cash_before", d.game.state.cash)), d._money(data.get("cash_after", int(d.game.state.cash) - int(data.get("cash_cost", data.get("costs", 0)))))]],
		["顧客満足度", "%d → %d" % [int(data.get("satisfaction_before", 70)), int(data.get("satisfaction_after", 70))]],
		["信用", "%d → %d" % [int(data.get("credit_before", 0)), int(data.get("credit_after", 0))]]
	]
	for row in rows:
		var label: Label = d._label(str(row[0]), 15, UI.MUTED); label.autowrap_mode = TextServer.AUTOWRAP_OFF; grid.add_child(label)
		var value: Label = d._label(str(row[1]), 18, UI.INK); value.name = "CloseoutValue_" + str(row[0]); value.autowrap_mode = TextServer.AUTOWRAP_OFF; value.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.add_child(value)

static func _error(d, body: VBoxContainer, message: String) -> void:
	if message.is_empty(): return
	var label: Label = d._label(message, 14, UI.RED); label.name = "CloseoutError"; body.add_child(label)

static func _submit(d, displayed: Dictionary) -> void:
	var now: Dictionary = d.game.contract_closeout_preview()
	var w: Dictionary = d.widgets.receipt
	for field in ["id", "fee_forgone", "costs", "cash_cost", "cash_before", "satisfaction_before", "satisfaction_after", "credit_before", "credit_after"]:
		if now.get(field) != displayed.get(field):
			w.closeout_error = "条件が変わりました。金額と顧客評価を確認してください。"; w.closeout_focus = "CloseoutContinue"; d._refresh_receipt(); return
	if not bool(now.get("available", false)): w.closeout_open = false; d._refresh_receipt(); return
	if not d._save_session(false): return
	d.switching_target = true
	if not d.game.cancel_current_contract():
		d.switching_target = false
		w.closeout_error = "保存失敗。契約・費用・調査を保持しています。再試行できます。"
		w.closeout_focus = "CloseoutConfirm"
		d._refresh_receipt(); return
	d._reload_contract_session()
	d._show_app("receipt")

static func _result(d, body: VBoxContainer, footer: HBoxContainer, receipt: Dictionary) -> void:
	var title: Label = d._label("中止・未完了", 27, UI.WARNING); title.name = "CloseoutResult"; body.add_child(title)
	body.add_child(d._label("DAY %02d の精算" % int(receipt.get("day", 0)), 14, UI.MUTED))
	body.add_child(d._label(str(receipt.get("client", "")) + " / " + str(receipt.get("title", "")), 17))
	_numbers(d, body, receipt)
	body.add_child(d._label("請求 ¥0  ·  完了件数 +0  ·  経験値 +0", 14, UI.MUTED))
	add_archive(d, body, receipt)
	body.add_child(d._label("再受注は翌日以降の新規受注で確認できます。", 14, UI.MUTED))
	var next: Button = d._primary("案件一覧へ", d._contracts); next.name = "CloseoutNext"; footer.add_child(next)
	_focus.call_deferred(d, "CloseoutNext")
	var history: Button = d._button("受注履歴", func(): d._show_app("mail"); d.widgets.mail.folder = "history"; d.widgets.mail.reading = false; d._refresh_mail())
	history.name = "CloseoutHistory"; footer.add_child(history)

static func add_archive(d, body: VBoxContainer, receipt: Dictionary) -> void:
	var records: VBoxContainer = d._disclosure(body, "保存した調査・設定を確認")
	records.get_parent().get_child(records.get_index() - 1).name = "CloseoutArchiveToggle"
	var archive: Dictionary = d.game.state.get("contract_closeouts", {}).get(str(receipt.get("archived_context", receipt.get("id", ""))), {})
	var text := TextEdit.new(); text.name = "CloseoutArchive"; text.editable = false
	text.add_theme_stylebox_override("read_only", UI.style(Color.WHITE, UI.OS_BORDER, 8, 6, 3))
	text.add_theme_color_override("font_readonly_color", UI.INK)
	text.add_theme_color_override("background_color", Color.WHITE)
	text.add_theme_font_override("font", UI.font())
	text.add_theme_font_size_override("font_size", int(13 * float(d.game.settings.get("text_scale", 1.0))))
	text.custom_minimum_size.y = 150; text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = JSON.stringify(archive, "  "); records.add_child(text)
	var toggle := records.get_parent().get_child(records.get_index() - 1) as Button
	toggle.pressed.connect(func():
		if records.visible: _reveal_archive.call_deferred(d, text)
	)

static func _reveal_archive(d, text: Control) -> void:
	for _frame in 3: await d.get_tree().process_frame
	if not is_instance_valid(text) or not text.is_visible_in_tree(): return
	var parent := text.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(text)
