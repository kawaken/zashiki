# Markdownプレビューペイン実装計画（Zashikiフォーク）

## Context

ターミナルに「Claude.aiのアーティファクト」のようなMarkdownビューワーを組み込みたい。Claude Code（定額）がmdファイルを書き、ターミナル側は表示だけを担うのでAPI従量課金は発生しない。このフォークはmainが独自開発ライン（LOCAL_PATCH.md参照）であり、方針は「追加中心・既存APIシグネチャ変更なし・upstreamマージ競合最小化」。**Zigコアには手を入れず、Swift側のみで完結させる。**

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

- **macOSデプロイターゲットをmacOS 15.0に引き上げる**（現状はZashiki関連ターゲットが13.0/13.1、一部ターゲット--おそらくWidget/AppIntents系--は既に15.5）。ユーザー確認済み（2026-08-10「基本新しいので良いよ。OSX13とか古すぎるやろ」）。CIランナーは既に`macos-15`なので追加対応不要
- 画像読み込み（`AttachmentLoader`）はデフォルトでリモートURLをfetchしうる実装（`URLAttachmentLoader` → `ImageLoader.shared.image(for:)`）なので、**`file://`スキームのみ許可する独自`AttachmentLoader`を実装する**必要がある（「外部通信なし」要件を満たすため。未実装、要検証）
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
MarkdownPreviewFileWatcher (DispatchSourceFileSystemObject)
 └─ write/extend → 80msデバウンスで再読込
 └─ delete/rename → ソース破棄→再アーム（atomic save対応、リトライ付き）
```

- コンテンツ受け渡し: `MarkdownPreviewModel`の`@Published var content: String`をそのまま`StructuredText(markdown:)`に渡すだけ。WKWebView時代の`evaluateJavaScript`のような明示的なブリッジは不要（SwiftUIの差分更新に任せる）
- スクロール位置維持: `StructuredText`はSwiftUIネイティブViewなので、内容差し替え時のスクロール位置維持はSwiftUI標準の挙動に依存する（`ScrollView`でラップする場合は`ScrollViewReader`等で明示制御が必要になる可能性があり、Step 2で要検証）
- ダークモード: SwiftUIが自動追従（`.textual.structuredTextStyle(.gitHub)`がダーク/ライト両対応のテーマを提供する想定、Step 1で確認）
- リンククリック: `StructuredText`が生成する`Text`のリンクは標準で`NSWorkspace`に委譲される想定（Step 2で要検証。委譲されない場合は環境値経由でハンドラを差し込む）
- QuickTerminalも継承で機構的に動くが未調整扱い（問題が出たらメニューvalidateで無効化）

## 変更・新規ファイル

### 新規: `macos/Sources/Features/Markdown Preview/`（5ファイル）

| ファイル                           | 責務                                                                                                                           |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `MarkdownPreviewModel.swift`       | ObservableObject。`isVisible`/`fileURL`/`content`/`revision`/`errorMessage`。`open(url:)`/`toggle()`/`close()`、watcher管理    |
| `MarkdownPreviewFileWatcher.swift` | DispatchSourceラッパー。デバウンス+再アーム                                                                                    |
| `MarkdownPreviewSplit.swift`       | `isVisible`で `SplitView(.horizontal)` に包むか素通しか切替（差分最小化の要）                                                  |
| `MarkdownPreviewPane.swift`        | ヘッダ（ファイル名・閉じる）+ `StructuredText` + 空/エラー状態。空状態に「Open File...」ボタン（NSOpenPanel）                  |
| `MarkdownPreviewImageLoader.swift` | `Textual`の`AttachmentLoader`プロトコル実装。`file://`スキーム以外の画像参照は読み込まずプレースホルダ表示（外部通信ゼロ担保） |

### 既存ファイルへの変更（最小差分）

| ファイル                                                       | 変更                                                                                                                                                                                                                                                                                                                                      |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `macos/Sources/Features/Terminal/TerminalView.swift`           | `TerminalViewModel` に `var markdownPreview: MarkdownPreviewModel { get }` 追加。`.ready` の既存ZStackを `MarkdownPreviewSplit` で包む（開き2行+閉じ1行、`.frame` 修飾子は外側へ移動）                                                                                                                                                    |
| `macos/Sources/Features/Terminal/BaseTerminalController.swift` | `let markdownPreview = MarkdownPreviewModel()` + `@IBAction func toggleMarkdownPreview(_:)`（非表示化時 `Ghostty.moveFocus(to: focusedSurface)`）                                                                                                                                                                                         |
| `macos/Sources/App/macOS/MainMenu.xib`                         | Viewメニュー（Command Palette項目の後）に「Toggle Markdown Preview」Cmd+Shift+M、`target="-1"`（First Responder）で `toggleMarkdownPreview:`                                                                                                                                                                                              |
| `macos/Ghostty-Info.plist`                                     | `CFBundleURLTypes` を新規追加。`CFBundleURLSchemes = ["zashiki"]`、`CFBundleURLName = "dev.kawaken.zashiki"`、`CFBundleTypeRole = Viewer`。既存の`UTExportedTypeDeclarations`と同じ場所・書式に倣う                                                                                                                                       |
| `macos/Sources/App/macOS/AppDelegate.swift`                    | `func application(_ application: NSApplication, open urls: [URL])` を新規追加（既存の`application(_:openFile:)`の直後が自然）。`zashiki://markdown-preview/open?path=...`をパース → パス検証 → frontmost `TerminalController`解決 → `controller.markdownPreview.open(url:)`。未対応ホスト/不正パスはログのみで無視                        |
| `macos/Ghostty.xcodeproj/project.pbxproj`                      | ①`Textual`のSPMリモートパッケージ参照を追加（`Sparkle`の既存エントリを雛形にする: `XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` + 対象ターゲットのFrameworks build phase）②Zashiki関連ターゲットの`MACOSX_DEPLOYMENT_TARGET`を13.0/13.1→15.0に引き上げ③Ghostty-iOSの`membershipExceptions`に新規Swiftファイルを追記 |

### 新規: URLスキームCLIラッパー

`zashiki://`のURL形式: `zashiki://markdown-preview/open?path=<パーセントエンコードした絶対パス>`

| ファイル                     | 内容                                                                                                                                                                                                                                                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `scripts/zashiki-md-preview` | 相対パスを絶対化 → パーセントエンコード → `ZASHIKI_APP`環境変数があれば `open -a "$ZASHIKI_APP" "zashiki://markdown-preview/open?path=$ENCODED"`（Debugビルドを名指しで起動、既定ハンドラの登録状況に依存しない）、なければ `open "zashiki://..."`（システム既定ハンドラ、通常は`/Applications`のRelease版） |

## 実装ステップ（段階的に動作確認）

1. **SPMパッケージ追加 + デプロイターゲット引き上げ + 試験表示**
   `Textual`をpbxprojに追加、Zashiki関連ターゲットのデプロイターゲットをmacOS 15.0に引き上げる。テスト用に適当なSwiftUIビュー（後で削除可）で `StructuredText(markdown: "# test\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n\`\`\`swift\nlet x = 1\n\`\`\`")`を表示し、GFMテーブル・コードハイライト・ダークモード切替を確認
検証:`macos/build.nu --configuration Debug` が通る。ビルド後のアプリでテスト表示が正しくレンダリングされる
2. **Model + ペインUI + TerminalView統合 + メニュー**（watcher以外）
   検証: トグルで空状態ペイン表示/非表示（Cmd+Shift+M含む）、Open File...でmd表示、ディバイダドラッグ、**トグル前後でシェルセッション生存**（`sleep 100` 継続・スクロールバック保持）、スプリット/タブ/フルスクリーンで崩れなし。リンククリックが`NSWorkspace`に委譲されること、スクロール位置維持の挙動を確認
3. **ライブ更新（watcher）**
   検証: (a) `>>` 追記 (b) vimの`:w`（atomic save） (c) Claude Codeによる書き換え (d) `mv` でのrename上書き → 1秒以内に再描画・スクロール維持。(e) 削除→エラー表示→再作成で復帰
4. **URLスキーム受け口 + シェルラッパー**
   検証（アプリは絶対パス指定）:
   `open -a <abs>/macos/build/Debug/Zashiki.app "zashiki://markdown-preview/open?path=/tmp/test.md"` でDebugビルドへ直接配送されること
   `ZASHIKI_APP=<abs>/macos/build/Debug/Zashiki.app scripts/zashiki-md-preview README.md`
   まず `application(_:open:)` が `CFBundleURLTypes` 登録だけでカスタムスキームに対して実際に呼ばれるか確認（呼ばれない場合は`applicationWillFinishLaunching`で`NSAppleEventManager`に`kInternetEventClass`/`kAEGetURL`の明示ハンドラを登録するフォールバックに切り替える。この点は未検証のため要注意）
   エラーパス（存在しないファイル、ウィンドウなし、不正なpath）も確認
5. **仕上げ**: `swiftlint lint --strict --fix` → フルビルド `zig build -Doptimize=ReleaseFast -Dxcframework-target=native` → `zig build test`（新規SwiftファイルがCIのlint/testに引っかからないか確認）→ LOCAL_PATCH.mdの手順で `/Applications` 配備 → Claude Codeにmdを書かせて実運用確認 → LOCAL_PATCH.md追記（変更ファイル表・使い方・動作確認手順・依存ライブラリ出典・upstream競合注意・デプロイターゲット引き上げの記録）→ コミット

## 主要リスクと対処

- **pbxproj手編集**: ID重複に注意（24桁hexを新規採番）。build.nuの成否で即検出。2026-08-08時点でpbxprojはリネーム・アイコン差し替え・TEST_HOST修正等で何度も手編集済みなので、既存の「変更前1行が唯一であることをassertしてから置換する」スクリプト方式を踏襲する。ただしSPMパッケージ参照（`XCRemoteSwiftPackageReference`/`XCSwiftPackageProductDependency`）の追加はこれまでのファイル参照追加より構造が複雑なので、`Sparkle`の既存エントリを一字一句参考にしつつ慎重に行う。うまくいかない場合はXcode GUIで一度追加してdiffを確認する手も検討する
- **Textualが0.x系**: 初タグから半年程度でAPIが安定していない可能性がある。`Package.resolved`でバージョンを固定し、更新時は差分を確認する
- **デプロイターゲット引き上げの影響範囲**: macOS 13.0/13.1→15.0に上げると、それ未満のmacOSでは起動不可になる。個人利用前提のため許容（ユーザー確認済み、2026-08-10）
- **画像ローダーのネットワーク制限**: `Textual`のデフォルト`AttachmentLoader`はリモートURLをfetchしうる実装。`file://`スキーム以外を拒否する独自実装が必須（未実装）。これを怠ると「外部通信なし」要件が破れる
- **SwiftUI構造切替によるサーフェス再アタッチ**: Inspector前例ありだが横分割+全体ラップは新パターン → Step 2のセッション生存確認を必須とする
- **StructuredTextのスクロール位置維持・リンク委譲の挙動が未検証**: WKWebView時代は`evaluateJavaScript`や`decidePolicyFor`で明示制御していたが、Textual採用によりSwiftUI標準の挙動に依存する部分が増えた。Step 2で実機確認する
- **configキーバインド連携は不可**（`syncMenuShortcut` はZigコアのアクション名前提）→ xibの静的Cmd+Shift+Mで代替。制約をLOCAL_PATCH.mdに明記
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
