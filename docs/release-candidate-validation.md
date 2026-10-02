# UIと業務フローの改善・検証

受注した案件から顧客サービスを開き、通常利用、調査、修正、検証、顧客の結果、次の案件へ進む流れを整えた。既存の18段階の案内と変更前後の比較を使い、案内の追加で操作上の問題を隠さない。

## 主な変更

- Samba、Identity、診断では、操作した対象と返った内容・拒否結果を見える位置に表示する。Sambaの再試行は入力から実行ボタンまでを表示し、狭幅の設定ラベルも読める幅を確保する。
- ハンティングは原記録、ネットワーク調査は資源と応答、復旧は候補と本番の内容、検知はイベントと条件、APIは要求と応答、供給網は成果物と配布先を中心に操作する。
- 変更によって古くなった測定を、新しい不合格と区別する。納品結果は対象別の検証と実測応答を保存し、後日の環境変更から独立させる。
- 顧客の業務データは同じ正本へ反映する。保存失敗、権限拒否、競合では入力を保ち、誤った対応から実体を復元できる経路を残す。
- 既存の請求ポータル、認可された調査、インシデント対応の実装と接続し、収支・評価・請求明細も保持する。

## 検証結果

Godot 4.7.2、Windows x64で、2026-10-02に存在した119本の `game/tests/test_*.gd` を実行した。116本はheadlessで通過し、描画・実ポインタを必要とする3本は実描画で通過した。headlessでの非通過結果は描画試験と区別して保持した。

実OSポインタにアクセスできない制限環境では、`test_cursor_state.gd` と `test_workstation_monitor.gd` が座標を取得できない。デスクトップへのアクセスがある環境で同じソースを再実行し、実座標の一致を確認した。`test_title_scene.gd` は描画フレームを待つため、headlessだけでは完了しない。

全件実行後の最後の変更はSambaのラベル幅と再試行時の表示位置、それを確認するテストだった。影響する `test_samba_ui.gd`、`test_service_workflows.gd`、`test_samba_result_visibility.gd`、`test_release_journey.gd` の4本を再実行し、すべて通過した。

通常の初期資金から始めた実描画の通し試験では、会社作成、受注、顧客サービスの利用、UIからの保存と再開、修正、検証、納品、翌日の次の依頼まで到達した。1440×900と960×600・文字130%で確認し、完了フラグ・資金・スキル・正解設定を直接変更していない。

## 再実行例

リポジトリのルートから、インストール済みのGodotコマンドで実行する。

```sh
godot --headless --path game --script res://tests/test_specialist_models.gd -- --qa-profile=review-specialists
godot --headless --path game --script res://tests/test_journey_outcomes.gd -- --qa-profile=review-outcomes
godot --path game --script res://tests/test_release_journey.gd -- --qa-profile=review-journey
godot --path game --script res://tests/test_release_journey.gd -- --qa-profile=review-journey-narrow --narrow
```

描画が必要な試験はGUIを利用できる環境で実行する。QA profileを指定し、通常プレイのセーブと分ける。必要に応じて別の `APPDATA` を指定する。出力先を指定できる試験では `WHL_CAPTURE_DIR` を使う。

## 確認範囲

自動入力、モデル検証、実画面の確認は、人による初見の試遊とは異なる。全案件を人が完走した評価、楽しさ・学習効果、すべてのハードウェアでの互換性は今回の検証に含めていない。狭い画面で長い記録を読む際のスクロール、有限の教材データという制約も残る。
