# IMEへの周辺文字列提供（NSTextInputClient）

## 目的

ATOKをはじめとする日本語IMEは、変換精度を上げるために「挿入点の前後にある
確定済みテキスト」をアプリから読み取る。macOSではこれが`NSTextInputClient`の
`attributedSubstring(forProposedRange:actualRange:)` / `selectedRange()`
経由で行われる。

Zashikiは`NSTextInputClient`を実装しているが、この読み取り経路は**実質的に
機能していない**（詳細は後述）。結果としてATOKは常に「周辺文字列なし」と判断し、
コンテキスト無しの変換にフォールバックしている。

ゴールは、シェルのプロンプト行に入力中のテキスト（カーソルより前の確定済み文字列）
をIMEに渡し、変換精度を改善すること。

## 現状（調査結果 2026-08-21）

`macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:1879` の
`extension Ghostty.SurfaceView: NSTextInputClient` に必須メソッドは全て存在する。
しかし文脈取得に関わる部分は QuickLook 用に作られており、IME用途では機能しない:

| メソッド | 現状 | 問題 |
| --- | --- | --- |
| `attributedSubstring(forProposedRange:actualRange:)` (:1936) | 要求rangeを無視してマウス選択中のテキストを返す | 選択が無ければ`range.length == 0`または`read_selection`失敗で常に`nil` |
| `selectedRange()` (:1889) | `ghostty_surface_read_selection`の結果（マウス選択範囲） | 挿入点ではない。選択なしなら`NSRange()` = `{0,0}` |
| `characterIndex(for:)` (:1970) | 常に`0`を返すスタブ | 未実装 |
| `attributedString()` (optional) | 未実装 | IMKTextInput側の全文/length取得も効かない |

`actualRange`はどのメソッドでも書き戻していない。実装コメントにも「macOSが
意味不明なrangeを投げてくるので常に選択を返す」と明記されており、IMEからの
問い合わせは想定されていない。

なお`validAttributesForMarkedText()` (:1929) の`.markedClauseSegment`対応
（コミット`46379d11f`）は preedit の文節下線を**IMEから受け取る**ための
フォークパッチであり、本件（端末からIMEへ渡す）とは逆方向で別物。

### 使える材料

- `ghostty_surface_read_text(surface, ghostty_selection_s, ghostty_text_s*)`
  で任意の画面範囲のテキストを読める（`SurfaceView_AppKit.swift:260`の
  `cachedScreenContents`で使用中）
- OSC 133 semantic prompt はコアで対応済み。セル単位で
  `Cell.SemanticContent` = `.output` / `.input` / `.prompt` が付く
  （`src/terminal/page.zig:2126`）
- `Screen.selectLine()` (`src/terminal/Screen.zig:2953`) が
  `semantic_prompt_boundary`オプションを持ち、**semantic状態の変化を境界として
  ソフトラップを辿りつつ行を切り出す**。カーソル位置のPinを渡せば、プロンプト
  文字列（`user@host >`）を除いた入力部分だけが取れる。本件の中核として再利用できる
- `Surface.imePoint()` (`src/Surface.zig:2105`) が
  `screens.active.cursor`にアクセスしている。カーソルのPin取得の前例

## 障害

1. **オフセット座標系が壊れている。**
   `Surface.Text.Viewport.offset_start`は`row * cols + col`という
   **セルグリッド上の線形位置**であって、返却される文字列のインデックスではない
   （`src/Surface.zig:2031`）。末尾空白のトリム・改行・全角=2セルで全部ズレる。
   `selectedRange()`はこの値をそのままNSRangeとして返しているので、
   NSRange↔文字列の対応が最初から取れていない。ソース側のコメントにも
   「部分的に見えている選択では値が間違っている、今のapprtユースケースでは
   正しさが要らないので後で直す」と書かれている
2. **挿入点をNSRangeで表現する手段がない。**
   `ghostty_surface_ime_point`はピクセル座標しか返さない
3. **`selectedRange()`の用途が衝突している。**
   QuickLook（`firstRect`が`selectedRange()`との一致でIMEかQuickLookかを判定
   している :1989）と Accessibility（`accessibilitySelectedTextRange` :2336）が
   同じメソッドを共有している。座標系を変えると両方が壊れる
4. **ターミナルにドキュメントモデルがない。**
   カーソル前後のセルを素直に返すと、プロンプト文字列や`ls`の出力が「文脈」として
   混ざる。OSC 133が出ているシェルに限定すれば入力行だけ抜けるが、未対応シェルでは
   フォールバックが必要

## 方針

- **OSC 133がある場合のみ**周辺文字列を返す。無い場合は現状どおり`nil`を返して
  劣化させない。プロンプト文字列や過去の出力を「文脈」として渡すと、変換精度が
  上がるどころか悪化するリスクがあるため
- 対象は**カーソルより前の入力テキスト**を最優先とする。カーソル後ろは
  優先度を下げる（`selectLine`で行全体が取れるので、後から足すのは容易）
- `selectedRange()`の既存の意味論は**変えない**。QuickLookとAccessibilityの
  回帰リスクが高すぎる。IME用の座標系は preedit 中（`hasMarkedText() == true`）
  だけ有効にする分岐で導入する
- **まず観測から入る。** ATOKが実際にどのメソッドをどの順・どんなrangeで呼ぶかは
  IMK実装依存で、ドキュメント化されていない。推測で実装すると空振りする

## 実装ステップ

### フェーズ0: 計装してATOKの挙動を観測する（最優先・低コスト）

実装の前に、ATOKが本当に周辺文字列を要求しているのかを確認する。要求していない
なら以降のフェーズは全て無駄になる。

- `attributedSubstring(forProposedRange:actualRange:)`、`selectedRange()`、
  `characterIndex(for:)`、`hasMarkedText()`に一時的な`Ghostty.logger.debug`を
  追加する（:1937に既にコメントアウトされたログの残骸がある）
- `attributedString()`（optional）にもスタブ＋ログを置いて、呼ばれるかを見る
- `sudo log stream --level debug --predicate 'subsystem=="dev.kawaken.zashiki"'`
  で観測。ATOKで日本語入力し、以下を記録する:
  - どのメソッドがどんな`range`で呼ばれるか
  - `nil`を返したときの後続の挙動（諦めるか、別のrangeで再問い合わせするか）
  - `selectedRange()`が返した`{0,0}`を基準に問い合わせてきているか
- 比較対象としてことえり（日本語IM）でも同じ観測を行い、ATOK固有かを切り分ける
- **判断ポイント**: ここで「ATOKは周辺文字列を要求していない」と判明したら、
  この計画は破棄してplan/から削除する

### フェーズ1: コア側に入力行取得APIを足す

`src/Surface.zig`に、カーソル位置の入力行とカーソルオフセットを返す関数を追加:

- カーソルの`page_pin`を取得（`imePoint()` :2107 と同じ経路）
- そのセルの`semantic_content`が`.input`でなければ失敗を返す
  （＝shell integration無し、または出力表示中）
- `screens.active.selectLine(.{ .pin = cursor_pin, .semantic_prompt_boundary = true })`
  で入力範囲の`Selection`を得る
- `dumpTextLocked`でテキスト化
- **同時に、返す文字列先頭からカーソル位置までのUTF-16コードユニット数**を計算して
  返す。既存の`offset_start`（セルグリッド線形位置）は使わない。ここが障害1への対処で、
  本フェーズの本質的な作業。文字列を実際に走査してオフセットを出す
- C ABI: `ghostty_surface_read_input_line(ghostty_surface_t, ghostty_text_s*, uint32_t* cursor_utf16_offset)`
  を`src/apprt/embedded.zig`と`include/ghostty.h`に追加
- Zig側のテストを`zig build test -Dtest-filter=...`で追加する。特に全角文字・
  ソフトラップ・絵文字（サロゲートペア）でオフセットが合うこと

### フェーズ2: Swift側の配線

`SurfaceView_AppKit.swift`の`NSTextInputClient` extension:

- 入力行テキストとカーソルUTF-16オフセットを保持するキャッシュを持つ
  （`CachedValue`の既存パターンを使う。ただしIMEの応答性が要るので
  durationは`cachedScreenContents`の500msより短く。フェーズ0の観測で
  呼び出し頻度を見てから決める）
- `selectedRange()`: `hasMarkedText()`が`true`のときだけ
  `NSRange(location: cursorUTF16Offset, length: 0)`を返す。それ以外は現状維持
- `attributedSubstring(forProposedRange:actualRange:)`:
  `hasMarkedText()`が`true`のとき、入力行テキストから要求rangeとの共通部分を
  切り出して返し、**`actualRange`に実際に返した範囲を書き戻す**。
  それ以外は現状のQuickLook向け実装を維持
- `characterIndex(for:)`: 優先度低。フェーズ0でATOKが呼んでいなければ触らない

### フェーズ3: フォールバックと設定

- OSC 133非対応シェルでは何も返さない（＝現状維持）ことをREADMEに明記
- 挙動に問題が出た場合に切れるよう、設定オプションでの無効化を検討。
  ただし設定を増やすコストと釣り合うかはフェーズ2の結果を見て判断する

## 検証

- `zig build test -Dtest-filter=<新規テスト名>` でコア側オフセット計算を検証
- 実機でATOKを使い、以下を確認:
  - 入力行に文脈がある状態で変換候補が変わるか（例: `git ` と打った後に
    「こみっと」→「commit」等の学習が効くか）
  - preedit中にカーソル移動・画面スクロール・ペイン切り替えをしてもクラッシュ
    しないか
  - **回帰確認**: マウス選択→QuickLook（3本指タップ/`⌃⌘D`）が従来どおり動くか
  - **回帰確認**: VoiceOverで選択テキストが正しく読まれるか
  - ことえり・韓国語IMEでpreeditが壊れていないか（過去に`fa141a726`,
    `d60a16c14`などIME周りの修正が入っている領域なので特に注意）

## リスク・未解決

- **フェーズ0の結果次第で全部無駄になる。** ATOKが`nil`を受けた時点で
  周辺文字列の利用を諦めている可能性、そもそも問い合わせていない可能性がある
- `selectedRange()`を`hasMarkedText()`で分岐させる方式は、「マウス選択がある状態で
  IME入力を開始する」ケースで QuickLook 判定（:1989）と干渉しうる。
  フェーズ2で実機確認が要る
- 入力行の取得はロックを取って画面を走査するので、preedit中に高頻度で呼ばれると
  レンダリングに影響する可能性がある。キャッシュのdurationで調整する
- カーソル位置がビューポート外（スクロール中）の場合の扱いは未検討。
  `imePoint()`にも同じ`TODO`が残っている（`src/Surface.zig:2111`）
- upstream（ghostty-org/ghostty）に同種の実装・議論があるかは未調査。
  フェーズ1に入る前に一度確認するとよい
