# Issue起点のPlanライフサイクルへ変更

## Issue

- https://github.com/kawaken/zashiki/issues/123

## 背景

現在はPlanを先に作成してIssueへ同期する運用だが、課題の優先度を決める前に
Plan作成とPRが必要になっている。Issueを先に起点にし、実装に必要な設計を
Planへ整理する流れへ変更する。

## 方針

- ユーザーが対応するIssueを選び、エージェントへ依頼する。
- エージェントはIssueを確認してPlanを検討し、作業ブランチでコミット・プッシュしたうえでdraft PRを作成する。
- ユーザーのPlanレビュー後、エージェントが実装・検証し、PRを通常状態へ変更する。
- 実装完了時はPlanへ実装上の判断やCI結果を追記し、同じPR内で`docs/history/`へ移動する。Plan移動だけの別PRは作成しない。
- Issueは課題と進捗の起点とし、詳細な設計・実装判断はPlanを正とする。
- ユーザーがPlan作成から実装・検証まで一気に依頼した場合は、draft PRでのレビュー段階を省略できる。

## 変更対象

- `AGENTS.md` の「Plan and Issue Lifecycle」節を上記のIssue起点の流れに合わせる。

## 検証

- `git diff --check`
- 変更後のライフサイクル記述が、Issue #123の依頼内容と矛盾しないことを確認する。

## 実装結果

- `AGENTS.md` をIssue起点の運用へ更新し、Planレビュー用のdraft PRと同一PR内での履歴移動を明記した。
- ドキュメント変更のため、アプリのビルド・テストは実施していない。
