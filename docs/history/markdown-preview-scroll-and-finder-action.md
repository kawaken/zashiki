# Markdownプレビューのスクロール改善とFinder操作

## 対象

- Issue #249: Markdownプレビューのスクロール処理が遅い
- Issue #250: ファイルを選んでプレビューする操作をFinder表示に置き換える

## 調査結果

- `MarkdownPreviewPane`は全ての見出しセクションを通常の`VStack`で生成している。長い文書では、画面外の`StructuredText`まで一度に構築するため、スクロール時の負荷が増える。
- ヘッダーのフォルダボタンと空状態のボタンが`NSOpenPanel`を開き、プレビュー対象のファイルを選ぶ機能になっている。Issue #250はこの導線をやめ、表示中のファイルをFinderで選択する操作を求めている。

## 方針

- セクションの表示コンテナを`LazyVStack`にして、必要なセクションをスクロールに応じて構築する。
- 履歴セクションIDとページ内リンクの`ScrollViewReader`動作は維持する。
- ヘッダーのフォルダボタンは`NSWorkspace.activateFileViewerSelecting`で表示中のファイルをFinder上で選択する。
- プレビュー内のファイル選択パネル導線を取り除き、ファイルが未選択ならFinderボタンを無効化する。

## テスト・検証

- `just lint`と`just test`を実行する。
- 長いMarkdownでLazyVStackを使う構成と、表示中ファイルをFinderで開く導線をCI成果物で確認する。

## 実装記録

- 本文の見出しセクションを`LazyVStack`で表示し、画面外の`StructuredText`を一度に構築しないようにした。
- フォルダボタンは表示中のMarkdownをFinder上で選択する操作に変更した。ファイル未選択時は無効化する。
- ヘッダーと空状態から`NSOpenPanel`を開く導線を削除した。
- `just lint`とmacOS XCTestを含む`just test`は成功。
- スクロール負荷とFinder操作の実機確認はCI artifactで行う。
