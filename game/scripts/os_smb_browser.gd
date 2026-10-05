extends RefCounted
class_name OSSMBrowser

const UI=preload("res://scripts/ui_theme.gd")
const Glyph=preload("res://scripts/service_glyph.gd")
const INK=Color("202a34")
const MUTED=Color("67717c")
const LINE=Color("dce2e8")
const BLUE=Color("0067c0")

static func copy(key: String) -> String:return UI.copy("samba_"+key)
static func label(d,parent: Node,text: String,size:=14,color:=INK) -> Label:
	var node: Label=d._label(text,size,color);node.add_theme_font_override("font",UI.font(400));node.autowrap_mode=TextServer.AUTOWRAP_OFF;node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(node);return node
static func button(d,parent: Node,text: String,id: String,callback: Callable,primary:=false) -> Button:
	var node: Button=d._button(text,callback);node.name=id;node.custom_minimum_size.y=32
	for kind in ["normal","hover","pressed","focus"]:
		node.add_theme_stylebox_override(kind,UI.style(BLUE if primary else Color("edf3f9") if kind!="normal" else Color.WHITE,BLUE if primary else LINE,12,7,3))
		node.add_theme_color_override("font_"+kind+"_color",Color.WHITE if primary else INK)
	node.add_theme_color_override("font_color",Color.WHITE if primary else INK);parent.add_child(node);return node
static func remember(d) -> void:d._save_session(false)
static func field(d,parent: Node,title: String,id: String,key: String,fallback: String) -> LineEdit:
	label(d,parent,title,13,MUTED)
	var node:=LineEdit.new();node.name=id;node.text=str(d.samba_ui.get(key,fallback));node.custom_minimum_size.y=34;parent.add_child(node)
	node.text_changed.connect(func(value):d.samba_ui[key]=value;remember(d));return node

static func _preview_path(d) -> String:
	return str(d.samba_ui.get("access_preview_path", d.samba_ui.get("access_destination", "")))

static func _upload_preview(d) -> void:
	d.samba_ui.access_source = _preview_path(d)
	d.samba_ui.access_remote = str(d.samba_ui.get("access_selected", ""))
	d.samba_ui.transfer_mode = "upload"
	d._render_smb()

static func render(d,parent: VBoxContainer) -> void:
	var s: Dictionary=d.samba_ui
	var toolbar:=HFlowContainer.new();toolbar.add_theme_constant_override("h_separation",8);toolbar.add_theme_constant_override("v_separation",6);parent.add_child(toolbar)
	var user:=OptionButton.new();user.name="SmbUser";user.add_item(copy("employee")+" · staff");user.add_item(copy("guest"));user.select(1 if str(s.get("access_user","staff"))=="guest" else 0);toolbar.add_child(user)
	user.item_selected.connect(func(index):s.access_user="staff" if index==0 else "guest";s.transfer_mode="";d._smb_list();d._render_smb())
	button(d,toolbar,copy("refresh"),"SmbRefresh",func():d._smb_list();d._render_smb())
	button(d,toolbar,copy("upload"),"SmbUploadOpen",func():s.transfer_mode="upload";d._render_smb())
	var download:=button(d,toolbar,copy("download"),"SmbDownloadOpen",func():s.transfer_mode="download";d._render_smb())
	download.disabled=str(s.get("access_selected","")).is_empty()
	if str(s.get("transfer_mode","")) in ["upload","download"]:
		_transfer(d,parent,str(s.transfer_mode));return
	if bool(s.get("access_stale",false)):
		var stale:=label(d,parent,"前回取得した内容を表示中です。「更新」で一覧を再取得できます。",12,Color("8b5e10"))
		stale.name="SmbStale";stale.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var output:=str(s.get("access_output",""))
	var last: Dictionary = s.get("last_transfer",{})
	if not last.is_empty() and str(s.get("access_operation","")) == "upload" and str(last.get("direction","")) == "upload" and str(last.get("response","")) == output and str(last.get("user","")) == str(s.get("access_user","staff")) and str(last.get("share","")) == str(s.get("access_share","share")):
		var receipt := preload("res://scripts/smb_transfer_receipt.gd").new(); receipt.setup(d,last); parent.add_child(receipt)
	elif not output.is_empty():
		var failed:=output.begins_with("NT_STATUS_") or output.begins_with("{") or output.begins_with("put:") or output.begins_with("get:") or output.begins_with("smbclient:")
		var result:=label(d,parent,output,13,Color("ba302e") if failed else MUTED);result.name="SmbOutput";result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		if failed:
			var recovery:=label(d,parent,"転送先・ファイル名・接続ユーザーを確認して再試行してください。入力内容は保持されています。",13,MUTED)
			recovery.name="SmbRecoveryHint";recovery.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var listing:=HFlowContainer.new();listing.add_theme_constant_override("h_separation",8);listing.add_theme_constant_override("v_separation",6);parent.add_child(listing)
	var files: Array=s.get("access_files",[])
	if files.is_empty():label(d,listing,copy("access_denied") if "ACCESS_DENIED" in output else copy("no_files"),14,MUTED)
	for raw in files:
		var name:=str(raw);var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);listing.add_child(row);Glyph.add_to(row,"file",20,BLUE)
		var entry:=button(d,row,name,"SmbFile_"+name.validate_node_name(),func():
			s.access_destination="/home/operator/"+name
			d._smb_get(name,str(s.access_destination));d._render_smb())
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT;entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		entry.add_theme_stylebox_override("normal",UI.style(Color("e7f1fb") if str(s.get("access_selected",""))==name else Color.WHITE,Color.TRANSPARENT,8,8,0))
	if not str(s.get("access_selected","")).is_empty():
		var preview_path := _preview_path(d)
		var desk := preload("res://scripts/smb_document_desk.gd").new(); desk.setup(d,str(s.access_selected),preview_path,_upload_preview.bind(d)); parent.add_child(desk)
		var details: VBoxContainer = d._disclosure(parent,"取得先・接続の詳細")
		var path_label:=label(d,details,"取得先: "+preview_path,12,MUTED);path_label.name="SmbPreviewPath";path_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label(d,details,"共有: //files01.client.test/"+str(s.get("access_share","share"))+" / 利用者: "+str(s.get("access_user","staff")),12,MUTED)

static func _transfer(d,parent: VBoxContainer,mode: String) -> void:
	var s: Dictionary=d.samba_ui
	var position := parent.get_child_count()
	var details: VBoxContainer = d._disclosure(parent,"パス・応答の詳細")
	var source: LineEdit
	var destination: LineEdit
	if mode=="upload":
		source=field(d,details,copy("local_source"),"SmbSource","access_source","/srv/data/orders.csv")
		destination=LineEdit.new();destination.name="SmbRemoteName";destination.text=str(s.get("access_remote","orders.csv"));details.add_child(destination)
		destination.text_changed.connect(func(value):s.access_remote=value;remember(d))
	else:
		destination=field(d,details,copy("download_destination"),"SmbDestination","access_destination","/home/operator/orders.csv")
		source=destination
	var raw:=label(d,details,str(s.get("access_output","")),13,MUTED);raw.name="SmbOutput";raw.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var last: Dictionary=s.get("last_transfer",{})
	if not last.is_empty():label(d,details,"前の転送 #"+str(last.get("attempt",0))+": "+str(last.get("filename",""))+" · "+str(last.get("response","")),12,MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label(d,details,"共有: //files01.client.test/"+str(s.get("access_share","share")),12,MUTED)
	var desk:=preload("res://scripts/smb_transfer_desk.gd").new();desk.setup(d,mode,source,destination);parent.add_child(desk);parent.move_child(desk,position)
