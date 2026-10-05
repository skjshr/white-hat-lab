extends RefCounted

## Pure comparison of two CSV snapshots. No Game, VM, or scene dependencies.
const MAX_INPUT_BYTES := 2_000_000
const MAX_ROWS := 10_000
const MAX_COLUMNS := 256
const MAX_CELLS := 500_000
const ID_HEADERS := ["id", "order", "order_id", "customer_id"]

static func compare(before: String, after: String) -> Dictionary:
	var empty := _empty_result(before, after)
	if before.to_utf8_buffer().size() > MAX_INPUT_BYTES or after.to_utf8_buffer().size() > MAX_INPUT_BYTES:
		empty.error = "input_too_large"
		return empty
	var before_parsed := _parse_csv(before)
	var after_parsed := _parse_csv(after)
	if not str(before_parsed.error).is_empty() or not str(after_parsed.error).is_empty():
		empty.error = str(before_parsed.error) if not str(before_parsed.error).is_empty() else str(after_parsed.error)
		return empty
	var before_rows: Array = before_parsed.rows
	var after_rows: Array = after_parsed.rows
	if before_rows.size() > MAX_ROWS or after_rows.size() > MAX_ROWS:
		empty.error = "too_many_rows"
		return empty
	var before_header: Array = before_rows[0] if not before_rows.is_empty() else []
	var after_header: Array = after_rows[0] if not after_rows.is_empty() else []
	var before_width := _max_width(before_rows)
	var after_width := _max_width(after_rows)
	if before_width > MAX_COLUMNS or after_width > MAX_COLUMNS:
		empty.error = "too_many_columns"
		return empty
	if int(before_parsed.cell_count) + int(after_parsed.cell_count) > MAX_CELLS:
		empty.error = "too_many_cells"
		return empty

	var columns := _align_columns(before_header, after_header, before_width, after_width)
	var match_info := _row_match_mode(before_rows, after_rows, before_header, after_header)
	var pairs := _pair_rows(before_rows, after_rows, match_info)
	var moved_keys := _moved_keys(pairs, before_rows, after_rows, str(match_info.mode), int(match_info.key_index))
	var rows: Array = []
	var counts := {"added":0,"removed":0,"changed":0,"moved":0,"cells":0}
	for pair in pairs:
		var bi: int = int(pair.before_index)
		var ai: int = int(pair.after_index)
		var kind := "added" if bi == 0 else "removed" if ai == 0 else "unchanged"
		var row_moved := false
		if bi > 0 and ai > 0 and str(match_info.mode) == "key":
			row_moved = moved_keys.has(str(before_rows[bi][int(match_info.key_index)]))
		var cells: Array = []
		var row_changed := false
		for column in columns:
			var before_present: bool = bi > 0 and int(column.before_index) >= 0 and int(column.before_index) - 1 < before_rows[bi].size()
			var after_present: bool = ai > 0 and int(column.after_index) >= 0 and int(column.after_index) - 1 < after_rows[ai].size()
			var before_value := str(before_rows[bi][int(column.before_index) - 1]) if before_present else ""
			var after_value := str(after_rows[ai][int(column.after_index) - 1]) if after_present else ""
			var cell_changed := false
			if bi > 0 and ai > 0:
				cell_changed = before_present != after_present or before_value != after_value
				if cell_changed: counts.cells += 1
				row_changed = row_changed or cell_changed
			cells.append({"before":before_value,"after":after_value,"before_present":before_present,"after_present":after_present,"changed":cell_changed})
		if bi == 0: counts.added += 1
		elif ai == 0: counts.removed += 1
		elif row_changed: kind = "changed"; counts.changed += 1
		if row_moved: counts.moved += 1
		rows.append({"kind":kind,"moved":row_moved,"before_index":bi + 1 if bi > 0 else 0,"after_index":ai + 1 if ai > 0 else 0,"cells":cells})
	var parsed_same := before_rows == after_rows
	var bytes_same := before.to_utf8_buffer() == after.to_utf8_buffer()
	empty.merge({
		"columns":columns,
		"rows":rows,
		"counts":counts,
		"matching":"key:" + str(match_info.header) if str(match_info.mode) == "key" else "position",
		"byte_only":not bytes_same and parsed_same,
		"identical":bytes_same
	}, true)
	return empty

static func _empty_result(before: String, after: String) -> Dictionary:
	var same := before.to_utf8_buffer() == after.to_utf8_buffer()
	return {"columns":[],"rows":[],"counts":{"added":0,"removed":0,"changed":0,"moved":0,"cells":0},"matching":"position","byte_only":false,"identical":same,"error":""}

static func _parse_csv(csv: String) -> Dictionary:
	var rows: Array = []
	var row: Array[String] = []
	var cell := ""
	var cell_started := false
	var quoted := false
	var cells_total := 0
	var i := 0
	while i < csv.length():
		var ch := csv.substr(i, 1)
		if ch == '"':
			if quoted and i + 1 < csv.length() and csv.substr(i + 1, 1) == '"':
				cell += '"'; cell_started = true; i += 1
			elif quoted: quoted = false
			elif cell.is_empty(): quoted = true; cell_started = true
			else: cell += ch; cell_started = true
		elif ch == ',' and not quoted:
			row.append(cell); cell = ""; cell_started = false; cells_total += 1
			if row.size() >= MAX_COLUMNS: return {"rows":[],"error":"too_many_columns","cell_count":cells_total}
		elif (ch == '\n' or ch == '\r') and not quoted:
			if ch == '\r' and i + 1 < csv.length() and csv.substr(i + 1, 1) == '\n': i += 1
			row.append(cell); cells_total += 1
			if row.size() > MAX_COLUMNS: return {"rows":[],"error":"too_many_columns","cell_count":cells_total}
			rows.append(row); row = []; cell = ""; cell_started = false
			if rows.size() > MAX_ROWS or cells_total > MAX_CELLS: return {"rows":[],"error":"csv_limit_exceeded","cell_count":cells_total}
		else: cell += ch; cell_started = true
		i += 1
	if quoted: return {"rows":[],"error":"unterminated_quote","cell_count":cells_total}
	if cell_started or not row.is_empty():
		row.append(cell); rows.append(row); cells_total += 1
	if not rows.is_empty() and rows[0].size() > MAX_COLUMNS: return {"rows":[],"error":"too_many_columns","cell_count":cells_total}
	if rows.size() > MAX_ROWS: return {"rows":[],"error":"too_many_rows","cell_count":cells_total}
	if not rows.is_empty() and rows[0].size() > MAX_COLUMNS: return {"rows":[],"error":"too_many_columns","cell_count":cells_total}
	return {"rows":rows,"error":"","cell_count":cells_total}

static func _max_width(rows: Array) -> int:
	var width := 0
	for row in rows: width = maxi(width, row.size())
	return width

static func _align_columns(before_header: Array, after_header: Array, before_width: int, after_width: int) -> Array:
	var before_names: Array = before_header.duplicate()
	var after_names: Array = after_header.duplicate()
	while before_names.size() < before_width: before_names.append("")
	while after_names.size() < after_width: after_names.append("")
	var before_counts := _counts(before_names)
	var after_counts := _counts(after_names)
	var shared_after: Dictionary = {}
	for index in before_names.size():
		var name := str(before_names[index])
		if not name.is_empty() and int(before_counts.get(name, 0)) == 1 and int(after_counts.get(name, 0)) == 1:
			shared_after[index] = _index_of(after_names, name)
	var used_after: Dictionary = {}
	for after_index in shared_after.values(): used_after[int(after_index)] = true
	var result: Array = []
	for before_index in before_names.size():
		var name := str(before_names[before_index])
		var after_index := -1
		var key := ""
		if shared_after.has(before_index):
			after_index = int(shared_after[before_index]); key = name
		elif before_index < after_names.size() and not used_after.has(before_index):
			after_index = before_index; used_after[after_index] = true; key = "position:%d" % (before_index + 1)
		else:
			key = "before:%d" % (before_index + 1)
		var after_name := str(after_names[after_index]) if after_index >= 0 else ""
		result.append({"before":name,"after":after_name,"key":key,"before_index":before_index + 1,"after_index":after_index + 1 if after_index >= 0 else -1})
	for after_index in after_names.size():
		if used_after.has(after_index): continue
		result.append({"before":"","after":str(after_names[after_index]),"key":"after:%d" % (after_index + 1),"before_index":-1,"after_index":after_index + 1})
	return result

static func _counts(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		var name := str(value)
		result[name] = int(result.get(name, 0)) + 1
	return result

static func _index_of(values: Array, name: String) -> int:
	for index in values.size():
		if str(values[index]) == name: return index
	return -1

static func _row_match_mode(before_rows: Array, after_rows: Array, before_header: Array, after_header: Array) -> Dictionary:
	if before_header.is_empty() or after_header.is_empty(): return {"mode":"position","header":"","key_index":-1}
	var header := str(before_header[0])
	if header.strip_edges().to_lower() != str(after_header[0]).strip_edges().to_lower() or header.strip_edges().to_lower() not in ID_HEADERS: return {"mode":"position","header":"","key_index":-1}
	var before_values: Variant = _unique_row_keys(before_rows, 0)
	var after_values: Variant = _unique_row_keys(after_rows, 0)
	if before_values == null or after_values == null: return {"mode":"position","header":"","key_index":-1}
	return {"mode":"key","header":header,"key_index":0,"before_keys":before_values,"after_keys":after_values}

static func _unique_row_keys(rows: Array, column_index: int) -> Variant:
	var keys := {}
	for row_index in range(1, rows.size()):
		var row: Array = rows[row_index]
		if column_index >= row.size(): return null
		var value := str(row[column_index])
		if value.strip_edges().is_empty() or keys.has(value): return null
		keys[value] = row_index
	return keys

static func _pair_rows(before_rows: Array, after_rows: Array, match_info: Dictionary) -> Array:
	var before_count := maxi(0, before_rows.size() - 1)
	var after_count := maxi(0, after_rows.size() - 1)
	var result: Array = []
	if str(match_info.mode) == "key":
		var after_keys: Dictionary = match_info.after_keys
		var paired_after: Dictionary = {}
		for before_index in range(1, before_rows.size()):
			var key := str(before_rows[before_index][int(match_info.key_index)])
			var after_index: int = int(after_keys.get(key, 0))
			result.append({"before_index":before_index,"after_index":after_index})
			if after_index > 0: paired_after[after_index] = true
		for after_index in range(1, after_rows.size()):
			if not paired_after.has(after_index): result.append({"before_index":0,"after_index":after_index})
	else:
		var paired := mini(before_count, after_count)
		for offset in paired: result.append({"before_index":offset + 1,"after_index":offset + 1})
		for offset in range(paired, before_count): result.append({"before_index":offset + 1,"after_index":0})
		for offset in range(paired, after_count): result.append({"before_index":0,"after_index":offset + 1})
	return result

static func _moved_keys(pairs: Array, before_rows: Array, after_rows: Array, mode: String, key_index: int) -> Dictionary:
	var moved := {}
	if mode != "key": return moved
	var sequence: Array[int] = []
	var keys: Array[String] = []
	var seen_after: Dictionary = {}
	for pair in pairs:
		var bi := int(pair.before_index); var ai := int(pair.after_index)
		if bi == 0 or ai == 0: continue
		var key := str(before_rows[bi][key_index])
		if seen_after.has(key): continue
		seen_after[key] = true
		sequence.append(ai); keys.append(key)
	var kept := _lis_indices(sequence)
	for index in keys.size():
		if not kept.has(index): moved[keys[index]] = true
	return moved

static func _lis_indices(sequence: Array[int]) -> Dictionary:
	var tails: Array[int] = []
	var tail_indices: Array[int] = []
	var previous: Array[int] = []
	for index in sequence.size():
		var low := 0; var high := tails.size()
		while low < high:
			var mid := (low + high) / 2
			if tails[mid] < sequence[index]: low = mid + 1
			else: high = mid
		previous.append(tail_indices[low - 1] if low > 0 else -1)
		if low == tails.size():
			tails.append(sequence[index]); tail_indices.append(index)
		else:
			tails[low] = sequence[index]; tail_indices[low] = index
	var kept := {}
	if tail_indices.is_empty(): return kept
	var cursor: int = tail_indices.back()
	while cursor >= 0:
		kept[cursor] = true
		cursor = previous[cursor]
	return kept
