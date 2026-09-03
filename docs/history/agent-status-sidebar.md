# Claude/Codex Agent 状態の Worktree Status サイドパネル表示

## Issue

[#134](https://github.com/kawaken/zashiki/issues/134)

## 目的

Zashiki 内の Surface で動作している Claude Code / Codex CLI を Surface 単位で
検出し、既存の Worktree Status サイドパネルに Agents セクションとして表示する。
Agent 行から該当 Surface にフォーカスできるようにし、複数の split を開いたままでも
どの作業ディレクトリで何が起きているかを一覧で把握できるようにする。

## 調査結果

- `SurfaceView` は `surfaceModel.foregroundPID` 経由で PTY の foreground process group
  の PID を取得できる。
- `SurfaceView` には `cachedVisibleContents` / `cachedScreenContents` があり、端末画面の
  テキストを一時的に取得できる。画面内容を保存する永続ストレージは追加しない。
- Herdr は foreground process を主信号にし、既知の許可・質問 UI だけを blocked と判定する。
  未知の画面は安全側に倒して idle/unknown とする。
- WezTerm Agent Deck は provider と status のパターンを分離し、一定間隔で pane ごとに更新する。
- 上記を踏まえ、Zashiki は process 名で Claude/Codex を候補化し、画面下部と入力行の
  一時スナップショットから `working` / `waiting` / `idle` / `unknown` を推定する。

## 実装内容

- `AgentDetector` を純粋な判定器として追加し、Claude Code / Codex の process path と
  runtime wrapper 上の画面識別子を候補にした。
- `proc_pidpath` で foreground PID の実行ファイルを解決し、約 750ms 間隔の表示中監視で
  Surface ごとの Agent 状態を更新する。
- 画面下部の処理中表示、permission/確認/質問、入力行、入力プロンプト、直前画面との差分を
  使って `working` / `waiting` / `idle` / `unknown` を推定する。入力や画面スナップショットは
  pane 表示中のメモリ上だけで保持し、Surface 消滅時に破棄する。
- Worktree Status pane 上部に Agent が存在するときだけ Agents セクションを表示し、provider、
  状態、作業ディレクトリ、相対更新時刻、説明用 tooltip/accessibility label を表示する。
- Agent 行のクリックで対象 Surface をアクティブ化し、既存の `Zashiki.moveFocus(to:)` で focus
  を移動する。Worktree Status と Markdown Preview の既存レイアウトは維持した。

## 検証結果

- `AgentStatusTests` の 9 ケース（Claude/Codex の識別、runtime wrapper、versioned Claude
  executable、working/waiting/idle/unknown、未知 process の除外）が通過。
- `just lint` 通過（Zig format check と SwiftLint、既存警告なし）。
- macOS の `xcodebuild` 対象テストおよび app build 通過。
- `just test-fast` は既存の package sandbox 制約を回避して app build までは通過したが、
  統合テスト runner が長時間終了しなかったため完走扱いにはしていない。対象テストと lint を
  完了条件にした。

## 対象外

- Claude Code / Codex の hook、IPC、プラグインのインストールや設定変更。
- Agent への入力送信、停止、再開。
- Zashiki 外の端末、リモートセッション、バックグラウンドセッション。
- `done` 状態の追加や、provider の網羅的対応。
