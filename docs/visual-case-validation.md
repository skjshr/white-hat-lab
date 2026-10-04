# 代表2案件の図解UI検証（2026-10-04）

基準は `b02be49c5f34ecba326165de5eb35020bce961d7`。対象は通信復旧 `service-2-case-0` と台帳復旧 `service-1-case-3`。既存の要求実測・顧客照合・原本保全・保存失敗時の巻き戻しを、業務アプリとBackrestの図で見せる変更である。

通信は短い状態バッジの列と接続図を検討し、停止位置と検査・設定操作を結び付けられる接続図を選んだ。台帳は生テキスト比較と実数値の書類カードを検討し、日付・金額の差、復元先、保全状態を見比べられる書類カードを選んだ。設計理由は [visual-case-workspaces.md](visual-case-workspaces.md) に記録した。これは実装と画像を比較した設計判断であり、初見ユーザーに複数案を試してもらった実験ではない。

## 確認済みの意味と既存機能

独立したソースレビューでは、表示の読み取りによる修復・観測・工数消費は追加されていない。Game、VM、顧客の受入条件はこの増分で変更していない。通信図の全体成功には既存の実測 `passed` が必要であり、HTTP422は到達後のアプリ異常、DNS失敗は管理遮断未確認として扱う。古い結果・未観測・不正な応答を成功にしない。

台帳の構文を読めること、bytesが同じこと、顧客照合の成功は別々に判定する。原本の「保持」は健康の証明ではない。復元計画の現在値と変更後を実エントリから描き、原本・対象外への書き込み予定を現在の保持状態と分ける。既存の計画再確認、ファイル別の復元先、複合案件の本番置換許可も維持する。ファイアウォールの成功操作後に限り、破棄されたボタンのフォーカスを同じ文脈の操作へ戻す。

`test_visual_case_state.gd` は154 assertions、失敗0。実VMの通信結果と実restic計画に加え、明示した不正・旧記録fixtureを確認した。投影対象の不変性、HTTP422、HTTP本文中の誤解を招く文字列、空ファイル、破損内容同士の一致、原本変更予定、skipped／unchanged、対象外追加、パス境界、複合案件を含む。ログは外部監査フォルダ `audit/visual-20261004/semantic/plan-final.stdout.log`。実行前後の5ファイルのハッシュは一致し、最終ソースとの一致も確認した。

## 14件の回帰

製品ソース確定後、隔離した保存プロファイルでGodot 4.7.2のheadless実行を行った。14件すべてexit 0、所定の完了マーカーあり。スクリプトエラー、assertion失敗、リソースリークはなく、環境の証明書ストア警告だけを記録した。

| テスト | 結果 |
|---|---|
| network_request_evidence | 56 assertions、PASS |
| backup_authorization | 91 assertions、PASS |
| backup_authorization_integration | 53 assertions、PASS |
| business_workspace | PASS |
| business_transactions | 74 assertions、PASS |
| business_cross_service_ui | 69 assertions、PASS |
| backup_console | failures=0 |
| firewall_ui | failures=0 |
| interface | PASS（編集・コマンド・案件・経済・保存・描画） |
| window_layout | WINDOW_LAYOUT_OK |
| tutorial_ui | failures=0（通常経路） |
| linked_identity | PASS |
| linked_identity_ui | failures=0 |
| service_workflows | 97 assertions、failures=0 |

実行条件・個別stdout/stderr・判定は `audit/visual-20261004/regression/`、集計は `summary.json`。製品スクリプト、content、project設定、対象14テストの計159ファイルは実行前後でハッシュが一致した。同時に修正されていた実画面テスト2件の倍率fixtureは、この不変性の主張に含めない。headlessの成功だけでは画面の読みやすさや操作到達性を判断しない。

## 実画面の受入記録

最終採用は次の4実行。すべてexit 0、失敗0、実行エラーは環境の証明書ストア警告だけだった。狭幅は960×600でGame設定とInterface外枠の両方を130%にし、通信図または実フォントの倍率も各checkpointで確認した。

| 画面 | 条件 | assertions | 実入力（click／key／wheel） | 外部監査フォルダ |
|---|---|---:|---|---|
| 通信 | 1440×900・100% | 408 | 25／84／0 | `after/network-wide` |
| 通信 | 960×600・全画面130% | 450 | 25／84／7 | `after/network-narrow-true130` |
| 台帳 | 1920×1080・100% | 292 | 27／27／0 | `after/backup-wide` |
| 台帳 | 960×600・全画面130% | 292 | 27／27／10 | `after/backup-narrow-true130` |

上記フォルダの起点は `audit/visual-20261004/`。実行ログ・入力履歴・画像を保持した。詳細は `network-acceptance.md` と `after/backup-review.md`、通信の実行別ハッシュは `network-acceptance-evidence.json` に記録した。通信の最終狭幅03／07を開き、名前解決で停止した経路、未確認の管理遮断、復旧後の接続線と独立した管理遮断、実受注行が読めることを確認した。検査・設定・同じ業務への戻りを実Tab／Enterで操作し、保存、適用、再測定、実顧客データの参照、納品まで進めた。Save後は戻る操作へ逆Tabでも到達する。OS全体のフォーカス巡回を変更したという主張はしない。

台帳の最終狭幅04／06を開き、実際の50,000／62,800、保存先と版、復元先パス、3つの照合・保全状態が同時に読めることを確認した。壊れた最新版の復元成功と顧客照合失敗を区別し、旧版への実キーボード切替、原本変更予定の確認、保存失敗の巻き戻し、正しい復元、再読込、診断・検証・納品まで進めた。比較カードは実wheelで位置を合わせ、版選択への到達は別の実キーボード操作で確認した。

変更前との比較は、通信の `before/network-wide` と倍率を修正した `before/network-narrow-true130`、台帳の `before/backup-wide` と `before-corrected-scale/backup-narrow` を使う。修正した通信baselineは171 assertionsでPASS。台帳baselineは178 assertions中、選択パスの可視assertが1件失敗してexit 1となったため、変更前の表示限界を示す画像としてのみ扱う。変更前の製品は基準commitのまま、倍率を適用するタイミングだけを外部fixtureで直した。

通信試験は通常資金の初日の受注を公開APIで準備し、台帳試験は初期資金を維持して案件資格（peak_profit=35,000、operations=2）をfixtureで準備した。バックグラウンドの実時間進行は止め、実操作の工数・取引は残す。台帳の保存失敗だけは明示的な保存先エラーfixtureを使う。修復・比較・納品の操作はGodotの実入力イベントで行い、既知のnode名を使って対象を探す。

## 失敗・未採用証拠と制約

- 初期Backrest狭幅試験は187 assertionsが通った一方、実画像では金額Labelの幅が0だった。表示成功の証拠から除外し、幅の修正と実文字幅・カード内・viewport内の検査を追加した。
- 初期通信図には一文字ずつの折返し、図の高さを超えるノード、Save後のフォーカス消失があった。修正前の画像・ログを保持している。主要操作の再確認は実Tab／Enterを使い、内部signalの直接発火を操作の証拠にしない。
- 旧通信狭幅の「130%」はInterface外枠だけが130%、Desktopは100%だった。旧Backrest狭幅はアプリ130%、外枠100%だった。これらを全画面130%の証拠に数えず、GameとInterfaceの両方をassertするfixtureで取り直した。
- 全画面130%でガイドを再表示したBackrest比較ではguard下端が2px欠け、各6件のgeometry失敗を記録した。製品コードを変えず、実wheelで比較カードとguardを合わせるfixtureに修正した。全controlが初期viewportへ同時に入るという主張はしない。
- 比較画像はガイド表示条件を合わせる。ガイドを隠し、説明やraw詳細を開かずに進める操作経路とは分ける。ガイドを隠したことで増えた面積をUI改修の効果へ数えない。

今回の確認は既知の操作対象を使う自動実画面検証である。新しい初見ユーザーテスト、プレイヤーの理解速度や楽しさの実証、全案件・長期会社経営の再試験ではない。既存顧客アプリの編集・取引・他サービスとの接続は上記回帰で確認した。

## 会社進行の追加回帰

凍結した実装で既存の `test_ecosystem_journey.gd` をnative実行し、4日・4納品、入金後資金12,010、保存・再開までPASS・exit 0を確認した。207クリック、130キー、20wheel。設備の受取・配置は既存試験の公開API補助3操作を使うため、全経路をマウスだけで完了したという意味ではない。ログと実画像は `audit/visual-20261004/ecosystem-regression/`。script・parse・assert失敗はなく、環境のshader cache作成・証明書ストア警告が残る。
