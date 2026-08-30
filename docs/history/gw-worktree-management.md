# `gw` Worktree Status サイドパネル

## 経緯

当初は「`kawaken/gw`をGit worktree管理ツールとして採用するか」を検討する計画だった。実際に`gw guide`、`gw list [--json]`、`gw inspect <worktree> [--json]`、`gw refresh [--json]`、`gw clean --dry-run`を実行して動作確認した結果、`gw`はGit状態・GitHub PR状態（gh経由）・エージェントセッション状態（claude:active/ended/unknown）を突き合わせて`keep`/`review`/`recommended`のcleanup判定を返すツールとして十分機能しており、採用は確定方向。

その後、この`gw`の情報をZashiki本体のUIに統合したいという要望が出た。「Markdownプレビューのように、左側のサイドパネルでworktree状態を確認したい。将来的にはVSCodeのように複数の情報パネルを切り替えられるものにしたいが、今回はそこまでやらない」という方針。

そこで本プランは「gwの適合性検討」から「gw情報を表示するworktree状態サイドパネルの実装」へ切り替える。既存のMarkdown Preview機能（右側パネル、`SplitView`ベース）が唯一かつ最も近い実装前例であり、これをテンプレートとして左パネルを実装する。

### 2026-08-31 追記：実装着手前の再確認

Issue化後に`gw`本体が更新されており、`gw list --json`/`gw clean --dry-run --json`のスキーマが当初の想定から変わっていた（`schema_version`フィールドの追加、`github`直下だった`pr`情報が`github.pr`のネスト構造に変更、`agent.provider`（`claude`/`codex`の区別）の追加）。「tolerantに文字列としてデコードする」という設計方針自体は変わらないが、構造体のネスト構成は現物に合わせて更新する（詳細は「`GwSchema.swift`」の項）。

また、追加の要望が来たためスコープを次の3点変更する。

1. **`gw clean`をUIから呼べるボタンを追加する**（当初「対象外」としていたが要望により追加）。個別worktreeの選択削除までは対応せず、`gw clean`（recommended判定のもの一括）をボタン一つで実行できれば十分とする。破壊的操作のため確認ダイアログを挟む。
2. **PR番号は`#123`形式のテキスト＋GitHub URLへのリンクとして表示する。**
3. **各行の状態表現は極力アイコンベースにする**（agentのprovider/lifecycle、git clean/dirty、cleanupの推奨度をSF Symbolsで視覚化し、branch名以外はテキストに頼りすぎない）。

## 実装内容

### 新規ファイル（`macos/Sources/Features/Worktree Status/`）

| ファイル | 役割 |
|---|---|
| `WorktreeStatusModel.swift` | ウィンドウ単位の状態を持つ`ObservableObject`。`isVisible`/`worktrees`/`isLoading`/`errorMessage`/`lastUpdatedAt`/`revision`。`open()`/`close()`/`toggle()`/`refresh(directory:)`。`MarkdownPreviewModel.swift`が雛形。 |
| `GwSchema.swift` | `gw list --json`/`gw clean --json`のCodable構造体群。トップレベルに`schema_version`（`Int`。想定外の値でも読み捨てて処理は継続し、UIに警告は出さない）。`worktree.github.pr`は`GwPullRequest?`のネスト構造体（`number: Int`, `title: String`, `state: String`, `merged_at: String?`, `url: String`, `head_branch: String`）として持ち、`worktree.github.status`（`available`等）と分ける。`worktree.agent.provider`（`claude`/`codex`/欠落＝Optional）を追加。列挙的な文字列フィールド（`cleanup.recommendation`, `agent.lifecycle`, `agent.activity`, `github.status`, `agent.provider`等）はSwift `enum`に直接デコードせず`String`として保持し、UI側でtolerantに`switch`＋`default`変換する（`gw`のマイナー更新で未知の値が増えてもデコード全体が失敗しないようにするため）。 |
| `GwClient.swift` | `Process`起動・PATH解決・タイムアウト・stdout/stderr分離取得・デコードを担う層。`func fetchWorktrees(directory: URL) async throws -> GwListOutput`、`func clean(directory: URL) async throws -> GwCleanOutput`（`gw clean --json`。dry-runは使わずUI側で確認ダイアログを出してから直接実行する）。 |
| `WorktreeStatusSplit.swift` | `MarkdownPreviewSplit`の左パネル版（`SplitView(.horizontal, $split, left: WorktreeStatusPane, right: content)`）。 |
| `WorktreeStatusPane.swift` | ヘッダー（タイトル・更新ボタン／スピナー・`gw clean`ボタン・閉じるボタン）＋本体（loading/error/gw未検出/pwd未確定/空/一覧の各状態）。`gw clean`ボタンは`cleanup.recommendation == "recommended"`が1件も無い場合は無効化。押下で確認ダイアログ（対象branch・PR番号の一覧を表示）→実行→完了後`refresh()`。 |
| `WorktreeStatusRowView.swift` | 1worktree分の行UI。branch名（またはdetached時は短縮HEAD）はテキスト表示、それ以外は極力SF Symbolsアイコン化する：git clean/dirtyの丸アイコン、agent providerのアイコン＋lifecycle（active/ended/unknown）を色で表現、cleanupの推奨度アイコン（recommended/review/keep）、ahead/behindの矢印＋数字、lockアイコン。PRは`#<number>`のテキストリンク（`state`で色分け、クリックで`url`を開く）として表示。 |

### 変更ファイル

| ファイル | 変更内容 |
|---|---|
| `macos/Sources/Features/Terminal/BaseTerminalController.swift` | `let worktreeStatus = WorktreeStatusModel()`を`markdownPreview`と並べて追加。`toggleWorktreeStatus(_:)` IBActionを追加。 |
| `macos/Sources/Features/Terminal/TerminalView.swift` | `TerminalViewModel`プロトコルに`var worktreeStatus: WorktreeStatusModel { get }`を追加。既存の`MarkdownPreviewSplit`をさらに`WorktreeStatusSplit`で外側からラップ。既存の`@FocusedValue(\.zashikiSurfacePwd)`を使い、`.onChange`でデバウンス付き再取得をトリガー。 |
| `macos/Sources/App/macOS/MainMenu.xib` | Viewメニューに「Toggle Worktree Status」を追加、`toggleWorktreeStatus:`へ接続。 |

## 主要な設計判断

1. **データ取得はSwift `Process`で直接`gw list --json`を呼ぶ**（Zig CLI経由は不採用）。Zig CLI経由にしても結局Swift側が`zashiki`バイナリを`Process`起動する必要があり、工程が増えるだけで解決する問題がない。Swiftで`Process`を使う前例はゼロだが、今回のような「GUIが外部コマンドの結果を能動的に取り込む」ユースケース自体が初めてなので新規開拓する。
2. **更新トリガーは「パネル表示時」「手動更新ボタン」「フォーカス中サーフェスのpwd変化（デバウンス300〜500ms）」の3つのみ。自動ポーリングは行わない。** 実測で`gw list --json`は約5秒かかる（GitHub/agent情報取得が支配的）。常時ポーリングはコストが高すぎる。`MarkdownPreviewFileWatcher`がイベント駆動でポーリングを避けている既存方針とも揃える。
3. **`gw`未インストール／非Git環境ではパネルを無効化せず、エラー状態を表示する。** `git worktree list`ベースの簡易フォールバックはV1では実装しない（cleanup判定・PR状態・agent状態という付加価値のほとんどが`gw`固有情報であり、フォールバックしても大きく劣化した表示にしかならないため）。PATH解決は`ProcessInfo.environment["PATH"]`→既知のインストール先（`/opt/homebrew/bin`, `/usr/local/bin`, `~/go/bin`, `~/.local/bin`）→`ZASHIKI_GW`環境変数の順に探索する。
4. **表示対象リポジトリは`surfacePwd`から決定。** `gw`に`-C`相当のフラグは無く、`git`同様カレントディレクトリから親を辿って解決するため、`Process.currentDirectoryURL`に`surfacePwd`を渡すだけでよい。`surfacePwd`が`nil`の場合はホーム等へフォールバックせず、明示的な空状態を表示する。
5. **将来のパネル切り替え基盤は作り込まない。** 今回はMarkdown Preview（右）とWorktree Status（左）が別サイドなので、同一スロットでの切り替えUIは不要。`isVisible`＋`open/close/toggle`という共通の形と、モデル/ビューの責務分離だけ守っておく（Rule of Three：2例目で無理に共通化しない）。

## エラーハンドリング

`GwClientError`として`.binaryNotFound` / `.processFailed(exitCode:, stderr:)` / `.timedOut`（15〜20秒閾値） / `.decodingFailed`を区別し、それぞれ異なるメッセージを表示する。取得失敗時も直前の`worktrees`一覧は消さず、`errorMessage`と`lastUpdatedAt`の古さだけ更新する（`MarkdownPreviewModel.errorMessage`と同じ設計）。`clean()`の失敗も同様に`errorMessage`へ反映し、`worktrees`は変更しない（部分的に削除が成功していた場合は直後の`refresh()`で実態に追従させる）。

## `gw clean`ボタンの挙動

1. ヘッダーの`gw clean`ボタンは`cleanup.recommendation == "recommended"`のworktreeが0件のとき非活性。
2. 押下時、対象worktree（branch名・PR番号があれば`#123`）の一覧を確認ダイアログ（`NSAlert`）に列挙し、実行/キャンセルを選ばせる。
3. 実行を選ぶと`GwClient.clean(directory:)`（`gw clean --json`、dry-runなしの実削除）を呼ぶ。ボタンはローディング状態にしてボタン自体を無効化（二重実行防止）。
4. 成功・失敗いずれも完了後に`refresh()`し、`worktrees`を最新化する。失敗時は`errorMessage`にstderrの要約を表示する。
5. `--dry-run`はUIからは呼ばない（確認ダイアログ自体がdry-runの代替）。

## 実装ステップ

1. `GwSchema.swift`：Codable構造体とtolerant変換。fixture（PR有無、detached、locked、agent情報欠落、`provider`欠落パターン）でデコード検証。
2. `GwClient.swift`：PATH解決・`Process`起動・タイムアウト・エラー型・`fetchWorktrees`/`clean`。バイナリパスをDIできる初期化子でテスト可能にする。
3. `WorktreeStatusModel.swift`：`GwClient`を呼ぶ状態管理（`refresh`/`clean`）。
4. `WorktreeStatusPane.swift`/`WorktreeStatusRowView.swift`：各状態のUI、アイコン表現、PRリンク、`gw clean`ボタンと確認ダイアログ。
5. `WorktreeStatusSplit.swift`：左パネル版`SplitView`ラッパー。
6. `BaseTerminalController.swift`・`TerminalView.swift`・`MainMenu.xib`の配線、`surfacePwd`デバウンス再取得。
7. 実機でのPATH問題を確認し、必要ならフォールバック探索先を調整。
8. Xcodeビルド・動作確認、Markdown Previewとの左右同時表示確認。

## 検証

- 実機ビルドで複数worktreeを持つ本リポジトリを開き、パネル表示内容が`gw list --json`の実行結果と一致することを確認。
- detached HEAD、PRなし、agent情報欠落（`provider`欠落含む）のworktreeがクラッシュせず適切な代替表示になることを確認。
- `gw`をPATHから外した状態でエラー表示になり、メニュー項目自体は有効なままであることを確認。
- 非Gitディレクトリにフォーカスした状態でエラーメッセージが表示されることを確認。
- 更新ボタン押下中、約5秒のローディング表示でUIがフリーズしないことを確認。
- PRバッジをクリックしてデフォルトブラウザでPRページが開くことを確認。
- recommended対象がない状態で`gw clean`ボタンが非活性になることを確認。
- recommended対象がある状態で`gw clean`実行→確認ダイアログ→実行後に一覧が更新され、削除されたworktreeが消えることを確認。
- Markdown Preview（右）とWorktree Status（左）同時表示でレイアウトが破綻しないことを確認。
- 複数ペイン（別worktree）間のフォーカス切り替えでパネル内容が追従することを確認。

## 対象外（将来課題）

- パネル切り替えUI（VSCode的なアクティビティバー、同一スロットでの複数パネル排他表示）
- 個別worktreeを選択しての部分削除（`gw clean`は一括実行のみ対応）
- `zashiki://worktree-status/...`のようなCLIトリガーの新設
- `gw`未検出時の`git worktree list --porcelain`ベース簡易フォールバック
- 自動ポーリング（低頻度タイマーによるambient更新）
- `gw inspect`によるworktree詳細ドリルダウン
- 設定ファイルでのパネル無効化・`gw`パス明示設定UI

## 完了後

実装PRがmainへマージされたら、このプランを`plan/`から削除する。PATH解決やエラーハンドリングで実装時に判明した知見があれば`docs/history/`へ短い履歴を残す。
