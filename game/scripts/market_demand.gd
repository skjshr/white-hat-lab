extends RefCounted

const CATEGORIES := ["advisory", "operations", "response"]
const PHASE_COUNTS := [2, 3, 4]

static func phase(day: int, category_offset: int = 0) -> int:
	return posmod(day + category_offset, PHASE_COUNTS.size())

static func _id(candidate: Dictionary) -> String:
	return str(candidate.get("case_id",candidate.get("id","")))

static func select_by_category(candidates: Array, day: int, recent: Array = [], existing: Array = [], skill_ranks: Dictionary = {}, priority_ids: Array = []) -> Array:
	var selected: Array = []
	for raw_id in existing:
		var existing_id := str(raw_id)
		if not existing_id.is_empty() and existing_id not in selected: selected.append(existing_id)
	for category_index in CATEGORIES.size():
		var category: String=CATEGORIES[category_index]
		var group: Array=candidates.filter(func(item):return item is Dictionary and bool(item.get("unlocked",false)) and str(item.get("category",""))==category)
		var count := 0
		for candidate in group:
			if _id(candidate) in selected: count += 1
		var limit:=mini(group.size(),PHASE_COUNTS[phase(day,category_index)])
		while count < limit:
			var available: Array = group.filter(func(item): return _id(item) not in selected)
			if available.is_empty(): break
			var chosen: Dictionary = _choose_candidate(group, available, category, day, recent, skill_ranks, count == 0, selected)
			var chosen_id := _id(chosen)
			if chosen_id.is_empty() or chosen_id in selected: break
			selected.append(chosen_id); count += 1
	# A newly learned specialty may be promoted immediately. Preserve all existing
	# leads and allow at most one priority promotion per category.
	for category in CATEGORIES:
		var category_priority_present := false
		for already_id in selected:
			for candidate in candidates:
				if _id(candidate) == str(already_id) and str(candidate.get("category", "")) == category and str(already_id) in priority_ids:
					category_priority_present = true; break
			if category_priority_present: break
		if category_priority_present: continue
		for priority_id in priority_ids:
			var candidate_id := str(priority_id)
			if candidate_id in selected: continue
			var found: Dictionary = {}
			for candidate in candidates:
				if _id(candidate) == candidate_id and bool(candidate.get("unlocked",false)) and str(candidate.get("category","")) == category:
					found = candidate; break
			if not found.is_empty():
				selected.append(candidate_id)
				break
	return selected

static func _choose_candidate(all_group: Array, group: Array, category: String, day: int, recent: Array, skill_ranks: Dictionary, first_slot: bool, selected: Array) -> Dictionary:
	var available: Array = group.duplicate()
	var non_recent: Array = available.filter(func(item): return _id(item) not in recent)
	if not non_recent.is_empty(): available = non_recent
	var invested_rank := int(skill_ranks.get(category, 0))
	if first_slot:
		var eligible: Array = available.filter(func(item): return int(item.get("required_rank", item.get("tier", 1))) <= invested_rank or skill_ranks.is_empty())
		if not eligible.is_empty(): available = eligible
		available.sort_custom(func(a,b):
			var ar := int(a.get("required_rank", a.get("tier", 1))); var br := int(b.get("required_rank", b.get("tier", 1)))
			if ar != br: return ar > br
			return _seed(day, _id(a)) < _seed(day, _id(b)))
		return available[0]
	var family_counts: Dictionary = {}
	for item in all_group:
		var family := _family(item)
		family_counts[family] = int(family_counts.get(family, 0)) + (1 if _id(item) in selected else 0)
	available.sort_custom(func(a,b):
		var af := _family(a); var bf := _family(b); var ac := int(family_counts.get(af, 0)); var bc := int(family_counts.get(bf, 0))
		if ac != bc: return ac < bc
		return _seed(day, _id(a)) < _seed(day, _id(b)))
	return available[0]

static func prioritize_relationships(candidates: Array, leads: Array, priority_ids: Array, protected_ids: Array, day: int) -> Array:
	var result := leads.duplicate()
	var by_id := {}
	for candidate in candidates: by_id[_id(candidate)] = candidate
	for raw_id in priority_ids:
		var id := str(raw_id)
		if id in result or not by_id.has(id): continue
		var candidate: Dictionary = by_id[id]
		if not bool(candidate.get("unlocked", false)): continue
		var category := str(candidate.get("category", ""))
		var index := CATEGORIES.find(category)
		if index < 0: continue
		var category_leads: Array = result.filter(func(lead_id): return str(by_id.get(str(lead_id), {}).get("category", "")) == category)
		if category_leads.size() < PHASE_COUNTS[phase(day, index)]:
			result.append(id); continue
		# Never replace a quote the player has prepared, an accepted job, or a
		# different customer's earned consultation. No extra daily demand is minted.
		for slot in range(result.size() - 1, -1, -1):
			var current := str(result[slot])
			if current in protected_ids or current in priority_ids: continue
			if str(by_id.get(current, {}).get("category", "")) != category: continue
			result[slot] = id; break
	return result

static func _family(candidate: Dictionary) -> String:
	var family := str(candidate.get("work_family", ""))
	return family if not family.is_empty() else "chapter-" + str(candidate.get("chapter", ""))

static func _seed(day: int, id: String) -> String:
	return (str(day) + "/" + id).sha256_text()
