# Markdownプレビューのフォントサイズ追従

## 対象

- Issue #225

## 調査結果

ターミナルのフォント変更後のセルサイズは`SurfaceView.cellSize`に反映され、現在フォーカス中のSurfaceから`FocusedValue`の`zashikiSurfaceCellSize`として`TerminalView`以下へ公開されている。Markdownプレビューはこの値をまだ参照せず、SwiftUIの既定サイズで描画していた。

## 方針

- 現在フォーカス中のターミナルSurfaceのセル高をMarkdownプレビューへ渡す。
- ターミナルの行高に対する既存UIの基準（約0.8倍）を使ってpoint sizeへ変換する。
- Markdown本文とFront Matter表へ同じサイズを適用する。
- セルサイズがまだ取得できない場合は、現在のシステム標準サイズへフォールバックする。
- 実機でのフォント変更確認はリリース後に行うため、CI通過後にマージする。

## 実装内容

- `MarkdownPreviewPane`で`zashikiSurfaceCellSize`を購読し、Markdownの基準サイズを算出。
- `StructuredText`とFront Matter表へ算出したサイズを適用。
- 既存の見出しスケール、レイアウト、テキスト選択は維持する。

## テスト・検証

- `just lint`とCIの`just test-fast`を実行する。
- 実機でターミナルのフォントサイズ変更、Surface切替、プレビュー表示を確認する（リリース後）。

## 対象外

- ターミナルとMarkdownプレビューのフォントファミリー統一。
- プレビュー専用のフォントサイズ設定。
- #224の履歴UI変更。
