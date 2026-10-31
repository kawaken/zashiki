# 端末本体の統合改善 #295 #296 #297 #305 #306 #307 #308 #309 #289

## 基準と進め方

- 基準は最新origin/main `f96b40855`。#313の入力・出力保護、#314のSparkle更新、#315の共有許可、#316の同期・資源寿命修正を確認した。
- 9件の本文・コメントを確認し、既存claimはなかった。Codexが各Issueにwipとclaimを記録した。関連PRの履歴も確認する。
- 全体で1ブランチ・1worktree・1Plan・1PR。Planレビューは実装フローに含め、ローカル検証をまとめてからpushする。needs-verificationは付けず、実機未確認を成功扱いにしない。
- ATOK文節下線、IME周辺文字列通知・確定後invalidate、独自タブとMarkdownプレビュー、配布・更新設定を維持する。共有許可は拡大しない。
- 上流の個別差分と後続修正を調査し、現行実装に必要な部分を採用する。remote追加・一括マージはしない。

## 依存関係と対応順

1. #295: LineIteratorの空行・コメント消費後にreaderを補充。小bufferで回帰を再現する。
2. #296: retained render state再生成時のframe countをリセット。閾値前後を検証。
3. #308: 行再利用時のmetadata全体初期化と、wrapped wide character消去時の前行dirty。#309の再利用fast pathの前提にする。
4. #305 → #306: 確定文字列をtyped inputへ統一し、その手前でNSStringのUTF-16分割入力を復元する。drop専用の保護経路は維持。
5. #307: preedit glyphへfont-thickenと強度を渡す。独自文節下線は維持。
6. #297: hard newline、wide tail/head、page境界の選択・コピー・表示を整合させる。
7. #309: pageの基盤最適化→same-style bulk copy→wide pair fast pathの順。style、grapheme、hyperlink、tracked pin、cursorを検証。
8. #289: 独自タブからの可視通知を確認し、GPU資源を非表示時に解放、表示時に再生成。#316の非同期main queue DisplayLink管理とcallback寿命を維持。

## 採用候補

| Issue | Ghosttyの個別差分                                                                                                                                                                                                                                                                                      | 現行での確認・検証方針                                                      |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| #295  | [#13638](https://github.com/ghostty-org/ghostty/pull/13638), `713ad0eb1`                                                                                                                                                                                                                               | 空行・コメントでcontinueのみ。buffer末尾の後続設定を検証                    |
| #296  | [#13585](https://github.com/ghostty-org/ghostty/pull/13585), `e69dc2bee`                                                                                                                                                                                                                               | count reset欠落。周期的な再生成を検証                                       |
| #308  | [#14010](https://github.com/ghostty-org/ghostty/pull/14010), `046a45a5f`; [#14054](https://github.com/ghostty-org/ghostty/pull/14054), `76e568b47`                                                                                                                                                     | resetRowなし。scroll/erase/resize、primary/alternate、prompt、page境界      |
| #305  | [#13817](https://github.com/ghostty-org/ghostty/pull/13817), `900912295`                                                                                                                                                                                                                               | marked textなしはsendText。入力メソッド経路とdropを区別                     |
| #306  | [#13737](https://github.com/ghostty-org/ghostty/pull/13737), `b0b9fbc8d`                                                                                                                                                                                                                               | String変換前のNSString code unit保持が必要。片側・順序・介在入力を検証      |
| #307  | [#14230](https://github.com/ghostty-org/ghostty/pull/14230), `88abb77b1`                                                                                                                                                                                                                               | preedit optionsにthicken指定なし                                            |
| #297  | [#14354](https://github.com/ghostty-org/ghostty/pull/14354), `aa9ed7d51`; [#14391](https://github.com/ghostty-org/ghostty/pull/14391), `69bf1ac87`; [#14632](https://github.com/ghostty-org/ghostty/pull/14632), `b1d9492cf`; [#14651](https://github.com/ghostty-org/ghostty/pull/14651), `d3d4c15d6` | 単語選択・formatter・renderの回帰テストを個別採用                           |
| #309  | [#13537](https://github.com/ghostty-org/ghostty/pull/13537), `aa21caeaa`; [#13827](https://github.com/ghostty-org/ghostty/pull/13827), `d760ee96e`                                                                                                                                                     | 同条件のASCII・日本語・絵文字履歴で前後計測。上流の倍率は実測として扱わない |
| #289  | [#14017](https://github.com/ghostty-org/ghostty/pull/14017), `683d8db64`                                                                                                                                                                                                                               | swapchain等の解放・再生成と独自タブ通知を調査。GPU実測可否を記録            |

## 検証・完了条件

- 変更ごとの回帰・正常系focused test。可能なものは修正を外した失敗も確認する。
- 最終状態で既存justタスクによるfull test、CI相当lint/test、app build。必要なGitHub checksを確認し、通常merge commitのAutoMergeを使う。
- 性能測定はworkload、build mode、反復条件、before/afterを記録。測定不能や実機未確認は理由を明記する。
- 実装判断・後続差分・検証結果を本Planへ追記し、完成時にdocs/historyへ移動する。
- PRに9件の原因・修正・検証・未確認一覧を載せる。マージ後は完了したIssueに結果記録、wip解除、明示close。未対応は開いたままにする。

## 実装・検証記録

- #295: 小bufferのコメント・空行後に後続設定を読める。補充を外すと`LineIterator refills`が失敗、復元後成功。
- #296: cleanupだけを小関数へ分け、100,000 frameの前後と次の周期までstateが保持されることを検証。resetを外すとexpected 1 / found 100001で失敗。
- #308: Page.resetRow / Row.resetを導入し、廃棄容量とscroll/insert/deleteの再利用箇所へ適用。primary/alternate、scroll region、page境界、prompt、selectLineの回帰を採用。resetを外すと再利用metadata検査が失敗。前行dirtyを外すとwrapped wide ECHの検査が失敗。
- #305: 全insertText確定をneutral key eventへ統一。入力ソース変更の早期returnでもaccumulatorの確定文字列を先に送る。drop APIは変更しない。key marshallingの日本語・音声相当・絵文字・改行・emptyをSwiftテスト化。
- #306: upstreamのlead/trail処理を状態付きdecoderへまとめ、NSString bridge前にcode unitを確認。属性付き文字、unsupported値、フォーカス喪失、marked text開始、文字確定のない別key eventでpendingを消す。分割pair・片側・順序・割り込みをSwiftテスト化。
- #307: preeditのthicken/strengthを指定。実際のSharedGridへaddPreeditCellを通し、off/on×strength 0/100/255×通常/強調下線のatlas位置が期待glyphと一致する回帰テストを追加。ATOK相当の両セルの下線も検証。
- #297: hard newlineとwide owner解決、page-list層での終端延長、表示範囲補正を採用。現行PinMapはArrayListのため上流の新Map APIを使わず適合。RenderState.cleanのない現行ではdirtyを明示clearする。focused selectWord/selection成功。
- #309: 上流benchmark frameworkは現行から削除済みのため復活させず、opt-inの`reflow benchmark`テストを追加。80×24、同じ120セル幅のASCII/CJK/emoji各2,000行、13列変更のdance、warmup 1回＋5回測定、前後全文一致を検査。初回Debug参考値はASCII約376→31ms、CJK約374→47ms、emoji約374→48ms（中央値）。ReleaseFastの最終値は下記。
- 後続差分調査: PageList/Screen/render/generic/SurfaceViewの2026-08以降のpath履歴を確認。保存cursorの`afded91d`、非reflowのwide切断`e6db5b63`、Capacity.adjustのrow上限`84983d06`はresizeの安全性に関係するため採用する。snapshot固有のtestは現行にその機能がないため対象外。全行clear時のKitty placeholder flag修正`a573781c`も#308のmetadata問題として採用する。
- #289: 独自BaseTerminalControllerは選択tab×window occlusionを全splitへ通知済み。swap chainをoptional化しhidden時にdraw_mutex内でinflight完了を待って解放する。CoreAnimationの直接drawもhidden判定で抑制。Threadはvisibleを先にrendererへ通知してからcatch-up update/drawする。DisplayLink制御は#316の非同期main queue方式を維持しmutex外で要求する。
- 上流のidle parking / renderer共有device / GTK context変更は別設計のため採用しない。`72cf5085`のdraw mutexとCVDisplayLinkStopのdeadlock注意は、#316の非同期要求とmutex外syncで満たす。
- 中間full test/ciはsandbox内でSwift macro plugin起動が失敗。共有許可に従いsandbox外で再実行し成功した。共有許可ファイル自体は変更していない。
- 追加のmixed履歴回帰で、全角headが新しい最終列へ来るとtracked pinをspacer headへ早く移しすぎる既存経路を検出した。writeCellがrepeatして次行へ全角文字を書き直すまでpin移動を遅らせ、文字・live cursorを保持する。trailing blankにある一般pinは既存仕様で幅へclampされるので、文字pinの保持とは区別する。
- 初回ベンチの`-Doptimize=ReleaseFast`は、build.zigがcore testsをDebug固定しているため実際にはDebugだった。初回値はDebug参考値へ訂正する。通常テストの既定Debugを保ち、core用`-Dtest-optimize=ReleaseFast`を追加して同条件の前後を取り直す。

## 最終検証結果

- `just test`: Zig全件・embeddedテスト・shell integration・macOS XCTest成功。確定文字列とUTF-16の新規Swiftケースもtest target内で成功。XCTest出力では418ケース成功。
- 最後に追加した#308のpage境界テストはfocusedで成功し、最終`just ci`の全件にも含めた。画面全体を大きくする初期fixtureは遅かったため、既存PageList.splitで小さい有効なpage境界を作るfixtureへ改善した。
- `just ci`: core/embedded全件、shell integration 2件、Swiftコンパイル、Zig format、SwiftLint成功。SwiftLintは207ファイル、違反0。`just build`も成功。
- #295補充、#296カウンター、#308 row resetと前行dirty、#297単語/コピー/表示、#307 preedit render optionsは、それぞれ修正を外すと原因に対応する回帰テストで失敗し、復元後成功した。
- #289は実Metal資源を作り、遅延callbackで未完了frameを模擬して解放の完了待ちを検証。重複解放・hidden中の直接draw抑止・再生成・atlas同期状態も確認。hidden時解放を外すとembedded testのchain=null期待が失敗し、復元後成功した。実GPU commandの完了競合を再現したとは扱わない。GPUがない環境ではこの1件をskipする。
- #309追加のmixed履歴ではSGR付き日本語/絵文字、結合文字、OSC8リンクを80行以上に書き、幅5/23/7/12/31/12の変更後にVT表現全体が一致。tracked文字pinとlive cursorも保持。wide-wrap pin修正前は期待する語のcodepointが0になり失敗した。
- 既存の#313 external paste、#316 DisplayLink/cached value/clipboard completion等もfull suiteで維持を確認。ATOK下線はpreedit glyphと両セルのunderline spriteをCPU側の実font atlasで検証した。
- `git diff --check`成功。共有許可・Sparkle lockfile・配布workflowに差分なし。最後のfetchでもorigin/mainは基準と同じ。GitHub必須チェックの結果は統合PRに記録する。

## 性能実測

### Reflow

macOS 27.2 / arm64、Zig 0.16.0、core testをReleaseFastでコンパイル。
`ZASHIKI_REFLOW_BENCHMARK=1 zig build test -Dtest-optimize=ReleaseFast -Dtest-filter='reflow benchmark'`。
beforeは`79494db09`のPageList/page（#309採用前）、afterは本変更。
同一のtest harness、page allocator、50MB scrollback上限、80列×24行で120セル幅の
履歴2,000論理行（80列では4,001物理行）を生成する。幅40/132/80/60/120/80/40/132/80/60/120/40/80の
13変更を1 cycleとし、warmup 1 cycle後、5 cycleを個別測定。fill・全文検査は時間外。

| 履歴   | before中央値 | after中央値 | 比率 |
| ------ | ------------ | ----------- | ---- |
| ASCII  | 17.037ms     | 2.210ms     | 7.7× |
| 日本語 | 17.989ms     | 3.328ms     | 5.4× |
| 絵文字 | 18.075ms     | 3.327ms     | 5.4× |

いずれも前後の全文一致に成功。これはcore testのallocator/page設定を使った局所測定であり、
実アプリのウィンドウドラッグ全体の遅延ではない。上流公表値は本測定へ流用していない。

### GPU

実Metal device、Debug embedded test、21 swap chain、各triple-buffered targetを1200×800へ拡張。
20個をhiddenにする前後の`MTLDevice.currentAllocatedSize`は246,185,984→12,222,464 byte
（234.78→11.66MiB）。再表示相当のchain生成＋target拡張20回は平均0.295ms、中央値0.290ms、最大0.334ms。
`ZASHIKI_GPU_BENCHMARK=1 just test-filter 'hidden GPU resources'`で再現できる。
通常のtestではmemory計測を行わずlifecycleのみ確認する。

アプリ全体の21タブ、実フォントatlas、Kitty画像、background imageを使ったmemory/footprint計測ではない。
初回presentやタブ切替から表示完了までの遅延も含めない。CPU側のfont grid、Kitty image等の
swap chain外の資源は保持する設計であり、全GPU資源を解放したとは表現しない。

## 未確認事項と完了手順

- 実ATOK/日本語IMEの連続変換、周辺文字列通知の視覚操作、音声入力、絵文字picker、Unicode Hex Inputの実操作、入力ソース切替の手動確認は未実施。
- 実アプリでの全角選択・消去表示、分割/移動/終了と高速タブ切替、background出力、Kitty画像とMarkdown preview表示を組み合わせた手動確認は未実施。実GPUの資源テストと区別する。
- ユーザー指定に従い実機確認をマージ条件にせず、needs-verificationを付けない。9件とも現行で必要な修正があり、対象外・解決済みとして省略したIssueはない。
- 1つのPRだけを作成し、必要なchecks/reviewを満たして通常mergeのAutoMergeでマージする。マージ後は各Issueへ結果を記録しwipを外して明示的にcloseする。
