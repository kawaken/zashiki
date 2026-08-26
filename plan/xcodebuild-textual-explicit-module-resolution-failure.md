# ローカルxcodebuildがTextual依存のexplicit module解決で失敗する

## 発見の経緯

`plan/ime-surrounding-text.md`のフェーズ0（IME観測用ログ計装）作業中、実機確認の
ためにZashiki.appをビルドしようとしたところ、`zig build`が呼ぶxcodebuildが
毎回同じエラーで失敗することに気づいた。IME側のコード変更（`SurfaceView_AppKit.swift`
へのログ追加のみ）とは無関係で、`main`をそのままビルドしても再現する。

## 現状

`zig build`（内部で`xcodebuild -project Zashiki.xcodeproj -scheme Zashiki
-configuration Debug ... -destination platform=macOS`を実行）が以下で失敗する:

```
/…/DerivedData/Zashiki-*/SourcePackages/checkouts/textual/Sources/Textual/Internal/Attachment/MathAttachment.swift:2:31: error: unable to resolve module dependency: 'SwiftUIMath'
@_spi(Textual) private import SwiftUIMath

/…/DerivedData/Zashiki-*/SourcePackages/checkouts/textual/Sources/Textual/Internal/Font/AnyFontProvider+Font.swift:1:8: error: unable to resolve module dependency: 'ConcurrencyExtras'
import ConcurrencyExtras
```

失敗するビルドコマンドは`SwiftDriver Textual`（依存関係スキャン段階）。`SwiftUIMath`
と`ConcurrencyExtras`自体は同じビルド内で正常にコンパイルされ`EmitSwiftModule`まで
成功しているのに、`Textual`ターゲットの依存関係スキャンがそれらの`.swiftmodule`を
見つけられない。

## 再現条件

- **`main`ブランチをそのままビルドしても再現する**（コード変更は無関係）
- **全worktree共通で再現する。** 検証用に`origin/main`から新規worktreeを作り
  （新規DerivedData、`Zashiki-aaonsnfunajcqkbpeatwzoanzfhx`）ビルドしても同じ
  エラーが出た。特定のworktree・DerivedDataディレクトリの破損ではない
- Swiftコード自体のエラーではない（`SwiftUIMath`/`ConcurrencyExtras`のコンパイルは
  成功している）

## 試したが直らなかったこと

- `~/Library/Developer/Xcode/DerivedData/Zashiki-*`の削除→`zig build`での再生成
- `SourcePackages`のみ削除して`xcodebuild -resolvePackageDependencies`で
  パッケージを取り直す（`Package.resolved`のpinは正常な内容だった）
- `xcodebuild clean`
- `SWIFT_ENABLE_EXPLICIT_MODULES=NO`をビルド引数に追加（同じ`no such module`
  エラーで失敗。SPMパッケージターゲットのビルド設定はXcodeプロジェクト側の
  コマンドライン引数を継承しない可能性がある）
- `-jobs 1`でのシリアルビルド（並列スケジューリングのレースではないことを確認）

## 環境情報

- macOS 26.5.2 (25F84)
- Xcode 26.6 (Build 17F113)、SDK: MacOSX26.5.sdk
- Zig 0.16.0 (Homebrew)
- 依存パッケージ（`Package.resolved`）: textual 0.5.0, swiftui-math 0.1.0,
  swift-concurrency-extras 1.4.1, Sparkle 2.9.0

## CIとの差異（確認済み）

`.github/workflows/test.yml`は`macos-15`ランナー上で`/Applications/Xcode_26*.app`を
明示的に選択している。直近の`main`へのCI成功実行（`gh run view <id> --log`、
2026-08-26T02:39 UTC完了分）を確認したところ:

- **CI: Xcode 26.3 (Build 17C529)**
- **ローカル: Xcode 26.6 (Build 17F113)**

マイナーバージョンが3つ分ずれており、CIは成功しているのにローカルだけ失敗する
現象と整合する。**ローカルのXcode 26.6でexplicit module buildに関する回帰が
入っている可能性が高い**というのが現時点の最有力仮説。

## 次の調査候補

- ~~CIで実際に使われているXcodeのマイナーバージョンを確認する~~ → 確認済み（上記）
- Xcode 26.3相当の旧バージョンをローカルに追加インストールして再現するか確認する
  （容量が大きいツールなので、実施前にユーザーに確認する）
- Apple Developer Forums / Feedback AssistantでXcode 26.4〜26.6の
  explicit module build回帰が報告されていないか確認する
- Textual / SwiftUIMath / swift-concurrency-extras のGitHubリポジトリで
  Xcode 26.6 + explicit module buildに関する既知issueがないか確認する
- `xcodebuild`の`-showBuildTimingSummary`や`-verbose`でモジュールスキャンの
  詳細ログを取り、`SwiftUIMath.swiftmodule`の実際の出力パスと`Textual`側が
  探索しているパスの不一致を確認する

## 影響

- ローカルでのZashiki.appビルド・実機確認ができない状態。IME周辺文字列対応
  （`plan/ime-surrounding-text.md`）のフェーズ0はこれにブロックされて保留中
- CIは`zig build test -Demit-macos-app=false ...`ではなく通常のSwiftビルドを
  行っており（`plan/ci-macos-build-and-test-verification.md`参照）、少なくとも
  最近のCI実行では成功している。ローカル固有の問題である可能性が高い
