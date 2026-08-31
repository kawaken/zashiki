# `entry-point`を基準にしたworktree開始手順の整理

## 目的

作業開始時の基準ブランチを`entry-point`に統一し、`main`の更新漏れや古い
ベースからのworktree作成を防ぐ。同時に、Git worktreeの作業ファイルと共有
Gitメタデータの権限境界を区別し、サンドボックス環境でコミットできない問題を
運用ルールだけで解決できるかどうかを明確にする。

## 調査結果

- `entry-point`は作業用ブランチではなく、最新の`main`から作業用ブランチを
  作るためのローカルな基準ブランチとして扱うのが適切。
- `git fetch`やコミットは、作業ファイルだけでなく共有リポジトリのGit
  メタデータ（`FETCH_HEAD`、index、refsなど）への書き込みを必要とする。
- linked worktreeでは、作業ディレクトリが書き込み可能でも共有Gitメタデータが
  サンドボックスの許可範囲外になる場合がある。この場合、`entry-point`を経由
  しても権限エラーは解消しない。
- Codexなどがすでに作成した専用worktreeを割り当てている場合、その中からさら
  にworktreeを作ると、権限境界とworktreeの入れ子が複雑になる。割り当て済み
  worktreeではそのまま作業する方が安全。

## 提案する開始手順

書き込み権限のあるbootstrap用checkoutで、次の順序を実行する。

1. 作業中の変更がないことを確認する。
2. `git fetch origin main`でリモートの`main`を取得する。
3. ローカルの`main`を`git pull --ff-only origin main`で更新する。
4. `git switch entry-point`し、`git rebase main`で`main`に追従させる。
5. `entry-point`から、要件に応じた作業ブランチと専用worktreeを作る。
6. 作業・検証・コミットは作業用worktree内だけで行う。

`entry-point`に固有のコミットが不要で、単に`main`と同一に保ちたい場合は、
rebaseの前に差分と未コミット変更を確認する。変更を破棄する操作は自動で行わず、
必要なら人間の確認を求める。

## 既存ルールとの統合

- `1 task = 1 branch = 1 worktree`は維持する。
- `entry-point`は複数タスクで共有する作業ブランチにせず、bootstrap用checkout
  でだけ一時的に使う。
- `main`、`entry-point`、他タスクのworktreeを、作業用worktreeから操作しない。
- Codexなどから専用worktreeを割り当てられた場合は、新しいworktreeを作らず、
  割り当てられた場所を使う。その場合の基準は最新の`origin/main`とし、
  `entry-point`の更新操作はbootstrap用checkout側で済ませる。
- `git fetch`、index更新、commit、pushのいずれかが権限エラーになる場合、
  ルールで回避せず、共有Gitメタデータまで書き込み可能なcheckoutまたは、
  サンドボックス内に完結した通常cloneを環境側で用意する。

## AGENTS.mdへの反映

既存のGit Worktree節を、上記のbootstrap手順と割り当て済みworktreeの例外が
矛盾しないように書き換える。サンドボックスの権限をルールで変更できるとは
記載せず、環境側の許可が必要な条件として明記する。

## 検証

- `git diff --check`
- `AGENTS.md`のGit Worktree節を読み返し、`main`の直接操作禁止、専用worktree、
  `entry-point`同期、サンドボックス権限の扱いが矛盾しないことを確認する。

## 実装時の知見（2026-08-31）

- linked worktreeからの`git fetch`は、作業ディレクトリが書き込み可能でも共有
  Gitメタデータ側の`FETCH_HEAD`更新で権限エラーになった。権限を付与するとfetch
  自体は成功したため、`entry-point`運用ではなく環境の書き込み境界が原因だと確認
  できた。
- `git commit`は実行できた一方、push後のremote-tracking refとbranch設定の更新、
  `git mv`によるindex lockの作成でも同じ権限エラーが発生した。Git操作ごとに必要な
  メタデータ書き込みが異なるため、個別の回避策ではなくcheckout全体の権限を確認
  する必要がある。
- `entry-point`をbootstrap用checkoutで同期し、Codexなどから割り当てられたtask
  worktreeでは入れ子のworktreeを作らない方針を`AGENTS.md`へ反映した。
- ドキュメント変更のため、`git diff --check origin/main HEAD`を実行した。ビルドと
  テストは実施していない。
