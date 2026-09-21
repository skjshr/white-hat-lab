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
static func panel(parent: Node) -> VBoxContainer:
	var frame:=PanelContainer.new();frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frame.add_theme_stylebox_override("panel",UI.style(Color.WHITE,LINE,16,14,0));parent.add_child(frame)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",10);frame.add_child(body);return body

static func render(d,parent: VBoxContainer) -> void:
	var s: Dictionary=d.samba_ui
	var toolbar:=HFlowContainer.new();toolbar.add_theme_constant_override("h_separation",8);toolbar.add_theme_constant_override("v_separation",6);parent.add_child(toolbar)
	var user:=OptionButton.new();user.name="SmbUser";user.add_item(copy("employee")+" · staff");user.add_item(copy("guest"));user.select(1 if str(s.get("access_user","staff"))=="guest" else 0);toolbar.add_child(user)
	user.item_selected.connect(func(index):s.access_user="staff" if index==0 else "guest";s.transfer_mode="";d._smb_list();d._render_smb())
	button(d,toolbar,copy("refresh"),"SmbRefresh",func():d._smb_list();d._render_smb())
	button(d,toolbar,copy("upload"),"SmbUploadOpen",func():s.transfer_mode="upload";d._render_smb())
	var download:=button(d,toolbar,copy("download"),"SmbDownloadOpen",func():s.transfer_mode="download";d._render_smb())
	download.disabled=str(s.get("access_selected","")).is_empty()
	var output:=str(s.get("access_output",""))
	if not output.is_empty():
		var failed:=output.begins_with("NT_STATUS_") or output.begins_with("{") or output.begins_with("put:")
		var result:=label(d,parent,output,13,Color("ba302e") if failed else MUTED);result.name="SmbOutput";result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if str(s.get("transfer_mode","")) in ["upload","download"]:
		_transfer(d,parent,str(s.transfer_mode));return
	var compact:=float(d.windows.files.size.x)<1100
	var panes: BoxContainer=VBoxContainer.new() if compact else HBoxContainer.new();panes.add_theme_constant_override("separation",12);parent.add_child(panes)
	var listing:=panel(panes);listing.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label(d,listing,copy("name"),13,MUTED);listing.add_child(HSeparator.new())
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
		var preview:=panel(panes);preview.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label(d,preview,str(s.access_selected),17)
		var contents:=TextEdit.new();contents.name="SmbPreview";contents.editable=false;contents.text=str(s.get("access_preview",""));contents.custom_minimum_size.y=210;contents.add_theme_font_override("font",d.mono)
		for kind in ["normal","read_only"]:contents.add_theme_stylebox_override(kind,UI.style(Color("f9fbfd"),LINE,10,10,0))
		for kind in ["font_color","font_readonly_color","font_uneditable_color"]:contents.add_theme_color_override(kind,INK)
		preview.add_child(contents)

static func _transfer(d,parent: VBoxContainer,mode: String) -> void:
	var s: Dictionary=d.samba_ui;var body:=panel(parent)
	label(d,body,copy(mode),18)
	if mode=="upload":
		var source:=field(d,body,copy("local_source"),"SmbSource","access_source","/srv/data/orders.csv")
		var available:=OptionButton.new();available.name="SmbSourcePicker";body.add_child(available)
		for path in d.game.vm_list("/srv/data"):
			if not str(path).ends_with("/"):
				available.add_item(str(path));available.set_item_metadata(available.item_count-1,str(path))
				if str(path)==source.text:available.select(available.item_count-1)
		available.item_selected.connect(func(index):source.text=str(available.get_item_metadata(index));s.access_source=source.text;remember(d))
		var remote:=field(d,body,copy("remote_filename"),"SmbRemoteName","access_remote","orders.csv")
		var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",8);body.add_child(actions)
		button(d,actions,copy("upload"),"SmbUpload",func():
			if d._smb_put(source.text,remote.text):s.transfer_mode=""
			d._render_smb(),true)
		button(d,actions,copy("cancel"),"SmbTransferCancel",func():s.transfer_mode="";d._render_smb())
	else:
		label(d,body,str(s.get("access_selected","")),14,MUTED)
		var destination:=field(d,body,copy("download_destination"),"SmbDestination","access_destination","/home/operator/orders.csv")
		var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",8);body.add_child(actions)
		button(d,actions,copy("download"),"SmbDownload",func():
			if d._smb_get(str(s.get("access_selected","")),destination.text):s.transfer_mode=""
			d._render_smb(),true)
		button(d,actions,copy("cancel"),"SmbTransferCancel",func():s.transfer_mode="";d._render_smb())
