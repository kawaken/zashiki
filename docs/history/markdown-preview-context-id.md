# Markdownプレビューの所属先IDをCLIから取得する

## Issue

- #269

## 背景

`ZASHIKI_SURFACE_ID`はSurface生成時に子プロセスの環境へ設定される。長時間動くClaudeのデーモンやバックグラウンドジョブは起動時の値を保持し続けるため、後から別のWindow/タブにいるユーザーがプレビューを依頼すると、意図しない場所に表示されることがある。

CLIではIDを「terminal ID」と呼ぶ。値は既存のSurface IDをそのまま利用し、環境変数で配布するのをやめる。所属先を特定できる処理はCLIで実行時にIDを問い合わせ、IDを指定してプレビューを依頼する。所属先を持たない処理はIDを省略し、依頼時点のアクティブWindowを使う。

## 方針

- `zashiki +terminal-id`を追加する。CLIが取得したTTY名をZashikiへ送り、アプリがSurfaceのPTY名と照合してterminal IDを応答する。
- ID問い合わせは要求・応答が必要なため、既存の`zashiki://`要求と一時応答ファイルの仕組みを使う。
- `ZASHIKI_SURFACE_ID`の子プロセス環境への設定と、CLIによる読み取りを削除する。
- `zashiki +markdown-preview --terminal-id <id> <file>`で明示IDを指定できるようにする。省略時はアプリがアクティブWindowを選ぶ。
- 明示IDが不正または既に閉じられている場合はエラーを返し、別Windowへ黙ってフォールバックしない。
- Window単位かタブ単位かはCLIの契約に含めず、既存IDからアプリ内の所有先を解決する。プレビューの状態管理単位は別途選べるようにする。
- TTYから所属先を特定できない場合、`+terminal-id`はIDを返さない。Cronなどの呼び出し元はIDなしでプレビューを依頼できる。

## CLIの流れ

所属先が分かる呼び出し元:

```sh
id=$(zashiki +terminal-id)
zashiki +markdown-preview --terminal-id "$id" report.md
```

所属ターミナルがない呼び出し元:

```sh
zashiki +markdown-preview report.md
```

## 実装結果

- `zashiki +terminal-id`が呼び出し元の制御TTYを実行時に調べ、Zashikiへ問い合わせて対応するterminal IDを標準出力へ返す。対応するterminalがない場合はエラー終了する。
- `ZASHIKI_SURFACE_ID`を子プロセスへ設定する処理を削除した。
- `zashiki +markdown-preview --terminal-id <id> <file>`は指定IDのSurfaceを含むタブへプレビューを開く。ID省略時は既存の`TerminalController.preferredParent`を使い、アクティブWindowを優先する。
- 指定IDが不正または終了済みなら別Windowへフォールバックせずエラーにする。
- プレビューCLIはアプリからの応答を待ち、開けた場合は対象パスを標準出力へ表示して0、開けなかった場合は理由を標準エラーへ表示して非0で終了する。
- Window/タブの状態管理単位は今回のCLI契約では固定しない。現状のプレビュー状態はタブ単位で、terminal IDから所有タブを解決する。

## 検証結果

- `just lint` — 成功。
- `just test-fast` — 成功。ZigテストとSwiftコンパイルを実行。
- `just test` — 成功。ZigテストとmacOS XCTestを実行。
- ハンズオンで複数Window/タブへの明示ID指定と、IDなしのアクティブWindow表示を確認する。PRには`needs-verification`を付け、確認完了までマージしない。
