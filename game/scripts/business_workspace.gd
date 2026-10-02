class_name BusinessWorkspace
extends RefCounted

## Read-only parser for the customer's small sales and accounting workspace.
## The VM supplies the provider filesystem; this class never mutates it.
const CUSTOMERS_FILE := "/srv/data/customers.csv"
const ORDERS_FILE := "/srv/data/orders.csv"
const LEDGER_FILE := "/srv/data/ledger.txt"

static func _file(provider: Dictionary, name: String) -> Dictionary:
	var fs: Dictionary = provider.get("fs", {}) if provider.get("fs", {}) is Dictionary else {}
	for key in [name, "/srv/data/" + name]:
		if fs.has(key): return {"ok":true,"text":str(fs[key])}
	return {"ok":false,"code":404,"error":"missing_file"}

static func _csv(text: String, expected: Array, file_name: String) -> Dictionary:
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	if lines.is_empty() or lines[0] != ",".join(expected): return {"ok":false,"code":422,"error":"malformed_%s_header" % file_name}
	var rows: Array = []
	for line in lines.slice(1):
		if line.is_empty(): return {"ok":false,"code":422,"error":"malformed_%s_row" % file_name}
		var fields := line.split(",", true)
		var invalid := false
		for value in fields:
			if str(value).is_empty() or str(value).contains("\n"): invalid = true
		if fields.size() != expected.size() or invalid:
			return {"ok":false,"code":422,"error":"malformed_%s_row" % file_name}
		rows.append(fields)
	return {"ok":true,"rows":rows}

static func parse_customers(text: String) -> Dictionary:
	var parsed := _csv(text, ["id","name"], "customers")
	if not parsed.ok: return parsed
	var seen: Dictionary = {}; var rows: Array = []
	for fields in parsed.rows:
		var id := str(fields[0])
		if seen.has(id): return {"ok":false,"code":422,"error":"duplicate_customer"}
		seen[id] = true; rows.append({"id":id,"name":str(fields[1])})
	return {"ok":true,"rows":rows,"by_id":seen}

static func parse_orders(text: String, customers: Dictionary) -> Dictionary:
	var parsed := _csv(text, ["order","customer","total"], "orders")
	if not parsed.ok: return parsed
	var ids: Dictionary = customers.get("by_id", {})
	var seen: Dictionary = {}; var rows: Array = []
	for fields in parsed.rows:
		var order_id := str(fields[0]); var customer_id := str(fields[1]); var total_text := str(fields[2])
		if seen.has(order_id) or not ids.has(customer_id) or not total_text.is_valid_int(): return {"ok":false,"code":422,"error":"malformed_orders_row"}
		var total := int(total_text)
		if total < 0: return {"ok":false,"code":422,"error":"malformed_orders_total"}
		seen[order_id] = true; rows.append({"order":order_id,"customer":customer_id,"total":total})
	return {"ok":true,"rows":rows}

static func parse_ledger(text: String) -> Dictionary:
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	if lines.is_empty(): return {"ok":false,"code":422,"error":"malformed_ledger"}
	var rows: Array = []; var seen_dates: Dictionary = {}
	for line in lines:
		var parts := line.split(" ", false)
		if parts.size() != 3 or str(parts[1]).count("=") != 1 or str(parts[2]).count("=") != 1 or str(parts[1]).get_slice("=",0) != "opening" or str(parts[2]).get_slice("=",0) != "closing":
			return {"ok":false,"code":422,"error":"malformed_ledger"}
		var date := str(parts[0]); var opening_text := str(parts[1]).get_slice("=",1); var closing_text := str(parts[2]).get_slice("=",1)
		var date_parts := date.split("-")
		if date_parts.size() != 3 or date_parts[0].length() != 4 or date_parts[1].length() != 2 or date_parts[2].length() != 2 or not date_parts[0].is_valid_int() or not date_parts[1].is_valid_int() or not date_parts[2].is_valid_int() or not opening_text.is_valid_int() or not closing_text.is_valid_int():
			return {"ok":false,"code":422,"error":"malformed_ledger"}
		var year := int(date_parts[0]); var month := int(date_parts[1]); var day := int(date_parts[2]); var leap := year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
		var month_days := [31,29 if leap else 28,31,30,31,30,31,31,30,31,30,31]
		if year < 1 or month < 1 or month > 12 or day < 1 or day > int(month_days[month - 1]) or seen_dates.has(date): return {"ok":false,"code":422,"error":"malformed_ledger"}
		seen_dates[date] = true; rows.append({"date":date,"opening":int(opening_text),"closing":int(closing_text),"movement":int(closing_text)-int(opening_text)})
	return {"ok":true,"rows":rows}

static func _json_response(provider: Dictionary, resource: String) -> Dictionary:
	var external: Dictionary = provider.get("external_storage", {}) if provider.get("external_storage", {}) is Dictionary else {}
	if external.is_empty(): external = {"enabled":false,"ok":bool(provider.get("available", false)),"code":200 if bool(provider.get("available", false)) else 503,"error":str(provider.get("error", "")),"host":"files01.client.test","share":"share","path":"/srv/share/partner-order.csv","writable":false}
	if not bool(provider.get("available", false)):
		var provider_error := str(provider.get("error", "provider_unavailable"))
		var denied := {"ok":false,"code":403 if provider_error == "storage_denied" else 503,"error":provider_error}; denied.external_storage = external; return denied
	var customers_file := _file(provider, "customers.csv")
	var orders_file := _file(provider, "orders.csv")
	var ledger_file := _file(provider, "ledger.txt")
	if resource == "customers":
		if not customers_file.ok: customers_file.external_storage = external; return customers_file
		var customers := parse_customers(str(customers_file.text)); if not customers.ok: customers.external_storage = external; return customers
		return {"ok":true,"code":200,"data":{"customers":customers.rows,"sha256":str(customers_file.text).sha256_text()},"external_storage":external}
	if resource == "orders":
		if not customers_file.ok: customers_file.external_storage = external; return customers_file
		if not orders_file.ok: orders_file.external_storage = external; return orders_file
		var customers := parse_customers(str(customers_file.text)); if not customers.ok: customers.external_storage = external; return customers
		var orders := parse_orders(str(orders_file.text), customers); if not orders.ok: orders.external_storage = external; return orders
		return {"ok":true,"code":200,"data":{"customers":customers.rows,"orders":orders.rows,"sha256":str(orders_file.text).sha256_text()},"external_storage":external}
	if resource == "ledger":
		if not ledger_file.ok: ledger_file.external_storage = external; return ledger_file
		var ledger := parse_ledger(str(ledger_file.text)); if not ledger.ok: ledger.external_storage = external; return ledger
		return {"ok":true,"code":200,"data":{"ledger":ledger.rows,"sha256":str(ledger_file.text).sha256_text()},"external_storage":external}
	return {"ok":false,"code":404,"error":"unknown_resource","external_storage":external}

static func handle_get(provider: Dictionary, resource: String) -> Dictionary:
	return _json_response(provider, resource)

static func fingerprint(provider: Dictionary, include_shared: bool = false) -> String:
	var fs: Dictionary = provider.get("fs", {}) if provider.get("fs", {}) is Dictionary else {}
	var payload := {"available":bool(provider.get("available",false)),"customers":str(fs.get(CUSTOMERS_FILE,fs.get("customers.csv",""))),"orders":str(fs.get(ORDERS_FILE,fs.get("orders.csv",""))),"ledger":str(fs.get(LEDGER_FILE,fs.get("ledger.txt","")))}
	if include_shared:
		payload.error = str(provider.get("error", "")); payload.customers = str(fs.get(CUSTOMERS_FILE,fs.get("/srv/share/customers.csv", ""))); payload.orders = str(fs.get(ORDERS_FILE,fs.get("/srv/share/partner-order.csv", ""))); payload.partner_order = str(fs.get("/srv/share/partner-order.csv", "")); payload.external_storage = provider.get("external_storage", {}).duplicate(true) if provider.get("external_storage", {}) is Dictionary else {}
		payload.customers_exists = fs.has("/srv/share/customers.csv")
		payload.orders_exists = fs.has("/srv/share/partner-order.csv")
	return JSON.stringify(payload,"",true).sha256_text()
