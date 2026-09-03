# GitHub IssueアサインでClaude Codeを起動するAction

関連: [Issue #124](https://github.com/kawaken/zashiki/issues/124)

## 目的

zashiki (public repo) で、GitHub Issueに担当者としてClaudeをアサインすると、
`claude-code-action` が起動しClaude Codeが作業を開始する仕組みを導入する。
実行のたびにcost/usageをBigQueryへ記録し、集計・可視化できるようにする。

## 決定事項

- **認証（Claude側）:** `claude setup-token` で発行したOAuthトークンを
  `CLAUDE_CODE_OAUTH_TOKEN` としてリポジトリSecretsに登録する。Pro/Maxサブスクの
  利用枠内で完結させ、API従量課金は使わない。
- **トリガー:** Issueアサイン。`claude-code-action` の `assignee_trigger`
  パラメータを使う。GitHub App「Claude」をインストールすると、assigneeに設定
  できるbotユーザーが使えるようになる。
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

### 未着手

- `.github/workflows/claude.yml` の実装
- `.github/claude/CI-NOTES.md` の作成
- BigQueryへのinsert処理（`execution_file`パース、
  `google-github-actions/auth` + `google-github-actions/upload-bigquery-data`
  or `bq load` の実装）
- GitHub App「Claude」のインストールと `CLAUDE_CODE_OAUTH_TOKEN` の登録
- dbtプロジェクトの構築（後回し。当面はBigQuery上の直接SQLで集計する）

## 完了条件

- Issueに担当者としてClaudeをアサインすると、上記制約下でClaude Codeが起動し
  PRを作成できる
- 実行のたびにcost/usageがBigQueryに記録され、集計・可視化ができる
