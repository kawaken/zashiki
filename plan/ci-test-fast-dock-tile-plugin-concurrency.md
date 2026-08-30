# CIのjust test-fastがDockTilePlugin.swiftのSwift 6並行性エラーで失敗する

## 経緯

#78 の対応(PR #91)をマージ後、main の CI(`Test` workflow / `just test-fast`)
が失敗していることに気づいた。調査の結果、今回のマージとは無関係の既存の
問題と判明した。

## 症状

CIランナー(Xcode 16.4, Swift 6 モード)で `zig build test -Dmacos-app-xctest=false`
を実行すると、`DockTilePlugin` ターゲットのビルドが以下のエラーで失敗する:

```
Sources/Features/Custom App Icon/DockTilePlugin.swift:73:23: error: sending 'newIcon' risks causing data races
            guard let newIcon else {
~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~
Sources/Features/Custom App Icon/DockTilePlugin.swift:73:23: note: task-isolated 'newIcon' is captured by a main actor-isolated closure. main actor-isolated uses in closure may race against later nonisolated uses
```

Swift 6 の strict concurrency checking によるもの。**ローカル環境(手元の
Xcodeバージョン)では再現しない** ため、これまで見過ごされていた可能性が
高い。

## 発生時期の特定

GitHub Actions の実行履歴を確認したところ:

- `793dc5eb98`(2026-08-29 12:34 のマージ)時点までは成功
- `f9096ab71`(2026-08-30 03:51、PR #89 "just-runner" マージ後)以降は失敗

の間で壊れたとみられる。#78 の対応(PR #91)がこの問題を引き起こしたので
はなく、既存の壊れた main の上にマージされた形になる。

## 検討すべき対応

- `DockTilePlugin.swift:73` 付近の `newIcon` の扱いを Swift 6 concurrency
  ルールに沿って修正する(実際のコード修正)。
- CIランナーとローカルの Xcode バージョン差異を調べ、必要なら `just` タス
  クや CI 設定側で揃える(ローカルで再現しないままだと、今後も同種の問題
  を見落とすリスクがある)。
- なぜ `793dc5eb98` → `f9096ab71` の間で顕在化したのか(CIランナーイメージ
  の更新でXcodeバージョンが上がった可能性が高い)を確認する。

## 参考

- 失敗run: https://github.com/kawaken/zashiki/actions/runs/33294215854
  (マージ後、fe25cbb9)
- 同様に失敗していた過去run: https://github.com/kawaken/zashiki/actions/runs/33291207661
  (f9096ab71)

## 対象外

- #78 で対応した `expectExitCode(0)` 周りの再検討(そちらは既に解決済み)

## 追加調査: 根本原因はXcodeバージョン選択の伝播漏れだった

`DockTilePlugin.swift`側の`nonisolated(unsafe)`修正(PR #94)をCIで検証したところ、
そのエラー自体は解消したが、続けて別のエラーが発生した:

```
Sources/Helpers/Backport.swift:126:19: error: cannot find type 'NSGlassEffectView' in scope
```

`NSGlassEffectView`はmacOS 26 SDKで追加された型で、`@available(macOS 26, *)`
ガードを付けていてもコンパイル時の型解決自体はSDKに依存するため、macOS 26
未満のSDK(Xcode 16.4が同梱するMacOSX15.5.sdk)ではビルドできない。

CIのジョブログを確認すると、`Select Xcode`/`Xcode Version`ステップでは
`DEVELOPER_DIR=/Applications/Xcode_26.3.0.app/Contents/Developer`が正しく
設定され`xcodebuild -version`も`Xcode 26.3`を返しているのに、続く
`just test-fast`ステップの`Command line invocation:`ログでは
`/Applications/Xcode_16.4.app/Contents/Developer/usr/bin/xcodebuild`が
実行されている。

原因は`src/build/ZashikiXcodebuild.zig`の`build`/`xctest`両ステップ:

```zig
// External environment variables can mess up xcodebuild, so
// we create a new empty environment.
const env_map = try b.allocator.create(std.process.Environ.Map);
env_map.* = .init(b.allocator);
if (env.get("PATH")) |v| try env_map.put("PATH", v);
```

`xcodebuild`プロセスに渡す環境を意図的に空にして`PATH`だけコピーしている
ため、`DEVELOPER_DIR`が継承されない。結果、CIが`DEVELOPER_DIR`で選択した
Xcode 26.3.0は無視され、`xcodebuild`はシステムデフォルト(ランナーの
`xcode-select`設定、Xcode 16.4)にフォールバックしていた。

このロジックは2025-10-10の時点(コミット`47f3c946`)から存在しており、
issue #92の「発生時期」調査で見つけた`f9096ab71`(PR #89)前後の変化とは
無関係。おそらく以前は
CIランナーイメージの`xcode-select`デフォルトがXcode 26系だったため
表面化しておらず、ランナーイメージ更新でデフォルトがXcode 16.4になった
ことで、この伝播漏れが初めて問題化したと考えられる(未確認)。

### 対応方針

`ZashikiXcodebuild.zig`の`build`/`xctest`両ステップの`env_map`に
`DEVELOPER_DIR`をPATHと同様に明示的にコピーする。これによりCI側が選択した
Xcodeバージョンが実際に使われるようになり、Xcode 16.4起因のエラー
(Swift 6並行性エラー、`NSGlassEffectView`未定義)がそもそも発生しなく
なるはず。

`DockTilePlugin.swift`の`nonisolated(unsafe)`修正(PR #94)自体はSwift 6の
並行性ルールに沿った正しい修正であり、悪影響もないため維持する
(仮に将来何らかの理由でXcode 16.4が使われても安全になる副次効果がある)。

## 完了後

対応方針が決まり実装・検証が完了したら、この計画を削除し、判断の要点を
`docs/history/`に短い履歴として残す。
