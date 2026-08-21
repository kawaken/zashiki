# i18n (gettext) の削除と、将来の日本語UI対応の方針

## 背景

Zashikiには上流Ghostty由来のgettextベースのi18n機構が丸ごと残っている
（`po/` に33言語、`pkg/libintl`、`src/os/i18n.zig`、`src/build/GhosttyI18n.zig`）。
しかし調査の結果、**これは既に機能として死んでいる**:

- 翻訳を引く唯一の口はC API `ghostty_translate()`（`src/main_c.zig:170`）
- そのC APIをmacOSのSwift側から呼んでいる箇所は **0件**
- `macos/` に `.lproj` も `NSLocalizedString` も `String(localized:)` も **0件**
- つまり毎ビルド `msgfmt` で33言語の `.mo` を生成し、`Zashiki.app/Contents/Resources/
  share/locale/` に同梱しているが、**誰も読んでいない**
- 生成される `.mo` のドメインは `com.mitchellh.ghostty` のままでリブランドも漏れている

元々GTK版UIの文字列を翻訳するための仕組みで、GTK apprtを削除した時点
（`docs/history/remove-gtk-apprt.md`）で用済みになっていた。

## 決定事項

1. **gettextベースのi18nは丸ごと削除する。** 将来UIを日本語化したくなった場合も
   gettextは復活させない
2. **将来の日本語UI対応はmacOSネイティブの仕組みで行う。** Swiftの
   `String(localized:)` + String Catalog (`.xcstrings`) を使う。理由:
   - 翻訳対象は実質 `macos/Sources/` のSwift UI文字列だけ（メニュー、設定画面、
     アラート）。Zig側のコアはユーザー向け文字列をほぼ持たない
   - Xcodeが翻訳漏れを検出でき、`msgfmt` のような外部ツールへのビルド依存が消える
   - libghostty境界をまたいで文字列を渡す必要がなくなる
3. **今回は日本語化そのものは行わない。** 削除だけ行い、日本語化は必要になった時点で
   別タスクとして着手する

## 削除対象

| 対象 | 備考 |
|---|---|
| `po/` 全体 | 33の `.po` + `com.mitchellh.ghostty.pot` + README 2本 |
| `pkg/libintl` | Apple環境にlibintlが無いためバンドルしていたLGPLライブラリ |
| `src/os/i18n.zig` / `src/os/i18n_locales.zig` | 本体 |
| `src/build/GhosttyI18n.zig` | `msgfmt` を叩く `.mo` 生成ステップ |
| `src/main_c.zig` の `ghostty_translate` | + `include/ghostty.h:1035` の宣言 |
| `src/global.zig:217-219` | `i18n.init()` 呼び出し |
| `build.zig` の `i18n` 変数と `translations` step | 6箇所程度 |
| `src/build/Config.zig` の `-Di18n` オプション | + `src/build_config.zig:44` |
| `src/build/SharedDeps.zig` のlibintlブロック | Darwin向けブロック内 |
| `macos/Ghostty.xcodeproj` の `share/locale` 参照 | `project.pbxproj:78` |

## 注意点

**`canonicalizeLocale()` は `src/os/i18n.zig` にあるが、`src/os/locale.zig:200` から
呼ばれており、こちらはmacOSのロケール設定に必要なので消してはいけない。**

ただし `canonicalizeLocale` には既に `if (comptime !build_config.i18n)` の分岐があり
（`i18n.zig:92`）、i18n無効時は「文字列をバッファにコピーするだけ」に退化する。
したがって削除時は、この関数まるごとではなく **i18n無効時の分岐の中身を
`locale.zig` 側に直接インライン展開する** のが正しい。`fixZhLocale` もi18n有効時
専用なので一緒に消える。

## 検証

- `zig build -Demit-macos-app=false` が通る
- `zig build test` が通る
- `zig build` でmacOSアプリがビルドでき、`Zashiki.app/Contents/Resources/share/locale`
  が消えていること
- アプリを起動してメニュー・設定画面の英語表示が変わっていないこと
