# Markdownプレビューペイン実装計画（Zashikiフォーク）

## Context

ターミナルに「Claude.aiのアーティファクト」のようなMarkdownビューワーを組み込みたい。Claude Code（定額）がmdファイルを書き、ターミナル側は表示だけを担うのでAPI従量課金は発生しない。このフォークはmainが独自開発ライン（LOCAL_PATCH.md参照）であり、方針は「追加中心・既存APIシグネチャ変更なし・upstreamマージ競合最小化」。**Zigコアには手を入れず、Swift側のみで完結させる。**

要件:

- ターミナルウィンドウ右側にMarkdownプレビューペインを表示（トグル可能）
- CLIから `osascript` 経由でファイルを開ける（薄いシェルラッパー付き）
- 表示中ファイルのライブ更新（Claude Codeの書き換えに追従、atomic save対応）
- レンダリングはWKWebView + 同梱markdown-it/highlight.js（外部通信なし）

調査で確認済みの根拠:

- **前例**: Terminal Inspector（`macos/Sources/Ghostty/Surface View/InspectorView.swift` の `InspectableSurface`）が「if/elseで `SplitView` の片側に `NSViewRepresentable` を並べる」同型パターン。`SplitView<L,R>`（`macos/Sources/Features/Splits/SplitView.swift`）は汎用でドラッグディバイダ付き
- AppleScriptコマンド追加は sdef + NSScriptCommandサブクラス1ファイルの定型（`macos/Sources/Features/AppleScript/ScriptInputTextCommand.swift` がテンプレート）。コマンドコード `GhstMdPv`/`GhstMdCl` は既存と非衝突（2026-08-08時点で再確認済み）
- `Sources/` はPBXFileSystemSynchronizedRootGroupなのでSwiftファイルは置くだけでターゲットに入る（Ghostty-iOSのmembershipExceptionsへの除外追記は必要、`project.pbxproj`のメカニズムは健在）
- WebKitはimportのみで使用可（Frameworks追加不要）、App Sandbox無効

### 命名方針（2026-08-08のリネーム作業を踏まえて追記）

アプリ名は Ghostty → **Zashiki** にリネーム済み（`dev.kawaken.zashiki`、Swiftモジュール名は`PRODUCT_MODULE_NAME`指定により内部的に`Ghostty`のまま維持）。今回の新規実装では以下の使い分けをする:

- **既存のGhostty命名規則に合わせるべきもの**: AppleScriptコマンド実装クラス（`GhosttyScriptWindow`等の兄弟クラスと同じ命名規則に揃える。例: `GhosttyScriptMarkdownPreviewCommand`）。これは内部シンボルの一貫性の問題で、upstream競合最小化の対象でもある
- **Zashiki向けに新しく命名すべきもの**: このフォーク独自の新規機能でupstreamに対応物が存在しないもの（JSのレンダー関数名、CLIラッパーのファイル名・環境変数名）。`ghosttyRender` → `zashikiRender`、`scripts/ghostty-md-preview` → `scripts/zashiki-md-preview`、`GHOSTTY_APP` → `ZASHIKI_APP`
- ビルド成果物は `Zashiki.app`（`Ghostty.app`ではない）。検証コマンド例もこれに合わせて更新済み

## アーキテクチャ

```
BaseTerminalController
 └─ let markdownPreview = MarkdownPreviewModel()   ← 状態源（ウィンドウ単位）
TerminalView.body (.readyケース)
 └─ MarkdownPreviewSplit { 既存ZStack }             ← 非表示時は素通し
     └─ SplitView(.horizontal, left: 既存, right: MarkdownPreviewPane)
         └─ MarkdownPreviewWebView (NSViewRepresentable + WKWebView)
             └─ template.html を loadFileURL、更新は evaluateJavaScript("zashikiRender(...)")
MarkdownPreviewFileWatcher (DispatchSourceFileSystemObject)
 └─ write/extend → 80msデバウンスで再読込
 └─ delete/rename → ソース破棄→再アーム（atomic save対応、リトライ付き）
```

- コンテンツ受け渡し: テンプレート1回ロード + `evaluateJavaScript`（スクロール位置維持）。JSONエンコードして渡す
- ダークモード: WKWebViewはeffectiveAppearance継承 → CSSの `@media (prefers-color-scheme: dark)` で自動追従
- リンククリックは `decidePolicyFor` でcancelして `NSWorkspace.shared.open`。初回fileロード以外のナビゲーションは拒否（外部通信ゼロ担保）
- QuickTerminalも継承で機構的に動くが未調整扱い（問題が出たらメニューvalidateで無効化）

## 変更・新規ファイル

### 新規: `macos/Sources/Features/Markdown Preview/`（5ファイル）

| ファイル                           | 責務                                                                                                                        |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `MarkdownPreviewModel.swift`       | ObservableObject。`isVisible`/`fileURL`/`content`/`revision`/`errorMessage`。`open(url:)`/`toggle()`/`close()`、watcher管理 |
| `MarkdownPreviewFileWatcher.swift` | DispatchSourceラッパー。デバウンス+再アーム                                                                                 |
| `MarkdownPreviewSplit.swift`       | `isVisible`で `SplitView(.horizontal)` に包むか素通しか切替（差分最小化の要）                                               |
| `MarkdownPreviewPane.swift`        | ヘッダ（ファイル名・閉じる）+ WebView + 空/エラー状態。空状態に「Open File...」ボタン（NSOpenPanel）                        |
| `MarkdownPreviewWebView.swift`     | WKWebViewラップ。Coordinatorがロード完了までのバッファリングとrender                                                        |

### 新規: `macos/MarkdownPreviewWeb/`（Sources/の外＝同期グループとの二重登録回避）

- `template.html` / `preview.js` / `style.css`（自作）
- `markdown-it.min.js`（markdown-it@14, MIT）、`highlight.min.js`（@highlightjs/cdn-assets@11 common版, BSD-3）、`github-markdown.min.css`（github-markdown-css@5, MIT）、`hljs-themes.css`（github + github-dark をmedia queryで結合）
- CDN(jsdelivr)から取得してコミット。バージョン・URL・ライセンスをLOCAL_PATCH.mdに記録
- preview.jsは `html: false`、`zashikiRender(markdown, baseHref)` を公開、スクロール位置維持

### 既存ファイルへの変更（最小差分）

| ファイル                                                       | 変更                                                                                                                                                                                                                                                                                                                                  |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `macos/Sources/Features/Terminal/TerminalView.swift`           | `TerminalViewModel` に `var markdownPreview: MarkdownPreviewModel { get }` 追加。`.ready` の既存ZStackを `MarkdownPreviewSplit` で包む（開き2行+閉じ1行、`.frame` 修飾子は外側へ移動）                                                                                                                                                |
| `macos/Sources/Features/Terminal/BaseTerminalController.swift` | `let markdownPreview = MarkdownPreviewModel()` + `@IBAction func toggleMarkdownPreview(_:)`（非表示化時 `Ghostty.moveFocus(to: focusedSurface)`）                                                                                                                                                                                     |
| `macos/Sources/App/macOS/MainMenu.xib`                         | Viewメニュー（Command Palette項目の後）に「Toggle Markdown Preview」Cmd+Shift+M、`target="-1"`（First Responder）で `toggleMarkdownPreview:`                                                                                                                                                                                          |
| `macos/Ghostty.sdef`                                           | commands末尾（`send mouse scroll` の後、Standard Suiteの前）に `preview markdown`（code=`GhstMdPv`、direct-parameter=パス、optional `in` terminal パラメータ code=`GMdT`）と `close markdown preview`（code=`GhstMdCl`、`GMcT`）を追加                                                                                                |
| `macos/Ghostty.xcodeproj/project.pbxproj`                      | ①`MarkdownPreviewWeb` のfolder reference（PBXFileReference `lastKnownFileType = folder` + PBXBuildFile + Resources group children + Zashiki(旧Ghostty)ターゲットのPBXResourcesBuildPhase の4箇所。前例はかつての`Ghostty.icon`参照、現在は削除済みなので新規に倣う）②Ghostty-iOSの `membershipExceptions` に新規Swift 6ファイルを追記 |

### 新規: AppleScriptコマンドとCLIラッパー

| ファイル                                                                       | 内容                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `macos/Sources/Features/AppleScript/GhosttyScriptMarkdownPreviewCommand.swift` | `NSScriptCommand` サブクラス2つ（open/close）。既存の`GhosttyScriptXxxCommand`群と同じ命名規則。冒頭 `NSApp.validateScript(command:)` ガード → パス検証（`expandingTildeInPath` + 存在確認）→ terminal引数 or frontmost `TerminalController` 解決 → `controller.markdownPreview.open(url:)`。エラーは `scriptErrorNumber`/`scriptErrorString` |
| `scripts/zashiki-md-preview`                                                   | `osascript - "$file" <<EOF` のargv渡し（クォート問題回避）。相対パスは絶対化。`ZASHIKI_APP` 環境変数でDebugビルドを指定可能                                                                                                                                                                                                                   |

## 実装ステップ（段階的に動作確認）

1. **アセット + pbxproj folder reference**
   検証: `macos/build.nu --configuration Debug` が通り `Zashiki.app/Contents/Resources/MarkdownPreviewWeb/` に全ファイル。template.htmlをSafari単体で開き、コンソールで `zashikiRender("# test\n\n…")` を実行して描画・ハイライト・ダークモード切替を確認
2. **Model + ペインUI + TerminalView統合 + メニュー**（watcher以外）
   検証: トグルで空状態ペイン表示/非表示（Cmd+Shift+M含む）、Open File...でmd表示、ディバイダドラッグ、**トグル前後でシェルセッション生存**（`sleep 100` 継続・スクロールバック保持）、スプリット/タブ/フルスクリーンで崩れなし
3. **ライブ更新（watcher）**
   検証: (a) `>>` 追記 (b) vimの`:w`（atomic save） (c) Claude Codeによる書き換え (d) `mv` でのrename上書き → 1秒以内に再描画・スクロール維持。(e) 削除→エラー表示→再作成で復帰
4. **AppleScript + シェルラッパー**
   検証（`macos/AGENTS.md`手順、アプリは絶対パス指定）:
   `osascript -e 'tell application "<abs>/macos/build/Debug/Zashiki.app" to preview markdown "/tmp/test.md"'`
   `ZASHIKI_APP=<abs>/macos/build/Debug/Zashiki.app scripts/zashiki-md-preview README.md`
   エラーパス（存在しないファイル、ウィンドウなし、`macos-applescript` 無効）も確認
5. **仕上げ**: `swiftlint lint --strict --fix` → フルビルド `zig build -Doptimize=ReleaseFast -Dxcframework-target=native` → `zig build test`（新規SwiftファイルがCIのlint/testに引っかからないか確認）→ LOCAL_PATCH.mdの手順で `/Applications` 配備 → Claude Codeにmdを書かせて実運用確認 → LOCAL_PATCH.md追記（変更ファイル表・使い方・動作確認手順・アセット出典・upstream競合注意）→ コミット

## 主要リスクと対処

- **pbxproj手編集**: ID重複に注意（24桁hexを新規採番）。build.nuの成否で即検出。2026-08-08時点でpbxprojはリネーム・アイコン差し替え・TEST_HOST修正等で何度も手編集済みなので、既存の「変更前1行が唯一であることをassertしてから置換する」スクリプト方式を踏襲する
- **SwiftUI構造切替によるサーフェス再アタッチ**: Inspector前例ありだが横分割+全体ラップは新パターン → Step 2のセッション生存確認を必須とする
- **WKWebViewのローカル読込**: `loadFileURL(_:allowingReadAccessTo: URL(fileURLWithPath: "/"))` でmd内の画像参照を許容（Sandbox無効のローカル用途。JS側 `html: false`+ナビゲーション遮断で緩和、LOCAL_PATCH.mdにトレードオフ明記）。画像が出ん場合の第一容疑はここ
- **configキーバインド連携は不可**（`syncMenuShortcut` はZigコアのアクション名前提）→ xibの静的Cmd+Shift+Mで代替。制約をLOCAL_PATCH.mdに明記
- **ウィンドウサイズ**: デフォルト非表示なので初期サイズ算出に影響なし。表示時はウィンドウ幅維持でターミナルが縮む（Inspectorと同挙動）。自動拡幅はv2候補
- **CI**: 新規Swiftファイルは`zig build test`（`GhosttyTests`）と`swiftlint lint --strict`の対象になる。WKWebViewを使うUIコードはユニットテスト対象外にしてよいが、`MarkdownPreviewFileWatcher`のデバウンスロジック等ロジック部分は簡単な単体テストを足す余地がある（必須ではない）

## 検証（全体）

Step 1〜4の各検証に加え、最終的に:

1. `/Applications` 配備後、実際のClaude Codeセッションでmdを書かせながら `zashiki-md-preview` で開き、ライブ更新を確認
2. システム外観のライト/ダーク切替でプレビューが追従
3. upstream由来の既存機能（スプリット、タブ、Inspector、Command Palette）が無事なこと
4. `zig build test` と `swiftlint lint --strict` がCI上でも通ること
