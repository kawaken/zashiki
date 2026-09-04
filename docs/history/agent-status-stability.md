# Agents一覧のClaude Code状態判定安定化

## Issue

[#149](https://github.com/kawaken/zashiki/issues/149)

## 目的

Issue #134で追加したAgents一覧について、Claude Codeの実際のTUI表示に合わせて
`idle` / `waiting` / `working`を判定し、状態が画面の一時的な変化で揺れないようにする。

## 方針

- Claude Codeが実際に表示する素の`>`入力プロンプトを`idle`として認識する。
- 質問文が最後の行にない選択式UIを、操作フッターを根拠に`waiting`として認識する。
- `Esc to cancel`のように待機UIにも現れる文字列をworking判定から除外する。
- 直前の画面との差分だけで`working`と断定しない。既知の処理中表示がない場合は`unknown`とする。
- `inputLine`は補助的なシグナルとして残すが、Claude Code TUIの入力検出をそれだけに依存しない。
- 実際の動画で確認できたClaude Codeの画面形状を単体テストfixtureに追加する。

## 実装

- `AgentDetector`の判定順と画面パターンを修正する。
- 画面差分ベースのworkingフォールバックを削除する。
- `>` idle、選択式waiting、質問文が最後の行でないwaiting、未知画面の回帰テストを追加する。

## 検証

- `xcodebuild test -only-testing:ZashikiTests/AgentStatusTests` が通過した。
- `just lint` が通過した。
- `just test-fast` はアプリビルド成功後、統合テストrunnerが長時間無出力のまま終了しなかったため中断した。

## 実装結果

- Claude Codeの素の`>`プロンプトを`idle`として扱えるようになった。
- 選択式UIの`Enter to select` / `Esc to cancel`フッターを`waiting`として扱うようになった。
- `Esc to cancel`を`working`シグナルから外し、判定順序を`waiting` → `idle` → `working`にした。
- 直前画面との差分だけで`working`と判定するフォールバックを削除した。
- 動画で確認した画面形状を含む回帰テストを追加した。
