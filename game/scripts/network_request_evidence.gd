extends RefCounted
## A saved measurement of one business request. Rendering never executes probes.

static func request(url: String) -> Dictionary:
	var scheme := url.get_slice("://", 0)
	if scheme not in ["http", "https"] or url.contains("?") or url.contains("#"): return {}
	var address := url.get_slice("://", 1)
	var authority := address.get_slice("/", 0)
	if authority not in ["intranet.client.test", "intranet.client.test:443", "intranet.client.test:80"]: return {}
	var path := address.substr(authority.length()).trim_suffix("/")
	if path not in ["", "/sales", "/customers", "/accounting"]: return {}
	var resource := "ledger" if path == "/accounting" else ("customers" if path == "/customers" else "orders")
	return {"url":url, "resource":resource, "request_url":scheme+"://"+authority+"/api/business/"+resource}

static func project(record: Dictionary, context: String, url: String, fingerprint: String) -> Dictionary:
	if record.is_empty() or str(record.get("context", "")) != context or str(record.get("url", "")) != url:
		return {"status":"unobserved", "rows":[], "passed":false}
	var fresh := str(record.get("fingerprint", "")) == fingerprint
	var result := record.duplicate(true)
	result.status = "current" if fresh else "stale"
	result.passed = fresh and bool(record.get("passed", false))
	return result

static func rows(outputs: Dictionary) -> Array:
	var dns := str(outputs.get("dns-check", ""))
	var business := str(outputs.get("request", ""))
	var admin := str(outputs.get("admin-check", ""))
	var admin_reached := not admin.contains("Could not resolve")
	var admin_blocked := admin_reached and admin.contains("FIREWALL_DENIED")
	return [
		{"id":"dns", "label":"名前解決", "passed":dns.contains("status: NOERROR"), "detail":"応答あり" if dns.contains("status: NOERROR") else "名前解決に失敗", "output":dns},
		{"id":"business", "label":"同じ業務データ", "passed":business.begins_with("HTTP/1.1 200 "), "detail":"HTTP 200 / データを取得" if business.begins_with("HTTP/1.1 200 ") else ("HTTP応答なし" if business.begins_with("curl:") else business.get_slice("\n",0)), "output":business},
		{"id":"admin", "label":"外部からの管理接続", "passed":admin_blocked, "detail":"管理接続を遮断" if admin_blocked else ("名前解決で停止 / 遮断は未確認" if not admin_reached else "管理接続の遮断を確認できません"), "output":admin}
	]
