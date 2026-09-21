extends SceneTree

const Game = preload("res://scripts/game.gd")
const Catalog = preload("res://scripts/case_catalog.gd")
const VM = preload("res://scripts/virtual_machine.gd")
var failures: Array[String] = []

func _assert(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _new_game() -> Game:
	var game := Game.new(); root.add_child(game)
	game.save_path = "user://diagnostics_qa.json"; game.backup_path = "user://diagnostics_qa.json.bak"; game.previous_path = "user://diagnostics_qa.previous.json"; game.settings_path = "user://diagnostics_qa_settings.json"
	game.new_game(); game.choose_strategy("advisory")
	return game

func _prepare(game: Game, item: Dictionary, completed: Array = []) -> void:
	if item.has("targets") and item.targets is Array and not item.targets.is_empty():
		game.state.career_mode = true; game.state.awaiting_contract = true; game.state.peak_profit = 1000000
		game.state.skills = {"operations":3,"advisory":3,"response":3}; game._make_offers()
		for offer in game.state.offers:
			if str(offer.get("case_id", "")) == str(item.id):
				game.choose_contract(str(offer.id)); break
		game.vm_run("ssh client")
		return
	game.state.chapter = int(item.chapter); game.state.credit = 999999; game.state.completed_ids = completed.duplicate()
	game.state.contract = {"case_id":str(item.id)}; game.state.current_contract_id = ""
	game.accept_mission()
	game.vm_run("ssh client")

func _apply_and_probe(game: Game, item: Dictionary) -> bool:
	var machine = game._vm()
	var config: String = machine._config_text(item.desired)
	if not game.vm_write(game.vm_info().config_path, config): return false
	if game.vm_run("systemctl restart "+game.vm_info().service).begins_with("Job failed"): return false
	if int(item.chapter) == 1:
		var has_valid := false
		for snapshot in machine.state.get("snapshots", []):
			if snapshot.get("repository", "") == item.desired.get("repository", "") and snapshot.get("files", {}) == machine.RECORDS: has_valid = true
		if not has_valid: game.vm_run("restic backup /srv/data")
		game.vm_run("restic restore 00000001:/srv/data --target /restore" if item.has("latest_snapshot_overrides") else "restic restore latest --target /restore")
	if int(item.chapter) == 4: game.vm_run("cp /var/log/evidence.log /evidence/original.log")
	preload("res://tests/identity_test_support.gd").authenticate_current(game)
	# A probe such as an upload can legitimately mutate its result fixture. Re-run
	# stale observations once the fixture has settled, as the terminal UI asks.
	for pass_index in 3:
		for probe in game.diagnostic_probes():
			if not (bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and bool(probe.get("passed", false))):
				game.run_diagnostic(str(probe.id))
		if game.diagnostic_probes().all(func(p): return p.recorded and p.fresh and p.passed): break
	return game.verify().all(func(check): return check.passed)

func _init() -> void:
	var game := _new_game()
	for chapter in 6:
		var item := {"id":str(["share","backup","network","account","incident","transfer"][chapter]),"chapter":chapter,"desired":game._legacy_desired() if game.has_method("_legacy_desired") else {}}
		_prepare(game, item, ["share","backup","network","account","incident"].slice(0, chapter))
		_assert(not game.diagnostic_probes().is_empty(), "story probes %d" % chapter)
		_assert(not game.can_deliver(), "unmeasured story %d blocked" % chapter)
		game.assign_colleague("aya"); _assert(not game.can_deliver(), "NPC alone story %d blocked" % chapter)
		game._assignments = {}; game.state.assignments = {}
		var desired: Dictionary = game._vm()._legacy_desired()
		if chapter == 0: _assert(game.capture_baseline(), "baseline capture story 0")
		_assert(_apply_and_probe(game, {"chapter":chapter,"desired":desired}), "story operation %d" % chapter)
		_assert(game.can_deliver(), "measured story %d can deliver" % chapter)
		if chapter == 0:
			game.save_game(); game.load_game(); _assert(game.diagnostic_probes().all(func(p): return p.recorded and p.fresh), "saved probes restore")
			var before := game.diagnostic_probes().size(); game.vm_read("/home/aoba/README.txt")
			_assert(game.diagnostic_probes().size() == before and game.diagnostic_probes().all(func(p): return p.fresh), "unrelated file read keeps probes")
			game.rollback_configuration(); _assert(not game.can_deliver() and game.diagnostic_probes().any(func(p): return not p.fresh), "rollback invalidates diagnostics")
			_apply_and_probe(game, {"chapter":chapter,"desired":desired})
		_assert(game.deliver(), "story delivery %d" % chapter)

	var prior := ["share","backup","network","account","incident"]
	for item in Catalog.all():
		if item.has("targets") and item.targets is Array and not item.targets.is_empty(): continue
		var cgame := _new_game(); _prepare(cgame, item, prior if int(item.chapter) > 0 else [])
		_assert(_apply_and_probe(cgame, item), "catalog measured %s" % item.id)
		_assert(cgame.can_deliver(), "catalog deliver gate %s" % item.id)
		_assert(cgame.deliver(), "catalog delivery %s" % item.id)

	for composite in Catalog.all():
		if composite.get("targets",[]).is_empty(): continue
		var multi := _new_game(); _prepare(multi, composite, [])
		_assert(multi.state.targets.size() == composite.targets.size(), "composite target count "+str(composite.id))
		var original_budget: float = multi.work_status().budget
		for target_index in multi.state.targets.size():
			multi.select_target(target_index); multi.vm_run("ssh client")
			_assert(multi.work_status().budget == original_budget,"stable composite deadline")
			var target_case := Catalog.by_id(str(multi.state.targets[target_index].case_id))
			_assert(_apply_and_probe(multi, target_case), "composite target %s/%d" % [composite.id,target_index])
			_assert(multi.can_deliver() == (target_index == multi.state.targets.size()-1),"all services required")
		_assert(multi.deliver(),"composite delivery "+str(composite.id))
	# Actual completed colleague work must preserve policy and leave delivery to the player.
	var crew := _new_game(); crew.accept_mission(); crew.vm_run("ssh client")
	var original_config: String = crew.vm_read(crew.vm_info().config_path)
	for id in ["aya","ren"]:
		crew.assign_colleague(id); crew._finish_colleague(id,crew._assignments[id])
	_assert(crew.vm_read(crew.vm_info().config_path)==original_config,"crew never silently chooses policy")
	_assert(not crew.vm_read("/home/operator/aya-inspection.txt").is_empty(),"crew writes actual report")
	_assert(crew.capture_baseline(),"investigation does not lock configuration backup")
	_assert(not crew.can_deliver(),"completed crew tasks alone cannot deliver")
	# Service failures are distinct from a successful access rejection.
	var network := _new_game(); _prepare(network,Catalog.by_id("service-2-case-0"))
	network.run_diagnostic("admin-check")
	_assert(not network.diagnostic_probes().filter(func(p):return p.id=="admin-check")[0].passed,"DNS failure is not accepted as access denial")
	# Transport negotiation is evaluated before the admin application policy:
	# an HTTPS request with TLS disabled must not teach a learner that a 403
	# authorization response was observed.
	var legacy_network: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../artifacts/simulator/v124/legacy-v123-firewall.json")))
	var tls_order := VM.new(); tls_order.setup(2,legacy_network); tls_order.run("ssh client")
	tls_order.state.applied = {"dns":"on","business":"allow","admin_public":"deny","tls":"off"}
	_assert(tls_order.run("curl https://admin.client.test/").begins_with("curl: (35) TLS handshake failed"),"TLS handshake precedes admin authorization")
	tls_order.state.applied.tls = "on"
	_assert(tls_order.run("curl https://admin.client.test/").begins_with("HTTP/1.1 403"),"admin authorization is evaluated after TLS")
	var stale_tls := VM.new(); stale_tls.setup(2,legacy_network); stale_tls.run("ssh client")
	stale_tls.state.applied = {"dns":"on","business":"allow","admin_public":"deny","tls":"off"}
	var stale_admin: Dictionary = stale_tls._active_probes().filter(func(p):return p.id=="admin-check")[0]
	stale_admin.expectation = "status:403"; stale_admin.recorded = true; stale_admin.passed = true; stale_admin.fresh = true; stale_admin.result = "HTTP/1.1 403 Forbidden"; stale_admin.fingerprint = "old-tls-fingerprint"
	stale_admin.fingerprint = stale_tls._fingerprint()
	_assert(bool(stale_admin.recorded) and bool(stale_admin.passed),"old admin result is a recorded saved measurement")
	var stale_tls_loaded := VM.new(); stale_tls_loaded.setup(2, stale_tls.export_state()); stale_tls_loaded.run("ssh client")
	var normalized_admin: Dictionary = stale_tls_loaded.probes().filter(func(p):return p.id=="admin-check")[0]
	_assert(str(normalized_admin.expectation)=="status:403" and not bool(normalized_admin.get("recorded",false)) and not bool(normalized_admin.get("passed",false)),"old admin authorization result is invalidated after TLS ordering change")
	var before_scenario: String = network._scenario().id
	network.vm_run("reset-lab --confirm")
	_assert(network._vm().state.scenario.id==before_scenario,"reset preserves customer scenario")
	_assert(network.diagnostic_probes().all(func(p):return not p.recorded),"reset clears old measurements")
	# Load must preserve old ongoing contracts without retroactively imposing new gates.
	crew.state.erase("diagnostics_required"); crew.save_game(); crew.load_game()
	_assert(not crew.state.diagnostics_required,"old contract compatibility")
	# Portal v2 is exercised at the VM boundary so browser presentation cannot
	# accidentally mask authorization, expiry, route, or audit regressions.
	var portal := VM.new(); portal.setup(5); portal.run("ssh client")
	portal.write_file(str(portal.state.config_path),portal.configuration_text({"staff":"write","partner":"read","public":"read","expires":"7d","mfa":"on","tls":"on","audit":"on"}));portal.run("systemctl restart portal")
	var denied := portal.run("curl -H 'Authorization: Bearer partner-session' 'https://portal.client.test/partner?link=current'")
	var allowed := portal.run("curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=current'")
	_assert(denied.contains("401") and denied.contains("mfa_required"),"portal password-only session rejected")
	_assert(allowed.begins_with("HTTP/1.1 200"),"portal MFA session allowed")
	_assert(portal.run("curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=month-old'").begins_with("HTTP/1.1 410"),"portal 7d expiry")
	portal.run("portal share partner read 30d")
	_assert(portal.run("curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=week-old'").begins_with("HTTP/1.1 200"),"portal 30d week-old link")
	_assert(portal.run("curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=month-old'").begins_with("HTTP/1.1 410"),"portal 30d expiry")
	portal.run("portal share partner read unlimited")
	_assert(portal.run("curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=month-old'").begins_with("HTTP/1.1 200"),"portal unlimited link")
	_assert(portal.run("curl https://unknown.client.test/partner").begins_with("curl: (6)"),"portal unknown host")
	_assert(portal.run("curl https://portal.client.test/unknown").begins_with("HTTP/1.1 404"),"portal unknown route")
	var audit_fingerprint := portal._fingerprint()
	portal.run("curl -H 'Authorization: Bearer partner-session' 'https://portal.client.test/partner?link=current'")
	portal.run("curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=current'")
	_assert(portal._fingerprint() == audit_fingerprint,"audit GET keeps diagnostic fingerprint fresh")
	var audit_log := str(portal.run("journalctl"))
	_assert(audit_log.contains("identity=partner") and audit_log.contains("status=401 result=denied") and audit_log.contains("status=200 result=allowed"),"audit identifies actual denied and allowed outcomes")
	var active_portal := _new_game(); _prepare(active_portal,Catalog.by_id("service-5-case-0"))
	_assert(_apply_and_probe(active_portal,Catalog.by_id("service-5-case-0")),"portal complete access evidence")
	var valid_revision: int = active_portal.state.validated_revision
	active_portal.vm_run("curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=current'")
	_assert(active_portal.state.validated_revision == valid_revision and active_portal.can_deliver(),"audited read preserves Game delivery validation")
	var legacy_saved: Dictionary = portal.export_state(); legacy_saved.erase("access_model_version")
	var legacy_portal := VM.new(); legacy_portal.setup(5, legacy_saved)
	_assert(int(legacy_portal.state.get("access_model_version",0)) == 1,"saved portal state remains v1")
	_assert(legacy_portal.run("curl https://portal.client.test/partner").begins_with("HTTP/1.1 200"),"legacy portal probe behavior preserved")
	# Samba v2 keeps the semantic exercise but uses an actual smb.conf subset.
	var samba := VM.new(); samba.setup(0); samba.run("ssh client")
	_assert(int(samba.state.get("samba_model_version",0)) == 2,"new Samba VM is versioned")
	_assert(str(samba.state.fs[samba.state.config_path]).contains("[global]") and str(samba.state.fs[samba.state.config_path]).contains("[share]"),"new Samba config uses sections")
	var samba_text := "[global]\nserver role = standalone server\nguest account = nobody\nmap to guest = Bad User\n\n[share]\npath = /srv/share\navailable = yes\nread only = yes\nguest ok = yes\nvalid users = staff, nobody\nwrite list = staff\nread list = nobody\n"
	samba.write_file(samba.state.config_path, samba_text)
	_assert(samba.run("testparm -s").contains("Loaded services file OK"),"testparm validates without applying")
	_assert(str(samba.state.applied.get("staff","")) == "read","testparm does not apply Samba config")
	_assert(samba.run("systemctl restart samba").contains("active"),"Samba real config restart")
	_assert(samba.run("smbclient //files01.client.test/share -U staff -c ls").begins_with("report.txt"),"Samba staff read")
	_assert(samba.run("smbclient //files01.client.test/share -U staff -c 'put /srv/data/orders.csv'").contains("OK"),"Samba write list overrides read only")
	_assert(samba.run("smbclient //files01.client.test/share -N -c ls").begins_with("report.txt"),"Samba anonymous guest read")
	_assert(samba.run("smbclient //files01.client.test/share -N -c 'put /srv/data/orders.csv'").contains("ACCESS_DENIED"),"Samba anonymous write denied")
	_assert(samba.run("smbclient //wrong.client.test/share -U staff -c ls").contains("BAD_NETWORK_NAME"),"Samba wrong host rejected")
	var old_config := str(samba.state.fs[samba.state.config_path]); samba.write_file(samba.state.config_path, "[share]\nread only = maybe\n")
	_assert(samba.run("testparm -s").contains("invalid") or samba.run("testparm -s").contains("missing"),"testparm rejects invalid syntax")
	_assert(samba.state.active,"testparm does not stop active service")
	var saved_samba: Dictionary = samba.export_state(); saved_samba.erase("samba_model_version"); saved_samba.fs[saved_samba.config_path] = "staff=read\nguest=write\n"; saved_samba.applied = {"staff":"read","guest":"write"}
	var legacy_samba := VM.new(); legacy_samba.setup(0,saved_samba)
	_assert(int(legacy_samba.state.get("samba_model_version",0)) == 1,"legacy Samba state remains v1")
	_assert(str(legacy_samba.state.fs[legacy_samba.state.config_path]).contains("staff=") ,"legacy Samba flat config preserved")
	# Boundary fixtures exercise effective smb.conf semantics rather than only the
	# catalog's generated configuration: defaults, list precedence, and paths.
	var samba_defaults := VM.new(); samba_defaults.setup(0); samba_defaults.run("ssh client")
	samba_defaults.write_file(samba_defaults.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\n\n[share]\npath = /srv/share\n")
	_assert(samba_defaults.run("systemctl restart samba").contains("active"),"Samba defaults config starts")
	_assert(samba_defaults.state.applied.get("staff") == "read" and samba_defaults.state.applied.get("guest") == "none","Samba default read-only and guest denial")
	_assert(samba_defaults.run("smbclient //client/share -U staff -c 'put /srv/data/orders.csv'").contains("ACCESS_DENIED"),"Samba default read-only blocks write")
	var samba_lists := VM.new(); samba_lists.setup(0); samba_lists.run("ssh client")
	samba_lists.write_file(samba_lists.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\n\n[share]\npath = /srv/share\nread only = yes\nguest ok = yes\nvalid users = staff\nwrite list = staff\nread list = staff\n")
	samba_lists.run("systemctl restart samba")
	_assert(samba_lists.run("smbclient //client/share -U staff -c 'put /srv/data/orders.csv'").contains("OK"),"Samba write list overrides read list")
	samba_lists.write_file(samba_lists.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\n\n[share]\npath = /srv/share\nread only = yes\nguest ok = yes\nvalid users = nobody\nwrite list = staff\nread list = staff\n")
	samba_lists.run("systemctl restart samba")
	_assert(samba_lists.run("smbclient //client/share -U staff -c 'put /srv/data/orders.csv'").contains("ACCESS_DENIED"),"Samba valid users blocks staff despite write list")
	samba_lists.write_file(samba_lists.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\n\n[share]\npath = /srv/share\nread only = yes\nguest ok = yes\nvalid users = staff\ninvalid users = staff\nwrite list = staff\nread list = staff\n")
	samba_lists.run("systemctl restart samba")
	_assert(samba_lists.run("smbclient //client/share -U staff -c 'put /srv/data/orders.csv'").contains("ACCESS_DENIED"),"Samba invalid users overrides write list")
	samba_lists.write_file(samba_lists.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\nread only = no\nguest ok = yes\nvalid users = staff\n\n[share]\npath = /srv/share\n")
	samba_lists.run("systemctl restart samba")
	_assert(samba_lists.state.applied.get("staff") == "write","Samba global defaults inherit into share")
	_assert(samba_lists.run("smbclient //client/share -U staff -c 'put /srv/data/orders.csv'").contains("OK"),"Samba inherited writable default permits staff")
	samba_lists.write_file("/tmp/upload.txt", "upload bytes")
	_assert(samba_lists.run("smbclient //client/share -U staff -c 'put /tmp/upload.txt uploaded.txt'").contains("OK") and samba_lists.state.fs.get("/srv/share/uploaded.txt","") == "upload bytes","Samba put reads local bytes")
	var samba_path := VM.new(); samba_path.setup(0); samba_path.run("ssh client")
	samba_path.state.dirs.append("/srv/share-alt"); samba_path.state.fs["/srv/share-alt/alt.txt"] = "alternate evidence"; samba_path.state.fs["/srv/share-alt/report.txt"] = "alternate report bytes"
	samba_path.write_file(samba_path.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\n\n[alt]\npath = /srv/share-alt\nread only = yes\nvalid users = staff\n")
	samba_path.run("systemctl restart samba")
	_assert(samba_path.run("smbclient //client/alt -U staff -c ls").contains("alt.txt"),"Samba alternate share lists its configured path")
	_assert(samba_path.run("smbclient //client/share -U staff -c ls").contains("BAD_NETWORK_NAME"),"Samba unconfigured share is rejected")
	_assert(samba_path.run("smbclient //client/alt -U staff -c 'get alt.txt /tmp/alt-copy.txt'").contains("OK") and samba_path.state.fs.get("/tmp/alt-copy.txt","") == "alternate evidence","Samba get preserves bytes at destination")
	samba_path.write_file(samba_path.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\n\n[share]\npath = /srv/share-alt\nread only = yes\nvalid users = staff\n")
	samba_path.run("systemctl restart samba")
	_assert(samba_path.run("curl https://files.client.test/staff/report.txt").contains("alternate report bytes"),"Browser GET uses configured alternate share bytes")
	samba_path.state.fs.erase("/srv/share-alt/report.txt")
	_assert(samba_path.run("curl https://files.client.test/staff/report.txt").begins_with("HTTP/1.1 404"),"Browser GET reports missing configured report")
	samba_path.write_file("/tmp/upload.txt", "upload evidence")
	_assert(samba_path.run("smbclient //client/share -U staff -c 'put /tmp/upload.txt uploaded.txt'").contains("ACCESS_DENIED"),"Samba read-only alternate share blocks put")
	var samba_missing := VM.new(); samba_missing.setup(0); samba_missing.run("ssh client")
	samba_missing.write_file(samba_missing.state.config_path, "[global]\nserver role = standalone server\n\n[share]\npath = /srv/no-such-share\nread only = no\nvalid users = staff\n")
	_assert(samba_missing.run("systemctl restart samba").contains("active"),"Samba missing path config parses")
	_assert(not samba_missing.evaluate()[0],"Samba missing path cannot satisfy staff write evaluation")
	_assert(samba_missing.run("smbclient //client/share -U staff -c ls").contains("BAD_NETWORK_NAME"),"Samba missing path is unavailable")
	var samba_mapping := VM.new(); samba_mapping.setup(0); samba_mapping.run("ssh client")
	samba_mapping.write_file(samba_mapping.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Bad User\n\n[share]\npath = /srv/share\nguest ok = yes\n")
	samba_mapping.run("systemctl restart samba")
	_assert(samba_mapping.run("smbclient //client/share -U Never -c ls").contains("report.txt"),"Samba Bad User maps unknown account to guest")
	samba_mapping.write_file(samba_mapping.state.config_path, "[global]\nserver role = standalone server\nmap to guest = Never\n\n[share]\npath = /srv/share\nguest ok = yes\n")
	samba_mapping.run("systemctl restart samba")
	_assert(samba_mapping.run("smbclient //client/share -U Never -c ls").contains("LOGON_FAILURE"),"Samba Never rejects unknown account")

	var log := FileAccess.open("user://v14-diagnostics.log", FileAccess.WRITE)
	if log:
		log.store_string("DIAGNOSTICS failures=%d cases=%d\n" % [failures.size(), Catalog.all().size()])
		for failure in failures: log.store_string("FAIL: %s\n" % failure)
		log.close()
	print("DIAGNOSTICS failures=", failures.size(), " cases=", Catalog.all().size(), " log=user://v14-diagnostics.log")
	for failure in failures: print("FAIL: ", failure)
	quit(1 if not failures.is_empty() else 0)
