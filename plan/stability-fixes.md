# 安定性改善 #298–#303

## スコープと基準

- 基準: origin/main `685f26866`。6件を1ブランチ・1PRで扱う。
- 各Issueの本文・コメントを確認済み。他のclaim・wip・関連実装PRは見つからず、Codexが各Issueをclaimした。
- Planレビューを実装フローに含める。`needs-verification`は付けず、実機未確認を成功扱いにしない。
- ATOK文節下線、IME周辺文字列通知、独自タブ、#313の貼り付け・ドロップ保護、配布・更新設定を維持する。
- 共有許可設定は `.claude/settings.json` と `.codex/rules/development.rules` を確認済み。変更しない。検証は既存justタスクを優先する。

## 依存関係・順序

直接の依存はない。#302 → #300 → #303 → #298 → #299 → #301の順に、所有権の局所的な修正から進める。
#303と#301はrendererに触れるが、shaperのエラー時解放とDisplayLink寿命は独立。#289のGPUリソース解放は含めない。

## 調査と設計

| Issue | 現行コードの到達経路と問題 | 方針・回帰検証 |
| --- | --- | --- |
| #302 | `write_*_file` → `Surface.writeScreenFile`。成功時にTempDirの2つのhandleが閉じない。deinitもparentを閉じない。初期化エラー経路も確認する。 | ファイルを保持するcloseと削除を区別する。成功・失敗・選択なしをdeferで統一。handle閉鎖、保持した内容の再読み込み、反復時のFDを検証。 |
| #300 | `Exec.queueWrite`は64 byte単位でSegmentedPoolを2つcheckoutする。grow後のmodulo巡回は未完了領域へ戻り得る。 | pointer-stableなMemoryPoolに要求とbufferを一体で保持し、完了した個体だけ返す。拡張・低速相手・CRLF・write error・終了時の寿命を検証。 |
| #303 | `CTFontCopyDisplayName`、CFString生成、Typesetterのline生成のnullを非optional化している。 | optional/errorを呼び出し元まで伝播。表示名欠落はfamily nameにfallback。Copy所有権とshaperの失敗時解放を確認。日本語の正常描画と失敗注入を検証。 |
| #298 | accessibilityとIMEが同じCachedValueを使用。Task失効はget/invalidateと非同期にvalue/taskを変更する。 | fetch中は状態lockを保持せず、invalidate世代とexpiry世代を検証する。再入・古いTask・並行get/invalidate・破棄を検証し、TSanの実行可否と限界を記録。 |
| #299 | 重複clipboard確認の通知callback中にnative requestを同期完了している。 | 次のmain queue turnで元surfaceが生存している場合だけ拒否完了する。閉鎖、連続要求、承認・拒否・キャンセルとnative側の所有権を確認。 |
| #301 | render threadのloopEnter/Exit、focus/visible、display変更からCVDisplayLinkを直接操作。Surfaceはcallback先のrenderer_threadを先に破棄。 | 状態要求は非同期にmain queueへ集約。mainがrenderをjoinする間もrenderはmainを同期waitしない。stop完了前にcallback先を解放しない。状態収束・queued close・寿命を検証。 |

## 個別採用元

リモートの追加・一括マージは行わず、以下の差分と関連履歴を調査し現行toolchainに合わせる。

- #302: [Ghostty #13644](https://github.com/ghostty-org/ghostty/pull/13644)
- #300: [Ghostty #13659](https://github.com/ghostty-org/ghostty/pull/13659), `f948d4207655f31ae9b95fa039e73524df43cd13`
- #303: [Ghostty #13642](https://github.com/ghostty-org/ghostty/pull/13642), `b60970ce250e9000f48e013ba9d1f9efb0316f49`; [#13679](https://github.com/ghostty-org/ghostty/pull/13679), `571c62dada5da79f68d12d376957cc1d02d846b1`
- #298: [Ghostty #13646](https://github.com/ghostty-org/ghostty/pull/13646), `c9ef382fc97d8256b9c5af3e8f13841896b0db15`。独自invalidateがあるため単純移植せず世代管理を追加する。
- #299: [Ghostty #13648](https://github.com/ghostty-org/ghostty/pull/13648), `ae0ff51c42f859b483b4a5a073b7fb4941f78273`
- #301: [Ghostty #14691](https://github.com/ghostty-org/ghostty/pull/14691), `81598385d608dda4946093d6d6a234d204a2f225`。現行Zashikiはidle parking以前のfocus/visible方式なので動作方針を維持して適用する。

## 検証・完了条件

- 原因に対応する回帰テストを追加し、可能なものは修正前に失敗することを確認する。
- focused tests → `just test` → `just ci` → `just build`。エラーや変更に応じて必要な検証を追加する。
- 実機のスリープ復帰、解像度変更、外部ディスプレイ抜き差し、ATOKの視覚確認は、実施できた範囲と未実施を分ける。
- 修正単位のコミットにIssue番号を記載。各Issueへ結果を記録し、Planを同じPRでdocs/historyへ移動する。
- PRをreadyにし、通常merge commitのAutoMergeを有効化してCI・レビュー条件を監視。条件の回避や手動mergeは行わない。
- マージ後に各Issueへ完了記録、wip解除、明示的closeを行う。

## 実装・検証記録

- #302: TempDirは成功時の2 handle漏れに加えて、deinitでもparent未close。initの親open後・子create後のエラー処理も不足していたため同時に修正する。
- #303: DeferredFaceのCopy系文字列はreleaseされず、返却文字列も内部ポインタだった。bufへコピーしてreleaseする所有権へ揃える必要がある。
- #299: 通常の確認sheetもraw surfaceを保持しており、閉鎖後に応答すると古いsurfaceを参照し得る。Swift側で元surfaceの生存確認と完了一回性を共通化する。native側は未完了要求を追跡してsurface破棄時に回収する（現行はheap requestを追跡しておらず閉鎖時に漏れる）。

- #302実装: 成功時はretain close、失敗・選択なしはdelete closeへ統一。initのエラー時も親handleと作成済みディレクトリを回収。128回のretain/delete、FD閉鎖、保持した日本語内容の再読込テストを追加し、osのtest rootへ登録した。親closeを外すとBADF期待で失敗、復元すると`just test-filter TempDir`成功。実際の外部エディタ起動は未実施。

- #300: libxevのkqueue backendはloop停止後に未処理callbackを再実行せず、stream.deinitはFDを閉じない。通常の終了はsubprocess.stopでFDを閉じ、IO thread内でpoolを最後に解放する。3MiBを137 byteずつ読み取りつつ3回追加する回帰テストは、元のSegmentedPoolでexpected 0 / found 125のデータ不一致を再現。修正後に一致しCRLF・日本語も維持。SIGPIPEを抑制したbroken pipeによる実OS write error callbackを検証。write errorは回復不能なapp障害ではなく、警告ログとしテストの意図したerror log失敗も避ける。未完了要求を残したloop停止でtesting allocatorに漏れなし。

- #303実装: display name欠落はfamily nameへfallback。Copy文字列は呼び出し側bufferにコピーしてrelease。descriptor/family/PostScriptの失敗もoptional化し、font resizeはOOM、fallback discoveryは候補なしとして扱う。CFString・Typesetter lineのOOMをshaperへ伝播し、renderer.updateFrameはdeferでendFrameを必ず呼ぶ。日本語shapingと8 frame反復を検証。dyld interpositionによるdisplay/string/typesetter/lineの4種類のnull注入はすべて成功。displayのnull判定だけ外すとSIGABRTで失敗し、復元後に再成功。実OSのOOMやATOKの視覚操作は未実施。

- #301調査: upstream DisplayLinkのpath履歴は導入コミットのみで後続変更なし。開始適用中にstop要求が入るとactual stateがまだfalseで要求を取り逃す窓もあるため、desired stateが変わった場合も必ずsyncをqueueする。現行のfocus/visible制御は維持し、hasVsyncから未作成・停止後の再試行を行う。Surface初期化失敗時にも開始済みthreadをjoinし、callback停止後にThread資源を破棄する必要がある。

- #298実装: 状態lockの外でfetchし、並行missは許容しつつ先に発行された現在世代の値をcacheする。invalidate/expiryは世代を進め、古いfetchと失効Taskによる再発行・消去を防ぐ。NSLockはget/失効/invalidate/deinitの状態アクセスを保護。IMEの独自invalidateも同じ経路を使用。6 SwiftテストをTSanで実行し競合報告なし。lockを外した同じ実装ではTSanがinvalidateLockedのdata raceを検出。独立した実装抽出によるTSanであり、アプリ全体のTSanや実機ATOK操作は未実施。

- #299実装・検証: 元surfaceのidentityを確認する完了一回の応答objectをsheetと重複拒否で共有。重複拒否は次のmain queue turnへ移す。native要求は完了まで独立保持し、二重完了はdereference前に無視、閉鎖で全pendingを回収する。100連続要求、deferred前の閉鎖・surface差替え、承認/キャンセルをSwiftテストで検証。遅延を外すとcallback中の完了を検出して失敗。nativeの既存external pasteテストに重複・完了・未応答破棄を追加し成功。#313の制御文字、bracketed paste、drop相当の文字列経路を維持。実際の確認sheet操作は未実施。

- #302追加回帰: 実際のSurface.writeScreenFileをembedded runtimeのhost callbackまで通し、screen/history/selection × plain/VT/HTMLを8反復（72出力）、consumerへ渡す直前のOOMを8回、選択なしを32回実行。各回のFD数がbaselineと一致し、成功時は返却後のファイル読込が成功。外部アプリの実起動はしていない。embedded test targetへ常時登録した。

- #301実装・検証: CoreVideo操作をmainだけに限定し、render側はatomic desired stateと非同期queueのみ使用。停止を要求した後でもrenderer.Thread.draw_nowはrenderer.close完了まで生存させる。queued syncが残る場合はwrapperの解放を最後のqueued callbackへ委譲。mockの4テスト（集約、close、開始失敗/外部停止、開始中stop要求）成功。desired変更時のqueueを外すとstop要求テストが失敗。実際のスリープ・hotplug・解像度変更、thread spawn失敗注入は未実施。

- #300テスト調整: closed FDはlibxev内でUnexpected errnoのstack traceを出すため、実際の切断相当のbroken pipeでerror completionを検証する形に変更。実行成功し、不要な診断出力もなくなった。
