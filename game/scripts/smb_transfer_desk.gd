extends Control
## Two endpoints and the actual response. Painting never requests remote data.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("243641")
const BLUE := Color("0067c0")
const RED := Color("a82f33")
const GREEN := Color("236854")
var d
var mode := "upload"
var factor := 1.0
var items: Dictionary = {}
var projected: Dictionary = {}
var paper_height := 86.0
var footer_y := 164.0
var drop_hover := false
var source_field: LineEdit
var destination_field: LineEdit

static func response_state(record: Dictionary) -> String:
	if record.is_empty(): return "unmeasured"
	var response := str(record.get("response",""))
	if bool(record.get("success",false)): return "saved"
	if response.contains("save_failed"): return "save_failed"
	if response == "NT_STATUS_ACCESS_DENIED": return "denied"
	if response == "NT_STATUS_CONNECTION_REFUSED": return "connection"
	if response.begins_with("put: local file missing"): return "missing"
	if response.contains("OBJECT_NAME_NOT_FOUND"): return "missing_remote"
	if response.contains("INVALID_PARAMETER") or response.contains("BAD_NETWORK_NAME"): return "invalid"
	return "failed"

func setup(desktop, direction: String, source: LineEdit, destination: LineEdit) -> void:
	d = desktop; mode = direction; source_field = source; destination_field = destination
	name = "SmbTransferDesk"; factor = float(d.game.settings.get("text_scale",1.0)); size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label("SmbTransferLocalTitle","編集コピー" if mode == "upload" else "取得先",13)
	_label("SmbTransferRemoteTitle","共有 · " + str(d.samba_ui.get("access_share","share")),13)
	_label("SmbTransferIdentity",str(d.samba_ui.get("access_user","staff")),12)
	_label("SmbTransferLocalCaption","保存済みの内容" if mode == "upload" else "取得するコピー",11)
	_label("SmbTransferRemoteCaption","取得時の内容",11)
	_label("SmbTransferState","",13)
	_label("SmbSourceDraft","● 未保存 · エディターで保存",13)
	_label("SmbRecoveryHint","入力を保持",11)
	var local := _paper("SmbTransferLocalPreview"); var remote := _paper("SmbTransferRemotePreview")
	remote.set_drag_forwarding(Callable(),func(point,data): return _can_drop_data(point+remote.position,data),func(point,data): _drop_data(point+remote.position,data))
	paper_height = maxf(86 * factor, local.get_theme_font("font").get_height(local.get_theme_font_size("font_size")) * 5 + 10 * factor)
	footer_y = 76 * factor + paper_height
	custom_minimum_size.y = footer_y + 68 * factor
	var picker := OptionButton.new(); picker.name = "SmbSourcePicker"; picker.fit_to_longest_item = false; add_child(picker); items.picker = picker
	var sources: Array[String] = []
	for folder in ["/srv/data","/home/operator",source.text.get_base_dir()]:
		for path in d.game.vm_list(folder):
			if not str(path).ends_with("/") and str(path) not in sources: sources.append(str(path))
	sources.sort()
	if not source.text.is_empty() and source.text not in sources: sources.append(source.text)
	for path in sources:
		picker.add_item(_source_name(path)); picker.set_item_metadata(picker.item_count-1,path)
		if path == source.text: picker.select(picker.item_count-1)
	picker.disabled = sources.is_empty() or mode != "upload"
	picker.item_selected.connect(func(index): source.text = str(picker.get_item_metadata(index)); source.text_changed.emit(source.text))
	if mode == "upload":
		destination.reparent(self); items.remote_name = destination
		destination.set_drag_forwarding(Callable(),func(point,data): return _can_drop_data(point+destination.position,data),func(point,data): _drop_data(point+destination.position,data))
	else:
		picker.hide()
		_label("SmbTransferLocalName",destination.text.get_file(),13)
		_label("SmbTransferRemoteName",str(d.samba_ui.get("access_selected","")),13)
	var send: Button = d._button("送信 →" if mode == "upload" else "← 取得",_send); send.name = "SmbUpload" if mode == "upload" else "SmbDownload"
	var edit: Button = d._button("エディター",func(): d._open_editor(source.text)); edit.name = "SmbTransferEdit"; edit.visible = mode == "upload"
	var cancel: Button = d._button("共有へ戻る",func(): d.samba_ui.transfer_mode = ""; d._render_smb()); cancel.name = "SmbTransferCancel"
	for button in [edit,send,cancel]:
		for color in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(color,Color.WHITE if button == send else INK)
		for kind in ["normal","hover","pressed","focus"]: button.add_theme_stylebox_override(kind,UI.style(BLUE if button == send else Color("edf3f9"),BLUE if button == send else Color("88a6b8"),7,5,3))
		add_child(button)
	items.send = send; items.edit = edit; items.cancel = cancel
	var mark := preload("res://scripts/service_glyph.gd").new(); mark.name = "SmbTransferFailureMark"; mark.kind = "blocked"; mark.tint = RED; add_child(mark); items.mark = mark
	var grip := Control.new(); grip.name = "SmbCopyGrip"; grip.tooltip_text = "共有フォルダーへドラッグ"; grip.mouse_default_cursor_shape = Control.CURSOR_DRAG
	grip.set_drag_forwarding(_copy_drag,Callable(),Callable()); add_child(grip); items.grip = grip; grip.visible = mode == "upload"
	source.text_changed.connect(func(_value): refresh())
	destination.text_changed.connect(func(_value): refresh())
	resized.connect(_layout); refresh()
	items.SmbTransferIdentity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items.SmbTransferLocalTitle.tooltip_text = "共有フォルダーへドラッグ" if mode == "upload" else "取得先"

func _source_name(path: String) -> String:
	var area := " · コピー" if path.begins_with("/home/operator/") else " · 顧客資料" if path.begins_with("/srv/data/") else ""
	var exists: bool = _local_exists(path)
	return ("" if exists else "? ") + path.get_file() + area

func _local_exists(path: String) -> bool:
	if path.strip_edges().is_empty(): return false
	var normalized: String = d.game._vm()._path(path)
	return d.game.vm_list(normalized.get_base_dir()).has(normalized)

func _label(id: String, value: String, pixels: int) -> Label:
	var node := Label.new(); node.name = id; node.text = value
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override("font",UI.font(400)); node.add_theme_font_size_override("font_size",roundi(pixels * factor)); node.add_theme_color_override("font_color",INK)
	node.clip_text = true; node.tooltip_text = value; add_child(node); items[id] = node; return node

func _paper(id: String) -> TextEdit:
	var node := TextEdit.new(); node.name = id; node.editable = false; node.tab_input_mode = false
	node.add_theme_font_override("font",UI.font(400)); node.add_theme_font_size_override("font_size",roundi(13 * factor))
	for kind in ["normal","read_only"]: node.add_theme_stylebox_override(kind,UI.style(Color("fffdf5"),Color.TRANSPARENT,4,4,0))
	for kind in ["font_color","font_readonly_color","font_uneditable_color"]: node.add_theme_color_override(kind,INK)
	add_child(node); items[id] = node; return node

func refresh() -> void:
	var source := source_field.text
	var filename: String = destination_field.text if mode == "upload" else str(d.samba_ui.get("access_selected",""))
	var local_path: String = source if mode == "upload" else destination_field.text
	var present: bool = _local_exists(source)
	var contents: String = str(d.game.vm_read(source)) if present else ""
	var dirty: bool = mode == "upload" and d.drafts.has(source) and str(d.drafts[source]) != contents
	var record: Dictionary = d.samba_ui.get("last_transfer",{})
	var matches: bool = not record.is_empty() and str(record.get("direction","")) == mode and str(record.get("local_path","")) == local_path and str(record.get("filename","")) == filename and str(record.get("user","")) == str(d.samba_ui.get("access_user","staff")) and str(record.get("share","")) == str(d.samba_ui.get("access_share","share"))
	if matches: matches = str(record.get("security_signature","")) == d._smb_security_signature()
	if mode == "upload" and matches: matches = str(record.get("source_sha256","")) == contents.sha256_text()
	var state := response_state(record) if matches else "unmeasured"
	if dirty: state = "draft"
	projected = {"state":state,"attempt":int(record.get("attempt",0)) if matches else 0,"current_request":matches,"source":local_path,"filename":filename,"user":str(d.samba_ui.get("access_user","staff")),"bytes":int(record.get("bytes",0)) if matches and state == "saved" else 0}
	items.SmbTransferLocalPreview.text = contents if mode == "upload" and present else "? ファイルなし" if mode == "upload" else ""
	var observed: bool = filename == str(d.samba_ui.get("access_selected","")) and str(d.samba_ui.get("access_scope","")) == str(d.samba_ui.get("access_share","share")) + "|" + str(d.samba_ui.get("access_user","staff"))
	items.SmbTransferRemotePreview.text = str(d.samba_ui.get("access_preview","")) if observed else "? 内容未取得"
	items.SmbTransferRemoteCaption.text = "取得時の内容" if observed else "未取得"
	if mode == "download":
		items.SmbTransferLocalName.text = destination_field.text.get_file()
		items.SmbTransferLocalPreview.text = str(d.game.vm_read(destination_field.text)) if state == "saved" else "? 取得前"
	var messages := {"unmeasured":"○ 未転送","saved":"✓ 保存済み · " + str(projected.bytes) + " B","denied":"× 共有で拒否","save_failed":"× 保存失敗 · 転送を取り消し","connection":"× 接続できない","missing":"× コピーがない","missing_remote":"× 共有ファイルなし","invalid":"× 転送先・名前を確認","failed":"? 応答エラー","draft":"● 未保存"}
	var prefix := "#" + str(projected.attempt) + "  " if matches else ""
	items.SmbTransferState.text = prefix + str(messages[state]); items.SmbTransferState.tooltip_text = items.SmbTransferState.text
	items.SmbTransferState.add_theme_color_override("font_color",GREEN if state == "saved" else RED if state not in ["unmeasured","draft"] else INK)
	items.SmbSourceDraft.visible = dirty; items.SmbTransferState.visible = not dirty
	items.SmbRecoveryHint.visible = state not in ["unmeasured","saved","draft"]
	items.send.disabled = dirty or source.strip_edges().is_empty() or destination_field.text.strip_edges().is_empty()
	items.edit.disabled = not present
	items.mark.visible = state in ["save_failed","missing"]
	items.grip.mouse_default_cursor_shape = Control.CURSOR_ARROW if items.send.disabled else Control.CURSOR_DRAG
	items.grip.tooltip_text = "未保存 · エディターで保存" if dirty else "共有フォルダーへドラッグ"
	if mode == "upload":
		items.picker.tooltip_text = source
		var found := false
		for index in items.picker.item_count:
			if str(items.picker.get_item_metadata(index)) == source: items.picker.select(index); found = true
		if not found:
			items.picker.add_item(_source_name(source)); items.picker.set_item_metadata(items.picker.item_count-1,source); items.picker.select(items.picker.item_count-1)
	queue_redraw()

func _send() -> void:
	refresh()
	if items.send.disabled: return
	var ok: bool = d._smb_put(source_field.text,destination_field.text) if mode == "upload" else d._smb_get(str(d.samba_ui.get("access_selected","")),destination_field.text)
	if ok: d.samba_ui.transfer_mode = ""
	d._render_smb()

func _copy_drag(_point: Vector2) -> Variant:
	refresh()
	if mode != "upload" or items.send.disabled: return null
	var preview := Label.new(); preview.text = source_field.text.get_file() + " →"; preview.add_theme_color_override("font_color",INK)
	preview.add_theme_stylebox_override("normal",UI.style(Color("fffdf5"),Color("7293a2"),12,8,2)); set_drag_preview(preview)
	return {"kind":"smb_saved_copy","desk":get_instance_id(),"source":source_field.text}

func _can_drop_data(point: Vector2, data: Variant) -> bool:
	var accepted: bool = mode == "upload" and not items.send.disabled and data is Dictionary and str(data.get("kind","")) == "smb_saved_copy" and int(data.get("desk",0)) == get_instance_id() and str(data.get("source","")) == source_field.text and Rect2(size.x*.58,0,size.x*.42,paper_height+76*factor).has_point(point)
	drop_hover = accepted; queue_redraw(); return accepted

func _drop_data(point: Vector2, data: Variant) -> void:
	if _can_drop_data(point,data): _send()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: drop_hover = false; queue_redraw()

func _ready() -> void: _layout()
func _place(id: String, rect: Rect2) -> void:
	var node: Control = items[id]; node.position = rect.position; node.size = rect.size
func _layout() -> void:
	if size.x <= 1: return
	var w := size.x; var f := factor; var pane := w * .42
	_place("SmbTransferLocalTitle",Rect2(30*f,0,pane-32*f,23*f))
	_place("SmbTransferRemoteTitle",Rect2(w*.58+30*f,0,pane-32*f,23*f))
	_place("SmbTransferIdentity",Rect2(w*.425,76*f,w*.15,23*f))
	_place("picker",Rect2(6*f,30*f,pane-12*f,29*f))
	if mode == "upload": _place("remote_name",Rect2(w*.58+6*f,30*f,pane-12*f,29*f))
	else:
		_place("SmbTransferLocalName",Rect2(8*f,30*f,pane-16*f,29*f))
		_place("SmbTransferRemoteName",Rect2(w*.58+8*f,30*f,pane-16*f,29*f))
	_place("SmbTransferLocalPreview",Rect2(7*f,68*f,pane-14*f,paper_height))
	_place("SmbTransferRemotePreview",Rect2(w*.58+7*f,68*f,pane-14*f,paper_height))
	_place("SmbTransferLocalCaption",Rect2(9*f,footer_y-4*f,pane-18*f,21*f))
	_place("SmbTransferRemoteCaption",Rect2(w*.58+9*f,footer_y-4*f,pane-18*f,21*f))
	for id in ["SmbTransferState","SmbSourceDraft"]: _place(id,Rect2(4*f,footer_y+18*f,w*.78,24*f))
	_place("SmbRecoveryHint",Rect2(w*.80,footer_y+18*f,w*.20,24*f))
	_place("edit",Rect2(0,footer_y+45*f,w*.24,31*f))
	_place("send",Rect2(w*.36,footer_y+45*f,w*.28,31*f))
	_place("cancel",Rect2(w*.75,footer_y+45*f,w*.25,31*f))
	var mark_x := w*.93 if str(projected.get("state","")) == "save_failed" and mode == "upload" else w*.35
	_place("mark",Rect2(mark_x,footer_y-35*f,28*f,28*f))
	_place("grip",Rect2(0,0,pane,26*f))
	custom_minimum_size.y = footer_y + 79*f
	queue_redraw()

func _draw() -> void:
	var w := size.x; var f := factor; var pane := w*.42
	# Sheet stack on the left, a folder with a raised tab on the right.
	draw_rect(Rect2(3*f,33*f,pane-6*f,paper_height+47*f),Color("c6d6e0"))
	draw_style_box(UI.style(Color("fffdf5"),Color("b7b4a9"),0,0,1),Rect2(0,27*f,pane,paper_height+49*f))
	draw_colored_polygon(PackedVector2Array([Vector2(w*.58,27*f),Vector2(w*.58,20*f),Vector2(w*.58+pane*.40,20*f),Vector2(w*.58+pane*.45,27*f)]),Color("c9b76e"))
	draw_style_box(UI.style(Color("eee3b8"),Color("b5a56a"),0,0,2),Rect2(w*.58,27*f,pane,paper_height+49*f))
	if drop_hover: draw_rect(Rect2(w*.58,27*f,pane,paper_height+49*f),BLUE,false,3*f)
	for x in [8*f,w*.58+8*f]:
		draw_rect(Rect2(x,2*f,14*f,18*f),Color("7097ac"),false,f)
		for line in 3: draw_line(Vector2(x+3*f,(7+line*4)*f),Vector2(x+11*f,(7+line*4)*f),Color("7097ac"),f)
	var center := Vector2(w*.5,119*f); var state := str(projected.get("state","unmeasured"))
	var color := GREEN if state == "saved" else RED if state not in ["unmeasured","draft"] else Color("7097ac")
	var start := Vector2(pane+4*f,center.y); var end := Vector2(w*.58-4*f,center.y)
	if state == "saved": draw_line(start,end,color,3*f,true)
	else: draw_dashed_line(start,end,color,2*f,5*f,true)
	draw_circle(center,14*f,Color("eef3f6")); draw_arc(center,14*f,0,TAU,32,color,2*f,true)
	if state == "saved":
		draw_line(center+Vector2(-7,0)*f,center+Vector2(-2,5)*f,color,3*f,true); draw_line(center+Vector2(-2,5)*f,center+Vector2(8,-6)*f,color,3*f,true)
	elif state in ["denied","connection","invalid","missing_remote"]:
		for sign in [-1,1]: draw_line(center+Vector2(-6,-6*sign)*f,center+Vector2(6,6*sign)*f,color,3*f,true)
	else:
		draw_circle(center,3*f,color)
	var tip := end if mode == "upload" else start; var sign := 1 if mode == "upload" else -1
	draw_line(tip,tip+Vector2(-7*sign,-5)*f,color,2*f,true); draw_line(tip,tip+Vector2(-7*sign,5)*f,color,2*f,true)
