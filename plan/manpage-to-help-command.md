# manページ生成の廃止と、CLIヘルプへの集約

## 背景

Zashikiは `zashiki(1)` / `zashiki(5)` のmanページを生成して `Zashiki.app` に同梱している。
この仕組みには以下の問題がある:

- **外部ツール `pandoc` に依存する。** `src/build/mdgen` がMarkdownを生成し、pandocが
  man形式とHTMLに変換する
- **ビルド結果が環境依存で非決定的になる。** `emit_docs` のデフォルトは
  「PATHに `pandoc` があれば true、無ければ false」（`src/build/Config.zig:381-397`）。
  つまり開発者のマシンにpandocが入っているかどうかでアプリバンドルの中身が変わる
- **既に破綻の兆候がある。** Xcodeプロジェクトが `zig-out/share/man` の存在を前提に
  しているため、docsを出さない構成では空のプレースホルダファイルを作って誤魔化す
  コードが入っている（`build.zig:93`付近 / `GhosttyDocs.zig:116`）
- HTML出力（`share/ghostty/doc/*.html`）は ghostty.org のサイト用で、Zashikiには
  対応するサイトが無く完全に無駄

一方で **manページの中身はCLIから既にほぼ全部引ける**:

| 情報 | 既存コマンド |
|---|---|
| 設定オプション1つの説明 | `zashiki +explain-config --option=font-size` |
| キーバインドアクションの説明 | `zashiki +explain-config --keybind=copy_to_clipboard` |
| 現在の設定値 | `zashiki +show-config` |
| キーバインド一覧 | `zashiki +list-keybinds` |
| アクション一覧 | `zashiki +list-actions` |
| テーマ / フォント / 色一覧 | `zashiki +list-themes` / `+list-fonts` / `+list-colors` |
| 設定の検証 | `zashiki +validate-config` |

manページ（`zashiki(5)`）もCLIヘルプも、**同じ `help_strings`（`Config.zig` の
ドキュメントコメントからビルド時に生成される）を参照している**ので、情報源は同一。
manを消してもドキュメントは失われない。

## 唯一の欠落: 設定オプションの全件一覧

`+help` の出力に、現状こう書かれている（`src/cli/help.zig:48-51`）:

> To see a list of all available configuration options, please see
> the `src/config/Config.zig` file. A future update will allow seeing
> the list of configuration options from the command line.

**上流自身が「CLIから設定一覧を見られるようにするのは将来の課題」と認めている。**
`zashiki(5)` manページはまさにこの全件一覧を提供しているので、manを消すならここを
埋める必要がある。

## 方針

1. **`+list-config` アクションを新設する。** 全設定オプションを
   `help_strings.Config` から列挙し、既存の `src/cli/Pager.zig` に流す。
   `+explain-config` と同じ描画ロジックを再利用できるはず
   - `--option-only` のようなフラグでオプション名だけを列挙できると、
     シェル補完やgrepと組み合わせやすい（補完自体は別途削除対象なので優先度低）
2. **`+help` の「Config.zigを見てくれ」という文言を `+list-config` の案内に差し替える**
3. **mdgen / pandoc / manページ / HTML出力を削除する**

## 削除対象

| 対象 | 備考 |
|---|---|
| `src/build/mdgen/` | header/footer の `.md` 4本と生成ロジック |
| `src/build/GhosttyDocs.zig` | pandocを叩くステップ、プレースホルダ生成ハックを含む |
| `src/build/GhosttyWebdata.zig` / `src/build/webgen/` | ghostty.orgのサイト用JSON生成。移行先不要、単純削除 |
| `src/build/Config.zig` の `emit_docs` オプション | pandoc探索ロジックごと |
| `build.zig` のdocs関連（88-97行付近） | プレースホルダ生成の分岐も消える |
| `macos/Ghostty.xcodeproj` の `share/man` 参照 | `project.pbxproj:83` |

## 実施順序

`+list-config` を先に作って動作確認してから、mdgen側を消す。逆順にすると
一時的に設定一覧を引く手段が無くなる。

## 検証

- `zashiki +list-config` で全オプションがページャで読める
- `zashiki +explain-config --option=font-size` が従来通り動く
- `pandoc` がPATHに無い環境でも `zig build` が通り、アプリバンドルが同じ中身になる
- `Zashiki.app/Contents/Resources/share/man` が消えてもXcodeビルドが通る
