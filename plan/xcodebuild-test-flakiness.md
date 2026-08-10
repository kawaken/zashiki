# xcodebuild testの初回起動フレーキーさ

## 現象

CIの`test`ジョブ（`zig build test -Demit-macos-app=false`）内で、Swift側の
XCTest実行（`xcodebuild test -scheme Ghostty -skip-testing GhosttyUITests`）
がほぼ毎回、起動から5〜8秒で失敗する:

```
test
+- xcodebuild test w
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
...
IDETestOperationsObserverDebug: 5.614 elapsed -- Testing started completed.
failed command: cd .../macos && xcodebuild test -scheme Ghostty -skip-testing GhosttyUITests -arch arm64
```

にもかかわらず、`zig build test`ジョブ全体は最終的に`success`として完了する。
このジョブが唯一の実行ステップなので、CIのUI上は緑になり、失敗に気づけない。

## 調査

PR #11（draft、マージ済みではなく閉じた）で、`test.yml`に`xcodebuild test`を
zigのラッパーを介さず直接実行するデバッグステップを追加して検証した。

結果: `zig build test`内での1回目の起動は失敗するが、その直後に**同じコマンドを
もう一度実行すると`** TEST SUCCEEDED **`まで正常に完了する**（所要15秒程度）。
DerivedDataキャッシュ・環境は1回目と2回目で同一。

## 分かったこと

- 実行環境（GitHub Hosted `macos-15`ランナー、毎回まっさらなVM）で
  `xcodebuild test`を初めて起動した時だけ、テストホストプロセスの
  起動が何らかの理由で失敗する、よくあるCIのフレーキーさだと考えられる
- 2回目の起動は問題なく成功する
- `zig build test`が最終的に`success`になる理由（1回目の`xcodebuild test`失敗が
  なぜ`zig build`全体の終了コードに影響しないのか）は**未解明**。
  `src/build/GhosttyXcodebuild.zig`の`xctest`ステップは
  `step.expectExitCode(0)`を設定しており、通常なら失敗が伝播するはずだが、
  実際にはそうなっていない
- 結果として、**Swift側のユニットテスト（`macos/Tests/`配下の
  ConfigTests, SplitTreeTests等）が、CI上では実質的に一度も完走せずに
  緑判定になっている可能性が高い**。テストとして機能していない懸念がある

## 未着手・保留

- upstream(ghostty-org/ghostty)の`GhosttyXcodebuild.zig`・実際のCI実行結果を
  見て、同じフレーキーさが起きているか比較する（`add_repo`の承認待ちで保留）
  - upstreamのtest.ymlはNamespace Cloud専用ランナーに依存しており、標準の
    GitHub Hostedランナーとは環境が異なる可能性がある。フレーキーさが
    「まっさらなmacOSランナーでの初回起動」に起因するなら、warm/persistent
    なランナーを使うupstreamでは再現しないかもしれない

## 対応案

`src/build/GhosttyXcodebuild.zig`の`xctest`ステップ（`xcodebuild test`を
呼んでいる`RunStep`）に、失敗したら1回だけ自動リトライする仕組みを入れる。
例えばシェルラッパーで:

```sh
xcodebuild test -scheme Ghostty -skip-testing GhosttyUITests $ARGS \
  || xcodebuild test -scheme Ghostty -skip-testing GhosttyUITests $ARGS
```

のような形にする。これはZigのbuildコード自体の変更なので、ローカルで
検証できず、CIで確認しながら進める必要がある。

あわせて、「なぜ現状successになっているのか」の解明もできれば行いたい
（本当にテストが機能してないのか、実は何らかの形でリトライ済みで
成功しているのか、確証を持てていないため）。
