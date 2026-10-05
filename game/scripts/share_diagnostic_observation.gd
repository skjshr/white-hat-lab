extends RefCounted
## Public command + saved response only. A directory listing never proves content.
## The acceptance verdict belongs to Game; it is separate from the observed stage.

static func tokens(command: String) -> Array[String]:
	# Same bounded quote grammar as the simulated guest, without constructing a VM.
	var result: Array[String] = []
	var word := ""
	var quote := ""
	for ch in command:
		if ch in ["\"", "'"]:
			if quote.is_empty(): quote = ch
			elif quote == ch: quote = ""
			else: word += ch
		elif ch in [" ", "\t"] and quote.is_empty():
			if not word.is_empty(): result.append(word); word = ""
		else: word += ch
	if not word.is_empty(): result.append(word)
	return result

static func sha256(value: String) -> bool:
	if value.length() != 64: return false
	for ch in value.to_lower():
		if not ch in "0123456789abcdef": return false
	return true

static func project(probe: Dictionary) -> Dictionary:
	var args := tokens(str(probe.get("command", "")))
	var v := {"protocol":"smb", "recorded":bool(probe.get("recorded", false)), "fresh":bool(probe.get("fresh", false)), "passed":bool(probe.get("passed", false)), "host":"", "path":"", "user":"guest", "method":"LS", "operation":"ls", "local_path":"", "remote_name":"", "transport":"unknown", "outcome":"unknown", "stop_at":"", "availability":"unknown", "files":[], "hash":"", "expected_hash":"", "hash_match":"unknown", "status":0, "expected_status":0, "rule":"", "error":"", "source":{}, "rows":[], "specimen":"file"}
	if args.is_empty(): return v
	if args[0] == "sha256sum":
		v.protocol = "hash"; v.method = "SHA256"; v.operation = "hash"
		if args.size() == 2: v.path = args[1]; v.local_path = args[1]
		var expected := str(probe.get("expectation", ""))
		if sha256(expected): v.expected_hash = expected.to_lower()
	else:
		var operation := "ls"
		for index in range(1, args.size()):
			var arg := args[index]
			if arg.begins_with("//"):
				var parts := arg.trim_prefix("//").split("/", false)
				if parts.size() == 2: v.host = parts[0]; v.path = "/" + parts[1]
			elif arg == "-U" and index + 1 < args.size(): v.user = args[index + 1].get_slice("%", 0)
			elif arg == "-c" and index + 1 < args.size(): operation = args[index + 1]
		var op := tokens(operation)
		if not op.is_empty(): v.operation = op[0]; v.method = op[0].to_upper()
		if op.size() >= 2:
			if op[0] == "put": v.local_path = op[1]; v.remote_name = op[2] if op.size() >= 3 else op[1].get_file()
			elif op[0] == "get": v.remote_name = op[1]; v.local_path = op[2] if op.size() >= 3 else ""
	if not bool(v.recorded): return v
	var output := str(probe.get("result", "")).strip_edges()
	if v.protocol == "hash":
		if output == "sha256sum: file missing":
			v.outcome = "file_missing"; v.stop_at = "local_file"; v.transport = "local"; v.availability = "unavailable"
		elif not str(v.path).is_empty() and output.length() > 66 and output.substr(64, 2) == "  " and sha256(output.left(64)) and output.substr(66) == str(v.path):
			v.hash = output.left(64).to_lower(); v.outcome = "hash_read"; v.transport = "local"; v.availability = "available"
			if not str(v.expected_hash).is_empty(): v.hash_match = "match" if v.hash == v.expected_hash else "different"
		return v
	var stages := {
		"NT_STATUS_ACCESS_DENIED":["access_denied", "operation", "denied"],
		"NT_STATUS_LOGON_FAILURE":["logon_failed", "identity", "unavailable"],
		"NT_STATUS_BAD_NETWORK_NAME":["share_missing", "share", "unavailable"],
		"NT_STATUS_CONNECTION_REFUSED: service is not running":["service_stopped", "share", "unavailable"],
		"smbclient: SMB service unavailable on this host":["service_stopped", "share", "unavailable"],
		"NT_STATUS_OBJECT_NAME_NOT_FOUND":["remote_missing", "specimen", "unavailable"],
		"NT_STATUS_OBJECT_PATH_NOT_FOUND":["path_missing", "specimen", "unavailable"],
		"NT_STATUS_INVALID_PARAMETER":["invalid_request", "request", "unknown"],
		"put: local file missing":["local_missing", "local_file", "unavailable"]}
	var stage_key := "NT_STATUS_INVALID_PARAMETER" if output.begins_with("NT_STATUS_INVALID_PARAMETER: ") else output
	if stages.has(stage_key):
		var stage: Array = stages[stage_key]
		v.outcome = stage[0]; v.stop_at = stage[1]; v.availability = stage[2]
		v.transport = "unreachable" if v.outcome == "service_stopped" else "local" if v.outcome == "local_missing" else "replied"
	elif str(v.operation) == "put" and not str(v.remote_name).is_empty() and output == "putting file " + str(v.remote_name) + ": OK":
		v.outcome = "written"; v.transport = "replied"; v.availability = "available"
	elif str(v.operation) == "get" and not str(v.remote_name).is_empty() and output == "getting file " + str(v.remote_name) + ": OK":
		v.outcome = "downloaded"; v.transport = "replied"; v.availability = "available"
	elif str(v.operation) == "ls" and not str(v.host).is_empty() and not str(v.path).is_empty():
		if output == "0 files": v.outcome = "listed"; v.files = []
		elif not output.is_empty():
			# Legacy responses are untyped. Recognize conservative file names;
			# prose, JSON, usage and unknown errors stay uninterpreted.
			var names: Array[String] = []
			var matcher := RegEx.new(); matcher.compile("^[\\p{L}\\p{N}_][\\p{L}\\p{N}_. -]*\\.[\\p{L}\\p{N}_-]+$")
			for line in output.split("\n", false):
				if matcher.search(line) == null: names.clear(); break
				names.append(line)
			if not names.is_empty(): v.outcome = "listed"; v.files = names
		if v.outcome == "listed": v.transport = "replied"; v.availability = "available"
	return v

static func caption(value: Dictionary) -> String:
	return str({"unknown":"未観測" if not bool(value.recorded) else "応答を特定できず", "listed":"一覧取得 · %d件" % value.files.size(), "written":"共有へ保存 ✓", "downloaded":"手元へ取得 ✓", "access_denied":"操作拒否 ×", "logon_failed":"認証失敗 ×", "share_missing":"共有先なし ×", "service_stopped":"共有サービス停止 ×", "remote_missing":"ファイルなし ×", "path_missing":"保存先なし ×", "local_missing":"手元のファイルなし ×", "invalid_request":"要求形式 ×", "file_missing":"手元のファイルなし ×", "hash_read":"原本と一致 ✓" if str(value.hash_match) == "match" else "原本と異なる ≠" if str(value.hash_match) == "different" else "照合値取得"}.get(str(value.outcome), "未観測"))
