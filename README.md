# Zashiki

<p align="center">
  <img src="macos/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="Zashiki icon" width="128">
</p>

[@kawaken](https://github.com/kawaken)による、macOS専用の
[Ghostty](https://github.com/ghostty-org/ghostty)フォークです。

## 特徴的な機能

- **日本語IME対応** — ATOKなどのpreeditで、変換中の文節を太い下線で表示します。また
  `NSTextInputClient`経由で現在の行に入力済みの周辺文字列をIMEに渡すことで、
  ATOKなどの変換精度を改善します。
- **Markdownプレビュー** — `Cmd+Shift+M`でSwiftUIネイティブのプレビューを開き、
  ファイル変更をライブ反映します。

リリースごとの変更点は[CHANGELOG.md](CHANGELOG.md)を参照してください。

## 開発

開発用のビルド・テスト・Lint・整形コマンドは、リポジトリ直下の
`justfile` にまとめています。macOS では Homebrew で `just` を導入してから、
`just` または `just help` で利用可能なタスクを確認してください。

```sh
brew install just
just build
just test-fast
just lint
```

`just test-fast` は PR 向けのテストと Swift コンパイル、`just test` は macOS
XCTest を含むフルテストを実行します。特定の Zig テストだけを実行する場合は
`just test-filter "テスト名"` を使ってください。Xcode を切り替える場合は、
システム設定を変更せず `DEVELOPER_DIR` を指定できます。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer just test-fast
```
