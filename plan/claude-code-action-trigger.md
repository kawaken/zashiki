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

### 完了: ワークフロー実装

- `.github/workflows/claude.yml`: `issues.assigned`イベントをトリガーに、
  `github.actor == 'kawaken'`の場合のみ`claude-code-action@v1`を実行する。
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

### 未着手

- GitHub App「Claude」のインストールと `CLAUDE_CODE_OAUTH_TOKEN` の登録
  （ブラウザでの手動操作が必要）
- 上記のセットアップ後、実際にIssueをアサインしてのE2E動作確認
- dbtプロジェクトの構築（後回し。当面はBigQuery上の直接SQLで集計する）

## 完了条件

- Issueに担当者としてClaudeをアサインすると、上記制約下でClaude Codeが起動し
  PRを作成できる
- 実行のたびにcost/usageがBigQueryに記録され、集計・可視化ができる
