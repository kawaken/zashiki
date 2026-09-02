# CI の Node.js 20 deprecated アノテーション対応

## 目的

GitHub Actions の CI 実行時に表示される `Node.js 20 is deprecated.` アノテーションを
解消し、Zig のセットアップ処理を Node.js 24 ランタイムで実行する。

## 現状と調査結果

- `test.yml` と `release.yml` の全ジョブが `mlugg/setup-zig@d1434d0...`（v2.2.1）を
  利用している。
- v2.2.1 の公式 `action.yml` は `runs.using: node20` を指定している。
- `mlugg/setup-zig` には Node 24 対応だけを行った公式ブランチがあり、v2.2.1 からの
  実装差分はランタイム指定とパッケージメタデータのみである。
- 他の利用アクションは、checkout、upload-artifact、release が Node 24 対応済みで、
  cache の Node 20 は今回の Issue の警告対象として報告されていない。

## 実装方針

- `mlugg/setup-zig` を Node 24 対応コミット `272b55e6c4fcef353f6d923050ff32f018636378`
  に SHA 固定で更新する。
- バージョン取得、キャッシュ、Zig のセットアップ手順は変更しない。
- 同じ Action を参照する全箇所を一括更新し、CI 経路による設定差異を作らない。

## 検証

- YAML の差分と `git diff --check` を確認する。
- `action.yml` の Node 24 対応を公式リポジトリのコミットと照合する。
- ワークフロー変更を含むため、GitHub Actions の `test` ジョブが実行されることを確認する。

## 完了後

実装完了後、この内容に実装結果と CI の確認結果を追記して
`docs/history/issue-128-node24-actions.md` へ移動する。
