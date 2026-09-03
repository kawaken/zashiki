# CI実行時の注意事項（claude-code-action）

このファイルは、GitHub Issueのアサインをトリガーに起動する
`claude-code-action`実行時にのみ適用される。ローカルでの開発作業には
適用しない。作業を始める前に必ず読み、内容に従うこと。

## Git Worktree / ブランチ運用の適用外

ルートの`CLAUDE.md`にはworktree/ブランチ作成に関する運用ルールが
書かれているが、CI実行時はこの適用外とする。`claude-code-action`自体が
`branch_name` outputで実行ごとのブランチを作成・管理するため、追加の
ブランチ作成やworktree操作を行う必要はない。actionが用意した作業ツリー・
ブランチ上でそのまま変更すること。

## Issue/Planライフサイクルの簡略化

`CLAUDE.md`の「Plan and Issue Lifecycle」に定めるIssueのclaim(`wip`
ラベル)、Plan作成・draft PRでのレビューといった多段階フローは、人間の
セッションでの運用を想定している。CI実行は1回の起動で完結させる必要が
あるため、次のように簡略化する。

- Issueのclaim(`wip`ラベル・コメント)は行わなくてよい。アサインされた
  こと自体がclaim済みの意思表示とみなす
- `plan/`にPlanを作ってレビューを挟むフローは省略し、実装まで一度に
  進めてよい。設計上の重要な決定はPRの本文に書く
- 変更が完了したら、actionが作成したブランチからPRを作成する
- PRの作成後、`gh pr merge --auto --merge`でAutoMergeを有効にする。
  ただし見た目や挙動の確認が要る規模の変更だと判断した場合は、
  `needs-verification`ラベルを付けてAutoMergeを有効にしない

## 公開情報の扱い

`CLAUDE.md`の「Public-Facing Work」に従い、個人環境のパス・設定・GCP
リソースの識別子（プロジェクトID、サービスアカウント名、Workload
Identity Pool/Provider名など）はPR本文・Issueコメント・コミット
メッセージに書かない。
