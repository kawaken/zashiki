# Changelog

## Unreleased

- タブをウィンドウの中で管理するように変更。左右のパネル（Worktree Status / Agents / Markdownプレビュー）はウィンドウに1つになり、タブバーはその間に表示される
- Markdownプレビューの開閉をウィンドウ単位に変更。表示するファイルと履歴はタブごとで、タブを切り替えるとそのタブのファイルに切り替わる
- macOS標準のタブ機能（タブのドラッグによるウィンドウ間の移動・切り離し、「すべてのウィンドウを統合」）は使えなくなった

## v0.8.0 (2026-10-10)

- `zashiki +markdown-preview`がプレビューを開いた結果を確認し、成功・失敗をメッセージと終了コードで呼び出し元へ返すように
- Markdownプレビューへフォーカスを移すと文字サイズが変わる問題を修正
- AboutダイアログのBuild番号の表示を削除
- Undo履歴を消去するとクラッシュする問題を修正

## v0.7.0 (2026-10-07)

- ウィンドウ上部の見た目を切り替える設定（`macos-titlebar-style`、`window-decoration`、`macos-non-native-fullscreen`、`macos-window-buttons`、`macos-titlebar-proxy-icon`）と、キーバインド用アクション `toggle_window_decorations` を廃止。見た目は従来の既定値に固定
- タイトル横のフォルダアイコン（プロキシアイコン）を表示しないように。タイトルを右クリックして表示するフォルダ階層のメニューも出さないように
- `fullscreen` 設定の値を `true` / `false` のみに変更（`non-native` などの値は廃止）
- Markdownプレビューの文字サイズを、ターミナルとは別に調整・リセットできるように
- 履歴を戻っても、その後に開いたファイルの履歴が消えないように修正
- 長いMarkdown文書のスクロールを改善
- プレビュー中のファイルをFinderで表示できるようにし、ファイル選択機能を廃止
- Markdownプレビューの履歴一覧を新しい順に表示

## v0.6.0 (2026-10-01)

- Markdownプレビューの履歴を一覧表示し、開いたファイルへ直接戻れるように
- Markdownプレビューの外部リンクをブラウザで開き、ページ内リンクから該当する見出しへ移動できるように
- Markdownプレビューの本文とFrontMatterの文字サイズが、ターミナルの文字サイズに追従するように
- Markdownプレビューのファイル名にカーソルを合わせると、フルパスを表示するように
- Markdownプレビューの履歴切り替え時の重複読み込みを減らし、表示速度を改善
- Markdownプレビューでコピーのショートカットが引き続き効かない問題を再修正

## v0.5.0 (2026-09-28)

- MarkdownプレビューでFrontMatter(`---`で囲まれたメタデータ)をキー・バリューのテーブルとして表示するように
- Markdownプレビューに戻る/進むの履歴ナビゲーションを追加
- Markdownプレビューのヘッダーからファイルを選択して切り替えられるように
- Markdownプレビューのパネル内でコピーのショートカットが効かない不具合を修正

## v0.4.0 (2026-09-10)

- Worktree StatusとAgentsの状態をウィンドウ内のタブ間で共有し、Agents一覧から別タブ・分割ペインへ移動できるように
- Agentの会話履歴をSurface内のレールとして表示し、該当する会話位置へ移動できるように
- Worktree StatusとAgentsを個別に表示・非表示できるようにし、両方をサイドパネル内で分割表示できるように
- Agentsの確認待ち・作業中・アイドル状態の検出精度を改善
- Worktree Statusから、フォーカス中のWorktreeを含む不要なWorktreeを正しく削除できるように修正
- Worktree Statusのツールチップが行全体で表示されるように修正

## v0.3.1 (2026-09-06)

- Worktree Statusのアイコン・状態表示でホバーツールチップが表示されるように修正
- Claude CodeのIdle / Waiting状態を正しく検出し、状態判定の誤表示を修正
- `gw` GitHub PR status schema v2に対応
- Worktree StatusのCmd+Yショートカットを追加

## v0.3.0 (2026-09-04)

- `gw` Worktree Statusサイドパネルを追加し、worktreeの状態確認と`gw clean`の実行に対応
- GitHub PRを`#123`形式のリンクとして表示
- Aboutウィンドウの不要なDocsボタンを削除
- Worktree Statusの各アイコン・状態表示に詳細なホバーツールチップを追加
- Claude Code / CodexのAgent状態をWorktree Statusに表示し、対象Surfaceへフォーカスできるように

## v0.2.1 (2026-08-31)

- Aboutウィンドウで表示されていたGhosttyロゴへの切り替えアニメーションを廃止し、Zashikiロゴに固定
- Alternate Iconsなどに残っていたGhostty由来のアイコンアセットを削除

## v0.2.0 (2026-08-28)

- IMEへ周辺文字列を提供し、ATOKなどでより正確な変換ができるように
- Markdownプレビューをコマンドラインから起動できるように（`zashiki +markdown-preview <file>`）
- Sparkleによる自動更新の土台を整備（現状は手動ダウンロードのみ）
- UI・CLI表記のGhostty→Zashiki置換を完了
- gettextベースの多言語対応(i18n)・manページ生成・Linux専用設定を削除

## v0.1.0 (2026-08-12)

- Ghosttyの個人用macOSフォークとして開始（アプリ名をZashikiに変更）
- ATOKなど日本語IME向けに、変換中の文節を太い下線で強調表示
- Markdownプレビューペイン機能を追加（`Cmd+Shift+M`）
- Linux/GTK向けコードを削除
