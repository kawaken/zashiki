# RCリリースビルド失敗の修正

## 背景

RCタグ`v0.2.0-rc.3`のRelease workflowは、`zig build test`の後の
`Build Zashiki.app`で失敗した。

失敗ログでは、arm64のmacOS runner上で`-Dxcframework-target=native`を指定して
いるにもかかわらず、Xcodeが`x86_64`向けの`zashiki`もリンクしようとしていた。
native向けに生成される`GhosttyKit.xcframework`はarm64用のため、Xcodeの
デフォルトアーキテクチャ設定と組み合わせるとリンクに失敗する。

また、Tag ReleaseからRelease workflowを起動するとき、Release workflowの
checkout対象が`main`のままになっている。そのため、入力値は
`v0.2.0-rc.3`でもGitのexact tagを検出できず、アプリの
`MARKETING_VERSION`にタグではなくコミット短縮ハッシュが渡される。

## 目的

- native向けRCビルドをrunnerのアーキテクチャだけで確実にビルドする
- アプリ内のバージョンとReleaseタグを一致させる
- 修正後の新しいRCタグで、テスト・ビルド・配布物生成まで確認できるようにする

## 実装内容

### 1. Xcodeのビルドアーキテクチャを明示する

`src/build/ZashikiXcodebuild.zig`を変更する。

- `xcframework-target=native`の場合、`xcodebuild`のbuildステップに
  `ARCHS=arm64`または`ARCHS=x86_64`を追加する
- 同じ指定をmacOS XCTestステップにも追加する
- `xcframework-target=universal`の場合は、既存どおりXcodeの標準設定に任せる
- `-destination platform=macOS,arch=...`はdestinationの選択に使い、
  ビルドアーキテクチャの制約は`ARCHS`で担保する

### 2. Release workflowでリリース対象をcheckoutする

`.github/workflows/release.yml`のcheckoutを、workflow dispatch時の
`inputs.version`、またはタグpush時の`github.ref`を対象にする。

- `workflow_dispatch`で`version=v0.2.0-rc.N`が渡された場合は、そのタグをcheckoutする
- タグpushで起動した場合は、起動元のタグをcheckoutする
- `git describe --exact-match --tags`がタグを認識できるよう、タグ情報を取得する
- `MARKETING_VERSION`が`0.2.0-rc.N`になることをログまたはビルド設定で確認する

この変更では自動更新の有効化やSparkleのチャンネル設計は扱わない。
既存のappcast生成処理も、今回のビルド修正とは分離して維持する。

## 検証

### ローカル

- `zig fmt src/build/ZashikiXcodebuild.zig`
- `zig build test -Dtest-filter=<関連テスト>`
- Apple Silicon環境で`zig build -Doptimize=ReleaseFast -Dxcframework-target=native`
- 生成された`Zashiki.app/Contents/MacOS/zashiki`がarm64のみであることを
  `file`または`lipo -info`で確認する

### GitHub Actions

- `zig build test`が成功する
- `Build Zashiki.app`が成功する
- `MARKETING_VERSION`がRCタグのバージョンになる
- ZIPと署名付きappcastが生成され、GitHub Releaseに添付される
- 既存タグを上書きせず、修正後は次のRC番号（例:`v0.2.0-rc.4`）で実行する

## 対象外

- Sparkle自動更新の完成・自動チェックの有効化
- Developer ID署名・notarization
- universal binaryをRC配布物の必須要件にすること
- 既存の`v0.2.0-rc.3`タグの上書き

## 進捗・判明した事実

- 実装内容1（Xcodeのビルドアーキテクチャ明示）はPR #66で対応済み。
  `ARCHS=`ではなく、`xc_arch`指定時（native）に`ONLY_ACTIVE_ARCH=YES`を
  build/testの両ステップへ追加する方式で解決した。Release
  configurationは元々`ONLY_ACTIVE_ARCH=NO`のため、`-destination`で
  archを絞っても両アーキをリンクしにいってしまうのが原因だった。
- 実装内容2（Release workflowのcheckout対象）は未対応のまま残っていた。
  原因は`.github/workflows/tag-release.yml`の`gh workflow run release.yml
  --ref "${{ github.ref_name }}"`。`github.ref_name`はtag-release.yml自身の
  起動元ref（=main）であり、新規に打ったタグではない。そのため
  release.yml側の`actions/checkout`は常にmainをcheckoutし、
  `git describe --exact-match --tags`がタグを検出できず
  `MARKETING_VERSION`にコミット短縮ハッシュが入っていた。
  `--ref "$TAG"`に修正した。

## 完了後

実装とRC検証が完了したら、このプランを削除する。実装上の判断やCIで得た知見に
記録価値がある場合のみ、`docs/history/`へ短い履歴を残す。
