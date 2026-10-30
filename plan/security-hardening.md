# セキュリティ候補9件の統合対応

## 対象と方針

対象: #285、#286、#287、#288、#290、#291、#292、#293、#294。
開始時点のmain: `52746b8ec`。全Issueの本文・コメント・関連PR検索を確認し、
他担当のwip/claimと既存の関連PRがないことを確認した。Codexが各Issueをclaimする。
1タスク、`security-hardening` ブランチ、既存の割当worktree、統合Plan、PR各1つで進める。
Planレビューは実装フローに含める。needs-verificationは付けず、通常のAutoMergeを使う。

静的比較の記述だけでは不具合確定とせず、現行の入口・影響・既存防御を調査する。
Ghosttyのadvisory、修正コミット、関連差分、後続修正を個別に確認し、
ZashikiのZig 0.16.0と既存実装に合わせる。一括マージ、remote追加、画像機能追加はしない。
ATOK文節下線、IME周辺文字列通知、独自タブ管理を維持する。

## 依存関係と対応順

1. #285の貼り付け安全判定を修正し、#286のドロップを既存の保護・エンコード経路につなぐ。
   IME確定入力とドロップは別の入口として検証する。
2. #287のzsh/bash動的通知、#294のファイル実行、#288の端末由来URLを個別に保護する。
   #288のC API種別とSwift判定は同時に変更し、Markdown登録外部アプリと区別する。
3. #292のレイアウト寸法とTerminal初期化を検証し、#291のスクロール領域を制限する。
   tmuxの有無によらずDCSから到達する入力として扱う。
4. #293の画面クリアでページが破棄される場合のstyle/hyperlinkを移行する。
5. #290は一時ディレクトリ境界、open後検証、共有メモリ範囲、画像寸法演算、
   PNG割当制限、配置演算をそれぞれ確認し、独立したコミットに分ける。

## 検証

- 異常入力と正常入力の回帰テストを追加し、可能なものは修正前に失敗を確認する。
- シェル通知はプロセス出力をバイト列として捕捉し、端末へ危険なシーケンスを送らない。
- ファイル・共有メモリ・PNGの再現は隔離テストと専用一時領域に限定する。
- Zig focused tests、Swift unit tests、シェルテスト、`just lint`、`just ci`を実施する。
- UI実機確認をマージ条件にせず、実施していない確認は明記する。
- 各Issueへ個別の到達経路、修正内容、検証結果を記録する。
- 完了時に本Planへ採用コミットと検証記録を追記し、同じPR内でdocs/historyへ移す。
  全チェック・レビュー条件を確認してAutoMerge、マージ後に各Issueへ完了記録、wip解除、closeする。

## 参考

- [貼り付けCR advisory](https://github.com/ghostty-org/ghostty/security/advisories/GHSA-4hwh-wx3w-3fqg) / Ghostty #14687
- [ドロップ advisory](https://github.com/ghostty-org/ghostty/security/advisories/GHSA-v8cw-fg4j-jcc4) / Ghostty #14679
- [シェル通知 advisory](https://github.com/ghostty-org/ghostty/security/advisories/GHSA-2r63-vmw6-3m3c) / Ghostty #14859
- [URL advisory](https://github.com/ghostty-org/ghostty/security/advisories/GHSA-cw69-wm67-5pv8)
- [Kitty advisory](https://github.com/ghostty-org/ghostty/security/advisories/GHSA-mhff-mv4q-fp63)
- Ghostty [#14680](https://github.com/ghostty-org/ghostty/pull/14680)、[#14858](https://github.com/ghostty-org/ghostty/pull/14858)、[#14857](https://github.com/ghostty-org/ghostty/pull/14857)、[#14688](https://github.com/ghostty-org/ghostty/pull/14688)

## 調査・実装記録

実装と検証の進行に合わせて追記する。
