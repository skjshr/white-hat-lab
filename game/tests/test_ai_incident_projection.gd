extends SceneTree
## Model-only regression. No player save, GUI, invented observation or receipt.
const MODEL = preload("res://scripts/saas_ai_preflight.gd")
const PROJECTION = preload("res://scripts/ai_incident_projection.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error("AI_INCIDENT_PROJECTION: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func act(world: Dictionary, operation: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = MODEL.act(world, operation, args)
	check(bool(result.get("changed", false)) and result.get("state", {}) is Dictionary, "actual model operation produces a saved observation: " + operation)
	return result.get("state", {})

func project(world: Dictionary) -> Dictionary:
	var before := encoded(world)
	var result: Dictionary = PROJECTION.build(world)
	check(encoded(world) == before and encoded(PROJECTION.build(world)) == encoded(result), "repeated projection preserves the exact clock, records, policy, receipt and loss")
	return result

func event(view: Dictionary, id: String) -> Dictionary:
	for row in view.get("events", []):
		if str(row.get("id", "")) == id: return row
	return {}

func leakage_and_history() -> void:
	var world: Dictionary = MODEL.create()
	var initial := project(world)
	var pending: Array = initial.get("pending", [])
	check(int(initial.get("now", -1)) == 0 and initial.get("events", []).is_empty() and pending.size() == 2 and pending.all(func(row): return not row.has("read") and not row.has("write") and not row.has("status")) and str(initial.get("deadline", {}).get("status", "")) == "waiting" and initial.get("business_event", {}).is_empty(), "scheduled inputs are not fabricated measurements or completed customer work")
	MODEL.advance(world, 12)
	var observed := project(world)
	var first := event(observed, "AI-SYNC-01")
	var frozen := encoded(first)
	var saved_ids: Array = world.egress.schedule[0].get("record_ids", [])
	check(int(first.get("minute", -1)) == 12 and int(first.get("read", {}).get("status", 0)) == 200 and int(first.get("write", {}).get("status", 0)) == 200 and int(first.get("rows", 0)) == 3 and int(first.get("impact_cost", 0)) == 1500 and encoded(first.get("record_ids", [])) == encoded(saved_ids) and saved_ids.size() == 2 and int(observed.get("total_rows", 0)) == 3, "the twelve-minute read and write trace the two real originals and three charged copies")
	if not first.is_empty():
		first.read.status = 999; first.record_ids.append("not-a-record")
	check(encoded(event(project(world), "AI-SYNC-01")) == frozen, "editing a detached display result cannot change original observations")
	world = act(world, "configure", {"key":"customers","enabled":false})
	var changed := project(world)
	check(not bool(world.ai_preflight.policy.customers) and encoded(event(changed, "AI-SYNC-01")) == frozen and int(changed.get("total_impact_cost", 0)) == 1500, "a current denial cannot recolor or erase the older successful export and its cost")
	MODEL.advance(world, 5)
	var stopped := project(world)
	var second := event(stopped, "AI-SYNC-02")
	check(int(second.get("minute", -1)) == 18 and int(second.get("read", {}).get("status", 0)) == 403 and int(second.get("write", {}).get("status", 0)) == 403 and int(second.get("rows", -1)) == 0 and str(second.get("write", {}).get("blocked_reason", "")) == "customer-read-denied" and int(stopped.get("total_rows", 0)) == 3 and encoded(event(stopped, "AI-SYNC-01")) == frozen, "read denial prevents the next actual send while prior copies remain visible")
	# Explicit old optional-field schema, reconstructed only in memory. It is
	# not a native save fixture and does not invent successful model state.
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(world))
	legacy.ai_preflight.erase("requests"); legacy.ai_preflight.erase("knowledge")
	legacy.ai_preflight.business.erase("accepted_summaries"); legacy.invoice.erase("accepted_summaries")
	var old_json := encoded(legacy)
	var resumed := project(legacy)
	check(encoded(legacy) == old_json and encoded(resumed) == encoded(stopped) and not legacy.ai_preflight.has("requests"), "JSON-loaded older optional data keeps its original history without render-time migration")

func outbound_denial() -> void:
	var world := act(MODEL.create(), "configure", {"key":"external","enabled":false})
	MODEL.advance(world, 11)
	var view := project(world)
	var observed := event(view, "AI-SYNC-01")
	check(int(observed.get("read", {}).get("status", 0)) == 200 and int(observed.get("read", {}).get("rows", 0)) == 3 and int(observed.get("write", {}).get("status", 0)) == 403 and str(observed.get("write", {}).get("blocked_reason", "")) == "recipient-policy" and int(observed.get("rows", -1)) == 0 and int(view.get("total_rows", -1)) == 0 and int(view.get("total_impact_cost", -1)) == 0, "blocking only the destination retains the real successful read but creates no exported rows or compensation")

func deadline_and_retry() -> void:
	var clean := act(MODEL.create(), "configure", {"key":"customers","enabled":false})
	clean = act(clean, "configure", {"key":"external","enabled":false})
	MODEL.advance(clean, 10)
	var timely := act(clean, "run_business")
	var accepted := project(timely)
	var receipt := str(timely.invoice.get("receipt_id", ""))
	var answers := encoded(timely.invoice.get("accepted_summaries", []))
	var first_receipt_id := str(accepted.get("deadline", {}).get("record_id", ""))
	check(not receipt.is_empty() and not first_receipt_id.is_empty() and str(accepted.get("deadline", {}).get("status", "")) == "met" and int(accepted.get("deadline", {}).get("received_minute", -1)) == 14 and int(accepted.get("deadline", {}).get("received_count", 0)) == 6 and int(accepted.get("deadline", {}).get("loss_cost", -1)) == 0, "six actual customer answers received at minute fourteen meet the deadline")
	# Old record shape only: omit a timestamp from actual successful work.
	var unknown_time: Dictionary = JSON.parse_string(JSON.stringify(timely))
	for record in unknown_time.records:
		if str(record.get("action", "")) == "run_business": record.erase("minute")
	var unknown_view := project(unknown_time)
	check(str(unknown_view.get("deadline", {}).get("status", "")) == "unknown" and int(unknown_view.get("deadline", {}).get("received_minute", 0)) == -1 and int(unknown_view.get("deadline", {}).get("received_count", 0)) == 6 and str(unknown_view.get("deadline", {}).get("record_id", "")) == first_receipt_id, "a real receipt with an absent timestamp remains received but cannot be declared on time")
	timely = act(timely, "configure", {"key":"desk","enabled":false})
	timely = act(timely, "run_business")
	var refused := project(timely)
	check(int(refused.get("business_event", {}).get("status", 0)) == 403 and encoded(refused.get("deadline", {})) == encoded(accepted.get("deadline", {})) and str(timely.invoice.get("receipt_id", "")) == receipt and encoded(timely.invoice.get("accepted_summaries", [])) == answers, "a later refused recheck stays separate from the first timely receipt and its accepted content")
	timely = act(timely, "configure", {"key":"desk","enabled":true})
	timely = act(timely, "run_business")
	var retried := project(timely)
	var duplicate: Dictionary = MODEL.act(timely, "run_business")
	check(int(retried.get("business_event", {}).get("status", 0)) == 200 and str(retried.get("deadline", {}).get("record_id", "")) == first_receipt_id and int(retried.get("deadline", {}).get("loss_cost", -1)) == 0 and str(timely.invoice.get("receipt_id", "")) == receipt and not bool(duplicate.get("changed", true)) and encoded(duplicate.get("state", {})) == encoded(timely), "recovery and duplicate retry retain the same first receipt without a late fee or new work")
	MODEL.advance(clean, 1)
	var late := act(clean, "run_business")
	var late_view := project(late)
	var late_receipt_id := str(late_view.get("deadline", {}).get("record_id", ""))
	var late_charge_id := str(late_view.get("deadline", {}).get("late_record_id", ""))
	check(not late_receipt_id.is_empty() and not late_charge_id.is_empty() and late_receipt_id != late_charge_id and late.records.any(func(row): return str(row.get("id", "")) == late_receipt_id and str(row.get("action", "")) == "run_business"), "the late receipt opens its accepted work original, separately from the overdue charge original")
	check(str(late_view.get("deadline", {}).get("status", "")) == "late" and int(late_view.get("deadline", {}).get("received_minute", -1)) == 15 and int(late_view.get("deadline", {}).get("received_count", 0)) == 6 and int(late_view.get("deadline", {}).get("loss_cost", 0)) == 900 and int(late_view.get("total_impact_cost", -1)) == 0, "minute fifteen acceptance retains the separate deadline loss even though normal work succeeds without leakage")
	var late_flag_only: Dictionary = JSON.parse_string(JSON.stringify(late))
	late_flag_only.records = late_flag_only.records.filter(func(row): return str(row.get("action", "")) != "summary_overdue")
	for record in late_flag_only.records:
		if str(record.get("action", "")) == "run_business": record.erase("minute")
	var flag_view := project(late_flag_only)
	check(str(flag_view.get("deadline", {}).get("status", "")) == "late" and int(flag_view.get("deadline", {}).get("received_minute", 0)) == -1 and int(flag_view.get("deadline", {}).get("loss_cost", 0)) == 900, "the model's saved lateness and loss outrank an unknown receipt time even without the older deadline record")
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(late))
	MODEL.advance(legacy, 8)
	var resumed := project(legacy)
	check(int(resumed.get("deadline", {}).get("loss_cost", 0)) == 900 and str(resumed.get("deadline", {}).get("record_id", "")) == str(late_view.get("deadline", {}).get("record_id", "")) and legacy.records.filter(func(row): return str(row.get("action", "")) == "summary_overdue").size() == 1, "JSON resume and later time do not invent another deadline charge or replace its receipt")

func run() -> void:
	leakage_and_history()
	outbound_denial()
	deadline_and_retry()
	print("AI_INCIDENT_PROJECTION_TEST_PASS" if failures.is_empty() else "AI_INCIDENT_PROJECTION_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
