# UIに残るGhostty表記の洗い出しとZashikiへの置換

- **実施PR**: [#24](https://github.com/kawaken/zashiki/pull/24)（2026-08-13マージ）
- **元プラン**: `plan/rebrand-ghostty-remnants.md`（削除済み、このドキュメントに統合）

## 目的

macOSアプリのUI（メニュー、ダイアログ、コマンドパレット等）とCLI出力（`--version`/`--help`等）に残っていた"Ghostty"表記を、内部識別子（`Notification.Name`・`NSUserInterfaceItemIdentifier`・`UserDefaults`）や実行ファイル名（`EXECUTABLE_NAME`）も含めて全面的に"Zashiki"へ置換した。過去に「upstream競合最小化のため内部シンボルは維持する」としていた方針をユーザー判断で撤回し、フルブランド化を対応対象に格上げした。

## Planとの差分

Planでは「UserDefaults suite名の変更には既存ユーザー設定の移行処理が必要」と見積もっていたが、実際には誤りだった。`UserDefaults.ghostty`はReleaseビルドでは常に`.standard`にフォールバックする設計で、実運用で使われるsuite名（DockTilePlugin連携用）は過去のリネーム作業で既に`dev.kawaken.zashiki`に追従済みだったため、移行処理は不要だった。代わりに、実際に移行が必要だったのは想定していなかった`CustomGhosttyIcon2`（カスタムDockアイコン設定の永続化キー）で、こちらに一回限りの移行読み込みを追加した。

また、Planでは`EXECUTABLE_NAME`変更に伴い`xcodebuild -scheme "Ghostty"`の修正も必要と見積もっていたが、これは別のPR（markdown preview機能の実装時）で既に`-scheme "Zashiki"`へ修正済みだったことが判明した。実際に必要だった変更は`EXECUTABLE_NAME`・`TEST_HOST`末尾・`ZashikiXcodebuild.zig`の`open`ステップの3箇所のみで、Planの見積もりより小さかった。

最終確認のための全体スイープで、Planに含まれていなかった追加箇所も見つかり対応した:

- `src/cli/show_face.zig`・`list_themes.zig`・`ssh_cache.zig`（`+show-face`/`+list-themes`/`+ssh-cache`のCLI出力文言）
- `Ghostty.Config.swift`のカスタムアイコンのデフォルトパス（`~/.config/ghostty/Ghostty.icns` → `Zashiki.icns`）
- `Fullscreen.swift`の内部通知識別子（`com.mitchellh.fullscreenDid*`）

意図的に対応外としたもの（Planにも記載済みだが、実装完了時点で改めて確定）:

- Swiftモジュール名（`PRODUCT_MODULE_NAME=Ghostty`）・型名（`Ghostty.App`等）・`GhosttyPackage.swift`内の約30個の`Notification.Name`プロパティ名（文字列値はリネーム済みだがSwift側のプロパティ名自体は`ghostty*`のまま）— より大規模な別リファクタが必要なため
- Zigビルドシステムの内部ファイル名（`GhosttyLib.zig`等）— 同上
- `xterm-ghostty` terminfoエントリ、libghostty-vtのC API型名（`GhosttyBuffer`等）— 外部エコシステムとの互換性に関わるプロトコル/ABI識別子のため

Planに含まれていた「C: Sparkle appcast URLの自前化」は本PRでは対応せず、後続の別プラン `plan/auto-update-feed-url.md` に引き継いだ。

## 注意事項として引き継いだ点

`QuickTerminalWindow.swift`のアクセシビリティ識別子を`dev.kawaken.zashiki.quickTerminal`に変更した。AeroSpace等のサードパーティAppからこの識別子を参照する既存設定がある場合は追従が必要。

## 関連コミット

- `e32511738` refactor: UI・CLIに残るGhostty表記をZashikiに置換 (#24)（squash merge）
