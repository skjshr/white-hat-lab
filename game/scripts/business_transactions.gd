class_name BusinessTransactions
extends RefCounted

const Workspace = preload("res://scripts/business_workspace.gd")
const LIMIT := 256
const MAX_AMOUNT := 1000000000

static func rejected(code: int, error: String, field: String = "") -> Dictionary:
	return {"ok":false,"changed":false,"code":code,"error":error,"field":field}

static func _text(value: Variant, limit: int) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > limit: return false
	for forbidden in [",", "\n", "\r", "\t"]:
		if value.contains(forbidden): return false
	for index in value.length():
		if value.unicode_at(index) < 32: return false
	return true

static func _amount(value: Variant, signed_value := false) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return false
	return is_finite(float(value)) and float(value) == floorf(float(value)) and absf(float(value)) <= MAX_AMOUNT and (signed_value or float(value) >= 0)

static func _find(rows: Array, key: String, id: String) -> int:
	for i in rows.size():
		if str(rows[i].get(key, "")) == id: return i
	return -1

static func _next(rows: Array, key: String, prefix: String, first: int = 1) -> String:
	var number := maxi(1,first)
	while _find(rows, key, "%s%03d" % [prefix,number]) >= 0: number += 1
	return "%s%03d" % [prefix,number]

static func _csv(rows: Array, keys: Array) -> String:
	var lines: Array[String] = [",".join(keys)]
	for row in rows:
		var values: Array[String] = []
		for key in keys: values.append(str(row[key]))
		lines.append(",".join(values))
	return "\n".join(lines) + "\n"

## Produces a write set; only Game commits it with the owning VM and save.
static func plan(provider: Dictionary, action: String, args: Dictionary) -> Dictionary:
	if not bool(provider.get("available",false)): return rejected(503,"provider_unavailable")
	if not bool(provider.get("writable",true)): return rejected(403,"storage_readonly")
	if str(args.get("expected_revision","")) != Workspace.fingerprint(provider,true): return rejected(409,"conflict")
	var resource := "ledger" if action == "append_ledger" else "orders"
	var parsed := Workspace.handle_get(provider,resource)
	if not bool(parsed.get("ok",false)): return rejected(int(parsed.get("code",422)),str(parsed.get("error","invalid_source")))
	var data: Dictionary = parsed.data.duplicate(true)
	var writes := {}; var item := {}; var changed := true; var sequence := {}
	if action == "append_ledger":
		if not _text(args.get("date"),10): return rejected(422,"invalid_date","date")
		if not _amount(args.get("amount"),true): return rejected(422,"invalid_amount","amount")
		var rows: Array = data.ledger
		if rows.size() >= LIMIT: return rejected(429,"record_limit")
		var date := str(args.date); var last: Dictionary = rows.back() if not rows.is_empty() else {"date":"","closing":0}
		if date <= str(last.date): return rejected(409,"date_must_follow_ledger","date")
		var closing := int(last.closing) + int(args.amount)
		if closing < 0 or closing > MAX_AMOUNT: return rejected(422,"invalid_balance","amount")
		var line := "%s opening=%d closing=%d\n" % [date,int(last.closing),closing]
		if not bool(Workspace.parse_ledger(line).get("ok",false)): return rejected(422,"invalid_date","date")
		var source := Workspace._file(provider,"ledger.txt")
		writes[Workspace.LEDGER_FILE] = str(source.text).strip_edges()+"\n"+line
		item = {"date":date,"opening":int(last.closing),"closing":closing,"movement":int(args.amount)}
	elif action in ["create_customer","update_customer","delete_customer","create_order","update_order","delete_order"]:
		var customers: Array = data.customers; var orders: Array = data.orders
		var customer_op := action.ends_with("customer")
		var rows: Array = customers if customer_op else orders
		var key := "id" if customer_op else "order"
		var id := str(args.get("id","")); var index := _find(rows,key,id)
		if action.begins_with("create_"):
			if rows.size() >= LIMIT: return rejected(429,"record_limit")
			var sequence_key := "customer" if customer_op else "order"
			id = _next(rows,key,"C" if customer_op else "O",int(provider.get("sequences",{}).get(sequence_key,1)))
			sequence[sequence_key] = int(id.substr(1))+1
		elif index < 0: return rejected(404,"record_missing","id")
		if action.begins_with("delete_"):
			if customer_op and orders.any(func(row): return str(row.customer)==id): return rejected(409,"customer_has_orders","id")
			item = rows[index].duplicate(true); rows.remove_at(index)
		else:
			if customer_op:
				if not _text(args.get("name"),80): return rejected(422,"invalid_name","name")
				item = {"id":id,"name":str(args.name).strip_edges()}
			else:
				if _find(customers,"id",str(args.get("customer",""))) < 0: return rejected(422,"unknown_customer","customer")
				if not _amount(args.get("total")): return rejected(422,"invalid_amount","total")
				item = {"order":id,"customer":str(args.customer),"total":int(args.total)}
			if index >= 0:
				changed = rows[index] != item
				rows[index] = item
			else: rows.append(item)
		if customer_op: writes[Workspace.CUSTOMERS_FILE] = _csv(customers,["id","name"])
		else: writes[Workspace.ORDERS_FILE] = _csv(orders,["order","customer","total"])
	else: return rejected(400,"unknown_action")
	return {"ok":true,"changed":changed,"code":201 if action.begins_with("create_") or action=="append_ledger" else 200,"item":item,"writes":writes,"resource":resource,"sequence":sequence}
