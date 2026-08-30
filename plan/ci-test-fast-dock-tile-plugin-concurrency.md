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

## 完了後

対応方針が決まり実装・検証が完了したら、この計画を削除し、判断の要点を
`docs/history/`に短い履歴として残す。
