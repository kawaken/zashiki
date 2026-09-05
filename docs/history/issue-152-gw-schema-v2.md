# Issue #152: `gw list --json` schema v2 対応

## 目的

`kawaken/gw` の JSON schema v2 で追加された GitHub PR 検索状態を、Zashiki の Worktree Status に正しく反映する。PR がない状態、ブランチ等の理由で確認できない状態、GitHub 連携の取得失敗を `github.pr == null` だけで同一視しない。

## 実装内容

- `schema_version: 2`、トップレベルの `sources.github`、`errors` を Codable fixture で検証。
- `worktrees[].github.status` の `found`、`not_found`、`unknown`、`unavailable` を状態アイコンと tooltip に変換。
- `found` で PR がある場合の既存の PR 番号リンクと state 色分けを維持。
- 未知の status は文字列のままデコードし、汎用アイコンと tooltip にフォールバック。
- v1 由来の `available` を含む既存データも文字列としてデコード可能な形を維持。

## 検証結果

- `swiftlint lint --strict`: 成功（違反 0）。
- `git diff --check`: 成功。
- `just test-fast`: Xcode の Swift package dependency 解決が sandbox の `sandbox_apply: Operation not permitted` で停止。sandbox 外で再実行しても全体ビルドが無出力で進まなかったため中断し、直接の `xcodebuild` でも同じ package 解決エラーを確認した。

実機での Worktree Status の各アイコン表示と tooltip 操作は未確認。
