extends RefCounted
class_name CustomerStock

## Pure customer-side stock model. The game owns persistence, cash, history and
## notifications; this module only validates and mutates the supplied state.
const UI = preload("res://scripts/ui_theme.gd")

const SKU := "gateway"
const MODEL := "WHG-2"
const SUPPLIER := "Minato Supply"
const UNIT_COST := 3200
const BACKUP_SKU := "backup_appliance"
const BACKUP_MODEL := "WHB-2"
const BACKUP_UNIT_COST := 4800
const MAX_CAPACITY := 6
const DELIVERY_WAIT_SECONDS := 30.0
const SHIPPING_SECONDS := 12.0
const STATUSES := ["queued", "ready", "carried", "stored", "staged", "shipping", "delivered"]

static func catalog() -> Array:
	return [_product(SKU), _product(BACKUP_SKU)]

static func product(sku: String = SKU) -> Dictionary:
	return _product(sku)

static func _product(sku: String) -> Dictionary:
	if sku == BACKUP_SKU:
		return {"sku":BACKUP_SKU,"title":UI.copy("stock_backup_appliance"),"summary":UI.copy("stock_backup_summary"),"icon":"stock_backup","model":BACKUP_MODEL,"supplier":SUPPLIER,"unit_cost":BACKUP_UNIT_COST,"capacity":MAX_CAPACITY,"id_prefix":"stock-nas-","serial_prefix":"WHB-"}
	return {"sku":SKU,"title":UI.copy("stock_gateway"),"summary":UI.copy("stock_gateway_summary"),"icon":"stock_gateway","model":MODEL,"supplier":SUPPLIER,"unit_cost":UNIT_COST,"capacity":MAX_CAPACITY,"id_prefix":"stock-fw-","serial_prefix":"WHG-"}

static func ensure(state: Dictionary) -> void:
	if not state.has("customer_stock"):
		state.customer_stock = {"next_serial":1,"units":[]}

static func _stock(state: Dictionary) -> Dictionary:
	var stock = state.get("customer_stock", null)
	return stock if stock is Dictionary else {}

static func _new_unit(sku: String, serial_number: int, ordered_day: int, receiving_slot: int) -> Dictionary:
	var item := _product(sku)
	var suffix := "%06d" % serial_number
	return {"id":str(item.id_prefix)+suffix,"serial":str(item.serial_prefix)+suffix,"sku":sku,"model":item.model,"supplier":item.supplier,"unit_cost":int(item.unit_cost),"status":"queued","elapsed_seconds":0.0,"ordered_day":ordered_day,"contract_id":"","target_index":-1,"shelf_slot":-1,"receiving_slot":receiving_slot,"box_position":ready_position(receiving_slot)}

static func _receiving_slot(state: Dictionary) -> int:
	var used: Array = []
	for item in units(state):
		if str(item.get("status", "")) in ["queued", "ready"]: used.append(int(item.get("receiving_slot", -1)))
	for slot in MAX_CAPACITY:
		if slot not in used: return slot
	return -1

static func units(state: Dictionary) -> Array:
	var stock := _stock(state)
	return stock.get("units", []).duplicate(true) if stock.get("units", []) is Array else []

static func unit(state: Dictionary, id: String) -> Dictionary:
	var stock := _stock(state)
	if not stock.get("units", []) is Array: return {}
	for item in stock.units:
		if item is Dictionary and str(item.get("id", "")) == id: return item
	return {}

static func _error(code: String) -> Dictionary:
	return {"ok":false,"error":code.trim_prefix("stock_error_")}

static func _capacity_used(state: Dictionary) -> int:
	var count := 0
	for item in units(state):
		if str(item.get("status", "")) not in ["shipping", "delivered"]: count += 1
	return count

static func active_count(state: Dictionary) -> int:
	return _capacity_used(state)

static func purchaseable(state: Dictionary, quantity: int = 1, sku: String = SKU) -> bool:
	var stock := _stock(state)
	var item := _product(sku)
	return not stock.is_empty() and str(item.sku) == sku and bool(state.get("career_mode", false)) and quantity >= 1 and quantity <= 3 and _capacity_used(state) + quantity <= MAX_CAPACITY and typeof(state.get("cash", null)) in [TYPE_INT, TYPE_FLOAT] and int(state.cash) >= int(item.unit_cost) * quantity and stock.get("units", []) is Array and state.get("history", []) is Array

static func purchase(state: Dictionary, quantity: int, sku: String = SKU) -> Dictionary:
	var stock := _stock(state)
	if stock.is_empty() or not stock.get("units", []) is Array: return _error("stock_error_checks")
	if not bool(state.get("career_mode", false)): return _error("stock_error_career")
	var item := _product(sku)
	if str(item.sku) != sku: return _error("stock_error_sku")
	if quantity < 1 or quantity > 3: return _error("stock_error_quantity")
	if _capacity_used(state) + quantity > MAX_CAPACITY: return _error("stock_error_capacity")
	var total_cost := int(item.unit_cost) * quantity
	if typeof(state.get("cash", null)) not in [TYPE_INT, TYPE_FLOAT] or int(state.cash) < total_cost: return _error("stock_error_cash")
	if not state.get("history", []) is Array: return _error("stock_error_checks")
	var next_serial := int(stock.get("next_serial", 0))
	if next_serial < 1: return _error("stock_error_checks")
	var ids: Array[String] = []
	for i in quantity:
		var serial_number := next_serial + i
		var receiving_slot := _receiving_slot(state)
		if receiving_slot < 0: return _error("stock_error_capacity")
		var created := _new_unit(sku, serial_number, int(state.get("day", 0)), receiving_slot)
		stock.units.append(created); ids.append(str(created.id))
	stock.next_serial = next_serial + quantity
	state.cash = int(state.cash) - total_cost
	state.history.append({"kind":"inventory_purchase","day":int(state.get("day", 0)),"amount":total_cost,"sku":sku,"serials":ids.duplicate()})
	return {"ok":true,"error":"","ids":ids,"total":total_cost,"sku":sku}

static func advance(state: Dictionary, delta: float, wait_seconds: float = DELIVERY_WAIT_SECONDS) -> Dictionary:
	var stock := _stock(state)
	if stock.is_empty() or not stock.get("units", []) is Array or not is_finite(delta) or delta < 0.0 or not is_finite(wait_seconds) or wait_seconds <= 0.0: return {"progressed":false,"arrived":false}
	var progressed := false
	var arrived := false
	for item in stock.units:
		if not item is Dictionary or str(item.get("status", "")) != "queued": continue
		var previous := float(item.get("elapsed_seconds", 0.0))
		item.elapsed_seconds = minf(wait_seconds, previous + delta)
		if item.elapsed_seconds > previous: progressed = true
		if item.elapsed_seconds >= wait_seconds:
			item.status = "ready"; item.box_position = ready_position(int(item.get("receiving_slot", 0))); arrived = true
	for item in stock.units:
		if not item is Dictionary or str(item.get("status", "")) != "shipping": continue
		var previous_shipping := float(item.get("elapsed_seconds", 0.0))
		item.elapsed_seconds = minf(SHIPPING_SECONDS, previous_shipping + delta)
		if item.elapsed_seconds > previous_shipping: progressed = true
		if item.elapsed_seconds >= SHIPPING_SECONDS:
			item.status = "delivered"; arrived = true
	return {"progressed":progressed,"arrived":arrived}

static func _legacy_delivery_busy(state: Dictionary) -> bool:
	for order in state.get("delivery_orders", []):
		if order is Dictionary and str(order.get("status", "")) in ["carried", "placing"]: return true
	return false

static func take(state: Dictionary, id: String) -> Dictionary:
	if _legacy_delivery_busy(state): return _error("stock_error_held")
	var stock := _stock(state)
	if stock.is_empty() or not stock.get("units", []) is Array: return _error("stock_error_checks")
	for item in stock.units:
		if item is Dictionary and str(item.get("status", "")) == "carried" and str(item.get("id", "")) != id: return _error("stock_error_held")
	for item in stock.units:
		if item is Dictionary and str(item.get("id", "")) == id:
			if str(item.get("status", "")) not in ["ready", "stored", "staged"]: return _error("stock_error_status")
			item.status = "carried"; item.shelf_slot = -1; item.receiving_slot = -1
			return {"ok":true,"error":"","unit":item.duplicate(true)}
	return _error("stock_error_unknown")

static func store(state: Dictionary, id: String) -> Dictionary:
	var stock := _stock(state)
	if stock.is_empty() or not stock.get("units", []) is Array: return _error("stock_error_checks")
	for item in stock.units:
		if item is Dictionary and str(item.get("id", "")) == id:
			if str(item.get("status", "")) != "carried" or not str(item.get("contract_id", "")).is_empty(): return _error("stock_error_status")
			var used: Array = []
			for other in stock.units:
				if other is Dictionary and int(other.get("shelf_slot", -1)) >= 0: used.append(int(other.shelf_slot))
			var slot := -1
			for candidate in MAX_CAPACITY:
				if candidate not in used: slot = candidate; break
			if slot < 0: return _error("stock_error_position")
			item.status = "stored"; item.shelf_slot = slot; item.box_position = shelf_position(slot)
			return {"ok":true,"error":"","unit":item.duplicate(true)}
	return _error("stock_error_unknown")

static func stage(state: Dictionary, id: String, contract_id: String, target_index: int) -> Dictionary:
	var stock := _stock(state)
	if stock.is_empty() or not stock.get("units", []) is Array: return _error("stock_error_checks")
	if contract_id.is_empty() or target_index < 0: return _error("stock_error_contract")
	for item in stock.units:
		if not item is Dictionary: continue
		if str(item.get("id", "")) == id: continue
		if str(item.get("status", "")) == "staged": return _error("stock_error_assigned")
		if not str(item.get("contract_id", "")).is_empty() and str(item.get("contract_id", "")) == contract_id and int(item.get("target_index", -1)) == target_index: return _error("stock_error_assigned")
	for item in stock.units:
		if item is Dictionary and str(item.get("id", "")) == id:
			if str(_product(str(item.get("sku", ""))).sku) != str(item.get("sku", "")): return _error("stock_error_sku")
			if str(item.get("status", "")) != "carried": return _error("stock_error_status")
			if not str(item.get("contract_id", "")).is_empty() and str(item.contract_id) != contract_id: return _error("stock_error_contract")
			item.status = "staged"; item.contract_id = contract_id; item.target_index = target_index; item.shelf_slot = -1; item.receiving_slot = -1; item.box_position = staged_position(target_index)
			return {"ok":true,"error":"","unit":item.duplicate(true)}
	return _error("stock_error_unknown")

static func dispatch(state: Dictionary, id: String) -> Dictionary:
	var live := unit(state, id)
	if live.is_empty(): return _error("stock_error_unknown")
	if str(_product(str(live.get("sku", ""))).sku) != str(live.get("sku", "")): return _error("stock_error_hardware")
	if str(live.get("status", "")) != "carried" or str(live.get("contract_id", "")).is_empty() or int(live.get("target_index", -1)) < 0: return _error("stock_error_status")
	live.status = "shipping"; live.elapsed_seconds = 0.0; live.shelf_slot = -1; live.receiving_slot = -1
	return {"ok":true,"error":"","unit":live.duplicate(true)}

static func assigned(state: Dictionary, contract_id: String, target_index: int = 0) -> Dictionary:
	for item in units(state):
		if str(item.get("contract_id", "")) == contract_id and int(item.get("target_index", -1)) == target_index: return item
	return {}

static func ready_position(index: int) -> Array:
	var i := maxi(0, index) % MAX_CAPACITY
	return [-2.8 + float(i % 3) * 0.7, 0.16, 3.1 + float(floori(float(i) / 3.0)) * 0.75]

static func shelf_position(slot: int) -> Array:
	var i := clampi(slot, 0, MAX_CAPACITY - 1)
	return [5.4, 0.425 + float(floori(float(i) / 3.0)) * 0.605, 0.87 + float(i % 3) * 0.33]

static func staged_position(target_index: int) -> Array:
	return [0.05, 0.92, -1.1]

static func _integral(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value))

static func _suffix(value: Variant, prefix: String) -> int:
	if typeof(value) != TYPE_STRING or not str(value).begins_with(prefix): return -1
	var tail := str(value).substr(prefix.length())
	if tail.length() != 6 or not tail.is_valid_int(): return -1
	return int(tail)

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _integral(value.get("next_serial", null)) or int(value.next_serial) < 1 or not value.get("units", []) is Array: return false
	var ids := {}; var serials := {}; var max_serial := 0
	var carried_count := 0; var staged_count := 0; var active_count := 0
	var shelf_slots := {}; var receiving_slots := {}
	for item in value.units:
		if not item is Dictionary: return false
		for key in ["id","serial","sku","model","supplier","status","contract_id"]:
			if typeof(item.get(key, null)) != TYPE_STRING: return false
		var product := _product(str(item.sku))
		if str(product.sku) != str(item.sku) or str(item.model) != str(product.model) or str(item.supplier) != SUPPLIER or str(item.status) not in STATUSES: return false
		var id_serial := _suffix(item.id, str(product.id_prefix)); var serial_number := _suffix(item.serial, str(product.serial_prefix))
		if id_serial < 1 or serial_number != id_serial or ids.has(str(item.id)) or serials.has(str(item.serial)): return false
		ids[str(item.id)] = true; serials[str(item.serial)] = true; max_serial = maxi(max_serial, id_serial)
		if typeof(item.get("unit_cost", null)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(item.unit_cost)) or float(item.unit_cost) != float(product.unit_cost): return false
		if typeof(item.get("elapsed_seconds", null)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(item.elapsed_seconds)) or float(item.elapsed_seconds) < 0.0: return false
		for key in ["ordered_day","target_index","shelf_slot","receiving_slot"]:
			if not _integral(item.get(key, null)): return false
		var target_index := int(item.target_index); var shelf_slot := int(item.shelf_slot); var receiving_slot := int(item.receiving_slot)
		if int(item.ordered_day) < 0 or target_index < -1 or shelf_slot < -1 or receiving_slot < -1: return false
		if shelf_slot >= MAX_CAPACITY or receiving_slot >= MAX_CAPACITY: return false
		if item.get("box_position",null) is not Array or item.box_position.size() != 3: return false
		for coordinate in item.box_position:
			if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)): return false
		if str(item.contract_id).is_empty() != (target_index < 0): return false
		var status := str(item.status)
		if status == "stored":
			if shelf_slot < 0 or shelf_slots.has(shelf_slot): return false
			shelf_slots[shelf_slot] = true
		elif shelf_slot != -1: return false
		if status in ["queued", "ready"]:
			if receiving_slot >= 0:
				if receiving_slots.has(receiving_slot): return false
				receiving_slots[receiving_slot] = true
		elif receiving_slot != -1: return false
		if status not in ["shipping", "delivered"]: active_count += 1
		if status == "carried": carried_count += 1
		if status == "staged": staged_count += 1
	if int(value.next_serial) <= max_serial or carried_count > 1 or staged_count > 1 or active_count > MAX_CAPACITY: return false
	return true
