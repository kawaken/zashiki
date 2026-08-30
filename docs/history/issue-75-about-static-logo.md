# AboutウィンドウでZashikiのロゴを静的に表示する

- **対応Issue**: [#75](https://github.com/kawaken/zashiki/issues/75)
- **元プラン**: `plan/issue-75-about-static-logo.md`（このドキュメントに統合）

## 背景

Aboutウィンドウのロゴが、表示後に複数のアイコンへ切り替わっていた。Zashikiのロゴだけを静的に表示し、Ghostty由来の不要なロゴがアセットに残っていないか確認した。

## 対応内容

- Aboutウィンドウのアイコン表示を `zashikiIconImage()` に固定した。
- About専用のアイコン切り替え、タイマー、ホバー・クリック操作、アニメーションを削除した。
- `AboutController` からアイコン切り替えの開始・停止処理を削除した。
- 不要になった `AboutViewModel.swift` と `CyclingIconView.swift` を削除した。
- Xcodeアセットを確認したが、Ghostty専用のロゴ画像は見つからなかった。`AppIconImage`、`Alternate Icons`、`Custom Icon` は既存のZashiki機能で使われているため維持した。

## 検証

- `swiftlint lint --strict Sources/Features/About/AboutView.swift Sources/Features/About/AboutController.swift`
  - 違反 0
- `zig build`
  - `BUILD SUCCEEDED`
- About関連ソースに切り替え・タイマー・アニメーションの参照が残っていないことを確認した。

## 実装メモ

`zashikiIconImage()` は実行中アプリの現在のZashikiアイコンを取得し、取得できない場合は `AppIconImage` にフォールバックする。Aboutウィンドウでもこの既存経路をそのまま使うことで、表示時から同じロゴを静的に表示できる。
