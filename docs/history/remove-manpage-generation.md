# manページ・HTMLドキュメント生成の削除

- **元プラン**: `plan/manpage-to-help-command.md` →
  `plan/remove-manpage-generation.md`（削除済み、このドキュメントに統合）

## 目的

`src/build/mdgen`（manページ生成）と `src/build/webgen`（ghostty.org用の
JSON生成）を削除し、CLIヘルプに一本化した。

## Planとの差分

最初に書いたプランは前提が2つとも誤っており、調査の結果ほぼ全面的に書き
直すことになった。実装前に検証しておいて良かった類の間違いなので記録する。

### 誤り1: 「移行先を新設する必要がある」

当初プランはこう書いていた:

> manページ(5)だけが全設定オプションの一覧を提供している。消すなら
> `+list-config` を新設して埋める必要がある。

**誤り。** `+show-config --default --docs` が既に全設定オプションを
ドキュメント付きで出力していた（実測3,829行）。

皮肉なことに、削除対象である `src/build/mdgen/ghostty_5_header.md` の中身
自身がこのコマンドを案内していた:

> You can view all available configuration options and their documentation by
> executing the command `ghostty +show-config --default --docs`.

つまり上流Ghostty側で既に代替コマンドが実装済みであり、新規実装は不要
だった。結果、コード変更は `src/cli/help.zig` の文言1箇所のみになった。

`+help` には上流由来の古い文言が残っていた:

> To see a list of all available configuration options, please see
> the `src/config/Config.zig` file. A future update will allow seeing
> the list of configuration options from the command line.

「CLIから見られるようにするのは将来の課題」と書かれているが、その将来は
既に来ていて `+show-config --default --docs` として実現している。上流が
実装した際に文言を直し忘れたものと思われる。これを実際のコマンドの案内に
差し替えた。

### 誤り2: 「manページが同梱されている」

当初プランは「manページを `Zashiki.app` に同梱している」前提で書いていた。

**誤り。** `emit_docs` のデフォルトは「PATHに `pandoc` があれば true」で、
開発機に pandoc は入っていなかった。manページは一度も生成されておらず、
実際にアプリに入っていたのは `GhosttyDocs.installDummy` が置く
プレースホルダだけだった:

```console
$ cat zig-out/Zashiki.app/Contents/Resources/man/.placeholder
emit-docs not true so no man pages
```

このプレースホルダは、Xcodeプロジェクトが `zig-out/share/man` の存在を
前提にしているため「ディレクトリを空で存在させる」ためだけのハックである。

## 削除を選んだ決め手

調査中に分かったことだが、仮に pandoc をインストールすると man ページの
生成が始まり、その中身は上流Ghostty向けのままなので **Zashikiユーザーに
誤った情報を提供する**:

| man(5)の記述                                                 | Zashikiでの実際            |
| ------------------------------------------------------------ | -------------------------- |
| `% GHOSTTY(5)` / `**ghostty**`                               | コマンド名は `zashiki`     |
| 設定は `.../com.mitchellh.ghostty/config.ghostty`            | `dev.kawaken.zashiki` 配下 |
| ログは `subsystem=="com.mitchellh.ghostty"`                  | `dev.kawaken.zashiki`      |
| `journalctl --user --unit app-com.mitchellh.ghostty.service` | Linux非対応                |
| `$LOCALAPPDATA` に設定を探す                                 | Windows非対応              |
| BUGS: `ghostty-org/ghostty/issues`                           | `kawaken/zashiki`          |
| AUTHOR: Mitchell Hashimoto                                   | —                          |

252行のヘッダ/フッタMarkdownをZashiki向けに書き直して維持し続けるか、
生成ごと消すかの二択であり、後者を選んだ。

## 削除したもの

- `src/build/mdgen/`（`mdgen.zig`、header/footer の `.md` 4本、
  `main_ghostty_1.zig` / `main_ghostty_5.zig`）
- `src/build/GhosttyDocs.zig`（pandocを叩くステップと `installDummy` ハック）
- `src/build/webgen/` と `src/build/GhosttyWebdata.zig`
- `-Demit-docs` / `-Demit-webdata` オプション（pandoc探索ロジックごと）
- `ExeEntrypoint` の `mdgen_*` / `webgen_*` 6バリアント
  （残るのは `ghostty` と `helpgen` の2つ）
- `macos/Zashiki.xcodeproj` の `share/man` 参照

これで pandoc の有無でビルド結果が変わる非決定性も解消した。

## 残タスク

`+show-config --default --docs` の出力先頭に出る `language` 設定は
「GTK only」と明記されており、GTK apprt と i18n を削除した現在は効果を
持たない。他にも GTK/Linux 専用の設定が `Config.zig` に残っている可能性が
あり、別途棚卸しが必要。
