extends SceneTree

var ui
var game
var pc
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	create_timer(150).timeout.connect(func(): push_error("cross service timeout"); quit(2))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ",label)

func frames(count: int = 5) -> void:
	for _i in count: await process_frame

func target(chapter: int) -> int:
	for i in game.state.targets.size():
		if int(game.state.targets[i].chapter)==chapter: return i
	return -1

func configure(chapter: int, values: Dictionary) -> void:
	check(game.select_target(target(chapter)),"configure target "+str(chapter)); game.vm_run("ssh client")
	check(game.vm_write(str(game.vm_info().config_path),str(game._vm().configuration_text(values))),"stage configuration")
	check(str(game.vm_run("systemctl restart "+str(game.vm_info().service))).contains("active"),"service available")

func fixture(case_id: String) -> bool:
	if is_instance_valid(ui):
		ui.queue_free(); await frames()
	ui=load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	game=ui._game(); game.set_process(false)
	check(game.save_path.begins_with("user://qa-"),"isolated QA storage")
	check(ui._new_game(),"new fixture")
	check(game.choose_strategy("advisory") and game.start_free_career(),"career")
	game.state.skills={"advisory":20,"operations":20,"response":20}; game.state.peak_profit=1000000; game.state.profit=1000000; game._update_growth()
	game.state.market_leads=[case_id]; game.state.market_day=int(game.state.day); game._make_offers()
	var offer: Dictionary={}
	for item in game.state.offers:
		if str(item.get("case_id",""))==case_id and bool(item.get("market_available",false)): offer=item; break
	check(not offer.is_empty(),"offer "+case_id)
	if offer.is_empty(): return false
	check(game.set_offer_quote(str(offer.id),int(offer.get("reward",offer.get("base_reward",0)))) and game.choose_contract(str(offer.id)),"accept "+case_id)
	if target(0)>=0: configure(0,{"staff":"write","guest":"none"})
	configure(2,{"dns":"on","business":"allow","admin_public":"deny","tls":"on"})
	game.set_settings({"resolution":"1280x720","window_mode":"windowed","volume":0},false)
	root.size=Vector2i(1280,720); ui.open_panel("terminal"); await frames()
	pc=ui.desktop; pc._show_app("browser"); await frames()
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	await frames()
	return true

func press(name: String) -> void:
	var button=pc.widgets.browser.page.find_child(name,true,false)
	check(button is BaseButton,"button "+name)
	if button is BaseButton: button.pressed.emit()
	await frames()

func fill(name: String, value: String) -> void:
	var input=pc.widgets.browser.page.find_child(name,true,false)
	check(input is LineEdit,"input "+name)
	if input is LineEdit: input.text=value; input.text_changed.emit(value)

func text(name: String) -> String:
	var input=pc.widgets.browser.page.find_child(name,true,false)
	return str(input.text) if input is LineEdit else "<missing>"

func switch_to(chapter: int) -> void:
	check(pc._select_target(target(chapter)),"UI target switch "+str(chapter)); await frames()
	pc._run_command("ssh client"); await frames()

func read_invariant() -> String:
	return JSON.stringify({"clock":game.state.get("clock_minutes"),"work":game.state.get("work"),"cash":game.state.get("cash"),"history":game.state.get("history"),"revision":game.state.get("revision"),"checks":game.state.get("checks"),"vm":game._vm().export_state()},"",true)

func verify_reads(resource: String) -> void:
	await frames()
	var before:=read_invariant()
	for _i in 12:
		game.business_read(resource,pc.browser_url)
		pc._refresh_business_if_changed()
	await frames()
	check(read_invariant()==before,"passive/read API has no clock, fee, evidence, traffic, or probe effects")
	before=read_invariant()
	await press("BusinessRefresh")
	check(read_invariant()==before,"explicit business Refresh is read-only")

func run() -> void:
	if not await fixture("composite-branch-reopen"): quit(1); return
	var initial_read:=read_invariant()
	pc._browse_url("https://intranet.client.test/sales",true); await frames()
	check(read_invariant()==initial_read,"initial business browser navigation is read-only")
	check(pc.browser_response.contains("12800"),"initial orders shown")
	await verify_reads("orders")
	await press("BusinessNewOrder"); fill("BusinessOrderTotal","12345")
	var original_revision: String=str(pc.business_ui.get("form_revision",""))
	await switch_to(0)
	pc._run_command("cp /srv/share/customers.csv /home/operator/customers-original.csv")
	pc._run_command("cp /srv/share/partner-order.csv /home/operator/orders-original.csv")
	# Upload inputs are fixture documents; the canonical share is changed only by SMB.
	check(game.vm_write("/home/operator/customers-upload.csv","id,name\n101,Aoba\n102,Minato\n103,北町営業\n"),"prepare customer upload")
	check(game.vm_write("/home/operator/orders-upload.csv","order,customer,total\n501,101,18900\n502,103,32000\n"),"prepare order upload")
	pc._run_command("smbclient //files01.client.test/share -U staff -c 'put /home/operator/customers-upload.csv customers.csv'")
	pc._run_command("smbclient //files01.client.test/share -U staff -c 'put /home/operator/orders-upload.csv partner-order.csv'")
	check(pc.terminal_log.contains("putting file partner-order.csv: OK"),"terminal SMB writes actual share")
	await switch_to(2); pc._show_app("browser"); await frames(8)
	check(pc.browser_response.contains("北町営業") and pc.browser_response.contains("32000"),"business browser follows customer and order SMB writes")
	check(text("BusinessOrderTotal")=="12345" and str(pc.business_ui.get("form_revision",""))==original_revision,"unsaved order draft and original revision survive source switch")
	await press("BusinessSave")
	check(text("BusinessOrderTotal")=="12345" and not pc.browser_response.contains("12345"),"stale draft does not overwrite updated data and input remains")
	await switch_to(0)
	pc._run_command("smbclient //files01.client.test/share -U staff -c 'put /home/operator/customers-original.csv customers.csv'")
	pc._run_command("smbclient //files01.client.test/share -U staff -c 'put /home/operator/orders-original.csv partner-order.csv'")
	await switch_to(2); pc._show_app("browser"); await frames(8)
	check(pc.browser_response.contains("12800") and not pc.browser_response.contains("北町営業"),"restored original files are visible")
	check(text("BusinessOrderTotal")=="12345","restoration preserves pending input")
	await press("BusinessSave")
	check(pc.browser_response.contains("12345") and str(pc.business_ui.get("form",""))=="","registration succeeds after exact baseline restoration")
	var owner_key: String=game._vm_key(target(0))
	var expected_customers: String=str(game.state.vm_states[owner_key].fs["/srv/share/customers.csv"])
	var expected_orders: String=str(game.state.vm_states[owner_key].fs["/srv/share/partner-order.csv"])
	check(pc._save_session() and game.save_game(),"save data and pending UI context")
	game._machine=null; game._machine_key=""; check(game.load_game(),"reload saved service")
	pc._reload_contract_session(); await frames(8); pc._show_app("browser"); await frames()
	check(str(game.state.vm_states[owner_key].fs["/srv/share/customers.csv"])==expected_customers and str(game.state.vm_states[owner_key].fs["/srv/share/partner-order.csv"])==expected_orders,"reopen retains exact canonical shared bytes")
	check(pc.browser_response.contains("12345"),"reopened browser shows saved order")
	await verify_reads("orders")

	if not await fixture("firm-remote-hardening"): quit(1); return
	initial_read=read_invariant()
	pc._browse_url("https://intranet.client.test/accounting",true); await frames()
	check(read_invariant()==initial_read,"initial accounting navigation is read-only")
	await press("BusinessNewLedger"); fill("BusinessLedgerDate","2026-09-20"); fill("BusinessLedgerAmount","500")
	check(pc._save_session() and game.save_game(),"save unfinished ledger draft")
	game._machine=null; game._machine_key=""; check(game.load_game(),"reopen unfinished draft")
	pc._reload_contract_session(); await frames(8); pc._show_app("browser"); await frames()
	check(text("BusinessLedgerAmount")=="500" and text("BusinessLedgerDate")=="2026-09-20","unsaved ledger draft survives full save and reopen")
	pc._run_command("cp /srv/data/ledger.txt /home/operator/ledger-original.txt")
	check(game.vm_write("/home/operator/ledger-upload.txt","2026-09-18 opening=50000 closing=75000\n"),"prepare valid ledger document")
	pc._run_command("cp /home/operator/ledger-upload.txt /srv/data/ledger.txt"); await frames(8)
	check(pc.browser_response.contains("75000"),"visible accounting follows terminal copy without Refresh")
	check(text("BusinessLedgerAmount")=="500" and text("BusinessLedgerDate")=="2026-09-20","ledger draft survives passive refresh")
	await press("BusinessSave")
	check(text("BusinessLedgerAmount")=="500" and pc.browser_response.contains("75000"),"stale ledger append is rejected without losing draft")
	pc._run_command("cp /home/operator/ledger-original.txt /srv/data/ledger.txt"); await frames(8)
	check(pc.browser_response.contains("62800"),"restored ledger returns to original balance")
	await press("BusinessSave")
	check(pc.browser_response.contains("63300"),"new append derives balance from restored ledger")
	var expected_ledger: String=game.vm_read("/srv/data/ledger.txt")
	check(pc._save_session() and game.save_game(),"save appended ledger")
	game._machine=null; game._machine_key=""; check(game.load_game(),"reopen appended ledger")
	pc._reload_contract_session(); await frames(8); pc._show_app("browser"); await frames()
	check(game.vm_read("/srv/data/ledger.txt")==expected_ledger and pc.browser_response.contains("63300"),"reopen retains exact ledger bytes and derived balance")
	await verify_reads("ledger")
	if failures.is_empty(): print("BUSINESS_CROSS_SERVICE_UI_PASS assertions=",assertions)
	else: print("BUSINESS_CROSS_SERVICE_UI_FAIL count=",failures.size()," assertions=",assertions)
	quit(0 if failures.is_empty() else 1)
