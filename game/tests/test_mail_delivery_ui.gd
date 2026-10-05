extends SceneTree
## UI/API fixture from a genuinely earned paid company; not an intake journey.
const THREAD=preload("res://scripts/mail_delivery_thread.gd")
var failures: Array[String]=[]
var assertions:=0
var game
var ui
var pc
var narrow: bool="--narrow" in OS.get_cmdline_user_args()
func _init() -> void:
	create_timer(80).timeout.connect(func(): push_error("MAIL_DELIVERY_TIMEOUT"); quit(2))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions+=1
	if not ok: failures.append(label); print("FAIL ",label)
func frames(count:=7) -> void:
	for _frame in count: await process_frame
func object(id: String) -> Node: return ui.find_child(id,true,false)
func press(id: String) -> void:
	var button:=object(id) as Button
	check(button!=null and not button.disabled,"available action "+id)
	if button!=null and not button.disabled: button.pressed.emit()
	await frames()
func same(a: Variant,b: Variant) -> bool: return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await frames(); await RenderingServer.frame_post_draw
	var folder:=OS.get_environment("WHL_CAPTURE_DIR"); DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+("-narrow" if narrow else "-wide")+".png"))==OK,"capture "+label)
func build() -> void:
	ui=load("res://scripts/interface.gd").new(); root.add_child(ui); await frames()
	ui.guided_intro.skip(); ui.next_task_guide.set_enabled(false); ui._set_text_scale(1.3 if narrow else 1.0); ui.open_panel("terminal"); await frames(); pc=ui.desktop; pc._show_app("mail")
	if not pc.windows.mail.maximized: pc.windows.mail.toggle_maximize()
	await frames()
func run() -> void:
	game=root.get_node("Game"); game.set_process(false)
	if not game.save_path.begins_with("user://qa-"): quit(2); return
	var path:=OS.get_environment("WHL_MAIL_FIXTURE"); var source:=FileAccess.get_file_as_string(path)
	check(not source.is_empty(),"actual paid company source exists")
	if source.is_empty(): quit(2); return
	var file:=FileAccess.open(game.save_path,FileAccess.WRITE); file.store_string(source); file.close()
	check(game.load_game() and game.current_done(),"copy genuinely completed company to QA")
	game.set_process(false); game.set_settings({"resolution":"960x600" if narrow else "1920x1080","window_mode":"windowed","text_scale":1.3 if narrow else 1.0,"volume":0},false)
	root.get_node("Graphics").apply_settings(game.settings); await frames()
	await build()
	var id: String=str(game.state.current_contract_id); var record:=THREAD.delivery_for(game.state,id)
	await press("MailContract_"+id.validate_node_name()); pc=ui.desktop
	var reply: Dictionary=object("MailDeliveryThread").get_meta("delivery")
	check(is_equal_approx(float(object("MailReceivedSheet").factor),1.3 if narrow else 1.0) and object("MailCustomerScores").get_theme_font_size("font_size")==roundi(15*(1.3 if narrow else 1.0)),"actual score font honors requested text setting")
	check(not narrow or is_equal_approx(root.get_visible_rect().size.x,960),"small-window test uses actual window coordinates rather than a scaled larger canvas")
	check(str(reply.id)==id and bool(reply.confirmed) and str(reply.rating)=="late","thread uses exact paid daily-report delivery")
	check(object("MailCustomerReply").text.contains("締めの作業を再開") and not object("MailCustomerReply").text.contains("保存できず"),"current reply states confirmed recovery instead of old urgent request")
	check(object("MailCustomerScores").text.contains("75 → 60") and object("MailNextContact").text.contains("相談を保留"),"recorded loss and held next consultation appear together")
	check(not object("MailOriginalRequest").is_visible_in_tree() and not object("MailReceivedDetails").is_visible_in_tree(),"original request and inspection details start collapsed")
	for key in ["MailReceivedSheet","MailCustomerReply","MailReceivedAttachment","MailCustomerRoute","MailReceiptAction"]:
		var node:=object(key) as Control
		var viewport: Rect2=pc.widgets.mail.footer_frame.get_global_rect() if key in ["MailReceivedAttachment","MailCustomerRoute","MailReceiptAction"] else pc.widgets.mail.body.get_parent().get_global_rect()
		check(node.is_visible_in_tree() and viewport.grow(1).encloses(node.get_global_rect()),"primary reply object visible without scrolling "+key)
	for key in ["MailReceivedStatus","MailReceivedCount","MailDeliveryTiming","MailCustomerScores","MailNextContact"]:
		var label:=object(key) as Label
		var text_size:=label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size"))
		check(label.size.x+1>=text_size.x and label.size.y+1>=text_size.y,"whole graphical reply caption fits at requested font size "+key)
	await capture("01-real-paid-customer-reply")
	var before: Dictionary=game.state.duplicate(true); var machine: Dictionary=game._vm().export_state()
	await press("MailReceivedAttachment")
	check(object("MailReceivedDetails").is_visible_in_tree() and object("MailReceivedDetails").get_child_count()>=record.checks.size(),"attachment opens this delivery's recorded acceptance checks")
	await press("MailReceivedAttachment")
	pc._refresh_mail(); await frames()
	check(same(game.state.history,before.history) and same(game.state.customer_relations,before.customer_relations) and same(game.state.company_cycle,before.company_cycle) and same(game._vm().export_state(),machine) and int(game.state.cash)==int(before.cash) and int(game.state.clock_minutes)==int(before.clock_minutes),"reading attachment and repainting never measure, transact or alter customer state")
	check(pc._save_session() and game.save_game(),"save selected conversation")
	ui.queue_free(); await frames(); check(game.load_game(),"resume selected reply"); game.set_process(false); await build()
	check(str(object("MailDeliveryThread").get_meta("delivery").id)==id and pc.widgets.mail.reading,"saved exact job conversation reopens")
	var unknown:=record.duplicate(true); unknown.erase("checks"); unknown.erase("rating"); unknown.erase("satisfaction_before"); unknown.erase("satisfaction_after")
	var missing:=THREAD.project(game.state,unknown)
	check(not bool(missing.confirmed) and str(missing.rating)=="" and missing.before==null and missing.after==null and not str(missing.body).contains("再開"),"missing legacy evidence never becomes success, timing or customer scores")
	check(THREAD.delivery_for(game.state,"missing-job").is_empty() and not bool(THREAD.project(game.state,{}).completed),"absent job never borrows latest delivery")
	var old_style: Dictionary=game.state.duplicate(true); old_style.contract_contexts={}
	for row in old_style.history:
		if str(row.get("id",""))==id: row.erase("delivery_results")
	var legacy_reply:=THREAD.project(old_style,THREAD.delivery_for(old_style,id))
	check(not bool(legacy_reply.report_write_confirmed) and not str(legacy_reply.body).contains("締めの作業を再開"),"old daily-named case without its report response never assumes newer catalog behavior")
	var current: Dictionary=game.state.duplicate(true); var forged:=record.duplicate(true); forged.client="別の顧客"
	check(THREAD.project(current,forged).event.is_empty() and not bool(THREAD.project(current,forged).confirmed),"same contract identifier with another client cannot borrow confirmation or customer event")
	var older: Dictionary={}
	for row in game.state.history:
		if row is Dictionary and str(row.get("id",""))!=id and str(row.get("id","")) in game.state.completed_ids and str(row.get("kind","delivery"))=="delivery": older=row; break
	check(not older.is_empty(),"earned company contains a genuine earlier completed job")
	pc.widgets.mail.folder_picker.select(1); pc.widgets.mail.folder_picker.item_selected.emit(1); await frames()
	await press("MailHistory_"+str(older.id).validate_node_name())
	check(str(object("MailDeliveryThread").get_meta("delivery").id)==str(older.id) and same(object("MailDeliveryThread").get_meta("delivery").checks,older.get("checks",[])) and str(game.state.current_contract_id)==id,"reading genuine earlier history uses its own checks without switching the working job")
	check(pc._save_session() and game.save_game(),"save selected exact history identity")
	ui.queue_free(); await frames(); check(game.load_game(),"resume exact earlier history"); game.set_process(false); await build()
	check(pc.widgets.mail.folder=="history" and str(object("MailDeliveryThread").get_meta("delivery").id)==str(older.id),"saved history identity survives reload independently of active job")
	pc.widgets.mail.search.text="再開"; pc.widgets.mail.search.text_changed.emit("再開"); await frames()
	check(object("MailHistory_"+id.validate_node_name())!=null,"mail search includes the actual completed customer reply")
	pc.widgets.mail.search.text=""; pc.widgets.mail.search.text_changed.emit(""); await frames()
	pc.widgets.mail.folder_picker.select(0); pc.widgets.mail.folder_picker.item_selected.emit(0); await frames(); await press("MailContract_"+id.validate_node_name()); pc=ui.desktop
	check(game.end_day_reason().is_empty() and game.end_day(),"actual company day settlement retires completed contexts")
	game.set_process(false); check(not game.state.contract_contexts.has(id),"completed dispatch context actually retired")
	pc.widgets.mail.folder="history"; pc.widgets.mail.reading=false; pc._refresh_mail(); await frames(); await press("MailHistory_"+id.validate_node_name())
	var archived: Dictionary=object("MailDeliveryThread").get_meta("delivery")
	check(str(archived.id)==id and same(archived.checks,record.checks) and int(archived.before)==75 and int(archived.after)==60,"next-day mail retains this delivery's own checks and customer consequence")
	check(bool(archived.report_write_confirmed)==record.has("delivery_results"),"report-specific confirmation survives only if its actual observations were retained")
	var retained_request:=THREAD.request_for(game.state,record)
	check(str(retained_request.source)==("saved-request" if record.has("request_mail") else "unknown"),"next-day original request uses its retained snapshot or explicit missing state")
	if record.has("request_mail"): check(str(object("MailOriginalRequest").text)==str(record.request_mail.body).strip_edges(),"next-day request text stays exactly the delivery's saved original")
	await capture("03-next-day-retained-customer-reply")
	await capture("02-resumed-customer-reply")
	check(FileAccess.get_file_as_string(path)==source,"original paid source remains exact")
	print("MAIL_DELIVERY_UI assertions=",assertions," failures=",failures)
	ui.queue_free(); await frames(); quit(0 if failures.is_empty() else 1)
