# Markdownプレビューのフォーカス時フォントサイズ変化

## 対象

- Issue #241

## 調査結果

- MarkdownPreviewPaneは`@FocusedValue(\.zashikiSurfaceCellSize)`からセル高を取得する。
- ターミナルからプレビューへフォーカスを移すとFocusedValueがnilになり、システム標準サイズへフォールバックするため、表示サイズが変化する。
- TerminalViewは最後にフォーカスしたSurfaceViewを保持しており、SurfaceViewは現在のセルサイズを公開している。

## 方針

- プレビューにフォーカスがある間は、最後にフォーカスしたターミナルSurfaceのセル高を使う。
- ターミナルにフォーカスがある場合は、現在フォーカス中のSurfaceのセル高を優先する。
- どちらも有効なセル高を持たない場合のみ、従来どおりシステム標準サイズへフォールバックする。
- サイズ選択を小さなポリシー関数にまとめ、現在値・直近値・無効値の優先順位をモデルテストで確認する。

## テスト

- `just lint`
- `just test`
- UI上でターミナルとMarkdownプレビュー間のフォーカスを切り替え、サイズが保たれることを確認する。

## 実装記録

- TerminalViewが保持する最後にフォーカスしたSurfaceをMarkdownPreviewSplit全体の環境値として渡す。
- MarkdownPreviewPaneは現在フォーカス中のSurfaceサイズを優先し、値がないときは最後にフォーカスしたSurfaceのセル高を使う。
- セル高が0または未設定ならシステム標準サイズへの従来フォールバックを維持する。
- 現在のセル高・最後のセル高・無効値の優先順位を検証する回帰テストを追加。
- `just lint`成功。`just test`成功（274 tests、failed 0）。
- 手動のUIフォーカス切替確認は未実施。ビューの実機確認はPR後のCI/ユーザー検証に残す。
