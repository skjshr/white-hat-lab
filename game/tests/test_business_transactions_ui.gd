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
	var folder := ProjectSettings.globalize_path("res://../../audit/all-services/captures")
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
	game.set_settings({"resolution":"960x600" if narrow else "1440x900", "window_mode":"windowed", "text_scale":1.3 if narrow else 1.0, "volume":0}, false)
	ui._set_text_scale(1.3 if narrow else 1.0)
	root.size = Vector2i(960, 640) if narrow else Vector2i(1440, 900)
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
	pc._browse_url("https://intranet.client.test/customers",true)
	await frames(6)
	press("BusinessNewCustomer")
	await frames(4)
	fill("BusinessCustomerName","海辺商店")
	await snap("customer-create")
	press("BusinessSave")
	await frames(8)
	check(pc.browser_response.contains("海辺商店"),"customer created through UI")
	pc._browse_url("https://intranet.client.test/sales",true)
	await frames(6)
	press("BusinessNewOrder")
	await frames(4)
	var choice = pc.widgets.browser.page.find_child("BusinessCustomerChoice",true,false)
	check(choice is OptionButton,"customer choice")
	if choice is OptionButton:
		for i in choice.item_count:
			if choice.get_item_text(i).contains("海辺商店"): choice.select(i); choice.item_selected.emit(i); break
	fill("BusinessOrderTotal","18600")
	press("BusinessSave")
	await frames(8)
	check(pc.browser_response.contains("18600") and pc.browser_response.contains("海辺商店"),"order saved through UI")
	await snap("order-saved")
	press("BusinessBack")
	await frames(5)
	await snap("order-list")
	pc._browse_url("https://intranet.client.test/accounting",true)
	await frames(6)
	press("BusinessNewLedger")
	await frames(4)
	fill("BusinessLedgerDate","2026-09-19"); fill("BusinessLedgerAmount","18600")
	press("BusinessSave")
	await frames(8)
	check(pc.browser_response.contains("81400"),"derived balance visible")
	await snap("ledger-saved")
	if failures.is_empty(): print("BUSINESS_TRANSACTIONS_UI_PASS")
	else: print("BUSINESS_TRANSACTIONS_UI_FAIL ",failures)
	quit(0 if failures.is_empty() else 1)

func press(node_name: String) -> void:
	var button = pc.widgets.browser.page.find_child(node_name,true,false)
	check(button is BaseButton,"button "+node_name)
	if button is BaseButton: button.pressed.emit()

func fill(node_name: String, value: String) -> void:
	var input = pc.widgets.browser.page.find_child(node_name,true,false)
	check(input is LineEdit,"input "+node_name)
	if input is LineEdit: input.text=value; input.text_changed.emit(value)
