extends RefCounted

## Controlled, reversible incident drift for the maintenance cadence.
## This module only changes one persisted VM target; Game owns when to call it.

const VM = preload("res://scripts/virtual_machine.gd")

static func introduce(targets: Array, incident_id: String) -> Dictionary:
	var original: Array = targets.duplicate(true)
	if targets.is_empty() or incident_id.strip_edges().is_empty():
		return {"targets":original,"target_index":-1,"kind":"","changed":false}
	var start := absi(incident_id.hash()) % targets.size()
	for offset in targets.size():
		var index := (start + offset) % targets.size()
		var candidate: Dictionary = targets[index] if targets[index] is Dictionary else {}
		var changed := _apply(candidate, incident_id)
		if bool(changed.get("changed", false)):
			var result := original
			result[index] = changed.target
			return {"targets":result,"target_index":index,"kind":str(changed.kind),"changed":true}
	return {"targets":original,"target_index":-1,"kind":"","changed":false}

static func _apply(candidate: Dictionary, incident_id: String) -> Dictionary:
	if not candidate.has("chapter") or not candidate.has("vm_state"):
		return {"changed":false}
	var chapter := int(candidate.get("chapter", -1))
	if chapter < 0 or chapter > 5:
		return {"changed":false}
	var raw_saved: Variant = candidate.get("vm_state", {})
	var raw_scenario: Variant = candidate.get("scenario", {})
	if not raw_saved is Dictionary or not raw_scenario is Dictionary:
		return {"changed":false}
	var saved: Dictionary = raw_saved.duplicate(true)
	if saved.is_empty() or saved.get("schema", 0) != 2 or not saved.get("fs") is Dictionary or not saved.get("applied") is Dictionary or not saved.get("dirs") is Array or not saved.get("snapshots") is Array or not saved.get("events") is Array:
		return {"changed":false}
	var machine = VM.new()
	machine.setup(chapter, saved, raw_scenario.duplicate(true))
	if not bool(machine.state.get("active", false)):
		return {"changed":false}
	var before: Dictionary = machine.state.applied.duplicate(true)
	var desired: Dictionary = raw_scenario.get("desired", {}) if raw_scenario.get("desired", {}) is Dictionary else {}
	var before_eval: Array = machine.evaluate()
	if before_eval.is_empty() or not before_eval.all(func(item): return bool(item)):
		return {"changed":false}
	var before_fingerprint := machine._fingerprint()
	var kind := ""
	var changed := false
	if chapter == 0:
		var guest_mode := str(before.get("guest", "none"))
		if desired.has("guest") and guest_mode != str(desired.guest): return {"changed":false}
		if guest_mode not in ["none", "read", "write"]: return {"changed":false}
		machine.run("ssh client")
		var samba_text := _samba_guest_drift(str(machine.state.fs.get(machine.state.config_path, "")), str(before.get("share_name", "share")), guest_mode == "none")
		if samba_text.is_empty() or not machine.write_file(str(machine.state.config_path), samba_text): return {"changed":false}
		kind = "share"; changed = true
	elif chapter == 1:
		if str(before.get("schedule", "off")) not in ["off", "daily"]: return {"changed":false}
		if desired.has("schedule") and str(before.schedule) != str(desired.schedule): return {"changed":false}
		var values: Dictionary = before.duplicate(true); values.schedule = "off" if str(values.schedule) == "daily" else "daily"
		machine.run("ssh client")
		if not machine.write_file(str(machine.state.config_path), machine.configuration_text(values)): return {"changed":false}
		kind = "backup"; changed = true
	elif chapter == 2:
		if str(before.get("business", "deny")) not in ["deny", "allow"]: return {"changed":false}
		if desired.has("business") and str(before.business) != str(desired.business): return {"changed":false}
		var values: Dictionary = before.duplicate(true); values.business = "deny" if str(values.business) == "allow" else "allow"
		machine.run("ssh client")
		if int(machine.state.get("firewall_model_version", 1)) >= 2:
			var rules: Array = values.get("rules", []).duplicate(true)
			var policy_changed := false
			for rule in rules:
				if str(rule.get("interface", "")) != "lan" or str(rule.get("destination", "")) != "192.0.2.20/32": continue
				if str(rule.get("destination_port", "")) not in ["80", "443"] and int(rule.get("destination_port", -1)) not in [80,443]: continue
				rule.action = "pass" if str(values.business) == "allow" else "block"
				policy_changed = true
			if not policy_changed: return {"changed":false}
			values.rules = rules
		if not machine.write_file(str(machine.state.config_path), machine.configuration_text(values)): return {"changed":false}
		kind = "network"; changed = true
	elif chapter == 3:
		var current := str(before.get("current", "disabled"))
		if current not in ["active", "disabled"]: return {"changed":false}
		if desired.has("current") and current != str(desired.current): return {"changed":false}
		machine.run("ssh client")
		if int(machine.state.get("identity_model_version", 1)) >= 2:
			var result: Variant = JSON.parse_string(machine.run("identity enable current " + ("off" if current == "active" else "on")))
			if not result is Dictionary or not bool(result.get("ok", false)): return {"changed":false}
		else:
			var values: Dictionary = before.duplicate(true); values.current = "disabled" if current == "active" else "active"
			if not machine.write_file(str(machine.state.config_path), machine.configuration_text(values)): return {"changed":false}
		kind = "account"; changed = true
	elif chapter == 4:
		var endpoint := ""
		var values: Dictionary = before.duplicate(true)
		if str(before.get("pc_a", "connected")) == "isolated" and (not desired.has("pc_a") or str(before.pc_a) == str(desired.pc_a)):
			endpoint = "pc_a"; values.pc_a = "connected"
		elif str(before.get("pc_b", "connected")) == "connected" and (not desired.has("pc_b") or str(before.pc_b) == str(desired.pc_b)):
			endpoint = "pc_b"; values.pc_b = "isolated"
		elif str(before.get("pc_b", "connected")) == "isolated" and (not desired.has("pc_b") or str(before.pc_b) == str(desired.pc_b)):
			endpoint = "pc_b"; values.pc_b = "connected"
		else: return {"changed":false}
		machine.run("ssh client")
		if not machine.write_file(str(machine.state.config_path), machine.configuration_text(values)): return {"changed":false}
		kind = "incident"; changed = true
	elif chapter == 5:
		if str(before.get("audit", "off")) not in ["off", "on"]: return {"changed":false}
		if desired.has("audit") and str(before.audit) != str(desired.audit): return {"changed":false}
		var values: Dictionary = before.duplicate(true); values.audit = "off" if str(values.audit) == "on" else "on"
		machine.run("ssh client")
		if not machine.write_file(str(machine.state.config_path), machine.configuration_text(values)): return {"changed":false}
		kind = "portal"; changed = true
	if not changed: return {"changed":false}
	var restart := machine.run("systemctl restart " + str(machine.state.service))
	if not restart.contains("active (running)"):
		return {"changed":false}
	var after_eval: Array = machine.evaluate()
	var after_fingerprint := machine._fingerprint()
	if after_eval.is_empty() or after_eval.all(func(item): return bool(item)) or after_fingerprint == before_fingerprint:
		return {"changed":false}
	# The write/restart already advanced mutation; this is only an audit event.
	machine.state.events.append("%04d maintenance incident=%s kind=%s target=%s" % [int(machine.state.mutation),incident_id,kind,str(candidate.get("vm_key", ""))])
	if machine.state.events.size() > 80: machine.state.events.pop_front()
	var updated := candidate.duplicate(true)
	updated.vm_state = machine.export_state()
	return {"changed":true,"kind":kind,"target":updated}

static func _samba_guest_drift(text: String, target_share: String, introduce_guest: bool) -> String:
	var lines := text.split("\n", true)
	var section := ""
	var in_share := false
	var share_found := false
	var share_end := lines.size()
	var seen_guest := false
	var seen_available := false
	var seen_valid := false
	var seen_invalid := false
	var seen_write := false
	for i in lines.size():
		var raw := str(lines[i]); var trimmed := raw.strip_edges()
		if trimmed.begins_with("[") and trimmed.ends_with("]"):
			if in_share: share_end = i
			section = trimmed.substr(1, trimmed.length() - 2).strip_edges().to_lower()
			in_share = section == target_share.strip_edges().to_lower()
			if in_share: share_found = true
			continue
		if not in_share or trimmed.is_empty() or trimmed.begins_with("#") or trimmed.begins_with(";"): continue
		var cut := trimmed.find("=")
		if cut < 1: continue
		var key := trimmed.left(cut).strip_edges().to_lower().replace(" ", "").replace("\t", "")
		var value := trimmed.substr(cut + 1).strip_edges()
		if key == "available":
			if introduce_guest: lines[i] = raw.left(raw.find("=") + 1) + " yes"
			seen_available = true
		elif key == "guestok": lines[i] = raw.left(raw.find("=") + 1) + (" yes" if introduce_guest else " no"); seen_guest = true
		elif key == "validusers":
			seen_valid = true
			var users: Array = Array(value.replace(",", " ").split(" ", false))
			if introduce_guest and "nobody" not in users: users.append("nobody")
			if not introduce_guest: users = users.filter(func(user): return str(user) != "nobody")
			lines[i] = raw.left(raw.find("=") + 1) + " " + " ".join(users)
		elif key == "invalidusers":
			seen_invalid = true
			var invalid: Array = Array(value.replace(",", " ").split(" ", false))
			invalid = invalid.filter(func(user): return str(user) != "nobody")
			lines[i] = raw.left(raw.find("=") + 1) + " " + " ".join(invalid)
		elif key == "writelist":
			seen_write = true
			var writers: Array = Array(value.replace(",", " ").split(" ", false))
			writers = writers.filter(func(user): return str(user) != "nobody")
			lines[i] = raw.left(raw.find("=") + 1) + " " + " ".join(writers)
	if not share_found: return ""
	if introduce_guest and not seen_available: lines.insert(share_end, "    available = yes")
	if not seen_guest: lines.insert(share_end, "    guest ok = " + ("yes" if introduce_guest else "no"))
	return "\n".join(lines)
