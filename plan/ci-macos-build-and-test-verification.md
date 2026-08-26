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

## 対象外

- PRごとのフルXCTestを必須にすること
- GitHub Hostedの`macos-15`イメージをローカルで完全再現すること
- 他プロジェクトやupstreamのCI実装との比較
- macOS以外のCIを復活させること
- リトライ機構の実装(フレーキーの実在が確認できなかったため見送り。再発
  したら別途起票する)

## 完了後

対応方針が決まり実装・検証が完了したら、この計画を削除し、判断の要点を
`docs/history/`に短い履歴として残す。
