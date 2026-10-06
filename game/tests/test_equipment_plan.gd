extends SceneTree

## Synthetic funded-company/node regression. This does not replace native
## floor-plan input, furnished-office collision, or player usability checks.
const DELIVERY = preload("res://scripts/equipment_delivery.gd")
const POSITION := [2.7, 0.0, 2.4]
const YAW := PI

class TestWorld extends Node3D:
	var upgrade_collisions: Dictionary = {}

var failures: Array[String] = []
var game: Node
var world: Node3D
var delivery: Node3D
var save_files: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("EQUIPMENT_PLAN: " + label)

func snapshot() -> Dictionary:
	# Normalize JSON number types across a real save/load without ignoring data.
	return JSON.parse_string(JSON.stringify({"cash":game.state.cash,
		"profit":game.state.profit, "history":game.state.history,
		"billing":game.state.get("billing", {}), "equipment":game.state.equipment,
		"orders":game.state.delivery_orders, "staff_capacity":game.staff_capacity(),
		"contract_capacity":game.contract_capacity()}))

func unmount_delivery() -> void:
	if not is_instance_valid(delivery): return
	# Use the production material-release path for a live placement ghost.
	delivery._release_visual(delivery)
	world.remove_child(delivery)
	delivery = null

func mount_delivery() -> void:
	unmount_delivery()
	delivery = DELIVERY.new()
	world.add_child(delivery)
	delivery.setup(game)

func prepare_company(suffix: String) -> bool:
	unmount_delivery()
	game.save_path = "user://qa-equipment-plan-%s-%s.json" % [OS.get_process_id(), suffix]
	game.backup_path = game.save_path + ".bak"
	game.previous_path = game.save_path + ".previous"
	game.settings_path = game.save_path + ".settings"
	for path in [game.save_path, game.backup_path, game.previous_path, game.settings_path, game.save_path + ".tmp"]:
		save_files.append(str(path))
	if not game.new_game():
		check(false, "isolated company saves")
		return false
	game.state.cash = 40000 # Only the fixture's funds are synthetic.
	if not game.buy_equipment("teamdesk"):
		check(false, "desk purchased through Game API")
		return false
	game.set_delivery_clock_paused(false)
	game.advance_delivery(30.0)
	check(game.save_game(), "arrived order is saved")
	mount_delivery()
	check(str(game.delivery_for("teamdesk").get("status", "")) == "ready"
		and int(game.state.cash) == 24000 and game.staff_capacity() == 0,
		"purchase costs 16000; arrival alone does not open a staff seat")
	return true

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"):
		push_error("EQUIPMENT_PLAN requires isolated QA storage")
		quit(2)
		return
	game.set_process(false)
	world = TestWorld.new()
	root.add_child(world)
	await normal_install()
	await interrupted_install()
	unmount_delivery()
	await process_frame
	world.free()
	for path in save_files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("EQUIPMENT_PLAN failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func normal_install() -> void:
	if not prepare_company("normal"): return
	await physics_frame
	var before := snapshot()
	var saved_hash: String = FileAccess.get_sha256(game.save_path)
	var invalid_position := [-0.5, 0.0, -1.0] # Existing fixed desk, not free floor.
	var reason: String = delivery.plan_error("teamdesk", invalid_position, YAW)
	var rejected: Dictionary = delivery.install_from_plan("teamdesk", invalid_position, YAW)
	check(not reason.is_empty() and not bool(rejected.get("ok", false))
		and snapshot() == before and FileAccess.get_sha256(game.save_path) == saved_hash,
		"invalid floor choice leaves cash, order, capacity and saved bytes untouched")
	check(delivery.plan_error("teamdesk", POSITION, YAW).is_empty() and snapshot() == before,
		"valid plan preview is read-only")
	var installed: Dictionary = delivery.install_from_plan("teamdesk", POSITION, YAW)
	check(bool(installed.get("ok", false)) and game.staff_capacity() == 1
		and game.contract_capacity() == 5 and game.state.equipment.count("teamdesk") == 1,
		"normal plan installs one desk and opens its real staffing and contract capacity")
	var after := snapshot()
	var order: Dictionary = game.state.delivery_orders[0]
	var saved_position: Array = order.get("install_position", [])
	var same_position: bool = saved_position.size() == POSITION.size()
	if same_position:
		# Vector3 uses single precision; this tolerates roundoff, not grid snapping.
		for index in POSITION.size():
			same_position = same_position and absf(float(saved_position[index]) - float(POSITION[index])) <= 0.00001
	check(str(order.get("status", "")) == "installed"
		and same_position
		and is_equal_approx(float(order.get("rotation_y", 0)), YAW)
		and after.cash == before.cash and after.history == before.history,
		"floor position and orientation persist without a second purchase")
	check(game.load_game() and snapshot() == after, "installed desk, capacity and accounting survive JSON reload")
	mount_delivery()
	saved_hash = FileAccess.get_sha256(game.save_path)
	var duplicate: Dictionary = delivery.install_from_plan("teamdesk", POSITION, YAW)
	check(not bool(duplicate.get("ok", false)) and snapshot() == after
		and FileAccess.get_sha256(game.save_path) == saved_hash,
		"repeat plan install cannot create another desk, fee or capacity")

func interrupted_install() -> void:
	if not prepare_company("interrupted"): return
	await physics_frame
	check(delivery.interact("pickup", "teamdesk") and delivery.interact("place_start", "teamdesk"),
		"ordinary pickup and placement create the interrupted saved order")
	var before := snapshot()
	var saved_hash: String = FileAccess.get_sha256(game.save_path)
	var saved_path: String = game.save_path
	mount_delivery() # Rebuilt UI has no transient placement ghost.
	check(not delivery.is_placing() and str(game.delivery_for("teamdesk").get("status", "")) == "placing",
		"saved placing order is authoritative after presentation is rebuilt")
	# A regular save file cannot also be a directory: fail the real write safely.
	game.save_path = saved_path + "/blocked.json"
	var failed: Dictionary = delivery.install_from_plan("teamdesk", POSITION, YAW)
	game.save_path = saved_path
	check(not bool(failed.get("ok", false)) and not str(failed.get("error", "")).is_empty()
		and snapshot() == before and game.staff_capacity() == 0
		and FileAccess.get_sha256(saved_path) == saved_hash,
		"failed installation save restores the order and grants no capacity or fee")
	check(game.load_game(), "interrupted placing save reloads through Game")
	# Existing save compatibility puts an uninstalled carried/placing box back at
	# the receiving point; the plan must resume that order, not mint another one.
	check(str(game.delivery_for("teamdesk").get("status", "")) == "ready"
		and game.state.delivery_orders.size() == 1 and game.staff_capacity() == 0
		and int(game.state.cash) == int(before.cash) and snapshot().history == before.history,
		"save resume returns the same paid box to receiving without installation effects")
	mount_delivery()
	await physics_frame
	var retried: Dictionary = delivery.install_from_plan("teamdesk", POSITION, YAW)
	check(bool(retried.get("ok", false)) and game.state.equipment.count("teamdesk") == 1
		and game.staff_capacity() == 1 and game.contract_capacity() == 5
		and int(game.state.cash) == int(before.cash) and snapshot().history == before.history,
		"retry completes installation exactly once after write failure and resume")
	var completed := snapshot()
	check(game.load_game() and snapshot() == completed, "retried installation stays committed on next reload")
