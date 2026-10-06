extends RefCounted
## A customer's folio is separate from both the EDR policy and our company cash.
## Only a newly authored hotel VM creates these files. Reads never seed repairs.
const PATH := "/srv/hotel/folios.json"
const DEVICE := "pc_b"
const FOLIO := "F-204"

static func enabled(saved: Dictionary) -> bool:
	return int(saved.get("scenario", {}).get("hotel_workflow_version", 0)) == 1

static func initialize(saved: Dictionary) -> void:
	if not enabled(saved): return
	if "/srv/hotel" not in saved.dirs: saved.dirs.append("/srv/hotel")
	var document := {"version":1,"rooms":[
		{"room":"201","guest":"佐伯 航","status":"occupied","folio_id":""},
		{"room":"202","guest":"宮原 奏","status":"occupied","folio_id":""},
		{"room":"203","guest":"高瀬 直人","status":"occupied","folio_id":""},
		{"room":"204","guest":"水瀬 柚","status":"departure","folio_id":FOLIO}
	],"folios":[{"id":FOLIO,"room":"204","guest":"水瀬 柚","lines":[
		{"label":"宿泊 · 1泊","amount":19800},
		{"label":"朝食 · 1名","amount":1800},
		{"label":"駐車場 · 1泊","amount":1200}
	],"total":22800,"balance":22800,"status":"pending","receipt":{}}],"last_attempt":{}}
	saved.fs[PATH] = JSON.stringify(document, "", true)
	saved.hotel_journal = []

static func _document(saved: Dictionary) -> Dictionary:
	var content := str(saved.get("fs", {}).get(PATH, ""))
	if content.is_empty(): return {}
	var parsed: Variant = JSON.parse_string(content)
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1 or not parsed.get("rooms") is Array or not parsed.get("folios") is Array: return {}
	if not parsed.get("last_attempt", {}) is Dictionary: return {}
	for room in parsed.rooms:
		if not room is Dictionary or not room.has_all(["room", "guest", "status", "folio_id"]): return {}
	for folio in parsed.folios:
		if not folio is Dictionary or not folio.has_all(["id", "room", "guest", "lines", "total", "balance", "status", "receipt"]) or not folio.lines is Array or not folio.receipt is Dictionary: return {}
		if typeof(folio.total) not in [TYPE_INT, TYPE_FLOAT] or typeof(folio.balance) not in [TYPE_INT, TYPE_FLOAT]: return {}
		if not is_finite(float(folio.total)) or not is_finite(float(folio.balance)) or float(folio.total) != floorf(float(folio.total)) or float(folio.balance) != floorf(float(folio.balance)): return {}
		if folio.status not in ["pending", "received"]: return {}
		var total := 0
		for line in folio.lines:
			if not line is Dictionary or not line.has_all(["label", "amount"]) or typeof(line.amount) not in [TYPE_INT, TYPE_FLOAT]: return {}
			if not is_finite(float(line.amount)) or float(line.amount) != floorf(float(line.amount)) or float(line.amount) < 0: return {}
			total += int(line.amount)
		if total != int(folio.total) or total <= 0 or total > 100000000: return {}
	return parsed

static func _folio(document: Dictionary, id: String) -> Dictionary:
	for row in document.get("folios", []):
		if str(row.id) == id: return row
	return {}

static func _received(saved: Dictionary, folio: Dictionary) -> bool:
	if folio.is_empty() or str(folio.get("status", "")) != "received" or int(folio.get("balance", -1)) != 0: return false
	var receipt: Dictionary = folio.get("receipt", {})
	if str(receipt.get("number", "")).is_empty() or str(receipt.get("folio_id", "")) != str(folio.id) or int(receipt.get("total", -1)) != int(folio.total) or str(receipt.get("folio_sha256", "")) != _folio_hash(folio): return false
	for entry in saved.get("hotel_journal", []):
		if entry is Dictionary and str(entry.get("action", "")) == "receive" and _canonical(entry.get("receipt", {})) == _canonical(receipt): return true
	return false

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

static func _folio_hash(folio: Dictionary) -> String:
	# Numeric JSON values become floats after loading; hash the same canonical
	# representation before and after restart.
	var source := {"id":folio.id,"room":folio.room,"guest":folio.guest,"lines":folio.lines,"total":folio.total}
	return _canonical(source).sha256_text()

static func snapshot(saved: Dictionary) -> Dictionary:
	if not enabled(saved): return {"enabled":false}
	var document := _document(saved)
	var result := {"enabled":true,"connected":bool(saved.get("connected", false)) and bool(saved.get("active", false)),"client":str(saved.get("scenario", {}).get("client", "白波ホテル")),"device":DEVICE,"isolated":str(saved.get("applied", {}).get(DEVICE, "")) == "isolated","rooms":document.get("rooms", []).duplicate(true),"folios":document.get("folios", []).duplicate(true),"last_attempt":document.get("last_attempt", {}).duplicate(true),"source":PATH,"error":"data_unavailable" if document.is_empty() else ""}
	return result

static func accepted(saved: Dictionary) -> bool:
	return enabled(saved) and _received(saved, _folio(_document(saved), FOLIO))

static func outcome(saved: Dictionary) -> Dictionary:
	if not enabled(saved): return {}
	var folio := _folio(_document(saved), FOLIO)
	if folio.is_empty(): return {"folio_id":FOLIO,"status":"unavailable"}
	return {"folio_id":FOLIO,"room":str(folio.room),"guest":str(folio.guest),"total":int(folio.total),"balance":int(folio.balance),"status":"received" if _received(saved, folio) else "pending","receipt":folio.receipt.duplicate(true),"reservation_device":"pc_a","reservation_isolated":str(saved.get("applied", {}).get("pc_a", "")) == "isolated"}

static func rejected(code: int, error: String) -> Dictionary:
	return {"ok":false,"code":code,"error":error,"response":"HTTP %d · %s" % [code, error],"changed":false}

## Return a write set. Game commits the file, journal, clock and compensation together.
static func plan(saved: Dictionary, id: String, day: int, clock: String) -> Dictionary:
	if not enabled(saved): return rejected(404, "unsupported_workflow")
	var document := _document(saved)
	if document.is_empty(): return rejected(422, "data_unavailable")
	var folio := _folio(document, id)
	if id != FOLIO or folio.is_empty(): return rejected(404, "folio_missing")
	var code := 200
	var error := ""
	if not bool(saved.get("connected", false)): code = 503; error = "not_connected"
	elif not bool(saved.get("active", false)): code = 503; error = "service_unavailable"
	elif str(saved.get("applied", {}).get(DEVICE, "")) == "isolated": code = 403; error = "endpoint_isolated"
	elif str(saved.get("applied", {}).get(DEVICE, "")) != "connected": code = 503; error = "endpoint_unavailable"
	if code == 200 and _received(saved, folio):
		# A retry may follow an intervening 403. Preserve the original receipt,
		# but record this actual response without another payment or work charge.
		document.last_attempt = {"folio_id":id,"code":200,"error":"","day":day,"clock":clock,"device":DEVICE,"duplicate":true}
		return {"ok":true,"code":200,"error":"","response":"HTTP 200 · 受付済み " + str(folio.receipt.number),"receipt":folio.receipt.duplicate(true),"changed":true,"duplicate":true,"minutes":0.0,"file":JSON.stringify(document, "", true),"journal":saved.get("hotel_journal", []).duplicate(true)}
	# A changed/tampered accepted folio must not be received a second time.
	if code == 200 and (str(folio.status) != "pending" or int(folio.balance) != int(folio.total)):
		return rejected(409, "folio_conflict")
	if code == 200 and saved.get("hotel_journal", []).any(func(entry): return entry is Dictionary and str(entry.get("action", "")) == "receive" and str(entry.get("receipt", {}).get("folio_id", "")) == id): return rejected(409, "folio_conflict")
	var attempt := {"folio_id":id,"code":code,"error":error,"day":day,"clock":clock,"device":DEVICE}
	document.last_attempt = attempt
	var journal: Array = saved.get("hotel_journal", []).duplicate(true)
	var result := {"ok":code == 200,"code":code,"error":error,"response":"HTTP %d · %s" % [code, error],"changed":true,"minutes":3.0}
	if code == 200:
		var receipt := {"number":"SH-%02d-204-0001" % day,"folio_id":id,"room":str(folio.room),"total":int(folio.total),"folio_sha256":_folio_hash(folio),"received_day":day,"received_clock":clock}
		folio.status = "received"; folio.balance = 0; folio.receipt = receipt
		journal.append({"action":"receive","receipt":receipt.duplicate(true)})
		result.receipt = receipt.duplicate(true); result.response = "HTTP 200 · 受付完了 " + str(receipt.number)
	else: journal.append({"action":"attempt","attempt":attempt.duplicate(true)})
	result.file = JSON.stringify(document, "", true)
	result.journal = journal
	return result
