extends RefCounted
## Operator controls render public exercise observations, never private actor state.
const UI = preload("res://scripts/ui_theme.gd")
const INK := Color("243746")
const MUTED := Color("657986")
const GREEN := Color("176e62")
const PALE := Color("e8f3ee")
const BORDER := Color("dbe4e9")
const AMBER := Color("9a6519")
const RED := Color("aa4237")
const FIELD_LABELS := {"customer":"取引先","issue_date":"発行日","due_date":"支払期限","line_items":"明細・単価","notes":"備考"}

var d
var ui: Dictionary
var exercise: Dictionary
var send: Callable
var redraw: Callable
var navigate: Callable
var scale := 1.0
var narrow := false

static func defaults(desktop) -> void:
	if not desktop.pentest_ui.get("incident_ui") is Dictionary: desktop.pentest_ui.incident_ui = {}
	var initial := {"section":"events","variant":"mixed","seed":"","selected_event":"","selected_session":"","invoice_id":"","versions":{},"source_version":0,"fields":[],"feedback":"","error":false,"show_chart":false,"show_context":false,"show_archive":false,"show_probe":false,"probe":{},"versions_dirty":false}
	for key in initial:
		if not desktop.pentest_ui.incident_ui.has(key): desktop.pentest_ui.incident_ui[key] = initial[key]

static func receive(desktop, result: Dictionary, args: Dictionary) -> void:
	defaults(desktop)
	var state: Dictionary = desktop.pentest_ui.incident_ui
	var response: Dictionary = result.get("response",{})
	var status := int(response.get("status",0))
	var payload: Dictionary = response.get("data",{}) if response.get("data",{}) is Dictionary else {}
	state.error = not bool(result.get("ok",false)) or status >= 400
	state.feedback = str(result.get("message",payload.get("message","")))
	if state.error: return
	match str(args.get("op","")):
		"versions":
			state.versions = payload.duplicate(true); state.invoice_id = str(payload.get("invoice_id",state.invoice_id)); state.versions_dirty = false
			if not payload.get("versions",[]).any(func(row): return int(row.get("version",0)) == int(state.source_version)):
				state.source_version = int(payload.get("versions",[])[0].get("version",0)) if not payload.get("versions",[]).is_empty() else 0
			state.fields = []
		"restore_version": state.versions_dirty = true
		"business_probe": state.probe = payload.duplicate(true)
		"assess", "finish":
			state.section = "result"
			_reveal_result.call_deferred(desktop,str(desktop.pentest_ui.get("_context_key","main")))

static func _reveal_result(desktop, context: String) -> void:
	# The result replaces a scrolled form. Wait for wrapped rows to settle before
	# aligning the measured outcome, without borrowing focus from another app.
	for frame in range(3):
		if not is_instance_valid(desktop): return
		await desktop.get_tree().process_frame
	if not is_instance_valid(desktop) or str(desktop.pentest_ui.get("_context_key","main")) != context or str(desktop.pentest_ui.tab) != "operations" or str(desktop.pentest_ui.incident_ui.section) != "result": return
	var root: Control = desktop.widgets.advanced.root
	if not is_instance_valid(root): return
	var scroll := root.find_child("PentestScroll",true,false) as ScrollContainer
	var heading := root.find_child("IncidentResultSummary",true,false) as Control
	if is_instance_valid(scroll) and is_instance_valid(heading): scroll.scroll_vertical += roundi(heading.global_position.y-scroll.global_position.y)

func build(desktop, parent: VBoxContainer, data: Dictionary, dispatch: Callable, refresh: Callable, open_tab: Callable) -> void:
	d = desktop; defaults(d); ui = d.pentest_ui.incident_ui
	exercise = data.get("exercise",{})
	send = dispatch; redraw = refresh; navigate = open_tab
	scale = float(d.game.settings.get("text_scale",1.0)); narrow = bool(d.widgets.advanced.get("narrow",false))
	if not bool(exercise.get("active",false)):
		_lobby(parent)
		_feedback(parent)
		return
	_header(parent)
	_feedback(parent)
	var tabs := _flow(parent)
	for spec in [["events","イベント","clock"],["sessions","セッション","users"],["versions","請求書の版","file"],["result","対応結果","check"]]:
		var button := _button(tabs,str(spec[1]),"IncidentTab_"+str(spec[0]),func(): ui.section = str(spec[0]); redraw.call(),str(ui.section) == str(spec[0]),str(spec[2]))
		button.toggle_mode = true; button.set_pressed_no_signal(str(ui.section) == str(spec[0]))
	match str(ui.section):
		"sessions": _sessions(parent)
		"versions": _versions(parent)
		"result": _results(parent)
		_: _events(parent)

func _lobby(parent: VBoxContainer) -> void:
	var title := _row(parent)
	_icon(title,"monitor",30)
	_label(title,"対応演習",24,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var context: Dictionary = exercise.get("context",{})
	_label(parent,str(context.get("brief","請求サービスのコピーで、活動記録を調べ、対処と業務の復旧を行います。")),14,MUTED)
	var path := _flow(parent)
	for item in [["clock","記録を調べる"],["shield","対処する"],["refresh","業務を確かめる"]]:
		var step := _panel(path,Color("f3f7f9")); var line := _row(step); _icon(line,str(item[0]),20); _label(line,str(item[1]),14,INK)
	var previous := not str(exercise.get("run_id","")).is_empty()
	var concluded := str(exercise.get("phase","")) == "concluded"
	if previous:
		var pending := _row(parent)
		_label(pending,"終了した演習" if concluded else "中断した演習  ·  経過 %d 分"%int(exercise.get("tick",0)),15,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(pending,"結果を見る" if concluded else "演習を再開","IncidentResume",func(): send.call("incident_resume",{}),true,"play")
	if previous and not concluded: return
	_start_fields(parent)
	_button(parent,"新しい条件で再挑戦" if previous else "演習を開始","IncidentRestart" if previous else "IncidentStart",func(): _start(previous),true,"play")
	_label(parent,"通常の案件データと編集中の内容は、この演習とは別に保持されます。",12,MUTED)

func _start_fields(parent: VBoxContainer) -> void:
	var row := _row(parent)
	var variant := OptionButton.new(); variant.name = "IncidentVariant"; variant.custom_minimum_size.y = 36*scale; variant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for spec in [["mixed","標準シナリオ"],["exfil","通信中心のシナリオ"]]:
		variant.add_item(str(spec[1])); variant.set_item_metadata(variant.item_count-1,str(spec[0]))
		if str(ui.variant) == str(spec[0]): variant.select(variant.item_count-1)
	variant.item_selected.connect(func(index): ui.variant = str(variant.get_item_metadata(index)))
	variant.add_theme_font_size_override("font_size",int(14*scale)); variant.add_theme_color_override("font_color",INK); row.add_child(variant)
	var seed := _input(row,"IncidentSeed",str(ui.seed),"条件番号（空欄で変更）",func(value): ui.seed = value)
	seed.tooltip_text = "同じ番号で同じ初期条件を再現できます。"

func _start(restart: bool) -> void:
	var args := {"variant":str(ui.variant)}
	var value := str(ui.seed).strip_edges()
	if not value.is_empty():
		if not value.is_valid_int(): ui.feedback = "条件番号は整数で入力してください。"; ui.error = true; redraw.call(); return
		args["seed"] = int(value)
	send.call("incident_restart" if restart else "incident_start",args)

func _header(parent: VBoxContainer) -> void:
	var row := _row(parent); _icon(row,"monitor",22)
	_label(row,"サービス運用",20,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chip(row,"終了" if _concluded() else "演習中",MUTED if _concluded() else GREEN)
	_chip(row,"経過 %d 分"%int(exercise.get("tick",0)),INK)
	_chip(row,"条件 %d"%int(exercise.get("seed",0)),MUTED)
	_button(row,"通常業務へ","IncidentLeave",func(): send.call("incident_leave",{}),false,"back")
	var tools := _flow(parent)
	if not _concluded():
		_button(tools,"1分進める","IncidentAdvance",func(): _op("advance"),false,"clock")
		_button(tools,"業務を確認","IncidentBusinessProbe",func(): _op("business_probe"),false,"play")
		_button(tools,"対応を評価","IncidentAssess",func(): _op("assess"),true,"check")
		var paused := bool(exercise.get("export_paused",false))
		_button(tools,"CSV受付を再開" if paused else "CSV受付を一時停止","IncidentExportPause",func(): _op("set_export_paused",{"paused":not paused}),false,"refresh" if paused else "shield")
		_chip(tools,"CSV 一時停止中" if paused else "CSV 受付中",AMBER if paused else GREEN)

func _events(parent: VBoxContainer) -> void:
	var tools := _flow(parent)
	_button(tools,"記録を更新","IncidentRefresh",func(): _op("audit"),false,"refresh")
	_button(tools,"処理の推移","IncidentChartToggle",func(): ui.show_chart = not bool(ui.show_chart); redraw.call(),bool(ui.show_chart),"monitor")
	_button(tools,"顧客の運用予定","IncidentContextToggle",func(): ui.show_context = not bool(ui.show_context); redraw.call(),bool(ui.show_context),"mail")
	_label(tools,"保存した記録 %d"%exercise.get("evidence",[]).size(),12,MUTED)
	if bool(ui.show_context): _context(parent)
	if bool(ui.show_chart): _chart(parent)
	var rows: Array = exercise.get("events",[])
	var selected := _find(rows,str(ui.selected_event),"id")
	var split: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new(); split.add_theme_constant_override("separation",14); parent.add_child(split)
	if not narrow or selected.is_empty():
		var listing := _column(split,0); listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var columns := _row(listing); _cell(columns,"時刻 / 結果",0.85,12,MUTED); _cell(columns,"操作・対象",3.2,12,MUTED); _cell(columns,"利用者",1.1,12,MUTED)
		var scroller := _table_scroll(listing,"IncidentEventTable")
		for index in range(rows.size()-1,-1,-1):
			var event: Dictionary = rows[index]
			var id := str(event.get("id",""))
			var line := _table_row(scroller,"IncidentEvent_"+id.validate_node_name(),id == str(ui.selected_event),func(): ui.selected_event = id; redraw.call())
			line.get_parent().get_parent().set_meta("event_id",id)
			var status := str(int(event.get("status",0))) if str(event.get("kind","request")) != "customer_note" else "連絡"
			_cell(line,"%02d分 · %s"%[int(event.get("tick",0)),status],0.85,12,RED if int(event.get("status",0)) >= 400 else MUTED)
			_cell(line,str(event.get("summary",str(event.get("method",""))+" "+str(event.get("path","")))),3.2,13,INK)
			_cell(line,str(event.get("principal","—")),1.1,12,MUTED)
		if rows.is_empty(): _label(scroller,"記録はまだありません。",14,MUTED)
	if not selected.is_empty(): _event_detail(_column(split,9),selected)

func _event_detail(parent: VBoxContainer, event: Dictionary) -> void:
	parent.name = "IncidentEventDetail"; parent.set_meta("event_id",str(event.get("id",""))); parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if narrow: _button(parent,"記録一覧へ","IncidentEventBack",func(): ui.selected_event = ""; redraw.call(),false,"back")
	var title := _row(parent); _icon(title,"mail" if str(event.get("kind","")) == "customer_note" else "terminal",20)
	_label(title,"%02d分 · %s"%[int(event.get("tick",0)),str(event.get("id",""))],15,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(parent,str(event.get("summary","")),15,INK)
	var actions := _flow(parent)
	var facts := _panel(parent,Color("f5f8fa"))
	for pair in [["操作",str(event.get("method",""))+" "+str(event.get("path",""))],["利用者",str(event.get("principal",""))],["端末 / 接続元",str(event.get("device",""))+" / "+str(event.get("source",""))],["セッション",str(event.get("session_id",""))],["請求書",str(event.get("invoice_id",""))],["応答",str(event.get("status",""))],["転送量",str(int(event.get("bytes",0)))+" bytes"]]:
		if not str(pair[1]).is_empty(): _fact(facts,str(pair[0]),str(pair[1]))
	var pinned: bool = exercise.get("evidence",[]).any(func(row): return str(row.get("id","")) == str(event.get("id","")))
	var pin := _button(actions,"保存を解除" if pinned else "記録を保存","IncidentUnpinEvent" if pinned else "IncidentPinEvent",func(): _op("unpin_event" if pinned else "pin_event",{"event_id":str(event.id)}),false,"attachment")
	pin.disabled = _concluded()
	if _concluded(): pin.tooltip_text = "終了した演習の保存記録は変更できません。"
	if not str(event.get("session_id","" )).is_empty(): _button(actions,"セッションを見る","IncidentEventSession",func(): ui.section = "sessions"; ui.selected_session = str(event.session_id); redraw.call(),false,"users")
	if not str(event.get("invoice_id","" )).is_empty(): _button(actions,"請求書の版を見る","IncidentEventVersions",func(): ui.section = "versions"; ui.invoice_id = str(event.invoice_id); _op("versions",{"invoice_id":str(event.invoice_id)}),false,"file")
	var changes: Dictionary = event.get("changes",{})
	for key in changes:
		if not FIELD_LABELS.has(str(key)) or not changes[key] is Dictionary: continue
		var changed := _panel(parent,Color("fff8ec")); _label(changed,str(FIELD_LABELS[str(key)]),13,INK)
		var values := _row(changed)
		var before := _label(values,_field_text(str(key),changes[key].get("before")),12,MUTED); before.size_flags_horizontal = Control.SIZE_EXPAND_FILL; before.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_icon(values,"arrow_right",16)
		var after := _label(values,_field_text(str(key),changes[key].get("after")),12,INK); after.size_flags_horizontal = Control.SIZE_EXPAND_FILL; after.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _sessions(parent: VBoxContainer) -> void:
	var tools := _flow(parent); _button(tools,"セッションを更新","IncidentRefresh",func(): _op("sessions"),false,"refresh")
	var rows: Array = exercise.get("sessions",[]); var selected := _find(rows,str(ui.selected_session),"session_id")
	var split: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new(); split.add_theme_constant_override("separation",14); parent.add_child(split)
	if not narrow or selected.is_empty():
		var listing := _column(split,0); var header := _row(listing)
		_cell(header,"利用者 / 状態",1.2,12,MUTED); _cell(header,"端末・接続元",2.0,12,MUTED); _cell(header,"最終利用",0.8,12,MUTED)
		var table := _table_scroll(listing,"IncidentSessionTable")
		for session in rows:
			var id := str(session.get("session_id","")); var revoked := bool(session.get("revoked",false))
			var line := _table_row(table,"IncidentSession_"+id.validate_node_name(),id == str(ui.selected_session),func(): ui.selected_session = id; redraw.call())
			line.get_parent().get_parent().set_meta("session_id",id)
			_cell(line,str(session.get("principal",session.get("username","")))+(" · 失効" if revoked else " · 有効"),1.2,13,MUTED if revoked else INK)
			_cell(line,str(session.get("device",""))+" / "+str(session.get("source","")),2.0,12,MUTED)
			_cell(line,"%d分"%int(session.get("last_tick",0)),0.8,12,MUTED)
	if selected.is_empty(): return
	var detail := _column(split,9); detail.name = "IncidentSessionDetail"; detail.set_meta("session_id",str(selected.get("session_id","")))
	if narrow: _button(detail,"セッション一覧へ","IncidentSessionBack",func(): ui.selected_session = ""; redraw.call(),false,"back")
	_label(detail,str(selected.get("device","")),19,INK)
	var revoked := bool(selected.get("revoked",false)); _chip(detail,"失効済み" if revoked else "有効",MUTED if revoked else GREEN)
	var revoke := _button(detail,"このセッションを失効","IncidentRevokeSession",func(): _op("revoke_session",{"session_id":str(selected.session_id)}),false,"shield"); revoke.disabled = revoked or _concluded()
	for pair in [["識別子",str(selected.get("session_id",""))],["利用者",str(selected.get("principal",selected.get("username","")))],["接続元",str(selected.get("source",""))],["作成",str(selected.get("created_tick",0))+"分"],["最終利用",str(selected.get("last_tick",0))+"分"]]: _fact(detail,str(pair[0]),str(pair[1]))
	_label(detail,"失効した接続は元に戻りません。利用を再開する場合は新しいログインが必要です。",12,MUTED)
	var related: Array = exercise.get("events",[]).filter(func(row): return str(row.get("session_id","")) == str(selected.get("session_id","")))
	for item in related.slice(maxi(0,related.size()-5)):
		_button(detail,"%02d分 · %s"%[int(item.get("tick",0)),str(item.get("method",""))+" "+str(item.get("path",""))],"IncidentRelatedEvent_"+str(item.get("id","")).validate_node_name(),func(): ui.section = "events"; ui.selected_event = str(item.id); redraw.call(),false,"terminal")

func _versions(parent: VBoxContainer) -> void:
	var tools := _row(parent)
	_input(tools,"IncidentInvoiceId",str(ui.invoice_id),"請求番号",func(value): ui.invoice_id = value)
	_button(tools,"版を取得","IncidentLoadVersions",func(): _op("versions",{"invoice_id":str(ui.invoice_id).strip_edges()}),false,"refresh")
	var data: Dictionary = ui.versions
	if data.is_empty(): _label(parent,"活動記録または請求書に表示された番号を選択してください。",13,MUTED); return
	var rows: Array = data.get("versions",[]); var current := _find(rows,int(data.get("current_version",0)),"version"); var source := _find(rows,int(ui.source_version),"version")
	var meta := _row(parent); _label(meta,str(data.get("invoice_id",""))+"  ·  現在の版 "+str(int(data.get("current_version",0))),17,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chooser := OptionButton.new(); chooser.name = "IncidentSourceVersion"; chooser.custom_minimum_size.y = 36*scale; chooser.add_theme_font_size_override("font_size",int(13*scale)); chooser.add_theme_color_override("font_color",INK); meta.add_child(chooser)
	for item in rows:
		chooser.add_item("版 %d · %d分 · %s"%[int(item.get("version",0)),int(item.get("tick",0)),str(item.get("actor",""))]); chooser.set_item_metadata(chooser.item_count-1,int(item.get("version",0)))
		if int(item.get("version",0)) == int(ui.source_version): chooser.select(chooser.item_count-1)
	chooser.item_selected.connect(func(index): ui.source_version = int(chooser.get_item_metadata(index)); ui.fields = []; redraw.call())
	if source.is_empty() or current.is_empty(): return
	var latest_fields: Dictionary = current.get("fields",{}); var source_fields: Dictionary = source.get("fields",{})
	var heading := _row(parent); _cell(heading,"戻す項目",0.8,12,MUTED); _cell(heading,"現在の値",2.0,12,MUTED); _cell(heading,"選択した版の値",2.0,12,MUTED)
	for key in FIELD_LABELS:
		var changed: bool = latest_fields.get(key) != source_fields.get(key)
		var box := _panel(parent,Color("fff8ec") if changed else Color("f7fafb")); var row := _row(box)
		var check := CheckBox.new(); check.name = "IncidentField_"+str(key); check.text = str(FIELD_LABELS[key]); check.custom_minimum_size.x = 128*scale; check.add_theme_font_size_override("font_size",int(13*scale)); check.add_theme_color_override("font_color",INK); check.button_pressed = str(key) in ui.fields; check.disabled = not changed or bool(ui.versions_dirty) or _concluded(); row.add_child(check)
		check.toggled.connect(func(on):
			if on and str(key) not in ui.fields: ui.fields.append(str(key))
			elif not on: ui.fields.erase(str(key))
			var restore := d.widgets.advanced.root.find_child("IncidentRestoreVersion",true,false) as Button
			if is_instance_valid(restore): restore.disabled = ui.fields.is_empty() or bool(ui.versions_dirty) or _concluded()
		)
		var before := _label(row,_field_text(str(key),latest_fields.get(key)),13,INK); before.size_flags_horizontal = Control.SIZE_EXPAND_FILL; before.size_flags_stretch_ratio = 2; before.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var after := _label(row,_field_text(str(key),source_fields.get(key)),13,GREEN if changed else MUTED); after.size_flags_horizontal = Control.SIZE_EXPAND_FILL; after.size_flags_stretch_ratio = 2; after.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var restore := _button(parent,"選択した項目を復元","IncidentRestoreVersion",func(): _op("restore_version",{"invoice_id":str(data.get("invoice_id","")),"source_version":int(ui.source_version),"expected_version":int(data.get("current_version",0)),"fields":ui.fields.duplicate()}),true,"refresh")
	restore.disabled = ui.fields.is_empty() or bool(ui.versions_dirty) or _concluded()
	_label(parent,"版を再取得すると、復元後の値を比較できます。" if bool(ui.versions_dirty) else "選んだ項目だけを、新しい版として保存します。",12,MUTED)

func _results(parent: VBoxContainer) -> void:
	var result: Dictionary = exercise.get("result",{}) if _concluded() else exercise.get("assessment",{})
	var summary := _label(parent,"対応結果" if _concluded() else "業務の状態を確認",22,INK); summary.name = "IncidentResultSummary"
	if _concluded():
		var metrics: Dictionary = result.get("metrics",{})
		var impact := _flow(parent)
		for spec in [["disclosure_count","CSVの取得回数"],["remaining_damage","未復元の変更"],["legitimate_failures","通常業務の失敗"],["evidence_count","保存した記録"]]:
			if not metrics.has(str(spec[0])): continue
			var metric := _panel(impact,Color("f5f8fa")); _label(metric,str(spec[1]),12,MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
			var value := _label(metric,str(int(metrics[str(spec[0])]))+(" 回" if str(spec[0]) in ["disclosure_count","legitimate_failures"] else " 件"),24,INK); value.name = "IncidentMetric_"+str(spec[0]); value.autowrap_mode = TextServer.AUTOWRAP_OFF
		var debrief: Variant = result.get("debrief","")
		if debrief is String and not debrief.is_empty(): _label(parent,debrief,14,INK)
		elif debrief is Array:
			for line in debrief: _label(parent,str(line),14,INK)
		elif debrief is Dictionary:
			_label(parent,str(debrief.get("summary","")),14,INK).name = "IncidentDebriefSummary"
			var facts := _flow(parent); _chip(facts,"請求書 "+str(debrief.get("invoice_id","")),INK); _chip(facts,"接続 "+str(debrief.get("session_id","")),INK)
	if result.is_empty():
		_label(parent,"業務確認で実際の操作を試し、現在の対応結果を評価します。",14,MUTED)
	else:
		for check in result.get("checks",[]):
			var row := _row(parent); var passed := bool(check.get("passed",false)); _icon(row,"check" if passed else "warning",20)
			var text := _column(row,3); _label(text,str(check.get("label","")),15,GREEN if passed else AMBER)
			if not passed: _label(text,str(check.get("message","")),12,MUTED)
	if not _concluded():
		var tools := _flow(parent)
		_button(tools,"業務を確認","IncidentResultProbe",func(): _op("business_probe"),false,"play")
		_button(tools,"評価を更新","IncidentResultAssess",func(): _op("assess"),true,"refresh")
		_button(tools,"終了して結果を見る","IncidentFinish",func(): _op("finish"),false,"check")
	var details := _flow(parent)
	var probe: Dictionary = ui.probe
	if not probe.is_empty():
		_button(details,"業務確認の通信 · "+("完了" if bool(probe.get("passed",false)) else "要確認"),"IncidentProbeDetails",func(): ui.show_probe = not bool(ui.show_probe); redraw.call(),false,"code")
	_button(details,"処理の推移","IncidentResultChart",func(): ui.show_chart = not bool(ui.show_chart); redraw.call(),false,"chart")
	if bool(ui.show_probe) and not probe.is_empty():
		for step in probe.get("steps",[]):
			var row := _row(parent); _chip(row,str(int(step.get("status",0))),GREEN if int(step.get("status",0)) < 400 else RED); _label(row,str(step.get("method",""))+" "+str(step.get("path","")),13,INK)
	if bool(ui.show_chart): _chart(parent)
	if _concluded():
		var debrief: Variant = result.get("debrief",{})
		if debrief is Dictionary:
			_label(parent,str(debrief.get("notes","")),13,MUTED).name = "IncidentDebriefNotes"
			for disclosure in debrief.get("disclosures",[]):
				var row := _row(parent); _icon(row,"attachment",18); _label(row,"%d分 · %s · %d bytes · %s"%[int(disclosure.get("tick",0)),str(disclosure.get("invoice_id","")),int(disclosure.get("bytes",0)),str(disclosure.get("event_id",""))],13,RED)
		_start_fields(parent); _button(parent,"新しい条件で再挑戦","IncidentRestart",func(): _start(true),true,"play")
	_archive(parent)

func _archive(parent: VBoxContainer) -> void:
	var results: Array = exercise.get("results",[])
	if results.is_empty(): return
	_button(parent,"過去の演習 %d件"%results.size(),"IncidentArchiveToggle",func(): ui.show_archive = not bool(ui.show_archive); redraw.call(),false,"clock")
	if not bool(ui.show_archive): return
	var archive := _column(parent,7); archive.name = "IncidentArchive"
	var header := _row(archive); _cell(header,"条件 / 経過",1.2,12,MUTED); _cell(header,"CSV取得回数",1.0,12,MUTED); _cell(header,"未復元",1.0,12,MUTED); _cell(header,"通常業務の失敗",1.4,12,MUTED)
	for result in results:
		var metrics: Dictionary = result.get("result",{}).get("metrics",{}); var row := _row(archive)
		_cell(row,"%d / %d分"%[int(result.get("seed",0)),int(result.get("tick",0))],1.2,13,INK)
		for spec in [["disclosure_count",1.0],["remaining_damage",1.0],["legitimate_failures",1.4]]: _cell(row,str(int(metrics.get(str(spec[0]),0))),float(spec[1]),13,INK)

func _context(parent: VBoxContainer) -> void:
	var context: Dictionary = exercise.get("context",{}); var box := _panel(parent,Color("f5f8fa"))
	_label(box,str(context.get("title","顧客の運用予定")),16,INK)
	if not str(context.get("brief","" )).is_empty(): _label(box,str(context.brief),13,MUTED)
	for order in context.get("work_orders",[]):
		_label(box,str(order.get("principal",""))+" · "+str(order.get("device",""))+" · "+str(order.get("invoice_id","")),13,INK)
		_label(box,str(order.get("details",order.get("operation",""))),13,MUTED)

func _chart(parent: VBoxContainer) -> void:
	var box := _panel(parent,Color("f5f8fa")); var head := _row(box)
	_label(head,"記録された要求の推移（累積）",14,INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chip(head,"受理",GREEN); _chip(head,"拒否・失敗",RED)
	var plot := TrafficPlot.new(); plot.name = "IncidentTrafficChart"; plot.points = exercise.get("series",[]).duplicate(true); plot.custom_minimum_size.y = 125*scale; plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_child(plot)

class TrafficPlot extends Control:
	var points: Array = []
	func _draw() -> void:
		var font := UI.font(400); var bottom := size.y-24; var height := maxf(1,bottom-14); var width := maxf(1,size.x-40); var maximum := 1.0
		var first_tick := float(points.front().get("tick",0)) if not points.is_empty() else 0.0
		var last_tick := float(points.back().get("tick",0)) if not points.is_empty() else 0.0
		for point in points: maximum = maxf(maximum,maxf(float(point.get("request_success",0)),float(point.get("request_failure",0))))
		draw_line(Vector2(30,10),Vector2(30,bottom),BORDER); draw_line(Vector2(30,bottom),Vector2(size.x-10,bottom),BORDER)
		draw_string(font,Vector2(0,18),str(int(maximum)),HORIZONTAL_ALIGNMENT_LEFT,-1,11,MUTED); draw_string(font,Vector2(12,bottom),"0",HORIZONTAL_ALIGNMENT_LEFT,-1,11,MUTED)
		for series in [["request_success",GREEN],["request_failure",RED]]:
			var positions := PackedVector2Array()
			for index in points.size():
				var point: Dictionary = points[index]; var x := 30+width*(float(point.get("tick",0))-first_tick)/maxf(1,last_tick-first_tick); var y := bottom-height*float(point.get(str(series[0]),0))/maximum; positions.append(Vector2(x,y)); draw_circle(Vector2(x,y),2.5,series[1])
			if positions.size() > 1: draw_polyline(positions,series[1],2,true)
		if not points.is_empty():
			draw_string(font,Vector2(30,size.y-5),"%d分"%int(points.front().get("tick",0)),HORIZONTAL_ALIGNMENT_LEFT,-1,11,MUTED)
			draw_string(font,Vector2(size.x-50,size.y-5),"%d分"%int(points.back().get("tick",0)),HORIZONTAL_ALIGNMENT_LEFT,-1,11,MUTED)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED: queue_redraw()

func _feedback(parent: VBoxContainer) -> void:
	if str(ui.feedback).is_empty(): return
	var label := _label(parent,str(ui.feedback),13,RED if bool(ui.error) else GREEN); label.name = "IncidentFeedback"

func _op(op: String, args: Dictionary = {}) -> void:
	args = args.duplicate(true); args["op"] = op; args["run_id"] = str(exercise.get("run_id","")); args["command_id"] = (str(exercise.get("run_id",""))+":"+op+":"+str(Time.get_ticks_usec())).sha256_text().left(24)
	send.call("incident_action",args)

func _concluded() -> bool: return str(exercise.get("phase","")) == "concluded"

func _find(rows: Array, value: Variant, key: String) -> Dictionary:
	for row in rows:
		if str(row.get(key,"")) == str(value): return row
	return {}

func _field_text(key: String, value: Variant) -> String:
	if key == "line_items" and value is Array:
		var lines: Array[String] = []
		for item in value: lines.append("%s  ×%d  ¥%d"%[str(item.get("description","")),int(item.get("quantity",0)),int(item.get("unit_price",0))])
		return "\n".join(lines)
	return str(value) if value != null and not str(value).is_empty() else "—"

func _column(parent: Node, spacing := 8) -> VBoxContainer:
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",spacing); parent.add_child(box); return box

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",10); parent.add_child(row); return row

func _flow(parent: Node) -> HFlowContainer:
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation",8); row.add_theme_constant_override("v_separation",6); parent.add_child(row); return row

func _panel(parent: Node, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.add_theme_stylebox_override("panel",UI.style(color,BORDER,10,8,6)); parent.add_child(panel); return _column(panel,7)

func _label(parent: Node, text: String, point: int, color: Color) -> Label:
	var label := Label.new(); label.text = text; label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.add_theme_font_override("font",UI.font(400)); label.add_theme_font_size_override("font_size",int(point*scale)); label.add_theme_color_override("font_color",color); label.autowrap_mode = TextServer.AUTOWRAP_OFF if parent is HBoxContainer or parent is HFlowContainer else TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label); return label

func _cell(parent: Node, text: String, weight: float, point: int, color: Color) -> Label:
	var label := _label(parent,text,point,color); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.size_flags_vertical = Control.SIZE_SHRINK_CENTER; label.size_flags_stretch_ratio = weight; label.clip_text = true; label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; label.tooltip_text = text; return label

func _chip(parent: Node, text: String, color: Color) -> void:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER; panel.add_theme_stylebox_override("panel",UI.style(color.lightened(0.9),Color.TRANSPARENT,8,4,4)); parent.add_child(panel); _label(panel,text,12,color).autowrap_mode = TextServer.AUTOWRAP_OFF

func _icon(parent: Node, name: String, point: int) -> void:
	var icon := TextureRect.new(); icon.texture = UI.symbol(_symbol(name)); icon.custom_minimum_size = Vector2(point,point)*scale; icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER; parent.add_child(icon)

func _button(parent: Node, text: String, id: String, callback: Callable, primary := false, icon := "") -> Button:
	var button: Button = d._button(text,callback); button.name = id; button.custom_minimum_size.y = 34*scale; button.add_theme_font_size_override("font_size",int(13*scale)); button.icon = UI.symbol(_symbol(icon)) if not icon.is_empty() else null; button.expand_icon = false; button.add_theme_constant_override("icon_max_width",int(17*scale)); button.add_theme_stylebox_override("normal",UI.style(GREEN if primary else Color.WHITE,GREEN if primary else BORDER,11,7,5)); button.add_theme_stylebox_override("hover",UI.style(Color("258777") if primary else PALE,GREEN,11,7,5)); button.add_theme_color_override("font_color",Color.WHITE if primary else INK); button.add_theme_color_override("font_hover_color",Color.WHITE if primary else GREEN); parent.add_child(button); return button

func _symbol(name: String) -> String:
	return str({"monitor":"chart","users":"person","warning":"help","shield":"stop","mail":"inbox","terminal":"code","arrow_right":"forward"}.get(name,name))

func _input(parent: Node, id: String, value: String, placeholder: String, changed: Callable) -> LineEdit:
	var field := LineEdit.new(); field.name = id; field.text = value; field.placeholder_text = placeholder; field.custom_minimum_size.y = 36*scale; field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; field.expand_to_text_length = false; field.add_theme_font_size_override("font_size",int(14*scale)); field.add_theme_color_override("font_color",INK); field.add_theme_stylebox_override("normal",UI.style(Color("f7fafb"),BORDER,10,8,4)); field.add_theme_stylebox_override("focus",UI.style(Color.WHITE,GREEN,10,8,4)); field.text_changed.connect(changed); parent.add_child(field); return field

func _table_scroll(parent: Node, id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.name = id; scroll.follow_focus = true; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.custom_minimum_size.y = (220 if not narrow else 165)*scale; scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(scroll); return _column(scroll,1)

func _table_row(parent: Node, id: String, selected: bool, callback: Callable) -> HBoxContainer:
	var button := _button(parent,"",id,callback); button.custom_minimum_size.y = 48*scale; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.add_theme_stylebox_override("normal",UI.style(PALE if selected else Color.WHITE,GREEN if selected else BORDER,10,7,0))
	var margin := MarginContainer.new(); margin.mouse_filter = Control.MOUSE_FILTER_IGNORE; margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",10); margin.add_theme_constant_override("margin_right",10); button.add_child(margin)
	var row := _row(margin); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; return row

func _fact(parent: Node, title: String, value: String) -> void:
	var row := _row(parent); var key := _label(row,title,12,MUTED); key.custom_minimum_size.x = 94*scale; var text := _label(row,value,13,INK); text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
