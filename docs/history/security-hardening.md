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

- #285: Surface.completeClipboardPasteからisSafeへ到達し、非bracketed時のCRが通る。
  保護設定の意味を維持して判定をisSafeWithへ集約し、CR/LF/CRLF/終端/日本語を検証する。
- #286: performDragOperationはinsertTextを直接呼んでいた。IMEのinsertTextを変更せず、
  明示テキスト用C APIを追加して既存completeClipboardRequestへ接続する。
  現行APIは旧形式なのでGhostty #14679の新しいclipboard content構造体は採用しない。
  標準Zigテストはstandalone runtimeでembedded moduleを参照していなかった。
  単純なmodule参照ではruntime型が合わないため、macOS用embeddedテスト入口を追加する。
  本番と同じruntimeのメモリ内surface・通知キューでC APIをテストし、PTYは作らない。
  参照前のfocused実行はAPIテスト成功という根拠には含めない。
- #287: zsh cwdは展開ありprint、bash cwdは制御文字未除去。コマンドtitleは既に除去するが、
  cwd由来titleも別途監査する。Ghostty #14859を個別採用する。
  実際のbashプロンプト展開を捕捉するテストで、PS1の`\w`によるcwdタイトルにも
  生のESC/BELが入りOSCフレームが壊れることを確認した。cwdタイトルはprecmdで
  制御文字を除去して通知する。zshのcwdタイトルにも明示的な除去を適用する。
- #288: OSC 8だけでなくunknownもNSWorkspaceへ直接渡る。
  Ghostty #13634と後続#14683を組み合わせ、generic openerもfail closedにする。
- #291/#292: DCS 1000pからtmux viewerへ入り、ペイン状態・レイアウトが端末出力だけで到達する。
  Ghostty #14858のsnapshot変更はZashikiにその機能がないため対象外。
  新規だけでなく既存ペインの過大寸法もコピー前に拒否する。
  #14680のテストは上流の初期画面選択修正を前提としていたため、現行では
  pane-stateで更新されるprimaryカーソルを確認し、別にactive出力のスクロールも検証する。
- #293: #14857は#14686のcursorPageReplacedに依存する。現行には後者もないため、
  単一行の通常スクロール時のページ破棄修正と回帰テストも必要な依存として採用する。
- #294: openFileからquoteしたパスがinitialInputへ入る。C0/DEL/C1をquote前に拒否する。
- 初回ZigテストはMetal Toolchain不足でテスト本体に到達せず失敗。成功扱いしない。
- #290: `af2faa311a`（ディレクトリ境界）、`ec04900ab9`（open後検証）、
  `f766f303a7`（共有メモリ）、`590d669c4a`（PNG）、`e5840bb9ba`（配置）を確認。
  画像寸法は上限確認後に乗算し、PNGデコーダの個別割当を400MiB以下へ制限する。
  新しい画像C API・animation・relative placementは採用しない。
  現行renderer/image.zigの可視判定はpage pinからの矩形を使い、上流C APIのi32加算は存在しない。
  macOS一時ディレクトリの別名に関する後続修正#14569も確認する。
  open後検証は一時領域内の2ファイルとsymlink差替えでハンドルの同一性をテストし、
  デバイスのblocklistは文字列テストで分離する。特殊ファイルを開く再現は行わない。

## 採用元の記録

| 対象 | 確認したGhosttyコミット（該当部分のみ採用） |
| --- | --- |
| #285 | `cc53940b4c` (#14687) |
| #286 | `c440e5b946` (#14679)、旧clipboard APIに適合 |
| #287 | `ebd449995d` (#14859)、bash cwdタイトル経路も追加修正 |
| #288 | `54fe8e1885` (#13634) と後続 `0125483678` (#14683) |
| #290 | `af2faa311a`、`ec04900ab9`、`f766f303a7`、`590d669c4a`、`e5840bb9ba`、後続 `3fe938dbc8` (#14569) |
| #291 | `bc2cf6fd79` (#14680)、テストの画面選択は現行に適合 |
| #292 | `bf14ea1fbd` (#14858)、既存ペインもサイズ検証 |
| #293 | 依存 `7db25f9f3d` (#14686) と `1c2ea72225` (#14857) |
| #294 | `827d5c8294` (#14688) |

## 回帰検出力の確認

各修正に対応する保護を一時的に無効化し、検証後に必ず復元した。
CR判定、ドロップの確認要求、元のzsh/bash通知、URLファイル拒否、制御文字判定、
tmux領域・ゼロ寸法拒否、scrollClearのページ移行を外すと、対応する回帰テストが失敗した。
Kittyはパス境界、共有メモリの範囲超過、PNG割当上限の各テストで失敗を確認した。
PNGの保護を外す検証には失敗する下位allocatorと偽デコーダだけを使い、巨大画像の実割当は行っていない。
scrollClearは隔離プロセスの整合性assertとhyperlinkテストで問題を再現した。

共有メモリの移植テストは当初offset超過のみを検証していた。
sizeが残り領域を超えるケースでは保護を外しても成功してしまったため、
明示size・暗黙rawサイズ・PNG末尾・400MiB超過の検証を追加し、再度失敗を確認した。

## 検証と残る確認範囲

- CR・bracketed paste、pane-state正常/異常領域、scrollClearのfocusedテストが成功。
- embedded runtimeのC APIテストを実際に含む実行で130/130件が成功。
- zsh/bashの通知を捕捉する2テスト（日本語、空白、literal backslash、C0/DEL/C1）が成功。
  このテストを`just test`と`just test-fast`にも接続した。
- SwiftのURL安全ポリシー・両リンク種別・キャンセル・通常パス・制御文字テストが成功。
  既存のIME・Markdown外部アプリ・タブ管理の単体テストも成功した。
- `just lint`と`just --fmt --check`が成功。最終コミットの全体テストとCIの結果は
  統合PR #313の検証欄・GitHub Checksへ記録する。
- 初回のMetal Toolchain不足は解消後に再実行した。初回の失敗は成功件数に含めない。
- 実ドラッグ、ATOK/IMEの実操作、外部アプリの実起動、実在tmuxへの接続、画像の実画面表示、
  任意タイミングのファイル差替え競合は実機確認していない。
  安全性の検証はプロセス内通知キュー、Swift判断と起動callback、端末状態、専用一時領域で行った。
  これらの実機確認をマージ条件にせず、needs-verificationを付けない。
