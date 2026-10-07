extends RefCounted
const M = preload("res://scripts/management_ui.gd")
const COPY = preload("res://scripts/ui_theme.gd")
const MODEL = preload("res://scripts/care_portfolio_view.gd")
const SERVICE = preload("res://scripts/care_service_canvas.gd")
const BALANCE = preload("res://scripts/care_balance_canvas.gd")

static func _label(ui, parent: Node, text: String, size: int = 14) -> Label:
	var label: Label = ui._label(text, size, M.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent is HFlowContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label

static func _button(ui, parent: Node, text: String, action: Callable, id: String, role: String = "secondary", selected: bool = false) -> Button:
	var button: Button = ui._button(text, action); button.name = id
	M.button(button, role, selected); parent.add_child(button)
	return button

static func _flow(parent: Node) -> HFlowContainer:
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation", 8); row.add_theme_constant_override("v_separation", 5)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row); return row

static func _signature(ui, g, model: Dictionary) -> String:
	var stable := model.duplicate(true)
	for row in stable.get("clients", []): row.erase("remaining")
	var members := []
	for member in g.team_members(): members.append([str(member.id), str(g.staff_availability(str(member.id), "maintenance"))])
	return JSON.stringify([stable, members, str(ui.get_meta("company_client", "")), g.state.get("market_leads", []), g.state.get("offers", [])]).sha256_text()

static func build(ui, g) -> void:
	for parent in [ui.modal_body, ui.modal_footer]:
		for child in parent.get_children():
			if str(child.name) in ["CarePortfolio", "CareActions"]: parent.remove_child(child); child.queue_free()
	var model: Dictionary = MODEL.snapshot(g)
	var root := VBoxContainer.new(); root.name = "CarePortfolio"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	root.theme = M.theme(float(ui.text_scale))
	root.theme.set_color("font_color", "TooltipLabel", M.INK)
	root.theme.set_stylebox("panel", "TooltipPanel", M.surface(M.PAPER, 8, true))
	ui.modal_body.add_child(root)
	var balance := BALANCE.new(); balance.name = "CareBalance"; root.add_child(balance); balance.configure(model, float(ui.text_scale))
	balance.tooltip_text = "当日の保守収入 − 保守原価 − 全社員の給与。\n単発案件の利益・採用費・設備費は日締めで確認。"
	var clients: Array = model.get("clients", [])
	var selected := str(ui.get_meta("company_client", ""))
	if not clients.any(func(row): return str(row.client) == selected):
		selected = str(clients[0].client) if not clients.is_empty() else ""
		ui.set_meta("company_client", selected)
	var tabs := _flow(root); tabs.name = "CareClients"
	var current := {}
	for row in clients:
		var client := str(row.client)
		var button := _button(ui, tabs, client, func():
			ui.set_meta("company_client", client); build(ui, g)
		, "CompanyClient_" + client.sha256_text().left(10), "tab", selected == client)
		button.tooltip_text = str(row.get("job_status", "unknown"))
		if selected == client: current = row
	if current.is_empty():
		_label(ui, root, "保守契約なし · 納品した対象を、毎日の点検へ", 17)
	else:
		var canvas := SERVICE.new(); canvas.name = "CareService"; root.add_child(canvas); canvas.configure(current, float(ui.text_scale))
		_owner(ui, root, g, current)
		var once := _flow(root)
		_label(ui, once, "今回だけ任せる", 13)
		for member in g.team_members():
			var id := str(member.id)
			var delegate := _button(ui, once, str(member.name), func():
				if not g.assign_maintenance(selected, id): ui._management_feedback("点検を開始できませんでした。担当の状態と保存先を確認して再試行できます。")
			, "Maintenance_" + id)
			var unavailable := str(g.staff_availability(id, "maintenance"))
			delegate.disabled = not g.can_run_maintenance(selected) or not unavailable.is_empty()
			delegate.tooltip_text = unavailable if not unavailable.is_empty() else "今日の点検を任せる。定期担当は変更しません。"
		_actions(ui, g, current)
	_opportunities(ui, root, g, model)
	ui.controls.care_portfolio_signature = _signature(ui, g, model)

static func _owner(ui, root: Node, g, row: Dictionary) -> void:
	var client := str(row.client)
	var controls := _flow(root)
	_label(ui, controls, "定期担当", 14)
	var picker := OptionButton.new(); picker.name = "CareOwner_" + client.sha256_text().left(10)
	picker.custom_minimum_size.x = 180 * float(ui.text_scale); M.field(picker)
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.add_item("毎回手動"); picker.set_item_metadata(0, "")
	var owner := str(row.get("owner", "")); var found := owner.is_empty()
	for member in g.maintenance_owner_candidates():
		picker.add_item(str(member.name)); picker.set_item_metadata(picker.item_count - 1, str(member.id))
		if str(member.id) == owner: picker.select(picker.item_count - 1); found = true
	if not found:
		picker.add_item("担当不在"); picker.select(picker.item_count - 1); picker.set_item_disabled(picker.item_count - 1, true)
	picker.tooltip_text = "担当者が勤務中で空いていれば、毎日の点検を自動で開始。\n実行中の仕事の担当は変更しません。"
	picker.item_selected.connect(func(index):
		if not g.set_maintenance_owner(client, str(picker.get_item_metadata(index))):
			ui._management_feedback("定期担当を保存できませんでした。元の担当を保持しています。")
			build(ui, g)
	)
	controls.add_child(picker)
	_label(ui, controls, "日次点検 / %d対象" % row.get("scope", []).size() if bool(row.get("scope_known", false)) else "旧契約 · 対象記録なし", 13)

static func _actions(ui, g, row: Dictionary) -> void:
	var client := str(row.client); var suffix := client.sha256_text().left(10)
	var actions := _flow(ui.modal_footer); actions.name = "CareActions"
	var incident: Dictionary = row.get("incident", {})
	var state := str(incident.get("status", ""))
	if state in ["detected", "working"]:
		var ticket := _button(ui, actions, "障害を調べる", func(): ui._open_maintenance_incident(client), "CareIncident_" + suffix, "primary")
		var reason := str(g.maintenance_incident_reason(client)); ticket.disabled = not reason.is_empty(); ticket.tooltip_text = reason
	var start := _button(ui, actions, "修復後の再点検" if state == "recheck" else "自分で点検", func():
		if not g.run_maintenance(client): ui._management_feedback("点検できませんでした。保存された状態を保持しています。")
	, "CareSelfCheck_" + suffix, "primary" if state not in ["detected", "working"] else "secondary")
	start.disabled = not g.can_run_maintenance(client)
	var result := _button(ui, actions, "点検記録", func(): ui._show_maintenance_result(client), "CareResult_" + suffix)
	result.disabled = not bool(row.get("result_known", false)) or str(row.get("result", "")).is_empty()
	_button(ui, actions, "今日の仕事へ", func():
		ui.operations_choices.view = "today"
		var job: Dictionary = g._maintenance_job_for(client)
		ui.operations_choices.workday_selected = "maintenance:" + str(job.get("id", ""))
		ui.open_panel("board")
	, "CareWorkday")

static func eligible_offers(g) -> Array:
	var rows := []; var clients := {}
	for raw in g.state.get("offers", []):
		if not raw is Dictionary: continue
		var id := str(raw.get("id", "")); var client := str(raw.get("client", ""))
		if id.is_empty() or client.is_empty() or clients.has(client): continue
		if not bool(raw.get("market_available", false)): continue
		if not bool(raw.get("unlocked", false)) or id in g.state.get("completed_ids", []) or g.state.get("contract_contexts", {}).has(id): continue
		var agreement: Dictionary = g.state.get("care_agreements", {}).get(client, {})
		if bool(agreement.get("active", false)) or bool(agreement.get("pending", false)): continue
		if not g.care_case_reason(raw).is_empty(): continue
		var terms: Dictionary = g.care_terms(client)
		rows.append({"id":id, "client":client, "title":str(raw.get("title", "")), "fee":int(terms.fee), "net":int(terms.net), "reason":str(terms.reason)})
		clients[client] = true
	return rows

static func open_offer(ui, g, id: String) -> void:
	var available := false
	for row in eligible_offers(g):
		if str(row.id) == id and str(row.reason).is_empty(): available = true; break
	if not available:
		ui._management_feedback("相談の条件が変わりました。現在の保守枠と案件を確認してください。")
		return
	if not g.set_offer_plan("care", id):
		ui._management_feedback("保守付きの見積条件を保存できませんでした。再試行できます。")
		return
	ui.board_selected_id = id; ui.open_panel("sales")

static func _opportunities(ui, root: Node, g, model: Dictionary) -> void:
	root.add_child(M.rule())
	var line := _flow(root)
	var reserved := int(model.get("reserved_count", -1)); var capacity := int(model.get("capacity", -1))
	_label(ui, line, "保守を増やす · %s / %s社" % [str(reserved) if reserved >= 0 else "?", str(capacity) if capacity >= 0 else "?"], 15)
	var offers := eligible_offers(g)
	for offer in offers:
		var button := _button(ui, root, "%s · %s   → 日額 ¥%d" % [str(offer.client), str(offer.title), int(offer.fee)], func(): open_offer(ui, g, str(offer.id)), "CareOffer_" + str(offer.id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not str(offer.reason).is_empty()
		button.tooltip_text = str(offer.reason) if button.disabled else "保守付きの見積を開く。まだ受注しません。\n納品後に日次点検を開始。点検成功時の原価差引 ¥%d / 日。" % int(offer.net)
	if offers.is_empty(): _label(ui, root, "今日の追加相談なし", 13)
	_button(ui, line, "すべての相談", func(): ui._open_cycle_other_work(), "CareAllOffers", "quiet")

static func refresh_live(ui, g) -> void:
	var model: Dictionary = MODEL.snapshot(g)
	var signature := _signature(ui, g, model)
	if str(ui.controls.get("care_portfolio_signature", "")) != signature:
		var scroll: int = ui.modal_scroll.scroll_vertical
		var focus: Control = ui.get_viewport().gui_get_focus_owner()
		var name := str(focus.name) if is_instance_valid(focus) and ui.modal.is_ancestor_of(focus) else ""
		build(ui, g)
		ui.modal_scroll.set_deferred("scroll_vertical", scroll)
		if not name.is_empty():
			var restored = ui.modal.find_child(name, true, false)
			if restored is Control and restored.focus_mode != Control.FOCUS_NONE: _restore_focus.call_deferred(weakref(restored))
	else:
		var canvas = ui.modal_body.find_child("CareService", true, false)
		if is_instance_valid(canvas):
			for row in model.get("clients", []):
					if str(row.client) == str(ui.get_meta("company_client", "")): canvas.configure(row, float(ui.text_scale)); break

static func _restore_focus(target_ref: WeakRef) -> void:
	var target = target_ref.get_ref()
	if target is Control and target.is_inside_tree() and target.is_visible_in_tree() and not target.is_queued_for_deletion(): target.grab_focus()
