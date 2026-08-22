# stable / preview 更新チャンネルの追加

## 目的

Zashikiの自動更新を、本番版とプレビュー版（ベータ版・RC版）で分離する。
本番利用者は安定版だけを受け取り、検証利用者はRCやベータ版を継続的に受け取れる
ようにする。Ghostty本家の`tip`（mainの各コミットから生成するnightly）は、現時点
では運用コストと必要性を考慮して対象外とする。

## 決定事項

- チャンネルは`stable`と`preview`の2つを用意する
- `preview`にはベータ版・RC版を含める
- ユーザー設定は次のいずれか1行だけを書く

  ```ini
  auto-update-channel = stable
  auto-update-channel = preview
  ```

- 設定がない場合は`stable`を既定値とする
- Sparkleのnative channel機能を利用する
- stable/previewを1つのappcast.xml内で管理する
- appcastはGitHub Pagesの固定URLで公開する
- リリース固有URLではなく、更新のたびに同じ固定URLのappcastを更新する
- `tip`用のnightly feedとGitHub Actionsの毎コミットビルドは今回実装しない

## 現状

- `AutoUpdateChannel`は現在`stable`と`tip`のみ
- `UpdateDelegate`は現在feed URLをチャンネルごとに切り替える
- `stable`はGitHub Releaseの`latest/download/appcast.xml`を参照する
- Sparkle native channelとGitHub Pages上の単一appcastは未実装
- 自動チェックは現在無効（`SUEnableAutomaticChecks=false`）であり、これは今回の
  チャンネル追加とは別に扱う

## 実装内容

### 1. 設定値を追加する

- Swiftの`AutoUpdateChannel`に`preview`を追加する
- Zig側の設定パーサーで`stable`/`preview`を受け付ける
- 未指定・不正値は`stable`へフォールバックする
- 設定ドキュメントまたは生成ヘルプに、各チャンネルの意味を記載する

### 2. 単一appcastとSparkle channelを導入する

- appcastの参照先をGitHub Pagesの固定URL（例:
  `https://kawaken.github.io/zashiki/appcast.xml`）に統一する
- 各`<item>`にstable/previewのchannelを付ける
- `allowedChannels`相当のdelegateで、stable利用者とpreview利用者の表示対象を分ける
- preview利用者にはstableも許可し、正式版リリース後に安定版へ移行できるようにする

### 3. Release workflowとGitHub Pagesを連携する

- 正式版とRC/betaのReleaseを同じappcastへ追加する
- GitHub ReleaseはRC/betaをPre-releaseのまま維持する
- appcast内の過去項目を保持し、Sparkleが更新比較できるようにする
- enclosureのダウンロードURLはGitHub Releaseの各リリースassetを指す
- `SPARKLE_PRIVATE_KEY`を使ったEdDSA署名を継続する
- ActionsからGitHub Pages（`gh-pages`またはPages用artifact）へappcastを公開する
- Pages公開に必要なActions権限と初回設定を整える

### 4. UI・説明を整える

- 設定ファイルで`stable`/`preview`を切り替えられることをヘルプに記載する
- READMEには詳細なリリース手順を追加せず、必要なら設定リファレンスやhelp
  subcommand側で説明する
- 設定変更後にfeedが切り替わることをテストする

## テスト・検証

- `stable`指定時にstable channelだけが表示される
- `preview`指定時にpreviewとstableが表示される
- 未指定・不正値がstableへフォールバックする
- GitHub Pagesの固定URLからappcastを取得できる
- stable/preview両方の項目に署名が付与され、Sparkleが読み込める
- RC2からRC3（またはbetaの次版）を手動チェックできる
- 正式版リリース後、preview利用者が正式版を更新候補として認識できる
- 既存のstable利用者がpreview版を誤って受け取らない

## 対象外・今後の検討

- `tip`/nightlyの毎コミットビルドと配布
- GitHub Releaseの`latest/download/appcast.xml`を更新feedとして使い続けること
- Developer ID署名・notarizationの導入（更新チャンネルとは独立したリリース基盤の課題）
- 設定画面からチャンネルを切り替えるUI（まずは設定ファイルで提供）

## 完了後

実装PRがmainへマージされたら、このプランを削除する。実装上の判断やworkflowの
差分に記録価値がある場合のみ、`docs/history/`へ短い履歴を残す。
