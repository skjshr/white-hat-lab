extends RefCounted
## Offline environments with executable request, traffic and build models.

const IDS := ["advanced-ddos", "advanced-api", "advanced-supplychain"]

static func create(case_id: String) -> Dictionary:
	if case_id not in IDS: return {}
	var s: Dictionary = {"case_id":case_id,"kind":case_id,"revision":0,"world_revision":0,"clock":0,"events":[],"evidence":{},"inspected":[],"measurements":{},"last_result":{},"model":{}}
	if case_id == "advanced-ddos":
		s.model = {"rule":{"route":"*","mode":"count","limit":100},"capacity":300,"session":{"id":"sid-74","user":"svc-release","active":true},"task":{"id":"cache-sync-12","command":"sync /srv/orders remote-archive","enabled":true},"requests":[{"id":"r01","route":"/checkout","method":"POST","rate":50,"cost":2,"client":"customer-web"},{"id":"r02","route":"/catalog","method":"GET","rate":90,"cost":1,"client":"campaign-web"},{"id":"r03","route":"/search","method":"GET","rate":650,"cost":3,"client":"shared-proxy"},{"id":"r04","route":"/search","method":"GET","rate":5,"cost":3,"client":"customer-web"}],"exports":0}
		_event(s,"ingress-01","edge01","traffic","09:01 /search rate=655/s; /checkout rate=50/s; /catalog rate=90/s; capacity=300 work/s")
		_event(s,"auth-74","admin01","identity","08:57 session=sid-74 user=svc-release src=198.51.100.74; change-window=none")
		_event(s,"task-12","store01","scheduler","08:58 session=sid-74 created task=cache-sync-12 command=sync /srv/orders remote-archive")
		_event(s,"ops-05","store01","scheduler","08:00 task=invoice-job owner=finance approved=yes; output=/srv/invoices")
	elif case_id == "advanced-api":
		s.model = {"policy":{"tenant":false,"approval":false,"job_owner":false},"users":{"alice":{"tenant":"north","role":"employee"},"noah":{"tenant":"north","role":"reviewer"},"beth":{"tenant":"south","role":"reviewer"}},"invoices":{"INV-N01":{"tenant":"north","owner":"alice","state":"draft","amount":18000},"INV-S01":{"tenant":"south","owner":"beth","state":"draft","amount":27000}},"jobs":{},"proofs":{},"retest":{},"request_count":0}
		_event(s,"api-scope","api01","contract","Allowed: test tenants north/south; /invoices and /exports; fixtures only")
		_event(s,"api-policy","api01","spec","Employees read own-tenant invoices; reviewers approve own-tenant invoices; export downloads are creator-bound")
		_event(s,"api-roles","identity01","directory","alice=north/employee; noah=north/reviewer; beth=south/reviewer")
	else:
		var source := "service orders-api\nGET /orders -> HTTP 200\n"
		var dependency := "csv-parser 2.4.1\n"
		var clean := source + dependency
		var dirty := clean + "POSTBUILD: remote_sync /srv/orders\n"
		s.model = {"source":source,"dependency":dependency,"hook":"postbuild-sync","signer":"ci-key-01","revoked_keys":[],"pipeline_session":true,"blocked":[],"artifacts":{"pkg-41":{"bytes":clean,"signer":"ci-key-00","source_sha":source.sha256_text(),"dependency_sha":dependency.sha256_text(),"builder":"build01","steps":["compile","package"]},"pkg-42":{"bytes":dirty,"signer":"ci-key-01","source_sha":source.sha256_text(),"dependency_sha":dependency.sha256_text(),"builder":"build01","steps":["compile","postbuild-sync","package"]}},"deployments":{"orders-a":"pkg-42","orders-b":"pkg-42"},"build_count":42,"last_build":"","accesses":0}
		_event(s,"deploy-42","registry01","release","09:12 pkg-42 signed=ci-key-01 deployed=orders-a,orders-b; source revision unchanged")
		_event(s,"build-42","build01","build","09:08 job=42 steps=compile,postbuild-sync,package; source and dependency hashes retained")
		_event(s,"token-42","build01","identity","09:06 token=runner-session-19 scope=pipeline:write source=198.51.100.74; approved-change=none")
		_event(s,"egress-42","orders-a","network","09:13 process=orders-api destination=remote-archive action=POST /orders")
	return s

static func _event(s: Dictionary, id: String, asset: String, source: String, detail: String) -> void:
	s.events.append({"id":id,"time":"09:%02d" % (int(s.clock) % 60),"asset":asset,"source":source,"detail":detail,"pinned":false})

static func _node(id: String, detail: String, x: float, y: float) -> Dictionary:
	return {"id":id,"label":id,"detail":detail,"status_key":"adv_state_ready","x":x,"y":y}

static func _edge(from: String, to: String, label: String) -> Dictionary:
	return {"from":from,"to":to,"label":label}

static func _record(id: String, label: String, detail: String) -> Dictionary:
	return {"id":id+"/"+label,"label":label,"detail":detail,"status_key":"adv_state_ready"}

static func _action(id: String, target: String, options: Array = []) -> Dictionary:
	var choices: Array = []
	for option in options:
		choices.append({"id":str(option),"label":str(option)})
	return {"id":id,"label_key":"adv_action_"+id,"target":target,"options":choices}

static func _world(s: Dictionary) -> void:
	s.world_revision = int(s.world_revision) + 1
	s.measurements = {}

static func _result(s: Dictionary, ok: bool, key: String, detail: String = "", minutes: float = 2.0) -> Dictionary:
	s.revision = int(s.revision) + 1
	s.clock = int(s.clock) + int(minutes)
	if not detail.is_empty(): _event(s,"op-%d" % int(s.revision),"console","operation",detail)
	var result: Dictionary = {"ok":ok,"changed":true,"minutes":minutes,"result_key":key,"result_args":[]}
	s.last_result = result.duplicate(true)
	return result

static func _invalid() -> Dictionary:
	return {"ok":false,"changed":false,"minutes":0.0,"result_key":"adv_result_unknown","result_args":[]}

static func act(s: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	if str(s.get("case_id", "")) not in IDS: return _invalid()
	var target := str(args.get("target", ""))
	var option := str(args.get("option", ""))
	if action == "pin":
		for event in s.events:
			if str(event.id) == target:
				var preserved: Dictionary = event.duplicate(true)
				preserved.sha256 = str(event.detail).sha256_text()
				s.evidence[target] = preserved
				return _result(s,true,"adv_result_evidence","",0)
		return _invalid()
	if action == "inspect":
		var valid: bool = view(s).nodes.any(func(n: Dictionary): return str(n.id) == target)
		if not valid: return _invalid()
		if target not in s.inspected: s.inspected.append(target)
		return _result(s,true,"adv_result_observed","inspect " + target,1)
	match str(s.case_id):
		"advanced-ddos": return _ddos_action(s,action,target,option)
		"advanced-api": return _api_action(s,action,target,option)
		"advanced-supplychain": return _supply_action(s,action,target,option)
	return _invalid()

static func _traffic(s: Dictionary) -> Dictionary:
	var m: Dictionary = s.model
	var load_value := 0.0
	var accepted: Dictionary = {}
	for request in m.requests:
		var count := float(request.rate)
		if str(m.rule.route) in ["*",str(request.route)]:
			if str(m.rule.mode) == "block": count = 0
			elif str(m.rule.mode) == "limit": count = minf(count,float(m.rule.limit))
		accepted[str(request.id)] = count
		load_value += count * float(request.cost)
	var available := load_value <= float(m.capacity)
	return {"load":load_value,"capacity":m.capacity,"checkout":available and float(accepted.r01) == 50.0,"catalog":available and float(accepted.r02) == 90.0,"search":available and float(accepted.r04) == 5.0,"unauthorized":bool(m.session.active) or bool(m.task.enabled)}

static func _ddos_action(s: Dictionary, action: String, target: String, option: String) -> Dictionary:
	var m: Dictionary = s.model
	if action == "apply_rule" and target == "waf01":
		var parts := option.split("|")
		if parts.size() != 3 or parts[0] not in ["*","/search","/checkout","/catalog"] or parts[1] not in ["count","limit","block"] or not str(parts[2]).is_valid_int(): return _invalid()
		m.rule = {"route":parts[0],"mode":parts[1],"limit":clampi(int(parts[2]),0,1000)}
		_world(s)
		return _result(s,true,"adv_result_changed","WAF " + option,4)
	if action == "revoke" and target == "admin01" and option == "sid-74" and target in s.inspected:
		m.session.active = false; _world(s)
		return _result(s,true,"adv_result_changed","session sid-74 revoked",3)
	if action == "disable_task" and target == "store01" and option == "cache-sync-12" and target in s.inspected:
		m.task.enabled = false; _world(s)
		return _result(s,true,"adv_result_changed","task cache-sync-12 disabled",3)
	if action == "measure":
		var actual := _traffic(s)
		if bool(actual.unauthorized): m.exports = int(m.exports) + 1
		s.measurements = actual.duplicate(true); s.measurements.revision = s.world_revision
		return _result(s,true,"adv_result_measured",JSON.stringify(actual),4)
	return _invalid()

static func _api_request(s: Dictionary, actor: String, operation: String, resource: String) -> Dictionary:
	var m: Dictionary = s.model
	if not m.users.has(actor): return {"status":401,"body":"unauthenticated"}
	var user: Dictionary = m.users[actor]
	if operation == "download":
		if not m.jobs.has(resource): return {"status":404,"body":"job not found"}
		var job: Dictionary = m.jobs[resource]
		if bool(m.policy.job_owner) and str(job.owner) != actor: return {"status":403,"body":"export owner mismatch"}
		return {"status":200,"body":str(job.bytes)}
	if not m.invoices.has(resource): return {"status":404,"body":"invoice not found"}
	var invoice: Dictionary = m.invoices[resource]
	if bool(m.policy.tenant) and str(invoice.tenant) != str(user.tenant): return {"status":403,"body":"tenant mismatch"}
	if operation == "approve":
		if bool(m.policy.approval) and str(user.role) != "reviewer": return {"status":403,"body":"reviewer required"}
		invoice.state = "approved"
		return {"status":200,"body":"approved " + resource}
	if operation == "export":
		var job_id := "job-"+actor+"-"+resource
		m.jobs[job_id] = {"owner":actor,"tenant":invoice.tenant,"bytes":"invoice,amount,state\n%s,%d,%s\n" % [resource,int(invoice.amount),str(invoice.state)]}
		return {"status":201,"body":job_id}
	if operation == "read": return {"status":200,"body":JSON.stringify(invoice)}
	return {"status":400,"body":"operation not supported"}

static func _api_issue(m: Dictionary, actor: String, operation: String, resource: String) -> String:
	if operation == "download" and m.jobs.has(resource) and str(m.jobs[resource].owner) != actor: return "job_owner"
	if m.invoices.has(resource) and m.users.has(actor):
		if str(m.invoices[resource].tenant) != str(m.users[actor].tenant): return "tenant"
		if operation == "approve" and str(m.users[actor].role) != "reviewer": return "approval"
	return ""

static func _api_action(s: Dictionary, action: String, target: String, option: String) -> Dictionary:
	var m: Dictionary = s.model
	if action == "request":
		var parts := option.split("|")
		if parts.size() != 2: return _invalid()
		var actor := str(parts[0]); var operation := str(parts[1])
		var issue := _api_issue(m,actor,operation,target)
		var response := _api_request(s,actor,operation,target)
		m.request_count = int(m.request_count) + 1
		var record: Dictionary = {"actor":actor,"operation":operation,"resource":target,"response":response.duplicate(true),"evidence_id":"http-%d" % int(m.request_count)}
		if not issue.is_empty() and int(response.status) in [200,201]: m.proofs[issue] = record.duplicate(true)
		_world(s); m.retest = {}
		_event(s,"http-%d" % int(m.request_count),target,"HTTP",JSON.stringify(record))
		return _result(s,true,"adv_result_observed","",2)
	if action == "set_policy" and target == "api01":
		var parts := option.split("|")
		if parts.size() != 2 or not m.policy.has(parts[0]) or parts[1] not in ["enforce","audit"]: return _invalid()
		m.policy[parts[0]] = parts[1] == "enforce"; m.retest = {}; _world(s)
		return _result(s,true,"adv_result_changed","policy " + option,4)
	if action == "retest":
		var results: Dictionary = {}
		for issue in m.proofs:
			var proof: Dictionary = m.proofs[issue]
			results[issue] = _api_request(s,str(proof.actor),str(proof.operation),str(proof.resource))
		m.retest = {"revision":s.world_revision,"results":results}
		return _result(s,true,"adv_result_measured","replay " + JSON.stringify(results),5)
	if action == "measure":
		var own := _api_request(s,"alice","read","INV-N01")
		var approval := _api_request(s,"noah","approve","INV-N01")
		var export_result := _api_request(s,"noah","export","INV-N01")
		var download := _api_request(s,"noah","download",str(export_result.body))
		s.measurements = {"revision":s.world_revision,"own":own,"approval":approval,"export":export_result,"download":download}
		return _result(s,true,"adv_result_measured",JSON.stringify(s.measurements),5)
	return _invalid()

static func _clean_bytes(m: Dictionary) -> String:
	return str(m.source)+str(m.dependency)

static func _artifact_trusted(m: Dictionary, artifact: Dictionary) -> bool:
	return str(artifact.get("bytes", "")) == _clean_bytes(m) and str(artifact.get("source_sha", "")) == str(m.source).sha256_text() and str(artifact.get("dependency_sha", "")) == str(m.dependency).sha256_text() and str(artifact.get("signer", "")) not in m.revoked_keys

static func _supply_action(s: Dictionary, action: String, target: String, option: String) -> Dictionary:
	var m: Dictionary = s.model
	if action == "quarantine" and target == "registry01" and m.artifacts.has(option):
		if option not in m.blocked: m.blocked.append(option)
		_world(s); return _result(s,true,"adv_result_changed","quarantine artifact " + option,3)
	if action == "revoke" and target == "build01" and option == "runner-session-19" and target in s.inspected:
		m.pipeline_session = false; _world(s)
		return _result(s,true,"adv_result_changed","pipeline session revoked",3)
	if action == "rotate" and target == "build01" and target in s.inspected:
		if str(m.signer) not in m.revoked_keys: m.revoked_keys.append(str(m.signer))
		m.signer = "ci-key-%02d" % (m.revoked_keys.size() + 1); _world(s)
		return _result(s,true,"adv_result_changed","new signer " + str(m.signer),4)
	if action == "remove_hook" and target == "build01" and target in s.inspected:
		m.hook = ""; _world(s)
		return _result(s,true,"adv_result_changed","postbuild hook removed",3)
	if action == "build" and target == "build01":
		if bool(m.pipeline_session):
			m.hook = "postbuild-sync"
			_event(s,"pipeline-%d" % int(s.revision),"build01","audit","runner-session-19 reapplied pipeline step postbuild-sync")
		var contents := _clean_bytes(m)
		var steps: Array = ["compile"]
		if not str(m.hook).is_empty(): contents += "POSTBUILD: remote_sync /srv/orders\n"; steps.append(str(m.hook))
		steps.append("package"); m.build_count = int(m.build_count) + 1
		var id := "pkg-%d" % int(m.build_count)
		m.artifacts[id] = {"bytes":contents,"signer":m.signer,"source_sha":str(m.source).sha256_text(),"dependency_sha":str(m.dependency).sha256_text(),"builder":"build01","steps":steps}
		m.last_build = id; _world(s)
		_event(s,"build-"+id,"build01","build",id+" sha256="+contents.sha256_text()+" steps="+str(steps))
		return _result(s,true,"adv_result_built",id,8)
	if action == "deploy" and m.deployments.has(target) and m.artifacts.has(option):
		if option in m.blocked or str(m.artifacts[option].signer) in m.revoked_keys: return _result(s,false,"adv_result_denied","deploy rejected " + option,1)
		m.deployments[target] = option; _world(s)
		return _result(s,true,"adv_result_changed","deploy " + target + " " + option,4)
	if action == "measure":
		var endpoints: Dictionary = {}
		for host in m.deployments:
			var artifact: Dictionary = m.artifacts[str(m.deployments[host])]
			var leaked: bool = str(artifact.bytes).contains("remote_sync")
			if leaked: m.accesses = int(m.accesses) + 1
			endpoints[host] = {"status":200 if str(artifact.bytes).contains("HTTP 200") else 503,"egress":leaked,"sha256":str(artifact.bytes).sha256_text(),"trusted":_artifact_trusted(m,artifact)}
		s.measurements = {"revision":s.world_revision,"endpoints":endpoints}
		return _result(s,true,"adv_result_measured",JSON.stringify(endpoints),5)
	return _invalid()

static func _check(id: String, passed: bool) -> Dictionary:
	return {"id":id,"label_key":"adv_check_"+id,"passed":passed}

static func checks(s: Dictionary) -> Array:
	var m: Dictionary = s.get("model", {})
	var measured: Dictionary = s.get("measurements", {})
	var fresh := not measured.is_empty() and int(measured.get("revision", -1)) == int(s.get("world_revision",0))
	var evidence: Dictionary = s.get("evidence", {})
	match str(s.get("case_id", "")):
		"advanced-ddos":
			var actual := _traffic(s)
			return [_check("ddos_evidence",evidence.has("ingress-01") and evidence.has("auth-74") and evidence.has("task-12")),_check("ddos_capacity",fresh and float(actual.load) <= float(actual.capacity)),_check("ddos_business",fresh and bool(actual.checkout) and bool(actual.catalog) and bool(actual.search)),_check("ddos_access",fresh and not bool(actual.unauthorized))]
		"advanced-api":
			var proved: bool = ["tenant","approval","job_owner"].all(func(k: String): return m.proofs.has(k))
			var retest: Dictionary = m.retest
			var blocked := int(retest.get("revision",-1)) == int(s.world_revision)
			for issue in ["tenant","approval","job_owner"]:
				blocked = blocked and int(retest.get("results",{}).get(issue,{}).get("status",0)) == 403
			var preserved := proved
			for issue in m.proofs:
				preserved = preserved and evidence.has(str(m.proofs[issue].get("evidence_id", "")))
			var business := fresh and int(measured.get("own",{}).get("status",0)) == 200 and int(measured.get("approval",{}).get("status",0)) == 200 and int(measured.get("download",{}).get("status",0)) == 200
			return [_check("api_proof",proved),_check("api_evidence",preserved),_check("api_retest",blocked),_check("api_business",business)]
		"advanced-supplychain":
			var clean: bool = fresh and measured.get("endpoints",{}).size() == 2
			for endpoint in measured.get("endpoints",{}).values(): clean = clean and int(endpoint.status) == 200 and not bool(endpoint.egress) and bool(endpoint.trusted)
			var built := not str(m.last_build).is_empty() and _artifact_trusted(m,m.artifacts.get(str(m.last_build),{}))
			return [_check("supply_evidence",evidence.has("build-42") and evidence.has("token-42") and evidence.has("egress-42")),_check("supply_pipeline",not bool(m.pipeline_session) and str(m.hook).is_empty() and "ci-key-01" in m.revoked_keys),_check("supply_build",built and "pkg-42" in m.blocked),_check("supply_business",clean)]
	return []

static func view(s: Dictionary, selected: String = "") -> Dictionary:
	if str(s.get("case_id", "")) not in IDS: return {}
	var v: Dictionary = {"kind":s.case_id,"revision":s.revision,"nodes":[],"edges":[],"events":[],"records":[],"actions":[],"checks":checks(s),"last_result":s.last_result.duplicate(true)}
	for event in s.events:
		var visible: Dictionary = event.duplicate(true); visible.pinned = s.evidence.has(str(event.id)); v.events.append(visible)
	for event in s.evidence.values(): v.records.append(_record(str(event.id),str(event.source)+" / "+str(event.asset),str(event.detail)+"\nSHA256 "+str(event.sha256)))
	var m: Dictionary = s.model
	if str(s.case_id) == "advanced-ddos":
		v.nodes = [_node("edge01","HTTP ingress",0.03,0.12),_node("waf01","Request rules",0.35,0.12),_node("store01","Orders application",0.68,0.12),_node("admin01","Management sessions",0.35,0.62)]
		v.edges = [_edge("edge01","waf01","HTTP"),_edge("waf01","store01","HTTP"),_edge("admin01","store01","management")]
		if selected == "waf01":
			var options: Array = []
			for route in ["*","/search","/checkout","/catalog"]:
				for rule in ["count|100","limit|20","limit|100","block|0"]: options.append(route+"|"+rule)
			v.actions.append(_action("apply_rule",selected,options)); v.records.append(_record(selected,"WAF",JSON.stringify(m.rule)))
		if selected in s.inspected:
			if selected == "admin01":
				v.records.append(_record(selected,"Session",JSON.stringify(m.session))); v.actions.append(_action("revoke",selected,["sid-74"]))
			if selected == "store01":
				v.records.append(_record(selected,"Scheduled task",JSON.stringify(m.task))); v.actions.append(_action("disable_task",selected,["cache-sync-12"]))
			if selected == "edge01":
				for req in m.requests: v.records.append(_record(selected,str(req.id),JSON.stringify(req)))
	elif str(s.case_id) == "advanced-api":
		v.nodes = [_node("identity01","Accounts and roles",0.03,0.13),_node("api01","Authorization policy",0.35,0.13),_node("INV-N01","north / invoice",0.68,0.05),_node("INV-S01","south / invoice",0.68,0.62)]
		v.edges = [_edge("identity01","api01","session"),_edge("api01","INV-N01","HTTP"),_edge("api01","INV-S01","HTTP")]
		if selected == "api01":
			var options: Array = []
			for policy in m.policy:
				for mode in ["audit","enforce"]: options.append(str(policy)+"|"+mode)
			v.actions.append(_action("set_policy",selected,options)); v.records.append(_record(selected,"Policy",JSON.stringify(m.policy)))
		if selected == "identity01":
			for actor in m.users: v.records.append(_record(selected,str(actor),JSON.stringify(m.users[actor])))
		if m.invoices.has(selected):
			v.records.append(_record(selected,selected,JSON.stringify(m.invoices[selected])))
			var options: Array = []
			for actor in m.users:
				for op in ["read","approve","export"]: options.append(str(actor)+"|"+op)
			v.actions.append(_action("request",selected,options))
		for job_id in m.jobs:
			v.records.append(_record(str(job_id),str(job_id),JSON.stringify(m.jobs[job_id])))
			v.actions.append(_action("request",str(job_id),["alice|download","noah|download","beth|download"]))
		v.actions.append(_action("retest","api01"))
	else:
		v.nodes = [_node("source01","Source and dependencies",0.02,0.12),_node("build01","Build pipeline",0.34,0.12),_node("registry01","Signed artifacts",0.67,0.12),_node("orders-a","Orders replica A",0.34,0.64),_node("orders-b","Orders replica B",0.67,0.64)]
		v.edges = [_edge("source01","build01","build inputs"),_edge("build01","registry01","publish"),_edge("registry01","orders-a","deploy"),_edge("registry01","orders-b","deploy")]
		if selected == "source01":
			v.records.append(_record(selected,"source",str(m.source)+"SHA256 "+str(m.source).sha256_text())); v.records.append(_record(selected,"dependency",str(m.dependency)+"SHA256 "+str(m.dependency).sha256_text()))
		if selected == "build01":
			v.actions.append(_action("build",selected))
			if selected in s.inspected:
				v.records.append(_record(selected,"Pipeline","hook="+str(m.hook)+"; signer="+str(m.signer)+"; runner-session-19="+str(m.pipeline_session)))
				v.actions.append(_action("revoke",selected,["runner-session-19"])); v.actions.append(_action("rotate",selected)); v.actions.append(_action("remove_hook",selected))
		if selected == "registry01":
			for id in m.artifacts:
				var artifact: Dictionary = m.artifacts[id]
				v.records.append(_record(selected,str(id),"SHA256 "+str(artifact.bytes).sha256_text()+"; signer="+str(artifact.signer)+"; steps="+str(artifact.steps)+"\n"+str(artifact.bytes)))
			v.actions.append(_action("quarantine",selected,m.artifacts.keys()))
		if m.deployments.has(selected):
			v.records.append(_record(selected,"Installed",str(m.deployments[selected]))); v.actions.append(_action("deploy",selected,m.artifacts.keys()))
	if not selected.is_empty() and v.nodes.any(func(n: Dictionary): return str(n.id) == selected): v.actions.push_front(_action("inspect",selected))
	v.actions.append(_action("measure","environment"))
	if not s.measurements.is_empty(): v.records.append(_record("measurement","Latest measurement",JSON.stringify(s.measurements)))
	return v
