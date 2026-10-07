# ExpiringUndoManagerの全操作削除時クラッシュ

## 対象

- Issue #244

## 調査結果

- `removeAllActions()`はUndoManagerの操作を削除した後、`expiringTargets`を空のSetに置き換える。
- 期限付きターゲットの最後の参照がこの置き換え中に解放されると、`ExpiringTarget.deinit`から`expire()`が呼ばれ、同じUndoManagerの`removeAllActions(withTarget:)`へ再入して`expiringTargets`を変更する。
- `removeAllActions(withTarget:)`も対象をSetから外しながらexpireを呼ぶため、コレクション更新より先に対象を別の強参照へ退避し、再入中の変更と分離する。

## 方針

- `removeAllActions()`では既存ターゲットをローカルに保持したままUndoManagerの操作とSetをクリアし、その後にターゲットを解放する。
- `removeAllActions(withTarget:)`では一致するExpiringTargetを先にSetから除き、Setの更新後にexpireさせる。
- UndoManagerの標準動作と対象ごとの削除を維持する回帰テストを追加する。

## テスト

- `removeAllActions()`が期限付き操作を全て削除し、クラッシュしない。
- `removeAllActions(withTarget:)`が指定対象だけを除き、別対象のundoを維持する。
- `just lint`と`just test`を実行する。

## 実装結果

- `removeAllActions()`では既存ターゲットをローカル変数で保持し、UndoManagerとSetの更新後に解放するよう変更した。
- `removeAllActions(withTarget:)`では対象を先にSetから除外してからexpireするよう変更した。
- 2つの回帰テストを`macos/Tests/Zashiki/ExpiringUndoManagerTests.swift`に追加した。

## 検証結果

- `just lint`: 成功（Swift 192ファイル、違反なし）。
- `git diff --check`: 成功。
- `just test-fast`: Xcodeのアプリビルドは成功したが、テストを無効化したビルド後にZig側のコマンドが終了せず、停止した。
- `just test`: 20分以上テスト出力とxcresultの生成がない状態が続いたため停止した。テスト完了は確認できていない。
