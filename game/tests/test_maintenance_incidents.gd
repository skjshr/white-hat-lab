extends SceneTree

const VM = preload("res://scripts/virtual_machine.gd")
const Incidents = preload("res://scripts/maintenance_incidents.gd")
const Catalog = preload("res://scripts/case_catalog.gd")
var failures := 0

func expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)

func make_target(chapter: int, desired: Dictionary) -> Dictionary:
	var vm = VM.new()
	var scenario := {"desired":desired,"probes":[]}
	scenario.initial = desired.duplicate(true)
	vm.setup(chapter, {}, scenario)
	if chapter == 4: vm.state.fs["/evidence/original.log"] = vm.state.evidence_original
	return {"chapter":chapter,"vm_key":"fixture/site-0","vm_state":vm.export_state(),"scenario":scenario}

func _init() -> void:
	var healthy := make_target(0, {"staff":"write","guest":"none"})
	var original := healthy.duplicate(true)
	var result := Incidents.introduce([healthy], "incident-share-1")
	expect(bool(result.changed) and int(result.target_index) == 0 and str(result.kind) == "share", "share incident selected")
	expect(healthy.vm_state.fs == original.vm_state.fs, "input target not mutated")
	var changed_vm = VM.new(); changed_vm.setup(0, result.targets[0].vm_state, result.targets[0].scenario)
	expect(str(changed_vm.state.applied.get("guest","")) == "read", "guest access drift measured")
	expect(changed_vm.state.snapshots == original.vm_state.snapshots, "snapshots preserved")
	expect(changed_vm.state.fs.get("/var/log/evidence.log","") == original.vm_state.fs.get("/var/log/evidence.log",""), "evidence preserved")
	expect(str(changed_vm.state.events[-1]).contains("incident=incident-share-1"), "incident audit persisted")
	var custom_vm = VM.new(); custom_vm.setup(0); custom_vm.run("ssh client")
	var custom_conf := "[global]\n    server role = standalone server\n    map to guest = Bad User\n    guest account = nobody\n\n[share]\n    path = /srv/share\n    available = yes\n    read only = yes\n    guest ok = no\n    valid users = staff\n    write list = staff\n    read list = staff\n\n[private]\n    path = /srv/private\n    read only = yes\n    guest ok = no\n    valid users = staff\n"
	expect(custom_vm.write_file(str(custom_vm.state.config_path), custom_conf), "custom smb config write")
	expect(custom_vm.run("systemctl restart samba").contains("active (running)"), "custom smb config active")
	var custom_target := {"chapter":0,"vm_key":"custom/site-0","vm_state":custom_vm.export_state(),"scenario":{}}
	var custom_result := Incidents.introduce([custom_target], "incident-share-custom")
	var custom_changed = VM.new(); custom_changed.setup(0, custom_result.targets[0].vm_state, {})
	expect(bool(custom_result.changed) and str(custom_changed.state.applied.samba.share["read list"]) == "staff" and not bool(custom_changed.state.applied.samba.private["guest ok"]), "custom smb option preserved")
	var identity := make_target(3, {"former":"disabled","sessions":"revoked","current":"active","mfa":"on"})
	var identity_result := Incidents.introduce([identity], "incident-account-1")
	expect(bool(identity_result.changed) and str(identity_result.kind) == "account", "account incident selected")
	var identity_vm = VM.new(); identity_vm.setup(3, identity_result.targets[0].vm_state, identity_result.targets[0].scenario)
	expect(str(identity_vm.state.applied.get("current","")) == "disabled", "current account drift measured")
	var pc_b_target := make_target(4, {"pc_a":"connected","pc_b":"connected","logs":"keep","reset":"wait"})
	var pc_b_result := Incidents.introduce([pc_b_target], "incident-pc-b")
	var pc_b_vm = VM.new(); pc_b_vm.setup(4, pc_b_result.targets[0].vm_state, pc_b_result.targets[0].scenario)
	expect(bool(pc_b_result.changed) and str(pc_b_vm.state.applied.get("pc_b","")) == "isolated", "pc-b incident selected")
	var ineligible := make_target(4, {"pc_a":"connected","pc_b":"connected","logs":"keep","reset":"wait"})
	ineligible.vm_state.applied.pc_b = "isolated"
	ineligible.vm_state.fs[ineligible.vm_state.config_path] = "# scenario configuration\npc_a=connected\npc_b=isolated\nlogs=keep\nreset=wait\n"
	var no_change := Incidents.introduce([ineligible], "incident-noop-1")
	expect(not bool(no_change.changed) and no_change.targets == [ineligible], "ineligible target unchanged")
	var catalog_checked := 0
	for item in Catalog.all():
		if item.get("targets", []).size() > 0: continue
		var chapter := int(item.get("chapter", -1))
		var machine = VM.new(); machine.setup(chapter, {}, item)
		machine.run("ssh client")
		var config := machine.configuration_text(item.get("desired", {}))
		if not machine.write_file(str(machine.state.config_path), config): continue
		if not machine.run("systemctl restart " + str(machine.state.service)).contains("active (running)"): continue
		if chapter == 1:
			var good_id := ""
			for snapshot in machine.state.snapshots:
				if snapshot.get("repository", "") == item.desired.get("repository", "") and snapshot.get("files", {}) == machine.RECORDS:
					good_id = str(snapshot.get("id", "")); break
			if good_id.is_empty():
				machine.run("restic backup /srv/data")
				for snapshot in machine.state.snapshots:
					if snapshot.get("repository", "") == item.desired.get("repository", "") and snapshot.get("files", {}) == machine.RECORDS:
						good_id = str(snapshot.get("id", "")); break
			if not good_id.is_empty(): machine.run("restic restore " + good_id + ":/srv/data --target /restore")
		if chapter == 4:
			machine.run("cp /var/log/evidence.log /evidence/original.log")
		var target := {"chapter":chapter,"vm_key":str(item.id), "vm_state":machine.export_state(),"scenario":item.duplicate(true)}
		var incident := Incidents.introduce([target], "catalog-"+str(item.id))
		expect(bool(incident.changed), "healthy catalog incident "+str(item.id))
		catalog_checked += 1
	expect(catalog_checked > 30, "catalog healthy coverage")
	print("MAINTENANCE incidents failures=%d" % failures)
	quit(1 if failures > 0 else 0)
