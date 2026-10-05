extends SceneTree
const ShareProjection = preload("res://scripts/share_diagnostic_observation.gd")
const Unified = preload("res://scripts/diagnostic_observation.gd")
var failures: Array[String] = []
var assertions := 0

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); push_error(label)

func probe(result: String, operation := "ls", expectation := "DENIED") -> Dictionary:
	return {"command":"smbclient //files01.client.test/share -U guest%fictional -c '" + operation + "'", "recorded":true, "fresh":true, "passed":true, "expectation":expectation, "result":result}

func _init() -> void:
	for entry in [["NT_STATUS_ACCESS_DENIED", "access_denied", "operation", "denied"], ["NT_STATUS_LOGON_FAILURE", "logon_failed", "identity", "unavailable"], ["NT_STATUS_BAD_NETWORK_NAME", "share_missing", "share", "unavailable"], ["NT_STATUS_CONNECTION_REFUSED: service is not running", "service_stopped", "share", "unavailable"], ["NT_STATUS_OBJECT_NAME_NOT_FOUND", "remote_missing", "specimen", "unavailable"], ["NT_STATUS_OBJECT_PATH_NOT_FOUND", "path_missing", "specimen", "unavailable"], ["put: local file missing", "local_missing", "local_file", "unavailable"]]:
		var raw := probe(str(entry[0])); var before := raw.duplicate(true); var value: Dictionary = ShareProjection.project(raw)
		check(value.outcome == entry[1] and value.stop_at == entry[2] and value.availability == entry[3], "different failure has actual stage " + str(entry[1]))
		check(value.passed and value.user == "guest" and raw == before, "public verdict and requested user preserved without password or mutation")
		check(Unified.project(raw) == value, "unified projection shares strict SMB interpretation")
	for response in ["usage: smbclient //client/share", "{\"error\":\"save_failed\"}", "everything fine", "putting file other.csv: OK", "", "NT_STATUS_UNKNOWN", "put: local file missing\nreport.txt"]:
		var value: Dictionary = ShareProjection.project(probe(response))
		check(value.outcome == "unknown" and value.files.is_empty() and value.availability == "unknown", "untyped error/prose never becomes listing " + response)
	var listed: Dictionary = ShareProjection.project(probe("report.txt\norders.csv"))
	check(ShareProjection.project(probe("NT_STATUS_INVALID_PARAMETER: unsupported smb operation", "del report.txt")).outcome == "invalid_request", "actual suffixed guest command error is a request-stage failure")
	check(listed.outcome == "listed" and listed.files == ["report.txt", "orders.csv"] and listed.hash.is_empty(), "directory names only; no fabricated contents or hash")
	check(ShareProjection.project(probe("受注.csv\n顧客台帳.txt")).files == ["受注.csv", "顧客台帳.txt"], "actual Unicode file names remain distinct listing specimens")
	check(ShareProjection.project(probe("0 files")).outcome == "listed" and ShareProjection.project(probe("0 files")).files.is_empty(), "observed empty directory is distinct from no observation")
	var put: Dictionary = ShareProjection.project(probe("putting file archived.csv: OK", "put /srv/data/orders.csv archived.csv"))
	check(put.outcome == "written" and put.remote_name == "archived.csv" and put.local_path == "/srv/data/orders.csv" and put.files.is_empty() and put.hash.is_empty(), "actual PUT remote name and source; success does not invent byte content")
	check(ShareProjection.project(probe("putting file orders.csv: OK", "put /srv/data/orders.csv archived.csv")).outcome == "unknown", "mismatched PUT response cannot claim target success")
	var get: Dictionary = ShareProjection.project(probe("getting file report.txt: OK", "get report.txt /home/operator/copy.txt"))
	check(get.outcome == "downloaded" and get.local_path == "/home/operator/copy.txt", "GET destination preserved; no inferred default local path")
	var unrun := probe("report.txt"); unrun.recorded = false
	check(ShareProjection.project(unrun).files.is_empty() and ShareProjection.project(unrun).outcome == "unknown", "unrun response not exposed")
	var stale := probe("report.txt"); stale.fresh = false
	check(ShareProjection.project(stale).files == ["report.txt"] and not ShareProjection.project(stale).fresh, "historical list keeps original evidence with stale flag")
	var hash_value := "a".repeat(64)
	var sha := {"command":"sha256sum '/srv/share/orders.csv'", "expectation":hash_value, "recorded":true, "fresh":true, "passed":true, "result":hash_value + "  /srv/share/orders.csv"}
	check(ShareProjection.project(sha).hash_match == "match" and ShareProjection.project(sha).transport == "local", "local full original match does not claim SMB connection")
	sha.result = "a".repeat(63) + "b  /srv/share/orders.csv"
	check(ShareProjection.project(sha).hash_match == "different", "last hex digit affects equality beyond abbreviated text")
	sha.result = hash_value + "  /srv/share/other.csv"
	check(ShareProjection.project(sha).hash_match == "unknown" and ShareProjection.project(sha).hash.is_empty(), "wrong file cannot acquire requested file hash")
	sha.result = "sha256sum: file missing"
	check(ShareProjection.project(sha).outcome == "file_missing" and ShareProjection.project(sha).hash_match == "unknown", "missing local specimen stays unavailable without hash")
	print("SHARE_DIAGNOSTIC_OBSERVATION assertions=", assertions, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
