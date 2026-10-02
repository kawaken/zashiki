# 左右パネルの幅をウィンドウ（tabGroup）単位で共有する

Issue #208

## 問題

`WorktreeStatusSplit` / `MarkdownPreviewSplit` の分割位置が各タブの `TerminalView` の `@State` に
あり、タブを切り替えるとパネル幅がタブごとに独立して見えていた。#195 で共有されたのは
表示状態（`WorktreeStatusModel`）のみだった。

## 実装判断

- SwiftUI の View 階層を window 単位へ持ち上げる案は、タブが別 `NSWindow`（tabGroup）である
  ため採らず、分割位置のみを共有モデルへ移した。
- `PanelLayoutModel`（左パネル幅・左パネル内の縦分割・右プレビュー幅）を新設し、
  `worktreeStatus` / `agentStatus` と同じ経路（`TerminalController.newTab` で親から引き継ぎ）
  で tabGroup 内の全タブが同一インスタンスを持つようにした。
- Markdown プレビューの内容・表示状態はタブごとのままで、幅のみ共有している。

## 検証

- `xcodebuild`（Debug）ビルド成功、`swiftlint lint --strict` 違反なし。
- 実機でのタブ切り替え時の幅維持は未確認。
