# GitHub Issueへの`claude`ラベル付与でClaude Codeを起動するAction

関連: [Issue #124](https://github.com/kawaken/zashiki/issues/124)

## 目的

zashiki (public repo) で、GitHub Issueに`claude`ラベルを付けると、
`claude-code-action` が起動しClaude Codeが作業を開始する仕組みを導入する。
実行のたびにcost/usageをBigQueryへ記録し、集計・可視化できるようにする。

## 決定事項

- **認証（Claude側）:** `claude setup-token` で発行したOAuthトークンを
  `CLAUDE_CODE_OAUTH_TOKEN` としてリポジトリSecretsに登録する。Pro/Maxサブスクの
  利用枠内で完結させ、API従量課金は使わない。
- **トリガー:** Issueへの`claude`ラベル付与。`claude-code-action` の
  `label_trigger` パラメータを使う。当初はIssueアサイン
  （`assignee_trigger`）を予定していたが、サードパーティのGitHub App
  はGitHub上でissueのassignee候補になれない制約があり
  （`Bot does not have access to the repository`エラーを実機で確認）、
  断念した。公式のセットアップウィザード`/install-github-app`が生成する
  デフォルトテンプレートも`assignee_trigger`を使っておらず、Anthropic側も
  同じ制約を把握して回避していると考えられる
- **起動者制限:** publicリポジトリのため、ワークフロー側で
  `if: github.actor == 'kawaken'` 等により自分がアサインした場合のみ起動する
  よう絞る。actionの `allowed_non_write_users` は使わない（公式にRISKYと
  明記されている）。
- **CI実行時のルール分離:** ルートの `CLAUDE.md` は変更しない（Codexと共有の
  ため）。`.github/claude/CI-NOTES.md` を新設し、「CI実行時はworktree/
  ブランチ作成ルールの適用外（action自体が`branch_name` outputでブランチを
  管理する）」と明記する。actionの `prompt` inputでこのファイルを読ませる
  指示を注入し、ルートのCLAUDE.mdへの追記は避ける。
- **消費量トラッキング:** actionのoutput `execution_file`（`claude -p`相当の
  JSON実行ログ。`total_cost_usd`・`usage`を含む）を実行後のステップで抽出し、
  BigQueryのrawテーブルにinsertする。Grafana Cloud無料枠（OTEL経由）も比較
  検討したが、retentionが14日と短く、既存のdbt資産に合流できるBigQuery側を
  優先する。dbtによる変換レイヤーは今回はスコープ外とし、当面はBigQuery上で
  直接SQLを書いて集計・確認する。

## 現状（進捗）

### 完了: BigQuery環境セットアップ

専用のGCPプロジェクトを新規作成し、課金アカウントを紐付けた（想定利用量は
無料枠内: クエリ月1TB / ストレージ月10GB）。課金アカウントなしの
BigQuery Sandbox は、データが60日で自動削除されストリーミングinsertも
不可のため、継続的なトラッキング用途には不採用。有効化したAPI:
`bigquery.googleapis.com`, `iam.googleapis.com`, `iamcredentials.googleapis.com`,
`sts.googleapis.com`, `cloudresourcemanager.googleapis.com`。

- データセット・テーブルを作成した。よく使う値（`run_id`, `executed_at`,
  `issue_number`, `pr_number`, `total_cost_usd`）は列として持ち、生ログ
  全体（`execution_file`）もJSON列で保持するハイブリッド構成
- GitHub Actionsからの認証はWorkload Identity連携（長期のSAキーJSONは
  発行しない）。サービスアカウントに `roles/bigquery.dataEditor` /
  `roles/bigquery.jobUser` を付与し、OIDC provider側の attribute
  condition でこのリポジトリ（`kawaken/zashiki`）以外からのimpersonation
  を拒否している。データセット単位のIAMバインディングはallowlistingが
  必要な機能でCLIから設定できなかったため、プロジェクト単位の付与に
  留めた
  - プロジェクトID・サービスアカウント名・Workload Identity Pool/Provider
    の具体的な識別子は、publicリポジトリに載せないためこの文書には
    記載しない（GCPコンソールで確認できる）
  - リポジトリSecrets登録済み: `GCP_WORKLOAD_IDENTITY_PROVIDER`,
    `GCP_SERVICE_ACCOUNT`（ワークフローからは`google-github-actions/auth`
    にこれらのSecretsを渡して利用する）

### 完了: ワークフロー実装

- `.github/workflows/claude.yml`: `issues.labeled`イベントをトリガーに、
  付与されたラベルが`claude`かつ`github.actor == 'kawaken'`の場合のみ
  `claude-code-action@v1`を実行する（`label_trigger: "claude"`）。
  実行後、`execution_file`が出力されていれば
  `google-github-actions/auth@v2`でWorkload Identity連携により認証し、
  `record_usage.py`でBigQueryに記録する（`if: always()`で、Claude Code側が
  失敗してもusageは記録する）
- `.github/claude/CI-NOTES.md`: CI実行時はworktree/ブランチ作成ルールを
  適用外とする旨、Issue/Planライフサイクルの多段階フローをCI向けに
  簡略化する旨、GCP識別子を含む公開情報の扱いを明記した
- `.github/scripts/record_usage.py`: `execution_file`（単一JSONまたは
  JSON Lines）をパースし、`type == "result"`のレコードから
  `total_cost_usd`を取り出す。BigQueryへは`load_table_from_json`で
  バッチロードする（ストリーミングinsertは無料枠外の課金対象になるため
  採用しなかった）
  - 実装時の落とし穴: JSON型カラムには生のPythonオブジェクト（dict/list）
    をそのまま渡す必要がある。事前に`json.dumps()`で文字列化して渡すと、
    その文字列自体が1つのJSON値として二重にエンコードされてしまう
    （`payload`が`"\"{...}\""`のような形になる）。ローカルでテスト
    insertして`JSON_EXTRACT_SCALAR`で検証し、この不具合を発見・修正した
  - `claude -p --output-format json`の実際のトップレベルフィールドを
    ローカル実行で確認済み: `total_cost_usd`, `usage`, `num_turns`,
    `duration_ms`, `type`, `subtype`, `result`, `session_id` 等

### 完了: GitHub App・トークン設定、トリガー方式の見直し

- GitHub App「Claude」のインストール、`CLAUDE_CODE_OAUTH_TOKEN`の発行・
  登録が完了した
- `assignee_trigger`でのE2E確認時、テスト用Issueにclaude/claude[bot]を
  アサインしようとしたところ両方とも失敗した。`claude[bot]`
  （実際のBotアカウント、type: Bot）は`Bot does not have access to the
  repository`エラーとなり、リポジトリのRepository accessにzashikiが
  含まれていても解決しなかった
- 検証のため公式の`/install-github-app`ウィザードを試したところ、
  自動生成されたPRのテンプレートは`assignee_trigger`を使わず
  `trigger_phrase`（コメントでの`@claude`メンション）方式だった。これは
  Anthropic自身がassigneeアサイン方式の制約を把握し、標準テンプレートで
  回避していることの裏付けと判断し、そのPRは取り込まずクローズした
  （BigQuery記録処理も削除されてしまうため）
- `label_trigger: "claude"`に切り替え、リポジトリに`claude`ラベルを
  新規作成した。Issueに`claude`ラベルを付ける操作は通常のwrite権限で
  行えるため、Botのassignee候補問題とは無関係に動作する見込み

### 完了: E2E動作確認1回目、2件の不具合を修正

Issue #155(テスト用)に`claude`ラベルを付け、初回のE2E実行を行った。
2つの不具合が見つかり修正した。

- **promptにIssue内容を実装する指示がなかった**: `prompt`
  にはCI-NOTES.mdを読む指示のみを書いており、「このIssueを実装して
  ください」という指示がなかった。claude-code-actionは`prompt`を
  指定すると、それだけが唯一の指示になり、Issue本文は自動注入され
  ない(ドキュメントに明記はないが実機で確認)。結果、Claudeは
  CI-NOTES.mdを読んだだけで2ターン・6秒足らずで終了し、実装は
  行われなかった。Issue本文を直接prompt埋め込むとinjectionの
  リスクがあるため、`Issue #${{ github.event.issue.number }} の
  内容を実装してください`と番号だけを渡し、Claude自身に
  `gh issue view`等のツールでIssue詳細を取得させる形にした
- **`record_usage.py`が実際のexecution_file形式に対応していなかった**:
  ローカルテストでは単一のJSONオブジェクトを想定していたが、実際の
  `execution_file`は複数メッセージを含むJSON配列全体として書き出されて
  おり、`AttributeError: 'list' object has no attribute 'get'`で失敗
  した。単一のJSON値(オブジェクトまたは配列)としてまずパースを試み、
  配列ならフラット化するよう`load_records()`を修正し、配列形式の
  execution_fileでローカル実insert・`JSON_EXTRACT_SCALAR`抽出まで
  再検証した

### 完了: E2E動作確認2回目、agent/tagモードの根本原因を特定

前回の修正(Issue番号をpromptに追記)を反映して再度E2E実行したところ、
23ターン・cost $0.37まで動いたが、Issueの内容取得もPR作成もできずに
終了した。Claudeの最終応答(BigQueryのpayloadから確認)によると、
`gh`/`curl`/`git ls-remote`/`WebFetch`など、ネットワークに触れる
操作がすべて「要承認」のまま拒否され、承認が得られなかった。

`anthropics/claude-code-action`のソースコード
(`src/modes/detector.ts`, `src/create-prompt/index.ts`)を直接確認し、
根本原因を特定した。

- `issues`イベントで`prompt`入力を指定すると、`checkContainsTrigger`
  (label_trigger等のトリガー判定)による分岐を経由せず、**無条件で
  "agent"モード**になる
- "agent"モードでは`context.prompt`の文字列だけがそのまま使われ、
  GitHub Issueの本文・タイトルなどのコンテキストは一切自動注入されない
  (これが実装できなかった直接の原因)
- `prompt`を指定しなければ、`issues`イベント+`labeled`アクション+
  ラベル名一致の条件で"tag"モードになり、GitHub Issueのコンテキストが
  自動的にdefaultPromptへ含まれる。これがAnthropicの想定する標準的な
  動作ルートと考えられる

### 決定: プロンプト差し替え方式とPhase分けした設計変更

- `prompt`入力は削除し、tagモードを維持する
- CI実行時のルール(CI-NOTES.md)は、`prompt`の代わりに`CLAUDE.md`
  (実体は`AGENTS.md`へのシンボリックリンク)を一時的に差し替えることで
  Claude Code標準の自動読み込みに乗せる。Claude Code Action実行前に
  `git update-index --skip-worktree AGENTS.md`してからCI-NOTES.mdの
  内容を追記し、実行後に`--no-skip-worktree`+`git checkout --`で復元
  する。`--skip-worktree`によりClaudeが`git add -A`等をしても差し替え
  分がステージングされず、コミットに紛れ込まない
- 併せて今後の設計変更をPhase分けして決定した(今回のPRはPhase 1のみ
  実装する)
  - **Phase 1(今回)**: 上記のtagモード化+CLAUDE.md差し替え方式を導入し、
    Issueコンテキストが正しく渡ることをE2Eで確認する。Claudeが自律的に
    コミット・PR作成する現行の設計はそのまま維持する
  - **Phase 2**: git/gh関連のBashコマンドを`claude_args`の
    `--disallowedTools`で禁止し、コミット・ブランチ作成・PR作成を
    ワークフロー側のステップに移す。Claudeには実装(ファイル編集)のみ
    させ、トークン消費を実装作業に集中させる
  - **Phase 3**: `wip`ラベルの管理を見直す。付与は引き続きClaude(または
    ワークフロー)が作業開始時に行うが、外すのはPRマージ時に移す(別途
    `pull_request: closed`イベントのワークフローが必要)
  - GitHub Projectsを使ったIssueステータス管理とClaudeの作業管理の
    分離は、今回のIssue #124のスコープを超えるため保留。必要になれば
    別Issueとして切り出す

### 完了: E2E動作確認3回目、PR自動作成の欠如を発見・自動化

Phase 1(tagモード化)を反映して再度E2E実行したところ、Claudeが実際に
Issue内容(Cmd+Yショートカット)を正しく実装し、コミット・プッシュまで
成功した(24ターン、$0.42)。tagモード化は効果があった。ただし、
`gh pr create`相当のPR作成はできず、Issueコメントに「Create PRリンク」
(GitHubのcompareページURL)を貼るだけに留まった。

最初はGitHub Actionsのリポジトリ設定「Allow GitHub Actions to create
and approve pull requests」が無効(個人アカウントのデフォルト)なことが
原因かと疑い、`can_approve_pull_request_reviews`を`true`に変更したが
効果がなかった。改めてclaude-code-actionの公式FAQを確認したところ、
**これは仕様だった**: 「Claudeはデフォルトで自動PRを作成しない。
ブランチにコミットをプッシュし、事前入力されたPR送信ページへの
リンクを提供するだけ」と明記されている。ブランチ保護ルールの尊重と、
PR作成の最終決定権をユーザーに残すための意図的な設計とのこと。

「`claude`ラベルを付けるとPRができる」というUXを実現するため、
Phase 2で予定していた「PR作成をワークフロー側に移す」を前倒しで実装
した。Claude Code Action実行後、`steps.claude.outputs.branch_name`が
あれば`gh pr create`を実行するステップを追加した(既にPRが存在する
場合や、変更がなく作成に失敗する場合はスキップする)。作成したPR番号
は`record_usage.py`の`--pr-number`にも渡すようにした
(`--issue-number`/`--pr-number`は空文字列を渡されることがあるため、
`int`ではなく空文字列をNoneとして扱うカスタム型に変更した)。

### 完了: E2E動作確認4回目、PR自動作成成功。ビルド確認とCI未トリガー問題

PR自動作成を反映して再度E2E実行したところ、実際にPR(#161)が自動作成
され、BigQueryにもissue_number/pr_numberが正しく記録された。Issue #124
の完了条件(claudeラベル付与でClaude Codeが起動しPRを作成できる、
cost/usageがBigQueryに記録される)を達成した。

残課題としてビルド確認(`just`/`zig`/`xcodebuild`がGitHub Actions runner
環境にない)を検討したが、ユーザーの判断で「Issue経由のclaude.ymlでは
実装のみ行い、ビルド確認は既存のPR向けCI(test.yml)に任せればよい」と
した。ただし、実際にPR #161のCIチェックを確認したところ
「no checks reported」で**test.ymlが全くトリガーされていなかった**。

原因はGitHub Actionsの既知の制約: `GITHUB_TOKEN`で作成したPRは、その
イベント自体が新しいワークフロー実行をトリガーしない。`Create Pull
Request`ステップで`GH_TOKEN: ${{ github.token }}`を使っていたことが
原因。actionのoutput`github_token`(GitHub App token。inputの
`github_token`が空の場合にactionが自動設定する)に切り替え、
`${{ steps.claude.outputs.github_token || github.token }}`とした。
ただし、claude-code-action内部の最後のステップで
installation tokenをrevokeしているログを確認しているため、この
outputが後続ステップでまだ有効か(revokeが完了する前にoutputとして
セットされるか)は実機で要検証。

### 完了: E2E動作確認5回目、github_token outputは使えず。PATに切り替え

`github_token` outputに切り替えて再度E2E実行したところ、予想通り
`HTTP 401: Bad credentials`でPR作成に失敗した。claude-code-action
内部の最後のステップでinstallation tokenをrevokeしており、`||`による
`github.token`へのフォールバックは値が空でないため発動しなかった
(revoke済みの無効なトークン文字列自体は空文字列ではないため)。

このリポジトリに限定し、Contents/Pull requestsをwriteに絞った
fine-grained PAT(Personal Access Token)を発行し、`GH_PAT_PR_CREATE`
としてSecretsに登録した(値はこの会話を経由せず、GitHubの管理画面に
直接貼り付けてもらった)。`Create Pull Request`ステップの`GH_TOKEN`を
これに切り替える。

### 完了: E2E動作確認6回目、PAT方式でPR作成・CIトリガーとも成功

PAT(`GH_PAT_PR_CREATE`)方式に切り替えて再度E2E実行したところ、PR(#164)
が正常に作成され、かつ`test.yml`のCI(`just lint`, `just test-fast`)が
正常にトリガーされ全部passした。Issue #124の完了条件(claudeラベル付与
でClaude Codeが起動しPRを作成できる、cost/usageがBigQueryに記録される、
PRのCIも正常に動く)を達成した。テスト用に使っていたIssue #155・
PR #164は実装内容として妥当だったためそのままマージ・クローズした。

### 決定: Phase 2, 3もIssue #124のスコープに含めて実装する

ユーザーから「全部やってほしい」との指示があり、Phase 2(git操作の
分離)・Phase 3(wipラベル管理の見直し)も本Issueの中で実装する。

### Phase 2実装: git/PR操作をワークフロー側に分離

`Run Claude Code`ステップの実行ログから、Claudeが実際にファイルの
コミット・プッシュに使っているツールを特定した:
`Bash(git add:*)`, `Bash(git commit:*)`, `Bash(git rm:*)`,
`Bash(.../scripts/git-push.sh:*)`(専用スクリプト経由のpush)。加えて
GitHub API経由で直接コミットを作る`mcp__github_file_ops__commit_files`/
`delete_files`というMCPツールも存在する(`use_commit_signing: true`の
場合に使われると推測、デフォルトはfalseなので通常は前者のBash系が
使われる)。

- `claude.yml`にワークフロー側で作業用ブランチを作成するステップ
  (`Create working branch`)を追加した。Claude実行前に
  `claude/issue-<番号>-<タイムスタンプ>`ブランチへ切り替える
- `Run Claude Code`ステップに`claude_args`の`--disallowedTools`を追加し、
  上記のgit系コマンドとMCPツールを禁止した。Claudeにはファイル編集
  (Edit/Write等、常時許可される基本ツール)のみを行わせる
- 実行後、`Commit and push changes`ステップを追加。`git status
  --porcelain`で変更の有無を確認し、あれば`git add -A && git commit &&
  git push`を行う。コミットメッセージはIssueタイトル+
  `Related to #<番号>`とする、変更がなければスキップする
  (`has_changes` outputで後続のPR作成ステップに伝える)
- `Create Pull Request`ステップの参照先を`steps.claude.outputs.
  branch_name`から`steps.branch.outputs.branch_name`(ワークフロー側で
  作成したブランチ)に変更した

### Phase 2の不具合修正: git push認証エラー

E2Eテスト用に軽量なIssue #166を新規作成して確認したところ、
`Commit and push changes`ステップで`git push`が
`Invalid username or token. Password authentication is not supported`
で失敗した。想定通り、Claude Code Action実行中にremoteの認証情報が
書き換えられ、action終了時のtoken revoke処理の影響で無効化されていた。
`git remote set-url`でPAT(`GH_PAT_PR_CREATE`)を使い、push前に明示的に
認証情報を再設定するよう修正した。

### Phase 2の不具合修正2: PR作成のレースコンディション

認証修正後に再度E2E確認(Issue #166)したところ、`git push`自体は成功
したが、直後の`gh pr create`が
`GraphQL: No commits between main and <branch>`で失敗した。`git push`
直後はGitHub側のレプリケーションが追いついておらず、GraphQL API側では
まだ新しいコミットが認識されないタイミング問題(既知のレースコンディ
ション)。`gh pr create`に最大5回・5秒間隔のリトライを追加した。

### 未着手

- 上記(PR作成リトライ)を反映した状態での再E2E確認
- Phase 3(wipラベルをPRマージ時に外す。別途`pull_request: closed`
  イベントのワークフローが必要)の実装
- dbtプロジェクトの構築（後回し。当面はBigQuery上の直接SQLで集計する）

## 完了条件

- Issueに`claude`ラベルを付けると、上記制約下でClaude Codeが起動しPRを
  作成できる (Phase 1の範囲で達成済み)
- 実行のたびにcost/usageがBigQueryに記録され、集計・可視化ができる
  (達成済み)
- Claudeの作業はファイル編集のみとし、git/PR操作はワークフロー側の
  決定的なロジックで行う (Phase 2、実装中)
- `wip`ラベルはPRマージ時に外れる (Phase 3、未着手)
