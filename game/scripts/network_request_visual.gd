extends RefCounted
## Pure presentation of saved evidence. No machine access or inferred topology.

static func _node(title: String, state := "unknown", detail := "未確認") -> Dictionary:
	return {"title":title,"state":state,"detail":detail,"edge_state":state}

static func project(view: Dictionary, url: String) -> Dictionary:
	var status := str(view.get("status","unobserved"))
	var title := "会計データ" if "/accounting" in url else ("顧客データ" if "/customers" in url else "販売データ")
	var result := {"status":status,"complete":false,"summary":"未観測 · 検査で経路を確認", "dns":_node("名前解決"),"business":_node(title),"admin":_node("管理接続")}
	if status == "unobserved": return result
	if status == "stale":
		result.summary = "古い観測 · 再検査が必要"
		for id in ["dns","business","admin"]:
			result[id].state = "stale"; result[id].detail = "古い観測"; result[id].edge_state="stale"
		return result
	if status != "current": return result
	var outputs: Dictionary = view.get("outputs",{}) if view.get("outputs",{}) is Dictionary else {}
	var dns := str(outputs.get("dns-check",""))
	var business := str(outputs.get("request",""))
	var admin := str(outputs.get("admin-check",""))
	var business_code := _http_code(business)
	if dns.contains("status: NOERROR"):
		result.dns = _node("名前解決","pass","応答あり")
	elif _dns_failed(dns) or (business_code==0 and business.begins_with("curl:") and _dns_failed(business)):
		result.dns = _node("名前解決","fail","応答なし")
	if business_code==200:
		result.business = _node(title,"pass","HTTP 200")
	elif business_code>0:
		result.business = _node(title,"fail","データ不正 / 422" if business_code==422 else "HTTP "+str(business_code))
		result.business.edge_state="pass"
	elif business.begins_with("curl:") and _dns_failed(business):
		result.business = _node(title,"unreached","未到達")
	elif business.begins_with("curl:") and business.contains("FIREWALL_DENIED"):
		result.business = _node(title,"fail","通信拒否")
	elif business.begins_with("curl:"):
		var lower := business.to_lower()
		if "certificate" in lower or "ssl" in lower or "tls" in lower:
			result.business = _node(title,"fail","TLS 失敗")
		elif "refused" in lower or "timed out" in lower or "failed to connect" in lower:
			result.business = _node(title,"fail","接続失敗")
	if _http_code(admin)>0:
		result.admin = _node("管理接続","fail","応答あり")
		result.admin.edge_state="pass"
	elif admin.begins_with("curl:") and _dns_failed(admin):
		result.admin = _node("管理接続","unreached","遮断は未確認")
	elif admin.begins_with("curl:") and admin.contains("FIREWALL_DENIED"):
		result.admin = _node("管理接続","blocked","遮断")
	result.complete = bool(view.get("passed",false)) and result.dns.state=="pass" and result.business.state=="pass" and result.admin.state=="blocked"
	result.summary = "通信の実測 · 確認済" if result.complete else "通信の実測 · 未解決あり"
	return result

static func _dns_failed(output: String) -> bool:
	return output.contains("Could not resolve") or output.contains("status: SERVFAIL") or output.contains("status: NXDOMAIN") or output.contains("no servers could be reached")

static func _http_code(output: String) -> int:
	var first := output.get_slice("\n",0).strip_edges().split(" ",false)
	if first.size()<2 or str(first[0]) not in ["HTTP/1.0","HTTP/1.1","HTTP/2"]: return 0
	var code := str(first[1])
	return int(code) if code.length()==3 and code.is_valid_int() and int(code)>=100 and int(code)<=599 else 0
