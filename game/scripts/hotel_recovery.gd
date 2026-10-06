extends RefCounted
## One newly received reservation; the previous guest's settled folio is immutable.
const REMEDIATION = preload("res://scripts/endpoint_remediation.gd")
const PATH := "/srv/hotel/reservations.json"
const FOLIO_PATH := "/srv/hotel/folios.json"
const EVIDENCE_PATH := "/handoff/evidence.log"
const ID := "R-204-NEXT"
const DEVICE := "pc_a"

static func enabled(saved: Dictionary) -> bool:
	var scenario: Dictionary = saved.get("scenario", {})
	return int(scenario.get("hotel_workflow_version", 0)) == 2 and bool(scenario.get("hotel_recovery", false))

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

static func _source(document: Dictionary) -> Dictionary:
	return {"id":document.get("id", ""),"room":document.get("room", ""),"guest":document.get("guest", ""),"arrival_day":document.get("arrival_day", 0),"nights":document.get("nights", 0)}

static func _source_hash(document: Dictionary) -> String:
	return _canonical(_source(document)).sha256_text()

static func initialize(saved: Dictionary) -> void:
	if not enabled(saved) or saved.get("fs", {}).has(PATH) or saved.has("reservation_authorization"): return
	var accepted_day := int(saved.get("scenario", {}).get("hotel_recovery_day", 0))
	if accepted_day < 1: return
	var document := {"version":1,"id":ID,"room":"204","guest":"雨宮 渚","arrival_day":accepted_day + 1,"nights":1,"status":"pending","bookingno":"","receipt":{},"last_attempt":{}}
	saved.fs[PATH] = JSON.stringify(document, "", true)
	saved.reservation_journal = []
	saved.reservation_authorization = {"version":1,"source_sha256":_source_hash(document)}

static func _document(saved: Dictionary) -> Dictionary:
	var text := str(saved.get("fs", {}).get(PATH, ""))
	if text.is_empty(): return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1: return {}
	if not parsed.has_all(["id", "room", "guest", "arrival_day", "nights", "status", "bookingno", "receipt", "last_attempt"]): return {}
	if str(parsed.id) != ID or str(parsed.room).is_empty() or str(parsed.guest).is_empty() or str(parsed.status) not in ["pending", "imported"]: return {}
	for field in ["arrival_day", "nights"]:
		if typeof(parsed[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(parsed[field])) or float(parsed[field]) != floorf(float(parsed[field])) or int(parsed[field]) < 1: return {}
	if not parsed.receipt is Dictionary or not parsed.last_attempt is Dictionary: return {}
	return parsed

static func _source_matches(saved: Dictionary, document: Dictionary) -> bool:
	var authority: Variant = saved.get("reservation_authorization", {})
	return not document.is_empty() and authority is Dictionary and int(authority.get("version", 0)) == 1 and str(authority.get("source_sha256", "")) == _source_hash(document)

static func _imported(saved: Dictionary, document: Dictionary) -> bool:
	if not _source_matches(saved, document) or str(document.get("status", "")) != "imported": return false
	var receipt: Dictionary = document.get("receipt", {})
	var number := str(document.get("bookingno", ""))
	if number.is_empty() or str(receipt.get("number", "")) != number or str(receipt.get("bookingno", "")) != number or str(receipt.get("reservation_id", "")) != ID or str(receipt.get("source_sha256", "")) != _source_hash(document): return false
	for entry in saved.get("reservation_journal", []):
		if entry is Dictionary and str(entry.get("action", "")) == "import" and _canonical(entry.get("receipt", {})) == _canonical(receipt): return true
	return false

static func snapshot(saved: Dictionary) -> Dictionary:
	if not enabled(saved): return {"enabled":false}
	var document := _document(saved)
	var result: Dictionary = document.duplicate(true)
	result.merge({"enabled":true,"id":ID,"device":DEVICE,"isolated":str(saved.get("applied", {}).get(DEVICE, "")) == "isolated","connected":bool(saved.get("connected", false)) and bool(saved.get("active", false)),"business_available":bool(REMEDIATION.status(saved, DEVICE).get("business_available", false)),"source":PATH,"error":"data_unavailable" if document.is_empty() else ("reservation_changed" if not _source_matches(saved, document) else "")}, true)
	if document.is_empty():
		result.merge({"room":"","guest":"","arrival_day":0,"nights":0,"status":"pending","bookingno":"","receipt":{},"last_attempt":{}})
	elif str(document.status) == "imported" and not _imported(saved, document):
		result.error = "receipt_mismatch"
		# A receipt-looking guest file is not a successful server-side import.
		result.status = "pending"
	return result

static func accepted(saved: Dictionary) -> bool:
	return enabled(saved) and _imported(saved, _document(saved))

static func preserved(saved: Dictionary) -> bool:
	if not enabled(saved): return false
	var handoff: Variant = saved.get("scenario", {}).get("hotel_handoff", {})
	if not handoff is Dictionary or not handoff.get("hotel_journal") is Array: return false
	var folio_content := str(handoff.get("folio_content", ""))
	var evidence := str(handoff.get("evidence_content", ""))
	var receipt_number := str(handoff.get("source_folio_receipt", ""))
	if folio_content.is_empty() or evidence.is_empty() or receipt_number.is_empty() or str(handoff.get("source_contract_id", "")).is_empty(): return false
	if str(saved.get("fs", {}).get(FOLIO_PATH, "")) != folio_content or str(saved.get("fs", {}).get(EVIDENCE_PATH, "")) != evidence or evidence.sha256_text() != str(handoff.get("evidence_sha256", "")): return false
	if _canonical(saved.get("hotel_journal", [])) != _canonical(handoff.hotel_journal): return false
	var document: Variant = JSON.parse_string(folio_content)
	if not document is Dictionary or not document.get("folios") is Array: return false
	for folio in document.folios:
		if folio is Dictionary and str(folio.get("id", "")) == "F-204":
			return str(folio.get("status", "")) == "received" and int(folio.get("balance", -1)) == 0 and folio.get("receipt") is Dictionary and str(folio.receipt.get("number", "")) == receipt_number
	return false

static func outcome(saved: Dictionary) -> Dictionary:
	if not enabled(saved): return {}
	var document := _document(saved)
	var result := _source(document)
	result.status = "imported" if accepted(saved) else "pending"
	result.bookingno = str(document.get("bookingno", ""))
	result.receipt = document.get("receipt", {}).duplicate(true)
	result.handoff_preserved = preserved(saved)
	return result

static func rejected(code: int, error: String) -> Dictionary:
	return {"ok":false,"code":code,"error":error,"response":"HTTP %d · %s" % [code, error],"changed":false}

## Game writes file/path and reservation_journal in its existing save transaction.
## Transport and business availability gate synchronization; malware clearance
## is the independent security acceptance gate, not a magic application lock.
static func plan(saved: Dictionary, id: String, day: int, clock: String) -> Dictionary:
	if not enabled(saved): return rejected(404, "unsupported_workflow")
	if id != ID: return rejected(404, "reservation_missing")
	var document := _document(saved)
	if document.is_empty(): return rejected(422, "data_unavailable")
	if not _source_matches(saved, document): return rejected(409, "reservation_changed")
	var code := 200
	var error := ""
	if not bool(saved.get("connected", false)): code = 503; error = "not_connected"
	elif not bool(saved.get("active", false)): code = 503; error = "service_unavailable"
	elif str(saved.get("applied", {}).get(DEVICE, "")) == "isolated": code = 403; error = "endpoint_isolated"
	elif str(saved.get("applied", {}).get(DEVICE, "")) != "connected": code = 503; error = "endpoint_unavailable"
	elif not bool(REMEDIATION.status(saved, DEVICE).get("business_available", false)): code = 503; error = "business_unavailable"
	var journal: Array = saved.get("reservation_journal", []).duplicate(true)
	var duplicate := code == 200 and _imported(saved, document)
	if code == 200 and not duplicate:
		if str(document.status) != "pending" or not document.receipt.is_empty() or not str(document.bookingno).is_empty(): return rejected(409, "reservation_conflict")
		if journal.any(func(entry): return entry is Dictionary and str(entry.get("action", "")) == "import"): return rejected(409, "reservation_conflict")
	var attempt := {"id":ID,"code":code,"error":error,"day":day,"clock":clock,"device":DEVICE}
	document.last_attempt = attempt
	var result := {"ok":code == 200,"code":code,"error":error,"response":"HTTP %d · %s" % [code, error],"changed":true,"minutes":0.0 if duplicate else 3.0,"path":PATH,"duplicate":duplicate}
	if code == 200:
		if not duplicate:
			var number := "RS-%02d-204-0001" % int(document.arrival_day)
			var receipt := {"number":number,"bookingno":number,"reservation_id":ID,"room":str(document.room),"guest":str(document.guest),"arrival_day":int(document.arrival_day),"nights":int(document.nights),"received_day":day,"received_clock":clock,"source_sha256":_source_hash(document)}
			document.status = "imported"; document.bookingno = number; document.receipt = receipt
			journal.append({"action":"import","receipt":receipt.duplicate(true)})
		result.receipt = document.receipt.duplicate(true)
		result.response = "HTTP 200 · 予約取込済み " + str(document.bookingno)
	else: journal.append({"action":"attempt","attempt":attempt.duplicate(true)})
	result.file = JSON.stringify(document, "", true)
	result.journal = journal
	return result
