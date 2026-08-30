# macOS CIのビルド・テスト検証(残タスク: 紛らわしいログの解消)

## 経緯

元々の計画(PR時のSwiftビルド検証追加・XCTestのdestination明示)は完了した:

- PR/push時のCI(`test.yml`)に、Zigコアのテストに加えてmacOSアプリの
  Swiftコンパイル(`xcodebuild build`)を追加した。`-Dmacos-app-xctest=false`
  でXCTestは実行しない。実ランナーで検証済み(GitHub Actions上でpass)。
- `xcodebuild build`/`xcodebuild test`の両方に`-destination`を明示し、
  複数destinationマッチの警告(`WARNING: Using the first of multiple
matching destinations`)を解消した(`-destination`と`-arch`は併用不可の
  ため`-arch`を置き換え)。実ランナーで警告が消えることを確認済み。
- 過去に報告されていた「`xcodebuild test`の初回だけ失敗する」フレーキーは、
  ローカル・実ランナーいずれでも再現しなかった。リトライ機構の実装は見送り。

## 残タスク: Zigのbuild runnerが出す紛らわしい`failed command:`ログ

調査の過程で、このフォークのコードとは別に、Zig 0.16.0の
`std.Build.Step.Run`自体の挙動が判明した:

- `has_side_effects=true`のRunStep(`ZashikiXcodebuild`の`build`/`xctest`が
  該当)はプロセスをspawnする前に「万一失敗したらこれが原因」として
  `result_failed_command`を無条件セットする
- そのプロセスがstderrに何か出力すると(xcodebuildの通常の進捗ログなど)、
  ステップが実際には成功していても`printErrorMessages`が呼ばれ、
  `result_failed_command`が非nullなままなら`failed command: ...`という
  行を表示してしまう
- 実際の成功/失敗判定(`zig build`の終了コード)は独立した`failure_count`
  ロジックで正しく行われている。表示だけが紛らわしい

実ランナーのログでも同じ表示を確認済み(`build`/`xctest`両ステップとも、
成功しているのに`failed command:`が出る)。害はないが、ログを読む人が
誤って「失敗した」と判断するリスクがあるため、解消したい。

### 検討すべき対応

- `RunStep`の`stdio`設定を`.infer_from_args`から明示的な設定に変更し、
  stderrを`inherit`(即時表示)ではなく`capture`させ、成功時は破棄・失敗時
  のみ表示するようにできないか調査する。ただしこれを行うと、xcodebuildの
  ビルド進捗がリアルタイムに見えなくなるトレードオフがある可能性が高く、
  実際に試して確認する必要がある。
- あるいは、Zig側のこの挙動をバグとしてupstream(ziglang/zig)に報告する
  選択肢もある(このフォークの対応とは別軸)。
- 最小限の対応として、ログの意味を`CLAUDE.md`かこのファイルにコメントで
  残し、「buildステップのログに出る`failed command:`は成功時にも出る
  仕様であり、ジョブ全体のpass/failで判断すること」を明記するだけに
  留める案もある。

### 根本原因の特定(Zig 0.16.0 `std.Build.Step.Run`のソース調査)

`std/Build/Step/Run.zig`と`compiler/build_runner.zig`を読んで、原因を
「stderrに何か出力すると`printErrorMessages`が呼ばれる」から一段深く
特定できた:

- `ZashikiXcodebuild`の`build`/`xctest`ステップは`has_side_effects = true`
  に加えて`step.expectExitCode(0)`を呼んでいた。`expectExitCode`は内部で
  `addCheck`を呼び、Runの`stdio`を`.infer_from_args`から`.check`へ**切り
  替えてしまう**。
- `stdio == .check`のとき、`spawnChildAndCollect`は`has_side_effects`の
  値に関わらずstderrを常に`.pipe`(バッファリング)にする
  (`.infer_from_args`ならではの`has_side_effects`分岐は素通りされる)。
- 子プロセスの終了後、`evalGeneric`は
  `stderr_is_diagnostic = run.captured_stderr == null and switch (run.stdio) { .check => |checks| !checksContainStderr(checks.items), else => true }`
  という判定で、stderrに何か書かれていれば**成功・失敗を問わず**
  `result_stderr`へ丸ごとコピーする(`checksContainStderr`はexpectStdErrEqual
  等を使っていない限りfalse)。
- `build_runner.zig`の`makeStep`は`result_stderr.len > 0`なら
  `printErrorMessages`を呼ぶ。`result_failed_command`は`spawnChildAndCollect`
  が子プロセスをspawnする直前に無条件でセットされ、成功時にクリアされる
  経路が無いため、この`printErrorMessages`呼び出しで一緒に表示されてしまう。
  これが紛らわしい`failed command:`の正体。
- 一方、`expectExitCode(0)`を呼ばず`stdio`を`.infer_from_args`のままに
  すると、`spawnChildAndCollect`は`has_side_effects=true`から
  `stdout`/`stderr`を`.inherit`にする(ターミナルへ直接流れ、キャプチャ
  されない)。終了コードの判定は`evalGeneric`の`else`分岐が
  `Step.handleChildProcessTerm`を呼ぶことで**`expectExitCode`を呼ばなく
  ても引き続き行われる**(非ゼロ終了で`s.fail("process exited with error
code {d}", ...)`)。つまり`expectExitCode(0)`は元々不要な呼び出しだった。

`/tmp`に最小限のzigプロジェクト(`has_side_effects=true`のRunStepで
`echo ... >&2; exit 0`と`exit 3`を実行するだけの2ステップ)を作って検証:

- `expectExitCode`を呼ばない場合、成功ステップはstderrの内容がそのまま
  表示されるだけで`failed command:`は出ない。失敗ステップは
  `error: process exited with error code 3`と`failed command: ...`が
  正しく表示される。

### 実施した対応

`src/build/ZashikiXcodebuild.zig`の`build`/`xctest`両ステップから
`step.expectExitCode(0);`を削除(その理由をコード内コメントに記載)。
実機で検証:

- `zig build -Dmacos-app-xctest=false`: `BUILD SUCCEEDED`かつログ中に
  `failed command:`が0件。xcodebuildの進捗(Resolve Package Graph以降の
  各ステップ)もリアルタイムでターミナルに出力される(以前の`.check`モード
  ではstdoutが`.ignore`だったため、副次的にビルド進捗の可視性も改善)。
- `zig build test`(xctestステップ込み): 同様に成功時`failed command:`
  0件を確認。

検討していた「stdioをcapture設定に変更する」という対応は不要だった。
`expectExitCode(0)`という一見無害な1行がそもそもの原因であり、それを
削除するだけでstdio既定値(`.infer_from_args`)に戻り、副作用なく解決した。

## 対象外

- PRごとのフルXCTestを必須にすること
- GitHub Hostedの`macos-15`イメージをローカルで完全再現すること
- 他プロジェクトやupstreamのCI実装との比較
- macOS以外のCIを復活させること
- リトライ機構の実装(フレーキーの実在が確認できなかったため見送り。再発
  したら別途起票する)

## 完了

`step.expectExitCode(0)`の削除で解消し、実機で検証済み。詳細は上記
「根本原因の特定」「実施した対応」を参照。
