# IMEへの周辺文字列提供（NSTextInputClient）

- **実施ブランチ**: `worktree-ime-surrounding-text`
- **元プラン**: `plan/ime-surrounding-text.md`（このドキュメントへ移行）
- **PR**: #63

## 実施内容

- `Screen.inputLineTextBeforeCursor`（`src/terminal/Screen.zig`）を追加。
  カーソルがOSC133の入力領域内にあるとき、行頭からカーソル直前までの
  テキストを返す。`selectLine`+`selectionString`（`map`オプションで
  バイトインデックス→Pinのマッピングを取得）→カーソルPinに`Pin.eql`で
  一致するバイト位置で文字列を切り詰める、という実装
- `Surface.inputLineBeforeCursor`/`Locked`の薄いラッパーと、C ABI
  `ghostty_surface_read_input_line`（既存の`ghostty_text_s`を再利用）を追加
- Swift側`NSTextInputClient`extensionで`attributedString()`を実装し、
  周辺文字列をIMEに提供。`selectedRange()`/`attributedSubstring()`は
  既存のマウス選択・QuickLook・Accessibility用の挙動を変えず、
  `hasMarkedText()==true`のときだけIME用のフォールバックを追加
- `insertText()`でIME確定時に`NSTextInputContext.invalidateCharacterCoordinates()`
  を呼び、IMEに文脈更新を通知するようにした

## Planとの差分・検証

**フェーズ1原案の致命的バグを実装前に発見・修正**: 原案は「カーソル位置の
セルの`semantic_content`が`.input`か」だけを見る設計だったが、ユーザーが
文字を打った直後カーソルは常に「まだ何も書かれていない次のセル」に進む
ため、これでは一番肝心なタイミングで毎回失敗する。`Screen.promptClickMove`
と同じOR条件（`cursor.semantic_content == .input or page_cell.semantic_content
== .input`）に変更した。あわせて`cursor_utf16_offset`という別出力
パラメータを廃止し、「返す文字列は常にカーソル位置で終わる」設計にして
UTF-16オフセット計算をZig側で行わないようにした。

**フェーズ0の観測結果が二転三転した**: 最初の実機観測でATOKが
`attributedString()`を一度も呼ばなかったため「周辺文字列を要求していない」
と見えたが、原因はATOK側の環境設定「挿入ポイント前後の文章を参照して
変換する」がOFFだったこと。ONにすると挙動が変わり、計画は継続する
判断となった。

**実装後に想定外の問題が発覚**: `attributedString()`を実装した直後の
実機観測で、IME有効化後の最初の1回しか呼ばれず、以降のフォーカス
セッション中はずっと古い（最初は空の）文脈をキャッシュしたまま使われる
ことが判明した。原因は`selectedRange()`が`hasMarkedText()==false`の間
固定の空レンジを返し続けるため、ATOKが「カーソル位置は変わっていない
＝文脈も変わっていない」と誤解していたと考えられる。`insertText()`での
確定時に`CachedValue`を手動invalidateしてから
`invalidateCharacterCoordinates()`を呼ぶことで解決した（`CachedValue`に
`invalidate()`を新規追加）。

**検証**: `zig build test -Dtest-filter=inputLineTextBeforeCursor`で
12ケース・77件全てgreen（全角文字・ソフトラップ・絵文字サロゲートペア・
グラフェンクラスタ・行途中カーソル等）。実機のATOKで、文節ごとに確定・
変換を繰り返すテスト（ATOK自身の連文節解析の影響を排除するため）を行い、
周辺文字列が文節確定のたびに正しく更新され、複数の同音異義語
（聞く/効く等）で意図通りの変換ができることを確認した。QuickLook
（3本指タップ）の回帰なしを確認。

**未実施のまま終えたこと**: VoiceOverでの実機回帰確認（実機のキーボード
設定でショートカットが押せなかった。既存のマウス選択パスは無変更のため
回帰リスクは低いと判断）、ことえり・韓国語IMEでの`selectedRange()`/
`attributedSubstring()`分岐の実機確認、カーソルがビューポート外
（スクロール中）の場合の扱い（`imePoint()`と同じ未解決TODO）。
フェーズ3（設定オプションでの無効化）は実機で問題が顕在化しなかった
ため見送った。
