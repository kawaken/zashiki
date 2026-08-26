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
  `characterIndex(for:)`、`hasMarkedText()`に一時的な`Zashiki.logger.debug`を
  追加する（:1937に既にコメントアウトされたログの残骸がある）→ **実施済み**
  （`ime-observe:`プレフィックス、`worktree-ime-surrounding-text`ブランチの
  コミット`4160f7525`）
- `attributedString()`（optional）にもスタブ＋ログを置いて、呼ばれるかを見る
  → **実施済み**（未実装だったので新規追加）
- 観測はユーザーが目視するのではなく、`sudo log stream --level debug
  --predicate 'subsystem=="dev.kawaken.zashiki"' > <file> 2>&1` でログを
  ファイルにリダイレクトし、Claudeが後から読んで解析する。ATOKとことえりで
  別ファイルに記録し、以下を確認する:
  - どのメソッドがどんな`range`で呼ばれるか
  - `nil`を返したときの後続の挙動（諦めるか、別のrangeで再問い合わせするか）
  - `selectedRange()`が返した`{0,0}`を基準に問い合わせてきているか
  - `attributedString()`が呼ばれるかどうか
- 比較対象としてことえり（日本語IM）でも同じ観測を行い、ATOK固有かを切り分ける
- **判断ポイント**: ここで「ATOKは周辺文字列を要求していない」と判明したら、
  この計画は破棄してplan/から削除する

**現状（2026-08-26）**: ビルドをブロックしていたXcode 26のexplicit module build
既知バグはPR #58（`SWIFT_ENABLE_EXPLICIT_MODULES=NO`追加）で解決済み。
リベース後、ビルドが実際に`Zashiki.app`まで到達したことで、それまで
Textual依存解決エラーに隠れて発見できていなかった別の実バグ
（`attributedString()`スタブの戻り値optionalityがプロトコル定義と不一致）も
見つかり修正した。ビルドは`zig build`で成功する状態。

**観測結果（2026-08-27）**: ATOKで3回、ことえりで1回、実機観測を実施した
（`sudo log stream`をファイルにリダイレクトしClaudeが解析する方式）。

- `attributedString()`（画面全体取得）は**ATOKでは3回のテスト全てで
  0回**。一方**ことえりでは1回のテストで5回呼ばれた**
- ATOKの`attributedSubstring(forProposedRange:actualRange:)`が要求する
  `range`は、常に**0起点の相対位置**で、現在入力中のmarkedText文字列の
  範囲内に完全に収まっていた。「あいうえお」を確定した直後に独立した
  新規入力で「きく」を変換しても、rangeは`{0,2}`のようにmarkedText内で
  完結し、直前の確定済みテキスト（周辺文字列）への到達は一度も確認
  できなかった
- `selectedRange()`は常に「no selection」（空のNSRange）を返しており、
  正しいカーソル位置を一切提供できていない
- `characterIndex(for:)`は一度も呼ばれなかった

**結論（判断ポイントの判定）**: 「ATOKは周辺文字列を要求していない」と
断定するのは早計と判断した。むしろ「`selectedRange()`が常にカーソル位置
不明（空）を返すため、ATOKは0起点の手探りでしか問い合わせできておらず、
周辺文字列にアクセスする足がかり自体が与えられていない」可能性が高い。
この計画は破棄せず、フェーズ1（`selectedRange()`を正しいカーソル位置に
直す）に進み、その後で改めてATOKの挙動を観測する方針とした。

### フェーズ1: コア側に入力行取得APIを足す — 実施済み（2026-08-27）

上記の原案には実装前に致命的なバグが見つかったため、以下の内容に変更して
実装した（コミット`6ccba0498`）:

- **原案のバグ**: 「カーソル位置のセルの`semantic_content`が`.input`か」だけを
  見ると、ユーザーが文字を打った直後（カーソルが次の未書込セルに進んだ状態、
  一番肝心なタイミング）で毎回失敗する。`Screen.promptClickMove`と同じ
  `cursor.semantic_content == .input or cursor.page_cell.semantic_content == .input`
  というOR条件に変更した
- **`cursor_utf16_offset`パラメータを廃止**。「返す文字列は常にカーソル位置で
  終わる」という設計にし、呼び出し側（Swift）は`(text as NSString).length`を
  そのままカーソルのUTF-16オフセットとして使えるようにした。Zig側はUTF-16を
  一切扱わない
- `Screen.inputLineTextBeforeCursor`（`src/terminal/Screen.zig`、
  `promptClickMove`の直後）: `selectLine`+`selectionString`（`map`オプションで
  バイトインデックス→Pinのマッピングを取得）→カーソルPinに`Pin.eql`で一致する
  バイト位置で文字列を切り詰める、という実装
- `Surface.inputLineBeforeCursor`/`Locked`（`dumpText`/`dumpTextLocked`と
  同じロック規約）
- C ABI: `ghostty_surface_read_input_line(ghostty_surface_t, ghostty_text_s*)`
  （`cursor_utf16_offset`パラメータは無し、既存の`ghostty_text_s`を再利用）
- `zig build test -Dtest-filter=inputLineTextBeforeCursor`で12ケース・77件
  全てgreen（基本、OSC133非対応、プロンプト/出力上のカーソル、空入力、全角、
  ソフトラップ、絵文字サロゲートペア、グラフェンクラスタ、行途中カーソル、
  ソフトラップ跨ぎ行途中、画面最初）

### フェーズ2: Swift側の配線 — 実施済み（2026-08-27）

`SurfaceView_AppKit.swift`の`NSTextInputClient` extension（コミット`832b3bdea`）:

- `cachedInputLineBeforeCursor: CachedValue<String>`をduration
  `.milliseconds(50)`で追加（`cachedScreenContents`の500msより短く。ATOKが
  `attributedString()`を3回連続で呼ぶ既知の挙動を1回のロック取得に潰す狙い。
  実機観測後に調整前提の暫定値）
- **`attributedString()`**: ゲート条件なしで実装。ファイル内でこのメソッドを
  呼んでいるのはIMEだけ（QuickLook・Accessibilityは無関係）と確認済みなので
  回帰リスクはゼロ。フェーズ0で観測された「preedit開始直前に3回連続で呼ばれる」
  という挙動に直接効く
- **`selectedRange()`**: 既存のマウス選択パス（`ghostty_surface_read_selection`）
  は変更せず、失敗時のフォールバックとして`hasMarkedText()==true`のときだけ
  `NSRange(location: (inputLine as NSString).length, length: 0)`を返す
- **`attributedSubstring(forProposedRange:actualRange:)`**: 同様に既存の
  マウス選択パスを保持し、フォールバックとして`hasMarkedText()==true`のとき
  だけ入力行テキストを`NSIntersectionRange`で切り出し`actualRange`に書き戻す
- `characterIndex(for:)`は変更なし（フェーズ0でATOKが呼んでいないことを確認済み）
- `zig build` / `swiftlint lint --strict` いずれも成功

**未実施（次にユーザーが起きてから）**:
- `attributedString()`単体、および`selectedRange()`/`attributedSubstring()`の
  IME分岐が入った状態での実機観測（ATOKでの変換候補の変化を確認）
- **回帰確認必須**: マウス選択→QuickLook（3本指タップ/`⌃⌘D`）、VoiceOverでの
  選択テキスト読み上げが従来通り動くか
- キャッシュduration（50ms暫定値）の調整要否を実機の呼び出し頻度から判断

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
