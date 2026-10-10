# リリース全テストのタイムアウト調査

- Issue: [#262](https://github.com/kawaken/zashiki/issues/262)
- 状態: 調査・対応方針のレビュー待ち。workflowと製品コードの変更は未実施。

## 結論

最有力の原因は、新規追加された`ExpiringUndoManagerTests`のundoグループ開始漏れ。
手元の全テストでも完了待ちを再現し、Xcodeのテストホスト診断ログから
`NSInternalInconsistencyException`を確認した。
`groupsByEvent = false`で自動グループ化を止めているのに、
`beginUndoGrouping()`なしで`registerUndo`を呼び出している。

同じ条件の単独コードも同じ例外で異常終了し、明示的なグループ開始・終了を
追加すると既存2ケース相当の検証が成功した。CIの診断artifactがないため、
CI上の例外そのものは未確認だが、同一commitでの2回の停止と整合する。

まずテストのグループ化を修正してCIの全テストを再確認する。
単に45分を60分・90分へ伸ばす対応は、この停止を解消しない可能性が高い。

## 確認した実行

GitHub Actionsのjob / step timestampsと、両試行および直近成功回のraw logを照合した。
以下の時刻はUTC。ジョブ時間にはセットアップと後処理を含む。

| 実行 | 結果 | 全テストstep | アプリbuild step | ジョブ全体 |
| --- | --- | --- | --- | --- |
| [2026-09-28](https://github.com/kawaken/zashiki/actions/runs/36418651080) | 成功 | 16分08秒 | 5分25秒 | 23分45秒 |
| [2026-10-01](https://github.com/kawaken/zashiki/actions/runs/36864311776) | 成功 | 13分58秒 | 5分16秒 | 21分45秒 |
| [2026-10-07](https://github.com/kawaken/zashiki/actions/runs/37567536852) | 成功 | 13分03秒 | 3分39秒 | 18分17秒 |
| [2026-10-10 / attempt 1](https://github.com/kawaken/zashiki/actions/runs/38020501993/attempts/1) | 45分でキャンセル | 44分33秒 | 未到達 | 45分27秒 |
| [2026-10-10 / attempt 2](https://github.com/kawaken/zashiki/actions/runs/38020501993/attempts/2) | 45分でキャンセル | 44分47秒 | 未到達 | 45分50秒 |

失敗対象は `0749f995dce0070372327da815fc974a10f058d3`。
2回目の開始がrunの作成から約46分後なのは、1回目終了後に再実行されたため。
最初のjobはrun作成の約10秒後に開始している。

### 停止位置

- attempt 1: `zig build test`開始03:26:20、`xcodebuild test`出力開始03:27:17、
  最後のビルド出力03:32:21、キャンセル04:10:53。無出力は38分32秒。
- attempt 2: `zig build test`開始04:12:25、`xcodebuild test`出力開始04:13:21、
  最後のビルド出力04:17:09、キャンセル04:57:12。無出力は40分03秒。
- 両試行ともテストケースの結果、`IDETestOperationsObserverDebug`の完了ログ、
  `** TEST SUCCEEDED **`はない。コンパイルエラーも見当たらない。
- 10月7日の成功回は03:41:57にビルド終盤、03:42:06に
  `9.828 elapsed -- Testing started completed.`、03:42:07に
  `** TEST SUCCEEDED **`が記録されている。テストケースのpassed行は319件。
  全テストstepはその約8分後の03:50:10に完了している。
- `Testing started`やケース結果がXcode側で後から出力される成功例なので、
  失敗回にその行がないことは「ケースが一つも実行されなかった」証明にはならない。
- 失敗実行のartifactは0件。xcresult、Xcodeの診断ログ、停止中のstack sampleは
  保存されておらず、事後に確定できる範囲には限界がある。

### 環境比較

10月7日の成功回と10月10日の両失敗試行は、同じ
`macos-15-arm64` / image `20260907.0337.1` / Xcode 26.3 (`17C529`) /
Zig 0.16.0を利用している。ランナーイメージやXcodeの切り替わりは確認できない。
実行ごとの負荷差は測定されておらず、否定も肯定もできない。

## ビルド構成と変更差分

- `.github/workflows/release.yml`の45分制限はテストstep単独ではなく、
  test・ReleaseFast build・公開・CHANGELOG処理を含むjob全体にかかる。
- `build.zig`の`test`はZigのテスト実行と、native XCFrameworkに依存する
  `xcodebuild test`の両方を依存として持つ。Xcodeの完了だけでは全体は終わらない。
- テスト用XCFrameworkは既にnative指定。`-Dxcframework-target=native`を
  テストコマンドに追加するだけでは、この部分の負荷は減らない。
- `ZashikiXcodebuild.zig`はUIテストの実行をskipするが、ログには
  `ZashikiUITests-Runner.app`のビルドも現れる。実行対象とビルド対象は区別する。
- リリースworkflowにはXcode DerivedDataのcacheがないが、
  `mlugg/setup-zig`によるZig cacheは既に有効。2回目は復元も確認できる。
  「cacheが一切ない」ことを原因にはしない。
- `test-fast`はXCTestを省略してSwiftのコンパイルを行う。
  リリースもこれだけに置き換えると、現在リリースが担うXCTest実行が失われる。
- 直近成功commit `5f2aacd`から失敗commitまで、release workflowとビルド定義の
  差分はない。主な変更はMarkdown previewの開封応答・フォーカス時の文字サイズ、
  About表示、ExpiringUndoManager修正とその新規テスト。
  差分には追加のXCTest対象が含まれるが、どれが原因かを示すログはない。

## ローカルで再現した原因

Xcode 27.0で`zig build test --summary all`を実行すると、Swiftの多数のケースが
成功した後に完了しなくなった。テストホストのxcresultのStaging内にある
`StandardOutputAndStandardError.txt`で以下を確認した。

```text
_registerUndoObject:: Zashiki.ExpiringUndoManager ... is in invalid state,
must begin a group before registering undo
FAULT: NSInternalInconsistencyException
```

スタックには`ExpiringUndoManager.registerUndo`と
`ExpiringUndoManagerTests.removeAllActionsSafelyClearsExpiringActions`が含まれる。
この例外の後もホストアプリは生存し、sampleではメインスレッドがイベント待ち。
Xcodeのテスト完了通知は出ず、調査側から中断するまで待ち続けた。

問題の2ケースはPR #258で追加された。どちらも`groupsByEvent = false`の直後に
グループを開始せず`registerUndo`する。手元のFoundation SDKヘッダーでも、
自動グループ化と明示的なグループ開始・終了の仕様を確認した。

既存の`ExpiringUndoManager.swift`と`Duration+Extension.swift`を使った
一時的なコマンドライン再現コードで比較した。

| 条件 | 結果 |
| --- | --- |
| 自動グループ化OFF、グループ開始なし | 同じ`NSInternalInconsistencyException`で終了（signal 6） |
| グループ開始・終了あり、removeAllActions | canUndo/canRedoがfalseになる検証成功 |
| グループ開始・終了あり、対象指定削除とundo | 他対象のundo保持・実行と削除対象の未実行を検証成功 |

CIはmacOS 15 / Xcode 26.3、手元はmacOS 26 / Xcode 27.0であり、完全に同じ環境
ではない。CI側のraw logにはこの例外は転送されていないため、確定と推定を区別する。

## 対応方針案

### 最小の修正

`macos/Tests/Zashiki/ExpiringUndoManagerTests.swift`の両ケースで、登録の前に
`beginUndoGrouping()`、登録の後に`endUndoGrouping()`を呼ぶ。
2ケース目は2対象の登録を1グループとして閉じ、対象指定削除後に残った操作をundoする。
自動グループ化を戻す代替案もあるが、run loopに依存しない今のテストの意図を
保つには明示的にグループ化する方が適切。
製品側のUndoManager実装を変更する必要性は今回確認していない。

修正後はまず両XCTestを単独実行し、続いて全Zigテストと全macOS単体テストを
実行する。CIの全テストで今回の停止が解消することを確認する。
リリース公開を伴わない方法で検証し、調査だけのためにタグpush・Release公開はしない。

### タイムアウトと診断

通常時のjobは18〜24分であり、45分には既に相当の余裕がある。
先に上記修正後の実績を計測し、上限値の変更が必要か判断する。
ジョブ全体の45分と各工程の時間予算は区別する。
`test-fast`への置き換えによるXCTestの省略は行わない。

今回の例外は標準のActions logでは見えず、テストホストの診断ファイルで
判明した。今後の失敗時にxcresultと診断ログをartifactとして残す改善は有用。
job cancel前に中断・回収できる時間予算を設ける案を別途検討する。
Zig / XCTestのjob分割、DerivedData cache追加、並列テスト無効化は、
今回の原因に対する最小修正には含めない。

## 今回の調査での検証

- Actions APIの両attempt、直近3回の成功step所要時間、raw logを照合。
- workflow、Zigの依存グラフ、Xcode scheme / test planと変更差分を確認。
- 全テストを手元で実行し、XCTestの例外による完了待ちを再現。
  停止確認後に中断したため全テスト成功は未確認。通常サンドボックスでの
  最初の試行はSwift Package解決時に権限制約で失敗し、制約外で再試行した。
- 同じUndoManagerソースによる単独再現コードで、例外の発生条件と
  明示的なグループ化による両ケース相当の成功を確認。
- グループ化を一時追加した実際のXCTest 2ケースを単独実行し、
  `** TEST SUCCEEDED **`と両ケースのpassedを確認（各約0.001秒）。
  実験用のSwift変更は元に戻し、今回のPRはPlanのみとする。
- `git diff --check`を実行。

## 未確定事項

- CI上で同じ例外が起きていたことの直接確認と、修正後のCI全テスト結果。
- 修正後の全体所要時間と負荷変動時の実績。今回workflowは変更・再実行していない。
