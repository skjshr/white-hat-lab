class_name CompanyBilling
extends RefCounted

const VERSION := 1

static func ensure(state: Dictionary) -> bool:
	if not state.has("billing"):
		state.billing = {"version":VERSION,"next_invoice":1,"invoices":[],"payments":[]}
		return true
	if not state.billing is Dictionary: return false
	var billing: Dictionary = state.billing
	if billing.has("version") and _amount(billing.version) != VERSION: return false
	if billing.has("next_invoice") and _amount(billing.next_invoice) < 1: return false
	if billing.has("invoices") and not billing.invoices is Array: return false
	if billing.has("payments") and not billing.payments is Array: return false
	if not billing.has("version"): billing.version = VERSION
	if not billing.has("next_invoice"): billing.next_invoice = 1
	if not billing.has("invoices") or not billing.invoices is Array: billing.invoices = []
	if not billing.has("payments") or not billing.payments is Array: billing.payments = []
	return true

static func terms(offer: Dictionary) -> Dictionary:
	var tier := clampi(int(offer.get("tier", offer.get("grade", 1))), 1, 3)
	return {"days":tier - 1}

static func _amount(value: Variant) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return -1
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number > 2147483647.0 or number != floorf(number): return -1
	return roundi(number)

static func _signed_amount(value: Variant) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return -1
	var number := float(value)
	if not is_finite(number) or number < -2147483648.0 or number > 2147483647.0 or number != floorf(number): return -1
	return int(number)

static func _valid_signed_money(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return false
	var number := float(value)
	return is_finite(number) and number >= -2147483648.0 and number <= 2147483647.0 and number == floorf(number)

static func _valid_billing(state: Dictionary) -> bool:
	if not ensure(state) or (state.has("cash") and not _valid_signed_money(state.get("cash"))): return false
	var ids: Dictionary = {}; var refs: Dictionary = {}; var payment_ids: Dictionary = {}
	for invoice in state.billing.invoices:
		if not invoice is Dictionary: return false
		var id := str(invoice.get("id", "")); var suffix := id.trim_prefix("INV/")
		if not suffix.is_valid_int() or _amount(int(suffix)) < 1 or id != _invoice_id(int(suffix)) or ids.has(id): return false
		var fee := _amount(invoice.get("fee", -1)); var bonus := _amount(invoice.get("bonus", -1)); var baseline := _amount(invoice.get("baseline_bonus", -1)); var material := _amount(invoice.get("material_cost", -1)); var amount := _amount(invoice.get("amount", -1)); var days := _amount(invoice.get("payment_days", -1)); var material_billable := bool(invoice.get("material_billable", false))
		var expected_amount := fee + bonus + (material if material_billable else 0)
		if fee < 0 or bonus < 0 or baseline < 0 or material < 0 or amount < 0 or days < 0 or days > 2 or baseline > bonus or fee > 2147483647 - bonus or expected_amount > 2147483647 or amount != expected_amount: return false
		if str(invoice.get("contract_id", "")).is_empty() or _amount(invoice.get("created_day", -1)) < 0: return false
		for field in ["posted_day", "due_day", "paid_day"]:
			if not _valid_signed_money(invoice.get(field)): return false
		var status := str(invoice.get("status", "")); var posted := int(invoice.posted_day); var due := int(invoice.due_day); var paid := int(invoice.paid_day)
		if status == "draft" and (posted != -1 or due != -1 or paid != -1): return false
		if status in ["posted", "paid"] and (posted < int(invoice.created_day) or due != posted + days): return false
		if status == "posted" and paid != -1: return false
		if status == "paid" and (paid < due or str(invoice.get("reference", "")) != "BANK/%04d" % int(suffix)): return false
		if status not in ["draft", "posted", "paid"]: return false
		ids[id] = invoice
	for payment in state.billing.payments:
		if not payment is Dictionary: return false
		var invoice_id := str(payment.get("invoice_id", "")); var reference := str(payment.get("reference", "")); var amount := _amount(payment.get("amount", -1))
		if not ids.has(invoice_id) or payment_ids.has(invoice_id) or amount < 0 or refs.has(reference): return false
		var invoice: Dictionary = ids[invoice_id]
		if str(invoice.status) != "paid" or reference != str(invoice.reference) or amount != int(invoice.amount) or _amount(payment.get("day", -1)) != int(invoice.paid_day): return false
		refs[reference] = true; payment_ids[invoice_id] = true
	for id in ids:
		if str(ids[id].status) == "paid" and not payment_ids.has(id): return false
	return true

static func _invoice_id(counter: int) -> String:
	return "INV/%04d" % maxi(1, counter)

static func _find_invoice(state: Dictionary, id: String) -> Dictionary:
	for invoice in state.get("billing", {}).get("invoices", []):
		if invoice is Dictionary and str(invoice.get("id", "")) == id: return invoice
	return {}

static func create_draft(state: Dictionary, contract_id: String, contract: Dictionary, receipt: Dictionary) -> Dictionary:
	if not ensure(state): return {"ok":false,"error":"invalid_state"}
	if not state.get("history", []) is Array or not _valid_billing(state): return {"ok":false,"error":"invalid_state"}
	for existing in state.billing.invoices:
		if existing is Dictionary and str(existing.get("contract_id", "")) == contract_id:
			return {"ok":true,"error":"","invoice":existing.duplicate(true)}
	var fee := _amount(receipt.get("fee", 0)); var bonus := _amount(receipt.get("bonus", 0)); var baseline_bonus := _amount(receipt.get("baseline_bonus", 0)); var material_cost := _amount(receipt.get("material_cost", 0)); var material_billable := bool(receipt.get("material_billable", false)) and material_cost > 0
	var payment_days := _amount(contract.get("payment_days",0))
	var invoice_amount := fee + bonus + (material_cost if material_billable else 0)
	if contract_id.is_empty() or fee < 0 or bonus < 0 or baseline_bonus < 0 or material_cost < 0 or baseline_bonus > bonus or payment_days < 0 or payment_days > 2 or fee > 2147483647 - bonus or invoice_amount > 2147483647 or _amount(state.get("day", -1)) < 0: return {"ok":false,"error":"invalid_invoice"}
	if typeof(contract.get("payment_days",0)) == TYPE_FLOAT and float(contract.get("payment_days",0)) != float(payment_days): return {"ok":false,"error":"invalid_invoice"}
	var counter := maxi(1, int(state.billing.get("next_invoice", 1))); var max_counter := 0
	for existing in state.billing.invoices:
		if not existing is Dictionary: continue
		var existing_id := str(existing.get("id", "")); var suffix := existing_id.trim_prefix("INV/")
		if existing_id.begins_with("INV/") and suffix.is_valid_int(): max_counter = maxi(max_counter, int(suffix))
	counter = maxi(counter, max_counter + 1)
	if counter >= 2147483647: return {"ok":false,"error":"invalid_invoice"}
	var invoice_id := _invoice_id(counter)
	var invoice := {"id":invoice_id,"contract_id":contract_id,"client":str(receipt.get("client",contract.get("client", ""))),"title":str(receipt.get("title",contract.get("title", ""))),"fee":fee,"bonus":bonus,"baseline_bonus":baseline_bonus,"material_cost":material_cost,"material_billable":material_billable,"amount":invoice_amount,"payment_days":payment_days,"created_day":int(state.get("day",0)),"posted_day":-1,"due_day":-1,"paid_day":-1,"status":"draft"}
	state.billing.invoices.append(invoice); state.billing.next_invoice = counter + 1
	return {"ok":true,"error":"","invoice":invoice.duplicate(true)}

static func post(state: Dictionary, id: String) -> Dictionary:
	var trial: Dictionary = state.duplicate(true)
	var result := _post_mutation(trial, id)
	if not bool(result.get("ok", false)): return result
	if str(result.invoice.get("status", "")) == "draft": return result
	state.billing = trial.billing; state.cash = trial.cash; state.history = trial.history
	return result

static func _post_mutation(state: Dictionary, id: String) -> Dictionary:
	if not ensure(state) or not state.get("history") is Array or not _valid_signed_money(state.get("cash", null)) or _amount(state.get("day", -1)) < 0 or not _valid_billing(state): return {"ok":false,"error":"invalid_state"}
	var invoice := _find_invoice(state,id)
	if invoice.is_empty(): return {"ok":false,"error":"invoice_not_found"}
	var current_status := str(invoice.get("status", ""))
	if current_status in ["posted", "paid"]: return {"ok":true,"error":"","invoice":invoice.duplicate(true)}
	if current_status != "draft": return {"ok":false,"error":"invalid_invoice"}
	var amount := _amount(invoice.get("amount", -1)); var payment_days := _amount(invoice.get("payment_days", -1)); if amount < 0 or payment_days < 0 or payment_days > 2: return {"ok":false,"error":"invalid_invoice"}
	var day := int(state.get("day",0))
	if day < int(invoice.created_day) or day > 2147483647 - payment_days: return {"ok":false,"error":"invalid_invoice"}
	invoice.posted_day = day; invoice.due_day = day + payment_days
	invoice.status = "posted"
	if payment_days == 0:
		var settled := _settle_mutation(state, day)
		if not bool(settled.get("ok", false)): return settled
	return {"ok":true,"error":"","invoice":invoice.duplicate(true)}

static func settle_due(state: Dictionary, day: int) -> Dictionary:
	var trial: Dictionary = state.duplicate(true)
	var result := _settle_mutation(trial, day)
	if not bool(result.get("ok", false)): return result
	state.billing = trial.billing; state.cash = trial.cash; state.history = trial.history
	return result

static func _settle_mutation(state: Dictionary, day: int) -> Dictionary:
	if not ensure(state) or not state.get("history") is Array or not _valid_signed_money(state.get("cash", null)) or _amount(day) < 0 or not _valid_billing(state): return {"ok":false,"error":"invalid_state"}
	var due_total := 0
	for candidate in state.billing.invoices:
		if str(candidate.get("status", "")) != "posted" or int(candidate.get("posted_day", -1)) < 0 or int(candidate.get("due_day", -1)) > day: continue
		var candidate_amount := _amount(candidate.get("amount", -1)); if candidate_amount < 0 or due_total > 2147483647 - candidate_amount: return {"ok":false,"error":"invalid_invoice"}
		due_total += candidate_amount
	var current_cash := _signed_amount(state.get("cash", null)); if current_cash > 2147483647 - due_total: return {"ok":false,"error":"cash_overflow"}
	var paid_total := 0; var settled: Array = []
	for invoice in state.billing.invoices:
		if str(invoice.get("status", "")) != "posted" or int(invoice.get("posted_day", -1)) < 0 or int(invoice.get("due_day", -1)) < int(invoice.get("posted_day", -1)) or int(invoice.get("due_day", -1)) > day: continue
		var amount := _amount(invoice.get("amount", -1)); if amount < 0: return {"ok":false,"error":"invalid_invoice"}
		var suffix := str(invoice.get("id", "")).trim_prefix("INV/"); var reference := "BANK/%04d" % maxi(1, int(suffix) if suffix.is_valid_int() else 0)
		invoice.status = "paid"; invoice.paid_day = day; invoice.reference = reference; paid_total += amount
		var payment := {"invoice_id":str(invoice.id),"reference":reference,"day":day,"amount":amount,"client":str(invoice.get("client", ""))}
		state.billing.payments.append(payment); settled.append(payment.duplicate(true)); state.cash = int(state.get("cash",0)) + amount
		state.history.append({"kind":"invoice_payment","day":day,"amount":amount,"invoice_id":str(invoice.id),"reference":reference})
	return {"ok":true,"error":"","payments":settled,"paid_total":paid_total}

static func summary(state: Dictionary, day: int) -> Dictionary:
	var billing: Variant = state.get("billing", {})
	if not billing is Dictionary or not billing.get("invoices", []) is Array: return {"draft_total":0,"receivable_total":0,"paid_today":0,"due_next_day":0}
	var draft_total := 0; var receivable_total := 0; var paid_today := 0; var due_next_day := 0
	for invoice in billing.get("invoices", []):
		if not invoice is Dictionary: continue
		var amount := maxi(0,_amount(invoice.get("amount",0))); var status := str(invoice.get("status", ""))
		if status == "draft": draft_total += amount
		elif status == "posted":
			receivable_total += amount
			if _amount(invoice.get("due_day", -1)) == day + 1: due_next_day += amount
		elif status == "paid" and _amount(invoice.get("paid_day", -1)) == day: paid_today += amount
	return {"draft_total":draft_total,"receivable_total":receivable_total,"paid_today":paid_today,"due_next_day":due_next_day}

static func list(state: Dictionary) -> Array:
	var billing: Variant = state.get("billing", {})
	if not billing is Dictionary or not billing.get("invoices", []) is Array: return []
	var result: Array = []
	for invoice in billing.get("invoices", []):
		if invoice is Dictionary: result.append(invoice.duplicate(true))
	return result
