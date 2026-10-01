# Markdownプレビューのリンク操作

## 対象

- Issue #223

## 調査結果

Textualの`StructuredText`はリンククリックをSwiftUIの`openURL`環境値へ渡せる。外部URLを既定のブラウザへ開く処理はZashiki側で追加できる。一方、Textualは見出しへのスクロール用IDを公開していないため、Markdown本文を見出し単位の`StructuredText`へ分割し、SwiftUIの`ScrollViewReader`で見出しslugへ移動する。

## 方針

- `http`などの外部URLは`NSWorkspace`で既定のアプリ（Web URLなら既定のブラウザ）へ渡す。
- 現在表示中のMarkdownを指すフラグメントリンクは、見出しから生成したslugへスクロールする。
- 見出しはGitHub互換のslug、重複時は`-1`以降の連番で解決する。
- フェンス付きコードブロック内の見出し風テキストは分割対象にしない。
- 実機でのクリック確認はリリース後に行うため、CI通過後にマージする。

## 実装内容

- Markdown本文を見出し単位に分割する`MarkdownPreviewDocument`を追加。
- `MarkdownPreviewPane`を`ScrollViewReader`構成にし、Textualの`openURL`を処理。
- 外部URLを`NSWorkspace.shared.open`で開き、ローカルのページ内リンクを対象見出しへ移動。
- 見出しslug生成、重複見出し、コードフェンス、明示アンカーのユニットテストを追加。

## テスト・検証

- `MarkdownPreviewModelTests`で分割とアンカー生成を確認する。
- `just lint`とCIの`just test-fast`を実行する。
- 実機確認はリリース後に行う。

## 正式リリース準備での検証結果

- PRの`just test-fast`はSwiftコンパイルまでで、macOS XCTestは実行しない。
- v0.6.0のRelease workflowのフルテストで、明示アンカーのテストだけが失敗した。
- Markdown本文の末尾改行を分割処理が保持する一方、テストの期待値が末尾改行を含んでいなかった。アンカー生成の失敗ではない。
- 実装は変更せず、テストで末尾改行あり・なしの両方を検証するようにし、それぞれの本文が保持されることを確認する。

## 対象外

- Markdownファイル間のアプリ内遷移。
- 外部サイト側のフラグメントへのアプリ内スクロール。
- #224の履歴UI変更。
