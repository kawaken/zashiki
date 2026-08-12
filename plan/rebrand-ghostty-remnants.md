# UIに残るGhostty名残の洗い出しと対応チェックリスト

## 作業状況

- 2026-08-12: Exploreエージェントによる網羅調査＋過去のリネームコミット（`ff09c5f94` 〜 `4475d5352` 等、フェーズ1〜のZashikiリネーム作業）を突き合わせて本ドキュメントを作成。まだコード修正には着手していない（一覧化のみ）
- 前提: このフォークの命名方針は「[[ghostty_fork_direction]]」（アプリ名はZashiki）。過去のリネームで **表示文言（UI text）は対応済みの箇所と未対応の箇所が混在**しており、**内部シンボル（モジュール名・通知名・実行ファイル名）はupstream追従のため意図的にGhosttyのまま維持**する方針がすでに確立している

## 方針（重要）

このリポジトリは「upstream（本家Ghostty）を追従し続ける」ことを明言したフォーク（`AboutView.swift`の説明文 "A personal, macOS-only fork of Ghostty, tracking upstream rather than diverging from it." より）。過去のリネーム作業でも一貫して次のルールが取られている:

- **`macos/`配下のUI表示文言**（メニュー、ダイアログ、About画面等）: フォーク独自にビルド・保守する範囲なので **対応してOK**
- **内部シンボル**（Swiftモジュール名`PRODUCT_MODULE_NAME`、`EXECUTABLE_NAME`、`NSUserInterfaceItemIdentifier`、`Notification.Name`、UserDefaults suite名など）: 変更するとupstreamとの差分が広がり将来のマージが困難になるため **意図的に`Ghostty`のまま維持**（コミット`4475d5352`, `84d1b93e8`で明言済み）
- **`src/`配下（Zigコア、Linux/GTK版とも共有）**: upstreamと共有しているコードなので、CLIの`--version`/`--help`出力等に残る"Ghostty"表記を変更するかは **要相談**（変更するとupstream同期のたびコンフリクトが増える。マージ頻度・実利益とのトレードオフ）

## A. 対応不要（意図的にGhosttyのまま維持・修正しないこと）

| 項目 | 根拠 |
|---|---|
| `project.pbxproj`: `EXECUTABLE_NAME = ghostty;`（全Configuration） | コミット `84d1b93e8`「EXECUTABLE_NAME自体は変更方針により小文字"ghostty"のまま」 |
| `project.pbxproj`: `PRODUCT_MODULE_NAME = Ghostty;` | コミット `4475d5352`「内部シンボルはupstream競合最小化のため変更しない」。`MainMenu.xib`の`customModule="Ghostty"`もこれに追従済み |
| `GhosttyPackage.swift`等の`Notification.Name("com.mitchellh.ghostty.*")`、`NSUserInterfaceItemIdentifier`、`UserDefaults.ghostty`/`ghosttySuite` | 同上の内部シンボル方針 |
| `AboutView.swift:86` "A personal, macOS-only fork of **Ghostty**, tracking upstream..." | 事実として本家Ghosttyのフォークであることを説明する文脈であり、ブランド名残ではなく仕様文言 |
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

## C. 機能面（UIに間接的に影響、対応要否は相談）

| 項目 | 内容 |
|---|---|
| `UpdateDelegate.swift:14-15` | Sparkleのappcast URLが `tip.files.ghostty.org` / `release.files.ghostty.org`（本家）のまま。**このURLを変えない限りUpdate画面には本家Ghosttyのリリースノートが表示される**。フォーク独自のリリースフローを持つ気がなければ、そもそもUpdate機能自体をどう扱うかから要検討 |

## D. 要相談（`src/`＝Zigコア、upstream共有部分）

以下はupstream追従方針とのトレードオフがあるため、対応するかどうかまずユーザーに確認する:

| ファイル:行 | 内容 |
|---|---|
| `src/cli/version.zig:29` | `"Ghostty {s}\n\n"`（`--version`出力） |
| `src/cli/help.zig:36-56` | `"Usage: ghostty [+action]..."`, `"Run the Ghostty terminal emulator..."`, `` "open -na Ghostty.app" ``（`--help`出力。実バイナリ名は`ghostty`のままなので`ghostty`部分は実態と一致しているが、`Ghostty.app`は実際のバンドル名`Zashiki.app`と不一致） |
| `src/cli/ssh.zig:16` | `"Usage: ghostty +ssh..."` |
| `src/input/command.zig:674` | コマンドパレットの組み込みデフォルトコマンドのタイトルが`"Ghostty"` |
| `src/Surface.zig:1355` | `"Ghostty failed to launch the requested command:"`（ターミナル画面に描画されるエラー文言） |
| `macos/Sources/App/macOS/main.swift:16` | CLI起動失敗時のstderr文言（macos側だがCLI起動シナリオ） |

## E. 未確認・要確認

- `macos/Sources/App/iOS/iOSApp.swift:45` の `Text("Ghostty")` — iOSターゲット（`Ghostty-iOS`）は出荷対象なのか？ 出荷しないなら対応不要
- `project.pbxproj`の`Ghostty-iOS`ターゲット`INFOPLIST_KEY_CFBundleDisplayName = Ghostty`も同様に出荷有無次第
- `src/config/Config.zig:2842`のdocコメント中のサンプル値（`command-palette-entry`のドキュメント例） — `--help`相当のドキュメント出力に混ざる可能性、実害は小さい

## 次のアクション（要ユーザー判断）

1. **B（macos/配下のUI文言）は対応して良いか** → 良ければB-1から順に着手
2. **C（Sparkle appcast URL）** → 独自リリースフローを持つ気があるか、それとも自動更新機能自体を無効化するか
3. **D（src/のCLI文言）** → upstream追従を優先してこのまま残すか、ブランド一貫性を優先して変更するか
4. **E（iOSターゲット）** → 出荷対象かどうか
