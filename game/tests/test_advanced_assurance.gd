extends SceneTree
const ENGINE = preload("res://scripts/advanced_assurance.gd")
var failures: Array[String] = []

func _init() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ",label)

func action(s: Dictionary, id: String, target: String = "", option: String = "") -> Dictionary:
	return ENGINE.act(s,id,{"target":target,"option":option})

func passed(s: Dictionary) -> bool:
	return ENGINE.checks(s).all(func(c: Dictionary): return bool(c.passed))

static func solution(case_id: String) -> Array:
	match case_id:
		"advanced-ddos": return [["pin","ingress-01"],["pin","auth-74"],["pin","task-12"],["inspect","admin01"],["inspect","store01"],["apply_rule","waf01","/search|limit|20"],["revoke","admin01","sid-74"],["disable_task","store01","cache-sync-12"],["measure","environment"]]
		"advanced-api": return [["request","INV-S01","alice|read"],["request","INV-N01","alice|approve"],["request","INV-S01","beth|export"],["request","job-beth-INV-S01","alice|download"],["pin","http-1"],["pin","http-2"],["pin","http-4"],["set_policy","api01","tenant|enforce"],["set_policy","api01","approval|enforce"],["set_policy","api01","job_owner|enforce"],["retest","api01"],["measure","environment"]]
		"advanced-supplychain": return [["pin","build-42"],["pin","token-42"],["pin","egress-42"],["inspect","build01"],["quarantine","registry01","pkg-42"],["revoke","build01","runner-session-19"],["rotate","build01"],["remove_hook","build01"],["build","build01"],["deploy","orders-a","pkg-43"],["deploy","orders-b","pkg-43"],["measure","environment"]]
	return []

func run() -> void:
	var traffic: Dictionary = ENGINE.create("advanced-ddos")
	action(traffic,"measure")
	check(not bool(traffic.measurements.checkout),"overload rejects normal orders")
	action(traffic,"apply_rule","waf01","*|block|0"); action(traffic,"measure")
	check(float(traffic.measurements.load) == 0 and not bool(traffic.measurements.checkout),"blanket block removes load but also business")
	action(traffic,"apply_rule","waf01","/search|limit|20"); action(traffic,"measure")
	check(bool(traffic.measurements.checkout) and bool(traffic.measurements.unauthorized),"availability restored while intrusion remains")
	check(not passed(traffic),"availability alone not delivery")
	var api: Dictionary = ENGINE.create("advanced-api")
	action(api,"request","INV-N01","alice|approve")
	check(str(api.model.invoices["INV-N01"].state) == "approved","unauthorized approval changes actual invoice")
	action(api,"set_policy","api01","approval|enforce")
	action(api,"request","INV-S01","alice|approve")
	check(str(api.model.invoices["INV-S01"].state) == "draft","role enforcement prevents unauthorized state mutation")
	var supply: Dictionary = ENGINE.create("advanced-supplychain")
	action(supply,"inspect","build01"); action(supply,"remove_hook","build01"); action(supply,"build","build01")
	check(str(supply.model.artifacts["pkg-43"].bytes).contains("remote_sync"),"stolen pipeline session reinserts real artifact bytes")
	action(supply,"quarantine","registry01","pkg-43")
	check(not bool(action(supply,"deploy","orders-a","pkg-43").ok),"quarantined artifact cannot deploy")
	for case_id in ENGINE.IDS:
		var s: Dictionary = ENGINE.create(case_id)
		check(not passed(s),"initial unsolved "+case_id)
		for step in solution(case_id):
			check(bool(action(s,str(step[0]),str(step[1]) if step.size()>1 else "",str(step[2]) if step.size()>2 else "").ok),"action "+case_id+" "+str(step))
		check(passed(s),"real solution "+case_id)
		var restored: Variant = JSON.parse_string(JSON.stringify(s))
		check(restored is Dictionary and passed(restored),"JSON resume "+case_id)
		if case_id == "advanced-ddos": action(s,"apply_rule","waf01","*|block|0")
		elif case_id == "advanced-api": action(s,"set_policy","api01","tenant|audit")
		else: action(s,"rotate","build01")
		check(not passed(s),"post-verification mutation stales outcome "+case_id)
	print("ADVANCED_ASSURANCE_PASS" if failures.is_empty() else "ADVANCED_ASSURANCE_FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
