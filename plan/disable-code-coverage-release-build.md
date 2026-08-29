# ReleaseLocalビルドのコードカバレッジ無効化

## 背景

macOSアプリのビルド後、実行した作業ディレクトリにLLVMのプロファイル
データファイル`default.profraw`が生成されることがある。

リポジトリ内のZigコード、Xcodeプロジェクト設定、CI設定には、コードカバレッジを
明示的に有効化する設定は存在しない。一方、共有Xcodeスキームではアプリが
profiling対象として指定されており、`ReleaseLocal`を使うビルドの実リンクコマンドに
`-fprofile-instr-generate`が追加されていることを確認した。このフラグがLLVMの
プロファイルランタイムをリンクし、実行終了時に既定名の`default.profraw`を生成する。

Xcodeの設定はClang系とSwift系で分かれているため、片方だけを無効化すると計測が
残る可能性がある。

## 目的

- 通常の`ReleaseLocal`アプリビルドでコードカバレッジ計測を無効化する
- `default.profraw`を通常のアプリ実行で生成しない
- XCTestやXcodeの明示的なprofiling用途とは設定を混同しない

## 実装内容

### 1. ReleaseLocalの設定を明示する

`macos/Zashiki.xcodeproj/project.pbxproj`の`ReleaseLocal`設定に以下を追加する。

- `CLANG_ENABLE_CODE_COVERAGE = NO`
- `SWIFT_ENABLE_CODE_COVERAGE = NO`

これを設定ファイル上の通常ビルドの既定値にする。

### 2. Zigからの通常ビルド経路を分離する

`src/build/ZashikiXcodebuild.zig`の通常アプリビルド用`xcodebuild`呼び出しは scheme
ではなく`Zashiki` targetを直接指定し、以下をビルド設定として渡す。

- `CLANG_ENABLE_CODE_COVERAGE=NO`
- `SWIFT_ENABLE_CODE_COVERAGE=NO`

scheme経由では上記設定を`NO`にしてもリンク時に計測フラグが残るため、通常ビルドと
profiling/test操作の経路を分離する。`xcodebuild test`側の設定は今回変更しない。

### 3. profiling用途は対象外にする

`ProfileAction`と`buildForProfiling`は変更しない。Xcodeから明示的にプロファイリングを
実行する用途を残し、今回の変更対象は通常のアプリビルドに限定する。

## 検証

### 静的確認

- `git grep`でcoverage設定とプロファイルフラグの意図しない残存を確認する
- `xmllint --noout macos/Zashiki.xcodeproj/xcshareddata/xcschemes/Zashiki.xcscheme`
- `plutil -lint macos/Zashiki.xcodeproj/project.pbxproj`
- `zig fmt --check src/build/ZashikiXcodebuild.zig`

### ビルド・実行確認

- `zig build -Demit-macos-app=false`
- macOSアプリのクリーンビルドを実行する
- verboseなリンクコマンドに`-fprofile-instr-generate`がないことを確認する
- 生成されたアプリを実行し、`default.profraw`が生成されないことを確認する
- `zig build test`でZigテストと既存のmacOSテストビルドが壊れていないことを確認する

## 対象外

- XCTestのカバレッジ計測方針の変更
- Xcodeの明示的なProfile/Instruments実行の機能削除
- 既存の`default.profraw`ファイルの自動削除

## 完了後

実装と検証が完了したら、このプランを削除する。通常ビルドとprofiling用途の挙動に
差が残る場合のみ、判断内容を`docs/history/`へ記録する。
