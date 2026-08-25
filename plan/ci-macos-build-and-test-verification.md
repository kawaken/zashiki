# macOS CIのビルド・テスト検証

## 目的

PR / push時のCIでは、macOSアプリのSwiftコードがコンパイルできることを
軽量に検証し、タグpush時のリリースCIではXCTestを含むフル検証を行う。

PRごとの`xcodebuild test`は実行時間とmacOSランナーのコストが大きく、初回の
テストホスト起動にフレーキーさも確認されている。そのためPR時にフルテストを
戻すことは目的にしない。一方、現在の設定ではテストだけでなくSwiftのビルド
自体もPR CIから外れているため、その間を埋める。

## 現状

### PR / push時

`.github/workflows/test.yml`の`test`ジョブはmacOSランナー上で次を実行する:

```shell-session
zig build test -Demit-macos-app=false -Demit-xcframework=false
```

この指定により、Zigコアのテストは実行されるが、macOSアプリのXcodeビルドと
XCTestは実行されない。`swiftlint`は別ジョブで実行されるものの、Swiftの型検査・
リンクを含むコンパイル検証の代わりにはならない。

なお、`.github/workflows/test.yml`のmacOSアプリビルドジョブは現在
`workflow_dispatch`時だけ実行される。

### タグpush時

`.github/workflows/release.yml`ではフラグなしの`zig build test`を実行し、
macOSアプリ側の`xcodebuild test`を含むフルテストを行った後、Zashiki.appを
ビルドする。品質保証をリリース時に集約する現在の方針自体は維持する。

## 確認されている問題

### Swiftコンパイルの検証が抜けている

Swiftファイルを変更したPRでも、PR CIでは実際のSwiftコンパイルが行われない。
コンパイルエラーがリリース時まで発見されない可能性がある。

### XCTestの初回起動がフレーキー

過去の調査では、GitHub Hostedの`macos-15`ランナーで初回の
`xcodebuild test`が5〜8秒程度で失敗し、直後に同じコマンドを再実行すると
成功した。初回ログには複数destinationにマッチした旨の警告が出ていた。

まだ、次の点は確定していない:

- destinationの自動選択が失敗原因なのか
- Xcodeの初回起動、テストホスト、DerivedData準備などランナー環境の問題なのか
- `xcodebuild`の失敗が、なぜ外側の`zig build`の終了コードに伝播しなかったのか

失敗を1回リトライすれば成功する可能性はあるが、リトライ後の失敗を確実に
CIへ伝播させることが前提となる。

## 方針

- PR / push時は、Zigコアのテストに加えてmacOSアプリのSwiftコンパイルだけを
  実行する。XCTestは実行しない。
- タグpush時は、引き続きフルの`zig build test`を実行する。
- XCTestを実行する経路では、destinationを明示して自動選択を避ける。
- 初回失敗への対策としてリトライを導入する場合でも、最大1回に限定する。
- 初回と再試行の両方のログを残し、再試行後の失敗は必ずCI失敗にする。
- `ZashikiXcodebuild`の`build`ステップと`xctest`ステップの依存関係を確認し、
  ビルドだけを実行する経路を明確に分離する。
- GitHub HostedのmacOS環境そのものをローカルで再現できる前提にはしない。
  upstreamとの比較は行わず、このフォークのコードとGitHub Actionsの実行結果だけ
  で切り分ける。

## 実装ステップ

### フェーズ0: ローカルでの切り分け

YAMLを何度も変更する前に、`src/build/ZashikiXcodebuild.zig`が組み立てる
現在の`xcodebuild`引数をローカルのmacOSで直接実行する。

1. `xcodebuild -showdestinations`で、`Zashiki.xcodeproj` / `Zashiki` schemeの
   利用可能なdestinationを確認する。
2. プロジェクト、scheme、configuration、`-skip-testing ZashikiUITests`、
   `SYMROOT`、アーキテクチャなどを現在のZigラッパーと揃える。
3. 同じコマンドを複数回実行し、初回だけ失敗するか確認する。
4. Xcodeバージョン、destination、DerivedDataの状態、各試行の終了コードを記録する。

`act`はActionsの式・ジョブ条件・シェルステップの確認には使えるが、通常は
Docker上のLinux環境で動くため、`runs-on: macos-15`のXcode挙動は再現できない。
macOS固有の切り分けには、ローカルのMacでの直接実行と、必要最小限の
`workflow_dispatch`による実ランナー検証を使う。

### フェーズ1: PR時のSwiftビルド経路を追加する

- `ZashikiXcodebuild`の既存ステップを調査し、XCTestに依存せずmacOSアプリを
  コンパイルできる構成を作る。
- 必要なら、ビルド専用のBuild Stepまたは設定オプションを追加する。
- PR / push時の既存macOSジョブに組み込み、Zigコアのテストと同じ変更検証の中で
  Swiftコンパイルも行う。
- XCTestやアプリ起動はこの経路に含めない。
- Xcode DerivedData / SwiftPMキャッシュを再利用し、macOSランナーの実行時間を
  必要以上に増やさない。

### フェーズ2: XCTest経路の安定化

- `xcodebuild test`に明示的なdestinationを渡す。
- 初回失敗時だけ同じコマンドを1回再実行する仕組みを、ZigのRunStepまたは
  検証可能なシェルラッパーとして実装する。
- 1回目の失敗を無条件に成功扱いにせず、2回目の終了コードを最終結果にする。
- `step.expectExitCode(0)`が実際に`zig build test`へ失敗を伝播させることを、
  意図的な失敗を使って確認する。
- リトライなしでも再現する失敗と、初回起動だけの一時的な失敗をログ上で区別できる
  ようにする。

### フェーズ3: Actionsの検証

- PR / push時にSwiftのビルドエラーを検出できることを確認する。
- タグpush時にSwift XCTestを含むフルテストが実行されることを確認する。
- フルテストの初回失敗時にリトライが行われ、2回目も失敗した場合はリリースが
  停止することを確認する。
- YAMLを繰り返し編集して試すのではなく、必要な診断情報を一度の
  `workflow_dispatch`実行で収集する。

## 検証項目

- Swiftの型エラーを含む変更がPR CIで失敗する。
- Zigコアのテストは従来どおりPR CIで実行される。
- PR CIではXCTestを実行せず、実行時間とランナーコストを抑えられる。
- リリースCIではmacOSアプリ側のXCTestも実行される。
- destinationの自動選択警告が消える、または意図したdestinationがログに出る。
- 1回目だけ失敗して2回目に成功した場合はCIが成功する。
- 2回連続で失敗した場合はCIが失敗する。
- `act`で確認できる範囲と、実macOSランナーでしか確認できない範囲が文書化される。

## 対象外

- PRごとのフルXCTestを必須にすること
- GitHub Hostedの`macos-15`イメージをローカルで完全再現すること
- 他プロジェクトやupstreamのCI実装との比較
- macOS以外のCIを復活させること

## 完了後

実装とCI検証が完了したら、この計画を削除する。初回フレーキーの原因や
リトライ・destination固定など、今後も覚えておく価値のある判断があれば、
`docs/history/`に短い履歴を残す。
