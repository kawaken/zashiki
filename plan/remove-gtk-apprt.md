# GTK apprtの削除プラン

## 実施状況

**実施済み。** 本プランに従い、`src/apprt/gtk/`および`apprt.Runtime.gtk`への
全参照を削除した。想定していた14ファイル（+`src/cli/new_window.zig`はコメント
のみで実害なし）に加えて、プラン作成時には洗い出せていなかった以下も
併せて対応が必要だった:

- `src/build/SharedDeps.zig`の`addGtkNg`/`gtkNgDistResources`（GObject/
  Wayland/gtk4-layer-shellのリンク・gresource/blueprintビルドロジック、
  約300行）
- `src/build/Config.zig`の`-Dgtk-x11`/`-Dgtk-wayland`オプションと
  `src/build/gtk.zig`ヘルパー
- `src/build/GhosttyDist.zig`の`gtkNgDistResources`呼び出し（`zig build dist`
  用のGTKリソース同梱）
- `src/build/GhosttyI18n.zig` — `zig build`のたびに`config.i18n`が真なら
  即座に`src/apprt/gtk`を`openDir`で開こうとしていたため、削除すると
  **全ターゲットで`zig build`が即座に失敗する**ことが判明。翻訳文字列の
  GTK抽出ロジック（blueprintファイル・GTK配下の`.zig`ファイル走査）を削除。
- `build.zig.zon`の`gobject`/`zig_wayland`/`wayland`/`wayland_protocols`/
  `plasma_wayland_protocols`/`gtk4_layer_shell`依存と、`pkg/gtk4-layer-shell`
  （ベンダリングされたラッパーパッケージ）を削除。

`gtk-single-instance`・`gtk-titlebar-style`・`class`・`show_gtk_inspector`
などのGTK名の付いた**設定/キーバインドAPI自体**は意図的に残した
（クロスプラットフォームな設定ファイル互換性のためのno-opとして）。

この環境には`zig`コンパイラが無いためローカルでのビルド検証はできておらず、
最終確認はCIに委ねている。

## 追記: 設定/キーバインド/CLI APIのGTK専用サーフェスも削除

上記の実装完了後、「クロスプラットフォーム互換性のためのno-opとして残した」
GTK名の設定・キーバインドAPIについても、本フォークが個人用・macOS専用で
クロスプラットフォームを目指すものではないという方針のもと、追加で削除した:

- `class`/`x11-instance-name`/`gtk-*`（`gtk-single-instance`、
  `gtk-titlebar`、`gtk-tabs-location`、`gtk-titlebar-hide-when-maximized`、
  `gtk-toolbar-style`、`gtk-titlebar-style`、`gtk-wide-tabs`、
  `gtk-horizontal-tab-scroll`、`gtk-custom-css`、`gtk-opengl-debug`、
  `gtk-quick-terminal-layer`、`gtk-quick-terminal-namespace`）の
  設定フィールドと、対応する型（`GtkSingleInstance`等）・compat
  リネームエントリ・関連テストを`Config.zig`から削除
- キーバインドアクション`show_gtk_inspector`を`apprt/action.zig`・
  `input/Binding.zig`・`App.zig`・`input/command.zig`・
  `macos/Sources/Ghostty/Ghostty.Command.swift`・`include/ghostty.h`から削除
- `+new-window`/`+toggle-quick-terminal`CLIサブコマンド
  （GTKのD-Bus IPCでしか実装されておらず、macOS(embedded)/`none`
  ランタイムでは常にfalseを返すだけで、このフォークでは常に失敗していた）
  を`src/cli/`、`apprt/ipc.zig`一式、`include/ghostty.h`の
  `ghostty_ipc_*`型ごと削除

## 目的

`src/apprt/gtk/`（Linux/FreeBSD向けGTKアプリランタイム、約1.1MB）を含む、
GTK関連コードをソースツリーから削除する。個人用macOSフォークにLinux対応は
不要という方針に基づく。

## 現状分析

### GTKコードは既に「無害」

`src/apprt/runtime.zig`を見ると、`apprt.Runtime`enumは`none`と`gtk`の
2値しかない。macOS向けのデフォルトは`none`（アプリバイナリを作らず、
Xcodeがlibghosttyにリンクする方式）で、`gtk`はLinux/FreeBSDでのデフォルトに
すぎない:

```zig
pub fn default(target: std.Target) Runtime {
    return switch (target.os.tag) {
        .linux, .freebsd => .gtk,
        else => .none,
    };
}
```

さらに、GTK固有の分岐の多くは`comptime`で確定する`build_config.app_runtime`
に対するswitchの中にあり、macOSビルド(`app_runtime == .none`)では
そもそも解析されない（Zigはcomptime既知のswitch operandで、選ばれない
分岐を意味解析しない）。

**つまり現状、GTKコードはmacOSビルドに一切コストを与えていない**
（ディスク容量以外）。`-Dapp-runtime=gtk`を明示的に指定しない限り
到達しない。

### 削除の難しさ

`src/apprt/gtk/`をただ`git rm`するだけでは壊れる。`src/apprt.zig`が
`pub const gtk = @import("apprt/gtk.zig");`を無条件に持っていて、
ファイルが無いと`@import`解決自体が失敗する。

さらに、`apprt.Runtime`enumから`gtk`を消すには、enumの`.gtk`という
フィールドを参照している**全箇所**を同時に消す必要がある。switch文の
enum網羅性チェックはcomptime pruningとは無関係に常に行われるため、
1箇所でも消し忘れると全ターゲット(macOSも含む)でビルドが壊れる。

現時点で`src/apprt/gtk/`の外から`.gtk`を参照している箇所は14ファイル:

| ファイル                                  | 内容                                                     |
| ----------------------------------------- | -------------------------------------------------------- |
| `src/apprt.zig:45`                        | `runtime`の解決switch                                    |
| `src/apprt/runtime.zig:18`                | `Runtime.default()`                                      |
| `src/apprt/surface.zig:123`               | GObject型定義(`gobject.ext.defineBoxed`)                 |
| `src/apprt/structs.zig:46,52,86`          | GObject型定義(`gobject.ext.defineEnum/defineBoxed`)      |
| `src/apprt/action.zig:682`                | 同上                                                     |
| `src/config/Config.zig:4713,9098,9813`    | 同上 + GTKドキュメントへの外部リンク(コメント、実害なし) |
| `src/renderer/OpenGL.zig:169,204,226,241` | GTK向けGLコンテキスト処理                                |
| `src/terminal/mouse.zig:85`               | GObject型定義                                            |
| `src/font/face.zig:62`                    | 同上                                                     |
| `src/input/Binding.zig:977`               | 同上                                                     |
| `src/datastruct/split_tree.zig:1316`      | 同上                                                     |
| `src/cli/version.zig:49`                  | `+version`出力にGTKバージョン情報を含めるかの分岐        |
| `src/build/SharedDeps.zig:692`            | ビルド時のGTK依存リンク                                  |

`src/config/Config.zig`の2箇所(1546, 3717行)はGTKドキュメントへの
コメント内リンクなので実質ノイズ、消さなくても実害はない。

## 費用対効果

- **メリット**: ディスク容量 約1.1MB削減、ソースツリーがシンプルになる
- **コスト**:
  - 14ファイルの書き換え（`gobject`パッケージ依存の`@import("gobject")`
    呼び出しをどう扱うか要検討。GObject連携自体を消すのか、単に
    switch文を`none`単独の非switch(if文等)に置き換えるだけにするのか）
  - ローカルでmacOS向け`zig build`を検証する手段がこの環境には無いため、
    CIに何度か投げて赤くなったら直す、という進め方になる
  - `build.zig` / `src/build/Config.zig`側のGTK関連ビルドオプション
    (`-Dgtk-x11`等)や`SharedDeps.zig`のGTKリンクロジックも合わせて
    整理が必要

現状GTKコードはビルドに実害を与えていない（容量以外）ため、急ぐ理由は
特にない。

## 進め方（実施する場合）

1. `apprt.Runtime`から`.gtk`を消し、`none`単独のenumにする
   （あるいはenum自体を廃止して`app_runtime`を常に`none`扱いにする、
   というより踏み込んだ簡略化も検討の余地あり）
2. 上記14ファイルの`.gtk`分岐を、コンパイルが通る形に一つずつ潰す
   - GObject関連(`defineEnum`/`defineBoxed`)は、呼び出し元がGTK
     ビルド時にしか使われない生成コードなので、switchのその分岐を
     削って`none`だけの単純な形にする
   - `OpenGL.zig`のGTK向けGLコンテキスト処理は削除
   - `SharedDeps.zig`のGTKリンクロジックを削除
3. `src/apprt/gtk/`ディレクトリを削除
4. `build.zig` / `src/build/Config.zig`のGTK固有オプション
   (`-Dgtk-x11`, `-Dgtk-x11`関連の依存解決など)を整理
5. `build.zig.zon`の`gtk4_layer_shell`等GTK専用の`pkg/`依存を
   `lazy = true`のまま残すか、合わせて消すか判断
6. `zig build` / `zig build test`をCIで確認、赤くなった箇所を直す
   のを繰り返す
7. `AGENTS.md`の「Directory Structure」からGTKの記述は既に削除済み
   （別PRで対応済み）

上記1〜7は全てPR #14（2026-08-10マージ）で実施済み。詳細・追加対応は
冒頭の「実施状況」を参照。
