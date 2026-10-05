extends RefCounted
## Shows only actual, durable contract measurements. Rendering performs no work.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("243944")
const MUTED := Color("677781")
const IDS := ["staff-read", "staff-write", "guest-read", "guest-write"]

class AccessStage extends Control:
	var text_factor := 1.0
	var results: Array = []
	var objects: Dictionary = {}
	func _ready() -> void:
		resized.connect(layout)
		layout()
	func layout() -> void:
		if size.x <= 1: return
		var w := size.x
		for i in results.size():
			var id := str(results[i].id)
			var y := row_y(i)
			var button: Button = objects[id].button
			button.position = Vector2(w * 0.29, y - 17 * text_factor)
			button.size = Vector2(w * 0.25, 34 * text_factor)
			var label: Label = objects[id].label
			label.position = Vector2(w * 0.56, y - 20 * text_factor)
			label.size = Vector2(w * 0.22, 44 * text_factor)
		for pair in [["staff", 0.23], ["guest", 0.74]]:
			var label: Label = objects[pair[0]]
			label.position = Vector2(0, size.y * float(pair[1]) + 19 * text_factor)
			label.size = Vector2(w * 0.20, 28 * text_factor)
		var folder: Button = objects.folder
		folder.position = Vector2(w * 0.81, size.y * 0.5 - 35 * text_factor)
		folder.size = Vector2(w * 0.18, 52 * text_factor)
		var edit: Button = objects.edit
		edit.position = Vector2(w * 0.81, size.y * 0.5 + 23 * text_factor)
		edit.size = Vector2(w * 0.18, 30 * text_factor)
		queue_redraw()
	func row_y(index: int) -> float:
		return size.y * [0.105, 0.335, 0.615, 0.845][index]
	func _draw() -> void:
		var w := size.x
		for actor in 2:
			var center := Vector2(w * 0.10, size.y * (0.23 if actor == 0 else 0.74))
			var monitor := Rect2(center - Vector2(24,18) * text_factor, Vector2(48,31) * text_factor)
			draw_style_box(UI.style(Color("e4eff5"), Color("527486"), 4,4,3), monitor)
			draw_line(center + Vector2(0,13)*text_factor, center + Vector2(0,19)*text_factor, INK, 2*text_factor, true)
			draw_line(center + Vector2(-14,19)*text_factor, center + Vector2(14,19)*text_factor, INK, 2*text_factor, true)
		for i in results.size():
			var result: Dictionary = results[i]
			var y := row_y(i)
			var actor_y := size.y * (0.23 if i < 2 else 0.74)
			var path := PackedVector2Array([Vector2(w*0.17,actor_y), Vector2(w*0.23,y), Vector2(w*0.29,y)])
			var status := str(result.status)
			var color := MUTED if status in ["unknown","stale","error"] else Color("28784e") if result.passed == true else Color("a1482c")
			if status in ["unknown","stale"]:
				_dashed(path[0],path[1],color); _dashed(path[1],path[2],color)
			else: draw_polyline(path,color,2*text_factor,true)
			var start := Vector2(w*0.78,y)
			var end := Vector2(w*0.81,size.y*0.5-9*text_factor)
			if status in ["unknown","stale"]: _dashed(start,end,color)
			else: draw_line(start,end,color,2*text_factor,true)
			var marker := path[1]
			if status in ["denied","error"]:
				draw_circle(marker,8*text_factor,Color("eef0f2"))
				draw_line(marker-Vector2(5,5)*text_factor,marker+Vector2(5,5)*text_factor,color,2*text_factor,true)
				draw_line(marker+Vector2(-5,5)*text_factor,marker+Vector2(5,-5)*text_factor,color,2*text_factor,true)
			elif status == "allowed":
				var tip := path[2] if str(result.operation) == "write" else path[0]
				var direction := 1.0 if str(result.operation) == "write" else -1.0
				draw_colored_polygon(PackedVector2Array([tip,tip+Vector2(-7*direction,-4)*text_factor,tip+Vector2(-7*direction,4)*text_factor]),color)
			elif status == "stale":
				draw_arc(marker,7*text_factor,0,TAU,24,color,2*text_factor,true)
				draw_line(marker,marker+Vector2(0,-5)*text_factor,color,2*text_factor,true)
				draw_line(marker,marker+Vector2(4,0)*text_factor,color,2*text_factor,true)
		var f := Rect2(w*0.805,size.y*0.5-45*text_factor,w*0.19,64*text_factor)
		draw_rect(Rect2(f.position+Vector2(5,-7)*text_factor,Vector2(25,8)*text_factor),Color("a9cddd"))
		draw_style_box(UI.style(Color("edf6fb"),Color("6f9eaf"),3,3,4),f)
	func _dashed(start: Vector2, end: Vector2, color: Color) -> void:
		var length := start.distance_to(end)
		if length <= 0: return
		var direction := (end-start)/length
		for step in range(0,ceili(length),int(10*text_factor)):
			draw_line(start+direction*step,start+direction*minf(step+5*text_factor,length),color,1.5*text_factor,true)

static func _command(probe: Dictionary, id: String) -> bool:
	var actor := "staff" if id.begins_with("staff-") else "guest"
	var suffixes: Array = ["ls"] if id.ends_with("-read") else ['"put /srv/data/orders.csv"', "'put /srv/data/orders.csv'"]
	for host in ["client","files01.client.test"]:
		for suffix in suffixes:
			if str(probe.get("command","")) == "smbclient //"+host+"/share -U "+actor+" -c "+str(suffix): return true
	return false

static func _access(output: String, writing: bool) -> String:
	var value := output.strip_edges()
	if value == "NT_STATUS_ACCESS_DENIED": return "denied"
	if value.begins_with("NT_STATUS_") or value.begins_with("smbclient:") or value.begins_with("put:") or value.begins_with("usage:") or value.begins_with("{"): return "error"
	if writing: return "allowed" if value == "putting file orders.csv: OK" else "unknown"
	if value == "0 files": return "allowed"
	var files := value.split("\n",false)
	if "report.txt" not in files: return "unknown"
	for filename in files:
		if not str(filename).is_valid_filename(): return "unknown"
	return "allowed"

static func project(probes: Array) -> Array:
	var result: Array = []
	for id in IDS:
		var probe: Dictionary = {}
		for p in probes:
			if p is Dictionary and str(p.get("id","")) == id and _command(p,id): probe = p; break
		var recorded := bool(probe.get("recorded",false))
		var fresh := recorded and bool(probe.get("fresh",false))
		var raw := str(probe.get("result","")) if recorded else ""
		var status := "stale" if recorded and not fresh else _access(raw,id.ends_with("-write")) if fresh else "unknown"
		var expectation := str(probe.get("expectation",""))
		var requirement := "deny" if expectation == "DENIED" else "allow" if expectation in ["OK","report.txt"] else "unknown"
		var passed: Variant = null
		if fresh and status in ["allowed","denied"] and requirement != "unknown":
			passed = bool(probe.get("passed",false)) and ((status == "allowed" and requirement == "allow") or (status == "denied" and requirement == "deny"))
		result.append({"id":id,"actor":"staff" if id.begins_with("staff-") else "guest","operation":"write" if id.ends_with("-write") else "read","recorded":recorded,"fresh":fresh,"status":status,"requirement":requirement,"passed":passed,"raw":raw,"command":str(probe.get("command",""))})
	return result

static func should_render_home(d, parsed: Dictionary, probes: Array) -> bool:
	var shares: Dictionary = parsed.get("values",{}).get("shares",{})
	if not str(d.samba_ui.get("selected_share","")).is_empty() or shares.size() != 1 or not shares.has("share"): return false
	if int(d.game._current_chapter()) != 0: return false
	for p in project(probes):
		if str(p.command).is_empty(): return false
	return true

static func build(d, parent: VBoxContainer, probes: Array, applied_path: String) -> void:
	var body := VBoxContainer.new(); body.name = "SambaAccessBoard"; body.add_theme_constant_override("separation",4); parent.add_child(body)
	var stage := AccessStage.new(); stage.name = "SambaAccessPaths"; stage.text_factor = float(d.game.settings.get("text_scale",1.0)); stage.results = project(probes)
	stage.custom_minimum_size = Vector2(0,188*stage.text_factor); stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var error: Dictionary = d.samba_ui.get("probe_action_error",{})
	for actor in ["staff","guest"]:
		var label: Label = d._label("社員 · staff" if actor == "staff" else "来客 · guest",12,INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stage.add_child(label); stage.objects[actor] = label
	for p in stage.results:
		var id := str(p.id)
		var button: Button = d._button("閲覧" if str(p.operation) == "read" else "保存",_run.bind(d,id))
		button.name = "SambaAccess_"+id; button.icon = UI.symbol("file"); button.tooltip_text = str(p.command)+"\n"+str(p.raw)
		button.disabled = d.game.current_done() or not bool(d.game.vm_info().get("connected",false))
		stage.add_child(button)
		var names := {"unknown":"? 未測定","stale":"◷ 再検査","allowed":"→ 許可","denied":"× 拒否","error":"! 実行エラー"}
		var actual := str(names.get(str(p.status),"? 未測定"))
		if p.passed != null: actual += "  ✓" if p.passed == true else "  !"
		var failed_action := str(error.get("id","")) == id
		if failed_action: actual = "! 保存失敗" if str(error.error) == "save_failed" else "! 未接続"
		var wanted := "依頼: 許可" if str(p.requirement) == "allow" else "依頼: 拒否" if str(p.requirement) == "deny" else "依頼: 不明"
		var label: Label = d._label(actual+"\n"+wanted,12,INK if p.passed == true else Color("a1482c") if p.passed == false else MUTED)
		label.name = "SambaAccessResult_"+id; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.minimum_size_changed.connect(stage.layout)
		if failed_action:
			label.name = "SambaAccessActionError"; label.tooltip_text = str(error.message)
			label.add_theme_color_override("font_color",Color("a1482c"))
		stage.add_child(label); stage.objects[id] = {"button":button,"label":label}
	var folder: Button = d._button("share",func(): _select(d))
	folder.name = "SambaShare_share"; folder.tooltip_text = "//"+str(d.game.vm_info().host)+"/share → "+applied_path
	stage.add_child(folder); stage.objects.folder = folder
	var edit: Button = d._button("編集",func(): _select(d)); edit.name = "SambaEdit_share"; stage.add_child(edit); stage.objects.edit = edit
	body.add_child(stage)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation",6); body.add_child(actions)
	var config: Button = d._button("設定ファイルを開く",d._open_config); config.name = "SambaOpenConfig"; actions.add_child(config)
	var files: Button = d._button("ファイルを開く",func(): d._open_samba_share("share")); files.name = "SambaOpenShare_share"; actions.add_child(files)
	var details: VBoxContainer = d._disclosure(body,"測定コマンドと応答"); details.name = "SambaAccessDetails"
	if not error.is_empty():
		var feedback: Label = d._label(str(error.message),12,Color("a1482c")); feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; details.add_child(feedback)
	for p in stage.results:
		var raw: Label = d._label(str(p.command)+"\n"+(str(p.raw) if bool(p.recorded) else "未測定"),12,INK); raw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; details.add_child(raw)
	var focus := str(d.samba_ui.get("_focus_probe_id",""))
	if not focus.is_empty(): d.samba_ui.erase("_focus_probe_id"); _focus.call_deferred(d,stage,focus)

static func _select(d) -> void:
	d.samba_ui.selected_share = "share"; d.samba_ui.tab = "shares"; d.samba_ui.workspace = "config"; d._render_samba()

static func _run(d, id: String) -> void:
	d.samba_ui["_focus_probe_id"] = id; d.samba_ui.erase("probe_action_error")
	var was_refreshing: bool = d.refreshing
	d.refreshing = true
	var output := str(d.game.run_diagnostic(id))
	d.refreshing = was_refreshing
	d._invalidate_smb()
	var error: Variant = JSON.parse_string(output) if output.strip_edges().begins_with("{") else null
	if error is Dictionary and str(error.get("error","")) in ["save_failed","hardware_unavailable"]:
		var message := "測定を保存できません。再試行できます。" if str(error.error) == "save_failed" else "顧客端末に接続できません。"
		d.samba_ui.probe_action_error = {"id":id,"message":message,"error":str(error.error)}
		d._notify(message)
	d._render_samba()
	if d.widgets.has("verify"): d._refresh_checks()
	if d.widgets.has("monitor"): d._refresh_monitor()

static func _focus(d, stage: Control, id: String) -> void:
	for _i in 3:
		await d.get_tree().process_frame
		if not is_instance_valid(stage): return
	var target := stage.find_child("SambaAccess_"+id,true,false) as Control
	if target == null or not target.is_visible_in_tree(): return
	target.grab_focus()
	var ancestor: Node = target.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(target)
		ancestor = ancestor.get_parent()
