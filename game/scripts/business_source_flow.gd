extends RefCounted
class_name BusinessSourceFlow

## Read-only projection and compact renderer for the actual business API response.
const UI = preload("res://scripts/ui_theme.gd")
const Glyph = preload("res://scripts/service_glyph.gd")
const BUSINESS = preload("res://scripts/business_workspace.gd")

const PURPLE := Color("714b67")
const INK := Color("282828")
const MUTED := Color("6b6b6b")
const RED := Color("b42318")
const GREEN := Color("2f7d4a")

static func _payload(response: String) -> Dictionary:
	var text := response.strip_edges()
	if text.is_empty(): return {}
	var separator := text.find("\n\n")
	if separator >= 0: text = text.substr(separator + 2).strip_edges()
	else:
		separator = text.find("\r\n\r\n")
		if separator >= 0: text = text.substr(separator + 4).strip_edges()
	var parser := JSON.new()
	if parser.parse(text) == OK and parser.data is Dictionary: return parser.data
	var first_line := text.get_slice("\n", 0).strip_edges()
	if first_line.begins_with("HTTP/"):
		var parts := first_line.split(" ", false)
		var code := int(parts[1]) if parts.size() > 1 and str(parts[1]).is_valid_int() else 0
		return {"ok":false,"code":code,"error":"http_error","_http_error":true}
	var lower := text.to_lower()
	if lower.begins_with("curl:") or lower.contains("could not resolve host") or lower.contains("connection refused"):
		return {"ok":false,"error":"network","transport_error":true}
	return {"ok":false,"error":"malformed_response","_format_error":true}

static func _data(payload: Dictionary) -> Dictionary:
	var nested: Variant = payload.get("data", {})
	return nested if nested is Dictionary else {}

static func _source_path(view: String, payload: Dictionary, data: Dictionary, storage: Dictionary) -> String:
	if view == "sales":
		if bool(storage.get("enabled", false)) and not str(storage.get("path", "")).is_empty(): return str(storage.get("path", ""))
		return BUSINESS.ORDERS_FILE
	if view == "customers":
		for key in ["customers_source", "customer_source", "customers_path"]:
			var explicit_path := str(data.get(key, ""))
			if not explicit_path.is_empty(): return explicit_path
		if bool(storage.get("enabled", false)) and not str(storage.get("path", "")).is_empty():
			return str(storage.get("path", "")).get_base_dir().path_join("customers.csv")
		return BUSINESS.CUSTOMERS_FILE
	var actual_ledger_source := str(data.get("ledger_source", data.get("source", payload.get("ledger_source", ""))))
	return actual_ledger_source if not actual_ledger_source.is_empty() else BUSINESS.LEDGER_FILE

static func project(view: String, response: String) -> Dictionary:
	var normalized_view := view if view in ["sales", "customers", "accounting"] else "sales"
	var payload := _payload(response)
	var data := _data(payload)
	var storage_value: Variant = payload.get("external_storage", data.get("external_storage", {}))
	var storage: Dictionary = storage_value if storage_value is Dictionary else {}
	var result := {
		"view": normalized_view,
		"visible": bool(storage.get("enabled", false)),
		"fetched": not response.strip_edges().is_empty(),
		"status": "not_fetched",
		"symbol": "?",
		"label": "未取得",
		"host": str(storage.get("host", "")),
		"share": str(storage.get("share", "")),
		"path": _source_path(normalized_view, payload, data, storage),
		"count": 0,
		"count_label": "",
		"error": str(payload.get("error", "")),
		"code": int(payload.get("code", 0)),
		"server": {"symbol":"?","status":"unknown","label":"応答未確認","name":"取得元","detail":""},
		"file": {"symbol":"?","status":"unknown","label":"未確認","name":"対象ファイル","detail":""},
		"business": {"symbol":"?","status":"unknown","label":"未取得","name":{"sales":"受注","customers":"顧客","accounting":"台帳"}.get(normalized_view, "業務結果"),"detail":""},
	}
	if normalized_view == "accounting":
		result.server.name = "業務API"
		result.server.detail = "業務データの取得応答"
	else:
		result.server.name = "共有サーバー"
		result.server.detail = "//%s/%s" % [result.host, result.share] if not str(result.host).is_empty() else "共有サーバー"
	result.file.detail = str(result.path)
	if not bool(result.fetched): return result
	var storage_error := not storage.is_empty() and bool(storage.get("enabled", false)) and not bool(storage.get("ok", false))
	if storage_error or str(payload.get("error", "")) in ["provider_unavailable", "service_unavailable", "storage_denied", "network", "connection_refused"] or bool(payload.get("transport_error", false)):
		result.status = "unavailable"; result.symbol = "×"; result.label = "共有接続不可"
		if str(result.error).is_empty(): result.error = str(storage.get("error", "provider_unavailable"))
		var denied := str(result.error) == "storage_denied"
		if denied: result.label = "共有アクセス拒否"
		result.server = {"symbol":"×","status":"error","label":"アクセス拒否" if denied else "接続不可","name":result.server.name,"detail":result.server.detail}
		result.file = {"symbol":"?","status":"unknown","label":"未確認","name":"対象ファイル","detail":result.path}
		result.business = {"symbol":"?","status":"unknown","label":"未取得","name":result.business.name,"detail":"取得結果なし"}
		return result
	if bool(payload.get("_format_error", false)):
		result.status = "malformed"; result.symbol = "!"; result.label = "形式異常"
		result.server = {"symbol":"✓","status":"ok","label":"応答あり","name":result.server.name,"detail":result.server.detail}
		result.file = {"symbol":"?","status":"unknown","label":"内容未確認","name":"対象ファイル","detail":result.path}
		result.business = {"symbol":"!","status":"error","label":"応答形式異常","name":result.business.name,"detail":"JSONを読み取れません"}
		return result
	var error := str(payload.get("error", ""))
	if error in ["missing_file", "file_missing"]:
		result.status = "missing"; result.symbol = "!"; result.label = "ファイルなし"
		result.server = {"symbol":"✓","status":"ok","label":"応答あり","name":result.server.name,"detail":result.server.detail}
		if normalized_view == "sales":
			var customers_path := _source_path("customers", payload, data, storage)
			result.file = {"symbol":"!","status":"error","label":"必要資料なし","name":"受注・顧客資料","detail":"注文資料または顧客資料のいずれかを確認できません","tooltip":"注文: %s\n顧客: %s" % [result.path, customers_path]}
			result.business = {"symbol":"!","status":"error","label":"資料不足","name":result.business.name,"detail":"API応答だけでは不足ファイルを特定できません"}
		else:
			result.file = {"symbol":"×","status":"error","label":"ファイルなし","name":"対象ファイル","detail":result.path}
			result.business = {"symbol":"!","status":"error","label":"未取得","name":result.business.name,"detail":"ファイルがありません"}
		return result
	if error.begins_with("malformed_") or error in ["duplicate_customer", "invalid", "malformed"]:
		result.status = "malformed"; result.symbol = "!"; result.label = "形式異常"
		result.server = {"symbol":"✓","status":"ok","label":"応答あり","name":result.server.name,"detail":result.server.detail}
		if normalized_view == "sales" and (error.begins_with("malformed_customers") or error == "duplicate_customer"):
			var customer_path := _source_path("customers", payload, data, storage)
			result.file = {"symbol":"✓","status":"ok","label":"読取済","name":"顧客資料","detail":customer_path}
			result.business = {"symbol":"!","status":"error","label":"顧客資料異常","name":result.business.name,"detail":error}
		elif normalized_view == "sales" and error.begins_with("malformed_orders"):
			result.file = {"symbol":"✓","status":"ok","label":"読取済","name":"受注資料","detail":result.path}
			result.business = {"symbol":"!","status":"error","label":"受注資料異常","name":result.business.name,"detail":error}
		else:
			result.file = {"symbol":"✓","status":"ok","label":"読取済","name":"対象ファイル","detail":result.path}
			result.business = {"symbol":"!","status":"error","label":"形式異常","name":result.business.name,"detail":error}
		return result
	if not bool(payload.get("ok", false)):
		result.status = "unavailable"; result.symbol = "×"; result.label = "取得失敗"
		result.server = {"symbol":"×","status":"error","label":"応答エラー","name":result.server.name,"detail":"HTTP %d" % int(result.code) if int(result.code) > 0 else error}
		result.file = {"symbol":"?","status":"unknown","label":"未確認","name":"対象ファイル","detail":result.path}
		result.business = {"symbol":"!","status":"error","label":"取得失敗","name":result.business.name,"detail":error}
		return result
	var rows: Variant
	match normalized_view:
		"sales":
			var orders: Variant = data.get("orders", null)
			var customers: Variant = data.get("customers", null)
			if not orders is Array or not customers is Array:
				result.status = "malformed"; result.symbol = "!"; result.label = "形式異常"; result.error = "malformed_orders_payload"
				result.server = {"symbol":"✓","status":"ok","label":"応答あり","name":result.server.name,"detail":result.server.detail}
				result.file = {"symbol":"?","status":"unknown","label":"内容未確認","name":"対象ファイル","detail":result.path}
				result.business = {"symbol":"!","status":"error","label":"形式異常","name":result.business.name,"detail":result.error}
				return result
			rows = orders
			result.count_label = "受注"
		"customers":
			rows = data.get("customers", null)
			if not rows is Array:
				result.status = "malformed"; result.symbol = "!"; result.label = "形式異常"; result.error = "malformed_customers_payload"
				result.server = {"symbol":"✓","status":"ok","label":"応答あり","name":result.server.name,"detail":result.server.detail}
				result.file = {"symbol":"?","status":"unknown","label":"内容未確認","name":"対象ファイル","detail":result.path}
				result.business = {"symbol":"!","status":"error","label":"形式異常","name":result.business.name,"detail":result.error}
				return result
			result.count_label = "顧客"
		"accounting":
			rows = data.get("ledger", null)
			if not rows is Array:
				result.status = "malformed"; result.symbol = "!"; result.label = "形式異常"; result.error = "malformed_ledger_payload"
				result.server = {"symbol":"✓","status":"ok","label":"応答あり","name":result.server.name,"detail":result.server.detail}
				result.file = {"symbol":"?","status":"unknown","label":"内容未確認","name":"対象ファイル","detail":result.path}
				result.business = {"symbol":"!","status":"error","label":"形式異常","name":result.business.name,"detail":result.error}
				return result
			result.count_label = "明細"
	result.status = "ok"; result.symbol = "✓"; result.label = "取得済"; result.count = rows.size()
	result.server = {"symbol":"✓","status":"ok","label":"応答あり","name":result.server.name,"detail":result.server.detail}
	result.file = {"symbol":"✓","status":"ok","label":"読取済","name":"対象ファイル","detail":result.path}
	result.business = {"symbol":"✓","status":"ok","label":"%d %s" % [int(result.count), str(result.count_label)],"name":result.business.name,"detail":"業務データ取得済"}
	return result

static func _label(d, parent: Node, text: String, size: int, color: Color) -> Label:
	var label: Label = d._label(text, size, color)
	label.add_theme_font_override("font", UI.font(400))
	label.add_theme_font_size_override("font_size", int(size * float(d.game.settings.get("text_scale", 1.0))))
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(label)
	return label

static func render(d, parent: Node, projection: Dictionary, refresh_action: Callable) -> Control:
	if not bool(projection.get("visible", false)): return null
	var frame := PanelContainer.new()
	frame.name = "BusinessSourceFlow"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edge: Color = GREEN if str(projection.get("status", "")) == "ok" else (RED if str(projection.get("status", "")) in ["unavailable", "missing", "malformed"] else Color("b9aeb7"))
	var style := UI.style(Color("faf8fa"), edge, 8, 6, 1)
	frame.add_theme_stylebox_override("panel", style)
	parent.add_child(frame)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	frame.add_child(content)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	content.add_child(top)
	var symbol := str(projection.get("symbol", "?"))
	var label_color: Color = GREEN if str(projection.get("status", "")) == "ok" else (RED if symbol in ["×", "!"] else MUTED)
	var state_label := _label(d, top, "%s %s" % [symbol, str(projection.get("label", "未取得"))], 14, label_color)
	state_label.name = "BusinessSourceStatus"
	state_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var count_text := ""
	if str(projection.get("status", "")) == "ok": count_text = "%d %s" % [int(projection.get("count", 0)), str(projection.get("count_label", "件"))]
	var space := Control.new(); space.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(space)
	if not count_text.is_empty():
		var count_label := _label(d, top, count_text, 14, MUTED)
		count_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var flow := HFlowContainer.new()
	flow.name = "BusinessSourceFlowRoute"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 4)
	content.add_child(flow)
	var server: Dictionary = projection.get("server", {})
	var file: Dictionary = projection.get("file", {})
	var business: Dictionary = projection.get("business", {})
	_stage(d, flow, server, "network", 1)
	Glyph.add_to(flow, "arrow", 18, PURPLE)
	_stage(d, flow, file, "file", 2)
	Glyph.add_to(flow, "arrow", 18, PURPLE)
	_stage(d, flow, business, "process", 3)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	var fetched_label := "前回の取得: 未実行" if not bool(projection.get("fetched", false)) else "前回の取得: %s" % str(projection.get("label", "取得失敗"))
	var fetched := _label(d, footer, fetched_label, 14, MUTED)
	fetched.name = "BusinessSourceLastFetch"
	fetched.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var footer_space := Control.new(); footer_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(footer_space)
	var detail := ""
	if not str(projection.get("error", "")).is_empty(): detail = str(projection.get("error", ""))
	if int(projection.get("code", 0)) > 0: detail += ("  " if not detail.is_empty() else "") + "HTTP " + str(projection.code)
	var details := VBoxContainer.new(); details.name = "BusinessSourceDetails"; details.visible = false; content.add_child(details)
	for info in [str(server.get("detail", "")), str(file.get("tooltip", file.get("detail", ""))), str(business.get("detail", "")), detail]:
		if str(info).is_empty(): continue
		var info_label := _label(d, details, str(info), 14, MUTED)
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_toggle: Button = d._button("詳細", func(): details.visible = not details.visible)
	detail_toggle.name = "BusinessSourceDetailsToggle"; detail_toggle.custom_minimum_size.y = 34
	detail_toggle.add_theme_font_size_override("font_size", int(14 * float(d.game.settings.get("text_scale", 1.0))))
	footer.add_child(detail_toggle)
	var refresh: Button = d._button("更新", refresh_action)
	refresh.name = "BusinessStorageRefresh"
	refresh.custom_minimum_size = Vector2(88, 34)
	refresh.add_theme_font_size_override("font_size", int(14 * float(d.game.settings.get("text_scale", 1.0))))
	refresh.tooltip_text = "業務画面を再取得"
	footer.add_child(refresh)
	return frame

static func _stage(d, parent: Node, stage: Dictionary, icon: String, index: int) -> Control:
	var section := VBoxContainer.new()
	section.name = "BusinessSourceStage%d" % index
	section.custom_minimum_size.x = 190 * float(d.game.settings.get("text_scale", 1.0))
	section.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	section.add_theme_constant_override("separation", 2)
	parent.add_child(section)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 5)
	section.add_child(title_row)
	Glyph.add_to(title_row, icon, 22, PURPLE)
	var title := _label(d, title_row, str(stage.get("name", "取得元")), 14, INK)
	title.name = "BusinessSourceStageName%d" % index
	var detail := str(stage.get("detail", ""))
	if icon == "network" and detail.begins_with("//"): detail = detail.trim_prefix("//").get_slice("/", 0)
	if icon == "file" and not detail.is_empty():
		var filename := detail.get_file()
		if not filename.is_empty(): detail = filename
		if str(stage.get("label", "")) == "必要資料なし": detail = "受注・顧客資料"
	if icon == "process" and str(stage.get("status", "")) == "error": detail = "利用できません"
	var value := _label(d, section, detail, 14, MUTED)
	value.name = "BusinessSourceStageDetail%d" % index
	value.clip_text = true
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.tooltip_text = str(stage.get("tooltip", stage.get("detail", "")))
	var state_text := "%s %s" % [str(stage.get("symbol", "?")), str(stage.get("label", "未確認"))]
	var state_color: Color = GREEN if str(stage.get("status", "")) == "ok" else (RED if str(stage.get("status", "")) == "error" else MUTED)
	var status := _label(d, section, state_text, 14, state_color)
	status.name = "BusinessSourceStageStatus%d" % index
	return section
