extends SceneTree

var game
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ",label)

func canonical(value: Variant) -> String:
	return JSON.stringify(value,"",true)

func accept(case_id: String) -> bool:
	game._reset_state(); game.choose_strategy("advisory"); game.start_free_career()
	game.state.skills = {"advisory":20,"operations":20,"response":20}
	game.state.profit = 1000000; game.state.peak_profit = 1000000; game._update_growth()
	game.state.market_leads = [case_id]; game.state.market_day = int(game.state.day)
	for day in 120:
		game.state.day = day+1; game._make_offers()
		for offer in game.state.offers:
			if str(offer.get("case_id","")) == case_id and bool(offer.get("market_available",false)):
				game.set_offer_quote(str(offer.id),int(offer.get("reward",offer.get("base_reward",0))))
				return game.choose_contract(str(offer.id))
	return false

func target(chapter: int) -> int:
	for i in game.state.targets.size():
		if int(game.state.targets[i].chapter)==chapter: return i
	return -1

func configure(chapter: int, values: Dictionary) -> void:
	check(game.select_target(target(chapter)),"target "+str(chapter)); game.vm_run("ssh client")
	var vm = game._vm()
	check(game.vm_write(str(vm.state.config_path),str(vm.configuration_text(values))),"configuration "+str(chapter))
	check(str(game.vm_run("systemctl restart "+str(vm.state.service))).contains("active"),"service "+str(chapter))

func action(name: String, args: Dictionary = {}) -> Dictionary:
	var payload := args.duplicate(true)
	payload.expected_revision = str(game.business_read().get("revision",""))
	return game.business_action(name,payload)

func rejected_unchanged(name: String, args: Dictionary, code: int, label: String) -> void:
	var before := canonical(game.state); var vm := canonical(game._vm().export_state())
	var result := action(name,args)
	check(int(result.get("code",0))==code,label+" status")
	check(before==canonical(game.state) and vm==canonical(game._vm().export_state()),label+" no mutation")

func run() -> void:
	game = load("res://scripts/game.gd").new(); root.add_child(game); await process_frame; game.set_process(false)
	game.save_path = "user://qa-business-transactions-%s.json" % OS.get_process_id()
	game.backup_path = game.save_path+".bak"; game.previous_path = game.save_path+".previous"
	if not accept("firm-remote-hardening"): check(false,"accept ordinary gateway"); quit(1); return
	check(true,"accept ordinary gateway")
	configure(2,{"dns":"on","business":"allow","admin_public":"deny","tls":"on"})
	var read: Dictionary = game.business_read()
	check(bool(read.get("ok",false)) and bool(read.get("capabilities",{}).get("write",false)),"normal service available")
	var before := canonical(game.state); var original_vm := canonical(game._vm().export_state())
	for _i in 10: game.business_read("orders","https://intranet.client.test/sales")
	check(before==canonical(game.state) and original_vm==canonical(game._vm().export_state()),"refresh has no time, save, traffic, or probe side effects")
	check(int(game.business_read("orders","https://elsewhere.test/sales").code)==404,"host boundary")
	var customer := action("create_customer",{"name":"海辺商店"})
	check(bool(customer.get("ok",false)),"create customer")
	var cid := str(customer.get("item",{}).get("id",""))
	check(game.vm_read("/srv/data/customers.csv").contains(cid+",海辺商店"),"customer stored in canonical CSV")
	check(str(game.vm_run("curl https://intranet.client.test/api/business/customers")).contains("海辺商店"),"customer HTTP and workspace use same data")
	var order := action("create_order",{"customer":cid,"total":4500})
	check(bool(order.get("ok",false)),"create order")
	var oid := str(order.get("item",{}).get("order",""))
	check(str(game.vm_run("curl https://intranet.client.test/api/business/orders")).contains(oid),"ordinary HTTP reads same order")
	rejected_unchanged("delete_customer",{"id":cid},409,"customer reference restriction")
	rejected_unchanged("create_order",{"customer":"missing","total":1},422,"unknown customer")
	rejected_unchanged("create_order",{"customer":cid,"total":-5},422,"negative amount")
	rejected_unchanged("create_order",{"customer":cid,"total":1.5},422,"fractional amount")
	rejected_unchanged("create_customer",{"name":"bad,name"},422,"unsupported CSV delimiter")
	var stale := str(game.business_read().revision)
	check(bool(action("update_order",{"id":oid,"customer":cid,"total":6500}).ok),"update order")
	before=canonical(game.state)
	var conflict: Dictionary = game.business_action("update_order",{"id":oid,"customer":cid,"total":999,"expected_revision":stale})
	check(int(conflict.code)==409 and before==canonical(game.state),"stale edit cannot overwrite current order")
	check(bool(action("append_ledger",{"date":"2026-09-19","amount":6500}).ok),"append accounting entry")
	var ledger: Dictionary = game.business_read("ledger")
	check(int(ledger.data.ledger.back().closing)==69300,"balance calculated from previous closing")
	rejected_unchanged("append_ledger",{"date":"2026-09-20","amount":-1000000},422,"insufficient balance")
	rejected_unchanged("append_ledger",{"date":"2026-09-19","amount":1},409,"duplicate ledger date")
	var saved_path: String = game.save_path
	before=canonical(game.state); original_vm=canonical(game._vm().export_state())
	game.save_path="user://missing-business-directory/save.json"
	var failed := action("create_order",{"customer":cid,"total":777})
	game.save_path=saved_path
	check(int(failed.code)==507 and before==canonical(game.state) and original_vm==canonical(game._vm().export_state()),"save failure rolls back data, history, clock, and VM")
	check(game.save_game(),"save CRUD state")
	var csv: String = game.vm_read("/srv/data/orders.csv")
	game._machine=null; game._machine_key=""; check(game.load_game(),"load CRUD state")
	check(game.vm_read("/srv/data/orders.csv")==csv and int(game.business_read("ledger").data.ledger.back().closing)==69300,"saved customer data reopens")
	check(bool(action("delete_order",{"id":oid}).ok) and bool(action("delete_customer",{"id":cid}).ok),"delete order then unreferenced customer")
	var another := action("create_customer",{"name":"別の顧客"})
	check(str(another.get("item",{}).get("id","")) != cid,"deleted IDs are not reused")
	var last_sequence: int=int(game._vm().state.business_journal.back().sequence)
	var increasing := true
	for i in 300:
		var changed := action("update_customer",{"id":"101","name":"通常顧客 %03d" % i})
		var actual: int=int(game._vm().state.business_journal.back().sequence)
		increasing = increasing and bool(changed.get("ok",false)) and actual == last_sequence+1
		last_sequence=actual
	check(increasing,"300 normal transactions keep strictly increasing journal sequence")
	var retained: Array=game._vm().state.business_journal
	check(retained.size()==256 and int(retained.front().sequence)==last_sequence-255,"history cap retains last 256 distinct consecutive entries")
	check(game.save_game(),"save capped history")
	game._machine=null; game._machine_key=""; check(game.load_game(),"reopen capped history")
	check(bool(action("update_customer",{"id":"101","name":"再開後の顧客"}).ok) and int(game._vm().state.business_journal.back().sequence)==last_sequence+1,"journal sequence continues after JSON reopen")

	check(accept("composite-branch-reopen"),"accept linked branch")
	configure(0,{"staff":"write","guest":"none"})
	configure(2,{"dns":"on","business":"allow","admin_public":"deny","tls":"on"})
	var source_key: String=game._vm_key(target(0))
	var original_orders := str(game.state.vm_states[source_key].fs["/srv/share/partner-order.csv"])
	var linked := action("create_order",{"customer":"101","total":7500})
	check(bool(linked.get("ok",false)),"linked order committed")
	check(str(game.state.vm_states[source_key].fs["/srv/share/partner-order.csv"]).contains(str(linked.get("item",{}).get("order","NOT_CREATED"))),"linked provider receives real bytes")
	check(not original_orders.is_empty() and str(game.state.targets[target(0)].scenario.probes.back().expectation) != original_orders.sha256_text(),"current source hash follows authorized write")
	var linked_before := canonical(game.state)
	game.save_path="user://missing-business-directory/save.json"
	failed=action("create_customer",{"name":"保存失敗顧客"}); game.save_path=saved_path
	check(int(failed.code)==507 and linked_before==canonical(game.state),"linked owner and all target projections rollback")
	configure(5,{"staff":"write","partner":"read","public":"none","expires":"7d","mfa":"on","tls":"on","audit":"on"})
	for chapter in [0,2,5]:
		game.select_target(target(chapter)); game.vm_run("ssh client")
		var passed := false
		for _round in 3:
			for probe in game.diagnostic_probes():
				if not bool(probe.get("fresh",false)) or not bool(probe.get("passed",false)): game.run_diagnostic(str(probe.id))
			var checks: Array = game.verify()
			passed = not checks.is_empty() and checks.all(func(item): return bool(item.get("passed",false)))
			if passed: break
		check(passed,"authorized business changes preserve case checks "+str(chapter))
	var gateway := target(2)
	configure(0,{"staff":"read","guest":"none"}); game.select_target(gateway); game.vm_run("ssh client")
	rejected_unchanged("create_order",{"customer":"101","total":1},403,"provider write permission")
	configure(0,{"staff":"write","guest":"none"})
	check(game.vm_write("/srv/share/partner-order.csv","CORRUPTED\n"),"corrupt canonical source")
	game.select_target(gateway); game.vm_run("ssh client")
	var blocked := action("create_customer",{"name":"cannot repair by registration"})
	check(not bool(blocked.get("ok",false)),"normal registration cannot bypass source recovery")
	check(game.vm_read("/srv/data/orders.csv") != "CORRUPTED\n","gateway is not canonical provider")
	game.select_target(target(0)); game.vm_run("ssh client")
	check(game.vm_write("/srv/share/partner-order.csv","order,customer,total\n501,101,999\n"),"valid but incorrect source data")
	game.select_target(gateway); game.vm_run("ssh client")
	rejected_unchanged("create_customer",{"name":"cannot legitimize valid corruption"},409,"fixed recovery baseline rejects syntactically valid corruption")
	check(accept("advanced-portal"),"accept independent invoice service")
	before=canonical(game.state)
	check(int(game.business_read().get("code",0))==400 and before==canonical(game.state),"legacy workspace cannot create a second data source inside an advanced engine")
	if failures.is_empty(): print("BUSINESS_TRANSACTIONS_PASS assertions=",assertions)
	else: print("BUSINESS_TRANSACTIONS_FAIL ",failures)
	quit(0 if failures.is_empty() else 1)
