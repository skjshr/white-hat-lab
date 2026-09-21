extends SceneTree

const VISUALS = preload("res://scripts/equipment_visuals.gd")
const ART = preload("res://scripts/equipment_art.gd")
const RULES = preload("res://scripts/placement_rules.gd")
var failures: Array[String] = []
var game
var office

func _init() -> void:
	create_timer(55).timeout.connect(func(): push_error("equipment catalog QA timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count: int = 3) -> void:
	for i in count: await process_frame
	await physics_frame

func geometry(node: Node, transform: Transform3D = Transform3D.IDENTITY) -> Array:
	var entries: Array = []
	var next := transform
	if node is Node3D: next = transform * node.transform
	if node is MeshInstance3D: entries.append([node.mesh.get_aabb(), next])
	for child in node.get_children(): entries.append_array(geometry(child, next))
	return entries

func choose_floor(id: String) -> Array:
	# Prefer spacious annex positions for desks; evaluate real collision and routes.
	for yaw in [0.0, PI, PI / 2.0, PI * 1.5]:
		for x in [7.4, 10.5, 9.0, -2.0, 1.5, -4.6, 3.7, 0.0]:
			for z in [1.0, 3.9, 2.1, -3.7, -0.1, -1.8]:
				office.delivery.update_placement_preview([x, 0.0, z], yaw)
				if office.delivery.placement_valid(): return [x, 0.0, z, yaw]
	return []

func deliver_carton(id: String) -> bool:
	# The fixture pauses the office process while it drives delivery directly;
	# explicitly open the delivery clock and refresh the world projection before
	# exercising the real pickup path.
	game.set_delivery_clock_paused(false)
	game.set_delivery_clock_enabled(false)
	game.advance_delivery(999.0)
	office.delivery.sync_orders(game.delivery_orders())
	return str(game.delivery_for(id).get("status", "")) == "ready"

func run() -> void:
	game = root.get_node("Game"); game.set_process(false)
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	check(game.new_game(), "isolated company")
	game.state.cash = 200000; game.state.office_expansion = {"status":"open", "price":28000}
	office = load("res://scripts/office.gd").new(); root.add_child(office)
	await frames(8)
	office.started = true; office.set_process(false); office.player.set_physics_process(false)
	office.player.position = Vector3(0,0.05,4.1)
	office.ui.controls.menu.hide(); office.ui.current_kind = ""
	for id in ["teamdesk", "annexdesk_a", "annexdesk_b", "workstation", "diagnostic", "backup", "plant"]:
		var balance: int = game.state.cash; var price: int = game.equipment_price(id)
		check(game.buy_equipment(id) and int(game.state.cash) == balance - price, "purchase " + id)
		check(id not in game.state.equipment, "no effect before installation " + id)
		check(deliver_carton(id), "delivery ready " + id)
		var picked: bool = office.delivery.interact("pickup", id)
		check(picked, "pickup delivered carton " + id)
		if not picked: continue
		var unpacked: bool = office.delivery.interact("place_start", id)
		check(unpacked, "unpack full equipment " + id)
		if not unpacked: continue
		await frames()
		var source: Node3D = VISUALS.build(id)
		var preview: Node3D = office.delivery._ghost
		if not is_instance_valid(preview):
			check(false, "ghost exists " + id)
			source.free()
			continue
		var preview_xform: Transform3D = preview.transform; preview.transform = Transform3D.IDENTITY
		check(geometry(source) == geometry(preview), "ghost is catalog factory geometry " + id)
		preview.transform = preview_xform
		var catalog: Texture2D = ART.icon(id)
		check(catalog != null and catalog.get_width() == 512, "rendered catalog image " + id)
		var position := choose_floor(id)
		check(not position.is_empty(), "has valid place in furnished office " + id)
		if position.is_empty(): source.free(); continue
		check(office.delivery.interact("confirm", id), "place equipment " + id)
		await frames()
		var installed: Node3D = office.upgrades.get(id) if office.upgrades is Dictionary else null
		if not is_instance_valid(installed):
			check(false, "installed node exists " + id)
			source.free()
			continue
		var saved_transform: Transform3D = installed.transform; installed.transform = Transform3D.IDENTITY
		check(geometry(source) == geometry(installed), "installed equals factory geometry " + id)
		installed.transform = saved_transform
		check(id in game.state.equipment and installed.visible, "visible installed effect " + id)
		print("PLACED ", id, " ", position)
		source.free()
	check(game.buy_equipment("monitor"), "purchase monitor")
	check(deliver_carton("monitor"), "delivery ready monitor")
	var monitor_picked: bool = office.delivery.interact("pickup", "monitor")
	var monitor_unpacked: bool = monitor_picked and office.delivery.interact("place_start", "monitor")
	check(monitor_unpacked, "unpack monitor")
	if not monitor_unpacked:
		print("EQUIPMENT_CATALOG_DELIVERY failures=", failures.size())
		office.queue_free(); await frames()
		quit(1)
	office.delivery.update_placement_preview([0.0,0.8,-1.03],PI/2.0)
	check(office.delivery.placement_valid(), "monitor fits actual desk " + office.delivery.placement_reason())
	check(office.delivery.interact("confirm", "monitor"), "install tabletop monitor")
	await frames()
	check(office.upgrades.monitor.position.is_equal_approx(Vector3(0,0.8,-1.03)), "tabletop monitor position survives rendering")
	check(office.delivery.interact("place_start", "monitor"), "installed monitor can move")
	var yaw: float = office.delivery._placing_rotation
	check(office.delivery.interact("rotate_right", "monitor") and is_equal_approx(office.delivery._placing_rotation, yaw+PI/12.0), "wheel rotates monitor 15 degrees")
	office.delivery.update_placement_preview([0.3,0.8,-1.0],0.0)
	check(not office.delivery.placement_valid() and not office.delivery.interact("confirm", "monitor"), "desk overhang blocked")
	check(office.delivery.interact("cancel", "monitor"), "cancel keeps installed monitor")
	check(ART.icon("monitor") != null, "monitor catalog exists")
	check(game.save_game() and game.load_game(), "all installed equipment reloads")
	for id in ["teamdesk", "annexdesk_a", "annexdesk_b", "workstation", "diagnostic", "backup", "plant", "monitor"]:
		check(id in game.state.equipment, "ownership survives reload " + id)
	print("EQUIPMENT_CATALOG_DELIVERY failures=", failures.size())
	office.queue_free(); await frames()
	quit(0 if failures.is_empty() else 1)
