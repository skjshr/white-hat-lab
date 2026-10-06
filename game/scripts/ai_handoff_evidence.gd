extends RefCounted
## Approval facts from explicitly selected originals only. No world/policy lookup.

static func _missing() -> Dictionary:
	return {"state":"missing","record_id":"","original_id":"","detail":"","sources":[],"sources_known":false,"recipient":"","recipient_known":false,"contacts_scope":"","contacts_scope_known":false,"contact_ids":[],"contact_ids_known":false,"shipment_ids":[],"shipment_ids_known":false,"excluded_recipient":"","excluded_recipient_known":false}

static func _project(record_id: String, original: Dictionary) -> Dictionary:
	var result := _missing()
	var data_value: Variant = original.get("data", {})
	var data: Dictionary = data_value if data_value is Dictionary else {}
	result.state = "present"; result.record_id = record_id
	result.original_id = str(original.get("id", "")); result.detail = str(original.get("detail", ""))
	for pair in [["sources","approved_sources"],["contact_ids","approved_contact_ids"],["shipment_ids","approved_shipment_ids"]]:
		var key := str(pair[0]); var source := str(pair[1])
		result[key + "_known"] = data.get(source) is Array
		result[key] = data[source].duplicate(true) if data.get(source) is Array else []
	for pair in [["recipient","approved_recipient"],["contacts_scope","contacts_scope"],["excluded_recipient","excluded_recipient"]]:
		var key := str(pair[0]); var source := str(pair[1])
		result[key + "_known"] = data.get(source) is String
		result[key] = str(data[source]) if data.get(source) is String else ""
	return result

static func _is_approval(row: Dictionary, id: String) -> bool:
	return str(row.get("id", "")) == id and str(row.get("action", "")) == "consent_review" and int(row.get("status", 0)) == 200

static func build(records: Array, selected_ids: Array) -> Dictionary:
	var result := {"previous":_missing(),"current":_missing()}
	for value in records:
		if not value is Dictionary: continue
		var row: Dictionary = value; var id := str(row.get("id", ""))
		if id.is_empty() or id not in selected_ids: continue
		if _is_approval(row, "AI-401"):
			result.current = _project(id, row)
		elif str(row.get("action", "")) == "baseline_reference" and int(row.get("status", 0)) == 200:
			var data_value: Variant = row.get("data", {})
			if not data_value is Dictionary: continue
			var original_value: Variant = data_value.get("original")
			if not original_value is Dictionary or not _is_approval(original_value, "AI-301"): continue
			if data_value.has("source_record_id") and str(data_value.source_record_id) != str(original_value.id): continue
			result.previous = _project(id, original_value)
	return result
