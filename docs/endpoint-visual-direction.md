# EDR の造形と素材

## 白波フロント

ホテルの通常業務には、生成画像を背景に置く代わりに操作できる客室ラックと精算票を実装する。白い紙、温かい灰色の作業面、深い青緑の操作色を用い、EDRの端末・証拠マップと区別する。ドアと出発荷物をベクターで描画し、未送信・403・受領印・残高は保存状態から表示する。同梱Noto Sans JPの見出し・金額・補足の階層を使う。

構造の参照は[Cloudbedsの予約カレンダー](https://myfrontdesk.cloudbeds.com/hc/en-us/articles/48384262863771-Manage-reservations-from-the-New-Calendar)の客室と予約を保った詳細操作、および[Oracleのフロント業務](https://docs.oracle.com/en/industries/hospitality/opera-cloud/25.1/ocsuh/ch_front_desk.htm)の在室・出発・精算の分離。画面やブランド素材は転載せず、ゲーム内の架空ホテルと専用データで組み立てる。

## 端末と記録の調査

2026-10-06。業務接続 → 端末 → 通信記録を、操作できる対象として配置する。青い実線は現在の接続設定、切断記号は隔離、灰色の点線は過去の通信記録。画像自体には状態・文字・判定を焼き込まない。接続の測定、スキャン、ファイルの詳細はプレイヤーの操作で開く。

文字は既存同梱の Noto Sans JP を使い、本文14、補足12、見出し24を基本とする。平常・未測定は中立色、操作と選択は青、失敗は文字と記号を併用する。実サービスのブランドフォントは追加配布しない。

参照した一次資料:

- [Fluent 2 typography](https://fluent2.microsoft.design/typography): 文字の階層、本文と補足の大きさ。
- [Fluent 2 color](https://fluent2.microsoft.design/color): 中立色・操作色・状態色の使い分け。
- [Defender incident investigation](https://learn.microsoft.com/en-us/defender-endpoint/investigate-incidents): 端末と証拠を関係から調べる構造。
- [Defender device actions](https://learn.microsoft.com/en-us/defender-endpoint/respond-machine-alerts): 隔離・解除・調査と操作履歴。
- [Critical asset management](https://learn.microsoft.com/en-us/security-exposure-management/critical-asset-management): 端末の業務上の重要性を調査の文脈に含める考え方。ゲームの補償単価・顧客評価ルールは独自の架空契約であり、実サービスの機能や料金として扱わない。
- [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit): 無料モデルの公式 CC0 表記を確認。既存のオフィス素材と整合を検討するための参照。今回、新しいモデル一式は追加していない。

## 保存記録の調査マップ

通常の調査案件は、端末・記録中のプロセス名・送信/DNS/ファイル参照を列で結ぶ。プロセス名と発行元が同じ記録をまとめるが、実プロセスの同一性や現在の稼働を表さない。線はすべて過去の記録を示す点線で、隔離しても消さない。現在の設定は端末の「○ 接続許可 / × 隔離」で別に示す。ファイル参照のアドレスは「関連先」とし、送信したと断定しない。

端末の図を押すと操作へ、記録の図を押すと元のイベント詳細へ進む。検索やグループ化後も元のイベント添字を使う。詳細から比較と端末操作へ戻れる。復旧案件には業務マップと記録比較の両方を用意し、同じ保存状態を参照する。小画面・文字拡大では列を維持して縦にスクロールし、記録の名称・時刻・発行元を省略しない。従来の詳細末尾にあった重複したカード列は削除した。

## 組み込んだ生成画像

ファイル: `game/assets/ui/endpoint/workstation-v1.png`。Codex の組み込み画像生成で作成した透明背景の端末。ローカルな別サービス、追加APIキー、有料外部サービスは使用していない。素材の加工は行わず、Godotの表示サイズで縮小する。生成物を CC0 素材として扱わない。

生成時の最終プロンプト:

> Use case: stylized-concept. Asset type: a reusable transparent game UI hardware sprite for White Hat Lab, a professional fictional security-company simulator. Create one premium semi-realistic isometric desktop workstation: a slim dark graphite monitor with a quiet blank deep navy screen, compact dark graphite computer tower, pale gray keyboard and mouse. The whole workstation is one centered isolated object, view from slightly above at a 3/4 angle, front of monitor facing the viewer. Refined hard-surface construction, precise bevels, restrained industrial design, clean studio lighting with subtle blue reflection. Crisp readable silhouette when reduced to 100 pixels. Actual transparent background, no ground plane, no environment, no table, no opaque shadow rectangle. Keep every object fully inside the image with 12 percent empty margin. No text, no logo, no label, no security badge, no baked-in status indicator, no rounded UI panel, no border. The image will be used as an interactive device object, with separate code-rendered status and connections.
