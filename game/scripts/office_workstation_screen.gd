extends Node3D
class_name OfficeWorkstationScreen

## A small, physical monitor surface for the office.  The viewport is kept
## separate from the desktop application so the room can show truthful work
## state without changing the saved game or stealing desktop focus.
const UI = preload("res://scripts/ui_theme.gd")
const SCREEN_SIZE := Vector2i(640, 360)

var game = null
var screen: Node3D
var workstation_id := ""
var viewport: SubViewport
var page: Control
var preview: Texture2D
var last_signature := ""
var preview_active := false

func setup(target: Node3D, game_ref, id: String) -> void:
	screen = target
	game = game_ref
	workstation_id = id
	name = "WorkstationScreen_%s" % id
	_build_viewport()
	_apply_texture()
	refresh(true)

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = SCREEN_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.handle_input_locally = false
	add_child(viewport)
	page = Control.new()
	page.name = "Desktop"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(page)
	var background := TextureRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://assets/ui/aoba-wallpaper-v16.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(background)
	var topbar := ColorRect.new()
	topbar.name = "Topbar"
	topbar.position = Vector2(48, 24)
	topbar.size = Vector2(544, 36)
	topbar.color = Color("f7f9fb")
	page.add_child(topbar)
	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(14, 6)
	title.size = Vector2(360, 24)
	title.add_theme_font_override("font", UI.font(600))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("263849"))
	title.text = UI.copy("workstation_app", "Operations")
	topbar.add_child(title)
	var connection_label := Label.new()
	connection_label.name = "Connection"
	connection_label.position = Vector2(430, 8)
	connection_label.size = Vector2(100, 22)
	connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	connection_label.add_theme_font_override("font", UI.font(400))
	connection_label.add_theme_font_size_override("font_size", 14)
	connection_label.add_theme_color_override("font_color", Color("607384"))
	connection_label.text = "LOCAL"
	topbar.add_child(connection_label)
	var panel := ColorRect.new()
	panel.name = "WorkPanel"
	panel.position = Vector2(48, 60)
	panel.size = Vector2(544, 244)
	panel.color = Color("ffffff")
	page.add_child(panel)
	var state_label := Label.new()
	state_label.name = "State"
	state_label.position = Vector2(18, 14)
	state_label.size = Vector2(508, 34)
	state_label.add_theme_font_override("font", UI.font(600))
	state_label.add_theme_font_size_override("font_size", 22)
	state_label.add_theme_color_override("font_color", Color("263849"))
	panel.add_child(state_label)
	var subject := Label.new()
	subject.name = "Subject"
	subject.position = Vector2(18, 56)
	subject.size = Vector2(508, 40)
	subject.add_theme_font_override("font", UI.font(600))
	subject.add_theme_font_size_override("font_size", 19)
	subject.add_theme_color_override("font_color", Color("263849"))
	panel.add_child(subject)
	var detail := Label.new()
	detail.name = "Detail"
	detail.position = Vector2(18, 104)
	detail.size = Vector2(508, 72)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_override("font", UI.font(400))
	detail.add_theme_font_size_override("font_size", 16)
	detail.add_theme_color_override("font_color", Color("536476"))
	panel.add_child(detail)
	var progress := ProgressBar.new()
	progress.name = "Progress"
	progress.position = Vector2(18, 190)
	progress.size = Vector2(508, 18)
	progress.show_percentage = false
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.add_theme_stylebox_override("background", UI.style(Color("cbd9d8"), Color.TRANSPARENT, 0, 0, 2))
	progress.add_theme_stylebox_override("fill", UI.style(Color("246b72"), Color.TRANSPARENT, 0, 0, 2))
	panel.add_child(progress)
	var footer := ColorRect.new()
	footer.name = "Taskbar"
	footer.position = Vector2(0, 324)
	footer.size = Vector2(640, 36)
	footer.color = Color("f7f9fb")
	page.add_child(footer)
	var task := Label.new()
	task.name = "Task"
	task.position = Vector2(18, 7)
	task.size = Vector2(500, 22)
	task.add_theme_font_override("font", UI.font(400))
	task.add_theme_font_size_override("font_size", 14)
	task.add_theme_color_override("font_color", Color("536476"))
	task.text = UI.copy("workstation_queue", "Work queue")
	footer.add_child(task)
	var day := Label.new()
	day.name = "Day"
	day.position = Vector2(520, 7)
	day.size = Vector2(102, 22)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	day.add_theme_font_override("font", UI.font(400))
	day.add_theme_font_size_override("font_size", 14)
	day.add_theme_color_override("font_color", Color("536476"))
	footer.add_child(day)
	var apps := HBoxContainer.new()
	apps.name = "AppIcons"
	apps.position = Vector2(270, 4)
	apps.size = Vector2(156, 28)
	apps.alignment = BoxContainer.ALIGNMENT_CENTER
	apps.add_theme_constant_override("separation", 8)
	footer.add_child(apps)
	for app_id in ["files", "terminal", "browser", "monitor"]:
		var icon := TextureRect.new()
		icon.name = "App_%s" % app_id
		icon.custom_minimum_size = Vector2(25, 25)
		icon.texture = UI.icon(app_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		apps.add_child(icon)

func _label(node_name: String) -> Label:
	return page.get_node("WorkPanel/%s" % node_name) as Label

func _assignment_for_screen() -> Dictionary:
	if game == null: return {}
	if workstation_id == "terminal":
		var current: Dictionary = game.state.get("assignments", {}).get("player", {})
		if not current.is_empty(): return current
		return game.work_status() if game.has_method("work_status") else {}
	var member_id := _member_id_for_screen()
	if not member_id.is_empty():
		var active: Dictionary = game.state.get("assignments", {}).get(member_id, {})
		if not active.is_empty() and str(active.get("status", "")) in ["working", "done"]: return game._dispatch_display(member_id, active)
		if game.has_method("dispatch_queue"):
			var pending: Array = game.dispatch_queue(member_id)
			if not pending.is_empty(): return pending[0]
	return {}

func _member_id_for_screen() -> String:
	if game == null: return ""
	if workstation_id in ["aya", "ren"]: return workstation_id
	if not game.has_method("team_members"): return ""
	for member in game.team_members():
		if not member is Dictionary: continue
		var member_id := str(member.get("id", ""))
		if game.has_method("staff_workplace") and str(game.staff_workplace(member_id)) == workstation_id: return member_id
	return ""

func _member_on_shift(member_id: String) -> bool:
	if game == null or member_id.is_empty() or member_id in ["aya", "ren"]: return true
	var staff: Dictionary = game.state.get("staff", {}).get(member_id, {})
	if staff.is_empty() or not bool(staff.get("active", false)): return false
	if not game.has_method("staff_shift_catalog"): return true
	var selected: Dictionary = {}
	for item in game.staff_shift_catalog():
		if str(item.get("id", "")) == str(staff.get("shift", "day")): selected = item; break
	var minute := int(game.state.get("clock_minutes", 540))
	return minute >= int(selected.get("start", 540)) and minute < int(selected.get("end", 1080))

func _queue_count() -> int:
	if game == null: return 0
	if workstation_id == "terminal":
		if game.has_method("contract_queue"): return game.contract_queue().size()
		return 0
	var member_id := _member_id_for_screen()
	if member_id.is_empty() or not game.has_method("dispatch_queue"): return 0
	return game.dispatch_queue(member_id).size()

func _contract_for(job: Dictionary) -> Dictionary:
	if game == null: return {}
	if job.is_empty() and workstation_id != "terminal": return {}
	if not str(job.get("title", "")).is_empty() or not str(job.get("client", "")).is_empty(): return job
	var contract_id := str(job.get("contract_id", job.get("id", "")))
	if contract_id.is_empty(): contract_id = str(game.state.get("current_contract_id", ""))
	var contexts: Dictionary = game.state.get("contract_contexts", {})
	if contexts.has(contract_id):
		var context: Dictionary = contexts.get(contract_id, {})
		var context_contract: Dictionary = context.get("contract", {})
		var context_result: Dictionary = context_contract.duplicate(true)
		context_result["targets"] = context.get("targets", [])
		return context_result
	if game.has_method("contract_queue"):
		for item in game.contract_queue():
			if str(item.get("id", item.get("contract_id", ""))) == contract_id: return item
	if game.has_method("mission") and contract_id == str(game.state.get("current_contract_id", "")): return game.mission()
	return {}

func _signature() -> String:
	if game == null: return workstation_id
	var job: Dictionary = _assignment_for_screen()
	var mission: Dictionary = _contract_for(job)
	return JSON.stringify({
		"day": int(game.state.get("day", 1)),
		"clock": int(game.state.get("clock_minutes", 0)),
		"accepted": bool(game.state.get("accepted", false)),
		"done": bool(game.current_done()) if game.has_method("current_done") else false,
		"job": job,
		"mission": mission,
		"preview": preview_active
	})

func refresh(force := false) -> void:
	if preview_active or page == null: return
	var current := _signature()
	if not force and current == last_signature: return
	last_signature = current
	_render_state()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _render_state() -> void:
	var job: Dictionary = _assignment_for_screen()
	var mission: Dictionary = _contract_for(job)
	var status := str(job.get("status", job.get("phase", "")))
	if workstation_id == "terminal" and game != null and game.has_method("current_done") and bool(game.current_done()): status = "done"
	var state_text := UI.copy("workstation_waiting", "Waiting")
	var member_id := _member_id_for_screen()
	var hardware_ready := true
	if not job.is_empty() and game != null:
		if workstation_id == "terminal" and game.has_method("_customer_hardware_connected"): hardware_ready = bool(game._customer_hardware_connected())
		elif workstation_id != "terminal" and game.has_method("_colleague_hardware_connected"): hardware_ready = bool(game._colleague_hardware_connected(job))
	if not hardware_ready: state_text = UI.copy("workstation_hardware_wait", "Hardware unavailable")
	elif status == "working": state_text = UI.copy("workstation_working", "Working")
	elif status == "done": state_text = UI.copy("workstation_done", "Done")
	elif job.is_empty() and not member_id.is_empty() and not _member_on_shift(member_id): state_text = UI.copy("workstation_off_shift", "Off shift")
	elif job.is_empty() and game != null and bool(game.state.get("accepted", false)): state_text = UI.copy("workstation_waiting", "Waiting")
	elif job.is_empty(): state_text = UI.copy("workstation_waiting", "Waiting")
	_label("State").text = state_text
	var title := str(mission.get("title", mission.get("name", "")))
	var client := str(mission.get("client", ""))
	if title.is_empty() and client.is_empty():
		_label("Subject").text = UI.copy("workstation_waiting", "No active work")
		_label("Detail").text = UI.copy("workstation_queue") % _queue_count()
	else:
		_label("Subject").text = client + ("  /  " if not client.is_empty() and not title.is_empty() else "") + title
		var target_default: int = 0
		if game != null: target_default = int(game.state.get("target_index", 0))
		var target_index: int = int(job.get("target_index", job.get("target", target_default)))
		var target_values: Array = mission.get("targets", []) if mission.get("targets", []) is Array else []
		if target_values.is_empty() and game != null and game.state.get("targets", []) is Array: target_values = game.state.get("targets", [])
		var target_count: int = target_values.size()
		var remaining := int(round(float(job.get("remaining", job.get("work_minutes", 0.0)))))
		var target_name := str(job.get("target_name", ""))
		var target_text := UI.copy("ops_target", "Target")
		if not target_name.is_empty(): target_text += ": " + target_name
		var remaining_minutes := float(job.get("remaining", job.get("work_minutes", 0.0)))
		if workstation_id != "terminal" and game != null and game.has_method("_crew_minutes"):
			var raw_total := maxf(0.001, float(job.get("total", 1.0)))
			remaining_minutes = game._crew_minutes(job) * float(job.get("remaining", raw_total)) / raw_total
		var remaining_text := UI.copy("dispatch_remaining", "Remaining %d min") % int(round(remaining_minutes))
		_label("Detail").text = "%s\n%s" % [target_text if not target_name.is_empty() else "%s %d/%d" % [target_text, target_index + 1, maxi(target_count, 1)], remaining_text]
	var total := maxf(1.0, float(job.get("total", job.get("work_minutes", 1.0))))
	var remaining_value := clampf(float(job.get("remaining", total)), 0.0, total)
	var progress := page.get_node("WorkPanel/Progress") as ProgressBar
	progress.value = 1.0 - remaining_value / total if status == "working" else 1.0 if status == "done" else 0.0
	var day := int(game.state.get("day", 1)) if game != null else 1
	page.get_node("Taskbar/Task").text = UI.copy("workstation_queue", "Queue: %d") % _queue_count()
	page.get_node("Taskbar/Day").text = "DAY %d" % day

func _apply_texture() -> void:
	var texture: Texture2D = preview if preview_active else viewport.get_texture()
	if screen == null or texture == null: return
	for mesh in screen.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.mesh.get_surface_count() < 2: continue
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 1.0
		material.uv1_scale = Vector3(1.0 / 14.92664, 1.0 / 9.19924, 1.0)
		material.uv1_offset = Vector3(-0.26676 / 14.92664, 10.562574 / 9.19924, 0.0)
		mesh.set_surface_override_material(1, material)

func set_desktop_preview(texture: Texture2D) -> void:
	preview = texture
	preview_active = texture != null
	_apply_texture()
	if preview_active:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func clear_desktop_preview() -> void:
	set_desktop_preview(null)
	refresh(true)
