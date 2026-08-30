# 内部に残るGhosttyロゴを削除する

## 背景

Aboutウィンドウの対応後も、XcodeアセットにGhostty由来のロゴ画像が残っていた。対象は旧標準アイコンの `AppIconImage.imageset`、アーティスト作成の `Alternate Icons`、`custom-style` の幽霊レイヤー `CustomIconGhost.imageset/ghosty.png` である。

## 実装

- `AppIconImage.imageset`、`Alternate Icons`、`CustomIconGhost.imageset` を削除した。
- `macos-icon` のGhostty派生バリアントと `macos-icon-ghost-color` を削除した。
- 設定画面、エラー画面、SurfaceView、Dockプラグインに残っていた旧アイコン参照を整理した。
- `custom-style` のフレーム、画面グラデーション、CRT、光沢のレイヤーは維持した。
- 保存済みのカスタムアイコン設定を読めるよう、旧 `ghostColor` フィールドはデコード時だけ受け付け、新しいデータにはエンコードしないようにした。
- `official` は現在のZashikiアプリアイコンを使い、Dockアイコンのリセットもシステム標準のZashikiアイコンへ戻すようにした。

## 検証

- Ghosttyロゴ関連アセットとコード参照を検索し、対象の参照が残っていないことを確認した。
- `just lint`
- `just test-fast`
- `git diff --check`

いずれも成功した。`CustomGhosttyIcon` などのUserDefaultsキーは、旧バージョンからのデータ移行用の識別子として残している。
