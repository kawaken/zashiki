# ウィンドウ上部の見た目を切り替える設定を廃止する

Issue #239

## 目的

ウィンドウ上部（タイトルバー・タブバー）の見た目や配置を切り替える設定を廃止し、既定値の
挙動に固定する。#208 でタブバーとパネルの配置を変える前に、考慮する組み合わせを減らす。

## 対象と固定する挙動

| 設定 | 固定する挙動 | 既定値以外のための実装 |
| --- | --- | --- |
| `macos-titlebar-style` | `transparent` | `tabs` 用のウィンドウクラス2つ（約1,050行）、`hidden` 用1つ（約120行）、xib 3〜4つ |
| `window-decoration` | タイトルバーあり | タイトルバーなしの分岐（nib 選択、`styleMask`、新規タブ時の警告ダイアログ） |
| `macos-non-native-fullscreen` | macOS 標準のフルスクリーン | `toggle_fullscreen` で独自フルスクリーンを選ぶ分岐 |
| `macos-window-buttons` | 表示 | 信号機ボタンを隠す処理 |
| `macos-titlebar-proxy-icon` | 表示 | アイコンを隠す分岐 |

いずれも設定ファイルでは使われていない（XDG と Application Support の両方を確認済み）。

## 調査で分かったこと

### `macos-non-native-fullscreen` を消しても、独自フルスクリーンの実装は残る

独自フルスクリーン（`NonNativeFullscreen` 系クラス）は、この設定以外からも使われている。

- Quick Terminal は設定に関係なく常に独自フルスクリーンを使う。
- `fullscreen` 設定（起動時にフルスクリーンにする）が `non-native`・
  `non-native-visible-menu`・`non-native-padded-notch` の値を持つ。
- ウィンドウ復元が、保存されていたフルスクリーンの種類を復元する。

設定キーを消すだけでは、通常のウィンドウが `fullscreen = non-native` 経由で独自
フルスクリーンになる経路が残る。#208 の目的（通常のウィンドウで考える組み合わせを減らす）
には、`fullscreen` の値も `false` / `true` に絞る必要がある。クラス自体は Quick Terminal
のために残す。

### `toggle_window_decorations` は macOS では未実装

キーバインド用のアクションとして定義だけあり、macOS 側は何もしない。`window-decoration`
と一緒に消せる。

### `native` スタイルのクラスは残る

`TerminalWindow` は `transparent` 用クラスの基底なので残る。`native` 用の `Terminal.xib` は
タイトルバーなしの場合の既定 nib としても使われており、消せるかは実装時に確認する。
`TerminalWindow` と `TransparentTitlebarTerminalWindow` の統合は行わない。

### 設定キーを消すと、そのキーを書いた設定ファイルは警告になる

未知のキーは起動時の設定エラーウィンドウに "unknown field" と表示される。起動はできる。
`docs/history/remove-linux-only-config.md` と同じ扱いにし、互換用の読み飛ばしは入れない。
リリース時に CHANGELOG へ廃止した設定を記載する。

## 実装

設定ごとにコミットを分け、1つの PR にまとめる。

1. `macos-titlebar-style`
   - `Config.zig` のキーと `MacTitlebarStyle`、Swift 側の `macosTitlebarStyle` と型を削除。
   - `TerminalController` の nib 選択を `TerminalTransparentTitlebar` 固定にする。
   - `TitlebarTabsTahoeTerminalWindow`・`TitlebarTabsVenturaTerminalWindow`・
     `HiddenTitlebarTerminalWindow` と対応する xib を削除。これらのクラスを前提にした分岐
     （`TerminalController`、`SurfaceScrollView`、`TerminalView` の `ignoresSafeArea`）を整理。
   - `ZashikiTitlebarTabsUITests` を削除。`ZashikiWindowPositionUITests`・`ZashikiThemeTests`・
     `ConfigTests` から該当スタイルのケースを外す。
2. `window-decoration`
   - キーと `WindowDecoration`（パース処理とテストを含む）、Swift 側の `windowDecorations` を削除。
   - タイトルバーなしの分岐を削除。`toggle_window_decorations` アクションも削除。
   - `fullscreen` のドキュメントにある `window-decoration` への言及を削除。
3. `macos-non-native-fullscreen` と `fullscreen` の値
   - キーと `NonNativeFullscreen`（設定用 enum）を削除し、`toggle_fullscreen` は常に標準の
     フルスクリーンにする。
   - `fullscreen` を `false` / `true` のみにする。
   - 独自フルスクリーンのクラスと Quick Terminal の挙動は変えない。
4. `macos-window-buttons`、`macos-titlebar-proxy-icon`
   - キーと型、隠す処理を削除。

## レビューで決めたいこと

- `fullscreen` の値を `false` / `true` に絞ってよいか。Issue に挙げた5つの設定には
  含まれていないが、絞らないと通常のウィンドウが独自フルスクリーンになる経路が残る。

## 検証

- `just lint`、`just test-fast`、`just test`（macOS XCTest を含む）
- 実機確認（PR に `needs-verification` を付ける）
  - 既定の設定で、ウィンドウ・タブバー・タイトルの見た目が変更前と同じ
  - フルスクリーンの出入り、タブの追加・切り替え、ウィンドウ復元
  - Quick Terminal の表示とフルスクリーン
