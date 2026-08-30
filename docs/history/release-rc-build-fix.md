# RCリリースビルド失敗の修正

- **Issue**: [#82](https://github.com/kawaken/zashiki/issues/82)
- **元プラン**: `plan/release-rc-build-fix.md`（このドキュメントへ移行）

## 実施内容

RCタグのRelease workflowで発生していた2つの問題を、別々のPRで修正した。

1. **Xcodeビルドアーキテクチャの不一致**（PR #66）
   `-Dxcframework-target=native`はホストアーキ（arm64）のみで
   `GhosttyKit.xcframework`をビルドするが、Release configurationは元々
   `ONLY_ACTIVE_ARCH=NO`のため、`-destination`でarchを絞っても
   x86_64向けリンクを試みてシンボル未解決で失敗していた。
   `ARCHS=`指定ではなく、native時に`ONLY_ACTIVE_ARCH=YES`を
   xcodebuildのbuild/testステップへ追加する方式で解決した。

2. **Release workflowのcheckout対象がmainのまま**（PR #87）
   `tag-release.yml`が`gh workflow run release.yml --ref
"${{ github.ref_name }}"`としていたが、`github.ref_name`は
   tag-release.yml自身の起動元ref（=main）であり、新規に打った
   タグではなかった。そのためrelease.yml側のcheckoutは常にmainを
   対象にし、`git describe --exact-match --tags`がタグを検出できず
   `MARKETING_VERSION`にコミット短縮ハッシュが渡っていた。
   `--ref "$TAG"`に修正した。

## Planとの差分・検証

Planでは実装内容1を`ARCHS=arm64`/`ARCHS=x86_64`指定として設計していたが、
実際には`ONLY_ACTIVE_ARCH=YES`の方が変更が小さく、同じ問題を解決できた。

修正後、`v0.2.0-rc.4`を実際に発行してGitHub Actions上で検証した。

- `zig build test`（xcodebuild testを含む）が成功
- `Build Zashiki.app`が成功
- checkoutログで`refs/tags/v0.2.0-rc.4`が対象になっていることを確認
- `MARKETING_VERSION=0.2.0-rc.4`がxcodebuildに渡っていることをログで確認
- `Zashiki-v0.2.0-rc.4-macos.zip`と`appcast.xml`がGitHub Releaseに添付された
- 既存の`v0.2.0-rc.3`タグは上書きしていない

ローカルでの`lipo -info`によるarm64単一アーキテクチャの確認はPR #66の
作業時に実施済み。今回はCI経由の検証のみ行った。
