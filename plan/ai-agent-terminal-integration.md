# AIエージェント↔Zashiki連携の調査

## 目的

Zashikiは「AIとの共生・共同利用」を前提にしたターミナルという方向性を持つ。
Claude Codeのような、シェル配下で動くAIエージェントから、Zashiki本体の機能を
能動的に呼び出せるようにしたい。

最初の具体ユースケースはMarkdownプレビュー機能（`zashiki://markdown-preview/open`
URLスキーム、実装済み。`docs/history/markdown-preview.md`参照）を、AIエージェントが
使いやすい形で正確に「呼び出し元のウィンドウ」に開けるようにすること。将来的には
Yes/No確認のような双方向のやり取りも視野に入れている。

## 検討して分かったこと

### OSCエスケープシーケンスによる子プロセス↔ターミナル通信（一方向）

Ghosttyには`src/terminal/osc.zig`を中心に、子プロセスの`stdout`（PTY経由）に
書かれたOSC (Operating System Command) エスケープシーケンスを解釈し、ターミナル
自身の挙動を変える仕組みが既にある。

- `OSC 8` ハイパーリンク、`OSC 9`/`777` デスクトップ通知、`OSC 133` semantic
  prompt（shell integration）等
- パイプライン: `子プロセスのstdout → PTY → osc.zigのパーサー →
  termio/stream_handler.zig → apprt.action → C ABI境界（ghostty_target_s、
  GHOSTTY_TARGET_SURFACE + surfaceポインタ） → Swift側で
  surfaceView(from:)により発火元Surfaceを直接特定 → 実際のUI操作（例:
  UNUserNotificationCenterでの通知表示）`
- このパイプラインは「どのSurface（ウィンドウ/ペイン）から来たか」をC ABIレベルで
  正確に解決できる。URLスキーム経由（`open`→Launch Services→
  `TerminalController.preferredParent`で最後にアクティブなウィンドウを推測）
  より原理的に正確

### OSCの「標準化」の実態

OSCという枠組み自体（`ESC ]` 〜 `BEL`/`ST`という構文）はECMA-48で標準化されて
いるが、「番号Nに何の意味を持たせるか」を管理する中央レジストリは存在しない。
実態は早い者勝ち＋緩い合意形成のグラデーション:

- `OSC 1337`: iTerm2が独自に決めて公開しただけ（他社が追従するかは任意）
- `OSC 133`: fish shell/iTerm2界隈が提案、freedesktop.org系gitlabに緩い仕様書
- `OSC 3008`: `uapi-group.org`という複数プロジェクト間で事前調整するコミュニティが
  策定した「Hierarchical Context Signalling」仕様。Ghosttyでは**パーサーは
  実装済みだが、実際のアクション処理は何もしていない（no-op）**
- Ghosttyが実際に使用中のOSC番号: `0,10,11,13,21,22,30,44,52,55,64,66,72,77,
  104,133,245,246,300,552,583,588,593,598,603,618,624,629,668,674,681,688,
  700,705,712,717,729,775,777,802,804,806,808,810,812,814,821,823,825,827,
  829,831,833,835,837,839,1337,3008,5522`
- `OSC 1337`はGhosttyでは39種のキーを認識するが、実際に処理しているのは
  `Copy`（クリップボード）と`CurrentDir`（cwd報告）の**2つだけ**。
  `ReportVariable`等の照会（本来は双方向）系は全部未実装
  （`src/terminal/osc/parsers/iterm2.zig`）

### OSCの双方向性は「プロトコルの約束事」であって仕組みそのものではない

OSCは常に子プロセス→ターミナルの一方向（`stdout`書き込み）。ターミナル→
子プロセス方向は別の仕組みで、`termio.Message.writeReq`でPTY masterに書き込み、
それが子プロセスの`stdin`として読める、という**別チャネル**を組み合わせて
初めて「双方向」に見えているだけ（DSR/カーソル位置照会が実例）。OS/PTY層は
バイト列を右から左に流すだけで、エスケープシーケンスの意味は両端が実装して
初めて成立する。

### 【最重要】Claude CodeのBashツール経由ではOSCは機能しない

ローカルのZashiki環境で実機検証した結果:

- `printf '\033]9;...\007'`をBashツールで実行しても、Ghostty/Zashiki側の
  デスクトップ通知は**発火しない**
- 原因: Claude Codeの実装上、Bashツールは子プロセスの`stdout`を**キャプチャして
  テキストとしてUIにレンダリングする経路**を通り、その過程でESC/BEL等の制御
  文字がサニタイズ（除去）される。生のエスケープシーケンスをそのまま端末に
  流すと、偽プロンプト・画面クリア・タイトル書き換えによるフィッシング等の
  攻撃が可能になるため、これは意図的なセキュリティ対策と考えられる
- 「ユーザーが直接打ち込んだか」「Claude Codeにお願いして実行してもらったか」は
  無関係。**Bashツールという実行経路を通る限り、実行主体を問わず同じ制限が
  かかる**。応答テキストとして直接OSCを出力させようとした場合も同様に機能
  しなかった（Claude Code自身の応答テキストも最終的にはBashツール的な経路を
  通らざるを得ないため）
- 唯一機能するのはClaude Code本体（信頼された自プロセス）が自分の`stdout`に
  直接書き込む、ハードコードされた通知（`idle_prompt`/`agent_completed`等の
  Notification hook）。これはUIレンダリング層をバイパスしている

（検証中に得た副次的な学び: `UNUserNotificationCenter`の通知は
`requireFocus`（デフォルト`true`）により、フォーカスが当たっているウィンドウ
では意図的に抑制される。`show_desktop_notification`のOSCコマンドには
`requireFocus`を指定するフィールドが無く常に`true`固定。テスト時はフォーカスを
外す必要がある）

## 結論：OSCベースの双方向プロトコル構想はBashツール経由では成立しない

Claude CodeのBashツールから任意のOSCを送る、という設計は前提から崩れている。
一方で、この制約の影響を受けない経路が2つ残っている:

1. **`zashiki://` URLスキーム（実装済み）** — `open`コマンドの効果は
   Launch Services経由の副作用であり、「stdoutのテキストがどう表示されるか」
   というサニタイズの対象と無関係。Bashツール経由でも問題なく機能する
2. **環境変数（`ZASHIKI_SURFACE_ID`等）** — サニタイズの対象は「出力」であって
   「環境変数」ではないため、Bashツールのサブプロセスにも普通に継承される

## `zashiki://`クエリパラメータの汎用規約（実装済み）

URLの構造は`zashiki://<feature>/<verb>?<args>`。「REST」ではなく
**RPC-over-URL**として設計している（カスタムURLスキームにはHTTPメソッドの
軸が存在しないため、動詞を`path`セグメントに埋め込む形。Slack Web API の
`chat.postMessage`的な命名と同じ発想）。

- `<feature>`: 機能の名前空間（例: `markdown-preview`）
- `<verb>`: その名前空間内での動作。小さな統制語彙を使う（`open`/`close`/
  `toggle`/`show`/`ask`など、新しい動詞が要る時は既存語彙から選べないか
  先に検討する）
- `<args>`: 各verb固有の引数 + 全アクション共通の予約引数
  - **予約引数（現時点で`surface`のみ）**: 発火元ウィンドウのSurface ID。
    値は`0x`+16桁hex（環境変数`ZASHIKI_SURFACE_ID`と同一フォーマット、
    AIエージェント側は`$ZASHIKI_SURFACE_ID`をそのまま埋め込むだけでよい）。
    省略可、省略時・解決失敗時は直近アクティブウィンドウにフォールバック
- 未知の`host`/`path`/`query`は黙って無視してログのみ（前方互換性のため、
  既存実装のまま）

### 一方向: Surface正確特定（実装済み）

`zashiki://`の全アクション共通の規約として`surface=`パラメータを採用した。

- Zig: `Surface.id` (u64) を`ghostty_surface_id()` C APIとして公開
  (`src/apprt/embedded.zig`, `include/ghostty.h`)。元々`GHOSTTY_SURFACE_ID`
  という名前でGTK版DBus IPC専用に設計されていた環境変数は、他でリネーム
  済みの命名規則に合わせて`ZASHIKI_SURFACE_ID`にリネームした
  (`src/Surface.zig`)。旧名は誰にも消費されていなかった（macOS側は今回まで
  未消費、GTK側は削除済み）ため後方互換のエイリアスは設けていない
- Swift: `Ghostty.SurfaceView.ghosttySurfaceID: UInt64?`
  (`SurfaceView_AppKit.swift`) + 逆引き関数
  `AppDelegate.terminalController(forGhosttySurfaceID:)`
  (`AppDelegate+Ghostty.swift`。既存の`ghosttySurface(id: UUID)`とは別軸の
  識別子なので別関数として追加、両方残す)
- パース責務: `AppDelegate.handleZashikiURL`（ホスト振り分けの前段、全
  アクション共通の入口）で一度だけ`surface`を解決し、
  `BaseTerminalController?`を各アクションハンドラに渡す。「見つからない
  場合にどうフォールバックするか」はアクション固有の判断としてハンドラ側に
  委ねた（markdown-previewは`sourceController ?? preferredParent ??
  newWindow`の順）
- 後方互換性: `surface`なし、または解決失敗時は常に既存の
  `preferredParent`ベースの推測にフォールバックするため、既存の呼び出し
  （`surface`パラメータ無し）は無変更で動作し続ける

### 双方向（Zashiki→AIエージェントへの応答、例: Yes/No確認）

OSC/PTY経由の応答書き込み（`termio.Message.writeReq`をYes/No用に転用する案）は、
Bashツールが起動するサブプロセスがそもそも実PTYに透過的に接続されているか
自体が疑わしく（`stdout`は明確にキャプチャ・サニタイズされることが判明した）、
`stdin`も同様に実ターミナルと直結していない可能性が高い。この方式は前提から
検証し直す必要がある。

有力な代替案: ターミナルI/Oに依存しない別のローカルIPC（Unix domain socket・
loopback HTTP等）を、CLIヘルパープロセスとZashiki本体（既に起動中のGUIプロセス）
の間に用意する。サーフェス特定には環境変数`ZASHIKI_SURFACE_ID`をリクエスト
ペイロードに含める。

## 未解決の課題

- 双方向IPC（Unix domain socket等）の実装規模・セキュリティ境界（ローカル
  プロセス間とはいえ、他ユーザー・他アプリからの不正な接続をどう防ぐか）
- Claude Codeのhookシステム（`PreToolUse`/`PostToolUse`/`Notification`等）に
  Bashツールとは別の、サニタイズされない出力経路が存在するかは未検証
