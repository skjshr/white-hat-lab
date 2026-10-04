extends SceneTree
const Evidence = preload("res://scripts/network_request_evidence.gd")
const VM = preload("res://scripts/virtual_machine.gd")
const Catalog = preload("res://scripts/case_catalog.gd")
var game
var assertions := 0
var failures: Array[String] = []
const URL := "https://intranet.client.test/sales"

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ",label)

func scenario() -> Dictionary:
	for item in Catalog.all():
		if str(item.id)=="service-2-case-0": return item.duplicate(true)
	return {}

func fixtures() -> void:
	# Explicit isolated model variants, separate from the normal-funded journey.
	var machine = VM.new(); machine.setup(2,{},scenario()); machine.run("ssh client")
	var read: Dictionary = machine.business_read("orders",URL)
	check(not read.ok and read.transport_error and read.code==0 and read.transport_kind=="dns", "DNS is transport failure without HTTP code")
	var before: Dictionary = machine.export_state()
	for _i in 5: machine.business_read("orders",URL)
	check(machine.export_state()==before,"reading transport failure records no traffic or measurement")
	machine.firewall_action("services",{"dns":"on","tls":"off"}); machine.firewall_action("apply")
	read = machine.business_read("orders",URL)
	check(read.transport_error and read.transport_kind=="tls" and read.code==0,"TLS is transport failure without HTTP code")
	check(machine.business_read("orders","http://intranet.client.test/sales").ok,"HTTP route is actual unencrypted request, not HTTPS evidence")
	machine.firewall_action("services",{"dns":"on","tls":"on"}); machine.firewall_action("apply")
	var rule: Dictionary = machine.firewall_snapshot().rules[0].duplicate(true)
	rule.action="block"
	machine.firewall_action("save_rule",{"rule":rule}); machine.firewall_action("apply")
	read=machine.business_read("orders",URL)
	check(read.transport_error and read.transport_kind=="dns" and read.raw.contains("FIREWALL_DENIED"),"DNS policy denial remains transport failure")
	var denied: String = machine.run("curl https://admin.client.test:8443")
	var rows: Array = Evidence.rows({"admin-check":denied})
	check(not rows[2].passed and str(rows[2].detail).contains("遮断は未確認"),"DNS denial is never proof of admin destination block")
	rule.action="pass"; machine.firewall_action("save_rule",{"rule":rule}); machine.firewall_action("apply")
	rule=machine.firewall_snapshot().rules[1].duplicate(true); rule.action="block"
	machine.firewall_action("save_rule",{"rule":rule}); machine.firewall_action("apply")
	read=machine.business_read("orders",URL)
	check(read.transport_error and read.transport_kind=="denied" and read.code==0,"TCP policy block receives no application HTTP status")
	rule.action="pass"; machine.firewall_action("save_rule",{"rule":rule}); machine.firewall_action("apply")
	read=machine.business_read("orders",URL)
	check(read.ok and read.code==200 and read.data.orders[0].order=="501", "real successful business data remains HTTP 200")
	machine.state.fs["/srv/data/orders.csv"]="CORRUPTED DATA\n"
	read=machine.business_read("orders",URL)
	check(not read.ok and read.code==422 and not read.get("transport_error",false),"real application data error retains HTTP 422")
	check(Evidence.request("https://intranet.client.test/accounting").resource=="ledger","accounting URL derives matching real resource")
	check(Evidence.request("https://intranet.client.test/unknown").is_empty() and Evidence.request("https://external.example/sales").is_empty(),"unsupported exact requests rejected")
	var record := {"context":"case-a:0","url":URL,"fingerprint":"same","passed":true,"rows":[]}
	check(Evidence.project(record,"case-b:0",URL,"same").status=="unobserved","other contract evidence not reused")
	check(Evidence.project(record,"case-a:1",URL,"same").status=="unobserved","other target evidence not reused")
	check(Evidence.project(record,"case-a:0","https://intranet.client.test/accounting","same").status=="unobserved","other business endpoint evidence not reused")
	check(Evidence.project(record,"case-a:0",URL,"changed").status=="stale","changed state invalidates saved request")

func run() -> void:
	game=root.get_node("Game"); game.set_process(false)
	if not str(game.save_path).begins_with("user://qa-network-request-"): quit(2); return
	fixtures()
	check(game.new_game() and game.choose_strategy("advisory") and game.start_free_career(),"normal funded career")
	var offers: Array=game.state.offers.filter(func(item):return str(item.get("case_id",""))=="service-2-case-0" and bool(item.get("unlocked",false)) and bool(item.get("market_available",true)))
	check(not offers.is_empty() and game.choose_contract(str(offers[0].id)),"actual day-one case accepted")
	if offers.is_empty(): quit(1); return
	check(not str(game.mission().title).contains("名前解決") and str(game.mission().brief).contains("事務担当"),"runtime case title does not disclose solution and matches clinic task")
	check(game.vm_run("ssh client").contains("Authenticated"),"public customer connect")
	var machine=game._vm()
	var rules: Array=machine.firewall_snapshot().applied_rules.duplicate(true)
	var data_files := {}
	for path in ["/srv/data/customers.csv","/srv/data/orders.csv","/srv/data/ledger.txt"]: data_files[path]=game.vm_read(path)
	var view: Dictionary=game.network_request_view(URL)
	check(view.available and view.status=="unobserved","legacy/no saved measurements remains unobserved")
	var previous: Dictionary=game.state.duplicate(true); var vm_before: Dictionary=machine.export_state()
	for _i in 8: game.network_request_view(URL); game.business_read("orders",URL)
	check(game.state==previous and machine.export_state()==vm_before,"repeated rendering projection cannot mutate state or VM")
	var read: Dictionary=game.business_read("orders",URL)
	check(read.transport_error and not str(read.response).begins_with("HTTP/") and read.revision.length()>0 and read.has("capabilities"),"Game keeps transport type and revision without fabricated HTTP response")
	var clock_before: int=game.state.clock_minutes
	var observed: Dictionary=game.network_request_test(URL)
	check(observed.ok and not observed.measurement.passed,"actual initial reproduction fails")
	check(game.state.clock_minutes-clock_before==9,"explicit measurement reuses matching acceptance request and charges nine real minutes")
	check(game.network_request_view(URL).status=="current" and not game.network_request_view(URL).passed,"fresh failure shown as failure")
	check(not observed.measurement.rows[2].passed,"initial DNS failure does not claim admin protection")
	check(observed.measurement.commands.request=='curl "https://intranet.client.test/api/business/orders"',"same sales request mapped to real orders endpoint")
	previous=game.state.duplicate(true); vm_before=machine.export_state()
	check(not game.network_request_test("https://intranet.client.test/unknown").ok,"unknown request refused")
	check(game.state==previous and machine.export_state()==vm_before,"refused request consumes no time and preserves evidence")
	check(game.firewall_action("services",{"dns":"on","tls":"on"}).ok,"save actual service change")
	check(game.network_request_view(URL).status=="stale","pending configuration invalidates earlier observation")
	check(game.business_read("orders",URL).transport_error,"pending save still leaves actual DNS failure")
	check(game.network_request_test(URL).ok and not game.network_request_view(URL).passed,"pending-state retest cannot invent restoration")
	check(game.firewall_action("apply").ok,"apply actual service change")
	check(game.network_request_view(URL).status=="stale","apply requires explicit new observation")
	observed=game.network_request_test(URL)
	check(observed.ok and observed.measurement.passed and game.network_request_view(URL).passed,"fresh actual business plus protection accepted")
	check(str(observed.measurement.outputs.request).contains('"order":"501"') and str(observed.measurement.outputs.request).contains('"total":12800'),"captured exact real record bytes, not generic app readiness")
	check(observed.measurement.outputs["admin-check"].contains("FIREWALL_DENIED") and not observed.measurement.outputs["admin-check"].contains("Could not resolve"),"admin request really reaches denied route")
	check(machine.firewall_snapshot().applied_rules==rules and machine.state.applied.tls=="on","ordered policy and TLS preserved")
	for path in data_files: check(game.vm_read(path)==data_files[path],"customer bytes preserved "+path)
	var checks: Array=game.verify()
	check(not checks.is_empty() and game.can_deliver(),"existing verification and delivery acceptance use real fresh probes")
	check(game.save_game() and game.load_game(),"request measurements persist through real save/load")
	game.set_process(false); machine=game._vm()
	check(game.network_request_view(URL).passed and game.can_deliver(),"restored observation stays accurate after normalization")
	check(game.network_request_view("https://intranet.client.test/accounting").status=="unobserved","changing view does not transfer sales evidence to ledger")
	previous=game.state.duplicate(true); vm_before=machine.export_state()
	var save_path: String=game.save_path
	game.save_path="user://missing-network-request-"+str(OS.get_process_id())+"/save.json"
	var failed: Dictionary=game.network_request_test(URL)
	game.save_path=save_path
	check(not failed.ok and failed.error=="save_failed","save failure is reported")
	check(game.state==previous and machine.export_state()==vm_before,"save failure rolls back exact state clock probes and measurement")
	check(game.network_request_view(URL).passed,"failed retest retains previously saved actual evidence")
	# A generic ready banner must not satisfy the new actual-list acceptance.
	var healthy_orders: String=game.vm_read("/srv/data/orders.csv")
	check(game.vm_write("/srv/data/orders.csv","CORRUPTED DATA\n"),"explicit malformed data regression fixture")
	observed=game.network_request_test(URL)
	check(observed.ok and not observed.measurement.passed and str(observed.measurement.outputs["business-check"]).begins_with("HTTP/1.1 422"),"real malformed list fails the existing business acceptance probe")
	game.verify()
	check(not game.can_deliver(),"malformed business records cannot be delivered behind a generic HTTP 200 banner")
	check(game.vm_write("/srv/data/orders.csv",healthy_orders),"restore exact regression fixture bytes")
	game.network_request_test(URL); game.verify()
	check(game.can_deliver(),"healthy actual list restores existing acceptance")
	# Existing diagnostics remain sufficient: absence of this optional UI evidence is no gate.
	machine.state.erase("network_request_evidence")
	game.state.vm_states[game._vm_key()]=machine.export_state()
	check(game.network_request_view(URL).status=="unobserved" and game.can_deliver(),"old saves and existing diagnostic workflow need no additional mandatory click")
	var old_scenario := scenario()
	for probe in old_scenario.probes:
		if str(probe.id)=="business-check": probe.command="curl https://intranet.client.test"; probe.expectation="status:200|Sales workspace"
	var old_machine=VM.new(); old_machine.setup(2,{},old_scenario)
	var old_saved: Dictionary=old_machine.export_state()
	var restored=VM.new(); restored.setup(2,old_saved,scenario())
	check(restored.probes().any(func(probe):return str(probe.id)=="business-check" and str(probe.command)=="curl https://intranet.client.test"),"accepted legacy probe command remains unchanged on load")
	print("NETWORK_REQUEST_EVIDENCE_PASS assertions=",assertions," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
