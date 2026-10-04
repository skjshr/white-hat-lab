extends RefCounted
## Direct manipulation for the selected file in the authored recovery case.
## Render only projects recorded bytes; every operation is an explicit callback.
const Visual=preload("res://scripts/backup_visual.gd")
const PaperObject=preload("res://scripts/backup_workbench_object.gd")
const Seal=preload("res://scripts/backup_document.gd")
const UI=preload("res://scripts/ui_theme.gd")
const INK=Color("e5eeee")
const PAPER_INK=Color("243737")
const MUTED=Color("9eb2b3")
const AMBER=Color("efc45d")

static func _text(d,parent:Node,value:String,points:int,color:Color=INK,id:String="") -> Label:
	var node:Label=d._label(value,points,color);node.name=id if not id.is_empty() else "Text"
	node.add_theme_font_override("font",UI.font(500 if points>=18 else 400));node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.clip_text=false;node.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING;node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(node);return node

static func _margin(parent:Control,padding:int) -> VBoxContainer:
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,padding)
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(margin)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",4);stack.mouse_filter=Control.MOUSE_FILTER_IGNORE;margin.add_child(stack);return stack

static func _paper(d,parent:Node,doc:Dictionary,title:String,id:String,selected:bool=false,action:Callable=Callable()) -> Button:
	var paper:=PaperObject.new();paper.name=id;paper.document_kind=str(doc.kind);paper.selected=selected;paper.interactive=action.is_valid()
	var compact:bool=float(d.windows.browser.size.x)/maxf(1.0,float(d.game.settings.get("text_scale",1.0)))<1100
	var paper_height:=204.0 if compact else 372.0
	paper.custom_minimum_size=Vector2(162 if compact else 280,paper_height);paper.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	paper.set_meta("document",doc.duplicate(true));parent.add_child(paper)
	if action.is_valid():paper.pressed.connect(action)
	var padding:=14 if compact else 24
	var content:=_margin(paper,padding)
	var caption:=_text(d,content,title,12,PAPER_INK,id+"Caption");caption.custom_minimum_size.y=24
	if str(doc.kind)=="ledger":
		for field in doc.fields:
			if str(field.key)!="date":_text(d,content,str(field.label),10,Color("68766e"))
			var text:=str(field.value) if str(field.key)=="date" else Visual.number(str(field.value))
			var value:=_text(d,content,text,12 if str(field.key)=="date" else 22 if compact else 32,PAPER_INK,id+"Value_"+str(field.key));value.autowrap_mode=TextServer.AUTOWRAP_OFF
			if not compact:
				var gap:=Control.new();gap.custom_minimum_size.y=12 if str(field.key)=="date" else 18;gap.mouse_filter=Control.MOUSE_FILTER_IGNORE;content.add_child(gap)
	elif str(doc.kind)=="damaged":
		var mark:=_text(d,content,"!",52,Color("99621c"),id+"DamageMark");mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_text(d,content,"読取不可",16,Color("79531e"),id+"Damage")
	elif str(doc.kind)=="missing":
		_text(d,content,"—",42,Color("607975"));_text(d,content,"ファイルなし",13,PAPER_INK,id+"Missing")
	elif str(doc.kind)=="unread":
		_text(d,content,"…",42,Color("607975"));_text(d,content,"読取失敗" if bool(doc.get("read_error",false)) else "開いて確認",13,PAPER_INK,id+"Unread")
	else:
		var lines:Array=doc.get("lines",[])
		_text(d,content,"\n".join(PackedStringArray(lines.slice(0,3))) if not lines.is_empty() else "空のファイル",12,PAPER_INK,id+"Text")
	content.minimum_size_changed.connect(func():paper.custom_minimum_size.y=maxf(paper_height,content.get_combined_minimum_size().y+padding*2))
	return paper

static func _state(d,parent:Node,state:String,words:String,id:String) -> Control:
	var color:=Color("75d7a3") if state in ["matched","preserved"] else AMBER if state in ["mismatch","changed"] else MUTED
	var mark:="✓" if state in ["matched","preserved"] else "!" if state in ["mismatch","changed"] else "?"
	var row:=HBoxContainer.new();row.name=id;row.set_meta("state",state);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(row)
	var seal:=Seal.new();seal.kind="guard-"+state;seal.custom_minimum_size=Vector2(28,28);row.add_child(seal)
	_text(d,row,mark+" "+words,12,color,id+"Label");return row

static func render(d,parent:VBoxContainer,s:Dictionary,live:Dictionary,snapshot:Dictionary,repo:String,api) -> void:
	var path:=str(s.path);var fs:Dictionary=live.get("fs",{});var source:=str(snapshot.get("paths",["/srv/data"])[0]);var relative:=path.trim_prefix(source.trim_suffix("/")+"/")
	var acceptance:Dictionary=d.game._vm().backup_acceptance_view();var guards:=Visual.acceptance(acceptance)
	var panel:=PanelContainer.new();panel.name="BackupWorkbench";panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var viewport:=parent.get_parent() as Control
	panel.custom_minimum_size.y=maxf(380,viewport.size.y)
	panel.add_theme_stylebox_override("panel",UI.style(Color("182c30"),Color("365055"),18,14,0));parent.add_child(panel)
	var layout:=VBoxContainer.new();layout.add_theme_constant_override("separation",12);panel.add_child(layout)
	var toolbar:=HBoxContainer.new();toolbar.add_theme_constant_override("separation",12);layout.add_child(toolbar)
	_text(d,toolbar,"Backrest",20);_text(d,toolbar,path.get_file(),16,INK,"BackupSelectedPath")
	api.button(d,toolbar,"ファイル","BackupFileToggle",func():s["file_list_open"]=true;api.rerender(d))
	api.button(d,toolbar,"詳細","BackupContentDetails",func():s["content_details"]=not bool(s.get("content_details",false));api.rerender(d))
	var center:=CenterContainer.new();center.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(center)
	var composition:=VBoxContainer.new();composition.add_theme_constant_override("separation",18);center.add_child(composition)
	var desk:=HBoxContainer.new();desk.name="BackupWorkbenchObjects";desk.add_theme_constant_override("separation",40);composition.add_child(desk)
	var versions:=VBoxContainer.new();versions.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;desk.add_child(versions)
	_text(d,versions,"保存版 · "+repo,12,MUTED)
	var shelf:=HBoxContainer.new();shelf.name="BackupVersionShelf";shelf.add_theme_constant_override("separation",10);versions.add_child(shelf)
	var compact:bool=float(d.windows.browser.size.x)/maxf(1.0,float(d.game.settings.get("text_scale",1.0)))<1100
	for candidate in live.get("snapshots",[]):
		if str(candidate.get("repository",""))!=repo:continue
		var candidate_source:=str(candidate.get("paths",["/srv/data"])[0]);var candidate_relative:=path.trim_prefix(candidate_source.trim_suffix("/")+"/")
		if not candidate.get("files",{}).has(candidate_relative):continue
		var candidate_id:=str(candidate.get("id",""));var key:=JSON.stringify([repo,candidate_id,path])
		var recorded:Dictionary=s.get("inspected_files",{}) if s.get("inspected_files",{}) is Dictionary else {}
		var observed:bool=recorded.has(key) and str(recorded[key])==str(candidate.files[candidate_relative])
		var failed:bool=candidate_id==str(snapshot.id) and s.has("preview") and str(s.preview)!=str(candidate.files[candidate_relative])
		if failed:observed=false
		var doc:Dictionary=Visual.document(str(recorded[key])) if observed else {"kind":"unread","fields":[],"lines":[],"bytes":0}
		doc["read_error"]=failed
		var selected:bool=candidate_id==str(snapshot.id)
		var lift:=MarginContainer.new();lift.mouse_filter=Control.MOUSE_FILTER_IGNORE;lift.add_theme_constant_override("margin_top",0 if selected else 14 if compact else 28);lift.add_theme_constant_override("margin_bottom",14 if selected and compact else 28 if selected else 0);shelf.add_child(lift)
		var sheet:=_paper(d,lift,doc,"版 "+candidate_id,"BackupSnapshot_"+candidate_id,selected,func():api._select_snapshot(d,s,candidate,repo);api._focus_after(d,"BackupSnapshot_"+candidate_id))
		sheet.set_meta("snapshot_id",candidate_id);sheet.set_meta("source_path",path);sheet.set_meta("repository",repo);sheet.set_meta("observed",observed)
	var bridge:=VBoxContainer.new();bridge.name="BackupWorkbenchAction";bridge.size_flags_vertical=Control.SIZE_SHRINK_CENTER;desk.add_child(bridge)
	if not bool(s.get("restore_open",false)):
		var restore:Button=api.button(d,bridge,"復元 →","BackupRestoreToPath",func():s["restore_scope"]="selected";s["restore_open"]=true;api._refresh_plan(d,s,snapshot,repo,_destination(s),true);api.rerender(d))
		restore.custom_minimum_size=Vector2(90,48);restore.add_theme_stylebox_override("normal",UI.style(Color("196b6e"),Color("7ac8c4"),12,10,5))
	else:_text(d,bridge,"→",30,INK)
	var tray:=PaperObject.new();tray.name="BackupDestinationTray";tray.shape="tray";tray.custom_minimum_size=Vector2(310 if compact else 380,270);tray.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;desk.add_child(tray)
	var target:=_margin(tray,14)
	target.minimum_size_changed.connect(func():tray.custom_minimum_size.y=maxf(260,target.get_combined_minimum_size().y+28))
	var actual_path:=str(api._comparison_restore_path(live,path))
	if actual_path.is_empty():actual_path="/restore".path_join(path.trim_prefix("/"))
	tray.set_meta("destination",actual_path)
	var tray_head:=HBoxContainer.new();tray_head.add_theme_constant_override("separation",8);target.add_child(tray_head)
	var open:bool=bool(s.get("restore_open",false))
	_text(d,tray_head,_destination(s) if open else actual_path.get_base_dir(),15,INK,"BackupDestinationLabel")
	if open:_confirmation(d,target,s,live,snapshot,repo,path,actual_path,api)
	else:
		var state:=str(guards.restored)
		var status:="照合一致" if state=="matched" else "照合不一致" if state=="mismatch" else "未復元" if state=="missing" else "照合不明"
		_state(d,tray_head,state,status,"BackupRecoveryGuard")
		var sheet:=_paper(d,target,Visual.document(str(fs.get(actual_path,"")),fs.has(actual_path)),path.get_file(),"BackupCurrentDocument")
		var result:=str(s.get("restore_result",""))
		if result=="failed":_text(d,target,"保存に失敗 · 変更なし",12,AMBER,"BackupRestoreResult")
	var protected:=HBoxContainer.new();protected.name="BackupProtectedFiles";protected.add_theme_constant_override("separation",12);composition.add_child(protected)
	var words:={"preserved":"保持","changed":"変更あり","unknown":"記録なし"}
	var original:=PaperObject.new();original.shape="original";original.document_kind=str(Visual.document(str(fs.get(path,"")),fs.has(path)).kind);original.name="BackupOriginalBundle";original.custom_minimum_size=Vector2(50 if compact else 62,62 if compact else 78);protected.add_child(original)
	if original.document_kind=="damaged":
		var mark:=_text(d,_margin(original,8),"!",24,Color("79531e"));mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_state(d,protected,str(guards.original),"原本 · "+str(words.get(guards.original,"記録なし")),"BackupOriginalGuard")
	var bundle:=PaperObject.new();bundle.shape="bundle";bundle.name="BackupUnrelatedBundle";bundle.custom_minimum_size=Vector2(50 if compact else 62,62 if compact else 78);protected.add_child(bundle)
	_state(d,protected,str(guards.unrelated),"ほかのファイル · "+str(words.get(guards.unrelated,"記録なし")),"BackupUnrelatedGuard")
	if bool(s.get("content_details",false)):_details(d,layout,s,snapshot,path,relative,actual_path,fs,acceptance,api)
	var resize:Callable=func():
		if is_instance_valid(panel):panel.custom_minimum_size.y=maxf(380,viewport.size.y)
	viewport.resized.connect(resize)
	panel.tree_exiting.connect(func():if is_instance_valid(viewport) and viewport.resized.is_connected(resize):viewport.resized.disconnect(resize))
	desk.resized.connect(func():
		if compact:desk.add_theme_constant_override("separation",12)
	)

static func _confirmation(d,parent:VBoxContainer,s:Dictionary,live:Dictionary,snapshot:Dictionary,repo:String,path:String,actual_path:String,api) -> void:
	var heading:=HBoxContainer.new();parent.add_child(heading);_text(d,heading,"復元前の確認",13)
	api.button(d,heading,"戻る","BackupCloseRestore",func():s["restore_open"]=false;api.rerender(d))
	var plan:Dictionary=s.get("restore_plan",{}) if s.get("restore_plan",{}) is Dictionary else {}
	var entries:Array=plan.get("entries",[]) if bool(plan.get("ok",false)) else []
	if not str(plan.get("error","")).is_empty():_text(d,parent,str(plan.error),12,AMBER,"BackupPlanError")
	var chosen:Dictionary={}
	for entry in entries:
		if str(entry.get("source",""))==path:chosen=entry;break
	var planned_path:=str(chosen.get("path",actual_path));var fs:Dictionary=live.get("fs",{})
	_text(d,parent,planned_path,11,MUTED,"BackupPlanRoute")
	var preview:=HBoxContainer.new();preview.name="BackupPlanEntries";preview.add_theme_constant_override("separation",8);parent.add_child(preview)
	var before:=Visual.document(str(fs.get(planned_path,"")),fs.has(planned_path))
	var after:=str(fs.get(planned_path,"")) if str(chosen.get("status",""))=="skipped" else str(chosen.get("value",""))
	var first:=_paper(d,preview,before,"現在","BackupPlanBefore");first.custom_minimum_size.x=135
	var second:=_paper(d,preview,Visual.document(after,not chosen.is_empty() and (fs.has(planned_path) or str(chosen.get("status",""))!="skipped")),"予定","BackupPlanAfter");second.custom_minimum_size.x=135
	var warning:Dictionary=api._planned_live_changes(d.game._vm().backup_acceptance_view(),entries)
	if int(warning.original)>0 or int(warning.unrelated)>0:_text(d,parent,"! 原本を変更する予定 "+str(warning.original) if int(warning.original)>0 else "! 対象外を変更する予定 "+str(warning.unrelated),12,AMBER,"BackupPlannedLiveChanges")
	var stale:=_text(d,parent,"再確認が必要",12,AMBER,"BackupPreviewStale");stale.visible=not bool(s.get("plan_previewed",false))
	preview.visible=bool(s.get("plan_previewed",false))
	var outcome:=str(s.get("restore_result",""))
	if outcome=="failed":_text(d,parent,"保存に失敗 · 変更なし",12,AMBER,"BackupRestoreResult")
	if outcome=="preview_stale":_text(d,parent,"内容が変わりました · 再確認",12,AMBER,"BackupRestoreResult")
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",8);parent.add_child(actions)
	var execute:Button=api.button(d,actions,"この内容で復元","BackupExecuteRestore",func():api._execute_restore(d,s,snapshot,repo,_destination(s)))
	execute.disabled=entries.is_empty() or not bool(s.get("plan_previewed",false))
	api.button(d,actions,"設定","BackupRestoreSettings",func():s["workbench_settings"]=not bool(s.get("workbench_settings",false));api.rerender(d))
	if bool(s.get("workbench_settings",false)):
		var destination:=LineEdit.new();destination.name="BackupDestination";destination.text=str(s.get("destination","/restore"));parent.add_child(destination)
		destination.text_changed.connect(func(value):s["destination"]=value;s["plan_previewed"]=false;execute.disabled=true;preview.visible=false;stale.visible=true;api.persist(d))
		var policy:=OptionButton.new();policy.name="BackupOverwrite";policy.add_item("上書きする");policy.add_item("既存を保持");policy.select(1 if str(s.get("overwrite","always"))=="never" else 0);parent.add_child(policy)
		policy.item_selected.connect(func(index):s["overwrite"]="never" if index==1 else "always";s["plan_previewed"]=false;api.rerender(d);api._focus_after(d,"BackupOverwrite"))
	if not bool(s.get("plan_previewed",false)) or bool(s.get("workbench_settings",false)):
		api.button(d,parent,"差分を再確認","BackupPreviewChanges",func():api._refresh_plan(d,s,snapshot,repo,_destination(s),true);api.rerender(d))

static func _destination(s:Dictionary) -> String:
	var target:=str(s.get("destination","/restore")).strip_edges()
	return target if not target.is_empty() else "/restore"

static func _details(d,parent:Node,s:Dictionary,snapshot:Dictionary,path:String,relative:String,destination:String,fs:Dictionary,acceptance:Dictionary,api) -> void:
	_text(d,parent,"保存元 "+str(snapshot.get("repository",""))+" / "+str(snapshot.id)+" / "+path+"\n復元先 "+destination,12,MUTED,"BackupFullPaths")
	var cache:Dictionary=s.get("inspected_files",{}) if s.get("inspected_files",{}) is Dictionary else {}
	var key:=JSON.stringify([str(snapshot.get("repository","")),str(snapshot.id),path])
	var cached_valid:bool=cache.has(key) and str(cache[key])==str(snapshot.files[relative])
	var saved:=str(s.preview) if s.has("preview") else str(cache[key]) if cached_valid else "未確認"
	for entry in [[saved,"BackupPreview"],[str(fs.get(destination,"（ファイルなし）")),"BackupCurrentPreview"]]:
		var text:=TextEdit.new();text.name=entry[1];text.text=entry[0];text.editable=false;text.custom_minimum_size.y=90;parent.add_child(text)
	_text(d,parent,"保全判定: "+str(acceptance),11,MUTED,"BackupAcceptanceDetails")
	api.button(d,parent,"保存先・全体操作","BackupBackSnapshots",func():s["file_list_open"]=true;api.rerender(d))
