extends SceneTree

const ObservationProjection = preload("res://scripts/diagnostic_observation.gd")
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_test_business_response_shapes()
	_test_transport_and_smb()
	_test_dns_hash_and_unmeasured()
	for failure in failures: push_error(failure)
	print("DIAGNOSTIC_OBSERVATION_PASS assertions=" + str(assertions) if failures.is_empty() else "DIAGNOSTIC_OBSERVATION_FAIL count=" + str(failures.size()) + " assertions=" + str(assertions))
	quit(0 if failures.is_empty() else 1)

func _test_business_response_shapes() -> void:
	var mismatch := _probe("curl https://intranet.client.test/api/business/orders", "status:200|" + "a".repeat(64), "HTTP/1.1 200 OK\nContent-Type: application/json\n\n" + JSON.stringify({"ok":true,"code":200,"data":{"orders":[{"order":"501","customer":"101","total":12800}],"customers":[{"id":"101","name":"Aoba"}],"sha256":"" + "b".repeat(64)},"external_storage":{"enabled":true,"ok":true,"host":"files01.client.test","path":"/srv/share/partner-order.csv"}}), false, true)
	var mismatch_before: Dictionary = mismatch.duplicate(true)
	var first: Dictionary = ObservationProjection.project(mismatch)
	check(first.protocol == "http" and first.host == "intranet.client.test" and first.path == "/api/business/orders", "HTTP host and request path come from public command URL")
	check(first.status == 200 and first.expected_status == 200 and first.availability == "available" and first.transport == "replied", "actual HTTP response and accessible provider project independently of acceptance")
	check(first.passed == false and first.specimen == "orders" and first.rows == first.data.orders, "probe PASS remains authoritative while actual orders data is preserved")
	check(first.hash == "b".repeat(64) and first.expected_hash == "a".repeat(64) and first.hash_match == "different", "hash projection compares only actual body hash with public expected hash")
	var last_digit: Dictionary = mismatch.duplicate(true)
	last_digit.result = _http(200, {"code":200, "data":{"sha256":"a".repeat(63) + "b"}})
	check(ObservationProjection.project(last_digit).hash_match == "different", "full hash comparison rejects a mismatch outside the abbreviated graphical seal")
	check(first.source == {"enabled":true,"ok":true,"host":"files01.client.test","path":"/srv/share/partner-order.csv"} and first.data.orders.size() == 1, "source and data retain actual nested response payload")
	check(mismatch == mismatch_before and first.rows == first.data.orders, "projection does not mutate input and rows is a detached copy")
	first.rows.clear()
	check(mismatch == mismatch_before and first.data.orders.size() == 1, "projected row list does not alias input or projected data")

	var malformed_payload := {"ok":false,"code":422,"error":"malformed_orders_row","external_storage":{"enabled":true,"ok":true,"host":"files01.client.test","path":"/srv/share/partner-order.csv"}}
	var malformed: Dictionary = ObservationProjection.project(_probe("curl https://intranet.client.test/api/business/orders", "status:200", _http(422, malformed_payload), true, true))
	check(malformed.status == 422 and malformed.expected_status == 200 and malformed.error == "malformed_orders_row", "malformed order response exposes actual business error and actual status")
	check(malformed.availability == "available" and malformed.source.ok and malformed.rows.is_empty(), "readable share remains available despite malformed business data")

	var unavailable_payload := {"ok":false,"code":503,"error":"provider_unavailable","external_storage":{"enabled":true,"ok":false,"code":503,"error":"provider_unavailable","host":"files01.client.test","path":"/srv/share/partner-order.csv"}}
	var unavailable: Dictionary = ObservationProjection.project(_probe("curl https://intranet.client.test/api/business/orders", "status:200", _http(503, unavailable_payload), false, true))
	check(unavailable.status == 503 and unavailable.availability == "unavailable" and unavailable.error == "provider_unavailable", "HTTP 503 and actual unavailable provider stay distinct from readable validation failure")
	var json_error: Dictionary = ObservationProjection.project(_probe("business request", "", JSON.stringify({"ok":false,"code":507,"error":"save_failed"}), false, true))
	check(json_error.status == 507 and json_error.transport == "replied" and json_error.availability == "unavailable" and json_error.error == "save_failed", "raw JSON response uses actual code and error when no HTTP status line exists")
	var portal: Dictionary = ObservationProjection.project(_probe("curl -X PUT -H 'Authorization: Bearer partner-session' 'https://portal.client.test/partner?link=current'", "status:401|mfa_required", "HTTP/1.1 401 Unauthorized\n" + JSON.stringify({"ok":false,"code":401,"error":"mfa_required"}), true, true))
	check(portal.method == "PUT" and portal.error == "mfa_required" and portal.status == 401 and portal.passed, "actual portal PUT and single-line JSON response preserve method and denial evidence")
	check(first.method == "GET", "default HTTP requests retain the guest VM's GET operation")

func _test_transport_and_smb() -> void:
	var blocked: Dictionary = ObservationProjection.project(_probe("curl https://intranet.client.test/api/business/orders", "status:200", "curl: (28) Operation timed out FIREWALL_DENIED action=block rule=lan-business", false, true))
	check(blocked.transport == "firewall" and blocked.rule == "lan-business" and blocked.status == 0 and blocked.availability == "unknown", "firewall transport retains actual rule without inventing an HTTP response")

	var denied: Dictionary = ObservationProjection.project(_probe("smbclient //files01.client.test/share -U guest -c 'ls'", "DENIED", "NT_STATUS_ACCESS_DENIED", true, true))
	check(denied.protocol == "smb" and denied.host == "files01.client.test" and denied.path == "/share", "SMB endpoint is projected from public share command")
	check(denied.transport == "replied" and denied.availability == "denied" and denied.passed, "actual SMB access denial remains distinct from contract PASS")
	var bad_share: Dictionary = ObservationProjection.project(_probe("smbclient //files01.client.test/share -U guest -c 'ls'", "DENIED", "NT_STATUS_BAD_NETWORK_NAME", false, false))
	check(bad_share.availability == "unavailable" and bad_share.transport == "replied" and not bad_share.passed, "missing SMB share is unavailable, not an ACL denial")

func _test_dns_hash_and_unmeasured() -> void:
	var dns: Dictionary = ObservationProjection.project(_probe("dig +tcp intranet.client.test", "NOERROR", ";; status: SERVFAIL\n;; no answer", false, true))
	check(dns.protocol == "dns" and dns.host == "intranet.client.test" and dns.transport == "dns" and dns.availability == "unavailable" and dns.status == 0, "DNS observation remains DNS evidence without an HTTP status")

	var hash_value := "c".repeat(64)
	var hash: Dictionary = ObservationProjection.project(_probe("sha256sum /srv/share/customers.csv", hash_value, hash_value + "  /srv/share/customers.csv", true, true))
	check(hash.protocol == "hash" and hash.path == "/srv/share/customers.csv" and hash.specimen == "file" and hash.transport == "local", "file hash command projects local path and specimen")
	check(hash.hash == hash_value and hash.expected_hash == hash_value and hash.hash_match == "match" and hash.availability == "available", "actual sha256sum output is compared to published expectation")

	var raw_unmeasured := _probe("curl https://intranet.client.test/api/business/orders", "status:200", _http(200, {"ok":true,"code":200,"data":{"orders":[{"order":"fictional"}]},"external_storage":{"ok":true}}), false, false)
	raw_unmeasured.recorded = false
	var unmeasured: Dictionary = ObservationProjection.project(raw_unmeasured)
	check(not unmeasured.recorded and not unmeasured.fresh and not unmeasured.passed and unmeasured.status == 0 and unmeasured.transport == "unknown", "unmeasured probe does not expose seeded result or claim a response")
	check(unmeasured.data.is_empty() and unmeasured.source.is_empty() and unmeasured.rows.is_empty() and unmeasured.availability == "unknown", "unmeasured response data and provider are not fabricated from stale fields")

	var stale_payload := {"ok":true,"code":200,"data":{"customers":[{"id":"101","name":"Aoba"}],"sha256":"" + "d".repeat(64)},"external_storage":{"enabled":true,"ok":true}}
	var stale: Dictionary = ObservationProjection.project(_probe("curl https://intranet.client.test/api/business/customers", "status:200", _http(200, stale_payload), true, false))
	check(stale.recorded and not stale.fresh and stale.passed and stale.data.customers.size() == 1 and stale.availability == "available", "stale observation retains real historical response without rescoring its prior PASS")

func _probe(command: String, expectation: String, result: String, passed: bool, fresh: bool) -> Dictionary:
	return {"command":command,"expectation":expectation,"recorded":true,"result":result,"passed":passed,"fresh":fresh}

func _http(status: int, payload: Dictionary) -> String:
	return "HTTP/1.1 %d OK\nContent-Type: application/json\n\n%s" % [status, JSON.stringify(payload)]

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); print("FAIL ", label)
