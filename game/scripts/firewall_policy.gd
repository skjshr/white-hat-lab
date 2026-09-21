extends RefCounted

## Bounded chapter-2 firewall policy model.
## The policy is intentionally a small game format, not a native firewall export.

const VERSION := 2
const LAN_NETWORK := "192.168.10.0/24"
const LAN_ADDRESS := "192.168.10.1"
const WAN_ADDRESS := "198.51.100.1"
const BUSINESS_ADDRESS := "192.0.2.20"
const STAFF_ADDRESS := "192.168.10.10"
const EXTERNAL_ADDRESS := "203.0.113.10"
const ADMIN_ADDRESS := "198.51.100.1"

static func _rule_defaults() -> Dictionary:
	return {"id":"","interface":"lan","action":"block","protocol":"any","source":"any","source_port":"any","destination":"any","destination_port":"any","disabled":false,"log":false,"description":""}

static func default_rules(values: Dictionary = {}) -> Array:
	var dns_rule := _rule_defaults()
	dns_rule.id = "lan-dns"
	dns_rule.interface = "lan"
	dns_rule.action = "pass"
	dns_rule.protocol = "udp"
	dns_rule.source = "lan_net"
	dns_rule.destination = "self"
	dns_rule.destination_port = 53
	dns_rule.description = "LAN DNS"
	var business_rule := _rule_defaults()
	business_rule.id = "lan-business"
	business_rule.interface = "lan"
	business_rule.action = "pass" if str(values.get("business", "allow")) == "allow" else "block"
	business_rule.protocol = "tcp"
	business_rule.source = "lan_net"
	business_rule.destination = BUSINESS_ADDRESS + "/32"
	business_rule.destination_port = 443
	business_rule.description = "Business HTTPS"
	var business_http := business_rule.duplicate(true)
	business_http.id = "lan-business-http"
	business_http.destination_port = 80
	business_http.description = "Business HTTP"
	var admin_rule := _rule_defaults()
	admin_rule.id = "wan-admin"
	admin_rule.interface = "wan"
	admin_rule.action = "pass" if str(values.get("admin_public", "deny")) == "allow" else "block"
	admin_rule.protocol = "tcp"
	admin_rule.source = "any"
	admin_rule.destination = "self"
	admin_rule.destination_port = 8443
	admin_rule.description = "WAN management"
	return [dns_rule, business_rule, business_http, admin_rule]

static func configuration_text(values: Dictionary = {}) -> String:
	var policy := {"version":VERSION,"dns":str(values.get("dns", "off")),"tls":str(values.get("tls", "off")),"rules":[]}
	if values.has("rules") and values.rules is Array:
		policy.rules = values.rules.duplicate(true)
	else:
		policy.rules = default_rules(values)
	var checked := parse_config(JSON.stringify(policy))
	if not str(checked.get("error", "")).is_empty():
		# Preserve invalid caller data for the editor/restart error path; never
		# replace a customer's draft with a healthy default policy.
		return JSON.stringify(policy, "\t") + "\n"
	return canonical_text(checked.get("values", {}))

static func canonical_text(policy: Dictionary) -> String:
	var out := {"version":VERSION,"dns":str(policy.get("dns", "off")),"tls":str(policy.get("tls", "off")),"rules":policy.get("rules", []).duplicate(true)}
	return JSON.stringify(out, "\t") + "\n"

static func parse_config(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK: return {"error":"invalid_json","values":{}}
	var parsed: Variant = parser.data
	if not parsed is Dictionary: return {"error":"invalid_json","values":{}}
	if int(parsed.get("version", 0)) != VERSION: return {"error":"invalid_version","values":{}}
	if str(parsed.get("dns", "")) not in ["off", "on"]: return {"error":"invalid_dns","values":{}}
	if str(parsed.get("tls", "")) not in ["off", "on"]: return {"error":"invalid_tls","values":{}}
	if not parsed.get("rules", null) is Array: return {"error":"invalid_rules","values":{}}
	var rules: Array = []
	var seen := {}
	for item in parsed.rules:
		if not item is Dictionary: return {"error":"invalid_rule","values":{}}
		var checked := normalize_rule(item)
		if not bool(checked.get("ok", false)): return {"error":str(checked.get("error", "invalid_rule")),"values":{}}
		var rule: Dictionary = checked.rule
		if seen.has(str(rule.id)): return {"error":"duplicate_rule_id","values":{}}
		seen[rule.id] = true
		rules.append(rule)
	var values := {"version":VERSION,"dns":str(parsed.dns),"tls":str(parsed.tls),"rules":rules}
	var compatibility := computed_services(values)
	values.merge(compatibility, true)
	return {"error":"","values":values}

static func normalize_rule(raw: Dictionary) -> Dictionary:
	var allowed := ["id","interface","action","protocol","source","source_port","destination","destination_port","disabled","log","description"]
	for key in raw.keys():
		if str(key) not in allowed: return {"ok":false,"error":"unknown_rule_field"}
	var rule := _rule_defaults()
	for key in rule.keys():
		if raw.has(key): rule[key] = raw[key]
	var id := str(rule.id).strip_edges()
	if id.is_empty() or id.length() > 40 or not _safe_id(id): return {"ok":false,"error":"invalid_rule_id"}
	rule.id = id
	if str(rule.interface) not in ["wan", "lan"]: return {"ok":false,"error":"invalid_interface"}
	if str(rule.action) not in ["pass", "block", "reject"]: return {"ok":false,"error":"invalid_action"}
	if str(rule.protocol) not in ["any", "tcp", "udp", "tcp_udp", "icmp"]: return {"ok":false,"error":"invalid_protocol"}
	for key in ["source", "destination"]:
		var endpoint := str(rule[key]).strip_edges()
		if not _valid_endpoint(endpoint): return {"ok":false,"error":"invalid_endpoint"}
		rule[key] = endpoint
	for key in ["source_port", "destination_port"]:
		var port := _normalize_port(rule[key])
		if not bool(port.get("ok", false)): return {"ok":false,"error":"invalid_port"}
		rule[key] = port.value
	if str(rule.protocol) in ["icmp"] and (str(rule.source_port) != "any" or str(rule.destination_port) != "any"): return {"ok":false,"error":"icmp_ports_not_allowed"}
	if not (rule.disabled is bool) or not (rule.log is bool): return {"ok":false,"error":"invalid_boolean"}
	rule.disabled = rule.disabled
	rule.log = rule.log
	rule.description = str(rule.description)
	if rule.description.length() > 52: return {"ok":false,"error":"description_too_long"}
	return {"ok":true,"rule":rule}

static func _safe_id(value: String) -> bool:
	for ch in value:
		if not (ch == "_" or ch == "-" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")): return false
	return true

static func _valid_endpoint(value: String) -> bool:
	if value in ["any", "lan_net", "self"]: return true
	var ip := value
	var bits := 32
	if "/" in value:
		if value.count("/") != 1: return false
		ip = value.get_slice("/", 0)
		var suffix := value.get_slice("/", 1)
		if not _digits_only(suffix): return false
		bits = int(suffix)
	if bits < 0 or bits > 32 or not _valid_ipv4(ip): return false
	return true

static func _valid_ipv4(value: String) -> bool:
	var parts := value.split(".", false)
	if parts.size() != 4: return false
	for part in parts:
		if not _digits_only(part) or int(part) < 0 or int(part) > 255: return false
	return true

static func _digits_only(value: String) -> bool:
	if value.is_empty(): return false
	for ch in value:
		if ch < "0" or ch > "9": return false
	return true

static func _normalize_port(value: Variant) -> Dictionary:
	if value is int:
		var port := int(value)
		return {"ok":port >= 0 and port <= 65535,"value":port}
	if value is float:
		if value != floor(value): return {"ok":false}
		var float_port := int(value)
		return {"ok":float_port >= 0 and float_port <= 65535,"value":float_port}
	var text := str(value).strip_edges()
	if text == "any": return {"ok":true,"value":"any"}
	if ":" in text:
		if text.count(":") != 1: return {"ok":false}
		var left := text.get_slice(":", 0); var right := text.get_slice(":", 1)
		if not _digits_only(left) or not _digits_only(right): return {"ok":false}
		var first := int(left); var last := int(right)
		return {"ok":first >= 0 and last <= 65535 and first <= last,"value":"%d:%d" % [first,last]}
	if not _digits_only(text): return {"ok":false}
	var single := int(text)
	return {"ok":single >= 0 and single <= 65535,"value":single}

static func computed_services(policy: Dictionary) -> Dictionary:
	var business := evaluate(policy, "lan", STAFF_ADDRESS, BUSINESS_ADDRESS, "tcp", 40000, 443)
	var admin := evaluate(policy, "wan", EXTERNAL_ADDRESS, ADMIN_ADDRESS, "tcp", 40000, 8443)
	return {"business":"allow" if str(business.get("action", "block")) == "pass" else "deny","admin_public":"allow" if str(admin.get("action", "block")) == "pass" else "deny"}

static func evaluate(policy: Dictionary, interface_name: String, source: String, destination: String, protocol: String, source_port: int, destination_port: int) -> Dictionary:
	if interface_name not in ["wan", "lan"]: return {"action":"block","rule_id":"default","logged":false}
	var rules: Array = policy.get("rules", []) if policy is Dictionary else []
	for item in rules:
		if not item is Dictionary or bool(item.get("disabled", false)): continue
		if str(item.get("interface", "")) != interface_name: continue
		if not _protocol_matches(str(item.get("protocol", "any")), protocol): continue
		if not _endpoint_matches(str(item.get("source", "any")), source, interface_name): continue
		if not _endpoint_matches(str(item.get("destination", "any")), destination, interface_name): continue
		if not _port_matches(item.get("source_port", "any"), source_port) or not _port_matches(item.get("destination_port", "any"), destination_port): continue
		return {"action":str(item.get("action", "block")),"rule_id":str(item.get("id", "")),"logged":bool(item.get("log", false))}
	return {"action":"block","rule_id":"default","logged":false}

static func _protocol_matches(rule_protocol: String, actual: String) -> bool:
	if rule_protocol == "any": return true
	if rule_protocol == "tcp_udp": return actual in ["tcp", "udp"]
	return rule_protocol == actual

static func _endpoint_matches(rule_endpoint: String, actual: String, interface_name: String) -> bool:
	if rule_endpoint == "any": return true
	if rule_endpoint == "lan_net": return _in_cidr(actual, LAN_NETWORK)
	if rule_endpoint == "self": return actual in [LAN_ADDRESS, WAN_ADDRESS]
	return _in_cidr(actual, rule_endpoint)

static func _port_matches(rule_port: Variant, actual: int) -> bool:
	if str(rule_port) == "any": return true
	var text := str(rule_port)
	if ":" in text: return actual >= int(text.get_slice(":",0)) and actual <= int(text.get_slice(":",1))
	return actual == int(rule_port)

static func _in_cidr(actual: String, network: String) -> bool:
	if not _valid_ipv4(actual): return false
	var ip_parts := actual.split(".", false)
	var base := network.get_slice("/", 0)
	var bits := int(network.get_slice("/", 1)) if "/" in network else 32
	if not _valid_ipv4(base): return false
	var ip_num := _ip_number(ip_parts)
	var base_num := _ip_number(base.split(".", false))
	var mask := 0 if bits == 0 else (0xffffffff << (32 - bits)) & 0xffffffff
	return (ip_num & mask) == (base_num & mask)

static func _ip_number(parts: Array) -> int:
	return (int(parts[0]) << 24) | (int(parts[1]) << 16) | (int(parts[2]) << 8) | int(parts[3])
