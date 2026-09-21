extends SceneTree
var failures: Array[String] = []
var game
func _init() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("procurement timeout"); quit(2))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ",label)
func run() -> void:
	game = load("res://scripts/game.gd").new(); root.add_child(game); await process_frame; game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"isolated QA path")
	game._reset_state(); game.choose_strategy("advisory"); game.state.peak_profit=20000; game.state.cash=30000; game.start_free_career()
	var offer: Dictionary = {}
	for day in 60:
		game.state.day=day+1; game._make_offers()
		for candidate in game.state.offers:
			if str(candidate.case_id)=="hardware-gateway-install" and bool(candidate.market_available): offer=candidate; break
		if not offer.is_empty(): break
	check(not offer.is_empty(),"hardware daily lead exists")
	if offer.is_empty(): finish(); return
	check(int(offer.estimated_cost)==3900 and game.choose_contract(str(offer.id)),"hardware contract accepted with estimated COGS")
	check(game._customer_hardware().is_empty() and not game.vm_info().connected,"unreceived device offline")
	check(game.vm_run("ssh client").contains("hardware_unavailable"),"SSH blocked before receiving hardware")
	check(not game.vm_write(str(game.vm_info().config_path),"dns=on"),"editor cannot configure nonexistent device")
	check(not bool(game.firewall_action("services",{"dns":"on"}).ok),"console cannot configure nonexistent device")
	check(not game.staff_availability("aya").is_empty(),"staff cannot inspect absent hardware")
	var cash: int=game.state.cash; var profit: int=game.state.profit
	var path: String=game.save_path; var bad_path: String="user://missing-stock-"+str(OS.get_process_id())+"/save.json"
	game.save_path=bad_path; var failed: Dictionary=game.buy_customer_stock(2); game.save_path=path
	check(str(failed.error)=="save" and int(game.state.cash)==cash and game.customer_stock_units().is_empty(),"purchase failure rolls back cash and units")
	var purchase: Dictionary=game.buy_customer_stock(2)
	check(bool(purchase.ok) and int(game.state.cash)==cash-6400 and int(game.state.profit)==profit,"stock payment is inventory asset")
	if not bool(purchase.ok): finish(); return
	var id: String=purchase.ids[0]; var spare: String=purchase.ids[1]
	check(str(game.buy_customer_stock(4).error)=="quantity","bounded quantity")
	check(game.delivery_orders().is_empty(),"queued units not visible in office")
	game.advance_delivery(29.0); check(str(game.customer_stock_for(id).status)=="queued","lead time incomplete")
	game.save_path=bad_path; game.advance_delivery(1.0); game.save_path=path
	check(str(game.customer_stock_for(id).status)=="queued" and float(game.customer_stock_for(id).elapsed_seconds)==29.0,"arrival failure rolls back state")
	game.advance_delivery(1.0); check(game.customer_stock_boxes().size()==2,"both physical cartons arrived")
	check(game.take_delivery(spare) and bool(game.store_customer_stock(spare).ok),"spare received onto shelf")
	check(game.take_delivery(id) and not game.take_delivery(spare),"one hand carry capacity")
	game.save_path=bad_path; failed=game.stage_customer_stock(id); game.save_path=path
	check(str(failed.error)=="save" and str(game.customer_stock_for(id).contract_id).is_empty() and game._customer_hardware().is_empty(),"failed stage leaves no phantom association")
	check(bool(game.stage_customer_stock(id).ok),"stage serial onto actual contract")
	check(game.vm_run("ssh client").contains("Connected") or bool(game.vm_info().connected),"staged machine connects")
	var manifest=JSON.parse_string(game.vm_read("/etc/hardware.json"))
	check(manifest is Dictionary and str(manifest.get("serial",""))==str(game.customer_stock_for(id).serial),"VM manifest is physical serial")
	check(game.vm_run("dig intranet.client.test").contains("SERVFAIL"),"factory DNS has no working intranet")
	check(game.take_delivery(id),"staged carton can be picked up")
	check(str(game.dispatch_customer_stock(id).error)=="checks" and str(game.customer_stock_for(id).status)=="carried","untested hardware cannot ship")
	check(game.vm_run("ssh client").contains("hardware_unavailable"),"carried hardware offline")
	check(not game._colleague_hardware_connected({"contract_id":str(game.state.current_contract_id),"target_index":0}),"background staff pauses while device is unplugged")
	check(game.put_down_delivery(id,[-2.8,0.16,3.1]) and str(game._customer_hardware().id)==id,"drop preserves serial association")
	check(game.save_game() and game.load_game(),"JSON roundtrip with assigned floor and shelf stock")
	check(game.take_delivery(id) and bool(game.stage_customer_stock(id).ok),"restage same serial")
	game.vm_run("ssh client")
	check(bool(game.firewall_action("services",{"dns":"on","tls":"on"}).ok),"DNS configured through real service action")
	var rule: Dictionary={}
	for candidate in game._vm().firewall_snapshot().rules:
		if str(candidate.id)=="lan-business":rule=candidate.duplicate(true)
	check(not rule.is_empty(),"real LAN rule selected")
	rule.action="pass"
	check(bool(game.firewall_action("save_rule",{"rule":rule}).ok),"real LAN policy saved")
	check(game.vm_run("dig intranet.client.test").contains("SERVFAIL"),"draft does not alter applied policy")
	check(bool(game.firewall_action("apply").ok),"policy applied to staged hardware")
	check(game.vm_run("curl https://intranet.client.test").begins_with("HTTP/1.1 200"),"employee business access restored")
	check(game.vm_run("curl https://admin.client.test:8443").contains("FIREWALL_DENIED"),"WAN administration denied")
	for probe in game.diagnostic_probes():game.run_diagnostic(str(probe.id))
	var checks: Array=game.verify()
	check(checks.any(func(c):return bool(c.get("hardware",false)) and not bool(c.passed)),"arrival gate visible")
	check(checks.filter(func(c):return not bool(c.get("hardware",false))).all(func(c):return bool(c.passed)) and not game.can_deliver(),"real measurements pass but undelivered appliance cannot invoice")
	check(game.take_delivery(id),"pick up verified serial")
	game.save_path=bad_path; failed=game.dispatch_customer_stock(id); game.save_path=path
	check(str(failed.error)=="save" and str(game.customer_stock_for(id).status)=="carried","shipment save failure rolls back")
	check(bool(game.dispatch_customer_stock(id).ok) and not game.can_deliver(),"verified serial ships but arrival pending")
	check(game.customer_stock_summary().used==1,"shipping frees warehouse capacity")
	check(game.save_game() and game.load_game(),"shipping reload")
	game.advance_delivery(11.0);check(str(game.customer_stock_for(id).status)=="shipping","shipment lead time respected")
	game.advance_delivery(1.0);check(str(game.customer_stock_for(id).status)=="delivered" and game.can_deliver(),"physical arrival releases invoice")
	var before_invoice: int=game.state.cash
	check(game.deliver(),"invoice completed")
	var receipt: Dictionary=game.completion_receipt()
	if receipt.is_empty():
		print("DELIVERY_DIAG ",JSON.stringify({"checks":game._vm_checks(),"targets":game.state.targets,"fp":game._vm()._fingerprint(),"probes":game.diagnostic_probes()})); finish(); return
	check(int(receipt.material_cost)==3200 and int(receipt.cost)==3900 and str(receipt.hardware_serial)==str(game.customer_stock_for(id).serial),"receipt records single actual COGS and serial")
	check(int(game.state.cash)==before_invoice-700 and int(game.state.profit)==profit+int(receipt.net),"delivery records operating cost while preserving paid hardware COGS")
	check(not game.deliver(),"duplicate invoice refused")
	var ledger: Dictionary=game.day_preview()
	check(int(ledger.inventory_spending)==6400 and int(ledger.contract_net)==int(receipt.net),"ledger separates stock spending and earned profit")
	check(int(ledger.draft_total)==int(receipt.fee)+int(receipt.bonus)+int(receipt.material_cost),"delivered hardware is an invoice line awaiting collection")
	var invoice_id := str(receipt.get("invoice_id",""))
	var posted: Dictionary=game.post_invoice(invoice_id)
	check(bool(posted.get("ok",false)),"hardware invoice confirmed")
	if bool(posted.get("ok",false)):
		while int(game.state.day)<int(posted.invoice.due_day): check(game.end_day(),"advance to hardware invoice due day")
		check(int(game.state.cash)==cash+int(receipt.net)-3200 and int(game.state.profit)==profit+int(receipt.net) and int(game.state.cash)-cash+3200==int(game.state.profit)-profit,"collection reconciles cash, consumed COGS, and remaining inventory asset")
		var collected: int=game.state.cash
		check(bool(game.post_invoice(invoice_id).ok) and int(game.state.cash)==collected,"hardware receipt cannot be collected twice")
	check(str(game.customer_stock_for(spare).status)=="stored","unused stock survives job")
	check(game.save_game() and game.load_game() and str(game.customer_stock_for(spare).status)=="stored","completed shipment and spare survive reload")
	# Old saves acquire an empty inventory, never a hardware gate on remote jobs.
	game.save_path=path+".legacy";game.backup_path=path+".legacy.bak";game.previous_path=path+".legacy.previous"
	game._reset_state();game.choose_strategy("advisory");game.start_free_career()
	var old_offer: Dictionary={}
	for candidate in game.state.offers:
		if bool(candidate.market_available) and int(candidate.chapter)==2:old_offer=candidate;break
	check(not old_offer.is_empty() and game.choose_contract(str(old_offer.get("id",""))),"ordinary remote job accepted")
	game.state.erase("customer_stock");check(game.save_game() and game.load_game(),"legacy missing stock migration")
	check(game.customer_stock_units().is_empty() and game._customer_requirement().is_empty(),"old remote job needs no new hardware")
	game.vm_run("ssh client");check(bool(game.vm_info().connected),"old remote job connects normally")
	finish()
func finish() -> void:
	print("PROCUREMENT_TEST_PASS" if failures.is_empty() else "PROCUREMENT_TEST_FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
