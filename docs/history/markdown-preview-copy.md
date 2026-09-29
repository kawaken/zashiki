# MarkdownプレビューでのCopyショートカット修正

## 目的

Markdownプレビューでテキストを選択した状態でも、ターミナル側の`Cmd+C`処理に
奪われず、選択中のプレビュー内容をショートカットでコピーできるようにする。

## 現状と原因

- Markdown本文はTextualの`NSTextInteractionView`で選択とCopyを提供している。
- Zashikiの`SurfaceView`は、ターミナルのkeybindを処理するために
  `performKeyEquivalent`を実装している。
- `Cmd+C`はZashikiのメニューshortcutにも登録されているため、AppKitが同じwindow内の
  `SurfaceView`へkey equivalentを問い合わせる。
- 前回の修正で、ターミナル自身がfirst responderでない場合のkeybind処理は止めたが、
  非ターミナルのfirst responderへ標準の`copy:` actionを明示的に渡す経路はない。
  そのため、Textualのselection viewがfirst responderになっているケースでも、
  Zashiki側のメニューshortcut処理と競合する。

## 実装方針

- `SurfaceView.performKeyEquivalent`で標準の`Cmd+C`を識別する。
- windowのfirst responderが`SurfaceView`以外で、`copy:`を実装している場合は、その
  responderへ直接Copy actionを転送してイベントを消費する。
- terminal自身がfirst responderの場合は既存のkeybind処理を維持する。
- それ以外のキーや、Copyを実装しないresponderには従来通りイベントを返す。

## 実装結果

- `SurfaceView.performKeyEquivalent`で標準の`Cmd+C`を検出する処理を追加した。
- first responderがterminal surface以外で`NSText.copy:`を実装している場合、
  `tryToPerform`でそのresponderへCopy actionを転送する。
- terminal surface自身がfirst responderの場合は、既存のkeybind処理へそのまま進む。
- Markdown preview専用の状態参照やTextual内部APIへの依存は追加していない。

## 検証

- SwiftLintまたは関連するmacOS lintを実行する。
- 可能ならDebug appをビルドし、Markdownプレビューの選択範囲で`Cmd+C`を確認する。
- Terminalの通常の`Cmd+C`コピーと、既存のメニューshortcut処理が変わらないことを確認する。
- Metal Toolchainなど環境不足でビルドできない場合は、未検証事項として記録する。

### 実行結果

- `swiftlint lint --strict`: 成功（0 violations）。
- `xcrun swiftc -parse macos/Sources/Zashiki/Surface View/SurfaceView_AppKit.swift`:
  成功。
- `git diff --check`: 成功。
- `just build` / `just test-fast`: XcodeにMetal Toolchainが無く、`metal`実行時に失敗。
- GUIでの手動確認: Macがロックされており未実施。

## 完了後

実装PRがmainへマージされたら、このプランを`docs/history/`へ移動する。
