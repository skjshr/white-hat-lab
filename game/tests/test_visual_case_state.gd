extends SceneTree

## Pure visual projection checks against real VM observations. Model variants and
## malformed/missing display records below are explicit isolated fixtures; they
## do not claim a full player journey or measured native accessibility.
const VM = preload("res://scripts/virtual_machine.gd")
const Catalog = preload("res://scripts/case_catalog.gd")
const Evidence = preload("res://scripts/network_request_evidence.gd")
const URL := "https://intranet.client.test/sales"
const LEDGER := "/srv/data/ledger.txt"
var network
var backup
var backup_console
var failures: Array[String] = []
var assertions := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL visual_case_state: ", label)

func run() -> void:
	network = load("res://scripts/network_request_visual.gd")
	backup = load("res://scripts/backup_visual.gd")
	backup_console = load("res://scripts/os_backup_console.gd")
	check(network != null and backup != null and backup_console != null, "visual helpers and restore-plan projection exist")
	if network == null or backup == null or backup_console == null: finish(); return
	network_cases()
	document_cases()
	backup_cases()
	planned_restore_cases()
	finish()

func observed(machine) -> Dictionary:
	var outputs := {}
	for probe in machine.probes():
		if str(probe.id) in ["dns-check", "admin-check"]: outputs[str(probe.id)] = machine.run(str(probe.command))
	outputs.request = machine.run("curl https://intranet.client.test/api/business/orders")
	var rows: Array = Evidence.rows(outputs)
	var record := {"context":"isolated-network:0","url":URL,"fingerprint":machine._fingerprint(),"outputs":outputs,"rows":rows,"passed":rows.all(func(row):return bool(row.passed))}
	return Evidence.project(record,"isolated-network:0",URL,machine._fingerprint())

func project(view: Dictionary) -> Dictionary:
	var before := JSON.stringify(view)
	var result: Dictionary = network.project(view,URL)
	check(JSON.stringify(view) == before, "network projection does not mutate evidence")
	return result

func set_rule(machine, id: String, action: String) -> void:
	var found := false
	for rule in machine.firewall_snapshot().rules:
		if str(rule.id) != id: continue
		var edit: Dictionary = rule.duplicate(true); edit.action = action
		check(bool(machine.firewall_action("save_rule",{"rule":edit}).get("ok",false)), "stage actual rule " + id)
		check(bool(machine.firewall_action("apply").get("ok",false)), "apply actual rule " + id)
		found = true; break
	check(found, "rule selected by actual ID " + id)

func network_cases() -> void:
	var vm = VM.new(); vm.setup(2,{},Catalog.by_id("service-2-case-0")); vm.run("ssh client")
	var empty: Dictionary = project(Evidence.project({},"isolated-network:0",URL,vm._fingerprint()))
	check(not bool(empty.complete), "unobserved cannot claim completion")
	for key in ["dns","business","admin"]: check(str(empty[key].state) == "unknown", "unobserved node " + key)
	var view := observed(vm)
	check(str(view.outputs.request).begins_with("curl:") and not str(view.outputs.request).contains("HTTP/"), "real initial DNS failure has no HTTP response")
	var visual := project(view)
	check(str(visual.dns.state) == "fail", "observed DNS fault located at name resolution")
	check(str(visual.business.state) in ["unknown","unreached"], "DNS stop does not claim measured application failure or success")
	check(str(visual.admin.state) in ["unknown","unreached"] and not visual.complete, "DNS stop cannot be counted as management protection")
	check(bool(vm.firewall_action("services",{"dns":"on","tls":"off"}).get("ok",false)) and bool(vm.firewall_action("apply").get("ok",false)), "apply real TLS-failure variant")
	view = observed(vm); visual = project(view)
	check(str(visual.dns.state) == "pass" and str(visual.business.state) == "fail", "actual TLS failure occurs after observed DNS success")
	check(str(visual.business.get("edge_state","")) != "pass", "TLS failure never paints an application-response edge")
	check(not visual.complete and str(view.outputs.request).begins_with("curl:"), "TLS failure is not HTTP or complete")
	check(bool(vm.firewall_action("services",{"dns":"on","tls":"on"}).get("ok",false)) and bool(vm.firewall_action("apply").get("ok",false)), "apply TLS recovery")
	set_rule(vm,"lan-business","block")
	view = observed(vm); visual = project(view)
	check(str(view.outputs.request).contains("FIREWALL_DENIED") and str(visual.business.state) in ["fail","blocked"], "actual business policy deny is visible without HTTP fabrication")
	check(not visual.complete, "business denial cannot complete customer request")
	set_rule(vm,"lan-business","pass")
	var normal: String = vm.read_file("/srv/data/orders.csv")
	check(vm.write_file("/srv/data/orders.csv","CORRUPTED DATA\n"), "create actual malformed application data variant")
	view = observed(vm); visual = project(view)
	check(str(view.outputs.request).begins_with("HTTP/1.1 422") and str(visual.business.state) == "fail", "HTTP 422 displayed as actual application data failure")
	check(str(visual.business.detail).contains("データ") and str(visual.business.detail).contains("422"), "application rejection has a short data-error caption linked to the measured status")
	check(str(visual.business.get("edge_state","")) == "pass", "HTTP 422 reached application while the content/result node failed")
	check(str(visual.dns.state) == "pass" and not visual.complete, "application error does not erase observed transport evidence or imply completion")
	check(vm.write_file("/srv/data/orders.csv",normal), "restore actual normal data")
	view = observed(vm); visual = project(view)
	check(str(visual.dns.state) == "pass" and str(visual.business.state) == "pass", "actual DNS and HTTP 200 observations project success")
	check(str(visual.admin.state) == "blocked" and visual.complete, "intended measured management denial is protection success")
	var not_accepted: Dictionary = view.duplicate(true); not_accepted.passed = false
	check(not bool(project(not_accepted).complete), "visible successes cannot override the authoritative overall diagnostic acceptance")
	var before: Dictionary = vm.export_state()
	for _i in 5: project(view)
	check(vm.export_state() == before, "repeated visual projection does not measure, append traffic or mutate VM")
	var stale: Dictionary = Evidence.project(view,"isolated-network:0",URL,"different-fingerprint")
	check(bool(stale.rows[0].passed), "stale fixture retains historical successful row")
	visual = project(stale)
	check(not visual.complete, "historical success cannot complete current request")
	for key in ["dns","business","admin"]:
		check(str(visual[key].state) == "stale", "stale node suppresses current success: " + key)
		check(str(visual[key].get("edge_state","")) == "stale", "stale route cannot retain current success: " + key)
	for other in [["other-case:0",URL],["isolated-network:1",URL],["isolated-network:0","https://intranet.client.test/accounting"]]:
		visual = project(Evidence.project(view,str(other[0]),str(other[1]),vm._fingerprint()))
		check(not visual.complete and str(visual.business.state) == "unknown", "different context/target/URL cannot borrow success")
	set_rule(vm,"wan-admin","pass")
	view = observed(vm); visual = project(view)
	check(str(view.outputs["admin-check"]).begins_with("HTTP/") and str(visual.admin.state) != "blocked" and not visual.complete, "actual reachable management route is not a successful restriction")
	check(str(visual.admin.get("edge_state","")) == "pass", "reachable management response remains a reached edge despite failed restriction")
	# A parsed application's response body is not a transport-layer observation.
	for body in ["FIREWALL_DENIED", "Could not resolve host: admin.client.test"]:
		var application_denial: Dictionary = view.duplicate(true)
		application_denial.outputs["admin-check"] = "HTTP/1.1 403 Forbidden\n\n" + body
		visual = project(application_denial)
		check(str(visual.admin.state) == "fail" and str(visual.admin.get("edge_state","")) == "pass" and not visual.complete, "application body text cannot be promoted into a transport deny: " + body)
	var unknown := {"status":"current","passed":false,"outputs":{},"rows":[]}
	visual = project(unknown)
	for key in ["dns","business","admin"]: check(str(visual[key].state) == "unknown", "missing response remains unknown: " + key)
	unknown.outputs = {"dns-check":"unsupported response", "request":"unrecognized output", "admin-check":""}
	visual = project(unknown)
	check(not visual.complete and str(visual.business.state) == "unknown" and str(visual.admin.state) == "unknown", "unknown output never invents a measured outcome")
	unknown.outputs["admin-check"] = "HTTP/garbage"
	visual = project(unknown)
	check(str(visual.admin.state) == "unknown", "malformed HTTP-looking text is not a parsed management response")
	unknown.passed = true
	visual = project(unknown)
	check(not visual.complete, "a lone old/corrupt passed flag without recognizable observations cannot paint completion")
	var body_text := {"status":"current","passed":false,"outputs":{"request":"HTTP/1.1 422 Unprocessable Entity\n\nCould not resolve FIREWALL_DENIED"}}
	visual = project(body_text)
	check(str(visual.dns.state) == "unknown", "application response text cannot invent an unmeasured DNS fault")
	check(str(visual.business.state) == "fail" and str(visual.business.get("edge_state","")) == "pass", "application body text cannot erase the parsed reached response")
	var dns_denied := {"status":"current","passed":false,"outputs":{"dns-check":"SERVFAIL FIREWALL_DENIED","request":"curl: (6) Could not resolve host: intranet.client.test (FIREWALL_DENIED)","admin-check":"curl: (6) Could not resolve host: admin.client.test (FIREWALL_DENIED)"}}
	visual = project(dns_denied)
	check(str(visual.admin.state) != "blocked", "DNS-policy refusal is not proof of destination management block")

func document_cases() -> void:
	var healthy := "2026-09-18 opening=50000 closing=62800\n"
	var other := "2026-09-18 opening=50000 closing=61800\n"
	var doc: Dictionary = backup.document(healthy)
	check(str(doc.kind) == "ledger" and doc.fields.size() >= 3, "actual readable ledger becomes inspected data fields")
	var values := {}
	for field in doc.fields: values[str(field.key)] = str(field.value)
	check(str(values.get("opening","")) == "50000" and str(values.get("closing","")) == "62800", "document values come from exact source amounts")
	check(not bool(doc.get("accepted",false)) and not bool(doc.get("healthy",false)), "parseable document carries no customer-success assertion")
	check(str(backup.document(other).kind) == "ledger", "a different amount is also parseable, without correctness inference")
	var compared: Dictionary = backup.comparison(healthy,other,true)
	check(not bool(compared.equal) and "closing" in compared.changed_keys, "actual differing ledger field is highlighted")
	compared = backup.comparison("CORRUPTED DATA\n","CORRUPTED DATA\n",true)
	check(bool(compared.equal) and str(compared.saved.kind) == "damaged" and not bool(compared.get("accepted",false)), "corrupt-to-corrupt equality stays equality, not customer acceptance")
	check(str(backup.document("",false).kind) == "missing" and str(backup.document("",true).kind) != "missing", "missing and existing empty files remain distinct")
	var empty_document: Dictionary = backup.document("",true)
	check(int(empty_document.bytes) == 0 and empty_document.lines.is_empty(), "empty existing file reaches the explicit empty-document label instead of a blank line")
	check(not bool(backup.comparison(healthy,"",false).equal), "missing destination is not an equal restored copy")
	check(str(backup.document("unrecognized text\n").kind) == "text", "unknown content retains neutral inspectable text")

func acceptance(view: Dictionary) -> Dictionary:
	var before := JSON.stringify(view)
	var result: Dictionary = backup.acceptance(view)
	check(JSON.stringify(view) == before, "backup acceptance projection does not mutate trusted evidence")
	return result

func backup_cases() -> void:
	var vm = VM.new(); vm.setup(1,{},Catalog.by_id("service-1-case-3")); vm.run("ssh client")
	var visual: Dictionary = acceptance(vm.backup_acceptance_view())
	check(str(visual.restored) == "missing" and not visual.accepted, "actual missing recovery artifact remains incomplete")
	check(str(visual.original) == "preserved" and str(visual.unrelated) == "preserved", "damaged but unchanged intake original is preserved, not called repaired")
	var original: String = vm.read_file(LEDGER)
	var good := ""
	for line in str(vm.run("restic -r offsite snapshots")).split("\n"):
		var columns := line.strip_edges().split(" ",false)
		if columns.size() < 2 or str(columns[1]) != "offsite": continue
		var id := str(columns[0])
		var bytes: String = vm.run("restic -r offsite dump %s %s" % [id,LEDGER])
		if bytes != original and not bytes.begins_with("restic:"): good = id; break
	check(not good.is_empty(), "select actual readable older bytes from inventory")
	check(str(vm.run("restic -r offsite restore latest --target /restore --include " + LEDGER)).begins_with("restored"), "wrong latest restore command really succeeds")
	visual = acceptance(vm.backup_acceptance_view())
	check(str(visual.restored) == "mismatch" and not visual.accepted, "command success is not customer acceptance")
	check(str(vm.run("restic -r offsite restore %s --target /restore-other --include %s" % [good,LEDGER])).begins_with("restored"), "correct bytes restored outside approved region")
	visual = acceptance(vm.backup_acceptance_view())
	check(str(visual.restored) == "mismatch" and not visual.accepted, "correct content at unauthorized path stays unaccepted")
	check(str(vm.run("restic -r offsite restore %s --target /restore --include %s" % [good,LEDGER])).begins_with("restored"), "real approved recovery succeeds")
	visual = acceptance(vm.backup_acceptance_view())
	check(str(visual.restored) == "matched" and str(visual.original) == "preserved" and str(visual.unrelated) == "preserved" and visual.accepted, "existing trusted checks alone create recovery/preservation success")
	var accepted_state: Dictionary = vm.export_state()
	check(vm.write_file(LEDGER,"replaced original\n"), "real original modification")
	visual = acceptance(vm.backup_acceptance_view())
	check(str(visual.original) == "changed" and str(visual.restored) == "matched" and not visual.accepted, "good artifact cannot hide changed original")
	check(vm.write_file("/srv/data/customers.csv","modified unrelated\n"), "real unrelated modification")
	visual = acceptance(vm.backup_acceptance_view())
	check(str(visual.unrelated) == "changed" and not visual.accepted, "unrelated modification is separately visible")
	var old: Dictionary = accepted_state.duplicate(true)
	old.erase("backup_authorization_version"); old.erase("backup_authorization"); old.erase("backup_restore_origins"); old.scenario.erase("backup_preservation_required")
	var legacy = VM.new(); legacy.setup(1,old,Catalog.by_id("service-1-case-3"))
	visual = acceptance(legacy.backup_acceptance_view())
	for key in ["restored","original","unrelated"]: check(str(visual[key]) == "unknown", "legacy absent baseline stays unknown: " + key)
	check(not visual.accepted, "legacy cannot draw newly proven preservation")
	var invalid: Dictionary = accepted_state.duplicate(true); invalid.erase("backup_authorization")
	var broken = VM.new(); broken.setup(1,invalid,Catalog.by_id("service-1-case-3"))
	visual = acceptance(broken.backup_acceptance_view())
	for key in ["restored","original","unrelated"]: check(str(visual[key]) == "unknown", "invalid known record does not fabricate changed/preserved state: " + key)
	check(not visual.accepted, "invalid baseline cannot draw acceptance")

func planned_changes(vm, plan: Dictionary) -> Dictionary:
	check(bool(plan.get("ok",false)), "change projection receives actual successful VM restore plan")
	var view: Dictionary = vm.backup_acceptance_view()
	var inputs := JSON.stringify({"view":view,"entries":plan.get("entries",[])})
	var before: Dictionary = vm.export_state()
	var changes: Dictionary = backup_console._planned_live_changes(view,plan.get("entries",[]))
	check(JSON.stringify({"view":view,"entries":plan.get("entries",[])}) == inputs and vm.export_state() == before, "planned-change projection does not write files or alter current protection")
	return changes

func planned_restore_cases() -> void:
	var vm = VM.new(); vm.setup(1,{},Catalog.by_id("service-1-case-3")); vm.run("ssh client")
	var original: String = vm.read_file(LEDGER)
	var good := ""
	for line in str(vm.run("restic -r offsite snapshots")).split("\n"):
		var columns := line.strip_edges().split(" ",false)
		if columns.size() < 2 or str(columns[1]) != "offsite": continue
		var id := str(columns[0])
		var bytes: String = vm.run("restic -r offsite dump %s %s" % [id,LEDGER])
		if bytes != original and not bytes.begins_with("restic:"): good = id; break
	check(not good.is_empty(), "planned-change scenario selects actual stored version")
	if good.is_empty(): return
	var plan: Dictionary = vm.restic_restore_plan("offsite",good,"/",[LEDGER],"always")
	check(plan.entries.size() == 1 and str(plan.entries[0].status) == "overwrite" and str(plan.entries[0].path) == LEDGER, "actual plan would overwrite live original")
	var changes := planned_changes(vm,plan)
	check(int(changes.original) == 1 and int(changes.unrelated) == 0, "planned original overwrite is distinct from current preserved state")
	check(bool(vm.backup_acceptance_view().original_preserved) and vm.read_file(LEDGER) == original, "preview leaves original currently preserved despite planned write")
	plan = vm.restic_restore_plan("offsite","latest","/",[LEDGER],"always")
	check(str(plan.entries[0].status) == "unchanged", "latest damaged original is an actual no-content-change plan")
	changes = planned_changes(vm,plan)
	check(int(changes.original) == 0 and int(changes.unrelated) == 0, "unchanged write plan has no planned content-change warning")
	plan = vm.restic_restore_plan("offsite",good,"/",[LEDGER],"never")
	check(str(plan.entries[0].status) == "skipped", "skip-existing actually avoids overwriting original")
	changes = planned_changes(vm,plan)
	check(int(changes.original) == 0 and int(changes.unrelated) == 0, "skipped write does not claim planned original damage")
	plan = vm.restic_restore_plan("offsite",good,"/restore",[LEDGER],"always")
	changes = planned_changes(vm,plan)
	check(int(changes.original) == 0 and int(changes.unrelated) == 0, "new artifact in isolated restore area leaves live-data plan unaffected")
	# Create and then remove an extra file through VM APIs. Its real snapshot
	# proves a future addition can affect the protected live directory too.
	var extra := "/srv/data/archive-note.txt"
	check(vm.write_file(extra,"archived note\n"), "create actual extra file for stored-version fixture")
	check(str(vm.run("restic -r offsite backup /srv/data")).begins_with("snapshot saved:"), "capture actual extra file in repository")
	vm.run("rm " + extra)
	check(not vm.state.fs.has(extra) and bool(vm.backup_acceptance_view().unrelated_preserved), "remove fixture addition through API to recover current original file set")
	plan = vm.restic_restore_plan("offsite","latest","/",[extra],"always")
	check(plan.entries.size() == 1 and str(plan.entries[0].status) == "new", "actual future plan would add unrelated live file")
	changes = planned_changes(vm,plan)
	check(int(changes.original) == 0 and int(changes.unrelated) == 1, "new live-directory file is an unrelated planned change")
	plan = vm.restic_restore_plan("offsite","latest:/srv/data","/srv/data-copy",["archive-note.txt"],"always")
	changes = planned_changes(vm,plan)
	check(int(changes.original) == 0 and int(changes.unrelated) == 0, "prefix-lookalike directory is not the protected live directory")
	# Explicitly reconstruct the existing composite's authorized replacement
	# scope. Its actual overwrite plan must not acquire standalone warnings.
	var scope: Dictionary = Catalog.by_id("service-1-case-3").duplicate(true)
	scope.erase("backup_preservation_required")
	scope.backup_acceptance_mode = "production_replacement"
	scope.checks = scope.checks.slice(0,3)
	var composite = VM.new(); composite.setup(1,{},scope); composite.run("ssh client")
	plan = composite.restic_restore_plan("offsite",good,"/",[LEDGER],"always")
	check(str(plan.entries[0].status) == "overwrite" and not bool(composite.backup_acceptance_view().available), "production-replacement scope still has real overwrite plan without standalone approval")
	changes = planned_changes(composite,plan)
	check(int(changes.original) == 0 and int(changes.unrelated) == 0, "explicit production-replacement scope receives no invented standalone warning")

func finish() -> void:
	print("VISUAL_CASE_STATE ",JSON.stringify({"assertions":assertions,"failures":failures.size(),"details":failures}))
	quit(0 if failures.is_empty() else 1)
