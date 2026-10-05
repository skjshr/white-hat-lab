extends SceneTree

const CYCLE = preload("res://scripts/company_cycle.gd")
const CATALOG = preload("res://scripts/case_catalog.gd")
const CLIENT := "つばさ文具"
const SOURCE := "service-0-case-0"
const NEXT := "service-5-case-1"
var failures: Array[String] = []
var assertions := 0

class FakeGame extends RefCounted:
	var level := 1
	var state := {
		"day":1,"chapter":0,"career_mode":true,"cash":12000,"profit":5100,"credit":51,"peak_profit":5100,
		"skills":{"advisory":1,"operations":0,"response":0},"history":[],"completed_ids":[],
		"customer_relations":{},"care_agreements":{},"offers":[],"market_leads":[],
		"billing":{"version":1,"next_invoice":1,"invoices":[],"payments":[]},
		"vm_states":{"retained/site-0":{"fs":{"/srv/data/orders.csv":"id,quantity\nA,2\n"},"applied":{"guest":"none","staff":"write"}}},
		"maintenance_targets":{"つばさ文具":[{"asset_id":"share-0","vm_state":{"fs":{"/srv/data/orders.csv":"preserved bytes"}}}]},
		"contract_contexts":{"current":{"completed":false,"work":{"minutes":9}}}
	}
	func company_level() -> Dictionary:
		return {"level":level}

func _init() -> void:
	_test_legacy_and_receipt_gate()
	_test_first_story_delivery()
	_test_selection_and_eligibility()
	_test_relationship_recovery()
	_test_completion_and_roundtrip()
	_test_completed_history_retention()
	_test_saved_schema_validation()
	if failures.is_empty():
		print("PASS company_cycle %d assertions" % assertions)
	else:
		for failure in failures: print("FAIL company_cycle: ", failure)
		print("FAIL company_cycle %d failures / %d assertions" % [failures.size(), assertions])
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)

func _new_game() -> FakeGame:
	var game := FakeGame.new()
	CYCLE.ensure(game.state)
	return game

func _other_state(game: FakeGame) -> String:
	var copy: Dictionary = game.state.duplicate(true)
	copy.erase("company_cycle")
	return JSON.stringify(copy)

func _receipt(case_id: String, rating: String = "on_time", satisfaction: int = 75) -> Dictionary:
	var authored: Dictionary = CATALOG.by_id(case_id)
	return {"case_id":case_id,"client":str(authored.get("client","")),"title":str(authored.get("title","")),"rating":rating,"satisfaction_after":satisfaction,"checks":[{"passed":true}],"day":1}

func _record(game: FakeGame, contract_id: String, receipt: Dictionary) -> Dictionary:
	game.state.completed_ids.append(contract_id)
	game.state.history.append({"id":contract_id,"case_id":str(receipt.get("case_id","")),"day":int(receipt.get("day",1))})
	game.state.customer_relations[str(receipt.get("client",""))] = {"satisfaction":int(receipt.get("satisfaction_after",0))}
	var before := _other_state(game)
	var result: Dictionary = CYCLE.record_delivery(game, contract_id, receipt)
	_expect(_other_state(game) == before, "record only changes company_cycle: " + contract_id)
	return result

func _lead(game: FakeGame, client: String = CLIENT) -> Dictionary:
	return game.state.get("company_cycle",{}).get("leads",{}).get(client,{})

func _public_lead(game: FakeGame, client: String = CLIENT) -> Dictionary:
	var snapshot: Dictionary = CYCLE.view(game)
	for lead in snapshot.get("leads",[]):
		if str(lead.get("client","")) == client: return lead
	return {}

func _test_legacy_and_receipt_gate() -> void:
	var game := FakeGame.new()
	game.state.history = [{"id":"legacy-delivery","case_id":SOURCE,"grade":"S","profit":9000}]
	game.state.completed_ids = ["legacy-delivery"]
	var before := _other_state(game)
	CYCLE.ensure(game.state)
	_expect(_other_state(game) == before, "migration preserves historical money, VM and history")
	_expect(int(game.state.get("company_cycle",{}).get("version",0)) == 1, "cycle schema version")
	_expect(game.state.company_cycle.leads.is_empty() and game.state.company_cycle.events.is_empty(), "legacy history does not backfill leads or events")
	_expect(game.state.company_cycle.processed_deliveries.is_empty(), "legacy history is not guessed as fresh receipts")
	var initialized := JSON.stringify(game.state)
	CYCLE.ensure(game.state)
	_expect(JSON.stringify(game.state) == initialized, "ensure is idempotent")
	CYCLE.view(game); CYCLE.priority_case_ids(game)
	_expect(JSON.stringify(game.state) == initialized, "view and priority do not credit legacy history")
	var missing_quality := _receipt(SOURCE)
	missing_quality.erase("rating")
	var rejected: Dictionary = CYCLE.record_delivery(game,"legacy-delivery",missing_quality)
	_expect(not bool(rejected.get("changed",false)) and game.state.company_cycle.leads.is_empty(), "missing receipt quality is not inferred from legacy grade")
	var no_delivery := _new_game()
	var raw: Dictionary = CYCLE.record_delivery(no_delivery,"uncompleted",_receipt(SOURCE))
	_expect(not bool(raw.get("changed",false)) and _lead(no_delivery).is_empty(), "uncompleted work cannot create a referral")
	print("PASS company_cycle group: legacy and receipt gates" if failures.is_empty() else "CHECK company_cycle group: legacy and receipt gates")

func _test_selection_and_eligibility() -> void:
	var game := _new_game()
	var created := _record(game,"source-1",_receipt(SOURCE))
	_expect(bool(created.get("changed",false)), "fresh delivery creates cycle event")
	var lead := _lead(game)
	_expect(str(lead.get("case_id","")) == NEXT, "stable next case for Tsubasa is external sharing expiry")
	_expect(str(lead.get("status","")) == "pending", "locked lead remains persisted pending")
	var target: Dictionary = CATALOG.by_id(str(lead.get("case_id","")))
	var source: Dictionary = CATALOG.by_id(SOURCE)
	_expect(str(target.get("client","")) == CLIENT and str(target.get("id","")) != SOURCE, "same customer gets distinct authored case")
	_expect(str(target.get("work_family","")) != str(source.get("work_family","")), "another available work family is preferred")
	_expect(not bool(target.get("retired_from_new_offers",true)), "retired cases never become referrals")
	var snapshot := JSON.stringify(game.state)
	var duplicate: Dictionary = CYCLE.record_delivery(game,"source-1",_receipt(SOURCE))
	_expect(not bool(duplicate.get("changed",false)) and JSON.stringify(game.state) == snapshot, "same contract is fully idempotent")
	var public_lead := _public_lead(game)
	_expect(str(public_lead.get("status","")) == "locked", "level requirement is exposed as locked")
	_expect(int(public_lead.get("required_level",0)) == 2 and not public_lead.get("reasons",[]).is_empty(), "locked lead explains authored level requirement")
	_expect(NEXT not in CYCLE.priority_case_ids(game), "locked level cannot bypass market eligibility")
	game.level = 2; game.state.skills.advisory = 0
	public_lead = _public_lead(game)
	_expect(str(public_lead.get("status","")) == "locked" and not public_lead.get("required_skills",{}).is_empty(), "skills still lock a level-qualified lead")
	_expect(NEXT not in CYCLE.priority_case_ids(game), "locked skill cannot bypass market eligibility")
	game.state.skills.advisory = 1
	_expect(str(_public_lead(game).get("status","")) == "ready" and NEXT in CYCLE.priority_case_ids(game), "eligible pending lead becomes ready and prioritized")
	var before := JSON.stringify(_lead(game))
	_record(game,"other-client",_receipt("service-0-case-1"))
	_expect(JSON.stringify(_lead(game)) == before, "another customer's delivery does not alter Tsubasa's lead")
	_expect(game.state.company_cycle.leads.size() <= 2, "at most one lead per customer")
	print("PASS company_cycle group: selection and eligibility" if failures.is_empty() else "CHECK company_cycle group: selection and eligibility")

func _test_first_story_delivery() -> void:
	var game := _new_game()
	game.state.career_mode = false
	var receipt := {"case_id":"","client":CLIENT,"title":"最初の共有復旧","rating":"on_time","satisfaction_after":75,"checks":[{"passed":true}],"day":1}
	_record(game,"share",receipt)
	var lead := _lead(game)
	_expect(str(lead.get("case_id","")) == NEXT, "first story chapter selects another family without inventing source case")
	_expect(str(lead.get("source_case_id","unexpected")) == "", "first story retains empty source case id")
	_expect(str(lead.get("source_contract_id","")) == "share", "first story retains actual source contract id")
	_expect(str(_public_lead(game).get("status","")) == "locked", "first story referral explains future eligibility")

func _test_relationship_recovery() -> void:
	for quality in ["late","rework"]:
		var game := _new_game(); game.level = 20
		game.state.skills = {"advisory":10,"operations":10,"response":10}
		_record(game,"bad-source-"+quality,_receipt(SOURCE,quality,35))
		_expect(str(_lead(game).get("status","")) == "paused", "poor first delivery creates paused lead: " + quality)
		_expect(str(_public_lead(game).get("status","")) == "paused" and NEXT not in CYCLE.priority_case_ids(game), "paused referral cannot become market priority: " + quality)
		var recovery: Dictionary = CYCLE.view(game)
		_expect(not recovery.get("relationship_recovery",[]).is_empty(), "relationship recovery is exposed: " + quality)
		_record(game,"poor-relationship-"+quality,_receipt(SOURCE,"on_time",39))
		_expect(str(_lead(game).get("status","")) == "paused", "on-time delivery below satisfaction 40 remains paused")
		_record(game,"recovered-"+quality,_receipt(SOURCE,"on_time",40))
		_expect(str(_lead(game).get("status","")) == "pending" and NEXT in CYCLE.priority_case_ids(game), "real on-time delivery at satisfaction 40 resumes referral")
		_record(game,"later-bad-"+quality,_receipt(SOURCE,quality,60))
		_expect(str(_lead(game).get("status","")) == "paused" and NEXT not in CYCLE.priority_case_ids(game), "later poor delivery pauses existing referral even above 40")
	print("PASS company_cycle group: relationship recovery" if failures.is_empty() else "CHECK company_cycle group: relationship recovery")

func _test_completion_and_roundtrip() -> void:
	var game := _new_game(); game.level = 20
	game.state.skills = {"advisory":10,"operations":10,"response":10}
	_record(game,"source-for-save",_receipt(SOURCE))
	var restored := FakeGame.new(); restored.level = game.level
	restored.state = JSON.parse_string(JSON.stringify(game.state))
	CYCLE.ensure(restored.state)
	# JSON numbers decode as floats. Normalize both complete views to the same
	# wire representation, preserving every field while comparing 1 and 1.0 fairly.
	var original_view := JSON.stringify(JSON.parse_string(JSON.stringify(CYCLE.view(game))))
	var restored_view := JSON.stringify(JSON.parse_string(JSON.stringify(CYCLE.view(restored))))
	_expect(restored_view == original_view, "JSON reload preserves public lead and event content")
	_expect(CYCLE.priority_case_ids(restored) == CYCLE.priority_case_ids(game), "JSON reload preserves priority order")
	var before := JSON.stringify(restored.state)
	CYCLE.record_delivery(restored,"source-for-save",_receipt(SOURCE))
	_expect(JSON.stringify(restored.state) == before, "processed delivery remains idempotent after JSON reload")
	var events_before: int = restored.state.company_cycle.events.size()
	_record(restored,"completed-referral",_receipt(NEXT))
	_expect(restored.state.company_cycle.processed_deliveries.has("completed-referral"), "actual target delivery is processed")
	_expect(restored.state.company_cycle.events.size() > events_before, "actual target delivery records outcome event")
	_expect(NEXT not in CYCLE.priority_case_ids(restored), "completed target is no longer a market priority")
	var lead := _lead(restored)
	_expect(str(lead.get("case_id","")) != NEXT or str(lead.get("status","")) == "fulfilled", "completed referral is fulfilled or replaced by next distinct lead")
	if str(lead.get("status","")) in ["pending","paused"]:
		_expect(str(lead.get("case_id","")) not in [SOURCE,NEXT], "new lead excludes all previously completed cases")
		var next_case: Dictionary = CATALOG.by_id(str(lead.get("case_id","")))
		_expect(str(next_case.get("client","")) == CLIENT and not bool(next_case.get("retired_from_new_offers",true)), "subsequent referral stays same-customer and nonretired")
	var exhausted := _new_game(); exhausted.level = 20
	exhausted.state.skills = {"advisory":10,"operations":10,"response":10}
	_record(exhausted,"last-source",_receipt(SOURCE))
	for item in CATALOG.all():
		if str(item.get("client","")) == CLIENT and str(item.get("id","")) not in [SOURCE,NEXT]:
			exhausted.state.history.append({"id":"earlier-"+str(item.id),"case_id":str(item.id)})
	_record(exhausted,"last-referral",_receipt(NEXT))
	_expect(str(_lead(exhausted).get("status","")) == "fulfilled", "exhausted customer retains fulfilled referral")
	_expect(str(_public_lead(exhausted).get("status","")) == "fulfilled", "fulfilled status is publicly visible")
	_expect(CYCLE.priority_case_ids(exhausted).is_empty(), "completed or retired catalog cannot be reissued as referrals")
	var later := _receipt(SOURCE, "late", 55); later.day = 2
	_record(exhausted, "later-customer-delivery", later)
	_expect(int(_public_lead(exhausted).last_outcome.satisfaction) == 55 and int(_public_lead(exhausted).last_outcome.day) == 2, "fulfilled customer's gauge retains latest actual delivery, not the original satisfaction")
	_expect(str(_lead(exhausted).status) == "fulfilled" and str(_lead(exhausted).fulfilled_contract_id) == "last-referral", "later delivery does not undo previously fulfilled work")
	print("PASS company_cycle group: completion and persistence" if failures.is_empty() else "CHECK company_cycle group: completion and persistence")

func _test_completed_history_retention() -> void:
	var game := _new_game(); game.level = 20
	game.state.skills = {"advisory":10,"operations":10,"response":10}
	_record(game,"retention-source",_receipt(SOURCE))
	var completed: Array[String] = [SOURCE]
	# Complete the actual referrals, rather than seeding completion metadata.
	for index in CATALOG.all().size():
		var lead := _lead(game)
		if str(lead.get("status","")) != "pending": break
		var case_id := str(lead.get("case_id",""))
		_expect(case_id not in completed, "referral chain never repeats a completed case")
		_record(game,"retention-target-%d" % index,_receipt(case_id))
		completed.append(case_id)
	_expect(completed.size() >= 3 and NEXT in completed, "retention fixture completes source, next and later real referrals")
	_expect(str(_lead(game).get("status","")) == "fulfilled", "actual referral chain reaches authored customer catalog end")
	game.state.history = [game.state.history.back().duplicate(true)]
	var reloaded := FakeGame.new(); reloaded.level = game.level
	reloaded.state = JSON.parse_string(JSON.stringify(game.state))
	CYCLE.ensure(reloaded.state)
	_record(reloaded,"retention-repeat-after-trim",_receipt(completed.back()))
	_expect(str(_lead(reloaded).get("status","")) == "fulfilled", "trimmed history and JSON reload do not reopen completed referrals")
	_expect(CYCLE.priority_case_ids(reloaded).is_empty(), "completed referral memory survives ordinary history retention")
	print("PASS company_cycle group: completed history retention" if failures.is_empty() else "CHECK company_cycle group: completed history retention")

func _reject_cycle(value: Variant, label: String) -> void:
	_expect(not CYCLE.validate(value), "reject malformed cycle: " + label)
	var state := {"company_cycle":value,"cash":900,"vm_states":{"kept":"unchanged"}}
	var before := JSON.stringify(state)
	CYCLE.ensure(state)
	_expect(JSON.stringify(state) == before, "ensure never resets invalid saved cycle: " + label)

func _test_saved_schema_validation() -> void:
	var minimal := {"version":1,"leads":{},"events":[],"processed_deliveries":{}}
	_expect(CYCLE.validate(minimal), "minimal version 1 schema accepts absent optional maps")
	for value in [null, [], "invalid", 1]: _reject_cycle(value,"root " + str(typeof(value)))
	for key in ["version","leads","events","processed_deliveries"]:
		var missing: Dictionary = minimal.duplicate(true); missing.erase(key)
		_reject_cycle(missing,"missing " + key)
	for version in [0,2,"1",1.5,true]:
		var bad: Dictionary = minimal.duplicate(true); bad.version = version
		_reject_cycle(bad,"version " + str(version))
	for key in ["leads","processed_deliveries","completed_cases","earned_goals"]:
		var bad: Dictionary = minimal.duplicate(true); bad[key] = []
		_reject_cycle(bad,"map type " + key)
	var bad_events: Dictionary = minimal.duplicate(true); bad_events.events = {}
	_reject_cycle(bad_events,"events not array")
	bad_events.events = ["not a dictionary"]
	_reject_cycle(bad_events,"event not dictionary")
	for processed in [1,"true",{},null]:
		var bad: Dictionary = minimal.duplicate(true); bad.processed_deliveries["completed-contract"] = processed
		_reject_cycle(bad,"processed delivery is not boolean: " + str(typeof(processed)))
	var game := _new_game()
	_record(game,"schema-source",_receipt(SOURCE))
	var valid: Dictionary = game.state.company_cycle.duplicate(true)
	_expect(CYCLE.validate(valid), "actual generated lead and event satisfy saved schema")
	_expect(CYCLE.validate(JSON.parse_string(JSON.stringify(valid))), "integer-valued JSON floats satisfy saved schema")
	for status in ["pending","paused","fulfilled"]:
		var accepted: Dictionary = valid.duplicate(true); accepted.leads[CLIENT].status = status
		_expect(CYCLE.validate(accepted), "persisted lead status accepted: " + status)
	for status in ["ready","locked","unknown",1]:
		var bad: Dictionary = valid.duplicate(true); bad.leads[CLIENT].status = status
		_reject_cycle(bad,"public or malformed persisted status: " + str(status))
	var mismatched: Dictionary = valid.duplicate(true)
	mismatched.leads["different customer"] = mismatched.leads[CLIENT]; mismatched.leads.erase(CLIENT)
	_reject_cycle(mismatched,"customer map key does not match lead client")
	var nonlead: Dictionary = valid.duplicate(true); nonlead.leads[CLIENT] = []
	_reject_cycle(nonlead,"lead not dictionary")
	for key in ["id","client","case_id","source_contract_id"]:
		var empty_id: Dictionary = valid.duplicate(true); empty_id.leads[CLIENT][key] = ""
		_reject_cycle(empty_id,"empty identifier " + key)
		var wrong_id: Dictionary = valid.duplicate(true); wrong_id.leads[CLIENT][key] = 7
		_reject_cycle(wrong_id,"identifier not string " + key)
	for requirements in [[],"advisory",{"advisory":"1"},{"advisory":1.5},{"advisory":-1}]:
		var bad: Dictionary = valid.duplicate(true); bad.leads[CLIENT].required_skills = requirements
		_reject_cycle(bad,"malformed required skills " + JSON.stringify(requirements))
	for level in ["2",2.5,-1]:
		var bad: Dictionary = valid.duplicate(true); bad.leads[CLIENT].required_level = level
		_reject_cycle(bad,"malformed required level " + str(level))
	var with_goal: Dictionary = valid.duplicate(true)
	with_goal.earned_goals = {"first-referral":{"day":2,"title":"顧客からの次の依頼"}}
	_expect(CYCLE.validate(with_goal), "earned goal integer day and string title accepted")
	_expect(CYCLE.validate(JSON.parse_string(JSON.stringify(with_goal))), "earned goal JSON integer-valued day accepted")
	for day in ["2",2.5,-1]:
		var bad: Dictionary = with_goal.duplicate(true); bad.earned_goals["first-referral"].day = day
		_reject_cycle(bad,"malformed earned goal day " + str(day))
	var bad_goal: Dictionary = with_goal.duplicate(true); bad_goal.earned_goals["first-referral"].title = 4
	_reject_cycle(bad_goal,"earned goal title not string")
	bad_goal = with_goal.duplicate(true); bad_goal.earned_goals["first-referral"] = []
	_reject_cycle(bad_goal,"earned goal not dictionary")
	var future: Dictionary = with_goal.duplicate(true)
	future.extension = {"keep":["future metadata",7]}
	future.leads[CLIENT].extension = {"source":"unrecognized but retained"}
	future.events[0].extension = "keep event metadata"
	_expect(CYCLE.validate(future), "unknown extra fields do not invalidate otherwise valid schema")
	var future_state := {"company_cycle":future}; var before := JSON.stringify(future_state)
	CYCLE.ensure(future_state)
	_expect(JSON.stringify(future_state) == before, "ensure preserves unknown fields and all valid saved values")
	print("PASS company_cycle group: saved schema validation" if failures.is_empty() else "CHECK company_cycle group: saved schema validation")
