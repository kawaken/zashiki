# Issue #152: `gw list --json` schema v2 対応

## 目的

`kawaken/gw` の JSON schema v2 で追加された GitHub PR 検索状態を、Zashiki の Worktree Status に正しく反映する。PR がない状態、ブランチ等の理由で確認できない状態、GitHub 連携の取得失敗を `github.pr == null` だけで同一視しない。

## 方針

- `schema_version: 2`、トップレベルの `sources.github`、`errors` を既存の Codable モデルで受け取れることを fixture で検証する。
- `worktrees[].github.status` は文字列のまま保持し、`found`、`not_found`、`unknown`、`unavailable` を UI の状態アイコンと tooltip に変換する。
- `found` で PR がある場合は、既存の PR 番号リンクと state 色分けを維持する。
- 未知の status は将来の `gw` 更新でデコードを壊さず、汎用の状態アイコンと人間向けの tooltip を表示する。
- v1 の fixture/cached status `available` もデコード可能な状態を保つ。ただし v2 の表示確認は新しい status 値で行う。

## 実装

1. `GwWorktree` に GitHub PR 状態の説明を追加する。
2. PR がない行にも GitHub 状態アイコンを表示し、状態を tooltip で区別する。
3. `GwSchemaTests` と `GwClientTests` の schema fixture を v2 に更新し、4 種類の status と `sources`/`errors` を検証する。
4. `just test-fast`、`just lint`、`git diff --check` で検証する。

## 完了条件

- v2 の `gw list --json` と `gw clean --json` をデコードできる。
- PR ありの表示・リンクが従来どおり動く。
- PR なし、確認不能、取得失敗を Worktree Status 上で区別できる。
- 未知の status でもクラッシュせず表示できる。
