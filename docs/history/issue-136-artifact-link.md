# PRマージ後のビルドartifact URL案内

## 目的

`needs-verification`付きPRで生成した`Zashiki.app`のGitHub Actions artifactを、
PRマージ後も関連Issueからダウンロードできるようにする。

## 実装内容

- `.github/workflows/comment-build-artifact.yml`を追加した
- `Test` workflowの成功完了と、マージ済み`pull_request`のクローズを監視する
  - CIが先に完了してからマージされる場合
  - マージ後にCIが完了する場合
    の両方を処理する
- `workflow_run`のhead SHAから関連PRを取得し、または`pull_request`のhead SHAから
  成功済みの`Test` runを取得する
- マージ済みであること、`Test`が成功していること、PR番号に対応する
  `Zashiki-pr<N>` artifactが存在し期限切れでないことをすべて確認する
- PR本文の同一リポジトリIssue参照を対象とし、対象IssueへartifactページのURLを
  コメントする
- コメントにはartifactの有効期限と、GitHubログイン・アクセス権が必要なことを案内する
- run/artifact IDの隠しマーカーで同じartifactの二重投稿を防ぐ

## 対象外

- `needs-verification`が付いていないPRへのartifact生成
- CI失敗時やartifactが存在しない場合のIssueコメント
- 期限切れartifactの再公開・長期保存

## 検証

- Ruby YAMLパーサーでworkflowの構文を確認
- `actions/github-script`の埋め込みJavaScriptを構文チェック
- GitHub APIレスポンスを模したモックで、成功済みartifactのコメント生成を確認
- `git diff --check`を実行

CIではSwiftLintの更新により既存の`aspectRatio(contentMode: .fit)` 2箇所が新しい
`legacy_swiftui_aspect_ratio`違反になったため、同等の`scaledToFit()`へ置換して
必須lintを通過させた。
