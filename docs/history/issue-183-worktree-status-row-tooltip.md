# Worktree Status 行全体のツールチップ

## Issue

- Issue #183: Worktree Status のホバー範囲を行全体へ広げ、各状態の説明を
  1つのツールチップにまとめる。

## 問題

`WorktreeStatusRowView` は状態ごとのアイコンやラベルに個別の `.help()` と
AppKit tooltip bridge を付けているため、ホバー判定が狭く、カーソルが少しずれると
ツールチップが消える。

## 方針

- `GwWorktree` の既存の個別ヘルププロパティは、各状態の情報源として残す。
- 表示名、Git、upstream、agent、PR/GitHub、lock、cleanup の説明を行用の
  プロパティへ結合する。PRがない場合はGitHubステータスを使い、lockはロック時だけ
  含める。
- 行のフル幅に `contentShape(Rectangle())` を設定し、行の外側へ `.help()` と
  `.appKitTooltip()` を1つずつ付ける。
- 個別のアイコンやリンクからはツールチップを外し、表示・クリック操作は維持する。

## 実装結果

- `GwWorktree.rowHelp` を追加し、既存の個別ヘルプを改行区切りで結合した。
- `WorktreeStatusRowView` のフル幅の行へ `.help()` と `.appKitTooltip()` を
  1つずつ付け、`contentShape(Rectangle())` で行全体をホバー対象にした。
- アイコン・ラベル・PRリンクの個別ツールチップを外し、PRがない場合のGitHub状態と
  ロック時のロック説明も行用ツールチップへ含めた。
- PRあり、PRなし・Gitエラー、ロックありの行用ツールチップをテストで検証した。

## 検証結果

- `just lint`: 成功（0 violations / 0 serious）
- `git diff --check`: 成功
- `xcodebuild ... test -only-testing:ZashikiTests/GwSchemaTests`: 成功
- `just test-fast` のmacOS app build: 成功
- 実アプリでのマウスホバー確認は未実施。行全体の実機挙動はCIでは確認できないため、
  PRで手動確認事項として報告する。
