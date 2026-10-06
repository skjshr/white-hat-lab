extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")

static func state(d, kind: String) -> Dictionary:
	if not d.advanced_ui.get(kind) is Dictionary: d.advanced_ui[kind] = {}
	return d.advanced_ui[kind]

static func label(parent: Node, text: String, size: int = 15, color: Color = UI.INK, wrap: bool = false) -> Label:
	var item := Label.new(); item.text = text
	var scale: float = float(parent.get_theme_default_font_size()) / 14.0 if parent is Control else 1.0
	item.add_theme_font_size_override("font_size", maxi(11,roundi(size * scale))); item.add_theme_color_override("font_color", color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if wrap: item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(item); return item

static func button(parent: Node, text: String, id: String, callback: Callable, icon: String = "") -> Button:
	var item := Button.new(); item.name = id; item.text = text
	item.custom_minimum_size.y = 34
	var known_icon: String = str({"next":"forward","network":"link","compare":"link","key":"person","send":"forward","download":"inbox"}.get(icon,icon))
	if not known_icon.is_empty(): item.icon = UI.symbol(known_icon); item.expand_icon = false; item.add_theme_constant_override("icon_max_width", 18)
	item.pressed.connect(callback); parent.add_child(item); return item

static func row(parent: Node) -> HFlowContainer:
	var item := HFlowContainer.new(); item.add_theme_constant_override("h_separation", 8); item.add_theme_constant_override("v_separation", 6); parent.add_child(item); return item

static func panel(parent: Node, title: String = "", color: Color = Color("f8fafc")) -> VBoxContainer:
	var card := PanelContainer.new(); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.style(color, UI.BORDER, 7, 12, 10)); parent.add_child(card)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation", 8); card.add_child(body)
	if not title.is_empty(): label(body, title, 16)
	return body

static func input(d, parent: Node, kind: String, key: String, id: String, placeholder: String = "", secret: bool = false) -> LineEdit:
	var s := state(d, kind); var item := LineEdit.new(); item.name = id
	item.text = str(s.get(key, "")); item.placeholder_text = placeholder; item.secret = secret
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL; item.custom_minimum_size = Vector2(180, 34)
	item.text_changed.connect(func(value: String): s[key] = value; d._save_session(false))
	parent.add_child(item); return item

static func editor(d, parent: Node, kind: String, key: String, id: String, fallback: String = "", editable: bool = true) -> TextEdit:
	var s := state(d, kind); var item := TextEdit.new(); item.name = id
	item.text = str(s.get(key, fallback)); item.editable = editable; item.custom_minimum_size.y = 105
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL; item.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_style(item)
	if editable: item.text_changed.connect(func(): s[key] = item.text; d._save_session(false))
	parent.add_child(item); return item

static func text_style(item: TextEdit) -> void:
	item.add_theme_color_override("font_color",UI.INK)
	item.add_theme_color_override("font_readonly_color",UI.INK)
	item.add_theme_color_override("caret_color",UI.INK)
	item.add_theme_stylebox_override("normal",UI.style(Color.WHITE,UI.BORDER,6,8,6))
	item.add_theme_stylebox_override("read_only",UI.style(Color("f2f6fa"),UI.BORDER,6,8,6))

static func table(parent: Node, id: String, columns: Array, height: float = 180) -> Tree:
	var tree := Tree.new(); tree.name = id; tree.columns = columns.size(); tree.hide_root = true
	tree.column_titles_visible = true; tree.select_mode = Tree.SELECT_ROW; tree.allow_reselect = true
	var scale: float=float(parent.get_theme_default_font_size())/14.0 if parent is Control else 1.0
	tree.custom_minimum_size.y = height * maxf(1.0,scale) if height<200 else height; tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in columns.size(): tree.set_column_title(i, str(columns[i])); tree.set_column_expand(i, true); tree.set_column_clip_content(i, true)
	parent.add_child(tree); tree.create_item(); return tree

static func table_row(tree: Tree, values: Array, metadata: Variant) -> TreeItem:
	var item := tree.create_item(tree.get_root()); item.set_metadata(0, metadata)
	for i in mini(values.size(), tree.columns): item.set_text(i, str(values[i])); item.set_tooltip_text(i, str(values[i]))
	return item

static func mount(d, parent: VBoxContainer, kind: String, title: String) -> void:
	parent.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new(); parent.add_child(head)
	var heading := label(head, title, 19); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.clip_text = true
	button(head, "検証", "AdvancedVerify", func():
		var results: Array=d.game.verify()
		var passed: int=results.filter(func(item):return bool(item.get("passed",false))).size()
		var s:=state(d,kind); s.message="受入確認  %d / %d" % [passed,results.size()]; s.result_ok=passed==results.size()
		choose(d,kind,"tab","results"), "check")
	var delivery := button(head, "納品へ", "AdvancedDelivery", d._show_app.bind("receipt"), "next")
	var nav:=HFlowContainer.new(); nav.name="InvestigationNavigation"; parent.add_child(nav)
	var feedback:=PanelContainer.new(); feedback.name="InvestigationResultBar"; parent.add_child(feedback)
	var status := label(feedback, "", 13, UI.MUTED, true); status.name = "InvestigationFeedback"
	var scroll := ScrollContainer.new(); scroll.name = "InvestigationScroll"; scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; parent.add_child(scroll)
	var body := VBoxContainer.new(); body.name = "InvestigationBody"; body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 9); scroll.add_child(body)
	d.widgets.advanced = {"family":kind,"body":body,"scroll":scroll,"delivery":delivery,"status":status,"feedback":feedback,"nav":nav,"signature":""}
	parent.resized.connect(func(): d._refresh_advanced.call_deferred())
	state(d, kind)

static func begin(d, kind: String, data: Dictionary) -> VBoxContainer:
	var w: Dictionary = d.widgets.advanced; var s := state(d, kind)
	var signature := JSON.stringify([data, s, d.game.can_deliver(),int(d.windows.advanced.size.x)])
	if str(w.get("signature", "")) == signature: return null
	w.signature = signature; w.delivery.disabled = not d.game.can_deliver()
	w.status.text = str(s.get("message", data.get("last_result", {}).get("message", "")))
	w.feedback.visible=not w.status.text.is_empty()
	var result_ok: bool=bool(s.get("result_ok",data.get("last_result",{}).get("ok",true)))
	w.feedback.add_theme_stylebox_override("panel",UI.style(Color("edf7f1") if result_ok else Color("fff1ed"),Color("aed1bc") if result_ok else Color("dfa396"),5,9,5))
	w.status.add_theme_color_override("font_color",Color("285b42") if result_ok else Color("8a3529"))
	var focus: Control = w.body.get_viewport().gui_get_focus_owner()
	var mark := {"name":"","caret":0,"scroll":int(w.get("next_scroll",w.scroll.scroll_vertical))}
	w.erase("next_scroll")
	if is_instance_valid(focus) and w.body.is_ancestor_of(focus):
		mark.name = str(focus.name)
		if focus is LineEdit: mark.caret = focus.caret_column
	for child in w.body.get_children(): w.body.remove_child(child); child.queue_free()
	for child in w.nav.get_children(): w.nav.remove_child(child); child.queue_free()
	_restore.call_deferred(d, w.body, mark)
	return w.body

static func _restore(d, body: Control, mark: Dictionary) -> void:
	if not is_instance_valid(body) or d.current_app != "advanced": return
	var scroll: ScrollContainer = body.get_parent()
	var existing: Control = body.get_viewport().gui_get_focus_owner()
	if not str(mark.name).is_empty() and not is_instance_valid(existing):
		var control: Control = body.find_child(str(mark.name), true, false)
		if is_instance_valid(control) and control.is_visible_in_tree():
			# Rebuilt controls have not finished layout; retain position while restoring focus.
			var follow_focus := scroll.follow_focus
			scroll.follow_focus = false
			control.grab_focus()
			if control is LineEdit: control.caret_column = int(mark.caret)
			scroll.follow_focus = follow_focus
	scroll.set_deferred("scroll_vertical", int(mark.scroll))

static func send(d, kind: String, action: String, args: Dictionary = {}) -> Dictionary:
	d._save_session(false)
	var result: Dictionary = d.game.advanced_action(action, args)
	state(d, kind)["message"] = str(result.get("message", "操作を記録しました。"))
	state(d,kind)["result_ok"]=bool(result.get("ok",false))
	d._save_session(false); d._refresh_advanced.call_deferred(); return result

static func choose(d, kind: String, key: String, value: Variant) -> void:
	if key=="tab" and d.widgets.has("advanced"):
		var s:=state(d,kind); s["scroll_"+str(s.get("tab",""))]=int(d.widgets.advanced.scroll.scroll_vertical)
		d.widgets.advanced.next_scroll=int(s.get("scroll_"+str(value),0))
	state(d, kind)[key] = value; d._save_session(false); d._refresh_advanced.call_deferred()

static func navigation(d,kind: String,items: Array,default_tab: String,prefix: String) -> void:
	var selected:=str(state(d,kind).get("tab",default_tab))
	for item in items:
		var b:=button(d.widgets.advanced.nav,str(item[1]),prefix+str(item[0]),choose.bind(d,kind,"tab",item[0]))
		b.toggle_mode=true; b.button_pressed=selected==str(item[0]); UI.navigation(b,b.button_pressed)

static func columns(d,parent: Node,left_width: float=340.0) -> Array:
	var width: float=float(d.windows.advanced.size.x)
	var wide: bool=width>=900
	var container: BoxContainer=HBoxContainer.new() if wide else VBoxContainer.new()
	container.add_theme_constant_override("separation",10); parent.add_child(container)
	var left:=VBoxContainer.new(); var right:=VBoxContainer.new()
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL; right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if wide: left.custom_minimum_size.x=minf(left_width,width*0.46); left.size_flags_horizontal=Control.SIZE_FILL
	container.add_child(left); container.add_child(right)
	return [left,right]

static func chip(parent: Node,text: String,color: Color=UI.MUTED) -> void:
	var frame:=PanelContainer.new(); frame.add_theme_stylebox_override("panel",UI.style(Color("edf2f7"),Color.TRANSPARENT,5,8,4)); parent.add_child(frame)
	label(frame,text,13,color)

static func checks(parent: Node, data: Dictionary) -> void:
	var box := panel(parent, "受入確認")
	for item in data.get("checks", []): label(box, ("✓  " if item.get("passed", false) else "○  ") + UI.copy(str(item.get("label_key", ""))), 14, UI.GREEN if item.get("passed", false) else UI.MUTED, true)

static func observations(parent: Node, rows: Array, id: String = "InvestigationObservations") -> Tree:
	var tree := table(parent, id, ["記録", "操作", "対象", "結果"], 150)
	for item in rows: table_row(tree, [item.get("id", ""), item.get("operation", ""), item.get("target", ""), item.get("status", "")], item)
	return tree
