# Worktree Status 一覧のツールチップ修正

## 関連

- Issue #148: サイドバーのWorktree一覧のアイコンツールチップが表示されない
- 直前の実装: PR #133 / `docs/history/worktree-status-tooltips.md`

## 問題

Worktree Status の一覧行では、SwiftUI の `help` modifier を個々の
`Image`、`Text`、`Link` に付けている。しかし、実アプリのスクロールされた
Worktree 一覧上でホバーしても、期待する macOS の help tag が表示されない。
文言の生成と Codable の状態変換は既存テストで検証済みであり、問題は一覧内の
SwiftUI view から AppKit の tooltip へ伝わる表示経路にあると考えられる。

## 方針

- Worktree 行の表示は維持し、tooltip だけを AppKit の `NSView.toolTip` に
  接続する小さな SwiftUI bridge を追加する。
- 行内の各状態表示が持つ既存の詳細文言を再利用し、branch/HEAD、Git、upstream、
  agent、PR、lock、cleanup の個別 tooltip を維持する。
- Link のクリックやスクロールを妨げないよう、tooltip bridge は表示だけを担当し、
  SwiftUI の本来の hit testing を奪わない構成にする。
- 既存の `.help` はアクセシビリティ向けの補助として残すか、bridge 側の
  `accessibilityHelp` と重複する場合は整理する。

## 実装

1. Worktree Status 専用の AppKit tooltip bridge / View modifier を追加した。
   `NSView.toolTip` を設定した透明な `NSViewRepresentable` を overlay として
   配置し、`hitTest` は `nil` を返して本来の SwiftUI 操作を通過させる。
2. `WorktreeStatusRowView` の branch/HEAD、Git、upstream、agent、PR、lock、
   cleanup の各 tooltip を bridge 経由にした。既存の `.help` はアクセシビリティ
   用に残している。
3. tooltip 文言の既存テストは変更せず、macOS target に新規 bridge が含まれて
   build できることを確認した。
4. 実装判断と検証結果をこの文書へ追記し、`docs/history/` に移動する。

## 検証

- `just test-fast`
- `just lint`
- macOS app build
- 実アプリの Worktree Status 一覧で、各アイコンと branch/PR にホバーして
  tooltip が表示されることを確認する（既存のローカルビルドを対象にし、別の
  アプリを終了しない）。

### 実施結果

- `just test-fast`: 成功
- `just lint`: 成功（0 violations / 0 serious）
- `just test-fast` に含まれる Debug macOS app build: 成功
- ローカル build の bundle path は `macos/build/Debug/Zashiki.app`。
- 実アプリのホバー確認: Mac がロック中で自動解除できなかったため未実施。
  GUI の起動・終了は行っておらず、別ビルドを終了する操作もしていない。

## 完了条件

- Issue #148 の報告症状が実アプリで解消している（人手確認待ち）。
- 既存の Worktree Status 表示・PR リンク・スクロール操作を壊していない。
- Plan に実装判断と CI/実機検証結果を記録し、実装 PR で `docs/history/` に移動する。
