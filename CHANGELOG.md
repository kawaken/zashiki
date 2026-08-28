# Changelog

Zashiki（[@kawaken](https://github.com/kawaken)によるGhosttyの個人用macOSフォーク）の
リリースごとの変更点。README.mdに載せるほどではない細かな修正・削除も含め、
ユーザーに影響のある変更をここに記録する。

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
