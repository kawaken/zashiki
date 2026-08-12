# GTK apprtの削除

- **実施PR**: [#14](https://github.com/kawaken/zashiki/pull/14)（2026-08-10マージ）
- **元プラン**: `plan/remove-gtk-apprt.md`（削除済み、このドキュメントに統合）

## 目的

`src/apprt/gtk/`（Linux/FreeBSD向けGTKアプリランタイム、約1.1MB）を含む、
GTK関連コードをソースツリーから削除した。個人用macOSフォークにLinux対応は
不要という方針に基づく。

## Planとの差分

Planでは`.gtk`を参照する14ファイルの書き換えで完結すると見積もっていたが、
実際にはビルドスクリプト側に想定していなかった依存が多数あり、追加対応が
必要だった:

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

また、Planでは`gtk-single-instance`・`gtk-titlebar-style`・`class`・
`show_gtk_inspector`などのGTK名の付いた**設定/キーバインドAPI自体**は
「クロスプラットフォームな設定ファイル互換性のためのno-op」として意図的に
残す方針だったが、実装完了後に方針を再考し、個人用・macOS専用フォークで
クロスプラットフォームを目指すものではないという理由で、これらも追加で
削除した:

- `class`/`x11-instance-name`/`gtk-*`系の設定フィールドと対応する型
  （`GtkSingleInstance`等）・compatリネームエントリ・関連テストを
  `Config.zig`から削除
- キーバインドアクション`show_gtk_inspector`を関連ファイル一式から削除
- `+new-window`/`+toggle-quick-terminal`CLIサブコマンド（GTKのD-Bus IPC
  でしか実装されておらず、このフォークでは常に失敗していた）を
  `apprt/ipc.zig`一式ごと削除

## 関連コミット

- `0d178578b` GTK apprtを削除
- `22bbb787a` GTK専用の設定/キーバインド/CLI IPC APIを削除
- `6ff92b3f7` Merge pull request #14
- `090bc54f0` docs/ci: plan/remove-gtk-apprt.mdの矛盾を修正 (#17)
