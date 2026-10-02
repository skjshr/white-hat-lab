extends RefCounted
## Persistent fictional business service behind the portal's HTTP recorder.

const PASSWORDS := {"alice":"Alice-demo-27", "noah":"Noah-demo-27", "beth":"Beth-demo-27"}
const EDITABLE := ["customer", "issue_date", "due_date", "notes", "line_items"]
const INVOICE_LIMIT := 256
const MAX_TOTAL := 999999999

static func initialize(m: Dictionary, legacy: bool = false) -> void:
	if not m.has("auth_version"):
		m.auth_version = 1
		m.sessions = {}
		m.session_counter = 0
		if legacy:
			for username in m.users:
				m.sessions[username] = {"username":username,"revoked":false,"legacy":true}
	if not m.has("invoice_history"): m.invoice_history = {}
	if not m.has("invoice_counter"): m.invoice_counter = 1000
	if not m.has("event_counter"): m.event_counter = 0
	if not m.has("business_idempotency"): m.business_idempotency = {}
	for invoice in m.invoices.values():
		if not invoice.has("version"):
			invoice.version = 1
			invoice.updated_sequence = 0
			invoice.issue_date = "2026-10-01"
			invoice.due_date = "2026-10-31"
			invoice.notes = ""
			invoice.line_items = [{"description":"業務支援サービス","quantity":1,"unit_price":int(invoice.amount)}]
		if not m.invoice_history.has(str(invoice.id)):
			m.invoice_history[str(invoice.id)] = []
			_event(m, invoice, "imported", str(invoice.owner), 0, {"state":invoice.state,"amount":invoice.amount})

static func wire(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0: return int(value)
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value: out[key] = wire(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(wire(item))
		return out
	return value

static func response(status: int, data: Dictionary, headers: Dictionary = {}) -> Dictionary:
	var result_headers := headers.duplicate(true)
	result_headers["content-type"] = "application/json"
	var data_copy: Dictionary = wire(data)
	return {"status":status,"data":data_copy,"body":JSON.stringify(data_copy),"content_type":"application/json","headers":result_headers}

static func error(status: int, message: String, fields: Dictionary = {}) -> Dictionary:
	var data := {"error":message}
	if not fields.is_empty(): data.fields = fields
	return response(status, data)

static func principal(m: Dictionary, token: String, historical: bool = false) -> String:
	# Legacy identity is interpreted without changing old evidence or read-only views.
	if not m.has("auth_version"): return token if m.get("users", {}).has(token) else ""
	var session: Dictionary = m.get("sessions", {}).get(token, {})
	if session.is_empty() or (not historical and bool(session.get("revoked", false))): return ""
	var username := str(session.get("username", ""))
	return username if m.users.has(username) else ""

static func public_user(m: Dictionary, username: String) -> Dictionary:
	if not m.users.has(username): return {}
	var user: Dictionary = m.users[username]
	return {"username":username,"name":str(user.name),"tenant":str(user.tenant),"role":str(user.role)}

static func auth(m: Dictionary, req: Dictionary) -> Dictionary:
	var path := str(req.path).get_slice("?", 0)
	var method := str(req.method)
	if path == "/api/auth/login":
		if method != "POST": return response(405, {"error":"method not allowed"}, {"allow":"POST"})
		var username: Variant = req.body.get("username", null)
		var password: Variant = req.body.get("password", null)
		if not username is String or not password is String or not PASSWORDS.has(username) or password != PASSWORDS.get(username) or not m.users.has(username): return error(401, "IDまたはパスワードを確認してください。")
		if m.sessions.size() >= 512: return error(429, "検証用セッションの上限に達しました。")
		m.session_counter = int(m.session_counter) + 1
		var token := "sess_" + (str(m.nonce) + ":" + str(m.session_counter) + ":" + str(randi()) + ":" + str(Time.get_ticks_usec())).sha256_text().substr(0, 40)
		m.sessions[token] = {"username":username,"revoked":false,"legacy":false}
		return response(200, {"session":token,"user":public_user(m, username)})
	if path not in ["/api/auth/session", "/api/auth/logout"]: return {}
	var username := principal(m, str(req.session))
	if username.is_empty(): return error(401, "ログインしてください。")
	if path == "/api/auth/session":
		if method != "GET": return response(405, {"error":"method not allowed"}, {"allow":"GET"})
		return response(200, {"session":str(req.session),"user":public_user(m, username)})
	if method != "POST": return response(405, {"error":"method not allowed"}, {"allow":"POST"})
	m.sessions[str(req.session)].revoked = true
	return response(200, {"logged_out":true})

static func dispatch(m: Dictionary, req: Dictionary, username: String, sequence: int) -> Dictionary:
	var path := str(req.path).get_slice("?", 0)
	var method := str(req.method)
	var user: Dictionary = m.users[username]
	if path == "/api/invoices":
		if method == "GET": return _list(m, req, user)
		if method == "POST": return _create(m, req, username, sequence)
		return response(405, {"error":"method not allowed"}, {"allow":"GET, POST"})
	var parts := path.split("/", false)
	if parts.size() < 3 or parts[0] != "api" or parts[1] != "invoices": return {}
	if parts.size() > 4 or (parts.size() == 4 and parts[3] not in ["approve", "history"]): return error(404, "route not found")
	if not m.invoices.has(parts[2]): return error(404, "invoice not found")
	var invoice: Dictionary = m.invoices[parts[2]]
	if str(invoice.tenant) != str(user.tenant): return error(403, "invoice is outside your organization")
	if parts.size() == 4:
		if parts[3] == "history":
			if method != "GET": return response(405, {"error":"method not allowed"}, {"allow":"GET"})
			return response(200, {"events":m.invoice_history.get(str(invoice.id), []).duplicate(true)})
		if method != "POST": return response(405, {"error":"method not allowed"}, {"allow":"POST"})
		return _approve(m, req, username, invoice, sequence)
	if method == "GET": return response(200, invoice)
	if method == "PATCH": return _update(m, req, username, invoice, sequence)
	return response(405, {"error":"method not allowed"}, {"allow":"GET, PATCH"})

static func _list(m: Dictionary, req: Dictionary, user: Dictionary) -> Dictionary:
	var query: Dictionary = {}
	if "?" in str(req.path):
		for pair in str(req.path).get_slice("?", 1).split("&", false):
			query[pair.get_slice("=", 0).uri_decode()] = pair.substr(pair.find("=") + 1).replace("+", " ").uri_decode() if "=" in pair else ""
	var state := str(query.get("state", "all"))
	if state not in ["all", "draft", "approved"]: return error(400, "状態の絞り込みを確認してください。")
	var search := str(query.get("q", "")).strip_edges().to_lower()
	var invoices: Array = []
	var summary := {"count":0,"draft_count":0,"approved_count":0,"total":0}
	for invoice in m.invoices.values():
		if str(invoice.tenant) != str(user.tenant): continue
		if state != "all" and str(invoice.state) != state: continue
		if not search.is_empty() and not str(invoice.id).to_lower().contains(search) and not str(invoice.customer).to_lower().contains(search): continue
		invoices.append(invoice.duplicate(true))
		summary.count += 1
		summary[str(invoice.state) + "_count"] += 1
		summary.total += int(invoice.amount)
	invoices.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.id) < str(b.id))
	return response(200, {"invoices":invoices,"tenant":user.tenant,"summary":summary})

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value) and absf(value) <= MAX_TOTAL)

static func _date(value: Variant) -> bool:
	if not value is String or value.length() != 10 or value[4] != "-" or value[7] != "-": return false
	var parts: PackedStringArray = str(value).split("-")
	if parts.size() != 3: return false
	for part in parts:
		if not str(part).is_valid_int() or str(part).begins_with("+") or str(part).begins_with("-"): return false
	var year := int(parts[0]); var month := int(parts[1]); var day := int(parts[2])
	if year < 1900 or year > 2199 or month < 1 or month > 12: return false
	var days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day >= 1 and day <= days[month - 1]

static func _validated(body: Dictionary, existing: Dictionary = {}) -> Dictionary:
	var fields: Dictionary = {}
	for key in body:
		if key not in EDITABLE and not (key == "version" and not existing.is_empty()): fields[key] = "この項目は変更できません。"
	var clean: Dictionary = {}
	for key in EDITABLE: clean[key] = body.get(key, existing.get(key, "" if key != "line_items" else []) )
	for key in ["customer", "notes"]:
		if not clean[key] is String: fields[key] = "文字で入力してください。"
		elif str(clean[key]).length() > (2000 if key == "notes" else 180): fields[key] = "入力が長すぎます。"
		else: clean[key] = str(clean[key]).strip_edges()
	if clean.customer is String and str(clean.customer).is_empty(): fields.customer = "取引先を入力してください。"
	for key in ["issue_date", "due_date"]:
		if not _date(clean[key]): fields[key] = "有効な日付をYYYY-MM-DDで入力してください。"
	if not fields.has("issue_date") and not fields.has("due_date") and str(clean.due_date) < str(clean.issue_date): fields.due_date = "支払期限は発行日以降にしてください。"
	var items: Array = []
	var total := 0
	if not clean.line_items is Array or clean.line_items.is_empty() or clean.line_items.size() > 50: fields.line_items = "明細を1〜50行入力してください。"
	else:
		for line in clean.line_items:
			if not line is Dictionary:
				fields.line_items = "明細の形式を確認してください。"; continue
			var description: Variant = line.get("description", null)
			var quantity: Variant = line.get("quantity", null)
			var price: Variant = line.get("unit_price", null)
			if not description is String or description.strip_edges().is_empty() or description.length() > 240:
				fields.line_items = "各明細の内容を1〜240文字で入力してください。"; continue
			if not _integer(quantity) or not _integer(price) or int(quantity) <= 0 or int(quantity) > 100000 or int(price) < 0 or int(price) > MAX_TOTAL:
				fields.line_items = "数量は正の整数、単価は0以上の整数で入力してください。"; continue
			total += int(quantity) * int(price)
			items.append({"description":description.strip_edges(),"quantity":int(quantity),"unit_price":int(price)})
	if total <= 0 or total > MAX_TOTAL: fields.line_items = "合計額は1〜999,999,999円にしてください。"
	clean.line_items = items
	clean.amount = total
	return {"data":clean,"fields":fields}

static func _create(m: Dictionary, req: Dictionary, username: String, sequence: int) -> Dictionary:
	var validated := _validated(req.body)
	if not validated.fields.is_empty(): return error(422, "入力内容を確認してください。", validated.fields)
	var idem := str(req.headers.get("idempotency-key", ""))
	var idem_key := username + ":create:" + idem
	var fingerprint := JSON.stringify(wire(req.body))
	if not idem.is_empty() and m.business_idempotency.has(idem_key):
		var previous: Dictionary = m.business_idempotency[idem_key]
		if str(previous.fingerprint) != fingerprint: return error(409, "同じ送信キーが別の内容に使われています。")
		return response(201, previous.invoice)
	if m.invoices.size() >= INVOICE_LIMIT + (160 if bool(m.get("exercise_mode", false)) else 0): return error(429, "検証用請求書の上限に達しました。")
	m.invoice_counter = int(m.invoice_counter) + 1
	var invoice: Dictionary = validated.data
	var tenant := str(m.users[username].tenant)
	invoice.merge({"id":"INV-%s%d" % ["N" if tenant == "north" else "S", int(m.invoice_counter)],"tenant":tenant,"owner":username,"currency":"JPY","state":"draft","version":1,"updated_sequence":sequence})
	m.invoices[str(invoice.id)] = invoice
	m.invoice_history[str(invoice.id)] = []
	_event(m, invoice, "created", username, sequence, invoice.duplicate(true))
	if not idem.is_empty(): m.business_idempotency[idem_key] = {"fingerprint":fingerprint,"invoice":invoice.duplicate(true)}
	return response(201, invoice)

static func _version(req: Dictionary, invoice: Dictionary) -> Dictionary:
	var version: Variant = req.body.get("version", null)
	if not _integer(version) or int(version) < 1: return error(422, "版を指定してください。", {"version":"請求書を開き直してください。"})
	if int(version) != int(invoice.version): return error(409, "他の変更が保存されています。最新の請求書を開き直してください。")
	return {}

static func _update(m: Dictionary, req: Dictionary, username: String, invoice: Dictionary, sequence: int) -> Dictionary:
	if str(m.users[username].role) != "reviewer" and str(invoice.owner) != username: return error(403, "この請求書を編集する権限がありません。")
	if str(invoice.state) != "draft": return error(409, "承認済みの請求書は変更できません。")
	var conflict := _version(req, invoice)
	if not conflict.is_empty(): return conflict
	var validated := _validated(req.body, invoice)
	if not validated.fields.is_empty(): return error(422, "入力内容を確認してください。", validated.fields)
	var changes: Dictionary = {}
	for key in validated.data:
		if wire(invoice.get(key)) != wire(validated.data[key]): changes[key] = {"before":invoice.get(key),"after":validated.data[key]}
	if changes.is_empty(): return response(200, invoice)
	invoice.merge(validated.data, true)
	invoice.version = int(invoice.version) + 1
	invoice.updated_sequence = sequence
	_event(m, invoice, "updated", username, sequence, changes)
	return response(200, invoice)

static func _approve(m: Dictionary, req: Dictionary, username: String, invoice: Dictionary, sequence: int) -> Dictionary:
	if str(m.users[username].role) != "reviewer": return error(403, "承認担当者のみ承認できます。")
	var conflict := _version(req, invoice)
	if not conflict.is_empty(): return conflict
	for key in req.body:
		if key != "version": return error(422, "承認要求の形式を確認してください。", {str(key):"承認時は版のみを指定してください。"})
	if str(invoice.state) == "approved": return response(200, invoice)
	invoice.state = "approved"
	invoice.version = int(invoice.version) + 1
	invoice.updated_sequence = sequence
	_event(m, invoice, "approved", username, sequence, {"state":{"before":"draft","after":"approved"}})
	return response(200, invoice)

static func _event(m: Dictionary, invoice: Dictionary, action: String, username: String, sequence: int, changes: Dictionary) -> void:
	m.event_counter = int(m.event_counter) + 1
	m.invoice_history[str(invoice.id)].append({"id":"event-%d" % int(m.event_counter),"invoice_id":str(invoice.id),"action":action,"actor":username,"actor_name":str(m.users.get(username, {}).get("name", username)),"sequence":sequence,"version":int(invoice.version),"changes":changes.duplicate(true)})

static func csv(invoice: Dictionary) -> String:
	var keys := ["id", "tenant", "customer", "amount", "currency", "state", "issue_date", "due_date", "notes"]
	var cells: PackedStringArray = []
	for key in keys:
		var value := str(invoice.get(key, ""))
		if key == "amount": value = str(int(invoice.amount))
		if "," in value or '"' in value or "\n" in value or "\r" in value: value = '"' + value.replace('"', '""') + '"'
		cells.append(value)
	return "invoice_id,tenant,customer,amount,currency,state,issue_date,due_date,notes\n" + ",".join(cells) + "\n"
