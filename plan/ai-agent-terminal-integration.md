# AIエージェント↔Zashiki連携の今後の検討

## 位置づけ

このプランは、AIエージェントからZashikiを操作するための将来課題を扱う。
MarkdownプレビューのURL起動、`surface`による発火元Surfaceの特定、その他の
既に実装済みの基盤と調査結果は、`docs/history/ai-agent-terminal-integration.md`
に記録した。

コーディングエージェントが利用するCLIアクションの追加は、個別の実装計画
`plan/markdown-preview-cli-action.md`で扱う。

## 未解決の課題

### 双方向IPC

ZashikiからAIエージェントへ応答を返す用途（例: Yes/No確認）について、PTYや
OSCを使わないローカルIPCを検討する。

- Unix domain socket、またはloopback HTTPの適合性を比較する
- CLIヘルパーと起動中のZashikiの間で要求・応答をやり取りできる設計にする
- `ZASHIKI_SURFACE_ID`を含む要求をどのように認証・検証するか決める
- 他ユーザー・他アプリからの不正接続を防ぐセキュリティ境界を定義する

### Claude Code hookとの連携

Claude Codeの`PreToolUse`、`PostToolUse`、`Notification`などに、Bashツールとは
異なるサニタイズされない出力経路があるかを確認する。存在する場合は、CLIや
IPCとの責務分担を決める。

## 完了条件

- 双方向IPCを採用、部分採用、または見送る判断ができている
- 採用する場合の認証・権限・ライフサイクルを定義できている
- エージェント固有のhookとZashiki共通の連携基盤の境界が明確になっている
- 実装に進む場合は、個別機能のプランへ分解できている
