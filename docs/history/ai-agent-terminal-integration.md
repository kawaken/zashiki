# AIエージェント↔Zashiki連携の調査と基盤実装

## 概要

AIエージェントからZashikiの機能を呼び出す方法を調査し、Markdownプレビューを
最初のユースケースとして、URLスキームと発火元Surface特定の基盤を実装した。

## 調査結果

### OSCはBashツール経由の連携には使えない

Zashikiには、PTYを通じて子プロセスのstdoutからOSCエスケープシーケンスを受け取り、
ターミナルの動作を変える仕組みがある。しかし、Claude CodeのBashツール経由では
stdoutがキャプチャされ、端末制御文字がサニタイズされるため、任意のOSCをZashikiへ
届ける方式は成立しない。

OSCの双方向性も、OSC自身が双方向プロトコルなのではなく、PTYへの書き戻しなど別の
チャネルを組み合わせた結果として成立している。Bashツールの実行環境が実PTYへ
透過的に接続されていることを前提にできないため、応答用途へそのまま転用しない。

### URLスキームを採用した

出力のサニタイズに依存しない経路として、macOSのLaunch Servicesを使う独自URL
スキームを採用した。

```text
zashiki://<feature>/<verb>?<args>
```

Markdownプレビューの既存入口は次のURLである。

```text
zashiki://markdown-preview/open?path=<percent-encoded absolute path>
```

アプリが未起動なら起動され、起動中ならURLを受け取ってプレビューペインを開く。
URLの処理は未知の入力を無視してログに残す方針とし、将来の機能追加に備えた。

### 発火元Surfaceを指定できるようにした

URL共通の予約引数として`surface`を追加した。値は`ZASHIKI_SURFACE_ID`と同じ形式の
`0x`付き16桁hexで、エージェント側は環境変数をそのままURLへ渡せる。

ZashikiはURL受信時にSurface IDを一度だけ解決し、該当ウィンドウへ操作を渡す。値が
省略・不正・失効している場合は、従来どおり直近の親ウィンドウや新規ウィンドウへ
フォールバックする。

## 現在の実装範囲

- `zashiki://` URLの汎用的なfeature／verb／query構造
- `markdown-preview/open`のURL受信とファイル検証
- `surface`クエリによる発火元Surfaceの特定
- 子プロセスへ渡す`ZASHIKI_SURFACE_ID`

Markdownプレビューの表示機能の経緯は、`docs/history/markdown-preview.md`を参照。
エージェントから呼び出すCLIアクションは、`plan/markdown-preview-cli-action.md`
で別途扱う。

## 未実装として残したもの

- ZashikiからAIエージェントへ返答する双方向IPC
- Claude Code hookを使った、Bashとは別の連携経路の検証
- ローカルIPCを採用する場合の認証・権限・セキュリティ境界
