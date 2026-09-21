extends RefCounted
## Browser page renderer for the virtual customer's real curl response.

const UI = preload("res://scripts/ui_theme.gd")
const SHARE_BLUE := Color("4267c9")
const ID_VIOLET := Color("7961b8")
const EDR_GREEN := Color("22745f")

static func _code(result: String) -> int:
	var first := result.get_slice("\n", 0).strip_edges()
	var parts := first.split(" ", false)
	if parts.size() > 1 and str(parts[1]).is_valid_int(): return int(parts[1])
	return 0

static func _host(url: String) -> String:
	var value := url.trim_prefix("https://").trim_prefix("http://")
	return value.get_slice("/", 0)

static func _body(result: String) -> String:
	return result.substr(result.find("\n") + 1).strip_edges() if result.contains("\n") else ""

static func _value_rows(body: String) -> Dictionary:
	var values := {}
	for line in body.split("\n"):
		if "=" in line:
			values[line.get_slice("=", 0).strip_edges()] = line.get_slice("=", 1).strip_edges()
	return values

static func _service_text(line: String) -> String:
	return {"Sales workspace: operational": "営業ワークスペース  ·  稼働中", "Management console": "管理コンソール", "Transport: TLS 1.3": "通信方式  ·  TLS 1.3", "PC-B business session healthy": "PC-B  ·  業務セッション正常"}.get(line, line)

static func _status(d, host: String, code: int) -> Label:
	var text := "応答なし"
	var color := UI.MUTED
	if code == 200:
		text = "接続済み  ·  HTTP 200"
		color = UI.GREEN
	elif code > 0:
		text = "HTTP %d" % code
		color = UI.WARNING if code < 500 else UI.RED
	var label = d._label(text, 12, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

static func _accent(chapter: int) -> Color:
	return SHARE_BLUE if chapter in [0, 2] else ID_VIOLET if chapter in [3, 5] else EDR_GREEN if chapter == 4 else UI.OS_ACCENT

static func _service_nav(d, shell: VBoxContainer, url: String, chapter: int) -> void:
	var host := _host(url)
	var links: Array = []
	match chapter:
		0: links = [["社員", "https://files.client.test/staff/report.txt"], ["ゲスト", "https://files.client.test/guest/report.txt"]]
		1: links = [["社内ポータル", "https://intranet.client.test"]]
		2: links = [["社内ポータル", "https://intranet.client.test"], ["管理", "https://admin.client.test"]]
		3: links = [["在籍", "https://identity.client.test/current/login"], ["退職", "https://identity.client.test/former/login"], ["セッション", "https://identity.client.test/former/session"]]
		4: links = [["PC-A", "https://edr.client.test/pc-a/outbound"], ["PC-B", "https://edr.client.test/pc-b/business"]]
		5: links = [["社員", "https://portal.client.test/staff"], ["取引先", "https://portal.client.test/partner"], ["公開", "https://portal.client.test/public"]]
		_: return
	if chapter==2 and d._firewall_v2():
		links[1][1]="https://admin.client.test:8443"
		links.append([UI.copy("fw_title"),d.FIREWALL_URL])
	var nav: HBoxContainer = d._row(shell, 5)
	var accent := _accent(chapter)
	for link in links:
		var target := str(link[1])
		var button: Button = d._button(str(link[0]), d._browse_url.bind(target, true))
		UI.os_navigation(button, target == url.get_slice("?",0), accent)
		nav.add_child(button)

static func _header(d, shell: VBoxContainer, host: String, code: int, info: Dictionary, accent := UI.OS_ACCENT, customer := "") -> void:
	var location_text := (customer+"  /  "+host) if not customer.is_empty() else "顧客サイト  /  "+host
	var location: Label = d._label(location_text, 12, UI.MUTED)
	location.autowrap_mode = TextServer.AUTOWRAP_OFF
	location.clip_text = true
	shell.add_child(location)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.style(UI.OS_PANEL, accent, 6, 6))
	shell.add_child(bar)
	var row = d._row(bar, 8)
	var lock = d._label("●", 12, UI.GREEN if code == 200 else UI.WARNING)
	row.add_child(lock)
	var title = d._label(host, 14, accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text = true
	row.add_child(title)
	var service := str(info.get("service", ""))
	if not service.is_empty(): row.add_child(d._label(service, 12, UI.MUTED))
	row.add_child(_status(d, host, code))

static func render(d, page: VBoxContainer, url: String, result: String) -> void:
	var shell: VBoxContainer = d._box(page, 6)
	var code := _code(result)
	var host := _host(url)
	var info: Dictionary = d.game.vm_info() if d.game != null else {}
	var chapter: int = d.game._current_chapter() if d.game != null else -1
	var accent := _accent(chapter)
	var mission: Dictionary = d.game.mission() if d.game != null else {}
	_header(d, shell, host, code, info, accent, str(mission.get("client", "顧客")))
	_service_nav(d, shell, url, chapter)
	if code == 200:
		var dark := chapter == 4
		var foreground := Color("e7f4ee") if dark else UI.INK
		var chapter_titles := ["共有ファイル", "社内ポータル", "社内ポータル", "アカウント", "端末の接続状態", "取引先とのファイル共有"]
		var page_title = chapter_titles[clampi(chapter, 0, chapter_titles.size() - 1)]
		var page_head = d._row(shell, 4)
		var heading = d._label(page_title, 18, accent)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page_head.add_child(heading)
		page_head.add_child(d._label(str(mission.get("client", "顧客")), 12, UI.MUTED))
		var document: PanelContainer = PanelContainer.new()
		document.add_theme_stylebox_override("panel", UI.style(UI.OS_SHELL if dark else UI.OS_PANEL, accent, 8, 8))
		shell.add_child(document)
		var doc: VBoxContainer = d._box(document, 6)
		var body := _body(result)
		if chapter == 0:
			var filename := url.get_file()
			doc.add_child(d._label(filename, 15, accent))
			doc.add_child(HSeparator.new())
			var preview = d._label(body, 14, foreground)
			preview.add_theme_font_override("font", d.mono)
			preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			doc.add_child(preview)
		elif chapter == 5:
			var values := _value_rows(body)
			for line in body.split("\n"):
				if line.begins_with("Document: "):
					doc.add_child(d._label(line.trim_prefix("Document: "), 15, accent))
			var table := GridContainer.new()
			table.columns = 2
			table.add_theme_constant_override("h_separation", 24)
			table.add_theme_constant_override("v_separation", 5)
			doc.add_child(table)
			var names: Dictionary = {"role": "利用者", "expires": "有効期限", "MFA": "追加認証", "transport": "通信方式", "audit": "アクセス記録"}
			var labels: Dictionary = {"staff": "社員", "partner": "取引先", "public": "公開リンク", "7d": "7日", "30d": "30日", "unlimited": "期限なし", "on": "有効", "off": "無効"}
			for key in values:
				table.add_child(d._label(names.get(key, key), 12, UI.MUTED))
				table.add_child(d._label(labels.get(values[key], values[key]), 14, foreground))
		elif chapter == 3:
			var user := "退職者アカウント" if "former" in url else "在籍者アカウント"
			doc.add_child(d._label(user, 15, foreground))
			doc.add_child(d._label("追加認証待ち" if "challenge required" in body else "認証済み", 14, UI.GREEN))
		else:
			for line in body.split("\n"):
				if line.strip_edges().is_empty(): continue
				var item = d._row(doc, 5)
				item.add_child(d._label("●", 11, UI.GREEN))
				item.add_child(d._label(_service_text(line), 14, foreground))
		var raw: VBoxContainer = d._disclosure(shell, "HTTP応答の詳細")
		var raw_label: Label = d._label(result, 12, foreground)
		raw_label.add_theme_font_override("font", d.mono)
		raw.add_child(raw_label)
		return

	var heading := "表示不可"
	var raw_result := result.strip_edges()
	var is_http_or_curl := raw_result.begins_with("HTTP/") or raw_result.begins_with("HTTP ") or raw_result.begins_with("curl:")
	if code == 0 and not is_http_or_curl:
		shell.add_child(d._label("顧客サイト接続失敗", 18, UI.INK))
		shell.add_child(d._label(raw_result if not raw_result.is_empty() else "無応答", 14, UI.INK))
		return
	if code == 401:
		heading = "要サインイン"
		if "mfa_required" in result:
			heading = "要追加認証"
	elif code == 403:
		heading = "アクセス拒否"
	elif code == 404:
		heading = "ページ未検出"
	elif code == 410:
		heading = "共有リンク期限切れ"
	elif result.to_lower().contains("tls") or result.to_lower().contains("certificate"):
		heading = "安全な接続確立失敗"
	shell.add_child(d._label(heading, 18, UI.RED))
	shell.add_child(d._label("HTTP %d" % code if code > 0 else "接続エラー", 13, UI.WARNING))
	var raw_error: VBoxContainer = d._disclosure(shell, "エラー応答の詳細")
	var raw_error_label: Label = d._label(result, 12, UI.MUTED)
	raw_error_label.add_theme_font_override("font", d.mono)
	raw_error.add_child(raw_error_label)
