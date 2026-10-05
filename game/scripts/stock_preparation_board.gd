extends RefCounted
## A projection of real serials, stock positions, and recorded validation.
## Only explicit button actions enter the transactional stock APIs.
const M = preload("res://scripts/management_ui.gd")
const STOCK = preload("res://scripts/customer_stock.gd")
const FLOW = preload("res://scripts/stock_preparation_flow.gd")

static func project(game, selected: String) -> Dictionary:
	var contract: Dictionary = game.state.get("contract", {})
	var requirement: Dictionary = game._customer_requirement()
	var contract_id := str(game.state.get("current_contract_id", ""))
	var target := int(game.state.get("target_index", 0))
	var units: Array = []
	var assigned: Dictionary = {}
	for raw in game.customer_stock_units():
		var unit: Dictionary = raw.duplicate(true)
		var bound := str(unit.get("contract_id", "")) == contract_id and int(unit.get("target_index", -1)) == target
		if bound: assigned = unit
		# Retired customer hardware stays in the serial ledger. The bench shows
		# current work and inventory still physically within the company.
		if str(unit.get("status", "")) in ["shipping", "delivered"] and not bound: continue
		unit["owner"] = str(contract.get("client", "")) if bound else "別案件" if not str(unit.get("contract_id", "")).is_empty() else ""
		units.append(unit)
	if not units.any(func(unit): return str(unit.id) == selected) and not assigned.is_empty(): selected = str(assigned.id)
	var chosen: Dictionary = {}
	for unit in units:
		if str(unit.id) == selected: chosen = unit
	var checks: Array = game.state.get("checks", [])
	var current := bool(game.state.get("inspected", false)) and int(game.state.get("validated_revision", -1)) == int(game.state.get("revision", 0)) and not checks.is_empty()
	var passed := 0; var total := 0
	for check in checks:
		if bool(check.get("hardware", false)): continue
		total += 1
		if bool(check.get("passed", false)): passed += 1
	var active: bool = bool(game.state.get("accepted", false)) and not game.current_done() and not requirement.is_empty()
	return {"units":units,"selected":selected,"chosen":chosen,"assigned":assigned,"client":str(contract.get("client", "")),"target":str(contract.get("title", "")),"model":str(STOCK.product(str(requirement.get("sku", ""))).get("model", "")),"icon":str(STOCK.product(str(requirement.get("sku", ""))).get("icon", "stock_gateway")),"has_requirement":active,"cash":int(game.state.get("cash", 0)),"current":current,"passed":passed,"total":total,"revision":int(game.state.get("revision", 0))}

static func _label(ui, parent: Node, text: String, size := 14) -> Label:
	var label: Label = ui._label(text, size, M.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

static func _button(ui, parent: Node, title: String, id: String, action: Callable) -> Button:
	var button: Button = ui._button(title, action); button.name = id
	button.custom_minimum_size.y = 36 * ui.text_scale
	M.button(button); parent.add_child(button)
	return button

static func render(ui, parent: Node, game) -> void:
	var data := project(game, str(ui.get_meta("stock_prep_selection", "")))
	var heading := _label(ui, parent, "", 17); heading.name = "PreparationContext"
	var flow = FLOW.new(); parent.add_child(flow); flow.setup(ui, data)
	flow.unit_selected.connect(func(id: String):
		ui.set_meta("stock_prep_selection", id); ui.set_meta("stock_prep_feedback", ""); refresh(ui))
	var facts := _label(ui, parent, "", 13); facts.name = "PreparationFacts"
	var actions := VBoxContainer.new(); actions.name = "PreparationActions"; actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_theme_constant_override("separation", 6); ui.modal_footer.add_child(actions)
	var feedback := _label(ui, actions, "", 13); feedback.name = "PreparationFeedback"
	var row := HFlowContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("h_separation", 8); row.add_theme_constant_override("v_separation", 5); actions.add_child(row)
	_button(ui, row, "机へ接続", "PreparationPrepare", func(): _act(ui, game, "prepare_customer_stock", "● 選択した機材を設定台に接続しました。", "PreparationPrepare"))
	_button(ui, row, "端末を開く", "PreparationTerminal", func(): _desktop(ui, "terminal"))
	_button(ui, row, "検証を開く", "PreparationVerify", func(): _desktop(ui, "verify"))
	var ship := _button(ui, row, "顧客へ発送", "PreparationShip", func(): _act(ui, game, "ship_prepared_customer_stock", "→ 発送しました。顧客の受領を待っています。", "PreparationShip")); M.button(ship, "primary")
	_button(ui, row, "完了・請求", "PreparationReceipt", func(): _desktop(ui, "receipt"))
	refresh(ui)

static func _desktop(ui, app: String) -> void:
	ui.open_panel("terminal")
	if is_instance_valid(ui.desktop): ui.desktop._show_app(app)

static func _error(code: String) -> String:
	if code == "assigned": code = "staged"
	return {"save":"保存できませんでした。位置と設定を戻しました。保存先を確認して再試行してください。","sku":"この案件は別の型式です。依頼された機材を選んでください。","contract":"この機材は現在の対象に割り当てられません。案件と割当を確認してください。","checks":"発送できません。設定を適用し、検証で最新の業務・保護チェックを通してください。","held":"別の機材を持っています。先に3Dオフィスで置いてください。","staged":"設定台は使用中です。接続中の機材を確認してください。","status":"この位置からは操作できません。入荷と機材の状態を確認してください。","unknown":"機材が見つかりません。別のシリアルを選んでください。"}.get(code, "操作できませんでした。機材と案件の状態を確認してください。")

static func _act(ui, game, method: String, success: String, focus_id: String) -> void:
	var data := project(game, str(ui.get_meta("stock_prep_selection", "")))
	var result: Dictionary = game.call(method, str(data.selected))
	ui.set_meta("stock_prep_feedback", success if bool(result.get("ok", false)) else "! " + _error(str(result.get("error", "unknown"))))
	ui.set_meta("stock_prep_feedback_signature", _feedback_signature(project(game, str(data.selected))))
	refresh(ui)
	var focus: Control = ui.modal_footer.find_child(focus_id, true, false)
	if is_instance_valid(focus) and focus is BaseButton and focus.disabled: focus = ui.modal_footer.find_child("PreparationTerminal" if method == "prepare_customer_stock" else "PreparationReceipt", true, false)
	if is_instance_valid(focus): focus.grab_focus()

static func _feedback_signature(data: Dictionary) -> String:
	return JSON.stringify([data.selected, data.chosen.get("status", ""), data.revision, data.current, data.passed, data.total])

static func refresh(ui) -> void:
	if not is_instance_valid(ui.modal): return
	var flow = ui.modal.find_child("StockPreparationFlow", true, false)
	if not is_instance_valid(flow): return
	var game = ui._game()
	var data := project(game, str(ui.get_meta("stock_prep_selection", "")))
	var feedback_signature := str(ui.get_meta("stock_prep_feedback_signature", ""))
	if not feedback_signature.is_empty() and feedback_signature != _feedback_signature(data):
		ui.set_meta("stock_prep_feedback", ""); ui.set_meta("stock_prep_feedback_signature", "")
	flow.set_view(data)
	var heading: Label = ui.modal.find_child("PreparationContext", true, false)
	heading.text = "%s · %s · 現金 ¥%d" % [data.client, data.model, data.cash] if data.has_requirement else "✓ 納入済 · %s · %s · 現金 ¥%d" % [data.client,data.model,data.cash] if str(data.assigned.get("status", "")) == "delivered" else "納入案件を選択してください。現金 ¥%d" % data.cash
	var facts: Label = ui.modal.find_child("PreparationFacts", true, false)
	var selected: Dictionary = data.chosen
	var validation := "未検証" if data.total == 0 else ("✓ 最新" if data.current and data.passed == data.total else "! 要確認" if data.current else "↻ 再検証") + " %d/%d" % [data.passed,data.total]
	facts.text = "%s  /  検証 %s  /  設定 rev.%d" % [str(selected.get("serial", "機材を選択")), validation, data.revision]
	var active := bool(data.has_requirement)
	var status := str(selected.get("status", ""))
	var bound := not selected.is_empty() and str(selected.get("contract_id", "")) == str(game.state.get("current_contract_id", "")) and int(selected.get("target_index", -1)) == int(game.state.get("target_index", 0))
	for pair in [["PreparationPrepare",active and status in ["ready","stored","carried"]],["PreparationTerminal",active and bound and status in ["staged","delivered"]],["PreparationVerify",active and bound and status in ["staged","delivered"]],["PreparationShip",active and bound and status in ["staged","carried"]],["PreparationReceipt",bound and status == "delivered"]]:
		var button: Button = ui.modal_footer.find_child(pair[0], true, false)
		button.disabled = not bool(pair[1])
	var feedback: Label = ui.modal_footer.find_child("PreparationFeedback", true, false)
	feedback.text = str(ui.get_meta("stock_prep_feedback", ""))
	feedback.visible = not feedback.text.is_empty()
