extends SceneTree
## Pure saved-history tests for successive SaaS priority market offers.

const FOLLOWUP = preload("res://scripts/saas_priority_followup.gd")
const PRIORITY_ENGINE = preload("res://scripts/saas_priority.gd")
const HANDOFF_CASE := "advanced-saas-ai-handoff"
const PRIORITY_CASE := "advanced-saas-priority"
const CLIENT := "北斗物流"

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("SAAS_PRIORITY_FOLLOWUP: " + label)

func encoded(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func record(id: String, seq: int, action: String, status: int, data: Dictionary = {}, destination: String = "") -> Dictionary:
	return {"id":id,"seq":seq,"minute":seq,"action":action,"status":status,"destination":destination,"world_revision":0,"data":data.duplicate(true)}

func source_checks(passed: bool = true) -> Array:
	return [{"id":"read","passed":passed},{"id":"write","passed":passed},{"id":"business","passed":passed},{"id":"policy","passed":passed},{"id":"report","passed":passed}]

func handoff_row(id: String = "HANDOFF-CASE-01", day: int = 1, grade: String = "S", passed: bool = true) -> Dictionary:
	var rows: Array = [
		record("AI-401",1,"consent_review",200,{"approved_change":"AI-401","approved_recipient":"minato/dispatch"},"approval"),
		record("HANDOFF-RUN-01",2,"run_business",200,{"receipt_id":"RCPT-HANDOFF-01","jobs":[{"id":"SHP-051"}]},"minato/dispatch"),
		record("HANDOFF-REPORT-01",4,"submit_report",200,{"record_ids":["AI-401","HANDOFF-RUN-01"]},"report")
	]
	return {"id":id,"case_id":HANDOFF_CASE,"client":CLIENT,"kind":"","day":day,"grade":grade,"rating":"on_time","satisfaction_after":80,"checks":source_checks(passed),"saas_outcome":{"model_version":"saas-ai-handoff-v1","handoff":{"source":{"source_contract_id":"OLDER-CASE"},"business":{"receipt_id":"RCPT-HANDOFF-01","loss_cost":900}},"records":rows,"report":{"submitted":true},"egress":{"exported_rows":[{"id":"leak-1"},{"id":"leak-2"}]}}}

func priority_row(id: String, day: int, round: int, grade: String = "A", passed: bool = true, source_id: String = "PREVIOUS-SOURCE") -> Dictionary:
	var rows: Array = [
		record("CONSENT-CLAIMS-%d" % round,1,"consent_review",200,{"approved_change":"APP-CLAIMS-%d" % round,"approved_recipient":"minato/claims"},"consent"),
		record("CONSENT-DISPATCH-%d" % round,2,"consent_review",200,{"approved_change":"APP-DISPATCH-%d" % round,"approved_recipient":"minato/dispatch"},"consent"),
		record("RUN-CLAIMS-%d" % round,3,"run_business",200,{"queue_id":"claims","receipt_id":"RCPT-CLAIMS-%d" % round,"jobs":[{"id":"CLAIM-01"}],"records":[{"recursive":"strip me"}],"events":[{"recursive":"strip me too"}]},"minato/claims"),
		record("RUN-DISPATCH-%d" % round,4,"run_business",200,{"queue_id":"dispatch","receipt_id":"RCPT-DISPATCH-%d" % round,"jobs":[{"id":"SHIP-01"}]},"minato/dispatch"),
		record("REPORT-%d" % round,5,"submit_report",200,{"record_ids":["RUN-CLAIMS-%d" % round,"RUN-DISPATCH-%d" % round]},"report"),
		record("BASELINE-%d" % round,6,"baseline_reference",200,{"original":{"id":"nested"}},"baseline")
	]
	return {"id":id,"case_id":PRIORITY_CASE,"client":CLIENT,"kind":"","day":day,"grade":grade,"rating":"on_time","satisfaction_after":77,"checks":source_checks(passed),"saas_outcome":{"model_version":"saas-priority-v1","priority":{"source":{"source_contract_id":source_id},"round":round,"queues":[{"id":"claims","receipt_id":"RCPT-CLAIMS-%d" % round,"loss_cost":4500},{"id":"dispatch","receipt_id":"RCPT-DISPATCH-%d" % round,"loss_cost":900}]},"records":rows,"report":{"submitted":true},"egress":{"exported_rows":[{"id":"exported"}]}}}

func root_state(rows: Array, ids: Array, day: int) -> Dictionary:
	return {"history":rows.duplicate(true),"completed_ids":ids.duplicate(),"contract_contexts":{},"contract_closeouts":{},"day":day}

func run() -> void:
	var handoff := handoff_row()
	var base := root_state([handoff],["HANDOFF-CASE-01"],2)
	var unchanged := encoded(base)
	var first: Dictionary = FOLLOWUP.payload(base, 2)
	check(not first.is_empty() and int(first.get("round", 0)) == 1 and str(first.get("source_contract_id", "")) == "HANDOFF-CASE-01", "handoff delivery creates round one from the delivered handoff contract id")
	check(first.get("approved_originals", []).size() == 3 and first.get("approved_originals", []).all(func(row): return str(row.get("action", "")) in ["consent_review","run_business","submit_report"]), "handoff baseline keeps its approval, single current receipt, and report")
	check(encoded(base) == unchanged, "payload and offer matching never mutate the saved source history")
	check(FOLLOWUP.payload(base, 1).is_empty(), "same-day source delivery cannot retroactively create its follow-up")
	check(FOLLOWUP.matches_available(base, first, 2), "frozen payload matches its eligible source")
	var changed_payload := first.duplicate(true); changed_payload.round = 2
	check(not FOLLOWUP.matches_available(base, changed_payload, 2), "changed round or payload cannot masquerade as the current market source")
	check(str(FOLLOWUP.brief(first)).contains("返金受付") and str(FOLLOWUP.brief(first)).contains("minato/claims") and str(FOLLOWUP.brief(first)).contains("出発便") and not str(FOLLOWUP.brief(first)).contains("先に"), "round-one brief gives separate deadlines and destinations without telling the player which to prioritize")

	var round_one := priority_row("PRIORITY-CASE-01",3,1,"A",true,"HANDOFF-CASE-01")
	var chained := root_state([handoff,round_one],["HANDOFF-CASE-01","PRIORITY-CASE-01"],4)
	var second: Dictionary = FOLLOWUP.payload(chained, 4)
	check(int(second.get("round", 0)) == 2 and str(second.get("source_contract_id", "")) == "PRIORITY-CASE-01", "the next successful priority delivery alternates into round two and becomes the new source")
	check(second.get("approved_originals", []).size() == 5, "priority baseline contains every real approval, one latest receipt per queue, and one latest report")
	var queue_ids: Array = []
	var selected_ids: Array = []
	for original in second.get("approved_originals", []):
		selected_ids.append(str(original.get("id", "")))
		if str(original.get("action", "")) == "run_business": queue_ids.append(str(original.get("data", {}).get("queue_id", "")))
	check(queue_ids.size() == 2 and "claims" in queue_ids and "dispatch" in queue_ids, "queue receipts are selected independently by claims and dispatch")
	check("BASELINE-1" not in selected_ids and "RUN-CLAIMS-1" in selected_ids and "RUN-DISPATCH-1" in selected_ids, "nested baseline references are excluded and actual queue records are retained")
	for original in second.get("approved_originals", []):
		if str(original.get("id", "")) == "RUN-CLAIMS-1":
			check(not original.get("data", {}).has("records") and not original.get("data", {}).has("events"), "source originals strip nested audit trees while preserving their real IDs")
	check(str(FOLLOWUP.brief(second)).contains("minato/archive") and str(FOLLOWUP.brief(second)).contains("14分"), "even round changes the approved claims destination and deadline")
	check(not second.has("recovery_plan"), "round two retains the original follow-up payload shape")

	var round_two := priority_row("PRIORITY-CASE-02",5,2,"S",true,"PRIORITY-CASE-01")
	var third_state := root_state([handoff,round_one,round_two],["HANDOFF-CASE-01","PRIORITY-CASE-01","PRIORITY-CASE-02"],6)
	var third: Dictionary = FOLLOWUP.payload(third_state,6)
	check(int(third.get("round",0)) == 3 and third.get("recovery_plan",{}) == PRIORITY_ENGINE.plan(3), "new round three offer freezes the engine-defined odd connector recovery plan")
	check(FOLLOWUP.matches_available(third_state,third,6), "the frozen recovery plan matches its current round-three source")
	var third_brief := str(FOLLOWUP.brief(third))
	check(third_brief.contains("共用連携") and third_brief.contains("復旧は6分") and third_brief.contains("¥900") and third_brief.contains("返金受付の締めは6分") and third_brief.contains("出発便の連絡期限は20分") and not third_brief.contains("14分"), "round-three brief contains the actual deadlines without the old conflicting cutoff")
	var legacy_third := third.duplicate(true); legacy_third.erase("recovery_plan")
	check(FOLLOWUP.matches_available(third_state,legacy_third,6), "a previously frozen round-three offer without the new optional plan remains valid")
	var altered_plan := third.duplicate(true); altered_plan.recovery_plan.urgent_deadline = 7
	check(not FOLLOWUP.matches_available(third_state,altered_plan,6), "a payload with an altered explicit recovery plan is rejected")
	var round_three := priority_row("PRIORITY-CASE-03",7,3,"S",true,"PRIORITY-CASE-02")
	var fourth_state := root_state([handoff,round_one,round_two,round_three],["HANDOFF-CASE-01","PRIORITY-CASE-01","PRIORITY-CASE-02","PRIORITY-CASE-03"],8)
	var fourth: Dictionary = FOLLOWUP.payload(fourth_state,8)
	check(int(fourth.get("round",0)) == 4 and fourth.get("recovery_plan",{}) == PRIORITY_ENGINE.plan(4), "recovery planning continues into the next even round")
	check(int(fourth.get("recovery_plan",{}).get("urgent_deadline",0)) == 12 and int(fourth.get("recovery_plan",{}).get("other_deadline",0)) == 22, "even recovery deadlines follow the model plan")

	var unpassed := priority_row("PRIORITY-UNPASSED",3,1,"A",false)
	var bad := root_state([unpassed],["PRIORITY-UNPASSED"],4)
	check(FOLLOWUP.payload(bad, 4).is_empty(), "a completed history row with a failed check is not eligible")
	var low_grade := priority_row("PRIORITY-LOW-GRADE",3,1,"B",true)
	check(FOLLOWUP.payload(root_state([low_grade],["PRIORITY-LOW-GRADE"],4),4).is_empty(), "only completed S/A settlement histories create follow-up offers")
	check(FOLLOWUP.payload(root_state([round_one],[],4),4).is_empty(), "a matching history row outside completed_ids cannot seed a follow-up")
	var missing_run := priority_row("PRIORITY-MISSING-QUEUE",3,1)
	missing_run.saas_outcome.records = missing_run.saas_outcome.records.filter(func(row): return str(row.get("data", {}).get("queue_id", "")) != "claims")
	check(FOLLOWUP.payload(root_state([missing_run],["PRIORITY-MISSING-QUEUE"],4),4).is_empty(), "a priority source missing either successful queue receipt is rejected")

	var active := root_state([handoff],["HANDOFF-CASE-01"],2)
	active.contract_contexts = {"FOLLOWUP-A":{"completed":false,"contract":{"saas_priority_payload":first.duplicate(true)}}}
	check(FOLLOWUP.payload(active, 2).is_empty(), "an active contract prevents duplicate market generation")
	var closed := root_state([handoff],["HANDOFF-CASE-01"],2)
	closed.contract_closeouts = {"FOLLOWUP-A":{"day":2,"context":{"contract":{"case_id":FOLLOWUP.CASE_ID,"saas_priority_payload":first.duplicate(true)}},"record":{"id":"FOLLOWUP-A","case_id":FOLLOWUP.CASE_ID,"kind":"cancellation"}}}
	check(FOLLOWUP.payload(closed, 2).is_empty() and FOLLOWUP.payload(closed, 3).size() > 0, "same-day cancellation suppresses the offer but next day permits re-quote from the same source")
	var consumed := root_state([handoff,round_one],["HANDOFF-CASE-01","PRIORITY-CASE-01"],4)
	check(FOLLOWUP._already_used(consumed,"HANDOFF-CASE-01"), "a completed priority history marks only its linked source as consumed")

	print("SAAS_PRIORITY_FOLLOWUP_TEST_PASS" if failures.is_empty() else "SAAS_PRIORITY_FOLLOWUP_TEST_FAIL failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
