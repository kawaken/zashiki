# Markdownプレビューペイン実装計画（Zashikiフォーク）

## 作業状況

- **作業ブランチ**: `markdown-preview`（`kawaken/zashiki`、`main`から派生）
- **PR**: [#12](https://github.com/kawaken/zashiki/pull/12)（`main`向け、未マージ）
- 別環境でこの続きをやる場合は、まず`git fetch origin` → `git checkout markdown-preview`（無ければ`git checkout -b markdown-preview origin/markdown-preview`）でこのブランチの内容を取得すること。`main`のままだとStep 1・2の実装が一切乗っていない
- 現在地: Step 1・2・3はコード実装完了・`zig build`/`zig build test`成功確認済みだが、**画面上の動作確認は未実施**（作業した開発環境にGUI表示アクセスがない、`screencapture`失敗を確認済み）。次はStep 4（URLスキーム受け口）だが、着手前にStep 1〜3の実機確認（`zig build`してCmd+Shift+M・ファイル書き換えのライブ反映等を試す）をおすすめする

## Context

ターミナルに「Claude.aiのアーティファクト」のようなMarkdownビューワーを組み込みたい。Claude Code（定額）がmdファイルを書き、ターミナル側は表示だけを担うのでAPI従量課金は発生しない。このフォークはmainが独自開発ラインで、方針は「追加中心・既存APIシグネチャ変更なし・upstreamマージ競合最小化」。**Zigコアには手を入れず、Swift側のみで完結させる。**

要件:

- ターミナルウィンドウ右側にMarkdownプレビューペインを表示（トグル可能）
- CLIから独自URLスキーム（`zashiki://`）経由でファイルを開ける（薄いシェルラッパー付き）
- 表示中ファイルのライブ更新（Claude Codeの書き換えに追従、atomic save対応）
- レンダリングはSwiftUIネイティブ（[Textual](https://github.com/gonzalezreal/textual)ライブラリ）。WebKit/HTML/CSS/DOMを一切使わない（外部通信なし、攻撃対象面を最小化）

調査で確認済みの根拠:

- **前例**: Terminal Inspector（`macos/Sources/Ghostty/Surface View/InspectorView.swift` の `InspectableSurface`）が「if/elseで `SplitView` の片側に別ビューを並べる」同型パターン。`SplitView<L,R>`（`macos/Sources/Features/Splits/SplitView.swift`）は汎用でドラッグディバイダ付き
- `AppDelegate.swift`（`macos/Sources/App/macOS/AppDelegate.swift`）には既に `func application(_ sender: NSApplication, openFile filename: String) -> Bool`（L448〜）というレガシーなファイルオープンの受け口がある。これを見本に、URLスキーム受け口として新しく `func application(_ application: NSApplication, open urls: [URL])` を追加する（後述）
- `Sources/` はPBXFileSystemSynchronizedRootGroupなのでSwiftファイルは置くだけでターゲットに入る（Ghostty-iOSのmembershipExceptionsへの除外追記は必要、`project.pbxproj`のメカニズムは健在）
- SPMのリモートパッケージ追加は`Sparkle`で既に前例あり（`project.pbxproj`に`XCRemoteSwiftPackageReference`が既存）。`Textual`追加もこのパターンを踏襲できる

### 命名方針（2026-08-08のリネーム作業を踏まえて追記）

アプリ名は Ghostty → **Zashiki** にリネーム済み（`dev.kawaken.zashiki`、Swiftモジュール名は`PRODUCT_MODULE_NAME`指定により内部的に`Ghostty`のまま維持）。今回の新規実装ではこのフォーク独自の新規機能名にはZashiki側の命名を使う（CLIラッパーのファイル名・環境変数名）。`scripts/ghostty-md-preview` → `scripts/zashiki-md-preview`、`GHOSTTY_APP` → `ZASHIKI_APP`。ビルド成果物は `Zashiki.app`（`Ghostty.app`ではない）。検証コマンド例もこれに合わせて更新済み

### トリガー方式の方針転換（2026-08-10）

当初案（本家由来のAppleScriptサポートに `preview markdown`/`close markdown preview` コマンドを追加する）から方針転換。理由:

- 本家のAppleScript連携機構（`macos/Sources/Features/AppleScript/`）自体を将来的に丸ごと削除したいと考えており、新機能をその上に積み増したくない（AppleScript削除自体は別タスクとして`plan/remove-applescript.md`に切り出す想定・現時点では未着手）
- CLIから直接操作できれば十分で、`osascript`を経由する必然性がない
- ウォッチ機能（開いているファイルの監視・ライブ更新）は従来通り維持する。トリガー方式の変更が影響するのは「外部から開かせる入口」だけ

代わりに、独自URLスキーム `zashiki://` をCFBundleURLTypesに登録し、`open "zashiki://..."` から起動・操作できるようにする。

### ビルド/エコシステム表記の方針（2026-08-10）

Swiftモジュール名（`PRODUCT_MODULE_NAME = Ghostty`）等の**コード内部の表記**はライブラリ利用に近いものとして許容する一方、**ビルドコマンド・スキーム名などビルド/エコシステム面での`Ghostty`表記は避ける**方針とした。この方針に基づき、Step 1の作業中に見つかった以下の対応を実施済み:

- 共有Xcodeスキームファイル `Ghostty.xcscheme` → `Zashiki.xcscheme` にリネーム（スキーム内部の`BlueprintName`は元々`Zashiki`を指していたが、ファイル名＝`xcodebuild -scheme`で指定する名前だけが古いままだった）
- macOSアプリ専用のビルドロジックファイル `src/build/GhosttyXcodebuild.zig` → `src/build/ZashikiXcodebuild.zig` にリネーム（`build.zig`・`src/build/main.zig`の参照も追従。`GhosttyDocs.zig`等クロスプラットフォーム共通のビルドファイル群は対象外）
- 冗長だった`macos/build.nu`（nushell依存、`zig build`と並行するmacOS専用ビルド経路）を削除し、`zig build`一本に統一（詳細は下記リスク欄）
- `macos/AGENTS.md`のビルド手順・出力パス例を`Ghostty.app` → `Zashiki.app`に更新、`zig build`ベースの手順に書き換え

### レンダリング方式の方針転換（2026-08-10）

当初案（WKWebView + 同梱markdown-it/highlight.js）から、SwiftUIネイティブレンダリング（`Textual`ライブラリ）に転換。

**転換の経緯**: 「JSライブラリのvendoringはセキュリティリスクを一気に上げるのでは」という指摘を受けて再検討。WKWebView案はvendorされたJS（markdown-it・highlight.js）自体のサプライチェーンリスクに加え、WebKitというHTML/CSS/DOM/ナビゲーションを含む巨大なレンダリングエンジンをアプリに持ち込むことになる（このアプリはApp Sandbox無効のため影響範囲も大きい）。代替のSwiftネイティブ選択肢を調査した:

| ライブラリ                                                                          | 用途                                                 | 調査結果                                                                                                                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [swift-markdown-ui (MarkdownUI)](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown→SwiftUI View直接描画                        | MIT、macOS 12+、GFMテーブル対応、`swift-cmark`（Apple/swiftlang公式）ベース。**maintenance mode**（新規開発は後継の`Textual`へ移行済み）                                                                                                                                                                                                                   |
| [Textual](https://github.com/gonzalezreal/textual)（MarkdownUIの後継、採用）        | 同上                                                 | MIT、829 stars。`StructuredText(markdown:baseURL:)` というSwiftUI Viewで直接描画。GFMテーブル・組み込みGitHubテーマ（`.textual.structuredTextStyle(.gitHub)`）・コードシンタックスハイライト対応。**ただし macOS 15+ 必須**（`Package.swift`の`platforms`より）。バージョンはまだ0.x系（初タグ2025-12-27、最新0.5.0が2026-06-15）でAPI破壊的変更の余地あり |
| [HighlightSwift](https://github.com/appstefan/HighlightSwift)                       | コードシンタックスハイライト（比較検討のみ、不採用） | highlight.jsをJavaScriptCore（WebKitではない）で実行。Textual採用によりTextual内蔵のハイライタ（`Internal/Highlighter`、Prism.jsベースと推測、同じくJavaScriptCore経由）で足りるため今回は使わない                                                                                                                                                         |

**Textualを採用した理由**:

- MarkdownUIより新しいこと自体は理由ではなく、**ユーザーが常に最新macOSを使う前提**のためmacOS 15+要求はデメリットにならないと判断（2026-08-10確認）
- MarkdownUIは「maintenance mode」＝新機能は追加されない。今から採用するライブラリとしては後継のTextualの方が妥当
- WKWebViewを完全に排除でき、JSが実行される場所もJavaScriptCore（DOM・ナビゲーション・ネットワークスタックを持たない、狭いサンドボックス）に限定される

**この転換に伴う波及的な決定**:

- **macOSデプロイターゲットをmacOS 15.0（Sequoia）に引き上げる**（現状はZashiki関連ターゲットが13.0/13.1、一部ターゲット--おそらくWidget/AppIntents系--は既に15.5）。ユーザー確認済み（2026-08-10）。フロア決定の根拠: 2026-08-10時点の現行macOSは**26 Tahoe**（26.6、2026-07-27リリース）。WWDC 2025でOSバージョン番号がリリース年基準に統一され、Sequoia(15)の次がTahoe(26)になった（16〜25は欠番、iOS/iPadOS等も同時に統一）ため、実際の系譜は 13 Ventura → 14 Sonoma → 15 Sequoia → 26 Tahoe → 27 Golden Gate(2026年9月予定)。ユーザーの「直近2バージョンくらいで十分」という方針のうち、**現行の1つ前であるmacOS 15 Sequoiaをフロアとすることで確定**（Textualの要求macOS 15+とも一致）。CIランナーは既に`macos-15`なので追加対応不要
- 画像読み込み（`AttachmentLoader`）はデフォルトでリモートURLをfetchしうる実装（`URLAttachmentLoader` → `ImageLoader.shared.image(for:)`）なので、**`file://`スキームのみ許可する独自`AttachmentLoader`を実装する**必要がある（「外部通信なし」要件を満たすため。✅ `MarkdownPreviewImageLoader.swift`として実装済み、Step 2）
- markdown-it/highlight.js/github-markdown-cssのvendoring（`macos/MarkdownPreviewWeb/`）は不要になったため削除済み

## アーキテクチャ

```
BaseTerminalController
 └─ let markdownPreview = MarkdownPreviewModel()   ← 状態源（ウィンドウ単位）
TerminalView.body (.readyケース)
 └─ MarkdownPreviewSplit { 既存ZStack }             ← 非表示時は素通し
     └─ SplitView(.horizontal, left: 既存, right: MarkdownPreviewPane)
         └─ StructuredText(markdown: content, baseURL: ...)   ← Textual、SwiftUIネイティブ
             .textual.structuredTextStyle(.gitHub)
             .textual.imageAttachmentLoader(MarkdownPreviewImageLoader())  ← file://のみ許可
MarkdownPreviewFileWatcher (DispatchSourceFileSystemObject)          ← ✅実装済み
 └─ write/extend → 80msデバウンスで再読込
 └─ delete/rename → ソース破棄→再アーム（atomic save対応、リトライ付き）
```

- コンテンツ受け渡し: `MarkdownPreviewModel`の`@Published var content: String`をそのまま`StructuredText(markdown:)`に渡すだけ（実装済み）。WKWebView時代の`evaluateJavaScript`のような明示的なブリッジは不要（SwiftUIの差分更新に任せる）
- スクロール位置維持: `StructuredText`はSwiftUIネイティブViewなので、内容差し替え時のスクロール位置維持はSwiftUI標準の挙動に依存する（`ScrollView`でラップする場合は`ScrollViewReader`等で明示制御が必要になる可能性がある。**未検証**——開発環境にGUI表示アクセスがなく、ユーザーの実機確認待ち）
- ダークモード: SwiftUIが自動追従する想定（`.textual.structuredTextStyle(.gitHub)`がダーク/ライト両対応のテーマを提供する想定）。**未検証**——Step 1のテストビューは画面表示まで至らず削除済み、Step 2でも同様の理由で未確認
- リンククリック: `StructuredText`が生成する`Text`のリンクは標準で`NSWorkspace`に委譲される想定。**未検証**（委譲されない場合は環境値経由でハンドラを差し込む）
- QuickTerminalも継承で機構的に動くが未調整扱い（問題が出たらメニューvalidateで無効化）

## 変更・新規ファイル

### 新規: `macos/Sources/Features/Markdown Preview/`（5ファイル、✅実装済み・2026-08-11）

| ファイル                           | 責務                                                                                                                                                                                                                                                                                                                                            |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MarkdownPreviewModel.swift`       | ✅ ObservableObject。`isVisible`/`fileURL`/`content`/`revision`/`errorMessage`。`open(url:)`/`reload()`/`toggle()`/`close()`。`open(url:)`が`MarkdownPreviewFileWatcher`を起動し自動検知を配線済み（Step 3）                                                                                                                                    |
| `MarkdownPreviewFileWatcher.swift` | ✅ `DispatchSourceFileSystemObject`ラッパー。write/extendは80msデバウンスして`onChange`（`reload()`）を呼ぶ。delete/rename（atomic saveでfdが無効化された場合含む）はsourceを破棄し即座に`onChange`を呼んでから100ms間隔で再アームをリトライし続け、ファイルが復活したら`onChange`で復帰。表示/非表示に関わらずwatchingを継続する                                                                                                          |
| `MarkdownPreviewSplit.swift`       | ✅ `isVisible`で `SplitView(.horizontal)` に包むか素通しか切替（InspectorViewのif/elseパターンを踏襲）                                                                                                                                                                                                                                          |
| `MarkdownPreviewPane.swift`        | ✅ ヘッダ（ファイル名・閉じる）+ `StructuredText` + 空/エラー状態。空状態に「Open File...」ボタン（NSOpenPanel）                                                                                                                                                                                                                                |
| `MarkdownPreviewImageLoader.swift` | ✅ `Textual`の`AttachmentLoader`プロトコル実装。`file://`スキーム以外はロードを`throw`で拒否（`WithAttachments`内部で`try?`により静かに無視される＝該当箇所は画像なしでレンダリング継続、明示的なプレースホルダ画像は出さない）。Textual内部の非公開`Attachment`型に依存せず、`Image`/`CGSize`/`String`のみで構成した自前の`Attachment`型を使用 |

### 既存ファイルへの変更（最小差分）

| ファイル                                                       | 変更                                                                                                                                                                                                                                                                                                                                 |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `macos/Sources/Features/Terminal/TerminalView.swift`           | ✅ `TerminalViewModel` に `var markdownPreview: MarkdownPreviewModel { get }` 追加。`.ready` の既存ZStackを `MarkdownPreviewSplit` で包み、`.frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)` は `MarkdownPreviewSplit` 側に移動                                                                      |
| `macos/Sources/Features/Terminal/BaseTerminalController.swift` | ✅ `let markdownPreview = MarkdownPreviewModel()` + `@IBAction func toggleMarkdownPreview(_:)`（非表示化時 `Ghostty.moveFocus(to: focusedSurface)`）                                                                                                                                                                                 |
| `macos/Sources/App/macOS/MainMenu.xib`                         | ✅ Viewメニュー（Command Palette項目の後）に「Toggle Markdown Preview」Cmd+Shift+M、`target="-1"`（First Responder）で `toggleMarkdownPreview:`                                                                                                                                                                                      |
| `macos/Ghostty-Info.plist`                                     | 未実装（Step 4）。`CFBundleURLTypes` を新規追加。`CFBundleURLSchemes = ["zashiki"]`、`CFBundleURLName = "dev.kawaken.zashiki"`、`CFBundleTypeRole = Viewer`。既存の`UTExportedTypeDeclarations`と同じ場所・書式に倣う                                                                                                                |
| `macos/Sources/App/macOS/AppDelegate.swift`                    | 未実装（Step 4）。`func application(_ application: NSApplication, open urls: [URL])` を新規追加（既存の`application(_:openFile:)`の直後が自然）。`zashiki://markdown-preview/open?path=...`をパース → パス検証 → frontmost `TerminalController`解決 → `controller.markdownPreview.open(url:)`。未対応ホスト/不正パスはログのみで無視 |
| `macos/Ghostty.xcodeproj/project.pbxproj`                      | ✅ ①`Textual`のSPMリモートパッケージ参照（Step 1で追加済み）②Zashiki関連ターゲットの`MACOSX_DEPLOYMENT_TARGET`を13.0/13.1→15.0（Step 1で実施済み）③Ghostty-iOSの`membershipExceptions`にMarkdown Preview配下の新規Swift 4ファイルを追記（Step 2で実施済み）                                                                          |

### 新規: URLスキームCLIラッパー

`zashiki://`のURL形式: `zashiki://markdown-preview/open?path=<パーセントエンコードした絶対パス>`

| ファイル                     | 内容                                                                                                                                                                                                                                                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `scripts/zashiki-md-preview` | 相対パスを絶対化 → パーセントエンコード → `ZASHIKI_APP`環境変数があれば `open -a "$ZASHIKI_APP" "zashiki://markdown-preview/open?path=$ENCODED"`（Debugビルドを名指しで起動、既定ハンドラの登録状況に依存しない）、なければ `open "zashiki://..."`（システム既定ハンドラ、通常は`/Applications`のRelease版） |

## 実装ステップ（段階的に動作確認）

1. **SPMパッケージ追加 + デプロイターゲット引き上げ + 試験表示**（✅完了、2026-08-10）
   `Textual`をpbxprojに追加、Zashiki関連ターゲットのデプロイターゲットをmacOS 15.0に引き上げ。検証用の一時ビュー（`MarkdownPreviewSmokeTestView.swift`）で`StructuredText(markdown:)`のコンパイル・リンクを確認後、Step 2実装時に削除済み
   検証: `zig build`（フルアプリビルド）でBUILD SUCCEEDED、`Zashiki.app/Contents/Resources/`に`textual_Textual.bundle`/`swiftui-math_SwiftUIMath.bundle`が同梱されることを確認済み。`zig build test -Demit-macos-app=false`（CIと同一コマンド）も実機確認済み（3095/3111件成功・16件スキップ・失敗0件）
2. **Model + ペインUI + TerminalView統合 + メニュー**（watcher以外、✅コード実装完了、2026-08-11）
   `MarkdownPreviewModel`/`MarkdownPreviewSplit`/`MarkdownPreviewPane`/`MarkdownPreviewImageLoader`の4ファイルを実装。`TerminalViewModel`に`markdownPreview`追加、`BaseTerminalController`に`markdownPreview`プロパティと`toggleMarkdownPreview(_:)`、`MainMenu.xib`に「Toggle Markdown Preview」（Cmd+Shift+M）を追加
   検証: `zig build`でBUILD SUCCEEDED（400/400ステップ）、コンパイルエラー・SwiftLint警告なし。**画面上での動作確認（トグル・Open File...・ディバイダドラッグ・シェルセッション生存・スクロール位置維持・リンク委譲）は未実施**——この開発環境（サンドボックス）にはGUI表示アクセスがなく（`screencapture`が"could not create image from display"で失敗）、アプリ自体は正常起動・終了できることは確認したが画面は見れない。ユーザー自身の実機での確認が必要
3. **ライブ更新（watcher）**（✅コード実装完了、2026-08-11）
   `MarkdownPreviewFileWatcher`を実装し、`MarkdownPreviewModel.open(url:)`から起動するよう配線。
   検証: `zig build`（フルアプリビルド）でBUILD SUCCEEDED、`zig build test -Demit-macos-app=false`（CIと同一コマンド）も実機確認済み（221件成功・1件スキップ・失敗0件。1回目の実行はplan記載済みの既知フレーキーさでテストが空振りしたため2回目で確認）。コンパイルエラー・SwiftLint警告なし
   (a) `>>` 追記 (b) vimの`:w`（atomic save） (c) Claude Codeによる書き換え (d) `mv` でのrename上書き → 1秒以内に再描画・スクロール維持。(e) 削除→エラー表示→再作成で復帰 — **いずれも未実施**（Step 2と同じ理由でこの開発環境にはGUI表示アクセスがなく、`screencapture`も失敗する。ユーザー自身の実機での確認が必要）
4. **URLスキーム受け口 + シェルラッパー**
   検証（アプリは絶対パス指定）:
   `open -a <abs>/macos/build/Debug/Zashiki.app "zashiki://markdown-preview/open?path=/tmp/test.md"` でDebugビルドへ直接配送されること
   `ZASHIKI_APP=<abs>/macos/build/Debug/Zashiki.app scripts/zashiki-md-preview README.md`
   まず `application(_:open:)` が `CFBundleURLTypes` 登録だけでカスタムスキームに対して実際に呼ばれるか確認（呼ばれない場合は`applicationWillFinishLaunching`で`NSAppleEventManager`に`kInternetEventClass`/`kAEGetURL`の明示ハンドラを登録するフォールバックに切り替える。この点は未検証のため要注意）
   エラーパス（存在しないファイル、ウィンドウなし、不正なpath）も確認
5. **仕上げ**: `swiftlint lint --strict --fix` → フルビルド `zig build -Doptimize=ReleaseFast -Dxcframework-target=native` → `zig build test`（新規SwiftファイルがCIのlint/testに引っかからないか確認）→ ビルドした`Zashiki.app`を`/Applications`に配備 → Claude Codeにmdを書かせて実運用確認 → 本plan文書に最終的な使い方・動作確認手順・依存ライブラリ出典・upstream競合注意・デプロイターゲット引き上げの記録を追記（変更ファイル表等は各Stepの実装時に随時更新済み）→ コミット

## 主要リスクと対処

- **pbxproj手編集**: ID重複に注意（24桁hexを新規採番）。`zig build`の成否で即検出。2026-08-08時点でpbxprojはリネーム・アイコン差し替え・TEST_HOST修正等で何度も手編集済みなので、既存の「変更前1行が唯一であることをassertしてから置換する」スクリプト方式を踏襲する。SPMパッケージ参照（`XCRemoteSwiftPackageReference`/`XCSwiftPackageProductDependency`）の追加も`Sparkle`の既存エントリを雛形にすれば同じ方式で問題なく追加できた（2026-08-10実施）
- **（解決済み）`xcodebuild -target`は推移的SPM依存を解決できない**: `Textual`は`SwiftUIMath`/`ConcurrencyExtras`という2つの依存パッケージを持つ（`Sparkle`は依存ゼロの単独パッケージだったため今まで問題にならなかった）。Xcode 26の「Explicitly Built Modules」機構が推移的パッケージ依存を伴うビルド計画を`-target`単体指定では正しく組み立てられない既知の不具合（[Swift Forums](https://forums.swift.org/t/xcode-26-unable-to-find-module-dependency/80516)参照）に該当し、`unable to resolve module dependency`で失敗した。`-scheme`指定（ワークスペース全体の計画を使う）に切り替えると解決することを確認。**upstream本家は同じ`-target`方式のままなので、この変更はupstreamとの差分になる**（本家は依存ゼロのSparkleしか使っていないため今後も問題化しない見込み）
- **（解決済み）ビルドシステムの二重化とSYMROOT問題（2026-08-10）**: `zig build`（ルート`CLAUDE.md`が案内する本来のビルド方法）とは別に、macOS専用の`macos/build.nu`（要nushell）がビルド出力先を明示指定するためだけに存在していた。`zig build`側は出力先（`SYMROOT`）を指定しておらず、各マシンのXcode設定（DerivedData/レガシーどちらがデフォルトか）に依存する隠れた環境差があった。素の環境やCIランナーではDerivedData側に倒れ、`zig build`の「アプリをコピーする」ステップが空振りする潜在バグがあった。対応として`src/build/GhosttyXcodebuild.zig`を`src/build/ZashikiXcodebuild.zig`にリネームした上で、`build`/`xctest`両ステップに絶対パスの`SYMROOT`（`b.pathFromRoot("macos/build")`）を明示指定し、`macos/build.nu`を削除して`zig build`一本に統一した。**相対パスのSYMROOTだとSPMパッケージのモジュール解決が壊れる（`-target`問題と同種の症状が再発する）ことが分かったため、必ず絶対パスで指定する**必要がある。`zig build`（フルアプリビルド）・`zig build test -Demit-macos-app=false`（CIと同一コマンド、xcodebuild test含む）の両方で実機確認済み（後者は3095/3111件成功・16件スキップ・失敗0件）
- **Textualが0.x系**: 初タグから半年程度でAPIが安定していない可能性がある。`Package.resolved`でバージョンを固定し、更新時は差分を確認する
- **デプロイターゲット引き上げの影響範囲**: macOS 13.0/13.1→15.0に上げると、それ未満のmacOSでは起動不可になる。個人利用前提のため許容（ユーザー確認済み、2026-08-10）
- **（解決済み）画像ローダーのネットワーク制限**: `Textual`のデフォルト`AttachmentLoader`はリモートURLをfetchしうる実装だったため、`MarkdownPreviewImageLoader`で`file://`スキーム以外を`throw`で拒否する独自実装を追加した（2026-08-11実装）
- **（未検証・要実機確認）SwiftUI構造切替によるサーフェス再アタッチ**: Inspector前例ありだが横分割+全体ラップは新パターン。コードは実装済みだが、この開発環境にGUI表示アクセスがなく（`screencapture`失敗）セッション生存確認ができていない。ユーザーの実機確認が必要
- **（未検証・要実機確認）StructuredTextのスクロール位置維持・リンク委譲の挙動**: WKWebView時代は`evaluateJavaScript`や`decidePolicyFor`で明示制御していたが、Textual採用によりSwiftUI標準の挙動に依存する部分が増えた。上記と同じ理由で未確認
- **configキーバインド連携は不可**（`syncMenuShortcut` はZigコアのアクション名前提）→ xibの静的Cmd+Shift+Mで代替。制約は本plan文書に明記（このセクション）
- **ウィンドウサイズ**: デフォルト非表示なので初期サイズ算出に影響なし。表示時はウィンドウ幅維持でターミナルが縮む（Inspectorと同挙動）。自動拡幅はv2候補
- **URLスキームの既定ハンドラ**: 同じ`dev.kawaken.zashiki`系Bundle IDのDebug/Release両方を並行して使う場合、`zashiki://`スキームの既定ハンドラは片方にしかならない（LSHandlerRankの仕様）。`open -a`で明示的にアプリを指定すれば既定ハンドラに関係なく届くため、`scripts/zashiki-md-preview`は`ZASHIKI_APP`未指定時のみ既定ハンドラ（`open`のみ）に頼る設計とする
- **`application(_:open:)`がカスタムURLスキームに対して実際に発火するかは未検証**: ファイルオープン（Documentタイプ）での実績はあるが、`CFBundleURLTypes`経由のGetURL Apple Eventで同じデリゲートメソッドが呼ばれるかはStep 4で確認するまで確定情報ではない。発火しない場合は`NSAppleEventManager`への明示ハンドラ登録に切り替える
- **CI**: 新規Swiftファイルは`zig build test`（`GhosttyTests`）と`swiftlint lint --strict`の対象になる。CIランナーは既に`macos-15`なのでデプロイターゲット引き上げによる追加対応は不要。`MarkdownPreviewFileWatcher`のデバウンスロジック等ロジック部分は簡単な単体テストを足す余地がある（必須ではない）

## 検証（全体）

Step 1〜4の各検証に加え、最終的に:

1. `/Applications` 配備後、実際のClaude Codeセッションでmdを書かせながら `zashiki-md-preview` で開き、ライブ更新を確認
2. システム外観のライト/ダーク切替でプレビューが追従
3. upstream由来の既存機能（スプリット、タブ、Inspector、Command Palette）が無事なこと
4. `zig build test` と `swiftlint lint --strict` がCI上でも通ること
