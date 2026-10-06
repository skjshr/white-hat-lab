extends RefCounted
const U = preload("res://scripts/investigation_ui.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Canvas = preload("res://scripts/saas_session_canvas.gd")
const KIND := "advanced-saas-response"
const INK = Color("283139")
const MUTED = Color("6b7781")

static func render(d, parent: Node, n: Dictionary) -> void:
	var source: Dictionary = n.get("session_case", {}); var sessions: Array = source.get("sessions", [])
	var s := U.state(d, KIND); var selected_id := str(s.get("selected_session", ""))
	var selected := _session(sessions, selected_id)
	var frame := PanelContainer.new(); frame.add_theme_stylebox_override("panel", UI.style(Color.WHITE, Color("d6dce0"), 12, 10, 1)); parent.add_child(frame)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation", 8); frame.add_child(body)
	var title := U.row(body); _label(title, "IDENTITY / 接続券", 18)
	_label(title, "対応 %d分" % int(n.get("elapsed_minutes", 0)), 13, MUTED)
	var next := int(n.get("next_event_minute", -1))
	if next >= 0: _label(title, "次の同期 %d分" % next, 13, MUTED)
	var copies: int = n.get("egress", {}).get("exported_rows", []).size()
	_label(title, "延べ送信 %d行" % copies, 13, UI.RED if copies > 0 else MUTED)
	var global := U.row(body)
	_button(global, "監査記録を取得 · 2分", "SaasCollectAudit", _send.bind(d, "collect_audit", {}))
	_button(global, "すべての券を失効 · 2分", "SaasRevokeAllConnections", _send.bind(d, "revoke_all_connections", {}))
	if not selected.is_empty():
		var target := U.row(body)
		_label(target, "選択 " + selected_id + " / " + str(selected.get("device", "")), 15)
		var state := "○ 発行済み" if bool(selected.get("active", false)) else "× 失効済み"
		_label(target, state, 13, MUTED)
		var actions := U.row(body)
		_button(actions, "発行原本", "SaasOpenSessionOriginal", _open_evidence.bind(d, "original"))
		_button(actions, "要求内容を調査 · 1分", "SaasInspectConnection", _send.bind(d, "inspect_connection", {"session_id": selected_id}))
		_button(actions, "この券を試す · 1分", "SaasProbeSession", _send.bind(d, "probe_session", {"session_id": selected_id}))
		var revoke := _button(actions, "この券を失効 · 2分", "SaasRevokeConnection", _send.bind(d, "revoke_connection", {"session_id": selected_id}))
		revoke.disabled = not bool(selected.get("active", false))
		var purpose := str(selected.get("purpose", ""))
		if purpose in ["billing", "aggregation"]:
			var reissue := _button(actions, ("請求券" if purpose == "billing" else "集計券") + "を再発行 · 2分", "SaasReissueConnection", _send.bind(d, "reissue_connection", {"purpose": purpose}))
			reissue.disabled = bool(selected.get("active", false))
		if purpose == "billing": _button(actions, "請求デスクへ", "SaasOpenBilling", U.choose.bind(d, KIND, "tab", "billing"))
		var last: Dictionary = selected.get("latest_probe", {})
		if not last.is_empty():
			var response := U.row(body); _label(response, _measurement(n, last) + " · " + str(last.get("id", "")), 14, MUTED)
			_button(response, "実測原文", "SaasOpenSessionProbe", _open_evidence.bind(d, "probe"))
		if not selected.get("latest_inspection", {}).is_empty(): _button(actions, "要求記録を開く", "SaasOpenSessionHistory", _open_evidence.bind(d, "history"))
	else: _label(body, "接続券を選択", 14, MUTED)
	if not selected.is_empty(): _evidence(d, body, n, selected)
	var shown: Array = []
	for session in sessions:
		var inspection: Dictionary = session.get("latest_inspection", {}); var probe: Dictionary = session.get("latest_probe", {})
		var observed := inspection if not inspection.is_empty() else probe
		shown.append({"id": str(session.get("id", "")), "device": str(session.get("device", "?")), "issued_at": str(session.get("issued_at", "?")), "active": bool(session.get("active", false)), "approval": _approval(n, session), "destination": _destination(observed), "destination_kind": str(observed.get("data", {}).get("destination", "")), "read_rows": int(inspection.get("data", {}).get("read_rows", -1)), "status": int(probe.get("status", 0)), "fresh": _fresh(n, probe), "measurement": _measurement(n, probe)})
	var consent: Dictionary = source.get("consent", {}); var chart := Canvas.new(); body.add_child(chart); var app_name := ""
	for app in n.get("apps", []):
		if str(app.get("id", "")) == str(consent.get("app_id", "")): app_name = str(app.get("publisher", app.get("label", "")))
	chart.configure({"app": str(consent.get("app_id", "")), "label": app_name, "approval": str(consent.get("approved_change", "")) + " · " + str(consent.get("approved_by", "")), "sessions": shown}, float(d.game.settings.get("text_scale", 1.0)), selected_id, select.bind(d))
	if copies > 0: _label(body, "▤ 外部に残るコピー · 延べ %d行" % copies, 14, UI.RED)
	var schedule := U.row(body)
	for item in source.get("schedule", []):
		var status := str(item.get("status", "scheduled"))
		var marker := "◇" if status == "scheduled" else "×" if status == "blocked" else "↑"
		_label(schedule, "%s %d分 · %s" % [marker, int(item.get("due_minute", 0)), "予定" if status == "scheduled" else "拒否" if status == "blocked" else "%d行" % int(item.get("row_count", 0))], 13, MUTED)

static func _label(parent: Node, text: String, points: int = 14, color: Color = INK) -> Label:
	return U.label(parent, text, points, color, not parent is HFlowContainer)

static func _button(parent: Node, text: String, id: String, action: Callable) -> Button:
	var button := U.button(parent, text, id, action)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, INK)
	for state in ["hover", "pressed", "hover_pressed"]: button.add_theme_stylebox_override(state, UI.style(Color("e8f0f5"), Color("7094aa"), 8, 6, 2))
	return button

static func select(id: String, d) -> void:
	var s := U.state(d, KIND); s.selected_session = id; s.session_evidence = ""; s.erase("open_record")
	d.widgets.advanced.next_scroll = 0; d._save_session(false); d._refresh_advanced.call_deferred()

static func _session(sessions: Array, id: String) -> Dictionary:
	for session in sessions:
		if str(session.get("id", "")) == id: return session
	return {}

static func _record(n: Dictionary, id: String) -> Dictionary:
	for record in n.get("records", []):
		if str(record.get("id", "")) == id: return record
	return {}

static func _fresh(n: Dictionary, record: Dictionary) -> bool:
	return not record.is_empty() and int(record.get("world_revision", -1)) == int(n.get("world_revision", 0))

static func _measurement(n: Dictionary, record: Dictionary) -> String:
	if record.is_empty(): return "? 未実測"
	var code := int(record.get("status", 0))
	return ("実測 " if _fresh(n, record) else "過去 ") + ("× " if code >= 400 else "✓ ") + str(code)

static func _approval(n: Dictionary, session: Dictionary) -> String:
	var original := _record(n, str(session.get("issued_record_id", "")))
	if original.is_empty(): return "? 発行原本"
	var data: Dictionary = original.get("data", {})
	var approved := str(data.get("approved_change", ""))
	if str(original.get("action", "")) == "reissue_connection": return "↻ " + str(n.get("session_case", {}).get("consent", {}).get("approved_change", ""))
	return "✓ " + approved if not approved.is_empty() and approved != "none" else "— 承認記載なし"

static func _destination(inspection: Dictionary) -> String:
	if inspection.is_empty(): return ""
	var data: Dictionary = inspection.get("data", {})
	var destination := str(data.get("destination", ""))
	if destination in ["", "unknown"]: return ""
	if destination.begins_with("invoice/"): return "請求 " + destination.trim_prefix("invoice/")
	return str({"billing": "顧客請求", "customer-billing": "顧客請求", "aggregation": "社内集計", "internal-aggregate": "社内集計", "internal-aggregation": "社内集計", "external-storage": "外部保存"}.get(destination, destination))

static func _open_evidence(d, part: String) -> void:
	var s := U.state(d, KIND); s.session_evidence = "" if str(s.get("session_evidence", "")) == part else part; s.session_raw = false
	d._save_session(false); d._refresh_advanced.call_deferred()

static func _evidence(d, parent: Node, n: Dictionary, session: Dictionary) -> void:
	var s := U.state(d, KIND); var part := str(s.get("session_evidence", "")); var record: Dictionary = {}
	if part == "original": record = _record(n, str(session.get("issued_record_id", "")))
	elif part == "history": record = session.get("latest_inspection", {})
	elif part == "probe": record = session.get("latest_probe", {})
	if record.is_empty(): return
	var paper := PanelContainer.new(); paper.name = "SaasSessionEvidence"; paper.add_theme_stylebox_override("panel", UI.style(Color("fbfaf3"), Color("c8c5b7"), 12, 9, 1)); parent.add_child(paper)
	var content := VBoxContainer.new(); paper.add_child(content)
	var header := U.row(content); _label(header, ("発行原本" if part == "original" else "要求内容" if part == "history" else "接続実測") + " / " + str(record.get("id", "")), 15)
	_button(header, "閉じる", "SaasCloseSessionEvidence", _open_evidence.bind(d, part))
	var facts := U.row(content)
	_label(facts, str(session.get("id", "")) + " · " + str(session.get("issued_at", "")) + " · " + str(session.get("device", "")), 14)
	if part == "original":
		_label(content, _approval(n, session), 14)
		var destination := str(record.get("data", {}).get("destination", ""))
		_label(content, "発行時の要求先 → " + (_destination(record) if not destination.is_empty() and destination != "unknown" else "記載なし"), 14, MUTED)
	else:
		_label(content, str(record.get("detail", "")), 14)
		if part == "history":
			_label(content, "→ " + _destination(record), 14)
			if record.get("data", {}).has("read_rows"): _label(content, "要求 %d行" % int(record.data.read_rows), 14, MUTED)
		else: _label(content, _measurement(n, record), 14)
	_button(content, "▾ 原文" if bool(s.get("session_raw", false)) else "▸ 原文", "SaasSessionShowRaw", U.choose.bind(d, KIND, "session_raw", not bool(s.get("session_raw", false))))
	if bool(s.get("session_raw", false)):
		var raw := TextEdit.new(); raw.name = "SaasSessionRaw"; raw.editable = false; raw.text = JSON.stringify(record, "\t")
		raw.custom_minimum_size.y = 140 * float(d.game.settings.get("text_scale", 1.0)); raw.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; U.text_style(raw); content.add_child(raw)

static func _send(d, action: String, args: Dictionary) -> void:
	var result := U.send(d, KIND, action, args); var s := U.state(d, KIND)
	if bool(result.get("ok", false)):
		if action == "inspect_connection": s.session_evidence = ""; s.session_raw = false
		elif action == "reissue_connection":
			for session in d.game.advanced_view().get("saas", {}).get("session_case", {}).get("sessions", []):
				if str(session.get("purpose", "")) == str(args.get("purpose", "")) and bool(session.get("active", false)): s.selected_session = str(session.get("id", ""))
			s.session_evidence = ""
	d._save_session(false)
