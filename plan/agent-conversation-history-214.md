# Issue #214: Agent会話履歴レールの不具合調査

## 調査結果

- `GHOSTTY_POINT_SCREEN` は、API上はアクティブなScreenの先頭から末尾までを
  読み出す。スクロール位置だけで範囲が変わる実装ではない。
- Claude Code / Codexが使うalternate screenはスクロールバックを持たず、
  Ghostty側の`scrollbar.total`も表示行数になる。TUIが内部で保持する過去の会話は、
  TUIが再描画した範囲しかSurface APIから取得できない。
- そのため、会話をスクロールすると`screenContents`自体が変わり、現在の実装が
  `entries`を置き換えることで表示マーカー数も変化する。Ghosttyの行番号を使った
  `scroll_to_row`ではTUI内部の仮想スクロール位置へ移動できない。
- `.onHover`によるカスタムプレビューと`.help`によるネイティブtooltipが同時に
  有効だったため、ホバー時の二重表示はZashiki側で解消できる。

## 対応方針

- レールのカスタムプレビューと競合する`.help`を削除する。
- `AgentConversationParser`の行番号変換は、Ghostty側のprimary screenの
  スクロールバックを読む場合には現行の`scrollbar.total`基準を維持する。
- alternate screen上のTUI内部履歴を完全取得・クリック移動するには、Agentの
  ログやIPCなどSurface外の連携が必要になる。現在のIssueの実装範囲では推測で
  代替せず、未解決の制約として記録する。

## 検証

- AgentConversationParserの既存テストで、行番号変換と複数行応答を確認する。
- SwiftLintと対象macOSテストを実行する。
- Claude Code / Codexのalternate screenで、会話全体取得とクリック移動は
  現行APIの制約により未検証・未解決としてPRに明記する。

## 追加調査：実現可能な段階設計

### 第1段階：fullscreenを維持したviewport capture/navigation

classic renderer固定は主案にしない。fullscreen/TUIの使い勝手を維持したまま、
対象はまずClaude Codeだけに限定する。機能はデフォルトで無効にし、メニューバーの
Viewメニューから「Claude Code履歴の自動スクロール」をオンにした場合だけ、Agentが
アイドル状態のときにZashikiが既存のSurface入力APIで制御された
スクロールイベントを送り、表示された画面を複数回読み取って履歴を収集する。
設定がオフの場合は現在表示中の画面だけを読み取り、スクロールイベントを送らない。
Codexは当面、既存の検出・表示対象から外し、Claude Codeの検証が終わるまで対象に
追加しない。

想定する状態遷移は次の通り。

1. 現在の画面fingerprint、表示位置、Agentの入力状態を保存する。
2. Agentがidleで、入力欄やpermission promptを表示していないことを確認する。
3. 上方向のwheel/page相当のイベントを送り、画面更新を待つ。
4. `GHOSTTY_POINT_SCREEN`で現在表示されているentryを読み、安定IDでmergeする。
5. 画面が変わらない、上端に到達した、安全上限に達したら停止する。
6. 保存したfingerprintが再び現れるまで下方向へ戻し、元の表示状態を復元する。

クリック時もGhosttyの`scroll_to_row`は使わず、entryの安定IDを手掛かりに同じ
探索を行い、対象entryが画面に現れたところで停止する。現在の行番号はalternate
screen内の一時的な表示位置に過ぎないため、レールのIDには使わない。

providerごとにスクロール方向、bottom復帰、入力中判定、entryの境界検出が異なる
ので、`AgentConversationNavigator`のようなAdapter境界を設ける。まずは一つの
provider（Claude Code）で小さな実機検証を行い、スクロール中の画面更新と復元が安定するかを
確認してから他providerへ広げる。

この方式は常時バックグラウンドで画面を動かさず、履歴レールを開いたとき・明示的
に履歴を読み込むとき・entryをクリックしたときだけ実行する。途中でAgentがbusyに
なったり入力が発生した場合は即座にキャンセルし、可能ならbottomへ戻す。

### 第2段階：provider公式のtranscript/IPC連携

viewport captureで全履歴や復元を安定して扱えないproviderについては、providerの
公式transcript/event sourceや、TUIが提供するtranscript modeをAdapterから利用する。

1. Agent起動時にsession ID・provider・Surface IDを関連付ける。
2. providerの正式なtranscript/event sourceからentryを受け取る。
3. providerがentry単位の表示移動を提供する場合は、entry IDで`navigate`する。
4. ZashikiはSurface上のレール表示を担当し、providerごとの境界はAdapterに閉じ込める。

ログを直接読む方式は表示だけなら作れるが、rewind/compaction/複数Surface/
権限境界との対応が不安定になりやすい。まずviewport captureで実現可能性を測り、
必要なproviderだけ公式連携へ進む。

classic renderer / no-alt-screenは、この主設計が失敗した場合のfallbackまたは
診断手段として残す。ユーザーに通常運用として要求しない。

### 設定と安全策

- 設定キーはUserDefaultsに保存し、初期値は`false`にする。
- Viewメニューのチェック状態を設定値と同期する。
- 設定をオフにした時点で実行中のcapture taskをキャンセルし、可能なら保存した
  表示状態へ戻す。
- idle判定が崩れた、入力欄やpermission promptが現れた、画面が復元できない場合は
  それ以上スクロールせず停止する。

### 採用しない案

- alternate screenの内容をGhostty側で長期保存する：TUIは過去行を再描画せず、
  出力バイト列だけでは会話単位を安全に復元できない。
- Agentがbusyまたは入力受付中にPageUpやマウスホイールを送る：TUIごとに挙動が
  違い、実行中のAgentへ意図しない入力を送る危険がある。送る場合はidle判定、
  明示操作、キャンセル、表示状態の復元を必須にする。

## 実装結果

- 対象providerをClaude Codeだけに限定した。Codexは検出を残すが、会話履歴レールの
  収集・移動対象からは外す。
- `View`メニューに「Claude Code履歴の自動スクロール」を追加し、UserDefaultsへ保存
  する。初期値はオフで、オフ時は現在のviewportだけを読み取り、スクロールイベントを
  送らない。
- オン時はClaude Codeがidleかつmouse reporting中の場合だけ、最大32回の上方向scrollで
  viewportを収集する。画面が変化しなくなったら停止し、最大48回の下方向scrollで保存した
  画面fingerprintの復元を試みる。設定変更・busy化・入力待ちではcaptureをキャンセルする。
- レールのクリックは`scroll_to_row`を使わず、Claude Codeのviewportを同じ方向へ探索して
  安定entry IDを含む画面で停止する。alternate screenの行番号はviewportごとに変わるため、
  IDから除外した。
- ホバー時の二重tooltipは、カスタムプレビューと競合していた`.help`を削除して解消した。

## 検証結果と未検証事項

- `git diff --check`: 成功
- `swiftlint lint --strict`: 成功
- `xcodebuild` Debug build: 成功
- `AgentStatusTests`: 成功（安定entry IDの追加テストを含む）
- Claude Code実機でのscroll方向、全履歴収集、保存位置への復元、設定オフ時の無操作、
  レールクリック移動は未検証。実機確認が終わるまでPRには`needs-verification`を付ける。
