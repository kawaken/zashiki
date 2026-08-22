# Zashiki

## リリース更新（Sparkle）

リリースworkflowはSparkle署名済みの`appcast.xml`をGitHub Releaseへ添付する。
初回リリース前に、Sparkle 2.9.0の`generate_keys`でZashiki専用のEdDSA鍵を生成し、
`generate_keys -x <temporary-file>`でエクスポートした秘密鍵をリポジトリのActions
Secret `SPARKLE_PRIVATE_KEY`へ登録する。秘密鍵をリポジトリやworkflowログに保存してはならない。

公開鍵は`macos/Zashiki-Info.plist`の`SUPublicEDKey`に登録済みである。`generate_appcast`
はCI内でSecretを標準入力から受け取り、前回のstable appcastを引き継いで署名済みの
新しいfeedを生成する。`SUEnableAutomaticChecks`はnotarization完了まで`false`のままにする。

<p align="center">
  <img src="macos/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="Zashiki icon" width="128">
</p>

[@kawaken](https://github.com/kawaken)'s private, macOS-only fork of
[Ghostty](https://github.com/ghostty-org/ghostty).

## Fork-specific features

- **ATOK / Japanese IME preedit styling** — the clause currently being
  converted gets a thicker underline than the rest of the preedit text,
  matching how ATOK itself distinguishes it.
- **Markdown preview pane** — toggle a preview pane (`Cmd+Shift+M`) that
  renders Markdown natively in SwiftUI (no WebKit). Open a file from the
  CLI via a custom `zashiki://` URL scheme (e.g. `open "zashiki://markdown-preview/open?path=<path>&surface=$ZASHIKI_SURFACE_ID"`,
  with `<path>` percent-encoded); the pane live-updates as the file
  changes. The optional `surface` query item (a surface's
  `ZASHIKI_SURFACE_ID` environment variable) targets the exact window
  the request came from; omit it to target the most-recently-active
  window instead. Handy for previewing files an agent like Claude Code
  is writing to.
