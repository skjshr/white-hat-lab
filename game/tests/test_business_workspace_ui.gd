extends SceneTree
var ui
var game
var pc
var failures: Array[String] = []
var profile := str(OS.get_process_id())
var capture: bool = "--capture" in OS.get_cmdline_user_args()
var narrow: bool = "--narrow" in OS.get_cmdline_user_args()
const SOURCE_FLOW = preload("res://scripts/business_source_flow.gd")
func _init() -> void:
	create_timer(150.0).timeout.connect(func(): push_error("business ui timeout"); quit(2))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)
func frames(count: int = 4) -> void:
	for _i in count: await process_frame
func target(chapter: int) -> int:
	for i in game.state.targets.size():
		if int(game.state.targets[i].get("chapter", -1)) == chapter: return i
	return -1
func ssh(index: int) -> bool:
	check(game.select_target(index), "select target")
	var result: String = game.vm_run("ssh client")
	check(result.contains("Authenticated"), "ssh target")
	return bool(game.vm_info().get("connected", false))
func find_name(node: Node, prefix: String) -> Node:
	for child in node.get_children():
		if str(child.name).begins_with(prefix): return child
		var nested := find_name(child, prefix)
		if nested != null: return nested
	return null
func find_snapshot(raw: String) -> String:
	for line in raw.split("\n"):
		var parts: PackedStringArray = line.strip_edges().split(" ", false)
		if parts.size() >= 4 and parts[0] == "00000001" and parts[1] == "offsite": return parts[0]
	return ""
func snap(label: String) -> void:
	if not capture: return
	await frames(8)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/simulator/business/ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(label + ("-narrow" if narrow else "-wide") + ".png")
	check(get_root().get_texture().get_image().save_png(path) == OK, "capture " + label)
	print("CAPTURE ", path)
func test_business_source_projection() -> void:
	var provider := {"enabled":true,"ok":true,"host":"files.example.test","share":"share","path":"/srv/share/partner-order.csv"}
	var success_response := JSON.stringify({"ok":true,"external_storage":provider,"data":{"orders":[{"order":"SO-1"}],"customers":[{"id":"C1"}]}})
	var success: Dictionary = SOURCE_FLOW.project("sales",success_response)
	check(success.status == "ok" and success.count == 1, "business source only reports real order rows")
	check(success.host == "files.example.test" and success.share == "share" and success.path == "/srv/share/partner-order.csv", "successful fetch retains provider and actual file")
	check(success.server.status == "ok" and success.file.status == "ok" and success.business.status == "ok", "successful fetch projects each flow stage separately")
	var missing: Dictionary = SOURCE_FLOW.project("sales",JSON.stringify({"ok":false,"error":"missing_file","code":404,"external_storage":provider}))
	check(missing.status == "missing", "allowed provider with missing file is not success")
	check(missing.server.status == "ok" and missing.file.label == "必要資料なし" and missing.business.label == "資料不足", "sales missing file does not falsely identify the absent dependency")
	var malformed_data := {"ok":true,"external_storage":provider,"data":{"orders":"not-an-array","customers":[]}}
	var malformed: Dictionary = SOURCE_FLOW.project("sales",JSON.stringify(malformed_data))
	check(malformed.status == "malformed" and malformed.count == 0, "allowed provider with malformed response is not success")
	var malformed_customer: Dictionary = SOURCE_FLOW.project("sales",JSON.stringify({"ok":false,"error":"malformed_customers_header","code":422,"external_storage":provider}))
	check(malformed_customer.file.name == "顧客資料" and malformed_customer.business.label == "顧客資料異常", "customer parse failure is attributed to customer source")
	var malformed_order: Dictionary = SOURCE_FLOW.project("sales",JSON.stringify({"ok":false,"error":"malformed_orders_row","code":422,"external_storage":provider}))
	check(malformed_order.file.name == "受注資料" and malformed_order.business.label == "受注資料異常", "order parse failure is attributed to orders source")
	var unavailable_provider := provider.duplicate(true); unavailable_provider.ok = false; unavailable_provider.code = 503
	var unavailable: Dictionary = SOURCE_FLOW.project("sales",JSON.stringify({"ok":false,"error":"provider_unavailable","external_storage":unavailable_provider}))
	check(unavailable.status == "unavailable" and unavailable.symbol == "×", "provider failure is distinguished from file/data failure")
	var denied_provider := provider.duplicate(true); denied_provider.ok = false; denied_provider.error = "storage_denied"
	var denied: Dictionary = SOURCE_FLOW.project("sales",JSON.stringify({"ok":false,"error":"storage_denied","code":403,"external_storage":denied_provider}))
	check(denied.label == "共有アクセス拒否" and denied.server.label == "アクセス拒否" and denied.file.status == "unknown", "access denial preserves its reason without claiming a file read")
	var not_fetched: Dictionary = SOURCE_FLOW.project("accounting","")
	check(not_fetched.status == "not_fetched" and not_fetched.path == "/srv/data/ledger.txt", "no fetch and ledger provider path are explicit")
	var ordinary_provider := provider.duplicate(true); ordinary_provider.enabled = false
	var ordinary: Dictionary = SOURCE_FLOW.project("sales",JSON.stringify({"ok":true,"external_storage":ordinary_provider,"data":{"orders":[],"customers":[]}}))
	check(not ordinary.visible and ordinary.path == "/srv/data/orders.csv", "ordinary non-shared cases hide SMB and use the actual order file")
	var ledger_success: Dictionary = SOURCE_FLOW.project("accounting",JSON.stringify({"ok":true,"external_storage":provider,"data":{"ledger":[{"date":"2026-10-05"}]}}))
	check(ledger_success.status == "ok" and ledger_success.path == "/srv/data/ledger.txt", "accounting never displays the orders share as its source")
	var missing_ledger: Dictionary = SOURCE_FLOW.project("accounting",JSON.stringify({"ok":false,"error":"missing_file","code":404,"external_storage":provider}))
	check(missing_ledger.file.label == "ファイルなし" and missing_ledger.file.detail == "/srv/data/ledger.txt", "missing ledger is identified at its actual path")
	var customer_success: Dictionary = SOURCE_FLOW.project("customers",JSON.stringify({"ok":true,"external_storage":provider,"data":{"customers":[{"id":"C1"}]}}))
	check(customer_success.path == "/srv/share/customers.csv", "customer path follows the provider customer mount")
	check(SOURCE_FLOW.project("sales","not valid JSON").status == "malformed", "unparseable fetched content is not reported as missing fetch or success")
func run() -> void:
	test_business_source_projection()
	ui = load("res://scripts/interface.gd").new()
	root.add_child(ui)
	await frames(3)
	game = ui._game()
	game.set_process(false)
	check(game.save_path.begins_with("user://qa-"), "QA storage")
	check(ui._new_game(), "new game")
	check(game.choose_strategy("response") and game.start_free_career(), "response career")
	game.state.skills.advisory = 10; game.state.skills.operations = 10; game.state.skills.response = 10
	game.state.profit = 1000000; game.state.peak_profit = 1000000; game._update_growth()
	var offer: Dictionary = {}
	for day in 60:
		game.state.day = day + 1
		game._make_offers()
		for item in game.state.offers:
			if str(item.get("case_id", "")) == "composite-corruption-response" and bool(item.get("market_available", false)):
				offer = item; break
		if not offer.is_empty(): break
	check(not offer.is_empty(), "composite offer")
	if offer.is_empty(): quit(1); return
	var offer_id := str(offer.get("id", ""))
	check(game.set_offer_quote(offer_id, int(offer.get("reward", offer.get("base_reward", 0)))) and game.choose_contract(offer_id), "accept composite")
	var backup := target(1); var firewall := target(2)
	check(backup >= 0 and firewall >= 0, "linked targets")
	if backup < 0 or firewall < 0: quit(1); return
	if ssh(backup):
		var cfg := "schedule=daily\nrepository=offsite\n"
		check(game.vm_write(str(game.vm_info().get("config_path", "")), cfg), "backup config")
		check(game.vm_run("systemctl restart restic").contains("active"), "backup active")
		var sid := find_snapshot(game.vm_run("restic -r offsite snapshots"))
		check(not sid.is_empty(), "snapshot")
		if not sid.is_empty():
			check(game.vm_run("restic -r offsite restore " + sid + ":/srv/data --target /restore").contains("restored"), "restore")
	if ssh(firewall):
		var policy: String = game._vm().configuration_text({"dns":"on","business":"allow","admin_public":"deny","tls":"on"})
		check(game.vm_write(str(game.vm_info().get("config_path", "")), policy), "firewall config")
		check(game.vm_run("systemctl restart firewall").contains("active"), "firewall active")
	if ssh(backup):
		check(game.vm_run("cp /restore/ledger.txt /srv/data/ledger.txt") == "", "copy restored ledger")
	check(ssh(firewall), "return firewall")
	game.set_settings({"resolution":"960x600" if narrow else "1280x720", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 640) if narrow else Vector2i(1280, 720)
	ui.open_panel("terminal")
	await frames(6)
	pc = ui.desktop
	check(pc != null, "desktop")
	pc._show_app("browser")
	await frames(6)
	if not pc.windows.browser.maximized: pc.windows.browser.toggle_maximize()
	await frames(4)
	pc._browse_url("https://intranet.client.test/sales", true)
	await frames(10)
	check(pc.browser_response.contains("Aoba") or pc.widgets.browser.page.find_child("BusinessOrderList", true, false) != null, "sales actual response")
	check(pc.widgets.browser.page.find_child("BusinessOrderList", true, false) != null, "sales list")
	var source_flow: Control = pc.widgets.browser.page.find_child("BusinessSourceFlow", true, false)
	check(source_flow == null, "non-shared ordinary provider does not display an SMB source flow")
	var source_before_state: Dictionary = game.state.duplicate(true)
	var source_before_clock: int = game.clock_minutes()
	var source_before_cash: int = int(game.state.cash)
	var source_before_key: String = game._vm_key()
	var source_before_vm: Dictionary = game._vm().export_state()
	var source_probe := VBoxContainer.new()
	var fixture_provider := {"enabled":true,"ok":true,"host":"files.example.test","share":"share","path":"/srv/share/partner-order.csv"}
	var fixture_response := JSON.stringify({"ok":true,"external_storage":fixture_provider,"data":{"orders":[{"order":"SO-1"}],"customers":[{"id":"C1"}]}})
	SOURCE_FLOW.render(pc,source_probe,SOURCE_FLOW.project("sales",fixture_response),func(): pass)
	var rendered_flow: Control = source_probe.find_child("BusinessSourceFlow",true,false)
	check(rendered_flow != null, "enabled provider renders compact data flow")
	if rendered_flow != null:
		check(rendered_flow.find_child("BusinessSourceStage1",true,false) != null and rendered_flow.find_child("BusinessSourceStage2",true,false) != null and rendered_flow.find_child("BusinessSourceStage3",true,false) != null, "renderer separates source, file and business result")
		var rendered_status: Label = rendered_flow.find_child("BusinessSourceStatus",true,false)
		check(rendered_status is Label and str(rendered_status.text).contains("取得済"), "successful fetch remains visible")
		check(rendered_flow.find_child("BusinessStorageRefresh",true,false) is Button, "source flow provides explicit refresh")
	check(game.state == source_before_state and game.clock_minutes() == source_before_clock and int(game.state.cash) == source_before_cash, "source render leaves game state, clock and money unchanged")
	check(game._vm_key() == source_before_key and game._vm().export_state() == source_before_vm, "source render leaves VM/key unchanged")
	source_probe.free()
	await snap("sales-list")
	var first = find_name(pc.widgets.browser.page, "BusinessOrderOpen_")
	check(first is BaseButton, "order row")
	if first is BaseButton: first.pressed.emit()
	await frames(8)
	check(pc.widgets.browser.page.find_child("BusinessSelectedOrder", true, false) != null, "order detail")
	await snap("sales-detail")
	var back = pc.widgets.browser.page.find_child("BusinessBack", true, false)
	check(back is BaseButton, "order back")
	if back is BaseButton: back.pressed.emit()
	await frames(6)
	var search = pc.widgets.browser.page.find_child("BusinessSearch", true, false)
	check(search is LineEdit, "sales search")
	check(pc.widgets.browser.page.find_child("BusinessSelectedOrder", true, false) == null, "back closes record")
	if search is LineEdit:
		search.grab_focus(); search.text = "No matching customer"; search.text_changed.emit(search.text)
		await frames(3)
		check(search.has_focus(), "search preserves keyboard focus")
		check(pc.widgets.browser.page.find_child("BusinessNoResults", true, false).visible, "empty search visible")
		check(pc.widgets.browser.page.find_child("BusinessOrderCount", true, false).text.begins_with("0"), "filtered count zero")
		await snap("sales-empty")
	if search is LineEdit: search.text = "Aoba"; search.text_changed.emit("Aoba")
	await frames(4)
	check(pc.widgets.browser.page.find_child("BusinessNoResults", true, false) == null or not pc.widgets.browser.page.find_child("BusinessNoResults", true, false).visible, "search match")
	pc._browse_url("https://intranet.client.test/accounting", true)
	await frames(10)
	check(pc.widgets.browser.page.find_child("BusinessNoStatements", true, false) == null, "accounting rows")
	check(pc.browser_response.contains("62800"), "accounting 62800")
	await snap("accounting")
	if ssh(backup): check(game.vm_write("/srv/data/ledger.txt", "malformed ledger\n"), "malformed ledger")
	check(ssh(firewall), "return firewall for data error")
	pc._browse_url("https://intranet.client.test/accounting", true)
	await frames(8)
	check(pc.browser_response.contains("422"), "data error response")
	var malformed_flow: Control = pc.widgets.browser.page.find_child("BusinessSourceFlow", true, false)
	check(malformed_flow == null, "non-shared malformed ledger does not invent an SMB source")
	await snap("data-error")
	if ssh(firewall):
		var deny_policy: String = game._vm().configuration_text({"dns":"on","business":"deny","admin_public":"deny","tls":"on"})
		check(game.vm_write(str(game.vm_info().get("config_path", "")), deny_policy), "deny policy")
		check(game.vm_run("systemctl restart firewall").contains("active"), "deny firewall")
	pc._browse_url("https://intranet.client.test/accounting", true)
	await frames(8)
	check(not pc.browser_response.contains("62800"), "transport response")
	await snap("transport-error")
	if failures.is_empty(): print("BUSINESS_UI_CAPTURE_PASS")
	else: print("BUSINESS_UI_CAPTURE_FAIL count=", failures.size())
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
