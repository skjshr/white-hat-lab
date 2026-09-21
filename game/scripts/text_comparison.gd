extends RefCounted
## Small, deterministic line comparison used by the editor compare view.

static func compare(before: String, after: String) -> Dictionary:
	var left: Array = before.split("\n", true)
	var right: Array = after.split("\n", true)
	var prefix := 0
	while prefix < left.size() and prefix < right.size() and left[prefix] == right[prefix]: prefix += 1
	var left_end := left.size() - 1
	var right_end := right.size() - 1
	while left_end >= prefix and right_end >= prefix and left[left_end] == right[right_end]:
		left_end -= 1; right_end -= 1
	var removed: Array[int] = []
	var added: Array[int] = []
	if prefix <= left_end or prefix <= right_end:
		var n := maxi(0, left_end - prefix + 1)
		var m := maxi(0, right_end - prefix + 1)
		# Keep UI work bounded for generated or log-like files.
		if n * m <= 250000:
			var rows: Array = []
			for i in range(n + 1):
				var row: Array = []
				row.resize(m + 1)
				for j in range(m + 1): row[j] = 0
				rows.append(row)
			for i in range(n - 1, -1, -1):
				for j in range(m - 1, -1, -1):
					rows[i][j] = rows[i + 1][j + 1] + 1 if left[prefix + i] == right[prefix + j] else maxi(rows[i + 1][j], rows[i][j + 1])
			var i := 0; var j := 0
			while i < n and j < m:
				if left[prefix + i] == right[prefix + j]: i += 1; j += 1
				elif rows[i + 1][j] >= rows[i][j + 1]: removed.append(prefix + i); i += 1
				else: added.append(prefix + j); j += 1
			while i < n: removed.append(prefix + i); i += 1
			while j < m: added.append(prefix + j); j += 1
		else:
			for i in range(prefix, left_end + 1): removed.append(i)
			for j in range(prefix, right_end + 1): added.append(j)
	return {"before_lines": left, "after_lines": right, "removed": removed, "added": added}
