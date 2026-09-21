extends SceneTree
var ui
var game
var pc
var failures: Array[String] = []
var profile := str(OS.get_process_id())
var capture: bool = "--capture" in OS.get_cmdline_user_args()
var narrow: bool = "--narrow" in OS.get_cmdline_user_args()
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
func run() -> void:
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
