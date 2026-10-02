extends RefCounted
## The ordinary invoicing application renders only responses received by its user.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("243746")
const MUTED := Color("657986")
const GREEN := Color("176e62")
const PALE := Color("e8f3ee")
const BORDER := Color("dbe4e9")

var d
var state: Dictionary
var service: Dictionary
var send: Callable
var redraw: Callable
var store: Callable
var scale := 1.0
var narrow := false

static func defaults(desktop) -> void:
	var s: Dictionary = desktop.pentest_ui
	if not s.get("service") is Dictionary: s.service = {}
	var initial := {"page":"list","session_checked":false,"query":"","filter":"all","invoices":[],"summary":{},"invoice":{},"events":[],"export":{},"download":{},"drafts":{},"feedback":"","error":false,"credentials_open":false,"login_username":"","login_password":"","selected_invoice":"","data_updated":false}
	for key in initial:
		if not s.service.has(key): s.service[key] = initial[key]

static func _clear_observed(s: Dictionary, reset_filters := true) -> void:
	var app: Dictionary = s.service
	for key in ["invoice","summary","export","download"]: app[key] = {}
	app.invoices = []; app.events = []; app.selected_invoice = ""; app.page = "list"
	app.erase("export_status_url"); app.erase("export_download_url")
	s.portal_request_id = ""; s.erase("export_status_url"); s.erase("export_download_url")
	if reset_filters: app.query = ""; app.filter = "all"

static func invalidate(desktop) -> void:
	var s: Dictionary = desktop.pentest_ui
	_clear_observed(s)
	s.portal_session = ""; s.portal_user = {}; s.service.session_checked = false

static func list_request(app: Dictionary) -> Dictionary:
	var query := str(app.get("query","")).uri_encode()
	return {"method":"GET","path":"/api/invoices?q="+query+"&state="+str(app.get("filter","all")),"intent":"list"}

static func receive(desktop, result: Dictionary, intent: String) -> Dictionary:
	var s: Dictionary = desktop.pentest_ui
	var app: Dictionary = s.service
	var response: Dictionary = result.get("response",{})
	var status := int(response.get("status",0))
	var data: Dictionary = response.get("data",{}) if response.get("data",{}) is Dictionary else {}
	var background := intent.begins_with("incident_")
	if not background or status >= 400 or status == 0:
		app.error = status >= 400 or status == 0
		app.feedback = ""
	if intent == "logout" and status in [200,401]:
		invalidate(desktop); app.login_password = ""; app.feedback = "ログアウトしました。"
		return {}
	if status >= 400 or status == 0:
		app.feedback = str(data.get("error","操作を完了できませんでした。もう一度お試しください。"))
		var username := str(s.portal_user.get("username",""))
		if intent in ["create","update"] and app.drafts.has(username):
			app.drafts[username].errors = data.get("fields",{}).duplicate(true)
			app.drafts[username].conflict = status == 409
		if status == 401 and intent != "login":
			invalidate(desktop); app.feedback = "ログインし直してください。編集中の請求書は保留しています。"
		return {}
	if background:
		if intent == "incident_list":
			app.invoices = data.get("invoices",[]).duplicate(true); app.summary = data.get("summary",{}).duplicate(true)
		elif intent == "incident_detail":
			app.invoice = data.duplicate(true)
			var held: Dictionary = app.drafts.get(str(s.portal_user.get("username","")),{})
			if str(held.get("invoice_id","")) == str(data.get("id","")) and int(held.get("version",0)) < int(data.get("version",0)):
				held.conflict = true; app.data_updated = true
		elif intent == "incident_history": app.events = data.get("events",[]).duplicate(true)
		return {}
	app.data_updated = false
	if intent in ["login","resume"]:
		var old_user := str(s.portal_user.get("username",""))
		var user: Dictionary = data.get("user",{})
		_clear_observed(s,intent == "login" or old_user != str(user.get("username","")))
		s.portal_session = str(data.get("session","")); s.portal_user = user.duplicate(true)
		app.session_checked = true; app.login_password = ""; app.error = false
		return list_request(app)
	if intent == "list":
		app.invoices = data.get("invoices",[]).duplicate(true)
		app.summary = data.get("summary",{}).duplicate(true)
		app.page = "list"
	elif intent in ["detail","create","update","approve"]:
		app.invoice = data.duplicate(true); app.selected_invoice = str(data.get("id",""))
		app.events = []; app.page = "detail"
		if intent in ["create","update"]:
			app.drafts.erase(str(s.portal_user.get("username","")))
			app.feedback = "請求書を作成しました。" if intent == "create" else "変更を保存しました。"
		if intent == "approve": app.feedback = "請求書を承認しました。"
	elif intent == "history":
		app.events = data.get("events",[]).duplicate(true); app.page = "detail"
	elif intent in ["export","poll"]:
		app.export = data.duplicate(true); app.page = "export"
		if data.has("status_url"): app.export_status_url = str(data.status_url)
		if data.has("download_url"): app.export_download_url = str(data.download_url)
	elif intent == "download":
		app.download = data.duplicate(true); app.page = "download"
		app.feedback = "CSVを取得しました。"
	return {}

func build(desktop, parent: VBoxContainer, data: Dictionary, send_request: Callable, redraw_view: Callable, save_ui: Callable) -> void:
	d = desktop; state = d.pentest_ui; service = state.service
	send = send_request; redraw = redraw_view; store = save_ui
	scale = float(d.game.settings.get("text_scale",1.0))
	narrow = bool(d.widgets.advanced.get("narrow",false))
	_brand(parent)
	if not str(service.feedback).is_empty():
		var feedback := _label(parent,str(service.feedback),13,Color("a63e34") if bool(service.error) else GREEN)
		feedback.name = "InvoiceFeedback"
	if state.portal_user.is_empty() or str(state.portal_session).is_empty():
		_login(parent,data)
		return
	if not bool(service.session_checked):
		_label(parent,"セッションを確認しています…",15,MUTED)
		if bool(service.error): _button(parent,"もう一度確認","InvoiceResumeSession",func(): _send("GET","/api/auth/session",{}, {},"resume"),true,"refresh")
		return
	if str(service.page) != "form" and not _draft().is_empty():
		var retained := HFlowContainer.new(); retained.add_theme_constant_override("h_separation",8); parent.add_child(retained)
		_label(retained,"編集中の請求書",12,MUTED)
		_button(retained,"下書きを再開","InvoiceResumeDraft",func(): service.page = "form"; service.feedback = ""; redraw.call(),false,"file")
	if bool(service.get("data_updated",false)) and not _draft().is_empty():
		var updated := _label(parent,"サービスのデータが更新されました。編集中の入力は保持しています。",13,MUTED); updated.name = "InvoiceDataUpdated"
		if not str(_draft().get("invoice_id","" )).is_empty(): _button(parent,"最新の請求書を確認","InvoiceInspectUpdated",func(): _open_invoice(str(_draft().invoice_id)),false,"refresh")
	match str(service.page):
		"form": _form(parent)
		"detail": _detail(parent,service.invoice)
		"export": _export(parent)
		"download":
			_toolbar_back(parent)
			_paper(parent,service.download)
		_: _list(parent)

func _brand(parent: VBoxContainer) -> void:
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation",10); parent.add_child(top)
	var logo := PanelContainer.new(); logo.add_theme_stylebox_override("panel",UI.style(PALE,Color.TRANSPARENT,10,9,8)); top.add_child(logo)
	var image := TextureRect.new(); image.texture = UI.symbol("briefcase"); image.custom_minimum_size = Vector2(25,25); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; logo.add_child(image)
	var brand := _column(top,1); brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(brand,"MIHAMA  /  請求管理",20,GREEN)
	_label(brand,"portal.mihama.test",11,MUTED)
	if not state.portal_user.is_empty() and bool(service.session_checked):
		var account := _column(top,1)
		_label(account,str(state.portal_user.get("username",""))+" · "+_tenant(str(state.portal_user.get("tenant",""))),12,INK)
		_label(account,"承認担当" if str(state.portal_user.get("role","")) == "reviewer" else "担当者",11,MUTED)
		_button(top,"ログアウト","InvoiceLogout",func(): _send("POST","/api/auth/logout",{}, {},"logout"),false,"external")
	parent.add_child(HSeparator.new())

func _login(parent: VBoxContainer, data: Dictionary) -> void:
	_label(parent,"ログイン",25,INK)
	var fields: BoxContainer = HBoxContainer.new() if not narrow else VBoxContainer.new()
	fields.add_theme_constant_override("separation",12); parent.add_child(fields)
	_input(fields,"ユーザー名","InvoiceLoginUsername",str(service.login_username),func(value: String): service.login_username = value; store.call())
	var password := _input(fields,"パスワード","InvoiceLoginPassword",str(service.login_password),func(value: String): service.login_password = value; store.call())
	password.secret = true
	password.text_submitted.connect(func(_value: String): _login_send())
	_button(parent,"ログイン","InvoiceLoginSubmit",_login_send,true,"person")
	_button(parent,"支給されたテストアカウント  ▴" if bool(service.credentials_open) else "支給されたテストアカウント  ▾","InvoiceTestAccountsToggle",func(): service.credentials_open = not bool(service.credentials_open); redraw.call(),false,"help")
	if bool(service.credentials_open):
		for account in data.get("accounts",[]):
			var username := str(account.get("username",account.get("session","")))
			var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12); parent.add_child(row)
			var info := _column(row,2); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_label(info,str(account.get("name",username)),13,INK)
			_label(info,username+"  /  "+str(account.get("password","")),12,MUTED)
			_button(row,"入力する","InvoiceTestAccount_"+username,func(): service.login_username = username; service.login_password = str(account.get("password","")); redraw.call(),false,"copy")

func _login_send() -> void:
	_send("POST","/api/auth/login",{"username":str(service.login_username),"password":str(service.login_password)}, {},"login")

func _list(parent: VBoxContainer) -> void:
	var heading := HBoxContainer.new(); parent.add_child(heading)
	_label(heading,"請求書",24,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading,"新規作成","InvoiceNew",func(): _start_form({}),true,"plus")
	var toolbar := HBoxContainer.new(); toolbar.add_theme_constant_override("separation",8); parent.add_child(toolbar)
	var search := LineEdit.new(); search.name = "InvoiceSearch"; search.placeholder_text = "請求番号・取引先を検索"; search.text = str(service.query); search.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _style_input(search); toolbar.add_child(search)
	search.text_changed.connect(func(value: String): service.query = value; store.call())
	search.text_submitted.connect(func(_value: String): _load_list())
	var filter := OptionButton.new(); filter.name = "InvoiceStateFilter"; toolbar.add_child(filter)
	filter.add_theme_font_size_override("font_size",int(13*scale)); filter.custom_minimum_size.y = 36*scale
	for option in [["all","すべて"],["draft","下書き"],["approved","承認済み"]]:
		filter.add_item(str(option[1])); filter.set_item_metadata(filter.item_count-1,str(option[0]))
		if str(service.filter) == str(option[0]): filter.select(filter.item_count-1)
	filter.item_selected.connect(func(index: int): service.filter = str(filter.get_item_metadata(index)); _load_list())
	_button(toolbar,"検索","InvoiceSearchSubmit",_load_list,false,"search")
	_button(toolbar,"更新","PentestPortalLoad",_load_list,false,"refresh")
	var summary: Dictionary = service.summary
	_label(parent,"%d 件  ·  合計 %s"%[int(summary.get("count",service.invoices.size())),_yen(summary.get("total",0))],12,MUTED)
	var table := _column(parent,0); table.name = "InvoiceTable"
	var head := PanelContainer.new(); head.add_theme_stylebox_override("panel",UI.style(Color("f2f6f8"),BORDER,12,8,0)); table.add_child(head)
	var labels := HBoxContainer.new(); labels.add_theme_constant_override("separation",12); head.add_child(labels)
	for column in [["請求番号",0.18],["取引先",0.31],["支払期限",0.17],["金額",0.19],["状態",0.15]]: _cell(labels,str(column[0]),float(column[1]),12,MUTED)
	for invoice in service.invoices:
		var id := str(invoice.get("id",""))
		var row := Button.new(); row.name = "PentestInvoice_"+id.validate_node_name(); row.custom_minimum_size.y = 53*scale; row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.tooltip_text = str(invoice.get("customer",""))+" / "+id
		row.add_theme_stylebox_override("normal",UI.style(PALE if id == str(service.selected_invoice) else Color.WHITE,BORDER,12,9,0))
		row.add_theme_stylebox_override("hover",UI.style(Color("edf5f5"),GREEN,12,9,0)); row.add_theme_stylebox_override("focus",UI.style(Color.TRANSPARENT,GREEN,12,9,0))
		row.pressed.connect(func(): _open_invoice(id)); table.add_child(row)
		var cells := HBoxContainer.new(); cells.add_theme_constant_override("separation",12); cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); cells.offset_left = 12; cells.offset_right = -12; cells.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(cells)
		_cell(cells,id,0.18,13,GREEN)
		_cell(cells,str(invoice.get("customer","")),0.31,14,INK)
		_cell(cells,str(invoice.get("due_date","—")),0.17,12,MUTED)
		_cell(cells,_yen(invoice.get("amount",0)),0.19,14,INK)
		var status := _column(cells,0); status.size_flags_stretch_ratio = 0.15; status.size_flags_vertical = Control.SIZE_SHRINK_CENTER; status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge(status,str(invoice.get("state","draft")))
	if service.invoices.is_empty():
		var empty := _column(table,8); empty.add_theme_constant_override("separation",12)
		_label(empty,"該当する請求書はありません",17,MUTED)
		if not str(service.query).is_empty() or str(service.filter) != "all": _button(empty,"検索を解除","InvoiceClearSearch",func(): service.query = ""; service.filter = "all"; _load_list(),false,"close")

func _toolbar_back(parent: VBoxContainer) -> HFlowContainer:
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation",8); parent.add_child(row)
	_button(row,"請求書一覧","PentestPortalLoad",_load_list,false,"back")
	return row

func _detail(parent: VBoxContainer, invoice: Dictionary) -> void:
	if invoice.is_empty(): _load_list(); return
	var id := str(invoice.get("id",""))
	var toolbar := _toolbar_back(parent)
	var editable := str(invoice.get("state","")) == "draft" and (str(state.portal_user.get("role","")) == "reviewer" or str(invoice.get("owner","")) == str(state.portal_user.get("username","")))
	var edit := _button(toolbar,"編集","InvoiceEdit",func(): _start_form(invoice),false,"file"); edit.disabled = not editable
	if not editable: edit.tooltip_text = "承認済みの請求書、または他の担当者の請求書は編集できません。"
	if str(invoice.get("state","")) == "draft":
		var approve := _button(toolbar,"承認","InvoiceApprove",func(): _send("POST","/api/invoices/"+id.uri_encode()+"/approve",{"version":int(invoice.get("version",1))},{},"approve"),true,"check")
		approve.disabled = str(state.portal_user.get("role","")) != "reviewer"
		if approve.disabled: approve.tooltip_text = "承認担当のアカウントで承認できます。"
	_button(toolbar,"CSVを作成","PentestCreateExport",func(): _send("POST","/api/exports",{"invoice_id":id},{"idempotency-key":(str(state.portal_session)+":"+str(state.portal_request_id)+":"+id).sha256_text().left(24)},"export"),false,"attachment")
	_button(toolbar,"更新履歴","InvoiceHistory",func(): _send("GET","/api/invoices/"+id.uri_encode()+"/history",{}, {},"history"),false,"clock")
	_button(toolbar,"更新","InvoiceDetailRefresh",func(): _open_invoice(id),false,"refresh")
	var held := _draft()
	if not held.is_empty() and bool(held.get("conflict",false)) and str(held.get("invoice_id","")) == id and int(invoice.get("version",1)) > int(held.get("version",1)):
		if editable: _conflict_review(parent,held,invoice)
		else: _label(parent,"承認済みのため編集できません。保留した入力は参照・取消できます。",13,MUTED)
	_paper(parent,invoice)
	if not service.events.is_empty(): _timeline(parent)

func _conflict_review(parent: VBoxContainer, held: Dictionary, latest: Dictionary) -> void:
	var panel := PanelContainer.new(); panel.name = "InvoiceConflictReview"; panel.add_theme_stylebox_override("panel",UI.style(Color("fff8e8"),Color("e7c889"),14,12,5)); parent.add_child(panel)
	var box := _column(panel,9)
	_label(box,"更新内容の確認  ·  版 %d → %d"%[int(held.version),int(latest.get("version",1))],16,INK)
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation",12); box.add_child(header)
	_cell(header,"項目",0.2,11,MUTED); _cell(header,"最新版",0.4,11,MUTED); _cell(header,"保留した入力",0.4,11,MUTED)
	for key in ["customer","issue_date","due_date","line_items","notes"]:
		if held.fields.get(key) == held.source.get(key): continue
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12); box.add_child(row)
		_cell(row,{"customer":"取引先","issue_date":"発行日","due_date":"支払期限","line_items":"明細","notes":"備考"}[key],0.2,12,MUTED)
		_cell(row,_field_summary(key,latest.get(key)),0.4,12,INK)
		_cell(row,_field_summary(key,held.fields.get(key)),0.4,12,GREEN)
	_button(box,"この入力で編集を再開","InvoiceRebaseDraft",func():
		for key in ["customer","issue_date","due_date","line_items","notes"]:
			if held.fields.get(key) == held.source.get(key): held.fields[key] = latest[key].duplicate(true) if latest[key] is Array else latest[key]
		held.version = int(latest.get("version",1)); held.source = latest.duplicate(true); held.errors = {}; held.conflict = false
		service.page = "form"; service.feedback = "最新版に対する編集です。内容を確認して保存してください。"; service.error = false; redraw.call()
	,true,"file")

static func _field_summary(key: String, value: Variant) -> String:
	if key != "line_items" or not value is Array: return str(value)
	var parts: Array[String] = []
	for item in value: parts.append(str(item.get("description",""))+" ×"+str(item.get("quantity",0))+" / "+_yen(item.get("unit_price",0)))
	return "、".join(parts)

func _paper(parent: VBoxContainer, invoice: Dictionary) -> void:
	var surround := PanelContainer.new(); surround.add_theme_stylebox_override("panel",UI.style(Color("edf1f3"),Color.TRANSPARENT,16,16,8)); parent.add_child(surround)
	var paper := PanelContainer.new(); paper.name = "InvoiceDocument"; paper.add_theme_stylebox_override("panel",UI.style(Color.WHITE,BORDER,22,22,1)); surround.add_child(paper)
	var content := _column(paper,16)
	var top := HBoxContainer.new(); content.add_child(top)
	var title := _column(top,3); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(title,"請 求 書",26,INK)
	_label(title,str(invoice.get("id",invoice.get("invoice_id",""))),12,MUTED)
	var chip := _badge(top,str(invoice.get("state","draft"))); chip.name = "InvoiceDetailState"
	var addresses := HBoxContainer.new(); addresses.add_theme_constant_override("separation",24); content.add_child(addresses)
	var recipient := _column(addresses,5); recipient.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var customer := _label(recipient,str(invoice.get("customer",""))+" 御中",19,INK); customer.name = "InvoiceDetailCustomer"
	_label(recipient,"下記の通りご請求申し上げます。",11,MUTED)
	var issuer := _column(addresses,5); issuer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; issuer.size_flags_stretch_ratio = 0.7
	_label(issuer,"ミハマ経理サービス · "+_tenant(str(invoice.get("tenant",""))),13,INK)
	_label(issuer,"発行日  "+str(invoice.get("issue_date","—")),12,MUTED)
	_label(issuer,"支払期限  "+str(invoice.get("due_date","—")),12,INK)
	var total_row := PanelContainer.new(); total_row.add_theme_stylebox_override("panel",UI.style(PALE,Color.TRANSPARENT,16,12,4)); content.add_child(total_row)
	var total := HBoxContainer.new(); total_row.add_child(total)
	_label(total,"ご請求金額",13,GREEN).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var amount := _label(total,_yen(invoice.get("amount",0)),28,GREEN); amount.name = "InvoiceDetailTotal"
	var lines := _column(content,0)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation",12); lines.add_child(head)
	for item in [["品目",0.52],["数量",0.12],["単価",0.18],["金額",0.18]]: _cell(head,str(item[0]),float(item[1]),11,MUTED)
	lines.add_child(HSeparator.new())
	for item in invoice.get("line_items",[]):
		var row := HBoxContainer.new(); row.custom_minimum_size.y = 38*scale; row.add_theme_constant_override("separation",12); lines.add_child(row)
		_cell(row,str(item.get("description","")),0.52,13,INK)
		_cell(row,str(item.get("quantity",0)),0.12,13,INK)
		_cell(row,_yen(item.get("unit_price",0)),0.18,13,INK)
		_cell(row,_yen(int(item.get("quantity",0))*int(item.get("unit_price",0))),0.18,13,INK)
		lines.add_child(HSeparator.new())
	if not str(invoice.get("notes","")).is_empty():
		_label(content,"備考",11,MUTED); _label(content,str(invoice.notes),13,INK)
	var foot := HBoxContainer.new(); content.add_child(foot)
	_label(foot,"担当  "+str(invoice.get("owner",""))+"  ·  版 "+str(int(invoice.get("version",1))),11,MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if str(invoice.get("state","")) == "approved":
		var stamp := PanelContainer.new(); stamp.name = "InvoiceApprovedStamp"; stamp.add_theme_stylebox_override("panel",UI.style(Color.WHITE,GREEN,12,7,2)); foot.add_child(stamp)
		_label(stamp,"✓  承認済",17,GREEN).autowrap_mode = TextServer.AUTOWRAP_OFF

func _timeline(parent: VBoxContainer) -> void:
	var heading := HBoxContainer.new(); heading.name = "InvoiceActivityHeading"; parent.add_child(heading)
	_label(heading,"更新履歴",18,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading,"閉じる","InvoiceHistoryBack",func(): service.events = []; redraw.call(),false,"close")
	var timeline := _column(parent,0); timeline.name = "InvoiceActivityTimeline"
	var field_labels := {"id":"請求番号","tenant":"組織","owner":"担当","currency":"通貨","customer":"取引先","line_items":"明細","amount":"合計金額","due_date":"支払期限","issue_date":"発行日","notes":"備考","state":"承認状態","version":"版"}
	for event in service.events:
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12); row.custom_minimum_size.y = 58*scale; timeline.add_child(row)
		var marker := _label(row,"●\n│",15,GREEN); marker.size_flags_vertical = Control.SIZE_FILL
		var text := _column(row,3); text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action := str(event.get("action",""))
		var actor := str(event.get("actor_name",event.get("actor","")))
		if actor == "incident-operator": actor = "対応担当"
		_label(text,{"created":"請求書を作成","updated":"請求書を更新","approved":"承認","restored":"請求書を復元","create":"請求書を作成","update":"請求書を更新","approve":"承認"}.get(action,action)+"  ·  "+actor,13,INK)
		var changes: Variant = event.get("changes",{})
		var details: Array[String] = []
		if changes is Dictionary:
			for key in changes:
				if field_labels.has(str(key)): details.append(str(field_labels[str(key)]))
		_label(text,"版 %d  ·  操作 #%d%s"%[int(event.get("version",1)),int(event.get("sequence",0)),"  ·  "+" / ".join(details) if not details.is_empty() else ""],11,MUTED)

func _draft() -> Dictionary:
	return service.drafts.get(str(state.portal_user.get("username","")),{})

func _start_form(invoice: Dictionary) -> void:
	var existing := _draft()
	if not existing.is_empty():
		service.page = "form"; service.feedback = "編集中の請求書を再開しました。"; redraw.call(); return
	var issue := Time.get_date_string_from_system()
	var due := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system())+30*86400).left(10)
	var fields := {"customer":str(invoice.get("customer","")),"issue_date":str(invoice.get("issue_date",issue)),"due_date":str(invoice.get("due_date",due)),"notes":str(invoice.get("notes","")),"line_items":invoice.get("line_items",[{"description":"","quantity":1,"unit_price":0}]).duplicate(true)}
	service.drafts[str(state.portal_user.get("username",""))] = {"mode":"create" if invoice.is_empty() else "update","invoice_id":str(invoice.get("id","")),"version":int(invoice.get("version",1)),"source":invoice.duplicate(true),"fields":fields,"errors":{},"conflict":false,"dirty":false,"key":("invoice:"+str(Time.get_ticks_usec())+":"+str(state.portal_session)).sha256_text().left(24)}
	service.page = "form"; service.feedback = ""; redraw.call()

func _form(parent: VBoxContainer) -> void:
	var draft := _draft()
	if draft.is_empty(): service.page = "list"; _list(parent); return
	var fields: Dictionary = draft.fields
	var top := HFlowContainer.new(); top.add_theme_constant_override("h_separation",8); parent.add_child(top)
	_label(top,"新しい請求書" if str(draft.mode) == "create" else str(draft.invoice_id)+" を編集",21,INK)
	var save := _button(top,"保存","InvoiceSave",_save_form,true,"save")
	if str(service.invoice.get("id","")) == str(draft.invoice_id) and str(service.invoice.get("state","")) == "approved":
		save.disabled = true; save.tooltip_text = "この請求書は承認済みのため変更できません。"
	_button(top,"取消","InvoiceCancel",_cancel_form,false,"close")
	_button(top,"一覧へ","PentestPortalLoad",_load_list,false,"back")
	if not draft.errors.is_empty():
		var messages: Array[String] = []
		for key in draft.errors: messages.append(str(draft.errors[key]))
		var errors := _label(parent,"\n".join(messages),13,Color("a63e34")); errors.name = "InvoiceFormErrors"
	if bool(draft.conflict) and not str(draft.invoice_id).is_empty(): _button(parent,"最新版を確認（入力は保留）","InvoiceReloadConflict",func(): _open_invoice(str(draft.invoice_id)),false,"refresh")
	var meta: BoxContainer = HBoxContainer.new() if not narrow else VBoxContainer.new(); meta.add_theme_constant_override("separation",12); parent.add_child(meta)
	_input(meta,"取引先","InvoiceCustomer",str(fields.customer),func(value: String): fields.customer = value; _form_changed(draft,"customer"))
	var dates := HBoxContainer.new(); dates.add_theme_constant_override("separation",12); dates.size_flags_horizontal = Control.SIZE_EXPAND_FILL; meta.add_child(dates)
	var issue := _input(dates,"発行日","InvoiceIssueDate",str(fields.issue_date),func(value: String): fields.issue_date = value; _form_changed(draft,"issue_date")); issue.custom_minimum_size.x = 122*scale
	var due := _input(dates,"支払期限","InvoiceDueDate",str(fields.due_date),func(value: String): fields.due_date = value; _form_changed(draft,"due_date")); due.custom_minimum_size.x = 122*scale
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation",8); parent.add_child(head)
	for item in [["品目・内容",0.48],["数量",0.12],["単価（円）",0.20],["金額",0.20]]: _cell(head,str(item[0]),float(item[1]),12,MUTED)
	var spacer := Control.new(); spacer.custom_minimum_size.x = 36*scale; head.add_child(spacer)
	for index in fields.line_items.size():
		var line: Dictionary = fields.line_items[index]
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation",8); parent.add_child(row)
		_line_input(row,"InvoiceLineDescription_%d"%index,str(line.get("description","")),0.48,func(value: String): line.description = value; _form_changed(draft,"line_items"))
		_line_input(row,"InvoiceLineQuantity_%d"%index,str(line.get("quantity",1)),0.12,func(value: String): line.quantity = int(value) if value.is_valid_int() else value; _form_changed(draft,"line_items"))
		_line_input(row,"InvoiceLinePrice_%d"%index,str(line.get("unit_price",0)),0.20,func(value: String): line.unit_price = int(value) if value.is_valid_int() else value; _form_changed(draft,"line_items"))
		var amount := _cell(row,_yen(_line_total(line)),0.20,13,INK); amount.name = "InvoiceLineTotal_%d"%index
		var remove := _button(row,"","InvoiceRemoveLine_%d"%index,func(): fields.line_items.remove_at(index); _form_changed(draft); redraw.call(),false,"close")
		remove.tooltip_text = "この明細を削除"; remove.disabled = fields.line_items.size() <= 1
	_button(parent,"明細を追加","InvoiceAddLine",func(): fields.line_items.append({"description":"","quantity":1,"unit_price":0}); _form_changed(draft); redraw.call(),false,"plus")
	var sum_row := HBoxContainer.new(); parent.add_child(sum_row)
	_label(sum_row,"合計",14,MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var total := _label(sum_row,_yen(_form_total(fields)),25,GREEN); total.name = "InvoiceFormTotal"
	_label(parent,"備考",12,MUTED)
	var notes := TextEdit.new(); notes.name = "InvoiceNotes"; notes.text = str(fields.notes); notes.custom_minimum_size.y = 74*scale; notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; notes.add_theme_font_size_override("font_size",int(14*scale)); notes.add_theme_stylebox_override("normal",UI.style(Color("f7fafb"),BORDER,10,8,4)); parent.add_child(notes)
	notes.add_theme_font_override("font",UI.font(400)); notes.add_theme_color_override("font_color",INK); notes.add_theme_color_override("font_readonly_color",MUTED); notes.add_theme_color_override("caret_color",INK); notes.add_theme_color_override("selection_color",GREEN); notes.add_theme_color_override("font_selected_color",Color.WHITE)
	notes.text_changed.connect(func(): fields.notes = notes.text; _form_changed(draft,"notes"))

func _form_changed(draft: Dictionary, field_name := "") -> void:
	draft.dirty = true
	if not field_name.is_empty():
		for key in draft.errors.keys():
			if str(key).begins_with(field_name): draft.errors.erase(key)
	store.call()
	var root: Node = d.widgets.advanced.root
	var errors := root.find_child("InvoiceFormErrors",true,false) as Label
	if is_instance_valid(errors):
		var messages: Array[String] = []
		for key in draft.errors: messages.append(str(draft.errors[key]))
		errors.text = "\n".join(messages); errors.visible = not messages.is_empty()
	var total := root.find_child("InvoiceFormTotal",true,false) as Label
	if is_instance_valid(total): total.text = _yen(_form_total(draft.fields))
	for index in draft.fields.line_items.size():
		var line := root.find_child("InvoiceLineTotal_%d"%index,true,false) as Label
		if is_instance_valid(line): line.text = _yen(_line_total(draft.fields.line_items[index]))

func _save_form() -> void:
	var draft := _draft()
	if draft.is_empty(): return
	var body: Dictionary = draft.fields.duplicate(true)
	var headers := {}
	if str(draft.mode) == "update": body["version"] = int(draft.version)
	else: headers["idempotency-key"] = str(draft.key)
	_send("PATCH" if str(draft.mode) == "update" else "POST","/api/invoices/"+str(draft.invoice_id).uri_encode() if str(draft.mode) == "update" else "/api/invoices",body,headers,str(draft.mode))

func _cancel_form() -> void:
	var draft := _draft()
	if not draft.is_empty() and not draft.source.is_empty(): service.invoice = draft.source.duplicate(true); service.page = "detail"
	else: service.page = "list"
	service.drafts.erase(str(state.portal_user.get("username",""))); service.feedback = ""; redraw.call()

func _export(parent: VBoxContainer) -> void:
	_toolbar_back(parent)
	var data: Dictionary = service.export
	var processing := str(data.get("status","")) == "processing"
	_label(parent,"CSVを作成しています" if processing else "CSVの準備ができました",22,INK)
	var progress := ProgressBar.new(); progress.name = "PentestExportProgress"; progress.value = 48 if processing else 100; progress.show_percentage = false; progress.custom_minimum_size.y = 8; parent.add_child(progress)
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation",8); parent.add_child(row)
	_button(row,"状態を更新","PentestPollExport",func(): _send("GET",str(service.get("export_status_url","")),{}, {},"poll"),false,"refresh")
	var download := _button(row,"CSVをダウンロード","PentestDownloadExport",func(): _send("GET",str(service.get("export_download_url","")),{}, {},"download"),true,"attachment")
	download.disabled = processing
	if not service.invoice.is_empty():
		_label(parent,str(service.invoice.get("customer","")),15,INK)
		_label(parent,_yen(service.invoice.get("amount",0)),22,GREEN)

func _open_invoice(id: String) -> void:
	_send("GET","/api/invoices/"+id.uri_encode(),{}, {},"detail")

func _load_list() -> void:
	var request := list_request(service)
	_send("GET",str(request.path),{}, {},"list")

func _send(method: String, path: String, body: Dictionary, headers: Dictionary, intent: String) -> void:
	service.feedback = ""; service.error = false
	store.call(); send.call(method,path,body,headers,intent)

func _input(parent: Node, title: String, node_name: String, value: String, changed: Callable) -> LineEdit:
	var column := _column(parent,5); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(column,title,12,MUTED)
	return _line_input(column,node_name,value,1.0,changed)

func _line_input(parent: Node, node_name: String, value: String, weight: float, changed: Callable) -> LineEdit:
	var field := LineEdit.new(); field.name = node_name; field.text = value; field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; field.size_flags_stretch_ratio = weight; _style_input(field)
	field.text_changed.connect(changed); parent.add_child(field); return field

func _style_input(field: LineEdit) -> void:
	field.custom_minimum_size = Vector2(0,36*scale); field.expand_to_text_length = false
	field.add_theme_font_size_override("font_size",int(14*scale)); field.add_theme_color_override("font_color",INK)
	field.add_theme_stylebox_override("normal",UI.style(Color("f7fafb"),BORDER,10,8,4)); field.add_theme_stylebox_override("focus",UI.style(Color.WHITE,GREEN,10,8,4))

func _button(parent: Node, title: String, node_name: String, callback: Callable, primary := false, icon_name := "") -> Button:
	var button: Button = d._button(title,callback); button.name = node_name
	button.icon = UI.symbol(icon_name) if not icon_name.is_empty() else null; button.expand_icon = false; button.add_theme_constant_override("icon_max_width",int(17*scale))
	if title.is_empty(): button.custom_minimum_size.x = 36*scale
	button.custom_minimum_size.y = 36*scale; button.add_theme_font_size_override("font_size",int(13*scale)); button.tooltip_text = title
	button.add_theme_stylebox_override("normal",UI.style(GREEN if primary else Color.WHITE,GREEN if primary else BORDER,12,7,5)); button.add_theme_stylebox_override("hover",UI.style(Color("258777") if primary else PALE,GREEN,12,7,5))
	button.add_theme_color_override("font_color",Color.WHITE if primary else INK); button.add_theme_color_override("font_hover_color",Color.WHITE if primary else GREEN)
	parent.add_child(button); return button

func _badge(parent: Node, value: String) -> Label:
	var panel := PanelContainer.new(); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER; panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var approved := value == "approved"
	panel.add_theme_stylebox_override("panel",UI.style(PALE if approved else Color("fff2d8"),Color.TRANSPARENT,9,5,5)); parent.add_child(panel)
	var label := _label(panel,"✓ 承認済み" if approved else "下書き",11,GREEN if approved else Color("92651d"))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

func _cell(parent: Node, text: String, weight: float, point: int, color: Color) -> Label:
	var label := _label(parent,text,point,color); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.size_flags_vertical = Control.SIZE_SHRINK_CENTER; label.size_flags_stretch_ratio = weight
	label.autowrap_mode = TextServer.AUTOWRAP_OFF; label.clip_text = true; label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; label.tooltip_text = text
	return label

func _label(parent: Node, text: String, point: int, color: Color) -> Label:
	var label := Label.new(); label.text = text; label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.add_theme_font_override("font",UI.font(400)); label.add_theme_font_size_override("font_size",int(point*scale)); label.add_theme_color_override("font_color",color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF if parent is HBoxContainer or parent is HFlowContainer else TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label); return label

func _column(parent: Node, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",separation); parent.add_child(column); return column

static func _line_total(item: Dictionary) -> int:
	return int(str(item.get("quantity",0))) * int(str(item.get("unit_price",0)))

static func _form_total(fields: Dictionary) -> int:
	var amount := 0
	for item in fields.get("line_items",[]): amount += _line_total(item)
	return amount

static func _tenant(value: String) -> String:
	return {"north":"北営業","south":"南営業"}.get(value,value)

static func _yen(value: Variant) -> String:
	var digits := str(int(value)); var output := ""
	for index in digits.length():
		if index > 0 and (digits.length()-index)%3 == 0: output += ","
		output += digits[index]
	return "¥"+output
