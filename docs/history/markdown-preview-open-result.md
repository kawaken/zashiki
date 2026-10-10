# Markdownプレビューを開いた結果を呼び出し元へ返す

## Issue

- #259

## 調査結果

- `zashiki +markdown-preview`は`open`コマンドでURLをLaunch Servicesへ渡し、`open`の終了コードをそのままCLIの終了コードとして返している。
- `open`の成功はアプリがURLを受け取ったことを示すだけで、Zashikiがパスを受け入れてプレビューペインを表示したことまでは呼び出し元に伝わらない。
- AppDelegateのURLハンドラは不正なパスや見つからないファイルをログに出すだけで、CLIから結果を取得できない。

## 方針

- CLIがリクエストごとのランダムな一時応答ファイルを`/tmp`に用意し、そのパスをURLに付けてアプリへ渡す。
- アプリは要求を検証し、プレビュー状態を更新した後に結果を応答ファイルへ書く。応答パスは`/tmp`直下の専用prefixとURL-safeなランダム名に限定する。
- CLIは最大10秒応答を待ち、成功時はstdoutに開いたパスを出し、アプリ側の拒否・応答タイムアウト時はstderrと非0終了コードで呼び出し元に知らせる。
- 応答パラメータのない既存`zashiki://markdown-preview/open` URLは従来どおり利用できる。

## 確認

- URL組み立てと応答解析のZigテストを追加する。
- 応答先パス検証のSwiftテストを追加する。
- `just lint`と`just test-fast`を実行する。

## リリース

- v0.7.0以降のユーザー向け変更を確認してCHANGELOGへ反映する。
- このIssueは新しいCLI機能のため、feature扱いで次のMINORリリースに含める。

## 実装結果

- CLIからのURLに応答ファイルを付け、アプリがプレビューペインを表示した後に`opened`を返すようにした。
- 不正なパス、ファイル不在、プレビュー未表示はエラー応答を返す。応答が10秒以内に届かない場合CLIは失敗し、成功時は開いたファイルパスをstdoutに出す。
- 応答ファイルのパス検証、URL組み立ての回帰テストを追加した。
- v0.7.0以降の変更をまとめてv0.8.0のCHANGELOGに記録した。

## 検証結果

- `just lint`: 成功（違反なし）。
- `just test-filter 'build markdown preview URL'`: 成功。
- `xcodebuild test -only-testing:ZashikiTests/MarkdownPreviewModelTests`: 成功。追加した応答先検証テストを含む。
- `just test-fast`: Xcodeアプリビルドは成功したが、Zig側コマンドがビルド後に終了しなかったため停止した。CIでの確認を継続する。
- `git diff --check`: 成功。
