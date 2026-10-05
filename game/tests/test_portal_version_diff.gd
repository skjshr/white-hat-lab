extends SceneTree

const Diff = preload("res://scripts/portal_version_diff.gd")
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_test_quoted_csv_and_row_changes()
	_test_move_detection()
	_test_duplicate_key_fallback()
	_test_columns_and_presence()
	_test_headers_bytes_and_limits()
	_test_determinism()
	for failure in failures: push_error(failure)
	print("PORTAL_VERSION_DIFF_PASS assertions=" + str(assertions) if failures.is_empty() else "PORTAL_VERSION_DIFF_FAIL count=" + str(failures.size()) + " assertions=" + str(assertions))
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label)

func _test_quoted_csv_and_row_changes() -> void:
	var before := "id,note,amount\r\n1,\"line one\nline two\",100\r\n2,old,250\r\n3,keep,9\r\n"
	var after := "id,note,amount\r\n0,new,1\r\n1,\"new, note\",100\r\n3,keep,9\r\n4,added,8\r\n"
	var result: Dictionary = Diff.compare(before, after)
	check(result.matching == "key:id", "known unique identity header selects keyed row matching")
	check(result.counts.added == 2 and result.counts.removed == 1 and result.counts.changed == 1 and result.counts.cells == 1, "insertions, deletions and one edited paired cell remain separate")
	check(result.counts.moved == 0, "inserting and removing keyed rows does not mark neighboring rows moved")
	var edited := _row_by_before(result, 2)
	check(edited.kind == "changed" and edited.cells[1].before == "line one\nline two" and edited.cells[1].after == "new, note", "quoted commas and embedded newlines parse into actual cell values")
	check(_row_by_after(result, 3).before_index == 2 and _row_by_after(result, 3).after_index == 3, "row indexes preserve source CSV numbering including the header")
	check(not result.identical and not result.byte_only, "semantic edits are not byte-only changes")

func _test_move_detection() -> void:
	var result: Dictionary = Diff.compare("id,value\nA,a\nB,b\nC,c\n", "id,value\nB,b\nA,a\nC,c\n")
	check(result.matching == "key:id" and result.counts.changed == 0 and result.counts.cells == 0, "reordered keyed rows retain unchanged cell values")
	check(result.counts.moved == 1 and result.rows.any(func(row): return bool(row.moved)), "LIS order comparison marks the minimal moved row set")
	var moved_row: Dictionary = result.rows.filter(func(row): return bool(row.moved))[0]
	check(moved_row.before_index != moved_row.after_index and moved_row.kind == "unchanged", "move marker is distinct from cell changes")

func _test_duplicate_key_fallback() -> void:
	var result: Dictionary = Diff.compare("order_id,value\nX,old\nX,second\n", "order_id,value\nX,new\nX,second\n")
	check(result.matching == "position" and result.counts.changed == 1 and result.counts.cells == 1, "duplicate keys disable key matching and fall back to rows by position")
	check(result.counts.moved == 0 and result.rows[0].kind == "changed", "positional fallback does not invent moves")
	var empty_key: Dictionary = Diff.compare("customer_id,value\n,old\n", "customer_id,value\n,new\n")
	check(empty_key.matching == "position", "empty identity values disable key matching")
	var case_header: Dictionary = Diff.compare("ID,value\nA,old\n", "id,value\nA,new\n")
	check(case_header.matching == "key:ID" and case_header.counts.changed == 1, "known identity headers are recognized case-insensitively while retaining the source label")

func _test_columns_and_presence() -> void:
	var reordered: Dictionary = Diff.compare("id,name,total\n1,A,10\n", "total,id,name\n10,1,A\n")
	check(reordered.columns.size() == 3 and reordered.columns[0].before == "id" and reordered.columns[0].after_index == 2, "unique header names align reordered columns")
	check(reordered.counts.changed == 0 and reordered.counts.cells == 0, "column reorder does not cascade into data edits")
	var added_column: Dictionary = Diff.compare("id,name\n1,A\n", "id,name,total\n1,A,\n")
	check(added_column.columns.size() == 3 and added_column.columns[2].before_index == -1 and added_column.columns[2].after_index == 3, "new columns append after before-order columns and use negative one for absence")
	check(added_column.rows[0].cells[2].before_present == false and added_column.rows[0].cells[2].after_present and added_column.rows[0].cells[2].after == "", "blank cell differs from absent cell in an added column")
	check(added_column.counts.changed == 1 and added_column.counts.cells == 1, "added column presence is counted once per paired data row")
	var removed_column: Dictionary = Diff.compare("id,name,total\n1,A,\n", "id,name\n1,A\n")
	check(removed_column.columns[2].before_index == 3 and removed_column.columns[2].after_index == -1 and removed_column.rows[0].cells[2].before_present, "removed blank column remains distinguishable from a missing column")
	var duplicate_columns: Dictionary = Diff.compare("id,value,value\n1,left,right\n", "id,value,value\n1,left,changed\n")
	check(duplicate_columns.columns[1].key == "position:2" and duplicate_columns.columns[2].key == "position:3" and duplicate_columns.counts.cells == 1, "duplicate column names fall back to positional alignment")
	var blank_missing: Dictionary = Diff.compare("id,value\n1,\n", "id,value\n1\n")
	check(blank_missing.rows[0].cells[1].before_present and not blank_missing.rows[0].cells[1].after_present and blank_missing.rows[0].cells[1].changed, "blank field and short row produce different presence states")
	var unnamed_changed: Dictionary = Diff.compare("id,name,total\n1,A,10,old\n", "id,name,total\n1,A,10,new\n")
	check(unnamed_changed.columns.size() == 4 and unnamed_changed.columns[3].before == "" and unnamed_changed.columns[3].after == "" and unnamed_changed.rows[0].cells[3].changed, "extra unnamed cells beyond the header width remain aligned and compared")
	check(unnamed_changed.counts.changed == 1 and unnamed_changed.counts.cells == 1, "edit in an unnamed fourth column increments the paired row and cell counts")
	var unnamed_added: Dictionary = Diff.compare("id,name,total\n1,A,10\n", "id,name,total\n1,A,10,extra\n")
	check(unnamed_added.columns[3].before_index == -1 and unnamed_added.columns[3].after_index == 4 and not unnamed_added.rows[0].cells[3].before_present and unnamed_added.rows[0].cells[3].after_present, "a one-sided ragged extra field is represented as an added unnamed column")
	check(unnamed_added.counts.changed == 1 and unnamed_added.counts.cells == 1, "one-sided unnamed field is counted once")
	var unnamed_removed: Dictionary = Diff.compare("id,name,total\n1,A,10,\n", "id,name,total\n1,A,10\n")
	check(unnamed_removed.columns[3].before_index == 4 and unnamed_removed.columns[3].after_index == -1 and unnamed_removed.rows[0].cells[3].before_present and not unnamed_removed.rows[0].cells[3].after_present, "shorter one-sided row keeps extra blank cell distinct from missing field")

func _test_headers_bytes_and_limits() -> void:
	var header_only: Dictionary = Diff.compare("id,total\n1,9\n", "id,amount\n1,9\n")
	check(header_only.columns[1].before == "total" and header_only.columns[1].after == "amount" and header_only.counts.changed == 0, "header-only change appears in columns without a fake data-row edit")
	check(not header_only.byte_only and not header_only.identical, "header edit is semantic, not byte-only")
	var byte_only: Dictionary = Diff.compare("id,name\n1,A\n", "id,name\r\n1,A\r\n")
	check(byte_only.byte_only and not byte_only.identical and byte_only.counts.changed == 0, "line-ending-only difference is reported as byte-only")
	var same: Dictionary = Diff.compare("id,name\n1,A\n", "id,name\n1,A\n")
	check(same.identical and not same.byte_only and same.rows[0].kind == "unchanged", "exact input match is identified")
	var invalid: Dictionary = Diff.compare("id,value\n1,\"unfinished", "id,value\n1,ok\n")
	check(invalid.error == "unterminated_quote" and invalid.rows.is_empty(), "malformed quoted CSV returns a bounded error result")
	var too_large: Dictionary = Diff.compare("x".repeat(Diff.MAX_INPUT_BYTES + 1), "")
	check(too_large.error == "input_too_large" and too_large.counts.changed == 0, "input-size limit rejects oversized snapshots without partial output")

func _test_determinism() -> void:
	var before := "order_id,total\nA,10\nB,20\nC,30\n"
	var after := "order_id,total\nB,21\nA,10\nD,40\n"
	var first: Dictionary = Diff.compare(before, after)
	var second: Dictionary = Diff.compare(before, after)
	check(first == second, "same inputs produce the same comparison without side effects")
	check(first.counts.added == 1 and first.counts.removed == 1 and first.counts.changed == 1, "keyed change, removal and addition are reported independently")

func _row_by_before(result: Dictionary, index: int) -> Dictionary:
	for row in result.rows:
		if int(row.get("before_index", 0)) == index: return row
	return {}

func _row_by_after(result: Dictionary, index: int) -> Dictionary:
	for row in result.rows:
		if int(row.get("after_index", 0)) == index: return row
	return {}
