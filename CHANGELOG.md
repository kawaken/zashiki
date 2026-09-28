# Changelog

## Unreleased

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
