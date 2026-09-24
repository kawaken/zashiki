# Markdownプレビューの表示中ファイル切り替え

対応Issue: #207

## 現状の問題

Markdownプレビューには、ファイルが未選択のときに`NSOpenPanel`を開く
「Open File...」ボタンがある。一方、ファイルを表示している状態では
ヘッダーに前後移動と閉じる操作しかなく、GUIから別のMarkdownファイルを
選択できない。

## 方針

- 既存の`MarkdownPreviewPane.openFile()`を再利用する。
- プレビューのヘッダーにファイル選択ボタンを常設し、表示中のファイルから
  別ファイルへ切り替えられるようにする。
- `MarkdownPreviewModel.open(url:)`が担っている履歴更新、内容の読み込み、
  ファイル監視の挙動は変更しない。

## 実装

`MarkdownPreviewPane`のヘッダーにフォルダーアイコンの「Open File...」ボタンを
追加した。空状態の既存ボタンと同じ`openFile()`を呼ぶため、ファイル種別の制限や
キャンセル時の挙動は従来どおりである。

## 検証

- `just lint`: 成功（0 violations / 0 serious）
- `just test-fast`: 成功（ZigテストおよびmacOS Debug app build）
- XcodeのCoreDevice/CoreSimulatorに関する環境警告は出力されたが、ビルドは成功した。
- 実アプリでの手動操作確認は未実施。

## 完了条件

- Markdownプレビューでファイルを表示中に、ヘッダーから別ファイルを選択できる。
- 選択したファイルが既存の履歴・ライブリロード機能を通じて表示される。
- 既存の空状態のファイル選択と閉じる・前後移動操作が維持される。
