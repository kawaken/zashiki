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

- GCPプロジェクト: `zashiki-analytics`
  - 課金アカウントを紐付け済み（想定利用量は無料枠内: クエリ月1TB / ストレージ
    月10GB）
  - 課金アカウントなしの BigQuery Sandbox は、データが60日で自動削除され
    ストリーミングinsertも不可のため、継続的なトラッキング用途には不採用
  - 有効化したAPI: `bigquery.googleapis.com`, `iam.googleapis.com`,
    `iamcredentials.googleapis.com`, `sts.googleapis.com`,
    `cloudresourcemanager.googleapis.com`
- データセット: `claude_usage`（ロケーション: `asia-northeast1`）
- テーブル: `claude_usage.raw_executions`
  - よく使う値は列として持ち、生ログ全体もJSON列で保持するハイブリッド構成
  - スキーマ:
    - `run_id` STRING REQUIRED（GitHub Actions run ID）
    - `executed_at` TIMESTAMP REQUIRED
    - `issue_number` INTEGER NULLABLE
    - `pr_number` INTEGER NULLABLE
    - `total_cost_usd` FLOAT NULLABLE
    - `payload` JSON NULLABLE（`execution_file`全体）
- GitHub Actionsからの認証: Workload Identity連携（長期のSAキーJSONは発行
  しない）
  - サービスアカウント: `github-actions-bq-writer@zashiki-analytics.iam.gserviceaccount.com`
    - ロール: `roles/bigquery.dataEditor`, `roles/bigquery.jobUser`
      （プロジェクト単位。データセット単位のIAMバインディングは
      allowlistingが必要な機能でCLIから設定できなかったため見送り）
  - Workload Identity Pool: `github-actions-pool`
  - OIDC Provider: `github-provider`
    - issuer: `https://token.actions.githubusercontent.com`
    - attribute mapping: `google.subject=assertion.sub`,
      `attribute.repository=assertion.repository`,
      `attribute.actor=assertion.actor`
    - attribute condition: `assertion.repository=='kawaken/zashiki'`
      （このリポジトリ以外からのimpersonationを拒否）
  - リポジトリSecrets登録済み: `GCP_WORKLOAD_IDENTITY_PROVIDER`,
    `GCP_SERVICE_ACCOUNT`

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
