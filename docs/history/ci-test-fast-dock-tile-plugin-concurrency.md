# CIのjust test-fastがDockTilePlugin.swiftのSwift 6並行性エラーで失敗する

## 発見の経緯

#78 の対応(PR #91)をマージ後、main の CI(`Test` workflow / `just test-fast`)が
失敗していることに気づいた。調査の結果、今回のマージとは無関係の既存の問題と
判明した。

## 症状

CIランナー(Xcode 16.4, Swift 6 モード)で `zig build test -Dmacos-app-xctest=false`
を実行すると、`DockTilePlugin` ターゲットのビルドが以下のエラーで失敗する:

```
Sources/Features/Custom App Icon/DockTilePlugin.swift:73:23: error: sending 'newIcon' risks causing data races
```

Swift 6 の strict concurrency checking によるもの。**ローカル環境(手元の
Xcode 26系)では再現しない**ため、これまで見過ごされていた。

`DockTilePlugin.swift`側を`nonisolated(unsafe)`で修正(PR #94)してCIで
再検証したところ、このエラーは解消したが、続けて別のエラーが発生した:

```
Sources/Helpers/Backport.swift:126:19: error: cannot find type 'NSGlassEffectView' in scope
```

`NSGlassEffectView`はmacOS 26 SDKで追加された型で、`@available(macOS 26, *)`
ガードを付けていてもコンパイル時の型解決自体はSDKに依存するため、macOS 26
未満のSDK(Xcode 16.4が同梱するMacOSX15.5.sdk)ではビルドできない。この2つ目の
エラーが、根本原因の発見につながった。

## 原因(判明)

CIのジョブログを確認すると、`Select Xcode`/`Xcode Version`ステップでは
`DEVELOPER_DIR=/Applications/Xcode_26.3.0.app/Contents/Developer`が正しく
設定され`xcodebuild -version`も`Xcode 26.3`を返しているのに、続く
`just test-fast`ステップの`Command line invocation:`ログでは
`/Applications/Xcode_16.4.app/Contents/Developer/usr/bin/xcodebuild`が
実行されていた。

原因は`src/build/ZashikiXcodebuild.zig`の`build`/`xctest`両ステップ。
「外部環境変数がxcodebuildに悪影響を与えうる」という理由で、xcodebuildを
呼ぶ`RunStep`には`PATH`だけをコピーした空環境を渡していた
(2025-10-10、コミット`47f3c946`から存在するロジック)。この結果
`DEVELOPER_DIR`が継承されず、CIが明示的に選んだXcode 26.3.0は無視されて
`xcodebuild`はシステムデフォルト(ランナーの`xcode-select`設定、Xcode 16.4)
にフォールバックしていた。DockTilePluginの並行性エラーも`NSGlassEffectView`
未定義エラーも、どちらもこの「意図しないXcode 16.4が使われている」ことの
症状に過ぎなかった。

issue #92の「発生時期」調査で見つけていた`f9096ab71`(PR #89)前後の変化との
関連は確認できなかった。おそらく以前はCIランナーイメージの`xcode-select`
デフォルト自体がXcode 26系だったため表面化しておらず、ランナーイメージ更新で
デフォルトがXcode 16.4になったことで、この伝播漏れが初めて問題化したと
考えられる(未確認)。

## 対応(実施済み)

1. `DockTilePlugin.swift`の`NSDockTile.setIcon(_:)`: `DispatchQueue.main.async`
   クロージャにキャプチャする`newIcon: NSImage?`(非Sendable)を
   `nonisolated(unsafe)`のローカル変数に取り出してから渡すよう変更(PR #94)。
   Swift 6の並行性ルールに沿った修正で、根本原因とは別に単体でも正しい直し方。
2. `ZashikiXcodebuild.zig`の`build`/`xctest`両ステップの`env_map`に、`PATH`と
   同様に`DEVELOPER_DIR`を明示的にコピーする行を追加(PR #94)。CI側で選択した
   Xcodeバージョンが実際に`xcodebuild`へ伝わるようになった。

両方とも同一PR(#94)でCI(Xcode 16.4ランナー)上でグリーンになることを確認済み。
マージ後のmain上のCIも成功を確認済み。ローカル(Xcode 26.6)では元々どちらの
エラーも再現しないため、修正の妥当性はCI側でのみ検証できた。

## 影響

- CIの`just test-fast`が再びグリーンになった。
- `DEVELOPER_DIR`伝播漏れは`build`/`xctest`両方の`xcodebuild`呼び出しに
  共通する問題だったため、明示的なXcodeバージョン選択に依存する他のCI
  ジョブ(将来`workflow_dispatch`の`build`ジョブなど)でも同様の問題が
  未然に防がれるようになった。
