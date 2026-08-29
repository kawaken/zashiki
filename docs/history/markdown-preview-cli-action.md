# MarkdownプレビューCLIアクション

## 目的

Zashiki内で動作するコーディングエージェントが、Markdownファイルを発火元の
ターミナルウィンドウへ確実に開けるCLI入口を提供する。

```sh
zashiki +markdown-preview README.md
```

## 前提

- macOSアプリ側には`zashiki://markdown-preview/open`のURLハンドラが既にある
- URLの`surface`クエリで発火元Surfaceを指定できる
- Zashikiが起動したシェルには、実行ファイルのディレクトリを`PATH`へ追加し、
  `ZASHIKI_BIN_DIR`にも設定する既存処理がある
- `scripts/zashiki-md-preview`は削除済みであり、CLIアクションがその役割を引き継ぐ
- 既存のCLIは、`+`で始まる1段のアクションとアクション固有ヘルプを使う

## 実装方針

### CLIアクション

- `Action` enumに`markdown-preview`を追加する
- `src/cli/markdown_preview.zig`を追加し、既存のアクション登録・dispatch・options
  の仕組みに接続する
- 引数はMarkdownファイルのパスを1つだけ受け取る
- 相対パスはCLIのカレントディレクトリから解決する
- ファイルが存在しない、ディレクトリである、引数がない、複数ある場合は、stderrへ
  明確なエラーを出して失敗する
- 拡張子だけで判断せず、既存URLハンドラと同じく通常ファイルとして扱えるかを検証する
- `+markdown-preview --help`で、使用例と起動方式を説明する

### Zashikiへの中継

- パスをRFC 3986のクエリ値として安全にエンコードする
- `ZASHIKI_SURFACE_ID`が有効な場合は、URLの`surface`へそのまま渡す
- `zashiki://markdown-preview/open?path=...&surface=...`を生成する
- `/bin/sh`経由の文字列実行はせず、`/usr/bin/open`を引数配列で起動する
- 起動中のZashikiと別のビルドを誤って選ばないよう、現在の実行ファイルから対象
  app bundleを指定できるかを確認する。難しい場合は、登録済みURLハンドラへの送信を
  フォールバックとする
- CLIはプレビュー表示完了を待たず、URLの受け渡し結果を終了コードで返す

### PATHの確認

追加のPATH実装は原則不要。`src/termio/Exec.zig`の既存処理が、実行中のZashikiの
実行ファイルディレクトリ（Releaseでは`Zashiki.app/Contents/MacOS`）をシェルの
`PATH`へ追加しているため、そこにある`zashiki`を呼び出せる。

リネーム後の回帰として、次を確認する。

```sh
command -v zashiki
echo "$ZASHIKI_BIN_DIR"
zashiki +help
```

PATHがシェル設定で上書きされても、`$ZASHIKI_BIN_DIR/zashiki`で呼び出せることを
確認する。

## 実装ステップ

1. CLIアクションの登録と個別ヘルプを追加する
2. パス検証・絶対パス化・URLエンコードを実装する
3. `open`によるURL中継と`surface`引き継ぎを実装する
4. CLI引数、エラー、空白・日本語を含むパスのテストを追加する
5. Zashiki内の新しいシェルでPATHと`ZASHIKI_BIN_DIR`を確認する
6. 起動中のZashiki、未起動のZashiki、複数のZashikiビルドがある場合を実機確認する

## 完了条件

- `zashiki +markdown-preview <file>`でプレビューが開く
- Zashiki内のエージェントから実行した場合、発火元ウィンドウに開く
- 相対パス、空白・日本語を含むパスを扱える
- 不正な引数や存在しないファイルが安全に失敗する
- `+help`と`+markdown-preview --help`から使い方を発見できる
- 既存のURL起動、ショートカット、PATH、通常のCLIアクションに回帰がない

## 対象外

- ZashikiとAIエージェント間の双方向IPC
- Markdownプレビューの表示・ライブ更新そのものの変更
- Zashiki外の一般シェルへ`zashiki`をインストールする仕組み
