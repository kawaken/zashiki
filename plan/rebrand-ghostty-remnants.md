# UIに残るGhostty名残の洗い出しと対応チェックリスト

## 作業状況

- 2026-08-12: Exploreエージェントによる網羅調査＋過去のリネームコミット（`ff09c5f94` 〜 `4475d5352` 等、フェーズ1〜のZashikiリネーム作業）を突き合わせて本ドキュメントを作成。まだコード修正には着手していない（一覧化のみ）
- 前提: このフォークの命名方針は「[[ghostty_fork_direction]]」（アプリ名はZashiki）
- **2026-08-12 追記（方針転換）**: 「upstream競合最小化」を理由に内部シンボルや`src/`のCLI文言をGhosttyのまま残す、という過去方針（コミット`4475d5352`, `84d1b93e8`）はユーザー判断により**撤回**。以後は内部シンボル・実行ファイル名・`src/`のCLI文言も含めてフルブランド化を対応対象とする。旧A・旧Dは統合して下記Dに移動し、代わりに各項目ごとの**upstream競合とは別の実装コスト・実害**を明記する形に更新した
- **2026-08-12 追記2（方針再確定）**: D・Eも含めて**基本的に全部変える**方針に確定。D各項目の実装コスト・実害の注記は「着手をためらう理由」ではなく単なる実装メモとして残す。upstream競合は「実際にupstreamの機能を取り込みたくなったとき」に個別対応すればよく、それを理由に今リネームを避ける必要はない。E（iOSターゲット等）も対応対象に格上げ

## 方針（更新後）

- **`macos/`配下のUI表示文言**（メニュー、ダイアログ、About画面等）: 対応してOK
- **内部シンボル・実行ファイル名・`src/`のCLI文言**: upstream追従を理由にした制約は撤廃、**全て対応対象**。実装コスト・実害の注記（設定移行、ビルドパイプライン追従、テストファイル書き換え等）は着手判断の材料ではなく実装時のチェック事項として残す
- **iOSターゲット等（旧E）**: 出荷有無の確認待ちとして保留していたが、対応対象に格上げ

## A. 対応不要（ブランド名残ではなく、意味のある記述）

| 項目 | 根拠 |
|---|---|
| `AboutView.swift:86` "A personal, macOS-only fork of **Ghostty**, tracking upstream..." | 事実として本家Ghosttyのフォークであることを説明する文脈であり、ブランド名残ではなく仕様文言（upstream追従方針とは無関係に、フォーク元を明示する記述として残す） |
| コード内コメント、`os_log`のデバッグログ文言 | ユーザーに見えるUIではない |
| `GhosttyKit.xcframework`, `*.entitlements`, テストターゲットの`PRODUCT_BUNDLE_IDENTIFIER`等ビルド成果物・非出荷物 | 非UI |

## B. 対応推奨（`macos/`配下のUI表示文言・優先度順）

### B-1. ダイアログ・アラート（優先度: 高、ユーザーの目に直接入る）

| ファイル:行 | 内容 |
|---|---|
| `macos/Sources/App/macOS/AppDelegate.swift:497` | `"Allow Ghostty to execute \"\(filename)\"?"` |
| `macos/Sources/App/macOS/AppDelegate.swift:1374, 1412` | `"Quit Ghostty?"`（終了確認ダイアログ、2箇所） |
| `macos/Sources/Features/App Intents/IntentPermission.swift:48` | `"Allow Shortcuts to interact with Ghostty?"` |
| `macos/Sources/Features/App Intents/GhosttyIntentError.swift:8, 10` | `"The Ghostty app isn't properly initialized."` / `"Ghostty doesn't allow Shortcuts."` |

### B-2. 常用UI文言（優先度: 中）

| ファイル:行 | 内容 |
|---|---|
| `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift:95` | `"Update Ghostty and Restart"` |
| `macos/Sources/Features/Settings/SettingsView.swift:17` | 案内文中の "...restart Ghostty."（`.config/ghostty/`のパス自体は互換性のため変更不要） |
| `macos/Sources/Features/Terminal/ErrorView.swift:13` | `"...restart Ghostty."`（致命的エラー画面） |
| `macos/Sources/Features/Update/UpdatePopoverView.swift:65` | `"Ghostty can automatically check for updates..."` |
| `macos/Sources/Features/Secure Input/SecureInputOverlay.swift:61-62` | 説明文＋実在しないメニューパス `Ghostty > Secure Keyboard Entry`（実際のメニューは既にZashikiにリネーム済みなので不整合） |
| `macos/Sources/Features/About/CyclingIconView.swift:29` | `.accessibilityLabel("Ghostty Application Icon")` |

### B-3. デバッグビルド限定（優先度: 低、Releaseでは非表示）

| ファイル:行 | 内容 |
|---|---|
| `macos/Sources/Features/Terminal/TerminalView.swift:161, 165-167, 178` | デバッグビルド警告バナー＋アクセシビリティ文言 |

### B-4. ウィンドウタイトルの初期値/フォールバック（優先度: 低、実行時に即上書きされるはず）

| ファイル | 内容 |
|---|---|
| `TitlebarTabsVenturaTerminalWindow.swift:589`, `TitlebarTabsTahoeTerminalWindow.swift:276` | `"👻 Ghostty"` |
| `Terminal.xib`, `TerminalHiddenTitlebar.xib`, `TerminalTabsTitlebarVentura.xib`, `TerminalTabsTitlebarTahoe.xib`, `TerminalTransparentTitlebar.xib`, `QuickTerminal.xib`（各`title=`属性、6ファイル） | 同上 |

### B-5. Xcodeプロジェクト設定（ユーザーに見える表示名）

| 項目 | 内容 |
|---|---|
| `project.pbxproj`: DockTilePluginターゲットの`INFOPLIST_KEY_CFBundleDisplayName = "Ghostty Dock Tile Plugin"`（全Configuration） | Finder情報パネル等で見える可能性 |

### B-6. Info.plist（キー名は非UIだが、値の参照元は要整理）

| 項目 | 内容 |
|---|---|
| `Ghostty-Info.plist`の`GhosttyBuild`/`GhosttyCommit`キー | 値は`AboutView.swift`/`UpdateViewModel.swift`のバージョン表示に使われる。キー名自体はビルドスクリプトが書き込む内部キーなので必須ではないが、一貫性のため`ZashikiBuild`/`ZashikiCommit`へのリネームも検討可（ビルドスクリプト側の追従が必要） |

## C. 対応対象（Sparkle appcast URLを自前に差し替え、2026-08-12決定）

| 項目 | 内容 |
|---|---|
| `UpdateDelegate.swift:14-15` | Sparkleのappcast URLが `tip.files.ghostty.org` / `release.files.ghostty.org`（本家）のまま。**自分のappcast URLに差し替える方針で決定**（Update機能自体は維持） |

対応方針・注意点:

- 単なる文字列置換では終わらない。**appcast.xmlを実際に配信するインフラが要る**（GitHub Releases + `appcast.xml`をホストする形が有力。`.github/workflows/release.yml`は既に「タグを打ったらad-hoc署名のZashiki.appをzipにしてGitHub Releaseに添付する」最小構成が動いている）
- `release.yml`のコメントに「Apple Developer Program登録後にnotarization・Developer ID署名・Sparkle自動更新を追加するのは別タスク」と明記されている。[[atok_patch_distribution_plan]]（Apple Developer Program登録の方針は決定済み・登録自体はこの時点で未確認）を参照し、**Developer登録状況を先に確認**してから着手すること（未署名アプリへのSparkle自動更新はGatekeeper警告と絡んで体験が悪い可能性がある）
- 実装順序の目安: (1) Developer登録状況を確認 → (2) `release.yml`にappcast.xml生成・公開ステップを追加 → (3) `UpdateDelegate.swift`のURLを自前ドメイン/GitHub Pages等に差し替え → (4) 実リリースで動作確認

## D. 対応対象（内部シンボル・実行ファイル名・`src/`のCLI文言）

upstream競合は考慮不要（upstream機能を実際に取り込みたくなった時点で個別対応すればよい）。各項目の実装コスト・実害は着手時のチェック事項として記載。

### D-1. 内部シンボル（Swiftモジュール名・識別子）

| 項目 | 内容 | 変更に伴う実装コスト・実害 |
|---|---|---|
| `project.pbxproj`: `PRODUCT_MODULE_NAME = Ghostty;`（全Configuration） | Swiftモジュール名をZashikiへ | `GhosttyTests`配下17ファイルの`@testable import Ghostty`を全て書き換え要。`MainMenu.xib`ほか各xibの`customModule="Ghostty"`も追従が必要（コミット`4475d5352`が一度この作業を避けて維持を選んだ経緯あり） |
| `GhosttyPackage.swift`等の`Notification.Name("com.mitchellh.ghostty.*")`、`NSUserInterfaceItemIdentifier` | 内部通知・識別子名の変更 | 送受信両側の書き換え漏れがあると通知が届かなくなるだけで、外部への実害は基本なし。全参照箇所の洗い出しが必要 |
| `UserDefaults.ghostty` / `UserDefaults.ghosttySuite`（`UserDefaults+Extension.swift`） | suite名の変更 | **要注意**: suite名を変えると既存ユーザーの設定が新suiteから見えなくなり初期化されたように見える。移行処理（旧suiteから新suiteへの値コピー）を別途実装しない限り、ビルド更新のタイミングでユーザー設定が消失する |

### D-2. 実行ファイル名

| 項目 | 内容 | 変更に伴う実装コスト・実害 |
|---|---|---|
| `project.pbxproj`: `EXECUTABLE_NAME = ghostty;`（全Configuration） | `zashiki`へ変更 | コードサイニング・entitlements・`src/build/GhosttyXcodebuild.zig`のscheme参照（`-scheme "Ghostty"`は前回のリネームで未改修と明記あり）等、ビルドパイプライン側の追従が必要。`TEST_HOST`パス（既に`Zashiki.app`）の末尾バイナリ名も追従要 |

### D-3. `src/`（Zigコア、Linux/GTK版とも共有）のCLI出力文言

| ファイル:行 | 内容 |
|---|---|
| `src/cli/version.zig:29` | `"Ghostty {s}\n\n"`（`--version`出力） |
| `src/cli/help.zig:36-56` | `"Usage: ghostty [+action]..."`, `"Run the Ghostty terminal emulator..."`, `` "open -na Ghostty.app" ``（`--help`出力。バイナリ名を`zashiki`に変えるなら`Usage:`行もそれに追従） |
| `src/cli/ssh.zig:16` | `"Usage: ghostty +ssh..."` |
| `src/input/command.zig:674` | コマンドパレットの組み込みデフォルトコマンドのタイトルが`"Ghostty"` |
| `src/Surface.zig:1355` | `"Ghostty failed to launch the requested command:"`（ターミナル画面に描画されるエラー文言） |
| `macos/Sources/App/macOS/main.swift:16` | CLI起動失敗時のstderr文言（macos側だがCLI起動シナリオ） |

備考: 本フォークはmacOS専用運用（Linux/GTK版はビルド・実行対象外、コミット`ff09c5f94`より）なので、Linux/GTK版との共有を理由にした変更のためらいは不要。

## E. 対応対象（旧・未確認、格上げ）

以前は「最初は変えなくて良い」との判断で保留していたが、対応対象に格上げ。

| 項目 | 内容 |
|---|---|
| `macos/Sources/App/iOS/iOSApp.swift:45` | `Text("Ghostty")`（iOSターゲット`Ghostty-iOS`の初期化中プレースホルダー画面） |
| `project.pbxproj`: `Ghostty-iOS`ターゲットの`INFOPLIST_KEY_CFBundleDisplayName = Ghostty`（全Configuration） | iOSホーム画面のアプリ名 |
| `src/config/Config.zig:2842`のdocコメント中のサンプル値（`command-palette-entry`のドキュメント例） | `--help`相当のドキュメント出力に混ざる可能性 |

## 次のアクション

1. **B（macos/配下のUI文言）** → 対応対象、B-1から順に着手
2. **C（Sparkle appcast URL）** → 対応対象（自前appcastへ差し替え）。ただしDeveloper登録状況の確認が前提なので、B/D/Eの後、単独タスクとして着手するのが良さそう
3. **D（内部シンボル・実行ファイル名・src/のCLI文言）** → 対応対象。D-1のUserDefaults suite名変更は設定移行の実装、D-2のEXECUTABLE_NAME変更はビルドパイプライン追従が必要な点だけ実装時に注意（着手判断の材料ではなく実装メモ）
4. **E（iOSターゲット等）** → 対応対象
