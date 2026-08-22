# manページ・HTMLドキュメント生成の削除

> 旧ファイル名: `plan/manpage-to-help-command.md`
> 当初は「manページの代わりに `+list-config` を新設して移行する」という
> プランだったが、調査の結果**移行先は既に存在しており新設は不要**だと
> 分かったため、内容を全面的に書き直した（詳細は「当初プランからの訂正」）。

## 結論

`src/build/mdgen`（manページ生成）と `src/build/webgen`（ghostty.org用
JSON生成）を削除する。**移行作業は不要**で、`+help` の文言を1箇所直すだけ。

## 現状: この機能は動いていない

`emit_docs` のデフォルトは「PATHに `pandoc` があれば true、無ければ false」
（`src/build/Config.zig:327-345`）。開発機に pandoc は入っていないため、
manページは**一度も生成されていない**。

代わりに `GhosttyDocs.installDummy`（`src/build/GhosttyDocs.zig:111`）が
プレースホルダを置いている。今 `Zashiki.app` に実際に入っているのはこれだけ:

```console
$ find zig-out/Zashiki.app/Contents/Resources/man -type f
zig-out/Zashiki.app/Contents/Resources/man/.placeholder

$ cat zig-out/Zashiki.app/Contents/Resources/man/.placeholder
emit-docs not true so no man pages
```

このプレースホルダは、Xcodeプロジェクトが `zig-out/share/man` の存在を前提に
しているため「ディレクトリを空で存在させる」ためだけのハックである。

## pandocを入れると、むしろ壊れる

仮に pandoc をインストールすると man ページの生成が始まるが、その中身
（`src/build/mdgen/ghostty_5_header.md` ほか）は上流Ghostty向けのままで、
**Zashikiのユーザーに誤った情報を提供する**:

| man(5)の記述 | Zashikiでの実際 |
|---|---|
| `% GHOSTTY(5)` / `**ghostty** - Ghostty terminal emulator configuration file` | コマンド名は `zashiki` |
| 設定ファイルは `$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty` | `dev.kawaken.zashiki` 配下 |
| ログは `sudo log stream --predicate 'subsystem=="com.mitchellh.ghostty"'` | `subsystem=="dev.kawaken.zashiki"` |
| `journalctl --user --unit app-com.mitchellh.ghostty.service` でログが見られる | Linux非対応 |
| `$LOCALAPPDATA` に設定ファイルを探す | Windows非対応 |
| BUGS: `https://github.com/ghostty-org/ghostty/issues` | `kawaken/zashiki` |
| AUTHOR: Mitchell Hashimoto | — |

252行のヘッダ/フッタ Markdown を Zashiki 向けに書き直して維持し続けるか、
生成ごと消すかの二択であり、後者を選ぶ。

## 移行先は既に存在する（当初プランからの訂正）

当初プランでは「manページ(5)だけが全設定オプションの一覧を提供している。
消すなら `+list-config` を新設して埋める必要がある」と書いていた。**これは
誤り**だった。

`+show-config --default --docs` が既に全設定オプションをドキュメント付きで
出力する（実測3,829行）:

```console
$ zashiki +show-config --default --docs
# The font families to use.
#
# You can generate the list of valid values using the CLI:
#
#     ghostty +list-fonts
# ...
font-family =
```

皮肉なことに、削除対象の `ghostty_5_header.md` 自身がこのコマンドを案内して
いる。したがって **`+list-config` の新設は不要**。

man(1) が提供していた情報についても既存コマンドで代替できる:

| man の情報 | 既存コマンド |
|---|---|
| 全設定オプション＋説明 | `zashiki +show-config --default --docs` |
| 設定オプション1つの説明 | `zashiki +explain-config --option=font-size` |
| キーバインドアクションの説明 | `zashiki +explain-config --keybind=copy_to_clipboard` |
| 現在の設定値 | `zashiki +show-config` |
| キーバインド一覧 | `zashiki +list-keybinds` |
| アクション一覧 | `zashiki +list-actions` |
| テーマ / フォント / 色一覧 | `zashiki +list-themes` / `+list-fonts` / `+list-colors` |

man(5) も CLI も同じ `help_strings`（`Config.zig` のドキュメントコメントから
ビルド時に生成）を情報源にしているため、内容は同一である。

## 作業内容

### 1. `+help` の文言を直す（唯一のコード変更）

`src/cli/help.zig:48-50` に上流由来の古い文言が残っている:

```
To see a list of all available configuration options, please see
the `src/config/Config.zig` file. A future update will allow seeing
the list of configuration options from the command line.
```

「将来CLIから見られるようにする」と書いてあるが、`+show-config --default
--docs` として既に実現済み。ソースファイルを見ろという案内は不適切なので
差し替える。

### 2. 削除

| 対象 | 備考 |
|---|---|
| `src/build/mdgen/` | `mdgen.zig` と header/footer の `.md` 4本（252行）、`main_ghostty_1.zig` / `main_ghostty_5.zig` |
| `src/build/GhosttyDocs.zig` | pandocを叩くステップと `installDummy` ハック |
| `src/build/webgen/` と `src/build/GhosttyWebdata.zig` | ghostty.org のサイト用JSON生成。Zashikiには対応するサイトが無い |
| `src/build/Config.zig` の `emit_docs` / `emit_webdata` | pandoc探索ロジックごと |
| `src/build/Config.zig` の `ExeEntrypoint` の `mdgen_*` / `webgen_*` | 6バリアント。`src/main.zig` の分岐も併せて |
| `build.zig` のdocs/webdata関連 | `installDummy` の分岐を含む |
| `src/build/ZashikiXcodebuild.zig` の `docs` 依存 | |
| `macos/Zashiki.xcodeproj` の `share/man` 参照 | `project.pbxproj:69` |

`ExeEntrypoint` は削除後 `ghostty` と `helpgen` の2つになる。

### 3. 実施順序

`+help` の文言を先に直してから削除する。逆順でも壊れないが、
「案内先が無い状態」を一瞬でも作らないため。

## 検証

- `zashiki +help` の出力が `+show-config --default --docs` を案内している
- `zashiki +show-config --default --docs` が従来通り全オプションを出す
- `zashiki +explain-config --option=font-size` が従来通り動く
- `zig build` / `zig build test` が成功する
- `Zashiki.app/Contents/Resources/man` が消えてもXcodeビルドが通る
  （`installDummy` ごと消えるため、pbxprojの参照削除が前提）
- pandoc の有無でビルド結果が変わらなくなる

## 補足: 別途対応が必要なもの

調査中に気づいたが、このプランの対象外:

- `+show-config --default --docs` の出力先頭に出る `language` 設定は
  「GTK only」と明記されており、GTK apprt と i18n を削除した現在は
  効果を持たない。他にも GTK/Linux 専用の設定が `Config.zig` に残っている
  可能性がある
