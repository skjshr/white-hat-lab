class_name NextTaskGuide
extends RefCounted
## Read-only next action resolver. It only observes the game state and returns
## navigation metadata; it never accepts, edits, verifies, saves, or delivers.
const UI_COPY = preload("res://scripts/ui_theme.gd")

static func resolve(game) -> Dictionary:
	if game == null or game.state.is_empty(): return _item("none", "", "", "", "", "")
	var s: Dictionary = game.state
	if bool(_call(game, "current_done", [], false)):
		return _copy_item("done", "next_done_title", "next_done_body", "receipt", "GuideDeliver")
	if str(s.get("strategy", "")).is_empty() and not bool(s.get("career_mode", false)):
		return _copy_item("strategy", "guide_strategy_title", "guide_strategy_body", "board", "GuideStrategy_operations")
	if bool(s.get("career_mode", false)) and (bool(s.get("awaiting_contract", false)) or not bool(s.get("accepted", false))):
		return _copy_item("board", "next_board_title", "next_board_body", "board", "ContractBoard")
	if not bool(s.get("accepted", false)):
		return _copy_item("accept", "next_accept_title", "next_accept_body", "mail", "GuideMailMessage")
	if bool(_call(game, "advanced_active", [], false)):
		return _advanced(game)
	return _legacy(game)

static func _legacy(game) -> Dictionary:
	var s: Dictionary = game.state
	var supply := _supply_step(game)
	if not supply.is_empty(): return supply
	var info: Dictionary = game.vm_info()
	var machine = game._vm()
	var chapter: int = game._current_chapter()
	if not bool(info.get("connected", false)):
		if chapter == 0 and _has_console(game):
			return _copy_item("connect", "next_connect_title", "next_connect_body", "browser", "SambaConnect", {"url":_legacy_url(game)})
		return _copy_item("connect", "next_connect_title", "next_terminal_body", "terminal", "TerminalConnect")
	var service_error := str(machine.state.get("error", ""))
	if not service_error.is_empty():
		# A failed restart is already observed. Inspect only the saved syntax, not
		# hidden desired settings, so a repaired file leads back to Apply even
		# while the service retains its previous failure until that restart.
		var config_path := str(info.get("config_path", ""))
		var parsed := _dict_call(machine, "_parse_config", [game.vm_read(config_path)])
		var current_error := str(parsed.get("error", service_error))
		if not current_error.is_empty():
			return _copy_item("fix-config", "next_fix_title", "next_fix_body", "editor", "ConfigEditor", {"config_path":config_path,"hint":current_error + "\n" + UI_COPY.copy("next_fix_hint")})
		return _copy_item("apply", "guide_restart_title", "next_apply_body", "monitor", "ServiceRestart")
	var review: Dictionary = game.case_review()
	var optional_hint := UI_COPY.copy("next_optional_baseline") if bool(review.get("can_capture", false)) and not bool(review.get("current_recorded", false)) else ""
	if bool(machine.state.get("dirty", false)) and str(machine.state.get("error", "")).is_empty():
		return _copy_item("apply", "guide_restart_title", "next_apply_body", "monitor", "ServiceRestart", {"hint":UI_COPY.copy("next_diagnostic_hint")})
	if not bool(machine.state.get("active", true)) and str(machine.state.get("error", "")).is_empty():
		return _copy_item("apply", "guide_restart_title", "next_apply_body", "monitor", "ServiceRestart")
	# Only observed failures may direct a correction. Never inspect hidden desired
	# configuration to tell the player whether an unmeasured fix was correct.
	var probes: Array = game.diagnostic_probes()
	for probe in probes:
		if bool(probe.get("recorded", false)) and bool(probe.get("fresh", false)) and not bool(probe.get("passed", false)):
			return _optional(_fix(game, probe), optional_hint)
	var observed := probes.any(func(row): return bool(row.get("recorded", false)))
	# A successful Samba upload changes the file listing and invalidates prior
	# read evidence. Suggest the public write checks first so the player can
	# finish on the final file state without repeating the read checks. This
	# only selects a diagnostic; the player still runs every check explicitly.
	var observation_order := probes
	if chapter == 0 and int(machine.state.get("samba_model_version", 1)) >= 2:
		observation_order = probes.filter(func(row): return str(row.get("id", "")) in ["staff-write", "guest-write"])
		observation_order.append_array(probes.filter(func(row): return str(row.get("id", "")) not in ["staff-write", "guest-write"]))
	for probe in observation_order:
		if not bool(probe.get("recorded", false)) or not bool(probe.get("fresh", false)):
			var result := _copy_item("test" if observed else "investigate", "next_test_title" if observed else "next_investigate_title", "next_probe_body", "verify", "DiagnosticRun", {"probe_id":str(probe.get("id", "")), "hint":str(probe.get("description", "")) + "\n" + UI_COPY.copy("next_diagnostic_hint")})
			result.body += "  " + str(probe.get("label", ""))
			return _optional(result, optional_hint)
	# Verification can expose extra contract conditions that individual probes do
	# not cover. Surface those observed failures instead of looping on Verify.
	if int(s.get("validated_revision", -1)) == int(s.get("revision", 0)):
		for check in s.get("checks", []):
			if not bool(check.get("passed", false)) and not bool(check.get("hardware", false)):
				return _optional(_fix(game, check), optional_hint)
		var hardware: Dictionary = game._customer_hardware()
		if not hardware.is_empty() and str(hardware.get("status", "")) == "staged":
			return _copy_item("ship", "stock_dispatch", "next_ship_body", "office", "")
	if not _validated(game):
		return _optional(_copy_item("validate", "guide_validate_title", "next_validation_body", "verify", "DiagnosticValidate", {"hint":UI_COPY.copy("next_diagnostic_hint")}), optional_hint)
	return _completion_step(game)

static func _fix(game, probe: Dictionary) -> Dictionary:
	var route := "browser" if _has_console(game) else "editor"
	var description := str(probe.get("description", probe.get("label", "")))
	var lines := PackedStringArray([description, UI_COPY.copy("next_fix_hint")])
	for text in game.mission().get("hints", []):
		if text is String: lines.append(text)
	var result := _copy_item("fix", "next_fix_title", "next_fix_body", route, "SambaEdit_share" if game._current_chapter() == 0 and route == "browser" else "", {"hint":"\n".join(lines)})
	result.body += "  " + str(probe.get("label", ""))
	if route == "browser": result.url = _legacy_url(game)
	else: result.config_path = str(game.vm_info().get("config_path", ""))
	return result

static func _has_console(game) -> bool:
	var keys := ["samba_model_version", "backup_model_version", "firewall_model_version", "identity_model_version", "edr_model_version", "portal_model_version"]
	return int(game._vm().state.get(keys[game._current_chapter()], 1)) >= 2

static func _supply_step(game) -> Dictionary:
	var requirement: Dictionary = game._customer_requirement()
	if requirement.is_empty(): return {}
	var hardware: Dictionary = game._customer_hardware()
	var status := str(hardware.get("status", ""))
	if status in ["staged", "delivered"]: return {}
	if status in ["ready", "stored"]: return _copy_item("receive", "stock_stage", "next_receive_body", "office", "")
	if status == "shipping": return _copy_item("shipping", "stock_status_shipping", "next_shipping_body", "office", "")
	if status == "carried":
		var checks: Array = game.state.get("checks", [])
		var ready: bool = int(game.state.get("validated_revision", -1)) == int(game.state.get("revision", 0)) and not checks.is_empty() and checks.all(func(row): return bool(row.get("hardware", false)) or bool(row.get("passed", false)))
		return _copy_item("ship", "stock_dispatch", "next_ship_body", "office", "") if ready else _copy_item("receive", "stock_stage", "next_receive_body", "office", "")
	var matching: Array = game.customer_stock_units().filter(func(unit): return str(unit.get("sku", "")) == str(requirement.get("sku", "")) and str(unit.get("contract_id", "")).is_empty())
	for unit in matching:
		if str(unit.get("status", "")) in ["ready", "stored", "carried"]:
			return _copy_item("receive", "stock_stage", "next_receive_body", "office", "")
	if matching.any(func(unit): return str(unit.get("status", "")) == "queued"):
		return _copy_item("inbound", "stock_inbound", "next_inbound_body", "office", "")
	return _copy_item("procure", "stock_title", "next_buy_body", "shop", "StockTab")

static func _completion_step(game) -> Dictionary:
	var s: Dictionary = game.state
	var next_index := _next_target_index(s)
	if next_index >= 0:
		var result := _copy_item("site", "next_site_title", "next_site_body", "terminal", "TargetSelectorSlot", {"target_index":next_index})
		result.body += "  " + str(s.targets[next_index].get("name", ""))
		return result
	# Use the real delivery guard; colleague jobs and linked environments can
	# invalidate delivery even when retained check rows look complete.
	if game.can_deliver(): return _copy_item("deliver", "guide_deliver_title", "guide_deliver_body", "receipt", "GuideDeliver")
	var contract_id := str(s.get("current_contract_id", ""))
	for queue in s.get("dispatch_queues", {}).values():
		for job in queue:
			if str(job.get("kind", "normal")) == "normal" and str(job.get("contract_id", "")) == contract_id:
				return _copy_item("team", "dispatch_title", "next_team_body", "team", "")
	for job in game._assignments.values():
		if str(job.get("status", "")) == "working" and str(job.get("contract_id", "")) == contract_id:
			return _copy_item("team", "dispatch_title", "next_team_body", "team", "")
	return _copy_item("validate", "guide_validate_title", "next_validation_body", "verify", "DiagnosticValidate")

static func _advanced(game) -> Dictionary:
	var checks: Array = _array_call(game, "diagnostic_probes")
	var failed: Dictionary = {}
	for check in checks:
		if not bool(check.get("passed", false)):
			failed = check; break
	if failed.is_empty():
		if _validated(game):
			return _completion_step(game)
		if not _validated(game):
			return _copy_item("validate", "guide_validate_title", "adv_verify", "advanced", "AdvancedVerify")
	var label_key := str(failed.get("label_key", ""))
	var objective := UI_COPY.copy(label_key, UI_COPY.copy("next_workbench_body", ""))
	return _item("workbench", UI_COPY.copy("next_investigate_title"), UI_COPY.copy("next_workbench_body") + "  " + objective, objective, "advanced", "AdvancedTab_results", {"objective_id":str(failed.get("id", ""))})

static func _copy_item(id: String, title_key: String, body_key: String, route: String, target: String, extra: Dictionary = {}) -> Dictionary:
	var hint_key: String = {"fix":"next_failed_hint","test":"next_failed_hint","validate":"next_diagnostic_hint"}.get(id, "")
	var result := _item(id, UI_COPY.copy(title_key, ""), UI_COPY.copy(body_key, ""), UI_COPY.copy(hint_key, "") if not str(hint_key).is_empty() else "", route, target)
	result.merge(extra, true)
	return result

static func _item(id: String, title: String, body: String, hint: String, route: String, target: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"id":id,"title":title,"body":body,"hint":hint,"route":route,"target":target}
	result.merge(extra, true)
	return result

static func _validated(game) -> bool:
	var s: Dictionary = game.state
	if int(s.get("validated_revision", -1)) != int(s.get("revision", 0)): return false
	var checks: Array = s.get("checks", []) if s.get("checks", []) is Array else []
	return not checks.is_empty() and checks.all(func(row): return bool(row.get("passed", false)))

static func _next_target_index(s: Dictionary) -> int:
	var targets: Array = s.get("targets", [])
	var current := int(s.get("target_index", 0))
	for offset in range(1, targets.size()):
		var index: int = (current + offset) % targets.size()
		var target: Dictionary = targets[index]
		var checks: Array = target.get("checks", [])
		if not bool(target.get("inspected", false)) or int(target.get("validated_revision", -1)) != int(target.get("revision", 0)) or checks.is_empty() or checks.any(func(row): return not bool(row.get("passed", false))):
			return index
	return -1

static func _legacy_url(game) -> String:
	var chapter := int(_call(game, "_current_chapter", [], int(game.state.get("chapter", 0))))
	match clampi(chapter, 0, 5):
		0: return "https://files01.client.test:9090/file-sharing"
		1: return "http://backup.client.test:9898"
		2: return "https://gateway.client.test/firewall_rules.php"
		3: return "https://identity.client.test/admin/client/console/"
		4: return "https://edr.client.test/security/devices"
		_: return "https://portal.client.test/apps/files/"

static func _optional(result: Dictionary, hint: String) -> Dictionary:
	if not hint.is_empty():
		result.hint = (str(result.get("hint", "")) + "\n" + hint).strip_edges()
		result.optional_baseline = true
	return result

static func _dict_call(object, method: String, args: Array = []) -> Dictionary:
	var value = _call(object, method, args, {})
	return value if value is Dictionary else {}

static func _array_call(object, method: String, args: Array = []) -> Array:
	var value = _call(object, method, args, [])
	return value if value is Array else []

static func _array_method(object, method: String) -> Array:
	if object == null or not object.has_method(method): return []
	var value = object.call(method)
	return value if value is Array else []

static func _call(object, method: String, args: Array, fallback):
	if object == null or not object.has_method(method): return fallback
	return object.callv(method, args)
