# 端末本体の統合改善 #295 #296 #297 #305 #306 #307 #308 #309 #289

## 基準と進め方

- 基準は最新origin/main `f96b40855`。#313の入力・出力保護、#314のSparkle更新、#315の共有許可、#316の同期・資源寿命修正を確認した。
- 9件の本文・コメントを確認し、既存claimはなかった。Codexが各Issueにwipとclaimを記録した。関連PRの履歴も確認する。
- 全体で1ブランチ・1worktree・1Plan・1PR。Planレビューは実装フローに含め、ローカル検証をまとめてからpushする。needs-verificationは付けず、実機未確認を成功扱いにしない。
- ATOK文節下線、IME周辺文字列通知・確定後invalidate、独自タブとMarkdownプレビュー、配布・更新設定を維持する。共有許可は拡大しない。
- 上流の個別差分と後続修正を調査し、現行実装に必要な部分を採用する。remote追加・一括マージはしない。

## 依存関係と対応順

1. #295: LineIteratorの空行・コメント消費後にreaderを補充。小bufferで回帰を再現する。
2. #296: retained render state再生成時のframe countをリセット。閾値前後を検証。
3. #308: 行再利用時のmetadata全体初期化と、wrapped wide character消去時の前行dirty。#309の再利用fast pathの前提にする。
4. #305 → #306: 確定文字列をtyped inputへ統一し、その手前でNSStringのUTF-16分割入力を復元する。drop専用の保護経路は維持。
5. #307: preedit glyphへfont-thickenと強度を渡す。独自文節下線は維持。
6. #297: hard newline、wide tail/head、page境界の選択・コピー・表示を整合させる。
7. #309: pageの基盤最適化→same-style bulk copy→wide pair fast pathの順。style、grapheme、hyperlink、tracked pin、cursorを検証。
8. #289: 独自タブからの可視通知を確認し、GPU資源を非表示時に解放、表示時に再生成。#316の非同期main queue DisplayLink管理とcallback寿命を維持。

## 採用候補

| Issue | Ghosttyの個別差分 | 現行での確認・検証方針 |
| --- | --- | --- |
| #295 | [#13638](https://github.com/ghostty-org/ghostty/pull/13638) | 空行・コメントでcontinueのみ。buffer末尾の後続設定を検証 |
| #296 | [#13585](https://github.com/ghostty-org/ghostty/pull/13585), `e69dc2bee` | count reset欠落。周期的な再生成を検証 |
| #308 | [#14010](https://github.com/ghostty-org/ghostty/pull/14010), `046a45a5f`; [#14054](https://github.com/ghostty-org/ghostty/pull/14054), `76e568b47` | resetRowなし。scroll/erase/resize、primary/alternate、prompt、page境界 |
| #305 | [#13817](https://github.com/ghostty-org/ghostty/pull/13817), `900912295` | marked textなしはsendText。入力メソッド経路とdropを区別 |
| #306 | [#13737](https://github.com/ghostty-org/ghostty/pull/13737), `b0b9fbc8d` | String変換前のNSString code unit保持が必要。片側・順序・介在入力を検証 |
| #307 | [#14230](https://github.com/ghostty-org/ghostty/pull/14230), `88abb77b1` | preedit optionsにthicken指定なし |
| #297 | [#14354](https://github.com/ghostty-org/ghostty/pull/14354), `aa9ed7d51`; [#14391](https://github.com/ghostty-org/ghostty/pull/14391), `69bf1ac87`; [#14632](https://github.com/ghostty-org/ghostty/pull/14632), `b1d9492cf`; [#14651](https://github.com/ghostty-org/ghostty/pull/14651), `d3d4c15d6` | 単語選択・formatter・renderの回帰テストを個別採用 |
| #309 | [#13537](https://github.com/ghostty-org/ghostty/pull/13537), `aa21caeaa`; [#13827](https://github.com/ghostty-org/ghostty/pull/13827), `d760ee96e` | 同条件のASCII・日本語・絵文字履歴で前後計測。上流の倍率は実測として扱わない |
| #289 | [#14017](https://github.com/ghostty-org/ghostty/pull/14017) | swapchain等の解放・再生成と独自タブ通知を調査。GPU実測可否を記録 |

## 検証・完了条件

- 変更ごとの回帰・正常系focused test。可能なものは修正を外した失敗も確認する。
- 最終状態で既存justタスクによるfull test、CI相当lint/test、app build。必要なGitHub checksを確認し、通常merge commitのAutoMergeを使う。
- 性能測定はworkload、build mode、反復条件、before/afterを記録。測定不能や実機未確認は理由を明記する。
- 実装判断・後続差分・検証結果を本Planへ追記し、完成時にdocs/historyへ移動する。
- PRに9件の原因・修正・検証・未確認一覧を載せる。マージ後は完了したIssueに結果記録、wip解除、明示close。未対応は開いたままにする。

## 実装・検証記録

調査・実装に応じて追記する。
