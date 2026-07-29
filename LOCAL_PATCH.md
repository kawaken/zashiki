# フォーク運用メモ（独自ターミナル開発）

このリポジトリは ghostty-org/ghostty のフォークで、**main が独自開発ライン**。
upstream の tip をベースに、独自パッチ（下記の ATOK 対応など）を積んでいく。
upstream への PR は作らない。upstream の変更（脆弱性・不具合修正）には
マージで追随する（「upstream への追随手順」参照）。

経緯: 最初は `atok-preedit` ブランチで「リリースタグ + パッチ + rebase」の
運用だったが、独自開発に方針転換し 2026-07-29 に main へ fast-forward
マージした。`atok-preedit` ブランチは記録として温存（今後は更新しない）。

## パッチ内容

**macos: render IME clause underlines in preedit**

ATOK 等の IME が変換中テキスト（preedit）に付与する文節ごとの下線属性を
描画に反映する。注目文節（変換対象の文節）は太め下線、それ以外は通常の一本下線。

変更ファイル（追加中心・既存 API のシグネチャ変更なし。upstream マージ時の
競合を最小化する方針）:

| ファイル | 変更 |
| --- | --- |
| `macos/.../SurfaceView_AppKit.swift` | `validAttributesForMarkedText` で `underlineStyle` を受理。太下線範囲をコードポイント単位のスタイル配列にして送信 |
| `include/ghostty.h` | `ghostty_surface_preedit_styled` を追加 |
| `src/apprt/embedded.zig` | 上記 C API の実装（既存 `ghostty_surface_preedit` は温存） |
| `src/Surface.zig` | `preeditStyledCallback` を追加。既存 `preeditCallback` は委譲のみ |
| `src/renderer/State.zig` | `Preedit.Codepoint` に `emphasized: bool` を追加 |
| `src/font/sprite.zig` | `underline_thick` スプライトを追加 |
| `src/font/sprite/draw/special.zig` | `underline_thick` の描画関数を追加（通常下線の約1.6倍の太さ、隙間なし1本線） |
| `src/renderer/generic.zig` | `addUnderlineSprite` を追加（`terminal.Attribute.Underline` を経由せず直接スプライト指定）。`emphasized` なセルは `underline_thick` で描画 |

スタイル値の意味: コードポイントごとに 1 バイト。`2` 以上 = 注目文節、それ以外 = 通常。

## 別マシンでの初回セットアップ

```sh
# 1. clone（デフォルトブランチの main で作業する）
git clone https://github.com/kawaken/ghostty.git
cd ghostty

# 2. upstream 追随用にリモートを追加
git remote add upstream https://github.com/ghostty-org/ghostty.git

# 3. Zig を Homebrew で導入
brew install zig

# 4. Xcode の準備（下記「ビルド環境」参照）
sudo xcode-select --switch /Applications/Xcode.app
```

## ビルド環境

- **Xcode 26**（macOS 26 SDK / iOS SDK / Metal Toolchain 含む）が必須
  - iOS SDK は `zig build` のビルドグラフ生成時に参照されるため、
    Command Line Tools だけでは `zig build test` すら動かない
  - 初回: `sudo xcode-select --switch /Applications/Xcode.app` を実行し、
    Xcode を一度起動してコンポーネントをインストールする
- **Zig**: Homebrew の `zig`（無印、PATH に入る）。2026-07-28 時点で
  `0.16.0`。リリースごとに `build.zig.zon` の `minimum_zig_version` を
  確認し、`zig version` と合わなければ `brew upgrade zig` する
  - 以前は keg-only の `zig@0.15` を PATH プレフィックス付きで使っていたが、
    upstream が `minimum_zig_version = 0.16.0` に上げたタイミングで
    無印 `zig`（0.16.0）に切り替え済み

## ビルド手順

```sh
zig build -Doptimize=ReleaseFast -Dxcframework-target=native
```

- 成果物: `zig-out/Ghostty.app`（実体は `macos/build/ReleaseLocal/Ghostty.app`）

## 端末へのリリース（/Applications の正規版をパッチ版に差し替える）

### 事前準備（初回のみ）

Ghostty の設定ファイル（`~/.config/ghostty/config` など）に以下を追加する:

```
auto-update = off
```

**これをやらないと Sparkle の自動アップデートが公式ビルドで上書きして
パッチが消える。** upstream への追随は本メモのマージ手順で手動で行う。

### 差し替え手順

```sh
# 1. Ghostty を完全終了（Cmd+Q）。以降は Terminal.app 等の別ターミナルで実行
#    （Ghostty 内で実行するとコピー中に自分のセッションが死ぬ）

# 2. 差し替え
rm -rf /Applications/Ghostty.app
cp -R zig-out/Ghostty.app /Applications/

# 3. 起動して動作確認（下記「動作確認」参照）
```

補足:

- ローカルビルドは ad-hoc 署名になるため、公式ビルド（Developer ID 署名）
  から差し替えた直後は、システム設定で Ghostty に与えていた権限
  （フルディスクアクセス等）が再要求されることがある
- 設定ファイルや履歴はアプリバンドルの外（`~/.config/ghostty` 等）に
  あるので差し替えで消えない
- 公式ビルドに戻したい場合は https://ghostty.org/download から
  dmg を落として同じ手順で上書きすればよい

## 動作確認

ATOK で日本語を入力し、スペースで変換 → 変換中に注目文節だけ太め下線、
他の文節が通常の一本下線になっていれば OK。

## upstream への追随手順（マージ方式）

独自コミットを積んでいくため、rebase ではなく **upstream をマージで
取り込む**。履歴は汚れるが、自分のコミットのハッシュが変わらず、
何をどこで取り込んだかが履歴に残る。

取り込む単位は 2 択:

- **安定タグ（`vX.Y.Z`）**: 基本はこちら。リリースされた品質のものだけ入る
- **`upstream/main`（tip）**: 未リリースの修正がすぐ欲しいときだけ

```sh
# 1. main で作業していることを確認
git switch main

# 2. upstream の最新を取得
git fetch upstream --tags

# 3. マージ（安定タグの例。tip なら upstream/main を指定）
git merge v1.4.0

# 4. 競合したら解決してコミット（下記「競合解決の指針」参照）

# 5. Zig バージョン確認（合わなければ brew upgrade zig）
grep minimum_zig_version build.zig.zon
zig version

# 6. ビルドして動作確認
zig build -Doptimize=ReleaseFast -Dxcframework-target=native

# 7. 「端末へのリリース」の差し替え手順で /Applications を更新

# 8. push
git push origin main
```

### 競合解決の指針

- 独自パッチは追加中心なので競合は起きにくい。起きた場合は
  上の変更ファイル表を参考に、upstream 側の変更を活かしつつ
  独自部分を当て直す
- upstream 側で preedit 周りが変わっていたら（特に `syncPreedit` /
  `preeditCallback` / `addPreeditCell`）、同じ方針で実装し直す
- 解決に迷ったら `git merge --abort` で一旦戻し、upstream 側の
  変更内容を確認してからやり直す
