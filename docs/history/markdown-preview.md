# Markdownプレビューペイン実装

- **実施PR**: [#12](https://github.com/kawaken/zashiki/pull/12)（2026-08-11マージ）
- **元プラン**: `plan/markdown-preview.md`（削除済み、このドキュメントに統合）

## 目的

ターミナルウィンドウ右側にMarkdownプレビューペインを表示する機能。Claude Code
が書いたmdファイルを、外部通信なしでライブプレビューできるようにする。

## Planとの差分（方針転換）

- **レンダリング方式**: 当初案はWKWebView + 同梱markdown-it/highlight.jsだったが、
  「vendoringされたJSのサプライチェーンリスク」を指摘され再検討。WebKit（DOM・
  ナビゲーション・ネットワークスタックを含む大きなレンダリングエンジン）を
  持ち込まない方針に転換し、SwiftUIネイティブの`Textual`ライブラリを採用。
  この転換に伴い、macOSデプロイターゲットを13.0/13.1→15.0（Sequoia）に
  引き上げる波及があった。
- **トリガー方式**: 当初案は本家由来のAppleScriptサポートに`preview markdown`
  コマンドを追加する方式だったが、AppleScript連携機構自体を将来削除したいと
  いう方針と衝突するため転換。独自URLスキーム`zashiki://`をCFBundleURLTypes
  に登録し、`open`コマンド経由で操作する方式にした。
- **ビルドシステム**: 実装中に、`zig build`と並行して存在していたmacOS専用の
  `macos/build.nu`（nushell依存）がビルド出力先（SYMROOT）を暗黙に固定して
  いるだけの重複経路だと判明。`zig build`側にSYMROOTを明示指定した上で
  `build.nu`を削除し、`zig build`一本に統一した（Planのスコープ外だったが
  作業中に発見・対応）。
- **`xcodebuild`のビルド単位**: `Textual`が推移的SPM依存（`SwiftUIMath`/
  `ConcurrencyExtras`）を持つため、Planでは想定していなかった
  `unable to resolve module dependency`エラーに遭遇。`-target`単体指定から
  `-scheme`指定に切り替えて解決した。

## 実機未検証のまま完了扱いになった項目

開発環境にGUI表示アクセスがなく（`screencapture`失敗、Accessibility権限も
なし）、Planの「検証（全体）」に挙げていた以下の画面上での確認は、コード実装
完了・CI通過の確認のみでマージに至った:

- トグル・ディバイダドラッグ・ダークモード追従
- ライブ更新（追記・atomic save・削除→復帰）の実際の見た目
- `StructuredText`のスクロール位置維持・リンククリックの委譲挙動
- URLスキーム経由でのプレビューペイン起動の見た目（ログ上は成功パスを確認
  したのみ）
- `/Applications`への実配備・実運用確認

## マージ後の変更（2026-08-13）

CIレビューで「`scripts/zashiki-md-preview`が`AppDelegate.swift`から参照されて
いるのに`paths-ignore`の`scripts/**`でCIスキップ対象になっている」との指摘を
受けたが、調査の結果`AppDelegate.swift`側はdocコメントでファイル名に言及して
いるだけでビルドには一切組み込まれていなかった（`xcodeproj`にも`zig build`にも
非依存）。Markdownプレビュー機能自体はアプリ本体の`zashiki://`URLスキームで
完結しており、`scripts/zashiki-md-preview`はパス絶対化+URLエンコードのみを
行う薄いラッパーに過ぎず必要性が薄いと判断し削除。CLIから開く場合は直接
`open "zashiki://markdown-preview/open?path=<percent-encoded absolute path>"`
を使う。これに伴い`paths-ignore`の`scripts/**`エントリも削除。

## 関連コミット

- `8d65532b3` Step1(Textual導入)
- `4a887559a` Step2(Model+ペインUI+TerminalView統合)
- `379e0025c` Step3(ファイル監視・ライブ更新)
- `676079689` Step4(URLスキーム受け口+シェルラッパー)
- `b3269111d` Merge pull request #12
