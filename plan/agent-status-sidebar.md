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

## 設計

### 検出

- `AgentDetector` は入力（process 名、画面テキスト、入力行、直前画面）から provider と
  status を返す純粋な判定器にする。テストでは実際の Surface やプロセスを作らずに判定を検証する。
- process 名は macOS の `proc_pidpath` で foreground PID から取得する。
- `claude` / `claude-code` / `codex` / `codex-cli` を process 名として認識する。
  process 名だけで判定できないラッパーは、画面に明確な `Claude Code` / `OpenAI Codex` の
  識別子がある場合だけ候補にする。
- `waiting` は許可・拒否、確認、質問などの既知の末尾画面を優先して判定する。
- `working` は既知の処理中表示、または短い監視間隔内で画面が変化した場合に判定する。
- `idle` は既知の入力プロンプトが表示され、permission/question の表示がない場合に判定する。
- 既知 Agent だが画面の形が判定不能な場合は `unknown` とし、危険な操作や入力は追加しない。

### モデルと更新

- `AgentStatusModel` は Worktree Status pane が表示されている間だけ約 750ms 間隔で全 Surface を
  更新する。Worktree の `gw list` 更新とは分離する。
- 公開する行データは provider、status、Surface、作業ディレクトリ、最終状態変化時刻を持つ。
- 同じ Surface の状態または画面スナップショットに変化がない間は `lastUpdatedAt` を維持する。
- Surface が閉じた場合は次回スナップショットから行と一時画面内容を破棄する。

### UI

- 既存 Worktree Status pane の上部に Agent が存在するときだけ `Agents` セクションを表示する。
- 行には provider、状態アイコン／ラベル、作業ディレクトリ、相対更新時刻を表示し、provider と
  状態の意味は `.help` と accessibility label でも説明する。
- 行をクリックすると `Zashiki.moveFocus(to:)` と window activation を使って対応 Surface に移動する。
- Agent が無い場合は Agents セクションを表示しない。検出不能な既知 Agent は `unknown` 行として残す。

## 実装ステップ

1. `AgentStatus.swift` に provider/status、スナップショット、判定器を追加し、画面パターンの単体テストを書く。
2. `AgentStatusModel.swift` に Surface 列挙、PID→process 名解決、更新時刻保持、キャンセル可能な監視を追加する。
3. Worktree Status pane/split に Surface 配列を渡し、Agents セクションとクリックフォーカスを追加する。
4. `TerminalView` から現在の Surface tree を渡し、既存の Worktree / Markdown Preview のレイアウトを維持する。
5. SwiftLint、対象テスト、`just test-fast` または同等のビルドを実行する。

## 検証

- process 名と画面テキストの組み合わせで Claude/Codex を識別できる。
- known provider の permission/question、working、idle、unknown を誤って別状態にしない。
- Agent 行が Surface ごとに一意で、Surface 消滅時に消える。
- Agent が無いとき Agents セクションが非表示になる。
- Worktree Status / Markdown Preview の既存表示と同時に使える。
- 実機で Claude Code と Codex を別 split で起動し、各行クリックでフォーカスが移ることを確認する。

## 対象外

- Claude Code / Codex の hook、IPC、プラグインのインストールや設定変更。
- Agent への入力送信、停止、再開。
- Zashiki 外の端末、リモートセッション、バックグラウンドセッション。
- `done` 状態の追加や、provider の網羅的対応。
