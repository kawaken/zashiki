# ローカルパッチ運用メモ（atok-preedit ブランチ）

このブランチは **リリースタグ + ローカルパッチ** で運用する個人ビルド用ブランチ。
upstream への PR は作らない。

## パッチ内容

**macos: render IME clause underlines in preedit**

ATOK 等の IME が変換中テキスト（preedit）に付与する文節ごとの下線属性を
描画に反映する。注目文節（変換対象の文節）は二重下線、それ以外は一本下線。

変更ファイル（追加中心・既存 API のシグネチャ変更なし。リベース時の競合を
最小化する方針）:

| ファイル | 変更 |
| --- | --- |
| `macos/.../SurfaceView_AppKit.swift` | `validAttributesForMarkedText` で `underlineStyle` を受理。太下線範囲をコードポイント単位のスタイル配列にして送信 |
| `include/ghostty.h` | `ghostty_surface_preedit_styled` を追加 |
| `src/apprt/embedded.zig` | 上記 C API の実装（既存 `ghostty_surface_preedit` は温存） |
| `src/Surface.zig` | `preeditStyledCallback` を追加。既存 `preeditCallback` は委譲のみ |
| `src/renderer/State.zig` | `Preedit.Codepoint` に `emphasized: bool` を追加 |
| `src/renderer/generic.zig` | `emphasized` なセルは `.double` 下線で描画 |

スタイル値の意味: コードポイントごとに 1 バイト。`2` 以上 = 注目文節、それ以外 = 通常。

## ビルド環境

- **Xcode 26**（macOS 26 SDK / iOS SDK / Metal Toolchain 含む）が必須
  - iOS SDK は `zig build` のビルドグラフ生成時に参照されるため、
    Command Line Tools だけでは `zig build test` すら動かない
  - 初回: `sudo xcode-select --switch /Applications/Xcode.app` を実行し、
    Xcode を一度起動してコンポーネントをインストールする
- **Zig**: Homebrew の `zig@0.15`（keg-only）。リリースごとに
  `build.zig.zon` の `minimum_zig_version` を確認し、合わなければ
  `brew install zig@0.<N>` で追加する

## ビルド手順

```sh
PATH="/opt/homebrew/opt/zig@0.15/bin:$PATH" zig build -Doptimize=ReleaseFast -Dxcframework-target=native
```

- 成果物: `zig-out/Ghostty.app`（実体は `macos/build/ReleaseLocal/Ghostty.app`）
- インストール: Ghostty を終了してから `/Applications` へコピー

```sh
cp -R zig-out/Ghostty.app /Applications/
```

## 動作確認

ATOK で日本語を入力し、スペースで変換 → 変換中に注目文節だけ二重下線、
他の文節が一本下線になっていれば OK。

## 新リリースへの追随手順

```sh
# 1. 現在のベースタグを確認（例: v1.3.1）
git describe --tags --abbrev=0 atok-preedit

# 2. 新しいタグを取得
git fetch upstream --tags

# 3. パッチを新タグへ載せ替え（<old> は手順1の結果）
git rebase --onto <new-tag> <old-tag> atok-preedit

# 4. Zig バージョン確認（brew の zig@ と一致しているか）
grep minimum_zig_version build.zig.zon

# 5. ビルドして入れ替え
PATH="/opt/homebrew/opt/zig@0.15/bin:$PATH" zig build -Doptimize=ReleaseFast -Dxcframework-target=native
cp -R zig-out/Ghostty.app /Applications/
```

リベースで競合した場合は、上の変更ファイル表を参考に該当箇所を手で解決する。
upstream 側で preedit 周りが変わっていたら（特に `syncPreedit` /
`preeditCallback` / `addPreeditCell`）、同じ方針で当て直す。
