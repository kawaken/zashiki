# CI必須チェックとdocs-only高速マージの両立

## 概要

`main`向けRulesetにPull RequestとCIの必須条件が設定されていないため、
AutoMergeがGitHub Actionsの完了を待たずにマージされる状態になっている。
一方、現在のworkflowは`paths-ignore`で設計ドキュメントなどを除外しており、
CIをrequired status checkにすると、docs-onlyのPRでworkflowがskipされて
Pendingのままマージできなくなる。

コード変更ではCI完了を必須にしつつ、Markdown・設計ドキュメントだけのPRは
これまでどおり高速にAutoMergeできるよう、workflowとRulesetを組み合わせて
修正する。

## Issue

- https://github.com/kawaken/zashiki/issues/115
- プランファイル: https://github.com/kawaken/zashiki/blob/ci-required-checks/plan/required-ci-checks-with-docs-bypass.md

## 現状

- `main`のRulesetは存在するが、削除禁止とforce push禁止だけが設定されている
- Pull Request必須、`just lint`、`just test-fast`のrequired status checkは未設定
- `.github/workflows/test.yml`の`pull_request`は`paths-ignore`でdocs-onlyの変更を除外している
- docs-onlyでworkflow自体がskipされると、required checkはPendingになり得る
- `zig build (macOS app)`は`workflow_dispatch`限定のため、PR必須チェックの対象外とする

## 目標

- コード変更を含むPRは、`just lint`と`just test-fast`が成功するまでマージできない
- Markdown・`plan/`・`docs/history/`などのdocs-only PRは、重いCIを実行せずAutoMergeできる
- docs-onlyとコード変更の混在PRでは、通常どおりCIを実行する
- workflow自身の変更は検証対象から除外せず、CI設定の変更も検出できる

## 対応方針

### 1. workflowのトリガーと変更判定を整理する

- `pull_request`イベントではworkflow全体を常に起動し、workflowレベルの
  `paths-ignore`でrequired checkを消す構成をやめる
- 最初に変更ファイルを判定するjobを追加し、コード関連の変更があるかをoutputにする
- 変更判定用jobは外部依存を増やさず、PRのbaseとheadの差分から判定する
- `just lint`と`just test-fast`は変更判定jobに依存させ、docs-onlyならjob-levelの
  `if`でskipする
- GitHub Actionsでは条件付きでskipされたjobはSuccess扱いになるため、docs-onlyでも
  required checkがPendingにならない構成にする
- 既存のdocs-only対象（`plan/**`、`docs/history/**`、`.claude/**`、
  `README.md`、`AGENTS.md`、`CHANGELOG.md`、`LICENSE`、`typos.toml`、
  `Makefile`）を判定ルールへ移す
- `.github/workflows/**`は判定対象から外さず、workflow変更時はCIを実行する

### 2. Rulesetにマージ条件を追加する

- 既存の`main` RulesetにPull Request必須を追加する
- `just lint`と`just test-fast`をrequired status checksに追加する
- `zig build (macOS app)`はPRで実行されないためrequiredにしない
- 必須チェックの設定はworkflow変更がmainへ反映され、チェック名が確認できてから行う

### 3. 既存の開発運用を維持する

- 通常のマージコミットを使うAutoMerge運用を維持する
- macOS appの実ビルドをPRごとに実行する構成には変更しない
- このIssueではアプリ本体の機能やローカルテスト内容は変更しない

## 検証

- コード変更だけのPRで`just lint`と`just test-fast`が実行されること
- docs-onlyのPRでworkflowは起動し、2つのrequired checkがSuccess（skip）になること
- docsとコードを混在させたPRでCIが実行されること
- `.github/workflows/`の変更でCIがskipされないこと
- required check未完了のコード変更PRではAutoMergeが待機すること
- required check完了後にAutoMergeが通常のマージコミットで進むこと
- `just lint`と`just test-fast`を実行すること

## 完了条件

- workflowの変更がmainへ反映されている
- `main` RulesetにPull Request、`just lint`、`just test-fast`の必須条件が設定されている
- コード変更PRはCI完了前にマージされない
- docs-only PRの高速マージが維持されている
- Ruleset変更と検証結果をIssueへ記録する
