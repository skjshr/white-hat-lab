class_name CaseCatalog
extends RefCounted
const DISPLAY_COPY = preload("res://scripts/ui_theme.gd")
const PROFESSIONAL_CONTRACTS = preload("res://scripts/professional_contracts.gd")
const HOTEL_HANDOFF = preload("res://scripts/hotel_handoff.gd")
## Definitions remain addressable for old saves and linked composite targets, but
## these simple/repetitive cases are no longer generated as fresh market leads.
const RETIRED_NEW_OFFER_IDS := {
	"firm-permission-review": true,
	"firm-remote-hardening": true,
	"firm-continuity": true,
	"firm-recovery-drill": true,
	"firm-account-containment": true,
	"firm-major-containment": true,
	"firm-partner-rollout": true,
	"firm-clean-recovery": true,
	"firm-leak-response": true,
	"service-0-case-3": true,
	"service-2-case-2": true,
	"service-2-case-3": true,
	"service-3-case-2": true,
	"service-3-case-3": true,
	"service-4-case-3": true,
	"service-5-case-2": true,
	"service-5-case-3": true,
	"service-0-case-4": true,
	"service-0-case-5": true,
	"service-1-case-4": true,
	"service-1-case-5": true,
	"service-2-case-4": true,
	"service-2-case-5": true,
	"service-3-case-4": true,
	"service-3-case-5": true,
	"service-4-case-5": true,
	"service-5-case-4": true,
	"service-5-case-5": true,
	"hotel-reservation-recovery": true,
}
## Authored operational contracts. Each profile has a distinct initial state / requirement pair.
static var _catalog: Array = []
const CATEGORIES := ["advisory","operations","advisory","operations","response","advisory"]
const SERVICES := ["Samba / ファイル共有","restic / バックアップ運用","DNS・ファイアウォール・TLS","ID管理 / アカウント・セッション","EDR / 端末隔離・証拠保全","HTTPS / 社外ファイル共有"]
const CLIENTS := ["つばさ文具","青葉デザイン","港町クリニック","北斗物流","白波ホテル","東雲会計事務所"]
const LABELS := {"staff":"社員の権限","guest":"ゲストの権限","schedule":"バックアップ周期","repository":"保存先","dns":"名前解決","business":"業務通信","admin_public":"インターネットからの管理接続","tls":"暗号化通信","former":"旧アカウント","sessions":"既存セッション","current":"在籍者アカウント","mfa":"追加認証","pc_a":"PC-A","pc_b":"PC-B","logs":"原本ログ","reset":"初期化","partner":"取引先の権限","public":"公開権限","expires":"共有期限","audit":"監査ログ"}
const VALUES := {"none":"拒否","read":"読み取り","write":"読み書き","daily":"毎日","off":"無効","on":"有効","local":"同一拠点","offsite":"別拠点","allow":"許可","deny":"拒否","disabled":"無効","active":"有効","valid":"有効","revoked":"失効","connected":"通常接続","isolated":"隔離","keep":"保全","erase":"消去","wait":"実施しない","wipe":"初期化","7d":"7日","30d":"30日","unlimited":"無期限"}

static func all() -> Array:
	if not _catalog.is_empty(): return _catalog
	var shared := {"staff":"write","guest":"none"}
	var network := {"dns":"on","business":"allow","admin_public":"deny","tls":"on"}
	var account := {"former":"disabled","sessions":"revoked","current":"active","mfa":"on"}
	var incident := {"pc_a":"isolated","pc_b":"connected","logs":"keep","reset":"wait"}
	var portal := {"staff":"write","partner":"read","public":"none","expires":"7d","mfa":"on","tls":"on","audit":"on"}
	# File permissions: repair, read-only archive, guest publication, containment.
	_add(0,0,"社員が日報を保存できない","社員の保存操作のみ拒否されます。ゲストアクセスの遮断を維持し、社員の書き込み権限を復旧してください。",_with(shared,{"staff":"read"}),shared,{"share_work_file":"/srv/data/report.txt","intake":{"kind":"daily-report"},"fs_overrides":{"/srv/data/report.txt":"つばさ文具 / 経理日報\n本日受付 12件\n照合待ち 2件\n締め担当 staff\n","/srv/share/report.txt":"つばさ文具 / 経理日報\n前日受付 9件\n照合待ち 0件\n締め担当 staff\n"}})
	_add(0,1,"保管資料を閲覧専用にする","確定済み資料の誤更新を防ぎます。社員は読み取りのみ、ゲストは拒否してください。",shared,{"staff":"read","guest":"none"})
	_add(0,2,"公開資料フォルダーを整備","この共有フォルダーは公開資料専用です。社員に更新権限、来客に閲覧権限のみ付与してください。",{"staff":"read","guest":"write"},{"staff":"write","guest":"read"})
	_add(0,3,"ゲストの書き込みを禁止","公開資料に外部から書き込みが可能です。来客の閲覧を残し、書き込みだけを拒否してください。",{"staff":"write","guest":"write"},{"staff":"write","guest":"read"})
	_add(0,4,"情報流出時の共有停止","調査が終わるまでこの共有を停止します。社員・ゲストともアクセスを拒否してください。",{"staff":"write","guest":"read"},{"staff":"none","guest":"none"})
	_add(0,5,"会計資料の一般公開を解除","社内保管資料が来客にも見えています。社員の閲覧を維持し、更新とゲストアクセスを止めてください。",{"staff":"write","guest":"read"},{"staff":"read","guest":"none"})
	# Backups: distinct recovery sets and incidents; snapshots retain real file bytes.
	_add(1,0,"会計台帳の日次バックアップ","台帳を同一拠点へ日次バックアップし、別フォルダーへ復元して内容を照合してください。",{"schedule":"off","repository":"local"},{"schedule":"daily","repository":"local"},{"required_files":["/srv/data/ledger.txt"]})
	_add(1,1,"顧客台帳を別拠点へバックアップ","日次バックアップは稼働中ですが、保存先が同一拠点になっています。保存先を別拠点に変更し、顧客台帳の復元を確認してください。",{"schedule":"daily","repository":"local"},{"schedule":"daily","repository":"offsite"},{"required_files":["/srv/data/customers.csv"]})
	_add(1,2,"誤削除された受注表の復元","受注表が削除されています。別拠点にバックアップが存在します。既存データを上書きせず、/restore に復元してください。",{"schedule":"daily","repository":"offsite"},{"schedule":"daily","repository":"offsite"},{"required_files":["/srv/data/orders.csv"],"seed_snapshot_repository":"offsite","missing_files":["/srv/data/orders.csv"]})
	_add(1,3,"締め台帳の内容を確認できない","現物を保全し、保存分を調べて台帳を別フォルダーへ取り出してください。",{"schedule":"daily","repository":"offsite"},{"schedule":"daily","repository":"offsite"},{"required_files":["/srv/data/ledger.txt"],"seed_snapshot_repository":"offsite","fs_overrides":{"/srv/data/ledger.txt":"CORRUPTED DATA\n"},"latest_snapshot_overrides":{"/srv/data/ledger.txt":"CORRUPTED DATA\n"},"backup_preservation_required":true,"checks":["毎日の退避設定を維持する","別拠点の保存先を維持する","台帳を /restore 配下へ取り出し、顧客の照合票と一致する","調査開始時の台帳原本を保持する","顧客台帳・受注表など対象外の稼働データを保持する"]})
	_add(1,4,"停止したバックアップの再開","周期が無効になっています。別拠点への毎日退避を再開し、顧客・受注の2ファイルを復元確認してください。",{"schedule":"off","repository":"offsite"},{"schedule":"daily","repository":"offsite"},{"required_files":["/srv/data/customers.csv","/srv/data/orders.csv"]})
	_add(1,5,"全データの災害復旧リハーサル","同一拠点の手動退避のみ設定されています。別拠点への日次退避に変更し、顧客・受注・台帳の3点を復元してください。",{"schedule":"off","repository":"local"},{"schedule":"daily","repository":"offsite"},{"required_files":["/srv/data/customers.csv","/srv/data/orders.csv","/srv/data/ledger.txt"],"seed_snapshot_repository":"local"})
	_add_hardware_backup_install()
	# Network: each request has a different fault or an intentional maintenance state.
	_add(2,0,"請求確認用の一覧を開けない","院内の事務担当が法人向けの請求確認に使う一覧を開けません。同じ業務を再現し、通常の利用と管理接続の制限を確認してください。",_with(network,{"dns":"off"}),network)
	# Fresh contracts verify the real list, rather than a generic server banner.
	# Accepted saves retain their own stored probes and are not rewritten.
	for probe in _catalog.back().probes:
		if str(probe.get("id",""))=="business-check":
			probe.command = "curl https://intranet.client.test/api/business/orders"
			probe.expectation = 'status:200|"orders":'
			probe.label = "請求確認用の一覧を取得"
			probe.description = "同じ業務データを取得し、一覧として読めることを確認する"
	_add(2,1,"HTTPS接続の障害対応","業務サイトの暗号化接続が失敗します。TLSを有効に戻し、他の通信制御を維持してください。",_with(network,{"tls":"off"}),network)
	_add(2,2,"管理画面への外部アクセスを遮断","管理接続だけが外部へ公開されています。業務利用を止めずに外部からの管理接続を拒否してください。",_with(network,{"admin_public":"allow"}),network)
	_add(2,3,"誤遮断された業務通信の復旧","通信ルール変更後、業務サイトに接続できません。業務通信を復旧し、管理画面の外部遮断を維持してください。",_with(network,{"business":"deny"}),network)
	_add(2,4,"保守中の業務通信を一時停止","承認された保守時間です。名前解決とTLSは維持し、業務通信・外部管理接続を拒否してください。",network,_with(network,{"business":"deny"}))
	_add(2,5,"初期化されたゲートウェイを再構成","複数の設定が既定値に戻っています。DNS・業務通信・TLSを戻し、外部管理接続を拒否してください。",{"dns":"off","business":"deny","admin_public":"allow","tls":"off"},network)
	# Identity: separate faults plus a controlled containment request.
	_add(3,0,"退職者の新規ログインを止める","退職者アカウントが有効です。在籍者のアクセスを維持し、退職者アカウントを無効化してください。",_with(account,{"former":"active"}),account)
	_add(3,1,"退職者の既存セッションを失効","アカウントは停止済みですが、既存セッションが残っています。セッションを失効してください。",_with(account,{"sessions":"valid"}),account)
	_add(3,2,"在籍者の追加認証を有効化","在籍者はログインできますが追加認証がありません。業務利用を維持してMFAを有効にしてください。",_with(account,{"mfa":"off"}),account)
	_add(3,3,"誤停止された在籍者アカウントの復旧","在籍者アカウントまで無効化されています。在籍者を有効に戻し、退職者アカウントの停止を維持してください。",_with(account,{"current":"disabled"}),account)
	_add(3,4,"ID侵害時の一時停止","封じ込めのため旧アカウント・在籍者とも停止し、全既存セッションを失効してください。MFAは維持します。",_with(account,{"former":"active","sessions":"valid"}),_with(account,{"current":"disabled"}))
	_add(3,5,"退職処理の抜け漏れを修正","新規ログイン・既存セッション・追加認証に未対応の項目があります。在籍者の利用を維持して是正してください。",{"former":"active","sessions":"valid","current":"active","mfa":"off"},account)
	# Incident response: A/B/both, false positive, containment corrections.
	_add(4,0,"PC-Aの不審通信を封じ込め","ログで特定したPC-Aを隔離し、正常なPC-Bの通信を維持してください。証拠ログを /evidence/original.log に保全します。",_with(incident,{"pc_a":"connected"}),incident,{"suspect":"pc_a"})
	_add(4,1,"PC-Bの不審通信を封じ込め","今回の対象はPC-Bです。PC-Aの業務を止めずPC-Bを隔離し、証拠原本をコピーしてください。",_with(incident,{"pc_a":"connected"}),_with(incident,{"pc_a":"connected","pc_b":"isolated"}),{"suspect":"pc_b"})
	_add(4,2,"誤隔離した正常端末の隔離を解除","PC-Aが調査対象ですがPC-Bも隔離されています。PC-Bの隔離を解除し、証拠を保全してください。",_with(incident,{"pc_b":"isolated"}),incident,{"suspect":"pc_a"})
	_add(4,3,"2台に広がった不審通信","PC-A・PC-Bの双方に不審ログがあります。両端末を隔離し、ログを削除せず証拠を保全してください。",_with(incident,{"pc_a":"connected"}),_with(incident,{"pc_b":"isolated"}),{"suspect":"both"})
	_add(4,4,"誤検知から業務を再開","調査記録は正常な業務通信です。両端末の隔離を解除し、判断根拠となったログを保全してください。",_with(incident,{"pc_b":"isolated"}),_with(incident,{"pc_a":"connected"}),{"suspect":"none"})
	_add(4,5,"隔離対象を取り違えた対応の修正","不審なPC-Bが未隔離で、正常なPC-Aが誤隔離されています。対象を修正し、証拠ログを保全してください。",incident,_with(incident,{"pc_a":"connected","pc_b":"isolated"}),{"suspect":"pc_b"})
	# Sharing: explicit read, upload, duration, revocation, evidence requirements.
	_add(5,0,"取引先資料を閲覧専用にする","取引先が編集可能になっています。7日間の閲覧専用に変更し、社員の更新権限と認証・監査ログ設定を維持してください。",_with(portal,{"partner":"write"}),portal)
	_add(5,1,"共有リンクの有効期限を設定","共有期限が無期限になっています。7日で失効するよう変更し、他の制限は維持してください。",_with(portal,{"expires":"unlimited"}),portal)
	_add(5,2,"公開リンクからの閲覧を停止","資料が公開URLから閲覧できます。取引先の認証付き閲覧を残して公開アクセスを拒否してください。",_with(portal,{"public":"read"}),portal)
	_add(5,3,"取引先の納品アップロード窓口","承認された取引先に30日間の納品権限が必要です。読み書きを許可し、MFA・TLS・監査を維持してください。",portal,_with(portal,{"partner":"write","expires":"30d"}))
	_add(5,4,"契約終了後の共有を取り消す","契約が終了しました。取引先と公開アクセスを拒否し、社員の更新と監査記録を維持してください。",portal,_with(portal,{"partner":"none"}))
	_add(5,5,"外部共有の認証・監査ログ設定","外部共有のMFA・TLS・監査ログが無効です。7日間の閲覧専用を維持し、3項目を有効化してください。",_with(portal,{"mfa":"off","tls":"off","audit":"off"}),portal)
	_add(2,0,DISPLAY_COPY.copy("stock_case_title"),DISPLAY_COPY.copy("stock_case_brief"),{"dns":"off","business":"deny","admin_public":"deny","tls":"on"},network,{"id":"hardware-gateway-install","title":DISPLAY_COPY.copy("stock_case_title"),"brief":DISPLAY_COPY.copy("stock_case_brief"),"tier":1,"required_level":2,"reward":8200,"targets":[{"chapter":2,"case_id":"hardware-gateway-install","name":"WHG-2"}],"supply_requirement":{"sku":"gateway","quantity":1,"target_index":0}})
	_add_composite("composite-branch-reopen","支店の業務再開","支店の利用者が社内サイト、共有資料、取引先提出の順に業務を再開できません。各サービスの原因を調査し、支店の通常利用と不要な公開操作の拒否を確認してください。",2,2,8000,[{"chapter":2,"case_id":"service-2-case-3","name":"支店ゲートウェイ"},{"chapter":0,"case_id":"service-0-case-0","name":"支店共有サーバー"},{"chapter":5,"case_id":"service-5-case-0","name":"支店の外部ファイル共有"}])
	_catalog.append({"id":"branch-order-continuity","title":"新支店の受注表を別拠点へ退避","client":"北斗物流・新支店","chapter":1,"category":"operations","tier":1,"required_level":2,"brief":"業務を再開した新支店から、受注表の退避を依頼されました。前回の共有サーバーから引き継いだ partner-order.csv を毎日 offsite に退避し、/restore へ復元して顧客の照合票と比較してください。元の受注表と他の資料を変更せず、支店の業務を続けられる状態で納品します。","service":SERVICES[1],"evidence":[],"hints":[],"debrief":"退避できたことと、必要な内容を復元できたことを別々に確認します。","checks":["毎日の退避を有効にする","別拠点へ退避する","引き継いだ受注表を復元・照合する","元の受注表を維持する","他の業務資料を維持する"],"probes":[],"required_files":["/srv/data/partner-order.csv"],"backup_preservation_required":true,"initial":{"schedule":"off","repository":"local"},"desired":{"schedule":"daily","repository":"offsite"},"reward":6200,"work_family":"backup","source_case_id":"composite-branch-reopen"})
	_catalog.back().targets = [{"chapter":1,"case_id":"branch-order-continuity","name":"新支店の退避サーバー"}]
	_add_composite("composite-former-access","退職者IDによる不正アクセス","退職処理後も以前のセッションと公開共有が残り、取引先資料への不要な経路が疑われています。利用者の業務を止めずにアクセス経路を調査し、終了後の利用を再確認してください。",3,5,10000,[{"chapter":3,"case_id":"service-3-case-1","name":"ID管理"},{"chapter":5,"case_id":"service-5-case-2","name":"公開共有"}])
	_add_composite("composite-corruption-response","不審通信とデータ破損","不審端末の通信と会計台帳の破損が報告されました。端末の隔離、証拠保全、データ復元、管理経路の確認を順に行ってください。",4,7,16000,[{"chapter":4,"case_id":"service-4-case-1","name":"調査対象PC"},{"chapter":1,"case_id":"service-1-case-3","name":"会計台帳"},{"chapter":2,"case_id":"service-2-case-2","name":"管理ゲートウェイ"}])
	_add_endpoint_recovery()
	_catalog.append(HOTEL_HANDOFF.catalog_definition(_catalog.back()))
	_add_advanced_cases()
	PROFESSIONAL_CONTRACTS.append_to(_catalog)
	_ensure_metadata()
	return _catalog

static func _ensure_metadata() -> void:
	for item in _catalog:
		if not item is Dictionary: continue
		var id := str(item.get("id", "")); var category := str(item.get("category", "operations")); var tier := int(item.get("tier", 1)); var chapter := int(item.get("chapter", 0))
		item.retired_from_new_offers = RETIRED_NEW_OFFER_IDS.has(id) or bool(item.get("hotel_recovery_only", false))
		var family := str(item.get("work_family", ""))
		if family.is_empty():
			if id == "endpoint-recovery": family = "endpoint_recovery"
			elif id.begins_with("hardware-gateway"): family = "deployment_gateway"
			elif id.begins_with("hardware-backup"): family = "deployment_backup"
			elif id.begins_with("composite-"): family = id
			else: family = ["permissions", "backup", "network", "identity", "endpoint", "external_sharing"][clampi(chapter, 0, 5)]
		item.work_family = family
		var existing_skills: Variant = item.get("required_skills", {})
		if not existing_skills is Dictionary or existing_skills.is_empty(): item.required_skills = {category:tier}
		var skills: Dictionary = item.required_skills
		if not item.has("required_rank") or int(item.get("required_rank", 0)) <= 0: item.required_rank = int(skills.get(category, tier))

static func _add_endpoint_recovery() -> void:
	var probes: Array = []
	for device in ["a","b"]:
		probes.append({"id":"recovery-business-"+device,"label":DISPLAY_COPY.copy("rmd_probe_business_"+device),"command":"curl https://edr.client.test/pc-"+device+"/business","expectation":"status:200|business session healthy"})
		probes.append({"id":"recovery-clean-"+device,"label":DISPLAY_COPY.copy("rmd_probe_clean_"+device),"command":"edr status pc_"+device,"expectation":"\"ready\":true"})
	probes.append({"id":"evidence-log","label":DISPLAY_COPY.copy("rmd_check_evidence"),"command":"sha256sum /var/log/evidence.log","expectation":"pending-evidence-hash"})
	for probe in probes:
		probe.description = DISPLAY_COPY.copy("rmd_probe_description")
		probe.merge({"recorded":false,"passed":false,"fresh":false,"result":""})
	var config := {"pc_a":"connected","pc_b":"connected","logs":"keep","reset":"wait"}
	_catalog.append({"id":"endpoint-recovery","title":DISPLAY_COPY.copy("rmd_case_title"),"client":CLIENTS[1],"chapter":4,"category":"response","tier":2,"required_level":5,"brief":DISPLAY_COPY.copy("rmd_case_brief"),"service":SERVICES[4],"evidence":[DISPLAY_COPY.copy("rmd_guide_review")],"hints":[],"debrief":DISPLAY_COPY.copy("rmd_debrief"),"checks":[DISPLAY_COPY.copy("rmd_check_business"),DISPLAY_COPY.copy("rmd_check_clean"),DISPLAY_COPY.copy("rmd_check_evidence")],"probes":probes,"desired":config.duplicate(true),"initial":config.duplicate(true),"required_files":[],"reward":7800,"suspect":"pc_a","edr_recovery_required":true})
	_catalog.back().engagement_brief = "本社の外部送信と、入稿室の業務停止を調査してください。端末・ファイル・変更記録を比較し、証拠を保全して両拠点の業務を復旧します。対応中の不審送信は1分¥100、入稿・制作の停止は1分¥50の補償経費がかかります。"
	_catalog.back().reward = 15600 # Both authored sites; retain the former two-site quote.
	_catalog.back().targets = preload("res://scripts/endpoint_engagement.gd").profiles(_catalog.back())

static func _add_advanced_cases() -> void:
	var ai_followup = preload("res://scripts/saas_ai_followup.gd")
	_catalog.append({"id":ai_followup.CASE_ID,"title":ai_followup.TITLE,"client":ai_followup.CLIENT,"chapter":3,"category":"response","tier":1,"required_level":8,"required_skills":{"response":1},"brief":ai_followup.BRIEF,"service":"AI連携・公開前審査","evidence":[],"hints":[],"debrief":"資料参照と送付先の許可範囲を実測し、要約の社内受付と外部送信の記録を報告しました。","checks":[DISPLAY_COPY.copy("ai_preflight_check_read"),DISPLAY_COPY.copy("ai_preflight_check_write"),DISPLAY_COPY.copy("ai_preflight_check_business"),DISPLAY_COPY.copy("ai_preflight_check_policy"),DISPLAY_COPY.copy("ai_preflight_check_report")],"probes":[],"desired":{},"initial":{},"targets":[{"chapter":3,"case_id":ai_followup.CASE_ID,"name":"北斗物流・AI Gate"}],"reward":10000,"advanced_work_minutes":120,"work_family":"ai-preflight"})
	_add_portal_pentest()
	_add_advanced_case("advanced-hunt", "response", 4, 7, {"response":5,"advisory":2}, 26000, 260)
	_add_advanced_case("advanced-pentest", "advisory", 2, 7, {"advisory":5,"operations":2}, 28000, 300)
	_add_relay_pentest()
	_add_advanced_case("advanced-recovery", "operations", 1, 8, {"operations":5,"response":3}, 32000, 320)
	_add_advanced_case("advanced-ddos", "response", 2, 7, {"operations":5,"response":2}, 30000, 240)
	_add_advanced_case("advanced-api", "advisory", 5, 7, {"advisory":5}, 34000, 260)
	_add_advanced_case("advanced-supplychain", "advisory", 1, 10, {"advisory":6,"response":5}, 40000, 340)
	_add_advanced_case("advanced-cloud", "operations", 3, 7, {"response":5,"operations":2}, 30000, 240)
	_catalog.append({"id":"advanced-saas-response","title":"緊急: SaaS連携の漏洩警報","client":"北斗物流","chapter":3,"category":"response","tier":1,"required_level":3,"required_skills":{"response":1},"brief":"SaaS事業者から連携トークンの漏洩警報が届きました。当社データの流出はまだ未確認です。請求連携と資料ビューアの承認・発行済み接続を照合し、持出しの有無と停止を確認してください。本日の請求BILL-001を受け付けるまでが契約です。","service":"SaaS緊急対応","evidence":[],"hints":[],"debrief":"流出の実記録と接続の停止、通常請求の受付を確認しました。","checks":[DISPLAY_COPY.copy("adv_check_summary")],"probes":[],"desired":{},"initial":{},"targets":[{"chapter":3,"case_id":"advanced-saas-response","name":"北斗物流・SaaS連携"}],"reward":9000,"advanced_work_minutes":120,"work_family":"saas-response"})
	_catalog.append({"id":"advanced-saas-watch","title":"緊急: 新しいSaaS連携の検出","client":"北斗物流","chapter":3,"category":"response","tier":1,"required_level":3,"required_skills":{"response":1},"brief":"前回の対応後、新たな資料エクスポート連携が追加されました。前回の承認原記録と今回の申請を照合し、外部同期と既存接続を調べてください。通常の請求業務を保ったまま、持出しの有無と停止を報告してください。","service":"SaaS継続監視・緊急対応","evidence":[],"hints":[],"debrief":"流出の実記録と接続の停止、通常請求の受付を確認しました。","checks":[DISPLAY_COPY.copy("adv_check_summary")],"probes":[],"desired":{},"initial":{},"targets":[{"chapter":3,"case_id":"advanced-saas-watch","name":"北斗物流・SaaS連携"}],"reward":9000,"advanced_work_minutes":120,"work_family":"saas-response","saas_watch_only":true,"retired_from_new_offers":true})
	_catalog.append({"id":"advanced-saas-sessions","title":"緊急: 承認済み連携からの資料取得","client":"北斗物流","chapter":3,"category":"response","tier":1,"required_level":5,"required_skills":{"response":1},"brief":"承認済みの請求連携で、いつもと異なる資料取得の要求が観測されました。月次集計も同じアプリを使っています。発行原本と接続ごとの要求記録を照合し、必要な業務接続を残して対応してください。本日の請求BILL-003と社内集計の再確認までが契約です。","service":"SaaS接続調査・緊急対応","evidence":[],"hints":[],"debrief":"接続ごとの記録を比較し、資料取得の封じ込めと請求・集計の継続を確認しました。","checks":[DISPLAY_COPY.copy("adv_check_summary")],"probes":[],"desired":{},"initial":{},"targets":[{"chapter":3,"case_id":"advanced-saas-sessions","name":"北斗物流・業務連携の接続"}],"reward":12500,"advanced_work_minutes":120,"work_family":"saas-sessions"})
	_add_advanced_case("advanced-malware", "response", 4, 10, {"response":7}, 36000, 300)
	_add_advanced_case("advanced-detection", "operations", 4, 8, {"operations":6,"advisory":3}, 42000, 360)

static func _add_portal_pentest() -> void:
	_catalog.append({"id":"advanced-portal","title":DISPLAY_COPY.copy("adv_portal_title"),"client":DISPLAY_COPY.copy("adv_portal_client"),"chapter":5,"category":"advisory","tier":1,"required_level":1,"required_skills":{"advisory":0},"brief":DISPLAY_COPY.copy("adv_portal_brief"),"service":DISPLAY_COPY.copy("adv_portal_service"),"evidence":[],"hints":[],"debrief":DISPLAY_COPY.copy("adv_portal_debrief"),"checks":[DISPLAY_COPY.copy("portal_check_report"),DISPLAY_COPY.copy("portal_check_security_retest"),DISPLAY_COPY.copy("portal_check_business_retest")],"probes":[],"desired":{},"initial":{},"targets":[{"chapter":5,"case_id":"advanced-portal","name":"portal.mihama.test"}],"reward":6500,"advanced_work_minutes":90,"work_family":"web-pentest"})

static func _add_relay_pentest() -> void:
	# Several connected hosts belong to one engagement, not separate site VMs.
	_catalog.append({"id":"advanced-pentest-relay","title":DISPLAY_COPY.copy("adv_relay_title"),"client":"北斗物流","chapter":2,"category":"advisory","tier":3,"required_level":7,"required_skills":{"advisory":5,"operations":2},"brief":DISPLAY_COPY.copy("adv_relay_brief"),"service":DISPLAY_COPY.copy("adv_service"),"evidence":[],"hints":[],"debrief":DISPLAY_COPY.copy("adv_relay_debrief"),"checks":[DISPLAY_COPY.copy("adv_check_summary")],"probes":[],"desired":{},"initial":{},"targets":[{"chapter":2,"case_id":"advanced-pentest-relay","name":DISPLAY_COPY.copy("adv_relay_environment")}],"reward":32000,"advanced_work_minutes":340})

static func _add_advanced_case(id: String, category: String, chapter: int, required_level: int, required_skills: Dictionary, reward: int, work_minutes: int) -> void:
	var slug := id.trim_prefix("advanced-")
	_catalog.append({"id":id,"title":DISPLAY_COPY.copy("adv_%s_title" % slug),"client":CLIENTS[chapter % CLIENTS.size()],"chapter":chapter,"category":category,"tier":3,"required_level":required_level,"required_skills":required_skills,"brief":DISPLAY_COPY.copy("adv_%s_brief" % slug),"service":DISPLAY_COPY.copy("adv_service"),"evidence":[],"hints":[],"debrief":DISPLAY_COPY.copy("adv_check_summary"),"checks":[DISPLAY_COPY.copy("adv_check_summary")],"probes":[],"desired":{},"initial":{},"targets":[{"chapter":chapter,"case_id":id,"name":DISPLAY_COPY.copy("adv_environment")}],"reward":reward,"advanced_work_minutes":work_minutes})

static func _add_hardware_backup_install() -> void:
	var initial := {"schedule":"off","repository":"local"}
	var desired := {"schedule":"daily","repository":"local"}
	var required := ["/srv/data/customers.csv","/srv/data/orders.csv","/srv/data/ledger.txt"]
	var extra := {"required_files":required,"hardware_commissioning":true,"supply_requirement":{"sku":"backup_appliance","quantity":1,"target_index":0}}
	var probes := _probes(1, desired, extra)
	_catalog.append({"id":"hardware-backup-install","title":DISPLAY_COPY.copy("stock_backup_case_title","Backup appliance commissioning"),"client":CLIENTS[1],"chapter":1,"category":"operations","tier":1,"required_level":2,"brief":DISPLAY_COPY.copy("stock_backup_case_brief","Commission the customer backup appliance, restore the three required records, and verify their real contents."),"service":SERVICES[1],"evidence":[DISPLAY_COPY.copy("stock_backup_case_check","Verify snapshots, restore output, and file hashes before shipment.")],"hints":[],"debrief":DISPLAY_COPY.copy("stock_backup_case_debrief","The appliance is useful only after a real restore and content verification."),"checks":[DISPLAY_COPY.copy("stock_backup_case_check","Restore and compare all required records before delivery." )],"probes":probes,"desired":desired.duplicate(true),"initial":initial.duplicate(true),"required_files":required.duplicate(true),"reward":9000,"supply_requirement":extra.supply_requirement.duplicate(true),"hardware_commissioning":true})
	# Capture original records only when accepting a newly authored case.
	# Existing saved VMs retain their prior scope and are never backfilled.
	_catalog.back().backup_preservation_required = true
	_catalog.back().checks = ["日次の退避を有効にする", "拠点内の保存先を使う", "3台帳を /restore に復元・照合する", "元の業務台帳を維持する", "対象外の資料を維持する"]

static func _with(base: Dictionary, changes: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	result.merge(changes,true)
	return result

static func _add_composite(id: String, title: String, brief: String, chapter: int, required_level: int, reward: int, targets: Array) -> void:
	_catalog.append({"id":id,"title":title,"client":{"composite-branch-reopen":"北斗物流・新支店","composite-former-access":"東雲会計事務所","composite-corruption-response":"港町クリニック"}.get(id,"取引先"),"chapter":chapter,"category":{"composite-branch-reopen":"advisory","composite-former-access":"operations","composite-corruption-response":"response"}.get(id,"operations"),"tier":1 if required_level==2 else (2 if required_level==5 else 3),"required_level":required_level,"brief":brief,"service":"複数サービス連携","evidence":["時系列ログと利用者への影響を整理","各拠点の通常利用と拒否すべき操作を確認する"],"hints":[],"debrief":"複数サービスの因果関係と復旧順序を記録してから納品します。","checks":["各対象サービスの原因調査・復旧・再検証を完了する","全対象の業務利用と不要なアクセス拒否を確認する"],"targets":targets,"target_count":targets.size(),"desired":{},"initial":{},"required_files":[],"probes":[],"reward":reward})

	if id == "composite-corruption-response": _catalog.back()["brief"] = DISPLAY_COPY.copy("business_corruption_brief")
	if id == "composite-branch-reopen": _catalog.back()["brief"] = DISPLAY_COPY.copy("branch_brief")

static func _add(chapter: int, variant: int, title: String, brief: String, initial: Dictionary, desired: Dictionary, extra: Dictionary = {}) -> void:
	var tier := 1 + int(variant/2)
	var checks: Array[String] = []
	var evidence: Array[String] = []
	for key in desired:
		checks.append(_check_text(str(key),str(desired[key])))
		
	if chapter == 4:
		title = DISPLAY_COPY.copy("edr_case_title_"+str(variant), "Endpoint investigation")
		checks[0] = DISPLAY_COPY.copy("edr_check_a", "PC-A response matches investigation")
		checks[1] = DISPLAY_COPY.copy("edr_check_b", "PC-B response matches investigation")
	if chapter == 1: checks.append("指定データを復元先へ展開し、元データと内容を照合")
	if chapter == 4: checks.append("不審端末の業務影響を確認し、証拠原本と保全コピーを照合")
	if evidence.is_empty(): evidence.append("設定だけで判断せず、顧客データと業務操作の結果を確認する")
	var case_data := {"id":"service-%d-case-%d" % [chapter,variant],"title":title,"client":CLIENTS[(chapter+variant)%CLIENTS.size()],"chapter":chapter,"category":CATEGORIES[chapter],"tier":tier,"required_level":[1,2,5,7,10,12][variant],"brief":_brief(chapter,variant),"service":SERVICES[chapter],"evidence":evidence,"hints":[],"debrief":"操作の成否と復旧記録を確認してから納品してください。","checks":checks,"probes":_probes(chapter,desired,extra),"desired":desired.duplicate(true),"initial":initial.duplicate(true),"required_files":[],"reward":[2400,3200,5200,6800,9800,12500][variant]+chapter*250}
	case_data.merge(extra,true)
	_catalog.append(case_data)

static func _brief(chapter: int, variant: int) -> String:
	var briefs := [
		["経理の社員から『日報は開けるが保存できない』と連絡がありました。今日の締めまでに通常の編集を再開したいそうです。来客には社内資料を見せない運用です。",
		"確定済みの資料を誤って書き換えたため、保管庫を閲覧専用にします。社員は読めれば十分で、来客への公開は認められていません。",
		"展示会の資料を来客にも配ります。社員が原稿を更新し、来客が完成版を読む運用です。外部の人が内容を変えられないことを確認してください。",
		"来客から『資料フォルダーにファイルを置けた』と報告されました。公開資料の閲覧は続けたいので、共有を全面停止せずに調べてください。",
		"機密資料の流出が疑われています。調査完了まで、この共有は社内外とも利用停止する承認が出ています。保管データを消さずアクセスを止めてください。",
		"来客用のPCから会計資料が見えてしまいました。この資料は確定済みで、社内の担当者が閲覧するためだけに残す方針です。"],
		["前日の会計台帳を戻せるか、経理から確認依頼です。毎日の自動退避と、別フォルダーへの復元を実演してください。今回は同一拠点の保管が契約条件です。",
		"災害対策として顧客台帳を別拠点にも保管する契約になりました。現在の退避先を調べ、毎日の運用と復元した台帳の内容を確認してください。",
		"受注表を誤って削除したため、出荷の照合ができません。別拠点に残る正常な退避データを探し、/restore へ取り出してください。",
		"台帳の締め残高を確認できず、経理の作業が止まっています。別拠点の保存分を調べ、正常時の照合票に合う台帳を /restore 配下へ取り出してください。現在の台帳と、業務で使っている顧客台帳・受注表は変更しないでください。保存ID・復元先・照合結果を経理へ引き渡します。本番ファイルへの置き換えは今回の範囲外です。",
		"今朝のバックアップ完了通知が届いていません。顧客台帳と受注表を毎日別拠点へ退避する運用です。設定を修復し、両方の復元を確認してください。",
		"本社が使えなくなった場合の復旧訓練です。顧客・受注・会計の3ファイルを毎日別拠点へ保管し、/restore の内容まで照合してください。"],
		["港町クリニックの事務担当から『法人向けの請求確認に使う一覧を開けない』と連絡がありました。https://intranet.client.test/sales で同じ業務を再現し、原因を調べてください。復旧後は一覧を再確認し、暗号化通信と外部からの管理接続の遮断を維持してください。",
		"業務サイトを開くと、安全な接続を確立できないというエラーが出ます。通常業務を戻し、管理画面の外部遮断は維持してください。",
		"外部回線から管理画面が見えるという通報です。営業の業務サイトは止めず、公開範囲を調査してください。",
		"通信ルール変更後、営業の業務サイトに接続できません。DNS・TLS・通信制御を確認し、管理画面の外部遮断を維持して復旧してください。",
		"承認済みの保守作業です。保守中は業務サイトへの通信を止めます。名前解決と暗号化設定は残し、外部管理接続も閉じた状態にしてください。",
		"機器交換後、複数の部署で社内サイトへの接続に失敗しています。通常業務を再開し、管理画面が外部から使えないことも確認してください。"],
		["退職した人が、以前のIDで再びログインできたと連絡がありました。在籍者は通常どおり働ける状態を保って調べてください。",
		"退職者のIDは止めたはずなのに、開いたままのブラウザでは使えています。新規ログインと既存セッションを別々に確認してください。",
		"在籍者のアカウントに追加認証を導入する依頼です。社員の業務を継続し、退職済みIDや古いセッションを再び有効にしないでください。",
		"退職処理後、在籍社員までログイン不能になりました。在籍者のアクセスを復旧し、退職者のアクセス遮断を維持してください。",
		"ID侵害の疑いがあり、全利用者の一時停止が承認されました。旧IDと在籍IDの両方を止め、残ったセッションも使えなくしてください。認証設定は保持します。",
		"退職処理の監査です。新規ログイン・既存セッション・在籍者の追加認証をそれぞれ点検し、在籍者の業務だけを維持してください。"],
		["端末から不審な通信が発生しています。ログの送信元と宛先を照合し、不審な端末のみ隔離してください。正常な端末の業務は維持します。",
		"前回とは別の端末から警告が出ました。前回の設定を使い回さず、今回のログから対象を判断してください。証拠原本も残します。",
		"警告対応のあと、関係ない端末まで仕事ができなくなりました。不審通信の記録と現在の隔離状態を比べ、正常な端末だけを戻してください。",
		"警告が複数の端末で発生しました。影響範囲をログで調べ、見落としなく封じ込めてください。初期化は承認されていません。",
		"業務通信を異常として検知した可能性があります。ログの承認済み通信を確認し、誤隔離なら仕事を再開できる状態へ戻してください。判断に使う原本は保存します。",
		"隔離後もアラートが続き、別の端末が通信不能になっています。ログと隔離対象を照合し、設定を見直してください。"],
		["取引先が閲覧用資料を編集できる状態です。取引先は認証付きで7日間閲覧のみ、社員のみ更新可能に設定してください。",
		"共有リンクが無期限になっています。取引先の閲覧期限を7日に設定し、一般公開を遮断、認証と監査ログを維持してください。",
		"未認証のユーザーにも取引先資料が公開されています。認証済み取引先の閲覧を維持し、一般公開アクセスを遮断してください。",
		"今回の契約では、取引先が30日間ファイルを納品します。認証付きの閲覧とアップロードを許可し、一般公開はせず、記録を残してください。",
		"取引先の契約が満了しました。外部アクセスを遮断し、社内の更新権限と監査ログの記録は維持してください。",
		"社外共有の監査で、認証・暗号化・ログ記録の不足が指摘されました。取引先の閲覧期限（7日）と社員の更新権限を維持したまま是正してください。"]
	]
	return briefs[chapter][variant]

static func _check_text(key: String, value: String) -> String:
	var meanings := {
		"staff":{"write":"社員は資料を閲覧・更新できる","read":"社員は閲覧のみ可能（更新不可）","none":"社員からのアクセスも停止する"},
		"guest":{"none":"来客は閲覧も更新もできない","read":"来客は閲覧のみ可能（更新不可）","write":"来客は資料を更新できる"},
		"schedule":{"daily":"業務データを毎日自動で退避する","off":"自動退避を停止する"},
		"repository":{"offsite":"退避データを別拠点に保管する","local":"退避データを同一拠点に保管する"},
		"dns":{"on":"社内サイトの名前から接続先を取得できる"},
		"business":{"allow":"営業の業務サイトへ接続できる","deny":"保守中の業務サイトへの通信は遮断する"},
		"admin_public":{"deny":"外部から管理画面へ接続できない"},
		"tls":{"on":"通信は暗号化されている"},
		"former":{"disabled":"退職者は新しくログインできない"},
		"sessions":{"revoked":"退職者の既存セッションも利用できない"},
		"current":{"active":"在籍者はログインできる","disabled":"在籍者も一時的にログインを停止する"},
		"mfa":{"on":"利用者の追加認証を必須化"},
		"pc_a":{"isolated":"ログで特定した不審端末の通信を止める","connected":"正常端末の業務通信を維持する"},
		"pc_b":{"isolated":"影響範囲に含まれる端末を隔離する","connected":"影響のない端末は業務を継続する"},
		"logs":{"keep":"判断に使用した原本ログを残す"},
		"reset":{"wait":"調査対象の初期化・消去はしない"},
		"partner":{"read":"取引先は閲覧だけができる","write":"取引先は閲覧と納品アップロードができる","none":"取引先は資料へアクセスできない"},
		"public":{"none":"公開URLから資料を利用できない"},
		"expires":{"7d":"共有の有効期間は7日","30d":"共有の有効期間は30日"},
		"audit":{"on":"資料を利用した記録を残す"}
	}
	return str(meanings.get(key,{}).get(value,LABELS.get(key,key)+": "+VALUES.get(value,value)))

static func _probes(chapter: int, desired: Dictionary, extra: Dictionary) -> Array:
	var probes: Array = []
	if chapter == 0:
		probes = [{"id":"staff-read","label":"社員の閲覧","command":"smbclient //client/share -U staff -c ls","expectation":"report.txt" if desired.get("staff") in ["read","write"] else "DENIED"},{"id":"staff-write","label":"社員の保存","command":"smbclient //client/share -U staff -c \"put /srv/data/orders.csv\"","expectation":"OK" if desired.get("staff") == "write" else "DENIED"},{"id":"guest-read","label":"来客の閲覧","command":"smbclient //client/share -U guest -c ls","expectation":"report.txt" if desired.get("guest") in ["read","write"] else "DENIED"},{"id":"guest-write","label":"来客の保存","command":"smbclient //client/share -U guest -c \"put /srv/data/orders.csv\"","expectation":"OK" if desired.get("guest") == "write" else "DENIED"}]
		if str(extra.get("share_work_file", "")) == "/srv/data/report.txt":
			for probe in probes:
				if str(probe.id).ends_with("-write"): probe.command = str(probe.command).replace("/srv/data/orders.csv", "/srv/data/report.txt")
	elif chapter == 1:
		var required: Array = extra.get("required_files", ["/srv/data/ledger.txt"])
		var hashes := {"customers.csv":"20c8fd203bc89fd002d46648ced954d5cb3748a97cde755b0ce43fc895bbf115","orders.csv":"3870c28fbbaf84f8f89e8cae67a924d2830c688a67b570a2977aa8787864eff3","ledger.txt":"624393b28c7619034eb619898b67e9ff4dc49c605fd73bb926417d68bdf21a9e"}
		probes = [{"id":"backup-list","label":"退避先と履歴","command":"restic snapshots","expectation":"Repository|"+str(desired.get("repository","offsite"))}]
		for path in required:
			var filename := str(path).get_file()
			probes.append({"id":"restore-"+filename,"label":"復元照合 / "+filename,"command":"sha256sum /restore/"+filename,"expectation":hashes.get(filename,"missing")})
	elif chapter == 2:
		probes = [{"id":"dns-check","label":"名前解決を確認","command":"dig intranet.client.test","expectation":"NOERROR" if desired.get("dns") == "on" else "SERVFAIL"},{"id":"business-check","label":"業務サイトを確認","command":"curl https://intranet.client.test","expectation":"status:200|Sales workspace" if desired.get("business") == "allow" and desired.get("tls") == "on" else "curl: (7)" if desired.get("business") == "deny" else "curl: (6)"},{"id":"admin-check","label":"管理画面の外部公開を確認","command":"curl https://admin.client.test","expectation":"status:403" if desired.get("admin_public") == "deny" else "status:200|Management console"}]
	elif chapter == 3:
		probes = [{"id":"former-login","label":"旧利用者の新規ログインを確認","command":"curl https://identity.client.test/former/login","expectation":"status:401" if desired.get("former") == "disabled" else "status:200"},{"id":"former-session","label":"退職者の既存セッションを確認","command":"curl https://identity.client.test/former/session","expectation":"status:401|session revoked" if desired.get("sessions") == "revoked" else "status:200"},{"id":"current-mfa","label":"在籍者の追加認証を確認","command":"curl https://identity.client.test/current/login","expectation":"status:200|challenge required" if desired.get("current") == "active" and desired.get("mfa") == "on" else "status:403" if desired.get("current") != "active" else "status:200|not required"}]
	elif chapter == 4:
		probes = [{"id":"pc-a-check","label":"PC-Aの通信を確認","command":"curl https://edr.client.test/pc-a/outbound","expectation":"status:403|isolated" if desired.get("pc_a") == "isolated" else "status:200|outbound allowed"},{"id":"pc-b-check","label":"PC-Bの業務継続を確認","command":"curl https://edr.client.test/pc-b/business","expectation":"status:200|business session healthy" if desired.get("pc_b") == "connected" else "status:403|business interrupted"},{"id":"evidence-log","label":"証拠ログの完全性を確認","command":"sha256sum /var/log/evidence.log","expectation":"pending-evidence-hash"}]
	else:
		var partner_link := "current"
		var old_link := "week-old" if desired.get("expires") == "30d" else "month-old"
		var old_expectation := "status:200" if desired.get("expires") == "unlimited" or (desired.get("expires") == "30d" and old_link == "week-old") else "status:410"
		probes = [{"id":"partner-read","label":"取引先の閲覧を確認","command":"curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link="+partner_link+"'","expectation":"status:200" if desired.get("partner") in ["read","write"] else "status:403"},{"id":"partner-password-only","label":"MFA未完了の閲覧拒否","command":"curl -H 'Authorization: Bearer partner-session' 'https://portal.client.test/partner?link=current'","expectation":"status:401|mfa_required" if desired.get("mfa") == "on" else "status:200"},{"id":"partner-write","label":"取引先の更新可否を確認","command":"curl -X PUT -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=current'","expectation":"status:200" if desired.get("partner") == "write" else "status:403"},{"id":"public-read","label":"公開URLの拒否を確認","command":"curl 'https://portal.client.test/public?link=current'","expectation":"status:403" if desired.get("public") == "none" else ("status:401|mfa_required" if desired.get("mfa") == "on" else "status:200")},{"id":"expired-link","label":"期限切れリンクを確認","command":"curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link="+old_link+"'","expectation":old_expectation},{"id":"portal-audit","label":"許可・拒否の監査記録を確認","command":"journalctl","expectation":"portal GET"}]
	for probe in probes:
		probe.description = _probe_description(probe); probe.recorded = false; probe.passed = false; probe.fresh = false; probe.result = ""
		if chapter == 4 and str(probe.id) in ["pc-a-check","pc-b-check"]:
			probe.label = DISPLAY_COPY.copy("edr_probe_a" if str(probe.id)=="pc-a-check" else "edr_probe_b", "Endpoint connection test")
			probe.description = DISPLAY_COPY.copy("edr_probe_description", "Compare the observed connection with the investigation records.")
	if chapter == 5:
		# Normal and negative access are separate measurements. Staff access is
		# also tested when the customer's partner relationship has ended.
		probes.insert(0,{"id":"staff-read","label":"社員の業務継続","command":"curl -H 'Authorization: Bearer staff-session' 'https://portal.client.test/staff?link=current'","expectation":"status:200" if desired.get("staff") in ["read","write"] else "status:403"})
		probes.insert(1,{"id":"partner-anonymous","label":"未認証でのアクセス","command":"curl 'https://portal.client.test/partner?link=current'","expectation":"status:401|login required"})
		for probe in probes:
			if probe.id == "expired-link":
				probe.label = "31日前の共有リンク"
				probe.command = "curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=month-old'"
				probe.expectation = "status:410" if desired.get("expires") != "unlimited" else ("status:200" if desired.get("partner") in ["read","write"] else "status:403")
			if probe.id == "portal-audit": probe.expectation = "portal GET|status=200 result=allowed|result=denied"
		probes.insert(probes.size()-1,{"id":"week-old-link","label":"8日前の共有リンク","command":"curl -H 'Authorization: Bearer partner-mfa-session' 'https://portal.client.test/partner?link=week-old'","expectation":"status:410" if desired.get("expires") == "7d" else ("status:200" if desired.get("partner") in ["read","write"] else "status:403")})
		for probe in probes:
			probe.description = _probe_description(probe); probe.recorded = false; probe.passed = false; probe.fresh = false; probe.result = ""
	return probes

static func by_id(id: String) -> Dictionary:
	for item in all():
		if item.id == id: return item
	return {}

static func _probe_description(probe: Dictionary) -> String:
	var expect := str(probe.expectation)
	if str(probe.get("id","")) == "portal-audit": return "アクセスの記録で、利用者・対象・許可と拒否の結果を確認します。"
	if expect.begins_with("status:410"): return "発行日からの有効期間を過ぎたリンクの応答を確認します。"
	if str(probe.get("command", "")).begins_with("sha256sum "): return "保全した原本と現在のログが同一内容であることを確認します。"
	if "ACCESS_DENIED" in expect or expect == "DENIED": return "該当ユーザーの操作がアクセス拒否されることを確認します。"
	if expect.begins_with("status:403"): return "この接続は許可されません。サービスが応答したうえでアクセスを拒否する必要があります。"
	if expect.begins_with("status:401"): return "必要な認証を満たさないセッションでアクセスできないことを確認します。"
	if expect.begins_with("status:200"): return "業務操作に成功し、必要な認証・通信条件が応答に含まれることを確認します。"
	if "curl: (7)" in expect: return "承認された保守中のため、業務通信がファイアウォールで拒否されることを確認します。"
	if "NOERROR" in expect: return "社内サイトのホスト名から接続先のIPアドレスを取得できることを確認します。"
	if expect.length()==64: return "退避データと復元先ファイルの内容が一致することを確認します。"
	if expect.begins_with("Repository|"): return "指定の退避先に正常なバックアップが存在することを確認します。"
	if expect.begins_with("/restore/"): return "指定した業務ファイルが復元先フォルダーに存在することを確認します。"
	if expect == "PC-A": return "送信元・宛先・プロセスを読み、承認された業務通信と異常な通信を区別してください。"
	return "この利用者が資料を"+("保存できる" if expect == "OK" else "閲覧できる")+"ことを確認します。"
