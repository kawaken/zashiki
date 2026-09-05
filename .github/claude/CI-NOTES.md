# CI実行時の注意事項（claude-code-action）

この内容は、GitHub Issueに`claude`ラベルを付けることをトリガーに起動
する`claude-code-action`実行時のみ、ワークフローによって`CLAUDE.md`の
末尾に一時的に追記される。ローカルでの開発作業には適用しない。

この差し替えは実行のたびにワークフロー側が行うため、`CLAUDE.md`自体を
編集・訂正する作業は行わないこと（実行後に元の内容へ復元される）。

## Git操作・PR作成・wipラベル管理はワークフロー側が行う

ルートの`CLAUDE.md`にはworktree/ブランチ作成に関する運用ルールが
書かれているが、CI実行時はこの適用外とする。ブランチの作成・コミット・
プッシュ・PR作成・`wip`ラベルの付与/削除は、すべてワークフロー
(`claude.yml`, `remove-wip-on-merge.yml`)側が決定的なロジックで行う。
あなたの役割はIssueの内容を実装すること(ファイルの読み書き)のみで、
`git add`/`git commit`/`git push`やIssue・PRのラベル/コメント操作は
行わない(そもそもツール制限で実行できない)。

## Issue/Planライフサイクルの簡略化

`CLAUDE.md`の「Plan and Issue Lifecycle」に定めるPlan作成・draft PR
でのレビューといった多段階フローは、人間のセッションでの運用を想定
している。CI実行は1回の起動で完結させる必要があるため、
`plan/`にPlanを作ってレビューを挟むフローは省略し、実装まで一度に
進めてよい。設計上の重要な決定は、実装内容が分かるようにファイルの
コメント等に残す。

## 公開情報の扱い

`CLAUDE.md`の「Public-Facing Work」に従い、個人環境のパス・設定・GCP
リソースの識別子（プロジェクトID、サービスアカウント名、Workload
Identity Pool/Provider名など）はPR本文・Issueコメント・コミット
メッセージに書かない。
