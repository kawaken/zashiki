# Config.zig に残る非macOSプラットフォーム専用設定の棚卸し

## 背景

GTK apprt の削除（`docs/history/remove-gtk-apprt.md`）と、その後のmacOS専用化
（PR #37）で、Linux/GTK/Wayland/X11 向けのコードはソースツリーから消えた。
しかし `src/config/Config.zig` には**それらのプラットフォームにしか効かない
設定が残っている**。

象徴的なのが `zashiki +show-config --default --docs` の出力先頭:

```console
$ zashiki +show-config --default --docs | head -20
# Set Ghostty's graphical user interface language to a language other than the
# system default language. For example:
#
#     language = de
# ...
# GTK only.
# Available since 1.3.0.
language =
```

**全設定の一覧を見ようとした人が最初に目にするのが、このフォークでは絶対に
効かない設定**という状態になっている。

## 調査結果

`Config.zig` の189個のトップレベル設定のうち、38件がドキュメント中で
GTK / Wayland / X11 / Linux / FreeBSD / KDE / GNOME / Plasma に言及していた
（「named X11 color」のような色名の記述は除外）。

これを「実際にmacOSで効くか」で分類した。判定方法は、`Config.zig` の定義箇所
以外での参照の有無:

- Zig側: `@"設定名"` での参照
- Swift側: 設定名およびそのcamelCase形

### A. 完全に死んでいる（削除対象・13件）

Zig側・Swift側ともに**参照が1件も無い**もの。設定はパースされるが、値を読む
コードがどこにも存在しない。

| 設定 | ドキュメント上の記述 |
|---|---|
| `language` | GTK only |
| `window-subtitle` | This feature is only supported on GTK |
| `window-show-tab-bar` | Currently only supported on Linux (GTK) |
| `window-titlebar-background` | Currently only supported in the GTK app |
| `window-titlebar-foreground` | Currently only supported in the GTK app |
| `quit-after-last-window-closed-delay` | Only implemented on Linux |
| `quick-terminal-keyboard-interactivity` | Only has an effect on Linux Wayland |
| `async-backend` | This is only supported on Linux |
| `app-notifications` | This configuration only applies to GTK |
| `linux-cgroup` | cgroup分離（Linux専用） |
| `linux-cgroup-memory-limit` | 同上 |
| `linux-cgroup-processes-limit` | 同上 |
| `linux-cgroup-hard-fail` | 同上 |

付随して、これらの設定でしか使われていない型（`AsyncBackend`、`LinuxCgroup`
など）も削除できる。`AsyncBackend` は `Config.zig` 外での参照ゼロを確認済み。

### B. macOSで効くが、ドキュメントにLinux固有の記述が混ざる（文言整理・約25件）

設定自体は生きているが、説明文にこのフォークでは無意味な記述が残っている。
例:

- `background-blur` — "On Wayland, Ghostty uses `ext-background-effect-v1`" /
  "On X11, blur can only be enabled when using the KWin compositor as a part
  of KDE Plasma"
- `keybind` — `global:` について "On Linux, you need a desktop environment
  that implements the ... KDE Plasma (since 5.27) and GNOME (since 48)"
- `quit-after-last-window-closed` — "On Linux, this defaults to `true` since..."
- `window-position-x` / `window-save-state` / `undo-timeout` —
  "only supported on macOS" 側の注記（Linuxとの対比が不要になった）
- `bell-features` / `bell-audio-path` / `bell-audio-volume` —
  "Available since: 1.2.0 on GTK, 1.3.0 on macOS" のようなGTK向けバージョン注記
- `window-decoration` — `server` 値の説明が丸ごとLinux/GTK前提。値自体を
  削るかは要検討（`auto` / `client` / `none` はmacOSで意味がある）

これらは**挙動を変えない純粋なドキュメント整理**なので、Aとは別コミットに
分けるべき。量が多いので、一度に全部やるか段階的にやるかは要判断。

### C. 付随して消せるもの

`getGObjectType` — GTK環境でgobject型として登録するための宣言。GTK apprt
削除後は全て `.none => void` に潰れており、8ファイル18箇所に残っている。

```zig
/// Make this a valid gobject if we're in a GTK environment.
pub const getGObjectType = switch (build_config.app_runtime) {
    .none => void,
};
```

対象ファイル: `src/apprt/structs.zig`, `src/apprt/surface.zig`,
`src/apprt/action.zig`, `src/config/Config.zig`, `src/input/Binding.zig`,
`src/terminal/mouse.zig`, `src/font/face.zig`,
`src/datastruct/split_tree.zig`

## 注意点: 設定キーを消すと既存の設定ファイルがエラーになる

未知の設定キーは `src/cli/args.zig` で `error.InvalidField`（診断メッセージは
"unknown field"）になり、起動時の設定エラーウィンドウに表示される。クラッシュ
はしないが、ユーザーがそのキーを書いていると毎回警告が出る。

**確認済み**: A の13件はいずれもユーザーの設定ファイルで使われていない。
確認対象は現在の探索パス（`src/config/file_load.zig`）:

| 種別 | パス |
|---|---|
| XDG（新） | `$XDG_CONFIG_HOME/zashiki/config.ghostty` |
| XDG（旧・後方互換） | `$XDG_CONFIG_HOME/zashiki/config` |
| App Support（新） | `~/Library/Application Support/dev.kawaken.zashiki/config.ghostty` |
| App Support（旧・後方互換） | `~/Library/Application Support/dev.kawaken.zashiki/config` |

## 実施順序

1. **A（13件の削除）** — 挙動不変。付随する型（`AsyncBackend`, `LinuxCgroup`）
   と、`Config.zig` 内のテストも併せて整理する
2. **C（`getGObjectType` の削除）** — 同じく挙動不変。Aと同じPRでよい
3. **B（ドキュメント整理）** — 別PR。挙動を変えないがdiffが大きくなるため

## 検証

- `zig build` / `zig build test` が成功する
- `zashiki +show-config --default --docs` の先頭が `language` でなくなる
- `zashiki +validate-config` が既存の設定ファイルで通る
- 削除した設定を書いた設定ファイルで "unknown field" 診断が出ることを確認
  （＝意図通りエラーとして扱われる）

## 実施結果

A・B・Cを3PRに分けて実施した:

- A + C（設定13件の削除 + `getGObjectType`削除）: [#45](https://github.com/kawaken/zashiki/pull/45)
- B（生きている設定のドキュメント整理29件 + `window-decoration`の`server`値削除）: [#47](https://github.com/kawaken/zashiki/pull/47)

Bの実装中に、スコープ外の新規発見が2件あった。プラン外だったためBのPRには含めず、
別PRで対応した:

1. **`freetype-load-flags`が完全に死んでいた。** このフォークのフォントバックエンドは
   CoreTextのみ（`font.Backend`は`.coretext`しか存在しない）で、`hasFreetype()`が
   常に`false`を返すため、`freetype-load-flags`設定は元からパースされるだけで
   一切効果を持たなかった。設定フィールドとFreeType読み込みフラグの`packed struct`を
   削除し、`font/face.zig`の`FreetypeLoadFlags`型を`void`に固定した。
   `Collection.zig`/`SharedGridSet.zig`側の`freetype_load_flags`フィールド自体は
   （既に常に`void`型で実質ゼロコストなことと、`font.Backend`のような他の
   1択に潰れた抽象化層を維持する既存方針に合わせて）そのまま残した。

2. **`window-theme`の`ghostty`値もmacOSで無効だった。** ドキュメントには
   「Linux buildsのみ対応」と明記されており、Swift側の`NSAppearance`拡張
   （`NSAppearance+Extension.swift`）は`"dark"`/`"light"`/`"auto"`しか処理せず
   `ghostty`は`default: return nil`に落ちていた。enumから値を削除した
   （Swift側には元々`ghostty`ケースは存在しなかった）。

検証: 両設定を書いた設定ファイルで診断が出ることを確認した。

```
freetype-load-flags: unknown field
window-theme: invalid value "ghostty", valid values are: auto, system, light, dark
```
