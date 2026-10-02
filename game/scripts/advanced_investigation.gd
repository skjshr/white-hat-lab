extends RefCounted

# Offline, serializable investigations. Views contain observations, never the
# private answer model. Legacy files are migrated on a copy for read-only views.
const LIMIT := 96

static func upgrade(s: Dictionary) -> void:
	if int(s.get("investigation_version", 0)) >= 2: return
	s.investigation_version = 2
	s["sequence"] = int(s.get("sequence",0))
	s["observations"] = s.get("observations",[])
	s["evidence"] = s.get("evidence",{})
	s["migration_notice"] = "旧版の原記録・実設定を保持しました。受入確認には原記録の照合と現在の状態での試験が必要です。" if int(s.get("revision",0))>0 else ""
	var w: Dictionary = s.world
	if s.kind == "advanced-hunt":
		w["links"] = []
		w["change_revision"] = 0
		w["measurements"] = {}
		w["work_orders"] = [{"id":"CHG-114","time":"02:00–02:10","account":"backup-agent","host":"backup01","task":"task-backup","path":"/srv/data","detail":"別拠点退避。日報・会計の読み取りと、業務端末の接続を継続する。"}]
		for i in s.events.size():
			var e: Dictionary = s.events[i]
			if str(e.get("id", "")).begins_with("evt-"):
				e["source"] = ["gateway","endpoint","fileserver"][i % 3]
				e["kind"] = "telemetry"
				e["account"] = str(w.sessions.get(str(e.get("session", "")), {}).get("account", ""))
				e["hash"] = _canonical_event(e).sha256_text()
				if bool(e.get("pinned",false)): s.evidence[str(e.id)]=e.duplicate(true)
	elif s.kind == "advanced-pentest":
		w["files"] = w.get("files", {}).duplicate(true)
		w.files["share01/daily.csv"] = "date,total\n2026-10-01,12800\n"
		w.files["share01/README.txt"] = "社員の日報共有です。daily.csv は日次集計、deploy.env は配置時の設定です。\n"
		w.files["evidence/README.txt"] = "この領域はレポートサービス専用です。CSV は架空の診断用データです。\n"
		w["principal"] = str(w.get("principal","employee01"))
		w["authenticated_epoch"] = 0
		w["credential_epoch"] = 1
		w["known"] = ["share01", "evidence"]
		w["report"] = {}
		w["fixed"] = bool(w.get("grant_fixed", false))
		w["change_revision"] = 0
		w["retests"] = {}
	else:
		w["sessions"] = w.get("sessions",{"sid-admin-03":{"account":"restore-operator","device":"console01","active":true},"sid-sync-17":{"account":"restore-operator","device":"ws17","active":true}})
		w["credential_epoch"] = 1 if bool(w.get("identity",{}).get("compromised",true)) else 2
		w["change_revision"] = 0
		w["business_test"] = {}
		w["stage_revision"] = int(w.get("stage_revision", 0))
		w["reference"] = [{"id":"001","amount":100}]
		w["service_results"] = []
		w["published_revision"] = -1
		w["services"] = w.get("services",{"identity":false,"database":false,"app":false})
		# Earlier scans were hash-only. Keep them for audit without pretending they
		# are a parsed current ledger inspection.
		if w.has("scan") and not w.scan.has("rows"): w["legacy_scan"]=w.scan.duplicate(true); w.scan={}

static func _canonical_event(e: Dictionary) -> String:
	var copy: Dictionary = e.duplicate(true)
	copy.erase("pinned"); copy.erase("hash")
	return JSON.stringify(copy)

static func _result(ok: bool, message: String, changed: bool = false, data: Dictionary = {}, minutes: float = 0.0) -> Dictionary:
	return {"ok":ok,"changed":changed,"minutes":minutes,"message":message,"data":data.duplicate(true)}

static func _log(s: Dictionary, operation: String, target: String, status: int, data: Dictionary) -> Dictionary:
	s.sequence = int(s.sequence) + 1
	var row := {"id":"obs-%d" % int(s.sequence),"sequence":int(s.sequence),"operation":operation,"target":target,"status":status,"data":data.duplicate(true)}
	s.observations.append(row)
	while s.observations.size() > LIMIT: s.observations.pop_front()
	return row

static func _observe(s: Dictionary, op: String, target: String, status: int, data: Dictionary, message: String) -> Dictionary:
	var row := _log(s, op, target, status, data)
	return _result(status < 400, message, true, {"record":row}, 0)

static func _lookup(s: Dictionary, id: String) -> Dictionary:
	if s.evidence.has(id): return s.evidence[id]
	for row in s.get("observations", []):
		if str(row.id) == id: return row
	for row in s.get("events", []):
		if str(row.get("id", "")) == id and str(row.get("kind", "")) == "telemetry": return row
	if s.kind == "advanced-hunt":
		for row in s.world.work_orders:
			if str(row.id) == id: return row
	return {}

static func _pin(s: Dictionary, id: String) -> Dictionary:
	if s.evidence.has(id): return _result(true, "保存済みの根拠です。")
	var row := _lookup(s, id)
	if row.is_empty(): return _result(false, "観測した記録を選んでください。")
	if s.evidence.size() >= 24: return _result(false, "根拠は 24 件までです。不要な記録を外してください。")
	s.evidence[id] = row.duplicate(true)
	return _result(true, "原記録を保存しました。", true)

static func _valid_args(args: Dictionary) -> bool:
	if JSON.stringify(args).length() > 20000: return false
	for key in args:
		if not key is String and not key is StringName: return false
		if args[key] is Object or args[key] is Callable: return false
	return true

static func act(s: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	upgrade(s)
	if not _valid_args(args): return _result(false, "入力が大きすぎるか、形式が不正です。")
	var target: String = str(args.get("target", args.get("option", "")))
	if args.has("option") and not str(args.option).is_empty(): target = str(args.option)
	var result: Dictionary
	if action in ["pin", "pin_event", "preserve_evidence"]: result = _pin(s, target)
	elif action == "unpin":
		if s.kind == "advanced-pentest" and target in s.world.report.get("evidence", {}).keys(): return _result(false, "提出済みの根拠は保持されます。")
		var existed: bool = s.evidence.has(target)
		s.evidence.erase(target)
		result = _result(true, "根拠から外しました。", existed)
	elif s.kind == "advanced-hunt": result = _hunt(s, action, args, target)
	elif s.kind == "advanced-pentest": result = _pentest(s, action, args, target)
	else: result = _recovery(s, action, args, target)
	if bool(result.get("changed", false)):
		s.revision = int(s.get("revision", 0)) + 1
		s.last_result = result.duplicate(true)
	return result

static func _hunt(s: Dictionary, action: String, args: Dictionary, target: String) -> Dictionary:
	var w: Dictionary = s.world
	if action == "correlate" or action.begins_with("correlate_"):
		var ids = args.get("event_ids", [])
		if not ids is Array or ids.size() < 2 or ids.size() > 6: return _result(false, "照合する原記録を 2〜6 件選んでください。")
		var rows: Array = []; var unique: Array = []; var sources: Array = []; var sid := ""
		for id in ids:
			if not id is String or id in unique: return _result(false, "異なる原記録を選んでください。")
			var row := _lookup(s, id)
			if row.get("kind", "") != "telemetry": return _result(false, "原テレメトリ以外は照合できません。")
			if sid.is_empty(): sid = str(row.session)
			if str(row.session) != sid: return _observe(s, "correlate", "", 422, {"event_ids":ids}, "接続 ID が異なります。同じ接続という仮説はこの記録では成立しません。")
			unique.append(id); rows.append(row.duplicate(true))
			if not str(row.source) in sources: sources.append(str(row.source))
		if sources.size() < 2: return _result(false, "異なる収集元の記録を照合してください。")
		var link := {"session":sid,"event_ids":unique,"sources":sources,"records":rows}
		if w.links.any(func(x): return x.event_ids == unique): return _result(true, "同じ照合は保存済みです。")
		w.links.append(link)
		while w.links.size()>24: w.links.pop_front()
		return _observe(s, "correlate", sid, 200, link, "時刻・接続・収集元を結び付けました。作業予定と照合してください。")
	if action in ["probe_security", "probe_business", "restore_business"]:
		var security := action == "probe_security"
		var steps: Array = []
		if security:
			for sid in w.sessions:
				var session: Dictionary = w.sessions[sid]
				var host: String = str(session.host)
				var allowed: bool = bool(session.active) and bool(w.assets.get(host, {}).get("connected", false)) and bool(w.assets.fs02.connected)
				steps.append({"target":sid,"operation":"接続による読取","allowed":allowed})
			for task_id in w.tasks:
				var task: Dictionary = w.tasks[task_id]
				steps.append({"target":task_id,"operation":"定期処理の実行","allowed":bool(task.enabled) and bool(w.assets.get(str(task.host), {}).get("connected", false)) and bool(w.assets.fs02.connected)})
		else:
			for host in w.assets: steps.append({"target":host,"operation":"業務接続","allowed":bool(w.assets[host].connected)})
			steps.append({"target":"sid-b21","operation":"承認済み退避の接続","allowed":bool(w.sessions["sid-b21"].active)})
			steps.append({"target":"task-backup","operation":"承認済み退避の実行","allowed":bool(w.tasks["task-backup"].enabled)})
		var key := "security" if security else "business"
		w.measurements[key] = {"revision":int(w.change_revision),"steps":steps}
		return _observe(s, action, "", 200, w.measurements[key], "実際の接続結果を記録しました。")
	var collection := ""; var field := ""; var value := false
	if action in ["isolate_host", "reconnect_host"]: collection = "assets"; field = "connected"; value = action == "reconnect_host"
	elif action in ["revoke_session", "restore_session"]: collection = "sessions"; field = "active"; value = action == "restore_session"
	elif action in ["disable_task", "enable_task"]: collection = "tasks"; field = "enabled"; value = action == "enable_task"
	if collection.is_empty(): return _result(false, "対象を選択して操作してください。")
	if not w[collection].has(target): return _result(false, "対象が存在しません。")
	if bool(w[collection][target][field]) == value: return _result(true, "対象は既にこの状態です。")
	w[collection][target][field] = value
	w.change_revision = int(w.change_revision) + 1
	_log(s, action, target, 200, {field:value})
	return _result(true, "対象の状態を変更しました。業務への影響を再確認してください。", true, {}, 2)

static func _resource_path(value: Variant) -> String:
	if not value is String or value.length() > 160: return "!invalid"
	var path: String = value.strip_edges().trim_prefix("/").trim_suffix("/")
	if ".." in path.split("/") or "\\" in path or "\n" in path or ":" in path: return "!invalid"
	return path

static func _network_access(w: Dictionary, principal: String, path: String) -> bool:
	if principal == "employee01": return path == "share01" or (path.begins_with("share01/") and (not bool(w.fixed) or path != "share01/deploy.env"))
	if principal == "svc-report": return path == "evidence" or path.begins_with("evidence/")
	return false

static func _network_record(s: Dictionary, op: String, path: String, status: int, data: Dictionary, message: String) -> Dictionary:
	data["principal"] = str(s.world.principal)
	data["revision"] = int(s.world.change_revision)
	return _observe(s, op, path, status, data, message)

static func _pentest(s: Dictionary, action: String, args: Dictionary, target: String) -> Dictionary:
	var w: Dictionary = s.world
	if action in ["reset_session", "discover_assets"]:
		w.principal = "employee01"
		return _network_record(s, "session", "employee01", 200, {}, "支給された社員の接続に戻りました。")
	if action == "authenticate":
		var user = args.get("username", ""); var credential = args.get("credential", "")
		if not user is String or not credential is String: return _result(false, "利用者と資格情報を文字列で入力してください。")
		if user.length() > 80 or credential.length() > 256: return _result(false, "入力が長すぎます。")
		if user != "svc-report" or credential != str(w.credential): return _network_record(s, "authenticate", str(user), 401, {}, "認証できませんでした。")
		w.principal = user; w.authenticated_epoch = int(w.credential_epoch)
		return _network_record(s, "authenticate", user, 200, {}, "接続を確立しました。")
	if action in ["browse", "read"]:
		var path := _resource_path(args.get("path", target))
		if path == "!invalid": return _network_record(s, action, "", 400, {}, "パスの形式が不正です。")
		if str(w.principal) == "svc-report" and int(w.authenticated_epoch) != int(w.credential_epoch): return _network_record(s, action, path, 401, {}, "接続が失効しています。")
		if path.is_empty() and action == "browse": return _network_record(s, action, path, 200, {"entries":[{"path":"share01","directory":true},{"path":"evidence","directory":true}]}, "許可された検証環境の共有一覧です。")
		var known: bool = path in ["share01", "evidence"] or w.files.has(path)
		if not known: return _network_record(s, action, path, 404, {}, "資源が見つかりません。")
		if not _network_access(w, str(w.principal), path):
			if bool(w.fixed) and path == "share01/deploy.env" and w.principal == "employee01": w.retests["denied"] = int(w.change_revision)
			return _network_record(s, action, path, 403, {}, "この利用者にはアクセスが許可されていません。")
		if action == "browse":
			if w.files.has(path): return _network_record(s, action, path, 400, {}, "フォルダーを指定してください。")
			var entries: Array = []
			for file in w.files:
				if str(file).begins_with(path + "/"): entries.append({"path":file,"directory":false,"size":str(w.files[file]).to_utf8_buffer().size()})
			return _network_record(s, action, path, 200, {"entries":entries}, "フォルダーを開きました。")
		if not w.files.has(path): return _network_record(s, action, path, 400, {}, "ファイルを指定してください。")
		var bytes: String = str(w.files[path])
		if bool(w.fixed) and path == "share01/daily.csv" and w.principal == "employee01": w.retests["business"] = int(w.change_revision)
		return _network_record(s, action, path, 200, {"bytes":bytes,"sha256":bytes.sha256_text()}, "ファイルの内容を取得しました。")
	if action == "submit_finding":
		var ids = args.get("evidence_ids", [])
		if not ids is Array or ids.size() < 2 or ids.size() > 6: return _result(false, "観測した根拠を 2〜6 件選んでください。")
		var leak := false; var proof := false; var saved := {}
		for id in ids:
			var row := _lookup(s, str(id))
			if row.is_empty(): return _result(false, "保持されていない記録があります。")
			saved[str(id)] = row.duplicate(true)
			if row.get("operation", "") == "read" and int(row.get("status", 0)) == 200:
				leak = leak or (str(row.target) == "share01/deploy.env" and row.data.get("principal", "") == "employee01" and str(row.data.get("bytes", "")).contains("TOKEN="))
				proof = proof or (str(row.target) == "evidence/proof.csv" and row.data.get("principal", "") == "svc-report" and not str(row.data.get("bytes", "")).is_empty())
		if not leak or not proof: return _result(false, "権限の変化と取得できたデータを再現できる原記録が必要です。")
		w.report = {"evidence":saved,"accepted":true}
		return _result(true, "顧客が再現を確認しました。修正版を受け取れます。", true)
	if action in ["customer_fix", "modify_grant"]:
		if not bool(w.report.get("accepted", false)): return _result(false, "先に観測した根拠を提出してください。")
		if bool(w.fixed): return _result(true, "修正版は受領済みです。")
		w.fixed = true; w.grant_fixed = true; w.change_revision = int(w.change_revision) + 1
		w.credential_epoch = int(w.credential_epoch) + 1; w.credential = "rotated-" + str(w.credential_epoch)
		w.files["share01/deploy.env"] = "SERVICE_USER=svc-report\nTOKEN=" + str(w.credential) + "\n"
		return _result(true, "顧客が配置設定の公開範囲と資格情報を更新しました。元の操作と通常の日報を再確認してください。", true, {}, 3)
	return _result(false, "資源の閲覧・読取・認証で観測してください。旧経路ショートカットは利用できません。")

static func _ledger(w: Dictionary, bytes: String) -> Dictionary:
	var lines := bytes.strip_edges().split("\n", false)
	var rows: Array = []; var seen := {}; var errors: Array = []; var total := 0
	if lines.is_empty() or lines[0].strip_edges() != "id,amount": return {"rows":[],"errors":["台帳の列を解釈できません。"],"total":0,"matches":false}
	for i in range(1, lines.size()):
		var cells := lines[i].strip_edges().split(",")
		if cells.size() != 2 or not cells[1].is_valid_int(): errors.append("%d 行目の形式を確認してください。" % (i + 1)); continue
		if seen.has(cells[0]): errors.append("伝票 ID %s が重複しています。" % cells[0])
		seen[cells[0]] = int(cells[1]); total += int(cells[1]); rows.append({"id":cells[0],"amount":int(cells[1])})
	var matches: bool = errors.is_empty() and seen.size() == w.reference.size()
	for row in w.reference:
		if not seen.has(str(row.id)) or int(seen.get(str(row.id), -1)) != int(row.amount): matches = false
	return {"rows":rows,"errors":errors,"total":total,"matches":matches}

static func _startup(bytes: String) -> Dictionary:
	var effects: Array=[]; var errors: Array=[]; var writes_ledger:=false
	for line in bytes.split("\n",false):
		var command: String=line.strip_edges()
		if command.is_empty() or command=="none" or command.begins_with("#"): continue
		if command=="sync-persistence": effects.append("同期キャッシュの台帳で ledger.csv を上書き"); writes_ledger=true
		elif command=="logrotate /var/log": effects.append("業務ログを整理（台帳変更なし）")
		else: errors.append("未登録の起動処理: "+command)
	return {"effects":effects,"errors":errors,"writes_ledger":writes_ledger}

static func _recovery(s: Dictionary, action: String, args: Dictionary, target: String) -> Dictionary:
	var w: Dictionary = s.world
	if action in ["compare_snapshots", "inspect_snapshot"]:
		if not w.snapshots.has(target): return _result(false, "スナップショットがありません。")
		w["selected_snapshot"] = target
		return _observe(s, "inspect_snapshot", target, 200, {"files":w.snapshots[target]}, "保存内容を開きました。")
	if action == "stage_restore":
		var selected: String = str(args.get("snapshot", w.get("selected_snapshot", "")))
		if not w.snapshots.has(selected): return _result(false, "復元元を選んでください。")
		w.staged = w.snapshots[selected].duplicate(true); w.stage_revision = int(w.stage_revision) + 1
		w["stage_source"] = selected; w["scan"] = {}; w.business_test = {}; w.services = {"identity":false,"database":false,"app":false}
		return _result(true, "隔離先に復元しました。本番の内容は保持されています。", true, {}, 3)
	if action == "edit_stage":
		var file = args.get("file", ""); var content = args.get("content", "")
		if not file is String or not content is String or content.length() > 8000 or not file in ["ledger", "startup"]: return _result(false, "隔離先の台帳か起動設定を指定してください。")
		if w.staged.is_empty(): return _result(false, "先に隔離先へ復元してください。")
		if str(w.staged.get(file, "")) == content: return _result(true, "内容は変更されていません。")
		w.staged[file] = content; w.stage_revision = int(w.stage_revision) + 1; w.business_test = {}; w.services = {"identity":false,"database":false,"app":false}
		return _result(true, "隔離先だけを変更しました。試験をやり直してください。", true, {}, 2)
	if action in ["scan_stage", "probe_stage"]:
		if w.staged.is_empty(): return _result(false, "先に隔離先へ復元してください。")
		var data := _ledger(w, str(w.staged.get("ledger", "")))
		data["startup"] = str(w.staged.get("startup", "")); data["revision"] = int(w.stage_revision)
		data["startup_execution"] = _startup(str(w.staged.get("startup","")))
		w.scan = data.duplicate(true)
		return _observe(s, "scan_stage", str(w.get("stage_source", "")), 200, data, "台帳と起動設定の内容を検査しました。控えと照合してください。")
	if action == "revoke_session":
		if not w.sessions.has(target): return _result(false, "接続がありません。")
		if not bool(w.sessions[target].active): return _result(true, "失効済みです。")
		w.sessions[target].active = false; w.change_revision = int(w.change_revision) + 1
		return _result(true, "選択した管理接続を失効しました。", true, {}, 1)
	if action in ["rotate_identity", "repair_identity"]:
		if str(args.get("account", target)) != "restore-operator": return _result(false, "更新する管理アカウントを選んでください。")
		w.credential_epoch = int(w.credential_epoch) + 1; w.change_revision = int(w.change_revision) + 1
		return _result(true, "管理資格情報を更新しました。発行済み接続は別に確認してください。", true, {}, 2)
	if action in ["isolate_network", "isolate_production"]:
		if bool(w.network_isolated): return _result(true, "本番接続は停止中です。")
		w.network_isolated = true; w.change_revision = int(w.change_revision) + 1
		return _result(true, "本番の外部接続を停止しました。", true, {}, 1)
	if action == "start_service":
		if not target in ["identity", "database", "app"]: return _result(false, "サービスがありません。")
		if w.staged.is_empty(): return _result(false, "隔離先のデータがありません。")
		var ok := true; var reason := "起動しました。"
		if target == "identity": ok = int(w.credential_epoch) > 1; reason = "管理資格情報を更新してから起動してください。" if not ok else reason
		elif target == "database": ok = bool(w.services.identity) and _ledger(w, str(w.staged.ledger)).errors.is_empty(); reason = "認証サービスまたは台帳形式を確認してください。" if not ok else reason
		else: ok = bool(w.services.database) and _startup(str(w.staged.get("startup",""))).errors.is_empty(); reason = "データベースまたは起動設定の構文を確認してください。" if not ok else reason
		w.services[target] = ok
		return _observe(s, "start_service", target, 200 if ok else 409, {"running":ok}, reason)
	if action == "probe_business":
		if w.staged.is_empty(): return _result(false, "隔離先のデータがありません。")
		var ledger := _ledger(w, str(w.staged.ledger))
		w.business_test = {"revision":int(w.stage_revision),"running":bool(w.services.app),"ledger":ledger,"total":ledger.total}
		return _observe(s, "probe_business", "staging", 200 if w.services.app else 503, w.business_test, "隔離先の業務結果を取得しました。")
	if action == "restore_business":
		if not bool(w.network_isolated): return _result(false, "本番への接続を停止してから反映してください。")
		if w.staged.is_empty() or int(w.business_test.get("revision", -1)) != int(w.stage_revision) or not bool(w.business_test.get("running", false)): return _result(false, "現在の隔離先で業務試験を実行してください。")
		w.production = w.staged.duplicate(true); w.published_revision = int(w.stage_revision)
		return _result(true, "試験した内容を本番へ反映しました。接続再開後も確認してください。", true, {}, 3)
	if action == "reconnect_business":
		if int(w.published_revision) != int(w.stage_revision) or w.staged.is_empty(): return _result(false, "現在の隔離先を本番へ反映してください。")
		w.network_isolated = false
		var persistence: bool = _startup(str(w.production.get("startup",""))).writes_ledger
		var access := bool(w.sessions["sid-sync-17"].active) or int(w.credential_epoch) <= 1
		w["reinfection_observed"] = persistence or access
		if persistence or access: w.production.ledger = "id,amount\n001,999999\n"
		w["reconnected"] = true
		return _observe(s, "reconnect_business", "production", 200, {"ledger":str(w.production.ledger),"startup":str(w.production.startup)}, "本番接続を再開しました。台帳の実内容を取得しました。")
	return _result(false, "対象を選んで操作してください。旧一括修復は利用できません。")

static func checks(state: Dictionary) -> Array:
	var s := state.duplicate(true); upgrade(s)
	var w: Dictionary = s.world; var values: Array = []
	if s.kind == "advanced-hunt":
		var linked: Array = []; var normal := false
		for link in w.links:
			if link.session == "sid-r44":
				for source in link.sources:
					if not source in linked: linked.append(source)
			if link.session == "sid-b21": normal = true
		var source_evidence: Array = []
		for row in s.evidence.values():
			if row.get("kind", "") == "telemetry" and row.get("session", "") == "sid-r44" and not row.source in source_evidence: source_evidence.append(row.source)
		var security: Dictionary = w.measurements.get("security", {}); var business: Dictionary = w.measurements.get("business", {})
		var contained: bool = not bool(w.sessions["sid-r44"].active) and not bool(w.tasks["task-sync"].enabled)
		var running: bool = not business.is_empty() and business.get("steps", []).all(func(x): return bool(x.allowed))
		values = [linked.size() == 3 and normal, source_evidence.size() >= 2 and s.evidence.has("CHG-114"), contained and int(security.get("revision", -1)) == int(w.change_revision), running and int(business.get("revision", -1)) == int(w.change_revision), normal and bool(w.sessions["sid-b21"].active) and bool(w.tasks["task-backup"].enabled)]
	elif s.kind == "advanced-pentest":
		values = [not s.observations.is_empty(), bool(w.report.get("accepted", false)), bool(w.fixed) and int(w.retests.get("denied", -1)) == int(w.change_revision), bool(w.fixed) and int(w.retests.get("business", -1)) == int(w.change_revision)]
	else:
		var current: bool = int(w.get("scan", {}).get("revision", -1)) == int(w.stage_revision)
		var ledger := _ledger(w, str(w.get("staged", {}).get("ledger", "")))
		var identity: bool = int(w.credential_epoch) > 1 and not bool(w.sessions["sid-sync-17"].active)
		var tested: bool = int(w.business_test.get("revision", -1)) == int(w.stage_revision) and bool(w.business_test.get("running", false))
		var startup:=_startup(str(w.get("staged",{}).get("startup","")))
		values = [ledger.matches, current and ledger.errors.is_empty(), identity, not startup.writes_ledger and startup.errors.is_empty() and current, bool(w.get("reconnected", false)) and not bool(w.network_isolated), tested and _ledger(w, str(w.production.get("ledger", ""))).matches, bool(w.get("reconnected", false)) and not bool(w.get("reinfection_observed", true)) and int(w.published_revision) == int(w.stage_revision)]
	var rows: Array = []
	for i in s.checks.size():
		var row: Dictionary = s.checks[i].duplicate(true); row["passed"] = bool(values[i]) if i < values.size() else false; rows.append(row)
	return rows

static func view(state: Dictionary, selected: String = "") -> Dictionary:
	var s := state.duplicate(true); upgrade(s)
	var w: Dictionary = s.world
	var out := {"kind":s.kind,"revision":s.revision,"selected":selected,"nodes":[],"edges":[],"events":[],"records":[],"actions":[],"checks":checks(s),"last_result":s.get("last_result", {}),"observations":s.observations,"evidence":s.evidence}
	# Kept for non-visual API callers; no action IDs encode a secret target.
	out.actions = [{"id":"observe","label_key":"adv_nav_events","target":"","options":[]}]
	if s.kind == "advanced-hunt":
		out["hunt"] = {"events":s.events.filter(func(x): return x.get("kind", "") == "telemetry"),"work_orders":w.work_orders,"assets":w.assets,"sessions":w.sessions,"tasks":w.tasks,"links":w.links,"measurements":w.measurements,"change_revision":w.change_revision}
		out.events = out.hunt.events
		out.records = [{"id":"work-orders","label":"顧客の作業予定","detail":JSON.stringify(w.work_orders)}]
	elif s.kind == "advanced-pentest":
		out["network"] = {"principal":w.principal,"scope":["share01", "evidence"],"brief":"社員アカウントから到達できる範囲を、架空の検証環境だけで確認してください。日報共有は継続利用します。設定変更は顧客が行います。","fixed":w.fixed,"report":w.report,"retests":w.retests}
		out.records = [{"id":"scope","label":"許可範囲","detail":"share01 / evidence — 閲覧・読取・取得した資格情報による認証。削除・範囲外接続は禁止。"}]
	else:
		var snapshots: Array = []
		for id in w.snapshots: snapshots.append({"id":id,"revision":w.snapshots[id].get("revision", 0),"files":["ledger", "startup"]})
		out["recovery"] = {"snapshots":snapshots,"selected_snapshot":w.get("selected_snapshot", ""),"stage_source":w.get("stage_source", ""),"staged":w.staged,"stage_revision":w.stage_revision,"scan":w.get("scan", {}),"services":w.services,"sessions":w.sessions,"credential_epoch":w.credential_epoch,"network_isolated":w.network_isolated,"production":w.production,"reference":w.reference,"business_test":w.business_test,"published_revision":w.published_revision}
		out.records = [{"id":"reference","label":"経理の伝票控え","detail":JSON.stringify(w.reference)}]
	return out
