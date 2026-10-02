extends RefCounted
class_name OSIdentityConsole

const COPY = preload("res://scripts/ui_theme.gd")
const MASTHEAD := Color("17191b")
const NAV := Color("25282a")
const NAV_ACTIVE := Color("3a3f42")
const PAPER := Color("ffffff")
const SUBTLE := Color("f1f2f3")
const INK := Color("1f2326")
const MUTED := Color("687178")
const BLUE := Color("0b6fc4")
const BORDER := Color("d7dadd")

static func _copy(key: String, fallback: String = "") -> String:
	return COPY.copy(key, fallback)

static func _shell_arg(value: String) -> String:
	if value.contains("\n") or value.contains("\r"): return ""
	return "'" + value.replace("'", "'\"'\"'") + "'"

static func _secret_arg(value: String) -> String:
	if value.is_empty() or value.length() > 128: return ""
	for character in value:
		if character == "\n" or character == "\r" or character == "\t" or character.unicode_at(0) < 32: return ""
	return _shell_arg(value)

static func _st(d) -> Dictionary:
	if not d.identity_ui is Dictionary:
		d.identity_ui = {}
	return d.identity_ui

static func _rerender(d) -> void:
	d._render_identity()

static func _reflow_password_row(shell: Control, row_name: String, label_name: String, field_name: String, inline_fields: bool, text_scale: float) -> void:
	var row := shell.find_child(row_name, true, false) as BoxContainer
	var field_label := shell.find_child(label_name, true, false) as Label
	var field := shell.find_child(field_name, true, false) as LineEdit
	if not is_instance_valid(row) or not is_instance_valid(field_label) or not is_instance_valid(field): return
	if row.vertical == inline_fields: row.vertical = not inline_fields
	var separation := 12 if inline_fields else 2
	if row.get_theme_constant("separation") != separation: row.add_theme_constant_override("separation", separation)
	var label_width := 160.0 * text_scale if inline_fields else 0.0
	if not is_equal_approx(field_label.custom_minimum_size.x, label_width): field_label.custom_minimum_size.x = label_width
	var label_flags := Control.SIZE_SHRINK_BEGIN if inline_fields else Control.SIZE_EXPAND_FILL
	if field_label.size_flags_horizontal != label_flags: field_label.size_flags_horizontal = label_flags
	var wrapping := TextServer.AUTOWRAP_OFF if inline_fields else TextServer.AUTOWRAP_WORD_SMART
	if field_label.autowrap_mode != wrapping: field_label.autowrap_mode = wrapping
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

static func _reflow(d, shell: Control) -> void:
	if not is_instance_valid(shell) or not is_instance_valid(d.windows.browser): return
	var scale := maxf(1.0, float(d.game.settings.get("text_scale", 1.0)))
	var width := float(d.windows.browser.size.x)
	var narrow_nav := width / scale < 1100.0
	var compact_nav := narrow_nav and not bool(_st(d).get("nav_expanded", false))
	var desired_height := maxf(360.0, float(d.windows.browser.size.y) - 86.0)
	if not is_equal_approx(shell.custom_minimum_size.y, desired_height): shell.custom_minimum_size.y = desired_height
	var nav_panel := shell.find_child("IdentityNavigationPanel", true, false) as Control
	var nav_width := 156.0 if compact_nav else 205.0
	if is_instance_valid(nav_panel) and not is_equal_approx(nav_panel.custom_minimum_size.x, nav_width): nav_panel.custom_minimum_size.x = nav_width
	var nav_items := shell.find_child("IdentityNavigationItems", true, false) as Control
	var nav_items_width := 136.0 if compact_nav else 185.0
	if is_instance_valid(nav_items) and not is_equal_approx(nav_items.custom_minimum_size.x, nav_items_width): nav_items.custom_minimum_size.x = nav_items_width
	var nav_pad := shell.find_child("IdentityNavigationPadding", true, false) as MarginContainer
	if is_instance_valid(nav_pad):
		var nav_padding := 6 if compact_nav else 10
		for edge in ["left", "right", "top", "bottom"]:
			if nav_pad.get_theme_constant("margin_" + edge) != nav_padding: nav_pad.add_theme_constant_override("margin_" + edge, nav_padding)
	var nav_toggle := shell.find_child("IdentityNavigationToggle", true, false) as Button
	if is_instance_valid(nav_toggle):
		if nav_toggle.visible != narrow_nav: nav_toggle.visible = narrow_nav
		var toggle_text := "›" if compact_nav else "‹"
		if nav_toggle.text != toggle_text: nav_toggle.text = toggle_text
	var nav_fill := shell.find_child("IdentityNavigationFill", true, false) as Control
	if is_instance_valid(nav_fill) and nav_fill.visible == compact_nav: nav_fill.visible = not compact_nav
	var nav_version := shell.find_child("IdentityNavigationVersion", true, false) as Control
	if is_instance_valid(nav_version) and nav_version.visible == compact_nav: nav_version.visible = not compact_nav
	var content_margin := shell.find_child("IdentityContentMargin", true, false) as MarginContainer
	if is_instance_valid(content_margin):
		var content_padding := 12 if compact_nav else 28
		for edge in ["left", "right", "top", "bottom"]:
			if content_margin.get_theme_constant("margin_" + edge) != content_padding: content_margin.add_theme_constant_override("margin_" + edge, content_padding)
	var form := shell.find_child("IdentityPasswordForm", true, false) as Control
	var form_width := clampf(width - 270.0, 240.0, 600.0)
	if is_instance_valid(form) and not is_equal_approx(form.custom_minimum_size.x, form_width): form.custom_minimum_size.x = form_width
	var inline_fields := width / scale >= 550.0
	_reflow_password_row(shell, "IdentityNewPasswordRow", "IdentityNewPasswordLabel", "IdentityPassword", inline_fields, scale)
	_reflow_password_row(shell, "IdentityConfirmPasswordRow", "IdentityConfirmPasswordLabel", "IdentityPasswordConfirmation", inline_fields, scale)

static func _run(d, command: String) -> void:
	var s := _st(d)
	var raw := str(d._identity_command("identity "+command)) if d.has_method("_identity_command") else ""
	var parsed = JSON.parse_string(raw)
	s["output"] = parsed if parsed != null else {"ok": false, "error": raw}
	d.get_node("/root/Soundscape").play_ui("work_success" if parsed is Dictionary and bool(parsed.get("ok",false)) else "work_failure")
	if parsed is Dictionary:
		s["last_action"] = command.get_slice(" ", 0)
		s["last_target"] = command.get_slice(" ", 1) if str(s.last_action) in ["enable", "access", "logout", "logout-all"] else ""
		if command.begins_with("enable ") and bool(parsed.get("ok", false)):
			var drafts: Dictionary = s.get("account_drafts", {})
			drafts.erase(command.get_slice(" ", 1)); s["account_drafts"] = drafts
		if command.begins_with("access "):
			var observations: Dictionary = s.get("session_observations", {})
			observations[command.get_slice(" ", 1)] = {"response":parsed.duplicate(true), "state":_access_state(d)}
			s["session_observations"] = observations
		if command.begins_with("login "):
			s.erase("challenge"); s.erase("enrollment"); s.erase("required_action")
		if parsed.has("required_action"):
			s["required_action"] = str(parsed.get("required_action", ""))
		if parsed.has("challenge"):
			s["challenge"] = parsed.challenge; s["enrollment"] = bool(parsed.get("enrollment",false))
		if parsed.has("token"):
			s["token"] = parsed.token
			s.erase("challenge"); s.erase("enrollment"); s.erase("required_action")
		if command.begins_with("password-set ") and bool(parsed.get("ok", false)):
			s.erase("credential_form")
		if command.begins_with("password-update ") and bool(parsed.get("ok", false)):
			s.erase("required_action")
	s.erase("_parent")
	d.identity_ui = s
	d._save_session(false)
	if d.has_method("_render_identity"):
		d._render_identity()
	else:
		_rerender(d)

static func _access_state(d) -> String:
	var snapshot: Dictionary = d.game._vm().identity_snapshot()
	return JSON.stringify({"users":snapshot.get("users", []), "sessions":snapshot.get("sessions", []), "policy":snapshot.get("policy", {}), "active":d.game._vm().state.get("active", false)}, "", true)

static func _label(d, parent: Node, text: String, size := 14, color := INK) -> Label:
	var l: Label = d._label(text, size, color)
	l.add_theme_font_override("font", COPY.font(600 if size >= 18 else 400))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

static func _surface(parent: Node, color: Color = PAPER) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", COPY.style(color, BORDER, 16, 18, 2))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	return box

static func _button(d, parent: Node, text: String, callback: Callable, selected := false) -> Button:
	var b: Button = d._button(text, callback)
	b.add_theme_font_size_override("font_size", int(round(13.0 * float(d.game.settings.get("text_scale", 1.0)))))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if selected:
		b.add_theme_color_override("font_color", Color.WHITE)
		var box := StyleBoxFlat.new()
		box.bg_color = NAV_ACTIVE
		box.corner_radius_top_left = 4; box.corner_radius_top_right = 4
		box.corner_radius_bottom_left = 4; box.corner_radius_bottom_right = 4
		b.add_theme_stylebox_override("normal", box)
	parent.add_child(b)
	return b

static func _masthead_button(d, parent: Node, text: String, callback: Callable) -> Button:
	var b: Button = d._button(text, callback)
	b.flat = true
	b.add_theme_color_override("font_color", Color("e8eaeb"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", COPY.style(Color.TRANSPARENT, Color.TRANSPARENT, 9, 5, 3))
	b.add_theme_stylebox_override("hover", COPY.style(Color("2b2f31"), Color.TRANSPARENT, 9, 5, 3))
	parent.add_child(b)
	return b

static func _nav_button(d, parent: Node, text: String, name: String, callback: Callable, selected := false) -> Button:
	var b := _button(d, parent, text, callback, selected)
	b.name = name
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", Color("eef0f1"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := COPY.style(NAV_ACTIVE if selected else NAV, Color.TRANSPARENT, 12, 7, 2)
	normal.content_margin_left = 14; normal.content_margin_right = 10
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", COPY.style(Color("34383a"), Color.TRANSPARENT, 12, 7, 2))
	return b

static func _section(d, parent: Node, text: String) -> void:
	var l := _label(d, parent, text.to_upper(), 11, Color("aeb4b7"))
	l.add_theme_constant_override("outline_size", 0)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


static func _run_user(d, command: String) -> void:
	_run(d, command)

static func render(d, parent: VBoxContainer) -> void:
	var s := _st(d)
	var text_scale := maxf(1.0, float(d.game.settings.get("text_scale", 1.0)))
	var narrow_nav := float(d.windows.browser.size.x) / text_scale < 1100.0
	var compact_nav := narrow_nav and not bool(s.get("nav_expanded", false))
	var snapshot: Dictionary = {}
	if is_instance_valid(d.game) and d.game.has_method("_vm") and d.game._vm() != null:
		snapshot = d.game._vm().identity_snapshot()
	var shell := VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 0)
	shell.custom_minimum_size.y = maxf(360,float(d.windows.browser.size.y)-86)
	parent.add_child(shell)
	var masthead := PanelContainer.new()
	masthead.custom_minimum_size.y = 58
	masthead.add_theme_stylebox_override("panel", COPY.style(MASTHEAD, Color.TRANSPARENT, 14, 8, 0))
	shell.add_child(masthead)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); masthead.add_child(top)
	var mark := _label(d, top, "KEYCLOAK", 20, Color("e7eaeb")); mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; mark.autowrap_mode = TextServer.AUTOWRAP_OFF
	var realm_label := _label(d, top, _copy("identity_realm", "Realm"), 13, Color("c4c9cb")); realm_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; realm_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var realm := _label(d, top, "client", 14, Color("e8eaeb")); realm.name = "IdentityRealm"; realm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; realm.autowrap_mode = TextServer.AUTOWRAP_OFF; realm.custom_minimum_size.x = 112
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(spacer)
	# Keycloak's admin shell keeps the realm context in the masthead and leaves
	# page actions in the content area; avoid adding actions that have no VM API.
	var context := _label(d, top, _copy("identity_admin", "Admin Console"), 12, Color("aeb4b7")); context.size_flags_horizontal = Control.SIZE_SHRINK_END; context.autowrap_mode = TextServer.AUTOWRAP_OFF

	var work := HBoxContainer.new(); work.size_flags_vertical = Control.SIZE_EXPAND_FILL; work.add_theme_constant_override("separation", 0); shell.add_child(work)
	var nav_panel := PanelContainer.new(); nav_panel.name = "IdentityNavigationPanel"; nav_panel.custom_minimum_size.x = 156 if compact_nav else 205; nav_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL; nav_panel.add_theme_stylebox_override("panel", COPY.style(NAV, Color.TRANSPARENT, 0, 0, 0)); work.add_child(nav_panel)
	var nav := VBoxContainer.new(); nav.add_theme_constant_override("separation", 3); nav_panel.add_child(nav)
	var nav_scroll := ScrollContainer.new(); nav_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; nav.add_child(nav_scroll)
	var nav_items := VBoxContainer.new(); nav_items.name = "IdentityNavigationItems"; nav_items.add_theme_constant_override("separation", 3); nav_items.custom_minimum_size.x = 136 if compact_nav else 185; nav_scroll.add_child(nav_items)
	var nav_pad := MarginContainer.new(); nav_pad.name = "IdentityNavigationPadding"
	for edge in ["left","right","top","bottom"]: nav_pad.add_theme_constant_override("margin_"+edge, 6 if compact_nav else 10)
	nav_items.add_child(nav_pad)
	var nav_content := VBoxContainer.new(); nav_content.add_theme_constant_override("separation", 3); nav_pad.add_child(nav_content)
	var nav_toggle := _nav_button(d, nav_content, "›" if compact_nav else "‹", "IdentityNavigationToggle", func():s["nav_expanded"] = not bool(s.get("nav_expanded", false)); d.identity_ui = s; _rerender(d))
	nav_toggle.tooltip_text = "Keycloak navigation"
	nav_toggle.visible = narrow_nav
	_label(d, nav_content, "client", 12, Color("b1b7ba"))
	var view := str(s.get("view", "users"))
	for item in [["users", "identity_users", "Users"], ["authentication", "identity_authentication", "Authentication"], ["events", "identity_events", "Events"]]:
		var nav_label := _copy(item[1], item[2])
		var nav_button := _nav_button(d, nav_content, nav_label, "IdentityView_"+str(item[0]), func(): s["view"] = item[0]; s.erase("user"); s.erase("output"); d.identity_ui = s; _rerender(d), view == item[0])
	var login_label := _copy("identity_test_login", "Test login")
	var login_nav := _nav_button(d, nav_content, login_label, "IdentityView_login", func(): s["view"] = "login"; s.erase("output"); s.erase("challenge"); s.erase("enrollment"); s.erase("required_action"); d.identity_ui = s; _rerender(d), view == "login")
	var nav_fill := Control.new(); nav_fill.name = "IdentityNavigationFill"; nav_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL; nav_content.add_child(nav_fill)
	var version := _label(d, nav_content, "Keycloak Admin Console", 11, Color("9aa3a7")); version.name = "IdentityNavigationVersion"; version.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var paper := PanelContainer.new(); paper.size_flags_horizontal=Control.SIZE_EXPAND_FILL; paper.size_flags_vertical=Control.SIZE_EXPAND_FILL; paper.add_theme_stylebox_override("panel",COPY.style(Color.WHITE,Color.TRANSPARENT,0,0,0)); work.add_child(paper)
	var main := VBoxContainer.new(); main.size_flags_horizontal = Control.SIZE_EXPAND_FILL; main.size_flags_vertical = Control.SIZE_EXPAND_FILL; main.add_theme_constant_override("separation", 0); paper.add_child(main)
	var main_scroll := ScrollContainer.new(); main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; main.add_child(main_scroll)
	var margin := MarginContainer.new(); margin.name = "IdentityContentMargin"; margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content_padding := 12 if compact_nav else 28
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge, content_padding)
	main_scroll.add_child(margin)
	var body := VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 8); margin.add_child(body)
	var page_title := _copy("identity_users", "Users") if view == "users" else (_copy("identity_authentication", "Authentication") if view == "authentication" else (_copy("identity_events", "Events") if view == "events" else _copy("identity_test_login", "Test login")))
	if view == "login" and str(s.get("required_action", "")) == "UPDATE_PASSWORD": page_title = _copy("identity_admin_update_password", "Update password")
	if view != "users" or str(s.get("user", "")).is_empty():
		_label(d, body, page_title, 26, INK)
	if view != "login" and not _response(d).is_empty(): _result(d, body, false)
	if view == "authentication": _auth(d, body, snapshot)
	elif view == "events": _events(d, body, snapshot)
	elif view == "login": _login(d, body)
	else: _users(d, body, s, snapshot)
	if view != "login" and not _response(d).is_empty():
		var detail: VBoxContainer = d._disclosure(body, _copy("identity_response", "Response"))
		_label(d, detail, JSON.stringify(_response(d), "  "), 12, MUTED)
	shell.resized.connect(func():
		if is_instance_valid(shell): _reflow(d, shell)
	)
	_reflow(d, shell)

static func _response(d) -> Dictionary:
	var output = _st(d).get("output", {})
	return output if output is Dictionary else {}

static func _users(d, body: VBoxContainer, s: Dictionary, data: Dictionary) -> void:
	var selected := str(s.get("user", ""))
	if selected.is_empty():
		var search_row := HBoxContainer.new(); search_row.add_theme_constant_override("separation", 6); body.add_child(search_row)
		var search := LineEdit.new(); search.name = "IdentitySearch"; search.placeholder_text = _copy("experience_search_users", _copy("identity_search", "Search users")); search.text = str(s.get("search", "")); search.size_flags_horizontal = Control.SIZE_EXPAND_FILL; search_row.add_child(search)
		var search_button: Button = d._button(_copy("experience_search_users"), func(): s["search"] = search.text; d.identity_ui = s; _rerender(d)); search_button.name = "IdentitySearchButton"; search_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; search_row.add_child(search_button)
		var query := str(s.get("search", "")).strip_edges().to_lower()
		var users = data.get("users", [])
		var table := _surface(body, PAPER)
		var header := HBoxContainer.new(); header.add_theme_constant_override("separation", 10); table.add_child(header)
		_label(d, header, _copy("identity_user", "User"), 12, MUTED)
		var header_status := _label(d, header, _copy("identity_status", "Status"), 12, MUTED); header_status.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; header_status.custom_minimum_size.x = 92
		var header_action := _label(d, header, "", 12, MUTED); header_action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; header_action.custom_minimum_size.x = 92
		table.add_child(HSeparator.new())
		for u in users:
			if not u is Dictionary: continue
			if not query.is_empty() and not str(u.get("user", "")).to_lower().contains(query): continue
			var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); row.custom_minimum_size.y = 42; table.add_child(row)
			var name := _button(d, row, str(u.get("user", "")), func(): s["user"] = str(u.get("user", "")); s["user_tab"] = "details"; s.erase("confirm_otp_delete"); s.erase("confirm_otp_delete_user"); d.identity_ui = s; _rerender(d)); name.name = "IdentityUser_"+str(u.get("user", "")); name.size_flags_horizontal = Control.SIZE_EXPAND_FILL; name.alignment = HORIZONTAL_ALIGNMENT_LEFT; name.flat = true; name.add_theme_color_override("font_color", BLUE); name.add_theme_color_override("font_hover_color", INK)
			var status := _label(d, row, _copy("identity_enabled", "Enabled") if bool(u.get("enabled", false)) else _copy("identity_disabled", "Disabled"), 13, MUTED); status.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; status.custom_minimum_size.x = 92
			var open := _button(d, row, "⋯", func(): s["user"] = str(u.get("user", "")); s["user_tab"] = "details"; s.erase("confirm_otp_delete"); s.erase("confirm_otp_delete_user"); d.identity_ui = s; _rerender(d)); open.name = "IdentityDetails_"+str(u.get("user", "")); open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; open.custom_minimum_size.x = 48; open.tooltip_text = _copy("identity_details", "Details")
			table.add_child(HSeparator.new())
		return
	var user: Dictionary = {}
	for u in data.get("users", []):
		if u is Dictionary and str(u.get("user", "")) == selected: user = u; break
	var crumbs := HBoxContainer.new(); crumbs.add_theme_constant_override("separation", 8); body.add_child(crumbs)
	var users_link := _button(d, crumbs, _copy("identity_users", "Users"), func(): s.erase("user"); d.identity_ui = s; _rerender(d)); users_link.name = "IdentityUsersBreadcrumb"; users_link.flat = true; users_link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; users_link.add_theme_color_override("font_color", BLUE)
	var chevron := _label(d, crumbs, "›", 13, MUTED); chevron.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; chevron.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label(d, crumbs, selected, 18, INK)
	if str(s.get("user_tab", "")) == "credentials" and str(s.get("credential_form", "")) == "password":
		_password_form(d, body, selected, s)
		return
	var active_sessions: Array = data.get("sessions", []).filter(func(item): return item is Dictionary and str(item.get("user", "")) == selected and not bool(item.get("revoked", false)))
	var lifecycle := HFlowContainer.new(); lifecycle.add_theme_constant_override("h_separation", 10); body.add_child(lifecycle)
	lifecycle.name = "IdentityAccountLifecycle"
	var lifecycle_status := _label(d, lifecycle, "新規ログイン: " + ("有効" if bool(user.get("enabled", false)) else "停止") + "  ·  既存セッション: %d 件" % active_sessions.size(), 13, INK)
	lifecycle_status.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lifecycle_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	lifecycle_status.tooltip_text = "アカウントの停止と、発行済みセッションの失効は別の操作です。"
	var login := _button(d, lifecycle, "ログインを試す", func(): d._open_identity_login(selected))
	login.name = "IdentityLoginAs_" + selected
	login.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var tabs := HFlowContainer.new(); tabs.add_theme_constant_override("h_separation", 0); tabs.add_theme_constant_override("v_separation",0); body.add_child(tabs)
	for tab in ["details", "credentials", "sessions"]:
		var active: bool = str(s.get("user_tab", "details")) == tab
		var tab_button := _button(d, tabs, _copy("identity_"+tab, tab.capitalize()), func(): s["user_tab"] = tab; d.identity_ui = s; _rerender(d), active); tab_button.name = "IdentityTab_"+tab
		tab_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var tab_style := COPY.style(PAPER if active else SUBTLE, BLUE if active else BORDER, 12, 6, 0)
		tab_style.border_width_left = 0; tab_style.border_width_right = 0
		tab_style.border_width_top = 2 if active else 0
		tab_style.border_width_bottom = 1 if not active else 0
		tab_button.add_theme_stylebox_override("normal", tab_style)
		tab_button.add_theme_stylebox_override("hover", COPY.style(Color("e7f1f8"), BORDER, 12, 7, 0))
		tab_button.add_theme_color_override("font_color", BLUE if active else MUTED)
	match str(s.get("user_tab", "details")):
		"credentials": _credentials(d, body, user, selected, s)
		"sessions": _sessions(d, body, data, selected)
		_: _details(d, body, user, selected)

static func _details(d, body: VBoxContainer, user: Dictionary, id: String) -> void:
	var enabled := bool(user.get("enabled", false))
	var state := _st(d)
	var drafts: Dictionary = state.get("account_drafts", {})
	var heading := HBoxContainer.new(); heading.custom_minimum_size.y = 42; body.add_child(heading)
	_label(d, heading, _copy("identity_admin_user_details", "User details"), 18, INK)
	var check := CheckBox.new(); check.name = "IdentityEnable"; check.text = _copy("identity_enabled", "Enabled"); check.button_pressed = bool(drafts.get(id, enabled)); check.size_flags_horizontal = Control.SIZE_SHRINK_END; heading.add_child(check)
	var draft_note := _label(d, body, "未保存の変更" if drafts.has(id) else "現在のアカウント状態", 12, MUTED)
	draft_note.name = "IdentityAccountDraft"
	check.toggled.connect(func(value): drafts[id] = value; state["account_drafts"] = drafts; d.identity_ui = state; draft_note.text = "未保存の変更"; d._save_session(false))
	var save: Button = d._button(_copy("identity_save", "Save"), func(): _run_user(d, "enable "+id+" "+("on" if check.button_pressed else "off"))); save.name = "IdentitySave"; save.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; heading.add_child(save)
	var table := VBoxContainer.new(); table.name = "IdentityUserDetails"; table.add_theme_constant_override("separation", 0); body.add_child(table)
	for pair in [[_copy("identity_username", "Username"), id], [_copy("identity_status", "Status"), _copy("identity_enabled", "Enabled") if enabled else _copy("identity_disabled", "Disabled")], [_copy("identity_mfa_required", "MFA"), _copy("identity_mfa_required", "Required") if bool(user.get("mfa_required", false)) else _copy("identity_mfa_off", "Optional")]]:
		var row := HBoxContainer.new(); row.custom_minimum_size.y = 42; table.add_child(row); _label(d, row, str(pair[0]), 13, MUTED); _label(d, row, str(pair[1]), 13, INK)

static func _credentials(d, body: VBoxContainer, user: Dictionary, id: String, state: Dictionary) -> void:
	if str(state.get("credential_form", "")) == "password":
		_password_form(d, body, id, state)
		return
	var table := GridContainer.new(); table.columns = 4
	table.name = "IdentityCredentialsTable"
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 18); table.add_theme_constant_override("v_separation", 16)
	body.add_child(table)
	for key in ["credential_type", "label", "data", "actions"]:
		_label(d, table, _copy("identity_admin_" + key), 12, MUTED).custom_minimum_size.y = 40
	for column in 4: table.add_child(HSeparator.new())
	_label(d, table, _copy("identity_admin_credential_password", "Password"), 13, INK)
	_label(d, table, "—", 13, MUTED)
	var password_status := _copy("identity_admin_temporary_on", "Temporary") if bool(user.get("password_temporary", false)) else _copy("identity_admin_permanent", "Permanent")
	if not bool(user.get("password_set", true)): password_status = _copy("identity_admin_required_actions", "Required actions")
	_label(d, table, password_status, 13, MUTED)
	var change := _button(d, table, _copy("identity_admin_reset_password", "Reset password"), func(): state["credential_form"] = "password"; state.erase("output"); d.identity_ui = state; _rerender(d)); change.name = "IdentityPasswordChange"; change.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if bool(user.get("otp_registered", false)):
		for column in 4: table.add_child(HSeparator.new())
		_label(d, table, _copy("identity_admin_credential_otp", "OTP"), 13, INK)
		_label(d, table, "—", 13, MUTED)
		_label(d, table, _copy("identity_otp_registered", "Registered"), 13, MUTED)
		var otp_delete := _button(d, table, _copy("identity_admin_delete_otp", "Delete"), func():
			if bool(state.get("confirm_otp_delete", false)) and str(state.get("confirm_otp_delete_user", "")) == id:
				state.erase("confirm_otp_delete")
				state.erase("confirm_otp_delete_user")
				d.identity_ui = state
				_run_user(d, "otp-delete " + id)
			else:
				state["confirm_otp_delete"] = true
				state["confirm_otp_delete_user"] = id
				d.identity_ui = state
				_rerender(d)
		)
		otp_delete.name = "IdentityOtpDelete"; otp_delete.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if bool(state.get("confirm_otp_delete", false)) and str(state.get("confirm_otp_delete_user", "")) == id:
		_label(d, body, _copy("identity_admin_delete_otp_confirm", "Delete this OTP credential?"), 13, COPY.RED)
		var actions := HBoxContainer.new(); body.add_child(actions)
		var confirm := _button(d, actions, _copy("identity_admin_delete_otp", "Confirm"), func(): state.erase("confirm_otp_delete"); state.erase("confirm_otp_delete_user"); d.identity_ui = state; _run_user(d, "otp-delete " + id)); confirm.name = "IdentityOtpDeleteConfirm"; confirm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var cancel := _button(d, actions, _copy("identity_admin_cancel", "Cancel"), func(): state.erase("confirm_otp_delete"); state.erase("confirm_otp_delete_user"); d.identity_ui = state; _rerender(d)); cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

static func _password_form(d, body: VBoxContainer, id: String, state: Dictionary) -> void:
	var form := VBoxContainer.new(); form.name = "IdentityPasswordForm"; form.add_theme_constant_override("separation", 8); body.add_child(form)
	form.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; form.custom_minimum_size.x = minf(600, float(d.windows.browser.size.x) - 270)
	_label(d, form, _copy("identity_admin_reset_password", "Change password"), 18, INK)
	var text_scale := maxf(1.0, float(d.game.settings.get("text_scale", 1.0)))
	var inline_fields := float(d.windows.browser.size.x) / text_scale >= 550.0
	var new_password_row := BoxContainer.new(); new_password_row.name = "IdentityNewPasswordRow"; new_password_row.vertical = not inline_fields
	new_password_row.add_theme_constant_override("separation", 12 if inline_fields else 2)
	form.add_child(new_password_row)
	var new_password_label := _label(d, new_password_row, _copy("identity_admin_new_password", "New password"), 12, MUTED); new_password_label.name = "IdentityNewPasswordLabel"
	var password := LineEdit.new(); password.name = "IdentityPassword"; password.placeholder_text = _copy("identity_admin_new_password", "New password"); password.secret = true; password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if inline_fields:
		new_password_label.custom_minimum_size.x = 160.0 * text_scale
		new_password_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		new_password_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	new_password_row.add_child(password)
	var confirmation_row := BoxContainer.new(); confirmation_row.name = "IdentityConfirmPasswordRow"; confirmation_row.vertical = not inline_fields
	confirmation_row.add_theme_constant_override("separation", 12 if inline_fields else 2)
	form.add_child(confirmation_row)
	var confirmation_label := _label(d, confirmation_row, _copy("identity_admin_confirm_password", "Confirm password"), 12, MUTED); confirmation_label.name = "IdentityConfirmPasswordLabel"
	var confirmation := LineEdit.new(); confirmation.name = "IdentityPasswordConfirmation"; confirmation.placeholder_text = _copy("identity_admin_confirm_password", "Confirm password"); confirmation.secret = true; confirmation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if inline_fields:
		confirmation_label.custom_minimum_size.x = 160.0 * text_scale
		confirmation_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		confirmation_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	confirmation_row.add_child(confirmation)
	var temporary := CheckBox.new(); temporary.name = "IdentityPasswordTemporary"; temporary.text = _copy("identity_admin_temporary", "Temporary"); temporary.button_pressed = true; form.add_child(temporary)
	var actions := HBoxContainer.new(); actions.add_theme_constant_override("separation", 8); form.add_child(actions)
	var save := _button(d, actions, _copy("identity_admin_set_password", "Save"), func():
		var first := _secret_arg(password.text); var second := _secret_arg(confirmation.text)
		if first.is_empty() or second.is_empty() or password.text != confirmation.text:
			state["output"] = {"ok":false,"error":"invalid_password" if first.is_empty() or second.is_empty() else "password_mismatch"}; d.identity_ui = state; _rerender(d); return
		_run_user(d, "password-set " + id + " " + first + " " + ("temporary" if temporary.button_pressed else "permanent"))
	); save.name = "IdentityPasswordSave"; save.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var cancel := _button(d, actions, _copy("identity_admin_cancel", "Cancel"), func(): state.erase("credential_form"); d.identity_ui = state; _rerender(d)); cancel.name = "IdentityPasswordCancel"; cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

static func _sessions(d, body: VBoxContainer, data: Dictionary, id: String) -> void:
	var sessions: Array = data.get("sessions",[]).filter(func(session):return session is Dictionary and str(session.get("user",""))==id)
	sessions.reverse()
	var active: Array = sessions.filter(func(session): return not bool(session.get("revoked",false)))
	if sessions.is_empty():
		_label(d,body,_copy("identity_no_sessions","No active sessions"),14,MUTED)
		return
	var table := VBoxContainer.new(); table.name = "IdentitySessionsTable"; table.add_theme_constant_override("separation", 12); body.add_child(table)
	var observations: Dictionary = _st(d).get("session_observations", {})
	for session in sessions:
		var row := _surface(table, SUBTLE)
		var session_id := str(session.get("id", ""))
		var revoked := bool(session.get("revoked", false))
		_label(d,row,session_id + "  ·  " + ("失効済み" if revoked else "発行済み"),14,INK)
		_label(d,row,str(session.get("client","")) + "  ·  " + str(session.get("ip","")) + "  ·  発行 " + str(session.get("issued", "")),12,MUTED)
		var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 8); row.add_child(actions)
		var access := _button(d,actions,"このセッションでアクセスを確認",func(): _run_user(d,"access "+session_id)); access.name="IdentitySessionAccess_"+session_id
		var logout := _button(d,actions,_copy("identity_logout","Logout"),func(): _run_user(d,"logout "+session_id)); logout.name="IdentityLogout_"+session_id; logout.disabled = revoked
		access.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; logout.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var observation: Dictionary = observations.get(session_id, {})
		if not observation.is_empty():
			var response: Dictionary = observation.get("response", {})
			var fresh := str(observation.get("state", "")) == _access_state(d)
			var result := _label(d,row,("今回の状態で確認: " if fresh else "変更前の確認: ") + ("アクセス成功" if bool(response.get("ok", false)) else "アクセス拒否 · " + str(response.get("error", ""))),13,INK if fresh else MUTED)
			result.name = "IdentitySessionResult_" + session_id
	var all: Button = d._button(_copy("identity_logout_all", "Logout all"), func(): _run_user(d, "logout-all "+id)); all.name = "IdentityLogoutAll_"+id; all.disabled=active.is_empty(); all.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; body.add_child(all)

static func _auth(d, body: VBoxContainer, snapshot: Dictionary) -> void:
	var crumbs := HBoxContainer.new(); crumbs.add_theme_constant_override("separation", 8); body.add_child(crumbs)
	var auth_crumb := _label(d, crumbs, _copy("identity_authentication", "Authentication"), 13, BLUE); auth_crumb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; auth_crumb.autowrap_mode = TextServer.AUTOWRAP_OFF
	var chevron := _label(d, crumbs, "›", 13, MUTED); chevron.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; chevron.autowrap_mode = TextServer.AUTOWRAP_OFF
	var flow_crumb := _label(d, crumbs, _copy("identity_flow_details", "Flow details"), 13, MUTED); flow_crumb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; flow_crumb.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label(d,body,"browser",20,INK)
	var policy: Dictionary=snapshot.get("policy",{});var enabled:=bool(policy.get("mfa_required",false))
	var table:=VBoxContainer.new();table.name="IdentityAuthFlow";table.add_theme_constant_override("separation",0);body.add_child(table)
	var header:=HBoxContainer.new();header.custom_minimum_size.y=46;table.add_child(header)
	var step_header:=_label(d,header,_copy("identity_flow_step"),13,MUTED);step_header.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var requirement:=_label(d,header,_copy("identity_flow_requirement"),13,MUTED);requirement.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;requirement.custom_minimum_size.x=180;requirement.autowrap_mode=TextServer.AUTOWRAP_OFF
	table.add_child(HSeparator.new())
	var toggle: OptionButton
	var rows := [["execution", "IdentityFlowPassword", "Username Password Form", true], ["flow", "IdentityFlowConditional", "Browser - Conditional 2FA", enabled], ["step", "IdentityFlowOtp", "OTP Form", enabled]]
	for entry in rows:
		var row:=HBoxContainer.new();row.custom_minimum_size.y=54;row.add_theme_constant_override("separation",12);table.add_child(row)
		var kind:=_label(d,row,str(entry[0]),11,BLUE);kind.custom_minimum_size.x=92;kind.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;kind.autowrap_mode=TextServer.AUTOWRAP_OFF
		var name:=_label(d,row,str(entry[2]),14,INK);name.name=str(entry[1]);name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if str(entry[1])=="IdentityFlowPassword":
			var required:=_label(d,row,_copy("experience_required"),13,MUTED);required.custom_minimum_size.x=180;required.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;required.autowrap_mode=TextServer.AUTOWRAP_OFF
		elif str(entry[1])=="IdentityFlowOtp":
			toggle=OptionButton.new();toggle.name="IdentityMfa";toggle.add_item(_copy("identity_disabled", "Disabled"));toggle.add_item(_copy("experience_required"));toggle.select(1 if enabled else 0);toggle.custom_minimum_size.x=180;toggle.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(toggle)
			toggle.add_theme_stylebox_override("normal",COPY.style(Color.WHITE,Color("d2d2d2"),4,6,0))
		else:
			var conditional:=_label(d,row,_copy("experience_required") if enabled else _copy("identity_disabled", "Disabled"),13,MUTED);conditional.custom_minimum_size.x=180;conditional.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;conditional.autowrap_mode=TextServer.AUTOWRAP_OFF
		table.add_child(HSeparator.new())
	var apply:=_button(d,body,_copy("identity_apply"),func():_run(d,"mfa "+("on" if toggle.selected==1 else "off")));apply.name="IdentityApply";apply.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;apply.add_theme_color_override("font_color",Color.WHITE);apply.add_theme_stylebox_override("normal",COPY.style(BLUE,Color.TRANSPARENT,16,8,3))

static func _event_type_label(item: Dictionary) -> String:
	var event_type := str(item.get("type", ""))
	var outcome := str(item.get("outcome", ""))
	match event_type:
		"account_enable": return _copy("identity_admin_event_enable" if outcome == "on" else "identity_admin_event_disable", event_type)
		"mfa_policy": return _copy("identity_admin_event_mfa", event_type)
		"password_set": return _copy("identity_admin_event_reset_password", event_type)
		"password_update": return _copy("identity_admin_event_update_password", event_type)
		"otp_delete": return _copy("identity_admin_event_remove_otp", event_type)
		"otp_verify": return _copy("identity_verify_otp", event_type)
		"session_revoke", "session_revoke_all": return _copy("identity_admin_event_logout", event_type)
		"session_issued": return _copy("identity_authenticated", event_type)
		"login": return _copy("identity_admin_event_login", event_type)
		"access": return _copy("identity_admin_event_access", event_type)
		_: return event_type

static func _event_outcome_label(outcome: String) -> String:
	return _copy("identity_admin_event_" + _event_outcome_group(outcome), outcome)

static func _event_outcome_group(outcome: String) -> String:
	if outcome in ["ok", "allowed", "enabled", "disabled", "on", "off", "permanent", "temporary"]:
		return "success"
	if outcome in ["password_update_required", "mfa_required"]:
		return "pending"
	return "failure"

static func _events(d, body: VBoxContainer, snapshot: Dictionary) -> void:
	var state := _st(d)
	var scope := str(state.get("event_scope", "user"))
	var scope_tabs := HBoxContainer.new(); scope_tabs.add_theme_constant_override("separation", 4); body.add_child(scope_tabs)
	var user_tab := _button(d, scope_tabs, _copy("identity_admin_user_events", "User events"), func(): state["event_scope"] = "user"; state.erase("event_selected"); d.identity_ui = state; _rerender(d), scope == "user"); user_tab.name = "IdentityEventsUserTab"
	var admin_tab := _button(d, scope_tabs, _copy("identity_admin_admin_events", "Admin events"), func(): state["event_scope"] = "admin"; state.erase("event_selected"); d.identity_ui = state; _rerender(d), scope == "admin"); admin_tab.name = "IdentityEventsAdminTab"
	var filters := HBoxContainer.new(); filters.add_theme_constant_override("separation", 8); body.add_child(filters)
	var user_filter := OptionButton.new(); user_filter.name = "IdentityEventUser"; user_filter.add_item(_copy("identity_admin_event_all", "All users"), 0); user_filter.set_item_metadata(0, "")
	var seen_users: Dictionary = {}
	for item in snapshot.get("audit_events", []):
		if item is Dictionary:
			var event_user := str(item.get("user", ""))
			if not event_user.is_empty() and not seen_users.has(event_user): seen_users[event_user] = true; user_filter.add_item(event_user); user_filter.set_item_metadata(user_filter.item_count - 1, event_user)
	user_filter.select(0); filters.add_child(user_filter)
	var outcome_filter := OptionButton.new(); outcome_filter.name = "IdentityEventOutcome"; outcome_filter.add_item(_copy("identity_admin_event_all", "All results"), 0); outcome_filter.set_item_metadata(0, "")
	for group in ["success", "pending", "failure"]:
		outcome_filter.add_item(_copy("identity_admin_event_" + group)); outcome_filter.set_item_metadata(outcome_filter.item_count - 1, group)
	outcome_filter.select(0); filters.add_child(outcome_filter)
	var wanted_user := str(state.get("event_user", "")); var wanted_outcome := str(state.get("event_outcome", ""))
	for index in range(user_filter.item_count):
		if str(user_filter.get_item_metadata(index)) == wanted_user:
			user_filter.select(index); break
	for index in range(outcome_filter.item_count):
		if str(outcome_filter.get_item_metadata(index)) == wanted_outcome:
			outcome_filter.select(index); break
	user_filter.item_selected.connect(func(index): state["event_user"] = str(user_filter.get_item_metadata(index)); state.erase("event_selected"); d.identity_ui = state; _rerender(d))
	outcome_filter.item_selected.connect(func(index): state["event_outcome"] = str(outcome_filter.get_item_metadata(index)); state.erase("event_selected"); d.identity_ui = state; _rerender(d))
	var rows: Array = []
	for item in snapshot.get("audit_events", []):
		if not item is Dictionary: continue
		if str(item.get("category", "user")) != scope: continue
		if not wanted_user.is_empty() and str(item.get("user", "")) != wanted_user: continue
		if not wanted_outcome.is_empty() and _event_outcome_group(str(item.get("outcome", ""))) != wanted_outcome: continue
		rows.append(item)
	rows.sort_custom(func(a, b): return int(a.get("sequence", 0)) > int(b.get("sequence", 0)))
	if rows.is_empty():
		_label(d, body, _copy("identity_empty_events", "No events"), 14, MUTED)
		var legacy: VBoxContainer = d._disclosure(body, _copy("identity_admin_legacy_events", "Legacy event log")); legacy.name = "IdentityLegacyEvents"
		for event in snapshot.get("events", []): _label(d, legacy, str(event), 12, MUTED)
		return
	var table := VBoxContainer.new(); table.name = "IdentityEventsTable"; table.add_theme_constant_override("separation", 0); body.add_child(table)
	var header := HBoxContainer.new(); header.custom_minimum_size.y = 40; table.add_child(header)
	var id_header := _label(d, header, _copy("identity_admin_event_id", "ID"), 12, MUTED); id_header.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; id_header.custom_minimum_size.x = 80
	header.add_theme_constant_override("separation", 8)
	_label(d, header, _copy("identity_admin_event_type", "Event"), 12, MUTED)
	_label(d, header, _copy("identity_admin_event_user", "User"), 12, MUTED)
	_label(d, header, _copy("identity_admin_event_result", "Result"), 12, MUTED)
	table.add_child(HSeparator.new())
	for item in rows:
		var seq := int(item.get("sequence", 0)); var row := HBoxContainer.new(); row.custom_minimum_size.y = 42; row.add_theme_constant_override("separation", 8); table.add_child(row)
		var open := _button(d, row, str(seq), func(): state["event_selected"] = seq; d.identity_ui = state; _rerender(d)); open.name = "IdentityEvent_" + str(seq); open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		open.custom_minimum_size.x = 80; open.flat = true; open.alignment = HORIZONTAL_ALIGNMENT_LEFT; open.add_theme_color_override("font_color", BLUE)
		_label(d, row, _event_type_label(item), 13, INK)
		_label(d, row, str(item.get("user", "")), 13, MUTED)
		_label(d, row, _event_outcome_label(str(item.get("outcome", ""))), 13, MUTED)
		table.add_child(HSeparator.new())
	var selected_seq := int(state.get("event_selected", -1)); var selected: Dictionary = {}
	for item in rows:
		if int(item.get("sequence", -1)) == selected_seq: selected = item; break
	if not selected.is_empty():
		var details := _surface(body, PAPER); details.name = "IdentityEventDetails"
		body.move_child(details.get_parent(), table.get_index())
		_label(d, details, _copy("identity_admin_event_details", "Event details"), 16, INK)
		_label(d, details, "%s  ·  %s  ·  %s" % [_event_type_label(selected), str(selected.get("user", "")), _event_outcome_label(str(selected.get("outcome", "")))], 13, MUTED)
		var raw: VBoxContainer = d._disclosure(details, _copy("identity_admin_show_data", "Event data")); _label(d, raw, JSON.stringify(selected, "  "), 12, MUTED)

static func _login(d, body: VBoxContainer) -> void:
	var form := VBoxContainer.new(); form.add_theme_constant_override("separation",10); form.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; form.custom_minimum_size.x=clampf(float(d.windows.browser.size.x)-230,240,600); body.add_child(form); body=form
	if str(_st(d).get("challenge", "")).is_empty():
		_login_credentials(d, body)
	else:
		_label(d, body, str(_st(d).get("username", "")), 14, MUTED)
		if str(_st(d).get("required_action", "")) == "UPDATE_PASSWORD" or str(_st(d).get("output", {}).get("error", "")) == "password_update_required":
			_password_update_form(d, body)
		else:
			_label(d,body,_copy("identity_enrollment_required","Enrollment required") if bool(_st(d).get("enrollment",false)) else _copy("identity_challenge_required","OTP required"),14,MUTED)
			var otp := LineEdit.new(); otp.name="IdentityOtp"; otp.placeholder_text=_copy("identity_otp","OTP"); body.add_child(otp)
			var verify: Button=d._button(_copy("identity_verify_otp","Verify OTP"),func(): _run(d,"otp "+str(_st(d).get("challenge",""))+" "+otp.text)); verify.name="IdentityVerifyOtp"; verify.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; body.add_child(verify)
	# Keep the previously issued application's token separate from a new challenge.
	if str(_st(d).get("challenge", "")).is_empty():
		_label(d,body,_copy("identity_token","Token"),13,MUTED)
		var token := LineEdit.new(); token.name = "IdentityToken"; token.text = str(_st(d).get("token", "")); token.placeholder_text = _copy("identity_token", "Token"); body.add_child(token)
		var access: Button = d._button(_copy("identity_access", "Access"), func(): var s := _st(d); s["token"] = token.text; d.identity_ui = s; _run(d, "access "+token.text)); access.name = "IdentityAccess"; access.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; body.add_child(access)
	_result(d,body)

static func _login_credentials(d, body: VBoxContainer) -> void:
	var user := LineEdit.new(); user.name = "IdentityLoginUser"; user.placeholder_text = _copy("identity_username", "Username"); user.text = str(_st(d).get("username", "")); body.add_child(user)
	var password := LineEdit.new(); password.name = "IdentityLoginPassword"; password.placeholder_text = _copy("identity_password", "Password"); password.secret = true; body.add_child(password)
	var sign_in: Button = d._primary(_copy("identity_sign_in", "Sign in"), func():
		var s := _st(d); var user_arg := _shell_arg(user.text); var password_arg := _secret_arg(password.text)
		if user.text.is_empty() or user_arg.is_empty() or password_arg.is_empty():
			s["output"] = {"ok":false,"error":"invalid_password"}; d.identity_ui = s; _rerender(d); return
		s["username"] = user.text; d.identity_ui = s; _run(d, "login "+user_arg+" "+password_arg)
	); sign_in.name = "IdentitySignIn"; sign_in.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; body.add_child(sign_in)

static func _password_update_form(d, body: VBoxContainer) -> void:
	var form := VBoxContainer.new(); form.name = "IdentityPasswordUpdateForm"; form.add_theme_constant_override("separation", 8); body.add_child(form)
	_label(d, form, _copy("identity_admin_new_password", "New password"), 12, MUTED)
	var password := LineEdit.new(); password.name = "IdentityPasswordUpdate"; password.placeholder_text = _copy("identity_admin_new_password", "New password"); password.secret = true; form.add_child(password)
	_label(d, form, _copy("identity_admin_confirm_password", "Confirm password"), 12, MUTED)
	var confirmation := LineEdit.new(); confirmation.name = "IdentityPasswordUpdateConfirmation"; confirmation.placeholder_text = _copy("identity_admin_confirm_password", "Confirm password"); confirmation.secret = true; form.add_child(confirmation)
	var update: Button = d._button(_copy("identity_admin_update_password", "Update password"), func():
		var first := _secret_arg(password.text); var second := _secret_arg(confirmation.text)
		if first.is_empty() or second.is_empty() or password.text != confirmation.text:
			var state := _st(d); state["output"] = {"ok":false,"error":"invalid_password" if first.is_empty() or second.is_empty() else "password_mismatch"}; d.identity_ui = state; _rerender(d); return
		_run(d, "password-update " + str(_st(d).get("challenge", "")) + " " + first)
	); update.name = "IdentityPasswordUpdateSubmit"; update.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; form.add_child(update)


static func _result(d, body: VBoxContainer, show_details := true) -> void:
	var response := _response(d)
	if response.is_empty(): return
	var error := str(response.get("error",""))
	var key := "identity_authenticated" if response.has("token") or response.has("mfa") and response.has("user") else "identity_saved"
	if not bool(response.get("ok",false)):
		key = {"invalid_credentials":"identity_invalid_credentials","invalid_otp":"identity_invalid_otp","save_failed":"identity_save_failed","revoked_session":"identity_revoked","password_update_required":"identity_admin_password_update_required","password_mismatch":"identity_admin_password_mismatch","invalid_password":"identity_admin_password_invalid"}.get(error,"identity_denied")
	elif error == "password_update_required":
		key = "identity_admin_password_update_required"
	elif response.has("challenge"): key="identity_enrollment_required" if bool(response.get("enrollment",false)) else "identity_challenge_required"
	var message := _copy(key, key)
	var action := str(_st(d).get("last_action", ""))
	var target := str(_st(d).get("last_target", ""))
	if action == "access": message = "アクセス成功" if bool(response.get("ok", false)) else message
	elif action == "logout" and bool(response.get("ok", false)): message = "セッションを失効しました"
	elif action == "logout-all" and bool(response.get("ok", false)): message = "全セッションを失効しました"
	if not target.is_empty(): message = target + " · " + message
	var stale := false
	if action == "access":
		var observed: Dictionary = _st(d).get("session_observations", {}).get(target, {})
		stale = not observed.is_empty() and str(observed.get("state", "")) != _access_state(d)
		if stale: message = "変更前の確認 · " + message
	var feedback := _label(d,body,message,14,MUTED if stale else (COPY.GREEN if bool(response.get("ok",false)) else COPY.RED))
	feedback.name = "IdentityActionFeedback"
	if not show_details: return
	var detail: VBoxContainer=d._disclosure(body,_copy("identity_response","Response"))
	_label(d,detail,JSON.stringify(response,"  "),12,MUTED)
