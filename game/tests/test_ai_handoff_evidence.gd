extends SceneTree
## Pure evidence projection and its saved-organization boundary. No player save.
const EVIDENCE = preload("res://scripts/ai_handoff_evidence.gd")
const MODEL = preload("res://scripts/saas_ai_handoff.gd")
const PREVIOUS = preload("res://scripts/saas_ai_preflight.gd")
var failures: Array[String] = []
var initial: Dictionary = {}
var previous_id := "HANDOFF-BASE-AI-301"

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("AI_HANDOFF_EVIDENCE: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func latest(world: Dictionary, action: String) -> Dictionary:
	var result: Dictionary = {}
	for row in world.records:
		if str(row.action) == action: result = row
	return result

func prepare() -> void:
	var previous: Dictionary = PREVIOUS.create()
	for key in ["customers","external"]: previous = PREVIOUS.act(previous,"configure",{"key":key,"enabled":false}).state
	previous = PREVIOUS.act(previous,"run_business").state
	var normal: Dictionary = latest(previous,"run_business").duplicate(true)
	var probe: Dictionary = PREVIOUS.act(previous,"probe_boundaries"); previous = probe.state
	previous = PREVIOUS.act(previous,"collect_audit").state
	var ids: Array = ["AI-301",str(normal.id),str(latest(previous,"collect_audit").id)]
	ids.append_array(probe.data.record_ids)
	var submitted: Dictionary = PREVIOUS.act(previous,"submit_report",{"record_ids":ids}); previous = submitted.state
	check(bool(submitted.get("ok", false)), "previous approval, receipt and report are produced by actual model actions")
	initial = MODEL.create_followup({"source_contract_id":"qa-evidence-prior","source_day":4,"client":"北斗物流","approved_originals":[previous.records[0].duplicate(true),normal,latest(previous,"submit_report").duplicate(true)]})
	check(not initial.is_empty(), "the normal follow-up retains the selected-wrapper originals")

func selected_originals() -> void:
	var before := encoded(initial)
	var empty: Dictionary = EVIDENCE.build(initial.records, [])
	var current: Dictionary = EVIDENCE.build(initial.records, ["AI-401"])
	var previous: Dictionary = EVIDENCE.build(initial.records, [previous_id])
	check(empty.previous.state == "missing" and empty.current.state == "missing" and current.previous.state == "missing" and previous.current.state == "missing", "unselected approvals remain missing even though the world and handoff source contain them")
	var result: Dictionary = EVIDENCE.build(initial.records, [previous_id,"AI-401"])
	check(result.previous.record_id == previous_id and result.previous.original_id == "AI-301" and result.previous.sources == ["faq","dispatch"] and result.previous.recipient == "desk" and not result.previous.contacts_scope_known, "the prior approval cites its selected wrapper and preserves its actual source and recipient scope")
	check(result.current.record_id == "AI-401" and result.current.sources == ["dispatch","contacts"] and result.current.contacts_scope == "linked" and result.current.contact_ids.size() == 3 and result.current.shipment_ids.size() == 3 and result.current.recipient == "minato/dispatch" and result.current.excluded_recipient == "minato/archive", "the new approval exposes the actual three-contact scope and the two distinct recipient paths")
	var other_ids: Array = initial.records.filter(func(row): return str(row.action) == "baseline_reference" and str(row.id) != previous_id).map(func(row): return str(row.id))
	other_ids.append("AI-301")
	check(EVIDENCE.build(initial.records, other_ids).previous.state == "missing", "an original ID or selected prior report cannot silently select a nested approval")
	result.current.contact_ids.append("not-a-contact")
	check(encoded(initial) == before and EVIDENCE.build(initial.records,["AI-401"]).current.contact_ids.size() == 3, "projected arrays are detached and repeated reading cannot alter saved originals")

func missing_fields() -> void:
	# Reconstruct only old optional evidence fields, not a successful world.
	var records: Array = JSON.parse_string(JSON.stringify(initial.records))
	for row in records:
		if str(row.id) == "AI-401":
			row.data.erase("approved_contact_ids"); row.data.approved_shipment_ids = []; row.data.excluded_recipient = ""
		elif str(row.id) == previous_id: row.data.original.data.erase("approved_sources")
	var result: Dictionary = EVIDENCE.build(records, [previous_id,"AI-401"])
	check(result.current.state == "present" and not result.current.contact_ids_known and result.current.contact_ids.is_empty() and result.current.shipment_ids_known and result.current.shipment_ids.is_empty() and result.current.excluded_recipient_known and result.current.excluded_recipient.is_empty() and not result.previous.sources_known, "absent optional fields remain unknown while explicitly empty values remain known")
	for row in records:
		if str(row.id) == "AI-401": row.data.approved_sources = "dispatch"; row.data.approved_recipient = null
	result = EVIDENCE.build(records, ["AI-401"])
	check(not result.current.sources_known and not result.current.recipient_known, "malformed old optional values are unknown instead of being presented as an explicit empty permission")

func saved_organization() -> void:
	var ids: Array = initial.records.map(func(row): return str(row.id))
	var organized: Dictionary = MODEL.act(initial,"organize_records",{"mode":"assistant","record_ids":ids})
	var world: Dictionary = organized.state
	var snapshot := encoded(world.organization.comparison)
	check(int(organized.get("usage_cost", 0)) == 300 and world.organization.comparison.approvals.previous.state == "present" and world.organization.comparison.approvals.current.state == "present" and world.organization.comparison.lanes.values().all(func(lane): return str(lane.state) == "unknown"), "four selected originals produce approval differences without manufacturing boundary or business measurements")
	world = MODEL.act(world,"configure",{"key":"partner_archive","enabled":false}).state
	var before := encoded(world)
	var shown: Dictionary = MODEL.view(world).handoff.organization.comparison
	check(encoded(world.organization.comparison) == snapshot and encoded(shown.approvals) == encoded(world.organization.comparison.approvals) and not bool(shown.fresh) and encoded(world) == before, "a later policy change marks the organization old without rewriting its approval facts or measurements")
	ids.reverse()
	var duplicate: Dictionary = MODEL.act(world,"organize_records",{"mode":"assistant","record_ids":ids})
	check(not bool(duplicate.get("changed", true)) and int(duplicate.get("cost", -1)) == 0 and encoded(duplicate.state) == before, "the same selected originals reuse the saved comparison without time or another fee after a policy change")
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(world))
	check(encoded(MODEL.view(resumed)) == encoded(MODEL.view(world)) and encoded(resumed) == before, "JSON resume preserves the comparison, original records, costs and stale state")
	var legacy_result: Dictionary = MODEL.act(initial,"organize_records",{"mode":"manual","record_ids":[previous_id]})
	var legacy: Dictionary = legacy_result.state
	legacy.organization.comparison.erase("approvals")
	var legacy_before := encoded(legacy); var lanes := encoded(legacy.organization.comparison.lanes)
	var legacy_view: Dictionary = MODEL.view(legacy).handoff.organization.comparison
	check(legacy_view.approvals.previous.state == "present" and legacy_view.approvals.current.state == "missing" and encoded(legacy.organization.comparison.lanes) == lanes and encoded(legacy) == legacy_before, "old organization is enriched only from its own selected IDs while persisted lanes, fees and source remain unchanged")

func run() -> void:
	prepare()
	if not initial.is_empty(): selected_originals(); missing_fields(); saved_organization()
	print("AI_HANDOFF_EVIDENCE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
