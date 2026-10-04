extends "res://tests/test_care_lifecycle.gd"
## Normal funds and real repairs; deterministic market-lead fixture only.
## Covers replacement of the same retained asset and addition of another one.
func _init() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	call_deferred("run_parallel")

func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func run_parallel() -> void:
	for other_case in ["service-1-case-0", "service-0-case-1"]:
		game=load("res://scripts/game.gd").new();root.add_child(game);game.set_process(false)
		var stem:="user://qa-care-parallel-%s-%s" % [OS.get_process_id(),other_case]
		game.save_path=stem+".json";game.backup_path=stem+".bak";game.previous_path=stem+".previous";game.settings_path=stem+".settings"
		expect(game.new_game() and game.choose_strategy("operations") and game.start_free_career(),"normal funded career")
		game.set_offer_plan("care")
		var offer:=_service_offer("service-1-case-0")
		expect(not offer.is_empty() and game.choose_contract(str(offer.get("id",""))),"real backup care accepted")
		game.inspect_mission();await _finish_contract();expect(game.deliver(),"real backup delivery")
		var client:=str(offer.client)
		expect(bool(game.post_invoice(str(game.completion_receipt().invoice_id)).ok),"earned invoice collected")
		expect(game.end_day(),"second day")
		if other_case=="service-0-case-1":expect(game.learn_skill("advisory"),"earned skill opens different service")
		var parallel:=_service_offer(other_case)
		expect(not parallel.is_empty() and str(parallel.get("client",""))==client and game.choose_contract(str(parallel.get("id",""))),"ordinary care contract opened for same client")
		var ordinary_id:=str(game.state.current_contract_id)
		game.vm_run("ssh client");expect(game.vm_write("/home/operator/parallel-note.txt","UNSAVED WORK CONTEXT"),"ordinary VM has separate live work")
		var vm_before: Variant=canonical(game._vm().export_state())
		var detected:=false
		for _day in 7:
			game.maintenance_jobs()
			if game.can_run_maintenance(client):expect(game.run_maintenance(client),"parallel retained inspection executes")
			if str(game.care_incident(client).get("status",""))=="detected":detected=true;break
			expect(game.end_day(),"advance ordinary unfinished contract")
		expect(detected,"unfinished ordinary work does not suppress real drift")
		expect(canonical(game._vm().export_state())==vm_before,"drift and inspection leave ordinary working bytes unchanged")
		expect(str(game.state.current_contract_id)==ordinary_id,"ordinary context remains selected")
		expect(game.maintenance_result(client).begins_with("FAIL"),"actual retained probe observes fault")
		expect(int(game.maintenance_summary().earned)==0,"fault earns no daily retainer")
		var incident_id:=str(game.care_incident(client).get("id",""))
		expect(not game.open_maintenance_incident(client),"ordinary work must be handed back before opening repair")
		expect(game.end_day(),"failed inspection day closes")
		expect(str(game.care_incident(client).get("id",""))==incident_id,"unresolved incident is not replaced next day")
		expect(canonical(game._vm().export_state())==vm_before,"day transition preserves parallel draft")
		game.inspect_mission();await _finish_contract();expect(game.deliver(),"ordinary work actually finishes")
		var count:=1 if other_case=="service-1-case-0" else 2
		expect(game.state.maintenance_targets[client].size()==count,"scope merges only matching asset identity")
		expect(str(game.care_incident(client).get("status",""))=="detected","ordinary delivery does not silently close incident")
		expect(game.can_run_maintenance(client) and game.run_maintenance(client),"expanded scope requires actual reinspection")
		if other_case=="service-0-case-1":
			expect(game.maintenance_result(client).begins_with("FAIL"),"new healthy service does not mask broken old asset")
			expect(game.open_maintenance_incident(client),"real retained repair opens after ordinary work")
			game.inspect_mission();await _finish_contract()
			var money:=int(game.state.cash);var credit:=int(game.state.credit)
			expect(game.deliver(),"all retained assets repaired")
			expect(int(game.state.cash)==money and int(game.state.credit)==credit,"covered repair grants no fee or credit")
			expect(game.run_maintenance(client),"repaired full scope rechecked")
		expect(str(game.care_incident(client).get("status",""))=="closed" and game.maintenance_result(client).begins_with("PASS"),"actual full inspection closes incident")
		expect(int(game.maintenance_summary().earned)==int(game.state.care_agreements[client].fee),"verified retained business restores earnings")
		expect(game.save_game() and game.load_game(),"recovered scope survives save/load")
		expect(str(game.care_incident(client).get("status",""))=="closed","loaded incident remains closed")
		expect(game.end_day(),"recovered day settles")
		expect(str(game.care_incident(client).get("status",""))=="closed","new grace period prevents immediate duplicate incident")
		game.queue_free()
	print("CARE_PARALLEL_WORK_PASS" if failures==0 else "CARE_PARALLEL_WORK_FAIL count="+str(failures))
	quit(0 if failures==0 else 1)
