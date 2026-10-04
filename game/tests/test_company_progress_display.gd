extends SceneTree
## Native board review plus view-only award fixtures. The fixture images do not
## claim gameplay completion; the integration journey covers earning the goals.

const DISPLAY = preload("res://scripts/company_progress_display.gd")
var game
var office
var failures: Array[String] = []
var assertions := 0
var capture_enabled := "--capture" in OS.get_cmdline_user_args()
var narrow := "--narrow" in OS.get_cmdline_user_args()

func _init() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("Company progress display timeout"); quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); print("FAIL ", label)

func frames(count := 6) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	if not capture_enabled: return
	await frames(12); await RenderingServer.frame_post_draw
	var folder := OS.get_environment("WHL_CAPTURE_DIR")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../artifacts/company-progress")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name + ("-narrow" if narrow else "-wide") + ".png")) == OK, "capture " + name)

func run() -> void:
	game = root.get_node("Game")
	if not str(game.save_path).begins_with("user://qa-"): quit(2); return
	game.set_process(false)
	check(game.new_game(), "isolated game")
	check(game.choose_strategy("advisory") and game.start_free_career(), "real new company")
	game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0}, false)
	office = load("res://scripts/office.gd").new(); root.add_child(office)
	await frames(12)
	root.size = Vector2i(960,600) if narrow else Vector2i(1920,1080)
	office.started = true; office.ui.controls.menu.hide(); office.ui.current_kind = ""
	office.player.set_physics_process(false); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	office.player.position = Vector3(3.4,0.05,-1.8)
	office.player.camera.look_at(Vector3(3.4,2.0,-4.74),Vector3.UP)
	var before := JSON.stringify(game.state)
	office._state_changed(); office._state_changed()
	check(JSON.stringify(game.state) == before, "office progress refresh never mutates world state")
	check(is_instance_valid(office.company_progress) and not office.mission_board.visible, "new visible progress replaces old count label")
	check(not bool(office.company_progress.get_meta("earned_first_delivery", false)), "no first-delivery award on new game")
	await capture("01-new-company")
	var display = office.company_progress
	var metadata := {"day":8,"level":3,"catalog_count":61}
	var fixture := {"earned_goals":{},"opportunities":[],"goals":[{"id":"first_delivery","title":"開業の一歩","progress":1.0,"complete":true},{"id":"independent_lab","title":"頼られる技術会社","progress":0.6},{"id":"sustainable_team","title":"続く会社へ","progress":0.2}]}
	var unchanged := JSON.stringify(fixture)
	check(display.sync(fixture,metadata,true).is_empty(), "conditions alone do not award tokens")
	check(not bool(display.get_meta("earned_first_delivery", false)), "uncommitted goal remains unearned")
	check(JSON.stringify(fixture) == unchanged, "display leaves passed view intact")
	fixture.earned_goals = {"first_delivery":{"day":1,"title":"開業の一歩"}}
	fixture.opportunities = [{"status":"ready","client":"つばさ文具"}]
	var gained: Array[String] = display.sync(fixture,metadata,true)
	check(gained == ["開業の一歩"], "one live newly saved goal gets one celebration")
	check(bool(display.get_meta("earned_first_delivery", false)), "saved award gets visible token")
	check(display.sync(fixture,metadata,true).is_empty(), "repeated change produces no repeat celebration")
	await create_timer(0.6).timeout
	check(display._tokens[0].scale.is_equal_approx(Vector3.ONE), "award animation settles without growing forever")
	check(str(display._status.text).contains("指名相談 1件"), "ready count comes from actual view status")
	await capture("02-earned-and-consultation-fixture")
	fixture.earned_goals.independent_lab = {"day":8,"title":"頼られる技術会社"}
	fixture.opportunities = [{"status":"paused","client":"つばさ文具"}]
	check(display.sync(fixture,metadata,false).is_empty(), "non-live reload produces no celebration")
	check(bool(display.get_meta("earned_independent_lab", false)), "non-live reload still restores token")
	check(str(display._status.text).contains("保留中"), "paused consultation is visibly distinguished")
	await capture("03-two-awards-paused-fixture")
	var restored = DISPLAY.new(); office.add_child(restored); restored.setup(office.font); restored.hide()
	check(restored.sync(fixture,metadata,true).is_empty(), "initial saved-game mount is silent even when live")
	check(JSON.stringify(game.state) == before, "fixtures never alter gameplay world")
	display.sync({"earned_goals":{},"goals":[],"opportunities":[]}, metadata, false)
	check(not bool(display.get_meta("earned_first_delivery", true)), "new company clears old visible awards")
	for value in display._bars: check(not value.visible, "zero progress bars disappear")
	print("COMPANY_PROGRESS_DISPLAY ", assertions, " assertions / ", failures.size(), " failures")
	office.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
