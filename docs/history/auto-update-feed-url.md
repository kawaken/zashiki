# AutoUpdateのfeed URL・署名鍵切り替え

- **実施ブランチ**: `auto-update-sparkle`
- **元プラン**: `plan/auto-update-feed-url.md`（このドキュメントへ移行）

## 実施内容

- stable用feed URLをGhosttyのサーバーからGitHub Releaseの固定URLへ変更した。
  `https://github.com/kawaken/zashiki/releases/latest/download/appcast.xml`
- tip用feedはまだ提供しないため、Zashikiの存在しないGitHub Release URLを返すようにした。
- Sparkle EdDSA鍵をZashiki用に新規生成し、公開鍵を`Zashiki-Info.plist`へ登録した。
  秘密鍵はKeychain、GitHub Actions Secret `SPARKLE_PRIVATE_KEY`、1Passwordへ保管した。
- Release workflowに`generate_appcast`のビルド・署名・GitHub Releaseへの添付を追加した。
  前回stableのappcastを取得して履歴を引き継ぎ、秘密鍵は標準入力から渡す。
- `SUEnableAutomaticChecks`は、Developer ID署名とnotarizationが完了するまで`false`のまま維持する。
- リブランド後も残っていた古い`Ghostty.xcodeproj`によるXcodeのプロジェクト自動選択を避けるため、
  `ZashikiXcodebuild.zig`のbuild/test両方で`Zashiki.xcodeproj`を明示指定した。
- `generate_appcast`の出力先を明示し、CI作業ディレクトリへ誤出力されないようにした。

## Planとの差分・検証

PlanではSecrets登録を手動作業としていたが、実際にはユーザー確認のもとでGitHub Secret登録まで完了した。
Apple Developer Program登録、Developer ID署名、notarization、tip/nightly feedの提供、
`SUEnableAutomaticChecks=true`への変更は実施していない。

クリーンなZashiki.appをReleaseLocal構成でビルドし、`codesign --verify --deep --strict`を通過した。
そのアーカイブからKeychainのEdDSA鍵で`generate_appcast`を実行し、`sparkle:edSignature`を含む
appcastが生成されることを確認した。GitHub Releaseの実運用検証はmainへのマージ後に行う。
