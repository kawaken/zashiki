# gettextベースのi18nの削除

- **元プラン**: `plan/i18n-removal.md`（削除済み、このドキュメントに統合）

## 目的

上流Ghostty由来のgettext i18n機構（`po/`の33言語、`pkg/libintl`、
`src/os/i18n.zig`、`src/build/GhosttyI18n.zig`）を削除した。

削除の根拠は「使っていないから」ではなく「既に機能として死んでいたから」:

- 翻訳を引く唯一の口は C API `ghostty_translate()`
- そのC APIをmacOSのSwift側から呼んでいる箇所は0件
- `macos/` に `.lproj` も `NSLocalizedString` も `String(localized:)` も0件
- 毎ビルド `msgfmt` で33言語の `.mo` を生成し
  `Zashiki.app/Contents/Resources/share/locale/` に同梱していたが、
  誰も読んでいなかった。ドメイン名も `com.mitchellh.ghostty` のまま

元々GTK版UIの文字列を翻訳するための仕組みで、GTK apprtを削除した時点
（`docs/history/remove-gtk-apprt.md`）で用済みになっていた。

## Planとの差分

Planでは `canonicalizeLocale()` について「i18n無効時の分岐の中身を
`locale.zig` 側にインライン展開するのが正しい」と書いていたが、実際には
**その通りにすると挙動が悪化する**ことが分かったので方針を変えた。

`canonicalizeLocale()` は、macOSがBCP-47形式（`ja-JP`, `zh-Hans-CN`）で
返す優先言語をPOSIXロケール形式（`ja_JP`, `zh_CN`）に変換して環境変数
`LANGUAGE` にセットするために使われている。`LANGUAGE` はアプリ自身の翻訳
だけでなく、**ターミナルの子プロセスにも継承される**ので、シェル上の
gettext対応CLIツール（GNU coreutils等）が読む。

i18n無効時の分岐は「バッファにそのままコピーするだけ」なので、これを
そのまま採用すると `LANGUAGE=ja-JP:en-US` のようなBCP-47形式が子プロセスに
漏れ、POSIX形式を期待するgettextが解釈できなくなる。

そこで `src/os/locale.zig` に、libintlに依存しない最小の変換を実装した:

1. `fixZhLocale` はそのまま移設（`zh-Hans-CN` → `zh_CN` 等、
   スクリプトサブタグを地域に畳み込む特殊ケース）
2. それ以外は BCP-47 の区切り `-` を POSIX の `_` に置換

`sr-Latn-RS` のような zh 以外でスクリプトサブタグを持つタグは
`sr_Latn_RS` になり厳密には正しくないが、libintl無しでの単純コピーよりは
良く、実用上ほぼ発生しない。ユニットテスト `test canonicalizeLocale` を
追加してある。

## 将来の日本語UI対応

gettextは復活させない。必要になったらSwiftの `String(localized:)` +
String Catalog（`.xcstrings`）を使う。理由:

- 翻訳対象は実質 `macos/Sources/` のSwift UI文字列だけ
- Xcodeが翻訳漏れを検出でき、`msgfmt` への外部ビルド依存が消える
- libghostty境界をまたいで文字列を渡す必要がなくなる
