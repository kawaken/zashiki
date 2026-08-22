# Zashiki

<p align="center">
  <img src="macos/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="Zashiki icon" width="128">
</p>

[@kawaken](https://github.com/kawaken)による、macOS専用の
[Ghostty](https://github.com/ghostty-org/ghostty)フォークです。アプリ名、Bundle ID、
CLI、設定・リソースの参照先はZashiki向けに分離しています。

## Fork-specific features

- **日本語IME対応** — ATOKなどのpreeditで、変換中の文節を太い下線で表示します。
- **Markdownプレビュー** — `Cmd+Shift+M`でSwiftUIネイティブのプレビューを開きます。
  WebKitを使わず、ファイル変更をライブ反映します。CLIやAIエージェントからは、パスを
  percent-encodeして次のURLを開けます:

  ```sh
  open "zashiki://markdown-preview/open?path=<encoded-path>&surface=$ZASHIKI_SURFACE_ID"
  ```

  `surface`を省略すると、直近アクティブなウィンドウが対象になります。

- **Sparkle更新基盤** — stable feedをGitHub Releaseで配布し、署名済みappcastを生成します。
  自動チェックはDeveloper ID署名・notarization完了まで無効です。

## 開発

macOSアプリのビルドにはXcode、macOS SDK、Metal Toolchainが必要です。

```sh
zig build
zig build -Doptimize=ReleaseFast -Dxcframework-target=native -Demit-macos-app=true
zig build test -Dtest-filter=<test-name>
```

生成物は`zig-out/`にインストールされます。Swift側を含むReleaseビルドはXcodeの
`Zashiki.xcodeproj`を使用します。

## リリース

Release workflowは、`v*.*.*`タグのpush、またはGitHub Actionsの手動実行で起動します。
mainへマージしただけではReleaseは作成されません。手動実行時は`version`入力にタグ相当の
バージョン（例: `v0.3.0`）を指定します。

workflowは`Zashiki-*-macos.zip`と署名済み`appcast.xml`をGitHub Releaseへ添付します。
前回stableのappcastを引き継ぐため、Releaseを実行する前にActions Secret
`SPARKLE_PRIVATE_KEY`が必要です。秘密鍵はリポジトリへ保存せず、Keychain・1Passwordなどで
バックアップしてください。現在はad-hoc署名のためnotarizationされておらず、
`SUEnableAutomaticChecks`も`false`です。
