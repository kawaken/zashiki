# Aboutダイアログの修正

## 概要

AboutダイアログにあるDocsボタンが、Zashikiでは提供していない
Ghostty本家のヘルプページへリンクしている。現状はZashiki独自のヘルプページが
ないため、誤解を招くDocsボタンをAboutダイアログから削除する。

## Issue

- https://github.com/kawaken/zashiki/issues/102

## 現状

- `AboutView`が`https://ghostty.org/docs`をDocs URLとして保持している
- AboutダイアログにDocsボタンが表示され、上記URLを開く
- GitHubボタンはZashikiのリポジトリを開くため、引き続き利用できる
- メインメニューのHelp項目はすでにZashikiのGitHubリポジトリを開く実装になっている
- Issueの記載どおり、Build情報の変更は今回の対象外とする

## 期待する動作

- AboutダイアログにDocsボタンを表示しない
- GitHubボタン、バージョン・Build・Commitの表示は現在の動作を維持する
- AboutダイアログからGhostty本家のヘルプページへ遷移する導線をなくす

## 対応方針

1. `macos/Sources/Features/About/AboutView.swift`からDocs URLの定義を削除する
2. 同ファイルのDocsボタンと、それに必要な条件分岐を削除する
3. `openURL`はGitHubボタンで使い続けるため、不要になった場合を除いて維持する
4. Aboutダイアログのボタン配置と既存表示に意図しない変更がないことを確認する

## 検証

- `git diff --check`
- AboutダイアログのUIを確認し、DocsボタンがなくGitHubボタンだけ残ることを確認する
- バージョン、Build、Commitの表示とリンクが維持されていることを確認する
- BuildはIssueの指定どおり実行しない

## 対象外・今後の検討

- Zashiki独自のドキュメントページの新設
- メインメニューのHelpリンクの変更
- Update画面など、リリースノートを参照する既存リンクの変更

## 完了後

実装が完了したら、このプランを`docs/history/`へ移動する。実装上の判断や検証結果に
記録価値がある場合は、短い履歴として追記する。その後、Issueの`wip`ラベルを外して
Issueを明示的にクローズする。

## 実装結果

- `AboutView`からGhostty本家のDocs URLとDocsボタンを削除した
- GitHubボタンとVersion・Build・Commit表示は変更していない
- `just lint`（Zig format check / SwiftLint）を実行し、違反0件を確認した
- Issueの指定どおり、BuildとUIの実機確認は実施していない
