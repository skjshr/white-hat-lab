extends RefCounted
## Pure projection of one already-recorded public diagnostic probe.
## This module never reads Game/VM state and never infers a PASS from transport.

static func project(probe: Dictionary) -> Dictionary:
	var recorded := bool(probe.get("recorded", false))
	var fresh := bool(probe.get("fresh", false))
	var output := str(probe.get("result", "")) if recorded else ""
	var command := str(probe.get("command", ""))
	var expectation := str(probe.get("expectation", ""))
	var protocol := _protocol(command)
	var payload: Dictionary = _payload(output) if recorded else {}
	var data: Dictionary = payload.get("data", {}) if payload.get("data", {}) is Dictionary else {}
	var source: Dictionary = payload.get("external_storage", {}).duplicate(true) if payload.get("external_storage", {}) is Dictionary else {}
	var status := _status(output, payload) if recorded else 0
	var expected_status := _expected_status(expectation)
	var actual_hash := _actual_hash(output, data) if recorded else ""
	var expected_hash := _expected_hash(expectation)
	var hash_match := "unknown"
	if not actual_hash.is_empty() and not expected_hash.is_empty():
		hash_match = "match" if actual_hash == expected_hash else "different"
	var rows: Array = []
	var specimen := "response"
	if data.get("orders", null) is Array:
		specimen = "orders"; rows = data.orders.duplicate(true)
	elif data.get("customers", null) is Array:
		specimen = "customers"; rows = data.customers.duplicate(true)
	elif protocol == "hash":
		specimen = "file"
	var error := str(payload.get("error", ""))
	if error.is_empty(): error = str(source.get("error", ""))
	var transport := _transport(protocol, output, status, recorded)
	var availability := _availability(protocol, output, status, payload, source, recorded)
	var network := _location(command, protocol)
	return {
		"recorded":recorded,
		"fresh":fresh,
		"passed":bool(probe.get("passed", false)),
		"protocol":protocol,
		"method":_method(command) if protocol == "http" else "",
		"host":str(network.get("host", "")),
		"path":str(network.get("path", "")),
		"status":status,
		"expected_status":expected_status,
		"transport":transport,
		"rule":_rule(output) if recorded else "",
		"error":error,
		"data":data.duplicate(true),
		"source":source,
		"hash":actual_hash,
		"expected_hash":expected_hash,
		"hash_match":hash_match,
		"availability":availability,
		"specimen":specimen,
		"rows":rows
	}

static func _protocol(command: String) -> String:
	var text := command.strip_edges().to_lower()
	if text.begins_with("curl "): return "http"
	if text.begins_with("smbclient "): return "smb"
	if text.begins_with("sha256sum "): return "hash"
	if text.begins_with("dig "): return "dns"
	return "command"

static func _payload(output: String) -> Dictionary:
	var body := output
	if "\n\n" in output: body = output.substr(output.find("\n\n") + 2)
	elif output.begins_with("HTTP/") and "\n" in output: body = output.substr(output.find("\n") + 1)
	if not body.strip_edges().begins_with("{"): return {}
	var parsed: Variant = JSON.parse_string(body)
	return parsed if parsed is Dictionary else {}

static func _method(command: String) -> String:
	# Match the guest VM's supported explicit -X method; default requests are GET.
	var matcher := RegEx.new()
	if matcher.compile("(?:^|\\s)-X\\s+['\"]?([A-Za-z]+)") == OK:
		var found := matcher.search(command)
		if found != null: return found.get_string(1).to_upper()
	return "GET"

static func _status(output: String, payload: Dictionary) -> int:
	var http := RegEx.new()
	if http.compile("(?m)^HTTP/\\d(?:\\.\\d)?\\s+(\\d{3})(?:\\s|$)") == OK:
		var found := http.search(output)
		if found != null: return int(found.get_string(1))
	var code: Variant = payload.get("code", 0)
	return int(code) if typeof(code) in [TYPE_INT, TYPE_FLOAT] else 0

static func _expected_status(expectation: String) -> int:
	for part in expectation.split("|", false):
		if not part.begins_with("status:"): continue
		var candidate := part.trim_prefix("status:")
		return int(candidate) if candidate.is_valid_int() else 0
	return 0

static func _is_sha256(value: String) -> bool:
	if value.length() != 64: return false
	for character in value.to_lower():
		if "0123456789abcdef".find(character) < 0: return false
	return true

static func _expected_hash(expectation: String) -> String:
	for part in expectation.split("|", false):
		var candidate := part.strip_edges()
		if _is_sha256(candidate): return candidate.to_lower()
	return ""

static func _actual_hash(output: String, data: Dictionary) -> String:
	var from_data := str(data.get("sha256", "")).to_lower()
	if _is_sha256(from_data): return from_data
	var first := output.strip_edges().get_slice(" ", 0).to_lower()
	return first if _is_sha256(first) else ""

static func _location(command: String, protocol: String) -> Dictionary:
	var result := {"host":"", "path":""}
	var url_matcher := RegEx.new()
	if url_matcher.compile("https?://([^/\\s'\"]+)(/[^\\s'\"]*)?") == OK:
		var url_match := url_matcher.search(command)
		if url_match != null:
			result.host = url_match.get_string(1)
			result.path = url_match.get_string(2).get_slice("?", 0)
			return result
	if protocol == "smb":
		var smb_matcher := RegEx.new()
		if smb_matcher.compile("//([^/\\s]+)/([^/\\s]+)") == OK:
			var smb_match := smb_matcher.search(command)
			if smb_match != null:
				result.host = smb_match.get_string(1)
				result.path = "/" + smb_match.get_string(2)
	elif protocol == "hash":
		var pieces := command.split(" ", false)
		if pieces.size() > 1:
			result.path = str(pieces[1]).trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
	elif protocol == "dns":
		for piece in command.split(" ", false):
			if not piece.begins_with("+") and not piece.begins_with("-") and piece != "dig":
				result.host = piece
	return result

static func _rule(output: String) -> String:
	var matcher := RegEx.new()
	if matcher.compile("FIREWALL_DENIED\\s+action=[^\\s]+\\s+rule=([^\\s]+)") != OK: return ""
	var found := matcher.search(output)
	return found.get_string(1) if found != null else ""

static func _transport(protocol: String, output: String, status: int, recorded: bool) -> String:
	if not recorded: return "unknown"
	if "FIREWALL_DENIED" in output: return "firewall"
	if protocol == "dns": return "dns"
	if "Could not resolve host" in output or "SERVFAIL" in output or "NXDOMAIN" in output: return "dns"
	if "CONNECTION_REFUSED" in output or "connection refused" in output.to_lower() or "Operation timed out" in output: return "unreachable"
	if status > 0 or output.contains("NT_STATUS_") or output.begins_with("putting file ") or output.begins_with("getting file "): return "replied"
	if protocol == "hash" or protocol == "command": return "local"
	return "unknown"

static func _availability(protocol: String, output: String, status: int, payload: Dictionary, source: Dictionary, recorded: bool) -> String:
	if not recorded: return "unknown"
	if protocol == "smb":
		if "NT_STATUS_ACCESS_DENIED" in output or "NT_STATUS_LOGON_FAILURE" in output: return "denied"
		if "NT_STATUS_BAD_NETWORK_NAME" in output or "NT_STATUS_CONNECTION_REFUSED" in output: return "unavailable"
		if output.begins_with("putting file ") and output.ends_with(": OK"): return "available"
		if output.begins_with("getting file ") and output.ends_with(": OK"): return "available"
		if "NT_STATUS_" not in output and not output.begins_with("putting file ") and not output.begins_with("getting file ") and not output.is_empty(): return "available"
		return "unknown"
	if protocol == "http":
		if status == 403 or status == 401: return "denied"
		if status >= 500: return "unavailable"
		if source.has("ok") and typeof(source.get("ok")) == TYPE_BOOL:
			if bool(source.ok): return "available"
			var source_code := int(source.get("code", 0))
			if source_code == 403: return "denied"
			if source_code == 503: return "unavailable"
			return "unknown"
		if status >= 200 and status < 500: return "available"
		return "unknown"
	if protocol == "dns":
		if "NOERROR" in output: return "available"
		if "SERVFAIL" in output or "NXDOMAIN" in output: return "unavailable"
		return "unknown"
	if protocol == "hash":
		return "available" if not _actual_hash(output, {}).is_empty() else "unavailable"
	if status == 403 or status == 401: return "denied"
	if status >= 500: return "unavailable"
	if status >= 200 and status < 500: return "available"
	return "unknown"
